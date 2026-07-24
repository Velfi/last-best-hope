package game_tests

import "core:fmt"
import "core:testing"

recovery_profile_seed :: proc(
	operation: Skirmish_Mission_Kind,
	profile: Skirmish_Recovery_Profile,
) -> u64 {
	for seed in u64(1) ..= 10000 do if skirmish_recovery_profile(seed, operation) == profile {
		return seed
	}
	return 0
}

@(test)
skirmish_generation_budget_matches_objective_workload :: proc(t: ^testing.T) {
	recovery := skirmish_generation_budget(.Seedship_Recovery)
	recon := skirmish_generation_budget(.Reconnaissance)
	salvage := skirmish_generation_budget(.Contested_Salvage)
	engagement := skirmish_generation_budget(.Fleet_Engagement)

	testing.expect(t, recovery.workload > engagement.workload)
	testing.expect(t, recon.workload > engagement.workload)
	testing.expect_value(t, salvage.workload, recovery.workload)
	testing.expect_value(t, recovery.max_factions, 2)
	testing.expect_value(t, recon.max_factions, 2)
	testing.expect_value(t, salvage.max_factions, 2)
	testing.expect_value(t, engagement.max_factions, 4)
	testing.expect(t, recovery.geometry_scale < engagement.geometry_scale)
	testing.expect(t, salvage.geometry_scale < engagement.geometry_scale)
}

@(test)
skirmish_generation_assigns_recovery_capability_to_recovery_contracts :: proc(
	t: ^testing.T,
) {
	recovery_operations := [?]Skirmish_Mission_Kind {
		.Seedship_Recovery,
		.Disabled_Ship_Rescue,
		.Convoy_Escort,
		.Contested_Salvage,
		.Repair_And_Tow,
	}
	for operation in recovery_operations {
		testing.expect_value(
			t,
			skirmish_operational_role_for_mission(.Utility_Hull, operation),
			Ship_Operational_Role.Recovery_Tug,
		)
	}
	testing.expect(
		t,
		skirmish_operational_role_for_mission(.Utility_Hull, .Fleet_Engagement) !=
			.Recovery_Tug,
	)
	testing.expect_value(
		t,
		skirmish_operational_role_for_mission(.Utility_Hull, .Raid_And_Deploy),
		Ship_Operational_Role.Courier,
	)
	testing.expect_value(
		t,
		skirmish_archetype_for_mission(.Interceptor, .Reconnaissance),
		Ship_Hull_Archetype.Scout,
	)
	incapable := skirmish_default_setup()
	incapable.mission = .Seedship_Recovery
	for &entry in incapable.loadout do entry = {.Fighter, 1}
	testing.expect(t, !skirmish_primary_capability_ready(&incapable))
}

@(test)
skirmish_recovery_profiles_are_deterministic_bounded_and_weighted :: proc(t: ^testing.T) {
	counts: [SKIRMISH_RECOVERY_PROFILE_COUNT]int
	for seed in u64(1) ..= 1000 {
		first := skirmish_recovery_profile(seed, .Seedship_Recovery)
		testing.expect_value(t, first, skirmish_recovery_profile(seed, .Seedship_Recovery))
		index := skirmish_recovery_profile_index(first)
		testing.expect(t, index >= 0 && index < len(counts))
		counts[index] += 1
		testing.expect_value(
			t,
			skirmish_recovery_profile(seed, .Fleet_Engagement),
			Skirmish_Recovery_Profile.None,
		)
	}
	// Broad bounds catch missing profiles or badly skewed hashing without
	// pinning the test to one exact hash histogram.
	testing.expect(t, counts[0] >= 180 && counts[0] <= 320)
	testing.expect(t, counts[1] >= 220 && counts[1] <= 380)
	testing.expect(t, counts[2] >= 180 && counts[2] <= 320)
	testing.expect(t, counts[3] >= 140 && counts[3] <= 280)
}

@(test)
skirmish_recovery_profiles_remain_within_the_mission_workload_budget :: proc(
	t: ^testing.T,
) {
	operations := [?]Skirmish_Mission_Kind {
		.Seedship_Recovery,
		.Disabled_Ship_Rescue,
		.Contested_Salvage,
		.Repair_And_Tow,
	}
	profiles := [?]Skirmish_Recovery_Profile {
		.Clear_Approach,
		.Picketed_Target,
		.Drifting_Target,
		.Heavy_Tow,
	}
	for operation in operations {
		for profile in profiles {
			seed := recovery_profile_seed(operation, profile)
			testing.expect(t, seed > 0)
			setup := skirmish_default_setup()
			setup.mission = operation
			setup.contract_seed = seed
			m := combat_new_skirmish_mission(9100 + seed, setup)
			testing.expect_value(t, m.skirmish_recovery_profile, profile)
			budget := skirmish_recovery_profile_budget(&m, profile)
			testing.expect(t, budget.capable)
			testing.expect(t, budget.viable)
			testing.expect(t, budget.total_seconds <= budget.limit_seconds)
			combat_mission_destroy(&m)
		}
	}
}

