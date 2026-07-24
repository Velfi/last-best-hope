package main

import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"
import rl "zelda_engine:canvas2d"

navigation_body_equal :: proc(a, b: game.Celestial_Body_Ref) -> bool {
	return a.kind == b.kind && a.index == b.index
}

navigation_body_label :: proc(
	system: ^game.Solar_System,
	body: game.Celestial_Body_Ref,
) -> string {
	if system == nil do return "UNRESOLVED"
	return game.system_body_name(system^, body)
}

navigation_ship_label :: proc(c: ^game.Campaign, id: game.Ship_ID) -> string {
	if c == nil || id == 0 do return "UNRESOLVED"
	for ship in c.ships[:c.ship_count] do if ship.id == id do return ship.name
	return fmt.tprintf("SHIP %04d", u32(id))
}

navigation_target_label :: proc(
	c: ^game.Campaign,
	system: ^game.Solar_System,
	body: game.Celestial_Body_Ref,
) -> string {
	label := navigation_body_label(system, body)
	if c == nil do return label
	if deposit_at := game.fleet_deposit_index(c, body); deposit_at >= 0 {
		deposit := c.fleet_navigation.deposits[deposit_at]
		return(
			deposit.intel < .Characterized ? fmt.tprintf("%s · MATERIAL SIGNATURE", label) : deposit.remaining_propellant_kt <= 1e-9 && deposit.remaining_feedstock <= 0 ? fmt.tprintf("%s · SOURCE DEPLETED", label) : fmt.tprintf("%s · MATERIAL SOURCE", label) \
		)
	}
	return label
}

navigation_local_target_count :: proc(
	system: ^game.Solar_System,
	current: game.Celestial_Body_Ref,
) -> int {
	if system == nil do return 0
	count := 0
	for _, i in system.planets[:system.planet_count] {
		if !navigation_body_equal({kind = .Planet, index = i}, current) do count += 1
	}
	for _, i in system.asteroids[:system.asteroid_count] {
		if !navigation_body_equal({kind = .Asteroid, index = i}, current) do count += 1
	}
	return count
}

navigation_cycle_local_target :: proc(
	system: ^game.Solar_System,
	current, selected: game.Celestial_Body_Ref,
	step: int,
) -> game.Celestial_Body_Ref {
	if system == nil || navigation_local_target_count(system, current) <= 0 do return selected
	total := system.planet_count + system.asteroid_count
	index := selected.kind == .Planet ? selected.index : system.planet_count + selected.index
	if index < 0 || index >= total do index = step < 0 ? 0 : -1
	for _ in 0 ..< total {
		index = (index + step + total) % total
		candidate :=
			index < system.planet_count ? game.Celestial_Body_Ref{kind = .Planet, index = index} : game.Celestial_Body_Ref{kind = .Asteroid, index = index - system.planet_count}
		if !navigation_body_equal(candidate, current) do return candidate
	}
	return selected
}

// Keep dense asteroid belts legible while never hiding either end of the
// transfer the player is currently evaluating.
navigation_map_draws_asteroid :: proc(
	index: int,
	current, selected: game.Celestial_Body_Ref,
) -> bool {
	if index < 12 do return true
	body := game.Celestial_Body_Ref {
		kind  = .Asteroid,
		index = index,
	}
	return navigation_body_equal(body, current) || navigation_body_equal(body, selected)
}

@(test)
navigation_target_cycle_reaches_bodies_beyond_the_visible_shortlist :: proc(t: ^testing.T) {
	system := game.Solar_System {
		planet_count   = 6,
		asteroid_count = 10,
	}
	current := game.Celestial_Body_Ref {
		kind  = .Planet,
		index = 0,
	}
	target := game.Celestial_Body_Ref {
		kind  = .Planet,
		index = 5,
	}
	next := navigation_cycle_local_target(&system, current, target, 1)
	testing.expect_value(t, next, game.Celestial_Body_Ref{kind = .Asteroid, index = 0})
	last := game.Celestial_Body_Ref {
		kind  = .Asteroid,
		index = 9,
	}
	wrapped := navigation_cycle_local_target(&system, current, last, 1)
	testing.expect_value(t, wrapped, game.Celestial_Body_Ref{kind = .Planet, index = 1})
	previous := navigation_cycle_local_target(&system, current, target, -1)
	testing.expect_value(t, previous, game.Celestial_Body_Ref{kind = .Planet, index = 4})
}

@(test)
navigation_map_keeps_selected_or_current_distant_asteroid_visible :: proc(t: ^testing.T) {
	current := game.Celestial_Body_Ref {
		kind  = .Asteroid,
		index = 18,
	}
	selected := game.Celestial_Body_Ref {
		kind  = .Asteroid,
		index = 23,
	}
	testing.expect(t, navigation_map_draws_asteroid(0, current, selected))
	testing.expect(t, navigation_map_draws_asteroid(18, current, selected))
	testing.expect(t, navigation_map_draws_asteroid(23, current, selected))
	testing.expect(t, !navigation_map_draws_asteroid(24, current, selected))
}

