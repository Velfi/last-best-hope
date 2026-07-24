# Ship taxonomy

The simulation separates three layers:

- `Ship_Hull_Archetype`: one of 24 physical production hulls.
- `Ship_Operational_Role`: current equipment and assignment. The design source
  lists 37 named roles despite describing the total as “roughly 35”; all 37 are
  retained.
- `Ship`: persistent identity, including name, captain, crew, community,
  construction lineage, damage, scars, memories, relationships, and history.

`Role` remains the older eight-value diaspora duty used by campaign planning.
`Hull_Class` remains the five-value scale envelope used by mass and legacy
generation. Neither replaces the production or operational layer.

## Production hulls and configurations

| Family | Production hull | Operational configurations |
| --- | --- | --- |
| Strike craft | Scout | Scout |
| Strike craft | Interceptor | Interceptor |
| Strike craft | Fighter | Fighter |
| Strike craft | Strike Fighter | Strike Fighter |
| Strike craft | Bomber | Bomber |
| Strike craft | Assault Shuttle | Assault Shuttle |
| Light combatant | Patrol Boat | Patrol Boat |
| Light combatant | Corvette | Corvette |
| Light combatant | Torpedo Boat | Torpedo Boat |
| Light combatant | Gunship | Gunship |
| Frigate | Picket Frigate | Picket Ship |
| Frigate | Combat Frigate | Flak, Missile, Electronic-Warfare, or Active-Defense Frigate |
| Frigate | Support Frigate | Support Frigate |
| Frigate | Minelayer Frigate | Minelayer Frigate |
| Line warship | Destroyer | Destroyer |
| Line warship | Light Cruiser | Light Cruiser |
| Line warship | Heavy Cruiser | Heavy Cruiser |
| Line warship | Battlecruiser | Battlecruiser |
| Line warship | Battleship | Battleship |
| Carrier and command | Carrier | Escort Carrier, Fleet Carrier, or Command Ship |
| Line warship | Dreadnought | Dreadnought |
| Diaspora | Utility Hull | Courier, Tanker, Recovery Tug, or Hospital Ship |
| Diaspora | Transport Hull | Freighter, Fabricator Ship, or Colony Transport |
| Diaspora | Habitat Hull | Habitat Ship, Seedship, Generation Ship, or Arkship |

## Implemented tactical rules

- Ordinary Seedship operations expose 8–12 distinct archetypes. Battleships,
  dreadnoughts, generation ships, and arkships are excluded from routine roster
  generation.
- Strike craft lose readiness outside flight-deck support range.
- Sensors improve relay work. Pickets and scouts use extended sensor profiles.
- Flak, interception, anti-light, anti-frigate, and anti-capital relationships
  are bounded damage responses, not deterministic counters.
- Debris and wreckage mask missile attacks. Capital fire benefits from open lanes
  and rear-quarter geometry, so terrain and approach can outweigh type bonuses.
- Electronic warfare reduces nearby hostile guidance. Active-defense frigates
  combine ECM, decoys, and defensive fire for nearby allies. Support ships repair nearby active hulls. Minelayers
  damage hostile elements that enter their denial radius.
- An active command ship provides immediate reporting, full sensor sharing, and
  synchronized fire. Its loss adds report delay, reduces shared acquisition and
  precision, and increases captain autonomy without disabling the interface.
- Recovery vessels can restore disabled command elements and preserve their
  persistent ship records.

`ship_operational_profile` exposes strategic capabilities for all 37 roles,
including boarding, capture, Propellant, cargo, fabrication, medical care,
population, settlement, archive, and command values. Systems should consume
these values rather than infer function from a display name.

## Presentation

The 3D combat renderer uses a shared admiralty silhouette with one archetype
mark for each of the 24 production hulls. The selected-element panel shows the
operational role. Contact footprint follows a compressed logarithmic tonnage
scale, so displacement is ordered consistently without making strike craft
unselectable or capital ships screen-sized. A labeled five-step tonnage band
reinforces the same information without relying on size alone. The alpha-matted
6×4 raster atlas in `assets/ships` provides
the same vocabulary for future canvas and non-3D consumers.

The main menu's Ship Guidebook groups all 37 operational configurations into
the six fleet families. Each entry shows its production hull, tactical icon,
installed modules, function, field response, and the capability record consumed
by the simulation. A Combat Basics page explains objective play, screening,
counter relationships, terrain, nearby support, recovery, and withdrawal in
plain language.
