package game

import "core:fmt"
import "core:math"
dark_random_position :: proc(state: ^u64, extent, depth: f64) -> Dark_Vec4 {
	return {
		planet_random_range(state, -extent, extent),
		planet_random_range(state, -extent, extent),
		planet_random_range(state, -extent, extent),
		planet_random_range(state, -depth, depth),
	}
}

dark_chunk_coord_at :: proc(position: Dark_Vec4) -> Dark_Chunk_Coord {
	r: Dark_Chunk_Coord
	for axis in 0 ..< 4 do r[axis] = i32(math.floor(position[axis] / DARK_CHUNK_SIZE))
	return r
}
dark_chunk_equal :: proc(a, b: Dark_Chunk_Coord) -> bool {for axis in 0 ..< 4 do if a[axis] != b[axis] do return false
	return true}
dark_chunk_less :: proc(a, b: Dark_Chunk_Coord) -> bool {for axis in 0 ..< 4 {if a[axis] < b[axis] do return true
		if a[axis] > b[axis] do return false}
	return false}
dark_chunk_seed :: proc(seed: u64, coord: Dark_Chunk_Coord) -> u64 {
	r := seed ~ 0x34444348554e4b31
	for axis in 0 ..< 4 {r ~= u64(u32(coord[axis])) + u64(axis + 1) * 0x9e3779b9; r = planet_rng_next(&r)}
	return r
}
dark_chunk_position :: proc(state: ^u64, coord: Dark_Chunk_Coord) -> Dark_Vec4 {
	r: Dark_Vec4
	for axis in 0 ..< 4 do r[axis] = f64(coord[axis]) * DARK_CHUNK_SIZE + planet_random_range(state, .4, DARK_CHUNK_SIZE - .4)
	return r
}
dark_query_chunk :: proc(
	seed: u64,
	galaxy_neighborhood_count: int,
	coord: Dark_Chunk_Coord,
) -> Dark_Chunk {
	state := dark_chunk_seed(seed, coord)
	r := Dark_Chunk {
		coord = coord,
	}
	for i in 0 ..< DARK_CHUNK_DOORS {
		id := planet_rng_next(&state); if id == 0 do id = 1
		r.doors[i] = {
			id                  = id,
			chunk               = coord,
			position            = dark_chunk_position(&state, coord),
			radius              = planet_random_range(&state, .35, .8),
			galaxy_neighborhood = int(
				planet_rng_next(&state) % u64(max(galaxy_neighborhood_count, 1)),
			),
			access              = planet_random_range(&state, .5, 1),
			semantic_tags       = make_semantic_tags(
				.Entity,
				.Destination,
				.Navigation,
				.Discovery,
			),
		}
	}
	for i in 0 ..< DARK_CHUNK_FIELDS {
		id := planet_rng_next(&state); if id == 0 do id = 1
		r.fields[i] = {
			id                = id,
			chunk             = coord,
			position          = dark_chunk_position(&state, coord),
			radius            = planet_random_range(&state, 1.5, 3.8),
			wake_energy       = planet_random_range(&state, 0, .2),
			film              = planet_random_range(&state, .08, .45),
			hush              = planet_random_range(&state, 0, .12),
			detritus          = planet_random_range(&state, 0, .18),
			law_intensity     = planet_random_range(&state, .04, .55),
			weather_intensity = planet_random_range(&state, .02, .45),
			weather_phase     = planet_random_range(&state, 0, math.PI * 2),
			semantic_tags     = make_semantic_tags(.Entity, .Species, .Environment),
		}
	}
	for i in 0 ..< DARK_CHUNK_ORGANISMS {
		role_roll := int(planet_rng_next(&state) % 10)
		role: Dark_Ecological_Role =
			role_roll < 5 ? .Lantern_Grazer : role_roll < 7 ? .Shear_Hunter : role_roll < 9 ? .Hush_Colony : .Grave_Reef
		genome_seed := planet_rng_next(&state)
		id := planet_rng_next(&state); if id == 0 do id = 1
		r.organisms[i] = {
			id            = id,
			chunk         = coord,
			role          = role,
			position      = dark_chunk_position(&state, coord),
			orientation   = dark_orientation_for_id(id),
			radius        = role == .Grave_Reef ? 2.5 : planet_random_range(&state, .45, 1.15),
			energy        = planet_random_range(&state, .45, .9),
			condition     = 1,
			sensory_range = role == .Shear_Hunter ? 5.5 : 3.5,
			mobility      = dark_mobility_for_role(role),
			behavior      = role == .Grave_Reef ? .Dormant : .Migrating,
			genome        = generate_sdf_creature(genome_seed),
			alive         = true,
			semantic_tags = make_semantic_tags(.Entity, .Species, .Environment, .Discovery),
		}
	}
	return r
}

