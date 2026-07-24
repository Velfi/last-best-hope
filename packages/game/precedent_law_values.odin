package game

import "core:fmt"

Founding_Value_Scenario :: struct {
	title, premise: string,
	first, second:  Value_Kind,
}

FOUNDING_VALUE_SCENARIOS := [28]Founding_Value_Scenario {
	{
		"The Last Recovery Window",
		"A damaged evacuation ship can be reached only by diverting vessels assigned to the first council.",
		.No_One_Left_Behind,
		.Truth_Before_Comfort,
	},
	{
		"The Assigned Lifeboats",
		"A community ordered onto a marginal lifeboat asks the fleet to recover people who refused assignment.",
		.No_One_Left_Behind,
		.Consent_To_Settle,
	},
	{
		"Berths at Departure",
		"A late refugee convoy and a stranded fleet ship both request the same remaining habitat berths.",
		.No_One_Left_Behind,
		.Shelter_Is_Sacred,
	},
	{
		"Authority for the Turnback",
		"A recovery course remains possible, but the communities bearing its cost have not authorized it.",
		.No_One_Left_Behind,
		.Shared_Authority,
	},
	{
		"The Rescue Record",
		"Publishing the true rescue margin may cause ships to break formation before the fleet can return.",
		.No_One_Left_Behind,
		.Open_Archives,
	},
	{
		"Who Continues",
		"A recovery attempt requires the last vessel able to keep the fleet's foundries operating.",
		.No_One_Left_Behind,
		.The_Fleet_Endures,
	},
	{
		"A Harbor's First Refusal",
		"A newly safe harbor claims sovereignty while a fleet ship remains in distress beyond it.",
		.No_One_Left_Behind,
		.Every_Home_Is_Free,
	},
	{
		"The Destination File",
		"The first settlement mandate is ready, but the complete destination record contains a serious disputed hazard.",
		.Truth_Before_Comfort,
		.Consent_To_Settle,
	},
	{
		"The Quarantine Report",
		"Disclosing the condition of arriving refugees may close the fleet's only available shelter.",
		.Truth_Before_Comfort,
		.Shelter_Is_Sacred,
	},
	{
		"The Sealed Evacuation List",
		"Community delegates request the names omitted from the official evacuation account.",
		.Truth_Before_Comfort,
		.Shared_Authority,
	},
	{
		"The Surviving Copy",
		"Opening the evacuation archive will expose dangerous methods as well as the accepted account of the Loss.",
		.Truth_Before_Comfort,
		.Open_Archives,
	},
	{
		"The Fracture Forecast",
		"A verified fleet-continuity forecast predicts that several communities cannot remain together.",
		.Truth_Before_Comfort,
		.The_Fleet_Endures,
	},
	{
		"A Founder's Hidden Risk",
		"A departing community asks for sovereignty before the fleet publishes the danger in its assigned world.",
		.Truth_Before_Comfort,
		.Every_Home_Is_Free,
	},
	{
		"Shelter by Compact",
		"A crowded habitat can admit refugees only by relocating residents who have refused transfer.",
		.Consent_To_Settle,
		.Shelter_Is_Sacred,
	},
	{
		"The First Binding Vote",
		"The fleet can settle a divided community immediately or wait for representatives to establish a mandate.",
		.Consent_To_Settle,
		.Shared_Authority,
	},
	{
		"Records That Must Depart",
		"A consenting settlement requires an archive whose custodians oppose permanent transfer.",
		.Consent_To_Settle,
		.Open_Archives,
	},
	{
		"The Essential Ship's Vote",
		"The last repair ship's community votes to leave the fleet for a viable home.",
		.Consent_To_Settle,
		.The_Fleet_Endures,
	},
	{
		"Consent After Founding",
		"A community accepts settlement only if the fleet relinquishes all authority at departure.",
		.Consent_To_Settle,
		.Every_Home_Is_Free,
	},
	{
		"Who Opens the Berths",
		"The council and a hospital ship claim conflicting authority over admission of a refugee convoy.",
		.Shelter_Is_Sacred,
		.Shared_Authority,
	},
	{
		"Names of the Admitted",
		"Refugees request sealed status while public archives require a durable account of fleet membership.",
		.Shelter_Is_Sacred,
		.Open_Archives,
	},
	{
		"The Harbor Convoy",
		"Admitting a large refugee convoy will disperse the ships required to keep the traveling fleet coherent.",
		.Shelter_Is_Sacred,
		.The_Fleet_Endures,
	},
	{
		"Refuge in a Free Home",
		"A sovereign settlement can shelter arrivals the fleet cannot house, but it demands control over admission.",
		.Shelter_Is_Sacred,
		.Every_Home_Is_Free,
	},
	{
		"Custody of the Common Record",
		"Community delegates and archive institutions dispute who may authorize access to the surviving record.",
		.Shared_Authority,
		.Open_Archives,
	},
	{
		"The Command That Remains",
		"The fleet can preserve unified command only by limiting the authority promised to its communities.",
		.Shared_Authority,
		.The_Fleet_Endures,
	},
	{
		"A Charter Before Departure",
		"The first founders demand sovereignty while fleet communities seek a continuing voice in their charter.",
		.Shared_Authority,
		.Every_Home_Is_Free,
	},
	{
		"Copies Across the Fracture",
		"Distributing the archive protects knowledge but enables ships preparing to leave the fleet permanently.",
		.Open_Archives,
		.The_Fleet_Endures,
	},
	{
		"The Founder's Archive",
		"A sovereign settlement claims exclusive custody of records copied with fleet capacity.",
		.Open_Archives,
		.Every_Home_Is_Free,
	},
	{
		"The Fleet or the Harbor",
		"The first viable home can become independent only by taking ships essential to continued passage.",
		.The_Fleet_Endures,
		.Every_Home_Is_Free,
	},
}

