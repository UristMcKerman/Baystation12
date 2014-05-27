
#define THERMAL_RELEASE_MODIFIER 20000		//Higher == more heat released during reaction
#define SUPERMATTER_POWER_LOSS_RATE 0.0005
#define REPAIR_TEMPERATURE_BOUND T0C+100
#define STEFAN_BOLTZMANN_CONSTANT 0.0000000567
#define RADIATION_OUTPUT_KOEFFICIENT 0.5
#define RADIATION_ORGANIC_KOEFFICIENT 0.1

//These would be what you would get at point blank, decreases with distance
#define DETONATION_RADS 200
#define DETONATION_HALLUCINATION 600


#define WARNING_DELAY 30 		//seconds between warnings.

/obj/machinery/power/supermatter
	name = "Supermatter"
	desc = "A strangely translucent and iridescent crystal. \red You get headaches just from looking at it."
	icon = 'icons/obj/engine.dmi'
	icon_state = "darkmatter"
	density = 1
	anchored = 0
	luminosity = 4

	var/base_icon_state = "darkmatter"

	var/inner_temperature = 293
	var/inner_heatcapacity = 1000000	//With power==500 the temperature will increase by 10. ~6 minutes to warm up to melting point
	var/inner_conductivity = 0.5 		//Should not exceed 1
	var/surface = 0.5					//Used in black-body heat radiation

	var/casing_melting = 3600	//Somewhere near tungsten melting point. Referred as T_cm in comment below
	var/damage_buildup = 50		//How much damage will casing get for every T_cm above T_cm

	var/damage = 0
	var/damage_archived = 0
	var/warning_point = 0
	var/warning_alert = "Danger! Crystal casing is melting! Structure is unstable!"
	var/emergency_point = 700
	var/emergency_alert = "CRYSTAL DELAMINATION IMMINENT."
	var/explosion_point = 1000

	var/emergency_issued = 0

	var/explosion_power = 8

	var/lastwarning = 0                        // Time in 1/10th of seconds since the last sent warning
	var/power = 0

	var/oxygen = 0				  // Moving this up here for easier debugging.

	//Temporary values so that we can optimize this
	//How much the bullets damage should be multiplied by when it is added to the internal variables
	var/config_bullet_energy = 1
	//How much hallucination should it produce per unit of power?
	var/config_hallucination_power = 0.1

	var/obj/item/device/radio/radio

	shard //Small subtype, less efficient and more sensitive, but less boom.
		name = "Supermatter Shard"
		desc = "A strangely translucent and iridescent crystal that looks like it used to be part of a larger structure. \red You get headaches just from looking at it."
		icon_state = "darkmatter_shard"
		base_icon_state = "darkmatter_shard"

		warning_point = 0
		emergency_point = 300
		explosion_point = 500	//Two times less tough

		surface = 0.125						//Used in black-body heat radiation
		inner_heatcapacity = 200 * 12500	//Capacity of 12500 moles of toxins, or 150kg; enough for superdense crystal shard.
		inner_conductivity = 0.3 			//Should not exceed 1
		damage_buildup = 10					//Two times faster

		explosion_power = 3 //3,6,9,12? Or is that too small?


/obj/machinery/power/supermatter/New()
	. = ..()
	radio = new (src)


/obj/machinery/power/supermatter/Del()
	del radio
	. = ..()

/obj/machinery/power/supermatter/proc/explode()
	for(var/mob/living/mob in living_mob_list)
		if(istype(mob, /mob/living/carbon/human))
			//Hilariously enough, running into a closet should make you get hit the hardest.
			mob:hallucination += max(50, min(300, DETONATION_HALLUCINATION * sqrt(1 / (get_dist(mob, src) + 1)) ) )
		var/rads = DETONATION_RADS * sqrt( 1 / (get_dist(mob, src) + 1) )
		mob.apply_effect(rads, IRRADIATE)

	explosion(get_turf(src), explosion_power, explosion_power * 2, explosion_power * 3, explosion_power * 4, 1)
	del src
	return

