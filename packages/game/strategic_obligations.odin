package game

import "core:fmt"

MAX_OBLIGATIONS :: 24

Obligation_Kind :: enum {
	Fleet_Maintenance,
	Settlement_Support,
	Open_Route,
	Archive_Custody,
	Active_Guarantee,
}
Obligation_Status :: enum {
	Active,
	Suspended,
	Reduced,
	Transferred,
	Assumed_By_Settlement,
	Mothballed,
}
Contraction_Choice :: enum {
	Suspend_Route,
	Reduce_Guarantee,
	Mothball_Capability,
	Transfer_Authority,
	Settlement_Assumption,
}

Strategic_Obligation :: struct {
	id:                                                 u32,
	kind:                                               Obligation_Kind,
	status:                                             Obligation_Status,
	name:                                               string,
	compute, manpower, raw_materials, ships, attention: i32,
	ship:                                               Ship_ID,
	settlement:                                         Settlement_ID,
	institution:                                        Institution_ID,
	origin_event, last_event:                           u64,
	underfunded_seasons:                                i32,
}

Obligation_State :: struct {
	initialized:                                                 bool,
	next_id:                                                     u32,
	items:                                                       [MAX_OBLIGATIONS]Strategic_Obligation,
	count:                                                       int,
	reserved_compute, reserved_manpower, reserved_raw_materials: i32,
	attention_total, attention_reserved, underfunded_count:      i32,
	emergency_debt, emergency_due_season:                        i32,
}

obligation_active :: proc(o: Strategic_Obligation) -> bool {return(
		o.status == .Active ||
		o.status == .Reduced \
	)}

add_obligation :: proc(
	c: ^Campaign,
	kind: Obligation_Kind,
	name: string,
	compute, manpower, raw_materials, ships, attention: i32,
	ship := Ship_ID(0),
	settlement := Settlement_ID(0),
	institution := Institution_ID(0),
	cause: u64 = 0,
) -> int {
	s := &c.obligations; if s.count >= MAX_OBLIGATIONS do return -1
	s.next_id += 1; i := s.count; s.count += 1
	s.items[i] = {
		id            = s.next_id,
		kind          = kind,
		status        = .Active,
		name          = name,
		compute       = max(compute, 0),
		manpower      = max(manpower, 0),
		raw_materials = max(raw_materials, 0),
		ships         = max(ships, 0),
		attention     = max(attention, 0),
		ship          = ship,
		settlement    = settlement,
		institution   = institution,
		origin_event  = cause,
		last_event    = cause,
	}
	record_event(
		c,
		.Capacity_Committed,
		fmt.tprintf("%s entered the seasonal ledger.", name),
		ship,
		compute + manpower + raw_materials,
		settlement_id = settlement,
		institution_id = institution,
		cause_sequence = cause,
	)
	s.items[i].origin_event = c.event_sequence; s.items[i].last_event = c.event_sequence
	return i
}

initialize_obligations :: proc(c: ^Campaign) {
	if c.obligations.initialized do return
	c.obligations.initialized = true; c.obligations.attention_total = 10
	_ = add_obligation(c, .Fleet_Maintenance, "Traveling fleet maintenance", 2, 3, 3, 2, 3)
	_ = add_obligation(c, .Open_Route, "Known route watch", 2, 1, 0, 1, 2, institution = 2)
	_ = add_obligation(
		c,
		.Archive_Custody,
		"Unique archive custody",
		2,
		2,
		1,
		1,
		2,
		institution = 3,
	)
}

