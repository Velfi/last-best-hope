package game

import "core:fmt"
import "core:math"

combat_doctrine_rules :: proc(
	d: Combat_Doctrine,
) -> (
	withdraw, pursuit: f32,
	priority: Combat_Target_Priority,
) {
	switch d {
	case .Cautious_Screen:
		return 55, 150, .Threats_To_Objective
	case .Balanced:
		return 30, 240, .Threats_To_Objective
	case .Hunter_Killer:
		return 20, 390, .Support
	case .Last_Stand:
		return 0, 520, .Capital
	}
	return 30, 240, .Threats_To_Objective
}
combat_set_doctrine :: proc(m: ^Combat_Mission, index: int, d: Combat_Doctrine) {if index >= 0 &&
	   index < m.friendly_count {m.units[index].doctrine = d; g := m.units[index].group
		combat_apply_group_doctrine(&m.groups[g], d)}}

combat_set_stance :: proc(m: ^Combat_Mission, index: int, stance: Combat_Stance) {
	if index < 0 || index >= m.friendly_count do return
	m.units[index].stance = stance
	group := m.units[index].group
	if group < 0 || group >= COMBAT_GROUP_COUNT do return
	first := true
	common := stance
	for unit in m.units[:m.friendly_count] do if unit.group == group {
		if first {
			common = unit.stance
			first = false
		} else if unit.stance != common {
			return
		}
	}
	m.groups[group].stance = common
}

combat_command_action :: proc(order: Combat_Order) -> Combat_Command_Action {
	switch order {
	case .Move, .Intercept:
		return .Move
	case .Control, .Recover:
		return .Act
	case .Attack:
		return .Attack
	case .Withdraw, .Extract:
		return .Withdraw
	case .Hold, .Guard:
		return .Hold
	}
	return .Hold
}

combat_add_interaction :: proc(m: ^Combat_Mission, interaction: Combat_Interaction) -> int {
	if m.interaction_count >= COMBAT_MAX_INTERACTIONS do return -1
	index := m.interaction_count
	m.interactions[index] = interaction
	m.interactions[index].active = true
	m.interaction_count += 1
	return index
}

combat_interaction_available :: proc(m: ^Combat_Mission, index: int) -> bool {
	if index < 0 || index >= m.interaction_count do return false
	interaction := &m.interactions[index]
	if !interaction.active || interaction.complete do return false
	switch interaction.kind {
	case .Capture:
		return(
			interaction.target >= 0 &&
			interaction.target < len(m.relay_progress) &&
			m.relay_progress[interaction.target] < 100 \
		)
	case .Recover:
		return m.seedship_found && !m.fabrication_recovered
	case .Rescue:
		return(
			interaction.target >= 0 &&
			interaction.target < m.friendly_count &&
			m.units[interaction.target].disabled \
		)
	case .Scan:
		return m.anomaly_progress < 100
	case .Salvage:
		return !m.fabrication_recovered
	case .Deploy:
		return(
			interaction.target >= 0 &&
			interaction.target < len(m.relay_progress) &&
			m.relay_progress[interaction.target] < 100 \
		)
	case .Repair:
		return(
			interaction.target >= 0 &&
			interaction.target < m.friendly_count &&
			m.units[interaction.target].disabled \
		)
	case .Escort:
		return true
	case .None:
		return false
	}
	return false
}

combat_issue_interaction :: proc(
	m: ^Combat_Mission,
	index: int,
	kind: Combat_Interaction_Kind,
	destination: Combat_Vec3,
	target := -1,
) {
	#partial switch kind {
	case .Capture, .Scan, .Deploy:
		combat_issue_order(m, index, .Control, destination, target)
	case .Recover, .Salvage:
		combat_issue_order(m, index, .Recover, destination, -1)
	case .Rescue, .Repair:
		combat_issue_order(m, index, .Recover, destination, target)
	case .Escort:
		combat_issue_order(m, index, .Guard, destination, target)
		if index >= 0 && index < m.friendly_count do m.units[index].guard = target
	case .None:
	}
}

