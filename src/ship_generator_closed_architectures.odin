package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:math"

ship_architecture_has_closed_hull :: proc(kind: game.Ship_Generator_Kind) -> bool {
	return kind == .Single_Hull || kind == .Delta
}

ship_closed_hull_mount_module :: proc(
	r: ^game.Procedural_Ship_Recipe,
	source: game.Procedural_Ship_Placement,
) -> game.Procedural_Ship_Placement {
	architecture := game.ship_generator_kind_supported(r.architecture)
	if !ship_architecture_has_closed_hull(architecture) do return source
	module := source
	half_length := r.frame.keel_length * .5
	half_beam := r.frame.beam * .5
	half_height := r.frame.height * .58
	if architecture == .Single_Hull {
		half_length, half_beam, half_height = ship_single_hull_half_extents(r)
	}
	if architecture == .Delta {
		half_length, half_beam, half_height = ship_delta_half_extents(r)
	}
	side: f32 = source.position[1] < 0 ? -1 : 1
	switch source.module {
	case .Drive:
		module.position = {
			-half_length * .88,
			clamp(source.position[1], -half_beam * .28, half_beam * .28),
			clamp(source.position[2], -half_height * .32, half_height * .32),
		}
		module.direction = {-1, 0, 0}
	case .Radiator:
		mount_x := clamp(source.position[0], -half_length * .56, half_length * .48)
		// Sink the deployment root into the armored shoulder. The panels still
		// clear the hull, but end-on views no longer read as a detached crossbar.
		mount_beam := half_beam * .78
		if architecture == .Delta {
			mount_beam, _, _ = ship_delta_section_at_x(
				r.seed,
				half_length,
				half_beam,
				half_height,
				mount_x,
				r.family,
			)
		}
		module.position = {mount_x, side * mount_beam, 0}
		module.direction = {0, side, 0}
	case .Antenna:
		mount_x := clamp(source.position[0], -half_length * .48, half_length * .52)
		if architecture == .Delta {
			section_beam: f32
			section_beam, _, _ = ship_delta_section_at_x(
				r.seed,
				half_length,
				half_beam,
				half_height,
				mount_x,
				r.family,
			)
			mount_y := clamp(source.position[1], -section_beam * .34, section_beam * .34)
			vertical_side: f32 = source.position[2] < 0 ? -1 : 1
			mount_z := ship_delta_surface_z(
				r.seed,
				half_length,
				half_beam,
				half_height,
				mount_x,
				mount_y,
				vertical_side > 0,
				r.family,
			)
			module.position = {mount_x, mount_y, mount_z}
			module.direction = {0, 0, vertical_side}
			// Modular-frame antenna scales can be taller than an entire delta is
			// thick. Bound the installation to the host hull so it reads as a mast,
			// not a disconnected ship-sized slab seen end-on in plan view.
			module.scale[0] = min(module.scale[0], half_length * .045)
			module.scale[1] = min(module.scale[1], half_beam * .075)
			module.scale[2] = min(module.scale[2], half_height * 1.25)
		} else {
			module.position = {mount_x, side * half_beam * .58, half_height * .92}
			module.direction = {0, side, 0}
		}
	case .Keel, .Bow, .Armor, .Pressure_Hull, .Truss, .Tank, .Mission, .Dock, .Ring_Segment:
	}
	return module
}

ship_rendered_transverse_center_of_mass :: proc(
	r: ^game.Procedural_Ship_Recipe,
) -> [2]f32 {
	weighted, total := [2]f32{}, f32(0)
	closed := ship_architecture_has_closed_hull(r.architecture)
	for source in r.modules[:r.module_count] {
		if source.mass <= 0 do continue
		position := source.position
		if closed {
			if ship_module_exposed_by_architecture(r.architecture, source.module) {
				position = ship_closed_hull_mount_module(r, source).position
			} else {
				// The closed pressure body absorbs internal modules into a centered
				// structural envelope; their old frame socket is not a visible or
				// physical outboard installation after hull integration.
				position[1] = 0
				position[2] = 0
			}
		}
		weighted[0] += position[1] * source.mass
		weighted[1] += position[2] * source.mass
		total += source.mass
	}
	if total <= 0 do return {}
	return {weighted[0] / total, weighted[1] / total}
}

