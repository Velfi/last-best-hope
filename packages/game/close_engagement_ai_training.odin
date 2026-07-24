package game

// These are bounded behavioral weights, never permissions. Physical rules,
// doctrine, information access, and fire-control authorization remain outside
// the trainable surface.
Combat_AI_Parameters :: struct {
	sensor_value,
	objective_value,
	travel_cost,
	masking_value,
	force_value,
	escape_value,
	support_value,
	pressure_cost,
	readiness_value,
	hysteresis: f32,
}

COMBAT_AI_CURRICULUM_VERSION :: 3
COMBAT_AI_CONTROLLER_REVISION :: 8
COMBAT_AI_EVALUATION_REVISION :: 8
COMBAT_AI_CURRICULUM_OPERATIONS :: 11
COMBAT_AI_CURRICULUM_OPPONENTS :: 4
COMBAT_AI_CURRICULUM_RUNS :: COMBAT_AI_CURRICULUM_OPERATIONS * COMBAT_AI_CURRICULUM_OPPONENTS

Combat_AI_Operation_Family :: enum {
	Recovery,
	Control_Intelligence,
	Force_Mobility,
}

Combat_AI_Curriculum_Sample :: struct {
	index:                       int,
	operation:                   Skirmish_Mission_Kind,
	family:                      Combat_AI_Operation_Family,
	opponent_index:              int,
	doctrine:                    Combat_Doctrine,
	mission_seed, contract_seed: u64,
	faction_count:               int,
}

Combat_AI_Curriculum_Metrics :: struct {
	score:                                                       f64,
	runs, wins, partials, objectives:                            int,
	preserved, disabled, enemy_losses, player_losses:            int,
	primary_failures, objective_orders, interaction_completions: int,
	extraction_completions, objective_aborts:                    int,
	probe_launches, probe_completions, probe_losses:             int,
	screened_runs:                                              int,
	friendly_total, enemy_total:                                 int,
}

Combat_AI_Evaluation :: struct {
	score:                                                        f64,
	runs, wins, partials:                                         int,
	objectives, preserved, disabled, enemy_losses, player_losses: int,
	primary_failures, objective_orders, interaction_completions:  int,
	extraction_completions, objective_aborts:                     int,
	probe_launches, probe_completions, probe_losses:              int,
	screened_runs:                                               int,
	recovery_profile_runs,
	recovery_profile_wins:                                      [SKIRMISH_RECOVERY_PROFILE_COUNT]int,
	ordnance_remaining, initial_ordnance:                         int,
	friendly_total, enemy_total:                                  int,
	mean_time:                                                    f64,
	operations:                                                   [COMBAT_AI_CURRICULUM_OPERATIONS]Combat_AI_Curriculum_Metrics,
	families:                                                     [len(
		Combat_AI_Operation_Family,
	)]Combat_AI_Curriculum_Metrics,
}

combat_ai_evaluation_score :: proc(value: Combat_AI_Evaluation) -> f64 {
	return value.score
}

combat_ai_default_parameters :: proc() -> Combat_AI_Parameters {
	return {1, 1, 1, 1, 1, 1, 1, 1, 1, 1}
}

combat_ai_parameters_valid :: proc(p: Combat_AI_Parameters) -> bool {
	values := [10]f32 {
		p.sensor_value,
		p.objective_value,
		p.travel_cost,
		p.masking_value,
		p.force_value,
		p.escape_value,
		p.support_value,
		p.pressure_cost,
		p.readiness_value,
		p.hysteresis,
	}
	for value in values do if value < .5 || value > 1.5 do return false
	return true
}

combat_ai_parameters_for :: proc(m: ^Combat_Mission, side: Combat_Side) -> Combat_AI_Parameters {
	p := m.ai_parameters[combat_side_index(side)]
	if p.sensor_value == 0 do return combat_ai_default_parameters()
	return p
}

combat_ai_set_parameters :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	parameters: Combat_AI_Parameters,
) -> bool {
	if !combat_ai_parameters_valid(parameters) do return false
	m.ai_parameters[combat_side_index(side)] = parameters
	return true
}

