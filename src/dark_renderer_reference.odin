package main

import game "../packages/game"
import "core:math"
import "core:mem"
import "core:testing"
import "core:time"
import vk "vendor:vulkan"
import rl "zelda_engine:canvas2d"
import engine "zelda_engine:engine"

dark_door_section_visibility :: proc(observer_w, door_w, radius: f64) -> f32 {
	local_w := math.abs(observer_w - door_w) / max(radius, .001)
	if local_w >= 1 do return 0
	return f32(math.sqrt(1 - local_w * local_w))
}

dark_door_section_color :: proc(observer_w, door_w: f64, inward, outward: [4]f32) -> [4]f32 {
	return door_w >= observer_w ? inward : outward
}

@(test)
dark_door_section_visibility_fades_at_the_w_boundary :: proc(t: ^testing.T) {
	testing.expect_value(t, dark_door_section_visibility(0, 0, 2), f32(1))
	testing.expect(t, dark_door_section_visibility(0, 1, 2) > 0)
	testing.expect_value(t, dark_door_section_visibility(0, 2, 2), f32(0))
}

@(test)
dark_door_section_color_marks_inward_and_outward_routes :: proc(t: ^testing.T) {
	inward := [4]f32{.48, .76, .82, .94}
	outward := [4]f32{.49, .70, .53, .92}
	testing.expect_value(t, dark_door_section_color(0, 1, inward, outward), inward)
	testing.expect_value(t, dark_door_section_color(0, -1, inward, outward), outward)
}

