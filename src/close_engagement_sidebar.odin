package main

import game "../packages/game"
import "core:fmt"
import "core:testing"
import rl "zelda_engine:canvas2d"

combat_group_selected :: proc(s: ^Ux_State, group: int) -> bool {
	for u in s.combat.units[:s.combat.friendly_count] do if u.group == group && u.selected do return true
	return false
}

combat_group_fully_selected :: proc(s: ^Ux_State, group: int) -> bool {
	found := false
	for u in s.combat.units[:s.combat.friendly_count] do if u.group == group {
		found = true
		if !u.selected do return false
	}
	return found
}

combat_selected_group_count :: proc(s: ^Ux_State) -> int {
	count := 0
	for group in 0 ..< game.COMBAT_GROUP_COUNT do if combat_group_selected(s, group) do count += 1
	return count
}

combat_toggle_group :: proc(s: ^Ux_State, group: int) {
	selected := combat_group_fully_selected(s, group)
	for &u, i in s.combat.units[:s.combat.friendly_count] do if u.group == group {
		u.selected = !selected
		if !selected do s.combat_selected = i
	}
	if selected do for u, i in s.combat.units[:s.combat.friendly_count] do if u.selected {
		s.combat_selected = i
		break
	}
}

combat_focus_selected :: proc(s: ^Ux_State, fallback: int) -> bool {
	for u, i in s.combat.units[:s.combat.friendly_count] do if u.selected {s.combat_selected = i; return true}
	s.combat_selected = clamp(fallback, 0, max(s.combat.friendly_count - 1, 0)); return false
}

combat_focus_step :: proc(s: ^Ux_State, direction: int) -> bool {
	if s.combat.friendly_count <= 0 || direction == 0 do return false
	start := clamp(s.combat_selected, 0, s.combat.friendly_count - 1)
	for offset in 1 ..= s.combat.friendly_count {
		index := (start + direction * offset) % s.combat.friendly_count
		if index < 0 do index += s.combat.friendly_count
		if s.combat.units[index].selected {
			s.combat_selected = index
			return index != start
		}
	}
	return false
}

combat_select_unit :: proc(s: ^Ux_State, index: int, additive: bool) {
	if index < 0 || index >= s.combat.friendly_count do return
	if !additive {for &u in s.combat.units[:s.combat.friendly_count] do u.selected = false; s.combat.units[index].selected = true; s.combat_selected = index; return}
	s.combat.units[index].selected = !s.combat.units[index].selected
	if s.combat.units[index].selected {s.combat_selected = index} else do _ = combat_focus_selected(s, index)
}

combat_select_group :: proc(s: ^Ux_State, group: int, additive: bool) {
	if additive {
		combat_toggle_group(s, group)
		return
	}
	for &u, i in s.combat.units[:s.combat.friendly_count] {
		u.selected = u.group == group
		if u.selected do s.combat_selected = i
	}
}

combat_selected_ship_count :: proc(s: ^Ux_State) -> (active, total: int) {
	for u in s.combat.units[:s.combat.friendly_count] do if u.selected {
		active += u.formation_active
		total += u.formation_ships
	}
	return
}

combat_selected_stance :: proc(s: ^Ux_State) -> (stance: game.Combat_Stance, mixed, found: bool) {
	for unit in s.combat.units[:s.combat.friendly_count] do if unit.selected {
		if !found {
			stance = unit.stance
			found = true
		} else if unit.stance != stance {
			mixed = true
		}
	}
	return
}

combat_set_selected_stance :: proc(s: ^Ux_State, stance: game.Combat_Stance) {
	for unit, index in s.combat.units[:s.combat.friendly_count] do if unit.selected {
		game.combat_set_stance(&s.combat, index, stance)
	}
}

combat_unit_command_label :: proc(s: ^Ux_State, unit: ^game.Combat_Unit) -> string {
	action := game.combat_command_action(unit.order)
	switch action {
	case .Hold:
		return "Hold"
	case .Move:
		return "Move"
	case .Attack:
		return "Attack"
	case .Withdraw:
		return "Withdraw"
	case .Act:
		// The simulation keeps a general Act command; the presentation should
		// report the mission verb that caused it rather than exposing that
		// implementation detail to the player.
		for interaction in s.combat.interactions[:s.combat.interaction_count] {
			if game.combat_distance(unit.destination, interaction.position) < 1 do return interaction.verb
		}
		if unit.order == .Recover {
			if unit.target >= 0 && unit.target < s.combat.friendly_count && s.combat.units[unit.target].disabled do return "Rescue"
			return "Recover"
		}
		return "Act"
	}
	return "Hold"
}

