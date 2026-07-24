package game

ship_construction_wing_sweep :: proc(ship: Ship) -> int {
	if ship.wing_sweep >= 1 && ship.wing_sweep <= 3 do return int(ship.wing_sweep) - 1
	identity := ship.construction_seed
	if identity == 0 do identity = u64(ship.id)
	return int(ship_construction_visual_mix(identity ~ 0x6a09e667f3bcc909) % 3)
}

ship_construction_keel_profile :: proc(ship: Ship) -> int {
	if ship.keel_profile >= 1 && ship.keel_profile <= 3 do return int(ship.keel_profile) - 1
	identity := ship.construction_lineage
	if identity == 0 do identity = ship.construction_seed
	if identity == 0 do identity = u64(ship.id)
	return int(ship_construction_visual_mix(identity ~ 0x082efa98ec4e6c89) % 3)
}

ship_construction_drive_layout :: proc(ship: Ship) -> int {
	if ship.drive_layout >= 1 && ship.drive_layout <= 3 do return int(ship.drive_layout) - 1
	identity := ship.construction_seed
	if identity == 0 do identity = u64(ship.id)
	return int(ship_construction_visual_mix(identity ~ 0x3f84d5b5b5470917) % 3)
}

ship_construction_drive_setback :: proc(ship: Ship) -> int {
	if ship.drive_setback >= 1 && ship.drive_setback <= 3 do return int(ship.drive_setback) - 1
	identity := ship.construction_seed
	if identity == 0 do identity = u64(ship.id)
	return int(ship_construction_visual_mix(identity ~ 0xbb67ae8584caa73b) % 3)
}

ship_construction_bow_profile :: proc(ship: Ship) -> int {
	if ship.bow_profile >= 1 && ship.bow_profile <= 3 do return int(ship.bow_profile) - 1
	identity := ship.construction_seed
	if identity == 0 do identity = u64(max(int(ship.id), 1))
	return int(ship_construction_visual_mix(identity ~ 0x9216d5d98979fb1b) % 3)
}

ship_construction_preferred_bow_profile :: proc(ship: Ship) -> int {
	primary, accent := ship_construction_family_pair(ship)
	return (primary * 2 + accent + ship_construction_keel_profile(ship)) % 3
}

ship_construction_structural_profile :: proc(ship: Ship) -> int {
	return ship_construction_keel_profile(ship) * 9 +
	       ship_construction_wing_stance(ship) * 3 +
	       ship_construction_drive_layout(ship)
}

ship_construction_mission_profile :: proc(ship: Ship) -> int {
	if ship.mission_profile >= 1 && ship.mission_profile <= 3 do return int(ship.mission_profile) - 1
	identity := ship.construction_seed
	if identity == 0 do identity = u64(ship.id)
	return int(ship_construction_visual_mix(identity ~ 0x510e527fade682d1) % 3)
}

ship_construction_centerline_bias :: proc(ship: Ship) -> int {
	identity := ship.construction_seed
	if identity == 0 do identity = u64(max(int(ship.id), 1))
	return int(ship_construction_visual_mix(identity ~ 0xa54ff53a5f1d36f1) & 1)
}

ship_construction_visual_fingerprint :: proc(ship: Ship) -> u64 {
	primary, accent := ship_construction_family_pair(ship)
	layout := ship_construction_layout_code(ship)
	fingerprint := u64(0)
	place := u64(1)
	for bit in uint(0) ..< 5 {
		family := ((layout >> bit) & 1) == 0 ? primary : accent
		fingerprint += u64(family) * place
		place *= 6
	}
	return fingerprint
}

ship_construction_recipe_fingerprint :: proc(ship: Ship) -> u64 {
	fingerprint := ship_construction_visual_fingerprint(ship)
	place := u64(6 * 6 * 6 * 6 * 6)
	fingerprint += u64(ship_construction_utility_hardpoint(ship)) * place
	place *= 9
	fingerprint += u64(ship_construction_wing_stance(ship)) * place
	place *= 3
	fingerprint += u64(ship_construction_keel_profile(ship)) * place
	place *= 3
	fingerprint += u64(ship_construction_drive_layout(ship)) * place
	place *= 3
	fingerprint += u64(ship_construction_bow_profile(ship)) * place
	place *= 3
	fingerprint += u64(ship_construction_wing_sweep(ship)) * place
	place *= 3
	fingerprint += u64(ship_construction_drive_setback(ship)) * place
	place *= 3
	fingerprint += u64(ship_construction_mission_profile(ship)) * place
	place *= 3
	if ship_construction_utility_hardpoint(ship) % 3 == 1 do fingerprint += u64(ship_construction_centerline_bias(ship)) * place
	return fingerprint
}
