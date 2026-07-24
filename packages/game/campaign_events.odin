package game

import "core:fmt"
import "core:testing"

semantic_tag_summary :: proc(tags: Semantic_Tags) -> string {
	if semantic_has(tags, .Accountability) do return "ARCHIVE · ACCOUNTABILITY · CONTESTED"
	if semantic_has(tags, .Jurisdiction) do return "SHIP · INSTITUTION · JURISDICTION"
	if semantic_has(tags, .Autonomy) do return "SHIP · PASSAGE · AUTONOMY"
	if semantic_has(tags, .Damage) do return "SHIP · DAMAGE · SURVIVAL"
	if semantic_has(tags, .Repair) do return "SHIP · REPAIR"
	if semantic_has(tags, .Rescue) do return "RESCUE · CARE"
	if semantic_has(tags, .Governance) do return "GOVERNANCE · COMMUNITY"
	if semantic_has(tags, .Knowledge) do return "ARCHIVE · KNOWLEDGE"
	if semantic_has(tags, .Migration) do return "SETTLEMENT · MIGRATION"
	if semantic_has(tags, .Ship) do return "SHIP · EVENT MEMORY"
	return "HISTORICAL RECORD"
}

semantic_tags_for_event_cause :: proc(role: Event_Cause_Role) -> Semantic_Tags {
	tags := make_semantic_tags(.Memory, .Causality)
	switch role {case .Precedent:
		return semantic_add(tags, .Rule, .Governance); case .Opposition, .Contradiction:
		return semantic_add(tags, .Contested); case .Trigger, .Memory, .Continuation:
		return tags}
	return tags
}

event_cause_role_name :: proc(role: Event_Cause_Role) -> string {
	switch role {case .Trigger:
		return "TRIGGERED BY"; case .Precedent:
		return "JUSTIFIED BY"; case .Memory:
		return "RECALLED"; case .Opposition:
		return "OPPOSED BY"; case .Continuation:
		return "CONTINUED"; case .Contradiction:
		return "CONTRADICTED BY"}
	return "CAUSED BY"
}

event_cites :: proc(event: Campaign_Event, sequence: u64) -> bool {
	for i in 0 ..< event.cause_count do if event.causes[i].sequence == sequence do return true
	return false
}

