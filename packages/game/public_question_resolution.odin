package game

import "core:fmt"
public_form_rival_authority :: proc(c: ^Campaign, q: ^Public_Question) -> bool {
	ship :=
		q.lead.kind == .Ship ? Ship_ID(q.lead.id) : Ship_ID(0); if ship == 0 && q.source.need_index >= 0 do ship = c.needs[q.source.need_index].ship; si := ship_index(c, ship); if si < 0 || !c.ships[si].active || c.public_politics.rival_count >= MAX_RIVAL_AUTHORITIES do return false
	community :=
		c.ships[si].community; ci := community_index(c, community); population := max(c.ships[si].crew, 1); if ci >= 0 {population = min(population, max(c.communities[ci].population - 1, 0)); c.communities[ci].population -= population}
	c.ships[si].active =
		false; c.ships[si].committed = false; c.ships[si].departure = .Political_Schism
	r := &c.public_politics.rivals[c.public_politics.rival_count]; c.public_politics.rival_count += 1; r^ = {
		id         = c.public_politics.next_rival_id,
		active     = true,
		ship       = ship,
		community  = community,
		population = population,
	}; c.public_politics.next_rival_id += 1
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
		cause_sequence = q.opened_event,
	); r.origin_event = c.event_sequence; r.last_event = c.event_sequence; q.status = .Resolved; q.resolution_event = c.event_sequence; return true
}

public_reconcile_rival :: proc(
	c: ^Campaign,
	id: u32,
	term: Reconciliation_Term,
	cause: u64,
) -> bool {for &r in c.public_politics.rivals[:c.public_politics.rival_count] do if r.id == id && r.active {si := ship_index(c, r.ship); ci := community_index(c, r.community); if si < 0 || ci < 0 do return false; c.ships[si].active = true; c.ships[si].departure = .None; c.communities[ci].population += r.population; r.active = false; r.reconciliation = term; record_event(c, .Jurisdiction_Changed, fmt.tprintf("%s returned under %v.", c.ships[si].name, term), r.ship, value = r.population, community = r.community, cause_sequence = cause); r.last_event = c.event_sequence; refresh_political_constituencies(c); return true}
	return false}

need_claim_name_public :: proc(kind: Need_Kind) -> string {switch
	kind {case .Sustenance_Shortfall:
		return "a supply shortage"; case .Settlement_Demand:
		return "a settlement request"; case .Settlement_Defense:
		return "a threatened settlement"; case .Representation:
		return "a request for representation"; case .Settlement_Charter:
		return "settlement terms"; case .Jurisdiction_Dispute:
		return "disputed jurisdiction"; case .Institution_Dispute:
		return "institutional custody"; case .Ship_Repair:
		return "a ship repair"; case .Archive_Staffing:
		return "archive custody"}
	return "an open claim"}

open_public_question :: proc(c: ^Campaign, source: Public_Question_Source) -> bool {
	public_politics_initialize(c); p := &c.public_politics
	q: Public_Question; ok := false
	if source.rival_authority !=
	   0 {q, ok = public_question_from_rival(c, source.rival_authority)} else if source.precedent_case != 0 {q, ok = public_question_from_precedent(c, source.precedent_case)} else if source.front_index >= 0 {q, ok = public_question_from_front(c, source.front_index)} else if source.obligation_index >= 0 {q, ok = public_question_from_obligation(c, source.obligation_index)} else {q, ok = public_question_from_need(c, source.need_index, source.operation)}
	if !ok do return false
	q.id = Public_Question_ID(
		p.next_question_id,
	); p.next_question_id += 1; q.status = .Open; q.urgency = .Organizing; q.opened_season = c.season
	if public_question_active(
		&p.open,
	) {if p.queued.status != .None do return false; p.queued = q; return true}
	p.open =
		q; record_event(c, .Situation_Proposed, fmt.tprintf("%s %s", q.lead.name, q.request), q.lead.kind == .Ship ? Ship_ID(q.lead.id) : 0, community = q.lead.kind == .Community ? Community_ID(q.lead.id) : 0, cause_sequence = q.origin_event); p.open.opened_event = c.event_sequence; return true
}

public_response_index :: proc(q: ^Public_Question, id: u32) -> int {for r, i in q.responses[:q.response_count] do if r.id == id do return i
	return -1}

