package game_tests

import "core:strings"
import "core:testing"
@(test)
snapshot_restores_rng_and_history :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 99)
	snapshot := campaign_snapshot(&c)
	defer free(snapshot)
	advance_season(&c)
	testing.expect(t, c.event_count > snapshot.event_count)
	testing.expect(t, c.rng_sequence >= snapshot.rng_sequence)
	testing.expect(t, campaign_restore(&c, snapshot^))
	testing.expect_value(t, c.event_count, snapshot.event_count)
	testing.expect_value(t, c.rng_state, snapshot.rng_state)
	testing.expect_value(t, c.season, snapshot.season)
}

@(test)
snapshot_rejects_incompatible_rules :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c)
	snapshot := campaign_snapshot(&c)
	defer campaign_destroy_heap(snapshot)
	snapshot.rules_identity ~= 0xff
	testing.expect(t, !campaign_restore(&c, snapshot^))
}

@(test)
relationship_carries_rescue_history_into_later_autonomy :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 101)
	hook_index := create_broken_procession_hook(&c, 400, Ship_ID(1))
	testing.expect(t, hook_index >= 0)
	testing.expect_value(t, c.historical_figure_count, 1)
	testing.expect_value(t, c.historical_figures[0].name, "Tala Venn")
	hook := &c.history_hooks[hook_index]
	hook.stage = .Obligation
	origin := c.relationships[0].origin_event
	advance_history_hook_for_need(&c, hook.community, hook.ship, true)
	testing.expect_value(t, c.relationship_count, 1)
	testing.expect_value(t, c.relationships[0].kind, Relationship_Kind.Advocated_For)
	testing.expect(t, c.relationships[0].last_event > origin)
	testing.expect(t, c.relationships[0].strength > 0)
}

@(test)
historical_figure_and_institution_follow_the_fleets_response :: proc(t: ^testing.T) {
	honored: Campaign
	campaign_init(&honored, 107); neglected: Campaign
	campaign_init(&neglected, 107)
	campaigns := [2]^Campaign{&honored, &neglected}
	for c in campaigns {hook_index := create_broken_procession_hook(c, 450, Ship_ID(1))
		c.history_hooks[hook_index].stage = .Obligation
		c.history_hooks[hook_index].obligation_event = c.history_hooks[hook_index].origin_event}
	before := honored.institutions[0].legitimacy
	advance_history_hook_for_need(&honored, honored.history_hooks[0].community, Ship_ID(1), true)
	advance_history_hook_for_need(
		&neglected,
		neglected.history_hooks[0].community,
		Ship_ID(1),
		false,
	)
	testing.expect(t, honored.institutions[0].legitimacy > before)
	testing.expect(t, neglected.institutions[0].legitimacy < before)
	testing.expect_value(
		t,
		honored.historical_figures[0].role,
		"delegate of the Broken Procession",
	)
	testing.expect_value(
		t,
		neglected.historical_figures[0].role,
		"organizer of the unanswered petition",
	)
	testing.expect_value(t, honored.historical_figures[0].institution, Institution_ID(1))
	last := honored.events[honored.event_count - 1]
	testing.expect_value(t, last.kind, Event_Kind.Institution_Changed)
	testing.expect_value(t, last.figure_id, honored.historical_figures[0].id)
	testing.expect_value(t, last.cause_sequence, honored.history_hooks[0].consequence_event)
	testing.expect_value(t, last.institution_id, Institution_ID(1))
	for i in 0 ..< MAX_NEEDS do neglected.needs[i] = {}
	institution_source := neglected.event_sequence; surface_needs(&neglected)
	initiative := -1
	for need, i in neglected.needs do if need.institution == Institution_ID(1) {initiative = i; testing.expect_value(t, need.source_event, institution_source)}
	testing.expect(t, initiative >= 0)
	testing.expect_value(t, neglected.needs[initiative].figure, neglected.historical_figures[0].id)
	testing.expect(t, strings.contains(neglected.needs[initiative].detail, "Tala Venn"))
	weakened := neglected.institutions[0].legitimacy
	testing.expect(t, resolve_need(&neglected, initiative))
	testing.expect(t, neglected.institutions[0].legitimacy > weakened)
	figure_event := neglected.events[neglected.event_count - 1]
	testing.expect_value(t, figure_event.kind, Event_Kind.Historical_Figure_Changed)
	testing.expect_value(t, figure_event.figure_id, neglected.historical_figures[0].id)
	testing.expect_value(t, figure_event.institution_id, Institution_ID(1))
	testing.expect_value(t, neglected.historical_figures[0].public_actions, i32(2))
	_ = evaluate_ending(&honored); found_figure := false
	for evidence in honored.ending_evidence[:honored.ending_evidence_count] do if strings.contains(evidence, "Tala Venn") do found_figure = true
	testing.expect(t, found_figure)
}

