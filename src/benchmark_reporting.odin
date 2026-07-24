package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:os"
import filepath "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"
import ui "zelda_engine:ui"
import benchmark "zelda_engine:benchmark"

galaxy_benchmark_report :: proc(label: string, zoom: f64, cpu, gpu: []f64) {
	CPU_DRAW_P95_BUDGET_MS :: 14.0
	benchmark.sort_samples(cpu)
	benchmark.sort_samples(gpu)
	median_index := len(cpu) / 2
	p95_index := min((len(cpu) * 95 + 99) / 100 - 1, len(cpu) - 1)
	if len(gpu) > 0 {
		gpu_median_index := len(gpu) / 2
		gpu_p95_index := min((len(gpu) * 95 + 99) / 100 - 1, len(gpu) - 1)
		fmt.print("{\"scenario\":\"")
		fmt.print(label)
		fmt.printf("\",\"zoom\":%.0f,\"samples\":%d,\"cpu_draw_ms\":", zoom, len(cpu))
		fmt.print("{\"median\":")
		fmt.printf(
			"%.4f,\"p95\":%.4f,\"max\":%.4f",
			cpu[median_index],
			cpu[p95_index],
			cpu[len(cpu) - 1],
		)
		fmt.print("},\"cpu_draw_p95_budget_ms\":")
		fmt.printf(
			"%.1f,\"budget_pass\":%v,\"gpu_frame_ms\":",
			CPU_DRAW_P95_BUDGET_MS,
			cpu[p95_index] <= CPU_DRAW_P95_BUDGET_MS,
		)
		fmt.print("{\"median\":")
		fmt.printf(
			"%.4f,\"p95\":%.4f,\"max\":%.4f",
			gpu[gpu_median_index],
			gpu[gpu_p95_index],
			gpu[len(gpu) - 1],
		)
		fmt.println("}}")
	} else {
		fmt.print("{\"scenario\":\"")
		fmt.print(label)
		fmt.printf("\",\"zoom\":%.0f,\"samples\":%d,\"cpu_draw_ms\":", zoom, len(cpu))
		fmt.print("{\"median\":")
		fmt.printf(
			"%.4f,\"p95\":%.4f,\"max\":%.4f",
			cpu[median_index],
			cpu[p95_index],
			cpu[len(cpu) - 1],
		)
		fmt.print("},\"cpu_draw_p95_budget_ms\":")
		fmt.printf(
			"%.1f,\"budget_pass\":%v,\"gpu_frame_ms\":null",
			CPU_DRAW_P95_BUDGET_MS,
			cpu[p95_index] <= CPU_DRAW_P95_BUDGET_MS,
		)
		fmt.println("}")
	}
}

combat_render_benchmark_report :: proc(label: string, seed: u64, cpu, gpu: []f64) {
	CPU_DRAW_P95_BUDGET_MS :: 8.0; GPU_FRAME_BUDGET_MS :: 16.67
	benchmark.sort_samples(
		cpu,
	); benchmark.sort_samples(gpu); median := len(cpu) / 2; p95 := min((len(cpu) * 95 + 99) / 100 - 1, len(cpu) - 1)
	fmt.print(
		"{\"scenario\":\"",
	); fmt.print(label); fmt.printf("\",\"seed\":%d,\"samples\":%d,\"cpu_draw_ms\":", seed, len(cpu)); fmt.print("{\"median\":"); fmt.printf("%.4f,\"p95\":%.4f,\"max\":%.4f", cpu[median], cpu[p95], cpu[len(cpu) - 1]); fmt.printf("},\"cpu_draw_p95_budget_ms\":%.2f,\"cpu_budget_pass\":%v,\"gpu_frame_ms\":", CPU_DRAW_P95_BUDGET_MS, cpu[p95] <= CPU_DRAW_P95_BUDGET_MS)
	if len(gpu) >
	   0 {gpu_median := len(gpu) / 2; gpu_p95 := min((len(gpu) * 95 + 99) / 100 - 1, len(gpu) - 1); fmt.print("{\"median\":"); fmt.printf("%.4f,\"p95\":%.4f,\"max\":%.4f", gpu[gpu_median], gpu[gpu_p95], gpu[len(gpu) - 1]); fmt.printf("},\"gpu_frame_budget_ms\":%.2f,\"gpu_p95_budget_pass\":%v,\"gpu_max_budget_pass\":%v}\n", GPU_FRAME_BUDGET_MS, gpu[gpu_p95] <= GPU_FRAME_BUDGET_MS, gpu[len(gpu) - 1] <= GPU_FRAME_BUDGET_MS)} else {fmt.println("null,\"gpu_frame_budget_ms\":16.67,\"gpu_timestamp_available\":false}")}
}

