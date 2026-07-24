package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"
import "core:time"

GALAXY_VIEW :: rl.Rectangle{24, 104, 880, 536}
planet_detail_benchmark_time: f32 = -1
planet_detail_atmosphere_cpu_ms: f64
planet_detail_benchmark_system: game.Solar_System

// The wide plate is an explicit deterministic point catalogue. Sixty thousand
// marks is dense enough for the galaxy to read as a stellar aggregate at the
// default view while remaining comfortably inside the immediate-mode budget.
MAX_GALAXY_RENDER_STARS :: 60000
GALAXY_LOD_TILE_RADIUS :: 40
// Local catalogue candidates are evaluated only for visible world tiles. The
// The projected-tile cull limits evaluation to visible world plates, allowing
// resolved arms, rings, and knots to carry substantially more real stars.
GALAXY_LOD_STARS_PER_TILE :: 768
Galaxy_Render_Star :: struct {
	x, y, z: f32,
	alpha:   u8,
	size:    u8,
}

galaxy_map_scale :: proc(s: ^Ux_State) -> f64 {
	return(
		f64(min(GALAXY_VIEW.width, GALAXY_VIEW.height)) *
		0.46 /
		max(s.galaxy.disk_radius_kpc, 0.01) *
		s.galaxy_zoom \
	)
}

galaxy_map_y_aspect :: proc(g: ^game.Galaxy) -> f64 {
	switch g.morphology {
	case .Elliptical:
		return .66 + .20 * galaxy_star_unit(g.seed, 0, 60)
	case .Dwarf_Irregular:
		return .68 + .18 * galaxy_star_unit(g.seed, 0, 61)
	case .Spiral, .Barred_Spiral:
		// Uniform in cos(inclination), limited to moderately inclined survey
		// plates so the map remains navigable and never collapses edge-on.
		return .58 + .38 * galaxy_star_unit(g.seed, 0, 64)
	}
	return 1
}

galaxy_map_position_angle :: proc(g: ^game.Galaxy) -> f64 {
	switch g.morphology {
	case .Elliptical:
		return galaxy_star_unit(g.seed, 0, 62) * math.PI
	case .Dwarf_Irregular:
		return galaxy_star_unit(g.seed, 0, 63) * 2 * math.PI
	case .Spiral, .Barred_Spiral:
		return galaxy_star_unit(g.seed, 0, 65) * math.PI
	}
	return 0
}

galaxy_project_ellipse :: proc(
	g: ^game.Galaxy,
	intrinsic_angle, intrinsic_aspect: f64,
) -> (
	major_scale, minor_scale, projected_angle: f64,
) {
	// Project the two intrinsic semiaxis vectors, then recover the screen-space
	// ellipse from the eigenvalues/eigenvector of U*U' + V*V'. This keeps a thin
	// Ferrers bar consistent with the inclined disk instead of merely rotating it.
	ux, uy := galaxy_project_world_delta(g, math.cos(intrinsic_angle), math.sin(intrinsic_angle))
	vx, vy := galaxy_project_world_delta(
		g,
		-math.sin(intrinsic_angle) * intrinsic_aspect,
		math.cos(intrinsic_angle) * intrinsic_aspect,
	)
	xx, yy := ux * ux + vx * vx, uy * uy + vy * vy
	xy := ux * uy + vx * vy
	discriminant := math.sqrt(max((xx - yy) * (xx - yy) + 4 * xy * xy, 0.0))
	lambda_major := max((xx + yy + discriminant) * .5, 0.0)
	lambda_minor := max((xx + yy - discriminant) * .5, 0.0)
	major_scale, minor_scale = math.sqrt(lambda_major), math.sqrt(lambda_minor)
	projected_angle = .5 * math.atan2(2 * xy, xx - yy)
	return
}

galaxy_project_world_delta :: proc(g: ^game.Galaxy, x, y: f64) -> (projected_x, projected_y: f64) {
	return galaxy_project_world_xyz(g, x, y, 0)
}

galaxy_project_world_xyz :: proc(
	g: ^game.Galaxy,
	x, y, z: f64,
) -> (
	projected_x, projected_y: f64,
) {
	angle := galaxy_map_position_angle(g)
	cos_angle, sin_angle := math.cos(angle), math.sin(angle)
	flattened_y := y * galaxy_map_y_aspect(g)
	if g.morphology == .Spiral || g.morphology == .Barred_Spiral {
		sin_inclination := math.sqrt(max(1 - galaxy_map_y_aspect(g) * galaxy_map_y_aspect(g), 0.0))
		flattened_y += z * sin_inclination
	}
	return x * cos_angle - flattened_y * sin_angle, x * sin_angle + flattened_y * cos_angle
}

