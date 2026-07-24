---
name: review-game-systems
description: Review a game, prototype, design document, or implementation to identify its core loops and system dynamics; determine whether those systems function, communicate causality, interact coherently, and create meaningful play; diagnose dominant strategies, runaway feedback, dead ends, busywork, weak recovery, and disconnected mechanics; and recommend prioritized design or implementation changes. Use for game-design reviews, system audits, mechanic critiques, prototype evaluations, balance investigations, and reviews of simulation or strategy-game code.
---

# Review Game Systems

Analyze the game as a set of coupled feedback systems. Separate observed evidence from inference, and separate functional correctness, legibility, and quality of play.

## Gather Evidence

Inspect the artifacts the user placed in scope: design documents, rules, code, tests, screenshots, telemetry, saves, or a playable build. Read repository instructions before reviewing project files. If player-facing text or visuals are in scope, read the project's relevant guidelines.

Do not pretend to have played an unplayable build. Label conclusions as:

- **Observed**: directly supported by code, rules, telemetry, or play.
- **Inferred**: follows from connected evidence but has not been tested directly.
- **Unknown**: evidence needed before judging.

When possible, trace at least one representative play sequence end to end instead of reviewing mechanics only in isolation.

## Map the System

Identify:

1. The player fantasy and object of care: what the player is managing and why outcomes matter.
2. The core recurring loop: observe, decide, commit, resolve, receive feedback, adapt.
3. Nested timescales: immediate, short-term, campaign-scale, and persistent aftermath.
4. State variables, resources, actors, relationships, and constraints.
5. Player levers and the costs, risks, information, and reversibility attached to them.
6. Positive feedback loops that create growth, momentum, or specialization.
7. Negative feedback loops that create resistance, recovery, or changing problems.
8. Connections through which one system changes another.
9. Feedback channels: map, animation, audio, alerts, tooltips, event text, history, and forecasts.

Express every important loop in causal form:

```text
pressure or opportunity
→ player intervention
→ simulation response
→ visible consequence
→ changed future decision
```

If the last step is missing, flag the loop as potentially closed but non-generative: it resolves state without creating new play.

For a detailed set of tests and failure patterns, read [references/review-rubric.md](references/review-rubric.md).

## Evaluate in Order

### 1. Functional integrity

Determine whether rules execute as described, state remains valid, outcomes are deterministic where required, save/load preserves the loop, and AI or automation can use the same system coherently. Look for unreachable states, stale derived values, circular dependencies, order-sensitive updates, exploits, and performance cliffs.

Do not make balance claims about a system that is not functionally reliable.

### 2. Causal legibility

Determine whether the player can answer:

- What changed?
- Why did it change?
- In which direction is it moving?
- What can I do about it?
- What will the known costs and risks be?

Treat incorrect or missing feedback as a system failure, not cosmetic polish. Check whether alerts are actionable, value breakdowns expose principal causes, and consequences arrive close enough to their causes to be learnable.

### 3. Meaningful play

Judge decisions by whether they offer materially different, informed, viable consequences. A decision is stronger when it contains tension among competing values, uncertainty the player can reason about, opportunity cost, and persistent effects.

Ask:

- Do multiple strategies remain viable in context, or does one option dominate?
- Does the decision change future state, or only refill a meter?
- Can the player form a plan and revise it from feedback?
- Do player identity, prior choices, or current conditions alter the answer?
- Are setbacks recoverable through interesting adaptation?
- Does mastery increase expressive control instead of removing all tension?

Do not equate complexity, randomness, punishment, or quantity of options with meaningful play.

### 4. System interaction

Check whether mechanics generate consequences for one another without collapsing into an opaque modifier soup. Prefer connections that change decisions over connections that merely add numeric bonuses.

For each connection, identify:

- the source state;
- the propagated effect;
- the receiving system;
- the player-visible explanation;
- the resulting new decision.

Flag orphan systems that consume attention but neither influence nor receive influence from the core loop.

### 5. Pacing and escalation

Check whether pressure is signaled before resolution, whether intervention windows are long enough to reason about, and whether escalation changes the problem rather than only increasing its magnitude. Examine action frequency, notification load, downtime, delayed consequences, and simultaneous crises.

### 6. Persistence and history

Check what remains after a loop resolves. Prefer consequences that alter relationships, capabilities, geography, institutions, identity, or future options. Verify that persistent state is recalled accurately rather than merely described as important.

### 7. Balance and resilience

Only after the prior checks, examine rates, thresholds, costs, reward curves, snowballing, death spirals, and comeback paths. Distinguish:

- **Parameter problem**: the structure produces good decisions at the wrong rate or magnitude.
- **Rule problem**: incentives or transitions produce the wrong behavior.
- **Structural problem**: the loop lacks agency, feedback, interaction, or consequential state.

Recommend tuning only for parameter problems.

## Diagnose Severity

Assign each finding:

- **Critical**: breaks the core loop, invalidates player understanding, corrupts state, or eliminates meaningful choice.
- **High**: repeatedly creates dominant play, opaque failure, non-decisions, or unrecoverable cascades.
- **Medium**: weakens pacing, variety, feedback, or system connection in common play.
- **Low**: localized friction or missed expressive potential.

Also state confidence and evidence. Do not manufacture findings to fill every category.

## Recommend Changes

Lead with the smallest change that addresses the diagnosed cause. For every recommendation, include:

1. The failure it addresses.
2. The changed rule, feedback, or implementation boundary.
3. The expected effect on player behavior.
4. Risks and interactions with adjacent systems.
5. A falsifiable validation method.

Prefer new decisions over flat penalties. Prefer visible causal links over additional explanatory prose. Prefer recoverable setbacks that change plans over abrupt run termination unless termination is the intended experience.

## Validate

Propose tests proportionate to the evidence available:

- deterministic scenario or seed tests for rule execution;
- invariant and save/load tests for state integrity;
- scripted simulations for rates, distributions, and runaway loops;
- expert playtests for depth and dominant strategies;
- first-use tests for causal comprehension;
- longitudinal sessions for pacing, persistence, and campaign recovery;
- telemetry questions tied to a stated hypothesis.

Do not use telemetry alone to infer why players behaved a certain way. Pair behavioral data with observation, interviews, or play diaries when motivation matters.

## Report

Use this compact structure unless the user requests another format:

1. **Verdict**: whether the core dynamics function and create meaningful play.
2. **System map**: causal description of the core and supporting loops.
3. **What works**: strengths supported by evidence.
4. **Findings**: severity, evidence, causal diagnosis, and player impact.
5. **Recommendations**: prioritized changes with risks.
6. **Validation plan**: tests and success criteria.
7. **Unknowns**: evidence that could change the judgment.

Use precise language. Describe what the rules cause players to do; do not certify what players feel without research evidence.
