package game

import "core:testing"
fleet_shuffle_roles :: proc(seed: u64, roles: ^[MAX_SHIPS]Role) {
	state := ship_generator_stream(seed, 0xbe5466cf34e90c6c)
	for index := MAX_SHIPS - 1; index > 0; index -= 1 {
		other := int(fleet_generator_next(&state) % u64(index + 1))
		roles[index], roles[other] = roles[other], roles[index]
	}
}

fleet_bow_profiles :: proc(seed: u64, ships: [MAX_SHIPS]Ship) -> [MAX_SHIPS]u8 {
	// Allocate the exact four-of-each inventory to yard preferences. Seeded ship
	// order and overflow choices keep equally good allocations campaign-specific.
	profiles: [MAX_SHIPS]u8
	remaining := [3]int{MAX_SHIPS / 3, MAX_SHIPS / 3, MAX_SHIPS / 3}
	order: [MAX_SHIPS]int
	for &index, i in order do index = i
	state := ship_generator_stream(seed, 0x9216d5d98979fb1b)
	for index := MAX_SHIPS - 1; index > 0; index -= 1 {
		other := int(fleet_generator_next(&state) % u64(index + 1))
		order[index], order[other] = order[other], order[index]
	}
	// Reserve every achievable preferred match before overflow can consume a
	// profile needed by a later hull.
	for ship_index in order {
		ship := ships[ship_index]
		if profiles[ship_index] != 0 || ship.construction_lineage == 0 do continue
		preferred := ship_construction_preferred_bow_profile(ship)
		if remaining[preferred] < 2 do continue
		partner := -1
		for other_index in order {
			if other_index == ship_index || profiles[other_index] != 0 do continue
			if ships[other_index].construction_lineage == ship.construction_lineage {
				partner = other_index
				break
			}
		}
		if partner < 0 do continue
		profiles[ship_index] = u8(preferred + 1)
		profiles[partner] = u8(preferred + 1)
		remaining[preferred] -= 2
	}
	for ship_index in order {
		if profiles[ship_index] != 0 do continue
		preferred := ship_construction_preferred_bow_profile(ships[ship_index])
		if remaining[preferred] == 0 do continue
		profiles[ship_index] = u8(preferred + 1)
		remaining[preferred] -= 1
	}
	// Keep unavoidable overflow siblings together when a remaining profile has
	// room for both; this is secondary to doctrine alignment and exact balance.
	for ship_index in order {
		ship := ships[ship_index]
		if profiles[ship_index] != 0 || ship.construction_lineage == 0 do continue
		partner := -1
		for other_index in order {
			if other_index == ship_index || profiles[other_index] != 0 do continue
			if ships[other_index].construction_lineage == ship.construction_lineage {
				partner = other_index
				break
			}
		}
		if partner < 0 do continue
		first := int(fleet_generator_next(&state) % 3)
		chosen := -1
		for offset in 0 ..< 3 {
			candidate := (first + offset) % 3
			if remaining[candidate] >= 2 && (chosen < 0 || remaining[candidate] > remaining[chosen]) do chosen = candidate
		}
		if chosen < 0 do continue
		profiles[ship_index] = u8(chosen + 1)
		profiles[partner] = u8(chosen + 1)
		remaining[chosen] -= 2
	}
	for ship_index in order {
		if profiles[ship_index] != 0 do continue
		first := int(fleet_generator_next(&state) % 3)
		chosen := first
		for offset in 0 ..< 3 {
			candidate := (first + offset) % 3
			if remaining[candidate] > remaining[chosen] do chosen = candidate
		}
		profiles[ship_index] = u8(chosen + 1)
		remaining[chosen] -= 1
	}
	return profiles
}

fleet_bow_doctrine_alignment :: proc(ships: []Ship) -> (aligned, optimal: int) {
	preference_counts: [3]int
	for ship in ships {
		preferred := ship_construction_preferred_bow_profile(ship)
		preference_counts[preferred] += 1
		if ship_construction_bow_profile(ship) == preferred do aligned += 1
	}
	for count in preference_counts do optimal += min(count, MAX_SHIPS / 3)
	return
}

fleet_mission_profile_collision_score :: proc(
	ships: [MAX_SHIPS]Ship,
	profiles: [MAX_SHIPS]u8,
) -> int {
	counts: [8][3]int
	for ship, i in ships {
		role := clamp(int(ship.role), 0, len(counts) - 1)
		profile := clamp(int(profiles[i]) - 1, 0, 2)
		counts[role][profile] += 1
	}
	score := 0
	for role_counts in counts do for count in role_counts do score += count * (count - 1) / 2
	return score
}

fleet_mission_profile_optimal_score :: proc(ships: [MAX_SHIPS]Ship) -> int {
	role_counts: [8]int
	for ship in ships do role_counts[clamp(int(ship.role), 0, len(role_counts) - 1)] += 1
	score := 0
	for count in role_counts do score += max(count - 3, 0)
	return score
}

