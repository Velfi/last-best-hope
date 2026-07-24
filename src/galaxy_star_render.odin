package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"
import "core:time"

@(test)
galaxy_projected_ellipse_axes_are_ordered_bounded_and_seeded :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(64) {
		g := game.Galaxy {
			seed       = seed,
			morphology = .Barred_Spiral,
		}
		major, minor, angle := galaxy_project_ellipse(&g, .7, .3)
		repeated_major, repeated_minor, repeated_angle := galaxy_project_ellipse(&g, .7, .3)
		testing.expect(t, major >= minor && major <= 1 && minor > 0)
		testing.expect(t, angle >= -math.PI / 2 && angle <= math.PI / 2)
		testing.expect_value(t, major, repeated_major)
		testing.expect_value(t, minor, repeated_minor)
		testing.expect_value(t, angle, repeated_angle)
	}
}

@(test)
galaxy_hatch_signature_is_seeded_bounded_and_reproducible :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(128) {
		g := game.Galaxy {
			seed = seed,
		}
		spacing, irregularity, rotation := galaxy_hatch_signature(&g)
		testing.expect(t, spacing >= 5.6 && spacing <= 6.7)
		testing.expect(t, irregularity >= .31 && irregularity <= .53)
		testing.expect(t, rotation >= -.17 && rotation <= .17)
		a, b, c := galaxy_hatch_signature(&g)
		testing.expect_value(t, a, spacing)
		testing.expect_value(t, b, irregularity)
		testing.expect_value(t, c, rotation)
	}
}

@(test)
galaxy_young_arm_fraction_tracks_activity_and_excludes_non_disks :: proc(t: ^testing.T) {
	quiet := game.Galaxy {
		morphology                            = .Spiral,
		stellar_mass_solar                    = 1.0e11,
		star_formation_rate_solar_masses_year = .01,
	}
	active := quiet
	active.star_formation_rate_solar_masses_year = 30
	testing.expect(t, galaxy_young_arm_fraction(&quiet) >= .32)
	testing.expect(t, galaxy_young_arm_fraction(&active) <= .62)
	testing.expect(t, galaxy_young_arm_fraction(&active) > galaxy_young_arm_fraction(&quiet))
	testing.expect_value(t, galaxy_old_disk_arm_response(&quiet), f64(.16))
	testing.expect(
		t,
		galaxy_total_arm_tracing_fraction(&quiet) > galaxy_young_arm_fraction(&quiet),
	)
	testing.expect(t, galaxy_total_arm_tracing_fraction(&quiet) < 1)
	quiet.morphology = .Elliptical
	testing.expect_value(t, galaxy_young_arm_fraction(&quiet), f64(0))
	testing.expect_value(t, galaxy_old_disk_arm_response(&quiet), f64(0))
	testing.expect_value(t, galaxy_total_arm_tracing_fraction(&quiet), f64(0))
}

@(test)
galaxy_spiral_component_render_fractions_follow_generated_bulges :: proc(t: ^testing.T) {
	morphologies := [?]game.Galaxy_Morphology {
		game.Galaxy_Morphology.Spiral,
		game.Galaxy_Morphology.Barred_Spiral,
	}
	for morphology in morphologies {
		previous_bulge := f64(-1)
		for step in 0 ..= 20 {
			bulge_fraction := .08 + .30 * f64(step) / 20
			g := game.Galaxy {
				morphology     = morphology,
				bulge_fraction = bulge_fraction,
			}
			bar := galaxy_render_bar_fraction(&g)
			bulge := galaxy_render_bulge_fraction(&g)
			testing.expect(t, bulge >= previous_bulge)
			testing.expect(t, bar >= 0 && bulge >= 0 && bar + bulge < .55)
			if morphology == .Spiral do testing.expect_value(t, bar, f64(0))
			if morphology == .Barred_Spiral {
				testing.expect(t, bar >= .12 && bar <= .18)
				testing.expect_value(t, galaxy_bar_axis_ratio(&g), f64(.30))
			} else {
				testing.expect_value(t, galaxy_bar_axis_ratio(&g), f64(1))
			}
			previous_bulge = bulge
		}
	}
}

