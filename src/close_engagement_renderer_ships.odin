package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:math"
import "core:mem"
import "core:testing"
import "core:time"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
dark_append_recipe_ship :: proc(
	ship: ^game.Ship,
	anchor: game.Combat_Vec3,
	visual_scale, facing, pitch, bank, power: f32,
	ink, engine_ink: [4]f32,
) {
	recipe := game.procedural_ship_generate_for_ship(ship^)
	for module in recipe.modules[:recipe.module_count] {
		sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]
		// Every recipe module is a depth-tested world cage. Cylindrical machinery
		// gets true transverse sections; structural modules retain their authored
		// mount direction and proportions.
		corners := [8][3]f32 {
			{-sx, -sy, -sz},
			{sx, -sy, -sz},
			{sx, sy, -sz},
			{-sx, sy, -sz},
			{-sx, -sy, sz},
			{sx, -sy, sz},
			{sx, sy, sz},
			{-sx, sy, sz},
		}
		edges := [12][2]int {
			{0, 1},
			{1, 2},
			{2, 3},
			{3, 0},
			{4, 5},
			{5, 6},
			{6, 7},
			{7, 4},
			{0, 4},
			{1, 5},
			{2, 6},
			{3, 7},
		}
		module_ink := ink; if module.module == .Drive do module_ink = engine_ink
		if module.module == .Radiator do module_ink = {ink[0], ink[1], ink[2], .62}
		for edge in edges {a := dark_ship_point(module, corners[edge[0]], anchor, visual_scale, facing, pitch, bank); b := dark_ship_point(module, corners[edge[1]], anchor, visual_scale, facing, pitch, bank); combat_3d_append_line(a, b, module_ink)}
		if module.module == .Pressure_Hull ||
		   module.module == .Tank ||
		   module.module == .Drive ||
		   module.module == .Ring_Segment {
			segments := 12
			for end in -1 ..= 1 {if end == 0 do continue; x := f32(end) * sx; for segment in 0 ..< segments {a := f32(segment) * 2 * math.PI / f32(segments); b := f32(segment + 1) * 2 * math.PI / f32(segments); p0 := dark_ship_point(module, {x, f32(math.cos(f64(a))) * sy, f32(math.sin(f64(a))) * sz}, anchor, visual_scale, facing, pitch, bank); p1 := dark_ship_point(module, {x, f32(math.cos(f64(b))) * sy, f32(math.sin(f64(b))) * sz}, anchor, visual_scale, facing, pitch, bank); combat_3d_append_line(p0, p1, module_ink)}}
		}
		if module.module == .Drive && power > .01 {
			plume := sx * (.35 + power * 2.8)
			plume_ink := [4]f32 {
				engine_ink[0],
				engine_ink[1],
				engine_ink[2],
				engine_ink[3] * (.24 + power * .76),
			}
			for offset in -1 ..= 1 {
				y := f32(offset) * sy * .42
				a := dark_ship_point(
					module,
					{-sx, y, 0},
					anchor,
					visual_scale,
					facing,
					pitch,
					bank,
				)
				b := dark_ship_point(
					module,
					{-sx - plume, y * (1 + power * .35), 0},
					anchor,
					visual_scale,
					facing,
					pitch,
					bank,
				)
				combat_3d_append_line(a, b, plume_ink)
			}
		}
		if module.service_mark !=
		   .None {mark := dark_ship_point(module, {0, sy * 1.08, sz * 1.08}, anchor, visual_scale, facing, pitch, bank); tip := dark_ship_point(module, {sx * .35, sy * 1.3, sz * 1.42}, anchor, visual_scale, facing, pitch, bank); combat_3d_append_line(mark, tip, module.service_mark == .Dark_Scar ? engine_ink : ink)}
	}
}

combat_3d_recipe_extent :: proc(recipe: ^game.Procedural_Ship_Recipe) -> f32 {
	extent: f32 = 1
	for module in recipe.modules[:recipe.module_count] {
		extent = max(
			extent,
			math.abs(module.position[0]) + module.scale[0],
			math.abs(module.position[1]) + module.scale[1],
			math.abs(module.position[2]) + module.scale[2],
		)
	}
	return extent
}

