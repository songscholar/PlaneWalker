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
