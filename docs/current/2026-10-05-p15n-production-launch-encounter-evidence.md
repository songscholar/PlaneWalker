# P15N Production Launch Encounter Foundation Evidence

- Status: Approved / Current
- Document Role: Current executable evidence for production native encounter integration
- Authority Level: Verification below the P15N specification
- Applies To: Main, Host, Facade, RoomRuntime, EncounterRunner and native hostile frames
- Owner: Project runtime implementation lead
- Depends On: `docs/superpowers/specs/2026-10-05-plane-walker-p15n-production-launch-encounters-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Production integration foundation and targeted regressions pass

## Verified Production Path

Actual Main launches the activated Launch content. Facade resolves the full
LaunchEncounterCatalog against the actual floor node and compatible authored
template. The existing registry catalog projection removes only pack provenance
metadata before strict definition validation. M1 retains its original catalog.

EncounterRunner binds a native driver to the actual Player, RoomController,
threat registry, authored room scene, encounter ledger and hostile payload owner.
Wave clocks advance only through accepted Player frames. Native spawns use
actual room anchors plus authored offsets, deterministic source identities and
the activated hostile definitions. Post-frame publication acknowledges native
actors before another frame can enter the aggregate.

`production_launch_encounter_test` verifies real Main and Host route entry,
native first-wave registration, source and frame identity, physical room-motion
binding, paused wave clocks and exact whole-aggregate late rollback. Forged
Health death signals and forged final-death receipts cannot remove living roster
rows. The complete selected elite recipe executes every authored wave, retires
authenticated native death receipts and publishes one room clear and reward.
Completion compares the concrete resolved recipe ID rather than its profile ID.

Wave and spawn callbacks refuse aggregate replacement, duplicate committed
signals and Player frame reentry. Cancelling in a wave callback stops subsequent
same-frame warnings, tears down the native aggregate at the accepted boundary,
and releases the Player frame owner.

The lifecycle test uses explicit lethal Health fixtures to close roster rows;
it proves native death authentication and room settlement, not unaided combat
balance or a complete five-floor production playthrough.

## Retained Test Results

Meaningful missing-production RED: `build/test-logs/p15n-launch-production/red`.
Real activated metadata RED: `catalog-diagnostics`.
Real forged-death and missing-room-completion RED: `room-lifecycle-red`.
Production lifecycle and cancellation GREEN: `cancellation-complete`.
Accepted native Run, room and concrete encounter metadata RED: `metadata-red`;
GREEN: `metadata-green`. The binding uses the existing Controller scope helper
before actor configuration and retains the resolved concrete encounter identity.

Seven targeted regression scenes passed under the same log root:

- `regression-facade`: RunRuntimeFacade.
- `regression-encounter-runner`: legacy EncounterRunner behavior.
- `regression-room-runtime`: RoomRuntime behavior.
- `regression-native-actor-final`: native Launch hostile actor behavior.
- `regression-frame-authority`: native finite Moth payloads and room completion.
- `regression-meta-host`: authenticated actual Host launch.
- `regression-native-checkpoint-shared-drain`: all six physical safe cold cases.

Every retained GREEN scene passed with zero known leak warnings. Scans found
no script errors, parse errors or leaked native instances. Expected injected
late-frame refusals emit the established fixed-frame rejection diagnostic.
The existing macOS certificate lookup warning is environment noise. Godot
4.6.1 does not expose line coverage here; no coverage percentage is claimed.

The updated M1 compatibility smoke is separately retained by the Main owner at
`build/test-logs/p17b-m1-compatibility` and passes with zero leaks. Its explicit
M1 run still traverses all five rooms; the current production start remains Launch.

## Remaining Production Work

- Complete native Boss zone, healing, summon, wall, arena and time-response owners.
- Apply every selected elite affix through actual native state and frame behavior.
- Complete event-ambush encounter anchors and concrete continuation ID binding.
- Finish all twenty-two native species mechanisms and complete production scenes.
- Recreate active combat actors, payloads, waves and clocks in cold checkpoints.
- Prove a full five-floor gameplay run without fixture completions.

This milestone removes the legacy encounter substitution from the production
Launch route. It is a verified integration foundation, not full-product completion.
