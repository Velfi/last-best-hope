# Recover the Seedship vertical slice

Launch the deterministic command-level operation from **Fleet Operation** on
the main menu or directly with `build/last-best-hope --combat`.

Launch the fleet-scale stress scenario with
`build/last-best-hope --combat-stress`. It uses a large layered formation around
the same seeded objective space. Individual ship marks establish battle scale
while orders, targeting, and damage remain formation-level, keeping memory and
simulation work bounded. Exact scenario scale is covered by game tests.

Launch the deterministic fleet finale with
`build/last-best-hope --combat-finale`. It uses a large heap-backed coalition
and defender roster. Use `--capture-combat-finale <path>` for a diagnostic
capture. Exact composition and memory bounds are covered by game tests.

Measure the rendered normal and stress views with identical camera, seed,
resolution, warmup, and sample counts using:

```sh
VIZZA_GPU_PROFILER=1 build/last-best-hope --benchmark-combat-render
```

The command emits one JSON object per scenario. CPU draw time includes canvas
construction plus 3D world construction and command recording. The M4 Max
1280×720 CPU p95 budget is 8 ms. GPU frame time is included when the Vulkan
driver exposes timestamp queries; otherwise `gpu_timestamp_available` is
`false` rather than substituting a CPU estimate.

Use `--capture-combat-resize <path> <width> <height>` to exercise swapchain,
depth attachment, Retina framebuffer scaling, letterboxing, viewport, and
scissor recreation at a chosen logical window size.

Append `sidebar-hover` after the output path for `--capture-combat` or
`--capture-combat-late` to pin the pointer over a task group and include its
hover dossier in the deterministic capture.

Append `no-selection` instead to clear every friendly selection before the
capture. This exercises the command deck's disabled state and explicit
`NO SELECTION` warning.

## Controls

Campaign battles begin from **Battle** on the Fleet screen. The deployment
manifest may contain any positive number of available ships. Assign every
selected ship to Screen, Strike, or Recovery; each task group must contain at
least one ship. The manifest reports capability coverage and its Propellant cost
before commitment. Committing records the deployed ships and cost immediately.
If play is interrupted after commitment, reopening the chronicle resolves the
operation under its saved standing orders; quitting cannot erase its risk.

Campaign hulls contribute their current power, damage, experience, mass, and
operational modules to their command element. Standing precedents set the
opening doctrine. The player may depart from that authority at a visible
Cohesion cost. A completed operation cannot be repeated until a historical
front changes and creates another operational cause.

Combat subsystem condition persists back to each named campaign ship as bounded
Mobility, Sensors, Strike, Support, and Endurance impairments. These impairments
reduce deployment coverage and Passage performance without replacing structural
damage or creating another repair currency. Bounded repairs clear one
impairment; full repair clears all impairments while retaining scars and service
history. Loss of an essential capability surfaces the existing repair,
substitution, or accepted-gap response.

- Click or drag around friendly command elements to select them; hold Shift to toggle individual elements or add a box selection.
- Press 1–3 or click **Screen**, **Strike**, or **Recovery** to select a prepared task group.
- Click **Move**, then press on the tactical field and drag vertically to set depth; release to place the three-dimensional destination. A simple click uses the current depth.
- Click an enemy to order selected elements to attack it.
- Right-click open space to move selected elements immediately, or right-click an enemy to attack it.
- **Engage**, **Screen**, and **Evade** are persistent stances. Changing stance does not cancel the current action. Screen prioritizes strike craft near the formation's work; Evade suppresses optional engagements.
- **Move**, contextual **Act**, **Hold**, and **Withdraw** are actions. C invokes the current Act interaction: Capture for an unsecured relay, Recover for the seedship, or Rescue for a disabled ally when Recovery is selected.
- Clicking a hostile contact issues Attack directly. Mandatory extraction remains automatic when the navigation window closes.
- Emergency Defense appears under **Ability** because it spends countermeasures without replacing the current stance or action.
- Press Q or click the selected element's ability to activate it. **Spinal Salvo** then requires a target volume; its aiming line shows projected time to impact before firing. Flight time increases with range. The salvo has two charges, a 75-second recycle, a 120-unit minimum range, and can strike friendly ships inside its blast volume.
- Press E to hold selected elements or X to withdraw them.
- Press R or click **Emergency Defense** to spend a threatened element's
  countermeasures, readiness, and emissions against salvos already inbound.
- Press G to cycle selected elements through Silent, Passive Watch, Active
  Search, Illuminate, Relay, and Deceive sensor policies. Active emissions
  improve distant tracks while exposing the observer.
