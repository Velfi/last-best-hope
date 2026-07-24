package game_tests

import "core:testing"

@(test)
campaign_clock_is_frame_partition_deterministic :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 25001)
	b: Campaign
	campaign_init(&b, 25001)
	defer campaign_destroy(&a)
	defer campaign_destroy(&b)
	for _ in 0 ..< 60 do _ = campaign_tick(&a, 1.0 / 60.0)
	for _ in 0 ..< 10 do _ = campaign_tick(&b, .1)
	testing.expect_value(t, a.clock.now, b.clock.now)
	testing.expect_value(t, a.season, b.season)
	testing.expect_value(t, a.event_sequence, b.event_sequence)
}

@(test)
campaign_attention_globally_pauses_and_resumes_explicitly :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 25002)
	defer campaign_destroy(&c)
	id := campaign_raise_attention(
		&c,
		{
			source = .Campaign,
			level = .Decision,
			title = "A decision is due.",
			cause = "Standing policy no longer settles the work.",
			default_action = "Hold the existing commitment.",
			choices = {"HOLD", "", "", ""},
			choice_count = 1,
		},
	)
	testing.expect(t, id != 0)
	testing.expect(t, c.clock.paused_for_attention)
	before := c.clock.now
	testing.expect_value(t, campaign_tick(&c, 10), i64(0))
	testing.expect_value(t, c.clock.now, before)
	testing.expect(t, campaign_resolve_attention(&c, id, 0))
	testing.expect(t, !c.clock.paused_for_attention)
	testing.expect(t, campaign_set_speed(&c, .One))
	testing.expect(t, campaign_tick(&c, 1) > 0)
}

@(test)
direct_campaign_resolution_invalidates_its_stale_attention_pause :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 250021)
	defer campaign_destroy(&c)
	c.ending_prompt_pending = true

	advance_season(&c)
	testing.expect(t, campaign_pending_attention(&c) != nil)
	testing.expect(t, conclude_chronicle(&c))
	testing.expect(t, c.ending_finale.active)
	testing.expect(t, !c.ending_prompt_pending)

	before := c.clock.now
	advance_season(&c)
	testing.expect(t, campaign_pending_attention(&c) == nil)
	testing.expect(t, !c.clock.paused_for_attention)
	testing.expect(t, c.clock.now > before)
}

@(test)
scheduled_council_work_advances_without_a_season_turn :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 25003)
	defer campaign_destroy(&c)
	seed_front_families(&c)
	_ = activate_front_proposal(&c, 0)
	testing.expect(t, choose_political_direction(&c, .Front, 0, 0))
	checkpoints := c.council.checkpoint_count
	testing.expect(t, campaign_advance_exact(&c, 30 * CAMPAIGN_DAY_SECONDS) > 0)
	testing.expect(t, c.council.checkpoint_count > checkpoints)
	testing.expect_value(t, c.season, i32(0))
}

@(test)
clock_schedule_attention_and_active_council_survive_save_load :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 25004)
	defer campaign_destroy(&c)
	seed_front_families(&c)
	_ = activate_front_proposal(&c, 0)
	testing.expect(t, choose_political_direction(&c, .Front, 0, 0))
	id := campaign_raise_attention(
		&c,
		{
			source = .Campaign,
			level = .Decision,
			title = "Hold for review.",
			cause = "The forecast changed.",
			default_action = "Hold.",
			choices = {"HOLD", "", "", ""},
			choice_count = 1,
		},
	)
	data := campaign_serialize(&c)
	defer delete(data)
	restored: Campaign
	defer campaign_destroy(&restored)
	result := campaign_deserialize(data[:], &restored)
	testing.expect(t, result.ok)
	testing.expect_value(t, restored.clock.now, c.clock.now)
	testing.expect_value(t, restored.council.phase, c.council.phase)
	testing.expect(t, campaign_pending_attention(&restored) != nil)
	testing.expect_value(t, campaign_pending_attention(&restored).id, id)
}

@(test)
operation_elapsed_waits_behind_attention_without_being_lost :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 25005)
	defer campaign_destroy(&c)
	id := campaign_raise_attention(
		&c,
		{
			source = .Campaign,
			level = .Decision,
			title = "Hold.",
			cause = "A boundary is unresolved.",
			default_action = "Hold.",
			choices = {"HOLD", "", "", ""},
			choice_count = 1,
		},
	)
	before := c.clock.now
	testing.expect_value(t, campaign_advance_operation_delta(&c, 3600), i64(0))
	testing.expect_value(t, c.clock.now, before)
	testing.expect(t, c.clock.operation_fraction_seconds >= 3600)
	testing.expect(t, campaign_resolve_attention(&c, id, 0))
	testing.expect_value(t, campaign_advance_operation_delta(&c, 0), i64(3600))
	testing.expect_value(t, i64(c.clock.now) - i64(before), i64(3600))
}

@(test)
advance_to_attention_crosses_routine_reporting_boundaries :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 25006)
	defer campaign_destroy(&c)
	c.max_seasons = 2
	testing.expect(t, campaign_advance_to_attention(&c))
	testing.expect_value(t, c.season, i32(2))
	testing.expect(t, c.ending_prompt_pending)
	testing.expect(t, campaign_pending_attention(&c) != nil)
}

@(test)
project_commitment_is_atomic_when_schedule_is_full :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 25007)
	defer campaign_destroy(&c)
	for i in 0 ..< len(c.scheduled_work) {
		c.scheduled_work[i] = {
			id         = u64(i + 1),
			source     = .Obligation,
			source_id  = u64(i + 1),
			started_at = c.clock.now,
			due_at     = Campaign_Time(i64(c.clock.now) + CAMPAIGN_REPORT_SECONDS),
			active     = true,
		}
	}
	before := c.material_economy.fleet.stock
	testing.expect(t, !queue_project(&c, .Produce_Reserves))
	testing.expect_value(t, c.material_economy.fleet.stock, before)
	for project in c.projects do testing.expect(t, !project.active)
}

@(test)
campaign_attention_default_changes_the_underlying_state :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 25008)
	defer campaign_destroy(&c)
	c.economy_loss_decision_pending = true
	c.economy_loss_candidate = c.ships[0].id
	c.material_economy.fleet.stock.equipment = 0
	c.material_economy.fleet.stock.services = 0
	_ = campaign_tick(&c, 0)
	pending := campaign_pending_attention(&c)
	testing.expect(t, pending != nil)
	testing.expect(t, campaign_resolve_attention(&c, pending.id, -1))
	testing.expect(t, !c.economy_loss_decision_pending)
	testing.expect(t, !c.ships[0].active)
}