refresh_semantic_tags :: proc(c: ^Campaign) {
	for &event in c.events[:c.event_count] {event.semantic_tags = semantic_tags_for_event(event.kind, event.ship_id, event.related_ship_id, event.community, event.figure_id, event.institution_id, event.settlement_id, event.archive_id, event.account_status); if event.account_exposed do event.semantic_tags = semantic_add(event.semantic_tags, .Accountability); if event.cause_count > 0 do event.semantic_tags = semantic_add(event.semantic_tags, .Causality); for &cause in event.causes[:event.cause_count] do cause.semantic_tags = semantic_tags_for_event_cause(cause.role)}
	for &ship in c.ships[:c.ship_count] {ship.semantic_tags = semantic_tags_for_ship(ship.role); for &memory in ship.memories[:ship.memory_count] {event_at := event_index_by_sequence(c, memory.event_sequence); if event_at >= 0 do memory.semantic_tags = semantic_add(c.events[event_at].semantic_tags, .Memory)}}
	for &community in c.communities[:c.community_count] do community.semantic_tags = make_semantic_tags(.Entity, .Community)
	for &attribute in c.attributes {attribute.semantic_tags = make_semantic_tags(.Entity); switch attribute.class {case .Identity:
			attribute.semantic_tags = semantic_add(
				attribute.semantic_tags,
				.Identity,
			); case .Capability:
			attribute.semantic_tags = semantic_add(
				attribute.semantic_tags,
				.Capability,
			); case .Value:
			attribute.semantic_tags = semantic_add(attribute.semantic_tags, .Value)}}
	for &institution in c.institutions {institution.semantic_tags = make_semantic_tags(.Entity, .Institution, .Governance); switch institution.id {case 2:
			institution.semantic_tags = semantic_add(
				institution.semantic_tags,
				.Navigation,
				.Knowledge,
			); case 3:
			institution.semantic_tags = semantic_add(
				institution.semantic_tags,
				.Archive,
				.Knowledge,
				.Care,
			); case 4:
			institution.semantic_tags = semantic_add(
				institution.semantic_tags,
				.Industry,
				.Repair,
			); case 5:
			institution.semantic_tags = semantic_add(
				institution.semantic_tags,
				.Care,
				.Rescue,
			); case:}}
	for &archive in c.archives do archive.semantic_tags = make_semantic_tags(.Entity, .Archive, .Knowledge)
	for &precedent in c.precedents[:c.precedent_count] do precedent.semantic_tags = semantic_tags_for_precedent(precedent.kind)
	for &need in c.needs do if need.active || need.resolved || need.detail != "" {need.semantic_tags = semantic_tags_for_need(need.kind)}
	for &project in c.projects do if project.active || project.kind != .None {project.semantic_tags = make_semantic_tags(.Project); if project.ship != 0 do project.semantic_tags = semantic_add(project.semantic_tags, .Ship); if project.kind == .Repair do project.semantic_tags = semantic_add(project.semantic_tags, .Repair)}
	for &promise in c.promises[:c.promise_count] do promise.semantic_tags = make_semantic_tags(.Promise, .Community)
	for &settlement in c.settlements[:c.settlement_count] do settlement.semantic_tags = make_semantic_tags(.Entity, .Settlement, .Migration, .Founding)
	for &relationship in c.settlement_relationships[:c.settlement_relationship_count] {relationship.semantic_tags = make_semantic_tags(.Relationship, .Settlement, .Migration); if relationship.kind == .Exchange do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Industry); if relationship.kind == .Dependency do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Care, .Survival)}
	for &hook in c.history_hooks[:c.history_hook_count] do hook.semantic_tags = make_semantic_tags(.Memory, .Community, .Relationship)
	for &relationship in c.relationships[:c.relationship_count] do relationship.semantic_tags = make_semantic_tags(.Relationship, .Ship, .Community)
	for &relationship in c.ship_relationships[:c.ship_relationship_count] {
		relationship.semantic_tags =
			relationship.kind == .Construction_Siblings ? make_semantic_tags(.Relationship, .Ship, .Identity) : make_semantic_tags(.Relationship, .Ship, .Passage)
		if relationship.shared_passages > 0 do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Passage)
	}
	for &relationship in c.institution_ship_relationships[:c.institution_ship_relationship_count] {relationship.semantic_tags = make_semantic_tags(.Relationship, .Ship, .Institution, .Governance, .Jurisdiction); if relationship.stance == .Contested do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Contested)}
	for &relationship in c.community_institution_relationships[:c.community_institution_relationship_count] {relationship.semantic_tags = make_semantic_tags(.Relationship, .Community, .Institution, .Governance); if relationship.stance == .Opposition do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Contested)}
	for &relationship in c.institution_relationships[:c.institution_relationship_count] {relationship.semantic_tags = make_semantic_tags(.Relationship, .Institution, .Governance, relationship.policy); if relationship.stance == .Rivalry do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Contested)}
	for &figure in c.historical_figures[:c.historical_figure_count] {figure.semantic_tags = make_semantic_tags(.Entity, .Figure); if figure.institution != 0 do figure.semantic_tags = semantic_add(figure.semantic_tags, .Institution); if figure.settlement != 0 do figure.semantic_tags = semantic_add(figure.semantic_tags, .Settlement, .Migration); if figure.passage_actions > 0 do figure.semantic_tags = semantic_add(figure.semantic_tags, .Passage, .Autonomy)}
	for &front in c.fronts[:c.front_count] do front.semantic_tags = semantic_add(front.semantic_tags, .Entity, .Event, .Causality)
	for &proposal in c.future_fronts[:c.future_front_count] do proposal.semantic_tags = semantic_add(proposal.semantic_tags, .Governance, .Causality)
	refresh_passage_semantic_tags(&c.passage)
}

