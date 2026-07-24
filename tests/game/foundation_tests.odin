package game_tests

import "core:testing"

@(test)
events_retain_typed_convergent_causes :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 2718)
	record_event(
		&c,
		.Ship_Damaged,
		"Wayward Light returned damaged.",
		1,
		1,
	); damage_event := c.event_sequence
	testing.expect(
		t,
		enact_precedent_fixture(
			&c,
			.Ship_Sovereignty,
			"Captains retain operational authority.",
			true,
		),
	); rule_event := c.event_sequence
	record_event(
		&c,
		.Need_Surfaced,
		"The damage became a jurisdiction dispute.",
		1,
		community = 1,
		cause_sequence = damage_event,
		institution_id = 2,
		precedent_event = rule_event,
	)
	event := &c.events[c.event_count - 1]; testing.expect_value(t, event.cause_count, 2); testing.expect_value(t, event.causes[0].role, Event_Cause_Role.Trigger); testing.expect_value(t, event.causes[1].role, Event_Cause_Role.Precedent); testing.expect(t, event_cites(event^, damage_event)); testing.expect(t, event_cites(event^, rule_event)); testing.expect(t, semantic_has(event.semantic_tags, .Causality)); testing.expect(t, semantic_has(event.causes[1].semantic_tags, .Rule))
	record_event(
		&c,
		.Community_Memory_Changed,
		"The community remembered the dispute.",
		1,
		community = 1,
	)
	memory_event :=
		c.event_sequence; testing.expect(t, add_event_cause(&c, memory_event, event.sequence, .Memory)); memory := &c.events[c.event_count - 1]; testing.expect_value(t, memory.cause_count, 1); testing.expect_value(t, memory.causes[0].role, Event_Cause_Role.Memory)
}

@(test)
political_opposition_initiates_and_can_resolve_a_later_conflict :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1618)
	record_event(
		&c,
		.Need_Neglected,
		"The Navigation Guild's staffing petition went unanswered.",
		1,
		community = 2,
		institution_id = 2,
	); first := c.event_sequence
	testing.expect(
		t,
		record_community_institution_response(&c, 2, 2, false, first),
	); first_break := c.event_sequence
	record_event(
		&c,
		.Need_Neglected,
		"A second Navigation Guild petition went unanswered.",
		1,
		community = 2,
		cause_sequence = first_break,
		institution_id = 2,
	); second := c.event_sequence
	testing.expect(t, record_community_institution_response(&c, 2, 2, false, second))
	index := community_institution_relationship_index(
		&c,
		2,
		2,
	); testing.expect(t, index >= 0); if index < 0 do return
	relationship :=
		c.community_institution_relationships[index]; testing.expect_value(t, relationship.stance, Community_Institution_Stance.Opposition); testing.expect_value(t, relationship.strength, i32(-2)); testing.expect(t, semantic_has(relationship.semantic_tags, .Contested)); testing.expect_value(t, community_institution_need_cost_modifier(&c, 2, 2), i32(2))
	for i in 0 ..< MAX_NEEDS do c.needs[i] = {}
	used: [NEED_KIND_COUNT]bool; need, derived := derive_historical_need(&c, &used); testing.expect(t, derived); testing.expect_value(t, need.kind, Need_Kind.Representation); testing.expect_value(t, need.source_event, relationship.last_event); testing.expect_value(t, need.institution, Institution_ID(2))
	c.needs[0] =
		need; c.needs[0].active = true; c.needs[0].cost = 2; c.needs[0].detail = "Reconcile the political break."; c.needs[0].semantic_tags = semantic_tags_for_need(need.kind)
	testing.expect(
		t,
		resolve_need(&c, 0),
	); relationship = c.community_institution_relationships[index]; testing.expect_value(t, relationship.stance, Community_Institution_Stance.Coalition); testing.expect(t, relationship.strength > 0); last_at := event_index_by_sequence(&c, relationship.last_event); testing.expect(t, last_at >= 0); if last_at >= 0 do testing.expect_value(t, c.events[last_at].kind, Event_Kind.Political_Relationship_Changed)
}

