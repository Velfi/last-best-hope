package game

import "core:math"
import "core:testing"
procedural_ship_symmetric_counterpart :: proc(r: ^Procedural_Ship_Recipe, index: int) -> int {
	socket := r.sockets[index]
	if !socket.symmetric || math.abs(socket.position[1]) + math.abs(socket.position[2]) < .001 do return -1
	for other_index in 0 ..< r.socket_count {
		if other_index == index do continue
		other := r.sockets[other_index]
		if other.symmetric && math.abs(socket.position[0] - other.position[0]) < .001 && math.abs(socket.position[1] + other.position[1]) < .001 && math.abs(socket.position[2] + other.position[2]) < .001 do return other_index
	}
	return -1
}

procedural_ship_branch_roll :: proc(family: Procedural_Ship_Family, state: ^u64) -> f32 {
	// Strike frames stay close to a planar swept-wing silhouette. Larger ships
	// use a small vocabulary of repeated yard-built mounting planes. Continuous
	// random angles made end-on silhouettes look like accidental radial
	// starbursts; quantized planes read as an intentional structural system.
	shallow, steep: f32
	switch family {case .Strike:
		shallow, steep = 0, .06; case .Fleet:
		shallow, steep = .18, .40; case .Habitat:
		shallow, steep = .28, .66}
	sign: f32 = procedural_ship_rng(state) % 2 == 0 ? -1 : 1
	return sign * (procedural_ship_rng(state) % 3 == 0 ? steep : shallow)
}

procedural_ship_branch_axial_bay :: proc(
	family: Procedural_Ship_Family,
	roll, spacing: f32,
) -> f32 {
	// Separate the shallow and steep attachment planes along the keel. This
	// preserves a clean section while preventing their roots and payloads from
	// occupying the same visual knot in three-quarter and side views.
	if family == .Strike do return 0
	threshold := family == .Fleet ? f32(.3) : f32(.47)
	return math.abs(roll) >= threshold ? spacing * .18 : -spacing * .12
}

procedural_ship_fleet_citadel_bounds :: proc(station_count: int) -> (first, last: int) {
	first = max(1, station_count / 4)
	last = min(station_count - 2, station_count - 1 - station_count / 4)
	return
}