galaxy_unproject_world_delta :: proc(
	g: ^game.Galaxy,
	projected_x, projected_y: f64,
) -> (
	x, y: f64,
) {
	angle := galaxy_map_position_angle(g)
	cos_angle, sin_angle := math.cos(angle), math.sin(angle)
	x = projected_x * cos_angle + projected_y * sin_angle
	flattened_y := -projected_x * sin_angle + projected_y * cos_angle
	y = flattened_y / galaxy_map_y_aspect(g)
	return
}

galaxy_world_to_screen :: proc(s: ^Ux_State, x, y: f64) -> rl.Vector2 {
	return galaxy_world_to_screen_z(s, x, y, 0)
}

galaxy_world_to_screen_z :: proc(s: ^Ux_State, x, y, z: f64) -> rl.Vector2 {
	scale := galaxy_map_scale(s)
	projected_x, projected_y := galaxy_project_world_xyz(
		&s.galaxy,
		x - s.galaxy_pan_x,
		y - s.galaxy_pan_y,
		z,
	)
	return V(
		GALAXY_VIEW.x + GALAXY_VIEW.width / 2 + f32(projected_x * scale),
		GALAXY_VIEW.y + GALAXY_VIEW.height / 2 + f32(projected_y * scale),
	)
}

galaxy_sample_disk_height :: proc(rank, scale_height: f64) -> f64 {
	// Inverse CDF of a symmetric sech^2(z/h) sheet. Clamp only the numerical
	// endpoints; deterministic ranks otherwise preserve the physical tail.
	centered := clamp(rank, 1.0e-6, 1 - 1.0e-6) * 2 - 1
	return scale_height * math.atanh(centered)
}

galaxy_disk_scale_height :: proc(g: ^game.Galaxy, radius: f64, young, in_bar: bool) -> f64 {
	if in_bar do return g.disk_radius_kpc * .018
	radius_fraction := clamp(radius / max(g.disk_radius_kpc, .01), 0.0, 1.0)
	if young {
		// Recently formed associations remain close to the gas midplane.
		return g.disk_radius_kpc * .012 * (.9 + .2 * radius_fraction * radius_fraction)
	}
	// A quadratic flare approximates the weakening vertical restoring force in
	// the outer old disk without producing a visibly swollen inner component.
	return g.disk_radius_kpc * .028 * (.75 + radius_fraction * radius_fraction)
}

@(test)
galaxy_disk_scale_height_flares_old_stars_but_keeps_young_disk_cold :: proc(t: ^testing.T) {
	g := game.Galaxy {
		disk_radius_kpc = 10,
	}
	old_inner := galaxy_disk_scale_height(&g, 0, false, false)
	old_outer := galaxy_disk_scale_height(&g, 10, false, false)
	young_outer := galaxy_disk_scale_height(&g, 10, true, false)
	bar_outer := galaxy_disk_scale_height(&g, 10, false, true)
	testing.expect(t, old_outer > old_inner * 2)
	testing.expect(t, young_outer < old_outer)
	testing.expect(t, bar_outer < old_inner)
}

@(test)
galaxy_disk_height_sampler_is_symmetric_monotonic_and_bounded_at_catalog_endpoints :: proc(
	t: ^testing.T,
) {
	h := .32
	low := galaxy_sample_disk_height(0, h)
	middle := galaxy_sample_disk_height(.5, h)
	high := galaxy_sample_disk_height(1, h)
	testing.expect(t, low < middle && middle < high)
	testing.expect(t, math.abs(middle) < 1.0e-12)
	testing.expect(t, math.abs(low + high) < 1.0e-9)
	testing.expect(t, math.abs(high) < h * 8)
}

galaxy_point_visible :: proc(p: rl.Vector2, margin: f32 = 0) -> bool {
	return(
		p.x >= GALAXY_VIEW.x + margin &&
		p.x <= GALAXY_VIEW.x + GALAXY_VIEW.width - margin &&
		p.y >= GALAXY_VIEW.y + margin &&
		p.y <= GALAXY_VIEW.y + GALAXY_VIEW.height - margin \
	)
}

