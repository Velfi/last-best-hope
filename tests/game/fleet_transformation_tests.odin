package game_tests

import "core:testing"

@(test)
retirement_and_inheritance_keep_a_traceable_roster :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 701); old := c.ships[0].id; old_name := c.ships[0].name
	testing.expect(
		t,
		retire_ship(&c, old),
	); heir := add_historical_ship(&c, "Second Measure", .Survey, .Inheritance, old)
	testing.expect(
		t,
		heir != 0 && heir != old,
	); at := ship_index(&c, heir); testing.expect(t, at >= 0 && c.ships[at].active); testing.expect(t, c.ships[at].construction_lineage != 0)
	found_retirement, found_entry :=
		false,
		false; for r in c.transformations.records[:c.transformations.record_count] {if r.kind == .Retirement && r.ship == old do found_retirement = true; if r.kind == .New_Ship && r.ship == heir && r.predecessor == old do found_entry = true}; testing.expect(t, found_retirement && found_entry); testing.expect(t, old_name != "")
}

@(test)
refit_changes_capability_social_role_and_autonomy_pressure :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		702,
	); id := c.ships[2].id; testing.expect(t, refit_ship_role(&c, id, .Hospital, "mobile convalescent commons")); i := ship_index(&c, id); ci := ship_continuity_index(&c, id)
	testing.expect_value(
		t,
		c.ships[i].role,
		Role.Hospital,
	); testing.expect_value(t, c.transformations.continuity[ci].social_role, "mobile convalescent commons"); testing.expect(t, c.transformations.continuity[ci].autonomy_pressure > 0)
}

@(test)
captain_succession_and_severe_states_remain_recoverable :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		703,
	); id := c.ships[0].id; record_ship_autonomy(&c, "The ship selected its own survey line.", id, 1); prior := c.ships[0].captain
	testing.expect(
		t,
		succeed_captain(&c, id, "Rin Vale", "Rin Vale reopened the prior survey ruling."),
	); next := c.ships[0].captain; fi := historical_figure_index(&c, next); testing.expect(t, next != prior && c.historical_figures[fi].predecessor == prior)
	testing.expect(
		t,
		mothball_ship(&c, id),
	); testing.expect(t, restore_mothballed_ship(&c, id)); testing.expect(t, divide_ship_command(&c, id))
}

@(test)
migration_requires_consent_and_capacity_and_institutions_can_change_form :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 704); community := c.communities[0].id; ship := c.ships[1].id
	testing.expect(
		t,
		!migrate_community(&c, community, 100, to_ship = ship),
	); testing.expect(t, migrate_community(&c, community, 100, to_ship = ship, consent = true)); testing.expect(t, isolate_community(&c, community))
	testing.expect(
		t,
		place_institution(&c, 2, .Ship_Bound, ship = ship),
	); testing.expect_value(t, c.transformations.placements[1].form, Institution_Form.Ship_Bound)
}

@(test)
thirty_seasons_change_the_founding_roster_through_recorded_succession :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 705); founder := c.ships[0].id
	c.season = 15; advance_fleet_transformations(&c); c.season = 30; advance_fleet_transformations(&c)
	testing.expect(
		t,
		ship_index(&c, founder) < 0,
	); testing.expect(t, c.transformations.record_count >= 4); testing.expect_value(t, c.ship_count, INITIAL_SHIPS)
}
