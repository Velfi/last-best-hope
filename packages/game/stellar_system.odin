package game

import "core:math"

MAX_SYSTEM_STARS :: 2
MAX_SYSTEM_EVENTS :: 32
MAX_PLANET_CLIMATE_SEGMENTS :: 12
STELLAR_SYSTEM_MODEL_VERSION :: u32(2)

Stellar_Phase :: enum {
	Protostar,
	Main_Sequence,
	Hertzsprung_Gap,
	Red_Giant,
	Core_Helium_Burning,
	Asymptotic_Giant,
	Stripped_Helium,
	White_Dwarf,
	Neutron_Star,
	Black_Hole,
	Merged,
}

Black_Hole_Accretion_Kind :: enum {
	Dormant,
	Wind_Fed,
	Transfer_Disk,
	Thick_Flow,
}

Black_Hole_Accretion :: struct {
	kind:                        Black_Hole_Accretion_Kind,
	donor_index:                 int,
	roche_lobe_fill:             f64,
	eddington_fraction:          f64,
	disk_outer_radius_km:        f64,
	view_cosine:                 f64,
	view_position_angle_radians: f64,
}

Celestial_Body_Kind :: enum {
	None,
	Barycenter,
	Star,
	Planet,
	Moon,
	Asteroid,
	Central_Black_Hole,
}
Celestial_Body_Ref :: struct {
	kind:  Celestial_Body_Kind,
	index: int,
}
Orbital_Host :: struct {
	body: Celestial_Body_Ref,
}

Orbital_Elements :: struct {
	semi_major_axis_au:         f64,
	eccentricity:               f64,
	inclination_radians:        f64,
	ascending_node_radians:     f64,
	argument_periapsis_radians: f64,
	mean_anomaly_radians:       f64,
	epoch_days:                 f64,
}

System_Vec3 :: [3]f64
System_Body_State :: struct {
	position_au, velocity_au_day: System_Vec3,
}

System_Star :: struct {
	profile:                              Star_Profile,
	initial_mass_solar:                   f64,
	metallicity_dex:                      f64,
	class:                                Star_Class,
	phase:                                Stellar_Phase,
	effective_temperature_k:              f64,
	main_sequence_lifetime_billion_years: f64,
	core_mass_solar:                      f64,
	spin_period_days:                     f64,
	bound:                                bool,
}

System_Event_Kind :: enum {
	Stellar_Phase_Changed,
	Wind_Mass_Loss,
	Tidal_Circularization,
	Mass_Transfer,
	Common_Envelope,
	Supernova,
	Binary_Disrupted,
	Stellar_Merger,
	Planet_Orbit_Changed,
	Planet_Engulfed,
	Planet_Ejected,
	Climate_Changed,
}

System_Evolution_Event :: struct {
	age_billion_years: f64,
	kind:              System_Event_Kind,
	primary:           Celestial_Body_Ref,
	secondary:         Celestial_Body_Ref,
	pre_mass_solar:    f64,
	post_mass_solar:   f64,
	pre_axis_au:       f64,
	post_axis_au:      f64,
}

Planet_Flux_Envelope :: struct {
	mean_earth, minimum_earth, maximum_earth, variance_earth2, eclipse_minimum_earth: f64,
	runaway_greenhouse_index, maximum_greenhouse_index:                               f64,
}

Planet_Climate_History :: struct {
	start_age_billion_years, end_age_billion_years:          f64,
	mean_flux_earth, minimum_flux_earth, maximum_flux_earth: f64,
	climate:                                                 Climate_Band,
	temperate:                                               bool,
}

System_Stability_Limits :: struct {
	circumprimary_outer_au:   f64,
	circumsecondary_outer_au: f64,
	circumbinary_inner_au:    f64,
}

system_ref_valid :: proc(system: ^Solar_System, ref: Celestial_Body_Ref) -> bool {
	switch ref.kind {
	case .Barycenter:
		return system.star_count == 2
	case .Star:
		return ref.index >= 0 && ref.index < system.star_count
	case .Planet:
		return ref.index >= 0 && ref.index < system.planet_count
	case .Moon:
		return ref.index >= 0 && ref.index < system.moon_count
	case .Asteroid:
		return ref.index >= 0 && ref.index < system.asteroid_count
	case .None, .Central_Black_Hole:
	}
	return false
}

