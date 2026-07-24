package game

import "core:fmt"

MAX_STRANDED_PASSAGE_GROUPS :: MAX_SHIPS

Stranded_Passage_Outcome :: enum {
	None,
	Returned_Home,
	Remained_Independent,
}

Stranded_Passage_Group :: struct {
	id:                  u64,
	relay_id, door_id:   u64,
	galaxy_neighborhood: int,
	ships:               [MAX_EXPEDITION_SHIPS]Ship_ID,
	ship_count:          int,
	active:              bool,
	outcome:             Stranded_Passage_Outcome,
	stranded_season:     i32,
	last_attempt_season: i32,
	route_opened_season: i32,
	route_progress:      i32,
	reported_stage:      i32,
}

stranded_passage_active :: proc(c: ^Campaign) -> bool {
	for group in c.stranded_passage_groups[:c.stranded_passage_group_count] do if group.active do return true
	return false
}

stranded_passage_slot :: proc(c: ^Campaign) -> int {
	for group, i in c.stranded_passage_groups[:c.stranded_passage_group_count] do if !group.active do return i
	if c.stranded_passage_group_count < MAX_STRANDED_PASSAGE_GROUPS {
		i := c.stranded_passage_group_count
		c.stranded_passage_group_count += 1
		return i
	}
	return -1
}

