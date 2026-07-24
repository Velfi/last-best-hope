package game

import "core:fmt"
import "core:math"

far_preview_command :: proc(e: ^Far_Engagement, command: Far_Command) -> Far_Decision_Preview {
	preview := Far_Decision_Preview {
		known = true,
	}
	requester := clamp(e.decision.requesting_group, 0, e.task_group_count - 1)
	preview.command_delay_seconds = far_light_delay_seconds(
		e.task_groups[0].position,
		e.task_groups[requester].position,
	)
	#partial switch command {
	case .Illuminate:
		preview.uncertainty_change_km = -e.beliefs[0].uncertainty_radius_km * .35
	case .Detach_Baseline:
		preview.delta_v_cost_km_s = 35
		preview.uncertainty_change_km = -e.beliefs[0].uncertainty_radius_km * .18
	case .Shift_Intercept:
		preview.delta_v_cost_km_s = 90 * f64(e.task_group_count)
		preview.arrival_change_seconds = 5400
	case .Branch_Formation:
		preview.decoy_cost = 1
	case .Launch_Shaping_Salvo:
		preview.ordnance_cost = 2
		target := far_selected_truth_index(e)
		if target >= 0 {
			belief := e.beliefs[e.selected_belief]
			preview.weapon_flight_seconds =
				far_distance(e.task_groups[1].position, belief.estimated_position) / 1800
			preview.target_uncertainty_at_arrival_km =
				belief.uncertainty_radius_km +
				far_vec_length(belief.estimated_velocity) * preview.weapon_flight_seconds * .015 +
				preview.weapon_flight_seconds * .8
		}
	case .Launch_Full_Salvo:
		preview.ordnance_cost = 5
		target := far_selected_truth_index(e)
		if target >= 0 {
			belief := e.beliefs[e.selected_belief]
			preview.weapon_flight_seconds =
				far_distance(e.task_groups[1].position, belief.estimated_position) / 2800
			preview.target_uncertainty_at_arrival_km =
				belief.uncertainty_radius_km +
				far_vec_length(belief.estimated_velocity) * preview.weapon_flight_seconds * .015 +
				preview.weapon_flight_seconds * .8
		}
	case .Disperse_Fleet:
		preview.delta_v_cost_km_s = 55 * f64(e.task_group_count)
	case .Deploy_Decoys:
		preview.decoy_cost = 2
	case .Break_Deadline:
		preview.arrival_change_seconds = 12600
	case .Pursue:
		preview.arrival_change_seconds = 14400
	case .Withdraw:
		preview.arrival_change_seconds = 7200
	case:
	}
	return preview
}

far_set_selected_belief :: proc(e: ^Far_Engagement, index: int) -> bool {
	if index < 0 || index >= e.belief_count do return false
	e.selected_belief = index
	return true
}

far_selected_truth_index :: proc(e: ^Far_Engagement) -> int {
	if e.selected_belief < 0 || e.selected_belief >= e.belief_count do return -1
	truth_id := e.beliefs[e.selected_belief].truth_id
	for truth, i in e.truth_contacts[:e.truth_contact_count] do if truth.stable_id == truth_id && truth.hostile do return i
	return -1
}

far_plan_task_group :: proc(e: ^Far_Engagement, group: ^Far_Task_Group, hostile := false) {
	if !group.operational do return
	order := group.received_order
	to_destination := far_vec_sub(order.destination, group.position)
	distance := far_vec_length(to_destination)
	desired := far_vec_normalize(to_destination)
	desired_speed: f64 =
		group.doctrine == .Preserve_Force ? 520 : group.doctrine == .Complete_At_Cost ? 720 : 610
	group.posture, group.reason = .Transit, .Following_Order
	if order.verb == .Observe {
		group.posture, group.reason = .Shadow, .Building_Track
		desired_speed = 380
	} else if order.verb == .Escort {
		group.posture, group.reason = .Screen, .Protecting_Subject
	} else if order.verb == .Recover {
		group.posture, group.reason = .Recover, .Recovery_Possible
	} else if order.verb == .Withdraw {
		group.posture, group.reason = .Break_Contact, .Deadline_Threat
	}
	if hostile {
		group.posture = distance < 12.0e6 ? .Fire_And_Displace : .Intercept
		group.reason = distance < 12.0e6 ? .Firing_Solution : .Following_Order
	}
	target_velocity := far_vec_scale(desired, desired_speed)
	delta := far_vec_sub(target_velocity, group.velocity)
	required := far_vec_length(delta)
	if required > .000001 && group.delta_v_remaining_km_s > 0 {
		max_step := min(required, group.max_acceleration_km_s2 * 30)
		group.acceleration = far_vec_scale(far_vec_normalize(delta), max_step / 30)
	} else {
		group.acceleration = {}
	}
	group.last_plan_score = distance
	group.plan_revision += 1
	group.commitment_until_seconds = e.elapsed_seconds + 120
}

