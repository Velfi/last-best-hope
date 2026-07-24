package game_tests

import "core:math"
import "core:testing"

expect_same_active_continuum :: proc(t: ^testing.T, a, b: ^Dark_Continuum) {
	testing.expect_value(t, a.seed, b.seed)
	testing.expect_value(t, a.anchor_door_id, b.anchor_door_id)
	testing.expect_value(t, a.anchor_neighborhood, b.anchor_neighborhood)
	testing.expect_value(t, a.anchor_position, b.anchor_position)
	testing.expect_value(t, a.loaded_chunks, b.loaded_chunks)
	testing.expect_value(t, a.loaded_chunk_count, b.loaded_chunk_count)
	testing.expect_value(t, a.doors, b.doors)
	testing.expect_value(t, a.door_count, b.door_count)
	testing.expect_value(t, a.organisms, b.organisms)
	testing.expect_value(t, a.organism_count, b.organism_count)
	testing.expect_value(t, a.fields, b.fields)
	testing.expect_value(t, a.field_count, b.field_count)
}

@(test)
dark_continuum_generation_is_deterministic :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(
		91,
	); a := generate_dark_continuum(77, &galaxy); b := generate_dark_continuum(77, &galaxy)
	expect_same_active_continuum(
		t,
		&a,
		&b,
	); testing.expect_value(t, a.loaded_chunk_count, 1); testing.expect_value(t, a.door_count, DARK_CHUNK_DOORS); testing.expect(t, a.organism_count > 0 && a.field_count > 0)
}

@(test)
dark_chunk_queries_and_loading_ignore_generation_order :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(911)
	a := generate_dark_continuum(771, &galaxy)
	b := a
	first := Dark_Chunk_Coord{2, -1, 4, 3}
	second := Dark_Chunk_Coord{-3, 5, 0, -2}
	testing.expect_value(
		t,
		dark_query_chunk(a.seed, galaxy.neighborhood_count, first),
		dark_query_chunk(a.seed, galaxy.neighborhood_count, first),
	)
	testing.expect(t, dark_ensure_chunk_loaded(&a, first))
	testing.expect(t, dark_ensure_chunk_loaded(&a, second))
	testing.expect(t, dark_ensure_chunk_loaded(&b, second))
	testing.expect(t, dark_ensure_chunk_loaded(&b, first))
	expect_same_active_continuum(t, &a, &b)
}

@(test)
dark_chunk_eviction_restores_persistent_changes :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(912)
	d := generate_dark_continuum(772, &galaxy)
	defer dark_continuum_destroy_storage(&d)
	origin := Dark_Chunk_Coord{}
	door_id := d.doors[0].id
	d.doors[0].traffic = 17
	d.fields[0].film = .123
	d.organisms[0].injury = .42
	organism_id := d.organisms[0].id
	for i in 1 ..= INITIAL_DARK_ARCHIVED_CHUNKS + MAX_DARK_LOADED_CHUNKS + 1 do testing.expect(t, dark_ensure_chunk_loaded(&d, {i32(i), 0, 0, 0}))
	testing.expect(t, d.archived_chunk_count > INITIAL_DARK_ARCHIVED_CHUNKS)
	testing.expect(t, dark_archived_chunk_index(&d, origin) >= 0)
	testing.expect(t, dark_ensure_correspondence_loaded(&d, door_id, d.anchor_neighborhood))
	door_found, field_found, organism_found := false, false, false
	for door in d.doors[:d.door_count] do if door.id == door_id {door_found = true; testing.expect_value(t, door.traffic, i32(17))}
	for field in d.fields[:d.field_count] do if dark_chunk_equal(field.chunk, origin) {field_found = true; testing.expect_value(t, field.film, f64(.123)); break}
	for organism in d.organisms[:d.organism_count] do if organism.id == organism_id {organism_found = true; testing.expect_value(t, organism.injury, f64(.42))}
	testing.expect(t, door_found && field_found && organism_found)
}

