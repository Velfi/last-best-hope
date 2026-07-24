package game

import "core:math"

Geometry_4D_Point :: [4]f64
Geometry_3D_Vector :: [3]f64

Sdf_Creature_Primitive :: enum u8 {
	Ellipsoid,
	Capsule,
	Rounded_Box,
	Torus,
	Superellipsoid,
	Double_Lobe,
	Clifford_Torus,
	Lamina,
	Radial_Cross,
	Recursive_Coral,
	Kaleidoscope_Shell,
}

Sdf_Creature_Combine :: enum u8 {
	Smooth_Union,
	Union,
	Smooth_Subtract,
	Subtract,
	Smooth_Intersect,
	Intersect,
}
Sdf_Creature_Gene_Role :: enum u8 {
	Core,
	Appendage,
	Cavity,
	Mouth,
	Digestive_Tract,
	Mask,
	Detail,
}
Sdf_Creature_Motion :: enum u8 {
	Still,
	Pulse,
	Drift,
	Orbit,
	Wave,
	Fractal_Fold,
}

// A gene is a transformed 4D SDF primitive and its operation in an ordered
// CSG program. The fourth coordinate is spatial; inherited motion parameters
// supply the fifth, temporal coordinate without mutating the genome.
Sdf_Creature_Gene :: struct {
	primitive:                                        Sdf_Creature_Primitive,
	combine:                                          Sdf_Creature_Combine,
	role:                                             Sdf_Creature_Gene_Role,
	center:                                           Geometry_4D_Point,
	radius:                                           Geometry_4D_Point,
	// Six plane angles orient anatomy in XY, XZ, XW, YZ, YW, and ZW. A full
	// 4D rotation prevents every lamina, ring, and ossicle sharing world axes.
	rotation:                                         [6]f64,
	fractal_iterations:                               u8,
	fractal_scale, fractal_phase:                     f64,
	smoothness:                                       f64,
	motion:                                           Sdf_Creature_Motion,
	motion_axis:                                      u8,
	motion_phase, motion_frequency, motion_amplitude: f64,
	time_center, time_extent:                         f64,
}

geometry_4d_length :: proc(point: Geometry_4D_Point) -> f64 {
	return math.sqrt(
		point[0] * point[0] + point[1] * point[1] + point[2] * point[2] + point[3] * point[3],
	)
}

geometry_4d_smooth_min :: proc(a, b, smoothing: f64) -> f64 {
	if smoothing <= 0 do return min(a, b)
	h := clamp(0.5 + 0.5 * (b - a) / smoothing, 0.0, 1.0)
	return b * (1 - h) + a * h - smoothing * h * (1 - h)
}

geometry_4d_smooth_max :: proc(a, b, smoothing: f64) -> f64 {
	return -geometry_4d_smooth_min(-a, -b, smoothing)
}