far_plan_ai :: proc(e: ^Far_Engagement) {
	if e.elapsed_seconds < e.next_ai_plan_seconds do return
	e.next_ai_plan_seconds += 30
	for &group in e.task_groups[:e.task_group_count] do far_plan_task_group(e, &group)
	for &truth in e.truth_contacts[:e.truth_contact_count] do if truth.active do far_plan_task_group(e, &truth.group, true)
}

far_integrate_task_group :: proc(group: ^Far_Task_Group, dt_seconds: f64) {
	if !group.operational do return
	dv := far_vec_scale(group.acceleration, dt_seconds)
	dv_length := far_vec_length(dv)
	if dv_length > group.delta_v_remaining_km_s {
		dv = far_vec_scale(far_vec_normalize(dv), group.delta_v_remaining_km_s)
		dv_length = group.delta_v_remaining_km_s
	}
	group.velocity = far_vec_add(group.velocity, dv)
	group.delta_v_remaining_km_s = max(0, group.delta_v_remaining_km_s - dv_length)
	group.position = far_vec_add(group.position, far_vec_scale(group.velocity, dt_seconds))
}

far_update_physical_groups :: proc(e: ^Far_Engagement, dt_seconds: f64) {
	for &group in e.task_groups[:e.task_group_count] do far_integrate_task_group(&group, dt_seconds)
	for &truth in e.truth_contacts[:e.truth_contact_count] do far_integrate_task_group(&truth.group, dt_seconds)
	for i in 0 ..< e.task_group_count do far_sync_legacy_group(e, i)
	for &belief, i in e.beliefs[:e.belief_count] {
		age := e.elapsed_seconds - belief.received_at_seconds
		belief.estimated_position = far_vec_add(
			belief.estimated_position,
			far_vec_scale(belief.estimated_velocity, dt_seconds),
		)
		belief.uncertainty_radius_km = min(
			90.0e6,
			belief.uncertainty_radius_km +
			far_vec_length(belief.estimated_velocity) * dt_seconds * .015 +
			age * .8,
		)
		e.contacts[i].estimated_position = {
			belief.estimated_position.x / 1.0e6,
			belief.estimated_position.y / 1.0e6,
		}
		e.contacts[i].estimated_velocity = {
			belief.estimated_velocity.x * 3600 / 1.0e6,
			belief.estimated_velocity.y * 3600 / 1.0e6,
		}
		e.contacts[i].uncertainty_mkm = belief.uncertainty_radius_km / 1.0e6
		e.contacts[i].confidence = belief.confidence
		e.contacts[i].identity =
			belief.identified ? .Confirmed_Interceptor : belief.confidence >= .55 ? .Probable_Capital : belief.confidence >= .32 ? .Track : .Signal
	}
}

