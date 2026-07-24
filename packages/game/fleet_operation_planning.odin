package game

import "core:math"

COMBAT_OPERATION_VERSION :: 1
COMBAT_PLAN_VERSION :: 1
COMBAT_PLAN_MAX_WAYPOINTS :: 12
COMBAT_PLAN_MAX_CONTINGENCIES :: 6
COMBAT_OPERATION_MAX_FEATURES :: 32
COMBAT_OPERATION_MAX_NAV_NODES :: 32
COMBAT_OPERATION_MAX_INTEL :: 16
COMBAT_OPERATION_MAX_ISSUES :: 32

Combat_Operation_Context :: enum {
	None,
	Campaign,
	Skirmish,
	Linked,
}

Combat_Objective_Priority_Policy :: enum {
	Preserve_Force,
	Balanced,
	Complete_At_Cost,
}

Combat_Engagement_Policy :: enum {
	Avoid,
	Defend,
	Favorable,
	Seek_Battle,
}

Combat_Cohesion_Policy :: enum {
	Tight,
	Mutual_Support,
	Flexible,
	Independent,
}

Combat_Pursuit_Policy :: enum {
	None,
	To_Boundary,
	Until_Disabled,
}

Combat_Withdrawal_Policy :: enum {
	Early,
	Damaged,
	Critical,
	Never_Autonomous,
}

Combat_Rescue_Policy :: enum {
	Safe_Only,
	Accept_Risk,
	Leave_Disabled,
}

Combat_Ordnance_Policy :: enum {
	Conserve,
	Confirmed_Priority,
	Liberal,
}

Combat_Target_Policy :: enum {
	Objective_Threats,
	Strike_Craft,
	Support,
	Capitals,
}

Combat_Doctrine_Policy :: struct {
	preset:     Combat_Doctrine,
	objective:  Combat_Objective_Priority_Policy,
	engagement: Combat_Engagement_Policy,
	cohesion:   Combat_Cohesion_Policy,
	pursuit:    Combat_Pursuit_Policy,
	withdrawal: Combat_Withdrawal_Policy,
	rescue:     Combat_Rescue_Policy,
	ordnance:   Combat_Ordnance_Policy,
	emissions:  Combat_Emission_Policy,
	targets:    Combat_Target_Policy,
}

Combat_Plan_Volume_Kind :: enum {
	Sphere,
	Cylinder,
}

Combat_Plan_Route :: struct {
	waypoints: [COMBAT_PLAN_MAX_WAYPOINTS]Combat_Vec3,
	count:     int,
}

Combat_Plan_Volume :: struct {
	kind:                Combat_Plan_Volume_Kind,
	center:              Combat_Vec3,
	radius, half_height: f32,
}

Combat_Contingency_Trigger :: enum {
	None,
	Objective_Complete,
	Protected_Group_Threatened,
	Capability_Lost,
	Casualty_Threshold,
	Contact_Classified,
	Route_Blocked,
	Extraction_Window,
}

Combat_Contingency_Action :: enum {
	None,
	Follow_Fallback,
	Screen_Group,
	Commit_Reserve,
	Disengage,
	Request_Exception,
}

Combat_Plan_Contingency :: struct {
	trigger:                     Combat_Contingency_Trigger,
	action:                      Combat_Contingency_Action,
	subject_group, target_group: int,
	threshold:                   f32,
	enabled, fired:              bool,
}

Combat_Task_Group_Plan :: struct {
	id:                                 u32,
	name:                               string,
	custom_name:                        [32]u8,
	custom_name_length:                 int,
	active, locked, reserve, withdrawn: bool,
	order:                              Combat_Order,
	objective_index, support_group:     int,
	primary_route, withdrawal_route:    Combat_Plan_Route,
	boundary:                           Combat_Plan_Volume,
	doctrine:                           Combat_Doctrine_Policy,
	contingencies:                      [COMBAT_PLAN_MAX_CONTINGENCIES]Combat_Plan_Contingency,
	contingency_count:                  int,
}

Combat_Plan_Assignment :: struct {
	ship:              Ship_ID,
	unit_index, group: int,
	archetype:         Ship_Hull_Archetype,
	locked:            bool,
}

Combat_Plan_Issue :: enum {
	None,
	No_Groups,
	Unassigned_Ship,
	Primary_Objective_Unassigned,
	Capability_Missing,
	Route_Missing,
	Route_Outside_Grid,
	Route_Impassable,
	Withdrawal_Missing,
	Invalid_Support,
	Reserve_Without_Trigger,
	Invalid_Contingency,
	Contingency_Cycle,
	Timing_Missed,
	Thin_Redundancy,
	Uncertain_Intelligence,
	Hazardous_Route,
	Weak_Time_Margin,
	Unauthorized_Deviation,
	Exposed_Extraction,
}

Combat_Plan_Validation :: struct {
	errors, warnings:           [COMBAT_OPERATION_MAX_ISSUES]Combat_Plan_Issue,
	error_count, warning_count: int,
	valid:                      bool,
}

Combat_Plan_Forecast :: struct {
	route_time_min, exposure, sensor_coverage, mutual_support: f32,
	capability_confidence, extraction_margin:                  f32,
}

