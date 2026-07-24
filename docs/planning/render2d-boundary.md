# Render2D repository boundary

> **Planning status — 2026-07-24:** the ownership and migration-state sections
> describe the current boundary. “Remaining work” is a migration plan; the
> compatibility facade is still required by application callers.

Last Best Hope consumes the product-neutral `zelda_engine:render2d` contract.
The engine owns transient, reusable mechanisms: basic renderer data, camera and
clip math, plain geometry generation, input transitions, resource ownership
metadata, and consumer-supplied shader and batch-payload descriptors.

Last Best Hope owns all serializable and authored presentation policy:

- hatch presets and hatch-density policy;
- planet, star, SDF-volume, and Trinitron effects;
- shader implementations and packaged shader-manifest entries;
- graphical fixtures, tolerances, capture scenarios, and performance budgets.

`packages/canvas` is the compatibility adapter during migration. Its basic
vector, rectangle, color, texture, camera, and vertex names alias the engine
types. Its effect types, presets, push layout, and specialized draw operations
remain product-local. New reusable mechanisms should be added to `render2d`;
new visual policy should remain here.

The consumer supplies source identities, stages, entry points, and fallback
base paths through `render2d.Renderer_Descriptor`. The canvas adapter resolves
the engine shader manifest before trying the packaged fallback. Neither the
engine package nor its tests names or locates Last Best Hope shader assets.

Resource ownership is explicit. A renderer destroys only resources marked
`.Owned`; borrowed windows, Vulkan contexts, textures, attachments, UI context,
transient buffers, and consumer effect data outlive their use by the renderer.
In-flight device work must complete before owned GPU objects are destroyed.

## Current migration state

The engine owns reusable vector, rectangle, color, texture, camera, vertex,
batch, graph, input, renderer-descriptor, runtime, ownership, and metrics types.
It also owns plain geometry, camera and scissor math, SDL input translation, and
renderer lifecycle tests. `zelda_engine:ui` has no renderer dependency.

The compatibility facade still owns font and texture-file policy, LBH drawing
vocabulary, the product push-constant layout, effect encoding, Vulkan
composition, and the combat world-pass callback. Application callers still
import `packages/canvas`; removal is therefore not yet safe.

Generic UI helpers may own layout and interaction geometry. Last Best Hope keeps
its theme, fonts, engraving chrome, semantic colors, navigation vocabulary,
game-aware panels, save policy, and graphical fixtures.

## Remaining work

1. Replace product-specific submission operations with an opaque consumer
   payload encoder and consumer pass callbacks.
2. Migrate application callers to `zelda_engine:render2d` plus the LBH effect
   adapter, then remove the compatibility facade.
3. Migrate capture sequencing to the shared harness without changing fixture
   seeds, frame timing, names, or background-window behavior.
4. Compare graphical baselines at supported viewports and UI scales, run matched
   performance captures, and verify window, resize, shutdown, packaging,
   screenshot, gamepad, and reduced-motion behavior on supported platforms.

Acceptance requires equivalent rendering and input, no Last Best Hope concepts
or asset paths in the engine, a single reusable implementation of generic UI
and capture behavior, and no regression beyond the documented performance
budget.
