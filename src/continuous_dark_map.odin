package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:math"

// The Dark is the environment, not a map inset.  The world pass fills the
// logical canvas and the expedition readout is drawn over it afterward.
CONTINUOUS_DARK_VIEW :: rl.Rectangle{0, 0, 1280, 720}

draw_continuous_dark_3d_overlay :: proc(s: ^Ux_State) {
	p := &s.campaign.passage; d := &s.campaign.outer_dark.continuum; origin := p.dark_navigation.position
	law, weather := game.dark_environment_at(
		d,
		origin,
	); wake := f64(0); if at := game.dark_nearest_field(d, origin); at >= 0 do wake = d.fields[at].wake_energy
	if contains(CONTINUOUS_DARK_VIEW) {
		wheel := rl.GetMouseWheelMove(
			
		); if wheel != 0 do s.dark_zoom = clamp(s.dark_zoom * f64(math.exp(f64(wheel) * .12)), .65, 8)
		if rl.IsMouseButtonDown(
			.RIGHT,
		) {delta := rl.GetMouseDelta(); scale := max(ux_zoom, .01); dark_3d_orbit(s, delta.x / scale * .006, delta.y / scale * .006)}
	}
	key_orbit := f32(
		.018,
	); if rl.IsKeyDown(.LEFT) do dark_3d_orbit(s, -key_orbit, 0); if rl.IsKeyDown(.RIGHT) do dark_3d_orbit(s, key_orbit, 0); if rl.IsKeyDown(.UP) do dark_3d_orbit(s, 0, -key_orbit); if rl.IsKeyDown(.DOWN) do dark_3d_orbit(s, 0, key_orbit)
	label_x := f32(820)
	draw_text("RIGHT DRAG / ARROWS ORBIT · WHEEL DEPTH", label_x, 122, TYPE_FINE, UX.dim)
	draw_fmt(
		label_x,
		122 + readable_text_size(TYPE_FINE) + 3,
		TYPE_MICRO,
		UX.info,
		"LAW %.2f · WEATHER %.2f · WAKE %.2f · TRACKS %d",
		law,
		weather,
		wake,
		p.dark_navigation.tracker.track_count,
	)
	ship_world := dark_target_world(d.anchor_position, p.dark_navigation.position)
	if ship_screen, visible := dark_3d_project_to_ui(s, ship_world); visible {
		r := f32(11); ink := rl.Color{174, 196, 193, 175}
		rl.DrawLineEx(
			V(ship_screen.x - r, ship_screen.y - r),
			V(ship_screen.x - r / 3, ship_screen.y - r),
			1,
			ink,
		)
		rl.DrawLineEx(
			V(ship_screen.x - r, ship_screen.y - r),
			V(ship_screen.x - r, ship_screen.y - r / 3),
			1,
			ink,
		)
		rl.DrawLineEx(
			V(ship_screen.x + r, ship_screen.y + r),
			V(ship_screen.x + r / 3, ship_screen.y + r),
			1,
			ink,
		)
		rl.DrawLineEx(
			V(ship_screen.x + r, ship_screen.y + r),
			V(ship_screen.x + r, ship_screen.y + r / 3),
			1,
			ink,
		)
		leader_end := V(ship_screen.x + 74, ship_screen.y - 24)
		rl.DrawLineEx(V(ship_screen.x + r, ship_screen.y - r), leader_end, 1, ink)
		label_y := leader_end.y - readable_text_size(TYPE_MICRO) / 2
		draw_text("FLAGSHIP · LAMP ORIGIN", leader_end.x + 8, label_y, TYPE_MICRO, UX.info)
		draw_text(
			"BLACKOUT LIMIT 900",
			leader_end.x + 8,
			label_y + readable_text_size(TYPE_MICRO) + 3,
			TYPE_MICRO,
			UX.dim,
		)
	}
}
