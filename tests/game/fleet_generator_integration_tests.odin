package game_tests

import "core:testing"

@(test)
generated_fleet_is_deterministic_and_self_sufficient :: proc(t: ^testing.T) {
	a := generate_fleet(8128, balanced_fleet_goals(), "FCS")
	b := generate_fleet(8128, balanced_fleet_goals(), "FCS")
	for ship, i in a {
		testing.expect_value(t, ship.name, b[i].name)
		testing.expect_value(t, ship.role, b[i].role)
		testing.expect_value(t, ship.hull_class, b[i].hull_class)
		testing.expect_value(t, ship.community, b[i].community)
		testing.expect_value(t, ship.passage_trait, b[i].passage_trait)
		testing.expect_value(t, ship.mass_tonnes, b[i].mass_tonnes)
		testing.expect_value(t, ship.power, b[i].power)
		testing.expect_value(t, ship.crew, b[i].crew)
	}
	required_roles := [4]Role{.Habitat, .Agriculture, .Hospital, .Foundry}
	for required in required_roles {
		found := false
		for ship in a do if ship.role == required do found = true
		testing.expect(t, found)
	}
}

@(test)
generated_fleets_have_unique_persistent_construction_recipes :: proc(t: ^testing.T) {
	profiles := [3]Fleet_Goals{balanced_fleet_goals(), {exploration = 100}, {settlement = 100}}
	for goals in profiles {
		for seed in 1 ..= 256 {
			fleet := generate_fleet(u64(seed), goals, "FCS")
			base_family_counts: [6]int
			base_hardpoint_counts: [9]int
			base_wing_stance_counts: [3]int
			base_wing_sweep_counts: [3]int
			base_keel_profile_counts: [3]int
			base_drive_layout_counts: [3]int
			base_drive_setback_counts: [3]int
			base_mission_profile_counts: [3]int
			base_bow_profile_counts: [3]int
			base_structural_profiles: [27]bool
			for ship, i in fleet {
				primary, accent := ship_construction_family_pair(ship)
				base_family_counts[primary] += 1
				base_family_counts[accent] += 1
				base_hardpoint_counts[ship_construction_utility_hardpoint(ship)] += 1
				base_wing_stance_counts[ship_construction_wing_stance(ship)] += 1
				base_wing_sweep_counts[ship_construction_wing_sweep(ship)] += 1
				base_keel_profile_counts[ship_construction_keel_profile(ship)] += 1
				base_drive_layout_counts[ship_construction_drive_layout(ship)] += 1
				base_drive_setback_counts[ship_construction_drive_setback(ship)] += 1
				base_mission_profile_counts[ship_construction_mission_profile(ship)] += 1
				base_bow_profile_counts[ship_construction_bow_profile(ship)] += 1
				base_structural_profiles[ship_construction_structural_profile(ship)] = true
				fingerprint := ship_construction_visual_fingerprint(ship)
				for prior in fleet[:i] {
					testing.expect(t, ship_construction_visual_fingerprint(prior) != fingerprint)
					testing.expect(
						t,
						ship_construction_family_fingerprint(prior) !=
						ship_construction_family_fingerprint(ship),
					)
				}
			}
			for count in base_family_counts do testing.expect(t, count >= 3 && count <= 5)
			for count in base_hardpoint_counts do testing.expect(t, count >= 1 && count <= 2)
			base_hardpoints: [MAX_SHIPS]u8
			for ship, i in fleet do base_hardpoints[i] = u8(ship_construction_utility_hardpoint(ship) + 1)
			testing.expect_value(
				t,
				fleet_utility_hardpoint_collision_score(fleet, base_hardpoints),
				0,
			)
			for count in base_wing_stance_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			base_wing_stances: [MAX_SHIPS]u8
			for ship, i in fleet do base_wing_stances[i] = u8(ship_construction_wing_stance(ship) + 1)
			testing.expect_value(
				t,
				fleet_mission_profile_collision_score(fleet, base_wing_stances),
				fleet_mission_profile_optimal_score(fleet),
			)
			for count in base_wing_sweep_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			base_wing_sweeps: [MAX_SHIPS]u8
			for ship, i in fleet do base_wing_sweeps[i] = u8(ship_construction_wing_sweep(ship) + 1)
			testing.expect_value(
				t,
				fleet_mission_profile_collision_score(fleet, base_wing_sweeps),
				fleet_mission_profile_optimal_score(fleet),
			)
			for count in base_keel_profile_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			for count in base_drive_layout_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			base_drive_layouts: [MAX_SHIPS]u8
			for ship, i in fleet do base_drive_layouts[i] = u8(ship_construction_drive_layout(ship) + 1)
			testing.expect_value(
				t,
				fleet_mission_profile_collision_score(fleet, base_drive_layouts),
				fleet_mission_profile_optimal_score(fleet),
			)
			for count in base_drive_setback_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			base_drive_setbacks: [MAX_SHIPS]u8
			for ship, i in fleet do base_drive_setbacks[i] = u8(ship_construction_drive_setback(ship) + 1)
			testing.expect_value(
				t,
				fleet_mission_profile_collision_score(fleet, base_drive_setbacks),
				fleet_mission_profile_optimal_score(fleet),
			)
			for count in base_mission_profile_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			base_mission_profiles: [MAX_SHIPS]u8
			for ship, i in fleet do base_mission_profiles[i] = u8(ship_construction_mission_profile(ship) + 1)
			testing.expect_value(
				t,
				fleet_mission_profile_collision_score(fleet, base_mission_profiles),
				fleet_mission_profile_optimal_score(fleet),
			)
			for count in base_bow_profile_counts do testing.expect(t, count >= 3 && count <= 5)
			for count in base_bow_profile_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			base_aligned, base_optimal := fleet_bow_doctrine_alignment(fleet[:])
			testing.expect_value(t, base_aligned, base_optimal)
			base_structural_profile_count := 0
			for present in base_structural_profiles do if present do base_structural_profile_count += 1
			testing.expect_value(t, base_structural_profile_count, MAX_SHIPS)
			campaign: Campaign
			campaign_init(&campaign, u64(seed))
			apply_generated_fleet(&campaign, goals, "FCS")
			lineage_family_counts: [6]int
			lineage_hardpoint_counts: [9]int
			lineage_wing_stance_counts: [3]int
			lineage_wing_sweep_counts: [3]int
			lineage_keel_profile_counts: [3]int
			lineage_drive_layout_counts: [3]int
			lineage_drive_setback_counts: [3]int
			lineage_mission_profile_counts: [3]int
			lineage_bow_profile_counts: [3]int
			lineage_structural_profiles: [27]bool
			for ship, i in campaign.ships[:campaign.ship_count] {
				primary, accent := ship_construction_family_pair(ship)
				lineage_family_counts[primary] += 1
				lineage_family_counts[accent] += 1
				lineage_hardpoint_counts[ship_construction_utility_hardpoint(ship)] += 1
				lineage_wing_stance_counts[ship_construction_wing_stance(ship)] += 1
				lineage_wing_sweep_counts[ship_construction_wing_sweep(ship)] += 1
				lineage_keel_profile_counts[ship_construction_keel_profile(ship)] += 1
				lineage_drive_layout_counts[ship_construction_drive_layout(ship)] += 1
				lineage_drive_setback_counts[ship_construction_drive_setback(ship)] += 1
				lineage_mission_profile_counts[ship_construction_mission_profile(ship)] += 1
				lineage_bow_profile_counts[ship_construction_bow_profile(ship)] += 1
				lineage_structural_profiles[ship_construction_structural_profile(ship)] = true
				fingerprint := ship_construction_visual_fingerprint(ship)
				for prior in campaign.ships[:i] {
					testing.expect(t, ship_construction_visual_fingerprint(prior) != fingerprint)
					relationship := ship_relationship_index(&campaign, prior.id, ship.id)
					siblings :=
						relationship >= 0 &&
						campaign.ship_relationships[relationship].kind == .Construction_Siblings
					same_family :=
						ship_construction_family_fingerprint(prior) ==
						ship_construction_family_fingerprint(ship)
					testing.expect_value(t, same_family, siblings)
				}
			}
			for count in lineage_family_counts do testing.expect(t, count >= 3 && count <= 5)
			for count in lineage_hardpoint_counts do testing.expect(t, count >= 1 && count <= 2)
			lineage_hardpoints: [MAX_SHIPS]u8
			for ship, i in campaign.ships do lineage_hardpoints[i] = u8(ship_construction_utility_hardpoint(ship) + 1)
			testing.expect_value(
				t,
				fleet_utility_hardpoint_collision_score(campaign.ships, lineage_hardpoints),
				0,
			)
			for count in lineage_wing_stance_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			lineage_wing_stances: [MAX_SHIPS]u8
			for ship, i in campaign.ships do lineage_wing_stances[i] = u8(ship_construction_wing_stance(ship) + 1)
			testing.expect_value(
				t,
				fleet_mission_profile_collision_score(campaign.ships, lineage_wing_stances),
				fleet_mission_profile_optimal_score(campaign.ships),
			)
			for count in lineage_wing_sweep_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			for count in lineage_keel_profile_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			for count in lineage_drive_layout_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			lineage_drive_layouts: [MAX_SHIPS]u8
			for ship, i in campaign.ships do lineage_drive_layouts[i] = u8(ship_construction_drive_layout(ship) + 1)
			testing.expect_value(
				t,
				fleet_mission_profile_collision_score(campaign.ships, lineage_drive_layouts),
				fleet_mission_profile_optimal_score(campaign.ships),
			)
			for count in lineage_drive_setback_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			lineage_drive_setbacks: [MAX_SHIPS]u8
			for ship, i in campaign.ships do lineage_drive_setbacks[i] = u8(ship_construction_drive_setback(ship) + 1)
			testing.expect_value(
				t,
				fleet_mission_profile_collision_score(campaign.ships, lineage_drive_setbacks),
				fleet_mission_profile_optimal_score(campaign.ships),
			)
			for count in lineage_mission_profile_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			for count in lineage_bow_profile_counts do testing.expect(t, count >= 3 && count <= 5)
			for count in lineage_bow_profile_counts do testing.expect_value(t, count, MAX_SHIPS / 3)
			lineage_aligned, lineage_optimal := fleet_bow_doctrine_alignment(
				campaign.ships[:campaign.ship_count],
			)
			testing.expect_value(t, lineage_aligned, lineage_optimal)
			coherent_lineages := 0
			coherent_sweeps := 0
			for relationship in campaign.ship_relationships[:campaign.ship_relationship_count] {
				first_at := ship_index(&campaign, relationship.ship_a)
				second_at := ship_index(&campaign, relationship.ship_b)
				if first_at < 0 || second_at < 0 do continue
				if ship_construction_bow_profile(campaign.ships[first_at]) == ship_construction_bow_profile(campaign.ships[second_at]) do coherent_lineages += 1
				if ship_construction_wing_sweep(campaign.ships[first_at]) == ship_construction_wing_sweep(campaign.ships[second_at]) do coherent_sweeps += 1
			}
			testing.expect(t, coherent_lineages >= 2)
			testing.expect(t, coherent_sweeps >= 2)
			lineage_structural_profile_count := 0
			for present in lineage_structural_profiles do if present do lineage_structural_profile_count += 1
			testing.expect_value(t, lineage_structural_profile_count, MAX_SHIPS)
		}
	}
}