- Select Cautious Screen, Balanced, Hunter-Killer, or Last Stand in the right rail. Presets change withdrawal thresholds and pursuit limits.
- Combat coordinates are physical plot units: one unit is 1,000 kilometres,
  and one simulation-time unit is one minute. The ordinary chart spans about
  two million kilometres; the Seedship navigation window is 24 hours.
- Pause, 1×, 10×, 100×, and 1,000× control simulation speed. Press **I** to
  advance to the next forecast arrival, hostile terminal approach, command
  request, or navigation deadline. Every setting
  drains the same deterministic fixed-step accumulator; compression changes
  waiting time, not outcomes. **Withdraw All** preserves what remains when the
  operation is no longer favorable.
- Sustained fire builds **Pressure**. Pressured elements maneuver and fire less effectively; pinned elements are sharply degraded. Concentrated fighter, corvette, and capital fire imposes the most pressure. Debris and wreckage reduce incoming pressure and clear it faster, while **Withdraw** breaks contact, clears pressure rapidly, and grants withdrawal speed.
- Middle-drag or WASD pans. The mouse wheel zooms around the cursor, and F focuses the selected element.
- Pinch on a touchpad to zoom. Two-finger secondary-click and drag—or right-drag with a mouse—orbits freely around the field; a secondary click without dragging still issues a contextual order.

The orbitable perspective chart projects actual `(x, y, z)` simulation
positions. A tactical reference grid sits below the combat volume. Every ship
and objective has a stem down to its grid contact, so altitude remains visible
without selection. Selected units show their active path, formation ghosts,
destination stem, and contextual weapon envelope.

Each engagement defines a six-by-six operational grid. Military-style
addresses read the lateral letter before the advancing number: **A1** begins at
the fleet-entry edge, while **F6** lies across the front at the opposing edge.
Continuous altitude is reported through engagement-specific **High**,
**Plane**, and **Low** bands, producing locations such as **C4 High**. Sector
addresses are references for orders and reports; they do not constrain movement
or weapon resolution to cells.

## Architecture

`packages/game/close_engagement.odin` contains seeded battlefield generation,
fixed-step simulation, orders, doctrines, utility target selection, combat,
mission progression, recovery, extraction, and factual outcomes. It has no
renderer dependency. `src/close_engagement_renderer_3d.odin` owns the perspective
camera, projection and ray casting, depth-tested Vulkan world geometry, and GPU
resource lifetime. `src/close_engagement_scene.odin` owns input, command panels,
tactical annotations, requests, and results. The canvas renders a D32-backed
world pass first, then loads the color attachment for the depth-free 2D UI.

Command elements are the tactical entities. Each owns a contiguous
roster of exact persistent ship records; ordinary ship records receive damage
and survival outcomes but do not navigate or run AI independently. The
simulation supports up to 16,384 exact ships with a dynamically sized set of
active command elements. Group summaries update at a fixed one-second planning
cadence, and rendered formation marks are capped independently of roster size.
The roster is allocated to the exact mission size on the heap and explicitly
released on replay, reseeding, and shutdown; large ship state is never embedded
in the mission value or placed on the stack.

The finale runs for seventeen minutes at 1×. Its installation begins a firing
cycle every 180 seconds and reveals its complete beam corridor for the final 18
seconds. Every individual ship intersecting that corridor is resolved from its
stable ID and formation state. Strike craft are destroyed; capital ships and
carriers lose 70% of individual hull; both fleets are affected identically.
Holding both targeting relays pauses the cycle and exposes the installation for
60 seconds. Coalition bombers inside the exposed strike volume can permanently
disable it before withdrawal.

Finale acceptance uses three repeated benchmark runs with the same seed. The
fixed simulation tick p95 budget is 2 ms, CPU draw p95 is 8 ms, no post-warmup
frame attributable to roster traversal may exceed 16.67 ms, and roster plus
derived render data must remain below 64 MB. Graphical launch is gated behind
ownership tests, the normal build, and the repeated headless simulations.

Generation uses an authored grammar: two separated and independently defended
relay approaches, a seedship offset between them, an open capital-ship lane, a
debris corridor, an anomaly volume, and a distant extraction point. The screen
and strike groups open on different relays while the recovery vessel holds with
its carrier and the capital ship advances through the open lane. A displayed
seed reproduces positions and enemy composition.