combat_issue_order :: proc(
	m: ^Combat_Mission,
	index: int,
	order: Combat_Order,
	destination: Combat_Vec3,
	target := -1,
) {if index < 0 || index >= m.friendly_count do return; u := &m.units[index]; if u.disabled || u.extracted do return
	if order == .Guard || order == .Intercept do u.stance = .Screen
	if order == .Attack && target >= 0 {u.engagement_target = target; u.denied_target = -1
		u.costly_denied_target = -1}
	else if order != u.order || target != u.target {u.engagement_target = -1; u.denied_target = -1
		u.costly_denied_target = -1}
	u.order = order
	u.destination = destination
	u.target = target
	u.withdrawing = order == .Withdraw || order == .Extract
	switch order {
	case .Hold:
		u.maneuver_intent = .Hold_Geometry
	case .Move:
		u.maneuver_intent = .Approach_Objective
	case .Guard:
		u.maneuver_intent = .Screen_Element
	case .Control, .Recover:
		u.maneuver_intent = .Approach_Objective
	case .Intercept:
		u.maneuver_intent = .Intercept_Salvo
	case .Attack:
		u.maneuver_intent = .Close_To_Envelope
	case .Withdraw, .Extract:
		u.maneuver_intent = .Withdraw
	}
	u.trajectory_forecast = combat_trajectory_forecast(
		u.position,
		u.velocity,
		destination,
		u.max_acceleration,
		u.speed,
	)
	u.action =
		order == .Guard ? .Screening : order == .Control ? .Capturing : order == .Extract ? .Extracting : .Navigating}
combat_issue_group_order :: proc(
	m: ^Combat_Mission,
	group: int,
	order: Combat_Order,
	destination: Combat_Vec3,
	target := -1,
) {if group < 0 || group >= COMBAT_GROUP_COUNT do return; g := &m.groups[group]; g.objective =
		order
	g.destination = destination
	g.target = target
	for &u, i in m.units[:m.friendly_count] do if u.group == group do combat_issue_order(m, i, order, destination, target)}
combat_surface_request :: proc(
	m: ^Combat_Mission,
	kind: Combat_Request_Kind,
	unit: int,
	text, consequence: string,
	target := -1,
) {if m.request_pending || m.request_cooldown > 0 do return; m.request_kind = kind
	m.request_unit = unit
	m.request_target = target
	m.request_text = text
	m.request_consequence = consequence
	m.request_timer = 12
	m.request_pending = true}
combat_request_default :: proc(m: ^Combat_Mission) -> bool {d :=
		m.units[clamp(m.request_unit, 0, m.friendly_count - 1)].doctrine
	switch
	m.request_kind {
	case .Commit_Screen:
		return d != .Hunter_Killer
	case .Release_Torpedoes:
		return d == .Hunter_Killer || d == .Last_Stand
	case .Damaged_Withdrawal:
		return d != .Last_Stand
	case .Pursuit:
		return d == .Hunter_Killer || d == .Last_Stand
	case .Authorize_Fire:
		return d != .Cautious_Screen || m.request_costly == false
	case .Authorize_Ability:
		group := clamp(m.units[clamp(m.request_unit, 0, m.friendly_count - 1)].group, 0, COMBAT_GROUP_COUNT - 1)
		return m.groups[group].ordnance_policy == .Liberal
	case .Authorize_Emergency_Defense:
		return true
	case .None:
		return false
	}
	return false}
combat_resolve_request :: proc(m: ^Combat_Mission, approve: bool) {if !m.request_pending do return
	kind := m.request_kind
	unit := m.request_unit
	target := m.request_target
	costly_request := m.request_costly; m.request_pending = false
	m.request_timer = 0
	m.request_cooldown = kind == .Authorize_Fire ? 0 : 18
	switch kind {
	case .Commit_Screen:
		if approve {recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1); combat_issue_group_order(m, 0, .Guard, m.units[recovery].position); for &u in m.units[:m.friendly_count] do if u.group == 0 do u.guard = recovery
			combat_add_event(
				m,
				fmt.tprintf("Screen group committed to %s.", m.units[recovery].name),
			)} else {combat_add_event(m, "Screen group retained its relay perimeter.")}
	case .Release_Torpedoes:
		if unit >= 0 && unit < m.friendly_count {m.units[unit].costly_shot_authorized = approve
			combat_add_event(
				m,
				approve ? "Torpedo reserve released for the capital target." : "Torpedo reserve remains sealed.",
			)}
	case .Damaged_Withdrawal:
		if approve &&
		   unit >= 0 &&
		   unit < m.friendly_count {combat_issue_order(m, unit, .Withdraw, m.extraction)
			combat_add_event(
				m,
				"Damaged command element ordered to withdraw.",
			)} else {combat_add_event(m, "Damaged command element remains on its objective.")}
	case .Pursuit:
		if approve &&
		   unit >= 0 &&
		   target >= 0 {combat_issue_order(m, unit, .Attack, m.units[target].position, target)
			combat_add_event(
				m,
				"Limited pursuit approved.",
			)} else {combat_add_event(m, "Pursuit denied; engagement boundary retained.")}
	case .Authorize_Fire:
		if unit >= 0 &&
		   unit <
			   m.friendly_count {u := &m.units[unit]; if approve {u.engagement_target = target; u.denied_target = -1; u.costly_denied_target = -1; if costly_request do u.costly_shot_authorized = true; combat_add_event(m, costly_request ? "Limited ordnance authorized for one salvo." : "Engagement authorized.")} else if costly_request {u.costly_denied_target = target; combat_add_event(m, "Limited ordnance withheld; routine fire continues.")} else {u.denied_target = target; u.target = -1; combat_add_event(m, "Fire withheld; the element is seeking another contact.")}}
	case .Authorize_Ability:
		if approve && unit >= 0 && unit < m.friendly_count {
			_ = combat_activate_ship_ability(m, unit, m.request_ability_target)
			combat_add_event(m, "Requested ship ability authorized.")
		} else {
			combat_add_event(m, "Requested ship ability withheld.")
		}
	case .Authorize_Emergency_Defense:
		if approve && unit >= 0 && unit < m.friendly_count {
			_ = combat_emergency_defense(m, unit)
		} else {
			combat_add_event(m, "Emergency defensive stores remained sealed.")
		}
	case .None:
	}; m.request_costly = false}

