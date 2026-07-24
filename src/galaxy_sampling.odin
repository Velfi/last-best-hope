package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"
import "core:time"

galaxy_sample_spiral_theta :: proc(g: ^game.Galaxy, star_index: int, radius: f64) -> f64 {
	// Rejection-sample the Cox-Gomez density perturbation over the underlying
	// exponential disk. Attempts and random channels are fixed, so the stellar
	// plate remains deterministic for a supplied seed.
	C_SUM :: 8.0 / (3.0 * math.PI) + .5 + 8.0 / (15.0 * math.PI)
	AMPLITUDE :: 1.15
	ceiling := 1 + AMPLITUDE * galaxy_spiral_arm_envelope(g, radius) * 1.15 * C_SUM
	fallback := galaxy_star_unit(g.seed, star_index, 80) * 2 * math.PI
	for attempt in 0 ..< 10 {
		theta := galaxy_star_unit(g.seed, star_index, 80 + attempt * 2) * 2 * math.PI
		accept := galaxy_star_unit(g.seed, star_index, 81 + attempt * 2)
		if accept * ceiling <= galaxy_spiral_relative_density(g, radius, theta) do return theta
		fallback = theta
	}
	return fallback
}

// An exponential disk describes surface density, Sigma(R) ~ exp(-R/h).
// The probability of finding a representative star in an annulus therefore
// includes its area: p(R) ~ R exp(-R/h), with the CDF below.
galaxy_exponential_disk_cdf :: proc(radius, scale_length: f64) -> f64 {
	return game.galaxy_exponential_disk_cdf(radius, scale_length)
}

galaxy_sample_exponential_disk :: proc(u, scale_length, limit: f64) -> f64 {
	return game.sample_truncated_exponential_disk_radius(u, scale_length, limit)
}

galaxy_outer_disk_taper :: proc(radius_fraction: f64) -> f64 {
	// Preserve the exponential body through 0.80R, then smoothly truncate its
	// surface density to zero at the survey radius instead of clipping a hard rim.
	t := clamp((1 - radius_fraction) / .20, 0.0, 1.0)
	return t * t * (3 - 2 * t)
}

galaxy_sample_tapered_exponential_disk :: proc(
	g: ^game.Galaxy,
	star_index: int,
	scale_length, limit: f64,
) -> f64 {
	// Rejection sampling renormalizes the tapered disk, so every cached entry
	// remains a real rendered star. Fixed channels and attempts preserve seeded
	// determinism; the fallback lies inside the untapered body.
	for attempt in 0 ..< 12 {
		rank_channel := attempt == 0 ? 0 : 120 + attempt * 2
		rank := galaxy_star_unit(g.seed, star_index, rank_channel)
		radius := galaxy_sample_exponential_disk(rank, scale_length, limit)
		accept := galaxy_star_unit(g.seed, star_index, 121 + attempt * 2)
		if accept <= galaxy_outer_disk_taper(radius / max(limit, .01)) do return radius
	}
	return galaxy_sample_exponential_disk(
		galaxy_star_unit(g.seed, star_index, 149),
		scale_length,
		limit * .8,
	)
}

galaxy_outer_disk_taper_is_smooth_and_reduces_edge_population :: proc(t: ^testing.T) {
	testing.expect_value(t, galaxy_outer_disk_taper(0), f64(1))
	testing.expect_value(t, galaxy_outer_disk_taper(.8), f64(1))
	testing.expect_value(t, galaxy_outer_disk_taper(1), f64(0))
	g := game.Galaxy {
		seed            = 5719,
		morphology      = .Spiral,
		disk_radius_kpc = 10,
	}
	scale_length := g.disk_radius_kpc / 3.2
	tapered_outer, raw_outer := 0, 0
	for i in 0 ..< 1024 {
		tapered := galaxy_sample_tapered_exponential_disk(&g, i, scale_length, g.disk_radius_kpc)
		raw := galaxy_sample_exponential_disk(
			galaxy_star_unit(g.seed, i, 0),
			scale_length,
			g.disk_radius_kpc,
		)
		testing.expect(t, tapered >= 0 && tapered <= g.disk_radius_kpc)
		testing.expect_value(
			t,
			galaxy_sample_tapered_exponential_disk(&g, i, scale_length, g.disk_radius_kpc),
			tapered,
		)
		if tapered > g.disk_radius_kpc * .92 do tapered_outer += 1
		if raw > g.disk_radius_kpc * .92 do raw_outer += 1
	}
	testing.expect(t, tapered_outer * 3 < raw_outer)
}

