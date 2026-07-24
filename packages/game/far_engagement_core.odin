package game

// Far Engagement is the deterministic, operational-scale counterpart to
// Close Engagement. Presentation asks for intent at commitment boundaries; this
// package advances trajectories, contact beliefs, autonomous formations,
// weapon processes, consequences, and the factual record.

import "core:fmt"
import "core:math"

FAR_MAX_GROUPS :: 5
FAR_MAX_CONTACTS :: 4
FAR_MAX_SALVOS :: 12
FAR_MAX_RECORDS :: 40
FAR_FIXED_STEP_HOURS :: f64(1.0 / 120.0) // thirty simulated seconds

Far_Vec2 :: struct {
	x, y: f64,
}

Far_Phase :: enum {
	Dormant,
	Find,
	Fix,
	Shape,
	Commit,
	Interpret,
	Complete,
}

Far_Formation :: enum {
	Concentrated,
	Screened,
	Dispersed,
	Branched,
	Detached,
}

Far_Emission :: enum {
	Silent,
	Passive,
	Active_Search,
	Illuminate,
	Relay,
	Deceive,
}

Far_Authority :: enum {
	Report_Only,
	Confirm_Commitments,
	Confirm_Engagements,
	Direct_Command,
}

Far_Objective :: enum {
	Preserve_Passage_Course,
	Intercept,
	Screen,
	Recovery,
}

Far_Group_State :: enum {
	Operational,
	Pressured,
	Disabled,
	Separated,
	Lost,
	Arrived,
}

Far_Contact_Identity :: enum {
	Signal,
	Track,
	Probable_Picket,
	Probable_Capital,
	Confirmed_Interceptor,
}

Far_Wave_Phase :: enum {
	Boost,
	Cruise,
	Acquisition,
	Terminal,
	Resolved,
}

Far_Decision_Kind :: enum {
	None,
	Contact_Interpretation,
	Opening_Commitment,
	Intercept_Response,
	Launch_Authorization,
	Defensive_Shaping,
	Constraint_Conflict,
	Damage_Assessment,
	Recovery_Commitment,
	End_Confrontation,
}

Far_Command :: enum {
	Accept_Standing_Orders,
	Remain_Passive,
	Illuminate,
	Detach_Baseline,
	Hold_Protected_Course,
	Shift_Intercept,
	Branch_Formation,
	Launch_Shaping_Salvo,
	Launch_Full_Salvo,
	Hold_Ordnance,
	Maintain_Screen,
	Disperse_Fleet,
	Deploy_Decoys,
	Expose_Screen,
	Break_Deadline,
	Abandon_Screen,
	Continue_Mission,
	Dispatch_Recovery,
	Signal_Disabled,
	Pursue,
	Withdraw,
}

Far_Salvo_Purpose :: enum {
	Shape_Course,
	Destroy_Formation,
	Force_Separation,
	Attack_Protected_Group,
	Draw_Defenses,
}

Far_Group :: struct {
	id:                    u32,
	name, commander:       string,
	objective:             Far_Objective,
	formation:             Far_Formation,
	emission:              Far_Emission,
	state:                 Far_Group_State,
	position, velocity:    Far_Vec2,
	desired_velocity:      Far_Vec2,
	maneuver_reserve:      f64,
	signature_reserve:     f64,
	defensive_reserve:     f64,
	cohesion, hull:        f64,
	ships, disabled_ships: int,
	protected, detached:   bool,
}

Far_Contact :: struct {
	id:                 u32,
	name:               string,
	identity:           Far_Contact_Identity,
	estimated_position: Far_Vec2,
	estimated_velocity: Far_Vec2,
	uncertainty_mkm:    f64,
	confidence:         f64,
	last_observed_hour: f64,
	emission_strength:  f64,
	probable_maneuver:  f64,
	hostile, active:    bool,
}

Far_Salvo :: struct {
	id:                                     u32,
	source_group, target_group:             int,
	source_contact, target_contact:         int,
	purpose:                                Far_Salvo_Purpose,
	phase:                                  Far_Wave_Phase,
	launch_hour, arrival_hour:              f64,
	weapons_launched, weapons_surviving:    int,
	guidance, search_volume_mkm:            f64,
	friendly, detected, active, redirected: bool,
}

Far_Decision :: struct {
	kind:                   Far_Decision_Kind,
	title, situation:       string,
	forecast, default_text: string,
	commands:               [4]Far_Command,
	labels:                 [4]string,
	consequences:           [4]string,
	unavailable_reasons:    [4]string,
	option_enabled:         [4]bool,
	option_count:           int,
	default_option:         int,
	requesting_group:       int,
	raised_hour:            f64,
	pending:                bool,
}

