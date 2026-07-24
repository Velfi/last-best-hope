package game

import "core:fmt"
import "core:math"

// Close Engagement stores plot distance in thousands of kilometres and time in
// minutes. Keeping the chart near the origin preserves renderer precision;
// these conversions are the public physical contract.
COMBAT_KM_PER_UNIT :: f64(1000)
COMBAT_SECONDS_PER_TIME_UNIT :: f64(60)
COMBAT_LIGHT_KM_PER_SECOND :: f64(299792.458)
COMBAT_STANDARD_GRAVITY_KM_S2 :: f64(.00980665)

Combat_Sensor_Mode :: enum {
	Silent,
	Passive_Watch,
	Active_Search,
	Illuminate,
	Relay,
	Deceive,
}

Combat_Maneuver_Intent :: enum {
	Hold_Geometry,
	Close_To_Envelope,
	Open_Distance,
	Screen_Element,
	Cross_Bearing,
	Mask_Behind_Field,
	Intercept_Salvo,
	Approach_Objective,
	Withdraw,
}

Combat_Wave_Phase :: enum {
	Boost,
	Cruise,
	Search,
	Terminal,
	Resolved,
}

Combat_Weapon_Profile :: struct {
	min_range_km, effective_range_km, maximum_range_km: f64,
	projectile_speed_km_s, acceleration_g, endurance_minutes: f64,
	heat_per_shot: f32,
	limited: bool,
}

Combat_Trajectory_Forecast :: struct {
	closest_approach_km: f64,
	time_to_closest_minutes: f64,
	burn_minutes: f64,
	arrival_speed_km_s: f64,
	valid: bool,
}

combat_units_to_km :: proc(units: f32) -> f64 {
	return f64(units) * COMBAT_KM_PER_UNIT
}

combat_km_to_units :: proc(km: f64) -> f32 {
	return f32(km / COMBAT_KM_PER_UNIT)
}

combat_minutes_to_seconds :: proc(minutes: f32) -> f64 {
	return f64(minutes) * COMBAT_SECONDS_PER_TIME_UNIT
}

combat_light_delay_minutes :: proc(distance_units: f32) -> f32 {
	seconds := combat_units_to_km(max(distance_units, 0)) / COMBAT_LIGHT_KM_PER_SECOND
	return f32(seconds / COMBAT_SECONDS_PER_TIME_UNIT)
}

combat_acceleration_units_per_minute2 :: proc(acceleration_g: f64) -> f32 {
	km_per_minute2 :=
		acceleration_g * COMBAT_STANDARD_GRAVITY_KM_S2 *
		COMBAT_SECONDS_PER_TIME_UNIT * COMBAT_SECONDS_PER_TIME_UNIT
	return combat_km_to_units(km_per_minute2)
}

combat_role_acceleration_g :: proc(u: Combat_Unit) -> f64 {
	// The recovery tug is a dedicated combat rescue craft. It must cross the
	// operational volume after relay acquisition; ordinary diaspora hulls keep
	// their lower sustained acceleration.
	if u.operational_role == .Recovery_Tug do return 3.0
	if u.side == .Friendly && u.role == .Capital do return .04
	switch ship_hull_archetype_family(u.hull_archetype) {
	case .Strike_Craft:
		return .20
	case .Light_Combatant:
		return .08
	case .Frigate:
		return .04
	case .Line_Warship:
		if u.hull_archetype == .Battleship || u.hull_archetype == .Dreadnought do return .006
		return .015
	case .Carrier_And_Command:
		return .015
	case .Diaspora:
		return .01
	case .Unspecified:
	}
	return .02
}

combat_role_cruise_speed_units_per_minute :: proc(u: Combat_Unit) -> f32 {
	if u.operational_role == .Recovery_Tug do return 12
	switch ship_hull_archetype_family(u.hull_archetype) {
	case .Strike_Craft:
		return 12
	case .Light_Combatant:
		return 8
	case .Frigate:
		return 5
	case .Line_Warship:
		if u.hull_archetype == .Battleship || u.hull_archetype == .Dreadnought do return 2
		return 3.5
	case .Carrier_And_Command:
		return 3
	case .Diaspora:
		return 2.5
	case .Unspecified:
	}
	return 4
}

combat_weapon_profile :: proc(weapon: Combat_Weapon_Class) -> Combat_Weapon_Profile {
	switch weapon {
	case .Laser:
		return {50000, 160000, 300000, 299792.458, 0, 0, 22, false}
	case .Kinetic:
		return {10000, 80000, 150000, 100, 0, 0, 10, false}
	case .Guided_Missile:
		return {300000, 1200000, 3000000, 40, .04, 1200, 12, true}
	case .Heavy_Torpedo:
		return {50000, 180000, 300000, 67, .12, 120, 18, true}
	case .Defensive_Gun:
		return {100, 2000, 5000, 5, 0, 0, 4, false}
	case .Defensive_Laser:
		return {5000, 25000, 50000, 299792.458, 0, 0, 8, false}
	case .Spinal_Kinetic:
		return {50000, 220000, 500000, 150, 0, 0, 55, true}
	}
	return {}
}

