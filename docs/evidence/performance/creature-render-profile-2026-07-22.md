# Creature rendering CPU profile — 2026-07-22

## Scope

- Machine: MacBook Pro `Mac16,5`, Apple M4 Max (14 cores), 36 GB RAM.
- Scenario: seed 404, four evolved creatures, five panels per creature,
  600×750 PPM contact sheet.
- Build: `odin build tools/creature_gallery ... -o:speed -debug`.
- Tree: working directory snapshot; this directory is not a Git checkout, so no
  revision or clean-base comparison is available.
- Repetitions: three valid sequential runs after one discarded smoke run.

## Measurements

| Metric | Run A | Run B | Run C | Median | Worst | Budget | Status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Evolution total (ms) | 4828.609 | 4611.993 | 4592.912 | 4611.993 | 4828.609 | 60000 | Pass |
| Rendering total (ms) | 4642.933 | 4594.711 | 4498.258 | 4594.711 | 4642.933 | 15000 | Pass |
| Rendering per panel (ms) | 232.147 | 229.736 | 224.913 | 229.736 | 232.147 | 750 | Pass |
| End-to-end total (ms) | 9472.092 | 9207.217 | 9092.343 | 9207.217 | 9472.092 | — | Informational |

Worst-case render time has 69.0% headroom against both render budgets. The
render range is 3.1% of the median, inside the 5% relative-noise tolerance.
Evolution's range is 5.1%, slightly above that tolerance because the first run
was colder; no relative performance conclusion is made.

## CPU sample

A three-second macOS `sample` capture was attached after the measured evolution
window, covering the contact-sheet render phase. It collected 2609 main-thread
samples.

- `sdf_creature_distance_at` was the largest identified leaf: 892 samples
  (34.2%). Almost all remaining stacks were descendants of the same SDF query.
- `__sincos_stret` plus its call stub accounted for at least 481 leaf samples
  (18.4%); additional unsymbolized `libsystem_m` frames sit beneath the same
  trigonometric calls.
- `render_panel` itself had only 9 self samples (0.3%). Ray traversal and pixel
  orchestration are not the primary leaf cost.
- `pow` had 12 leaf samples (0.5%). Superellipsoid exponentiation is minor.

The primary optimization candidate is rotation preparation. Every point query
visits every gene, and `geometry_4d_primitive_distance` recomputes sine and cosine
for all six 4D plane rotations. Preparing animated genes and their rotation
coefficients once per `(genome, time)` panel should remove repeated trigonometry
from both sphere-tracing steps and six normal samples. A matched benchmark is
required before claiming that optimization succeeds.

## Reproduction

```sh
odin build tools/creature_gallery \
  -collection:zelda_engine=/Users/zelda/Documents/zelda-engine/packages \
  -out:/tmp/creature-gallery-profile -o:speed -debug

/tmp/creature-gallery-profile /tmp/creature-profile.ppm 404
```

Artifacts from this run:

- `/tmp/creature-render.sample.txt` — full-workload eight-second sample.
- `/tmp/creature-render-only.sample.txt` — render-window three-second sample.
- `/tmp/creature-profile-{a,b,c}.ppm` — matched benchmark outputs.

This report is a profile of the current snapshot, not an accepted performance
baseline. Accept a baseline only from an explicitly approved checkpoint.

## Prepared-field optimization

Animated genes, six outer 4D plane rotations, and every bounded fractal-fold
angle are now prepared once per `(genome, time)` sampling batch. Rendering and
fitness evaluation reuse those coefficients for every SDF query.

Three new matched optimized runs produced:

| Metric | Before median | After median | Delta | Change | After worst |
| --- | ---: | ---: | ---: | ---: | ---: |
| Evolution total (ms) | 4611.993 | 1243.154 | −3368.839 | −73.0% | 1289.593 |
| Rendering total (ms) | 4594.711 | 1435.964 | −3158.747 | −68.7% | 1559.318 |
| Rendering per panel (ms) | 229.736 | 71.798 | −157.938 | −68.7% | 77.966 |
| End-to-end total (ms) | 9207.217 | 2679.626 | −6527.591 | −70.9% | 2849.422 |

The after runs retain 89.6% render-budget headroom. Their PPM SHA-256 hashes
match the before artifact exactly:
`17533290d6eff5d4edcb92a6b3856ce60002f94692423a44ee73d19b230c99c2`.

The final render-window sample collected 891 samples. No sine or cosine frame
appeared in its reported hotspot list; `sdf_creature_prepared_distance` now
accounts for 868 leaf samples (97.4%), `pow` for 12 (1.3%), and gallery
orchestration for 9 (1.0%). The remaining work is the intended primitive and CSG
math rather than repeatable transform setup.

Final artifacts:

- `/tmp/creature-profile-final-{1,2,3}.ppm` — matched optimized outputs.
- `/tmp/creature-render-final.sample.txt` — final render-window CPU sample.