@(test)
skirmish_picketed_recovery_reassigns_existing_hostiles_to_the_target :: proc(
	t: ^testing.T,
) {
	setup := skirmish_default_setup()
	setup.mission = .Disabled_Ship_Rescue
	setup.contract_seed = recovery_profile_seed(setup.mission, .Picketed_Target)
	m := combat_new_skirmish_mission(9201, setup)
	defer combat_mission_destroy(&m)
	target := m.units[m.objective_unit].position
	nearby := 0
	for unit in m.units[m.friendly_count:m.unit_count] do if combat_distance(
		unit.position,
		target,
	) < 120 {
		nearby += 1
	}
	testing.expect_value(t, m.skirmish_recovery_profile, Skirmish_Recovery_Profile.Picketed_Target)
	testing.expect(t, nearby >= 2)
	testing.expect(t, !skirmish_recovery_target_secured(&m, target))
	for &unit in m.units[m.friendly_count:m.unit_count] do if !unit.disabled &&
	   combat_distance(unit.position, target) < 90 {
		unit.disabled = true
		break
	}
	testing.expect(t, skirmish_recovery_target_secured(&m, target))
}

@(test)
skirmish_drifting_recovery_target_and_interaction_move_together :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Repair_And_Tow
	setup.contract_seed = recovery_profile_seed(setup.mission, .Drifting_Target)
	m := combat_new_skirmish_mission(9202, setup)
	defer combat_mission_destroy(&m)
	target := m.objective_unit
	before := m.units[target].position
	combat_tick_fixed(&m, .05)
	after := m.units[target].position
	testing.expect_value(t, m.skirmish_recovery_profile, Skirmish_Recovery_Profile.Drifting_Target)
	testing.expect(t, after != before)
	found := false
	for interaction in m.interactions[:m.interaction_count] do if interaction.target == target {
		found = true
		testing.expect_value(t, interaction.position, after)
	}
	testing.expect(t, found)
}

@(test)
skirmish_heavy_tow_reduces_extraction_mobility_exactly_once :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Disabled_Ship_Rescue
	setup.contract_seed = recovery_profile_seed(setup.mission, .Heavy_Tow)
	m := combat_new_skirmish_mission(9203, setup)
	defer combat_mission_destroy(&m)
	recovery := m.recovery_unit
	target := m.objective_unit
	recovery_speed := m.units[recovery].speed
	target_speed := m.units[target].speed
	skirmish_apply_heavy_tow(&m, recovery, target)
	testing.expect(t, m.recovery_tow_slowed)
	testing.expect_value(t, m.units[recovery].speed, recovery_speed * .45)
	testing.expect_value(t, m.units[target].speed, target_speed * .45)
	skirmish_apply_heavy_tow(&m, recovery, target)
	testing.expect_value(t, m.units[recovery].speed, recovery_speed * .45)
	testing.expect_value(t, m.units[target].speed, target_speed * .45)
}

@(test)
skirmish_raid_and_deploy_assigns_the_generated_courier :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Raid_And_Deploy
	m := combat_new_skirmish_mission(8301, setup)
	defer combat_mission_destroy(&m)
	deployer := m.objective_unit

	testing.expect_value(t, m.units[deployer].operational_role, Ship_Operational_Role.Courier)
	testing.expect(t, .Cargo in combat_unit_modules(m.units[deployer]))
	testing.expect_value(t, deployer, skirmish_deployment_element(&m))
}

@(test)
skirmish_silent_infiltration_legacy_requests_normalize_to_reconnaissance :: proc(
	t: ^testing.T,
) {
	setup := skirmish_default_setup()
	setup.mission = .Silent_Infiltration
	m := combat_new_skirmish_mission(8302, setup)
	defer combat_mission_destroy(&m)

	testing.expect_value(t, m.skirmish_setup.mission, Skirmish_Mission_Kind.Reconnaissance)
	testing.expect_value(t, m.skirmish_infiltration_cover, Skirmish_Infiltration_Cover.None)
	testing.expect(t, skirmish_has_objective(&m, .Complete_Reconnaissance))
	testing.expect(t, !skirmish_has_objective(&m, .Complete_Covert_Scan))
}

@(test)
skirmish_objective_pressure_is_deterministic_and_varies_across_contracts :: proc(
	t: ^testing.T,
) {
	open, screened := 0, 0
	for seed in u64(1) ..= 60 {
		first := skirmish_objective_pressure(.Reconnaissance, seed)
		testing.expect_value(t, first, skirmish_objective_pressure(.Reconnaissance, seed))
		if first == .Picket_Screen {
			screened += 1
		} else {
			open += 1
		}
		testing.expect_value(
			t,
			skirmish_objective_pressure(.Fleet_Engagement, seed),
			Skirmish_Objective_Pressure.Open_Approach,
		)
	}
	testing.expect(t, open > 0)
	testing.expect(t, screened > 0)
	testing.expect(t, screened < 30)
}