@(test)
combat_group_click_replaces_and_shift_click_toggles :: proc(t: ^testing.T) {
	s := ux_state_create(
		
	); defer ux_state_destroy(s); s.combat.units = make([dynamic]game.Combat_Unit, 3); defer delete(s.combat.units); s.combat.friendly_count = 3; s.combat.unit_count = 3; s.combat.units[0].group = 0; s.combat.units[1].group = 1; s.combat.units[2].group = 1
	combat_select_group(
		s,
		1,
		false,
	); testing.expect(t, !s.combat.units[0].selected && s.combat.units[1].selected && s.combat.units[2].selected)
	combat_select_group(
		s,
		0,
		true,
	); testing.expect(t, s.combat.units[0].selected && s.combat.units[1].selected && s.combat.units[2].selected)
	combat_select_group(
		s,
		1,
		true,
	); testing.expect(t, s.combat.units[0].selected && !s.combat.units[1].selected && !s.combat.units[2].selected)
	combat_select_group(
		s,
		0,
		true,
	); testing.expect(t, !s.combat.units[0].selected && !s.combat.units[1].selected && !s.combat.units[2].selected)
}

@(test)
combat_ship_click_replaces_and_shift_click_toggles :: proc(t: ^testing.T) {
	s := ux_state_create(
		
	); defer ux_state_destroy(s); s.combat.units = make([dynamic]game.Combat_Unit, 3); defer delete(s.combat.units); s.combat.friendly_count = 3; s.combat.unit_count = 3
	combat_select_unit(
		s,
		1,
		false,
	); testing.expect(t, !s.combat.units[0].selected && s.combat.units[1].selected && !s.combat.units[2].selected)
	combat_select_unit(
		s,
		2,
		true,
	); testing.expect(t, s.combat.units[1].selected && s.combat.units[2].selected); testing.expect_value(t, s.combat_selected, 2)
	combat_select_unit(
		s,
		2,
		true,
	); testing.expect(t, s.combat.units[1].selected && !s.combat.units[2].selected); testing.expect_value(t, s.combat_selected, 1)
	combat_select_unit(s, 1, true); testing.expect(t, !s.combat.units[1].selected)
}

@(test)
combat_focus_cycle_preserves_multi_selection :: proc(t: ^testing.T) {
	s := ux_state_create(); defer ux_state_destroy(s)
	s.combat.units = make([dynamic]game.Combat_Unit, 4); defer delete(s.combat.units)
	s.combat.friendly_count = 4; s.combat.unit_count = 4
	s.combat.units[0].selected =
		true; s.combat.units[2].selected = true; s.combat.units[3].selected = true
	s.combat_selected = 0
	testing.expect(t, combat_focus_step(s, 1)); testing.expect_value(t, s.combat_selected, 2)
	testing.expect(t, combat_focus_step(s, 1)); testing.expect_value(t, s.combat_selected, 3)
	testing.expect(t, combat_focus_step(s, 1)); testing.expect_value(t, s.combat_selected, 0)
	testing.expect(t, combat_focus_step(s, -1)); testing.expect_value(t, s.combat_selected, 3)
	testing.expect(
		t,
		s.combat.units[0].selected && s.combat.units[2].selected && s.combat.units[3].selected,
	)
}

combat_command_button :: proc(
	rect: rl.Rectangle,
	label, title, explanation: string,
	enabled := true,
	active := false,
	severity := 0,
	hotkey := "",
) -> bool {
	activated := button(rect, hotkey == "" ? label : "", enabled, active)
	if hotkey != "" {
		key_color := enabled ? (active ? UX.info : UX.dim) : UX.unavailable
		key_rect := R(rect.x + 7, rect.y + (rect.height - 16) / 2, 12, 16)
		rl.DrawRectangleRoundedLinesEx(key_rect, 0, 1, 1, key_color)
		key_text_rect := R(key_rect.x + 2, key_rect.y + 2, key_rect.width - 4, key_rect.height - 4)
		draw_text_fitted(hotkey, key_text_rect, TYPE_MICRO_TIGHT, key_color)
		draw_text_fitted(
			label,
			R(rect.x + 21, rect.y, rect.width - 25, rect.height),
			TYPE_LABEL,
			enabled ? UX.text : UX.unavailable,
		)
	}
	if enabled && severity > 0 {
		color := severity > 1 ? UX.bad : UX.warn
		rl.DrawRectangleRec(R(rect.x, rect.y, 3, rect.height), color)
		accent_x := hotkey == "" ? rect.x + 7 : rect.x + 4
		rl.DrawLineEx(V(accent_x, rect.y + 4), V(accent_x, rect.y + rect.height - 4), 1, color)
	}
	if rl.CheckCollisionPointRec(ux_mouse, rect) {
		ux_tooltip = {
			visible = true,
			anchor  = rect,
			title   = title,
			body    = explanation,
		}
	}
	return activated
}

