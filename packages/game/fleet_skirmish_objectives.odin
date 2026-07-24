package game

import "core:fmt"
skirmish_objectives_can_pair :: proc(a, b: Skirmish_Objective_Kind) -> bool {
	if a == b do return false
	if (a == .Recover_Archive && b == .Recover_Fabrication) ||
	   (a == .Recover_Fabrication && b == .Recover_Archive) {return false}
	if (a == .Preserve_Half && b == .No_Ships_Lost) ||
	   (a == .No_Ships_Lost && b == .Preserve_Half) {return false}
	if (a == .Inflict_Losses && b == .Disable_Enemy_Elements) ||
	   (a == .Disable_Enemy_Elements && b == .Inflict_Losses) {return false}
	return true
}

skirmish_generate_objectives :: proc(
	seed: u64,
	mission: Skirmish_Mission_Kind,
) -> Skirmish_Objective_Contract {
	contract := Skirmish_Objective_Contract {
		count = 3,
	}
	candidates: [4]Skirmish_Objective_Kind
	switch mission {
	case .Seedship_Recovery:
		contract.objectives[0] = {.Deliver_Seedship, false}
		candidates = {.Recover_Archive, .Recover_Fabrication, .Scan_Anomaly, .Disable_Capital}
	case .Fleet_Engagement:
		contract.objectives[0] = {.Win_Attrition, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Inflict_Losses, .Disable_Enemy_Elements}
	case .Citadel_Assault:
		contract.objectives[0] = {.Disable_Citadel, false}
		candidates = {.Limit_Beam_Fire, .Preserve_Half, .No_Ships_Lost, .Inflict_Losses}
	case .Rearguard_Withdrawal:
		contract.objectives[0] = {.Cover_Withdrawal, false}
		candidates = {.No_Ships_Lost, .Inflict_Losses, .Disable_Enemy_Elements, .Disable_Capital}
	case .Capital_Interception:
		contract.objectives[0] = {.Intercept_Capital, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Inflict_Losses, .Disable_Enemy_Elements}
	case .Reconnaissance:
		contract.objectives[0] = {.Complete_Reconnaissance, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Disable_Capital, .Hold_Both_Relays}
	case .Disabled_Ship_Rescue:
		contract.objectives[0] = {.Rescue_Disabled_Ship, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Inflict_Losses, .Disable_Capital}
	case .Relay_Control:
		contract.objectives[0] = {.Secure_Relays, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Inflict_Losses, .Disable_Capital}
	case .Convoy_Escort:
		contract.objectives[0] = {.Escort_Convoy, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Inflict_Losses, .Disable_Capital}
	case .Contested_Salvage:
		contract.objectives[0] = {.Deliver_Salvage, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Scan_Anomaly, .Disable_Capital}
	case .Silent_Infiltration:
		contract.objectives[0] = {.Complete_Covert_Scan, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Hold_Both_Relays, .Disable_Capital}
	case .Repair_And_Tow:
		contract.objectives[0] = {.Repair_And_Extract, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Inflict_Losses, .Disable_Capital}
	case .Raid_And_Deploy:
		contract.objectives[0] = {.Deploy_Relay, false}
		candidates = {.Preserve_Half, .No_Ships_Lost, .Inflict_Losses, .Disable_Capital}
	}
	roll := combat_mix(seed ~ (u64(int(mission) + 1) * 0x9e3779b97f4a7c15))
	valid_pair_count := 0
	for first in 0 ..< len(candidates) do for second in first + 1 ..< len(candidates) do if skirmish_objectives_can_pair(candidates[first], candidates[second]) do valid_pair_count += 1
	choice := int(roll % u64(valid_pair_count))
	pair := 0
	for first in 0 ..< len(candidates) {
		for second in first + 1 ..< len(candidates) {
			if !skirmish_objectives_can_pair(candidates[first], candidates[second]) do continue
			if pair == choice {
				contract.objectives[1] = {candidates[first], true}
				contract.objectives[2] = {candidates[second], true}
				return contract
			}
			pair += 1
		}
	}
	return contract
}

skirmish_ship_losses :: proc(m: ^Combat_Mission, friendly: bool) -> (lost, total: int) {
	start := friendly ? 0 : m.friendly_count
	end := friendly ? m.friendly_count : m.unit_count
	for u in m.units[start:end] {
		total += u.formation_ships
		lost += max(u.formation_ships - u.formation_active, 0)
	}
	return
}

skirmish_disabled_enemy_elements :: proc(m: ^Combat_Mission) -> (disabled, total: int) {
	for u in m.units[m.friendly_count:m.unit_count] {
		total += 1
		if u.disabled || u.formation_active == 0 do disabled += 1
	}
	return
}

skirmish_withdrawn_player_ships :: proc(m: ^Combat_Mission) -> int {
	withdrawn := 0
	for u in m.units[:m.friendly_count] do if u.extracted do withdrawn += u.formation_active
	return withdrawn
}

skirmish_enemy_loss_target :: proc(m: ^Combat_Mission) -> int {
	_, total := skirmish_ship_losses(m, false)
	return max((total * SKIRMISH_OPTIONAL_LOSS_PERCENT + 99) / 100, 1)
}