orbital_elements_valid :: proc(o: Orbital_Elements) -> bool {
	return(
		o.semi_major_axis_au > 0 &&
		o.semi_major_axis_au < 1.0e6 &&
		o.eccentricity >= 0 &&
		o.eccentricity < 1 &&
		o.inclination_radians == o.inclination_radians &&
		o.ascending_node_radians == o.ascending_node_radians &&
		o.argument_periapsis_radians == o.argument_periapsis_radians &&
		o.mean_anomaly_radians == o.mean_anomaly_radians \
	)
}

system_host_mass :: proc(system: ^Solar_System, host: Orbital_Host) -> f64 {
	#partial switch host.body.kind {
	case .Star:
		if host.body.index >= 0 && host.body.index < system.star_count do return system.stars[host.body.index].profile.mass_solar
	case .Barycenter:
		mass: f64
		for star in system.stars[:system.star_count] do if star.bound do mass += star.profile.mass_solar
		return mass
	case .Planet:
		if host.body.index >= 0 && host.body.index < system.planet_count do return system.planets[host.body.index].body.inputs.mass_earth / 332946.0
	case:
	}
	return 0
}

solve_kepler :: proc(mean_anomaly, eccentricity: f64) -> f64 {
	m := math.mod(mean_anomaly, 2 * math.PI)
	if m < 0 do m += 2 * math.PI
	e := eccentricity < .8 ? m : math.PI
	for _ in 0 ..< 12 {
		f := e - eccentricity * math.sin(e) - m
		d := 1 - eccentricity * math.cos(e)
		e -= f / max(d, 1.0e-12)
	}
	return e
}

orbit_relative_state :: proc(
	elements: Orbital_Elements,
	host_mass_solar, epoch_days: f64,
) -> System_Body_State {
	if !orbital_elements_valid(elements) || host_mass_solar <= 0 do return {}
	period_days := 365.256 * math.sqrt(math.pow(elements.semi_major_axis_au, 3) / host_mass_solar)
	n := 2 * math.PI / period_days
	mean := elements.mean_anomaly_radians + n * (epoch_days - elements.epoch_days)
	eccentric := solve_kepler(mean, elements.eccentricity)
	x := elements.semi_major_axis_au * (math.cos(eccentric) - elements.eccentricity)
	y :=
		elements.semi_major_axis_au *
		math.sqrt(1 - elements.eccentricity * elements.eccentricity) *
		math.sin(eccentric)
	ded := n / max(1 - elements.eccentricity * math.cos(eccentric), 1.0e-12)
	vx := -elements.semi_major_axis_au * math.sin(eccentric) * ded
	vy :=
		elements.semi_major_axis_au *
		math.sqrt(1 - elements.eccentricity * elements.eccentricity) *
		math.cos(eccentric) *
		ded
	co, so := math.cos(elements.ascending_node_radians), math.sin(elements.ascending_node_radians)
	ci, si := math.cos(elements.inclination_radians), math.sin(elements.inclination_radians)
	cw, sw :=
		math.cos(elements.argument_periapsis_radians),
		math.sin(elements.argument_periapsis_radians)
	transform :: proc(x, y, co, so, ci, si, cw, sw: f64) -> System_Vec3 {
		return {
			(co * cw - so * sw * ci) * x + (-co * sw - so * cw * ci) * y,
			(so * cw + co * sw * ci) * x + (-so * sw + co * cw * ci) * y,
			sw * si * x + cw * si * y,
		}
	}
	return {
		position_au = transform(x, y, co, so, ci, si, cw, sw),
		velocity_au_day = transform(vx, vy, co, so, ci, si, cw, sw),
	}
}

