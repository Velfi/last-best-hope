package game

// Ship_Service_Tier is the simulation-owned meaning behind visible service
// heraldry. Presentation code chooses the atlas cell used for each tier.
Ship_Service_Tier :: enum u8 {
	None,
	First,
	Second,
	Third,
	Fourth,
	Fifth,
	Sixth,
}

Ship_Promise_Record :: enum u8 {
	None,
	Upheld,
	Broken,
	Transformed,
}

ship_service_score :: proc(ship: Ship) -> int {
	memory_score := min(ship.memory_count + int(ship.archived_memory_count), 6)
	return max(int(ship.experience), 0) + max(int(ship.discoveries), 0) * 2 + memory_score
}

ship_service_tier :: proc(ship: Ship) -> Ship_Service_Tier {
	score := ship_service_score(ship)
	if score <= 0 do return .None
	if score <= 2 do return .First
	if score <= 5 do return .Second
	if score <= 8 do return .Third
	if score <= 12 do return .Fourth
	if score <= 17 do return .Fifth
	return .Sixth
}

// Prefer the explicitly recorded latest outcome. Counters are retained as a
// compatibility fallback for saves created before last_promise_status existed.
ship_promise_record :: proc(ship: Ship) -> Ship_Promise_Record {
	if ship.last_promise_event != 0 {
		switch ship.last_promise_status {
		case .Upheld:
			return .Upheld
		case .Broken:
			return .Broken
		case .Transformed:
			return .Transformed
		case .Active:
		}
	}
	if ship.promises_broken > 0 do return .Broken
	if ship.promises_transformed > 0 do return .Transformed
	if ship.promises_upheld > 0 do return .Upheld
	return .None
}