@(test)
skirmish_screened_reconnaissance_places_a_real_picket_at_the_anomaly :: proc(
	t: ^testing.T,
) {
	contract_seed: u64
	for seed in u64(1) ..= 100 do if skirmish_objective_pressure(
		.Reconnaissance,
		seed,
	) == .Picket_Screen {
		contract_seed = seed
		break
	}
	testing.expect(t, contract_seed > 0)
	setup := skirmish_default_setup()
	setup.mission = .Reconnaissance
	setup.contract_seed = contract_seed
	m := combat_new_skirmish_mission(8201, setup)
	defer combat_mission_destroy(&m)

	testing.expect_value(t, m.skirmish_objective_pressure, Skirmish_Objective_Pressure.Picket_Screen)
	testing.expect_value(t, m.raider_groups[1].objective, Combat_Order.Control)
	testing.expect_value(t, m.raider_groups[1].destination, m.anomaly)
	pickets := 0
	for unit in m.units[m.friendly_count:m.unit_count] do if unit.group == 1 {
		pickets += 1
		testing.expect(t, combat_distance(unit.position, m.anomaly) < 150)
	}
	testing.expect(t, pickets > 0)
}

@(test)
skirmish_screened_recovery_places_pickets_at_the_authored_wreck :: proc(
	t: ^testing.T,
) {
	contract_seed: u64
	for seed in u64(1) ..= 100 do if skirmish_objective_pressure(
		.Contested_Salvage,
		seed,
	) == .Picket_Screen {
		contract_seed = seed
		break
	}
	testing.expect(t, contract_seed > 0)
	setup := skirmish_default_setup()
	setup.mission = .Contested_Salvage
	setup.contract_seed = contract_seed
	m := combat_new_skirmish_mission(8202, setup)
	defer combat_mission_destroy(&m)

	testing.expect_value(t, m.skirmish_objective_pressure, Skirmish_Objective_Pressure.Picket_Screen)
	testing.expect_value(t, m.raider_groups[1].destination, m.seedship)
	pickets := 0
	for unit in m.units[m.friendly_count:m.unit_count] do if unit.group == 1 {
		pickets += 1
		testing.expect(t, combat_distance(unit.position, m.seedship) < 150)
	}
	testing.expect(t, pickets > 0)
}

@(test)
skirmish_generation_caps_opposition_for_multi_stage_objectives :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.faction_count = 4
	setup.mission = .Seedship_Recovery
	recovery := combat_new_skirmish_mission(4001, setup)
	defer combat_mission_destroy(&recovery)
	testing.expect_value(t, recovery.skirmish_setup.faction_count, 2)

	setup.mission = .Fleet_Engagement
	engagement := combat_new_skirmish_mission(4001, setup)
	defer combat_mission_destroy(&engagement)
	testing.expect_value(t, engagement.skirmish_setup.faction_count, 4)
}

@(test)
skirmish_generation_shortens_high_workload_routes :: proc(t: ^testing.T) {
	seed := u64(4002)
	base := combat_new_mission(seed)
	defer combat_mission_destroy(&base)
	setup := skirmish_default_setup()
	setup.seed = seed
	setup.mission = .Seedship_Recovery
	recovery := combat_new_skirmish_mission(seed, setup)
	defer combat_mission_destroy(&recovery)

	base_distance := combat_distance(base.units[0].position, base.relays[0])
	budgeted_distance := combat_distance(recovery.units[0].position, recovery.relays[0])
	testing.expect(t, budgeted_distance < base_distance)
}

@(test)
combat_reassigns_disabled_recovery_specialist :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Reconnaissance
	m := combat_new_skirmish_mission(4003, setup)
	defer combat_mission_destroy(&m)
	previous := m.recovery_unit
	m.units[previous].disabled = true

	combat_tick_fixed(&m, .05)

	testing.expect(t, !m.complete)
	testing.expect(t, m.recovery_unit != previous)
	testing.expect(t, !m.units[m.recovery_unit].disabled)
}

@(test)
combat_recovery_reassignment_preserves_objective_progress :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Seedship_Recovery
	m := combat_new_skirmish_mission(4004, setup)
	defer combat_mission_destroy(&m)
	previous := m.recovery_unit
	m.recovery_progress = 50
	m.units[previous].disabled = true

	combat_tick_fixed(&m, .05)

	testing.expect(t, !m.complete)
	testing.expect(t, m.recovery_unit != previous)
	testing.expect_value(t, m.recovery_progress, f32(50))
}

@(test)
skirmish_reconnaissance_equips_bounded_probes :: proc(
	t: ^testing.T,
) {
	recon_setup := skirmish_default_setup()
	recon_setup.mission = .Reconnaissance
	recon := combat_new_skirmish_mission(8101, recon_setup)
	defer combat_mission_destroy(&recon)
	recon_probes := 0
	for unit in recon.units[:recon.friendly_count] do recon_probes += unit.recon_probes
	testing.expect(t, recon_probes > 0)
	testing.expect(t, recon_probes <= recon.friendly_count)
}

