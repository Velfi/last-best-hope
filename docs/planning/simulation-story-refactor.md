# Simulation-generated story refactor

> **Planning status — 2026-07-24:** this is a migration target. The current
> codebase still includes the narrative director and authored situation paths it
> describes replacing; none of the numbered phases should be read as completed
> unless a current contract and tests say so.

## Decision

`Last Best Hope` will author systems, pressures, actor behavior, and intervention
verbs. It will not author complete situations with predetermined casts, choices,
or outcomes.

The simulation is authoritative. A player-facing story beat is a legible view of
an existing conflict in campaign state. Choosing an intervention submits an
ordinary simulation command. The resulting history records what the simulation
actually changed.

This refactor preserves the deterministic campaign, continuous Dark, economies,
institutions, precedents, relationships, and persistent ships. It replaces the
legacy `Fleet_Situation` construction path and narrows the narrative director to
attention management.

## Product target

The campaign should repeatedly produce this loop:

```text
independent systems create pressure
→ dependencies expose named actors and valued futures
→ incompatible protections become simultaneously relevant
→ the player redirects risk through a simulation command
→ systems advance and resolve the consequences
→ persistent changes alter a later decision
```

A surfaced conflict is eligible for player interruption only when:

1. at least one persistent actor, place, institution, promise, or capability is
   materially exposed;
2. at least two valuable outcomes cannot both be fully protected;
3. the player has at least two legal, materially different interventions;
4. waiting or choosing changes future simulation state;
5. at least one consequence survives the immediate resolution.

If standing policy produces an uncontested legal answer, the simulation acts
without pausing and records the result.

## Current boundary

The current simulation already provides suitable sources:

- fleet and settlement material economies;
- typed fleet stock and protected operating floors;
- ship damage, roles, traits, histories, captains, and relationships;
- communities, grievances, institutions, mandates, and authority;
- promises, obligations, precedents, historical fronts, and contested records;
- Passage routes, manifests, ecology, relays, separated groups, and discoveries;
- combat missions and persistent ship outcomes.

The legacy interaction path crosses the wrong boundary. Functions such as
`make_repair_debt_situation`, `make_rescue_situation`, and
`make_settlement_situation` construct:

- a dramatic title and proposal;
- a selected cast;
- fixed positions and reasons;
- a fixed array of bespoke choices;
- bespoke resolution effects.

Those functions use real state, but they still author the complete dramatic
shape. The outcome space is determined by the situation constructor rather than
by the current set of legal simulation operations.

The existing narrative director has a second, narrower problem: priority and
repetition control are useful, but `major_story_beat_ready` treats pacing as a
permission to create or surface content. Pacing should suppress interruptions,
not suppress simulation consequences or manufacture importance.

## New architecture

### 1. Pressure

A pressure is a continuously or discretely changing simulation condition. It is
not a story beat.

```odin
Pressure_ID :: distinct u64

Pressure_Kind :: enum {
    Reserve_Shortfall,
    Capability_Strain,
    Ship_Exposure,
    Community_Grievance,
    Obligation_Due,
    Promise_Risk,
    Authority_Conflict,
    Route_Instability,
    Ecological_Contact,
    Settlement_Dependency,
    Information_Dispute,
}

Pressure :: struct {
    id:               Pressure_ID,
    kind:             Pressure_Kind,
    source:           Entity_Ref,
    affected:         [MAX_PRESSURE_AFFECTED]Entity_Ref,
    affected_count:   int,
    magnitude:        i32,
    direction:        Pressure_Direction,
    warning_threshold:i32,
    failure_threshold:i32,
    deadline:         i32,
    origin_event:     u64,
    last_change_event:u64,
    semantic_tags:    Semantic_Tags,
}
```

Pressure adapters expose existing authoritative state. They do not duplicate it.
For example, a reserve pressure reads the fleet ledger; it does not store another
supplies value. Persistent pressure records are justified only when identity or
history cannot be reconstructed from current state.

### 2. Dependency

A dependency explains why pressure on one entity matters elsewhere.

```odin
Dependency_Kind :: enum {
    Houses,
    Supplies,
    Repairs,
    Commands,
    Represents,
    Protects,
    Carries_Record,
    Maintains_Route,
    Owes_Promise,
    Relies_On_Trade,
    Shares_Crew,
}

Dependency :: struct {
    source:       Entity_Ref,
    target:       Entity_Ref,
    kind:         Dependency_Kind,
    strength:     i32,
    capacity:     i64,
    origin_event: u64,
    last_event:   u64,
}
```

