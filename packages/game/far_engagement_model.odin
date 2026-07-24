package game

// Physical and command contracts for operational-scale open-space combat.
// All positions are kilometres, velocities kilometres/second, time seconds,
// mass kilograms, energy joules, power watts, and angles radians.

import "core:fmt"
import "core:math"

FAR_C_KM_S : f64 : 299792.458
FAR_SCHEMA_VERSION : u32 : 2
FAR_MAX_SHIPS :: 24
FAR_MAX_TRUTH_CONTACTS :: 4
FAR_MAX_TRANSMISSIONS :: 48

Far_Objective_Family :: enum {
	Breakthrough,
	Interception,
	Escort,
	Reconnaissance,
	Withdrawal_Recovery,
}

Far_Complication :: enum {
	None,
	False_Contacts,
	Command_Delay,
	Damaged_Drives,
	Neutral_Traffic,
	Uncertain_Reinforcement,
	Divided_Objectives,
	Deteriorating_Deadline,
}

Far_Doctrine :: enum {
	Preserve_Force,
	Balanced,
	Complete_At_Cost,
}

Far_Posture :: enum {
	Transit,
	Observe,
	Shadow,
	Cross_Bearing,
	Screen,
	Intercept,
	Fire_And_Displace,
	Break_Contact,
	Recover,
	Unable,
}

Far_Plan_Reason :: enum {
	Following_Order,
	Building_Track,
	Protecting_Subject,
	Firing_Solution,
	Weapon_Threat,
	Deadline_Threat,
	Support_Lost,
	Recovery_Possible,
	Insufficient_Capability,
}

Far_Order_Verb :: enum {
	Break_Through,
	Intercept,
	Escort,
	Observe,
	Withdraw,
	Recover,
}

Far_Weapon_Type :: enum {
	Guided_Missile,
	Kinetic,
	Laser,
}

Far_Transmission_Kind :: enum {
	Observation,
	Order,
	Report,
	Acknowledgement,
	Damage_Assessment,
}

Far_Hit_Zone :: enum {
	Drive,
	Sensors,
	Radiators,
	Weapons,
	Command,
	Habitat,
	Structure,
}

Far_Ship_State :: enum {
	Operational,
	Mission_Killed,
	Destroyed,
	Recovering,
	Recovered,
	Abandoned,
}

Far_Encounter_Spec :: struct {
	schema_version:                  u32,
	seed:                            u64,
	objective_family:                Far_Objective_Family,
	complication:                    Far_Complication,
	route_origin, route_destination: Far_Vec2,
	deadline_seconds:                f64,
	difficulty:                      f64,
	friendly_manifest:               [FAR_MAX_SHIPS]Ship_ID,
	friendly_count:                  int,
	enemy_manifest:                  [FAR_MAX_SHIPS]u64,
	enemy_count:                     int,
	known_contact_count:             int,
	friendly_faction, enemy_faction: string,
}

Far_Operational_Order :: struct {
	verb:                   Far_Order_Verb,
	subject_group_id:       u32,
	object_id:              u32,
	destination:            Far_Vec2,
	boundary_center:        Far_Vec2,
	boundary_radius_km:     f64,
	deadline_seconds:       f64,
	acceptable_loss:        f64,
	ordnance_authorized:    int,
	decoys_authorized:      int,
	pursuit_authorized:     bool,
	rescue_authorized:      bool,
	formation:              Far_Formation,
	emission:               Far_Emission,
	authority_deviation_authorized: bool,
	authority_breach: bool,
	authority_breach_clause: Operation_Authority_Clause,
}

Far_Task_Group :: struct {
	stable_id:                                      u32,
	member_ids:                                     [FAR_MAX_SHIPS]Ship_ID,
	member_count:                                   int,
	commander:                                      Figure_ID,
	order, received_order:                          Far_Operational_Order,
	doctrine:                                       Far_Doctrine,
	posture:                                        Far_Posture,
	reason:                                         Far_Plan_Reason,
	position, velocity, acceleration:               Far_Vec2,
	max_acceleration_km_s2, delta_v_remaining_km_s: f64,
	sensor_power_w, radiator_capacity_w:            f64,
	plan_revision:                                  u32,
	commitment_until_seconds:                       f64,
	last_plan_score:                                f64,
	operational:                                    bool,
}

Far_Truth_Contact :: struct {
	stable_id:                                      u32,
	group:                                          Far_Task_Group,
	emission_power_w:                               f64,
	projected_area_m2:                              f64,
	active, hostile:                                bool,
}

Far_Contact_Belief :: struct {
	stable_id:                                      u32,
	observer_group_id, truth_id:                    u32,
	estimated_position, estimated_velocity:         Far_Vec2,
	observed_at_seconds, received_at_seconds:       f64,
	uncertainty_radius_km, confidence:              f64,
	identified, active:                             bool,
}