@(test)
recon_probe_completes_a_favorable_scan_and_consumes_the_launcher_store :: proc(
	t: ^testing.T,
) {
	setup := skirmish_default_setup()
	setup.mission = .Reconnaissance
	m := combat_new_skirmish_mission(8102, setup)
	defer combat_mission_destroy(&m)
	launcher := m.objective_unit
	before := m.units[launcher].recon_probes
	for &unit in m.units[m.friendly_count:m.unit_count] do unit.disabled = true

	testing.expect(t, combat_launch_recon_probe(&m, launcher, m.anomaly))
	testing.expect_value(t, m.units[launcher].recon_probes, before - 1)
	for m.recon_probe.status != .Complete && m.time < 300 {
		combat_update_recon_probe(&m, .05)
		m.time += .05
	}

	testing.expect_value(t, m.recon_probe.status, Combat_Recon_Probe_Status.Complete)
	testing.expect_value(t, m.anomaly_progress, f32(100))
	testing.expect(t, !combat_launch_recon_probe(&m, launcher, m.anomaly))
}

@(test)
recon_probe_can_be_detected_and_destroyed_before_completing_the_scan :: proc(
	t: ^testing.T,
) {
	setup := skirmish_default_setup()
	setup.mission = .Reconnaissance
	m := combat_new_skirmish_mission(8103, setup)
	defer combat_mission_destroy(&m)
	launcher := m.objective_unit
	destination := m.units[launcher].position
	testing.expect(t, combat_launch_recon_probe(&m, launcher, destination))
	for &unit in m.units[m.friendly_count:m.unit_count] do unit.position = destination

	for m.recon_probe.status != .Destroyed && m.time < 30 {
		combat_update_recon_probe(&m, .05)
		m.time += .05
	}

	testing.expect(t, m.recon_probe.detected)
	testing.expect_value(t, m.recon_probe.status, Combat_Recon_Probe_Status.Destroyed)
	testing.expect(t, m.anomaly_progress < 100)
}

@(test)
generated_picket_screen_can_destroy_a_recon_probe :: proc(t: ^testing.T) {
	contract_seed: u64
	for seed in u64(1) ..= 100 do if skirmish_objective_pressure(
		.Reconnaissance,
		seed,
	) == .Picket_Screen {
		contract_seed = seed
		break
	}
	setup := skirmish_default_setup()
	setup.mission = .Reconnaissance
	setup.contract_seed = contract_seed
	m := combat_new_skirmish_mission(8203, setup)
	defer combat_mission_destroy(&m)
	launcher := m.objective_unit
	testing.expect(t, combat_launch_recon_probe(&m, launcher, m.anomaly))

	for m.recon_probe.status != .Destroyed &&
	    m.recon_probe.status != .Complete &&
	    m.time < 120 {
		combat_update_recon_probe(&m, .05)
		m.time += .05
	}

	testing.expect_value(t, m.recon_probe.status, Combat_Recon_Probe_Status.Destroyed)
	testing.expect_value(t, m.recon_probes_lost, 1)
}

@(test)
skirmish_cost_is_visible_without_restricting_composition :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	base := skirmish_loadout_cost(&setup)
	setup.loadout[0] = {.Dreadnought, 99}
	testing.expect(t, skirmish_loadout_cost(&setup) > base)
	testing.expect_value(t, skirmish_loadout_ship_count(&setup), 119)
}

@(test)
skirmish_generation_is_seeded_and_applies_loadout :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.faction_count = 4
	setup.loadout[0] = {.Battleship, 3}
	a := combat_new_skirmish_mission(404, setup); defer combat_mission_destroy(&a)
	b := combat_new_skirmish_mission(404, setup); defer combat_mission_destroy(&b)
	testing.expect_value(t, a.units[0].hull_archetype, Ship_Hull_Archetype.Battleship)
	testing.expect_value(t, a.units[0].formation_ships, 3)
	testing.expect_value(t, a.ship_count, b.ship_count)
	testing.expect_value(
		t,
		a.units[a.friendly_count].formation_ships,
		b.units[b.friendly_count].formation_ships,
	)
}

@(test)
skirmish_recovery_assignment_follows_capable_loadout :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	for &entry in setup.loadout do entry = {.Dreadnought, 1}
	baseline_rate := skirmish_recovery_loadout_rate(&setup)
	setup.loadout[2] = {.Utility_Hull, 1}
	testing.expect_value(t, skirmish_recovery_loadout_index(&setup), 2)
	testing.expect(t, skirmish_recovery_loadout_rate(&setup) > baseline_rate)
	m := combat_new_skirmish_mission(406, setup)
	defer combat_mission_destroy(&m)
	testing.expect_value(t, m.recovery_unit, 2)
}

@(test)
skirmish_recovery_uses_the_assigned_element :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	for &entry in setup.loadout do entry = {.Dreadnought, 1}
	setup.loadout[2] = {.Utility_Hull, 1}
	m := combat_new_skirmish_mission(407, setup)
	defer combat_mission_destroy(&m)
	testing.expect_value(t, m.recovery_unit, 2)
	m.seedship_found = true
	m.phase = .Recovery
	m.units[m.recovery_unit].position = m.seedship
	m.units[m.recovery_unit].order = .Recover
	m.units[4].disabled = true
	m.units[4].hull = 0
	combat_tick_fixed(&m, .05)
	testing.expect(t, !m.complete)
	testing.expect(t, m.recovery_progress > 0)
}