procedural_ship_frame_generate :: proc(
	seed: u64,
	family: Procedural_Ship_Family,
) -> Procedural_Ship_Recipe {
	state := seed ~ (0x9e3779b97f4a7c15 + u64(family) * 0x100000001b3); if state == 0 do state = 1
	target := 0
	switch family {case .Strike:
		target = 8 + int(procedural_ship_rng(&state) % 9); case .Fleet:
		target = 20 + int(procedural_ship_rng(&state) % 21); case .Habitat:
		target = 24 + int(procedural_ship_rng(&state) % 37)}
	keel_count :=
		family == .Strike ? 5 + target / 5 : family == .Fleet ? 8 + target / 6 : 10 + target / 7
	ring_station_count := family == .Habitat ? (target >= 42 ? 3 : 2) : 0
	// Reserve enough construction budget for at least one complete paired
	// truss-and-payload assembly, including on the smallest strike frames. The
	// remaining branch budget is even: four slots make a lateral pair and two
	// make a dorsal mast with its own structural root.
	keel_count = min(keel_count, target - 4)
	if (target - keel_count - ring_station_count) % 2 != 0 do keel_count -= 1
	spacing := family == .Strike ? 1.35 : f32(1.7)
	r := Procedural_Ship_Recipe {
		seed = seed,
		family = family,
		greebly_density = 2,
		frame = {
			keel_length = f32(keel_count - 1) * spacing,
			beam = family == .Strike ? 3.2 : family == .Fleet ? 5.2 : 6.4,
			height = family == .Strike ? 1.4 : 3.2,
			station_count = keel_count,
		},
	}
	for station in 0 ..< keel_count {
		x := (f32(station) - f32(keel_count - 1) * .5) * spacing
		domain := procedural_ship_bit(
			.Keel,
		); if station == 0 do domain = procedural_ship_bit(.Drive); if station == keel_count - 1 do domain = procedural_ship_bit(.Bow)
		// The stern socket's axis is the exhaust-facing axis. Drive geometry uses
		// that axis directly, unlike the keel's forward construction direction.
		// Keeping this at +X makes an otherwise regular modular ship fire its
		// bells through the hull toward the bow.
		socket_direction := [3]f32{1, 0, 0}
		if station == 0 do socket_direction = {-1, 0, 0}
		_ = procedural_ship_add_socket(
			&r,
			station - 1,
			{x, 0, 0},
			socket_direction,
			station == 0 || station == keel_count - 1,
			false,
			false,
			domain,
		)
	}
	if family == .Habitat {
		r.frame.ring_station_count = ring_station_count
		for ring_index in 0 ..< r.frame.ring_station_count {
			station := (ring_index + 1) * (keel_count - 1) / (r.frame.ring_station_count + 1)
			x :=
				r.sockets[station].position[0] +
				(procedural_ship_unit(&state) - .5) * spacing * .14
			_ = procedural_ship_add_socket(
				&r,
				station,
				{x, 0, 0},
				{0, 1, 0},
				true,
				true,
				true,
				procedural_ship_bit(.Ring_Segment),
			)
		}
	}

	// Add paired and dorsal branches to the axial frame. Larger paired branches
	// have an inner truss root and an outer functional hardpoint, so equipment
	// reads as a load-bearing assembly rather than floating at the end of a line.
	// Coordinates are continuous and seeded; they are not cells in a voxel grid.
	branch_span := max(
		keel_count - 2,
		1,
	); branch_offset := int(procedural_ship_rng(&state) % u64(branch_span)); branch_step := 1 + int(procedural_ship_rng(&state) % u64(branch_span)); for procedural_ship_gcd(branch_step, branch_span) != 1 do branch_step = branch_step % branch_span + 1; branch_index := 0
	for r.socket_count < target {
		remaining := target - r.socket_count
		sequence_index := branch_index
		branch_index += 1
		station := 1 + (branch_offset + sequence_index * branch_step) % branch_span
		if family == .Fleet {
			// Fleet payloads collect behind an armored amidships citadel. The
			// drive and bow approaches retain exposed keel and service access.
			first, last := procedural_ship_fleet_citadel_bounds(keel_count)
			citadel_span := last - first + 1
			citadel_step := 1 + branch_step % citadel_span
			for procedural_ship_gcd(citadel_step, citadel_span) != 1 do citadel_step = citadel_step % citadel_span + 1
			station =
				first +
				(branch_offset % citadel_span + sequence_index * citadel_step) % citadel_span
		} else if family == .Habitat {
			// Habitat payloads form inhabited districts around their rotation
			// structures. Three adjacent fabrication bays per ring leave exposed
			// keel and utilities between districts instead of uniform clutter.
			district := sequence_index % ring_station_count
			district_band := (sequence_index / ring_station_count) % 3 - 1
			ring_station := (district + 1) * (keel_count - 1) / (ring_station_count + 1)
			station = clamp(ring_station + district_band, 1, keel_count - 2)
		}
		x := r.sockets[station].position[0] + (procedural_ship_unit(&state) - .5) * spacing * .34
		pressure :=
			family == .Habitat && r.socket_count > keel_count + 2 && r.socket_count % 5 == 0
		if remaining >= 4 {
			// Strike equipment hugs the keel closely enough to preserve a compact
			// arrowhead. Capital frames have the fabrication depth and structural
			// leverage for longer transverse yards.
			reach: f32
			if family == .Strike {
				reach = 1.15 + procedural_ship_unit(&state) * .75
			} else {
				reach = 1.45 + procedural_ship_unit(&state) * 2.2
			}
			// Strike payloads sit on strongly swept load paths so their compact
			// frame reads as an arrowhead rather than a crossbeam with round tips.
			sweep: f32 = 0; if family == .Strike do sweep = -reach * (.72 + procedural_ship_unit(&state) * .18)
			roll := procedural_ship_branch_roll(family, &state)
			x += procedural_ship_branch_axial_bay(family, roll, spacing)
			lateral :=
				reach * f32(math.cos(f64(roll))); vertical := reach * f32(math.sin(f64(roll)))
			parent_position := r.sockets[station].position
			sides := [2]f32{-1, 1}
			for side in sides {
				tip := [3]f32{x + sweep, side * lateral, side * vertical}
				// A truss placement stores its center and local long-axis direction.
				// Its half-extent reaches from the keel to the functional hardpoint.
				root_center := [3]f32 {
					(parent_position[0] + tip[0]) * .5,
					(parent_position[1] + tip[1]) * .5,
					(parent_position[2] + tip[2]) * .5,
				}
				root_direction := procedural_ship_direction(parent_position, tip)
				root := procedural_ship_add_socket(
					&r,
					station,
					root_center,
					root_direction,
					false,
					false,
					true,
					procedural_ship_bit(.Truss),
				)
				_ = procedural_ship_add_socket(
					&r,
					root,
					tip,
					procedural_ship_direction(root_center, tip),
					true,
					pressure,
					true,
					procedural_ship_domain(family, true, pressure),
				)
			}
		} else if remaining >= 2 {
			// Two remaining slots cannot support a mirrored lateral branch. Spend
			// them on a short axial service extension instead, so a final large
			// payload cannot move the center of mass away from the drive line.
			axial_sign: f32 = procedural_ship_rng(&state) % 2 == 0 ? -1 : 1
			tip := [3]f32 {
				x + axial_sign * (.45 + procedural_ship_unit(&state) * .35),
				0,
				0,
			}; parent_position := r.sockets[station].position; root_center := [3]f32{(parent_position[0] + tip[0]) * .5, (parent_position[1] + tip[1]) * .5, (parent_position[2] + tip[2]) * .5}; root_direction := procedural_ship_direction(parent_position, tip)
			root := procedural_ship_add_socket(
				&r,
				station,
				root_center,
				root_direction,
				false,
				false,
				false,
				procedural_ship_bit(.Truss),
			)
			_ = procedural_ship_add_socket(
				&r,
				root,
				tip,
				procedural_ship_direction(root_center, tip),
				true,
				pressure,
				false,
				procedural_ship_domain(family, true, pressure),
			)
		}
	}
	return r
}