fleet_balanced_role_profiles :: proc(
	seed: u64,
	ships: [MAX_SHIPS]Ship,
	domain: u64,
) -> [MAX_SHIPS]u8 {
	profiles: [MAX_SHIPS]u8
	for &profile, i in profiles do profile = u8(i % 3 + 1)
	state := ship_generator_stream(seed, domain)
	for index := MAX_SHIPS - 1; index > 0; index -= 1 {
		other := int(fleet_generator_next(&state) % u64(index + 1))
		profiles[index], profiles[other] = profiles[other], profiles[index]
	}
	// Preserve the exact four-of-each inventory while separating repeated roles
	// across deck profiles. Strictly improving swaps terminate deterministically;
	// the seeded starting permutation resolves equally optimal allocations.
	for {
		current := fleet_mission_profile_collision_score(ships, profiles)
		if current == fleet_mission_profile_optimal_score(ships) do break
		best, best_first, best_second := current, -1, -1
		for first in 0 ..< MAX_SHIPS do for second in first + 1 ..< MAX_SHIPS {
			if profiles[first] == profiles[second] do continue
			profiles[first], profiles[second] = profiles[second], profiles[first]
			score := fleet_mission_profile_collision_score(ships, profiles)
			profiles[first], profiles[second] = profiles[second], profiles[first]
			if score < best {best = score; best_first = first; best_second = second}
		}
		if best_first < 0 do break
		profiles[best_first], profiles[best_second] = profiles[best_second], profiles[best_first]
	}
	return profiles
}

fleet_mission_profiles :: proc(seed: u64, ships: [MAX_SHIPS]Ship) -> [MAX_SHIPS]u8 {
	return fleet_balanced_role_profiles(seed, ships, 0x1f83d9abfb41bd6b)
}

fleet_wing_stance_structural_profile_count :: proc(
	ships: [MAX_SHIPS]Ship,
	stances: [MAX_SHIPS]u8,
) -> int {
	seen: [27]bool
	for ship, i in ships {
		profile :=
			ship_construction_keel_profile(ship) * 9 +
			clamp(int(stances[i]) - 1, 0, 2) * 3 +
			ship_construction_drive_layout(ship)
		seen[profile] = true
	}
	count := 0
	for present in seen do if present do count += 1
	return count
}

fleet_wing_stances :: proc(seed: u64, ships: [MAX_SHIPS]Ship) -> [MAX_SHIPS]u8 {
	result := fleet_balanced_role_profiles(seed, ships, 0x243f6a8885a308d3)
	optimal_role_score := fleet_mission_profile_optimal_score(ships)
	// Among equally role-diverse allocations, prefer the assignment exposing the
	// most distinct keel/wing/drive silhouettes. Count-preserving swaps retain
	// exact 4/4/4 stance balance.
	for {
		best := fleet_wing_stance_structural_profile_count(ships, result)
		best_first, best_second := -1, -1
		for first in 0 ..< MAX_SHIPS do for second in first + 1 ..< MAX_SHIPS {
			if result[first] == result[second] do continue
			result[first], result[second] = result[second], result[first]
			role_score := fleet_mission_profile_collision_score(ships, result)
			structural_count := fleet_wing_stance_structural_profile_count(ships, result)
			result[first], result[second] = result[second], result[first]
			if role_score == optimal_role_score && structural_count > best {
				best = structural_count
				best_first, best_second = first, second
			}
		}
		if best_first < 0 do break
		result[best_first], result[best_second] = result[best_second], result[best_first]
	}
	return result
}

fleet_drive_setbacks :: proc(seed: u64, ships: [MAX_SHIPS]Ship) -> [MAX_SHIPS]u8 {
	return fleet_balanced_role_profiles(seed, ships, 0x13198a2e03707344)
}

fleet_drive_layout_structural_profile_count :: proc(
	ships: [MAX_SHIPS]Ship,
	layouts: [MAX_SHIPS]u8,
) -> int {
	seen: [27]bool
	for ship, i in ships {
		profile :=
			ship_construction_keel_profile(ship) * 9 +
			ship_construction_wing_stance(ship) * 3 +
			clamp(int(layouts[i]) - 1, 0, 2)
		seen[profile] = true
	}
	count := 0
	for present in seen do if present do count += 1
	return count
}

fleet_drive_layouts :: proc(seed: u64, ships: [MAX_SHIPS]Ship) -> [MAX_SHIPS]u8 {
	result := fleet_balanced_role_profiles(seed, ships, 0xa4093822299f31d0)
	optimal_role_score := fleet_mission_profile_optimal_score(ships)
	for {
		best := fleet_drive_layout_structural_profile_count(ships, result)
		best_first, best_second := -1, -1
		for first in 0 ..< MAX_SHIPS do for second in first + 1 ..< MAX_SHIPS {
			if result[first] == result[second] do continue
			result[first], result[second] = result[second], result[first]
			role_score := fleet_mission_profile_collision_score(ships, result)
			structural_count := fleet_drive_layout_structural_profile_count(ships, result)
			result[first], result[second] = result[second], result[first]
			if role_score == optimal_role_score && structural_count > best {
				best = structural_count
				best_first, best_second = first, second
			}
		}
		if best_first < 0 do break
		result[best_first], result[best_second] = result[best_second], result[best_first]
	}
	return result
}