@(test)
galaxy_lod_catalog_is_world_stable_bounded_and_sparse :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed                                  = 0x51a7,
		morphology                            = .Spiral,
		stellar_mass_solar                    = 6.0e10,
		star_formation_rate_solar_masses_year = 1.6,
		disk_radius_kpc                       = 14,
		spiral_arm_count                      = 3,
		spiral_pitch_degrees                  = 18,
	}
	tile_x, tile_y := 8, -3
	tile_size := g.disk_radius_kpc / GALAXY_LOD_TILE_RADIUS
	accepted := 0
	for candidate in 0 ..< GALAXY_LOD_STARS_PER_TILE {
		x, y, visible, alpha := galaxy_lod_star_candidate(&g, tile_x, tile_y, candidate)
		testing.expect(t, x >= f64(tile_x) * tile_size && x < f64(tile_x + 1) * tile_size)
		testing.expect(t, y >= f64(tile_y) * tile_size && y < f64(tile_y + 1) * tile_size)
		x2, y2, visible2, alpha2 := galaxy_lod_star_candidate(&g, tile_x, tile_y, candidate)
		testing.expect_value(t, x2, x)
		testing.expect_value(t, y2, y)
		testing.expect_value(t, visible2, visible)
		testing.expect_value(t, alpha2, alpha)
		if visible {
			accepted += 1
			testing.expect(t, alpha >= 22 && alpha <= 96)
		}
	}
	testing.expect(t, accepted > 0 && accepted < GALAXY_LOD_STARS_PER_TILE)
	_, _, visible, _ := galaxy_lod_star_candidate(&g, GALAXY_LOD_TILE_RADIUS, tile_y, 0)
	testing.expect(t, !visible)
}

@(test)
galaxy_lod_density_supports_every_morphology :: proc(t: ^testing.T) {
	g := game.Galaxy {
		seed            = 0x51a7,
		disk_radius_kpc = 10,
		bulge_fraction  = .2,
	}
	morphologies := [?]game.Galaxy_Morphology {
		.Spiral,
		.Barred_Spiral,
		.Elliptical,
		.Dwarf_Irregular,
	}
	for morphology in morphologies {
		g.morphology = morphology
		if morphology == .Spiral || morphology == .Barred_Spiral {
			g.stellar_mass_solar = 6.0e10
			g.star_formation_rate_solar_masses_year = 1.6
			g.spiral_arm_count = 3
			g.spiral_pitch_degrees = 18
		}
		x, y := f64(0), f64(0)
		if morphology == .Dwarf_Irregular {
			clump_radius := g.disk_radius_kpc * (.12 + .48 * galaxy_star_unit(g.seed, 0, 20))
			clump_angle := galaxy_star_unit(g.seed, 0, 21) * 2 * math.PI
			x, y = clump_radius * math.cos(clump_angle), clump_radius * math.sin(clump_angle)
		}
		density, structure := galaxy_lod_local_density(&g, x, y)
		testing.expect(t, density > 0 && density <= 1)
		testing.expect(t, structure >= 0 && structure <= 1.5)
	}
}

