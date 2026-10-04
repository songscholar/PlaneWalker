# P15E Native Event Ambush Evidence

- Status: Approved / Current
- Document Role: Current executable event-encounter production evidence
- Authority Level: Verification below the P15E specification
- Applies To: Launch event rooms, catalog, Facade, RoomRuntime and native Player frames
- Owner: Project runtime implementation lead
- Depends On: `docs/superpowers/specs/2026-10-05-plane-walker-p15e-native-event-ambush-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual native event encounter and targeted regressions pass

## Verified Production Flow

Actual Main accepts the Wanderer/sword Launch loadout with stop and rewind and
seed 6. Host routes the generated `layer_01_a`, `layer_02_a`, `layer_03_c` path.
The real selector freezes `event_sleeping_guardian` in the actual streamed
`room_event_crossroads` scene. Its authored `commit` option starts a native
encounter whose room identity is the real floor node.

All three event templates and scenes declare `enemy_wave_primary` at (416, 176).
The event resolver strictly validates the actual event template and selects an
authored combat recipe through its own seed/profile/node channel, after existing
spawn-offset, entry-distance, separation and camera-margin checks. Normal combat
template compatibility remains enforced. No compatibility species substitute is
introduced, and the authored ruins profile remains the Sleeping Guardian source
on later floors as well.

The RoomRuntime keeps the original event profile and continuation ID. Runner
completion is authenticated against its concrete recipe snapshot, settled state,
empty living/pending roster and actual outcome. Only then is the original profile
submitted to the event authority. Active completion/failure signals, profile-ID
impersonation, foreign continuation rebinding and duplicate settlements have no
event consequence. Repeated accepted synchronization does not restart a Runner.
Synchronous start refusal cannot report success or replace the prior continuation.
Room synchronization also checks the complete current Facade view, authoritative
continuation and accepted revision before touching the Runner. Forged terminal
views and stale successful command results cannot cancel an active encounter.

Accepted actual Player frames spawn physical native actors at the authored event
anchor. Authenticated final-death receipts complete the selected waves, resolve
the original event consequence, allow dismissal and reopen normal route choices.

The two prerequisite combat room clears and lethal Health calls are explicit
fixtures. This establishes production wiring, native wave/death settlement and
event routing. It does not establish unaided combat balance or a five-floor run.

## Retained Verification

All paths below are under `build/test-logs/p15e-event-production`.

- Meaningful actual Main RED: `authored-anchor-red`, absent event anchor/resolver.
- Catalog contract RED: `catalog-red`, absent event-geometry resolution API.
- Actual Main native ambush and forged-view preservation GREEN: `production-final`.
- Catalog strict event geometry/determinism GREEN: `catalog-final`.
- Continuation success/failure/forgery/reentry/start-refusal plus current
  authority matching GREEN: `sync-authority-green`.
- Meaningful forged-terminal/stale-command synchronization RED:
  `sync-authority-red`, identified by independent focused review.
- Existing RoomRuntime GREEN: `regression-room-runtime`.
- Event Facade GREEN: `regression-event-facade-authority`.
- Existing event room lifecycle GREEN: `regression-event-lifecycle`.
- Native production encounter GREEN: `regression-native-production`.
- Six safe native cold checkpoint cases GREEN: `regression-native-checkpoint`.
- Actual authored room-scene contract GREEN: `regression-room-scenes`.

The Event Facade regression first exposed its obsolete Runner test fixture: it
lacked the production native configuration interface introduced by P15N. The
fixture now records and verifies the exact Host participants. It remains a
composition fixture; the separate Main test supplies actual gameplay evidence.

Every retained GREEN has zero known leak warnings and no script, parse or
missing-resource errors. The established macOS certificate warning is environment
noise. Godot does not collect line coverage here; no coverage percentage is claimed.

## Content Handoff And Remaining Work

The root content owner refreshed the four changed content hashes in the pack
descriptor and retained the previous P17 compatibility snapshot. Final verified
descriptor fingerprint is
`bfe092524cafc7054aa38b379e374198a1d47c85f4a3c14ca97047e73a3a142b`;
aggregate is
`3d217de6fec4ad4d4527486cddf381321f53873474197f064ffd0dbb85552227`.

Active combat checkpoint reconstruction, full native enemy/Boss mechanisms and
affixes, and unaided full-game balancing remain subsequent milestones. This
event ambush milestone does not claim full-product completion.
