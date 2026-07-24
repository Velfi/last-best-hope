package game

import "core:fmt"
import "core:math"

far_default_spec :: proc(seed: u64) -> Far_Encounter_Spec {
	actual_seed := seed == 0 ? u64(1) : seed
	family := Far_Objective_Family(far_mix(actual_seed) % 5)
	complication := Far_Complication(1 + far_mix(actual_seed ~ 0x51f15e) % 7)
	return {
		schema_version      = FAR_SCHEMA_VERSION,
		seed                = actual_seed,
		objective_family    = family,
		complication        = complication,
		route_origin        = {0, 0},
		// Thirty million km keeps the conservative 520 km/s route inside the
		// standard eighteen-hour corridor; the old 36 Mkm route did not.
		route_destination   = {30.0e6, 0},
		deadline_seconds    = 18 * 3600,
		difficulty          = 1,
		friendly_count      = 9,
		enemy_count         = 6,
		known_contact_count = complication == .False_Contacts ? 3 : 2,
		friendly_faction    = "LAST FLEET",
		enemy_faction       = "UNKNOWN INTERCEPTOR",
	}
}

far_order_for_family :: proc(
	family: Far_Objective_Family,
	group_id: u32,
	destination: Far_Vec2,
	deadline_seconds: f64,
) -> Far_Operational_Order {
	verb := Far_Order_Verb.Break_Through
	switch family {
	case .Breakthrough:
		verb = .Break_Through
	case .Interception:
		verb = .Intercept
	case .Escort:
		verb = group_id == 1 ? .Escort : .Intercept
	case .Reconnaissance:
		verb = .Observe
	case .Withdrawal_Recovery:
		verb = group_id == 3 ? .Recover : .Withdraw
	}
	return {
		verb = verb,
		subject_group_id = group_id,
		destination = destination,
		boundary_center = destination,
		boundary_radius_km = 45.0e6,
		deadline_seconds = deadline_seconds,
		acceptable_loss = .15,
		ordnance_authorized = 4,
		decoys_authorized = 2,
		rescue_authorized = true,
		formation = .Screened,
		emission = .Passive,
	}
}

far_initialize_task_group :: proc(
	id: u32,
	position, velocity, destination: Far_Vec2,
	family: Far_Objective_Family,
) -> Far_Task_Group {
	order := far_order_for_family(family, id, destination, 18 * 3600)
	doctrine := id == 1 ? Far_Doctrine.Preserve_Force : id == 2 ? .Complete_At_Cost : .Balanced
	return {
		stable_id = id,
		order = order,
		received_order = order,
		doctrine = doctrine,
		posture = .Transit,
		reason = .Following_Order,
		position = position,
		velocity = velocity,
		max_acceleration_km_s2 = id == 1 ? .0035 : .0055,
		delta_v_remaining_km_s = id == 1 ? 350 : 520,
		sensor_power_w = id == 3 ? 9.0e8 : 3.5e8,
		radiator_capacity_w = 2.0e9,
		operational = true,
	}
}

far_sync_legacy_group :: proc(e: ^Far_Engagement, index: int) {
	if index < 0 || index >= e.task_group_count || index >= e.group_count do return
	task := &e.task_groups[index]
	group := &e.groups[index]
	group.id = task.stable_id
	group.position = {task.position.x / 1.0e6, task.position.y / 1.0e6}
	group.velocity = {task.velocity.x * 3600 / 1.0e6, task.velocity.y * 3600 / 1.0e6}
	group.desired_velocity = group.velocity
	group.maneuver_reserve = clamp(task.delta_v_remaining_km_s / 520 * 100, 0, 100)
	group.state = task.operational ? .Operational : .Disabled
}