// For a projected Sersic profile, x=b_n(R/R_e)^(1/n) follows Gamma(2n, 1).
// We use n=2 for a moderately concentrated elliptical, whose integer-shape
// Gamma CDF is cheap to invert without a frame-dependent rejection loop.
galaxy_sersic_n2_cdf_x :: proc(x: f64) -> f64 {
	return game.galaxy_sersic_n2_cdf_x(x)
}

galaxy_sample_sersic_n2 :: proc(u, effective_radius, limit: f64) -> f64 {
	return game.sample_truncated_sersic_n2_radius(u, effective_radius, limit)
}

galaxy_sample_sersic :: proc(u, effective_radius, limit: f64, n: int) -> f64 {
	return game.sample_truncated_sersic_integer_radius(u, effective_radius, limit, n)
}

galaxy_sersic_relative_intensity :: proc(radius, effective_radius: f64, n: int) -> f64 {
	clamped_n := clamp(n, 1, 4)
	b_n := game.galaxy_sersic_b_n(clamped_n)
	ratio := max(radius, 0) / max(effective_radius, 1.0e-9)
	return math.exp(-b_n * (math.pow(ratio, 1 / f64(clamped_n)) - 1))
}

// A projected Ferrers bar has finite support inside elliptical radius m=1:
// Sigma(m) ~ (1-m^2)^n. Including annular area makes t=m^2 follow a
// Beta(1,n+1) distribution, so it has this direct inverse transform.
galaxy_sample_ferrers_m :: proc(u: f64, order: f64 = 2) -> f64 {
	return game.sample_ferrers_elliptical_radius(u, order)
}

galaxy_render_star_count :: proc(g: ^game.Galaxy) -> int {
	population_log := math.log10(max(f64(g.estimated_star_count), 1.0e7))
	return int(clamp(18000 + (population_log - 8) * 10500, 18000.0, f64(MAX_GALAXY_RENDER_STARS)))
}

galaxy_stellar_density_noise :: proc(g: ^game.Galaxy, x, y, cell_size: f64, channel: int) -> f64 {
	// Smooth value noise supplies associations and voids in world space. Keeping
	// the lattice independent of render tiles prevents seams during navigation.
	safe_cell_size := max(cell_size, 1.0e-6)
	gx, gy := x / safe_cell_size, y / safe_cell_size
	ix, iy := int(math.floor(gx)), int(math.floor(gy))
	tx, ty := gx - f64(ix), gy - f64(iy)
	sx, sy := tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
	corner :: proc(g: ^game.Galaxy, x, y, channel: int) -> f64 {
		// Galaxy coordinates occupy only a few dozen cells; the bias makes the
		// signed lattice coordinates explicit before packing them into the hash.
		key := (y + 4096) * 8192 + (x + 4096)
		return galaxy_star_unit(g.seed, key, channel)
	}
	a := corner(g, ix, iy, channel)
	b := corner(g, ix + 1, iy, channel)
	c := corner(g, ix, iy + 1, channel)
	d := corner(g, ix + 1, iy + 1, channel)
	lower := a + (b - a) * sx
	upper := c + (d - c) * sx
	return lower + (upper - lower) * sy
}

