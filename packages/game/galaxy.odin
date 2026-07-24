package game

import "core:fmt"
import "core:math"

MAX_GALACTIC_NEIGHBORHOODS :: 64
// Capacity only: the generated galaxy decides how many sampled neighborhoods
// contain a reachable mapped system.
MAX_DETAILED_GALACTIC_SYSTEMS :: 16
MAX_CANDIDATE_HOMES :: MAX_DETAILED_GALACTIC_SYSTEMS
MAX_WORLD_SURVEYS :: MAX_DETAILED_GALACTIC_SYSTEMS
CAMPAIGN_GALAXY_SEED_SALT :: u64(0x67616c617879)
SCHWARZSCHILD_RADIUS_KM_PER_SOLAR_MASS :: 2.95325008

Galaxy_Morphology :: enum {
	Spiral,
	Barred_Spiral,
	Elliptical,
	Dwarf_Irregular,
}
Stellar_Population :: enum {
	Thin_Disk,
	Thick_Disk,
	Bulge,
	Halo,
	Young_Association,
}

Galactic_Neighborhood :: struct {
	x_kpc, y_kpc, z_kpc:            f64,
	galactocentric_radius_kpc:      f64,
	arm_index:                      int,
	population:                     Stellar_Population,
	metallicity_dex:                f64,
	mean_age_billion_years:         f64,
	stellar_density_relative_solar: f64,
	radiation_risk:                 f64,
	planet_occurrence_probability:  f64,
	in_galactic_habitable_zone:     bool,
}

Galactic_System :: struct {
	neighborhood_index: int,
	metallicity_dex:    f64,
	reachability:       f64,
	system:             Solar_System,
}

Galaxy :: struct {
	seed:                                  u64,
	morphology:                            Galaxy_Morphology,
	stellar_mass_solar:                    f64,
	dark_matter_halo_mass_solar:           f64,
	estimated_star_count:                  u64,
	disk_radius_kpc:                       f64,
	scale_height_kpc:                      f64,
	bulge_fraction:                        f64,
	spiral_arm_count:                      int,
	spiral_pitch_degrees:                  f64,
	central_black_hole_occupied:           bool,
	central_black_hole_occupation_chance:  f64,
	central_black_hole_mass_solar:         f64,
	star_formation_rate_solar_masses_year: f64,
	supernova_rate_per_century:            f64,
	mean_metallicity_dex:                  f64,
	habitable_zone_inner_kpc:              f64,
	habitable_zone_outer_kpc:              f64,
	neighborhoods:                         [MAX_GALACTIC_NEIGHBORHOODS]Galactic_Neighborhood,
	neighborhood_count:                    int,
	detailed_systems:                      [dynamic]Galactic_System,
	detailed_system_count:                 int,
}

Celestial_Reference :: struct {
	valid:                                          bool,
	neighborhood_index, system_index, planet_index: int,
	system_seed, planet_seed:                       u64,
	neighborhood_name, system_name, planet_name:    string,
}

Candidate_World_Class :: enum {
	Surveyed_Unsuitable,
	Engineered_Candidate,
	Naturally_Habitable,
}
Biosphere_Evidence :: enum {
	None,
	Potential,
	Complex_Potential,
}
World_Survey_Funnel :: struct {
	systems,
	stars,
	planets,
	terrestrial,
	conservative_hz,
	stable,
	atmosphere_retained,
	water_bearing,
	long_term,
	settlement_capable: i32,
}
Candidate_World_Profile :: struct {
	classification:                                                                                    Candidate_World_Class,
	gravity_earth,
	mean_flux_earth,
	minimum_flux_earth,
	maximum_flux_earth:                            f64,
	atmosphere_retention_margin,
	water_fraction,
	radiation_exposure,
	temperate_history_fraction:       f64,
	tidal_state:                                                                                       Tidal_State,
	biosphere:                                                                                         Biosphere_Evidence,
	food_potential,
	construction_burden,
	maintenance_basis_points,
	population_capacity:                i32,
	terrestrial,
	conservative_hz,
	stable_orbit,
	atmosphere_retained,
	water_bearing,
	long_term_climate: bool,
	measured_evidence,
	modeled_inference:                                                              string,
}
World_Survey_Record :: struct {
	reference:                         Celestial_Reference,
	profile:                           Candidate_World_Profile,
	funnel:                            World_Survey_Funnel,
	system_index, season:              i32,
	expedition_seed, discovered_event: u64,
	survey_cost:                       Fleet_Stock,
	repeat:                            bool,
}
Candidate_Home :: struct {
	reference:                                     Celestial_Reference,
	profile:                                       Candidate_World_Profile,
	discovered_event, discovering_expedition_seed: u64,
	independent_review:                            bool,
}

