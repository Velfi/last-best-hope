package game

import "core:fmt"
import "core:math"

Passage_Depth_Forecast :: struct {
	current_depth, peak_depth, safe_limit, emergency_limit: f64,
	safe_margin, emergency_margin:                         f64,
	valid:                                                  bool,
}

passage_field_depth_rating :: proc(p: ^Passage) -> f64 {
	if p.field_depth_rating > 0 do return p.field_depth_rating
	return STANDARD_FIELD_DEPTH_RATING
}

passage_emergency_depth_limit :: proc(p: ^Passage) -> f64 {
	if p.emergency_depth_limit > 0 do return p.emergency_depth_limit
	return EMERGENCY_FIELD_DEPTH_LIMIT
}

passage_depth_forecast :: proc(c: ^Campaign, p: ^Passage, course: ^Dark_Course) -> Passage_Depth_Forecast {
	r := Passage_Depth_Forecast{safe_limit = passage_field_depth_rating(p), emergency_limit = passage_emergency_depth_limit(p)}
	if !p.active || p.domain != .Dark || course.waypoint_count < 2 do return r
	d := &c.outer_dark.continuum
	r.current_depth = dark_depth_from_anchor(d.seed, d.anchor_position, p.dark_navigation.position)
	r.peak_depth = r.current_depth
	depth_samples := [3]f64{0, 0.5, 1}
	for i in 1 ..< course.waypoint_count {
		a, b := course.waypoints[i - 1].position, course.waypoints[i].position
		for fraction in depth_samples {
			depth := dark_depth_from_anchor(d.seed, d.anchor_position, dark_vec4_lerp(a, b, fraction))
			r.peak_depth = max(r.peak_depth, depth)
		}
	}
	r.safe_margin = r.safe_limit - r.peak_depth
	r.emergency_margin = r.emergency_limit - r.peak_depth
	r.valid = true
	return r
}

passage_correspondence_reach_name :: proc(c: ^Campaign, door: ^Dark_Door) -> string {
	depth := dark_depth_from_anchor(c.outer_dark.continuum.seed, c.outer_dark.continuum.anchor_position, door.position)
	if depth < 1.5 do return "LOCAL REACH"
	if depth < 4 do return "REGIONAL REACH"
	if depth < 6.5 do return "DISTANT REACH"
	return "EXTREME REACH"
}

passage_course_requires_emergency :: proc(c: ^Campaign, p: ^Passage, course: ^Dark_Course) -> bool {
	forecast := passage_depth_forecast(c, p, course)
	// A course that is already beyond the stable band may always descend toward
	// the anchor; only a new deeper commitment needs explicit authority.
	return forecast.valid && forecast.peak_depth > forecast.safe_limit + 1e-6 && forecast.peak_depth > forecast.current_depth + 1e-6
}

passage_course_within_depth_envelope :: proc(c: ^Campaign, p: ^Passage, course: ^Dark_Course) -> bool {
	forecast := passage_depth_forecast(c, p, course)
	return forecast.valid && forecast.peak_depth <= forecast.emergency_limit + 1e-6
}

authorize_passage_emergency_descent :: proc(c: ^Campaign, p: ^Passage, course: ^Dark_Course) -> (bool, string) {
	if !passage_course_requires_emergency(c, p, course) do return false, "This course remains within the stable field-depth rating."
	if !passage_course_within_depth_envelope(c, p, course) do return false, "This course exceeds the expedition's emergency field-depth limit."
	endpoint := course.waypoints[course.waypoint_count - 1].position
	door_at := dark_door_at_position(&c.outer_dark.continuum, endpoint)
	if door_at < 0 || dark_door_detection_confidence(&c.outer_dark.continuum, p.dark_navigation.position, &c.outer_dark.continuum.doors[door_at]) <= 0 do return false, "Emergency descent must end at a detected correspondence."
	p.emergency_target_door_id = c.outer_dark.continuum.doors[door_at].id
	p.emergency_depth_committed = true
	record_event(c, .Situation_Decided, "The expedition accepted an unstable field-depth descent toward a detected correspondence; return may require a relay.", p.ships[0], institution_id = p.contract.sponsor)
	return true, "Emergency depth commitment recorded. Cross the correspondence or preserve a recoverable missing-voyage record."
}

plot_passage_course :: proc(
	c: ^Campaign,
	p: ^Passage,
	course: Dark_Course,
) -> (
	Dark_Course_Forecast,
	bool,
	) {
	course_copy := course
	if !p.active || p.domain != .Dark || !passage_course_within_depth_envelope(c, p, &course_copy) do return {}, false
	if passage_course_requires_emergency(c, p, &course_copy) {
		endpoint := course_copy.waypoints[course_copy.waypoint_count - 1].position
		door_at := dark_door_at_position(&c.outer_dark.continuum, endpoint)
		if p.emergency_target_door_id == 0 || door_at < 0 || c.outer_dark.continuum.doors[door_at].id != p.emergency_target_door_id do return {}, false
	}
	current_depth := dark_depth_from_anchor(c.outer_dark.continuum.seed, c.outer_dark.continuum.anchor_position, p.dark_navigation.position)
	if p.emergency_target_door_id != 0 && current_depth > passage_field_depth_rating(p) {
		endpoint := course_copy.waypoints[course_copy.waypoint_count - 1].position
		if dark_depth_from_anchor(c.outer_dark.continuum.seed, c.outer_dark.continuum.anchor_position, endpoint) > passage_field_depth_rating(p) do return {}, false
	}
	f, ok := plot_dark_course(
		&c.outer_dark.continuum,
		&p.dark_navigation,
		course,
	)
	if ok {p.phase = .Underway; p.pause_reason = .None; p.safe_endpoint = .None}
	return f, ok}