@(test)
incompatible_institution_policies_create_a_resolvable_rivalry :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 5772); advance_institution_politics(&c)
	testing.expect_value(
		t,
		c.institution_relationship_count,
		1,
	); if c.institution_relationship_count != 1 do return
	index := 0
	relationship :=
		c.institution_relationships[index]; testing.expect_value(t, relationship.stance, Institution_Relationship_Stance.Rivalry); testing.expect(t, relationship.policy == .Jurisdiction || relationship.policy == .Accountability || relationship.policy == .Rescue); testing.expect(t, semantic_has(relationship.semantic_tags, .Contested))
	for i in 0 ..< MAX_NEEDS do c.needs[i] = {}; used: [NEED_KIND_COUNT]bool; need, derived := derive_historical_need(&c, &used); testing.expect(t, derived); testing.expect_value(t, need.kind, Need_Kind.Institution_Dispute); testing.expect_value(t, need.institution, relationship.institution_a); testing.expect_value(t, need.opposing_institution, relationship.institution_b); testing.expect_value(t, need.source_event, relationship.last_event)
	c.needs[0] =
		need; c.needs[0].active = true; c.needs[0].cost = 2; c.needs[0].detail = "Reconcile the authority dispute."; c.needs[0].semantic_tags = semantic_tags_for_need(need.kind); testing.expect(t, resolve_need(&c, 0)); relationship = c.institution_relationships[index]; testing.expect_value(t, relationship.stance, Institution_Relationship_Stance.Accord); testing.expect(t, relationship.strength > 0)
}

@(test)
reported_settlements_form_a_causally_convergent_network :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 811)
	record_event(
		&c,
		.Settlement_Reported,
		"Harbor One reported.",
		1,
		70,
		1,
		settlement_id = 1,
	); first := c.event_sequence
	record_event(
		&c,
		.Settlement_Reported,
		"Harbor Two reported.",
		2,
		48,
		2,
		settlement_id = 2,
	); second := c.event_sequence
	c.settlements[0] = {
		id                 = 1,
		name               = "Harbor One",
		active             = true,
		reported           = true,
		viability          = 70,
		founding_community = 1,
		founder_ship       = 1,
		last_report_event  = first,
	}; c.settlements[1] = {
		id                 = 2,
		name               = "Harbor Two",
		active             = true,
		reported           = true,
		viability          = 48,
		founding_community = 2,
		founder_ship       = 2,
		last_report_event  = second,
	}; c.settlement_count = 2
	advance_settlement_relationships(
		&c,
	); testing.expect_value(t, c.settlement_relationship_count, 1); relationship := c.settlement_relationships[0]; testing.expect_value(t, relationship.kind, Settlement_Relationship_Kind.Dependency); event_at := event_index_by_sequence(&c, relationship.origin_event); testing.expect(t, event_at >= 0); if event_at >= 0 {event := c.events[event_at]; testing.expect_value(t, event.cause_count, 2); testing.expect(t, event_cites(event, first)); testing.expect(t, event_cites(event, second))}
}

@(test)
pivotal_memories_survive_routine_history_pressure :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		99,
	); record_event(&c, .Ship_Scarred, "Wayward Light acquired a permanent scar.", 1); scar_event := c.event_sequence
	for i in 0 ..< MAX_SHIP_MEMORIES + 4 do record_event(&c, .Ship_Damaged, "Routine damage report.", 1, 1)
	found :=
		false; for memory in c.ships[0].memories[:c.ships[0].memory_count] do if memory.event_sequence == scar_event do found = true; testing.expect(t, found)
	testing.expect(
		t,
		c.ships[0].archived_memory_count > 0,
	); testing.expect(t, semantic_has(c.ships[0].archived_memory_tags, .Memory))
	latest_damage := latest_event_matching_tags(
		&c,
		make_semantic_tags(.Ship, .Damage),
	); testing.expect(t, latest_damage > scar_event)
}