combat_request_ship_ability :: proc(
	m: ^Combat_Mission,
	index: int,
	target: Combat_Vec3 = {},
) -> bool {
	if m == nil || index < 0 || index >= m.friendly_count ||
	   !combat_ship_ability_ready(m, index) || m.request_pending ||
	   m.request_cooldown > 0 {
		return false
	}
	ability := combat_ship_ability(m.units[index])
	m.request_ability_target = target
	m.units[index].ability_requested = true
	combat_surface_request(
		m,
		.Authorize_Ability,
		index,
		fmt.tprintf("%s requests authority to activate %v.", m.units[index].name, ability),
		"Approval spends one persistent ability charge.",
	)
	return m.request_pending
}

combat_operation_propose_ability :: proc(m: ^Combat_Mission) {
	if m == nil || !m.operation.committed_plan.committed ||
	   m.request_pending || m.request_cooldown > 0 {
		return
	}
	for unit, index in m.units[:m.friendly_count] {
		if unit.ability_requested || !combat_ship_ability_ready(m, index) do continue
		group := m.groups[clamp(unit.group, 0, COMBAT_GROUP_COUNT - 1)]
		if unit.pressure < 55 && unit.hull / max(unit.max_hull, f32(1)) > .6 &&
		   group.cohesion > 65 && group.readiness > 60 {
			continue
		}
		target: Combat_Vec3
		if unit.target >= m.friendly_count && unit.target < m.unit_count {
			target = m.units[unit.target].position
		}
		if combat_request_ship_ability(m, index, target) do return
	}
}

combat_request_emergency_defense :: proc(m: ^Combat_Mission, index: int) -> bool {
	if m == nil || index < 0 || index >= m.friendly_count ||
	   m.request_pending || m.request_cooldown > 0 {
		return false
	}
	unit := m.units[index]
	if unit.defense_cooldown > 0 ||
	   unit.chaff + unit.flares + unit.decoys <= 0 {
		return false
	}
	combat_surface_request(
		m,
		.Authorize_Emergency_Defense,
		index,
		fmt.tprintf("%s requests emergency defensive authority.", unit.name),
		"Approval spends countermeasures and exposes the ship's defensive emissions.",
	)
	return m.request_pending
}

combat_side_index :: proc(side: Combat_Side) -> int {return side == .Friendly ? 0 : 1}
combat_contact_trace :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	index: int,
) -> ^Combat_Contact_Trace {if index < 0 || index >= m.unit_count do return nil; return(
		&m.contacts[combat_side_index(side)][index] \
	)}
combat_contact_visible :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	index: int,
) -> bool {trace := combat_contact_trace(m, side, index); return(
		trace != nil &&
		trace.liveness != .Unknown &&
		trace.liveness != .Lost \
	)}
combat_contact_targetable :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	index: int,
) -> bool {trace := combat_contact_trace(m, side, index); return(
		trace != nil &&
		trace.assessment != .Confirmed_Disabled &&
		(trace.liveness == .Fresh || trace.liveness == .Aging) &&
		trace.confidence >= .3 \
	)}

