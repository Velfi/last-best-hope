package game

import "core:fmt"
import "core:testing"

MAX_CONSTITUENCIES :: 64
MAX_POLITICAL_MOVEMENTS :: 12
MAX_POLITICAL_MEASURES :: 16
MAX_POLITICAL_COMMITMENTS :: 24
MAX_JURISDICTION_EDGES :: 64
MAX_MOVEMENT_CONSTITUENCIES :: 16
MAX_RIVAL_AUTHORITIES :: 12

Affiliation :: enum u8 {
	Community,
	Ship_Crew,
	Navigation,
	Habitat,
	Industry,
	Care,
	Faith,
	Institution,
}
Affiliation_Set :: bit_set[Affiliation;u16]

Political_Pressure :: enum {
	Concern,
	Organizing,
	Pressing,
	Defiant,
	Schismatic,
}
Political_Measure_Kind :: enum {
	Resource_Allocation,
	Expedition_Priority,
	Ship_Assignment,
	Institution_Custody,
	Jurisdiction,
	Representation,
	Settlement_Terms,
	Standing_Doctrine,
}
Political_Measure_Status :: enum {
	Proposed,
	Referred,
	Amended,
	Enacted,
	Delayed,
	Rejected,
	Appealed,
	Superseded,
}
Political_Commitment_Kind :: enum {
	Allocate_Stores,
	Reserve_Ship,
	Commission_Expedition,
	Guarantee_Berths,
	Transfer_Jurisdiction,
	Transfer_Custody,
	Establish_Representation,
	Disclose_Record,
	Meet_Deadline,
}
Political_Commitment_Status :: enum {
	Proposed,
	Binding,
	Fulfilled,
	Breached,
	Renegotiated,
	Released,
}
Political_Authority_Kind :: enum {
	Ship,
	Institution,
	Settlement,
	Fleet,
}
Political_Route_Result :: enum {
	Local,
	Escalated,
	Contested,
}

Constituency :: struct {
	id:                           u32,
	community:                    Community_ID,
	ship:                         Ship_ID,
	institution:                  Institution_ID,
	affiliations:                 Affiliation_Set,
	population, political_weight: i32,
	active:                       bool,
}

Political_Measure :: struct {
	id:                                                                u32,
	kind:                                                              Political_Measure_Kind,
	status:                                                            Political_Measure_Status,
	movement:                                                          u32,
	target_ship:                                                       Ship_ID,
	target_institution, responsible_institution:                       Institution_ID,
	target_settlement:                                                 Settlement_ID,
	requested_authority:                                               Authority_Policy,
	responsible_kind:                                                  Political_Authority_Kind,
	responsible_id:                                                    u32,
	resource_cost:                                                     i32,
	deadline:                                                          i32,
	requires_precedent, formal_appeal, player_attention, acknowledged: bool,
	source_event, last_event:                                          u64,
}

Political_Movement :: struct {
	id, measure:              u32,
	active:                   bool,
	pressure:                 Political_Pressure,
	constituencies:           [MAX_MOVEMENT_CONSTITUENCIES]u32,
	constituency_count:       int,
	support_weight, leverage: i32,
	spokesperson:             Figure_ID,
	origin_event, last_event: u64,
	warned:                   bool,
}

Jurisdiction_Edge :: struct {
	id:                 u32,
	active:             bool,
	from_kind, to_kind: Political_Authority_Kind,
	from_id, to_id:     u32,
	measure_kind:       Political_Measure_Kind,
	precedent_event:    u64,
}

Political_Commitment :: struct {
	id, source_measure:       u32,
	kind:                     Political_Commitment_Kind,
	status:                   Political_Commitment_Status,
	issuer:                   Institution_ID,
	beneficiary_community:    Community_ID,
	beneficiary_movement:     u32,
	ship:                     Ship_ID,
	institution:              Institution_ID,
	settlement:               Settlement_ID,
	materials, propellant, value:   i32,
	due_season:               i32,
	origin_event, last_event: u64,
}

Rival_Authority :: struct {
	id, source_movement:      u32,
	active:                   bool,
	ship:                     Ship_ID,
	community:                Community_ID,
	population:               i32,
	origin_event, last_event: u64,
}

