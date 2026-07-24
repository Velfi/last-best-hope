package main

import game "../../packages/game"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:time"

PANEL :: 150
COLUMNS :: 4
ROWS :: 5
WIDTH :: PANEL * COLUMNS
HEIGHT :: PANEL * ROWS

pixel :: proc(image: []u8, x, y: int, value: u8) {
	if x < 0 || y < 0 || x >= WIDTH || y >= HEIGHT do return
	at := (x + y * WIDTH) * 3
	image[at], image[at + 1], image[at + 2] = value, value, u8(f32(value) * .91)
}

render_panel :: proc(
	image: []u8,
	genome: ^game.Sdf_Creature_Genome,
	column, row: int,
	w, time: f64,
) {
	prepared := game.sdf_creature_prepare_at(genome, time)
	for py in 5 ..< PANEL - 5 {
		for px in 5 ..< PANEL - 5 {
			x := (f64(px) / f64(PANEL - 1) * 2 - 1) * 1.45
			y := (1 - f64(py) / f64(PANEL - 1) * 2) * 1.45
			hit := false
			hit_z := -1.55
			// Conservative sphere tracing is much faster than a fixed-depth scan,
			// while a small floor keeps approximate CSG distances moving forward.
			for step in 0 ..< 72 {
				distance := game.sdf_creature_prepared_distance(&prepared, {x, y, hit_z, w})
				if distance < .004 {hit = true; break}
				hit_z += max(distance * .68, .012)
				if hit_z > 1.55 do break
			}
			if !hit do continue
			normal, ok := game.sdf_creature_prepared_slice_normal(
				&prepared,
				{x, y, hit_z, w},
				.008,
			)
			light := .54
			if ok do light = clamp(.34 + normal[0] * -.22 + normal[1] * .42 + normal[2] * -.36, .16, 1.0)
			depth := clamp((hit_z + 1.55) / 3.10, 0, 1)
			value := u8(clamp((light * .72 + (1 - depth) * .28) * 235, 32, 242))
			// Sparse engraved cuts keep broad surfaces from becoming flat white.
			if (px + py * 2 + int(math.abs(hit_z) * 31)) % 17 == 0 do value = u8(f32(value) * .42)
			pixel(image, column * PANEL + px, row * PANEL + py, value)
		}
	}
	// Slice registration marks make panel boundaries readable on black.
	for x in 8 ..< PANEL - 8 {pixel(image, column * PANEL + x, row * PANEL + 8, 48); pixel(image, column * PANEL + x, (row + 1) * PANEL - 9, 48)}
}

main :: proc() {
	output := "creature-gallery.ppm"
	base_seed := u64(404)
	if len(os.args) > 1 do output = os.args[1]
	if len(os.args) >
	   2 {parsed, ok := strconv.parse_int(os.args[2]); if ok && parsed >= 0 do base_seed = u64(parsed)}
	image := make([]u8, WIDTH * HEIGHT * 3); defer delete(image)
	total_started := time.tick_now()
	evolution_seconds, render_seconds := 0.0, 0.0
	slices := [3]f64{-.65, 0, .65}
	times := [2]f64{1.7, 3.4}
	for column in 0 ..< COLUMNS {
		evolution_started := time.tick_now()
		result := game.evolve_sdf_creature(base_seed + u64(column) * 7919, 6)
		evolution_seconds += time.duration_seconds(time.tick_since(evolution_started))
		fmt.printf(
			"seed=%d fitness=%.3f symmetry=%.3f topology=%.3f temporal=%.3f voids=%.3f appendages=%d genes=%d\n",
			base_seed + u64(column) * 7919,
			result.fitness.total,
			result.fitness.symmetry,
			result.fitness.topology_change,
			result.fitness.temporal_change,
			result.fitness.void_expression,
			result.fitness.appendages,
			result.creature.gene_count,
		)
		render_started := time.tick_now()
		for w, row in slices do render_panel(image, &result.creature, column, row, w, 0)
		for biological_time, index in times do render_panel(image, &result.creature, column, index + 3, 0, biological_time)
		render_seconds += time.duration_seconds(time.tick_since(render_started))
	}
	header := fmt.aprintf("P6\n%d %d\n255\n", WIDTH, HEIGHT); defer delete(header)
	data := make([dynamic]u8, 0, len(header) + len(image)); defer delete(data)
	append(&data, ..transmute([]u8)header); append(&data, ..image)
	if err := os.write_entire_file(output, data[:]); err != nil {fmt.eprintln(err); os.exit(1)}
	fmt.printf("wrote %s (%dx%d)\n", output, WIDTH, HEIGHT)
	total_seconds := time.duration_seconds(time.tick_since(total_started))
	fmt.printf(
		"{{\"scenario\":\"creature-gallery\",\"seed\":%d,\"creatures\":%d,\"panels_per_creature\":%d,\"width\":%d,\"height\":%d,\"evolution_ms\":%.3f,\"render_ms\":%.3f,\"render_ms_per_panel\":%.3f,\"total_ms\":%.3f}}\n",
		base_seed,
		COLUMNS,
		ROWS,
		WIDTH,
		HEIGHT,
		evolution_seconds * 1000,
		render_seconds * 1000,
		render_seconds * 1000 / f64(COLUMNS * ROWS),
		total_seconds * 1000,
	)
}
