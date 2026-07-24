package main

import game "../packages/game"

need_cost_name :: proc(kind: game.Need_Kind) -> string {switch kind {case .Sustenance_Shortfall:
		return "SUSTENANCE"; case .Ship_Repair, .Settlement_Defense:
		return "INDUSTRY"; case .Archive_Staffing:
		return(
			"KNOWLEDGE" \
		); case .Settlement_Demand, .Representation, .Settlement_Charter, .Jurisdiction_Dispute, .Institution_Dispute:
		return "COHESION"}; return "RESOURCE"}