far_generate_candidate :: proc(spec: Far_Encounter_Spec) -> (e: Far_Engagement) {
	actual := spec
	if actual.seed == 0 do actual.seed = 1
	if actual.schema_version == 0 do actual.schema_version = FAR_SCHEMA_VERSION
	if actual.deadline_seconds <= 0 do actual.deadline_seconds = 18 * 3600
	if actual.route_destination == (Far_Vec2{}) do actual.route_destination = {30.0e6, 0}
	e.schema_version = FAR_SCHEMA_VERSION
	e.spec = actual
	e.seed, e.rng = actual.seed, actual.seed
	e.active = true
	e.briefing_pending = true
	e.phase = .Find
	e.duration_seconds = actual.deadline_seconds + 4 * 3600
	e.deadline_seconds = actual.deadline_seconds
	e.duration_hours = e.duration_seconds / 3600
	e.deadline_hour = e.deadline_seconds / 3600
	e.arrival_hour = e.deadline_hour - .8
	e.protected_course = {actual.route_destination.x / 1.0e6, actual.route_destination.y / 1.0e6}
	e.projected_arrival = e.protected_course
	e.group_count, e.task_group_count = 3, 3
	e.contact_count, e.belief_count =
		min(actual.known_contact_count, FAR_MAX_CONTACTS),
		min(actual.known_contact_count, FAR_MAX_CONTACTS)
	e.truth_contact_count = 2
	if actual.complication == .Neutral_Traffic || actual.complication == .Uncertain_Reinforcement {
		e.truth_contact_count = 3
	}
	e.next_salvo_id, e.next_transmission_id = 1, 1
	e.authority = .Confirm_Commitments
	e.heavy_ordnance, e.decoys = 10, 6
	e.next_ai_plan_seconds = 30
	e.next_observation_seconds = 60
	e.next_enemy_launch_seconds = 2 * 3600
	e.groups[0] = {
		id                = 1,
		name              = "COMMON HEARTH",
		commander         = "Fleet command",
		objective         = .Preserve_Passage_Course,
		formation         = .Screened,
		emission          = .Passive,
		state             = .Operational,
		ships             = 3,
		protected         = true,
		signature_reserve = 82,
		defensive_reserve = 58,
		cohesion          = 88,
		hull              = 100,
	}
	e.groups[1] = {
		id                = 2,
		name              = "RESOLUTE SCREEN",
		commander         = "Screen command",
		objective         = .Screen,
		formation         = .Screened,
		emission          = .Passive,
		state             = .Operational,
		ships             = 3,
		signature_reserve = 70,
		defensive_reserve = 92,
		cohesion          = 84,
		hull              = 100,
	}
	e.groups[2] = {
		id                = 3,
		name              = "FAR LANTERN",
		commander         = "Recon command",
		objective         = .Screen,
		formation         = .Dispersed,
		emission          = .Silent,
		state             = .Operational,
		ships             = 3,
		signature_reserve = 96,
		defensive_reserve = 46,
		cohesion          = 76,
		hull              = 100,
	}
	friendly_destination :=
		actual.objective_family == .Withdrawal_Recovery ? actual.route_origin : actual.route_destination
	friendly_velocity := Far_Vec2{560, 0}
	group_0_position := Far_Vec2{0, 0}
	group_1_position := Far_Vec2{1.8e6, -2.2e6}
	group_2_position := Far_Vec2{-1.2e6, 3.6e6}
	if actual.objective_family == .Withdrawal_Recovery {
		// A withdrawal begins on the outward side of the corridor and already
		// carries return velocity. Reversing a 560 km/s outbound course would
		// require more delta-v than any generated group possesses.
		friendly_velocity = {-560, 0}
		group_0_position = {4.8e6, 0}
		group_1_position = {4.8e6, -.45e6}
		group_2_position = {4.8e6, .45e6}
	}
	e.task_groups[0] = far_initialize_task_group(
		1,
		group_0_position,
		friendly_velocity,
		friendly_destination,
		actual.objective_family,
	)
	e.task_groups[1] = far_initialize_task_group(
		2,
		group_1_position,
		friendly_velocity,
		friendly_destination,
		actual.objective_family,
	)
	e.task_groups[2] = far_initialize_task_group(
		3,
		group_2_position,
		friendly_velocity,
		friendly_destination,
		actual.objective_family,
	)
	if actual.complication == .Damaged_Drives {
		e.task_groups[0].delta_v_remaining_km_s *= .6
		e.task_groups[0].max_acceleration_km_s2 *= .7
	}
	for i in 0 ..< e.task_group_count do far_sync_legacy_group(&e, i)

	enemy_y := (far_rand(&e) - .5) * 8.0e6
	e.truth_contacts[0] = {
		stable_id         = 101,
		group             = far_initialize_task_group(
			101,
			{23.5e6, enemy_y - 2.8e6},
			{-320, 120},
			actual.route_origin,
			.Interception,
		),
		emission_power_w  = 4.0e8,
		projected_area_m2 = 4500,
		active            = true,
		hostile           = true,
	}
	e.truth_contacts[1] = {
		stable_id         = 102,
		group             = far_initialize_task_group(
			102,
			{25.5e6, enemy_y + 3.4e6},
			{-250, -80},
			actual.route_origin,
			.Interception,
		),
		emission_power_w  = 2.2e8,
		projected_area_m2 = 2400,
		active            = true,
		hostile           = true,
	}
	if actual.complication == .Neutral_Traffic {
		e.truth_contacts[2] = {
			stable_id         = 103,
			group             = far_initialize_task_group(
				103,
				{19.0e6, -5.5e6},
				{140, 35},
				actual.route_destination,
				.Escort,
			),
			emission_power_w  = 1.8e8,
			projected_area_m2 = 3200,
			active            = true,
			hostile           = false,
		}
	} else if actual.complication == .Uncertain_Reinforcement {
		e.truth_contacts[2] = {
			stable_id         = 103,
			group             = far_initialize_task_group(
				103,
				{31.0e6, 6.0e6},
				{-410, -90},
				actual.route_origin,
				.Interception,
			),
			emission_power_w  = 1.5e8,
			projected_area_m2 = 2800,
			active            = false,
			hostile           = true,
		}
		e.reinforcement_arrival_seconds = 6 * 3600
	}
	if actual.complication == .Divided_Objectives {
		e.task_groups[2].order.verb = .Observe
		e.task_groups[2].received_order = e.task_groups[2].order
		e.task_groups[2].order.destination = e.truth_contacts[1].group.position
		e.task_groups[2].received_order.destination = e.truth_contacts[1].group.position
	}
	if actual.complication == .Deteriorating_Deadline {
		e.deadline_seconds -= 2 * 3600
		e.deadline_hour = e.deadline_seconds / 3600
		far_add_record(&e, "The route window is closing two hours earlier than the nominal chart.")
	}
	// Orders carry the same authoritative deadline as the encounter. Complications
	// may revise that deadline after groups are initialized, so synchronize both
	// local intent and received standing orders before briefing.
	for &task in e.task_groups[:e.task_group_count] {
		task.order.deadline_seconds = e.deadline_seconds
		task.received_order.deadline_seconds = e.deadline_seconds
	}
	for i in 0 ..< e.belief_count {
		truth_index := min(i, e.truth_contact_count - 1)
		truth := e.truth_contacts[truth_index]
		false_contact := actual.complication == .False_Contacts && i == e.belief_count - 1
		offset_angle := far_rand(&e) * math.PI * 2
		error_km := 2.2e6 + far_rand(&e) * 2.4e6
		e.beliefs[i] = {
			stable_id             = u32(i + 1),
			observer_group_id     = 3,
			truth_id              = false_contact ? u32(0) : truth.stable_id,
			estimated_position    = {
				truth.group.position.x + math.cos(offset_angle) * error_km,
				truth.group.position.y + math.sin(offset_angle) * error_km,
			},
			estimated_velocity    = truth.group.velocity,
			uncertainty_radius_km = error_km,
			confidence            = .18 + far_rand(&e) * .12,
			active                = true,
		}
		e.contacts[i] = {
			id                 = false_contact ? u32(199) : truth.stable_id,
			name               = i == 0 ? "CONTACT AMBER" : i == 1 ? "CONTACT CINDER" : "CONTACT ECHO",
			identity           = .Signal,
			estimated_position = {
				e.beliefs[i].estimated_position.x / 1.0e6,
				e.beliefs[i].estimated_position.y / 1.0e6,
			},
			estimated_velocity = {
				e.beliefs[i].estimated_velocity.x * 3600 / 1.0e6,
				e.beliefs[i].estimated_velocity.y * 3600 / 1.0e6,
			},
			uncertainty_mkm    = e.beliefs[i].uncertainty_radius_km / 1.0e6,
			confidence         = e.beliefs[i].confidence,
			hostile            = false_contact || truth.hostile,
			active             = true,
		}
	}
	enemy_outcomes := e.truth_contact_count * 3
	friendly_count := min(max(actual.friendly_count, 9), FAR_MAX_SHIPS - enemy_outcomes)
	e.ship_outcome_count = friendly_count + enemy_outcomes
	hulls := [6]Ship_Hull_Archetype {
		.Habitat_Hull,
		.Destroyer,
		.Picket_Frigate,
		.Combat_Frigate,
		.Light_Cruiser,
		.Support_Frigate,
	}
	for i in 0 ..< friendly_count {
		id := actual.friendly_manifest[i]
		if id == 0 do id = Ship_ID(i + 1)
		hull := hulls[i % len(hulls)]
		e.ship_outcomes[i] = far_ship_physics_from_hull(id, hull, 180 + i * 12)
		group_index := i % e.task_group_count
		group := &e.task_groups[group_index]
		group.member_ids[group.member_count] = id
		group.member_count += 1
	}
	for i in 0 ..< enemy_outcomes {
		index := friendly_count + i
		e.ship_outcomes[index] = far_ship_physics_from_hull(
			0,
			hulls[(i + 1) % len(hulls)],
			120 + i * 8,
			false,
		)
		e.ship_outcomes[index].enemy_id = u64(1001 + i)
	}
	far_add_record(&e, "Briefing assembled from delayed route intelligence.")
	return
}