galaxy_stellar_association_modulation :: proc(g: ^game.Galaxy, x, y: f64) -> f64 {
	if g.morphology != .Spiral && g.morphology != .Barred_Spiral do return 1
	// Giant stellar complexes sit inside broader star-forming regions. Both
	// octaves have expectation 0.5, so this redistributes stars without changing
	// the expected population of the exponential disk.
	coarse := galaxy_stellar_density_noise(g, x, y, g.disk_radius_kpc * .14, 120)
	fine := galaxy_stellar_density_noise(g, x, y, g.disk_radius_kpc * .055, 121)
	field := coarse * .68 + fine * .32
	return .43 + 1.14 * field
}

@(test)
galaxy_stellar_associations_are_seeded_continuous_and_mean_preserving :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed            = 0x51a7,
		morphology      = .Spiral,
		disk_radius_kpc = 14,
	}
	x, y := 2.7, -1.9
	value := galaxy_stellar_association_modulation(&g, x, y)
	testing.expect_value(t, galaxy_stellar_association_modulation(&g, x, y), value)
	testing.expect(t, value >= .43 && value <= 1.57)
	nearby := galaxy_stellar_association_modulation(&g, x + .001, y - .001)
	testing.expect(t, math.abs(value - nearby) < .01)
	sum := f64(0)
	for iy in 0 ..< 41 {
		for ix in 0 ..< 41 {
			sx := -g.disk_radius_kpc + 2 * g.disk_radius_kpc * f64(ix) / 40
			sy := -g.disk_radius_kpc + 2 * g.disk_radius_kpc * f64(iy) / 40
			sum += galaxy_stellar_association_modulation(&g, sx, sy)
		}
	}
	mean := sum / (41 * 41)
	testing.expect(t, mean > .90 && mean < 1.10)
	g.morphology = .Elliptical
	testing.expect_value(t, galaxy_stellar_association_modulation(&g, x, y), f64(1))
}

@(test)
galaxy_render_star_count_is_large_bounded_and_population_weighted :: proc(t: ^testing.T) {
	dwarf := game.Galaxy {
		estimated_star_count = 10_000_000,
	}
	milky_way := game.Galaxy {
		estimated_star_count = 100_000_000_000,
	}
	giant := game.Galaxy {
		estimated_star_count = 10_000_000_000_000,
	}
	testing.expect_value(t, galaxy_render_star_count(&dwarf), 18000)
	testing.expect(t, galaxy_render_star_count(&milky_way) > 48000)
	testing.expect(t, galaxy_render_star_count(&milky_way) < MAX_GALAXY_RENDER_STARS)
	testing.expect_value(t, galaxy_render_star_count(&giant), MAX_GALAXY_RENDER_STARS)
}