dark_correlated_neighborhood :: proc(d: ^Dark_Continuum, position: Dark_Vec4, id: u64) -> int {
	count := max(d.galaxy_neighborhood_count, 1)
	depth := dark_depth_from_anchor(d.seed, d.anchor_position, position)
	start, finish := 0, count
	if depth < 1.5 {finish = max(1, count / 4)}
	else if depth < 4 {start = count / 4; finish = max(start + 1, count / 2)}
	else if depth < 6.5 {start = count / 2; finish = max(start + 1, count * 7 / 8)}
	else {start = count * 7 / 8}
	return d.neighborhood_by_anchor_distance[start + int(id % u64(max(finish - start, 1)))]
}

dark_assign_correlated_door_endpoint :: proc(d: ^Dark_Continuum, door: ^Dark_Door) {
	if d.anchor_door_id == 0 || door.id == d.anchor_door_id do return
	door.galaxy_neighborhood = dark_correlated_neighborhood(d, door.position, door.id)
}

dark_rebuild_neighborhood_distance_order :: proc(d: ^Dark_Continuum, galaxy: ^Galaxy) {
	if d == nil || galaxy == nil || d.anchor_neighborhood < 0 || d.anchor_neighborhood >= galaxy.neighborhood_count do return
	for i in 0 ..< d.galaxy_neighborhood_count {
		d.neighborhood_by_anchor_distance[i] = i
		for j := i; j > 0; j -= 1 {
			a, b := d.neighborhood_by_anchor_distance[j - 1], d.neighborhood_by_anchor_distance[j]
			dx_a, dy_a, dz_a := galaxy.neighborhoods[a].x_kpc - galaxy.neighborhoods[d.anchor_neighborhood].x_kpc, galaxy.neighborhoods[a].y_kpc - galaxy.neighborhoods[d.anchor_neighborhood].y_kpc, galaxy.neighborhoods[a].z_kpc - galaxy.neighborhoods[d.anchor_neighborhood].z_kpc
			dx_b, dy_b, dz_b := galaxy.neighborhoods[b].x_kpc - galaxy.neighborhoods[d.anchor_neighborhood].x_kpc, galaxy.neighborhoods[b].y_kpc - galaxy.neighborhoods[d.anchor_neighborhood].y_kpc, galaxy.neighborhoods[b].z_kpc - galaxy.neighborhoods[d.anchor_neighborhood].z_kpc
			if dx_a * dx_a + dy_a * dy_a + dz_a * dz_a <= dx_b * dx_b + dy_b * dy_b + dz_b * dz_b do break
			d.neighborhood_by_anchor_distance[j - 1], d.neighborhood_by_anchor_distance[j] = d.neighborhood_by_anchor_distance[j], d.neighborhood_by_anchor_distance[j - 1]
		}
	}
}
dark_sort_loaded_entities :: proc(d: ^Dark_Continuum) {
	for i in 1 ..< d.door_count {value := d.doors[i]; j := i; for j > 0 && d.doors[j - 1].id > value.id {d.doors[j] = d.doors[j - 1]; j -= 1}; d.doors[j] = value}
	for i in 1 ..< d.field_count {value := d.fields[i]; j := i; for j > 0 && d.fields[j - 1].id > value.id {d.fields[j] = d.fields[j - 1]; j -= 1}; d.fields[j] = value}
	for i in 1 ..< d.organism_count {value := d.organisms[i]; j := i; for j > 0 && d.organisms[j - 1].id > value.id {d.organisms[j] = d.organisms[j - 1]; j -= 1}; d.organisms[j] = value}
}
dark_archived_chunk_index :: proc(d: ^Dark_Continuum, coord: Dark_Chunk_Coord) -> int {for archived, i in d.archived_chunks[:d.archived_chunk_count] do if dark_chunk_equal(archived.coord, coord) do return i
	return -1}
