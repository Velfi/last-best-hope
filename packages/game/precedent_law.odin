package game

import "core:fmt"

Value_Kind :: enum {
	No_One_Left_Behind,
	Truth_Before_Comfort,
	Consent_To_Settle,
	Shelter_Is_Sacred,
	Shared_Authority,
	Open_Archives,
	The_Fleet_Endures,
	Every_Home_Is_Free,
}
Value_Status :: enum {
	Claimed,
	Tested,
	Embodied,
	Compromised,
	Renounced,
}
Civilization_Value :: struct {
	kind:                                            Value_Kind,
	status:                                          Value_Status,
	claimed_event, last_test_event, renounced_event: u64,
	tests, consistent_tests, contradictions:         i32,
	enacted_precedent:                               Precedent_ID,
}

Precedent_Status :: enum {
	Active,
	Contested,
	Superseded,
}
Precedent_Domain :: enum {
	None,
	Rescue,
	Combat_Withdrawal,
	Settlement_Defense,
	Departure,
	Disclosure,
	Adaptation,
	Settlement_Charter,
	Refuge,
	Archives,
	Authority,
	Fleet_Continuity,
}
Precedent_Scope :: distinct u32
Precedent_Interpretation :: enum {
	Default,
	Attempt_When_Reachable,
	Attempt_Unless_Fleet_Collapse_Risk,
	Answer_Existing_Protection_Duties,
	Material_Risk_Before_Exposure,
	Verified_Risk_Before_Exposure,
	Public_Finding_Protected_Method,
	Participatory_Majority_With_Exit,
	Voluntary_Opt_In,
	Supermajority_Irreversible_Transfer,
	Temporary_Berth_And_Review,
	Admission_Up_To_Habitat_Floor,
	Aid_Or_Berth_When_Viable,
	Affected_Communities_Represented,
	Rotating_Council_Jurisdiction,
	Institutional_Delegation_With_Review,
	Public_Copy_With_Personal_Seals,
	Recognized_Custodian_Copies,
	Open_Queries_Emergency_Replication,
	Essential_Capabilities_Preserved,
	Compact_Allows_Distributed_Fleet,
	Central_Command_Must_Persist,
	Immediate_Charter_Sovereignty,
	Timed_Transition_With_Review,
	Enumerated_Federal_Powers,
	Community_Authorized_Heritable_Change,
	Individual_Opt_In_Unmodified_Lineage,
	Emergency_Adaptation_Descendant_Review,
}
Precedent :: struct {
	id:                              Precedent_ID,
	kind:                            Precedent_Kind,
	status:                          Precedent_Status,
	scope:                           Precedent_Scope,
	interpretation:                  Precedent_Interpretation,
	season:                          i32,
	detail:                          string,
	defining:                        bool,
	event_sequence, source_decision: u64,
	sponsor_institution:             Institution_ID,
	beneficiary:                     Community_ID,
	superseded_by:                   Precedent_ID,
	semantic_tags:                   Semantic_Tags,
}
Precedent_Case_Status :: enum {
	Pending,
	Affirmed,
	Narrowed,
	Replaced,
	Contested,
}
Precedent_Case :: struct {
	id:                                                          Precedent_Case_ID,
	primary, secondary:                                          Precedent_ID,
	status:                                                      Precedent_Case_Status,
	source_decision, contradiction_event, cited_authority_event: u64,
	initiator_ship:                                              Ship_ID,
	affected_community:                                          Community_ID,
	responsible_institution:                                     Institution_ID,
	review_season:                                               i32,
	last_event:                                                  u64,
}

Precedent_Action :: enum {
	None,
	Comply,
	Bounded,
	Exception,
	Depart,
}
Precedent_Classification :: enum {
	None,
	Complies,
	Bounded_Compliance,
	Exception,
	Departure,
	Disputed,
}
Precedent_Review :: enum {
	Affirm,
	Narrow,
	Replace,
	Leave_Contested,
}
Precedent_Action_Facts :: struct {
	fulfills_default, limits_duty, invokes_emergency, rejects_default: bool,
	material_commitment:                                               i32,
	residual_obligation:                                               bool,
}

Precedent_Context :: struct {
	domain:                Precedent_Domain,
	primary_precedent:     Precedent_ID,
	source_decision:       u64,
	ship:                  Ship_ID,
	community:             Community_ID,
	institution:           Institution_ID,
	cited_authority_event: u64,
	secondary_precedent:   Precedent_ID,
	facts:                 Precedent_Action_Facts,
}