galaxy_ring_segment_count :: proc(radius, projected_scale: f64) -> int {
	projected_circumference := 2 * math.PI * max(radius, 0) * max(projected_scale, 0)
	return clamp(int(math.ceil(projected_circumference / 10)), 96, 2048)
}

galaxy_semantic_ring_visibility :: proc(density, structure: f64) -> f32 {
	// Semantic ink stays continuous but yields where stars and engraved structure
	// already carry high contrast. In black inter-arm space it returns to full.
	return f32(
		clamp(
			1 - .62 * math.sqrt(clamp(density, 0.0, 1.0)) - .12 * clamp(structure, 0.0, 1.5),
			.26,
			1.0,
		),
	)
}

galaxy_segment_intersects_view :: proc(a, b: rl.Vector2, margin: f32 = 2) -> bool {
	left, right := GALAXY_VIEW.x - margin, GALAXY_VIEW.x + GALAXY_VIEW.width + margin
	top, bottom := GALAXY_VIEW.y - margin, GALAXY_VIEW.y + GALAXY_VIEW.height + margin
	return(
		!(max(a.x, b.x) < left ||
			min(a.x, b.x) > right ||
			max(a.y, b.y) < top ||
			min(a.y, b.y) > bottom) \
	)
}

draw_galaxy_world_ring :: proc(s: ^Ux_State, radius: f64, color: rl.Color) {
	segments := galaxy_ring_segment_count(radius, galaxy_map_scale(s))
	zoom_ink := f32(clamp(2 / math.sqrt(s.galaxy_zoom), .25, 1.0))
	ring_color := color
	ring_color.a = u8(f32(color.a) * zoom_ink)
	previous := galaxy_world_to_screen(s, radius, 0)
	for i in 1 ..= segments {
		angle := f64(i) * 2 * math.PI / f64(segments)
		current := galaxy_world_to_screen(s, radius * math.cos(angle), radius * math.sin(angle))
		if galaxy_segment_intersects_view(previous, current) {
			mid_angle := (f64(i) - .5) * 2 * math.PI / f64(segments)
			density, structure := galaxy_lod_local_density(
				&s.galaxy,
				radius * math.cos(mid_angle),
				radius * math.sin(mid_angle),
			)
			segment_color := ring_color
			segment_color.a = u8(
				f32(ring_color.a) * galaxy_semantic_ring_visibility(density, structure),
			)
			rl.DrawLineEx(previous, current, 1, segment_color)
		}
		previous = current
	}
}

galaxy_star_hash :: proc(value: u64) -> u64 {
	x := (value ~ (value >> 30)) * 0xbf58476d1ce4e5b9
	x = (x ~ (x >> 27)) * 0x94d049bb133111eb
	return x ~ (x >> 31)
}

galaxy_star_unit :: proc(seed: u64, index, channel: int) -> f64 {
	value := galaxy_star_hash(
		seed + u64(index) * 0x9e3779b97f4a7c15 + u64(channel) * 0xd1b54a32d192ed03,
	)
	return f64(value >> 11) * (1.0 / 9007199254740992.0)
}

galaxy_irregular_clump_count :: proc(g: ^game.Galaxy) -> int {
	return 3 + int(galaxy_star_hash(g.seed ~ 0x6972726567756c61) % 5)
}

galaxy_irregular_clump_sigma :: proc(g: ^game.Galaxy, clump: int) -> f64 {
	return g.disk_radius_kpc * (.065 + .045 * galaxy_star_unit(g.seed, clump, 24))
}

galaxy_irregular_hatch_contour :: proc(contour: int) -> (sigma_radius, ink: f32, layers: int) {
	switch contour {
	case 0:
		return 2.35, 10, 1
	case 1:
		return 1.45, 16, 2
	case 2:
		return .78, 24, 3
	}
	return 0, 0, 0
}

@(test)
galaxy_irregular_hatch_contours_concentrate_ink_inward :: proc(t: ^testing.T) {
	previous_radius, previous_ink, previous_layers := f32(1.0e9), f32(-1), 0
	for contour in 0 ..< 3 {
		radius, ink, layers := galaxy_irregular_hatch_contour(contour)
		testing.expect(t, radius > 0 && radius < previous_radius)
		testing.expect(t, ink > previous_ink)
		testing.expect(t, layers > previous_layers)
		previous_radius, previous_ink, previous_layers = radius, ink, layers
	}
}

