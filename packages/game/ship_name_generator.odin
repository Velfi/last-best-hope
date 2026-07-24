package game

import "core:fmt"
import "core:strings"

// Style selects vocabulary while Format selects grammatical construction.
// Either may remain Any to search the complete deterministic candidate space.
Ship_Name_Style :: enum u8 {
	Any,
	Civic,
	Hearth,
	Natural,
	Navigational,
	Testament,
}

Ship_Name_Format :: enum u8 {
	Any,
	Authored,
	Civic_Compound,
	Natural_Compound,
	Navigational_Compound,
	Testament_Compound,
	Definite_Title,
	Possessive,
	Conjunction,
	Of_Construction,
	Numbered,
	Declarative,
}

SHIP_NAME_COMPONENT_WIDTH :: 8
SHIP_NAME_GENERATED_FORMATS :: 10
SHIP_NAME_CANDIDATE_COUNT ::
	len(SHIP_GENERATOR_NAMES) +
	SHIP_NAME_GENERATED_FORMATS * SHIP_NAME_COMPONENT_WIDTH * SHIP_NAME_COMPONENT_WIDTH

SHIP_NAME_CIVIC_LEFT := [8]string {
	"Common",
	"Mutual",
	"Open",
	"Shared",
	"Public",
	"Kindred",
	"Free",
	"United",
}
SHIP_NAME_CIVIC_RIGHT := [8]string {
	"Accord",
	"Assembly",
	"Compact",
	"Council",
	"Hand",
	"Labor",
	"Purpose",
	"Trust",
}
SHIP_NAME_NATURAL_LEFT := [8]string {
	"Ashen",
	"Blue",
	"Bronze",
	"Cloud",
	"Golden",
	"Green",
	"Pale",
	"White",
}
SHIP_NAME_NATURAL_RIGHT := [8]string {
	"Cedar",
	"Current",
	"Finch",
	"Heron",
	"Meadow",
	"Orchard",
	"Rain",
	"Willow",
}
SHIP_NAME_NAV_LEFT := [8]string{"Aft", "Cross", "Far", "First", "High", "Long", "Outer", "True"}
SHIP_NAME_NAV_RIGHT := [8]string {
	"Bearing",
	"Compass",
	"Horizon",
	"Meridian",
	"North",
	"Passage",
	"Vector",
	"Wake",
}
SHIP_NAME_TESTAMENT_LEFT := [8]string {
	"Clear",
	"Final",
	"First",
	"Honest",
	"Open",
	"Patient",
	"Quiet",
	"Second",
}
SHIP_NAME_TESTAMENT_RIGHT := [8]string {
	"Account",
	"Grace",
	"Ledger",
	"Memory",
	"Promise",
	"Record",
	"Resolve",
	"Witness",
}
SHIP_NAME_TITLE_LEFT := [8]string {
	"Broad",
	"Broken",
	"Common",
	"Far",
	"Mended",
	"Old",
	"Small",
	"Unfinished",
}
SHIP_NAME_TITLE_RIGHT := [8]string {
	"Bell",
	"Bridge",
	"Harbor",
	"Lantern",
	"Road",
	"Table",
	"Thread",
	"Window",
}
SHIP_NAME_POSSESSORS := [8]string {
	"Amari",
	"Bren",
	"Cato",
	"Darya",
	"Elian",
	"Hester",
	"Imani",
	"Tomas",
}
SHIP_NAME_POSSESSIONS := [8]string {
	"Compass",
	"Garden",
	"Lantern",
	"Mark",
	"Measure",
	"Promise",
	"Rest",
	"Wake",
}
SHIP_NAME_PAIR_LEFT := [8]string {
	"Bell",
	"Cedar",
	"Compass",
	"Fire",
	"Garden",
	"Harbor",
	"Salt",
	"Stone",
}
SHIP_NAME_PAIR_RIGHT := [8]string {
	"Ash",
	"Dawn",
	"Light",
	"Rain",
	"River",
	"Thread",
	"Water",
	"Willow",
}
SHIP_NAME_OF_LEFT := [8]string {
	"Measure",
	"Promise",
	"Record",
	"Shelter",
	"Thread",
	"Voice",
	"Weight",
	"Witness",
}
SHIP_NAME_OF_RIGHT := [8]string{"Ash", "Dawn", "Earth", "Home", "Rain", "Stars", "Water", "Winter"}
SHIP_NAME_NUMBERED_LEFT := [8]string {
	"Signal",
	"Measure",
	"Lantern",
	"Harbor",
	"Witness",
	"Compass",
	"Garden",
	"Bell",
}
SHIP_NAME_NUMBERS := [8]string{"One", "Two", "Three", "Five", "Seven", "Nine", "Eleven", "Forty"}
SHIP_NAME_DECLARATIVE_LEFT := [8]string {
	"We",
	"They",
	"All",
	"None",
	"Home",
	"Mercy",
	"Memory",
	"Dawn",
}
SHIP_NAME_DECLARATIVE_RIGHT_PLURAL := [8]string {
	"Abide",
	"Answer",
	"Endure",
	"Return",
	"Remain",
	"Remember",
	"Wait",
	"Watch",
}
SHIP_NAME_DECLARATIVE_RIGHT_SINGULAR := [8]string {
	"Abides",
	"Answers",
	"Endures",
	"Returns",
	"Remains",
	"Remembers",
	"Waits",
	"Watches",
}

