package game

import "core:fmt"
import "core:testing"

MAX_PUBLIC_QUESTION_ACTORS :: 3
MAX_PUBLIC_RESPONSES :: 3
MAX_PUBLIC_COMMITMENTS :: 24

Public_Question_ID :: distinct u32
Public_Commitment_ID :: distinct u32

Public_Question_Category :: enum {
	None,
	Material_Need,
	Historical_Front,
	Continuing_Obligation,
	Representation,
	Institution_Custody,
	Jurisdiction,
	Settlement_Terms,
	Standing_Doctrine,
	Precedent_Review,
	Reconciliation,
}

Public_Urgency :: enum {
	Organizing,
	Demanding_Action,
	Acting_Separately,
}
Public_Question_Status :: enum {
	None,
	Open,
	Objection,
	Bound,
	Accounting,
	Resolved,
	Withdrawn,
}
Public_Actor_Kind :: enum {
	Community,
	Institution,
	Ship,
	Settlement,
}
Public_Actor_Stance :: enum {
	Support,
	Oppose,
	Conditional,
}
Public_Response_Kind :: enum {
	Provide_Resources,
	Change_Authority,
	Promise_Record,
	Refuse,
	Withdraw,
}
Public_Commitment_Family :: enum {
	None,
	Resources,
	Ship_Or_Expedition,
	Authority_Or_Representation,
	Record_Or_Deadline,
}
Public_Commitment_Outcome :: enum {
	Pending,
	Fulfilled,
	Transformed,
	Breached,
	Renegotiated,
	Released,
}
Public_Objection_Answer :: enum {
	Amend,
	Pay_Cost,
	Invoke_Authority,
	Withdraw,
}
Reconciliation_Term :: enum {
	None,
	Restored_Jurisdiction,
	Recognized_Autonomy,
	Shared_Pending_Review,
}

Public_Question_Source :: struct {
	need_index, front_index, obligation_index: int,
	precedent_case:                            Precedent_Case_ID,
	rival_authority:                           u32,
	operation:                                 Operation_Kind,
}

Public_Actor :: struct {
	kind:         Public_Actor_Kind,
	id:           u32,
	stance:       Public_Actor_Stance,
	weight:       i32,
	name, reason: string,
	cause_event:  u64,
}

Public_Response :: struct {
	id:                   u32,
	kind:                 Public_Response_Kind,
	label, consequence:   string,
	commitment_family:    Public_Commitment_Family,
	materials, cohesion:  i32,
	ship:                 Ship_ID,
	institution:          Institution_ID,
	settlement:           Settlement_ID,
	authority:            Authority_Policy,
	disclosure:           Disclosure_Policy,
	due_season:           i32,
	reconciliation:       Reconciliation_Term,
	available, contested: bool,
}

Public_Question :: struct {
	id:                                                                              Public_Question_ID,
	status:                                                                          Public_Question_Status,
	category:                                                                        Public_Question_Category,
	urgency:                                                                         Public_Urgency,
	source:                                                                          Public_Question_Source,
	title,
	request,
	jurisdiction_reason:                                             string,
	lead:                                                                            Public_Actor,
	actors:                                                                          [MAX_PUBLIC_QUESTION_ACTORS]Public_Actor,
	actor_count:                                                                     int,
	responsible_kind:                                                                Political_Authority_Kind,
	responsible_id:                                                                  u32,
	responses:                                                                       [MAX_PUBLIC_RESPONSES]Public_Response,
	response_count:                                                                  int,
	selected_response:                                                               u32,
	deadline,
	opened_season:                                                         i32,
	origin_event,
	opened_event,
	objection_event,
	resolution_event,
	accounting_event: u64,
	objection_text:                                                                  string,
	objection_answered:                                                              bool,
	commitment:                                                                      Public_Commitment_ID,
}

Public_Commitment :: struct {
	id:                       Public_Commitment_ID,
	question:                 Public_Question_ID,
	family:                   Public_Commitment_Family,
	outcome:                  Public_Commitment_Outcome,
	ship:                     Ship_ID,
	institution:              Institution_ID,
	settlement:               Settlement_ID,
	community:                Community_ID,
	materials, cohesion:      i32,
	authority:                Authority_Policy,
	disclosure:               Disclosure_Policy,
	due_season:               i32,
	origin_event, last_event: u64,
	public_record:            bool,
}

