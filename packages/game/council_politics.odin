package game

import "core:fmt"

MAX_COUNCIL_POSITIONS :: 12
MAX_COUNCIL_DIRECTIONS :: 3

Council_Source_Kind :: enum {
	None,
	Front,
	Obligation,
}
Council_Phase :: enum {
	None,
	Proposal,
	Deliberation,
	Ratification,
	Enacted,
	Failed,
	Cancelled,
}
Council_Checkpoint_Outcome :: enum {
	Success,
	Advance,
	Debate,
	Stall,
}
Council_Support_Band :: enum {
	Marginal,
	Weak,
	Contested,
	Strong,
}
Council_Actor_Kind :: enum {
	Institution,
	Community,
	Ship,
}
Council_Stance :: enum {
	Oppose,
	Conditional,
	Support,
}

Council_Position :: struct {
	kind:         Council_Actor_Kind,
	id:           u32,
	stance:       Council_Stance,
	influence:    i32,
	name, reason: string,
	cause_event:  u64,
}

Council_Direction :: struct {
	name, effect:         string,
	source_kind:          Council_Source_Kind,
	source_index:         int,
	front_transformation: Front_Transformation,
	contraction:          Contraction_Choice,
	maintain:             bool,
	emergency:            bool,
}

Council_Direction_Preview :: struct {
	support_band:                            Council_Support_Band,
	success_chance, stall_chance:            i32,
	strongest_supporter, strongest_opponent: string,
	doctrine_conflict, authorized_cause:     bool,
}

Council_Enactment :: struct {
	id:                                                                         u32,
	active:                                                                     bool,
	direction:                                                                  Council_Direction,
	phase:                                                                      Council_Phase,
	momentum, setbacks, checkpoint_count:                                       i32,
	success_chance, advance_chance, debate_chance, stall_chance:                i32,
	support, opposition:                                                        i32,
	support_band:                                                               Council_Support_Band,
	positions:                                                                  [MAX_COUNCIL_POSITIONS]Council_Position,
	position_count:                                                             int,
	strongest_supporter, strongest_opponent, support_reason, opposition_reason: string,
	source_event, started_event, last_event:                                    u64,
	exception_pending:                                                          bool,
	exception_doctrine, exception_reason:                                       string,
	last_outcome:                                                               Council_Checkpoint_Outcome,
	failed_source_kind:                                                         Council_Source_Kind,
	failed_source_index:                                                        int,
	cooldown_until:                                                             i32,
}

council_front_direction :: proc(
	front: Historical_Front,
	source_index, option: int,
) -> Council_Direction {
	values := front_family_transformations(front.kind)
	t := values[clamp(option, 0, 2)]
	name := "Share responsibility"
	switch t {
	case .Shared_Ownership:
		name = "Share authority"
	case .Distributed_Cost:
		name = "Distribute the cost"
	case .Broadened_Constituency:
		name = "Broaden representation"
	case .Revised_Doctrine:
		name = "Revise fleet doctrine"
	case .Damaged_Institution:
		name = "Limit the responsible institution"
	case .Constrained_Route:
		name = "Accept a constrained route"
	case .Continuing_Obligation:
		name = "Accept a continuing obligation"
	case .Changed_Authority:
		name = "Transfer authority"
	case .None:
	}
	effect := "The fleet records a durable change in authority."
	switch t {
	case .Shared_Ownership:
		effect =
			front.kind == .Passage_Access ? "Reduce import dependence by 8 and share route ownership." : "Increase Civic Assembly legitimacy by 2 and share authority."
	case .Distributed_Cost:
		effect = "Spend 3 industry, gain 2 cohesion, and restore agricultural equipment."
	case .Broadened_Constituency:
		effect = "Increase community trust by 3 and reduce grievance by 1."
	case .Revised_Doctrine:
		effect = "Spend up to 2 knowledge, gain 3 sustenance, and improve nutrient closure."
	case .Damaged_Institution:
		effect = "Reduce Civic Assembly legitimacy by 8 and constrain its authority."
	case .Constrained_Route:
		effect = "Mark a route Strained and increase import dependence by 15."
	case .Continuing_Obligation:
		effect = "Lose 2 cohesion and preserve the obligation for later review."
	case .Changed_Authority:
		effect = "Increase Navigation Guild legitimacy by 4 and transfer allocation authority."
	case .None:
	}
	return {
		name = name,
		effect = effect,
		source_kind = .Front,
		source_index = source_index,
		front_transformation = t,
	}
}

