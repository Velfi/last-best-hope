package game_tests

import "core:math"
import "core:strings"
import "core:testing"
@(test)
ship_generator_honors_locked_tuning :: proc(t: ^testing.T) {
	config := default_ship_generator_config(3)
	config.name = "Test Article"
	config.role = .Escort
	config.role_locked = true
	config.capability_percent = 150
	config.crew_percent = 50
	config.variation_percent = 0
	config.trait = .Cautious
	config.trait_locked = true
	ship := generate_ship(44, config)
	testing.expect_value(t, ship.name, "Test Article")
	testing.expect_value(t, ship.role, Role.Escort)
	testing.expect_value(t, ship.power, i32(15))
	testing.expect_value(t, ship.crew, i32(115))
	testing.expect_value(t, ship.passage_trait, Passage_Ship_Trait.Cautious)
}

@(test)
ship_generator_can_select_role_from_goals :: proc(t: ^testing.T) {
	config := default_ship_generator_config()
	config.variation_percent = 0
	ship := generate_ship(19, config, {exploration = 100})
	testing.expect(t, ship.role == .Survey || ship.role == .Archive)
	matching := generate_ship(19, config, {exploration = 100})
	testing.expect_value(t, ship.role, matching.role)
	testing.expect_value(t, ship.power, matching.power)
	testing.expect_value(t, ship.crew, matching.crew)
}

@(test)
ship_generator_spans_strike_craft_to_capital_ships :: proc(t: ^testing.T) {
	config := default_ship_generator_config()
	config.role = .Escort
	config.role_locked = true
	config.variation_percent = 0
	config.hull_class = .Strike_Craft
	fighter := generate_ship(8, config)
	config.hull_class = .Capital_Ship
	capital := generate_ship(8, config)
	testing.expect_value(t, fighter.crew, i32(1))
	testing.expect(t, fighter.power >= 1)
	testing.expect_value(t, capital.crew, i32(23000))
	testing.expect_value(t, capital.power, i32(60))
	testing.expect(t, capital.crew > fighter.crew * 10000)
	testing.expect(t, fighter.mass_tonnes >= 8 && fighter.mass_tonnes <= 35)
	testing.expect(t, capital.mass_tonnes >= 4000000 && capital.mass_tonnes <= 120000000)
}

@(test)
ship_generator_configuration_domains_do_not_reroll_each_other :: proc(t: ^testing.T) {
	config := default_ship_generator_config(2)
	config.role = .Foundry
	config.role_locked = true
	config.variation_percent = 25
	baseline := generate_ship(90210, config)

	trait_locked := config
	trait_locked.trait = .Cautious
	trait_locked.trait_locked = true
	with_trait := generate_ship(90210, trait_locked)
	testing.expect_value(t, with_trait.mass_tonnes, baseline.mass_tonnes)
	testing.expect_value(t, with_trait.power, baseline.power)
	testing.expect_value(t, with_trait.crew, baseline.crew)

	heavier := config
	heavier.mass_percent = 150
	with_mass := generate_ship(90210, heavier)
	testing.expect(t, with_mass.mass_tonnes > baseline.mass_tonnes)
	testing.expect_value(t, with_mass.power, baseline.power)
	testing.expect_value(t, with_mass.crew, baseline.crew)

	stronger := config
	stronger.capability_percent = 150
	with_power := generate_ship(90210, stronger)
	testing.expect(t, with_power.power > baseline.power)
	testing.expect_value(t, with_power.mass_tonnes, baseline.mass_tonnes)
	testing.expect_value(t, with_power.crew, baseline.crew)

	staffed := config
	staffed.crew_percent = 150
	with_crew := generate_ship(90210, staffed)
	testing.expect(t, with_crew.crew > baseline.crew)
	testing.expect_value(t, with_crew.mass_tonnes, baseline.mass_tonnes)
	testing.expect_value(t, with_crew.power, baseline.power)
}

@(test)
community_assignment_does_not_reroll_construction_or_capability :: proc(t: ^testing.T) {
	config := default_ship_generator_config(5)
	config.role = .Archive
	config.role_locked = true
	config.hull_class = .Corvette
	config.community = 1
	first := generate_ship(8819, config)
	config.community = 4
	second := generate_ship(8819, config)
	testing.expect(t, first.community != second.community)
	testing.expect_value(t, first.name, second.name)
	testing.expect_value(t, first.construction_seed, second.construction_seed)
	testing.expect_value(t, first.mass_tonnes, second.mass_tonnes)
	testing.expect_value(t, first.power, second.power)
	testing.expect_value(t, first.crew, second.crew)
	testing.expect_value(t, first.passage_trait, second.passage_trait)
}