procedural_ship_parent_compatible :: proc(child, parent: Procedural_Ship_Module) -> bool {
	if child == .Radiator || child == .Dock || child == .Antenna do return parent == .Keel || parent == .Truss || parent == .Pressure_Hull || parent == .Mission
	if child == .Pressure_Hull || child == .Ring_Segment do return parent != .Radiator && parent != .Antenna
	return true
}

procedural_ship_pick :: proc(domain: u16, state: ^u64) -> Procedural_Ship_Module {
	count := procedural_ship_count(domain); if count == 0 do return .Truss
	pick := int(procedural_ship_rng(state) % u64(count))
	for value in 0 ..< 12 {module := Procedural_Ship_Module(value); if !procedural_ship_has(domain, module) do continue; if pick == 0 do return module; pick -= 1}
	return .Truss
}

procedural_ship_module_scale :: proc(
	family: Procedural_Ship_Family,
	module: Procedural_Ship_Module,
	state: ^u64,
) -> [3]f32 {
	j :=
		.88 +
		procedural_ship_unit(state) *
			.28; base := family == .Strike ? .58 : family == .Fleet ? .82 : f32(.96)
	keel_radial := family == .Fleet ? f32(1.22) : family == .Habitat ? f32(1.12) : f32(1)
	// Keel blocks leave a fabrication break around the shared centerline
	// longeron instead of merging into one visually continuous extrusion. Fleet
	// and habitat frames carry a broader load-bearing spine than strike craft.
	switch module {case .Keel:
		return {.72 * base * j, .48 * base * keel_radial, .42 * base * keel_radial}; case .Bow:
		// A Fleet frame's long armored prow terminates its axial load path;
		// Strike craft retain a compact knife point, while Habitat bows spread
		// laterally around docking and debris-protection volume.
		if family == .Fleet do return {1.85 * base * j, .9 * base, .58 * base}
		if family == .Habitat do return {1.55 * base * j, .98 * base, .62 * base}
		return {1.35 * base * j, .65 * base, .48 * base}
	case .Drive:
		return {.92 * base, .78 * base, .7 * base}; case .Armor:
		return {1.05 * base * j, .88 * base, .62 * base}; case .Pressure_Hull:
		return {1.15 * base * j, .92 * base, .88 * base}; case .Truss:
		return {1.08 * base * j, .2 * base, .2 * base}; case .Tank:
		return {1.25 * base * j, .66 * base, .66 * base}; case .Radiator:
		return {.88 * base, 1.25 * base, .08 * base}; case .Mission:
		return {.88 * base * j, .72 * base, 1.0 * base}; case .Dock:
		return {.52 * base, .78 * base, .78 * base}; case .Antenna:
		return {.28 * base, .28 * base, 1.35 * base}; case .Ring_Segment:
		return {.65 * base, 2.5 * base * j, 2.5 * base * j}}
	return {base, base, base}
}