Far_Record :: struct {
	hour:        f64,
	text:        string,
	group:       int,
	command:     Far_Command,
	consequence: bool,
}

Far_Result :: struct {
	passage_reached, deadline_kept, enemy_broken: bool,
	friendly_ships, ships_arrived:                int,
	ships_disabled, ships_lost, ships_recovered:  int,
	heavy_ordnance_spent, decoys_spent:           int,
	ending:                                       string,
}

// Far_Choice_Projection is a deterministic, non-authoritative branch forecast
// used to compare pending commands. It exposes only state already available to
// fleet command; hidden hostile truth remains hidden.
Far_Choice_Projection :: struct {
	valid, objective_complete, deadline_kept: bool,
	horizon_seconds:                          f64,
	task_positions:                           [FAR_MAX_GROUPS]Far_Vec2,
	task_count:                               int,
	track_confidence:                         f64,
	ships_disabled, ships_lost:               int,
}

Far_Engagement :: struct {
	schema_version:                                                                                                         u32,
	spec:                                                                                                                   Far_Encounter_Spec,
	briefing_pending,
	briefing_committed:                                                                                   bool,
	elapsed_seconds,
	duration_seconds,
	deadline_seconds:                                                                    f64,
	task_groups:                                                                                                            [FAR_MAX_GROUPS]Far_Task_Group,
	task_group_count:                                                                                                       int,
	truth_contacts:                                                                                                         [FAR_MAX_TRUTH_CONTACTS]Far_Truth_Contact,
	truth_contact_count:                                                                                                    int,
	beliefs:                                                                                                                [FAR_MAX_CONTACTS]Far_Contact_Belief,
	belief_count:                                                                                                           int,
	selected_belief:                                                                                                        int,
	transmissions:                                                                                                          [FAR_MAX_TRANSMISSIONS]Far_Transmission,
	transmission_count:                                                                                                     int,
	next_transmission_id:                                                                                                   u32,
	weapon_flights:                                                                                                         [FAR_MAX_SALVOS]Far_Weapon_Flight,
	weapon_flight_count:                                                                                                    int,
	ship_outcomes:                                                                                                          [FAR_MAX_SHIPS]Far_Ship_Outcome,
	ship_outcome_count:                                                                                                     int,
	next_ai_plan_seconds,
	next_observation_seconds:                                                                         f64,
	next_enemy_launch_seconds:                                                                                              f64,
	reinforcement_arrival_seconds:                                                                                          f64,
	impact_serial:                                                                                                          u64,
	objective_complete,
	objective_failed:                                                                                   bool,
	opening_commitment_resolved,
	first_track_decision,
	first_fire_decision:                                                 bool,
	first_defense_decision,
	first_recovery_decision:                                                                        bool,
	active,
	complete,
	paused_for_decision:                                                                                  bool,
	seed,
	rng:                                                                                                              u64,
	phase:                                                                                                                  Far_Phase,
	hour,
	duration_hours,
	deadline_hour,
	arrival_hour:                                                                      f64,
	fixed_accumulator:                                                                                                      f64,
	protected_course,
	projected_arrival:                                                                                    Far_Vec2,
	viable_course_margin_hours,
	intercept_margin_hours:                                                                     f64,
	groups:                                                                                                                 [FAR_MAX_GROUPS]Far_Group,
	group_count:                                                                                                            int,
	contacts:                                                                                                               [FAR_MAX_CONTACTS]Far_Contact,
	contact_count:                                                                                                          int,
	salvos:                                                                                                                 [FAR_MAX_SALVOS]Far_Salvo,
	next_salvo_id:                                                                                                          u32,
	records:                                                                                                                [FAR_MAX_RECORDS]Far_Record,
	record_count:                                                                                                           int,
	decision:                                                                                                               Far_Decision,
	opening_commitment:                                                                                                     Far_Command,
	authority:                                                                                                              Far_Authority,
	operation_authority:                                                                                                    Operation_Authority,
	stage_contact,
	stage_intercept,
	stage_launch:                                                                           bool,
	stage_incoming,
	stage_conflict,
	stage_damage:                                                                           bool,
	stage_recovery,
	stage_end:                                                                                              bool,
	baseline_detached,
	false_branch,
	screen_exposed:                                                                        bool,
	fleet_disperse,
	passage_committed,
	intercept_pressure_applied,
	recovery_committed,
	recovery_completed,
	outcome_applied: bool,
	enemy_formation:                                                                                                        Far_Formation,
	enemy_emission:                                                                                                         Far_Emission,
	enemy_maneuver_reserve,
	enemy_defensive_reserve:                                                                        f64,
	heavy_ordnance,
	decoys:                                                                                                 int,
	hostile_flights_diverted:                                                                                               int,
	result:                                                                                                                 Far_Result,
}

