package game

import "core:fmt"
import "core:math"

MAX_RESOURCE_DEPOSITS :: 64
FLEET_NAVIGATION_WORK_ID :: u64(0x4e41564947415445)
AU_DAY_TO_KM_S :: 149_597_870.7 / 86_400.0
GAUSSIAN_GRAVITY :: 0.01720209895

Fleet_Navigation_Phase :: enum {
	Holding,
	Transfer,
	Harvesting,
}

Fleet_Navigation_Stop :: enum {
	None,
	Arrived,
	Target_Reserve,
	Latest_Departure,
	Tanks_Full,
	Deposit_Exhausted,
	Extraction_Interrupted,
	Material_Deviation,
}

Resource_Intel :: enum {
	Catalogued,
	Signature,
	Characterized,
	Surveyed,
}

Resource_Deposit :: struct {
	body:                                                                    Celestial_Body_Ref,
	composition:                                                             Asteroid_Composition,
	initial_propellant_kt, remaining_propellant_kt:                          f64,
	initial_feedstock, remaining_feedstock:                                  i64,
	water_fraction, feedstock_fraction, accessibility, operating_difficulty: f64,
	interruption_fraction:                                                   f64,
	intel:                                                                   Resource_Intel,
}

Fleet_Transfer_Forecast :: struct {
	valid, feasible, crosses_reserve, has_recovery_source:                                bool,
	target:                                                                               Celestial_Body_Ref,
	departure_at, arrival_at:                                                             Campaign_Time,
	duration_days, departure_delta_v_km_s, arrival_delta_v_km_s:                          f64,
	total_delta_v_km_s, propellant_cost_kt:                                               f64,
	propellant_before_kt, propellant_after_kt, reserve_kt:                                f64,
	reserve_margin_kt, expected_harvest_days, expected_harvest_kt, recovery_shortfall_kt: f64,
	limiting_ship:                                                                        Ship_ID,
	cause:                                                                                string,
}

Fleet_Harvest_Forecast :: struct {
	valid:                                                                                      bool,
	body:                                                                                       Celestial_Body_Ref,
	propellant_rate_kt_day,
	available_propellant_kt,
	storage_headroom_kt,
	target_propellant_kt: f64,
	feedstock_rate_day:                                                                         f64,
	available_feedstock,
	feedstock_headroom,
	target_feedstock:                                  i64,
	duration_days:                                                                              f64,
	stop:                                                                                       Fleet_Navigation_Stop,
	interruption_known:                                                                         bool,
	cause:                                                                                      string,
}

Fleet_Transfer_Order :: struct {
	active, emergency_override, deviation_reported: bool,
	forecast:                                       Fleet_Transfer_Forecast,
	cause_event:                                    u64,
}

Fleet_Harvest_Order :: struct {
	active,
	deviation_reported:                                                                          bool,
	body:                                                                                                Celestial_Body_Ref,
	started_at,
	due_at,
	latest_departure_at:                                                             Campaign_Time,
	starting_propellant_kt,
	target_propellant_kt,
	planned_propellant_kt,
	planned_propellant_rate_kt_day: f64,
	target_feedstock,
	planned_feedstock:                                                                 i64,
	planned_feedstock_rate_day:                                                                          f64,
	interruption_pending,
	interrupted:                                                                   bool,
	stop:                                                                                                Fleet_Navigation_Stop,
	cause_event:                                                                                         u64,
}

Fleet_Navigation :: struct {
	initialized:                  bool,
	phase:                        Fleet_Navigation_Phase,
	system_index:                 int,
	current_body:                 Celestial_Body_Ref,
	position_au, velocity_au_day: System_Vec3,
	protected_reserve_fraction:   f64,
	transfer:                     Fleet_Transfer_Order,
	harvest:                      Fleet_Harvest_Order,
	deposits:                     [MAX_RESOURCE_DEPOSITS]Resource_Deposit,
	deposit_count:                int,
	last_stop:                    Fleet_Navigation_Stop,
	last_navigation_event:        u64,
}

fleet_navigation_epoch_days :: proc(c: ^Campaign) -> f64 {
	return f64(i64(c.clock.now)) / f64(CAMPAIGN_DAY_SECONDS)
}

fleet_navigation_system :: proc(c: ^Campaign) -> ^Solar_System {
	if c == nil ||
	   c.galaxy == nil ||
	   c.fleet_navigation.system_index < 0 ||
	   c.fleet_navigation.system_index >= c.galaxy.detailed_system_count {
		return nil
	}
	return &c.galaxy.detailed_systems[c.fleet_navigation.system_index].system
}

fleet_propellant_capacity :: proc(c: ^Campaign) -> f64 {
	total: f64
	for ship in c.ships[:c.ship_count] do if ship.active && !ship.committed do total += max(ship.propellant_capacity_kt, 0)
	return total
}

fleet_propellant_remaining :: proc(c: ^Campaign) -> f64 {
	total: f64
	for ship in c.ships[:c.ship_count] do if ship.active && !ship.committed do total += clamp(ship.propellant_kt, 0, ship.propellant_capacity_kt)
	return total
}

fleet_propellant_reserve :: proc(c: ^Campaign) -> f64 {
	fraction := c.fleet_navigation.protected_reserve_fraction
	if fraction <= 0 do fraction = .2
	return fleet_propellant_capacity(c) * fraction
}

fleet_propellant_sync_ledger :: proc(c: ^Campaign) {
	c.material_economy.fleet.stock.propellant = i64(math.floor(fleet_propellant_remaining(c) + .5))
}

