package game

// Deterministic command-level Close Engagement for the Recover the Seedship slice.
// Presentation deliberately lives in src; this file owns mission generation,
// autonomous intent, combat, objectives, and the factual outcome record.

import "core:fmt"
import "core:math"
Combat_Strategic_Asset :: struct {
	position:                                                 Combat_Vec3,
	charge, exposure_remaining, disable_progress, beam_flash: f32,
	lock_target, shots_fired, ships_hit:                      int,
	locked, disabled:                                         bool,
	beam_aim:                                                 Combat_Vec3,
}

Combat_Recon_Probe_Status :: enum {
	Unavailable,
	In_Flight,
	Scanning,
	Destroyed,
	Complete,
}

Combat_Recon_Probe :: struct {
	status:             Combat_Recon_Probe_Status,
	launcher:           int,
	position,
	destination:        Combat_Vec3,
	hull,
	max_hull,
	speed,
	scan_rate:          f32,
	detected:           bool,
}

Combat_Subsystems :: struct {
	engines, sensors, radiators, weapons, flight_deck, command, life_support: f32,
}

Combat_Unit :: struct {
	name,
	commander,
	trait,
	history:                                                                                                 string,
	side:                                                                                                                            Combat_Side,
	role:                                                                                                                            Combat_Role,
	hull_archetype:                                                                                                                  Ship_Hull_Archetype,
	operational_role:                                                                                                                Ship_Operational_Role,
	campaign_modules:                                                                                                                Ship_Modules,
	weapon_packages:                                                                                                                 Ship_Weapon_Packages,
	defense_packages:                                                                                                                Ship_Defense_Packages,
	capital_type:                                                                                                                    Combat_Capital_Type,
	doctrine:                                                                                                                        Combat_Doctrine,
	stance:                                                                                                                          Combat_Stance,
	captain_trait:                                                                                                                   Passage_Ship_Trait,
	captain_profile:                                                                                                                 Captain_Profile,
	order:                                                                                                                           Combat_Order,
	action:                                                                                                                          Combat_Action,
	group:                                                                                                                           int,
	position,
	velocity,
	acceleration,
	destination:                                                                                   Combat_Vec3,
	tactical_destination:                                                                                                            Combat_Vec3,
	target,
	guard:                                                                                                                   int,
	hull,
	max_hull,
	range,
	damage,
	speed,
	facing,
	turn_rate,
	weapon_cooldown,
	attack_run_timer,
	weapon_flash,
	impact_flash:          f32,
	craft,
	max_craft,
	torpedoes,
	recon_probes,
	decoys,
	chaff,
	flares,
	veterancy,
	kills:                                                            int,
	formation_ships:                                                                                                                 int,
	formation_active:                                                                                                                int,
	tonnage_each:                                                                                                                    i64,
	roster_start,
	damage_cursor:                                                                                                     int,
	cohesion,
	readiness,
	pressure:                                                                                                   f32,
	exposure:                                                                                                                        f32,
	signature,
	base_signature,
	engine_power,
	max_acceleration,
	turn_authority,
	burn_heat,
	network_burst_timer,
	silent_running_timer: f32,
	ability_charges:                                                                                                                 int,
	ability_cooldown:                                                                                                                f32,
	defense_cooldown:                                                                                                                f32,
	defense_response:                                                                                                                string,
	selected,
	disabled,
	extracted,
	withdrawing,
	ability_requested:                                                                                bool,
	engagement_target,
	denied_target,
	costly_denied_target:                                                                          int,
	costly_shot_authorized,
	active_sensors,
	silent_running,
	combat_burn:                                                             bool,
	communication:                                                                                                                   Combat_Communication_State,
	maneuver_job:                                                                                                                    Combat_Maneuver_Job,
	sensor_mode:                                                                                                                     Combat_Sensor_Mode,
	maneuver_intent:                                                                                                                 Combat_Maneuver_Intent,
	drive_acceleration_g:                                                                                                            f32,
	weapon_heat:                                                                                                                     f32,
	trajectory_forecast:                                                                                                             Combat_Trajectory_Forecast,
	subsystems:                                                                                                                       Combat_Subsystems,
}