Dynamic_Politics_State :: struct {
	initialized:                                                                               bool,
	constituencies:                                                                            [MAX_CONSTITUENCIES]Constituency,
	constituency_count:                                                                        int,
	movements:                                                                                 [MAX_POLITICAL_MOVEMENTS]Political_Movement,
	movement_count:                                                                            int,
	measures:                                                                                  [MAX_POLITICAL_MEASURES]Political_Measure,
	measure_count:                                                                             int,
	jurisdiction:                                                                              [MAX_JURISDICTION_EDGES]Jurisdiction_Edge,
	jurisdiction_count:                                                                        int,
	commitments:                                                                               [MAX_POLITICAL_COMMITMENTS]Political_Commitment,
	commitment_count:                                                                          int,
	rivals:                                                                                    [MAX_RIVAL_AUTHORITIES]Rival_Authority,
	rival_count:                                                                               int,
	next_constituency_id,
	next_movement_id,
	next_measure_id,
	next_edge_id,
	next_commitment_id: u32,
}

political_pressure_label :: proc(p: Political_Pressure) -> string {
	switch p {case .Concern:
		return "scattered concern"; case .Organizing:
		return "gathering support"; case .Pressing:
		return "broad pressure"; case .Defiant:
		return "open defiance"; case .Schismatic:
		return "separate authority"}
	return "quiet"
}

political_measure_name :: proc(kind: Political_Measure_Kind) -> string {
	switch kind {case .Resource_Allocation:
		return "allocation measure"; case .Expedition_Priority:
		return "expedition priority"; case .Ship_Assignment:
		return "ship assignment"; case .Institution_Custody:
		return "institutional custody"; case .Jurisdiction:
		return "ship authority measure"; case .Representation:
		return "representation measure"; case .Settlement_Terms:
		return "settlement terms"; case .Standing_Doctrine:
		return "fleet doctrine measure"}
	return "measure"
}

political_authority_name :: proc(c: ^Campaign, m: Political_Measure) -> string {switch
	m.responsible_kind {case .Ship:
		return political_ship_name(c, Ship_ID(m.responsible_id)); case .Institution:
		return institution_name(c, Institution_ID(m.responsible_id)); case .Settlement:
		if i := settlement_index(c, Settlement_ID(m.responsible_id)); i >= 0 do return c.settlements[i].name; case .Fleet:
		return "fleet coordination"}
	return "fleet coordination"}

political_constituency_affiliations :: proc(c: ^Campaign, ship: Ship) -> Affiliation_Set {
	r: Affiliation_Set = {.Community, .Ship_Crew}
	switch ship.role {case .Survey:
		r += {.Navigation}; case .Escort:
		r += {.Institution}; case .Habitat, .Colony:
		r += {.Habitat}; case .Foundry, .Agriculture:
		r += {.Industry}; case .Hospital:
		r += {.Care}; case .Archive:
		r += {.Faith}}
	return r
}

political_ship_name :: proc(c: ^Campaign, id: Ship_ID) -> string {if i := ship_index(c, id); i >= 0 do return c.ships[i].name
	return "the named ship"}

refresh_political_constituencies :: proc(c: ^Campaign) {
	p := &c.politics; community_ship_counts: [MAX_COMMUNITIES]i32
	for ship in c.ships[:c.ship_count] do if ship.active {if ci := community_index(c, ship.community); ci >= 0 do community_ship_counts[ci] += 1}
	for &constituency in p.constituencies[:p.constituency_count] do constituency.active = false
	for ship in c.ships[:c.ship_count] {
		ci := community_index(c, ship.community); if ci < 0 do continue
		at := -1; for constituency, i in p.constituencies[:p.constituency_count] do if constituency.ship == ship.id {at = i; break}
		if at <
		   0 {if p.constituency_count >= MAX_CONSTITUENCIES do continue; at = p.constituency_count; p.constituency_count += 1; p.constituencies[at].id = p.next_constituency_id; p.next_constituency_id += 1}
		population := max(
			c.communities[ci].population / max(community_ship_counts[ci], 1),
			ship.crew,
		)
		p.constituencies[at].community =
			ship.community; p.constituencies[at].ship = ship.id; p.constituencies[at].institution = captain_institution_for_role(ship.role); p.constituencies[at].affiliations = political_constituency_affiliations(c, ship); p.constituencies[at].population = population; p.constituencies[at].political_weight = max(population / 1000, 1); p.constituencies[at].active = ship.active
	}
}

ensure_jurisdiction_edge :: proc(
	c: ^Campaign,
	from_kind: Political_Authority_Kind,
	from_id: u32,
	to_kind: Political_Authority_Kind,
	to_id: u32,
	kind: Political_Measure_Kind,
	precedent: u64 = 0,
) {
	p := &c.politics
	for &edge in p.jurisdiction[:p.jurisdiction_count] do if edge.from_kind == from_kind && edge.from_id == from_id && edge.to_kind == to_kind && edge.to_id == to_id && edge.measure_kind == kind {edge.active = true; edge.precedent_event = precedent; return}
	if p.jurisdiction_count >= MAX_JURISDICTION_EDGES do return
	p.jurisdiction[p.jurisdiction_count] = {
		id              = p.next_edge_id,
		active          = true,
		from_kind       = from_kind,
		to_kind         = to_kind,
		from_id         = from_id,
		to_id           = to_id,
		measure_kind    = kind,
		precedent_event = precedent,
	}; p.next_edge_id += 1; p.jurisdiction_count += 1
}

