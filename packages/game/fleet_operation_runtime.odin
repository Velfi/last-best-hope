package game

combat_target_priority_from_policy :: proc(policy: Combat_Target_Policy) -> Combat_Target_Priority {
	switch policy {
	case .Strike_Craft:
		return .Strike_Craft
	case .Support:
		return .Support
	case .Capitals:
		return .Capital
	case .Objective_Threats:
		return .Threats_To_Objective
	}
	return .Threats_To_Objective
}

combat_apply_doctrine_policy :: proc(group: ^Combat_Group, policy: Combat_Doctrine_Policy) {
	combat_apply_group_doctrine(group, policy.preset)
	group.emission_policy = policy.emissions
	group.priority = combat_target_priority_from_policy(policy.targets)
	group.objective_policy = policy.objective
	group.engagement_policy = policy.engagement
	group.cohesion_policy = policy.cohesion
	group.rescue_policy = policy.rescue
	group.ordnance_policy = policy.ordnance
	switch policy.pursuit {
	case .None:
		group.pursuit_limit = 0
	case .To_Boundary:
		group.pursuit_limit = 300
	case .Until_Disabled:
		group.pursuit_limit = 900
	}
	switch policy.withdrawal {
	case .Early:
		group.withdraw_threshold = 72
	case .Damaged:
		group.withdraw_threshold = 45
	case .Critical:
		group.withdraw_threshold = 20
	case .Never_Autonomous:
		group.withdraw_threshold = 0
	}
}

combat_operation_compile_mission :: proc(
	m: ^Combat_Mission,
	operation: ^Combat_Operation,
) -> bool {
	if m == nil || operation == nil || !operation.active ||
	   !operation.committed_plan.committed {
		return false
	}
	m.operation = operation^
	m.grid = operation.battlespace.grid
	m.fire_control = operation.committed_plan.fire_control
	m.extraction = operation.battlespace.extraction.center
	if operation.battlespace.objective_count > 0 do m.relays[0] = operation.battlespace.objective_positions[0]
	if operation.battlespace.objective_count > 1 do m.relays[1] = operation.battlespace.objective_positions[1]
	if operation.battlespace.objective_count > 2 {
		m.seedship = operation.battlespace.objective_positions[2]
		m.anomaly = operation.battlespace.objective_positions[2]
	}
	for interaction, index in m.interactions[:m.interaction_count] {
		if index < operation.battlespace.objective_count {
			m.interactions[index].position = operation.battlespace.objective_positions[index]
		}
	}
	for feature_index in 0 ..< min(3, operation.battlespace.feature_count) {
		feature := operation.battlespace.features[feature_index]
		kind := Combat_Terrain_Kind.Debris
		switch feature.kind {
		case .Open_Lane:
			kind = .Open_Lane
		case .Radiation:
			kind = .Radiation
		case .Debris, .Wreckage, .Sensor_Shadow, .Communication_Shadow:
			kind = .Debris
		}
		m.terrain[feature_index] = {
			kind = kind,
			center = feature.volume.center,
			radius = feature.volume.radius,
		}
	}
	plan := &m.operation.committed_plan
	for group_index in 0 ..< COMBAT_GROUP_COUNT {
		source := &plan.groups[group_index]
		target := &m.groups[group_index]
		if !source.active {
			target.name = ""
			target.objective = .Hold
			continue
		}
		target.name = combat_plan_group_name(source)
		target.objective = source.order
		target.destination =
			source.primary_route.waypoints[max(source.primary_route.count - 1, 0)]
		combat_apply_doctrine_policy(target, source.doctrine)
		target.operation_boundary = source.boundary
		target.boundary_enforced = true
		m.operation_route_cursor[group_index] = min(1, source.primary_route.count - 1)
	}
	for assignment in plan.assignments[:plan.assignment_count] {
		if assignment.unit_index < 0 || assignment.unit_index >= m.friendly_count do continue
		unit := &m.units[assignment.unit_index]
		unit.group = clamp(assignment.group, 0, COMBAT_GROUP_COUNT - 1)
		group_plan := plan.groups[unit.group]
		unit.position = group_plan.primary_route.waypoints[0]
		unit.position.y += f32((assignment.unit_index % 3) - 1) * 28
		unit.doctrine = group_plan.doctrine.preset
		unit.order = group_plan.order
		unit.destination =
			group_plan.primary_route.waypoints[min(1, max(group_plan.primary_route.count - 1, 0))]
		unit.tactical_destination = unit.destination
	}
	for group_index in 0 ..< COMBAT_GROUP_COUNT {
		group_plan := plan.groups[group_index]
		if !group_plan.active do continue
		combat_issue_group_order(
			m,
			group_index,
			group_plan.order,
			group_plan.primary_route.waypoints[min(1, max(group_plan.primary_route.count - 1, 0))],
		)
	}
	return true
}