// The league deliberately contains policies with different tactical biases.
// They remain bounded scoring weights: none can bypass doctrine, information,
// fire authorization, or physical simulation rules.
combat_ai_league_parameters :: proc(index: int) -> Combat_AI_Parameters {
	p := combat_ai_default_parameters()
	switch index % 4 {
	case 0: // Shipped baseline.
	case 1:
		// Concealment and survival.
		p.sensor_value = 1.2
		p.masking_value = 1.35
		p.escape_value = 1.3
		p.pressure_cost = 1.2
		p.force_value = .8
	case 2:
		// Objective pressure and concentration.
		p.objective_value = 1.35
		p.force_value = 1.3
		p.travel_cost = .75
		p.escape_value = .8
	case 3:
		// Endurance and mutual support.
		p.support_value = 1.35
		p.readiness_value = 1.3
		p.hysteresis = 1.25
		p.objective_value = .9
	}
	return p
}

combat_ai_league_doctrine :: proc(index: int) -> Combat_Doctrine {
	switch index % 4 {
	case 0:
		return .Cautious_Screen
	case 1:
		return .Balanced
	case 2:
		return .Hunter_Killer
	case 3:
		return .Last_Stand
	}
	return .Balanced
}

combat_ai_curriculum_operation :: proc(index: int) -> Skirmish_Mission_Kind {
	operations := [COMBAT_AI_CURRICULUM_OPERATIONS]Skirmish_Mission_Kind {
		.Seedship_Recovery,
		.Disabled_Ship_Rescue,
		.Contested_Salvage,
		.Repair_And_Tow,
		.Reconnaissance,
		.Relay_Control,
		.Raid_And_Deploy,
		.Fleet_Engagement,
		.Rearguard_Withdrawal,
		.Capital_Interception,
		.Convoy_Escort,
	}
	return operations[index % len(operations)]
}

combat_ai_operation_family :: proc(
	operation: Skirmish_Mission_Kind,
) -> Combat_AI_Operation_Family {
	switch operation {
	case .Seedship_Recovery, .Disabled_Ship_Rescue, .Contested_Salvage, .Repair_And_Tow:
		return .Recovery
	case .Reconnaissance, .Relay_Control, .Silent_Infiltration, .Raid_And_Deploy:
		return .Control_Intelligence
	case .Fleet_Engagement,
	     .Rearguard_Withdrawal,
	     .Capital_Interception,
	     .Convoy_Escort,
	     .Citadel_Assault:
		return .Force_Mobility
	}
	return .Force_Mobility
}

combat_ai_curriculum_sample :: proc(
	seed_base: u64,
	sample_index: int,
) -> Combat_AI_Curriculum_Sample {
	cell := sample_index % COMBAT_AI_CURRICULUM_RUNS
	operation_index := cell % COMBAT_AI_CURRICULUM_OPERATIONS
	opponent_index := cell / COMBAT_AI_CURRICULUM_OPERATIONS
	cycle := sample_index / COMBAT_AI_CURRICULUM_RUNS
	identity := combat_mix(
		seed_base ~ u64(cell + 1) * 0x9e3779b97f4a7c15 ~ u64(cycle + 1) * 0x6a09e667f3bcc909,
	)
	operation := combat_ai_curriculum_operation(operation_index)
	requested_factions := 2 + int(combat_mix(identity ~ 0xa4093822299f31d0) % 3)
	budget := skirmish_generation_budget(operation)
	return {
		index = cell,
		operation = operation,
		family = combat_ai_operation_family(operation),
		opponent_index = opponent_index,
		doctrine = combat_ai_league_doctrine(opponent_index),
		mission_seed = combat_mix(identity ~ 0x243f6a8885a308d3),
		contract_seed = combat_mix(identity ~ 0x13198a2e03707344),
		faction_count = min(requested_factions, budget.max_factions),
	}
}

combat_ai_metrics_add :: proc(
	metrics: ^Combat_AI_Curriculum_Metrics,
	score: f64,
	wins,
	partials,
	objectives,
	preserved,
	disabled,
	enemy_losses,
	player_losses,
	friendly_total,
	enemy_total,
	objective_orders,
	interaction_completions,
	extraction_completions,
	objective_aborts,
	probe_launches,
	probe_completions,
	probe_losses,
	screened_runs: int,
) {
	metrics.score += score
	metrics.runs += 1
	metrics.wins += wins
	metrics.partials += partials
	metrics.objectives += objectives
	metrics.preserved += preserved
	metrics.disabled += disabled
	metrics.enemy_losses += enemy_losses
	metrics.player_losses += player_losses
	metrics.primary_failures += 1 - wins
	metrics.objective_orders += objective_orders
	metrics.interaction_completions += interaction_completions
	metrics.extraction_completions += extraction_completions
	metrics.objective_aborts += objective_aborts
	metrics.probe_launches += probe_launches
	metrics.probe_completions += probe_completions
	metrics.probe_losses += probe_losses
	metrics.screened_runs += screened_runs
	metrics.friendly_total += friendly_total
	metrics.enemy_total += enemy_total
}

