package game

import "core:math"

SDF_CREATURE_MAX_GENES :: 12
SDF_CREATURE_POPULATION :: 20
SDF_CREATURE_GRID :: 9
SDF_CREATURE_SLICES :: 5
SDF_CREATURE_ARCHIVE_CELLS :: 36

Sdf_Creature_Genome :: struct {
	seed:       u64,
	genes:      [SDF_CREATURE_MAX_GENES]Sdf_Creature_Gene,
	gene_count: int,
}

Sdf_Creature_Fitness :: struct {
	total:                                                                        f64,
	complexity:                                                                   f64,
	continuity:                                                                   f64,
	variation:                                                                    f64,
	occupancy:                                                                    f64,
	asymmetry:                                                                    f64,
	viable:                                                                       bool,
	components, appendages:                                                       int,
	topology_change, temporal_change, void_expression, surface_density, symmetry: f64,
}

Sdf_Creature_Evolution :: struct {
	creature:      Sdf_Creature_Genome,
	fitness:       Sdf_Creature_Fitness,
	initial_best:  f64,
	generations:   int,
	evaluations:   int,
	archive_cells: int,
}

// Presentation and tools query the same genome thousands of times at one T.
// Prepare time deformation and rotation coefficients once for that sampling
// batch instead of repeating transcendental work at every point.
Sdf_Creature_Prepared :: struct {
	genes:                                                                        [SDF_CREATURE_MAX_GENES]Sdf_Creature_Gene,
	rotation_cos,
	rotation_sin:                                                   [SDF_CREATURE_MAX_GENES][6]f64,
	coral_cos_a,
	coral_sin_a,
	coral_cos_b,
	coral_sin_b,
	kaleido_cos,
	kaleido_sin: [SDF_CREATURE_MAX_GENES][5]f64,
	gene_count:                                                                   int,
	time:                                                                         f64,
}

sdf_creature_archive_cell :: proc(f: Sdf_Creature_Fitness) -> int {
	appendage_band := min(
		f.appendages / 2,
		3,
	); symmetry_band := f.symmetry < .55 ? 0 : f.symmetry < .82 ? 1 : 2; change_band := f.topology_change < .28 ? 0 : f.topology_change < .66 ? 1 : 2
	return appendage_band + symmetry_band * 4 + change_band * 12
}

Sdf_Creature_Evolution_Config :: struct {
	generations:     int,
	minimum_genes:   int,
	maximum_genes:   int,
	mutation_amount: f64,
}

SDF_CREATURE_DEFAULT_CONFIG :: Sdf_Creature_Evolution_Config {
	generations     = 24,
	minimum_genes   = 8,
	maximum_genes   = 12,
	mutation_amount = 0.16,
}

sdf_creature_clamp :: proc(value, low, high: f64) -> f64 {
	return min(max(value, low), high)
}

// Negative values are inside. Genes form an ordered CSG program, allowing the
// same primitive vocabulary to add tissue, carve it, or constrain it.
sdf_creature_distance :: proc(genome: ^Sdf_Creature_Genome, point: [4]f64) -> f64 {
	return sdf_creature_distance_at(genome, point, 0)
}

// World queries keep the inherited SDF in organism-local coordinates. Scale
// is uniform so the returned value remains a conservative distance estimate.
sdf_creature_world_distance_at :: proc(
	genome: ^Sdf_Creature_Genome,
	world_point, world_center: [4]f64,
	scale, time: f64,
) -> f64 {
	if scale <= 0 do return 1000
	local: [4]f64; for axis in 0 ..< 4 do local[axis] = (world_point[axis] - world_center[axis]) / scale
	return sdf_creature_distance_at(genome, local, time) * scale
}

sdf_creature_gradient_4d_at :: proc(
	genome: ^Sdf_Creature_Genome,
	point: [4]f64,
	time, epsilon: f64,
) -> (
	normal: [4]f64,
	ok: bool,
) {
	if epsilon <= 0 do return {}, false
	for axis in 0 ..< 4 {before, after := point, point; before[axis] -= epsilon; after[axis] += epsilon; normal[axis] = sdf_creature_distance_at(genome, after, time) - sdf_creature_distance_at(genome, before, time)}
	length := geometry_4d_length(normal); if length <= 1e-12 do return {}, false
	for &component in normal do component /= length
	return normal, true
}

// Conservative body contact samples each body's center against the other SDF
// and combines that with bounding hyperspheres. It cannot report contact for
// bodies separated only along w, which is the critical 4D invariant.
sdf_creatures_contact_at :: proc(
	a: ^Sdf_Creature_Genome,
	a_center: [4]f64,
	a_scale: f64,
	b: ^Sdf_Creature_Genome,
	b_center: [4]f64,
	b_scale, time: f64,
) -> (
	penetration: f64,
	contact: bool,
) {
	center_distance := geometry_4d_length(dark_vec4_sub(b_center, a_center))
	if center_distance > a_scale * 1.8 + b_scale * 1.8 do return 0, false
	da := sdf_creature_world_distance_at(a, b_center, a_center, a_scale, time)
	db := sdf_creature_world_distance_at(b, a_center, b_center, b_scale, time)
	separation := min(da, db)
	return max(-separation, 0), separation <= 0
}