combat_3d_formation_anchor :: proc(
	center: game.Combat_Vec3,
	facing: f32,
	slot, count: int,
	spacing: f32,
) -> game.Combat_Vec3 {
	columns := min(max(count, 1), 3); row := slot / columns; column := slot % columns
	rows := (count + columns - 1) / columns
	forward := (f32(row) - f32(rows - 1) * .5) * spacing * .82
	across := (f32(column) - f32(columns - 1) * .5) * spacing
	c, s := f32(math.cos(f64(facing))), f32(math.sin(f64(facing)))
	return {
		center.x + forward * c - across * s,
		center.y + forward * s + across * c,
		center.z + (f32((slot % 2) * 2 - 1)) * spacing * .12,
	}
}

combat_3d_friendly_unit_has_recipe_ship :: proc(s: ^Ux_State, unit_index: int) -> bool {
	if unit_index < 0 || unit_index >= s.combat.friendly_count do return false
	for ship_id, i in s.combat.campaign_ships[:s.combat.campaign_ship_count] {
		if s.combat.campaign_ship_elements[i] != unit_index do continue
		if i < len(s.combat.campaign_ship_roster_indices) {
			roster := s.combat.campaign_ship_roster_indices[i]
			if roster < 0 || roster >= s.combat.ship_count || s.combat.ships[roster].hull <= 0 do continue
		}
		if game.ship_index(s.campaign, ship_id) >= 0 do return true
	}
	return false
}

combat_3d_unit_uses_contact_glyph :: proc(s: ^Ux_State, unit_index: int) -> bool {
	if unit_index < 0 || unit_index >= s.combat.unit_count do return false
	if unit_index < s.combat.friendly_count do return !combat_3d_friendly_unit_has_recipe_ship(s, unit_index)
	// Unknown hostile construction remains a sensor truth rather than an
	// invented hull. Identification replaces the glyph with the seeded model.
	return game.combat_contact_trace(&s.combat, .Friendly, unit_index).identity != .Identified
}

combat_3d_ship_world_point :: proc(
	p: [3]f32,
	anchor: game.Combat_Vec3,
	scale, c, s: f32,
) -> [3]f32 {
	x, y, z := p[0] * scale, p[1] * scale, p[2] * scale
	return {anchor.x + x * c - y * s, anchor.y + x * s + y * c, anchor.z + z}
}

