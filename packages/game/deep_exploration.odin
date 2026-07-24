package game

STANDARD_FIELD_DEPTH_RATING :: 4.0
EMERGENCY_FIELD_DEPTH_LIMIT :: 6.5

Deep_Exploration_Setup :: struct {
	purpose:    Dark_Contract_Purpose,
	ship_count: int,
	strategy:   Dark_Strategy_Profile,
}

DEEP_EXPLORATION_PURPOSES :: [5]Dark_Contract_Purpose {
	.Map_Unknown_Door,
	.Verify_Correspondence,
	.Ecological_Survey,
	.Stabilize_Relay,
	.Infrastructure_Run,
}

deep_exploration_default_setup :: proc() -> Deep_Exploration_Setup {
	return {purpose = .Map_Unknown_Door, ship_count = 2, strategy = dark_default_strategy(.None)}
}

deep_exploration_purpose_name :: proc(purpose: Dark_Contract_Purpose) -> string {
	switch purpose {
	case .Map_Unknown_Door:
		return "MAP UNKNOWN DOOR"
	case .Verify_Correspondence:
		return "VERIFY CORRESPONDENCE"
	case .Ecological_Survey:
		return "ECOLOGICAL SURVEY"
	case .Stabilize_Relay:
		return "STABILIZE RELAY"
	case .Infrastructure_Run:
		return "INFRASTRUCTURE RUN"
	case .None:
		return "NO OBJECTIVE"
	}
	return "NO OBJECTIVE"
}

deep_exploration_purpose_description :: proc(purpose: Dark_Contract_Purpose) -> string {
	switch purpose {
	case .Map_Unknown_Door:
		return "Locate and cross an unmapped correspondence, then return its position."
	case .Verify_Correspondence:
		return "Cross a correspondence and establish a reliable normal-space position."
	case .Ecological_Survey:
		return "Record the five known ecological roles before returning."
	case .Stabilize_Relay:
		return "Reach normal space and establish or service an authenticated relay."
	case .Infrastructure_Run:
		return "Find a resource-bearing endpoint and preserve a route back to it."
	case .None:
		return ""
	}
	return ""
}

deep_exploration_contract :: proc(setup: ^Deep_Exploration_Setup) -> Dark_Contract {
	contract := default_passage_contract()
	contract.purpose = setup.purpose
	contract.undertaking_id = 0
	contract.need_index = -1
	contract.required_roles = 0
	contract.protected_roles = {}
	contract.breach_authorized = false
	contract.standalone = true
	return contract
}
