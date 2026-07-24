package game_tests

import "core:testing"

@(test)
fleet_utility_hardpoints_cover_every_mount_with_seeded_balanced_repeats :: proc(t: ^testing.T) {
	ships: [MAX_SHIPS]Ship
	for &ship, i in ships do ship.role = Role(i % 8)
	first := fleet_utility_hardpoints(91, ships)
	repeat := fleet_utility_hardpoints(91, ships)
	neighbor := fleet_utility_hardpoints(92, ships)
	testing.expect_value(t, first, repeat)
	testing.expect(t, first != neighbor)
	counts: [9]int
	for hardpoint in first {
		testing.expect(t, hardpoint >= 1 && hardpoint <= 9)
		counts[int(hardpoint) - 1] += 1
	}
	for count in counts do testing.expect(t, count >= 1 && count <= 2)
	testing.expect_value(t, fleet_utility_hardpoint_collision_score(ships, first), 0)
}

@(test)
fleet_mission_profiles_are_exact_balanced_seeded_permutations :: proc(t: ^testing.T) {
	ships: [MAX_SHIPS]Ship
	for &ship, i in ships do ship.role = Role(i % 8)
	first := fleet_mission_profiles(91, ships)
	repeat := fleet_mission_profiles(91, ships)
	neighbor := fleet_mission_profiles(92, ships)
	testing.expect_value(t, first, repeat)
	testing.expect(t, first != neighbor)
	counts: [3]int
	for profile in first do counts[int(profile) - 1] += 1
	for count in counts do testing.expect_value(t, count, MAX_SHIPS / 3)
	testing.expect_value(
		t,
		fleet_mission_profile_collision_score(ships, first),
		fleet_mission_profile_optimal_score(ships),
	)
}

@(test)
fleet_wing_stances_are_exact_role_diverse_and_independent_from_mission_decks :: proc(
	t: ^testing.T,
) {
	ships: [MAX_SHIPS]Ship
	for &ship, i in ships do ship.role = Role(i % 8)
	first := fleet_wing_stances(91, ships)
	repeat := fleet_wing_stances(91, ships)
	neighbor := fleet_wing_stances(92, ships)
	mission := fleet_mission_profiles(91, ships)
	testing.expect_value(t, first, repeat)
	testing.expect(t, first != neighbor)
	testing.expect(t, first != mission)
	counts: [3]int
	for stance in first do counts[int(stance) - 1] += 1
	for count in counts do testing.expect_value(t, count, MAX_SHIPS / 3)
	testing.expect_value(
		t,
		fleet_mission_profile_collision_score(ships, first),
		fleet_mission_profile_optimal_score(ships),
	)
}

@(test)
fleet_drive_setbacks_are_exact_role_diverse_and_independently_seeded :: proc(t: ^testing.T) {
	ships: [MAX_SHIPS]Ship
	for &ship, i in ships do ship.role = Role(i % 8)
	first := fleet_drive_setbacks(91, ships)
	repeat := fleet_drive_setbacks(91, ships)
	neighbor := fleet_drive_setbacks(92, ships)
	mission := fleet_mission_profiles(91, ships)
	wing := fleet_wing_stances(91, ships)
	testing.expect_value(t, first, repeat)
	testing.expect(t, first != neighbor)
	testing.expect(t, first != mission)
	testing.expect(t, first != wing)
	counts: [3]int
	for setback in first do counts[int(setback) - 1] += 1
	for count in counts do testing.expect_value(t, count, MAX_SHIPS / 3)
	testing.expect_value(
		t,
		fleet_mission_profile_collision_score(ships, first),
		fleet_mission_profile_optimal_score(ships),
	)
}