passage_render_benchmark_report :: proc(seed: u64, cpu, wall, gpu: []f64) {
	benchmark.sort_samples(cpu); benchmark.sort_samples(wall); benchmark.sort_samples(gpu)
	median :=
		len(cpu) /
		2; p95 := min((len(cpu) * 95 + 99) / 100 - 1, len(cpu) - 1); p99 := min((len(cpu) * 99 + 99) / 100 - 1, len(cpu) - 1)
	fmt.print(
		"{\"scenario\":\"passage-16-generated-creatures\",\"resolution\":\"1920x1080\",\"seed\":",
	); fmt.printf("%d,\"samples\":%d,", seed, len(cpu))
	fmt.printf(
		"\"visible_creatures\":%d,\"genome_cache_uploads\":%d,\"ray_step_ceiling\":52,\"resolution_tier\":1.0,",
		combat_3d.creature_visible_count,
		combat_3d.creature_cache_uploads,
	)
	fmt.print(
		"\"cpu_draw_ms\":{",
	); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"p99\":%.4f,\"max\":%.4f},", cpu[median], cpu[p95], cpu[p99], cpu[len(cpu) - 1])
	fmt.print(
		"\"wall_frame_ms\":{",
	); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"p99\":%.4f,\"max\":%.4f},\"frame_budget_ms\":16.67,\"wall_p95_budget_pass\":%v,", wall[median], wall[p95], wall[p99], wall[len(wall) - 1], wall[p95] <= 16.67)
	if len(gpu) >
	   0 {gm := len(gpu) / 2; gp95 := min((len(gpu) * 95 + 99) / 100 - 1, len(gpu) - 1); gp99 := min((len(gpu) * 99 + 99) / 100 - 1, len(gpu) - 1); fmt.print("\"gpu_frame_ms\":{"); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"p99\":%.4f,\"max\":%.4f},\"gpu_p95_budget_pass\":%v}\n", gpu[gm], gpu[gp95], gpu[gp99], gpu[len(gpu) - 1], gpu[gp95] <= 16.67)} else {fmt.println("\"gpu_frame_ms\":null,\"gpu_timestamp_available\":false}")}
}

ship_generator_benchmark_report :: proc(
	seed: u64,
	family: game.Procedural_Ship_Family,
	cpu, wall, gpu: []f64,
) {
	CPU_P95_BUDGET_MS :: 8.0; FRAME_P95_BUDGET_MS :: 16.67
	benchmark.sort_samples(cpu); benchmark.sort_samples(wall); benchmark.sort_samples(gpu)
	median := len(cpu) / 2; p95 := min((len(cpu) * 95 + 99) / 100 - 1, len(cpu) - 1)
	fmt.print(
		"{\"scenario\":\"ship-generator-detail\",\"resolution\":\"3840x2160\",\"seed\":",
	); fmt.printf("%d,\"family\":\"%v\",\"samples\":%d,", seed, family, len(cpu))
	fmt.print(
		"\"cpu_draw_ms\":{",
	); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"cpu_p95_budget_ms\":%.2f,\"cpu_budget_pass\":%v,", cpu[median], cpu[p95], cpu[len(cpu) - 1], CPU_P95_BUDGET_MS, cpu[p95] <= CPU_P95_BUDGET_MS)
	fmt.print(
		"\"wall_frame_ms\":{",
	); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"frame_p95_budget_ms\":%.2f,\"wall_budget_pass\":%v,", wall[median], wall[p95], wall[len(wall) - 1], FRAME_P95_BUDGET_MS, wall[p95] <= FRAME_P95_BUDGET_MS)
	if len(gpu) >
	   0 {gpu_median := len(gpu) / 2; gpu_p95 := min((len(gpu) * 95 + 99) / 100 - 1, len(gpu) - 1); fmt.print("\"gpu_frame_ms\":{"); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"gpu_p95_budget_ms\":%.2f,\"gpu_budget_pass\":%v}\n", gpu[gpu_median], gpu[gpu_p95], gpu[len(gpu) - 1], FRAME_P95_BUDGET_MS, gpu[gpu_p95] <= FRAME_P95_BUDGET_MS)} else {fmt.println("\"gpu_frame_ms\":null,\"gpu_p95_budget_ms\":16.67,\"gpu_timestamp_available\":false}")}
}

