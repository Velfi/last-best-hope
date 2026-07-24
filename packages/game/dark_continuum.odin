package game

import "core:fmt"
import "core:math"

// The continuum is authoritative Dark geography. Presentation may project it,
// but routes, manifestations, and contacts are evaluated in four dimensions.
MAX_DARK_LOADED_CHUNKS :: 16
INITIAL_DARK_ARCHIVED_CHUNKS :: 32
MAX_DARK_DOORS :: 48
MAX_DARK_ORGANISMS :: 32
MAX_DARK_FIELD_CELLS :: 32
MAX_DARK_COURSE_WAYPOINTS :: 16
MAX_DARK_TRACKS :: 20
MAX_DARK_INJURY_MASKS :: 6
MAX_FORECAST_FACTORS :: 8
DARK_FIXED_STEP :: 0.1
DARK_CHUNK_SIZE :: 8.0
DARK_CHUNK_DOORS :: 3
DARK_CHUNK_ORGANISMS :: 2
DARK_CHUNK_FIELDS :: 2

Dark_Vec4 :: [4]f64
Dark_Chunk_Coord :: [4]i32
Forecast_Evidence :: enum u8 {
	Observed,
	Inferred,
	Unknown,
}
Forecast_Factor :: struct {
	label:         string,
	contribution:  f64,
	confidence:    f64,
	source_ship:   Ship_ID,
	source_event:  u64,
	evidence:      Forecast_Evidence,
}
Dark_Sensor_Posture :: enum u8 {
	Quiet,
	Passive,
	Active_Sweep,
	Illuminate,
}
Dark_Ecological_Role :: enum u8 {
	Wake_Film,
	Lantern_Grazer,
	Hush_Colony,
	Shear_Hunter,
	Grave_Reef,
}
Dark_Behavior :: enum u8 {
	Dormant,
	Feeding,
	Migrating,
	Hunting,
	Withdrawing,
	Colonizing,
	Injured,
}

Dark_Door :: struct {
	id:                  u64,
	chunk:               Dark_Chunk_Coord,
	position:            Dark_Vec4,
	radius:              f64,
	galaxy_neighborhood: int,
	endpoint_known:      bool,
	access:              f64,
	traffic:             i32,
	semantic_tags:       Semantic_Tags,
}

Dark_Mobility_Profile :: struct {
	preferred_depth, depth_tolerance:               f64,
	spatial_acceleration, fourth_axis_acceleration: f64,
	correspondence_tolerance, law_drift_tolerance:  f64,
	manifestation_breadth, depth_crossing_cost:     f64,
}

Dark_Injury_Mask :: struct {
	local_center:     Dark_Vec4,
	radius, severity: f64,
	inflicted_tick:   u64,
}

Dark_Manifestation_Conditions :: struct {
	observer_correspondence_w:                                               f64,
	correspondence_width, isolation_strength, curvature, wake, law, weather: f64,
}

Dark_Manifestation_Query :: struct {
	world_slice_w, local_slice_w, breadth, confidence: f64,
	manifested:                                        bool,
}

Dark_Organism :: struct {
	id:                                u64,
	chunk:                             Dark_Chunk_Coord,
	role:                              Dark_Ecological_Role,
	position, velocity:                Dark_Vec4,
	orientation:                       [6]f64,
	radius, energy, condition, injury: f64,
	sensory_range:                     f64,
	mobility:                          Dark_Mobility_Profile,
	behavior:                          Dark_Behavior,
	target_id:                         u64,
	attached_ship:                     Ship_ID,
	attached_organism:                 u64,
	last_contact_tick:                 u64,
	death_tick:                        u64,
	genome:                            Sdf_Creature_Genome,
	injury_masks:                      [MAX_DARK_INJURY_MASKS]Dark_Injury_Mask,
	injury_mask_count:                 int,
	alive:                             bool,
	semantic_tags:                     Semantic_Tags,
}

Dark_Field_Cell :: struct {
	id:                                              u64,
	chunk:                                           Dark_Chunk_Coord,
	position:                                        Dark_Vec4,
	radius, wake_energy, film, hush, detritus:       f64,
	law_intensity, weather_intensity, weather_phase: f64,
	semantic_tags:                                   Semantic_Tags,
}