procedural_ship_module_mass_factor :: proc(module: Procedural_Ship_Module) -> f32 {
	return module == .Truss ? .35 : module == .Radiator ? .18 : module == .Ring_Segment ? .42 : 1
}

procedural_ship_axial_mass_factor :: proc(
	r: ^Procedural_Ship_Recipe,
	module: Procedural_Ship_Module,
	position: [3]f32,
) -> f32 {
	// Yard frames are organized into legible mass zones rather than distributing
	// interchangeable payload boxes uniformly along the keel. Slender systems and
	// primary structure keep their engineered dimensions; only enclosed payloads
	// participate in the family silhouette.
	if module == .Keel || module == .Bow || module == .Drive || module == .Truss || module == .Radiator || module == .Antenna || module == .Ring_Segment do return 1
	half_length := max(
		r.frame.keel_length * .5,
		f32(.001),
	); normalized := position[0] / half_length
	switch r.family {
	case .Strike:
		// Forward-loaded armor and mission gear reinforce the arrowhead without
		// turning the exposed equipment into pressure-vessel beads.
		return normalized > .08 ? f32(1.2) : normalized < -.45 ? f32(.82) : f32(1.02)
	case .Fleet:
		// A broad amidships citadel gives capital hulls one dominant machinery
		// mass, with visibly lighter approach structure at bow and drive ends.
		return math.abs(normalized) < .46 ? f32(1.24) : f32(.84)
	case .Habitat:
		// Civilian payloads collect into districts around the inherited habitat
		// rings. The intervening keel remains open and inspectable.
		nearest := half_length * 2
		for candidate in r.modules[:r.module_count] do if candidate.module == .Ring_Segment do nearest = min(nearest, math.abs(position[0] - candidate.position[0]))
		return nearest < 1.85 ? f32(1.2) : f32(.84)
	}
	return 1
}

procedural_ship_apply_axial_mass_scale :: proc(
	r: ^Procedural_Ship_Recipe,
	module: Procedural_Ship_Module,
	position: [3]f32,
	scale: ^[3]f32,
) {
	factor := procedural_ship_axial_mass_factor(r, module, position)
	// Radial growth carries the silhouette; restrained axial growth prevents
	// neighboring fabrication bays from melting into a continuous extrusion.
	scale[0] *= .82 + factor * .18; scale[1] *= factor; scale[2] *= factor
}

procedural_ship_normalize_visual_mass_distribution :: proc(
	r: ^Procedural_Ship_Recipe,
	preserved_total: f32,
) {
	raw_total := f32(0)
	for &module in r.modules[:r.module_count] {
		module.mass =
			module.scale[0] *
			module.scale[1] *
			module.scale[2] *
			procedural_ship_module_mass_factor(module.module)
		raw_total += module.mass
	}
	if raw_total <= 0 {
		r.mass = preserved_total
		return
	}
	factor := preserved_total / raw_total
	for &module in r.modules[:r.module_count] do module.mass *= factor
	r.mass = preserved_total
}

procedural_ship_fit_drive_to_frame :: proc(r: ^Procedural_Ship_Recipe) {
	// A drive bank must communicate enough aperture and machinery to accelerate
	// the hull wrapped around it. These are minimums, not uniform dimensions:
	// capability and construction identity may still produce larger engines.
	min_beam := r.frame.beam * .16
	min_height := r.frame.height * .22
	for &module in r.modules[:r.module_count] {
		if module.module != .Drive do continue
		module.scale[1] = max(module.scale[1], min_beam)
		module.scale[2] = max(module.scale[2], min_height)
	}
}