public_bind_response :: proc(c: ^Campaign, q: ^Public_Question, r: Public_Response) -> bool {
	p := &c.public_politics; if r.commitment_family == .None do return true
	if p.commitment_count >= MAX_PUBLIC_COMMITMENTS do return false
	if r.materials > fleet_materials(c) || r.cohesion > c.strategic.cohesion do return false
	if r.ship !=
	   0 {si := ship_index(c, r.ship); if si < 0 || !c.ships[si].active || c.ships[si].committed do return false; c.ships[si].committed = true}
	if r.materials > 0 && !fleet_stock_spend(c, {manufactured_goods = i64(r.materials)}, .Committed) do return false; c.strategic.cohesion -= r.cohesion
	v := &p.commitments[p.commitment_count]; p.commitment_count += 1; v^ = {
		id          = Public_Commitment_ID(p.next_commitment_id),
		question    = q.id,
		family      = r.commitment_family,
		outcome     = .Pending,
		ship        = r.ship,
		institution = r.institution,
		settlement  = r.settlement,
		community   = q.lead.kind == .Community ? Community_ID(q.lead.id) : 0,
		materials   = r.materials,
		cohesion    = r.cohesion,
		authority   = r.authority,
		disclosure  = r.disclosure,
		due_season  = r.due_season,
	}; p.next_commitment_id += 1
	record_event(
		c,
		.Capacity_Committed,
		fmt.tprintf("%s entered a binding public commitment.", r.label),
		r.ship,
		value = r.materials,
		community = v.community,
		cause_sequence = q.opened_event,
		institution_id = r.institution,
	); v.origin_event = c.event_sequence; v.last_event = c.event_sequence; q.commitment = v.id; q.status = .Bound
	return true
}

choose_public_response :: proc(c: ^Campaign, id: Public_Question_ID, response_id: u32) -> bool {
	q := &c.public_politics.open; if q.id != id || q.status != .Open do return false
	i := public_response_index(
		q,
		response_id,
	); if i < 0 do return false; r := q.responses[i]; if !r.available do return false
	q.selected_response = response_id
	if r.contested && q.actor_count > 1 {
		objector := q.actor_count - 1
		best_score := i32(-1)
		best_rank: u64
		for actor, i in q.actors[:q.actor_count] {
			if actor.kind == q.lead.kind && actor.id == q.lead.id do continue
			stance_score: i32 =
				actor.stance == .Oppose ? 20 : actor.stance == .Conditional ? 10 : 0
			score := stance_score + actor.weight
			rank := narrative_rank(
				c,
				.Public_Objection,
				u64(actor.kind) << 32 | u64(actor.id),
				u64(q.id),
			)
			if score > best_score ||
			   score == best_score &&
				   rank > best_rank {objector = i; best_score = score; best_rank = rank}
		}
		q.status = .Objection; q.objection_text = fmt.tprintf("%s asks the fleet to amend the response before it binds.", q.actors[objector].name); record_event(c, .Situation_Response, q.objection_text, cause_sequence = q.opened_event); q.objection_event = c.event_sequence; return true
	}
	if r.kind ==
	   .Refuse {record_event(c, .Situation_Decided, fmt.tprintf("The fleet refused: %s", q.request), cause_sequence = q.opened_event); q.status = .Resolved; q.resolution_event = c.event_sequence; return true}
	if q.category == .Historical_Front &&
	   r.commitment_family ==
		   .None {front := c.fronts[q.source.front_index]; values := front_family_transformations(front.kind); if i >= len(values) || !transform_front(c, front.id, values[i], q.opened_event) do return false}
	if q.category == .Continuing_Obligation &&
	   r.commitment_family ==
		   .None {if !contract_obligation(c, q.source.obligation_index, .Mothball_Capability) do return false}
	if q.category == .Precedent_Review &&
	   r.commitment_family ==
		   .None {review := i == 0 ? Precedent_Review.Affirm : Precedent_Review.Narrow; case_at := -1; for item, j in c.precedent_cases[:c.precedent_case_count] do if item.id == q.source.precedent_case {case_at = j; break}; if case_at < 0 do return false; item := c.precedent_cases[case_at]; pi := precedent_index_by_id(c, item.primary); interpretation := Precedent_Interpretation.Default; if pi >= 0 && review == .Narrow do interpretation = precedent_narrow_interpretation(c.precedents[pi].kind); if !review_precedent_case(c, q.source.precedent_case, review, 0, interpretation) do return false}
	if q.category ==
	   .Reconciliation {if !public_reconcile_rival(c, q.source.rival_authority, r.reconciliation, q.origin_event) do return false; if r.reconciliation == .Recognized_Autonomy {for &institution in c.institutions do if institution.active {institution.authority_policy = .Ship_Autonomy; break}}}
	if !public_bind_response(c, q, r) do return false
	if r.commitment_family ==
	   .None {q.status = .Resolved; record_event(c, .Situation_Decided, r.consequence, cause_sequence = q.opened_event); q.resolution_event = c.event_sequence}
	return true
}

