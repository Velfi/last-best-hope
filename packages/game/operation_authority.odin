package game

import "core:encoding/json"
import "core:fmt"

OPERATION_AUTHORITY_VERSION :: 1

Operation_Authority_Clause :: enum {
	None,
	Objective,
	Beneficiary,
	Burden_Ship,
	Required_Roles,
	Protected_Roles,
	Exposure,
	Rescue,
	Withdrawal,
	Ordnance,
	Disclosure,
	Deviation,
	Reviewer,
}
Operation_Exposure :: enum {
	Conservative,
	Proportional,
	Mission_Critical,
}
Operation_Ordnance_Authority :: enum {
	Defensive_Only,
	Confirmed_Targets,
	Unrestricted,
}
Operation_Deviation_Authority :: enum {
	Prohibited,
	Explicit_Approval,
	Command_Discretion,
}

Operation_Authority_Source :: struct {
	clause:       Operation_Authority_Clause,
	undertaking_id:   u32,
	causal_event: u64,
}
Operation_Authority :: struct {
	version:                                           u32,
	undertaking_id:                                        u32,
	objective:                                         Operation_Objective,
	beneficiary:                                       Community_ID,
	burden_ship:                                       Ship_ID,
	required_roles, protected_roles:                   [8]bool,
	exposure:                                          Operation_Exposure,
	rescue:                                            Rescue_Policy,
	withdrawal:                                        Operation_Withdrawal,
	ordnance:                                          Operation_Ordnance_Authority,
	disclosure:                                        Disclosure_Policy,
	deviation:                                         Operation_Deviation_Authority,
	reviewer:                                          Institution_ID,
	beneficiary_name, burden_ship_name, reviewer_name: string,
	sources:                                           [13]Operation_Authority_Source,
	compiled_event:                                    u64,
	valid:                                             bool,
}
Operation_Authority_Issue :: enum {
	None,
	Missing_Undertaking,
	Inactive_Undertaking,
	Missing_Objective,
	Operation_Mismatch,
	Missing_Beneficiary,
	Missing_Burden_Ship,
	Missing_Reviewer,
	Missing_Causal_Event,
	Missing_Required_Role,
	Burden_Protected,
	Required_Protected,
	Rescue_Withdrawal_Conflict,
}
Operation_Authority_Validation :: struct {
	issues: [8]Operation_Authority_Issue,
	count:  int,
	valid:  bool,
}

operation_authority_add_issue :: proc(
	v: ^Operation_Authority_Validation,
	issue: Operation_Authority_Issue,
) {
	if v.count < len(v.issues) {v.issues[v.count] = issue; v.count += 1}
}
validate_operation_authority :: proc(
	a: ^Operation_Authority,
	operation: Operation_Kind = .None,
) -> (
	v: Operation_Authority_Validation,
) {
	if a == nil || a.undertaking_id == 0 {operation_authority_add_issue(&v, .Missing_Undertaking); return}
	if a.objective == .None do operation_authority_add_issue(&v, .Missing_Objective)
	if operation != .None && operation_objective_kind(a.objective) != operation do operation_authority_add_issue(&v, .Operation_Mismatch)
	if a.beneficiary == 0 do operation_authority_add_issue(&v, .Missing_Beneficiary)
	if a.burden_ship == 0 do operation_authority_add_issue(&v, .Missing_Burden_Ship)
	if a.reviewer == 0 do operation_authority_add_issue(&v, .Missing_Reviewer)
	if a.compiled_event == 0 do operation_authority_add_issue(&v, .Missing_Causal_Event)
	has_required := false
	for required, role in a.required_roles {
		if required do has_required = true
		if required &&
		   a.protected_roles[role] {operation_authority_add_issue(&v, .Required_Protected); break}
	}
	if !has_required do operation_authority_add_issue(&v, .Missing_Required_Role)
	if a.burden_ship != 0 && a.rescue == .Absolute_Duty && a.withdrawal == .Mandatory_Threshold {
		operation_authority_add_issue(&v, .Rescue_Withdrawal_Conflict)
	}
	v.valid = v.count == 0
	return
}
compact_objective_for_call :: proc(call: ^Compact_Call) -> Operation_Objective {
	if call == nil do return .None
	switch call.family {
	case .Survey_Verify:
		if call.approaches[call.selected_approach].kind == .Deep_Verification do return .Passage_Inspect_Treaty
		return .Passage_Evaluate_Home
	case .Rescue_Recover:
		return .Passage_Recover_Missing_Ship
	case .Escort_Evacuate:
		return .Passage_Escort_Migration
	case .Stabilize_Build:
		return .Passage_Recover_Reserves
	case .Defend_Intercept:
		if call.approaches[call.selected_approach].kind == .Delayed_Interception do return .Combat_Contested_Route
		return .Combat_Defend_Settlement
	case .None:
	}
	return .None
}