Combat_Operation_Plan :: struct {
	version:                        int,
	id:                             u64,
	committed, immutable:           bool,
	groups:                         [COMBAT_GROUP_COUNT]Combat_Task_Group_Plan,
	group_count:                    int,
	assignments:                    [MAX_SHIPS]Combat_Plan_Assignment,
	assignment_count:               int,
	objective_groups:               [3]int,
	fire_control:                   Combat_Fire_Control,
	validation:                     Combat_Plan_Validation,
	forecasts:                      [COMBAT_GROUP_COUNT]Combat_Plan_Forecast,
	revision:                       u32,
	authority_deviation_authorized: bool,
	authority_breach:               bool,
	authority_breach_clause:        Operation_Authority_Clause,
}

Combat_Operation_Feature_Kind :: enum {
	Open_Lane,
	Debris,
	Wreckage,
	Radiation,
	Sensor_Shadow,
	Communication_Shadow,
}

Combat_Operation_Feature :: struct {
	id:         u32,
	kind:       Combat_Operation_Feature_Kind,
	volume:     Combat_Plan_Volume,
	impassable: bool,
}

Combat_Operation_Nav_Node :: struct {
	id:             u32,
	position:       Combat_Vec3,
	neighbors:      [8]int,
	neighbor_count: int,
}

Combat_Intel_Contact :: struct {
	id:                             u32,
	estimate:                       Combat_Vec3,
	uncertainty_radius, confidence: f32,
	role:                           Combat_Role,
	identified, reinforcement:      bool,
}

Combat_Operation_Battlespace :: struct {
	grid:                                    Combat_Engagement_Grid,
	features:                                [COMBAT_OPERATION_MAX_FEATURES]Combat_Operation_Feature,
	feature_count:                           int,
	nodes:                                   [COMBAT_OPERATION_MAX_NAV_NODES]Combat_Operation_Nav_Node,
	node_count:                              int,
	friendly_deployment, hostile_deployment: Combat_Plan_Volume,
	extraction, reinforcement:               Combat_Plan_Volume,
	objective_positions:                     [3]Combat_Vec3,
	objective_count:                         int,
}

Combat_Operation_Intelligence :: struct {
	contacts:      [COMBAT_OPERATION_MAX_INTEL]Combat_Intel_Contact,
	contact_count: int,
	quality:       f32,
}

Combat_Operation_Chain_Ship :: struct {
	ship:                       Ship_ID,
	position, velocity:         Combat_Vec3,
	hull:                       f32,
	torpedoes, ability_charges: int,
	disabled, extracted:        bool,
}

Combat_Operation_Chain :: struct {
	active:                bool,
	battle_index:          int,
	elapsed_time:          f32,
	ships:                 [MAX_SHIPS]Combat_Operation_Chain_Ship,
	ship_count:            int,
	known_contacts:        [COMBAT_OPERATION_MAX_INTEL]Combat_Intel_Contact,
	known_contact_count:   int,
	wreckage:              [COMBAT_MAX_WRECKAGE_FIELDS]Combat_Wreckage_Field,
	wreckage_count:        int,
	unresolved_objectives: [3]Skirmish_Objective,
	unresolved_count:      int,
}

Combat_Operation :: struct {
	version:                                                                  int,
	active:                                                                   bool,
	operation_context:                                                        Combat_Operation_Context,
	seed, geography_seed, objective_seed, intelligence_seed, enemy_plan_seed: u64,
	origin_event:                                                             u64,
	mission:                                                                  Skirmish_Mission_Kind,
	objectives:                                                               Skirmish_Objective_Contract,
	battlespace:                                                              Combat_Operation_Battlespace,
	intelligence:                                                             Combat_Operation_Intelligence,
	draft, committed_plan, enemy_plan:                                        Combat_Operation_Plan,
	chain:                                                                    Combat_Operation_Chain,
	authority:                                                                Operation_Authority,
}

combat_authority_doctrine :: proc(a: ^Operation_Authority) -> Combat_Doctrine_Policy {
	if a == nil || !a.valid do return combat_doctrine_policy(.Balanced)
	policy := combat_doctrine_policy(.Balanced)
	switch a.exposure {
	case .Conservative:
		policy.objective = .Preserve_Force; policy.engagement = .Defend
	case .Proportional:
		policy.objective = .Balanced; policy.engagement = .Favorable
	case .Mission_Critical:
		policy.objective = .Complete_At_Cost; policy.engagement = .Seek_Battle
	}
	switch a.withdrawal {
	case .Command_Discretion:
		policy.withdrawal = .Damaged
	case .Protected_Return:
		policy.withdrawal = .Early
	case .Mandatory_Threshold:
		policy.withdrawal = .Critical
	}
	switch a.rescue {
	case .Discretionary:
		policy.rescue = .Safe_Only
	case .Mutual_Aid:
		policy.rescue = .Accept_Risk
	case .Absolute_Duty:
		policy.rescue = .Accept_Risk
	}
	switch a.ordnance {
	case .Defensive_Only:
		policy.ordnance = .Conserve
	case .Confirmed_Targets:
		policy.ordnance = .Confirmed_Priority
	case .Unrestricted:
		policy.ordnance = .Liberal
	}
	return policy
}

apply_operation_authority_to_combat :: proc(
	operation: ^Combat_Operation,
	authority: Operation_Authority,
) -> bool {
	if operation == nil ||
	   !authority.valid ||
	   operation_objective_kind(authority.objective) != .Combat {
		return false
	}
	operation.authority = authority
	authority_copy := authority
	policy := combat_authority_doctrine(&authority_copy)
	for &group in operation.draft.groups[:operation.draft.group_count] do if group.active {
		group.doctrine = policy
	}
	return true
}