fleet_propellant_distribute :: proc(c: ^Campaign, desired_total_kt: f64) -> f64 {
	total_capacity := fleet_propellant_capacity(c)
	remaining := clamp(desired_total_kt, 0, total_capacity)
	reserve_fraction := c.fleet_navigation.protected_reserve_fraction
	if reserve_fraction <= 0 do reserve_fraction = .2
	for &ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		ship.propellant_kt = min(ship.propellant_capacity_kt * reserve_fraction, remaining)
		remaining -= ship.propellant_kt
	}
	for &ship in c.ships[:c.ship_count] {
		if !ship.active ||
		   ship.committed ||
		   remaining <= 1e-9 ||
		   ship.operational_role != .Tanker {
			continue
		}
		added := min(ship.propellant_capacity_kt - ship.propellant_kt, remaining)
		ship.propellant_kt += added
		remaining -= added
	}
	proportional_headroom := 0.0
	for ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed || ship.operational_role == .Tanker do continue
		proportional_headroom += max(ship.propellant_capacity_kt - ship.propellant_kt, 0)
	}
	if remaining > 1e-9 && proportional_headroom > 1e-9 {
		fraction := min(remaining / proportional_headroom, 1)
		for &ship in c.ships[:c.ship_count] {
			if !ship.active || ship.committed || ship.operational_role == .Tanker do continue
			ship.propellant_kt +=
				max(ship.propellant_capacity_kt - ship.propellant_kt, 0) * fraction
		}
	}
	fleet_propellant_sync_ledger(c)
	return fleet_propellant_remaining(c)
}

fleet_propellant_consume :: proc(c: ^Campaign, amount_kt: f64) -> bool {
	if amount_kt < 0 || fleet_propellant_remaining(c) + 1e-9 < amount_kt do return false
	_ = fleet_propellant_distribute(c, fleet_propellant_remaining(c) - amount_kt)
	return true
}

fleet_propellant_gain :: proc(c: ^Campaign, amount_kt: f64) -> f64 {
	before := fleet_propellant_remaining(c)
	_ = fleet_propellant_distribute(c, before + max(amount_kt, 0))
	return fleet_propellant_remaining(c) - before
}

fleet_deposit_index :: proc(c: ^Campaign, body: Celestial_Body_Ref) -> int {
	for deposit, i in c.fleet_navigation.deposits[:c.fleet_navigation.deposit_count] do if deposit.body == body do return i
	return -1
}

fleet_feedstock_capacity :: proc(c: ^Campaign) -> i64 {
	capacity := i64(48)
	for ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		if ship.role == .Foundry do capacity += 32
		if ship.operational_role == .Tanker do capacity += 12
	}
	return capacity
}

fleet_feedstock_headroom :: proc(c: ^Campaign) -> i64 {
	return max(fleet_feedstock_capacity(c) - c.material_economy.fleet.stock.raw_materials, 0)
}

fleet_feedstock_harvest_rate :: proc(c: ^Campaign) -> f64 {
	rate: f64
	for ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		condition := clamp(1 - f64(ship.damage + ship.impairments.support) * .06, .25, 1)
		if ship.role == .Foundry do rate += .35 * condition
		if ship.operational_role == .Tanker do rate += .05 * condition
		if ship.role == .Survey do rate += .02 * condition
	}
	return rate
}

resource_intel_name :: proc(intel: Resource_Intel) -> string {
	switch intel {case .Catalogued:
		return "CATALOGUED"; case .Signature:
		return "MATERIAL SIGNATURE"; case .Characterized:
		return "CHARACTERIZED"; case .Surveyed:
		return "SURVEYED"}
	return "UNRESOLVED"
}

fleet_resource_intel_update :: proc(c: ^Campaign) {
	if c == nil do return
	for &deposit in c.fleet_navigation.deposits[:c.fleet_navigation.deposit_count] {
		intel: Resource_Intel = .Catalogued
		if deposit.body == c.fleet_navigation.current_body {
			intel = .Surveyed
		} else {
			state, ok := fleet_navigation_body_state(
				c,
				deposit.body,
				fleet_navigation_epoch_days(c),
			)
			if ok {
				distance := fleet_vec_length(
					fleet_vec_sub(state.position_au, c.fleet_navigation.position_au),
				)
				threshold := .35
				for ship in c.ships[:c.ship_count] do if ship.active && !ship.committed && ship.role == .Survey {threshold *= 1.8; break}
				if distance <=
				   threshold *
					   .15 {intel = .Surveyed} else if distance <= threshold * .5 {intel = .Characterized} else if distance <= threshold {intel = .Signature}
			}
		}
		if int(intel) > int(deposit.intel) do deposit.intel = intel
	}
}

fleet_navigation_body_state :: proc(
	c: ^Campaign,
	body: Celestial_Body_Ref,
	epoch_days: f64,
) -> (
	System_Body_State,
	bool,
) {
	system := fleet_navigation_system(c)
	if system == nil || !system_ref_valid(system, body) do return {}, false
	return system_body_state_at(system, body, epoch_days)
}

fleet_vec_length :: proc(v: System_Vec3) -> f64 {
	return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
}

fleet_vec_sub :: proc(a, b: System_Vec3) -> System_Vec3 {
	return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}
}

