# Fleet Navigation

Fleet navigation is a deterministic campaign rhythm:

**Plan one leg → burn → coast → arrive → harvest → revise**

The player commands destinations and acceptable risk. Captains automate burns,
station-keeping, transfers, refining, and tanker balancing. The campaign stops
for attention when a leg or hold completes, or when a material change invalidates
its declared reserve, deadline, return, or fleet-integrity boundary.

## Physical state

The campaign owns the fleet's current stellar system, reference body, position,
velocity, epoch, active order, protected reserve, water deposits, and causal
navigation history. Each ship owns dry mass, propellant capacity, current
propellant, thrust, and exhaust velocity. Damage and mobility impairments affect
the resulting forecast.

Propellant is balanced automatically: every active ship receives its protected
reserve, tankers fill next, and the remainder is distributed among other ships
in proportion to headroom. The normal interface shows the aggregate, reachable
destinations, arrival reserve, limiting ship, and whether the target's known
water source can replace the planned burn. Ship dossiers expose exact
inventories.

## Transfers

`fleet_transfer_forecast` is the authoritative pure preview. It evaluates the
generated Keplerian ephemerides, solves a deterministic Lambert transfer, and
applies the rocket equation to every participating ship. A leg is feasible only
when every ship can complete its departure and rendezvous burns.

Committing a leg records its forecast and schedules arrival on the campaign
clock. Routine execution does not ask for confirmations. Crossing the protected
reserve requires an explicit emergency authorization and a causal record.
Route advice can recommend either the lowest-burn protected window or the
earliest protected window; the latter exposes campaign-time pressure as a
deliberate trade against propellant.

## Harvesting

Water deposits are derived once from generated body mass, composition,
temperature, gravity, and rotation. Their remaining recoverable mass persists.
Tankers and ship condition determine deterministic extraction and refining
throughput. Power, heat, losses, storage, and transfer work are throughput
factors, not player-managed resources.

A hold has an aggregate propellant target and latest departure date. It ends at
the first governing condition: target, deadline, full storage, or depletion.
If ship condition reduces refining throughput during an active hold, the
campaign stops for attention, preserves the work already completed, and revises
only the remaining window within that declared departure deadline.
No rescue deposit or incident is generated after chronicle creation.

## The Outer Dark

Normal-space propellant governs movement inside stellar systems. Interstellar
travel uses mapped Outer Dark correspondences. Reaching a correspondence is a
local transfer; crossing its Dark segment is a separate planned leg governed by
time, coherence, topology, and exposure. Direct relativistic interstellar legs
are unavailable.

Passage detachments escrow the physical propellant aboard their selected ships.
The main fleet may move while they are away. Fleet ephemerides therefore alter
their return forecasts and can create navigation attention when the protected
return reserve becomes infeasible.
