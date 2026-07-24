package game

import "core:math"

PROCEDURAL_SHIP_MAX_MODULES :: 64

Procedural_Ship_Family :: enum u8 {
	Strike,
	Fleet,
	Habitat,
}
Procedural_Ship_Module :: enum u8 {
	Keel,
	Bow,
	Drive,
	Armor,
	Pressure_Hull,
	Truss,
	Tank,
	Radiator,
	Mission,
	Dock,
	Antenna,
	Ring_Segment,
}
Ship_Material_Class :: enum u8 {
	Hull_Plate,
	Armor,
	Truss,
	Pressure_Vessel,
	Radiator,
	Drive,
	Glass,
	Machinery,
}

Procedural_Ship_Service_Mark :: enum u8 {
	None,
	Patch_Plate,
	Breach_Cage,
	Dark_Scar,
}

Procedural_Ship_Frame :: struct {
	keel_length, beam, height:         f32,
	station_count, ring_station_count: int,
}

Procedural_Ship_Socket :: struct {
	id:                                    u32,
	parent:                                i16,
	position:                              [3]f32,
	direction:                             [3]f32,
	exposed, pressure_required, symmetric: bool,
	domain:                                u16,
}

Procedural_Ship_Placement :: struct {
	id, surface_id:   u32,
	socket:           i16,
	// Presentation form selected by immutable construction identity. Zero is a
	// valid default so raw procedural recipes remain backwards compatible.
	variant:          u8,
	mount_variant:    u8,
	// -1/0/+1 records a low/nominal/high-output drive installation. Bell count
	// uses this discrete construction trait while scale retains the finer power
	// variation, keeping a ship's machinery legible rather than merely larger.
	drive_power_tier: i8,
	service_mark:     Procedural_Ship_Service_Mark,
	module:           Procedural_Ship_Module,
	material:         Ship_Material_Class,
	position, scale:  [3]f32,
	direction:        [3]f32,
	mass:             f32,
}

Procedural_Ship_Recipe :: struct {
	seed:                                                                     u64,
	family:                                                                   Procedural_Ship_Family,
	architecture:                                                             Ship_Generator_Kind,
	greebly_density:                                                          int,
	// Capability-derived presentation scales. Zero means nominal for raw test
	// recipes and construction-only contact sheets.
	drive_capability_scale, weapon_capability_scale:                          f32,
	weapon_package:                                                           Ship_Weapon_Package,
	frame:                                                                    Procedural_Ship_Frame,
	systems:                                                                  Procedural_Ship_System_Graph,
	socket_count, module_count:                                               int,
	sockets:                                                                  [PROCEDURAL_SHIP_MAX_MODULES]Procedural_Ship_Socket,
	modules:                                                                  [PROCEDURAL_SHIP_MAX_MODULES]Procedural_Ship_Placement,
	mass:                                                                     f32,
	complete, connected, pressure_connected, radiators_exposed, drives_valid: bool,
	backtracks:                                                               int,
	fingerprint:                                                              u64,
}

procedural_ship_family_name :: proc(family: Procedural_Ship_Family) -> string {
	switch family {case .Strike:
		return "STRIKE"; case .Fleet:
		return "FLEET"; case .Habitat:
		return "HABITAT / UTILITY"}
	return "FLEET"
}

ship_generator_kind_name :: proc(kind: Ship_Generator_Kind) -> string {
	supported := ship_generator_kind_supported(kind)
	switch supported {
	case .Modular_Frame:
		return "MODULAR FRAME"
	case .Single_Hull:
		return "SINGLE HULL"
	case .Delta:
		return "DELTA"
	case .Saucer:
		return "DELTA"
	}
	return "MODULAR FRAME"
}

ship_generator_kind_supported :: proc(kind: Ship_Generator_Kind) -> Ship_Generator_Kind {
	if kind == .Saucer do return .Delta
	return kind
}

ship_construction_style_name :: proc(style: Ship_Construction_Style) -> string {
	switch style {
	case .Distributed_Fabrication:
		return "DISTRIBUTED FABRICATION"
	case .Living_Hullcraft:
		return "LIVING HULLCRAFT"
	case .Machine_Partnership:
		return "MACHINE PARTNERSHIP"
	case .Closed_Cycle:
		return "CLOSED-CYCLE MASTERY"
	}
	return "DISTRIBUTED FABRICATION"
}