fleet_vec_dot :: proc(a, b: System_Vec3) -> f64 {
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fleet_vec_scale :: proc(v: System_Vec3, s: f64) -> System_Vec3 {
	return {v[0] * s, v[1] * s, v[2] * s}
}

fleet_stumpff_c :: proc(z: f64) -> f64 {
	if z > 1e-8 do return (1 - math.cos(math.sqrt(z))) / z
	if z < -1e-8 do return (math.cosh(math.sqrt(-z)) - 1) / -z
	return .5 - z / 24 + z * z / 720
}

fleet_stumpff_s :: proc(z: f64) -> f64 {
	if z > 1e-8 {root := math.sqrt(z); return (root - math.sin(root)) / (root * root * root)}
	if z < -1e-8 {root := math.sqrt(-z); return (math.sinh(root) - root) / (root * root * root)}
	return 1.0 / 6.0 - z / 120 + z * z / 5040
}

// Deterministic universal-variable, short-way Lambert solution. The system
// model is Keplerian, so this remains a matched two-body forecast rather than
// introducing an order-dependent integrator.
fleet_lambert_velocity :: proc(
	r1v, r2v: System_Vec3,
	days, mu: f64,
) -> (
	v1, v2: System_Vec3,
	ok: bool,
) {
	r1, r2 := fleet_vec_length(r1v), fleet_vec_length(r2v)
	if r1 <= 0 || r2 <= 0 || days <= 0 || mu <= 0 do return
	cosine := clamp(fleet_vec_dot(r1v, r2v) / (r1 * r2), -1.0, 1.0)
	sine := math.sqrt(max(1 - cosine * cosine, 0))
	if sine <= 1e-8 || 1 - cosine <= 1e-10 do return
	a := sine * math.sqrt(r1 * r2 / (1 - cosine))
	if math.abs(a) <= 1e-12 do return
	target := math.sqrt(mu) * days
	low, high := -4 * math.PI * math.PI, 4 * math.PI * math.PI
	z, y: f64
	for _ in 0 ..< 96 {
		z = (low + high) * .5
		cc, ss := fleet_stumpff_c(z), fleet_stumpff_s(z)
		if cc <= 0 {low = z; continue}
		y = r1 + r2 + a * (z * ss - 1) / math.sqrt(cc)
		if y <= 0 {low = z; continue}
		time_value := math.pow(y / cc, 1.5) * ss + a * math.sqrt(y)
		if time_value < target do low = z
		else do high = z
	}
	cc, ss := fleet_stumpff_c(z), fleet_stumpff_s(z)
	y = r1 + r2 + a * (z * ss - 1) / math.sqrt(max(cc, 1e-12))
	if y <= 0 do return
	f := 1 - y / r1
	g := a * math.sqrt(y / mu)
	gdot := 1 - y / r2
	if math.abs(g) <= 1e-12 do return
	v1 = fleet_vec_scale(fleet_vec_sub(r2v, fleet_vec_scale(r1v, f)), 1 / g)
	v2 = fleet_vec_scale(fleet_vec_sub(fleet_vec_scale(r2v, gdot), r1v), 1 / g)
	ok = true
	return
}

fleet_ship_effective_exhaust_velocity :: proc(ship: Ship) -> f64 {
	// Mobility damage makes a ship spend more reaction mass for the same
	// maneuver. Keep the degradation bounded so an impaired ship remains a
	// recoverable planning problem until it loses maneuver authority entirely.
	condition := clamp(1 - f64(ship.damage) * .035 - f64(ship.impairments.mobility) * .08, .55, 1)
	return max(ship.drive_exhaust_velocity_km_s * condition, 1)
}

fleet_ship_propellant_cost :: proc(ship: Ship, delta_v_km_s: f64) -> f64 {
	ve := fleet_ship_effective_exhaust_velocity(ship)
	dry := max(f64(ship.mass_tonnes) / 1000.0, 1)
	wet := dry + max(ship.propellant_kt, 0)
	return wet * (1 - math.exp(-max(delta_v_km_s, 0) / ve))
}

fleet_transfer_forecast :: proc(
	c: ^Campaign,
	target: Celestial_Body_Ref,
	arrival_at: Campaign_Time,
) -> Fleet_Transfer_Forecast {
	result := Fleet_Transfer_Forecast {
		target               = target,
		departure_at         = c.clock.now,
		arrival_at           = arrival_at,
		propellant_before_kt = fleet_propellant_remaining(c),
		reserve_kt           = fleet_propellant_reserve(c),
	}
	if !c.fleet_navigation.initialized || c.fleet_navigation.phase != .Holding {
		result.cause = "The fleet is not holding a navigable orbit."
		return result
	}
	seconds := i64(arrival_at) - i64(c.clock.now)
	if seconds < CAMPAIGN_DAY_SECONDS {
		result.cause = "Arrival must be at least one day after departure."
		return result
	}
	result.duration_days = f64(seconds) / f64(CAMPAIGN_DAY_SECONDS)
	departure_epoch := fleet_navigation_epoch_days(c)
	arrival_epoch := departure_epoch + result.duration_days
	start, start_ok := fleet_navigation_body_state(
		c,
		c.fleet_navigation.current_body,
		departure_epoch,
	)
	finish, finish_ok := fleet_navigation_body_state(c, target, arrival_epoch)
	system := fleet_navigation_system(c)
	if !start_ok || !finish_ok || system == nil {
		result.cause = "The target ephemeris is unavailable."
		return result
	}
	host_mass := max(system.stars[0].profile.mass_solar, .01)
	mu := GAUSSIAN_GRAVITY * GAUSSIAN_GRAVITY * host_mass
	v1, v2, solved := fleet_lambert_velocity(
		start.position_au,
		finish.position_au,
		result.duration_days,
		mu,
	)
	if !solved {
		result.cause = "No stable short-way transfer exists for that arrival."
		return result
	}
	result.departure_delta_v_km_s =
		fleet_vec_length(fleet_vec_sub(v1, start.velocity_au_day)) * AU_DAY_TO_KM_S
	result.arrival_delta_v_km_s =
		fleet_vec_length(fleet_vec_sub(finish.velocity_au_day, v2)) * AU_DAY_TO_KM_S
	result.total_delta_v_km_s = result.departure_delta_v_km_s + result.arrival_delta_v_km_s
	min_margin := f64(1e30)
	for ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		cost := fleet_ship_propellant_cost(ship, result.total_delta_v_km_s)
		result.propellant_cost_kt += cost
		margin :=
			ship.propellant_kt -
			cost -
			ship.propellant_capacity_kt * c.fleet_navigation.protected_reserve_fraction
		if margin < min_margin {min_margin = margin; result.limiting_ship = ship.id}
		if cost > ship.propellant_kt + 1e-9 {
			result.cause = fmt.tprintf("%s cannot complete the planned burns.", ship.name)
			return result
		}
	}
	result.propellant_after_kt = result.propellant_before_kt - result.propellant_cost_kt
	result.reserve_margin_kt = result.propellant_after_kt - result.reserve_kt
	result.crosses_reserve = result.reserve_margin_kt < -1e-9 || min_margin < -1e-9
	result.valid = true
	result.feasible = !result.crosses_reserve
	if result.crosses_reserve do result.cause = "The transfer crosses the fleet's protected recovery reserve."
	else do result.cause = "Every active ship can execute the transfer within reserve."
	if deposit_at := fleet_deposit_index(c, target); deposit_at >= 0 {
		result.has_recovery_source = true
		rate := fleet_harvest_rate(c)
		result.expected_harvest_kt = min(
			c.fleet_navigation.deposits[deposit_at].remaining_propellant_kt,
			result.propellant_cost_kt,
		)
		result.recovery_shortfall_kt = result.propellant_cost_kt - result.expected_harvest_kt
		if rate > 0 do result.expected_harvest_days = result.expected_harvest_kt / rate
	}
	return result
}