ship_rendered_transverse_mass_offset :: proc(r: ^game.Procedural_Ship_Recipe) -> f32 {
	center := ship_rendered_transverse_center_of_mass(r)
	return f32(math.sqrt(f64(center[0] * center[0] + center[1] * center[1])))
}

ship_delta_section_at_x :: proc(
	seed: u64,
	sx, sy, sz, x: f32,
	family := game.Procedural_Ship_Family.Fleet,
) -> (
	half_beam, edge_top, edge_bottom: f32,
) {
	plan := ship_delta_planform(seed, sx, sy, family)
	for i in 0 ..< len(plan) {
		next := (i + 1) % len(plan)
		x0, x1 := plan[i][0], plan[next][0]
		if x < min(x0, x1) - .0001 || x > max(x0, x1) + .0001 || math.abs(x1 - x0) < .0001 do continue
		t := clamp((x - x0) / (x1 - x0), f32(0), f32(1))
		y := plan[i][1] + (plan[next][1] - plan[i][1]) * t
		top0, bottom0 := ship_delta_edge_vertical(seed, x0, i, sx, sz)
		top1, bottom1 := ship_delta_edge_vertical(seed, x1, next, sx, sz)
		candidate_beam := math.abs(y)
		if candidate_beam >= half_beam {
			half_beam = candidate_beam
			edge_top = top0 + (top1 - top0) * t
			edge_bottom = bottom0 + (bottom1 - bottom0) * t
		}
	}
	if half_beam <= .0001 {
		half_beam = sy * .08
		edge_top, edge_bottom = ship_delta_edge_vertical(seed, x, 3, sx, sz)
	}
	return
}

ship_delta_surface_z :: proc(
	seed: u64,
	sx, sy, sz, x, y: f32,
	dorsal: bool,
	family := game.Procedural_Ship_Family.Fleet,
) -> f32 {
	// Match the triangle fan emitted by ship_append_delta_hull_faces exactly.
	// A same-x lateral interpolation is only exact through the fan center; away
	// from it, that approximation leaves small but visible air gaps under masts.
	plan := ship_delta_planform(seed, sx, sy, family)
	center := [2]f32{-sx * (dorsal ? .05 : .12), 0}
	center_z := dorsal ? sz * 1.22 : -sz
	for i in 0 ..< len(plan) {
		next := (i + 1) % len(plan)
		a, b := plan[i], plan[next]
		denom := (b[1] - center[1]) * (a[0] - center[0]) + (center[0] - b[0]) * (a[1] - center[1])
		if math.abs(denom) < .000001 do continue
		wa := ((b[1] - center[1]) * (x - center[0]) + (center[0] - b[0]) * (y - center[1])) / denom
		wb := ((center[1] - a[1]) * (x - center[0]) + (a[0] - center[0]) * (y - center[1])) / denom
		wc := 1 - wa - wb
		if wa < -.0001 || wb < -.0001 || wc < -.0001 do continue
		top_a, bottom_a := ship_delta_edge_vertical(seed, a[0], i, sx, sz)
		top_b, bottom_b := ship_delta_edge_vertical(seed, b[0], next, sx, sz)
		za := dorsal ? top_a : bottom_a
		zb := dorsal ? top_b : bottom_b
		return wc * center_z + wa * za + wb * zb
	}
	// Mount coordinates are clamped inside the planform, but retain a stable
	// fallback for degenerate frames and floating-point boundary cases.
	_, edge_top, edge_bottom := ship_delta_section_at_x(seed, sx, sy, sz, x, family)
	return dorsal ? edge_top : edge_bottom
}
