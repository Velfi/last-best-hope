# Fleet AI design

## Implemented stealth and maneuver layer

Fleet autonomy now treats survival as an information problem. Cautious groups
use concealment, passive sensing, ambush windows, and track-breaking movement;
hunter-killer groups use continuous coordination, repeated passes, and combat
burns. Balanced and last-stand doctrines retain endurance-oriented behavior.

Both sides run the same deterministic one-second maneuver planner from their
own contact picture. The planner chooses shadowing, masked approaches,
cross-bearings, ambushes, skirmish passes, displacement, contact breaking,
withdrawal screens, reforming, or declining contact. Each choice records a
factual reason, preferred range, escape margin, fire permission, and burn
permission for presentation and tests.

Signature derives from hull profile, sensors, track sharing, weapon exposure,
acceleration, combat burn, damage, and masking. Movement uses bounded
acceleration and turn authority. Hostile track uncertainty grows when an
observed formation accelerates without illumination or multiple observers;
silent running suppresses weapons, sensors, communications, and hard thrust
while degrading an existing hostile solution.

## Intended experience

The player commands like an admiral. They decide what must happen, which part
of the fleet should do it, and what risks are acceptable. Captains decide how
to fly, fight, support one another, and respond to ordinary contact.

The command loop is:

1. Before battle, organize task groups and set doctrine.
2. During battle, assign or revise objectives.
3. Observe execution, reports, and emerging risks.
4. Intervene only when the objective changes or doctrine does not authorize a
   consequential choice.

An order should remain useful for tens of seconds. If competent play requires
repeatedly correcting facing, range, target, or formation, that behavior
belongs in doctrine or unit autonomy instead.

## Command hierarchy

Close Engagement has three decision layers.

| Layer | Owner | Decides | Typical cadence |
| --- | --- | --- | --- |
| Strategic | Player before battle | Task groups, doctrine, reserves, expendable resources | Once per operation |
| Operational | Player during battle | Objectives, boundaries, priorities, commitment of reserves | A few times per phase |
| Tactical | AI | Formation, route, range, targets, screens, attack runs, local withdrawal | Continuously |

The simulation remains authoritative and deterministic in `packages/game`.
Presentation in `src` displays intent, confidence, exceptions, and reports; it
does not choose tactics.

## 1. Organizing the fleet

### Use role-led combined-arms task groups

A task group has a primary purpose and enough supporting capability to operate
without constant help. It is not merely a bucket of ships with the same role.
For example, a strike group may contain bombers as its principal force, a
fighter escort, and a carrier or corvette that extends its operating time.

Every ship contributes a capability vector derived from its hull, role,
equipment, damage, captain, experience, and persistent history:

- **Control:** hold or contest a volume.
- **Strike:** damage hardened or high-value targets.
- **Screen:** intercept threats and protect another element.
- **Mobility:** reach, pursue, or disengage.
- **Support:** repair, recover, refuel, or coordinate.
- **Recon:** detect, classify, and maintain contact.
- **Endurance:** remain effective under damage or over time.

An operation defines task-group templates as desired capability ranges rather
than exact ship classes. The same objective can therefore be met by different
fleet histories.

Example templates:

| Template | Principal capability | Required support | Typical weakness |
| --- | --- | --- | --- |
| Screen | Screen, control | Recon, mobility | Low hardened-target damage |
| Strike | Strike, mobility | Screen or support | Vulnerable while forming attacks |
| Recovery | Support, endurance | Screen, control | Slow and objective-bound |
| Line | Control, endurance | Screen, strike | Slow to redeploy |
| Recon | Recon, mobility | Screen | Cannot sustain a major engagement |

### Deterministic assignment

Automatic organization should solve a small, deterministic constrained
assignment problem:

1. Lock ships the player explicitly assigned.
2. Give each required group the best available command ship.
3. Satisfy its minimum capability coverage.
4. Add ships that improve its principal capability without creating a more
   serious shortfall elsewhere.
5. Put remaining ships in reserve or reinforce the lowest-confidence group.

Candidate score:

`fit = capability coverage + cohesion + command affinity - travel mismatch - critical scarcity`

**Cohesion** rewards ships with shared service, established escort
relationships, or compatible captains. **Critical scarcity** prevents the
organizer from assigning the fleet's only recovery ship to a group that merely
benefits from support. Ties resolve by stable ship ID, never container order or
frame timing.

