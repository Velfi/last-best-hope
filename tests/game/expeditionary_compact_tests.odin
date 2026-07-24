package game_tests

import game "../../packages/game"
import "core:testing"

install_compact_test_need :: proc(c: ^game.Campaign, slot: int, kind: game.Need_Kind) {
	game.record_event(c, .Need_Surfaced, "A deterministic test need surfaced.")
	c.needs[slot] = {
		kind         = kind,
		community    = 1,
		ship         = game.Ship_ID(slot + 1),
		deadline     = c.season + 2,
		cost         = 2,
		active       = true,
		detail       = game.need_detail(kind),
		source_event = c.event_sequence,
		institution  = game.Institution_ID(slot % game.MAX_INSTITUTIONS + 1),
	}
}

@(test)
compact_docket_surfaces_at_most_one_call_per_boundary :: proc(t: ^testing.T) {
	c: game.Campaign
	game.campaign_init(&c, 17001)
	defer game.campaign_destroy(&c)
	install_compact_test_need(&c, 0, .Ship_Repair)
	install_compact_test_need(&c, 1, .Settlement_Defense)
	install_compact_test_need(&c, 2, .Archive_Staffing)
	testing.expect(t, game.compact_surface_one_call(&c))
	testing.expect_value(t, c.compact.call_count, 1)
	testing.expect(t, !game.compact_surface_one_call(&c))
	testing.expect_value(t, c.compact.call_count, 1)
	testing.expect(t, game.validate_expeditionary_compact(&c))
}

@(test)
compact_calls_are_seed_and_state_deterministic :: proc(t: ^testing.T) {
	a, b: game.Campaign
	game.campaign_init(&a, 17002)
	game.campaign_init(&b, 17002)
	defer game.campaign_destroy(&a)
	defer game.campaign_destroy(&b)
	install_compact_test_need(&a, 0, .Ship_Repair)
	install_compact_test_need(&b, 0, .Ship_Repair)
	testing.expect(t, game.compact_surface_one_call(&a))
	testing.expect(t, game.compact_surface_one_call(&b))
	testing.expect_value(t, a.compact.calls[0].family, b.compact.calls[0].family)
	testing.expect_value(t, a.compact.calls[0].source_event, b.compact.calls[0].source_event)
	testing.expect_value(t, a.compact.calls[0].offer_count, b.compact.calls[0].offer_count)
	for i in 0 ..< a.compact.calls[0].offer_count {
		testing.expect_value(
			t,
			a.compact.calls[0].offers[i].ship,
			b.compact.calls[0].offers[i].ship,
		)
		testing.expect_value(
			t,
			a.compact.calls[0].offers[i].condition,
			b.compact.calls[0].offers[i].condition,
		)
	}
}

@(test)
compact_excludes_ordinary_political_questions :: proc(t: ^testing.T) {
	c: game.Campaign
	game.campaign_init(&c, 17003)
	defer game.campaign_destroy(&c)
	install_compact_test_need(&c, 0, .Representation)
	testing.expect(t, !game.compact_surface_one_call(&c))
	testing.expect_value(t, c.compact.call_count, 0)
}

@(test)
compact_deferred_call_resolves_without_blocking_the_campaign :: proc(t: ^testing.T) {
	c: game.Campaign
	game.campaign_init(&c, 17004)
	defer game.campaign_destroy(&c)
	install_compact_test_need(&c, 0, .Ship_Repair)
	testing.expect(t, game.compact_surface_one_call(&c))
	c.needs[0].active = false
	c.needs[0].resolved = true
	game.compact_refresh_calls(&c)
	testing.expect_value(
		t,
		c.compact.calls[0].status,
		game.Compact_Call_Status.Resolved_Autonomously,
	)
}

