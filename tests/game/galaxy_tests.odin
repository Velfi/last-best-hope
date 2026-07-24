package game_tests

import "core:math"
import "core:testing"

@(test)
habitable_reconnaissance_is_local_deterministic_and_preliminary :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(24) {
		c := new_campaign_seeded_heap(seed)
		duplicate := new_campaign_seeded_heap(seed)
		testing.expect_value(t, len(duplicate.habitable_contacts), len(c.habitable_contacts))
		for contact, i in c.habitable_contacts do testing.expect_value(t, duplicate.habitable_contacts[i], contact)
		campaign_destroy_heap(duplicate)
		origin := c.outer_dark.continuum.anchor_neighborhood
		for contact in c.habitable_contacts {
			testing.expect_value(t, contact.neighborhood_index, origin)
			testing.expect(t, contact.distance_pc <= HABITABLE_OBSERVATION_RADIUS_PC)
			testing.expect(t, contact.transmitted)
			testing.expect(t, !contact.surveyed)
		}
		before := len(c.habitable_contacts)
		habitable_reveal_campaign_bubble(c, origin, c.outer_dark.continuum.anchor_door_id)
		testing.expect_value(t, len(c.habitable_contacts), before)
		testing.expect_value(t, c.world_survey_count, 0)
		testing.expect_value(t, c.surveyed_system_mask, u64(0))
		campaign_destroy_heap(c)
	}
}

@(test)
habitable_contact_distribution_matches_reconnaissance_model :: proc(t: ^testing.T) {
	total, nonempty, empty, maximum := 0, 0, 0, 0
	runs := 10000
	for seed in u64(1) ..= u64(runs) {
		count := habitable_contact_target_count(seed)
		total += count
		maximum = max(maximum, count)
		if count > 0 do nonempty += 1
		if count == 0 do empty += 1
	}
	mean := f64(total) / f64(runs)
	rate := f64(nonempty) / f64(runs)
	testing.expect(t, mean >= 1.9 && mean <= 2.1)
	testing.expect(t, rate >= .80 && rate <= .90)
	testing.expect(t, empty > 0)
	testing.expect(t, maximum <= MAX_LOCAL_HABITABLE_CONTACTS)
}

@(test)
dark_exit_contacts_remain_local_until_transmitted :: proc(t: ^testing.T) {
	c := new_campaign_seeded_heap(8827)
	defer campaign_destroy_heap(c)
	starting := len(c.habitable_contacts)
	p := Passage {
		active                   = true,
		local_habitable_contacts = make(
			[dynamic]Habitable_World_Contact,
			0,
			0,
			context.temp_allocator,
		),
	}
	destination := (c.outer_dark.continuum.anchor_neighborhood + 1) % c.galaxy.neighborhood_count
	habitable_reveal_passage_bubble(c, &p, destination, 991)
	testing.expect_value(t, len(c.habitable_contacts), starting)
	for contact in p.local_habitable_contacts do testing.expect(t, !contact.transmitted)
	dark_transmit_passage_knowledge(c, &p, 17)
	testing.expect_value(t, len(c.habitable_contacts), starting + len(p.local_habitable_contacts))
	for contact in p.local_habitable_contacts do testing.expect(t, contact.transmitted)
	dark_transmit_passage_knowledge(c, &p, 17)
	testing.expect_value(t, len(c.habitable_contacts), starting + len(p.local_habitable_contacts))
}

@(test)
surveying_preliminary_contact_materializes_stable_evidence :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(24) {
		c := new_campaign_seeded_heap(seed)
		if len(c.habitable_contacts) == 0 {
			campaign_destroy_heap(c)
			continue
		}
		contact_id := c.habitable_contacts[0].id
		reference, _ := survey_habitable_contact(c, contact_id, 73)
		testing.expect(t, reference.valid)
		testing.expect_value(t, c.world_survey_count, 1)
		testing.expect(t, c.habitable_contacts[0].surveyed)
		testing.expect(t, c.habitable_contacts[0].materialized_system_index >= 0)
		campaign_destroy_heap(c)
		return
	}
	testing.expect(t, false, "expected a seeded opening contact")
}

@(test)
confirmed_candidate_queues_one_fleet_celebration :: proc(t: ^testing.T) {
	c := new_campaign_seeded_heap(3917)
	defer campaign_destroy_heap(c)
	for seed in u64(1) ..= u64(512) {
		_, discovered := discover_candidate_home(c, seed)
		if !discovered do continue
		testing.expect(t, candidate_celebration_pending(c))
		candidate, pending := candidate_celebration(c)
		testing.expect(t, pending)
		testing.expect(t, candidate != nil)
		testing.expect_value(
			t,
			c.events[c.event_count - 1].kind,
			Event_Kind.Habitable_World_Confirmed,
		)
		testing.expect(t, acknowledge_candidate_celebration(c))
		testing.expect(t, !candidate_celebration_pending(c))
		testing.expect(t, !acknowledge_candidate_celebration(c))
		return
	}
	testing.expect(t, false, "expected a deterministic settlement candidate")
}

