package game

import "core:math"

HABITABILITY_MODEL_VERSION :: u32(3)
HABITABILITY_BATCHES :: 64

Habitability_Scenario :: enum {
	Conservative,
	Evidence_Centered,
	Optimistic,
}
Habitability_Tier :: enum {
	Any_Planet,
	Rocky,
	Temperate_Rocky,
	Earth_Analogue,
	Long_Term_Habitable,
	Potential_Biosphere,
	Potential_Complex_Biosphere,
}

Habitability_Assumptions :: struct {
	version:              u32,
	scenario:             Habitability_Scenario,
	eta_rocky_hz_gk:      f64,
	eta_rocky_hz_m:       f64,
	atmosphere_retention: f64,
	climate_persistence:  f64,
	abiogenesis:          f64,
	complex_life:         f64,
}

Habitability_Interval :: struct {
	median, low_5, high_95, rate_per_star: f64,
}

Habitability_Cell :: struct {
	neighborhood_index: int,
	stars_represented:  f64,
	samples:            int,
	rates:              [len(Habitability_Tier)]f64,
}

Galaxy_Habitability_Report :: struct {
	seed:          u64,
	model_version: u32,
	scenario:      Habitability_Scenario,
	star_count:    u64,
	sample_count:  int,
	tiers:         [len(Habitability_Tier)]Habitability_Interval,
	cells:         [MAX_GALACTIC_NEIGHBORHOODS]Habitability_Cell,
	cell_count:    int,
}

Planet_Habitability_Assessment :: struct {
	highest_tier:                                                                                             Habitability_Tier,
	rocky,
	temperate,
	earth_size,
	suitable_star,
	stable_orbit,
	atmosphere_retained,
	surface_water,
	long_term: bool,
}

habitability_assumptions :: proc(scenario: Habitability_Scenario) -> Habitability_Assumptions {
	switch scenario {
	case .Conservative:
		return {HABITABILITY_MODEL_VERSION, scenario, 0.25, 0.28, 0.25, 0.20, 0.001, 0.001}
	case .Evidence_Centered:
		return {HABITABILITY_MODEL_VERSION, scenario, 0.37, 0.33, 0.52, 0.48, 0.08, 0.04}
	case .Optimistic:
		return {HABITABILITY_MODEL_VERSION, scenario, 0.65, 0.65, 0.78, 0.72, 0.50, 0.20}
	}
	return {}
}

habitability_scenario_name :: proc(value: Habitability_Scenario) -> string {
	switch value {case .Conservative:
		return "conservative"; case .Evidence_Centered:
		return "evidence-centered"; case .Optimistic:
		return "optimistic"}
	return "unknown"
}

parse_habitability_scenario :: proc(value: string) -> (Habitability_Scenario, bool) {
	switch value {case "conservative":
		return .Conservative, true; case "evidence-centered", "centered":
		return .Evidence_Centered, true; case "optimistic":
		return .Optimistic, true}
	return .Evidence_Centered, false
}

habitability_tier_name :: proc(value: Habitability_Tier) -> string {
	switch value {
	case .Any_Planet:
		return "planet-hosting stars"
	case .Rocky:
		return "rocky planets"
	case .Temperate_Rocky:
		return "temperate rocky planets"
	case .Earth_Analogue:
		return "strict Earth analogues"
	case .Long_Term_Habitable:
		return "long-term habitable candidates"
	case .Potential_Biosphere:
		return "potential biospheres"
	case .Potential_Complex_Biosphere:
		return "potential complex biospheres"
	}
	return "unknown"
}

