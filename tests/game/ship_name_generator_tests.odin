package game_tests

import "core:testing"
import "core:fmt"
import "core:strings"

@(test)
ship_name_prefixes_are_validated_formatted_and_excluded_as_displayed :: proc(t: ^testing.T) {
	plain := generate_ship_name(7719)
	config := default_ship_name_config()
	config.prefix = "FNS"
	prefixed := generate_ship_name(7719, config)
	testing.expect_value(t, prefixed, fmt.tprintf("FNS %s", plain))
	testing.expect(t, ship_name_is_valid(prefixed))

	config.excluded_names = []string{prefixed}
	testing.expect(t, generate_ship_name(7719, config) != prefixed)
	config.prefix = "bad prefix"
	testing.expect_value(t, generate_ship_name(7719, config), plain)
}

@(test)
generated_society_identity_supplies_every_ship_prefix :: proc(t: ^testing.T) {
	for identity in 0 ..< 4 {
		draft := civilization_setup_generate(9000 + u64(identity))
		draft.choices[int(Setup_Field.Identity_One)] = identity
		prefix := civilization_ship_prefix(&draft)
		campaign: Campaign
		ok, _ := civilization_setup_commit(&draft, &campaign)
		testing.expect(t, ok)
		for ship in campaign.ships[:campaign.ship_count] {
			testing.expect(t, strings.has_prefix(ship.name, fmt.tprintf("%s ", prefix)))
		}
	}
}

@(test)
ship_name_generator_is_deterministic_thematic_and_rerollable :: proc(t: ^testing.T) {
	config := default_ship_name_config()
	config.style = .Navigational
	first := generate_ship_name(7719, config)
	testing.expect_value(t, first, generate_ship_name(7719, config))
	testing.expect(t, ship_name_matches_style(first, .Navigational))
	suggestions := suggest_ship_names(7719, config)
	for name, index in suggestions {
		testing.expect(t, name != "" && ship_name_matches_style(name, .Navigational))
		for prior in suggestions[:index] do testing.expect(t, name != prior)
	}
}

@(test)
ship_name_generator_honors_exclusions_and_safe_fallback :: proc(t: ^testing.T) {
	excluded := []string{"Common Hearth", "Far Harbor"}
	config := default_ship_name_config()
	config.excluded_names = excluded
	for reroll in u32(0) ..< 32 {
		name := generate_ship_name(42, config, reroll)
		testing.expect(t, name != excluded[0] && name != excluded[1])
	}
	config.style = .Civic
	config.format = .Natural_Compound
	testing.expect(t, generate_ship_name(42, config) != "")
}

@(test)
fleet_ship_name_generation_is_unique_and_role_aware :: proc(t: ^testing.T) {
	roles := [MAX_SHIPS]Role {
		.Habitat,
		.Agriculture,
		.Foundry,
		.Archive,
		.Hospital,
		.Survey,
		.Escort,
		.Colony,
		.Survey,
		.Escort,
		.Habitat,
		.Colony,
	}
	names := fleet_ship_names(90210, roles, "FCS")
	for name, index in names {
		testing.expect(t, ship_name_is_valid(name))
		for prior in names[:index] do testing.expect(t, name != prior)
	}
	testing.expect_value(t, names, fleet_ship_names(90210, roles, "FCS"))
}

@(test)
ship_name_formats_are_large_distinct_and_selectable :: proc(t: ^testing.T) {
	testing.expect(t, SHIP_NAME_CANDIDATE_COUNT >= 450)
	for index in 0 ..< SHIP_NAME_CANDIDATE_COUNT {
		name, format := ship_name_candidate(index)
		testing.expect(t, name != "" && format != .Any && ship_name_is_valid(name))
		for prior in 0 ..< index {
			prior_name, _ := ship_name_candidate(prior)
			testing.expect(t, name != prior_name)
		}
	}
	for format_value in 1 ..= int(Ship_Name_Format.Declarative) {
		config := default_ship_name_config()
		config.format = Ship_Name_Format(format_value)
		for name in suggest_ship_names(7719 + u64(format_value), config) {
			testing.expect(t, name != "")
			matched := false
			for index in 0 ..< SHIP_NAME_CANDIDATE_COUNT {
				candidate, format := ship_name_candidate(index)
				if candidate == name {matched = format == config.format; break}
			}
			testing.expect(t, matched)
		}
	}
}

@(test)
declarative_ship_names_agree_with_their_subjects :: proc(t: ^testing.T) {
	declarative_start :=
		len(SHIP_GENERATOR_NAMES) +
		(SHIP_NAME_GENERATED_FORMATS - 1) * SHIP_NAME_COMPONENT_WIDTH * SHIP_NAME_COMPONENT_WIDTH
	we_remain, _ := ship_name_candidate(declarative_start + 4)
	they_watch, _ := ship_name_candidate(declarative_start + SHIP_NAME_COMPONENT_WIDTH + 7)
	home_remains, _ := ship_name_candidate(declarative_start + 4 * SHIP_NAME_COMPONENT_WIDTH + 4)
	testing.expect_value(t, we_remain, "We Remain")
	testing.expect_value(t, they_watch, "They Watch")
	testing.expect_value(t, home_remains, "Home Remains")
}
