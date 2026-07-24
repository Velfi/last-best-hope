package game

import "core:fmt"
form_issue_movement :: proc(
	c: ^Campaign,
	kind: Political_Measure_Kind,
	ship: Ship_ID,
	institution: Institution_ID,
	settlement: Settlement_ID,
	source: u64,
) -> u32 {
	if source == 0 do return 0; initialize_dynamic_politics(c); p := &c.politics; measure_slot := -1; movement_slot := -1
	for prior, i in p.movements[:p.movement_count] {mi := political_measure_index(c, prior.measure); if mi < 0 || p.measures[mi].kind != kind || p.measures[mi].target_ship != ship || p.measures[mi].target_institution != institution || p.measures[mi].target_settlement != settlement do continue; if prior.active do return prior.id; if source == 0 || source <= p.measures[mi].last_event do return 0; movement_slot = i; measure_slot = mi; break}
	measure_id := u32(0); movement_id := u32(0)
	if movement_slot >=
	   0 {measure_id = p.measures[measure_slot].id; movement_id = p.movements[movement_slot].id} else {if p.movement_count >= MAX_POLITICAL_MOVEMENTS || p.measure_count >= MAX_POLITICAL_MEASURES {movement_slot, measure_slot = reusable_political_slots(c); if movement_slot < 0 do return 0} else {measure_slot = p.measure_count; p.measure_count += 1; movement_slot = p.movement_count; p.movement_count += 1}; measure_id = p.next_measure_id; p.next_measure_id += 1; movement_id = p.next_movement_id; p.next_movement_id += 1}
	m := &p.measures[measure_slot]; m^ = {
		id                 = measure_id,
		kind               = kind,
		status             = .Proposed,
		movement           = movement_id,
		target_ship        = ship,
		target_institution = institution,
		target_settlement  = settlement,
		deadline           = c.season + 2,
		source_event       = source,
		last_event         = source,
	}
	movement := &p.movements[movement_slot]; movement^ = {
		id           = movement_id,
		measure      = measure_id,
		active       = true,
		pressure     = .Concern,
		origin_event = source,
		last_event   = source,
	}
	for constituency in p.constituencies[:p.constituency_count] {
		if !constituency.active do continue; supports := constituency.ship == ship || constituency.institution == institution
		switch kind {case .Resource_Allocation:
			supports =
				supports ||
				.Industry in constituency.affiliations ||
				.Habitat in constituency.affiliations; case .Expedition_Priority:
			supports =
				supports ||
				.Navigation in constituency.affiliations; case .Ship_Assignment, .Jurisdiction:
			supports =
				supports ||
				.Ship_Crew in
					constituency.affiliations; case .Institution_Custody, .Standing_Doctrine:
			supports = supports || .Institution in constituency.affiliations; case .Representation:
			supports = true; case .Settlement_Terms:
			supports = supports || .Habitat in constituency.affiliations}
		if !supports || movement.constituency_count >= MAX_MOVEMENT_CONSTITUENCIES do continue
		movement.constituencies[movement.constituency_count] =
			constituency.id; movement.constituency_count += 1; movement.support_weight += constituency.political_weight
	}
	movement.leverage = max(
		movement.support_weight / 2,
		1,
	); route := political_route_measure(c, m); record_event(c, .Situation_Proposed, fmt.tprintf("Constituencies submitted a %s.", political_measure_name(kind)), ship, community = movement.constituency_count > 0 ? p.constituencies[political_constituency_index(c, movement.constituencies[0])].community : 0, cause_sequence = source); m.last_event = c.event_sequence; movement.last_event = c.event_sequence
	if route ==
	   .Local {m.status = .Referred; record_event(c, .Situation_Response, fmt.tprintf("%s received the %s.", political_authority_name(c, m^), political_measure_name(kind)), ship, institution_id = m.responsible_institution, cause_sequence = m.last_event); m.last_event = c.event_sequence}
	return movement_id
}

