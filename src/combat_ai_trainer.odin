package main

import game "../packages/game"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:time"

COMBAT_AI_TRAINER_VERSION :: game.COMBAT_AI_CURRICULUM_VERSION

Combat_AI_Checkpoint :: struct {
	version:                                  int,
	curriculum_version, matrix_runs:          int,
	controller_revision, evaluation_revision: int,
	operation_names:                          [game.COMBAT_AI_CURRICULUM_OPERATIONS]string,
	generation:                               int,
	seed, rng_state:                          u64,
	development_runs, validation_runs:        int,
	champion:                                 game.Combat_AI_Parameters,
	development, validation:                  game.Combat_AI_Evaluation,
}

Combat_AI_Checkpoint_Header :: struct {
	version,
	curriculum_version,
	matrix_runs,
	controller_revision,
	evaluation_revision: int,
}

combat_ai_parse_int :: proc(value: string, fallback: int) -> int {
	if parsed, ok := strconv.parse_int(value); ok do return int(parsed)
	return fallback
}

combat_ai_parse_u64 :: proc(value: string, fallback: u64) -> u64 {
	if parsed, ok := strconv.parse_uint(value); ok do return u64(parsed)
	return fallback
}

combat_ai_random :: proc(state: ^u64) -> f32 {
	state^ = game.combat_mix(state^ + 0x9e3779b97f4a7c15)
	return f32(state^ & 0xffffff) / f32(0xffffff)
}

combat_ai_parameter_get :: proc(p: game.Combat_AI_Parameters, index: int) -> f32 {
	switch index {
	case 0:
		return p.sensor_value
	case 1:
		return p.objective_value
	case 2:
		return p.travel_cost
	case 3:
		return p.masking_value
	case 4:
		return p.force_value
	case 5:
		return p.escape_value
	case 6:
		return p.support_value
	case 7:
		return p.pressure_cost
	case 8:
		return p.readiness_value
	case 9:
		return p.hysteresis
	}
	return 1
}

combat_ai_parameter_set :: proc(p: ^game.Combat_AI_Parameters, index: int, value: f32) {
	bounded := clamp(value, f32(.5), f32(1.5))
	switch index {
	case 0:
		p.sensor_value = bounded
	case 1:
		p.objective_value = bounded
	case 2:
		p.travel_cost = bounded
	case 3:
		p.masking_value = bounded
	case 4:
		p.force_value = bounded
	case 5:
		p.escape_value = bounded
	case 6:
		p.support_value = bounded
	case 7:
		p.pressure_cost = bounded
	case 8:
		p.readiness_value = bounded
	case 9:
		p.hysteresis = bounded
	}
}

combat_ai_mutate :: proc(
	parent: game.Combat_AI_Parameters,
	state: ^u64,
	amount: f32,
) -> game.Combat_AI_Parameters {
	child := parent
	changes := 1 + int(combat_ai_random(state) * 3)
	for _ in 0 ..< changes {
		index := int(combat_ai_random(state) * 10) % 10
		delta := (combat_ai_random(state) * 2 - 1) * amount
		combat_ai_parameter_set(&child, index, combat_ai_parameter_get(child, index) + delta)
	}
	return child
}

combat_ai_write_file_atomically :: proc(path: string, data: []byte) -> bool {
	// A process-specific name prevents simultaneous trainer or trial runs from
	// clobbering one another's temporary file before either rename completes.
	temporary := fmt.tprintf("%s.%d.tmp", path, os.get_pid())
	if write_err := os.write_entire_file(temporary, data); write_err != nil {
		fmt.eprintf("could not write temporary file %s: %v\n", temporary, write_err)
		return false
	}
	if rename_err := os.rename(temporary, path); rename_err != nil {
		fmt.eprintf("could not replace file %s with %s: %v\n", path, temporary, rename_err)
		if remove_err := os.remove(temporary); remove_err != nil {
			fmt.eprintf("could not remove failed temporary file %s: %v\n", temporary, remove_err)
		}
		return false
	}
	return true
}

