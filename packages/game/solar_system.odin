package game

import "core:math"

MAX_SYSTEM_PLANETS :: 10
MAX_SYSTEM_MOONS :: 48
MAX_SYSTEM_BELTS :: 2
MAX_SYSTEM_ASTEROIDS :: 16

Star_Class :: enum {
	M,
	K,
	G,
	F,
}
System_Planet_Kind :: enum {
	Rocky,
	Ocean,
	Ice,
	Ice_Giant,
	Gas_Giant,
}

Surface_Component :: enum {
	Silicate,
	Iron_Oxide,
	Liquid_Water,
	Water_Ice,
	Sulfur,
	Carbon,
	Methane,
	Ammonia,
	Vegetation,
}
SURFACE_COMPONENT_COUNT :: len(Surface_Component)

Cloud_Component :: enum {
	Water,
	Ammonia,
	Methane,
	Sulfur,
}
CLOUD_COMPONENT_COUNT :: len(Cloud_Component)

// Fractions describe the materials visible at the top of the atmosphere, not
// bulk planetary chemistry. This lets presentation color what an observer can
// actually see while keeping the generated fact deterministic in game state.
Planet_Surface_Composition :: struct {
	fractions: [SURFACE_COMPONENT_COUNT]f64,
}

Planet_Cloud_Composition :: struct {
	fractions: [CLOUD_COMPONENT_COUNT]f64,
}

System_Planet :: struct {
	body:                   Planet,
	host:                   Orbital_Host,
	orbit:                  Orbital_Elements,
	flux_envelope:          Planet_Flux_Envelope,
	climate_history:        [MAX_PLANET_CLIMATE_SEGMENTS]Planet_Climate_History,
	climate_history_count:  int,
	kind:                   System_Planet_Kind,
	surface:                Planet_Surface_Composition,
	clouds:                 Planet_Cloud_Composition,
	geometric_albedo:       f64,
	moon_start:             int,
	moon_count:             int,
	mutual_hill_separation: f64,
}

planet_cloud_composition :: proc(
	kind: System_Planet_Kind,
	temperature_kelvin: f64,
	seed: u64,
) -> Planet_Cloud_Composition {
	state := seed ~ 0xe7037ed1a0b428db
	c: Planet_Cloud_Composition
	set :: proc(c: ^Planet_Cloud_Composition, component: Cloud_Component, value: f64) {
		c.fractions[int(component)] = max(value, 0)
	}
	switch kind {
	case .Rocky:
		// Thin rocky atmospheres still form water clouds where moisture survives;
		// hot examples gain a small sulfurous aerosol contribution.
		set(&c, .Water, planet_random_range(&state, .72, .96))
		set(
			&c,
			.Sulfur,
			temperature_kelvin > 380 ? planet_random_range(&state, .10, .34) : planet_random_range(&state, 0, .06),
		)
	case .Ocean:
		set(&c, .Water, planet_random_range(&state, .92, 1.0))
		set(&c, .Sulfur, planet_random_range(&state, 0, .025))
	case .Ice:
		set(&c, .Water, planet_random_range(&state, .86, .98))
		set(&c, .Methane, planet_random_range(&state, .01, .10))
		set(&c, .Ammonia, planet_random_range(&state, 0, .06))
	case .Ice_Giant:
		set(&c, .Methane, planet_random_range(&state, .46, .66))
		set(&c, .Ammonia, planet_random_range(&state, .18, .34))
		set(&c, .Water, planet_random_range(&state, .08, .22))
	case .Gas_Giant:
		set(&c, .Ammonia, planet_random_range(&state, .38, .58))
		set(&c, .Sulfur, planet_random_range(&state, .12, .30))
		set(&c, .Methane, planet_random_range(&state, .08, .22))
		set(&c, .Water, planet_random_range(&state, .06, .18))
	}
	total: f64
	for value in c.fractions do total += value
	if total > 0 do for &value in c.fractions do value /= total
	return c
}

