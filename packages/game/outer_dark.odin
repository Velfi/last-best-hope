package game

// Outer_Dark owns only the continuous deterministic manifold. Galaxy
// correspondences live on Dark_Door records; routes, authored sites, projected
// weather, and graph infrastructure have no parallel runtime representation.
Outer_Dark :: struct {
	seed:          u64,
	continuum:     Dark_Continuum,
	semantic_tags: Semantic_Tags,
}

generate_outer_dark_for_galaxy :: proc(seed: u64, galaxy: ^Galaxy) -> Outer_Dark {
	return {
		seed = seed,
		continuum = generate_dark_continuum(seed ~ 0x636f6e74696e7575, galaxy),
		semantic_tags = make_semantic_tags(.Entity, .Environment, .Navigation, .Discovery),
	}
}

generate_outer_dark :: proc(seed: u64) -> Outer_Dark {
	galaxy := generate_galaxy(seed ~ 0x6461726b)
	defer galaxy_destroy(&galaxy)
	return generate_outer_dark_for_galaxy(seed, &galaxy)
}
