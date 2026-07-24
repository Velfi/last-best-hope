package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:testing"
import stbi "vendor:stb/image"
ship_generator_build :: proc(s: ^Ux_State) {
	architecture := s.ship_generator_recipe.architecture
	ship := ship_generator_identity(s.ship_generator_seed, s.ship_generator_family)
	ship.generator_kind = architecture
	s.ship_generator_recipe = game.procedural_ship_generate_for_ship(ship)
	s.ship_generator_ready = true
}

draw_ship_generator :: proc(s: ^Ux_State) {
	if !s.ship_generator_ready {s.ship_generator_seed = u64(rl.GetTime() * 1000000) + 1; s.ship_generator_camera = ship_generator_default_camera(); ship_generator_build(s)}
	draw_stars(
		
	); draw_text("SHIP GENERATOR", 34, 25, TYPE_DISPLAY_COMPACT, UX.text); draw_text("PROCEDURAL CONSTRUCTION · LIVING ENGRAVING", 36, 62, TYPE_SMALL, UX.info)
	exhaust_phase := s.reduced_motion ? f32(.37) : f32(rl.GetTime())
	viewport := R(
		320,
		92,
		900,
		520,
	); panel(viewport, true); draw_procedural_ship(&s.ship_generator_recipe, R(334, 106, 872, 492), s.ship_generator_camera, true, {}, true, exhaust_phase)
	if rl.CheckCollisionPointRec(ux_mouse, viewport) {
		wheel := rl.GetMouseWheelMove(
			
		); if wheel != 0 do s.ship_generator_camera.zoom = clamp(s.ship_generator_camera.zoom + wheel * .08, .55, 2.2)
		if rl.IsMouseButtonDown(
			.LEFT,
		) {d := rl.GetMouseDelta(); s.ship_generator_camera.yaw += d.x * .006; s.ship_generator_camera.pitch = clamp(s.ship_generator_camera.pitch + d.y * .006, -1.35, 1.35)}
	}
	controls := R(
		28,
		92,
		270,
		520,
	); panel(controls); label_caps("CONSTRUCTION SEED", 48, 118, UX.info); draw_fmt(48, 146, TYPE_BODY, UX.text, "%d", s.ship_generator_seed)
	if button(
		R(48, 176, 55, 30),
		"−",
	) {s.ship_generator_seed = max(s.ship_generator_seed - 1, 1); ship_generator_build(s)}
	if button(R(110, 176, 55, 30), "+") {s.ship_generator_seed += 1; ship_generator_build(s)}
	if button(
		R(172, 176, 106, 30),
		"RANDOM",
	) {s.ship_generator_seed = u64(rl.GetTime() * 1000000) + 1; ship_generator_build(s)}
	label_caps(
		"FRAME FAMILY",
		48,
		232,
	); families := [3]game.Procedural_Ship_Family{.Strike, .Fleet, .Habitat}; labels := [3]string{"STRIKE", "FLEET", "HABITAT"}
	for family, i in families do if radio_button(R(48, 258 + f32(i) * 38, 230, 30), labels[i], s.ship_generator_family == family) {s.ship_generator_family = family; ship_generator_build(s)}
	label_caps("ARCHITECTURE", 48, 378)
	architectures := [3]game.Ship_Generator_Kind {
		.Modular_Frame,
		.Single_Hull,
		.Delta,
	}; architecture_labels := [3]string{"FRAME", "HULL", "DELTA"}
	for architecture, i in architectures {x := 48 + f32(i) * 77; y := f32(402); if radio_button(R(x, y, 70, 28), architecture_labels[i], s.ship_generator_recipe.architecture == architecture) {s.ship_generator_recipe.architecture = architecture; ship_generator_build(s)}}
	if button(R(48, 474, 230, 30), "RESET CAMERA") do s.ship_generator_camera = ship_generator_default_camera()
	label_caps(
		"RECIPE",
		48,
		516,
	); r := &s.ship_generator_recipe; draw_fmt(48, 542, TYPE_LABEL, UX.text, "%d MODULES · %.1f MASS", r.module_count, r.mass); draw_fmt(48, 564, TYPE_CAPTION, r.complete ? UX.good : UX.bad, "SOLVER %s · %d BACKTRACKS", r.complete ? "COMPLETE" : "INVALID", r.backtracks); draw_fmt(48, 586, TYPE_FINE, UX.dim, "FINGERPRINT %016x", r.fingerprint)
	if back_button(
		R(28, 650, 150, 38),
		"← MENU",
	) {s.screen = s.return_screen; s.ship_generator_ready = false}
	draw_text(
		"DRAG TO ORBIT · WHEEL TO ZOOM · SURFACE-ANCHORED HATCH",
		320,
		662,
		TYPE_LABEL,
		UX.dim,
	)
}

