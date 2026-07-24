package game

forecast_add_factor :: proc(
	factors: ^[MAX_FORECAST_FACTORS]Forecast_Factor,
	count: ^int,
	label: string,
	contribution: f64,
	confidence: f64,
	evidence: Forecast_Evidence,
	source_ship: Ship_ID = 0,
	source_event: u64 = 0,
) {
	if count^ >= MAX_FORECAST_FACTORS do return
	factors[count^] = {
		label        = label,
		contribution = contribution,
		confidence   = clamp(confidence, 0, 1),
		source_ship  = source_ship,
		source_event = source_event,
		evidence     = evidence,
	}
	count^ += 1
}

ship_impairment_total :: proc(value: Ship_Impairments) -> i32 {
	return value.mobility + value.sensors + value.strike + value.support + value.endurance
}

ship_clear_one_impairment :: proc(ship: ^Ship) -> bool {
	best := max(
		max(ship.impairments.mobility, ship.impairments.sensors),
		max(max(ship.impairments.strike, ship.impairments.support), ship.impairments.endurance),
	)
	if best <= 0 do return false
	if ship.impairments.mobility == best {
		ship.impairments.mobility -= 1
	} else if ship.impairments.sensors == best {
		ship.impairments.sensors -= 1
	} else if ship.impairments.strike == best {
		ship.impairments.strike -= 1
	} else if ship.impairments.support == best {
		ship.impairments.support -= 1
	} else {
		ship.impairments.endurance -= 1
	}
	return true
}

ship_clear_impairments :: proc(ship: ^Ship) {
	ship.impairments = {}
}

dark_sensor_posture_name :: proc(posture: Dark_Sensor_Posture) -> string {
	switch posture {
	case .Quiet:        return "QUIET"
	case .Passive:      return "PASSIVE"
	case .Active_Sweep: return "ACTIVE SWEEP"
	case .Illuminate:   return "ILLUMINATE"
	}
	return "PASSIVE"
}

Dark_Sensor_Profile :: struct {
	range_scale, confidence_scale, coherence_rate, emission, wake_scale: f64,
	update_ticks:                                                        u64,
}

dark_sensor_profile :: proc(posture: Dark_Sensor_Posture) -> Dark_Sensor_Profile {
	switch posture {
	case .Quiet:
		return {.62, .68, -.001, 0, .55, 4}
	case .Active_Sweep:
		return {1.25, 1.18, .004, .45, 1.25, 1}
	case .Illuminate:
		return {1.45, 1.35, .009, 1, 1.7, 1}
	case .Passive:
		return {1, 1, 0, 0, 1, 2}
	}
	return {1, 1, 0, 0, 1, 2}
}