@(test)
evidence_centered_hz_occurrence_matches_published_intervals_at_scale :: proc(t: ^testing.T) {
	for class in Star_Class {
		count := 0
		for seed in u64(1) ..= u64(100_000) {s := Solar_System {
				seed       = seed,
				star_count = 1,
			}; s.stars[0].class = class; if system_evidence_hz_occurrence(&s) do count += 1}
		rate := f64(count) / 100_000
		if class ==
		   .M {testing.expect(t, rate >= .21 && rate <= .43); testing.expect(t, abs(rate - .33) < .01)} else {testing.expect(t, rate >= .15 && rate <= .60); testing.expect(t, abs(rate - .37) < .01)}
	}
}

@(test)
survey_selection_is_not_conditioned_on_planets_and_does_not_touch_campaign_rng :: proc(
	t: ^testing.T,
) {
	c: Campaign
	campaign_init(
		&c,
		8821,
	); defer campaign_destroy(&c); before_state, before_sequence := c.rng_state, c.rng_sequence
	for i in 0 ..< c.galaxy.detailed_system_count {record, ok := survey_candidate_system(&c, u64(i)); testing.expect(t, ok); testing.expect_value(t, record.system_index, i32(i)); testing.expect_value(t, record.funnel.systems, i32(1))}
	testing.expect_value(
		t,
		c.rng_state,
		before_state,
	); testing.expect_value(t, c.rng_sequence, before_sequence)
}

@(test)
survey_selection_visits_reachable_systems_before_repeating :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 8822); defer campaign_destroy(&c)
	seen: u64
	for _ in 0 ..< c.galaxy.detailed_system_count {
		record, ok := survey_candidate_system(&c, 0); testing.expect(t, ok)
		bit :=
			u64(1) << u64(record.system_index); testing.expect(t, (seen & bit) == 0); seen |= bit
	}
	repeated, ok := survey_candidate_system(
		&c,
		0,
	); testing.expect(t, ok); testing.expect(t, repeated.repeat)
}

@(test)
black_hole_radius_scales_with_mass :: proc(t: ^testing.T) {
	testing.expect(t, abs(black_hole_schwarzschild_radius_km(1) - 2.95325008) < 1.0e-8)
	testing.expect(t, abs(black_hole_schwarzschild_radius_km(4.0e6) - 1.181300032e7) < 1)
	testing.expect_value(t, black_hole_schwarzschild_radius_km(-1), f64(0))
	testing.expect(t, abs(black_hole_photon_sphere_radius_km(10) - 44.2987512) < 1.0e-7)
	testing.expect(t, abs(black_hole_isco_radius_km(10) - 88.5975024) < 1.0e-7)
}

@(test)
central_black_hole_occupation_tracks_observed_mass_anchors :: proc(t: ^testing.T) {
	testing.expect(t, abs(central_black_hole_occupation_probability(1.0e7) - .39) < 1.0e-9)
	testing.expect(t, abs(central_black_hole_occupation_probability(1.0e8) - .90) < 1.0e-9)
	testing.expect(t, central_black_hole_occupation_probability(1.0e10) >= .99)
	previous: f64
	for exponent in 6 ..= 12 {
		chance := central_black_hole_occupation_probability(math.pow(10.0, f64(exponent)))
		testing.expect(t, chance >= previous && chance >= 0 && chance <= 1)
		previous = chance
	}
}

@(test)
central_black_hole_mass_is_seeded_scattered_and_host_bounded :: proc(t: ^testing.T) {
	a_state, b_state, c_state := u64(71), u64(71), u64(72)
	a := central_black_hole_mass_for_galaxy(1.0e10, .Spiral, &a_state)
	b := central_black_hole_mass_for_galaxy(1.0e10, .Spiral, &b_state)
	c := central_black_hole_mass_for_galaxy(1.0e10, .Spiral, &c_state)
	testing.expect_value(t, a, b)
	testing.expect(t, a != c)
	testing.expect(t, a >= 1.0e2 && a <= 2.0e8)
}

@(test)
candidate_home_screen_rejects_unstable_or_untemperate_worlds :: proc(t: ^testing.T) {
	star := Star_Profile {
		mass_solar        = 1,
		luminosity_solar  = 1,
		radius_solar      = 1,
		age_billion_years = 4.5,
	}
	temperate, ok := evaluate_planet(
		1,
		star,
		{
			mass_earth = 1,
			radius_earth = 1,
			semi_major_axis_au = 1,
			eccentricity = .02,
			bond_albedo = .3,
			greenhouse_warming_k = 30,
			initial_rotation_hours = 24,
		},
	)
	testing.expect(t, ok && planet_is_candidate_home(temperate))
	frozen, frozen_ok := evaluate_planet(
		2,
		star,
		{
			mass_earth = 1,
			radius_earth = 1,
			semi_major_axis_au = 4,
			eccentricity = .02,
			bond_albedo = .3,
			greenhouse_warming_k = 0,
			initial_rotation_hours = 24,
		},
	)
	testing.expect(t, frozen_ok && !planet_is_candidate_home(frozen))
	giant, giant_ok := evaluate_planet(
		3,
		star,
		{
			mass_earth = 40,
			radius_earth = 5,
			semi_major_axis_au = 1,
			eccentricity = .02,
			bond_albedo = .3,
			greenhouse_warming_k = 30,
			initial_rotation_hours = 24,
		},
	)
	testing.expect(t, giant_ok && !planet_is_candidate_home(giant))
}