combat_weapon_range :: proc(u: Combat_Unit, weapon: Combat_Weapon_Class) -> f32 {
	profile := combat_weapon_profile(weapon)
	range := combat_km_to_units(profile.maximum_range_km)
	tuning := clamp(u.range / 150, f32(.65), f32(1.45))
	return range * tuning
}

combat_weapon_minimum_range :: proc(weapon: Combat_Weapon_Class) -> f32 {
	return combat_km_to_units(combat_weapon_profile(weapon).min_range_km)
}

combat_weapon_flight_minutes :: proc(weapon: Combat_Weapon_Class, distance_units: f32) -> f32 {
	profile := combat_weapon_profile(weapon)
	if profile.projectile_speed_km_s <= 0 do return 0
	return f32(
		combat_units_to_km(distance_units) /
		profile.projectile_speed_km_s /
		COMBAT_SECONDS_PER_TIME_UNIT,
	)
}

combat_trajectory_forecast :: proc(
	position, velocity, destination: Combat_Vec3,
	acceleration_units_per_minute2, cruise_speed_units_per_minute: f32,
) -> Combat_Trajectory_Forecast {
	dx := f64(destination.x - position.x)
	dy := f64(destination.y - position.y)
	dz := f64(destination.z - position.z)
	distance := math.sqrt(dx * dx + dy * dy + dz * dz)
	if distance <= .000001 do return {valid = true}
	acceleration := f64(max(acceleration_units_per_minute2, f32(.000001)))
	cruise := f64(max(cruise_speed_units_per_minute, f32(.000001)))
	turnover_distance := cruise * cruise / acceleration
	time: f64
	burn: f64
	if distance <= turnover_distance {
		burn = math.sqrt(distance / acceleration)
		time = burn * 2
	} else {
		burn = cruise / acceleration
		time = burn * 2 + (distance - turnover_distance) / cruise
	}
	relative_speed :=
		math.sqrt(f64(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z))
	return {
		closest_approach_km = 0,
		time_to_closest_minutes = time,
		burn_minutes = burn,
		arrival_speed_km_s = relative_speed * COMBAT_KM_PER_UNIT / COMBAT_SECONDS_PER_TIME_UNIT,
		valid = true,
	}
}

combat_format_distance :: proc(distance_units: f32) -> string {
	km := combat_units_to_km(distance_units)
	if km >= 1000000 do return fmt.tprintf("%.2f Mkm", km / 1000000)
	return fmt.tprintf("%.0f km", km)
}

combat_format_duration :: proc(minutes: f32) -> string {
	if minutes >= 60 do return fmt.tprintf("%.1f h", minutes / 60)
	return fmt.tprintf("%.0f min", minutes)
}

combat_set_sensor_mode :: proc(m: ^Combat_Mission, index: int, mode: Combat_Sensor_Mode) {
	if index < 0 || index >= m.friendly_count do return
	u := &m.units[index]
	if u.disabled || u.extracted do return
	u.sensor_mode = mode
	u.silent_running = mode == .Silent
	u.active_sensors = mode == .Active_Search || mode == .Illuminate || mode == .Deceive
	if mode == .Relay do u.communication = .Continuous
	if u.active_sensors {
		u.exposure = min(100, u.exposure + 12)
		combat_add_event_at(m, fmt.tprintf("%s began active emissions", u.name), u.position)
	}
}

combat_minutes_until_next_decision :: proc(m: ^Combat_Mission) -> f32 {
	if m.complete || m.request_pending do return 0
	soonest := max(combat_mission_duration(m) - m.time, f32(0))
	for salvo in m.salvos {
		if !salvo.active || salvo.side == .Friendly do continue
		// Pause before terminal defense, not after the useful response window.
		terminal := max(salvo.time_remaining - 12, f32(0))
		soonest = min(soonest, terminal)
	}
	for u in m.units[:m.friendly_count] {
		if u.disabled || u.extracted || !u.trajectory_forecast.valid do continue
		arrival := f32(u.trajectory_forecast.time_to_closest_minutes)
		if arrival > .05 do soonest = min(soonest, arrival)
	}
	return max(soonest, f32(.05))
}

combat_advance_to_next_decision :: proc(m: ^Combat_Mission) {
	remaining := combat_minutes_until_next_decision(m)
	for remaining > 0 && !m.complete && !m.request_pending {
		step := min(remaining, f32(1))
		combat_tick(m, step)
		remaining -= step
	}
}
