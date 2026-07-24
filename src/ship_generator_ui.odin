package main

import game "../packages/game"
import "core:c"
import "core:fmt"
import "core:math"
import "core:testing"
import stbi "vendor:stb/image"
import rl "zelda_engine:canvas2d"

ship_module_name :: proc(module: game.Procedural_Ship_Module) -> string {
	switch module {
	case .Keel:
		return "KEEL SECTION"
	case .Bow:
		return "BOW ASSEMBLY"
	case .Drive:
		return "DRIVE BANK"
	case .Armor:
		return "ARMOR SHIELD"
	case .Pressure_Hull:
		return "PRESSURE HULL"
	case .Truss:
		return "OPEN TRUSS"
	case .Tank:
		return "PROPELLANT TANK"
	case .Radiator:
		return "RADIATOR ARRAY"
	case .Mission:
		return "MISSION MODULE"
	case .Dock:
		return "DOCKING FRAME"
	case .Antenna:
		return "SENSOR MAST"
	case .Ring_Segment:
		return "HABITAT RING"
	}
	return "SHIP MODULE"
}

ship_module_description :: proc(module: game.Procedural_Ship_Module) -> string {
	switch module {
	case .Keel:
		return "Primary load-bearing spine section."
	case .Bow:
		return "Forward collision and approach structure."
	case .Drive:
		return "Thrust machinery and exhaust assembly."
	case .Armor:
		return "External plate protecting a vulnerable mounting."
	case .Pressure_Hull:
		return "Sealed volume for crew, passengers, or stores."
	case .Truss:
		return "Open structural member carrying load between modules."
	case .Tank:
		return "Pressure vessel reserved for propellant or working fluid."
	case .Radiator:
		return "Exposed surface for rejecting waste heat."
	case .Mission:
		return "Replaceable machinery fitted for the ship's current work."
	case .Dock:
		return "Capture frame for transfer and service operations."
	case .Antenna:
		return "Instrument mast for sensing and communication."
	case .Ring_Segment:
		return "Rotating inhabited section arranged around the keel."
	}
	return "Installed ship structure."
}

ship_module_projected_bounds :: proc(
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) -> rl.Rectangle {
	origin := ship_module_render_origin(module)
	if module.module == .Ring_Segment do origin = {module.position[0], 0, 0}
	axis, side, up := ship_module_basis(module)
	sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]
	if module.module == .Drive {sx *= 3.0; sy *= 1.55; sz *= 1.55}
	if module.module == .Dock {sx *= 1.72; sy *= 1.15; sz *= 1.15}
	if module.module == .Antenna do sz *= 2.2
	if module.module == .Ring_Segment {sy = module.scale[1]; sz = module.scale[1]}
	min_x, min_y, max_x, max_y := f32(1e30), f32(1e30), f32(-1e30), f32(-1e30)
	for corner in 0 ..< 8 {
		lx: f32 =
			corner & 1 == 0 ? -sx : sx; ly: f32 = corner & 2 == 0 ? -sy : sy; lz: f32 = corner & 4 == 0 ? -sz : sz
		world := [3]f32 {
			origin[0] + axis[0] * lx + side[0] * ly + up[0] * lz,
			origin[1] + axis[1] * lx + side[1] * ly + up[1] * lz,
			origin[2] + axis[2] * lx + side[2] * ly + up[2] * lz,
		}
		p := ship_project(world, camera, center, scale).screen
		min_x = min(
			min_x,
			p.x,
		); min_y = min(min_y, p.y); max_x = max(max_x, p.x); max_y = max(max_y, p.y)
	}
	padding: f32 = module.module == .Truss ? 6 : 3
	return R(
		min_x - padding,
		min_y - padding,
		max(max_x - min_x + padding * 2, f32(10)),
		max(max_y - min_y + padding * 2, f32(10)),
	)
}

ship_hovered_module :: proc(
	r: ^game.Procedural_Ship_Recipe,
	rect: rl.Rectangle,
	camera: Ship_Generator_Camera,
	point: rl.Vector2,
) -> int {
	if ship_architecture_has_closed_hull(r.architecture) {
		return ship_closed_hull_hovered_module(r, rect, camera, point)
	}
	center, scale := ship_recipe_view_fit(r, camera, rect)
	best, best_area := -1, f32(1e30)
	for module, index in r.modules[:r.module_count] {
		bounds := ship_module_projected_bounds(module, camera, center, scale)
		area := bounds.width * bounds.height
		if rl.CheckCollisionPointRec(point, bounds) &&
		   area < best_area {best = index; best_area = area}
	}
	return best
}