Far_Transmission :: struct {
	id:                                             u32,
	kind:                                           Far_Transmission_Kind,
	sender_group_id, receiver_group_id:             u32,
	sent_at_seconds, arrives_at_seconds:             f64,
	origin_position, receiver_position_at_send:     Far_Vec2,
	order:                                          Far_Operational_Order,
	belief:                                         Far_Contact_Belief,
	text:                                           string,
	emission_power_w:                               f64,
	active, delivered, acknowledged:                bool,
}

Far_Weapon_Flight :: struct {
	id:                                             u32,
	weapon_type:                                    Far_Weapon_Type,
	source_group_id, target_group_id, target_truth_id: u32,
	launch_position, position, velocity:            Far_Vec2,
	target_estimate_position, target_estimate_velocity: Far_Vec2,
	launch_seconds, predicted_arrival_seconds:       f64,
	acceleration_km_s2, propellant_seconds:               f64,
	projectile_mass_kg, explosive_yield_j:          f64,
	laser_power_w, laser_dwell_seconds:              f64,
	dispersion_radians, seeker_radius_km:            f64,
	weapons_launched, weapons_surviving:             int,
	detected, acquired, resolved, friendly, active:  bool,
}

Far_Ship_Outcome :: struct {
	ship_id:                                        Ship_ID,
	enemy_id:                                       u64,
	state:                                          Far_Ship_State,
	mass_kg, projected_area_m2:                     f64,
	armor_areal_density_kg_m2:                      f64,
	structure_j, drive, sensors, radiators:          f64,
	weapons, command, habitat:                      f64,
	crew_initial, crew_surviving:                   int,
	last_energy_j, last_coupled_energy_j:            f64,
	last_zone:                                      Far_Hit_Zone,
	last_weapon:                                    Far_Weapon_Type,
	cause:                                          string,
	friendly:                                       bool,
}

Far_Command_Result :: struct {
	ok:      bool,
	reason:  string,
}

Far_Decision_Preview :: struct {
	command_delay_seconds:      f64,
	arrival_change_seconds:     f64,
	weapon_flight_seconds:      f64,
	target_uncertainty_at_arrival_km: f64,
	delta_v_cost_km_s:          f64,
	uncertainty_change_km:      f64,
	ordnance_cost, decoy_cost:  int,
	known:                      bool,
}

far_vec_add :: proc(a, b: Far_Vec2) -> Far_Vec2 {
	return {a.x + b.x, a.y + b.y}
}

far_vec_sub :: proc(a, b: Far_Vec2) -> Far_Vec2 {
	return {a.x - b.x, a.y - b.y}
}

far_vec_scale :: proc(a: Far_Vec2, scale: f64) -> Far_Vec2 {
	return {a.x * scale, a.y * scale}
}

far_vec_length :: proc(a: Far_Vec2) -> f64 {
	return math.sqrt(a.x * a.x + a.y * a.y)
}

far_vec_normalize :: proc(a: Far_Vec2) -> Far_Vec2 {
	length := far_vec_length(a)
	if length <= 1.0e-12 do return {}
	return {a.x / length, a.y / length}
}

far_light_delay_seconds :: proc(a, b: Far_Vec2) -> f64 {
	return far_distance(a, b) / FAR_C_KM_S
}

far_reachable_radius_km :: proc(
	delta_v_remaining_km_s, max_acceleration_km_s2, seconds: f64,
) -> f64 {
	if seconds <= 0 || delta_v_remaining_km_s <= 0 || max_acceleration_km_s2 <= 0 do return 0
	burn_seconds := min(seconds, delta_v_remaining_km_s / max_acceleration_km_s2)
	return .5 * max_acceleration_km_s2 * burn_seconds * burn_seconds +
		max(0, seconds - burn_seconds) * max_acceleration_km_s2 * burn_seconds
}

far_intercept_time_seconds :: proc(
	relative_position, relative_velocity: Far_Vec2,
	interceptor_speed_km_s: f64,
) -> (f64, bool) {
	a := relative_velocity.x * relative_velocity.x +
		relative_velocity.y * relative_velocity.y -
		interceptor_speed_km_s * interceptor_speed_km_s
	b := 2 * (relative_position.x * relative_velocity.x +
		relative_position.y * relative_velocity.y)
	c := relative_position.x * relative_position.x +
		relative_position.y * relative_position.y
	if math.abs(a) < 1.0e-12 {
		if math.abs(b) < 1.0e-12 do return 0, false
		t := -c / b
		return t, t > 0
	}
	discriminant := b * b - 4 * a * c
	if discriminant < 0 do return 0, false
	root := math.sqrt(discriminant)
	t0, t1 := (-b - root) / (2 * a), (-b + root) / (2 * a)
	t := t0 > 0 ? t0 : t1
	return t, t > 0
}

far_kinetic_energy_j :: proc(mass_kg, relative_speed_km_s: f64) -> f64 {
	speed_m_s := relative_speed_km_s * 1000
	return .5 * mass_kg * speed_m_s * speed_m_s
}