far_mix :: proc(x: u64) -> u64 {
	v := x
	v ~= v >> 30
	v *= 0xbf58476d1ce4e5b9
	v ~= v >> 27
	v *= 0x94d049bb133111eb
	return v ~ (v >> 31)
}

far_rand :: proc(e: ^Far_Engagement) -> f64 {
	e.rng = far_mix(e.rng + 0x9e3779b97f4a7c15)
	return f64(e.rng & 0xffffff) / f64(0xffffff)
}

far_distance :: proc(a, b: Far_Vec2) -> f64 {
	x, y := a.x - b.x, a.y - b.y
	return math.sqrt(x * x + y * y)
}

far_formation_name :: proc(value: Far_Formation) -> string {
	switch value {
	case .Concentrated:
		return "CONCENTRATED"
	case .Screened:
		return "SCREENED"
	case .Dispersed:
		return "DISPERSED"
	case .Branched:
		return "BRANCHED"
	case .Detached:
		return "DETACHED"
	}
	return "UNKNOWN"
}

far_emission_name :: proc(value: Far_Emission) -> string {
	switch value {
	case .Silent:
		return "SILENT"
	case .Passive:
		return "PASSIVE"
	case .Active_Search:
		return "ACTIVE SEARCH"
	case .Illuminate:
		return "ILLUMINATE"
	case .Relay:
		return "RELAY"
	case .Deceive:
		return "DECEIVE"
	}
	return "UNKNOWN"
}

far_phase_name :: proc(value: Far_Phase) -> string {
	switch value {
	case .Dormant:
		return "DORMANT"
	case .Find:
		return "FIND"
	case .Fix:
		return "FIX"
	case .Shape:
		return "SHAPE"
	case .Commit:
		return "COMMIT"
	case .Interpret:
		return "INTERPRET"
	case .Complete:
		return "COMPLETE"
	}
	return "UNKNOWN"
}

far_wave_phase_name :: proc(value: Far_Wave_Phase) -> string {
	switch value {
	case .Boost:
		return "BOOST"
	case .Cruise:
		return "CRUISE"
	case .Acquisition:
		return "ACQUISITION"
	case .Terminal:
		return "TERMINAL"
	case .Resolved:
		return "RESOLVED"
	}
	return "UNKNOWN"
}

far_format_time :: proc(hours: f64) -> string {
	total_minutes := max(0, int(math.round(hours * 60)))
	return fmt.tprintf("%02dh %02dm", total_minutes / 60, total_minutes % 60)
}

far_add_record :: proc(
	e: ^Far_Engagement,
	text: string,
	group := -1,
	command := Far_Command.Accept_Standing_Orders,
	consequence := false,
) {
	if e.record_count >= FAR_MAX_RECORDS {
		for i in 1 ..< FAR_MAX_RECORDS do e.records[i - 1] = e.records[i]
		e.record_count = FAR_MAX_RECORDS - 1
	}
	e.records[e.record_count] = {e.hour, text, group, command, consequence}
	e.record_count += 1
}

far_default_engagement :: proc(seed: u64) -> (e: Far_Engagement) {
	return far_generate_encounter(far_default_spec(seed))
}