Combat_Result :: struct {
	population, archive, fabrication:                                   int,
	population_secured, archive_secured, fabrication_secured:           bool,
	friendly_total, friendly_preserved, casualties, rescued, abandoned: int,
	ships_total, ships_preserved, ships_disabled:                       int,
	player_ships_lost, enemy_ships_lost, beam_ships_hit, beam_shots:    int,
	strategic_asset_disabled:                                           bool,
	enemy_capital_disabled, sensor_data, anomaly_data:                  bool,
	heavy_ammunition:                                                   int,
	optional_completed:                                                 int,
	mission_time:                                                       f32,
	consequence:                                                        string,
}

Combat_Outcome :: enum {
	Defeat,
	Partial_Success,
	Victory,
}

combat_result_outcome :: proc(m: ^Combat_Mission) -> Combat_Outcome {
	if m.skirmish {
		if skirmish_primary_objective_met(m) do return .Victory
		if m.result.ships_preserved > 0 || skirmish_optional_objectives_met(m) > 0 do return .Partial_Success
		return .Defeat
	}
	if m.scenario == .Finale do return m.result.strategic_asset_disabled ? .Victory : .Defeat
	if m.result.population > 0 do return .Victory
	if m.result.sensor_data do return .Partial_Success
	return .Defeat
}

Combat_Autoplay_Report :: struct {
	seed:                                                        u64,
	completed:                                                   bool,
	population, archive, fabrication, anomaly, capital_disabled: bool,
	preserved, casualties:                                       int,
	time:                                                        f32,
	relay_progress:                                              [2]f32,
	recovery_progress, recovery_distance, recovery_match_speed:  f32,
	recovery_disabled, recovery_extracted:                       bool,
	friendly_unextracted:                                        int,
	first_unextracted_role:                                      Combat_Role,
	last_extraction_role:                                        Combat_Role,
	last_extraction_time:                                        f32,
}

