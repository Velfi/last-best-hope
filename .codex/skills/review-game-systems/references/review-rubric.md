# Game System Review Rubric

Use the relevant sections; do not force every review to answer every question.

## Contents

1. Loop anatomy
2. Meaningful-decision tests
3. Feedback dynamics
4. Legibility
5. Pacing and persistence
6. Implementation checks
7. Common failure patterns
8. Scoring guidance

## 1. Loop Anatomy

For each major loop, record:

| Field | Question |
|---|---|
| Trigger | What pressure or opportunity starts the loop? |
| Signal | How and when does the player learn about it? |
| Levers | What can the player change? |
| Commitment | What resource, time, position, relationship, or option is placed at risk? |
| Resolution | Which rules turn the commitment into an outcome? |
| Feedback | How are outcome, cause, and magnitude communicated? |
| Persistence | What remains after resolution? |
| Recurrence | How does the changed state produce another decision? |

Also record update cadence, affected entities, randomness, AI participation, and save-state requirements.

## 2. Meaningful-Decision Tests

### Alternatives

- Are at least two options viable under some understandable conditions?
- Are options different in kind, timing, or exposure—not only magnitude?
- Does “do nothing” have a modeled consequence when it is available?

### Information

- Can the player estimate outcomes well enough to own the decision?
- Is uncertainty bounded, signaled, and affected by preparation?
- Are hidden consequences surprises rather than concealed rules?

### Tradeoffs

- Does each strong benefit consume or endanger something relevant?
- Does a choice move pressure between systems, actors, or timescales?
- Can one universal currency trivially solve unrelated problems?

### Context

- Do current state, previous choices, identity, geography, or relationships change the best answer?
- Does the decision remain interesting after the player understands the rules?
- Does expertise reveal additional options rather than a fixed script?

### Consequence

- Does the outcome alter future choices?
- Can the game recall who acted, what was promised, or what was damaged?
- Does success create responsibility or exposure as well as power?

## 3. Feedback Dynamics

### Positive loops

Identify compounding growth such as wealth producing more wealth, territory producing more military capacity, or reputation attracting more allies.

Ask:

- What starts the snowball?
- How early does it become irreversible?
- Does growth introduce qualitatively new obligations or only larger numbers?
- Can rivals recognize and respond to it?

### Negative loops

Identify resistance and recovery such as upkeep, logistics, legitimacy, dissent, congestion, or coalition formation.

Ask:

- Does resistance create a decision or merely slow the player?
- Is it causally connected to the behavior it constrains?
- Can the player prepare, adapt, or accept an alternate outcome?
- Does recovery preserve history, or erase the episode?

### Cascades

Trace at least one adverse and one beneficial cascade across systems. Check for:

- amplification without intervention windows;
- several penalties driven by the same underlying variable;
- recovery resources disabled by the state that requires recovery;
- oscillation around thresholds;
- binary penalties that flicker on and off;
- stabilizers that eliminate interesting variance.

## 4. Legibility

For important state, verify that the player can see:

- current magnitude and direction;
- principal causes and their relative contribution;
- thresholds or plausible outcome range;
- time until consequence where knowable;
- available interventions and opportunity costs;
- whether an effect is temporary, persistent, reversible, or precedent-setting.

Check information hierarchy. The most actionable cause should not be buried beneath exhaustive detail. Aggregate routine changes; interrupt play only for decisions or consequences that merit interruption.

## 5. Pacing and Persistence

### Pacing

- Does signal precede crisis?
- Is there enough time for more than one response?
- Does waiting ever constitute a strategic choice?
- Do nested loops peak simultaneously too often?
- Does the player spend more time issuing maintenance commands than revising plans?
- Does late-game scale increase delegation or only click volume?

### Persistence

- Which consequences survive the current encounter, turn, or campaign phase?
- Are records specific enough to be referenced later?
- Do changed relationships or practices affect rules?
- Does the game preserve responsibility for outcomes?
- Can repeated temporary effects accumulate into history?

## 6. Implementation Checks

### State and determinism

- Keep authoritative state separate from presentation and executable policy.
- Derive display values from authoritative state or invalidate caches reliably.
- Use explicit ordering for dependent updates.
- Route randomness through seeded streams appropriate to the project.
- Ensure iteration order and collection layout do not alter deterministic outcomes.
- Serialize active processes, cooldowns, provenance, and scheduled consequences.

### Data-driven rules

- Separate reusable mechanics from authored content.
- Give triggers, effects, weights, cooldowns, and scopes validation errors.
- Provide trace output for failed triggers and numeric breakdowns.
- Make authored content hot-reloadable where practical.
- Record causal provenance for player-facing values and events.

### Time and performance

- Assign systems deliberate update cadences rather than evaluating everything every frame.
- Measure cost by entity count and interaction count, not aggregate population labels.
- Avoid global scans for local state changes.
- Test late-campaign object counts and pathological fragmentation.

### AI and automation

- Prefer the same actions and constraints for players and AI.
- Expose AI weights and rejected-action reasons.
- Test whether automation preserves player intent.
- Ensure AI competence does not depend on hidden exemptions that invalidate player reasoning.

### Testing

- Test invariants and transitions separately from balance.
- Create scenario fixtures for every threshold and resolution path.
- Test save/load at each active phase.
- Compare identical seeds across builds when determinism matters.
- Use simulation batches for distributional questions; use human tests for comprehension and meaning.

## 7. Common Failure Patterns

| Pattern | Diagnostic sign | Typical intervention |
|---|---|---|
| Closed non-generative loop | Player restores a meter and returns to the prior state | Add persistent aftermath or cross-system consequence |
| Non-decision | One option is superior across contexts | Introduce distinct costs, timing, exposure, or identity constraints |
| Modifier soup | Many bonuses change totals without changing plans | Collapse modifiers and create fewer rule-changing effects |
| Orphan system | Mechanic consumes attention but affects no core decision | Connect it causally or remove/automate it |
| Whack-a-mole | Frequent local problems demand repetitive correction | Add policy, delegation, batching, or slower consequential choices |
| Death spiral | Failure removes the tools required to recover | Preserve recovery levers and convert loss into changed goals |
| Empty snowball | Growth increases output but introduces no new play | Add obligations, exposure, rivals, or coordination problems |
| Opaque cascade | Distant effects arrive without provenance | Surface causal chain, forecasts, and contribution breakdowns |
| Threshold flicker | Penalties repeatedly toggle at a boundary | Add hysteresis, staged escalation, or a progress-based situation |
| Fake uncertainty | Outcome is hidden but unaffected by player knowledge | Add signals, preparation, or explicit risk ranges |
| Content bandage | Events describe importance unsupported by mechanics | Persist and reuse consequential state in later rules |
| Premature tuning | Values are adjusted before the loop works | Repair agency, feedback, or structure before balancing |

## 8. Scoring Guidance

Use scores only when comparison or tracking benefits from them. Score each dimension from 0–4 and always accompany the number with evidence.

| Score | Meaning |
|---|---|
| 0 | Missing or fundamentally broken |
| 1 | Present but commonly fails its purpose |
| 2 | Functional with important structural weaknesses |
| 3 | Strong in normal play with bounded issues |
| 4 | Consistently creates clear, adaptive, consequential play |

Suggested dimensions:

- functional integrity;
- causal legibility;
- decision quality;
- system interaction;
- pacing;
- persistence;
- resilience and recovery;
- implementation observability.

Do not average scores into a single number when a critical failure would be hidden by the average.