offer_political_commitment :: proc(
	c: ^Campaign,
	measure_id: u32,
	kind: Political_Commitment_Kind,
	ship: Ship_ID = 0,
	materials: i32 = 0,
	due_season: i32 = 0,
) -> u32 {
	initialize_dynamic_politics(c); p := &c.politics; mi := political_measure_index(c, measure_id)
	if mi < 0 || int(kind) < 0 || int(kind) > int(Political_Commitment_Kind.Meet_Deadline) || materials < 0 || materials > fleet_materials(c) do return 0
	m := &p.measures[mi]; movement_index := political_movement_index(c, m.movement); if movement_index < 0 do return 0
	effective_ship := ship
	if effective_ship == 0 do effective_ship = m.target_ship
	switch kind {
	case .Allocate_Stores:
		if materials <= 0 do return 0
	case .Reserve_Ship, .Commission_Expedition, .Transfer_Jurisdiction:
		si := ship_index(c, effective_ship)
		if si < 0 || !c.ships[si].active || c.ships[si].committed do return 0
	case .Guarantee_Berths, .Establish_Representation:
		if m.movement == 0 do return 0
	case .Transfer_Custody:
		if m.target_institution == 0 || institution_index(c, m.target_institution) < 0 do return 0
	case .Disclose_Record:
		if m.source_event == 0 do return 0
	case .Meet_Deadline:
		if due_season <= c.season do return 0
	}
	slot := p.commitment_count
	if slot >=
	   MAX_POLITICAL_COMMITMENTS {slot = -1; for item, i in p.commitments[:p.commitment_count] do if item.status != .Binding {slot = i; break}; if slot < 0 do return 0} else {p.commitment_count += 1}
	id := p.next_commitment_id; p.next_commitment_id += 1
	beneficiary := Community_ID(
		0,
	); if movement_index >= 0 && p.movements[movement_index].constituency_count > 0 {constituency_id := p.movements[movement_index].constituencies[0]; for constituency in p.constituencies[:p.constituency_count] do if constituency.id == constituency_id {beneficiary = constituency.community; break}}
	v := &p.commitments[slot]; v^ = {
		id                    = id,
		source_measure        = measure_id,
		kind                  = kind,
		status                = .Binding,
		issuer                = m.responsible_institution,
		beneficiary_community = beneficiary,
		beneficiary_movement  = m.movement,
		ship                  = effective_ship,
		institution           = m.target_institution,
		settlement            = m.target_settlement,
		materials             = materials,
		due_season            = due_season,
	}
	if materials > 0 && !fleet_stock_spend(c, {manufactured_goods = i64(materials)}, .Committed) do return 0
	if kind == .Reserve_Ship ||
	   kind == .Commission_Expedition ||
	   kind == .Transfer_Jurisdiction {si := ship_index(c, v.ship); c.ships[si].committed = true}
	detail := fmt.tprintf(
		"A binding %v commitment entered the %s.",
		kind,
		political_measure_name(m.kind),
	); if v.ship != 0 do detail = fmt.tprintf("A binding %v commitment named %s.", kind, political_ship_name(c, v.ship))
	record_event(
		c,
		.Capacity_Committed,
		detail,
		v.ship,
		value = materials,
		community = beneficiary,
		cause_sequence = m.last_event,
		institution_id = v.issuer,
	); v.origin_event = c.event_sequence; v.last_event = c.event_sequence
	return id
}

release_political_ship_reservation :: proc(c: ^Campaign, ship: Ship_ID, except: u32) {if ship == 0 do return
	for v in c.politics.commitments[:c.politics.commitment_count] do if v.id != except && v.status == .Binding && v.ship == ship && (v.kind == .Reserve_Ship || v.kind == .Commission_Expedition || v.kind == .Transfer_Jurisdiction) do return
	if si := ship_index(c, ship); si >= 0 do c.ships[si].committed = false}