sdf_swept_hyperspheres_contact :: proc(
	a0, a1: [4]f64,
	a_radius: f64,
	b0, b1: [4]f64,
	b_radius: f64,
) -> bool {
	relative_start := dark_vec4_sub(
		a0,
		b0,
	); relative_delta := dark_vec4_sub(dark_vec4_sub(a1, a0), dark_vec4_sub(b1, b0)); denominator := dark_vec4_dot(relative_delta, relative_delta); t := 0.0; if denominator > 1e-12 do t = clamp(-dark_vec4_dot(relative_start, relative_delta) / denominator, 0, 1)
	closest := dark_vec4_add(relative_start, dark_vec4_scale(relative_delta, t))
	return dark_vec4_length(closest) <= a_radius + b_radius
}

sdf_creature_animated_gene :: proc(gene: Sdf_Creature_Gene, time: f64) -> Sdf_Creature_Gene {
	animated := gene
	phase := gene.motion_phase + time * gene.motion_frequency
	axis := int(gene.motion_axis % 4)
	switch gene.motion {
	case .Still:
	case .Pulse:
		scale := sdf_creature_clamp(1 + gene.motion_amplitude * math.sin(phase), .55, 1.45)
		for i in 0 ..< 4 do animated.radius[i] *= scale
	case .Drift:
		animated.center[axis] += gene.motion_amplitude * math.sin(phase)
	case .Orbit:
		animated.center[axis] += gene.motion_amplitude * math.sin(phase)
		animated.center[(axis + 1) % 4] += gene.motion_amplitude * math.cos(phase)
	case .Wave:
		for i in 0 ..< 4 do animated.center[i] += gene.motion_amplitude * math.sin(phase + f64(i) * .83) * .55
	case .Fractal_Fold:
		animated.fractal_phase += gene.motion_amplitude * 4.5 * math.sin(phase)
		animated.fractal_scale = sdf_creature_clamp(
			gene.fractal_scale * (1 + gene.motion_amplitude * .32 * math.cos(phase)),
			1.35,
			1.95,
		)
	}
	return animated
}

sdf_creature_prepare_at :: proc(genome: ^Sdf_Creature_Genome, time: f64) -> Sdf_Creature_Prepared {
	prepared := Sdf_Creature_Prepared {
		gene_count = genome.gene_count,
		time       = time,
	}
	for gene, index in genome.genes[:genome.gene_count] {
		prepared.genes[index] = sdf_creature_animated_gene(gene, time)
		for angle, plane in prepared.genes[index].rotation {
			prepared.rotation_cos[index][plane] = math.cos(angle)
			prepared.rotation_sin[index][plane] = math.sin(angle)
		}
		for iteration in 0 ..< 5 {
			coral_angle := prepared.genes[index].fractal_phase + f64(iteration) * .91
			prepared.coral_cos_a[index][iteration], prepared.coral_sin_a[index][iteration] =
				math.cos(coral_angle), math.sin(coral_angle)
			prepared.coral_cos_b[index][iteration], prepared.coral_sin_b[index][iteration] =
				math.cos(coral_angle * .73), math.sin(coral_angle * .73)
			kaleido_angle := prepared.genes[index].fractal_phase + f64(iteration) * 1.17
			prepared.kaleido_cos[index][iteration], prepared.kaleido_sin[index][iteration] =
				math.cos(kaleido_angle), math.sin(kaleido_angle)
		}
	}
	return prepared
}

sdf_creature_prepared_distance :: proc(prepared: ^Sdf_Creature_Prepared, point: [4]f64) -> f64 {
	distance := 1000.0
	for &gene, index in prepared.genes[:prepared.gene_count] {
		operand := geometry_4d_primitive_distance_prepared(
			&gene,
			point,
			&prepared.rotation_cos[index],
			&prepared.rotation_sin[index],
			&prepared.coral_cos_a[index],
			&prepared.coral_sin_a[index],
			&prepared.coral_cos_b[index],
			&prepared.coral_sin_b[index],
			&prepared.kaleido_cos[index],
			&prepared.kaleido_sin[index],
		)
		if gene.time_extent > 0 {
			time_distance := (math.abs(prepared.time - gene.time_center) - gene.time_extent) * .18
			operand = geometry_4d_smooth_max(operand, time_distance, gene.smoothness)
		}
		if index == 0 {distance = operand; continue}
		distance = geometry_4d_combine_distance(distance, operand, gene.combine, gene.smoothness)
	}
	return distance
}