ship_contact_capture_architecture := game.Ship_Generator_Kind.Modular_Frame

ship_contact_architecture_from_name :: proc(name: string) -> game.Ship_Generator_Kind {
	switch name {
	case "single":
		return .Single_Hull
	case "delta":
		return .Delta
	case:
		return .Modular_Frame
	}
}

ship_contact_service_mark_from_name :: proc(
	name: string,
) -> (game.Procedural_Ship_Service_Mark, bool) {
	switch name {
	case "patch":
		return .Patch_Plate, true
	case "breach":
		return .Breach_Cage, true
	case "dark":
		return .Dark_Scar, true
	}
	return .None, false
}

ship_contact_recipe_dump_main :: proc() {
	base_seed := u64(24301)
	family := game.Procedural_Ship_Family.Fleet
	if len(os.args) >= 3 do base_seed = parse_u64_or(os.args[2], base_seed)
	if len(os.args) >= 4 do family = game.procedural_ship_family_from_name(os.args[3])
	fmt.println("row,module,kind,x,y,z,sx,sy,sz")
	for row in 0 ..< 4 {
		ship := ship_generator_contact_identity(
			base_seed + u64(row),
			base_seed,
			family,
			row,
		)
		recipe := game.procedural_ship_generate_for_ship(ship)
		for module, index in recipe.modules[:recipe.module_count] {
			fmt.printf(
				"%d,%d,%d,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f\n",
				row,
				index,
				int(module.module),
				module.position[0],
				module.position[1],
				module.position[2],
				module.scale[0],
				module.scale[1],
				module.scale[2],
			)
		}
	}
}

ship_contact_dump_projected_segment :: proc(
	row, column: int,
	a_world, b_world: [3]f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale, width: f32,
) {
	a := ship_project(a_world, camera, center, scale)
	b := ship_project(b_world, camera, center, scale)
	dx, dy := b.screen.x - a.screen.x, b.screen.y - a.screen.y
	length := f32(math.sqrt(f64(dx * dx + dy * dy)))
	if length < .001 do return
	nx, ny := -dy / length * width, dx / length * width
	fmt.printf(
		"%d,%d,%d,%.5f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f\n",
		row,
		column,
		int(game.Ship_Material_Class.Truss),
		(a.depth + b.depth) * .5,
		a.screen.x + nx,
		a.screen.y + ny,
		b.screen.x + nx,
		b.screen.y + ny,
		b.screen.x - nx,
		b.screen.y - ny,
		a.screen.x - nx,
		a.screen.y - ny,
	)
}