answer_public_objection :: proc(
	c: ^Campaign,
	id: Public_Question_ID,
	answer: Public_Objection_Answer,
) -> bool {
	q := &c.public_politics.open; if q.id != id || q.status != .Objection || q.objection_answered do return false
	i := public_response_index(
		q,
		q.selected_response,
	); if i < 0 do return false; r := q.responses[i]
	switch answer {
	case .Amend:
		r.commitment_family = .Record_Or_Deadline; r.due_season = max(r.due_season, c.season + 1)
	case .Pay_Cost:
		if c.strategic.cohesion < 2 do return false; c.strategic.cohesion -= 2
	case .Invoke_Authority:
		if !has_precedent(c, .Emergency_Command) && !has_precedent(c, .Ship_Sovereignty) do return false
	case .Withdraw:
		q.status = .Withdrawn; q.objection_answered = true
		record_event(
			c,
			.Situation_Decided,
			"The sponsor withdrew the response after the recorded objection.",
			cause_sequence = q.objection_event,
		)
		q.resolution_event = c.event_sequence
		return true
	}
	q.objection_answered =
		true; record_event(c, .Situation_Decided, fmt.tprintf("The fleet answered the objection by %v.", answer), cause_sequence = q.objection_event)
	return public_bind_response(c, q, r)
}

public_commitment_index :: proc(c: ^Campaign, id: Public_Commitment_ID) -> int {for v, i in c.public_politics.commitments[:c.public_politics.commitment_count] do if v.id == id do return i
	return -1}

account_public_commitment :: proc(
	c: ^Campaign,
	id: Public_Commitment_ID,
	outcome: Public_Commitment_Outcome,
	public_record: bool,
) -> bool {
	i := public_commitment_index(
		c,
		id,
	); if i < 0 || outcome == .Pending do return false; v := &c.public_politics.commitments[i]; if v.outcome != .Pending do return false
	v.outcome = outcome; v.public_record = public_record
	if v.ship != 0 {si := ship_index(c, v.ship); if si >= 0 do c.ships[si].committed = false}
	if outcome == .Released ||
	   outcome ==
		   .Renegotiated {fleet_stock_gain(c, {manufactured_goods = i64(v.materials)}, .Recovery, v.origin_event); c.strategic.cohesion += v.cohesion}
	ci := community_index(
		c,
		v.community,
	); if ci >= 0 {if outcome == .Fulfilled {c.communities[ci].trust = min(c.communities[ci].trust + 3, 100); c.communities[ci].grievance = max(c.communities[ci].grievance - 1, 0)} else if outcome == .Breached {c.communities[ci].trust = max(c.communities[ci].trust - 2, 0); c.communities[ci].grievance = min(c.communities[ci].grievance + 1, 10)}}
	ii := institution_index(
		c,
		v.institution,
	); if ii >= 0 {delta := outcome == .Fulfilled ? i32(2) : outcome == .Breached ? i32(-3) : i32(0); c.institutions[ii].legitimacy = clamp(c.institutions[ii].legitimacy + delta, 0, 100)}
	record_event(
		c,
		outcome == .Breached ? .Promise_Changed : .Capacity_Released,
		fmt.tprintf("Public commitment %d was %v.", id, outcome),
		v.ship,
		value = i32(outcome),
		community = v.community,
		cause_sequence = v.last_event,
		institution_id = v.institution,
	); v.last_event = c.event_sequence
	q := &c.public_politics.open; if q.id == v.question {q.status = .Resolved; q.accounting_event = c.event_sequence; q.resolution_event = c.event_sequence}
	return true
}