council_obligation_directions :: proc(
	c: ^Campaign,
	index: int,
) -> (
	[MAX_COUNCIL_DIRECTIONS]Council_Direction,
	int,
) {
	r: [MAX_COUNCIL_DIRECTIONS]Council_Direction
	if index < 0 || index >= c.obligations.count do return r, 0
	o := c.obligations.items[index]; count := 0
	r[count] = {
		name         = "Maintain the commitment",
		effect       = fmt.tprintf(
			"Reserve %d compute, %d manpower, %d materials, and %d attention each season.",
			o.compute,
			o.manpower,
			o.raw_materials,
			o.attention,
		),
		source_kind  = .Obligation,
		source_index = index,
		maintain     = true,
	}; count += 1
	choice := Contraction_Choice.Mothball_Capability
	switch o.kind {case .Open_Route:
		choice = .Suspend_Route; case .Active_Guarantee:
		choice = .Reduce_Guarantee; case .Settlement_Support:
		choice = .Settlement_Assumption; case .Archive_Custody:
		choice = .Transfer_Authority; case .Fleet_Maintenance:
		choice = .Mothball_Capability}
	labels := [5]string {
		"Suspend the route",
		"Reduce the guarantee",
		"Mothball the capability",
		"Transfer authority",
		"Ask the settlement to assume it",
	}
	effects := [5]string {
		"Suspend the route while preserving its traffic record.",
		"Reduce the guarantee and its seasonal reservation.",
		"Release its capacity until the fleet restores it.",
		"Transfer the duty to its named institution.",
		"Transfer the duty to the settlement with recorded consent.",
	}
	r[count] = {
		name         = labels[int(choice)],
		effect       = fmt.tprintf(
			"Release up to %d compute, %d manpower, %d materials, and %d attention. %s",
			o.compute,
			o.manpower,
			o.raw_materials,
			o.attention,
			effects[int(choice)],
		),
		source_kind  = .Obligation,
		source_index = index,
		contraction  = choice,
	}; count += 1
	if has_precedent(c, .Emergency_Command) {r[count] = {
			name         = "Suspend under emergency authority",
			effect       = "Releases capacity now and creates constitutional debt and a later review.",
			source_kind  = .Obligation,
			source_index = index,
			contraction  = choice,
			emergency    = true,
		}; count += 1}
	return r, count
}

council_direction_options :: proc(
	c: ^Campaign,
	kind: Council_Source_Kind,
	index: int,
) -> (
	[MAX_COUNCIL_DIRECTIONS]Council_Direction,
	int,
) {
	r: [MAX_COUNCIL_DIRECTIONS]Council_Direction
	switch kind {
	case .Front:
		if index < 0 || index >= c.front_count || c.fronts[index].dormant do return r, 0
		for i in 0 ..< 3 do r[i] = council_front_direction(c.fronts[index], index, i)
		return r, 3
	case .Obligation:
		return council_obligation_directions(c, index)
	case .None:
		return r, 0
	}
	return r, 0
}

council_direction_policy :: proc(d: Council_Direction) -> Authority_Policy {
	if d.maintain do return .Shared_Authority
	switch d.front_transformation {
	case .Shared_Ownership, .Broadened_Constituency, .Distributed_Cost, .Continuing_Obligation:
		return .Shared_Authority
	case .Changed_Authority, .Revised_Doctrine, .Constrained_Route:
		return .Ship_Autonomy
	case .Damaged_Institution:
		return .Central_Command
	case .None:
	}
	switch d.contraction {case .Transfer_Authority, .Settlement_Assumption:
		return .Shared_Authority; case .Suspend_Route, .Reduce_Guarantee, .Mothball_Capability:
		return .Central_Command}
	return .Shared_Authority
}