@(test)
jurisdiction_dispute_reconciles_through_a_causal_need :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 314)
	testing.expect(
		t,
		enact_precedent_fixture(
			&c,
			.Ship_Sovereignty,
			"Captains retain operational authority.",
			true,
		),
	)
	rule_event := precedent_event_for(&c, .Ship_Sovereignty)
	record_ship_autonomy(&c, "Wayward Light chose its own vector.", 1, 1)
	index := institution_ship_relationship_index(&c, 2, 1)
	testing.expect(t, index >= 0)
	if index < 0 do return
	relationship := c.institution_ship_relationships[index]
	testing.expect_value(t, relationship.stance, Institution_Ship_Stance.Contested)
	testing.expect_value(t, relationship.precedent_event, rule_event)
	testing.expect(t, semantic_has(relationship.semantic_tags, .Jurisdiction))
	for i in 0 ..< MAX_NEEDS do c.needs[i] = {}
	used: [NEED_KIND_COUNT]bool; need, derived := derive_historical_need(&c, &used)
	testing.expect(
		t,
		derived,
	); testing.expect_value(t, need.kind, Need_Kind.Jurisdiction_Dispute); testing.expect_value(t, need.source_event, relationship.last_event)
	c.needs[0] =
		need; c.needs[0].active = true; c.needs[0].cost = 2; c.needs[0].detail = need_detail(need.kind); c.needs[0].semantic_tags = semantic_tags_for_need(need.kind)
	testing.expect(t, resolve_need(&c, 0))
	relationship = c.institution_ship_relationships[index]
	testing.expect_value(t, relationship.stance, Institution_Ship_Stance.Reconciled)
	latest_at := event_index_by_sequence(
		&c,
		relationship.last_event,
	); testing.expect(t, latest_at >= 0)
	if latest_at >=
	   0 {testing.expect_value(t, c.events[latest_at].kind, Event_Kind.Jurisdiction_Changed); cause_at := event_index_by_sequence(&c, c.events[latest_at].cause_sequence); testing.expect(t, cause_at >= 0); if cause_at >= 0 do testing.expect_value(t, c.events[cause_at].kind, Event_Kind.Need_Resolved)}
}

import "core:strings"

@(test)
mitigated_need_has_a_smaller_recorded_setback :: proc(t: ^testing.T) {
	full: Campaign
	campaign_init(&full, 91)
	soft: Campaign
	campaign_init(&soft, 91)
	for i in 0 ..< MAX_NEEDS {full.needs[i] = {}; soft.needs[i] = {}}
	full.needs[0] = {
		kind      = .Archive_Staffing,
		community = 1,
		deadline  = 1,
		cost      = 9,
		active    = true,
		detail    = "Staff the archive",
		response  = .Open,
	}
	soft.needs[0] = full.needs[0]
	start_soft_knowledge := soft.material_economy.knowledge.deployable_capacity
	testing.expect(t, mitigate_need(&soft, 0))
	neglect_open_needs(&full)
	neglect_open_needs(&soft)
	testing.expect(t, full.strategic.cohesion < soft.strategic.cohesion)
	testing.expect_value(t, soft.needs[0].response, Need_Response.Neglected)
	testing.expect(t, soft.material_economy.knowledge.deployable_capacity < start_soft_knowledge)
}

@(test)
deferred_need_survives_one_season_and_cannot_be_deferred_twice :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 92)
	for i in 0 ..< MAX_NEEDS do c.needs[i] = {}
	c.needs[0] = {
		kind      = .Representation,
		community = 1,
		deadline  = 1,
		cost      = 8,
		active    = true,
		detail    = "Representation",
		response  = .Open,
	}
	testing.expect(t, defer_need(&c, 0))
	neglect_open_needs(&c)
	testing.expect(t, c.needs[0].active)
	testing.expect_value(t, c.needs[0].deadline, i32(2))
	testing.expect(t, !defer_need(&c, 0))
}