dark_mark_door_known :: proc(d: ^Dark_Continuum, id: u64) -> bool {
	found := false
	for &door in d.doors[:d.door_count] do if door.id == id {door.endpoint_known = true; found = true}
	for &archived in d.archived_chunks[:d.archived_chunk_count] do for &door in archived.doors[:archived.door_count] do if door.id == id {door.endpoint_known = true; found = true}
	return found
}
dark_ensure_correspondence_loaded :: proc(
	d: ^Dark_Continuum,
	id: u64,
	galaxy_neighborhood: int,
) -> bool {
	for door in d.doors[:d.door_count] do if (id == 0 || door.id == id) && door.galaxy_neighborhood == galaxy_neighborhood do return true
	for &archived in d.archived_chunks[:d.archived_chunk_count] {
		for door in archived.doors[:archived.door_count] do if (id == 0 || door.id == id) && door.galaxy_neighborhood == galaxy_neighborhood && door.endpoint_known do return dark_ensure_chunk_loaded(d, archived.coord)
	}
	return false
}
dark_chunk_distance :: proc(a, b: Dark_Chunk_Coord) -> i64 {result: i64; for axis in 0 ..< 4 do result += i64(abs(a[axis] - b[axis]))
	return result}
dark_archive_loaded_chunk :: proc(d: ^Dark_Continuum, coord: Dark_Chunk_Coord) -> bool {
	at := dark_archived_chunk_index(d, coord)
	if at < 0 {
		at = d.archived_chunk_count
		append(&d.archived_chunks, Dark_Archived_Chunk{})
		d.archived_chunk_count += 1
	}
	a := &d.archived_chunks[at]
	if a.organisms != nil do clear(&a.organisms)
	else do a.organisms = make([dynamic]Dark_Organism, 0, DARK_CHUNK_ORGANISMS)
	a.coord = coord
	a.door_count = 0
	a.field_count = 0
	a.archived_tick = d.simulation_tick
	write := 0
	for i in 0 ..< d.door_count {door := d.doors[i]; if dark_chunk_equal(door.chunk, coord) {if a.door_count < len(a.doors) {a.doors[a.door_count] = door; a.door_count += 1}} else {d.doors[write] = door; write += 1}}
	for i in write ..< d.door_count do d.doors[i] = {}
	d.door_count = write
	write = 0
	for i in 0 ..< d.field_count {field := d.fields[i]; if dark_chunk_equal(field.chunk, coord) {if a.field_count < len(a.fields) {a.fields[a.field_count] = field; a.field_count += 1}} else {d.fields[write] = field; write += 1}}
	for i in write ..< d.field_count do d.fields[i] = {}
	d.field_count = write
	write = 0
	a.organism_count = 0
	for i in 0 ..< d.organism_count {organism := d.organisms[i]; organism.chunk = dark_chunk_coord_at(organism.position); if dark_chunk_equal(organism.chunk, coord) {append(&a.organisms, organism); a.organism_count += 1} else {d.organisms[write] = organism; write += 1}}
	for i in write ..< d.organism_count do d.organisms[i] = {}
	d.organism_count = write
	for i in 0 ..< d.loaded_chunk_count do if dark_chunk_equal(d.loaded_chunks[i], coord) {for j in i ..< d.loaded_chunk_count - 1 do d.loaded_chunks[j] = d.loaded_chunks[j + 1]; d.loaded_chunk_count -= 1; d.loaded_chunks[d.loaded_chunk_count] = {}; break}
	return true
}
dark_evict_farthest_chunk :: proc(d: ^Dark_Continuum, requested: Dark_Chunk_Coord) -> bool {
	if d.loaded_chunk_count <= 0 do return false
	best := -1
	best_distance := i64(-1)
	for coord, i in d.loaded_chunks[:d.loaded_chunk_count] {
		distance := dark_chunk_distance(coord, requested)
		if distance > best_distance ||
		   distance == best_distance &&
			   (best < 0 ||
					   dark_chunk_less(
						   coord,
						   d.loaded_chunks[best],
					   )) {best = i; best_distance = distance}
	}
	return best >= 0 && dark_archive_loaded_chunk(d, d.loaded_chunks[best])
}
dark_ensure_chunk_loaded :: proc(d: ^Dark_Continuum, coord: Dark_Chunk_Coord) -> bool {
	for loaded in d.loaded_chunks[:d.loaded_chunk_count] do if dark_chunk_equal(loaded, coord) do return true
	archive_at := dark_archived_chunk_index(d, coord)
	doors_needed := archive_at >= 0 ? d.archived_chunks[archive_at].door_count : DARK_CHUNK_DOORS
	fields_needed :=
		archive_at >= 0 ? d.archived_chunks[archive_at].field_count : DARK_CHUNK_FIELDS
	organisms_needed :=
		archive_at >= 0 ? d.archived_chunks[archive_at].organism_count : DARK_CHUNK_ORGANISMS
	for d.loaded_chunk_count >= MAX_DARK_LOADED_CHUNKS || d.door_count + doors_needed > MAX_DARK_DOORS || d.organism_count + organisms_needed > MAX_DARK_ORGANISMS || d.field_count + fields_needed > MAX_DARK_FIELD_CELLS do if !dark_evict_farthest_chunk(d, coord) do return false
	if archive_at >= 0 {
		a := &d.archived_chunks[archive_at]
		for door in a.doors[:a.door_count] {d.doors[d.door_count] = door; d.door_count += 1}
		for field in a.fields[:a.field_count] {d.fields[d.field_count] = field; d.field_count += 1}
		for organism in a.organisms[:a.organism_count] {d.organisms[d.organism_count] = organism; d.organism_count += 1}
	} else {
		chunk := dark_query_chunk(d.seed, d.galaxy_neighborhood_count, coord)
		for &door in chunk.doors do dark_assign_correlated_door_endpoint(d, &door)
		for door in chunk.doors {d.doors[d.door_count] = door; d.door_count += 1}
		for field in chunk.fields {d.fields[d.field_count] = field; d.field_count += 1}
		for organism in chunk.organisms {d.organisms[d.organism_count] = organism; d.organism_count += 1}
	}
	d.loaded_chunks[d.loaded_chunk_count] = coord
	d.loaded_chunk_count += 1
	for i in 1 ..< d.loaded_chunk_count {value := d.loaded_chunks[i]; j := i; for j > 0 && dark_chunk_less(value, d.loaded_chunks[j - 1]) {d.loaded_chunks[j] = d.loaded_chunks[j - 1]; j -= 1}; d.loaded_chunks[j] = value}
	dark_sort_loaded_entities(d)
	return true
}