Combat_Mission :: struct {
	seed, rng:                                                      u64,
	scenario:                                                       Combat_Scenario,
	operation:                                                      Combat_Operation,
	ai_parameters:                                                  [2]Combat_AI_Parameters,
	skirmish:                                                       bool,
	skirmish_setup:                                                 Skirmish_Setup,
	skirmish_objectives:                                            Skirmish_Objective_Contract,
	skirmish_objective_pressure:                                    Skirmish_Objective_Pressure,
	skirmish_recovery_profile:                                      Skirmish_Recovery_Profile,
	skirmish_infiltration_cover:                                    Skirmish_Infiltration_Cover,
	grid:                                                           Combat_Engagement_Grid,
	heroism_scale:                                                  i32,
	time, accumulator:                                              f32,
	last_extraction_time:                                           f32,
	last_extraction_role:                                           Combat_Role,
	next_decision_time:                                             f32,
	phase:                                                          Combat_Phase,
	units:                                                          [dynamic]Combat_Unit,
	contacts:                                                       [2][dynamic]Combat_Contact_Trace,
	group_contacts:                                                 [2][COMBAT_GROUP_COUNT][dynamic]Combat_Contact_Trace,
	salvos:                                                         [dynamic]Combat_Salvo,
	salvo_count:                                                    int,
	unit_count, friendly_count:                                     int,
	recovery_unit:                                                  int,
	ships:                                                          []Combat_Ship_Record,
	ship_count:                                                     int,
	planning_accumulator:                                           f32,
	groups:                                                         [COMBAT_GROUP_COUNT]Combat_Group,
	raider_groups:                                                  [COMBAT_GROUP_COUNT]Combat_Group,
	terrain:                                                        [3]Combat_Terrain,
	wreckage_fields:                                                [COMBAT_MAX_WRECKAGE_FIELDS]Combat_Wreckage_Field,
	wreckage_field_count:                                           int,
	wreckage_pending:                                               [dynamic]int,
	wreckage_pending_tonnage:                                       [dynamic]f32,
	wreckage_pending_position:                                      [dynamic]Combat_Vec3,
	interactions:                                                   [COMBAT_MAX_INTERACTIONS]Combat_Interaction,
	interaction_count:                                              int,
	relays:                                                         [2]Combat_Vec3,
	relay_velocity:                                                 [2]Combat_Vec3,
	relay_progress:                                                 [2]f32,
	relays_synchronized:                                            bool,
	seedship, extraction, anomaly:                                  Combat_Vec3,
	seedship_velocity:                                              Combat_Vec3,
	recovery_target_velocity:                                      Combat_Vec3,
	seedship_found:                                                 bool,
	recovery_progress:                                              f32,
	population_recovered, archive_recovered, fabrication_recovered: bool,
	disabled_rescued:                                               int,
	recovery_tow_slowed:                                            bool,
	anomaly_progress:                                               f32,
	// Procedural objectives may designate one command element and remember a
	// deterministic failure condition without leaking presentation policy into
	// the simulation.
	objective_unit:                                                 int,
	objective_failed:                                               bool,
	recon_probe:                                                    Combat_Recon_Probe,
	recon_probes_launched,
	recon_probes_lost,
	recon_probes_completed:                                         int,
	complication:                                                   Combat_Complication,
	complication_triggered:                                         bool,
	capital_arrived, extraction_mandatory, complete:                bool,
	ability_pending:                                                bool,
	ability_kind:                                                   Combat_Ship_Ability,
	ability_source:                                                 int,
	ability_target:                                                 Combat_Vec3,
	ability_timer, ability_flash:                                   f32,
	request_text, request_consequence:                              string,
	request_unit, request_target:                                   int,
	request_timer, request_cooldown:                                f32,
	request_pending:                                                bool,
	request_kind:                                                   Combat_Request_Kind,
	request_costly:                                                 bool,
	request_ability_target:                                        Combat_Vec3,
	fire_control:                                                   Combat_Fire_Control,
	torpedo_request_made:                                           bool,
	pursuit_request_made:                                           bool,
	withdraw_request_made:                                          [dynamic]bool,
	operation_group_withdrawn:                                      [COMBAT_GROUP_COUNT]bool,
	operation_contingency_fired:                                    [COMBAT_GROUP_COUNT][COMBAT_PLAN_MAX_CONTINGENCIES]bool,
	operation_route_cursor:                                         [COMBAT_GROUP_COUNT]int,
	event_text:                                                     [10]string,
	event_time:                                                     [10]f32,
	event_count:                                                    int,
	event_serial:                                                   u64,
	last_guided_hit_source, last_guided_hit_target:                 int,
	last_guided_hit_time:                                           f32,
	result:                                                         Combat_Result,
	finale_phase:                                                   Combat_Finale_Phase,
	strategic_asset:                                                Combat_Strategic_Asset,
	campaign_ships:                                                 [dynamic]Ship_ID,
	campaign_ship_elements:                                         [dynamic]int,
	campaign_ship_roster_indices:                                   [dynamic]int,
	campaign_ship_count:                                            int,
	campaign_result_applied:                                        bool,
	campaign_origin_event:                                          u64,
	campaign_incident, campaign_authority:                          string,
	campaign_doctrine_deviation:                                    bool,
}

combat_unit_modules :: proc(u: Combat_Unit) -> Ship_Modules {
	if u.campaign_modules != {} do return u.campaign_modules
	return ship_operational_role_modules(u.operational_role)
}

combat_mix :: proc(x: u64) -> u64 {v := x; v ~= v >> 30; v *= 0xbf58476d1ce4e5b9; v ~= v >> 27
	v *= 0x94d049bb133111eb
	return v ~ (v >> 31)}
combat_rand :: proc(m: ^Combat_Mission) -> f32 {m.rng = combat_mix(m.rng + 0x9e3779b97f4a7c15)
	return f32(m.rng & 0xffff) / 65535.0}