ship_contact_face_dump_main :: proc() {
	base_seed := u64(24301)
	family := game.Procedural_Ship_Family.Fleet
	architecture := game.Ship_Generator_Kind.Modular_Frame
	if len(os.args) >= 3 do base_seed = parse_u64_or(os.args[2], base_seed)
	if len(os.args) >= 4 do family = game.procedural_ship_family_from_name(os.args[3])
	if len(os.args) >= 5 do architecture = ship_contact_architecture_from_name(os.args[4])
	views := [4]Ship_Generator_Camera {
		{.52, .55, 1},
		{0, math.PI * .5, 1},
		{0, 0, 1},
		{math.PI * .5, 0, 1},
	}
	ships: [4]game.Ship
	recipes: [4]game.Procedural_Ship_Recipe
	shared: [4]Ship_View_Span
	force_greeblies := false
	clear_service_marks := false
	forced_mark := game.Procedural_Ship_Service_Mark.None
	has_forced_mark := false
	if len(os.args) > 5 do for option in os.args[5:] {
		if option == "greeblies" {
			force_greeblies = true
		} else if option == "pristine" {
			clear_service_marks = true
		} else {
			mark, found := ship_contact_service_mark_from_name(option)
			if found {
				clear_service_marks = true
				forced_mark = mark
				has_forced_mark = true
			}
		}
	}
	for row in 0 ..< 4 {
		ships[row] = ship_generator_contact_architecture_identity(
			base_seed + u64(row),
			base_seed,
			family,
			row,
			architecture,
		)
		recipes[row] = game.procedural_ship_generate_for_ship(ships[row])
		if clear_service_marks {
			for &module in recipes[row].modules[:recipes[row].module_count] do module.service_mark = .None
		}
		if has_forced_mark {
			for &module in recipes[row].modules[:recipes[row].module_count] {
				if !game.procedural_ship_service_mark_compatible(module.module) do continue
				module.service_mark = forced_mark
				break
			}
		}
		if force_greeblies do recipes[row].greebly_density = 4
	}
	for column in 0 ..< 4 do for row in 0 ..< 4 {
		span := ship_recipe_view_span(&recipes[row], views[column])
		shared[column].x = max(shared[column].x, span.x)
		shared[column].z = max(shared[column].z, span.z)
	}
	fmt.println("row,column,material,depth,x0,y0,x1,y1,x2,y2,x3,y3")
	cell := R(0, 0, 440, 205)
	for row in 0 ..< 4 do for column in 0 ..< 4 {
		recipe := &recipes[row]
		camera := views[column]
		center, scale := ship_recipe_view_fit(recipe, camera, cell, shared[column])
		faces := make([dynamic]Ship_Project_Face, 0, recipe.module_count * 24, context.temp_allocator)
		if ship_architecture_has_closed_hull(recipe.architecture) {
			ship_append_closed_architecture_faces(&faces, recipe, camera, center, scale, false)
		} else {
			for station in 1 ..< recipe.frame.station_count do ship_append_keel_bridge_faces(&faces, recipe, station, camera, center, scale)
			ship_append_strike_prow_bridle_faces(&faces, recipe, camera, center, scale)
			ship_append_modular_fleet_weapon_faces(&faces, recipe, camera, center, scale)
		}
		greebly_budget := force_greeblies ? 30 : 0
		if greebly_budget > 0 && ship_architecture_has_closed_hull(recipe.architecture) {
			greebly_budget -= ship_append_closed_hull_auto_greeblies(
				&faces,
				recipe,
				recipe.greebly_density,
				greebly_budget,
				camera,
				center,
				scale,
			)
		}
		for source in recipe.modules[:recipe.module_count] {
			if !ship_module_exposed_by_architecture(recipe.architecture, source.module) do continue
			module := ship_closed_hull_mount_module(recipe, source)
			if recipe.architecture == .Delta && module.module == .Drive {
				ship_append_delta_distant_drive_faces(&faces, module, recipe.family, camera, center, scale)
			} else {
				ship_append_module_faces(&faces, module, recipe.family, camera, center, scale)
			}
			if greebly_budget > 0 {
				greebly_budget -= ship_append_auto_greeblies(
					&faces,
					module,
					recipe.greebly_density,
					greebly_budget,
					camera,
					center,
					scale,
				)
			}
		}
		// These projected rails are part of the live ship renderer but are not
		// polygon faces. Emit screen-space quads before the solid faces so the
		// headless contact sheet preserves the same connected load paths and
		// payload occlusion as the interactive view.
		if recipe.architecture == .Modular_Frame {
			for station in 1 ..< recipe.frame.station_count {
				for segment in ship_axial_bay_segments(recipe, station) {
					ship_contact_dump_projected_segment(
						row,
						column,
						segment[0],
						segment[1],
						camera,
						center,
						scale,
						.40,
					)
				}
			}
			for module in recipe.modules[:recipe.module_count] {
				if module.module == .Truss {
					for segment in ship_truss_local_segments(module) {
						ship_contact_dump_projected_segment(
							row,
							column,
							ship_module_local_point(module, segment[0]),
							ship_module_local_point(module, segment[1]),
							camera,
							center,
							scale,
							.42,
						)
					}
				} else if module.module == .Dock {
					for segment in ship_dock_guide_local_segments(module) {
						ship_contact_dump_projected_segment(
							row,
							column,
							ship_module_local_point(module, segment[0]),
							ship_module_local_point(module, segment[1]),
							camera,
							center,
							scale,
							.38,
						)
					}
				}
			}
		}
		ship_face_sort(faces[:])
		for face in faces {
			if !ship_face_camera_facing(face) do continue
			fmt.printf(
				"%d,%d,%d,%.5f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f\n",
				row,
				column,
				int(face.material),
				face.depth,
				face.points[0].x,
				face.points[0].y,
				face.points[1].x,
				face.points[1].y,
				face.points[2].x,
				face.points[2].y,
				face.points[3].x,
				face.points[3].y,
			)
		}
	}
}

