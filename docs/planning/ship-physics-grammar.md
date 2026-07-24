# Physics-first procedural ship grammar

> **Planning status — 2026-07-24:** this document sets the target grammar for
> future generator work. Its “Current implementation disposition” is an audit of
> what may be retained or reinterpreted, not a claim that the architecture-family
> conversion or the implementation order has already shipped.

## Design premise

A spacecraft is not a naval hull in vacuum. Its silhouette is the visible
solution to a small set of coupled problems:

1. Put thrust through the center of mass.
2. Carry propellant, pressure vessels, and payload through the primary load path.
3. Reject every watt of waste heat that is not stored.
4. Keep crew, electronics, tanks, optics, and radiators out of harmful plumes,
   radiation cones, firing arcs, and each other's view factors.
5. Generate control torque with thrusters at useful lever arms.
6. Survive the mission's acceleration, debris, radiation, and combat exposure.

The generator should select a physical operating regime first. Role, history,
and style then modify that solution without violating it.

## Established constraints

### Thrust and mass

- Main thrust must pass through the current center of mass. Real thrust-vector
  control exists specifically to point engine thrust through the center of mass;
  residual position and angular errors produce pointing error and torque.
- Large off-axis masses require a counter-mass, a shifted/gimballed thrust line,
  or enough continuous control authority to wastefully cancel the moment.
- Propellant consumption moves the center of mass. Tanks should therefore cluster
  around the thrust axis or drain symmetrically.
- The primary structure is an axial compression/tension path between engines,
  tanks, weapon or payload, and habitat. Heavy cantilevers require visibly deeper
  roots.
- RCS belongs near the ends of the vehicle, where the moment arm is useful, and
  every plume needs clear space.

