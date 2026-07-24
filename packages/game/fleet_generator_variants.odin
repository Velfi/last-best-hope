package game

// generate_fleet produces a self-sufficient expeditionary fleet. The first
// four hulls guarantee food, habitation, medicine, and repair capacity. The
// remaining hulls follow the supplied goals with diminishing returns, which
// prevents a single priority from producing an implausible monoculture.
generate_fleet :: proc(seed: u64, goals: Fleet_Goals, prefix: string) -> [MAX_SHIPS]Ship {
	assert(
		prefix != "" && ship_name_prefix_is_valid(prefix),
		"generated fleets require a valid ship prefix",
	)
	state := seed
	if state == 0 do state = 1
	roles: [MAX_SHIPS]Role
	roles[0] = .Habitat
	roles[1] = .Agriculture
	roles[2] = .Hospital
	roles[3] = .Foundry
	used := 4
	for used < MAX_SHIPS {
		best_role := Role.Habitat
		best_score := i32(-1)
		for role_value in 0 ..< 8 {
			role := Role(role_value)
			count := fleet_role_count(&roles, used, role)
			if count >= 4 do continue
			// Each duplicate reduces the role's marginal value by 30% of its
			// initial score; a small seeded term resolves otherwise equal plans.
			base := fleet_role_score(role, goals) + 100
			score := base * 10 / i32(10 + count * 3) + i32(fleet_generator_next(&state) % 17)
			if score > best_score {best_score = score; best_role = role}
		}
		roles[used] = best_role
		used += 1
	}
	fleet_shuffle_roles(seed, &roles)
	hull_classes := fleet_hull_classes(seed, roles)

	ships: [MAX_SHIPS]Ship
	// Names belong to stable hull identities, not the current fleet priorities:
	// changing doctrine may change a hull's role but must not rename the ship.
	names := fleet_identity_ship_names(seed, prefix)
	trait_counts: [5]int
	family_counts: [6]int
	hardpoint_counts: [9]int
	wing_stance_counts: [3]int
	wing_sweep_counts: [3]int
	keel_profile_counts: [3]int
	drive_layout_counts: [3]int
	drive_setback_counts: [3]int
	structural_profile_counts: [27]int
	trait_state := ship_generator_stream(seed, 0x3f84d5b5b5470917)
	capability_state := ship_generator_stream(seed, 0xbb67ae8584caa73b)
	construction_state := ship_generator_stream(seed, 0x1f83d9abfb41bd6b)
	communities := fleet_community_assignments(seed, roles)
	for role, i in roles {
		config := default_ship_generator_config(i)
		config.role = role
		config.role_locked = true
		config.variation_percent = 10
		config.trait = fleet_trait_for_role(&trait_state, role, &trait_counts)
		config.trait_locked = true
		trait_counts[int(config.trait) - 1] += 1
		config.community = communities[i]
		config.hull_class = hull_classes[i]
		simulation_seed := fleet_generator_next(&capability_state)
		config.hull_archetype = ship_hull_archetype_for_ordinary_roster(
			simulation_seed,
			role,
			config.hull_class,
		)
		config.operational_role = ship_operational_role_for_ordinary_roster(
			simulation_seed,
			role,
			config.hull_archetype,
		)
		config.name = names[i]
		base_ship := generate_ship(simulation_seed, config, goals)
		// A repeated yard-family pair implies shared provenance. Reserve that visual
		// language for factual construction siblings, then prefer candidates using
		// underrepresented families so one campaign cannot become visually monochrome.
		best_candidate: Ship
		best_score := int(1 << 30)
		found_candidate := false
		for _ in 0 ..< 96 {
			identity_seed := fleet_generator_next(&construction_state)
			candidate := ship_with_construction_identity(base_ship, identity_seed)
			family_fingerprint := ship_construction_family_fingerprint(candidate)
			visual_fingerprint := ship_construction_visual_fingerprint(candidate)
			duplicate := false
			for prior in ships[:i] {
				if ship_construction_family_fingerprint(prior) == family_fingerprint ||
				   ship_construction_visual_fingerprint(prior) ==
					   visual_fingerprint {duplicate = true; break}
			}
			if duplicate do continue
			primary, accent := ship_construction_family_pair(candidate)
			hardpoint := ship_construction_utility_hardpoint(candidate)
			wing_stance := ship_construction_wing_stance(candidate)
			wing_sweep := ship_construction_wing_sweep(candidate)
			keel_profile := ship_construction_keel_profile(candidate)
			drive_layout := ship_construction_drive_layout(candidate)
			drive_setback := ship_construction_drive_setback(candidate)
			structural_profile := ship_construction_structural_profile(candidate)
			score :=
				(family_counts[primary] + family_counts[accent]) * 24 +
				max(family_counts[primary], family_counts[accent]) +
				hardpoint_counts[hardpoint] * 16 +
				wing_stance_counts[wing_stance] * 16 +
				wing_sweep_counts[wing_sweep] * 64 +
				keel_profile_counts[keel_profile] * 16 +
				drive_layout_counts[drive_layout] * 16 +
				drive_setback_counts[drive_setback] * 16 +
				structural_profile_counts[structural_profile] * 64
			if !found_candidate || score < best_score {
				best_candidate = candidate
				best_score = score
				found_candidate = true
			}
		}
		if !found_candidate {
			for _ in 0 ..< 256 {
				identity_seed := fleet_generator_next(&construction_state)
				candidate := ship_with_construction_identity(base_ship, identity_seed)
				family_fingerprint := ship_construction_family_fingerprint(candidate)
				visual_fingerprint := ship_construction_visual_fingerprint(candidate)
				duplicate := false
				for prior in ships[:i] {
					if ship_construction_family_fingerprint(prior) == family_fingerprint ||
					   ship_construction_visual_fingerprint(prior) ==
						   visual_fingerprint {duplicate = true; break}
				}
				if !duplicate {best_candidate = candidate; found_candidate = true; break}
			}
		}
		ships[i] = best_candidate
		primary, accent := ship_construction_family_pair(best_candidate)
		family_counts[primary] += 1
		family_counts[accent] += 1
		hardpoint_counts[ship_construction_utility_hardpoint(best_candidate)] += 1
		wing_stance_counts[ship_construction_wing_stance(best_candidate)] += 1
		wing_sweep_counts[ship_construction_wing_sweep(best_candidate)] += 1
		keel_profile_counts[ship_construction_keel_profile(best_candidate)] += 1
		drive_layout_counts[ship_construction_drive_layout(best_candidate)] += 1
		drive_setback_counts[ship_construction_drive_setback(best_candidate)] += 1
		structural_profile_counts[ship_construction_structural_profile(best_candidate)] += 1
	}
	hardpoints := fleet_utility_hardpoints(seed, ships)
	for &ship, i in ships do ship.utility_hardpoint = hardpoints[i]
	wing_stances := fleet_wing_stances(seed, ships)
	for &ship, i in ships do ship.wing_stance = wing_stances[i]
	wing_sweeps := fleet_wing_sweeps(seed, ships)
	for &ship, i in ships do ship.wing_sweep = wing_sweeps[i]
	drive_layouts := fleet_drive_layouts(seed, ships)
	for &ship, i in ships do ship.drive_layout = drive_layouts[i]
	keel_profiles := fleet_keel_profiles(seed, ships)
	for &ship, i in ships do ship.keel_profile = keel_profiles[i]
	drive_setbacks := fleet_drive_setbacks(seed, ships)
	for &ship, i in ships do ship.drive_setback = drive_setbacks[i]
	bow_profiles := fleet_bow_profiles(seed, ships)
	for &ship, i in ships do ship.bow_profile = bow_profiles[i]
	mission_profiles := fleet_mission_profiles(seed, ships)
	for &ship, i in ships do ship.mission_profile = mission_profiles[i]
	return ships
}