planet_geometric_albedo :: proc(
	kind: System_Planet_Kind,
	surface: Planet_Surface_Composition,
) -> f64 {
	// Visible-light estimates for an unresolved disk. Solid surfaces use a
	// component-weighted reflectance; giant planets are governed by cloud tops.
	weights := [SURFACE_COMPONENT_COUNT]f64{.12, .18, .08, .65, .55, .04, .42, .58, .10}
	value: f64
	for fraction, i in surface.fractions do value += fraction * weights[i]
	if kind == .Gas_Giant do value = max(value, .42)
	if kind == .Ice_Giant do value = max(value, .38)
	return clamp(value, .04, .75)
}

planet_surface_composition :: proc(
	kind: System_Planet_Kind,
	temperature_kelvin: f64,
	seed: u64,
) -> Planet_Surface_Composition {
	state := seed ~ 0xa0761d6478bd642f
	c: Planet_Surface_Composition
	set :: proc(c: ^Planet_Surface_Composition, component: Surface_Component, value: f64) {
		c.fractions[int(component)] = max(value, 0)
	}
	switch kind {
	case .Rocky:
		set(&c, .Silicate, planet_random_range(&state, .52, .82))
		set(&c, .Iron_Oxide, planet_random_range(&state, .04, .34))
		set(
			&c,
			.Sulfur,
			temperature_kelvin > 400 ? planet_random_range(&state, .08, .24) : planet_random_range(&state, 0, .07),
		)
		set(&c, .Carbon, planet_random_range(&state, .02, .12))
		if temperature_kelvin < 270 do set(&c, .Water_Ice, planet_random_range(&state, .04, .28))
	case .Ocean:
		set(&c, .Liquid_Water, planet_random_range(&state, .62, .82))
		set(&c, .Silicate, planet_random_range(&state, .12, .28))
		set(&c, .Water_Ice, temperature_kelvin < 285 ? planet_random_range(&state, .02, .10) : 0)
		set(&c, .Iron_Oxide, planet_random_range(&state, 0, .04))
	case .Ice:
		set(&c, .Water_Ice, planet_random_range(&state, .60, .86))
		set(&c, .Silicate, planet_random_range(&state, .08, .24))
		set(&c, .Carbon, planet_random_range(&state, .02, .12))
		set(&c, .Methane, planet_random_range(&state, 0, .08))
	case .Ice_Giant:
		set(&c, .Methane, planet_random_range(&state, .48, .70))
		set(&c, .Ammonia, planet_random_range(&state, .14, .30))
		set(&c, .Water_Ice, planet_random_range(&state, .08, .22))
	case .Gas_Giant:
		set(&c, .Ammonia, planet_random_range(&state, .42, .66))
		set(&c, .Sulfur, planet_random_range(&state, .08, .28))
		set(&c, .Methane, planet_random_range(&state, .08, .24))
		set(&c, .Water_Ice, planet_random_range(&state, .02, .12))
	}
	total: f64
	for value in c.fractions do total += value
	if total > 0 do for &value in c.fractions do value /= total
	return c
}

Asteroid_Belt :: struct {
	host:                 Orbital_Host,
	orbit:                Orbital_Elements,
	inner_au:             f64,
	outer_au:             f64,
	estimated_mass_earth: f64,
	ice_rich:             bool,
	sample_start:         int,
	sample_count:         int,
}

Solar_System :: struct {
	model_version:                 u32,
	seed:                          u64,
	formation_epoch_billion_years: f64,
	present_age_billion_years:     f64,
	metallicity_dex:               f64,
	stars:                         [MAX_SYSTEM_STARS]System_Star,
	star_count:                    int,
	binary_bound:                  bool,
	initial_binary_orbit:          Orbital_Elements,
	binary_orbit:                  Orbital_Elements,
	events:                        [MAX_SYSTEM_EVENTS]System_Evolution_Event,
	event_count:                   int,
	frost_line_au:                 f64,
	planets:                       [MAX_SYSTEM_PLANETS]System_Planet,
	planet_count:                  int,
	moons:                         [MAX_SYSTEM_MOONS]Moon,
	moon_count:                    int,
	belts:                         [MAX_SYSTEM_BELTS]Asteroid_Belt,
	belt_count:                    int,
	asteroids:                     [MAX_SYSTEM_ASTEROIDS]Asteroid,
	asteroid_count:                int,
}