refresh_jurisdiction_graph :: proc(c: ^Campaign) {
	p := &c.politics; for &edge in p.jurisdiction[:p.jurisdiction_count] do edge.active = false
	sovereignty := precedent_event_for(c, .Ship_Sovereignty)
	for measure in p.measures[:p.measure_count] {
		if measure.status == .Enacted || measure.status == .Rejected || measure.status == .Superseded do continue
		if measure.target_ship !=
		   0 {if si := ship_index(c, measure.target_ship); si >= 0 && c.ships[si].active {institution := captain_institution_for_role(c.ships[si].role); if measure.kind == .Jurisdiction && sovereignty != 0 {ensure_jurisdiction_edge(c, .Ship, u32(measure.target_ship), .Ship, u32(measure.target_ship), measure.kind, sovereignty)} else {ensure_jurisdiction_edge(c, .Ship, u32(measure.target_ship), .Institution, u32(institution), measure.kind)}; ensure_jurisdiction_edge(c, .Institution, u32(institution), .Fleet, 1, measure.kind)}}
		if measure.target_institution !=
		   0 {ensure_jurisdiction_edge(c, .Institution, u32(measure.target_institution), .Institution, u32(measure.target_institution), measure.kind)}
		if measure.target_settlement !=
		   0 {ensure_jurisdiction_edge(c, .Settlement, u32(measure.target_settlement), .Fleet, 1, measure.kind)}
	}
}

initialize_dynamic_politics :: proc(c: ^Campaign) {
	p := &c.politics
	if p.initialized do return
	p.initialized =
		true; p.next_constituency_id = 1; p.next_movement_id = 1; p.next_measure_id = 1; p.next_edge_id = 1; p.next_commitment_id = 1
	refresh_political_constituencies(c); refresh_jurisdiction_graph(c)
}

political_measure_index :: proc(c: ^Campaign, id: u32) -> int {for m, i in c.politics.measures[:c.politics.measure_count] do if m.id == id do return i
	return -1}
political_movement_index :: proc(c: ^Campaign, id: u32) -> int {for m, i in c.politics.movements[:c.politics.movement_count] do if m.id == id do return i
	return -1}
political_commitment_index :: proc(c: ^Campaign, id: u32) -> int {for v, i in c.politics.commitments[:c.politics.commitment_count] do if v.id == id do return i
	return -1}
political_constituency_index :: proc(c: ^Campaign, id: u32) -> int {for v, i in c.politics.constituencies[:c.politics.constituency_count] do if v.id == id do return i
	return -1}

reusable_political_slots :: proc(c: ^Campaign) -> (int, int) {
	for movement, i in c.politics.movements[:c.politics.movement_count] {
		if movement.active do continue; blocked := false
		for rival in c.politics.rivals[:c.politics.rival_count] do if rival.active && rival.source_movement == movement.id {blocked = true; break}
		if blocked do continue
		mi := political_measure_index(c, movement.measure); if mi < 0 do continue
		for commitment in c.politics.commitments[:c.politics.commitment_count] do if commitment.status == .Binding && commitment.source_measure == movement.measure {blocked = true; break}
		if !blocked do return i, mi
	}
	return -1, -1
}