combat_3d_append_recipe_at_unit :: proc(
	ship: ^game.Ship,
	u: ^game.Combat_Unit,
	slot, count: int,
	ink, engine_ink: [4]f32,
) {
	recipe := game.procedural_ship_generate_for_ship(ship^)
	display_size := game.ship_tonnage_visual_scale(max(ship.mass_tonnes, u.tonnage_each))
	// Fit the generated hull inside its existing tactical footprint. Formation
	// offsets remain wider than the hulls, so individual persistent ships read as
	// a group without changing the command element's simulation position.
	visual_scale := display_size / max(combat_3d_recipe_extent(&recipe) * 1.25, 1)
	anchor := combat_3d_formation_anchor(
		u.position,
		u.facing,
		slot,
		count,
		max(display_size * .72, 7),
	)
	faces := make([dynamic]Ship_Project_Face, 0, recipe.module_count * 24, context.temp_allocator)
	dummy_camera := Ship_Generator_Camera{}
	if ship_architecture_has_closed_hull(recipe.architecture) {
		ship_append_closed_architecture_faces(&faces, &recipe, dummy_camera, {}, 1)
	} else {
		for station in 1 ..< recipe.frame.station_count do ship_append_keel_bridge_faces(&faces, &recipe, station, dummy_camera, {}, 1)
		ship_append_strike_prow_bridle_faces(&faces, &recipe, dummy_camera, {}, 1)
		ship_append_modular_fleet_weapon_faces(&faces, &recipe, dummy_camera, {}, 1)
	}
	greebly_budgets := [5]int {
		0,
		8,
		16,
		30,
		48,
	}; greebly_budget := greebly_budgets[clamp(recipe.greebly_density, 0, 4)]
	if greebly_budget > 0 && ship_architecture_has_closed_hull(recipe.architecture) {
		greebly_budget -= ship_append_closed_hull_auto_greeblies(
			&faces,
			&recipe,
			recipe.greebly_density,
			greebly_budget,
			dummy_camera,
			{},
			1,
		)
	}
	for module in recipe.modules[:recipe.module_count] {
		if !ship_module_exposed_by_architecture(recipe.architecture, module.module) do continue
		mounted := ship_closed_hull_mount_module(&recipe, module)
		ship_append_module_faces(&faces, mounted, recipe.family, dummy_camera, {}, 1)
		if greebly_budget > 0 do greebly_budget -= ship_append_auto_greeblies(&faces, mounted, recipe.greebly_density, greebly_budget, dummy_camera, {}, 1)
	}
	c, sn := f32(math.cos(f64(u.facing))), f32(math.sin(f64(u.facing)))
	for face in faces {
		base := face.material == .Drive ? engine_ink : ink
		world := [4][3]f32{}
		for point, i in face.world do world[i] = combat_3d_ship_world_point(point, anchor, visual_scale, c, sn)
		// The fleet-screen silhouette and panel boundaries become depth-tested
		// engraved cuts over the same shared faces.
		edge_ink := base; edge_ink[3] = face.material == .Glass ? 1 : .90
		for edge in 0 ..< 4 do combat_3d_append_line(world[edge], world[(edge + 1) % 4], edge_ink)
	}
}

combat_3d_append_procedural_fleet :: proc(s: ^Ux_State) {
	friendly_ink := [4]f32{.82, .88, .85, .88}; friendly_engine := [4]f32{.58, .68, .69, .82}
	raider_ink := [4]f32{.70, .37, .31, .76}; raider_engine := [4]f32{.82, .58, .39, .82}
	counts: [game.COMBAT_GROUP_COUNT]int; cursors: [game.COMBAT_GROUP_COUNT]int
	for element in s.combat.campaign_ship_elements[:s.combat.campaign_ship_count] do if element >= 0 && element < len(counts) do counts[element] += 1
	// Friendly command elements retain the exact construction seed, refit,
	// service marks, and scars of every campaign ship assigned to them.
		for ship_id, i in s.combat.campaign_ships[:s.combat.campaign_ship_count] {
			element :=
				s.combat.campaign_ship_elements[i]; if element < 0 || element >= s.combat.friendly_count || element >= len(cursors) do continue
		if i <
		   len(
			   s.combat.campaign_ship_roster_indices,
		   ) {roster := s.combat.campaign_ship_roster_indices[i]; if roster >= 0 && roster < s.combat.ship_count && s.combat.ships[roster].hull <= 0 do continue}
		u, visible := combat_3d_display_unit(s, element); if !visible do continue
		ship_at := game.ship_index(s.campaign, ship_id); if ship_at < 0 do continue
		ink := friendly_ink; engine_ink := friendly_engine
		if u.disabled {ink = {.38, .38, .35, .62}; engine_ink = ink}
		combat_3d_append_recipe_at_unit(
			&s.campaign.ships[ship_at],
			&u,
			cursors[element],
			max(counts[element], 1),
			ink,
			engine_ink,
		)
		cursors[element] += 1
	}
	// Hostile construction becomes legible only after identification. Before
	// then the existing sensor glyph remains the truthful presentation.
	for unit_index in s.combat.friendly_count ..< s.combat.unit_count {
		trace := game.combat_contact_trace(&s.combat, .Friendly, unit_index)
		if trace.identity != .Identified do continue
		u, visible := combat_3d_display_unit(s, unit_index); if !visible do continue
		shown := min(max(u.formation_active, 1), 3)
		for member in 0 ..< shown {
			seed := game.combat_ship_id(s.combat.seed, unit_index, member)
			ship := game.Ship {
				id                = game.Ship_ID(seed),
				construction_seed = seed,
				hull_archetype    = u.hull_archetype,
				operational_role  = u.operational_role,
				mass_tonnes       = u.tonnage_each,
				active            = true,
			}
			ink :=
				u.disabled ? [4]f32{.38, .38, .35, .58} : raider_ink; engine_ink := u.disabled ? ink : raider_engine
			combat_3d_append_recipe_at_unit(&ship, &u, member, shown, ink, engine_ink)
		}
	}
}