far_raise_decision :: proc(
	e: ^Far_Engagement,
	kind: Far_Decision_Kind,
	title, situation, forecast: string,
	commands: []Far_Command,
	labels, consequences: []string,
	default_option := 0,
	requester := 0,
) {
	if e.decision.pending || len(commands) == 0 do return
	e.decision = {
		kind             = kind,
		title            = title,
		situation        = situation,
		forecast         = forecast,
		option_count     = min(len(commands), 4),
		default_option   = default_option,
		requesting_group = requester,
		raised_hour      = e.hour,
		pending          = true,
	}
	for command, i in commands[:e.decision.option_count] {
		e.decision.commands[i] = command
		e.decision.labels[i] = labels[i]
		e.decision.consequences[i] = consequences[i]
		e.decision.option_enabled[i] = true
	}
	for command, i in e.decision.commands[:e.decision.option_count] {
		#partial switch command {
		case .Launch_Shaping_Salvo:
			if e.heavy_ordnance < 2 {
				e.decision.option_enabled[i] = false
				e.decision.unavailable_reasons[i] = "Requires 2 heavy ordnance."
			}
		case .Launch_Full_Salvo:
			if e.heavy_ordnance < 5 {
				e.decision.option_enabled[i] = false
				e.decision.unavailable_reasons[i] = "Requires 5 heavy ordnance."
			}
		case .Branch_Formation:
			if e.decoys < 1 {
				e.decision.option_enabled[i] = false
				e.decision.unavailable_reasons[i] = "Requires 1 decoy train."
			}
		case .Deploy_Decoys:
			if e.decoys < 2 {
				e.decision.option_enabled[i] = false
				e.decision.unavailable_reasons[i] = "Requires 2 decoy trains."
			}
		case:
		}
	}
	e.decision.default_text = e.decision.labels[e.decision.default_option]
	e.paused_for_decision = true
}

far_apply_formation :: proc(e: ^Far_Engagement, formation: Far_Formation) {
	for &group in e.groups[:e.group_count] {
		if group.state == .Lost || group.state == .Arrived do continue
		group.formation = group.detached ? .Detached : formation
	}
	e.fleet_disperse = formation == .Dispersed
}

far_set_group_emission :: proc(e: ^Far_Engagement, group: int, emission: Far_Emission) -> bool {
	if group < 0 || group >= e.group_count do return false
	e.groups[group].emission = emission
	return true
}

