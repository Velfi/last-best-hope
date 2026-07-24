package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:testing"

ship_scar_dossier_label :: proc(scar: game.Ship_Scar) -> string {
	switch scar {
	case .Storm_Shaken:
		return "STORM-SHAKEN"
	case .Hull_Breach:
		return "HULL BREACH"
	case .Survivor_Guilt:
		return "SURVIVOR GUILT"
	case .Alien_Symbiosis:
		return "ALIEN SYMBIOSIS"
	case .Oathbound:
		return "OATHBOUND"
	case .Passage_Scarred:
		return "PASSAGE-SCARRED"
	case .None:
		return "NONE RECORDED"
	}
	return "NONE RECORDED"
}

ship_passage_trait_dossier_label :: proc(trait: game.Passage_Ship_Trait) -> string {
	switch trait {
	case .Curious:
		return "CURIOUS"
	case .Protective:
		return "PROTECTIVE"
	case .Cautious:
		return "CAUTIOUS"
	case .Committed:
		return "COMMITTED"
	case .Independent:
		return "INDEPENDENT"
	case .None:
		return "UNRECORDED"
	}
	return "UNRECORDED"
}

ship_hull_dossier_label :: proc(hull: game.Hull_Class) -> string {
	switch hull {
	case .Strike_Craft:
		return "STRIKE CRAFT"
	case .Corvette:
		return "CORVETTE"
	case .Fleet_Ship:
		return "FLEET SHIP"
	case .Cruiser:
		return "CRUISER"
	case .Capital_Ship:
		return "CAPITAL SHIP"
	case .Unspecified:
		return "UNSPECIFIED"
	}
	return "UNSPECIFIED"
}

