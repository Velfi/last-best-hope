package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:math"
import "core:mem"
import "core:os"
import "core:testing"
import "core:time"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"

dark_visual_angle_delta :: proc(from, to: f32) -> f32 {
	delta := to - from
	for delta > math.PI do delta -= 2 * math.PI
	for delta < -math.PI do delta += 2 * math.PI
	return delta
}

dark_visual_heading_step :: proc(current, target, max_step: f32) -> f32 {
	if max_step <= 0 do return current
	return current + clamp(dark_visual_angle_delta(current, target), -max_step, max_step)
}

dark_visual_power_step :: proc(current, target, elapsed: f32) -> f32 {
	rate := target > current ? f32(2.8) : f32(1.6)
	return clamp(current + clamp(target - current, -rate * elapsed, rate * elapsed), 0, 1)
}

dark_fleet_visual_power :: proc(s: ^Ux_State, target: f32) -> f32 {
	now := rl.GetTime()
	elapsed := f32(clamp(now - s.dark_fleet_power_time, f64(0), f64(.1)))
	if s.dark_fleet_power_time <= 0 do elapsed = 0
	s.dark_fleet_power_time = now
	if s.reduced_motion {
		s.dark_fleet_power = target
	} else {
		s.dark_fleet_power = dark_visual_power_step(s.dark_fleet_power, target, elapsed)
	}
	return s.dark_fleet_power
}

dark_fleet_visual_heading :: proc(
	s: ^Ux_State,
	target_facing, target_pitch: f32,
	moving: bool,
) -> (
	facing, pitch, turn: f32,
) {
	now := rl.GetTime()
	if !s.dark_fleet_heading_ready {
		s.dark_fleet_facing = target_facing
		s.dark_fleet_pitch = target_pitch
		s.dark_fleet_heading_ready = true
		s.dark_fleet_heading_time = now
		return target_facing, target_pitch, 0
	}
	elapsed := f32(clamp(now - s.dark_fleet_heading_time, f64(0), f64(.1)))
	s.dark_fleet_heading_time = now
	if !moving do return s.dark_fleet_facing, s.dark_fleet_pitch, 0
	if s.reduced_motion {
		s.dark_fleet_facing = target_facing
		s.dark_fleet_pitch = target_pitch
		return target_facing, target_pitch, 0
	}
	yaw_delta := dark_visual_angle_delta(s.dark_fleet_facing, target_facing)
	max_yaw := elapsed * 2.35
	max_pitch := elapsed * 1.8
	s.dark_fleet_facing = dark_visual_heading_step(s.dark_fleet_facing, target_facing, max_yaw)
	s.dark_fleet_pitch = dark_visual_heading_step(s.dark_fleet_pitch, target_pitch, max_pitch)
	return s.dark_fleet_facing, s.dark_fleet_pitch, clamp(yaw_delta / max(f32(math.PI), .001), -.32, .32)
}

@(test)
dark_visual_heading_uses_shortest_wrapped_turn :: proc(t: ^testing.T) {
	from := f32(math.PI - .05)
	to := f32(-math.PI + .05)
	next := dark_visual_heading_step(from, to, .04)
	testing.expect(t, dark_visual_angle_delta(from, next) > 0)
	testing.expect(t, math.abs(dark_visual_angle_delta(from, next) - .04) < 1e-5)
}

@(test)
dark_visual_heading_respects_turn_rate_and_converges :: proc(t: ^testing.T) {
	heading := f32(0)
	for _ in 0 ..< 4 do heading = dark_visual_heading_step(heading, 1, .2)
	testing.expect(t, math.abs(heading - .8) < 1e-5)
	heading = dark_visual_heading_step(heading, 1, .2)
	testing.expect(t, math.abs(heading - 1) < 1e-5)
}

@(test)
dark_visual_power_has_bounded_attack_and_slower_decay :: proc(t: ^testing.T) {
	testing.expect_value(t, dark_visual_power_step(0, 1, .1), f32(.28))
	testing.expect_value(t, dark_visual_power_step(1, 0, .1), f32(.84))
	testing.expect_value(t, dark_visual_power_step(.96, 1, .1), f32(1))
	testing.expect_value(t, dark_visual_power_step(.04, 0, .1), f32(0))
}