procedural_ship_apply_construction_style :: proc(
	r: ^Procedural_Ship_Recipe,
	style: Ship_Construction_Style,
) {
	for &module in r.modules[:r.module_count] {
		scale := [3]f32{1, 1, 1}
		switch style {
		case .Distributed_Fabrication:
			if module.module == .Truss || module.module == .Dock || module.module == .Radiator do scale = {1.08, 1.12, 1.12}
		case .Living_Hullcraft:
			if module.module == .Pressure_Hull || module.module == .Ring_Segment do scale = {1.06, 1.22, 1.22}
			if module.module == .Armor || module.module == .Keel do scale = {.94, .9, .9}
		case .Machine_Partnership:
			if module.module == .Keel || module.module == .Mission || module.module == .Antenna do scale = {1.12, 1.16, 1.22}
			if module.module == .Pressure_Hull || module.module == .Ring_Segment do scale = {.94, .9, .9}
		case .Closed_Cycle:
			if module.module == .Tank || module.module == .Pressure_Hull || module.module == .Ring_Segment do scale = {1.18, 1.14, 1.14}
			if module.module == .Radiator do scale = {.9, 1.28, 1.28}
			if module.module == .Truss do scale = {.9, .92, .92}
		}
		for axis in 0 ..< 3 do module.scale[axis] *= scale[axis]
		module.mass =
			module.scale[0] *
			module.scale[1] *
			module.scale[2] *
			procedural_ship_module_mass_factor(module.module)
	}
	r.mass = 0
	for module in r.modules[:r.module_count] do r.mass += module.mass
}

procedural_ship_family_from_name :: proc(name: string) -> Procedural_Ship_Family {
	switch name {case "strike":
		return .Strike; case "habitat", "utility":
		return .Habitat; case:
		return .Fleet}
}

procedural_ship_family_for_ship :: proc(ship: Ship) -> Procedural_Ship_Family {
	family := ship_hull_archetype_family(ship.hull_archetype)
	if family == .Unspecified && ship.operational_role != .Unspecified do family = ship_operational_role_family(ship.operational_role)
	switch family {
	case .Strike_Craft, .Light_Combatant:
		return .Strike
	case .Diaspora:
		return .Habitat
	case .Frigate, .Line_Warship, .Carrier_And_Command:
		return .Fleet
	case .Unspecified:
		switch ship.hull_class {
		case .Strike_Craft, .Corvette:
			return .Strike
		case .Fleet_Ship, .Cruiser, .Capital_Ship:
			return .Fleet
		case .Unspecified:
			if ship.role == .Habitat || ship.role == .Agriculture || ship.role == .Colony do return .Habitat
		}
	}
	return .Fleet
}

procedural_ship_role_signature :: proc(
	ship: Ship,
	family: Procedural_Ship_Family,
) -> Procedural_Ship_Module {
	switch ship.operational_role {
	case .Scout, .Picket_Ship, .Electronic_Warfare_Frigate, .Command_Ship, .Courier:
		return .Antenna
	case .Assault_Shuttle, .Escort_Carrier, .Fleet_Carrier, .Recovery_Tug:
		return .Dock
	case .Tanker, .Freighter, .Colony_Transport:
		return .Tank
	case .Hospital_Ship, .Habitat_Ship, .Seedship, .Generation_Ship, .Arkship:
		return .Pressure_Hull
	case .Fabricator_Ship, .Support_Frigate:
		return .Mission
	case .Interceptor,
	     .Fighter,
	     .Strike_Fighter,
	     .Bomber,
	     .Patrol_Boat,
	     .Corvette,
	     .Torpedo_Boat,
	     .Gunship,
	     .Flak_Frigate,
	     .Missile_Frigate,
	     .Shield_Frigate,
	     .Minelayer_Frigate,
	     .Destroyer,
	     .Light_Cruiser,
	     .Heavy_Cruiser,
	     .Battlecruiser,
	     .Battleship,
	     .Dreadnought:
		return .Armor
	case .Unspecified:
	}
	switch ship.role {case .Habitat, .Agriculture, .Hospital, .Colony:
		return .Pressure_Hull; case .Survey, .Archive:
		return .Antenna; case .Foundry:
		return .Mission; case .Escort:
		return .Armor}
	return family == .Habitat ? .Pressure_Hull : .Armor
}