draw_ship_contact_sheet :: proc(
	base_seed: u64,
	family: game.Procedural_Ship_Family,
	width, height: i32,
	single_hull := false,
) {
	architecture := ship_contact_capture_architecture
	if single_hull do architecture = .Single_Hull
	closed := ship_architecture_has_closed_hull(architecture)
	rl.DrawRectangle(
		0,
		0,
		width,
		height,
		{0, 0, 0, 255},
	); margin := f32(min(width, height)) * .025; header := f32(height) * .085; row_h := (f32(height) - header - margin) / 4; cell_w := (f32(width) - margin * 2) / 4
	draw_text(
		closed ? fmt.tprintf("%s SHIP CONTACT SHEET", game.ship_generator_kind_name(architecture)) : "PROCEDURAL SHIP CONTACT SHEET",
		margin,
		18,
		f32(max(18, int(f32(height) * .022))),
		UX.text,
	); draw_text(fmt.tprintf("%s · LINEAGE %d · FOUR ROLE / SERVICE REFITS · COMMON VIEW SCALE", game.procedural_ship_family_name(family), base_seed), margin, 52, f32(max(10, int(f32(height) * .009))), UX.dim)
	views := [4]Ship_Generator_Camera {
		{.52, .55, 1},
		{0, math.PI * .5, 1},
		{0, 0, 1},
		{math.PI * .5, 0, 1},
	}; view_names := [4]string{"THREE-QUARTER", "TOP", "SIDE", "STERN / SECTION"}
	ships: [4]game.Ship; recipes: [4]game.Procedural_Ship_Recipe; shared: [4]Ship_View_Span
	for row in 0 ..< 4 {seed := base_seed + u64(row); ships[row] = ship_generator_contact_architecture_identity(seed, base_seed, family, row, architecture); recipes[row] = game.procedural_ship_generate_for_ship(ships[row])}
	for column in 0 ..< 4 do for row in 0 ..< 4 {span := ship_recipe_view_span(&recipes[row], views[column]); shared[column].x = max(shared[column].x, span.x); shared[column].z = max(shared[column].z, span.z)}
	for column in 0 ..< 4 do draw_text(view_names[column], margin + f32(column) * cell_w + 12, header - 22, f32(max(9, int(f32(height) * .006))), UX.info)
	for row in 0 ..< 4 {seed := base_seed + u64(row); ship := ships[row]; recipe := &recipes[row]; y := header + f32(row) * row_h; draw_text(fmt.tprintf("SEED %d · %d MODULES · %s · %s · %s", seed, recipe.module_count, ship_generator_profile_code(ship), game.ship_operational_role_name(ship.operational_role), ship_generator_service_code(ship)), margin + 8, y + 18, f32(max(8, int(f32(height) * .0055))), UX.dim); for column in 0 ..< 4 {x := margin + f32(column) * cell_w; cell := R(x + 4, y + 28, cell_w - 8, row_h - 34); rl.DrawRectangleRec(cell, {0, 0, 0, 255}); draw_procedural_ship(recipe, cell, views[column], false, shared[column]); rl.DrawLineEx(V(x, y + row_h - 1), V(x + cell_w - 8, y + row_h - 1), 1, UX.line)}}
}