combat_ai_checkpoint_write :: proc(path: string, checkpoint: ^Combat_AI_Checkpoint) -> bool {
	data, err := json.marshal(checkpoint^)
	if err != nil {
		fmt.eprintf("could not serialize checkpoint %s: %v\n", path, err)
		return false
	}
	defer delete(data)
	return combat_ai_write_file_atomically(path, data[:])
}

combat_ai_checkpoint_read :: proc(path: string) -> (Combat_AI_Checkpoint, bool, bool) {
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil do return {}, false, false
	header: Combat_AI_Checkpoint_Header
	if json.unmarshal(data, &header) != nil {
		fmt.eprintf("checkpoint %s is not valid JSON; file preserved\n", path)
		return {}, false, true
	}
	if header.version != COMBAT_AI_TRAINER_VERSION ||
	   header.curriculum_version != game.COMBAT_AI_CURRICULUM_VERSION ||
	   header.controller_revision != game.COMBAT_AI_CONTROLLER_REVISION ||
	   header.evaluation_revision != game.COMBAT_AI_EVALUATION_REVISION ||
	   header.matrix_runs != game.COMBAT_AI_CURRICULUM_RUNS {
		fmt.eprintf(
			"checkpoint %s uses curriculum v%d matrix=%d controller/evaluation revisions %d/%d; expected v%d matrix=%d revisions %d/%d; file preserved\n",
			path,
			header.curriculum_version,
			header.matrix_runs,
			header.controller_revision,
			header.evaluation_revision,
			game.COMBAT_AI_CURRICULUM_VERSION,
			game.COMBAT_AI_CURRICULUM_RUNS,
			game.COMBAT_AI_CONTROLLER_REVISION,
			game.COMBAT_AI_EVALUATION_REVISION,
		)
		return {}, false, true
	}
	checkpoint: Combat_AI_Checkpoint
	if json.unmarshal(data, &checkpoint) != nil {
		fmt.eprintf("checkpoint %s is not valid JSON; file preserved\n", path)
		return {}, false, true
	}
	if !game.combat_ai_parameters_valid(checkpoint.champion) {
		fmt.eprintf("checkpoint %s has invalid AI parameters; file preserved\n", path)
		return {}, false, true
	}
	return checkpoint, true, true
}

combat_ai_apply_graphical_checkpoint :: proc(m: ^game.Combat_Mission, args: []string) {
	for index in 0 ..< len(args) - 1 {
		if args[index] != "--ai-checkpoint" do continue
		checkpoint, ok, _ := combat_ai_checkpoint_read(args[index + 1])
		if !ok {
			fmt.eprintf("could not load combat AI checkpoint %s\n", args[index + 1])
			return
		}
		_ = game.combat_ai_set_parameters(m, .Raider, checkpoint.champion)
		fmt.printf(
			"loaded hostile combat AI generation %d from %s\n",
			checkpoint.generation,
			args[index + 1],
		)
		return
	}
}

combat_ai_print_parameters :: proc(p: game.Combat_AI_Parameters) {
	fmt.printf(
		"sensor=%.4f objective=%.4f travel=%.4f masking=%.4f force=%.4f escape=%.4f support=%.4f pressure=%.4f readiness=%.4f hysteresis=%.4f\n",
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
	)
}