far_laser_spot_radius_m :: proc(
	wavelength_m, aperture_m, distance_km, pointing_error_rad: f64,
) -> f64 {
	diffraction := 1.22 * wavelength_m / max(aperture_m, .001)
	angle := math.sqrt(diffraction * diffraction + pointing_error_rad * pointing_error_rad)
	return max(.01, angle * distance_km * 1000)
}

far_armor_resistance_j :: proc(
	armor_areal_density_kg_m2, impact_area_m2: f64,
) -> f64 {
	// A conservative effective specific disruption energy for layered,
	// spaced armor. This is deliberately exposed as a physical calibration.
	return max(0, armor_areal_density_kg_m2 * impact_area_m2 * 8.0e6)
}

far_ship_physics_from_hull :: proc(
	ship_id: Ship_ID,
	hull: Ship_Hull_Archetype,
	crew: int,
	friendly := true,
) -> Far_Ship_Outcome {
	mass_kg := f64(ship_hull_archetype_nominal_mass(hull)) * 1000
	family := ship_hull_archetype_family(hull)
	area_factor: f64 = family == .Strike_Craft ? .012 :
		family == .Light_Combatant ? .035 :
		family == .Frigate ? .065 :
		family == .Line_Warship ? .12 :
		family == .Carrier_And_Command ? .17 : .22
	armor: f64 = family == .Line_Warship ? 1800 :
		family == .Carrier_And_Command ? 950 :
		family == .Frigate ? 620 :
		family == .Light_Combatant ? 350 :
		family == .Strike_Craft ? 90 : 240
	area := max(8.0, math.pow(max(mass_kg, 1), 2.0 / 3.0) * area_factor)
	return {
		ship_id = ship_id,
		state = .Operational,
		mass_kg = mass_kg,
		projected_area_m2 = area,
		armor_areal_density_kg_m2 = armor,
		structure_j = max(1.0e10, mass_kg * 2.4e6),
		drive = 1, sensors = 1, radiators = 1, weapons = 1,
		command = 1, habitat = 1,
		crew_initial = max(crew, 1), crew_surviving = max(crew, 1),
		friendly = friendly,
	}
}

far_zone_for_impact :: proc(seed: u64, impact_serial: u64) -> Far_Hit_Zone {
	return Far_Hit_Zone(far_mix(seed ~ impact_serial * 0x9e3779b97f4a7c15) % 7)
}

far_apply_physical_impact :: proc(
	outcome: ^Far_Ship_Outcome,
	weapon: Far_Weapon_Type,
	energy_j, impact_area_m2: f64,
	seed, impact_serial: u64,
) {
	if outcome.state == .Destroyed || energy_j <= 0 do return
	resistance := far_armor_resistance_j(outcome.armor_areal_density_kg_m2, impact_area_m2)
	coupled := max(0, energy_j - resistance)
	outcome.last_energy_j = energy_j
	outcome.last_coupled_energy_j = coupled
	outcome.last_weapon = weapon
	if energy_j >= outcome.structure_j * 8 || coupled >= outcome.structure_j * 3 {
		outcome.state = .Destroyed
		outcome.drive, outcome.sensors, outcome.radiators = 0, 0, 0
		outcome.weapons, outcome.command, outcome.habitat = 0, 0, 0
		outcome.crew_surviving = 0
		outcome.cause = fmt.tprintf(
			"Catastrophic %.2e J %v impact exceeded structural breakup energy.",
			energy_j, weapon,
		)
		return
	}
	if coupled <= 0 {
		outcome.cause = fmt.tprintf(
			"Armor rejected a %.2e J %v impact.", energy_j, weapon,
		)
		return
	}
	zone := far_zone_for_impact(seed, impact_serial)
	outcome.last_zone = zone
	fraction := clamp(coupled / max(outcome.structure_j, 1), 0, 1)
	switch zone {
	case .Drive: outcome.drive = max(0, outcome.drive - fraction * 2.4)
	case .Sensors: outcome.sensors = max(0, outcome.sensors - fraction * 3)
	case .Radiators: outcome.radiators = max(0, outcome.radiators - fraction * 3.2)
	case .Weapons: outcome.weapons = max(0, outcome.weapons - fraction * 2.6)
	case .Command: outcome.command = max(0, outcome.command - fraction * 3.4)
	case .Habitat:
		outcome.habitat = max(0, outcome.habitat - fraction * 2.8)
		casualties := clamp(int(math.ceil(f64(outcome.crew_initial) * fraction * .7)), 0, outcome.crew_surviving)
		outcome.crew_surviving -= casualties
	case .Structure:
		outcome.drive = max(0, outcome.drive - fraction * .8)
		outcome.habitat = max(0, outcome.habitat - fraction * .8)
	}
	if outcome.drive <= .12 || outcome.command <= .08 ||
	   outcome.habitat <= .08 || outcome.radiators <= .05 {
		outcome.state = .Mission_Killed
	}
	outcome.cause = fmt.tprintf(
		"%.2e J coupled through armor into the %v zone.", coupled, zone,
	)
}