combat_plan_within_authority :: proc(
	operation: ^Combat_Operation,
	plan: ^Combat_Operation_Plan,
) -> (
	bool,
	Operation_Authority_Clause,
) {
	if operation == nil || plan == nil || !operation.authority.valid do return true, .None
	expected := combat_authority_doctrine(&operation.authority)
	for group in plan.groups[:plan.group_count] do if group.active {
		if group.doctrine.rescue != expected.rescue do return false, .Rescue
		if group.doctrine.withdrawal != expected.withdrawal do return false, .Withdrawal
		if group.doctrine.ordnance != expected.ordnance do return false, .Ordnance
		if group.doctrine.objective != expected.objective do return false, .Exposure
	}
	return true, .None
}

combat_doctrine_policy :: proc(preset: Combat_Doctrine) -> Combat_Doctrine_Policy {
	switch preset {
	case .Cautious_Screen:
		return {
			preset = preset,
			objective = .Preserve_Force,
			engagement = .Defend,
			cohesion = .Tight,
			pursuit = .None,
			withdrawal = .Early,
			rescue = .Safe_Only,
			ordnance = .Conserve,
			emissions = .Passive_First,
			targets = .Objective_Threats,
		}
	case .Hunter_Killer:
		return {
			preset = preset,
			objective = .Complete_At_Cost,
			engagement = .Seek_Battle,
			cohesion = .Flexible,
			pursuit = .Until_Disabled,
			withdrawal = .Critical,
			rescue = .Accept_Risk,
			ordnance = .Liberal,
			emissions = .Continuous,
			targets = .Capitals,
		}
	case .Last_Stand:
		return {
			preset = preset,
			objective = .Complete_At_Cost,
			engagement = .Seek_Battle,
			cohesion = .Mutual_Support,
			pursuit = .To_Boundary,
			withdrawal = .Never_Autonomous,
			rescue = .Accept_Risk,
			ordnance = .Liberal,
			emissions = .Continuous,
			targets = .Objective_Threats,
		}
	case .Balanced:
	}
	return {
		preset = .Balanced,
		objective = .Balanced,
		engagement = .Favorable,
		cohesion = .Mutual_Support,
		pursuit = .To_Boundary,
		withdrawal = .Damaged,
		rescue = .Safe_Only,
		ordnance = .Confirmed_Priority,
		emissions = .Burst_Sharing,
		targets = .Objective_Threats,
	}
}

combat_operation_random :: proc(state: ^u64) -> f32 {
	state^ = combat_mix(state^ + 0x9e3779b97f4a7c15)
	return f32(state^ & 0xffffff) / f32(0xffffff)
}

combat_operation_grid_contains :: proc(grid: Combat_Engagement_Grid, p: Combat_Vec3) -> bool {
	return(
		p.x >= grid.min_x &&
		p.x <= grid.max_x &&
		p.y >= grid.min_y &&
		p.y <= grid.max_y &&
		p.z >= -180 &&
		p.z <= 180 \
	)
}

combat_operation_route_length :: proc(route: Combat_Plan_Route) -> f32 {
	total: f32
	for index in 1 ..< route.count do total += combat_distance(route.waypoints[index - 1], route.waypoints[index])
	return total
}

combat_operation_point_in_volume :: proc(point: Combat_Vec3, volume: Combat_Plan_Volume) -> bool {
	dx, dy, dz := point.x - volume.center.x, point.y - volume.center.y, point.z - volume.center.z
	if volume.kind == .Cylinder {
		return(
			dx * dx + dy * dy <= volume.radius * volume.radius &&
			math.abs(dz) <= volume.half_height \
		)
	}
	return dx * dx + dy * dy + dz * dz <= volume.radius * volume.radius
}

combat_operation_segment_intersects_volume :: proc(
	a, b: Combat_Vec3,
	volume: Combat_Plan_Volume,
) -> bool {
	// Sampling at a spacing smaller than the minimum generated hazard radius
	// is deterministic and conservative for the authored volume primitives.
	length := combat_distance(a, b)
	steps := max(1, int(math.ceil(f64(length / 24))))
	for step in 0 ..= steps {
		t := f32(step) / f32(steps)
		point := Combat_Vec3{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t}
		if combat_operation_point_in_volume(point, volume) do return true
	}
	return false
}

combat_operation_clamp_to_volume :: proc(
	point: Combat_Vec3,
	volume: Combat_Plan_Volume,
) -> Combat_Vec3 {
	if combat_operation_point_in_volume(point, volume) do return point
	dx, dy, dz := point.x - volume.center.x, point.y - volume.center.y, point.z - volume.center.z
	if volume.kind == .Cylinder {
		length := math.sqrt(dx * dx + dy * dy)
		if length > 0 {
			scale := volume.radius / length
			dx *= scale
			dy *= scale
		}
		dz = clamp(dz, -volume.half_height, volume.half_height)
	} else {
		length := math.sqrt(dx * dx + dy * dy + dz * dz)
		if length > 0 {
			scale := volume.radius / length
			dx *= scale
			dy *= scale
			dz *= scale
		}
	}
	return {volume.center.x + dx, volume.center.y + dy, volume.center.z + dz}
}