galaxy_sersic_index :: proc(g: ^game.Galaxy) -> int {
	switch g.morphology {
	case .Elliptical:
		return 2 + int(galaxy_star_hash(g.seed ~ 0x7365727369635f6e) % 3)
	case .Barred_Spiral:
		return 2 + int(galaxy_star_hash(g.seed ~ 0x62756c67655f5f6e) % 2)
	case .Spiral:
		return g.bulge_fraction >= .16 ? 2 : 1
	case .Dwarf_Irregular:
		return 1
	}
	return 2
}

galaxy_render_bar_fraction :: proc(g: ^game.Galaxy) -> f64 {
	if g.morphology != .Barred_Spiral do return 0
	return clamp(.10 + .18 * g.bulge_fraction, .12, .18)
}

galaxy_bar_axis_ratio :: proc(g: ^game.Galaxy) -> f64 {
	return g.morphology == .Barred_Spiral ? .30 : 1
}

galaxy_bar_inner_ring_fraction :: proc(g: ^game.Galaxy) -> f64 {
	if g.morphology != .Barred_Spiral do return 0
	return .045 + .025 * galaxy_star_unit(g.seed, 0, 67)
}

galaxy_bar_inner_ring_radius :: proc(g: ^game.Galaxy) -> f64 {
	return g.disk_radius_kpc * g.bulge_fraction * 1.35
}

galaxy_bar_inner_ring_axis_ratio :: proc(g: ^game.Galaxy) -> f64 {
	return .66 + .10 * galaxy_star_unit(g.seed, 0, 68)
}

galaxy_bar_inner_ring_density :: proc(g: ^game.Galaxy, x, y: f64) -> f64 {
	if g.morphology != .Barred_Spiral do return 0
	bar_radius := g.disk_radius_kpc * g.bulge_fraction
	bar_angle := galaxy_spiral_phase(g, bar_radius)
	cos_bar, sin_bar := math.cos(bar_angle), math.sin(bar_angle)
	bar_x := x * cos_bar + y * sin_bar
	bar_y := -x * sin_bar + y * cos_bar
	axis_ratio := galaxy_bar_inner_ring_axis_ratio(g)
	elliptical_radius := math.sqrt(bar_x * bar_x + (bar_y / axis_ratio) * (bar_y / axis_ratio))
	ring_radius := galaxy_bar_inner_ring_radius(g)
	sigma := max(ring_radius * .05, .001)
	delta := elliptical_radius - ring_radius
	return math.exp(-(delta * delta) / (2 * sigma * sigma))
}

@(test)
galaxy_bar_inner_ring_is_outside_bar_finite_and_seeded :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(64) {
		g := game.Galaxy {
			seed            = seed,
			morphology      = .Barred_Spiral,
			disk_radius_kpc = 14,
			bulge_fraction  = .2,
		}
		bar_radius := g.disk_radius_kpc * g.bulge_fraction
		ring_radius := galaxy_bar_inner_ring_radius(&g)
		testing.expect(t, ring_radius > bar_radius && ring_radius < g.disk_radius_kpc * .5)
		testing.expect(
			t,
			galaxy_bar_inner_ring_axis_ratio(&g) >= .66 &&
			galaxy_bar_inner_ring_axis_ratio(&g) <= .76,
		)
		testing.expect(
			t,
			galaxy_bar_inner_ring_fraction(&g) >= .045 &&
			galaxy_bar_inner_ring_fraction(&g) <= .07,
		)
		testing.expect_value(t, galaxy_bar_inner_ring_radius(&g), ring_radius)
	}
}

@(test)
galaxy_bar_inner_ring_density_peaks_on_projected_intrinsic_annulus :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed                 = 881,
		morphology           = .Barred_Spiral,
		disk_radius_kpc      = 14,
		bulge_fraction       = .2,
		spiral_pitch_degrees = 18,
	}
	bar_angle := galaxy_spiral_phase(&g, g.disk_radius_kpc * g.bulge_fraction)
	ring_radius := galaxy_bar_inner_ring_radius(&g)
	on_ring_x := ring_radius * math.cos(bar_angle)
	on_ring_y := ring_radius * math.sin(bar_angle)
	testing.expect(t, galaxy_bar_inner_ring_density(&g, on_ring_x, on_ring_y) > .999)
	testing.expect(t, galaxy_bar_inner_ring_density(&g, 0, 0) < .001)
	testing.expect(t, galaxy_bar_inner_ring_density(&g, on_ring_x * 1.3, on_ring_y * 1.3) < .001)
	g.morphology = .Spiral
	testing.expect_value(t, galaxy_bar_inner_ring_density(&g, on_ring_x, on_ring_y), f64(0))
}