@(test)
generated_roster_shuffle_preserves_composition_but_varies_identity_slots :: proc(t: ^testing.T) {
	roles := [MAX_SHIPS]Role {
		.Habitat,
		.Agriculture,
		.Hospital,
		.Foundry,
		.Survey,
		.Survey,
		.Archive,
		.Escort,
		.Colony,
		.Foundry,
		.Hospital,
		.Habitat,
	}
	a, b, c := roles, roles, roles
	fleet_shuffle_roles(991, &a)
	fleet_shuffle_roles(991, &b)
	fleet_shuffle_roles(992, &c)
	testing.expect_value(t, a, b)
	before_counts, after_counts: [8]int
	different := 0
	for role, i in roles {
		before_counts[int(role)] += 1
		after_counts[int(a[i])] += 1
		if a[i] != c[i] do different += 1
	}
	testing.expect_value(t, before_counts, after_counts)
	testing.expect(t, different >= 6)
}

@(test)
essential_roles_move_across_ship_id_space_between_campaigns :: proc(t: ^testing.T) {
	essentials := [4]Role{.Habitat, .Agriculture, .Hospital, .Foundry}
	seen_positions: [4][MAX_SHIPS]bool
	legacy_prefixes := 0
	for seed in 1 ..= 256 {
		fleet := generate_fleet(u64(seed), balanced_fleet_goals(), "FCS")
		if fleet[0].role == .Habitat && fleet[1].role == .Agriculture && fleet[2].role == .Hospital && fleet[3].role == .Foundry do legacy_prefixes += 1
		for essential, essential_index in essentials do for ship, position in fleet do if ship.role == essential do seen_positions[essential_index][position] = true
	}
	for positions in seen_positions {
		seen := 0
		for present in positions do if present do seen += 1
		testing.expect(t, seen >= 10)
	}
	testing.expect(t, legacy_prefixes <= 2)
}