far_resolve_decision :: proc(e: ^Far_Engagement, command: Far_Command) -> bool {
	if !e.decision.pending do return false
	valid := false
	for option in e.decision.commands[:e.decision.option_count] do if option == command {valid = true; break}
	if !valid do return false
	for option, i in e.decision.commands[:e.decision.option_count] do if option == command && !e.decision.option_enabled[i] {
		return false
	}
	kind := e.decision.kind
	if kind == .Opening_Commitment do e.opening_commitment = command
	switch command {
	case .Accept_Standing_Orders:
	case .Remain_Passive:
		far_add_record(e, "The fleet remained under passive watch.", 0, command)
	case .Illuminate:
		order := e.task_groups[2].received_order
		order.emission = .Illuminate
		_ = far_transmit_order(e, e.task_groups[0].position, 2, order)
		e.groups[2].signature_reserve = max(0, e.groups[2].signature_reserve - 34)
		far_add_record(e, "Illumination order transmitted to Far Lantern.", 2, command)
	case .Detach_Baseline:
		e.baseline_detached = true
		e.groups[2].detached = true
		e.groups[2].defensive_reserve -= 12
		order := e.task_groups[2].received_order
		order.formation = .Detached
		order.destination.y += 4.0e6
		_ = far_transmit_order(e, e.task_groups[0].position, 2, order)
		e.task_groups[2].delta_v_remaining_km_s = max(
			0,
			e.task_groups[2].delta_v_remaining_km_s - 35,
		)
		far_add_record(e, "Far Lantern detached to extend the passive baseline.", 2, command)
	case .Hold_Protected_Course:
		far_add_record(e, "Common Hearth held the protected course.", 0, command)
	case .Shift_Intercept:
		for &task, i in e.task_groups[:e.task_group_count] {
			order := task.received_order
			order.destination.y += 3.0e6
			_ = far_transmit_order(e, e.task_groups[0].position, i, order)
			task.delta_v_remaining_km_s = max(0, task.delta_v_remaining_km_s - 90)
			e.groups[i].maneuver_reserve = clamp(task.delta_v_remaining_km_s / 520 * 100, 0, 100)
		}
		e.arrival_hour += 1.5
		e.viable_course_margin_hours -= 1.5
		e.intercept_margin_hours += 3
		far_add_record(e, "The fleet shifted the projected intercept north.", 0, command)
	case .Branch_Formation:
		e.false_branch = true
		e.decoys = max(0, e.decoys - 1)
		e.result.decoys_spent += 1
		for task, i in e.task_groups[:e.task_group_count] {
			order := task.received_order
			order.formation = .Branched
			order.destination.y += f64(i - 1) * 2.2e6
			_ = far_transmit_order(e, e.task_groups[0].position, i, order)
		}
		far_add_record(
			e,
			"The fleet divided its signatures across two apparent courses.",
			0,
			command,
		)
	case .Launch_Shaping_Salvo:
		target := far_selected_truth_index(e)
		if target < 0 do return false
		e.heavy_ordnance -= 2
		e.result.heavy_ordnance_spent += 2
		result := far_launch_physical_weapon(e, true, 1, target, .Kinetic, 8)
		if !result.ok do return false
	case .Launch_Full_Salvo:
		target := far_selected_truth_index(e)
		if target < 0 do return false
		e.heavy_ordnance -= 5
		e.result.heavy_ordnance_spent += 5
		result := far_launch_physical_weapon(e, true, 1, target, .Guided_Missile, 20)
		if !result.ok do return false
	case .Hold_Ordnance:
		far_add_record(e, "Resolute withheld heavy ordnance.", 1, command)
	case .Maintain_Screen:
		for task, i in e.task_groups[:e.task_group_count] {
			order := task.received_order
			order.formation = .Screened
			_ = far_transmit_order(e, e.task_groups[0].position, i, order)
		}
		far_add_record(
			e,
			"Screening orders transmitted; local formations remain unchanged until receipt.",
			1,
			command,
		)
	case .Disperse_Fleet:
		for task, i in e.task_groups[:e.task_group_count] {
			order := task.received_order
			order.formation = .Dispersed
			order.destination.y += f64(i - 1) * 4.0e6
			_ = far_transmit_order(e, e.task_groups[0].position, i, order)
			e.task_groups[i].delta_v_remaining_km_s = max(
				0,
				e.task_groups[i].delta_v_remaining_km_s - 55,
			)
		}
		far_add_record(e, "The fleet dispersed beyond overlapping defensive fire.", 0, command)
	case .Deploy_Decoys:
		e.decoys -= 2
		e.result.decoys_spent += 2
		e.groups[0].signature_reserve = min(100, e.groups[0].signature_reserve + 18)
		far_add_record(e, "Common Hearth deployed two independent decoy trains.", 0, command)
	case .Expose_Screen:
		e.screen_exposed = true
		order := e.task_groups[1].received_order
		order.emission = .Illuminate
		// The screen's crossing is an actual course change, not a legacy display
		// velocity. The command still takes effect only once it reaches Resolute.
		order.destination.y -= 6.0e6
		_ = far_transmit_order(e, e.task_groups[0].position, 1, order)
		e.groups[1].signature_reserve = 8
		e.groups[1].maneuver_reserve = max(0, e.groups[1].maneuver_reserve - 30)
		far_add_record(
			e,
			"Resolute crossed the arrival corridor under active illumination.",
			1,
			command,
		)
	case .Break_Deadline:
		e.arrival_hour += 3.5
		e.viable_course_margin_hours -= 3.5
		e.task_groups[0].received_order.destination.y += 6.0e6
		far_add_record(
			e,
			"Common Hearth left the Passage course to retain the screen.",
			0,
			command,
		)
	case .Abandon_Screen:
		e.groups[1].state = .Separated
		e.groups[1].detached = true
		e.groups[1].formation = .Detached
		e.task_groups[1].received_order.verb = .Withdraw
		e.task_groups[1].received_order.destination = e.spec.route_origin
		far_add_record(e, "Common Hearth continued beyond Resolute's support range.", 0, command)
	case .Continue_Mission:
		e.passage_committed = true
		far_add_record(e, "The protected group continued toward the Passage.", 0, command)
	case .Dispatch_Recovery:
		e.recovery_committed = true
		e.groups[2].objective = .Recovery
		e.groups[2].maneuver_reserve = max(0, e.groups[2].maneuver_reserve - 24)
		order := e.task_groups[2].received_order
		order.verb = .Recover
		order.destination = e.task_groups[1].position
		_ = far_transmit_order(e, e.task_groups[0].position, 2, order)
		far_add_record(
			e,
			"Recovery order transmitted to Far Lantern; the screen remains where it fell until receipt.",
			2,
			command,
		)
	case .Signal_Disabled:
		e.groups[0].emission = .Relay
		e.groups[0].signature_reserve = max(0, e.groups[0].signature_reserve - 28)
		far_add_record(e, "Common Hearth opened a relay toward Resolute.", 0, command)
	case .Pursue:
		e.arrival_hour += 4
		e.viable_course_margin_hours -= 4
		e.enemy_formation = .Dispersed
		e.task_groups[1].received_order.verb = .Intercept
		e.task_groups[1].received_order.destination = e.truth_contacts[0].group.position
		far_add_record(e, "The fleet abandoned the arrival window and began pursuit.", 1, command)
	case .Withdraw:
		e.intercept_margin_hours += 6
		e.arrival_hour += 2
		for &task in e.task_groups[:e.task_group_count] {
			task.received_order.verb = .Withdraw
			task.received_order.destination = e.spec.route_origin
		}
		far_add_record(e, "The fleet withdrew from the intercept geometry.", 0, command)
	}
	_ = kind
	e.decision = {}
	e.paused_for_decision = false
	return true
}

