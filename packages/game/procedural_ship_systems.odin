package game

import "core:math"

PROCEDURAL_SHIP_MAX_SYSTEMS :: 24
PROCEDURAL_SHIP_MAX_SYSTEM_LINKS :: 64

Procedural_Ship_System_Kind :: enum u8 {
	Structure,
	Drive,
	Power,
	Propellant,
	Water,
	Heat_Rejection,
	Heat_Sink,
	Weapon,
	Habitat,
	Command,
	Sensor,
	RCS,
	Mission,
}

Procedural_Ship_Flow_Kind :: enum u8 {
	Load,
	Energy,
	Coolant,
	Material,
	Control,
	Crew,
}

Procedural_Ship_System_Node :: struct {
	id:                       u32,
	kind:                     Procedural_Ship_System_Kind,
	position:                 [3]f32,
	mass, volume:             f32,
	power_output, power_draw: f32,
	waste_heat, water:        f32,
	exposed, paired:          bool,
}

Procedural_Ship_System_Link :: struct {
	source, target: i16,
	kind:           Procedural_Ship_Flow_Kind,
	capacity:       f32,
}

Procedural_Ship_System_Graph :: struct {
	node_count, link_count: int,
	nodes:                  [PROCEDURAL_SHIP_MAX_SYSTEMS]Procedural_Ship_System_Node,
	links:                  [PROCEDURAL_SHIP_MAX_SYSTEM_LINKS]Procedural_Ship_System_Link,
	layout_score:           f32,
	complete, balanced:     bool,
	fingerprint:            u64,
}

procedural_ship_system_add :: proc(
	g: ^Procedural_Ship_System_Graph,
	kind: Procedural_Ship_System_Kind,
	mass, volume: f32,
) -> int {
	if g.node_count >= PROCEDURAL_SHIP_MAX_SYSTEMS do return -1
	index := g.node_count
	g.nodes[index] = {
		id = u32(index + 1),
		kind = kind,
		mass = max(mass, f32(.01)),
		volume = max(volume, f32(.01)),
	}
	g.node_count += 1
	return index
}

procedural_ship_system_link :: proc(
	g: ^Procedural_Ship_System_Graph,
	source, target: int,
	kind: Procedural_Ship_Flow_Kind,
	capacity: f32,
) {
	if source < 0 || target < 0 || source >= g.node_count || target >= g.node_count ||
	   g.link_count >= PROCEDURAL_SHIP_MAX_SYSTEM_LINKS {
		g.complete = false
		return
	}
	g.links[g.link_count] = {
		source = i16(source),
		target = i16(target),
		kind = kind,
		capacity = max(capacity, f32(.01)),
	}
	g.link_count += 1
}

procedural_ship_system_find :: proc(
	g: ^Procedural_Ship_System_Graph,
	kind: Procedural_Ship_System_Kind,
	occurrence := 0,
) -> int {
	found := 0
	for node, index in g.nodes[:g.node_count] {
		if node.kind != kind do continue
		if found == occurrence do return index
		found += 1
	}
	return -1
}

procedural_ship_system_layout_score :: proc(
	g: ^Procedural_Ship_System_Graph,
	beam: f32,
) -> f32 {
	score := f32(0)
	for link in g.links[:g.link_count] {
		a := g.nodes[int(link.source)].position
		b := g.nodes[int(link.target)].position
		dx, dy, dz := b[0] - a[0], b[1] - a[1], b[2] - a[2]
		distance := f32(math.sqrt(f64(dx * dx + dy * dy + dz * dz)))
		weight: f32 = 1
		switch link.kind {
		case .Load:
			weight = 2.4
		case .Coolant:
			weight = 1.8
		case .Material:
			weight = 1.35
		case .Energy:
			weight = 1.15
		case .Control, .Crew:
			weight = .65
		}
		score += distance * weight * max(link.capacity, f32(.1))
	}
	total_mass, moment_y, moment_z := f32(0), f32(0), f32(0)
	for node in g.nodes[:g.node_count] {
		total_mass += node.mass
		moment_y += node.mass * node.position[1]
		moment_z += node.mass * node.position[2]
	}
	if total_mass > 0 {
		offset_y, offset_z := moment_y / total_mass, moment_z / total_mass
		score +=
			f32(math.sqrt(f64(offset_y * offset_y + offset_z * offset_z))) /
			max(beam, f32(.1)) *
			400
	}
	power := procedural_ship_system_find(g, .Power)
	habitat := procedural_ship_system_find(g, .Habitat)
	water := procedural_ship_system_find(g, .Water)
	if power >= 0 && habitat >= 0 && water >= 0 {
		px := g.nodes[power].position[0]
		hx := g.nodes[habitat].position[0]
		wx := g.nodes[water].position[0]
		if wx < min(px, hx) || wx > max(px, hx) do score += 80
	}
	return score
}