ship_rendered_face_module_at :: proc(faces: []Ship_Project_Face, point: rl.Vector2) -> u32 {
	owner: u32 = ~u32(0)
	closest_depth := f32(1e30)
	for face in faces {
		if !ship_face_camera_facing(face) do continue
		if depth, inside := ship_face_depth_at(face, point); inside && depth < closest_depth {
			owner = face.module_id
			closest_depth = depth
		}
	}
	return owner
}

ship_closed_hull_hovered_module :: proc(
	r: ^game.Procedural_Ship_Recipe,
	rect: rl.Rectangle,
	camera: Ship_Generator_Camera,
	point: rl.Vector2,
) -> int {
	// Closed architectures subsume most recipe modules into one pressure body.
	// Their old modular-frame rectangles can overlap empty space and select an
	// invisible mission or tank. Pick the same visible faces the renderer uses.
	center, scale := ship_recipe_view_fit(r, camera, rect)
	faces := make([dynamic]Ship_Project_Face, 0, r.module_count * 24, context.temp_allocator)
	ship_append_closed_architecture_faces(&faces, r, camera, center, scale, true)
	greebly_budgets := [5]int{0, 8, 16, 30, 48}
	greebly_budget := greebly_budgets[clamp(r.greebly_density, 0, 4)]
	if greebly_budget > 0 do greebly_budget -= ship_append_closed_hull_auto_greeblies(&faces, r, r.greebly_density, greebly_budget, camera, center, scale)
	for module in r.modules[:r.module_count] {
		if !ship_module_exposed_by_architecture(r.architecture, module.module) do continue
		mounted := ship_closed_hull_mount_module(r, module)
		ship_append_module_faces(&faces, mounted, r.family, camera, center, scale)
		if greebly_budget > 0 do greebly_budget -= ship_append_auto_greeblies(&faces, mounted, r.greebly_density, greebly_budget, camera, center, scale)
	}
	owner := ship_rendered_face_module_at(faces[:], point)
	if owner == ~u32(0) do return -1
	// The loft is deliberately synthetic (owner 0); identify it using the
	// recipe's load-bearing keel rather than an embedded, non-visible module.
	if owner == 0 {
		for module, index in r.modules[:r.module_count] do if module.module == .Keel do return index
		return -1
	}
	for module, index in r.modules[:r.module_count] do if module.id == owner do return index
	return -1
}

draw_ship_module_hover :: proc(
	r: ^game.Procedural_Ship_Recipe,
	index: int,
	rect: rl.Rectangle,
	camera: Ship_Generator_Camera,
) {
	if index < 0 || index >= r.module_count do return
	center, scale := ship_recipe_view_fit(r, camera, rect); module := r.modules[index]
	if ship_architecture_has_closed_hull(r.architecture) &&
	   ship_module_exposed_by_architecture(r.architecture, module.module) {
		module = ship_closed_hull_mount_module(r, module)
	}
	bounds := ship_module_projected_bounds(module, camera, center, scale)
	rl.DrawRectangleRoundedLinesEx(bounds, 0, 1, 2, UX.info)
	for corner in 0 ..< 4 {
		a := V(
			corner & 1 == 0 ? bounds.x : bounds.x + bounds.width,
			corner & 2 == 0 ? bounds.y : bounds.y + bounds.height,
		)
		dx: f32 = corner & 1 == 0 ? 1 : -1; dy: f32 = corner & 2 == 0 ? 1 : -1
		rl.DrawLineEx(
			a,
			V(a.x + dx * 10, a.y),
			3,
			UX.text,
		); rl.DrawLineEx(a, V(a.x, a.y + dy * 10), 3, UX.text)
	}
}