system_stability_limits :: proc(system: ^Solar_System) -> System_Stability_Limits {
	if system.star_count < 2 || !system.binary_bound do return {circumprimary_outer_au = 1.0e6, circumsecondary_outer_au = 1.0e6}
	a := system.binary_orbit.semi_major_axis_au
	e := system.binary_orbit.eccentricity
	m1, m2 := system.stars[0].profile.mass_solar, system.stars[1].profile.mass_solar
	mu := m2 / max(m1 + m2, 1.0e-12)
	// Quarles et al. (2018, 2020) updated empirical S/P-type boundaries.
	s_primary :=
		a * (.501 - .435 * mu - .668 * e + .644 * mu * e + .152 * e * e - .196 * mu * e * e)
	mu2 := 1 - mu
	s_secondary :=
		a * (.501 - .435 * mu2 - .668 * e + .644 * mu2 * e + .152 * e * e - .196 * mu2 * e * e)
	p :=
		a *
		(1.48 +
				3.92 * e -
				1.41 * e * e +
				5.14 * mu +
				.33 * e * mu -
				7.95 * mu * mu +
				4.89 * e * e * mu * mu)
	return {max(s_primary, 0), max(s_secondary, 0), max(p, 0)}
}

system_star_barycentric_state :: proc(
	system: ^Solar_System,
	index: int,
	epoch_days: f64,
) -> System_Body_State {
	if system.star_count < 2 || !system.binary_bound || index < 0 || index > 1 do return {}
	rel := orbit_relative_state(
		system.binary_orbit,
		system.stars[0].profile.mass_solar + system.stars[1].profile.mass_solar,
		epoch_days,
	)
	other := 1 - index
	factor :=
		system.stars[other].profile.mass_solar /
		max(system.stars[0].profile.mass_solar + system.stars[1].profile.mass_solar, 1.0e-12)
	if index == 0 do factor = -factor
	for i in 0 ..< 3 {rel.position_au[i] *= factor; rel.velocity_au_day[i] *= factor}
	return rel
}

system_body_state_at :: proc(
	system: ^Solar_System,
	ref: Celestial_Body_Ref,
	epoch_days: f64,
) -> (
	System_Body_State,
	bool,
) {
	if !system_ref_valid(system, ref) do return {}, false
	#partial switch ref.kind {
	case .Barycenter:
		return {}, true
	case .Star:
		return system_star_barycentric_state(system, ref.index, epoch_days), true
	case .Planet:
		planet := &system.planets[ref.index]
		secular := planet.orbit
		if system.star_count == 2 && system.binary_bound {
			mass_total := system.stars[0].profile.mass_solar + system.stars[1].profile.mass_solar
			if planet.host.body.kind == .Barycenter {
				ratio :=
					system.binary_orbit.semi_major_axis_au /
					max(
						planet.orbit.semi_major_axis_au,
						1.0e-9,
					); forced := 1.25 * abs(system.stars[0].profile.mass_solar - system.stars[1].profile.mass_solar) / max(mass_total, 1.0e-9) * ratio * system.binary_orbit.eccentricity
				period :=
					365.256 *
					math.sqrt(
						math.pow(planet.orbit.semi_major_axis_au, 3) / mass_total,
					); precession := .75 * 2 * math.PI / period * (system.stars[0].profile.mass_solar * system.stars[1].profile.mass_solar / (mass_total * mass_total)) * ratio * ratio
				secular.eccentricity = clamp(
					planet.orbit.eccentricity +
					forced * math.cos(precession * (epoch_days - planet.orbit.epoch_days)),
					0,
					.8,
				); secular.argument_periapsis_radians += precession * (epoch_days - planet.orbit.epoch_days); secular.ascending_node_radians -= precession * (epoch_days - planet.orbit.epoch_days)
			} else if planet.host.body.kind == .Star {
				companion :=
					1 -
					planet.host.body.index; ratio := planet.orbit.semi_major_axis_au / max(system.binary_orbit.semi_major_axis_au, 1.0e-9); period := 365.256 * math.sqrt(math.pow(planet.orbit.semi_major_axis_au, 3) / max(system.stars[planet.host.body.index].profile.mass_solar, 1.0e-9)); precession := .75 * 2 * math.PI / period * (system.stars[companion].profile.mass_solar / mass_total) * ratio * ratio * ratio / math.pow(max(1 - system.binary_orbit.eccentricity * system.binary_orbit.eccentricity, .01), 1.5); secular.argument_periapsis_radians += precession * (epoch_days - planet.orbit.epoch_days)
			}
		}
		rel := orbit_relative_state(secular, system_host_mass(system, planet.host), epoch_days)
		if planet.host.body.kind ==
		   .Star {base, _ := system_body_state_at(system, planet.host.body, epoch_days); for i in 0 ..< 3 {rel.position_au[i] += base.position_au[i]; rel.velocity_au_day[i] += base.velocity_au_day[i]}}
		return rel, true
	case .Moon:
		moon := &system.moons[ref.index]
		host := Celestial_Body_Ref {
			kind  = .Planet,
			index = moon.host_planet_index,
		}
		base, ok := system_body_state_at(system, host, epoch_days); if !ok do return {}, false
		elements := moon.orbit
		rel := orbit_relative_state(elements, system_host_mass(system, {body = host}), epoch_days)
		for i in 0 ..< 3 {rel.position_au[i] += base.position_au[i]; rel.velocity_au_day[i] += base.velocity_au_day[i]}
		return rel, true
	case .Asteroid:
		a := &system.asteroids[ref.index]
		rel := orbit_relative_state(a.orbit, system_host_mass(system, a.host), epoch_days)
		if a.host.body.kind ==
		   .Star {base, _ := system_body_state_at(system, a.host.body, epoch_days); for i in 0 ..< 3 {rel.position_au[i] += base.position_au[i]; rel.velocity_au_day[i] += base.velocity_au_day[i]}}
		return rel, true
	case:
	}
	return {}, false
}

