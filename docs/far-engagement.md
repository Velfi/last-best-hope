# Far Engagement

Far Engagement is the deterministic operational simulator for ultra-long-range
open-space combat. It models future position, delayed knowledge, delegated
command, weapon flight, and persistent ship loss. It does not use the
frame-scale tactical combat state.

Launch a campaign-generated encounter with:

```sh
build/last-best-hope --far-engagement
```

Capture the command screen with:

```sh
build/last-best-hope --capture-far-engagement /tmp/far-engagement.png
```

## Physical model

Authoritative units are seconds, kilometres, kilometres per second, kilograms,
joules, watts, and radians. Encounters use a deterministic two-dimensional
inertial plane with bounded acceleration and delta-v. Reachable volumes,
intercept solutions, support geometry, and deadline corridors are calculated
from those quantities.

Information is also physical. Observations, reports, orders, acknowledgements,
and damage assessments are transmissions with a light-speed arrival time.
Friendly and hostile AI continue their last received order while new traffic is
in flight. Hostile truth is separate from every observer's contact belief.

## Lethality

Far Engagement has no generic ship hit points. Missiles, kinetic projectiles,
and lasers resolve through:

1. predicted target geometry and flight;
2. seeker acquisition or ballistic/beam miss distance;
3. terminal defense and decoys;
4. relative kinetic, explosive, or thermal energy;
5. armor resistance and coupled energy;
6. a deterministic coarse hit zone;
7. subsystem, crew, mission-kill, destruction, or recovery state.

Energy far beyond structural tolerance resolves catastrophic breakup directly.
Marginal penetrations resolve drive, sensor, radiator, weapon, command,
habitat, and structural consequences. Every material result records its
physical cause.

## Procedural operations

`Far_Encounter_Spec` describes a generated operation. Five objective families
are supported:

- breakthrough;
- interception;
- escort;
- reconnaissance;
- withdrawal and recovery.

The generator composes these with false contacts, command delay, damaged
drives, neutral traffic, uncertain reinforcement, divided objectives, or a
deteriorating deadline. It attempts up to sixteen deterministic geometries and
accepts only candidates where both conservative and committed plans can meet
the deadline while the opposition can still intervene.

Campaign encounters derive their friendly manifest from persistent ships.
The briefing permits task-group transfers and doctrine selection before
standing orders are committed.

## Command doctrine

Each task group carries persistent ship IDs, a commander, operational order,
doctrine, posture, reason code, trajectory, acceleration authority, delta-v,
sensors, and radiator capacity. Friendly and hostile groups use the same
assess–plan–execute loop and physical constraints.

Authority levels are distinct:

- **Report** executes standing defaults without interruption.
- **Commit** interrupts for scarce or irreversible commitments.
- **Engage** also interrupts before accepting hostile engagement geometry.
- **Direct** exposes every operational doctrine branch.

Commands are validated authoritatively. Unavailable options remain pending and
display their exact resource or physical constraint. Formation and emission
changes do not occur when clicked; the corresponding order must reach the task
group.

## Presentation

The operational plot renders friendly truth, hostile belief volumes, physical
weapon flights, active transmissions, one-hour reachable regions, and the
deadline corridor. Groups and contacts are selectable. Mouse wheel zooms the
plot and right-drag pans it. The command forecast displays plan reasons, track
age, light lag, reserves, and a causal ledger.

Decision previews expose known command delay, delta-v expenditure, arrival
change, uncertainty change, and scarce-resource cost without revealing hostile
truth.

## Persistence and aftermath

Save data includes a Far Engagement schema version, encounter specification,
truth and belief state, task groups, transmissions, weapon flights, per-ship
engineering outcomes, pending decisions, fixed-step remainder, and RNG state.
Legacy active scripted encounters restart from their stored seed under the
physical rules; completed and already-applied outcomes remain intact.

Aftermath is applied once to the exact persistent `Ship_ID` affected. Damage,
crew survival, mission kill, destruction, departure, and factual ship history
come from that ship's physical outcome rather than an aggregate group total.

## Architecture

- `far_engagement_model.odin` owns physical and command contracts.
- `far_engagement_generation.odin` owns campaign adapters, briefing,
  transmissions, and bounded procedural generation.
- `far_engagement_simulation.odin` owns AI planning, kinematics, weapons,
  event predicates, forecasts, and objective resolution.
- `far_engagement_core.odin` owns shared state, decisions, fixed-step
  execution, validation, results, and campaign aftermath.
- `src/far_engagement_scene.odin` presents authoritative state without
  determining outcomes.

The tests cover analytical physics, all objective families, doctrine and
manifest briefing changes, light-delayed orders, authority boundaries,
unaffordable commands, seeded determinism and variation, active-state
persistence, and exact per-ship aftermath.
