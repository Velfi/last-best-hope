package game

// Shared by the remaining same-package scenario checks and the dedicated game
// test package. It contains no test declarations or dependency on core:testing.
install_test_candidate_home :: proc(c: ^Campaign) -> Celestial_Reference {
	for gs, system_index in c.galaxy.detailed_systems[:c.galaxy.detailed_system_count] {
		if gs.system.planet_count <= 0 do continue
		names := generate_solar_system_names(gs.system)
		p := gs.system.planets[0]
		r := Celestial_Reference {
			valid              = true,
			neighborhood_index = gs.neighborhood_index,
			system_index       = system_index,
			planet_index       = 0,
			system_seed        = gs.system.seed,
			planet_seed        = p.body.seed,
			neighborhood_name  = "Test Neighborhood",
			system_name        = names.proper_name,
			planet_name        = names.planet_names[0],
		}
		profile := candidate_world_profile(c.galaxy, system_index, 0)
		profile.classification = .Engineered_Candidate
		c.candidate_homes[0] = {
			reference = r,
			profile   = profile,
		}
		c.candidate_home_count = 1
		c.candidate_home_known = true
		return r
	}
	return {}
}