Dark_Course_Waypoint :: struct {
	position: Dark_Vec4,
}
Dark_Course :: struct {
	waypoints:      [MAX_DARK_COURSE_WAYPOINTS]Dark_Course_Waypoint,
	waypoint_count: int,
}

Dark_Course_Forecast :: struct {
	distance, ship_days, law_drift, coherence_cost:                 f64,
	weather_exposure, ecological_interception, topology_confidence: f64,
	factors:                                                        [MAX_FORECAST_FACTORS]Forecast_Factor,
	factor_count:                                                   int,
	valid:                                                          bool,
}

Dark_Track :: struct {
	organism_id:                                                     u64,
	role:                                                            Dark_Ecological_Role,
	relative_bearing, velocity:                                      Dark_Vec4,
	distance, estimated_extent, energy_band, condition_band, injury: f64,
	preferred_depth:                                                 f64,
	behavior:                                                        Dark_Behavior,
	target_id:                                                       u64,
	confidence:                                                      f64,
	factors:                                                         [MAX_FORECAST_FACTORS]Forecast_Factor,
	factor_count:                                                    int,
}

Dark_Tracker :: struct {
	tracks:      [MAX_DARK_TRACKS]Dark_Track,
	track_count: int,
}
Dark_Chunk :: struct {
	coord:     Dark_Chunk_Coord,
	doors:     [DARK_CHUNK_DOORS]Dark_Door,
	organisms: [DARK_CHUNK_ORGANISMS]Dark_Organism,
	fields:    [DARK_CHUNK_FIELDS]Dark_Field_Cell,
}
Dark_Archived_Chunk :: struct {
	coord:          Dark_Chunk_Coord,
	doors:          [DARK_CHUNK_DOORS]Dark_Door,
	door_count:     int,
	organisms:      [dynamic]Dark_Organism,
	organism_count: int,
	fields:         [DARK_CHUNK_FIELDS]Dark_Field_Cell,
	field_count:    int,
	archived_tick:  u64,
}

Dark_Expedition_Navigation :: struct {
	position:                                           Dark_Vec4,
	course:                                             Dark_Course,
	forecast:                                           Dark_Course_Forecast,
	tracker:                                            Dark_Tracker,
	manual_velocity:                                    Dark_Vec4,
	segment:                                            int,
	segment_progress, speed, accumulator:               f64,
	sensor_posture:                                     Dark_Sensor_Posture,
	sensor_posture_event:                               u64,
	sensor_emission:                                    f64,
	autopilot_active, paused_for_replan, manual_active: bool,
}

Dark_Continuum :: struct {
	seed:                         u64,
	simulation_tick:              u64,
	simulation_time, accumulator: f64,
	paused:                       bool,
	galaxy_neighborhood_count:    int,
	neighborhood_by_anchor_distance: [MAX_GALACTIC_NEIGHBORHOODS]int,
	anchor_door_id:               u64,
	anchor_neighborhood:          int,
	anchor_position:              Dark_Vec4,
	loaded_chunks:                [MAX_DARK_LOADED_CHUNKS]Dark_Chunk_Coord,
	loaded_chunk_count:           int,
	archived_chunks:              [dynamic]Dark_Archived_Chunk,
	archived_chunk_count:         int,
	doors:                        [MAX_DARK_DOORS]Dark_Door,
	door_count:                   int,
	organisms:                    [MAX_DARK_ORGANISMS]Dark_Organism,
	organism_count:               int,
	fields:                       [MAX_DARK_FIELD_CELLS]Dark_Field_Cell,
	field_count:                  int,
	semantic_tags:                Semantic_Tags,
}

dark_vec4_add :: proc(a, b: Dark_Vec4) -> Dark_Vec4 {r: Dark_Vec4; for i in 0 ..< 4 do r[i] = a[i] + b[i]
	return r}
dark_vec4_sub :: proc(a, b: Dark_Vec4) -> Dark_Vec4 {r: Dark_Vec4; for i in 0 ..< 4 do r[i] = a[i] - b[i]
	return r}
dark_vec4_scale :: proc(a: Dark_Vec4, s: f64) -> Dark_Vec4 {r: Dark_Vec4; for i in 0 ..< 4 do r[i] = a[i] * s
	return r}
dark_vec4_dot :: proc(a, b: Dark_Vec4) -> f64 {r: f64; for i in 0 ..< 4 do r += a[i] * b[i]
	return r}