combat_3d_append_role_mark :: proc(u: ^game.Combat_Unit, size: f32, color: [4]f32) {
	switch u.role {
	case .Fighter:
		combat_3d_unit_line(u, -size, -size * .65, size, 0, color)
		combat_3d_unit_line(u, size, 0, -size, size * .65, color)
		combat_3d_unit_line(u, -size, size * .65, -size, -size * .65, color)
	case .Bomber:
		combat_3d_unit_line(u, -size, 0, 0, -size * .75, color)
		combat_3d_unit_line(u, 0, -size * .75, size, 0, color)
		combat_3d_unit_line(u, size, 0, 0, size * .75, color)
		combat_3d_unit_line(u, 0, size * .75, -size, 0, color)
		combat_3d_unit_line(u, -size * .3, -size * .45, size * .3, size * .45, color)
	case .Corvette:
		combat_3d_unit_line(u, -size, -size * .55, size * .45, -size * .55, color)
		combat_3d_unit_line(u, size * .45, -size * .55, size, 0, color)
		combat_3d_unit_line(u, size, 0, size * .45, size * .55, color)
		combat_3d_unit_line(u, size * .45, size * .55, -size, size * .55, color)
		combat_3d_unit_line(u, -size, size * .55, -size, -size * .55, color)
	case .Recovery:
		combat_3d_append_ring(u.position, size, color, 20)
		combat_3d_unit_line(u, -size * .55, 0, size * .55, 0, color)
		combat_3d_unit_line(u, 0, -size * .55, 0, size * .55, color)
	case .Carrier:
		combat_3d_unit_line(u, -size, -size * .5, size, -size * .5, color)
		combat_3d_unit_line(u, size, -size * .5, size, size * .5, color)
		combat_3d_unit_line(u, size, size * .5, -size, size * .5, color)
		combat_3d_unit_line(u, -size, size * .5, -size, -size * .5, color)
		combat_3d_unit_line(u, -size * .55, 0, size * .65, 0, color)
	case .Capital:
		combat_3d_unit_line(u, -size, -size * .45, size * .7, -size * .45, color)
		combat_3d_unit_line(u, size * .7, -size * .45, size, 0, color)
		combat_3d_unit_line(u, size, 0, size * .7, size * .45, color)
		combat_3d_unit_line(u, size * .7, size * .45, -size, size * .45, color)
		combat_3d_unit_line(u, -size, size * .45, -size, -size * .45, color)
		combat_3d_unit_line(u, -size * .65, -size * .18, size * .6, -size * .18, color)
		combat_3d_unit_line(u, -size * .65, size * .18, size * .6, size * .18, color)
	}
}

