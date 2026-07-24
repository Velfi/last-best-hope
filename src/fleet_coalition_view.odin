package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:strings"
import "core:testing"

constellation_ship_needs_care :: proc(c: ^game.Campaign, ship: game.Ship_ID) -> bool {
	for need in c.needs do if need.active && !need.resolved && need.ship == ship do return true
	return false
}


constellation_ship_state_label :: proc(ship: game.Ship) -> string {
	if ship.active do return ship.committed ? "COMMITTED" : ""
	switch ship.departure {
	case .Lost:
		return "LOST"
	case .Settlement:
		return "SETTLED"
	case .Dark_Voyage:
		return "DARK VOYAGE"
	case .Political_Schism:
		return "SCHISM"
	case .None:
		return "INACTIVE"
	}
	return "INACTIVE"
}

constellation_ship_condition_label :: proc(ship: game.Ship) -> string {
	switch ship.scar {
	case .Storm_Shaken:
		return "STORM-SHAKEN"
	case .Hull_Breach:
		return "BREACH"
	case .Survivor_Guilt:
		return "SURVIVOR"
	case .Alien_Symbiosis:
		return "SYMBIOSIS"
	case .Oathbound:
		return "OATHBOUND"
	case .Passage_Scarred:
		return "PASSAGE-SCARRED"
	case .None:
	}
	if ship.damage > 0 do return fmt.tprintf("DAMAGE %d", ship.damage)
	return ""
}


draw_constellation_hover_corners :: proc(marker: rl.Rectangle) {
	pad, tick := f32(5), f32(7)
	left, right := marker.x - pad, marker.x + marker.width + pad
	top, bottom := marker.y - pad, marker.y + marker.height + pad
	color := rl.Color{104, 181, 198, 145}
	corners := [4][2]rl.Vector2 {
		{V(left, top), V(1, 1)},
		{V(right, top), V(-1, 1)},
		{V(right, bottom), V(-1, -1)},
		{V(left, bottom), V(1, -1)},
	}
	for corner in corners {
		origin, direction := corner[0], corner[1]
		rl.DrawLineEx(origin, V(origin.x + direction.x * tick, origin.y), 1, color)
		rl.DrawLineEx(origin, V(origin.x, origin.y + direction.y * tick), 1, color)
	}
}

fleet_constellation_select_ship :: proc(s: ^Ux_State, index: int) {
	if index < 0 || index >= s.campaign.ship_count do return
	s.selected_ship = index
	if s.campaign.guidance_step == 1 {
		game.guidance_advance(s.campaign)
		_ = ux_save(s, true)
	}
}

@(test)
constellation_care_state_tracks_only_open_ship_needs :: proc(t: ^testing.T) {
	c := new(game.Campaign)
	defer free(c)
	ship := game.Ship_ID(7)
	c.needs[0] = {
		ship   = ship,
		active = true,
	}
	testing.expect(t, constellation_ship_needs_care(c, ship))
	c.needs[0].resolved = true
	testing.expect(t, !constellation_ship_needs_care(c, ship))
	c.needs[0].resolved = false
	c.needs[0].active = false
	testing.expect(t, !constellation_ship_needs_care(c, ship))
	testing.expect(t, !constellation_ship_needs_care(c, game.Ship_ID(8)))
}


@(test)
constellation_inactive_labels_preserve_departure_state :: proc(t: ^testing.T) {
	ship := game.Ship {
		active = true,
	}
	testing.expect_value(t, constellation_ship_state_label(ship), "")
	ship.committed = true
	testing.expect_value(t, constellation_ship_state_label(ship), "COMMITTED")
	ship.committed = false
	ship.active = false
	testing.expect_value(t, constellation_ship_state_label(ship), "INACTIVE")
	ship.departure = .Lost
	testing.expect_value(t, constellation_ship_state_label(ship), "LOST")
	ship.departure = .Settlement
	testing.expect_value(t, constellation_ship_state_label(ship), "SETTLED")
	ship.departure = .Dark_Voyage
	testing.expect_value(t, constellation_ship_state_label(ship), "DARK VOYAGE")
	ship.departure = .Political_Schism
	testing.expect_value(t, constellation_ship_state_label(ship), "SCHISM")
}

