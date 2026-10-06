# Native Five-Floor Victory Evidence

- Status: Focused Verified / Unified certification pending
- Document Role: Current native gameplay verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Main's ordinary five-floor combat, final heart, ending, credits and durable settlement
- Owner: Project integration lead
- Depends On: `docs/superpowers/plans/2026-10-05-native-complete-gameplay-certification.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human, unassisted, FPS, coverage or complete-matrix certification

## Tested Source

The untouched archive of commit
`4735176afdfa571a60ffdbd4b597f746331f422c` is retained at
`build/retained-checkout/five-floor-4735176-20261006`.
After completion, all 408 runtime GDScript files under `scripts/` and `autoload/`
match that commit byte-for-byte. Their sorted path/digest map has SHA-256
`05890b7bd27f2754f476e307382218edbf82270d60639e592811cfd7ee8af9e5`.
The authoritative content aggregate is
`838c31095581b7abb79a63cb51b025d448c2ddd9d29b8ed75d2a318d8305bb2b`.

`tools/run_tests.sh --filter p15_five_floor_run --timeout 7200` exits zero.
The real Main fixture retains production 60 Hz physics and time scale 1.0;
the runner uses fixed-fps wall acceleration. Both retained logs pass
`tools/runtime_log_validation.py --test-suite-scopes` without script errors,
unexpected engine errors or object/RID leaks.

## Actual Result

The physical report at the archive's `build/p15-five-floor-native-run.json`
records `complete: true`, no failures and 12,153 accepted combat frames across
21 combat, elite and Boss rooms. The unlocked Profile and survival protection
are explicit fixtures. The report marks `synthetic: false`,
`unassisted_victory: false` and `human_playtests: 0`.

| Boss | Room Frames | Physical Damage Observations | Final Death Receipts |
| --- | ---: | ---: | ---: |
| ruin_king | 827 | 10 | 1 |
| forest_heart | 1,179 | 15 | 1 |
| time_sovereign | 969 | 13 | 1 |
| forge_colossus | 1,388 | 18 | 1 |
| void_throne | 1,822 | 27 | 1 |

Ordinary movement and weapon press/release, paid Accelerate, actual physical
damage and authenticated exactly-once final deaths advance the route. The
Player walks to the native final heart fragment. Main completes the
`shattered_freedom` ending and credits, then returns to the Hub. Fresh physical
Profile storage verifies the victory settlement: 235 shards, 10 imprints,
sequence 1, terminal reason `victory`, digest
`5a0193f187c0b8662d8f414e481d1b9a8f746ce997dbc8edad17b52afbdd1686`.

The report SHA-256 is
`a744f898fbf147a0f0a6b339175eafc539be6ab0ad68febe047c628d8f3e3b06`.
Both scene logs at `build/five-floor/scene/` have SHA-256
`a432dc28452c60ef0a5e245c8545cddb3f39d3edfcc9926c60bdb78fc41ae42b`.

## Remaining Gate

This source predates the latest recording and hostile performance changes.
Its completed route proves the retained native victory path, not certification
of the current combined revision. The complete 750-case native matrix, exact
committed-source validation and line coverage, sustained/rendered performance,
final exports and finished UI/input matrix remain outstanding. All must pass
before only external human playtesting remains.

## Current Source Revalidation And Audio Retirement Fix

The imported frozen checkout `build/retained-checkout/native-matrix-resume-pilot-f5d6833`
was re-run with fresh output and user-data directories at
`build/five-floor-f5d6833-revalidation-20261006-v2/`. Its exact source revision
was `f5d6833cec91114bb7909bcb59c93ac8450b3bb9`; all 412 `scripts/` and
`autoload/` runtime files were unchanged, with sorted path/digest aggregate
`1056f5c80d20c5b663f8f38f4f3372ab09398c5d3d906d22ecc5da2c44c0f5e4`.

The frozen run reached the complete route and wrote the same report as the
earlier gate: `complete: true`, 21 rooms, 12,153 accepted frames, all five
Bosses in authored order, `shattered_freedom`, and
`physical_settlement_verified: true`. Its report SHA-256 is
`a744f898fbf147a0f0a6b339175eafc539be6ab0ad68febe047c628d8f3e3b06`.
The settlement remains sequence 1, terminal reason `victory`, 235 shards,
10 imprints, digest
`5a0193f187c0b8662d8f414e481d1b9a8f746ce997dbc8edad17b52afbdd1686`.

The frozen scene did not pass its final cleanup assertion. The report was
complete, but `_dispose_main()` retained two active music playback WeakRefs
after its 20 fixed-FPS `0.01` timers, so `TestSuite.finish()` emitted the
failure `full actual Main run releases independent music playback before process
exit`. Both fresh logs are byte-identical, SHA-256
`56ae212d64858770d5f25c6f2fa19277d12a57b774b38c200a6b10fc02a25fe9`, and the
strict paired validator rejects the run. This is a test-clock cleanup failure,
not a successful current-source gate.

Focused RED reproduced the same condition in
`tests/presentation/music_playback_retirement_test.tscn`: fixed-FPS scene time
advanced 4,035 microseconds while two playback objects remained live and the
process leaked an ObjectDB instance. RED logs are retained under
`build/music-retirement-red-20261006/` and fail strict paired validation.

Commit `a4bdefd436456cfafa4773abffa80955183f7625` adds
`tests/support/audio_playback_retirement.gd`, a bounded monotonic wall-time
drain that yields `SceneTree.process_frame` and never blocks the audio mixer.
The focused fixture also proves a still-owned reference times out at its real
wall deadline. The original music lifecycle test and the five-floor cleanup
assertion now use this helper; no runtime music source is changed.

On the post-fix current worktree, the focused retirement fixture, the original
music lifecycle scene and the five-floor scene all pass with strict paired logs.
The five-floor result again records 21 rooms, 12,153 frames, five Bosses,
`shattered_freedom` and physical settlement reload. Its stdout and engine logs
are byte-identical with SHA-256
`a432dc28452c60ef0a5e245c8545cddb3f39d3edfcc9926c60bdb78fc41ae42b`.
The post-fix source runtime aggregate remains
`6846893e8df57abdf8deb168fd001e2843668e4218d93698fea6c815d740808d`.

This post-fix run is a focused current-worktree revalidation. A clean full
five-floor gate must be rerun from the committed source after the remaining
working-tree changes are frozen; it does not close the 750-case matrix,
coverage, performance, UI, export or human-playtest gates.