passage_dark_course_forecast :: proc(
	c: ^Campaign,
	p: ^Passage,
	course: ^Dark_Course,
) -> Dark_Course_Forecast {
	r := dark_course_forecast(&c.outer_dark.continuum, course)
	profile := dark_sensor_profile(p.dark_navigation.sensor_posture)
	forecast_add_factor(
		&r.factors,
		&r.factor_count,
		fmt.tprintf(
			"%s sensor posture",
			dark_sensor_posture_name(p.dark_navigation.sensor_posture),
		),
		-profile.coherence_rate * 100,
		1,
		.Observed,
		p.ship_count > 0 ? p.ships[0] : 0,
		p.dark_navigation.sensor_posture_event,
	)
	sensor_damage: i32
	source_ship: Ship_ID
	for ship_id in p.ships[:p.ship_count] do if at := ship_index(c, ship_id); at >= 0 && c.ships[at].impairments.sensors > 0 {
		sensor_damage += c.ships[at].impairments.sensors
		if source_ship == 0 do source_ship = ship_id
	}
	if sensor_damage > 0 do forecast_add_factor(&r.factors, &r.factor_count, "damaged survey capability", -f64(sensor_damage), 1, .Observed, source_ship, latest_ship_event(c, source_ship))
	if p.dark_navigation.forecast.valid {
		delta := r.coherence_cost - p.dark_navigation.forecast.coherence_cost
		if abs(delta) > .0001 do forecast_add_factor(&r.factors, &r.factor_count, "change since held forecast", -delta, 1, .Observed, p.ship_count > 0 ? p.ships[0] : 0, p.dark_navigation.sensor_posture_event)
	}
	return r
}

set_passage_manual_helm :: proc(c: ^Campaign, p: ^Passage, direction: Dark_Vec4) -> bool {
	if !p.active || p.domain != .Dark do return false
	n := &p.dark_navigation; length := dark_vec4_length(direction)
	if length <= .001 {
		n.manual_active = false; n.manual_velocity = {}
		if p.phase == .Underway &&
		   !n.autopilot_active {p.phase = .Awaiting_Leg; p.pause_reason = .None}
		return true
	}
	n.manual_velocity = dark_vec4_scale(
		direction,
		max(n.speed, .1) / length,
	)
	probe := Dark_Course{waypoint_count = 2}; probe.waypoints[0].position = n.position; probe.waypoints[1].position = dark_vec4_add(n.position, dark_vec4_scale(n.manual_velocity, DARK_FIXED_STEP))
	current_depth := dark_depth_from_anchor(c.outer_dark.continuum.seed, c.outer_dark.continuum.anchor_position, n.position)
	if p.emergency_target_door_id != 0 && current_depth > passage_field_depth_rating(p) do return false
	if !passage_course_within_depth_envelope(c, p, &probe) || passage_course_requires_emergency(c, p, &probe) do return false
	n.manual_active = true; n.autopilot_active = false; n.paused_for_replan = false
	p.phase = .Underway; p.pause_reason = .None; p.safe_endpoint = .None
	return true
}

passage_contact_avoidance_course :: proc(
	c: ^Campaign,
	p: ^Passage,
	organism_id: u64,
) -> (
	Dark_Course,
	bool,
) {
	if !p.active || p.domain != .Dark || organism_id == 0 do return {}, false
	n := &p.dark_navigation
	if n.course.waypoint_count < 2 || n.segment >= n.course.waypoint_count - 1 do return {}, false
	track_at := -1
	for track, i in n.tracker.tracks[:n.tracker.track_count] do if track.organism_id == organism_id {track_at = i; break}
	if track_at < 0 do return {}, false
	start := n.position; destination := n.course.waypoints[n.course.waypoint_count - 1].position
	direct := dark_vec4_normalized(dark_vec4_sub(destination, start))
	if dark_vec4_length(direct) < 1e-9 do return {}, false
	track := n.tracker.tracks[track_at]
	away := dark_vec4_scale(dark_vec4_normalized(track.relative_bearing), -1)
	lateral := dark_vec4_sub(away, dark_vec4_scale(direct, dark_vec4_dot(away, direct)))
	if dark_vec4_length(lateral) < .05 {
		axis := int(organism_id % 4); basis: Dark_Vec4; basis[axis] = 1
		lateral = dark_vec4_sub(basis, dark_vec4_scale(direct, dark_vec4_dot(basis, direct)))
		if dark_vec4_length(lateral) <
		   .05 {axis = (axis + 1) % 4; basis = {}; basis[axis] = 1; lateral = dark_vec4_sub(basis, dark_vec4_scale(direct, dark_vec4_dot(basis, direct)))}
	}
	lateral = dark_vec4_normalized(lateral)
	if dark_vec4_length(lateral) < 1e-9 do return {}, false
	clearance := clamp(track.estimated_extent + 1.2, 1.5, 3.0)
	course := Dark_Course {
		waypoint_count = 3,
	}
	course.waypoints[0].position = start
	course.waypoints[1].position = dark_vec4_add(
		dark_vec4_lerp(start, destination, .5),
		dark_vec4_scale(lateral, clearance),
	)
	course.waypoints[2].position = destination
	forecast := dark_course_forecast(&c.outer_dark.continuum, &course)
	return course, forecast.valid
}

Dark_Track_Threat_Level :: enum {
	Clear,
	Watch,
	Hold,
}

Dark_Track_Threat :: struct {
	level:                                      Dark_Track_Threat_Level,
	hold_distance, warning_distance, clearance: f64,
	closing:                                    bool,
}

