package main

import game "../packages/game"

combat_3d_creature_seed :: proc(
	continuum_seed, organism_id: u64,
	role: game.Dark_Ecological_Role,
) -> u64 {
	return game.combat_mix(
		continuum_seed ~ game.combat_mix(organism_id + u64(role) * 0x9e3779b97f4a7c15),
	)
}

combat_3d_creature_genome :: proc(
	continuum_seed: u64,
	organism: ^game.Dark_Organism,
) -> ^game.Sdf_Creature_Genome {
	for &entry in combat_3d.creature_cache {
		if entry.valid && entry.id == organism.id do return &entry.genome
	}
	slot := -1
	for &entry, index in combat_3d.creature_cache {
		if !entry.valid {slot = index; break}
	}
	if slot < 0 do slot = int(organism.id % u64(len(combat_3d.creature_cache)))
	genome := organism.genome
	// New organisms already own their deterministic simulation genome. The
	// fallback exists only for legacy/fixture records created before that field.
	if genome.gene_count <= 0 do genome = game.generate_sdf_creature(combat_3d_creature_seed(continuum_seed, organism.id, organism.role))
	combat_3d.creature_cache[slot] = {
		valid  = true,
		id     = organism.id,
		genome = genome,
	}
	combat_3d.creature_cache_uploads += 1
	return &combat_3d.creature_cache[slot].genome
}

combat_3d_pack_creature_gene :: proc(
	gene: ^game.Sdf_Creature_Gene,
) -> Combat_3D_Creature_GPU_Gene {
	return {
		meta = {
			f32(gene.primitive),
			f32(gene.combine),
			f32(gene.role),
			f32(gene.fractal_iterations),
		},
		center = {
			f32(gene.center[0]),
			f32(gene.center[1]),
			f32(gene.center[2]),
			f32(gene.center[3]),
		},
		radius = {
			f32(gene.radius[0]),
			f32(gene.radius[1]),
			f32(gene.radius[2]),
			f32(gene.radius[3]),
		},
		rotation_a = {
			f32(gene.rotation[0]),
			f32(gene.rotation[1]),
			f32(gene.rotation[2]),
			f32(gene.rotation[3]),
		},
		rotation_b = {
			f32(gene.rotation[4]),
			f32(gene.rotation[5]),
			f32(gene.smoothness),
			f32(gene.fractal_scale),
		},
		motion_a = {
			f32(gene.motion),
			f32(gene.motion_axis),
			f32(gene.motion_phase),
			f32(gene.motion_frequency),
		},
		motion_b = {
			f32(gene.motion_amplitude),
			f32(gene.time_center),
			f32(gene.time_extent),
			f32(gene.fractal_phase),
		},
	}
}

combat_3d_append_generated_creature :: proc(
	continuum_seed: u64,
	organism: ^game.Dark_Organism,
	center: game.Combat_Vec3,
	radius, slice: f32,
	color: [4]f32,
	sensor_confidence: f32,
) {
	genome := combat_3d_creature_genome(continuum_seed, organism)
	if combat_3d.creature_gene_count + genome.gene_count > COMBAT_3D_MAX_CREATURE_GENES do return
	base := combat_3d.creature_gene_count
	for &gene in genome.genes[:genome.gene_count] {
		combat_3d.creature_genes[combat_3d.creature_gene_count] = combat_3d_pack_creature_gene(
			&gene,
		)
		combat_3d.creature_gene_count += 1
	}
	combat_3d_append_terrain_volume(
		center,
		radius,
		radius,
		DARK_VOLUME_GENERATED_CREATURE,
		f32(base),
		f32(genome.gene_count),
		slice,
		color,
		sensor_confidence,
	)
	combat_3d.creature_visible_count += 1
}
