package game

import "core:math"

HABITABLE_OBSERVATION_RADIUS_PC :: 30.0
MAX_LOCAL_HABITABLE_CONTACTS :: 8
MAX_MATERIALIZED_CONTACT_SYSTEMS :: 48

Habitable_World_Contact :: struct {
	id:                         u64,
	neighborhood_index:         int,
	source_door_id:             u64,
	system_generation_seed:     u64,
	system_seed, planet_seed:   u64,
	planet_index:               int,
	local_position_pc:          [3]f64,
	distance_pc:                f64,
	radius_earth, mean_flux:    f64,
	temperate_orbit_likelihood: f64,
	detected_season:            i32,
	transmitted, surveyed:      bool,
	materialized_system_index:  int,
}

habitable_contact_mix :: proc(value: u64) -> u64 {
	x := value
	x = (x ~ (x >> 30)) * 0xbf58476d1ce4e5b9
	x = (x ~ (x >> 27)) * 0x94d049bb133111eb
	return x ~ (x >> 31)
}

habitable_contact_unit :: proc(state: ^u64) -> f64 {
	state^ = habitable_contact_mix(state^ + 0x9e3779b97f4a7c15)
	return f64(state^ >> 11) / f64(u64(1) << 53)
}

habitable_contact_target_count :: proc(seed: u64) -> int {
	// Knuth's Poisson sampler with lambda 2: 86.5% of bubbles are non-empty.
	state := seed
	product := 1.0
	count := 0
	for product > f64(0.1353352832366127) && count <= MAX_LOCAL_HABITABLE_CONTACTS {
		product *= max(habitable_contact_unit(&state), 1e-12)
		count += 1
	}
	return clamp(count - 1, 0, MAX_LOCAL_HABITABLE_CONTACTS)
}

habitable_contact_planet :: proc(system: ^Solar_System) -> int {
	if system == nil do return -1
	hz := system_evidence_hz_planet(system)
	if hz < 0 || hz >= system.planet_count do return -1
	p := &system.planets[hz]
	density :=
		p.body.inputs.mass_earth / math.pow(max(p.body.inputs.radius_earth, .01), 3)
	if (p.kind != .Rocky && p.kind != .Ocean) ||
	   p.body.inputs.radius_earth < .5 ||
	   p.body.inputs.radius_earth > 1.8 ||
	   density < .45 ||
	   !p.body.orbit_stable {
		return -1
	}
	return hz
}

habitable_generate_bubble :: proc(
	g: ^Galaxy,
	neighborhood_index: int,
	source_door_id: u64,
	detected_season: i32,
	out: ^[dynamic]Habitable_World_Contact,
) {
	if g == nil ||
	   out == nil ||
	   neighborhood_index < 0 ||
	   neighborhood_index >= g.neighborhood_count {
		return
	}
	bubble_seed :=
		habitable_contact_mix(
			g.seed ~ u64(neighborhood_index + 1) * 0x70635f627562626c,
		)
	target := habitable_contact_target_count(bubble_seed)
	n := g.neighborhoods[neighborhood_index]
	state := bubble_seed
	for ordinal in 0 ..< target {
		found := false
		for attempt in 0 ..< 512 {
			generation_seed :=
				habitable_contact_mix(
					bubble_seed ~ u64(ordinal + 1) * 0x9e3779b97f4a7c15 ~ u64(attempt + 1),
				)
			system, ok := generate_solar_system_population(
				generation_seed,
				n.mean_age_billion_years,
				n.metallicity_dex,
			)
			if !ok do continue
			planet_index := habitable_contact_planet(&system)
			if planet_index < 0 do continue
			p := system.planets[planet_index]
			radius := HABITABLE_OBSERVATION_RADIUS_PC * math.pow(
				habitable_contact_unit(&state),
				1.0 / 3.0,
			)
			cos_theta := habitable_contact_unit(&state) * 2 - 1
			sin_theta := math.sqrt(max(0, 1 - cos_theta * cos_theta))
			phi := habitable_contact_unit(&state) * 2 * math.PI
			contact := Habitable_World_Contact {
				id = habitable_contact_mix(
					bubble_seed ~ u64(ordinal + 1) ~ system.seed ~ p.body.seed,
				),
				neighborhood_index = neighborhood_index,
				source_door_id = source_door_id,
				system_generation_seed = generation_seed,
				system_seed = system.seed,
				planet_seed = p.body.seed,
				planet_index = planet_index,
				local_position_pc = {
					radius * sin_theta * math.cos(phi),
					radius * sin_theta * math.sin(phi),
					radius * cos_theta,
				},
				distance_pc = radius,
				radius_earth = p.body.inputs.radius_earth,
				mean_flux = p.flux_envelope.mean_earth,
				temperate_orbit_likelihood = clamp(
					1 - math.abs(p.flux_envelope.mean_earth - .72),
					0,
					1,
				),
				detected_season = detected_season,
				materialized_system_index = -1,
			}
			append(out, contact)
			found = true
			break
		}
		if !found do break
	}
}

