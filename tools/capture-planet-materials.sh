#!/bin/sh
set -eu

output_dir="${1:-build/material-calibration}"
seed="${2:-24301}"
binary="${LBH_BINARY:-build/last-best-hope}"

mkdir -p "$output_dir/surface" "$output_dir/atmosphere"

for material in silicate iron-oxide liquid-water water-ice sulfur carbon methane ammonia vegetation; do
	"$binary" --capture-planet "$output_dir/surface/$material.png" "$seed" "material-surface-$material"
done

for material in water ammonia methane sulfur; do
	"$binary" --capture-planet "$output_dir/atmosphere/$material.png" "$seed" "material-atmosphere-$material"
done

printf 'Captured 13 deterministic material plates in %s\n' "$output_dir"