procedural_ship_role_signature_emphasis :: proc(module: Procedural_Ship_Module) -> [3]f32 {
	// A refit must read in silhouette, not merely satisfy a module inventory.
	// Keep the envelope directional: sensor masts grow tall, docks and tanks grow
	// radially, armor broadens into shoulders, and working decks gain height.
	switch module {
	case .Antenna:
		return {1.08, 1.18, 1.62}
	case .Dock:
		return {1.18, 1.42, 1.42}
	case .Tank:
		return {1.2, 1.3, 1.3}
	case .Pressure_Hull:
		return {1.12, 1.28, 1.28}
	case .Armor:
		return {1.12, 1.36, 1.08}
	case .Mission:
		return {1.16, 1.12, 1.34}
	case .Keel, .Bow, .Drive, .Truss, .Radiator, .Ring_Segment:
		return {1.12, 1.18, 1.18}
	}
	return {1, 1, 1}
}

procedural_ship_reinforce_payload_support :: proc(r: ^Procedural_Ship_Recipe, payload_index: int) {
	if payload_index < 0 || payload_index >= r.module_count do return
	socket := r.sockets[payload_index]
	parent_index := int(socket.parent)
	if parent_index < 0 || parent_index >= r.module_count do return
	payload := &r.modules[payload_index]
	parent := &r.modules[parent_index]
	if parent.module != .Truss do return
	off_axis := f32(
		math.sqrt(
			f64(
				payload.position[1] * payload.position[1] +
				payload.position[2] * payload.position[2],
			),
		),
	)
	if off_axis <= max(r.frame.beam * .025, f32(.04)) do return
	// Cantilever roots scale with the supported package, not with cosmetic RNG.
	// Independent radial courses preserve flat armor and tall antenna vocabulary
	// while preventing a giant installation from hanging on a hair-thin strut.
	required_y := payload.scale[1] * .18
	required_z := payload.scale[2] * .18
	if parent.scale[1] >= required_y && parent.scale[2] >= required_z do return
	r.mass -= parent.mass
	parent.scale[1] = max(parent.scale[1], required_y)
	parent.scale[2] = max(parent.scale[2], required_z)
	parent.mass =
		parent.scale[0] *
		parent.scale[1] *
		parent.scale[2] *
		procedural_ship_module_mass_factor(.Truss)
	r.mass += parent.mass
}

procedural_ship_refit_structural_connectors :: proc(r: ^Procedural_Ship_Recipe) {
	// Identity transforms can stretch and sweep the two endpoints of a branch by
	// different amounts. Reconstruct each truss from those final endpoints so
	// the visible member neither floats short nor penetrates its payload.
	for &connector, connector_index in r.modules[:r.module_count] {
		if connector.module != .Truss do continue
		parent_index := int(r.sockets[connector_index].parent)
		if parent_index < 0 || parent_index >= r.module_count do continue
		child_index := -1
		for socket, index in r.sockets[:r.socket_count] {
			if int(socket.parent) == connector_index {
				child_index = index
				break
			}
		}
		if child_index < 0 || child_index >= r.module_count do continue
		parent_position := r.modules[parent_index].position
		child_position := r.modules[child_index].position
		dx := child_position[0] - parent_position[0]
		dy := child_position[1] - parent_position[1]
		dz := child_position[2] - parent_position[2]
		distance := f32(math.sqrt(f64(dx * dx + dy * dy + dz * dz)))
		if distance <= .001 do continue
		r.mass -= connector.mass
		connector.position = {
			(parent_position[0] + child_position[0]) * .5,
			(parent_position[1] + child_position[1]) * .5,
			(parent_position[2] + child_position[2]) * .5,
		}
		connector.direction = {dx / distance, dy / distance, dz / distance}
		r.sockets[connector_index].position = connector.position
		r.sockets[connector_index].direction = connector.direction
		// A small manufactured overlap closes both joints without consuming a
		// meaningful fraction of either attached module.
		joint_overlap := max(max(connector.scale[1], connector.scale[2]) * .28, f32(.025))
		connector.scale[0] = distance * .5 + joint_overlap
		connector.mass =
			connector.scale[0] *
			connector.scale[1] *
			connector.scale[2] *
			procedural_ship_module_mass_factor(.Truss)
		r.mass += connector.mass
	}
}

