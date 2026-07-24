package game_tests

import "core:testing"

economy_test_settlement :: proc(
	id: u32,
	name: string,
	population: i32,
	viability: i32,
	ship: Ship_ID,
) -> Settlement {s := Settlement {
		id                            = Settlement_ID(id),
		name                          = name,
		population                    = population,
		viability                     = viability,
		liberty                       = 70,
		active                        = true,
		founder_ship                  = ship,
		participating_ship_count      = 1,
		participating_community_count = 1,
		founding_event                = u64(id),
	}; s.participating_ships[0] = ship; return s}

@(test)
settlement_economy_initialization_is_derived_and_names_are_distinct :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		801,
	); n: Settlement_Economy_Network; s1 := economy_test_settlement(1, "Pale Harbor", 2400, 68, c.ships[1].id); s2 := economy_test_settlement(2, "Pale Harbor", 1900, 62, c.ships[2].id)
	testing.expect(
		t,
		initialize_settlement_economy(&n, &c, &s1, "commons charter"),
	); testing.expect(t, initialize_settlement_economy(&n, &c, &s2, "archive charter")); testing.expect(t, n.economies[0].identity.name != n.economies[1].identity.name); testing.expect(t, n.economies[0].stock.food > 0 && n.economies[0].stock.people == 2400 && n.economies[0].infrastructure == 68)
}

@(test)
named_trade_conserves_stock_and_route_interruption_changes_both_ledgers :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		802,
	); n: Settlement_Economy_Network; a := economy_test_settlement(1, "Orchard", 2000, 75, c.ships[1].id); b := economy_test_settlement(2, "Foundry", 1800, 70, c.ships[2].id); testing.expect(t, initialize_settlement_economy(&n, &c, &a)); testing.expect(t, initialize_settlement_economy(&n, &c, &b)); n.economies[0].stock.food = 100; n.economies[1].stock.food = 2; flow := add_trade_flow(&n, "Orchard winter allotment", a.id, b.id, .Food, 20, 41, "Ilex Gate", "Gate Wardens", "escort covenant", .Strained, 5, 2); before := n.economies[0].stock.food + n.economies[1].stock.food
	testing.expect(
		t,
		settle_trade_flow(&n, flow),
	); f := n.flows[flow]; after := n.economies[0].stock.food + n.economies[1].stock.food + f.lost; testing.expect_value(t, after, before); testing.expect(t, f.shipped > 0 && f.delivered > 0 && n.economies[1].imports.food == f.delivered); producer_after := n.economies[0].stock.food; consumer_after := n.economies[1].stock.food; interrupt_trade_route(&n, 41); testing.expect(t, settle_trade_flow(&n, flow)); testing.expect_value(t, n.flows[flow].shipped, i64(0)); testing.expect_value(t, n.economies[0].stock.food, producer_after); testing.expect_value(t, n.economies[1].stock.food, consumer_after); testing.expect_value(t, n.economies[1].lifecycle, Settlement_Lifecycle.Dependent)
}

@(test)
three_settlement_300_season_ledgers_are_deterministic_and_recoverable :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 803); a, b: Settlement_Economy_Network
	for i in 0 ..< 3 {s := economy_test_settlement(u32(i + 1), i == 0 ? "Greenwater" : i == 1 ? "Kiln" : "Lantern", i32(1800 + i * 300), i32(65 + i * 5), c.ships[i + 1].id); testing.expect(t, initialize_settlement_economy(&a, &c, &s)); testing.expect(t, initialize_settlement_economy(&b, &c, &s))}
	a.economies[0].specialization = .Agricultural; b.economies[0].specialization = .Agricultural; a.economies[1].specialization = .Industrial; b.economies[1].specialization = .Industrial
	fa := add_trade_flow(
		&a,
		"Greenwater grain",
		1,
		2,
		.Food,
		8,
		7,
		"Pilgrim Span",
		"regional council",
		"mutual guarantee",
		.Stable,
		2,
		0,
	); fb := add_trade_flow(&b, "Greenwater grain", 1, 2, .Food, 8, 7, "Pilgrim Span", "regional council", "mutual guarantee", .Stable, 2, 0)
	for _ in 0 ..< 300 {for i in 0 ..< 3 {advance_settlement_economy(&a.economies[i]); advance_settlement_economy(&b.economies[i])}; _ = settle_trade_flow(&a, fa); _ = settle_trade_flow(&b, fb)}
	for i in 0 ..< 3 {testing.expect_value(t, a.economies[i].stock, b.economies[i].stock); testing.expect(t, a.economies[i].identity.name != a.economies[(i + 1) % 3].identity.name)}; testing.expect(t, a.economies[0].exports.food > 0 && a.economies[1].imports.food > 0); recover_settlement(&a.economies[2], {food = 20, goods = 10}, .Recovering); testing.expect_value(t, a.economies[2].lifecycle, Settlement_Lifecycle.Recovering)
}