@(test)
historical_figures_age_and_retire_from_recorded_careers :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 109)
	hook_index := create_broken_procession_hook(
		&c,
		400,
		1,
	); hook := &c.history_hooks[hook_index]; hook.stage = .Obligation; hook.obligation_event = hook.origin_event
	advance_history_hook_for_need(&c, hook.community, hook.ship, true)
	figure := &c.historical_figures[0]; starting_age := figure.age_years; career_event := figure.last_event
	for _ in 0 ..< 20 {if !figure.active do break; advance_historical_figures(&c)}
	testing.expect(t, figure.age_years > starting_age)
	testing.expect(t, !figure.active)
	testing.expect_value(t, figure.role, "retired public figure")
	retirement := c.events[c.event_count - 1]
	testing.expect_value(t, retirement.kind, Event_Kind.Historical_Figure_Changed)
	testing.expect_value(t, retirement.figure_id, figure.id)
	testing.expect_value(t, retirement.cause_sequence, career_event)
}

@(test)
repeated_treatment_becomes_community_memory_and_a_later_claim :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 110)
	for _ in 0 ..< 2 {
		c.needs[0] = {
			kind      = .Representation,
			community = 1,
			ship      = 1,
			deadline  = c.season + 1,
			active    = true,
			detail    = "Representation claim",
		}
		neglect_open_needs(&c)
	}
	community := &c.communities[0]
	testing.expect_value(t, community.grievance, i32(4))
	testing.expect_value(t, community.petitions_neglected, i32(2))
	testing.expect_value(t, community.position, Community_Position.Aggrieved)
	memory_event := community.last_memory_event
	testing.expect_value(t, c.events[c.event_count - 1].kind, Event_Kind.Community_Memory_Changed)
	community.trust = 70
	used: [NEED_KIND_COUNT]bool; need, derived := derive_historical_need(&c, &used)
	testing.expect(t, derived); testing.expect_value(t, need.kind, Need_Kind.Representation)
	testing.expect_value(
		t,
		need.community,
		Community_ID(1),
	); testing.expect_value(t, need.source_event, memory_event)
	need.active = true; need.cost = 1; need.deadline = c.season + 1; c.needs[0] = need
	testing.expect(t, resolve_need(&c, 0))
	testing.expect_value(t, community.grievance, i32(1))
	testing.expect_value(t, community.petitions_honored, i32(1))
}

@(test)
community_memory_changes_affiliated_ship_coordination :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 111); c.ships[0].community = 1
	c.communities[0].position = .Aggrieved; c.communities[0].grievance = 5; c.communities[0].petitions_neglected = 3
	record_event(
		&c,
		.Community_Memory_Changed,
		"The Ember Compact recorded repeated unanswered claims.",
		1,
		5,
		1,
	); c.communities[0].last_memory_event = c.event_sequence
	testing.expect_value(t, c.communities[0].last_memory_event, c.event_sequence)
}

