package main

import rl "zelda_engine:canvas2d"
import "core:fmt"
import benchmark "zelda_engine:benchmark"

SHIP_HATCH_BENCHMARK_COLUMNS :: 32
SHIP_HATCH_BENCHMARK_ROWS :: 18

ship_hatch_benchmark_quad_count :: proc() -> int {return(
		SHIP_HATCH_BENCHMARK_COLUMNS *
		SHIP_HATCH_BENCHMARK_ROWS \
	)}

ship_hatch_benchmark_label :: proc(phase: int) -> string {
	switch phase {
	case 0:
		return "fill-merged"
	case 1:
		return "hatch-1-layer-merged"
	case 2:
		return "hatch-4-layer-merged"
	case 3:
		return "hatch-4-layer-varied-batches"
	}
	return "unknown"
}

draw_ship_hatch_benchmark :: proc(phase: int, width, height: f32) {
	rl.DrawRectangle(0, 0, i32(width), i32(height), {0, 0, 0, 255})
	config := LBH_HATCH_ENGRAVING
	config.invert = true
	config.layer_count = phase == 1 ? 1 : 4
	config.thresholds = {0, 0, 0, 0}
	config.irregularity = phase >= 2 ? .28 : 0
	cell_w :=
		width /
		f32(SHIP_HATCH_BENCHMARK_COLUMNS); cell_h := height / f32(SHIP_HATCH_BENCHMARK_ROWS)
	for row in 0 ..< SHIP_HATCH_BENCHMARK_ROWS do for column in 0 ..< SHIP_HATCH_BENCHMARK_COLUMNS {
		x := f32(column) * cell_w; y := f32(row) * cell_h
		cell_config := phase == 0 ? rl.HATCH_DISABLED : config
		if phase == 3 do cell_config.offset = {f32((column * 37 + row * 11) % 97), f32((column * 13 + row * 41) % 89)}
		rl.DrawQuadHatched({x, y}, {x + cell_w, y}, {x + cell_w, y + cell_h}, {x, y + cell_h}, {231, 229, 211, 180}, cell_config)
	}
}

ship_hatch_benchmark_report :: proc(
	phase: int,
	label: string,
	quad_count: int,
	cpu, wall, gpu: []f64,
) {
	CPU_P95_BUDGET_MS :: 2.0; FRAME_P95_BUDGET_MS :: 16.67
	benchmark.sort_samples(cpu); benchmark.sort_samples(wall); benchmark.sort_samples(gpu)
	median := len(cpu) / 2; p95 := min((len(cpu) * 95 + 99) / 100 - 1, len(cpu) - 1)
	fmt.print(
		"{\"scenario\":\"ship-hatching-",
	); fmt.print(label); fmt.printf("\",\"phase\":%d,\"resolution\":\"3840x2160\",\"quads\":%d,\"samples\":%d,", phase, quad_count, len(cpu))
	fmt.print(
		"\"cpu_draw_ms\":{",
	); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"cpu_p95_budget_ms\":%.2f,\"cpu_budget_pass\":%v,", cpu[median], cpu[p95], cpu[len(cpu) - 1], CPU_P95_BUDGET_MS, cpu[p95] <= CPU_P95_BUDGET_MS)
	fmt.print(
		"\"wall_frame_ms\":{",
	); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"frame_p95_budget_ms\":%.2f,\"wall_budget_pass\":%v,", wall[median], wall[p95], wall[len(wall) - 1], FRAME_P95_BUDGET_MS, wall[p95] <= FRAME_P95_BUDGET_MS)
	if len(gpu) >
	   0 {gpu_median := len(gpu) / 2; gpu_p95 := min((len(gpu) * 95 + 99) / 100 - 1, len(gpu) - 1); fmt.print("\"gpu_frame_ms\":{"); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"gpu_p95_budget_ms\":%.2f,\"gpu_budget_pass\":%v}\n", gpu[gpu_median], gpu[gpu_p95], gpu[len(gpu) - 1], FRAME_P95_BUDGET_MS, gpu[gpu_p95] <= FRAME_P95_BUDGET_MS)} else {fmt.println("\"gpu_frame_ms\":null,\"gpu_timestamp_available\":false}")}
}