combat_operation_add_edge :: proc(space: ^Combat_Operation_Battlespace, a, b: int) {
	if a < 0 || b < 0 || a >= space.node_count || b >= space.node_count do return
	left := &space.nodes[a]
	right := &space.nodes[b]
	if left.neighbor_count < len(left.neighbors) {
		left.neighbors[left.neighbor_count] = b
		left.neighbor_count += 1
	}
	if right.neighbor_count < len(right.neighbors) {
		right.neighbors[right.neighbor_count] = a
		right.neighbor_count += 1
	}
}

combat_operation_add_node :: proc(space: ^Combat_Operation_Battlespace, p: Combat_Vec3) -> int {
	if space.node_count >= len(space.nodes) do return -1
	index := space.node_count
	space.nodes[index] = {
		id       = u32(index + 1),
		position = p,
	}
	space.node_count += 1
	return index
}

combat_operation_generate_battlespace :: proc(
	seed: u64,
	objectives: Skirmish_Objective_Contract,
) -> Combat_Operation_Battlespace {
	space: Combat_Operation_Battlespace
	space.grid = {-900, 900, -900, 900, -55, 55}
	state := combat_mix(seed)
	space.friendly_deployment = {.Sphere, {-720, 0, 0}, 135, 135}
	space.hostile_deployment = {.Sphere, {720, 0, 0}, 150, 150}
	space.extraction = {.Cylinder, {-820, 260, 0}, 110, 150}
	space.reinforcement = {.Cylinder, {820, -260, 0}, 110, 150}
	space.objective_count = objectives.count
	for index in 0 ..< objectives.count {
		x := -120 + f32(index) * 190
		y := -220 + combat_operation_random(&state) * 440
		z := -90 + combat_operation_random(&state) * 180
		space.objective_positions[index] = {x, y, z}
	}
	feature_kinds := [6]Combat_Operation_Feature_Kind {
		.Debris,
		.Radiation,
		.Sensor_Shadow,
		.Communication_Shadow,
		.Wreckage,
		.Open_Lane,
	}
	for index in 0 ..< 18 {
		center := Combat_Vec3 {
			-520 + combat_operation_random(&state) * 1040,
			-620 + combat_operation_random(&state) * 1240,
			-140 + combat_operation_random(&state) * 280,
		}
		kind := feature_kinds[index % len(feature_kinds)]
		radius := 70 + combat_operation_random(&state) * 125
		space.features[index] = {
			id = u32(index + 1),
			kind = kind,
			volume = {
				kind = index % 3 == 0 ? .Cylinder : .Sphere,
				center = center,
				radius = radius,
				half_height = 70 + combat_operation_random(&state) * 90,
			},
			impassable = kind == .Radiation && radius > 150,
		}
		space.feature_count += 1
	}
	start := combat_operation_add_node(&space, space.friendly_deployment.center)
	extract := combat_operation_add_node(&space, space.extraction.center)
	combat_operation_add_edge(&space, start, extract)
	for objective_index in 0 ..< objectives.count {
		objective := combat_operation_add_node(&space, space.objective_positions[objective_index])
		upper := combat_operation_add_node(
			&space,
			{-390 + f32(objective_index) * 80, -250 + f32(objective_index) * 80, 90},
		)
		lower := combat_operation_add_node(
			&space,
			{-350 + f32(objective_index) * 75, 260 - f32(objective_index) * 70, -90},
		)
		combat_operation_add_edge(&space, start, upper)
		combat_operation_add_edge(&space, upper, objective)
		combat_operation_add_edge(&space, start, lower)
		combat_operation_add_edge(&space, lower, objective)
		combat_operation_add_edge(&space, objective, extract)
	}
	// Reject the entire unseen candidate when either of the two authored
	// approaches intersects an impassable feature. Nothing is repaired after
	// the battlespace becomes player-visible.
	for feature in space.features[:space.feature_count] do if feature.impassable {
		for node in space.nodes[:space.node_count] {
			for neighbor_index in 0 ..< node.neighbor_count {
				neighbor := node.neighbors[neighbor_index]
				if neighbor <= int(node.id) - 1 do continue
				if combat_operation_segment_intersects_volume(node.position, space.nodes[neighbor].position, feature.volume) {
					return combat_operation_generate_battlespace(combat_mix(seed + 1), objectives)
				}
			}
		}
	}
	return space
}

combat_operation_generate_intelligence :: proc(
	seed: u64,
	space: ^Combat_Operation_Battlespace,
	faction_count: int,
) -> Combat_Operation_Intelligence {
	intel: Combat_Operation_Intelligence
	state := combat_mix(seed)
	intel.quality = .45 + combat_operation_random(&state) * .35
	count := clamp(2 + faction_count, 3, 8)
	for index in 0 ..< count {
		error := 45 + (1 - intel.quality) * 180
		intel.contacts[index] = {
			id                 = u32(index + 1),
			estimate           = {
				space.hostile_deployment.center.x - combat_operation_random(&state) * 360,
				space.hostile_deployment.center.y - 260 + combat_operation_random(&state) * 520,
				-130 + combat_operation_random(&state) * 260,
			},
			uncertainty_radius = error,
			confidence         = intel.quality * (.72 + combat_operation_random(&state) * .28),
			role               = index == count - 1 ? .Capital : index % 3 == 0 ? .Bomber : .Fighter,
			identified         = intel.quality > .68 && index < 2,
			reinforcement      = index == count - 1,
		}
		intel.contact_count += 1
	}
	return intel
}