draw_galaxy_stars :: proc(s: ^Ux_State) {
	g := &s.galaxy
	// These are stable representatives of the simulated population, not new
	// systems. A fixed seed makes the stellar plate reproducible across frames;
	// logarithmic scaling preserves the enormous population differences without
	// exceeding the immediate-mode canvas vertex budget.
	star_sample_count := galaxy_render_star_count(g)
	if s.galaxy_star_cache_seed != g.seed || s.galaxy_star_cache_count != star_sample_count {
		s.galaxy_star_cache_seed = g.seed
		s.galaxy_star_cache_count = star_sample_count
		scale_length := g.disk_radius_kpc / 3.2
		for i in 0 ..< star_sample_count {
			u0 := galaxy_star_unit(g.seed, i, 0)
			u1 := galaxy_star_unit(g.seed, i, 1)
			u2 := galaxy_star_unit(g.seed, i, 2)
			u3 := galaxy_star_unit(g.seed, i, 3)
			u4 := galaxy_star_unit(g.seed, i, 4)
			u5 := galaxy_star_unit(g.seed, i, 5)
			u6 := galaxy_star_unit(g.seed, i, 6)
			u7 := galaxy_star_unit(g.seed, i, 7)
			x, y, z: f64
			in_bar := false
			in_bulge := false
			young_arm := false
			arm_tracing := false
			arm_luminance_boost := 0
			switch g.morphology {
			case .Spiral, .Barred_Spiral:
				// Sigma(R) is exponential, so annular star counts carry an extra R
				// factor. Invert the truncated 2D CDF instead of sampling an exponential
				// radius (which makes the center much too dense).
				radius := galaxy_sample_tapered_exponential_disk(
					g,
					i,
					scale_length,
					g.disk_radius_kpc,
				)
				arm := int(galaxy_star_hash(g.seed + u64(i)) % u64(g.spiral_arm_count))
				young_arm = u2 < galaxy_young_arm_fraction(g)
				arm_tracing = young_arm || u6 < galaxy_old_disk_arm_response(g)
				if young_arm && u4 < .68 {
					// Gather young arm stars into stable associations rather than a
					// mathematically uniform ribbon. Each arm has a different phase offset.
					offset := galaxy_star_unit(g.seed, arm, 30) / f64(GALAXY_ARM_ASSOCIATION_COUNT)
					phase := radius / g.disk_radius_kpc + offset
					association := int(math.floor(phase * f64(GALAXY_ARM_ASSOCIATION_COUNT)))
					association_phase := galaxy_arm_association_radius_fraction(
						g,
						arm,
						association,
					)
					association_radius := clamp(
						association_phase * g.disk_radius_kpc,
						.02,
						g.disk_radius_kpc,
					)
					radius = radius * .38 + association_radius * .62
				}
				// The dynamically old disk remains nearly axisymmetric. The brighter young
				// component samples the analytic perturbation and makes arms emerge from
				// explicit stars rather than from a painted density fog.
				theta := arm_tracing ? galaxy_sample_spiral_theta(g, i, radius) : u1 * 2 * math.PI
				if young_arm {
					arm_density := galaxy_spiral_relative_density(g, radius, theta)
					arm_luminance_boost = 10 + int(clamp((arm_density - 1) * 20, 0.0, 26.0))
					// Young associations drift away from the older stellar-wave crest;
					// the sign flips at corotation as material and pattern exchange order.
					theta += galaxy_young_arm_phase_offset(g, radius)
				}
				bar_fraction := galaxy_render_bar_fraction(g)
				bulge_fraction := galaxy_render_bulge_fraction(g)
				ring_fraction := galaxy_bar_inner_ring_fraction(g)
				if g.morphology == .Barred_Spiral && u3 < bar_fraction {
					bar_radius := g.disk_radius_kpc * g.bulge_fraction
					m := galaxy_sample_ferrers_m(u0)
					bar_sample_angle := u1 * 2 * math.PI
					bar_x := bar_radius * m * math.cos(bar_sample_angle)
					bar_y := bar_radius * galaxy_bar_axis_ratio(g) * m * math.sin(bar_sample_angle)
					// Join the two bar ends to the phase of the logarithmic arm pair.
					bar_angle := galaxy_spiral_phase(g, bar_radius)
					x = bar_x * math.cos(bar_angle) - bar_y * math.sin(bar_angle)
					y = bar_x * math.sin(bar_angle) + bar_y * math.cos(bar_angle)
					in_bar = true
					young_arm = false
					arm_luminance_boost = 0
				} else if u3 < bar_fraction + bulge_fraction {
					// Model the bulge as a separate Sersic component rather than stealing
					// only those disk samples which happened to land inside the bar radius.
					bulge_limit := g.disk_radius_kpc * max(g.bulge_fraction, .08) * .82
					radius = galaxy_sample_sersic(
						u0,
						bulge_limit * .28,
						bulge_limit,
						galaxy_sersic_index(g),
					)
					bulge_theta := u1 * 2 * math.PI
					x = radius * math.cos(bulge_theta)
					y =
						radius *
						math.sin(bulge_theta) *
						(g.morphology == .Barred_Spiral ? .68 : .82)
					in_bulge = true
					young_arm = false
					arm_luminance_boost = 0
				} else if u3 < bar_fraction + bulge_fraction + ring_fraction {
					// A young inner resonance ring wraps just beyond the Ferrers bar.
					// Its finite width is explicit in the star catalogue; the matching
					// engraved annulus below only reinforces this real density feature.
					ring_radius := galaxy_bar_inner_ring_radius(g) * (.95 + .10 * u0)
					ring_theta := u1 * 2 * math.PI
					ring_x := ring_radius * math.cos(ring_theta)
					ring_y :=
						ring_radius * galaxy_bar_inner_ring_axis_ratio(g) * math.sin(ring_theta)
					bar_angle := galaxy_spiral_phase(g, g.disk_radius_kpc * g.bulge_fraction)
					x = ring_x * math.cos(bar_angle) - ring_y * math.sin(bar_angle)
					y = ring_x * math.sin(bar_angle) + ring_y * math.cos(bar_angle)
					young_arm = true
					arm_luminance_boost = 7
				} else {
					x, y = radius * math.cos(theta), radius * math.sin(theta)
				}
			case .Elliptical:
				// Ellipticals span a real family of projected Sersic concentrations;
				// the seeded n=2..4 profile gives each galaxy a distinct core/envelope.
				radius := galaxy_sample_sersic(
					u0,
					g.disk_radius_kpc * .24,
					g.disk_radius_kpc,
					galaxy_sersic_index(g),
				)
				theta := u1 * 2 * math.PI
				x, y = radius * math.cos(theta), radius * math.sin(theta)
			case .Dwarf_Irregular:
				if u3 < .74 {
					// Young associations gather around a handful of stable, asymmetric
					// knots; the remaining stars form the older diffuse component.
					clump := int(
						galaxy_star_hash(g.seed + u64(i) * 0x94d049bb133111eb) %
						u64(galaxy_irregular_clump_count(g)),
					)
					clump_radius :=
						g.disk_radius_kpc * (.12 + .48 * galaxy_star_unit(g.seed, clump, 20))
					clump_angle := galaxy_star_unit(g.seed, clump, 21) * 2 * math.PI
					clump_sigma := galaxy_irregular_clump_sigma(g, clump)
					clump_aspect := .68 + .64 * galaxy_star_unit(g.seed, clump, 22)
					clump_limit := g.disk_radius_kpc * .27
					clump_cdf :=
						1 -
						math.exp(-(clump_limit * clump_limit) / (2 * clump_sigma * clump_sigma))
					local_radius :=
						clump_sigma * math.sqrt(-2 * math.ln(max(1.0e-9, 1 - u0 * clump_cdf)))
					local_angle := u1 * 2 * math.PI
					x =
						clump_radius * math.cos(clump_angle) +
						local_radius * math.cos(local_angle) * clump_aspect
					y =
						clump_radius * math.sin(clump_angle) +
						local_radius * math.sin(local_angle) / clump_aspect
				} else {
					radius := g.disk_radius_kpc * math.sqrt(u0)
					theta := u1 * 2 * math.PI
					x = radius * math.cos(theta) + (u2 - .5) * g.disk_radius_kpc * .12
					y = radius * math.sin(theta)
				}
			}
			if g.morphology == .Spiral || g.morphology == .Barred_Spiral {
				if in_bulge {
					// The bulge is a spheroid, not part of the cold disk. Counter the
					// midplane compression so its sampled intrinsic axial ratio survives.
					q := galaxy_map_y_aspect(g)
					sin_inclination := math.sqrt(max(1 - q * q, 0.0))
					if sin_inclination > 1.0e-6 do z = y * (1 - q) / sin_inclination
				} else {
					stellar_radius := math.sqrt(x * x + y * y)
					scale_height := galaxy_disk_scale_height(g, stellar_radius, young_arm, in_bar)
					z = galaxy_sample_disk_height(u7, scale_height)
				}
			}
			bright := u5 > (young_arm ? .988 : .992)
			// More points, less ink per point: visible density now comes primarily
			// from the explicit catalogue rather than high-alpha overlap.
			base_alpha := galaxy_stellar_mark_alpha(u5, 14, 72, f64(arm_luminance_boost))
			s.galaxy_star_cache[i] = {
				x     = f32(x),
				y     = f32(y),
				z     = f32(z),
				alpha = bright ? u8(132) : in_bar ? galaxy_stellar_mark_alpha(u5, 10, 34, 0) : base_alpha,
				size  = bright ? u8(2) : u8(1),
			}
		}
	}
	for star in s.galaxy_star_cache[:star_sample_count] {
		p := galaxy_world_to_screen_z(s, f64(star.x), f64(star.y), f64(star.z))
		if !galaxy_point_visible(p, 1) do continue
		size := i32(star.size)
		rl.DrawRectangle(
			i32(p.x) - size / 2,
			i32(p.y) - size / 2,
			size,
			size,
			{220, 218, 205, star.alpha},
		)
	}
}

