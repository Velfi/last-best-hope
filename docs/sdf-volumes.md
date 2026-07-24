# SDF volume renderer

`packages/canvas` exposes `DrawSdfVolume` for axis-aligned bounds and
`DrawSdfVolumeEllipse` for projected, rotated volumes. Both use
`Sdf_Volume_Config`:

- `kind`: `Debris`, `Nebula`, or `Radiation`;
- `density`: absorption and visible mass;
- `seed`: deterministic material variation;
- `noise_scale`: size of internal structures;
- `cell_smoothing`: reconstruction width between occupied Voronoi cells;
- `edge_softness`: transition at the signed-distance boundary;
- `depth`: distance traversed through the canonical volume.

Volume draws remain ordinary canvas batches. The fragment shader recognizes a
volume batch through its procedural mode, raymarches a bounded canonical SDF,
assigns deterministic occupancy to a 3D Voronoi voxelization, smooths the 27
neighboring cells into coherent lobes, and composites density front to back. It
needs no volume texture, descriptor, or additional render pass.

Occupied samples cast directional self-shadow through three secondary density
samples toward a fixed key light. Accumulated optical depth controls both local
illumination and up to three layers of the canvas crosshatch shader. Hatch
spacing remains screen-stable, while layer count and pressure follow the
volume's internal shadow rather than its bounding ellipse.

Presentation code is responsible for projecting world-space bounds and choosing
semantic color. Keep alpha restrained: the tactical outline should identify a
volume's rules, while the interior density communicates its occupied space.
Close Engagement currently uses `Debris` and `Radiation`; `Nebula` is available for
maps and future encounters.

## Evolved 5D creatures

`packages/game/geometry_4d.odin` defines the 4D primitives, ordered CSG
operations, and slice-normal calculation. `packages/game/sdf_creature.odin`
owns the deterministic, renderer-independent genome and evolutionary policy.
Creatures are made from ellipsoids, capsules, rounded boxes, tori,
superellipsoids, paired lobes, Clifford hypertori, thin laminae, and four-axis
ossicle crosses using hard or smooth union, subtraction, and intersection.
The latter motifs deliberately resist terrestrial body plans: their visible
holes, sheets, and arm counts change as the slice crosses the fourth axis. A
three-dimensional manifestation is a hyper-slice selected by
the fourth spatial coordinate `w`; moving `w` reveals coherent anatomical
change rather than applying a conventional mesh animation. The complete field
is `F(x, y, z, w, t)`: `w` remains a fourth spatial coordinate and `t` is an
independent temporal coordinate.

In the setting, `w` is selected by physical conditions such as correspondence,
curvature, and isolation-field state. Time drives continuous movement,
metabolism, development, and injury within the higher-dimensional body. Each
gene inherits a motion mode (pulse, drift, orbit, or traveling wave), phase,
frequency, amplitude, and optional temporal lifespan. Appendages inherit nearby
frequencies and offset phases, producing coordinated motion instead of unrelated
noise. See [`dark-ecology.md`](dark-ecology.md) for the ecological contract.

`evolve_sdf_creature` uses seeded MAP-Elites search, crossover, mutation, and
local elitism across 36 appendage, symmetry, and transformation niches. Fitness samples five 3D hyper-slices and rewards bounded occupied
volume, silhouette complexity, continuity between slices, visible change along
the fourth axis, temporal anatomical change, and reflection agreement across
all three visible axes. Symmetry compares only foreground-involved sample pairs,
so surrounding empty space cannot inflate the score. The component scores are
returned with the genome so tools can expose why a specimen was selected.

The game package owns genomes, selection, and reproducibility. A future canvas
or combat presentation can upload the fixed-size gene array and evaluate the
same smooth CSG expression in a raymarch shader. The Creature Generator screen
extracts SDF-gradient surface samples and renders them as depth-ordered,
surface-aligned Gaussian splats. Projected normals determine each splat's
anisotropic covariance and lighting; a GPU fragment path evaluates analytical
Gaussian coverage over batched oriented quads. The screen supports sparse,
balanced, and dense starting body plans, three evolution depths, orbit dragging,
and independent manual or automatic traversal of `w` and `t`. Time queries are
deterministic and do not mutate the genome: the same seed, W slice, and T value
always reconstruct the same three-dimensional body.

Generation develops a dominant core first, followed by surface-anchored
anterior mouth, recursive digestive tract, external fractal crown, appendages,
cavities, masks, and detail. The mouth uses a controlled oblique facing so its
aperture survives the default manifestation view; the gut is a 4D recursive
subtraction whose single connected field can appear as several visible lumens.
Two early appendage genes form an exact reflected pair across organism-local X,
including mirrored plane rotations, providing evolution with a bilateral
scaffold before later mutations introduce variation.
Viability gates reject empty or
excessively fragmented specimens before aesthetic scoring, preventing invalid
dust from occupying otherwise useful archive niches.

Every gene also carries six deterministic plane angles spanning XY, XZ, XW,
YZ, YW, and ZW. The evaluator inverse-rotates queries into primitive-local
space, allowing rings, laminae, and ossicles to cross the visible slice at
oblique angles rather than sharing a conspicuous world-axis alignment.

For generator review, `tools/creature_gallery` renders five evolved seeds at
three W slices into a portable pixmap contact sheet without opening the game:

```sh
odin run tools/creature_gallery \
  -collection:zelda_engine=../zelda-engine/packages -- \
  /tmp/creature-gallery.ppm 404
```

Columns hold a creature constant. The first three rows traverse W from `-0.65`
through `0` to `0.65`; the final two hold W at zero and advance biological time
to `1.7` and `3.4`. This makes buried appendages, over-large cores, accidental
terrestrial symmetry, fourth-axis topology, and internal fractal animation
visible during generator tuning.