DARK_DEPTH_BAND_SPACING :: f64(1.25)

Dark_Umbilical_Grammar :: enum {
	Continuous,
	Caution,
	Uncertain,
	Unavailable,
}

dark_render_depth :: proc(d: ^game.Dark_Continuum, p: game.Dark_Vec4) -> f64 {
	return game.dark_depth_from_anchor(d.seed, d.anchor_position, p)
}

dark_course_maximum_depth :: proc(
	d: ^game.Dark_Continuum,
	course: ^game.Dark_Course,
) -> (
	depth: f64,
	index: int,
) {
	index = -1
	for point, i in course.waypoints[:course.waypoint_count] {
		candidate := dark_render_depth(d, point.position)
		if index < 0 || candidate > depth {depth = candidate; index = i}
	}
	return
}

dark_course_band_crossings :: proc(
	d: ^game.Dark_Continuum,
	course: ^game.Dark_Course,
	spacing: f64,
) -> int {
	if spacing <= 0 do return 0
	count := 0
	for i in 1 ..< course.waypoint_count {
		a := int(math.floor(dark_render_depth(d, course.waypoints[i - 1].position) / spacing))
		b := int(math.floor(dark_render_depth(d, course.waypoints[i].position) / spacing))
		count += abs(b - a)
	}
	return count
}

dark_umbilical_grammar :: proc(
	exit_known: bool,
	coherence, limit, confidence: f64,
) -> Dark_Umbilical_Grammar {
	if !exit_known do return .Unavailable
	if confidence < .52 do return .Uncertain
	if coherence >= limit * .72 do return .Caution
	return .Continuous
}

dark_append_depth_lamina :: proc(
	center: game.Combat_Vec3,
	radius: f32,
	band: int,
	seed: u64,
	color: [4]f32,
) {
	segments := 72
	for plane in 0 ..< 3 {
		for segment in 0 ..< segments {
			hash := game.combat_mix(
				seed + u64(band + 257) * 0x9e3779b97f4a7c15 + u64(plane * segments + segment),
			)
			// Broad deterministic omissions retain black rest. Every third
			// surviving fragment is extended to make primary structure legible.
			if hash & 0xff < 92 do continue
			a := f32(segment) / f32(segments) * 2 * math.PI
			run := 1 + int((hash >> 8) & 1)
			b := f32(min(segment + run, segments)) / f32(segments) * 2 * math.PI
			ca, sa := f32(math.cos(f64(a))) * radius, f32(math.sin(f64(a))) * radius
			cb, sb := f32(math.cos(f64(b))) * radius, f32(math.sin(f64(b))) * radius
			p0, p1 := center, center
			switch plane {
			case 0:
				p0.x += ca; p0.y += sa; p1.x += cb; p1.y += sb
			case 1:
				p0.x += ca; p0.z += sa; p1.x += cb; p1.z += sb
			case 2:
				p0.y += ca; p0.z += sa; p1.y += cb; p1.z += sb
			}
			alpha := color[3] * (plane == 0 ? .86 : .54)
			combat_3d_append_line(
				{p0.x, p0.y, p0.z},
				{p1.x, p1.y, p1.z},
				{color[0], color[1], color[2], alpha},
			)
		}
	}
}