@(test)
migration_requires_consent_route_food_and_housing_and_archives_reuse_slots :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		804,
	); n: Settlement_Economy_Network; a := economy_test_settlement(1, "Origin", 2000, 70, c.ships[1].id); b := economy_test_settlement(2, "Daughter", 1000, 70, c.ships[2].id); _ = initialize_settlement_economy(&n, &c, &a); _ = initialize_settlement_economy(&n, &c, &b); n.economies[0].stock.food = 100; n.economies[1].housing = 1500; testing.expect(t, !migrate_between_settlements(&n, 1, 2, 200, false, true)); testing.expect(t, !migrate_between_settlements(&n, 1, 2, 200, true, false)); testing.expect(t, migrate_between_settlements(&n, 1, 2, 200, true, true)); testing.expect_value(t, n.economies[0].population, i64(1800)); testing.expect_value(t, n.economies[1].population, i64(1200)); testing.expect(t, archive_settlement_economy(&n, 2, 1, 30, 9)); testing.expect_value(t, n.count, 1); testing.expect_value(t, n.archived_count, 1); testing.expect_value(t, n.archived[0].successor, Settlement_ID(1))
}

@(test)
campaign_season_syncs_economies_and_daughters_inherit_conserved_assets :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		805,
	); s := economy_test_settlement(1, "Morrow", 3000, 75, c.ships[2].id); c.settlements[0] = s; c.settlement_count = 1; advance_settlement_economies(&c); testing.expect_value(t, c.settlement_economies.count, 1); p := &c.settlement_economies.economies[0]; p.stock.food = 100; p.stock.goods = 80; p.stock.services = 30; p.stock.knowledge = 10; p.authority = 70; before := economy_stock_total(p.stock); daughter := sponsor_daughter_settlement(&c.settlement_economies, 1, "Morrow Reach", "Outer Shelf", "daughter commons", 500, {food = 10, goods = 15, services = 4, knowledge = 3}, true, true, 55); testing.expect(t, daughter != 0); d := &c.settlement_economies.economies[1]; testing.expect_value(t, d.identity.origin_event, u64(55)); testing.expect_value(t, p.stock.people + d.stock.people, i64(3000)); testing.expect_value(t, economy_stock_total(p.stock) + economy_stock_total(d.stock), before); testing.expect(t, construct_settlement_ship(d, 5, 2)); testing.expect_value(t, d.stock.ships, i64(1))
}

@(test)
funded_maintenance_preserves_infrastructure_without_automatic_viability_ratchet :: proc(
	t: ^testing.T,
) {
	c: Campaign
	campaign_init(
		&c,
		806,
	); s := economy_test_settlement(1, "Stillwater", 2200, 66, c.ships[1].id); c.settlements[0] = s; c.settlement_count = 1; advance_settlement_economies(&c); e := &c.settlement_economies.economies[0]; e.stock.food = 10000; e.stock.goods = 10000; advance_settlement_economies(&c); condition := e.infrastructure; first := c.settlements[0].viability
	for _ in 0 ..< 24 do advance_settlement_economies(&c)
	testing.expect_value(
		t,
		e.infrastructure,
		condition,
	); testing.expect_value(t, c.settlements[0].viability, first); testing.expect(t, e.assumed_maintenance)
}

@(test)
recorded_settlement_support_is_preserved_but_bounded_and_decays :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		807,
	); s := economy_test_settlement(1, "Bulwark", 2200, 66, c.ships[1].id); c.settlements[0] = s; c.settlement_count = 1; advance_settlement_economies(&c); e := &c.settlement_economies.economies[0]; e.stock.food = 10000; e.stock.goods = 10000; advance_settlement_economies(&c); baseline := c.settlements[0].viability
	c.settlements[0].viability += 10; advance_settlement_economies(&c); supported := c.settlements[0].viability; testing.expect(t, supported > baseline); testing.expect(t, supported <= baseline + 30)
	for _ in 0 ..< 12 do advance_settlement_economies(&c)
	testing.expect_value(
		t,
		c.settlements[0].viability,
		baseline,
	); testing.expect_value(t, e.recorded_development, i32(0)); testing.expect_value(t, e.infrastructure, i32(66))
}