Dependencies must affect rules. A repair dependency changes repair availability;
a record dependency changes which knowledge survives; a command dependency
changes authority or autonomous behavior. A relationship that affects only prose
is not a dependency.

Most initial dependencies can be projected from existing state:

- ship role and community;
- settlement founder and participating ships;
- trade flows and named routes;
- active commitments and promises;
- Passage cargo, records, relays, and task-group membership;
- institution custody and mandate reviewers;
- ship relationships where their strength already changes behavior.

### 3. Collision

A collision is a read-only diagnosis that two or more pressures compete for
shared capacity, authority, time, location, or actors.

```odin
Collision_ID :: distinct u64

Collision :: struct {
    id:                  Collision_ID,
    pressures:           [MAX_COLLISION_PRESSURES]Pressure_ID,
    pressure_count:      int,
    exposed:             [MAX_COLLISION_ACTORS]Entity_Ref,
    exposed_count:       int,
    contested_capability:Capability_Ref,
    deadline:            i32,
    origin_events:       [MAX_COLLISION_CAUSES]u64,
    origin_event_count:  int,
    stakes:              Stake_Vector,
    severity:            i32,
    persistence:         i32,
    novelty:             i32,
}
```

Collision detectors are generic joins over state, not scenario generators.
Initial detectors:

- two demands require the same insufficient stock or capacity;
- an obligation's required actor is damaged, committed, separated, or opposed;
- a mission objective and safe return cannot both fit the forecast budget;
- a mandate conflicts with captain policy, precedent, or community position;
- rescue mass and mission cargo exceed available holds;
- keeping a promise closes the operating margin of another named dependency;
- a settlement route failure exposes both a community and a fleet capability;
- disclosing a record satisfies one authority and violates another binding rule.

Every detector must be order-independent and produce a stable ID from the
identities of its sources. It may not consume simulation randomness.

### 4. Affordance

An affordance is a legal simulation operation applicable to a collision. It is
not a bespoke story choice.

```odin
Affordance :: struct {
    command:             Campaign_Command,
    legal:               bool,
    known_cost:          Cost_Vector,
    protected:           Stake_Vector,
    exposed:             Stake_Vector,
    reversible:          bool,
    forecast_confidence: i32,
    principal_causes:    [MAX_AFFORDANCE_CAUSES]u64,
    cause_count:         int,
}
```

Affordances come from command providers owned by the receiving system:

- allocate, reserve, release, substitute, ration, repair, or defer;
- commission, recall, split, reroute, withdraw, transmit, or remain;
- uphold policy, grant an exception, compel compliance, or transfer authority;
- disclose, restrict, review, or transmit a record;
- found, postpone, amend, evacuate, or dissolve a settlement commitment.

Each command executes through one authoritative rule path whether selected by a
human, bot, captain, institution, or standing policy. UI code never applies the
consequence directly.

A collision is not eligible for interruption unless at least two legal
affordances protect different stakes. "Pay the affordable amount or refuse" is
not sufficient when payment dominates and creates no new exposure.

### 5. Attention

The renamed `Attention_Director` selects which eligible collision, if any,
receives focus. It cannot create collisions, casts, choices, or consequences.

Selection order:

1. mandatory deadlines or irreversible transitions;
2. severity of exposed persistent stakes;
3. difference among legal affordances;
4. persistence of the expected consequences;
5. causal novelty and actor repetition;
6. stable seeded tie-break.

Story tempo controls the interruption budget, not simulation frequency:

- mandatory collisions always surface;
- suppressed collisions remain live and may worsen, resolve through policy, or
  become irrelevant;
- routine autonomous resolutions enter the chronicle without a modal;
- unresolved collisions are reconsidered when their state changes, not merely
  when a cooldown expires.

The director records why a collision was selected and which higher-scoring
collisions were deferred. This preserves the current auditability.

### 6. Presentation

Presentation is generated from structured facts after collision and affordance
calculation.

A decision view contains:

- the concrete state change that created the collision;
- the exposed named actors or futures;
- the shared constraint;
- the deadline or trend;
- legal commands with known costs, protected stakes, exposed stakes, and
  reversibility;