// fleet_transfer_best_window searches a fixed arrival grid, so route advice is
// reproducible for a supplied campaign state. It only recommends legs that
// preserve the protected reserve; emergency authority remains a player choice.
fleet_transfer_best_window :: proc(
	c: ^Campaign,
	target: Celestial_Body_Ref,
	minimum_days, maximum_days, step_days: i64,
) -> (
	Fleet_Transfer_Forecast,
	bool,
) {
	min_days := max(minimum_days, 1)
	max_days := max(maximum_days, min_days)
	step := max(step_days, 1)
	best: Fleet_Transfer_Forecast
	found := false
	for days := min_days; days <= max_days; days += step {
		arrival := campaign_time_add(c.clock.now, days * CAMPAIGN_DAY_SECONDS)
		candidate := fleet_transfer_forecast(c, target, arrival)
		if !candidate.valid || !candidate.feasible do continue
		if !found ||
		   candidate.propellant_cost_kt < best.propellant_cost_kt - 1e-9 ||
		   candidate.propellant_cost_kt <= best.propellant_cost_kt + 1e-9 &&
			   candidate.duration_days < best.duration_days {
			best = candidate
			found = true
		}
	}
	return best, found
}

// The reciprocal of the fuel-saving recommendation: use the first protected
// grid point so campaign-time pressure can be traded against propellant rather
// than requiring players to hunt the arrival slider manually.
fleet_transfer_fastest_safe_window :: proc(
	c: ^Campaign,
	target: Celestial_Body_Ref,
	minimum_days, maximum_days, step_days: i64,
) -> (
	Fleet_Transfer_Forecast,
	bool,
) {
	min_days := max(minimum_days, 1)
	max_days := max(maximum_days, min_days)
	step := max(step_days, 1)
	for days := min_days; days <= max_days; days += step {
		arrival := campaign_time_add(c.clock.now, days * CAMPAIGN_DAY_SECONDS)
		candidate := fleet_transfer_forecast(c, target, arrival)
		if candidate.valid && candidate.feasible do return candidate, true
	}
	return {}, false
}

// When no protected leg exists, retain the player's emergency decision while
// surfacing the least severe reserve breach on the same deterministic grid.
fleet_transfer_best_emergency_window :: proc(
	c: ^Campaign,
	target: Celestial_Body_Ref,
	minimum_days, maximum_days, step_days: i64,
) -> (
	Fleet_Transfer_Forecast,
	bool,
) {
	min_days := max(minimum_days, 1)
	max_days := max(maximum_days, min_days)
	step := max(step_days, 1)
	best: Fleet_Transfer_Forecast
	found := false
	for days := min_days; days <= max_days; days += step {
		arrival := campaign_time_add(c.clock.now, days * CAMPAIGN_DAY_SECONDS)
		candidate := fleet_transfer_forecast(c, target, arrival)
		if !candidate.valid || !candidate.crosses_reserve do continue
		if !found ||
		   candidate.reserve_margin_kt > best.reserve_margin_kt + 1e-9 ||
		   candidate.reserve_margin_kt >= best.reserve_margin_kt - 1e-9 &&
			   candidate.propellant_cost_kt < best.propellant_cost_kt - 1e-9 ||
		   candidate.reserve_margin_kt >= best.reserve_margin_kt - 1e-9 &&
			   candidate.propellant_cost_kt <= best.propellant_cost_kt + 1e-9 &&
			   candidate.duration_days < best.duration_days {
			best = candidate
			found = true
		}
	}
	return best, found
}

fleet_harvest_rate :: proc(c: ^Campaign) -> f64 {
	rate: f64
	for ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		condition := clamp(1 - f64(ship.damage + ship.impairments.support) * .06, .25, 1)
		if ship.operational_role == .Tanker do rate += .22 * condition
		if ship.role == .Foundry do rate += .08 * condition
		if ship.role == .Survey do rate += .025 * condition
	}
	return rate
}