far_resolve_default :: proc(e: ^Far_Engagement) -> bool {
	if !e.decision.pending do return false
	return far_resolve_decision(e, e.decision.commands[e.decision.default_option])
}

far_decision_required :: proc(e: ^Far_Engagement, commitment: bool, engagement := false) -> bool {
	switch e.authority {
	case .Report_Only:
		return false
	case .Confirm_Commitments:
		return commitment
	case .Confirm_Engagements:
		return commitment || engagement
	case .Direct_Command:
		return true
	}
	return true
}

far_finish :: proc(e: ^Far_Engagement) {
	if e.complete do return
	e.complete = true
	e.active = false
	e.phase = .Complete
	e.result.friendly_ships = 0
	e.result.ships_arrived = 0
	e.result.ships_disabled = 0
	e.result.ships_lost = 0
	for outcome in e.ship_outcomes[:e.ship_outcome_count] {
		if !outcome.friendly do continue
		e.result.friendly_ships += 1
		switch outcome.state {
		case .Destroyed, .Abandoned:
			e.result.ships_lost += 1
		case .Mission_Killed:
			e.result.ships_disabled += 1
		case .Recovered:
			e.result.ships_recovered += 1
			e.result.ships_arrived += 1
		case .Operational, .Recovering:
			e.result.ships_arrived += 1
		}
	}
	for &group, i in e.groups[:e.group_count] {
		task := e.task_groups[i]
		if !task.operational {
			group.state = .Disabled
		} else if far_distance(task.position, task.received_order.destination) <= 3.0e6 ||
		   e.objective_complete {
			group.state = .Arrived
		} else {
			group.state = .Separated
		}
	}
	e.result.deadline_kept = e.elapsed_seconds <= e.deadline_seconds + .01
	e.result.passage_reached = e.objective_complete && e.result.deadline_kept
	e.result.enemy_broken = true
	for truth in e.truth_contacts[:e.truth_contact_count] do if truth.active do e.result.enemy_broken = false
	if e.objective_complete {
		e.result.ending = fmt.tprintf(
			"%v objective completed with %d ships operational.",
			e.spec.objective_family,
			e.result.ships_arrived,
		)
	} else if e.result.ships_arrived > 0 {
		e.result.ending = fmt.tprintf(
			"%v objective failed; %d ships remain recoverable.",
			e.spec.objective_family,
			e.result.ships_arrived,
		)
	} else {
		e.result.ending = "The operational force was destroyed or abandoned before completing its objective."
	}
	far_add_record(e, e.result.ending, 0, .Accept_Standing_Orders, true)
	#partial switch e.opening_commitment {
	case .Hold_Protected_Course:
		far_add_record(
			e,
			fmt.tprintf(
				"PLAN CHECK · Passage hold ended with %s of route margin.",
				far_format_time(max(0, e.viable_course_margin_hours)),
			),
			0,
			.Hold_Protected_Course,
			true,
		)
	case .Shift_Intercept:
		far_add_record(
			e,
			fmt.tprintf(
				"PLAN CHECK · Intercept shift delayed the hostile launch window thirty minutes; route margin ended at %s.",
				far_format_time(max(0, e.viable_course_margin_hours)),
			),
			0,
			.Shift_Intercept,
			true,
		)
	case .Branch_Formation:
		far_add_record(
			e,
			fmt.tprintf(
				"PLAN CHECK · Branched course drew %d hostile flight(s) onto the screen branch.",
				e.hostile_flights_diverted,
			),
			1,
			.Branch_Formation,
			true,
		)
	}
}

far_step :: proc(e: ^Far_Engagement, dt_hours: f64) {
	far_step_physical(e, dt_hours * 3600)
}

far_tick :: proc(e: ^Far_Engagement, elapsed_hours: f64) {
	if elapsed_hours <= 0 || !e.active || e.complete || e.decision.pending || e.briefing_pending {
		return
	}
	e.fixed_accumulator += min(elapsed_hours, 24)
	for e.fixed_accumulator >= FAR_FIXED_STEP_HOURS && !e.decision.pending && !e.complete {
		far_step(e, FAR_FIXED_STEP_HOURS)
		e.fixed_accumulator -= FAR_FIXED_STEP_HOURS
	}
}