@(test)
generated_fleets_cover_every_trait_without_personality_clumping :: proc(t: ^testing.T) {
	profiles := [7]Fleet_Goals {
		balanced_fleet_goals(),
		{survival = 100},
		{exploration = 100},
		{settlement = 100},
		{industry = 100},
		{preservation = 100},
		{security = 100},
	}
	favored, total := 0, 0
	for goals in profiles {
		for seed in 1 ..= 128 {
			fleet := generate_fleet(u64(seed), goals, "FCS")
			counts: [5]int
			for ship in fleet {
				testing.expect(t, ship.passage_trait != .None)
				index := int(ship.passage_trait) - 1
				testing.expect(t, index >= 0 && index < len(counts))
				if index >= 0 && index < len(counts) do counts[index] += 1
				if fleet_trait_role_weight(ship.role, ship.passage_trait) > 20 do favored += 1
				total += 1
			}
			for count in counts do testing.expect(t, count >= 1 && count <= 3)
		}
	}
	testing.expect(t, favored * 100 / total >= 45)

	a := generate_fleet(3001, balanced_fleet_goals(), "FCS")
	b := generate_fleet(3002, balanced_fleet_goals(), "FCS")
	different := 0
	for ship, i in a do if ship.passage_trait != b[i].passage_trait do different += 1
	testing.expect(t, different >= 6)
}