resolve_political_commitment :: proc(
	c: ^Campaign,
	id: u32,
	status: Political_Commitment_Status,
) -> bool {
	if int(status) < 0 || int(status) > int(Political_Commitment_Status.Released) || status == .Proposed || status == .Binding do return false
	i := political_commitment_index(c, id); if i < 0 do return false
	v := &c.politics.commitments[i]; if v.status != .Binding do return false
	v.status = status; release_political_ship_reservation(c, v.ship, v.id)
	if status == .Released ||
	   status ==
		   .Renegotiated {fleet_stock_gain(c, {manufactured_goods = i64(v.materials)}, .Recovery, v.origin_event)}
	if status == .Fulfilled {
		switch v.kind {
		case .Allocate_Stores:
		case .Reserve_Ship, .Commission_Expedition:
		case .Guarantee_Berths:
			if ci := community_index(c, v.beneficiary_community);
			   ci >=
			   0 {c.communities[ci].trust = min(c.communities[ci].trust + 3, 100); c.communities[ci].grievance = max(c.communities[ci].grievance - 1, 0)}
		case .Transfer_Jurisdiction:
			mi := political_measure_index(c, v.source_measure)
			if mi >= 0 {m := &c.politics.measures[mi]; if ii := institution_index(c, m.responsible_institution); ii >= 0 do c.institutions[ii].authority_policy = m.requested_authority; _ = set_institution_ship_relationship(c, m.responsible_institution, v.ship, .Reconciled, 2, v.last_event, m.source_event); refresh_jurisdiction_graph(c)}
		case .Transfer_Custody:
			if v.institution != 0 && v.ship != 0 do _ = place_institution(c, v.institution, .Ship_Bound, v.ship, 0, v.last_event)
		case .Establish_Representation:
			if ci := community_index(c, v.beneficiary_community);
			   ci >=
			   0 {c.communities[ci].petitions_honored += 1; c.communities[ci].trust = min(c.communities[ci].trust + 2, 100)}
		case .Disclose_Record:
			if ii := institution_index(c, v.issuer); ii >= 0 do c.institutions[ii].disclosure_policy = .Open
		case .Meet_Deadline:
		}
	}
	kind := status == .Breached ? Event_Kind.Promise_Changed : Event_Kind.Capacity_Released
	record_event(
		c,
		kind,
		fmt.tprintf("Political commitment %d was %v.", id, status),
		v.ship,
		value = i32(status),
		cause_sequence = v.last_event,
	); v.last_event = c.event_sequence
	mi := political_movement_index(
		c,
		v.beneficiary_movement,
	); if mi >= 0 {movement := &c.politics.movements[mi]; if status == .Fulfilled {movement.pressure = Political_Pressure(max(int(movement.pressure) - 2, 0))} else if status == .Breached {movement.pressure = Political_Pressure(min(int(movement.pressure) + 2, int(Political_Pressure.Schismatic)))}; movement.last_event = v.last_event}
	return true
}

ratify_political_measure :: proc(c: ^Campaign, id: u32, accept: bool) -> bool {
	i := political_measure_index(c, id); if i < 0 do return false; m := &c.politics.measures[i]
	if m.status == .Enacted || m.status == .Rejected || m.status == .Superseded do return false
	movement_index := political_movement_index(
		c,
		m.movement,
	); if movement_index < 0 do return false; movement := &c.politics.movements[movement_index]
	has_binding :=
		false; for v in c.politics.commitments[:c.politics.commitment_count] do if v.source_measure == m.id && v.status == .Binding {has_binding = true; break}
	if accept && !has_binding && movement.pressure < .Pressing do return false
	if accept {m.status = .Enacted; if m.kind == .Jurisdiction && m.requested_authority == .Ship_Autonomy && !has_precedent(c, .Ship_Sovereignty) do _ = enact_precedent_after_event(c, .Ship_Sovereignty, "Ships retain authority within their recorded mandates.", m.last_event); record_event(c, .Jurisdiction_Changed, fmt.tprintf("The ship authority measure for %s was enacted.", political_ship_name(c, m.target_ship)), m.target_ship, institution_id = m.responsible_institution, cause_sequence = m.last_event); for &v in c.politics.commitments[:c.politics.commitment_count] do if v.source_measure == m.id && v.status == .Binding do _ = resolve_political_commitment(c, v.id, .Fulfilled); refresh_jurisdiction_graph(c)} else {m.status = .Rejected; movement.pressure = Political_Pressure(min(int(movement.pressure) + 1, int(Political_Pressure.Schismatic))); record_event(c, .Situation_Decided, fmt.tprintf("The ship authority measure for %s was rejected.", political_ship_name(c, m.target_ship)), m.target_ship, institution_id = m.responsible_institution, cause_sequence = m.last_event)}
	m.last_event = c.event_sequence; return true
}

refer_political_measure :: proc(c: ^Campaign, id: u32, institution: Institution_ID) -> bool {
	i := political_measure_index(
		c,
		id,
	); ii := institution_index(c, institution); if i < 0 || ii < 0 || !c.institutions[ii].active do return false
	m := &c.politics.measures[i]; if m.status == .Enacted || m.status == .Rejected || m.status == .Superseded do return false
	m.responsible_institution = institution; m.status = .Referred; m.player_attention = false
	record_event(
		c,
		.Situation_Response,
		fmt.tprintf(
			"%s received the %s.",
			c.institutions[ii].name,
			political_measure_name(m.kind),
		),
		m.target_ship,
		institution_id = institution,
		cause_sequence = m.last_event,
	); m.last_event = c.event_sequence; return true
}