procedural_ship_module_aabb_half_extent :: proc(
	module: Procedural_Ship_Placement,
	padding := f32(0),
) -> [3]f32 {
	axis := module.direction
	length := f32(math.sqrt(f64(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2])))
	if length <= .001 {
		axis = {1, 0, 0}
	} else {
		for &value in axis do value /= length
	}
	reference := [3]f32{0, 0, 1}
	if math.abs(axis[2]) > .9 do reference = {0, 1, 0}
	side := [3]f32 {
		reference[1] * axis[2] - reference[2] * axis[1],
		reference[2] * axis[0] - reference[0] * axis[2],
		reference[0] * axis[1] - reference[1] * axis[0],
	}
	side_length := f32(math.sqrt(f64(side[0] * side[0] + side[1] * side[1] + side[2] * side[2])))
	if side_length > .001 do for &value in side do value /= side_length
	up := [3]f32 {
		axis[1] * side[2] - axis[2] * side[1],
		axis[2] * side[0] - axis[0] * side[2],
		axis[0] * side[1] - axis[1] * side[0],
	}
	result: [3]f32
	for world_axis in 0 ..< 3 {
		result[world_axis] =
			math.abs(axis[world_axis]) * module.scale[0] +
			math.abs(side[world_axis]) * module.scale[1] +
			math.abs(up[world_axis]) * module.scale[2] +
			padding
	}
	return result
}

procedural_ship_modules_overlap_aabb :: proc(
	a, b: Procedural_Ship_Placement,
	padding := f32(0),
) -> bool {
	ah := procedural_ship_module_aabb_half_extent(a, padding)
	bh := procedural_ship_module_aabb_half_extent(b, padding)
	for axis in 0 ..< 3 {
		if math.abs(a.position[axis] - b.position[axis]) >= ah[axis] + bh[axis] do return false
	}
	return true
}

procedural_ship_resolve_radiator_keepouts :: proc(r: ^Procedural_Ship_Recipe) {
	// Thermal sizing occurs after the topology solve and can grow panels into
	// neighboring payloads. Slide each deployed assembly outward along its
	// mounting axis until its padded envelope is clear; connector refitting then
	// rebuilds the support to this final endpoint.
	padding := max(r.frame.beam * .018, f32(.045))
	for &radiator, radiator_index in r.modules[:r.module_count] {
		if radiator.module != .Radiator do continue
		parent_index := int(r.sockets[radiator_index].parent)
		step := max(max(radiator.scale[2] * 1.5, r.frame.beam * .035), f32(.08))
		for attempt in 0 ..< 48 {
			collision := false
			for other, other_index in r.modules[:r.module_count] {
				if other_index == radiator_index || other_index == parent_index do continue
				if procedural_ship_modules_overlap_aabb(radiator, other, padding) {
					collision = true
					break
				}
			}
			if !collision do break
			for axis in 0 ..< 3 do radiator.position[axis] += radiator.direction[axis] * step
		}
		r.sockets[radiator_index].position = radiator.position
	}
}

procedural_ship_emphasize_role_signature :: proc(r: ^Procedural_Ship_Recipe, index: int) {
	if index < 0 || index >= r.module_count do return
	module := &r.modules[index]; emphasis := procedural_ship_role_signature_emphasis(module.module)
	r.mass -= module.mass
	for axis in 0 ..< 3 do module.scale[axis] *= emphasis[axis]
	module.mass =
		module.scale[0] *
		module.scale[1] *
		module.scale[2] *
		procedural_ship_module_mass_factor(module.module)
	r.mass += module.mass
	procedural_ship_reinforce_payload_support(r, index)
}

procedural_ship_role_signature_target :: proc(family: Procedural_Ship_Family) -> int {
	// Role hardware is a physical mass, not merely a capability icon. Every
	// off-axis signature installation therefore needs a manufactured counterpart;
	// compact strike craft cannot hide reaction torque behind their small scale.
	return 2
}

