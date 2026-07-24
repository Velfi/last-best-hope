package game_tests

import "core:fmt"
import "core:testing"

prepare_accounted_ending_fixture :: proc(c: ^Campaign) {
	c.sustainable_seasons = 3; c.material_economy.fleet.maintenance_debt = 0
	c.compact.calls[0] = {id = 1, status = .Completed}; c.compact.call_count = 1
}

prepare_sustainable_settlement_fixture :: proc(
	c: ^Campaign,
	index: int,
	id: Settlement_ID,
	name: string,
	viability: i32,
) {
	c.settlements[index] = {
		id         = id,
		name       = name,
		region     = "Ending fixture",
		population = 2000,
		viability  = viability,
		liberty    = 70,
		active     = true,
	}
	c.settlement_count = max(c.settlement_count, index + 1)
	_ = initialize_settlement_economy(
		&c.settlement_economies,
		c,
		&c.settlements[index],
	); e := &c.settlement_economies.economies[c.settlement_economies.count - 1]; e.stock.food = max(e.population / 100, 1) + 20; e.lifecycle = .Self_Sustaining; e.sustainable_seasons = 3
}

prepare_passage_objectives_fixture :: proc(c: ^Campaign, count: i32) {
	c.dark_strategy_records = make(
		[dynamic]Dark_Strategy_Statistics,
		1,
		campaign_storage_allocator(),
	); c.dark_strategy_record_count = 1; c.dark_strategy_records[0].objective_successes = count
}

@(test)
fleet_starts_with_vertical_slice_cast :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c, 7)
	testing.expect_value(t, active_ship_count(&c), 12)
	testing.expect_value(t, total_population(&c), i32(55000))
	testing.expect_value(t, c.community_count, INITIAL_COMMUNITIES)}
@(test)
seeded_history_is_deterministic :: proc(t: ^testing.T) {a: Campaign
	campaign_init(&a, 91); b: Campaign
	campaign_init(&b, 91)
	for season := 0; season < 6; season += 1 {
		advance_season(&a)
		advance_season(&b)
	}
	testing.expect_value(t, a.rng_state, b.rng_state)
	testing.expect_value(t, a.strategic, b.strategic)
	testing.expect_value(t, a.ending, b.ending)}
@(test)
season_varies_new_needs_after_the_opening_board :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c)
	advance_season(&c)
	count := 0
	for n in c.needs do if n.active do count += 1
	testing.expect_value(t, count, 1)
	for &need in c.needs do need = {}
	c.season = 3
	surface_needs(&c)
	count = 0
	for n in c.needs do if n.active do count += 1
	testing.expect_value(t, count, 2)
	for &need in c.needs do need = {}
	c.season = 5
	surface_needs(&c)
	count = 0
	for n in c.needs do if n.active do count += 1
	testing.expect_value(t, count, 0)}
@(test)
expedition_creates_ship_history_and_candidate :: proc(t: ^testing.T) {c: Campaign
	campaign_init(
		&c,
		4,
	); ok := commission_expedition(&c, []Ship_ID{1, 2, 3, 5}, "Evaluate a possible home")
	testing.expect(t, ok)
	result := resolve_expedition(&c)
	testing.expect(t, result.outcome != .Lost)
	testing.expect_value(t, c.world_survey_count, 1)
	testing.expect_value(t, result.survey.funnel.systems, i32(1))
	if result.discovered_world.valid do testing.expect(t, celestial_reference_valid(&c, result.discovered_world))
	testing.expect(t, c.ships[0].history_count == 1)}
@(test)
repair_and_refit_change_ship_state :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c); c.ships[0].damage = 3
	testing.expect(t, queue_project(&c, .Repair, 1))
	advance_projects(&c)
	testing.expect_value(t, c.ships[0].damage, i32(0))
	testing.expect(t, c.ships[0].memory_count > 0)
	testing.expect_value(
		t,
		c.ships[0].memories[c.ships[0].memory_count - 1].kind,
		Event_Kind.Ship_Repaired,
	)
	testing.expect(t, c.ships[0].history_record_count > 0)
	testing.expect(t, queue_project(&c, .Refit, 1))
	advance_projects(&c)
	testing.expect_value(t, c.ships[0].power, i32(9))}