galaxy_render_bulge_fraction :: proc(g: ^game.Galaxy) -> f64 {
	switch g.morphology {
	case .Spiral:
		return clamp(g.bulge_fraction, .06, .28)
	case .Barred_Spiral:
		return clamp(g.bulge_fraction * .55, .09, .22)
	case .Elliptical:
		return 1
	case .Dwarf_Irregular:
		return 0
	}
	return 0
}

galaxy_hatch_signature :: proc(g: ^game.Galaxy) -> (spacing, irregularity, rotation: f32) {
	spacing = f32(5.6 + galaxy_star_unit(g.seed, 0, 70) * 1.1)
	irregularity = f32(.31 + galaxy_star_unit(g.seed, 0, 71) * .22)
	rotation = f32((galaxy_star_unit(g.seed, 0, 72) - .5) * .34)
	return
}

galaxy_arm_hatch_alpha :: proc(envelope, coherence, zoom: f64) -> u8 {
	// Arm engraving remains legible while navigating instead of disappearing as
	// soon as individual stars resolve. The density field still controls ink;
	// the floor only compensates for the hatch occupying a small part of a ribbon.
	zoom_ink := clamp(2.4 / math.sqrt(max(zoom, 1)), .72, 1.0)
	return u8(clamp((12 + envelope * coherence * 34) * zoom_ink, 8.0, 46.0))
}

galaxy_stellar_mark_alpha :: proc(rank, lower, upper, boost: f64) -> u8 {
	// A stellar luminosity function has many more dim stars than luminous ones.
	// This is an ink-space approximation rather than a linear random ramp: every
	// accepted catalogue entry remains an explicit mark, while only the upper tail
	// competes with engraved structure. Exceptional bright stars are handled by
	// the separate resolved-star branch below.
	heavy_tail := math.pow(clamp(rank, 0.0, 1.0), 2.75)
	return u8(clamp(lower + (upper - lower) * heavy_tail + boost, lower, 255.0))
}

@(test)
galaxy_stellar_mark_alpha_is_faint_weighted_and_monotonic :: proc(t: ^testing.T) {
	low := galaxy_stellar_mark_alpha(0, 14, 72, 0)
	median := galaxy_stellar_mark_alpha(.5, 14, 72, 0)
	high := galaxy_stellar_mark_alpha(1, 14, 72, 0)
	boosted := galaxy_stellar_mark_alpha(.5, 14, 72, 12)
	testing.expect_value(t, low, u8(14))
	testing.expect(t, median < 25)
	testing.expect(t, low < median && median < high)
	testing.expect_value(t, high, u8(72))
	testing.expect(t, boosted > median)
}

@(test)
galaxy_arm_hatch_alpha_tracks_density_and_survives_navigation_zoom :: proc(t: ^testing.T) {
	weak_wide := galaxy_arm_hatch_alpha(.2, .6, 1)
	dense_wide := galaxy_arm_hatch_alpha(1, 1, 1)
	dense_mid := galaxy_arm_hatch_alpha(1, 1, 8)
	dense_close := galaxy_arm_hatch_alpha(1, 1, 40)
	testing.expect(t, dense_wide > weak_wide)
	testing.expect_value(t, dense_wide, u8(46))
	testing.expect(t, dense_mid >= 36 && dense_mid < dense_wide)
	testing.expect(t, dense_close >= 32 && dense_close <= dense_mid)
}

galaxy_spiral_handedness :: proc(g: ^game.Galaxy) -> f64 {
	return galaxy_star_hash(g.seed ~ 0x73706972616c5f68) & 1 == 0 ? -1 : 1
}

galaxy_spiral_phase :: proc(g: ^game.Galaxy, radius: f64) -> f64 {
	scale_length := g.disk_radius_kpc / 3.2
	pitch := g.spiral_pitch_degrees * math.PI / 180
	// The constant-pitch logarithmic spiral used by analytic density-wave
	// models: theta(R) = theta_0 + ln(R/R_0) / tan(pitch).
	return(
		galaxy_spiral_handedness(g) *
		math.ln(max(radius, .05) / max(scale_length, .05)) /
		math.tan(pitch) \
	)
}