The organizer presents a recommendation and plain reasons: “Strong strike;
screening is thin” or “Common Hearth is the fleet's only recovery element.”
The player may override it. Automatic reassignment does not occur during
battle unless the player orders a reorganization; a damaged group adapts its
tactics rather than silently taking ships from another command.

### Group identity persists

Task groups should acquire records of their own without replacing ship
identity: who habitually escorts whom, which commander led the group, and what
formations survived. Reusing a proven group improves coordination modestly;
breaking it apart is always allowed. This makes organization part of fleet
history rather than a disposable loadout screen.

## 2. Commanding task groups

### Orders describe outcomes

An operational order is a contract with five fields:

```text
verb       what success means
subject    task group receiving the order
object     ship, contact, objective, route, or volume
boundary   where the group may operate
duration   until achieved, relieved, timed out, or superseded
```

The initial verb set should remain small:

- **Secure:** establish and retain control of a volume.
- **Protect:** prevent effective attack on a subject.
- **Defeat:** render a designated force unable to interfere.
- **Delay:** reduce an enemy's progress without decisive commitment.
- **Recover:** reach, stabilize, and remove a subject.
- **Observe:** maintain contact while avoiding decisive engagement.
- **Withdraw:** disengage and reach a destination while preserving cohesion.
- **Reserve:** remain ready and respond only under specified triggers.

“Move” can remain as a navigation convenience, but it should not be the main
combat verb. “Attack this contact” is a narrow form of **Defeat**. The player
designates an objective or force; the group chooses formation, approach, and
individual targets.

### Group-level execution loop

Each task group evaluates on a fixed simulation cadence, slower than weapon
resolution:

1. **Assess:** objective progress, known threats, group readiness, support,
   terrain, route risk, and time margin.
2. **Choose posture:** transit, approach, establish, execute, consolidate,
   disengage, or unable.
3. **Allocate jobs:** assign screen, main effort, support, scout, and reserve
   jobs to member elements.
4. **Select a maneuver:** approach route, defended volume, intercept point,
   attack axis, or withdrawal corridor.
5. **Issue tactical intents:** desired formation slot, target category, range
   band, and fire permission for each element.
6. **Report only meaningful changes:** objective achieved, material risk,
   doctrine exception, loss of capability, or inability to comply.

The group planner chooses among a bounded library of authored maneuvers. It is
not an unconstrained search. That keeps behavior legible, tunable, and exactly
replayable.

### Tactical autonomy

Ships execute their assigned job using utility scoring. Candidate actions may
include hold slot, intercept, screen, attack, flank, evade, support, recover,
re-form, and disengage.

Scores should be built from observable factors:

`utility = objective value + role fit + mutual support + survival + doctrine - travel and exposure costs`

Hysteresis and minimum commitment times prevent oscillation. A ship keeps its
current target or maneuver until another option is materially better, the
target becomes invalid, or safety rules force a change. Formation slots are
relative to the group's anchor and maneuver axis, not fixed world offsets.

Tactical AI must understand at least:

- weapon and sensor range bands;
- firing arcs and turn cost;
- collision and hazardous terrain;
- screening geometry between a threat and protected subject;
- local concentration of force;
- ammunition and ability budgets;
- damaged mobility and the group's slowest required member;
- recovery of disabled persistent ships when authorized.

## Doctrine

Doctrine is the player's standing answer to recurring tactical questions. It
should control behavior, not merely add numerical bonuses.

### Doctrine settings

Use a compact set of independent policies, with named presets as shortcuts:

| Policy | Example settings |
| --- | --- |
| Objective priority | Preserve force / Balanced / Complete at cost |
| Engagement posture | Avoid / Defend / Engage favorable / Seek battle |
| Cohesion | Tight / Mutual support / Flexible / Independent |
| Pursuit | None / To boundary / Until disabled |
| Withdrawal | Early / Damaged / Critical / Never autonomous |
| Ordnance | Conserve / Confirmed priority targets / Liberal |
| Rescue | Only if safe / Accept risk / Leave disabled elements |
| Target priority | Objective threats / Strike craft / Support / Capitals |

Presets such as **Cautious Screen**, **Balanced**, **Hunter-Killer**, and **Last
Stand** populate these policies. The player can inspect the actual permissions
and adjust the exceptional ones. Doctrine belongs primarily to a task group;
individual ship overrides should be rare and visible.

### Hard orders, doctrine, and captain judgment

Precedence is explicit:

