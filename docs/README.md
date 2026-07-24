# Documentation

Documentation is organized by what it claims, not by subsystem. Read a document
in `project/` as a description of the repository's present contract. Read a
document in `world/` as setting and simulation-reference material. Read
`planning/` as a proposal or migration target; it is not a promise that the
feature is already playable. `evidence/` holds dated measurements, studies, and
machine-readable baselines rather than enduring product truth.

## Project as implemented

- [`close-engagement.md`](project/close-engagement.md) — playable Recover the
  Seedship operation, controls, architecture, and budgets.
- [`close-engagement-command-model.md`](project/close-engagement-command-model.md)
  — implemented stance/action/ability grammar and its remaining extension seam.
- [`far-engagement.md`](project/far-engagement.md) — fleet-scale engagement
  simulation and presentation contract.
- [`fleet-navigation.md`](project/fleet-navigation.md) — fleet transfer,
  harvesting, and attention behavior.
- [`passage-expeditions.md`](project/passage-expeditions.md) — implemented
  continuous Dark-expedition state, navigation, and persistence contract.
- [`ship-taxonomy.md`](project/ship-taxonomy.md) — production hull and
  operational-role vocabulary.
- [`strategic-control-model.md`](project/strategic-control-model.md) —
  authoritative strategic reserves, capacity, and cohesion model.
- [`sdf-volumes.md`](project/sdf-volumes.md) — SDF creature-rendering boundary.
- [`art-direction.md`](project/art-direction.md),
  [`typography-accessibility.md`](project/typography-accessibility.md), and
  [`writing-guidelines.md`](project/writing-guidelines.md) — current
  presentation and player-facing-text standards.

## World reference

- [`membrane-ftl.md`](world/membrane-ftl.md) — Dark cosmology and transit
  invariants.
- [`dark-ecology.md`](world/dark-ecology.md) — Dark organisms, ecology, and
  encounter evidence.
- [`stellar-system-model.md`](world/stellar-system-model.md) — stellar,
  orbital, climate, and habitability model.

## Planning and migration targets

- [`simulation-story-refactor.md`](planning/simulation-story-refactor.md) —
  move authored situations toward simulation-derived collisions.
- [`diaspora-fleet.md`](planning/diaspora-fleet.md) — intended campaign loop,
  persistent-fleet design, and vertical-slice target.
- [`values-become-law.md`](planning/values-become-law.md) and
  [`value-law-library.md`](planning/value-law-library.md) — precedent-law
  framework scope and the proposed authored value library.
- [`fleet-ai-design.md`](planning/fleet-ai-design.md) — next command-hierarchy
  and tactical-autonomy work.
- [`ship-physics-grammar.md`](planning/ship-physics-grammar.md) — future
  physics-first ship-generator direction.
- [`render2d-boundary.md`](planning/render2d-boundary.md) — remaining Render2D
  extraction work.

## Evidence

- [`campaign-validation.md`](evidence/campaign-validation.md) — dated campaign
  gates and latest available balance evidence.
- [`performance/`](evidence/performance/) — dated profiles, budgets, and
  renderer baselines.
- [`playtests/`](evidence/playtests/) — study protocol, sessions, and chronicle.
- [`validation/`](evidence/validation/) and
  [`visual-baselines/`](evidence/visual-baselines/) — machine-readable results
  and captures.

## Maintenance

- Put present-tense, code-verified contracts in `project/`.
- Put fictional facts, scientific assumptions, and simulation-reference models
  in `world/`; mark any implementation boundary there explicitly.
- Put unimplemented work, alternatives, delivery sequences, and migration steps
  in `planning/`. Move or rewrite a plan when its target becomes the current
  contract.
- Keep dated results in `evidence/`, with their command, seed, machine, and
  budget where applicable. Do not promote a dated result into a current claim
  without a new validation run.
- Link every durable Markdown document from this index. Do not retain a link to
  a document that does not exist.