@(test)
constellation_condition_labels_preserve_damage_and_scar_history :: proc(t: ^testing.T) {
	ship: game.Ship
	testing.expect_value(t, constellation_ship_condition_label(ship), "")
	ship.damage = 2
	testing.expect_value(t, constellation_ship_condition_label(ship), "DAMAGE 2")
	ship.scar = .Hull_Breach
	testing.expect_value(t, constellation_ship_condition_label(ship), "BREACH")
	ship.scar = .Alien_Symbiosis
	testing.expect_value(t, constellation_ship_condition_label(ship), "SYMBIOSIS")
}


fleet_primary_affiliation :: proc(ship: game.Ship) -> game.Affiliation {
	switch ship.role {
	case .Survey:
		return .Navigation
	case .Escort:
		return .Institution
	case .Habitat, .Colony:
		return .Habitat
	case .Foundry, .Agriculture:
		return .Industry
	case .Hospital:
		return .Care
	case .Archive:
		return .Faith
	}
	return .Ship_Crew
}

fleet_affiliation_label :: proc(affiliation: game.Affiliation) -> string {
	switch affiliation {
	case .Navigation:
		return "NAVIGATION COALITION"
	case .Habitat:
		return "HABITAT COALITION"
	case .Industry:
		return "INDUSTRY COALITION"
	case .Care:
		return "CARE COALITION"
	case .Faith:
		return "FAITH COALITION"
	case .Institution:
		return "INSTITUTION COALITION"
	case .Community:
		return "COMMUNITY COALITION"
	case .Ship_Crew:
		return "INDEPENDENT CREWS"
	}
	return "INDEPENDENT CREWS"
}

fleet_affiliation_rank :: proc(affiliation: game.Affiliation) -> int {
	switch affiliation {
	case .Navigation:
		return 0
	case .Habitat:
		return 1
	case .Industry:
		return 2
	case .Care:
		return 3
	case .Faith:
		return 4
	case .Institution:
		return 5
	case .Community:
		return 6
	case .Ship_Crew:
		return 7
	}
	return 7
}

fleet_collect_coalitions :: proc(
	c: ^game.Campaign,
	keys: ^[8]game.Affiliation,
	counts: ^[8]int,
) -> int {
	group_count := 0
	for ship in c.ships[:c.ship_count] {
		key := fleet_primary_affiliation(ship)
		group := -1
		for candidate in 0 ..< group_count do if keys[candidate] == key {group = candidate; break}
		if group < 0 {
			group = 0
			for group < group_count && fleet_affiliation_rank(keys[group]) < fleet_affiliation_rank(key) do group += 1
			for at := group_count; at > group; at -= 1 {
				keys[at] = keys[at - 1]
				counts[at] = counts[at - 1]
			}
			keys[group] = key
			counts[group] = 0
			group_count += 1
		}
		counts[group] += 1
	}
	return group_count
}

fleet_coalition_voice :: proc(c: ^game.Campaign, affiliation: game.Affiliation) -> i32 {
	voice: i32
	for constituency in c.politics.constituencies[:c.politics.constituency_count] {
		if !constituency.active do continue
		ship_at := game.ship_index(c, constituency.ship)
		if ship_at < 0 || fleet_primary_affiliation(c.ships[ship_at]) != affiliation do continue
		voice += constituency.political_weight
	}
	return voice
}

@(test)
fleet_primary_affiliations_match_political_constituencies :: proc(t: ^testing.T) {
	cases := [8]struct {
		role:        game.Role,
		affiliation: game.Affiliation,
	} {
		{.Survey, .Navigation},
		{.Escort, .Institution},
		{.Habitat, .Habitat},
		{.Colony, .Habitat},
		{.Foundry, .Industry},
		{.Agriculture, .Industry},
		{.Hospital, .Care},
		{.Archive, .Faith},
	}
	for item in cases do testing.expect_value(t, fleet_primary_affiliation(game.Ship{role = item.role}), item.affiliation)
}