@(test)
generated_fleet_ship_names_are_unique_across_seeds :: proc(t: ^testing.T) {
	seen_names: [SHIP_NAME_CANDIDATE_COUNT]bool
	for seed in 1 ..= 128 {
		fleet := generate_fleet(u64(seed), balanced_fleet_goals(), "FCS")
		for ship, i in fleet {
			testing.expect(t, ship.name != "")
			testing.expect(t, ship_name_is_valid(ship.name))
			in_pool := false
			for name_index in 0 ..< SHIP_NAME_CANDIDATE_COUNT {
				candidate, _ := ship_name_candidate(name_index)
				if ship.name ==
				   ship_name_with_prefix(
					   candidate,
					   "FCS",
				   ) {in_pool = true; seen_names[name_index] = true; break}
			}
			testing.expect(t, in_pool)
			for prior in 0 ..< i do testing.expect(t, ship.name != fleet[prior].name)
		}
	}
	seen_count := 0
	for seen in seen_names do if seen do seen_count += 1
	testing.expect(t, seen_count >= 350)
}

@(test)
generated_fleet_names_change_materially_between_campaign_seeds :: proc(t: ^testing.T) {
	a := generate_fleet(4001, balanced_fleet_goals(), "FCS")
	b := generate_fleet(4002, balanced_fleet_goals(), "FCS")
	different := 0
	for ship, i in a do if ship.name != b[i].name do different += 1
	testing.expect(t, different >= 8)
}

@(test)
neighboring_campaigns_have_low_roster_name_overlap :: proc(t: ^testing.T) {
	overlap_total := 0
	max_overlap := 0
	for seed in 1 ..= 128 {
		first := generate_fleet(u64(seed), balanced_fleet_goals(), "FCS")
		second := generate_fleet(u64(seed + 1), balanced_fleet_goals(), "FCS")
		overlap := 0
		for a in first do for b in second do if a.name == b.name do overlap += 1
		overlap_total += overlap
		max_overlap = max(max_overlap, overlap)
	}
	// The format-driven space is large enough that neighboring campaigns should
	// usually share no names and only rarely share one.
	testing.expect(t, max_overlap <= 3)
	testing.expect(t, overlap_total <= 80)
}

