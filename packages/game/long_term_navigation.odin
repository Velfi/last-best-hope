package game

import "core:fmt"

// A discovered living-world signal can become a campaign-scale direction of
// travel. It never authorizes a direct normal-space jump: each mapped Dark
// correspondence only changes how much of the intervening galaxy is known.
Long_Term_Navigation_Goal :: struct {
	active:                                      bool,
	contact_id:                                  u64,
	target_neighborhood, origin_neighborhood:    int,
	set_event:                                   u64,
}

Long_Term_Navigation_Stage :: enum {
	Charting,
	Reached,
	Surveyed,
	Colonized,
}

Habitable_Contact_Intel :: enum {
	Signature,
	Orbital,
	Climate,
	Local_Survey,
	Surveyed,
}

// A 0.1 milliarcsecond equivalent resolving angle makes the intelligence
// stages depend on the fleet's actual observing geometry, sensor posture, and
// damaged instruments rather than an abstract campaign-completion percentage.
HABITABLE_SENSOR_ANGULAR_RESOLUTION_RAD :: 4.848136811e-10
HABITABLE_SENSOR_ORBITAL_RESOLUTION_KM :: 50000.0
HABITABLE_SENSOR_CLIMATE_RESOLUTION_KM :: 10000.0
PARSEC_KM :: 3.085677581e13

Long_Term_Navigation_Progress :: struct {
	valid:                                                       bool,
	target_neighborhood, closest_mapped_neighborhood:           int,
	original_distance_kpc, remaining_distance_kpc, progress:     f64,
	charted_correspondences:                                    int,
	stage:                                                       Long_Term_Navigation_Stage,
}

long_term_navigation_stage_name :: proc(value: Long_Term_Navigation_Stage) -> string {
	switch value {
	case .Charting: return "CHARTING PASSAGES"
	case .Reached: return "READY TO SURVEY"
	case .Surveyed: return "SUITABILITY CONFIRMED"
	case .Colonized: return "COLONY FOUNDED"
	}
	return "CHARTING PASSAGES"
}

habitable_contact_intel_from_sensor_resolution :: proc(goal_matches, surveyed: bool, stage: Long_Term_Navigation_Stage, resolution_km: f64) -> Habitable_Contact_Intel {
	if surveyed do return .Surveyed
	if !goal_matches do return .Signature
	if stage == .Reached do return .Local_Survey
	if resolution_km <= HABITABLE_SENSOR_CLIMATE_RESOLUTION_KM do return .Climate
	if resolution_km <= HABITABLE_SENSOR_ORBITAL_RESOLUTION_KM do return .Orbital
	return .Signature
}

habitable_contact_sensor_resolution_km :: proc(c: ^Campaign, contact: Habitable_World_Contact, progress: Long_Term_Navigation_Progress) -> f64 {
	if c == nil || !progress.valid do return 0
	profile := dark_sensor_profile(.Passive)
	damage: i32
	if c.passage.active {
		profile = dark_sensor_profile(c.passage.dark_navigation.sensor_posture)
		for ship_id in c.passage.ships[:c.passage.ship_count] do if at := ship_index(c, ship_id); at >= 0 do damage += c.ships[at].impairments.sensors
	}
	// A damaged sensor suite lowers effective aperture; illumination and active
	// sweeps recover resolving power at the usual exposure cost.
	effective_aperture := max(.25, profile.range_scale * (1 - f64(damage) * .12))
	range_pc := progress.remaining_distance_kpc * 1000 + contact.distance_pc
	return range_pc * PARSEC_KM * HABITABLE_SENSOR_ANGULAR_RESOLUTION_RAD / effective_aperture
}

habitable_contact_intel :: proc(c: ^Campaign, contact: Habitable_World_Contact) -> Habitable_Contact_Intel {
	progress := long_term_navigation_goal_progress(c)
	return habitable_contact_intel_from_sensor_resolution(
		progress.valid && c.long_term_navigation_goal.contact_id == contact.id,
		contact.surveyed,
		progress.stage,
		habitable_contact_sensor_resolution_km(c, contact, progress),
	)
}

