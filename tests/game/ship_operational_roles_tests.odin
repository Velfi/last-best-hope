package game_tests

import "core:testing"

@(test)
production_taxonomy_contains_24_named_archetypes_in_six_families :: proc(t: ^testing.T) {
	families: [6]bool
	for value in 1 ..= SHIP_HULL_ARCHETYPE_COUNT {
		archetype := Ship_Hull_Archetype(value)
		testing.expect(t, ship_hull_archetype_name(archetype) != "unspecified")
		family := ship_hull_archetype_family(archetype)
		testing.expect(t, family != .Unspecified)
		families[int(family) - 1] = true
		testing.expect(t, ship_hull_archetype_class(archetype) != .Unspecified)
	}
	for present in families do testing.expect(t, present)
}

@(test)
archetype_generation_is_seeded_and_preserves_broad_hull_scale :: proc(t: ^testing.T) {
	classes := [5]Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	seen: [SHIP_HULL_ARCHETYPE_COUNT]bool
	for hull_class in classes {
		for role_value in 0 ..< 8 {
			for seed in 1 ..= 512 {
				archetype := ship_hull_archetype_from_role(u64(seed), Role(role_value), hull_class)
				testing.expect_value(t, ship_hull_archetype_class(archetype), hull_class)
				testing.expect_value(
					t,
					archetype,
					ship_hull_archetype_from_role(u64(seed), Role(role_value), hull_class),
				)
				seen[int(archetype) - 1] = true
			}
		}
	}
	for present in seen do testing.expect(t, present)
}

@(test)
all_37_named_operational_roles_fit_a_production_hull_and_have_modules :: proc(t: ^testing.T) {
	for value in 1 ..= SHIP_OPERATIONAL_ROLE_COUNT {
		role := Ship_Operational_Role(
			value,
		); testing.expect(t, ship_operational_role_name(role) != "unspecified")
		fits :=
			false; for hull_value in 1 ..= SHIP_HULL_ARCHETYPE_COUNT do if ship_operational_role_fits_hull(role, Ship_Hull_Archetype(hull_value)) {fits = true; break}
		testing.expect(t, fits); testing.expect(t, ship_operational_role_modules(role) != {})
	}
}

@(test)
modular_hulls_change_role_without_changing_production_archetype :: proc(t: ^testing.T) {
	testing.expect(
		t,
		ship_operational_role_fits_hull(.Flak_Frigate, .Combat_Frigate),
	); testing.expect(t, ship_operational_role_fits_hull(.Missile_Frigate, .Combat_Frigate)); testing.expect(t, ship_operational_role_fits_hull(.Electronic_Warfare_Frigate, .Combat_Frigate)); testing.expect(t, ship_operational_role_fits_hull(.Shield_Frigate, .Combat_Frigate))
	testing.expect(
		t,
		ship_operational_role_fits_hull(.Hospital_Ship, .Utility_Hull),
	); testing.expect(t, ship_operational_role_fits_hull(.Fabricator_Ship, .Transport_Hull)); testing.expect(t, ship_operational_role_fits_hull(.Generation_Ship, .Habitat_Hull)); testing.expect(t, ship_operational_role_fits_hull(.Arkship, .Habitat_Hull))
}

@(test)
ordinary_roster_filter_reserves_campaign_defining_assets :: proc(t: ^testing.T) {
	for strategic_value in 0 ..< 8 do for seed in 1 ..= 512 {
		hull := ship_hull_archetype_for_ordinary_roster(u64(seed), Role(strategic_value), .Capital_Ship); testing.expect(t, hull != .Battleship && hull != .Dreadnought)
		role := ship_operational_role_for_ordinary_roster(u64(seed), Role(strategic_value), hull); testing.expect(t, role != .Generation_Ship && role != .Arkship)
	}
}

@(test)
every_operational_role_has_queryable_simulation_capability :: proc(t: ^testing.T) {
	for value in 1 ..= SHIP_OPERATIONAL_ROLE_COUNT {p := ship_operational_profile(Ship_Operational_Role(value)); total := p.recon + p.stealth + p.interception + p.anti_ship + p.boarding + p.capture + p.point_defense + p.long_range + p.electronic_warfare + p.shield + p.repair + p.recovery + p.area_denial + p.command + p.flight_support + p.cargo + p.propellant + p.fabrication + p.medical + p.population + p.colony + p.archive; testing.expect(t, total > 0)}
	testing.expect_value(
		t,
		ship_operational_profile(.Assault_Shuttle).capture,
		i32(100),
	); testing.expect_value(t, ship_operational_profile(.Command_Ship).command, i32(100)); testing.expect_value(t, ship_operational_profile(.Hospital_Ship).medical, i32(100)); testing.expect_value(t, ship_operational_profile(.Arkship).archive, i32(100))
}

@(test)
guidebook_covers_every_named_operational_role :: proc(t: ^testing.T) {
	for value in 1 ..= SHIP_OPERATIONAL_ROLE_COUNT {role := Ship_Operational_Role(value); testing.expect(t, ship_operational_role_function(role) != ""); testing.expect(t, ship_operational_role_response(role) != ""); testing.expect(t, ship_operational_role_hull(role) != .Unspecified); testing.expect(t, ship_operational_role_family(role) != .Unspecified)}
}
