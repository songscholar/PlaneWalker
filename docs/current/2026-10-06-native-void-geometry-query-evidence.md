# Native Void Geometry Query Evidence

- Status: Implemented / Current
- Document Role: Current focused native Void projection verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Native Void arena geometry and active pickup observation
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-void-geometry-query-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Verified Boundary

Void arena queries return a detached current projection containing arena
origin, terminal state, pillars and cores. Boss active pickup queries reuse the
existing detached `VoidAuxiliaryRuntime.active_pickups()` filter and order.
Only actual Void geometry/presentation observation sites use the projections.
Query-less runtime implementations keep the original complete-snapshot
fallbacks. Public complete snapshots retain all events and receipts.

No query replaces current domain ownership, restore validation, transaction
compensation, physical node/shape checks, accepted resource receipts, cold
verification or recorder state. No auxiliary validation implementation, content,
gameplay value, recorder capacity or admission budget changes. Independent
read-only review found no actionable issue in the three production diffs and
focused contract.

## Focused Contracts

`build/native-void-geometry-red` retains one missing-query assertion without
script/parse failures or leaks. Final GREEN is retained in
`build/native-void-geometry-green-2`. Exact typed-byte comparison covers actual
arena damage, phase transition, second-round core regeneration, retirement,
historical rollback and changed origin. Mutating query origin, terminal state,
construct rows or nested positions cannot mutate the full domain state.

An actual authored Void actor uses counted real arena and auxiliary runtimes.
Narrow query, native refresh and complete physical geometry checking take zero
full domain snapshots. Public complete snapshots still take exactly one
original capture each. Pickup filtering and order match the original full
projection for active pickups, real resource consumption, expiration, phase
retirement and historical restore. Nested pickup mutation is detached. Actual
pickup collision-radius and construct-transform tampering still refuse. Empty
unconfigured Boss queries and query-less complete fallbacks remain exact.

All 46 focused scenes pass:

| Contract | Retained Logs | Scenes |
| --- | --- | --- |
| Native Void geometry observation | `build/native-void-geometry-green-2` | 1 |
| Native boundary observation | `build/native-void-geometry-hostile_boundary_observation_test` | 1 |
| Native hostile Bridge | `build/native-void-geometry-hostile_frame_bridge_test` | 1 |
| Actor transaction and rollback | `build/native-void-geometry-launch_actor_transaction_test` | 1 |
| Actual Void Player frame | `build/native-void-geometry-void_player_frame_test` | 1 |
| Actual Boss actor | `build/native-void-geometry-launch_boss_actor_test` | 1 |
| Enemy unit contracts, including concurrent Void checkpoint slice | `build/native-void-geometry-enemies` | 40 |

Every paired stdout/Godot log passes strict scoped runtime validation. Bridge
declares four exact expected synchronous refusal operations; Void Player frame
declares one. Each has the exact message/count, returns false and completes in
both logs. There are no unexpected errors, warnings, script/parse failures or
object/RID leaks. Godot is `4.6.1.stable.official.14d19694e`; line coverage is
unsupported. Documentation governance and diff whitespace checks pass.

## Remaining Measurement

The isolated uninstrumented complete-frame comparison is pending. Focused
snapshot counts establish eliminated full observations, not a measured speedup.
The integrated source still needs sustained throughput, rendered performance,
45-minute soak and human playtesting.
