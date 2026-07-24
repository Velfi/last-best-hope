package game_tests

import "core:testing"

@(test)
ship_generator_architecture_names_cover_every_kind :: proc(t: ^testing.T) {
	expected := [4]string{"MODULAR FRAME", "SINGLE HULL", "DELTA", "DELTA"}
	for kind in Ship_Generator_Kind do testing.expect_value(t, ship_generator_kind_name(kind), expected[int(kind)])
}

@(test)
construction_styles_produce_distinct_deterministic_recipes :: proc(t: ^testing.T) {
	base := Ship {
		id                = 7,
		construction_seed = 7007,
		hull_archetype    = .Habitat_Hull,
		operational_role  = .Habitat_Ship,
		keel_profile      = 2,
		wing_stance       = 2,
	}
	fingerprints: [4]u64
	for style in Ship_Construction_Style {
		ship := base; ship.construction_style = style
		a := procedural_ship_generate_for_ship(ship); b := procedural_ship_generate_for_ship(ship)
		testing.expect_value(
			t,
			a.fingerprint,
			b.fingerprint,
		); fingerprints[int(style)] = a.fingerprint
	}
	for i in 0 ..< len(fingerprints) do for j in i + 1 ..< len(fingerprints) do testing.expect(t, fingerprints[i] != fingerprints[j])
}