dark_track_threat :: proc(track: ^Dark_Track) -> Dark_Track_Threat {
	result: Dark_Track_Threat
	if track == nil do return result
	#partial switch track.role {
	case .Shear_Hunter:
		result.hold_distance = 2.5; result.warning_distance = 3.2
	case .Grave_Reef:
		result.hold_distance = track.estimated_extent + 1
		result.warning_distance = track.estimated_extent + 1.7
	case:
		return result
	}
	result.clearance = track.distance - result.hold_distance
	result.closing = dark_vec4_dot(track.relative_bearing, track.velocity) < 0
	if track.distance <=
	   result.hold_distance {result.level = .Hold} else if track.distance <= result.warning_distance || track.role == .Shear_Hunter && track.behavior == .Hunting {result.level = .Watch}
	return result
}

dark_contact_pause_required :: proc(
	p: ^Passage,
	tracker: ^Dark_Tracker,
	contact_danger: bool = false,
) -> bool {
	dangerous := false; cleared_contact_nearby := false
	for &track in tracker.tracks[:tracker.track_count] {
		if track.organism_id == p.cleared_contact_id &&
		   track.distance < 3.2 {cleared_contact_nearby = true; continue}
		if dark_track_requires_response(&track) do dangerous = true
	}
	if contact_danger && !cleared_contact_nearby do dangerous = true
	if p.cleared_contact_id != 0 && !cleared_contact_nearby do p.cleared_contact_id = 0
	return dangerous
}

dark_track_requires_response :: proc(track: ^Dark_Track) -> bool {
	return dark_track_threat(track).level == .Hold
}

passage_shear_evasion_learners :: proc(c: ^Campaign, p: ^Passage) -> (result: int) {
	for ship_id in p.ships[:p.ship_count] do if at := ship_index(c, ship_id); at >= 0 && c.ships[at].active && c.ships[at].dark_contact_procedure != .Field_Quarantine && c.ships[at].dark_contact_procedure != .Shear_Evasion do result += 1
	return
}

respond_to_dark_contact :: proc(
	c: ^Campaign,
	p: ^Passage,
	accept_contact: bool,
	organism_id: u64 = 0,
) -> (
	bool,
	string,
) {
	if !p.active || p.domain != .Dark || p.phase != .Awaiting_Leg || p.pause_reason != .Dangerous_Contact do return false, "No dangerous contact is awaiting a command decision."
	track_at := -1
	for track, i in p.dark_navigation.tracker.tracks[:p.dark_navigation.tracker.track_count] do if track.organism_id == organism_id {track_at = i; break}
	if track_at < 0 || !dark_track_requires_response(&p.dark_navigation.tracker.tracks[track_at]) do return false, "Select the hunter or reef that triggered the course hold."
	track :=
		p.dark_navigation.tracker.tracks[track_at]; contact_name := dark_organism_name(track.organism_id, track.role)
	avoidance: Dark_Course
	if !accept_contact {ok: bool; avoidance, ok = passage_contact_avoidance_course(c, p, organism_id); if !ok do return false, "No evasive course can preserve the held destination."}
	if !accept_contact {
		p.cleared_contact_id = organism_id
		if _, ok := plot_passage_course(c, p, avoidance);
		   !ok {p.cleared_contact_id = 0; return false, "The evasive course could not be plotted."}
		learned := 0
		if track.role == .Shear_Hunter {
			for ship_id in p.ships[:p.ship_count] do if at := ship_index(c, ship_id); at >= 0 && c.ships[at].active && c.ships[at].dark_contact_procedure != .Field_Quarantine && c.ships[at].dark_contact_procedure != .Shear_Evasion {
				c.ships[at].dark_contact_procedure = .Shear_Evasion; learned += 1
				add_ship_history(c, ship_id, fmt.tprintf("Learned Shear-evasion procedure while opening distance from %s.", contact_name))
			}
		}
		if learned >
		   0 {record_event(c, .Situation_Decided, fmt.tprintf("The expedition opened distance from %s; %d ship%s adopted Shear-evasion procedure.", contact_name, learned, learned == 1 ? "" : "s"), p.ships[0], institution_id = p.contract.sponsor)} else {record_event(c, .Situation_Decided, fmt.tprintf("The expedition opened distance from %s and resumed toward its held destination.", contact_name), p.ships[0], institution_id = p.contract.sponsor)}
		if learned > 0 do return true, fmt.tprintf("Evasive course underway. %d ship%s learned Shear-evasion procedure.", learned, learned == 1 ? "" : "s")
		return true,
			"The expedition opened distance from the contact and resumed toward the held destination."
	}
	n := &p.dark_navigation
	if n.course.waypoint_count < 2 || n.segment >= n.course.waypoint_count - 1 do return false, "No held course remains beyond the contact."
	p.cleared_contact_id = organism_id
	n.autopilot_active =
		true; n.paused_for_replan = false; p.phase = .Underway; p.pause_reason = .None
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The expedition resumed its held course inside the contact range of %s.",
			contact_name,
		),
		p.ships[0],
		institution_id = p.contract.sponsor,
	)
	return true, "The expedition accepted contact risk and resumed the held course."
}

passage_coherence_limit :: proc(p: ^Passage) -> f64 {
	return(
		p.strategy.withdrawal == .Conservative ? .7 : p.strategy.withdrawal == .Mission_First ? 1.4 : 1.0 \
	)
}

Passage_Coherence_Forecast :: struct {
	current, added, projected, limit: f64,
	crosses_limit:                    bool,
}

Passage_Course_Time_Forecast :: struct {
	ship_days, membrane_days: f64,
}