advance_public_politics :: proc(c: ^Campaign) {
	public_politics_initialize(c); p := &c.public_politics; q := &p.open
	if q.status == .Resolved ||
	   q.status ==
		   .Withdrawn {if p.queued.status != .None {p.open = p.queued; p.queued = {}; record_event(c, .Situation_Proposed, fmt.tprintf("%s %s", p.open.lead.name, p.open.request), cause_sequence = p.open.origin_event); p.open.opened_event = c.event_sequence}; return}
	if q.status == .Open && c.season >= q.deadline && q.deadline > 0 {
		if q.urgency < .Acting_Separately do q.urgency = Public_Urgency(int(q.urgency) + 1)
		detail := "The petition entered public testimony."
		if q.urgency == .Demanding_Action do detail = fmt.tprintf("%s set a public deadline for the requested response.", q.lead.name)
		if q.urgency == .Acting_Separately do detail = fmt.tprintf("%s announced separate action after the deadline passed.", q.lead.name)
		record_event(
			c,
			.Situation_Response,
			detail,
			q.lead.kind == .Ship ? Ship_ID(q.lead.id) : 0,
			community = q.lead.kind == .Community ? Community_ID(q.lead.id) : 0,
			cause_sequence = q.opened_event,
		)
		if q.urgency == .Acting_Separately && q.category == .Jurisdiction do _ = public_form_rival_authority(c, q)
		q.deadline = c.season + 1
	}
	for &v in p.commitments[:p.commitment_count] do if v.outcome == .Pending && v.due_season > 0 && c.season > v.due_season do _ = account_public_commitment(c, v.id, .Breached, true)
}

resolve_open_public_question_autonomously :: proc(c: ^Campaign) -> bool {
	q := &c.public_politics.open
	if q.status != .Open && q.status != .Objection do return false
	if q.status == .Objection {
		return answer_public_objection(c, q.id, .Amend)
	}
	best := -1
	best_score := i32(-1_000_000)
	for response, i in q.responses[:q.response_count] {
		if !response.available do continue
		score := i32(0)
		if response.kind != .Refuse do score += 12
		if response.materials <= fleet_materials(c) do score += 6
		if response.cohesion <= c.strategic.cohesion do score += 6
		if response.authority == .Shared_Authority do score += 3
		if response.disclosure == .Open do score += 2
		score -= response.materials + response.cohesion
		if score > best_score {
			best = i
			best_score = score
		}
	}
	if best < 0 do return false
	if !choose_public_response(c, q.id, q.responses[best].id) do return false
	if q.status == .Objection do _ = answer_public_objection(c, q.id, .Amend)
	record_event(
		c,
		.Situation_Response,
		fmt.tprintf(
			"%s acted autonomously from visible authority, capacity, and standing policy.",
			q.lead.name,
		),
		cause_sequence = q.opened_event,
	)
	return true
}

surface_public_question :: proc(c: ^Campaign) -> bool {
	if public_question_active(&c.public_politics.open) do return false
	candidates: [MAX_NARRATIVE_CANDIDATES]Narrative_Candidate
	count := collect_public_question_candidates(c, candidates[:])
	if count == 0 do return false
	selected, ok := narrative_select_candidate(c, candidates[:count])
	if !ok do return false
	if !surface_public_question_candidate(c, selected) do return false
	narrative_record_selection(c, selected, candidates[:count])
	return true
}