far_launch_physical_weapon :: proc(
	e: ^Far_Engagement,
	friendly: bool,
	source_group_index, truth_index: int,
	weapon_type: Far_Weapon_Type,
	count: int,
) -> Far_Command_Result {
	if count <= 0 do return {false, "A launch requires at least one weapon."}
	if e.weapon_flight_count >= FAR_MAX_SALVOS do return {false, "No launch-control channel remains."}
	if friendly && (source_group_index < 0 || source_group_index >= e.task_group_count) do return {false, "Unknown launch group."}
	if truth_index < 0 || truth_index >= e.truth_contact_count do return {false, "No valid hostile track."}
	target_group_index := 0
	// A branched course is not merely a defensive modifier: it creates a second
	// plausible destination for a hostile track. Some deterministic enemy plans
	// commit to the screen branch, trading its exposure for the passage group's
	// safety.
	if !friendly &&
	   e.false_branch &&
	   e.groups[0].formation == .Branched &&
	   e.task_group_count > 1 &&
	   far_mix(e.seed ~ u64(e.weapon_flight_count)) % 2 == 0 {
		target_group_index = 1
	}
	source :=
		friendly ? e.task_groups[source_group_index].position : e.truth_contacts[truth_index].group.position
	target_truth := e.truth_contacts[truth_index]
	target_position :=
		friendly ? target_truth.group.position : e.task_groups[target_group_index].position
	target_velocity :=
		friendly ? target_truth.group.velocity : e.task_groups[target_group_index].velocity
	if !friendly {
		observation_delay := far_light_delay_seconds(source, target_position)
		target_position = far_vec_sub(
			target_position,
			far_vec_scale(target_velocity, observation_delay),
		)
		error_angle := far_rand(e) * math.PI * 2
		target_position.x += math.cos(error_angle) * 3.0e5
		target_position.y += math.sin(error_angle) * 3.0e5
	}
	if friendly {
		for belief in e.beliefs[:e.belief_count] do if belief.truth_id == target_truth.stable_id {
			if belief.confidence < .28 do return {false, "Track confidence is below launch authority."}
			target_position, target_velocity = belief.estimated_position, belief.estimated_velocity
			break
		}
	}
	distance := far_distance(source, target_position)
	speed: f64 =
		weapon_type == .Guided_Missile ? 2800 : weapon_type == .Kinetic ? 1800 : FAR_C_KM_S
	flight_seconds := distance / speed
	if weapon_type == .Laser && distance > 12.0e6 do return {false, "The target is beyond the beam's effective diffraction range."}
	if weapon_type == .Laser {
		target_position = far_vec_add(
			target_position,
			far_vec_scale(target_velocity, flight_seconds),
		)
	} else {
		relative := far_vec_sub(target_position, source)
		source_velocity :=
			friendly ? e.task_groups[source_group_index].velocity : target_truth.group.velocity
		relative_velocity := far_vec_sub(target_velocity, source_velocity)
		intercept, intercept_ok := far_intercept_time_seconds(relative, relative_velocity, speed)
		if intercept_ok {
			flight_seconds = intercept
			target_position = far_vec_add(
				target_position,
				far_vec_scale(target_velocity, intercept),
			)
		}
	}
	index := e.weapon_flight_count
	direction := far_vec_normalize(far_vec_sub(target_position, source))
	e.weapon_flights[index] = {
		id                        = e.next_salvo_id,
		weapon_type               = weapon_type,
		source_group_id           = friendly ? e.task_groups[source_group_index].stable_id : target_truth.stable_id,
		target_group_id           = friendly ? u32(0) : e.task_groups[target_group_index].stable_id,
		target_truth_id           = friendly ? target_truth.stable_id : u32(0),
		launch_position           = source,
		position                  = source,
		velocity                  = far_vec_add(
			far_vec_scale(direction, speed),
			friendly ? e.task_groups[source_group_index].velocity : target_truth.group.velocity,
		),
		target_estimate_position  = target_position,
		target_estimate_velocity  = target_velocity,
		launch_seconds            = e.elapsed_seconds,
		predicted_arrival_seconds = e.elapsed_seconds + flight_seconds,
		acceleration_km_s2        = weapon_type == .Guided_Missile ? .08 : 0,
		propellant_seconds        = weapon_type == .Guided_Missile ? 900 : 0,
		projectile_mass_kg        = weapon_type == .Guided_Missile ? 1200 : weapon_type == .Kinetic ? 420 : 0,
		explosive_yield_j         = weapon_type == .Guided_Missile ? 2.5e12 : 0,
		laser_power_w             = weapon_type == .Laser ? 8.0e11 : 0,
		laser_dwell_seconds       = weapon_type == .Laser ? 1.8 : 0,
		dispersion_radians        = weapon_type == .Kinetic ? 1.2e-6 : 4.0e-7,
		seeker_radius_km          = weapon_type == .Guided_Missile ? 1.8e6 : 0,
		weapons_launched          = count,
		weapons_surviving         = count,
		detected                  = friendly,
		friendly                  = friendly,
		active                    = true,
	}
	e.weapon_flight_count += 1
	e.next_salvo_id += 1
	if !friendly && target_group_index != 0 {
		e.hostile_flights_diverted += 1
		far_add_record(
			e,
			"Hostile guidance committed to the screen branch rather than the passage group.",
			target_group_index,
			.Branch_Formation,
			true,
		)
	}
	far_add_record(
		e,
		fmt.tprintf(
			"%d %v weapons launched; predicted flight %s.",
			count,
			weapon_type,
			far_format_time(flight_seconds / 3600),
		),
		source_group_index,
	)
	return {true, ""}
}