dark_3d_build_reference :: proc(s: ^Ux_State) {
	resize(
		&combat_3d.vertices,
		0,
	); resize(&combat_3d.glow_vertices, 0); resize(&combat_3d.instances, 0); resize(&combat_3d.terrain_instances, 0)
	combat_3d.creature_gene_count = 0; combat_3d.creature_visible_count = 0
	for &count in combat_3d.instance_count do count = 0
	continuum := &s.campaign.outer_dark.continuum; navigation := &s.campaign.passage.dark_navigation
	dim := [4]f32 {
		.35,
		.41,
		.41,
		.40,
	}; info := [4]f32{.48, .76, .82, .94}; good := [4]f32{.49, .70, .53, .92}; warn := [4]f32{.80, .67, .37, .98}; committed := [4]f32{.62, .50, .74, .90}
	current_depth := dark_render_depth(continuum, navigation.position)
	current_band := int(math.floor(current_depth / DARK_DEPTH_BAND_SPACING))
	// Anchor-relative metric bands replace decorative fixed-Z rings. Only the
	// neighborhood around the current band is emitted.
	for band in max(current_band - 2, 1) ..= current_band + 3 {
		radius := f32(f64(band) * DARK_DEPTH_BAND_SPACING * 44)
		confidence := navigation.forecast.topology_confidence
		alpha := f32(.07 + .08 * clamp(confidence, .35, 1))
		dark_append_depth_lamina({}, radius, band, continuum.seed, {dim[0], dim[1], dim[2], alpha})
	}
	// Sparse suspended cuts provide parallax between the observer, ecology, and
	// correspondence shells. They are deterministic world marks—not screen
	// noise—and remain sparse enough for the Dark's black rest to dominate.
	for mote in 0 ..< 54 {
		hash := game.combat_mix(continuum.seed + u64(mote + 1) * 0x9e3779b97f4a7c15)
		x :=
			(f32(hash & 0xffff) / 65535 - .5) *
			1180; y := (f32((hash >> 16) & 0xffff) / 65535 - .5) * 760; z := (f32((hash >> 32) & 0xffff) / 65535 - .5) * 1050
		length :=
			2.4 +
			f32((hash >> 48) & 0xff) /
				255 *
				6.2; alpha := .18 + f32((hash >> 56) & 0xff) / 255 * .26
		combat_3d_append_line(
			{x - length, y, z - length * .35},
			{x + length, y, z + length * .35},
			{.55, .62, .61, alpha},
		)
	}
	scale := f32(
		44,
	); fleet_position := navigation.position; view_origin := continuum.anchor_position
	// The view exposes X, Y, and Z as navigable space; W is the dimension being
	// sectioned. Each lamina therefore keeps its fixed 4D position and physical
	// extent. Moving through XYZ translates it through the view, while moving in
	// W changes the observed 3D cross-section. No nearest-field promotion, scale
	// inflation, or presentation-time fade participates in that geometry.
	for field in continuum.fields[:continuum.field_count] {
		local_w := (fleet_position[3] - field.position[3]) / max(field.radius, .001)
		if math.abs(local_w) > 1 do continue
		center := game.Combat_Vec3 {
			f32(field.position[0] - view_origin[0]) * scale,
			f32(field.position[1] - view_origin[1]) * scale,
			f32(field.position[2] - view_origin[2]) * scale,
		}
		radius := f32(field.radius) * scale
		slice_control := f32(clamp(local_w * .5 + .5, 0, 1))
		material := f32(clamp(field.film + field.hush * .6, 0, 1))
		combat_3d_append_terrain_volume(
			center,
			radius,
			radius,
			DARK_VOLUME_MEMBRANE,
			f32(field.id % 16777216),
			material,
			slice_control,
			{.88, .86, .78, .28 + material * .52},
		)
	}
	// Reserve depth-tested generated genomes for nearby ecology before minor
	// fields consume the fixed terrain budget. The organism id selects a stable
	// 4D CSG anatomy; W traversal and simulation time animate that same body.
	selected: [game.MAX_DARK_ORGANISMS]int; selected_count := 0
	for organism, index in continuum.organisms[:continuum.organism_count] {if organism.alive {selected[selected_count] = index; selected_count += 1}}
	for i in 1 ..< selected_count {value := selected[i]; j := i; for j > 0 {a := continuum.organisms[selected[j - 1]]; b := continuum.organisms[value]; ad := game.dark_vec4_length(game.dark_vec4_sub(a.position, fleet_position)); bd := game.dark_vec4_length(game.dark_vec4_sub(b.position, fleet_position)); if ad < bd || ad == bd && a.id < b.id do break; selected[j] = selected[j - 1]; j -= 1}; selected[j] = value}
	ecology_volumes := 0
	for selected_index in selected[:min(selected_count, COMBAT_3D_MAX_CREATURES)] {
		organism := &continuum.organisms[selected_index]
		track: ^game.Dark_Track
		for &candidate in navigation.tracker.tracks[:navigation.tracker.track_count] do if candidate.organism_id == organism.id {track = &candidate; break}
		// The command sensorium must not reveal simulation-perfect ecology. Only
		// detected organisms appear, at the tracker's estimated fix.
		if track == nil do continue
		estimated := game.dark_vec4_add(fleet_position, track.relative_bearing)
		position := game.Combat_Vec3 {
			f32(estimated[0] - view_origin[0]) * scale,
			f32(estimated[1] - view_origin[1]) * scale,
			f32(estimated[2] - view_origin[2]) * scale,
		}
		color :=
			organism.role == .Shear_Hunter ? warn : organism.role == .Grave_Reef ? committed : info
		radius := max(f32(track.estimated_extent) * scale * 1.35, 24)
		local_w := f32((fleet_position[3] - estimated[3]) / max(track.estimated_extent, .001))
		combat_3d_append_generated_creature(
			continuum.seed,
			organism,
			position,
			radius,
			local_w,
			{color[0], color[1], color[2], organism.role == .Shear_Hunter ? .72 : .52},
			f32(track.confidence),
		)
		threat := game.dark_track_threat(track)
		if threat.level !=
		   .Clear {threat_color := threat.level == .Hold ? [4]f32{.96, .25, .20, .96} : warn; combat_3d_append_orbit(position, radius * 1.22, {threat_color[0], threat_color[1], threat_color[2], threat_color[3]}, 0, 28); if threat.closing do combat_3d_append_orbit(position, radius * 1.38, {threat_color[0], threat_color[1], threat_color[2], threat_color[3] * .52}, 1, 20)}
		ecology_volumes += 1
	}
	// The expedition is drawn below from its generated hull recipe. Do not add a
	// generic terrain volume here: it reads as a second, unrelated hull.
	ship_anchor := game.Combat_Vec3 {
		f32(fleet_position[0] - view_origin[0]) * scale,
		f32(fleet_position[1] - view_origin[1]) * scale,
		f32(fleet_position[2] - view_origin[2]) * scale,
	}
	moving :=
		navigation.manual_active ||
		navigation.autopilot_active &&
			!navigation.paused_for_replan &&
			navigation.segment < navigation.course.waypoint_count - 1
	direction := game.Combat_Vec3{1, 0, 0}
	target_facing, target_pitch := s.dark_fleet_facing, s.dark_fleet_pitch
	if navigation.manual_active {
		dx, dy, dz :=
			f32(navigation.manual_velocity[0]),
			f32(navigation.manual_velocity[1]),
			f32(
				navigation.manual_velocity[2],
			); planar := f32(math.sqrt(f64(dx * dx + dy * dy))); visible_length := f32(math.sqrt(f64(dx * dx + dy * dy + dz * dz)))
		if visible_length >
		   .001 {target_facing = f32(math.atan2(f64(dy), f64(dx))); target_pitch = f32(math.atan2(f64(dz), f64(max(planar, .001))))}
	} else if moving {
		a :=
			navigation.course.waypoints[navigation.segment].position; b := navigation.course.waypoints[navigation.segment + 1].position
		dx, dy, dz :=
			f32(b[0] - a[0]),
			f32(b[1] - a[1]),
			f32(
				b[2] - a[2],
			); planar := f32(math.sqrt(f64(dx * dx + dy * dy))); visible_length := f32(math.sqrt(f64(dx * dx + dy * dy + dz * dz)))
		if visible_length >
		   .001 {target_facing = f32(math.atan2(f64(dy), f64(dx))); target_pitch = f32(math.atan2(f64(dz), f64(max(planar, .001))))}
	}
	facing, pitch, steering_bank := dark_fleet_visual_heading(
		s,
		target_facing,
		target_pitch,
		moving,
	)
	power_target := f32(.08)
	if navigation.manual_active do power_target = max(s.dark_fleet_power_command, .12)
	if navigation.autopilot_active && !navigation.paused_for_replan do power_target = .72
	power := dark_fleet_visual_power(s, power_target)
	cos_pitch := f32(math.cos(f64(pitch)))
	direction = {
		f32(math.cos(f64(facing))) * cos_pitch,
		f32(math.sin(f64(facing))) * cos_pitch,
		f32(math.sin(f64(pitch))),
	}
	visual_time := f32(continuum.simulation_time + continuum.accumulator)
	// Reserve up to two nearby correspondence throats before minor fields. Their
	// existing line rings remain labels; these toroids are the physical apertures.
	door_volumes := 0
	for door in continuum.doors[:continuum.door_count] {
		if door_volumes >= 2 do break
		section := dark_door_section_visibility(fleet_position[3], door.position[3], door.radius)
		if section <= .01 do continue
		position := game.Combat_Vec3 {
			f32(door.position[0] - view_origin[0]) * scale,
			f32(door.position[1] - view_origin[1]) * scale,
			f32(door.position[2] - view_origin[2]) * scale,
		}
		color := dark_door_section_color(fleet_position[3], door.position[3], info, good)
		radius := max(f32(door.radius) * scale * section, 28 * section)
		combat_3d_append_terrain_volume(
			position,
			radius * 1.28,
			radius * .56,
			DARK_VOLUME_DOOR_ALIGNMENT,
			f32(door.id % 16777216),
			.7,
			.5,
			{color[0], color[1], color[2], .18 + section * .54},
		)
		door_volumes += 1
	}
	combat_3d.terrain_volume_count = u32(
		len(combat_3d.terrain_instances),
	); combat_3d.terrain_lane_instance_first = combat_3d.terrain_volume_count; combat_3d.terrain_lane_instance_count = 0
	// The physical section is authoritative. Course confidence remains an
	// instrument reading in the UI instead of drawing a second, displaced copy
	// of the world over the laminae.
	combat_3d.terrain_survey_instance_first = u32(len(combat_3d.terrain_instances))
	combat_3d.terrain_survey_instance_count =
		u32(len(combat_3d.terrain_instances)) - combat_3d.terrain_survey_instance_first
	dark_append_course(
		s,
		continuum,
		&navigation.course,
		view_origin,
		scale,
		false,
		info,
		warn,
		committed,
	)
	dark_append_course(
		s,
		continuum,
		&s.dark_course_draft,
		view_origin,
		scale,
		true,
		info,
		warn,
		committed,
	)

	// The return bearing is deliberately subordinate until the route or a hold
	// makes recoverability actionable.
	_, exit_known := game.passage_propellant_to_fleet_exit(s.campaign, &s.campaign.passage)
	coherence_limit := game.passage_coherence_limit(&s.campaign.passage)
	grammar := dark_umbilical_grammar(
		exit_known,
		s.campaign.passage.coherence_exposure,
		coherence_limit,
		navigation.forecast.topology_confidence,
	)
	emphasized :=
		s.dark_course_draft.waypoint_count >= 2 ||
		s.campaign.passage.pause_reason == .Coherence_Limit ||
		s.campaign.passage.pause_reason == .Material_Obstruction
	umbilical_color :=
		grammar == .Unavailable ? [4]f32{.72, .31, .24, emphasized ? .82 : .28} : grammar == .Caution ? warn : [4]f32{dim[0], dim[1], dim[2], emphasized ? .60 : .18}
	dark_append_umbilical(ship_anchor, {}, grammar, umbilical_color)
	combat_3d.instance_first[3] = 0
	for door in continuum.doors[:continuum.door_count] {
		if len(combat_3d.instances) >= COMBAT_3D_MAX_INSTANCES do break
		section := dark_door_section_visibility(fleet_position[3], door.position[3], door.radius)
		if section <= .01 do continue
		position := [3]f32 {
			f32(door.position[0] - view_origin[0]) * scale,
			f32(door.position[1] - view_origin[1]) * scale,
			f32(door.position[2] - view_origin[2]) * scale,
		}
		color := dark_door_section_color(fleet_position[3], door.position[3], info, good)
		size := f32(door.radius) * scale * section
		append(
			&combat_3d.instances,
			Combat_3D_Instance {
				position,
				{1, 0, size, .18},
				{color[0], color[1], color[2], section * color[3]},
			},
		)
		combat_3d.instance_count[3] += 1
		combat_3d_append_ring(
			{position[0], position[1], position[2]},
			size,
			{color[0], color[1], color[2], section * .46},
			24,
		)
	}
	// Paired section ticks encode W independently of perspective depth.
	for track in navigation.tracker.tracks[:navigation.tracker.track_count] {
		estimated := game.dark_vec4_add(fleet_position, track.relative_bearing)
		p := game.Combat_Vec3 {
			f32(estimated[0] - view_origin[0]) * scale,
			f32(estimated[1] - view_origin[1]) * scale,
			f32(estimated[2] - view_origin[2]) * scale,
		}
		extent := max(
			f32(track.estimated_extent) * scale,
			20,
		); outward := track.relative_bearing[3] >= 0
		tick_color := track.confidence < .55 ? [4]f32{dim[0], dim[1], dim[2], .68} : info
		left_x, right_x := p.x - extent * 1.25, p.x + extent * 1.25
		gap :=
			f32(
				clamp(
					math.abs(track.relative_bearing[3]) / max(track.estimated_extent, .1),
					.15,
					1,
				),
			) *
			10
		if outward {
			combat_3d_append_line({left_x - gap, p.y - 5, p.z}, {left_x, p.y, p.z}, tick_color)
			combat_3d_append_line({right_x + gap, p.y + 5, p.z}, {right_x, p.y, p.z}, tick_color)
		} else {
			combat_3d_append_line({left_x, p.y, p.z}, {left_x + gap, p.y - 5, p.z}, tick_color)
			combat_3d_append_line({right_x, p.y, p.z}, {right_x - gap, p.y + 5, p.z}, tick_color)
		}
	}
	// The expedition is a small, mechanically legible 3D vessel rather
	// than a map token: axial keel, pressure hull rings, paired radiators, an
	// antenna mast, and narrow engine scatter all occupy world depth.
	ship_ink := [4]f32 {
		.96,
		.94,
		.86,
		1,
	}; engine_ink := [4]f32{info[0], info[1], info[2], .24 + power * .74}
	// Its anchor is the fleet's actual XYZ displacement from the entry point.
	// Ray-hit depth writes let orbiting carry it behind a lobe without forcing it
	// on top or pinning it to the camera.
	combat_3d.capture_glow = true
	for ship_id, ship_number in s.campaign.passage.ships[:s.campaign.passage.ship_count] {if ship_at := game.ship_index(s.campaign, ship_id); ship_at >= 0 {formation := combat_3d_formation_anchor(ship_anchor, facing, ship_number, s.campaign.passage.ship_count, 46); phase := visual_time * 1.15 + f32(ship_number) * 1.7; bank := f32(0); if !s.reduced_motion {formation.z += f32(math.sin(f64(phase))) * (moving ? 3.2 : .7); bank = f32(math.sin(f64(phase * .73))) * (moving ? .075 : .018) + steering_bank}; dark_append_recipe_ship(&s.campaign.ships[ship_at], formation, 3.15, facing, pitch, bank, power, ship_ink, engine_ink)}}
	combat_3d.capture_glow = false
	// The wake is a short material history in 3D space, not a motion streak.
	// Two separated filaments sag through depth and diverge slightly; sparse
	// pressure rings mark older engine pulses without becoming a route overlay.
	for segment in 0 ..< 7 {
		a := f32(
			segment,
		); b := a + 1; alpha := (moving ? .58 : .24) - a * (moving ? .058 : .024); trail_a := (42 + a * 18) * 1.35; trail_b := (42 + b * 18) * 1.35
		pa := game.Combat_Vec3 {
			ship_anchor.x - direction.x * trail_a,
			ship_anchor.y - direction.y * trail_a + f32(math.sin(f64(a * .72))) * 7,
			ship_anchor.z - direction.z * trail_a - a * a * .8,
		}
		pb := game.Combat_Vec3 {
			ship_anchor.x - direction.x * trail_b,
			ship_anchor.y - direction.y * trail_b + f32(math.sin(f64(b * .72))) * 7,
			ship_anchor.z - direction.z * trail_b - b * b * .8,
		}
		combat_3d_append_line(
			{pa.x, pa.y, pa.z},
			{pb.x, pb.y, pb.z},
			{info[0], info[1], info[2], alpha},
		)
		combat_3d_append_line(
			{pa.x, pa.y + 3 + a * .8, pa.z + 4},
			{pb.x, pb.y + 3 + b * .8, pb.z + 4},
			{info[0], info[1], info[2], alpha * .42},
		)
		if segment == 2 || segment == 5 do combat_3d_append_orbit(pb, 4 + b * 1.2, {info[0], info[1], info[2], alpha * .34}, segment % 3, 18)
	}
}