sdf_creature_prepared_slice_normal :: proc(
	prepared: ^Sdf_Creature_Prepared,
	point: [4]f64,
	epsilon: f64,
) -> (
	normal: [3]f64,
	ok: bool,
) {
	for axis in 0 ..< 3 {a, b := point, point; a[axis] -= epsilon; b[axis] += epsilon; normal[axis] = sdf_creature_prepared_distance(prepared, b) - sdf_creature_prepared_distance(prepared, a)}
	length := math.sqrt(
		normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2],
	); if length < .000001 do return {}, false
	for axis in 0 ..< 3 do normal[axis] /= length
	return normal, true
}

// A creature is a five-dimensional field F(x,y,z,w,t). Time deforms the
// inherited four-dimensional anatomy; querying the same seed and time is exact.
sdf_creature_distance_at :: proc(genome: ^Sdf_Creature_Genome, point: [4]f64, time: f64) -> f64 {
	distance := 1000.0
	for gene, index in genome.genes[:genome.gene_count] {
		animated := sdf_creature_animated_gene(gene, time)
		operand := geometry_4d_primitive_distance(animated, point)
		if gene.time_extent > 0 {
			time_distance := (math.abs(time - gene.time_center) - gene.time_extent) * .18
			operand = geometry_4d_smooth_max(operand, time_distance, gene.smoothness)
		}
		if index == 0 {distance = operand; continue}
		distance = geometry_4d_combine_distance(distance, operand, gene.combine, gene.smoothness)
	}
	return distance
}

sdf_creature_slice_normal_at :: proc(
	genome: ^Sdf_Creature_Genome,
	point: [4]f64,
	time, epsilon: f64,
) -> (
	normal: [3]f64,
	ok: bool,
) {
	for axis in 0 ..< 3 {a, b := point, point; a[axis] -= epsilon; b[axis] += epsilon; normal[axis] = sdf_creature_distance_at(genome, b, time) - sdf_creature_distance_at(genome, a, time)}
	length := math.sqrt(
		normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2],
	); if length < .000001 do return {}, false
	for axis in 0 ..< 3 do normal[axis] /= length
	return normal, true
}

sdf_creature_random_gene :: proc(state: ^u64, index: int) -> Sdf_Creature_Gene {
	gene := Sdf_Creature_Gene{}
	gene.primitive = Sdf_Creature_Primitive(
		planet_rng_next(state) % u64(len(Sdf_Creature_Primitive)),
	)
	roll := planet_random_unit(state)
	gene.combine =
		index == 0 ? .Smooth_Union : roll < .55 ? .Smooth_Union : roll < .68 ? .Union : roll < .82 ? .Smooth_Subtract : roll < .90 ? .Subtract : roll < .96 ? .Smooth_Intersect : .Intersect
	for axis in 0 ..< 4 {
		gene.center[axis] = planet_random_range(state, -0.62, 0.62)
		gene.radius[axis] = planet_random_range(state, 0.18, 0.72)
	}
	for &angle in gene.rotation do angle = planet_random_range(state, -math.PI, math.PI)
	gene.fractal_iterations = u8(3 + planet_rng_next(state) % 3)
	gene.fractal_scale = planet_random_range(state, 1.45, 1.82)
	gene.fractal_phase = planet_random_range(state, -math.PI, math.PI)
	// Bias one axis toward limbs/shells without prescribing a recognizable animal.
	long_axis := int(planet_rng_next(state) % 4)
	gene.radius[long_axis] = planet_random_range(state, 0.55, 1.0)
	gene.smoothness = planet_random_range(state, 0.04, 0.24)
	return gene
}