galaxy_lod_tile_intersects_view :: proc(s: ^Ux_State, tile_x, tile_y: int) -> bool {
	g := &s.galaxy
	tile_size := g.disk_radius_kpc / GALAXY_LOD_TILE_RADIUS
	x0, x1 := f64(tile_x) * tile_size, f64(tile_x + 1) * tile_size
	y0, y1 := f64(tile_y) * tile_size, f64(tile_y + 1) * tile_size
	corners := [4]rl.Vector2 {
		galaxy_world_to_screen(s, x0, y0),
		galaxy_world_to_screen(s, x1, y0),
		galaxy_world_to_screen(s, x1, y1),
		galaxy_world_to_screen(s, x0, y1),
	}
	min_x, max_x := corners[0].x, corners[0].x
	min_y, max_y := corners[0].y, corners[0].y
	for corner in corners[1:] {
		min_x, max_x = min(min_x, corner.x), max(max_x, corner.x)
		min_y, max_y = min(min_y, corner.y), max(max_y, corner.y)
	}
	return(
		!(max_x < GALAXY_VIEW.x - 1 ||
			min_x > GALAXY_VIEW.x + GALAXY_VIEW.width + 1 ||
			max_y < GALAXY_VIEW.y - 1 ||
			min_y > GALAXY_VIEW.y + GALAXY_VIEW.height + 1) \
	)
}

