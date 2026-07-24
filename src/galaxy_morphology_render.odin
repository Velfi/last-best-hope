package main

import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"
import "core:time"
import rl "zelda_engine:canvas2d"

draw_galaxy_structure :: proc(s: ^Ux_State) {
	g := &s.galaxy
	center := galaxy_world_to_screen(s, 0, 0)
	hatch_extent := g.bulge_fraction * (g.morphology == .Elliptical ? .52 : 1)
	bulge_pixels := f32(g.disk_radius_kpc * hatch_extent * galaxy_map_scale(s))
	bulge_aspect := g.morphology == .Elliptical ? f32(galaxy_map_y_aspect(g)) : f32(.84)
	structure_x_pixels := bulge_pixels
	structure_y_pixels := bulge_pixels * bulge_aspect
	structure_rotation := g.morphology == .Elliptical ? f32(galaxy_map_position_angle(g)) : f32(0)
	if g.morphology == .Barred_Spiral {
		bar_radius := g.disk_radius_kpc * g.bulge_fraction
		bar_angle := galaxy_spiral_phase(g, bar_radius)
		major_scale, minor_scale, projected_angle := galaxy_project_ellipse(
			g,
			bar_angle,
			galaxy_bar_axis_ratio(g),
		)
		structure_x_pixels = bulge_pixels * f32(major_scale)
		structure_y_pixels = bulge_pixels * f32(minor_scale)
		structure_rotation = f32(projected_angle)
	}
	rotation_cos := f32(math.cos(f64(structure_rotation)))
	rotation_sin := f32(math.sin(f64(structure_rotation)))
	structure_extent_x := math.sqrt(
		structure_x_pixels * structure_x_pixels * rotation_cos * rotation_cos +
		structure_y_pixels * structure_y_pixels * rotation_sin * rotation_sin,
	)
	structure_extent_y := math.sqrt(
		structure_x_pixels * structure_x_pixels * rotation_sin * rotation_sin +
		structure_y_pixels * structure_y_pixels * rotation_cos * rotation_cos,
	)
	room_x := min(center.x - GALAXY_VIEW.x, GALAXY_VIEW.x + GALAXY_VIEW.width - center.x)
	room_y := min(center.y - GALAXY_VIEW.y, GALAXY_VIEW.y + GALAXY_VIEW.height - center.y)
	fit_x := room_x / max(structure_extent_x, .01)
	fit_y := room_y / max(structure_extent_y, .01)
	// Fade before the ellipse reaches the viewport boundary. This keeps the
	// procedural triangles safely contained without an abrupt zoom/pan pop.
	hatch_visibility := clamp((min(fit_x, fit_y) - 1) / .32, f32(0), f32(1))
	hatch := LBH_HATCH_OUTER_DARK
	hatch_spacing, hatch_irregularity, hatch_rotation := galaxy_hatch_signature(g)
	sersic_n := galaxy_sersic_index(g)
	concentration := f32(sersic_n - 1) / 3
	hatch.invert = true // Untextured geometry supplies the silhouette mask.
	hatch.spacing = hatch_spacing - concentration * .55
	hatch.line_width = .85
	hatch.strength = .72
	hatch.irregularity = hatch_irregularity
	hatch.offset = V(-center.x, -center.y)

	// Crosshatching is reserved for the compressed central mass; the disk itself
	// is rendered from deterministic stars below.
	if hatch_visibility > 0 && g.morphology != .Dwarf_Irregular {
		if g.morphology == .Barred_Spiral {
			// The Ferrers component has finite elliptical support and is distinctly
			// thinner than the Sérsic bulge drawn over it.
			bar_hatch := hatch
			bar_hatch.spacing = hatch_spacing + .35
			bar_hatch.line_width = .88
			bar_hatch.strength = .76
			bar_hatch.layer_count = 2
			bar_hatch.rotation = hatch_rotation
			rl.DrawEllipseHatched(
				center,
				structure_x_pixels,
				structure_y_pixels,
				{220, 216, 198, u8(34 * hatch_visibility)},
				bar_hatch,
				72,
				structure_rotation,
			)
			// The inner resonance ring is a separate, young component outside the
			// finite bar. Project its intrinsic ellipse through the same inclined
			// disk transform used by its explicit catalogue stars.
			bar_radius := g.disk_radius_kpc * g.bulge_fraction
			bar_angle := galaxy_spiral_phase(g, bar_radius)
			ring_major, ring_minor, ring_angle := galaxy_project_ellipse(
				g,
				bar_angle,
				galaxy_bar_inner_ring_axis_ratio(g),
			)
			ring_pixels := galaxy_bar_inner_ring_radius(g) * galaxy_map_scale(s)
			ring_hatch := hatch
			ring_hatch.spacing = hatch_spacing + .8
			ring_hatch.line_width = .72
			ring_hatch.strength = .58
			ring_hatch.layer_count = 2
			ring_hatch.rotation = hatch_rotation + f32(ring_angle) - f32(math.PI * .5)
			ring_hatch.offset = V(-center.x, -center.y)
			ring_zoom_ink := f32(clamp(2 / math.sqrt(s.galaxy_zoom), .38, 1.0))
			rl.DrawEllipseRingHatched(
				center,
				f32(ring_pixels * 1.07 * ring_major),
				f32(ring_pixels * 1.07 * ring_minor),
				f32(ring_pixels * .93 * ring_major),
				f32(ring_pixels * .93 * ring_minor),
				{214, 215, 201, u8(18 * hatch_visibility * ring_zoom_ink)},
				ring_hatch,
				96,
				f32(ring_angle),
				.018,
				.012,
				f32(galaxy_star_unit(g.seed, 0, 69) * 2 * math.PI),
			)
		}
		central_layers := 2 + (sersic_n + 1) / 2
		for layer in 0 ..< central_layers {
			bulge_hatch := hatch
			bulge_hatch.spacing = hatch_spacing - concentration * .55
			bulge_hatch.line_width = .9
			bulge_hatch.layer_count = min(layer + 1, 3)
			bulge_hatch.rotation = hatch_rotation - .08 + f32(layer) * .13
			layer_fraction := f32(layer) / f32(max(central_layers - 1, 1))
			radius_scale := math.pow(1 - layer_fraction * .55, 1 + concentration * .32)
			base_alpha := f32(26 + layer * 7) + concentration * 9
			central_scale := g.morphology == .Barred_Spiral ? f32(.62) : f32(1)
			central_aspect := g.morphology == .Barred_Spiral ? f32(.68) : bulge_aspect
			rl.DrawEllipseHatched(
				center,
				bulge_pixels * central_scale * radius_scale,
				bulge_pixels * central_scale * central_aspect * radius_scale,
				{224, 219, 201, u8(base_alpha * hatch_visibility)},
				bulge_hatch,
				72,
				g.morphology == .Barred_Spiral ? 0 : structure_rotation,
			)
		}
		rl.DrawCircleV(center, 2.5, {236, 231, 211, u8(135 * hatch_visibility)})
	}
	draw_galaxy_elliptical_isophotes(s, center, hatch_spacing, hatch_irregularity, hatch_rotation)
	if g.morphology == .Spiral || g.morphology == .Barred_Spiral {
		// Broken ribbons follow the same analytic density maxima as the stars.
		// Their gaps suggest transient, recurrent arms while preserving the black
		// inter-arm channels required by the engraving treatment.
		arm_hatch := LBH_HATCH_OUTER_DARK
		arm_hatch.invert = true
		arm_hatch.spacing = 6.8
		arm_hatch.line_width = .92
		arm_hatch.strength = .76
		arm_hatch.irregularity = hatch_irregularity
		arm_hatch.layer_count = 2
		arm_hatch.edge_softness = 0 // Ribbon geometry supplies its own taper.
		map_scale := galaxy_map_scale(s)
		for arm in 0 ..< g.spiral_arm_count {
			for association in 3 ..< GALAXY_ARM_ASSOCIATION_COUNT - 1 {
				// Engrave only a seeded subset of the same radial associations used
				// by young stars. This prevents a resolved arm from becoming one long
				// artificial stripe while retaining a coherent large-scale spiral.
				association_key := arm * GALAXY_ARM_ASSOCIATION_COUNT + association
				if galaxy_star_unit(g.seed, association_key, 42) > .58 do continue
				POINT_COUNT :: 7
				points: [POINT_COUNT]rl.Vector2
				half_widths: [POINT_COUNT]f32
				mid_fraction := galaxy_arm_association_radius_fraction(g, arm, association)
				span_fraction := .032 + galaxy_star_unit(g.seed, association_key, 41) * .020
				start_fraction := mid_fraction - span_fraction * .5
				end_fraction := mid_fraction + span_fraction * .5
				mid_radius := g.disk_radius_kpc * mid_fraction
				mid_theta := galaxy_spiral_theta(g, arm, mid_radius)
				midpoint := galaxy_world_to_screen(
					s,
					mid_radius * math.cos(mid_theta),
					mid_radius * math.sin(mid_theta),
				)
				for point_index in 0 ..< POINT_COUNT {
					t := f64(point_index) / f64(POINT_COUNT - 1)
					radius_fraction := start_fraction + (end_fraction - start_fraction) * t
					radius := g.disk_radius_kpc * radius_fraction
					theta := galaxy_spiral_theta(g, arm, radius)
					points[point_index] = galaxy_world_to_screen(
						s,
						radius * math.cos(theta),
						radius * math.sin(theta),
					)
					envelope := galaxy_spiral_arm_envelope(g, radius)
					coherence := galaxy_spiral_arm_coherence(g, arm, radius)
					taper := .25 + .75 * math.sin(math.PI * t)
					half_widths[point_index] = clamp(
						f32(
							g.disk_radius_kpc *
							(.018 + .012 * radius_fraction) *
							envelope *
							math.sqrt(coherence) *
							taper *
							map_scale,
						),
						f32(2.6),
						f32(14),
					)
				}
				arm_envelope := galaxy_spiral_arm_envelope(g, mid_radius)
				arm_coherence := galaxy_spiral_arm_coherence(g, arm, mid_radius)
				arm_tangent := galaxy_projected_spiral_tangent_angle(g, arm, mid_radius)
				// Shader angles describe stroke normals. Rotating their frame by
				// tangent-pi/2 makes the two engraved cuts straddle the local arm
				// direction instead of forming a screen-aligned lattice.
				arm_hatch.rotation =
					f32(arm_tangent - math.PI * .5) +
					hatch_rotation +
					f32(galaxy_star_unit(g.seed, association_key, 43) * .18 - .09)
				arm_hatch.offset = V(-midpoint.x, -midpoint.y)
				rl.DrawRibbonHatched(
					points[:],
					half_widths[:],
					{
						216,
						215,
						201,
						galaxy_arm_hatch_alpha(arm_envelope, arm_coherence, s.galaxy_zoom),
					},
					arm_hatch,
				)
			}
		}
	}
	draw_galaxy_irregular_clumps(s, hatch_irregularity, hatch_rotation)
	draw_galaxy_stars(s)
	draw_galaxy_lod_stars(s)
	draw_galaxy_central_black_hole(s)
	draw_galaxy_world_ring(s, g.habitable_zone_inner_kpc, {126, 191, 151, 85})
	draw_galaxy_world_ring(s, g.habitable_zone_outer_kpc, {126, 191, 151, 85})
}