sdf_creature_develop_gene :: proc(
	state: ^u64,
	index: int,
	previous: Sdf_Creature_Gene,
) -> Sdf_Creature_Gene {
	gene := sdf_creature_random_gene(state, index)
	gene.motion_phase = planet_random_range(
		state,
		0,
		math.PI * 2,
	); gene.motion_frequency = planet_random_range(state, .35, 1.05); gene.motion_amplitude = planet_random_range(state, .035, .16); gene.motion_axis = u8(planet_rng_next(state) % 4)
	if index == 0 {
		gene.role = .Core; gene.combine = .Smooth_Union; core_roll := planet_random_unit(state)
		gene.primitive =
			core_roll < .08 ? .Ellipsoid : core_roll < .14 ? .Capsule : core_roll < .22 ? .Lamina : core_roll < .30 ? .Radial_Cross : core_roll < .50 ? .Clifford_Torus : core_roll < .76 ? .Recursive_Coral : .Kaleidoscope_Shell
		gene.center = {
			0,
			0,
			0,
			0,
		}; for axis in 0 ..< 4 do gene.radius[axis] = planet_random_range(state, .34, .68)
		if gene.primitive ==
		   .Lamina {thin := int(planet_rng_next(state) % 4); gene.radius[thin] = planet_random_range(state, .12, .28)}
		gene.motion =
			(gene.primitive == .Recursive_Coral || gene.primitive == .Kaleidoscope_Shell) ? .Fractal_Fold : .Pulse; gene.motion_amplitude = gene.motion == .Fractal_Fold ? planet_random_range(state, .18, .34) : planet_random_range(state, .025, .075); return gene
	}
	roll := planet_random_unit(state)
	gene.role =
		index == 1 ? .Mouth : index == 2 ? .Digestive_Tract : index == 3 ? .Detail : (index == 4 || index == 5 || index == 6) ? .Appendage : roll < .48 ? .Appendage : roll < .62 ? .Cavity : roll < .76 ? .Digestive_Tract : roll < .96 ? .Detail : .Mask
	switch gene.role {
	case .Appendage:
		gene.combine = .Smooth_Union; appendage_roll := planet_random_unit(state); gene.primitive =
			appendage_roll < .32 ? .Capsule : appendage_roll < .48 ? .Double_Lobe : appendage_roll < .64 ? .Lamina : appendage_roll < .78 ? .Radial_Cross : appendage_roll < .91 ? .Recursive_Coral : .Kaleidoscope_Shell
		gene.smoothness = planet_random_range(state, .018, .075)
		axis := int(planet_rng_next(state) % 4)
		sign := planet_random_unit(state) < .5 ? -1.0 : 1.0
		gene.center = previous.center
		gene.center[axis] += sign * (previous.radius[axis] * 1.02 + gene.radius[axis] * .72)
		gene.radius[axis] = max(gene.radius[axis], .72)
		for a in 0 ..< 4 do if a != axis do gene.radius[a] *= .24
		gene.motion =
			(gene.primitive == .Recursive_Coral || gene.primitive == .Kaleidoscope_Shell) ? .Fractal_Fold : (planet_random_unit(state) < .68 ? .Wave : .Orbit)
		gene.motion_axis = u8(axis)
		gene.motion_frequency = max(
			previous.motion_frequency + planet_random_range(state, -.12, .12),
			.18,
		)
		gene.motion_phase = previous.motion_phase + planet_random_range(state, .25, 1.15)
		if index ==
		   4 {gene.primitive = .Recursive_Coral; gene.fractal_iterations = 5; gene.fractal_scale = planet_random_range(state, 1.46, 1.70); gene.center = {}; gene.rotation = {}; for a in 0 ..< 4 do gene.radius[a] = planet_random_range(state, .34, .62); gene.motion = .Fractal_Fold}
		if gene.motion == .Fractal_Fold do gene.motion_amplitude = max(gene.motion_amplitude, .18)
	case .Cavity:
		gene.combine = planet_random_unit(state) < .72 ? .Smooth_Subtract : .Subtract
		cavity_roll := planet_random_unit(state)
		gene.primitive =
			cavity_roll < .46 ? .Ellipsoid : cavity_roll < .76 ? .Torus : .Clifford_Torus
		gene.center = previous.center
		for a in 0 ..< 4 do gene.center[a] += planet_random_range(state, -previous.radius[a] * .3, previous.radius[a] * .3)
		for a in 0 ..< 4 do gene.radius[a] *= .52
		gene.motion = planet_random_unit(state) < .7 ? .Pulse : .Drift
		gene.motion_amplitude *= .6
	case .Mouth:
		// The first bud is a guaranteed surface-breaking aperture. Oblique tori
		// and hypertori read as mouths while remaining unlike terrestrial jaws.
		gene.combine = .Smooth_Subtract; gene.primitive = planet_random_unit(state) < .68 ? .Torus : .Clifford_Torus
		axis := 2; sign := planet_random_unit(state) < .5 ? -1.0 : 1.0; gene.center = previous.center; gene.center[axis] += sign * previous.radius[axis] * .58
		for a in 0 ..< 4 do gene.radius[a] = previous.radius[a] * planet_random_range(state, .48, .68)
		gene.radius[axis] = previous.radius[axis] * .88
		// Mouths share a readable facing while retaining a small, seeded obliquity.
		gene.rotation = {
			planet_random_range(state, -.35, .35),
			planet_random_range(state, -.24, .24),
			planet_random_range(state, -.18, .18),
			planet_random_range(state, -.24, .24),
			planet_random_range(state, -.18, .18),
			planet_random_range(state, -.18, .18),
		}
		gene.smoothness = planet_random_range(
			state,
			.025,
			.065,
		); gene.motion = .Pulse; gene.motion_amplitude = planet_random_range(state, .04, .10)
	case .Digestive_Tract:
		// A recursive subtraction bores a branching gut through the higher body.
		// Its connected 4D field can manifest as several separate visible lumens.
		gene.combine = .Smooth_Subtract; gene.primitive = planet_random_unit(state) < .72 ? .Recursive_Coral : .Kaleidoscope_Shell; gene.center = previous.center
		for a in 0 ..< 4 do gene.radius[a] = previous.radius[a] * planet_random_range(state, .55, .82)
		gene.fractal_iterations = u8(
			4 + planet_rng_next(state) % 2,
		); gene.fractal_scale = planet_random_range(state, 1.48, 1.76); gene.smoothness = planet_random_range(state, .018, .055); gene.motion = .Fractal_Fold; gene.motion_amplitude = planet_random_range(state, .16, .32)
	case .Mask:
		gene.combine = planet_random_unit(state) < .75 ? .Smooth_Intersect : .Intersect
		gene.center = previous.center
		for a in 0 ..< 4 do gene.radius[a] = max(gene.radius[a], previous.radius[a] * .9)
		gene.motion = .Still
		gene.motion_amplitude = 0
	case .Detail:
		gene.combine = planet_random_unit(state) < .7 ? .Smooth_Union : .Union; gene.center =
			previous.center
		for a in 0 ..< 4 do gene.center[a] += planet_random_range(state, -previous.radius[a] * .7, previous.radius[a] * .7)
		for a in 0 ..< 4 do gene.radius[a] *= .36
		if planet_random_unit(state) < .58 do gene.primitive = planet_random_unit(state) < .62 ? .Recursive_Coral : .Kaleidoscope_Shell
		if index ==
		   3 {gene.primitive = planet_random_unit(state) < .72 ? .Recursive_Coral : .Kaleidoscope_Shell; gene.center = {}; gene.rotation = {}; for a in 0 ..< 4 do gene.radius[a] = planet_random_range(state, .30, .54); gene.fractal_iterations = 5}
		gene.motion =
			(gene.primitive == .Recursive_Coral || gene.primitive == .Kaleidoscope_Shell) ? .Fractal_Fold : .Wave
	case .Core:
	}
	if gene.role != .Mask &&
	   gene.role != .Mouth &&
	   gene.role != .Digestive_Tract &&
	   planet_random_unit(state) <
		   .12 {gene.time_center = planet_random_range(state, -1.2, 1.2); gene.time_extent = planet_random_range(state, 1.8, 3.8)}
	return gene
}