@(test)
neglected_obligation_changes_the_recorded_relationship :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 102)
	hook_index := create_broken_procession_hook(&c, 300, Ship_ID(2))
	hook := &c.history_hooks[hook_index]; hook.stage = .Obligation
	advance_history_hook_for_need(&c, hook.community, hook.ship, false)
	testing.expect_value(t, c.relationships[0].kind, Relationship_Kind.Unanswered_Obligation)
	testing.expect(t, c.relationships[0].strength < 0)
	testing.expect(t, relationship_description(&c, Ship_ID(2)) != "")
	testing.expect(t, c.relationships[0].strength < 0)
}

@(test)
history_events_form_a_navigable_causal_chain :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 103)
	hook_index := create_broken_procession_hook(
		&c,
		500,
		Ship_ID(1),
	); hook := &c.history_hooks[hook_index]
	hook.stage = .Obligation
	record_event(
		&c,
		.History_Continued,
		"The Broken Procession requested a council voice.",
		hook.ship,
		hook.population,
		hook.community,
		hook.origin_event,
	)
	hook.obligation_event = c.event_sequence
	advance_history_hook_for_need(&c, hook.community, hook.ship, true)
	origin_index := event_index_by_sequence(&c, hook.origin_event)
	obligation_index := event_index_by_sequence(&c, hook.obligation_event)
	consequence_index := event_index_by_sequence(&c, hook.consequence_event)
	testing.expect(t, origin_index >= 0 && obligation_index >= 0 && consequence_index >= 0)
	testing.expect_value(t, c.events[obligation_index].cause_sequence, hook.origin_event)
	testing.expect_value(t, c.events[consequence_index].cause_sequence, hook.obligation_event)
	testing.expect_value(t, c.events[consequence_index].community, hook.community)
}

@(test)
damaged_ship_history_surfaces_a_causally_linked_repair_need :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 104); for i in 0 ..< MAX_NEEDS do c.needs[i] = {}
	c.ships[4].damage = 3
	record_event(
		&c,
		.Ship_Damaged,
		"Mercy of Dawn returned with a breached medical deck.",
		Ship_ID(5),
		3,
	)
	damage_event := c.event_sequence
	surface_needs(&c)
	found := false
	for need in c.needs {if need.kind != .Ship_Repair do continue; found = true; testing.expect_value(t, need.ship, Ship_ID(5)); testing.expect_value(t, need.source_event, damage_event)}
	testing.expect(t, found)
	for event in c.events[:c.event_count] do if event.kind == .Need_Surfaced && event.ship_id == Ship_ID(5) do testing.expect_value(t, event.cause_sequence, damage_event)
}

@(test)
low_trust_hospital_damage_takes_priority_over_larger_routine_repairs :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1041)
	c.ships[0].damage = 4
	c.ships[4].damage = 1
	hospital_community := community_index(
		&c,
		c.ships[4].community,
	); testing.expect(t, hospital_community >= 0)
	c.communities[hospital_community].trust = 40
	used: [NEED_KIND_COUNT]bool
	need, derived := derive_historical_need(&c, &used)
	testing.expect(t, derived)
	testing.expect_value(t, need.kind, Need_Kind.Ship_Repair)
	testing.expect_value(t, need.ship, c.ships[4].id)
}