SHIP_NAME_SUGGESTION_COUNT :: 12

Ship_Name_Config :: struct {
	style:          Ship_Name_Style,
	format:         Ship_Name_Format,
	role:           Role,
	role_locked:    bool,
	excluded_names: []string,
	prefix:         string, // optional fleet or service designation, e.g. "FNS"
}

ship_name_candidate :: proc(index: int) -> (string, Ship_Name_Format) {
	if index < 0 || index >= SHIP_NAME_CANDIDATE_COUNT do return "", .Any
	if index < len(SHIP_GENERATOR_NAMES) {
		authored_names := SHIP_GENERATOR_NAMES
		return authored_names[index], .Authored
	}
	local := index - len(SHIP_GENERATOR_NAMES)
	format_index := local / (SHIP_NAME_COMPONENT_WIDTH * SHIP_NAME_COMPONENT_WIDTH)
	pair := local % (SHIP_NAME_COMPONENT_WIDTH * SHIP_NAME_COMPONENT_WIDTH)
	left, right := pair / SHIP_NAME_COMPONENT_WIDTH, pair % SHIP_NAME_COMPONENT_WIDTH
	switch format_index {
	case 0:
		return fmt.tprintf("%s %s", SHIP_NAME_CIVIC_LEFT[left], SHIP_NAME_CIVIC_RIGHT[right]),
			.Civic_Compound
	case 1:
		return fmt.tprintf("%s %s", SHIP_NAME_NATURAL_LEFT[left], SHIP_NAME_NATURAL_RIGHT[right]),
			.Natural_Compound
	case 2:
		return fmt.tprintf("%s %s", SHIP_NAME_NAV_LEFT[left], SHIP_NAME_NAV_RIGHT[right]),
			.Navigational_Compound
	case 3:
		return fmt.tprintf(
				"%s %s",
				SHIP_NAME_TESTAMENT_LEFT[left],
				SHIP_NAME_TESTAMENT_RIGHT[right],
			),
			.Testament_Compound
	case 4:
		return fmt.tprintf("The %s %s", SHIP_NAME_TITLE_LEFT[left], SHIP_NAME_TITLE_RIGHT[right]),
			.Definite_Title
	case 5:
		return fmt.tprintf("%s's %s", SHIP_NAME_POSSESSORS[left], SHIP_NAME_POSSESSIONS[right]),
			.Possessive
	case 6:
		return fmt.tprintf("%s and %s", SHIP_NAME_PAIR_LEFT[left], SHIP_NAME_PAIR_RIGHT[right]),
			.Conjunction
	case 7:
		return fmt.tprintf("%s of %s", SHIP_NAME_OF_LEFT[left], SHIP_NAME_OF_RIGHT[right]),
			.Of_Construction
	case 8:
		return fmt.tprintf("%s %s", SHIP_NAME_NUMBERED_LEFT[left], SHIP_NAME_NUMBERS[right]),
			.Numbered
	case 9:
		// We, They, and All take the base verb form; the remaining subjects are
		// singular. Keeping both tables aligned preserves the deterministic
		// candidate ordering while producing grammatical names.
		verbs := SHIP_NAME_DECLARATIVE_RIGHT_SINGULAR[:]
		if left < 3 do verbs = SHIP_NAME_DECLARATIVE_RIGHT_PLURAL[:]
		return fmt.tprintf("%s %s", SHIP_NAME_DECLARATIVE_LEFT[left], verbs[right]), .Declarative
	}
	return "", .Any
}

