# P15B Native Boss Temporal And Shared Semantic Router

- Status: retained implementation; broader Boss production scope remains active
- Document Role: Current implementation and verification evidence
- Authority Level: retained milestone evidence
- Applies To: P15B native Boss temporal runtime and shared semantic effects
- Owner: Plane Walker implementation team
- Depends On: P15D semantic authority foundation `09b74bd`
- Last Verified: 2026-10-05
- Date: 2026-10-05
- Dependency: P15D semantic authority foundation `09b74bd`
- Scope: authenticated native healing, Time Sovereign historical self rewind, and shared semantic effect transactions

## Executable Acceptance Criteria

1. Boss healing accepts only exact native receipts, rejects duplicate or inconsistent gains, and cannot reverse an already accepted phase.
2. Time Sovereign retains 180 accepted 60 Hz position/HP rows. Self rewind freezes its historical landing and its 150 HP per-cast / 300 HP encounter healing caps at commitment.
3. Eighty distinct watch damage cancels a pending rewind, retires its warning, spends no healing budget and grants the authored 55-frame recovery window.
4. Native self rewind reaches an unoccupied historical landing while bypassing travel-path obstacles. Occupied landings leave the body at its current position. Room constraints and native collision checks remain authoritative.
5. Actual Boss Health and the gameplay domain agree after healing. Candidate healing publishes no signal. Rejection restores native HP, position, history, caps, claims and effect state; retry publishes one signal.
6. The shared Router prepares, commits, compensates and publishes both payload and semantic child authorities. Persisted snapshots contain data rather than old native identities or transaction-ledger objects.
7. An actual Chrono Guard corridor damages the real Player after its full warning, owns one native projection and one secondary threat envelope, and compensates all candidate state on rejection.

## Implementation

`launch_boss_runtime.gd` now authenticates healing and uses minimum accepted HP as phase provenance. Closed temporal state validates contiguous history, historical references, frozen amounts, caps, generations, cancellation and damage claims. Self rewind requests a sealed relocation at its first active frame and delegates actual healing to the shared Router.

`launch_hostile_effect_authority.gd` includes semantic snapshots and native-root binding. Its sealed tickets own both child transactions, native damage records and native health records. Health gains are applied through the real Health component, bounded by available HP, buffered until publication and authenticated back into the target Actor's gameplay runtime. The Router also installs and retires semantic threat envelopes, supports native Actor targets and accepts sealed non-Wraith consumption adapters.

The P15D Actor relocation adapter checks the destination itself using native `test_move`, avoids scaling a relocation with slow, and retains collision-safe room constraints. It does not move through an occupied landing.

## RED And GREEN Evidence

- Healing endpoint RED: `planewalker-tests.efeo64`; native receipt / phase provenance GREEN: `planewalker-tests.5PAIEc`.
- Temporal history/caps RED: `planewalker-tests.wVInp4`; domain temporal GREEN: `planewalker-tests.4TsRAj`.
- Actual self rewind RED: `planewalker-tests.UCDHKu` (missing Router mechanism), then `planewalker-tests.G1c4M0` (semantic handler) and `planewalker-tests.SCqGbX` (native relocation).
- Final domain + native temporal gate: `./tools/run_tests.sh --filter boss_temporal --timeout 120`, `planewalker-tests.VQjelT`, 2/2 passed. Native fixtures exercise both a travel-path obstacle and an occupied landing, real HP 1000 -> 1150, exact rejection and one accepted healing observation.
- Shared native zone gate: `./tools/run_tests.sh --filter launch_semantic_router --timeout 120`, `planewalker-tests.AFNOaO`, 1/1 passed. The real Player loses exactly 28 HP after 35 warning frames, the native corridor and secondary threat fact roll back, and retry publishes one damage observation.
- Existing shared effects gate: `planewalker-tests.XpdP93`, 1/1 passed.
- Existing Boss runtime / Actor / projectile gate: `planewalker-tests.YsDCOB`, 3/3 passed.
- Test runner scanned native logs; all final gates report zero known leak warnings and no script/load failures. GDScript line coverage remains unavailable and no coverage percentage is claimed.

## Retained Limits And Next Work

- Watch cancellation is currently exercised through authenticated domain facts. A real weapon-targetable watch proxy and its native lifecycle are the next Boss task.
- Complete Ruin, Forest, Forge and Void arena constructs, phase mechanisms, secondary warnings, owner cleanup and production art still require implementation and native acceptance tests.
- The shared Router delegates supported semantics to P15D. Unknown handlers remain fail-closed; this milestone does not certify every authored enemy or Boss action as playable.
- Active-combat cold save/replay reconstruction is owned by P16R and must include the new semantic state and immediate target projection.
- No remote push, publication, purchase or additional dependency occurred in this milestone.

Rollback uses a precise local Git commit together with dependency `09b74bd`; no broad working-tree reset is required.