habitable_contact_intel_label :: proc(c: ^Campaign, contact: Habitable_World_Contact) -> string {
	switch habitable_contact_intel(c, contact) {
	case .Signature:
		return fmt.tprintf("%04d · REMOTE LIFE SIGNATURE", contact.id % 10000)
	case .Orbital:
		return fmt.tprintf("%04d · %.0f KM RESOLUTION · ORBITAL CANDIDATE", contact.id % 10000, habitable_contact_sensor_resolution_km(c, contact, long_term_navigation_goal_progress(c)))
	case .Climate:
		return fmt.tprintf("%04d · %.0f KM RESOLUTION · %.2f R-EARTH · TEMPERATE %.0f%%", contact.id % 10000, habitable_contact_sensor_resolution_km(c, contact, long_term_navigation_goal_progress(c)), contact.radius_earth, contact.temperate_orbit_likelihood * 100)
	case .Local_Survey:
		return fmt.tprintf("%04d · %.0f KM RESOLUTION · LOCAL SURVEY WINDOW OPEN", contact.id % 10000, habitable_contact_sensor_resolution_km(c, contact, long_term_navigation_goal_progress(c)))
	case .Surveyed:
		return fmt.tprintf("%04d · SURVEYED · %.2f R-EARTH", contact.id % 10000, contact.radius_earth)
	}
	return "REMOTE LIFE SIGNATURE"
}

long_term_navigation_goal_set :: proc(c: ^Campaign, contact_id: u64) -> (bool, string) {
	if c == nil do return false, "No campaign is available."
	at := habitable_contact_index(c.habitable_contacts[:], contact_id)
	if at < 0 do return false, "That habitable-world contact is not in the fleet record."
	contact := c.habitable_contacts[at]
	if contact.neighborhood_index < 0 || contact.neighborhood_index >= c.galaxy.neighborhood_count do return false, "The contact has no reachable galactic reference."
	c.long_term_navigation_goal = {
		active = true,
		contact_id = contact.id,
		target_neighborhood = contact.neighborhood_index,
		origin_neighborhood = c.outer_dark.continuum.anchor_neighborhood,
	}
	record_event(c, .Situation_Decided, fmt.tprintf("The fleet set a long-term navigation goal toward habitable contact %04d.", contact.id % 10000))
	c.long_term_navigation_goal.set_event = c.event_sequence
	return true, "Long-term navigation goal recorded. Chart correspondences that close the distance."
}

long_term_navigation_goal_progress :: proc(c: ^Campaign) -> Long_Term_Navigation_Progress {
	r := Long_Term_Navigation_Progress{closest_mapped_neighborhood = -1, target_neighborhood = -1}
	if c == nil || !c.long_term_navigation_goal.active do return r
	g := c.long_term_navigation_goal
	at := habitable_contact_index(c.habitable_contacts[:], g.contact_id)
	if at < 0 || c.habitable_contacts[at].neighborhood_index != g.target_neighborhood do return r
	original, ok := galaxy_neighborhood_distance(c, g.origin_neighborhood, g.target_neighborhood)
	if !ok || original <= 1e-9 do return r
	r = {valid = true, target_neighborhood = g.target_neighborhood, closest_mapped_neighborhood = g.origin_neighborhood, original_distance_kpc = original, remaining_distance_kpc = original, stage = .Charting}
	r.charted_correspondences = len(c.dark_fleet_atlas)
	// Only a leg the expedition can actually enter and survive advances the
	// goal. A geographically nearer but disconnected atlas mark remains useful
	// information, not false campaign progress.
	if c.passage.active {
		route := passage_fastest_known_route(c, &c.passage, g.target_neighborhood)
		if route.valid && route.uses_dark && route.exit_neighborhood >= 0 {
			distance, measured := galaxy_neighborhood_distance(c, route.exit_neighborhood, g.target_neighborhood)
			if measured && distance < r.remaining_distance_kpc {
				r.remaining_distance_kpc = distance
				r.closest_mapped_neighborhood = route.exit_neighborhood
			}
		}
	}
	if c.passage.active && c.passage.domain == .Normal_Space {
		distance, measured := galaxy_neighborhood_distance(c, c.passage.normal_course.start_neighborhood, g.target_neighborhood)
		if measured && distance < r.remaining_distance_kpc {
			r.remaining_distance_kpc = distance
			r.closest_mapped_neighborhood = c.passage.normal_course.start_neighborhood
		}
	}
	r.progress = clamp(1 - r.remaining_distance_kpc / r.original_distance_kpc, 0, 1)
	for relay in c.dark_relays do if relay.authenticated && relay.galaxy_neighborhood == g.target_neighborhood do r.stage = .Reached
	if c.habitable_contacts[at].surveyed do r.stage = .Surveyed
	for settlement in c.settlements[:c.settlement_count] do if settlement.active && settlement.celestial.system_seed == c.habitable_contacts[at].system_seed && settlement.celestial.planet_seed == c.habitable_contacts[at].planet_seed do r.stage = .Colonized
	return r
}