generate_sdf_creature :: proc(seed: u64) -> Sdf_Creature_Genome {
	return generate_sdf_creature_configured(seed, SDF_CREATURE_DEFAULT_CONFIG)
}

generate_sdf_creature_configured :: proc(
	seed: u64,
	config: Sdf_Creature_Evolution_Config,
) -> Sdf_Creature_Genome {
	state := seed ~ 0x6372656174757265
	genome := Sdf_Creature_Genome {
		seed = seed,
	}
	low := clamp(config.minimum_genes, 4, SDF_CREATURE_MAX_GENES)
	high := clamp(config.maximum_genes, low, SDF_CREATURE_MAX_GENES)
	genome.gene_count = low + int(planet_rng_next(&state) % u64(high - low + 1))
	for i in 0 ..< genome.gene_count {
		previous := Sdf_Creature_Gene{}
		if i > 0 {
			// Most tissue buds from the core; the remainder branches from existing
			// anatomy. This produces crowns, cages, and fans instead of one wormlike
			// chain whose later genes are hidden behind the first.
			parent := planet_random_unit(&state) < .62 ? 0 : int(planet_rng_next(&state) % u64(i))
			previous = genome.genes[parent]
		}
		genome.genes[i] = sdf_creature_develop_gene(&state, i, previous)
		if i == 6 {
			// A guaranteed bilateral pair gives selection a symmetric scaffold.
			// Conjugating XY/XZ/XW rotations reflects local orientation across X.
			genome.genes[i] = genome.genes[5]
			genome.genes[i].center[0] = -genome.genes[5].center[0]
			for plane in 0 ..< 3 do genome.genes[i].rotation[plane] = -genome.genes[5].rotation[plane]
		}
	}
	return genome
}