@(test)
role_authentic_hull_selection_covers_every_class :: proc(t: ^testing.T) {
	seen: [5]bool
	for role_value in 0 ..< 8 {
		role := Role(role_value)
		for seed in 1 ..= 256 {
			hull := ship_hull_class_from_role(u64(seed), role)
			testing.expect(t, hull != .Unspecified)
			seen[int(hull) - 1] = true
			switch role {
			case .Habitat:
				testing.expect(t, hull == .Fleet_Ship || hull == .Cruiser || hull == .Capital_Ship)
			case .Agriculture, .Hospital:
				testing.expect(t, hull == .Fleet_Ship || hull == .Cruiser)
			case .Foundry:
				testing.expect(t, hull == .Fleet_Ship || hull == .Cruiser || hull == .Capital_Ship)
			case .Archive:
				testing.expect(t, hull == .Corvette || hull == .Fleet_Ship || hull == .Cruiser)
			case .Survey:
				testing.expect(
					t,
					hull == .Strike_Craft || hull == .Corvette || hull == .Fleet_Ship,
				)
			case .Escort:
				testing.expect(t, hull == .Strike_Craft || hull == .Corvette || hull == .Cruiser)
			case .Colony:
				testing.expect(t, hull == .Cruiser || hull == .Capital_Ship)
			}
		}
	}
	for present in seen do testing.expect(t, present)
}

@(test)
unlocked_ship_generation_assigns_every_meaningful_trait_but_not_none :: proc(t: ^testing.T) {
	config := default_ship_generator_config()
	seen: [5]bool
	for seed in 1 ..= 256 {
		ship := generate_ship(u64(seed), config)
		testing.expect(t, ship.passage_trait != .None)
		index := int(ship.passage_trait) - 1
		testing.expect(t, index >= 0 && index < len(seen))
		seen[index] = true
		testing.expect_value(t, ship.passage_trait, generate_ship(u64(seed), config).passage_trait)
	}
	for present in seen do testing.expect(t, present)

	config.trait = .None
	config.trait_locked = true
	intentional_blank := generate_ship(19, config)
	testing.expect_value(t, intentional_blank.passage_trait, Passage_Ship_Trait.None)
}

@(test)
generated_mass_stays_inside_hull_class_envelope_after_all_tuning :: proc(t: ^testing.T) {
	classes := [5]Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for hull_class in classes {
		low, high := ship_hull_mass_range(hull_class)
		for role_value in 0 ..< 8 {
			role := Role(role_value)
			for seed in 1 ..= 64 {
				low_state := ship_generator_stream(u64(seed), 0xbf58476d1ce4e5b9)
				high_state := low_state
				light := generate_ship_mass(&low_state, role, hull_class, 25)
				heavy := generate_ship_mass(&high_state, role, hull_class, 200)
				testing.expect(t, light >= low && light <= high)
				testing.expect(t, heavy >= low && heavy <= high)
				testing.expect(t, light <= heavy)
			}
		}
	}
}

@(test)
archetype_mass_ranges_are_valid_ordered_and_visually_compressed :: proc(t: ^testing.T) {
	for value in 1 ..= SHIP_HULL_ARCHETYPE_COUNT {
		archetype := Ship_Hull_Archetype(
			value,
		); low, high := ship_hull_archetype_mass_range(archetype); class_low, class_high := ship_hull_mass_range(ship_hull_archetype_class(archetype))
		testing.expect(
			t,
			low > 0 && low <= high,
		); testing.expect(t, low >= class_low && high <= class_high)
	}
	ordered := [6]Ship_Hull_Archetype {
		.Scout,
		.Corvette,
		.Combat_Frigate,
		.Light_Cruiser,
		.Battleship,
		.Dreadnought,
	}
	for i in 1 ..< len(
		ordered,
	) {previous := ship_hull_archetype_nominal_mass(ordered[i - 1]); current := ship_hull_archetype_nominal_mass(ordered[i]); testing.expect(t, previous < current); testing.expect(t, ship_tonnage_visual_scale(previous) < ship_tonnage_visual_scale(current))}
	testing.expect(
		t,
		ship_tonnage_visual_scale(ship_hull_archetype_nominal_mass(.Dreadnought)) /
			ship_tonnage_visual_scale(ship_hull_archetype_nominal_mass(.Scout)) <
		4,
	)
}

@(test)
generated_ship_mass_stays_inside_its_archetype_band :: proc(t: ^testing.T) {
	for value in 1 ..= SHIP_HULL_ARCHETYPE_COUNT {archetype := Ship_Hull_Archetype(value); low, high := ship_hull_archetype_mass_range(archetype); for seed in 1 ..= 32 {state := ship_generator_stream(u64(seed), 0xbf58476d1ce4e5b9); mass := generate_ship_archetype_mass(&state, .Escort, archetype, 100); testing.expect(t, mass >= low && mass <= high)}}
}

@(test)
role_mass_bias_is_ordered_without_collapsing_seeded_variation :: proc(t: ^testing.T) {
	classes := [5]Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for hull_class in classes {
		strictly_ordered := 0
		for seed in 1 ..= 128 {
			light_state := ship_generator_stream(u64(seed), 0xbf58476d1ce4e5b9)
			standard_state := light_state
			heavy_state := light_state
			light := generate_ship_mass(&light_state, .Survey, hull_class, 100)
			standard := generate_ship_mass(&standard_state, .Escort, hull_class, 100)
			heavy := generate_ship_mass(&heavy_state, .Habitat, hull_class, 100)
			testing.expect(t, light <= standard && standard <= heavy)
			if light < standard && standard < heavy do strictly_ordered += 1
		}
		testing.expect(t, strictly_ordered >= 100)
	}

	seen: [256]i64
	unique := 0
	for seed in 1 ..= 256 {
		state := ship_generator_stream(u64(seed), 0xbf58476d1ce4e5b9)
		mass := generate_ship_mass(&state, .Foundry, .Fleet_Ship, 100)
		duplicate := false
		for prior in 0 ..< unique do if seen[prior] == mass do duplicate = true
		if !duplicate {seen[unique] = mass; unique += 1}
	}
	testing.expect(t, unique >= 220)
}