@(test)
settlement_is_irreversible_and_reports_later :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c, 2)
	_ = install_test_candidate_home(&c)
	c.colony_package_ready = true
	before := total_population(&c)
	testing.expect(t, found_test_settlement(&c, 2, 12, "Harbor One"))
	testing.expect(t, !c.ships[11].active)
	testing.expect(t, total_population(&c) < before)
	advance_season(&c)
	testing.expect(t, !c.settlements[0].reported)
	advance_season(&c)
	testing.expect(t, c.settlements[0].reported)}
@(test)
settlement_reports_form_a_recurring_causal_history :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 22); _ = install_test_candidate_home(&c); c.colony_package_ready = true
	testing.expect(t, found_test_settlement(&c, 2, 12, "Harbor One"))
	settlement := &c.settlements[0]
	testing.expect_value(t, settlement.id, Settlement_ID(1))
	founding_event := settlement.founding_event
	c.season = settlement.report_due; advance_settlements(&c)
	first_report := settlement.last_report_event
	testing.expect_value(t, settlement.report_count, i32(1))
	testing.expect_value(t, c.events[c.event_count - 1].cause_sequence, founding_event)
	c.season = settlement.report_due; advance_settlements(&c)
	testing.expect_value(t, settlement.report_count, i32(2))
	testing.expect(t, settlement.last_report_event > first_report)
	testing.expect_value(t, c.events[c.event_count - 1].cause_sequence, first_report)
}