system_relative_state_at :: proc(
	system: ^Solar_System,
	body: Celestial_Body_Ref,
	host: Orbital_Host,
	epoch_days: f64,
) -> (
	System_Body_State,
	bool,
) {
	a, ok := system_body_state_at(system, body, epoch_days); if !ok do return {}, false
	b, host_ok := system_body_state_at(
		system,
		host.body,
		epoch_days,
	); if host.body.kind == .Barycenter do host_ok = true
	if !host_ok do return {}, false
	for i in 0 ..< 3 {a.position_au[i] -= b.position_au[i]; a.velocity_au_day[i] -= b.velocity_au_day[i]}
	return a, true
}

system_planet_flux_at :: proc(system: ^Solar_System, planet_index: int, epoch_days: f64) -> f64 {
	if planet_index < 0 || planet_index >= system.planet_count do return 0
	p, ok := system_body_state_at(
		system,
		{kind = .Planet, index = planet_index},
		epoch_days,
	); if !ok do return 0
	flux: f64
	for star, i in system.stars[:system.star_count] {
		if !star.bound || star.profile.luminosity_solar <= 0 do continue
		s, _ := system_body_state_at(system, {kind = .Star, index = i}, epoch_days)
		dx, dy, dz :=
			p.position_au[0] -
			s.position_au[0],
			p.position_au[1] -
			s.position_au[1],
			p.position_au[2] -
			s.position_au[2]
		flux += star.profile.luminosity_solar / max(dx * dx + dy * dy + dz * dz, 1.0e-12)
	}
	return flux
}

kopparapu_effective_flux :: proc(
	temperature_k: f64,
	inner: bool,
	planet_mass_earth: f64 = 1,
) -> f64 {
	t := clamp(temperature_k, 2600, 7200) - 5780
	if inner {
		// Runaway-greenhouse coefficients; the mass correction follows the
		// 0.1, 1, and 5 Earth-mass ordering in Kopparapu et al. (2014).
		base :=
			1.107 +
			1.332e-4 * t +
			1.58e-8 * t * t -
			8.308e-12 * t * t * t -
			1.931e-15 * t * t * t * t
		mass_factor := planet_mass_earth < .5 ? .92 : planet_mass_earth > 2 ? 1.07 : 1.0
		return base * mass_factor
	}
	return(
		.356 +
		6.171e-5 * t +
		1.698e-9 * t * t -
		3.198e-12 * t * t * t -
		5.575e-16 * t * t * t * t \
	)
}