combat_3d_append_unit :: proc(u: ^game.Combat_Unit) {
	if u.extracted do return; color := [4]f32{.58, .68, .69, .9}; if u.side == .Raider do color = {.70, .37, .31, .9}; if u.disabled do color = {.38, .38, .35, .72}
	size := game.ship_tonnage_visual_scale(u.tonnage_each)
	combat_3d_append_hull_volume(u, size * 1.18, color)
	// The crisp six-role silhouette is GPU-instanced. A glow-only copy stays in
	// the sparse additive pass, while archetype and damage marks remain dynamic.
	combat_3d.capture_glow =
		true; combat_3d.glow_only = true; combat_3d_append_role_mark(u, size, color); combat_3d.glow_only = false
	// Archetype marks share the broad command-element silhouette above, then
	// add one readable role-specific feature. This keeps all 24 contacts distinct
	// in the depth-tested tactical volume without turning them into tiny ship art.
	switch u.hull_archetype {
	case .Scout:
		combat_3d_append_ring(u.position, size * .72, color, 14)
		combat_3d_unit_line(u, size * .25, 0, size * .5, 0, color)
	case .Interceptor:
		combat_3d_unit_line(u, -size * .1, -size, size * .35, -size * .6, color)
		combat_3d_unit_line(u, -size * .1, size, size * .35, size * .6, color)
	case .Fighter:
		combat_3d_unit_line(u, -size * .25, -size, size * .25, -size * .55, color)
		combat_3d_unit_line(u, -size * .25, size, size * .25, size * .55, color)
	case .Strike_Fighter:
		combat_3d_unit_line(u, -size * .25, -size, size * .25, -size * .55, color)
		combat_3d_unit_line(u, -size * .25, size, size * .25, size * .55, color)
		combat_3d_unit_line(u, size * .45, 0, size * .75, 0, color)
	case .Bomber:
		combat_3d_unit_line(u, size * .15, -size * .28, size * .5, -size * .28, color)
		combat_3d_unit_line(u, size * .15, size * .28, size * .5, size * .28, color)
	case .Assault_Shuttle:
		combat_3d_unit_line(u, -size * .15, -size * 1.05, size * .35, -size * 1.05, color)
		combat_3d_unit_line(u, -size * .15, size * 1.05, size * .35, size * 1.05, color)
	case .Patrol_Boat:
		combat_3d_append_ring(u.position, size * .8, color, 12)
	case .Corvette:
		combat_3d_unit_line(u, -size * .2, -size * .8, size * .2, -size * .8, color)
		combat_3d_unit_line(u, -size * .2, size * .8, size * .2, size * .8, color)
	case .Torpedo_Boat:
		combat_3d_unit_line(u, size * .25, 0, size * 1.35, 0, color)
	case .Gunship:
		combat_3d_unit_line(u, -size * .15, -size, size * .2, -size, color)
		combat_3d_unit_line(u, -size * .15, size, size * .2, size, color)
	case .Picket_Frigate:
		combat_3d_append_ring(u.position, size * 1.15, color, 18)
		combat_3d_unit_line(u, size * .35, 0, size * .55, 0, color)
	case .Combat_Frigate:
		combat_3d_unit_line(u, -size * .1, -size * .9, size * .3, -size * .9, color)
		combat_3d_unit_line(u, -size * .1, size * .9, size * .3, size * .9, color)
	case .Support_Frigate:
		combat_3d_unit_line(u, -size * .15, -size * .9, size * .25, -size * .9, color)
		combat_3d_unit_line(u, -size * .15, size * .9, size * .25, size * .9, color)
		combat_3d_unit_line(u, 0, -size * .25, 0, size * .25, color)
	case .Minelayer_Frigate:
		for mark in -1 ..= 1 do combat_3d_append_ring({u.position.x - size * .8, u.position.y + f32(mark) * size * .42, u.position.z}, size * .1, color, 6)
	case .Destroyer:
		for mark in -1 ..= 1 do combat_3d_unit_line(u, size * .2, f32(mark) * size * .25, size * .75, f32(mark) * size * .25, color)
	case .Light_Cruiser:
		combat_3d_unit_line(u, -size * .2, -size * .72, size * .25, -size * .72, color)
		combat_3d_unit_line(u, -size * .2, size * .72, size * .25, size * .72, color)
	case .Heavy_Cruiser:
		combat_3d_unit_line(u, -size * .7, -size * .7, size * .55, -size * .7, color)
		combat_3d_unit_line(u, -size * .7, size * .7, size * .55, size * .7, color)
	case .Battlecruiser:
		combat_3d_unit_line(u, size * .15, 0, size * 1.25, 0, color)
	case .Battleship:
		combat_3d_unit_line(u, -size * .5, -size * .72, size * .45, -size * .72, color)
		combat_3d_unit_line(u, -size * .5, size * .72, size * .45, size * .72, color)
		combat_3d_unit_line(u, -size * .45, 0, size * .65, 0, color)
	case .Carrier:
		combat_3d_unit_line(u, -size * .65, -size * .22, size * .6, -size * .22, color)
		combat_3d_unit_line(u, -size * .65, size * .22, size * .6, size * .22, color)
		for mark in -1 ..= 1 do combat_3d_append_ring({u.position.x, u.position.y + f32(mark) * size * .32, u.position.z}, size * .07, color, 6)
	case .Dreadnought:
		combat_3d_append_ring(u.position, size * 1.12, color, 8)
		combat_3d_append_ring(u.position, size * .88, color, 8)
	case .Utility_Hull:
		combat_3d_unit_line(u, -size * .25, -size * .95, size * .25, -size * .95, color)
		combat_3d_unit_line(u, -size * .25, size * .95, size * .25, size * .95, color)
	case .Transport_Hull:
		for mark in -1 ..= 1 do combat_3d_unit_line(u, -size * .3, f32(mark) * size * .35, size * .35, f32(mark) * size * .35, color)
	case .Habitat_Hull:
		combat_3d_append_ring(u.position, size * .5, color, 18)
		combat_3d_unit_line(u, -size * .25, -size, 0, -size * .72, color)
		combat_3d_unit_line(u, -size * .25, size, 0, size * .72, color)
	case .Unspecified:
	}
	combat_3d.capture_glow = false
	stem := [4]f32 {
		color[0],
		color[1],
		color[2],
		.35,
	}; combat_3d_append_line({u.position.x, u.position.y, COMBAT_GRID_Z}, {u.position.x, u.position.y, u.position.z}, stem)
	speed := f32(
		math.sqrt(
			f64(
				u.velocity.x * u.velocity.x +
				u.velocity.y * u.velocity.y +
				u.velocity.z * u.velocity.z,
			),
		),
	); if speed > 1 && !u.disabled {length := clamp(speed * .12, 7, 24); trail := [4]f32{color[0], color[1], color[2], u.selected ? .55 : .28}; combat_3d_append_line({u.position.x - u.velocity.x / speed * length, u.position.y - u.velocity.y / speed * length, u.position.z - u.velocity.z / speed * length}, {u.position.x, u.position.y, u.position.z}, trail)}
	if u.max_hull >
	   0 {damage_ratio := clamp(1 - u.hull / u.max_hull, 0, 1); fractures := int(damage_ratio * 4); for fracture in 0 ..< fractures {offset := (f32(fracture) - f32(fractures - 1) * .5) * size * .24; combat_3d_unit_line(u, -size * .55, offset - size * .18, size * .48, offset + size * .18, {.86, .84, .76, .72})}}
	if u.selected {combat_3d_append_ring(u.position, size * 1.45, {.86, .84, .76, .95}, 24); destination_color := [4]f32{.58, .68, .69, .5}; destination := u.tactical_destination; if destination == {} do destination = u.destination; combat_3d_append_line({u.position.x, u.position.y, u.position.z}, {destination.x, destination.y, destination.z}, destination_color)}
	if u.selected do combat_3d_append_ring(u.position, game.combat_weapon_range(u^, game.combat_weapon_class(u^, false)), {color[0], color[1], color[2], .24}, 48)
	if u.disabled {combat_3d_unit_line(u, -size * .65, -size * .65, size * .65, size * .65, color); combat_3d_unit_line(u, -size * .65, size * .65, size * .65, -size * .65, color)}
}

combat_3d_append_impact_flash :: proc(u: ^game.Combat_Unit) {
	if u.impact_flash <= 0 do return
	energy := clamp(u.impact_flash / .45, 0, 1)
	size := game.ship_tonnage_visual_scale(u.tonnage_each)
	core := size * (.7 + energy * 1.35)
	ring := size * (2.2 + energy * 1.7)
	// Values above one are intentional radiance in the floating-point scene
	// target. The presentation pass tone-maps the core and blooms its halo.
	color := [4]f32{1.2 + energy * 2.8, 1.05 + energy * 1.75, .72 + energy * .58, .96}
	combat_3d.capture_glow = true
	combat_3d_append_line(
		{u.position.x - core, u.position.y, u.position.z},
		{u.position.x + core, u.position.y, u.position.z},
		color,
	)
	combat_3d_append_line(
		{u.position.x, u.position.y - core, u.position.z},
		{u.position.x, u.position.y + core, u.position.z},
		color,
	)
	combat_3d_append_line(
		{u.position.x, u.position.y, u.position.z - core},
		{u.position.x, u.position.y, u.position.z + core},
		color,
	)
	// Unequal debris rays keep the flash from reading as another targeting glyph.
	combat_3d_append_line(
		{u.position.x - core * .55, u.position.y - core * .42, u.position.z},
		{u.position.x + core * 2.8, u.position.y + core * 2.15, u.position.z},
		color,
	)
	combat_3d_append_line(
		{u.position.x - core * 1.9, u.position.y + core * 1.35, u.position.z + core * .2},
		{u.position.x + core * .45, u.position.y - core * .32, u.position.z - core * .2},
		color,
	)
	combat_3d_append_orbit(u.position, ring, color, 0, 16)
	combat_3d_append_orbit(u.position, ring * .82, color, 1, 12)
	combat_3d.capture_glow = false
}