combat_ai_print_evaluation :: proc(label: string, value: game.Combat_AI_Evaluation) {
	fmt.printf(
		"%s score=%.2f runs=%d wins=%d partials=%d objectives=%d preserved=%d losses=%d:%d ordnance=%d mean=%.1fmin orders=%d interactions=%d extractions=%d aborts=%d failures=%d probes=%d:%d:%d screened=%d\n",
		label,
		value.score,
		value.runs,
		value.wins,
		value.partials,
		value.objectives,
		value.preserved,
		value.player_losses,
		value.enemy_losses,
		value.ordnance_remaining,
		value.mean_time,
		value.objective_orders,
		value.interaction_completions,
		value.extraction_completions,
		value.objective_aborts,
		value.primary_failures,
		value.probe_launches,
		value.probe_completions,
		value.probe_losses,
		value.screened_runs,
	)
	for metrics, family in value.families {
		if metrics.runs == 0 do continue
		fmt.printf(
			"  family=%s score=%.2f/run wins=%d/%d preserved=%d/%d losses=%d/%d\n",
			combat_ai_family_name(game.Combat_AI_Operation_Family(family)),
			metrics.score / f64(metrics.runs),
			metrics.wins,
			metrics.runs,
			metrics.preserved,
			metrics.friendly_total,
			metrics.player_losses,
			metrics.friendly_total,
		)
	}
	for profile in 0 ..< game.SKIRMISH_RECOVERY_PROFILE_COUNT {
		runs := value.recovery_profile_runs[profile]
		if runs == 0 do continue
		kind := game.Skirmish_Recovery_Profile(profile + 1)
		fmt.printf(
			"  recovery-profile=%s wins=%d/%d\n",
			game.skirmish_recovery_profile_name(kind),
			value.recovery_profile_wins[profile],
			runs,
		)
	}
	for metrics, operation in value.operations {
		if metrics.runs == 0 do continue
		fmt.printf(
			"  operation=%s score=%.2f/run wins=%d/%d objectives=%d preserved=%d/%d orders=%d interactions=%d extractions=%d aborts=%d failures=%d probes=%d:%d:%d screened=%d\n",
			game.skirmish_mission_name(game.combat_ai_curriculum_operation(operation)),
			metrics.score / f64(metrics.runs),
			metrics.wins,
			metrics.runs,
			metrics.objectives,
			metrics.preserved,
			metrics.friendly_total,
			metrics.objective_orders,
			metrics.interaction_completions,
			metrics.extraction_completions,
			metrics.objective_aborts,
			metrics.primary_failures,
			metrics.probe_launches,
			metrics.probe_completions,
			metrics.probe_losses,
			metrics.screened_runs,
		)
	}
}

combat_ai_family_name :: proc(family: game.Combat_AI_Operation_Family) -> string {
	switch family {
	case .Recovery:
		return "recovery"
	case .Control_Intelligence:
		return "control-intelligence"
	case .Force_Mobility:
		return "force-mobility"
	}
	return "unknown"
}

combat_ai_operation_names :: proc() -> [game.COMBAT_AI_CURRICULUM_OPERATIONS]string {
	names: [game.COMBAT_AI_CURRICULUM_OPERATIONS]string
	for &name, operation in names {
		name = game.skirmish_mission_name(game.combat_ai_curriculum_operation(operation))
	}
	return names
}

combat_ai_rate :: proc(numerator, denominator: int) -> f64 {
	if denominator <= 0 do return 0
	return f64(numerator) / f64(denominator)
}