combat_plan_default_group_name :: proc(index: int) -> string {
	names := [COMBAT_GROUP_COUNT]string {
		"Screen",
		"Strike",
		"Recovery",
		"Recon",
		"Line",
		"Support",
		"Reserve",
		"Rearguard",
	}
	return names[clamp(index, 0, COMBAT_GROUP_COUNT - 1)]
}

combat_plan_group_name :: proc(group: ^Combat_Task_Group_Plan) -> string {
	if group != nil &&
	   group.custom_name_length > 0 &&
	   group.custom_name_length <= len(group.custom_name) {
		return string(group.custom_name[:group.custom_name_length])
	}
	if group != nil do return group.name
	return ""
}

combat_plan_seed_route :: proc(
	space: ^Combat_Operation_Battlespace,
	objective_index, variant: int,
) -> Combat_Plan_Route {
	route: Combat_Plan_Route
	target :=
		space.objective_positions[clamp(objective_index, 0, max(space.objective_count - 1, 0))]
	route.waypoints[0] = space.friendly_deployment.center
	node_base := 2 + clamp(objective_index, 0, max(space.objective_count - 1, 0)) * 3
	route.waypoints[1] = space.nodes[node_base + (variant == 0 ? 1 : 2)].position
	route.waypoints[2] = target
	route.count = 3
	return route
}

combat_plan_seed_withdrawal :: proc(
	space: ^Combat_Operation_Battlespace,
	from: Combat_Vec3,
) -> Combat_Plan_Route {
	route: Combat_Plan_Route
	route.waypoints[0] = from
	route.waypoints[1] = space.extraction.center
	route.count = 2
	return route
}

combat_plan_recommend_skirmish :: proc(
	setup: Skirmish_Setup,
	operation: ^Combat_Operation,
) -> Combat_Operation_Plan {
	plan: Combat_Operation_Plan
	plan.version = COMBAT_PLAN_VERSION
	plan.id = combat_mix(operation.seed ~ 0x706c616e)
	plan.fire_control = .Confirm_Costly
	active_groups := min(max(operation.objectives.count, 3), COMBAT_GROUP_COUNT)
	plan.group_count = active_groups
	for index in 0 ..< active_groups {
		group := &plan.groups[index]
		group.id = u32(index + 1)
		group.name = combat_plan_default_group_name(index)
		group.active = true
		group.objective_index = min(index, operation.objectives.count - 1)
		group.support_group = -1
		group.order = index == 0 ? .Guard : index == 1 ? .Attack : index == 2 ? .Recover : .Control
		group.reserve = index >= operation.objectives.count
		group.primary_route = combat_plan_seed_route(
			&operation.battlespace,
			group.objective_index,
			index % 2,
		)
		group.withdrawal_route = combat_plan_seed_withdrawal(
			&operation.battlespace,
			group.primary_route.waypoints[group.primary_route.count - 1],
		)
		group.boundary = {
			kind        = .Sphere,
			center      = operation.battlespace.objective_positions[group.objective_index],
			radius      = 240,
			half_height = 180,
		}
		group.doctrine = combat_doctrine_policy(
			index == 0 ? .Cautious_Screen : index == 1 ? .Hunter_Killer : .Balanced,
		)
		if group.reserve {
			group.contingencies[0] = {
				trigger       = .Protected_Group_Threatened,
				action        = .Commit_Reserve,
				subject_group = index,
				target_group  = 0,
				threshold     = 50,
				enabled       = true,
			}
			group.contingency_count = 1
		}
	}
	for index in 0 ..< len(setup.loadout) {
		group := index % active_groups
		setup_copy := setup
		if index == skirmish_recovery_loadout_index(&setup_copy) do group = min(2, active_groups - 1)
		plan.assignments[plan.assignment_count] = {
			unit_index = index,
			group      = group,
			archetype  = setup.loadout[index].archetype,
		}
		plan.assignment_count += 1
	}
	for objective_index in 0 ..< operation.objectives.count do plan.objective_groups[objective_index] = min(objective_index, active_groups - 1)
	plan.revision = 1
	return plan
}

combat_operation_generate_skirmish :: proc(setup: Skirmish_Setup) -> Combat_Operation {
	seed := max(setup.seed, u64(1))
	operation: Combat_Operation
	operation.version = COMBAT_OPERATION_VERSION
	operation.active = true
	operation.operation_context = .Skirmish
	operation.seed = seed
	operation.geography_seed = combat_mix(seed ~ 0x67656f)
	operation.objective_seed = combat_mix(setup.contract_seed ~ 0x6f626a)
	operation.intelligence_seed = combat_mix(seed ~ 0x696e74656c)
	operation.enemy_plan_seed = combat_mix(seed ~ 0x656e656d79)
	operation.mission = setup.mission
	operation.objectives = skirmish_generate_objectives(setup.contract_seed, setup.mission)
	operation.battlespace = combat_operation_generate_battlespace(
		operation.geography_seed,
		operation.objectives,
	)
	operation.intelligence = combat_operation_generate_intelligence(
		operation.intelligence_seed,
		&operation.battlespace,
		setup.faction_count,
	)
	enemy_basis := operation
	enemy_basis.seed = operation.enemy_plan_seed
	operation.enemy_plan = combat_plan_recommend_skirmish(setup, &enemy_basis)
	for &group in operation.enemy_plan.groups do if group.active {
		group.primary_route.waypoints[0] = operation.battlespace.hostile_deployment.center
		group.withdrawal_route.waypoints[group.withdrawal_route.count - 1] = operation.battlespace.reinforcement.center
		enemy_doctrine := Combat_Doctrine.Balanced
		if int(group.id + u32(operation.enemy_plan_seed & 3)) % 2 == 0 {
			enemy_doctrine = .Hunter_Killer
		}
		group.doctrine = combat_doctrine_policy(enemy_doctrine)
	}
	operation.enemy_plan.committed = true
	operation.enemy_plan.immutable = true
	operation.draft = combat_plan_recommend_skirmish(setup, &operation)
	operation.draft.validation = combat_operation_validate_plan(&operation, &operation.draft)
	return operation
}