council_direction_preview :: proc(
	c: ^Campaign,
	d: Council_Direction,
) -> Council_Direction_Preview {
	e := Council_Enactment {
		direction = d,
		phase     = .Proposal,
	}
	council_refresh_support(c, &e)
	desired := council_direction_policy(d); doctrine := council_fleet_doctrine(c)
	return {
		support_band = e.support_band,
		success_chance = e.success_chance,
		stall_chance = e.stall_chance,
		strongest_supporter = e.strongest_supporter,
		strongest_opponent = e.strongest_opponent,
		doctrine_conflict = desired != doctrine,
		authorized_cause = council_has_deviation_cause(c, &e),
	}
}

council_fleet_doctrine :: proc(c: ^Campaign) -> Authority_Policy {
	if has_precedent(c, .Emergency_Command) do return .Central_Command
	if has_precedent(c, .Ship_Sovereignty) || has_precedent(c, .Right_Of_Departure) do return .Ship_Autonomy
	return .Shared_Authority
}

council_authority_name :: proc(policy: Authority_Policy) -> string {
	switch policy {case .Shared_Authority:
		return "shared authority"; case .Ship_Autonomy:
		return "ship autonomy"; case .Central_Command:
		return "central command"}
	return "established authority"
}

council_add_position :: proc(e: ^Council_Enactment, p: Council_Position) {
	if e.position_count >= MAX_COUNCIL_POSITIONS do return
	strongest_support := i32(-1)
	strongest_opposition := i32(-1)
	for prior in e.positions[:e.position_count] {
		if prior.stance == .Support do strongest_support = max(strongest_support, prior.influence)
		if prior.stance == .Oppose do strongest_opposition = max(strongest_opposition, prior.influence)
	}
	e.positions[e.position_count] = p; e.position_count += 1
	if p.stance ==
	   .Support {e.support += p.influence; if p.influence > strongest_support {e.strongest_supporter = p.name; e.support_reason = p.reason}}
	if p.stance ==
	   .Oppose {e.opposition += p.influence; if p.influence > strongest_opposition {e.strongest_opponent = p.name; e.opposition_reason = p.reason}}
}

council_refresh_support :: proc(c: ^Campaign, e: ^Council_Enactment) {
	e.position_count = 0; e.support = 0; e.opposition = 0; e.strongest_supporter = ""; e.strongest_opponent = ""; e.support_reason = ""; e.opposition_reason = ""
	desired := council_direction_policy(e.direction)
	for institution in c.institutions {
		if !institution.active do continue
		influence := clamp(
			institution.legitimacy / 10,
			2,
			10,
		); stance := Council_Stance.Conditional; reason := "Its mandate does not settle this direction."
		if institution.authority_policy ==
		   desired {stance = .Support; reason = fmt.tprintf("Its mandate for %s supports this direction.", council_authority_name(institution.authority_policy))} else {stance = .Oppose; reason = fmt.tprintf("Its mandate for %s opposes this transfer of authority.", council_authority_name(institution.authority_policy))}
		council_add_position(
			e,
			{
				kind = .Institution,
				id = u32(institution.id),
				stance = stance,
				influence = influence,
				name = institution.name,
				reason = reason,
			},
		)
	}
	for community in c.communities[:c.community_count] {
		influence := clamp(community.population / 10000, 1, 5); supporting := community.trust >= 55
		if desired == .Shared_Authority && community.grievance >= 2 do supporting = true
		stance :=
			Council_Stance.Support; if !supporting do stance = .Oppose; reason := supporting ? "Its recorded trust and petitions support the direction." : "Its unresolved grievances reduce support."
		council_add_position(
			e,
			{
				kind = .Community,
				id = u32(community.id),
				stance = stance,
				influence = influence,
				name = community.name,
				reason = reason,
				cause_event = community.last_memory_event,
			},
		)
	}
	for ship in c.ships[:c.ship_count] {
		if !ship.active do continue
		influence := i32(1 + min(ship.experience / 3, 2)); supporting := false
		if e.direction.source_kind == .Front && e.direction.source_index < c.front_count do supporting = front_role_solution(c.fronts[e.direction.source_index].kind, ship.role) == e.direction.front_transformation
		if ship.promises_broken > ship.promises_upheld && desired == .Central_Command do supporting = false
		stance :=
			Council_Stance.Support; if !supporting do stance = .Conditional; reason := supporting ? "Its operational role supports the proposed settlement." : "Its record does not establish a firm position."
		council_add_position(
			e,
			{
				kind = .Ship,
				id = u32(ship.id),
				stance = stance,
				influence = influence,
				name = ship.name,
				reason = reason,
				cause_event = latest_event_for_ship(c, ship.id),
			},
		)
	}
	delta := e.support - e.opposition
	e.support_band =
		delta >= 20 ? .Strong : delta >= 5 ? .Contested : delta >= -10 ? .Weak : .Marginal
	e.success_chance = clamp(30 + delta / 2 + e.momentum, 5, 75)
	e.stall_chance = clamp(18 - delta / 3 - e.momentum / 2 + e.setbacks * 5, 5, 65)
	remaining := max(
		100 - e.success_chance - e.stall_chance,
		0,
	); e.advance_chance = remaining / 2; e.debate_chance = remaining - e.advance_chance
}

