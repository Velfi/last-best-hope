package game

import "core:fmt"

// Renderer-facing contracts.  Every preview in this file is deliberately
// read-only: presentation may ask the same question any number of times
// without consuming campaign randomness.

Setup_Field :: enum {
	Identity_One,
	Identity_Two,
	Capability_One,
	Capability_Two,
	Value_One,
	Value_Two,
}

Civilization_Setup_Draft :: struct {
	seed:                 u64,
	rng_state:            u64,
	length:               Chronicle_Length,
	ruleset:              Ruleset,
	story_tempo:          Story_Tempo,
	material_pressure:    Material_Pressure,
	consequence_severity: Consequence_Severity,
	choices:              [6]int,
	locked:               [6]bool,
	loss_index:           int,
	preserved_index:      int,
	founding_choice:      int,
}

RULESET_PRESET_NAMES := [4]string{"FLEET PARITY", "HEROIC LINE", "SPACE OPERA", "MYTHIC ARMADA"}
RULESET_PRESET_HEROISM := [4]i32{1, 8, 64, 1000}
RULESET_PRESET_DESCRIPTIONS := [4]string {
	"One player ship is matched by about one equivalent enemy ship.",
	"One player ship can break a flotilla averaging eight enemy ships.",
	"Player ships cut through formations averaging sixty-four enemies each.",
	"Each player ship stands against an armada averaging one thousand enemies.",
}
STORY_TEMPO_NAMES := [3]string{"MEASURED", "SPACIOUS", "VOLATILE"}
STORY_TEMPO_DESCRIPTIONS := [3]string {
	"Major beats leave one clear season; new petitions arrive at a varied pace.",
	"Major beats leave at least two clear seasons; quiet seasons and single petitions are more common.",
	"Major beats may occur in consecutive seasons; two or three new petitions are common.",
}

ruleset_apply_preset :: proc(d: ^Civilization_Setup_Draft, preset: Ruleset_Preset) {
	if preset == .Custom {d.ruleset.preset = .Custom; return}
	i := int(preset); if i < 0 || i >= len(RULESET_PRESET_HEROISM) do return
	d.ruleset = {
		preset        = preset,
		heroism_scale = RULESET_PRESET_HEROISM[i],
	}
}

ruleset_set_heroism :: proc(d: ^Civilization_Setup_Draft, scale: i32) {
	d.ruleset.heroism_scale = clamp(scale, 1, 1000); d.ruleset.preset = .Custom
	for value, i in RULESET_PRESET_HEROISM do if value == d.ruleset.heroism_scale do d.ruleset.preset = Ruleset_Preset(i)
}

SETUP_NAMES := [6][4]string {
	{"Keepers of Ash", "Choir of Names", "Gardens of Memory", "The Unburied"},
	{"Many Kitchens", "Shared Night", "Pilgrim Houses", "Tide Ceremonies"},
	{"Fleetborn Adaptation", "Radiation-Hardened", "Low-Gravity Lineage", "Long Sleep Medicine"},
	{"Distributed Fabrication", "Living Hullcraft", "Machine Partnership", "Closed-Cycle Mastery"},
	{"No One Left Behind", "Truth Before Comfort", "Consent to Settle", "Shelter Is Sacred"},
	{"Shared Authority", "Open Archives", "The Fleet Endures", "Every Home Is Free"},
}