ship_assignment_dossier_label :: proc(ship: game.Ship) -> string {
	if ship.active do return ship.committed ? "COMMITTED" : "AVAILABLE"
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

ship_condition_dossier_label :: proc(ship: game.Ship) -> string {
	if ship.damage > 0 do return fmt.tprintf("DAMAGE %d", ship.damage)
	if !ship.active do return "NO CURRENT READOUT"
	return "OPERATIONAL"
}

ship_situation_relevant :: proc(situation: game.Fleet_Situation, ship: game.Ship) -> bool {
	if situation.phase == .None || situation.phase == .Resolved do return false
	if situation.initiator == ship.id do return true
	if situation.affected_community != 0 && situation.affected_community == ship.community do return true
	for i in 0 ..< situation.position_count do if situation.positions[i].ship == ship.id do return true
	// Situations without an attributed ship, community, or response are fleet-wide.
	return(
		situation.initiator == 0 &&
		situation.affected_community == 0 &&
		situation.position_count == 0 \
	)
}

ship_mass_dossier_label :: proc(buf: []byte, mass_tonnes: i64) -> string {
	if mass_tonnes >= 1_000_000 do return fmt.bprintf(buf, "%.1f MT", f64(mass_tonnes) / 1_000_000)
	if mass_tonnes >= 1_000 do return fmt.bprintf(buf, "%.1f KT", f64(mass_tonnes) / 1_000)
	return fmt.bprintf(buf, "%d T", mass_tonnes)
}


@(test)
dossier_scar_labels_are_player_facing_and_explicit :: proc(t: ^testing.T) {
	testing.expect_value(t, ship_scar_dossier_label(.None), "NONE RECORDED")
	testing.expect_value(t, ship_scar_dossier_label(.Hull_Breach), "HULL BREACH")
	testing.expect_value(t, ship_scar_dossier_label(.Survivor_Guilt), "SURVIVOR GUILT")
}

@(test)
dossier_passage_trait_labels_never_expose_raw_none :: proc(t: ^testing.T) {
	testing.expect_value(t, ship_passage_trait_dossier_label(.None), "UNRECORDED")
	testing.expect_value(t, ship_passage_trait_dossier_label(.Cautious), "CAUTIOUS")
	testing.expect_value(t, ship_passage_trait_dossier_label(.Independent), "INDEPENDENT")
}

@(test)
dossier_hull_and_mass_labels_are_archival_and_bounded :: proc(t: ^testing.T) {
	buf: [32]byte
	testing.expect_value(t, ship_hull_dossier_label(.Fleet_Ship), "FLEET SHIP")
	testing.expect_value(t, ship_hull_dossier_label(.Capital_Ship), "CAPITAL SHIP")
	testing.expect_value(t, ship_mass_dossier_label(buf[:], 24), "24 T")
	testing.expect_value(t, ship_mass_dossier_label(buf[:], 6_000), "6.0 KT")
	testing.expect_value(t, ship_mass_dossier_label(buf[:], 900_000), "900.0 KT")
	testing.expect_value(t, ship_mass_dossier_label(buf[:], 18_000_000), "18.0 MT")
}

@(test)
dossier_assignment_labels_distinguish_condition_from_availability :: proc(t: ^testing.T) {
	ship := game.Ship {
		active = true,
	}
	testing.expect_value(t, ship_assignment_dossier_label(ship), "AVAILABLE")
	ship.committed = true
	testing.expect_value(t, ship_assignment_dossier_label(ship), "COMMITTED")
	ship.active = false
	ship.committed = false
	ship.departure = .Lost
	testing.expect_value(t, ship_assignment_dossier_label(ship), "LOST")
	ship.departure = .Settlement
	testing.expect_value(t, ship_assignment_dossier_label(ship), "SETTLED")
}

@(test)
dossier_condition_does_not_call_lost_ships_operational :: proc(t: ^testing.T) {
	ship := game.Ship {
		active = true,
	}
	testing.expect_value(t, ship_condition_dossier_label(ship), "OPERATIONAL")
	ship.active = false
	ship.departure = .Lost
	testing.expect_value(t, ship_condition_dossier_label(ship), "NO CURRENT READOUT")
	ship.scar = .Hull_Breach
	testing.expect_value(t, ship_condition_dossier_label(ship), "NO CURRENT READOUT")
	ship.active = true
	testing.expect_value(t, ship_condition_dossier_label(ship), "OPERATIONAL")
	ship.damage = 2
	testing.expect_value(t, ship_condition_dossier_label(ship), "DAMAGE 2")
}

@(test)
dossier_situation_action_only_appears_for_involved_ships :: proc(t: ^testing.T) {
	ship := game.Ship {
		id        = 7,
		community = 3,
	}
	situation := game.Fleet_Situation {
		phase     = .Proposal,
		initiator = 7,
	}
	testing.expect(t, ship_situation_relevant(situation, ship))
	situation.initiator = 8
	testing.expect(t, !ship_situation_relevant(situation, ship))
	situation.affected_community = 3
	testing.expect(t, ship_situation_relevant(situation, ship))
	situation.affected_community = 4
	situation.positions[0].ship = 7
	situation.position_count = 1
	testing.expect(t, ship_situation_relevant(situation, ship))
	situation = {
		phase = .Decision,
	}
	testing.expect(t, ship_situation_relevant(situation, ship))
	situation.phase = .Resolved
	testing.expect(t, !ship_situation_relevant(situation, ship))
}


ship_memory_dossier_label :: proc(memory: game.Ship_Memory) -> string {
	#partial switch memory.kind {
	case .Chronicle_Started:
		return fmt.tprintf("E%03d · WITNESS TO THE LOSS", memory.event_sequence)
	case .Resource_Changed:
		return fmt.tprintf("E%03d · INHERITANCE CUSTODIAN", memory.event_sequence)
	case .Precedent_Enacted:
		return fmt.tprintf("E%03d · FOUNDING PRECEDENT", memory.event_sequence)
	case .Ship_Damaged:
		if memory.semantic_tags == 0 do return fmt.tprintf("E%03d · DAMAGE RECORD", memory.event_sequence)
	case .Ship_Repaired:
		if memory.semantic_tags == 0 do return fmt.tprintf("E%03d · REPAIR RECORD", memory.event_sequence)
	case .Ship_Scarred:
		if memory.semantic_tags == 0 do return fmt.tprintf("E%03d · PERMANENT SCAR", memory.event_sequence)
	case .Ship_Bond_Changed:
		if memory.semantic_tags == 0 do return fmt.tprintf("E%03d · SHIP BOND", memory.event_sequence)
	case .Promise_Changed:
		if memory.semantic_tags == 0 do return fmt.tprintf("E%03d · PROMISE RECORD", memory.event_sequence)
	}
	return fmt.tprintf(
		"E%03d · %s",
		memory.event_sequence,
		game.semantic_tag_summary(memory.semantic_tags),
	)
}