galaxy_spiral_theta :: proc(g: ^game.Galaxy, arm: int, radius: f64) -> f64 {
	return(
		f64(arm) * 2 * math.PI / f64(max(g.spiral_arm_count, 1)) +
		galaxy_spiral_phase(g, radius) \
	)
}

galaxy_spiral_dr_dtheta :: proc(g: ^game.Galaxy, radius: f64) -> f64 {
	pitch := g.spiral_pitch_degrees * math.PI / 180
	return galaxy_spiral_handedness(g) * max(radius, .05) * math.tan(pitch)
}

galaxy_projected_spiral_tangent_angle :: proc(g: ^game.Galaxy, arm: int, radius: f64) -> f64 {
	theta := galaxy_spiral_theta(g, arm, radius)
	dr_dtheta := galaxy_spiral_dr_dtheta(g, radius)
	// Differentiate x=r cos(theta), y=r sin(theta), then pass the tangent
	// through the same affine inclination used by stars, rings, and systems.
	dx := dr_dtheta * math.cos(theta) - radius * math.sin(theta)
	dy := dr_dtheta * math.sin(theta) + radius * math.cos(theta)
	projected_dx, projected_dy := galaxy_project_world_delta(g, dx, dy)
	return math.atan2(projected_dy, projected_dx)
}

@(test)
galaxy_projected_spiral_tangent_matches_finite_difference :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed                 = 91827,
		morphology           = .Spiral,
		disk_radius_kpc      = 12,
		spiral_arm_count     = 3,
		spiral_pitch_degrees = 17,
	}
	for arm in 0 ..< g.spiral_arm_count {
		radius := g.disk_radius_kpc * (.3 + .16 * f64(arm))
		theta := galaxy_spiral_theta(&g, arm, radius)
		dtheta := 1.0e-5
		radius_next := radius + galaxy_spiral_dr_dtheta(&g, radius) * dtheta
		theta_next := theta + dtheta
		x0, y0 := galaxy_project_world_delta(
			&g,
			radius * math.cos(theta),
			radius * math.sin(theta),
		)
		x1, y1 := galaxy_project_world_delta(
			&g,
			radius_next * math.cos(theta_next),
			radius_next * math.sin(theta_next),
		)
		finite_angle := math.atan2(y1 - y0, x1 - x0)
		analytic_angle := galaxy_projected_spiral_tangent_angle(&g, arm, radius)
		testing.expect(
			t,
			math.abs(
				math.atan2(
					math.sin(finite_angle - analytic_angle),
					math.cos(finite_angle - analytic_angle),
				),
			) <
			2.0e-5,
		)
	}
}

GALAXY_ARM_ASSOCIATION_COUNT :: 22

galaxy_arm_association_radius_fraction :: proc(g: ^game.Galaxy, arm, association: int) -> f64 {
	offset := galaxy_star_unit(g.seed, arm, 30) / f64(GALAXY_ARM_ASSOCIATION_COUNT)
	return (f64(association) + .5) / f64(GALAXY_ARM_ASSOCIATION_COUNT) - offset
}

@(test)
galaxy_arm_associations_are_seeded_evenly_spaced_centers :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed = 7319,
	}
	a := galaxy_arm_association_radius_fraction(&g, 1, 5)
	b := galaxy_arm_association_radius_fraction(&g, 1, 6)
	repeated := galaxy_arm_association_radius_fraction(&g, 1, 5)
	testing.expect(t, math.abs((b - a) - 1.0 / f64(GALAXY_ARM_ASSOCIATION_COUNT)) < 1.0e-9)
	testing.expect_value(t, a, repeated)
	testing.expect(t, a > 0 && b < 1)
}

// Cox & Gomez's analytic spiral-arm phase is
// gamma = N[theta - theta_0 - ln(R/R_0)/tan(pitch)]. Their first three
// Fourier coefficients approximate a narrow sinusoidal arm without turning
// the inter-arm disk into empty ribbons.
galaxy_spiral_gamma :: proc(g: ^game.Galaxy, radius, theta: f64) -> f64 {
	return f64(max(g.spiral_arm_count, 1)) * (theta - galaxy_spiral_phase(g, radius))
}

galaxy_spiral_harmonic :: proc(gamma: f64) -> f64 {
	C1 :: 8.0 / (3.0 * math.PI)
	C2 :: 0.5
	C3 :: 8.0 / (15.0 * math.PI)
	return C1 * math.cos(gamma) + C2 * math.cos(2 * gamma) + C3 * math.cos(3 * gamma)
}