fleet_harvest_forecast :: proc(
	c: ^Campaign,
	target_propellant_kt: f64,
	latest_departure_at: Campaign_Time = 0,
	target_feedstock: i64 = 0,
) -> Fleet_Harvest_Forecast {
	fleet_resource_intel_update(c)
	result := Fleet_Harvest_Forecast {
		body = c.fleet_navigation.current_body,
	}
	if !c.fleet_navigation.initialized || c.fleet_navigation.phase != .Holding {
		result.cause = "The fleet must hold at a surveyed source."
		return result
	}
	at := fleet_deposit_index(c, result.body)
	if at < 0 {
		result.cause = "No recoverable material deposit is known at this orbit."
		return result
	}
	deposit := c.fleet_navigation.deposits[at]
	if deposit.intel < .Characterized {
		result.cause = "Close the range or assign a Survey ship to characterize this material signal."
		return result
	}
	throughput := deposit.accessibility * (1 - deposit.operating_difficulty * .35)
	result.propellant_rate_kt_day = fleet_harvest_rate(c) * throughput
	result.feedstock_rate_day = fleet_feedstock_harvest_rate(c) * throughput
	result.available_propellant_kt = deposit.remaining_propellant_kt
	result.available_feedstock = deposit.remaining_feedstock
	result.storage_headroom_kt = fleet_propellant_capacity(c) - fleet_propellant_remaining(c)
	result.target_propellant_kt = clamp(
		target_propellant_kt - fleet_propellant_remaining(c),
		0,
		result.storage_headroom_kt,
	)
	result.feedstock_headroom = fleet_feedstock_headroom(c)
	result.target_feedstock = clamp(
		target_feedstock,
		0,
		min(result.feedstock_headroom, result.available_feedstock),
	)
	if result.propellant_rate_kt_day <= 0 && result.feedstock_rate_day <= 0 ||
	   result.target_propellant_kt <= 1e-9 && result.target_feedstock <= 0 {
		result.cause =
			result.storage_headroom_kt <= 1e-9 && result.feedstock_headroom <= 0 ? "Fleet tanks and feedstock holds are full." : "No recovery work is required."
		return result
	}
	requested_propellant, requested_feedstock :=
		result.target_propellant_kt, result.target_feedstock
	propellant := min(requested_propellant, result.available_propellant_kt)
	feedstock := min(requested_feedstock, result.available_feedstock)
	propellant_days :=
		result.propellant_rate_kt_day > 0 ? propellant / result.propellant_rate_kt_day : 0
	feedstock_days :=
		result.feedstock_rate_day > 0 ? f64(feedstock) / result.feedstock_rate_day : 0
	result.duration_days = max(propellant_days, feedstock_days)
	result.target_propellant_kt = propellant
	result.target_feedstock = feedstock
	result.stop =
		propellant < requested_propellant || feedstock < requested_feedstock ? .Deposit_Exhausted : .Target_Reserve
	if latest_departure_at > c.clock.now {
		days_available :=
			f64(i64(latest_departure_at) - i64(c.clock.now)) / f64(CAMPAIGN_DAY_SECONDS)
		if days_available < result.duration_days {
			result.target_propellant_kt = min(
				result.target_propellant_kt,
				days_available * result.propellant_rate_kt_day,
			)
			result.target_feedstock = min(
				result.target_feedstock,
				i64(days_available * result.feedstock_rate_day),
			)
			result.duration_days = days_available
			result.stop = .Latest_Departure
		}
	}
	if deposit.intel == .Surveyed &&
	   deposit.interruption_fraction > 0 &&
	   result.duration_days > deposit.interruption_fraction * 12 {
		result.interruption_known = true
		result.stop = .Extraction_Interrupted
	}
	result.valid = result.target_propellant_kt > 1e-9 || result.target_feedstock > 0
	result.cause = "Recovery is limited by installed processing, cargo holds, and the declared departure boundary."
	return result
}

fleet_navigation_commit_transfer :: proc(
	c: ^Campaign,
	forecast: Fleet_Transfer_Forecast,
	emergency_override: bool = false,
) -> (
	bool,
	string,
) {
	if !forecast.valid || !forecast.feasible && !emergency_override do return false, forecast.cause
	fresh := fleet_transfer_forecast(c, forecast.target, forecast.arrival_at)
	if !fresh.valid || !fresh.feasible && !emergency_override do return false, fresh.cause
	if !fleet_propellant_consume(c, fresh.propellant_cost_kt) do return false, "The fleet no longer carries the forecast propellant."
	record_event(
		c,
		.Resource_Changed,
		fmt.tprintf(
			"The fleet committed %.1f kt of propellant to a %.1f-day transfer.",
			fresh.propellant_cost_kt,
			fresh.duration_days,
		),
	)
	c.fleet_navigation.last_navigation_event = c.event_sequence
	c.fleet_navigation.transfer = {
		active             = true,
		emergency_override = emergency_override,
		forecast           = fresh,
		cause_event        = c.event_sequence,
	}
	c.fleet_navigation.phase = .Transfer
	if campaign_schedule_work(
		   c,
		   .Fleet_Navigation,
		   FLEET_NAVIGATION_WORK_ID,
		   fresh.arrival_at,
		   70,
	   ) ==
	   0 {
		_ = fleet_propellant_gain(c, fresh.propellant_cost_kt)
		c.fleet_navigation.transfer = {}
		c.fleet_navigation.phase = .Holding
		return false, "The campaign work queue cannot accept the transfer."
	}
	if emergency_override {
		record_event(
			c,
			.Situation_Decided,
			"Emergency authority exposed the fleet's protected recovery reserve.",
			cause_sequence = c.fleet_navigation.last_navigation_event,
		)
	}
	return true, "Transfer committed. Fleet time will stop at arrival or a material deviation."
}