@(test)
galaxy_lod_tile_projection_culls_offscreen_tiles_without_losing_center :: proc(t: ^testing.T) {
	s := ux_state_create(); defer ux_state_destroy(s)
	s.galaxy = game.Galaxy {
		seed                 = 9182,
		morphology           = .Barred_Spiral,
		disk_radius_kpc      = 12,
		spiral_pitch_degrees = 18,
	}
	s.galaxy_zoom = 40
	testing.expect(t, galaxy_lod_tile_intersects_view(s, 0, 0))
	testing.expect(
		t,
		!galaxy_lod_tile_intersects_view(
			s,
			GALAXY_LOD_TILE_RADIUS - 1,
			GALAXY_LOD_TILE_RADIUS - 1,
		),
	)
}

draw_galaxy_lod_stars :: proc(s: ^Ux_State) {
	g := &s.galaxy
	if s.galaxy_zoom <= 12 do return
	fade := f32(clamp((s.galaxy_zoom - 12) / 10, 0.0, 1.0))
	scale := galaxy_map_scale(s)
	angle := galaxy_map_position_angle(g)
	cos_angle, sin_angle := math.abs(math.cos(angle)), math.abs(math.sin(angle))
	y_aspect := galaxy_map_y_aspect(g)
	half_screen_x := f64(GALAXY_VIEW.width) / (2 * scale)
	half_screen_y := f64(GALAXY_VIEW.height) / (2 * scale)
	half_world_x := cos_angle * half_screen_x + sin_angle * half_screen_y
	half_world_y := (sin_angle * half_screen_x + cos_angle * half_screen_y) / y_aspect
	tile_size := g.disk_radius_kpc / GALAXY_LOD_TILE_RADIUS
	min_tile_x := max(
		-GALAXY_LOD_TILE_RADIUS,
		int(math.floor((s.galaxy_pan_x - half_world_x) / tile_size)) - 1,
	)
	max_tile_x := min(
		GALAXY_LOD_TILE_RADIUS - 1,
		int(math.floor((s.galaxy_pan_x + half_world_x) / tile_size)) + 1,
	)
	min_tile_y := max(
		-GALAXY_LOD_TILE_RADIUS,
		int(math.floor((s.galaxy_pan_y - half_world_y) / tile_size)) - 1,
	)
	max_tile_y := min(
		GALAXY_LOD_TILE_RADIUS - 1,
		int(math.floor((s.galaxy_pan_y + half_world_y) / tile_size)) + 1,
	)
	if min_tile_x > max_tile_x || min_tile_y > max_tile_y do return
	for tile_y in min_tile_y ..= max_tile_y {
		for tile_x in min_tile_x ..= max_tile_x {
			if !galaxy_lod_tile_intersects_view(s, tile_x, tile_y) do continue
			for candidate in 0 ..< GALAXY_LOD_STARS_PER_TILE {
				x, y, visible, alpha := galaxy_lod_star_candidate(g, tile_x, tile_y, candidate)
				if !visible do continue
				z := galaxy_lod_star_height(g, tile_x, tile_y, candidate, math.sqrt(x * x + y * y))
				p := galaxy_world_to_screen_z(s, x, y, z)
				if !galaxy_point_visible(p, 1) do continue
				rl.DrawRectangle(i32(p.x), i32(p.y), 1, 1, {220, 218, 205, u8(f32(alpha) * fade)})
			}
		}
	}
}

