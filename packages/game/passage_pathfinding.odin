package game

Dark_Aware_Route :: struct {
	valid:                                 bool,
	target_neighborhood:                   int,
	entry_door_id, exit_door_id:           u64,
	entry_neighborhood, exit_neighborhood: int,
	estimated_elapsed_days:                f64,
	uses_dark:                             bool,
}

Dark_Route_Door :: struct {
	id:           u64,
	neighborhood: int,
	position:     Dark_Vec4,
}

dark_route_door_append :: proc(
	c: ^Campaign,
	doors: ^[MAX_DARK_DOORS]Dark_Route_Door,
	count: ^int,
	id: u64,
	neighborhood: int,
) {
	if id == 0 || neighborhood < 0 || count^ >= len(doors) do return
	for known in doors[:count^] do if known.id == id do return
	_ = dark_ensure_correspondence_loaded(&c.outer_dark.continuum, id, neighborhood)
	for door in c.outer_dark.continuum.doors[:c.outer_dark.continuum.door_count] do if door.id == id {
		doors[count^] = {
			id           = id,
			neighborhood = neighborhood,
			position     = door.position,
		}
		count^ += 1
		return
	}
}

dark_route_known_doors :: proc(
	c: ^Campaign,
	p: ^Passage,
	doors: ^[MAX_DARK_DOORS]Dark_Route_Door,
) -> int {
	count := 0
	dark_route_door_append(
		c,
		doors,
		&count,
		c.outer_dark.continuum.anchor_door_id,
		c.outer_dark.continuum.anchor_neighborhood,
	)
	for discovery in c.dark_fleet_atlas do dark_route_door_append(c, doors, &count, discovery.door_id, discovery.galaxy_neighborhood)
	for discovery in p.local_atlas[:p.local_atlas_count] do dark_route_door_append(c, doors, &count, discovery.door_id, discovery.galaxy_neighborhood)
	return count
}

dark_route_normal_days :: proc(
	c: ^Campaign,
	from, to: int,
	velocity_fraction_c: f64,
) -> (
	f64,
	bool,
) {
	distance, ok := galaxy_neighborhood_distance(c, from, to)
	if !ok || velocity_fraction_c <= 0 || velocity_fraction_c >= 1 do return 0, false
	return distance * 1_191_000 / velocity_fraction_c, true
}

dark_route_membrane_days :: proc(d: ^Dark_Continuum, course: ^Dark_Course) -> f64 {
	if course.waypoint_count < 2 do return 0
	total := 0.0
	for i in 1 ..< course.waypoint_count {
		a := course.waypoints[i - 1].position
		b := course.waypoints[i].position
		mid := dark_vec4_scale(dark_vec4_add(a, b), .5)
		ship_days := dark_metric_distance(d.seed, a, b) * .72
		depth := dark_depth_from_anchor(d.seed, d.anchor_position, mid)
		total += dark_membrane_days_for_step(depth, ship_days)
	}
	return total
}

passage_fastest_known_route :: proc(
	c: ^Campaign,
	p: ^Passage,
	target: int,
	velocity_fraction_c: f64 = .18,
) -> Dark_Aware_Route {
	result := Dark_Aware_Route {
		target_neighborhood = target,
	}
	if !p.active || target < 0 || target >= c.galaxy.neighborhood_count do return result
	doors: [MAX_DARK_DOORS]Dark_Route_Door
	count := dark_route_known_doors(c, p, &doors)
	best_days := f64(1e300)
	if p.domain == .Normal_Space {
		start := p.normal_course.start_neighborhood
		if direct, ok := dark_route_normal_days(c, start, target, velocity_fraction_c); ok {
			best_days = direct
			result = {
				valid                  = true,
				target_neighborhood    = target,
				entry_neighborhood     = start,
				exit_neighborhood      = target,
				estimated_elapsed_days = direct,
			}
		}
		for entry in doors[:count] {
			approach, approach_ok := dark_route_normal_days(
				c,
				start,
				entry.neighborhood,
				velocity_fraction_c,
			)
			if !approach_ok do continue
			for exit in doors[:count] {
				if entry.id == exit.id do continue
				course := dark_course_to_door(
					entry.position,
					&Dark_Door{position = exit.position},
					1.8,
					c.outer_dark.continuum.anchor_position[3],
				)
				coherence := passage_course_coherence_forecast(c, p, &course)
				if coherence.crosses_limit do continue
				dark_days := dark_route_membrane_days(&c.outer_dark.continuum, &course)
				departure, departure_ok := dark_route_normal_days(
					c,
					exit.neighborhood,
					target,
					velocity_fraction_c,
				)
				if !departure_ok do continue
				total := approach + dark_days + departure
				if total < best_days {
					best_days = total
					result = {
						valid                  = true,
						target_neighborhood    = target,
						entry_door_id          = entry.id,
						exit_door_id           = exit.id,
						entry_neighborhood     = entry.neighborhood,
						exit_neighborhood      = exit.neighborhood,
						estimated_elapsed_days = total,
						uses_dark              = true,
					}
				}
			}
		}
	} else if p.domain == .Dark {
		for exit in doors[:count] {
			course := dark_course_to_door(
				p.dark_navigation.position,
				&Dark_Door{position = exit.position},
				1.8,
				c.outer_dark.continuum.anchor_position[3],
			)
			coherence := passage_course_coherence_forecast(c, p, &course)
			if coherence.crosses_limit do continue
			dark_days := dark_route_membrane_days(&c.outer_dark.continuum, &course)
			departure, ok := dark_route_normal_days(
				c,
				exit.neighborhood,
				target,
				velocity_fraction_c,
			)
			if !ok do continue
			total := dark_days + departure
			if total < best_days {
				best_days = total
				result = {
					valid                  = true,
					target_neighborhood    = target,
					exit_door_id           = exit.id,
					exit_neighborhood      = exit.neighborhood,
					estimated_elapsed_days = total,
					uses_dark              = true,
				}
			}
		}
	}
	return result
}

follow_fastest_known_route :: proc(
	c: ^Campaign,
	p: ^Passage,
	target: int,
	velocity_fraction_c: f64 = .18,
) -> (
	bool,
	string,
) {
	if p.phase == .Underway do return false, "The current route leg is still underway."
	route := passage_fastest_known_route(c, p, target, velocity_fraction_c)
	if !route.valid do return false, "No known route reaches that galaxy neighborhood."
	if p.domain == .Normal_Space {
		current := p.normal_course.start_neighborhood
		if current == target do return false, "The expedition is already at the destination."
		if route.uses_dark && route.entry_neighborhood == current {
			return enter_passage_dark(c, p, route.entry_door_id)
		}
		return false, "No accessible local correspondence joins the mapped Dark route."
	}
	for &door in c.outer_dark.continuum.doors[:c.outer_dark.continuum.door_count] do if door.id == route.exit_door_id {
		if dark_metric_distance(c.outer_dark.continuum.seed, p.dark_navigation.position, door.position) <= door.radius do return cross_passage_door(c, p)
		course := dark_course_to_door(p.dark_navigation.position, &door, 1.8, c.outer_dark.continuum.anchor_position[3])
		_, ok := plot_passage_course(c, p, course)
		return ok, ok ? "Dark course plotted to the fastest known exit." : "The recommended Dark leg could not be plotted."
	}
	return false, "The recommended Dark exit is not available."
}