@(test)
repair_decisions_change_ship_state_and_feed_future_petitions :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1042); c.ships[4].damage = 3
	record_event(
		&c,
		.Ship_Damaged,
		"Mercy of Dawn returned with structural damage.",
		c.ships[4].id,
		3,
	); damage_event := c.event_sequence
	surface_needs(&c); repair_index := -1
	for need, i in c.needs do if need.kind == .Ship_Repair && need.ship == c.ships[4].id do repair_index = i
	testing.expect(t, repair_index >= 0); testing.expect(t, c.needs[repair_index].detail != "")
	testing.expect(t, resolve_need(&c, repair_index))
	testing.expect_value(t, c.ships[4].damage, i32(1))
	repaired_event := c.events[c.event_count - 1]
	testing.expect_value(t, repaired_event.kind, Event_Kind.Ship_Repaired)
	testing.expect_value(t, repaired_event.cause_sequence, c.events[c.event_count - 3].sequence)
	testing.expect(t, c.ships[4].history_record_count > 0)

	for i in 0 ..< MAX_NEEDS do c.needs[i] = {}
	c.needs[0] = {
		kind         = .Ship_Repair,
		community    = c.ships[4].community,
		ship         = c.ships[4].id,
		deadline     = c.season + 1,
		active       = true,
		source_event = repaired_event.sequence,
	}
	neglect_open_needs(&c)
	testing.expect_value(t, c.ships[4].damage, i32(2))
	neglect_damage := c.events[c.event_count - 1]
	testing.expect_value(t, neglect_damage.kind, Event_Kind.Ship_Damaged)
	testing.expect_value(t, neglect_damage.cause_sequence, c.events[c.event_count - 3].sequence)
	used: [NEED_KIND_COUNT]bool; next, derived := derive_historical_need(&c, &used)
	testing.expect(t, derived); testing.expect_value(t, next.kind, Need_Kind.Ship_Repair)
	testing.expect_value(t, next.source_event, neglect_damage.sequence)
	testing.expect(t, damage_event < repaired_event.sequence)
}

@(test)
low_trust_community_surfaces_its_own_representation_need :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 105); for i in 0 ..< MAX_NEEDS do c.needs[i] = {}
	c.communities[2].trust = 30
	record_event(
		&c,
		.Need_Neglected,
		"The Foundry Houses' petition went unanswered.",
		community = Community_ID(3),
	)
	source := c.event_sequence
	surface_needs(&c)
	found := false
	for need in c.needs {if need.kind == .Representation && need.community == Community_ID(3) {found = true; testing.expect_value(t, need.source_event, source)}}
	testing.expect(t, found)
}

@(test)
seasonal_needs_are_distinct_when_fallbacks_are_required :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 106); for i in 0 ..< MAX_NEEDS do c.needs[i] = {}
	surface_needs(&c); seen: [NEED_KIND_COUNT]bool
	for need in c.needs {testing.expect(t, !seen[int(need.kind)]); seen[int(need.kind)] = true}
}

@(test)
precedents_change_later_fleet_need_costs :: proc(t: ^testing.T) {
	base: Campaign
	campaign_init(&base, 108); law: Campaign
	campaign_init(&law, 108)
	campaigns := [2]^Campaign{&base, &law}
	for c in campaigns {for i in 0 ..< MAX_NEEDS do c.needs[i] = {}; c.communities[0].trust = 30}
	_ = enact_precedent_fixture(
		&law,
		.Shared_Authority,
		"Every community receives a council voice.",
		true,
	)
	surface_needs(&base); surface_needs(&law)
	base_cost, law_cost: i32
	for need in base.needs do if need.kind == .Representation do base_cost = need.cost
	for need in law.needs do if need.kind == .Representation do law_cost = need.cost
	testing.expect_value(t, law_cost, base_cost - 2)
	testing.expect_value(t, precedent_need_cost_modifier(&law, .Archive_Staffing), i32(0))
	_ = enact_precedent_fixture(&law, .Open_Archives, "Knowledge belongs to every harbor.", true)
	testing.expect_value(t, precedent_need_cost_modifier(&law, .Archive_Staffing), i32(-3))
}

