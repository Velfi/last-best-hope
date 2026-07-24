# Documentation

This directory contains durable product contracts. Design intent, implemented
rules, and active technical boundaries belong here; completed plans, point-in-time
audits, and test transcripts do not. Repeatable measurements live under
`performance/`.

## Product

- [`diaspora-fleet.md`](diaspora-fleet.md) — player fantasy, campaign loop,
  persistent state, settlements, failure, and the Fleet/Passage relationship.
- [`simulation-story-refactor.md`](simulation-story-refactor.md) — authoritative
  simulation-to-story architecture and migration target.
- [`values-become-law.md`](values-become-law.md) — precedent rule model and
  player flow.
- [`value-law-library.md`](value-law-library.md) — authored content contract for
  the eight founding values.
- [`strategic-control-model.md`](strategic-control-model.md) — reserves,
  capacity, cohesion, and control.
- [`fleet-navigation.md`](fleet-navigation.md) — physical propellant, local
  transfers, harvesting, and the campaign navigation rhythm.

## Passage and setting

- [`passage-expeditions.md`](passage-expeditions.md) — continuous Dark
  expeditions, contracts, navigation, persistence, and implementation boundary.
- [`membrane-ftl.md`](membrane-ftl.md) — cosmology and transit invariants.
- [`dark-ecology.md`](dark-ecology.md) — Dark ecology and simulation model.
- [`stellar-system-model.md`](stellar-system-model.md) — stellar, orbital,
  climate, and habitability model.
- [`sdf-volumes.md`](sdf-volumes.md) — volume-rendering contract for manifested
  organisms.

## Fleet and combat

- [`ship-taxonomy.md`](ship-taxonomy.md) — hulls, configurations, roles, and
  tactical presentation.
- [`close-engagement.md`](close-engagement.md) — the implemented operation, controls,
  architecture, and performance budgets.
- [`close-engagement-command-model.md`](close-engagement-command-model.md) — command
  grammar and sidebar contract.
- [`fleet-ai-design.md`](fleet-ai-design.md) — command hierarchy, doctrine,
  autonomy, training, and validation.
- [`far-engagement.md`](far-engagement.md) — long-duration engagement model.

## Presentation and engineering

- [`art-direction.md`](art-direction.md) — visual language and asset review.
- [`writing-guidelines.md`](writing-guidelines.md) — player-facing prose.
- [`typography-accessibility.md`](typography-accessibility.md) — readability and
  accessibility invariants.
- [`render2d-boundary.md`](render2d-boundary.md) — engine/product ownership,
  migration status, and remaining work.
- [`campaign-validation.md`](campaign-validation.md) — release gates and latest
  authoritative campaign evidence.
- [`todo/README.md`](todo/README.md) — active dependency-ordered implementation
  roadmap.

## Performance evidence

- [`creature-render-profile-2026-07-22.md`](performance/creature-render-profile-2026-07-22.md)
  — creature gallery CPU profile and prepared-field optimization.
- [`close-engagement-visual-cost-2026-07-23.md`](performance/close-engagement-visual-cost-2026-07-23.md)
  — matched combat visual-cost measurements.

## Maintenance

- Update a system contract when behavior or intent changes; do not add a second
  status document.
- Put actionable work in the issue tracker or code-adjacent TODOs. A temporary
  implementation plan should be removed once its decisions are reflected in the
  relevant contract.
- Put reproducible benchmark results in `performance/`, including date, machine,
  command, seed, and budget.
- Link new durable documents from this index. Unlinked Markdown under `docs/`
  should be treated as a consolidation error.
