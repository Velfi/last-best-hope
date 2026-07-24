package game_tests

import "core:testing"
import "core:fmt"
import "core:strings"

@(test)
place_name_kinds_are_distinct_deterministic_and_filterable :: proc(t: ^testing.T) {
	seed := u64(0x1cedcafe)
	star := generate_star_name(seed)
	settlement := generate_settlement_name(seed)
	gate := generate_gate_name(seed)
	testing.expect_value(t, star, generate_star_name(seed))
	testing.expect_value(t, settlement, generate_settlement_name(seed))
	testing.expect_value(t, gate, generate_gate_name(seed))
	testing.expect(t, star != settlement && star != gate && settlement != gate)
	config := Celestial_Name_Config {
		max_length     = 24,
		excluded_names = []string{star, settlement, gate},
	}
	testing.expect(t, generate_star_name(seed, config) != star)
	testing.expect(t, generate_settlement_name(seed, config) != settlement)
	testing.expect(t, generate_gate_name(seed, config) != gate)
}

@(test)
door_hash_names_are_stable_three_word_identifiers :: proc(t: ^testing.T) {
	name := generate_door_hash_name(0x1cedcafe)
	testing.expect_value(t, name, generate_door_hash_name(0x1cedcafe))
	testing.expect(t, strings.count(name, "-") == 2)
	testing.expect(t, name != generate_door_hash_name(0x1cedcaff))
	for rune in name do testing.expect(t, rune == '-' || rune >= 'a' && rune <= 'z')
}

@(test)
celestial_names_are_deterministic_unique_and_complete :: proc(t: ^testing.T) {
	system := generate_solar_system(0x5eed)
	names := generate_solar_system_names(system)
	testing.expect_value(t, names, generate_solar_system_names(system))
	testing.expect(t, names.proper_name != "" && names.star_name != "")
	testing.expect_value(t, names.planet_count, system.planet_count)
	for name, index in names.planet_names[:names.planet_count] {
		testing.expect(t, name != "")
		for prior in names.planet_names[:index] do testing.expect(t, name != prior)
		testing.expect_value(t, names.planet_designations[index].component, u8('b' + index))
	}
}

@(test)
celestial_name_styles_rerolls_exclusions_and_orbital_scheme_work :: proc(t: ^testing.T) {
	system := generate_solar_system(7719)
	config := default_celestial_name_config(); config.style = .Navigational
	first := generate_solar_system_names(system, config)
	testing.expect_value(t, first.style, Celestial_Name_Style.Navigational)
	config.excluded_names = []string{first.proper_name}
	testing.expect(t, generate_solar_system_names(system, config).proper_name != first.proper_name)
	config.excluded_names = nil; config.planet_scheme = .Orbital
	orbital := generate_solar_system_names(system, config)
	for name, index in orbital.planet_names[:orbital.planet_count] {
		testing.expect(t, strings.has_prefix(name, orbital.star_name))
		testing.expect(t, strings.has_suffix(name, fmt.tprintf("%c", u8('b' + index))))
		for prior in orbital.planet_names[:index] do testing.expect(t, name != prior)
		testing.expect(t, format_catalog_designation(orbital.planet_designations[index]) != "")
	}
	testing.expect(t, generate_system_name(system.seed, config, 1) != "")
}

@(test)
systemic_planet_styles_use_distinct_vocabularies :: proc(t: ^testing.T) {
	seed := u64(99173)
	archival := generate_planet_name(seed, 0, {style = .Archival, max_length = 24})
	natural := generate_planet_name(seed, 0, {style = .Natural, max_length = 24})
	navigational := generate_planet_name(seed, 0, {style = .Navigational, max_length = 24})
	settlement := generate_planet_name(seed, 0, {style = .Settlement, max_length = 24})
	survey := generate_planet_name(seed, 0, {style = .Survey, max_length = 24})
	testing.expect(
		t,
		archival != natural &&
		archival != navigational &&
		archival != settlement &&
		archival != survey,
	)
	for candidate in PLANET_NAMES_ARCHIVAL do if candidate == archival {return}
	testing.expect(t, false, "archival planet name did not come from the archival vocabulary")
}
