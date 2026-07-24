package game

import "core:fmt"
import "core:strings"
default_celestial_name_config :: proc() -> Celestial_Name_Config {
	return {style = .Any, planet_scheme = .Systemic, max_length = 24}
}

celestial_name_hash :: proc(seed, domain: u64) -> u64 {
	return ship_construction_visual_mix(seed ~ domain)
}

celestial_name_excluded :: proc(name: string, excluded: []string) -> bool {
	for item in excluded do if strings.equal_fold(item, name) do return true
	return false
}

celestial_name_valid :: proc(name: string, config: Celestial_Name_Config) -> bool {
	return(
		name != "" &&
		(config.max_length <= 0 || len(name) <= config.max_length) &&
		!celestial_name_excluded(name, config.excluded_names) \
	)
}

celestial_style_for_seed :: proc(
	seed: u64,
	requested: Celestial_Name_Style,
) -> Celestial_Name_Style {
	if requested != .Any do return requested
	return Celestial_Name_Style(1 + celestial_name_hash(seed, 0x7374796c65) % 5)
}

celestial_system_pool :: proc(style: Celestial_Name_Style) -> []string {
	switch style {
	case .Archival:
		return SYSTEM_NAMES_ARCHIVAL[:]
	case .Natural:
		return SYSTEM_NAMES_NATURAL[:]
	case .Navigational:
		return SYSTEM_NAMES_NAVIGATIONAL[:]
	case .Settlement:
		return SYSTEM_NAMES_SETTLEMENT[:]
	case .Survey:
		return SYSTEM_NAMES_SURVEY[:]
	case .Any:
		return SYSTEM_NAMES_NATURAL[:]
	}
	return SYSTEM_NAMES_NATURAL[:]
}

celestial_planet_pool :: proc(style: Celestial_Name_Style) -> []string {
	switch style {
	case .Archival:
		return PLANET_NAMES_ARCHIVAL[:]
	case .Natural:
		return PLANET_NAMES_NATURAL[:]
	case .Navigational:
		return PLANET_NAMES_NAVIGATIONAL[:]
	case .Settlement:
		return PLANET_NAMES_SETTLEMENT[:]
	case .Survey:
		return PLANET_NAMES_SURVEY[:]
	case .Any:
		return PLANET_NAMES_NATURAL[:]
	}
	return PLANET_NAMES_NATURAL[:]
}

generate_system_name :: proc(
	seed: u64,
	config: Celestial_Name_Config = {planet_scheme = .Systemic, max_length = 24},
	reroll: u32 = 0,
) -> string {
	style := celestial_style_for_seed(seed, config.style)
	pool := celestial_system_pool(style)
	start := int(
		celestial_name_hash(seed ~ u64(reroll) * 0x9e3779b97f4a7c15, 0x73797374656d) %
		u64(len(pool)),
	)
	for offset in 0 ..< len(pool) {
		candidate := pool[(start + offset) % len(pool)]
		if celestial_name_valid(candidate, config) do return candidate
	}
	// Filters are advisory when they would make generation impossible.
	return(
		SYSTEM_NAMES_NATURAL[int(celestial_name_hash(seed, 0x66616c6c6261636b) % len(SYSTEM_NAMES_NATURAL))] \
	)
}

generate_planet_name :: proc(
	seed: u64,
	planet_index: int,
	config: Celestial_Name_Config = {planet_scheme = .Individual, max_length = 24},
	reroll: u32 = 0,
) -> string {
	key := seed ~ u64(planet_index + 1) * 0xbf58476d1ce4e5b9 ~ u64(reroll) * 0x94d049bb133111eb
	style := celestial_style_for_seed(key, config.style)
	pool := celestial_planet_pool(style)
	start := int(celestial_name_hash(key, 0x706c616e6574) % u64(len(pool)))
	for offset in 0 ..< len(pool) {
		candidate := pool[(start + offset) % len(pool)]
		if celestial_name_valid(candidate, config) do return candidate
	}
	return pool[start]
}

generate_star_name :: proc(
	seed: u64,
	config: Celestial_Name_Config = {max_length = 24},
	reroll: u32 = 0,
) -> string {
	key := seed ~ u64(reroll) * 0xd6e8feb86659fd93
	start := int(celestial_name_hash(key, 0x73746172) % len(STAR_NAMES))
	for offset in 0 ..< len(STAR_NAMES) {
		candidate := STAR_NAMES[(start + offset) % len(STAR_NAMES)]
		if celestial_name_valid(candidate, config) do return candidate
	}
	return STAR_NAMES[start]
}

generate_settlement_name :: proc(
	seed: u64,
	config: Celestial_Name_Config = {max_length = 24},
	reroll: u32 = 0,
) -> string {
	key := seed ~ u64(reroll) * 0xa0761d6478bd642f
	start := int(celestial_name_hash(key, 0x736574746c65) % len(SETTLEMENT_NAMES))
	for offset in 0 ..< len(SETTLEMENT_NAMES) {
		candidate := SETTLEMENT_NAMES[(start + offset) % len(SETTLEMENT_NAMES)]
		if celestial_name_valid(candidate, config) do return candidate
	}
	return "Common Ground"
}

format_catalog_designation :: proc(designation: Catalog_Designation) -> string {
	if designation.component == 0 do return fmt.tprintf("%s %d", designation.prefix, designation.number)
	return fmt.tprintf("%s %d %c", designation.prefix, designation.number, designation.component)
}