draw_galaxy_central_black_hole :: proc(s: ^Ux_State) {
	g := &s.galaxy
	if !g.central_black_hole_occupied do return
	center := galaxy_world_to_screen(s, 0, 0)
	// The event horizon is far below map resolution. These broken lensing rings
	// are an archival locator whose logarithmic size reports mass without
	// pretending that the survey has detected an accretion disk.
	mass_scale := f32(clamp((math.log10(max(g.central_black_hole_mass_solar, 1)) - 3) / 7, 0, 1))
	radius := (5.5 + mass_scale * 5.5) * f32(clamp(math.sqrt(s.galaxy_zoom), .8, 1.8))
	ink := rl.Color{224, 185, 96, 205}
	hit_radius := max(
		radius + 5,
		f32(12),
	); hit := R(center.x - hit_radius, center.y - hit_radius, hit_radius * 2, hit_radius * 2)
	interaction := rl.ButtonBehavior(ux_button_cursor, hit, true); ux_button_cursor += 1
	if interaction.activated && s.modal == .None {s.selected_body = {
			kind = .Central_Black_Hole,
		}; s.modal = .Body_Detail}
	if interaction.hovered || interaction.focused {
		ux_tooltip = {
			visible = true,
			anchor  = hit,
			title   = "CENTRAL BLACK HOLE",
			body    = fmt.tprintf(
				"%.2e M-SOLAR · Select for survey detail.",
				g.central_black_hole_mass_solar,
			),
		}
	}
	for ring in 0 ..< 2 {
		r := radius + f32(ring) * 3.5
		for segment in 0 ..< 20 {
			if (segment + ring * 3) % 7 == 0 do continue
			a0 := f32(segment) * 2 * f32(math.PI) / 20 + .18
			a1 := f32(segment + 1) * 2 * f32(math.PI) / 20 + .18
			p0 := V(center.x + math.cos(a0) * r, center.y + math.sin(a0) * r * .42)
			p1 := V(center.x + math.cos(a1) * r, center.y + math.sin(a1) * r * .42)
			rl.DrawLineEx(p0, p1, ring == 0 ? f32(1.15) : f32(.65), ink)
		}
	}
	rl.DrawCircleV(center, max(radius * .42, f32(3.2)), {2, 3, 3, 255})
	rl.DrawCircleV(center, 1.1, {231, 229, 211, 170})
	if s.galaxy_zoom >= 5 {
		draw_text("CENTRAL BLACK HOLE", center.x + radius + 7, center.y - 7, TYPE_FINE, UX.warn)
	}
}