navigation_days_from_now :: proc(c: ^game.Campaign, days: f64) -> game.Campaign_Time {
	return game.campaign_time_add(
		c.clock.now,
		i64(math.ceil(max(days, 1) * f64(game.CAMPAIGN_DAY_SECONDS))),
	)
}

navigation_campaign_day :: proc(at: game.Campaign_Time) -> i64 {
	return max(i64(at), i64(0)) / game.CAMPAIGN_DAY_SECONDS
}

navigation_reporting_boundaries_before :: proc(
	now, next_reporting_at, arrival: game.Campaign_Time,
) -> int {
	if arrival < next_reporting_at || next_reporting_at < now do return 0
	return int((i64(arrival) - i64(next_reporting_at)) / game.CAMPAIGN_REPORT_SECONDS) + 1
}

@(test)
navigation_campaign_day_uses_the_authoritative_campaign_clock :: proc(t: ^testing.T) {
	testing.expect_value(t, navigation_campaign_day(0), i64(0))
	testing.expect_value(
		t,
		navigation_campaign_day(
			game.Campaign_Time(3 * game.CAMPAIGN_DAY_SECONDS + game.CAMPAIGN_HOUR_SECONDS),
		),
		i64(3),
	)
}

@(test)
navigation_reports_known_campaign_boundaries_before_arrival :: proc(t: ^testing.T) {
	now := game.Campaign_Time(10 * game.CAMPAIGN_DAY_SECONDS)
	next := game.Campaign_Time(30 * game.CAMPAIGN_DAY_SECONDS)
	testing.expect_value(
		t,
		navigation_reporting_boundaries_before(
			now,
			next,
			game.Campaign_Time(29 * game.CAMPAIGN_DAY_SECONDS),
		),
		0,
	)
	testing.expect_value(
		t,
		navigation_reporting_boundaries_before(
			now,
			next,
			game.Campaign_Time(30 * game.CAMPAIGN_DAY_SECONDS),
		),
		1,
	)
	testing.expect_value(
		t,
		navigation_reporting_boundaries_before(
			now,
			next,
			game.Campaign_Time(30 * game.CAMPAIGN_DAY_SECONDS + game.CAMPAIGN_REPORT_SECONDS),
		),
		2,
	)
}