passage_course_segment_steps :: proc(distance, speed: f64) -> i64 {
	// Autopilot resolves one segment per fixed tick sequence and snaps to the
	// waypoint on its final tick. Forecasts must reserve that final tick too.
	return max(i64(math.ceil(distance / max(speed, .1) / DARK_FIXED_STEP)), 1)
}

passage_course_segment_dark_time :: proc(distance, speed: f64) -> f64 {
	return f64(passage_course_segment_steps(distance, speed)) * DARK_FIXED_STEP
}

// Passage timing is distinct from the geometry-only Dark forecast because
// expeditions can have different cruising speeds. This matches the fixed-step
// execution model: Dark time is distance divided by speed, and ship time is
// 0.72 of that duration.
passage_course_time_forecast :: proc(
	c: ^Campaign,
	p: ^Passage,
	course: ^Dark_Course,
) -> Passage_Course_Time_Forecast {
	r: Passage_Course_Time_Forecast
	if c == nil || p == nil || course == nil || course.waypoint_count < 2 do return r
	d := &c.outer_dark.continuum
	speed := max(p.dark_navigation.speed, .1)
	for i in 1 ..< course.waypoint_count {
		a, b := course.waypoints[i - 1].position, course.waypoints[i].position
		steps := passage_course_segment_steps(dark_metric_distance(d.seed, a, b), speed)
		ship_days := DARK_FIXED_STEP * .72
		for step in 1 ..= steps {
			point := dark_vec4_lerp(a, b, f64(step) / f64(steps))
			depth := dark_depth_from_anchor(d.seed, d.anchor_position, point)
			r.ship_days += ship_days
			r.membrane_days += dark_membrane_days_for_step(depth, ship_days)
		}
	}
	return r
}

passage_course_coherence_forecast :: proc(
	c: ^Campaign,
	p: ^Passage,
	course: ^Dark_Course,
) -> Passage_Coherence_Forecast {
	r := Passage_Coherence_Forecast {
		current = p.coherence_exposure,
		limit   = passage_coherence_limit(p),
	}
	if course.waypoint_count < 2 do return r
	d := &c.outer_dark.continuum; field_scars, symbionts := i32(0), i32(0)
	for ship_id in p.ships[:p.ship_count] do if at := ship_index(c, ship_id); at >= 0 {field_scars += c.ships[at].dark_field_scars; if c.ships[at].dark_symbiont_id != 0 do symbionts += 1}
	ship_count := f64(max(p.ship_count, 1)); speed := max(p.dark_navigation.speed, .1)
	sensor_profile := dark_sensor_profile(p.dark_navigation.sensor_posture)
	for i in 1 ..< course.waypoint_count {a, b := course.waypoints[i - 1].position, course.waypoints[i].position; steps := passage_course_segment_steps(dark_metric_distance(d.seed, a, b), speed); for step in 1 ..= steps {point := dark_vec4_lerp(a, b, f64(step) / f64(steps)); depth := dark_depth_from_anchor(d.seed, d.anchor_position, point); law, _ := dark_environment_at(d, point); r.added += (depth * .012 + law * .018 + f64(field_scars) / ship_count * .0015 + f64(symbionts) / ship_count * .002 + sensor_profile.coherence_rate) * DARK_FIXED_STEP}}
	r.projected = r.current + r.added; r.crosses_limit = r.projected >= r.limit
	return r
}

Passage_Coherence_Recovery_Preview :: struct {
	ship_days, target_exposure, held_added, held_projected, limit: f64,
	can_resume, crosses_limit:                                     bool,
}

passage_remaining_course :: proc(p: ^Passage) -> (Dark_Course, bool) {
	n := &p.dark_navigation
	if n.course.waypoint_count < 2 || n.segment >= n.course.waypoint_count - 1 do return {}, false
	result := Dark_Course {
		waypoint_count = 1 + n.course.waypoint_count - (n.segment + 1),
	}
	result.waypoints[0].position = n.position
	for old in n.segment + 1 ..< n.course.waypoint_count do result.waypoints[old - n.segment].position = n.course.waypoints[old].position
	return result, true
}

passage_coherence_recovery_preview :: proc(
	c: ^Campaign,
	p: ^Passage,
	full: bool,
) -> Passage_Coherence_Recovery_Preview {
	extra := f64(max(p.ship_count - 1, 0)); r := Passage_Coherence_Recovery_Preview {
		limit = passage_coherence_limit(p),
	}
	if full {r.ship_days = .75 + extra * .08; r.target_exposure = r.limit * .45; return r}
	r.ship_days = .28 + extra * .04; r.target_exposure = r.limit * .72
	if course, ok := passage_remaining_course(p);
	   ok {forecast := passage_course_coherence_forecast(c, p, &course); r.can_resume = true; r.held_added = forecast.added; r.held_projected = r.target_exposure + r.held_added; r.crosses_limit = r.held_projected >= r.limit}
	return r
}