draw_ship_detail_modal :: proc(s: ^Ux_State) {
	if s.campaign.ship_count <= 0 {s.modal = .None; return}
	ship := s.campaign.ships[clamp(s.selected_ship, 0, s.campaign.ship_count - 1)]
	recipe := game.procedural_ship_generate_for_ship(ship)
	rect := R(120, 70, 1040, 580); panel(rect, true)
	draw_text("SHIP SURVEY / CONSTRUCTION RECORD", 154, 100, TYPE_CAPTION, UX.info)
	draw_fmt(
		1124 - measure_text(fmt.tprintf("ID %04d", ship.id), TYPE_FINE).x,
		100,
		TYPE_FINE,
		UX.dim,
		"ID %04d",
		ship.id,
	)
	rl.DrawLineEx(V(154, 126), V(1126, 126), 1, UX.line)
	draw_text_fitted(ship.name, R(154, 146, 520, 48), TYPE_HERO_COMPACT, UX.text)
	draw_text_fitted(
		fmt.tprintf(
			"%s · %s · %s · %s",
			game.ship_operational_role_name(ship.operational_role),
			game.procedural_ship_family_name(recipe.family),
			game.ship_generator_kind_name(recipe.architecture),
			game.ship_construction_style_name(ship.construction_style),
		),
		R(158, 196, 650, 22),
		TYPE_SMALL_EMPHASIS,
		UX.info,
	)
	exhaust_phase := s.reduced_motion ? f32(.37) : f32(rl.GetTime())
	viewport := R(150, 232, 660, 330)
	// The engraving renderer emits hatch and wireframe geometry well beyond a
	// module's visible bounds at close zoom. Keep the expensive pass inside its
	// instrument window so zooming cannot paint over the dossier or the modal.
	rl.BeginScissorMode(viewport)
	draw_procedural_ship(
		&recipe,
		viewport,
		s.ship_detail_camera,
		true,
		{},
		true,
		exhaust_phase,
		ship_power_output_scale(ship),
	)
	if rl.CheckCollisionPointRec(ux_mouse, viewport) {
		wheel := rl.GetMouseWheelMove(
			
		); if wheel != 0 do s.ship_detail_camera.zoom = clamp(s.ship_detail_camera.zoom + wheel * .08, .55, 2.2)
		if rl.IsMouseButtonDown(
			.LEFT,
		) {delta := rl.GetMouseDelta(); s.ship_detail_camera.yaw += delta.x * .006; s.ship_detail_camera.pitch = clamp(s.ship_detail_camera.pitch + delta.y * .006, -1.35, 1.35)}
	}
	hovered := ship_hovered_module(&recipe, viewport, s.ship_detail_camera, ux_mouse)
	if ship_detail_capture_module >= 0 do hovered = clamp(ship_detail_capture_module, 0, recipe.module_count - 1)
	draw_ship_module_hover(&recipe, hovered, viewport, s.ship_detail_camera)
	rl.EndScissorMode()
	rl.DrawRectangleRoundedLinesEx(viewport, 0, 1, 1, UX.line)
	rl.DrawLineEx(V(840, 148), V(840, 574), 1, UX.line)
	draw_celestial_stat(870, 158, "HULL MASS", fmt.tprintf("%d t", ship.mass_tonnes))
	draw_celestial_stat(1000, 158, "CREW", fmt.tprintf("%d", ship.crew), UX.info)
	draw_celestial_stat(870, 226, "MODULES", fmt.tprintf("%02d", recipe.module_count))
	draw_celestial_stat(1000, 226, "POWER", fmt.tprintf("%d", ship.power))
	draw_celestial_stat(
		870,
		294,
		"CONDITION",
		ship.damage > 0 ? fmt.tprintf("DAMAGE %d", ship.damage) : "OPERATIONAL",
		ship.damage > 0 ? UX.warn : UX.good,
	)
	draw_celestial_stat(1000, 294, "SERVICE MARK", ship_generator_service_code(ship))
	label_caps("MODULE UNDER CURSOR", 870, 378, hovered >= 0 ? UX.info : UX.dim)
	if hovered >= 0 {
		module := recipe.modules[hovered]
		draw_text_fitted(
			ship_module_name(module.module),
			R(870, 401, 238, 24),
			TYPE_SUBHEADING_COMPACT,
			UX.text,
		)
		draw_text_wrapped(
			ship_module_description(module.module),
			R(870, 438, 238, 55),
			TYPE_LABEL,
			UX.dim,
		)
		draw_fmt(870, 505, TYPE_CAPTION, UX.info, "%v · %.1f MASS", module.material, module.mass)
		draw_fmt(
			870,
			526,
			TYPE_FINE,
			UX.dim,
			"MODULE %02d · SURFACE %04d",
			module.id,
			module.surface_id,
		)
	} else {
		draw_text_wrapped(
			"Hover any visible assembly to identify its installed function.",
			R(870, 405, 238, 55),
			TYPE_LABEL,
			UX.dim,
		)
	}
	draw_text("DRAG TO ORBIT · WHEEL TO ZOOM", 154, 586, TYPE_CAPTION, UX.dim)
	draw_text_fitted(
		ship_construction_profile_label(ship),
		R(154, 607, 650, 16),
		TYPE_FINE,
		UX.dim,
	)
	if back_button(R(1000, 594, 126, 32), "CLOSE") do s.modal = .None
}