sdf_creature_evaluate :: proc(genome: ^Sdf_Creature_Genome) -> Sdf_Creature_Fitness {
	base_prepared := sdf_creature_prepare_at(genome, 0)
	animated_prepared := sdf_creature_prepare_at(genome, 1.7)
	inside := [SDF_CREATURE_SLICES]int{}
	crossings := 0
	multi_boundary_rows := 0
	mirrored_disagreement, symmetry_active, symmetry_samples := 0, 0, 0
	temporal_disagreement := 0
	total_samples := SDF_CREATURE_GRID * SDF_CREATURE_GRID * SDF_CREATURE_GRID
	for slice in 0 ..< SDF_CREATURE_SLICES {
		w := -0.8 + 1.6 * f64(slice) / f64(SDF_CREATURE_SLICES - 1)
		for z in 0 ..< SDF_CREATURE_GRID {
			pz := -1.2 + 2.4 * f64(z) / f64(SDF_CREATURE_GRID - 1)
			for y in 0 ..< SDF_CREATURE_GRID {
				py := -1.2 + 2.4 * f64(y) / f64(SDF_CREATURE_GRID - 1)
				previous := false
				row_crossings := 0
				for x in 0 ..< SDF_CREATURE_GRID {
					px := -1.2 + 2.4 * f64(x) / f64(SDF_CREATURE_GRID - 1)
					occupied := sdf_creature_prepared_distance(&base_prepared, {px, py, pz, w}) < 0
					// Sample all three visible reflection planes on a coarser lattice.
					// Comparing only active foreground pairs prevents empty space from
					// making every tiny organism appear artificially symmetric.
					if (x + y + z) % 2 == 0 {
						point := [4]f64{px, py, pz, w}
						for axis in 0 ..< 3 {
							reflected := point; reflected[axis] = -reflected[axis]
							mirrored :=
								sdf_creature_prepared_distance(&base_prepared, reflected) < 0
							if occupied ||
							   mirrored {symmetry_active += 1; if occupied != mirrored do mirrored_disagreement += 1}
							symmetry_samples += 1
						}
					}
					if slice == SDF_CREATURE_SLICES / 2 {
						animated :=
							sdf_creature_prepared_distance(&animated_prepared, {px, py, pz, w}) < 0
						if occupied != animated do temporal_disagreement += 1
					}
					if occupied do inside[slice] += 1
					if x > 0 && occupied != previous {crossings += 1; row_crossings += 1}
					previous = occupied
				}
				if row_crossings >= 4 do multi_boundary_rows += 1
			}
		}
	}

	fitness := Sdf_Creature_Fitness{}
	nonempty := 0
	mean_occupancy := 0.0
	for count in inside {
		if count > 0 do nonempty += 1
		mean_occupancy += f64(count) / f64(total_samples)
	}
	mean_occupancy /= SDF_CREATURE_SLICES
	fitness.occupancy = max(0, 1 - math.abs(mean_occupancy - 0.16) / 0.16)
	fitness.continuity = f64(nonempty) / SDF_CREATURE_SLICES
	change := 0.0
	for i in 1 ..< SDF_CREATURE_SLICES do change += math.abs(f64(inside[i] - inside[i - 1])) / f64(total_samples)
	fitness.variation = sdf_creature_clamp(change / 0.30, 0, 1)
	crossing_ratio :=
		f64(crossings) /
		f64(SDF_CREATURE_SLICES * SDF_CREATURE_GRID * SDF_CREATURE_GRID * (SDF_CREATURE_GRID - 1))
	// A single convex blob produces few scanline crossings. Reward additional
	// boundaries from apertures, forks, and nested tissue; viability already
	// rejects disconnected dust, so complexity need not peak at blob density.
	fitness.complexity = sdf_creature_clamp(crossing_ratio / .22, 0, 1)
	fitness.void_expression = sdf_creature_clamp(
		f64(multi_boundary_rows) /
		f64(SDF_CREATURE_SLICES * SDF_CREATURE_GRID * SDF_CREATURE_GRID) /
		.12,
		0,
		1,
	)
	fitness.symmetry =
		symmetry_active > 0 ? 1 - f64(mirrored_disagreement) / f64(symmetry_active) : 0
	fitness.asymmetry = 1 - fitness.symmetry
	fitness.surface_density = crossing_ratio
	fitness.topology_change = sdf_creature_clamp(change / .16, 0, 1)
	fitness.temporal_change = sdf_creature_clamp(
		f64(temporal_disagreement) / f64(total_samples) / .15,
		0,
		1,
	)
	for gene in genome.genes[:genome.gene_count] do if gene.role == .Appendage do fitness.appendages += 1
	// A coarse central-slice component count is a viability constraint, not an
	// aesthetic reward. This prevents dust and empty masks winning a niche.
	CELL_COUNT :: SDF_CREATURE_GRID * SDF_CREATURE_GRID * SDF_CREATURE_GRID
	occupied: [CELL_COUNT]bool; visited: [CELL_COUNT]bool; queue: [CELL_COUNT]int
	for z in 0 ..< SDF_CREATURE_GRID {pz := -1.2 + 2.4 * f64(z) / f64(SDF_CREATURE_GRID - 1); for y in 0 ..< SDF_CREATURE_GRID {py := -1.2 + 2.4 * f64(y) / f64(SDF_CREATURE_GRID - 1); for x in 0 ..< SDF_CREATURE_GRID {px := -1.2 + 2.4 * f64(x) / f64(SDF_CREATURE_GRID - 1); occupied[x + y * SDF_CREATURE_GRID + z * SDF_CREATURE_GRID * SDF_CREATURE_GRID] = sdf_creature_prepared_distance(&base_prepared, {px, py, pz, 0}) < 0}}}
	for start in 0 ..< CELL_COUNT {if !occupied[start] || visited[start] do continue; fitness.components += 1; head, tail := 0, 1; queue[0] = start; visited[start] = true; for head < tail {at := queue[head]; head += 1; x := at % SDF_CREATURE_GRID; y := (at / SDF_CREATURE_GRID) % SDF_CREATURE_GRID; z := at / (SDF_CREATURE_GRID * SDF_CREATURE_GRID); neighbors := [6][3]int{{x - 1, y, z}, {x + 1, y, z}, {x, y - 1, z}, {x, y + 1, z}, {x, y, z - 1}, {x, y, z + 1}}; for n in neighbors {if n[0] < 0 || n[1] < 0 || n[2] < 0 || n[0] >= SDF_CREATURE_GRID || n[1] >= SDF_CREATURE_GRID || n[2] >= SDF_CREATURE_GRID do continue; ni := n[0] + n[1] * SDF_CREATURE_GRID + n[2] * SDF_CREATURE_GRID * SDF_CREATURE_GRID; if occupied[ni] && !visited[ni] {visited[ni] = true; queue[tail] = ni; tail += 1}}}}
	fitness.viable =
		nonempty >= 4 &&
		mean_occupancy > .025 &&
		mean_occupancy < .42 &&
		fitness.components >= 1 &&
		fitness.components <= 4
	appendage_quality := max(0, 1 - math.abs(f64(fitness.appendages) - 4) / 4)
	transformation_quality := max(0, 1 - math.abs(fitness.topology_change - .52) / .52)
	seen_clifford, seen_lamina, seen_cross, seen_fractal, cavities, digestive_genes :=
		false, false, false, false, 0, 0
	for gene in genome.genes[:genome.gene_count] {
		#partial switch gene.primitive {case .Clifford_Torus:
			seen_clifford = true; case .Lamina:
			seen_lamina = true; case .Radial_Cross:
			seen_cross = true; case .Recursive_Coral, .Kaleidoscope_Shell:
			seen_fractal = true}
		if gene.role == .Cavity do cavities += 1
		if gene.role == .Mouth || gene.role == .Digestive_Tract do digestive_genes += 1
	}
	motif_count :=
		(seen_clifford ? 1 : 0) +
		(seen_lamina ? 1 : 0) +
		(seen_cross ? 1 : 0) +
		(seen_fractal ? 1 : 0)
	alien_motif_quality :=
		f64(motif_count) / 4 * .68 +
		sdf_creature_clamp(f64(cavities + digestive_genes) / 4, 0, 1) * .32
	fitness.total =
		fitness.occupancy * .06 +
		fitness.continuity * .07 +
		fitness.variation * .06 +
		fitness.complexity * .12 +
		fitness.void_expression * .10 +
		fitness.symmetry * .22 +
		appendage_quality * .07 +
		transformation_quality * .06 +
		fitness.temporal_change * .04 +
		alien_motif_quality * .10 +
		(fitness.viable ? .10 : 0)
	if !fitness.viable do fitness.total *= .18
	return fitness
}