@(test)
skirmish_citadel_requires_and_accepts_torpedo_capability :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Citadel_Assault
	for &entry in setup.loadout do entry = {.Dreadnought, 1}
	testing.expect_value(t, skirmish_citadel_strike_loadout_index(&setup), -1)
	testing.expect(t, !skirmish_primary_capability_ready(&setup))

	setup.loadout[2] = {.Torpedo_Boat, 1}
	testing.expect_value(t, skirmish_citadel_strike_loadout_index(&setup), 2)
	testing.expect(t, skirmish_primary_capability_ready(&setup))
	m := combat_new_skirmish_mission(408, setup)
	defer combat_mission_destroy(&m)
	testing.expect(t, .Torpedoes in combat_unit_modules(m.units[2]))
	m.units[2].position = m.strategic_asset.position
	m.strategic_asset.exposure_remaining = 1
	combat_finale_update(&m, .05)
	testing.expect(t, m.strategic_asset.disable_progress > 0)
}

@(test)
skirmish_scan_assignment_rewards_sensor_capability :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	for &entry in setup.loadout do entry = {.Dreadnought, 1}
	baseline_rate := skirmish_scan_loadout_rate(&setup)
	setup.loadout[3] = {.Scout, 1}
	testing.expect_value(t, skirmish_scan_loadout_index(&setup), 3)
	testing.expect(t, skirmish_scan_loadout_rate(&setup) > baseline_rate)
}

@(test)
skirmish_fleet_engagement_has_a_distinct_objective_loop :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Fleet_Engagement
	m := combat_new_skirmish_mission(405, setup)
	defer combat_mission_destroy(&m)
	testing.expect(t, combat_is_fleet_engagement(&m))
	testing.expect_value(t, m.interaction_count, 0)
	testing.expect_value(t, m.phase, Combat_Phase.Capital_Contact)
	for u in m.units[:m.friendly_count] {
		testing.expect_value(t, u.order, Combat_Order.Attack)
		testing.expect(t, u.target >= m.friendly_count && u.target < m.unit_count)
	}
}

@(test)
skirmish_objective_contracts_are_seeded_distinct_and_compatible :: proc(t: ^testing.T) {
	for mission in Skirmish_Mission_Kind {
		a := skirmish_generate_objectives(901, mission)
		b := skirmish_generate_objectives(901, mission)
		testing.expect(t, a == b)
		testing.expect_value(t, a.count, 3)
		testing.expect(t, !a.objectives[0].optional)
		testing.expect(t, a.objectives[1].optional && a.objectives[2].optional)
		testing.expect(t, a.objectives[1].kind != a.objectives[2].kind)
		switch mission {
		case .Seedship_Recovery:
			testing.expect_value(t, a.objectives[0].kind, Skirmish_Objective_Kind.Deliver_Seedship)
		case .Fleet_Engagement:
			testing.expect_value(t, a.objectives[0].kind, Skirmish_Objective_Kind.Win_Attrition)
		case .Citadel_Assault:
			testing.expect_value(t, a.objectives[0].kind, Skirmish_Objective_Kind.Disable_Citadel)
		case .Rearguard_Withdrawal:
			testing.expect_value(t, a.objectives[0].kind, Skirmish_Objective_Kind.Cover_Withdrawal)
		case .Capital_Interception:
			testing.expect_value(
				t,
				a.objectives[0].kind,
				Skirmish_Objective_Kind.Intercept_Capital,
			)
		case .Reconnaissance:
			testing.expect_value(
				t,
				a.objectives[0].kind,
				Skirmish_Objective_Kind.Complete_Reconnaissance,
			)
		case .Disabled_Ship_Rescue:
			testing.expect_value(
				t,
				a.objectives[0].kind,
				Skirmish_Objective_Kind.Rescue_Disabled_Ship,
			)
		case .Relay_Control:
			testing.expect_value(t, a.objectives[0].kind, Skirmish_Objective_Kind.Secure_Relays)
		case .Convoy_Escort:
			testing.expect_value(t, a.objectives[0].kind, Skirmish_Objective_Kind.Escort_Convoy)
		case .Contested_Salvage:
			testing.expect_value(t, a.objectives[0].kind, Skirmish_Objective_Kind.Deliver_Salvage)
		case .Silent_Infiltration:
			testing.expect_value(
				t,
				a.objectives[0].kind,
				Skirmish_Objective_Kind.Complete_Covert_Scan,
			)
		case .Repair_And_Tow:
			testing.expect_value(
				t,
				a.objectives[0].kind,
				Skirmish_Objective_Kind.Repair_And_Extract,
			)
		case .Raid_And_Deploy:
			testing.expect_value(t, a.objectives[0].kind, Skirmish_Objective_Kind.Deploy_Relay)
		}
		for objective in a.objectives[:a.count] do testing.expect(t, skirmish_objective_compatible(mission, objective.kind))
	}
}