@(test)
dark_fixed_steps_ignore_render_frame_partitioning :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(
		92,
	); a := generate_dark_continuum(78, &galaxy); b := a; a.paused = false; b.paused = false
	for _ in 0 ..< 10 do advance_dark_continuum(&a, .1)
	for _ in 0 ..< 100 do advance_dark_continuum(&b, .01)
	testing.expect_value(
		t,
		a.simulation_tick,
		b.simulation_tick,
	); testing.expect_value(t, a.organisms, b.organisms); testing.expect_value(t, a.fields, b.fields)
}

@(test)
deep_native_mobility_expands_fourth_axis_authority :: proc(t: ^testing.T) {
	m := dark_mobility_for_role(.Shear_Hunter); direction := Dark_Vec4{0, 0, 0, 1}
	shallow :=
		direction[3] *
		m.fourth_axis_acceleration *
		(1 + dark_depth_from_anchor(1, {}, {0, 0, 0, .2}) * .16)
	deep :=
		direction[3] *
		m.fourth_axis_acceleration *
		(1 + dark_depth_from_anchor(1, {}, {0, 0, 0, 6}) * .16)
	testing.expect(
		t,
		deep > shallow,
	); testing.expect(t, m.depth_crossing_cost > 0 && m.law_drift_tolerance < 1)
}

@(test)
dark_depth_is_relative_to_the_anchor_correspondence :: proc(t: ^testing.T) {
	seed := u64(17)
	anchor := Dark_Vec4{30, -4, 8, 12}
	near := Dark_Vec4{-200, 90, 3, 12.25}
	deep := Dark_Vec4{-200, 90, 3, 18}
	testing.expect(
		t,
		dark_depth_from_anchor(seed, anchor, near) < dark_depth_from_anchor(seed, anchor, deep),
	)
	shift := Dark_Vec4{0, 0, 0, 7}
	testing.expect(
		t,
		math.abs(
			dark_depth_from_anchor(
				seed,
				dark_vec4_add(anchor, shift),
				dark_vec4_add(near, shift),
			) -
			dark_depth_from_anchor(seed, anchor, near),
		) <
		.08,
	)
}

@(test)
ship_motion_deposits_a_four_dimensional_wake :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(913)
	d := generate_dark_continuum(773, &galaxy)
	d.fields[0].position = {1, 0, 0, 1}
	d.fields[0].radius = 2
	d.fields[0].wake_energy = 0
	dark_deposit_wake(&d, {0, 0, 0, 0}, {2, 0, 0, 2}, .2)
	testing.expect(t, d.fields[0].wake_energy > 0)
	d.fields[0].wake_energy = 0
	dark_deposit_wake(&d, {0, 0, 0, -8}, {2, 0, 0, -8}, .2)
	testing.expect_value(t, d.fields[0].wake_energy, f64(0))
}

@(test)
course_forecast_samples_local_law_and_weather_fields :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(914)
	d := generate_dark_continuum(774, &galaxy)
	for &field in d.fields[:d.field_count] {field.position = {100, 100, 100, 100}; field.law_intensity = 0; field.weather_intensity = 0}
	course := Dark_Course {
		waypoint_count = 2,
	}
	course.waypoints[0].position = d.anchor_position
	course.waypoints[1].position = dark_vec4_add(d.anchor_position, {2, 0, 0, .5})
	calm := dark_course_forecast(&d, &course)
	d.fields[0].position = dark_vec4_scale(
		dark_vec4_add(course.waypoints[0].position, course.waypoints[1].position),
		.5,
	)
	d.fields[0].radius = 3
	d.fields[0].law_intensity = .8
	d.fields[0].weather_intensity = .9
	active := dark_course_forecast(&d, &course)
	testing.expect(t, active.law_drift > calm.law_drift)
	testing.expect(t, active.weather_exposure > calm.weather_exposure)
}

