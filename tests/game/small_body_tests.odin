package game_tests

import "core:testing"

solar_reference :: proc() -> Star_Profile {
	return {mass_solar = 1, luminosity_solar = 1, radius_solar = 1, age_billion_years = 4.6}
}

earth_reference :: proc() -> Planet {
	p, _ := evaluate_planet(
		1,
		solar_reference(),
		{
			mass_earth = 1,
			radius_earth = 1,
			semi_major_axis_au = 1,
			eccentricity = 0.0167,
			bond_albedo = 0.3,
			greenhouse_warming_k = 33,
			initial_rotation_hours = 24,
		},
	)
	return p
}

@(test)
lunar_reference_matches_orbit_and_gravity :: proc(t: ^testing.T) {
	m, ok := evaluate_moon(
		2,
		earth_reference(),
		{
			mass_lunar = 1,
			radius_lunar = 1,
			semi_major_axis_km = 384400,
			eccentricity = 0.0549,
			bond_albedo = 0.11,
			initial_rotation_hours = 655.7,
		},
	)
	testing.expect(t, ok)
	testing.expect(t, close_to(m.orbital_period_days, 27.28, 0.1))
	testing.expect(t, close_to(m.surface_gravity_earth, 0.165, 0.005))
	testing.expect_value(t, m.tidal_state, Tidal_State.Likely_Locked)
	testing.expect(t, m.outside_roche_limit && m.inside_stable_prograde_zone)
}

@(test)
moon_generation_is_deterministic :: proc(t: ^testing.T) {
	a, ok_a := generate_moon(900, earth_reference())
	b, ok_b := generate_moon(900, earth_reference())
	c, ok_c := generate_moon(901, earth_reference())
	testing.expect(t, ok_a && ok_b && ok_c)
	testing.expect_value(t, a.inputs, b.inputs)
	testing.expect(t, a.inputs != c.inputs)
}

@(test)
one_kilometer_rock_has_consistent_mass_and_escape_speed :: proc(t: ^testing.T) {
	a, ok := evaluate_asteroid(
		3,
		solar_reference(),
		{
			diameter_km = 1,
			density_g_cm3 = 3,
			semi_major_axis_au = 2.5,
			eccentricity = 0.1,
			inclination_degrees = 5,
			bond_albedo = 0.2,
			rotation_period_hours = 5,
			impact_velocity_km_s = 20,
			composition = .Silicate,
		},
	)
	testing.expect(t, ok)
	testing.expect(t, close_to(a.mass_kg, 1.5708e12, 1e8))
	testing.expect(t, close_to(a.orbital_period_years, 3.9528, 0.001))
	testing.expect(t, a.escape_velocity_m_s > 0.6 && a.escape_velocity_m_s < 0.7)
	testing.expect(t, a.cohesionless_spin_stable)
	testing.expect(t, a.impact_energy_megatons > 70)
}

@(test)
asteroid_generation_is_deterministic_and_composition_bounded :: proc(t: ^testing.T) {
	a, ok_a := generate_asteroid(44, solar_reference())
	b, ok_b := generate_asteroid(44, solar_reference())
	c, ok_c := generate_asteroid(45, solar_reference())
	testing.expect(t, ok_a && ok_b && ok_c)
	testing.expect_value(t, a.inputs, b.inputs)
	testing.expect(t, a.inputs != c.inputs)
	testing.expect(t, a.inputs.density_g_cm3 >= 0.6 && a.inputs.density_g_cm3 <= 7.5)
}

@(test)
invalid_small_body_inputs_are_rejected :: proc(t: ^testing.T) {
	_, moon_ok := evaluate_moon(1, {}, {})
	_, asteroid_ok := evaluate_asteroid(1, {}, {})
	testing.expect(t, !moon_ok && !asteroid_ok)
}