galaxy_lod_local_density :: proc(g: ^game.Galaxy, x, y: f64) -> (density, structure: f64) {
	radius := math.sqrt(x * x + y * y)
	if radius > g.disk_radius_kpc do return
	switch g.morphology {
	case .Spiral, .Barred_Spiral:
		theta := math.atan2(y, x)
		scale_length := g.disk_radius_kpc / 3.2
		disk_density :=
			math.exp(-radius / max(scale_length, .01)) *
			galaxy_outer_disk_taper(radius / max(g.disk_radius_kpc, .01))
		arm_tracing_fraction := galaxy_total_arm_tracing_fraction(g)
		arm_density := galaxy_spiral_relative_density(g, radius, theta)
		association := galaxy_stellar_association_modulation(g, x, y)
		density =
			disk_density *
			((1 - arm_tracing_fraction) + arm_tracing_fraction * arm_density) /
			1.30 *
			association
		structure = clamp(arm_density - 1, 0.0, 1.5)
		structure = max(structure, max(association - 1, 0.0) * .42)
		if g.morphology == .Barred_Spiral {
			ring_density := galaxy_bar_inner_ring_density(g, x, y)
			density += .62 * ring_density
			structure = max(structure, ring_density)
		}
	case .Elliptical:
		n := galaxy_sersic_index(g)
		b_n := game.galaxy_sersic_b_n(n)
		effective_radius := max(g.disk_radius_kpc * .24, .01)
		normalized_radius := radius / effective_radius
		reference := math.pow(.35, 1 / f64(n))
		// Normalize at 0.35 R_e. The global plate owns total luminosity; this
		// normalization only provides useful local detail at navigation zooms.
		density = .38 * math.exp(-b_n * (math.pow(normalized_radius, 1 / f64(n)) - reference))
		structure = clamp(density, 0.0, 1.0)
	case .Dwarf_Irregular:
		radius_fraction := radius / max(g.disk_radius_kpc, .01)
		diffuse := .08 * (1 - radius_fraction)
		strongest_clump := f64(0)
		for clump in 0 ..< galaxy_irregular_clump_count(g) {
			clump_radius := g.disk_radius_kpc * (.12 + .48 * galaxy_star_unit(g.seed, clump, 20))
			clump_angle := galaxy_star_unit(g.seed, clump, 21) * 2 * math.PI
			aspect := .68 + .64 * galaxy_star_unit(g.seed, clump, 22)
			sigma := galaxy_irregular_clump_sigma(g, clump)
			dx := (x - clump_radius * math.cos(clump_angle)) / aspect
			dy := (y - clump_radius * math.sin(clump_angle)) * aspect
			clump_density := math.exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
			strongest_clump = max(strongest_clump, clump_density)
		}
		density = diffuse + .52 * strongest_clump
		structure = strongest_clump
	}
	density = clamp(density, 0.0, 1.0)
	structure = clamp(structure, 0.0, 1.5)
	return
}

galaxy_lod_star_candidate :: proc(
	g: ^game.Galaxy,
	tile_x, tile_y, candidate: int,
) -> (
	x, y: f64,
	visible: bool,
	alpha: u8,
) {
	out_of_range :=
		tile_x < -GALAXY_LOD_TILE_RADIUS ||
		tile_x >= GALAXY_LOD_TILE_RADIUS ||
		tile_y < -GALAXY_LOD_TILE_RADIUS ||
		tile_y >= GALAXY_LOD_TILE_RADIUS ||
		candidate < 0 ||
		candidate >= GALAXY_LOD_STARS_PER_TILE
	if out_of_range do return
	tile_diameter := GALAXY_LOD_TILE_RADIUS * 2
	tile_key :=
		(tile_y + GALAXY_LOD_TILE_RADIUS) * tile_diameter + (tile_x + GALAXY_LOD_TILE_RADIUS)
	index := 1_000_000 + tile_key * GALAXY_LOD_STARS_PER_TILE + candidate
	tile_size := g.disk_radius_kpc / GALAXY_LOD_TILE_RADIUS
	x = (f64(tile_x) + galaxy_star_unit(g.seed, index, 110)) * tile_size
	y = (f64(tile_y) + galaxy_star_unit(g.seed, index, 111)) * tile_size
	luminosity_weighted_density, structure := galaxy_lod_local_density(g, x, y)
	accept := galaxy_star_unit(g.seed, index, 112)
	if accept >= clamp(luminosity_weighted_density, 0.0, 1.0) do return x, y, false, 0
	brightness_rank := galaxy_star_unit(g.seed, index, 113)
	structure_boost := clamp(structure * 12, 0.0, 18.0)
	alpha = galaxy_stellar_mark_alpha(brightness_rank, 22, 78, structure_boost)
	return x, y, true, alpha
}

galaxy_lod_star_height :: proc(
	g: ^game.Galaxy,
	tile_x, tile_y, candidate: int,
	radius: f64,
) -> f64 {
	if g.morphology != .Spiral && g.morphology != .Barred_Spiral do return 0
	tile_diameter := GALAXY_LOD_TILE_RADIUS * 2
	tile_key :=
		(tile_y + GALAXY_LOD_TILE_RADIUS) * tile_diameter + (tile_x + GALAXY_LOD_TILE_RADIUS)
	index := 1_000_000 + tile_key * GALAXY_LOD_STARS_PER_TILE + candidate
	return galaxy_sample_disk_height(
		galaxy_star_unit(g.seed, index, 114),
		galaxy_disk_scale_height(g, radius, false, false),
	)
}

