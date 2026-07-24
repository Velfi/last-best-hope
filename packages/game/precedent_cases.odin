package game

import "core:fmt"
precedent_application :: proc(
	c: ^Campaign,
	ctx: Precedent_Context,
	action: Precedent_Action,
) -> Precedent_Application {
	r: Precedent_Application; r.source_decision = ctx.source_decision; r.secondary = ctx.secondary_precedent
	best := -1
	if preferred := precedent_index_by_id(c, ctx.primary_precedent); preferred >= 0 {
		p := c.precedents[preferred]
		if p.status != .Superseded && precedent_scope_has(p.scope, ctx.domain) do best = preferred
	}
	for p, i in c.precedents[:c.precedent_count] {
		if best >= 0 && ctx.primary_precedent != 0 do break
		if p.status == .Superseded || !precedent_scope_has(p.scope, ctx.domain) do continue
		specificity := i32(
			0,
		); if ctx.community != 0 && p.beneficiary == ctx.community do specificity += 2; if ctx.institution != 0 && p.sponsor_institution == ctx.institution do specificity += 1
		best_specificity := i32(
			-1,
		); if best >= 0 {bp := c.precedents[best]; best_specificity = 0; if ctx.community != 0 && bp.beneficiary == ctx.community do best_specificity += 2; if ctx.institution != 0 && bp.sponsor_institution == ctx.institution do best_specificity += 1}
		if best < 0 || specificity > best_specificity || specificity == best_specificity && (p.season > c.precedents[best].season || p.season == c.precedents[best].season && u32(p.id) > u32(c.precedents[best].id)) do best = i
	}
	if best < 0 {r.classification = .None; r.reason = "No recorded rule applies."; return r}
	p :=
		c.precedents[best]; r.applicable = true; r.precedent = p.id; r.status = p.status; r.interpretation = p.interpretation; r.precedent_event = p.event_sequence
	f := ctx.facts
	if !f.fulfills_default && !f.limits_duty && !f.invokes_emergency && !f.rejects_default {
		#partial switch action {case .Comply:
			f.fulfills_default = true; case .Bounded:
			f.fulfills_default = true; f.limits_duty = true
			f.residual_obligation = true; case .Exception:
			f.invokes_emergency = true; case .Depart:
			f.rejects_default = true; case:}
	}
	if f.rejects_default {r.classification = .Departure; r.reason = "The action rejects the recorded default without exception authority."; r.creates_or_advances_case = true; r.known_consequence = "The rule becomes contested and constitutional review follows."} else if f.invokes_emergency {authority := active_precedent_id(c, .Emergency_Command); authority_at := precedent_index_by_id(c, authority); authority_valid := authority_at >= 0 && c.precedents[authority_at].event_sequence == ctx.cited_authority_event; r.classification = .Exception; r.reason = "The action invokes temporary authority to depart from the recorded default."; r.requires_authority = !authority_valid; r.creates_or_advances_case = true; r.known_consequence = r.requires_authority ? "No active emergency law supports this exception; review will test both action and authority." : "Active emergency authority supports the exception pending review."} else if f.fulfills_default && f.limits_duty && f.residual_obligation {r.classification = .Bounded_Compliance; r.reason = "The action meets a bounded duty and records what remains owed."; r.known_consequence = "A dated obligation survives this decision."} else if f.fulfills_default {r.classification = .Complies; r.reason = "The material action follows the recorded rule."; r.known_consequence = f.material_commitment > 0 ? "Capacity remains committed after the decision." : "The rule is applied without a continuing capacity commitment."} else {r.classification = .Disputed; r.reason = "The facts do not establish compliance, bounded duty, or valid departure."; r.creates_or_advances_case = true; r.known_consequence = "Constitutional review follows because the action's treatment of the rule is unresolved."}
	r.review_follows = r.creates_or_advances_case
	if p.status == .Contested &&
	   r.secondary ==
		   0 {for alternative in c.precedents[:c.precedent_count] do if alternative.id != p.id && alternative.status != .Superseded && precedent_scope_has(alternative.scope, ctx.domain) {r.secondary = alternative.id; break}}
	if p.status == .Contested &&
	   action == .None {r.classification = .Disputed; r.creates_or_advances_case = true}
	return r
}