galaxy_neighborhood_color :: proc(n: game.Galactic_Neighborhood) -> rl.Color {
	switch n.population {
	case .Young_Association:
		return {104, 181, 198, 235}
	case .Thin_Disk:
		return {218, 226, 230, 205}
	case .Thick_Disk:
		return {224, 185, 96, 210}
	case .Bulge:
		return {221, 166, 110, 220}
	case .Halo:
		return {183, 143, 220, 190}
	}
	return UX.text
}

galaxy_detailed_system_index :: proc(g: ^game.Galaxy, neighborhood_index: int) -> int {
	for sample, i in g.detailed_systems[:g.detailed_system_count] do if sample.neighborhood_index == neighborhood_index do return i
	return -1
}

galaxy_fleet_neighborhood_index :: proc(s: ^Ux_State) -> int {
	if s == nil ||
	   s.campaign == nil ||
	   s.campaign.galaxy == nil ||
	   !s.campaign.fleet_navigation.initialized {
		return -1
	}
	system_index := s.campaign.fleet_navigation.system_index
	if system_index < 0 || system_index >= s.campaign.galaxy.detailed_system_count do return -1
	return s.campaign.galaxy.detailed_systems[system_index].neighborhood_index
}

draw_galaxy_fleet_marker :: proc(
	s: ^Ux_State,
	p: rl.Vector2,
	radius: f32,
	neighborhood_index: int,
) {
	// The fleet occupies this system, but must not obscure its survey node. Keep
	// the locator offset and tether it with a fine rule so both identities remain
	// legible at a glance.
	marker := radius + 7
	anchor := V(p.x + radius + 18, p.y - radius - 18)
	rl.DrawLineEx(
		V(p.x + radius * .7, p.y - radius * .7),
		V(anchor.x - marker * .66, anchor.y + marker * .66),
		.8,
		{UX.info.r, UX.info.g, UX.info.b, 170},
	)
	rl.DrawLineEx(V(anchor.x, anchor.y - marker), V(anchor.x + marker, anchor.y), 1, UX.info)
	rl.DrawLineEx(V(anchor.x + marker, anchor.y), V(anchor.x, anchor.y + marker), 1, UX.info)
	rl.DrawLineEx(V(anchor.x, anchor.y + marker), V(anchor.x - marker, anchor.y), 1, UX.info)
	rl.DrawLineEx(V(anchor.x - marker, anchor.y), V(anchor.x, anchor.y - marker), 1, UX.info)
	rl.DrawLineEx(
		V(anchor.x - marker - 4, anchor.y),
		V(anchor.x - marker + 2, anchor.y),
		1.5,
		UX.info,
	)
	rl.DrawLineEx(
		V(anchor.x + marker - 2, anchor.y),
		V(anchor.x + marker + 4, anchor.y),
		1.5,
		UX.info,
	)
	rl.DrawLineEx(
		V(anchor.x, anchor.y - marker - 4),
		V(anchor.x, anchor.y - marker + 2),
		1.5,
		UX.info,
	)
	rl.DrawLineEx(
		V(anchor.x, anchor.y + marker - 2),
		V(anchor.x, anchor.y + marker + 4),
		1.5,
		UX.info,
	)
	draw_text("FLEET", anchor.x + marker + 7, anchor.y - 7, TYPE_LABEL, UX.info)

	hit := R(anchor.x - marker - 5, anchor.y - marker - 5, marker * 2 + 58, marker * 2 + 10)
	interaction := rl.ButtonBehavior(ux_button_cursor, hit, true)
	ux_button_cursor += 1
	if interaction.activated do s.selected_neighborhood = neighborhood_index
	if interaction.hovered || interaction.focused {
		ux_tooltip = {
			visible = true,
			anchor  = hit,
			title   = "FLEET LOCATION",
			body    = "Select to inspect the stellar system occupied by the fleet.",
		}
	}
}