@(test)
neighboring_campaigns_have_low_complete_construction_overlap :: proc(t: ^testing.T) {
	total_overlap := 0
	max_overlap := 0
	same_registry_slot := 0
	for seed in 1 ..= 128 {
		first: Campaign
		campaign_init(&first, u64(seed))
		second: Campaign
		campaign_init(&second, u64(seed + 1))
		apply_generated_fleet(&first, balanced_fleet_goals(), "FCS")
		apply_generated_fleet(&second, balanced_fleet_goals(), "FCS")
		overlap := 0
		for a, i in first.ships[:first.ship_count] {
			fingerprint := ship_construction_recipe_fingerprint(a)
			if fingerprint == ship_construction_recipe_fingerprint(second.ships[i]) do same_registry_slot += 1
			for b in second.ships[:second.ship_count] do if fingerprint == ship_construction_recipe_fingerprint(b) do overlap += 1
		}
		total_overlap += overlap
		max_overlap = max(max_overlap, overlap)
	}
	// A complete recipe occupies a very large construction space. These bounds
	// catch correlated seed streams while allowing rare legitimate collisions.
	testing.expect(t, max_overlap <= 2)
	testing.expect(t, total_overlap <= 24)
	testing.expect(t, same_registry_slot <= 4)
}

@(test)
generated_campaigns_do_not_repeat_complete_name_rosters :: proc(t: ^testing.T) {
	rosters: [128][MAX_SHIPS]string
	for seed in 1 ..= 128 {
		rosters[seed - 1] = fleet_identity_ship_names(u64(seed), "FCS")
		for prior in 0 ..< (seed - 1) {
			shared := 0
			for first in rosters[seed - 1] do for second in rosters[prior] do if first == second do shared += 1
			testing.expect(t, shared < MAX_SHIPS)
		}
	}
}


@(test)
fleet_priorities_do_not_reroll_stable_ship_identity :: proc(t: ^testing.T) {
	exploration := generate_fleet(711, {exploration = 100}, "FCS")
	settlement := generate_fleet(711, {settlement = 100}, "FCS")
	for ship, i in exploration {
		testing.expect_value(t, ship.name, settlement[i].name)
		testing.expect_value(t, ship.construction_seed, settlement[i].construction_seed)
	}
}

@(test)
generated_fleets_use_multiple_role_authentic_hull_classes :: proc(t: ^testing.T) {
	aggregate_seen: [5]bool
	for seed in 1 ..= 32 {
		fleet := generate_fleet(u64(seed), balanced_fleet_goals(), "FCS")
		fleet_seen: [5]bool
		class_count := 0
		for ship in fleet {
			index := int(ship.hull_class) - 1
			testing.expect(t, index >= 0 && index < len(fleet_seen))
			if !fleet_seen[index] {fleet_seen[index] = true; class_count += 1}
			aggregate_seen[index] = true
		}
		testing.expect(t, class_count >= 3)
	}
	for present in aggregate_seen do testing.expect(t, present)
}

@(test)
generated_fleets_avoid_role_and_scale_clumping_across_goal_space :: proc(t: ^testing.T) {
	profiles := [7]Fleet_Goals {
		balanced_fleet_goals(),
		{survival = 100},
		{exploration = 100},
		{settlement = 100},
		{industry = 100},
		{preservation = 100},
		{security = 100},
	}
	for goals in profiles {
		for seed in 1 ..= 256 {
			fleet := generate_fleet(u64(seed), goals, "FCS")
			role_counts: [8]int
			class_counts: [5]int
			for ship in fleet {
				role_counts[int(ship.role)] += 1
				class_index := int(ship.hull_class) - 1
				testing.expect(t, class_index >= 0 && class_index < len(class_counts))
				if class_index >= 0 && class_index < len(class_counts) {
					class_counts[class_index] += 1
					testing.expect(t, fleet_hull_role_weight(ship.role, ship.hull_class) > 0)
				}
			}
			class_kinds := 0
			for count in class_counts {
				if count > 0 do class_kinds += 1
				testing.expect(t, count <= 6)
			}
			for count in role_counts do testing.expect(t, count <= 4)
			testing.expect_value(
				t,
				class_kinds,
				fleet_hull_class_coverage_capacity(
					{
						fleet[0].role,
						fleet[1].role,
						fleet[2].role,
						fleet[3].role,
						fleet[4].role,
						fleet[5].role,
						fleet[6].role,
						fleet[7].role,
						fleet[8].role,
						fleet[9].role,
						fleet[10].role,
						fleet[11].role,
					},
				),
			)
		}
	}
}

