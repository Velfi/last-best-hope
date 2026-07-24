package game

import "core:math"

// Planet generation uses Earth, Solar, AU, and year units. Keeping the public
// inputs in familiar astronomical units also keeps the calculations inspectable.
Star_Profile :: struct {
	mass_solar:        f64,
	luminosity_solar:  f64,
	radius_solar:      f64,
	age_billion_years: f64,
}

Planet_Inputs :: struct {
	mass_earth:             f64,
	radius_earth:           f64,
	semi_major_axis_au:     f64,
	eccentricity:           f64,
	bond_albedo:            f64,
	greenhouse_warming_k:   f64,
	initial_rotation_hours: f64,
}

Tidal_State :: enum {
	Free_Rotating,
	Transitional,
	Likely_Locked,
}
Climate_Band :: enum {
	Frozen,
	Temperate,
	Hot,
	Infernal,
}

Planet :: struct {
	seed:                      u64,
	star:                      Star_Profile,
	inputs:                    Planet_Inputs,
	stellar_flux_earth:        f64,
	orbital_period_days:       f64,
	equilibrium_temperature_k: f64,
	surface_temperature_k:     f64,
	surface_gravity_earth:     f64,
	escape_velocity_km_s:      f64,
	tidal_lock_time_years:     f64,
	hill_radius_au:            f64,
	roche_limit_au:            f64,
	tidal_state:               Tidal_State,
	climate:                   Climate_Band,
	in_habitable_flux_band:    bool,
	orbit_stable:              bool,
}

planet_inputs_valid :: proc(star: Star_Profile, p: Planet_Inputs) -> bool {
	return(
		star.mass_solar > 0 &&
		star.luminosity_solar > 0 &&
		star.radius_solar > 0 &&
		star.age_billion_years >= 0 &&
		p.mass_earth > 0 &&
		p.radius_earth > 0 &&
		p.semi_major_axis_au > 0 &&
		p.eccentricity >= 0 &&
		p.eccentricity < 1 &&
		p.bond_albedo >= 0 &&
		p.bond_albedo < 1 &&
		p.initial_rotation_hours > 0 \
	)
}

evaluate_planet :: proc(seed: u64, star: Star_Profile, p: Planet_Inputs) -> (Planet, bool) {
	result := Planet {
		seed   = seed,
		star   = star,
		inputs = p,
	}
	if !planet_inputs_valid(star, p) do return result, false

	result.stellar_flux_earth =
		star.luminosity_solar / (p.semi_major_axis_au * p.semi_major_axis_au)
	result.orbital_period_days =
		365.256 *
		math.sqrt(
			p.semi_major_axis_au * p.semi_major_axis_au * p.semi_major_axis_au / star.mass_solar,
		)
	absorbed_relative_to_earth := result.stellar_flux_earth * (1 - p.bond_albedo) / 0.7
	result.equilibrium_temperature_k = 254.6 * math.pow(absorbed_relative_to_earth, 0.25)
	result.surface_temperature_k = result.equilibrium_temperature_k + p.greenhouse_warming_k
	result.surface_gravity_earth = p.mass_earth / (p.radius_earth * p.radius_earth)
	result.escape_velocity_km_s = 11.186 * math.sqrt(p.mass_earth / p.radius_earth)

	// Constant-Q estimate normalized to an Earth-like rocky planet. It is an
	// order-of-magnitude classification, not a claim to predict exact spin state.
	result.tidal_lock_time_years =
		1.0e11 *
		math.pow(p.semi_major_axis_au, 6) *
		p.mass_earth /
		(star.mass_solar * star.mass_solar * math.pow(p.radius_earth, 3))
	star_mass_earth := star.mass_solar * 332946.0
	result.hill_radius_au =
		p.semi_major_axis_au * math.pow(p.mass_earth / (3 * star_mass_earth), 1.0 / 3.0)
	star_radius_au := star.radius_solar * 0.00465047
	star_density_relative := star.mass_solar / math.pow(star.radius_solar, 3)
	planet_density_relative := p.mass_earth / math.pow(p.radius_earth, 3)
	result.roche_limit_au =
		2.44 *
		star_radius_au *
		math.pow(star_density_relative / planet_density_relative, 1.0 / 3.0)
	result.orbit_stable = p.semi_major_axis_au * (1 - p.eccentricity) > result.roche_limit_au

	age_years := star.age_billion_years * 1.0e9
	ratio := age_years / result.tidal_lock_time_years
	result.tidal_state =
		ratio >= 1 ? .Likely_Locked : ratio >= 0.1 ? .Transitional : .Free_Rotating
	result.climate =
		result.surface_temperature_k < 240 ? .Frozen : result.surface_temperature_k <= 310 ? .Temperate : result.surface_temperature_k <= 400 ? .Hot : .Infernal
	// Conservative, composition-agnostic screening; climate remains separately reported.
	result.in_habitable_flux_band =
		result.stellar_flux_earth >= 0.35 && result.stellar_flux_earth <= 1.10
	return result, true
}

planet_rng_next :: proc(state: ^u64) -> u64 {
	if state^ == 0 do state^ = 0x9e3779b97f4a7c15
	x := state^
	x ~= x >> 12; x ~= x << 25; x ~= x >> 27
	state^ = x
	return x * 2685821657736338717
}

planet_random_unit :: proc(state: ^u64) -> f64 {
	return f64(planet_rng_next(state) >> 11) / f64(u64(1) << 53)
}

planet_random_range :: proc(state: ^u64, low, high: f64) -> f64 {
	return low + (high - low) * planet_random_unit(state)
}

generate_planet :: proc(seed: u64, star: Star_Profile) -> (Planet, bool) {
	if star.mass_solar <= 0 || star.luminosity_solar <= 0 || star.radius_solar <= 0 do return {}, false
	state := seed
	// Log-uniform mass and orbit avoid clustering generated worlds at the large end.
	mass := math.pow(10.0, planet_random_range(&state, -1.0, 0.7))
	radius := mass < 1 ? math.pow(mass, 0.28) : math.pow(mass, 0.22)
	orbit :=
		math.pow(10.0, planet_random_range(&state, -1.0, 0.7)) * math.sqrt(star.luminosity_solar)
	inputs := Planet_Inputs {
		mass_earth             = mass,
		radius_earth           = radius,
		semi_major_axis_au     = orbit,
		eccentricity           = planet_random_range(&state, 0, 0.35),
		bond_albedo            = planet_random_range(&state, 0.08, 0.65),
		greenhouse_warming_k   = planet_random_range(&state, 0, 80),
		initial_rotation_hours = planet_random_range(&state, 8, 72),
	}
	return evaluate_planet(seed, star, inputs)
}
