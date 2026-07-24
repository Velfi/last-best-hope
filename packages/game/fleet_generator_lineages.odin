package game

import "core:testing"
initialize_generated_ship_lineages :: proc(c: ^Campaign) {
	c.ship_relationship_count = 0
	used: [MAX_SHIPS]bool
	state := ship_generator_stream(c.initial_seed, 0x082efa98ec4e6c89)
	for _ in 0 ..< 3 {
		best_first, best_second := -1, -1
		best_score := i32(-1)
		for first in 0 ..< c.ship_count {
			if used[first] do continue
			for second in first + 1 ..< c.ship_count {
				if used[second] || c.ships[first].hull_class != c.ships[second].hull_class || ship_construction_utility_hardpoint(c.ships[first]) == ship_construction_utility_hardpoint(c.ships[second]) do continue
				score := i32(fleet_generator_next(&state) % 17)
				if c.ships[first].community != c.ships[second].community do score += 30
				if c.ships[first].role != c.ships[second].role do score += 20
				if ship_construction_keel_profile(c.ships[first]) == ship_construction_keel_profile(c.ships[second]) do score += 100
				if ship_construction_wing_stance(c.ships[first]) != ship_construction_wing_stance(c.ships[second]) do score += 40
				if ship_construction_drive_layout(c.ships[first]) != ship_construction_drive_layout(c.ships[second]) do score += 40
				if score >
				   best_score {best_score = score; best_first = first; best_second = second}
			}
		}
		if best_first < 0 do break
		used[best_first], used[best_second] = true, true
		a, b := c.ships[best_first].id, c.ships[best_second].id
		if a > b do a, b = b, a
		lineage_identity := c.initial_seed ~ (u64(a) << 32 | u64(b))
		lineage := u64(0)
		lineage_keel_profile := u8(1)
		lineage_state := ship_generator_stream(lineage_identity, 0x452821e638d01377)
		best_lineage_score := int(1 << 30)
		found_lineage := false
		for _ in 0 ..< 512 {
			candidate := fleet_generator_next(&lineage_state)
			first_ship, second_ship := c.ships[best_first], c.ships[best_second]
			first_ship.construction_lineage = candidate
			second_ship.construction_lineage = candidate
			candidate_keel := u8(
				ship_construction_visual_mix(candidate ~ 0x082efa98ec4e6c89) % 3 + 1,
			)
			first_ship.keel_profile = candidate_keel
			second_ship.keel_profile = candidate_keel
			first_fingerprint := ship_construction_visual_fingerprint(first_ship)
			second_fingerprint := ship_construction_visual_fingerprint(second_ship)
			family_fingerprint := ship_construction_family_fingerprint(first_ship)
			first_hardpoint := ship_construction_utility_hardpoint(first_ship)
			second_hardpoint := ship_construction_utility_hardpoint(second_ship)
			collision :=
				first_fingerprint == second_fingerprint || first_hardpoint == second_hardpoint
			if !collision {
				for ship, index in c.ships[:c.ship_count] {
					if index == best_first || index == best_second do continue
					fingerprint := ship_construction_visual_fingerprint(ship)
					if fingerprint == first_fingerprint ||
					   fingerprint == second_fingerprint ||
					   ship_construction_family_fingerprint(ship) ==
						   family_fingerprint {collision = true; break}
				}
			}
			if collision do continue
			counts: [6]int
			hardpoints: [9]int
			keel_profiles: [3]int
			structural_profiles: [27]int
			for ship, index in c.ships[:c.ship_count] {
				if index == best_first || index == best_second do continue
				primary, accent := ship_construction_family_pair(ship)
				counts[primary] += 1
				counts[accent] += 1
				hardpoints[ship_construction_utility_hardpoint(ship)] += 1
				keel_profiles[ship_construction_keel_profile(ship)] += 1
				structural_profiles[ship_construction_structural_profile(ship)] += 1
			}
			primary, accent := ship_construction_family_pair(first_ship)
			keel_profile := ship_construction_keel_profile(first_ship)
			first_profile := ship_construction_structural_profile(first_ship)
			second_profile := ship_construction_structural_profile(second_ship)
			resulting_profile_count := 0
			for count, profile in structural_profiles {
				if count > 0 || profile == first_profile || profile == second_profile do resulting_profile_count += 1
			}
			keel_imbalance := 0
			for count, profile in keel_profiles {
				resulting := count + (profile == keel_profile ? 2 : 0)
				keel_imbalance += abs(resulting - 4)
			}
			family_imbalance := 0
			for count, family in counts {
				resulting := count
				if family == primary || family == accent do resulting += 2
				family_imbalance += abs(resulting - 4)
			}
			score :=
				(counts[primary] + counts[accent]) * 36 +
				max(counts[primary], counts[accent]) +
				(hardpoints[first_hardpoint] + hardpoints[second_hardpoint]) * 36 +
				keel_profiles[keel_profile] * 192 +
				(structural_profiles[first_profile] + structural_profiles[second_profile]) * 64 +
				(27 - resulting_profile_count) * 10000 +
				keel_imbalance * 100000 +
				family_imbalance * 1000000
			if first_profile == second_profile do score += 256
			if !found_lineage || score < best_lineage_score {
				lineage = candidate
				lineage_keel_profile = candidate_keel
				best_lineage_score = score
				found_lineage = true
			}
		}
		c.ships[best_first].construction_lineage = lineage
		c.ships[best_second].construction_lineage = lineage
		c.ships[best_first].keel_profile = lineage_keel_profile
		c.ships[best_second].keel_profile = lineage_keel_profile
		c.ship_relationships[c.ship_relationship_count] = {
			ship_a        = a,
			ship_b        = b,
			kind          = .Construction_Siblings,
			semantic_tags = make_semantic_tags(.Relationship, .Ship, .Identity),
		}
		c.ship_relationship_count += 1
	}
}

