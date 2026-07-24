package game

import "core:fmt"

SKIRMISH_LOADOUT_SLOTS :: 7
SKIRMISH_MIN_FACTIONS :: 2
SKIRMISH_MAX_FACTIONS :: 4
SKIRMISH_OPTIONAL_LOSS_PERCENT :: 10

Skirmish_Mission_Kind :: enum {
	Seedship_Recovery,
	Fleet_Engagement,
	Citadel_Assault,
	Rearguard_Withdrawal,
	Capital_Interception,
	Reconnaissance,
	Disabled_Ship_Rescue,
	Relay_Control,
	Convoy_Escort,
	Contested_Salvage,
	Silent_Infiltration,
	Repair_And_Tow,
	Raid_And_Deploy,
}

Skirmish_Objective_Pressure :: enum {
	Open_Approach,
	Picket_Screen,
}

Skirmish_Recovery_Profile :: enum {
	None,
	Clear_Approach,
	Picketed_Target,
	Drifting_Target,
	Heavy_Tow,
}

SKIRMISH_RECOVERY_PROFILE_COUNT :: 4

Skirmish_Infiltration_Cover :: enum {
	None,
	Objective_Shroud,
	Masked_Corridor,
}

Skirmish_Objective_Kind :: enum {
	None,
	Deliver_Seedship,
	Win_Attrition,
	Disable_Citadel,
	Recover_Archive,
	Recover_Fabrication,
	Scan_Anomaly,
	Disable_Capital,
	Preserve_Half,
	No_Ships_Lost,
	Inflict_Losses,
	Disable_Enemy_Elements,
	Hold_Both_Relays,
	Limit_Beam_Fire,
	Cover_Withdrawal,
	Intercept_Capital,
	Complete_Reconnaissance,
	Rescue_Disabled_Ship,
	Secure_Relays,
	Escort_Convoy,
	Deliver_Salvage,
	Complete_Covert_Scan,
	Repair_And_Extract,
	Deploy_Relay,
}

Skirmish_Objective :: struct {
	kind:     Skirmish_Objective_Kind,
	optional: bool,
}

Skirmish_Objective_Contract :: struct {
	objectives: [3]Skirmish_Objective,
	count:      int,
}

Skirmish_Loadout_Entry :: struct {
	archetype: Ship_Hull_Archetype,
	ships:     int,
}

Skirmish_Setup :: struct {
	seed:          u64,
	contract_seed: u64,
	faction_count: int,
	mission:       Skirmish_Mission_Kind,
	loadout:       [SKIRMISH_LOADOUT_SLOTS]Skirmish_Loadout_Entry,
}

SKIRMISH_ARCHETYPES :: [24]Ship_Hull_Archetype {
	.Scout,
	.Interceptor,
	.Fighter,
	.Strike_Fighter,
	.Bomber,
	.Assault_Shuttle,
	.Patrol_Boat,
	.Corvette,
	.Torpedo_Boat,
	.Gunship,
	.Picket_Frigate,
	.Combat_Frigate,
	.Support_Frigate,
	.Minelayer_Frigate,
	.Destroyer,
	.Light_Cruiser,
	.Heavy_Cruiser,
	.Battlecruiser,
	.Battleship,
	.Carrier,
	.Dreadnought,
	.Utility_Hull,
	.Transport_Hull,
	.Habitat_Hull,
}

skirmish_default_setup :: proc() -> Skirmish_Setup {
	return {
		seed = 0x5eed,
		contract_seed = 0x5eed,
		faction_count = 2,
		mission = .Seedship_Recovery,
		loadout = {
			{.Interceptor, 8},
			{.Fighter, 8},
			{.Bomber, 6},
			{.Gunship, 3},
			{.Utility_Hull, 1},
			{.Carrier, 1},
			{.Heavy_Cruiser, 1},
		},
	}
}

skirmish_reroll_objectives :: proc(setup: ^Skirmish_Setup) {
	if setup == nil do return
	current := skirmish_generate_objectives(setup.contract_seed, setup.mission)
	candidate := combat_mix(setup.contract_seed + 0x9e3779b97f4a7c15)
	for _ in 0 ..< 8 {
		if skirmish_generate_objectives(candidate, setup.mission) != current {
			setup.contract_seed = candidate
			return
		}
		candidate = combat_mix(candidate + 0x9e3779b97f4a7c15)
	}
	setup.contract_seed = candidate
}

