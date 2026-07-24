package game_tests

import "core:math"
import "core:testing"

@(test)
sdf_creature_generation_and_evolution_are_seed_deterministic :: proc(t: ^testing.T) {
	a := evolve_sdf_creature(4404, 4)
	b := evolve_sdf_creature(4404, 4)
	testing.expect_value(t, a.creature, b.creature)
	testing.expect_value(t, a.fitness, b.fitness)
	testing.expect_value(t, a.evaluations, SDF_CREATURE_POPULATION * 5)
}

@(test)
sdf_creature_evolution_preserves_or_improves_the_best_candidate :: proc(t: ^testing.T) {
	result := evolve_sdf_creature(9917, 6)
	testing.expect(t, result.fitness.total >= result.initial_best)
	testing.expect(t, result.fitness.continuity > 0)
	testing.expect(t, result.creature.gene_count >= 4)
	testing.expect(t, result.creature.gene_count <= SDF_CREATURE_MAX_GENES)
}

@(test)
sdf_creature_fourth_axis_changes_the_visible_slice :: proc(t: ^testing.T) {
	genome := Sdf_Creature_Genome {
		gene_count = 1,
	}
	genome.genes[0] = {
		primitive  = .Ellipsoid,
		combine    = .Smooth_Union,
		center     = {0, 0, 0, 0},
		radius     = {0.5, 0.5, 0.5, 0.5},
		smoothness = 0.1,
	}
	testing.expect(t, sdf_creature_distance(&genome, {0, 0, 0, 0}) < 0)
	testing.expect(t, sdf_creature_distance(&genome, {0, 0, 0, 0.75}) > 0)
}

@(test)
sdf_creature_fifth_axis_animates_deterministically :: proc(t: ^testing.T) {
	genome := Sdf_Creature_Genome {
		gene_count = 1,
	}
	genome.genes[0] = {
		primitive        = .Ellipsoid,
		combine          = .Smooth_Union,
		radius           = {.5, .5, .5, .5},
		motion           = .Drift,
		motion_axis      = 0,
		motion_frequency = 1,
		motion_amplitude = .25,
	}
	rest := sdf_creature_distance_at(&genome, {.45, 0, 0, 0}, 0)
	moved := sdf_creature_distance_at(&genome, {.45, 0, 0, 0}, math.PI / 2)
	repeated := sdf_creature_distance_at(&genome, {.45, 0, 0, 0}, math.PI * 2)
	testing.expect(t, math.abs(rest - moved) > .1)
	testing.expect(t, math.abs(rest - repeated) < .000001)
}

@(test)
sdf_creature_fractal_fold_animates_internal_anatomy :: proc(t: ^testing.T) {
	genome := Sdf_Creature_Genome {
		gene_count = 1,
	}
	genome.genes[0] = {
		primitive          = .Recursive_Coral,
		combine            = .Smooth_Union,
		radius             = {.7, .7, .7, .7},
		fractal_iterations = 4,
		fractal_scale      = 1.62,
		motion             = .Fractal_Fold,
		motion_frequency   = 1,
		motion_amplitude   = .22,
	}
	difference := 0.0
	for z in -3 ..= 3 do for y in -3 ..= 3 do for x in -3 ..= 3 {
		point := [4]f64{f64(x) * .18, f64(y) * .18, f64(z) * .18, .12}
		difference += math.abs(sdf_creature_distance_at(&genome, point, 0) - sdf_creature_distance_at(&genome, point, math.PI * .5))
	}
	testing.expect(t, difference > .25)
	testing.expect_value(t, genome.genes[0].center, [4]f64{})
}

@(test)
sdf_creature_prepared_sampling_matches_direct_field :: proc(t: ^testing.T) {
	genome := generate_sdf_creature(7341)
	times := [3]f64{0, .73, 2.1}
	for sample_time in times {
		prepared := sdf_creature_prepare_at(&genome, sample_time)
		for z in -2 ..= 2 do for y in -2 ..= 2 do for x in -2 ..= 2 {
			point := [4]f64{f64(x) * .31, f64(y) * .27, f64(z) * .29, f64(x - y) * .11}
			direct := sdf_creature_distance_at(&genome, point, sample_time)
			cached := sdf_creature_prepared_distance(&prepared, point)
			testing.expect(t, math.abs(direct - cached) < 1e-12)
		}
	}
}

@(test)
sdf_creature_temporal_extent_can_grow_and_shed_tissue :: proc(t: ^testing.T) {
	genome := Sdf_Creature_Genome {
		gene_count = 1,
	}
	genome.genes[0] = {
		primitive   = .Ellipsoid,
		combine     = .Smooth_Union,
		radius      = {.5, .5, .5, .5},
		time_extent = 1,
	}
	testing.expect(t, sdf_creature_distance_at(&genome, {0, 0, 0, 0}, 0) < 0)
	testing.expect(t, sdf_creature_distance_at(&genome, {0, 0, 0, 0}, 4) > 0)
}

@(test)
sdf_creature_primitive_and_csg_vocabulary_produce_distinct_fields :: proc(t: ^testing.T) {
	for primitive in Sdf_Creature_Primitive {
		g := Sdf_Creature_Genome {
			gene_count = 1,
		}; g.genes[0] = {
			primitive  = primitive,
			combine    = .Smooth_Union,
			radius     = {.6, .5, .4, .7},
			smoothness = .12,
		}
		testing.expect(t, sdf_creature_distance(&g, {0, 0, 0, 0}) < .5)
	}
	base := Sdf_Creature_Genome {
		gene_count = 2,
	}
	base.genes[0] = {
		primitive = .Ellipsoid,
		combine   = .Union,
		radius    = {.8, .8, .8, .8},
	}
	base.genes[1] = {
		primitive = .Ellipsoid,
		combine   = .Subtract,
		radius    = {.3, .3, .3, .3},
	}
	testing.expect(t, sdf_creature_distance(&base, {0, 0, 0, 0}) > 0)
	testing.expect(t, sdf_creature_distance(&base, {.6, 0, 0, 0}) < 0)
}