- links to the causal events and relevant ledger breakdowns.

Templates may turn structured facts into grammatical sentences. They must not
invent motives, certify historical meaning, or promise an outcome the command
does not implement.

The chronicle records actions and resulting state changes separately:

```text
E142: Resolute remained at Relay Orison to preserve the transmitted record.
E143: The fleet recovered 3 fewer Navigation capacity while Resolute was absent.
E151: Common Hearth assumed Resolute's survey obligation.
```

The game does not add "this sacrifice defined the fleet." Later dependencies,
behavior, and decisions establish significance.

## Representative end-to-end sequence

This sequence is illustrative state composition, not an authored scenario:

1. A settlement economy imports food through a correspondence maintained by
   `Resolute`.
2. Passage damage reduces `Resolute`'s safe return margin.
3. A fleet sustenance need commissions the task group to recover crop stock.
4. Rescue survivors occupy holds needed by that stock.
5. A relay forecast shows that immediate transmission is possible but return
   before coherence failure is not guaranteed.
6. Pressure adapters expose food, rescue, ship-survival, record, and route
   pressures.
7. Dependencies connect the settlement to the route, the route to `Resolute`,
   the survivors to their sponsor, and the fleet to the cargo.
8. A collision detector finds that time and hold capacity cannot protect every
   stake.
9. Command providers offer only currently legal operations: abandon cargo,
   transfer survivors, split the task group, transmit and remain, attempt the
   return, or withdraw from the objective.
10. The player submits one command.
11. Passage, economy, ship autonomy, and public authority resolve normally.
12. New dependencies and records change later repair, settlement, mandate, and
    expedition decisions.

The engine authored none of those twelve steps as a complete event. Designers
authored the systems that made the collision possible and the operations that
can redirect it.

## Implementation boundaries

### `packages/game`

Owns:

- pressure projection and stable identities;
- dependency projection and persistent dependency records;
- collision detection;
- affordance enumeration and command validation;
- attention selection;
- autonomous policy resolution;
- command execution;
- causal event recording;
- save validation and deterministic tests.

### `src`

Owns:

- collision, pressure, dependency, and forecast presentation;
- causal inspection and ledger breakdowns;
- player command requests;
- pacing transitions and acknowledgement;
- no rule resolution and no alternative consequence tables.

### Bot and agent interface

Bots and external agents receive the same collisions and affordances exposed to
the player. They choose command IDs, not situation choice indices. Hidden state
remains hidden. A policy may decline interruption and allow standing rules to
resolve the collision.

## Migration plan

### Phase 1: establish the command seam

1. Introduce `Entity_Ref`, `Stake_Vector`, `Cost_Vector`, and a stable
   `Campaign_Command` envelope.
2. Wrap existing public-question, capacity, settlement, Passage, and authority
   mutations behind command validation and execution.
3. Route bots and UI through the same command path.
4. Add command preview tests proving that advertised known costs match execution.

No legacy interaction is removed in this phase.

### Phase 2: project pressure and dependencies

1. Add read-only adapters over ledgers, needs, obligations, promises, ships,
   settlements, passages, and institutions.
2. Add a debug report listing active pressures and dependency paths.
3. Require every projected pressure to cite authoritative source state and a
   causal event.
4. Verify that projection does not mutate RNG or campaign state.

### Phase 3: implement three collision detectors

Start with high-value cross-system conflicts:

1. shared capacity contention;
2. mission objective versus safe return;
3. mandate versus actor autonomy or precedent.

For each detector, enumerate affordances from existing commands and expose a
developer-only collision view. Do not add prose polish yet.

### Phase 4: replace legacy interactions vertically

Replace in this order:

1. repair debt;
2. rescue continuation;
3. contested evidence;
4. settlement founding;
5. value hard cases.

For each replacement:

- delete the complete situation constructor only after parity tests pass;
- preserve existing persistent effects where they remain structurally valid;
- remove fixed choice arrays and choice-index bot policy;
- derive actor positions from current policy, memory, and dependencies;
- allow the collision not to occur when the necessary state does not intersect.

Value hard cases should be the final migration. A value is tested only when an
ordinary collision makes compliance and exception materially different. The
game must not schedule a test merely because a value has gone untested.

### Phase 5: narrow the narrative director

