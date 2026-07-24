package game

import "core:math"

advance_dark_continuum :: proc(d: ^Dark_Continuum, elapsed: f64) {
	if d.paused || elapsed <= 0 do return
	d.accumulator = min(d.accumulator + elapsed, 2)
	for d.accumulator + 1e-9 >=
	    DARK_FIXED_STEP {advance_dark_continuum_fixed(d); d.accumulator -= DARK_FIXED_STEP}
}

dark_course_forecast :: proc(d: ^Dark_Continuum, course: ^Dark_Course) -> Dark_Course_Forecast {
	r := Dark_Course_Forecast {
		topology_confidence = 1,
		valid               = course.waypoint_count >=
			2 && course.waypoint_count <= MAX_DARK_COURSE_WAYPOINTS,
	}
	if !r.valid do return r
	for i in 1 ..< course.waypoint_count {a := course.waypoints[i - 1].position; b := course.waypoints[i].position; _ = dark_ensure_chunk_loaded(d, dark_chunk_coord_at(a)); _ = dark_ensure_chunk_loaded(d, dark_chunk_coord_at(b)); segment := dark_metric_distance(d.seed, a, b); mid := dark_vec4_scale(dark_vec4_add(a, b), .5); depth := dark_depth_from_anchor(d.seed, d.anchor_position, mid); law, weather := dark_environment_at(d, mid); r.distance += segment; r.law_drift += segment * (depth * .018 + law * .12); r.coherence_cost += segment * (.6 + depth * .24 + law * .16); r.weather_exposure += segment * weather * .08; r.topology_confidence *= clamp(1 - depth * .025 - weather * .04, .35, 1)
		for organism in d.organisms[:d.organism_count] {if !organism.alive || organism.role == .Grave_Reef do continue; distance := dark_metric_distance(d.seed, mid, organism.position); if distance < organism.sensory_range + segment * .5 do r.ecological_interception += clamp(1 - distance / (organism.sensory_range + segment * .5), 0, 1) * .12}
	}
	r.ship_days =
		r.distance *
		.72; r.ecological_interception = clamp(r.ecological_interception, 0, 1); r.weather_exposure = clamp(r.weather_exposure, 0, 1)
	forecast_add_factor(&r.factors, &r.factor_count, "metric distance", -r.distance * .05, 1, .Observed)
	forecast_add_factor(&r.factors, &r.factor_count, "topology confidence", r.topology_confidence, r.topology_confidence, .Inferred)
	forecast_add_factor(&r.factors, &r.factor_count, "weather exposure", -r.weather_exposure, r.topology_confidence, .Inferred)
	forecast_add_factor(&r.factors, &r.factor_count, "ecological interception", -r.ecological_interception, r.topology_confidence, .Inferred)
	if r.topology_confidence < .999 do forecast_add_factor(&r.factors, &r.factor_count, "unobserved topology", 0, 1 - r.topology_confidence, .Unknown)
	return r
}

dark_nearest_unknown_door :: proc(d: ^Dark_Continuum, position: Dark_Vec4) -> int {
	coord := dark_chunk_coord_at(position)
	_ = dark_ensure_chunk_loaded(d, coord)
	for axis in 0 ..< 4 {neighbor := coord; neighbor[axis] += 1; _ = dark_ensure_chunk_loaded(d, neighbor); neighbor[axis] -= 2; _ = dark_ensure_chunk_loaded(d, neighbor)}
	best := -1; best_distance := f64(1.0e30)
	for door, i in d.doors[:d.door_count] {if door.endpoint_known || dark_door_detection_confidence(d, position, &d.doors[i]) <= .05 do continue; distance := dark_metric_distance(d.seed, position, door.position); if distance < best_distance {best = i; best_distance = distance}}
	return best
}

dark_course_to_door :: proc(
	position: Dark_Vec4,
	door: ^Dark_Door,
	depth_excursion: f64,
	anchor_w: f64 = 0,
) -> Dark_Course {
	c := Dark_Course {
		waypoint_count = 3,
	}; c.waypoints[0].position = position; c.waypoints[2].position = door.position
	for axis in 0 ..< 4 do c.waypoints[1].position[axis] = (position[axis] + door.position[axis]) * .5
	relative_w := c.waypoints[1].position[3] - anchor_w
	sign :=
		relative_w < 0 ? -1.0 : 1.0; c.waypoints[1].position[3] = anchor_w + sign * max(math.abs(relative_w), max(depth_excursion, 0))
	return c
}