@(test)
sdf_creature_configuration_bounds_the_initial_body_plan :: proc(t: ^testing.T) {
	config := SDF_CREATURE_DEFAULT_CONFIG
	config.minimum_genes, config.maximum_genes = 9, 12
	for seed in u64(1) ..= u64(16) {
		genome := generate_sdf_creature_configured(seed, config)
		testing.expect(t, genome.gene_count >= 9 && genome.gene_count <= 12)
	}
}

@(test)
sdf_creature_development_and_quality_diversity_preserve_niches :: proc(t: ^testing.T) {
	genome := generate_sdf_creature(404)
	testing.expect_value(t, genome.genes[0].role, Sdf_Creature_Gene_Role.Core)
	testing.expect_value(t, genome.genes[0].combine, Sdf_Creature_Combine.Smooth_Union)
	result := evolve_sdf_creature(404, 8)
	testing.expect(
		t,
		result.archive_cells >= 2 && result.archive_cells <= SDF_CREATURE_ARCHIVE_CELLS,
	)
	testing.expect(t, result.fitness.total >= result.initial_best)
}

@(test)
sdf_creature_seeded_development_reaches_alien_shape_motifs :: proc(t: ^testing.T) {
	seen_clifford, seen_lamina, seen_cross, seen_fractal := false, false, false, false
	for seed in u64(1) ..= u64(64) {
		genome := generate_sdf_creature(seed)
		for gene in genome.genes[:genome.gene_count] {
			#partial switch gene.primitive {
			case .Clifford_Torus:
				seen_clifford = true
			case .Lamina:
				seen_lamina = true
			case .Radial_Cross:
				seen_cross = true
			case .Recursive_Coral, .Kaleidoscope_Shell:
				seen_fractal = true
			}
		}
	}
	testing.expect(t, seen_clifford && seen_lamina && seen_cross && seen_fractal)
}

@(test)
sdf_creature_develops_mouth_gut_and_multiple_fractal_fields :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(32) {
		genome := generate_sdf_creature(seed)
		testing.expect_value(t, genome.genes[1].role, Sdf_Creature_Gene_Role.Mouth)
		testing.expect_value(t, genome.genes[2].role, Sdf_Creature_Gene_Role.Digestive_Tract)
		fractals := 0
		for gene in genome.genes[:genome.gene_count] do if gene.primitive == .Recursive_Coral || gene.primitive == .Kaleidoscope_Shell do fractals += 1
		testing.expect(t, fractals >= 3)
	}
}

@(test)
sdf_creature_development_seeds_a_reflected_appendage_pair :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(24) {
		genome := generate_sdf_creature(seed)
		a, b := genome.genes[5], genome.genes[6]
		testing.expect_value(t, a.role, Sdf_Creature_Gene_Role.Appendage)
		testing.expect_value(t, b.role, Sdf_Creature_Gene_Role.Appendage)
		testing.expect(t, math.abs(a.center[0] + b.center[0]) < 1e-12)
		for axis in 1 ..< 4 do testing.expect(t, math.abs(a.center[axis] - b.center[axis]) < 1e-12)
		for plane in 0 ..< 3 do testing.expect(t, math.abs(a.rotation[plane] + b.rotation[plane]) < 1e-12)
	}
}

@(test)
sdf_creature_fitness_recognizes_visible_internal_voids :: proc(t: ^testing.T) {
	genome := Sdf_Creature_Genome {
		gene_count = 2,
	}
	genome.genes[0] = {
		primitive = .Ellipsoid,
		combine   = .Smooth_Union,
		role      = .Core,
		radius    = {1, 1, 1, 1},
	}
	genome.genes[1] = {
		primitive = .Torus,
		combine   = .Subtract,
		role      = .Mouth,
		radius    = {.82, .82, .82, .82},
	}
	fitness := sdf_creature_evaluate(&genome)
	testing.expect(t, fitness.void_expression > 0)
}

@(test)
sdf_creature_fitness_biases_symmetric_3d_cross_sections :: proc(t: ^testing.T) {
	symmetric := Sdf_Creature_Genome {
		gene_count = 1,
	}
	symmetric.genes[0] = {
		primitive = .Ellipsoid,
		combine   = .Smooth_Union,
		role      = .Core,
		radius    = {.75, .60, .50, .70},
	}
	asymmetric := symmetric
	asymmetric.gene_count = 2
	asymmetric.genes[1] = {
		primitive  = .Ellipsoid,
		combine    = .Smooth_Union,
		role       = .Detail,
		center     = {.58, .32, -.18, 0},
		radius     = {.42, .34, .31, .42},
		smoothness = .04,
	}
	symmetric_fitness := sdf_creature_evaluate(&symmetric)
	asymmetric_fitness := sdf_creature_evaluate(&asymmetric)
	testing.expect(t, symmetric_fitness.symmetry > .92)
	testing.expect(t, symmetric_fitness.symmetry > asymmetric_fitness.symmetry)
	testing.expect(t, symmetric_fitness.total > asymmetric_fitness.total)
}