campaign_galaxy :: proc(c: ^Campaign) -> ^Galaxy {return c.galaxy}
celestial_reference_valid :: proc(c: ^Campaign, r: Celestial_Reference) -> bool {if c.galaxy == nil || !r.valid || r.system_index < 0 || r.system_index >= c.galaxy.detailed_system_count do return false
	s := &c.galaxy.detailed_systems[r.system_index]
	return(
		s.neighborhood_index == r.neighborhood_index &&
		r.planet_index >= 0 &&
		r.planet_index < s.system.planet_count &&
		s.system.seed == r.system_seed &&
		s.system.planets[r.planet_index].body.seed == r.planet_seed \
	)}
candidate_home_index :: proc(c: ^Campaign, r: Celestial_Reference) -> int {for candidate, i in c.candidate_homes[:c.candidate_home_count] do if candidate.reference.system_seed == r.system_seed && candidate.reference.planet_seed == r.planet_seed do return i
	return -1}
candidate_celebration_pending :: proc(c: ^Campaign) -> bool {
	return c != nil && c.candidate_celebration_cursor >= 0 &&
	       c.candidate_celebration_cursor < c.candidate_home_count
}
candidate_celebration :: proc(c: ^Campaign) -> (^Candidate_Home, bool) {
	if !candidate_celebration_pending(c) do return nil, false
	return &c.candidate_homes[c.candidate_celebration_cursor], true
}
acknowledge_candidate_celebration :: proc(c: ^Campaign) -> bool {
	if !candidate_celebration_pending(c) do return false
	c.candidate_celebration_cursor += 1
	return true
}
register_candidate_home :: proc(
	c: ^Campaign,
	record: World_Survey_Record,
	expedition_seed: u64,
) -> bool {
	if !candidate_world_selectable(record.profile) || !record.reference.valid ||
	   c.candidate_home_count >= MAX_CANDIDATE_HOMES ||
	   candidate_home_index(c, record.reference) >= 0 {
		return false
	}
	at := c.candidate_home_count
	c.candidate_homes[at] = {
		reference = record.reference,
		profile = record.profile,
		discovering_expedition_seed = expedition_seed,
	}
	c.candidate_home_count += 1
	c.candidate_home_known = true
	classification := record.profile.classification == .Naturally_Habitable ? "naturally habitable world" : "settlement-capable world requiring engineered support"
	record_event(
		c,
		.Habitable_World_Confirmed,
		fmt.tprintf(
			"The survey of %s in %s confirmed a %s.",
			record.reference.planet_name,
			record.reference.system_name,
			classification,
		),
	)
	c.candidate_homes[at].discovered_event = c.event_sequence
	return true
}
world_probability :: proc(seed, salt: u64) -> f64 {state := seed ~ salt; return planet_random_unit(
		&state,
	)}