obligation_substitution :: proc(
	c: ^Campaign,
	o: Strategic_Obligation,
) -> (
	compute, manpower, raw_materials, attention: i32,
	detail: string,
) {
	compute, manpower, raw_materials, attention =
		o.compute, o.manpower, o.raw_materials, o.attention
	// Substitution is earned by this fleet's actual capabilities and public rules.
	if o.kind ==
	   .Fleet_Maintenance {for ship in c.ships[:c.ship_count] do if ship.active && ship.role == .Foundry {raw_materials = max(raw_materials - 1, 0); attention += 1; detail = "foundry substitution"; break}}
	if o.kind == .Archive_Custody &&
	   c.institutions[2].active {manpower = max(manpower - 1, 0); compute += 1; detail = "Seed Archive stewardship"}
	if o.kind == .Open_Route &&
	   precedent_event_for(c, .Shared_Authority) !=
		   0 {attention = max(attention - 1, 0); manpower += 1; detail = "shared-authority watch rotations"}
	if o.ship !=
	   0 {for r in c.ship_relationships[:c.ship_relationship_count] do if (r.ship_a == o.ship || r.ship_b == o.ship) && r.strength >= 2 {attention = max(attention - 1, 0); detail = "bonded-ship rotation"; break}}
	return
}

advance_obligations :: proc(c: ^Campaign) {
	initialize_obligations(c); s := &c.obligations
	major_recorded := false
	emergency_due := s.emergency_debt > 0 && c.season >= s.emergency_due_season
	for settlement in c.settlements[:c.settlement_count] {
		if !settlement.active do continue; found := false; for o in s.items[:s.count] do if o.kind == .Settlement_Support && o.settlement == settlement.id do found = true
		if !found do _ = add_obligation(c, .Settlement_Support, fmt.tprintf("Support for %s", settlement.name), 1, 2, 2, 0, 2, settlement = settlement.id)
	}
	for promise in c.promises[:c.promise_count] {
		if promise.status != .Active do continue; found := false; for o in s.items[:s.count] do if o.kind == .Active_Guarantee && o.name == promise.detail do found = true
		if !found do _ = add_obligation(c, .Active_Guarantee, promise.detail, 1, 2, 1, 1, 2)
	}
	// Remove only last season's obligation reservation, preserving situation commitments.
	c.capacities.compute.reserved = max(c.capacities.compute.reserved - s.reserved_compute, 0)
	c.capacities.manpower.reserved = max(c.capacities.manpower.reserved - s.reserved_manpower, 0)
	c.capacities.raw_materials.reserved = max(
		c.capacities.raw_materials.reserved - s.reserved_raw_materials,
		0,
	)
	s.reserved_compute = 0; s.reserved_manpower = 0; s.reserved_raw_materials = 0; s.attention_reserved = 0; s.underfunded_count = 0
	// Visible demographic demand grows with communities and settlements, not arbitrary decay.
	// Councils do not gain hours as the ledger grows; later campaigns must choose
	// which duties receive seasonal review.
	s.attention_total = max(5, 10 - c.season / 3)
	for &o in s.items[:s.count] {
		if !obligation_active(o) do continue
		compute, manpower, materials, attention, _ := obligation_substitution(c, o)
		if o.kind ==
		   .Fleet_Maintenance {growth := max(c.season - 6, 0) / 3; manpower += growth; materials += growth}
		if o.status ==
		   .Reduced {compute = (compute + 1) / 2; manpower = (manpower + 1) / 2; materials = (materials + 1) / 2; attention = (attention + 1) / 2}
		can_fund :=
			s.reserved_compute + compute <= capacity_available(c.capacities.compute) &&
			s.reserved_manpower + manpower <= capacity_available(c.capacities.manpower) &&
			s.reserved_raw_materials + materials <=
				capacity_available(c.capacities.raw_materials) &&
			s.attention_reserved + attention <= s.attention_total
		if can_fund {s.reserved_compute += compute; s.reserved_manpower += manpower; s.reserved_raw_materials += materials; s.attention_reserved += attention; continue}
		o.underfunded_seasons += 1; s.underfunded_count += 1
		// The first missed season is a warning and intervention window. Persistent
		// underfunding changes Cohesion and settlement viability from the second
		// season onward, after the player has seen which duty is binding.
		if o.underfunded_seasons > 1 {
			c.strategic.cohesion = max(c.strategic.cohesion - 1, 0)
			if o.kind == .Settlement_Support &&
			   o.settlement !=
				   0 {si := settlement_index(c, o.settlement); if si >= 0 {c.settlements[si].viability = max(c.settlements[si].viability - 2, 0); record_event(c, .Settlement_Setback, fmt.tprintf("%s deferred maintenance after fleet support remained unfunded.", c.settlements[si].name), settlement_id = o.settlement, cause_sequence = o.last_event)}}
		}
		report_due := o.underfunded_seasons == 1 || o.underfunded_seasons % 4 == 0
		if report_due &&
		   !emergency_due &&
		   !major_recorded &&
		   major_story_beat_ready(
			   c,
		   ) {record_event(c, .Need_Surfaced, fmt.tprintf("%s exceeded the capacity reserved for this season.", o.name), o.ship, o.underfunded_seasons, settlement_id = o.settlement, institution_id = o.institution, cause_sequence = o.last_event); o.last_event = c.event_sequence; mark_major_story_beat(c); major_recorded = true}
	}
	c.capacities.compute.reserved +=
		s.reserved_compute; c.capacities.manpower.reserved += s.reserved_manpower; c.capacities.raw_materials.reserved += s.reserved_raw_materials
	// This is the dated consequence of a player-invoked emergency, not an
	// unrelated director beat, so it resolves on its promised season.
	if emergency_due {c.strategic.cohesion = max(c.strategic.cohesion - s.emergency_debt, 0); record_event(c, .Political_Relationship_Changed, "The Civic Assembly reviewed capacity taken under emergency authority.", value = -s.emergency_debt, institution_id = 1); s.emergency_debt = 0}
}