plot_dark_course :: proc(
	d: ^Dark_Continuum,
	navigation: ^Dark_Expedition_Navigation,
	course: Dark_Course,
) -> (
	Dark_Course_Forecast,
	bool,
) {
	candidate := course
	forecast := dark_course_forecast(d, &candidate); if !forecast.valid do return forecast, false
	if dark_metric_distance(d.seed, navigation.position, course.waypoints[0].position) > .05 do return forecast, false
	navigation.course =
		candidate; navigation.forecast = forecast; navigation.segment = 0; navigation.segment_progress = 0; navigation.autopilot_active = true; navigation.paused_for_replan = false; navigation.manual_active = false; navigation.manual_velocity = {}
	return forecast, true
}

dark_navigation_resolve_candidate :: proc(
	d: ^Dark_Continuum,
	prior, ideal: Dark_Vec4,
) -> (
	candidate: Dark_Vec4,
	blocked: bool,
) {
	candidate = ideal
	for organism in d.organisms[:d.organism_count] {
		if !organism.alive do continue
		clearance :=
			dark_metric_distance(d.seed, candidate, organism.position) -
			organism.radius; if clearance >= .18 do continue
		away := dark_vec4_sub(candidate, organism.position); length := dark_vec4_length(away)
		if length <=
		   1e-9 {axis := int((organism.id ~ d.simulation_tick) % 4); away[axis] = 1; length = 1}
		correction := min(
			.18 - clearance,
			.12,
		); candidate = dark_vec4_add(candidate, dark_vec4_scale(away, correction / length))
	}
	if dark_metric_distance(d.seed, ideal, candidate) > .13 do return candidate, true
	for organism in d.organisms[:d.organism_count] {
		if !organism.alive do continue
		candidate_clearance :=
			dark_metric_distance(d.seed, candidate, organism.position) -
			organism.radius; if candidate_clearance >= .18 do continue
		prior_clearance := dark_metric_distance(d.seed, prior, organism.position) - organism.radius
		if candidate_clearance <= prior_clearance + .001 do return candidate, true
	}
	return candidate, false
}

advance_dark_navigation_fixed :: proc(
	d: ^Dark_Continuum,
	navigation: ^Dark_Expedition_Navigation,
) {
	_ = dark_ensure_chunk_loaded(d, dark_chunk_coord_at(navigation.position))
	navigation.tracker = dark_tracker_scan(d, navigation.position, 8)
	if navigation.manual_active {
		ideal := dark_vec4_add(
			navigation.position,
			dark_vec4_scale(navigation.manual_velocity, DARK_FIXED_STEP),
		); candidate, blocked := dark_navigation_resolve_candidate(d, navigation.position, ideal)
		if blocked {navigation.manual_active = false; navigation.manual_velocity = {}; navigation.paused_for_replan = true; return}
		navigation.position = candidate; return
	}
	if !navigation.autopilot_active || navigation.paused_for_replan || navigation.course.waypoint_count < 2 do return
	if navigation.segment >=
	   navigation.course.waypoint_count - 1 {navigation.autopilot_active = false; return}
	a :=
		navigation.course.waypoints[navigation.segment].position; b := navigation.course.waypoints[navigation.segment + 1].position
	segment_distance := dark_metric_distance(
		d.seed,
		a,
		b,
	); if segment_distance <= 1e-9 {navigation.position = b; navigation.segment += 1; navigation.segment_progress = 0; return}
	prior_progress := navigation.segment_progress
	navigation.segment_progress += max(navigation.speed, .1) * DARK_FIXED_STEP / segment_distance
	arrived := navigation.segment_progress >= 1
	ideal := b
	if !arrived do for axis in 0 ..< 4 do ideal[axis] = a[axis] + (b[axis] - a[axis]) * navigation.segment_progress
	candidate, blocked := dark_navigation_resolve_candidate(d, navigation.position, ideal)
	if blocked {
		navigation.segment_progress = prior_progress
		navigation.paused_for_replan = true
		navigation.autopilot_active = false
		return
	}
	navigation.position = candidate
	if arrived {navigation.position = b; navigation.segment += 1; navigation.segment_progress = 0; if navigation.segment >= navigation.course.waypoint_count - 1 do navigation.autopilot_active = false}
}

advance_dark_expedition :: proc(
	d: ^Dark_Continuum,
	navigation: ^Dark_Expedition_Navigation,
	elapsed: f64,
) {
	if d.paused || elapsed <= 0 do return
	navigation.accumulator = min(navigation.accumulator + elapsed, 2)
	for navigation.accumulator + 1e-9 >=
	    DARK_FIXED_STEP {advance_dark_navigation_fixed(d, navigation); navigation.accumulator -= DARK_FIXED_STEP}
}