@(test)
emergency_forecast_is_pure_and_accounts_for_mitigation :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 93)
	for i in 0 ..< MAX_NEEDS do c.needs[i] = {}
	c.strategic.cohesion = 12
	c.needs[0] = {
		kind      = .Sustenance_Shortfall,
		community = 1,
		deadline  = 1,
		cost      = 9,
		active    = true,
		detail    = "Food",
		response  = .Open,
	}
	before_rng := c.rng_sequence
	open := forecast_emergency_pressure(&c)
	testing.expect_value(t, c.rng_sequence, before_rng)
	c.needs[0].response = .Mitigated
	soft := forecast_emergency_pressure(&c)
	testing.expect(t, soft.cohesion_loss < open.cohesion_loss)
	testing.expect(t, soft.reserve_loss < open.reserve_loss)
}

@(test)
constitutional_emergency_records_count_first_season_and_cause :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 94)
	for i in 0 ..< MAX_NEEDS do c.needs[i] = {}
	c.strategic.cohesion = 0
	c.strategic.cohesion = 0
	advance_season(&c)
	testing.expect_value(t, c.emergency_count, i32(1))
	testing.expect_value(t, c.first_emergency_season, i32(1))
	testing.expect_value(t, c.last_emergency_cause, Emergency_Cause.Cohesion)
	testing.expect_value(
		t,
		c.strategic.cohesion,
		i32(0),
	); testing.expect_value(t, c.strategic.cohesion, i32(0))
}

@(test)
emergency_recovery_uses_hysteresis_and_reaches_a_structural_target :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 771); c.strategic.cohesion = 0; c.strategic.cohesion = 0; advance_season(&c)
	testing.expect(
		t,
		c.emergency_recovery_active,
	); testing.expect(t, c.emergency_recovery_target > EMERGENCY_FLOOR); count := c.emergency_count
	advance_season(&c); testing.expect_value(t, c.emergency_count, count)
	for _ in 0 ..< 2 {c.strategic.cohesion = 100; c.strategic.cohesion = 100; advance_season(&c)}
	testing.expect(
		t,
		!c.emergency_recovery_active,
	); testing.expect_value(t, c.emergency_count, count)
}

@(test)
same_cause_emergency_has_tempo_specific_refractory_period_without_passive_grant :: proc(
	t: ^testing.T,
) {
	measured: Campaign
	campaign_init(
		&measured,
		1801,
	); measured.story_tempo = .Measured; measured.strategic.cohesion = 10; before := measured.strategic.cohesion; advance_season(&measured)
	testing.expect_value(
		t,
		measured.emergency_count,
		i32(1),
	); testing.expect(t, measured.strategic.cohesion <= before); until := measured.emergency_refractory_until_by_cause[int(Emergency_Cause.Cohesion)]; testing.expect_value(t, until - measured.season, i32(6))
	volatile: Campaign
	campaign_init(
		&volatile,
		1801,
	); volatile.story_tempo = .Volatile; volatile.strategic.cohesion = 10; advance_season(&volatile); testing.expect_value(t, volatile.emergency_refractory_until_by_cause[int(Emergency_Cause.Cohesion)] - volatile.season, i32(4))
}

@(test)
recurring_emergency_blocks_temporary_relief_until_structural_command :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1802,
	); c.strategic.cohesion = 10; advance_season(&c); first := c.emergency_count
	c.emergency_recovery_active =
		false; c.season = c.emergency_refractory_until_by_cause[int(Emergency_Cause.Cohesion)] - 1; c.strategic.cohesion = 10; advance_season(&c)
	testing.expect_value(
		t,
		c.emergency_count,
		first + 1,
	); testing.expect(t, c.emergency_structural_response_pending); testing.expect(t, !publish_discovery(&c)); target := c.emergency_recovery_target
	testing.expect(
		t,
		apply_emergency_structural_response(&c, .Protect_Development),
	); testing.expect(t, !c.emergency_structural_response_pending); testing.expect(t, c.emergency_recovery_target < target); testing.expect(t, c.emergency_preparedness >= 64)
}