validate_dynamic_politics :: proc(c: ^Campaign) -> bool {
	p := &c.politics; if !p.initialized do return p.constituency_count == 0 && p.movement_count == 0 && p.measure_count == 0 && p.jurisdiction_count == 0 && p.commitment_count == 0 && p.rival_count == 0
	if p.constituency_count < 0 || p.constituency_count > MAX_CONSTITUENCIES || p.movement_count < 0 || p.movement_count > MAX_POLITICAL_MOVEMENTS || p.measure_count < 0 || p.measure_count > MAX_POLITICAL_MEASURES || p.jurisdiction_count < 0 || p.jurisdiction_count > MAX_JURISDICTION_EDGES || p.commitment_count < 0 || p.commitment_count > MAX_POLITICAL_COMMITMENTS || p.rival_count < 0 || p.rival_count > MAX_RIVAL_AUTHORITIES do return false
	max_constituency, max_movement, max_measure, max_edge, max_commitment: u32
	for item, i in p.constituencies[:p.constituency_count] {if item.id == 0 || community_index(c, item.community) < 0 || ship_index(c, item.ship) < 0 || item.population < 0 || item.political_weight < 0 do return false; for prior in p.constituencies[:i] do if prior.id == item.id do return false; max_constituency = max(max_constituency, item.id)}
	for item, i in p.measures[:p.measure_count] {if item.id == 0 || int(item.kind) < 0 || int(item.kind) > int(Political_Measure_Kind.Standing_Doctrine) || int(item.status) < 0 || int(item.status) > int(Political_Measure_Status.Superseded) || political_movement_index(c, item.movement) < 0 do return false; for prior in p.measures[:i] do if prior.id == item.id do return false; max_measure = max(max_measure, item.id)}
	for item, i in p.movements[:p.movement_count] {
		mi := political_measure_index(c, item.measure)
		if item.id == 0 || mi < 0 || p.measures[mi].movement != item.id || item.constituency_count < 0 || item.constituency_count > MAX_MOVEMENT_CONSTITUENCIES || int(item.pressure) < 0 || int(item.pressure) > int(Political_Pressure.Schismatic) do return false
		for prior in p.movements[:i] do if prior.id == item.id do return false
		for j in 0 ..< item.constituency_count {
			cid := item.constituencies[j]
			if political_constituency_index(c, cid) < 0 do return false
			for k in 0 ..< j do if item.constituencies[k] == cid do return false
		}
		max_movement = max(max_movement, item.id)
	}
	for item, i in p.jurisdiction[:p.jurisdiction_count] {if item.id == 0 || int(item.measure_kind) < 0 || int(item.measure_kind) > int(Political_Measure_Kind.Standing_Doctrine) do return false; for prior in p.jurisdiction[:i] do if prior.id == item.id do return false; max_edge = max(max_edge, item.id)}
	for item, i in p.commitments[:p.commitment_count] {if item.id == 0 || item.source_measure == 0 || item.status == .Binding && political_measure_index(c, item.source_measure) < 0 || int(item.kind) < 0 || int(item.kind) > int(Political_Commitment_Kind.Meet_Deadline) || int(item.status) < 0 || int(item.status) > int(Political_Commitment_Status.Released) || item.ship != 0 && ship_index(c, item.ship) < 0 do return false; for prior in p.commitments[:i] do if prior.id == item.id do return false; max_commitment = max(max_commitment, item.id)}
	for item, i in p.rivals[:p.rival_count] {if item.id == 0 || item.active && political_movement_index(c, item.source_movement) < 0 || ship_index(c, item.ship) < 0 || community_index(c, item.community) < 0 || item.population < 0 do return false; for prior in p.rivals[:i] do if prior.id == item.id do return false}
	return(
		p.next_constituency_id > max_constituency &&
		p.next_movement_id > max_movement &&
		p.next_measure_id > max_measure &&
		p.next_edge_id > max_edge &&
		p.next_commitment_id > max_commitment \
	)
}

political_route_measure :: proc(c: ^Campaign, m: ^Political_Measure) -> Political_Route_Result {
	refresh_jurisdiction_graph(c)
	if m.formal_appeal ||
	   m.requires_precedent ||
	   m.resource_cost >
		   fleet_materials(c) /
			   4 {m.responsible_kind = .Fleet; m.responsible_id = 1; m.player_attention = true; return .Escalated}
	if m.target_ship == 0 &&
	   m.target_settlement == 0 &&
	   m.target_institution !=
		   0 {if institution_index(c, m.target_institution) < 0 {m.player_attention = true; return .Escalated}; m.responsible_kind = .Institution; m.responsible_id = u32(m.target_institution); m.responsible_institution = m.target_institution; m.player_attention = false; return .Local}
	if m.target_ship !=
	   0 {if si := ship_index(c, m.target_ship); si >= 0 {institution := captain_institution_for_role(c.ships[si].role); sovereignty := precedent_event_for(c, .Ship_Sovereignty); if m.kind == .Jurisdiction && sovereignty != 0 {ensure_jurisdiction_edge(c, .Ship, u32(m.target_ship), .Ship, u32(m.target_ship), m.kind, sovereignty)} else {ensure_jurisdiction_edge(c, .Ship, u32(m.target_ship), .Institution, u32(institution), m.kind)}}}
	if m.target_institution != 0 do ensure_jurisdiction_edge(c, .Institution, u32(m.target_institution), .Fleet, 1, m.kind)
	if m.target_settlement != 0 do ensure_jurisdiction_edge(c, .Settlement, u32(m.target_settlement), .Fleet, 1, m.kind)
	from_kind := Political_Authority_Kind.Fleet; from_id := u32(1)
	if m.target_ship !=
	   0 {from_kind = .Ship; from_id = u32(m.target_ship)} else if m.target_institution != 0 {from_kind = .Institution; from_id = u32(m.target_institution)} else if m.target_settlement != 0 {from_kind = .Settlement; from_id = u32(m.target_settlement)}
	found :=
		false; contested := false; destination_kind := Political_Authority_Kind.Fleet; destination_id := u32(1)
	for edge in c.politics.jurisdiction[:c.politics.jurisdiction_count] do if edge.active && edge.from_kind == from_kind && edge.from_id == from_id && edge.measure_kind == m.kind {
		if found && (edge.to_kind != destination_kind || edge.to_id != destination_id) do contested = true
		if !found {destination_kind = edge.to_kind; destination_id = edge.to_id; found = true}
	}
	if !found {m.responsible_kind = .Fleet; m.responsible_id = 1; m.player_attention = true; return .Escalated}
	m.responsible_kind = destination_kind; m.responsible_id = destination_id
	if destination_kind == .Institution do m.responsible_institution = Institution_ID(destination_id)
	if contested {m.player_attention = true; return .Contested}
	if destination_kind == .Fleet {m.player_attention = true; return .Escalated}
	m.player_attention = false; return .Local
}