1. Simulation safety and physical possibility.
2. Direct player order.
3. Doctrine constraints and permissions.
4. Group commander's plan.
5. Captain-level tactical utility.

A direct order does not imply unspecified sacrifice. “Secure Relay A” under an
early-withdrawal doctrine means attempt it while preserving the group. “Secure
Relay A at any cost” is a doctrine change or explicit command rider and should
be presented as such.

Captains may influence how well a permitted action is performed and which
equally valid maneuver they prefer. They should not secretly invert doctrine.
History can create legible tendencies—an escort that is quicker to aid a known
partner, for example—but these remain bounded by the player's standing orders.

## Command exceptions

The AI asks the player only when a choice is consequential, outside doctrine,
and cannot wait for the next normal order. Appropriate requests include:

- leave the assigned boundary to pursue a damaged capital;
- expose the objective to rescue a disabled ship;
- expend a scarce strategic weapon;
- continue after the group's required capability is lost;
- abandon cargo or a persistent ship to meet extraction.

Each request states one action and one concrete cost. If ignored, doctrine
supplies the deterministic default. Ordinary target changes, attack runs,
formation changes, evasive maneuvers, and local disengagement do not interrupt
the player.

To prevent request spam, exceptions are deduplicated by cause, subject, and
objective state. A rejected request remains rejected until a material fact
changes.

## Legibility and trust

Competent autonomy only feels fair if the player can read it.

For each task group, display:

- current objective and boundary;
- current posture and maneuver;
- readiness and capability shortfalls;
- doctrine exceptions currently suppressing an action;
- a short forecast: **confident**, **contested**, **unlikely**, or **unable**,
  followed by the dominant factual reason.

Selecting a group should reveal its intended route, defended volume, screen
relationship, attack axis, and withdrawal corridor. Reports should describe
observable changes: “Screen can no longer cover Common Hearth,” not “The
commander has lost confidence.”

The AI should expose a compact reason code for every group plan and ship
action. These codes power tooltips, event records, tests, and debugging without
requiring the UI to reconstruct intent from motion.

## Suggested simulation model

Add explicit group and doctrine state rather than continuing to copy a preset
onto every unit:

```text
Combat_Task_Group
  stable_id, name, commander
  member_ids[]
  capability_current[], capability_required[]
  order: Combat_Operational_Order
  doctrine: Combat_Doctrine_Policy
  posture, maneuver, plan_revision
  anchor, axis, boundary, route[]
  confidence, shortfall_flags, reason_code

Combat_Operational_Order
  verb, subject_id, object_kind, object_id
  destination, boundary_radius
  completion_condition, expiry

Combat_Tactical_Intent
  job, formation_slot, target_id, target_category
  desired_range, fire_permission, disengage_point
  reason_code, valid_until
```

Groups refer to stable IDs, never array positions. Planning runs at a fixed
interval and in stable group-ID order. Candidate maneuvers and actions are
enumerated in stable order; equal scores use stable IDs as tie-breakers. Any
random variation consumes the mission's seeded stream at explicit planning
events, not every frame.

Random skirmish generation budgets objective workload before applying
opposition and geometry. Multi-stage operations receive fewer simultaneous
hostile factions and shorter objective routes than direct engagements.
Requested faction count remains an input, but the operation budget caps the
effective count when additional opposition would consume the time needed for
relay capture, scanning, recovery, or extraction. The same seed and setup
always produce the same effective budget and geometry.

Reconnaissance, seedship recovery, and contested salvage also derive an
objective-pressure profile from the contract seed. An open approach leaves the
opposing force in its ordinary deployment. A picket-screen approach detaches
two existing raider elements to hold the authored anomaly or wreck; it does not
add enemy strength or apply a hidden objective penalty. The opening event
records the pickets, and trainer reports count screened cells so changes in
mission topology remain attributable.

Recovery contracts also select one bounded profile from the contract seed:
clear approach, picketed target, drifting target, or heavy tow. Clear
approaches preserve a favorable baseline. Picketed targets reuse two existing
hostile elements; recovery begins after the screen is reduced to one element.
Drifting targets move with forecast inertial velocity, and recovery craft must
intercept and match it. Heavy-tow contracts identify two existing hostile
elements along the forecast extraction route, then reduce tug and recovered
ship mobility after the interaction.

Before accepting a profile, generation estimates approach, interaction, and
extraction time using the assigned recovery element. The estimate must fit
within 75 percent of the mission duration and the loadout must contain a
capable recovery element. A profile that exceeds this workload bound falls
back to a clear approach. No profile adds hostile strength or bypasses normal
movement, detection, damage, recovery, or extraction rules.