council_source_event :: proc(c: ^Campaign, d: Council_Direction) -> u64 {
	if d.source_kind == .Front && d.source_index >= 0 && d.source_index < c.front_count do return c.fronts[d.source_index].last_change_event
	if d.source_kind == .Obligation && d.source_index >= 0 && d.source_index < c.obligations.count do return c.obligations.items[d.source_index].last_event
	return 0
}

surface_council_front :: proc(c: ^Campaign, kind: Front_Kind, source_event: u64) -> int {
	for &front, i in c.fronts[:c.front_count] do if front.kind == kind {
		front.pressure = min(front.pressure + 2, 10); front.last_change_event = source_event; front.last_change_season = c.season
		if front.originating_event_count < MAX_EVENT_CAUSES {front.originating_events[front.originating_event_count] = source_event; front.originating_event_count += 1}
		return i
	}
	if c.future_front_count == 0 do seed_front_families(c)
	for &proposal, i in c.future_fronts[:c.future_front_count] do if proposal.kind == kind {proposal.source_event = source_event; if activate_front_proposal(c, i) do return c.front_count - 1}
	return -1
}

choose_political_direction :: proc(
	c: ^Campaign,
	kind: Council_Source_Kind,
	index, option: int,
) -> bool {
	e := &c.council
	if e.active || e.exception_pending || c.season < e.cooldown_until && kind == e.failed_source_kind && index == e.failed_source_index do return false
	options, count := council_direction_options(
		c,
		kind,
		index,
	); if option < 0 || option >= count do return false
	e^ = {
		id           = e.id + 1,
		active       = true,
		direction    = options[option],
		phase        = .Proposal,
		source_event = council_source_event(c, options[option]),
	}
	council_refresh_support(c, e)
	record_event(
		c,
		.Situation_Proposed,
		fmt.tprintf("The council began considering %s.", e.direction.name),
		value = i32(kind),
		cause_sequence = e.source_event,
	); e.started_event = c.event_sequence; e.last_event = c.event_sequence
	campaign_clock_initialize(c)
	_ = campaign_schedule_work(
		c,
		.Council,
		u64(e.id),
		campaign_time_add(c.clock.now, 30 * CAMPAIGN_DAY_SECONDS),
		20,
	)
	return true
}

council_mix :: proc(x: u64) -> u64 {v := x; v ~= v >> 30; v *= 0xbf58476d1ce4e5b9; v ~= v >> 27
	v *= 0x94d049bb133111eb
	return v ~ (v >> 31)}
council_roll :: proc(c: ^Campaign, e: ^Council_Enactment) -> i32 {return i32(
		council_mix(
			c.initial_seed ~
			u64(e.id) * 0x9e3779b97f4a7c15 ~
			u64(e.phase) << 32 ~
			u64(e.checkpoint_count),
		) %
		100,
	)}

council_has_deviation_cause :: proc(c: ^Campaign, e: ^Council_Enactment) -> bool {
	if e.direction.source_kind == .Front && e.direction.source_index < c.front_count do return c.fronts[e.direction.source_index].pressure >= 7
	if e.direction.source_kind == .Obligation && e.direction.source_index < c.obligations.count do return c.obligations.items[e.direction.source_index].underfunded_seasons >= 2
	return false
}

