#!/bin/sh
set -eu

atlas=${1:-assets/ships/combat-archetype-icons-atlas-v1.png}
output_dir=${2:-assets/ships/combat-archetype-icons-v1}
rebuilt_atlas=${3:-assets/ships/combat-archetype-icons-atlas-v1.png}

command -v magick >/dev/null 2>&1 || {
	printf '%s\n' 'recenter_craft_symbols.sh requires ImageMagick (magick).' >&2
	exit 1
}

names='scout interceptor fighter strike-fighter bomber assault-shuttle
patrol-boat corvette torpedo-boat gunship picket-frigate combat-frigate
support-frigate minelayer-frigate destroyer light-cruiser heavy-cruiser battlecruiser
battleship carrier dreadnought utility-hull transport-hull habitat-hull'

# The generated symbols wandered across the nominal 256 px cell edges. These
# separators sit in the empty valleys between the six visual groups, allowing
# each complete symbol (including detached role marks) to be recovered first.
x_starts='0 299 544 783 1016 1247'
x_ends='299 544 783 1016 1247 1536'

mkdir -p "$output_dir"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/craft-symbols.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

index=0
for name in $names; do
	row=$((index / 6))
	column=$((index % 6))
	x_start=$(printf '%s\n' "$x_starts" | cut -d ' ' -f $((column + 1)))
	x_end=$(printf '%s\n' "$x_ends" | cut -d ' ' -f $((column + 1)))
	width=$((x_end - x_start))
	y_start=$((row * 256))

	magick "$atlas" \
		-crop "${width}x256+${x_start}+${y_start}" +repage \
		-trim +repage \
		-gravity center -background none -extent 256x256 \
		"$output_dir/$name.png"
	index=$((index + 1))
done

magick \
	\( "$output_dir/scout.png" "$output_dir/interceptor.png" "$output_dir/fighter.png" "$output_dir/strike-fighter.png" "$output_dir/bomber.png" "$output_dir/assault-shuttle.png" +append \) \
	\( "$output_dir/patrol-boat.png" "$output_dir/corvette.png" "$output_dir/torpedo-boat.png" "$output_dir/gunship.png" "$output_dir/picket-frigate.png" "$output_dir/combat-frigate.png" +append \) \
	\( "$output_dir/support-frigate.png" "$output_dir/minelayer-frigate.png" "$output_dir/destroyer.png" "$output_dir/light-cruiser.png" "$output_dir/heavy-cruiser.png" "$output_dir/battlecruiser.png" +append \) \
	\( "$output_dir/battleship.png" "$output_dir/carrier.png" "$output_dir/dreadnought.png" "$output_dir/utility-hull.png" "$output_dir/transport-hull.png" "$output_dir/habitat-hull.png" +append \) \
	-background none -append "$work_dir/rebuilt.png"

mv "$work_dir/rebuilt.png" "$rebuilt_atlas"