Precedent_Application :: struct {
	applicable:               bool,
	precedent:                Precedent_ID,
	secondary:                Precedent_ID,
	status:                   Precedent_Status,
	interpretation:           Precedent_Interpretation,
	classification:           Precedent_Classification,
	reason:                   string,
	requires_authority:       bool,
	creates_or_advances_case: bool,
	precedent_event:          u64,
	source_decision:          u64,
	known_consequence:        string,
	review_follows:           bool,
}

Precedent_Enactment :: struct {
	kind:                Precedent_Kind,
	interpretation:      Precedent_Interpretation,
	scope:               Precedent_Scope,
	source_decision:     u64,
	detail:              string,
	sponsor_institution: Institution_ID,
	beneficiary:         Community_ID,
	defining:            bool,
}

precedent_domain_scope :: proc(domain: Precedent_Domain) -> Precedent_Scope {
	if domain == .None do return Precedent_Scope(0)
	return Precedent_Scope(u32(1) << u32(domain))
}

precedent_scope_has :: proc(scope: Precedent_Scope, domain: Precedent_Domain) -> bool {
	return domain != .None && (u32(scope) & u32(precedent_domain_scope(domain))) != 0
}

precedent_scope_for_kind :: proc(kind: Precedent_Kind) -> Precedent_Scope {
	add := proc(scope: Precedent_Scope, domain: Precedent_Domain) -> Precedent_Scope {
		return Precedent_Scope(u32(scope) | u32(precedent_domain_scope(domain)))
	}
	s: Precedent_Scope
	#partial switch kind {
	case .No_One_Left_Behind:
		s = add(s, .Rescue); s = add(s, .Combat_Withdrawal); s = add(s, .Settlement_Defense)
	case .Accountable_Disclosure, .Protective_Withholding:
		s = add(s, .Disclosure); s = add(s, .Settlement_Charter)
	case .Consent_Of_The_Settled, .Council_Assignment, .Proportionate_Asset_Division:
		s = add(s, .Settlement_Charter); s = add(s, .Adaptation); s = add(s, .Departure)
	case .Right_Of_Refuge, .Emergency_Admission, .Closed_Berths:
		s = add(s, .Refuge); s = add(s, .Settlement_Defense)
	case .Shared_Authority, .Emergency_Command, .Ship_Sovereignty:
		s = add(s, .Authority); s = add(s, .Departure); s = add(s, .Settlement_Charter)
	case .Open_Archives, .Custodial_Archives:
		s = add(s, .Archives); s = add(s, .Disclosure); s = add(s, .Settlement_Charter)
	case .Continuity_Of_The_Fleet:
		s = add(s, .Fleet_Continuity); s = add(s, .Departure); s = add(s, .Settlement_Charter)
	case .Founding_Independence, .Continuing_Fleet_Jurisdiction, .Right_Of_Departure:
		s = add(s, .Departure); s = add(s, .Settlement_Charter)
	case .Adaptation_Accepted:
		s = add(s, .Adaptation); s = add(s, .Settlement_Charter)
	}
	return s
}

precedent_default_interpretation :: proc(kind: Precedent_Kind) -> Precedent_Interpretation {
	#partial switch kind {
	case .No_One_Left_Behind:
		return .Attempt_When_Reachable
	case .Accountable_Disclosure:
		return .Material_Risk_Before_Exposure
	case .Protective_Withholding:
		return .Verified_Risk_Before_Exposure
	case .Consent_Of_The_Settled:
		return .Participatory_Majority_With_Exit
	case .Right_Of_Refuge:
		return .Temporary_Berth_And_Review
	case .Emergency_Admission:
		return .Admission_Up_To_Habitat_Floor
	case .Closed_Berths:
		return .Aid_Or_Berth_When_Viable
	case .Shared_Authority:
		return .Affected_Communities_Represented
	case .Open_Archives:
		return .Public_Copy_With_Personal_Seals
	case .Custodial_Archives:
		return .Recognized_Custodian_Copies
	case .Continuity_Of_The_Fleet:
		return .Essential_Capabilities_Preserved
	case .Founding_Independence:
		return .Immediate_Charter_Sovereignty
	case .Adaptation_Accepted:
		return .Community_Authorized_Heritable_Change
	case:
		return .Default
	}
}