@(test)
compact_acceptance_compiles_the_only_charter_and_settles_secondment_once :: proc(t: ^testing.T) {
	c: game.Campaign
	game.campaign_init(&c, 17005)
	defer game.campaign_destroy(&c)
	install_compact_test_need(&c, 0, .Ship_Repair)
	testing.expect(t, game.compact_surface_one_call(&c))
	call := &c.compact.calls[0]
	testing.expect(t, call.offer_count > 0)
	testing.expect(t, game.compact_toggle_offer(&c, call.id, 0))
	before := c.material_economy.fleet.stock
	committed_before := c.material_economy.fleet.committed
	ship := call.offers[0].ship
	testing.expect(t, game.compact_accept_call(&c, call.id))
	testing.expect(t, c.material_economy.fleet.committed != committed_before)
	undertaking := &c.compact.active
	testing.expect_value(t, undertaking.status, game.Compact_Undertaking_Status.Planning)
	testing.expect(t, undertaking.charter.valid)
	testing.expect(t, undertaking.charter.hard_authority.valid)
	testing.expect_value(t, undertaking.charter.hard_authority.undertaking_id, u32(undertaking.id))
	testing.expect(t, game.compact_ship_is_seconded(&c, ship))
	testing.expect(t, game.compact_withdraw_undertaking(&c, "Fixed-seed withdrawal."))
	testing.expect_value(t, c.material_economy.fleet.stock, before)
	testing.expect_value(t, c.material_economy.fleet.committed, committed_before)
	testing.expect(t, !game.compact_withdraw_undertaking(&c, "Duplicate withdrawal."))
	testing.expect_value(t, c.material_economy.fleet.stock, before)
	testing.expect_value(t, c.compact.history_count, 1)
	testing.expect_value(t, c.compact.active.status, game.Compact_Undertaking_Status.None)
	testing.expect(t, game.validate_expeditionary_compact(&c))
}

@(test)
compact_call_without_named_need_sponsor_resolves_an_active_reviewer :: proc(t: ^testing.T) {
	c: game.Campaign
	game.campaign_init(&c, 17006)
	defer game.campaign_destroy(&c)
	install_compact_test_need(&c, 0, .Ship_Repair)
	c.needs[0].institution = 0
	testing.expect(t, game.compact_surface_one_call(&c))
	call := &c.compact.calls[0]
	testing.expect(t, call.sponsor != 0)
	testing.expect(t, game.compact_toggle_offer(&c, call.id, 0))
	testing.expect(t, game.compact_accept_call(&c, call.id))
	testing.expect(t, c.compact.active.charter.hard_authority.reviewer != 0)
}

@(test)
operating_withdrawal_returns_only_through_validated_aftermath :: proc(t: ^testing.T) {
	c: game.Campaign
	game.campaign_init(&c, 17007)
	defer game.campaign_destroy(&c)
	install_compact_test_need(&c, 0, .Ship_Repair)
	testing.expect(t, game.compact_surface_one_call(&c))
	call := &c.compact.calls[0]
	testing.expect(t, game.compact_toggle_offer(&c, call.id, 0))
	before_accept := c.material_economy.fleet.stock
	committed_before := c.material_economy.fleet.committed
	sponsor_at := game.institution_index(&c, call.sponsor)
	if sponsor_at >= 0 do c.institutions[sponsor_at].disclosure_policy = .Open
	testing.expect(t, game.compact_accept_call(&c, call.id))
	ship := c.compact.active.seconded_ships[0]
	c.compact.active.status = .Operating
	after_accept := c.material_economy.fleet.stock
	testing.expect(t, game.compact_withdraw_undertaking(&c, "Return under standing doctrine."))
	testing.expect_value(t, c.material_economy.fleet.stock, after_accept)
	testing.expect(t, game.compact_ship_is_seconded(&c, ship))
	testing.expect(t, c.compact.active.withdrawal_requested)

	mismatched := game.Operation_Aftermath {
		id             = 7001,
		layer          = .Passage,
		undertaking_id = game.Compact_Undertaking_ID(u32(c.compact.active.id) + 1),
		intent_event   = c.compact.active.charter.intent_event,
		ship_count     = 1,
	}
	mismatched.ships[0].ship = ship
	validation := game.validate_operation_aftermath(&c, &mismatched)
	testing.expect(t, !validation.valid)
	testing.expect_value(t, validation.issue, game.Operation_Aftermath_Issue.Undertaking_Mismatch)
	testing.expect(t, !game.queue_operation_aftermath(&c, mismatched))
	testing.expect_value(t, c.pending_aftermath.id, game.Operation_ID(0))
	c.pending_aftermath = mismatched
	testing.expect(t, !game.apply_operation_aftermath(&c))
	testing.expect_value(t, c.pending_aftermath.id, game.Operation_ID(0))

	aftermath := mismatched
	aftermath.undertaking_id = c.compact.active.id
	aftermath.objective = .Partial
	aftermath.evidence_recovered = 1
	aftermath.id = 7002
	testing.expect(t, game.validate_operation_aftermath(&c, &aftermath).valid)
	testing.expect(t, game.queue_operation_aftermath(&c, aftermath))
	testing.expect(t, game.apply_operation_aftermath(&c))
	testing.expect_value(t, c.compact.history_count, 1)
	testing.expect_value(t, c.compact.active.status, game.Compact_Undertaking_Status.None)
	testing.expect(t, !game.compact_ship_is_seconded(&c, ship))
	testing.expect(t, c.material_economy.fleet.stock != before_accept)
	testing.expect_value(t, c.material_economy.fleet.committed, committed_before)
	ledger := c.compact.history[0].resource_ledger
	settled_total := game.compact_resources_add(
		game.compact_resources_add(ledger.consumed, ledger.recovered),
		game.compact_resources_add(ledger.lost, ledger.released),
	)
	testing.expect_value(t, settled_total, ledger.reserved)
	testing.expect(t, ledger.settled)
	testing.expect(t, c.compact.counsel.available)
	testing.expect(t, c.compact.counsel.option_count >= 2)
	for action in c.compact.counsel.actions[:c.compact.counsel.option_count] {
		testing.expect(t, action.action != .Local_Response)
	}
	cost_before_callback := c.needs[0].cost
	c.clock.now = game.campaign_time_add(c.clock.now, 4 * game.CAMPAIGN_REPORT_SECONDS)
	game.compact_advance_callbacks(&c)
	testing.expect(t, c.needs[0].cost != cost_before_callback)
	for callback in c.compact.callbacks[:c.compact.callback_count] {
		testing.expect(t, callback.applied_event != 0)
		testing.expect_value(t, callback.stage, game.Compact_Callback_Stage.Resolved)
	}
	cost_after_callback := c.needs[0].cost
	events_after_callback := c.event_sequence
	game.compact_advance_callbacks(&c)
	testing.expect_value(t, c.needs[0].cost, cost_after_callback)
	testing.expect_value(t, c.event_sequence, events_after_callback)
	testing.expect(t, game.validate_expeditionary_compact(&c))
}

