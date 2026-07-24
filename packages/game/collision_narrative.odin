package game

import "core:fmt"

MAX_NARRATIVE_FACTS :: 3
MAX_NARRATIVE_ACTORS :: 3
MAX_NARRATIVE_POSITIONS :: 2
MAX_NARRATIVE_AFFORDANCES :: MAX_SITUATION_CHOICES

Collision_ID :: distinct u64
Collision_Command_ID :: distinct u64

Narrative_Fact_Kind :: enum {
	None,
	Manifestation,
	Cause,
	Callback,
	Unknown,
}
Narrative_Actor_Kind :: enum {
	None,
	Ship,
	Community,
	Institution,
	Settlement,
}

Narrative_Fact :: struct {
	kind:  Narrative_Fact_Kind,
	text:  string,
	token: string,
	event: u64,
}

Narrative_Actor :: struct {
	kind: Narrative_Actor_Kind,
	id:   u32,
	name: string,
}

Attributed_Position :: struct {
	actor: Narrative_Actor,
	text:  string,
	token: string,
	event: u64,
}

Affordance_View :: struct {
	id:                 Collision_Command_ID,
	label:              string,
	consequence:        string,
	protects:           string,
	exposes:            string,
	cost:               string,
	status:             string,
	unavailable_reason: string,
	available:          bool,
	confidence:         i32,
	cause_event:        u64,
}

Narrative_View :: struct {
	valid:            bool,
	id:               Collision_ID,
	title:            string,
	domain:           string,
	stakes:           string,
	severity:         i32,
	deadline:         i32,
	origin_event:     u64,
	manifestation:    Narrative_Fact,
	causes:           [MAX_NARRATIVE_FACTS]Narrative_Fact,
	cause_count:      int,
	actors:           [MAX_NARRATIVE_ACTORS]Narrative_Actor,
	actor_count:      int,
	positions:        [MAX_NARRATIVE_POSITIONS]Attributed_Position,
	position_count:   int,
	affordances:      [MAX_NARRATIVE_AFFORDANCES]Affordance_View,
	affordance_count: int,
	callbacks:        [MAX_NARRATIVE_FACTS]Narrative_Fact,
	callback_count:   int,
	unknowns:         [MAX_NARRATIVE_FACTS]Narrative_Fact,
	unknown_count:    int,
}

collision_id_for_situation :: proc(s: ^Fleet_Situation) -> Collision_ID {
	if s == nil || s.kind == .None do return 0
	return Collision_ID(
		narrative_mix(u64(s.kind) << 56 ~ s.origin_event ~ u64(s.initiator) << 16 ~ u64(s.id)),
	)
}

collision_command_id :: proc(
	id: Collision_ID,
	choice: Situation_Choice,
	index: int,
) -> Collision_Command_ID {
	return Collision_Command_ID(narrative_mix(u64(id) ~ u64(choice.effect) << 32 ~ u64(index + 1)))
}

collision_domain :: proc(kind: Situation_Kind) -> string {
	switch kind {
	case .Repair_Debt:
		return "CAPACITY"
	case .Settlement:
		return "SETTLEMENT"
	case .Rescue:
		return "RESCUE"
	case .Contested_Evidence:
		return "EVIDENCE"
	case .Combat_Aftermath:
		return "AUTHORITY"
	case .Value_No_One_Left_Behind,
	     .Value_Truth_Before_Comfort,
	     .Value_Consent_To_Settle,
	     .Value_Shelter_Is_Sacred,
	     .Value_Shared_Authority,
	     .Value_Open_Archives,
	     .Value_The_Fleet_Endures,
	     .Value_Every_Home_Is_Free:
		return "AUTHORITY"
	case .None:
	}
	return "FLEET"
}

collision_actor_ship :: proc(c: ^Campaign, id: Ship_ID) -> Narrative_Actor {
	at := ship_index(c, id); if at < 0 do return {}
	return {kind = .Ship, id = u32(id), name = c.ships[at].name}
}