combat_operation_withdraw_group :: proc(m: ^Combat_Mission, group_index: int) -> bool {
	if m == nil || !m.operation.committed_plan.committed ||
	   group_index < 0 || group_index >= COMBAT_GROUP_COUNT {
		return false
	}
	plan := &m.operation.committed_plan.groups[group_index]
	if !plan.active || m.operation_group_withdrawn[group_index] do return false
	m.operation_group_withdrawn[group_index] = true
	destination := m.extraction
	if plan.withdrawal_route.count > 0 {
		m.operation_route_cursor[group_index] = min(1, plan.withdrawal_route.count - 1)
		destination = plan.withdrawal_route.waypoints[m.operation_route_cursor[group_index]]
	}
	for &unit, index in m.units[:m.friendly_count] do if unit.group == group_index &&
	   !unit.disabled && !unit.extracted {
		combat_issue_order(m, index, .Withdraw, destination)
	}
	combat_add_event(m, "A task group began immediate withdrawal.")
	return true
}

combat_operation_withdraw_fleet :: proc(m: ^Combat_Mission) -> bool {
	if m == nil || !m.operation.committed_plan.committed do return false
	withdrew := false
	for group_index in 0 ..< COMBAT_GROUP_COUNT {
		if combat_operation_withdraw_group(m, group_index) do withdrew = true
	}
	return withdrew
}

combat_operation_advance_routes :: proc(m: ^Combat_Mission) {
	if m == nil || !m.operation.committed_plan.committed do return
	for group_index in 0 ..< COMBAT_GROUP_COUNT {
		group := m.operation.committed_plan.groups[group_index]
		if !group.active do continue
		route := m.operation_group_withdrawn[group_index] ? group.withdrawal_route : group.primary_route
		if route.count <= 0 do continue
		cursor := clamp(m.operation_route_cursor[group_index], 0, route.count - 1)
		center: Combat_Vec3
		active: f32
		for unit in m.units[:m.friendly_count] do if unit.group == group_index &&
		   !unit.disabled && !unit.extracted {
			center.x += unit.position.x
			center.y += unit.position.y
			center.z += unit.position.z
			active += 1
		}
		if active <= 0 do continue
		center.x /= active
		center.y /= active
		center.z /= active
		if combat_distance(center, route.waypoints[cursor]) < 65 &&
		   cursor < route.count - 1 {
			cursor += 1
			m.operation_route_cursor[group_index] = cursor
			order := m.operation_group_withdrawn[group_index] ? Combat_Order.Withdraw : group.order
			combat_issue_group_order(m, group_index, order, route.waypoints[cursor])
		}
	}
}

combat_operation_capture_continuity :: proc(m: ^Combat_Mission) -> Combat_Operation_Chain {
	chain := m.operation.chain
	chain.active = true
	chain.battle_index += 1
	chain.elapsed_time += m.time
	chain.ship_count = 0
	for assignment in m.operation.committed_plan.assignments[:m.operation.committed_plan.assignment_count] {
		if assignment.unit_index < 0 || assignment.unit_index >= m.friendly_count ||
		   chain.ship_count >= len(chain.ships) {
			continue
		}
		unit := m.units[assignment.unit_index]
		chain.ships[chain.ship_count] = {
			ship = assignment.ship,
			position = unit.position,
			velocity = unit.velocity,
			hull = unit.hull,
			torpedoes = unit.torpedoes,
			ability_charges = unit.ability_charges,
			disabled = unit.disabled,
			extracted = unit.extracted,
		}
		chain.ship_count += 1
	}
	chain.known_contact_count =
		min(m.operation.intelligence.contact_count, len(chain.known_contacts))
	for index in 0 ..< chain.known_contact_count {
		chain.known_contacts[index] = m.operation.intelligence.contacts[index]
		chain.known_contacts[index].uncertainty_radius =
			min(300, chain.known_contacts[index].uncertainty_radius + m.time / 120)
	}
	chain.wreckage_count = min(m.wreckage_field_count, len(chain.wreckage))
	for index in 0 ..< chain.wreckage_count do chain.wreckage[index] = m.wreckage_fields[index]
	chain.unresolved_count = 0
	for objective in m.skirmish_objectives.objectives[:m.skirmish_objectives.count] do if
	   !skirmish_objective_met(m, objective.kind) &&
	   chain.unresolved_count < len(chain.unresolved_objectives) {
		chain.unresolved_objectives[chain.unresolved_count] = objective
		chain.unresolved_count += 1
	}
	return chain
}

