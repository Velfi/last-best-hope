package game

import "core:math"

// Deterministic rapid population-synthesis layer. The phase ordering, remnant
// mapping, Roche geometry, orbital mass response, and interaction sequence
// follow the SSE/BSE model family (Hurley, Pols & Tout 2000; Hurley, Tout &
// Pols 2002). Coefficients are deliberately centralized for reference testing.

stellar_class_for_temperature :: proc(temperature: f64) -> Star_Class {
	if temperature < 3900 do return .M
	if temperature < 5200 do return .K
	if temperature < 6000 do return .G
	return .F
}

stellar_main_sequence_lifetime :: proc(mass, metallicity_dex: f64) -> f64 {
	z_factor := clamp(math.pow(10.0, metallicity_dex * .08), .72, 1.28)
	return 10 * math.pow(max(mass, .08), -2.5) * z_factor
}

stellar_remnant_mass :: proc(initial_mass: f64, phase: Stellar_Phase) -> f64 {
	#partial switch phase {
	case .White_Dwarf:
		return clamp(.109 * initial_mass + .394, .50, 1.38)
	case .Neutron_Star:
		return clamp(1.17 + .09 * (initial_mass - 8), 1.17, 2.25)
	case .Black_Hole:
		return clamp(.12 * initial_mass + 1.8, 3, 45)
	case:
		return initial_mass
	}
}

evolve_star_to_age :: proc(initial_mass, metallicity_dex, age_gyr: f64) -> System_Star {
	tms := stellar_main_sequence_lifetime(initial_mass, metallicity_dex)
	s := System_Star {
		initial_mass_solar                   = initial_mass,
		metallicity_dex                      = metallicity_dex,
		main_sequence_lifetime_billion_years = tms,
		bound                                = true,
		spin_period_days                     = 12 + 18 / clamp(initial_mass, .2, 4),
	}
	f := age_gyr / max(tms, 1.0e-9)
	mass, luminosity, radius := initial_mass, f64(0), f64(0)
	if f <
	   .001 {s.phase = .Protostar; luminosity = math.pow(initial_mass, 2.2) * (.45 + f * 550); radius = math.pow(initial_mass, .8) * (2.5 - f * 1200)
	} else if f <
	   1 {s.phase = .Main_Sequence; mass = initial_mass * (1 - .008 * f); luminosity = (initial_mass < .43 ? .23 * math.pow(initial_mass, 2.3) : math.pow(initial_mass, 4)) * (.72 + .48 * f); radius = math.pow(initial_mass, .8) * (.9 + .22 * f)
	} else if f <
	   1.08 {s.phase = .Hertzsprung_Gap; mass = initial_mass * (.992 - .04 * (f - 1) / .08); luminosity = math.pow(initial_mass, 3.6) * (1 + 12 * (f - 1) / .08); radius = math.pow(initial_mass, .8) * (1.12 + 8 * (f - 1) / .08)
	} else if f <
	   1.18 {s.phase = .Red_Giant; mass = initial_mass * (.95 - .12 * (f - 1.08) / .10); luminosity = math.pow(initial_mass, 3.1) * (15 + 85 * (f - 1.08) / .10); radius = math.pow(initial_mass, .65) * (10 + 90 * (f - 1.08) / .10)
	} else if f <
	   1.25 {s.phase = .Core_Helium_Burning; mass = initial_mass * .82; luminosity = math.pow(initial_mass, 2.8) * 35; radius = math.pow(initial_mass, .55) * 12
	} else if f <
	   1.31 {s.phase = .Asymptotic_Giant; mass = initial_mass * (.80 - .20 * (f - 1.25) / .06); luminosity = math.pow(initial_mass, 3) * 120; radius = math.pow(initial_mass, .5) * 180
	} else {
		if initial_mass <
		   8 {s.phase = .White_Dwarf; mass = stellar_remnant_mass(initial_mass, s.phase); radius = .012 * math.pow(max(mass, .2), -1.0 / 3.0); luminosity = .01 / math.pow(max(age_gyr - tms, .02), 1.25)
		} else if initial_mass <
		   22 {s.phase = .Neutron_Star; mass = stellar_remnant_mass(initial_mass, s.phase); radius = 1.7e-5; luminosity = 1.0e-5
		} else {s.phase = .Black_Hole; mass = stellar_remnant_mass(initial_mass, s.phase); radius =
				4.24e-6 * mass
			luminosity = 1.0e-9}
	}
	s.core_mass_solar =
		s.phase >= .White_Dwarf ? mass : clamp(.08 * initial_mass + .1 * f, 0, mass)
	s.profile = {
		mass_solar        = max(mass, .01),
		luminosity_solar  = max(luminosity, 1.0e-10),
		radius_solar      = max(radius, 1.0e-8),
		age_billion_years = age_gyr,
	}
	s.effective_temperature_k =
		5772 *
		math.pow(
			s.profile.luminosity_solar /
			max(s.profile.radius_solar * s.profile.radius_solar, 1.0e-16),
			.25,
		)
	s.class = stellar_class_for_temperature(s.effective_temperature_k)
	return s
}