combat_stance_selector :: proc(
	s: ^Ux_State,
	rect: rl.Rectangle,
	enabled: bool,
	selected: game.Combat_Stance,
	mixed: bool,
) {
	segment_width := rect.width / 3
	rl.DrawRectangleRec(rect, enabled ? UX.raised : UX.void)

	for i in 0 ..< 3 {
		stance := game.Combat_Stance(i)
		segment := R(rect.x + f32(i) * segment_width, rect.y, segment_width, rect.height)
		index := ux_button_cursor
		ux_button_cursor += 1
		interaction := rl.ButtonBehavior(index, segment, enabled)
		active := enabled && !mixed && selected == stance
		if active {
			rl.DrawRectangleRec(
				R(segment.x + 1, segment.y + 1, segment.width - 2, segment.height - 2),
				rl.Color{38, 67, 69, 255},
			)
			rl.DrawRectangleRec(
				R(segment.x + 1, segment.y + segment.height - 3, segment.width - 2, 2),
				UX.info,
			)
		} else if interaction.hovered || interaction.focused {
			rl.DrawRectangleRec(
				R(segment.x + 1, segment.y + 1, segment.width - 2, segment.height - 2),
				rl.Color{32, 32, 29, 255},
			)
		}

		glyph_color :=
			!enabled ? UX.unavailable : active ? UX.info : interaction.hovered ? UX.text : UX.dim
		cx := segment.x + segment.width / 2
		gy := segment.y + 9
		switch stance {
		case .Engage:
			rl.DrawLineEx(V(cx - 8, gy - 3), V(cx - 2, gy + 2), 1, glyph_color)
			rl.DrawLineEx(V(cx + 8, gy - 3), V(cx + 2, gy + 2), 1, glyph_color)
			rl.DrawLineEx(V(cx - 2, gy + 2), V(cx + 2, gy + 2), 2, glyph_color)
		case .Screen:
			rl.DrawLineEx(V(cx - 8, gy - 3), V(cx - 8, gy + 3), 1, glyph_color)
			rl.DrawLineEx(V(cx - 8, gy - 3), V(cx - 4, gy - 3), 1, glyph_color)
			rl.DrawLineEx(V(cx - 8, gy + 3), V(cx - 4, gy + 3), 1, glyph_color)
			rl.DrawLineEx(V(cx + 8, gy - 3), V(cx + 8, gy + 3), 1, glyph_color)
			rl.DrawLineEx(V(cx + 4, gy - 3), V(cx + 8, gy - 3), 1, glyph_color)
			rl.DrawLineEx(V(cx + 4, gy + 3), V(cx + 8, gy + 3), 1, glyph_color)
			rl.DrawRectangleRec(R(cx - 1, gy - 1, 2, 2), glyph_color)
		case .Evade:
			rl.DrawLineEx(V(cx - 2, gy), V(cx - 8, gy - 4), 1, glyph_color)
			rl.DrawLineEx(V(cx - 2, gy), V(cx - 8, gy + 4), 1, glyph_color)
			rl.DrawLineEx(V(cx + 2, gy), V(cx + 8, gy - 4), 1, glyph_color)
			rl.DrawLineEx(V(cx + 2, gy), V(cx + 8, gy + 4), 1, glyph_color)
		}

		label := stance == .Engage ? "ENGAGE" : stance == .Screen ? "SCREEN" : "EVADE"
		label_width := measure_text(label, TYPE_MICRO_TIGHT).x
		draw_text(
			label,
			cx - label_width / 2,
			segment.y + 15,
			TYPE_MICRO_TIGHT,
			enabled ? UX.text : UX.unavailable,
		)

		if interaction.hovered {
			title :=
				stance == .Engage ? "ENGAGE STANCE" : stance == .Screen ? "SCREEN STANCE" : "EVADE STANCE"
			body :=
				stance == .Engage ? "Fight valid contacts using doctrine priority and pursuit limits." : stance == .Screen ? "Prioritize strike craft and threats close to the formation's current work." : "Continue the current action while avoiding optional engagements."
			ux_tooltip = {
				visible = true,
				anchor  = segment,
				title   = title,
				body    = body,
			}
		}
		if interaction.activated do combat_set_selected_stance(s, stance)
	}

	for i in 1 ..< 3 {
		x := rect.x + f32(i) * segment_width
		rl.DrawLineEx(
			V(x, rect.y + 4),
			V(x, rect.y + rect.height - 4),
			1,
			enabled ? UX.line : UX.unavailable,
		)
	}
	rl.DrawRectangleRoundedLinesEx(rect, 0, 1, 1, enabled ? UX.line : UX.unavailable)
}