@(test)
skirmish_generated_contracts_remain_compatible_across_seeds :: proc(t: ^testing.T) {
	for mission in Skirmish_Mission_Kind do for seed in u64(1) ..= 256 {
		contract := skirmish_generate_objectives(seed, mission)
		for objective in contract.objectives[:contract.count] do testing.expect(t, skirmish_objective_compatible(mission, objective.kind))
		testing.expect(t, skirmish_objectives_can_pair(contract.objectives[1].kind, contract.objectives[2].kind))
	}
}

@(test)
skirmish_contracts_reject_nested_optional_objectives :: proc(t: ^testing.T) {
	testing.expect(t, !skirmish_objectives_can_pair(.Recover_Archive, .Recover_Fabrication))
	testing.expect(t, !skirmish_objectives_can_pair(.Preserve_Half, .No_Ships_Lost))
	testing.expect(t, !skirmish_objectives_can_pair(.Inflict_Losses, .Disable_Enemy_Elements))
	seen_beam_limit := false
	for seed in u64(1) ..= 64 {
		contract := skirmish_generate_objectives(seed, .Citadel_Assault)
		for objective in contract.objectives[:contract.count] {
			testing.expect(t, objective.kind != .Hold_Both_Relays)
			if objective.kind == .Limit_Beam_Fire do seen_beam_limit = true
		}
	}
	testing.expect(t, seen_beam_limit)
}

@(test)
skirmish_survival_objectives_require_mission_commitment :: proc(t: ^testing.T) {
	m := Combat_Mission {
		skirmish = true,
	}
	m.skirmish_setup.mission = .Fleet_Engagement
	m.result = {
		ships_total     = 10,
		ships_preserved = 10,
	}
	testing.expect(t, !skirmish_objective_met(&m, .Preserve_Half))
	testing.expect(t, !skirmish_objective_met(&m, .No_Ships_Lost))
	m.result.enemy_ships_lost = 1
	testing.expect(t, skirmish_objective_met(&m, .Preserve_Half))
	testing.expect(t, skirmish_objective_met(&m, .No_Ships_Lost))

	m.skirmish_setup.mission = .Citadel_Assault
	m.result.enemy_ships_lost = 0
	m.result.beam_shots = 1
	testing.expect(t, !skirmish_objective_met(&m, .Limit_Beam_Fire))
	m.result.sensor_data = true
	testing.expect(t, skirmish_objective_met(&m, .Limit_Beam_Fire))
	m.result.beam_shots = 2
	testing.expect(t, !skirmish_objective_met(&m, .Limit_Beam_Fire))
}

@(test)
skirmish_objective_generation_varies_across_seeds :: proc(t: ^testing.T) {
	seen: [16]bool
	variety := 0
	for seed in u64(1) ..= 64 {
		contract := skirmish_generate_objectives(seed, .Seedship_Recovery)
		pair :=
			(int(contract.objectives[1].kind) * 4 + int(contract.objectives[2].kind)) % len(seen)
		if !seen[pair] {seen[pair] = true; variety += 1}
	}
	testing.expect(t, variety >= 4)
}

@(test)
skirmish_outcome_reads_the_generated_primary_objective :: proc(t: ^testing.T) {
	m := Combat_Mission {
		skirmish = true,
	}
	m.skirmish_objectives.count = 1
	m.skirmish_objectives.objectives[0] = {.Win_Attrition, false}
	m.result = {
		ships_total       = 10,
		ships_preserved   = 5,
		player_ships_lost = 2,
		enemy_ships_lost  = 3,
	}
	testing.expect_value(t, combat_result_outcome(&m), Combat_Outcome.Victory)
	m.result.enemy_ships_lost = 2
	testing.expect_value(t, combat_result_outcome(&m), Combat_Outcome.Victory)
	m.result.enemy_ships_lost = 1
	testing.expect_value(t, combat_result_outcome(&m), Combat_Outcome.Partial_Success)
	m.result.ships_preserved = 0
	testing.expect_value(t, combat_result_outcome(&m), Combat_Outcome.Defeat)
}

@(test)
skirmish_live_objective_status_reads_authoritative_losses :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Fleet_Engagement
	m := combat_new_skirmish_mission(906, setup)
	defer combat_mission_destroy(&m)
	m.units[0].formation_active -= 1
	m.units[m.friendly_count].formation_active = 0
	m.units[m.friendly_count].disabled = true
	testing.expect(
		t,
		skirmish_objective_status(&m, .Win_Attrition) == "LOSSES P1 · O1 · WITHDRAWN 0",
	)
	m.units[0].extracted = true
	withdrawn := m.units[0].formation_active
	_, player_total := skirmish_ship_losses(&m, true)
	testing.expect(
		t,
		skirmish_objective_status(&m, .Win_Attrition) ==
		fmt.tprintf("LOSSES P1 · O1 · WITHDRAWN %d", withdrawn),
	)
	testing.expect(
		t,
		skirmish_objective_status(&m, .Preserve_Half) ==
		fmt.tprintf(
			"WITHDRAWN %d / %d · SURVIVING %d",
			withdrawn,
			(player_total + 1) / 2,
			player_total - 1,
		),
	)
	target := (m.unit_count - m.friendly_count + 1) / 2
	testing.expect(
		t,
		skirmish_objective_status(&m, .Disable_Enemy_Elements) ==
		fmt.tprintf("ELEMENTS DISABLED 1 / %d", target),
	)
}

