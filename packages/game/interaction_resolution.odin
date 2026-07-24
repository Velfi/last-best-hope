package game

import "core:fmt"
advance_interaction :: proc(c: ^Campaign) -> bool {
	s := &c.current_situation
	if s.phase ==
	   .Proposal {s.phase = .Responses; for position in s.positions[:s.position_count] {at := ship_index(c, position.ship); if at >= 0 do c.ships[at].current_position = fmt.tprintf("%v on %s", position.position, s.title); record_event(c, .Situation_Response, position.reasons[0].detail, position.ship, i32(position.position), s.affected_community, s.proposal_event)}; return true}
	if s.phase == .Responses {s.phase = .Decision; return true}
	return false
}

resolve_settlement_interaction :: proc(
	c: ^Campaign,
	s: ^Fleet_Situation,
	effect: Situation_Choice_Effect,
) {
	if effect == .Delay || effect == .Decline do return
	si := ship_index(c, s.initiator); if si < 0 || c.settlement_count >= MAX_SETTLEMENTS do return
	if !celestial_reference_valid(c, s.celestial) do return
	ship := &c.ships[si]; settlement := &c.settlements[c.settlement_count]
	candidate_at := candidate_home_index(c, s.celestial)
	reviewed := candidate_at >= 0 && c.candidate_homes[candidate_at].independent_review
	settlement.id = Settlement_ID(
		c.settlement_count + 1,
	); settlement.name = c.settlement_count == 0 ? "Pale Harbor" : fmt.tprintf("Pale Harbor %d", c.settlement_count + 1); settlement.population = ship.crew; settlement.viability = (effect == .Amend_Settlement ? 72 : 64) + (reviewed ? 8 : 0); settlement.liberty = 78; settlement.founded_season = c.season; settlement.report_due = c.season + 2; settlement.active = true; settlement.founder_ship = ship.id; settlement.founding_community = ship.community; settlement.participating_ships[0] = ship.id; settlement.participating_ship_count = 1; settlement.proposal_event = s.proposal_event
	if effect ==
	   .Amend_Settlement {settlement.orbital_refuge = true; settlement.orbital_refuge_capacity = max(ship.crew * 2, 1000); settlement.continuing_obligations = continuing_set(settlement.continuing_obligations, .Civilian_Mobility, true)}
	settlement.region = s.celestial.planet_name
	settlement.celestial = s.celestial
	ship.active =
		false; ship.departure = .Settlement; ship.current_commitment = fmt.tprintf("Founding vessel of %s.", settlement.name); add_ship_history(c, ship.id, ship.current_commitment)
	founding_detail := fmt.tprintf("%s was founded under an open charter.", settlement.name)
	if settlement.orbital_refuge do founding_detail = fmt.tprintf("%s was founded under an open charter with orbital refuge for %d people.", settlement.name, settlement.orbital_refuge_capacity)
	if reviewed do founding_detail = fmt.tprintf("%s The viability forecast incorporated an independent review.", founding_detail)
	record_event(
		c,
		.Settlement_Founded,
		founding_detail,
		ship.id,
		settlement.population,
		ship.community,
		s.proposal_event,
		settlement_id = settlement.id,
	); settlement.founding_event = c.event_sequence; settlement.last_report_event = c.event_sequence; settlement.decision_event = c.event_sequence; c.settlement_count += 1; c.colony_package_ready = false
}

