package main

import game "../packages/game"
import "core:c"
import "core:fmt"
import "core:math"
import "core:testing"
import stbi "vendor:stb/image"
import rl "zelda_engine:canvas2d"

SHIP_SINGLE_HULL_SECTION_COUNT :: 7

ship_single_hull_apply_habitat_districts :: proc(
	beam_profile, height_profile: ^[SHIP_SINGLE_HULL_SECTION_COUNT]f32,
	ring_count: int,
) {
	// Rotation districts remain inside the pressure boundary, but their bearing
	// drums and inhabited decks push visibly against it. Alternating shoulders
	// and service waists keep a sealed ark from reading as a generic cigar.
	if ring_count >= 3 {
		shoulders := [3]int{1, 3, 5}
		for station in shoulders {
			beam_profile[station] *= 1.30
			height_profile[station] *= 1.18
		}
		waists := [2]int{2, 4}
		for station in waists {
			beam_profile[station] *= .65
			height_profile[station] *= .80
		}
	} else {
		shoulders := [2]int{2, 4}
		for station in shoulders {
			beam_profile[station] *= 1.34
			height_profile[station] *= 1.20
		}
		beam_profile[3] *= .62
		height_profile[3] *= .78
	}
}

ship_single_hull_half_extents :: proc(
	r: ^game.Procedural_Ship_Recipe,
) -> (
	half_length, half_beam, half_height: f32,
) {
	half_length = r.frame.keel_length * .5
	half_beam = r.frame.beam * .5
	half_height = r.frame.height * .58
	if r.family == .Strike {
		// Interceptors wrap the same axial machinery in a longer, narrower
		// pressure shell. The extended prow and reduced frontal area distinguish
		// them from capital-ship capsules without changing their internal graph.
		half_length *= 1.18
		half_beam *= .80
		half_height *= .82
	}
	return
}

ship_append_module_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	switch ship_module_geometry(module.module) {
	case .Open_Truss:
		return
	case .Armor_Shield:
		ship_append_armor_faces(faces, module, camera, center, scale)
	case .Habitat_Ring:
		ship_append_ring_faces(faces, module, camera, center, scale)
	case .Pressure_Cylinder:
		ship_append_radial_faces(faces, module, camera, center, scale)
	case .Tank_Barrel:
		ship_append_tank_faces(faces, module, camera, center, scale)
	case .Drive_Nozzle:
		ship_append_drive_faces(faces, module, family, camera, center, scale)
	case .Dock_Frame:
		ship_append_dock_faces(faces, module, camera, center, scale)
	case .Radiator_Array:
		ship_append_radiator_faces(faces, module, camera, center, scale)
	case .Mission_Block:
		ship_append_mission_faces(faces, module, camera, center, scale)
	case .Antenna_Array:
		ship_append_antenna_faces(faces, module, camera, center, scale)
	case .Bow_Wedge:
		ship_append_bow_faces(faces, module, family, camera, center, scale)
	case .Angular:
		if module.module ==
		   .Keel {ship_append_keel_faces(faces, module, family, camera, center, scale)} else {ship_append_box_faces(faces, module, camera, center, scale)}
	}
	ship_append_service_mark_faces(faces, module, camera, center, scale)
}

ship_module_exposed_by_architecture :: proc(
	architecture: game.Ship_Generator_Kind,
	module: game.Procedural_Ship_Module,
) -> bool {
	if architecture == .Modular_Frame do return true
	// A monocoque's pressure vessels, payload rooms, armor, bow, docks, and
	// supporting frame are represented by the closed loft and its authored
	// surface installations. Reusing their modular-frame socket geometry leaves
	// disconnected equipment islands beside the hull. Only hardware which must
	// exchange heat, thrust, or signals with space remains externally legible.
	switch module {
	case .Drive, .Radiator, .Antenna:
		return true
	case .Keel, .Bow, .Armor, .Pressure_Hull, .Truss, .Tank, .Mission, .Dock, .Ring_Segment:
		return false
	}
	return false
}

ship_single_hull_internal_wart_compatible :: proc(module: game.Procedural_Ship_Module) -> bool {
	switch module {
	case .Armor, .Pressure_Hull, .Tank, .Mission, .Ring_Segment:
		return true
	case .Keel, .Bow, .Drive, .Truss, .Radiator, .Dock, .Antenna:
		return false
	}
	return false
}