combat_doctrine_friendly_fire_tolerance :: proc(doctrine: Combat_Doctrine) -> f32 {
	switch doctrine {
	case .Cautious_Screen:
		return 0
	case .Balanced:
		return .18
	case .Hunter_Killer:
		return .5
	case .Last_Stand:
		return 1
	}
	return 0
}

combat_captain_recklessness_modifier :: proc(trait: Passage_Ship_Trait) -> f32 {
	switch trait {
	case .Cautious:
		return -.18
	case .Protective:
		return -.12
	case .Curious:
		return .08
	case .Independent:
		return .14
	case .Committed:
		return .2
	case .None:
		return 0
	}
	return 0
}

combat_captain_context_modifier :: proc(u: Combat_Unit, decision_context: Captain_Context) -> f32 {
	if !u.captain_profile.initialized do return combat_captain_recklessness_modifier(u.captain_trait)
	p := u.captain_profile
	risk := f32(i32(p.facets[int(Captain_Facet.Risk_Tolerance)]) - 2) * .08
	#partial switch decision_context {
	case .Friendly_Fire:
		return(
			risk -
			f32(i32(p.facets[int(Captain_Facet.Life_Preservation)]) - 2) * .07 +
			f32(i32(p.facets[int(Captain_Facet.Mission_Commitment)]) - 2) * .03 \
		)
	case .Rescue:
		return risk + f32(i32(p.facets[int(Captain_Facet.Solidarity)]) - 2) * .08
	case .Withdrawal:
		return risk + f32(i32(p.facets[int(Captain_Facet.Mission_Commitment)]) - 2) * .06
	case .Pursuit:
		return risk + f32(i32(p.facets[int(Captain_Facet.Confrontation)]) - 2) * .06
	case .Objective_Exposure:
		return risk + f32(i32(p.facets[int(Captain_Facet.Mission_Commitment)]) - 2) * .05
	case .Command_Degraded:
		return(
			f32(i32(p.facets[int(Captain_Facet.Personal_Autonomy)]) - 2) * .08 +
			f32(i32(p.facets[int(Captain_Facet.Improvisation)]) - 2) * .05 \
		)
	}
	return risk
}

combat_friendly_fire_tolerance :: proc(u: Combat_Unit) -> f32 {
	return clamp(
		combat_doctrine_friendly_fire_tolerance(u.doctrine) +
		combat_captain_context_modifier(u, .Friendly_Fire),
		0,
		1,
	)
}

combat_friendly_fire_risk :: proc(
	m: ^Combat_Mission,
	attacker, target: int,
	weapon: Combat_Weapon_Class,
) -> f32 {
	if attacker < 0 || attacker >= m.unit_count || target < 0 || target >= m.unit_count do return 1
	if weapon != .Guided_Missile && weapon != .Heavy_Torpedo do return 0
	a :=
		m.units[attacker]; aim, valid := combat_contact_position(m, a.side, target); if !valid do return 1
	segment := Combat_Vec3{aim.x - a.position.x, aim.y - a.position.y, aim.z - a.position.z}
	denom :=
		segment.x * segment.x +
		segment.y * segment.y +
		segment.z * segment.z; if denom <= .0001 do return 1
	risk: f32 = 0
	for ally, index in m.units[:m.unit_count] {if index == attacker || ally.side != a.side || ally.disabled || ally.extracted do continue
		to_ally := Combat_Vec3 {
			ally.position.x - a.position.x,
			ally.position.y - a.position.y,
			ally.position.z - a.position.z,
		}; fraction := (to_ally.x * segment.x + to_ally.y * segment.y + to_ally.z * segment.z) / denom
		if fraction <= 0 || fraction >= 1 do continue
		closest := Combat_Vec3 {
			a.position.x + segment.x * fraction,
			a.position.y + segment.y * fraction,
			a.position.z + segment.z * fraction,
		}; radius := combat_element_separation_radius(ally) * .7
		distance := combat_distance(
			closest,
			ally.position,
		); if distance < radius do risk = max(risk, 1 - distance / radius)
	}
	return clamp(risk, 0, 1)
}