SETUP_DESCRIPTIONS := [6][4]string {
	{
		"The dead are remembered through objects carried between ships.",
		"Names are sung into a living communal record.",
		"Cuttings from every lost biome accompany the dead.",
		"No rite is complete until land is found.",
	},
	{
		"Ritual meals define community and hospitality.",
		"The fleet observes a common artificial night.",
		"Households reorganize around each vessel they inhabit.",
		"Water and return are central ritual metaphors.",
	},
	{
		"Long exposure to artificial gravity improves tolerance of marginal habitats.",
		"The population tolerates high-radiation environments.",
		"Bodies thrive in weak gravity but require care planetside.",
		"Safe suspension extends the fleet's practical range.",
	},
	{
		"Foundries can substitute for one another at reduced efficiency.",
		"Engineered organisms maintain some ship systems.",
		"Machine minds retain critical operational expertise.",
		"Life support loses less material over long passages.",
	},
	{
		"Distress calls create a public expectation of rescue.",
		"Leaders are expected to disclose dangerous knowledge.",
		"No community should be planted without meaningful consent.",
		"Refuge is owed even when it is costly.",
	},
	{
		"Communities expect a voice in fleet command.",
		"Knowledge belongs to the whole diaspora.",
		"Fragmentation is treated as an existential failure.",
		"Settlements must become sovereign rather than possessions.",
	},
}

// These summaries expose the fleet-generation pressure that every founding
// attribute applies. The cultural description remains fiction-facing; this
// line tells the player what accepting or rerolling it changes immediately.
SETUP_FLEET_EFFECTS := [6][4]string {
	{
		"Favors preservation ships.",
		"Strongly favors preservation ships.",
		"Favors preservation and survival ships.",
		"Favors settlement ships.",
	},
	{
		"Favors survival ships.",
		"Favors survival and preservation ships.",
		"Favors settlement ships.",
		"Favors exploration ships.",
	},
	{
		"Favors settlement and exploration ships.",
		"Favors settlement and security ships.",
		"Strongly favors exploration ships.",
		"Strongly favors exploration ships.",
	},
	{
		"Favors industry ships; sets distributed construction.",
		"Favors survival ships; sets living-hull construction.",
		"Favors industry and preservation ships; sets machine-partnered construction.",
		"Favors survival ships; sets closed-cycle construction.",
	},
	{
		"Favors survival and security ships; later choices may test this value.",
		"Favors preservation ships; later choices may test this value.",
		"Favors settlement ships; later choices may test this value.",
		"Favors survival and settlement ships; later choices may test this value.",
	},
	{
		"Favors survival ships; later choices may test this value.",
		"Favors preservation and exploration ships; later choices may test this value.",
		"Favors survival and security ships; later choices may test this value.",
		"Favors settlement ships; later choices may test this value.",
	},
}

setup_attribute_effect :: proc(d: ^Civilization_Setup_Draft, index: int) -> string {
	if index < 0 || index >= len(d.choices) do return ""
	if index >= 4 do return "A public expectation; it grants no passive bonus and may be tested by later decisions."
	return SETUP_FLEET_EFFECTS[index][clamp(d.choices[index], 0, 3)]
}

LOSS_NAMES := [4]string {
	"The Burning Sky",
	"The Closed Gates",
	"The Severed Fleet",
	"The Unanswered Silence",
}
LOSS_RECORDS := [4]string {
	"The home system was lost to a cascading catastrophe.",
	"The fleet departed after its people were expelled.",
	"The fleet departed through the fracture of a civil war.",
	"The fleet departed after an event whose cause remains unresolved.",
}
PRESERVED_NAMES := [4]string {
	"Seed and Genetic Banks",
	"Scientific Corpora",
	"Cultural Archives",
	"Machine Memories",
}
FOUNDING_PRECEDENTS := [4]Precedent_Kind {
	.Shared_Authority,
	.Emergency_Command,
	.Open_Archives,
	.No_One_Left_Behind,
}
FOUNDING_RECORDS := [4]string {
	"Every community received a voice in fleet authority.",
	"Emergency command was retained for the crossing.",
	"The surviving archives were opened to the whole fleet.",
	"The fleet committed itself to answer those left in danger.",
}

setup_value_kind :: proc(
	d: ^Civilization_Setup_Draft,
	slot: int,
) -> Value_Kind {return Value_Kind(clamp(d.choices[4 + slot], 0, 7))}
setup_attribute_name :: proc(d: ^Civilization_Setup_Draft, index: int) -> string {if index >= 4 do return value_name(setup_value_kind(d, index - 4))
	return SETUP_NAMES[index][clamp(d.choices[index], 0, 3)]}