roche_lobe_radius_fraction :: proc(mass_ratio: f64) -> f64 {
	q13 := math.pow(max(mass_ratio, 1.0e-9), 1.0 / 3.0); q23 := q13 * q13
	return .49 * q23 / (.6 * q23 + math.ln(1 + q13))
}

black_hole_accretion_state :: proc(
	system: ^Solar_System,
	black_hole_index: int,
) -> Black_Hole_Accretion {
	view_state := system.seed ~ (u64(black_hole_index + 1) * 0x9e3779b97f4a7c15)
	// Random sight lines are isotropic when cos(inclination) is uniform. Keeping
	// this derived from the system seed makes the survey projection reproducible.
	result := Black_Hole_Accretion {
		kind                        = .Dormant,
		donor_index                 = -1,
		view_cosine                 = clamp(planet_random_unit(&view_state), .12, .96),
		view_position_angle_radians = planet_random_range(&view_state, -math.PI / 2, math.PI / 2),
	}
	if black_hole_index < 0 ||
	   black_hole_index >= system.star_count ||
	   system.stars[black_hole_index].phase != .Black_Hole ||
	   system.star_count != 2 ||
	   !system.binary_bound {
		return result
	}

	donor_index := 1 - black_hole_index
	donor := &system.stars[donor_index]
	if !donor.bound || donor.phase >= .White_Dwarf do return result
	black_hole := &system.stars[black_hole_index]
	periapsis_au := system.binary_orbit.semi_major_axis_au * (1 - system.binary_orbit.eccentricity)
	donor_lobe_au :=
		periapsis_au *
		roche_lobe_radius_fraction(donor.profile.mass_solar / black_hole.profile.mass_solar)
	black_hole_lobe_au :=
		periapsis_au *
		roche_lobe_radius_fraction(black_hole.profile.mass_solar / donor.profile.mass_solar)
	donor_radius_au := donor.profile.radius_solar * .00465047
	result.donor_index = donor_index
	result.roche_lobe_fill = donor_radius_au / max(donor_lobe_au, 1.0e-12)
	result.disk_outer_radius_km = max(
		black_hole_isco_radius_km(black_hole.profile.mass_solar) * 5,
		black_hole_lobe_au * 149597870.7 * .30,
	)

	if result.roche_lobe_fill >= 1 {
		unstable_donor := donor.phase == .Red_Giant || donor.phase == .Asymptotic_Giant
		result.kind = unstable_donor ? .Thick_Flow : .Transfer_Disk
		result.eddington_fraction = clamp(
			(unstable_donor ? .35 : .04) * math.pow(result.roche_lobe_fill, 2),
			1.0e-4,
			1,
		)
		return result
	}

	wind_strength: f64
	#partial switch donor.phase {
	case .Red_Giant:
		wind_strength = .8
	case .Asymptotic_Giant:
		wind_strength = 1
	case .Stripped_Helium:
		wind_strength = .65
	case .Core_Helium_Burning:
		wind_strength = .18
	case .Main_Sequence:
		if donor.initial_mass_solar >= 8 do wind_strength = .12
	case:
	}
	if wind_strength > 0 && periapsis_au <= 25 {
		capture :=
			math.pow(black_hole.profile.mass_solar / 10, 2) / max(periapsis_au * periapsis_au, .04)
		result.eddington_fraction = clamp(wind_strength * capture * .002, 1.0e-7, .03)
		if result.eddington_fraction >= 1.0e-6 do result.kind = .Wind_Fed
	}
	return result
}