procedural_ship_transverse_center_of_mass :: proc(r: ^Procedural_Ship_Recipe) -> [2]f32 {
	weighted, total := [2]f32{}, f32(0)
	for module in r.modules[:r.module_count] {
		if module.mass <= 0 do continue
		weighted[0] += module.position[1] * module.mass
		weighted[1] += module.position[2] * module.mass
		total += module.mass
	}
	if total <= 0 do return {}
	return {weighted[0] / total, weighted[1] / total}
}

procedural_ship_transverse_mass_offset :: proc(r: ^Procedural_Ship_Recipe) -> f32 {
	center := procedural_ship_transverse_center_of_mass(r)
	return f32(math.sqrt(f64(center[0] * center[0] + center[1] * center[1])))
}

procedural_ship_append_role_hardpoints :: proc(
	r: ^Procedural_Ship_Recipe,
	signature: Procedural_Ship_Module,
	needed: int,
) {
	if needed <= 0 || r.frame.station_count < 3 do return
	remaining_needed := needed
	group := 2
	if r.module_count + group * 2 > PROCEDURAL_SHIP_MAX_MODULES do return
	// The inherited frame fingerprint, not the individual hull seed, owns the
	// attachment station. Sister hulls with the same role must share topology
	// even when their yard proportions and equipment dimensions differ.
	state :=
		r.fingerprint ~
		0x3c79ac492ba7b653 ~
		u64(signature) * 0x1c69b3f74ac4ae35; if state == 0 do state = 1
	first, last := 1, r.frame.station_count - 2
	if r.family == .Fleet do first, last = procedural_ship_fleet_citadel_bounds(r.frame.station_count)
	station :=
		first +
		int(
			procedural_ship_rng(&state) % u64(last - first + 1),
		); anchor := r.modules[station].position
	reach := r.family == .Strike ? f32(1.25) : r.family == .Fleet ? f32(2.15) : f32(2.55)
	first_side: f32 = procedural_ship_rng(&state) % 2 == 0 ? -1 : 1
	shared_payload_scale := procedural_ship_module_scale(r.family, signature, &state)
	for member in 0 ..< group {
		side := first_side * (member == 0 ? f32(1) : -1)
		axial_sweep := r.family == .Strike ? reach * f32(.62) : f32(0)
		tip := [3]f32 {
			anchor[0] - axial_sweep,
			side * reach,
			side * (r.family == .Strike ? .18 : .34),
		}
		center := [3]f32 {
			(anchor[0] + tip[0]) * .5,
			(anchor[1] + tip[1]) * .5,
			(anchor[2] + tip[2]) * .5,
		}
		direction := procedural_ship_direction(anchor, tip); symmetric := group == 2
		root_index := procedural_ship_add_socket(
			r,
			station,
			center,
			direction,
			false,
			false,
			symmetric,
			procedural_ship_bit(.Truss),
		)
		if root_index < 0 do break
		dx, dy, dz :=
			center[0] -
			anchor[0],
			center[1] -
			anchor[1],
			center[2] -
			anchor[2]; distance := f32(math.sqrt(f64(dx * dx + dy * dy + dz * dz)))
		truss_scale := procedural_ship_module_scale(
			r.family,
			.Truss,
			&state,
		); truss_scale[0] = max(distance, truss_scale[1]); truss_mass := truss_scale[0] * truss_scale[1] * truss_scale[2] * procedural_ship_module_mass_factor(.Truss)
		r.modules[root_index] = {
			id         = u32(root_index + 1),
			surface_id = u32(0x10000 + root_index * 17),
			socket     = i16(root_index),
			module     = .Truss,
			material   = .Truss,
			position   = center,
			scale      = truss_scale,
			direction  = direction,
			mass       = truss_mass,
		}; r.mass += truss_mass; r.module_count += 1
		payload_index := procedural_ship_add_socket(
			r,
			root_index,
			tip,
			direction,
			true,
			false,
			symmetric,
			procedural_ship_domain(r.family, true, false),
		)
		if payload_index < 0 do break
		payload_scale :=
			shared_payload_scale; procedural_ship_apply_axial_mass_scale(r, signature, tip, &payload_scale); payload_mass := payload_scale[0] * payload_scale[1] * payload_scale[2] * procedural_ship_module_mass_factor(signature)
		r.modules[payload_index] = {
			id         = u32(payload_index + 1),
			surface_id = u32(0x10000 + payload_index * 17),
			socket     = i16(payload_index),
			module     = signature,
			material   = procedural_ship_material(signature),
			position   = tip,
			scale      = payload_scale,
			direction  = direction,
			mass       = payload_mass,
		}; r.mass += payload_mass; r.module_count += 1
		procedural_ship_emphasize_role_signature(r, payload_index); remaining_needed -= 1
	}
}