generate_main_sequence_star :: proc(seed: u64) -> System_Star {
	state := seed
	mass := math.pow(10.0, planet_random_range(&state, -0.70, 0.176))
	luminosity := mass < 0.43 ? 0.23 * math.pow(mass, 2.3) : math.pow(mass, 4)
	radius := math.pow(mass, 0.8)
	lifetime := 10 * mass / luminosity
	maximum_age := min(lifetime * 0.9, 12.5)
	age := planet_random_range(&state, 0.1, maximum_age)
	temperature := 5772 * math.pow(luminosity / (radius * radius), 0.25)
	class: Star_Class
	if temperature < 3900 {
		class = .M
	} else if temperature < 5200 {
		class = .K
	} else if temperature < 6000 {
		class = .G
	} else {
		class = .F
	}
	return {
		initial_mass_solar = mass,
		phase = .Main_Sequence,
		bound = true,
		profile = {
			mass_solar = mass,
			luminosity_solar = luminosity,
			radius_solar = radius,
			age_billion_years = age,
		},
		class = class,
		effective_temperature_k = temperature,
		main_sequence_lifetime_billion_years = lifetime,
	}
}

system_planet_mass_radius :: proc(
	state: ^u64,
	orbit, frost_line: f64,
) -> (
	f64,
	f64,
	System_Planet_Kind,
) {
	roll := planet_random_unit(state)
	mass, radius: f64
	kind: System_Planet_Kind
	if orbit < frost_line {
		mass = math.pow(10.0, planet_random_range(state, -0.8, 0.7))
		radius = mass < 1 ? math.pow(mass, 0.28) : math.pow(mass, 0.22)
		kind = roll < 0.18 ? .Ocean : .Rocky
	} else if roll < 0.25 {
		mass = math.pow(10.0, planet_random_range(state, -0.4, 0.8))
		radius = 1.15 * math.pow(mass, 0.28)
		kind = .Ice
	} else if roll < 0.68 {
		mass = math.pow(10.0, planet_random_range(state, 0.8, 1.65))
		radius = 3.9 * math.pow(mass / 17, 0.25)
		kind = .Ice_Giant
	} else {
		mass = math.pow(10.0, planet_random_range(state, 1.65, 3.0))
		radius = 11.2 * math.pow(mass / 318, -0.04)
		kind = .Gas_Giant
	}
	return mass, radius, kind
}

mutual_hill_separation :: proc(inner, outer: Planet, star_mass_solar: f64) -> f64 {
	mean_axis := (inner.inputs.semi_major_axis_au + outer.inputs.semi_major_axis_au) / 2
	hill :=
		mean_axis *
		math.pow(
			(inner.inputs.mass_earth + outer.inputs.mass_earth) / (3 * star_mass_solar * 332946),
			1.0 / 3.0,
		)
	return (outer.inputs.semi_major_axis_au - inner.inputs.semi_major_axis_au) / hill
}