galaxy_spiral_arm_envelope :: proc(g: ^game.Galaxy, radius: f64) -> f64 {
	radius_fraction := radius / max(g.disk_radius_kpc, .01)
	// The analytic perturbation decays exponentially with radius. Smooth inner
	// and outer tapers avoid extending the wave through the bulge or hard edge.
	radial_decay := math.exp(-radius / max(g.disk_radius_kpc * .72, .01))
	inner := clamp((radius_fraction - .10) / .14, 0.0, 1.0)
	inner = inner * inner * (3 - 2 * inner)
	outer := clamp((1 - radius_fraction) / .12, 0.0, 1.0)
	outer = outer * outer * (3 - 2 * outer)
	return radial_decay * inner * outer
}

galaxy_spiral_arm_coherence :: proc(g: ^game.Galaxy, arm: int, radius: f64) -> f64 {
	arm_count := max(g.spiral_arm_count, 1)
	normalized_arm := arm % arm_count
	if normalized_arm < 0 do normalized_arm += arm_count
	radius_fraction := radius / max(g.disk_radius_kpc, .01)
	phase_a := galaxy_star_unit(g.seed, normalized_arm, 52)
	phase_b := galaxy_star_unit(g.seed, normalized_arm, 53)
	// Two broad radial modes approximate the aggregation/disaggregation of a
	// transient stellar arm. Each arm receives independent seeded phases.
	coherence :=
		.82 +
		.20 * math.sin(2 * math.PI * (radius_fraction * 1.35 + phase_a)) +
		.13 * math.sin(2 * math.PI * (radius_fraction * 3.20 + phase_b))
	return clamp(coherence, .45, 1.15)
}

galaxy_nearest_spiral_arm :: proc(g: ^game.Galaxy, radius, theta: f64) -> int {
	arm_count := max(g.spiral_arm_count, 1)
	arm_coordinate := (theta - galaxy_spiral_phase(g, radius)) * f64(arm_count) / (2 * math.PI)
	arm := int(math.floor(arm_coordinate + .5)) % arm_count
	if arm < 0 do arm += arm_count
	return arm
}

galaxy_spiral_relative_density :: proc(g: ^game.Galaxy, radius, theta: f64) -> f64 {
	AMPLITUDE :: 1.15
	arm := galaxy_nearest_spiral_arm(g, radius, theta)
	coherence := galaxy_spiral_arm_coherence(g, arm, radius)
	return max(
		.04,
		1 +
		AMPLITUDE *
			galaxy_spiral_arm_envelope(g, radius) *
			coherence *
			galaxy_spiral_harmonic(galaxy_spiral_gamma(g, radius, theta)),
	)
}

galaxy_spiral_corotation_fraction :: proc(g: ^game.Galaxy) -> f64 {
	return .58 + .16 * galaxy_star_unit(g.seed, 0, 66)
}

galaxy_young_arm_phase_offset :: proc(g: ^game.Galaxy, radius: f64) -> f64 {
	// Material inside corotation overtakes the pattern; outside, the pattern
	// overtakes material. A bounded linear drift is sufficient at map scale and
	// gives the observed sign reversal without pretending to integrate orbits.
	radius_fraction := radius / max(g.disk_radius_kpc, .01)
	corotation := galaxy_spiral_corotation_fraction(g)
	return galaxy_spiral_handedness(g) * clamp((corotation - radius_fraction) * .18, -.075, .105)
}

@(test)
galaxy_young_arm_offset_reverses_at_seeded_corotation :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed            = 8127,
		morphology      = .Spiral,
		disk_radius_kpc = 12,
	}
	corotation := galaxy_spiral_corotation_fraction(&g)
	handedness := galaxy_spiral_handedness(&g)
	testing.expect(t, corotation >= .58 && corotation <= .74)
	testing.expect(t, galaxy_young_arm_phase_offset(&g, g.disk_radius_kpc * .3) * handedness > 0)
	testing.expect(
		t,
		math.abs(galaxy_young_arm_phase_offset(&g, g.disk_radius_kpc * corotation)) < 1.0e-12,
	)
	testing.expect(t, galaxy_young_arm_phase_offset(&g, g.disk_radius_kpc * .9) * handedness < 0)
	testing.expect_value(t, galaxy_spiral_corotation_fraction(&g), corotation)
}