fleet_navigation_commit_harvest :: proc(
	c: ^Campaign,
	target_propellant_kt: f64,
	latest_departure_at: Campaign_Time = 0,
	target_feedstock: i64 = 0,
) -> (
	bool,
	string,
) {
	forecast := fleet_harvest_forecast(
		c,
		target_propellant_kt,
		latest_departure_at,
		target_feedstock,
	)
	if !forecast.valid do return false, forecast.cause
	hold_days := forecast.duration_days
	if forecast.interruption_known {
		at := fleet_deposit_index(c, c.fleet_navigation.current_body)
		if at >= 0 do hold_days *= c.fleet_navigation.deposits[at].interruption_fraction
	}
	due := campaign_time_add(c.clock.now, i64(math.ceil(hold_days * f64(CAMPAIGN_DAY_SECONDS))))
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The fleet began recovering propellant at its current body; the hold is limited to %.1f days.",
			forecast.duration_days,
		),
	)
	c.fleet_navigation.last_navigation_event = c.event_sequence
	c.fleet_navigation.harvest = {
		active                         = true,
		body                           = c.fleet_navigation.current_body,
		started_at                     = c.clock.now,
		due_at                         = due,
		latest_departure_at            = latest_departure_at,
		starting_propellant_kt         = fleet_propellant_remaining(c),
		target_propellant_kt           = target_propellant_kt,
		planned_propellant_kt          = forecast.target_propellant_kt,
		planned_propellant_rate_kt_day = forecast.propellant_rate_kt_day,
		target_feedstock               = target_feedstock,
		planned_feedstock              = forecast.target_feedstock,
		planned_feedstock_rate_day     = forecast.feedstock_rate_day,
		interruption_pending           = forecast.interruption_known,
		stop                           = forecast.stop,
		cause_event                    = c.event_sequence,
	}
	c.fleet_navigation.phase = .Harvesting
	if campaign_schedule_work(c, .Fleet_Navigation, FLEET_NAVIGATION_WORK_ID, due, 60) == 0 {
		c.fleet_navigation.harvest = {}
		c.fleet_navigation.phase = .Holding
		return false, "The campaign work queue cannot accept the recovery hold."
	}
	return true, "Recovery hold committed. Fleet time will stop at its governing condition."
}

fleet_navigation_resume_harvest :: proc(c: ^Campaign, accept_delay: bool) -> (bool, string) {
	if c == nil || c.fleet_navigation.phase != .Harvesting || !c.fleet_navigation.harvest.active || !c.fleet_navigation.harvest.interrupted do return false, "No material interruption awaits a response."
	order := &c.fleet_navigation.harvest
	if !accept_delay {
		order.active = false
		c.fleet_navigation.phase = .Holding
		c.fleet_navigation.last_stop = .Extraction_Interrupted
		record_event(
			c,
			.Situation_Decided,
			"The fleet departed the material source after its operating limit interrupted recovery.",
			cause_sequence = order.cause_event,
		)
		return true, "The fleet retained the recovered material and ended the hold."
	}
	order.interrupted = false
	order.planned_propellant_rate_kt_day *= .65
	order.planned_feedstock_rate_day *= .65
	days := max(
		order.planned_propellant_kt / max(order.planned_propellant_rate_kt_day, .001),
		f64(order.planned_feedstock) / max(order.planned_feedstock_rate_day, .001),
	)
	order.due_at = campaign_time_add(c.clock.now, i64(math.ceil(days * f64(CAMPAIGN_DAY_SECONDS))))
	if order.latest_departure_at > c.clock.now && order.due_at > order.latest_departure_at {
		order.due_at = order.latest_departure_at
		order.stop = .Latest_Departure
	}
	if campaign_schedule_work(c, .Fleet_Navigation, FLEET_NAVIGATION_WORK_ID, order.due_at, 60) == 0 do return false, "The campaign work queue cannot resume this recovery hold."
	record_event(
		c,
		.Situation_Decided,
		"The fleet accepted reduced extraction throughput and continued the recovery hold.",
		cause_sequence = order.cause_event,
	)
	return true, "Recovery resumed at reduced throughput."
}