@(test)
open_archives_expose_a_disputed_report_and_surface_accountability :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		109,
	); _ = enact_precedent_fixture(&c, .Open_Archives, "The fleet opened its records.", true)
	record_event(
		&c,
		.Expedition_Returned,
		"The expedition reported no viable settlement.",
		Ship_ID(1),
		community = Community_ID(1),
		authoritative_detail = "The site was viable with adaptation.",
		account_status = .Contradicted,
	)
	report_event := c.event_sequence; assembly_before := c.institutions[0].legitimacy
	advance_season(&c)
	report_at := event_index_by_sequence(
		&c,
		report_event,
	); testing.expect(t, report_at >= 0 && c.events[report_at].account_exposed)
	revelation := c.pending_accountability_event; testing.expect(t, revelation > report_event)
	revelation_at := event_index_by_sequence(
		&c,
		revelation,
	); testing.expect(t, revelation_at >= 0); testing.expect_value(t, c.events[revelation_at].kind, Event_Kind.Archive_Revelation); testing.expect_value(t, c.events[revelation_at].cause_sequence, report_event); testing.expect_value(t, c.events[revelation_at].archive_id, Archive_ID(3)); testing.expect(t, c.institutions[0].legitimacy < assembly_before)
	need_at := -1; for need, i in c.needs do if need.active && need.source_event == revelation {need_at = i; break}; testing.expect(t, need_at >= 0); testing.expect_value(t, c.needs[need_at].kind, Need_Kind.Representation); testing.expect_value(t, c.needs[need_at].institution, Institution_ID(1))
	testing.expect(
		t,
		resolve_need(&c, need_at),
	); testing.expect_value(t, c.pending_accountability_event, u64(0)); memory_event := c.communities[0].last_memory_event; testing.expect(t, memory_event > revelation); testing.expect(t, !review_contested_account(&c))
}

@(test)
sealed_archives_do_not_expose_disputed_reports :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		110,
	); record_event(&c, .Expedition_Returned, "The expedition reported no viable settlement.", Ship_ID(1), community = Community_ID(1), authoritative_detail = "The site was viable with adaptation.", account_status = .Contradicted); report_at := c.event_count - 1
	advance_season(
		&c,
	); testing.expect(t, !c.events[report_at].account_exposed); testing.expect_value(t, c.pending_accountability_event, u64(0))
}

@(test)
typed_ship_memories_capture_both_participants_and_event_context :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		111,
	); record_event(&c, .Ship_Bond_Changed, "Wayward Light and Kepler's Promise established shared routines.", Ship_ID(1), 2, Community_ID(1), related_ship_id = Ship_ID(2)); event := c.events[c.event_count - 1]
	first :=
		c.ships[0].memories[c.ships[0].memory_count - 1]; second := c.ships[1].memories[c.ships[1].memory_count - 1]
	testing.expect_value(
		t,
		first.event_sequence,
		event.sequence,
	); testing.expect_value(t, first.kind, Event_Kind.Ship_Bond_Changed); testing.expect_value(t, first.other_ship, Ship_ID(2)); testing.expect_value(t, first.community, Community_ID(1))
	testing.expect_value(
		t,
		second.event_sequence,
		event.sequence,
	); testing.expect_value(t, second.other_ship, Ship_ID(1))
	testing.expect(
		t,
		semantic_has(event.semantic_tags, .Event),
	); testing.expect(t, semantic_has(event.semantic_tags, .Relationship)); testing.expect(t, semantic_has(first.semantic_tags, .Memory)); testing.expect(t, semantic_has(first.semantic_tags, .Ship))
}