far_candidate_viable :: proc(e: ^Far_Engagement) -> bool {
	if e == nil || e.deadline_seconds <= 0 do return false
	// Validate the objective itself—not only one nominal route distance—under
	// the same deterministic standing plan available to a player who delegates
	// routine decisions. This includes all groups, actual delta-v, the selected
	// complication, and the objective's own terminal rule.
	trial := e^
	if !far_commit_briefing(&trial).ok do return false
	trial.authority = .Report_Only
	for trial.active && !trial.complete && trial.elapsed_seconds < trial.deadline_seconds {
		far_tick(&trial, .25)
		if trial.decision.pending do _ = far_resolve_default(&trial)
	}
	return trial.complete && trial.objective_complete && trial.result.deadline_kept
}

far_generate_encounter :: proc(spec: Far_Encounter_Spec) -> Far_Engagement {
	candidate_spec := spec
	for attempt in 0 ..< 16 {
		candidate_spec.seed = spec.seed + u64(attempt) * 0x9e3779b97f4a7c15
		candidate := far_generate_candidate(candidate_spec)
		if far_candidate_viable(&candidate) do return candidate
	}
	// If the requested complication cannot produce a viable standing plan, use
	// a deterministic baseline operation rather than emitting a known-losing
	// fallback. The record makes the reduced complexity visible.
	fallback_spec := spec
	fallback_spec.complication = .None
	for attempt in 0 ..< 16 {
		fallback_spec.seed = spec.seed + u64(attempt) * 0xd1b54a32d192ed03
		fallback := far_generate_candidate(fallback_spec)
		if far_candidate_viable(&fallback) {
			far_add_record(
				&fallback,
				"Generator deferred an invalid complication and issued a viable baseline operation.",
			)
			return fallback
		}
	}
	// This state should be unreachable. Preserve deterministic output and leave
	// a factual record if future rule changes violate the viability invariant.
	fallback := far_generate_candidate(fallback_spec)
	far_add_record(
		&fallback,
		"Generator exhausted its viability search; this operation requires review.",
	)
	return fallback
}

