package game_tests

import "core:testing"

@(test)
dynamic_politics_is_deterministic_and_constituencies_overlap :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 8201); b: Campaign
	campaign_init(&b, 8201); initialize_dynamic_politics(&a); initialize_dynamic_politics(&b)
	testing.expect_value(
		t,
		a.politics.constituency_count,
		b.politics.constituency_count,
	); testing.expect(t, a.politics.constituency_count > 0)
	testing.expect(
		t,
		.Community in a.politics.constituencies[0].affiliations,
	); testing.expect(t, .Ship_Crew in a.politics.constituencies[0].affiliations)
	ship :=
		a.ships[0].id; one := form_fleet_authority_movement(&a, ship, a.event_sequence); two := form_fleet_authority_movement(&b, ship, b.event_sequence); testing.expect_value(t, one, two); advance_dynamic_politics(&a); advance_dynamic_politics(&b); testing.expect_value(t, a.politics.movements[0].pressure, b.politics.movements[0].pressure)
}

@(test)
legacy_dynamic_politics_is_not_serialized :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		8202,
	); movement_id := form_fleet_authority_movement(&c, c.ships[0].id, c.event_sequence); mi := political_movement_index(&c, movement_id); measure := c.politics.movements[mi].measure; before := fleet_materials(&c)
	id := offer_political_commitment(
		&c,
		measure,
		.Reserve_Ship,
		c.ships[0].id,
		1,
		c.season + 1,
	); testing.expect(t, id != 0); testing.expect_value(t, fleet_materials(&c), before - 1); testing.expect(t, c.ships[0].committed)
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); result := campaign_deserialize(data[:], &restored); testing.expect(t, result.ok); testing.expect_value(t, restored.politics.commitment_count, 0); testing.expect_value(t, restored.politics.movement_count, 0)
}

@(test)
political_routing_keeps_routine_measures_local_and_escalates_precedent :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 8203); initialize_dynamic_politics(&c); local := Political_Measure {
		kind               = .Institution_Custody,
		target_institution = 1,
	}; testing.expect_value(t, political_route_measure(&c, &local), Political_Route_Result.Local)
	escalated := Political_Measure {
		kind               = .Standing_Doctrine,
		requires_precedent = true,
	}; testing.expect_value(
		t,
		political_route_measure(&c, &escalated),
		Political_Route_Result.Escalated,
	); testing.expect(t, escalated.player_attention)
}

@(test)
resolved_authority_issue_reuses_identity_only_after_new_cause :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		8204,
	); ship := c.ships[0].id; first := form_fleet_authority_movement(&c, ship, 10); testing.expect(t, first != 0); mi := political_movement_index(&c, first); measure := c.politics.movements[mi].measure; c.politics.movements[mi].active = false; c.politics.measures[political_measure_index(&c, measure)].status = .Rejected; c.politics.measures[political_measure_index(&c, measure)].last_event = 20
	testing.expect_value(
		t,
		form_fleet_authority_movement(&c, ship, 10),
		u32(0),
	); testing.expect_value(t, form_fleet_authority_movement(&c, ship, 21), first); testing.expect_value(t, c.politics.movement_count, 1); testing.expect_value(t, c.politics.measure_count, 1)
}

@(test)
schism_transfers_population_and_reconciliation_restores_it :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		8205,
	); ship := c.ships[0].id; community := c.ships[0].community; ci := community_index(&c, community); before := c.communities[ci].population; movement_id := form_fleet_authority_movement(&c, ship, 1); mi := political_movement_index(&c, movement_id); political_schism(&c, &c.politics.movements[mi]); testing.expect(t, !c.ships[0].active); testing.expect(t, c.communities[ci].population < before); testing.expect_value(t, c.politics.rival_count, 1); testing.expect(t, reconcile_rival_authority(&c, c.politics.rivals[0].id)); testing.expect(t, c.ships[0].active); testing.expect_value(t, c.communities[ci].population, before)
}

@(test)
commitment_kinds_validate_apply_and_release_once :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		8206,
	); ship := c.ships[0].id; movement_id := form_fleet_authority_movement(&c, ship, 1); mi := political_movement_index(&c, movement_id); measure := c.politics.movements[mi].measure
	testing.expect_value(
		t,
		offer_political_commitment(&c, measure, .Allocate_Stores, 0, 0, c.season + 1),
		u32(0),
	); id := offer_political_commitment(&c, measure, .Reserve_Ship, ship, 0, c.season + 1); testing.expect(t, id != 0); testing.expect(t, c.ships[0].committed); testing.expect(t, resolve_political_commitment(&c, id, .Released)); testing.expect(t, !c.ships[0].committed); testing.expect(t, !resolve_political_commitment(&c, id, .Released))
}

@(test)
autonomous_resolution_can_only_be_acknowledged_once :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		8207,
	); initialize_dynamic_politics(&c); id := form_issue_movement(&c, .Institution_Custody, 0, 1, 0, 1); mi := political_movement_index(&c, id); measure_id := c.politics.movements[mi].measure; m := &c.politics.measures[political_measure_index(&c, measure_id)]; m.status = .Enacted; m.player_attention = false; testing.expect(t, acknowledge_political_resolution(&c, measure_id)); testing.expect(t, !acknowledge_political_resolution(&c, measure_id))
}