combat_3d_display_unit :: proc(s: ^Ux_State, index: int) -> (game.Combat_Unit, bool) {
	u := s.combat.units[index]
	if u.extracted do return u, false
	if u.side == .Friendly do return u, true
	position, visible := game.combat_contact_position(&s.combat, .Friendly, index)
	if !visible do return u, false
	trace := game.combat_contact_trace(&s.combat, .Friendly, index); u.position = position
	// Unidentified and old reports use a neutral mark and never leak true heading.
	if trace.identity != .Identified ||
	   trace.liveness ==
		   .Stale {u.facing = 0; u.hull_archetype = .Unspecified; u.operational_role = .Unspecified; u.role = .Corvette}
	if trace.assessment != .Confirmed_Disabled do u.disabled = false
	return u, true
}

combat_3d_append_debris_plates :: proc(
	seed: u64,
	center: game.Combat_Vec3,
	radius: f32,
) {
	// Presentation-only wreckage: broad terrain fragments supply the black
	// shadow archipelago beneath these marks. Torn contours, ribs, and localized
	// hatching identify a few fragments as ruined hull rather than wireframe
	// targeting glyphs.
	for i in 0 ..< 96 {
		hash := game.combat_mix(seed + u64(i + 1) * 0x9e3779b97f4a7c15)
		cluster := i % 5
		angle :=
			f32(cluster) / 5 * 2 * math.PI +
			(f32((hash >> 48) & 0xffff) / 65535 - .5) * .72
		radial := (.12 + f32((hash >> 16) & 0xffff) / 65535 * .88) * radius
		height := (f32((hash >> 32) & 0xffff) / 65535 - .5) * 96
		p := game.Combat_Vec3{
			center.x + f32(math.cos(f64(angle))) * radial,
			center.y + f32(math.sin(f64(angle))) * radial,
			center.z + height,
		}
		heading := f32(hash & 0xffff) / 65535 * 2 * math.PI
		length := 9 + f32((hash >> 8) & 0xff) / 255 * (i < 24 ? 52 : 24)
		dx := f32(math.cos(f64(heading))) * length
		dy := f32(math.sin(f64(heading))) * length
		dz := (f32((hash >> 40) & 0xff) / 255 - .5) * length * .55
		if i >= 18 {
			// Minor ribs and slivers keep the corridor's directional flow.
			combat_3d_append_line(
				{p.x - dx, p.y - dy, p.z - dz},
				{p.x + dx, p.y + dy, p.z + dz},
				{.66, .63, .56, .58},
			)
			continue
		}

		// Major fragments use a chipped six-point hull contour. The unequal
		// shoulders and bitten starboard edge prevent a reusable triangle from
		// emerging at tactical scale.
		forward_x := f32(math.cos(f64(heading)))
		forward_y := f32(math.sin(f64(heading)))
		side_x := -forward_y
		side_y := forward_x
		half_length := length
		half_width := length * (.28 + f32((hash >> 24) & 0xff) / 255 * .22)
		tilt := dz * .72
		p0 := [3]f32{p.x-forward_x*half_length+side_x*half_width*.10, p.y-forward_y*half_length+side_y*half_width*.10, p.z-tilt}
		p1 := [3]f32{p.x-forward_x*half_length*.42-side_x*half_width*.82, p.y-forward_y*half_length*.42-side_y*half_width*.82, p.z-tilt*.38}
		p2 := [3]f32{p.x+forward_x*half_length*.08-side_x*half_width*.43, p.y+forward_y*half_length*.08-side_y*half_width*.43, p.z+tilt*.08}
		p3 := [3]f32{p.x+forward_x*half_length-side_x*half_width*.18, p.y+forward_y*half_length-side_y*half_width*.18, p.z+tilt}
		p4 := [3]f32{p.x+forward_x*half_length*.52+side_x*half_width*.74, p.y+forward_y*half_length*.52+side_y*half_width*.74, p.z+tilt*.46}
		p5 := [3]f32{p.x-forward_x*half_length*.28+side_x*half_width*.61, p.y-forward_y*half_length*.28+side_y*half_width*.61, p.z-tilt*.22}
		rim := [4]f32{.88, .84, .74, .86}
		combat_3d_append_line(p0,p1,rim)
		combat_3d_append_line(p1,p2,rim)
		combat_3d_append_line(p2,p3,rim)
		combat_3d_append_line(p3,p4,rim)
		combat_3d_append_line(p4,p5,rim)
		combat_3d_append_line(p5,p0,rim)

		// Near-black cross-strokes visually join the contour to the filled
		// wreckage volume. Their variable width leaves torn bites at both edges.
		for stroke in 0 ..< 7 {
			t := (f32(stroke) + .5) / 7
			longitudinal := (t * 2 - 1) * half_length * .72
			stroke_hash := game.combat_mix(hash + u64(stroke + 1) * 0x517cc1b727220a95)
			width_scale := .48 + f32(stroke_hash & 0xff) / 255 * .38
			cx := p.x + forward_x * longitudinal
			cy := p.y + forward_y * longitudinal
			cz := p.z + tilt * (t * 2 - 1) * .72
			combat_3d_append_line(
				{cx-side_x*half_width*width_scale, cy-side_y*half_width*width_scale, cz},
				{cx+side_x*half_width*width_scale, cy+side_y*half_width*width_scale, cz},
				{.08, .075, .065, .94},
			)
		}

		// Localized burin cuts stop short of the silhouette, reading as plating
		// scars and exposed ribs rather than a uniformly hatched icon.
		for cut in 0 ..< 3 {
			t := (f32(cut) + 1) / 4
			cx := p.x + forward_x * ((t * 2 - 1) * half_length * .46)
			cy := p.y + forward_y * ((t * 2 - 1) * half_length * .46)
			cz := p.z + tilt * (t * 2 - 1) * .42
			combat_3d_append_line(
				{cx-side_x*half_width*.38, cy-side_y*half_width*.38, cz},
				{cx+side_x*half_width*.18+forward_x*half_length*.16, cy+side_y*half_width*.18+forward_y*half_length*.16, cz+tilt*.10},
				{.93, .90, .82, .68},
			)
		}
	}
}