@(test)
protected_development_capacity_cannot_be_spent_as_temporary_relief :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1803); c.material_economy.fleet.stock.supplies = 20
	testing.expect(
		t,
		!use_contingency_reserves(&c),
	); testing.expect_value(t, fleet_supply(&c), i32(20)); testing.expect(t, queue_project(&c, .Analyze_Discovery))
}

@(test)
pre_emergency_warning_surfaces_before_constitutional_incidence :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1804); c.strategic.cohesion = EMERGENCY_FLOOR + 8; advance_season(&c)
	testing.expect_value(
		t,
		c.emergency_count,
		i32(0),
	); testing.expect(t, c.emergency_structural_response_pending); testing.expect(t, !c.emergency_structural_response_required)
	found :=
		false; for event in c.events[:c.event_count] do if event.kind == .Need_Surfaced && strings.contains(event.detail, "pre-emergency warning band") do found = true; testing.expect(t, found)
}

@(test)
structural_preparedness_prevents_first_emergency_without_resource_grant :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1805,
	); c.strategic.cohesion = EMERGENCY_FLOOR + 8; advance_season(&c); hope := c.strategic.cohesion; cohesion := c.strategic.cohesion
	testing.expect(
		t,
		apply_emergency_structural_response(&c, .Institutional_Recovery),
	); testing.expect_value(t, c.strategic.cohesion, hope); testing.expect_value(t, c.strategic.cohesion, cohesion); testing.expect(t, c.emergency_preparedness >= 8)
	c.strategic.cohesion =
		EMERGENCY_FLOOR -
		2; advance_season(&c); testing.expect_value(t, c.emergency_count, i32(0)); testing.expect(t, c.strategic.cohesion <= EMERGENCY_FLOOR)
}

@(test)
warning_band_forecast_is_bot_visible_before_the_floor :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1806,
	); c.strategic.cohesion = EMERGENCY_FLOOR + 10; p := forecast_emergency_pressure(&c)
	testing.expect(t, p.critical); testing.expect(t, p.projected_cohesion > EMERGENCY_FLOOR)
}

@(test)
paid_warning_band_relief_builds_finite_preparedness :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1807,
	); c.strategic.cohesion = EMERGENCY_FLOOR + 10; c.material_economy.knowledge.deployable_capacity = 20; c.material_economy.knowledge.deployable_capacity = 20
	testing.expect(
		t,
		publish_discovery(&c),
	); testing.expect(t, c.emergency_preparedness > 0); prepared := c.emergency_preparedness
	c.strategic.cohesion =
		EMERGENCY_FLOOR -
		1; advance_season(&c); testing.expect_value(t, c.emergency_count, i32(0)); testing.expect(t, c.emergency_preparedness < prepared)
}

@(test)
repeated_temporary_relief_has_a_visible_effectiveness_limit :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		772,
	); c.material_economy.knowledge.deployable_capacity = 40; c.strategic.cohesion = 20
	before :=
		c.strategic.cohesion; testing.expect(t, publish_discovery(&c)); first := c.strategic.cohesion - before
	before =
		c.strategic.cohesion; testing.expect(t, publish_discovery(&c)); second := c.strategic.cohesion - before
	testing.expect(
		t,
		second < first,
	); testing.expect_value(t, c.emergency_response_uses[0], i32(2)); testing.expect(t, c.events[c.event_count - 1].value == second)
}

@(test)
stable_ids_drive_expeditions :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 17)
	testing.expect_value(t, ship_index(&c, Ship_ID(1)), 0)
	testing.expect(t, commission_expedition(&c, []Ship_ID{1, 2, 3, 5}, "Evaluate a possible home"))
	testing.expect_value(t, c.expedition.ships[0], Ship_ID(1))
	testing.expect(t, c.ships[0].committed)
}