navigation_draw_system_map :: proc(
	c: ^game.Campaign,
	system: ^game.Solar_System,
	rect: rl.Rectangle,
	target: ^game.Celestial_Body_Ref,
) {
	panel(rect)
	center := V(rect.x + rect.width * .5, rect.y + rect.height * .5)
	epoch := game.fleet_navigation_epoch_days(c)
	max_axis: f64 = 1
	for planet in system.planets[:system.planet_count] do max_axis = max(max_axis, planet.orbit.semi_major_axis_au)
	for asteroid in system.asteroids[:system.asteroid_count] do max_axis = max(max_axis, asteroid.orbit.semi_major_axis_au)
	radius_for :: proc(axis, maximum: f64, radius: f32) -> f32 {
		return f32(math.log(1 + max(axis, 0), 2.0) / math.log(1 + max(maximum, 1), 2.0)) * radius
	}
	body_point := proc(
		system: ^game.Solar_System,
		body: game.Celestial_Body_Ref,
		epoch: f64,
		center: rl.Vector2,
		maximum: f64,
		display_radius: f32,
	) -> (
		rl.Vector2,
		bool,
	) {
		state, ok := game.system_body_state_at(system, body, epoch)
		if !ok do return {}, false
		length := math.sqrt(
			state.position_au[0] * state.position_au[0] +
			state.position_au[1] * state.position_au[1],
		)
		if length <= 1e-9 do return center, true
		axis := length
		#partial switch body.kind {
		case .Planet:
			axis = system.planets[body.index].orbit.semi_major_axis_au
		case .Asteroid:
			axis = system.asteroids[body.index].orbit.semi_major_axis_au
		}
		radius :=
			f32(math.log(1 + max(axis, 0), 2.0) / math.log(1 + max(maximum, 1), 2.0)) *
			display_radius
		return V(
				center.x + f32(state.position_au[0] / length) * radius,
				center.y + f32(state.position_au[1] / length) * radius,
			),
			true
	}
	map_radius := min(rect.width, rect.height) * .43
	if origin, origin_ok := body_point(
		system,
		c.fleet_navigation.current_body,
		epoch,
		center,
		max_axis,
		map_radius,
	); origin_ok {
		if destination, destination_ok := body_point(system, target^, epoch, center, max_axis, map_radius); destination_ok && !navigation_body_equal(c.fleet_navigation.current_body, target^) do rl.DrawLineEx(origin, destination, 1.5, rl.Color{UX.info.r, UX.info.g, UX.info.b, 150})
	}
	for planet in system.planets[:system.planet_count] {
		r := radius_for(
			planet.orbit.semi_major_axis_au,
			max_axis,
			min(rect.width, rect.height) * .43,
		)
		prior := V(center.x + r, center.y)
		for segment in 1 ..= 48 {
			angle := f32(segment) / 48 * 2 * f32(math.PI)
			next := V(
				center.x + f32(math.cos(f64(angle))) * r,
				center.y + f32(math.sin(f64(angle))) * r,
			)
			rl.DrawLineEx(prior, next, 1, rl.Color{UX.line.r, UX.line.g, UX.line.b, 100})
			prior = next
		}
	}
	rl.DrawCircleV(center, 5, UX.text)
	for planet, i in system.planets[:system.planet_count] {
		body := game.Celestial_Body_Ref {
			kind  = .Planet,
			index = i,
		}
		state, ok := game.system_body_state_at(system, body, epoch)
		if !ok do continue
		r := radius_for(
			planet.orbit.semi_major_axis_au,
			max_axis,
			min(rect.width, rect.height) * .43,
		)
		length := math.sqrt(
			state.position_au[0] * state.position_au[0] +
			state.position_au[1] * state.position_au[1],
		)
		x, y := center.x + r, center.y
		if length > 0 {
			x = center.x + f32(state.position_au[0] / length) * r
			y = center.y + f32(state.position_au[1] / length) * r
		}
		color :=
			navigation_body_equal(body, c.fleet_navigation.current_body) ? UX.good : navigation_body_equal(body, target^) ? UX.info : UX.dim
		rl.DrawCircleV(V(x, y), 4, color)
		hovered :=
			math.sqrt(
				f64((ux_mouse.x - x) * (ux_mouse.x - x) + (ux_mouse.y - y) * (ux_mouse.y - y)),
			) <=
			9
		if hovered do ux_tooltip = {
			visible = true,
			anchor  = R(x - 4, y - 4, 8, 8),
			title   = navigation_body_label(system, body),
			body    = navigation_body_equal(body, c.fleet_navigation.current_body) ? "Current holding orbit." : "Local transfer target. Click to select.",
		}
		if !navigation_body_equal(body, c.fleet_navigation.current_body) && rl.IsMouseButtonPressed(.LEFT) && hovered do target^ = body
	}
	for asteroid, i in system.asteroids[:system.asteroid_count] {
		if !navigation_map_draws_asteroid(i, c.fleet_navigation.current_body, target^) do continue
		body := game.Celestial_Body_Ref {
			kind  = .Asteroid,
			index = i,
		}
		state, ok := game.system_body_state_at(system, body, epoch)
		if !ok do continue
		r := radius_for(
			asteroid.orbit.semi_major_axis_au,
			max_axis,
			min(rect.width, rect.height) * .43,
		)
		length := math.sqrt(
			state.position_au[0] * state.position_au[0] +
			state.position_au[1] * state.position_au[1],
		)
		x, y := center.x + r, center.y
		if length > 0 {
			x = center.x + f32(state.position_au[0] / length) * r
			y = center.y + f32(state.position_au[1] / length) * r
		}
		deposit_at := game.fleet_deposit_index(c, body)
		color :=
			navigation_body_equal(body, c.fleet_navigation.current_body) ? UX.good : navigation_body_equal(body, target^) ? UX.info : deposit_at >= 0 && (c.fleet_navigation.deposits[deposit_at].remaining_propellant_kt > 1e-9 || c.fleet_navigation.deposits[deposit_at].remaining_feedstock > 0) ? UX.good : UX.dim
		rl.DrawRectangle(i32(x - 2), i32(y - 2), 4, 4, color)
		hovered :=
			math.sqrt(
				f64((ux_mouse.x - x) * (ux_mouse.x - x) + (ux_mouse.y - y) * (ux_mouse.y - y)),
			) <=
			9
		if hovered {
			tooltip_body := "Local transfer target. Click to select."
			if deposit_at >= 0 {
				deposit := c.fleet_navigation.deposits[deposit_at]
				tooltip_body =
					deposit.intel < .Characterized ? "Material signature. Close range to characterize." : deposit.remaining_propellant_kt <= 1e-9 && deposit.remaining_feedstock <= 0 ? "Material source depleted. Click to select." : "Known physical material source. Click to select."
			}
			ux_tooltip = {
				visible = true,
				anchor  = R(x - 4, y - 4, 8, 8),
				title   = navigation_body_label(system, body),
				body    = tooltip_body,
			}
		}
		if !navigation_body_equal(body, c.fleet_navigation.current_body) && rl.IsMouseButtonPressed(.LEFT) && hovered do target^ = body
	}
	label_caps("CURRENT EPHEMERIS", rect.x + 14, rect.y + 12, UX.dim)
}