@(test)
repeated_explicit_support_accumulates_to_a_bound_then_decays :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		808,
	); s := economy_test_settlement(1, "Rampart", 2200, 66, c.ships[1].id); c.settlements[0] = s; c.settlement_count = 1; advance_settlement_economies(&c); e := &c.settlement_economies.economies[0]; e.stock.food = 10000; e.stock.goods = 10000; advance_settlement_economies(&c); baseline := c.settlements[0].viability
	prior := baseline
	for _ in 0 ..< 4 {c.settlements[0].viability += 10; advance_settlement_economies(&c); testing.expect(t, c.settlements[0].viability >= prior); prior = c.settlements[0].viability}
	testing.expect(
		t,
		c.settlements[0].viability >= baseline + 25,
	); testing.expect(t, c.settlements[0].viability <= baseline + 30); testing.expect(t, e.recorded_development <= 29)
	for _ in 0 ..< 30 do advance_settlement_economies(&c)
	testing.expect_value(
		t,
		c.settlements[0].viability,
		baseline,
	); testing.expect_value(t, e.recorded_development, i32(0)); testing.expect_value(t, e.infrastructure, i32(66))
}

@(test)
settlement_resilience_and_ui_contracts_expose_named_causal_dependencies :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		809,
	); a := economy_test_settlement(1, "Grower", 2000, 70, c.ships[1].id); b := economy_test_settlement(2, "Clinic", 1800, 68, c.ships[2].id); _ = initialize_settlement_economy(&c.settlement_economies, &c, &a); _ = initialize_settlement_economy(&c.settlement_economies, &c, &b); n := &c.settlement_economies; n.economies[0].stock.food = 100; n.economies[1].stock.food = 1; f := add_trade_flow(n, "named relief grain", 1, 2, .Food, 12, 9, "Mercy Route", "route council", "escort pledge", .Degrading, 3, 2, 77); _ = settle_trade_flow(n, f); view, ok := settlement_ledger_view(&c, 2); testing.expect(t, ok); testing.expect_value(t, view.imports.food, n.flows[f].delivered); views: [dynamic]Trade_Dependency_View; defer delete(views); testing.expect_value(t, trade_dependency_views(&c, 2, &views), 1); testing.expect_value(t, views[0].origin_event, u64(77)); testing.expect_value(t, views[0].route, "Mercy Route"); testing.expect(t, apply_settlement_resilience(n, 2, .Convoy_Escort, .Food, 0, f)); testing.expect_value(t, n.flows[f].guarantee, "settlement convoy escort"); n.economies[1].emergency_reserve.food = 5; testing.expect(t, apply_settlement_resilience(n, 2, .Stockpile_Release, .Food, 3)); testing.expect_value(t, n.economies[1].emergency_reserve.food, i64(2))
}

@(test)
local_surplus_can_assume_fleet_obligation_with_consent :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		810,
	); s := economy_test_settlement(1, "Self Reliance", 2200, 72, c.ships[1].id); c.settlements[0] = s; c.settlement_count = 1; _ = initialize_settlement_economy(&c.settlement_economies, &c, &c.settlements[0]); initialize_obligations(&c); oi := add_obligation(&c, .Settlement_Support, "Support for Self Reliance", 1, 2, 2, 0, 2, settlement = 1); e := &c.settlement_economies.economies[0]; e.stock.goods = 20; e.stock.services = 20; testing.expect(t, !assume_local_obligation(&c, oi, false)); testing.expect(t, assume_local_obligation(&c, oi, true)); testing.expect_value(t, c.obligations.items[oi].status, Obligation_Status.Assumed_By_Settlement); testing.expect(t, e.assumed_maintenance && e.consumed.goods == 2 && e.consumed.services == 3)
}

@(test)
core_daughter_and_bidirectional_fleet_migration_preserve_traceable_people :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		811,
	); s := economy_test_settlement(1, "Source", 3000, 75, c.ships[1].id); s.founding_community = c.communities[0].id; c.settlements[0] = s; c.settlement_count = 1; _ = initialize_settlement_economy(&c.settlement_economies, &c, &c.settlements[0]); e := &c.settlement_economies.economies[0]; e.stock.food = 100; e.stock.goods = 80; e.stock.services = 30; e.authority = 70; daughter := found_core_daughter_settlement(&c, 1, "Source Reach", "Outer Shelf", "daughter commons", 500, {food = 10, goods = 15, services = 4}, true, true, 88); testing.expect(t, daughter != 0); testing.expect_value(t, c.settlement_count, 2); testing.expect_value(t, c.settlements[1].proposal_event, u64(88)); testing.expect_value(t, c.settlement_relationship_count, 1); de := &c.settlement_economies.economies[settlement_economy_index(&c.settlement_economies, daughter)]; de.housing = 1000; de.stock.food = 100; before := de.population; testing.expect(t, migrate_fleet_and_settlement(&c, .Fleet_To_Settlement, c.communities[0].id, daughter, 0, 100, true, true)); testing.expect_value(t, de.population, before + 100); testing.expect(t, migrate_fleet_and_settlement(&c, .Settlement_To_Fleet, c.communities[0].id, daughter, c.ships[0].id, 50, true, true)); testing.expect_value(t, de.population, before + 50)
}