stabilize_passage_coherence :: proc(
	c: ^Campaign,
	p: ^Passage,
	full: bool = true,
) -> (
	bool,
	string,
) {
	if !p.active || p.domain != .Dark || p.phase != .Awaiting_Leg || p.pause_reason != .Coherence_Limit do return false, "No coherence incident is awaiting stabilization."
	preview := passage_coherence_recovery_preview(c, p, full)
	if !full && (!preview.can_resume || preview.crosses_limit) do return false, "The held course exceeds the buffer available after a field patch."
	depth := dark_depth_from_anchor(
		c.outer_dark.continuum.seed,
		c.outer_dark.continuum.anchor_position,
		p.dark_navigation.position,
	)
	p.elapsed_days +=
		preview.ship_days; p.membrane_elapsed_days += dark_membrane_days_for_step(depth, preview.ship_days); p.course_cost += (full ? .15 : .08) * f64(max(p.ship_count, 1)); p.coherence_exposure = preview.target_exposure
	p.pause_reason = .None; p.dark_navigation.paused_for_replan = false
	if full {
		p.dark_navigation.autopilot_active = false
		record_event(
			c,
			.Situation_Decided,
			fmt.tprintf(
				"The expedition held position for %.2f ship-days to fully stabilize its field.",
				preview.ship_days,
			),
			p.ships[0],
			institution_id = p.contract.sponsor,
		)
		return true, "Field coherence restored. Plot a new course."
	}
	p.phase = .Underway; p.dark_navigation.autopilot_active = true; p.dark_navigation.manual_active = false; p.dark_navigation.manual_velocity = {}
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The expedition patched its field in %.2f ship-days and resumed the held course.",
			preview.ship_days,
		),
		p.ships[0],
		institution_id = p.contract.sponsor,
	)
	return true, "Field patch holding. The expedition resumed its held course."
}

Passage_Obstruction_Response_Preview :: struct {
	detour_distance,
	detour_added,
	detour_coherence,
	wait_ship_days,
	wait_coherence,
	wait_projected,
	limit: f64,
	can_detour,
	can_wait,
	has_held_course:                                                                  bool,
}

passage_material_detour_course :: proc(c: ^Campaign, p: ^Passage) -> (Dark_Course, bool) {
	remaining, ok := passage_remaining_course(p); if !ok do return {}, false
	start :=
		remaining.waypoints[0].position; destination := remaining.waypoints[remaining.waypoint_count - 1].position; direct := dark_vec4_normalized(dark_vec4_sub(destination, start)); if dark_vec4_length(direct) < 1e-9 do return {}, false
	salt :=
		p.id ~
		c.outer_dark.continuum.simulation_tick; axis := int(salt % 4); basis: Dark_Vec4; basis[axis] = (salt >> 2) & 1 == 0 ? 1 : -1
	lateral := dark_vec4_sub(basis, dark_vec4_scale(direct, dark_vec4_dot(basis, direct)))
	if dark_vec4_length(lateral) <
	   .05 {axis = (axis + 1) % 4; basis = {}; basis[axis] = 1; lateral = dark_vec4_sub(basis, dark_vec4_scale(direct, dark_vec4_dot(basis, direct)))}
	lateral = dark_vec4_normalized(
		lateral,
	); if dark_vec4_length(lateral) < 1e-9 do return {}, false
	course := Dark_Course {
		waypoint_count = 3,
	}; course.waypoints[0].position =
		start; course.waypoints[1].position = dark_vec4_add(dark_vec4_lerp(start, destination, .5), dark_vec4_scale(lateral, 1.5)); course.waypoints[2].position = destination
	return course, dark_course_forecast(&c.outer_dark.continuum, &course).valid
}

passage_obstruction_response_preview :: proc(
	c: ^Campaign,
	p: ^Passage,
) -> Passage_Obstruction_Response_Preview {
	r := Passage_Obstruction_Response_Preview {
		limit          = passage_coherence_limit(p),
		wait_ship_days = .35 + f64(max(p.ship_count - 1, 0)) * .04,
	}
	if detour, ok := passage_material_detour_course(c, p);
	   ok {detour_forecast := dark_course_forecast(&c.outer_dark.continuum, &detour); direct := Dark_Course {
			waypoint_count = 2,
		}; direct.waypoints[0] =
			detour.waypoints[0]; direct.waypoints[1] = detour.waypoints[2]; held := dark_course_forecast(&c.outer_dark.continuum, &direct); coherence := passage_course_coherence_forecast(c, p, &detour); r.can_detour = true; r.detour_distance = detour_forecast.distance; r.detour_added = max(detour_forecast.distance - held.distance, 0); r.detour_coherence = coherence.projected}
	d := &c.outer_dark.continuum; depth := dark_depth_from_anchor(d.seed, d.anchor_position, p.dark_navigation.position); law, _ := dark_environment_at(d, p.dark_navigation.position); field_scars, symbionts := i32(0), i32(0); for ship_id in p.ships[:p.ship_count] do if at := ship_index(c, ship_id); at >= 0 {field_scars += c.ships[at].dark_field_scars; if c.ships[at].dark_symbiont_id != 0 do symbionts += 1}; ships := f64(max(p.ship_count, 1)); dark_time := r.wait_ship_days / .72; r.wait_coherence = (depth * .012 + law * .018 + f64(field_scars) / ships * .0015 + f64(symbionts) / ships * .002) * dark_time; r.wait_projected = p.coherence_exposure + r.wait_coherence
	_, r.has_held_course = passage_remaining_course(p); r.can_wait = r.wait_projected < r.limit
	return r
}

