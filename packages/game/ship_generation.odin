package game

generate_ship :: proc(
	seed: u64,
	config: Ship_Generator_Config,
	goals: Fleet_Goals = {
		survival = 60,
		exploration = 45,
		settlement = 45,
		industry = 50,
		preservation = 40,
		security = 40,
	},
) -> Ship {
	trait_state := ship_generator_stream(seed, 0x9e3779b97f4a7c15)
	mass_state := ship_generator_stream(seed, 0xbf58476d1ce4e5b9)
	power_state := ship_generator_stream(seed, 0x94d049bb133111eb)
	crew_state := ship_generator_stream(seed, 0xd2b74407b1ce6e93)
	role := config.role
	if !config.role_locked do role = ship_role_from_goals(seed, goals)
	hull_class := config.hull_class
	if hull_class == .Unspecified do hull_class = .Fleet_Ship
	id := config.id
	if id == 0 do id = 1
	community := config.community
	if community == 0 do community = 1
	capability_percent := config.capability_percent
	if capability_percent == 0 do capability_percent = 100
	crew_percent := config.crew_percent
	if crew_percent == 0 do crew_percent = 100
	mass_percent := config.mass_percent
	if mass_percent == 0 do mass_percent = 100
	name := config.name
	if name == "" do name = ship_generator_name(seed, id)
	trait := config.trait
	if !config.trait_locked {
		traits := GENERATED_SHIP_TRAITS
		trait = traits[int(fleet_generator_next(&trait_state) % u64(len(traits)))]
	}
	construction_seed := ship_construction_identity_seed(seed, id)
	hull_archetype := config.hull_archetype
	if hull_archetype == .Unspecified do hull_archetype = ship_hull_archetype_from_role(construction_seed, role, hull_class)
	operational_role := config.operational_role
	if operational_role == .Unspecified || !ship_operational_role_fits_hull(operational_role, hull_archetype) do operational_role = ship_operational_role_for_hull(construction_seed, role, hull_archetype)
	return {
		id = id,
		name = name,
		construction_seed = construction_seed,
		bow_profile = u8(ship_construction_visual_mix(construction_seed ~ 0x9216d5d98979fb1b) % 3 + 1),
		utility_hardpoint = u8(ship_construction_visual_mix(construction_seed ~ 0xd1310ba698dfb5ac) % 9 + 1),
		wing_sweep = u8(ship_construction_visual_mix(construction_seed ~ 0x6a09e667f3bcc909) % 3 + 1),
		wing_stance = u8(ship_construction_visual_mix(construction_seed ~ 0x13198a2e03707344) % 3 + 1),
		keel_profile = u8(ship_construction_visual_mix(construction_seed ~ 0x082efa98ec4e6c89) % 3 + 1),
		mission_profile = u8(ship_construction_visual_mix(construction_seed ~ 0x510e527fade682d1) % 3 + 1),
		drive_layout = u8(ship_construction_visual_mix(construction_seed ~ 0x3f84d5b5b5470917) % 3 + 1),
		drive_setback = u8(ship_construction_visual_mix(construction_seed ~ 0xbb67ae8584caa73b) % 3 + 1),
		role = role,
		hull_class = hull_class,
		hull_archetype = hull_archetype,
		operational_role = operational_role,
		weapon_package = ship_weapon_package_for(id, hull_archetype, operational_role),
		defense_packages = ship_defense_packages_for(id, hull_archetype, operational_role),
		mass_tonnes = generate_ship_archetype_mass(&mass_state, role, hull_archetype, mass_percent),
		power = scaled_ship_value(ship_hull_class_power(role, hull_class), capability_percent, config.variation_percent, &power_state),
		crew = scaled_ship_value(ship_hull_class_crew(role, hull_class), crew_percent, config.variation_percent, &crew_state),
		community = community,
		active = true,
		passage_trait = trait,
		semantic_tags = semantic_tags_for_ship(role),
	}
}