sdf_creature_crossover :: proc(a, b: ^Sdf_Creature_Genome, state: ^u64) -> Sdf_Creature_Genome {
	child := a^
	child.seed = planet_rng_next(state)
	child.gene_count = (a.gene_count + b.gene_count) / 2
	child.gene_count = min(max(child.gene_count, 4), SDF_CREATURE_MAX_GENES)
	for i in 0 ..< child.gene_count {
		source := planet_random_unit(state) < 0.5 ? a : b
		child.genes[i] = source.genes[i % source.gene_count]
	}
	return child
}

sdf_creature_mutate :: proc(genome: ^Sdf_Creature_Genome, state: ^u64, amount := 0.16) {
	for &gene in genome.genes[:genome.gene_count] {
		if planet_random_unit(state) < 0.10 do gene.primitive = Sdf_Creature_Primitive(planet_rng_next(state) % u64(len(Sdf_Creature_Primitive)))
		for axis in 0 ..< 4 {
			if planet_random_unit(state) < 0.55 do gene.center[axis] = sdf_creature_clamp(gene.center[axis] + planet_random_range(state, -amount, amount), -0.9, 0.9)
			if planet_random_unit(state) < 0.55 do gene.radius[axis] = sdf_creature_clamp(gene.radius[axis] + planet_random_range(state, -amount, amount), 0.10, 1.1)
		}
		for &angle in gene.rotation do if planet_random_unit(state) < .32 do angle += planet_random_range(state, -amount * 2.4, amount * 2.4)
		if planet_random_unit(state) < .28 do gene.fractal_scale = sdf_creature_clamp(gene.fractal_scale + planet_random_range(state, -amount * .45, amount * .45), 1.35, 1.95)
		if planet_random_unit(state) < .38 do gene.fractal_phase += planet_random_range(state, -amount * 2.5, amount * 2.5)
		if planet_random_unit(state) < .06 do gene.fractal_iterations = u8(2 + planet_rng_next(state) % 4)
		if planet_random_unit(state) < 0.4 do gene.smoothness = sdf_creature_clamp(gene.smoothness + planet_random_range(state, -amount * 0.4, amount * 0.4), 0.01, 0.32)
		if planet_random_unit(state) < .08 do gene.motion = Sdf_Creature_Motion(planet_rng_next(state) % u64(len(Sdf_Creature_Motion)))
		if planet_random_unit(state) < .5 do gene.motion_phase += planet_random_range(state, -amount * 2, amount * 2)
		if planet_random_unit(state) < .45 do gene.motion_frequency = sdf_creature_clamp(gene.motion_frequency + planet_random_range(state, -amount, amount), .12, 1.8)
		if planet_random_unit(state) < .45 do gene.motion_amplitude = sdf_creature_clamp(gene.motion_amplitude + planet_random_range(state, -amount * .35, amount * .35), 0, .48)
	}
	for &gene, index in genome.genes[:genome.gene_count] {
		if index == 0 {gene.combine = .Smooth_Union; continue}
		if planet_random_unit(state) < .10 do gene.combine = Sdf_Creature_Combine(planet_rng_next(state) % u64(len(Sdf_Creature_Combine)))
	}
	if genome.gene_count < SDF_CREATURE_MAX_GENES && planet_random_unit(state) < 0.12 {
		genome.genes[genome.gene_count] = sdf_creature_develop_gene(
			state,
			genome.gene_count,
			genome.genes[genome.gene_count - 1],
		)
		genome.gene_count += 1
	} else if genome.gene_count > 4 && planet_random_unit(state) < 0.08 {
		genome.gene_count -= 1
	}
}

