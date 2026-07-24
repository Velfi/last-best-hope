package game

procedural_ship_fingerprint :: proc(r: Procedural_Ship_Recipe) -> u64 {
	h := r.seed ~ (u64(r.family) << 56) ~ u64(r.module_count)
	for i in 0 ..< r.module_count {
		module := r.modules[i]
		value := u64(module.module) | u64(module.material) << 8 | u64(module.id) << 16
		h = ship_construction_visual_mix(h ~ value)
	}
	return h
}