@(test)
manifestation_changes_with_observer_conditions_not_biological_motion :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(915)
	d := generate_dark_continuum(775, &galaxy)
	o := &d.organisms[0]
	base := Dark_Manifestation_Conditions {
		observer_correspondence_w = o.position[3],
		correspondence_width      = .8,
	}
	isolated := base
	isolated.isolation_strength = 1
	position_before := o.position
	a := dark_manifestation_for(o, base)
	b := dark_manifestation_for(o, isolated)
	testing.expect_value(t, o.position, position_before)
	testing.expect(t, math.abs(a.local_slice_w - b.local_slice_w) > 1e-6)
}

@(test)
injury_masks_remove_localized_four_dimensional_anatomy :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(916)
	d := generate_dark_continuum(776, &galaxy)
	o := &d.organisms[0]
	before := dark_organism_world_distance_at(o, o.position, 0)
	dark_record_injury(o, o.position, 1, 12)
	after := dark_organism_world_distance_at(o, o.position, 0)
	testing.expect(t, after > before)
	testing.expect_value(t, o.injury_mask_count, 1)
}

@(test)
hunters_cannot_intercept_without_local_correspondence_evidence :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(917)
	d := generate_dark_continuum(777, &galaxy)
	d.field_count = 0
	d.organism_count = 2
	hunter := &d.organisms[0]
	prey := &d.organisms[1]
	hunter.role = .Shear_Hunter
	hunter.position = {0, 0, 0, 0}
	hunter.sensory_range = 3
	hunter.target_id = 0
	prey.role = .Lantern_Grazer
	prey.position = {0, 0, 0, 8}
	_ = dark_organism_acceleration(&d, 0)
	testing.expect_value(t, hunter.target_id, u64(0))
	prey.position[3] = 2
	_ = dark_organism_acceleration(&d, 0)
	testing.expect_value(t, hunter.target_id, prey.id)
}

@(test)
hush_colonies_can_attach_to_grazer_bodies :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(918)
	d := generate_dark_continuum(778, &galaxy)
	d.organism_count = 2
	colony := &d.organisms[0]
	host := &d.organisms[1]
	colony.role = .Hush_Colony
	colony.position = {0, 0, 0, 1}
	colony.radius = 1
	colony.sensory_range = 4
	colony.attached_organism = 0
	host.role = .Lantern_Grazer
	host.position = colony.position
	host.radius = 1
	colony.genome = {
		gene_count = 1,
	}
	colony.genome.genes[0] = {
		primitive  = .Ellipsoid,
		combine    = .Smooth_Union,
		radius     = {.8, .8, .8, .8},
		smoothness = .05,
	}
	host.genome = colony.genome
	advance_dark_continuum_fixed(&d)
	testing.expect_value(t, colony.attached_organism, host.id)
}

@(test)
detritus_drives_grave_reef_succession :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(919)
	d := generate_dark_continuum(779, &galaxy)
	d.simulation_tick = 1199
	d.organism_count = 0
	d.field_count = 1
	d.fields[0].detritus = .9
	advance_dark_continuum_fixed(&d)
	testing.expect_value(t, d.organism_count, 1)
	testing.expect_value(t, d.organisms[0].role, Dark_Ecological_Role.Grave_Reef)
	testing.expect(t, d.fields[0].detritus < .9)
}

@(test)
species_law_tolerance_changes_ecological_cost :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(920)
	a := generate_dark_continuum(780, &galaxy)
	b := a
	a.organism_count = 1; a.field_count = 1; a.organisms[0].position = a.fields[0].position; a.organisms[0].energy = .7; a.fields[0].law_intensity = 1; a.fields[0].radius = 4
	b.organism_count = 1; b.field_count = 1; b.organisms[0].position = b.fields[0].position; b.organisms[0].energy = .7; b.fields[0].law_intensity = 1; b.fields[0].radius = 4
	a.organisms[0].mobility.law_drift_tolerance = 0
	b.organisms[0].mobility.law_drift_tolerance = 1
	advance_dark_continuum_fixed(&a)
	advance_dark_continuum_fixed(&b)
	testing.expect(t, a.organisms[0].energy < b.organisms[0].energy)
}