draw_galaxy_elliptical_isophotes :: proc(
	s: ^Ux_State,
	center: rl.Vector2,
	hatch_spacing, hatch_irregularity, hatch_rotation: f32,
) {
	g := &s.galaxy
	if g.morphology != .Elliptical || s.galaxy_zoom >= 6 do return
	isophote_hatch := LBH_HATCH_OUTER_DARK
	isophote_hatch.invert = true
	isophote_hatch.spacing = hatch_spacing + 1.4
	isophote_hatch.line_width = .65
	isophote_hatch.strength = .42
	isophote_hatch.irregularity = hatch_irregularity
	isophote_hatch.layer_count = 2
	isophote_hatch.edge_softness = .08
	isophote_hatch.rotation = hatch_rotation
	isophote_hatch.offset = V(-center.x, -center.y)
	overview_fade := clamp((6 - s.galaxy_zoom) / 5, 0.0, 1.0)
	map_scale := galaxy_map_scale(s)
	isophote_fractions := [?]f64{.38, .62, .82}
	for radius_fraction in isophote_fractions {
		radius := g.disk_radius_kpc * radius_fraction
		band_width := g.disk_radius_kpc * (.022 + .010 * (1 - radius_fraction))
		outer_x := f32((radius + band_width) * map_scale)
		outer_y := outer_x * f32(galaxy_map_y_aspect(g))
		inner_x := f32(max(radius - band_width, .01) * map_scale)
		inner_y := inner_x * f32(galaxy_map_y_aspect(g))
		intensity := galaxy_sersic_relative_intensity(
			radius,
			g.disk_radius_kpc * .24,
			galaxy_sersic_index(g),
		)
		alpha := u8(clamp((3 + math.sqrt(intensity) * 18) * overview_fade, 0.0, 18.0))
		if alpha > 0 do rl.DrawEllipseRingHatched(center, outer_x, outer_y, inner_x, inner_y, {216, 213, 199, alpha}, isophote_hatch, 96, f32(galaxy_map_position_angle(g)))
	}
}

draw_galaxy_irregular_clumps :: proc(s: ^Ux_State, hatch_irregularity, hatch_rotation: f32) {
	g := &s.galaxy
	if g.morphology != .Dwarf_Irregular do return
	clump_hatch := LBH_HATCH_OUTER_DARK
	clump_hatch.invert = true
	clump_hatch.spacing = 7
	clump_hatch.line_width = .75
	clump_hatch.strength = .55
	clump_hatch.irregularity = hatch_irregularity
	for clump in 0 ..< galaxy_irregular_clump_count(g) {
		clump_radius := g.disk_radius_kpc * (.12 + .48 * galaxy_star_unit(g.seed, clump, 20))
		clump_angle := galaxy_star_unit(g.seed, clump, 21) * 2 * math.PI
		clump_aspect := .68 + .64 * galaxy_star_unit(g.seed, clump, 22)
		clump_center := galaxy_world_to_screen(
			s,
			clump_radius * math.cos(clump_angle),
			clump_radius * math.sin(clump_angle),
		)
		clump_zoom_ink := f32(clamp(2 / math.sqrt(s.galaxy_zoom), .4, 1.0))
		base_rotation := hatch_rotation + f32(galaxy_star_unit(g.seed, clump, 23) * .7 - .35)
		for contour in 0 ..< 3 {
			sigma_radius, contour_ink, contour_layers := galaxy_irregular_hatch_contour(contour)
			clump_pixels := clamp(
				f32(
					galaxy_irregular_clump_sigma(g, clump) *
					f64(sigma_radius) *
					galaxy_map_scale(s),
				),
				f32(3),
				f32(72),
			)
			if !galaxy_point_visible(clump_center, -clump_pixels) do continue
			clump_hatch.layer_count = contour_layers
			clump_hatch.rotation = base_rotation + f32(contour) * .055
			clump_hatch.offset = V(-clump_center.x, -clump_center.y)
			boundary_warp :=
				f32(.045 + .035 * f32(2 - contour)) +
				f32(.04 * galaxy_star_unit(g.seed, clump, 25))
			rl.DrawEllipseHatched(
				clump_center,
				clump_pixels * f32(clump_aspect),
				clump_pixels * f32(galaxy_map_y_aspect(g) / clump_aspect),
				{210, 215, 202, u8(contour_ink * clump_zoom_ink)},
				clump_hatch,
				48,
				f32(galaxy_map_position_angle(g)),
				boundary_warp,
				f32(galaxy_star_unit(g.seed, clump, 26) * 2 * math.PI),
			)
		}
	}
}