far_generate_campaign_encounter :: proc(
	c: ^Campaign,
	seed: u64,
	family := Far_Objective_Family.Breakthrough,
) -> Far_Engagement {
	spec := far_default_spec(seed)
	spec.objective_family = family
	spec.friendly_count = 0
	manifest_count :=
		c.combat_deployment_active ? c.combat_deployment_count : c.compact.active.seconded_count
	for i in 0 ..< manifest_count {
		index := ship_index(c, c.compact.active.seconded_ships[i])
		if c.combat_deployment_active do index = ship_index(c, c.combat_deployment_ships[i])
		if index < 0 || index >= c.ship_count do continue
		ship := c.ships[index]
		if !ship.active || ship.departure != .None do continue
		if spec.friendly_count >= FAR_MAX_SHIPS - 12 do break
		spec.friendly_manifest[spec.friendly_count] = ship.id
		spec.friendly_count += 1
	}
	e := far_generate_encounter(spec)
	if c != nil &&
	   (c.compact.active.status == .Planning || c.compact.active.status == .Operating) &&
	   c.compact.active.route == .Far_Engagement &&
	   c.compact.active.charter.valid {
		_ = apply_operation_authority_to_far_engagement(
			&e,
			c.compact.active.charter.hard_authority,
		)
		c.compact.active.status = .Operating
	}
	for i in 0 ..< e.ship_outcome_count {
		if !e.ship_outcomes[i].friendly do break
		index := ship_index(c, e.ship_outcomes[i].ship_id)
		if index < 0 do continue
		ship := c.ships[index]
		e.ship_outcomes[i] = far_ship_physics_from_hull(
			ship.id,
			ship.hull_archetype,
			int(ship.crew),
		)
		group_index := i % e.task_group_count
		e.task_groups[group_index].commander = ship.captain
		if i < e.group_count {
			e.groups[i].name = ship.name
			captain_index := historical_figure_index(c, ship.captain)
			if captain_index >= 0 do e.groups[i].commander = c.historical_figures[captain_index].name
		}
	}
	return e
}