respond_to_material_obstruction :: proc(
	c: ^Campaign,
	p: ^Passage,
	wait_for_drift: bool,
) -> (
	bool,
	string,
) {
	if !p.active || p.domain != .Dark || p.phase != .Awaiting_Leg || p.pause_reason != .Material_Obstruction do return false, "No material obstruction is holding the course."
	preview := passage_obstruction_response_preview(c, p)
	if !wait_for_drift {
		if !preview.can_detour do return false, "No destination-preserving detour is available."
		course, _ := passage_material_detour_course(
			c,
			p,
		); if _, ok := plot_passage_course(c, p, course); !ok do return false, "The detour could not be plotted."
		record_event(
			c,
			.Situation_Decided,
			fmt.tprintf(
				"The expedition added %.2f range to detour around a material obstruction.",
				preview.detour_added,
			),
			p.ships[0],
			institution_id = p.contract.sponsor,
		)
		return true, "Detour plotted. The expedition resumed toward the held destination."
	}
	if !preview.can_wait do return false, "Waiting would exceed the available coherence buffer."
	d := &c.outer_dark.continuum; depth := dark_depth_from_anchor(d.seed, d.anchor_position, p.dark_navigation.position); _, weather := dark_environment_at(d, p.dark_navigation.position); dark_time := preview.wait_ship_days / .72
	p.elapsed_days +=
		preview.wait_ship_days; p.membrane_elapsed_days += dark_membrane_days_for_step(depth, preview.wait_ship_days); p.accumulated_depth += depth * preview.wait_ship_days; p.environment_exposure += weather * dark_time; p.coherence_exposure = preview.wait_projected; p.course_cost += .03 * f64(max(p.ship_count, 1))
	advance_dark_continuum(
		d,
		dark_time,
	); p.dark_navigation.tracker = dark_tracker_scan(d, p.dark_navigation.position, 8); p.dark_navigation.paused_for_replan = false; p.dark_navigation.autopilot_active = preview.has_held_course; p.phase = preview.has_held_course ? .Underway : .Awaiting_Leg; p.pause_reason = .None
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The expedition held position for %.2f ship-days to let a material obstruction drift.",
			preview.wait_ship_days,
		),
		p.ships[0],
		institution_id = p.contract.sponsor,
	)
	if !preview.has_held_course do return true, "The obstruction drifted. Plot a new course."
	return true, "The obstruction drifted. The expedition resumed its held course."
}

passage_has_ship_role :: proc(c: ^Campaign, p: ^Passage, role: Role) -> bool {
	for ship_id in p.ships[:p.ship_count] do if at := ship_index(c, ship_id); at >= 0 && c.ships[at].active && c.ships[at].role == role do return true
	return false
}

dark_documentation_confidence_required :: proc(c: ^Campaign, p: ^Passage) -> f64 {
	return passage_has_ship_role(c, p, .Survey) ? .25 : .6
}

document_dark_contact :: proc(c: ^Campaign, p: ^Passage, organism_id: u64) -> (bool, string) {
	if !p.active || p.domain != .Dark || p.contract.purpose != .Ecological_Survey do return false, "This undertaking has no ecological survey objective."
	track_at := -1; for track, i in p.dark_navigation.tracker.tracks[:p.dark_navigation.tracker.track_count] do if track.organism_id == organism_id {track_at = i; break}
	if track_at < 0 do return false, "The organism is no longer resolved by the expedition sensorium."
	track := p.dark_navigation.tracker.tracks[track_at]; role_bit := u32(1) << u32(track.role)
	if p.observed_ecology_roles & role_bit != 0 do return false, "This ecological role is already secured in the expedition record."
	required_confidence := dark_documentation_confidence_required(c, p)
	if track.confidence < required_confidence do return false, fmt.tprintf("Close to %.0f%% confidence before committing the survey record.", required_confidence * 100)
	depth := dark_depth_from_anchor(
		c.outer_dark.continuum.seed,
		c.outer_dark.continuum.anchor_position,
		p.dark_navigation.position,
	); ship_days := .25
	p.elapsed_days +=
		ship_days; p.membrane_elapsed_days += dark_membrane_days_for_step(depth, ship_days); p.course_cost += .05; p.coherence_exposure += .04 + depth * .01; p.observed_ecology_roles |= role_bit; p.contract.evidence_count += 1
	for &observation in p.local_observations[:p.local_observation_count] do if observation.organism_id == organism_id {observation.confidence = max(observation.confidence, .9); break}
	p.dark_navigation.autopilot_active =
		false; p.dark_navigation.manual_active = false; p.phase = .Awaiting_Leg; p.pause_reason = .Contract_Evidence
	if p.observed_ecology_roles & p.contract.required_ecology_roles == p.contract.required_ecology_roles do p.contract.objective_met = true
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The expedition held course long enough to document %s as an ecological role.",
			dark_organism_name(track.organism_id, track.role),
		),
		p.ships[0],
		institution_id = p.contract.sponsor,
	)
	return true, "Ecological role secured. The interrupted course must be replotted."
}
passage_course_to_unknown_door :: proc(
	c: ^Campaign,
	p: ^Passage,
	depth: f64,
) -> (
	Dark_Course,
	bool,
) {i := dark_nearest_unknown_door(&c.outer_dark.continuum, p.dark_navigation.position); if i < 0 do return {}, false
	return passage_course_to_door(c, p, c.outer_dark.continuum.doors[i].id, depth)
}

passage_propellant_capacity :: proc(p: ^Passage) -> f64 {
	return f64(max(p.manifest.allocated.propellant, 0))
}

passage_propellant_remaining :: proc(p: ^Passage) -> f64 {
	return max(passage_propellant_capacity(p) - p.course_cost, 0)
}

passage_propellant_to_fleet_exit :: proc(c: ^Campaign, p: ^Passage) -> (f64, bool) {
	if !p.active || p.domain != .Dark do return 0, false
	route := passage_fastest_known_route(c, p, c.outer_dark.continuum.anchor_neighborhood)
	if !route.valid || route.exit_door_id == 0 do return 0, false
	for &door in c.outer_dark.continuum.doors[:c.outer_dark.continuum.door_count] do if door.id == route.exit_door_id {
		return dark_metric_distance(c.outer_dark.continuum.seed, p.dark_navigation.position, door.position), true
	}
	return 0, false
}

passage_return_reserve :: proc(c: ^Campaign, p: ^Passage) -> f64 {
	if cost, known := passage_propellant_to_fleet_exit(c, p); known do return cost
	return passage_propellant_capacity(p) * .5
}