combat_operation_linked_draft :: proc(m: ^Combat_Mission) -> Combat_Operation {
	operation := m.operation
	operation.chain = combat_operation_capture_continuity(m)
	operation.operation_context = .Linked
	operation.seed = combat_mix(operation.seed ~ u64(operation.chain.battle_index))
	operation.draft = operation.committed_plan
	operation.draft.committed = false
	operation.draft.immutable = false
	operation.draft.id = combat_mix(operation.seed ~ 0x6c696e6b)
	operation.draft.revision = 1
	for assignment in operation.draft.assignments[:operation.draft.assignment_count] {
		if assignment.unit_index < 0 || assignment.unit_index >= m.friendly_count do continue
		group := &operation.draft.groups[assignment.group]
		if group.primary_route.count > 0 {
			group.primary_route.waypoints[0] = m.units[assignment.unit_index].position
		}
	}
	operation.committed_plan = {}
	operation.intelligence.contact_count = operation.chain.known_contact_count
	for index in 0 ..< operation.chain.known_contact_count {
		operation.intelligence.contacts[index] = operation.chain.known_contacts[index]
	}
	operation.draft.validation = combat_operation_validate_plan(&operation, &operation.draft)
	return operation
}

combat_operation_add_reachable_reinforcements :: proc(
	operation: ^Combat_Operation,
	c: ^Campaign,
) -> int {
	if operation == nil || c == nil || !operation.chain.active do return 0
	theater := ""
	for assignment in operation.draft.assignments[:operation.draft.assignment_count] do if
	   assignment.ship != 0 {
		at := ship_index(c, assignment.ship)
		if at >= 0 {
			theater = c.ships[at].current_position
			break
		}
	}
	if theater == "" do return 0
	added := 0
	for ship in c.ships[:c.ship_count] {
		if operation.draft.assignment_count >= len(operation.draft.assignments) do break
		if !ship.active || ship.departure != .None || ship.committed ||
		   ship.current_position != theater {
			continue
		}
		already := false
		for assignment in operation.draft.assignments[:operation.draft.assignment_count] do if
		   assignment.ship == ship.id {
			already = true
			break
		}
		if already do continue
		group := 6
		operation.draft.groups[group].active = true
		operation.draft.groups[group].reserve = true
		operation.draft.assignments[operation.draft.assignment_count] = {
			ship = ship.id,
			unit_index = min(operation.draft.assignment_count, COMBAT_GROUP_COUNT - 1),
			group = group,
			archetype = ship.hull_archetype,
		}
		operation.draft.assignment_count += 1
		added += 1
	}
	return added
}

combat_operation_prepare_linked_campaign :: proc(
	operation: ^Combat_Operation,
	c: ^Campaign,
) -> bool {
	if operation == nil || c == nil || !operation.chain.active do return false
	c.combat_deployment_active = true
	c.combat_deployment_count = 0
	c.combat_deployment_seed = operation.seed
	for assignment in operation.draft.assignments[:operation.draft.assignment_count] {
		if assignment.ship == 0 || ship_index(c, assignment.ship) < 0 do continue
		index := c.combat_deployment_count
		c.combat_deployment_ships[index] = assignment.ship
		c.combat_deployment_groups[index] = assignment.group
		c.combat_deployment_count += 1
	}
	return c.combat_deployment_count > 0
}