council_apply_direction :: proc(c: ^Campaign, e: ^Council_Enactment) -> bool {
	ok := false
	if e.direction.source_kind == .Front &&
	   e.direction.source_index >= 0 &&
	   e.direction.source_index <
		   c.front_count {front := c.fronts[e.direction.source_index]; ok = transform_front(c, front.id, e.direction.front_transformation, e.last_event)}
	if e.direction.source_kind == .Obligation &&
	   e.direction.source_index >= 0 &&
	   e.direction.source_index < c.obligations.count {
		if e.direction.maintain {o := &c.obligations.items[e.direction.source_index]; o.underfunded_seasons = max(o.underfunded_seasons - 1, 0); record_event(c, .Capacity_Committed, fmt.tprintf("The council maintained %s.", o.name), cause_sequence = e.last_event); ok = true} else {ok = contract_obligation(c, e.direction.source_index, e.direction.contraction); if ok && e.direction.emergency {c.obligations.emergency_debt += 2; c.obligations.emergency_due_season = max(c.obligations.emergency_due_season, c.season + 2); record_event(c, .Constitutional_Emergency, fmt.tprintf("Emergency authority suspended %s pending review.", e.direction.name), value = 2, cause_sequence = e.last_event)}}
	}
	if ok {for p in e.positions[:e.position_count] {if p.kind == .Institution {at := institution_index(c, Institution_ID(p.id)); if at >= 0 {change := i32(p.stance == .Support ? 2 : p.stance == .Oppose ? -2 : 0); c.institutions[at].legitimacy = clamp(c.institutions[at].legitimacy + change, 0, 100)}}}; record_event(c, .Situation_Complied, fmt.tprintf("The fleet enacted %s.", e.direction.name), value = i32(e.direction.source_kind), cause_sequence = e.last_event); e.last_event = c.event_sequence}
	return ok
}

resolve_council_checkpoint :: proc(c: ^Campaign, outcome: Council_Checkpoint_Outcome) {
	e := &c.council; if !e.active || e.exception_pending do return
	e.last_outcome = outcome
	switch outcome {
	case .Success:
		if e.phase ==
		   .Ratification {if council_apply_direction(c, e) {e.phase = .Enacted; e.active = false}} else {e.phase = e.phase == .Proposal ? .Deliberation : .Ratification; record_event(c, .Situation_Response, fmt.tprintf("%s advanced to %v.", e.direction.name, e.phase), value = i32(e.phase), cause_sequence = e.last_event); e.last_event = c.event_sequence}
	case .Advance:
		e.momentum = min(e.momentum + 10, 30); record_event(
			c,
			.Situation_Response,
			fmt.tprintf("Support advanced for %s.", e.direction.name),
			value = e.momentum,
			cause_sequence = e.last_event,
		)
		e.last_event = c.event_sequence
	case .Debate:
		conflict := council_direction_policy(e.direction) != council_fleet_doctrine(c)
		if conflict &&
		   !council_has_deviation_cause(
				   c,
				   e,
			   ) {e.exception_pending = true; e.exception_doctrine = council_authority_name(council_fleet_doctrine(c)); e.exception_reason = "The proposed response departs from fleet doctrine without a recorded cause."; return}
		e.momentum = max(
			e.momentum - 2,
			-20,
		); debate_detail := fmt.tprintf("The council debated %s under its recorded doctrine.", e.direction.name)
		if conflict {
			if e.direction.source_kind == .Front &&
			   e.direction.source_index >= 0 &&
			   e.direction.source_index <
				   c.front_count {front := c.fronts[e.direction.source_index]; debate_detail = fmt.tprintf("Authorized deviation: %s pressure %d.", front.name, front.pressure)} else if e.direction.source_kind == .Obligation && e.direction.source_index >= 0 && e.direction.source_index < c.obligations.count {obligation := c.obligations.items[e.direction.source_index]; debate_detail = fmt.tprintf("Authorized deviation: %s underfunded for %d seasons.", obligation.name, obligation.underfunded_seasons)}
		}
		record_event(
			c,
			.Situation_Response,
			debate_detail,
			value = e.momentum,
			cause_sequence = e.source_event,
		); e.last_event = c.event_sequence
	case .Stall:
		e.setbacks += 1; e.momentum = max(e.momentum - 10, -30); record_event(
			c,
			.Situation_Response,
			fmt.tprintf("%s stalled with setback %d of 3.", e.direction.name, e.setbacks),
			value = e.setbacks,
			cause_sequence = e.last_event,
		)
		e.last_event = c.event_sequence
		if e.setbacks >=
		   3 {e.phase = .Failed; e.active = false; e.failed_source_kind = e.direction.source_kind; e.failed_source_index = e.direction.source_index; e.cooldown_until = c.season + 2; if e.direction.source_kind == .Front && e.direction.source_index < c.front_count do c.fronts[e.direction.source_index].pressure = min(c.fronts[e.direction.source_index].pressure + 2, 10); record_event(c, .Situation_Decided, fmt.tprintf("The motion to %s failed after three setbacks.", e.direction.name), value = 3, cause_sequence = e.last_event); e.last_event = c.event_sequence}
	}
}

