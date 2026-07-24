package game_tests

import "core:testing"

aftermath_test_begin_operation :: proc(c: ^Campaign, layer: Operation_Layer) {
	if c.compact.call_count == 0 do c.compact.call_count = 1
	call := &c.compact.calls[0]
	call.id = 1
	call.status = .Accepted
	call.sponsor = c.institutions[0].id
	call.beneficiary = c.communities[0].id
	call.source_event = 1
	call.opened_season = c.season
	call.deadline = c.season + 2
	call.title = "Test operation"
	call.stakes = "Exercise the validated operation return path."
	call.autonomous_trajectory = "The source institution acts without Compact support."
	call.approach_count = MAX_COMPACT_APPROACHES
	call.selected_approach = 0
	call.offer_count = 2
	call.source = {
		kind = .Institution,
		id = u64(c.institutions[0].id),
		causal_event = 1,
	}
	for offer_index in 0..<call.offer_count {
		call.offers[offer_index] = {
			contributor = c.institutions[0].id,
			ship = c.ships[offer_index].id,
			condition = .Protect_Ship,
			available = true,
			selected = true,
			source_event = 1,
		}
	}
	c.compact.next_call_id = 2
	undertaking_id := Compact_Undertaking_ID(c.compact.next_undertaking_id)
	c.compact.next_undertaking_id += 1
	route :=
		layer == .Passage ? Compact_Operation_Route.Passage :
		layer == .Close_Engagement ? Compact_Operation_Route.Close_Engagement :
		Compact_Operation_Route.Far_Engagement
	operation := layer == .Passage ? Operation_Kind.Passage : .Combat
	c.compact.active = {
		id = undertaking_id,
		call = call.id,
		status = .Operating,
		operation = operation,
		route = route,
		seconded_count = 2,
		charter = {
			version = 1,
			undertaking = undertaking_id,
			call = call.id,
			intent_event = 1,
			compiled_event = 1,
			valid = true,
		},
	}
	c.compact.active.seconded_ships[0] = c.ships[0].id
	c.compact.active.seconded_ships[1] = c.ships[1].id
	call.undertaking = undertaking_id
}

aftermath_test_facts :: proc(
	c: ^Campaign,
	id: u64,
	abandonment := false,
) -> Operation_Outcome_Facts {
	ship_a, ship_b := c.ships[0].id, c.ships[1].id
	community := c.communities[0].id
	kind := Social_Consequence_Kind.Witnessed_Rescue
	if abandonment do kind = .Abandonment
	ships := make([]Operation_Ship_Outcome, 2, context.temp_allocator)
	ships[0] = {
		ship             = ship_a,
		damage           = 1,
		crew_change      = -2,
		experience       = 2,
		recovery_seconds = CAMPAIGN_DAY_SECONDS,
	}
	ships[1] = {
		ship       = ship_b,
		experience = 1,
		withdrew   = true,
	}
	social := make([]Social_Consequence_Input, 1, context.temp_allocator)
	social[0] = {
		kind = kind,
		actor_ship = ship_a,
		subject_ship = ship_b,
		community = community,
		institution = c.institutions[0].id,
		knowledge = {
			participants_know = true,
			authenticated = true,
			witness_community = community,
			witness_institution = c.institutions[0].id,
		},
	}
	events := make([]Operation_Causal_Event, 1, context.temp_allocator)
	events[0] = {
		kind              = .Expedition_Returned,
		ship              = ship_a,
		related_ship      = ship_b,
		community         = community,
		observation_index = 0,
		detail            = abandonment ? "The ships returned without the requested rescue." : "The ships returned with the survivors aboard.",
	}
	return {
		id = Operation_ID(id),
		elapsed_seconds = 2 * CAMPAIGN_DAY_SECONDS,
		objective = .Achieved,
		protected_exposure = 1,
		rescues = abandonment ? 0 : 1,
		withdrawals = 1,
		evidence_recovered = 1,
		resources = {supplies = -2, propellant = -1},
		ships = ships,
		social = social,
		events = events,
	}
}