generate_dark_continuum :: proc(seed: u64, galaxy: ^Galaxy) -> Dark_Continuum {
	d := Dark_Continuum {
		seed                      = seed,
		paused                    = true,
		galaxy_neighborhood_count = galaxy.neighborhood_count,
		semantic_tags             = make_semantic_tags(
			.Entity,
			.Environment,
			.Navigation,
			.Discovery,
		),
	}
	_ = dark_ensure_chunk_loaded(&d, {})
	// The origin correspondence is the fleet's authenticated anchor. Every other
	// endpoint remains expedition-local until its record is transmitted.
	best := 0
	for door, i in d.doors[:d.door_count] do if dark_metric_distance(d.seed, {}, door.position) < dark_metric_distance(d.seed, {}, d.doors[best].position) do best = i
	d.doors[best], d.doors[0] = d.doors[0], d.doors[best]
	d.doors[0].endpoint_known = true
	d.anchor_door_id = d.doors[0].id
	d.anchor_neighborhood = d.doors[0].galaxy_neighborhood
	d.anchor_position = d.doors[0].position
	dark_rebuild_neighborhood_distance_order(&d, galaxy)
	for &door in d.doors[:d.door_count] do dark_assign_correlated_door_endpoint(&d, &door)
	return d
}

dark_continuum_destroy_storage :: proc(d: ^Dark_Continuum) {
	for &archived in d.archived_chunks do delete(archived.organisms)
	delete(d.archived_chunks)
	d.archived_chunks = nil
	d.archived_chunk_count = 0
}