// Deterministic tournament selection plus elitism. Keeping the full result
// makes improvements and evaluation cost visible to tooling and tests.
evolve_sdf_creature :: proc(seed: u64, generations := 24) -> Sdf_Creature_Evolution {
	config := SDF_CREATURE_DEFAULT_CONFIG
	config.generations = generations
	return evolve_sdf_creature_configured(seed, config)
}

evolve_sdf_creature_configured :: proc(
	seed: u64,
	config: Sdf_Creature_Evolution_Config,
) -> Sdf_Creature_Evolution {
	archive := [SDF_CREATURE_ARCHIVE_CELLS]Sdf_Creature_Genome{}
	archive_fitness := [SDF_CREATURE_ARCHIVE_CELLS]Sdf_Creature_Fitness{}
	occupied := [SDF_CREATURE_ARCHIVE_CELLS]bool{}
	state := seed ~ 0x65766f6c76652d34
	result := Sdf_Creature_Evolution {
		evaluations = SDF_CREATURE_POPULATION,
	}
	for i in 0 ..< SDF_CREATURE_POPULATION {
		candidate := generate_sdf_creature_configured(
			planet_rng_next(&state),
			config,
		); score := sdf_creature_evaluate(&candidate); cell := sdf_creature_archive_cell(score)
		if !occupied[cell] ||
		   score.total >
			   archive_fitness[cell].total {if !occupied[cell] do result.archive_cells += 1; occupied[cell] = true; archive[cell] = candidate; archive_fitness[cell] = score}
		if score.total > result.fitness.total {result.creature = candidate; result.fitness = score}
	}
	result.initial_best = result.fitness.total
	for generation in 0 ..< max(config.generations, 0) {
		for i in 0 ..< SDF_CREATURE_POPULATION {
			pick := proc(
				state: ^u64,
				occupied: ^[SDF_CREATURE_ARCHIVE_CELLS]bool,
			) -> int {start := int(planet_rng_next(state) % SDF_CREATURE_ARCHIVE_CELLS); for offset in 0 ..< SDF_CREATURE_ARCHIVE_CELLS {at :=
						(start + offset) % SDF_CREATURE_ARCHIVE_CELLS
					if occupied[at] do return at}
				return 0}
			pa, pb :=
				pick(&state, &occupied),
				pick(
					&state,
					&occupied,
				); candidate := sdf_creature_crossover(&archive[pa], &archive[pb], &state); sdf_creature_mutate(&candidate, &state, sdf_creature_clamp(config.mutation_amount, .02, .5)); score := sdf_creature_evaluate(&candidate); cell := sdf_creature_archive_cell(score)
			if !occupied[cell] ||
			   score.total >
				   archive_fitness[cell].total {if !occupied[cell] do result.archive_cells += 1; occupied[cell] = true; archive[cell] = candidate; archive_fitness[cell] = score}
			if score.total >
			   result.fitness.total {result.creature = candidate; result.fitness = score}
		}
		result.generations = generation + 1
		result.evaluations += SDF_CREATURE_POPULATION
	}
	return result
}