dark_vec4_length :: proc(a: Dark_Vec4) -> f64 {return math.sqrt(dark_vec4_dot(a, a))}
dark_vec4_normalized :: proc(a: Dark_Vec4) -> Dark_Vec4 {l := dark_vec4_length(a); if l < 1e-9 do return {}
	return dark_vec4_scale(a, 1 / l)}

dark_rotate_plane :: proc(value: Dark_Vec4, a, b: int, angle: f64) -> Dark_Vec4 {r := value
	c, s := math.cos(angle), math.sin(angle)
	r[a] = value[a] * c - value[b] * s
	r[b] = value[a] * s + value[b] * c
	return r}
dark_orientation_pairs := [6][2]int{{0, 1}, {0, 2}, {0, 3}, {1, 2}, {1, 3}, {2, 3}}
dark_organism_local_to_world :: proc(o: ^Dark_Organism, local: Dark_Vec4) -> Dark_Vec4 {r :=
		dark_vec4_scale(local, o.radius)
	for pair, i in dark_orientation_pairs do r = dark_rotate_plane(r, pair[0], pair[1], o.orientation[i])
	return dark_vec4_add(o.position, r)}
dark_organism_world_to_local :: proc(o: ^Dark_Organism, world: Dark_Vec4) -> Dark_Vec4 {r :=
		dark_vec4_sub(world, o.position)
	for reverse := 0; reverse < 6; reverse += 1 {i := 5 - reverse; pair :=
			dark_orientation_pairs[i]
		r = dark_rotate_plane(r, pair[0], pair[1], -o.orientation[i])}
	return dark_vec4_scale(r, 1 / max(o.radius, .001))}
dark_orientation_for_id :: proc(id: u64) -> [6]f64 {state := id ~ 0x34642d6f7269656e; r: [6]f64
	for &angle in r do angle = planet_random_range(&state, -math.PI, math.PI)
	return r}

// Depth is never an absolute fourth coordinate. It is the local separation
// from the expedition's authenticated membrane correspondence.
dark_depth_from_anchor :: proc(seed: u64, anchor, position: Dark_Vec4) -> f64 {
	a := position
	a[3] = anchor[3]
	return dark_metric_distance(seed, a, position)
}

// Static folds form a smooth conformal metric. The factor remains positive,
// so shortcuts bend distance without producing discontinuous teleportation.
dark_metric_factor :: proc(seed: u64, position: Dark_Vec4) -> f64 {
	phase := f64(seed % 104729) * .000061
	fold :=
		math.sin(position[0] * .071 + position[3] * .113 + phase) * .22 +
		math.sin(position[1] * .053 - position[2] * .067 + position[3] * .041 - phase) * .16
	depth := math.abs(position[3])
	return clamp(1 + fold - depth * .012, .28, 1.65)
}

dark_metric_gradient :: proc(seed: u64, position: Dark_Vec4) -> Dark_Vec4 {
	epsilon :: .05
	gradient: Dark_Vec4
	for axis in 0 ..< 4 {before, after := position, position; before[axis] -= epsilon; after[axis] += epsilon; gradient[axis] = (dark_metric_factor(seed, after) - dark_metric_factor(seed, before)) / (2 * epsilon)}
	return gradient
}

dark_vec4_lerp :: proc(a, b: Dark_Vec4, t: f64) -> Dark_Vec4 {
	return dark_vec4_add(a, dark_vec4_scale(dark_vec4_sub(b, a), t))
}

dark_metric_distance :: proc(seed: u64, a, b: Dark_Vec4) -> f64 {
	coordinate_length := dark_vec4_length(dark_vec4_sub(b, a))
	if coordinate_length < 1e-12 do return 0
	// Deterministic composite Simpson integration of ds = conformal(x)|dx|.
	// Unlike a midpoint sample, this resolves folds crossed anywhere along the
	// segment and composes consistently for player-authored course polylines.
	steps :: 8
	weighted := dark_metric_factor(seed, a) + dark_metric_factor(seed, b)
	for i in 1 ..< steps {
		weight := i % 2 == 0 ? 2.0 : 4.0
		weighted += weight * dark_metric_factor(seed, dark_vec4_lerp(a, b, f64(i) / steps))
	}
	return coordinate_length * weighted / (3 * steps)
}