geometry_4d_primitive_distance_prepared :: proc(
	gene: ^Sdf_Creature_Gene,
	point: Geometry_4D_Point,
	rotation_cos, rotation_sin: ^[6]f64,
	coral_cos_a, coral_sin_a, coral_cos_b, coral_sin_b, kaleido_cos, kaleido_sin: ^[5]f64,
) -> f64 {
	q := Geometry_4D_Point{}
	local := Geometry_4D_Point{}
	for axis in 0 ..< 4 do local[axis] = point[axis] - gene.center[axis]
	planes := [6][2]int{{0, 1}, {0, 2}, {0, 3}, {1, 2}, {1, 3}, {2, 3}}
	// Apply the inverse inherited rotation to query the primitive's local field.
	for _, index in gene.rotation {
		a, b :=
			planes[index][0], planes[index][1]; c, s := rotation_cos[index], rotation_sin[index]
		va, vb := local[a], local[b]; local[a] = c * va + s * vb; local[b] = -s * va + c * vb
	}
	minimum_radius := max(gene.radius[0], 0.04)
	for axis in 0 ..< 4 {
		radius := max(gene.radius[axis], 0.04)
		q[axis] = local[axis] / radius
		minimum_radius = min(minimum_radius, radius)
	}
	switch gene.primitive {
	case .Ellipsoid:
		return (geometry_4d_length(q) - 1) * minimum_radius
	case .Rounded_Box:
		o := Geometry_4D_Point{}
		largest := 0.0
		for axis in 0 ..< 4 {
			o[axis] = max(math.abs(q[axis]) - .82, 0.0)
			largest = max(largest, math.abs(q[axis]))
		}
		return (geometry_4d_length(o) + min(largest - .82, 0.0) - .18) * minimum_radius
	case .Superellipsoid:
		sum := 0.0
		for axis in 0 ..< 4 do sum += math.pow(math.abs(q[axis]), 4)
		return (math.pow(sum, .25) - 1) * minimum_radius
	case .Torus:
		ring := math.sqrt(q[0] * q[0] + q[1] * q[1]) - .62
		return (math.sqrt(ring * ring + q[2] * q[2] + q[3] * q[3]) - .38) * minimum_radius * 2.2
	case .Capsule:
		axis := 0
		for i in 1 ..< 4 do if gene.radius[i] > gene.radius[axis] do axis = i
		axial := max(math.abs(q[axis]) - .58, 0.0)
		radial := 0.0
		for i in 0 ..< 4 do if i != axis do radial += q[i] * q[i]
		return (math.sqrt(radial + axial * axial) - .64) * minimum_radius
	case .Double_Lobe:
		axis := 0
		for i in 1 ..< 4 do if gene.radius[i] > gene.radius[axis] do axis = i
		left, right := q, q
		left[axis] -= .48
		right[axis] += .48
		dl := (geometry_4d_length(left) - .72) * minimum_radius
		dr := (geometry_4d_length(right) - .72) * minimum_radius
		return geometry_4d_smooth_min(dl, dr, gene.smoothness * .6)
	case .Clifford_Torus:
		// A thickened Clifford torus: unlike an ordinary torus, both orthogonal
		// coordinate planes carry a ring. W traversal therefore opens, splits,
		// and recombines the visible anatomy instead of merely shrinking it.
		ring_a := math.sqrt(q[0] * q[0] + q[1] * q[1]) - .64
		ring_b := math.sqrt(q[2] * q[2] + q[3] * q[3]) - .64
		return (math.sqrt(ring_a * ring_a + ring_b * ring_b) - .28) * minimum_radius * 1.8
	case .Lamina:
		// A broad, thin 4D sheet. The thinnest inherited axis becomes its
		// thickness, so mutations can turn it edge-on in any spatial dimension.
		thin_axis := 0
		for i in 1 ..< 4 do if gene.radius[i] < gene.radius[thin_axis] do thin_axis = i
		broad := 0.0
		for i in 0 ..< 4 do if i != thin_axis do broad += q[i] * q[i]
		return max(math.sqrt(broad) - 1, math.abs(q[thin_axis]) - .18) * minimum_radius
	case .Radial_Cross:
		// Four mutually perpendicular ossicles share one node. Hyper-slices can
		// reveal three, two, or no visible arms while the 4D body stays connected.
		distance := 1000.0
		for arm_axis in 0 ..< 4 {
			axial := max(math.abs(q[arm_axis]) - .70, 0.0)
			radial := 0.0
			for i in 0 ..< 4 do if i != arm_axis do radial += q[i] * q[i]
			arm := math.sqrt(radial + axial * axial) - .22
			distance = geometry_4d_smooth_min(distance, arm, gene.smoothness * .35)
		}
		return distance * minimum_radius
	case .Recursive_Coral:
		// A bounded iterated fold grows successively smaller buds from a central
		// body. All four coordinates participate, so a 3D slice sees branches
		// appear, merge, and vanish without the 4D organism disconnecting.
		p := q
		distance := (geometry_4d_length(p) - .20) * minimum_radius
		scale := 1.0
		iterations := clamp(int(gene.fractal_iterations), 2, 5)
		fold_scale := clamp(gene.fractal_scale, 1.35, 1.95)
		for iteration in 0 ..< iterations {
			c, s := coral_cos_a[iteration], coral_sin_a[iteration]
			p[0], p[1] = c * p[0] - s * p[1], s * p[0] + c * p[1]
			c2, s2 := coral_cos_b[iteration], coral_sin_b[iteration]
			p[2], p[3] = c2 * p[2] - s2 * p[3], s2 * p[2] + c2 * p[3]
			for &component in p do component = math.abs(component)
			if p[0] < p[1] do p[0], p[1] = p[1], p[0]
			if p[2] < p[3] do p[2], p[3] = p[3], p[2]
			p[0] = (p[0] - .48) * fold_scale; p[1] = (p[1] - .31) * fold_scale
			p[2] = (p[2] - .25) * fold_scale; p[3] = (p[3] - .17) * fold_scale
			scale *= fold_scale
			bud := (geometry_4d_length(p) - (.26 - f64(iteration) * .018)) / scale * minimum_radius
			distance = geometry_4d_smooth_min(distance, bud, gene.smoothness * .38)
		}
		return distance
	case .Kaleidoscope_Shell:
		// Repeated mirror planes corrugate a hollow hypershell. Its animated fold
		// phase moves apertures over the surface rather than translating the body.
		p := q
		for iteration in 0 ..< clamp(int(gene.fractal_iterations), 2, 5) {
			c, s := kaleido_cos[iteration], kaleido_sin[iteration]
			p[0], p[2] = c * p[0] - s * p[2], s * p[0] + c * p[2]
			for &component in p do component = math.abs(component)
			p[0] -= .16; p[1] -= .11; p[2] -= .08; p[3] -= .06
		}
		radial := geometry_4d_length(q)
		corrugation := math.abs(p[0] + p[1] - p[2] - p[3]) * .055
		return (math.abs(radial - .72) - (.105 + corrugation)) * minimum_radius
	}
	return 1000
}

