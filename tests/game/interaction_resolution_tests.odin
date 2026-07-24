package game_tests

import "core:testing"

@(test)
interaction_requires_and_cites_persistent_history :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		71,
	); c.ships[3].damage = 3; record_event(&c, .Ship_Damaged, "Resolute still carries the breach opened at Ilex Gate.", c.ships[3].id, 3); origin := c.event_sequence
	testing.expect(
		t,
		surface_interaction(&c),
	); testing.expect_value(t, c.current_situation.kind, Situation_Kind.Repair_Debt); testing.expect_value(t, c.current_situation.origin_event, origin); testing.expect(t, c.current_situation.proposal_event > origin)
}

@(test)
interaction_resolution_is_deterministic_and_feeds_history_forward :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 88); b: Campaign
	campaign_init(&b, 88)
	a.ships[3].damage = 3; record_event(&a, .Ship_Damaged, "Resolute carries a recorded breach.", a.ships[3].id, 3); testing.expect(t, surface_interaction(&a)); testing.expect(t, advance_interaction(&a)); testing.expect(t, advance_interaction(&a)); testing.expect(t, resolve_interaction(&a, 0))
	b.ships[3].damage = 3; record_event(&b, .Ship_Damaged, "Resolute carries a recorded breach.", b.ships[3].id, 3); testing.expect(t, surface_interaction(&b)); testing.expect(t, advance_interaction(&b)); testing.expect(t, advance_interaction(&b)); testing.expect(t, resolve_interaction(&b, 0))
	testing.expect_value(
		t,
		a.current_situation,
		b.current_situation,
	); testing.expect_value(t, a.rng_state, b.rng_state); testing.expect(t, a.capacities.raw_materials.reserved == 4); testing.expect(t, a.ships[3].damage == 1); testing.expect(t, a.events[a.event_count - 1].kind == .Situation_Complied); testing.expect(t, a.events[a.event_count - 1].cause_sequence == a.current_situation.decision_event)
	testing.expect(t, !surface_interaction(&a))
}

@(test)
major_situations_leave_a_clear_season :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		89,
	); c.ships[3].damage = 3; record_event(&c, .Ship_Damaged, "Resolute carries a recorded breach.", c.ships[3].id, 3)
	record_event(
		&c,
		.Expedition_Returned,
		"The public and authoritative reports differ.",
		c.ships[1].id,
		authoritative_detail = "The sealed report differs.",
		account_status = .Contradicted,
	)
	testing.expect(
		t,
		surface_interaction(&c),
	); _ = advance_interaction(&c); _ = advance_interaction(&c); testing.expect(t, resolve_interaction(&c, 0))
	c.season = 1; testing.expect(t, !surface_interaction(&c))
	c.season = 2; testing.expect(t, surface_interaction(&c))
}

@(test)
situation_builders_are_pure_and_keep_two_reasons_or_fewer :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 301); _ = install_test_candidate_home(&c); c.colony_package_ready = true
	rng, event_count := c.rng_sequence, c.event_count
	a, ok := make_settlement_situation(&c); b, ok_b := make_settlement_situation(&c)
	testing.expect(
		t,
		ok && ok_b,
	); testing.expect_value(t, a, b); testing.expect_value(t, c.rng_sequence, rng); testing.expect_value(t, c.event_count, event_count)
	for position in a.positions[:a.position_count] do testing.expect(t, position.reason_count <= 2)
}

@(test)
settlement_situation_uses_three_beats_and_departure_is_irreversible :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		302,
	); _ = install_test_candidate_home(&c); c.colony_package_ready = true; testing.expect(t, surface_interaction(&c)); testing.expect_value(t, c.current_situation.kind, Situation_Kind.Settlement); testing.expect_value(t, c.current_situation.phase, Situation_Phase.Proposal)
	initiator :=
		c.current_situation.initiator; testing.expect(t, advance_interaction(&c)); testing.expect_value(t, c.current_situation.phase, Situation_Phase.Responses); testing.expect(t, advance_interaction(&c)); testing.expect_value(t, c.current_situation.phase, Situation_Phase.Decision); testing.expect(t, resolve_interaction(&c, 0))
	at := ship_index(
		&c,
		initiator,
	); testing.expect(t, at >= 0 && !c.ships[at].active); testing.expect_value(t, c.ships[at].departure, Ship_Departure.Settlement); testing.expect_value(t, c.settlement_count, 1); testing.expect(t, c.capacities.compute.reserved > 0)
}

@(test)
rescue_situation_creates_and_releases_named_commitment :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		303,
	); hook := create_broken_procession_hook(&c, 900, c.ships[4].id); testing.expect(t, hook >= 0); testing.expect(t, surface_interaction(&c)); testing.expect_value(t, c.current_situation.kind, Situation_Kind.Rescue); _ = advance_interaction(&c); _ = advance_interaction(&c); testing.expect(t, resolve_interaction(&c, 0)); testing.expect(t, c.capacities.manpower.reserved == 4); testing.expect_value(t, c.history_hooks[hook].stage, History_Hook_Stage.Consequence)
	c.season += 2; release_situation_capacity(&c); testing.expect_value(t, c.capacities.manpower.reserved, i32(0))
}

@(test)
evidence_situation_changes_which_record_later_ships_can_use :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		304,
	); record_event(&c, .Expedition_Returned, "The expedition reported no viable home.", c.ships[1].id, authoritative_detail = "The world was viable with adaptation.", account_status = .Contradicted); contested := c.event_sequence
	testing.expect(
		t,
		surface_interaction(&c),
	); testing.expect_value(t, c.current_situation.kind, Situation_Kind.Contested_Evidence); _ = advance_interaction(&c); _ = advance_interaction(&c); testing.expect(t, resolve_interaction(&c, 0)); at := event_index_by_sequence(&c, contested); testing.expect(t, at >= 0 && c.events[at].account_exposed)
}