Source: [JPL thrust-vector-control memorandum](https://ntrs.nasa.gov/api/citations/19750002097/downloads/19750002097.pdf);
[NASA spacecraft mass and RCS mechanics](https://ntrs.nasa.gov/api/citations/20220013375/downloads/20220013375.pdf).

### Heat rejection

- In vacuum, sustained power becomes a radiator problem. Area, emissivity,
  temperature, and view factor—not stylistic preference—set the rejection limit.
- Radiators must see cold space. Panels should not face one another closely, sit
  in hot exhaust, or hide behind a warm hull.
- High-power ships should be radiator sculptures. NASA's current nuclear-electric
  work describes a primary heat-rejection system exceeding 2,500 m² and accounting
  for 40–60% of dry mass.
- Radiators can fold, articulate, use multiple fluid loops, or accept high
  operating temperature. Those are tradeoffs in vulnerability, packaging,
  efficiency, and crew-safe turndown—not reasons to make the panels disappear.
- A short-sortie strike craft may use heat sinks and limited firing duration.
  A sustained-output warship cannot.

Sources: [NASA high-temperature NEP radiator engineering, 2025](https://ntrs.nasa.gov/citations/20250007547);
[NASA multi-megawatt radiator design](https://ntrs.nasa.gov/citations/20220019167);
[NASA thermal-control state of the art, 2026](https://www.nasa.gov/smallsat-institute/sst-soa/thermal-control/);
[NASA NEP-chemical vehicle study](https://ntrs.nasa.gov/citations/20210017131).

### Propellant and pressure

- Propellant and life-support storage should read as spheres, cylinders with
  domed ends, ellipsoids, or integrated pressure bodies. Arbitrary boxes are poor
  pressure vessels.
- Propellant volume follows mission delta-v and minimum engine performance. It is
  not leftover decorative volume.
- Tank slosh, feed symmetry, ullage, and changing mass distribution matter.
- Pressure vessels may double as structure, but doing so should produce continuous
  longitudinal and circumferential load paths.

Sources: [NASA space-flight propulsion sizing requirements](https://www.nasa.gov/sites/default/files/atoms/files/std8070.1.pdf);
[NASA composite pressure-vessel overview](https://www.nasa.gov/technology/tech-transfer-spinoffs/spaceship-storage-tanks-take-off-on-earth/);
[NASA unibody pressurized-structure project](https://techport.nasa.gov/projects/9462).

### Crew, radiation, and rotation

- Long-duration crew volume belongs inside shielding mass: water, food, waste,
  propellant where compatible, and a denser storm shelter.
- Nuclear reactors need distance and a shadow shield. A credible NEP arrangement
  places the reactor, power conversion, and much of the radiator system far from
  crew and sensitive electronics.
- Continuous artificial gravity requires rotation. A rotating habitat needs a
  clear radius, balanced counter-mass, bearings or a free-flying/tether solution,
  and a non-rotating thrust/docking spine.
- A decorative ring intersected by fixed modules is not a habitat.

Sources: [NASA radiation-protection technical brief](https://www.nasa.gov/wp-content/uploads/2023/12/ochmo-tb-020-radiation-protection.pdf);
[NASA Water Walls shielding/life-support concept](https://www.nasa.gov/general/water-walls-highly-reliable-and-massively-redundant-life-support-architecture/);
[NASA combined NEP/chemical layout](https://ntrs.nasa.gov/api/citations/20220007006/downloads/NETS%20NEP-Chem.pdf);
[NASA artificial-gravity and radiation study](https://ntrs.nasa.gov/api/citations/20230013553/downloads/Artificial%20gravity%20and%20radiation%20shielding.pdf).

### Weapons

Weapons are future assumptions, but their governing mechanics are not optional:

- A kinetic spinal gun should share the main load axis. Recoil then closes through
  the same structure that carries thrust.
- A turreted or broadside kinetic weapon creates a moment and needs counterfire,
  ballast, or attitude-control expenditure.
- A laser's visible aperture may be compact; its power conversion, capacitors,
  beam director, and radiator area dominate the architecture.
- Missiles externalize propulsion and recoil, but demand magazines, launch-clear
  zones, sensors, and thermal-safe storage.
- Armor is directional. Debris and combat protection should appear as Whipple
  spacing, shadow shields, sacrificial frontal mass, and compartment separation,
  not uniform fantasy plate over every surface.

## Architecture families

### 1. Spinal combatant — thrust plus gun

Physical hierarchy:

`drive bank → propellant → reactor/power → gun breech → barrel/sensors`

- Narrow frontal cross-section.
- Gun, drive, and nominal center of mass share one axis.
- Paired tanks surround the axis and drain symmetrically.
- RCS quads sit at bow and stern.
- Short-endurance craft use heat sinks and small retractable panels.
- Sustained combatants carry enormous edge-on radiator wings or droplet/advanced
  radiators if the setting explicitly supports them.
- Crew shelter sits near the center of mass, behind propellant/water and frontal
  sacrificial structure.

This should replace the current Delta architecture. A broad wedge is retained
only when it is a frontal shield or distributed radiator root, not because
triangles look fast.

### 2. Nuclear-electric cruiser — radiator and boom vehicle

Physical hierarchy:

`crew/payload → tanks → shadow shield → long boom → reactor/converters → radiators/thrusters`

- Very long separation between crew and reactor.
- Radiator area dominates plan and end views.
- Multiple independent thermal loops create repeated panel banks.
- Electric thruster clusters are numerous and physically small relative to the
  radiator system.
- Acceleration is low; the structure can be a light tension/compression truss.
- Chemical stages, if present, are separate high-thrust modules on the mass axis.

This is the realistic successor to the current Modular Frame Fleet family.

### 3. Rotating habitat/industrial ship

Physical hierarchy:

`non-rotating thrust spine + balanced rotating inhabited mass + shield stores +
industrial radiators`

- At least two balanced rotating masses, a torus, or a tethered pair.
- Rotation has a clear swept volume.
- Docking, engines, reactors, and primary radiators remain on non-rotating
  structure unless rotating joints are explicitly modeled.
- Water/waste/food form a visible shielding belt around occupied volume.
- Radiators and industrial equipment can exceed habitat span.

This replaces decorative ring segments with a real rotating subsystem.

### 4. Pressure-body utility craft

- Rounded or faceted pressure vessel around a short axial tank/engine stack.
- Minimal cantilevers.
- Deployable radiator and solar/power surfaces.
- Appropriate for couriers, landers, tugs, and short-duration crew craft.

This is the physically strongest use of the current Single Hull architecture.

## Generator invariants

Every completed recipe must prove:

1. Mass-weighted transverse center of mass lies within 5% of beam from the
   ungimballed thrust axis.
2. Propellant depletion preserves that bound or the drive gimbal/RCS budget
   explicitly covers the excursion.
3. Every heavy off-axis module has a counter-mass and a load-sized support.
4. Required radiator area is computed from waste heat and installed temperature,
   not hull aesthetics.
5. Radiator panels have usable view factors and no exhaust/plume intersection.
6. Pressure modules use pressure-efficient envelopes.
7. Crewed long-duration ships contain a shielded storm-shelter volume.
8. Reactors have a shadow-shield cone and crew separation.
9. RCS thrusters occur in balanced sets with clear plumes and useful lever arms.
10. Kinetic weapon recoil closes through the centerline structure.
11. Rotating habitats have balanced inertia and unobstructed swept volume.
12. Damage history may degrade redundancy, but never silently invalidate the
    underlying physics.

## Current implementation disposition

Keep:

- Deterministic lineage and refit variation.
- Mass-weighted thrust-axis checks.
- Paired off-axis payloads and load-sized trusses.
- Single Hull pressure-body vocabulary.
- Habitat rings as raw geometry, but only after conversion to a true rotating
  subsystem.
- Surface-rooted greeblies when they represent valves, pumps, RCS, sensors, and
  service history.

Reinterpret:

- Modular Frame Fleet → nuclear-electric boom/radiator cruiser.
- Modular Frame Strike → spinal combatant.
- Delta → spinal armored combatant, then retire the name and broad lifting-body
  assumptions.
- Greeblies → functional subsystem markers with plume, thermal, and access rules.

Remove:

- Aerodynamic “fast” shaping with no shielding, weapon, thermal, or launch
  justification.
- Lone decorative masts and unsupported heavy boxes.
- Tiny radiators on sustained high-power ships.
- Habitat rings pierced by fixed structure or payloads.
- Uniform armor and arbitrary rectangular pressure vessels.

## Implementation order

1. Replace Delta with Spinal Combatant while retaining its serialized enum value.
2. Make radiator area genuinely dominant on Fleet and Habitat ships, with
   independent loop banks and view-factor spacing.
3. Convert Habitat rings into balanced rotating districts with a clear swept
   volume and non-rotating axial spine.
4. Add reactor/shadow-shield/boom grammar to sustained-output ships.
5. Add explicit axial tank sets, RCS quads, plume-clearance checks, and propellant
   depletion center-of-mass tests.
6. Rebuild contact sheets around physical annotations: thrust axis, center of
   mass, radiator area, rotating volume, shield cone, and firing axis.
