package game_tests

import "core:testing"

proposal_test_campaign :: proc() -> Campaign {
	c: Campaign
	campaign_init(&c, 707); _ = install_test_candidate_home(&c); c.colony_package_ready = true
	return c
}

@(test)
settlement_assessment_is_pure_and_deterministic :: proc(t: ^testing.T) {
	c := proposal_test_campaign(
		
	); defer campaign_destroy(&c); testing.expect(t, begin_settlement_proposal(&c, "Harbor", "Pale Harbor"))
	c.settlement_proposal.requested_ships[11] =
		true; c.settlement_proposal.requested_communities[1] = true
	sequence, state, event_count := c.rng_sequence, c.rng_state, c.event_count
	a := proposal_assess(
		&c,
		c.settlement_proposal,
	); b := proposal_assess(&c, c.settlement_proposal)
	testing.expect_value(
		t,
		a.proposal.assessments[11],
		b.proposal.assessments[11],
	); testing.expect_value(t, c.rng_sequence, sequence); testing.expect_value(t, c.rng_state, state); testing.expect_value(t, c.event_count, event_count)
}

@(test)
voluntary_proposal_records_ship_choice_and_connected_obligations :: proc(t: ^testing.T) {
	c := proposal_test_campaign(
		
	); defer campaign_destroy(&c); for &community in c.communities[:c.community_count] {community.settlement_desire = 10; community.grievance = 3; community.trust = 45}
	testing.expect(
		t,
		begin_settlement_proposal(&c, "Free Harbor", "Pale Harbor"),
	); p := &c.settlement_proposal; founders := [4]int{2, 4, 8, 11}; for i in founders do p.requested_ships[i] = true; p.requested_communities[3] = true
	preview := proposal_assess(
		&c,
		p^,
	); testing.expect_value(t, preview.conduct, Settlement_Conduct.Voluntary); testing.expect(t, preview.participating_ships >= 3); testing.expect_value(t, preview.participating_communities, i32(1)); testing.expect(t, preview.projected_colony_viability >= 45); testing.expect(t, preview.valid); testing.expect(t, open_settlement_deliberation(&c)); testing.expect(t, finalize_settlement_proposal(&c))
	testing.expect_value(
		t,
		c.settlement_count,
		1,
	); testing.expect_value(t, c.settlements[0].founding_conduct, Settlement_Conduct.Voluntary); testing.expect(t, continuing_has(c.settlements[0].continuing_obligations, .Rescue)); testing.expect(t, !c.ships[11].active); testing.expect(t, c.promise_count >= 2)
	testing.expect_value(
		t,
		c.settlements[0].celestial,
		c.settlement_proposal.celestial,
	); testing.expect(t, celestial_reference_valid(&c, c.settlements[0].celestial))
}

@(test)
engineered_and_coercive_departures_are_inferred_from_conduct :: proc(t: ^testing.T) {
	engineered := proposal_test_campaign(
		
	); defer campaign_destroy(&engineered); engineered.communities[0].grievance = 5; engineered.communities[0].settlement_desire = 8
	testing.expect(
		t,
		begin_settlement_proposal(&engineered, "Assigned Harbor", "Candidate"),
	); ep := &engineered.settlement_proposal; ep.requested_ships[0] = true; ep.requested_communities[0] = true; ep.transfer_institutions[0] = true; ep.transfer_archives[0] = true
	e := proposal_assess(
		&engineered,
		ep^,
	); testing.expect_value(t, e.conduct, Settlement_Conduct.Engineered_Departure)
	coerced := proposal_test_campaign(
		
	); defer campaign_destroy(&coerced); testing.expect(t, begin_settlement_proposal(&coerced, "Council Harbor", "Candidate")); cp := &coerced.settlement_proposal; cp.procedure = .Council_Assignment; cp.requested_ships[0] = true; cp.requested_communities[0] = true; cp.obligations = continuing_set(cp.obligations, .Civilian_Mobility, false)
	forced := proposal_assess(
		&coerced,
		cp^,
	); testing.expect_value(t, forced.conduct, Settlement_Conduct.Coercive_Assignment); testing.expect(t, !forced.valid); testing.expect(t, authorize_settlement_founding_exception(&coerced, forced.proposal.founding_requirements.unmet_summary)); forced = proposal_assess(&coerced, coerced.settlement_proposal); testing.expect(t, forced.valid)
}

@(test)
three_ship_engineered_waiver_is_viable_but_carries_grievance :: proc(t: ^testing.T) {
	c := proposal_test_campaign(); defer campaign_destroy(&c)
	c.material_economy.fleet.stock.equipment = 0
	testing.expect(
		t,
		begin_settlement_proposal(&c, "Hard Start", "Candidate"),
	); p := &c.settlement_proposal; p.procedure = .Council_Assignment; p.requested_communities[0] = true
	roles := [3]Role{.Habitat, .Foundry, .Hospital}
	for role in roles {for ship, i in c.ships[:c.ship_count] do if ship.active && ship.role == role {p.requested_ships[i] = true; break}}
	preview := proposal_assess(
		&c,
		p^,
	); testing.expect(t, !preview.valid); testing.expect(t, u16(preview.proposal.founding_requirements.unmet) != 0)
	testing.expect(
		t,
		authorize_settlement_founding_exception(
			&c,
			preview.proposal.founding_requirements.unmet_summary,
		),
	); testing.expect(t, open_settlement_deliberation(&c)); testing.expect(t, finalize_settlement_proposal(&c))
	settlement :=
		c.settlements[0]; testing.expect(t, settlement.viability >= 50); testing.expect(t, settlement.initial_grievance >= 3); testing.expect(t, settlement.waived_founding_requirements != 0)
}

@(test)
withheld_evidence_reduces_consent_confidence_and_withdrawal_is_recoverable :: proc(t: ^testing.T) {
	c := proposal_test_campaign(
		
	); defer campaign_destroy(&c); testing.expect(t, begin_settlement_proposal(&c, "Harbor", "Candidate")); c.settlement_proposal.requested_ships[11] = true; c.settlement_proposal.requested_communities[1] = true
	open := proposal_assess(
		&c,
		c.settlement_proposal,
	); c.settlement_proposal.disclose_evidence = false; closed := proposal_assess(&c, c.settlement_proposal)
	testing.expect(
		t,
		closed.proposal.assessments[11].consent.confidence <
		open.proposal.assessments[11].consent.confidence,
	); active := active_ship_count(&c); population := total_population(&c); testing.expect(t, withdraw_settlement_proposal(&c)); testing.expect_value(t, active_ship_count(&c), active); testing.expect_value(t, total_population(&c), population); testing.expect_value(t, c.settlement_count, 0)
}

@(test)
proposal_round_trip_preserves_consents_and_configuration :: proc(t: ^testing.T) {
	c := proposal_test_campaign(
		
	); defer campaign_destroy(&c); testing.expect(t, begin_settlement_proposal(&c, "Harbor", "Candidate")); c.settlement_proposal.requested_ships[11] = true; c.settlement_proposal.requested_communities[1] = true; testing.expect(t, open_settlement_deliberation(&c))
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); result := campaign_deserialize(data[:], &restored)
	testing.expect(
		t,
		result.ok,
	); testing.expect_value(t, restored.settlement_proposal.phase, Settlement_Proposal_Phase.Deliberation); testing.expect_value(t, restored.settlement_proposal.assessments[11].consent, c.settlement_proposal.assessments[11].consent)
}