precedent_case_index :: proc(c: ^Campaign, primary, secondary: Precedent_ID) -> int {
	for v, i in c.precedent_cases[:c.precedent_case_count] do if v.status == .Pending && (v.primary == primary && v.secondary == secondary || v.primary == secondary && v.secondary == primary) do return i
	return -1
}

precedent_case_slot :: proc(c: ^Campaign) -> int {
	if c.precedent_case_count < MAX_PRECEDENT_CASES do return c.precedent_case_count
	oldest := -1
	for case_record, i in c.precedent_cases[:c.precedent_case_count] {
		if case_record.status == .Pending do continue
		if oldest < 0 || case_record.last_event < c.precedent_cases[oldest].last_event do oldest = i
	}
	return oldest
}

record_precedent_application :: proc(
	c: ^Campaign,
	ctx: Precedent_Context,
	action: Precedent_Action,
) -> (
	Precedent_Application,
	bool,
) {
	r := precedent_application(
		c,
		ctx,
		action,
	); if !r.applicable || ctx.source_decision == 0 || event_index_by_sequence(c, ctx.source_decision) < 0 do return r, false
	if r.creates_or_advances_case && precedent_case_index(c, r.precedent, r.secondary) < 0 && precedent_case_slot(c) < 0 do return r, false
	kind :=
		Event_Kind.Precedent_Applied; if r.creates_or_advances_case do kind = .Precedent_Contradicted
	detail := fmt.tprintf("%s E%03d.", r.reason, r.precedent_event)
	record_event(
		c,
		kind,
		detail,
		ctx.ship,
		value = i32(r.classification),
		community = ctx.community,
		cause_sequence = ctx.source_decision,
		institution_id = ctx.institution,
		precedent_event = r.precedent_event,
	)
	application_event := c.event_sequence
	if r.creates_or_advances_case {
		pi := precedent_index_by_id(
			c,
			r.precedent,
		); if pi >= 0 do c.precedents[pi].status = .Contested
		ci := precedent_case_index(c, r.precedent, r.secondary)
		if ci < 0 {
			if c.next_precedent_case_id == 0 do c.next_precedent_case_id = 1
			ci = precedent_case_slot(c); if ci < 0 do return r, false
			if ci == c.precedent_case_count do c.precedent_case_count += 1
			c.precedent_cases[ci] = {
				id                      = Precedent_Case_ID(c.next_precedent_case_id),
				primary                 = r.precedent,
				secondary               = r.secondary,
				status                  = .Pending,
				source_decision         = ctx.source_decision,
				contradiction_event     = application_event,
				cited_authority_event   = ctx.cited_authority_event,
				initiator_ship          = ctx.ship,
				affected_community      = ctx.community,
				responsible_institution = ctx.institution,
				review_season           = c.season + 1,
				last_event              = application_event,
			}; c.next_precedent_case_id += 1
		} else do c.precedent_cases[ci].last_event = application_event
	}
	return r, true
}

precedent_review_due :: proc(c: ^Campaign) -> bool {for case_record in c.precedent_cases[:c.precedent_case_count] do if case_record.status == .Pending && case_record.review_season <= c.season do return true
	return false}

review_precedent_case :: proc(
	c: ^Campaign,
	id: Precedent_Case_ID,
	resolution: Precedent_Review,
	replacement: Precedent_ID = 0,
	narrowed: Precedent_Interpretation = .Default,
) -> bool {
	ci := -1; for v, i in c.precedent_cases[:c.precedent_case_count] do if v.id == id && v.status == .Pending {ci = i; break}; if ci < 0 do return false
	case_record := &c.precedent_cases[ci]; pi := precedent_index_by_id(c, case_record.primary); if pi < 0 do return false
	p := &c.precedents[pi]
	switch resolution {
	case .Affirm:
		case_record.status = .Affirmed; p.status = .Active
	case .Narrow:
		if narrowed == .Default do return false; case_record.status = .Narrowed; p.status = .Active
		p.interpretation = narrowed
	case .Replace:
		ri := precedent_index_by_id(c, replacement); if ri < 0 || replacement == p.id do return false
		case_record.status = .Replaced
		p.status = .Superseded
		p.superseded_by = replacement
	case .Leave_Contested:
		case_record.status = .Contested; p.status = .Contested
	}
	record_event(
		c,
		.Precedent_Reviewed,
		fmt.tprintf("The council recorded %v for precedent E%03d.", resolution, p.event_sequence),
		value = i32(resolution),
		community = case_record.affected_community,
		cause_sequence = case_record.last_event,
		institution_id = case_record.responsible_institution,
		precedent_event = p.event_sequence,
	)
	case_record.last_event = c.event_sequence
	return true
}

