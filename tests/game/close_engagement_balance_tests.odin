package game_tests

import "core:testing"
import "core:time"

// These tests sample complete autoplay missions and enforce authored pacing
// and difficulty targets. Keep them in the balance suite rather than the
// edit-time correctness suite.

@(test)
combat_primary_objective_cannot_be_rushed_in_opening_minutes :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 60 * time.Second)
	for seed in 1 ..= 20 {
		m := combat_autoplay_mission(u64(seed), 180)
		testing.expect(t, !m.population_recovered)
		combat_mission_destroy(&m)
	}
}

@(test)
combat_autoplay_recovery_converges_on_the_moving_seedship :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 60 * time.Second)
	m := combat_new_mission(1)
	defer combat_mission_destroy(&m)
	recovery := m.recovery_unit
	starting_distance := combat_distance(m.units[recovery].position, m.seedship)
	controller: Combat_Autoplay_Controller
	found_at: f32 = -1
	found_distance: f32
	for !m.complete && m.time < 1100 {
		combat_autoplay_step(&m, &controller)
		combat_tick_fixed(&m, .05)
		if m.seedship_found && found_at < 0 {
			found_at = m.time
			found_distance = combat_distance(m.units[recovery].position, m.seedship)
		}
	}
	distance := combat_distance(m.units[recovery].position, m.seedship)
	testing.expectf(
		t,
		m.recovery_progress > 0 || distance < starting_distance,
		"recovery failed to converge: start=%.1f found-distance=%.1f end=%.1f relays=%.1f/%.1f found=%v at=%.1f order=%v disabled=%v speed=%.2f accel=%.4f velocity=%.2f/%.2f/%.2f",
		starting_distance,
		found_distance,
		distance,
		m.relay_progress[0],
		m.relay_progress[1],
		m.seedship_found,
		found_at,
		m.units[recovery].order,
		m.units[recovery].disabled,
		m.units[recovery].speed,
		m.units[recovery].max_acceleration,
		m.units[recovery].velocity.x,
		m.units[recovery].velocity.y,
		m.units[recovery].velocity.z,
	)
}

@(test)
combat_standard_balance_and_pacing :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 60 * time.Second)
	wins := 0
	total_time: f32
	first_failure: Combat_Autoplay_Report
	first_result: Combat_Autoplay_Report
	for seed in 1 ..= 100 {
		result := combat_autoplay(u64(seed))
		if seed == 1 do first_result = result
		if result.population do wins += 1
		if !result.population && first_failure.seed == 0 do first_failure = result
		total_time += result.time
		testing.expect(t, result.time <= COMBAT_DURATION + .1)
	}
	mean := total_time / 100
	testing.expectf(
		t,
		wins >= 75,
		"physical combat wins=%d mean=%.1f first-failure seed=%d relays=%.1f/%.1f recovery=%.1f distance=%.1f match=%.2f disabled=%v extracted=%v active=%d",
		wins,
		mean,
		first_failure.seed,
		first_failure.relay_progress[0],
		first_failure.relay_progress[1],
		first_failure.recovery_progress,
		first_failure.recovery_distance,
		first_failure.recovery_match_speed,
		first_failure.recovery_disabled,
		first_failure.recovery_extracted,
		first_failure.friendly_unextracted,
	)
	testing.expectf(
		t,
		mean >= 1100 && mean <= COMBAT_DURATION + .1,
		"physical combat wins=%d mean=%.1f seed1-time=%.1f active=%d role=%v recovery-extracted=%v last=%v@%.1f",
		wins,
		mean,
		first_result.time,
		first_result.friendly_unextracted,
		first_result.first_unextracted_role,
		first_result.recovery_extracted,
		first_result.last_extraction_role,
		first_result.last_extraction_time,
	)
}