skirmish_prepare_next_setup :: proc(previous: Skirmish_Setup, seed: u64) -> Skirmish_Setup {
	next := previous
	next.seed = max(seed, 1)
	next.contract_seed = combat_mix(next.seed + 0x6a09e667f3bcc909)
	previous_contract := skirmish_generate_objectives(previous.contract_seed, previous.mission)
	if skirmish_generate_objectives(next.contract_seed, next.mission) == previous_contract do skirmish_reroll_objectives(&next)
	return next
}

skirmish_mission_name :: proc(kind: Skirmish_Mission_Kind) -> string {
	switch kind {
	case .Seedship_Recovery:
		return "SEEDSHIP RECOVERY"
	case .Fleet_Engagement:
		return "FLEET ENGAGEMENT"
	case .Citadel_Assault:
		return "CITADEL ASSAULT"
	case .Rearguard_Withdrawal:
		return "REARGUARD WITHDRAWAL"
	case .Capital_Interception:
		return "CAPITAL INTERCEPTION"
	case .Reconnaissance:
		return "RECONNAISSANCE"
	case .Disabled_Ship_Rescue:
		return "DISABLED SHIP RESCUE"
	case .Relay_Control:
		return "RELAY CONTROL"
	case .Convoy_Escort:
		return "CONVOY ESCORT"
	case .Contested_Salvage:
		return "CONTESTED SALVAGE"
	case .Silent_Infiltration:
		return "SILENT INFILTRATION"
	case .Repair_And_Tow:
		return "REPAIR AND TOW"
	case .Raid_And_Deploy:
		return "RAID AND DEPLOY"
	}
	return "SKIRMISH"
}

skirmish_mission_description :: proc(kind: Skirmish_Mission_Kind) -> string {
	switch kind {
	case .Seedship_Recovery:
		return "Fix both relays, recover the seedship cargo, and reach extraction."
	case .Fleet_Engagement:
		return "Break the opposing formations while preserving enough ships to withdraw."
	case .Citadel_Assault:
		return "Control the relays, expose the citadel weapon, and disable it before withdrawal."
	case .Rearguard_Withdrawal:
		return(
			"Cover the fleet's disengagement and bring at least half its ships through extraction." \
		)
	case .Capital_Interception:
		return "Disable the opposing capital ship before the navigation window closes."
	case .Reconnaissance:
		return "Scan the anomaly and withdraw the assigned sensor element with its record."
	case .Disabled_Ship_Rescue:
		return "Restore the disabled command element and escort it to extraction."
	case .Relay_Control:
		return "Secure both command relays before withdrawing."
	case .Convoy_Escort:
		return "Guard the assigned convoy element and bring it through extraction."
	case .Contested_Salvage:
		return "Stabilize the wreck, recover its fabrication core, and deliver it."
	case .Silent_Infiltration:
		return "Scan the anomaly without allowing the assigned sensor element to be identified."
	case .Repair_And_Tow:
		return "Reach the disabled ship, restore it, and bring it through extraction."
	case .Raid_And_Deploy:
		return "Secure the forward relay and extract the element that established it."
	}
	return ""
}