fleet_lineage_family_balance_score :: proc(ships: []Ship) -> int {
	counts: [6]int
	for ship in ships {
		primary, accent := ship_construction_family_pair(ship)
		counts[primary] += 1
		counts[accent] += 1
	}
	violation, imbalance := 0, 0
	for count in counts {
		violation += max(3 - count, 0) + max(count - 5, 0)
		imbalance += abs(count - 4)
	}
	return violation * 1000 + imbalance
}

rebalance_generated_lineage_families :: proc(c: ^Campaign) {
	if fleet_lineage_family_balance_score(c.ships[:c.ship_count]) < 1000 do return
	for pass in 0 ..< 4 {
		changed := false
		for relationship in c.ship_relationships[:c.ship_relationship_count] {
			if relationship.kind != .Construction_Siblings do continue
			first := ship_index(c, relationship.ship_a)
			second := ship_index(c, relationship.ship_b)
			if first < 0 || second < 0 do continue
			original := c.ships[first].construction_lineage
			best_lineage := original
			best_score := fleet_lineage_family_balance_score(c.ships[:c.ship_count])
			state := ship_generator_stream(
				c.initial_seed ~
				u64(relationship.ship_a) << 32 ~
				u64(relationship.ship_b) ~
				u64(pass),
				0x9b05688c2b3e6c1f,
			)
			for _ in 0 ..< 1024 {
				candidate := fleet_generator_next(&state)
				first_ship, second_ship := c.ships[first], c.ships[second]
				first_ship.construction_lineage = candidate
				second_ship.construction_lineage = candidate
				first_visual := ship_construction_visual_fingerprint(first_ship)
				second_visual := ship_construction_visual_fingerprint(second_ship)
				family := ship_construction_family_fingerprint(first_ship)
				if first_visual == second_visual do continue
				collision := false
				for ship, index in c.ships[:c.ship_count] {
					if index == first || index == second do continue
					if ship_construction_family_fingerprint(ship) == family ||
					   ship_construction_visual_fingerprint(ship) == first_visual ||
					   ship_construction_visual_fingerprint(ship) ==
						   second_visual {collision = true; break}
				}
				if collision do continue
				c.ships[first].construction_lineage = candidate
				c.ships[second].construction_lineage = candidate
				score := fleet_lineage_family_balance_score(c.ships[:c.ship_count])
				c.ships[first].construction_lineage = original
				c.ships[second].construction_lineage = original
				if score < best_score {best_score = score; best_lineage = candidate}
			}
			if best_lineage != original {
				c.ships[first].construction_lineage = best_lineage
				c.ships[second].construction_lineage = best_lineage
				changed = true
				if fleet_lineage_family_balance_score(c.ships[:c.ship_count]) < 1000 do return
			}
		}
		if !changed do break
	}
}