evidence_centered_hz_rate :: proc(class: Star_Class) -> f64 {return class == .M ? .33 : .37}
system_evidence_hz_occurrence :: proc(system: ^Solar_System) -> bool {
	// This is the one observation-calibrated step. The downstream atmosphere,
	// water, climate, and biosphere filters are explicitly model assumptions.
	if system == nil || system.star_count <= 0 do return false
	mean: f64
	for star in system.stars[:system.star_count] do mean += evidence_centered_hz_rate(star.class)
	return world_probability(system.seed, 0x6574615f687a5f33) < clamp(mean, 0, .99)
}
system_evidence_hz_planet :: proc(system: ^Solar_System) -> int {
	if !system_evidence_hz_occurrence(system) do return -1
	best := -1; best_distance := f64(1e9)
	for p, i in system.planets[:system.planet_count] {
		density := p.body.inputs.mass_earth / math.pow(max(p.body.inputs.radius_earth, .01), 3)
		if (p.kind != .Rocky && p.kind != .Ocean) || p.body.inputs.radius_earth < .5 || p.body.inputs.radius_earth > 1.8 || density < .45 do continue
		distance := abs(p.flux_envelope.mean_earth - .72)
		if distance < best_distance {best = i; best_distance = distance}
	}
	return best
}
planet_temperate_history_fraction :: proc(p: ^System_Planet) -> f64 {
	total, temperate: f64
	for segment in p.climate_history[:p.climate_history_count] {duration := max(segment.end_age_billion_years - segment.start_age_billion_years, 0); total += duration; if segment.temperate do temperate += duration}
	return total > 0 ? temperate / total : 0
}
candidate_world_profile :: proc(
	g: ^Galaxy,
	system_index, planet_index: int,
) -> Candidate_World_Profile {
	r: Candidate_World_Profile
	if g == nil || system_index < 0 || system_index >= g.detailed_system_count do return r
	gs := &g.detailed_systems[system_index]; if planet_index < 0 || planet_index >= gs.system.planet_count do return r
	p := &gs.system.planets[planet_index]; body := p.body
	density := body.inputs.mass_earth / math.pow(max(body.inputs.radius_earth, .01), 3)
	r.gravity_earth =
		body.surface_gravity_earth; r.mean_flux_earth = p.flux_envelope.mean_earth; r.minimum_flux_earth = p.flux_envelope.minimum_earth; r.maximum_flux_earth = p.flux_envelope.maximum_earth; r.tidal_state = body.tidal_state
	r.terrestrial =
		(p.kind == .Rocky || p.kind == .Ocean) &&
		body.inputs.radius_earth >= .5 &&
		body.inputs.radius_earth <= 1.8 &&
		density >= .45
	r.conservative_hz =
		planet_index == system_evidence_hz_planet(&gs.system) &&
		p.flux_envelope.maximum_greenhouse_index >= 1 &&
		p.flux_envelope.runaway_greenhouse_index <= 1
	r.stable_orbit = body.orbit_stable && system_planet_orbit_stable(&gs.system, planet_index)
	activity := gs.system.stars[0].class == .M ? 1.35 : gs.system.stars[0].class == .F ? 1.15 : 1.0
	r.atmosphere_retention_margin = body.escape_velocity_km_s / max(8.5 * activity, 1)
	r.atmosphere_retained =
		r.atmosphere_retention_margin >= 1 && gs.system.present_age_billion_years >= .5
	r.water_fraction =
		p.surface.fractions[int(Surface_Component.Liquid_Water)] +
		p.surface.fractions[int(Surface_Component.Water_Ice)] * .25
	r.water_bearing = r.water_fraction >= .08
	r.temperate_history_fraction = planet_temperate_history_fraction(
		p,
	); r.long_term_climate = r.temperate_history_fraction >= .5
	n := g.neighborhoods[gs.neighborhood_index]; r.radiation_exposure = n.radiation_risk * activity
	supportable :=
		r.terrestrial &&
		r.stable_orbit &&
		r.gravity_earth >= .3 &&
		r.gravity_earth <= 2.2 &&
		r.radiation_exposure <= 2
	if r.terrestrial &&
	   r.conservative_hz &&
	   r.stable_orbit &&
	   r.atmosphere_retained &&
	   r.water_bearing &&
	   r.long_term_climate &&
	   r.gravity_earth >= .5 &&
	   r.gravity_earth <= 1.8 &&
	   r.radiation_exposure <= 1.2 &&
	   r.tidal_state !=
		   .Likely_Locked {r.classification = .Naturally_Habitable} else if supportable {r.classification = .Engineered_Candidate}
	deficits: i32
	if !r.conservative_hz do deficits += 1
	if !r.atmosphere_retained do deficits += 1
	if !r.water_bearing do deficits += 1
	if !r.long_term_climate do deficits += 1
	if r.tidal_state == .Likely_Locked do deficits += 1
	// Engineered candidates are supportable worlds whose deficits create the
	// settlement's long-term costs and choices. Requiring near-habitability here
	// made this category effectively duplicate Naturally_Habitable.
	if r.classification == .Engineered_Candidate && deficits > 3 do r.classification = .Surveyed_Unsuitable
	if r.classification != .Surveyed_Unsuitable &&
	   world_probability(body.seed, 0x62696f7370686572) <
		   .08 {r.biosphere = .Potential; if world_probability(body.seed, 0x636f6d706c6578) < .04 do r.biosphere = .Complex_Potential}
	r.food_potential = clamp(
		i32(
			20 +
			r.water_fraction * 45 +
			r.temperate_history_fraction * 35 +
			(r.biosphere != .None ? 5 : 0),
		),
		0,
		100,
	)
	r.construction_burden = clamp(
		20 + deficits * 18 + i32(abs(r.gravity_earth - 1) * 20) + i32(r.radiation_exposure * 8),
		10,
		100,
	)
	r.maintenance_basis_points = 10000 + r.construction_burden * 75
	r.population_capacity = clamp((110 - r.construction_burden) * 1000, 5000, 100000)
	r.measured_evidence = "Measured: orbit, gravity, flux history, surface composition, and radiation environment."
	r.modeled_inference = "Modeled: atmosphere retention, long-term climate, and biosphere evidence; incidence beyond terrestrial habitable-zone occurrence is not observationally constrained."
	return r
}
candidate_world_selectable :: proc(p: Candidate_World_Profile) -> bool {return(
		p.classification == .Naturally_Habitable ||
		p.classification == .Engineered_Candidate \
	)}