commit_situation_capacity :: proc(
	c: ^Campaign,
	s: ^Fleet_Situation,
	choice: Situation_Choice,
) -> bool {
	if choice.compute > capacity_available(c.capacities.compute) || choice.manpower > capacity_available(c.capacities.manpower) || choice.raw_materials > capacity_available(c.capacities.raw_materials) do return false
	if choice.compute + choice.manpower + choice.raw_materials == 0 do return true
	slot := -1
	for commitment, i in c.capacity_commitments do if !commitment.active {slot = i; break}
	if slot < 0 do return false
	commitment := &c.capacity_commitments[slot]
	commitment^ = {
		active         = true,
		situation_id   = s.id,
		release_season = c.season + (choice.effect == .Full_Rescue && s.kind == .Rescue ? 2 : 1),
		compute        = choice.compute,
		manpower       = choice.manpower,
		raw_materials  = choice.raw_materials,
		detail         = choice.consequence,
	}
	if choice.compute >
	   0 {source := interaction_capacity_source(c, .Compute); if source != 0 {commitment.source_ships[commitment.source_ship_count] = source; commitment.source_ship_count += 1}}
	if choice.manpower >
	   0 {source := interaction_capacity_source(c, .Manpower, commitment.source_ships[:commitment.source_ship_count]); if source != 0 {commitment.source_ships[commitment.source_ship_count] = source; commitment.source_ship_count += 1}}
	if choice.raw_materials >
	   0 {source := interaction_capacity_source(c, .Raw_Materials, commitment.source_ships[:commitment.source_ship_count]); if source != 0 {commitment.source_ships[commitment.source_ship_count] = source; commitment.source_ship_count += 1}}
	for source in commitment.source_ships[:commitment.source_ship_count] {at := ship_index(c, source); if at >= 0 do c.ships[at].current_commitment = choice.consequence}
	c.capacities.compute.reserved +=
		choice.compute; c.capacities.manpower.reserved += choice.manpower; c.capacities.raw_materials.reserved += choice.raw_materials
	record_event(
		c,
		.Capacity_Committed,
		choice.consequence,
		s.initiator,
		choice.compute + choice.manpower + choice.raw_materials,
		s.affected_community,
		s.proposal_event,
	)
	commitment.origin_event = c.event_sequence
	return true
}

