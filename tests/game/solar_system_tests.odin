package game_tests

import "core:math"
import "core:testing"

@(test)
solar_system_generation_is_deterministic :: proc(t: ^testing.T) {
	a := generate_solar_system(0x5eed)
	b := generate_solar_system(0x5eed)
	c := generate_solar_system(0x5eee)
	testing.expect_value(t, a, b)
	testing.expect(t, a != c)
	testing.expect(t, a.planet_count >= 1 && a.planet_count <= MAX_SYSTEM_PLANETS)
}

@(test)
generated_surface_components_are_normalized_and_match_planet_family :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(50) {
		system := generate_solar_system(seed)
		for planet in system.planets[:system.planet_count] {
			testing.expect(t, planet.geometric_albedo >= .04 && planet.geometric_albedo <= .75)
			total: f64
			for fraction in planet.surface.fractions {
				testing.expect(t, fraction >= 0 && fraction <= 1)
				total += fraction
			}
			testing.expect(t, math.abs(total - 1) < 1e-9)
			if planet.kind == .Ocean do testing.expect(t, planet.surface.fractions[int(Surface_Component.Liquid_Water)] > .5)
			if planet.kind == .Ice do testing.expect(t, planet.surface.fractions[int(Surface_Component.Water_Ice)] > .5)
			cloud_total: f64
			for fraction in planet.clouds.fractions {testing.expect(t, fraction >= 0 && fraction <= 1); cloud_total += fraction}
			testing.expect(t, math.abs(cloud_total - 1) < 1e-9)
			if planet.kind == .Ocean do testing.expect(t, planet.clouds.fractions[int(Cloud_Component.Water)] > .9)
			if planet.kind == .Gas_Giant do testing.expect(t, planet.clouds.fractions[int(Cloud_Component.Ammonia)] > planet.clouds.fractions[int(Cloud_Component.Water)])
			if planet.kind == .Ice_Giant do testing.expect(t, planet.clouds.fractions[int(Cloud_Component.Methane)] > planet.clouds.fractions[int(Cloud_Component.Water)])
		}
	}
}

@(test)
cloud_composition_generation_is_deterministic :: proc(t: ^testing.T) {
	a := planet_cloud_composition(.Gas_Giant, 130, 0xc10d)
	b := planet_cloud_composition(.Gas_Giant, 130, 0xc10d)
	c := planet_cloud_composition(.Gas_Giant, 130, 0xc10e)
	testing.expect_value(t, a, b); testing.expect(t, a != c)
}

@(test)
generated_star_remains_on_main_sequence :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(100) {
		star := generate_main_sequence_star(seed)
		testing.expect(t, star.profile.mass_solar >= 0.19 && star.profile.mass_solar <= 1.51)
		testing.expect(
			t,
			star.profile.age_billion_years < star.main_sequence_lifetime_billion_years,
		)
		testing.expect(
			t,
			star.effective_temperature_k > 2000 && star.effective_temperature_k < 8500,
		)
	}
}

@(test)
generated_planet_orbits_are_ordered_and_hill_stable :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(50) {
		system := generate_solar_system(seed)
		for outer, i in system.planets[:system.planet_count] do for inner in system.planets[:i] {
			if inner.host.body.kind != outer.host.body.kind || inner.host.body.index != outer.host.body.index do continue
			testing.expect(t, outer.body.inputs.semi_major_axis_au > inner.body.inputs.semi_major_axis_au)
			host_mass := system_effective_host_profile(&system, outer.host).mass_solar
			testing.expect(t, mutual_hill_separation(inner.body, outer.body, max(host_mass, .01)) >= 9)
		}
	}
}

@(test)
generated_moons_remain_in_their_stable_zone :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(30) {
		system := generate_solar_system(seed)
		testing.expect(t, system.moon_count <= MAX_SYSTEM_MOONS)
		for moon in system.moons[:system.moon_count] {
			testing.expect(t, moon.outside_roche_limit)
			testing.expect(t, moon.inside_stable_prograde_zone)
		}
	}
}

@(test)
system_belts_and_samples_share_bounds :: proc(t: ^testing.T) {
	system := generate_solar_system(77)
	for belt in system.belts[:system.belt_count] {
		testing.expect(t, belt.inner_au < belt.outer_au)
		for asteroid in system.asteroids[belt.sample_start:belt.sample_start + belt.sample_count] {
			testing.expect(t, asteroid.inputs.semi_major_axis_au >= belt.inner_au)
			testing.expect(t, asteroid.inputs.semi_major_axis_au <= belt.outer_au)
		}
	}
}

@(test)
invalid_host_star_rejects_system_generation :: proc(t: ^testing.T) {
	_, ok := generate_solar_system_around(1, {})
	testing.expect(t, !ok)
}