combat_has_firing_solution :: proc(
	m: ^Combat_Mission,
	attacker, index: int,
	weapon: Combat_Weapon_Class,
) -> bool {
	if attacker < 0 || attacker >= m.unit_count do return false
	side :=
		m.units[attacker].side; group := m.units[attacker].group; trace := combat_group_contact_trace(m, side, group, index); if trace == nil || !combat_group_contact_targetable(m, side, group, index) do return false
	threshold: f32 = .58; if weapon == .Guided_Missile || weapon == .Heavy_Torpedo do threshold = .42; if weapon == .Defensive_Gun || weapon == .Defensive_Laser do threshold = .3; if weapon == .Laser do threshold = .68
	return(
		trace.solution_quality >= threshold &&
		combat_friendly_fire_risk(m, attacker, index, weapon) <=
			combat_friendly_fire_tolerance(m.units[attacker]) \
	)
}
combat_contact_position :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	index: int,
) -> (
	Combat_Vec3,
	bool,
) {trace := combat_contact_trace(m, side, index); if trace == nil || trace.liveness == .Unknown || trace.liveness == .Lost do return {}, false
	prediction := min(trace.age, COMBAT_CONTACT_STALE_TIME)
	return {
			trace.position.x + trace.velocity.x * prediction,
			trace.position.y + trace.velocity.y * prediction,
			trace.position.z + trace.velocity.z * prediction,
		},
		true}

combat_sensor_range :: proc(u: Combat_Unit) -> f32 {
	range: f32 = 3000
	if .Sensors in combat_unit_modules(u) do range = 4200
	if u.hull_archetype == .Scout do range = 5000
	if u.hull_archetype == .Picket_Frigate do range = 5600
	switch u.sensor_mode {
	case .Silent:
		range *= .55
	case .Active_Search:
		range *= 1.35
	case .Illuminate:
		range *= 1.15
	case .Relay:
		range *= 1.05
	case .Deceive:
		range *= .72
	case .Passive_Watch:
	}
	return range
}
combat_contact_signature_for_archetype :: proc(archetype: Ship_Hull_Archetype) -> f32 {switch
	ship_hull_archetype_family(archetype) {case .Strike_Craft:
		return .72; case .Light_Combatant:
		return .88; case .Frigate:
		return 1; case .Line_Warship:
		return 1.3; case .Carrier_And_Command:
		return 1.48; case .Diaspora:
		return 1.38; case .Unspecified:
		return 1}
	return 1}
combat_contact_signature :: proc(u: Combat_Unit) -> f32 {return max(u.signature, f32(.12))}

combat_sensor_power :: proc(u: Combat_Unit) -> f32 {
	power: f32 = 1
	if .Sensors in combat_unit_modules(u) do power *= 1.65
	if u.hull_archetype == .Scout || u.hull_archetype == .Picket_Frigate do power *= 1.35
	power *= clamp(u.readiness / 100, .35, 1) * clamp(u.hull / max(u.max_hull, f32(1)), .3, 1)
	power *= clamp(u.subsystems.sensors / 100, f32(.2), f32(1))
	if u.active_sensors do power *= 1.65
	return power
}

combat_contact_display :: proc(trace: Combat_Contact_Trace) -> Combat_Contact_Display {
	if trace.solution_quality >= .72 && trace.error_radius <= 35 do return .Firing_Solution
	if trace.identity_confidence >= .7 do return .Identified
	if trace.confidence >= .42 do return .Track
	return .Signal
}
combat_contact_display_name :: proc(trace: Combat_Contact_Trace) -> string {switch
	combat_contact_display(trace) {
	case .Signal:
		return "SIGNAL"; case .Track:
		return "TRACK"; case .Identified:
		return "IDENTIFIED"; case .Firing_Solution:
		return "FIRING SOLUTION"}
	return "SIGNAL"}
combat_exposure_state :: proc(u: Combat_Unit) -> Combat_Exposure_State {
	if u.signature >= u.base_signature * 2.05 || u.exposure >= 75 do return .Fixed
	if u.signature >= u.base_signature * 1.5 || u.exposure >= 45 do return .Exposed
	if u.signature >= u.base_signature * 1.12 || u.active_sensors do return .Emitting
	return .Quiet
}
combat_exposure_state_name :: proc(u: Combat_Unit) -> string {switch combat_exposure_state(u) {
	case .Quiet:
		return "QUIET"; case .Emitting:
		return "EMITTING"; case .Exposed:
		return "EXPOSED"; case .Fixed:
		return "FIXED"}; return "QUIET"}
combat_doctrine_active_sensors :: proc(u: Combat_Unit) -> bool {
	if u.silent_running do return false
	if u.communication == .Continuous do return true
	if u.doctrine == .Cautious_Screen do return false
	if u.doctrine == .Hunter_Killer || u.doctrine == .Last_Stand do return true
	return u.order == .Attack || u.order == .Intercept || u.target >= 0
}