ship_append_single_hull_internal_warts :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	hull: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail: bool,
) {
	// Internal machinery still changes a monocoque's exterior: access crowns,
	// fairings, reinforcement plates, and pressure blisters reveal what occupies
	// the bays below. Keep the relief shallow and rooted in the closed loft so an
	// internal inventory never reads as a detached modular-frame payload.
	budget := detail ? 6 : 3
	for internal in r.modules[:r.module_count] {
		if budget <= 0 do break
		if !ship_single_hull_internal_wart_compatible(internal.module) do continue
		wart := hull
		wart.surface_id = 0xf1000000 + internal.surface_id * 16
		x := clamp(internal.position[0], -hull.scale[0] * .68, hull.scale[0] * .66)
		selector := (internal.surface_id ~ u32(r.seed)) % 3
		side: f32 = (internal.surface_id ~ u32(r.seed >> 32)) & 1 == 0 ? -1 : 1
		local_position: [3]f32
		local_scale: [3]f32
		switch internal.module {
		case .Pressure_Hull:
			wart.material = .Hull_Plate
			local_scale = {hull.scale[0] * .075, hull.scale[1] * .14, hull.scale[2] * .075}
		case .Tank:
			wart.material = .Machinery
			local_scale = {hull.scale[0] * .11, hull.scale[1] * .09, hull.scale[2] * .055}
		case .Mission:
			wart.material = .Machinery
			local_scale = {hull.scale[0] * .085, hull.scale[1] * .11, hull.scale[2] * .085}
		case .Armor:
			wart.material = .Armor
			local_scale = {hull.scale[0] * .12, hull.scale[1] * .13, hull.scale[2] * .035}
		case .Ring_Segment:
			wart.material = .Hull_Plate
			local_scale = {hull.scale[0] * .055, hull.scale[1] * .17, hull.scale[2] * .06}
		case .Keel, .Bow, .Drive, .Truss, .Radiator, .Dock, .Antenna:
			continue
		}
		if selector == 0 {
			// Dorsal access crown.
			local_position = {x, side * hull.scale[1] * .28, hull.scale[2] * 1.015}
		} else {
			// Shoulder fairing. Its inner half intersects the loft deliberately.
			local_position = {
				x,
				side * hull.scale[1] * .91,
				hull.scale[2] * (selector == 1 ? .34 : -.16),
			}
			local_scale[1] *= .62
			local_scale[2] *= 1.18
		}
		ship_append_local_box_faces(
			faces,
			wart,
			local_position,
			local_scale,
			u32(0),
			camera,
			center,
			scale,
		)
		budget -= 1
	}
}

ship_append_single_hull_history_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	hull: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail: bool,
) {
	// Internal rooms disappear inside a monocoque, but their repairs remain part
	// of the ship's biography. Map a bounded number onto the dorsal armor belt,
	// where they intersect an existing load-bearing surface and remain legible in
	// top, side, and three-quarter recognition views.
	budget := detail ? 2 : 1
	mark_index := 0
	for source in r.modules[:r.module_count] {
		if budget <= 0 do break
		if source.service_mark == .None do continue
		shape := game.ship_construction_visual_mix(
			r.seed ~ u64(source.surface_id) ~ 0x73b1e6d9a425cf08,
		)
		x := -hull.scale[0] * (.34 - f32(shape % 1000) / 1000 * .25)
		side: f32 = (shape >> 16) & 1 == 0 ? -1 : 1
		y := side * hull.scale[1] * (.08 + f32((shape >> 24) % 4) * .035)
		mark_scale := [3]f32{hull.scale[0] * .085, hull.scale[1] * .10, hull.scale[2] * .075}
		parity: u32 = side > 0 ? 0 : 1
		mark := hull
		mark.surface_id = 0xf1000800 + u32(mark_index) * 0x100 + parity
		mark.material = .Hull_Plate
		mark.service_mark = source.service_mark
		mark.position = {x, y, hull.scale[2] * 1.13 - mark_scale[2] * 1.035}
		mark.direction = {1, 0, 0}
		mark.scale = mark_scale
		ship_append_service_mark_faces(faces, mark, camera, center, scale)
		mark_index += 1
		budget -= 1
	}
}