open_ship_social_item :: proc(s: ^Ux_State, owner: game.Ship_ID, item: game.Ship_Social_Item) -> bool {
	event_at := game.event_index_by_sequence(s.campaign, item.cause_event)
	if event_at >= 0 {
		s.selected_event = event_at
		open_chronicle_from(s, .Fleet)
		return true
	}
	target := owner
	if item.reference_kind == .Ship && item.reference_id != 0 {
		target = game.Ship_ID(item.reference_id)
	}
	ship_at := game.ship_index(s.campaign, target)
	if ship_at < 0 do return false
	s.selected_ship = ship_at
	s.screen = .Fleet
	return true
}

@(test)
ship_social_navigation_opens_causal_events_and_ship_records :: proc(t: ^testing.T) {
	s := Ux_State{campaign = game.new_campaign_heap(27173)}
	defer game.campaign_destroy_heap(s.campaign)
	event := s.campaign.events[0]
	testing.expect(t, open_ship_social_item(&s, s.campaign.ships[0].id, {
		reference_kind = .Chronicle_Event,
		reference_id = event.sequence,
		cause_event = event.sequence,
	}))
	testing.expect_value(t, s.screen, Ux_Screen.Chronicle)
	testing.expect_value(t, s.selected_event, 0)
	testing.expect(t, open_ship_social_item(&s, s.campaign.ships[0].id, {
		reference_kind = .Ship,
		reference_id = u64(s.campaign.ships[1].id),
	}))
	testing.expect_value(t, s.screen, Ux_Screen.Fleet)
	testing.expect_value(t, s.selected_ship, 1)
}

@(test)
founding_memory_dossier_labels_are_distinct_and_bounded :: proc(t: ^testing.T) {
	memories := [3]game.Ship_Memory {
		{event_sequence = 2, kind = .Chronicle_Started},
		{event_sequence = 3, kind = .Resource_Changed},
		{event_sequence = 4, kind = .Precedent_Enacted},
	}
	labels: [3]string
	for memory, i in memories {
		labels[i] = ship_memory_dossier_label(memory)
		testing.expect(t, len(labels[i]) <= 29)
		for prior in 0 ..< i do testing.expect(t, labels[i] != labels[prior])
	}
	testing.expect_value(t, labels[0], "E002 · WITNESS TO THE LOSS")
	testing.expect_value(t, labels[1], "E003 · INHERITANCE CUSTODIAN")
	testing.expect_value(t, labels[2], "E004 · FOUNDING PRECEDENT")
	generic := ship_memory_dossier_label(
		game.Ship_Memory {
			event_sequence = 19,
			kind = .Ship_Damaged,
			semantic_tags = game.make_semantic_tags(.Memory, .Ship, .Damage),
		},
	)
	testing.expect_value(t, generic, "E019 · SHIP · DAMAGE · SURVIVAL")
}

@(test)
service_memory_dossier_labels_name_the_recorded_change :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		ship_memory_dossier_label({event_sequence = 7, kind = .Ship_Damaged}),
		"E007 · DAMAGE RECORD",
	)
	testing.expect_value(
		t,
		ship_memory_dossier_label({event_sequence = 8, kind = .Ship_Repaired}),
		"E008 · REPAIR RECORD",
	)
	testing.expect_value(
		t,
		ship_memory_dossier_label({event_sequence = 9, kind = .Ship_Scarred}),
		"E009 · PERMANENT SCAR",
	)
	testing.expect_value(
		t,
		ship_memory_dossier_label({event_sequence = 10, kind = .Ship_Bond_Changed}),
		"E010 · SHIP BOND",
	)
	testing.expect_value(
		t,
		ship_memory_dossier_label({event_sequence = 11, kind = .Promise_Changed}),
		"E011 · PROMISE RECORD",
	)
}