@(test)
v8_round_trip_preserves_archived_undertaking_and_resource_ledger :: proc(t: ^testing.T) {
	c := game.new_campaign_seeded_heap(17008)
	defer game.campaign_destroy_heap(c)
	install_compact_test_need(c, 0, .Ship_Repair)
	testing.expect(t, game.compact_surface_one_call(c))
	call := &c.compact.calls[0]
	testing.expect(t, game.compact_toggle_offer(c, call.id, 0))
	testing.expect(t, game.compact_accept_call(c, call.id))
	testing.expect(t, game.compact_withdraw_undertaking(c, "A persisted planning withdrawal."))
	data := game.campaign_serialize(c)
	defer delete(data)
	restored := game.new_campaign_seeded_heap(1)
	defer game.campaign_destroy_heap(restored)
	result := game.campaign_deserialize(data[:], restored)
	testing.expectf(t, result.ok, "%s", result.message)
	testing.expect_value(t, restored.compact.history_count, 1)
	testing.expect(t, restored.compact.history[0].resource_ledger.settled)
	testing.expect_value(
		t,
		restored.compact.history[0].resource_ledger.released,
		restored.compact.history[0].resource_ledger.reserved,
	)
	testing.expect(t, game.validate_expeditionary_compact(restored))
}

@(test)
non_need_calls_follow_their_source_instead_of_expiring_on_refresh :: proc(t: ^testing.T) {
	c: game.Campaign
	game.campaign_init(&c, 17006)
	defer game.campaign_destroy(&c)
	ship := &c.ships[0]
	ship.damage = 3
	game.record_event(&c, .Ship_Damaged, "A source-owned recovery state changed.", ship.id)
	source := game.Compact_Call_Source {
		kind         = .Ship,
		index        = 0,
		id           = u64(ship.id),
		causal_event = c.event_sequence,
	}
	call, ok := game.compact_make_sourced_call(
		&c,
		source,
		.Rescue_Recover,
		1,
		ship.community,
		ship.id,
		"Recovery support",
		"Damage threatens continued service.",
		"The ship chooses local repair or withdrawal.",
		c.season + 1,
	)
	testing.expect(t, ok)
	c.compact.calls[0] = call
	c.compact.call_count = 1
	game.compact_refresh_calls(&c)
	testing.expect_value(t, c.compact.calls[0].status, game.Compact_Call_Status.Open)
	ship.damage = 0
	game.compact_refresh_calls(&c)
	testing.expect_value(
		t,
		c.compact.calls[0].status,
		game.Compact_Call_Status.Resolved_Autonomously,
	)
}
