package game_tests

import "core:math"
import "core:testing"

geometry_4d_close :: proc(a, b: f64, tolerance := 1e-9) -> bool {
	return math.abs(a - b) <= tolerance
}

@(test)
geometry_4d_length_and_smoothing_obey_known_values :: proc(t: ^testing.T) {
	testing.expect(t, geometry_4d_close(geometry_4d_length({1, 2, 2, 4}), 5))
	testing.expect(t, geometry_4d_close(geometry_4d_smooth_min(2, 5, 0), 2))
	testing.expect(t, geometry_4d_close(geometry_4d_smooth_max(2, 5, 0), 5))
	testing.expect(t, geometry_4d_close(geometry_4d_smooth_min(0, 0, .4), -.1))
	testing.expect(t, geometry_4d_close(geometry_4d_smooth_max(0, 0, .4), .1))
}

@(test)
geometry_4d_primitives_classify_center_surface_and_exterior :: proc(t: ^testing.T) {
	for primitive in Sdf_Creature_Primitive {
		gene := Sdf_Creature_Gene {
			primitive  = primitive,
			radius     = {1, 1, 1, 1},
			smoothness = .1,
		}
		inside := Geometry_4D_Point{}
		if primitive == .Torus do inside = {.62, 0, 0, 0}
		if primitive == .Clifford_Torus do inside = {.64, 0, .64, 0}
		if primitive == .Kaleidoscope_Shell do inside = {.72, 0, 0, 0}
		testing.expect(t, geometry_4d_primitive_distance(gene, inside) <= 0)
		testing.expect(t, geometry_4d_primitive_distance(gene, {3, 3, 3, 3}) > 0)
	}
	unit := Sdf_Creature_Gene {
		primitive = .Ellipsoid,
		radius    = {1, 1, 1, 1},
	}
	testing.expect(t, geometry_4d_close(geometry_4d_primitive_distance(unit, {1, 0, 0, 0}), 0))
	testing.expect(t, geometry_4d_close(geometry_4d_primitive_distance(unit, {0, 0, 0, 2}), 1))
}

@(test)
geometry_4d_primitives_respect_translation_and_uniform_scale :: proc(t: ^testing.T) {
	gene := Sdf_Creature_Gene {
		primitive = .Ellipsoid,
		center    = {2, -3, 4, -5},
		radius    = {2, 2, 2, 2},
	}
	testing.expect(t, geometry_4d_close(geometry_4d_primitive_distance(gene, {2, -3, 4, -5}), -2))
	testing.expect(t, geometry_4d_close(geometry_4d_primitive_distance(gene, {4, -3, 4, -5}), 0))
	testing.expect(t, geometry_4d_close(geometry_4d_primitive_distance(gene, {6, -3, 4, -5}), 2))
}

@(test)
geometry_4d_gene_rotation_orients_anisotropic_anatomy :: proc(t: ^testing.T) {
	gene := Sdf_Creature_Gene {
		primitive = .Ellipsoid,
		radius    = {1, .25, .25, .25},
	}
	testing.expect(t, geometry_4d_primitive_distance(gene, {.8, 0, 0, 0}) < 0)
	testing.expect(t, geometry_4d_primitive_distance(gene, {0, .8, 0, 0}) > 0)
	gene.rotation[0] = math.PI * .5
	testing.expect(t, geometry_4d_primitive_distance(gene, {.8, 0, 0, 0}) > 0)
	testing.expect(t, geometry_4d_primitive_distance(gene, {0, .8, 0, 0}) < 0)
	// Rotation never displaces the inherited attachment point.
	testing.expect(t, geometry_4d_primitive_distance(gene, {0, 0, 0, 0}) < 0)
}

@(test)
geometry_4d_clifford_torus_changes_manifestation_across_w :: proc(t: ^testing.T) {
	gene := Sdf_Creature_Gene {
		primitive = .Clifford_Torus,
		radius    = {1, 1, 1, 1},
	}
	// The origin is the void between both rings. Different visible points join
	// the body as w traverses its second coordinate plane, then the body vanishes.
	testing.expect(t, geometry_4d_primitive_distance(gene, {0, 0, 0, 0}) > 0)
	testing.expect(t, geometry_4d_primitive_distance(gene, {.64, 0, .64, 0}) < 0)
	testing.expect(t, geometry_4d_primitive_distance(gene, {.64, 0, 0, .64}) < 0)
	testing.expect(t, geometry_4d_primitive_distance(gene, {.64, 0, 0, 1.4}) > 0)
}

@(test)
geometry_4d_csg_operations_match_set_semantics :: proc(t: ^testing.T) {
	// Negative means inside: A is inside and B is outside at this sample.
	a, b := -2.0, 3.0
	testing.expect(t, geometry_4d_close(geometry_4d_combine_distance(a, b, .Union, 0), -2))
	testing.expect(t, geometry_4d_close(geometry_4d_combine_distance(a, b, .Intersect, 0), 3))
	testing.expect(t, geometry_4d_close(geometry_4d_combine_distance(a, b, .Subtract, 0), -2))
	testing.expect(t, geometry_4d_close(geometry_4d_combine_distance(a, -.5, .Subtract, 0), .5))
	testing.expect(t, geometry_4d_combine_distance(a, b, .Smooth_Union, .2) <= min(a, b))
	testing.expect(t, geometry_4d_combine_distance(a, b, .Smooth_Intersect, .2) >= max(a, b))
}

@(test)
geometry_4d_slice_normal_is_unit_outward_and_holds_w_constant :: proc(t: ^testing.T) {
	genome := Sdf_Creature_Genome {
		gene_count = 1,
	}
	genome.genes[0] = {
		primitive = .Ellipsoid,
		radius    = {1, 1, 1, 1},
	}
	normal, ok := geometry_4d_slice_normal(&genome, {1, 0, 0, .5}, 1e-5)
	testing.expect(t, ok)
	testing.expect(t, geometry_4d_close(normal[0], 1, 1e-8))
	testing.expect(t, geometry_4d_close(normal[1], 0, 1e-8))
	testing.expect(t, geometry_4d_close(normal[2], 0, 1e-8))
	_, zero_ok := geometry_4d_slice_normal(&genome, {0, 0, 0, 0}, 1e-5)
	testing.expect(t, !zero_ok)
	_, invalid_ok := geometry_4d_slice_normal(&genome, {1, 0, 0, 0}, 0)
	testing.expect(t, !invalid_ok)
}