far_inbound_defense_profile :: proc(
	e: ^Far_Engagement,
	target_group_index: int,
) -> (
	formation_defense, decoy_bonus: f64,
) {
	if target_group_index < 0 || target_group_index >= e.group_count do return
	group := e.groups[target_group_index]
	formation_defense =
		group.formation == .Dispersed ? .72 : group.formation == .Branched ? .64 : group.formation == .Screened ? .52 : .38
	// Cohesion measures whether a formation can actually execute its planned
	// countermeasure geometry. Dispersion still lowers acquisition risk, but a
	// fragmented group loses some of that advantage as it struggles to share
	// tracks and defend its separated volumes.
	cohesion_factor := .65 + clamp(group.cohesion, 0, 100) / 100 * .35
	formation_defense *= cohesion_factor
	decoy_bonus = clamp(group.signature_reserve / 250, 0, .35)
	return
}

far_resolve_weapon_flight :: proc(e: ^Far_Engagement, flight: ^Far_Weapon_Flight) {
	if flight.resolved do return
	flight.resolved, flight.active = true, false
	if !flight.friendly {
		target_group_index := -1
		for group, i in e.task_groups[:e.task_group_count] do if group.stable_id == flight.target_group_id {target_group_index = i; break}
		if target_group_index < 0 do return
		target_group := &e.task_groups[target_group_index]
		miss_distance := far_distance(flight.position, target_group.position)
		acquisition :=
			flight.weapon_type == .Guided_Missile ? flight.seeker_radius_km : max(10.0, far_distance(flight.launch_position, target_group.position) * flight.dispersion_radians)
		flight.acquired = miss_distance <= acquisition
		if !flight.acquired {
			far_add_record(
				e,
				fmt.tprintf(
					"INBOUND %v RECEIPT · %d launched → no acquisition; missed by %.0f km.",
					flight.weapon_type,
					flight.weapons_launched,
					miss_distance,
				),
				target_group_index,
				.Accept_Standing_Orders,
				true,
			)
			return
		}
		formation_defense, decoy_bonus := far_inbound_defense_profile(e, target_group_index)
		survivors := max(
			0,
			int(math.round(f64(flight.weapons_surviving) * (1 - formation_defense - decoy_bonus))),
		)
		flight.weapons_surviving = survivors
		if survivors <= 0 {
			far_add_record(
				e,
				fmt.tprintf(
					"INBOUND %v RECEIPT · %d acquired → 0 penetrated; formation %.0f%% at %.0f%% cohesion plus %.0f%% decoys defeated the flight.",
					flight.weapon_type,
					flight.weapons_launched,
					formation_defense * 100,
					e.groups[target_group_index].cohesion,
					decoy_bonus * 100,
				),
				target_group_index,
				.Accept_Standing_Orders,
				true,
			)
			return
		}
		far_add_record(
			e,
			fmt.tprintf(
				"INBOUND %v RECEIPT · %d acquired → %d penetrated; formation %.0f%% at %.0f%% cohesion plus %.0f%% decoys.",
				flight.weapon_type,
				flight.weapons_launched,
				survivors,
				formation_defense * 100,
				e.groups[target_group_index].cohesion,
				decoy_bonus * 100,
			),
			target_group_index,
			.Accept_Standing_Orders,
			true,
		)
		for weapon_index in 0 ..< survivors {
			if target_group.member_count <= 0 do break
			member := int(
				far_mix(e.seed ~ u64(flight.id) ~ u64(weapon_index)) %
				u64(target_group.member_count),
			)
			ship_id := target_group.member_ids[member]
			target_index := -1
			for outcome, i in e.ship_outcomes[:e.ship_outcome_count] do if outcome.friendly && outcome.ship_id == ship_id {target_index = i; break}
			if target_index < 0 do continue
			outcome := &e.ship_outcomes[target_index]
			relative_velocity := far_vec_sub(flight.velocity, target_group.velocity)
			energy :=
				far_kinetic_energy_j(
					flight.projectile_mass_kg,
					far_vec_length(relative_velocity),
				) +
				flight.explosive_yield_j
			impact_area: f64 = .12
			if flight.weapon_type == .Laser {
				energy = flight.laser_power_w * flight.laser_dwell_seconds
				spot := far_laser_spot_radius_m(
					1.06e-6,
					18,
					far_distance(flight.launch_position, target_group.position),
					1.5e-8,
				)
				impact_area = math.PI * spot * spot
			}
			e.impact_serial += 1
			far_apply_physical_impact(
				outcome,
				flight.weapon_type,
				energy,
				impact_area,
				e.seed,
				e.impact_serial,
			)
			far_add_record(
				e,
				fmt.tprintf("%s: %s", e.groups[target_group_index].name, outcome.cause),
				target_group_index,
				.Accept_Standing_Orders,
				true,
			)
			if outcome.state == .Mission_Killed || outcome.state == .Destroyed {
				target_group.operational = false
				e.groups[target_group_index].state =
					outcome.state == .Destroyed ? .Lost : .Disabled
			}
		}
		return
	}
	target_truth_index := -1
	for truth, i in e.truth_contacts[:e.truth_contact_count] do if truth.stable_id == flight.target_truth_id {target_truth_index = i; break}
	if target_truth_index < 0 do return
	truth := &e.truth_contacts[target_truth_index]
	miss_distance := far_distance(flight.position, truth.group.position)
	acquisition :=
		flight.weapon_type == .Guided_Missile ? flight.seeker_radius_km : max(10.0, far_distance(flight.launch_position, truth.group.position) * flight.dispersion_radians)
	flight.acquired = miss_distance <= acquisition
	if !flight.acquired {
		far_add_record(
			e,
			fmt.tprintf(
				"%v RECEIPT · %d launched → no acquisition; target volume crossed by %.0f km.",
				flight.weapon_type,
				flight.weapons_launched,
				miss_distance,
			),
			-1,
			.Accept_Standing_Orders,
			true,
		)
		return
	}
	defense_fraction :=
		flight.weapon_type == .Guided_Missile ? .55 : flight.weapon_type == .Kinetic ? .18 : .04
	survivors := max(0, int(math.round(f64(flight.weapons_surviving) * (1 - defense_fraction))))
	flight.weapons_surviving = survivors
	if survivors <= 0 {
		far_add_record(
			e,
			fmt.tprintf(
				"%v RECEIPT · %d acquired → 0 penetrated; terminal defenses defeated the flight.",
				flight.weapon_type,
				flight.weapons_launched,
			),
			-1,
			.Accept_Standing_Orders,
			true,
		)
		return
	}
	far_add_record(
		e,
		fmt.tprintf(
			"%v RECEIPT · %d acquired → %d penetrated after terminal defense.",
			flight.weapon_type,
			flight.weapons_launched,
			survivors,
		),
		-1,
		.Accept_Standing_Orders,
		true,
	)
	enemy_outcome_count := e.truth_contact_count * 3
	target_start := e.ship_outcome_count - enemy_outcome_count + target_truth_index * 3
	for weapon_index in 0 ..< survivors {
		target_index :=
			target_start + int(far_mix(e.seed ~ u64(flight.id) ~ u64(weapon_index)) % 3)
		if target_index < 0 || target_index >= e.ship_outcome_count do continue
		outcome := &e.ship_outcomes[target_index]
		relative_velocity := far_vec_sub(flight.velocity, truth.group.velocity)
		energy :=
			far_kinetic_energy_j(flight.projectile_mass_kg, far_vec_length(relative_velocity)) +
			flight.explosive_yield_j
		impact_area: f64 = .12
		if flight.weapon_type == .Laser {
			energy = flight.laser_power_w * flight.laser_dwell_seconds
			spot := far_laser_spot_radius_m(
				1.06e-6,
				18,
				far_distance(flight.launch_position, truth.group.position),
				1.5e-8,
			)
			impact_area = math.PI * spot * spot
		}
		e.impact_serial += 1
		far_apply_physical_impact(
			outcome,
			flight.weapon_type,
			energy,
			impact_area,
			e.seed,
			e.impact_serial,
		)
		far_add_record(e, outcome.cause, -1, .Accept_Standing_Orders, true)
	}
	active_enemy := false
	for outcome in e.ship_outcomes[target_start:min(target_start + 3, e.ship_outcome_count)] do if outcome.state == .Operational do active_enemy = true
	if !active_enemy {
		truth.active = false
		truth.group.operational = false
	}
}