begin_stranded_passage_group :: proc(c: ^Campaign, p: ^Passage, relay_id: u64) -> bool {
	if relay_id == 0 || p.ship_count <= 0 do return false
	at := stranded_passage_slot(c)
	if at < 0 do return false
	group := &c.stranded_passage_groups[at]
	group^ = {
		id                  = next_random(c),
		relay_id            = relay_id,
		door_id             = p.pending_door_id,
		galaxy_neighborhood = p.normal_course.start_neighborhood,
		ships               = p.ships,
		ship_count          = p.ship_count,
		active              = true,
		stranded_season     = c.season,
		last_attempt_season = c.season,
	}
	for ship_id in group.ships[:group.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 {
		ship := &c.ships[ship_at]
		ship.current_position = "Remote authenticated relay"
		ship.current_commitment = "Searching for a route home from an authenticated relay."
	}
	return true
}

validate_stranded_passage_groups :: proc(c: ^Campaign) -> bool {
	if c.stranded_passage_group_count < 0 || c.stranded_passage_group_count > MAX_STRANDED_PASSAGE_GROUPS do return false
	notice_count := 0
	for group_index in 0 ..< c.stranded_passage_group_count {
		group := &c.stranded_passage_groups[group_index]
		if group.outcome !=
		   .None {notice_count += 1; if group.active || group.route_progress < 100 || group.route_opened_season <= 0 || group.route_opened_season > c.season do return false}
		if !group.active do continue
		if group.id == 0 || group.relay_id == 0 || dark_relay_index(c, group.relay_id) < 0 || group.galaxy_neighborhood < 0 || group.ship_count < 1 || group.ship_count > MAX_EXPEDITION_SHIPS || group.route_progress < 0 || group.route_progress > 100 || group.reported_stage < 0 || group.reported_stage > 4 || group.stranded_season > c.season || group.last_attempt_season < group.stranded_season || group.last_attempt_season > c.season do return false
		for ship_id, i in group.ships[:group.ship_count] {
			ship_at := ship_index(c, ship_id)
			if ship_at < 0 || c.ships[ship_at].active || c.ships[ship_at].departure != .Dark_Voyage do return false
			for prior in group.ships[:i] do if prior == ship_id do return false
		}
	}
	if c.stranded_outcome_notice_pending != (notice_count > 0) do return false
	if c.stranded_outcome_notice_pending {
		if c.stranded_outcome_candidate < 0 || c.stranded_outcome_candidate >= c.stranded_passage_group_count || c.stranded_passage_groups[c.stranded_outcome_candidate].outcome == .None do return false
	}
	return true
}

stranded_route_increment :: proc(c: ^Campaign, group: ^Stranded_Passage_Group) -> i32 {
	survey_bonus, damage_penalty := i32(0), i32(0)
	for ship_id in group.ships[:group.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 {
		ship := &c.ships[ship_at]
		if ship.role == .Survey do survey_bonus += 5
		damage_penalty += max(ship.damage, 0)
	}
	relay_bonus := i32(0)
	if relay_at := dark_relay_index(c, group.relay_id); relay_at >= 0 do relay_bonus = i32(c.dark_relays[relay_at].condition * 8)
	state := c.initial_seed ~ group.id ~ u64(c.season) * 0x9e3779b97f4a7c15
	jitter := i32(planet_rng_next(&state) % 8)
	return clamp(
		i32(18) + survey_bonus + relay_bonus + jitter - min(damage_penalty, i32(8)),
		i32(10),
		i32(38),
	)
}

stranded_group_lead :: proc(group: ^Stranded_Passage_Group) -> Ship_ID {
	if group.ship_count <= 0 do return 0
	return group.ships[0]
}

stranded_route_report :: proc(c: ^Campaign, group: ^Stranded_Passage_Group, stage: i32) {
	detail := "The relay expedition detected a recurring correspondence signal."
	switch stage {
	case 2:
		detail = "The relay expedition localized the correspondence signal."
	case 3:
		detail = "The relay expedition forecast a possible transit window."
	case 4:
		detail = "The relay expedition established a route home."
	}
	record_event(
		c,
		stage == 4 ? .Need_Surfaced : .Situation_Decided,
		detail,
		stranded_group_lead(group),
		value = group.route_progress,
	)
}

advance_stranded_passage_groups :: proc(c: ^Campaign) {
	if c.stranded_outcome_notice_pending do return
	for &group, group_index in c.stranded_passage_groups[:c.stranded_passage_group_count] {
		if !group.active || group.last_attempt_season >= c.season do continue
		group.last_attempt_season = c.season
		group.route_progress = min(
			group.route_progress + stranded_route_increment(c, &group),
			i32(100),
		)
		if relay_at := dark_relay_index(c, group.relay_id); relay_at >= 0 do c.dark_relays[relay_at].condition = min(c.dark_relays[relay_at].condition + .05, 1)
		for ship_id in group.ships[:group.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 {
			ship := &c.ships[ship_at]
			if ship.damage > 0 && (c.season + i32(ship_id % 2)) % 2 == 0 do ship.damage -= 1
		}
		stage :=
			group.route_progress >= 100 ? i32(4) : group.route_progress >= 75 ? i32(3) : group.route_progress >= 50 ? i32(2) : group.route_progress >= 25 ? i32(1) : i32(0)
		if stage > group.reported_stage {
			group.reported_stage = stage
			stranded_route_report(c, &group, stage)
		}
		if stage == 4 {
			group.route_opened_season = c.season
			if group.door_id !=
			   0 {for &door in c.outer_dark.continuum.doors[:c.outer_dark.continuum.door_count] do if door.id == group.door_id {door.access = max(door.access, .5); break}}
			resolve_stranded_choice(c, &group)
			c.stranded_outcome_notice_pending = true
			c.stranded_outcome_candidate = group_index
			return
		}
	}
}

stranded_group_chooses_return :: proc(c: ^Campaign, group: ^Stranded_Passage_Group) -> bool {
	return_weight, remain_weight := i32(1), i32(0)
	seasons_away := c.season - group.stranded_season
	if seasons_away <= 3 do return_weight += 2
	if seasons_away >= 4 do remain_weight += 2
	if has_precedent(c, .Ship_Sovereignty) || has_precedent(c, .Right_Of_Departure) do remain_weight += 1
	for ship_id in group.ships[:group.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 {
		ship := c.ships[ship_at]
		if ship.role == .Habitat || ship.role == .Agriculture || ship.role == .Colony do remain_weight += 2
		if ship.passage_trait == .Independent do remain_weight += 1
		if ship.passage_trait == .Committed || ship.passage_trait == .Protective do return_weight += 1
		if ship.promises_upheld > ship.promises_broken do return_weight += 1
		if ship.damage > 0 do return_weight += 1
	}
	if relay_at := dark_relay_index(c, group.relay_id); relay_at >= 0 && c.dark_relays[relay_at].condition >= .85 do remain_weight += 1
	return return_weight >= remain_weight
}

stranded_choice_basis :: proc(
	c: ^Campaign,
	group: ^Stranded_Passage_Group,
	return_home: bool,
) -> string {
	seasons_away := c.season - group.stranded_season
	if return_home {
		for ship_id in group.ships[:group.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 {
			ship := c.ships[ship_at]
			if ship.damage > 0 do return "The expedition cited repair and care available with the fleet."
			if ship.promises_upheld > ship.promises_broken || ship.passage_trait == .Committed || ship.passage_trait == .Protective do return "The expedition cited its continuing commitments to the fleet."
		}
		if seasons_away <= 3 do return "The expedition reported that the relay remained an outpost rather than a settled home."
		return "The expedition accepted the fleet's standing invitation."
	}
	for ship_id in group.ships[:group.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 {
		ship := c.ships[ship_at]
		if ship.role == .Habitat || ship.role == .Agriculture || ship.role == .Colony do return "The expedition reported that its ships could sustain the relay community."
	}
	if seasons_away >= 4 do return "The expedition reported that the relay had become its working home."
	if has_precedent(c, .Ship_Sovereignty) || has_precedent(c, .Right_Of_Departure) do return "The expedition exercised the fleet's recorded ship-autonomy rule."
	return "The expedition reported that the relay community was viable."
}

resolve_stranded_choice :: proc(c: ^Campaign, group: ^Stranded_Passage_Group) {
	return_home := stranded_group_chooses_return(c, group)
	lead := stranded_group_lead(group)
	basis := stranded_choice_basis(c, group, return_home)
	if return_home {
		group.outcome = .Returned_Home
		record_event(
			c,
			.Expedition_Returned,
			fmt.tprintf(
				"The relay expedition accepted the fleet's standing invitation and returned through the reopened correspondence. %s",
				basis,
			),
			lead,
			value = c.season - group.stranded_season,
		)
		for ship_id in group.ships[:group.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 {
			ship := &c.ships[ship_at]
			ship.active = true
			ship.departure = .None
			ship.committed = false
			ship.current_position = ""
			ship.current_commitment = ""
			ship.experience += 1
			ship.discoveries += 1
			add_ship_history(c, ship.id, "Returned after finding a route home from an authenticated relay.")
		}
	} else {
		group.outcome = .Remained_Independent
		record_event(
			c,
			.Situation_Decided,
			fmt.tprintf(
				"The relay expedition reported that it would remain as an independent relay community. %s",
				basis,
			),
			lead,
		)
		for ship_id in group.ships[:group.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 {
			ship := &c.ships[ship_at]
			ship.current_commitment = "Remained by choice with an independent relay community."
			add_ship_history(c, ship.id, ship.current_commitment)
		}
		if relay_at := dark_relay_index(c, group.relay_id); relay_at >= 0 do c.dark_relays[relay_at].condition = 1
	}
	group.active = false
	return
}

acknowledge_stranded_outcome :: proc(c: ^Campaign) -> bool {
	if !c.stranded_outcome_notice_pending || c.stranded_outcome_candidate < 0 || c.stranded_outcome_candidate >= c.stranded_passage_group_count do return false
	group := &c.stranded_passage_groups[c.stranded_outcome_candidate]
	if group.outcome == .None do return false
	group.outcome = .None
	c.stranded_outcome_notice_pending = false
	c.stranded_outcome_candidate = 0
	for &other, i in c.stranded_passage_groups[:c.stranded_passage_group_count] do if other.outcome != .None {c.stranded_outcome_notice_pending = true; c.stranded_outcome_candidate = i; break}
	return true
}
