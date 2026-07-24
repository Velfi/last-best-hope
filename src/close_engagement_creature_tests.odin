package main

import game "../packages/game"
import "core:testing"

@(test)
creature_render_seed_is_deterministic_and_identity_specific :: proc(t: ^testing.T) {
	a := combat_3d_creature_seed(77, 19, .Lantern_Grazer)
	testing.expect_value(t, a, combat_3d_creature_seed(77, 19, .Lantern_Grazer))
	testing.expect(t, a != combat_3d_creature_seed(77, 20, .Lantern_Grazer))
	testing.expect(t, a != combat_3d_creature_seed(78, 19, .Lantern_Grazer))
}

@(test)
creature_gpu_gene_pack_preserves_the_field_contract :: proc(t: ^testing.T) {
	gene := game.Sdf_Creature_Gene {
		primitive          = .Kaleidoscope_Shell,
		combine            = .Smooth_Subtract,
		role               = .Digestive_Tract,
		center             = {.1, .2, .3, .4},
		radius             = {.5, .6, .7, .8},
		rotation           = {1, 2, 3, 4, 5, 6},
		fractal_iterations = 5,
		fractal_scale      = 1.62,
		fractal_phase      = .71,
		smoothness         = .09,
		motion             = .Fractal_Fold,
		motion_axis        = 3,
		motion_phase       = .2,
		motion_frequency   = .8,
		motion_amplitude   = .25,
		time_center        = 2,
		time_extent        = .6,
	}
	p := combat_3d_pack_creature_gene(&gene)
	testing.expect_value(t, p.meta, [4]f32{10, 2, 4, 5})
	testing.expect_value(t, p.center, [4]f32{.1, .2, .3, .4})
	testing.expect_value(t, p.radius, [4]f32{.5, .6, .7, .8})
	testing.expect_value(t, p.rotation_b, [4]f32{5, 6, .09, 1.62})
	testing.expect_value(t, p.motion_a, [4]f32{5, 3, .2, .8})
	testing.expect_value(t, p.motion_b, [4]f32{.25, 2, .6, .71})
}