@(test)
settlement_politics_merge_obligations_and_persistent_ship_entry_keep_history :: proc(
	t: ^testing.T,
) {
	c: Campaign
	campaign_init(
		&c,
		812,
	); a := economy_test_settlement(1, "Union", 2400, 72, c.ships[1].id); b := economy_test_settlement(2, "Reach", 1200, 66, c.ships[2].id); c.settlements[0] = a; c.settlements[1] = b; c.settlement_count = 2; _ = initialize_settlement_economy(&c.settlement_economies, &c, &c.settlements[0]); _ = initialize_settlement_economy(&c.settlement_economies, &c, &c.settlements[1]); testing.expect(t, set_settlement_political_relationship(&c, 1, 2, .Federation, 40)); testing.expect_value(t, c.settlement_economies.political_links[0].kind, Regional_Political_Relationship.Federation); oi := add_obligation(&c, .Settlement_Support, "Reach maintenance", 1, 1, 1, 0, 1, settlement = 2); before := c.settlement_economies.economies[0].population + c.settlement_economies.economies[1].population; testing.expect(t, merge_settlements(&c, 1, 2, true, 41)); testing.expect_value(t, c.settlements[1].active, false); testing.expect_value(t, c.obligations.items[oi].settlement, Settlement_ID(1)); testing.expect_value(t, c.settlement_economies.economies[0].population, before)
	initialize_fleet_continuity(
		&c,
	); predecessor := c.ships[0].id; testing.expect(t, retire_ship(&c, predecessor)); e := &c.settlement_economies.economies[0]; e.stock.goods = 30; e.stock.services = 10; e.stock.ships = 2; id := settlement_add_persistent_ship(&c, 1, "Union Tender", "Captain Lio", .Foundry, .Construction, predecessor); testing.expect(t, id != 0); at := ship_index(&c, id); testing.expect(t, at >= 0 && c.ships[at].active && c.ships[at].captain != 0); ci := ship_continuity_index(&c, id); testing.expect_value(t, c.transformations.continuity[ci].entry, Ship_Entry_Kind.Construction)
}

@(test)
daughter_requires_parent_surplus_and_inherits_relationships :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		813,
	); s := economy_test_settlement(1, "Measure", 3000, 75, c.ships[1].id); s.founding_community = c.communities[0].id; s.fleet_relationship = 2; c.settlements[0] = s; c.settlement_count = 1; _ = initialize_settlement_economy(&c.settlement_economies, &c, &c.settlements[0]); e := &c.settlement_economies.economies[0]; e.authority = 70; e.stock.food = 31; e.stock.goods = 20; e.stock.services = 10
	testing.expect_value(
		t,
		found_core_daughter_settlement(
			&c,
			1,
			"Measure Reach",
			"Shelf",
			"daughter commons",
			500,
			{food = 5, goods = 5, services = 2},
			true,
			true,
			90,
		),
		Settlement_ID(0),
	)
	e.stock.food = 100; e.stock.goods = 50; daughter := found_core_daughter_settlement(&c, 1, "Measure Reach", "Shelf", "daughter commons", 500, {food = 5, goods = 5, services = 2}, true, true, 90); testing.expect(t, daughter != 0); testing.expect_value(t, c.settlements[1].founding_community, c.settlements[0].founding_community); testing.expect_value(t, c.settlements[1].fleet_relationship, c.settlements[0].fleet_relationship); testing.expect_value(t, c.settlement_economies.political_links[0].kind, Regional_Political_Relationship.Sponsor)
}

@(test)
campaign_trade_view_names_parties_and_cites_delivery_record :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		814,
	); a := economy_test_settlement(1, "Orchard", 2000, 75, c.ships[1].id); b := economy_test_settlement(2, "Kiln", 1800, 70, c.ships[2].id); c.settlements[0] = a; c.settlements[1] = b; c.settlement_count = 2; _ = initialize_settlement_economy(&c.settlement_economies, &c, &c.settlements[0]); _ = initialize_settlement_economy(&c.settlement_economies, &c, &c.settlements[1]); record_event(&c, .Settlement_Relationship_Changed, "Orchard and Kiln ratified the Ilex compact.", settlement_id = 1); origin := c.event_sequence; c.settlement_economies.economies[0].stock.food = 100; flow := add_trade_flow(&c.settlement_economies, "winter allotment", 1, 2, .Food, 10, 4, "Ilex Gate", "wardens", "compact", .Stable, 1, 0, origin); testing.expect(t, settle_campaign_trade_flow(&c, flow)); views: [dynamic]Trade_Dependency_View; defer delete(views); _ = trade_dependency_views(&c, 2, &views); testing.expect_value(t, views[0].supplier, "Orchard"); testing.expect_value(t, views[0].consumer, "Kiln"); testing.expect(t, views[0].last_event > views[0].origin_event); event := c.events[event_index_by_sequence(&c, views[0].last_event)]; testing.expect(t, event_cites(event, origin))
}