/obj/machinery/power/supermatter/proc/calc_stability()
	return num2text(round((1 - damage / explosion_point) * 100))

/obj/machinery/power/supermatter/process()
	inner_temperature += THERMAL_RELEASE_MODIFIER * power / inner_heatcapacity
	if (inner_temperature > casing_melting)
		damage += (inner_temperature / casing_melting - 1) * damage_buildup

	if(damage > warning_point) // while the core is still damaged and it's still worth noting its status
		if((world.timeofday - lastwarning) / 10 >= WARNING_DELAY)
			var/stability = calc_stability()
			if(damage > emergency_point)
				radio.autosay(addtext(emergency_alert, " Casing status: ",stability,"%"), "Supermatter Monitor")
				lastwarning = world.timeofday

			else if(damage > damage_archived) // The damage is still going up
				radio.autosay(addtext(warning_alert," Casing status: ",stability,"%"), "Supermatter Monitor")
				lastwarning = world.timeofday - 150
				damage_archived = damage

		if(damage > explosion_point)
			explode()
			return

	transfer_energy()
	power *= (1.0 - SUPERMATTER_POWER_LOSS_RATE)

	apply_bad_effects()

	var/turf/L = loc

	if(!istype(L)) 	//We are in a crate or somewhere that isn't turf, if we return to turf resume processing but for now.
		return  //Yeah just stop.

	if(istype(L, /turf/space))
		radiate_heat()
		return

	var/datum/gas_mixture/env = L.return_air()
	var/datum/gas_mixture/removed = env.remove(env.total_moles)

	if (removed)
		var/air_heatcapacity = removed.heat_capacity()
		var/temp_heatcapacity = air_heatcapacity*inner_heatcapacity/(air_heatcapacity+inner_heatcapacity)
		var/heat = (inner_temperature - removed.temperature) * inner_conductivity * temp_heatcapacity
		inner_temperature -= heat / inner_heatcapacity
		removed.temperature += (heat / max(1, removed.heat_capacity()))
		removed.temperature = max(0, min(removed.temperature, 1000000))
		removed.update_values()

		env.merge(removed)

	return 1


/obj/machinery/power/supermatter/bullet_act(var/obj/item/projectile/Proj)
	if(Proj.flag != "bullet")
		power += Proj.damage * config_bullet_energy
	else
		damage += Proj.damage * config_bullet_energy
	return 0


/obj/machinery/power/supermatter/attack_paw(mob/user as mob)
	return attack_hand(user)


/obj/machinery/power/supermatter/attack_robot(mob/user as mob)
	if(Adjacent(user))
		return attack_hand(user)
	else
		var/stability = calc_stability()
		user << "<span class = \"warning\">Supermatter monitor data:<br> Crystal temperature: [inner_temperature]<br> Casing integrity: [stability]</span>"
	return

/obj/machinery/power/supermatter/attack_ai(mob/user as mob)
		var/stability = calc_stability()
		user << "<span class = \"warning\">Supermatter monitor data:<br> Crystal temperature: [inner_temperature]<br> Casing integrity: [stability]</span>"

/obj/machinery/power/supermatter/attack_hand(mob/user as mob)
	user.visible_message("<span class=\"warning\">\The [user] reaches out and touches \the [src], inducing a resonance... \his body starts to glow and bursts into flames before flashing into ash.</span>",\
		"<span class=\"danger\">You reach out and touch \the [src]. Everything starts burning and all you can hear is ringing. Your last thought is \"That was not a wise decision.\"</span>",\
		"<span class=\"warning\">You hear an uneartly ringing, then what sounds like a shrilling kettle as you are washed with a wave of heat.</span>")
	Consume(user)

/obj/machinery/power/supermatter/proc/transfer_energy()
	for(var/obj/machinery/power/rad_collector/R in rad_collectors)
		if(get_dist(R, src) <= 15) // Better than using orange() every process
			R.receive_pulse(power * RADIATION_OUTPUT_KOEFFICIENT)
			//TODO: Radiation collectors will collect full radiation even through walls. Should be discussed.
	return