resolve_interaction :: proc(c: ^Campaign, choice_index: int) -> bool {
	s := &c.current_situation; if s.phase != .Decision || choice_index < 0 || choice_index >= s.choice_count do return false
	snapshot := campaign_snapshot(c)
	choice :=
		s.choices[choice_index]; if !commit_situation_capacity(c, s, choice) {campaign_destroy_heap(snapshot); return false}
	si := ship_index(c, s.initiator)
	switch s.kind {
	case .Repair_Debt:
		if si >= 0 &&
		   (choice.effect == .Full_Rescue ||
				   choice.effect ==
					   .Bounded_Rescue) {repair := i32(choice.effect == .Full_Rescue ? 2 : 1); c.ships[si].damage = max(c.ships[si].damage - repair, 0); if choice.effect == .Full_Rescue {ship_clear_impairments(&c.ships[si])} else {_ = ship_clear_one_impairment(&c.ships[si])}; if choice.effect == .Full_Rescue && s.position_count > 1 do _ = interaction_change_bond(c, s.initiator, s.positions[1].ship, 1, s.proposal_event); add_ship_history(c, s.initiator, fmt.tprintf("Received repairs after E%03d.", s.origin_event))} else if si >= 0 do add_ship_history(c, s.initiator, fmt.tprintf("Repair was refused after E%03d.", s.origin_event))
	case .Rescue:
		if choice.effect ==
		   .Full_Rescue {_ = set_ship_community_relationship(c, s.initiator, s.affected_community, .Sponsorship, 1); for &hook in c.history_hooks[:c.history_hook_count] do if hook.community == s.affected_community {hook.stage = .Consequence; hook.consequence_event = s.proposal_event}}
		if choice.effect == .Promise_Return do _ = add_promise(c, s.affected_community, c.season + 1, "Transfer the sponsored survivors to stable fleet berths.")
		if choice.effect ==
		   .Refuse_Rescue {_ = set_ship_community_relationship(c, s.initiator, s.affected_community, .Unanswered_Obligation, -2); if si >= 0 do c.ships[si].pending_claim = "The rescue request was declined under fleet authority."}
	case .Settlement:
		if choice.effect == .Delay {
			candidate_at := candidate_home_index(c, s.celestial)
			if candidate_at >= 0 do c.candidate_homes[candidate_at].independent_review = true
		}
		resolve_settlement_interaction(c, s, choice.effect)
	case .Contested_Evidence:
		ei := event_index_by_sequence(c, s.origin_event)
		if ei >= 0 {
			if choice.effect == .Publish_Evidence do c.events[ei].account_exposed = true
			if choice.effect == .Review_Evidence do _ = add_promise(c, s.affected_community, c.season + 1, "Publish the independent review of the contested report.")
			if choice.effect == .Restricted_Disclosure && si >= 0 do c.ships[si].pending_claim = "Received the contested evidence under a restriction; the fleet record remains disputed."
			if choice.effect == .Conceal_Evidence && si >= 0 do c.ships[si].pending_claim = "The authoritative report remains withheld from the fleet."
		}
	case .Combat_Aftermath:
		#partial switch choice.effect {
		case .Honor_Combat_Withdrawal:
			_ = enact_precedent_after_event(
				c,
				.Ship_Sovereignty,
				"Damaged ships may withdraw from combat under their own authority.",
				s.proposal_event,
			)
		case .Commend_Combat_Recovery:
			c.strategic.cohesion = min(c.strategic.cohesion + 3, 100)
			if si >= 0 do add_ship_history(c, s.initiator, "Received the fleet's commendation after the operation.")
		case .Expand_Combat_Authority:
			_ = enact_precedent_after_event(
				c,
				.Emergency_Command,
				"Command may extend pursuit during a declared fleet operation.",
				s.proposal_event,
			)
			if at := institution_index(c, 1); at >= 0 do c.institutions[at].legitimacy = max(c.institutions[at].legitimacy - 4, 0)
		case:
		}
	case .Value_No_One_Left_Behind,
	     .Value_Truth_Before_Comfort,
	     .Value_Consent_To_Settle,
	     .Value_Shelter_Is_Sacred,
	     .Value_Shared_Authority,
	     .Value_Open_Archives,
	     .Value_The_Fleet_Endures,
	     .Value_Every_Home_Is_Free,
	     .None:
	}
	s.selected_choice = choice_index; s.phase = .Resolved
	record_event(
		c,
		.Situation_Decided,
		choice.consequence,
		s.initiator,
		i32(s.kind),
		s.affected_community,
		s.proposal_event,
	)
	s.decision_event = c.event_sequence
	if s.kind >= .Value_No_One_Left_Behind && s.kind <= .Value_Every_Home_Is_Free do if !resolve_value_hard_case(c, s, choice) {_ = campaign_restore(c, snapshot^); free(snapshot); return false}
	if !record_situation_law(
		c,
		s,
		choice,
	) {_ = campaign_restore(c, snapshot^); free(snapshot); return false}
	record_event(
		c,
		.Situation_Complied,
		choice.consequence,
		s.initiator,
		i32(s.kind),
		s.affected_community,
		s.decision_event,
	); for position in s.positions[:s.position_count] {at := ship_index(c, position.ship); if at >= 0 do c.ships[at].current_position = ""}; refresh_capacity_state(c); campaign_destroy_heap(snapshot); return true
}

release_situation_capacity :: proc(c: ^Campaign) {
	for &commitment in c.capacity_commitments {if !commitment.active || commitment.release_season > c.season do continue; c.capacities.compute.reserved = max(c.capacities.compute.reserved - commitment.compute, 0); c.capacities.manpower.reserved = max(c.capacities.manpower.reserved - commitment.manpower, 0); c.capacities.raw_materials.reserved = max(c.capacities.raw_materials.reserved - commitment.raw_materials, 0); for source in commitment.source_ships[:commitment.source_ship_count] {at := ship_index(c, source); if at >= 0 do c.ships[at].current_commitment = ""}; record_event(c, .Capacity_Released, commitment.detail, value = commitment.compute + commitment.manpower + commitment.raw_materials, cause_sequence = commitment.origin_event); commitment.active = false}
}