compile_compact_operation_authority :: proc(
	c: ^Campaign,
	call: ^Compact_Call,
	undertaking: ^Compact_Undertaking,
) -> (
	a: Operation_Authority,
	v: Operation_Authority_Validation,
) {
	if c == nil || call == nil || undertaking == nil || undertaking.id == 0 {
		operation_authority_add_issue(&v, .Missing_Undertaking)
		return
	}
	a.version = OPERATION_AUTHORITY_VERSION
	a.undertaking_id = u32(undertaking.id)
	a.objective = compact_objective_for_call(call)
	a.beneficiary = call.beneficiary
	a.compiled_event = undertaking.accepted_event
	a.reviewer = call.sponsor
	for offer in call.offers[:call.offer_count] {
		if !offer.selected || !offer.available do continue
		if a.burden_ship == 0 do a.burden_ship = offer.ship
		if at := ship_index(c, offer.ship); at >= 0 do a.required_roles[int(c.ships[at].role)] = true
	}
	if a.beneficiary == 0 && a.burden_ship != 0 {
		if at := ship_index(c, a.burden_ship); at >= 0 do a.beneficiary = c.ships[at].community
	}
	a.exposure = .Proportional
	a.rescue = .Mutual_Aid
	a.withdrawal = .Protected_Return
	a.ordnance = undertaking.approach == .Close_Defense ? .Defensive_Only : .Confirmed_Targets
	a.disclosure = .Accountable
	a.deviation = .Command_Discretion
	if at := institution_index(c, a.reviewer); at >= 0 {
		institution := c.institutions[at]
		a.rescue = institution.rescue_policy
		a.disclosure = institution.disclosure_policy
		a.deviation = .Explicit_Approval
		if institution.authority_policy == .Ship_Autonomy do a.deviation = .Command_Discretion
	}
	for clause in Operation_Authority_Clause {
		if clause == .None do continue
		a.sources[int(clause) - 1] = {clause, u32(undertaking.id), undertaking.accepted_event}
	}
	v = validate_operation_authority(&a, undertaking.operation)
	a.valid = v.valid
	if at := community_index(c, a.beneficiary); at >= 0 do a.beneficiary_name = c.communities[at].name
	if at := ship_index(c, a.burden_ship); at >= 0 do a.burden_ship_name = c.ships[at].name
	if at := institution_index(c, a.reviewer); at >= 0 do a.reviewer_name = c.institutions[at].name
	return
}
operation_authority_source :: proc(
	a: ^Operation_Authority,
	clause: Operation_Authority_Clause,
) -> Operation_Authority_Source {
	if a == nil || clause == .None do return {}
	return a.sources[int(clause) - 1]
}
operation_authority_clause_name :: proc(clause: Operation_Authority_Clause) -> string {
	switch clause {
	case .Objective:
		return "objective"
	case .Beneficiary:
		return "beneficiary"
	case .Burden_Ship:
		return "burden ship"
	case .Required_Roles:
		return "required roles"
	case .Protected_Roles:
		return "protected roles"
	case .Exposure:
		return "acceptable exposure"
	case .Rescue:
		return "rescue policy"
	case .Withdrawal:
		return "withdrawal policy"
	case .Ordnance:
		return "ordnance authority"
	case .Disclosure:
		return "disclosure policy"
	case .Deviation:
		return "deviation authority"
	case .Reviewer:
		return "reviewer"
	case .None:
	}
	return ""
}
operation_authority_explanation :: proc(
	a: ^Operation_Authority,
	clause: Operation_Authority_Clause,
) -> string {
	source := operation_authority_source(a, clause)
	if source.undertaking_id == 0 do return ""
	named_cause := ""
	switch clause {
	case .Beneficiary:
		if a.beneficiary_name != "" do named_cause = a.beneficiary_name
	case .Burden_Ship, .Required_Roles, .Protected_Roles, .Exposure, .Rescue, .Withdrawal:
		if a.burden_ship_name != "" do named_cause = a.burden_ship_name
	case .Ordnance, .Disclosure, .Deviation, .Reviewer:
		if a.reviewer_name != "" do named_cause = a.reviewer_name
	case .Objective, .None:
	}
	if named_cause != "" {
		return fmt.tprintf(
			"Undertaking %d %s authority for %s (event %d).",
			source.undertaking_id,
			operation_authority_clause_name(clause),
			named_cause,
			source.causal_event,
		)
	}
	return fmt.tprintf(
		"Undertaking %d %s authority (event %d).",
		source.undertaking_id,
		operation_authority_clause_name(clause),
		source.causal_event,
	)
}
operation_authority_allows_deviation :: proc(
	a: ^Operation_Authority,
	explicit_authorization: bool,
) -> bool {
	if a == nil || !a.valid do return false
	return a.deviation == .Command_Discretion || explicit_authorization
}

// Objective names differ by operation layer. This comparison deliberately
// holds every enforceable authority term constant while ignoring that adapter
// routing key.
operation_authority_semantics_equal :: proc(a, b: ^Operation_Authority) -> bool {
	if a == nil || b == nil do return false
	return(
		a.beneficiary == b.beneficiary &&
		a.burden_ship == b.burden_ship &&
		a.required_roles == b.required_roles &&
		a.protected_roles == b.protected_roles &&
		a.exposure == b.exposure &&
		a.rescue == b.rescue &&
		a.withdrawal == b.withdrawal &&
		a.ordnance == b.ordnance &&
		a.disclosure == b.disclosure &&
		a.deviation == b.deviation &&
		a.reviewer == b.reviewer \
	)
}

operation_authority_serialize :: proc(a: ^Operation_Authority) -> ([]u8, bool) {
	if a == nil || !a.valid do return nil, false
	data, error := json.marshal(a^)
	return data, error == nil
}

operation_authority_deserialize :: proc(
	data: []u8,
	operation: Operation_Kind = .None,
) -> (
	a: Operation_Authority,
	ok: bool,
) {
	if json.unmarshal(data, &a, allocator = context.temp_allocator) != nil ||
	   a.version != OPERATION_AUTHORITY_VERSION {
		return {}, false
	}
	validation := validate_operation_authority(&a, operation)
	a.valid = validation.valid
	return a, validation.valid
}
