# Plane Walker P16G Native Material Sources Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation evidence
- Authority Level: Native Encounter-to-Run settlement source boundary
- Applies To: EncounterSettlementAdapter, RunState material retention, terminal settlement and source policy
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Focused native sources; production encounter activation and full checkout certification pending

## Native Source Boundary

The adapter binds actual RunState and LaunchEncounterRuntime objects, the frozen
launch projection, visited current room, authored encounter digest and generation.
Registration requires a pending principal spawn, one native object per binding,
matching source/run/seed identity and an exact authored enemy or elite projection.
The twenty-two enemy definitions are read from the authoritative base catalog.

A source is accepted only from the bound native final-death signal with matching
initial runtime identity/definition, terminal runtime, dead Health and canonical
death receipt. Forged live signals, altered source properties, foreign definitions,
duplicate registrations and replacement room generations refuse. The role comes
from the encounter spawn, not from an actor property or caller reward amount.

The closed material policy currently grants one shard for an elite principal;
ordinary actors, Boss material and support work grant zero. Boss completion and
first-clear rewards retain their separate settlement authority. Amount bounds
agree across native insertion, terminal settlement and the JSON Schema.

RunState owns detached source insertion, canonical identity, deduplication and
event/revision limits. Source retention and Encounter retirement commit together.
An authenticated death refused by retention remains in an internal pending queue,
with an explicit retry result. It can retry after the native Actor is released;
the original launch, room, generation and roster must still match. An append
failure restores Encounter state. A future native room coordinator must call
retry_pending_deaths before allowing completion and expose retention refusal.
The adapter is not yet installed into Main's production room coordinator.

## Verification and Retention

Missing-adapter RED: planewalker-tests.JJ7EjK. Actual death in an unfinished room
RED: planewalker-tests.KqNDuy; terminal settlement now recognizes defeated
principals in the genuine visited current room, while Boss sources still require
cleared-room facts. Fixture parse errors are not counted as domain RED evidence.

Native GREEN: build/test-logs/p16-native-material-reviewed-v2, 1/1 scene. Tests
use a real generated floor, authored native Actor and Health death, then terminal
JSON round-trip. An elite material combines with the death guarantee for four
shards. Capacity, suspension and revision refusal preserve pending state; the
Actor is freed before retry, and repeated retry grants no second reward.
Zero-pay ordinary death retires without material retention even at event capacity.
Above-policy matching submitted/retained sources also refuse at settlement.

Settlement regression: build/test-logs/p16-material-settlement-regression, 1/1.
Closed policy Python contracts: 3/3. No runtime errors or leaks in final focused
logs. Independent review prompted participant typing, identity/digest sealing,
pending retries, amount caps and the one-object binding guard.

The test encounter is an explicit adapter fixture. It does not certify production
recipe authoring, elite affix execution, room completion UI, new save checkpoints
or packaged gameplay. The immutable d697164 certification exceeded its 1200-second
validation deadline and remains failed; focused GREEN does not supersede that
evidence. Godot line coverage and formal export components remain separate gates.

All changes are recoverable in a focused local commit. No remote publication or
external account use is involved.