planet_is_candidate_home :: proc(p: Planet) -> bool {
	assessment := assess_planet_habitability(p, false, false, false)
	return assessment.rocky && assessment.temperate && assessment.stable_orbit
}
survey_candidate_system_index :: proc(
	c: ^Campaign,
	system_index: int,
	expedition_seed: u64,
) -> (
	World_Survey_Record,
	bool,
) {
	if c.galaxy == nil ||
	   system_index < 0 ||
	   system_index >= c.galaxy.detailed_system_count ||
	   system_index >= 64 {
		return {}, false
	}
	gs := &c.galaxy.detailed_systems[system_index]; bit := u64(1) << u64(system_index); record := World_Survey_Record {
		system_index    = i32(system_index),
		season          = c.season,
		expedition_seed = expedition_seed,
		repeat          = (c.surveyed_system_mask & bit) != 0,
	}; record.funnel.systems = 1; record.funnel.stars = i32(gs.system.star_count); record.funnel.planets = i32(gs.system.planet_count)
	c.surveyed_system_mask |= bit
	best := -1; best_rank := -100000
	for _, i in gs.system.planets[:gs.system.planet_count] {
		profile := candidate_world_profile(c.galaxy, system_index, i)
		if profile.terrestrial do record.funnel.terrestrial += 1
		if profile.terrestrial && profile.conservative_hz do record.funnel.conservative_hz += 1
		if profile.terrestrial && profile.conservative_hz && profile.stable_orbit do record.funnel.stable += 1
		if profile.terrestrial && profile.conservative_hz && profile.stable_orbit && profile.atmosphere_retained do record.funnel.atmosphere_retained += 1
		if profile.terrestrial && profile.conservative_hz && profile.stable_orbit && profile.atmosphere_retained && profile.water_bearing do record.funnel.water_bearing += 1
		if profile.terrestrial && profile.conservative_hz && profile.stable_orbit && profile.atmosphere_retained && profile.water_bearing && profile.long_term_climate do record.funnel.long_term += 1
		if candidate_world_selectable(profile) do record.funnel.settlement_capable += 1
		rank :=
			int(profile.classification) * 100 +
			int(profile.food_potential) -
			int(profile.construction_burden)
		if rank > best_rank {best = i; best_rank = rank; record.profile = profile}
	}
	if best < 0 do return record, true
	names := generate_solar_system_names(
		gs.system,
	); planet := gs.system.planets[best]; record.reference = {
		valid              = true,
		neighborhood_index = gs.neighborhood_index,
		system_index       = system_index,
		planet_index       = best,
		system_seed        = gs.system.seed,
		planet_seed        = planet.body.seed,
		neighborhood_name  = fmt.tprintf("Neighborhood %02d", gs.neighborhood_index + 1),
		system_name        = names.proper_name,
		planet_name        = names.planet_names[best],
	}
	return record, true
}

survey_candidate_system :: proc(
	c: ^Campaign,
	expedition_seed: u64,
) -> (
	World_Survey_Record,
	bool,
) {
	if c.galaxy == nil || c.galaxy.detailed_system_count <= 0 do return {}, false
	system_index := int(expedition_seed % u64(c.galaxy.detailed_system_count))
	// A survey seed chooses where to begin, then advances to an unvisited reachable
	// system. Repeated RNG residues must not exhaust the exploration loop early.
	for offset in 0 ..< c.galaxy.detailed_system_count {
		candidate := (system_index + offset) % c.galaxy.detailed_system_count
		if (c.surveyed_system_mask & (u64(1) << u64(candidate))) ==
		   0 {system_index = candidate; break}
	}
	return survey_candidate_system_index(c, system_index, expedition_seed)
}
discover_candidate_home :: proc(
	c: ^Campaign,
	expedition_seed: u64,
) -> (
	Celestial_Reference,
	bool,
) {
	record, ok := survey_candidate_system(c, expedition_seed); if !ok do return {}, false
	if c.world_survey_count <
	   MAX_WORLD_SURVEYS {c.world_surveys[c.world_survey_count] = record; c.world_survey_count += 1}
	return record.reference, register_candidate_home(c, record, expedition_seed)
}