setup_attribute_description :: proc(
	d: ^Civilization_Setup_Draft,
	index: int,
) -> string {if index >= 4 do return value_claim(setup_value_kind(d, index - 4)); return(
		SETUP_DESCRIPTIONS[index][clamp(d.choices[index], 0, 3)] \
	)}

setup_memory_ship :: proc(c: ^Campaign, preferred: [2]Role, used: ^[MAX_SHIPS]bool) -> int {
	for role in preferred {
		for ship, i in c.ships[:c.ship_count] do if !used[i] && ship.role == role {used[i] = true; return i}
	}
	for _, i in c.ships[:c.ship_count] do if !used[i] {used[i] = true; return i}
	return -1
}

attach_setup_memory :: proc(
	c: ^Campaign,
	event_sequence: u64,
	preferred: [2]Role,
	used: ^[MAX_SHIPS]bool,
	history: string,
) {
	ship_at := setup_memory_ship(c, preferred, used)
	event_at := event_index_by_sequence(c, event_sequence)
	if ship_at < 0 || event_at < 0 do return
	ship := c.ships[ship_at]
	append_ship_memory(c, ship.id, c.events[event_at], 0)
	add_ship_history(c, ship.id, history)
}

apply_setup_history :: proc(d: ^Civilization_Setup_Draft, c: ^Campaign) {
	used_memory_ships: [MAX_SHIPS]bool
	c.loss = Loss_Kind(d.loss_index)
	c.preserved_inheritance = Preserved_Inheritance(d.preserved_index)
	record_event(c, .Chronicle_Started, LOSS_RECORDS[d.loss_index])
	claim_event := c.event_sequence
	first, second := setup_value_kind(d, 0), setup_value_kind(d, 1)
	c.values[0] = {
		kind          = first,
		status        = .Claimed,
		claimed_event = claim_event,
	}
	c.values[1] = {
		kind          = second,
		status        = .Claimed,
		claimed_event = claim_event,
	}
	loss_roles: [2]Role
	switch c.loss {
	case .Catastrophe:
		loss_roles = {.Hospital, .Habitat}
	case .Expulsion:
		loss_roles = {.Colony, .Escort}
	case .Civil_War:
		loss_roles = {.Escort, .Hospital}
	case .Unknown_Event:
		loss_roles = {.Survey, .Archive}
	}
	attach_setup_memory(
		c,
		c.event_sequence,
		loss_roles,
		&used_memory_ships,
		"Carries the fleet's record of the Loss.",
	)
	inheritance_roles: [2]Role
	switch c.preserved_inheritance {
	case .Seed_Banks:
		inheritance_roles = {.Agriculture, .Colony}
		c.archives[0].integrity = 100
		fleet_stock_gain(c, {supplies = 10})
	case .Scientific_Corpora:
		inheritance_roles = {.Archive, .Survey}
		c.archives[1].integrity = 100
		fleet_stock_gain(c, {supplies = 12})
	case .Cultural_Archives:
		inheritance_roles = {.Archive, .Habitat}
		c.archives[2].integrity = 100
		c.archives[3].integrity = 100
		c.strategic.cohesion = min(c.strategic.cohesion + 8, 100)
	case .Machine_Memories:
		inheritance_roles = {.Foundry, .Archive}
		c.archives[5].integrity = 100
		fleet_stock_gain(c, {supplies = 10})
	}
	record_event(
		c,
		.Resource_Changed,
		"One inheritance received complete protection during the evacuation.",
		value = i32(d.preserved_index),
	)
	attach_setup_memory(
		c,
		c.event_sequence,
		inheritance_roles,
		&used_memory_ships,
		"Guarded the preserved inheritance during evacuation.",
	)
	scenario := founding_value_scenario(first, second)
	chosen := d.founding_choice == 0 ? first : d.founding_choice == 1 ? second : first
	detail :=
		d.founding_choice < 2 ? founding_value_option(chosen) : "The question was referred to the first council with both claims preserved."
	founding_cost: i32 =
		d.founding_choice < 2 ? 4 : 2; _ = fleet_stock_spend(c, {supplies = i64(min(founding_cost, fleet_supply(c)))}, .Emergency)
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf("%s %s", scenario.title, detail),
		value = i32(d.founding_choice),
		cause_sequence = claim_event,
	)
	c.founding_decision_event = c.event_sequence
	if d.founding_choice < 2 {
		kind := value_primary_precedent(chosen)
		id, ok := enact_precedent_from_decision(
			c,
			{
				kind = kind,
				source_decision = c.founding_decision_event,
				detail = detail,
				defining = true,
			},
		)
		if ok do _ = record_value_test(c, chosen, true, c.founding_decision_event, id)
	} else {
		_ = record_value_test(c, first, true, c.founding_decision_event)
		_ = record_value_test(c, second, true, c.founding_decision_event)
	}
	precedent_roles := [2]Role{.Habitat, .Archive}
	attach_setup_memory(
		c,
		c.founding_decision_event,
		precedent_roles,
		&used_memory_ships,
		"Witnessed the fleet's founding decision.",
	)
}

