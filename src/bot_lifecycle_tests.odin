package main

import game "../packages/game"
import "core:testing"

@(test)
bot_progress_diagnostics_report_the_highest_priority_blocker :: proc(t: ^testing.T) {
	c := game.new_campaign_seeded_heap(801)
	defer game.campaign_destroy_heap(c)
	c.ending_prompt_pending = true
	c.material_economy.food_shortage_response_pending = true
	testing.expect_value(t, bot_run_blocker(c), "food shortage response")

	c.economy_loss_decision_pending = true
	testing.expect_value(t, bot_run_blocker(c), "economy loss decision")
}

@(test)
bot_progress_signature_changes_with_lifecycle_state :: proc(t: ^testing.T) {
	c := game.new_campaign_seeded_heap(802)
	defer game.campaign_destroy_heap(c)
	initial := bot_run_progress_signature(c)
	c.current_situation.phase = .Proposal
	testing.expect(t, bot_run_progress_signature(c) != initial)
	proposal := bot_run_progress_signature(c)
	c.current_situation.phase = .Decision
	testing.expect(t, bot_run_progress_signature(c) != proposal)
}