dark_mobility_for_role :: proc(role: Dark_Ecological_Role) -> Dark_Mobility_Profile {
	switch role {
	case .Wake_Film:
		return {
			preferred_depth = .6,
			depth_tolerance = .8,
			spatial_acceleration = .02,
			fourth_axis_acceleration = .01,
			correspondence_tolerance = .9,
			law_drift_tolerance = .3,
			manifestation_breadth = .8,
			depth_crossing_cost = .8,
		}
	case .Lantern_Grazer:
		return {
			preferred_depth = 2.2,
			depth_tolerance = 2.0,
			spatial_acceleration = .18,
			fourth_axis_acceleration = .25,
			correspondence_tolerance = .65,
			law_drift_tolerance = .65,
			manifestation_breadth = .72,
			depth_crossing_cost = .18,
		}
	case .Hush_Colony:
		return {
			preferred_depth = 1.4,
			depth_tolerance = 1.4,
			spatial_acceleration = .04,
			fourth_axis_acceleration = .05,
			correspondence_tolerance = .85,
			law_drift_tolerance = .45,
			manifestation_breadth = .38,
			depth_crossing_cost = .42,
		}
	case .Shear_Hunter:
		return {
			preferred_depth = 4.2,
			depth_tolerance = 3.0,
			spatial_acceleration = .22,
			fourth_axis_acceleration = .55,
			correspondence_tolerance = .42,
			law_drift_tolerance = .92,
			manifestation_breadth = .2,
			depth_crossing_cost = .12,
		}
	case .Grave_Reef:
		return {
			preferred_depth = 2.8,
			depth_tolerance = 2.5,
			correspondence_tolerance = .8,
			law_drift_tolerance = .75,
			manifestation_breadth = 1,
			depth_crossing_cost = 1,
		}
	}
	return {}
}

// Fleet names remain provisional descriptions. Identity persistence comes
// from the organism id, so the same body keeps its name across observations.
dark_organism_name :: proc(id: u64, role: Dark_Ecological_Role) -> string {
	prefixes := [8]string {
		"Split",
		"Hollow",
		"Braided",
		"Pale",
		"Crossing",
		"Ribbed",
		"Echoing",
		"Veiled",
	}
	forms := [5]string{"Film", "Lantern", "Hush", "Shear", "Reef"}
	prefix := prefixes[int(id % u64(len(prefixes)))]
	form := forms[int(role)]
	return fmt.tprintf("%s %s %03d", prefix, form, id % 1000)
}

dark_manifestation_for :: proc(
	o: ^Dark_Organism,
	conditions: Dark_Manifestation_Conditions,
) -> Dark_Manifestation_Query {
	state := o.genome.seed ~ 0x6d616e6966657374
	sensitivity := Dark_Vec4 {
		planet_random_range(&state, -.55, .55),
		planet_random_range(&state, -.45, .45),
		planet_random_range(&state, -.35, .35),
		planet_random_range(&state, -.30, .30),
	}
	condition_shift :=
		sensitivity[0] * conditions.isolation_strength +
		sensitivity[1] * conditions.curvature +
		sensitivity[2] * conditions.wake +
		sensitivity[3] * (conditions.law + conditions.weather)
	local_slice := conditions.observer_correspondence_w - o.position[3] + condition_shift
	breadth := max(
		o.mobility.manifestation_breadth * max(conditions.correspondence_width, .05),
		.04,
	)
	return {
		world_slice_w = o.position[3] + local_slice,
		local_slice_w = local_slice,
		breadth = breadth,
		confidence = clamp(1 - conditions.weather * .35 - conditions.law * .2, .1, 1),
		manifested = math.abs(local_slice) <= o.radius * (1 + breadth),
	}
}

dark_organism_remains_present :: proc(d: ^Dark_Continuum, o: ^Dark_Organism) -> bool {
	return o.alive || o.death_tick > 0 && d.simulation_tick <= o.death_tick + 300
}

dark_organism_world_distance_at :: proc(o: ^Dark_Organism, point: Dark_Vec4, time: f64) -> f64 {
	local := dark_organism_world_to_local(o, point)
	distance := sdf_creature_distance_at(&o.genome, local, time) * o.radius
	for mask in o.injury_masks[:o.injury_mask_count] {
		world_center := dark_organism_local_to_world(o, mask.local_center)
		cut := dark_vec4_length(dark_vec4_sub(point, world_center)) - mask.radius * o.radius
		distance = max(distance, -cut * mask.severity)
	}
	return distance
}