combat_ai_promotion_gate :: proc(
	incumbent, candidate: game.Combat_AI_Evaluation,
) -> (
	bool,
	string,
) {
	if candidate.score <= incumbent.score do return false, "aggregate score did not improve"
	if candidate.wins < incumbent.wins do return false, "primary wins regressed"
	if combat_ai_rate(candidate.player_losses, candidate.friendly_total) >
	   combat_ai_rate(incumbent.player_losses, incumbent.friendly_total) + .05 {
		return false, "player loss rate regressed"
	}
	if combat_ai_rate(candidate.preserved, candidate.friendly_total) <
	   combat_ai_rate(incumbent.preserved, incumbent.friendly_total) - .05 {
		return false, "preservation rate regressed"
	}
	for current, family in incumbent.families {
		next := candidate.families[family]
		if current.runs == 0 || next.runs == 0 do return false, "operation family coverage missing"
		if next.wins < current.wins - 1 {
			return false, fmt.tprintf(
				"%s primary wins collapsed",
				combat_ai_family_name(game.Combat_AI_Operation_Family(family)),
			)
		}
		if next.score / f64(next.runs) < current.score / f64(current.runs) - 25 {
			return false, fmt.tprintf(
				"%s score regressed",
				combat_ai_family_name(game.Combat_AI_Operation_Family(family)),
			)
		}
	}
	for profile in 0 ..< game.SKIRMISH_RECOVERY_PROFILE_COUNT {
		current_runs := incumbent.recovery_profile_runs[profile]
		next_runs := candidate.recovery_profile_runs[profile]
		if current_runs == 0 && next_runs == 0 do continue
		if current_runs != next_runs {
			return false, "recovery profile coverage changed"
		}
		if candidate.recovery_profile_wins[profile] <
		   incumbent.recovery_profile_wins[profile] - 1 {
			kind := game.Skirmish_Recovery_Profile(profile + 1)
			return false, fmt.tprintf(
				"%s recovery profile collapsed",
				game.skirmish_recovery_profile_name(kind),
			)
		}
	}
	return true, "accepted"
}

combat_ai_checkpoint_new :: proc(
	seed: u64,
	development_runs, validation_runs, workers: int,
) -> Combat_AI_Checkpoint {
	champion := game.combat_ai_default_parameters()
	return {
		version = COMBAT_AI_TRAINER_VERSION,
		curriculum_version = game.COMBAT_AI_CURRICULUM_VERSION,
		controller_revision = game.COMBAT_AI_CONTROLLER_REVISION,
		evaluation_revision = game.COMBAT_AI_EVALUATION_REVISION,
		matrix_runs = game.COMBAT_AI_CURRICULUM_RUNS,
		operation_names = combat_ai_operation_names(),
		seed = seed,
		rng_state = game.combat_mix(seed),
		development_runs = development_runs,
		validation_runs = validation_runs,
		champion = champion,
		development = combat_ai_evaluate_parallel(champion, seed, development_runs, workers),
		validation = combat_ai_evaluate_parallel(
			champion,
			seed + 1000000,
			validation_runs,
			workers,
		),
	}
}

combat_ai_baseline_signal_valid :: proc(value: game.Combat_AI_Evaluation) -> (bool, string) {
	if value.runs == 0 do return false, "baseline contains no runs"
	if value.wins >= value.runs do return false, "baseline is perfect"
	for metrics, family in value.families {
		if metrics.wins == 0 {
			return false, fmt.tprintf(
				"%s has no primary wins",
				combat_ai_family_name(game.Combat_AI_Operation_Family(family)),
			)
		}
	}
	for metrics, operation in value.operations {
		if metrics.wins == 0 && metrics.partials == 0 && metrics.objectives == 0 {
			return false, fmt.tprintf(
				"%s has no objective signal",
				game.skirmish_mission_name(game.combat_ai_curriculum_operation(operation)),
			)
		}
	}
	return true, "balanced objective signal"
}

combat_ai_print_training_progress :: proc(
	stage: string,
	generation, candidate, candidates, battles, accepted: int,
	started: time.Tick,
	max_seconds: f64,
) {
	elapsed := time.duration_seconds(time.tick_since(started))
	if max_seconds > 0 {
		remaining := max(0, max_seconds - elapsed)
		percent := min(100, elapsed / max_seconds * 100)
		fmt.printf(
			"progress stage=%s generation=%d candidate=%d/%d battles=%d accepted=%d elapsed=%.1fmin remaining=%.1fmin complete=%.1f%%\n",
			stage,
			generation,
			candidate,
			candidates,
			battles,
			accepted,
			elapsed / 60,
			remaining / 60,
			percent,
		)
	} else {
		fmt.printf(
			"progress stage=%s generation=%d candidate=%d/%d battles=%d accepted=%d elapsed=%.1fmin\n",
			stage,
			generation,
			candidate,
			candidates,
			battles,
			accepted,
			elapsed / 60,
		)
	}
}