precedent_narrow_interpretation :: proc(kind: Precedent_Kind) -> Precedent_Interpretation {
	#partial switch kind {case .No_One_Left_Behind:
		return .Attempt_Unless_Fleet_Collapse_Risk; case .Accountable_Disclosure:
		return .Public_Finding_Protected_Method; case .Consent_Of_The_Settled:
		return .Voluntary_Opt_In; case .Right_Of_Refuge:
		return .Admission_Up_To_Habitat_Floor; case .Shared_Authority:
		return .Institutional_Delegation_With_Review; case .Open_Archives:
		return .Recognized_Custodian_Copies; case .Continuity_Of_The_Fleet:
		return .Compact_Allows_Distributed_Fleet; case .Founding_Independence:
		return .Timed_Transition_With_Review; case:
		return .Default}
}

value_index :: proc(c: ^Campaign, kind: Value_Kind) -> int {for v, i in c.values do if v.kind == kind do return i
	return -1}

derived_value_status :: proc(v: Civilization_Value) -> Value_Status {
	if v.renounced_event != 0 do return .Renounced
	if v.contradictions > 0 do return .Compromised
	if v.tests <= 0 do return .Claimed
	if v.enacted_precedent != 0 do return .Embodied
	return .Tested
}

record_value_test :: proc(
	c: ^Campaign,
	kind: Value_Kind,
	consistent: bool,
	source: u64,
	precedent: Precedent_ID = 0,
) -> bool {
	i := value_index(
		c,
		kind,
	); if i < 0 || source == 0 || event_index_by_sequence(c, source) < 0 do return false
	v := &c.values[i]; v.tests += 1; v.last_test_event = source
	if consistent {v.consistent_tests += 1; if precedent != 0 do v.enacted_precedent = precedent} else do v.contradictions += 1
	v.status = derived_value_status(v^)
	record_event(
		c,
		.Value_Tested,
		consistent ? "A claimed value was followed in a material decision." : "A material decision departed from a claimed value.",
		value = i32(kind),
		cause_sequence = source,
	)
	return true
}

renounce_value :: proc(c: ^Campaign, kind: Value_Kind, source: u64) -> bool {
	i := value_index(
		c,
		kind,
	); if i < 0 || source == 0 || event_index_by_sequence(c, source) < 0 do return false
	v := &c.values[i]; v.renounced_event = source; v.last_test_event = source; v.status = derived_value_status(v^)
	record_event(
		c,
		.Value_Tested,
		"The civilization explicitly renounced a claimed value while preserving its prior record.",
		value = i32(kind),
		cause_sequence = source,
	)
	return true
}

value_name :: proc(kind: Value_Kind) -> string {
	switch kind {case .No_One_Left_Behind:
		return "No One Left Behind"; case .Truth_Before_Comfort:
		return "Truth Before Comfort"; case .Consent_To_Settle:
		return "Consent to Settle"; case .Shelter_Is_Sacred:
		return "Shelter Is Sacred"; case .Shared_Authority:
		return "Shared Authority"; case .Open_Archives:
		return "Open Archives"; case .The_Fleet_Endures:
		return "The Fleet Endures"; case .Every_Home_Is_Free:
		return "Every Home Is Free"}
	return "Value"
}

value_claim :: proc(kind: Value_Kind) -> string {
	switch kind {case .No_One_Left_Behind:
		return "Distress calls create a public expectation of rescue."; case .Truth_Before_Comfort:
		return "Leaders are expected to disclose dangerous knowledge."; case .Consent_To_Settle:
		return(
			"No community should be planted without meaningful consent." \
		); case .Shelter_Is_Sacred:
		return "Refuge is owed even when it is costly."; case .Shared_Authority:
		return "Communities expect a voice in fleet command."; case .Open_Archives:
		return "Knowledge belongs to the whole diaspora."; case .The_Fleet_Endures:
		return "Fragmentation is treated as an existential failure."; case .Every_Home_Is_Free:
		return "Settlements must become sovereign rather than possessions."}
	return ""
}