@(test)
galaxy_lod_star_height_is_stable_for_disks_and_zero_for_spheroids :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed            = 914,
		morphology      = .Spiral,
		disk_radius_kpc = 10,
	}
	height := galaxy_lod_star_height(&g, -3, 5, 81, 6)
	testing.expect_value(t, galaxy_lod_star_height(&g, -3, 5, 81, 6), height)
	testing.expect(t, math.abs(height) < g.disk_radius_kpc * .25)
	g.morphology = .Elliptical
	testing.expect_value(t, galaxy_lod_star_height(&g, -3, 5, 81, 6), f64(0))
}

galaxy_young_arm_fraction :: proc(g: ^game.Galaxy) -> f64 {
	if g.morphology != .Spiral && g.morphology != .Barred_Spiral do return 0
	mass_units := g.stellar_mass_solar / 1.0e10
	specific_activity := g.star_formation_rate_solar_masses_year / max(mass_units, .01)
	// This is a luminosity-weighted rendering fraction, not a stellar mass
	// fraction: short-lived young stars contribute disproportionate visible light.
	return clamp(.32 + .18 * specific_activity, .32, .62)
}

galaxy_old_disk_arm_response :: proc(g: ^game.Galaxy) -> f64 {
	if g.morphology != .Spiral && g.morphology != .Barred_Spiral do return 0
	// A spiral density wave perturbs old disk stars as well as illuminating young
	// associations. Keep that response weak so the inter-arm disk remains real.
	return .16
}

galaxy_total_arm_tracing_fraction :: proc(g: ^game.Galaxy) -> f64 {
	young := galaxy_young_arm_fraction(g)
	return young + (1 - young) * galaxy_old_disk_arm_response(g)
}

@(test)
galaxy_ring_tessellation_tracks_zoom_and_view_intersection :: proc(t: ^testing.T) {
	testing.expect_value(t, galaxy_ring_segment_count(0, 100), 96)
	wide := galaxy_ring_segment_count(5, 20)
	close := galaxy_ring_segment_count(5, 800)
	testing.expect(t, wide >= 96 && close > wide && close <= 2048)
	testing.expect_value(t, galaxy_ring_segment_count(100, 1000), 2048)
	testing.expect(
		t,
		galaxy_segment_intersects_view(
			V(GALAXY_VIEW.x + 10, GALAXY_VIEW.y + 10),
			V(GALAXY_VIEW.x + 20, GALAXY_VIEW.y + 20),
		),
	)
	testing.expect(
		t,
		galaxy_segment_intersects_view(
			V(GALAXY_VIEW.x - 20, GALAXY_VIEW.y + 20),
			V(GALAXY_VIEW.x + 20, GALAXY_VIEW.y + 20),
		),
	)
	testing.expect(
		t,
		!galaxy_segment_intersects_view(
			V(GALAXY_VIEW.x - 30, GALAXY_VIEW.y),
			V(GALAXY_VIEW.x - 20, GALAXY_VIEW.y + 20),
		),
	)
	empty := galaxy_semantic_ring_visibility(0, 0)
	disk := galaxy_semantic_ring_visibility(.35, .2)
	core := galaxy_semantic_ring_visibility(1, 1.5)
	testing.expect_value(t, empty, f32(1))
	testing.expect(t, empty > disk && disk > core)
	testing.expect_value(t, core, f32(.26))
}