@(test)
all_operation_layers_translate_equivalent_facts :: proc(t: ^testing.T) {
	a := new_campaign_heap(1416)
	b := new_campaign_heap(1416)
	d := new_campaign_heap(1416)
	defer campaign_destroy_heap(a); defer campaign_destroy_heap(b); defer campaign_destroy_heap(d)
	aftermath_test_begin_operation(a, .Passage)
	aftermath_test_begin_operation(b, .Close_Engagement)
	aftermath_test_begin_operation(d, .Far_Engagement)
	fa, fb, fd :=
		aftermath_test_facts(a, 1), aftermath_test_facts(b, 1), aftermath_test_facts(d, 1)
	aa := passage_operation_aftermath(a, fa)
	ab := close_engagement_operation_aftermath(b, fb)
	ad := far_engagement_operation_aftermath(d, fd)
	testing.expect(t, queue_operation_aftermath(a, aa) && apply_operation_aftermath(a))
	testing.expect(t, queue_operation_aftermath(b, ab) && apply_operation_aftermath(b))
	testing.expect(t, queue_operation_aftermath(d, ad) && apply_operation_aftermath(d))
	testing.expect_value(t, a.ships[0].damage, b.ships[0].damage)
	testing.expect_value(t, b.ships[0].damage, d.ships[0].damage)
	testing.expect_value(t, a.ships[0].crew, d.ships[0].crew)
	testing.expect_value(t, a.ship_relationships[0].strength, d.ship_relationships[0].strength)
	testing.expect_value(t, a.social_consequence_count, d.social_consequence_count)
}

@(test)
aftermath_application_is_idempotent :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1417); defer campaign_destroy(&c)
	aftermath_test_begin_operation(&c, .Passage)
	a := passage_operation_aftermath(&c, aftermath_test_facts(&c, 9))
	testing.expect(t, queue_operation_aftermath(&c, a))
	testing.expect(t, apply_operation_aftermath(&c))
	damage, events, bonds, social, work_id :=
		c.ships[0].damage,
		c.event_count,
		c.ship_relationship_count,
		c.social_consequence_count,
		c.next_scheduled_work_id
	testing.expect(t, !queue_operation_aftermath(&c, a))
	testing.expect(t, !apply_operation_aftermath(&c))
	testing.expect_value(t, c.ships[0].damage, damage)
	testing.expect_value(t, c.event_count, events)
	testing.expect_value(t, c.ship_relationship_count, bonds)
	testing.expect_value(t, c.social_consequence_count, social)
	testing.expect_value(t, c.next_scheduled_work_id, work_id)
}

@(test)
pending_aftermath_survives_save_load :: proc(t: ^testing.T) {
	c := new_campaign_heap(1418); defer campaign_destroy_heap(c)
	aftermath_test_begin_operation(c, .Far_Engagement)
	a := far_engagement_operation_aftermath(c, aftermath_test_facts(c, 10))
	testing.expect(t, queue_operation_aftermath(c, a))
	data := campaign_serialize(c); defer delete(data)
	restored := new(Campaign); defer campaign_destroy_heap(restored)
	result := campaign_deserialize(data[:], restored)
	testing.expect(t, result.ok)
	testing.expect_value(t, restored.pending_aftermath.id, Operation_ID(10))
	testing.expect(t, apply_operation_aftermath(restored))
	testing.expect_value(t, restored.ships[0].damage, c.ships[0].damage + 1)
	testing.expect(t, aftermath_completed(restored, 10))
}

@(test)
knowledge_boundaries_and_reconciliation_are_causal :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1616); defer campaign_destroy(&c)
	aftermath_test_begin_operation(&c, .Close_Engagement)
	hidden := aftermath_test_facts(&c, 20, true)
	hidden.social[0].knowledge = {}
	a := close_engagement_operation_aftermath(&c, hidden)
	testing.expect(t, queue_operation_aftermath(&c, a) && apply_operation_aftermath(&c))
	testing.expect_value(t, c.social_consequence_count, 0)
	public := aftermath_test_facts(&c, 21, true)
	aftermath_test_begin_operation(&c, .Close_Engagement)
	b := close_engagement_operation_aftermath(&c, public)
	testing.expect(t, queue_operation_aftermath(&c, b) && apply_operation_aftermath(&c))
	testing.expect_value(t, c.social_consequence_count, 1)
	before := operational_social_choice_modifiers(&c, c.ships[0].id, c.ships[1].id)
	testing.expect(t, before.rescue_default < 0)
	testing.expect(t, reconcile_social_consequence(&c, 21, c.ships[0].id, c.communities[0].id))
	after := operational_social_choice_modifiers(&c, c.ships[0].id, c.ships[1].id)
	testing.expect(t, after.rescue_default > before.rescue_default)
	testing.expect(t, c.communities[0].grievance >= 0)
}

