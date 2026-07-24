package game_tests

import "core:math"
import "core:strings"
import "core:testing"

@(test)
construction_centerline_bias_is_stable_balanced_and_stat_neutral :: proc(t: ^testing.T) {
	counts: [2]int
	for identity in 1 ..= 600 {
		ship := Ship {
			id                = Ship_ID(identity),
			construction_seed = u64(identity),
			role              = .Survey,
			hull_class        = .Cruiser,
		}
		bias := ship_construction_centerline_bias(ship)
		counts[bias] += 1
		changed := ship
		changed.role = .Colony
		changed.hull_class = .Capital_Ship
		changed.mass_tonnes = 120000000
		changed.power = 99
		changed.crew = 99999
		changed.construction_lineage = 0xabcdef
		testing.expect_value(t, ship_construction_centerline_bias(changed), bias)
	}
	for count in counts do testing.expect(t, count >= 260 && count <= 340)
}

@(test)
construction_mission_profiles_are_stable_balanced_and_capability_neutral :: proc(t: ^testing.T) {
	counts: [3]int
	for identity in 1 ..= 900 {
		ship := Ship {
			id                = Ship_ID(identity),
			construction_seed = u64(identity),
			role              = .Survey,
			hull_class        = .Cruiser,
		}
		profile := ship_construction_mission_profile(ship)
		counts[profile] += 1
		changed := ship
		changed.role = .Colony
		changed.hull_class = .Capital_Ship
		changed.mass_tonnes = 120000000
		changed.power = 99
		changed.crew = 99999
		changed.construction_lineage = 0xabcdef
		testing.expect_value(t, ship_construction_mission_profile(changed), profile)
	}
	for count in counts do testing.expect(t, count >= 260 && count <= 340)
}

@(test)
construction_wing_stances_are_stable_balanced_and_stat_neutral :: proc(t: ^testing.T) {
	counts: [3]int
	for identity in 1 ..= 600 {
		ship := Ship {
			id                = Ship_ID(identity),
			construction_seed = u64(identity),
			role              = .Survey,
			hull_class        = .Corvette,
		}
		stance := ship_construction_wing_stance(ship)
		testing.expect(t, stance >= 0 && stance < len(counts))
		counts[stance] += 1
		changed := ship
		changed.role = .Colony
		changed.hull_class = .Capital_Ship
		changed.mass_tonnes = 120000000
		changed.power = 99
		changed.crew = 99999
		testing.expect_value(t, ship_construction_wing_stance(changed), stance)
	}
	for count in counts do testing.expect(t, count >= 170 && count <= 230)
}

@(test)
construction_wing_sweeps_are_stable_balanced_and_independent_from_stance :: proc(t: ^testing.T) {
	counts: [3]int
	pairs: [9]bool
	for identity in 1 ..= 900 {
		ship := Ship {
			id                = Ship_ID(identity),
			construction_seed = u64(identity),
			role              = .Survey,
			hull_class        = .Corvette,
		}
		sweep := ship_construction_wing_sweep(ship)
		stance := ship_construction_wing_stance(ship)
		testing.expect(t, sweep >= 0 && sweep < len(counts))
		counts[sweep] += 1
		pairs[stance * 3 + sweep] = true
		changed := ship
		changed.role = .Colony
		changed.hull_class = .Capital_Ship
		changed.mass_tonnes = 120000000
		changed.power = 99
		changed.crew = 99999
		changed.construction_lineage = 0xabcdef
		testing.expect_value(t, ship_construction_wing_sweep(changed), sweep)
	}
	for count in counts do testing.expect(t, count >= 260 && count <= 340)
	for present in pairs do testing.expect(t, present)
}

@(test)
construction_keel_profiles_are_stable_balanced_and_independent_from_stance :: proc(t: ^testing.T) {
	counts: [3]int
	pairs: [9]bool
	for identity in 1 ..= 900 {
		ship := Ship {
			id                = Ship_ID(identity),
			construction_seed = u64(identity),
			role              = .Foundry,
			hull_class        = .Fleet_Ship,
		}
		profile := ship_construction_keel_profile(ship)
		stance := ship_construction_wing_stance(ship)
		testing.expect(t, profile >= 0 && profile < len(counts))
		counts[profile] += 1
		pairs[profile * 3 + stance] = true
		changed := ship
		changed.role = .Hospital
		changed.hull_class = .Capital_Ship
		changed.mass_tonnes = 120000000
		testing.expect_value(t, ship_construction_keel_profile(changed), profile)
	}
	for count in counts do testing.expect(t, count >= 260 && count <= 340)
	for present in pairs do testing.expect(t, present)

	first := Ship {
		id                   = 1,
		construction_seed    = 0x1111,
		construction_lineage = 0xabcde,
	}
	second := Ship {
		id                   = 2,
		construction_seed    = 0x9999,
		construction_lineage = 0xabcde,
	}
	testing.expect_value(
		t,
		ship_construction_keel_profile(first),
		ship_construction_keel_profile(second),
	)
	// Wing placement remains an individual assembly decision rather than a
	// lineage trait, so changing lineage cannot silently rebuild that stance.
	before := ship_construction_wing_stance(first)
	first.construction_lineage = 0xfedcb
	testing.expect_value(t, ship_construction_wing_stance(first), before)
}