dark_append_umbilical :: proc(
	a, b: game.Combat_Vec3,
	grammar: Dark_Umbilical_Grammar,
	color: [4]f32,
) {
	segments :=
		grammar == .Continuous ? 1 : grammar == .Caution ? 10 : grammar == .Uncertain ? 14 : 8
	for i in 0 ..< segments {
		if grammar == .Caution && i % 2 == 1 do continue
		if grammar == .Uncertain && (i % 4 == 1 || i % 4 == 2) do continue
		if grammar == .Unavailable && i % 2 == 1 do continue
		t0, t1 := f32(i) / f32(segments), f32(i + 1) / f32(segments)
		p0 := game.Combat_Vec3 {
			a.x + (b.x - a.x) * t0,
			a.y + (b.y - a.y) * t0,
			a.z + (b.z - a.z) * t0,
		}
		p1 := game.Combat_Vec3 {
			a.x + (b.x - a.x) * t1,
			a.y + (b.y - a.y) * t1,
			a.z + (b.z - a.z) * t1,
		}
		combat_3d_append_line({p0.x, p0.y, p0.z}, {p1.x, p1.y, p1.z}, color)
		if grammar == .Unavailable {
			m := game.Combat_Vec3{(p0.x + p1.x) * .5, (p0.y + p1.y) * .5, (p0.z + p1.z) * .5}
			combat_3d_append_line({m.x - 4, m.y - 4, m.z}, {m.x + 4, m.y + 4, m.z}, color)
		}
	}
}

dark_append_course :: proc(
	s: ^Ux_State,
	d: ^game.Dark_Continuum,
	course: ^game.Dark_Course,
	view_origin: game.Dark_Vec4,
	scale: f32,
	preview: bool,
	info, warn, committed: [4]f32,
) {
	if course.waypoint_count < 2 do return
	total := f64(0)
	for i in 1 ..< course.waypoint_count do total += game.dark_metric_distance(d.seed, course.waypoints[i - 1].position, course.waypoints[i].position)
	accumulated := f64(0)
	forecast := game.passage_course_coherence_forecast(s.campaign, &s.campaign.passage, course)
	for i in 1 ..< course.waypoint_count {
		a, b := course.waypoints[i - 1].position, course.waypoints[i].position
		segment := game.dark_metric_distance(d.seed, a, b)
		depth_a, depth_b := dark_render_depth(d, a), dark_render_depth(d, b)
		risk := max(depth_a, depth_b) / max(forecast.limit * 4, 1)
		color := info
		if !preview && risk > .72 do color = warn
		if forecast.crosses_limit do color = [4]f32{.78, .34, .24, .96}
		alpha := preview ? f32(.54) : f32(.86)
		combat_3d_append_dark_course_line(
			{
				f32(a[0] - view_origin[0]) * scale,
				f32(a[1] - view_origin[1]) * scale,
				f32(a[2] - view_origin[2]) * scale,
			},
			{
				f32(b[0] - view_origin[0]) * scale,
				f32(b[1] - view_origin[1]) * scale,
				f32(b[2] - view_origin[2]) * scale,
			},
			{color[0], color[1], color[2], alpha},
			f32(depth_a),
			f32(depth_b),
			f32(accumulated / max(total, .001)),
			f32((accumulated + segment) / max(total, .001)),
		)
		accumulated += segment
	}
	max_depth, max_at := dark_course_maximum_depth(d, course)
	if max_at >= 0 {
		point := course.waypoints[max_at].position
		p := game.Combat_Vec3 {
			f32(point[0] - view_origin[0]) * scale,
			f32(point[1] - view_origin[1]) * scale,
			f32(point[2] - view_origin[2]) * scale,
		}
		bracket := f32(8 + min(max_depth, 8) * .7)
		combat_3d_append_line(
			{p.x - bracket, p.y - bracket, p.z},
			{p.x - bracket * .25, p.y - bracket, p.z},
			committed,
		)
		combat_3d_append_line(
			{p.x - bracket, p.y - bracket, p.z},
			{p.x - bracket, p.y - bracket * .25, p.z},
			committed,
		)
		combat_3d_append_line(
			{p.x + bracket, p.y + bracket, p.z},
			{p.x + bracket * .25, p.y + bracket, p.z},
			committed,
		)
		combat_3d_append_line(
			{p.x + bracket, p.y + bracket, p.z},
			{p.x + bracket, p.y + bracket * .25, p.z},
			committed,
		)
	}
}