@(test)
galaxy_exponential_disk_sampler_inverts_truncated_surface_density :: proc(t: ^testing.T) {
	h, limit := 3.1, 12.7
	limit_cdf := galaxy_exponential_disk_cdf(limit, h)
	previous := f64(-1)
	samples := [?]f64{0, .01, .1, .25, .5, .75, .9, .99, 1}
	for u in samples {
		radius := galaxy_sample_exponential_disk(u, h, limit)
		testing.expect(t, radius >= previous && radius >= 0 && radius <= limit)
		testing.expect(
			t,
			math.abs(galaxy_exponential_disk_cdf(radius, h) - u * limit_cdf) < 2.0e-6,
		)
		previous = radius
	}
}

@(test)
galaxy_sersic_n2_sampler_inverts_projected_light_profile :: proc(t: ^testing.T) {
	B_N :: 3.67206075
	effective_radius, limit := 2.4, 13.0
	x_limit := B_N * math.sqrt(limit / effective_radius)
	limit_cdf := galaxy_sersic_n2_cdf_x(x_limit)
	previous := f64(-1)
	samples := [?]f64{0, .01, .1, .25, .5, .75, .9, .99, 1}
	for u in samples {
		radius := galaxy_sample_sersic_n2(u, effective_radius, limit)
		x := B_N * math.sqrt(radius / effective_radius)
		testing.expect(t, radius >= previous && radius >= 0 && radius <= limit)
		testing.expect(t, math.abs(galaxy_sersic_n2_cdf_x(x) - u * limit_cdf) < 2.0e-6)
		previous = radius
	}
}

@(test)
galaxy_integer_sersic_sampler_inverts_projected_light_profiles :: proc(t: ^testing.T) {
	effective_radius, limit := 2.4, 13.0
	for n in 1 ..= 4 {
		b_n := game.galaxy_sersic_b_n(n)
		x_limit := b_n * math.pow(limit / effective_radius, 1 / f64(n))
		limit_cdf := game.galaxy_sersic_integer_cdf_x(x_limit, n)
		previous := f64(-1)
		samples := [?]f64{0, .01, .1, .25, .5, .75, .9, .99, 1}
		for u in samples {
			radius := galaxy_sample_sersic(u, effective_radius, limit, n)
			x := b_n * math.pow(radius / effective_radius, 1 / f64(n))
			testing.expect(t, radius >= previous && radius >= 0 && radius <= limit)
			testing.expect(
				t,
				math.abs(game.galaxy_sersic_integer_cdf_x(x, n) - u * limit_cdf) < 3.0e-6,
			)
			previous = radius
		}
	}
}

@(test)
galaxy_sersic_isophote_intensity_is_normalized_and_monotonic :: proc(t: ^testing.T) {
	effective_radius := 2.4
	for n in 1 ..= 4 {
		testing.expect(
			t,
			math.abs(galaxy_sersic_relative_intensity(effective_radius, effective_radius, n) - 1) <
			1.0e-12,
		)
		previous := galaxy_sersic_relative_intensity(0, effective_radius, n)
		for step in 1 ..= 32 {
			radius := effective_radius * 4 * f64(step) / 32
			intensity := galaxy_sersic_relative_intensity(radius, effective_radius, n)
			testing.expect(t, intensity > 0 && intensity < previous)
			previous = intensity
		}
	}
	testing.expect(
		t,
		galaxy_sersic_relative_intensity(4 * effective_radius, effective_radius, 4) >
		galaxy_sersic_relative_intensity(4 * effective_radius, effective_radius, 2),
	)
}

@(test)
galaxy_ferrers_sampler_respects_finite_bar_density :: proc(t: ^testing.T) {
	order := f64(2)
	previous := f64(-1)
	samples := [?]f64{0, .01, .1, .25, .5, .75, .9, .99, 1}
	for u in samples {
		m := galaxy_sample_ferrers_m(u, order)
		cdf := 1 - math.pow(1 - m * m, order + 1)
		testing.expect(t, m >= previous && m >= 0 && m <= 1)
		testing.expect(t, math.abs(cdf - u) < 1.0e-10)
		previous = m
	}
}