collision_choice_available :: proc(c: ^Campaign, choice: Situation_Choice) -> bool {
	return(
		choice.compute <= capacity_available(c.capacities.compute) &&
		choice.manpower <= capacity_available(c.capacities.manpower) &&
		choice.raw_materials <= capacity_available(c.capacities.raw_materials) \
	)
}

collision_choice_cost :: proc(choice: Situation_Choice) -> string {
	if choice.compute + choice.manpower + choice.raw_materials == 0 do return "NO CAPACITY COMMITMENT"
	result := ""
	if choice.compute > 0 do result = fmt.tprintf("COMPUTE %d", choice.compute)
	if choice.manpower > 0 do result = fmt.tprintf("%s%sCREW %d", result, result != "" ? " · " : "", choice.manpower)
	if choice.raw_materials > 0 do result = fmt.tprintf("%s%sMATERIALS %d", result, result != "" ? " · " : "", choice.raw_materials)
	return result
}

collision_choice_unavailable_reason :: proc(c: ^Campaign, choice: Situation_Choice) -> string {
	compute_short := max(choice.compute - capacity_available(c.capacities.compute), 0)
	crew_short := max(choice.manpower - capacity_available(c.capacities.manpower), 0)
	materials_short := max(
		choice.raw_materials - capacity_available(c.capacities.raw_materials),
		0,
	)
	result := ""
	if compute_short > 0 do result = fmt.tprintf("NEEDS %d MORE COMPUTE", compute_short)
	if crew_short > 0 do result = fmt.tprintf("%s%sNEEDS %d MORE CREW", result, result != "" ? " · " : "", crew_short)
	if materials_short > 0 do result = fmt.tprintf("%s%sNEEDS %d MORE MATERIALS", result, result != "" ? " · " : "", materials_short)
	return result
}

collision_choice_stakes :: proc(
	s: ^Fleet_Situation,
	choice: Situation_Choice,
) -> (
	string,
	string,
) {
	switch choice.effect {
	case .Full_Rescue:
		return "complete repair or care", "capacity for other fleet work"
	case .Bounded_Rescue:
		return "a bounded recovery", "some damage or obligation"
	case .Promise_Return:
		return "current operating capacity", "a binding later transfer"
	case .Refuse_Rescue:
		return "current capacity", "the named obligation and relationship"
	case .Found_Settlement:
		return "the founding attempt", "the founding ship's place in the fleet"
	case .Amend_Settlement:
		return "settlement and civilian mobility", "additional fleet capacity"
	case .Delay:
		return "independent review", "time and reserved analysis"
	case .Decline:
		return "the traveling fleet", "the present settlement opportunity"
	case .Publish_Evidence:
		return "the open record", "control of the disputed account"
	case .Review_Evidence:
		return "independent verification", "time and analysis capacity"
	case .Restricted_Disclosure:
		return "limited operational knowledge", "an open fleet record"
	case .Conceal_Evidence:
		return "custody of the record", "informed fleet action"
	case .Honor_Combat_Withdrawal:
		return "ship withdrawal authority", "central pursuit authority"
	case .Commend_Combat_Recovery:
		return "the recovery conduct", "no new standing rule"
	case .Expand_Combat_Authority:
		return "central operational authority", "ship autonomy"
	case .Value_Comply:
		return "the recorded value", "the competing operational claim"
	case .Value_Bounded:
		return "a bounded application", "full compliance with either claim"
	case .Value_Exception:
		return "the immediate operation", "the recorded value"
	case .Value_Depart:
		return "actor autonomy", "continued fleet unity"
	case .None:
	}
	return choice.consequence, "another fleet claim"
}