passage_exploration_propellant_remaining :: proc(c: ^Campaign, p: ^Passage) -> f64 {
	return max(passage_propellant_remaining(p) - passage_return_reserve(c, p), 0)
}

auto_explore_return_reserve_required :: proc(c: ^Campaign, p: ^Passage) -> bool {
	course, found := passage_course_to_unknown_door(c, p, -1)
	if !found do return false
	return passage_course_requires_emergency(c, p, &course) || !passage_course_within_depth_envelope(c, p, &course)
}

order_systematic_dark_search :: proc(c: ^Campaign, p: ^Passage) -> (bool, string) {
	if !p.active || p.domain != .Dark || p.phase != .Awaiting_Leg do return false, "Auto explore requires a stationary expedition in the Dark."
	course, found := passage_course_to_unknown_door(c, p, -1)
	if !found do return false, "No unknown correspondence is currently detectable."
	if !passage_course_within_depth_envelope(c, p, &course) do return false, "The next search leg exceeds the emergency field-depth limit."
	if passage_course_requires_emergency(c, p, &course) && p.emergency_target_door_id == 0 do return false, "The next search leg enters an unstable depth band; authorize an emergency descent from its correspondence card."
	if _, ok := plot_passage_course(c, p, course); !ok do return false, "The next systematic search leg could not be plotted."
	p.systematic_search_active = true
	return true, "Auto explore underway. The expedition will stop before an uncommitted emergency descent."
}

cancel_systematic_dark_search :: proc(p: ^Passage) {
	p.systematic_search_active = false
}

passage_course_to_door :: proc(
	c: ^Campaign,
	p: ^Passage,
	door_id: u64,
	depth: f64 = -1,
) -> (
	Dark_Course,
	bool,
) {
	if !p.active || p.domain != .Dark do return {}, false
	door_at := -1
	for door, i in c.outer_dark.continuum.doors[:c.outer_dark.continuum.door_count] do if door.id == door_id {door_at = i; break}
	if door_at < 0 do return {}, false
	door := &c.outer_dark.continuum.doors[door_at]
	if dark_door_detection_confidence(&c.outer_dark.continuum, p.dark_navigation.position, door) <= 0 do return {}, false
	if depth >= 0 do return dark_course_to_door(p.dark_navigation.position, door, depth, c.outer_dark.continuum.anchor_position[3]), true
	base := p.strategy.depth == .Shallow ? .5 : p.strategy.depth == .Deep ? 4.0 : 1.8
	best := Dark_Course{}
	best_score := f64(1e30)
	candidate_depths := [3]f64{base, base * 1.45, max(base * .65, .2)}
	for candidate_depth in candidate_depths {
		candidate := dark_course_to_door(
			p.dark_navigation.position,
			door,
			candidate_depth,
			c.outer_dark.continuum.anchor_position[3],
		)
		forecast := dark_course_forecast(&c.outer_dark.continuum, &candidate)
		score := forecast.distance
		switch p.strategy.course {case .Best_Mapped:
			score =
				forecast.distance +
				(1 - forecast.topology_confidence) * 12; case .Lowest_Coherence:
			// This must use the expedition forecast rather than the generic
			// course load: field scars, symbionts, and the active sensor posture
			// all change the coherence the player will actually accumulate.
			score = passage_course_coherence_forecast(c, p, &candidate).projected
		case .Shortest_Metric:}
		if p.strategy.ecology == .Avoidant do score += forecast.ecological_interception * 8
		if score < best_score {best = candidate; best_score = score}
	}
	return best, best.waypoint_count > 0}
passage_record_discovery :: proc(p: ^Passage, d: ^Dark_Door, tick: u64) -> bool {for x in p.local_atlas[:p.local_atlas_count] do if x.door_id == d.id do return false
	if p.local_atlas_count >= MAX_LOCAL_DOOR_DISCOVERIES do return false
	p.local_atlas[p.local_atlas_count] = {
		door_id             = d.id,
		position_name_hash  = dark_door_position_name_hash(d.position),
		galaxy_neighborhood = d.galaxy_neighborhood,
		discovered_tick     = tick,
	}
	p.local_atlas_count += 1
	return true}
dark_endpoint_signals :: proc(
	c: ^Campaign,
	neighborhood: int,
) -> (
	resource, habitability: f64,
	ok: bool,
) {
	g := c.galaxy
	if neighborhood < 0 || neighborhood >= g.neighborhood_count do return 0, 0, false
	n := g.neighborhoods[neighborhood]
	resource = clamp(.35 + math.pow(10.0, n.metallicity_dex) * .3, .1, 1)
	habitability = n.planet_occurrence_probability * (n.in_galactic_habitable_zone ? 1.0 : .35)
	return resource, habitability, true
}
galaxy_neighborhood_position :: proc(c: ^Campaign, neighborhood: int) -> ([3]f64, bool) {
	g := c.galaxy
	if neighborhood < 0 || neighborhood >= g.neighborhood_count do return {}, false
	n := g.neighborhoods[neighborhood]
	return {n.x_kpc, n.y_kpc, n.z_kpc}, true
}
dark_relay_index :: proc(c: ^Campaign, id: u64) -> int {for relay, i in c.dark_relays[:c.dark_relay_count] do if relay.id == id do return i
	return -1}
dark_relay_at_neighborhood :: proc(c: ^Campaign, neighborhood: int) -> int {for relay, i in c.dark_relays[:c.dark_relay_count] do if relay.galaxy_neighborhood == neighborhood && relay.authenticated do return i
	return -1}