@(test)
galaxy_logarithmic_spiral_preserves_pitch_and_arm_separation :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed                 = 0x51a7,
		disk_radius_kpc      = 14,
		spiral_arm_count     = 4,
		spiral_pitch_degrees = 10,
	}
	previous := galaxy_spiral_theta(&g, 0, .1)
	handedness := galaxy_spiral_handedness(&g)
	radii := [?]f64{.5, 1, 2, 4, 8, 14}
	for radius in radii {
		theta := galaxy_spiral_theta(&g, 0, radius)
		testing.expect(t, (theta - previous) * handedness > 0)
		expected_slope := handedness * radius * math.tan(g.spiral_pitch_degrees * math.PI / 180)
		testing.expect(t, math.abs(galaxy_spiral_dr_dtheta(&g, radius) - expected_slope) < 1.0e-10)
		separation := galaxy_spiral_theta(&g, 1, radius) - theta
		testing.expect(t, math.abs(separation - math.PI / 2) < 1.0e-10)
		previous = theta
	}
}

@(test)
galaxy_spiral_handedness_is_balanced_seeded_and_discrete :: proc(t: ^testing.T) {
	seen_left, seen_right := false, false
	for seed in u64(1) ..= u64(128) {
		g := game.Galaxy {
			seed       = seed,
			morphology = .Spiral,
		}
		handedness := galaxy_spiral_handedness(&g)
		testing.expect(t, handedness == -1 || handedness == 1)
		testing.expect_value(t, galaxy_spiral_handedness(&g), handedness)
		seen_left = seen_left || handedness < 0
		seen_right = seen_right || handedness > 0
	}
	testing.expect(t, seen_left && seen_right)
}

@(test)
galaxy_cox_gomez_density_peaks_on_arms_and_tapers_at_edges :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed                 = 0x51a7,
		disk_radius_kpc      = 14,
		spiral_arm_count     = 3,
		spiral_pitch_degrees = 18,
	}
	radius := g.disk_radius_kpc * .45
	arm_theta := galaxy_spiral_theta(&g, 0, radius)
	interarm_theta := arm_theta + math.PI / f64(g.spiral_arm_count)
	testing.expect(t, galaxy_spiral_relative_density(&g, radius, arm_theta) > 1)
	testing.expect(t, galaxy_spiral_relative_density(&g, radius, interarm_theta) < 1)
	testing.expect(t, galaxy_spiral_arm_envelope(&g, 0) == 0)
	testing.expect(t, galaxy_spiral_arm_envelope(&g, g.disk_radius_kpc) == 0)
	for arm in 0 ..< g.spiral_arm_count {
		theta := galaxy_spiral_theta(&g, arm, radius)
		testing.expect(
			t,
			math.abs(
				galaxy_spiral_harmonic(galaxy_spiral_gamma(&g, radius, theta)) -
				galaxy_spiral_harmonic(0),
			) <
			1.0e-10,
		)
	}
}

@(test)
galaxy_spiral_coherence_is_bounded_seeded_and_arm_specific :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed                 = 0x51a7,
		disk_radius_kpc      = 14,
		spiral_arm_count     = 4,
		spiral_pitch_degrees = 18,
	}
	varied := false
	for arm in 0 ..< g.spiral_arm_count {
		previous := galaxy_spiral_arm_coherence(&g, arm, 0)
		for step in 0 ..= 32 {
			radius := g.disk_radius_kpc * f64(step) / 32
			coherence := galaxy_spiral_arm_coherence(&g, arm, radius)
			testing.expect(t, coherence >= .45 && coherence <= 1.15)
			testing.expect_value(t, galaxy_spiral_arm_coherence(&g, arm, radius), coherence)
			if math.abs(coherence - previous) > .01 do varied = true
			arm_theta := galaxy_spiral_theta(&g, arm, radius)
			testing.expect_value(t, galaxy_nearest_spiral_arm(&g, radius, arm_theta), arm)
			previous = coherence
		}
	}
	testing.expect(t, varied)
}