draw_galaxy_navigation_target_marker :: proc(p: rl.Vector2, radius, remaining_kpc: f32) {
	marker := radius + 8
	// Violet is reserved for a player commitment; the target is not another
	// survey result or contact classification.
	rl.DrawLineEx(V(p.x, p.y - marker), V(p.x + marker, p.y), 1.5, UX.committed)
	rl.DrawLineEx(V(p.x + marker, p.y), V(p.x, p.y + marker), 1.5, UX.committed)
	rl.DrawLineEx(V(p.x, p.y + marker), V(p.x - marker, p.y), 1.5, UX.committed)
	rl.DrawLineEx(V(p.x - marker, p.y), V(p.x, p.y - marker), 1.5, UX.committed)
	rl.DrawLineEx(V(p.x - 3, p.y - 3), V(p.x + 3, p.y + 3), 1.5, UX.committed)
	rl.DrawLineEx(V(p.x + 3, p.y - 3), V(p.x - 3, p.y + 3), 1.5, UX.committed)
	draw_fmt(
		p.x + marker + 7,
		p.y - 7,
		TYPE_LABEL,
		UX.committed,
		"TARGET · %.1f KPC REMAINING",
		remaining_kpc,
	)
}

update_galaxy_camera :: proc(s: ^Ux_State) {
	if s.galaxy_zoom <= 0 do s.galaxy_zoom = 1
	if !contains(GALAXY_VIEW) do return
	scale_before := galaxy_map_scale(s)
	mouse_projected_x := f64(ux_mouse.x - (GALAXY_VIEW.x + GALAXY_VIEW.width / 2))
	mouse_projected_y := f64(ux_mouse.y - (GALAXY_VIEW.y + GALAXY_VIEW.height / 2))
	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		before_x, before_y := galaxy_unproject_world_delta(
			&s.galaxy,
			mouse_projected_x / scale_before,
			mouse_projected_y / scale_before,
		)
		world_x, world_y := s.galaxy_pan_x + before_x, s.galaxy_pan_y + before_y
		s.galaxy_zoom = clamp(s.galaxy_zoom * math.exp(f64(wheel) * 0.18), 0.55, 160.0)
		scale_after := galaxy_map_scale(s)
		after_x, after_y := galaxy_unproject_world_delta(
			&s.galaxy,
			mouse_projected_x / scale_after,
			mouse_projected_y / scale_after,
		)
		s.galaxy_pan_x, s.galaxy_pan_y = world_x - after_x, world_y - after_y
	}
	if rl.IsMouseButtonDown(.LEFT) {
		delta := rl.GetMouseDelta()
		scale := galaxy_map_scale(s)
		world_delta_x, world_delta_y := galaxy_unproject_world_delta(
			&s.galaxy,
			f64(delta.x / ux_zoom) / scale,
			f64(delta.y / ux_zoom) / scale,
		)
		s.galaxy_pan_x -= world_delta_x
		s.galaxy_pan_y -= world_delta_y
	}
}