procedural_ship_system_apply_layout_candidate :: proc(
	g: ^Procedural_Ship_System_Graph,
	r: ^Procedural_Ship_Recipe,
	order: [4]Procedural_Ship_System_Kind,
	phase: f32,
) {
	half_length := max(r.frame.keel_length * .5, f32(2))
	beam := max(r.frame.beam, f32(1))
	for &node in g.nodes[:g.node_count] {
		node.position = {}
		switch node.kind {
		case .Drive:
			node.position[0] = -half_length * .92
		case .Weapon:
			node.position[0] = half_length * .72
		case .Command, .Sensor:
			node.position[0] = half_length * .42
		case .RCS:
			node.position[0] = node.paired ? half_length * .96 : -half_length * .96
		case .Heat_Rejection:
			side: f32 = node.paired ? 1 : -1
			node.position = {-half_length * .08, side * beam * (.72 + phase * .08), 0}
		case .Heat_Sink:
			node.position = {half_length * .08, 0, 0}
		case .Structure:
			node.position = {}
		case .Mission:
			node.position = {half_length * .18, 0, 0}
		case .Power, .Propellant, .Water, .Habitat:
			for kind, station in order {
				if node.kind == kind {
					node.position[0] =
						-half_length * .52 +
						f32(station) * half_length * .30
					break
				}
			}
		}
	}
}

