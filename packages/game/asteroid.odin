package game

import "core:math"

Asteroid_Composition :: enum {
	Carbonaceous,
	Silicate,
	Metallic,
	Icy,
}

Asteroid_Inputs :: struct {
	diameter_km:           f64,
	density_g_cm3:         f64,
	semi_major_axis_au:    f64,
	eccentricity:          f64,
	inclination_degrees:   f64,
	bond_albedo:           f64,
	rotation_period_hours: f64,
	impact_velocity_km_s:  f64,
	composition:           Asteroid_Composition,
}

Asteroid :: struct {
	seed:                       u64,
	host:                       Orbital_Host,
	orbit:                      Orbital_Elements,
	inputs:                     Asteroid_Inputs,
	mass_kg:                    f64,
	orbital_period_years:       f64,
	perihelion_au:              f64,
	aphelion_au:                f64,
	equilibrium_temperature_k:  f64,
	surface_gravity_m_s2:       f64,
	escape_velocity_m_s:        f64,
	critical_spin_period_hours: f64,
	impact_energy_megatons:     f64,
	cohesionless_spin_stable:   bool,
}

asteroid_inputs_valid :: proc(star: Star_Profile, a: Asteroid_Inputs) -> bool {
	return(
		star.mass_solar > 0 &&
		star.luminosity_solar > 0 &&
		a.diameter_km > 0 &&
		a.density_g_cm3 > 0 &&
		a.semi_major_axis_au > 0 &&
		a.eccentricity >= 0 &&
		a.eccentricity < 1 &&
		a.inclination_degrees >= 0 &&
		a.inclination_degrees <= 180 &&
		a.bond_albedo >= 0 &&
		a.bond_albedo < 1 &&
		a.rotation_period_hours > 0 &&
		a.impact_velocity_km_s >= 0 \
	)
}

evaluate_asteroid :: proc(seed: u64, star: Star_Profile, a: Asteroid_Inputs) -> (Asteroid, bool) {
	result := Asteroid {
		seed   = seed,
		inputs = a,
	}
	if !asteroid_inputs_valid(star, a) do return result, false
	radius_m := a.diameter_km * 500
	density_kg_m3 := a.density_g_cm3 * 1000
	result.mass_kg = 4.0 / 3.0 * math.PI * math.pow(radius_m, 3) * density_kg_m3
	result.orbital_period_years = math.sqrt(math.pow(a.semi_major_axis_au, 3) / star.mass_solar)
	result.perihelion_au = a.semi_major_axis_au * (1 - a.eccentricity)
	result.aphelion_au = a.semi_major_axis_au * (1 + a.eccentricity)
	mean_flux :=
		star.luminosity_solar /
		(a.semi_major_axis_au *
				a.semi_major_axis_au *
				math.sqrt(1 - a.eccentricity * a.eccentricity))
	result.equilibrium_temperature_k =
		254.6 * math.pow(mean_flux * (1 - a.bond_albedo) / 0.7, 0.25)
	result.surface_gravity_m_s2 = 6.67430e-11 * result.mass_kg / (radius_m * radius_m)
	result.escape_velocity_m_s = math.sqrt(2 * 6.67430e-11 * result.mass_kg / radius_m)
	result.critical_spin_period_hours =
		math.sqrt(3 * math.PI / (6.67430e-11 * density_kg_m3)) / 3600
	result.cohesionless_spin_stable = a.rotation_period_hours >= result.critical_spin_period_hours
	energy_joules := 0.5 * result.mass_kg * math.pow(a.impact_velocity_km_s * 1000, 2)
	result.impact_energy_megatons = energy_joules / 4.184e15
	return result, true
}

asteroid_composition_density :: proc(kind: Asteroid_Composition, state: ^u64) -> (f64, f64) {
	switch kind {
	case .Carbonaceous:
		return planet_random_range(state, 1.2, 2.2), planet_random_range(state, 0.02, 0.10)
	case .Silicate:
		return planet_random_range(state, 2.4, 3.5), planet_random_range(state, 0.10, 0.35)
	case .Metallic:
		return planet_random_range(state, 4.5, 7.5), planet_random_range(state, 0.10, 0.30)
	case .Icy:
		return planet_random_range(state, 0.6, 1.5), planet_random_range(state, 0.30, 0.75)
	}
	return 2, 0.1
}

generate_asteroid :: proc(seed: u64, star: Star_Profile) -> (Asteroid, bool) {
	if star.mass_solar <= 0 || star.luminosity_solar <= 0 do return {}, false
	state := seed
	kind := Asteroid_Composition(planet_rng_next(&state) % u64(len(Asteroid_Composition)))
	density, albedo := asteroid_composition_density(kind, &state)
	inputs := Asteroid_Inputs {
		diameter_km           = math.pow(10.0, planet_random_range(&state, -2, 2.7)),
		density_g_cm3         = density,
		semi_major_axis_au    = math.pow(10.0, planet_random_range(&state, -0.2, 1.0)),
		eccentricity          = planet_random_range(&state, 0, 0.65),
		inclination_degrees   = planet_random_range(&state, 0, 35),
		bond_albedo           = albedo,
		rotation_period_hours = math.pow(10.0, planet_random_range(&state, -0.1, 2)),
		impact_velocity_km_s  = planet_random_range(&state, 5, 35),
		composition           = kind,
	}
	return evaluate_asteroid(seed, star, inputs)
}