dark_nearest_field :: proc(d: ^Dark_Continuum, position: Dark_Vec4) -> int {
	best := -1; distance := f64(1.0e30)
	for field, i in d.fields[:d.field_count] {candidate := dark_metric_distance(d.seed, position, field.position); if candidate < distance {best = i; distance = candidate}}
	return best
}

dark_environment_at :: proc(d: ^Dark_Continuum, position: Dark_Vec4) -> (law, weather: f64) {
	weight_total := f64(0)
	for field in d.fields[:d.field_count] {
		distance := dark_metric_distance(d.seed, position, field.position)
		weight := clamp(1 - distance / max(field.radius * 2.5, .001), 0, 1)
		law += field.law_intensity * weight
		weather += field.weather_intensity * weight
		weight_total += weight
	}
	if weight_total > 1 {law /= weight_total; weather /= weight_total}
	return clamp(law, 0, 1), clamp(weather, 0, 1)
}

dark_door_detection_confidence :: proc(
	d: ^Dark_Continuum,
	observer: Dark_Vec4,
	door: ^Dark_Door,
) -> f64 {
	_, weather := dark_environment_at(d, door.position)
	range_limit := (8 + door.access * 8) * (1 - weather * .55)
	distance := dark_metric_distance(d.seed, observer, door.position)
	if distance > range_limit do return 0
	return clamp(
		(1 - distance / max(range_limit, .001)) * (.45 + door.access * .55) * (1 - weather * .45),
		0,
		1,
	)
}

dark_deposit_wake :: proc(d: ^Dark_Continuum, start, finish: Dark_Vec4, energy: f64) {
	mid := dark_vec4_scale(dark_vec4_add(start, finish), .5)
	segment := dark_metric_distance(d.seed, start, finish)
	for &field in d.fields[:d.field_count] {
		distance := dark_metric_distance(d.seed, mid, field.position)
		if distance <= field.radius + segment * .5 do field.wake_energy = clamp(field.wake_energy + energy * clamp(1 - distance / max(field.radius + segment * .5, .001), .1, 1), 0, 1)
	}
}

dark_apply_sensor_emission :: proc(
	d: ^Dark_Continuum,
	observer: Dark_Vec4,
	emission: f64,
) -> u64 {
	if emission <= 0 do return 0
	changed: u64
	for &organism in d.organisms[:d.organism_count] {
		if !organism.alive || organism.attached_ship != 0 do continue
		distance := dark_metric_distance(d.seed, observer, organism.position)
		if distance > organism.sensory_range + emission * 3 do continue
		prior := organism.behavior
		switch organism.role {
		case .Shear_Hunter:
			organism.behavior = .Hunting
			organism.target_id = d.anchor_door_id
			toward := dark_vec4_normalized(dark_vec4_sub(observer, organism.position))
			organism.velocity = dark_vec4_add(
				organism.velocity,
				dark_vec4_scale(toward, organism.mobility.fourth_axis_acceleration * emission * .04),
			)
		case .Lantern_Grazer:
			organism.behavior = .Withdrawing
			away := dark_vec4_normalized(dark_vec4_sub(organism.position, observer))
			organism.velocity = dark_vec4_add(
				organism.velocity,
				dark_vec4_scale(away, organism.mobility.spatial_acceleration * emission * .03),
			)
		case .Hush_Colony:
			if emission >= .8 do organism.behavior = .Colonizing
		case .Wake_Film, .Grave_Reef:
		}
		if changed == 0 && organism.behavior != prior do changed = organism.id
	}
	return changed
}

