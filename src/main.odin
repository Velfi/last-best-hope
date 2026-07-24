package main

import game "../packages/game"
import "core:fmt"
import "core:os"

run_demo :: proc() {c := game.new_campaign_heap(0x5eed); defer game.campaign_destroy_heap(c)
	ships := [2]int{0, 1}
	contract := game.default_passage_contract()
	ok, msg := game.begin_passage(c, contract, ships[:], &c.passage)
	fmt.println("LAST BEST HOPE — CONTINUOUS DARK")
	fmt.println(msg)
	if !ok do return
	result: Bot_Run_Result
	config := Bot_Run_Config {
		profile     = .Strategist,
		max_actions = 256,
	}
	ok = bot_reach_unknown_door(c, &config, &result, 2.5)
	if !ok {fmt.printf(
			"The voyage paused without reaching an unknown correspondence: %v.\n",
			c.passage.pause_reason,
		)
		return}
	fmt.println("The permanent galaxy endpoint is known. Select the next leg.")
	fmt.printf(
		"Local atlas discoveries: %d; objective met: %v\n",
		c.passage.local_atlas_count,
		c.passage.contract.objective_met,
	)
	if game.plot_normal_course_to_fleet(c, &c.passage) do game.advance_passage(c, &c.passage, c.passage.normal_course.total_days)
	if !game.set_passage_safe_endpoint(c, &c.passage, .Fleet) {fmt.println(
			"The fleet endpoint is not yet reachable.",
		)
		return}
	ok, msg = game.conclude_passage(c, &c.passage)
	fmt.println(msg)
	if !ok do return
	record := c.dark_strategy_records[0]
	estimate := game.dark_strategy_estimate(&record)
	fmt.printf(
		"Sponsor evidence %d · objective %.0f%% · safe %.0f%% · record %.0f%%\n",
		estimate.evidence,
		estimate.objective_rate * 100,
		estimate.safety_rate * 100,
		estimate.record_rate * 100,
	)}

dark_demo_main :: proc() {if len(os.args) > 1 && os.args[1] == "--agent" {run_agent_interface()
		return}
	if run_combat_ai_cli(os.args) do return
	if run_bot_cli(os.args) do return
	run_demo()}