@(test)
four_dimensional_separation_prevents_false_visible_contact :: proc(t: ^testing.T) {
	a := generate_sdf_creature(1); b := generate_sdf_creature(2)
	_, contact := sdf_creatures_contact_at(&a, {0, 0, 0, -4}, 1, &b, {0, 0, 0, 4}, 1, 0)
	testing.expect(t, !contact)
	testing.expect(
		t,
		!sdf_swept_hyperspheres_contact(
			{0, 0, 0, -4},
			{1, 0, 0, -4},
			1,
			{0, 0, 0, 4},
			{-1, 0, 0, 4},
			1,
		),
	)
}

@(test)
door_endpoint_remains_hidden_until_crossing :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(93); d := generate_dark_continuum(79, &galaxy); door := d.doors[1]
	testing.expect(
		t,
		!door.endpoint_known,
	); endpoint, ok := dark_cross_door(&d, door.id, door.position); testing.expect(t, ok); testing.expect_value(t, endpoint, door.galaxy_neighborhood); testing.expect(t, !d.doors[1].endpoint_known)
}

@(test)
course_depth_increases_ship_exposure :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(94); d := generate_dark_continuum(80, &galaxy)
	shallow := Dark_Course {
		waypoint_count = 2,
	}; shallow.waypoints[0].position =
		d.anchor_position; shallow.waypoints[0].position[3] += .2; shallow.waypoints[1].position = dark_vec4_add(shallow.waypoints[0].position, {4, 0, 0, 0})
	deep :=
		shallow; deep.waypoints[0].position[3] = d.anchor_position[3] + 5; deep.waypoints[1].position[3] = d.anchor_position[3] + 5
	a := dark_course_forecast(&d, &shallow); b := dark_course_forecast(&d, &deep)
	testing.expect(
		t,
		a.valid && b.valid,
	); testing.expect(t, b.law_drift > a.law_drift && b.coherence_cost > a.coherence_cost)
}

@(test)
door_course_depth_excursions_are_anchor_relative :: proc(t: ^testing.T) {
	door := Dark_Door {
		position = {8, 0, 0, 14},
	}
	course := dark_course_to_door({0, 0, 0, 10}, &door, 3, 12)
	testing.expect(t, math.abs(course.waypoints[1].position[3] - 12) >= 3)
}

@(test)
campaign_snapshots_do_not_alias_persistent_dark_deltas :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 921)
	defer campaign_destroy(&c)
	for i in 1 ..= MAX_DARK_LOADED_CHUNKS do testing.expect(t, dark_ensure_chunk_loaded(&c.outer_dark.continuum, {i32(i), 0, 0, 0}))
	testing.expect(t, c.outer_dark.continuum.archived_chunk_count > 0)
	snapshot := campaign_snapshot(&c)
	defer free(snapshot)
	before := snapshot.outer_dark.continuum.archived_chunks[0].organisms[0].injury
	c.outer_dark.continuum.archived_chunks[0].organisms[0].injury = clamp(before + .4, 0, 1)
	testing.expect_value(
		t,
		snapshot.outer_dark.continuum.archived_chunks[0].organisms[0].injury,
		before,
	)
	testing.expect(t, campaign_restore(&c, snapshot^))
	testing.expect_value(t, c.outer_dark.continuum.archived_chunks[0].organisms[0].injury, before)
}