combat_ai_train_league :: proc(
	path: string,
	generation_limit, runs: int,
	seed: u64,
	workers: int,
	max_seconds: f64 = 0,
) -> bool {
	if runs < game.COMBAT_AI_CURRICULUM_RUNS || runs % game.COMBAT_AI_CURRICULUM_RUNS != 0 {
		fmt.eprintf("runs must be a positive multiple of %d\n", game.COMBAT_AI_CURRICULUM_RUNS)
		return false
	}
	validation_runs := runs
	checkpoint, resumed, exists := combat_ai_checkpoint_read(path)
	if !resumed {
		if exists do return false
		checkpoint = combat_ai_checkpoint_new(seed, runs, validation_runs, workers)
		if valid, reason := combat_ai_baseline_signal_valid(checkpoint.validation); !valid {
			fmt.eprintf("balanced curriculum baseline rejected: %s\n", reason)
			return false
		}
		if !combat_ai_checkpoint_write(path, &checkpoint) {
			fmt.eprintf("could not write checkpoint %s\n", path)
			return false
		}
	}
	fmt.printf(
		"%s combat AI training at generation %d with %d workers; checkpoint %s\n",
		resumed ? "resuming" : "starting",
		checkpoint.generation,
		workers,
		path,
	)
	combat_ai_print_evaluation("validation", checkpoint.validation)
	combat_ai_print_parameters(checkpoint.champion)
	start_generation := checkpoint.generation
	started := time.tick_now()
	evaluated_battles := 0
	accepted_generations := 0
	candidate_count := 7
	combat_ai_print_training_progress(
		"ready",
		checkpoint.generation,
		0,
		candidate_count,
		evaluated_battles,
		accepted_generations,
		started,
		max_seconds,
	)
	for generation_limit <= 0 || checkpoint.generation - start_generation < generation_limit {
		if max_seconds > 0 && time.duration_seconds(time.tick_since(started)) >= max_seconds {
			break
		}
		generation := checkpoint.generation + 1
		development_seed := checkpoint.seed + u64(generation) * 10000
		best := checkpoint.champion
		best_development := combat_ai_evaluate_parallel(
			best,
			development_seed,
			checkpoint.development_runs,
			workers,
		)
		evaluated_battles += checkpoint.development_runs
		combat_ai_print_training_progress(
			"champion",
			generation,
			0,
			candidate_count,
			evaluated_battles,
			accepted_generations,
			started,
			max_seconds,
		)
		mutation_amount := max(f32(.025), f32(.18) / f32(math.sqrt(f64(1 + generation) * .08 + 1)))
		for candidate_index in 0 ..< candidate_count {
			candidate := combat_ai_mutate(
				checkpoint.champion,
				&checkpoint.rng_state,
				mutation_amount,
			)
			evaluation := combat_ai_evaluate_parallel(
				candidate,
				development_seed,
				checkpoint.development_runs,
				workers,
			)
			evaluated_battles += checkpoint.development_runs
			if evaluation.score > best_development.score {
				best = candidate
				best_development = evaluation
			}
			combat_ai_print_training_progress(
				"candidate",
				generation,
				candidate_index + 1,
				candidate_count,
				evaluated_battles,
				accepted_generations,
				started,
				max_seconds,
			)
		}
		best_validation := combat_ai_evaluate_parallel(
			best,
			checkpoint.seed + 1000000,
			checkpoint.validation_runs,
			workers,
		)
		evaluated_battles += checkpoint.validation_runs
		combat_ai_print_training_progress(
			"validation",
			generation,
			candidate_count,
			candidate_count,
			evaluated_battles,
			accepted_generations,
			started,
			max_seconds,
		)
		accepted, gate_reason := combat_ai_promotion_gate(checkpoint.validation, best_validation)
		if accepted {
			accepted_generations += 1
			checkpoint.champion = best
			checkpoint.development = best_development
			checkpoint.validation = best_validation
		}
		checkpoint.generation = generation
		if !combat_ai_checkpoint_write(path, &checkpoint) {
			fmt.eprintf("checkpoint write failed at generation %d\n", generation)
			return false
		}
		fmt.printf(
			"generation=%d accepted=%v gate=%s mutation=%.4f dev=%.2f validation=%.2f champion=%.2f\n",
			generation,
			accepted,
			gate_reason,
			mutation_amount,
			best_development.score,
			best_validation.score,
			checkpoint.validation.score,
		)
		combat_ai_print_training_progress(
			"checkpoint",
			generation,
			candidate_count,
			candidate_count,
			evaluated_battles,
			accepted_generations,
			started,
			max_seconds,
		)
	}
	combat_ai_print_training_progress(
		"complete",
		checkpoint.generation,
		candidate_count,
		candidate_count,
		evaluated_battles,
		accepted_generations,
		started,
		max_seconds,
	)
	return true
}