setup_next :: proc(state: ^u64) -> u64 {
	x := state^
	if x == 0 do x = 1
	x ~= x << u64(13); x ~= x >> u64(7); x ~= x << u64(17)
	if x == 0 do x = 1
	state^ = x
	return x
}

civilization_setup_generate :: proc(
	seed: u64,
	length := Chronicle_Length.Standard,
) -> Civilization_Setup_Draft {
	actual_seed := seed; if actual_seed == 0 do actual_seed = 1
	d := Civilization_Setup_Draft {
		seed                 = actual_seed,
		rng_state            = actual_seed,
		length               = length,
		ruleset              = DEFAULT_RULESET,
		story_tempo          = .Measured,
		material_pressure    = .Standard,
		consequence_severity = .Standard,
	}
	for &choice, i in d.choices do choice = int(setup_next(&d.rng_state) % (i < 4 ? 4 : 8))
	if d.choices[5] == d.choices[4] do d.choices[5] = (d.choices[5] + 1) % 8
	d.loss_index = int(setup_next(&d.rng_state) % 4)
	d.preserved_index = int(setup_next(&d.rng_state) % 4)
	d.founding_choice = int(setup_next(&d.rng_state) % 3)
	return d
}

civilization_setup_reroll :: proc(d: ^Civilization_Setup_Draft) {
	for &choice, i in d.choices {if !d.locked[i] do choice = int(setup_next(&d.rng_state) % (i < 4 ? 4 : 8))}
	if d.choices[5] == d.choices[4] && !d.locked[5] do d.choices[5] = (d.choices[5] + 1) % 8
}

civilization_setup_reroll_field :: proc(d: ^Civilization_Setup_Draft, field: Setup_Field) {
	i := int(
		field,
	); if !d.locked[i] {d.choices[i] = int(setup_next(&d.rng_state) % (i < 4 ? 4 : 8)); if i >= 4 && d.choices[5] == d.choices[4] do d.choices[i] = (d.choices[i] + 1) % 8}
}

// The first identity choice supplies the fleet's service tradition. These are
// cultural designations, not nation-state labels: they identify whose record a
// vessel belongs to without claiming that every community shares one polity.
civilization_ship_prefix :: proc(d: ^Civilization_Setup_Draft) -> string {
	prefixes := [4]string{"KAS", "CNS", "GMS", "TUS"}
	return prefixes[clamp(d.choices[int(Setup_Field.Identity_One)], 0, len(prefixes) - 1)]
}

civilization_setup_validate :: proc(d: ^Civilization_Setup_Draft) -> (bool, string) {
	if d.seed == 0 || d.rng_state == 0 do return false, "setup seed is invalid"
	if d.ruleset.heroism_scale < 1 || d.ruleset.heroism_scale > 1000 do return false, "heroism scale must be between 1 and 1000"
	for choice, i in d.choices do if choice < 0 || choice >= (i < 4 ? 4 : 8) do return false, "setup contains an unknown civilization attribute"
	if d.choices[4] == d.choices[5] do return false, "select two different values"
	if d.loss_index < 0 || d.loss_index >= 4 do return false, "the Loss is incomplete"
	if d.preserved_index < 0 || d.preserved_index >= 4 do return false, "preservation choice is incomplete"
	if d.founding_choice < 0 || d.founding_choice >= 3 do return false, "founding decision is incomplete"
	return true, "civilization is ready"
}