@(test)
tracker_only_reports_conditionally_manifested_four_dimensional_bodies :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(1811)
	d := generate_dark_continuum(1811, &galaxy)
	for &organism in d.organisms[:d.organism_count] do organism.alive = false
	observer := d.anchor_position
	visible := &d.organisms[0]
	visible.alive = true
	visible.position = observer
	visible.radius = .4
	hidden := &d.organisms[1]
	hidden.alive = true
	hidden.position = observer
	hidden.position[3] += 2
	hidden.radius = .1
	tracker := dark_tracker_scan(&d, observer, 8, 0)
	testing.expect_value(t, tracker.track_count, 1)
	testing.expect_value(t, tracker.tracks[0].organism_id, visible.id)
}

@(test)
four_dimensional_sdf_contact_finds_offset_lobes_between_body_centers :: proc(t: ^testing.T) {
	a := Dark_Organism {
		position = {0, 0, 0, 0},
		radius   = 1,
		alive    = true,
	}
	b := Dark_Organism {
		position = {1.2, 0, 0, 0},
		radius   = 1,
		alive    = true,
	}
	a.genome.gene_count = 1
	a.genome.genes[0] = {
		primitive  = .Ellipsoid,
		combine    = .Smooth_Union,
		center     = {.6, 0, 0, 0},
		radius     = {.35, .35, .35, .35},
		smoothness = .05,
	}
	b.genome.gene_count = 1
	b.genome.genes[0] = {
		primitive  = .Ellipsoid,
		combine    = .Smooth_Union,
		center     = {-.6, 0, 0, 0},
		radius     = {.35, .35, .35, .35},
		smoothness = .05,
	}
	testing.expect(t, dark_organism_world_distance_at(&a, b.position, 0) > 0)
	testing.expect(t, dark_organism_world_distance_at(&b, a.position, 0) > 0)
	penetration, contact := dark_organisms_contact_at(&a, &b, 0)
	testing.expect(t, contact)
	testing.expect(t, penetration > 0)
}

@(test)
six_plane_orientation_transforms_four_dimensional_anatomy :: proc(t: ^testing.T) {
	o := Dark_Organism {
		radius = 1,
		alive  = true,
	}; o.genome.gene_count = 1; o.genome.genes[0] = {
		primitive  = .Ellipsoid,
		combine    = .Smooth_Union,
		radius     = {.8, .2, .2, .2},
		smoothness = .01,
	}
	testing.expect(t, dark_organism_world_distance_at(&o, {.6, 0, 0, 0}, 0) < 0)
	o.orientation[2] = math.PI * .5 // rotate the x-w plane
	testing.expect(t, dark_organism_world_distance_at(&o, {.6, 0, 0, 0}, 0) > 0)
	testing.expect(t, dark_organism_world_distance_at(&o, {0, 0, 0, .6}, 0) < 0)
	local: Dark_Vec4 = {
		.3,
		-.2,
		.1,
		.4,
	}; world := dark_organism_local_to_world(&o, local); round_trip := dark_organism_world_to_local(&o, world)
	for axis in 0 ..< 4 do testing.expect(t, math.abs(round_trip[axis] - local[axis]) < 1e-9)
}

@(test)
weather_can_obscure_a_door_without_remapping_its_endpoint :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(
		1824,
	); d := generate_dark_continuum(1824, &galaxy); door := &d.doors[1]; door.access = .5; endpoint := door.galaxy_neighborhood
	observer := dark_vec4_add(
		door.position,
		{7, 0, 0, 0},
	); field := &d.fields[0]; field.position = door.position; field.radius = 10; field.weather_intensity = 0
	clear := dark_door_detection_confidence(&d, observer, door); testing.expect(t, clear > .05)
	field.weather_intensity = 1; obscured := dark_door_detection_confidence(&d, observer, door); testing.expect_value(t, obscured, f64(0)); testing.expect_value(t, door.galaxy_neighborhood, endpoint)
}

