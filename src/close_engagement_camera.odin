package main

import game "../packages/game"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

COMBAT_VIEW_SCALE :: f32(.38)
COMBAT_ZOOM_MIN :: f32(.65)
COMBAT_ZOOM_MAX :: f32(4)
COMBAT_MIN_PLANE_FACING :: f32(.20)
COMBAT_KEY_ORBIT_SPEED :: f32(.025)
Combat_Quat :: struct {
	x, y, z, w: f32,
}
COMBAT_GRID_Z :: f32(-140)
COMBAT_VIEWPORT :: rl.Rectangle{205, 72, 795, 548}
combat_quat_mul :: proc(a, b: Combat_Quat) -> Combat_Quat {return{
		a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
		a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
	}}
combat_quat_normalize :: proc(q: Combat_Quat) -> Combat_Quat {n := f32(
		math.sqrt(f64(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)),
	)
	if n < .0001 do return {0, 0, 0, 1}
	return{q.x / n, q.y / n, q.z / n, q.w / n}}
combat_quat_axis :: proc(axis: game.Combat_Vec3, angle: f32) -> Combat_Quat {half := angle * .5
	s := f32(math.sin(f64(half)))
	return combat_quat_normalize({axis.x * s, axis.y * s, axis.z * s, f32(math.cos(f64(half)))})}
combat_quat_rotate :: proc(q: Combat_Quat, v: game.Combat_Vec3) -> game.Combat_Vec3 {tx :=
		2 * (q.y * v.z - q.z * v.y)
	ty := 2 * (q.z * v.x - q.x * v.z)
	tz := 2 * (q.x * v.y - q.y * v.x)
	return{
		v.x + q.w * tx + (q.y * tz - q.z * ty),
		v.y + q.w * ty + (q.z * tx - q.x * tz),
		v.z + q.w * tz + (q.x * ty - q.y * tx),
	}}
combat_quat_inverse_rotate :: proc(
	q: Combat_Quat,
	v: game.Combat_Vec3,
) -> game.Combat_Vec3 {return combat_quat_rotate({-q.x, -q.y, -q.z, q.w}, v)}
combat_default_orientation :: proc() -> Combat_Quat {
	// The negative pitch places the observer four units above the command plane
	// for every three units across. Positive Z therefore rises toward camera.
	elevation := -f32(
		math.atan2(f64(4), f64(3)),
	); return combat_quat_mul(combat_quat_axis({1, 0, 0}, elevation), combat_quat_axis({0, 0, 1}, -.35))
}
combat_orbit :: proc(s: ^Ux_State, dx, dy: f32) {
	// Yaw about galactic up so horizontal orbit never rolls the command plane.
	// Pitch is screen-relative, but may not carry the camera through the plane or
	// close enough to edge-on that pointer rays and cursor-anchored zoom explode.
	yaw := combat_quat_axis({0, 0, 1}, dx); pitch := combat_quat_axis({1, 0, 0}, dy)
	candidate := combat_quat_normalize(
		combat_quat_mul(pitch, combat_quat_mul(s.combat_orientation, yaw)),
	)
	plane_normal := combat_quat_rotate(candidate, {0, 0, 1})
	if plane_normal.z >= COMBAT_MIN_PLANE_FACING do s.combat_orientation = candidate
}

combat_clamp_pan :: proc(s: ^Ux_State) {
	grid := s.combat.grid
	world_limit :=
		max(
			max(math.abs(grid.min_x), math.abs(grid.max_x)),
			max(math.abs(grid.min_y), math.abs(grid.max_y)),
		) +
		300
	limit := world_limit * COMBAT_VIEW_SCALE
	s.combat_pan_x = clamp(
		s.combat_pan_x,
		-limit,
		limit,
	); s.combat_pan_y = clamp(s.combat_pan_y, -limit, limit)
}

combat_zoom_anchor_safe :: proc(s: ^Ux_State, p: game.Combat_Vec3) -> bool {
	grid := s.combat.grid; padding := max(grid.max_x - grid.min_x, grid.max_y - grid.min_y)
	return(
		p.x >= grid.min_x - padding &&
		p.x <= grid.max_x + padding &&
		p.y >= grid.min_y - padding &&
		p.y <= grid.max_y + padding \
	)
}

combat_set_speed :: proc(s: ^Ux_State, speed: f32) {
	if speed <= 0 {
		s.combat_paused = true
		return
	}
	s.combat_speed = speed
	s.combat_paused = false
}

combat_toggle_pause :: proc(s: ^Ux_State) {
	if s.combat_paused {
		if s.combat_speed <= 0 do s.combat_speed = 1
		s.combat_paused = false
	} else {
		s.combat_paused = true
	}
}

combat_speed_control :: proc(s: ^Ux_State, rect: rl.Rectangle) {
	labels := [5]string{"", "1X", "10X", "100X", "1000X"}
	speeds := [5]f32{0, 1, 10, 100, 1000}
	selected := 0
	if !s.combat_paused {
		selected = 1
		best_distance := math.abs(s.combat_speed - speeds[selected])
		for speed, i in speeds[1:] {
			distance := math.abs(s.combat_speed - speed)
			if distance < best_distance {
				selected = i + 1
				best_distance = distance
			}
		}
	}
	chosen := tab_group(rect, labels[:], selected)
	tab_width := rect.width / f32(len(labels))
	pause_rect := R(rect.x, rect.y, tab_width, rect.height)
	pause_color := selected == 0 ? UX.text : UX.dim
	bar_y := pause_rect.y + 8
	bar_height := pause_rect.height - 16
	rl.DrawRectangleRec(R(pause_rect.x + tab_width * .40 - 2, bar_y, 2, bar_height), pause_color)
	rl.DrawRectangleRec(R(pause_rect.x + tab_width * .60, bar_y, 2, bar_height), pause_color)
	if rl.CheckCollisionPointRec(ux_mouse, pause_rect) {
		ux_tooltip = {
			visible = true,
			anchor  = pause_rect,
			title   = "PAUSE TACTICAL TIME",
			body    = "Pause or resume simulated time (Space).",
		}
	}
	if chosen != selected do combat_set_speed(s, speeds[chosen])
}

combat_draw_mission_clock :: proc(s: ^Ux_State) {
	clock_rect := R(990, 8, 270, 46)
	if rl.CheckCollisionPointRec(ux_mouse, clock_rect) {
		if rl.IsMouseButtonPressed(.LEFT) do s.combat_show_mission_time = !s.combat_show_mission_time
		ux_tooltip = {
			visible = true,
			anchor  = clock_rect,
			title   = s.combat_show_mission_time ? "MISSION TIME" : "NAVIGATION TIME",
			body    = s.combat_show_mission_time ? "Elapsed engagement time; click to show navigation time remaining." : "Navigation time remaining; click to show elapsed engagement time.",
		}
	}
	shown := s.combat.time
	label := "MISSION"
	color := UX.info
	if !s.combat_show_mission_time {
		shown = max(game.combat_mission_duration(&s.combat) - s.combat.time, 0)
		label = "NAV"
		color = shown < 120 ? UX.bad : UX.warn
	}
	draw_fmt(
		1000,
		17,
		TYPE_SUBHEADING_COMPACT,
		color,
		"%s %02d:%02d",
		label,
		int(shown) / 60,
		int(shown) % 60,
	)
}