procedural_ship_apply_role_signature :: proc(r: ^Procedural_Ship_Recipe, ship: Ship) {
	signature := procedural_ship_role_signature(ship, r.family)
	target := procedural_ship_role_signature_target(r.family)
	// Naturally collapsed signature modules supply the first refit locations, but
	// still receive deliberate silhouette treatment. Large frames emphasize two
	// separate installations so role hardware is not lost among dozens of bays.
	mission_count, radiator_count, signature_count, emphasized := 0, 0, 0, 0
	handled: [PROCEDURAL_SHIP_MAX_MODULES]bool
	for module, i in r.modules[:r.module_count] {
		if module.module == .Mission do mission_count += 1
		if module.module == .Radiator do radiator_count += 1
		if module.module == signature do signature_count += 1
	}
	for module, i in r.modules[:r.module_count] {
		if emphasized >= target do break
		if handled[i] || module.module != signature || i < r.frame.station_count || !r.sockets[i].exposed do continue
		procedural_ship_emphasize_role_signature(r, i); handled[i] = true; emphasized += 1
		counterpart := procedural_ship_symmetric_counterpart(r, i)
		if counterpart >= 0 &&
		   !handled[counterpart] &&
		   r.modules[counterpart].module == signature {
			procedural_ship_emphasize_role_signature(
				r,
				counterpart,
			); handled[counterpart] = true; emphasized += 1
		}
	}
	if signature_count >= target do return
	// Preserve solver-mandated installations and replace the first ordinary,
	// exposed payloads whose sockets explicitly accept the role signature. Keep
	// going until the family-scale quota is visible or no compatible bay remains.
	for &module, i in r.modules[:r.module_count] {
		if signature_count >= target do break
		if i < r.frame.station_count || module.module == .Truss || module.module == .Ring_Segment do continue
		if module.module == signature do continue
		socket := r.sockets[i]
		if !socket.exposed || !procedural_ship_has(socket.domain, signature) do continue
		parent :=
			socket.parent >= 0 ? r.modules[int(socket.parent)].module : Procedural_Ship_Module.Keel
		if !procedural_ship_parent_compatible(signature, parent) do continue
		counterpart := procedural_ship_symmetric_counterpart(r, i)
		replacement_count := counterpart >= 0 ? 2 : 1
		if module.module == .Mission && mission_count <= replacement_count do continue
		if module.module == .Radiator && r.family != .Strike && radiator_count <= replacement_count do continue
		state :=
			r.seed ~ 0x8f3f73b5cf1c9ade ~ u64(i) * 0x9e3779b97f4a7c15; if state == 0 do state = 1
		signature_scale := procedural_ship_module_scale(r.family, signature, &state)
		procedural_ship_apply_axial_mass_scale(r, signature, module.position, &signature_scale)
		indices := [2]int{i, counterpart}
		for placement_index in indices {
			if placement_index < 0 do continue
			placement := &r.modules[placement_index]; r.mass -= placement.mass
			if placement.module == .Mission do mission_count -= 1
			if placement.module == .Radiator do radiator_count -= 1
			placement.module =
				signature; placement.material = procedural_ship_material(signature); placement.scale = signature_scale
			placement.mass =
				signature_scale[0] *
				signature_scale[1] *
				signature_scale[2] *
				procedural_ship_module_mass_factor(signature); r.mass += placement.mass
			procedural_ship_emphasize_role_signature(r, placement_index)
			signature_count += 1; handled[placement_index] = true
		}
	}
	if signature_count < target do procedural_ship_append_role_hardpoints(r, signature, target - signature_count)
}