@(test)
settlement_defense_changes_its_future_record :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 31)
	c.settlements[0] = {
		id                 = 1,
		name               = "Low Harbor",
		population         = 2400,
		viability          = 45,
		active             = true,
		reported           = true,
		founding_community = 2,
		founder_ship       = 12,
		last_report_event  = 77,
	}
	c.settlement_count = 1
	used: [NEED_KIND_COUNT]bool
	need, derived := derive_historical_need(&c, &used)
	testing.expect(t, derived)
	testing.expect_value(t, need.kind, Need_Kind.Settlement_Defense)
	testing.expect_value(t, need.settlement, Settlement_ID(1))
	testing.expect_value(t, need.source_event, u64(77))
	need.active = true; need.cost = 1; need.deadline = c.season + 1; c.needs[0] = need
	before := c.settlements[0].viability
	testing.expect(t, resolve_need(&c, 0))
	testing.expect_value(t, c.settlements[0].viability, before + 10)
	testing.expect_value(t, c.events[c.event_count - 1].kind, Event_Kind.Settlement_Supported)
	testing.expect_value(
		t,
		c.events[c.event_count - 1].cause_sequence,
		c.events[c.event_count - 3].sequence,
	)

	c.needs[0] = {
		kind         = .Settlement_Defense,
		community    = 2,
		ship         = 7,
		deadline     = c.season + 1,
		active       = true,
		settlement   = 1,
		source_event = c.settlements[0].last_report_event,
	}
	before = c.settlements[0].viability
	neglect_open_needs(&c)
	testing.expect_value(t, c.settlements[0].viability, before - 10)
	testing.expect_value(t, c.events[c.event_count - 1].kind, Event_Kind.Settlement_Setback)
	testing.expect_value(
		t,
		c.events[c.event_count - 1].cause_sequence,
		c.events[c.event_count - 3].sequence,
	)
}
@(test)
low_liberty_settlement_petitions_under_prior_law :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 37)
	testing.expect(
		t,
		enact_precedent_fixture(
			&c,
			.Ship_Sovereignty,
			"Ships and settlements retain civil authority.",
			true,
		),
	)
	rule_event := c.precedents[0].event_sequence
	record_event(
		&c,
		.Settlement_Reported,
		"Narrow Harbor",
		12,
		70,
		2,
		settlement_id = 1,
	); report_event := c.event_sequence
	c.settlements[0] = {
		id                 = 1,
		name               = "Narrow Harbor",
		population         = 2200,
		viability          = 70,
		liberty            = 40,
		active             = true,
		reported           = true,
		founding_community = 2,
		founder_ship       = 12,
		last_report_event  = report_event,
	}; c.settlement_count = 1
	used: [NEED_KIND_COUNT]bool
	need, derived := derive_historical_need(&c, &used)
	testing.expect(t, derived); testing.expect_value(t, need.kind, Need_Kind.Settlement_Charter)
	testing.expect_value(
		t,
		need.source_event,
		report_event,
	); testing.expect_value(t, need.precedent_event, rule_event)
	testing.expect_value(t, precedent_need_cost_modifier(&c, .Settlement_Charter), i32(-2))
	need.active = true; need.deadline = c.season + 1; need.cost = 5; c.needs[0] = need
	testing.expect(t, resolve_need(&c, 0))
	testing.expect_value(t, c.settlements[0].liberty, i32(60))
	last := c.events[c.event_count - 1]
	testing.expect_value(t, last.kind, Event_Kind.Settlement_Charter_Changed)
	testing.expect_value(t, last.precedent_event, rule_event)
	testing.expect_value(t, last.cause_sequence, c.events[c.event_count - 3].sequence)
}
@(test)
unanswered_charter_petition_changes_later_settlement_state :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 38)
	c.settlements[0] = {
		id                 = 1,
		name               = "Narrow Harbor",
		population         = 2200,
		viability          = 70,
		liberty            = 40,
		active             = true,
		reported           = true,
		founding_community = 2,
		founder_ship       = 12,
		last_report_event  = 4,
	}; c.settlement_count = 1
	c.needs[0] = {
		kind         = .Settlement_Charter,
		community    = 2,
		ship         = 12,
		deadline     = c.season + 1,
		active       = true,
		settlement   = 1,
		source_event = 4,
	}
	neglect_open_needs(&c)
	testing.expect_value(t, c.settlements[0].liberty, i32(32))
	testing.expect_value(t, c.settlements[0].viability, i32(67))
	testing.expect_value(
		t,
		c.events[c.event_count - 1].kind,
		Event_Kind.Settlement_Charter_Changed,
	)
	testing.expect_value(
		t,
		c.settlements[0].last_report_event,
		c.events[c.event_count - 1].sequence,
	)
}
@(test)
open_archives_propagate_into_settlement_politics :: proc(t: ^testing.T) {
	closed: Campaign
	campaign_init(
		&closed,
		45,
	); _ = install_test_candidate_home(&closed); closed.colony_package_ready = true
	testing.expect(t, found_test_settlement(&closed, 2, 12, "Closed Harbor", false))
	testing.expect_value(t, closed.settlements[0].archive_id, Archive_ID(0))

	c: Campaign
	campaign_init(
		&c,
		45,
	); testing.expect(t, enact_precedent_fixture(&c, .Open_Archives, "Knowledge belongs to every harbor.", true)); rule_event := c.precedents[0].event_sequence
	_ = install_test_candidate_home(&c); c.colony_package_ready = true
	testing.expect(t, found_test_settlement(&c, 2, 12, "Reader's Harbor", false))
	settlement := &c.settlements[0]
	testing.expect_value(t, settlement.archive_id, Archive_ID(2))
	archive_event := c.events[c.event_count - 1]
	testing.expect_value(t, archive_event.kind, Event_Kind.Archive_Established)
	testing.expect_value(t, archive_event.cause_sequence, settlement.founding_event)
	testing.expect_value(t, archive_event.archive_id, Archive_ID(2))

	settlement.viability = 70
	before_knowledge :=
		c.material_economy.knowledge.deployable_capacity; c.season = settlement.report_due; advance_settlements(&c)
	testing.expect(t, c.material_economy.knowledge.deployable_capacity >= before_knowledge + 4)
	used: [NEED_KIND_COUNT]bool; need, derived := derive_historical_need(&c, &used)
	testing.expect(t, derived); testing.expect_value(t, need.kind, Need_Kind.Settlement_Charter)
	testing.expect_value(
		t,
		need.archive_id,
		Archive_ID(2),
	); testing.expect_value(t, need.precedent_event, rule_event)
	need.active = true; need.cost = 4; need.deadline = c.season + 1; c.needs[0] = need
	liberty_before :=
		settlement.liberty; knowledge_before := c.material_economy.knowledge.deployable_capacity
	testing.expect(t, resolve_need(&c, 0))
	testing.expect_value(t, settlement.liberty, liberty_before + 20)
	testing.expect_value(t, c.material_economy.knowledge.deployable_capacity, knowledge_before + 3)
	testing.expect_value(t, c.events[c.event_count - 1].archive_id, Archive_ID(2))
}
@(test)
campaign_continues_until_player_concludes_it :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c, 12, .Open)
	for _ in 0 ..< 6 do advance_season(&c)
	testing.expect_value(t, c.ending, Ending.In_Progress)
	testing.expect_value(t, c.max_seasons, i32(0))
	testing.expect(t, conclude_chronicle(&c))
	testing.expect(t, c.ending_finale.active)
	testing.expect_value(t, c.ending, Ending.In_Progress)
	testing.expect(t, !conclude_chronicle(&c))
	c.season = c.ending_finale.ends_season
	testing.expect(t, conclude_chronicle(&c))
	testing.expect(
		t,
		c.ending == .Nomadic_Fleet || c.ending == .Transformed || c.ending == .Fragmented_Survival,
	)}