@(test)
restricted_evidence_informs_one_ship_without_settling_the_fleet_record :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 3041); defer campaign_destroy(&c)
	record_event(
		&c,
		.Expedition_Returned,
		"The expedition reported no viable home.",
		c.ships[1].id,
		authoritative_detail = "The world was viable with adaptation.",
		account_status = .Contradicted,
	)
	contested := c.event_sequence
	testing.expect(
		t,
		surface_interaction(&c),
	); _ = advance_interaction(&c); _ = advance_interaction(&c)
	testing.expect(t, resolve_interaction(&c, 2))
	at := event_index_by_sequence(
		&c,
		contested,
	); testing.expect(t, at >= 0 && !c.events[at].account_exposed)
	si := ship_index(
		&c,
		c.current_situation.initiator,
	); testing.expect(t, si >= 0 && c.ships[si].pending_claim != "")
	state := strategic_state_view(
		&c,
	); testing.expect_value(t, state.information, Information_State.Disputed)
}

@(test)
settlement_review_persists_and_improves_later_founding_viability :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		3042,
	); defer campaign_destroy(&c); candidate := install_test_candidate_home(&c); c.colony_package_ready = true
	s, ok := make_settlement_situation(
		&c,
	); testing.expect(t, ok); c.current_situation = s; c.current_situation.phase = .Decision
	testing.expect(
		t,
		resolve_interaction(&c, 2),
	); at := candidate_home_index(&c, candidate); testing.expect(t, at >= 0 && c.candidate_homes[at].independent_review)
	later, later_ok := make_settlement_situation(
		&c,
	); testing.expect(t, later_ok); resolve_settlement_interaction(&c, &later, .Found_Settlement)
	testing.expect_value(t, c.settlements[0].viability, i32(72))
}

@(test)
active_collision_is_preserved_for_narrative_regeneration :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		305,
	); defer campaign_destroy(&c); _ = install_test_candidate_home(&c); c.colony_package_ready = true; testing.expect(t, surface_interaction(&c)); data := campaign_serialize(&c); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); result := campaign_deserialize(data[:], &restored); testing.expect(t, result.ok); testing.expect_value(t, restored.current_situation, c.current_situation); testing.expect_value(t, narrative_view_for_collision(&restored, collision_id_for_situation(&restored.current_situation)), narrative_view_for_collision(&c, collision_id_for_situation(&c.current_situation))); testing.expect_value(t, restored.capacities, c.capacities)
}

@(test)
settlement_situation_keeps_its_original_candidate_world :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 306); defer campaign_destroy(&c)
	first := install_test_candidate_home(
		&c,
	); testing.expect(t, first.valid); c.colony_package_ready = true
	s, situation_ok := make_settlement_situation(
		&c,
	); testing.expect(t, situation_ok); testing.expect_value(t, s.celestial, first)
	for seed := u64(307); seed < 400 && c.candidate_home_count < 2; seed += 1 do _, _ = discover_candidate_home(&c, seed)
	resolve_settlement_interaction(&c, &s, .Found_Settlement)
	testing.expect_value(t, c.settlement_count, 1)
	testing.expect_value(t, c.settlements[0].celestial, first)
}

@(test)
capacity_commitment_requires_a_release_slot_and_cites_its_own_origin :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 307)
	for &commitment in c.capacity_commitments do commitment.active = true
	before := c.capacities.raw_materials.reserved
	s := Fleet_Situation {
		id             = 77,
		kind           = .Repair_Debt,
		initiator      = c.ships[0].id,
		proposal_event = c.event_sequence,
	}
	testing.expect(
		t,
		!commit_situation_capacity(&c, &s, {raw_materials = 1, consequence = "No slot."}),
	)
	testing.expect_value(t, c.capacities.raw_materials.reserved, before)
	for &commitment in c.capacity_commitments do commitment = {}
	record_event(
		&c,
		.Situation_Proposed,
		"A bounded commitment.",
		c.ships[0].id,
	); s.proposal_event = c.event_sequence
	testing.expect(
		t,
		commit_situation_capacity(&c, &s, {raw_materials = 1, consequence = "One season."}),
	)
	origin := c.capacity_commitments[0].origin_event
	c.season += 1; release_situation_capacity(&c)
	e := c.events[c.event_count - 1]
	testing.expect_value(t, e.kind, Event_Kind.Capacity_Released)
	testing.expect(t, event_cites(e, origin))
}

@(test)
orbital_refuge_persists_as_housing_reserve_and_mobility_obligation :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		308,
	); defer campaign_destroy(&c); _ = install_test_candidate_home(&c); c.colony_package_ready = true
	s, ok := make_settlement_situation(
		&c,
	); testing.expect(t, ok); resolve_settlement_interaction(&c, &s, .Amend_Settlement)
	settlement := &c.settlements[0]
	testing.expect(t, settlement.orbital_refuge && settlement.orbital_refuge_capacity > 0)
	testing.expect(t, continuing_has(settlement.continuing_obligations, .Civilian_Mobility))
	testing.expect(t, initialize_settlement_economy(&c.settlement_economies, &c, settlement))
	e := c.settlement_economies.economies[0]
	testing.expect(t, e.housing >= e.population + i64(settlement.orbital_refuge_capacity))
	testing.expect(t, e.emergency_reserve.goods >= 3)
}