far_migrate_legacy_engagement :: proc(e: ^Far_Engagement) {
	if e == nil || e.schema_version >= FAR_SCHEMA_VERSION do return
	if e.active && !e.complete {
		seed := e.seed
		e^ = far_generate_encounter(far_default_spec(seed))
		far_add_record(
			e,
			"Legacy interception replanned under physical simulation rules.",
			-1,
			.Accept_Standing_Orders,
			true,
		)
		return
	}
	e.schema_version = FAR_SCHEMA_VERSION
}

far_commit_briefing :: proc(e: ^Far_Engagement) -> Far_Command_Result {
	if !e.briefing_pending do return {false, "The operational plan is already committed."}
	if e.operation_authority.undertaking_id != 0 && !e.operation_authority.valid {
		return {
			false,
			"The Compact charter contains incomplete or contradictory operation authority.",
		}
	}
	for group in e.task_groups[:e.task_group_count] {
		if group.member_count <= 0 do return {false, "Every task group requires at least one persistent ship."}
		if group.order.deadline_seconds <= 0 do return {false, "Every task group requires a valid deadline."}
		allowed, clause := far_order_within_authority(&e.operation_authority, group.order)
		if !allowed &&
		   !operation_authority_allows_deviation(
				   &e.operation_authority,
				   group.order.authority_deviation_authorized,
			   ) {
			return {false, operation_authority_explanation(&e.operation_authority, clause)}
		}
	}
	e.briefing_pending = false
	e.briefing_committed = true
	far_add_record(
		e,
		"Standing orders committed. Command traffic now obeys light delay.",
		-1,
		.Accept_Standing_Orders,
		true,
	)
	return {true, ""}
}

far_set_task_group_doctrine :: proc(
	e: ^Far_Engagement,
	group_index: int,
	doctrine: Far_Doctrine,
) -> Far_Command_Result {
	if !e.briefing_pending do return {false, "Doctrine changes require a new delayed order after commitment."}
	if group_index < 0 || group_index >= e.task_group_count do return {false, "Unknown task group."}
	e.task_groups[group_index].doctrine = doctrine
	return {true, ""}
}

far_transfer_last_member :: proc(
	e: ^Far_Engagement,
	from_group, to_group: int,
) -> Far_Command_Result {
	if !e.briefing_pending do return {false, "The manifest is already committed."}
	if from_group < 0 ||
	   from_group >= e.task_group_count ||
	   to_group < 0 ||
	   to_group >= e.task_group_count ||
	   from_group == to_group {
		return {false, "Invalid task-group transfer."}
	}
	source := &e.task_groups[from_group]
	target := &e.task_groups[to_group]
	if source.member_count <= 1 do return {false, "A task group cannot be left empty."}
	if target.member_count >= FAR_MAX_SHIPS do return {false, "The destination group is full."}
	source.member_count -= 1
	target.member_ids[target.member_count] = source.member_ids[source.member_count]
	target.member_count += 1
	source.member_ids[source.member_count] = 0
	e.groups[from_group].ships = source.member_count
	e.groups[to_group].ships = target.member_count
	return {true, ""}
}

