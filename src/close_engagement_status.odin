package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"

combat_sidebar_rule :: proc(y: f32, label: string) {
	rl.DrawLineEx({1028, y}, {1248, y}, 1, UX.unavailable)
	rl.DrawLineEx({1028, y}, {1060, y}, 2, UX.dim)
	draw_text(label, 1028, y + 9, TYPE_MICRO, UX.dim)
}

combat_sidebar_meter :: proc(label: string, value: f32, y: f32, color: rl.Color) {
	clamped := clamp(value, 0, 100)
	draw_text(label, 1028, y, TYPE_MICRO, UX.dim)
	draw_fmt(1222, y, TYPE_MICRO, color, "%3d", int(clamped))
	bar := R(1028, y + 13, 220, 4)
	rl.DrawRectangleRec(bar, UX.unavailable)
	if clamped > 0 do rl.DrawRectangleRec(R(bar.x, bar.y, bar.width * clamped / 100, bar.height), color)
	// A hairline cap makes current state readable at a glance even on short bars.
	cap_x := bar.x + bar.width * clamped / 100
	rl.DrawLineEx({cap_x, bar.y - 1}, {cap_x, bar.y + bar.height + 1}, 1, UX.text)
}

combat_sidebar_hull_meter :: proc(m: ^game.Combat_Mission, u: ^game.Combat_Unit, y: f32) {
	aggregate := clamp(u.hull / max(u.max_hull, f32(1)) * 100, 0, 100)
	aggregate_color := aggregate < 35 ? UX.bad : aggregate < 70 ? UX.warn : UX.good
	draw_text("HULL INTEGRITY", 1028, y, TYPE_MICRO, UX.dim)
	draw_fmt(1222, y, TYPE_MICRO, aggregate_color, "%3d", int(aggregate))
	bar := R(1028, y + 13, 220, 4)
	count := max(u.formation_ships, 1)
	start := u.roster_start
	if start < 0 || start + count > len(m.ships) {
		rl.DrawRectangleRec(bar, UX.unavailable)
		if aggregate > 0 do rl.DrawRectangleRec(R(bar.x, bar.y, bar.width * aggregate / 100, bar.height), aggregate_color)
		return
	}
	gap: f32 = count > 1 ? 1 : 0
	cell_width := (bar.width - gap * f32(count - 1)) / f32(count)
	individual_max := u.max_hull / f32(count)
	for ship, index in m.ships[start:start + count] {
		x := bar.x + f32(index) * (cell_width + gap)
		ratio := clamp(ship.hull / max(individual_max, f32(.001)), 0, 1)
		ship_color := ratio <= 0 ? UX.bad : ratio < .35 ? UX.bad : ratio < .7 ? UX.warn : UX.good
		rl.DrawRectangleRec(R(x, bar.y, cell_width, bar.height), UX.unavailable)
		if ratio > 0 do rl.DrawRectangleRec(R(x, bar.y, cell_width * ratio, bar.height), ship_color)
	}
}

combat_action_label :: proc(action: game.Combat_Action) -> string {
	switch action {
	case .Holding:
		return "HOLDING"
	case .Navigating:
		return "NAVIGATING"
	case .Screening:
		return "SCREENING"
	case .Capturing:
		return "CAPTURING"
	case .Attack_Run:
		return "ATTACK RUN"
	case .Repositioning:
		return "REPOSITIONING"
	case .Disengaging:
		return "DISENGAGING"
	case .Repairing:
		return "REPAIRING"
	case .Extracting:
		return "EXTRACTING"
	}
	return "AWAITING REPORT"
}

combat_weapon_package_label :: proc(value: game.Ship_Weapon_Package) -> string {
	switch value {
	case .Chemical_Autocannon:
		return "AUTOCANNON"
	case .Coilgun_Battery:
		return "COILGUN"
	case .Railgun_Battery:
		return "RAILGUN"
	case .Defensive_Laser:
		return "DEF LASER"
	case .Offensive_Laser:
		return "LASER"
	case .Guided_Missiles:
		return "GUIDED MISSILES"
	case .Heavy_Torpedoes:
		return "HEAVY TORPEDOES"
	case .Unspecified:
		return "UNARMED"
	}
	return "UNARMED"
}

