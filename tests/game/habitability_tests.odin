package game_tests

import "core:testing"

@(test)
earth_meets_physical_earth_analogue_tier :: proc(t: ^testing.T) {
	star := Star_Profile {
		mass_solar        = 1,
		luminosity_solar  = 1,
		radius_solar      = 1,
		age_billion_years = 4.6,
	}
	earth, ok := evaluate_planet(
		1,
		star,
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
	testing.expect(t, ok)
	a := assess_planet_habitability(earth, true, true, true)
	testing.expect_value(t, a.highest_tier, Habitability_Tier.Long_Term_Habitable)
	testing.expect(t, a.rocky && a.temperate && a.earth_size && a.suitable_star && a.stable_orbit)
}

@(test)
venus_does_not_meet_temperate_rocky_tier :: proc(t: ^testing.T) {
	star := Star_Profile {
		mass_solar        = 1,
		luminosity_solar  = 1,
		radius_solar      = 1,
		age_billion_years = 4.6,
	}
	venus, ok := evaluate_planet(
		2,
		star,
		{
			mass_earth = 0.815,
			radius_earth = 0.949,
			semi_major_axis_au = 0.723,
			eccentricity = 0.0068,
			bond_albedo = 0.77,
			greenhouse_warming_k = 510,
			initial_rotation_hours = 5832,
		},
	)
	testing.expect(t, ok)
	a := assess_planet_habitability(venus, true, false, false)
	testing.expect_value(t, a.highest_tier, Habitability_Tier.Rocky)
}

@(test)
habitability_report_is_deterministic_and_nested :: proc(t: ^testing.T) {
	g := generate_galaxy(711)
	a := estimate_galaxy_habitability(&g, .Evidence_Centered, 8192)
	b := estimate_galaxy_habitability(&g, .Evidence_Centered, 8192)
	testing.expect_value(t, a, b)
	testing.expect_value(t, a.model_version, HABITABILITY_MODEL_VERSION)
	for tier in 1 ..< len(Habitability_Tier) {
		testing.expect(t, a.tiers[tier].median <= a.tiers[tier - 1].median)
		testing.expect(t, a.tiers[tier].low_5 <= a.tiers[tier].high_95)
	}
}

@(test)
scenario_assumptions_order_speculative_outcomes :: proc(t: ^testing.T) {
	g := generate_galaxy(912)
	conservative := estimate_galaxy_habitability(&g, .Conservative, 32768)
	centered := estimate_galaxy_habitability(&g, .Evidence_Centered, 32768)
	optimistic := estimate_galaxy_habitability(&g, .Optimistic, 32768)
	tier := int(Habitability_Tier.Long_Term_Habitable)
	testing.expect(t, conservative.tiers[tier].median <= centered.tiers[tier].median)
	testing.expect(t, centered.tiers[tier].median <= optimistic.tiers[tier].median)
}

@(test)
cell_rates_are_bounded_and_cover_the_galaxy :: proc(t: ^testing.T) {
	g := generate_galaxy(44)
	r := estimate_galaxy_habitability(&g, .Evidence_Centered, 4096)
	testing.expect_value(t, r.cell_count, g.neighborhood_count)
	for cell in r.cells[:r.cell_count] {
		testing.expect(t, cell.samples > 0 && cell.stars_represented > 0)
		for rate in cell.rates do testing.expect(t, rate >= 0 && rate <= 1)
	}
}