@(test)
galaxy_morphology_projection_and_irregular_clumps_are_seeded_and_bounded :: proc(t: ^testing.T) {
	seen_clump_counts: [5]bool
	seen_sersic_indices: [3]bool
	min_sigma, max_sigma := f64(1.0e9), f64(0)
	for seed in u64(1) ..= u64(128) {
		g := game.Galaxy {
			seed       = seed,
			morphology = .Elliptical,
		}
		aspect := galaxy_map_y_aspect(&g)
		testing.expect(t, aspect >= .66 && aspect <= .86)
		testing.expect_value(t, galaxy_map_y_aspect(&g), aspect)
		sersic_n := galaxy_sersic_index(&g)
		testing.expect(t, sersic_n >= 2 && sersic_n <= 4)
		seen_sersic_indices[sersic_n - 2] = true
		irregular := game.Galaxy {
			seed            = seed,
			morphology      = .Dwarf_Irregular,
			disk_radius_kpc = 10,
		}
		irregular_aspect := galaxy_map_y_aspect(&irregular)
		testing.expect(t, irregular_aspect >= .68 && irregular_aspect <= .86)
		clump_count := galaxy_irregular_clump_count(&irregular)
		testing.expect(t, clump_count >= 3 && clump_count <= 7)
		seen_clump_counts[clump_count - 3] = true
		for clump in 0 ..< clump_count {
			sigma := galaxy_irregular_clump_sigma(&irregular, clump)
			testing.expect(t, sigma >= .65 && sigma <= 1.10)
			testing.expect_value(t, galaxy_irregular_clump_sigma(&irregular, clump), sigma)
			min_sigma, max_sigma = min(min_sigma, sigma), max(max_sigma, sigma)
		}
	}
	testing.expect(t, max_sigma - min_sigma > .40)
	for seen in seen_clump_counts do testing.expect(t, seen)
	for seen in seen_sersic_indices do testing.expect(t, seen)
	spiral := game.Galaxy {
		seed       = 9,
		morphology = .Spiral,
	}
	testing.expect(t, galaxy_map_y_aspect(&spiral) >= .58 && galaxy_map_y_aspect(&spiral) <= .96)
}

@(test)
galaxy_rotated_projection_round_trips_and_varies_by_seed :: proc(t: ^testing.T) {
	seen_elliptical_angles: [8]bool
	morphologies := [?]game.Galaxy_Morphology {
		.Elliptical,
		.Dwarf_Irregular,
		.Spiral,
		.Barred_Spiral,
	}
	for seed in u64(1) ..= u64(128) {
		for morphology in morphologies {
			g := game.Galaxy {
				seed       = seed,
				morphology = morphology,
			}
			angle := galaxy_map_position_angle(&g)
			testing.expect(t, angle >= 0 && angle < 2 * math.PI)
			projected_x, projected_y := galaxy_project_world_delta(&g, 3.25, -1.75)
			x, y := galaxy_unproject_world_delta(&g, projected_x, projected_y)
			testing.expect(t, math.abs(x - 3.25) < 1.0e-10)
			testing.expect(t, math.abs(y + 1.75) < 1.0e-10)
		}
		elliptical := game.Galaxy {
			seed       = seed,
			morphology = .Elliptical,
		}
		bucket := min(int(galaxy_map_position_angle(&elliptical) / math.PI * 8), 7)
		seen_elliptical_angles[bucket] = true
	}
	for seen in seen_elliptical_angles do testing.expect(t, seen)
	spiral := game.Galaxy {
		seed       = 9,
		morphology = .Spiral,
	}
	testing.expect(
		t,
		galaxy_map_position_angle(&spiral) >= 0 && galaxy_map_position_angle(&spiral) < math.PI,
	)
}