skirmish_objective_name :: proc(kind: Skirmish_Objective_Kind) -> string {
	switch kind {
	case .Deliver_Seedship:
		return "DELIVER SEEDSHIP SURVIVORS"
	case .Win_Attrition:
		return "MATCH OR EXCEED LOSSES AND WITHDRAW"
	case .Disable_Citadel:
		return "DISABLE THE CITADEL WEAPON"
	case .Recover_Archive:
		return "RECOVER THE GENETIC ARCHIVE"
	case .Recover_Fabrication:
		return "RECOVER THE FABRICATION CORE"
	case .Scan_Anomaly:
		return "COMPLETE THE ANOMALY SCAN"
	case .Disable_Capital:
		return "DISABLE THE ENEMY CAPITAL"
	case .Preserve_Half:
		return "WITHDRAW HALF THE PLAYER FLEET"
	case .No_Ships_Lost:
		return "LOSE NO PLAYER SHIPS"
	case .Inflict_Losses:
		return "DISABLE 10% OF OPPOSING SHIPS"
	case .Disable_Enemy_Elements:
		return "BREAK HALF THE ENEMY ELEMENTS"
	case .Hold_Both_Relays:
		return "HOLD BOTH RELAYS"
	case .Limit_Beam_Fire:
		return "ALLOW AT MOST ONE BEAM SHOT"
	case .Cover_Withdrawal:
		return "WITHDRAW HALF THE PLAYER FLEET"
	case .Intercept_Capital:
		return "INTERCEPT THE ENEMY CAPITAL"
	case .Complete_Reconnaissance:
		return "COMPLETE SCAN AND EXTRACT SCOUT"
	case .Rescue_Disabled_Ship:
		return "RESCUE THE DISABLED ELEMENT"
	case .Secure_Relays:
		return "SECURE BOTH COMMAND RELAYS"
	case .Escort_Convoy:
		return "ESCORT THE CONVOY TO EXTRACTION"
	case .Deliver_Salvage:
		return "DELIVER THE FABRICATION SALVAGE"
	case .Complete_Covert_Scan:
		return "SCAN WITHOUT IDENTIFICATION"
	case .Repair_And_Extract:
		return "REPAIR AND EXTRACT THE DISABLED SHIP"
	case .Deploy_Relay:
		return "DEPLOY THE FORWARD RELAY"
	case .None:
		return "NO OBJECTIVE"
	}
	return "NO OBJECTIVE"
}

skirmish_objective_compatible :: proc(
	mission: Skirmish_Mission_Kind,
	kind: Skirmish_Objective_Kind,
) -> bool {
	switch mission {
	case .Seedship_Recovery:
		return(
			kind == .Deliver_Seedship ||
			kind == .Recover_Archive ||
			kind == .Recover_Fabrication ||
			kind == .Scan_Anomaly ||
			kind == .Disable_Capital \
		)
	case .Fleet_Engagement:
		return(
			kind == .Win_Attrition ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Inflict_Losses ||
			kind == .Disable_Enemy_Elements \
		)
	case .Citadel_Assault:
		return(
			kind == .Disable_Citadel ||
			kind == .Limit_Beam_Fire ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Inflict_Losses \
		)
	case .Rearguard_Withdrawal:
		return(
			kind == .Cover_Withdrawal ||
			kind == .No_Ships_Lost ||
			kind == .Inflict_Losses ||
			kind == .Disable_Enemy_Elements ||
			kind == .Disable_Capital \
		)
	case .Capital_Interception:
		return(
			kind == .Intercept_Capital ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Inflict_Losses ||
			kind == .Disable_Enemy_Elements \
		)
	case .Reconnaissance:
		return(
			kind == .Complete_Reconnaissance ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Disable_Capital ||
			kind == .Hold_Both_Relays \
		)
	case .Disabled_Ship_Rescue:
		return(
			kind == .Rescue_Disabled_Ship ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Inflict_Losses ||
			kind == .Disable_Capital \
		)
	case .Relay_Control:
		return(
			kind == .Secure_Relays ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Inflict_Losses ||
			kind == .Disable_Capital \
		)
	case .Convoy_Escort:
		return(
			kind == .Escort_Convoy ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Inflict_Losses ||
			kind == .Disable_Capital \
		)
	case .Contested_Salvage:
		return(
			kind == .Deliver_Salvage ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Scan_Anomaly ||
			kind == .Disable_Capital \
		)
	case .Silent_Infiltration:
		return(
			kind == .Complete_Covert_Scan ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Hold_Both_Relays ||
			kind == .Disable_Capital \
		)
	case .Repair_And_Tow:
		return(
			kind == .Repair_And_Extract ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Inflict_Losses ||
			kind == .Disable_Capital \
		)
	case .Raid_And_Deploy:
		return(
			kind == .Deploy_Relay ||
			kind == .Preserve_Half ||
			kind == .No_Ships_Lost ||
			kind == .Inflict_Losses ||
			kind == .Disable_Capital \
		)
	}
	return false
}