black_hole_schwarzschild_radius_km :: proc(mass_solar: f64) -> f64 {
	return max(mass_solar, 0) * SCHWARZSCHILD_RADIUS_KM_PER_SOLAR_MASS
}

black_hole_photon_sphere_radius_km :: proc(mass_solar: f64) -> f64 {
	return black_hole_schwarzschild_radius_km(mass_solar) * 1.5
}

black_hole_isco_radius_km :: proc(mass_solar: f64) -> f64 {
	// Schwarzschild (non-spinning) reference orbit. Spin is not inferred by the
	// current survey model, so the UI must label this as a reference value.
	return black_hole_schwarzschild_radius_km(mass_solar) * 3
}

central_black_hole_occupation_probability :: proc(stellar_mass_solar: f64) -> f64 {
	// Burke et al. (2025) constrain occupation to at least 39% at 10^7 M-solar
	// and at least 90% at 10^8 M-solar. Above dwarf scales, observations are
	// consistent with near-unity occupation. Piecewise interpolation keeps those
	// empirical anchors visible instead of hiding seed-model assumptions in a fit.
	log_mass := math.log10(max(stellar_mass_solar, 1))
	if log_mass <= 7 do return clamp(.10 + (log_mass - 6) * .29, .02, .39)
	if log_mass <= 8 do return .39 + (log_mass - 7) * .51
	if log_mass <= 9 do return .90 + (log_mass - 8) * .07
	if log_mass <= 10 do return .97 + (log_mass - 9) * .025
	return .995
}

central_black_hole_mass_for_galaxy :: proc(
	stellar_mass_solar: f64,
	morphology: Galaxy_Morphology,
	state: ^u64,
) -> f64 {
	// Reines & Volonteri (2015): active, mostly disk hosts follow the lower
	// total-stellar-mass relation; ellipticals/classical bulges follow a steeper,
	// higher relation. The Gaussian term carries their observed rms scatter.
	log_stellar := math.log10(max(stellar_mass_solar, 1) / 1.0e11)
	u1 := max(planet_random_unit(state), 1.0e-12)
	u2 := planet_random_unit(state)
	normal := math.sqrt(-2 * math.ln(u1)) * math.cos(2 * math.PI * u2)
	log_mass, scatter: f64
	if morphology == .Elliptical {
		log_mass = 8.95 + 1.40 * log_stellar
		scatter = .60
	} else {
		log_mass = 7.45 + 1.05 * log_stellar
		scatter = .55
	}
	return clamp(math.pow(10.0, log_mass + normal * scatter), 1.0e2, stellar_mass_solar * .02)
}

galaxy_morphology_for_roll :: proc(roll: f64) -> Galaxy_Morphology {
	return(
		roll < 0.42 ? .Spiral : roll < 0.72 ? .Barred_Spiral : roll < 0.88 ? .Elliptical : .Dwarf_Irregular \
	)
}

galaxy_exponential_disk_cdf :: proc(radius, scale_length: f64) -> f64 {
	x := max(radius / max(scale_length, 1.0e-9), 0)
	return 1 - math.exp(-x) * (1 + x)
}

sample_truncated_exponential_disk_radius :: proc(u, scale_length, limit: f64) -> f64 {
	target := u * galaxy_exponential_disk_cdf(limit, scale_length)
	lo, hi := f64(0), limit
	for _ in 0 ..< 24 {
		mid := (lo + hi) * .5
		if galaxy_exponential_disk_cdf(mid, scale_length) < target {
			lo = mid
		} else {
			hi = mid
		}
	}
	return (lo + hi) * .5
}

galaxy_sersic_integer_cdf_x :: proc(x: f64, n: int) -> f64 {
	clamped_x := max(x, 0)
	shape := 2 * clamp(n, 1, 4)
	term, sum := f64(1), f64(1)
	for k in 1 ..< shape {
		term *= clamped_x / f64(k)
		sum += term
	}
	return 1 - math.exp(-clamped_x) * sum
}