/obj/machinery/power/supermatter/proc/apply_bad_effects()
	for(var/mob/living/carbon/human/l in view(src, 7)) // If they can see it without mesons on.  Bad on them.
		if(!istype(l.glasses, /obj/item/clothing/glasses/meson))
			l.hallucination = max(0, min(200, l.hallucination + power * config_hallucination_power * sqrt( 1 / max(1,get_dist(l, src)) ) ) )

	var/rad_dist = (power * RADIATION_ORGANIC_KOEFFICIENT) ** 0.5
	for(var/mob/living/l in view(src, rad_dist))
		var/rads = (power * RADIATION_ORGANIC_KOEFFICIENT) * (1 / get_dist(l, src))**2
		l.apply_effect(rads, IRRADIATE)

/obj/machinery/power/supermatter/proc/radiate_heat()
	var/heat = STEFAN_BOLTZMANN_CONSTANT * surface * inner_temperature ** 4
	inner_temperature = max(0, inner_temperature - heat / inner_heatcapacity)

/obj/machinery/power/supermatter/attackby(obj/item/weapon/W as obj, mob/living/user as mob)
	if (istype(W,/obj/item/device/analyzer))
		var/stability = calc_stability()
		user << "[W.icon]\blue You analyze supermatter core status:<br> Crystal temperature: [inner_temperature]<br> Casing integrity: [stability]"
		return
	else if (istype(W,/obj/item/stack/nanopaste) && damage > 0 && inner_temperature <= REPAIR_TEMPERATURE_BOUND)
		user << "\blue You fix core casing with nanopaste. Now it looks better."
		var/obj/item/stack/nanopaste/NP = W
		NP.use(1)
		damage = max(0, damage - 100)
		return

	user.visible_message("<span class=\"warning\">\The [user] touches \a [W] to \the [src] as a silence fills the room...</span>",\
		"<span class=\"danger\">You touch \the [W] to \the [src] when everything suddenly goes silent.\"</span>\n<span class=\"notice\">\The [W] flashes into dust as you flinch away from \the [src].</span>",\
		"<span class=\"warning\">Everything suddenly goes silent.</span>")

	user.drop_from_inventory(W)
	Consume(W)

	user.apply_effect(150, IRRADIATE)


/obj/machinery/power/supermatter/Bumped(atom/AM as mob|obj)
	if(istype(AM, /mob/living))
		AM.visible_message("<span class=\"warning\">\The [AM] slams into \the [src] inducing a resonance... \his body starts to glow and catch flame before flashing into ash.</span>",\
		"<span class=\"danger\">You slam into \the [src] as your ears are filled with unearthly ringing. Your last thought is \"Oh, fuck.\"</span>",\
		"<span class=\"warning\">You hear an uneartly ringing, then what sounds like a shrilling kettle as you are washed with a wave of heat.</span>")
	else
		AM.visible_message("<span class=\"warning\">\The [AM] smacks into \the [src] and rapidly flashes to ash.</span>",\
		"<span class=\"warning\">You hear a loud crack as you are washed with a wave of heat.</span>")

	Consume(AM)


/obj/machinery/power/supermatter/proc/Consume(var/mob/living/user)
	if(istype(user))
		user.dust()
		power += 200
	else
		del user

	power += 200

		//Some poor sod got eaten, go ahead and irradiate people nearby.
	for(var/mob/living/l in range(10))
		if(l in view())
			l.show_message("<span class=\"warning\">As \the [src] slowly stops resonating, you find your skin covered in new radiation burns.</span>", 1,\
				"<span class=\"warning\">The unearthly ringing subsides and you notice you have new radiation burns.</span>", 2)
		else
			l.show_message("<span class=\"warning\">You hear an uneartly ringing and notice your skin is covered in fresh radiation burns.</span>", 2)
		var/rads = 500 * sqrt( 1 / (get_dist(l, src) + 1) )
		l.apply_effect(rads, IRRADIATE)