@(test)
skirmish_proportional_loss_objective_scales_and_resolves_at_threshold :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Fleet_Engagement
	two_factions := combat_new_skirmish_mission(908, setup)
	defer combat_mission_destroy(&two_factions)
	two_target := skirmish_enemy_loss_target(&two_factions)

	setup.faction_count = 4
	four_factions := combat_new_skirmish_mission(908, setup)
	defer combat_mission_destroy(&four_factions)
	four_target := skirmish_enemy_loss_target(&four_factions)
	testing.expect(t, four_target > two_target)

	remaining := two_target - 1
	for &u in two_factions.units[two_factions.friendly_count:two_factions.unit_count] {
		lost := min(remaining, u.formation_active)
		u.formation_active -= lost
		remaining -= lost
		if remaining == 0 do break
	}
	testing.expect(t, !skirmish_objective_met(&two_factions, .Inflict_Losses))
	testing.expect(
		t,
		skirmish_objective_status(&two_factions, .Inflict_Losses) ==
		fmt.tprintf("OPPOSING LOSSES %d / %d", two_target - 1, two_target),
	)
	for &u in two_factions.units[two_factions.friendly_count:two_factions.unit_count] do if u.formation_active > 0 {u.formation_active -= 1; break}
	testing.expect(t, skirmish_objective_met(&two_factions, .Inflict_Losses))
	testing.expect(
		t,
		skirmish_objective_status(&two_factions, .Inflict_Losses) ==
		fmt.tprintf("OPPOSING LOSSES %d / %d", two_target, two_target),
	)
}

@(test)
skirmish_citadel_relay_objective_survives_exposure_transition :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Citadel_Assault
	m := combat_new_skirmish_mission(907, setup)
	defer combat_mission_destroy(&m)
	m.relay_progress = {100, 100}
	combat_finale_update(&m, .05)
	testing.expect(t, m.relays_synchronized)
	testing.expect_value(t, m.relay_progress, [2]f32{})
	combat_finish(&m)
	testing.expect(t, m.result.sensor_data)
	testing.expect(t, skirmish_objective_met(&m, .Hold_Both_Relays))
}

@(test)
skirmish_scan_objective_authors_and_gates_its_interaction :: proc(t: ^testing.T) {
	scan_seed, plain_seed: u64
	for seed in u64(1) ..= 128 {
		contract := skirmish_generate_objectives(seed, .Seedship_Recovery)
		has_scan := false
		for objective in contract.objectives[:contract.count] do if objective.kind == .Scan_Anomaly do has_scan = true
		if has_scan && scan_seed == 0 do scan_seed = seed
		if !has_scan && plain_seed == 0 do plain_seed = seed
	}
	testing.expect(t, scan_seed != 0 && plain_seed != 0)
	setup := skirmish_default_setup()
	setup.contract_seed = scan_seed
	with_scan := combat_new_skirmish_mission(scan_seed, setup)
	defer combat_mission_destroy(&with_scan)
	scan_interaction := -1
	for interaction, i in with_scan.interactions[:with_scan.interaction_count] do if interaction.kind == .Scan do scan_interaction = i
	testing.expect(t, scan_interaction >= 0)
	testing.expect(t, combat_interaction_available(&with_scan, scan_interaction))
	with_scan.units[0].position = with_scan.anomaly
	combat_issue_interaction(&with_scan, 0, .Scan, with_scan.anomaly)
	combat_tick_fixed(&with_scan, .05)
	testing.expect(t, with_scan.anomaly_progress > 0)
	scanner := skirmish_scan_loadout_index(&setup)
	for &u in with_scan.units[:with_scan.friendly_count] do u.position = {1000, 1000, 1000}
	with_scan.units[scanner].position = with_scan.anomaly
	with_scan.anomaly_progress = 0
	combat_tick_fixed(&with_scan, .05)
	single_progress := with_scan.anomaly_progress
	for &u in with_scan.units[:with_scan.friendly_count] do u.position = with_scan.anomaly
	with_scan.anomaly_progress = 0
	combat_tick_fixed(&with_scan, .05)
	testing.expect_value(t, with_scan.anomaly_progress, single_progress)
	with_scan.anomaly_progress = 100
	testing.expect(t, !combat_interaction_available(&with_scan, scan_interaction))

	setup.contract_seed = plain_seed
	without_scan := combat_new_skirmish_mission(plain_seed, setup)
	defer combat_mission_destroy(&without_scan)
	for interaction in without_scan.interactions[:without_scan.interaction_count] do testing.expect(t, interaction.kind != .Scan)
	without_scan.units[0].position = without_scan.anomaly
	combat_tick_fixed(&without_scan, .05)
	testing.expect_value(t, without_scan.anomaly_progress, f32(0))
}