combat_3d_build_reference :: proc(s: ^Ux_State) {
	resize(
		&combat_3d.vertices,
		0,
	); resize(&combat_3d.glow_vertices, 0); resize(&combat_3d.instances, 0); resize(&combat_3d.terrain_instances, 0); resize(&combat_3d.nebula_instances, 0); combat_3d.terrain_volume_count = 0; combat_3d.terrain_lane_instance_first = 0; combat_3d.terrain_lane_instance_count = 0; combat_3d.creature_gene_count = 0; combat_3d.creature_visible_count = 0; combat_3d.capture_glow = false; combat_3d.glow_only = false; minor := [4]f32{.34, .39, .39, .32}; major := [4]f32{.62, .72, .73, .58}
	grid :=
		s.combat.grid; cell_x := (grid.max_x - grid.min_x) / f32(game.COMBAT_SECTOR_ROWS); cell_y := (grid.max_y - grid.min_y) / f32(game.COMBAT_SECTOR_COLUMNS)
	// Temporary deterministic fixture for evaluating the standalone cheap
	// nebula shader in the real combat camera.  Several modest lobes build two
	// asymmetric cloud towers; no single proxy is large enough to disclose its
	// ellipsoid silhouette, and the central fire lane remains readable.
	nebula_seed := f32(s.combat.seed % 16777216)
	append(&combat_3d.nebula_instances,
		// Upper-left tower: a heavy base, a rising crown, and two torn shoulders.
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*1.45, grid.min_y+cell_y*2.00, -210}, {330, 205, 240, 2.45}, {nebula_seed+11, .78, 1.38, .46}, {.42, .45, .44}},
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*2.05, grid.min_y+cell_y*2.52, -145}, {290, 245, 275, 2.25}, {nebula_seed+23, .96, 1.52, .43}, {.47, .49, .48}},
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*2.72, grid.min_y+cell_y*2.18, -80}, {265, 165, 205, 2.60}, {nebula_seed+37, .71, 1.45, .40}, {.38, .41, .40}},
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*2.10, grid.min_y+cell_y*3.27, -25}, {215, 225, 190, 2.35}, {nebula_seed+49, 1.12, 1.62, .38}, {.50, .51, .49}},
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*3.18, grid.min_y+cell_y*2.75, 25}, {235, 150, 225, 2.15}, {nebula_seed+61, .86, 1.48, .36}, {.43, .46, .45}},
		// Lower-right tower: broader at its base with a hooked, broken crest.
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*4.25, grid.min_y+cell_y*3.95, -120}, {350, 210, 265, 2.35}, {nebula_seed+73, .74, 1.42, .44}, {.40, .43, .42}},
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*4.92, grid.min_y+cell_y*4.48, -45}, {300, 240, 245, 2.55}, {nebula_seed+87, 1.04, 1.58, .43}, {.48, .50, .48}},
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*5.52, grid.min_y+cell_y*3.92, 35}, {245, 175, 210, 2.30}, {nebula_seed+101, .82, 1.50, .38}, {.39, .42, .41}},
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*4.46, grid.min_y+cell_y*5.18, 85}, {225, 250, 235, 2.45}, {nebula_seed+113, 1.16, 1.68, .37}, {.51, .52, .50}},
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*5.63, grid.min_y+cell_y*4.93, 145}, {260, 170, 220, 2.20}, {nebula_seed+127, .68, 1.54, .35}, {.44, .46, .45}},
		// One faint bridge implies a continuous storm without closing the lane.
		Combat_3D_Nebula_Instance{{grid.min_x+cell_x*3.55, grid.min_y+cell_y*3.37, 180}, {250, 125, 185, 1.85}, {nebula_seed+139, .92, 1.30, .27}, {.37, .40, .39}},
	)
	for row in 0 ..= game.COMBAT_SECTOR_ROWS {x := grid.min_x + f32(row) * cell_x; color := row == 0 || row == game.COMBAT_SECTOR_ROWS ? major : minor; combat_3d_append_line({x, grid.min_y, COMBAT_GRID_Z}, {x, grid.max_y, COMBAT_GRID_Z}, color)}
	for column in 0 ..= game.COMBAT_SECTOR_COLUMNS {y := grid.min_y + f32(column) * cell_y; color := column == 0 || column == game.COMBAT_SECTOR_COLUMNS ? major : minor; combat_3d_append_line({grid.min_x, y, COMBAT_GRID_Z}, {grid.max_x, y, COMBAT_GRID_Z}, color)}
	info := [4]f32 {
		.58,
		.68,
		.69,
		.82,
	}; good := [4]f32{.45, .61, .42, .82}; warn := [4]f32{.69, .58, .35, .82}; committed := [4]f32{.56, .45, .67, .82}
	debris :=
		s.combat.terrain[0]; lane := s.combat.terrain[1]; radiation := s.combat.terrain[2]; combat_3d_append_ring(lane.center, lane.radius, {.58, .68, .69, .24}, 48); combat_3d_append_volume(radiation.center, radiation.radius, 90, {.70, .37, .31, .32})
	terrain_seed := f32(
		s.combat.seed % 16777216,
	); combat_3d_append_terrain_volume(debris.center, debris.radius, 55, 0, terrain_seed, 3.8, .34, {.31, .30, .27, .14}); combat_3d_append_terrain_volume(radiation.center, radiation.radius, 90, 1, terrain_seed + 37, 2.7, .24, {.70, .37, .31, .072})
	for field, field_index in s.combat.wreckage_fields[:s.combat.wreckage_field_count] {combat_3d_append_volume(field.center, field.radius, 22, {.38, .38, .35, .24}); combat_3d_append_terrain_volume(field.center, field.radius, 22, 0, terrain_seed + f32(field_index) * 19, 3.2, .22, {.38, .38, .35, .065})}
	// Contacts carry a faceted translucent hull beneath their engraved role
	// mark. At sector scale this is the primary depth cue: a genuine ellipsoid
	// with visible top/side facets, not a screen-space sprite.
	for _, i in s.combat.units[:s.combat.unit_count] {
		u, visible := combat_3d_display_unit(s, i); if !visible do continue
		size :=
			game.ship_tonnage_visual_scale(u.tonnage_each) *
			1.35; color := [4]f32{.58, .68, .69, .20}; if u.side == .Raider do color = {.70, .37, .31, .22}; if u.disabled do color = {.38, .38, .35, .16}
		combat_3d_append_terrain_volume(
			u.position,
			size,
			size * .62,
			0,
			terrain_seed + 211 + f32(i) * 13,
			2.0,
			.78,
			color,
		)
	}
	combat_3d.terrain_volume_count = u32(
		len(combat_3d.terrain_instances),
	); combat_3d_sort_terrain_volumes(s); combat_3d.terrain_lane_instance_first = u32(len(combat_3d.terrain_instances)); combat_3d_append_lane_decal(lane.center, lane.radius, terrain_seed + 73, {.58, .68, .69, .055}); combat_3d.terrain_lane_instance_count = u32(len(combat_3d.terrain_instances)) - combat_3d.terrain_lane_instance_first
	combat_3d_append_debris_plates(s.combat.seed, debris.center, debris.radius)
	for field, field_index in s.combat.wreckage_fields[:s.combat.wreckage_field_count] {
		combat_3d_append_volume(
			field.center,
			field.radius,
			field.radius * .38,
			{.50, .48, .43, .38},
		)
		marks := min(
			field.friendly_ships + field.raider_ships,
			24,
		); for mark in 0 ..< marks {hash := game.combat_mix(s.combat.seed + u64(field_index + 1) * 0x517cc1b727220a95 + u64(mark) * 0x9e3779b97f4a7c15); angle := f32(hash & 0xffff) / 65535 * 2 * math.PI; radial := f32((hash >> 16) & 0xffff) / 65535 * field.radius; height := (f32((hash >> 32) & 0xffff) / 65535 - .5) * field.radius * .7; p := game.Combat_Vec3{field.center.x + f32(math.cos(f64(angle))) * radial, field.center.y + f32(math.sin(f64(angle))) * radial, field.center.z + height}; combat_3d_append_line({p.x - 5, p.y - 2, p.z}, {p.x + 5, p.y + 2, p.z}, {.50, .48, .43, .62})}
	}
	for relay in s.combat.relays {combat_3d_append_ring(relay, 34, {info[0], info[1], info[2], .08}, 28); combat_3d_append_ring(relay, 30, {info[0], info[1], info[2], .14}, 28); combat_3d_append_ring(relay, 28, info, 28); combat_3d_append_line({relay.x, relay.y, COMBAT_GRID_Z}, {relay.x, relay.y, relay.z}, info)}
	combat_3d_append_ring(
		s.combat.extraction,
		39,
		{good[0], good[1], good[2], .08},
		28,
	); combat_3d_append_ring(s.combat.extraction, 35, {good[0], good[1], good[2], .14}, 28); combat_3d_append_ring(s.combat.extraction, 32, good, 28); combat_3d_append_line({s.combat.extraction.x, s.combat.extraction.y, COMBAT_GRID_Z}, {s.combat.extraction.x, s.combat.extraction.y, s.combat.extraction.z}, good)
	combat_3d_append_ring(
		s.combat.anomaly,
		43,
		{committed[0], committed[1], committed[2], .08},
		28,
	); combat_3d_append_ring(s.combat.anomaly, 39, {committed[0], committed[1], committed[2], .14}, 28); combat_3d_append_ring(s.combat.anomaly, 36, committed, 28); combat_3d_append_line({s.combat.anomaly.x, s.combat.anomaly.y, COMBAT_GRID_Z}, {s.combat.anomaly.x, s.combat.anomaly.y, s.combat.anomaly.z}, committed)
	if s.combat.seedship_found {combat_3d_append_ring(s.combat.seedship, 41, {warn[0], warn[1], warn[2], .08}, 28); combat_3d_append_ring(s.combat.seedship, 37, {warn[0], warn[1], warn[2], .14}, 28); combat_3d_append_ring(s.combat.seedship, 34, warn, 28); combat_3d_append_line({s.combat.seedship.x, s.combat.seedship.y, COMBAT_GRID_Z}, {s.combat.seedship.x, s.combat.seedship.y, s.combat.seedship.z}, warn)}
	for role in 0 ..< 6 {
		combat_3d.instance_first[role] = u32(
			len(combat_3d.instances),
		); combat_3d.instance_count[role] = 0
		for _, i in s.combat.units[:s.combat.unit_count] {u, visible := combat_3d_display_unit(s, i); if !visible || combat_3d_role_index(u.role) != role || !combat_3d_unit_uses_contact_glyph(s, i) do continue; color := [4]f32{.58, .68, .69, .9}; if u.side == .Raider {trace := game.combat_contact_trace(&s.combat, .Friendly, i); alpha: f32 = trace.liveness == .Stale ? .34 : trace.liveness == .Aging ? .62 : .9; color = {.70, .37, .31, alpha}}; if u.disabled do color = {.38, .38, .35, .72}; size := game.ship_tonnage_visual_scale(u.tonnage_each); append(&combat_3d.instances, Combat_3D_Instance{{u.position.x, u.position.y, u.position.z}, {f32(math.cos(f64(u.facing))), f32(math.sin(f64(u.facing))), size, .32}, color}); combat_3d.instance_count[role] += 1}
	}
	// Capture fixtures exercise tactical silhouettes, depth, effects, and
	// environmental compositing. Rebuilding every close-detail procedural ship
	// face on all fourteen capture frames dominates the main thread and can
	// exceed gigabytes of transient allocations; the ordinary game path still
	// retains the full persistent-ship renderer.
	capture_fixture := false
	if len(os.args) >= 2 {
		switch os.args[1] {
		case "--capture-combat", "--capture-combat-stress", "--capture-combat-finale",
		     "--capture-combat-late", "--capture-combat-result":
			capture_fixture = true
		}
	}
	if !capture_fixture do combat_3d_append_procedural_fleet(s)
	for _, i in s.combat.units[:s.combat.unit_count] {u, visible := combat_3d_display_unit(s, i); if !visible do continue; combat_3d_append_unit(&u); combat_3d_append_impact_flash(&u); if u.target >= 0 && u.target < s.combat.unit_count && !s.combat.units[u.target].disabled && (u.weapon_flash > 0 || u.action == .Attack_Run || u.selected && u.order == .Attack) {target, target_visible := game.combat_contact_position(&s.combat, .Friendly, u.target); if u.side == .Raider do target, target_visible = game.combat_contact_position(&s.combat, .Raider, u.target); if target_visible {beam := u.weapon_flash > 0 ? warn : (u.side == .Friendly ? info : [4]f32{.70, .37, .31, .62}); combat_3d_append_line({u.position.x, u.position.y, u.position.z}, {target.x, target.y, target.z}, beam); phase := f32(math.mod(f64(s.combat.time * .72 + f32(i) * .173), 1)); packet := game.Combat_Vec3{u.position.x + (target.x - u.position.x) * phase, u.position.y + (target.y - u.position.y) * phase, u.position.z + (target.z - u.position.z) * phase}; combat_3d_append_sphere(packet, 4, u.weapon_flash > 0 ? [4]f32{.9, .88, .78, .95} : beam)}}}
	for salvo in s.combat.salvos {if !salvo.active do continue; color := salvo.side == .Friendly ? warn : [4]f32{.70, .37, .31, .82}; combat_3d_append_line({salvo.position.x, salvo.position.y, salvo.position.z}, {salvo.target_volume.x, salvo.target_volume.y, salvo.target_volume.z}, {color[0], color[1], color[2], .35}); combat_3d_append_sphere(salvo.position, 8, color)}
	if s.combat_order_armed &&
	   (s.combat_order_drag_active ||
			   rl.CheckCollisionPointRec(
				   ux_mouse,
				   COMBAT_VIEWPORT,
			   )) {destination := s.combat_order_drag_active ? s.combat_order_drag_world : combat_3d_point_on_plane(s, ux_mouse, s.combat_altitude); if s.combat_order_drag_active do destination.z = s.combat_altitude; preview := [4]f32{.58, .68, .69, .68}; combat_3d_append_line({destination.x, destination.y, COMBAT_GRID_Z}, {destination.x, destination.y, destination.z}, preview); combat_3d_append_ring({destination.x, destination.y, COMBAT_GRID_Z}, 10, {preview[0], preview[1], preview[2], .34}, 18); combat_3d_append_ring(destination, 16, preview, 20); count := 0; for u in s.combat.units[:s.combat.friendly_count] do if u.selected do count += 1; slot := 0; for u in s.combat.units[:s.combat.friendly_count] do if u.selected {ghost := destination; if count > 1 {ghost.x += f32(slot - (count - 1) / 2) * 32; ghost.z += f32((slot % 2) * 2 - 1) * 10}; combat_3d_append_line({u.position.x, u.position.y, u.position.z}, {ghost.x, ghost.y, ghost.z}, {preview[0], preview[1], preview[2], .52}); combat_3d_append_volume(ghost, 7, 4, {preview[0], preview[1], preview[2], .58}); slot += 1}}
	if s.combat.ability_pending || s.combat.ability_flash > 0 do combat_3d_append_sphere(s.combat.ability_target, 85, s.combat.ability_pending ? warn : [4]f32{.70, .37, .31, .82})
	if s.combat_ability_armed {target := combat_3d_point_on_plane(s, ux_mouse, s.combat_altitude); combat_3d_append_sphere(target, 85, warn)}
	if s.combat.scenario ==
	   .Finale {asset := &s.combat.strategic_asset; asset_color := asset.disabled ? [4]f32{.38, .38, .35, .72} : asset.exposure_remaining > 0 ? committed : [4]f32{.70, .37, .31, .9}; combat_3d_append_sphere(asset.position, asset.disabled ? 22 : 42, asset_color); if asset.locked || asset.beam_flash > 0 do combat_3d_append_line({asset.position.x, asset.position.y, asset.position.z}, {asset.beam_aim.x, asset.beam_aim.y, asset.beam_aim.z}, asset.beam_flash > 0 ? [4]f32{.9, .88, .78, .95} : warn)}
}