procedural_ship_radiator_area :: proc(r: ^Procedural_Ship_Recipe) -> f32 {
	area := f32(0)
	for module in r.modules[:r.module_count] {
		if module.module == .Radiator {
			area += module.scale[0] * module.scale[1] * 4
		}
	}
	return area
}

procedural_ship_drive_aperture_area :: proc(r: ^Procedural_Ship_Recipe) -> f32 {
	area := f32(0)
	for module in r.modules[:r.module_count] {
		if module.module == .Drive {
			area += module.scale[1] * module.scale[2] * 4
		}
	}
	return area
}

procedural_ship_required_radiator_area :: proc(r: ^Procedural_Ship_Recipe) -> f32 {
	if r.family == .Strike do return 0
	// The installed drive aperture is the machinery heat proxy. A nominal drive
	// needs many times its own cross-section in low-temperature rejection area;
	// higher output worsens that ratio. Fleet and especially Habitat hulls add
	// continuous hotel/industrial heat proportional to inhabited planform.
	output := max(r.drive_capability_scale, f32(.7))
	drive_heat := procedural_ship_drive_aperture_area(r) * (8 + output * 6)
	hotel_factor := r.family == .Habitat ? f32(.07) : f32(.025)
	hotel_heat := r.frame.keel_length * r.frame.beam * hotel_factor
	return drive_heat + hotel_heat
}

procedural_ship_fit_radiators_to_power :: proc(r: ^Procedural_Ship_Recipe) {
	required := procedural_ship_required_radiator_area(r)
	if required <= 0 do return
	current := procedural_ship_radiator_area(r)
	if current <= 0 || current >= required do return
	factor := f32(math.sqrt(f64(required / current)))
	for &module in r.modules[:r.module_count] {
		if module.module != .Radiator do continue
		module.scale[0] *= factor
		module.scale[1] *= factor
	}
}

procedural_ship_service_mark_compatible :: proc(module: Procedural_Ship_Module) -> bool {
	return(
		module != .Drive &&
		module != .Bow &&
		module != .Truss &&
		module != .Radiator &&
		module != .Antenna &&
		module != .Ring_Segment \
	)
}

procedural_ship_apply_service_history :: proc(r: ^Procedural_Ship_Recipe, ship: Ship) {
	// Mutable history decorates, but never re-solves, the inherited frame. Damage
	// grows a stable sequence of local repairs; named and Dark scars supersede the
	// last plate with a more specific structure at the same deterministic site.
	mark_count := clamp(int(ship.damage), 0, 3)
	if ship.scar != .None || ship.dark_field_scars > 0 do mark_count = max(mark_count, 1)
	if mark_count == 0 do return
	state := r.seed ~ u64(ship.id) * 0x9e3779b97f4a7c15 ~ 0x5a17c9e3d4b68f21
	if state == 0 do state = 1
	for mark_index in 0 ..< mark_count {
		start := int(procedural_ship_rng(&state) % u64(max(r.module_count, 1)))
		chosen := -1
		for offset in 0 ..< r.module_count {
			index := (start + offset) % r.module_count; module := r.modules[index]
			if module.service_mark == .None &&
			   procedural_ship_service_mark_compatible(module.module) {chosen = index; break}
		}
		if chosen < 0 do break
		kind := Procedural_Ship_Service_Mark.Patch_Plate
		if mark_index == mark_count - 1 {
			if ship.dark_field_scars > 0 ||
			   ship.scar == .Passage_Scarred ||
			   ship.scar ==
				   .Alien_Symbiosis {kind = .Dark_Scar} else if ship.scar == .Hull_Breach {kind = .Breach_Cage}
		}
		r.modules[chosen].service_mark = kind
	}
}

procedural_ship_keel_profile :: proc(family: Procedural_Ship_Family, axial_distance: f32) -> f32 {
	// Concentrate the primary structure amidships and taper it toward the drive
	// and bow. The profile is deliberately stepped by station when rendered: it
	// reads as an assembled armored backbone instead of one uniform lattice rail.
	center, end: f32
	switch family {
	case .Strike:
		center, end = 1.58, .82
	case .Fleet:
		center, end = 1.38, .76
	case .Habitat:
		center, end = 1.28, .8
	}
	t := clamp(axial_distance, f32(0), f32(1))
	return center + (end - center) * t
}