value_primary_precedent :: proc(kind: Value_Kind) -> Precedent_Kind {
	switch kind {case .No_One_Left_Behind:
		return .No_One_Left_Behind; case .Truth_Before_Comfort:
		return .Accountable_Disclosure; case .Consent_To_Settle:
		return .Consent_Of_The_Settled; case .Shelter_Is_Sacred:
		return .Right_Of_Refuge; case .Shared_Authority:
		return .Shared_Authority; case .Open_Archives:
		return .Open_Archives; case .The_Fleet_Endures:
		return .Continuity_Of_The_Fleet; case .Every_Home_Is_Free:
		return .Founding_Independence}
	return .Shared_Authority
}

value_pair_index :: proc(a, b: Value_Kind) -> int {
	lo, hi := int(a), int(b); if lo > hi do lo, hi = hi, lo
	if lo == hi || lo < 0 || hi >= 8 do return -1
	return lo * (15 - lo) / 2 + (hi - lo - 1)
}

value_situation_kind :: proc(kind: Value_Kind) -> Situation_Kind {return Situation_Kind(
		int(Situation_Kind.Value_No_One_Left_Behind) + int(kind),
	)}

make_value_hard_case :: proc(c: ^Campaign, slot: int) -> (Fleet_Situation, bool) {
	if slot < 0 || slot >= len(c.values) do return {}, false
	v := c.values[slot]; if v.tests >= 2 do return {}, false
	d :=
		VALUE_HARD_CASES[int(v.kind)]; ship := Ship_ID(0); for candidate in c.ships[:c.ship_count] do if candidate.active {ship = candidate.id; break}; if ship == 0 do return {}, false
	score := i32(20); if v.tests == 0 do score += 5
	s := Fleet_Situation {
		id                 = c.next_situation_id + 1,
		kind               = value_situation_kind(v.kind),
		phase              = .Proposal,
		initiator          = ship,
		affected_community = c.ships[ship_index(c, ship)].community,
		origin_event       = v.last_test_event != 0 ? v.last_test_event : v.claimed_event,
		title              = d.title,
		proposal           = d.proposal,
		stakes             = d.stakes,
		dramatic_score     = score,
		value              = v.kind,
		law_domain         = d.domain,
	}
	s.choices = d.choices
	s.choice_count = 4
	return s, true
}

value_action_for_effect :: proc(effect: Situation_Choice_Effect) -> Precedent_Action {
	#partial switch effect {case .Value_Comply:
		return .Comply; case .Value_Bounded:
		return .Bounded; case .Value_Exception:
		return .Exception; case .Value_Depart:
		return .Depart; case:
		return .None}
}

situation_precedent_action :: proc(
	s: Fleet_Situation,
	choice: Situation_Choice,
) -> Precedent_Action {
	if s.kind >= .Value_No_One_Left_Behind && s.kind <= .Value_Every_Home_Is_Free do return value_action_for_effect(choice.effect)
	if s.kind == .Rescue do return choice.effect == .Full_Rescue ? .Comply : choice.effect == .Promise_Return ? .Bounded : .Depart
	if s.kind == .Contested_Evidence do return choice.effect == .Publish_Evidence ? .Comply : choice.effect == .Review_Evidence ? .Bounded : choice.effect == .Restricted_Disclosure ? .Exception : .Depart
	return .None
}

situation_precedent_facts :: proc(
	s: Fleet_Situation,
	choice: Situation_Choice,
) -> Precedent_Action_Facts {
	action := situation_precedent_action(s, choice)
	f := Precedent_Action_Facts {
		material_commitment = choice.compute + choice.manpower + choice.raw_materials,
	}
	#partial switch action {case .Comply:
		f.fulfills_default = true; case .Bounded:
		f.fulfills_default = true; f.limits_duty = true
		f.residual_obligation = true; case .Exception:
		f.invokes_emergency = true; case .Depart:
		f.rejects_default = true; case:}
	return f
}