far_project_choice :: proc(
	e: ^Far_Engagement,
	command: Far_Command,
	horizon_hours := f64(2),
) -> (
	projection: Far_Choice_Projection,
) {
	if e == nil || !e.decision.pending || horizon_hours <= 0 do return
	branch := e^
	if !far_resolve_decision(&branch, command) do return
	end_seconds := min(branch.deadline_seconds, branch.elapsed_seconds + horizon_hours * 3600)
	for branch.active && !branch.complete && branch.elapsed_seconds < end_seconds {
		step := min(f64(.05), (end_seconds - branch.elapsed_seconds) / 3600)
		far_tick(&branch, step)
		if branch.decision.pending do _ = far_resolve_default(&branch)
	}
	projection.valid = true
	projection.objective_complete = branch.objective_complete
	projection.deadline_kept = branch.elapsed_seconds <= branch.deadline_seconds
	projection.horizon_seconds = branch.elapsed_seconds - e.elapsed_seconds
	projection.task_count = branch.task_group_count
	for group, i in branch.task_groups[:branch.task_group_count] do projection.task_positions[i] = group.position
	for belief in branch.beliefs[:branch.belief_count] do projection.track_confidence = max(projection.track_confidence, belief.confidence)
	for outcome in branch.ship_outcomes[:branch.ship_outcome_count] {
		if !outcome.friendly do continue
		if outcome.state == .Mission_Killed do projection.ships_disabled += 1
		if outcome.state == .Destroyed || outcome.state == .Abandoned do projection.ships_lost += 1
	}
	return
}

far_time_to_next_event :: proc(e: ^Far_Engagement) -> f64 {
	if e.decision.pending || e.complete || e.briefing_pending do return 0
	next_seconds := min(e.next_ai_plan_seconds, e.next_observation_seconds)
	for transmission in e.transmissions[:e.transmission_count] do if transmission.active && transmission.arrives_at_seconds > e.elapsed_seconds {
		next_seconds = min(next_seconds, transmission.arrives_at_seconds)
	}
	for flight in e.weapon_flights[:e.weapon_flight_count] do if flight.active && flight.predicted_arrival_seconds > e.elapsed_seconds {
		next_seconds = min(next_seconds, flight.predicted_arrival_seconds)
	}
	return max(0, next_seconds - e.elapsed_seconds) / 3600
}

// Time compression is reserved for a concrete in-flight process. It must not
// become an alternate way to run an otherwise quiet operation to its outcome.
far_can_advance_to_decision :: proc(e: ^Far_Engagement) -> bool {
	if e == nil || !e.active || e.complete || e.decision.pending || e.briefing_pending do return false
	for transmission in e.transmissions[:e.transmission_count] do if transmission.active && transmission.arrives_at_seconds > e.elapsed_seconds {
		return true
	}
	for flight in e.weapon_flights[:e.weapon_flight_count] do if flight.active && flight.predicted_arrival_seconds > e.elapsed_seconds {
		return true
	}
	return false
}

far_time_to_next_in_flight_event :: proc(e: ^Far_Engagement) -> f64 {
	next_seconds := e.deadline_seconds
	for transmission in e.transmissions[:e.transmission_count] do if transmission.active && transmission.arrives_at_seconds > e.elapsed_seconds {
		next_seconds = min(next_seconds, transmission.arrives_at_seconds)
	}
	for flight in e.weapon_flights[:e.weapon_flight_count] do if flight.active && flight.predicted_arrival_seconds > e.elapsed_seconds {
		next_seconds = min(next_seconds, flight.predicted_arrival_seconds)
	}
	return max(0, next_seconds - e.elapsed_seconds) / 3600
}

far_advance_to_decision :: proc(e: ^Far_Engagement) {
	if !far_can_advance_to_decision(e) do return
	until := far_time_to_next_in_flight_event(e)
	far_tick(e, max(FAR_FIXED_STEP_HOURS, min(until + FAR_FIXED_STEP_HOURS, .5)))
}

far_set_authority :: proc(e: ^Far_Engagement, authority: Far_Authority) {
	e.authority = authority
}

