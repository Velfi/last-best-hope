package game_tests

import "core:math"
import "core:sys/posix"
import "core:testing"

test_binary_system :: proc() -> Solar_System {
	s: Solar_System
	s.model_version =
		STELLAR_SYSTEM_MODEL_VERSION; s.star_count = 2; s.binary_bound = true; s.present_age_billion_years = 4.6
	s.stars[0] = evolve_star_to_age(1, 0, 4.6); s.stars[1] = evolve_star_to_age(.8, 0, 4.6)
	s.binary_orbit = {
		semi_major_axis_au   = .22,
		eccentricity         = .1,
		mean_anomaly_radians = .3,
	}
	s.planet_count = 1; s.planets[0].host = {
		body = {kind = .Barycenter},
	}; s.planets[0].orbit = {
		semi_major_axis_au   = 1.2,
		eccentricity         = .04,
		mean_anomaly_radians = .8,
	}
	p, _ := evaluate_planet(
		7,
		system_effective_host_profile(&s, s.planets[0].host),
		{
			mass_earth = 1,
			radius_earth = 1,
			semi_major_axis_au = 1.2,
			eccentricity = .04,
			bond_albedo = .3,
			greenhouse_warming_k = 33,
			initial_rotation_hours = 24,
		},
	); s.planets[0].body = p
	return s
}

@(test)
stellar_evolution_covers_luminous_and_remnant_phases :: proc(t: ^testing.T) {
	main := evolve_star_to_age(
		1,
		0,
		4.6,
	); giant := evolve_star_to_age(1, 0, 11); white := evolve_star_to_age(1, 0, 14); neutron := evolve_star_to_age(12, 0, 1); black := evolve_star_to_age(35, 0, 1)
	testing.expect_value(
		t,
		main.phase,
		Stellar_Phase.Main_Sequence,
	); testing.expect(t, giant.phase == .Hertzsprung_Gap || giant.phase == .Red_Giant || giant.phase == .Core_Helium_Burning || giant.phase == .Asymptotic_Giant); testing.expect_value(t, white.phase, Stellar_Phase.White_Dwarf); testing.expect_value(t, neutron.phase, Stellar_Phase.Neutron_Star); testing.expect_value(t, black.phase, Stellar_Phase.Black_Hole)
	testing.expect(
		t,
		white.profile.mass_solar < white.initial_mass_solar,
	); testing.expect(t, neutron.profile.radius_solar < .001)
}

@(test)
stellar_population_and_history_are_seed_deterministic :: proc(t: ^testing.T) {
	a := generate_stellar_population(
		7719,
		8,
		-.2,
	); b := generate_stellar_population(7719, 8, -.2); c := generate_stellar_population(7720, 8, -.2)
	testing.expect_value(
		t,
		a,
		b,
	); testing.expect(t, a != c); testing.expect(t, a.star_count >= 1 && a.star_count <= 2)
}

@(test)
black_hole_accretion_follows_present_binary_geometry :: proc(t: ^testing.T) {
	s: Solar_System
	s.star_count = 2; s.binary_bound = true; s.binary_orbit = {
		semi_major_axis_au = 2,
		eccentricity       = 0,
	}
	s.stars[0] = evolve_star_to_age(35, 0, 1)
	s.stars[1] = evolve_star_to_age(1, 0, 4.6)
	dormant := black_hole_accretion_state(&s, 0)
	testing.expect_value(t, dormant.kind, Black_Hole_Accretion_Kind.Dormant)
	testing.expect(t, dormant.roche_lobe_fill < 1)
	testing.expect(t, dormant.view_cosine >= .12 && dormant.view_cosine <= .96)
	testing.expect_value(t, dormant.view_cosine, black_hole_accretion_state(&s, 0).view_cosine)
	testing.expect(t, math.abs(dormant.view_position_angle_radians) <= math.PI / 2)
	testing.expect_value(
		t,
		dormant.view_position_angle_radians,
		black_hole_accretion_state(&s, 0).view_position_angle_radians,
	)

	s.stars[1] = evolve_star_to_age(1, 0, 11.5)
	s.binary_orbit.semi_major_axis_au = .15
	active := black_hole_accretion_state(&s, 0)
	testing.expect(t, active.kind == .Transfer_Disk || active.kind == .Thick_Flow)
	testing.expect(t, active.roche_lobe_fill >= 1)
	testing.expect(t, active.eddington_fraction > 0 && active.disk_outer_radius_km > 0)
}

@(test)
binary_stability_limits_order_s_and_p_regions :: proc(t: ^testing.T) {
	s := test_binary_system(); limits := system_stability_limits(&s)
	testing.expect(
		t,
		limits.circumprimary_outer_au > 0 &&
		limits.circumprimary_outer_au < s.binary_orbit.semi_major_axis_au,
	)
	testing.expect(
		t,
		limits.circumsecondary_outer_au > 0 &&
		limits.circumbinary_inner_au > s.binary_orbit.semi_major_axis_au,
	)
}