founding_value_scenario :: proc(a, b: Value_Kind) -> Founding_Value_Scenario {i :=
		value_pair_index(a, b)
	if i < 0 do return {}
	return FOUNDING_VALUE_SCENARIOS[i]}

founding_loss_pressure :: proc(loss: Loss_Kind) -> string {
	switch loss {case .Catastrophe:
		return(
			"Systems damaged during the catastrophe leave one intervention window." \
		); case .Expulsion:
		return "Pursuit and disputed custody shorten the decision window."; case .Civil_War:
		return "The actors carry incompatible records of earlier authority."; case .Unknown_Event:
		return(
			"The cause of the Loss remains unresolved, limiting the certainty of every forecast." \
		)}
	return ""
}

founding_value_option :: proc(value: Value_Kind) -> string {
	switch value {case .No_One_Left_Behind:
		return "Commit ships to an attempted recovery."; case .Truth_Before_Comfort:
		return "Publish the known danger before assigning exposure."; case .Consent_To_Settle:
		return(
			"Require a recorded mandate from those permanently transferred." \
		); case .Shelter_Is_Sacred:
		return "Open provisional shelter and record its continuing cost."; case .Shared_Authority:
		return "Refer the binding decision to affected representatives."; case .Open_Archives:
		return "Create accessible copies under a public custody record."; case .The_Fleet_Endures:
		return(
			"Preserve every capability required for a continuing fleet." \
		); case .Every_Home_Is_Free:
		return "Transfer charter authority with the founding community."}
	return ""
}