dark_organism_world_gradient_at :: proc(
	o: ^Dark_Organism,
	point: Dark_Vec4,
	time: f64,
) -> (
	Dark_Vec4,
	bool,
) {
	epsilon := max(o.radius * .0025, .0005)
	gradient: Dark_Vec4
	for axis in 0 ..< 4 {
		before, after := point, point
		before[axis] -= epsilon
		after[axis] += epsilon
		gradient[axis] =
			dark_organism_world_distance_at(o, after, time) -
			dark_organism_world_distance_at(o, before, time)
	}
	length := dark_vec4_length(gradient)
	if length <= 1e-10 do return {}, false
	return dark_vec4_scale(gradient, 1 / length), true
}

dark_contact_probe :: proc(a, b: ^Dark_Organism, point: Dark_Vec4, time: f64) -> (f64, bool) {
	da := dark_organism_world_distance_at(a, point, time)
	db := dark_organism_world_distance_at(b, point, time)
	separation := max(da, db)
	return max(-separation, 0), separation <= 0
}

dark_organisms_contact_at :: proc(a, b: ^Dark_Organism, time: f64) -> (f64, bool) {
	center_distance := dark_vec4_length(dark_vec4_sub(b.position, a.position))
	if center_distance > a.radius * 2.2 + b.radius * 2.2 do return 0, false
	best_penetration := f64(0)
	contact_found := false
	best_separation := f64(1.0e30)
	best_point: Dark_Vec4
	seeds: [17 + 2 * SDF_CREATURE_MAX_GENES]Dark_Vec4
	seed_count := 0
	for i in 0 ..= 16 {seeds[seed_count] = dark_vec4_lerp(a.position, b.position, f64(i) / 16); seed_count += 1}
	// Offset CSG lobes need not intersect the line between body centers. Gene
	// centers provide stable additional starts without reducing either body to
	// a bounding sphere.
	for gene in a.genome.genes[:a.genome.gene_count] {seeds[seed_count] = dark_organism_local_to_world(a, gene.center); seed_count += 1}
	for gene in b.genome.genes[:b.genome.gene_count] {seeds[seed_count] = dark_organism_local_to_world(b, gene.center); seed_count += 1}
	for point in seeds[:seed_count] {
		da := dark_organism_world_distance_at(a, point, time)
		db := dark_organism_world_distance_at(b, point, time)
		separation := max(da, db)
		if separation <=
		   0 {contact_found = true; best_penetration = max(best_penetration, -separation)}
		if separation < best_separation {best_separation = separation; best_point = point}
	}
	if contact_found do return best_penetration, true
	point := best_point
	for _ in 0 ..< 10 {
		penetration, contact := dark_contact_probe(a, b, point, time)
		if contact do return penetration, true
		da := dark_organism_world_distance_at(a, point, time)
		db := dark_organism_world_distance_at(b, point, time)
		gradient: Dark_Vec4
		ok: bool
		if da >=
		   db {gradient, ok = dark_organism_world_gradient_at(a, point, time)} else {gradient, ok = dark_organism_world_gradient_at(b, point, time)}
		if !ok do break
		step := clamp(max(da, db), .002, max(min(a.radius, b.radius) * .3, .01))
		point = dark_vec4_sub(point, dark_vec4_scale(gradient, step))
	}
	return 0, false
}

dark_record_injury :: proc(o: ^Dark_Organism, world_contact: Dark_Vec4, severity: f64, tick: u64) {
	mask := Dark_Injury_Mask {
		radius         = clamp(.12 + severity * .8, .12, .55),
		severity       = clamp(severity, .1, 1),
		inflicted_tick = tick,
	}
	mask.local_center = dark_organism_world_to_local(o, world_contact)
	if o.injury_mask_count <
	   MAX_DARK_INJURY_MASKS {o.injury_masks[o.injury_mask_count] = mask; o.injury_mask_count += 1} else {oldest := 0; for existing, i in o.injury_masks do if existing.inflicted_tick < o.injury_masks[oldest].inflicted_tick do oldest = i; o.injury_masks[oldest] = mask}
	o.injury = clamp(o.injury + severity, 0, 1)
}