append_system_event :: proc(system: ^Solar_System, event: System_Evolution_Event) {
	if system.event_count >= MAX_SYSTEM_EVENTS do return
	system.events[system.event_count] = event; system.event_count += 1
}

evolve_binary_interactions :: proc(
	system: ^Solar_System,
	initial_a, initial_e: f64,
	age_gyr: f64,
	state: ^u64,
) {
	system.binary_bound = true
	system.binary_orbit = {
		semi_major_axis_au         = initial_a,
		eccentricity               = initial_e,
		inclination_radians        = planet_random_range(state, 0, .08),
		ascending_node_radians     = planet_random_range(state, 0, 2 * math.PI),
		argument_periapsis_radians = planet_random_range(state, 0, 2 * math.PI),
		mean_anomaly_radians       = planet_random_range(state, 0, 2 * math.PI),
	}
	system.initial_binary_orbit = system.binary_orbit
	m1i, m2i := system.stars[0].initial_mass_solar, system.stars[1].initial_mass_solar
	initial_total :=
		m1i +
		m2i; current_total := system.stars[0].profile.mass_solar + system.stars[1].profile.mass_solar
	peri := initial_a * (1 - initial_e)
	r1 :=
		system.stars[0].profile.radius_solar *
		.00465047; r2 := system.stars[1].profile.radius_solar * .00465047
	l1 :=
		peri *
		roche_lobe_radius_fraction(m1i / m2i); l2 := peri * roche_lobe_radius_fraction(m2i / m1i)
	if r1 >= l1 || r2 >= l2 {
		donor := r1 / l1 > r2 / l2 ? 0 : 1; receiver := 1 - donor
		pre := system.stars[donor].profile.mass_solar
		unstable :=
			system.stars[donor].phase == .Red_Giant ||
			system.stars[donor].phase == .Asymptotic_Giant
		if unstable {
			append_system_event(
				system,
				{
					age_billion_years = min(
						age_gyr,
						system.stars[donor].main_sequence_lifetime_billion_years * 1.1,
					),
					kind = .Common_Envelope,
					primary = {kind = .Star, index = donor},
					secondary = {kind = .Star, index = receiver},
					pre_mass_solar = pre,
					post_mass_solar = system.stars[donor].core_mass_solar,
					pre_axis_au = initial_a,
					post_axis_au = initial_a * .12,
				},
			)
			system.binary_orbit.semi_major_axis_au = max(
				initial_a * .12,
				(r1 + r2) * 1.2,
			); system.binary_orbit.eccentricity = 0
			if (r1 + r2) > .75 * peri { 	// envelope cannot be ejected: merge
				merged_mass := max(
					current_total * .88,
					.1,
				); system.stars[0] = evolve_star_to_age(merged_mass, system.metallicity_dex, age_gyr); system.stars[0].initial_mass_solar = initial_total; system.stars[1].bound = false; system.stars[1].phase = .Merged; system.star_count = 1; system.binary_bound = false
				append_system_event(
					system,
					{
						age_billion_years = age_gyr,
						kind = .Stellar_Merger,
						primary = {kind = .Star, index = 0},
						secondary = {kind = .Star, index = 1},
						pre_mass_solar = current_total,
						post_mass_solar = merged_mass,
						pre_axis_au = initial_a,
					},
				)
				return
			}
		} else {
			transfer := min(
				pre * .25,
				max(pre - system.stars[donor].core_mass_solar, 0),
			); system.stars[donor].profile.mass_solar -= transfer; system.stars[receiver].profile.mass_solar += transfer * .7
			system.binary_orbit.semi_major_axis_au *= max(
				(m1i * m2i) /
				max(
					system.stars[0].profile.mass_solar * system.stars[1].profile.mass_solar,
					1.0e-6,
				),
				.2,
			); system.binary_orbit.eccentricity *= .2
			append_system_event(
				system,
				{
					age_billion_years = age_gyr,
					kind = .Mass_Transfer,
					primary = {kind = .Star, index = donor},
					secondary = {kind = .Star, index = receiver},
					pre_mass_solar = pre,
					post_mass_solar = system.stars[donor].profile.mass_solar,
					pre_axis_au = initial_a,
					post_axis_au = system.binary_orbit.semi_major_axis_au,
				},
			)
		}
	} else if current_total < initial_total {
		system.binary_orbit.semi_major_axis_au *= initial_total / max(current_total, .01)
		append_system_event(
			system,
			{
				age_billion_years = age_gyr,
				kind = .Wind_Mass_Loss,
				primary = {kind = .Barycenter},
				pre_mass_solar = initial_total,
				post_mass_solar = current_total,
				pre_axis_au = initial_a,
				post_axis_au = system.binary_orbit.semi_major_axis_au,
			},
		)
	}
	compact_event :=
		system.stars[0].phase >= .Neutron_Star || system.stars[1].phase >= .Neutron_Star
	if compact_event {
		kick := planet_random_range(
			state,
			0,
			450,
		); orbital_speed := 29.78 * math.sqrt(max(current_total / system.binary_orbit.semi_major_axis_au, 0))
		append_system_event(
			system,
			{
				age_billion_years = age_gyr,
				kind = .Supernova,
				primary = {kind = .Star, index = system.stars[0].phase >= .Neutron_Star ? 0 : 1},
				pre_mass_solar = initial_total,
				post_mass_solar = current_total,
				pre_axis_au = initial_a,
				post_axis_au = system.binary_orbit.semi_major_axis_au,
			},
		)
		if current_total < initial_total * .5 ||
		   kick >
			   orbital_speed *
				   2.2 {system.binary_bound = false; system.star_count = 1; system.stars[1].bound = false; append_system_event(system, {age_billion_years = age_gyr, kind = .Binary_Disrupted, primary = {kind = .Star, index = 0}, secondary = {kind = .Star, index = 1}, pre_mass_solar = initial_total, post_mass_solar = current_total, pre_axis_au = initial_a})}
	}
}

