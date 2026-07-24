package game

import "core:math"

Moon_Inputs :: struct {
	mass_lunar:             f64,
	radius_lunar:           f64,
	semi_major_axis_km:     f64,
	eccentricity:           f64,
	bond_albedo:            f64,
	initial_rotation_hours: f64,
}

Moon :: struct {
	seed:                        u64,
	host_planet_index:           int,
	host:                        Orbital_Host,
	orbit:                       Orbital_Elements,
	inputs:                      Moon_Inputs,
	orbital_period_days:         f64,
	surface_gravity_earth:       f64,
	escape_velocity_km_s:        f64,
	equilibrium_temperature_k:   f64,
	roche_limit_km:              f64,
	host_hill_radius_km:         f64,
	tidal_lock_time_years:       f64,
	tidal_heating_relative_io:   f64,
	tidal_state:                 Tidal_State,
	outside_roche_limit:         bool,
	inside_stable_prograde_zone: bool,
}

moon_inputs_valid :: proc(host: Planet, p: Moon_Inputs) -> bool {
	return(
		host.inputs.mass_earth > 0 &&
		host.inputs.radius_earth > 0 &&
		p.mass_lunar > 0 &&
		p.radius_lunar > 0 &&
		p.semi_major_axis_km > 0 &&
		p.eccentricity >= 0 &&
		p.eccentricity < 1 &&
		p.bond_albedo >= 0 &&
		p.bond_albedo < 1 &&
		p.initial_rotation_hours > 0 \
	)
}

evaluate_moon :: proc(seed: u64, host: Planet, p: Moon_Inputs) -> (Moon, bool) {
	result := Moon {
		seed   = seed,
		inputs = p,
	}
	if !moon_inputs_valid(host, p) do return result, false

	mass_earth := p.mass_lunar * 0.012300
	radius_earth := p.radius_lunar * 0.2727
	result.orbital_period_days =
		2 *
		math.PI *
		math.sqrt(
			math.pow(p.semi_major_axis_km, 3) /
			(398600.4418 * (host.inputs.mass_earth + mass_earth)),
		) /
		86400
	result.surface_gravity_earth = mass_earth / math.pow(radius_earth, 2)
	result.escape_velocity_km_s = 11.186 * math.sqrt(mass_earth / radius_earth)
	absorbed_relative_to_earth := host.stellar_flux_earth * (1 - p.bond_albedo) / 0.7
	result.equilibrium_temperature_k = 254.6 * math.pow(absorbed_relative_to_earth, 0.25)

	host_density_relative := host.inputs.mass_earth / math.pow(host.inputs.radius_earth, 3)
	moon_density_relative := mass_earth / math.pow(radius_earth, 3)
	result.roche_limit_km =
		2.44 *
		host.inputs.radius_earth *
		6371 *
		math.pow(host_density_relative / moon_density_relative, 1.0 / 3.0)
	result.host_hill_radius_km = host.hill_radius_au * 149597870.7
	periapsis := p.semi_major_axis_km * (1 - p.eccentricity)
	apoapsis := p.semi_major_axis_km * (1 + p.eccentricity)
	result.outside_roche_limit = periapsis > result.roche_limit_km
	result.inside_stable_prograde_zone = apoapsis < 0.4895 * result.host_hill_radius_km

	result.tidal_lock_time_years =
		1.0e6 *
		math.pow(p.semi_major_axis_km / 384400, 6) *
		p.mass_lunar /
		(math.pow(host.inputs.mass_earth, 2) * math.pow(p.radius_lunar, 3))
	age_years := host.star.age_billion_years * 1.0e9
	ratio := age_years / result.tidal_lock_time_years
	result.tidal_state =
		ratio >= 1 ? .Likely_Locked : ratio >= 0.1 ? .Transitional : .Free_Rotating

	// Constant-Q scaling relative to Io; useful as a comparative activity index.
	result.tidal_heating_relative_io =
		math.pow(p.eccentricity / 0.0041, 2) *
		math.pow(host.inputs.mass_earth / 317.8, 2.5) *
		math.pow(p.radius_lunar / 0.2859, 5) *
		math.pow(421700 / p.semi_major_axis_km, 7.5)
	return result, true
}

generate_moon :: proc(seed: u64, host: Planet) -> (Moon, bool) {
	if host.inputs.mass_earth <= 0 || host.inputs.radius_earth <= 0 || host.hill_radius_au <= 0 do return {}, false
	state := seed
	mass := math.pow(10.0, planet_random_range(&state, -3, 0.3))
	radius := math.pow(mass, 0.32)
	host_radius_km := host.inputs.radius_earth * 6371
	outer_km := host.hill_radius_au * 149597870.7 * 0.42
	if outer_km <= host_radius_km * 3 do return {}, false
	orbit := math.pow(
		10.0,
		planet_random_range(&state, math.log10(host_radius_km * 3), math.log10(outer_km)),
	)
	inputs := Moon_Inputs {
		mass_lunar             = mass,
		radius_lunar           = radius,
		semi_major_axis_km     = orbit,
		eccentricity           = planet_random_range(&state, 0, 0.12),
		bond_albedo            = planet_random_range(&state, 0.04, 0.75),
		initial_rotation_hours = planet_random_range(&state, 8, 100),
	}
	return evaluate_moon(seed, host, inputs)
}