galaxy_sersic_b_n :: proc(n: int) -> f64 {
	nf := f64(clamp(n, 1, 4))
	// Ciotti-Bertin asymptotic expansion; already accurate to better than
	// 2e-4 throughout the n=1..4 range used by the renderer.
	return 2 * nf - 1.0 / 3.0 + 4.0 / (405 * nf) + 46.0 / (25515 * nf * nf)
}

sample_truncated_sersic_integer_radius :: proc(u, effective_radius, limit: f64, n: int) -> f64 {
	clamped_n := clamp(n, 1, 4)
	b_n := galaxy_sersic_b_n(clamped_n)
	x_limit := b_n * math.pow(limit / max(effective_radius, 1.0e-9), 1 / f64(clamped_n))
	target := u * galaxy_sersic_integer_cdf_x(x_limit, clamped_n)
	lo, hi := f64(0), x_limit
	for _ in 0 ..< 26 {
		mid := (lo + hi) * .5
		if galaxy_sersic_integer_cdf_x(mid, clamped_n) < target {
			lo = mid
		} else {
			hi = mid
		}
	}
	x := (lo + hi) * .5
	return effective_radius * math.pow(x / b_n, f64(clamped_n))
}

galaxy_sersic_n2_cdf_x :: proc(x: f64) -> f64 {
	return galaxy_sersic_integer_cdf_x(x, 2)
}

sample_truncated_sersic_n2_radius :: proc(u, effective_radius, limit: f64) -> f64 {
	return sample_truncated_sersic_integer_radius(u, effective_radius, limit, 2)
}

sample_ferrers_elliptical_radius :: proc(u: f64, order: f64 = 2) -> f64 {
	return math.sqrt(1 - math.pow(1 - u, 1 / (order + 1)))
}

galaxy_bulk_properties :: proc(g: ^Galaxy, state: ^u64) {
	switch g.morphology {
	case .Spiral, .Barred_Spiral:
		g.stellar_mass_solar = math.pow(10.0, planet_random_range(state, 9.5, 11.25))
		g.disk_radius_kpc = 15 * math.pow(g.stellar_mass_solar / 6.0e10, 0.32)
		g.scale_height_kpc = planet_random_range(state, 0.22, 0.55)
		g.bulge_fraction =
			g.morphology == .Barred_Spiral ? planet_random_range(state, 0.18, 0.38) : planet_random_range(state, 0.08, 0.25)
		g.spiral_arm_count = 2 + int(planet_rng_next(state) % 3)
		g.spiral_pitch_degrees = planet_random_range(state, 10, 28)
		g.star_formation_rate_solar_masses_year =
			1.6 * (g.stellar_mass_solar / 6.0e10) * planet_random_range(state, 0.45, 1.8)
		g.mean_metallicity_dex = planet_random_range(state, -0.25, 0.15)
	case .Elliptical:
		g.stellar_mass_solar = math.pow(10.0, planet_random_range(state, 10.0, 12.0))
		g.disk_radius_kpc = 8 * math.pow(g.stellar_mass_solar / 1.0e11, 0.45)
		g.scale_height_kpc = g.disk_radius_kpc * 0.65
		g.bulge_fraction = planet_random_range(state, 0.75, 0.98)
		g.star_formation_rate_solar_masses_year =
			0.02 * (g.stellar_mass_solar / 1.0e11) * planet_random_range(state, 0.2, 2)
		g.mean_metallicity_dex = planet_random_range(state, -0.15, 0.25)
	case .Dwarf_Irregular:
		g.stellar_mass_solar = math.pow(10.0, planet_random_range(state, 7.0, 9.5))
		g.disk_radius_kpc = 2.5 * math.pow(g.stellar_mass_solar / 1.0e9, 0.3)
		g.scale_height_kpc = g.disk_radius_kpc * 0.22
		g.bulge_fraction = planet_random_range(state, 0, 0.08)
		g.star_formation_rate_solar_masses_year =
			0.12 * (g.stellar_mass_solar / 1.0e9) * planet_random_range(state, 0.3, 2.5)
		g.mean_metallicity_dex = planet_random_range(state, -1.2, -0.35)
	}
	g.dark_matter_halo_mass_solar = g.stellar_mass_solar * planet_random_range(state, 12, 45)
	g.estimated_star_count = u64(g.stellar_mass_solar / 0.52)
	black_hole_state := g.seed ~ 0x626c61636b686f6c
	g.central_black_hole_occupation_chance = central_black_hole_occupation_probability(
		g.stellar_mass_solar,
	)
	g.central_black_hole_occupied =
		planet_random_unit(&black_hole_state) < g.central_black_hole_occupation_chance
	if g.central_black_hole_occupied {
		g.central_black_hole_mass_solar = central_black_hole_mass_for_galaxy(
			g.stellar_mass_solar,
			g.morphology,
			&black_hole_state,
		)
	}
	g.supernova_rate_per_century = max(0.002, 1.4 * g.star_formation_rate_solar_masses_year)
	g.habitable_zone_inner_kpc = g.disk_radius_kpc * (g.morphology == .Elliptical ? 0.18 : 0.24)
	g.habitable_zone_outer_kpc =
		g.disk_radius_kpc * (g.morphology == .Dwarf_Irregular ? 0.62 : 0.72)
}