@(test)
finale_locks_earned_identity_and_grades_the_result_after_three_seasons :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		5310,
	); c.length = .Open; c.max_seasons = 0; c.current_situation = {}; prepare_passage_objectives_fixture(&c, 2); defer delete(c.dark_strategy_records)
	testing.expect(t, conclude_chronicle(&c)); testing.expect(t, c.ending_finale.active)
	testing.expect_value(t, c.ending_finale.ending, Ending.Nomadic_Fleet)
	locked :=
		c.ending_finale.ending; c.uncontained_hazard_count = 4; c.material_economy.fleet.maintenance_debt = 20
	c.season = c.ending_finale.ends_season; testing.expect(t, conclude_chronicle(&c))
	testing.expect_value(
		t,
		c.ending,
		locked,
	); testing.expect_value(t, c.ending_quality, Ending_Quality.Stable)
}
@(test)
campaign_ends_when_the_traveling_fleet_dissolves :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c, 13)
	for &ship in c.ships[:c.ship_count] {ship.active = false; ship.departure = .Settlement}
	advance_season(&c)
	testing.expect_value(t, c.ending, Ending.Fragmented_Survival)
	testing.expect_value(t, c.season, i32(0))
}
@(test)
zero_hope_creates_recoverable_emergency :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c)
	c.strategic.cohesion = 0
	advance_season(&c)
	testing.expect(t, c.constitutional_emergency)
	testing.expect(t, c.ending == .In_Progress)
	testing.expect_value(t, c.strategic.cohesion, i32(0))
	testing.expect(t, c.emergency_recovery_active)}