appeal_political_measure :: proc(c: ^Campaign, id: u32) -> bool {
	i := political_measure_index(c, id); if i < 0 do return false; m := &c.politics.measures[i]
	if m.status == .Enacted || m.status == .Rejected || m.status == .Superseded do return false
	m.formal_appeal = true; m.player_attention = true; m.status = .Appealed
	record_event(
		c,
		.Situation_Response,
		fmt.tprintf("The %s was appealed to fleet coordination.", political_measure_name(m.kind)),
		m.target_ship,
		institution_id = m.responsible_institution,
		cause_sequence = m.last_event,
	); m.last_event = c.event_sequence; return true
}

acknowledge_political_resolution :: proc(c: ^Campaign, id: u32) -> bool {
	i := political_measure_index(c, id); if i < 0 do return false; m := &c.politics.measures[i]
	if m.acknowledged || m.player_attention || m.status != .Enacted && m.status != .Rejected && m.status != .Superseded do return false
	m.acknowledged =
		true; record_event(c, .Situation_Response, fmt.tprintf("Fleet coordination acknowledged the autonomous %s resolution.", political_measure_name(m.kind)), m.target_ship, cause_sequence = m.last_event); m.last_event = c.event_sequence; return true
}

political_schism :: proc(c: ^Campaign, movement: ^Political_Movement) {
	mi := political_measure_index(
		c,
		movement.measure,
	); if mi < 0 do return; m := &c.politics.measures[mi]
	ship :=
		m.target_ship; si := ship_index(c, ship); created := false; rival_slot := -1; for rival, i in c.politics.rivals[:c.politics.rival_count] do if !rival.active {rival_slot = i; break}; if rival_slot < 0 && c.politics.rival_count < MAX_RIVAL_AUTHORITIES {rival_slot = c.politics.rival_count; c.politics.rival_count += 1}
	if si >= 0 && c.ships[si].active && rival_slot >= 0 {
		community :=
			c.ships[si].community; population := max(c.ships[si].crew, 1); if ci := community_index(c, community); ci >= 0 {population = min(population, max(c.communities[ci].population - 1, 0)); c.communities[ci].population -= population}
		c.ships[si].departure = .Political_Schism; c.ships[si].active = false; c.ships[si].committed = false
		rival := &c.politics.rivals[rival_slot]; rival_id := rival.id; if rival_id == 0 do rival_id = u32(rival_slot + 1); rival^ = {
			id              = rival_id,
			source_movement = movement.id,
			active          = true,
			ship            = ship,
			community       = community,
			population      = population,
		}
		record_event(
			c,
			.Jurisdiction_Changed,
			fmt.tprintf(
				"%s departed under separate authority with %d people.",
				c.ships[si].name,
				population,
			),
			ship,
			value = population,
			community = community,
			cause_sequence = movement.last_event,
		); movement.last_event = c.event_sequence; rival.origin_event = c.event_sequence; rival.last_event = c.event_sequence
		created = true
	}
	if created {movement.pressure = .Schismatic; movement.active = false; m.status = .Superseded; m.last_event = movement.last_event} else {movement.pressure = .Defiant; movement.warned = true}
}

reconcile_rival_authority :: proc(c: ^Campaign, id: u32) -> bool {
	for &rival in c.politics.rivals[:c.politics.rival_count] do if rival.id == id && rival.active {
		si := ship_index(c, rival.ship); ci := community_index(c, rival.community); if si < 0 || ci < 0 do return false
		c.ships[si].active = true; c.ships[si].departure = .None; c.communities[ci].population += rival.population; rival.active = false
		record_event(c, .Jurisdiction_Changed, fmt.tprintf("%s returned from separate authority under reconciled terms.", c.ships[si].name), rival.ship, value = rival.population, community = rival.community, cause_sequence = rival.last_event); rival.last_event = c.event_sequence; refresh_political_constituencies(c); refresh_jurisdiction_graph(c); return true
	}
	return false
}