navigation_draw_propellant_wave :: proc(c: ^game.Campaign, rect: rl.Rectangle) {
	capacity := game.fleet_propellant_capacity(c)
	remaining := game.fleet_propellant_remaining(c)
	reserve := game.fleet_propellant_reserve(c)
	panel(rect)
	label_caps("PROPELLANT RHYTHM", rect.x + 16, rect.y + 13, UX.text)
	track := R(rect.x + 16, rect.y + 45, rect.width - 32, 12)
	rl.DrawRectangleRec(track, UX.void)
	fraction := capacity > 0 ? f32(clamp(remaining / capacity, 0, 1)) : 0
	reserve_fraction := capacity > 0 ? f32(clamp(reserve / capacity, 0, 1)) : 0
	ink := remaining <= reserve ? UX.warn : UX.good
	rl.DrawRectangleRec(
		R(track.x, track.y, track.width * fraction, track.height),
		rl.Color{ink.r, ink.g, ink.b, 120},
	)
	reserve_x := track.x + track.width * reserve_fraction
	rl.DrawLineEx(V(reserve_x, track.y - 5), V(reserve_x, track.y + track.height + 5), 2, UX.warn)
	rl.DrawLineEx(V(track.x, track.y), V(track.x + track.width, track.y), 1, UX.line)
	rl.DrawLineEx(
		V(track.x + track.width, track.y),
		V(track.x + track.width, track.y + track.height),
		1,
		UX.line,
	)
	rl.DrawLineEx(
		V(track.x + track.width, track.y + track.height),
		V(track.x, track.y + track.height),
		1,
		UX.line,
	)
	rl.DrawLineEx(V(track.x, track.y + track.height), V(track.x, track.y), 1, UX.line)
	draw_fmt(
		rect.x + 16,
		rect.y + 67,
		TYPE_FINE,
		UX.text,
		"%.1f / %.1f KT · RESERVE %.1f KT",
		remaining,
		capacity,
		reserve,
	)
	draw_fmt(
		rect.x + rect.width - 180,
		rect.y + 67,
		TYPE_FINE,
		c.fleet_navigation.phase == .Transfer ? UX.committed : c.fleet_navigation.phase == .Harvesting ? UX.good : UX.info,
		"%v",
		c.fleet_navigation.phase,
	)
	if button(R(rect.x + rect.width - 196, rect.y + 10, 42, 24), "−5", c.fleet_navigation.phase == .Holding) do c.fleet_navigation.protected_reserve_fraction = max(.05, c.fleet_navigation.protected_reserve_fraction - .05)
	if button(R(rect.x + rect.width - 64, rect.y + 10, 42, 24), "+5", c.fleet_navigation.phase == .Holding) do c.fleet_navigation.protected_reserve_fraction = min(.75, c.fleet_navigation.protected_reserve_fraction + .05)
	draw_fmt(
		rect.x + rect.width - 148,
		rect.y + 16,
		TYPE_MICRO,
		UX.warn,
		"RESERVE %.0f%%",
		c.fleet_navigation.protected_reserve_fraction * 100,
	)
	if rl.CheckCollisionPointRec(ux_mouse, R(rect.x + rect.width - 196, rect.y + 10, 174, 24)) do ux_tooltip = {
		visible = true,
		anchor  = R(rect.x + rect.width - 196, rect.y + 10, 174, 24),
		title   = "PROTECTED RESERVE",
		body    = "Propellant held back for recovery. A transfer below this threshold still requires emergency authority.",
	}
}

