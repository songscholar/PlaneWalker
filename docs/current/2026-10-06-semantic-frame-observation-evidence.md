# Semantic Frame Observation Evidence

- Status: Implemented / Focused verified
- Document Role: Current semantic observation optimization and regression evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Native semantic effect commit observation, complete compensation and historical fallback
- Owner: Project integration lead
- Depends On: [Gameplay completion plan](../superpowers/plans/2026-10-06-gameplay-ui-product-completion.md)
- Last Verified: 2026-10-06
- Certification Status: No full-current-source, frame-budget, saturation, rendered, soak, UI or human certification

## Observed Work And Change

`LaunchSemanticEffectAuthority._observations_match` previously requested a
complete `launch_runtime_snapshot` solely to compare `runtime.runtime_frame`.
That copied the Boss action, mechanism and arena state on every commit guard.
The Actor already exposes `native_frame_boundary`, which reads the current
Boss run, frame and terminal fields directly from its owned runtime.

The guard now reads only that boundary's frame. A method-missing historical
Actor retains the original complete snapshot fallback. Ordinary enemy runtimes
currently lack the three narrow runtime queries, so their Actor boundary still
uses one complete runtime snapshot. This slice does not claim an enemy snapshot
reduction or change that compatibility behavior.

The complete Health snapshot comparison, queued-for-deletion refusal, exact
global position comparison and full semantic ticket equality remain unchanged.
Frame equality still chooses `prepared_position`; a different frame chooses the
original `position`. The optimization adds no new clock, identity or terminal
acceptance rule, and complete preparation and rollback snapshots remain intact.

## Executable RED And GREEN

The replacement fixture loads five authored Boss scenes and the actual
`shattered_sentinel` and `rift_watcher` scenes. It prepares sealed Actor and
semantic tickets, commits the real Actor frame, compares the old full-snapshot
oracle with the new guard before and after commit and on an adjacent frame,
then exercises drift refusal, successful retry and complete rollback.

Valid RED is `build/semantic-frame-observation-red-v4`, whose stdout SHA-256 is
`a026ec615959589cdc5325e0d1bfedc0dd229fa1a6dbfe9e7294f79c6631f93f`.
It has exactly 20 assertion failures: four observation cases for each of five
Bosses expected zero complete runtime snapshot calls but observed one. Every
other fixture assertion passed; no script failure or leak explains RED.
Earlier `red`, `red-2` and `red-v3` attempts are fixture-development history and
are excluded from this executable result. `red-v3` was stopped after its type
inference error; the final fixture uses explicit Dictionary types.

GREEN is `build/semantic-frame-observation-green`, 1 passed and 0 failed.
The final fixture additionally proves the historical method fallback and
compares full Actor transaction and Health bytes. Each current Boss observation
uses zero complete runtime snapshots; both ordinary enemy observations retain
exactly one. The moving sentinel proves that original and prepared positions
are distinct. Health loss, a 0.125-pixel body drift and a forged frame ticket
still refuse; restoration retries and complete compensation succeed.

Each observation leaves the complete Actor, Actor transaction, Health and
semantic snapshots byte-equivalent. Node-bearing pending tickets also compare
equal by Dictionary identity, which avoids relying on object-free byte encoding
alone.

## Verification

| Scene | Retained directory | Result |
| --- | --- | --- |
| Semantic observation, five Bosses and two enemies | `build/semantic-frame-observation-green` | 1 passed, strict paired logs pass |
| Existing native boundary observation | `build/semantic-adjacent-boundary` | 1 passed, strict paired logs pass |
| Existing native semantic effect lifecycle | `build/semantic-adjacent-effects` | 1 passed, strict paired logs pass |

All six successful stdout and Godot logs have SHA-256
`31d2c6ce473319bd9b389b9f9af5ceb6eea678a637282aa49dd2fed1a3d69f60`.
They contain the same minimal engine header and successful assertion summary;
each physical pair was independently validated with zero expected-error scopes.
The two GDScript files pass the pinned AST parser and `git diff --check`.

Production source SHA-256 before this slice is
`89462aa5392172b234a0ab2c3e7cd57396bb8267eb45ea54b9bbe80aa57e5758`;
after it is `debdaa036975c304d014fd848c0f2a0a2c97fed0965b56416160b48eb0019e3f`.
The final fixture SHA-256 is
`299bcd0144b8048cfac2f074fcde46d8932e198c2bcf545ea79333c6e59619b6`.

This verifies removal of redundant Boss observation copies and unchanged
transaction behavior. It supplies no frame-time improvement percentage, full
suite coverage rate or release performance claim. Real-time performance,
complete current-source certification and the complete Native matrix remain
separate gates.