combat_distance :: proc(a, b: Combat_Vec3) -> f32 {x := a.x - b.x; y := a.y - b.y; z := a.z - b.z
	return math.sqrt(x * x + y * y + z * z)}
combat_map_position :: proc(p: Combat_Vec3) -> Combat_Vec3 {return{
		p.x * COMBAT_MAP_SCALE,
		p.y * COMBAT_MAP_SCALE,
		p.z * COMBAT_MAP_SCALE,
	}}
combat_sector_indices :: proc(grid: Combat_Engagement_Grid, p: Combat_Vec3) -> (column, row: int) {
	width := max(grid.max_y - grid.min_y, f32(1)); depth := max(grid.max_x - grid.min_x, f32(1))
	column = clamp(
		int((p.y - grid.min_y) / width * f32(COMBAT_SECTOR_COLUMNS)),
		0,
		COMBAT_SECTOR_COLUMNS - 1,
	)
	row = clamp(
		int((p.x - grid.min_x) / depth * f32(COMBAT_SECTOR_ROWS)),
		0,
		COMBAT_SECTOR_ROWS - 1,
	)
	return
}
combat_sector_label :: proc(grid: Combat_Engagement_Grid, p: Combat_Vec3) -> string {
	letters := [COMBAT_SECTOR_COLUMNS]string {
		"A",
		"B",
		"C",
		"D",
		"E",
		"F",
	}; column, row := combat_sector_indices(grid, p); return fmt.tprintf("%s%d", letters[column], row + 1)
}
combat_depth_plane :: proc(grid: Combat_Engagement_Grid, z: f32) -> Combat_Depth_Plane {if z < grid.low_ceiling do return .Low
	if z > grid.high_floor do return .High
	return .Plane}
combat_depth_plane_name :: proc(plane: Combat_Depth_Plane) -> string {switch plane {case .Low:
		return "LOW"; case .Plane:
		return "PLANE"; case .High:
		return "HIGH"}; return "PLANE"}
combat_depth_plane_record_name :: proc(plane: Combat_Depth_Plane) -> string {switch
	plane {case .Low:
		return "Low"; case .Plane:
		return "Plane"; case .High:
		return "High"}
	return "Plane"}
combat_location_label :: proc(
	grid: Combat_Engagement_Grid,
	p: Combat_Vec3,
) -> string {return fmt.tprintf(
		"%s %s",
		combat_sector_label(grid, p),
		combat_depth_plane_name(combat_depth_plane(grid, p.z)),
	)}
combat_add_event :: proc(m: ^Combat_Mission, text: string) {i := 9; for i > 0 {m.event_text[i] =
			m.event_text[i - 1]
		m.event_time[i] = m.event_time[i - 1]
		i -= 1}
	m.event_text[0] = text
	m.event_time[0] = m.time
	m.event_count = min(m.event_count + 1, 10)
	m.event_serial += 1}
combat_add_event_at :: proc(m: ^Combat_Mission, text: string, p: Combat_Vec3) {combat_add_event(
		m,
		fmt.tprintf(
			"%s in Sector %s %s.",
			text,
			combat_sector_label(m.grid, p),
			combat_depth_plane_record_name(combat_depth_plane(m.grid, p.z)),
		),
	)}

// Guided missiles are routine, rapid-fire weapons. Report a burst's result,
// not every projectile in it; torpedoes remain individually noteworthy.
combat_report_guided_hit :: proc(
	m: ^Combat_Mission,
	salvo: Combat_Salvo,
	text: string,
	p: Combat_Vec3,
) {
	if m.event_count > 0 &&
	   m.last_guided_hit_source == salvo.source &&
	   m.last_guided_hit_target == salvo.target &&
	   m.time - m.last_guided_hit_time <= 1.5 {
		return
	}
	combat_add_event_at(m, text, p)
	m.last_guided_hit_source = salvo.source
	m.last_guided_hit_target = salvo.target
	m.last_guided_hit_time = m.time
}