ship_contact_resize_png :: proc(path: string, width, height: i32) -> bool {
	w, h, channels: c.int; source := stbi.load(fmt.ctprintf("%s", path), &w, &h, &channels, 4); if source == nil do return false; defer stbi.image_free(source)
	if w == c.int(width) && h == c.int(height) do return true
	pixels := make([]u8, int(width) * int(height) * 4); defer delete(pixels)
	if stbi.resize_uint8(source, w, h, 0, raw_data(pixels), c.int(width), c.int(height), 0, 4) == 0 do return false
	return(
		stbi.write_png(
			fmt.ctprintf("%s", path),
			c.int(width),
			c.int(height),
			4,
			raw_data(pixels),
			c.int(width * 4),
		) !=
		0 \
	)
}

@(test)
ship_contact_sheet_uses_four_lineage_refits_and_four_fixed_views :: proc(t: ^testing.T) {base :=
		u64(500)
	for i in 0 ..< 4 {ship := ship_generator_contact_identity(base + u64(i), base, .Fleet, i); r :=
			game.procedural_ship_generate_for_ship(ship)
		testing.expect_value(t, r.seed, base + u64(i))
		testing.expect_value(t, ship.construction_lineage, base)
		testing.expect_value(t, r.family, game.Procedural_Ship_Family.Fleet)
		testing.expect(t, ship_generator_service_code(ship) != "")}
	testing.expect_value(
		t,
		ship_generator_service_code(ship_generator_contact_identity(base, base, .Fleet, 0)),
		"YARD CLEAN",
	)
	testing.expect_value(
		t,
		ship_generator_service_code(ship_generator_contact_identity(base + 2, base, .Fleet, 2)),
		"BREACH CAGE",
	)
	testing.expect_value(
		t,
		ship_generator_service_code(ship_generator_contact_identity(base + 3, base, .Fleet, 3)),
		"DARK SCAR",
	)
	a := ship_generator_default_camera()
	testing.expect(t, a.zoom == 1 && a.yaw != 0 && a.pitch != 0)
	end := Ship_Generator_Camera{math.PI * .5, 0, 1}
	center := rl.Vector2{100, 100}
	axial := ship_project({4, 0, 0}, end, center, 1).screen
	lateral := ship_project({0, 4, 0}, end, center, 1).screen
	testing.expect(t, math.abs(axial.x - center.x) < .001 && math.abs(axial.y - center.y) < .001)
	testing.expect(t, math.abs(lateral.x - center.x) > 3.9)}

ship_contact_shared_span_preserves_equal_scale_while_centering_each_hull :: proc(t: ^testing.T) {
	a := game.procedural_ship_generate_for_ship(
		ship_generator_contact_identity(700, 700, .Fleet, 0),
	); b := game.procedural_ship_generate_for_ship(ship_generator_contact_identity(703, 700, .Fleet, 3))
	camera := ship_generator_default_camera(
		
	); sa := ship_recipe_view_span(&a, camera); sb := ship_recipe_view_span(&b, camera); shared := Ship_View_Span{max(sa.x, sb.x), max(sa.z, sb.z)}; rect := R(0, 0, 480, 260)
	ca, scale_a := ship_recipe_view_fit(
		&a,
		camera,
		rect,
		shared,
	); cb, scale_b := ship_recipe_view_fit(&b, camera, rect, shared)
	testing.expect_value(
		t,
		scale_a,
		scale_b,
	); testing.expect(t, shared.x >= sa.x && shared.x >= sb.x && shared.z >= sa.z && shared.z >= sb.z)
	testing.expect(
		t,
		ca.x >= rect.x &&
		ca.x <= rect.x + rect.width &&
		cb.x >= rect.x &&
		cb.x <= rect.x + rect.width,
	)
}