run_combat_ai_cli :: proc(args: []string) -> bool {
	if len(args) < 2 do return false
	switch args[1] {
	case "--combat-ai-audit":
		runs := game.COMBAT_AI_CURRICULUM_RUNS
		if len(args) >= 3 do runs = max(combat_ai_parse_int(args[2], runs), runs)
		runs =
			((runs + game.COMBAT_AI_CURRICULUM_RUNS - 1) / game.COMBAT_AI_CURRICULUM_RUNS) *
			game.COMBAT_AI_CURRICULUM_RUNS
		seed := len(args) >= 4 ? combat_ai_parse_u64(args[3], 24301) : u64(24301)
		workers := combat_ai_default_workers()
		if len(args) >= 5 do workers = clamp(combat_ai_parse_int(args[4], workers), 1, COMBAT_AI_MAX_WORKERS)
		value := combat_ai_evaluate_parallel(
			game.combat_ai_default_parameters(),
			seed,
			runs,
			workers,
		)
		fmt.printf(
			"balanced curriculum audit: v%d matrix=%d runs=%d seed=%d workers=%d\n",
			game.COMBAT_AI_CURRICULUM_VERSION,
			game.COMBAT_AI_CURRICULUM_RUNS,
			runs,
			seed,
			workers,
		)
		combat_ai_print_evaluation("baseline", value)
		if valid, reason := combat_ai_baseline_signal_valid(value); !valid {
			fmt.eprintf("audit failed: %s\n", reason)
		} else {
			fmt.println("audit passed: balanced objective signal")
		}
		return true
	case "--combat-ai-overnight":
		if len(args) < 4 {
			fmt.println(
				"usage: --combat-ai-overnight <checkpoint.json> <hours> [runs] [seed] [workers]",
			)
			return true
		}
		hours, hours_ok := strconv.parse_f64(args[3])
		if !hours_ok || hours <= 0 {
			fmt.eprintln("hours must be greater than zero")
			return true
		}
		runs := game.COMBAT_AI_CURRICULUM_RUNS
		if len(args) >= 5 {
			runs = max(
				combat_ai_parse_int(args[4], game.COMBAT_AI_CURRICULUM_RUNS),
				game.COMBAT_AI_CURRICULUM_RUNS,
			)
		}
		runs =
			((runs + game.COMBAT_AI_CURRICULUM_RUNS - 1) / game.COMBAT_AI_CURRICULUM_RUNS) *
			game.COMBAT_AI_CURRICULUM_RUNS
		seed := len(args) >= 6 ? combat_ai_parse_u64(args[5], 24301) : u64(24301)
		workers := combat_ai_default_workers()
		if len(args) >= 7 {
			workers = clamp(combat_ai_parse_int(args[6], workers), 1, COMBAT_AI_MAX_WORKERS)
		}
		fmt.printf(
			"overnight curriculum: %.2f hours, %d paired league runs/candidate, seed=%d, workers=%d\n",
			hours,
			runs,
			seed,
			workers,
		)
		_ = combat_ai_train_league(args[2], 0, runs, seed, workers, hours * 3600)
		return true
	case "--combat-ai-report":
		if len(args) < 3 do return true
		checkpoint, ok, _ := combat_ai_checkpoint_read(args[2])
		if !ok {
			fmt.eprintln("checkpoint is missing or invalid")
			return true
		}
		fmt.printf("generation=%d seed=%d\n", checkpoint.generation, checkpoint.seed)
		combat_ai_print_evaluation("development", checkpoint.development)
		combat_ai_print_evaluation("validation", checkpoint.validation)
		combat_ai_print_parameters(checkpoint.champion)
		return true
	case "--combat-ai-validate":
		if len(args) < 3 do return true
		checkpoint, ok, _ := combat_ai_checkpoint_read(args[2])
		if !ok {
			fmt.eprintln("checkpoint is missing or invalid")
			return true
		}
		default_runs := game.COMBAT_AI_CURRICULUM_RUNS * 2
		runs := default_runs
		if len(args) >= 4 {
			runs = max(
				combat_ai_parse_int(args[3], default_runs),
				game.COMBAT_AI_CURRICULUM_RUNS,
			)
		}
		runs =
			((runs + game.COMBAT_AI_CURRICULUM_RUNS - 1) / game.COMBAT_AI_CURRICULUM_RUNS) *
			game.COMBAT_AI_CURRICULUM_RUNS
		seed :=
			len(args) >= 5 ? combat_ai_parse_u64(args[4], checkpoint.seed + 2000000) : checkpoint.seed + 2000000
		workers := combat_ai_default_workers()
		if len(args) >= 6 {
			workers = clamp(combat_ai_parse_int(args[5], workers), 1, COMBAT_AI_MAX_WORKERS)
		}
		value := combat_ai_evaluate_parallel(checkpoint.champion, seed, runs, workers)
		combat_ai_print_evaluation("holdout", value)
		return true
	case "--combat-ai-export":
		if len(args) < 4 do return true
		checkpoint, ok, _ := combat_ai_checkpoint_read(args[2])
		if !ok {
			fmt.eprintln("checkpoint is missing or invalid")
			return true
		}
		data, err := json.marshal(checkpoint.champion)
		if err != nil || os.write_entire_file(args[3], data[:]) != nil {
			fmt.eprintln("could not export parameters")
		} else {
			fmt.printf("exported reviewed candidate to %s\n", args[3])
		}
		if data != nil do delete(data)
		return true
	case "--combat-ai-trials":
		if len(args) < 4 {
			fmt.println(
				"usage: --combat-ai-trials <checkpoint.json> <report.json> [runs-per-block] [blocks] [seed] [workers]",
			)
			return true
		}
		runs_per_block := game.COMBAT_AI_CURRICULUM_RUNS
		if len(args) >= 5 {
			runs_per_block = max(
				combat_ai_parse_int(args[4], runs_per_block),
				game.COMBAT_AI_CURRICULUM_RUNS,
			)
		}
		runs_per_block =
			((runs_per_block + game.COMBAT_AI_CURRICULUM_RUNS - 1) /
				game.COMBAT_AI_CURRICULUM_RUNS) *
			game.COMBAT_AI_CURRICULUM_RUNS
		blocks := len(args) >= 6 ? clamp(combat_ai_parse_int(args[5], 4), 1, 64) : 4
		seed := len(args) >= 7 ? combat_ai_parse_u64(args[6], 900001) : u64(900001)
		workers := combat_ai_default_workers()
		if len(args) >= 8 {
			workers = clamp(combat_ai_parse_int(args[7], workers), 1, COMBAT_AI_MAX_WORKERS)
		}
		_ = combat_ai_run_trials(args[2], args[3], runs_per_block, blocks, seed, workers)
		return true
	}
	return false
}