fleet_navigation_resolve_due :: proc(c: ^Campaign, source_id: u64) {
	if source_id != FLEET_NAVIGATION_WORK_ID do return
	if c.fleet_navigation.phase == .Transfer && c.fleet_navigation.transfer.active {
		order := c.fleet_navigation.transfer
		state, ok := fleet_navigation_body_state(
			c,
			order.forecast.target,
			fleet_navigation_epoch_days(c),
		)
		if ok {
			c.fleet_navigation.current_body = order.forecast.target
			c.fleet_navigation.position_au = state.position_au
			c.fleet_navigation.velocity_au_day = state.velocity_au_day
		}
		c.fleet_navigation.transfer = {}
		c.fleet_navigation.phase = .Holding
		c.fleet_navigation.last_stop = ok ? .Arrived : .Material_Deviation
		record_event(
			c,
			.Situation_Decided,
			ok ? "The fleet completed its planned transfer and matched the target body." : "The target ephemeris could not be reconciled at arrival.",
			cause_sequence = order.cause_event,
		)
		_ = campaign_raise_attention(
			c,
			{
				source = .Fleet_Navigation,
				level = .Decision,
				source_id = FLEET_NAVIGATION_WORK_ID,
				cause_event = c.event_sequence,
				origin_event_id = order.cause_event,
				title = ok ? "FLEET TRANSFER COMPLETE" : "NAVIGATION PLAN DEVIATED",
				cause = ok ? "The fleet is holding at the planned body." : "Arrival state no longer matches the committed forecast.",
				default_action = "Open fleet navigation and plan the next leg.",
				choices = {"OPEN NAVIGATION", "", "", ""},
				choice_count = 1,
				default_choice = 0,
			},
		)
	} else if c.fleet_navigation.phase == .Harvesting && c.fleet_navigation.harvest.active {
		order := c.fleet_navigation.harvest
		at := fleet_deposit_index(c, order.body)
		recovered: f64
		feedstock: i64
		if at >= 0 {
			deposit := &c.fleet_navigation.deposits[at]
			if order.interruption_pending && !order.interrupted {
				fraction := deposit.interruption_fraction
				recovered = min(
					order.planned_propellant_kt * fraction,
					deposit.remaining_propellant_kt,
				)
				feedstock = min(
					i64(f64(order.planned_feedstock) * fraction),
					deposit.remaining_feedstock,
				)
				deposit.remaining_propellant_kt -= recovered
				deposit.remaining_feedstock -= feedstock
				recovered = fleet_propellant_gain(c, recovered)
				if feedstock > 0 do fleet_stock_gain(c, {raw_materials = feedstock}, .Recovery, order.cause_event)
				c.fleet_navigation.harvest.planned_propellant_kt = max(
					order.planned_propellant_kt - recovered,
					0,
				)
				c.fleet_navigation.harvest.planned_feedstock = max(
					order.planned_feedstock - feedstock,
					0,
				)
				c.fleet_navigation.harvest.interruption_pending = false
				c.fleet_navigation.harvest.interrupted = true
				record_event(
					c,
					.Resource_Changed,
					fmt.tprintf(
						"The fleet recovered %.1f kt of propellant and %d feedstock before an asteroid operating limit interrupted the hold.",
						recovered,
						feedstock,
					),
					cause_sequence = order.cause_event,
				)
				_ = campaign_raise_attention(
					c,
					{
						source = .Fleet_Navigation,
						level = .Decision,
						source_id = FLEET_NAVIGATION_WORK_ID,
						cause_event = c.event_sequence,
						origin_event_id = order.cause_event,
						title = "EXTRACTION INTERRUPTED",
						cause = "The asteroid's operating limit reduced extraction throughput.",
						default_action = "Depart with recovered material.",
						choices = {"DEPART", "CONTINUE SLOWLY", "", ""},
						choice_count = 2,
						default_choice = 0,
					},
				)
				return
			}
			recovered = min(order.planned_propellant_kt, deposit.remaining_propellant_kt)
			feedstock = min(order.planned_feedstock, deposit.remaining_feedstock)
			deposit.remaining_propellant_kt -= recovered
			deposit.remaining_feedstock -= feedstock
			recovered = fleet_propellant_gain(c, recovered)
			if feedstock > 0 do fleet_stock_gain(c, {raw_materials = feedstock}, .Recovery, order.cause_event)
		}
		c.fleet_navigation.harvest = {}
		c.fleet_navigation.phase = .Holding
		c.fleet_navigation.last_stop = order.stop
		record_event(
			c,
			.Resource_Changed,
			fmt.tprintf(
				"The fleet recovered %.1f kt of propellant and %d feedstock before the hold ended.",
				recovered,
				feedstock,
			),
			cause_sequence = order.cause_event,
		)
		_ = campaign_raise_attention(
			c,
			{
				source = .Fleet_Navigation,
				level = .Decision,
				source_id = FLEET_NAVIGATION_WORK_ID,
				cause_event = c.event_sequence,
				origin_event_id = order.cause_event,
				title = "PROPELLANT HOLD COMPLETE",
				cause = fmt.tprintf(
					"%.1f kt of propellant and %d feedstock entered fleet stores.",
					recovered,
					feedstock,
				),
				default_action = "Open fleet navigation and plan the next leg.",
				choices = {"OPEN NAVIGATION", "", "", ""},
				choice_count = 1,
				default_choice = 0,
			},
		)
	}
}

fleet_navigation_material_deviation :: proc(c: ^Campaign) -> (bool, string) {
	if c.fleet_navigation.phase != .Transfer || !c.fleet_navigation.transfer.active do return false, ""
	order := c.fleet_navigation.transfer
	for ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		if ship.impairments.mobility >= 3 {
			return true, fmt.tprintf(
				"%s lost the maneuver authority assumed by the plan.",
				ship.name,
			)
		}
	}
	if fleet_propellant_remaining(c) + 1e-6 < order.forecast.propellant_after_kt {
		return true, "A later commitment consumed propellant reserved by the active transfer."
	}
	return false, ""
}

// A transfer remains an executable standing order after a material change, but
// the player must be told when its declared safety boundary no longer holds.
// Reporting once preserves that choice without trapping the clock in duplicate
// attention prompts each simulation hour.
fleet_navigation_report_material_deviation :: proc(c: ^Campaign) -> bool {
	if c.fleet_navigation.phase != .Transfer ||
	   !c.fleet_navigation.transfer.active ||
	   c.fleet_navigation.transfer.deviation_reported {
		return false
	}
	deviated, cause := fleet_navigation_material_deviation(c)
	if !deviated do return false
	c.fleet_navigation.transfer.deviation_reported = true
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf("The active transfer deviated from its declared boundary: %s", cause),
		cause_sequence = c.fleet_navigation.transfer.cause_event,
	)
	_ = campaign_raise_attention(
		c,
		{
			source = .Fleet_Navigation,
			level = .Decision,
			source_id = FLEET_NAVIGATION_WORK_ID,
			cause_event = c.event_sequence,
			origin_event_id = c.fleet_navigation.transfer.cause_event,
			title = "NAVIGATION PLAN DEVIATED",
			cause = cause,
			default_action = "Acknowledge the changed condition and review the fleet record.",
			choices = {"OPEN NAVIGATION", "", "", ""},
			choice_count = 1,
			default_choice = 0,
		},
	)
	return true
}