// Keel is a shared lineage trait, so ordinary ship-by-ship balancing can split
// factual siblings. Enumerate the nine yard groups (three pairs plus six
// individuals), retain only exact 4/4/4 weighted assignments, then choose the
// one maximizing complete structural variety and repeated-role separation.
cohere_generated_lineage_keels :: proc(c: ^Campaign) {
	group_first, group_second: [MAX_SHIPS]int
	group_count := 0
	paired: [MAX_SHIPS]bool
	for relationship in c.ship_relationships[:c.ship_relationship_count] {
		if relationship.kind != .Construction_Siblings do continue
		first := ship_index(c, relationship.ship_a)
		second := ship_index(c, relationship.ship_b)
		if first < 0 || second < 0 do continue
		group_first[group_count], group_second[group_count] = first, second
		paired[first], paired[second] = true, true
		group_count += 1
	}
	for _, index in c.ships[:c.ship_count] do if !paired[index] {
		group_first[group_count], group_second[group_count] = index, -1
		group_count += 1
	}
	possibilities := 1
	for _ in 0 ..< group_count do possibilities *= 3
	best_code, best_score := 0, -1
	for code in 0 ..< possibilities {
		value := code
		assignment: [MAX_SHIPS]int
		counts: [3]int
		for group in 0 ..< group_count {
			profile := value % 3
			value /= 3
			assignment[group] = profile
			counts[profile] += group_second[group] >= 0 ? 2 : 1
		}
		if counts[0] != 4 || counts[1] != 4 || counts[2] != 4 do continue
		seen: [27]bool
		role_counts: [8][3]int
		changes := 0
		for group in 0 ..< group_count {
			profile := assignment[group]
			members := [2]int{group_first[group], group_second[group]}
			member_count := group_second[group] >= 0 ? 2 : 1
			for member in members[:member_count] {
				ship := c.ships[member]
				structural :=
					profile * 9 +
					ship_construction_wing_stance(ship) * 3 +
					ship_construction_drive_layout(ship)
				seen[structural] = true
				role_counts[clamp(int(ship.role), 0, 7)][profile] += 1
				if ship_construction_keel_profile(ship) != profile do changes += 1
			}
		}
		structural_count, role_collisions := 0, 0
		for present in seen do if present do structural_count += 1
		for profiles in role_counts do for count in profiles do role_collisions += count * (count - 1) / 2
		score := structural_count * 10000 - role_collisions * 100 - changes
		if score > best_score {best_score = score; best_code = code}
	}
	value := best_code
	for group in 0 ..< group_count {
		profile := u8(value % 3 + 1)
		value /= 3
		c.ships[group_first[group]].keel_profile = profile
		if group_second[group] >= 0 do c.ships[group_second[group]].keel_profile = profile
	}
}

reconcile_generated_structural_profiles :: proc(c: ^Campaign) {
	ships := c.ships
	layouts: [MAX_SHIPS]u8
	for ship, i in ships do layouts[i] = u8(ship_construction_drive_layout(ship) + 1)
	optimal_role_score := fleet_mission_profile_optimal_score(ships)
	for {
		best := fleet_drive_layout_structural_profile_count(ships, layouts)
		best_first, best_second := -1, -1
		for first in 0 ..< MAX_SHIPS do for second in first + 1 ..< MAX_SHIPS {
			if layouts[first] == layouts[second] do continue
			layouts[first], layouts[second] = layouts[second], layouts[first]
			role_score := fleet_mission_profile_collision_score(ships, layouts)
			structural_count := fleet_drive_layout_structural_profile_count(ships, layouts)
			layouts[first], layouts[second] = layouts[second], layouts[first]
			if role_score == optimal_role_score && structural_count > best {
				best = structural_count
				best_first, best_second = first, second
			}
		}
		if best_first < 0 do break
		layouts[best_first], layouts[best_second] = layouts[best_second], layouts[best_first]
	}
	if fleet_drive_layout_structural_profile_count(ships, layouts) < MAX_SHIPS {
		possibilities := 1
		for _ in 0 ..< MAX_SHIPS do possibilities *= 3
		for code in 0 ..< possibilities {
			value := code
			candidate: [MAX_SHIPS]u8
			counts: [3]int
			for &layout in candidate {
				layout = u8(value % 3 + 1)
				value /= 3
				counts[int(layout) - 1] += 1
			}
			if counts[0] != 4 || counts[1] != 4 || counts[2] != 4 do continue
			if fleet_mission_profile_collision_score(ships, candidate) != optimal_role_score do continue
			if fleet_drive_layout_structural_profile_count(ships, candidate) ==
			   MAX_SHIPS {layouts = candidate; break}
		}
	}
	for &ship, i in c.ships do ship.drive_layout = layouts[i]
}