@(test)
fleet_coalition_content_grows_instead_of_compressing_dense_groups :: proc(t: ^testing.T) {
	compact := [8]int{2, 2, 3, 1, 2, 2, 0, 0}
	dense := [8]int{12, 12, 12, 12, 0, 0, 0, 0}
	testing.expect_value(t, fleet_coalition_column_span(5), 1)
	testing.expect_value(t, fleet_coalition_column_span(6), 2)
	testing.expect_value(t, fleet_coalition_column_span(11), 3)
	testing.expect(t, fleet_coalition_content_height(6, &compact) <= 474)
	testing.expect(t, fleet_coalition_content_height(4, &dense) > 474)
}

draw_coalition_frame :: proc(rect: rl.Rectangle, focused: bool) {
	color := focused ? rl.Color{104, 181, 198, 105} : rl.Color{73, 88, 94, 75}
	rl.DrawLineEx(V(rect.x, rect.y), V(rect.x + rect.width, rect.y), 1, color)
	rl.DrawLineEx(V(rect.x, rect.y), V(rect.x, rect.y + 10), 1, color)
	rl.DrawLineEx(V(rect.x + rect.width, rect.y), V(rect.x + rect.width, rect.y + 10), 1, color)
	rl.DrawLineEx(V(rect.x, rect.y + rect.height), V(rect.x + 12, rect.y + rect.height), 1, color)
	rl.DrawLineEx(
		V(rect.x + rect.width - 12, rect.y + rect.height),
		V(rect.x + rect.width, rect.y + rect.height),
		1,
		color,
	)
}

fleet_coalition_column_span :: proc(ship_count: int) -> int {
	return clamp((max(ship_count, 1) + 4) / 5, 1, 3)
}

fleet_coalition_card_height :: proc(ship_count: int) -> f32 {
	span := fleet_coalition_column_span(ship_count)
	rows := (max(ship_count, 1) + span - 1) / span
	return f32(40 + rows * 48)
}

fleet_coalition_content_height :: proc(group_count: int, counts: ^[8]int) -> f32 {
	if group_count <= 0 do return 0
	height, row_height := f32(0), f32(0)
	used_columns := 0
	for group in 0 ..< group_count {
		span := fleet_coalition_column_span(counts[group])
		if used_columns > 0 && used_columns + span > 3 {
			height += row_height + 10
			used_columns = 0
			row_height = 0
		}
		row_height = max(row_height, fleet_coalition_card_height(counts[group]))
		used_columns += span
		if used_columns == 3 && group < group_count - 1 {
			height += row_height + 10
			used_columns = 0
			row_height = 0
		}
	}
	return height + row_height
}

fleet_coalition_cell :: proc(
	group, group_count: int,
	counts: ^[8]int,
	field: rl.Rectangle,
	scroll: f32 = 0,
) -> rl.Rectangle {
	gap := f32(10)
	unit_width := (field.width - gap * 2) / 3
	cell_y := field.y - scroll
	used_columns := 0
	row_height := f32(0)
	for candidate in 0 ..< group_count {
		span := fleet_coalition_column_span(counts[candidate])
		if used_columns > 0 && used_columns + span > 3 {
			cell_y += row_height + gap
			used_columns = 0
			row_height = 0
		}
		card_height := fleet_coalition_card_height(counts[candidate])
		if candidate == group {
			return R(
				field.x + f32(used_columns) * (unit_width + gap),
				cell_y,
				unit_width * f32(span) + gap * f32(span - 1),
				card_height,
			)
		}
		row_height = max(row_height, card_height)
		used_columns += span
		if used_columns == 3 {
			cell_y += row_height + gap
			used_columns = 0
			row_height = 0
		}
	}
	return R(field.x, cell_y, unit_width, 88)
}

fleet_coalition_ship_point :: proc(c: ^game.Campaign, ship_index: int) -> rl.Vector2 {
	if ship_index < 0 || ship_index >= c.ship_count do return V(-100, -100)
	keys: [8]game.Affiliation
	counts: [8]int
	group_count := fleet_collect_coalitions(c, &keys, &counts)
	target_key := fleet_primary_affiliation(c.ships[ship_index])
	target_group, target_slot := 0, 0
	for group in 0 ..< group_count do if keys[group] == target_key {target_group = group; break}
	for ship, i in c.ships[:c.ship_count] {
		if i == ship_index do break
		if fleet_primary_affiliation(ship) == target_key do target_slot += 1
	}
	field := R(24, 104, 802, 474)
	cell := fleet_coalition_cell(target_group, group_count, &counts, field)
	span := fleet_coalition_column_span(counts[target_group])
	rows := (counts[target_group] + span - 1) / span
	column := target_slot / rows
	row := target_slot % rows
	entry_width := cell.width / f32(span)
	return V(cell.x + f32(column) * entry_width + 32, cell.y + 44 + f32(row) * 48)
}