// Recovery is continuous in the campaign fiction even though its ledger gain
// resolves at the hold boundary. If damage slows refining, preserve the work
// already completed at the originally forecast rate, revise only the remaining
// hold, and honor the departure deadline the player recorded.
fleet_navigation_report_harvest_deviation :: proc(c: ^Campaign) -> bool {
	if c.fleet_navigation.phase != .Harvesting ||
	   !c.fleet_navigation.harvest.active ||
	   c.fleet_navigation.harvest.deviation_reported {
		return false
	}
	order := &c.fleet_navigation.harvest
	at := fleet_deposit_index(c, order.body)
	if at < 0 do return false
	prior_rate := order.planned_propellant_rate_kt_day
	actual_rate := fleet_harvest_rate(c) * c.fleet_navigation.deposits[at].accessibility
	if actual_rate >= prior_rate - 1e-9 do return false
	elapsed_days := max(
		f64(i64(c.clock.now) - i64(order.started_at)) / f64(CAMPAIGN_DAY_SECONDS),
		0,
	)
	completed := min(
		order.planned_propellant_kt,
		elapsed_days * order.planned_propellant_rate_kt_day,
	)
	remaining := max(order.planned_propellant_kt - completed, 0)
	new_due := c.clock.now
	if actual_rate > 1e-9 && remaining > 1e-9 {
		new_due = campaign_time_add(
			c.clock.now,
			i64(math.ceil(remaining / actual_rate * f64(CAMPAIGN_DAY_SECONDS))),
		)
	}
	if order.latest_departure_at > c.clock.now && new_due > order.latest_departure_at {
		available_days :=
			f64(i64(order.latest_departure_at) - i64(c.clock.now)) / f64(CAMPAIGN_DAY_SECONDS)
		order.planned_propellant_kt =
			completed + min(remaining, max(actual_rate, 0) * available_days)
		order.stop = .Latest_Departure
		new_due = order.latest_departure_at
	}
	order.due_at = new_due
	order.planned_propellant_rate_kt_day = actual_rate
	order.deviation_reported = true
	_ = campaign_schedule_work(c, .Fleet_Navigation, FLEET_NAVIGATION_WORK_ID, new_due, 60)
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"Recovery throughput fell from %.3f to %.3f kt/day; the remaining hold was revised.",
			prior_rate,
			actual_rate,
		),
		cause_sequence = order.cause_event,
	)
	_ = campaign_raise_attention(
		c,
		{
			source = .Fleet_Navigation,
			level = .Decision,
			source_id = FLEET_NAVIGATION_WORK_ID,
			cause_event = c.event_sequence,
			origin_event_id = order.cause_event,
			title = "RECOVERY PLAN DEVIATED",
			cause = fmt.tprintf(
				"Damage reduced refining from %.3f to %.3f kt/day; the remaining hold was revised.",
				prior_rate,
				actual_rate,
			),
			default_action = "Review the revised recovery deadline and acknowledge the changed condition.",
			choices = {"OPEN NAVIGATION", "", "", ""},
			choice_count = 1,
			default_choice = 0,
		},
	)
	return true
}

fleet_navigation_initialize :: proc(c: ^Campaign) {
	if c == nil || c.galaxy == nil || c.galaxy.detailed_system_count <= 0 do return
	index := 0
	for gs, i in c.galaxy.detailed_systems[:c.galaxy.detailed_system_count] do if gs.neighborhood_index == c.outer_dark.continuum.anchor_neighborhood {index = i; break}
	system := &c.galaxy.detailed_systems[index].system
	body := Celestial_Body_Ref {
		kind  = .Star,
		index = 0,
	}
	if system.planet_count > 0 do body = {
		kind  = .Planet,
		index = 0,
	}
	c.fleet_navigation = {
		initialized                = true,
		phase                      = .Holding,
		system_index               = index,
		current_body               = body,
		protected_reserve_fraction = .2,
	}
	state, ok := system_body_state_at(system, body, 0)
	if ok {
		c.fleet_navigation.position_au = state.position_au
		c.fleet_navigation.velocity_au_day = state.velocity_au_day
	}
	for asteroid, i in system.asteroids[:system.asteroid_count] {
		if c.fleet_navigation.deposit_count >= MAX_RESOURCE_DEPOSITS do break
		water_fraction, feedstock_fraction: f64
		switch asteroid.inputs.composition {
		case .Icy:
			water_fraction, feedstock_fraction = .55, .01
		case .Carbonaceous:
			water_fraction, feedstock_fraction = .08, .32
		case .Silicate:
			water_fraction, feedstock_fraction = .01, .58
		case .Metallic:
			water_fraction, feedstock_fraction = .002, .82
		}
		accessibility := clamp(
			.8 -
			asteroid.surface_gravity_m_s2 * 200 -
			math.abs(asteroid.inputs.rotation_period_hours - 12) / 100,
			.2,
			.95,
		)
		recoverable_kt :=
			asteroid.mass_kg /
			1e6 *
			water_fraction *
			clamp(.0005 + accessibility * .0015, .0005, .002)
		difficulty := clamp(
			(1 - accessibility) * .7 + (!asteroid.cohesionless_spin_stable ? .4 : 0),
			0,
			1,
		)
		feedstock := i64(clamp(asteroid.mass_kg / 1e15 * feedstock_fraction * .35, 1, 192))
		c.fleet_navigation.deposits[c.fleet_navigation.deposit_count] = {
			body = {kind = .Asteroid, index = i},
			composition = asteroid.inputs.composition,
			initial_propellant_kt = recoverable_kt,
			remaining_propellant_kt = recoverable_kt,
			initial_feedstock = feedstock,
			remaining_feedstock = feedstock,
			water_fraction = water_fraction,
			feedstock_fraction = feedstock_fraction,
			accessibility = accessibility,
			operating_difficulty = difficulty,
			interruption_fraction = difficulty >= .62 ? .45 + f64(asteroid.seed % 25) / 100 : 0,
			intel = .Catalogued,
		}
		c.fleet_navigation.deposit_count += 1
	}
	fleet_propulsion_initialize_ships(c)
	fleet_propellant_sync_ledger(c)
}

fleet_propulsion_initialize_ships :: proc(c: ^Campaign) {
	if c == nil do return
	for &ship in c.ships[:c.ship_count] {
		capacity_scale := ship.operational_role == .Tanker ? .0007 : .0004
		ship.propellant_capacity_kt = max(f64(ship.mass_tonnes) * capacity_scale, 2)
		ship.propellant_kt = ship.propellant_capacity_kt * .65
		// High-energy fusion exhaust keeps system-scale transfers consequential
		// without requiring propellant to dominate the mass of habitat ships.
		ship.drive_exhaust_velocity_km_s = 450
		ship.drive_thrust_kilonewtons = max(f64(ship.mass_tonnes) * .015, 100)
	}
}