contract_obligation :: proc(c: ^Campaign, index: int, choice: Contraction_Choice) -> bool {
	initialize_obligations(
		c,
	); if index < 0 || index >= c.obligations.count do return false; o := &c.obligations.items[index]; if !obligation_active(o^) do return false
	valid := false; next := o.status; detail: string
	switch choice {
	case .Suspend_Route:
		valid = o.kind == .Open_Route; next = .Suspended
		detail = fmt.tprintf("%s was suspended; its traffic record remains open.", o.name)
	case .Reduce_Guarantee:
		valid = o.kind == .Active_Guarantee; next = .Reduced
		detail = fmt.tprintf("%s was reduced by public vote.", o.name)
	case .Mothball_Capability:
		valid = o.ship != 0 || o.kind == .Fleet_Maintenance; next = .Mothballed
		detail = fmt.tprintf("%s was mothballed for later recovery.", o.name)
	case .Transfer_Authority:
		valid = o.institution != 0; next = .Transferred
		detail = fmt.tprintf("Authority for %s transferred to its named institution.", o.name)
	case .Settlement_Assumption:
		valid = o.settlement != 0; next = .Assumed_By_Settlement
		detail = fmt.tprintf("The settlement assumed %s with recorded consent.", o.name)
	}
	if !valid do return false; o.status = next; record_event(c, .Capacity_Released, detail, o.ship, o.compute + o.manpower + o.raw_materials, settlement_id = o.settlement, institution_id = o.institution, cause_sequence = o.last_event); o.last_event = c.event_sequence; return true
}

invoke_emergency_capacity :: proc(c: ^Campaign, index: int) -> bool {
	if index < 0 || index >= c.obligations.count do return false; o := &c.obligations.items[index]; if !obligation_active(o^) do return false
	o.status = .Suspended; c.obligations.emergency_debt += 2; c.obligations.emergency_due_season = max(c.obligations.emergency_due_season, c.season + 2)
	record_event(
		c,
		.Constitutional_Emergency,
		fmt.tprintf("Emergency authority suspended %s for immediate capacity.", o.name),
		o.ship,
		2,
		settlement_id = o.settlement,
		institution_id = 1,
		cause_sequence = o.last_event,
	); o.last_event = c.event_sequence; return true
}

obligation_capacity_margin :: proc(
	c: ^Campaign,
) -> (
	compute, manpower, materials, attention: i32,
) {s := &c.obligations; return capacity_available(c.capacities.compute),
	capacity_available(c.capacities.manpower),
	capacity_available(c.capacities.raw_materials),
	max(s.attention_total - s.attention_reserved, 0)}