draw_fleet_coalitions :: proc(s: ^Ux_State) {
	group_keys: [8]game.Affiliation
	group_counts: [8]int
	ship_groups: [game.MAX_SHIPS]int
	group_count := fleet_collect_coalitions(s.campaign, &group_keys, &group_counts)
	for ship, i in s.campaign.ships[:s.campaign.ship_count] {
		key := fleet_primary_affiliation(ship)
		for group in 0 ..< group_count do if group_keys[group] == key {ship_groups[i] = group; break}
	}
	if group_count == 0 do return

	field := R(24, 104, 802, 474)
	content_height := fleet_coalition_content_height(group_count, &group_counts)
	max_scroll := max(content_height - field.height, f32(0))
	if contains(field) {
		s.fleet_scroll = clamp(s.fleet_scroll - rl.GetMouseWheelMove() * 58, 0, max_scroll)
	} else {
		s.fleet_scroll = clamp(s.fleet_scroll, 0, max_scroll)
	}
	marker_scale := f32(.86)
	group_slots: [8]int
	points: [game.MAX_SHIPS]rl.Vector2
	markers: [game.MAX_SHIPS]rl.Rectangle
	labels: [game.MAX_SHIPS]rl.Rectangle

	rl.BeginScissorMode(field)
	for group in 0 ..< group_count {
		cell := fleet_coalition_cell(group, group_count, &group_counts, field, s.fleet_scroll)
		focused :=
			s.selected_ship >= 0 &&
			s.selected_ship < s.campaign.ship_count &&
			ship_groups[s.selected_ship] == group
		draw_coalition_frame(cell, focused)
		header_color := focused ? UX.info : UX.dim
		voice := fleet_coalition_voice(s.campaign, group_keys[group])
		header := fmt.tprintf(
			"%s · %d %s",
			fleet_affiliation_label(group_keys[group]),
			group_counts[group],
			group_counts[group] == 1 ? "SHIP" : "SHIPS",
		)
		if voice > 0 do header = fmt.tprintf("%s · VOICE %d", header, voice)
		draw_text_fitted(
			header,
			R(cell.x + 10, cell.y + 8, cell.width - 20, 16),
			TYPE_FINE,
			header_color,
		)
	}

	for ship, i in s.campaign.ships[:s.campaign.ship_count] {
		group := ship_groups[i]
		cell := fleet_coalition_cell(group, group_count, &group_counts, field, s.fleet_scroll)
		slot := group_slots[group]
		group_slots[group] += 1
		span := fleet_coalition_column_span(group_counts[group])
		rows := (group_counts[group] + span - 1) / span
		entry_column := slot / rows
		entry_row := slot % rows
		entry_width := cell.width / f32(span)
		point_y := cell.y + 44 + f32(entry_row) * 48
		points[i] = V(cell.x + f32(entry_column) * entry_width + 32, point_y)
		selected := s.selected_ship == i
		markers[i] = ship_marker_rect(ship, points[i].x, points[i].y, selected, marker_scale)
		labels[i] = R(
			cell.x + f32(entry_column) * entry_width + 58,
			point_y - 15,
			entry_width - 68,
			30,
		)
	}

	for ship, i in s.campaign.ships[:s.campaign.ship_count] {
		marker := markers[i]
		click_target := R(marker.x - 6, marker.y - 6, marker.width + 12, marker.height + 12)
		hovered := contains(field) && (contains(click_target) || contains(labels[i]))
		selected := s.selected_ship == i
		if hovered && rl.IsMouseButtonPressed(.LEFT) do fleet_constellation_select_ship(s, i)
		if hovered && !selected do draw_constellation_hover_corners(marker)
		if selected || hovered {
			color := selected ? rl.Color{104, 181, 198, 145} : rl.Color{104, 181, 198, 92}
			rl.DrawLineEx(
				V(marker.x + marker.width + 3, points[i].y),
				V(labels[i].x - 4, points[i].y),
				1,
				color,
			)
		}
		draw_ship_constellation_marker(ship, points[i].x, points[i].y, selected, marker_scale)
		needs_care := constellation_ship_needs_care(s.campaign, ship.id)
		if needs_care do rl.DrawCircleV(V(marker.x + marker.width + 3, marker.y - 2), 3, UX.warn)
		label_color :=
			!ship.active ? UX.unavailable : selected || hovered ? UX.info : needs_care ? UX.warn : UX.text
		draw_text_fitted(
			ship.name,
			R(labels[i].x, labels[i].y, labels[i].width, 16),
			TYPE_SMALL,
			label_color,
		)
		role_label := strings.to_upper(game.role_name(ship.role))
		if state := constellation_ship_state_label(ship); state != "" do role_label = fmt.tprintf("%s · %s", role_label, state)
		if ship.active {
			if condition := constellation_ship_condition_label(ship); condition != "" do role_label = fmt.tprintf("%s · %s", role_label, condition)
		}
		role_color :=
			!ship.active ? UX.unavailable : ship.scar != .None ? UX.bad : ship.damage > 0 ? UX.warn : ship.committed ? UX.committed : selected || hovered ? UX.info : UX.dim
		draw_text_fitted(
			role_label,
			R(labels[i].x, labels[i].y + 16, labels[i].width, 11),
			TYPE_FINE,
			role_color,
		)
	}
	rl.EndScissorMode()

	if max_scroll > 0 {
		track := R(field.x + field.width - 4, field.y + 4, 3, field.height - 8)
		thumb_height := max(track.height * field.height / content_height, f32(34))
		travel := track.height - thumb_height
		thumb_y := track.y + travel * s.fleet_scroll / max_scroll
		thumb := R(track.x - 3, thumb_y, 6, thumb_height)
		rl.DrawRectangleRec(track, UX.unavailable)
		rl.DrawRectangleRec(R(track.x, thumb.y, track.width, thumb.height), UX.info)
		if contains(thumb) && rl.IsMouseButtonPressed(.LEFT) do s.fleet_scroll_dragging = true
		if contains(track) && rl.IsMouseButtonPressed(.LEFT) && !contains(thumb) {
			ratio := clamp((ux_mouse.y - track.y - thumb_height / 2) / max(travel, f32(1)), 0, 1)
			s.fleet_scroll = ratio * max_scroll
			s.fleet_scroll_dragging = true
		}
		if s.fleet_scroll_dragging {
			if rl.IsMouseButtonDown(.LEFT) {
				delta := rl.GetMouseDelta()
				s.fleet_scroll = clamp(
					s.fleet_scroll +
					delta.y / max(ux_zoom, f32(.01)) * max_scroll / max(travel, f32(1)),
					0,
					max_scroll,
				)
			} else {
				s.fleet_scroll_dragging = false
			}
		}
	} else {
		s.fleet_scroll_dragging = false
	}
}


@(test)
fleet_coalition_layout_is_stable_and_scroll_bounds_are_clamped :: proc(t: ^testing.T) {
	counts := [8]int{12, 12, 12, 12, 0, 0, 0, 0}
	group_count := 4
	field := R(24, 104, 802, 474)
	content_height := fleet_coalition_content_height(group_count, &counts)
	max_scroll := max(content_height - field.height, f32(0))
	testing.expect(t, max_scroll > 0)
	testing.expect_value(t, clamp(f32(-50), f32(0), max_scroll), f32(0))
	testing.expect_value(t, clamp(max_scroll + 50, f32(0), max_scroll), max_scroll)
	first := fleet_coalition_cell(2, group_count, &counts, field, max_scroll / 2)
	second := fleet_coalition_cell(2, group_count, &counts, field, max_scroll / 2)
	testing.expect_value(t, first, second)
	testing.expect(t, first.width > 0 && first.height > 0)
}