generate_gate_name :: proc(
	seed: u64,
	config: Celestial_Name_Config = {max_length = 24},
	reroll: u32 = 0,
) -> string {
	key := seed ~ u64(reroll) * 0xe7037ed1a0b428db
	root_start := int(celestial_name_hash(key, 0x67617465) % len(GATE_ROOTS))
	form_start := int(celestial_name_hash(key, 0x70617373) % len(GATE_FORMS))
	for attempt in 0 ..< len(GATE_ROOTS) * len(GATE_FORMS) {
		root := GATE_ROOTS[(root_start + attempt / len(GATE_FORMS)) % len(GATE_ROOTS)]
		form := GATE_FORMS[(form_start + attempt) % len(GATE_FORMS)]
		candidate := fmt.tprintf("%s %s", root, form)
		if celestial_name_valid(candidate, config) do return candidate
	}
	return "Outer Gate"
}

door_hash_word :: proc(index: u64) -> string {
	adjective_count := u64(len(DOOR_HASH_ADJECTIVES))
	animal_count := u64(len(DOOR_HASH_ANIMALS))
	if index < adjective_count do return DOOR_HASH_ADJECTIVES[index]
	if index < adjective_count + animal_count do return DOOR_HASH_ANIMALS[index - adjective_count]
	return DOOR_HASH_OBJECTS[index - adjective_count - animal_count]
}

generate_door_hash_name :: proc(door_id: u64, reroll: u32 = 0) -> string {
	key := door_id ~ u64(reroll) * 0x9e3779b97f4a7c15
	word_count := u64(len(DOOR_HASH_ADJECTIVES) + len(DOOR_HASH_ANIMALS) + len(DOOR_HASH_OBJECTS))
	first := door_hash_word(celestial_name_hash(key, 0x646f6f725f6f6e65) % word_count)
	second := door_hash_word(celestial_name_hash(key, 0x646f6f725f74776f) % word_count)
	third := door_hash_word(celestial_name_hash(key, 0x646f6f725f746872) % word_count)
	return fmt.tprintf("%s-%s-%s", first, second, third)
}

generate_solar_system_names :: proc(
	system: Solar_System,
	config: Celestial_Name_Config = {planet_scheme = .Systemic, max_length = 24},
	reroll: u32 = 0,
) -> Solar_System_Names {
	style := celestial_style_for_seed(system.seed ~ u64(reroll), config.style)
	result := Solar_System_Names {
		style         = style,
		planet_scheme = config.planet_scheme,
		planet_count  = system.planet_count,
	}
	result.proper_name = generate_system_name(system.seed, config, reroll)
	result.star_name = generate_star_name(system.seed, config, reroll)
	for i in 0 ..< system.star_count do result.star_names[i] = fmt.tprintf("%s %c", result.star_name, u8('A' + i))
	result.catalog = {
		prefix = CATALOG_PREFIXES[celestial_name_hash(system.seed, 0x636174616c6f67) % len(CATALOG_PREFIXES)],
		number = u32(1000 + celestial_name_hash(system.seed, 0x6e756d626572) % 899000),
	}
	for index in 0 ..< system.planet_count {
		result.planet_designations[index] = {
			prefix    = result.catalog.prefix,
			number    = result.catalog.number,
			component = u8('b' + index),
		}
		if config.planet_scheme == .Orbital {
			result.planet_names[index] = fmt.tprintf("%s %c", result.star_name, u8('b' + index))
			continue
		}
		planet_config := config
		if config.planet_scheme == .Individual {
			planet_config.style = .Any
		} else {
			planet_config.style = style
		}
		for attempt in u32(0) ..< u32(len(PLANET_NAMES_NATURAL)) {
			candidate := generate_planet_name(
				system.seed ~ u64(style),
				index,
				planet_config,
				reroll + attempt,
			)
			duplicate := false
			for prior in result.planet_names[:index] do if candidate == prior {duplicate = true; break}
			if !duplicate {result.planet_names[index] = candidate; break}
		}
	}
	return result
}

system_body_name :: proc(system: Solar_System, ref: Celestial_Body_Ref) -> string {
	names := generate_solar_system_names(system)
	switch ref.kind {case .Barycenter:
		return names.proper_name; case .Star:
		if ref.index >= 0 && ref.index < system.star_count do return names.star_names[ref.index]; case .Planet:
		if ref.index >= 0 && ref.index < system.planet_count do return names.planet_names[ref.index]; case .Moon:
		return fmt.tprintf("%s moon %d", names.proper_name, ref.index + 1); case .Asteroid:
		return fmt.tprintf(
			"%s minor body %d",
			names.proper_name,
			ref.index + 1,
		); case .Central_Black_Hole:
		return "Galactic nucleus"; case .None:}
	return "Unknown body"
}

system_body_designation :: proc(system: Solar_System, ref: Celestial_Body_Ref) -> string {
	names := generate_solar_system_names(system)
	switch ref.kind {case .Barycenter:
		return format_catalog_designation(names.catalog); case .Star:
		if ref.index >= 0 && ref.index < system.star_count do return fmt.tprintf("%s %c", format_catalog_designation(names.catalog), u8('A' + ref.index)); case .Planet:
		if ref.index >= 0 && ref.index < system.planet_count do return format_catalog_designation(names.planet_designations[ref.index]); case .Moon:
		return fmt.tprintf(
			"%s-M%d",
			format_catalog_designation(names.catalog),
			ref.index + 1,
		); case .Asteroid:
		return fmt.tprintf(
			"%s-X%d",
			format_catalog_designation(names.catalog),
			ref.index + 1,
		); case .Central_Black_Hole:
		return "NUCLEUS"; case .None:}
	return "UNRESOLVED"
}