record_event :: proc(
	c: ^Campaign,
	kind: Event_Kind,
	detail := "",
	ship_id := Ship_ID(0),
	value: i32 = 0,
	community := Community_ID(0),
	cause_sequence: u64 = 0,
	figure_id := Figure_ID(0),
	institution_id := Institution_ID(0),
	settlement_id := Settlement_ID(0),
	related_ship_id := Ship_ID(0),
	precedent_event: u64 = 0,
	archive_id := Archive_ID(0),
	authoritative_detail := "",
	account_status := Account_Status.Uncontested,
	operation_id: u64 = 0,
	observation_index: i32 = -1,
) {
	if c.event_count >= MAX_EVENTS && !compact_chronicle(c) do return
	resolved_operation_id := operation_id
	resolved_observation_index := observation_index
	if resolved_operation_id == 0 && c.applying_operation_id != 0 {
		resolved_operation_id = u64(c.applying_operation_id)
		if resolved_observation_index < 0 do resolved_observation_index = c.applying_observation_index
	}
	c.event_sequence += 1
	tags := semantic_tags_for_event(
		kind,
		ship_id,
		related_ship_id,
		community,
		figure_id,
		institution_id,
		settlement_id,
		archive_id,
		account_status,
	)
	c.events[c.event_count] = {
		sequence             = c.event_sequence,
		kind                 = kind,
		season               = c.season,
		ship_id              = ship_id,
		value                = value,
		detail               = detail,
		authoritative_detail = authoritative_detail,
		account_status       = account_status,
		community            = community,
		cause_sequence       = cause_sequence,
		figure_id            = figure_id,
		institution_id       = institution_id,
		settlement_id        = settlement_id,
		related_ship_id      = related_ship_id,
		precedent_event      = precedent_event,
		archive_id           = archive_id,
		operation_id         = resolved_operation_id,
		observation_index       = resolved_observation_index,
		semantic_tags        = tags,
	}
	stored := &c.events[c.event_count]
	if c.passage.active {
		stored.passage_id = c.passage.id
		stored.ship_elapsed_days = c.passage.elapsed_days
		stored.membrane_elapsed_days = c.passage.membrane_elapsed_days
		if c.passage.domain == .Dark {
			stored.dark_depth = dark_depth_from_anchor(
				c.outer_dark.continuum.seed,
				c.outer_dark.continuum.anchor_position,
				c.passage.dark_navigation.position,
			)
		}
	}
	if cause_sequence != 0 &&
	   event_reference_exists(c, cause_sequence) {stored.causes[stored.cause_count] = {
			sequence      = cause_sequence,
			role          = .Trigger,
			semantic_tags = semantic_tags_for_event_cause(.Trigger),
		}; stored.cause_count += 1}
	if precedent_event != 0 &&
	   precedent_event != cause_sequence &&
	   event_reference_exists(c, precedent_event) &&
	   stored.cause_count < MAX_EVENT_CAUSES {stored.causes[stored.cause_count] = {
			sequence      = precedent_event,
			role          = .Precedent,
			semantic_tags = semantic_tags_for_event_cause(.Precedent),
		}; stored.cause_count += 1}
	if stored.cause_count > 0 do stored.semantic_tags = semantic_add(stored.semantic_tags, .Causality)
	event := c.events[c.event_count]
	c.event_count += 1
	remember_event_for_ships(c, event)
}

add_event_cause :: proc(
	c: ^Campaign,
	event_sequence, cause_sequence: u64,
	role: Event_Cause_Role,
) -> bool {
	event_at := event_index_by_sequence(c, event_sequence)
	if event_at < 0 || !event_reference_exists(c, cause_sequence) || event_sequence == cause_sequence do return false
	event := &c.events[event_at]; for cause in event.causes[:event.cause_count] do if cause.sequence == cause_sequence && cause.role == role do return true
	if event.cause_count >= MAX_EVENT_CAUSES do return false
	event.causes[event.cause_count] = {
		sequence      = cause_sequence,
		role          = role,
		semantic_tags = semantic_tags_for_event_cause(role),
	}; event.cause_count += 1; event.semantic_tags = semantic_add(event.semantic_tags, .Causality)
	return true
}

event_index_by_sequence :: proc(c: ^Campaign, sequence: u64) -> int {
	if sequence == 0 do return -1
	for event, i in c.events[:c.event_count] do if event.sequence == sequence do return i
	return -1
}

rng_next :: proc(c: ^Campaign) -> u64 {
	x := c.rng_state
	x ~= x << u64(13)
	x ~= x >> u64(7)
	x ~= x << u64(17)
	if x == 0 do x = 1
	c.rng_state = x
	c.seed = x
	c.rng_sequence += 1
	return x
}

rng_range :: proc(c: ^Campaign, upper: u64) -> u64 {
	if upper == 0 do return 0
	return rng_next(c) % upper
}