combat_contact_assessment_label :: proc(assessment: game.Combat_Assessment) -> string {
	switch assessment {
	case .Apparently_Damaged:
		return "DAMAGE INDICATED"
	case .Confirmed_Disabled:
		return "DISABLED"
	case .Unassessed:
		return "UNASSESSED"
	}
	return "UNASSESSED"
}

combat_sidebar_solution :: proc(solution: f32, assessment: string, y: f32) {
	quality := clamp(solution, 0, 100)
	color := quality >= 70 ? UX.bad : quality >= 35 ? UX.warn : UX.dim
	draw_fmt(1028, y, TYPE_FINE, color, "SOLUTION  %.0f%%", quality)
	draw_text_fitted(assessment, R(1124, y, 124, 16), TYPE_FINE, color)
	bar := R(1028, y + 14, 220, 3)
	rl.DrawRectangleRec(bar, UX.unavailable)
	if quality > 0 do rl.DrawRectangleRec(R(bar.x, bar.y, bar.width * quality / 100, bar.height), color)
}

combat_sidebar_alert_rail :: proc(color: rl.Color) {
	rl.DrawRectangleRec(R(1012, 116, 3, 234), color)
	rl.DrawRectangleRec(R(1012, 116, 14, 2), color)
	rl.DrawRectangleRec(R(1012, 348, 14, 2), color)
}

combat_sidebar_dual_progress :: proc(
	y: f32,
	left_label, right_label: string,
	left_value, right_value: f32,
	left_color, right_color: rl.Color,
) {
	cell_width: f32 = 106
	gap: f32 = 8
	// Kept explicit so the two semantic channels remain easy to audit.
	draw_text(left_label, 1028, y, TYPE_MICRO_TIGHT, left_color)
	left_value_text := fmt.tprintf("%.0f%%", left_value)
	draw_text(
		left_value_text,
		1028 + cell_width - measure_text(left_value_text, TYPE_MICRO_TIGHT).x,
		y,
		TYPE_MICRO_TIGHT,
		left_color,
	)
	draw_text(right_label, 1028 + cell_width + gap, y, TYPE_MICRO_TIGHT, right_color)
	right_value_text := fmt.tprintf("%.0f%%", right_value)
	draw_text(
		right_value_text,
		1248 - measure_text(right_value_text, TYPE_MICRO_TIGHT).x,
		y,
		TYPE_MICRO_TIGHT,
		right_color,
	)
	left_bar := R(1028, y + 13, cell_width, 3)
	right_bar := R(1028 + cell_width + gap, y + 13, cell_width, 3)
	rl.DrawRectangleRec(left_bar, UX.unavailable); rl.DrawRectangleRec(right_bar, UX.unavailable)
	rl.DrawRectangleRec(
		R(
			left_bar.x,
			left_bar.y,
			left_bar.width * clamp(left_value, 0, 100) / 100,
			left_bar.height,
		),
		left_color,
	)
	rl.DrawRectangleRec(
		R(
			right_bar.x,
			right_bar.y,
			right_bar.width * clamp(right_value, 0, 100) / 100,
			right_bar.height,
		),
		right_color,
	)
}


