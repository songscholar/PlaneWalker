# Native Void Burn Snapshot Query Evidence

- Status: Focused Verified / Integrated performance pending
- Document Role: Current gameplay performance implementation evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Void candidate-frame burn request observation
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Depends On: `docs/current/2026-10-06-native-void-burn-snapshot-query-plan.md`
- Evidence Status: Verified Locally
- Certification Status: No frame-budget, rendered, sustained or full-gameplay certification

## Retained Authority And Behavior

The actual Void Actor queries burn requests from its complete candidate Boss
snapshot instead of restoring a second arena preview only to read them. The
instance-owned Boss query still runs the original complete Boss validator;
the auxiliary query still runs the original complete child validator. Neither
query installs supplied state. Live and historical reads share the original
burn request algorithm, including exact payload identity, typed fields,
frame matching, six ticks, exclusive expiry and terminal behavior.

The real body preview remains. Query-less runtimes still execute the original
arena preview and restore. Other Boss previews perform mutations and remain
unchanged. No schema, gameplay damage, accepted history, geometry check,
receipt or rollback rule changes.

## Executable RED And GREEN

The new actual integration scene is
`tests/integration/combat/void_burn_snapshot_query_test.tscn`. Its original
production RED, retained at `build/native-void-burn-snapshot-query-red/`,
fails exactly three assertions: the missing Boss query, missing child query
and actual unnecessary arena preview. It has no other assertion, script,
parse or leak failure. The postimplementation GREEN in
`build/native-void-burn-snapshot-query-green/` passes with strict paired logs.

The fixture generates a real Scepter action and accepts its actual damage
receipt. It compares all typed request bytes with a separately configured,
fully restored original Boss at warning, receipt, six 30-frame ticks,
exclusive expiry and terminal boundaries. Repeated historical queries after
live terminal preserve complete input and live bytes. Caller mutation remains
detached. Full schema/owner/definition, derived burn, history and unrelated
arena corruption still refuse; standalone child corruption and unconfigured
or non-Void authorities also refuse.

The native scene verifies that only the body preview exists on the query
path, the query-less fallback still owns an arena preview, complete fallback
ticket/batch bytes match and rollback retains exact live Actor bytes.

## Focused Regression And Review

All 26 scenes selected by `--filter void_` pass, with retained per-scene
paired logs at `build/native-void-burn-snapshot-query-neighbors/`. These include
actual auxiliary lifecycle, damage/identity, pickups, Step, phase/heal,
physical geometry/collision, cold storage and player-frame behavior.
Three additional actual scenes pass with strict paired logs:

| Scene | Retained Log Directory |
| --- | --- |
| `hostile_frame_bridge` | `build/native-void-burn-bridge-regression/` |
| `native_run_replay_recorder` | `build/native-void-burn-recorder-regression/` |
| `native_recording_snapshot` | `build/native-void-burn-recording-regression/` |

The progress-validation lane independently reviews the production diff and
fixture and finds no actionable issue. Godot is
`4.6.1.stable.official.14d19694e`; direct line coverage is unavailable and is
not represented as measured coverage. Existing full clean certification and
the frozen native750 continue independently. No integrated timing result is
claimed for this slice; UI production and human playtesting remain pending.

| Retained Path | SHA-256 |
| --- | --- |
| `scripts/enemies/launch/launch_boss_actor.gd` | `29a105da50bfb16c6d4970c98cf1bd0d24a66ac4f3a319b33d76b9d4763382b3` |
| `scripts/enemies/launch/launch_boss_runtime.gd` | `d2b4d212b020036fbec1786c75b1036d96e77c506d53b8bda0b536ed88895ca5` |
| `scripts/enemies/launch/void_auxiliary_runtime.gd` | `86a0536da93802d3f761590f07e18a83969ea5b877cdfbb8de016e011c22415f` |
| Acceptance `.gd` | `6ac2fa42ef4e12421f8f4e92db2557b7e7c058022c3e1df822ae487ee0063845` |
| Acceptance `.tscn` | `3c2b21b7098e8ea2309daa59fce9723225e0440e1c354c2947827e418e7c75b0` |
| RED stdout | `a451f8401f818cb08569809e2732e3eb2537ada635f6b0569e2803e169347d22` |
| GREEN stdout | `31d2c6ce473319bd9b389b9f9af5ceb6eea678a637282aa49dd2fed1a3d69f60` |