new_campaign_seeded_heap :: proc(seed: u64) -> ^Campaign {
	c := new(Campaign)
	campaign_init(c, seed)
	return c
}
next_random :: proc(c: ^Campaign) -> u64 {return rng_next(c)}
campaign_init :: proc(c: ^Campaign, seed: u64 = 1, length := Chronicle_Length.Standard) {
	if c == nil do return
	actual_seed := seed
	if actual_seed == 0 do actual_seed = 1
	c^ = Campaign {
		format_version = CAMPAIGN_FORMAT_VERSION,
		rules_identity = CAMPAIGN_RULES_IDENTITY,
		initial_seed = actual_seed,
		seed = actual_seed,
		rng_state = actual_seed,
		length = length,
		ruleset = DEFAULT_RULESET,
		story_tempo = .Measured,
		material_pressure = .Standard,
		consequence_severity = .Standard,
		season = 0,
		year = 0,
		clock = {
			now = 0,
			reporting_period = 0,
			next_reporting_at = Campaign_Time(CAMPAIGN_REPORT_SECONDS),
			speed = .One,
		},
		strategic = {cohesion = 70},
		capacities = {
			compute = {total = 12},
			manpower = {total = 12},
			raw_materials = {total = 12},
		},
		stability = 3,
		ship_count = INITIAL_SHIPS,
		community_count = INITIAL_COMMUNITIES,
		first_emergency_season = -1,
		last_major_beat_season = -3,
		last_front_beat_season = -1,
		next_precedent_id = 1,
		next_precedent_case_id = 1,
		next_front_id = 1,
		compact = {
			version = COMPACT_CONTRACT_VERSION,
			next_call_id = 1,
			next_undertaking_id = 1,
			next_callback_id = 1,
			last_call_boundary_season = -1,
			quiet_until_season = -1,
			counsel = {chosen = -1},
		},
		ending = .In_Progress,
	}
	// Chronicle storage is deliberately heap-backed. A full fixed event buffer
	// made every Campaign local exceed Odin's 256 KiB safe-stack threshold.
	// The dynamic array serializes to the same JSON array as the former fixed
	// buffer, so existing saves remain compatible.
	when ODIN_TEST {
		// The test runner owns and resets its temporary arena after each test.
		// This lets value-style fixtures remain terse without leaking the
		// campaign's heap-backed Chronicle buffer when they do not mutate-owned
		// strings and therefore need no explicit campaign_destroy call.
		c.events = make([dynamic]Campaign_Event, MAX_EVENTS, context.temp_allocator)
	} else {
		c.events = make([dynamic]Campaign_Event, MAX_EVENTS)
	}
	storage := campaign_storage_allocator()
	c.settlement_economies.economies = make(
		[dynamic]Settlement_Economy,
		MAX_SETTLEMENT_ECONOMIES,
		storage,
	)
	c.settlement_economies.archived = make(
		[dynamic]Archived_Settlement_Economy,
		MAX_SETTLEMENT_ECONOMY_ARCHIVE,
		storage,
	)
	c.settlement_economies.flows = make([dynamic]Trade_Flow, MAX_TRADE_FLOWS, storage)
	c.settlement_economies.political_links = make(
		[dynamic]Settlement_Political_Link,
		MAX_SETTLEMENT_POLITICAL_LINKS,
		storage,
	)
	c.dark_fleet_atlas = make([dynamic]Dark_Atlas_Discovery, 0, 0, storage)
	c.dark_organism_observations = make([dynamic]Dark_Organism_Observation, 0, 0, storage)
	c.dark_strategy_records = make([dynamic]Dark_Strategy_Statistics, 0, 0, storage)
	c.dark_unresolved_voyages = make([dynamic]Dark_Voyage_Record, 0, 0, storage)
	c.dark_relays = make([dynamic]Dark_Relay_Record, 0, 0, storage)
	c.habitable_contacts = make([dynamic]Habitable_World_Contact, 0, 0, storage)
	c.max_seasons = chronicle_length_seasons(length)
	c.communities[0] = {
		id                = 1,
		name              = "Ember Compact",
		population        = 18000,
		children          = 3600,
		tolerance         = 3,
		settlement_desire = 2,
		trust             = 70,
	}
	c.communities[1] = {
		id                 = 2,
		name               = "Ocean Memory",
		population         = 15000,
		children           = 2700,
		tolerance          = 4,
		settlement_desire  = 4,
		trust              = 68,
		consents_to_settle = true,
	}
	c.communities[2] = {
		id                = 3,
		name              = "Foundry Houses",
		population        = 12000,
		children          = 1900,
		tolerance         = 5,
		settlement_desire = 1,
		trust             = 72,
	}
	c.communities[3] = {
		id                 = 4,
		name               = "New Dawn Assembly",
		population         = 10000,
		children           = 3200,
		tolerance          = 2,
		settlement_desire  = 3,
		trust              = 64,
		consents_to_settle = true,
	}
	c.attributes = {
		{
			.Identity,
			"Keepers of Ash",
			"The dead are remembered through objects carried between ships.",
			0,
			{},
		},
		{.Identity, "Many Kitchens", "Ritual meals define community and hospitality.", 0, {}},
		{
			.Capability,
			"Fleetborn Adaptation",
			"Long exposure to artificial gravity improves tolerance of marginal habitats.",
			0,
			{},
		},
		{
			.Capability,
			"Distributed Fabrication",
			"Foundries can substitute for one another at reduced efficiency.",
			0,
			{},
		},
		{
			.Value,
			"No One Left Behind",
			"Distress calls create a public expectation of rescue.",
			0,
			{},
		},
		{.Value, "Consent to Settlement", "Communities must choose permanent relocation.", 0, {}},
	}
	c.institutions = {
		{
			1,
			"Civic Assembly",
			"legitimate fleet-wide deliberation",
			75,
			true,
			1,
			{},
			.Shared_Authority,
			.Accountable,
			.Mutual_Aid,
		},
		{
			2,
			"Navigation Guild",
			"route knowledge and Passage intelligence",
			70,
			true,
			2,
			{},
			.Ship_Autonomy,
			.Open,
			.Discretionary,
		},
		{
			3,
			"Seed Archive",
			"biological restoration and agricultural resilience",
			72,
			true,
			2,
			{},
			.Shared_Authority,
			.Open,
			.Mutual_Aid,
		},
		{
			4,
			"Fleet Foundry Council",
			"repair and construction coordination",
			68,
			true,
			3,
			{},
			.Central_Command,
			.Accountable,
			.Discretionary,
		},
		{
			5,
			"Mercy Compact",
			"public health and rescue doctrine",
			74,
			true,
			4,
			{},
			.Shared_Authority,
			.Open,
			.Absolute_Duty,
		},
	}
	c.archives = {
		{1, "Seed and Genetic Bank", 90, 8, true, true, false, {}},
		{2, "Engineering Corpus", 80, 5, false, true, true, {}},
		{3, "Constitutional Archive", 85, 2, true, true, false, {}},
		{4, "Languages of Home", 75, 3, true, true, false, {}},
		{5, "Ecosystem Reliquary", 70, 10, true, true, false, {}},
		{6, "Recorded Ancestors", 65, 4, true, true, false, {}},
	}
	names := [INITIAL_SHIPS]string {
		"Wayward Light",
		"Kepler's Promise",
		"Long Measure",
		"Resolute",
		"Mercy of Dawn",
		"Kestrel",
		"Unbroken Thread",
		"Green Reliquary",
		"Common Hearth",
		"Anvil of Rain",
		"Testament",
		"Far Harbor",
	}
	roles := [INITIAL_SHIPS]Role {
		.Survey,
		.Archive,
		.Foundry,
		.Escort,
		.Hospital,
		.Survey,
		.Escort,
		.Agriculture,
		.Habitat,
		.Foundry,
		.Archive,
		.Colony,
	}
	for i in 0 ..< INITIAL_SHIPS {
		construction_seed := ship_construction_identity_seed(actual_seed, Ship_ID(i + 1))
		c.ships[i] = {
			id                = Ship_ID(i + 1),
			name              = names[i],
			construction_seed = construction_seed,
			role              = roles[i],
			hull_class        = .Fleet_Ship,
			hull_archetype    = ship_hull_archetype_from_role(
				construction_seed,
				roles[i],
				.Fleet_Ship,
			),
			operational_role  = ship_operational_role_for_hull(
				construction_seed,
				roles[i],
				ship_hull_archetype_from_role(construction_seed, roles[i], .Fleet_Ship),
			),
			mass_tonnes       = i64(45000 + i * 7000),
			power             = i32(7 + i % 4),
			crew              = i32(220 + i * 15),
			community         = Community_ID(i % INITIAL_COMMUNITIES + 1),
			active            = true,
		}
	}
	initialize_material_economy(c)
	c.ships[0].passage_trait = .Curious
	c.ships[1].passage_trait = .Independent
	c.ships[2].passage_trait = .Cautious
	c.ships[3].passage_trait = .Protective
	c.ships[4].passage_trait = .Protective
	c.ships[5].passage_trait = .Independent
	c.ships[6].passage_trait = .Committed
	refresh_semantic_tags(c)
	// The first pivotal evacuation choice: people were favored over redundant machinery.
	_ = fleet_stock_spend(c, {supplies = 5}, .Emergency)
	c.strategic.cohesion += 5
	record_event(
		c,
		.Chronicle_Started,
		"The fleet preserved lives at the cost of industrial redundancy.",
	)
	c.founding_decision_event = c.event_sequence
	c.values[0] = {
		kind          = .No_One_Left_Behind,
		status        = .Claimed,
		claimed_event = c.event_sequence,
	}
	c.values[1] = {
		kind          = .Consent_To_Settle,
		status        = .Claimed,
		claimed_event = c.event_sequence,
	}
	c.galaxy = new(Galaxy, campaign_storage_allocator())
	c.galaxy^ = generate_galaxy(actual_seed ~ CAMPAIGN_GALAXY_SEED_SALT)
	c.far_engagement = new(Far_Engagement, campaign_storage_allocator())
	c.outer_dark = generate_outer_dark_for_galaxy(actual_seed ~ 0x6f75746572, c.galaxy)
	fleet_navigation_initialize(c)
	habitable_reveal_campaign_bubble(
		c,
		c.outer_dark.continuum.anchor_neighborhood,
		c.outer_dark.continuum.anchor_door_id,
	)
}