dark_nearest_prey :: proc(d: ^Dark_Continuum, hunter_index: int) -> int {
	h := d.organisms[hunter_index]; best := -1; distance := h.sensory_range
	for prey, i in d.organisms[:d.organism_count] {if i == hunter_index || !prey.alive || prey.role != .Lantern_Grazer do continue; candidate := dark_metric_distance(d.seed, h.position, prey.position); if candidate < distance {best = i; distance = candidate}}
	return best
}

dark_nearest_grazer :: proc(d: ^Dark_Continuum, colony_index: int) -> int {
	colony := d.organisms[colony_index]
	best := -1
	distance := colony.sensory_range
	for grazer, i in d.organisms[:d.organism_count] {if i == colony_index || !grazer.alive || grazer.role != .Lantern_Grazer do continue; candidate := dark_metric_distance(d.seed, colony.position, grazer.position); if candidate < distance {best = i; distance = candidate}}
	return best
}

dark_organism_acceleration :: proc(d: ^Dark_Continuum, index: int) -> Dark_Vec4 {
	o := &d.organisms[index]; if !o.alive || o.role == .Grave_Reef do return {}
	target := Dark_Vec4{}; has_target := false
	if o.role == .Shear_Hunter {
		prey := dark_nearest_prey(d, index)
		if prey >=
		   0 {target = d.organisms[prey].position; has_target = true; o.target_id = d.organisms[prey].id; o.behavior = .Hunting}
	}
	if o.role == .Hush_Colony {
		grazer := dark_nearest_grazer(d, index)
		if grazer >=
		   0 {target = d.organisms[grazer].position; has_target = true; o.target_id = d.organisms[grazer].id; o.behavior = .Colonizing}
	}
	if !has_target {field := dark_nearest_field(d, o.position); if field >= 0 {target = d.fields[field].position; has_target = true; o.target_id = d.fields[field].id; o.behavior = o.role == .Hush_Colony ? .Colonizing : .Feeding}}
	if !has_target do return {}
	direction := dark_vec4_normalized(
		dark_vec4_sub(target, o.position),
	); depth := dark_depth_from_anchor(d.seed, d.anchor_position, o.position)
	// In a conformal metric, trajectories bend toward lower metric cost. Remove
	// the along-course component so folds change direction without creating a
	// spurious acceleration toward or away from the target.
	gradient := dark_metric_gradient(d.seed, o.position)
	perpendicular := dark_vec4_sub(
		gradient,
		dark_vec4_scale(direction, dark_vec4_dot(gradient, direction)),
	)
	direction = dark_vec4_normalized(
		dark_vec4_sub(direction, dark_vec4_scale(perpendicular, .35 * (1 + min(depth, 8) * .08))),
	)
	// Native fourth-axis authority grows with depth while ordinary spatial
	// acceleration stays bounded. Preferred-depth mismatch still costs energy.
	deep_freedom := 1 + min(depth, 8) * .16
	result := direction
	for axis in 0 ..< 3 do result[axis] *= o.mobility.spatial_acceleration
	result[3] *= o.mobility.fourth_axis_acceleration * deep_freedom
	return result
}

