package game_tests

import "core:testing"
import game "../../packages/game"

@(test)
persistent_fleet_playtest_fixture_has_complete_deterministic_preflight :: proc(t: ^testing.T) {
	a := game.persistent_fleet_playtest_fixture(5519)
	b := game.persistent_fleet_playtest_fixture(5519)
	testing.expect_value(t, a, b)
	preflight := game.persistent_fleet_playtest_preflight(&a)
	testing.expect(t, preflight.valid)
	testing.expect_value(t, a.duration_seconds, 52 * 60)
	testing.expect_value(t, a.moment_count, 8)
	testing.expect(t, a.authority.valid)
	testing.expect(t, a.doctrines[0].viable && a.doctrines[1].viable)
	testing.expect(t, a.doctrines[0].conduct != a.doctrines[1].conduct)
}

@(test)
persistent_fleet_playtest_capture_records_required_observation_channels_in_time_order :: proc(t: ^testing.T) {
	log := game.Persistent_Fleet_Playtest_Log{seed = 5519}
	captures := [6]game.Persistent_Fleet_Playtest_Capture {
		{kind = .Screen_Visit, timestamp_seconds = 30, value = 1},
		{kind = .Choice, timestamp_seconds = 480, moment_event = 1003, value = 2},
		{kind = .Attention_Duration, timestamp_seconds = 1560, duration_seconds = 42, moment_event = 1005},
		{kind = .Dossier_Use, timestamp_seconds = 1602, ship = 103},
		{kind = .Default_Accepted, timestamp_seconds = 1980, moment_event = 1006},
		{kind = .Causal_Link_Opened, timestamp_seconds = 2520, moment_event = 1007, linked_event = 1005},
	}
	for capture in captures do testing.expect(t, game.persistent_fleet_capture(&log, capture))
	testing.expect_value(t, log.count, len(captures))
	testing.expect(t, !game.persistent_fleet_capture(&log, {kind = .Choice, timestamp_seconds = 10}))
}

@(test)
persistent_fleet_playtest_preflight_rejects_missing_human_legibility_beats :: proc(t: ^testing.T) {
	fixture := game.persistent_fleet_playtest_fixture()
	fixture.moment_count -= 1
	preflight := game.persistent_fleet_playtest_preflight(&fixture)
	testing.expect(t, !preflight.valid)
	fixture = game.persistent_fleet_playtest_fixture()
	fixture.duration_seconds = 20 * 60
	preflight = game.persistent_fleet_playtest_preflight(&fixture)
	testing.expect(t, !preflight.valid)
}