assess_planet_habitability :: proc(
	p: Planet,
	atmosphere_retained, surface_water, long_term: bool,
) -> Planet_Habitability_Assessment {
	a: Planet_Habitability_Assessment
	a.highest_tier = .Any_Planet
	density_relative := p.inputs.mass_earth / math.pow(p.inputs.radius_earth, 3)
	a.rocky = p.inputs.mass_earth <= 8 && p.inputs.radius_earth <= 1.8 && density_relative >= 0.45
	if !a.rocky do return a
	a.highest_tier = .Rocky
	a.temperate = p.stellar_flux_earth >= 0.35 && p.stellar_flux_earth <= 1.10
	if !a.temperate do return a
	a.highest_tier = .Temperate_Rocky
	a.earth_size = p.inputs.radius_earth >= 0.8 && p.inputs.radius_earth <= 1.25
	a.suitable_star =
		p.star.mass_solar >= 0.6 && p.star.mass_solar <= 1.2 && p.star.age_billion_years >= 1
	a.stable_orbit = p.orbit_stable && p.inputs.eccentricity <= 0.20
	if !(a.earth_size && a.suitable_star && a.stable_orbit) do return a
	a.highest_tier = .Earth_Analogue
	a.atmosphere_retained = atmosphere_retained
	a.surface_water = surface_water
	a.long_term = long_term
	if atmosphere_retained && surface_water && long_term do a.highest_tier = .Long_Term_Habitable
	return a
}

habitability_sample_mass :: proc(state: ^u64) -> f64 {
	u := planet_random_unit(state)
	if u < 0.72 do return planet_random_range(state, 0.10, 0.60)
	if u < 0.88 do return planet_random_range(state, 0.60, 0.90)
	if u < 0.97 do return planet_random_range(state, 0.90, 1.10)
	return planet_random_range(state, 1.10, 1.40)
}

habitability_sample_one :: proc(
	state: ^u64,
	n: Galactic_Neighborhood,
	assumptions: Habitability_Assumptions,
) -> [len(Habitability_Tier)]bool {
	result: [len(Habitability_Tier)]bool
	sampled_seed := planet_rng_next(state)
	stellar := generate_stellar_population(
		sampled_seed,
		n.mean_age_billion_years,
		n.metallicity_dex,
	)
	mass := stellar.stars[0].initial_mass_solar
	close_binary :=
		stellar.star_count == 2 &&
		stellar.binary_bound &&
		stellar.binary_orbit.semi_major_axis_au < 10
	metal_factor := clamp(math.pow(10.0, n.metallicity_dex * 0.18), 0.55, 1.35)
	radiation_factor := clamp(1 / (1 + n.radiation_risk * 0.35), 0.35, 1.0)
	disk_factor := planet_random_range(state, 0.70, 1.30) * metal_factor
	host_probability := clamp((0.62 + 0.18 * disk_factor) * (close_binary ? 0.42 : 1), 0.08, 0.94)
	if planet_random_unit(state) >= host_probability do return result
	result[int(Habitability_Tier.Any_Planet)] = true

	rocky_probability := clamp(
		0.74 - 0.12 * max(mass - 1, 0) + 0.08 * (1 - metal_factor),
		0.35,
		0.88,
	)
	if planet_random_unit(state) >= rocky_probability do return result
	result[int(Habitability_Tier.Rocky)] = true

	eta := mass < 0.6 ? assumptions.eta_rocky_hz_m : assumptions.eta_rocky_hz_gk
	// eta is planets per star; conditioning on an existing rocky system converts it to a bounded event probability.
	temperate_probability := clamp(
		eta / max(host_probability * rocky_probability, 0.05) * radiation_factor,
		0,
		0.98,
	)
	if planet_random_unit(state) >= temperate_probability do return result
	result[int(Habitability_Tier.Temperate_Rocky)] = true

	radius := planet_random_range(state, 0.55, 1.55)
	flux := planet_random_range(state, 0.35, 1.10)
	eccentricity := planet_random_range(state, 0, close_binary ? 0.45 : 0.28)
	star_ok := mass >= 0.6 && mass <= 1.2
	earth_analogue :=
		radius >= 0.8 &&
		radius <= 1.25 &&
		flux >= 0.75 &&
		flux <= 1.10 &&
		eccentricity <= 0.20 &&
		star_ok &&
		n.mean_age_billion_years >= 1
	if !earth_analogue do return result
	result[int(Habitability_Tier.Earth_Analogue)] = true

	volatile_latent := disk_factor * planet_random_range(state, 0.35, 1.65)
	escape_factor := clamp(0.65 + 0.25 * mass, 0.5, 1.0) * radiation_factor
	atmosphere := planet_random_unit(state) < assumptions.atmosphere_retention * escape_factor
	water := planet_random_unit(state) < clamp(0.58 * volatile_latent, 0.05, 0.92)
	climate := planet_random_unit(state) < assumptions.climate_persistence * radiation_factor
	if !(atmosphere && water && climate) do return result
	result[int(Habitability_Tier.Long_Term_Habitable)] = true
	if planet_random_unit(state) >= assumptions.abiogenesis do return result
	result[int(Habitability_Tier.Potential_Biosphere)] = true
	if planet_random_unit(state) < assumptions.complex_life do result[int(Habitability_Tier.Potential_Complex_Biosphere)] = true
	return result
}

