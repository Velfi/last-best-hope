package game

Scenario_Domain :: enum {
	Passage,
	Combat,
}
Scenario_Objective_Predicate :: enum {
	Recover_Resource,
	Verify_Habitability,
	Evacuate_Population,
	Record_Violation,
	Escort_To_Endpoint,
	Recover_Ship,
	Disable_Command,
	Hold_Settlement,
	Open_Corridor,
	Protect_Convoy,
	Stabilize_Fleet,
	Control_Route,
}
Scenario_Failure_Continuation :: enum {
	Renewed_Claim,
	Recovery_Claim,
	Evacuation_Claim,
	Treaty_Dispute,
	Scattered_Convoy,
	Rescue_Search,
	Enemy_Entrenched,
	Settlement_Damaged,
	Blockade_Tightened,
	Migration_Diverted,
	Fleet_Adrift,
	Route_Closed,
}
Scenario_Capability :: enum u32 {
	Navigation = 1,
	Recovery   = 2,
	Medical    = 4,
	Escort     = 8,
	Survey     = 16,
	Logistics  = 32,
	Command    = 64,
	Firepower  = 128,
}

Scenario_Contract :: struct {
	scenario:              Operation_Objective,
	domain:                Scenario_Domain,
	objective:             Scenario_Objective_Predicate,
	required_capabilities: u32,
	optional_objective:    Scenario_Objective_Predicate,
	compatible_conduct:    [3]Operation_Conduct,
	generation_grammar:    string,
	failure_continuation:  Scenario_Failure_Continuation,
	political_output:      Need_Kind,
}

operation_objective_kind :: proc(objective: Operation_Objective) -> Operation_Kind {
	if objective >= .Passage_Recover_Reserves && objective <= .Passage_Recover_Missing_Ship {
		return .Passage
	}
	if objective >= .Combat_Recover_Seedship && objective <= .Combat_Contested_Route {
		return .Combat
	}
	return .None
}

operation_objective_purpose :: proc(objective: Operation_Objective) -> Dark_Contract_Purpose {
	switch objective {
	case .Passage_Evaluate_Home:
		return .Ecological_Survey
	case .Passage_Inspect_Treaty:
		return .Verify_Correspondence
	case .Passage_Recover_Reserves, .Passage_Evacuate_Harbor, .Passage_Escort_Migration:
		return .Infrastructure_Run
	case .Passage_Recover_Missing_Ship:
		return .Stabilize_Relay
	case .Combat_Recover_Seedship,
	     .Combat_Defend_Settlement,
	     .Combat_Break_Blockade,
	     .Combat_Escort_Migration,
	     .Combat_Recover_Disabled_Fleet,
	     .Combat_Contested_Route,
	     .None:
		return .None
	}
	return .None
}

scenario_contract :: proc(s: Operation_Objective) -> Scenario_Contract {
	terms := [3]Operation_Conduct{.Preserve_Lives, .Open_Record, .Mission_First}
	switch s {
	case .Passage_Recover_Reserves:
		return {
			s,
			.Passage,
			.Recover_Resource,
			u32(Scenario_Capability.Navigation) | u32(Scenario_Capability.Recovery),
			.Verify_Habitability,
			terms,
			"resource signature beyond a hazardous correspondence",
			.Renewed_Claim,
			.Sustenance_Shortfall,
		}
	case .Passage_Evaluate_Home:
		return {
			s,
			.Passage,
			.Verify_Habitability,
			u32(Scenario_Capability.Navigation) | u32(Scenario_Capability.Survey),
			.Record_Violation,
			terms,
			"candidate habitat with incomplete and contestable evidence",
			.Renewed_Claim,
			.Settlement_Demand,
		}
	case .Passage_Evacuate_Harbor:
		return {
			s,
			.Passage,
			.Evacuate_Population,
			u32(Scenario_Capability.Logistics) | u32(Scenario_Capability.Medical),
			.Recover_Resource,
			terms,
			"failing harbor, staged embarkation, closing safe endpoint",
			.Evacuation_Claim,
			.Settlement_Defense,
		}
	case .Passage_Inspect_Treaty:
		return {
			s,
			.Passage,
			.Record_Violation,
			u32(Scenario_Capability.Navigation) | u32(Scenario_Capability.Survey),
			.Control_Route,
			terms,
			"disputed correspondence with evidence held by opposing actors",
			.Treaty_Dispute,
			.Institution_Dispute,
		}
	case .Passage_Escort_Migration:
		return {
			s,
			.Passage,
			.Escort_To_Endpoint,
			u32(Scenario_Capability.Escort) | u32(Scenario_Capability.Logistics),
			.Recover_Ship,
			terms,
			"seasonal convoy crossing several replanning hazards",
			.Scattered_Convoy,
			.Representation,
		}
	case .Passage_Recover_Missing_Ship:
		return {
			s,
			.Passage,
			.Recover_Ship,
			u32(Scenario_Capability.Navigation) | u32(Scenario_Capability.Recovery),
			.Record_Violation,
			terms,
			"last-known trace, false correspondence, recoverable survivor record",
			.Rescue_Search,
			.Ship_Repair,
		}
	case .Combat_Recover_Seedship:
		return {
			s,
			.Combat,
			.Disable_Command,
			u32(Scenario_Capability.Command) | u32(Scenario_Capability.Firepower),
			.Recover_Ship,
			terms,
			"relay search revealing a protected strategic asset",
			.Enemy_Entrenched,
			.Archive_Staffing,
		}
	case .Combat_Defend_Settlement:
		return {
			s,
			.Combat,
			.Hold_Settlement,
			u32(Scenario_Capability.Escort) | u32(Scenario_Capability.Firepower),
			.Protect_Convoy,
			terms,
			"defensive rings around persistent civilian infrastructure",
			.Settlement_Damaged,
			.Settlement_Defense,
		}
	case .Combat_Break_Blockade:
		return {
			s,
			.Combat,
			.Open_Corridor,
			u32(Scenario_Capability.Command) | u32(Scenario_Capability.Firepower),
			.Protect_Convoy,
			terms,
			"layered interdiction screen with a timed traffic corridor",
			.Blockade_Tightened,
			.Sustenance_Shortfall,
		}
	case .Combat_Escort_Migration:
		return {
			s,
			.Combat,
			.Protect_Convoy,
			u32(Scenario_Capability.Escort) | u32(Scenario_Capability.Command),
			.Open_Corridor,
			terms,
			"moving civilian convoy whose route reacts to contact",
			.Migration_Diverted,
			.Representation,
		}
	case .Combat_Recover_Disabled_Fleet:
		return {
			s,
			.Combat,
			.Stabilize_Fleet,
			u32(Scenario_Capability.Recovery) | u32(Scenario_Capability.Firepower),
			.Disable_Command,
			terms,
			"separated disabled groups under converging attack",
			.Fleet_Adrift,
			.Ship_Repair,
		}
	case .Combat_Contested_Route:
		return {
			s,
			.Combat,
			.Control_Route,
			u32(Scenario_Capability.Navigation) | u32(Scenario_Capability.Firepower),
			.Open_Corridor,
			terms,
			"multiple access nodes with reversible control",
			.Route_Closed,
			.Jurisdiction_Dispute,
		}
	case .None:
		return {}
	}
	return {}
}

scenario_contract_valid :: proc(c: Scenario_Contract) -> bool {return(
		c.scenario != .None &&
		c.required_capabilities != 0 &&
		c.generation_grammar != "" &&
		c.political_output >= .Sustenance_Shortfall \
	)}