fleet_wing_sweeps :: proc(seed: u64, ships: [MAX_SHIPS]Ship) -> [MAX_SHIPS]u8 {
	return fleet_balanced_role_profiles(seed, ships, 0x452821e638d01377)
}

fleet_keel_structural_profile_count :: proc(ships: [MAX_SHIPS]Ship, keels: [MAX_SHIPS]u8) -> int {
	seen: [27]bool
	for ship, i in ships {
		profile :=
			clamp(int(keels[i]) - 1, 0, 2) * 9 +
			ship_construction_wing_stance(ship) * 3 +
			ship_construction_drive_layout(ship)
		seen[profile] = true
	}
	count := 0
	for present in seen do if present do count += 1
	return count
}

fleet_keel_profiles :: proc(seed: u64, ships: [MAX_SHIPS]Ship) -> [MAX_SHIPS]u8 {
	result := fleet_balanced_role_profiles(seed, ships, 0xbe5466cf34e90c6c)
	optimal_role_score := fleet_mission_profile_optimal_score(ships)
	for {
		best := fleet_keel_structural_profile_count(ships, result)
		best_first, best_second := -1, -1
		for first in 0 ..< MAX_SHIPS do for second in first + 1 ..< MAX_SHIPS {
			if result[first] == result[second] do continue
			result[first], result[second] = result[second], result[first]
			role_score := fleet_mission_profile_collision_score(ships, result)
			structural_count := fleet_keel_structural_profile_count(ships, result)
			result[first], result[second] = result[second], result[first]
			if role_score == optimal_role_score && structural_count > best {
				best = structural_count
				best_first, best_second = first, second
			}
		}
		if best_first < 0 do break
		result[best_first], result[best_second] = result[best_second], result[best_first]
	}
	// Pair swaps can stop at an 11-profile local optimum. Only in that rare case,
	// search the complete balanced inventory for a role-optimal 12-profile
	// assignment. The space is 3^12, but count filtering leaves 34,650 candidates.
	if fleet_keel_structural_profile_count(ships, result) < MAX_SHIPS {
		possibilities := 1
		for _ in 0 ..< MAX_SHIPS do possibilities *= 3
		for code in 0 ..< possibilities {
			value := code
			candidate: [MAX_SHIPS]u8
			counts: [3]int
			for &profile in candidate {
				profile = u8(value % 3 + 1)
				value /= 3
				counts[int(profile) - 1] += 1
			}
			if counts[0] != 4 || counts[1] != 4 || counts[2] != 4 do continue
			if fleet_mission_profile_collision_score(ships, candidate) != optimal_role_score do continue
			if fleet_keel_structural_profile_count(ships, candidate) == MAX_SHIPS {
				result = candidate
				break
			}
		}
	}
	return result
}

fleet_utility_hardpoint_collision_score :: proc(
	ships: [MAX_SHIPS]Ship,
	hardpoints: [MAX_SHIPS]u8,
) -> int {
	counts: [8][9]int
	for ship, i in ships {
		role := clamp(int(ship.role), 0, len(counts) - 1)
		hardpoint := clamp(int(hardpoints[i]) - 1, 0, 8)
		counts[role][hardpoint] += 1
	}
	score := 0
	for role_counts in counts do for count in role_counts do score += count * (count - 1) / 2
	return score
}

// Every campaign should demonstrate the full utility-mount grammar. Start with
// one of each hardpoint, add three distinct seeded repeats, then shuffle the
// inventory. Count-preserving swaps separate repeated roles across mounts so
// ships with the same job do not also inherit the same utility silhouette.
fleet_utility_hardpoints :: proc(seed: u64, ships: [MAX_SHIPS]Ship) -> [MAX_SHIPS]u8 {
	assert(MAX_SHIPS == 12)
	positions := [9]u8{1, 2, 3, 4, 5, 6, 7, 8, 9}
	state := ship_generator_stream(seed, 0x6c8e9cf570932bd5)
	for i := len(positions) - 1; i > 0; i -= 1 {
		other := int(fleet_generator_next(&state) % u64(i + 1))
		positions[i], positions[other] = positions[other], positions[i]
	}
	result: [MAX_SHIPS]u8
	for position, i in positions do result[i] = position
	for i in 0 ..< 3 do result[len(positions) + i] = positions[i]
	for i := len(result) - 1; i > 0; i -= 1 {
		other := int(fleet_generator_next(&state) % u64(i + 1))
		result[i], result[other] = result[other], result[i]
	}
	for {
		current := fleet_utility_hardpoint_collision_score(ships, result)
		if current == 0 do break
		best, best_first, best_second := current, -1, -1
		for first in 0 ..< MAX_SHIPS do for second in first + 1 ..< MAX_SHIPS {
			if result[first] == result[second] do continue
			result[first], result[second] = result[second], result[first]
			score := fleet_utility_hardpoint_collision_score(ships, result)
			result[first], result[second] = result[second], result[first]
			if score < best {best = score; best_first = first; best_second = second}
		}
		if best_first < 0 do break
		result[best_first], result[best_second] = result[best_second], result[best_first]
	}
	return result
}