@(test)
generated_fleets_balance_community_representation_and_spread_duties :: proc(t: ^testing.T) {
	profiles := [3]Fleet_Goals{balanced_fleet_goals(), {exploration = 100}, {settlement = 100}}
	for goals in profiles {
		for seed in 1 ..= 256 {
			fleet := generate_fleet(u64(seed), goals, "FCS")
			community_counts: [INITIAL_COMMUNITIES]int
			community_roles: [INITIAL_COMMUNITIES][8]int
			for ship in fleet {
				community := int(ship.community) - 1
				testing.expect(t, community >= 0 && community < INITIAL_COMMUNITIES)
				if community >= 0 && community < INITIAL_COMMUNITIES {
					community_counts[community] += 1
					community_roles[community][int(ship.role)] += 1
				}
			}
			for count in community_counts do testing.expect_value(t, count, MAX_SHIPS / INITIAL_COMMUNITIES)
			for roles in community_roles do for count in roles do testing.expect(t, count <= 1)
		}
	}

	a := generate_fleet(100, balanced_fleet_goals(), "FCS")
	b := generate_fleet(101, balanced_fleet_goals(), "FCS")
	different := 0
	for ship, i in a do if ship.community != b[i].community do different += 1
	testing.expect(t, different >= 6)
}

@(test)
fleet_goals_materially_change_composition :: proc(t: ^testing.T) {
	explorers := generate_fleet(55, {exploration = 100}, "FCS")
	settlers := generate_fleet(55, {settlement = 100}, "FCS")
	exploration_hulls, settlement_hulls := 0, 0
	for ship in explorers do if ship.role == .Survey || ship.role == .Archive do exploration_hulls += 1
	for ship in settlers do if ship.role == .Colony || ship.role == .Habitat do settlement_hulls += 1
	testing.expect(t, exploration_hulls >= 3)
	testing.expect(t, settlement_hulls >= 3)
}

@(test)
applying_a_generated_fleet_does_not_consume_campaign_rng :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 77)
	sequence := c.rng_sequence
	state := c.rng_state
	apply_generated_fleet(&c, {survival = 80, security = 60}, "FCS")
	testing.expect_value(t, c.rng_sequence, sequence)
	testing.expect_value(t, c.rng_state, state)
}

@(test)
applied_generated_fleet_is_immediately_tagged_and_saveable :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 991)
	apply_generated_fleet(&c, balanced_fleet_goals(), "FCS")
	for ship in c.ships[:c.ship_count] {
		testing.expect(t, ship.semantic_tags != Semantic_Tags(0))
		testing.expect(t, semantic_has(ship.semantic_tags, .Entity))
		testing.expect(t, semantic_has(ship.semantic_tags, .Ship))
	}
	data := campaign_serialize(&c)
	defer delete(data)
	restored: Campaign
	defer campaign_destroy(&restored)
	result := campaign_deserialize(data[:], &restored)
	testing.expect(t, result.ok)
	if result.ok {
		for ship, i in restored.ships[:restored.ship_count] {
			testing.expect_value(t, ship.name, c.ships[i].name)
			testing.expect_value(t, ship.construction_seed, c.ships[i].construction_seed)
			testing.expect_value(t, ship.construction_lineage, c.ships[i].construction_lineage)
			testing.expect_value(t, ship.bow_profile, c.ships[i].bow_profile)
			testing.expect_value(t, ship.utility_hardpoint, c.ships[i].utility_hardpoint)
			testing.expect_value(t, ship.wing_sweep, c.ships[i].wing_sweep)
			testing.expect_value(t, ship.wing_stance, c.ships[i].wing_stance)
			testing.expect_value(t, ship.keel_profile, c.ships[i].keel_profile)
			testing.expect_value(t, ship.mission_profile, c.ships[i].mission_profile)
			testing.expect_value(t, ship.drive_layout, c.ships[i].drive_layout)
			testing.expect_value(t, ship.drive_setback, c.ships[i].drive_setback)
			testing.expect_value(t, ship.hull_class, c.ships[i].hull_class)
			testing.expect_value(t, ship.semantic_tags, c.ships[i].semantic_tags)
		}
	}
}

