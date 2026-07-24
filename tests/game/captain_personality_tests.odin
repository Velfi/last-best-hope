package game_tests

import "core:testing"

@(test)
captain_profiles_are_seeded_diverse_and_do_not_consume_campaign_rng :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 8101); b: Campaign
	campaign_init(&b, 8101); rng := a.rng_state
	record_ship_autonomy(
		&a,
		"A recorded autonomous survey action.",
		a.ships[0].id,
		1,
	); record_ship_autonomy(&b, "A recorded autonomous survey action.", b.ships[0].id, 1)
	ai := historical_figure_index(
		&a,
		a.ships[0].captain,
	); bi := historical_figure_index(&b, b.ships[0].captain)
	testing.expect(
		t,
		ai >= 0 && bi >= 0,
	); testing.expect_value(t, a.historical_figures[ai].captain_profile, b.historical_figures[bi].captain_profile); testing.expect_value(t, a.rng_state, rng)
}

@(test)
captain_facets_can_hold_duty_autonomy_preservation_and_risk_together :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		8102,
	); record_ship_autonomy(&c, "A captain entered the record.", c.ships[0].id, 1); fi := historical_figure_index(&c, c.ships[0].captain); p := &c.historical_figures[fi].captain_profile
	p.facets[int(Captain_Facet.Institutional_Duty)] = 4; p.facets[int(Captain_Facet.Personal_Autonomy)] = 4; p.facets[int(Captain_Facet.Life_Preservation)] = 4; p.facets[int(Captain_Facet.Risk_Tolerance)] = 4; captain_refresh_convictions(p)
	testing.expect_value(
		t,
		p.facets[int(Captain_Facet.Institutional_Duty)],
		u8(4),
	); testing.expect_value(t, p.facets[int(Captain_Facet.Personal_Autonomy)], u8(4)); testing.expect(t, captain_dossier(&c, c.ships[0].captain).tension != "")
}

@(test)
captain_orders_are_binding_but_breachable_and_accountable :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		8103,
	); ship := c.ships[0].id; record_ship_autonomy(&c, "A captain entered the record.", ship, 1); captain := c.ships[0].captain; cause := c.event_sequence
	testing.expect(t, captain_issue_obligation(&c, captain, ship, .Rescue, 1, 3, cause) > 0)
	options := [2]Captain_Decision_Option {
		{available = true, complies = true, base_utility = 0, label = "withdraw"},
		{available = true, complies = false, base_utility = 60, label = "recover"},
	}
	result := captain_decide(
		&c,
		{
			captain = captain,
			decision_context = .Rescue,
			stakes = 3,
			source_event = cause,
			options = options[:],
		},
	); testing.expect(t, result.valid && result.overt_departure && result.obligation_status == .Breached); testing.expect(t, captain_apply_decision(&c, {captain = captain, decision_context = .Rescue, stakes = 3, source_event = cause, options = options[:]}, result)); breach := c.event_sequence
	testing.expect(
		t,
		captain_resolve_accountability(&c, captain, .Censure, breach),
	); testing.expect_value(t, c.captain_obligations[0].status, Captain_Obligation_Status.Accounted)
}

@(test)
repeated_evidence_changes_only_the_expressed_facet :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		8104,
	); record_ship_autonomy(&c, "A captain entered the record.", c.ships[0].id, 1); captain := c.ships[0].captain; fi := historical_figure_index(&c, captain); p := &c.historical_figures[fi].captain_profile; p.facets[int(Captain_Facet.Consultation)] = 1; other := p.facets[int(Captain_Facet.Confrontation)]
	for _ in 0 ..< 7 do _ = captain_record_evidence(&c, captain, .Consultation, 1)
	testing.expect_value(
		t,
		p.facets[int(Captain_Facet.Consultation)],
		u8(2),
	); testing.expect_value(t, p.facets[int(Captain_Facet.Confrontation)], other)
}