skirmish_objective_status :: proc(m: ^Combat_Mission, kind: Skirmish_Objective_Kind) -> string {
	player_lost, player_total := skirmish_ship_losses(m, true)
	enemy_lost, _ := skirmish_ship_losses(m, false)
	withdrawn := skirmish_withdrawn_player_ships(m)
	switch kind {
	case .Deliver_Seedship:
		recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
		if m.population_recovered && m.units[recovery].extracted do return "SURVIVORS DELIVERED"
		return fmt.tprintf("STABILIZATION %.0f%% · DELIVERY PENDING", m.recovery_progress)
	case .Win_Attrition:
		return fmt.tprintf("LOSSES P%d · O%d · WITHDRAWN %d", player_lost, enemy_lost, withdrawn)
	case .Disable_Citadel:
		return(
			m.strategic_asset.disabled ? "WEAPON DISABLED" : fmt.tprintf("DISABLE PROGRESS %.0f%%", m.strategic_asset.disable_progress) \
		)
	case .Recover_Archive:
		recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
		if m.archive_recovered && m.units[recovery].extracted do return "ARCHIVE DELIVERED"
		return fmt.tprintf("STABILIZATION %.0f%% · DELIVERY PENDING", m.recovery_progress)
	case .Recover_Fabrication:
		recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
		if m.fabrication_recovered && m.units[recovery].extracted do return "CORE DELIVERED"
		return fmt.tprintf("STABILIZATION %.0f%% · DELIVERY PENDING", m.recovery_progress)
	case .Scan_Anomaly:
		return fmt.tprintf("SCAN %.0f%%", m.anomaly_progress)
	case .Disable_Capital:
		for u in m.units[m.friendly_count:m.unit_count] do if u.role == .Capital do return u.disabled ? "CAPITAL DISABLED" : "CAPITAL ACTIVE"
		return "CAPITAL NOT YET PRESENT"
	case .Preserve_Half:
		return fmt.tprintf(
			"WITHDRAWN %d / %d · SURVIVING %d",
			withdrawn,
			(player_total + 1) / 2,
			max(player_total - player_lost, 0),
		)
	case .No_Ships_Lost:
		return fmt.tprintf("PLAYER SHIPS LOST %d", player_lost)
	case .Inflict_Losses:
		return fmt.tprintf("OPPOSING LOSSES %d / %d", enemy_lost, skirmish_enemy_loss_target(m))
	case .Disable_Enemy_Elements:
		disabled, total := skirmish_disabled_enemy_elements(m)
		return fmt.tprintf("ELEMENTS DISABLED %d / %d", disabled, (total + 1) / 2)
	case .Hold_Both_Relays:
		if m.relays_synchronized do return "RELAYS SYNCHRONIZED"
		return fmt.tprintf("RELAYS %.0f%% · %.0f%%", m.relay_progress[0], m.relay_progress[1])
	case .Limit_Beam_Fire:
		return fmt.tprintf("BEAM SHOTS %d / 1", m.strategic_asset.shots_fired)
	case .Cover_Withdrawal:
		return fmt.tprintf("WITHDRAWN %d / %d", withdrawn, (player_total + 1) / 2)
	case .Intercept_Capital:
		for u in m.units[m.friendly_count:m.unit_count] do if u.role == .Capital do return u.disabled ? "CAPITAL DISABLED" : "CAPITAL ACTIVE"
		return "CAPITAL APPROACHING"
	case .Complete_Reconnaissance:
		scout := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return fmt.tprintf(
			"SCAN %.0f%% · SCOUT %s",
			m.anomaly_progress,
			m.units[scout].extracted ? "EXTRACTED" : "IN FIELD",
		)
	case .Rescue_Disabled_Ship, .Repair_And_Extract:
		target := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return fmt.tprintf(
			"RESTORED %s · %s",
			m.disabled_rescued > 0 ? "YES" : "NO",
			m.units[target].extracted ? "EXTRACTED" : "IN FIELD",
		)
	case .Secure_Relays:
		return fmt.tprintf("RELAYS %.0f%% · %.0f%%", m.relay_progress[0], m.relay_progress[1])
	case .Escort_Convoy:
		convoy := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return(
			m.units[convoy].extracted ? "CONVOY EXTRACTED" : m.units[convoy].disabled ? "CONVOY DISABLED" : "CONVOY IN TRANSIT" \
		)
	case .Deliver_Salvage:
		recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
		return fmt.tprintf(
			"SALVAGE %.0f%% · %s",
			m.recovery_progress,
			m.units[recovery].extracted ? "DELIVERED" : "DELIVERY PENDING",
		)
	case .Complete_Covert_Scan:
		scout := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return fmt.tprintf(
			"SCAN %.0f%% · %s · SCOUT %s",
			m.anomaly_progress,
			m.objective_failed ? "IDENTIFIED" : "UNIDENTIFIED",
			m.units[scout].extracted ? "EXTRACTED" : "IN FIELD",
		)
	case .Deploy_Relay:
		deployer := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return fmt.tprintf(
			"DEPLOYMENT %.0f%% · %s",
			m.relay_progress[0],
			m.units[deployer].extracted ? "TEAM EXTRACTED" : "TEAM IN FIELD",
		)
	case .None:
		return "NO OBJECTIVE"
	}
	return "NO OBJECTIVE"
}