append_system_moons :: proc(system: ^Solar_System, planet_index: int, state: ^u64) {
	p := &system.planets[planet_index]
	p.moon_start = system.moon_count
	target := p.kind == .Gas_Giant ? 7 : p.kind == .Ice_Giant ? 5 : int(planet_rng_next(state) % 3)
	host_radius_km := p.body.inputs.radius_earth * 6371
	orbit := host_radius_km * planet_random_range(state, 3.5, 5.5)
	stable_outer := p.body.hill_radius_au * 149597870.7 * 0.42
	for _ in 0 ..< target {
		if system.moon_count >= MAX_SYSTEM_MOONS || orbit >= stable_outer do break
		max_mass_lunar := p.body.inputs.mass_earth * 0.005 / 0.0123
		mass := min(math.pow(10.0, planet_random_range(state, -3, 0.1)), max_mass_lunar)
		radius := math.pow(mass, 0.32)
		moon, ok := evaluate_moon(
			planet_rng_next(state),
			p.body,
			{
				mass_lunar = mass,
				radius_lunar = radius,
				semi_major_axis_km = orbit,
				eccentricity = planet_random_range(state, 0, 0.06),
				bond_albedo = planet_random_range(state, 0.04, 0.7),
				initial_rotation_hours = planet_random_range(state, 10, 100),
			},
		)
		if ok && moon.outside_roche_limit && moon.inside_stable_prograde_zone {
			moon.host_planet_index = planet_index
			moon.host = {
				body = {kind = .Planet, index = planet_index},
			}
			moon.orbit = {
				semi_major_axis_au   = moon.inputs.semi_major_axis_km / 149597870.7,
				eccentricity         = moon.inputs.eccentricity,
				mean_anomaly_radians = planet_random_range(state, 0, 2 * math.PI),
			}
			system.moons[system.moon_count] = moon
			system.moon_count += 1
			p.moon_count += 1
		}
		orbit *= planet_random_range(state, 1.65, 2.4)
	}
}

append_asteroid_belt :: proc(
	system: ^Solar_System,
	center, width: f64,
	ice_rich: bool,
	state: ^u64,
) {
	if system.belt_count >= MAX_SYSTEM_BELTS do return
	belt := &system.belts[system.belt_count]
	belt.inner_au = center * (1 - width)
	belt.outer_au = center * (1 + width)
	belt.host = {
		body = {kind = .Star, index = 0},
	}
	belt.orbit = {
		semi_major_axis_au = center,
		eccentricity       = 0,
	}
	belt.estimated_mass_earth = math.pow(10.0, planet_random_range(state, -5, -2))
	belt.ice_rich = ice_rich
	belt.sample_start = system.asteroid_count
	for _ in 0 ..< 4 {
		if system.asteroid_count >= MAX_SYSTEM_ASTEROIDS do break
		kind :=
			ice_rich ? Asteroid_Composition.Icy : Asteroid_Composition(planet_rng_next(state) % 3)
		density, albedo := asteroid_composition_density(kind, state)
		a, ok := evaluate_asteroid(
			planet_rng_next(state),
			system.stars[0].profile,
			{
				diameter_km = math.pow(10.0, planet_random_range(state, -1, 2.5)),
				density_g_cm3 = density,
				semi_major_axis_au = planet_random_range(state, belt.inner_au, belt.outer_au),
				eccentricity = planet_random_range(state, 0, 0.25),
				inclination_degrees = planet_random_range(state, 0, 18),
				bond_albedo = albedo,
				rotation_period_hours = math.pow(10.0, planet_random_range(state, 0.35, 2)),
				impact_velocity_km_s = planet_random_range(state, 5, 30),
				composition = kind,
			},
		)
		if ok {
			a.host = {
				body = {kind = .Star, index = 0},
			}
			a.orbit = {
				semi_major_axis_au   = a.inputs.semi_major_axis_au,
				eccentricity         = a.inputs.eccentricity,
				inclination_radians  = a.inputs.inclination_degrees * math.PI / 180,
				mean_anomaly_radians = planet_random_range(state, 0, 2 * math.PI),
			}
			system.asteroids[system.asteroid_count] = a
			system.asteroid_count += 1
			belt.sample_count += 1
		}
	}
	system.belt_count += 1
}