@(test)
generated_ships_are_semantically_complete_entities_at_creation :: proc(t: ^testing.T) {
	for role_value in 0 ..< 8 {
		role := Role(role_value)
		config := default_ship_generator_config(role_value)
		config.role = role
		config.role_locked = true
		ship := generate_ship(u64(700 + role_value), config)
		testing.expect_value(t, ship.semantic_tags, semantic_tags_for_ship(role))
		testing.expect(t, semantic_has(ship.semantic_tags, .Entity))
		testing.expect(t, semantic_has(ship.semantic_tags, .Ship))
	}
}

@(test)
construction_identity_is_stable_per_seed_and_varies_across_fleets :: proc(t: ^testing.T) {
	config := default_ship_generator_config(4)
	first := generate_ship(77, config)
	repeat := generate_ship(77, config)
	testing.expect(t, first.construction_seed != 0)
	testing.expect_value(t, first.construction_seed, repeat.construction_seed)

	seen: [64]u64
	unique := 0
	for seed in 1 ..= 64 {
		identity := generate_ship(u64(seed), config).construction_seed
		duplicate := false
		for prior in 0 ..< unique do if seen[prior] == identity do duplicate = true
		if !duplicate {seen[unique] = identity; unique += 1}
	}
	testing.expect(t, unique >= 60)

	campaign_a: Campaign
	campaign_init(&campaign_a, 41)
	campaign_b: Campaign
	campaign_init(&campaign_b, 41)
	campaign_c: Campaign
	campaign_init(&campaign_c, 42)
	different := 0
	for ship, i in campaign_a.ships[:campaign_a.ship_count] {
		testing.expect_value(t, ship.construction_seed, campaign_b.ships[i].construction_seed)
		if ship.construction_seed != campaign_c.ships[i].construction_seed do different += 1
	}
	testing.expect(t, different == campaign_a.ship_count)
}

@(test)
construction_identity_selection_cannot_reroll_ship_capabilities :: proc(t: ^testing.T) {
	config := default_ship_generator_config(5)
	config.role = .Survey
	config.role_locked = true
	config.hull_class = .Corvette
	original := generate_ship(0x7719, config)
	first := ship_with_construction_identity(original, 0x1111)
	second := ship_with_construction_identity(original, 0x2222)
	testing.expect(t, first.construction_seed != original.construction_seed)
	testing.expect(t, first.construction_seed != second.construction_seed)
	identities := [2]Ship{first, second}
	for ship in identities {
		testing.expect_value(t, ship.name, original.name)
		testing.expect_value(t, ship.role, original.role)
		testing.expect_value(t, ship.hull_class, original.hull_class)
		testing.expect_value(t, ship.mass_tonnes, original.mass_tonnes)
		testing.expect_value(t, ship.power, original.power)
		testing.expect_value(t, ship.crew, original.crew)
		testing.expect_value(t, ship.community, original.community)
		testing.expect_value(t, ship.passage_trait, original.passage_trait)
		testing.expect_value(
			t,
			ship.bow_profile,
			u8(ship_construction_visual_mix(ship.construction_seed ~ 0x9216d5d98979fb1b) % 3 + 1),
		)
		testing.expect_value(
			t,
			ship.utility_hardpoint,
			u8(ship_construction_visual_mix(ship.construction_seed ~ 0xd1310ba698dfb5ac) % 9 + 1),
		)
		testing.expect_value(
			t,
			ship.wing_sweep,
			u8(ship_construction_visual_mix(ship.construction_seed ~ 0x6a09e667f3bcc909) % 3 + 1),
		)
		testing.expect_value(
			t,
			ship.wing_stance,
			u8(ship_construction_visual_mix(ship.construction_seed ~ 0x13198a2e03707344) % 3 + 1),
		)
		testing.expect_value(
			t,
			ship.keel_profile,
			u8(ship_construction_visual_mix(ship.construction_seed ~ 0x082efa98ec4e6c89) % 3 + 1),
		)
		testing.expect_value(
			t,
			ship.mission_profile,
			u8(ship_construction_visual_mix(ship.construction_seed ~ 0x510e527fade682d1) % 3 + 1),
		)
		testing.expect_value(
			t,
			ship.drive_layout,
			u8(ship_construction_visual_mix(ship.construction_seed ~ 0x3f84d5b5b5470917) % 3 + 1),
		)
		testing.expect_value(
			t,
			ship.drive_setback,
			u8(ship_construction_visual_mix(ship.construction_seed ~ 0xbb67ae8584caa73b) % 3 + 1),
		)
	}
}