combat_draw_group_hulls :: proc(
	s: ^Ux_State,
	group, ship_total: int,
	bar: rl.Rectangle,
	aggregate_ratio: f32,
) {
	segmented := ship_total > 0 && ship_total <= 12 && s.combat.ships != nil
	if segmented do for u in s.combat.units[:s.combat.friendly_count] do if u.group == group {
		if u.roster_start < 0 || u.roster_start + u.formation_ships > len(s.combat.ships) {
			segmented = false
			break
		}
	}
	if !segmented {
		color := aggregate_ratio < .4 ? UX.bad : aggregate_ratio < .7 ? UX.warn : UX.info
		rl.DrawRectangleRec(bar, UX.unavailable)
		rl.DrawRectangleRec(
			R(bar.x, bar.y, bar.width * clamp(aggregate_ratio, 0, 1), bar.height),
			color,
		)
		for division in 1 ..= 3 {
			x := bar.x + bar.width * f32(division) / 4
			rl.DrawRectangleRec(R(x, bar.y, 1, bar.height), UX.void)
		}
		return
	}
	gap: f32 = 1
	segment_width := max((bar.width - gap * f32(ship_total - 1)) / f32(ship_total), 2)
	slot := 0
	for u in s.combat.units[:s.combat.friendly_count] do if u.group == group {
		individual_max := u.max_hull / f32(max(u.formation_ships, 1))
		for ship in s.combat.ships[u.roster_start:u.roster_start + u.formation_ships] {
			x := bar.x + f32(slot) * (segment_width + gap)
			segment := R(x, bar.y, segment_width, bar.height)
			ratio := clamp(ship.hull / max(individual_max, 1), 0, 1)
			color := ratio <= 0 ? UX.bad : ratio < .4 ? UX.bad : ratio < .7 ? UX.warn : UX.info
			if ratio <= 0 {
				rl.DrawRectangleRec(segment, rl.Color{UX.bad.r, UX.bad.g, UX.bad.b, 42})
				rl.DrawLineEx(V(segment.x, segment.y + segment.height), V(segment.x + segment.width, segment.y), 1, UX.bad)
			} else {
				rl.DrawRectangleRec(segment, UX.unavailable)
				rl.DrawRectangleRec(R(segment.x, segment.y, segment.width * ratio, segment.height), color)
			}
			slot += 1
		}
	}
}