generate_solar_system_around :: proc(seed: u64, star: System_Star) -> (Solar_System, bool) {
	if star.profile.mass_solar <= 0 || star.profile.luminosity_solar <= 0 || star.profile.radius_solar <= 0 do return {}, false
	system := Solar_System {
		model_version             = STELLAR_SYSTEM_MODEL_VERSION,
		seed                      = seed,
		star_count                = 1,
		present_age_billion_years = star.profile.age_billion_years,
	}
	system.stars[0] = star
	system.frost_line_au = 2.7 * math.sqrt(star.profile.luminosity_solar)
	state := seed ~ 0xd1b54a32d192ed03
	target := 4 + int(planet_rng_next(&state) % 7)
	orbit :=
		max(0.025, 0.05 * math.sqrt(star.profile.luminosity_solar)) *
		planet_random_range(&state, 0.75, 1.4)
	for i in 0 ..< target {
		if i > 0 do orbit *= planet_random_range(&state, 1.45, 2.15)
		mass, radius, kind := system_planet_mass_radius(&state, orbit, system.frost_line_au)
		if i > 0 {
			for _ in 0 ..< 24 {
				probe, _ := evaluate_planet(
					0,
					star.profile,
					{
						mass_earth = mass,
						radius_earth = radius,
						semi_major_axis_au = orbit,
						eccentricity = 0,
						bond_albedo = 0.3,
						initial_rotation_hours = 24,
					},
				)
				if mutual_hill_separation(system.planets[i - 1].body, probe, star.profile.mass_solar) >= 9 do break
				orbit *= 1.10
			}
		}
		if orbit > 60 do break
		albedo :=
			kind == .Gas_Giant ? planet_random_range(&state, 0.25, 0.55) : kind == .Ice_Giant ? planet_random_range(&state, 0.25, 0.5) : planet_random_range(&state, 0.08, 0.6)
		greenhouse := kind == .Rocky || kind == .Ocean ? planet_random_range(&state, 0, 70) : 0
		body, ok := evaluate_planet(
			planet_rng_next(&state),
			star.profile,
			{
				mass_earth = mass,
				radius_earth = radius,
				semi_major_axis_au = orbit,
				eccentricity = planet_random_range(&state, 0, 0.16),
				bond_albedo = albedo,
				greenhouse_warming_k = greenhouse,
				initial_rotation_hours = planet_random_range(&state, 7, 80),
			},
		)
		if !ok do continue
		surface := planet_surface_composition(kind, body.surface_temperature_k, body.seed)
		clouds := planet_cloud_composition(kind, body.surface_temperature_k, body.seed)
		system.planets[system.planet_count] = {
			body = body,
			host = {body = {kind = .Star, index = 0}},
			orbit = {
				semi_major_axis_au = body.inputs.semi_major_axis_au,
				eccentricity = body.inputs.eccentricity,
				mean_anomaly_radians = planet_random_range(&state, 0, 2 * math.PI),
			},
			kind = kind,
			surface = surface,
			clouds = clouds,
			geometric_albedo = planet_geometric_albedo(kind, surface),
		}
		if system.planet_count > 0 {
			system.planets[system.planet_count].mutual_hill_separation = mutual_hill_separation(
				system.planets[system.planet_count - 1].body,
				body,
				star.profile.mass_solar,
			)
		}
		system.planet_count += 1
	}
	for i in 0 ..< system.planet_count do append_system_moons(&system, i, &state)
	for i in 0 ..< system.planet_count {system.planets[i].flux_envelope = system_planet_flux_envelope(&system, i); f := system.planets[i].flux_envelope.mean_earth; system.planets[i].body.stellar_flux_earth = f; system.planets[i].climate_history[0] = {
			start_age_billion_years = 0,
			end_age_billion_years   = system.present_age_billion_years,
			mean_flux_earth         = f,
			minimum_flux_earth      = system.planets[i].flux_envelope.minimum_earth,
			maximum_flux_earth      = system.planets[i].flux_envelope.maximum_earth,
			climate                 = system.planets[i].body.climate,
			temperate               = f >= .35 && f <= 1.10,
		}; system.planets[i].climate_history_count = 1}

	// Belts occupy dynamically broad gaps rather than arbitrary planet-crossing bands.
	best_ratio, belt_center: f64
	for i in 1 ..< system.planet_count {
		ratio :=
			system.planets[i].body.inputs.semi_major_axis_au /
			system.planets[i - 1].body.inputs.semi_major_axis_au
		if ratio > best_ratio {
			best_ratio = ratio
			belt_center = math.sqrt(
				system.planets[i].body.inputs.semi_major_axis_au *
				system.planets[i - 1].body.inputs.semi_major_axis_au,
			)
		}
	}
	if best_ratio >= 1.8 do append_asteroid_belt(&system, belt_center, 0.12, belt_center >= system.frost_line_au, &state)
	if system.planet_count > 0 {
		outer := system.planets[system.planet_count - 1].body.inputs.semi_major_axis_au * 1.65
		if outer < 100 do append_asteroid_belt(&system, outer, 0.18, true, &state)
	}
	return system, system.planet_count > 0
}