planet_detail_benchmark_report :: proc(
	seed: u64,
	kind: game.System_Planet_Kind,
	cpu, atmosphere, gpu: []f64,
) {
	CPU_P95_BUDGET_MS :: 8.0; GPU_P95_BUDGET_MS :: 16.67; ATMOSPHERE_P95_BUDGET_MS :: 1.0
	benchmark.sort_samples(cpu); benchmark.sort_samples(atmosphere); benchmark.sort_samples(gpu)
	median := len(cpu) / 2; p95 := min((len(cpu) * 95 + 99) / 100 - 1, len(cpu) - 1)
	fmt.print(
		"{\"scenario\":\"planet-detail\",\"seed\":",
	); fmt.printf("%d,\"kind\":\"%v\",\"samples\":%d,", seed, kind, len(cpu))
	fmt.print(
		"\"cpu_frame_ms\":{",
	); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"cpu_p95_budget_ms\":%.2f,\"cpu_budget_pass\":%v,", cpu[median], cpu[p95], cpu[len(cpu) - 1], CPU_P95_BUDGET_MS, cpu[p95] <= CPU_P95_BUDGET_MS)
	fmt.print(
		"\"atmosphere_cpu_ms\":{",
	); fmt.printf("\"median\":%.6f,\"p95\":%.6f,\"max\":%.6f},\"atmosphere_p95_budget_ms\":%.2f,\"atmosphere_budget_pass\":%v,", atmosphere[median], atmosphere[p95], atmosphere[len(atmosphere) - 1], ATMOSPHERE_P95_BUDGET_MS, atmosphere[p95] <= ATMOSPHERE_P95_BUDGET_MS)
	if len(gpu) >
	   0 {gpu_median := len(gpu) / 2; gpu_p95 := min((len(gpu) * 95 + 99) / 100 - 1, len(gpu) - 1); fmt.printf("\"gpu_frame_ms\":{\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"gpu_p95_budget_ms\":%.2f,\"gpu_budget_pass\":%v}\n", gpu[gpu_median], gpu[gpu_p95], gpu[len(gpu) - 1], GPU_P95_BUDGET_MS, gpu[gpu_p95] <= GPU_P95_BUDGET_MS)} else {fmt.println("\"gpu_frame_ms\":null,\"gpu_p95_budget_ms\":16.67,\"gpu_timestamp_available\":false}")}
}

star_detail_benchmark_report :: proc(seed: u64, class: game.Star_Class, cpu, wall, gpu: []f64) {
	CPU_P95_BUDGET_MS :: 8.0; GPU_P95_BUDGET_MS :: 16.67
	benchmark.sort_samples(cpu); benchmark.sort_samples(wall); benchmark.sort_samples(gpu)
	median := len(cpu) / 2; p95 := min((len(cpu) * 95 + 99) / 100 - 1, len(cpu) - 1)
	fmt.print(
		"{\"scenario\":\"star-detail\",\"resolution\":\"3840x2160\",\"seed\":",
	); fmt.printf("%d,\"class\":\"%v\",\"samples\":%d,", seed, class, len(cpu))
	fmt.print(
		"\"cpu_frame_ms\":{",
	); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"cpu_p95_budget_ms\":%.2f,\"cpu_budget_pass\":%v,", cpu[median], cpu[p95], cpu[len(cpu) - 1], CPU_P95_BUDGET_MS, cpu[p95] <= CPU_P95_BUDGET_MS)
	fmt.print(
		"\"wall_frame_ms\":{",
	); fmt.printf("\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"frame_budget_ms\":%.2f,\"wall_p95_budget_pass\":%v,", wall[median], wall[p95], wall[len(wall) - 1], GPU_P95_BUDGET_MS, wall[p95] <= GPU_P95_BUDGET_MS)
	if len(gpu) >
	   0 {gpu_median := len(gpu) / 2; gpu_p95 := min((len(gpu) * 95 + 99) / 100 - 1, len(gpu) - 1); fmt.printf("\"gpu_frame_ms\":{\"median\":%.4f,\"p95\":%.4f,\"max\":%.4f},\"gpu_p95_budget_ms\":%.2f,\"gpu_budget_pass\":%v}\n", gpu[gpu_median], gpu[gpu_p95], gpu[len(gpu) - 1], GPU_P95_BUDGET_MS, gpu[gpu_p95] <= GPU_P95_BUDGET_MS)} else {fmt.println("\"gpu_frame_ms\":null,\"gpu_p95_budget_ms\":16.67,\"gpu_timestamp_available\":false}")}
}
