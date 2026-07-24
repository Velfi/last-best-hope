package game_tests

import "core:testing"

@(test)
decision_attention_requires_a_default_or_explicit_player_rule :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 27171)
	defer campaign_destroy(&c)
	rejected := campaign_raise_attention(
		&c,
		{
			source = .Campaign,
			level = .Decision,
			title = "Incomplete decision",
			cause = "The condition changed.",
		},
	)
	testing.expect_value(t, rejected, u64(0))
	accepted := campaign_raise_attention(
		&c,
		{
			source = .Campaign,
			level = .Decision,
			title = "Explicit resolution",
			cause = "The condition changed.",
			explicit_resolution_required = true,
		},
	)
	testing.expect(t, accepted != 0)
	pending := campaign_pending_attention(&c)
	testing.expect(t, pending != nil)
	testing.expect(t, pending.underway_action != "")
	testing.expect(t, pending.standing_order != "")
	testing.expect(t, pending.affected_summary != "")
	testing.expect(t, pending.response_window != "")
}

@(test)
every_attention_source_normalizes_to_a_complete_causal_record :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 27172)
	defer campaign_destroy(&c)
	sources := [5]Attention_Source{.Council, .Campaign, .Passage, .Far_Engagement, .Close_Engagement}
	for source, i in sources {
		id := campaign_raise_attention(
			&c,
			{
				source = source,
				source_id = u64(i + 1),
				level = .Decision,
				title = "Causal fixture",
				cause = "A known condition changed.",
				default_action = "Hold the current commitment.",
				choices = {"HOLD", "", "", ""},
				choice_count = 1,
				default_choice = 0,
			},
		)
		testing.expect(t, id != 0)
		for &event in c.attention_queue {
			if event.id != id do continue
			testing.expect(t, event.underway_action != "")
			testing.expect(t, event.changed_fact != "")
			testing.expect(t, event.standing_order != "")
			testing.expect(t, event.affected_summary != "")
			testing.expect(t, event.threshold != "")
			testing.expect(t, event.response_window != "")
			testing.expect(t, event.no_response_default != "")
		}
		campaign_clear_attention_source(&c, source, u64(i + 1))
		found_record := false
		for event in c.attention_queue do if event.id == id {
			found_record = true
			testing.expect(t, !event.active)
			testing.expect_value(t, event.record_status, Attention_Record_Status.Invalidated)
		}
		testing.expect(t, found_record)
	}
}

@(test)
deep_attention_default_resolves_the_backing_decision :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 27174)
	defer campaign_destroy(&c)
	e := Far_Engagement{}
	e.decision = {
		kind           = .Contact_Interpretation,
		title          = "Contact interpretation",
		situation      = "The contact crossed the standing threshold.",
		default_text   = "Remain under passive watch.",
		commands       = {
			.Remain_Passive,
			.Accept_Standing_Orders,
			.Accept_Standing_Orders,
			.Accept_Standing_Orders,
		},
		labels         = {"REMAIN PASSIVE", "", "", ""},
		option_enabled = {true, false, false, false},
		option_count   = 1,
		default_option = 0,
		pending        = true,
	}
	c.far_engagement = &e
	id := campaign_raise_attention(
		&c,
		{
			source = .Far_Engagement,
			source_id = 74,
			level = .Decision,
			title = e.decision.title,
			cause = e.decision.situation,
			default_action = e.decision.default_text,
			choices = {"REMAIN PASSIVE", "", "", ""},
			choice_values = {i32(Far_Command.Remain_Passive), 0, 0, 0},
			choice_count = 1,
			default_choice = 0,
		},
	)
	testing.expect(t, campaign_resolve_attention(&c, id, -1))
	testing.expect(t, !e.decision.pending)
	testing.expect(t, e.record_count > 0)
}

@(test)
combat_attention_default_resolves_the_backing_request :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 27175)
	defer campaign_destroy(&c)
	m := Combat_Mission {
		seed            = 75,
		units           = make([dynamic]Combat_Unit, 1),
		unit_count      = 1,
		friendly_count  = 1,
		request_pending = true,
		request_kind    = .Authorize_Emergency_Defense,
		request_unit    = 0,
	}
	defer delete(m.units)
	c.combat_runtime = &m
	id := campaign_raise_attention(
		&c,
		{
			source = .Close_Engagement,
			source_id = m.seed,
			level = .Decision,
			title = "Emergency defense",
			cause = "A defensive threshold was crossed.",
			default_action = "Authorize emergency defense.",
			choices = {"APPROVE", "DENY", "", ""},
			choice_values = {1, 0, 0, 0},
			choice_count = 2,
			default_choice = 0,
		},
	)
	testing.expect(t, campaign_resolve_attention(&c, id, -1))
	testing.expect(t, !m.request_pending)
	testing.expect(t, m.request_cooldown > 0)
}

@(test)
council_attention_default_withdraws_the_unsupported_deviation :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 27176)
	defer campaign_destroy(&c)
	seed_front_families(&c)
	_ = activate_front_proposal(&c, 0)
	testing.expect(t, choose_political_direction(&c, .Front, 0, 2))
	resolve_council_checkpoint(&c, .Debate)
	testing.expect(t, c.council.exception_pending)
	id := campaign_raise_attention(
		&c,
		{
			source = .Council,
			source_id = u64(c.council.id),
			level = .Constitutional,
			title = "Council authority conflict",
			cause = c.council.exception_reason,
			default_action = "Withdraw the motion.",
			choices = {"WITHDRAW", "RETAIN", "EMERGENCY", ""},
			choice_count = 3,
			default_choice = 0,
		},
	)
	testing.expect(t, campaign_resolve_attention(&c, id, -1))
	testing.expect(t, !c.council.exception_pending)
	testing.expect(t, !c.council.active)
}