@(test)
binary_ephemeris_preserves_barycenter :: proc(t: ^testing.T) {
	s := test_binary_system()
	for day in 0 ..< 100 {a, _ := system_body_state_at(&s, {kind = .Star, index = 0}, f64(day)); b, _ := system_body_state_at(&s, {kind = .Star, index = 1}, f64(day)); for axis in 0 ..< 3 {weighted := a.position_au[axis] * s.stars[0].profile.mass_solar + b.position_au[axis] * s.stars[1].profile.mass_solar; testing.expect(t, math.abs(weighted) < 1.0e-10)}}
}

@(test)
ephemeris_random_access_is_deterministic_and_periodic :: proc(t: ^testing.T) {
	s := test_binary_system(
		
	); period := 365.256 * math.sqrt(math.pow(s.binary_orbit.semi_major_axis_au, 3) / (s.stars[0].profile.mass_solar + s.stars[1].profile.mass_solar)); a, _ := system_body_state_at(&s, {kind = .Star, index = 0}, 17); b, _ := system_body_state_at(&s, {kind = .Star, index = 0}, 17 + period); c, _ := system_body_state_at(&s, {kind = .Star, index = 0}, 17)
	testing.expect_value(
		t,
		a,
		c,
	); for axis in 0 ..< 3 do testing.expect(t, math.abs(a.position_au[axis] - b.position_au[axis]) < 1.0e-9)
	far, _ := system_body_state_at(
		&s,
		{kind = .Star, index = 0},
		17 + period * 1000,
	); for axis in 0 ..< 3 do testing.expect(t, math.abs(a.position_au[axis] - far.position_au[axis]) < s.binary_orbit.semi_major_axis_au * .01)
}

@(test)
combined_binary_flux_matches_inverse_square_sum :: proc(t: ^testing.T) {
	s := test_binary_system(
		
	); planet, _ := system_body_state_at(&s, {kind = .Planet, index = 0}, 0); expected: f64
	for star, i in s.stars[:s.star_count] {position, _ := system_body_state_at(&s, {kind = .Star, index = i}, 0); d2: f64; for axis in 0 ..< 3 {d := planet.position_au[axis] - position.position_au[axis]; d2 += d * d}; expected += star.profile.luminosity_solar / d2}
	actual := system_planet_flux_at(
		&s,
		0,
		0,
	); testing.expect(t, math.abs(actual - expected) < 1.0e-12); envelope := system_planet_flux_envelope(&s, 0); testing.expect(t, envelope.minimum_earth <= envelope.mean_earth && envelope.mean_earth <= envelope.maximum_earth)
}

@(test)
generated_systems_have_valid_hosts_orbits_and_histories :: proc(t: ^testing.T) {
	saw_binary, saw_s, saw_p := false, false, false
	for seed in u64(1) ..= u64(500) {s, ok := generate_solar_system_population(seed, 6, -.1); testing.expect(t, ok && system_validate(&s)); if s.star_count == 2 && s.binary_bound {saw_binary = true; limits := system_stability_limits(&s); for p in s.planets[:s.planet_count] {if p.host.body.kind == .Barycenter {saw_p = true; testing.expect(t, p.orbit.semi_major_axis_au >= limits.circumbinary_inner_au)} else {saw_s = true; limit := p.host.body.index == 0 ? limits.circumprimary_outer_au : limits.circumsecondary_outer_au; testing.expect(t, p.orbit.semi_major_axis_au <= max(limit, .015))}; testing.expect(t, p.climate_history_count > 0)}}}
	testing.expect(t, saw_binary && saw_s && saw_p)
}

@(test)
binary_names_have_distinct_component_designations :: proc(t: ^testing.T) {
	s := test_binary_system(
		
	); s.seed = 91; names := generate_solar_system_names(s); testing.expect(t, names.star_names[0] != "" && names.star_names[1] != "" && names.star_names[0] != names.star_names[1])
}

@(test)
detailed_system_generation_meets_cpu_budget :: proc(t: ^testing.T) {
	// This test runs beside other tests in Odin's thread pool. Thread CPU time
	// measures generator work without charging it for scheduler preemption.
	started: posix.timespec; finished: posix.timespec
	_ = posix.clock_gettime(.THREAD_CPUTIME_ID, &started)
	for seed in u64(1) ..= u64(8) do _, _ = generate_solar_system_population(seed, 5.5, -.1)
	_ = posix.clock_gettime(.THREAD_CPUTIME_ID, &finished)
	elapsed_ms :=
		f64(finished.tv_sec - started.tv_sec) * 1000 +
		f64(finished.tv_nsec - started.tv_nsec) / 1_000_000
	testing.expectf(
		t,
		elapsed_ms < 100,
		"eight detailed systems took %.3f ms (budget 100 ms)",
		elapsed_ms,
	)
}