combat_operation_migrate_campaign_draft :: proc(c: ^Campaign) {
	if c == nil || !c.combat_deployment_active || c.combat_deployment_count <= 0 {
		c.combat_operation = {}
		return
	}
	setup := skirmish_default_setup()
	setup.seed = max(c.combat_deployment_seed, u64(1))
	setup.contract_seed = combat_mix(setup.seed ~ u64(c.compact.active.id + 1))
	setup.mission = combat_campaign_mission_kind(c, setup.seed)
	operation := combat_operation_generate_skirmish(setup)
	operation.operation_context = .Campaign
	operation.origin_event = c.event_sequence
	authority := c.compact.active.charter.hard_authority
	authority_validation := validate_operation_authority(&authority, .Combat)
	if authority_validation.valid do _ = apply_operation_authority_to_combat(&operation, authority)
	operation.draft.assignment_count = 0
	for index in 0 ..< c.combat_deployment_count {
		group := clamp(c.combat_deployment_groups[index], 0, COMBAT_GROUP_COUNT - 1)
		operation.draft.groups[group].active = true
		operation.draft.groups[group].id = u32(group + 1)
		operation.draft.groups[group].name = combat_plan_default_group_name(group)
		operation.draft.groups[group].doctrine = combat_doctrine_policy(
			c.combat_deployment_doctrines[group],
		)
		operation.draft.assignments[index] = {
			ship       = c.combat_deployment_ships[index],
			unit_index = group,
			group      = group,
			archetype  = c.ships[ship_index(c, c.combat_deployment_ships[index])].hull_archetype,
		}
		operation.draft.assignment_count += 1
	}
	operation.draft.committed = false
	operation.draft.immutable = false
	operation.draft.validation = combat_operation_validate_plan(&operation, &operation.draft)
	c.combat_operation = operation
}

combat_operation_add_issue :: proc(
	validation: ^Combat_Plan_Validation,
	issue: Combat_Plan_Issue,
	error: bool,
) {
	if error {
		if validation.error_count < len(validation.errors) {
			validation.errors[validation.error_count] = issue
			validation.error_count += 1
		}
	} else if validation.warning_count < len(validation.warnings) {
		validation.warnings[validation.warning_count] = issue
		validation.warning_count += 1
	}
}

combat_plan_group_has_capability :: proc(
	plan: ^Combat_Operation_Plan,
	group_index: int,
	order: Combat_Order,
) -> bool {
	for assignment in plan.assignments[:plan.assignment_count] do if assignment.group == group_index {
		role := skirmish_role_for_hull(assignment.archetype)
		modules := ship_operational_role_modules(skirmish_role_for_hull_operational(assignment.archetype))
		switch order {
		case .Recover:
			if role == .Recovery || .Repair in modules do return true
		case .Control:
			if .Sensors in modules || role == .Carrier do return true
		case .Attack, .Intercept:
			if role == .Fighter || role == .Bomber || role == .Corvette || role == .Carrier || role == .Capital {
				return true
			}
		case .Guard, .Hold, .Move, .Withdraw, .Extract:
			return true
		}
	}
	return false
}

combat_plan_reference_reaches :: proc(plan: ^Combat_Operation_Plan, from, sought: int) -> bool {
	visited: [COMBAT_GROUP_COUNT]bool
	cursor := from
	for step in 0 ..< COMBAT_GROUP_COUNT {
		if cursor < 0 || cursor >= COMBAT_GROUP_COUNT || visited[cursor] do return false
		if cursor == sought do return true
		visited[cursor] = true
		cursor = plan.groups[cursor].support_group
	}
	return false
}

combat_plan_contingency_reaches :: proc(plan: ^Combat_Operation_Plan, from, sought: int) -> bool {
	pending: [COMBAT_GROUP_COUNT]int
	visited: [COMBAT_GROUP_COUNT]bool
	pending[0] = from
	count := 1
	for count > 0 {
		count -= 1
		current := pending[count]
		if current < 0 || current >= COMBAT_GROUP_COUNT || visited[current] do continue
		if current == sought do return true
		visited[current] = true
		group := plan.groups[current]
		if group.support_group >= 0 && count < len(pending) {
			pending[count] = group.support_group
			count += 1
		}
		for contingency in group.contingencies[:group.contingency_count] do if contingency.enabled && contingency.target_group >= 0 && (contingency.action == .Screen_Group || contingency.action == .Commit_Reserve) && count < len(pending) {
			pending[count] = contingency.target_group
			count += 1
		}
	}
	return false
}