ship_append_single_hull_strike_weapon_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	hull: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	if r.family != .Strike do return
	weapon_scale := r.weapon_capability_scale
	if weapon_scale <= 0 do weapon_scale = 1
	service_side: f32 = (r.seed >> 3) & 1 == 0 ? -1 : 1
	stagger_phase: f32 = f32((r.seed >> 7) % 3) - 1
	// Strike hulls carry their weapon load along the reinforced forward dorsal
	// ridge. The shallow root fairing deliberately intersects the pressure shell
	// so the package reads as installed machinery rather than a floating prop.
	root := hull
	root.material = .Armor
	root.surface_id = 0xe6000000
	ship_append_local_box_faces(
		faces,
		root,
		{hull.scale[0] * .45, 0, hull.scale[2] * .84},
		{hull.scale[0] * .29, hull.scale[1] * .18, hull.scale[2] * .18},
		0,
		camera,
		center,
		scale,
	)
	// One seed-owned inspection housing records which side of the dorsal root
	// received the ship's original service run. It is bounded and functional,
	// preserving the interceptor silhouette while keeping sister ships distinct.
	root.material = .Machinery
	ship_append_local_box_faces(
		faces,
		root,
		{
			hull.scale[0] * (.34 + stagger_phase * .018),
			service_side * hull.scale[1] * .22,
			hull.scale[2] * .91,
		},
		{hull.scale[0] * .055, hull.scale[1] * .055, hull.scale[2] * .06},
		0x20,
		camera,
		center,
		scale,
	)
	if r.weapon_package == .Guided_Missiles {
		for side_index in 0 ..< 2 do for row in 0 ..< 2 {
			side: f32 = side_index == 0 ? -1 : 1
			store := hull
			store.position = ship_module_local_point(
				hull,
				{
					hull.scale[0] *
					(.39 + f32(row) * .28 + side * service_side * .025 + stagger_phase * .012),
					side * hull.scale[1] * .32,
					hull.scale[2] * 1.10,
				},
			)
			store.scale = {
				hull.scale[0] * .13 * weapon_scale,
				hull.scale[1] * .045 * weapon_scale,
				hull.scale[2] * .065 * weapon_scale,
			}
			store.material = .Machinery
			store.surface_id = 0xe6000100 + u32(side_index * 0x100 + row * 0x40)
			ship_append_local_box_faces(
				faces,
				store,
				{-store.scale[0] * .16, 0, -store.scale[2] * 1.25},
				{store.scale[0] * .82, store.scale[1] * .7, store.scale[2] * .16},
				0x08,
				camera,
				center,
				scale,
			)
			ship_append_tank_faces(faces, store, camera, center, scale)
			store.material = .Drive
			ship_append_weapon_engine_faces(
				faces,
				store,
				store.scale[0] * .22,
				1.08,
				camera,
				center,
				scale,
			)
			store.material = .Armor
			ship_append_weapon_nose_faces(faces, store, store.scale[0] * .42, .82, camera, center, scale)
			store.material = .Machinery
			for fin_index in 0 ..< 2 {
				fin_side: f32 = fin_index == 0 ? -1 : 1
				ship_append_local_box_faces(
					faces,
					store,
					{-store.scale[0] * .7, fin_side * store.scale[1] * 1.2, 0},
					{store.scale[0] * .17, store.scale[1] * .68, store.scale[2] * .13},
					u32(0x30 + fin_index * 8),
					camera,
					center,
					scale,
				)
			}
		}
		return
	}
	if r.weapon_package == .Heavy_Torpedoes {
		for side_index in 0 ..< 2 {
			side: f32 = side_index == 0 ? -1 : 1
			store := hull
			store.position = ship_module_local_point(
				hull,
				{
					hull.scale[0] * (.54 + side * service_side * .035 + stagger_phase * .012),
					side * hull.scale[1] * .28,
					hull.scale[2] * 1.10,
				},
			)
			store.scale = {
				hull.scale[0] * .31 * weapon_scale,
				hull.scale[1] * .075 * weapon_scale,
				hull.scale[2] * .095 * weapon_scale,
			}
			store.material = .Machinery
			store.surface_id = 0xe6000500 + u32(side_index * 0x80)
			for rail_index in 0 ..< 2 {
				rail_side: f32 = rail_index == 0 ? -1 : 1
				ship_append_local_box_faces(
					faces,
					store,
					{-store.scale[0] * .12, rail_side * store.scale[1] * .72, -store.scale[2] * 1.22},
					{store.scale[0] * .9, store.scale[1] * .13, store.scale[2] * .18},
					u32(0x08 + rail_index * 8),
					camera,
					center,
					scale,
				)
			}
			ship_append_tank_faces(faces, store, camera, center, scale)
			store.material = .Drive
			ship_append_weapon_engine_faces(
				faces,
				store,
				store.scale[0] * .14,
				.86,
				camera,
				center,
				scale,
			)
			store.material = .Armor
			ship_append_weapon_nose_faces(faces, store, store.scale[0] * .18, .96, camera, center, scale)
			store.material = .Machinery
			for band_index in 0 ..< 2 {
				band_x := band_index == 0 ? f32(-.72) : f32(.38)
				ship_append_local_box_faces(
					faces,
					store,
					{store.scale[0] * band_x, 0, 0},
					{store.scale[0] * .055, store.scale[1] * 1.16, store.scale[2] * 1.16},
					u32(0x38 + band_index * 0x10),
					camera,
					center,
					scale,
				)
			}
		}
		return
	}
	gun := hull
	gun.position = ship_module_local_point(
		hull,
		{
			hull.scale[0] * (.67 + stagger_phase * .012),
			service_side * hull.scale[1] * .025,
			hull.scale[2] * .98,
		},
	)
	gun.scale = {
		hull.scale[0] * (r.weapon_package == .Defensive_Laser ? f32(.13) : f32(.23)),
		hull.scale[1] * .027,
		hull.scale[2] * .04,
	}
	gun.material = .Machinery
	gun.surface_id = 0xe6000900
	barrel_count := r.weapon_package == .Chemical_Autocannon ? 2 : 1
	for barrel_index in 0 ..< barrel_count {
		barrel_side: f32 = barrel_count == 1 ? 0 : (barrel_index == 0 ? -1 : 1)
		ship_append_local_box_faces(
			faces,
			gun,
			{0, barrel_side * hull.scale[1] * .055, 0},
			gun.scale,
			u32(0x08 + barrel_index * 8),
			camera,
			center,
			scale,
		)
	}
	collar_count := 0
	switch r.weapon_package {
	case .Chemical_Autocannon, .Defensive_Laser:
		collar_count = 1
	case .Coilgun_Battery:
		collar_count = 4
	case .Railgun_Battery:
		collar_count = 2
	case .Offensive_Laser:
		collar_count = 3
	case .Unspecified, .Guided_Missiles, .Heavy_Torpedoes:
	}
	for collar_index in 0 ..< collar_count {
		t := f32(collar_index + 1) / f32(collar_count + 1)
		ship_append_local_box_faces(
			faces,
			gun,
			{-gun.scale[0] + gun.scale[0] * 2 * t, 0, 0},
			{gun.scale[0] * .08, hull.scale[1] * .07, hull.scale[2] * .075},
			u32(0x40 + collar_index * 8),
			camera,
			center,
			scale,
		)
	}
	if r.weapon_package == .Railgun_Battery {
		for fork_index in 0 ..< 2 {
			fork_side: f32 = fork_index == 0 ? -1 : 1
			ship_append_local_box_faces(
				faces,
				gun,
				{gun.scale[0] * .92, fork_side * hull.scale[1] * .07, 0},
				{gun.scale[0] * .18, hull.scale[1] * .018, hull.scale[2] * .05},
				u32(0x70 + fork_index * 8),
				camera,
				center,
				scale,
			)
		}
	}
	if r.weapon_package == .Defensive_Laser || r.weapon_package == .Offensive_Laser {
		emitter := gun
		emitter.material = .Glass
		ship_append_weapon_nose_faces(
			faces,
			emitter,
			gun.scale[0] * (r.weapon_package == .Offensive_Laser ? f32(.34) : f32(.22)),
			1.5,
			camera,
			center,
			scale,
		)
	}
	if r.weapon_package == .Chemical_Autocannon {
		ship_append_local_box_faces(
			faces,
			root,
			{hull.scale[0] * .36, service_side * hull.scale[1] * .28, hull.scale[2] * .86},
			{hull.scale[0] * .075, hull.scale[1] * .08, hull.scale[2] * .09},
			0xc0,
			camera,
			center,
			scale,
		)
	}
}