Public_Rival_Authority :: struct {
	id:                       u32,
	active:                   bool,
	ship:                     Ship_ID,
	community:                Community_ID,
	population:               i32,
	origin_event, last_event: u64,
	reconciliation:           Reconciliation_Term,
}

Public_Politics_State :: struct {
	initialized:                                         bool,
	open, queued:                                        Public_Question,
	commitments:                                         [MAX_PUBLIC_COMMITMENTS]Public_Commitment,
	commitment_count:                                    int,
	rivals:                                              [MAX_RIVAL_AUTHORITIES]Public_Rival_Authority,
	rival_count:                                         int,
	next_question_id, next_commitment_id, next_rival_id: u32,
}

public_actor_name :: proc(c: ^Campaign, kind: Public_Actor_Kind, id: u32) -> string {
	switch kind {
	case .Community:
		if i := community_index(c, Community_ID(id)); i >= 0 do return c.communities[i].name
	case .Institution:
		if i := institution_index(c, Institution_ID(id)); i >= 0 do return c.institutions[i].name
	case .Ship:
		if i := ship_index(c, Ship_ID(id)); i >= 0 do return c.ships[i].name
	case .Settlement:
		if i := settlement_index(c, Settlement_ID(id)); i >= 0 do return c.settlements[i].name
	}
	return "Fleet delegation"
}

public_question_open :: proc(q: ^Public_Question) -> bool {return(
		q.status == .Open ||
		q.status == .Objection \
	)}
public_question_active :: proc(q: ^Public_Question) -> bool {return(
		q.status == .Open ||
		q.status == .Objection ||
		q.status == .Bound ||
		q.status == .Accounting \
	)}
public_commitment_pending :: proc(v: Public_Commitment) -> bool {return v.outcome == .Pending}

public_politics_initialize :: proc(c: ^Campaign) {
	p := &c.public_politics; if p.initialized do return
	p.initialized = true; p.next_question_id = 1; p.next_commitment_id = 1; p.next_rival_id = 1
}

public_question_category_for_need :: proc(kind: Need_Kind) -> Public_Question_Category {
	#partial switch kind {
	case .Representation:
		return .Representation
	case .Institution_Dispute, .Archive_Staffing:
		return .Institution_Custody
	case .Jurisdiction_Dispute:
		return .Jurisdiction
	case .Settlement_Demand, .Settlement_Charter:
		return .Settlement_Terms
	case .Settlement_Defense:
		return .Standing_Doctrine
	case:
		return .Material_Need
	}
}

public_add_actor :: proc(
	c: ^Campaign,
	q: ^Public_Question,
	kind: Public_Actor_Kind,
	id: u32,
	stance: Public_Actor_Stance,
	weight: i32,
	reason: string,
	cause: u64 = 0,
) {
	if id == 0 || q.actor_count >= MAX_PUBLIC_QUESTION_ACTORS do return
	for a in q.actors[:q.actor_count] do if a.kind == kind && a.id == id do return
	a := Public_Actor {
		kind        = kind,
		id          = id,
		stance      = stance,
		weight      = max(weight, 1),
		name        = public_actor_name(c, kind, id),
		reason      = reason,
		cause_event = cause,
	}
	q.actors[q.actor_count] = a; q.actor_count += 1
	if q.lead.id == 0 do q.lead = a
}

public_add_response :: proc(q: ^Public_Question, r: Public_Response) {if q.response_count >= MAX_PUBLIC_RESPONSES do return
	response := r
	response.id = u32(q.response_count + 1)
	q.responses[q.response_count] = response
	q.response_count += 1}