@(test)
repeated_conduct_establishes_practice_without_dominant_policy :: proc(t: ^testing.T) {
	rescue := new_campaign_heap(1617)
	conceal := new_campaign_heap(1617)
	defer campaign_destroy_heap(rescue); defer campaign_destroy_heap(conceal)
	for i in 0 ..< 3 {
		aftermath_test_begin_operation(rescue, .Passage)
		facts := aftermath_test_facts(rescue, u64(30 + i))
		a := passage_operation_aftermath(rescue, facts)
		testing.expect(
			t,
			queue_operation_aftermath(rescue, a) && apply_operation_aftermath(rescue),
		)
	}
	testing.expect(t, rescue.operational_practices[int(Operational_Practice.Mutual_Rescue)] >= 3)
	facts := aftermath_test_facts(conceal, 40)
	aftermath_test_begin_operation(conceal, .Passage)
	facts.social[0].kind = .Concealed_Evidence
	facts.ships[0].damage = 0
	facts.ships[0].recovery_seconds = 0
	a := passage_operation_aftermath(conceal, facts)
	testing.expect(
		t,
		queue_operation_aftermath(conceal, a) && apply_operation_aftermath(conceal),
	)
	testing.expect(t, conceal.communities[0].trust <= rescue.communities[0].trust)
	// Rescue creates repair burdens and exposure; it is not a free positive meter.
	testing.expect(t, rescue.ships[0].damage > conceal.ships[0].damage)
	testing.expect(t, rescue.next_scheduled_work_id > conceal.next_scheduled_work_id)
	report := analyze_operational_policy_dominance()
	testing.expect(t, !report.universally_dominant)
}

@(test)
all_social_inputs_are_persistent_and_aftermath_events_have_provenance :: proc(t: ^testing.T) {
	kinds := [9]Social_Consequence_Kind {
		.Witnessed_Rescue,
		.Refused_Rescue,
		.Abandonment,
		.Covering_Withdrawal,
		.Unauthorized_Exposure,
		.Uncommunicated_Deviation,
		.Accepted_Responsibility,
		.Concealed_Evidence,
		.Shared_Survival,
	}
	for kind, i in kinds {
		c: Campaign
		campaign_init(&c, 1620 + u64(i))
		aftermath_test_begin_operation(&c, .Passage)
		facts := aftermath_test_facts(&c, 100 + u64(i))
		facts.social[0].kind = kind
		facts.social[0].accepted_responsibility = kind == .Accepted_Responsibility
		a := passage_operation_aftermath(&c, facts)
		testing.expect(t, queue_operation_aftermath(&c, a) && apply_operation_aftermath(&c))
		testing.expect_value(t, c.social_consequence_count, 1)
		found := false
		for event in c.events[:c.event_count] do if event.operation_id == 100 + u64(i) {
			found = true
			testing.expect(t, event.observation_index >= -1)
		}
		testing.expect(t, found)
		campaign_destroy(&c)
	}
}

@(test)
equivalent_adapters_preserve_rescue_withdrawal_exposure_and_objective :: proc(t: ^testing.T) {
	a := new_campaign_heap(1621)
	b := new_campaign_heap(1621)
	d := new_campaign_heap(1621)
	defer campaign_destroy_heap(a); defer campaign_destroy_heap(b); defer campaign_destroy_heap(d)
	fa, fb, fd :=
		aftermath_test_facts(a, 220), aftermath_test_facts(b, 220), aftermath_test_facts(d, 220)
	fa.objective, fb.objective, fd.objective = .Partial, .Partial, .Partial
	fa.rescues, fb.rescues, fd.rescues = 2, 2, 2
	fa.withdrawals, fb.withdrawals, fd.withdrawals = 3, 3, 3
	fa.protected_exposure, fb.protected_exposure, fd.protected_exposure = 4, 4, 4
	aa := passage_operation_aftermath(a, fa)
	ab := close_engagement_operation_aftermath(b, fb)
	ad := far_engagement_operation_aftermath(d, fd)
	testing.expect_value(t, aa.objective, ab.objective)
	testing.expect_value(t, ab.objective, ad.objective)
	testing.expect_value(t, aa.rescues, ad.rescues)
	testing.expect_value(t, aa.withdrawals, ad.withdrawals)
	testing.expect_value(t, aa.protected_exposure, ad.protected_exposure)
}