opposing_precedent_for_value :: proc(kind: Value_Kind) -> Precedent_Kind {
	switch kind {case .No_One_Left_Behind:
		return .Emergency_Command; case .Truth_Before_Comfort:
		return .Protective_Withholding; case .Consent_To_Settle:
		return .Council_Assignment; case .Shelter_Is_Sacred:
		return .Closed_Berths; case .Shared_Authority:
		return .Emergency_Command; case .Open_Archives:
		return .Custodial_Archives; case .The_Fleet_Endures:
		return .Right_Of_Departure; case .Every_Home_Is_Free:
		return .Continuing_Fleet_Jurisdiction}
	return .Emergency_Command
}

resolve_value_hard_case :: proc(
	c: ^Campaign,
	s: ^Fleet_Situation,
	choice: Situation_Choice,
) -> bool {
	action := value_action_for_effect(choice.effect); if action == .None do return false
	source := s.decision_event; if source == 0 do return false
	primary_kind := value_primary_precedent(
		s.value,
	); primary := active_precedent_id(c, primary_kind)
	if primary == 0 && (action == .Comply || action == .Bounded) {
		id, ok := enact_precedent_from_decision(
			c,
			{
				kind = primary_kind,
				source_decision = source,
				detail = founding_value_option(s.value),
				defining = true,
				beneficiary = s.affected_community,
			},
		); if ok do primary = id
	}
	if primary == 0 && (action == .Exception || action == .Depart) {
		opposing := opposing_precedent_for_value(
			s.value,
		); _, _ = enact_precedent_from_decision(c, {kind = opposing, source_decision = source, detail = "The fleet recorded the procedure used to depart from a claimed value.", beneficiary = s.affected_community})
		return record_value_test(c, s.value, false, source)
	}
	authority := precedent_event_for(c, .Emergency_Command); secondary: Precedent_ID
	if action == .Exception ||
	   action ==
		   .Depart {opposing := opposing_precedent_for_value(s.value); secondary = active_precedent_id(c, opposing); if secondary == 0 {secondary, _ = enact_precedent_from_decision(c, {kind = opposing, source_decision = source, detail = "The fleet recorded the procedure used to depart from the standing rule.", beneficiary = s.affected_community})}}
	_, ok := record_precedent_application(
		c,
		{
			domain = s.law_domain,
			primary_precedent = primary,
			source_decision = source,
			ship = s.initiator,
			community = s.affected_community,
			cited_authority_event = authority,
			secondary_precedent = secondary,
			facts = situation_precedent_facts(s^, choice),
		},
		action,
	)
	if !ok do return false
	if action == .Bounded do _ = add_promise(c, s.affected_community, c.season + 2, fmt.tprintf("Resolve the bounded duty recorded in %s.", s.title))
	return record_value_test(c, s.value, action == .Comply || action == .Bounded, source, primary)
}

record_situation_law :: proc(c: ^Campaign, s: ^Fleet_Situation, choice: Situation_Choice) -> bool {
	value :=
		Value_Kind.No_One_Left_Behind; domain := Precedent_Domain.None; action := Precedent_Action.None
	#partial switch s.kind {
	case .Rescue:
		value = .No_One_Left_Behind; domain = .Rescue
		action = choice.effect == .Full_Rescue ? .Comply : choice.effect == .Promise_Return ? .Bounded : .Depart
	case .Contested_Evidence:
		value = .Truth_Before_Comfort; domain = .Disclosure
		action = choice.effect == .Publish_Evidence ? .Comply : choice.effect == .Review_Evidence ? .Bounded : choice.effect == .Restricted_Disclosure ? .Exception : .Depart
	case:
		return true
	}
	vi := value_index(c, value); if vi < 0 do return true
	primary_kind := value_primary_precedent(value); primary := active_precedent_id(c, primary_kind)
	if primary == 0 &&
	   (action == .Comply ||
			   action ==
				   .Bounded) {id, ok := enact_precedent_from_decision(c, {kind = primary_kind, source_decision = s.decision_event, detail = founding_value_option(value), beneficiary = s.affected_community}); if ok do primary = id}
	if primary !=
	   0 {_, ok := record_precedent_application(c, {domain = domain, primary_precedent = primary, source_decision = s.decision_event, ship = s.initiator, community = s.affected_community, cited_authority_event = precedent_event_for(c, .Emergency_Command), facts = situation_precedent_facts(s^, choice)}, action); if !ok do return false}
	return record_value_test(
		c,
		value,
		action == .Comply || action == .Bounded,
		s.decision_event,
		primary,
	)
}