fleet_goals_from_setup :: proc(d: ^Civilization_Setup_Draft) -> Fleet_Goals {
	goals := balanced_fleet_goals()
	switch d.choices[0] {
	case 0:
		goals.preservation += 15
	case 1:
		goals.preservation += 20
	case 2:
		goals.preservation += 15; goals.survival += 10
	case 3:
		goals.settlement += 20
	}
	switch d.choices[1] {
	case 0:
		goals.survival += 15
	case 1:
		goals.survival += 10; goals.preservation += 10
	case 2:
		goals.settlement += 20
	case 3:
		goals.exploration += 15
	}
	switch d.choices[2] {
	case 0:
		goals.settlement += 15; goals.exploration += 10
	case 1:
		goals.settlement += 15; goals.security += 10
	case 2:
		goals.exploration += 20
	case 3:
		goals.exploration += 25
	}
	switch d.choices[3] {
	case 0:
		goals.industry += 25
	case 1:
		goals.survival += 20
	case 2:
		goals.industry += 15; goals.preservation += 15
	case 3:
		goals.survival += 25
	}
	switch Preserved_Inheritance(d.preserved_index) {
	case .Seed_Banks:
		goals.survival += 15; goals.settlement += 10
	case .Scientific_Corpora:
		goals.exploration += 20
	case .Cultural_Archives:
		goals.preservation += 20
	case .Machine_Memories:
		goals.industry += 20
	}
	goals.survival = clamp(goals.survival, 0, 100)
	goals.exploration = clamp(goals.exploration, 0, 100)
	goals.settlement = clamp(goals.settlement, 0, 100)
	goals.industry = clamp(goals.industry, 0, 100)
	goals.preservation = clamp(goals.preservation, 0, 100)
	goals.security = clamp(goals.security, 0, 100)
	return goals
}

civilization_setup_commit :: proc(d: ^Civilization_Setup_Draft, out: ^Campaign) -> (bool, string) {
	ok, message := civilization_setup_validate(d); if !ok do return false, message
	campaign_init(out, d.seed, d.length)
	out.ruleset = d.ruleset
	out.story_tempo = d.story_tempo
	out.material_pressure = d.material_pressure
	out.consequence_severity = d.consequence_severity
	ship_prefix := civilization_ship_prefix(d)
	apply_generated_fleet(out, fleet_goals_from_setup(d), ship_prefix)
	style := Ship_Construction_Style(clamp(d.choices[int(Setup_Field.Capability_Two)], 0, 3))
	for &ship in out.ships[:out.ship_count] {
		ship.construction_style = style
		ship.generator_kind =
			style == .Living_Hullcraft || style == .Closed_Cycle ? .Single_Hull : .Modular_Frame
	}
	for &attribute, i in out.attributes {
		choice := d.choices[i]
		attribute.name = setup_attribute_name(d, i)
		attribute.description = setup_attribute_description(d, i)
		attribute.class = i < 2 ? .Identity : i < 4 ? .Capability : .Value
	}
	// Setup generation is its own deterministic stream. Campaign resolution
	// begins from the resulting stream position so replay identity is complete.
	out.rng_state = d.rng_state; out.seed = d.rng_state
	apply_setup_history(d, out)
	// Founding choices establish the history from which the first public claims
	// are derived. Present that board immediately so the Council can authorize
	// an operation before any years have to pass.
	surface_needs(out)
	// Setup is also a reporting boundary: the opening claims must be available
	// to the Compact before the player is directed to review them.
	_ = compact_surface_one_call(out)
	return true, "chronicle founded"
}