new_campaign_heap :: proc(seed: u64 = 1, length := Chronicle_Length.Standard) -> ^Campaign {
	c := new(Campaign)
	campaign_init(c, seed, length)
	return c
}

campaign_destroy_heap :: proc(c: ^Campaign) {
	if c == nil do return
	campaign_destroy(c)
	free(c)
}

ship_index :: proc(c: ^Campaign, id: Ship_ID) -> int {
	for ship, i in c.ships do if ship.id == id do return i
	return -1
}

add_ship_history :: proc(c: ^Campaign, id: Ship_ID, detail: string) {
	index := ship_index(c, id)
	if index < 0 || detail == "" do return
	ship := &c.ships[index]
	if ship.history_record_count < MAX_SHIP_HISTORY {
		ship.history_records[ship.history_record_count] = detail
		ship.history_record_count += 1
	} else {
		for i in 1 ..< MAX_SHIP_HISTORY do ship.history_records[i - 1] = ship.history_records[i]
		ship.history_records[MAX_SHIP_HISTORY - 1] = detail
	}
	ship.history_note = detail
}

event_creates_ship_memory :: proc(kind: Event_Kind) -> bool {
	#partial switch kind {
	case .Need_Resolved,
	     .Need_Neglected,
	     .Autonomy_Triggered,
	     .Ship_Damaged,
	     .Ship_Repaired,
	     .Ship_Lost,
	     .Ship_Scarred,
	     .Ship_Bond_Changed,
	     .Promise_Changed,
	     .Precedent_Enacted,
	     .Settlement_Founded,
	     .Settlement_Reported,
	     .Settlement_Supported,
	     .Settlement_Setback,
	     .Settlement_Charter_Changed,
	     .Local_Settlement,
	     .Community_Joined,
	     .History_Continued,
	     .Historical_Figure_Emerged,
	     .Historical_Figure_Changed,
	     .Institution_Changed,
	     .Jurisdiction_Changed,
	     .Political_Relationship_Changed,
	     .Situation_Response,
	     .Situation_Decided,
	     .Situation_Complied,
	     .Capacity_Committed,
	     .Capacity_Released:
		return true
	case:
	}
	return false
}

event_memory_is_pivotal :: proc(kind: Event_Kind) -> bool {
	#partial switch kind {case .Ship_Lost,
	                           .Ship_Scarred,
	                           .Promise_Changed,
	                           .Precedent_Enacted,
	                           .Settlement_Founded,
	                           .Local_Settlement,
	                           .Historical_Figure_Emerged,
	                           .Historical_Figure_Changed,
	                           .Jurisdiction_Changed,
	                           .Political_Relationship_Changed,
	                           .Need_Resolved,
	                           .Need_Neglected:
		return true
	case:}
	return false
}