procedural_ship_generate :: proc(
	seed: u64,
	family: Procedural_Ship_Family,
) -> Procedural_Ship_Recipe {
	r := procedural_ship_frame_generate(
		seed,
		family,
	); state := seed ~ 0xd1b54a32d192ed03; if state == 0 do state = 1
	r.complete =
		true; r.connected = true; r.pressure_connected = true; r.radiators_exposed = true; r.drives_valid = true
	mission_count, radiator_count, pressure_count, ring_count := 0, 0, 0, 0
	for socket, i in r.sockets[:r.socket_count] {
		domain := socket.domain
		partner_index := procedural_ship_symmetric_partner(&r, i)
		// Family quotas are folded into the entropy domain before collapse.
		remaining := r.socket_count - i
		if family != .Strike && radiator_count == 0 && remaining <= 8 && socket.exposed && procedural_ship_has(domain, .Radiator) do domain = procedural_ship_bit(.Radiator)
		if mission_count == 0 && remaining <= 7 && procedural_ship_has(domain, .Mission) do domain = procedural_ship_bit(.Mission)
		if family == .Habitat && ring_count == 0 && remaining <= 6 && procedural_ship_has(domain, .Ring_Segment) do domain = procedural_ship_bit(.Ring_Segment)
		if family == .Habitat && pressure_count == 0 && remaining <= 4 && procedural_ship_has(domain, .Pressure_Hull) do domain = procedural_ship_bit(.Pressure_Hull)
		module :=
			partner_index >= 0 ? r.modules[partner_index].module : procedural_ship_pick(domain, &state)
		if socket.parent >= 0 {
			parent := r.modules[int(socket.parent)].module
			if !procedural_ship_parent_compatible(module, parent) {
				r.backtracks += 1; filtered := domain
				for value in 0 ..< 12 {candidate := Procedural_Ship_Module(value); if procedural_ship_has(filtered, candidate) && !procedural_ship_parent_compatible(candidate, parent) do filtered &= ~procedural_ship_bit(candidate)}
				if filtered ==
				   0 {r.complete = false; module = .Truss} else {module = procedural_ship_pick(filtered, &state)}
			}
		}
		if module == .Mission do mission_count += 1; if module == .Radiator do radiator_count += 1; if module == .Pressure_Hull || module == .Ring_Segment do pressure_count += 1; if module == .Ring_Segment do ring_count += 1
		scale :=
			partner_index >= 0 ? r.modules[partner_index].scale : procedural_ship_module_scale(family, module, &state)
		if module == .Keel {
			half_length := max(r.frame.keel_length * .5, f32(.001))
			profile := procedural_ship_keel_profile(
				family,
				math.abs(socket.position[0]) / half_length,
			)
			scale[1] *= profile; scale[2] *= profile
		}
		if module == .Truss && socket.parent >= 0 {
			parent_position := r.sockets[int(socket.parent)].position
			dx, dy, dz :=
				socket.position[0] -
				parent_position[0],
				socket.position[1] -
				parent_position[1],
				socket.position[2] -
				parent_position[2]
			distance := f32(
				math.sqrt(f64(dx * dx + dy * dy + dz * dz)),
			); scale = {max(distance, scale[1]), scale[1], scale[2]}
		}
		// A manufactured counterpart inherits its partner's already-zoned scale.
		// Applying the zone twice would make the second half of a pair larger.
		if partner_index < 0 do procedural_ship_apply_axial_mass_scale(&r, module, socket.position, &scale)
		mass := scale[0] * scale[1] * scale[2] * procedural_ship_module_mass_factor(module)
		r.modules[i] = {
			id         = u32(i + 1),
			surface_id = u32(0x10000 + i * 17),
			socket     = i16(i),
			module     = module,
			material   = procedural_ship_material(module),
			position   = socket.position,
			scale      = scale,
			direction  = socket.direction,
			mass       = mass,
		}
		r.mass += mass; r.module_count += 1
		if int(socket.parent) >= i do r.connected = false
		if socket.pressure_required && module != .Pressure_Hull && module != .Mission && module != .Ring_Segment do r.pressure_connected = false
		if module == .Radiator && !socket.exposed do r.radiators_exposed = false
		if module == .Drive && (i != 0 || socket.direction[0] >= 0) do r.drives_valid = false
	}
	if mission_count == 0 do r.complete = false
	if family == .Habitat && pressure_count == 0 do r.complete = false
	if family == .Habitat && ring_count == 0 do r.complete = false
	if family != .Strike && radiator_count == 0 do r.complete = false
	for module_index in r.frame.station_count ..< r.module_count {
		procedural_ship_reinforce_payload_support(&r, module_index)
	}
	r.complete =
		r.complete && r.connected && r.pressure_connected && r.radiators_exposed && r.drives_valid
	r.fingerprint = procedural_ship_fingerprint(r)
	return r
}