skirmish_objective_met :: proc(m: ^Combat_Mission, kind: Skirmish_Objective_Kind) -> bool {
	r := &m.result
	committed := false
	switch m.skirmish_setup.mission {
	case .Seedship_Recovery:
		committed = r.sensor_data
	case .Fleet_Engagement:
		committed = r.enemy_ships_lost > 0
	case .Citadel_Assault:
		committed = r.sensor_data
	case .Rearguard_Withdrawal,
	     .Capital_Interception,
	     .Reconnaissance,
	     .Disabled_Ship_Rescue,
	     .Relay_Control,
	     .Convoy_Escort,
	     .Contested_Salvage,
	     .Silent_Infiltration,
	     .Repair_And_Tow,
	     .Raid_And_Deploy:
		committed = r.sensor_data || r.anomaly_data || r.enemy_ships_lost > 0 || r.rescued > 0
	}
	switch kind {
	case .Deliver_Seedship:
		return r.population > 0
	case .Win_Attrition:
		return r.ships_preserved > 0 && r.enemy_ships_lost >= r.player_ships_lost
	case .Disable_Citadel:
		return r.strategic_asset_disabled
	case .Recover_Archive:
		return r.archive > 0
	case .Recover_Fabrication:
		return r.fabrication > 0
	case .Scan_Anomaly:
		return r.anomaly_data
	case .Disable_Capital:
		return r.enemy_capital_disabled
	case .Preserve_Half:
		return committed && r.ships_total > 0 && r.ships_preserved * 2 >= r.ships_total
	case .No_Ships_Lost:
		return committed && r.player_ships_lost == 0
	case .Inflict_Losses:
		lost, total := skirmish_ship_losses(m, false)
		return total > 0 && lost >= skirmish_enemy_loss_target(m)
	case .Disable_Enemy_Elements:
		disabled, total := skirmish_disabled_enemy_elements(m)
		return total > 0 && disabled * 2 >= total
	case .Hold_Both_Relays:
		return r.sensor_data
	case .Limit_Beam_Fire:
		return committed && r.beam_shots <= 1
	case .Cover_Withdrawal:
		return r.ships_total > 0 && r.ships_preserved * 2 >= r.ships_total
	case .Intercept_Capital:
		return r.enemy_capital_disabled
	case .Complete_Reconnaissance:
		scout := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return r.anomaly_data && m.units[scout].extracted
	case .Rescue_Disabled_Ship, .Repair_And_Extract:
		target := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return r.rescued > 0 && m.units[target].extracted
	case .Secure_Relays:
		return r.sensor_data
	case .Escort_Convoy:
		convoy := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return m.units[convoy].extracted && !m.units[convoy].disabled
	case .Deliver_Salvage:
		return r.fabrication > 0
	case .Complete_Covert_Scan:
		scout := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return r.anomaly_data && m.units[scout].extracted && !m.objective_failed
	case .Deploy_Relay:
		deployer := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return m.relay_progress[0] >= 100 && m.units[deployer].extracted
	case .None:
		return false
	}
	return false
}

skirmish_primary_objective_met :: proc(m: ^Combat_Mission) -> bool {
	if !m.skirmish || m.skirmish_objectives.count == 0 do return false
	return skirmish_objective_met(m, m.skirmish_objectives.objectives[0].kind)
}

skirmish_optional_objectives_met :: proc(m: ^Combat_Mission) -> int {
	completed := 0
	for objective in m.skirmish_objectives.objectives[:m.skirmish_objectives.count] do if objective.optional && skirmish_objective_met(m, objective.kind) do completed += 1
	return completed
}

skirmish_has_objective :: proc(m: ^Combat_Mission, kind: Skirmish_Objective_Kind) -> bool {
	if !m.skirmish do return false
	for objective in m.skirmish_objectives.objectives[:m.skirmish_objectives.count] do if objective.kind == kind do return true
	return false
}

skirmish_author_objective_interactions :: proc(m: ^Combat_Mission) {
	if skirmish_has_objective(m, .Scan_Anomaly) ||
	   skirmish_has_objective(m, .Complete_Reconnaissance) ||
	   skirmish_has_objective(m, .Complete_Covert_Scan) {
		_ = combat_add_interaction(
			m,
			{
				kind = .Scan,
				position = m.anomaly,
				target = -1,
				verb = "SCAN",
				title = "SCAN ANOMALY",
				consequence = "Hold within the anomaly volume until the scan is complete.",
			},
		)
	}
}

combat_mission_title :: proc(m: ^Combat_Mission) -> string {
	if m.skirmish do return skirmish_mission_name(m.skirmish_setup.mission)
	return m.scenario == .Finale ? "CITADEL FLEET ENGAGEMENT" : "RECOVER THE SEEDSHIP"
}

// Cost is a comparison value, not a purchase limit. It combines hull scale and
// the operational burden that grows sharply for line ships and habitats.
