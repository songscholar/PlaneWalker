# Native Boss Control Observation Evidence

- Status: Focused Native Contracts Verified / Committed-source timing pending
- Document Role: Current gameplay performance implementation and evidence
- Authority Level: Below AGENTS.md and native performance probe specification
- Applies To: Actual Boss sprite and committed telegraph observation paths
- Owner: Native observation lane
- Last Verified: 2026-10-06
- Depends On: `docs/current/2026-10-06-native-boss-control-observation-plan.md`
- Evidence Status: Verified Locally
- Certification Status: No FPS, rendered performance or complete gameplay certification

## Retained Behavior and Scope

`LaunchBossActor._refresh_control_visual` now builds only its current frame,
terminal and detached action presentation input through the existing native
queries. Its source ordering, safe contact deferral, arena/auxiliary refresh,
root-sweep projection, Watch update, Atlas configuration, pose/facing/clock and
exposure tint are unchanged. Generic telegraph phase selection uses existing
action/terminal queries when present. Ordinary native cold threat facts copy
only the detached current action geometry before the original native-fact
conversion, retaining complete typed fields and primitive order.

Time Sovereign self-rewind retains the complete original snapshot branch for
its historical landing and owner identity. Its `native_watch_snapshot` remains
unchanged, including consumed/cancelled casts and broken interrupt HP. Runtimes
without native queries retain the original complete snapshot algorithms and
copy counts. Ordinary Enemy runtimes currently follow that fallback.

Only the two Actor scripts, one new actual integration scene and these
documents are changed. BossRuntime, budgets, save/replay schemas, gameplay
rules, existing visual design and frozen matrix sources are not modified by
this slice. Arena and Forest auxiliary history copies remain separate work.

## Actual RED and GREEN

The new scene is
`tests/integration/combat/boss_control_visual_observation_test.tscn`.
It instantiates every authored native Boss scene, restores a counted real
BossRuntime to its actual full boundary and compares outputs to the original
full-snapshot algorithm using production Atlas/telegraph components.

The first fixture attempt additionally exposed two duplicate threat
registrations after fixture rollback. That initial log remains retained under
`build/native-boss-control-observation-20261006/red/`. The corrected
preimplementation acceptance run is retained under `red-acceptance/`, with
runner output `red-acceptance.stdout.log` in the same evidence directory.
It has exactly 60 failed copy-count assertions, no other failed assertions,
script/parse failure or leak. Sixteen ordinary refreshes compose 48 complete
Boss snapshots; Time Sovereign composes 64. All original output and authority
parity assertions already pass in this RED run.

After implementation, the same scene passes with strict paired stdout/engine
logs under `green/` and runner output `green.stdout.log`:

| Actual 16-refresh batch | Before | After |
| --- | ---: | ---: |
| Ordinary non-Time Boss | 48 full snapshots | 0 |
| Time Sovereign, ordinary action | 64 | 16 retained Watch snapshots |
| Time Sovereign, self-rewind | 64 | 32 retained Watch/landing snapshots |
| Query-less non-Time adapter | 48 | 48 |
| Query-less Time adapter | 64 | 64 |

Every batch checks original typed cold facts and detached returned descendants,
complete Atlas snapshots/modulation, all general/root telegraph fields and
Watch projections. Exact Actor/runtime/Health/threat-registry bytes remain
unchanged. Actual warning, active, recovery, cancellation, terminal, historical
restore, owner reconfiguration and query-less warning states are covered.
Eight accepted Time Sovereign frames create an actual historical landing
different from its current actor position. Two refresh requests during native
contact dispatch make zero complete reads, preserve the shown sprite until a
safe deferred flush and clear the queued flag before observing current state.

## Focused Native Neighbors

All nine real scene neighbors pass. Per-scene paired strict logs are retained
under `build/native-boss-control-observation-20261006/neighbors/`:

- `launch_hostile_telegraph`
- `forest_root_sweep_native`
- `boss_watch_native`
- `void_half_arena_native`
- `launch_boss_actor`
- `boss_frame_observation`
- `boss_ui_observation`
- `native_enemy_spatial_lifecycle`
- `time_sovereign_auxiliary_native`

The Watch neighbor verifies actual five-weapon 80-damage interruption,
rollback/retry, broken projection and fresh cold reconstruction. Root-sweep
verifies actual root destruction, warning restoration on rollback and physical
hit parity. General warning/cold and spatial lifecycle neighbors exercise
ordinary Enemy fallbacks. No unapproved script, engine error or leak appears.
Godot line coverage is explicitly unavailable, not reported as measured.

## Review and Source Retention

Root and the progress-validation lane independently read the precise production
diff and acceptance fixture and found no actionable issue. They checked real
Boss query ownership, ordinary Enemy fallback, self-rewind/Watch retention,
callback-before-query ordering, complete typed projection parity and immutable
returned data. Working-tree focused tests do not replace the integration lead's
final clean committed-source validation and performance run.

| Retained Path | SHA-256 |
| --- | --- |
| `scripts/enemies/launch/launch_boss_actor.gd` | `7053559ac1dafc46d4d1ec5be940cba4f0a767cb835e56ccb18978aca105a3bb` |
| `scripts/enemies/launch/launch_hostile_actor.gd` | `98341a4ab96d85855d368646c2b9b9abde3b34b8c3fbf9346078a400ad84c158` |
| New acceptance `.gd` | `702fc429361f6972b64ce89c97ece4350d6223da80b324b80037031fabe0214a` |
| `red-acceptance.stdout.log` | `d4ccb8def9ba1079b9a4e3f737aa0c2405d5e7fca29e20d32cce286d481b8c8c` |
| `green.stdout.log` | `2c37a09a3659d02820a17afcd0514f364524700d89c233cf8124f0806f0b3e83` |
| `neighbors.stdout.log` | `04c9fdf72de10e4c48fa9d22387c17b9a4f73c983b004636d5981599bd11e968` |

Separately, the earlier performance v2 validator integration passes the entire
CI orchestration contract on frozen `546779f9af6f3efe7bf551734398a9a1a9a1b1d0`
with explicit installed Python 3.10.16. Its 502 discovered scenes are mocked
orchestration evidence, not 502 actual native test certifications. The log is
`build/retained-checkout/ci-measurements-546779f-20261006/build/native-measurements-ci/ci-contract-python310.stdout.log`,
SHA-256 `ad871f76fca450b74810d4a23138335c5d65859b3d1b195a1f139501be39d9d4`.
Earlier shared-tree attempts were affected by newly unindexed current documents;
the first frozen attempt selected Python 3.13 without `jsonschema`. Both failed
attempts remain retained rather than relabeled as passes.

The independent frozen `abd5b6f` native750 remains running untouched. This slice
proves copy elimination and semantic parity; it does not establish a frame
budget, long-recording, saturation, human-playtest or complete gameplay pass.
UI production has not begun.