far_update_weapon_flights :: proc(e: ^Far_Engagement, dt_seconds: f64) {
	for &flight in e.weapon_flights[:e.weapon_flight_count] {
		if !flight.active do continue
		if flight.weapon_type == .Guided_Missile && flight.propellant_seconds > 0 {
			target := flight.target_estimate_position
			actual_target := target
			if flight.friendly {
				for truth in e.truth_contacts[:e.truth_contact_count] do if truth.stable_id == flight.target_truth_id {actual_target = truth.group.position; break}
			} else {
				for group in e.task_groups[:e.task_group_count] do if group.stable_id == flight.target_group_id {actual_target = group.position; break}
			}
			if far_distance(flight.position, actual_target) <= flight.seeker_radius_km {
				flight.acquired = true
				target = actual_target
			}
			desired := far_vec_normalize(far_vec_sub(target, flight.position))
			flight.velocity = far_vec_add(
				flight.velocity,
				far_vec_scale(desired, flight.acceleration_km_s2 * dt_seconds),
			)
			flight.propellant_seconds = max(0, flight.propellant_seconds - dt_seconds)
		}
		flight.position = far_vec_add(flight.position, far_vec_scale(flight.velocity, dt_seconds))
		progress :=
			(e.elapsed_seconds - flight.launch_seconds) /
			max(1, flight.predicted_arrival_seconds - flight.launch_seconds)
		if !flight.detected && progress >= .35 {
			flight.detected = true
			far_add_record(
				e,
				"Passive sensors resolved an inbound weapon flight.",
				-1,
				.Accept_Standing_Orders,
				true,
			)
		}
		if e.elapsed_seconds >= flight.predicted_arrival_seconds do far_resolve_weapon_flight(e, &flight)
	}
}