advance_dark_continuum_fixed :: proc(d: ^Dark_Continuum) {
	d.simulation_tick += 1; d.simulation_time += DARK_FIXED_STEP
	// Once a corpse has completed its visible withdrawal, its persistent meaning
	// lives in expedition observations and scars rather than an occupied body slot.
	// Stable compaction preserves the ordering of every surviving identity.
	write := 0
	for i in 0 ..< d.organism_count {
		o := d.organisms[i]
		expired := !o.alive && o.death_tick > 0 && d.simulation_tick > o.death_tick + 300
		if expired do continue
		if write != i do d.organisms[write] = o
		write += 1
	}
	for i in write ..< d.organism_count do d.organisms[i] = {}
	d.organism_count = write
	// Environment and primary production.
	for &field in d.fields[:d.field_count] {
		field.wake_energy = max(field.wake_energy - DARK_FIXED_STEP * .0015, 0)
		field.weather_intensity = clamp(
			field.weather_intensity +
			math.sin(d.simulation_time * .07 + field.weather_phase) * DARK_FIXED_STEP * .0008,
			0,
			1,
		)
		growth := (field.wake_energy * .028 + field.detritus * .006) * (1 - field.film)
		field.film = clamp(
			field.film + growth * DARK_FIXED_STEP - field.hush * .001 * DARK_FIXED_STEP,
			0,
			1,
		)
		field.hush = clamp(field.hush + field.film * .0004 * DARK_FIXED_STEP, 0, 1)
	}
	// Stable identity order is array order; expired bodies are only stable-compacted.
	original_organism_count := d.organism_count
	for i in 0 ..< original_organism_count {
		o := &d.organisms[i]; if !o.alive do continue
		if o.attached_ship != 0 {o.velocity = {}; o.behavior = .Colonizing; continue}
		if o.attached_organism != 0 {
			host_found := false
			for &host in d.organisms[:original_organism_count] do if host.id == o.attached_organism && host.alive {o.position = host.position; o.position[3] += min(host.radius * .12, .15); o.chunk = host.chunk; o.velocity = host.velocity; o.behavior = .Colonizing; o.energy = clamp(o.energy + DARK_FIXED_STEP * .0003, 0, 1); host_found = true; break}
			if host_found do continue
			o.attached_organism = 0
			o.target_id = 0
		}
		acceleration := dark_organism_acceleration(d, i)
		for axis in 0 ..< 4 {o.velocity[axis] = (o.velocity[axis] + acceleration[axis] * DARK_FIXED_STEP) * .992; o.position[axis] += o.velocity[axis] * DARK_FIXED_STEP}
		o.chunk = dark_chunk_coord_at(o.position)
		depth_error := math.abs(
			dark_depth_from_anchor(d.seed, d.anchor_position, o.position) -
			o.mobility.preferred_depth,
		)
		depth_cost :=
			max(depth_error - o.mobility.depth_tolerance, 0) *
			o.mobility.depth_crossing_cost *
			.0008
		law, _ := dark_environment_at(d, o.position)
		law_cost := max(law - o.mobility.law_drift_tolerance, 0) * .0012
		correspondence_width := clamp(
			1 - dark_depth_from_anchor(d.seed, d.anchor_position, o.position) * .08,
			.05,
			1,
		)
		correspondence_cost :=
			max(correspondence_width - o.mobility.correspondence_tolerance, 0) * .0007
		o.energy = clamp(
			o.energy - DARK_FIXED_STEP * (.00025 + depth_cost + law_cost + correspondence_cost),
			0,
			1,
		)
		field_index := dark_nearest_field(d, o.position)
		if field_index >=
		   0 {field := &d.fields[field_index]; distance := dark_metric_distance(d.seed, o.position, field.position)
			if distance < field.radius + o.radius {
				switch o.role {case .Lantern_Grazer:
					meal := min(field.film, DARK_FIXED_STEP * .004); field.film -= meal
					o.energy = clamp(o.energy + meal * .7, 0, 1); case .Hush_Colony:
					meal := min(field.wake_energy, DARK_FIXED_STEP * .002); field.wake_energy -=
						meal
					o.energy = clamp(o.energy + meal, 0, 1); case .Grave_Reef:
					field.detritus = clamp(
						field.detritus + DARK_FIXED_STEP * .0005,
						0,
						1,
					); case .Wake_Film, .Shear_Hunter:}
			}
		}
		if o.role == .Shear_Hunter &&
		   o.target_id !=
			   0 {for &prey in d.organisms[:original_organism_count] {if prey.id != o.target_id || !prey.alive do continue; if dark_metric_distance(d.seed, o.position, prey.position) <= o.radius + prey.radius {penetration, contact := dark_organisms_contact_at(o, &prey, d.simulation_time); if contact {meal := min(prey.energy, DARK_FIXED_STEP * .008); prey.energy -= meal; contact_point := dark_vec4_scale(dark_vec4_add(o.position, prey.position), .5); dark_record_injury(&prey, contact_point, clamp(meal * .45 + penetration * .05, .002, .12), d.simulation_tick); o.energy = clamp(o.energy + meal * .75, 0, 1)}}}}
		if o.role == .Hush_Colony &&
		   o.target_id !=
			   0 {for &host in d.organisms[:original_organism_count] {if host.id != o.target_id || !host.alive || host.role != .Lantern_Grazer do continue; if dark_metric_distance(d.seed, o.position, host.position) <= o.radius + host.radius {_, contact := dark_organisms_contact_at(o, &host, d.simulation_time); if contact {o.attached_organism = host.id; o.behavior = .Colonizing; o.velocity = host.velocity}}; break}}
		if o.role ==
		   .Lantern_Grazer {for reef in d.organisms[:original_organism_count] do if reef.alive && reef.role == .Grave_Reef && dark_metric_distance(d.seed, o.position, reef.position) < reef.radius * 1.8 {o.condition = clamp(o.condition + DARK_FIXED_STEP * .001, 0, 1); break}}
		if o.energy <=
		   0 {o.condition = max(o.condition - DARK_FIXED_STEP * .01, 0); o.behavior = .Injured}
		if o.condition <=
		   0 {o.alive = false; o.death_tick = d.simulation_tick; o.behavior = .Injured; if field_index >= 0 do d.fields[field_index].detritus = clamp(d.fields[field_index].detritus + .2, 0, 1)}
		if d.simulation_tick % 600 == 0 &&
		   o.alive &&
		   o.energy > .84 &&
		   o.condition > .75 &&
		   o.role != .Grave_Reef &&
		   d.organism_count < MAX_DARK_ORGANISMS {
			state :=
				o.id ~
				d.simulation_tick ~
				d.seed; child_id := planet_rng_next(&state); if child_id == 0 do child_id = 1
			child := o^; child.id = child_id; child.position[3] += .18; child.chunk = dark_chunk_coord_at(child.position); child.velocity = dark_vec4_scale(o.velocity, -.25); child.energy = .34; child.condition = .9; child.injury = 0; child.target_id = 0; child.behavior = .Migrating; child.genome = generate_sdf_creature(planet_rng_next(&state)); o.energy -= .24; d.organisms[d.organism_count] = child; d.organism_count += 1
		}
	}
	if d.simulation_tick % 1200 == 0 && d.organism_count < MAX_DARK_ORGANISMS {
		for &field in d.fields[:d.field_count] {
			if field.detritus < .72 || d.organism_count >= MAX_DARK_ORGANISMS do continue
			has_reef := false
			for organism in d.organisms[:d.organism_count] do if organism.alive && organism.role == .Grave_Reef && dark_metric_distance(d.seed, organism.position, field.position) < field.radius * 1.5 {has_reef = true; break}
			if has_reef do continue
			state := field.id ~ d.simulation_tick ~ d.seed
			id := planet_rng_next(&state); if id == 0 do id = 1
			d.organisms[d.organism_count] = {
				id            = id,
				chunk         = field.chunk,
				role          = .Grave_Reef,
				position      = field.position,
				orientation   = dark_orientation_for_id(id),
				radius        = 1.2,
				energy        = .45,
				condition     = .7,
				sensory_range = 1,
				mobility      = dark_mobility_for_role(.Grave_Reef),
				behavior      = .Dormant,
				genome        = generate_sdf_creature(planet_rng_next(&state)),
				alive         = true,
				semantic_tags = make_semantic_tags(.Entity, .Species, .Environment, .Discovery),
			}
			d.organism_count += 1
			field.detritus -= .5
		}
	}
	if d.organism_count != original_organism_count do dark_sort_loaded_entities(d)
}