geometry_4d_primitive_distance :: proc(gene: Sdf_Creature_Gene, point: Geometry_4D_Point) -> f64 {
	rotation_cos, rotation_sin := [6]f64{}, [6]f64{}
	for angle, index in gene.rotation {rotation_cos[index] = math.cos(angle); rotation_sin[index] = math.sin(angle)}
	coral_cos_a, coral_sin_a, coral_cos_b, coral_sin_b, kaleido_cos, kaleido_sin :=
		[5]f64{}, [5]f64{}, [5]f64{}, [5]f64{}, [5]f64{}, [5]f64{}
	for iteration in 0 ..< 5 {
		coral_angle := gene.fractal_phase + f64(iteration) * .91
		coral_cos_a[iteration], coral_sin_a[iteration] =
			math.cos(coral_angle), math.sin(coral_angle)
		coral_cos_b[iteration], coral_sin_b[iteration] =
			math.cos(coral_angle * .73), math.sin(coral_angle * .73)
		kaleido_angle := gene.fractal_phase + f64(iteration) * 1.17
		kaleido_cos[iteration], kaleido_sin[iteration] =
			math.cos(kaleido_angle), math.sin(kaleido_angle)
	}
	gene_copy := gene
	return geometry_4d_primitive_distance_prepared(
		&gene_copy,
		point,
		&rotation_cos,
		&rotation_sin,
		&coral_cos_a,
		&coral_sin_a,
		&coral_cos_b,
		&coral_sin_b,
		&kaleido_cos,
		&kaleido_sin,
	)
}

geometry_4d_combine_distance :: proc(
	current, operand: f64,
	operation: Sdf_Creature_Combine,
	smoothing: f64,
) -> f64 {
	switch operation {
	case .Smooth_Union:
		return geometry_4d_smooth_min(current, operand, smoothing)
	case .Union:
		return min(current, operand)
	case .Smooth_Subtract:
		return geometry_4d_smooth_max(current, -operand, smoothing)
	case .Subtract:
		return max(current, -operand)
	case .Smooth_Intersect:
		return geometry_4d_smooth_max(current, operand, smoothing)
	case .Intersect:
		return max(current, operand)
	}
	return current
}

// Central differences in the visible axes produce the normal of a 3D slice
// while holding its fourth coordinate fixed.
geometry_4d_slice_normal :: proc(
	genome: ^Sdf_Creature_Genome,
	point: Geometry_4D_Point,
	epsilon: f64,
) -> (
	normal: Geometry_3D_Vector,
	ok: bool,
) {
	if epsilon <= 0 do return {}, false
	for axis in 0 ..< 3 {
		before, after := point, point
		before[axis] -= epsilon
		after[axis] += epsilon
		normal[axis] = sdf_creature_distance(genome, after) - sdf_creature_distance(genome, before)
	}
	length := math.sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2])
	if length <= 1e-12 do return {}, false
	for &component in normal do component /= length
	return normal, true
}