Ordinary reconnaissance loadouts carry a bounded store of autonomous probes
on sensor and command elements. Launching a probe consumes one store. The probe
crosses the operational volume faster than a crewed ship and scans only after
reaching the authored anomaly, but hostile formations can detect and destroy it
at close range. A lost probe leaves the commander with its remaining stores or
a crewed scan; it does not terminate the mission. Reconnaissance contracts
refit the standard interceptor element as a scout rather than inventing a
privileged mission unit. It gains the authored sensor capability while
retaining the speed and fragility of a light element.

Silent Infiltration is retired from random generation, campaign operation
selection, skirmish setup, and the training curriculum until its covert-route
model is rebuilt. Its enum value remains reserved so older saves and replays do
not change the numeric identity of later operation types. A legacy request is
loaded as Reconnaissance.

Raid-and-deploy contracts similarly refit the standard utility hull as a
courier. The commander assigns that cargo-capable element to the authored
deployment interaction and withdraws the deployment team after completion;
other groups continue to screen rather than becoming implicit objective units.

## Failure behavior

The AI should degrade gracefully:

- If a group loses strike capability, it may screen or delay but reports that
  it cannot complete a defeat order.
- If it loses mobility, it tightens around the slowest required ship or asks
  permission to detach it.
- If command is disabled, a deterministic successor assumes command after a
  delay and coordination temporarily worsens.
- If a recovery, scanning, or deployment specialist is disabled, the best
  surviving capable element assumes the unfinished interaction.
- If communications are disrupted, the group continues its last valid order
  and doctrine; it does not become inert.
- If an objective becomes impossible, the group preserves what it can and
  reports **unable** rather than repeatedly attempting a fatal path.

These failures create recoverable setbacks, ship histories, scars, changed
relationships, and consequential choices instead of abrupt run termination.

## Validation

Competence needs behavioral tests, not only win-rate tests.

Deterministic scenarios should verify that:

- a screen places itself between bombers and its protected ship;
- bombers form supported attack runs and re-form after each pass;
- a strike group does not chase beyond its pursuit boundary;
- a group withdraws according to doctrine without abandoning required members;
- scarce ordnance follows authorization policy;
- a group reports loss of a required capability;
- the same seed and order schedule produce identical plans and outcomes;
- action hysteresis prevents target and posture thrashing;
- ignored requests resolve exactly according to doctrine;
- auto-organization preserves locked assignments and resolves ties by ID.

Balance runs should use an objective-level reference admiral that issues only
the same orders available to the player. On standard difficulty, the broader
campaign should retain its 75% experienced-player win target; combat AI should
not depend on per-frame intervention to reach that target.

## Implementation sequence

1. Replace copied doctrine presets with group-owned policy settings and retain
   the current four presets as UI shortcuts.
2. Introduce operational orders and group postures while adapting the current
   Screen, Strike, and Recovery groups by hand.
3. Add group job allocation, relative formation slots, hysteresis, and reason
   codes; keep existing movement and weapon resolution initially.
4. Replace per-unit target selection with intent-driven tactical utility.
5. Add capability-vector organization and a pre-battle recommendation screen.
6. Add command succession, relationship effects, and persistent group history
   after the core behavior is measurable and trustworthy.

The first playable milestone should prove one promise: the player can order
**Recovery protect Common Hearth** and **Strike defeat the enemy capital**, then
watch both groups choose sensible routes, formations, targets, attack timing,
and withdrawal behavior without further input.

## Unattended training

The executable includes a deterministic evolutionary trainer for the bounded
maneuver-scoring weights. It changes preferences, not weapon physics,
information access, fire permissions, or simulation rules. Every candidate is
evaluated under all four doctrines against a league containing the shipped
baseline, concealment, objective-pressure, and mutual-support opponents. A
candidate becomes champion only when it improves the fixed validation batch
without reducing wins or materially regressing preservation. The checkpoint is
rewritten atomically after every generation, so the process can be stopped and
resumed.

The trainer's unattended commander is deterministic and operation-aware. It
assigns the units and order sequence needed to pursue each contract, including
post-objective extraction, but it does not choose maneuver-scoring weights.
Those bounded weights still determine how formations approach, support one
another, respond to pressure, and survive while executing the commander's
orders. This separation gives every operation an objective signal without
making mission permissions or completion trainable.