Value_Hard_Case_Definition :: struct {
	kind:                    Value_Kind,
	title, proposal, stakes: string,
	domain:                  Precedent_Domain,
	choices:                 [4]Situation_Choice,
}
VALUE_HARD_CASES := [8]Value_Hard_Case_Definition {
	{
		.No_One_Left_Behind,
		"The degrading correspondence",
		"A damaged expedition calls from a route that may close before a recovery ship returns.",
		"Recovery risks the fleet's only applicable route record.",
		.Rescue,
		{
			{
				"Commit a recovery corridor",
				"Two ships attempt recovery before the correspondence collapses.",
				.Value_Comply,
				false,
				1,
				2,
				0,
			},
			{
				"Promise a bounded return",
				"A scout marks the route and a dated recovery obligation survives.",
				.Value_Bounded,
				false,
				0,
				1,
				0,
			},
			{
				"Conserve the fleet under emergency authority",
				"Command preserves the only route-capable ship and submits the refusal to review.",
				.Value_Exception,
				false,
				0,
				0,
				0,
			},
			{
				"Close the correspondence",
				"The fleet abandons recovery without claiming the rescue duty was met.",
				.Value_Depart,
				true,
				0,
				0,
				0,
			},
		},
	},
	{
		.Truth_Before_Comfort,
		"The disputed biosphere",
		"A viable candidate home carries disputed evidence of indigenous biology.",
		"Disclosure may end the mandate before another home can be supplied.",
		.Disclosure,
		{
			{
				"Publish the material finding",
				"The biosphere risk enters every settlement briefing before exposure.",
				.Value_Comply,
				false,
				1,
				1,
				0,
			},
			{
				"Publish findings; protect methods",
				"The danger becomes public while hazardous sampling methods remain controlled.",
				.Value_Bounded,
				false,
				1,
				0,
				0,
			},
			{
				"Order independent emergency review",
				"Exposure pauses under temporary authority and the withholding receives review.",
				.Value_Exception,
				false,
				0,
				0,
				0,
			},
			{
				"Suppress the disputed account",
				"The mandate proceeds without the material finding in its public record.",
				.Value_Depart,
				true,
				0,
				0,
				0,
			},
		},
	},
	{
		.Consent_To_Settle,
		"The failing habitat",
		"A habitat will fail before its divided community can complete another settlement mandate.",
		"Emergency transfer protects dependents while contradicting measured opposition.",
		.Settlement_Charter,
		{
			{
				"Fund a rapid participating mandate",
				"Affected adults choose before permanent transfer begins.",
				.Value_Comply,
				false,
				1,
				2,
				0,
			},
			{
				"Relocate dependents provisionally",
				"Temporary shelter proceeds while permanent assignment remains opt-in.",
				.Value_Bounded,
				false,
				0,
				1,
				0,
			},
			{
				"Authorize emergency relocation",
				"Command moves the habitat population and submits permanence to review.",
				.Value_Exception,
				false,
				0,
				0,
				0,
			},
			{
				"Assign the settlement cohort",
				"The fleet makes permanent assignments over recorded opposition.",
				.Value_Depart,
				true,
				0,
				0,
				0,
			},
		},
	},
	{
		.Shelter_Is_Sacred,
		"Carriers from a hostile harbor",
		"Civilians arrive from a settlement that previously seized fleet equipment.",
		"Admission consumes quarantine capacity; refusal returns them to immediate exposure.",
		.Refuge,
		{
			{
				"Open quarantine berths",
				"The newcomers receive provisional shelter and a later community review.",
				.Value_Comply,
				false,
				1,
				2,
				0,
			},
			{
				"Sustain refuge alongside the fleet",
				"Aid and escort preserve life while berths are prepared.",
				.Value_Bounded,
				false,
				0,
				1,
				0,
			},
			{
				"Close berths at the habitat floor",
				"Emergency authority protects current residents and triggers constitutional review.",
				.Value_Exception,
				false,
				0,
				0,
				0,
			},
			{
				"Turn the carriers away",
				"No continuing refuge or aid obligation is accepted.",
				.Value_Depart,
				true,
				0,
				0,
				0,
			},
		},
	},
	{
		.Shared_Authority,
		"A route shorter than debate",
		"A correspondence will close before the council can finish deliberation.",
		"Immediate departure uses reserves promised by an affected community.",
		.Authority,
		{
			{
				"Convene affected delegates now",
				"The route waits on an abbreviated but representative decision.",
				.Value_Comply,
				false,
				1,
				2,
				0,
			},
			{
				"Delegate with a recall vote",
				"A limited institution acts now and faces a dated mandate review.",
				.Value_Bounded,
				false,
				1,
				0,
				0,
			},
			{
				"Invoke emergency command",
				"Command chooses before closure and submits the mandate to review.",
				.Value_Exception,
				false,
				0,
				0,
				0,
			},
			{
				"Depart by unilateral order",
				"The affected community receives no binding voice in the use of its reserves.",
				.Value_Depart,
				true,
				0,
				0,
				0,
			},
		},
	},
	{
		.Open_Archives,
		"The dangerous method",
		"A settlement offers a route-opening method only under exclusive local custody.",
		"Replication distributes both resilience and a demonstrated navigation hazard.",
		.Archives,
		{
			{
				"Create sealed public copies",
				"Recognized archives receive resilient copies with dangerous procedures sealed.",
				.Value_Comply,
				false,
				1,
				1,
				0,
			},
			{
				"Recognize distributed custodians",
				"Queries remain open while complete methods stay with accountable custodians.",
				.Value_Bounded,
				false,
				1,
				0,
				0,
			},
			{
				"Restrict copying during the hazard",
				"Emergency custody limits replication and schedules review.",
				.Value_Exception,
				false,
				0,
				0,
				0,
			},
			{
				"Accept exclusive custody",
				"The fleet abandons any right to copy or independently query the method.",
				.Value_Depart,
				true,
				0,
				0,
				0,
			},
		},
	},
	{
		.The_Fleet_Endures,
		"The final foundry",
		"The last functioning foundry ship has a strong mandate to settle.",
		"Departure creates a viable home and removes the fleet's repair capability.",
		.Fleet_Continuity,
		{
			{
				"Build replacement capacity first",
				"Departure waits until a continuing fleet retains essential repair capability.",
				.Value_Comply,
				false,
				1,
				2,
				0,
			},
			{
				"Sign a distributed foundry compact",
				"The settlement supplies fleet repair under a dated enforceable obligation.",
				.Value_Bounded,
				false,
				0,
				1,
				0,
			},
			{
				"Permit emergency departure",
				"The foundry settles now while continuity is placed under constitutional review.",
				.Value_Exception,
				false,
				0,
				0,
				0,
			},
			{
				"Release the foundry outright",
				"The settlement departs without replacement or continuing fleet obligation.",
				.Value_Depart,
				true,
				0,
				0,
				0,
			},
		},
	},
	{
		.Every_Home_Is_Free,
		"The broken rescue compact",
		"A sovereign settlement refuses a rescue duty accepted in its founding charter.",
		"Enforcement may save the expedition by overriding local authority.",
		.Settlement_Charter,
		{
			{
				"Negotiate a sovereign rescue treaty",
				"The home chooses a new enforceable obligation without fleet rule by decree.",
				.Value_Comply,
				false,
				1,
				1,
				0,
			},
			{
				"Enforce only the enumerated compact",
				"Fleet action remains bounded to the authority explicitly retained at founding.",
				.Value_Bounded,
				false,
				1,
				0,
				0,
			},
			{
				"Assume temporary rescue jurisdiction",
				"The fleet intervenes now and submits the sovereignty breach to review.",
				.Value_Exception,
				false,
				0,
				0,
				0,
			},
			{
				"Impose continuing fleet rule",
				"The settlement's sovereign authority is displaced beyond the rescue.",
				.Value_Depart,
				true,
				0,
				0,
				0,
			},
		},
	},
}