combat_group_list :: proc(s: ^Ux_State, rect: rl.Rectangle, row_height: f32, scroll: ^f32) {
	content_height := f32(game.COMBAT_GROUP_COUNT) * row_height
	max_scroll := max(content_height - rect.height, 0)
	if rl.CheckCollisionPointRec(ux_mouse, rect) {
		scroll^ = clamp(scroll^ - rl.GetMouseWheelMove() * row_height, 0, max_scroll)
	} else {
		scroll^ = clamp(scroll^, 0, max_scroll)
	}
	rl.BeginScissorMode(rect)
	for group in 0 ..< game.COMBAT_GROUP_COUNT {
		y := rect.y + f32(group) * row_height - scroll^
		row := R(rect.x, y, rect.width - (max_scroll > 0 ? 8 : 0), row_height - 5)
		if y + row_height < rect.y || y > rect.y + rect.height do continue
		selected := combat_group_selected(s, group)
		hovered := rl.CheckCollisionPointRec(ux_mouse, row)
		active, ships, elements := 0, 0, 0
		hull, max_hull, pressure, readiness, cohesion: f32
		inbound_count := 0
		impact_time: f32 = 999
		disabled, withdrawing := false, false
		mixed_actions, mixed_stances := false, false
		action := game.Combat_Command_Action.Hold
		action_label := "Hold"
		stance := game.Combat_Stance.Engage
		for u, unit_index in s.combat.units[:s.combat.friendly_count] do if u.group == group {
			unit_action := game.combat_command_action(u.order)
			unit_action_label := combat_unit_command_label(s, &s.combat.units[unit_index])
			if elements == 0 {action = unit_action; action_label = unit_action_label; stance = u.stance} else {if unit_action != action || unit_action_label != action_label do mixed_actions = true; if u.stance != stance do mixed_stances = true}
			elements += 1
			active += u.formation_active
			ships += u.formation_ships
			hull += u.hull
			max_hull += u.max_hull
			pressure += u.pressure
			readiness += u.readiness
			cohesion += u.cohesion
			disabled = disabled || u.disabled
			withdrawing = withdrawing || u.withdrawing || u.order == .Withdraw || u.order == .Extract
			for salvo in s.combat.salvos do if game.combat_salvo_warning_actionable(salvo) && salvo.target == unit_index && salvo.side != u.side {
				inbound_count += 1
				impact_time = min(impact_time, salvo.time_remaining)
			}
		}
		if hovered && rl.IsMouseButtonPressed(.LEFT) do combat_select_group(s, group, rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT))
		if selected do rl.DrawRectangleRec(row, rl.Color{UX.info.r, UX.info.g, UX.info.b, 22})
		if hovered && !selected do rl.DrawRectangleRec(row, rl.Color{UX.text.r, UX.text.g, UX.text.b, 10})
		rule := selected ? UX.info : UX.unavailable
		rl.DrawLineEx(V(row.x, row.y), V(row.x + (selected ? 11 : 5), row.y), 1, rule)
		rl.DrawLineEx(V(row.x, row.y), V(row.x, row.y + row.height), selected ? 2 : 1, rule)
		// Number keys are the fastest path through an RTS command rail. Keep the
		// affordance visible here instead of making the player memorize it.
		key_color := selected ? UX.info : UX.dim
		key_rect := R(row.x + 8, row.y + 3, 12, 16)
		rl.DrawRectangleRoundedLinesEx(key_rect, 0, 1, 1, key_color)
		key_text_rect := R(key_rect.x + 2, key_rect.y + 2, key_rect.width - 4, key_rect.height - 4)
		draw_text_fitted(fmt.tprintf("%d", group + 1), key_text_rect, TYPE_MICRO_TIGHT, key_color)
		draw_text(
			s.combat.groups[group].name,
			row.x + 26,
			row.y + 4,
			TYPE_SMALL_EMPHASIS,
			selected ? UX.text : UX.dim,
		)
		hull_ratio := hull / max(max_hull, 1)
		average_pressure := pressure / f32(max(elements, 1))
		state_color :=
			disabled || inbound_count > 0 || hull_ratio < .4 ? UX.bad : hull_ratio < .7 || average_pressure >= 35 || withdrawing ? UX.warn : UX.info
		state_label :=
			disabled ? "DISABLED" : inbound_count > 0 ? "INBOUND" : hull_ratio < .4 ? "CRITICAL" : hull_ratio < .7 ? "DAMAGED" : average_pressure >= 65 ? "PINNED" : average_pressure >= 35 ? "PRESSURE" : withdrawing ? "EXIT" : ""
		if state_label != "" {
			// A fixed edge rail keeps urgent groups visible in peripheral vision.
			// Unlike flashing alerts, it remains readable while paused and does not
			// compete with missile timers or the tactical volume.
			edge_x := row.x + row.width - 1
			rl.DrawLineEx(V(edge_x, row.y + 3), V(edge_x, row.y + row.height - 3), 2, state_color)
			rl.DrawLineEx(V(edge_x - 5, row.y + 3), V(edge_x, row.y + 3), 1, state_color)
			rl.DrawLineEx(
				V(edge_x - 5, row.y + row.height - 3),
				V(edge_x, row.y + row.height - 3),
				1,
				state_color,
			)
			state_width := measure_text(state_label, TYPE_MICRO_TIGHT).x
			draw_text(
				state_label,
				row.x + row.width - state_width - 8,
				row.y + 5,
				TYPE_MICRO_TIGHT,
				state_color,
			)
		}
		if inbound_count > 0 {
			draw_fmt(
				row.x + 8,
				row.y + 23,
				TYPE_MICRO_TIGHT,
				UX.bad,
				"%d/%d · %d IN · %.1fs",
				active,
				ships,
				inbound_count,
				impact_time,
			)
		} else if mixed_actions || mixed_stances {
			draw_fmt(
				row.x + 8,
				row.y + 23,
				TYPE_MICRO_TIGHT,
				UX.warn,
				"%d/%d SHIPS · MIXED",
				active,
				ships,
			)
		} else {
			draw_fmt(
				row.x + 8,
				row.y + 23,
				TYPE_MICRO_TIGHT,
				state_color,
				"%d/%d · %v · %s",
				active,
				ships,
				s.combat.groups[group].maneuver,
				action_label,
			)
		}
		bar := R(row.x + 8, row.y + row.height - 7, row.width - 16, 3)
		combat_draw_group_hulls(s, group, ships, bar, hull_ratio)
		if hovered {
			order_summary :=
				mixed_actions || mixed_stances ? "Stances or actions are split." : fmt.tprintf("%v stance; %s.", stance, action_label)
			ux_tooltip = {
				visible     = true,
				anchor      = row,
				title       = fmt.tprintf(
					"TASK GROUP %d · %s",
					group + 1,
					s.combat.groups[group].name,
				),
				body        = fmt.tprintf(
					"%d/%d ships active · readiness %.0f%% · cohesion %.0f%%. %s",
					active,
					ships,
					readiness / f32(max(elements, 1)),
					cohesion / f32(max(elements, 1)),
					order_summary,
				),
				body_height = 60,
			}
		}
	}
	rl.EndScissorMode()
	if max_scroll > 0 {
		track := R(rect.x + rect.width - 3, rect.y, 3, rect.height)
		thumb_height := max(rect.height * rect.height / content_height, 16)
		thumb_y := rect.y + (rect.height - thumb_height) * (scroll^ / max_scroll)
		rl.DrawRectangleRec(track, UX.unavailable)
		rl.DrawRectangleRec(R(track.x, thumb_y, 3, thumb_height), UX.info)
	}
}