draw_galaxy_neighborhoods :: proc(s: ^Ux_State) {
	fleet_neighborhood := galaxy_fleet_neighborhood_index(s)
	target_neighborhood := -1
	target_remaining_kpc := f64(0)
	if s.campaign.long_term_navigation_goal.active {
		goal := game.long_term_navigation_goal_progress(s.campaign)
		if goal.valid {
			target_neighborhood = goal.target_neighborhood
			target_remaining_kpc = goal.remaining_distance_kpc
		}
	}
	if fleet_neighborhood >= 0 &&
	   target_neighborhood >= 0 &&
	   fleet_neighborhood < s.galaxy.neighborhood_count &&
	   target_neighborhood < s.galaxy.neighborhood_count &&
	   fleet_neighborhood != target_neighborhood {
		fleet := s.galaxy.neighborhoods[fleet_neighborhood]
		target := s.galaxy.neighborhoods[target_neighborhood]
		rl.DrawLineEx(
			galaxy_world_to_screen(s, fleet.x_kpc, fleet.y_kpc),
			galaxy_world_to_screen(s, target.x_kpc, target.y_kpc),
			1,
			UX.committed,
		)
	}
	for n, i in s.galaxy.neighborhoods[:s.galaxy.neighborhood_count] {
		p := galaxy_world_to_screen(s, n.x_kpc, n.y_kpc)
		if !galaxy_point_visible(p, 4) do continue
		detail := galaxy_detailed_system_index(&s.galaxy, i)
		detailed := detail >= 0
		contact_count := game.habitable_contacts_at_neighborhood(s.campaign, i)
		life_supporting := contact_count > 0
		radius := f32(clamp(1.6 + math.log2(max(s.galaxy_zoom, 1.0)) * 0.7, 1.6, 6.0))
		if detailed do radius += 2
		if life_supporting {
			marker := radius + 8
			rl.DrawLineEx(V(p.x, p.y - marker), V(p.x + marker, p.y), 1.5, UX.good)
			rl.DrawLineEx(V(p.x + marker, p.y), V(p.x, p.y + marker), 1.5, UX.good)
			rl.DrawLineEx(V(p.x, p.y + marker), V(p.x - marker, p.y), 1.5, UX.good)
			rl.DrawLineEx(V(p.x - marker, p.y), V(p.x, p.y - marker), 1.5, UX.good)
		}
		if s.selected_neighborhood == i {
			selection_hatch := LBH_HATCH_ENGRAVING
			selection_hatch.invert = true
			selection_hatch.spacing = 4
			selection_hatch.line_width = .75
			selection_hatch.strength = .82
			selection_hatch.layer_count = 2
			selection_hatch.edge_softness = .24
			selection_hatch.offset = V(-p.x, -p.y)
			rl.DrawCircleHatched(p, radius + 5, {104, 181, 198, 110}, selection_hatch, 28)
		}
		rl.DrawCircleV(
			p,
			radius,
			life_supporting ? UX.good : detailed ? UX.info : galaxy_neighborhood_color(n),
		)
		if i == fleet_neighborhood do draw_galaxy_fleet_marker(s, p, radius, i)
		if i == target_neighborhood && i != fleet_neighborhood do draw_galaxy_navigation_target_marker(p, radius, f32(target_remaining_kpc))
		if s.galaxy_zoom >= 9 &&
		   p.x < GALAXY_VIEW.x + GALAXY_VIEW.width - 90 &&
		   (detailed || s.selected_neighborhood == i) {
			if life_supporting {
				draw_fmt(
					p.x + 8,
					p.y - 7,
					TYPE_LABEL,
					UX.good,
					"%d CANDIDATE%s · REGION %02d",
					contact_count,
					contact_count != 1 ? "S" : "",
					i + 1,
				)
			} else {
				draw_fmt(
					p.x + 8,
					p.y - 7,
					TYPE_LABEL,
					detailed ? UX.info : UX.dim,
					"SYSTEM %02d",
					i + 1,
				)
			}
		}
		if rl.IsMouseButtonPressed(.LEFT) && contains(R(p.x - 9, p.y - 9, 18, 18)) do s.selected_neighborhood = i
	}
}