@(test)
galaxy_generation_is_deterministic :: proc(t: ^testing.T) {
	a := generate_galaxy(0x600d)
	b := generate_galaxy(0x600d)
	c := generate_galaxy(0x600e)
	testing.expect_value(
		t,
		a.seed,
		b.seed,
	); testing.expect_value(t, a.morphology, b.morphology); testing.expect_value(t, a.neighborhoods, b.neighborhoods); testing.expect_value(t, a.detailed_system_count, b.detailed_system_count)
	for system, i in a.detailed_systems do testing.expect_value(t, system, b.detailed_systems[i])
	testing.expect(
		t,
		a.seed != c.seed || a.morphology != c.morphology || a.neighborhoods != c.neighborhoods,
	)
	testing.expect_value(t, a.neighborhood_count, MAX_GALACTIC_NEIGHBORHOODS)
}

@(test)
reachable_system_population_emerges_from_galaxy_structure :: proc(t: ^testing.T) {
	minimum, maximum, total := MAX_DETAILED_GALACTIC_SYSTEMS, 0, 0
	for seed in u64(
		1,
	) ..= u64(20) {g := generate_galaxy(seed); minimum = min(minimum, g.detailed_system_count); maximum = max(maximum, g.detailed_system_count); total += g.detailed_system_count; for system in g.detailed_systems[:g.detailed_system_count] do testing.expect(t, system.reachability >= .04 && system.reachability <= .92)}
	testing.expect(
		t,
		minimum >= 1,
	); testing.expect(t, maximum > minimum); testing.expect(t, total / 20 > 8)
}

@(test)
galaxy_bulk_properties_are_physically_ordered :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(40) {
		g := generate_galaxy(seed)
		testing.expect(t, g.stellar_mass_solar > 0)
		testing.expect(t, g.dark_matter_halo_mass_solar > g.stellar_mass_solar)
		testing.expect(t, g.estimated_star_count > 0)
		testing.expect(t, g.disk_radius_kpc > 0 && g.scale_height_kpc > 0)
		testing.expect(
			t,
			g.central_black_hole_occupation_chance > 0 &&
			g.central_black_hole_occupation_chance <= 1,
		)
		testing.expect_value(t, g.central_black_hole_mass_solar > 0, g.central_black_hole_occupied)
		testing.expect_value(
			t,
			black_hole_schwarzschild_radius_km(g.central_black_hole_mass_solar) > 0,
			g.central_black_hole_occupied,
		)
		testing.expect(t, g.habitable_zone_inner_kpc < g.habitable_zone_outer_kpc)
		testing.expect(t, g.habitable_zone_outer_kpc <= g.disk_radius_kpc)
	}
}

@(test)
galactic_samples_stay_finite_and_within_structure :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(30) {
		g := generate_galaxy(seed)
		for n in g.neighborhoods[:g.neighborhood_count] {
			testing.expect(t, n.x_kpc == n.x_kpc && n.y_kpc == n.y_kpc && n.z_kpc == n.z_kpc)
			testing.expect(t, abs(n.x_kpc) < 1.0e6 && abs(n.y_kpc) < 1.0e6 && abs(n.z_kpc) < 1.0e6)
			testing.expect(t, n.galactocentric_radius_kpc >= 0)
			testing.expect(t, n.galactocentric_radius_kpc <= g.disk_radius_kpc * 1.01)
			testing.expect(t, n.metallicity_dex >= -2 && n.metallicity_dex <= 0.5)
			testing.expect(
				t,
				n.planet_occurrence_probability >= 0 && n.planet_occurrence_probability <= 1,
			)
		}
	}
}

@(test)
detailed_systems_inherit_local_age_and_metallicity :: proc(t: ^testing.T) {
	g := generate_galaxy(8128)
	testing.expect(t, g.detailed_system_count > 0)
	for sample in g.detailed_systems[:g.detailed_system_count] {
		n := g.neighborhoods[sample.neighborhood_index]
		testing.expect_value(t, sample.metallicity_dex, n.metallicity_dex)
		testing.expect(
			t,
			sample.system.stars[0].profile.age_billion_years <= n.mean_age_billion_years,
		)
		testing.expect(
			t,
			sample.system.stars[0].profile.age_billion_years <=
			max(
				sample.system.stars[0].main_sequence_lifetime_billion_years,
				sample.system.stars[0].profile.age_billion_years,
			),
		)
		testing.expect(t, sample.system.planet_count >= 0)
	}
}

@(test)
galaxy_morphology_sampler_covers_all_structural_models :: proc(t: ^testing.T) {
	seen: [4]bool
	for seed in u64(1) ..= u64(500) {
		g := generate_galaxy(seed)
		seen[int(g.morphology)] = true
	}
	for value in seen do testing.expect(t, value)
}