sample_disk_neighborhood :: proc(g: ^Galaxy, state: ^u64) -> Galactic_Neighborhood {
	n: Galactic_Neighborhood
	scale_length := g.disk_radius_kpc / 3.2
	radius := -scale_length * math.ln(max(1.0e-9, 1 - planet_random_unit(state)))
	radius = min(radius, g.disk_radius_kpc)
	arm: int
	theta: f64
	if g.morphology == .Dwarf_Irregular {
		arm = -1
		theta = planet_random_range(state, 0, 2 * math.PI)
	} else {
		arm = int(planet_rng_next(state) % u64(g.spiral_arm_count))
		pitch := g.spiral_pitch_degrees * math.PI / 180
		arm_phase := f64(arm) * 2 * math.PI / f64(g.spiral_arm_count)
		theta =
			arm_phase +
			math.ln(max(radius, 0.05) / max(scale_length, 0.05)) / math.tan(pitch) +
			planet_random_range(state, -0.20, 0.20)
	}
	n.x_kpc = radius * math.cos(theta)
	n.y_kpc = radius * math.sin(theta)
	z_sign := planet_random_unit(state) < 0.5 ? -1.0 : 1.0
	n.z_kpc = z_sign * (-g.scale_height_kpc * math.ln(max(1.0e-9, 1 - planet_random_unit(state))))
	n.galactocentric_radius_kpc = radius
	n.arm_index = arm
	n.population =
		math.abs(n.z_kpc) > 2 * g.scale_height_kpc ? .Thick_Disk : planet_random_unit(state) < 0.12 ? .Young_Association : .Thin_Disk
	return n
}

sample_elliptical_neighborhood :: proc(g: ^Galaxy, state: ^u64) -> Galactic_Neighborhood {
	n: Galactic_Neighborhood
	u := min(planet_random_unit(state), 0.94)
	sqrt_u := math.sqrt(u)
	radius := min(g.disk_radius_kpc, g.disk_radius_kpc * 0.18 * sqrt_u / (1 - sqrt_u))
	cos_polar := planet_random_range(state, -1, 1)
	sin_polar := math.sqrt(1 - cos_polar * cos_polar)
	theta := planet_random_range(state, 0, 2 * math.PI)
	n.x_kpc = radius * sin_polar * math.cos(theta)
	n.y_kpc = radius * sin_polar * math.sin(theta)
	n.z_kpc = radius * cos_polar * 0.78
	n.galactocentric_radius_kpc = math.sqrt(
		n.x_kpc * n.x_kpc + n.y_kpc * n.y_kpc + n.z_kpc * n.z_kpc,
	)
	n.arm_index = -1
	n.population = n.galactocentric_radius_kpc < g.disk_radius_kpc * 0.3 ? .Bulge : .Halo
	return n
}

finish_neighborhood_environment :: proc(g: ^Galaxy, n: ^Galactic_Neighborhood, state: ^u64) {
	radius_fraction := n.galactocentric_radius_kpc / max(g.disk_radius_kpc, 0.01)
	gradient := g.morphology == .Dwarf_Irregular ? -0.18 : -0.55
	n.metallicity_dex = clamp(
		g.mean_metallicity_dex +
		gradient * (radius_fraction - 0.45) +
		planet_random_range(state, -0.12, 0.12),
		-2.0,
		0.5,
	)
	if n.population == .Young_Association {
		n.mean_age_billion_years = planet_random_range(state, 0.01, 0.5)
	} else if g.morphology == .Elliptical || n.population == .Bulge || n.population == .Halo {
		n.mean_age_billion_years = planet_random_range(state, 8, 12.8)
	} else {
		n.mean_age_billion_years = planet_random_range(state, 1, 10.5)
	}
	n.stellar_density_relative_solar =
		max(0.01, math.exp(-3.2 * radius_fraction) * 12) *
		math.exp(-math.abs(n.z_kpc) / max(g.scale_height_kpc, 0.05))
	central_risk := 1 / (0.08 + n.galactocentric_radius_kpc * n.galactocentric_radius_kpc)
	formation_risk :=
		g.star_formation_rate_solar_masses_year / max(g.stellar_mass_solar / 1.0e10, 0.01)
	n.radiation_risk = central_risk + formation_risk * 0.15
	n.planet_occurrence_probability = clamp(
		0.28 + 0.35 * math.pow(10.0, n.metallicity_dex),
		0.12,
		0.92,
	)
	n.in_galactic_habitable_zone =
		n.galactocentric_radius_kpc >= g.habitable_zone_inner_kpc &&
		n.galactocentric_radius_kpc <= g.habitable_zone_outer_kpc &&
		n.metallicity_dex > -1.0
}

