package game_tests

import "core:testing"

@(test)
ship_service_tiers_include_active_and_archived_history :: proc(t: ^testing.T) {
	ship: Ship
	testing.expect_value(t, ship_service_tier(ship), Ship_Service_Tier.None)
	scores := [6]int{1, 3, 6, 9, 13, 18}
	tiers := [6]Ship_Service_Tier{.First, .Second, .Third, .Fourth, .Fifth, .Sixth}
	for score, i in scores {
		ship.experience = i32(score)
		testing.expect_value(t, ship_service_tier(ship), tiers[i])
	}
	ship.experience = 0
	ship.discoveries = 2
	ship.memory_count = 1
	ship.archived_memory_count = 1
	testing.expect_value(t, ship_service_score(ship), 6)
	testing.expect_value(t, ship_service_tier(ship), Ship_Service_Tier.Third)
}

@(test)
latest_promise_record_supersedes_legacy_counter_priority :: proc(t: ^testing.T) {
	ship := Ship {
		promises_broken = 2,
		promises_upheld = 1,
	}
	testing.expect_value(t, ship_promise_record(ship), Ship_Promise_Record.Broken)
	ship.last_promise_event = 19
	ship.last_promise_status = .Upheld
	testing.expect_value(t, ship_promise_record(ship), Ship_Promise_Record.Upheld)
	ship.last_promise_status = .Transformed
	testing.expect_value(t, ship_promise_record(ship), Ship_Promise_Record.Transformed)
}