passage_contract_progress :: proc(c: ^Campaign, p: ^Passage) -> Dark_Contract_Progress {
	r := Dark_Contract_Progress {
		purpose                = p.contract.purpose,
		objective_met          = p.contract.objective_met,
		evidence_count         = p.contract.evidence_count,
		observed_ecology_roles = p.observed_ecology_roles,
		required_ecology_roles = p.contract.required_ecology_roles,
		current_neighborhood   = -1,
	}
	if p.domain == .Normal_Space {
		r.current_neighborhood = p.normal_course.start_neighborhood
		r.endpoint_resource, r.endpoint_habitability, _ = dark_endpoint_signals(
			c,
			r.current_neighborhood,
		)
		r.relay_available = dark_relay_at_neighborhood(c, r.current_neighborhood) >= 0
	}
	return r
}
service_passage_relay :: proc(c: ^Campaign, p: ^Passage) -> (u64, bool, string) {
	if !p.active || p.domain != .Normal_Space || p.phase == .Underway do return 0, false, "Relay work requires a stationary expedition in normal space."
	neighborhood := p.normal_course.start_neighborhood
	at := dark_relay_at_neighborhood(c, neighborhood)
	if at < 0 {
		at = c.dark_relay_count
		id := next_random(c)
		append(
			&c.dark_relays,
			Dark_Relay_Record {
				id = id,
				galaxy_neighborhood = neighborhood,
				condition = .65,
				authenticated = true,
				established_event = c.event_sequence + 1,
				last_service_event = c.event_sequence + 1,
				sponsor = p.contract.sponsor,
				semantic_tags = make_semantic_tags(
					.Entity,
					.Infrastructure,
					.Navigation,
					.Discovery,
				),
			},
		)
		c.dark_relay_count += 1
	} else {
		c.dark_relays[at].condition = min(c.dark_relays[at].condition + .25, 1)
		c.dark_relays[at].last_service_event = c.event_sequence + 1
	}
	relay := &c.dark_relays[at]
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The expedition authenticated relay %d at galaxy neighborhood %d.",
			relay.id,
			neighborhood,
		),
		p.ships[0],
		institution_id = p.contract.sponsor,
	)
	relay.last_service_event = c.event_sequence
	p.authenticated_relay_id = relay.id
	p.relay_advised = false
	dark_transmit_passage_knowledge(c, p, relay.id)
	p.contract.evidence_count += 1
	if p.contract.purpose == .Stabilize_Relay do p.contract.objective_met = true
	if p.contract.purpose == .Infrastructure_Run {
		resource, _, valid := dark_endpoint_signals(c, neighborhood)
		p.contract.objective_met = valid && resource >= p.contract.resource_threshold
	}
	p.pause_reason = .Contract_Evidence
	if p.contract.purpose == .Infrastructure_Run && !p.contract.objective_met do return relay.id, true, "The relay is authenticated, but this endpoint does not meet the resource threshold."
	return relay.id, true, "The relay is authenticated and the expedition record can be uploaded."
}

establish_arrival_communications :: proc(c: ^Campaign, p: ^Passage) {
	if !p.active || p.domain != .Normal_Space || p.phase == .Underway do return
	if p.normal_course.start_neighborhood == c.outer_dark.continuum.anchor_neighborhood do return
	_, _, _ = service_passage_relay(c, p)
}
cross_passage_door :: proc(c: ^Campaign, p: ^Passage) -> (bool, string) {if !p.active || p.domain != .Dark do return false, "The expedition is not at a Dark correspondence."
	i := dark_door_at_position(&c.outer_dark.continuum, p.dark_navigation.position)
	if i < 0 do return false, "No correspondence volume intersects the fleet."
	d := &c.outer_dark.continuum.doors[i]
	locally_known := false
	for discovery in p.local_atlas[:p.local_atlas_count] do if discovery.door_id == d.id {locally_known = true; break}
	unknown := !dark_fleet_door_known(c, d.id) && !locally_known
	endpoint, ok := dark_cross_door(&c.outer_dark.continuum, d.id, p.dark_navigation.position)
	if !ok do return false, "The correspondence is inaccessible."
	if unknown {_ = passage_record_discovery(p, d, c.outer_dark.continuum.simulation_tick)
		p.contract.evidence_count += 1
		if p.contract.purpose == .Map_Unknown_Door {
			resource, habitability, _ := dark_endpoint_signals(c, endpoint)
			resource_ok :=
				p.contract.resource_threshold <= 0 || resource >= p.contract.resource_threshold
			habitability_ok :=
				p.contract.habitability_threshold <= 0 ||
				habitability >= p.contract.habitability_threshold
			p.contract.objective_met = resource_ok && habitability_ok
		}}
	if p.contract.purpose == .Verify_Correspondence do p.contract.objective_met = true
	p.domain = .Normal_Space
	p.normal_course = {
		start_neighborhood       = endpoint,
		destination_neighborhood = endpoint,
		velocity_fraction_c      = .18,
	}
	p.normal_course.start_position, _ = galaxy_neighborhood_position(c, endpoint)
	p.normal_course.destination_position = p.normal_course.start_position
	p.normal_course.current_position = p.normal_course.start_position
	p.phase = .Awaiting_Leg
	p.pause_reason = unknown ? .Unknown_Door : .Course_Arrival
	habitable_reveal_passage_bubble(c, p, endpoint, d.id)
	establish_arrival_communications(c, p)
	p.pending_door_id = d.id
	distance, measured := galaxy_neighborhood_distance(
		c,
		c.outer_dark.continuum.anchor_neighborhood,
		endpoint,
	)
	if measured do return true, fmt.tprintf("Correspondence verified %.1f kpc from the fleet. Relay established.", distance)
	return true, "Correspondence verified. Relay established."}