1. Rename narrative candidates to attention candidates.
2. Admit only detected collisions or required acknowledgements.
3. Replace beat cooldown gating with an interruption budget plus mandatory
   overrides.
4. Preserve seeded, order-independent ranking and deferred-candidate audit data.
5. Remove narrative ship casting. Actors must enter through dependencies or
   command jurisdiction.

### Phase 6: remove legacy state

After save-format migration and matched validation:

- remove `Fleet_Situation`, `Situation_Kind`, `Situation_Choice`, bespoke
  situation effects, and their string ownership paths;
- remove `surface_interaction`, `advance_interaction`, and
  `resolve_interaction`;
- remove situation queues and choice-index protocol fields;
- retain event causality, semantic tags, precedent facts, and public records.

An explicit save-format break is preferable to silently reconstructing live
legacy choices from insufficient state.

## Determinism requirements

- Pressure and dependency projection is pure for a campaign snapshot.
- Collision identity is derived from sorted stable source identities.
- Detector output is independent of collection iteration order.
- Affordance enumeration is stable and command IDs do not depend on UI order.
- Attention tie-breaking uses the campaign seed and stable collision ID without
  consuming the simulation RNG.
- Preview functions do not advance time, consume randomness, or mutate caches
  that affect resolution.
- Autonomous and player-issued commands use the same execution procedure.
- Save/load preserves every persistent input needed to reproduce an active
  collision and its legal affordances.

## Validation

### Functional

- permutation tests for detector order independence;
- preview-versus-execution property tests for known costs;
- command legality tests before and after save/load;
- invariant tests preventing duplicated stock, capacity, actors, and records;
- matched-seed tests showing UI inspection does not perturb outcomes;
- causal-reference validation for every surfaced pressure and consequence.

### Generativity

Across matched campaign samples, record:

- unique collision source combinations rather than titles;
- number of systems participating in each collision;
- percentage with a named persistent actor;
- percentage with two or more materially distinct legal affordances;
- percentage whose resolution changes a later command's legality or forecast;
- repeated identical affordance patterns;
- autonomous versus player-interrupted resolution;
- time from originating pressure to consequence and later callback.

Initial gates:

- at least 80% of interruptions expose a named persistent actor or place;
- at least 70% join state from two or more independently advancing systems;
- at least 60% change a later command, forecast, dependency, or actor policy;
- no legal affordance exceeds 70% selection among contexts with at least five
  comparable opportunities;
- no more than one discretionary interruption per season;
- mandatory collisions never disappear because of pacing.

These gates diagnose structure, not fun.

### Human play

Pair telemetry with observed play and a short causal interview:

- What changed?
- Which systems caused it?
- What could you protect?
- What did your command expose?
- What later situation changed because of that decision?

Success requires players to answer from the interface rather than reconstructing
the rules from debrief prose. After a session, players should recall persistent
actors and dependencies, not only event categories or resource gains.

## Risks

### Combinatorial noise

Generic detectors can produce technically valid but trivial collisions.
Eligibility therefore requires distinct protected stakes, persistent
consequences, and at least two viable affordances. Severity alone is not enough.

### Opaque causality

Cross-system generation can become modifier soup. Every pressure and affordance
must expose principal causes, authoritative values, and a bounded forecast. A
collision that cannot be explained cannot interrupt the player.

### Dominant generic commands

If "spend stock" resolves most collisions, the resource economy is absorbing
differences rather than generating play. Commands should often transfer exposure
to time, authority, relationships, geography, capability, or future obligations.

### False persistence

Recording prose without changing later rules does not satisfy persistence.
Generativity telemetry must track changed legality, forecasts, dependencies, or
behavioral policy.

### Excessive interruption

More detected collisions must not mean more modal decisions. Standing policy,
captain autonomy, and institutions should resolve ordinary cases. The player
governs exceptions and irreversibilities.

## First implementation slice

Implement shared capacity contention without adding a new authored event:

1. project two active demands on the same insufficient capacity;
2. trace each demand through dependencies to named affected actors;
3. enumerate existing allocate, substitute, defer, contract, and refuse commands;
4. forecast what each command protects and exposes;
5. let standing policy resolve uncontested cases;
6. interrupt only when viable commands protect different persistent stakes;
7. record the command, material resolution, and later dependency change.

This slice proves the architecture inside the ordinary fleet simulation before
touching the more complex Passage and value-law systems.