public_question_from_need :: proc(
	c: ^Campaign,
	index: int,
	operation: Operation_Kind = .None,
) -> (
	Public_Question,
	bool,
) {
	q: Public_Question
	if index < 0 || index >= MAX_NEEDS do return q, false
	n := c.needs[index]; if !n.active || n.resolved do return q, false
	q.category = public_question_category_for_need(n.kind)
	q.source = {
		need_index       = index,
		front_index      = -1,
		obligation_index = -1,
		operation        = operation,
	}
	q.origin_event =
		n.source_event; q.deadline = n.deadline; q.title = fmt.tprintf("%s asks the fleet to answer %s", n.community != 0 ? public_actor_name(c, .Community, u32(n.community)) : "A fleet constituency", need_claim_name_public(n.kind)); q.request = n.detail
	q.responsible_kind = .Fleet; q.responsible_id = 1; q.jurisdiction_reason = "The request commits fleet-wide capacity or changes a recorded public obligation."
	if n.community !=
	   0 {ci := community_index(c, n.community); weight := i32(1); if ci >= 0 do weight = max(c.communities[ci].population / 10000, 1); public_add_actor(c, &q, .Community, u32(n.community), .Support, weight, "Its recorded need is due before the stated season.", n.source_event)}
	if n.ship != 0 do public_add_actor(c, &q, .Ship, u32(n.ship), .Conditional, 2, "The ship would carry the operational burden.", latest_event_for_ship(c, n.ship))
	if n.opposing_institution != 0 do public_add_actor(c, &q, .Institution, u32(n.opposing_institution), .Oppose, 4, "Its recorded mandate disputes the requested authority.", n.precedent_event)
		public_add_response(
			&q,
			{
				kind = .Provide_Resources,
				label = "Fund the request",
				consequence = fmt.tprintf(
					"Commit %d materials to answer the recorded need.",
					max(n.cost, 1),
				),
				commitment_family = .Resources,
				materials = max(n.cost, 1),
				due_season = n.deadline,
				available = fleet_materials(c) >= max(n.cost, 1),
				contested = n.opposing_institution != 0,
			},
		)
	public_add_response(
		&q,
		{
			kind = .Promise_Record,
			label = "Promise review by the deadline",
			consequence = "Record a binding deadline and return the result for public accounting.",
			commitment_family = .Record_Or_Deadline,
			due_season = n.deadline,
			available = true,
			contested = n.opposing_institution != 0,
		},
	)
	public_add_response(
		&q,
		{
			kind = .Refuse,
			label = "Refuse the request",
			consequence = "Leave the need unresolved and move its constituency toward separate action.",
			available = true,
		},
	)
	return q, q.response_count >= 2
}

public_question_from_front :: proc(c: ^Campaign, index: int) -> (Public_Question, bool) {
	q: Public_Question; if index < 0 || index >= c.front_count || c.fronts[index].dormant do return q, false; front := c.fronts[index]
	q.category = .Historical_Front; q.source = {
		need_index       = -1,
		front_index      = index,
		obligation_index = -1,
	}; q.origin_event =
		front.last_change_event; q.deadline = c.season + 2; q.title = fmt.tprintf("The fleet must settle %s", front.name); q.request = front.known_next_risk; q.responsible_kind = .Fleet; q.responsible_id = 1; q.jurisdiction_reason = "The front changes fleet-wide authority, capacity, or doctrine."
	if c.community_count > 0 do public_add_actor(c, &q, .Community, u32(c.communities[0].id), .Support, max(c.communities[0].population / 10000, 1), "The front remains in its public record.", front.last_change_event)
	values := front_family_transformations(
		front.kind,
	); for value, i in values {direction := council_front_direction(front, index, i); public_add_response(&q, {kind = .Change_Authority, label = direction.name, consequence = direction.effect, commitment_family = .None, authority = council_direction_policy(direction), available = true, contested = i > 0})}
	return q, true
}

public_question_from_obligation :: proc(c: ^Campaign, index: int) -> (Public_Question, bool) {
	q: Public_Question; if index < 0 || index >= c.obligations.count do return q, false; o := c.obligations.items[index]; if !obligation_active(o) do return q, false
	q.category = .Continuing_Obligation; q.source = {
		need_index       = -1,
		front_index      = -1,
		obligation_index = index,
	}; q.origin_event =
		o.last_event; q.deadline = c.season + 1; q.title = fmt.tprintf("The fleet must account for %s", o.name); q.request = fmt.tprintf("The obligation reserves %d compute, %d manpower, %d materials, and %d attention each season.", o.compute, o.manpower, o.raw_materials, o.attention); q.responsible_kind = .Fleet; q.responsible_id = 1; q.jurisdiction_reason = "Only fleet coordination can preserve or contract a fleet-wide obligation."
	if o.institution != 0 do public_add_actor(c, &q, .Institution, u32(o.institution), .Support, 4, "Its public mandate carries the obligation.", o.last_event)
	public_add_response(
		&q,
		{
			kind = .Provide_Resources,
			label = "Maintain the obligation",
			consequence = "Preserve its reserved capacity and return it for later accounting.",
			commitment_family = .Resources,
			materials = max(o.raw_materials, 0),
			due_season = c.season + 2,
			available = fleet_materials(c) >= max(o.raw_materials, 0),
		},
	)
	public_add_response(
		&q,
		{
			kind = .Change_Authority,
			label = "Contract the obligation",
			consequence = "Release its reserved capacity and record the institutional cost.",
			available = true,
			contested = o.institution != 0,
		},
	)
	return q, true
}