combat_ai_evaluation_merge :: proc(total: ^Combat_AI_Evaluation, value: Combat_AI_Evaluation) {
	weighted_time := total.mean_time * f64(total.runs) + value.mean_time * f64(value.runs)
	total.score += value.score
	total.runs += value.runs
	total.wins += value.wins
	total.partials += value.partials
	total.objectives += value.objectives
	total.primary_failures += value.primary_failures
	total.objective_orders += value.objective_orders
	total.interaction_completions += value.interaction_completions
	total.extraction_completions += value.extraction_completions
	total.objective_aborts += value.objective_aborts
	total.probe_launches += value.probe_launches
	total.probe_completions += value.probe_completions
	total.probe_losses += value.probe_losses
	total.screened_runs += value.screened_runs
	for profile in 0 ..< SKIRMISH_RECOVERY_PROFILE_COUNT {
		total.recovery_profile_runs[profile] += value.recovery_profile_runs[profile]
		total.recovery_profile_wins[profile] += value.recovery_profile_wins[profile]
	}
	total.preserved += value.preserved
	total.disabled += value.disabled
	total.enemy_losses += value.enemy_losses
	total.player_losses += value.player_losses
	total.ordnance_remaining += value.ordnance_remaining
	total.initial_ordnance += value.initial_ordnance
	total.friendly_total += value.friendly_total
	total.enemy_total += value.enemy_total
	for &metrics, index in total.operations {
		source := value.operations[index]
		metrics.score += source.score
		metrics.runs += source.runs
		metrics.wins += source.wins
		metrics.partials += source.partials
		metrics.objectives += source.objectives
		metrics.preserved += source.preserved
		metrics.disabled += source.disabled
		metrics.enemy_losses += source.enemy_losses
		metrics.player_losses += source.player_losses
		metrics.primary_failures += source.primary_failures
		metrics.objective_orders += source.objective_orders
		metrics.interaction_completions += source.interaction_completions
		metrics.extraction_completions += source.extraction_completions
		metrics.objective_aborts += source.objective_aborts
		metrics.probe_launches += source.probe_launches
		metrics.probe_completions += source.probe_completions
		metrics.probe_losses += source.probe_losses
		metrics.screened_runs += source.screened_runs
		metrics.friendly_total += source.friendly_total
		metrics.enemy_total += source.enemy_total
	}
	for &metrics, index in total.families {
		source := value.families[index]
		metrics.score += source.score
		metrics.runs += source.runs
		metrics.wins += source.wins
		metrics.partials += source.partials
		metrics.objectives += source.objectives
		metrics.preserved += source.preserved
		metrics.disabled += source.disabled
		metrics.enemy_losses += source.enemy_losses
		metrics.player_losses += source.player_losses
		metrics.primary_failures += source.primary_failures
		metrics.objective_orders += source.objective_orders
		metrics.interaction_completions += source.interaction_completions
		metrics.extraction_completions += source.extraction_completions
		metrics.objective_aborts += source.objective_aborts
		metrics.probe_launches += source.probe_launches
		metrics.probe_completions += source.probe_completions
		metrics.probe_losses += source.probe_losses
		metrics.screened_runs += source.screened_runs
		metrics.friendly_total += source.friendly_total
		metrics.enemy_total += source.enemy_total
	}
	if total.runs > 0 do total.mean_time = weighted_time / f64(total.runs)
}