procedural_ship_system_graph_generate :: proc(
	ship: Ship,
	r: ^Procedural_Ship_Recipe,
) -> Procedural_Ship_System_Graph {
	g := Procedural_Ship_System_Graph{complete = true}
	scale: f32 = r.family == .Strike ? 10 : r.family == .Fleet ? 42 : 86
	output := max(r.drive_capability_scale, f32(.75))
	structure := procedural_ship_system_add(&g, .Structure, scale * .14, scale * .10)
	drive := procedural_ship_system_add(&g, .Drive, scale * .15, scale * .09)
	g.nodes[drive].power_draw = output * 8
	g.nodes[drive].waste_heat = output * 5
	power := procedural_ship_system_add(&g, .Power, scale * .12, scale * .08)
	g.nodes[power].power_output = output * 12
	g.nodes[power].waste_heat = output * 4
	propellant := procedural_ship_system_add(&g, .Propellant, scale * .25, scale * .28)
	water_fraction: f32 = r.family == .Strike ? .07 : r.family == .Fleet ? .16 : .28
	water := procedural_ship_system_add(&g, .Water, scale * water_fraction, scale * water_fraction)
	g.nodes[water].water = scale * water_fraction
	habitat := procedural_ship_system_add(
		&g,
		.Habitat,
		scale * (r.family == .Habitat ? .20 : .08),
		scale * (r.family == .Habitat ? .30 : .09),
	)
	command := procedural_ship_system_add(&g, .Command, scale * .035, scale * .03)
	sensor := procedural_ship_system_add(&g, .Sensor, scale * .018, scale * .02)
	weapon := -1
	if r.family != .Habitat {
		weapon = procedural_ship_system_add(
			&g,
			.Weapon,
			scale * (r.family == .Strike ? .16 : .10),
			scale * .08,
		)
		g.nodes[weapon].power_draw = max(r.weapon_capability_scale, f32(.7)) * 5
		g.nodes[weapon].waste_heat = max(r.weapon_capability_scale, f32(.7)) * 4
	}
	thermal_a, thermal_b := -1, -1
	if r.family == .Strike {
		thermal_a = procedural_ship_system_add(&g, .Heat_Sink, scale * .055, scale * .045)
		g.nodes[thermal_a].water = scale * .018
	} else {
		thermal_a = procedural_ship_system_add(&g, .Heat_Rejection, scale * .06, scale * .12)
		thermal_b = procedural_ship_system_add(&g, .Heat_Rejection, scale * .06, scale * .12)
		g.nodes[thermal_a].exposed = true
		g.nodes[thermal_b].exposed = true
		g.nodes[thermal_b].paired = true
	}
	rcs_a := procedural_ship_system_add(&g, .RCS, scale * .012, scale * .01)
	rcs_b := procedural_ship_system_add(&g, .RCS, scale * .012, scale * .01)
	g.nodes[rcs_b].paired = true
	mission := procedural_ship_system_add(&g, .Mission, scale * .06, scale * .09)

	for target in 1 ..< g.node_count do procedural_ship_system_link(
		&g,
		structure,
		target,
		.Load,
		max(g.nodes[target].mass / scale, f32(.05)),
	)
	procedural_ship_system_link(&g, propellant, drive, .Material, output)
	procedural_ship_system_link(&g, power, drive, .Energy, output)
	procedural_ship_system_link(&g, water, habitat, .Material, 1)
	procedural_ship_system_link(&g, water, power, .Coolant, .8)
	procedural_ship_system_link(&g, command, drive, .Control, 1)
	procedural_ship_system_link(&g, command, sensor, .Control, 1)
	procedural_ship_system_link(&g, command, rcs_a, .Control, 1)
	procedural_ship_system_link(&g, command, rcs_b, .Control, 1)
	procedural_ship_system_link(&g, habitat, command, .Crew, 1)
	procedural_ship_system_link(&g, command, mission, .Control, .7)
	if weapon >= 0 {
		procedural_ship_system_link(&g, power, weapon, .Energy, 1)
		procedural_ship_system_link(&g, command, weapon, .Control, 1)
	}
	procedural_ship_system_link(&g, power, thermal_a, .Coolant, output)
	procedural_ship_system_link(&g, drive, thermal_a, .Coolant, output)
	if thermal_b >= 0 {
		procedural_ship_system_link(&g, power, thermal_b, .Coolant, output)
		procedural_ship_system_link(&g, drive, thermal_b, .Coolant, output)
	}

	orders := [3][4]Procedural_Ship_System_Kind {
		{.Propellant, .Power, .Water, .Habitat},
		{.Power, .Propellant, .Water, .Habitat},
		{.Propellant, .Water, .Power, .Habitat},
	}
	phase :=
		f32(ship_construction_visual_mix(r.seed ~ 0x62a9d9ed799705f5) % 1000) /
		1000
	best := g
	best.layout_score = f32(1e30)
	for order in orders {
		candidate := g
		procedural_ship_system_apply_layout_candidate(&candidate, r, order, phase)
		candidate.layout_score = procedural_ship_system_layout_score(&candidate, r.frame.beam)
		if candidate.layout_score < best.layout_score do best = candidate
	}
	center := [2]f32{}
	total_mass := f32(0)
	for node in best.nodes[:best.node_count] {
		center[0] += node.position[1] * node.mass
		center[1] += node.position[2] * node.mass
		total_mass += node.mass
	}
	if total_mass > 0 {
		center[0] /= total_mass
		center[1] /= total_mass
	}
	best.balanced =
		f32(math.sqrt(f64(center[0] * center[0] + center[1] * center[1]))) <=
		max(r.frame.beam * .05, f32(.05))
	best.complete = best.complete && best.node_count > 0 && best.link_count > 0
	best.fingerprint = ship_construction_visual_mix(
		r.seed ~
			u64(best.node_count) * 0x9e3779b97f4a7c15 ~
			u64(best.link_count) * 0xbf58476d1ce4e5b9 ~
			u64(int(best.layout_score * 1000)),
	)
	return best
}