@(test)
skirmish_setup_previews_the_launched_contract_and_rerolls_deterministically :: proc(
	t: ^testing.T,
) {
	a := skirmish_default_setup()
	b := skirmish_default_setup()
	preview := skirmish_generate_objectives(a.contract_seed, a.mission)
	m := combat_new_skirmish_mission(a.seed, a)
	defer combat_mission_destroy(&m)
	testing.expect(t, m.skirmish_objectives == preview)
	skirmish_reroll_objectives(&a)
	skirmish_reroll_objectives(&b)
	testing.expect(t, a == b)
	testing.expect_value(t, a.seed, m.seed)
	testing.expect(t, a.contract_seed != m.skirmish_setup.contract_seed)
	testing.expect(t, skirmish_generate_objectives(a.contract_seed, a.mission) != preview)
	rerolled := combat_new_skirmish_mission(a.seed, a)
	defer combat_mission_destroy(&rerolled)
	rerolled_repeat := combat_new_skirmish_mission(b.seed, b)
	defer combat_mission_destroy(&rerolled_repeat)
	testing.expect_value(t, rerolled.relays, m.relays)
	testing.expect_value(t, rerolled.seedship, m.seedship)
	testing.expect_value(t, rerolled.anomaly, m.anomaly)
	testing.expect_value(t, rerolled.unit_count, m.unit_count)
	for u, i in rerolled.units[:rerolled.unit_count] do testing.expect_value(t, u.position, rerolled_repeat.units[i].position)
	testing.expect(t, rerolled.skirmish_objectives != m.skirmish_objectives)
}

@(test)
skirmish_next_operation_preserves_configuration_and_changes_contract :: proc(t: ^testing.T) {
	previous := skirmish_default_setup()
	previous.faction_count = 4
	previous.mission = .Fleet_Engagement
	previous.loadout[0] = {.Dreadnought, 7}
	previous_contract := skirmish_generate_objectives(previous.contract_seed, previous.mission)
	next := skirmish_prepare_next_setup(previous, previous.seed + 1)
	testing.expect_value(t, next.faction_count, previous.faction_count)
	testing.expect_value(t, next.mission, previous.mission)
	testing.expect_value(t, next.loadout, previous.loadout)
	testing.expect(t, next.seed != previous.seed)
	testing.expect(t, next.contract_seed != previous.contract_seed)
	testing.expect(
		t,
		skirmish_generate_objectives(next.contract_seed, next.mission) != previous_contract,
	)
}

@(test)
skirmish_new_mission_families_author_distinct_battlefield_rules :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()

	setup.mission = .Rearguard_Withdrawal
	rearguard := combat_new_skirmish_mission(1201, setup)
	defer combat_mission_destroy(&rearguard)
	testing.expect(t, combat_is_direct_engagement(&rearguard))
	testing.expect_value(t, rearguard.phase, Combat_Phase.Extraction)
	testing.expect(t, !rearguard.extraction_mandatory)
	for u in rearguard.units[:rearguard.friendly_count] do testing.expect_value(t, u.order, Combat_Order.Extract)

	setup.mission = .Reconnaissance
	recon := combat_new_skirmish_mission(1202, setup)
	defer combat_mission_destroy(&recon)
	testing.expect(t, skirmish_has_objective(&recon, .Complete_Reconnaissance))
	scan_found := false
	for interaction in recon.interactions[:recon.interaction_count] do if interaction.kind == .Scan do scan_found = true
	testing.expect(t, scan_found)

	setup.mission = .Disabled_Ship_Rescue
	rescue := combat_new_skirmish_mission(1203, setup)
	defer combat_mission_destroy(&rescue)
	testing.expect(t, rescue.objective_unit != rescue.recovery_unit)
	testing.expect(t, rescue.units[rescue.objective_unit].disabled)
	testing.expect_value(t, rescue.interactions[0].kind, Combat_Interaction_Kind.Rescue)

	setup.mission = .Convoy_Escort
	escort := combat_new_skirmish_mission(1204, setup)
	defer combat_mission_destroy(&escort)
	testing.expect_value(t, escort.units[escort.objective_unit].order, Combat_Order.Extract)
	testing.expect_value(t, escort.interactions[0].kind, Combat_Interaction_Kind.Escort)

	setup.mission = .Raid_And_Deploy
	deploy := combat_new_skirmish_mission(1205, setup)
	defer combat_mission_destroy(&deploy)
	testing.expect_value(t, deploy.interactions[0].kind, Combat_Interaction_Kind.Deploy)
	testing.expect_value(t, deploy.units[deploy.objective_unit].destination, deploy.relays[0])
}

@(test)
skirmish_new_primary_objectives_resolve_from_authoritative_state :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Raid_And_Deploy
	deploy := combat_new_skirmish_mission(1211, setup)
	defer combat_mission_destroy(&deploy)
	deploy.relay_progress[0] = 100
	deploy.units[deploy.objective_unit].extracted = true
	testing.expect(t, skirmish_objective_met(&deploy, .Deploy_Relay))
}
