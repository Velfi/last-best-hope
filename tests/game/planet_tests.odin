package game_tests

import "core:math"
import "core:testing"

close_to :: proc(a, b, tolerance: f64) -> bool {return math.abs(a - b) <= tolerance}

@(test)
earth_reference_has_expected_derived_values :: proc(t: ^testing.T) {
	star := Star_Profile {
		mass_solar        = 1,
		luminosity_solar  = 1,
		radius_solar      = 1,
		age_billion_years = 4.6,
	}
	inputs := Planet_Inputs {
		mass_earth             = 1,
		radius_earth           = 1,
		semi_major_axis_au     = 1,
		eccentricity           = 0.0167,
		bond_albedo            = 0.3,
		greenhouse_warming_k   = 33,
		initial_rotation_hours = 24,
	}
	p, ok := evaluate_planet(7, star, inputs)
	testing.expect(t, ok)
	testing.expect(t, close_to(p.stellar_flux_earth, 1, 0.001))
	testing.expect(t, close_to(p.orbital_period_days, 365.256, 0.01))
	testing.expect(t, close_to(p.surface_temperature_k, 287.6, 0.5))
	testing.expect(t, close_to(p.surface_gravity_earth, 1, 0.001))
	testing.expect_value(t, p.tidal_state, Tidal_State.Free_Rotating)
	testing.expect(t, p.orbit_stable && p.in_habitable_flux_band)
}

@(test)
close_world_around_small_star_is_likely_locked :: proc(t: ^testing.T) {
	star := Star_Profile {
		mass_solar        = 0.2,
		luminosity_solar  = 0.008,
		radius_solar      = 0.25,
		age_billion_years = 5,
	}
	inputs := Planet_Inputs {
		mass_earth             = 1,
		radius_earth           = 1,
		semi_major_axis_au     = 0.09,
		eccentricity           = 0.02,
		bond_albedo            = 0.3,
		greenhouse_warming_k   = 20,
		initial_rotation_hours = 30,
	}
	p, ok := evaluate_planet(8, star, inputs)
	testing.expect(t, ok)
	testing.expect_value(t, p.tidal_state, Tidal_State.Likely_Locked)
	testing.expect(t, p.orbit_stable)
}

@(test)
generation_is_deterministic_and_seeded :: proc(t: ^testing.T) {
	star := Star_Profile {
		mass_solar        = 1,
		luminosity_solar  = 1,
		radius_solar      = 1,
		age_billion_years = 4.6,
	}
	a, ok_a := generate_planet(12345, star)
	b, ok_b := generate_planet(12345, star)
	c, ok_c := generate_planet(12346, star)
	testing.expect(t, ok_a && ok_b && ok_c)
	testing.expect_value(t, a.inputs, b.inputs)
	testing.expect(t, a.inputs != c.inputs)
}

@(test)
invalid_physical_inputs_are_rejected :: proc(t: ^testing.T) {
	_, ok := evaluate_planet(1, {}, {})
	testing.expect(t, !ok)
}