@(test)
ship_contact_role_matrix_exposes_family_specific_mission_hardware :: proc(t: ^testing.T) {
	for family in game.Procedural_Ship_Family {
		roles: [4]game.Ship_Operational_Role; signatures: [4]game.Procedural_Ship_Module
		for row in 0 ..< 4 {
			roles[row] = ship_generator_contact_role(family, row)
			ship := ship_generator_contact_identity(900 + u64(row), 900, family, row)
			signatures[row] = game.procedural_ship_role_signature(ship, family)
			r := game.procedural_ship_generate_for_ship(ship); found := false
			for module in r.modules[:r.module_count] do found = found || module.module == signatures[row]
			testing.expect(t, found)
		}
		for i in 0 ..< 4 do for j in i + 1 ..< 4 do testing.expect(t, roles[i] != roles[j])
		unique_signatures := 0
		for i in 0 ..< 4 {fresh := true; for j in 0 ..< i do fresh = fresh && signatures[i] != signatures[j]; if fresh do unique_signatures += 1}
		testing.expect(t, unique_signatures >= 3)
	}
}

@(test)
ship_contact_sheet_profile_code_exposes_all_persistent_geometry_axes :: proc(t: ^testing.T) {
	ship := game.Ship {
		keel_profile      = 1,
		wing_stance       = 2,
		wing_sweep        = 3,
		drive_layout      = 1,
		drive_setback     = 2,
		bow_profile       = 3,
		mission_profile   = 1,
		utility_hardpoint = 9,
	}
	testing.expect_value(t, ship_generator_profile_code(ship), "K1/W2/S3/D1/E2/B3/M1/H9")
}

@(test)
ship_cross_section_vocabulary_reserves_high_radial_counts_for_pressure_structure :: proc(
	t: ^testing.T,
) {
	for geometry in Ship_Module_Geometry {
		segments := ship_geometry_radial_segments(geometry)
		if geometry == .Pressure_Cylinder || geometry == .Habitat_Ring {
			testing.expect(t, segments > 8)
		} else {
			testing.expect(t, segments <= 8)
		}
	}
	testing.expect_value(t, ship_geometry_radial_segments(.Tank_Barrel), 6)
	testing.expect_value(t, ship_geometry_radial_segments(.Drive_Nozzle), 6)
}

@(test)
ship_contact_sheet_hatching_preserves_black_mass_at_small_scale :: proc(t: ^testing.T) {
	close := ship_material_hatch_for_view(.Hull_Plate, .72, 17, true)
	distant := ship_material_hatch_for_view(.Hull_Plate, .72, 17, false)
	testing.expect(t, distant.layer_count < close.layer_count)
	testing.expect(t, distant.spacing > close.spacing)
	testing.expect(t, distant.line_width < close.line_width)
	shadow := ship_material_hatch_for_view(.Hull_Plate, .2, 17, false)
	testing.expect_value(t, shadow.layer_count, 1)
}

@(test)
single_hull_hatch_reserves_dense_marks_for_working_surfaces :: proc(t: ^testing.T) {
	hull := ship_single_hull_hatch_for_view(.Hull_Plate, .72, 17, true)
	armor := ship_single_hull_hatch_for_view(.Armor, .72, 18, true)
	machinery := ship_single_hull_hatch_for_view(.Machinery, .72, 19, true)
	standard := ship_material_hatch_for_view(.Hull_Plate, .72, 17, true)
	testing.expect_value(t, hull.layer_count, 1)
	testing.expect(t, hull.spacing > standard.spacing && hull.strength < standard.strength)
	testing.expect(
		t,
		machinery.layer_count > hull.layer_count && machinery.spacing < armor.spacing,
	)
}