precedent_interpretation_valid :: proc(
	kind: Precedent_Kind,
	interpretation: Precedent_Interpretation,
) -> bool {
	if interpretation == .Default do return precedent_default_interpretation(kind) == .Default
	#partial switch kind {
	case .No_One_Left_Behind:
		return(
			interpretation == .Attempt_When_Reachable ||
			interpretation == .Attempt_Unless_Fleet_Collapse_Risk ||
			interpretation == .Answer_Existing_Protection_Duties \
		)
	case .Accountable_Disclosure, .Protective_Withholding:
		return(
			interpretation == .Material_Risk_Before_Exposure ||
			interpretation == .Verified_Risk_Before_Exposure ||
			interpretation == .Public_Finding_Protected_Method \
		)
	case .Consent_Of_The_Settled:
		return(
			interpretation == .Participatory_Majority_With_Exit ||
			interpretation == .Voluntary_Opt_In ||
			interpretation == .Supermajority_Irreversible_Transfer \
		)
	case .Right_Of_Refuge, .Emergency_Admission, .Closed_Berths:
		return(
			interpretation == .Temporary_Berth_And_Review ||
			interpretation == .Admission_Up_To_Habitat_Floor ||
			interpretation == .Aid_Or_Berth_When_Viable \
		)
	case .Shared_Authority:
		return(
			interpretation == .Affected_Communities_Represented ||
			interpretation == .Rotating_Council_Jurisdiction ||
			interpretation == .Institutional_Delegation_With_Review \
		)
	case .Open_Archives, .Custodial_Archives:
		return(
			interpretation == .Public_Copy_With_Personal_Seals ||
			interpretation == .Recognized_Custodian_Copies ||
			interpretation == .Open_Queries_Emergency_Replication \
		)
	case .Continuity_Of_The_Fleet:
		return(
			interpretation == .Essential_Capabilities_Preserved ||
			interpretation == .Compact_Allows_Distributed_Fleet ||
			interpretation == .Central_Command_Must_Persist \
		)
	case .Founding_Independence:
		return(
			interpretation == .Immediate_Charter_Sovereignty ||
			interpretation == .Timed_Transition_With_Review ||
			interpretation == .Enumerated_Federal_Powers \
		)
	case .Adaptation_Accepted:
		return(
			interpretation == .Community_Authorized_Heritable_Change ||
			interpretation == .Individual_Opt_In_Unmodified_Lineage ||
			interpretation == .Emergency_Adaptation_Descendant_Review \
		)
	case:
		return false
	}
}

precedent_index_by_id :: proc(c: ^Campaign, id: Precedent_ID) -> int {
	if id == 0 do return -1
	for p, i in c.precedents[:c.precedent_count] do if p.id == id do return i
	return -1
}

active_precedent_id :: proc(c: ^Campaign, kind: Precedent_Kind) -> Precedent_ID {
	for i := c.precedent_count - 1;
	    i >= 0;
	    i -= 1 {p := c.precedents[i]; if p.kind == kind && p.status != .Superseded do return p.id}
	return 0
}

enact_precedent_from_decision :: proc(
	c: ^Campaign,
	e: Precedent_Enactment,
) -> (
	Precedent_ID,
	bool,
) {
	if c.precedent_count >= MAX_PRECEDENTS || e.source_decision == 0 || event_index_by_sequence(c, e.source_decision) < 0 || e.detail == "" do return 0, false
	if existing := active_precedent_id(c, e.kind); existing != 0 do return existing, false
	if c.next_precedent_id == 0 do c.next_precedent_id = 1
	id := Precedent_ID(c.next_precedent_id); c.next_precedent_id += 1
	interpretation :=
		e.interpretation; if interpretation == .Default do interpretation = precedent_default_interpretation(e.kind)
	scope := e.scope; if u32(scope) == 0 do scope = precedent_scope_for_kind(e.kind)
	c.precedents[c.precedent_count] = {
		id                  = id,
		kind                = e.kind,
		status              = .Active,
		scope               = scope,
		interpretation      = interpretation,
		season              = c.season,
		detail              = e.detail,
		defining            = e.defining,
		source_decision     = e.source_decision,
		sponsor_institution = e.sponsor_institution,
		beneficiary         = e.beneficiary,
		semantic_tags       = semantic_tags_for_precedent(e.kind),
	}
	c.precedent_count += 1
	record_event(
		c,
		.Precedent_Enacted,
		e.detail,
		value = i32(e.kind),
		community = e.beneficiary,
		cause_sequence = e.source_decision,
		institution_id = e.sponsor_institution,
	)
	c.precedents[c.precedent_count - 1].event_sequence = c.event_sequence
	return id, true
}

enact_precedent_after_event :: proc(
	c: ^Campaign,
	kind: Precedent_Kind,
	detail: string,
	source_decision: u64,
	defining := false,
) -> bool {
	_, ok := enact_precedent_from_decision(
		c,
		{kind = kind, source_decision = source_decision, detail = detail, defining = defining},
	)
	return ok
}

enact_precedent_fixture :: proc(
	c: ^Campaign,
	kind: Precedent_Kind,
	detail: string,
	defining := false,
) -> bool {
	record_event(c, .Situation_Decided, detail)
	return enact_precedent_after_event(c, kind, detail, c.event_sequence, defining)
}