// Reorder the existing sweep inventory across sibling hulls so yard lineages
// read coherently without changing fleet-wide profile counts. Exhaustively
// checking at most 3^6 assignments is small, deterministic, and preserves the
// construction diversity selected before relationships are established.
cohere_generated_lineage_sweeps :: proc(c: ^Campaign) {
	paired: [MAX_SHIPS]bool
	paired_indices: [MAX_SHIPS]int
	paired_count := 0
	original_counts: [3]int
	for ship in c.ships[:c.ship_count] do original_counts[ship_construction_wing_sweep(ship)] += 1
	for relationship in c.ship_relationships[:c.ship_relationship_count] {
		if relationship.kind != .Construction_Siblings do continue
		first := ship_index(c, relationship.ship_a)
		second := ship_index(c, relationship.ship_b)
		if first < 0 || second < 0 do continue
		paired[first], paired[second] = true, true
		paired_indices[paired_count], paired_indices[paired_count + 1] = first, second
		paired_count += 2
	}
	if paired_count < 2 do return
	unpaired_counts: [3]int
	unpaired_role_counts: [8][3]int
	for ship, index in c.ships[:c.ship_count] do if !paired[index] {
		profile := ship_construction_wing_sweep(ship)
		unpaired_counts[profile] += 1
		unpaired_role_counts[clamp(int(ship.role), 0, 7)][profile] += 1
	}
	possibilities := 1
	for _ in 0 ..< paired_count do possibilities *= 3
	best_code, best_score := 0, -1
	for code in 0 ..< possibilities {
		value := code
		counts := unpaired_counts
		role_counts := unpaired_role_counts
		assignment: [MAX_SHIPS]int
		changes := 0
		for position in 0 ..< paired_count {
			profile := value % 3
			value /= 3
			assignment[position] = profile
			counts[profile] += 1
			ship := c.ships[paired_indices[position]]
			role_counts[clamp(int(ship.role), 0, 7)][profile] += 1
			if profile != ship_construction_wing_sweep(c.ships[paired_indices[position]]) do changes += 1
		}
		if counts != original_counts do continue
		coherent := 0
		for position := 0; position < paired_count; position += 2 do if assignment[position] == assignment[position + 1] do coherent += 1
		role_collisions := 0
		for profiles in role_counts do for count in profiles do role_collisions += count * (count - 1) / 2
		// Shared-yard geometry is the primary lineage signal. Among equally
		// coherent assignments, retain as much repeated-role sweep diversity as
		// possible, then minimize unnecessary rebuilds from the seeded inventory.
		score := coherent * 10000 - role_collisions * 100 - changes
		if score > best_score {best_score = score; best_code = code}
	}
	value := best_code
	for position in 0 ..< paired_count {
		profile := value % 3
		value /= 3
		c.ships[paired_indices[position]].wing_sweep = u8(profile + 1)
	}
}

apply_generated_fleet :: proc(c: ^Campaign, goals: Fleet_Goals, prefix: string) {
	c.ships = generate_fleet(c.initial_seed, goals, prefix)
	c.ship_count = MAX_SHIPS
	initialize_generated_ship_lineages(c)
	rebalance_generated_lineage_families(c)
	cohere_generated_lineage_keels(c)
	reconcile_generated_structural_profiles(c)
	cohere_generated_lineage_sweeps(c)
	// Lineage assignment changes shared yard family and keel. Reallocate the
	// fixed bow inventory afterward so the final, persistent fleet remains the
	// best possible match for those factual construction relationships.
	bow_profiles := fleet_bow_profiles(c.initial_seed, c.ships)
	for &ship, i in c.ships do ship.bow_profile = bow_profiles[i]
	fleet_propulsion_initialize_ships(c)
	fleet_propellant_sync_ledger(c)
}