dark_ship_basis :: proc(module: game.Procedural_Ship_Placement) -> (axis, side, up: [3]f32) {
	axis, side, up = {1, 0, 0}, {0, 1, 0}, {0, 0, 1}
	if module.module == .Antenna {
		up =
			module.direction; length := f32(math.sqrt(f64(up[0] * up[0] + up[1] * up[1] + up[2] * up[2])))
		if length > .001 {for &v in up do v /= length} else {up = {0, 0, 1}}
		reference := [3]f32{1, 0, 0}; if math.abs(up[0]) > .9 do reference = {0, 1, 0}
		dot := reference[0] * up[0] + reference[1] * up[1] + reference[2] * up[2]
		axis = {reference[0] - up[0] * dot, reference[1] - up[1] * dot, reference[2] - up[2] * dot}
		length = f32(
			math.sqrt(f64(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2])),
		); for &v in axis do v /= length
		side = {
			up[1] * axis[2] - up[2] * axis[1],
			up[2] * axis[0] - up[0] * axis[2],
			up[0] * axis[1] - up[1] * axis[0],
		}; return
	}
	mounted :=
		module.module == .Truss ||
		module.module == .Armor ||
		module.module == .Pressure_Hull ||
		module.module == .Tank ||
		module.module == .Radiator ||
		module.module == .Mission ||
		module.module == .Dock
	if !mounted do return
	axis =
		module.direction; length := f32(math.sqrt(f64(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2])))
	if length > .001 {for &v in axis do v /= length} else {axis = {1, 0, 0}}
	reference := [3]f32{0, 0, 1}; if math.abs(axis[2]) > .9 do reference = {0, 1, 0}
	side = {
		reference[1] * axis[2] - reference[2] * axis[1],
		reference[2] * axis[0] - reference[0] * axis[2],
		reference[0] * axis[1] - reference[1] * axis[0],
	}
	length = f32(
		math.sqrt(f64(side[0] * side[0] + side[1] * side[1] + side[2] * side[2])),
	); for &v in side do v /= length
	up = {
		axis[1] * side[2] - axis[2] * side[1],
		axis[2] * side[0] - axis[0] * side[2],
		axis[0] * side[1] - axis[1] * side[0],
	}; return
}