combat_operation_apply_continuity :: proc(m: ^Combat_Mission) {
	if m == nil || !m.operation.chain.active do return
	for carried in m.operation.chain.ships[:m.operation.chain.ship_count] {
		unit_index := -1
		for assignment in m.operation.committed_plan.assignments[:m.operation.committed_plan.assignment_count] do if
		   assignment.ship == carried.ship {
			unit_index = assignment.unit_index
			break
		}
		if unit_index < 0 || unit_index >= m.friendly_count do continue
		unit := &m.units[unit_index]
		unit.position = carried.position
		unit.velocity = carried.velocity
		unit.hull = clamp(carried.hull, 0, unit.max_hull)
		unit.torpedoes = carried.torpedoes
		unit.ability_charges = carried.ability_charges
		unit.disabled = carried.disabled
		unit.extracted = false
	}
	m.wreckage_field_count = min(m.operation.chain.wreckage_count, len(m.wreckage_fields))
	for index in 0 ..< m.wreckage_field_count {
		m.wreckage_fields[index] = m.operation.chain.wreckage[index]
	}
}

combat_operation_contingency_triggered :: proc(
	m: ^Combat_Mission,
	group_index: int,
	contingency: Combat_Plan_Contingency,
) -> bool {
	group := combat_group_state(m, .Friendly, group_index)
	switch contingency.trigger {
	case .Objective_Complete:
		objective_index := m.operation.committed_plan.groups[group_index].objective_index
		return objective_index >= 0 &&
			objective_index < m.skirmish_objectives.count &&
			skirmish_objective_met(m, m.skirmish_objectives.objectives[objective_index].kind)
	case .Protected_Group_Threatened:
		target := clamp(contingency.target_group, 0, COMBAT_GROUP_COUNT - 1)
		return m.groups[target].active_elements > 0 &&
			(m.groups[target].strength < .65 || m.groups[target].cohesion < 55)
	case .Capability_Lost:
		return group.active_elements <= 0 || group.strength < max(contingency.threshold / 100, f32(.25))
	case .Casualty_Threshold:
		return group.strength * 100 <= contingency.threshold
	case .Contact_Classified:
		for trace in m.group_contacts[combat_side_index(.Friendly)][group_index] do if trace.identity == .Identified do return true
	case .Route_Blocked:
		return group.escape_margin < 0
	case .Extraction_Window:
		return m.extraction_mandatory || m.time >= max(contingency.threshold, f32(1080))
	case .None:
	}
	return false
}

combat_operation_execute_contingencies :: proc(m: ^Combat_Mission) {
	if m == nil || !m.operation.committed_plan.committed do return
	for group_index in 0 ..< COMBAT_GROUP_COUNT {
		group := &m.operation.committed_plan.groups[group_index]
		if !group.active || m.operation_group_withdrawn[group_index] do continue
		for contingency_index in 0 ..< group.contingency_count {
			contingency := &group.contingencies[contingency_index]
			if !contingency.enabled ||
			   m.operation_contingency_fired[group_index][contingency_index] ||
			   !combat_operation_contingency_triggered(m, group_index, contingency^) {
				continue
			}
			if contingency.action == .Request_Exception &&
			   (m.request_pending || m.request_cooldown > 0) {
				continue
			}
			m.operation_contingency_fired[group_index][contingency_index] = true
			switch contingency.action {
			case .Follow_Fallback:
				if group.withdrawal_route.count > 0 do combat_issue_group_order(
					m,
					group_index,
					.Move,
					group.withdrawal_route.waypoints[0],
				)
			case .Screen_Group:
				target_group := clamp(contingency.target_group, 0, COMBAT_GROUP_COUNT - 1)
				for target, target_index in m.units[:m.friendly_count] do if target.group == target_group {
					combat_issue_group_order(m, group_index, .Guard, target.position, target_index)
					break
				}
			case .Commit_Reserve:
				if group.primary_route.count > 0 do combat_issue_group_order(
					m,
					group_index,
					group.order,
					group.primary_route.waypoints[group.primary_route.count - 1],
				)
			case .Disengage:
				_ = combat_operation_withdraw_group(m, group_index)
			case .Request_Exception:
				unit := -1
				for candidate, candidate_index in m.units[:m.friendly_count] do if candidate.group == group_index {
					unit = candidate_index
					break
				}
				if unit >= 0 do combat_surface_request(
					m,
					.Pursuit,
					unit,
					"Task group requests authority to depart from the committed doctrine.",
					"Approval changes the group's committed response to the current contact.",
				)
			case .None:
			}
		}
	}
}