generate_solar_system :: proc(seed: u64) -> Solar_System {
	stellar := generate_stellar_population(seed, 4.6, 0)
	star := stellar.stars[0]
	system, _ := generate_solar_system_around(seed, star)
	apply_stellar_architecture(&system, &stellar)
	return system
}

system_effective_host_profile :: proc(system: ^Solar_System, host: Orbital_Host) -> Star_Profile {
	if host.body.kind == .Star && host.body.index >= 0 && host.body.index < system.star_count do return system.stars[host.body.index].profile
	if host.body.kind == .Barycenter {
		p := Star_Profile {
			age_billion_years = system.present_age_billion_years,
		}
		for s in system.stars[:system.star_count] {if !s.bound do continue; p.mass_solar += s.profile.mass_solar; p.luminosity_solar += s.profile.luminosity_solar; p.radius_solar = max(p.radius_solar, s.profile.radius_solar)}
		return p
	}
	return {}
}

apply_stellar_architecture :: proc(system, stellar: ^Solar_System) {
	system.model_version =
		stellar.model_version; system.present_age_billion_years = stellar.present_age_billion_years; system.metallicity_dex = stellar.metallicity_dex; system.stars = stellar.stars; system.star_count = stellar.star_count; system.binary_bound = stellar.binary_bound; system.initial_binary_orbit = stellar.initial_binary_orbit; system.binary_orbit = stellar.binary_orbit; system.events = stellar.events; system.event_count = stellar.event_count
	state := system.seed ~ 0x6f72626974616c
	limits := system_stability_limits(system)
	initial_system := system^; initial_system.binary_bound = initial_system.star_count == 2; initial_system.binary_orbit = initial_system.initial_binary_orbit; for &star in initial_system.stars[:initial_system.star_count] {star.profile.mass_solar = star.initial_mass_solar}
	initial_limits := system_stability_limits(&initial_system)
	combined_lum: f64; for s in system.stars[:system.star_count] do if s.bound do combined_lum += s.profile.luminosity_solar
	system.frost_line_au = 2.7 * math.sqrt(max(combined_lum, 1.0e-9))
	for &p, i in system.planets[:system.planet_count] {
		host := Orbital_Host {
			body = {kind = .Star, index = 0},
		}; axis := p.body.inputs.semi_major_axis_au
		if system.star_count == 2 && system.binary_bound {
			mode := i % 3
			if mode == 0 {host = {
					body = {kind = .Star, index = 0},
				}; axis = min(
					axis,
					max(initial_limits.circumprimary_outer_au * .72, .015),
				); axis *= system.stars[0].initial_mass_solar / max(system.stars[0].profile.mass_solar, .01)
			} else if mode == 1 {host = {
					body = {kind = .Star, index = 1},
				}; axis = min(
					axis,
					max(initial_limits.circumsecondary_outer_au * .72, .015),
				); axis *= system.stars[1].initial_mass_solar / max(system.stars[1].profile.mass_solar, .01)
			} else {host = {
					body = {kind = .Barycenter, index = 0},
				}; axis = max(
					axis,
					initial_limits.circumbinary_inner_au * 1.12,
				); initial_mass := system.stars[0].initial_mass_solar + system.stars[1].initial_mass_solar; current_mass := system.stars[0].profile.mass_solar + system.stars[1].profile.mass_solar; axis *= initial_mass / max(current_mass, .01)}
		}
		profile := system_effective_host_profile(
			system,
			host,
		); inputs := p.body.inputs; initial_axis := inputs.semi_major_axis_au; inputs.semi_major_axis_au = max(axis, .01)
		body, ok := evaluate_planet(p.body.seed, profile, inputs); if !ok do continue
		p.body = body; p.host = host; p.orbit = {
			semi_major_axis_au         = inputs.semi_major_axis_au,
			eccentricity               = inputs.eccentricity,
			inclination_radians        = planet_random_range(&state, 0, .045),
			ascending_node_radians     = planet_random_range(&state, 0, 2 * math.PI),
			argument_periapsis_radians = planet_random_range(&state, 0, 2 * math.PI),
			mean_anomaly_radians       = planet_random_range(&state, 0, 2 * math.PI),
		}
		if initial_axis != inputs.semi_major_axis_au do append_system_event(system, {age_billion_years = system.present_age_billion_years, kind = .Planet_Orbit_Changed, primary = {kind = .Planet, index = i}, pre_axis_au = initial_axis, post_axis_au = inputs.semi_major_axis_au})
	}
	// Apply present-day engulfment and dynamical survival after all stellar
	// architecture changes, then compact planets and their satellite indices.
	planet_map: [MAX_SYSTEM_PLANETS]int; for &v in planet_map do v = -1
	survivors: [MAX_SYSTEM_PLANETS]System_Planet; survivor_count := 0
	for p, i in system.planets[:system.planet_count] {
		survives, engulfed := true, false
		if p.host.body.kind ==
		   .Star {radius_au := system.stars[p.host.body.index].profile.radius_solar * .00465047; engulfed = p.orbit.semi_major_axis_au * (1 - p.orbit.eccentricity) <= radius_au * 1.05; survives = !engulfed}
		// Stellar evolution can compress several pre-evolution orbits onto the
		// same stability boundary. Retain only mutually Hill-stable planets that
		// orbit the same host; planets around different binary hosts are independent.
		if survives {for prior in survivors[:survivor_count] {
				same_host :=
					prior.host.body.kind == p.host.body.kind &&
					prior.host.body.index == p.host.body.index
				if !same_host do continue
				host_mass := system_effective_host_profile(system, p.host).mass_solar
				if p.body.inputs.semi_major_axis_au <= prior.body.inputs.semi_major_axis_au ||
				   mutual_hill_separation(prior.body, p.body, max(host_mass, .01)) <
					   9 {survives = false; break}
			}}
		if survives &&
		   system_planet_orbit_stable(
			   system,
			   i,
		   ) {planet_map[i] = survivor_count; survivors[survivor_count] = p; survivor_count += 1} else {append_system_event(system, {age_billion_years = system.present_age_billion_years, kind = engulfed ? .Planet_Engulfed : .Planet_Ejected, primary = {kind = .Planet, index = i}, pre_axis_au = p.orbit.semi_major_axis_au})}
	}
	if survivor_count !=
	   system.planet_count {system.planets = survivors; system.planet_count = survivor_count; new_moons: [MAX_SYSTEM_MOONS]Moon; new_moon_count := 0; for moon in system.moons[:system.moon_count] {mapped := moon.host_planet_index >= 0 && moon.host_planet_index < MAX_SYSTEM_PLANETS ? planet_map[moon.host_planet_index] : -1; if mapped < 0 do continue; remapped := moon; remapped.host_planet_index = mapped; remapped.host = {
				body = {kind = .Planet, index = mapped},
			}; new_moons[new_moon_count] =
				remapped; new_moon_count += 1}; system.moons = new_moons; system.moon_count = new_moon_count; for &p in system.planets[:system.planet_count] {p.moon_start = 0; p.moon_count = 0}; for moon in system.moons[:system.moon_count] do system.planets[moon.host_planet_index].moon_count += 1}
	for &belt, i in system.belts[:system.belt_count] {if system.star_count == 2 && system.binary_bound && i % 3 == 2 {belt.host = {
				body = {kind = .Barycenter},
			}; belt.orbit.semi_major_axis_au = max(
				belt.orbit.semi_major_axis_au,
				limits.circumbinary_inner_au * 1.15,
			)} else {host_index := system.star_count == 2 ? i % 2 : 0; belt.host = {
				body = {kind = .Star, index = host_index},
			}}}
	for &a, i in system.asteroids[:system.asteroid_count] {if system.star_count == 2 && system.binary_bound && i % 3 == 2 {a.host = {
				body = {kind = .Barycenter},
			}; a.orbit.semi_major_axis_au = max(
				a.orbit.semi_major_axis_au,
				limits.circumbinary_inner_au * 1.15,
			)} else {host_index := system.star_count == 2 ? i % 2 : 0; a.host = {
				body = {kind = .Star, index = host_index},
			}}}
	for &p, i in system.planets[:system.planet_count] {
		p.flux_envelope = system_planet_flux_envelope(
			system,
			i,
		); p.body.stellar_flux_earth = p.flux_envelope.mean_earth; p.body.in_habitable_flux_band = p.flux_envelope.maximum_greenhouse_index >= 1 && p.flux_envelope.runaway_greenhouse_index <= 1
		p.climate_history_count = 0
		start: f64
		for event in system.events[:system.event_count] {if p.climate_history_count >= MAX_PLANET_CLIMATE_SEGMENTS - 1 do break; if event.kind == .Wind_Mass_Loss || event.kind == .Mass_Transfer || event.kind == .Common_Envelope || event.kind == .Supernova || event.kind == .Stellar_Merger {fraction := clamp(event.age_billion_years / max(system.present_age_billion_years, 1.0e-9), 0, 1); mean := p.flux_envelope.mean_earth * (.7 + .3 * fraction); climate := mean < .35 ? Climate_Band.Frozen : mean <= 1.1 ? .Temperate : mean <= 2 ? .Hot : .Infernal; p.climate_history[p.climate_history_count] = {
					start_age_billion_years = start,
					end_age_billion_years   = event.age_billion_years,
					mean_flux_earth         = mean,
					minimum_flux_earth      = p.flux_envelope.minimum_earth,
					maximum_flux_earth      = p.flux_envelope.maximum_earth,
					climate                 = climate,
					temperate               = climate == .Temperate,
				}; p.climate_history_count += 1; start = event.age_billion_years}}
		p.climate_history[p.climate_history_count] = {
			start_age_billion_years = start,
			end_age_billion_years   = system.present_age_billion_years,
			mean_flux_earth         = p.flux_envelope.mean_earth,
			minimum_flux_earth      = p.flux_envelope.minimum_earth,
			maximum_flux_earth      = p.flux_envelope.maximum_earth,
			climate                 = p.body.climate,
			temperate               = p.body.in_habitable_flux_band,
		}; p.climate_history_count += 1
	}
}

generate_solar_system_population :: proc(
	seed: u64,
	age_gyr, metallicity_dex: f64,
) -> (
	Solar_System,
	bool,
) {
	stellar := generate_stellar_population(seed, age_gyr, metallicity_dex)
	formation_star := evolve_star_to_age(
		stellar.stars[0].initial_mass_solar,
		metallicity_dex,
		max(stellar.stars[0].main_sequence_lifetime_billion_years * .01, .001),
	)
	base, _ := generate_solar_system_around(
		seed,
		formation_star,
	); apply_stellar_architecture(&base, &stellar)
	return base, system_validate(&base)
}