ship_append_single_hull_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail := true,
) {
	// Single hulls use a deliberately authored-looking armored loft rather than
	// one constant-width extrusion. The changing sections establish a readable
	// prow, shoulder, waist, and engine stern while remaining deterministic.
	half_length, half_beam, half_height := ship_single_hull_half_extents(r)
	hull := game.Procedural_Ship_Placement {
		id         = 0,
		surface_id = 0xf0000000,
		module     = .Keel,
		material   = .Hull_Plate,
		position   = {0, 0, 0},
		direction  = {1, 0, 0},
		scale      = {half_length, half_beam, half_height},
	}
	has_dock := false
	armor_count, pressure_count, tank_count, mission_count := 0, 0, 0, 0
	for module in r.modules[:r.module_count] {
		has_dock = has_dock || module.module == .Dock
		switch module.module {
		case .Armor:
			armor_count += 1
		case .Pressure_Hull, .Ring_Segment:
			pressure_count += 1
		case .Tank:
			tank_count += 1
		case .Mission:
			mission_count += 1
		case .Keel, .Bow, .Drive, .Truss, .Radiator, .Dock, .Antenna:
		}
	}
	hangar_side: f32 = r.seed & 2 == 0 ? -1 : 1
	section_count :: SHIP_SINGLE_HULL_SECTION_COUNT
	section_points :: 8
	x_profile := [section_count]f32{-1, -.82, -.40, .05, .48, .82, 1}
	beam_profile := [section_count]f32{.54, .88, 1, .94, .82, .55, .10}
	height_profile := [section_count]f32{.62, .88, 1, .96, .82, .60, .16}
	z_profile := [section_count]f32{-.05, -.02, .04, .08, .10, .08, .04}
	// Seed-owned naval silhouettes change the major masses, not just surface
	// decoration. Six section grammars keep sister ships recognizable while
	// avoiding a fleet of near-identical seven-section loaves.
	profile_variant := int((r.seed ~ r.fingerprint ~ u64(r.family) * 0x9e3779b97f4a7c15) % 6)
	switch profile_variant {
	case 0:
		beam_profile = {.42, .74, .92, 1, .96, .66, .08}
		height_profile = {.54, .72, .88, 1, .94, .66, .14}
	case 1:
		beam_profile = {.60, .92, 1, .98, .84, .58, .12}
		height_profile = {.70, .94, 1, .98, .84, .62, .18}
	case 2:
		beam_profile = {.38, .68, .82, .86, .76, .48, .07}
		height_profile = {.50, .78, .94, 1, .86, .56, .12}
	case 3:
		// Broad armored shoulders over a visibly pinched machinery waist.
		beam_profile = {
			.48,
			.96,
			1,
			.70,
			.88,
			.52,
			.09,
		}; height_profile = {.62, .92, 1, .76, .90, .60, .15}; z_profile = {-.08, -.03, .08, .03, .12, .07, .02}
	case 4:
		// A deep stern citadel hands off to a long, narrow forward body.
		beam_profile = {
			.72,
			1,
			.94,
			.78,
			.64,
			.42,
			.06,
		}; height_profile = {.82, 1, .94, .82, .72, .48, .10}; z_profile = {-.10, -.02, .05, .10, .13, .11, .05}
	case 5:
		// Forward-heavy wedge with a compact drive neck.
		beam_profile = {
			.34,
			.62,
			.76,
			.90,
			1,
			.78,
			.11,
		}; height_profile = {.48, .68, .80, .92, 1, .72, .16}; z_profile = {-.04, 0, .04, .08, .14, .12, .06}
	}
	if r.family == .Habitat {
		ship_single_hull_apply_habitat_districts(
			&beam_profile,
			&height_profile,
			r.frame.ring_station_count,
		)
	}
	// The pressure boundary records what it encloses. These restrained biases
	// make refits readable in silhouette without exposing literal internal boxes.
	pressure_bias := clamp(f32(pressure_count - 2) * .035, f32(-.05), f32(.14))
	tank_bias := clamp(f32(tank_count) * .025, f32(0), f32(.12))
	mission_bias := clamp(f32(mission_count) * .018, f32(0), f32(.09))
	armor_bias := clamp(f32(armor_count - 3) * .018, f32(-.04), f32(.10))
	for station in 0 ..< section_count {
		midship := 1 - math.abs(f32(station - 3)) / 3
		beam_profile[station] *=
			1 +
			pressure_bias * midship +
			armor_bias * (station == 1 || station == 2 ? f32(1) : f32(.25))
		height_profile[station] *=
			1 +
			pressure_bias * midship +
			tank_bias * (station <= 3 ? f32(1) : f32(.25)) +
			mission_bias * (station >= 2 && station <= 4 ? f32(1) : f32(0))
		if has_dock && station >= 2 && station <= 4 {
			beam_profile[station] *= 1.08
			height_profile[station] *= .91
			z_profile[station] -= .035
		}
	}
	rings: [section_count][section_points][3]f32
	for station in 0 ..< section_count {
		sy := hull.scale[1] * beam_profile[station]; sz := hull.scale[2] * height_profile[station]
		section := [section_points][2]f32 {
			{-sy, -sz * .46},
			{-sy * .62, -sz},
			{sy * .62, -sz},
			{sy, -sz * .46},
			{sy, sz * .42},
			{sy * .48, sz},
			{-sy * .48, sz},
			{-sy, sz * .42},
		}
		for point in 0 ..< section_points do rings[station][point] = ship_module_local_point(hull, {hull.scale[0] * x_profile[station], section[point][0], section[point][1] + hull.scale[2] * z_profile[station]})
	}
	for station in 0 ..< section_count - 1 {
		for segment in 0 ..< section_points {
			next := (segment + 1) % section_points
			ny := (rings[station][segment][1] + rings[station][next][1]) * 0.5 / hull.scale[1]
			nz := (rings[station][segment][2] + rings[station][next][2]) * 0.5 / hull.scale[2]
			length := f32(
				math.sqrt(f64(ny * ny + nz * nz)),
			); if length > .001 {ny /= length; nz /= length}
			ship_append_face(
				faces,
				{
					rings[station][segment],
					rings[station + 1][segment],
					rings[station + 1][next],
					rings[station][next],
				},
				ship_module_local_normal(hull, {0, ny, nz}),
				hull,
				hull.surface_id + u32(station * section_points + segment),
				camera,
				center,
				scale,
			)
		}
	}
	for segment in 0 ..< section_points {
		next := (segment + 1) % section_points
		rear := ship_module_local_point(hull, {-hull.scale[0], 0, -hull.scale[2] * .05})
		front := ship_module_local_point(hull, {hull.scale[0], 0, hull.scale[2] * .04})
		ship_append_face(
			faces,
			{rear, rings[0][next], rings[0][segment], rear},
			ship_module_local_normal(hull, {-1, 0, 0}),
			hull,
			hull.surface_id + 0x100 + u32(segment),
			camera,
			center,
			scale,
		)
		ship_append_face(
			faces,
			{front, rings[section_count - 1][segment], rings[section_count - 1][next], front},
			ship_module_local_normal(hull, {1, 0, 0}),
			hull,
			hull.surface_id + 0x120 + u32(segment),
			camera,
			center,
			scale,
		)
	}

	// Layered armor and the command spine break the broad loft into functional
	// manufactured regions. A seed-owned side patch gives sister ships distinct
	// service character without sacrificing the family silhouette.
	armor := hull; armor.material = .Armor
	island_y := has_dock ? -hangar_side * hull.scale[1] * .20 : f32(0)
	ship_append_local_box_faces(
		faces,
		armor,
		{-hull.scale[0] * .18, island_y, hull.scale[2] * 1.02},
		{hull.scale[0] * .23, hull.scale[1] * .38, hull.scale[2] * .10},
		0x180,
		camera,
		center,
		scale,
	)
	ship_append_local_box_faces(
		faces,
		armor,
		{hull.scale[0] * .18, island_y, hull.scale[2] * .94},
		{hull.scale[0] * .16, hull.scale[1] * .25, hull.scale[2] * .11},
		0x1c0,
		camera,
		center,
		scale,
	)
	ship_append_local_box_faces(
		faces,
		armor,
		{hull.scale[0] * .48, island_y, hull.scale[2] * .68},
		{hull.scale[0] * .13, hull.scale[1] * .16, hull.scale[2] * .13},
		0x200,
		camera,
		center,
		scale,
	)
	// Narrow bridge lights are inset against both faces of the command block.
	// Repetition establishes inhabited scale without turning the deck into a
	// luminous stripe or relying on color.
	if detail {
		bridge_glass := hull; bridge_glass.material = .Glass
		for side_index in 0 ..< 2 {
			side: f32 = side_index == 0 ? -1 : 1
			for window in 0 ..< 4 {
				x := hull.scale[0] * (-.30 + f32(window) * .085)
				ship_append_local_box_faces(
					faces,
					bridge_glass,
					{x, island_y + side * hull.scale[1] * .385, hull.scale[2] * 1.105},
					{hull.scale[0] * .026, hull.scale[1] * .012, hull.scale[2] * .026},
					u32(0x220 + side_index * 0x40 + window * 8),
					camera,
					center,
					scale,
				)
			}
		}
	}
	// A carrier recipe earns a broad side aperture and armored lintel instead of
	// receiving a generic decorative bay. The seed selects the traffic side.
	if has_dock {
		hangar := hull; normal := ship_module_local_normal(hangar, {0, hangar_side, 0})
		outer_local := [4][3]f32 {
			{-hull.scale[0] * .18, hangar_side * hull.scale[1] * 1.028, -hull.scale[2] * .36},
			{hull.scale[0] * .41, hangar_side * hull.scale[1] * 1.028, -hull.scale[2] * .26},
			{hull.scale[0] * .34, hangar_side * hull.scale[1] * 1.028, hull.scale[2] * .15},
			{-hull.scale[0] * .12, hangar_side * hull.scale[1] * 1.028, hull.scale[2] * .10},
		}
		inner_local := [4][3]f32 {
			{-hull.scale[0] * .11, hangar_side * hull.scale[1] * 1.042, -hull.scale[2] * .27},
			{hull.scale[0] * .32, hangar_side * hull.scale[1] * 1.042, -hull.scale[2] * .20},
			{hull.scale[0] * .27, hangar_side * hull.scale[1] * 1.042, hull.scale[2] * .065},
			{-hull.scale[0] * .065, hangar_side * hull.scale[1] * 1.042, hull.scale[2] * .028},
		}
		outer, inner: [4][3]f32
		for corner in 0 ..< 4 {outer[corner] = ship_module_local_point(hangar, outer_local[corner]); inner[corner] = ship_module_local_point(hangar, inner_local[corner])}
		hangar.material = .Glass
		ship_append_face(
			faces,
			{inner[0], inner[1], inner[2], inner[3]},
			normal,
			hangar,
			hangar.surface_id + 0x260,
			camera,
			center,
			scale,
		)
		hangar.material = .Armor
		for edge in 0 ..< 4 {
			next := (edge + 1) % 4
			ship_append_face(
				faces,
				{outer[edge], outer[next], inner[next], inner[edge]},
				normal,
				hangar,
				hangar.surface_id + 0x268 + u32(edge),
				camera,
				center,
				scale,
			)
		}
		// The landing/service apron occupies the hangar side while the command
		// island shifts opposite it, creating a carrier-specific top silhouette.
		apron := hull; apron.material = .Armor
		ship_append_local_box_faces(
			faces,
			apron,
			{hull.scale[0] * .08, hangar_side * hull.scale[1] * .54, hull.scale[2] * .82},
			{hull.scale[0] * .31, hull.scale[1] * .24, hull.scale[2] * .025},
			0x278,
			camera,
			center,
			scale,
		)
		apron.material = .Machinery
		ship_append_local_box_faces(
			faces,
			apron,
			{hull.scale[0] * .08, hangar_side * hull.scale[1] * .54, hull.scale[2] * .851},
			{hull.scale[0] * .22, hull.scale[1] * .028, hull.scale[2] * .008},
			0x280,
			camera,
			center,
			scale,
		)
	}
	// One localized maintenance field provides believable panel scale without
	// wallpapering the complete hull. Its side and stagger belong to the seed.
	if detail {
		panel_side: f32 = r.seed & 4 == 0 ? -1 : 1
		panel := hull; panel.material = .Armor
		for row in 0 ..< 2 do for column in 0 ..< 3 {
			x := hull.scale[0] * (-.26 + f32(column) * .15 + f32(row) * .025)
			y := panel_side * hull.scale[1] * (.18 + f32(row) * .19)
			ship_append_local_box_faces(faces, panel, {x, y, hull.scale[2] * (.985 + f32(row) * .025)}, {hull.scale[0] * (.052 + f32((column + row) & 1) * .012), hull.scale[1] * .072, hull.scale[2] * .012}, u32(0x2e0 + row * 0x30 + column * 8), camera, center, scale)
		}
	}
	patch_side: f32 = r.seed & 1 == 0 ? -1 : 1
	ship_append_local_box_faces(
		faces,
		armor,
		{-hull.scale[0] * .05, patch_side * hull.scale[1] * .99, hull.scale[2] * .08},
		{hull.scale[0] * .17, hull.scale[1] * .035, hull.scale[2] * .28},
		0x240,
		camera,
		center,
		scale,
	)
	// Long machinery trenches and their armor ribs turn broad side plates into
	// functional ship-scale surfaces instead of uninterrupted patterned slabs.
	trench := hull; trench.material = .Machinery
	for side_index in 0 ..< 2 {
		side: f32 = side_index == 0 ? -1 : 1
		ship_append_local_box_faces(
			faces,
			trench,
			{-hull.scale[0] * .02, side * hull.scale[1] * .975, -hull.scale[2] * .16},
			{hull.scale[0] * .58, hull.scale[1] * .024, hull.scale[2] * .105},
			u32(0x280 + side_index * 0x40),
			camera,
			center,
			scale,
		)
		trench.material = .Armor
		if detail do for rib in 0 ..< 4 {
			x := hull.scale[0] * (-.48 + f32(rib) * .31)
			ship_append_local_box_faces(faces, trench, {x, side * hull.scale[1] * 1.01, -hull.scale[2] * .16}, {hull.scale[0] * .018, hull.scale[1] * .027, hull.scale[2] * .14}, u32(0x2a0 + side_index * 0x40 + rib * 8), camera, center, scale)
		}
		trench.material = .Machinery
	}
	if r.family == .Fleet {
		weapon_scale := r.weapon_capability_scale; if weapon_scale <= 0 do weapon_scale = 1
		// The drive modules plug into an armored aft citadel instead of emerging
		// naked from the hull cap. Twin shoulders protect a recessed service deck;
		// seed-owned auxiliary housings keep the bank from becoming perfectly even.
		engine := hull; engine.material = .Machinery
		ship_append_local_box_faces(
			faces,
			engine,
			{-hull.scale[0] * .91, 0, -hull.scale[2] * .08},
			{hull.scale[0] * .13, hull.scale[1] * .36, hull.scale[2] * .25},
			0x380,
			camera,
			center,
			scale,
		)
		for side_index in 0 ..< 2 {
			side: f32 = side_index == 0 ? -1 : 1
			engine.material = .Armor
			ship_append_local_box_faces(
				faces,
				engine,
				{-hull.scale[0] * .90, side * hull.scale[1] * .56, hull.scale[2] * .015},
				{hull.scale[0] * .15, hull.scale[1] * .19, hull.scale[2] * .31},
				u32(0x3c0 + side_index * 0x40),
				camera,
				center,
				scale,
			)
			engine.material = .Drive
			aux_scale: f32 = side == ((r.seed >> 5) & 1 == 0 ? f32(-1) : 1) ? 1.18 : .84
			ship_append_local_box_faces(
				faces,
				engine,
				{-hull.scale[0] * 1.035, side * hull.scale[1] * .55, -hull.scale[2] * .035},
				{
					hull.scale[0] * .105 * aux_scale,
					hull.scale[1] * .082 * aux_scale,
					hull.scale[2] * .105 * aux_scale,
				},
				u32(0x3d0 + side_index * 0x40),
				camera,
				center,
				scale,
			)
		}
		// Broad monocoque shoulders support distributed batteries away from the
		// axial spine. The stagger prevents the silhouette becoming a toy-like
		// row of identical turrets while retaining manufactured repetition.
		battery := hull; battery.material = .Machinery
		for side_index in 0 ..< 2 {
			side: f32 = side_index == 0 ? -1 : 1
			for battery_index in 0 ..< 2 {
				heavy := battery_index == int((r.seed >> 1) & 1)
				caliber := (heavy ? f32(1.28) : f32(.76)) * weapon_scale
				x := hull.scale[0] * (-.36 + f32(battery_index) * .62 + side * .05)
				y := side * hull.scale[1] * (battery_index == 0 ? .72 : .63)
				z := hull.scale[2] * (battery_index == 0 ? .63 : .72)
				base_id := u32(0x300 + side_index * 0x80 + battery_index * 0x30)
				if r.weapon_package == .Guided_Missiles {
					// A missile is not merely laid on the shoulder: give each launcher a
					// recessed armored cassette and two exposed guide rails. At board
					// distance this reads as a reloadable launch module rather than a
					// collection of loose auxiliary tanks.
					battery.material = .Armor
					ship_append_local_box_faces(
						faces,
						battery,
						{x, y, z - hull.scale[2] * .045 * caliber},
						{
							hull.scale[0] * .19 * caliber,
							hull.scale[1] * .105 * caliber,
							hull.scale[2] * .045 * caliber,
						},
						base_id,
						camera,
						center,
						scale,
					)
					store := hull
					store.position = ship_module_local_point(
						hull,
						{x, side * hull.scale[1] * (battery_index == 0 ? f32(.84) : f32(.72)), z},
					)
					store.scale = {
						hull.scale[0] * .16 * caliber,
						hull.scale[1] * .05 * caliber,
						hull.scale[2] * .06 * caliber,
					}
					store.material = .Machinery
					store.surface_id = 0xe4000000 + base_id
					ship_append_tank_faces(faces, store, camera, center, scale)
					store.material = .Drive
					ship_append_weapon_engine_faces(
						faces,
						store,
						store.scale[0] * .22,
						1.08,
						camera,
						center,
						scale,
					)
					store.material = .Armor
					ship_append_weapon_nose_faces(
						faces,
						store,
						store.scale[0] * .42,
						.82,
						camera,
						center,
						scale,
					)
					for fin_index in 0 ..< 2 {
						fin_side: f32 = fin_index == 0 ? -1 : 1
						ship_append_local_box_faces(
							faces,
							store,
							{-store.scale[0] * .72, fin_side * store.scale[1] * 1.22, 0},
							{store.scale[0] * .18, store.scale[1] * .72, store.scale[2] * .12},
							u32(0x30 + fin_index * 8),
							camera,
							center,
							scale,
						)
					}
					// The rails deliberately project beyond the cassette lip, making the
					// forward launch direction legible in the top-view integration board.
					battery.material = .Machinery
					for rail_index in 0 ..< 2 {
						rail_side: f32 = rail_index == 0 ? -1 : 1
						ship_append_local_box_faces(
							faces,
							battery,
							{x + hull.scale[0] * .025, y + rail_side * hull.scale[1] * .088 * caliber, z + hull.scale[2] * .025 * caliber},
							{hull.scale[0] * .205 * caliber, hull.scale[1] * .012 * caliber, hull.scale[2] * .016 * caliber},
							base_id + 0x60 + u32(rail_index * 8),
							camera,
							center,
							scale,
						)
					}
					continue
				}
				if r.weapon_package == .Heavy_Torpedoes {
					if battery_index > 0 do continue
					// Torpedoes sit in a deep saddle with wide restraint bands; their
					// support is visibly heavier than a missile cassette.
					battery.material = .Armor
					ship_append_local_box_faces(
						faces,
						battery,
						{hull.scale[0] * .02, side * hull.scale[1] * .82, hull.scale[2] * .62},
						{hull.scale[0] * .35 * weapon_scale, hull.scale[1] * .13 * weapon_scale, hull.scale[2] * .06 * weapon_scale},
						base_id,
						camera,
						center,
						scale,
					)
					store := hull
					store.position = ship_module_local_point(
						hull,
						{hull.scale[0] * .02, side * hull.scale[1] * .82, hull.scale[2] * .7},
					)
					store.scale = {
						hull.scale[0] * .3 * weapon_scale,
						hull.scale[1] * .085 * weapon_scale,
						hull.scale[2] * .095 * weapon_scale,
					}
					store.material = .Machinery
					store.surface_id = 0xe4001000 + u32(side_index * 0x80)
					ship_append_tank_faces(faces, store, camera, center, scale)
					store.material = .Drive
					ship_append_weapon_engine_faces(
						faces,
						store,
						store.scale[0] * .14,
						.86,
						camera,
						center,
						scale,
					)
					store.material = .Armor
					ship_append_weapon_nose_faces(
						faces,
						store,
						store.scale[0] * .18,
						.96,
						camera,
						center,
						scale,
					)
					store.material = .Machinery
					ship_append_local_box_faces(
						faces,
						store,
						{-store.scale[0] * .88, 0, 0},
						{store.scale[0] * .08, store.scale[1] * 1.2, store.scale[2] * 1.2},
						0x38,
						camera,
						center,
						scale,
					)
					for band_index in 0 ..< 2 {
						band_x := (band_index == 0 ? f32(-.34) : .34) * store.scale[0]
						ship_append_local_box_faces(
							faces,
							store,
							{band_x, 0, 0},
							{store.scale[0] * .045, store.scale[1] * 1.22, store.scale[2] * 1.22},
							0x48 + u32(band_index * 8),
							camera,
							center,
							scale,
						)
					}
					continue
				}
				ship_append_local_box_faces(
					faces,
					battery,
					{x, y, z},
					{
						hull.scale[0] * .075 * caliber,
						hull.scale[1] * .14 * caliber,
						hull.scale[2] * .075 * caliber,
					},
					base_id,
					camera,
					center,
					scale,
				)
				battery.material = .Armor
				ship_append_local_box_faces(
					faces,
					battery,
					{x + hull.scale[0] * .035, y, z + hull.scale[2] * .09 * caliber},
					{
						hull.scale[0] * .07 * caliber,
						hull.scale[1] * .105 * caliber,
						hull.scale[2] * .055 * caliber,
					},
					base_id + 8,
					camera,
					center,
					scale,
				)
				battery.material = .Machinery
				barrel_half_x := hull.scale[0] * (heavy ? f32(.17) : f32(.10))
				if r.weapon_package == .Chemical_Autocannon do barrel_half_x *= .72
				if r.weapon_package == .Defensive_Laser do barrel_half_x *= .58
				barrel_center := [3]f32 {
					x + hull.scale[0] * (heavy ? .20 : .14),
					y - side * hull.scale[1] * .045,
					z + hull.scale[2] * .105 * caliber,
				}
				barrel_count := r.weapon_package == .Chemical_Autocannon ? 2 : 1
				for barrel_index in 0 ..< barrel_count {
					barrel_side: f32 =
						barrel_count == 1 ? 0 : (barrel_index == 0 ? f32(-1) : f32(1))
					ship_append_local_box_faces(
						faces,
						battery,
						{
							barrel_center[0],
							barrel_center[1] + barrel_side * hull.scale[1] * .026,
							barrel_center[2],
						},
						{
							barrel_half_x,
							hull.scale[1] * .018 * caliber,
							hull.scale[2] * .018 * caliber,
						},
						base_id + 16 + u32(barrel_index * 8),
						camera,
						center,
						scale,
					)
				}
				collar_count := 0
				switch r.weapon_package {
				case .Chemical_Autocannon, .Defensive_Laser:
					collar_count = 1
				case .Coilgun_Battery:
					collar_count = 4
				case .Railgun_Battery:
					collar_count = 2
				case .Offensive_Laser:
					collar_count = 3
				case .Unspecified:
					collar_count = 0
				case .Guided_Missiles, .Heavy_Torpedoes:
				}
				for collar_index in 0 ..< collar_count {
					t := f32(collar_index + 1) / f32(collar_count + 1)
					collar_x := barrel_center[0] - barrel_half_x + barrel_half_x * 2 * t
					ship_append_local_box_faces(
						faces,
						battery,
						{collar_x, barrel_center[1], barrel_center[2]},
						{
							barrel_half_x * .08,
							hull.scale[1] * .036 * caliber,
							hull.scale[2] * .036 * caliber,
						},
						base_id + 0x40 + u32(collar_index * 8),
						camera,
						center,
						scale,
					)
				}
				if r.weapon_package == .Railgun_Battery {
					for fork_index in 0 ..< 2 {
						fork_side: f32 = fork_index == 0 ? -1 : 1
						ship_append_local_box_faces(
							faces,
							battery,
							{
								barrel_center[0] + barrel_half_x * .9,
								barrel_center[1] + fork_side * hull.scale[1] * .04,
								barrel_center[2],
							},
							{
								barrel_half_x * .18,
								hull.scale[1] * .012 * caliber,
								hull.scale[2] * .025 * caliber,
							},
							base_id + 0x70 + u32(fork_index * 8),
							camera,
							center,
							scale,
						)
					}
				}
				if r.weapon_package == .Defensive_Laser || r.weapon_package == .Offensive_Laser {
					emitter := hull
					emitter.position = ship_module_local_point(hull, barrel_center)
					emitter.scale = {
						barrel_half_x,
						hull.scale[1] * .018 * caliber,
						hull.scale[2] * .018 * caliber,
					}
					emitter.material = .Glass
					emitter.surface_id = 0xe4002000 + base_id
					ship_append_weapon_nose_faces(
						faces,
						emitter,
						barrel_half_x *
						(r.weapon_package == .Offensive_Laser ? f32(.34) : f32(.22)),
						1.5,
						camera,
						center,
						scale,
					)
				}
				if r.weapon_package == .Chemical_Autocannon {
					ship_append_local_box_faces(
						faces,
						battery,
						{
							x - hull.scale[0] * .025,
							y + side * hull.scale[1] * .11,
							z + hull.scale[2] * .04,
						},
						{
							hull.scale[0] * .04 * caliber,
							hull.scale[1] * .05 * caliber,
							hull.scale[2] * .06 * caliber,
						},
						base_id + 0xa0,
						camera,
						center,
						scale,
					)
				}
			}
		}
	}
	ship_append_single_hull_strike_weapon_faces(faces, r, hull, camera, center, scale)
	ship_append_single_hull_internal_warts(faces, r, hull, camera, center, scale, detail)
	ship_append_single_hull_history_faces(faces, r, hull, camera, center, scale, detail)
}