draw_fleet_ship_dossier :: proc(s: ^Ux_State) -> bool {
	panel(R(850, 72, 406, 582))
	ship := s.campaign.ships[clamp(s.selected_ship, 0, s.campaign.ship_count - 1)]
	label_caps("SHIP DOSSIER", 878, 96)
	draw_text_fitted(ship.name, R(878, 116, 210, 34), TYPE_HEADING_LARGE, UX.text)
	if button(R(1104, 116, 124, 30), "INSPECT") {
		s.ship_detail_camera = ship_generator_default_camera()
		s.modal = .Ship_Detail
	}
	mass_buf: [32]byte
	identity_buf: [128]byte
	draw_text_fitted(
		fmt.bprintf(
			identity_buf[:],
			"%v · %s · %s",
			ship.role,
			ship_hull_dossier_label(ship.hull_class),
			ship_mass_dossier_label(mass_buf[:], ship.mass_tonnes),
		),
		R(878, 151, 350, 20),
		TYPE_SMALL_EMPHASIS,
		UX.info,
	)
	draw_text_fitted(
		fmt.tprintf(
			"PWR %d · CREW %d · TRAIT %s",
			ship.power,
			ship.crew,
			ship_passage_trait_dossier_label(ship.passage_trait),
		),
		R(878, 173, 350, 18),
		TYPE_LABEL,
		UX.info,
	)
	condition_label := ship_condition_dossier_label(ship)
	draw_text_fitted(
		fmt.tprintf("CONDITION · %s", condition_label),
		R(878, 194, 182, 16),
		TYPE_SMALL_EMPHASIS,
		ship.damage > 0 ? UX.warn : !ship.active ? UX.dim : UX.good,
	)
	draw_text_fitted(
		fmt.tprintf("STATUS · %s", ship_assignment_dossier_label(ship)),
		R(1068, 194, 160, 16),
		TYPE_SMALL_EMPHASIS,
		!ship.active ? UX.unavailable : ship.committed ? UX.committed : UX.good,
	)
	draw_text_fitted(
		fmt.tprintf(
			"PROPELLANT %.1f / %.1f KT · THRUST %.0f KN",
			ship.propellant_kt,
			ship.propellant_capacity_kt,
			ship.drive_thrust_kilonewtons,
		),
		R(878, 213, 350, 16),
		TYPE_FINE,
		UX.dim,
	)
	draw_text_fitted(
		fmt.tprintf(
			"EXHAUST %.1f KM/S · MOBILITY %d · SUPPORT %d",
			ship.drive_exhaust_velocity_km_s,
			ship.impairments.mobility,
			ship.impairments.support,
		),
		R(878, 231, 350, 16),
		TYPE_FINE,
		ship.impairments.mobility > 0 || ship.impairments.support > 0 ? UX.warn : UX.dim,
	)
	identity_y := f32(249)
	community_at := game.community_index(s.campaign, ship.community)
	if community_at >= 0 {
		community := s.campaign.communities[community_at]
		draw_text_fitted(
			fmt.tprintf(
				"%s · %v · GRIEVANCE %d",
				community.name,
				community.position,
				community.grievance,
			),
			R(878, identity_y, 350, 18),
			TYPE_LABEL,
			community.position == .Aggrieved ? UX.warn : UX.dim,
		)
		identity_y += 18
	}
	captain_at := game.historical_figure_index(s.campaign, ship.captain)
	captain_conduct := ""
	if captain_at >= 0 {
		captain := s.campaign.historical_figures[captain_at]
		dossier := game.captain_dossier(s.campaign, captain.id)
		draw_text_fitted(
			fmt.tprintf("CAPTAIN · %s", captain.name),
			R(878, identity_y, 350, 17),
			TYPE_LABEL,
			UX.committed,
		)
		draw_text_fitted(
			fmt.tprintf(
				"PROFILE · %s · %s",
				dossier.primary_tendency,
				dossier.secondary_tendency,
			),
			R(878, identity_y + 18, 350, 16),
			TYPE_CAPTION,
			UX.committed,
		)
		captain_conduct = dossier.tension
		identity_y += 36
	} else {
		draw_text("CAPTAIN · NONE RECORDED", 878, identity_y, TYPE_LABEL, UX.dim)
		identity_y += 18
	}
	identity_divider_y := identity_y + 5
	situation_active := ship_situation_relevant(s.campaign.current_situation, ship)
	divider(878, identity_divider_y, 350)
	label_caps("CURRENT RECORD", 878, identity_divider_y + 10)
	record_y := identity_divider_y + 32
	if captain_conduct !=
	   "" {draw_text_fitted(fmt.tprintf("CAPTAIN CONDUCT · %s", captain_conduct), R(878, record_y, 350, 16), TYPE_SMALL, UX.warn); record_y += 18}
	if ship.current_position != "" {
		draw_text("POS", 856, record_y + 1, TYPE_MICRO, UX.dim)
		draw_text_fitted(
			ship.current_position,
			R(878, record_y, 350, 16),
			TYPE_SMALL_EMPHASIS,
			UX.info,
		)
		record_y += 18
	}
	if ship.current_commitment != "" {
		draw_text("VOW", 856, record_y + 1, TYPE_MICRO, UX.dim)
		draw_text_fitted(
			ship.current_commitment,
			R(878, record_y, 350, 16),
			TYPE_SMALL_EMPHASIS,
			UX.committed,
		)
		record_y += 18
	}
	if ship.pending_claim != "" {
		draw_text("CLM", 856, record_y + 1, TYPE_MICRO, UX.dim)
		draw_text_fitted(ship.pending_claim, R(878, record_y, 350, 16), TYPE_SMALL, UX.warn)
		record_y += 18
	}
	if captain_conduct == "" &&
	   ship.current_position == "" &&
	   ship.current_commitment == "" &&
	   ship.pending_claim ==
		   "" {draw_text("No active position, pledge, or claim.", 878, record_y, TYPE_SMALL, UX.dim); record_y += 18}
	if situation_active {if button(R(878, record_y + 4, 350, 24), "SITUATION AWAITING ATTENTION", true, true) do s.screen = .Interaction; record_y += 32}
	section_divider_y := record_y + 8
	divider(878, section_divider_y, 350)
	label_caps("SOCIAL POSITION", 878, section_divider_y + 10)
	record_y = section_divider_y + 29
	social := game.ship_social_position(s.campaign, ship.id)
	if social.item_count == 0 {
		draw_text("No active social record.", 878, record_y, TYPE_SMALL, UX.dim)
		record_y += 20
	} else {
		shown := min(social.item_count, 4)
		for item, i in social.items[:shown] {
			item_label := fmt.tprintf("%s · %s", item.label, item.detail)
			if button(R(878, record_y + f32(i) * 24, 350, 22), item_label) {
				_ = open_ship_social_item(s, ship.id, item)
			}
		}
		record_y += f32(shown) * 24
		if social.item_count > shown {
			draw_fmt(878, record_y, TYPE_MICRO, UX.dim, "+%d LINKED RECORDS", social.item_count - shown)
			record_y += 14
		}
	}
	relationship := game.relationship_description(s.campaign, ship.id)
	politics := game.community_institution_relationship_description(s.campaign, ship.community)
	section_divider_y = record_y + 8
	divider(878, section_divider_y, 350)
	label_caps("SERVICE HISTORY · LATEST 4", 878, section_divider_y + 10)
	service_y := section_divider_y + 32
	if ship.memory_count == 0 {
		draw_text("No event-linked memories recorded.", 878, service_y, TYPE_SMALL, UX.dim)
		service_y += 20
	} else {
		start := max(0, ship.memory_count - 4)
		for memory, i in ship.memories[start:ship.memory_count] {
			if button(R(878, service_y + f32(i) * 23, 350, 21), ship_memory_dossier_label(memory)) {
				event_at := game.event_index_by_sequence(s.campaign, memory.event_sequence)
				if event_at >= 0 {s.selected_event = event_at; open_chronicle_from(s, .Fleet)}
			}
		}
		service_y += f32(min(ship.memory_count, 4)) * 23
	}
	if relationship !=
	   "" {draw_text_fitted(fmt.tprintf("COMMUNITY · %s", relationship), R(878, service_y, 350, 16), TYPE_SMALL_EMPHASIS, UX.committed); service_y += 18} else if politics != "" {draw_text_fitted(fmt.tprintf("POLITICS · %s", politics), R(878, service_y, 350, 16), TYPE_SMALL_EMPHASIS, UX.committed); service_y += 18}
	jurisdiction := game.institution_ship_relationship_description(s.campaign, ship.id)
	bond := game.ship_bond_description(s.campaign, ship.id)
	if jurisdiction !=
	   "" {draw_text_fitted(fmt.tprintf("AUTHORITY · %s", jurisdiction), R(878, service_y, 350, 16), TYPE_SMALL_EMPHASIS, UX.warn); service_y += 18} else if bond != "" {draw_text_fitted(fmt.tprintf("%s · %s", ship_yard_pattern_name(ship), bond), R(878, service_y, 350, 16), TYPE_SMALL, UX.info); service_y += 18}
	for history_index := s.campaign.compact.history_count - 1; history_index >= 0; history_index -= 1 {
		undertaking := &s.campaign.compact.history[history_index]
		involved := false
		for seconded in undertaking.seconded_ships[:undertaking.seconded_count] do if seconded == ship.id {
			involved = true
			break
		}
		if !involved do continue
		draw_text_fitted(
			fmt.tprintf(
				"COMPACT · CALL %d · %v · %v",
				undertaking.call,
				undertaking.approach,
				undertaking.status,
			),
			R(878, service_y, 350, 16),
			TYPE_SMALL_EMPHASIS,
			UX.info,
		)
		service_y += 18
		break
	}
	draw_text_wrapped(
		ship_construction_profile_label(ship),
		R(878, service_y, 350, 28),
		TYPE_SMALL,
		UX.info,
	)
	if ship.experience > 0 || ship.discoveries > 0 {
		draw_text_fitted(
			fmt.tprintf("FIELD XP · %d · DISC %d", ship.experience, ship.discoveries),
			R(878, service_y + 30, 170, 16),
			TYPE_SMALL,
			UX.text,
		)
	} else {
		draw_text_fitted("FIELD XP · NONE", R(878, service_y + 30, 170, 16), TYPE_SMALL, UX.dim)
	}
	draw_text_fitted(
		fmt.tprintf("SCAR · %s", ship_scar_dossier_label(ship.scar)),
		R(1068, service_y + 30, 160, 16),
		TYPE_SMALL,
		ship.scar == .None ? UX.dim : UX.bad,
	)
	if ship.promises_upheld > 0 || ship.promises_broken > 0 || ship.promises_transformed > 0 {
		draw_text("PROMISES", 878, service_y + 48, TYPE_SMALL, UX.dim)
		draw_fmt(
			950,
			service_y + 48,
			TYPE_SMALL,
			ship.promises_upheld > 0 ? UX.good : UX.dim,
			"KEPT %d",
			ship.promises_upheld,
		)
		draw_fmt(
			1012,
			service_y + 48,
			TYPE_SMALL,
			ship.promises_broken > 0 ? UX.warn : UX.dim,
			"BROKEN %d",
			ship.promises_broken,
		)
		draw_fmt(
			1090,
			service_y + 48,
			TYPE_SMALL,
			ship.promises_transformed > 0 ? UX.committed : UX.dim,
			"CHANGED %d",
			ship.promises_transformed,
		)
	} else {
		draw_text("NO PROMISE OUTCOMES RECORDED", 878, service_y + 48, TYPE_SMALL, UX.dim)
	}
	return situation_active
}