@(test)
construction_drive_layouts_are_stable_balanced_and_individual :: proc(t: ^testing.T) {
	counts: [3]int
	for identity in 1 ..= 600 {
		ship := Ship {
			id                = Ship_ID(identity),
			construction_seed = u64(identity),
			role              = .Escort,
			hull_class        = .Corvette,
		}
		layout := ship_construction_drive_layout(ship)
		testing.expect(t, layout >= 0 && layout < len(counts))
		counts[layout] += 1
		changed := ship
		changed.role = .Habitat
		changed.hull_class = .Capital_Ship
		changed.power = 99
		changed.construction_lineage = 0xabcdef
		testing.expect_value(t, ship_construction_drive_layout(changed), layout)
	}
	for count in counts do testing.expect(t, count >= 170 && count <= 230)
}

@(test)
construction_drive_setbacks_are_stable_balanced_and_independent_from_layout :: proc(
	t: ^testing.T,
) {
	counts: [3]int
	pairs: [9]bool
	for identity in 1 ..= 900 {
		ship := Ship {
			id                = Ship_ID(identity),
			construction_seed = u64(identity),
			role              = .Escort,
			hull_class        = .Cruiser,
		}
		setback := ship_construction_drive_setback(ship)
		layout := ship_construction_drive_layout(ship)
		counts[setback] += 1
		pairs[layout * 3 + setback] = true
		changed := ship
		changed.role = .Habitat
		changed.hull_class = .Capital_Ship
		changed.mass_tonnes = 120000000
		changed.power = 99
		changed.construction_lineage = 0xabcdef
		testing.expect_value(t, ship_construction_drive_setback(changed), setback)
	}
	for count in counts do testing.expect(t, count >= 260 && count <= 340)
	for present in pairs do testing.expect(t, present)
}

@(test)
construction_bow_profiles_are_stable_balanced_and_stat_neutral :: proc(t: ^testing.T) {
	counts: [3]int
	for identity in 1 ..= 600 {
		ship := Ship {
			id                = Ship_ID(identity),
			construction_seed = u64(identity),
			role              = .Survey,
			hull_class        = .Corvette,
		}
		profile := ship_construction_bow_profile(ship)
		testing.expect(t, profile >= 0 && profile < len(counts))
		counts[profile] += 1
		changed := ship
		changed.role = .Colony
		changed.hull_class = .Capital_Ship
		changed.mass_tonnes = 90000000
		changed.construction_lineage = 0xabcdef
		testing.expect_value(t, ship_construction_bow_profile(changed), profile)
	}
	for count in counts do testing.expect(t, count >= 170 && count <= 230)
}

@(test)
utility_hardpoints_are_persistent_independent_construction_data :: proc(t: ^testing.T) {
	counts: [9]int
	for seed in 1 ..= 900 {
		ship := generate_ship(u64(seed), default_ship_generator_config(seed % MAX_SHIPS))
		hardpoint := ship_construction_utility_hardpoint(ship)
		testing.expect(t, ship.utility_hardpoint >= 1 && ship.utility_hardpoint <= 9)
		counts[hardpoint] += 1
		changed := ship
		changed.role = .Colony
		changed.hull_class = .Capital_Ship
		changed.construction_lineage = 0xabcdef
		testing.expect_value(t, ship_construction_utility_hardpoint(changed), hardpoint)
	}
	for count in counts do testing.expect(t, count >= 75 && count <= 125)
	legacy := Ship {
		id                = 7,
		construction_seed = 0x7719,
	}
	testing.expect_value(
		t,
		ship_construction_utility_hardpoint(legacy),
		int((ship_construction_layout_code(legacy) - 1) % 9),
	)
}

@(test)
construction_structural_profiles_cover_all_twenty_seven_combinations :: proc(t: ^testing.T) {
	seen: [27]bool
	for identity in 1 ..= 4096 {
		ship := Ship {
			id                = Ship_ID(identity),
			construction_seed = u64(identity),
		}
		profile := ship_construction_structural_profile(ship)
		testing.expect(t, profile >= 0 && profile < len(seen))
		seen[profile] = true
	}
	for present in seen do testing.expect(t, present)
}

@(test)
complete_recipe_fingerprint_distinguishes_mirrored_centerline_decks :: proc(t: ^testing.T) {
	base := Ship {
		id                   = 7,
		construction_lineage = 0xabcde,
		bow_profile          = 2,
		utility_hardpoint    = 5,
		wing_sweep           = 2,
		wing_stance          = 2,
		keel_profile         = 2,
		mission_profile      = 2,
		drive_layout         = 2,
		drive_setback        = 2,
	}
	port, starboard := base, base
	found_port, found_starboard := false, false
	for seed in 1 ..= 128 {
		candidate := base
		candidate.construction_seed = u64(seed)
		if ship_construction_centerline_bias(candidate) == 0 &&
		   !found_port {port = candidate; found_port = true}
		if ship_construction_centerline_bias(candidate) == 1 &&
		   !found_starboard {starboard = candidate; found_starboard = true}
	}
	testing.expect(t, found_port && found_starboard)
	testing.expect_value(
		t,
		ship_construction_visual_fingerprint(port),
		ship_construction_visual_fingerprint(starboard),
	)
	testing.expect(
		t,
		ship_construction_recipe_fingerprint(port) !=
		ship_construction_recipe_fingerprint(starboard),
	)
	port.utility_hardpoint = 4
	starboard.utility_hardpoint = 4
	testing.expect_value(
		t,
		ship_construction_recipe_fingerprint(port),
		ship_construction_recipe_fingerprint(starboard),
	)
}