form_fleet_authority_movement :: proc(c: ^Campaign, ship: Ship_ID, source: u64) -> u32 {
	if source == 0 do return 0; initialize_dynamic_politics(c); p := &c.politics
	measure_slot := -1; movement_slot := -1
	for prior, i in p.movements[:p.movement_count] {mi := political_measure_index(c, prior.measure); if mi < 0 || p.measures[mi].kind != .Jurisdiction || p.measures[mi].target_ship != ship do continue; if prior.active do return prior.id; if source == 0 || source <= p.measures[mi].last_event do return 0; movement_slot = i; measure_slot = mi; break}
	measure_id := u32(0); movement_id := u32(0)
	if movement_slot >=
	   0 {measure_id = p.measures[measure_slot].id; movement_id = p.movements[movement_slot].id} else {
		if p.movement_count >= MAX_POLITICAL_MOVEMENTS ||
		   p.measure_count >=
			   MAX_POLITICAL_MEASURES {movement_slot, measure_slot = reusable_political_slots(c); if movement_slot < 0 do return 0} else {measure_slot = p.measure_count; p.measure_count += 1; movement_slot = p.movement_count; p.movement_count += 1}
		measure_id =
			p.next_measure_id; p.next_measure_id += 1; movement_id = p.next_movement_id; p.next_movement_id += 1
	}
	m := &p.measures[measure_slot]; m^ = {
		id                  = measure_id,
		kind                = .Jurisdiction,
		status              = .Proposed,
		movement            = movement_id,
		target_ship         = ship,
		requested_authority = .Ship_Autonomy,
		requires_precedent  = !has_precedent(c, .Ship_Sovereignty),
		deadline            = c.season + 2,
		source_event        = source,
		last_event          = source,
	}
	movement := &p.movements[movement_slot]; movement^ = {
		id           = movement_id,
		measure      = measure_id,
		active       = true,
		pressure     = .Concern,
		origin_event = source,
		last_event   = source,
	}
	seen_weight: i32
	for constituency in p.constituencies[:p.constituency_count] {
		if !constituency.active do continue
		if constituency.ship != ship && .Navigation not_in constituency.affiliations do continue
		if movement.constituency_count >= MAX_MOVEMENT_CONSTITUENCIES do break
		movement.constituencies[movement.constituency_count] =
			constituency.id; movement.constituency_count += 1; seen_weight += constituency.political_weight
	}
	movement.support_weight = seen_weight; movement.leverage = max(seen_weight / 2, 1)
	route := political_route_measure(
		c,
		m,
	); record_event(c, .Situation_Proposed, fmt.tprintf("Crews submitted a ship authority measure for %s.", political_ship_name(c, ship)), ship, community = ship_index(c, ship) >= 0 ? c.ships[ship_index(c, ship)].community : 0, cause_sequence = source); movement.last_event = c.event_sequence; m.last_event = c.event_sequence
	if route ==
	   .Local {m.status = .Referred; record_event(c, .Situation_Response, fmt.tprintf("%s received the ship authority measure.", political_authority_name(c, m^)), ship, institution_id = m.responsible_institution, cause_sequence = m.last_event); m.last_event = c.event_sequence}
	return movement_id
}