combat_draw_status_panel :: proc(s: ^Ux_State) {
	label_caps("COMMAND ELEMENT", 1028, 91)
	selected_count := 0
	focus_ordinal := 0
	for element, index in s.combat.units[:s.combat.friendly_count] do if element.selected {
		selected_count += 1
		if index == s.combat_selected do focus_ordinal = selected_count
	}
	if selected_count > 1 {
		if button(R(1172, 84, 24, 22), "<") do _ = combat_focus_step(s, -1)
		if button(R(1224, 84, 24, 22), ">") do _ = combat_focus_step(s, 1)
		focus_ordinal = 0
		for element, index in s.combat.units[:s.combat.friendly_count] do if element.selected {
			focus_ordinal += 1
			if index == s.combat_selected do break
		}
		draw_fmt(1210, 94, TYPE_MICRO, UX.info, "%d/%d", focus_ordinal, selected_count)
	} else {
		draw_fmt(1248, 94, TYPE_MICRO, UX.dim, "%d SEL", selected_count)
	}
	sel := clamp(s.combat_selected, 0, s.combat.friendly_count - 1); u := &s.combat.units[sel]
	draw_ship_hull_archetype_icon(u.hull_archetype, R(1028, 116, 48, 48), UX.text)
	draw_text_fitted(u.name, R(1086, 116, 162, 25), TYPE_SUBHEADING_COMPACT, UX.text)
	draw_text_fitted(
		fmt.tprintf("%s · %s", u.commander, game.ship_operational_role_name(u.operational_role)),
		R(1086, 145, 162, 18),
		TYPE_SMALL,
		UX.info,
	)
	order_color := u.order == .Withdraw || u.order == .Extract ? UX.warn : UX.text
	group_plan := s.combat.groups[clamp(u.group, 0, game.COMBAT_GROUP_COUNT - 1)]
	draw_text_fitted(
		fmt.tprintf(
			"%v · %s",
			group_plan.maneuver,
			game.combat_maneuver_reason_name(group_plan.maneuver_reason),
		),
		R(1028, 166, 220, 14),
		TYPE_MICRO_TIGHT,
		order_color,
	)
	ability_name := game.combat_ship_ability_name(game.combat_ship_ability(u^))
	ability_state :=
		u.ability_charges <= 0 ? "--" : u.ability_cooldown > 0 ? fmt.tprintf("%.0fs", u.ability_cooldown) : fmt.tprintf("%dx", u.ability_charges)
	ability_summary_color :=
		u.ability_charges <= 0 ? UX.unavailable : u.ability_cooldown > 0 ? UX.dim : UX.info
	draw_text_fitted(
		fmt.tprintf("Q  %s", ability_name),
		R(1028, 181, 188, 14),
		TYPE_MICRO_TIGHT,
		ability_summary_color,
	)
	state_width := measure_text(ability_state, TYPE_MICRO_TIGHT).x
	draw_text(ability_state, 1248 - state_width, 181, TYPE_MICRO_TIGHT, ability_summary_color)
	pressure_color := u.pressure >= 65 ? UX.bad : u.pressure >= 35 ? UX.warn : UX.info
	combat_sidebar_hull_meter(&s.combat, u, 197)
	combat_sidebar_meter(game.combat_pressure_state(u^), u.pressure, 221, pressure_color)
	weapon_state :=
		u.weapon_cooldown > 0 ? fmt.tprintf("WPN %.1fs", u.weapon_cooldown) : "WPN READY"
	signature_value := game.combat_signature_percent(u^)
	combat_sidebar_meter(
		fmt.tprintf(
			"%s · %s",
			game.combat_exposure_state_name(u^),
			game.combat_signature_cause(u^),
		),
		signature_value,
		245,
		signature_value >= 65 ? UX.bad : UX.info,
	)
	ship_strength :=
		u.formation_ships > 0 ? f32(u.formation_active) / f32(u.formation_ships) : f32(0)
	craft_strength := u.max_craft > 0 ? f32(u.craft) / f32(u.max_craft) : f32(1)
	ships_color := ship_strength < .5 ? UX.bad : ship_strength < 1 ? UX.warn : UX.text
	craft_color := craft_strength < .5 ? UX.bad : craft_strength < 1 ? UX.warn : UX.text
	readiness_color := u.readiness < 35 ? UX.bad : u.readiness < 65 ? UX.warn : UX.info
	cohesion_color := u.cohesion < 35 ? UX.bad : u.cohesion < 65 ? UX.warn : UX.info
	draw_fmt(
		1028,
		274,
		TYPE_MICRO,
		ships_color,
		"SHIPS  %02d/%02d",
		u.formation_active,
		u.formation_ships,
	)
	draw_fmt(1138, 274, TYPE_MICRO, craft_color, "CRAFT  %02d/%02d", u.craft, u.max_craft)
	draw_fmt(1028, 291, TYPE_MICRO, readiness_color, "RDY %03d", int(u.readiness))
	draw_fmt(1098, 291, TYPE_MICRO, cohesion_color, "COH %03d", int(u.cohesion))
	stores_color := u.chaff + u.flares + u.decoys + u.torpedoes > 0 ? UX.warn : UX.dim
	draw_text_fitted(
		fmt.tprintf("CM %d/%d/%d · T %d", u.chaff, u.flares, u.decoys, u.torpedoes),
		R(1148, 291, 100, 16),
		TYPE_MICRO,
		stores_color,
	)
	primary := game.combat_unit_primary_weapon(u^)
	defense_state :=
		u.defense_cooldown > 0 ? fmt.tprintf("DEF %.0fs", u.defense_cooldown) : "DEF READY"
	defense_color := u.defense_cooldown > 0 ? UX.warn : UX.good
	draw_text_fitted(
		fmt.tprintf("WPN  %s", combat_weapon_package_label(primary)),
		R(1028, 311, 142, 16),
		TYPE_FINE,
		UX.info,
	)
	defense_width := measure_text(defense_state, TYPE_FINE).x
	draw_text(defense_state, 1248 - defense_width, 311, TYPE_FINE, defense_color)
	draw_text_fitted(
		fmt.tprintf("%s · %v CAPTAIN", u.trait, u.captain_trait),
		R(1028, 328, 220, 18),
		TYPE_SMALL_EMPHASIS,
		UX.warn,
	)
	defense_active := u.defense_response != "" && u.defense_cooldown > 0
	defense_detail := defense_active ? u.defense_response : u.history
	defense_detail_color :=
		!defense_active ? UX.dim : u.defense_response == "Terminal evasion failed" ? UX.bad : u.defense_response == "Emergency defense committed" ? UX.warn : UX.good
	draw_text_fitted(defense_detail, R(1028, 347, 220, 16), TYPE_LABEL, defense_detail_color)
	combat_sidebar_rule(360, "TACTICAL NETWORK")
	command := game.combat_command_state(&s.combat, .Friendly)
	status_y: f32 = 383
	draw_fmt(
		1028,
		status_y,
		TYPE_FINE,
		UX.text,
		"INTENT  %v",
		u.maneuver_intent,
	); status_y += 18
	draw_fmt(1028, status_y, TYPE_FINE, UX.info, "SENSORS  %v · HEAT %.0f%%", u.sensor_mode, u.weapon_heat)
	status_y += 18
	if u.trajectory_forecast.valid {
		draw_text_fitted(
			fmt.tprintf(
				"ARRIVAL  %s · BURN %s",
				game.combat_format_duration(f32(u.trajectory_forecast.time_to_closest_minutes)),
				game.combat_format_duration(f32(u.trajectory_forecast.burn_minutes)),
			),
			R(1028, status_y, 220, 16),
			TYPE_FINE,
			UX.warn,
		)
		status_y += 18
	}
	target_index := u.engagement_target >= 0 ? u.engagement_target : u.target
	if target_index >= 0 && target_index < s.combat.unit_count {
		target_name := s.combat.units[target_index].name
		target_position := s.combat.units[target_index].position
		solution: f32 = 100
		assessment := "VISUAL CONFIRM"
		if s.combat.units[target_index].side == .Raider {
			trace := game.combat_contact_trace(&s.combat, .Friendly, target_index)
			target_name = game.combat_contact_display_name(trace^)
			target_position, _ = game.combat_contact_position(&s.combat, .Friendly, target_index)
			solution = trace.solution_quality * 100
			assessment = combat_contact_assessment_label(trace.assessment)
		}
		distance := game.combat_distance(u.position, target_position)
		draw_text_fitted(
			fmt.tprintf("CONTACT  %s · %s", target_name, game.combat_format_distance(distance)),
			R(1028, status_y, 220, 16),
			TYPE_FINE,
			UX.bad,
		)
		status_y += 18
		combat_sidebar_solution(solution, assessment, status_y)
	} else {
		draw_fmt(
			1028,
			status_y,
			TYPE_FINE,
			UX.dim,
			"VECTOR  %s",
			game.combat_location_label(s.combat.grid, u.destination),
		)
		status_y += 18
		combat_sidebar_solution(0, "NO CONTACT", status_y)
	}
	status_y += 20
	inbound_count := 0
	tracking_count := 0
	impact_time: f32 = 999
	for salvo in s.combat.salvos do if game.combat_salvo_warning_actionable(salvo) && salvo.target == sel && salvo.side != u.side {
		inbound_count += 1
		impact_time = min(impact_time, salvo.time_remaining)
	}
	for hostile in s.combat.units[s.combat.friendly_count:s.combat.unit_count] do if !hostile.disabled && !hostile.extracted && (hostile.target == sel || hostile.engagement_target == sel) do tracking_count += 1
	if inbound_count > 0 || u.impact_flash > 0 || u.hull / u.max_hull < .35 || u.pressure >= 65 {
		combat_sidebar_alert_rail(UX.bad)
	} else if tracking_count > 0 || u.hull / u.max_hull < .7 || u.pressure >= 35 {
		combat_sidebar_alert_rail(UX.warn)
	}
	if inbound_count > 0 {
		draw_text_fitted(
			fmt.tprintf("THREAT  %d INBOUND · %s", inbound_count, game.combat_format_duration(impact_time)),
			R(1028, status_y, 220, 16),
			TYPE_FINE,
			UX.bad,
		)
		danger := 1 - clamp(impact_time / 30, 0, 1)
		threat_bar := R(1028, status_y + 14, 220, 3)
		rl.DrawRectangleRec(threat_bar, UX.unavailable)
		if danger > 0 do rl.DrawRectangleRec(R(threat_bar.x, threat_bar.y, threat_bar.width * danger, threat_bar.height), UX.bad)
		cap_x := threat_bar.x + threat_bar.width * danger
		rl.DrawLineEx(
			{cap_x, threat_bar.y - 1},
			{cap_x, threat_bar.y + threat_bar.height + 1},
			1,
			UX.text,
		)
	} else if tracking_count > 0 {
		draw_fmt(
			1028,
			status_y,
			TYPE_FINE,
			UX.warn,
			"THREAT  %d ELEMENTS TRACKING",
			tracking_count,
		)
	} else {
		draw_text("THREAT  NO INBOUND TRACKS", 1028, status_y, TYPE_FINE, UX.good)
	}
	status_y += 18
	draw_fmt(
		1028,
		status_y,
		TYPE_FINE,
		UX.info,
		"FIRE  %v · FF %.0f%%",
		s.combat.fire_control,
		game.combat_friendly_fire_tolerance(u^) * 100,
	); status_y += 18
	if !command.command_ship_active {draw_fmt(1028, status_y, TYPE_CAPTION, UX.warn, "COMMAND DEGRADED  +%.0fs", command.report_delay); status_y += 20}
	combat_sidebar_rule(status_y + 2, "MISSION PROGRESS")
	status_y += 25
	if s.combat.skirmish {
		for objective in s.combat.skirmish_objectives.objectives[:s.combat.skirmish_objectives.count] {
			role := objective.optional ? "OPTIONAL" : "PRIMARY"
			draw_text_fitted(
				fmt.tprintf("%s · %s", role, game.skirmish_objective_name(objective.kind)),
				R(1028, status_y, 220, 14),
				TYPE_MICRO,
				objective.optional ? UX.dim : UX.info,
			)
			draw_text_fitted(
				game.skirmish_objective_status(&s.combat, objective.kind),
				R(1028, status_y + 13, 220, 14),
				TYPE_MICRO,
				UX.text,
			)
			status_y += 29
		}
	}
	if s.combat.scenario == .Finale {
		asset := s.combat.strategic_asset
		draw_text_fitted(
			fmt.tprintf(
				"RELAYS %.0f / %.0f · %v",
				s.combat.relay_progress[0],
				s.combat.relay_progress[1],
				s.combat.finale_phase,
			),
			R(1028, status_y, 220, 18),
			TYPE_LABEL,
			asset.disabled ? UX.good : UX.warn,
		)
		status_y += 20
		draw_text_wrapped(
			fmt.tprintf(
				"WEAPON %.0f%% · EXPOSED %.0fs · DISABLE %.0f%%",
				asset.charge / game.COMBAT_FINALE_BEAM_CYCLE * 100,
				asset.exposure_remaining,
				asset.disable_progress,
			),
			R(1028, status_y, 220, 34),
			TYPE_LABEL,
			asset.exposure_remaining > 0 ? UX.committed : UX.bad,
		)
		status_y += 39
	} else if game.combat_is_fleet_engagement(&s.combat) {
		active_hostile, hostile_total := 0, 0
		for hostile in s.combat.units[s.combat.friendly_count:s.combat.unit_count] {
			hostile_total += hostile.formation_ships
			active_hostile += hostile.formation_active
		}
		draw_text_fitted(
			fmt.tprintf("OPPOSING SHIPS  %d / %d", active_hostile, hostile_total),
			R(1028, status_y, 220, 18),
			TYPE_LABEL,
			active_hostile == 0 ? UX.good : UX.warn,
		)
		status_y += 20
		draw_text(
			"WITHDRAWAL OPENS AT 10:00",
			1028,
			status_y,
			TYPE_LABEL,
			s.combat.extraction_mandatory ? UX.good : UX.info,
		)
		status_y += 24
	} else {
		combat_sidebar_dual_progress(
			status_y,
			"RELAY A",
			"RELAY B",
			s.combat.relay_progress[0],
			s.combat.relay_progress[1],
			UX.info,
			UX.info,
		); status_y += 20
		if s.combat.seedship_found {
			recovery_state := s.combat.population_recovered ? "POP" : "STABILIZE"
			combat_sidebar_dual_progress(
				status_y,
				recovery_state,
				"ANOMALY",
				s.combat.recovery_progress,
				s.combat.anomaly_progress,
				s.combat.population_recovered ? UX.good : UX.warn,
				UX.committed,
			)
		} else do draw_text("SEEDSHIP  NOT LOCATED", 1028, status_y, TYPE_LABEL, UX.warn)
		status_y += 24
	}
	combat_sidebar_rule(status_y, "LIVE ACTION LOG")
	if s.combat.event_count > 0 {
		latest_seconds := int(max(s.combat.event_time[0], 0))
		latest_stamp := fmt.tprintf("T+%02d:%02d", latest_seconds / 60, latest_seconds % 60)
		draw_text(
			latest_stamp,
			1248 - measure_text(latest_stamp, TYPE_MICRO).x,
			status_y + 9,
			TYPE_MICRO,
			UX.info,
		)
	}
	event_y := status_y + 24
	// Event copy may wrap to more lines than remain inside the command panel.
	// Clip only the scrolling body so the section title, timestamp, and panel
	// frame remain crisp and unobstructed.
	event_clip := R(1027, event_y, 222, max(f32(606) - event_y, f32(0)))
	if event_clip.height > 0 do rl.BeginScissorMode(event_clip)
	for text, i in s.combat.event_text[:min(s.combat.event_count, 3)] {
		if event_y >= 606 do break
		start_y := event_y
		text_x := i == 0 ? f32(1037) : f32(1034)
		event_y = draw_text_wrapped(
			text,
			R(text_x, event_y, 1248 - text_x, 606 - event_y),
			TYPE_LABEL,
			i == 0 ? UX.text : UX.dim,
		)
		if i == 0 {
			rl.DrawRectangleRec(R(1028, start_y, 2, max(event_y - start_y - 2, f32(8))), UX.info)
		} else {
			rl.DrawRectangleRec(R(1028, start_y + 5, 2, 2), UX.dim)
		}
		event_y += 7
	}
	if event_clip.height > 0 do rl.EndScissorMode()
}