far_projected_arrival_seconds :: proc(e: ^Far_Engagement, group_index: int) -> (f64, bool) {
	if group_index < 0 || group_index >= e.task_group_count do return 0, false
	group := e.task_groups[group_index]
	distance := far_distance(group.position, group.received_order.destination)
	speed := far_vec_length(group.velocity)
	if speed <= .0001 do return 0, false
	return e.elapsed_seconds + distance / speed, true
}

far_objective_eta_seconds :: proc(e: ^Far_Engagement) -> (f64, bool) {
	if e == nil || e.task_group_count <= 0 do return 0, false
	switch e.spec.objective_family {
	case .Breakthrough, .Escort:
		return far_projected_arrival_seconds(e, 0)
	case .Withdrawal_Recovery:
		latest: f64
		for group in e.task_groups[:e.task_group_count] {
			if !group.operational do continue
			distance := far_distance(group.position, e.spec.route_origin)
			speed := far_vec_length(group.velocity)
			if speed <= .0001 do return 0, false
			latest = max(latest, e.elapsed_seconds + distance / speed)
		}
		return latest, latest > 0
	case .Reconnaissance, .Interception:
		// These objectives depend on future contact behavior rather than a fixed
		// destination. Present a branch forecast instead of a false single ETA.
		return 0, false
	}
	return 0, false
}

far_update_objective_state :: proc(e: ^Far_Engagement) {
	switch e.spec.objective_family {
	case .Breakthrough, .Escort:
		e.objective_complete =
			far_distance(e.task_groups[0].position, e.spec.route_destination) <= 2.0e6
	case .Interception:
		any_hostile := false
		for truth in e.truth_contacts[:e.truth_contact_count] do if truth.active && truth.hostile do any_hostile = true
		if e.spec.complication == .Uncertain_Reinforcement &&
		   e.elapsed_seconds < e.reinforcement_arrival_seconds {
			any_hostile = true
		}
		e.objective_complete = !any_hostile
	case .Reconnaissance:
		identified := false
		for belief in e.beliefs[:e.belief_count] do if belief.identified do identified = true
		separation := far_distance(
			e.task_groups[min(2, e.task_group_count - 1)].position,
			e.truth_contacts[0].group.position,
		)
		// Reconnaissance must first enter the observation volume, then leave it
		// with a confirmed track. This keeps the opening, sensor, and defensive
		// choices in play instead of ending the operation at its initial standoff.
		if separation <= 15.0e6 do e.stage_contact = true
		e.objective_complete = e.stage_contact && identified && separation >= 20.0e6
	case .Withdrawal_Recovery:
		safe := true
		for group in e.task_groups[:e.task_group_count] do if group.operational && far_distance(group.position, e.spec.route_origin) > 3.0e6 {
			safe = false
		}
		e.objective_complete = safe
	}
	if e.objective_complete do far_finish(e)
}

