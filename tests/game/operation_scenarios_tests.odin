package game_tests

import "core:testing"

@(test)
all_twelve_operation_objectives_share_a_complete_contract :: proc(t: ^testing.T) {
	passage, combat := 0, 0; seen: [13]bool
	for raw in 1 ..= 12 {scenario := Operation_Objective(raw); contract := scenario_contract(scenario); testing.expect(t, scenario_contract_valid(contract)); testing.expect_value(t, contract.scenario, scenario); testing.expect(t, !seen[raw]); seen[raw] = true; if contract.domain == .Passage {passage += 1} else {combat += 1}}
	testing.expect_value(t, passage, 6); testing.expect_value(t, combat, 6)
}

@(test)
scenario_failures_create_the_authored_recoverable_follow_up :: proc(t: ^testing.T) {
	expected_continuations := [12]Scenario_Failure_Continuation {
		.Renewed_Claim,
		.Renewed_Claim,
		.Evacuation_Claim,
		.Treaty_Dispute,
		.Scattered_Convoy,
		.Rescue_Search,
		.Enemy_Entrenched,
		.Settlement_Damaged,
		.Blockade_Tightened,
		.Migration_Diverted,
		.Fleet_Adrift,
		.Route_Closed,
	}
	expected_outputs := [12]Need_Kind {
		.Sustenance_Shortfall,
		.Settlement_Demand,
		.Settlement_Defense,
		.Institution_Dispute,
		.Representation,
		.Ship_Repair,
		.Archive_Staffing,
		.Settlement_Defense,
		.Sustenance_Shortfall,
		.Representation,
		.Ship_Repair,
		.Jurisdiction_Dispute,
	}
	for raw in 1 ..= 12 {
		contract := scenario_contract(Operation_Objective(raw))
		testing.expect_value(t, contract.failure_continuation, expected_continuations[raw - 1])
		testing.expect_value(t, contract.political_output, expected_outputs[raw - 1])
	}
}
