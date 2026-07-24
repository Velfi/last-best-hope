package game_tests

import "core:math"
import "core:testing"

@(test)
combat_physical_unit_contract_is_stable :: proc(t: ^testing.T) {
	testing.expect_value(t, combat_units_to_km(1), f64(1000))
	testing.expect_value(t, combat_km_to_units(250000), f32(250))
	testing.expect(t, math.abs(f64(combat_light_delay_minutes(300)) - .0166782) < .00001)
}

@(test)
combat_weapon_profiles_use_physical_engagement_bands :: proc(t: ^testing.T) {
	laser := combat_weapon_profile(.Laser)
	missile := combat_weapon_profile(.Guided_Missile)
	torpedo := combat_weapon_profile(.Heavy_Torpedo)
	testing.expect_value(t, laser.maximum_range_km, f64(300000))
	testing.expect_value(t, missile.maximum_range_km, f64(3000000))
	testing.expect_value(t, torpedo.maximum_range_km, f64(300000))
	testing.expect(t, combat_weapon_flight_minutes(.Guided_Missile, 1200) > 490)
	testing.expect(t, combat_weapon_flight_minutes(.Guided_Missile, 1200) < 510)
}

@(test)
combat_role_thrust_is_mass_bounded :: proc(t: ^testing.T) {
	fighter := combat_unit("Fighter", "", "", "", .Friendly, .Fighter, {})
	capital := combat_unit("Capital", "", "", "", .Friendly, .Capital, {})
	testing.expect(t, fighter.drive_acceleration_g > capital.drive_acceleration_g)
	testing.expect(t, fighter.max_acceleration > capital.max_acceleration)
	testing.expect(t, fighter.speed > capital.speed)
}

@(test)
combat_trajectory_forecast_accounts_for_acceleration_and_braking :: proc(t: ^testing.T) {
	forecast := combat_trajectory_forecast(
		{},
		{},
		{1000, 0, 0},
		combat_acceleration_units_per_minute2(.04),
		5,
	)
	testing.expect(t, forecast.valid)
	testing.expect(t, forecast.burn_minutes > 0)
	testing.expect(t, forecast.time_to_closest_minutes > forecast.burn_minutes)
	testing.expect(t, forecast.time_to_closest_minutes < 2000)
}

@(test)
combat_time_compression_drains_the_same_fixed_steps :: proc(t: ^testing.T) {
	a := combat_new_mission(24301)
	b := combat_new_mission(24301)
	defer combat_mission_destroy(&a)
	defer combat_mission_destroy(&b)
	combat_tick(&a, 1)
	for _ in 0 ..< 20 do combat_tick(&b, .05)
	testing.expect_value(t, a.time, b.time)
	testing.expect_value(t, a.rng, b.rng)
	for unit, i in a.units[:a.unit_count] {
		testing.expect_value(t, unit.position, b.units[i].position)
		testing.expect_value(t, unit.velocity, b.units[i].velocity)
	}
}

@(test)
combat_seedship_recovery_requires_a_velocity_match :: proc(t: ^testing.T) {
	m := combat_new_mission(24301)
	defer combat_mission_destroy(&m)
	m.seedship_found = true
	recovery := &m.units[m.recovery_unit]
	recovery.position = m.seedship
	recovery.velocity = {m.seedship_velocity.x + .2, m.seedship_velocity.y, m.seedship_velocity.z}
	combat_tick_fixed(&m, .05)
	testing.expect_value(t, m.recovery_progress, f32(0))
	recovery.position = m.seedship
	recovery.velocity = m.seedship_velocity
	combat_tick_fixed(&m, .05)
	testing.expect(t, m.recovery_progress > 0)
}

@(test)
combat_next_decision_stops_before_hostile_terminal_defense :: proc(t: ^testing.T) {
	m := combat_new_mission(24301)
	defer combat_mission_destroy(&m)
	append(
		&m.salvos,
		Combat_Salvo{
			side = .Raider,
			active = true,
			time_remaining = 42,
			arrival_latest = m.time + 42,
		},
	)
	testing.expect_value(t, combat_minutes_until_next_decision(&m), f32(30))
}

@(test)
combat_damage_creates_a_deterministic_subsystem_scar :: proc(t: ^testing.T) {
	a := combat_new_mission(24301)
	b := combat_new_mission(24301)
	defer combat_mission_destroy(&a)
	defer combat_mission_destroy(&b)
	combat_apply_damage(&a, 0, 20)
	combat_apply_damage(&b, 0, 20)
	testing.expect_value(t, a.units[0].subsystems, b.units[0].subsystems)
	subsystems := a.units[0].subsystems
	total :=
		subsystems.engines + subsystems.sensors + subsystems.radiators +
		subsystems.weapons + subsystems.flight_deck + subsystems.command +
		subsystems.life_support
	testing.expect(t, total < 700)
}