far_update_recovery :: proc(e: ^Far_Engagement) {
	if !e.recovery_committed || e.recovery_completed || e.task_group_count < 3 do return
	if e.task_groups[2].received_order.verb != .Recover ||
	   far_distance(e.task_groups[2].position, e.task_groups[1].position) > 3.0e6 {
		return
	}
	recovered := 0
	for ship_id in e.task_groups[1].member_ids[:e.task_groups[1].member_count] {
		for &outcome in e.ship_outcomes[:e.ship_outcome_count] do if outcome.friendly && outcome.ship_id == ship_id && outcome.state == .Mission_Killed {
			outcome.state = .Recovered
			recovered += 1
		}
	}
	if recovered <= 0 do return
	e.recovery_completed = true
	e.task_groups[1].operational = true
	e.task_groups[2].received_order = e.task_groups[2].order
	e.groups[1].state, e.groups[2].objective = .Operational, .Screen
	far_add_record(
		e,
		fmt.tprintf(
			"RECOVERY RECEIPT · Far Lantern recovered %d disabled screen ship(s); both groups resumed the route.",
			recovered,
		),
		2,
		.Dispatch_Recovery,
		true,
	)
}

far_evaluate_physical_events :: proc(e: ^Far_Engagement) {
	if e.decision.pending || e.complete do return
	if !e.opening_commitment_resolved {
		e.opening_commitment_resolved = true
		far_raise_decision(
			e,
			.Opening_Commitment,
			"OPENING COMMITMENT",
			"Before the next report, choose whether the fleet preserves its passage course, shifts toward the hostile volume, or divides its apparent route.",
			"This commitment establishes the first operational problem; later reports show whether it created time, contact quality, or exposure.",
			{.Hold_Protected_Course, .Shift_Intercept, .Branch_Formation},
			{"HOLD PASSAGE", "SHIFT INTERCEPT", "BRANCH COURSE"},
			{
				"Preserve the route margin and leave the hostile volume uncertain.",
				"Spend fleet delta-v to improve the projected intercept at the cost of arrival margin.",
				"Spend one decoy train to present two routes; the groups must receive the order before they separate.",
			},
			0,
			0,
		)
		if !far_decision_required(e, true) do _ = far_resolve_default(e)
		return
	}
	best_confidence: f64
	for belief in e.beliefs[:e.belief_count] do best_confidence = max(best_confidence, belief.confidence)
	if !e.first_track_decision && best_confidence >= .32 {
		e.first_track_decision = true
		far_raise_decision(
			e,
			.Contact_Interpretation,
			"DELAYED CONTACT REPORT",
			"Far Lantern's observation has reached command. The hostile volume is still expanding between reports.",
			"Active illumination improves the next observation but reveals the observer at light speed.",
			{.Remain_Passive, .Illuminate, .Detach_Baseline},
			{"REMAIN PASSIVE", "ILLUMINATE", "EXTEND BASELINE"},
			{
				"Preserve ambiguity; accept wider future error.",
				"Increase sensor power and expose Far Lantern.",
				"Separate the observer from mutual defense.",
			},
			0,
			2,
		)
		if !far_decision_required(e, false) do _ = far_resolve_default(e)
		return
	}
	combat_objective :=
		e.spec.objective_family == .Breakthrough ||
		e.spec.objective_family == .Interception ||
		e.spec.objective_family == .Escort
	if combat_objective && !e.first_fire_decision && best_confidence >= .55 {
		e.first_fire_decision = true
		e.phase = .Shape
		far_raise_decision(
			e,
			.Launch_Authorization,
			"PHYSICAL FIRING SOLUTION",
			"A delayed track supports a long-range launch. The target may maneuver before arrival.",
			fmt.tprintf(
				"%d heavy weapons remain. Kinetic fire cannot correct after launch; missiles can spend propellant to pursue.",
				e.heavy_ordnance,
			),
			{.Launch_Shaping_Salvo, .Launch_Full_Salvo, .Hold_Ordnance},
			{"KINETIC SALVO", "GUIDED MISSILES", "WITHHOLD"},
			{
				"Spend 2 units on a ballistic prediction.",
				"Spend 5 units on guided weapons with finite propellant.",
				"Retain weapons and the current ambiguity.",
			},
			2,
			1,
		)
		if !far_decision_required(e, true) do _ = far_resolve_default(e)
		return
	}
	incoming := false
	for flight in e.weapon_flights[:e.weapon_flight_count] do if flight.active && !flight.friendly && flight.detected do incoming = true
	if !e.first_defense_decision && incoming {
		e.first_defense_decision = true
		e.phase = .Commit
		far_raise_decision(
			e,
			.Defensive_Shaping,
			"INBOUND ACQUISITION VOLUME",
			"A hostile flight is visible. Its seeker geometry, not a damage schedule, determines what it can acquire.",
			"Formation changes transmitted now may arrive after local captains begin terminal defense.",
			{.Maintain_Screen, .Disperse_Fleet, .Deploy_Decoys},
			{"MAINTAIN SCREEN", "DISPERSE", "DEPLOY DECOYS"},
			{
				"Keep overlapping defense.",
				"Spend delta-v to separate target volumes.",
				"Spend 2 decoy trains to enlarge false acquisition volumes.",
			},
			0,
			0,
		)
		if !far_decision_required(e, true) do _ = far_resolve_default(e)
		return
	}
	if !e.first_recovery_decision {
		disabled_screen := false
		for ship_id in e.task_groups[1].member_ids[:e.task_groups[1].member_count] {
			for outcome in e.ship_outcomes[:e.ship_outcome_count] do if outcome.friendly && outcome.ship_id == ship_id && outcome.state == .Mission_Killed do disabled_screen = true
		}
		if disabled_screen {
			e.first_recovery_decision, e.phase = true, .Interpret
			far_raise_decision(
				e,
				.Recovery_Commitment,
				"DISABLED SCREEN CONTACT",
				"A screen ship remains recoverable outside the passage route. Far Lantern can turn back, or the fleet can retain its time margin.",
				"Recovery spends Far Lantern's maneuver reserve and delays its return to the route; continuing leaves the disabled ship behind.",
				{.Dispatch_Recovery, .Continue_Mission, .Signal_Disabled},
				{"DISPATCH RECOVERY", "CONTINUE PASSAGE", "OPEN RELAY"},
				{
					"Order Far Lantern to recover the disabled screen ship.",
					"Preserve the route and leave the disabled screen ship behind.",
					"Spend signature reserve to relay the screen's status while retaining the route.",
				},
				1,
				2,
			)
			if !far_decision_required(e, true) do _ = far_resolve_default(e)
			return
		}
	}
	far_update_objective_state(e)
	if e.complete do return
	if e.elapsed_seconds >= e.deadline_seconds && !e.objective_complete {
		e.objective_failed = true
		far_finish(e)
	}
}