dark_ship_point :: proc(
	module: game.Procedural_Ship_Placement,
	local: [3]f32,
	anchor: game.Combat_Vec3,
	visual_scale, facing, pitch, bank: f32,
) -> [3]f32 {
	axis, side, up := dark_ship_basis(module); origin := module.position
	if module.module ==
	   .Antenna {for i in 0 ..< 3 do origin[i] += up[i] * module.scale[2]} else if module.module != .Truss && math.abs(axis[0] - 1) + math.abs(axis[1]) + math.abs(axis[2]) > .001 {for i in 0 ..< 3 do origin[i] += axis[i] * module.scale[0]}
	x := (origin[0] + axis[0] * local[0] + side[0] * local[1] + up[0] * local[2]) * visual_scale
	y := (origin[1] + axis[1] * local[0] + side[1] * local[1] + up[1] * local[2]) * visual_scale
	z := (origin[2] + axis[2] * local[0] + side[2] * local[1] + up[2] * local[2]) * visual_scale
	cp, sp :=
		f32(math.cos(f64(pitch))),
		f32(math.sin(f64(pitch))); cb, sb := f32(math.cos(f64(bank))), f32(math.sin(f64(bank)))
	px, pitched_z :=
		x * cp +
		z * sp,
		-x * sp +
		z * cp; py, pz := y * cb - pitched_z * sb, y * sb + pitched_z * cb
	c, s := f32(math.cos(f64(facing))), f32(math.sin(f64(facing)))
	return {anchor.x + px * c - py * s, anchor.y + px * s + py * c, anchor.z + pz}
}