habitability_percentile :: proc(values: ^[HABITABILITY_BATCHES]f64, fraction: f64) -> f64 {
	copy_values := values^
	for i in 1 ..< HABITABILITY_BATCHES {
		value := copy_values[i]
		j := i
		for j > 0 && copy_values[j - 1] > value {copy_values[j] = copy_values[j - 1]; j -= 1}
		copy_values[j] = value
	}
	index := clamp(
		int(math.round(fraction * f64(HABITABILITY_BATCHES - 1))),
		0,
		HABITABILITY_BATCHES - 1,
	)
	return copy_values[index]
}

estimate_galaxy_habitability :: proc(
	g: ^Galaxy,
	scenario: Habitability_Scenario,
	sample_count: int,
) -> Galaxy_Habitability_Report {
	report := Galaxy_Habitability_Report {
		seed          = g.seed,
		model_version = HABITABILITY_MODEL_VERSION,
		scenario      = scenario,
		star_count    = g.estimated_star_count,
	}
	samples := max(sample_count, HABITABILITY_BATCHES)
	report.sample_count = samples
	report.cell_count = g.neighborhood_count
	assumptions := habitability_assumptions(scenario)
	state: u64 = g.seed ~ u64(int(scenario) + 1) * 0x9e3779b97f4a7c15
	batch_rates: [len(Habitability_Tier)][HABITABILITY_BATCHES]f64
	overall_counts: [len(Habitability_Tier)]int
	batch_size := max(samples / HABITABILITY_BATCHES, 1)
	actual_samples := batch_size * HABITABILITY_BATCHES
	report.sample_count = actual_samples
	for batch in 0 ..< HABITABILITY_BATCHES {
		counts: [len(Habitability_Tier)]int
		for draw in 0 ..< batch_size {
			neighborhood_index := (batch * batch_size + draw) % g.neighborhood_count
			n := g.neighborhoods[neighborhood_index]
			outcomes := habitability_sample_one(&state, n, assumptions)
			cell := &report.cells[neighborhood_index]
			cell.neighborhood_index = neighborhood_index
			cell.samples += 1
			for passed, tier in outcomes {
				if passed {counts[tier] += 1; overall_counts[tier] += 1; cell.rates[tier] += 1}
			}
		}
		for count, tier in counts do batch_rates[tier][batch] = f64(count) / f64(batch_size)
	}
	stars_per_cell := f64(g.estimated_star_count) / f64(max(g.neighborhood_count, 1))
	for &cell in report.cells[:report.cell_count] {
		cell.stars_represented = stars_per_cell
		if cell.samples > 0 do for &rate in cell.rates do rate /= f64(cell.samples)
	}
	for tier in 0 ..< len(Habitability_Tier) {
		rate_median := f64(overall_counts[tier]) / f64(actual_samples)
		low_rate := habitability_percentile(&batch_rates[tier], 0.05)
		high_rate := habitability_percentile(&batch_rates[tier], 0.95)
		if overall_counts[tier] < HABITABILITY_BATCHES {
			count := f64(overall_counts[tier])
			low_rate = max(0, count - 1.645 * math.sqrt(count)) / f64(actual_samples)
			high_rate = (count + 1.645 * math.sqrt(count + 1)) / f64(actual_samples)
		}
		report.tiers[tier] = {
			median        = rate_median * f64(g.estimated_star_count),
			low_5         = low_rate * f64(g.estimated_star_count),
			high_95       = high_rate * f64(g.estimated_star_count),
			rate_per_star = rate_median,
		}
	}
	return report
}