habitable_contact_index :: proc(contacts: []Habitable_World_Contact, id: u64) -> int {
	for contact, i in contacts do if contact.id == id do return i
	return -1
}

habitable_ingest_contact :: proc(c: ^Campaign, incoming: Habitable_World_Contact) -> bool {
	if c == nil || incoming.id == 0 do return false
	if habitable_contact_index(c.habitable_contacts[:], incoming.id) >= 0 do return false
	record := incoming
	record.transmitted = true
	append(&c.habitable_contacts, record)
	return true
}

habitable_reveal_campaign_bubble :: proc(
	c: ^Campaign,
	neighborhood_index: int,
	source_door_id: u64,
) {
	if c == nil do return
	generated := make(
		[dynamic]Habitable_World_Contact,
		0,
		MAX_LOCAL_HABITABLE_CONTACTS,
		context.temp_allocator,
	)
	habitable_generate_bubble(
		c.galaxy,
		neighborhood_index,
		source_door_id,
		c.season,
		&generated,
	)
	for contact in generated do _ = habitable_ingest_contact(c, contact)
}

habitable_reveal_passage_bubble :: proc(
	c: ^Campaign,
	p: ^Passage,
	neighborhood_index: int,
	source_door_id: u64,
) {
	if c == nil || p == nil do return
	generated := make(
		[dynamic]Habitable_World_Contact,
		0,
		MAX_LOCAL_HABITABLE_CONTACTS,
		context.temp_allocator,
	)
	habitable_generate_bubble(
		c.galaxy,
		neighborhood_index,
		source_door_id,
		c.season,
		&generated,
	)
	for contact in generated {
		if habitable_contact_index(c.habitable_contacts[:], contact.id) >= 0 ||
		   habitable_contact_index(p.local_habitable_contacts[:], contact.id) >= 0 {
			continue
		}
		append(&p.local_habitable_contacts, contact)
	}
}

habitable_contacts_at_neighborhood :: proc(c: ^Campaign, neighborhood_index: int) -> int {
	if c == nil do return 0
	count := 0
	for contact in c.habitable_contacts do if contact.neighborhood_index == neighborhood_index do count += 1
	return count
}

materialize_habitable_contact :: proc(c: ^Campaign, contact: ^Habitable_World_Contact) -> int {
	if c == nil || c.galaxy == nil || contact == nil do return -1
	if contact.materialized_system_index >= 0 &&
	   contact.materialized_system_index < c.galaxy.detailed_system_count {
		return contact.materialized_system_index
	}
	for system, i in c.galaxy.detailed_systems[:c.galaxy.detailed_system_count] {
		if system.system.seed == contact.system_seed {
			contact.materialized_system_index = i
			return i
		}
	}
	if c.galaxy.detailed_system_count >= 64 ||
	   c.galaxy.detailed_system_count >=
		   MAX_DETAILED_GALACTIC_SYSTEMS + MAX_MATERIALIZED_CONTACT_SYSTEMS {
		return -1
	}
	n := c.galaxy.neighborhoods[contact.neighborhood_index]
	system, ok := generate_solar_system_population(
		contact.system_generation_seed,
		n.mean_age_billion_years,
		n.metallicity_dex,
	)
	if !ok || system.seed != contact.system_seed do return -1
	append(
		&c.galaxy.detailed_systems,
		Galactic_System {
			neighborhood_index = contact.neighborhood_index,
			metallicity_dex = n.metallicity_dex,
			reachability = 1,
			system = system,
		},
	)
	contact.materialized_system_index = c.galaxy.detailed_system_count
	c.galaxy.detailed_system_count += 1
	return contact.materialized_system_index
}

survey_habitable_contact :: proc(
	c: ^Campaign,
	contact_id, expedition_seed: u64,
) -> (Celestial_Reference, bool) {
	if c == nil do return {}, false
	at := habitable_contact_index(c.habitable_contacts[:], contact_id)
	if at < 0 do return {}, false
	contact := &c.habitable_contacts[at]
	system_index := materialize_habitable_contact(c, contact)
	if system_index < 0 do return {}, false
	record, ok := survey_candidate_system_index(c, system_index, expedition_seed)
	if !ok do return {}, false
	contact.surveyed = true
	if c.world_survey_count < MAX_WORLD_SURVEYS {
		c.world_surveys[c.world_survey_count] = record
		c.world_survey_count += 1
	}
	return record.reference, register_candidate_home(c, record, expedition_seed)
}