generate_galaxy :: proc(seed: u64) -> Galaxy {
	state := seed
	g := Galaxy {
		seed       = seed,
		morphology = galaxy_morphology_for_roll(planet_random_unit(&state)),
	}
	g.detailed_systems = make(
		[dynamic]Galactic_System,
		0,
		MAX_DETAILED_GALACTIC_SYSTEMS,
		campaign_storage_allocator(),
	)
	galaxy_bulk_properties(&g, &state)
	g.neighborhood_count = MAX_GALACTIC_NEIGHBORHOODS
	for i in 0 ..< g.neighborhood_count {
		n :=
			g.morphology == .Elliptical ? sample_elliptical_neighborhood(&g, &state) : sample_disk_neighborhood(&g, &state)
		finish_neighborhood_environment(&g, &n, &state)
		g.neighborhoods[i] = n
	}

	// Reachable-system count emerges from the galaxy. Dense, lower-radiation,
	// spatially nearby neighborhoods are easier to map; planet contents are not
	// consulted. One origin neighborhood is always represented.
	anchor := 0; anchor_score := f64(-1e9)
	for n, i in g.neighborhoods[:g.neighborhood_count] {score := math.log10(max(n.stellar_density_relative_solar, .001) + 1) - n.radiation_risk * .25 - math.abs(n.galactocentric_radius_kpc - (g.habitable_zone_inner_kpc + g.habitable_zone_outer_kpc) * .5) * .04; if score > anchor_score {anchor = i; anchor_score = score}}
	offset := int(planet_rng_next(&state) % u64(g.neighborhood_count))
	for sample in 0 ..< g.neighborhood_count {
		i := (offset + sample * 17) % g.neighborhood_count
		n := g.neighborhoods[i]
		dx :=
			n.x_kpc -
			g.neighborhoods[anchor].x_kpc; dy := n.y_kpc - g.neighborhoods[anchor].y_kpc; dz := n.z_kpc - g.neighborhoods[anchor].z_kpc; distance := math.sqrt(dx * dx + dy * dy + dz * dz); density := math.log10(max(n.stellar_density_relative_solar, .001) + 1)
		morphology_access :=
			g.morphology == .Dwarf_Irregular ? .10 : g.morphology == .Elliptical ? -.06 : 0
		reachability := clamp(
			.38 +
			density * .16 -
			distance / max(g.disk_radius_kpc, 1) * .35 -
			n.radiation_risk * .08 +
			morphology_access,
			.04,
			.92,
		)
		if i != anchor && planet_random_unit(&state) > reachability do continue
		if g.detailed_system_count >= MAX_DETAILED_GALACTIC_SYSTEMS do break
		system, ok := generate_solar_system_population(
			planet_rng_next(&state),
			n.mean_age_billion_years,
			n.metallicity_dex,
		)
		if ok {
			// Planet-hosting incidence remains a separate stellar-population draw.
			// A failed disk leaves a scientifically useful barren stellar system.
			if planet_random_unit(&state) > n.planet_occurrence_probability {
				system.planet_count = 0; system.moon_count = 0; system.belt_count = 0; system.asteroid_count = 0
			}
			append(
				&g.detailed_systems,
				Galactic_System {
					neighborhood_index = i,
					metallicity_dex = n.metallicity_dex,
					reachability = reachability,
					system = system,
				},
			)
			g.detailed_system_count += 1
		}
	}
	return g
}

galaxy_destroy :: proc(g: ^Galaxy) {
	when !ODIN_TEST do delete(g.detailed_systems)
	g.detailed_systems = nil; g.detailed_system_count = 0
}
