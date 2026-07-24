package main

import game "../../packages/game"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:time"

sort_samples :: proc(values: []f64) {
	for i in 1 ..< len(values) {
		value := values[i]
		j := i
		for j > 0 && values[j - 1] > value {
			values[j] = values[j - 1]
			j -= 1
		}
		values[j] = value
	}
}

main :: proc() {
	samples := 180
	seed := u64(0x5eed)
	if len(os.args) >
	   1 {parsed, ok := strconv.parse_int(os.args[1]); if ok do samples = clamp(parsed, 60, 900)}
	if len(os.args) >
	   2 {parsed, ok := strconv.parse_int(os.args[2]); if ok && parsed >= 0 do seed = u64(parsed)}

	mission := game.combat_new_finale_mission(seed)
	defer game.combat_mission_destroy(&mission)
	for _ in 0 ..< 20 do game.combat_tick_fixed(&mission, .05)

	values: [900]f64
	for i in 0 ..< samples {
		started := time.tick_now()
		game.combat_tick_fixed(&mission, .05)
		values[i] = time.duration_seconds(time.tick_since(started)) * 1000
	}
	sort_samples(values[:samples])
	p95_index := clamp(int(math.ceil(f64(samples) * .95)) - 1, 0, samples - 1)
	roster_bytes := len(mission.ships) * size_of(game.Combat_Ship_Record)
	fmt.printf(
		"{{\"scenario\":\"combat-finale\",\"seed\":%d,\"samples\":%d,\"ships\":%d,\"units\":%d,\"tick_p95_ms\":%.4f,\"tick_max_ms\":%.4f,\"tick_budget_pass\":%v,\"roster_bytes\":%d,\"memory_budget_pass\":%v}}\n",
		seed,
		samples,
		mission.ship_count,
		mission.unit_count,
		values[p95_index],
		values[samples - 1],
		values[p95_index] <= 2,
		roster_bytes,
		roster_bytes < 64 * 1024 * 1024,
	)
}