@(test)
generated_fleets_begin_with_sparse_factual_construction_lineages :: proc(t: ^testing.T) {
	a, b: Campaign
	campaign_init(&a, 7331)
	campaign_init(&b, 7331)
	apply_generated_fleet(&a, balanced_fleet_goals(), "FCS")
	apply_generated_fleet(&b, balanced_fleet_goals(), "FCS")
	testing.expect_value(t, a.ship_relationship_count, 3)
	testing.expect_value(t, a.ship_relationship_count, b.ship_relationship_count)
	used: [MAX_SHIPS]bool
	lineages: [3]u64
	for relationship, i in a.ship_relationships[:a.ship_relationship_count] {
		testing.expect_value(t, relationship, b.ship_relationships[i])
		testing.expect_value(t, relationship.kind, Ship_Relationship_Kind.Construction_Siblings)
		testing.expect_value(t, relationship.strength, i32(0))
		testing.expect_value(t, relationship.shared_passages, i32(0))
		testing.expect(t, semantic_has(relationship.semantic_tags, .Identity))
		testing.expect(t, !semantic_has(relationship.semantic_tags, .Passage))
		first, second := ship_index(&a, relationship.ship_a), ship_index(&a, relationship.ship_b)
		testing.expect(t, first >= 0 && second >= 0)
		if first >= 0 && second >= 0 {
			testing.expect(t, !used[first] && !used[second])
			used[first], used[second] = true, true
			testing.expect_value(t, a.ships[first].hull_class, a.ships[second].hull_class)
			testing.expect(t, a.ships[first].construction_lineage != 0)
			testing.expect_value(
				t,
				a.ships[first].construction_lineage,
				a.ships[second].construction_lineage,
			)
			lineages[i] = a.ships[first].construction_lineage
			for prior in 0 ..< i do testing.expect(t, lineages[prior] != lineages[i])
			testing.expect(t, ship_bond_description(&a, relationship.ship_a) != "")
		}
	}
	for paired, i in used do if !paired do testing.expect_value(t, a.ships[i].construction_lineage, u64(0))
	all_ids: [MAX_SHIPS]Ship_ID
	for ship, i in a.ships do all_ids[i] = ship.id
	modifier, _, _, _ := ship_bond_modifier(&a, all_ids[:])
	testing.expect_value(t, modifier, i32(0))
}

@(test)
construction_siblings_earn_operational_bonds_only_through_shared_passages :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 8129)
	apply_generated_fleet(&c, balanced_fleet_goals(), "FCS")
	relationship := c.ship_relationships[0]
	pair := [2]Ship_ID{relationship.ship_a, relationship.ship_b}
	record_shared_passage_bonds(&c, pair[:], c.event_sequence)
	modifier, _, _, _ := ship_bond_modifier(&c, pair[:])
	testing.expect_value(t, modifier, i32(0))
	record_shared_passage_bonds(&c, pair[:], c.event_sequence)
	modifier, _, _, _ = ship_bond_modifier(&c, pair[:])
	testing.expect_value(t, modifier, i32(1))
	index := ship_relationship_index(&c, relationship.ship_a, relationship.ship_b)
	testing.expect(t, index >= 0)
	if index >= 0 {
		testing.expect_value(
			t,
			c.ship_relationships[index].kind,
			Ship_Relationship_Kind.Construction_Siblings,
		)
		testing.expect_value(t, c.ship_relationships[index].shared_passages, i32(2))
		testing.expect(t, semantic_has(c.ship_relationships[index].semantic_tags, .Identity))
		testing.expect(t, semantic_has(c.ship_relationships[index].semantic_tags, .Passage))
	}
}