advance_dynamic_politics :: proc(c: ^Campaign) {
	initialize_dynamic_politics(
		c,
	); refresh_political_constituencies(c); refresh_jurisdiction_graph(c)
	// Discoverable disputes seed movements without opening a council form. The
	// first matching record is stable, so observation and UI never affect it.
	has_authority_movement := false
	for movement in c.politics.movements[:c.politics.movement_count] do if movement.active {mi := political_measure_index(c, movement.measure); if mi >= 0 && c.politics.measures[mi].kind == .Jurisdiction {has_authority_movement = true; break}}
	if !has_authority_movement {
		ship := Ship_ID(0); source := u64(0)
		for need in c.needs do if need.active && !need.resolved && need.kind == .Jurisdiction_Dispute {ship = need.ship; source = need.source_event; break}
		if ship ==
		   0 {for relationship in c.institution_ship_relationships[:c.institution_ship_relationship_count] do if relationship.stance == .Contested {ship = relationship.ship; source = relationship.last_event; break}}
		if ship != 0 do _ = form_fleet_authority_movement(c, ship, source)
	}
	for need in c.needs {
		if !need.active || need.resolved || need.kind == .Jurisdiction_Dispute do continue
		kind := Political_Measure_Kind.Resource_Allocation
		switch need.kind {case .Sustenance_Shortfall:
			kind = .Resource_Allocation; case .Settlement_Demand, .Settlement_Charter:
			kind = .Settlement_Terms; case .Ship_Repair:
			kind = .Ship_Assignment; case .Archive_Staffing, .Institution_Dispute:
			kind = .Institution_Custody; case .Settlement_Defense:
			kind = .Standing_Doctrine; case .Representation:
			kind = .Representation; case .Jurisdiction_Dispute:}
		_ = form_issue_movement(
			c,
			kind,
			need.ship,
			need.institution,
			need.settlement,
			need.source_event,
		)
	}
	for front in c.fronts[:c.front_count] {
		if front.dormant || front.pressure < 3 do continue
		switch front.kind {
		case .Closed_Cycle_Ecology:
			ship := first_active_ship_with_role(c, .Agriculture)
			_ = form_issue_movement(c, .Resource_Allocation, ship, captain_institution_for_role(.Agriculture), 0, front.last_change_event)
		case .Passage_Access:
			ship := first_active_ship_with_role(c, .Survey)
			_ = form_issue_movement(c, .Expedition_Priority, ship, captain_institution_for_role(.Survey), 0, front.last_change_event)
		case .Settlement_Obligation:
			settlement := Settlement_ID(0); if c.settlement_count > 0 do settlement = c.settlements[0].id
			_ = form_issue_movement(c, .Settlement_Terms, first_active_ship_with_role(c, .Colony), 0, settlement, front.last_change_event)
		case .Fleet_Authority:
		}
	}
	for &v in c.politics.commitments[:c.politics.commitment_count] do if v.status == .Binding && v.due_season > 0 && c.season > v.due_season do _ = resolve_political_commitment(c, v.id, .Breached)
	for &movement in c.politics.movements[:c.politics.movement_count] {
		if !movement.active do continue
		mi := political_measure_index(
			c,
			movement.measure,
		); if mi < 0 do continue; m := &c.politics.measures[mi]
		if m.status == .Enacted {movement.pressure = .Concern; movement.active = false; continue}
		if m.status == .Referred &&
		   !m.requires_precedent &&
		   c.season > 0 &&
		   c.season >
			   m.deadline {m.status = .Enacted; m.player_attention = false; record_event(c, .Situation_Complied, fmt.tprintf("%s enacted the %s within its jurisdiction.", political_authority_name(c, m^), political_measure_name(m.kind)), m.target_ship, institution_id = m.responsible_institution, cause_sequence = m.last_event); m.last_event = c.event_sequence; movement.last_event = c.event_sequence; movement.active = false; continue}
		has_binding :=
			false; for v in c.politics.commitments[:c.politics.commitment_count] do if v.source_measure == m.id && v.status == .Binding {has_binding = true; break}
		if has_binding {if movement.pressure > .Concern do movement.pressure = Political_Pressure(int(movement.pressure) - 1); continue}
		if c.season > m.deadline && m.deadline > 0 ||
		   c.season > 0 &&
			   c.season % 2 ==
				   0 {if movement.pressure < .Schismatic do movement.pressure = Political_Pressure(int(movement.pressure) + 1)}
		if movement.pressure == .Defiant &&
		   !movement.warned {movement.warned = true; record_event(c, .Situation_Response, fmt.tprintf("The %s reached open defiance; %s may act under separate authority.", political_measure_name(m.kind), political_ship_name(c, m.target_ship)), m.target_ship, cause_sequence = movement.last_event); movement.last_event = c.event_sequence; m.last_event = c.event_sequence}
		if movement.pressure == .Schismatic do political_schism(c, &movement)
	}
}

political_action_warning :: proc(c: ^Campaign, ship: Ship_ID) -> string {
	for v in c.politics.commitments[:c.politics.commitment_count] do if v.status == .Binding && v.ship == ship do return fmt.tprintf("%s is reserved by binding commitment %d; reassigning it will be recorded as a breach.", political_ship_name(c, ship), v.id)
	return ""
}