ship_generator_identity :: proc(seed: u64, family: game.Procedural_Ship_Family) -> game.Ship {
	hull: game.Ship_Hull_Archetype; role: game.Ship_Operational_Role
	switch family {case .Strike:
		hull = .Strike_Fighter; role = .Strike_Fighter; case .Fleet:
		hull = .Heavy_Cruiser; role = .Heavy_Cruiser; case .Habitat:
		hull = .Habitat_Hull; role = .Habitat_Ship}
	return {
		id = game.Ship_ID(max(int(seed & 0x7fff), 1)),
		construction_seed = seed,
		hull_archetype = hull,
		operational_role = role,
	}
}

ship_generator_contact_role :: proc(
	family: game.Procedural_Ship_Family,
	row: int,
) -> game.Ship_Operational_Role {
	strike := [4]game.Ship_Operational_Role{.Strike_Fighter, .Scout, .Assault_Shuttle, .Bomber}
	fleet := [4]game.Ship_Operational_Role {
		.Heavy_Cruiser,
		.Fleet_Carrier,
		.Command_Ship,
		.Support_Frigate,
	}
	habitat := [4]game.Ship_Operational_Role {
		.Habitat_Ship,
		.Colony_Transport,
		.Fabricator_Ship,
		.Courier,
	}
	switch family {case .Strike:
		return strike[row % 4]; case .Fleet:
		return fleet[row % 4]; case .Habitat:
		return habitat[row % 4]}
	return .Heavy_Cruiser
}

ship_generator_contact_identity :: proc(
	seed, lineage: u64,
	family: game.Procedural_Ship_Family,
	row: int,
) -> game.Ship {
	role := ship_generator_contact_role(family, row)
	ship := game.Ship {
		id                   = game.Ship_ID(max(int(seed & 0x7fff), 1)),
		construction_seed    = seed,
		construction_lineage = lineage,
		hull_archetype       = game.ship_operational_role_hull(role),
		operational_role     = role,
	}
	switch row % 4 {case 1:
		ship.damage = 1; case 2:
		ship.damage = 3; ship.scar = .Hull_Breach; case 3:
		ship.dark_field_scars = 2; ship.scar = .Passage_Scarred; case 0:}
	return ship
}

ship_generator_contact_single_hull_identity :: proc(
	seed, lineage: u64,
	family: game.Procedural_Ship_Family,
	row: int,
) -> game.Ship {
	ship := ship_generator_contact_identity(seed, lineage, family, row)
	ship.generator_kind = .Single_Hull
	ship.construction_style = row & 1 == 0 ? .Machine_Partnership : .Living_Hullcraft
	return ship
}

ship_generator_contact_architecture_identity :: proc(
	seed, lineage: u64,
	family: game.Procedural_Ship_Family,
	row: int,
	architecture: game.Ship_Generator_Kind,
) -> game.Ship {
	ship := ship_generator_contact_identity(seed, lineage, family, row)
	ship.generator_kind = architecture
	if ship_architecture_has_closed_hull(architecture) do ship.construction_style = row & 1 == 0 ? .Machine_Partnership : .Living_Hullcraft
	return ship
}

ship_generator_service_code :: proc(ship: game.Ship) -> string {
	if ship.dark_field_scars > 0 do return "DARK SCAR"
	if ship.scar == .Hull_Breach do return "BREACH CAGE"
	if ship.damage > 0 do return "PATCHED"
	return "YARD CLEAN"
}

ship_generator_profile_code :: proc(ship: game.Ship) -> string {
	return fmt.tprintf(
		"K%d/W%d/S%d/D%d/E%d/B%d/M%d/H%d",
		game.ship_construction_keel_profile(ship) + 1,
		game.ship_construction_wing_stance(ship) + 1,
		game.ship_construction_wing_sweep(ship) + 1,
		game.ship_construction_drive_layout(ship) + 1,
		game.ship_construction_drive_setback(ship) + 1,
		game.ship_construction_bow_profile(ship) + 1,
		game.ship_construction_mission_profile(ship) + 1,
		game.ship_construction_utility_hardpoint(ship) + 1,
	)
}