simulate_dark_expedition :: proc(
	d: ^Dark_Continuum,
	navigation: ^Dark_Expedition_Navigation,
) -> bool {
	if !navigation.autopilot_active || navigation.paused_for_replan do return false
	for navigation.autopilot_active && !navigation.paused_for_replan {
		advance_dark_continuum_fixed(d)
		advance_dark_navigation_fixed(d, navigation)
	}
	d.accumulator = 0
	navigation.accumulator = 0
	return !navigation.paused_for_replan
}

dark_manifestation_conditions_at :: proc(
	d: ^Dark_Continuum,
	observer: Dark_Vec4,
	isolation_strength: f64 = .5,
) -> Dark_Manifestation_Conditions {
	law, weather := dark_environment_at(d, observer)
	wake := f64(0)
	if field_at := dark_nearest_field(d, observer); field_at >= 0 do wake = d.fields[field_at].wake_energy
	return {
		observer_correspondence_w = observer[3],
		correspondence_width = clamp(
			1.15 - dark_depth_from_anchor(d.seed, d.anchor_position, observer) * .06,
			.18,
			1,
		),
		isolation_strength = clamp(isolation_strength, 0, 1),
		curvature = math.abs(dark_metric_factor(d.seed, observer) - 1),
		wake = wake,
		law = law,
		weather = weather,
	}
}

dark_tracker_scan :: proc(
	d: ^Dark_Continuum,
	observer: Dark_Vec4,
	sensor_range: f64,
	isolation_strength: f64 = .5,
) -> Dark_Tracker {
	t: Dark_Tracker
	conditions := dark_manifestation_conditions_at(d, observer, isolation_strength)
	for &organism in d.organisms[:d.organism_count] {if !dark_organism_remains_present(d, &organism) || t.track_count >= MAX_DARK_TRACKS do continue; relative := dark_vec4_sub(organism.position, observer); distance := dark_metric_distance(d.seed, observer, organism.position); if distance > sensor_range do continue; manifestation := dark_manifestation_for(&organism, conditions); if !manifestation.manifested do continue; confidence := clamp((1 - distance / max(sensor_range, .001)) * manifestation.confidence, .08, 1); t.tracks[t.track_count] = {
			organism_id      = organism.id,
			role             = organism.role,
			relative_bearing = relative,
			velocity         = organism.velocity,
			distance         = distance,
			estimated_extent = organism.radius,
			energy_band      = math.floor(organism.energy * 4) / 4,
			condition_band   = math.floor(organism.condition * 4) / 4,
			injury           = organism.injury,
			preferred_depth  = organism.mobility.preferred_depth,
			behavior         = organism.behavior,
			target_id        = organism.target_id,
			confidence       = confidence,
		}
		track := &t.tracks[t.track_count]
		forecast_add_factor(&track.factors, &track.factor_count, "range", 1 - distance / max(sensor_range, .001), 1, .Observed)
		forecast_add_factor(&track.factors, &track.factor_count, "manifestation stability", manifestation.confidence, manifestation.confidence, .Inferred)
		if confidence < .75 do forecast_add_factor(&track.factors, &track.factor_count, "unresolved signal", 0, 1 - confidence, .Unknown)
		t.track_count += 1}
	return t
}

dark_tracker_contains :: proc(t: ^Dark_Tracker, organism_id: u64) -> bool {
	for track in t.tracks[:t.track_count] do if track.organism_id == organism_id do return true
	return false
}

dark_cross_door :: proc(
	d: ^Dark_Continuum,
	door_id: u64,
	position: Dark_Vec4,
) -> (
	galaxy_neighborhood: int,
	ok: bool,
) {
	for &door in d.doors[:d.door_count] {if door.id != door_id do continue; if door.access <= 0 || dark_metric_distance(d.seed, position, door.position) > door.radius do return -1, false; door.traffic += 1; field := dark_nearest_field(d, door.position); if field >= 0 do d.fields[field].wake_energy = clamp(d.fields[field].wake_energy + .18, 0, 1); return door.galaxy_neighborhood, true}
	return -1, false
}

dark_door_at_position :: proc(d: ^Dark_Continuum, position: Dark_Vec4) -> int {
	for door, i in d.doors[:d.door_count] do if dark_metric_distance(d.seed, position, door.position) <= door.radius do return i
	return -1
}