@(test)
persistent_historical_objects_all_carry_semantic_tags :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		113,
	); _ = enact_precedent_fixture(&c, .Open_Archives, "Knowledge belongs to every harbor.", true); _ = add_promise(&c, Community_ID(1), c.season + 2, "Return for the separated convoy."); _ = queue_project(&c, .Repair, Ship_ID(1)); _ = create_broken_procession_hook(&c, 400, Ship_ID(1)); record_shared_passage_bonds(&c, []Ship_ID{1, 2}, c.event_sequence); c.ships[0].damage = 2; for i in 0 ..< MAX_NEEDS do c.needs[i] = {}; surface_needs(&c); c.settlements[0] = {
		id                 = 1,
		name               = "Tagged Harbor",
		population         = 1200,
		active             = true,
		founding_community = 1,
		founder_ship       = 1,
	}; c.settlement_count = 1; ships := [1]int{0}; _, _ = begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage); refresh_semantic_tags(&c)
	for ship in c.ships[:c.ship_count] do testing.expect(t, ship.semantic_tags != Semantic_Tags(0))
	for community in c.communities[:c.community_count] do testing.expect(t, community.semantic_tags != Semantic_Tags(0))
	for attribute in c.attributes do testing.expect(t, attribute.semantic_tags != Semantic_Tags(0))
	for institution in c.institutions do testing.expect(t, institution.semantic_tags != Semantic_Tags(0))
	for archive in c.archives do testing.expect(t, archive.semantic_tags != Semantic_Tags(0))
	for precedent in c.precedents[:c.precedent_count] do testing.expect(t, precedent.semantic_tags != Semantic_Tags(0))
	for promise in c.promises[:c.promise_count] do testing.expect(t, promise.semantic_tags != Semantic_Tags(0))
	for hook in c.history_hooks[:c.history_hook_count] do testing.expect(t, hook.semantic_tags != Semantic_Tags(0))
	for relationship in c.relationships[:c.relationship_count] do testing.expect(t, relationship.semantic_tags != Semantic_Tags(0))
	for relationship in c.ship_relationships[:c.ship_relationship_count] do testing.expect(t, relationship.semantic_tags != Semantic_Tags(0))
	for figure in c.historical_figures[:c.historical_figure_count] do testing.expect(t, figure.semantic_tags != Semantic_Tags(0))
	for need in c.needs do if need.active do testing.expect(t, need.semantic_tags != Semantic_Tags(0))
	for project in c.projects do if project.active do testing.expect(t, project.semantic_tags != Semantic_Tags(0))
	for settlement in c.settlements[:c.settlement_count] do testing.expect(t, settlement.semantic_tags != Semantic_Tags(0))
	for event in c.events[:c.event_count] do testing.expect(t, event.semantic_tags != Semantic_Tags(0))
	testing.expect(
		t,
		c.outer_dark.semantic_tags != Semantic_Tags(0),
	); testing.expect(t, c.outer_dark.continuum.semantic_tags != Semantic_Tags(0)); for door in c.outer_dark.continuum.doors[:c.outer_dark.continuum.door_count] do testing.expect(t, door.semantic_tags != Semantic_Tags(0)); for organism in c.outer_dark.continuum.organisms[:c.outer_dark.continuum.organism_count] do testing.expect(t, organism.semantic_tags != Semantic_Tags(0)); for field in c.outer_dark.continuum.fields[:c.outer_dark.continuum.field_count] do testing.expect(t, field.semantic_tags != Semantic_Tags(0))
	testing.expect(
		t,
		c.passage.semantic_tags != Semantic_Tags(0),
	); testing.expect(t, c.passage.contract.semantic_tags != Semantic_Tags(0))
}

@(test)
typed_ship_memories_keep_the_latest_twelve_events :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 112); sequences: [15]u64
	record_event(&c, .Ship_Repaired, "Structural repairs completed.", Ship_ID(1), 2)
	for i in 0 ..< len(
		sequences,
	) {record_event(&c, .Ship_Damaged, "Recorded damage.", Ship_ID(1), i32(i)); sequences[i] = c.event_sequence}
	testing.expect_value(
		t,
		c.ships[0].memory_count,
		MAX_SHIP_MEMORIES,
	); testing.expect_value(t, c.ships[0].memories[0].event_sequence, sequences[3]); testing.expect_value(t, c.ships[0].memories[MAX_SHIP_MEMORIES - 1].event_sequence, sequences[14])
	testing.expect(t, c.ships[0].archived_memory_count > 0)
	testing.expect(t, semantic_has(c.ships[0].archived_memory_tags, .Repair))
}
