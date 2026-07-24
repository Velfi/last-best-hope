package game_tests

import "core:testing"

@(test)
obligations_reserve_named_capacity_and_force_visible_tradeoffs :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		601,
	); c.season = 13; cohesion_before := c.strategic.cohesion; advance_obligations(&c)
	testing.expect(t, c.obligations.initialized); testing.expect(t, c.obligations.count >= 3)
	testing.expect(
		t,
		c.obligations.reserved_compute > 0 &&
		c.obligations.reserved_manpower > 0 &&
		c.obligations.reserved_raw_materials > 0,
	)
	testing.expect(t, c.obligations.underfunded_count > 0)
	// The surfaced shortfall precedes its systemic penalty by one season.
	testing.expect_value(t, c.strategic.cohesion, cohesion_before)
	advance_obligations(&c)
	testing.expect(t, c.strategic.cohesion < cohesion_before)
	// Both route suspension and foundry-backed substitution leave a recoverable campaign.
	route := -1; for o, i in c.obligations.items[:c.obligations.count] do if o.kind == .Open_Route do route = i
	testing.expect(
		t,
		route >= 0 && contract_obligation(&c, route, .Suspend_Route),
	); testing.expect(t, active_ship_count(&c) > 0)
}

@(test)
emergency_capacity_has_delayed_attributable_cost :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 602); initialize_obligations(&c); before := c.strategic.cohesion
	testing.expect(t, invoke_emergency_capacity(&c, 0)); due := c.obligations.emergency_due_season
	for c.season < due do advance_season(&c)
	testing.expect(
		t,
		c.obligations.emergency_debt == 0,
	); testing.expect(t, c.strategic.cohesion < before)
	found :=
		false; for e in c.events[:c.event_count] do if e.kind == .Political_Relationship_Changed && e.institution_id == 1 do found = true; testing.expect(t, found)
}

@(test)
obligation_substitution_reflects_fleet_history :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 603); initialize_obligations(&c); o := c.obligations.items[0]
	_, _, materials, attention, detail := obligation_substitution(&c, o)
	testing.expect(
		t,
		materials < o.raw_materials,
	); testing.expect(t, attention > o.attention); testing.expect(t, detail != "")
}