// Do not raise a terminal warning after the player's useful command window has
// already closed. Slower torpedoes remain visible deeper into their approach.
combat_salvo_warning_actionable :: proc(salvo: Combat_Salvo) -> bool {
	if !salvo.active do return false
	reaction_window: f32 = salvo.weapon == .Guided_Missile ? 2.5 : 1
	return salvo.time_remaining >= reaction_window
}

combat_role_tonnage :: proc(role: Combat_Role) -> f32 {
	switch role {
	case .Fighter:
		return 8
	case .Bomber:
		return 10
	case .Corvette:
		return 15
	case .Recovery:
		return 20
	case .Carrier:
		return 28
	case .Capital:
		return 40
	}
	return 8
}

combat_wreckage_radius :: proc(tonnage: f32) -> f32 {return tonnage * .45}

combat_add_wreckage_to_field :: proc(
	field: ^Combat_Wreckage_Field,
	side: Combat_Side,
	ships: int,
	tonnage: f32,
	position: Combat_Vec3,
) {
	if ships <= 0 do return
	old_tonnage := field.tonnage; new_tonnage := old_tonnage + tonnage
	if old_tonnage >
	   0 {field.center.x = (field.center.x * old_tonnage + position.x * tonnage) / new_tonnage; field.center.y = (field.center.y * old_tonnage + position.y * tonnage) / new_tonnage; field.center.z = (field.center.z * old_tonnage + position.z * tonnage) / new_tonnage} else {field.center = position}
	if side == .Friendly {field.friendly_ships += ships} else {field.raider_ships += ships}
	field.tonnage = new_tonnage; field.radius = combat_wreckage_radius(new_tonnage)
}

// Small losses remain individual contacts. Once eight hulls accumulate around
// an element, their exact losses become a persistent tactical wreckage field.
combat_record_wreckage :: proc(
	m: ^Combat_Mission,
	element, destroyed: int,
	position: Combat_Vec3,
) {
	if destroyed <= 0 || element < 0 || element >= m.unit_count do return
	side :=
		m.units[element].side; tonnage := f32(destroyed) * combat_role_tonnage(m.units[element].role)
	nearest := -1; nearest_distance: f32 = 100000
	for &field, i in m.wreckage_fields[:m.wreckage_field_count] {distance := combat_distance(position, field.center); if distance <= field.radius + 70 && distance < nearest_distance {nearest = i; nearest_distance = distance}}
	if nearest >=
	   0 {combat_add_wreckage_to_field(&m.wreckage_fields[nearest], side, destroyed, tonnage, position); return}
	pending :=
		m.wreckage_pending[element]; total := pending + destroyed; pending_tonnage := m.wreckage_pending_tonnage[element]; total_tonnage := pending_tonnage + tonnage
	if pending >
	   0 {prior := m.wreckage_pending_position[element]; m.wreckage_pending_position[element] = {(prior.x * pending_tonnage + position.x * tonnage) / total_tonnage, (prior.y * pending_tonnage + position.y * tonnage) / total_tonnage, (prior.z * pending_tonnage + position.z * tonnage) / total_tonnage}} else {m.wreckage_pending_position[element] = position}
	m.wreckage_pending[element] = total
	m.wreckage_pending_tonnage[element] = total_tonnage
	if total < COMBAT_WRECKAGE_THRESHOLD do return
	field_index := m.wreckage_field_count
	created := field_index < COMBAT_MAX_WRECKAGE_FIELDS
	if created {m.wreckage_field_count += 1} else {field_index = 0; nearest_distance = combat_distance(position, m.wreckage_fields[0].center); for &field, i in m.wreckage_fields[1:] {distance := combat_distance(position, field.center); if distance < nearest_distance {field_index = i + 1; nearest_distance = distance}}}
	combat_add_wreckage_to_field(
		&m.wreckage_fields[field_index],
		side,
		total,
		total_tonnage,
		m.wreckage_pending_position[element],
	)
	m.wreckage_pending[element] = 0; m.wreckage_pending_tonnage[element] = 0; m.wreckage_pending_position[element] = {}
	if created do combat_add_event_at(m, "Concentrated ship losses formed a wreckage field", m.wreckage_fields[field_index].center)
}