procedural_ship_rng :: proc(state: ^u64) -> u64 {
	state^ =
		state^ ~ (state^ >> 12); state^ = state^ ~ (state^ << 25); state^ = state^ ~ (state^ >> 27)
	return state^ * 0x2545f4914f6cdd1d
}

procedural_ship_unit :: proc(state: ^u64) -> f32 {return(
		f32(procedural_ship_rng(state) >> 40) /
		f32(1 << 24) \
	)}
procedural_ship_direction :: proc(from, to: [3]f32) -> [3]f32 {d := [3]f32 {
		to[0] - from[0],
		to[1] - from[1],
		to[2] - from[2],
	}
	length := f32(math.sqrt(f64(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])))
	if length <= .001 do return {1, 0, 0}
	return{d[0] / length, d[1] / length, d[2] / length}}
procedural_ship_gcd :: proc(a, b: int) -> int {x, y := a, b; for y != 0 {x, y = y, x % y}; return(
		x \
	)}
procedural_ship_bit :: proc(module: Procedural_Ship_Module) -> u16 {return u16(1) << u16(module)}
procedural_ship_has :: proc(domain: u16, module: Procedural_Ship_Module) -> bool {return(
		domain & procedural_ship_bit(module) !=
		0 \
	)}
procedural_ship_count :: proc(domain: u16) -> int {count := 0; for i in 0 ..< 12 do if domain & (u16(1) << u16(i)) != 0 do count += 1
	return count}

procedural_ship_material :: proc(module: Procedural_Ship_Module) -> Ship_Material_Class {
	switch module {case .Armor:
		return .Armor; case .Truss:
		return .Truss; case .Pressure_Hull, .Tank, .Ring_Segment:
		return .Pressure_Vessel; case .Radiator:
		return .Radiator; case .Drive:
		return .Drive; case .Antenna:
		return .Glass; case .Mission, .Dock:
		return .Machinery; case .Keel, .Bow:
		return .Hull_Plate}
	return .Hull_Plate
}

procedural_ship_domain :: proc(family: Procedural_Ship_Family, exposed, pressure: bool) -> u16 {
	d :=
		procedural_ship_bit(.Armor) |
		procedural_ship_bit(.Pressure_Hull) |
		procedural_ship_bit(.Truss) |
		procedural_ship_bit(.Tank) |
		procedural_ship_bit(.Mission)
	// Habitat rings occupy dedicated axial stations; ordinary hardpoints do not
	// collapse into rings because that would make topology depend on rendering.
	if exposed do d |= procedural_ship_bit(.Radiator) | procedural_ship_bit(.Dock) | procedural_ship_bit(.Antenna)
	if pressure do d &= procedural_ship_bit(.Pressure_Hull) | procedural_ship_bit(.Mission) | procedural_ship_bit(.Ring_Segment)
	// Strike crews live inside the armored axial spine. Exposed combat mounts
	// remain angular and directional instead of growing civilian pressure pods.
	if family == .Strike do d &= ~(procedural_ship_bit(.Tank) | procedural_ship_bit(.Pressure_Hull))
	return d
}

procedural_ship_add_socket :: proc(
	r: ^Procedural_Ship_Recipe,
	parent: int,
	position, direction: [3]f32,
	exposed, pressure, symmetric: bool,
	domain: u16,
) -> int {
	if r.socket_count >= PROCEDURAL_SHIP_MAX_MODULES do return -1
	i := r.socket_count; r.socket_count += 1
	r.sockets[i] = {
		id                = u32(i + 1),
		parent            = i16(parent),
		position          = position,
		direction         = direction,
		exposed           = exposed,
		pressure_required = pressure,
		symmetric         = symmetric,
		domain            = domain,
	}
	return i
}

procedural_ship_symmetric_partner :: proc(r: ^Procedural_Ship_Recipe, index: int) -> int {
	socket := r.sockets[index]
	if !socket.symmetric || math.abs(socket.position[1]) < .001 do return -1
	for prior_index in 0 ..< index {
		prior := r.sockets[prior_index]
		if !prior.symmetric do continue
		if math.abs(socket.position[0] - prior.position[0]) < .001 && math.abs(socket.position[1] + prior.position[1]) < .001 && math.abs(socket.position[2] + prior.position[2]) < .001 do return prior_index
	}
	return -1
}