combat_ai_evaluate_curriculum_sample :: proc(
	parameters: Combat_AI_Parameters,
	seed_base: u64,
	sample_index: int,
) -> Combat_AI_Evaluation {
	result: Combat_AI_Evaluation
	if !combat_ai_parameters_valid(parameters) do return result
	sample := combat_ai_curriculum_sample(seed_base, sample_index)
	setup := skirmish_default_setup()
	setup.seed = sample.mission_seed
	setup.contract_seed = sample.contract_seed
	setup.faction_count = sample.faction_count
	setup.mission = sample.operation
	m := combat_new_skirmish_mission(sample.mission_seed, setup)
	defer combat_mission_destroy(&m)
	_ = combat_ai_set_parameters(&m, .Friendly, parameters)
	_ = combat_ai_set_parameters(&m, .Raider, combat_ai_league_parameters(sample.opponent_index))
	for index in 0 ..< m.friendly_count do combat_set_doctrine(&m, index, sample.doctrine)
	friendly_total, enemy_total, initial_ordnance := 0, 0, 0
	for unit, index in m.units[:m.unit_count] {
		if index < m.friendly_count {
			friendly_total += unit.formation_ships
			initial_ordnance += unit.torpedoes
		} else {
			enemy_total += unit.formation_ships
		}
	}
	controller: Combat_Autoplay_Controller
	for !m.complete {
		combat_autoplay_step(&m, &controller)
		combat_tick_fixed(&m, .05)
	}
	controller.extraction_complete = combat_autoplay_extraction_satisfied(&m, &controller)
	primary := skirmish_primary_objective_met(&m)
	optional := skirmish_optional_objectives_met(&m)
	win := primary ? 1 : 0
	partial := !primary && optional > 0 ? 1 : 0
	objectives := win + optional
	friendly_denominator := f64(max(friendly_total, 1))
	enemy_denominator := f64(max(enemy_total, 1))
	ordnance_denominator := f64(max(initial_ordnance, 1))
	score :=
		f64(win) * 1000 +
		f64(partial) * 240 +
		f64(optional) * 120 +
		250 * f64(m.result.ships_preserved) / friendly_denominator +
		100 * f64(m.result.enemy_ships_lost) / enemy_denominator +
		50 * f64(m.result.heavy_ammunition) / ordnance_denominator -
		300 * f64(m.result.player_ships_lost) / friendly_denominator -
		75 * f64(m.result.ships_disabled) / friendly_denominator
	if primary {
		score += 50 * max(0, 1 - f64(m.result.mission_time) / f64(COMBAT_DURATION))
	}
	result = {
		score                   = score,
		runs                    = 1,
		wins                    = win,
		partials                = partial,
		objectives              = objectives,
		primary_failures        = 1 - win,
		objective_orders        = controller.primary_order_active ? 1 : 0,
		interaction_completions = controller.interaction_complete ? 1 : 0,
		extraction_completions  = controller.extraction_complete ? 1 : 0,
		objective_aborts        = controller.aborted ? 1 : 0,
		probe_launches          = m.recon_probes_launched,
		probe_completions       = m.recon_probes_completed,
		probe_losses            = m.recon_probes_lost,
		screened_runs           = m.skirmish_objective_pressure == .Picket_Screen ? 1 : 0,
		preserved               = m.result.ships_preserved,
		disabled                = m.result.ships_disabled,
		enemy_losses            = m.result.enemy_ships_lost,
		player_losses           = m.result.player_ships_lost,
		ordnance_remaining      = m.result.heavy_ammunition,
		initial_ordnance        = initial_ordnance,
		friendly_total          = friendly_total,
		enemy_total             = enemy_total,
		mean_time               = f64(m.result.mission_time),
	}
	if profile := skirmish_recovery_profile_index(m.skirmish_recovery_profile); profile >= 0 {
		result.recovery_profile_runs[profile] = 1
		result.recovery_profile_wins[profile] = win
	}
	combat_ai_metrics_add(
		&result.operations[sample.index % COMBAT_AI_CURRICULUM_OPERATIONS],
		score,
		win,
		partial,
		objectives,
		result.preserved,
		result.disabled,
		result.enemy_losses,
		result.player_losses,
		friendly_total,
		enemy_total,
		result.objective_orders,
		result.interaction_completions,
		result.extraction_completions,
		result.objective_aborts,
		result.probe_launches,
		result.probe_completions,
		result.probe_losses,
		result.screened_runs,
	)
	combat_ai_metrics_add(
		&result.families[int(sample.family)],
		score,
		win,
		partial,
		objectives,
		result.preserved,
		result.disabled,
		result.enemy_losses,
		result.player_losses,
		friendly_total,
		enemy_total,
		result.objective_orders,
		result.interaction_completions,
		result.extraction_completions,
		result.objective_aborts,
		result.probe_launches,
		result.probe_completions,
		result.probe_losses,
		result.screened_runs,
	)
	return result
}

// A complete batch covers all eleven active ordinary operations against all four
// doctrine/opponent archetypes. Simulation identity is independent of workers.
combat_ai_evaluate_league :: proc(
	parameters: Combat_AI_Parameters,
	seed_base: u64,
	runs: int,
) -> Combat_AI_Evaluation {
	result: Combat_AI_Evaluation
	if !combat_ai_parameters_valid(parameters) || runs <= 0 do return result
	for sample in 0 ..< runs {
		combat_ai_evaluation_merge(
			&result,
			combat_ai_evaluate_curriculum_sample(parameters, seed_base, sample),
		)
	}
	return result
}