@(test)
ship_solid_face_tones_separate_volume_from_space_without_losing_black_mass :: proc(t: ^testing.T) {
	dark := ship_material_base_tone(
		.Hull_Plate,
		0,
		false,
	); lit := ship_material_base_tone(.Hull_Plate, 1, false)
	testing.expect(t, dark > 3 && lit > dark && lit <= 31)
	testing.expect(
		t,
		ship_material_base_tone(.Armor, .5, false) <
		ship_material_base_tone(.Machinery, .5, false),
	)
	testing.expect(
		t,
		ship_material_base_tone(.Radiator, .5, false) < ship_material_base_tone(.Glass, .5, false),
	)
}

@(test)
ship_modules_use_distinct_structural_geometry :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		ship_module_geometry(.Pressure_Hull),
		Ship_Module_Geometry.Pressure_Cylinder,
	)
	testing.expect_value(t, ship_module_geometry(.Tank), Ship_Module_Geometry.Tank_Barrel)
	testing.expect_value(t, ship_module_geometry(.Drive), Ship_Module_Geometry.Drive_Nozzle)
	testing.expect_value(t, ship_module_geometry(.Dock), Ship_Module_Geometry.Dock_Frame)
	testing.expect_value(t, ship_module_geometry(.Radiator), Ship_Module_Geometry.Radiator_Array)
	testing.expect_value(t, ship_module_geometry(.Mission), Ship_Module_Geometry.Mission_Block)
	testing.expect_value(t, ship_module_geometry(.Antenna), Ship_Module_Geometry.Antenna_Array)
	testing.expect_value(t, ship_module_geometry(.Bow), Ship_Module_Geometry.Bow_Wedge)
	testing.expect_value(t, ship_module_geometry(.Ring_Segment), Ship_Module_Geometry.Habitat_Ring)
	testing.expect_value(t, ship_module_geometry(.Armor), Ship_Module_Geometry.Armor_Shield)
	testing.expect_value(t, ship_module_geometry(.Truss), Ship_Module_Geometry.Open_Truss)
}

@(test)
ship_keel_massing_is_lean_for_strike_and_layered_for_large_hulls :: proc(t: ^testing.T) {
	testing.expect_value(t, ship_keel_subassembly_count(.Strike), 1)
	testing.expect_value(t, ship_keel_subassembly_count(.Fleet), 4)
	testing.expect_value(t, ship_keel_subassembly_count(.Habitat), 4)
	module := game.Procedural_Ship_Placement {
		module    = .Keel,
		material  = .Hull_Plate,
		scale     = {.7, .5, .4},
		direction = {1, 0, 0},
	}
	for family in game.Procedural_Ship_Family {
		faces := make([dynamic]Ship_Project_Face, 0, 24, context.temp_allocator)
		ship_append_keel_faces(&faces, module, family, Ship_Generator_Camera{}, rl.Vector2{}, 1)
		testing.expect_value(t, len(faces), ship_keel_subassembly_count(family) * 6)
		if family != .Strike {
			machined_faces := 0
			for face in faces do if face.material != .Hull_Plate do machined_faces += 1
			testing.expect_value(t, machined_faces, 18)
		}
	}
}

@(test)
ship_keel_bridges_form_family_specific_citadels_and_ring_districts :: proc(t: ^testing.T) {
	counts: [3]int
	for family in game.Procedural_Ship_Family {
		r := game.procedural_ship_generate(24301, family)
		faces := make([dynamic]Ship_Project_Face, 0, 256, context.temp_allocator)
		for station in 1 ..< r.frame.station_count {
			if !ship_keel_bridge_enabled(&r, station) do continue
			counts[int(family)] += 1
			before := len(
				faces,
			); ship_append_keel_bridge_faces(&faces, &r, station, Ship_Generator_Camera{}, rl.Vector2{}, 1)
			expected := family == .Fleet ? 42 : 24
			testing.expect_value(t, len(faces) - before, expected)
			for face in faces[before:] do testing.expect(t, face.material == .Armor || face.material == .Machinery)
		}
	}
	testing.expect_value(t, counts[int(game.Procedural_Ship_Family.Strike)], 0)
	testing.expect(t, counts[int(game.Procedural_Ship_Family.Fleet)] >= 3)
	testing.expect(t, counts[int(game.Procedural_Ship_Family.Habitat)] >= 2)
}