@(test)
food_web_transfers_energy_causes_injury_death_and_reproduction :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(
		1826,
	); d := generate_dark_continuum(1826, &galaxy); d.organism_count = 3; d.field_count = 1
	field := &d.fields[0]; field.position = {}; field.radius = 3; field.film = .5; field.wake_energy = 0; field.detritus = 0; field.hush = 0
	for &o, i in d.organisms[:3] {o = Dark_Organism {
			id            = u64(i + 1),
			position      = {},
			radius        = 1,
			energy        = .5,
			condition     = 1,
			sensory_range = 8,
			alive         = true,
		}; o.genome.gene_count = 1; o.genome.genes[0] = {
			primitive  = .Ellipsoid,
			combine    = .Smooth_Union,
			radius     = {.8, .8, .8, .8},
			smoothness = .02,
		}}
	grazer := &d.organisms[0]; grazer.role = .Lantern_Grazer; grazer_before := grazer.energy; film_before := field.film
	hunter := &d.organisms[1]; hunter.role = .Shear_Hunter; hunter.target_id = grazer.id; hunter_before := hunter.energy
	_, initial_contact := dark_organisms_contact_at(
		hunter,
		grazer,
		0,
	); testing.expect(t, initial_contact)
	doomed := &d.organisms[2]; doomed.role = .Hush_Colony; doomed.condition = 0; doomed.energy = 0
	advance_dark_continuum_fixed(&d)
	testing.expect(
		t,
		field.film < film_before,
	); testing.expect(t, grazer.energy < grazer_before); testing.expect(t, grazer.injury > 0); testing.expect(t, hunter.energy > hunter_before); testing.expect(t, !doomed.alive); testing.expect(t, field.detritus >= .2)
	// Remove contacts, leave one healthy high-energy parent, and reach the stable
	// reproduction boundary without advancing 599 expensive ecological steps.
	d.organism_count = 1; parent := &d.organisms[0]; parent.alive = true; parent.role = .Lantern_Grazer; parent.energy = .9; parent.condition = 1; parent.position = field.position; d.simulation_tick = 599
	advance_dark_continuum_fixed(
		&d,
	); testing.expect_value(t, d.organism_count, 2); testing.expect(t, d.organisms[1].id != parent.id); testing.expect_value(t, d.organisms[1].energy, f64(.34))
}

@(test)
dead_anatomy_withdraws_over_a_persistent_manifestation_interval :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(1820)
	d := generate_dark_continuum(1820, &galaxy)
	for &organism in d.organisms[:d.organism_count] do organism.alive = false
	remains := &d.organisms[0]
	remains.alive = false
	remains.death_tick = 100
	remains.behavior = .Injured
	remains.position = d.anchor_position
	remains.radius = 2
	d.simulation_tick = 100
	tracker := dark_tracker_scan(&d, d.anchor_position, 8, 0)
	testing.expect_value(t, tracker.track_count, 1)
	d.simulation_tick = 401
	tracker = dark_tracker_scan(&d, d.anchor_position, 8, 0)
	testing.expect_value(t, tracker.track_count, 0)
}

@(test)
expired_anatomy_releases_capacity_without_reordering_survivors :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(1821)
	d := generate_dark_continuum(1821, &galaxy)
	testing.expect(t, d.organism_count >= 2)
	first_id := d.organisms[0].id
	second_id := d.organisms[1].id
	d.organisms[0].alive = false
	d.organisms[0].death_tick = 1
	d.simulation_tick = 301
	before := d.organism_count
	advance_dark_continuum_fixed(&d)
	testing.expect_value(t, d.organism_count, before - 1)
	testing.expect(t, d.organisms[0].id != first_id)
	testing.expect_value(t, d.organisms[0].id, second_id)
}