@(test)
seasonal_hazards_are_seeded_and_leave_recoverable_costs :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 17); b: Campaign
	campaign_init(&b, 17)
	for season := 0; season < 6; season += 1 {advance_season(&a); advance_season(&b)}
	testing.expect_value(t, a.hazard_count, b.hazard_count)
	testing.expect_value(t, a.uncontained_hazard_count, b.uncontained_hazard_count)
	testing.expect_value(t, a.strategic, b.strategic)
	testing.expect(t, a.hazard_count > 0)
	for ship in a.ships[:a.ship_count] do testing.expect(t, !ship.active || ship.damage < ship.power)
}
@(test)
repeated_hazards_prevent_an_unsettled_nomadic_win :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c)
	c.hazard_count = 4
	prepare_accounted_ending_fixture(
		&c,
	); prepare_passage_objectives_fixture(&c, 1); defer delete(c.dark_strategy_records); c.transformations.record_count = 2
	testing.expect_value(t, evaluate_ending(&c), Ending.Transformed)

	harbor: Campaign
	campaign_init(&harbor)
	harbor.hazard_count = 4
	prepare_accounted_ending_fixture(
		&harbor,
	); prepare_sustainable_settlement_fixture(&harbor, 0, 1, "Shelter", 70)
	testing.expect_value(t, evaluate_ending(&harbor), Ending.New_Home)
}
@(test)
strategic_pressure_uses_all_three_axes_and_stable_recovery :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1901)
	baseline := strategic_pressure(&c); testing.expect(t, !baseline.emergency)
	c.material_economy.fleet.stock.supplies = fleet_operating_floor(&c).stock.supplies - 1
	reserves := strategic_pressure(
		&c,
	); testing.expect(t, reserves.emergency); testing.expect_value(t, reserves.cause, Emergency_Cause.Reserves)
	c.material_economy.fleet.stock.supplies = 135; c.capacities.compute.damaged = c.capacities.compute.total; c.capacities.manpower.damaged = c.capacities.manpower.total; c.capacities.raw_materials.damaged = c.capacities.raw_materials.total
	capacity := strategic_pressure(
		&c,
	); testing.expect(t, capacity.emergency); testing.expect_value(t, capacity.cause, Emergency_Cause.Capacity)
}
@(test)
persistent_hazard_pressure_is_recoverable_and_not_an_automatic_fragmentation :: proc(
	t: ^testing.T,
) {
	c: Campaign
	campaign_init(&c, 1902); c.uncontained_hazard_count = 2; c.season = hazard_pressure_cadence(&c)
	advance_persistent_hazard_pressure(
		&c,
	); testing.expect_value(t, c.uncontained_hazard_count, i32(1))
	c.uncontained_hazard_count = 2; testing.expect_value(t, c.ending, Ending.In_Progress); testing.expect_value(t, evaluate_ending(&c), Ending.Fragmented_Survival)
}
@(test)
three_distinct_viable_endings_are_reachable :: proc(t: ^testing.T) {
	home: Campaign
	campaign_init(
		&home,
	); prepare_accounted_ending_fixture(&home); prepare_sustainable_settlement_fixture(&home, 0, 1, "Pale Harbor", 70); testing.expect_value(t, evaluate_ending(&home), Ending.New_Home)
	network: Campaign
	campaign_init(
		&network,
	); prepare_accounted_ending_fixture(&network); prepare_sustainable_settlement_fixture(&network, 0, 1, "Pale Harbor", 70); prepare_sustainable_settlement_fixture(&network, 1, 2, "Second Light", 65); network.settlement_economies.flows[0] = {
		active    = true,
		condition = .Stable,
	}; network.settlement_economies.flow_count = 1; testing.expect_value(t, evaluate_ending(&network), Ending.Harbor_Network)
	nomads: Campaign
	campaign_init(
		&nomads,
	); prepare_accounted_ending_fixture(&nomads); prepare_passage_objectives_fixture(&nomads, 2); defer delete(nomads.dark_strategy_records); testing.expect_value(t, evaluate_ending(&nomads), Ending.Nomadic_Fleet)
}
@(test)
promises_change_legitimacy_on_deadline :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c); testing.expect(t, add_promise(&c, 1, 1, "Repair the Common Hearth"))
	before := c.strategic.cohesion
	advance_season(&c)
	advance_season(&c)
	testing.expect_value(t, c.promises[0].status, Promise_Status.Broken)
	testing.expect(t, c.strategic.cohesion < before)}
@(test)
attributes_institutions_archives_and_precedents_persist :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c)
	testing.expect_value(t, c.attributes[4].class, Attribute_Class.Value)
	testing.expect(t, c.institutions[0].active)
	testing.expect(t, c.archives[0].unique)
	before := c.material_economy.knowledge.deployable_capacity
	testing.expect(
		t,
		enact_precedent_fixture(&c, .Open_Archives, "Knowledge belongs to every harbor.", true),
	)
	testing.expect_value(t, c.material_economy.knowledge.deployable_capacity, before)
	testing.expect(t, c.precedents[0].defining)
	testing.expect(t, c.precedents[0].id != 0 && c.precedents[0].source_decision != 0)
	snapshot := campaign_snapshot(&c)
	defer campaign_destroy_heap(snapshot)
	testing.expect_value(t, snapshot.precedent_count, 1)}