```sh
# Build once.
make build

# Confirm that the default policy does not already solve the curriculum.
build/last-best-hope --combat-ai-audit 44 24301 8

# Recommended unattended run. It stops after eight hours and leaves a
# resumable checkpoint after every completed generation.
mkdir -p var
build/last-best-hope --combat-ai-overnight var/combat-ai-league-v3.json 8 44 24301 8

# Inspect the champion or test it on two unseen curriculum matrices.
build/last-best-hope --combat-ai-report var/combat-ai-league-v3.json
build/last-best-hope --combat-ai-validate var/combat-ai-league-v3.json 88 900001

# Run the paired promotion gate: 4 complete unseen curriculum matrices.
make combat-ai-trials

# Play against the checkpoint's champion.
build/last-best-hope --combat --ai-checkpoint var/combat-ai-league-v3.json

# Export only the reviewed parameter block for promotion into game data.
build/last-best-hope --combat-ai-export var/combat-ai-league-v3.json var/combat-ai-candidate.json
```

Each 44-run curriculum covers the eleven active ordinary operation types
against all four league doctrines. Mission geometry, contract objectives, and faction count
vary deterministically while the player loadout remains fixed. Development
seeds rotate each generation; validation seeds remain fixed for comparable
acceptance decisions. Citadel assaults remain outside this curriculum because
their scale and victory rules are exceptional. During training, progress is printed after the
incumbent, every candidate, validation, and checkpoint. Each line includes
elapsed and remaining time, wall-clock completion, simulated battles, accepted
generations, and the checkpoint stage. The separate holdout command should be
used before promoting a champion, since the trainer never edits production
defaults automatically.

### Automated promotion trials

`make combat-ai-trials` runs the checkpoint and the untouched default AI on the
same holdout seeds. It prints progress after every block and writes
`var/combat-ai-league-v3-trials.json`. Override the inputs without editing the
Makefile:

```sh
make combat-ai-trials \
  COMBAT_AI_CHECKPOINT=var/combat-ai-league-v3.json \
  COMBAT_AI_REPORT=var/combat-ai-league-v3-trials.json \
  COMBAT_AI_TRIAL_RUNS=44 \
  COMBAT_AI_TRIAL_BLOCKS=5 \
  COMBAT_AI_TRIAL_SEED=900001 \
  COMBAT_AI_WORKERS=8
```

The JSON report includes the raw baseline and candidate metrics, per-block
deltas, a 95% win-rate interval, ship-preservation and loss deltas, and a
deterministic replay result. Recovery-profile run and win counts make changes
to recovery difficulty attributable. It also records the worker count used.
During a run, the terminal reports completed
battles, percentage, elapsed time, ETA, and live score and win-rate deltas.
The JSON file is updated atomically after every completed block with the
verdict `running`, so external monitors can inspect long trials safely.
Promotion requires:

- at least `+25` composite score per mission;
- a positive win signal, either a confidence interval above zero or a gain of
  at least three percentage points whose interval still overlaps improvement;
- no material ship-loss or preservation regression;
- no recovery profile losing more than one primary success;
- improvement in a majority of seed blocks and no regressing block;
- identical repeated outcomes for the deterministic replay sample.

These thresholds are an automated screening gate, not a replacement for the
scripted behavioral scenarios or expert observation described above.

Training, validation, and promotion trials evaluate independent seeds in
parallel. The final positional argument, or `COMBAT_AI_WORKERS` for the Make
target, selects `1` to `64` workers. When omitted, the executable uses the
machine's processor count capped at eight. Results are merged in seed order, so
worker count does not alter deterministic metrics, champion acceptance, or
checkpoint contents. Use fewer workers if concurrent simulations create memory
pressure.

Version 2 checkpoints contain seedship-only scores and are not comparable with
this curriculum. The v3 trainer preserves those files and reports the version
mismatch; use a new `combat-ai-league-v3.json` path rather than overwriting them.
Version 3 checkpoints also record controller and evaluation revisions. A
checkpoint from before the current operation-aware commander, recovery
profiles, mission-role refits, or reconnaissance-probe evaluation is rejected
and preserved even though its curriculum version is also 3. Archive the old
checkpoint under a descriptive name, then start a fresh
`var/combat-ai-league-v3.json`. Probe
launches, completed scans, and losses are included in aggregate and
per-operation reports so reconnaissance gains remain attributable.