@(test)
fleet_drive_layouts_are_exact_role_diverse_and_structurally_optimized :: proc(t: ^testing.T) {
	ships: [MAX_SHIPS]Ship
	for &ship, i in ships {
		ship.role = Role(i % 8)
		ship.keel_profile = u8(i % 3 + 1)
		ship.wing_stance = u8((i / 3) % 3 + 1)
	}
	first := fleet_drive_layouts(91, ships)
	repeat := fleet_drive_layouts(91, ships)
	neighbor := fleet_drive_layouts(92, ships)
	testing.expect_value(t, first, repeat)
	testing.expect(t, first != neighbor)
	counts: [3]int
	for layout in first do counts[int(layout) - 1] += 1
	for count in counts do testing.expect_value(t, count, MAX_SHIPS / 3)
	testing.expect_value(
		t,
		fleet_mission_profile_collision_score(ships, first),
		fleet_mission_profile_optimal_score(ships),
	)
	testing.expect(t, fleet_drive_layout_structural_profile_count(ships, first) >= 11)
}

@(test)
fleet_wing_sweeps_are_exact_role_diverse_and_independently_seeded :: proc(t: ^testing.T) {
	ships: [MAX_SHIPS]Ship
	for &ship, i in ships do ship.role = Role(i % 8)
	first := fleet_wing_sweeps(91, ships)
	repeat := fleet_wing_sweeps(91, ships)
	neighbor := fleet_wing_sweeps(92, ships)
	stance := fleet_wing_stances(91, ships)
	testing.expect_value(t, first, repeat)
	testing.expect(t, first != neighbor)
	testing.expect(t, first != stance)
	counts: [3]int
	for sweep in first do counts[int(sweep) - 1] += 1
	for count in counts do testing.expect_value(t, count, MAX_SHIPS / 3)
	testing.expect_value(
		t,
		fleet_mission_profile_collision_score(ships, first),
		fleet_mission_profile_optimal_score(ships),
	)
}

@(test)
fleet_keel_profiles_are_exact_role_diverse_and_structurally_optimized :: proc(t: ^testing.T) {
	ships: [MAX_SHIPS]Ship
	for &ship, i in ships {
		ship.role = Role(i % 8)
		ship.wing_stance = u8(i % 3 + 1)
		ship.drive_layout = u8((i / 3) % 3 + 1)
	}
	first := fleet_keel_profiles(91, ships)
	repeat := fleet_keel_profiles(91, ships)
	neighbor := fleet_keel_profiles(92, ships)
	testing.expect_value(t, first, repeat)
	testing.expect(t, first != neighbor)
	counts: [3]int
	for keel in first do counts[int(keel) - 1] += 1
	for count in counts do testing.expect_value(t, count, MAX_SHIPS / 3)
	testing.expect_value(
		t,
		fleet_mission_profile_collision_score(ships, first),
		fleet_mission_profile_optimal_score(ships),
	)
	testing.expect(t, fleet_keel_structural_profile_count(ships, first) >= 11)
}

@(test)
fleet_bow_profiles_are_exactly_balanced_seeded_permutations :: proc(t: ^testing.T) {
	ships: [MAX_SHIPS]Ship
	// Deliberately oversubscribe one doctrine so seeded overflow allocation is
	// observable independently from construction differences.
	for &ship, i in ships do ship = Ship {
		id                = Ship_ID(i + 1),
		construction_seed = 3,
	}
	first := fleet_bow_profiles(91, ships)
	repeat := fleet_bow_profiles(91, ships)
	neighbor := fleet_bow_profiles(92, ships)
	testing.expect_value(t, first, repeat)
	counts: [3]int
	differences := 0
	preference_counts: [3]int
	aligned := 0
	for profile, i in first {
		testing.expect(t, profile >= 1 && profile <= 3)
		counts[int(profile) - 1] += 1
		preferred := ship_construction_preferred_bow_profile(ships[i])
		preference_counts[preferred] += 1
		if int(profile) - 1 == preferred do aligned += 1
		if profile != neighbor[i] do differences += 1
	}
	for count in counts do testing.expect_value(t, count, MAX_SHIPS / 3)
	optimal_alignment := 0
	for count in preference_counts do optimal_alignment += min(count, MAX_SHIPS / 3)
	testing.expect_value(t, aligned, optimal_alignment)
	testing.expect(t, differences >= 2)
}