ship_name_format_matches :: proc(actual, requested: Ship_Name_Format) -> bool {
	return requested == .Any || actual == requested
}

default_ship_name_config :: proc() -> Ship_Name_Config {
	return {}
}

ship_name_contains_any :: proc(name: string, words: []string) -> bool {
	for word in words do if strings.contains(name, word) do return true
	return false
}

ship_name_matches_style :: proc(name: string, style: Ship_Name_Style) -> bool {
	switch style {
	case .Any:
		return true
	case .Civic:
		return ship_name_contains_any(
			name,
			[]string {
				"Allotment",
				"Assembly",
				"Civic",
				"Common",
				"Concordance",
				"Covenant",
				"Every Hand",
				"Labor",
				"Mutual",
				"Open Door",
				"Our Share",
				"Shared",
				"Table for",
			},
		)
	case .Hearth:
		return ship_name_contains_any(
			name,
			[]string {
				"Allotment",
				"Field",
				"Harbor",
				"Hearth",
				"Home",
				"Shelter",
				"Reliquary",
				"Orchard",
				"Seedkeeper",
				"Spare Key",
				"Stone Soup",
			},
		)
	case .Natural:
		return ship_name_contains_any(
			name,
			[]string {
				"Amber",
				"Cedar",
				"Current",
				"Dawn",
				"Elm",
				"Finch",
				"Foxglove",
				"Heron",
				"Ilex",
				"Juniper",
				"Kestrel",
				"Larkspur",
				"Meadow",
				"Rain",
				"Star",
				"Tide",
				"Water",
				"Willow",
			},
		)
	case .Navigational:
		return ship_name_contains_any(
			name,
			[]string {
				"Atlas",
				"Baseline",
				"Bearing",
				"Compass",
				"Fathom",
				"Horizon",
				"Mark",
				"Meridian",
				"North",
				"Orbit",
				"Parallax",
				"Passage",
				"Plumb",
				"Sounding",
				"Vector",
				"Wake",
				"Waymark",
				"Westing",
				"Zenith",
			},
		)
	case .Testament:
		return ship_name_contains_any(
			name,
			[]string {
				"Account",
				"Almanac",
				"Grace",
				"Ledger",
				"Memory",
				"Principle",
				"Promise",
				"Record",
				"Register",
				"Resolve",
				"Testament",
				"Trust",
				"Witness",
			},
		)
	}
	return true
}

ship_name_role_affinity :: proc(name: string, role: Role) -> i32 {
	switch role {
	case .Habitat:
		if ship_name_contains_any(name, []string{"Common", "Door", "Every Hand", "Harbor", "Hearth", "Shelter", "Spare Key", "Table for"}) do return 3
	case .Agriculture:
		if ship_name_contains_any(name, []string{"Allotment", "Cedar", "Field", "Orchard", "Rain", "Seed", "Water"}) do return 3
	case .Foundry:
		if ship_name_contains_any(name, []string{"Anvil", "Brass", "Forge", "Iron", "Labor", "Mended", "Quarry", "Repair", "Tempered"}) do return 3
	case .Archive:
		if ship_name_contains_any(name, []string{"Account", "Almanac", "Atlas", "Field Note", "Ledger", "Memory", "Record", "Register", "Reliquary", "Testament", "Witness"}) do return 3
	case .Hospital:
		if ship_name_contains_any(name, []string{"Conduct", "Grace", "Kindred", "Mercy", "Opinion", "Patient", "Prudence", "Shelter"}) do return 3
	case .Survey:
		if ship_name_contains_any(name, []string{"Baseline", "Cartographer", "Atlas", "Bearing", "Compass", "Fathom", "Horizon", "Mark", "Meridian", "Parallax", "Reference", "Signal", "Sounding", "Variable", "Vector", "Zenith"}) do return 3
	case .Escort:
		if ship_name_contains_any(name, []string{"Crossing Guard", "Good Knife", "Night Watch", "Resolute", "Safe Conduct", "Tempered", "Unbroken", "Vigilant", "Wing"}) do return 3
	case .Colony:
		if ship_name_contains_any(name, []string{"Allotment", "Dawn", "Field", "Harbor", "Hearth", "Horizon", "Morrow", "Orchard", "Promise", "Shelter"}) do return 3
	}
	return 0
}

ship_name_is_excluded :: proc(name: string, excluded_names: []string) -> bool {
	for excluded in excluded_names do if strings.equal_fold(name, excluded) do return true
	return false
}

