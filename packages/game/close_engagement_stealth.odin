package game

import "core:math"

combat_doctrine_policies :: proc(
	d: Combat_Doctrine,
) -> (
	Combat_Survival_Method,
	Combat_Emission_Policy,
	Combat_Attack_Rhythm,
	Combat_Displacement_Trigger,
) {
	switch d {
	case .Cautious_Screen:
		return .Concealment, .Passive_First, .Ambush, .When_Tracked
	case .Balanced:
		return .Endurance, .Burst_Sharing, .Repeated_Passes, .When_Pressured
	case .Hunter_Killer:
		return .Mobility, .Continuous, .Repeated_Passes, .After_Firing
	case .Last_Stand:
		return .Endurance, .Continuous, .Sustained, .Never
	}
	return .Endurance, .Burst_Sharing, .Repeated_Passes, .When_Pressured
}

combat_apply_group_doctrine :: proc(g: ^Combat_Group, d: Combat_Doctrine) {
	g.doctrine = d
	g.withdraw_threshold, g.pursuit_limit, g.priority = combat_doctrine_rules(d)
	g.survival_method, g.emission_policy, g.attack_rhythm, g.displacement_trigger =
		combat_doctrine_policies(d)
}

combat_signature_percent :: proc(u: Combat_Unit) -> f32 {return clamp(
		(u.signature / max(u.base_signature, f32(.1)) - .45) / 1.8 * 100,
		0,
		100,
	)}
combat_signature_cause :: proc(u: Combat_Unit) -> string {
	if u.silent_running do return "SILENT RUNNING"
	if u.combat_burn do return "COMBAT BURN"
	if u.active_sensors do return "ACTIVE SENSORS"
	if u.network_burst_timer > 0 do return "TRACK BURST"
	if u.exposure >= 45 do return "WEAPON EMISSIONS"
	return "HULL AND THRUST"
}

combat_group_state :: proc(m: ^Combat_Mission, side: Combat_Side, group: int) -> ^Combat_Group {
	bounded := clamp(group, 0, COMBAT_GROUP_COUNT - 1)
	return side == .Friendly ? &m.groups[bounded] : &m.raider_groups[bounded]
}

combat_update_signature :: proc(m: ^Combat_Mission, u: ^Combat_Unit, dt: f32) {
	if u.network_burst_timer > 0 do u.network_burst_timer = max(0, u.network_burst_timer - dt)
	if u.silent_running_timer >
	   0 {u.silent_running_timer = max(0, u.silent_running_timer - dt); u.silent_running = true}
	accel := math.sqrt(
		u.acceleration.x * u.acceleration.x +
		u.acceleration.y * u.acceleration.y +
		u.acceleration.z * u.acceleration.z,
	)
	modifier: f32 = 1
	if u.active_sensors do modifier += .42
	if u.communication == .Continuous do modifier += .32
	if u.network_burst_timer > 0 do modifier += .24
	if u.combat_burn do modifier += .65
	modifier += clamp(accel / max(u.max_acceleration, f32(1)), 0, 2) * .22
	modifier += u.exposure / 100 * .8
	modifier += clamp(1 - u.hull / max(u.max_hull, f32(1)), 0, 1) * .28
	if u.silent_running do modifier *= .52
	if combat_inside(u.position, m.terrain[0]) do modifier *= .62
	for field in m.wreckage_fields[:m.wreckage_field_count] do if combat_distance(u.position, field.center) < field.radius {modifier *= .7; break}
	u.signature = max(.12, u.base_signature * modifier)
	decay: f32 = 2.4; if u.silent_running do decay = 7; if combat_inside(u.position, m.terrain[0]) do decay *= 1.5
	if !u.active_sensors && !u.combat_burn && u.network_burst_timer <= 0 do u.exposure = max(0, u.exposure - dt * decay)
}