collect_public_question_candidates :: proc(c: ^Campaign, out: []Narrative_Candidate) -> int {
	if public_question_active(&c.public_politics.open) do return 0
	count := 0
	for rival, i in c.public_politics.rivals[:c.public_politics.rival_count] do if rival.active {
		narrative_append_candidate(out, &count, {domain = .Public_Question, priority = .Mandatory, source_kind = .Public_Rival, stable_id = narrative_mix(0x7100000000000000 ~ u64(rival.id)), source_event = rival.last_event, urgency = 100, source_index = i, principal_actor = {kind = .Ship, id = u32(rival.ship)}})
	}
	for item, i in c.precedent_cases[:c.precedent_case_count] do if item.status == .Pending && item.review_season <= c.season {
		narrative_append_candidate(out, &count, {domain = .Public_Question, priority = .Mandatory, source_kind = .Precedent_Case, stable_id = narrative_mix(0x7200000000000000 ~ u64(item.id)), source_event = item.last_event, urgency = 90 + (c.season - item.review_season) * 8, deadline = item.review_season, source_index = i})
	}
	for obligation, i in c.obligations.items[:c.obligations.count] do if obligation_active(obligation) && obligation.underfunded_seasons > 0 {
		narrative_append_candidate(out, &count, {domain = .Public_Question, priority = .Urgent, source_kind = .Obligation, stable_id = narrative_mix(0x7300000000000000 ~ u64(obligation.id) ~ obligation.origin_event), source_event = obligation.last_event, urgency = 50 + obligation.underfunded_seasons * 10, source_index = i, principal_actor = {kind = .Institution, id = u32(obligation.institution)}})
	}
	for front, i in c.fronts[:c.front_count] do if !front.dormant && front.pressure > 2 {
		narrative_append_candidate(out, &count, {domain = .Public_Question, priority = .Developing, source_kind = .Front_Question, stable_id = narrative_mix(0x7400000000000000 ~ u64(front.id)), source_event = front.last_change_event, urgency = front.pressure * 8, source_index = i})
	}
	for need, i in c.needs do if need.active && !need.resolved && compact_family_for_need(need.kind) == .None {
		actor := Narrative_Actor_Key{}
		if need.community != 0 do actor = {
			kind = .Community,
			id   = u32(need.community),
		}
		if need.ship != 0 do actor = {
			kind = .Ship,
			id   = u32(need.ship),
		}
		narrative_append_candidate(out, &count, {domain = .Public_Question, priority = .Developing, source_kind = .Need, stable_id = narrative_mix(0x7500000000000000 ~ need.source_event ~ u64(need.kind) << 48 ~ u64(need.community) << 32 ~ u64(need.ship) << 16 ~ u64(need.institution)), source_event = need.source_event, urgency = 20, deadline = need.deadline, source_index = i, principal_actor = actor, semantic_tags = need.semantic_tags})
	}
	return count
}

surface_public_question_candidate :: proc(c: ^Campaign, candidate: Narrative_Candidate) -> bool {
	#partial switch candidate.source_kind {
	case .Public_Rival:
		if candidate.source_index < 0 || candidate.source_index >= c.public_politics.rival_count do return false
		return open_public_question(
			c,
			{
				need_index = -1,
				front_index = -1,
				obligation_index = -1,
				rival_authority = c.public_politics.rivals[candidate.source_index].id,
			},
		)
	case .Precedent_Case:
		if candidate.source_index < 0 || candidate.source_index >= c.precedent_case_count do return false
		return open_public_question(
			c,
			{
				need_index = -1,
				front_index = -1,
				obligation_index = -1,
				precedent_case = c.precedent_cases[candidate.source_index].id,
			},
		)
	case .Obligation:
		return open_public_question(
			c,
			{need_index = -1, front_index = -1, obligation_index = candidate.source_index},
		)
	case .Front_Question:
		return open_public_question(
			c,
			{need_index = -1, front_index = candidate.source_index, obligation_index = -1},
		)
	case .Need:
		return open_public_question(
			c,
			{need_index = candidate.source_index, front_index = -1, obligation_index = -1},
		)
	case:
	}
	return false
}

validate_public_politics :: proc(c: ^Campaign) -> bool {
	p := &c.public_politics; if !p.initialized do return p.open.status == .None && p.queued.status == .None && p.commitment_count == 0
	if p.commitment_count < 0 || p.commitment_count > MAX_PUBLIC_COMMITMENTS || p.rival_count < 0 || p.rival_count > MAX_RIVAL_AUTHORITIES || public_question_active(&p.open) && p.open.id == 0 || p.open.actor_count < 0 || p.open.actor_count > MAX_PUBLIC_QUESTION_ACTORS || p.open.response_count < 0 || p.open.response_count > MAX_PUBLIC_RESPONSES do return false
	for v, i in p.commitments[:p.commitment_count] {if v.id == 0 || v.question == 0 do return false; for prior in p.commitments[:i] do if prior.id == v.id do return false}
	for r, i in p.rivals[:p.rival_count] {if r.id == 0 || ship_index(c, r.ship) < 0 || community_index(c, r.community) < 0 || r.population < 0 do return false; for prior in p.rivals[:i] do if prior.id == r.id do return false}
	return true
}