combat_plan_route_valid :: proc(
	operation: ^Combat_Operation,
	route: Combat_Plan_Route,
) -> (
	inside, passable: bool,
) {
	if route.count < 2 || route.count > len(route.waypoints) do return false, false
	inside = true
	passable = true
	for point_index in 0 ..< route.count {
		point := route.waypoints[point_index]
		if !combat_operation_grid_contains(operation.battlespace.grid, point) do inside = false
		for feature in operation.battlespace.features[:operation.battlespace.feature_count] {
			if feature.impassable && combat_operation_point_in_volume(point, feature.volume) {
				passable = false
			}
		}
		if point_index > 0 {
			for feature in operation.battlespace.features[:operation.battlespace.feature_count] do if feature.impassable && combat_operation_segment_intersects_volume(route.waypoints[point_index - 1], point, feature.volume) {
				passable = false
			}
		}
	}
	return
}

combat_operation_validate_plan :: proc(
	operation: ^Combat_Operation,
	plan: ^Combat_Operation_Plan,
) -> Combat_Plan_Validation {
	validation: Combat_Plan_Validation
	if plan.group_count <= 0 do combat_operation_add_issue(&validation, .No_Groups, true)
	assigned_objectives: [3]bool
	assigned_units: [SKIRMISH_LOADOUT_SLOTS]bool
	assigned_ships: [MAX_SHIPS]Ship_ID
	assigned_ship_count := 0
	group_assignments: [COMBAT_GROUP_COUNT]int
	for assignment in plan.assignments[:plan.assignment_count] {
		if assignment.group < 0 ||
		   assignment.group >= COMBAT_GROUP_COUNT ||
		   !plan.groups[assignment.group].active {
			combat_operation_add_issue(&validation, .Unassigned_Ship, true)
		}
		if assignment.group >= 0 && assignment.group < COMBAT_GROUP_COUNT {
			group_assignments[assignment.group] += 1
		}
		if operation.operation_context == .Skirmish &&
		   assignment.unit_index >= 0 &&
		   assignment.unit_index < len(assigned_units) {
			if assigned_units[assignment.unit_index] do combat_operation_add_issue(&validation, .Unassigned_Ship, true)
			assigned_units[assignment.unit_index] = true
		}
		if operation.operation_context != .Skirmish && assignment.ship != 0 {
			for ship in assigned_ships[:assigned_ship_count] do if ship == assignment.ship {
				combat_operation_add_issue(&validation, .Unassigned_Ship, true)
			}
			if assigned_ship_count < len(assigned_ships) {
				assigned_ships[assigned_ship_count] = assignment.ship
				assigned_ship_count += 1
			}
		}
	}
	for group, index in plan.groups {
		if !group.active do continue
		if group.id == 0 do combat_operation_add_issue(&validation, .Invalid_Support, true)
		for prior in 0 ..< index do if plan.groups[prior].active && plan.groups[prior].id == group.id {
			combat_operation_add_issue(&validation, .Invalid_Support, true)
		}
		if group_assignments[index] == 0 && !group.reserve {
			combat_operation_add_issue(&validation, .Capability_Missing, true)
		}
		if group.objective_index >= 0 && group.objective_index < operation.objectives.count {
			assigned_objectives[group.objective_index] = true
		}
		inside, passable := combat_plan_route_valid(operation, group.primary_route)
		if group.primary_route.count < 2 do combat_operation_add_issue(&validation, .Route_Missing, true)
		if !inside do combat_operation_add_issue(&validation, .Route_Outside_Grid, true)
		if !passable do combat_operation_add_issue(&validation, .Route_Impassable, true)
		if group.primary_route.count > 0 &&
		   !combat_operation_point_in_volume(
				   group.primary_route.waypoints[0],
				   operation.battlespace.friendly_deployment,
			   ) {
			combat_operation_add_issue(&validation, .Route_Missing, true)
		}
		if group.primary_route.count > 0 &&
		   group.objective_index >= 0 &&
		   group.objective_index < operation.battlespace.objective_count &&
		   combat_distance(
			   group.primary_route.waypoints[group.primary_route.count - 1],
			   operation.battlespace.objective_positions[group.objective_index],
		   ) >
			   80 {
			combat_operation_add_issue(&validation, .Timing_Missed, true)
		}
		inside, passable = combat_plan_route_valid(operation, group.withdrawal_route)
		if group.withdrawal_route.count < 2 do combat_operation_add_issue(&validation, .Withdrawal_Missing, true)
		if !inside do combat_operation_add_issue(&validation, .Route_Outside_Grid, true)
		if !passable do combat_operation_add_issue(&validation, .Route_Impassable, true)
		if group.withdrawal_route.count > 0 &&
		   !combat_operation_point_in_volume(
				   group.withdrawal_route.waypoints[group.withdrawal_route.count - 1],
				   operation.battlespace.extraction,
			   ) {
			combat_operation_add_issue(&validation, .Withdrawal_Missing, true)
		}
		if group.boundary.radius <= 0 ||
		   group.boundary.kind == .Cylinder && group.boundary.half_height <= 0 ||
		   !combat_operation_grid_contains(operation.battlespace.grid, group.boundary.center) {
			combat_operation_add_issue(&validation, .Route_Outside_Grid, true)
		}
		if group.support_group >= 0 &&
		   (group.support_group >= COMBAT_GROUP_COUNT ||
				   group.support_group == index ||
				   !plan.groups[group.support_group].active) {
			combat_operation_add_issue(&validation, .Invalid_Support, true)
		}
		if group.support_group >= 0 &&
		   combat_plan_reference_reaches(plan, group.support_group, index) {
			combat_operation_add_issue(&validation, .Contingency_Cycle, true)
		}
		has_capability := combat_plan_group_has_capability(plan, index, group.order)
		if !has_capability && group.support_group >= 0 {
			has_capability = combat_plan_group_has_capability(
				plan,
				group.support_group,
				group.order,
			)
		}
		if !group.reserve && !has_capability {
			combat_operation_add_issue(&validation, .Capability_Missing, true)
		}
		has_reserve_trigger := false
		for contingency_index in 0 ..< group.contingency_count {
			contingency := group.contingencies[contingency_index]
			if !contingency.enabled do continue
			if contingency.trigger == .None || contingency.action == .None {
				combat_operation_add_issue(&validation, .Invalid_Contingency, true)
			}
			if contingency.action == .Commit_Reserve do has_reserve_trigger = true
			if contingency.target_group == index &&
			   (contingency.action == .Screen_Group || contingency.action == .Commit_Reserve) {
				combat_operation_add_issue(&validation, .Contingency_Cycle, true)
			}
			if contingency.target_group >= 0 &&
			   combat_plan_contingency_reaches(plan, contingency.target_group, index) {
				combat_operation_add_issue(&validation, .Contingency_Cycle, true)
			}
			for prior_index in 0 ..< contingency_index {
				prior := group.contingencies[prior_index]
				if prior.enabled &&
				   prior.trigger == contingency.trigger &&
				   prior.action != contingency.action {
					combat_operation_add_issue(&validation, .Invalid_Contingency, true)
				}
			}
			if contingency.target_group >= COMBAT_GROUP_COUNT ||
			   contingency.subject_group < 0 ||
			   contingency.subject_group >= COMBAT_GROUP_COUNT {
				combat_operation_add_issue(&validation, .Invalid_Contingency, true)
			}
			if contingency.target_group >= 0 && !plan.groups[contingency.target_group].active {
				combat_operation_add_issue(&validation, .Invalid_Contingency, true)
			}
		}
		if group.reserve && !has_reserve_trigger do combat_operation_add_issue(&validation, .Reserve_Without_Trigger, true)
		length := combat_operation_route_length(group.primary_route)
		hazard_crossings := 0
		for waypoint in 1 ..< group.primary_route.count {
			for feature in operation.battlespace.features[:operation.battlespace.feature_count] do if !feature.impassable && combat_operation_segment_intersects_volume(group.primary_route.waypoints[waypoint - 1], group.primary_route.waypoints[waypoint], feature.volume) {
				hazard_crossings += 1
			}
		}
		support_score: f32 = 35
		if group.support_group >= 0 &&
		   group.primary_route.count > 0 &&
		   plan.groups[group.support_group].primary_route.count > 0 {
			support := plan.groups[group.support_group]
			support_score = clamp(
				100 -
				combat_distance(
					group.primary_route.waypoints[group.primary_route.count - 1],
					support.primary_route.waypoints[support.primary_route.count - 1],
				) /
					5,
				0,
				100,
			)
		}
		plan.forecasts[index] = {
			route_time_min        = length / 2.2,
			exposure              = clamp(length / 18 + f32(hazard_crossings) * 12, 0, 100),
			sensor_coverage       = operation.intelligence.quality * 100,
			mutual_support        = support_score,
			capability_confidence = has_capability ? 88 : 20,
			extraction_margin     = max(
				0,
				100 - combat_operation_route_length(group.withdrawal_route) / 10,
			),
		}
		if plan.forecasts[index].extraction_margin < 20 do combat_operation_add_issue(&validation, .Exposed_Extraction, false)
	}
	for objective, index in operation.objectives.objectives[:operation.objectives.count] {
		if !objective.optional && !assigned_objectives[index] {
			combat_operation_add_issue(&validation, .Primary_Objective_Unassigned, true)
		}
	}
	if operation.intelligence.quality < .55 do combat_operation_add_issue(&validation, .Uncertain_Intelligence, false)
	within_authority, clause := combat_plan_within_authority(operation, plan)
	if !within_authority {
		if operation_authority_allows_deviation(
			&operation.authority,
			plan.authority_deviation_authorized,
		) {
			plan.authority_breach = true
			plan.authority_breach_clause = clause
			combat_operation_add_issue(&validation, .Unauthorized_Deviation, false)
		} else {
			combat_operation_add_issue(&validation, .Unauthorized_Deviation, true)
		}
	}
	validation.valid = validation.error_count == 0
	return validation
}

combat_operation_commit :: proc(operation: ^Combat_Operation) -> bool {
	if operation == nil || !operation.active || operation.draft.committed do return false
	operation.draft.validation = combat_operation_validate_plan(operation, &operation.draft)
	if !operation.draft.validation.valid do return false
	operation.draft.committed = true
	operation.draft.immutable = true
	operation.draft.id = combat_mix(operation.draft.id ~ u64(operation.draft.revision))
	operation.committed_plan = operation.draft
	return true
}