combat_draw_left_command_panel :: proc(s: ^Ux_State) {
	locked_plan := s.combat.operation.committed_plan.committed
	label_caps("TASK GROUPS", 28, 91)
	selected_active, selected_total := combat_selected_ship_count(s)
	has_selection := selected_total > 0
	selection_text :=
		selected_active == selected_total ? (selected_total == 1 ? "1 SHIP" : fmt.tprintf("%d SHIPS", selected_total)) : fmt.tprintf("%d/%d SHIPS", selected_active, selected_total)
	draw_text(
		selection_text,
		178 - measure_text(selection_text, TYPE_MICRO).x,
		91,
		TYPE_MICRO,
		UX.info,
	)
	combat_group_list(s, R(27, 116, 151, 145), 49, &s.combat_group_scroll)
	label_caps("STANCE", 28, 277)
	selected_stance, mixed_stance, stance_found := combat_selected_stance(s)
	stance_state := !has_selection ? "NO SEL" : mixed_stance ? "MIXED" : ""
	if stance_state != "" do draw_text(stance_state, 178 - measure_text(stance_state, TYPE_MICRO).x, 277, TYPE_MICRO, UX.warn)
	combat_stance_selector(
		s,
		R(27, 296, 151, 28),
		has_selection && stance_found && !locked_plan,
		selected_stance,
		mixed_stance,
	)
	label_caps("ACTION", 28, 339)
	depth_text := fmt.tprintf("Z %+03d", int(s.combat_altitude))
	draw_text(
		depth_text,
		178 - measure_text(depth_text, TYPE_MICRO).x,
		339,
		TYPE_MICRO,
		has_selection ? UX.info : UX.unavailable,
	)
	if locked_plan {
		draw_text_wrapped(
			"Committed orders are executing autonomously.",
			R(27, 358, 151, 30),
			TYPE_MICRO,
			UX.dim,
		)
		if combat_command_button(
			R(27, 391, 151, 28),
			"WITHDRAW GROUP",
			"IMMEDIATE WITHDRAWAL",
			"The selected task group irreversibly follows its extraction route.",
			has_selection,
			false,
			1,
			"X",
		) {
			for unit in s.combat.units[:s.combat.friendly_count] do if unit.selected {
				_ = game.combat_operation_withdraw_group(&s.combat, unit.group)
				break
			}
		}
	} else {
		interaction := combat_context_interaction(s)
		if combat_command_button(
			R(23, 358, 80, 28),
			s.combat_order_armed && s.combat_order_kind == .Move ? "PLACE…" : "MOVE",
			"MOVE VECTOR",
			"Place a movement vector in the tactical volume. Drag vertically before release to set depth.",
			has_selection,
			s.combat_order_armed && s.combat_order_kind == .Move,
			0,
			"M",
		) {s.combat_order_armed = true; s.combat_order_kind = .Move}
		if combat_command_button(R(105, 358, 80, 28), interaction.label, interaction.title, interaction.explanation, interaction.enabled, false, 0, "C") do combat_issue_selected_interaction(s, interaction)
		if combat_command_button(R(23, 391, 80, 28), "HOLD", "HOLD POSITION", "Cancel the current action and remain at the present position.", has_selection, false, 0, "E") do combat_issue_selected(s, .Hold, {})
		if combat_command_button(R(105, 391, 80, 28), "WITHDRAW", "WITHDRAW SELECTED", "Leave the engagement through the extraction boundary.", has_selection, false, 1, "X") do combat_issue_selected(s, .Withdraw, s.combat.extraction)
	}
	label_caps("ABILITY", 28, 430)
	defense_unit := &s.combat.units[clamp(s.combat_selected, 0, s.combat.friendly_count - 1)]; defense_ready := has_selection && defense_unit.defense_cooldown <= 0 && defense_unit.chaff + defense_unit.flares + defense_unit.decoys > 0
	defense_has_stores := defense_unit.chaff + defense_unit.flares + defense_unit.decoys > 0
	defense_label :=
		defense_ready ? "EMERGENCY DEFENSE" : defense_unit.defense_cooldown > 0 ? fmt.tprintf("DEFENSE RECYCLE %.0fs", defense_unit.defense_cooldown) : "COUNTERMEASURES EMPTY"
	defense_title :=
		defense_ready ? "COMMIT EMERGENCY DEFENSE" : defense_has_stores ? "DEFENSE RECYCLING" : "COUNTERMEASURES EXHAUSTED"
	defense_explanation :=
		defense_ready ? "Spend countermeasures, readiness, and emissions to disrupt salvos already inbound." : defense_has_stores ? fmt.tprintf("Emergency defense returns in %.1f seconds.", defense_unit.defense_cooldown) : "The focused command element has no chaff, flares, or decoys remaining."
	if combat_command_button(
		R(27, 449, 151, 28),
		defense_label,
		defense_title,
		defense_explanation,
		defense_ready,
		false,
		1,
		"R",
	) {
		if locked_plan {
			_ = game.combat_request_emergency_defense(&s.combat, s.combat_selected)
		} else {
			_ = game.combat_emergency_defense(&s.combat, s.combat_selected)
		}
	}
	label_caps("BATTLE TEMPO", 28, 501)
	tempo_paused := s.combat_paused || s.combat_speed <= 0
	tempo_text := tempo_paused ? "PAUSED" : fmt.tprintf("%.1fX", s.combat_speed)
	draw_text(
		tempo_text,
		178 - measure_text(tempo_text, TYPE_MICRO).x,
		501,
		TYPE_MICRO,
		tempo_paused ? UX.warn : UX.info,
	)
	combat_speed_control(s, R(27, 521, 151, 28))
	label_caps("FLEET OVERRIDE", 28, 565)
	if combat_command_button(
		R(27, 583, 151, 28),
		"WITHDRAW ALL",
		"WITHDRAW ENTIRE FLEET",
		"Every friendly element abandons its objective and routes to extraction.",
		true,
		false,
		2,
	) {
		if locked_plan {
			_ = game.combat_operation_withdraw_fleet(&s.combat)
		} else {
			for i in 0 ..< s.combat.friendly_count do game.combat_issue_order(&s.combat, i, .Extract, s.combat.extraction)
		}
	}
}