far_transmit_order :: proc(
	e: ^Far_Engagement,
	sender_position: Far_Vec2,
	group_index: int,
	order: Far_Operational_Order,
) -> Far_Command_Result {
	order_copy := order
	if group_index < 0 || group_index >= e.task_group_count do return {false, "Unknown task group."}
	allowed, clause := far_order_within_authority(&e.operation_authority, order_copy)
	if !allowed {
		if !operation_authority_allows_deviation(
			&e.operation_authority,
			order_copy.authority_deviation_authorized,
		) {
			return {false, operation_authority_explanation(&e.operation_authority, clause)}
		}
		order_copy.authority_breach = true
		order_copy.authority_breach_clause = clause
	}
	if e.transmission_count >= FAR_MAX_TRANSMISSIONS do return {false, "Command channel is saturated."}
	group := &e.task_groups[group_index]
	index := e.transmission_count
	delay := far_light_delay_seconds(sender_position, group.position)
	if e.spec.complication == .Command_Delay do delay *= 1.35
	e.transmissions[index] = {
		id                        = e.next_transmission_id,
		kind                      = .Order,
		sender_group_id           = 0,
		receiver_group_id         = group.stable_id,
		sent_at_seconds           = e.elapsed_seconds,
		arrives_at_seconds        = e.elapsed_seconds + delay,
		origin_position           = sender_position,
		receiver_position_at_send = group.position,
		order                     = order_copy,
		text                      = fmt.tprintf(
			"Order to group %d arrives in %s.",
			group.stable_id,
			far_format_time(delay / 3600),
		),
		emission_power_w          = 7.5e8,
		active                    = true,
	}
	e.transmission_count += 1
	e.next_transmission_id += 1
	far_add_record(e, e.transmissions[index].text, group_index)
	return {true, ""}
}

far_order_within_authority :: proc(
	authority: ^Operation_Authority,
	order: Far_Operational_Order,
) -> (
	bool,
	Operation_Authority_Clause,
) {
	if authority == nil || !authority.valid do return true, .None
	if !order.rescue_authorized && authority.rescue == .Absolute_Duty do return false, .Rescue
	if order.ordnance_authorized > 0 && authority.ordnance == .Defensive_Only do return false, .Ordnance
	if order.pursuit_authorized && authority.exposure == .Conservative do return false, .Exposure
	if order.acceptable_loss > .10 && authority.exposure == .Conservative do return false, .Exposure
	return true, .None
}

apply_operation_authority_to_far_engagement :: proc(
	e: ^Far_Engagement,
	authority: Operation_Authority,
) -> bool {
	if e == nil || !authority.valid do return false
	e.operation_authority = authority
	for &group in e.task_groups[:e.task_group_count] {
		switch authority.exposure {
		case .Conservative:
			group.doctrine = .Preserve_Force
			group.order.acceptable_loss = min(group.order.acceptable_loss, .10)
			group.order.pursuit_authorized = false
		case .Proportional:
			group.doctrine = .Balanced
			group.order.acceptable_loss = min(group.order.acceptable_loss, .25)
		case .Mission_Critical:
			group.doctrine = .Complete_At_Cost
		}
		group.order.rescue_authorized = authority.rescue != .Discretionary
		switch authority.ordnance {
		case .Defensive_Only:
			group.order.ordnance_authorized = 0
		case .Confirmed_Targets:
			group.order.ordnance_authorized = min(group.order.ordnance_authorized, 2)
		case .Unrestricted:
		}
		group.received_order = group.order
	}
	return true
}