narrative_view_for_collision :: proc(c: ^Campaign, id: Collision_ID) -> Narrative_View {
	v: Narrative_View; s := &c.current_situation
	if id == 0 || id != collision_id_for_situation(s) || s.phase == .None || s.phase == .Resolved do return v
	v.valid =
		true; v.id = id; v.title = s.title; v.domain = collision_domain(s.kind); v.stakes = s.stakes; v.severity = s.dramatic_score
	v.origin_event = s.origin_event; v.deadline = c.season
	v.manifestation = {
		kind  = .Manifestation,
		text  = s.proposal,
		token = fmt.tprintf("collision:%v:manifestation", s.kind),
		event = s.proposal_event,
	}
	if s.origin_event != 0 {
		at := event_index_by_sequence(c, s.origin_event)
		if at >= 0 {e := c.events[at]; v.causes[v.cause_count] = {
				kind  = .Cause,
				text  = e.detail,
				token = fmt.tprintf("event:%d", e.sequence),
				event = e.sequence,
			}; v.cause_count += 1}
	}
	lead := collision_actor_ship(
		c,
		s.initiator,
	); if lead.kind != .None {v.actors[v.actor_count] = lead; v.actor_count += 1}
	if s.affected_community != 0 && v.actor_count < MAX_NARRATIVE_ACTORS {
		at := community_index(c, s.affected_community)
		if at >= 0 {community := c.communities[at]; v.actors[v.actor_count] = {
				kind = .Community,
				id   = u32(community.id),
				name = community.name,
			}; v.actor_count += 1}
	}
	for position in s.positions[:s.position_count] {
		actor := collision_actor_ship(c, position.ship); if actor.kind == .None do continue
		if v.actor_count <
		   MAX_NARRATIVE_ACTORS {seen := false; for a in v.actors[:v.actor_count] do if a.kind == actor.kind && a.id == actor.id do seen = true; if !seen {v.actors[v.actor_count] = actor; v.actor_count += 1}}
		if v.position_count < MAX_NARRATIVE_POSITIONS && position.reason_count > 0 {
			r := position.reasons[0]
			v.positions[v.position_count] = {
				actor = actor,
				text  = r.detail,
				token = fmt.tprintf("position:%d:%v", actor.id, position.position),
				event = r.source_event,
			}
			v.position_count += 1
		}
	}
	for choice, i in s.choices[:s.choice_count] {
		protects, exposes := collision_choice_stakes(s, choice)
		status := "REVERSIBLE"; if choice.irreversible do status = "IRREVERSIBLE"
		action := situation_precedent_action(
			s^,
			choice,
		); if action != .None do status = "PRECEDENT-SETTING"
		v.affordances[v.affordance_count] = {
			id                 = collision_command_id(id, choice, i),
			label              = choice.label,
			consequence        = choice.consequence,
			protects           = protects,
			exposes            = exposes,
			cost               = collision_choice_cost(choice),
			status             = status,
			unavailable_reason = collision_choice_unavailable_reason(c, choice),
			available          = collision_choice_available(c, choice),
			confidence         = 100,
			cause_event        = s.proposal_event,
		}
		v.affordance_count += 1
	}
	if s.origin_event != 0 {v.callbacks[0] = {
			kind  = .Callback,
			text  = v.causes[0].text,
			token = v.causes[0].token,
			event = s.origin_event,
		}; v.callback_count = 1}
	return v
}

execute_collision_command :: proc(
	c: ^Campaign,
	id: Collision_ID,
	command: Collision_Command_ID,
) -> (
	bool,
	string,
) {
	s := &c.current_situation
	if collision_id_for_situation(s) != id || s.phase == .None || s.phase == .Resolved do return false, "the collision changed; review the current state"
	for choice, i in s.choices[:s.choice_count] {
		if collision_command_id(id, choice, i) != command do continue
		if !collision_choice_available(c, choice) do return false, "fleet capacity changed; that intervention is no longer available"
		s.phase = .Decision
		if !resolve_interaction(c, i) do return false, "the collision changed during resolution"
		return true, "intervention entered the Chronicle"
	}
	return false, "the collision changed; review the available interventions"
}