system_planet_habitable_indices_at :: proc(
	system: ^Solar_System,
	planet_index: int,
	epoch_days: f64,
) -> (
	inner, outer: f64,
) {
	if planet_index < 0 || planet_index >= system.planet_count do return
	p, ok := system_body_state_at(
		system,
		{kind = .Planet, index = planet_index},
		epoch_days,
	); if !ok do return
	mass := system.planets[planet_index].body.inputs.mass_earth
	for star, i in system.stars[:system.star_count] {if !star.bound || star.profile.luminosity_solar <= 0 do continue; s, _ := system_body_state_at(system, {kind = .Star, index = i}, epoch_days); d2: f64; for axis in 0 ..< 3 {d := p.position_au[axis] - s.position_au[axis]; d2 += d * d}; flux := star.profile.luminosity_solar / max(d2, 1.0e-12); inner += flux / kopparapu_effective_flux(star.effective_temperature_k, true, mass); outer += flux / kopparapu_effective_flux(star.effective_temperature_k, false, mass)}
	return
}

system_planet_flux_envelope :: proc(
	system: ^Solar_System,
	planet_index: int,
) -> Planet_Flux_Envelope {
	result: Planet_Flux_Envelope; result.minimum_earth = 1.0e30
	for sample in 0 ..< 256 {
		t := f64(sample) * system.planets[planet_index].body.orbital_period_days / 256
		v := system_planet_flux_at(
			system,
			planet_index,
			t,
		); inner, outer := system_planet_habitable_indices_at(system, planet_index, t); result.mean_earth += v; result.variance_earth2 += v * v; result.minimum_earth = min(result.minimum_earth, v); result.maximum_earth = max(result.maximum_earth, v); result.runaway_greenhouse_index += inner; result.maximum_greenhouse_index += outer
	}
	result.mean_earth /= 256; result.runaway_greenhouse_index /= 256; result.maximum_greenhouse_index /= 256; result.variance_earth2 = max(result.variance_earth2 / 256 - result.mean_earth * result.mean_earth, 0); result.eclipse_minimum_earth = result.minimum_earth
	return result
}

system_planet_orbit_stable :: proc(system: ^Solar_System, planet_index: int) -> bool {
	if planet_index < 0 || planet_index >= system.planet_count do return false
	p := &system.planets[planet_index]; peri := p.orbit.semi_major_axis_au * (1 - p.orbit.eccentricity); apo := p.orbit.semi_major_axis_au * (1 + p.orbit.eccentricity)
	if system.star_count == 2 &&
	   system.binary_bound {limits := system_stability_limits(system); if p.host.body.kind == .Barycenter do return peri >= limits.circumbinary_inner_au * 1.10; if p.host.body.kind == .Star {limit := p.host.body.index == 0 ? limits.circumprimary_outer_au : limits.circumsecondary_outer_au; return apo <= limit * .90}}
	return p.body.orbit_stable
}

system_validate :: proc(system: ^Solar_System) -> bool {
	if system.star_count < 1 || system.star_count > MAX_SYSTEM_STARS do return false
	if system.star_count == 2 && system.binary_bound && !orbital_elements_valid(system.binary_orbit) do return false
	for star in system.stars[:system.star_count] do if star.profile.mass_solar <= 0 || star.profile.radius_solar <= 0 || star.profile.age_billion_years < 0 do return false
	for planet in system.planets[:system.planet_count] do if !system_ref_valid(system, planet.host.body) || !orbital_elements_valid(planet.orbit) do return false
	for moon in system.moons[:system.moon_count] do if moon.host.body.kind != .Planet || moon.host_planet_index < 0 || moon.host_planet_index >= system.planet_count || moon.host.body.index != moon.host_planet_index || !orbital_elements_valid(moon.orbit) do return false
	for belt in system.belts[:system.belt_count] do if !system_ref_valid(system, belt.host.body) || !orbital_elements_valid(belt.orbit) || belt.inner_au >= belt.outer_au do return false
	for asteroid in system.asteroids[:system.asteroid_count] do if !system_ref_valid(system, asteroid.host.body) || !orbital_elements_valid(asteroid.orbit) do return false
	return true
}
