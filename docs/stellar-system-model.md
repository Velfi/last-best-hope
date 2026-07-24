# Stellar-system model v2

The game generates a present-day deterministic snapshot from a formation seed,
age, and metallicity. Campaign time advances only the ephemeris. It does not
advance stellar evolution.

## State and hierarchy

A system contains one or two stellar components, an optional bound binary
orbit, and bodies whose `Orbital_Host` is a star, planet, or stellar
barycenter. Orbital elements use AU, radians, and days. All public evaluation
procedures are pure and permit random access to an epoch.

The model records architecture-changing events in a fixed-capacity timeline.
Planets removed by engulfment or loss are represented by an event and are not
left in the current bound-body arrays.

## Evolution

Rapid stellar and binary evolution follows the phase structure and interaction
ordering described by Hurley, Pols & Tout (2000) and Hurley, Tout & Pols
(2002): main-sequence evolution, giant branches, compact remnants, winds,
Roche-lobe overflow, stable transfer, common envelopes, mergers, core collapse,
and binary disruption. Roche lobes use the Eggleton approximation. Model
constants and remnant mappings are centralized in `stellar_evolution.odin` and
covered by reference/property tests.

The implementation is a population-synthesis model, not a detailed stellar
structure solver. Its output is a deterministic classification and survey
estimate. The UI must not present it as a directly measured evolutionary
track.

## Dynamics and validity

Keplerian elements are propagated with a deterministic Newton solution of
Kepler's equation. Binary components are placed about their mass-weighted
barycenter. Circumbinary planets include forced eccentricity plus apsidal and
nodal precession; circumstellar planets include companion-driven apsidal
precession. These secular terms assume a hierarchical, low-inclination system.

Generation uses the updated empirical S-type and P-type critical-radius fits
from Quarles et al. (2018, 2020) and adds a ten-percent safety margin. It rejects
or removes bodies that cross the relevant critical region or stellar envelope.
This is not an N-body proof of stability and must remain labelled as a model
estimate in player-facing presentation.

## Radiation and climate

Instantaneous flux is the inverse-square sum of all bound luminous components
at their evaluated positions. A deterministic 256-sample orbital envelope
stores mean, extrema, variance, and eclipse-floor estimates. Climate history is
segmented at architecture-changing stellar events. Habitable-flux screening is
an initial survey classification; the mass- and temperature-dependent limits
are based on Kopparapu et al. (2014).

## Habitability evidence

Campaign astronomy uses one fixed model. Difficulty, Story Tempo, and bot
profile do not change it. The observation-calibrated input is the occurrence of
terrestrial planets in the conservative habitable zone: 0.33 planets per M star
(validation interval 0.21–0.43), and 0.37 per pooled F, G, and K star
(validation interval 0.15–0.60). These are occurrence rates, not guarantees that
a system or campaign contains a candidate.

Every surveyed planet passes through a deterministic evidence chain:
terrestrial composition, conservative habitable-zone orbit, dynamical
stability, atmosphere retention, accessible water, and a temperate climate for
at least half its modeled stable history. Gravity, radiation, and tidal state
can rule out settlement or create an engineered candidate.

Orbit, gravity, flux history, surface composition, and local radiation are
presented as measured evidence. Atmosphere retention, accessible water,
long-term climate, abiogenesis, and complex life are model assumptions. The
game does not claim an empirical rate for surface habitability or biospheres.
An expedition surveys one reachable mapped system; it does not search other
systems behind the scenes. Barren, giant-only, and unsuitable systems—and
campaigns with no credible home—are valid outcomes.

## Primary references

- Hurley, Pols & Tout, *Comprehensive analytic formulae for stellar evolution
  as a function of mass and metallicity* (2000),
  <https://arxiv.org/abs/astro-ph/0001295>.
- Hurley, Tout & Pols, *Evolution of binary stars and the effect of tides on
  binary populations* (2002), <https://arxiv.org/abs/astro-ph/0201220>.
- Leung & Lee, *An Analytic Theory for the Orbits of Circumbinary Planets*
  (2012), <https://arxiv.org/abs/1212.2545>.
- Quarles et al., *Stability Limits of Circumbinary Planets* (2018),
  <https://arxiv.org/abs/1802.08868>.
- Quarles et al., *Orbital Stability of Circumstellar Planets in Binary
  Systems* (2020), <https://arxiv.org/abs/1912.11019>.
- Kopparapu et al., *Habitable Zones Around Main-Sequence Stars: Dependence on
  Planetary Mass* (2014), <https://arxiv.org/abs/1404.5292>.
- Hsu et al., *Occurrence Rates of Planets Orbiting FGK Stars* (2020),
  <https://arxiv.org/abs/1902.01417>.
- Bryson et al., *The Occurrence of Rocky Habitable-zone Planets around
  Solar-like Stars from Kepler Data* (2021),
  <https://doi.org/10.3847/1538-3881/abc418>.