ship_name_prefix_is_valid :: proc(prefix: string) -> bool {
	if prefix == "" do return true
	if len(prefix) > 8 || prefix[0] == ' ' || prefix[len(prefix) - 1] == ' ' do return false
	for byte in prefix {
		if byte <= ' ' || byte == '/' || byte == '\\' do return false
	}
	return true
}

ship_name_with_prefix :: proc(name, prefix: string) -> string {
	if prefix == "" || !ship_name_prefix_is_valid(prefix) do return name
	return fmt.tprintf("%s %s", prefix, name)
}

ship_name_is_valid :: proc(name: string) -> bool {
	if name == "" || name[0] == ' ' || name[len(name) - 1] == ' ' do return false
	for byte in name {
		if byte < ' ' || byte == '/' || byte == '\\' do return false
	}
	return true
}

ship_name_candidate_allowed :: proc(
	name: string,
	format: Ship_Name_Format,
	config: Ship_Name_Config,
) -> bool {
	display_name := ship_name_with_prefix(name, config.prefix)
	return(
		ship_name_is_valid(display_name) &&
		ship_name_format_matches(format, config.format) &&
		ship_name_matches_style(name, config.style) &&
		!ship_name_is_excluded(display_name, config.excluded_names) \
	)
}

ship_name_score :: proc(
	seed: u64,
	reroll: u32,
	index: int,
	name: string,
	config: Ship_Name_Config,
) -> u64 {
	key := seed ~ (u64(reroll) + 1) * 0x9e3779b97f4a7c15 ~ (u64(index) + 1) * 0xbf58476d1ce4e5b9
	score := ship_construction_visual_mix(key)
	if config.role_locked {
		// Affinity is a preference rather than a hard filter: every role retains
		// the full voice of the fleet, while fitting names surface more often.
		score = (score >> 2) + (u64(ship_name_role_affinity(name, config.role)) << 62)
	}
	return score
}

generate_ship_name :: proc(seed: u64, config: Ship_Name_Config = {}, reroll: u32 = 0) -> string {
	best := ""
	best_score := u64(0)
	for index in 0 ..< SHIP_NAME_CANDIDATE_COUNT {
		name, format := ship_name_candidate(index)
		if !ship_name_candidate_allowed(name, format, config) do continue
		score := ship_name_score(seed, reroll, index, name, config)
		if best == "" || score > best_score {best = name; best_score = score}
	}
	// Impossible filters degrade explicitly to the unrestricted authored pool.
	if best == "" {
		fallback := default_ship_name_config()
		fallback.prefix = config.prefix
		return generate_ship_name(seed, fallback, reroll)
	}
	return ship_name_with_prefix(best, config.prefix)
}

suggest_ship_names :: proc(
	seed: u64,
	config: Ship_Name_Config = {},
) -> [SHIP_NAME_SUGGESTION_COUNT]string {
	result: [SHIP_NAME_SUGGESTION_COUNT]string
	used := 0
	for reroll in u32(0) ..< u32(SHIP_NAME_CANDIDATE_COUNT) {
		candidate := generate_ship_name(seed, config, reroll)
		duplicate := false
		for prior in result[:used] do if prior == candidate {duplicate = true; break}
		if duplicate do continue
		result[used] = candidate
		used += 1
		if used == len(result) do break
	}
	return result
}

fleet_ship_names :: proc(seed: u64, roles: [MAX_SHIPS]Role, prefix: string) -> [MAX_SHIPS]string {
	result: [MAX_SHIPS]string
	for role, index in roles {
		config := default_ship_name_config()
		config.role = role
		config.role_locked = true
		config.prefix = prefix
		for reroll in u32(0) ..< u32(SHIP_NAME_CANDIDATE_COUNT) {
			candidate := generate_ship_name(
				seed ~ u64(index + 1) * 0x94d049bb133111eb,
				config,
				reroll,
			)
			duplicate := false
			for prior in result[:index] do if prior == candidate {duplicate = true; break}
			if !duplicate {result[index] = candidate; break}
		}
	}
	return result
}

fleet_identity_ship_names :: proc(seed: u64, prefix: string) -> [MAX_SHIPS]string {
	assert(prefix != "" && ship_name_prefix_is_valid(prefix))
	result: [MAX_SHIPS]string
	for _, index in result {
		config := default_ship_name_config()
		config.prefix = prefix
		config.excluded_names = result[:index]
		result[index] = generate_ship_name(seed ~ u64(index + 1) * 0x94d049bb133111eb, config)
	}
	return result
}