generate_stellar_population :: proc(seed: u64, age_gyr, metallicity_dex: f64) -> Solar_System {
	state := seed ~ 0x7374656c6c6172
	// Kroupa-like inverse sampling over the range represented by rapid tracks.
	u := planet_random_unit(
		&state,
	); primary_mass := clamp(.08 * math.pow(max(1 - u, .001), -.74), .08, 60)
	multiplicity := clamp(.18 + .22 * math.log10(max(primary_mass, .1) + 1), .12, .82)
	s := Solar_System {
		model_version             = STELLAR_SYSTEM_MODEL_VERSION,
		seed                      = seed,
		present_age_billion_years = age_gyr,
		metallicity_dex           = metallicity_dex,
		star_count                = 1,
	}
	s.stars[0] = evolve_star_to_age(primary_mass, metallicity_dex, age_gyr)
	if planet_random_unit(&state) < multiplicity {
		q := planet_random_range(
			&state,
			.12,
			1,
		); secondary_mass := primary_mass * q; s.star_count = 2; s.stars[1] = evolve_star_to_age(secondary_mass, metallicity_dex, age_gyr)
		period_days := math.pow(
			10,
			planet_random_range(&state, .2, 6.5),
		); axis := math.pow(period_days / 365.256, 2.0 / 3.0) * math.pow(primary_mass + secondary_mass, 1.0 / 3.0); ecc := period_days < 12 ? 0 : planet_random_range(&state, 0, .78)
		evolve_binary_interactions(&s, axis, ecc, age_gyr, &state)
	}
	return s
}