// Build the presentation recipe from the same immutable construction grammar
// used by campaign dossiers. These transforms change yard-built proportions,
// never mutable capability or damage state.
procedural_ship_generate_for_ship :: proc(ship: Ship) -> Procedural_Ship_Recipe {
	seed := ship.construction_seed
	if seed == 0 do seed = u64(max(int(ship.id), 1))
	// Lineage owns the inherited frame/socket architecture. Individual identity
	// still owns every yard choice applied below, including role refits and the
	// final fingerprint, so sister hulls are recognizable without being clones.
	topology_seed := ship.construction_lineage
	if topology_seed == 0 do topology_seed = seed
	r := procedural_ship_generate(topology_seed, procedural_ship_family_for_ship(ship))
	r.seed =
		seed; r.architecture = ship_generator_kind_supported(ship.generator_kind); r.greebly_density = ship_construction_greebly_density(ship)
	if ship.power > 0 {
		baseline := max(ship_hull_class_power(ship.role, ship.hull_class), 1)
		ratio := clamp(f32(ship.power) / f32(baseline), f32(.5), f32(1.5))
		r.drive_capability_scale = .78 + (ratio - .5) * .44
	} else {r.drive_capability_scale = 1}
	profile := ship_operational_profile(ship.operational_role)
	weapon_rating := max(profile.anti_ship, max(profile.point_defense, profile.long_range))
	r.weapon_capability_scale = .72 + f32(weapon_rating) / 100 * .63
	r.weapon_package = ship.weapon_package
	if r.weapon_package == .Unspecified {
		r.weapon_package = ship_weapon_package_for(
			ship.id,
			ship.hull_archetype,
			ship.operational_role,
		)
	}
	procedural_ship_apply_role_signature(&r, ship)
	procedural_ship_apply_construction_style(&r, ship.construction_style)
	keel_scales := [3]f32{.86, 1, 1.18}
	stance_scales := [3]f32{.82, 1, 1.22}
	bow_length_scales := [3]f32{.78, 1, 1.32}
	bow_beam_scales := [3]f32{1.18, 1, .78}
	mission_height_scales := [3]f32{.72, 1, 1.34}
	wing_sweep_factors := [3]f32{.34, 0, -.34}
	x_scale := keel_scales[ship_construction_keel_profile(ship)]
	radial_scale := stance_scales[ship_construction_wing_stance(ship)]
	wing_sweep := ship_construction_wing_sweep(ship)
	drive_layout := ship_construction_drive_layout(ship)
	drive_setback := ship_construction_drive_setback(ship)
	utility_hardpoint := ship_construction_utility_hardpoint(ship)
	centerline_bias := ship_construction_centerline_bias(ship)
	sweep_factor := wing_sweep_factors[wing_sweep]
	for &socket in r.sockets[:r.socket_count] {
		socket.position[0] *= x_scale
		socket.position[1] *= radial_scale
		socket.position[2] *= radial_scale
		radial_distance := f32(
			math.sqrt(
				f64(
					socket.position[1] * socket.position[1] +
					socket.position[2] * socket.position[2],
				),
			),
		)
		socket.position[0] += radial_distance * sweep_factor
	}
	for &module in r.modules[:r.module_count] {
		module.position[0] *= x_scale
		module.position[1] *= radial_scale
		module.position[2] *= radial_scale
		radial_distance := f32(
			math.sqrt(
				f64(
					module.position[1] * module.position[1] +
					module.position[2] * module.position[2],
				),
			),
		)
		module.position[0] += radial_distance * sweep_factor
		module.scale[0] *= x_scale
		if module.module == .Bow {
			bow := ship_construction_bow_profile(ship)
			module.variant = u8(bow)
			module.scale[0] *= bow_length_scales[bow]
			module.scale[1] *= bow_beam_scales[bow]
		}
		if module.module == .Mission {
			mission := ship_construction_mission_profile(ship)
			module.variant = u8(mission)
			module.mount_variant = u8(utility_hardpoint + centerline_bias * 9)
			module.scale[2] *= mission_height_scales[mission]
		}
		if module.module == .Drive {
			module.variant = u8(drive_layout)
			module.drive_power_tier =
				r.drive_capability_scale < .95 ? -1 : r.drive_capability_scale > 1.05 ? 1 : 0
			// Higher-output machinery needs longer turbomachinery and markedly
			// broader bells; radial growth carries most of the silhouette change.
			module.scale[0] *= .9 + r.drive_capability_scale * .1
			module.scale[1] *= .55 + r.drive_capability_scale * .45
			module.scale[2] *= .55 + r.drive_capability_scale * .45
		}
		if module.module == .Radiator {
			// Construction identity selects one of the thermally equivalent
			// deployment sculptures; seed and socket identity keep it stable.
			module.variant = u8(
				ship_construction_visual_mix(seed ~ u64(module.surface_id) * 0x9e3779b97f4a7c15) %
				3,
			)
		}
	}
	setback_factors := [3]f32{.32, 0, -.38}
	for &module, i in r.modules[:r.module_count] do if module.module == .Drive {
		offset := module.scale[0] * setback_factors[drive_setback]
		module.position[0] += offset; r.sockets[i].position[0] += offset
	}
	// Non-uniform identity transforms invalidate the solver's original local
	// axes. Rebuild every mounted direction from transformed attachment points;
	// habitat rings retain their explicit radial axis at the keel center.
	for &module, i in r.modules[:r.module_count] {
		parent := int(r.sockets[i].parent)
		if parent < 0 || module.module == .Ring_Segment do continue
		direction := procedural_ship_direction(r.modules[parent].position, module.position)
		r.sockets[i].direction = direction; module.direction = direction
	}
	r.frame.keel_length *= x_scale
	r.frame.beam *= radial_scale
	r.frame.height *= radial_scale
	preserved_mass := r.mass
	procedural_ship_fit_drive_to_frame(&r)
	procedural_ship_fit_radiators_to_power(&r)
	procedural_ship_resolve_radiator_keepouts(&r)
	procedural_ship_refit_structural_connectors(&r)
	for module_index in r.frame.station_count ..< r.module_count {
		procedural_ship_reinforce_payload_support(&r, module_index)
	}
	procedural_ship_normalize_visual_mass_distribution(&r, preserved_mass)
	identity_profile := ship_construction_keel_profile(ship)
	identity_profile = identity_profile * 3 + ship_construction_wing_stance(ship)
	identity_profile = identity_profile * 3 + wing_sweep
	identity_profile = identity_profile * 3 + drive_layout
	identity_profile = identity_profile * 3 + drive_setback
	identity_profile = identity_profile * 3 + ship_construction_bow_profile(ship)
	identity_profile = identity_profile * 3 + ship_construction_mission_profile(ship)
	identity_profile = identity_profile * 9 + utility_hardpoint
	if utility_hardpoint % 3 == 1 do identity_profile = identity_profile * 2 + centerline_bias
	r.fingerprint = ship_construction_visual_mix(
		procedural_ship_fingerprint(r) ~
		(u64(identity_profile) << 48) ~
		u64(ship.construction_style) * 0x9e3779b97f4a7c15 ~
		u64(ship.generator_kind) * 0xd1b54a32d192ed03,
	)
	procedural_ship_apply_service_history(&r, ship)
	r.systems = procedural_ship_system_graph_generate(ship, &r)
	return r
}