far_step_physical :: proc(e: ^Far_Engagement, dt_seconds: f64) {
	if !e.active || e.complete || e.decision.pending || e.briefing_pending do return
	e.elapsed_seconds += dt_seconds
	e.hour = e.elapsed_seconds / 3600
	if e.spec.complication == .Uncertain_Reinforcement &&
	   e.truth_contact_count >= 3 &&
	   !e.truth_contacts[2].active &&
	   e.elapsed_seconds >= e.reinforcement_arrival_seconds {
		e.truth_contacts[2].active = true
		far_add_record(
			e,
			"A previously unresolved drive group entered the observable volume.",
			-1,
			.Accept_Standing_Orders,
			true,
		)
	}
	far_deliver_transmissions(e)
	far_observe_contacts(e)
	far_plan_ai(e)
	far_update_physical_groups(e, dt_seconds)
	far_update_recovery(e)
	far_update_weapon_flights(e, dt_seconds)
	// Hostile launch is causal: a real track must enter a reachable firing volume,
	// and the same weapon constraints used by the player select the valid family.
	hostile_flight_active := false
	for flight in e.weapon_flights[:e.weapon_flight_count] do if flight.active && !flight.friendly do hostile_flight_active = true
	if !hostile_flight_active && e.elapsed_seconds >= e.next_enemy_launch_seconds {
		distance := far_distance(e.truth_contacts[0].group.position, e.task_groups[0].position)
		if distance <= 24.0e6 {
			weapon := Far_Weapon_Type.Guided_Missile
			if distance <= 12.0e6 {
				weapon = .Laser
			} else if far_mix(e.seed ~ u64(e.weapon_flight_count)) % 2 == 0 {
				weapon = .Kinetic
			}
			count := weapon == .Laser ? 1 : weapon == .Kinetic ? 5 : 8
			_ = far_launch_physical_weapon(e, false, 0, 0, weapon, count)
			e.next_enemy_launch_seconds = e.elapsed_seconds + 3 * 3600
		}
	}
	far_evaluate_physical_events(e)
}

far_command_name :: proc(value: Far_Order_Verb) -> string {
	switch value {
	case .Break_Through:
		return "BREAK THROUGH"
	case .Intercept:
		return "INTERCEPT"
	case .Escort:
		return "ESCORT"
	case .Observe:
		return "OBSERVE"
	case .Withdraw:
		return "WITHDRAW"
	case .Recover:
		return "RECOVER"
	}
	return "UNKNOWN"
}