@(test)
autopilot_makes_bounded_four_dimensional_avoidance_before_replanning :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(1812)
	d := generate_dark_continuum(1812, &galaxy)
	for &organism in d.organisms[:d.organism_count] do organism.alive = false
	n := Dark_Expedition_Navigation {
		position = d.anchor_position,
		speed    = 1,
	}
	course := Dark_Course {
		waypoint_count = 2,
	}
	course.waypoints[0].position = n.position
	course.waypoints[1].position = dark_vec4_add(n.position, {2, 0, 0, 0})
	_, ok := plot_dark_course(&d, &n, course)
	testing.expect(t, ok)
	step_distance := max(n.speed, .1) * DARK_FIXED_STEP
	segment_distance := dark_metric_distance(
		d.seed,
		course.waypoints[0].position,
		course.waypoints[1].position,
	)
	ideal := dark_vec4_lerp(
		course.waypoints[0].position,
		course.waypoints[1].position,
		step_distance / segment_distance,
	)
	obstacle := &d.organisms[0]
	obstacle.alive = true
	obstacle.radius = .05
	obstacle.position = dark_vec4_add(ideal, {.20, 0, 0, 0})
	advance_dark_navigation_fixed(&d, &n)
	testing.expect(t, !n.paused_for_replan)
	testing.expect(t, dark_metric_distance(d.seed, ideal, n.position) > 0)
	testing.expect(t, dark_metric_distance(d.seed, ideal, n.position) <= .13)
}

@(test)
autopilot_can_withdraw_from_an_existing_avoidance_overlap :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(1813); d := generate_dark_continuum(1813, &galaxy)
	for &organism in d.organisms[:d.organism_count] do organism.alive = false
	n := Dark_Expedition_Navigation {
		position = d.anchor_position,
		speed    = 1,
	}
	obstacle := &d.organisms[0]; obstacle.alive = true; obstacle.radius = .4; obstacle.position = dark_vec4_add(n.position, {.2, 0, 0, 0})
	before := dark_metric_distance(d.seed, n.position, obstacle.position) - obstacle.radius
	course := Dark_Course {
		waypoint_count = 2,
	}; course.waypoints[0].position =
		n.position; course.waypoints[1].position = dark_vec4_add(n.position, {-2, 0, 0, 0})
	_, ok := plot_dark_course(
		&d,
		&n,
		course,
	); testing.expect(t, ok); advance_dark_navigation_fixed(&d, &n)
	after := dark_metric_distance(d.seed, n.position, obstacle.position) - obstacle.radius
	testing.expect(t, !n.paused_for_replan); testing.expect(t, after > before)
}

@(test)
plotted_course_advances_in_fixed_four_dimensional_steps :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(95); d := generate_dark_continuum(81, &galaxy); d.paused = false
	n := Dark_Expedition_Navigation {
		position = {0, 0, 0, 0},
		speed    = 1,
	}; course := Dark_Course {
		waypoint_count = 2,
	}; course.waypoints[0].position = n.position; course.waypoints[1].position = {1, 2, 3, 4}
	_, ok := plot_dark_course(
		&d,
		&n,
		course,
	); testing.expect(t, ok); for _ in 0 ..< 5 do advance_dark_expedition(&d, &n, .1)
	testing.expect(
		t,
		n.position[0] > 0 && n.position[1] > 0 && n.position[2] > 0 && n.position[3] > 0,
	)
}

@(test)
simulated_dark_voyage_uses_the_fixed_step_autopilot :: proc(t: ^testing.T) {
	galaxy := generate_galaxy(96); d := generate_dark_continuum(82, &galaxy)
	for &organism in d.organisms[:d.organism_count] do organism.alive = false
	n := Dark_Expedition_Navigation {
		position = {0, 0, 0, 0},
		speed    = 1,
	}; course := Dark_Course {
		waypoint_count = 2,
	}; course.waypoints[0].position = n.position; course.waypoints[1].position = {1, 2, 3, 4}
	_, ok := plot_dark_course(
		&d,
		&n,
		course,
	); testing.expect(t, ok); testing.expect(t, simulate_dark_expedition(&d, &n)); testing.expect_value(t, n.position, course.waypoints[1].position); testing.expect(t, !n.autopilot_active)
}