advance_council_enactment :: proc(c: ^Campaign) {
	e := &c.council; if !e.active || e.exception_pending do return
	council_refresh_support(c, e); roll := council_roll(c, e); e.checkpoint_count += 1
	outcome := Council_Checkpoint_Outcome.Stall
	if roll <
	   e.success_chance {outcome = .Success} else if roll < e.success_chance + e.advance_chance {outcome = .Advance} else if roll < e.success_chance + e.advance_chance + e.debate_chance {outcome = .Debate}
	resolve_council_checkpoint(c, outcome)
}

resolve_political_exception :: proc(c: ^Campaign, choice: int) -> bool {
	e := &c.council; if !e.active || !e.exception_pending do return false
	switch choice {
	case 0:
		e.phase = .Cancelled; e.active = false; e.exception_pending = false
		campaign_cancel_work(c, .Council, u64(e.id))
		record_event(c, .Situation_Decided, fmt.tprintf("The council withdrew %s to preserve doctrine.", e.direction.name), cause_sequence = e.last_event)
	case 1:
		if c.strategic.cohesion < 2 do return false; c.strategic.cohesion -= 2; e.setbacks += 1
		e.momentum -= 5
		e.exception_pending = false
		_ = campaign_schedule_work(c, .Council, u64(e.id), campaign_time_add(c.clock.now, 30 * CAMPAIGN_DAY_SECONDS), 20)
		record_event(c, .Situation_Decided, fmt.tprintf("The council retained %s despite its doctrinal conflict.", e.direction.name), value = -2, cause_sequence = e.last_event)
	case 2:
		if !has_precedent(c, .Emergency_Command) do return false; e.exception_pending = false
		e.momentum += 15
		c.obligations.emergency_debt += 2
		c.obligations.emergency_due_season = max(c.obligations.emergency_due_season, c.season + 2)
		_ = campaign_schedule_work(c, .Council, u64(e.id), campaign_time_add(c.clock.now, 30 * CAMPAIGN_DAY_SECONDS), 20)
		record_event(c, .Constitutional_Emergency, fmt.tprintf("Emergency authority carried %s through the doctrinal dispute.", e.direction.name), value = 2, cause_sequence = e.last_event)
	case:
		return false
	}
	e.last_event = c.event_sequence
	campaign_clear_attention_source(c, .Council, u64(e.id))
	return true
}

cancel_political_direction :: proc(c: ^Campaign) -> bool {
	e := &c.council; if !e.active do return false
	e.active =
		false; e.exception_pending = false; e.phase = .Cancelled; e.failed_source_kind = e.direction.source_kind; e.failed_source_index = e.direction.source_index; e.cooldown_until = c.season + 1
	campaign_cancel_work(c, .Council, u64(e.id))
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf("The sponsor withdrew %s.", e.direction.name),
		cause_sequence = e.last_event,
	); e.last_event = c.event_sequence; c.strategic.cohesion = max(c.strategic.cohesion - 1, 0); return true
}