draw_navigation :: proc(s: ^Ux_State) {
	top_rail(s)
	c := s.campaign
	system := game.fleet_navigation_system(c)
	if system == nil {
		label_caps("FLEET NAVIGATION UNAVAILABLE", 36, 92, UX.bad)
		return
	}
	if s.navigation_arrival_days <= 0 do s.navigation_arrival_days = 180
	if s.navigation_harvest_fraction <= 0 do s.navigation_harvest_fraction = .8
	if s.navigation_harvest_deadline_days <= 0 do s.navigation_harvest_deadline_days = 90
	if !game.system_ref_valid(system, s.navigation_target) ||
	   navigation_body_equal(s.navigation_target, c.fleet_navigation.current_body) {
		if system.asteroid_count > 0 do s.navigation_target = {
			kind  = .Asteroid,
			index = 0,
		}
		else if system.planet_count > 1 do s.navigation_target = {
			kind  = .Planet,
			index = 1,
		}
		else do s.navigation_target = {
			kind  = .Star,
			index = 0,
		}
	}

	transfer_underway :=
		c.fleet_navigation.phase == .Transfer && c.fleet_navigation.transfer.active
	harvest_underway :=
		c.fleet_navigation.phase == .Harvesting && c.fleet_navigation.harvest.active
	map_target := s.navigation_target
	if transfer_underway do map_target = c.fleet_navigation.transfer.forecast.target
	if harvest_underway do map_target = c.fleet_navigation.current_body
	label_caps("FLEET NAVIGATION", 28, 76, UX.text)
	if transfer_underway {
		draw_fmt(
			28,
			96,
			TYPE_FINE,
			UX.committed,
			"TRANSFER TO %s",
			navigation_body_label(system, map_target),
		)
		draw_text_fitted(
			"COMMITTED LEG · CAPTAINS ARE EXECUTING THE RECORDED BURN",
			R(28, 112, 650, 18),
			TYPE_FINE,
			UX.dim,
		)
	} else if harvest_underway {
		draw_fmt(
			28,
			96,
			TYPE_FINE,
			UX.good,
			"RECOVERING AT %s",
			navigation_body_label(system, c.fleet_navigation.current_body),
		)
		draw_text_fitted(
			"COMMITTED HOLD · CAPTAINS ARE EXTRACTING AND REFINING WATER",
			R(28, 112, 650, 18),
			TYPE_FINE,
			UX.dim,
		)
	} else {
		draw_fmt(
			28,
			96,
			TYPE_FINE,
			UX.info,
			"HOLDING AT %s",
			navigation_body_label(system, c.fleet_navigation.current_body),
		)
		draw_text_fitted(
			"1 SELECT A LOCAL BODY  ·  2 SET ARRIVAL  ·  3 REVIEW THE BURN AND COMMIT",
			R(28, 112, 650, 18),
			TYPE_FINE,
			UX.dim,
		)
	}
	navigation_draw_system_map(c, system, R(28, 140, 650, 339), &map_target)
	navigation_draw_propellant_wave(c, R(28, 493, 650, 98))
	if transfer_underway {
		order := c.fleet_navigation.transfer
		remaining_days := max(
			f64(i64(order.forecast.arrival_at) - i64(c.clock.now)) /
			f64(game.CAMPAIGN_DAY_SECONDS),
			0,
		)
		panel(R(696, 76, 540, 515))
		label_caps("TRANSFER UNDERWAY", 720, 96, UX.committed)
		draw_text_fitted(
			fmt.tprintf("DESTINATION · %s", navigation_body_label(system, order.forecast.target)),
			R(720, 126, 490, 20),
			TYPE_BODY_EMPHASIS,
			UX.text,
		)
		draw_fmt(720, 164, TYPE_BODY_EMPHASIS, UX.info, "ARRIVAL IN %.1f DAYS", remaining_days)
		draw_fmt(
			720,
			196,
			TYPE_FINE,
			UX.text,
			"DEPART %.2f KM/S · RENDEZVOUS %.2f KM/S",
			order.forecast.departure_delta_v_km_s,
			order.forecast.arrival_delta_v_km_s,
		)
		draw_fmt(
			720,
			220,
			TYPE_FINE,
			UX.text,
			"COMMITTED BURN %.1f KT · TOTAL ΔV %.2f KM/S",
			order.forecast.propellant_cost_kt,
			order.forecast.total_delta_v_km_s,
		)
		draw_fmt(
			720,
			244,
			TYPE_FINE,
			order.forecast.crosses_reserve ? UX.warn : UX.good,
			"ARRIVAL RESERVE MARGIN %+.1f KT",
			order.forecast.reserve_margin_kt,
		)
		if order.emergency_override do draw_text_fitted("EMERGENCY AUTHORITY WAS RECORDED FOR THIS LEG.", R(720, 270, 490, 20), TYPE_FINE, UX.warn)
		if order.deviation_reported do draw_text_wrapped("A material change invalidated a planning boundary. The leg remains underway; its deviation is recorded in the campaign chronicle.", R(720, 308, 470, 52), TYPE_FINE, UX.warn)
		else do draw_text_wrapped("The leg remains within the conditions recorded at commitment. Campaign time will stop at arrival or if a material change invalidates that record.", R(720, 308, 470, 52), TYPE_FINE, UX.dim)
		draw_text_fitted(
			"ROUTINE EXECUTION IS AUTOMATIC. REVIEW THE FLEET OR ADVANCE TIME.",
			R(720, 548, 490, 18),
			TYPE_FINE,
			UX.dim,
		)
		draw_campaign_underway_rail(s, "TRANSFER UNDERWAY · CAPTAINS EXECUTE THE COMMITTED LEG")
		return
	}
	if harvest_underway {
		order := c.fleet_navigation.harvest
		remaining_days := max(
			f64(i64(order.due_at) - i64(c.clock.now)) / f64(game.CAMPAIGN_DAY_SECONDS),
			0,
		)
		panel(R(696, 76, 540, 515))
		label_caps(
			order.interrupted ? "EXTRACTION INTERRUPTED" : "RECOVERY HOLD UNDERWAY",
			720,
			96,
			order.interrupted ? UX.warn : UX.good,
		)
		if order.interrupted {
			draw_text_wrapped(
				"The body reached its forecast operating limit. Depart with recovered material or accept reduced throughput.",
				R(720, 268, 470, 54),
				TYPE_FINE,
				UX.warn,
			)
			if button(
				R(860, 548, 160, 32),
				"DEPART WITH CARGO",
			) {_, s.status = game.fleet_navigation_resume_harvest(c, false)}
			if button(
				R(1030, 548, 180, 32),
				"CONTINUE SLOWLY",
			) {_, s.status = game.fleet_navigation_resume_harvest(c, true)}
			draw_campaign_underway_rail(s, "EXTRACTION PAUSED · CHOOSE A RECOVERY RESPONSE")
			return
		}
		draw_text_fitted(
			fmt.tprintf("SOURCE · %s", navigation_body_label(system, order.body)),
			R(720, 126, 490, 20),
			TYPE_BODY_EMPHASIS,
			UX.text,
		)
		draw_fmt(720, 164, TYPE_BODY_EMPHASIS, UX.info, "HOLD ENDS IN %.1f DAYS", remaining_days)
		draw_fmt(
			720,
			196,
			TYPE_FINE,
			UX.text,
			"PLANNED %.1f KT · %d FEEDSTOCK",
			order.planned_propellant_kt,
			order.planned_feedstock,
		)
		draw_fmt(720, 220, TYPE_FINE, UX.dim, "GOVERNING CONDITION · %v", order.stop)
		if order.deviation_reported do draw_text_fitted("REFINING THROUGHPUT CHANGED · HOLD REVISED", R(720, 244, 490, 18), TYPE_FINE, UX.warn)
		draw_text_wrapped(
			"Recovery completes at the first recorded condition: tank target, departure deadline, full storage, or source depletion. Campaign time will stop when the hold resolves.",
			R(720, 268, 470, 54),
			TYPE_FINE,
			UX.dim,
		)
		draw_text_fitted(
			"ROUTINE RECOVERY IS AUTOMATIC. REVIEW THE FLEET OR ADVANCE TIME.",
			R(720, 548, 490, 18),
			TYPE_FINE,
			UX.dim,
		)
		draw_campaign_underway_rail(
			s,
			"RECOVERY HOLD UNDERWAY · CAPTAINS REFINE THE DECLARED TARGET",
		)
		return
	}

	panel(R(696, 76, 540, 515))
	local_target_count := navigation_local_target_count(system, c.fleet_navigation.current_body)
	label_caps("1 · SELECT A LOCAL BODY", 720, 96, UX.info)
	if local_target_count == 0 {
		// A barren system is a valid generated state. It cannot offer a local
		// transfer, so make the campaign-level next action explicit instead of
		// leaving an empty target panel and a disabled commit control.
		draw_text_fitted(
			"NO LOCAL BODIES ARE AVAILABLE FOR TRANSFER.",
			R(720, 130, 490, 22),
			TYPE_SMALL_EMPHASIS,
			UX.warn,
		)
		commission_ready := fleet_passage_commission_ready(c)
		compact_ready :=
			fleet_compact_notification_pending(c) ||
			(c.current_situation.phase != .None && c.current_situation.phase != .Resolved)
		message := "No Compact call is awaiting attention. Advance the season to continue the record."
		if compact_ready do message = "A Compact call is awaiting attention before a Passage can be commissioned."
		if commission_ready do message = "A Compact Passage undertaking is ready to commission beyond this system."
		draw_text_wrapped(message, R(720, 158, 465, 48), TYPE_FINE, UX.dim)
		if commission_ready && button(R(720, 220, 238, 38), "COMMISSION PASSAGE", true, true) {
			prepare_dark_briefing(s)
			s.screen = .Briefing
		}
		if !commission_ready &&
		   compact_ready &&
		   button(R(720, 220, 238, 38), "OPEN COMPACT", true, true) {
			if fleet_compact_notification_pending(c) do open_opening_council(s)
			else do s.screen = .Interaction
		}
		draw_text_fitted(
			"Fleet navigation only governs transfers inside this stellar system.",
			R(720, 268, 490, 18),
			TYPE_FINE,
			UX.dim,
		)
	} else {
		py: f32 = 124
		for i in 0 ..< min(system.planet_count, 4) {
			body := game.Celestial_Body_Ref {
				kind  = .Planet,
				index = i,
			}
			if navigation_body_equal(body, c.fleet_navigation.current_body) do continue
			if button(R(720, py, 230, 30), navigation_body_label(system, body), true, navigation_body_equal(body, s.navigation_target)) do s.navigation_target = body
			py += 34
		}
		for i in 0 ..< min(system.asteroid_count, 6) {
			body := game.Celestial_Body_Ref {
				kind  = .Asteroid,
				index = i,
			}
			if navigation_body_equal(body, c.fleet_navigation.current_body) do continue
			label := navigation_target_label(c, system, body)
			if button(R(960, 124 + f32(i) * 34, 250, 30), label, true, navigation_body_equal(body, s.navigation_target)) do s.navigation_target = body
		}
		if button(R(720, 314, 112, 24), "← PREVIOUS") do s.navigation_target = navigation_cycle_local_target(system, c.fleet_navigation.current_body, s.navigation_target, -1)
		if button(R(838, 314, 112, 24), "NEXT →") do s.navigation_target = navigation_cycle_local_target(system, c.fleet_navigation.current_body, s.navigation_target, 1)
		selected_label := navigation_target_label(c, system, s.navigation_target)
		draw_text_fitted(
			fmt.tprintf("TARGET · %s", selected_label),
			R(960, 318, 250, 16),
			TYPE_FINE,
			UX.info,
		)
	}

	divider(720, 342, 490)
	label_caps("2 · SET ARRIVAL WINDOW", 720, 359, UX.text)
	if button(R(720, 385, 55, 32), "−30") do s.navigation_arrival_days = max(1, s.navigation_arrival_days - 30)
	if button(R(781, 385, 55, 32), "−5") do s.navigation_arrival_days = max(1, s.navigation_arrival_days - 5)
	draw_fmt(850, 392, TYPE_BODY_EMPHASIS, UX.info, "%.0f DAYS", s.navigation_arrival_days)
	if button(R(980, 385, 55, 32), "+5") do s.navigation_arrival_days += 5
	if button(R(1041, 385, 65, 32), "+30") do s.navigation_arrival_days += 30
	if button(R(1112, 385, 46, 32), "FUEL", local_target_count > 0) {
		best, found := game.fleet_transfer_best_window(c, s.navigation_target, 30, 1200, 5)
		if found {
			s.navigation_arrival_days = best.duration_days
			s.status = fmt.tprintf(
				"Selected the lowest-burn protected-reserve window: %.0f days.",
				best.duration_days,
			)
		} else if emergency, emergency_found := game.fleet_transfer_best_emergency_window(
			c,
			s.navigation_target,
			30,
			1200,
			5,
		); emergency_found {
			s.navigation_arrival_days = emergency.duration_days
			s.status = fmt.tprintf(
				"No protected window found; selected the smallest reserve breach: %.0f days.",
				emergency.duration_days,
			)
		} else {
			s.status = "No protected-reserve transfer window was found in the next 1,200 days."
		}
	}
	if button(R(1164, 385, 46, 32), "FAST", local_target_count > 0) {
		fastest, found := game.fleet_transfer_fastest_safe_window(
			c,
			s.navigation_target,
			30,
			1200,
			5,
		)
		if found {
			s.navigation_arrival_days = fastest.duration_days
			s.status = fmt.tprintf(
				"Selected the earliest protected-reserve arrival: %.0f days.",
				fastest.duration_days,
			)
		} else {
			s.status = "No protected-reserve transfer window was found in the next 1,200 days."
		}
	}
	if rl.CheckCollisionPointRec(ux_mouse, R(1112, 385, 46, 32)) do ux_tooltip = {
		visible = true,
		anchor  = R(1112, 385, 46, 32),
		title   = "LOWEST-BURN WINDOW",
		body    = "Selects the protected-reserve arrival window with the least propellant cost.",
	}
	if rl.CheckCollisionPointRec(ux_mouse, R(1164, 385, 46, 32)) do ux_tooltip = {
		visible = true,
		anchor  = R(1164, 385, 46, 32),
		title   = "FASTEST SAFE WINDOW",
		body    = "Selects the earliest arrival window that preserves the protected reserve.",
	}

	arrival := navigation_days_from_now(c, s.navigation_arrival_days)
	reports_before_arrival := navigation_reporting_boundaries_before(
		c.clock.now,
		c.clock.next_reporting_at,
		arrival,
	)
	arrival_context := fmt.tprintf("ARRIVES · CAMPAIGN DAY %d", navigation_campaign_day(arrival))
	if reports_before_arrival > 0 {
		boundary_label :=
			reports_before_arrival == 1 ? "REPORTING BOUNDARY" : "REPORTING BOUNDARIES"
		arrival_context = fmt.tprintf(
			"%s · %d %s",
			arrival_context,
			reports_before_arrival,
			boundary_label,
		)
	}
	draw_text_fitted(arrival_context, R(850, 410, 360, 16), TYPE_MICRO, UX.dim)
	forecast := game.Fleet_Transfer_Forecast {
		cause = "Select a local body before setting a transfer.",
	}
	if local_target_count > 0 do forecast = game.fleet_transfer_forecast(c, s.navigation_target, arrival)
	forecast_ink := !forecast.valid ? UX.bad : forecast.crosses_reserve ? UX.warn : UX.good
	label_caps("3 · FORECAST", 720, 435, forecast_ink)
	draw_fmt(
		720,
		454,
		TYPE_FINE,
		UX.text,
		"DEPART %.2f KM/S · RENDEZVOUS %.2f KM/S",
		forecast.departure_delta_v_km_s,
		forecast.arrival_delta_v_km_s,
	)
	draw_fmt(
		720,
		474,
		TYPE_FINE,
		UX.text,
		"TOTAL ΔV %.2f KM/S · BURN %.1f KT",
		forecast.total_delta_v_km_s,
		forecast.propellant_cost_kt,
	)
	draw_fmt(
		720,
		494,
		TYPE_FINE,
		forecast_ink,
		"ARRIVAL %.1f KT · RESERVE MARGIN %+.1f KT",
		forecast.propellant_after_kt,
		forecast.reserve_margin_kt,
	)
	recovery_ink := forecast.recovery_shortfall_kt > 1e-9 ? UX.warn : UX.dim
	limiting_label := navigation_ship_label(c, forecast.limiting_ship)
	if !forecast.has_recovery_source do draw_fmt(720, 514, TYPE_FINE, UX.dim, "LIMITING %s · NO WATER SOURCE", limiting_label)
	else if forecast.expected_harvest_kt <= 1e-9 do draw_fmt(720, 514, TYPE_FINE, UX.warn, "LIMITING %s · SOURCE DEPLETED", limiting_label)
	else if forecast.recovery_shortfall_kt > 1e-9 do draw_fmt(720, 514, TYPE_FINE, recovery_ink, "LIMITING %s · SOURCE SHORT %.1f KT", limiting_label, forecast.recovery_shortfall_kt)
	else do draw_fmt(720, 514, TYPE_FINE, recovery_ink, "LIMITING %s · RECOVER %.1f KT / %.1f D", limiting_label, forecast.expected_harvest_kt, forecast.expected_harvest_days)
	draw_text_fitted(forecast.cause, R(720, 532, 490, 18), TYPE_FINE, forecast_ink)

	can_commit := c.fleet_navigation.phase == .Holding && forecast.valid
	commit_label := forecast.crosses_reserve ? "AUTHORIZE EMERGENCY LEG" : "COMMIT LEG"
	if button(R(720, 555, 238, 32), commit_label, can_commit) {
		ok, message := game.fleet_navigation_commit_transfer(c, forecast, forecast.crosses_reserve)
		s.status = message
		if ok do _ = game.campaign_set_speed(c, .One)
	}
	current_deposit := game.fleet_deposit_index(c, c.fleet_navigation.current_body)
	if current_deposit >= 0 {
		if button(R(970, 555, 32, 32), "−5") {
			s.navigation_harvest_fraction = max(.2, s.navigation_harvest_fraction - .05)
		}
		if button(R(1006, 555, 32, 32), "+5") {
			s.navigation_harvest_fraction = min(1, s.navigation_harvest_fraction + .05)
		}
		if button(R(1042, 555, 42, 32), "−30") {
			s.navigation_harvest_deadline_days = max(1, s.navigation_harvest_deadline_days - 30)
		}
		if button(R(1088, 555, 42, 32), "+30") {
			s.navigation_harvest_deadline_days += 30
		}
		draw_fmt(
			970,
			535,
			TYPE_FINE,
			UX.dim,
			"RECOVER %.0f%% · LEAVE +%.0f D",
			s.navigation_harvest_fraction * 100,
			s.navigation_harvest_deadline_days,
		)
		target_propellant := game.fleet_propellant_capacity(c) * s.navigation_harvest_fraction
		deadline := navigation_days_from_now(c, s.navigation_harvest_deadline_days)
		feedstock_target := game.fleet_feedstock_headroom(c)
		harvest := game.fleet_harvest_forecast(c, target_propellant, deadline, feedstock_target)
		if button(
			R(1134, 555, 76, 32),
			"RECOVER",
			c.fleet_navigation.phase == .Holding && harvest.valid,
		) {
			_, s.status = game.fleet_navigation_commit_harvest(
				c,
				target_propellant,
				deadline,
				feedstock_target,
			)
		}
	}

	if s.status != "" do draw_text_fitted(s.status, R(696, 607, 540, 20), TYPE_FINE, UX.dim)
	draw_campaign_underway_rail(s, "PLAN THE NEXT LEG · LET CAPTAINS EXECUTE ROUTINE WORK")
}