@(test)
dark_depth_presentation_helpers_are_deterministic_and_ordered :: proc(t: ^testing.T) {
	d := game.Dark_Continuum {
		seed            = 404,
		anchor_position = {},
	}
	course := game.Dark_Course {
		waypoint_count = 3,
	}
	course.waypoints[0].position = {}
	course.waypoints[1].position = {15, 0, 0, 2.5}
	course.waypoints[2].position = {35, 0, 0, 5}
	depth, index := dark_course_maximum_depth(&d, &course)
	testing.expect(t, depth > dark_render_depth(&d, course.waypoints[1].position))
	testing.expect_value(t, index, 2)
	first := dark_course_band_crossings(&d, &course, DARK_DEPTH_BAND_SPACING)
	second := dark_course_band_crossings(&d, &course, DARK_DEPTH_BAND_SPACING)
	testing.expect_value(t, first, second)
	testing.expect(t, first > 0)
}

@(test)
dark_return_grammar_prioritizes_unknown_then_uncertain_then_coherence :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		dark_umbilical_grammar(false, 0, 1, 1),
		Dark_Umbilical_Grammar.Unavailable,
	)
	testing.expect_value(
		t,
		dark_umbilical_grammar(true, 0, 1, .4),
		Dark_Umbilical_Grammar.Uncertain,
	)
	testing.expect_value(t, dark_umbilical_grammar(true, .8, 1, 1), Dark_Umbilical_Grammar.Caution)
	testing.expect_value(
		t,
		dark_umbilical_grammar(true, .2, 1, 1),
		Dark_Umbilical_Grammar.Continuous,
	)
}