far_deliver_transmissions :: proc(e: ^Far_Engagement) {
	for &transmission in e.transmissions[:e.transmission_count] {
		if !transmission.active ||
		   transmission.delivered ||
		   transmission.arrives_at_seconds > e.elapsed_seconds {
			continue
		}
		transmission.delivered = true
		transmission.active = false
		if transmission.kind == .Order {
			for &group, group_index in e.task_groups[:e.task_group_count] do if group.stable_id == transmission.receiver_group_id {
				previous_order := group.received_order
				group.received_order = transmission.order
				e.groups[group_index].formation = transmission.order.formation
				e.groups[group_index].emission = transmission.order.emission
				if transmission.order.formation == .Dispersed && previous_order.formation != .Dispersed {
					e.groups[group_index].cohesion = max(0, e.groups[group_index].cohesion - 12)
					e.fleet_disperse = true
				}
				if e.opening_commitment == .Shift_Intercept && group_index == 0 && !e.intercept_pressure_applied {
					e.intercept_pressure_applied = true
					e.next_enemy_launch_seconds += 1800
					far_add_record(e, "INTERCEPT RECEIPT · Common Hearth altered the hostile approach; the next hostile launch window slipped thirty minutes.", group_index, .Shift_Intercept, true)
				}
				if transmission.order.emission == .Illuminate {
					group.sensor_power_w = max(group.sensor_power_w, 2.1e9)
				}
				if group_index == 1 && e.screen_exposed {
					for &flight in e.weapon_flights[:e.weapon_flight_count] do if flight.active && !flight.friendly && !flight.acquired {
						flight.target_group_id = group.stable_id
						flight.target_estimate_position = group.position
						flight.target_estimate_velocity = group.velocity
					}
				}
				group.plan_revision += 1
				far_add_record(e, fmt.tprintf("ORDER RECEIVED · %s changed %v/%v to %v/%v after %s.", e.groups[group_index].name, previous_order.formation, previous_order.emission, transmission.order.formation, transmission.order.emission, far_format_time(transmission.arrives_at_seconds - transmission.sent_at_seconds)), group_index, .Accept_Standing_Orders, true)
				break
			}
		} else if transmission.kind == .Observation {
			for &belief in e.beliefs[:e.belief_count] do if belief.truth_id == transmission.belief.truth_id {
				belief = transmission.belief
				belief.received_at_seconds = e.elapsed_seconds
				break
			}
		}
	}
}

far_observe_contacts :: proc(e: ^Far_Engagement) {
	if e.elapsed_seconds < e.next_observation_seconds do return
	e.next_observation_seconds += 60
	observer := e.task_groups[min(2, e.task_group_count - 1)]
	for truth in e.truth_contacts[:e.truth_contact_count] {
		if !truth.active do continue
		distance := far_distance(observer.position, truth.group.position)
		emission_factor := truth.emission_power_w / 4.0e8
		signal := clamp(
			observer.sensor_power_w / 9.0e8 * emission_factor * 180.0e6 / max(distance, 1),
			.02,
			1,
		)
		for &belief, belief_index in e.beliefs[:e.belief_count] do if belief.truth_id == truth.stable_id {
			measurement_error := max(2.0e5, belief.uncertainty_radius_km * (1 - signal * .42))
			angle := far_rand(e) * math.PI * 2
			observation := Far_Contact_Belief {
				stable_id             = belief.stable_id,
				observer_group_id     = observer.stable_id,
				truth_id              = truth.stable_id,
				estimated_position    = {truth.group.position.x + math.cos(angle) * measurement_error, truth.group.position.y + math.sin(angle) * measurement_error},
				estimated_velocity    = truth.group.velocity,
				observed_at_seconds   = e.elapsed_seconds,
				uncertainty_radius_km = measurement_error,
				confidence            = clamp(belief.confidence + signal * .09, 0, 1),
				identified            = belief.confidence + signal * .09 >= .78,
				active                = true,
			}
			if e.transmission_count < FAR_MAX_TRANSMISSIONS {
				index := e.transmission_count
				e.transmissions[index] = {
					id                        = e.next_transmission_id,
					kind                      = .Observation,
					sender_group_id           = observer.stable_id,
					receiver_group_id         = 0,
					sent_at_seconds           = e.elapsed_seconds,
					arrives_at_seconds        = e.elapsed_seconds + far_light_delay_seconds(observer.position, e.task_groups[0].position),
					origin_position           = observer.position,
					receiver_position_at_send = e.task_groups[0].position,
					belief                    = observation,
					emission_power_w          = observer.sensor_power_w,
					active                    = true,
				}
				e.transmission_count += 1
				e.next_transmission_id += 1
			}
			_ = belief_index
			break
		}
	}
}