public_question_from_precedent :: proc(
	c: ^Campaign,
	id: Precedent_Case_ID,
) -> (
	Public_Question,
	bool,
) {
	q: Public_Question; at := -1; for item, i in c.precedent_cases[:c.precedent_case_count] do if item.id == id && item.status == .Pending {at = i; break}; if at < 0 do return q, false; item := c.precedent_cases[at]
	q.category = .Precedent_Review; q.source = {
		need_index       = -1,
		front_index      = -1,
		obligation_index = -1,
		precedent_case   = id,
	}; q.origin_event =
		item.last_event; q.deadline = item.review_season; q.title = fmt.tprintf("Constitutional case %d requires public review", id); q.request = "The fleet must affirm, narrow, or leave the recorded rule contested."; q.responsible_kind = .Fleet; q.responsible_id = 1; q.jurisdiction_reason = "A precedent can be reviewed only through fleet-wide public authority."
	if len(c.institutions) > 0 do public_add_actor(c, &q, .Institution, u32(c.institutions[0].id), .Conditional, clamp(c.institutions[0].legitimacy / 10, 2, 10), "Its legitimacy depends on a recorded interpretation.", item.last_event)
	public_add_response(
		&q,
		{
			kind = .Change_Authority,
			label = "Affirm the precedent",
			consequence = "Keep the rule in force and close the case.",
			available = true,
		},
	)
	public_add_response(
		&q,
		{
			kind = .Change_Authority,
			label = "Narrow the precedent",
			consequence = "Limit the rule to its recorded facts.",
			available = true,
			contested = true,
		},
	)
	public_add_response(
		&q,
		{
			kind = .Promise_Record,
			label = "Leave the rule contested",
			consequence = "Preserve the dispute for a later public review.",
			commitment_family = .Record_Or_Deadline,
			due_season = c.season + 2,
			available = true,
		},
	)
	return q, true
}

public_question_from_rival :: proc(c: ^Campaign, id: u32) -> (Public_Question, bool) {
	q: Public_Question; at := -1; for rival, i in c.public_politics.rivals[:c.public_politics.rival_count] do if rival.id == id && rival.active {at = i; break}; if at < 0 do return q, false; rival := c.public_politics.rivals[at]
	q.category = .Reconciliation; q.source = {
		need_index       = -1,
		front_index      = -1,
		obligation_index = -1,
		rival_authority  = id,
	}; q.origin_event =
		rival.last_event; q.deadline = c.season + 2; q.title = fmt.tprintf("%s offers terms for return", political_ship_name(c, rival.ship)); q.request = fmt.tprintf("%d people remain under separate authority.", rival.population); q.responsible_kind = .Fleet; q.responsible_id = 1; q.jurisdiction_reason = "Return changes both ship and fleet jurisdiction."
	public_add_actor(
		c,
		&q,
		.Ship,
		u32(rival.ship),
		.Support,
		3,
		"Its separate authority asks for a durable jurisdictional term.",
		rival.last_event,
	)
	public_add_response(
		&q,
		{
			kind = .Change_Authority,
			label = "Restore prior jurisdiction",
			consequence = "Return the ship and record restored fleet jurisdiction.",
			reconciliation = .Restored_Jurisdiction,
			available = true,
		},
	)
	public_add_response(
		&q,
		{
			kind = .Change_Authority,
			label = "Recognize ship autonomy",
			consequence = "Return the ship under recognized autonomous authority.",
			authority = .Ship_Autonomy,
			reconciliation = .Recognized_Autonomy,
			available = true,
			contested = true,
		},
	)
	public_add_response(
		&q,
		{
			kind = .Promise_Record,
			label = "Share authority pending review",
			consequence = "Return the ship under shared authority with a binding review date.",
			commitment_family = .Record_Or_Deadline,
			authority = .Shared_Authority,
			due_season = c.season + 2,
			reconciliation = .Shared_Pending_Review,
			available = true,
		},
	)
	return q, true
}