The operational volume is deliberately wider than a weapon envelope. Moving a
task group between relays, the seedship, the anomaly, and extraction consumes a
meaningful part of the twelve-minute navigation window. Relay fixes require
sustained local superiority; objective raiders divide between the approaches
while other formations screen the debris corridor and capital lane. An
abandoned relay can be jammed after capture, so both fixes must overlap before
the seedship position is confirmed. The relay defenders redeploy after one
falls. Securing the first relay triggers the seeded complication on the
remaining objective. Seedship stabilization is staged, and recovered cargo
only counts as delivered if Common Hearth reaches extraction.

Combat is intentionally silent in vacuum. Feedback is visual, while concise
text communications from named ships acknowledge direct orders and report
autonomous actions such as attack runs, disengagement, relay scans, recovery,
and extraction. There are no weapon, impact, interface, or music cues.

The seedship and targeting relays follow slow seeded inertial trajectories.
Recovery requires Common Hearth to approach within 12,000 kilometres and match
relative velocity below 1.7 kilometres per second before stabilization
advances.

Resolute is configured as a Linebreaker capital ship. Its manually activated
Spinal Salvo is resolved by the deterministic simulation: designation, range
validation, charges, recycle time, delayed impact, falloff, and friendly fire
all live in `packages/game`. The tactical scene owns only arming input and the
engraved target/impact presentation. Capital type is explicit state so later
capital classes can receive different signature actions without adding direct
control to ordinary command elements.

The depth-tested tactical renderer constructs Fighter, Bomber, Corvette,
Recovery, Carrier, and Capital admiralty marks from static indexed meshes and
draws them through per-frame GPU instance buffers. Each contact also carries a
low-poly translucent ellipsoid and etched wire hull so altitude and facing stay
legible in the default oblique top-down view. Grid, command plane, stems,
ranges, objectives, ship marks, hit tests, and canvas annotations use the same
perspective camera. Contact shaders preserve world heading, add bounded camera
cant, and enforce a small distant-contact screen-size floor. Debris, radiation,
wreckage, contact hulls, and the open lane share static indexed world meshes;
per-frame instance buffers provide their transforms and styles. Deterministic
fragment-shader breakup sits beneath their etched contour lines.

Debris masks missile and torpedo damage, the open lane improves capital-ship
fire, and the anomaly inflicts predictable radiation damage. Bombers expend
heavy ordnance, make attack runs, and disengage between passes. Capital ships
turn slowly and take additional damage through their stern quarter. Raiders
contest relays, screen strike craft, threaten the recovery vessel, and withdraw
damaged elements. One seeded complication occurs midway through the operation.

Combat information is side-specific. Passive and active sensors contribute
deterministic measurements whose error and update rate depend on range, sensor
power, readiness, terrain, electronic warfare, and target emissions. Command
ships and relays fuse those reports. Contacts progress from signal to track,
identification, and a weapon-quality firing solution; old reports retain a
predicted position while their uncertainty grows.

Every weapon requires an appropriate solution and firing increases the
attacker's exposure. Offensive lasers operate from 50,000–300,000 kilometres;
kinetic batteries from 10,000–150,000 kilometres; guided missiles from
300,000–3,000,000 kilometres; and heavy torpedoes from 50,000–300,000
kilometres. Guided weapons are aggregate waves with boost, cruise, search, and
terminal phases. Their arrival window, surviving weapon count, seeker type,
guidance quality, and delayed impact remain visible. Chaff, thermal flares,
active decoys, ECM, defensive lasers, defensive guns, and terminal evasion
resolve in that order. Captains spend these defenses automatically according
to doctrine. A wave that loses its track searches the last predicted volume.
An observed impact does not provide exact damage assessment until sensors
establish it.

Pre-battle orders include fleet fire control. **No Confirm** delegates all fire
to doctrine. **Confirm Big** pauses before each autonomous expenditure of
limited ordnance. **Confirm All** also pauses when a command element first opens
an engagement; approval covers routine fire until the target, order, or track
changes. Deliberately issuing an Attack order counts as authorization.

Eight or more destroyed hulls concentrated around a command element form a
persistent wreckage field. Later losses nearby enlarge it. Wreckage fields use
the same missile and torpedo masking rule as authored debris, and their seeded
engraved marks reproduce exactly when the battle is replayed. Field radius is
directly proportional to the accumulated wreck tonnage, so capital and carrier
losses occupy more space than the same number of strike craft.

Determinism, scenario balance, and stress bounds are verified by game tests and
dated validation evidence. This contract does not duplicate their scenario
sizes, seeds, or result values.