far_validate :: proc(e: ^Far_Engagement) -> bool {
	if e == nil do return false
	if !e.active && !e.complete && e.phase == .Dormant && e.group_count == 0 do return true
	if e.group_count < 1 ||
	   e.group_count > FAR_MAX_GROUPS ||
	   e.contact_count < 0 ||
	   e.contact_count > FAR_MAX_CONTACTS ||
	   e.record_count < 0 ||
	   e.record_count > FAR_MAX_RECORDS ||
	   e.heavy_ordnance < 0 ||
	   e.decoys < 0 ||
	   e.hour < 0 {
		return false
	}
	if e.schema_version != FAR_SCHEMA_VERSION ||
	   e.task_group_count < 1 ||
	   e.task_group_count > FAR_MAX_GROUPS ||
	   e.truth_contact_count < 0 ||
	   e.truth_contact_count > FAR_MAX_TRUTH_CONTACTS ||
	   e.belief_count < 0 ||
	   e.belief_count > FAR_MAX_CONTACTS ||
	   e.transmission_count < 0 ||
	   e.transmission_count > FAR_MAX_TRANSMISSIONS ||
	   e.weapon_flight_count < 0 ||
	   e.weapon_flight_count > FAR_MAX_SALVOS ||
	   e.ship_outcome_count < 0 ||
	   e.ship_outcome_count > FAR_MAX_SHIPS ||
	   e.elapsed_seconds < 0 ||
	   e.deadline_seconds <= 0 {
		return false
	}
	for task in e.task_groups[:e.task_group_count] {
		if task.stable_id == 0 ||
		   task.member_count < 0 ||
		   task.member_count > FAR_MAX_SHIPS ||
		   task.delta_v_remaining_km_s < 0 ||
		   task.max_acceleration_km_s2 < 0 {
			return false
		}
	}
	for group in e.groups[:e.group_count] {
		if group.id == 0 ||
		   group.ships < 0 ||
		   group.maneuver_reserve < 0 ||
		   group.maneuver_reserve > 100 ||
		   group.signature_reserve < 0 ||
		   group.signature_reserve > 100 ||
		   group.defensive_reserve < 0 ||
		   group.defensive_reserve > 100 {
			return false
		}
	}
	if e.decision.pending &&
	   (e.decision.option_count < 1 ||
			   e.decision.option_count > 4 ||
			   e.decision.default_option < 0 ||
			   e.decision.default_option >= e.decision.option_count) {
		return false
	}
	return true
}

far_apply_campaign_result :: proc(c: ^Campaign) -> bool {
	if c.far_engagement == nil do return false
	e := c.far_engagement
	if !e.complete || e.outcome_applied do return false
	e.outcome_applied = true
	primary := Ship_ID(0)
	for outcome in e.ship_outcomes[:e.ship_outcome_count] {
		if !outcome.friendly || outcome.ship_id == 0 do continue
		index := ship_index(c, outcome.ship_id)
		if index < 0 do continue
		ship := &c.ships[index]
		if primary == 0 do primary = ship.id
		if outcome.cause != "" do add_ship_history(c, ship.id, outcome.cause)
		ship.crew = i32(clamp(outcome.crew_surviving, 0, int(ship.crew)))
		switch outcome.state {
		case .Destroyed, .Abandoned:
			ship.damage = 10
			ship.active = false
			ship.departure = .Lost
		case .Mission_Killed:
			ship.damage = min(i32(10), ship.damage + 3)
		case .Recovered:
			ship.damage = min(i32(10), ship.damage + 2)
		case .Operational, .Recovering:
			if outcome.last_coupled_energy_j > 0 do ship.damage = min(i32(10), ship.damage + 1)
		}
	}
	event_kind :=
		e.result.ships_disabled + e.result.ships_lost > 0 ? Event_Kind.Ship_Damaged : .Expedition_Returned
	record_event(
		c,
		event_kind,
		e.result.ending,
		primary,
		i32(e.result.ships_disabled + e.result.ships_lost),
	)
	ships: [FAR_MAX_SHIPS]Ship_ID; ship_count := 0
	for outcome in e.ship_outcomes[:e.ship_outcome_count] {
		if outcome.friendly && outcome.ship_id != 0 && ship_count < len(ships) {
			ships[ship_count] = outcome.ship_id; ship_count += 1
		}
	}
	_ = apply_operation_return(
		c,
		.Far_Engagement,
		e.spec.seed,
		e.objective_complete && !e.objective_failed,
		ships[:ship_count],
		i64(e.elapsed_seconds),
		withdrawals = i32(max(e.result.friendly_ships - e.result.ships_arrived, 0)),
		protected_exposure = i32(e.result.ships_disabled + e.result.ships_lost),
		evidence = i32(e.transmission_count),
	)
	return true
}
