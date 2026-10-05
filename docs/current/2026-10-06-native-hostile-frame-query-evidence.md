# Native Hostile Frame Query Evidence

- Status: Implemented / Current
- Document Role: Current focused verification and performance evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Native hostile frame queries and private Boss preparation previews
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-hostile-frame-query-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Verified Boundary

The three production paths add Boss-owned current-frame, terminal and detached
action queries, then use them at internal observation sites. Other hostile
runtimes retain their complete-snapshot fallback. Public complete snapshots
retain their schema and detached mutable descendants.

Each actual hostile retains at most one body and one arena preview. Exact
`var_to_bytes` configuration equality includes definition, identity, and the
Boss's actual arena origin and body position. Every use restores and validates
the complete requested snapshot before preparing a frame. Changed typed
configuration rebuilds or refuses. The previews never replace live actor state,
physical geometry checks, receipt authentication, or transaction rollback.

## Focused Contracts

The missing-query RED is retained in `build/native-hostile-frame-query-red`.
It produces the scoped missing-API assertion without script/parse errors or
object/RID leaks. Final GREEN is retained in
`build/native-hostile-frame-query-green-2` and exercises all five authored Bosses.
It checks current queries, detached action descendants, actual advance,
terminal mutation, historical rollback, preserved original cold-validator
verdicts, separate body/arena ownership, mandatory restore before preview reuse,
changed origin, typed configuration changes, invalid configuration refusal,
and safe retry.

The following strict scene runs pass without runtime errors, warnings, or leaks:

| Contract | Retained Logs |
| --- | --- |
| 39 enemy unit scenes | `build/native-hostile-frame-query-regressions` |
| Native hostile Bridge | `build/native-hostile-frame-query-bridge` |
| Actual Boss actor | `build/native-hostile-frame-query-native-actor` |
| Actor transaction and rollback | `build/native-hostile-frame-query-native-transaction` |
| Actual Void Player frame | `build/native-hostile-frame-query-void-frame` |
| Forest native auxiliary | `build/native-hostile-frame-query-forest-native` |
| Forge native arena | `build/native-hostile-frame-query-forge-native` |

Godot is `4.6.1.stable.official.14d19694e`. Line coverage is unsupported.
Documentation governance and diff whitespace checks pass. No dependency,
gameplay value, recorder buffer, or admission budget changes.

## Uninstrumented Comparison Baseline

The clean `54866d42fb0bf46e55f9afa4bb442595dab14c25` archive at
`build/retained-checkout/native-recording-after-54866d4-20261006` runs
`build/floor4-phase2-uninstrumented-baseline-120/report.json` without timing
instrumentation. Its runtime aggregate SHA-256 is
`468f88a7b2796fcb6a3ea1758a39ba9bf7018b34503812a35c39cf9b059cf160`.
Authoritative content aggregate SHA-256 is
`838c31095581b7abb79a63cb51b025d448c2ddd9d29b8ed75d2a318d8305bb2b`.

Real Sword admission reaches fifth-floor Void phase index 2 after 2,501 native
frames, then accepts all 120 requested frames 2,502 through 2,621. The physical
tape is `INTERRUPTED`, has 121 observations, no recording failure, and exact
fresh first/last typed-byte readbacks. Its first observation SHA-256 is
`99ac84d00d33f0adcaa628441a2a97cbc9446ec9b31661db83cf60a4e798aca4` and last is
`28a6598b75adc82640b0a850c5c326a2b8558f971c84d8d296ca5f45c0c11f79`.
Strict stdout and Godot logs pass.

| Complete Player Advance | Mean | p95 | Maximum |
| --- | --- | --- | --- |
| Uninstrumented baseline | 55.765 ms | 59.371 ms | 80.675 ms |

Native duration is 2 seconds, wall duration 7.682 seconds, physical retention
14.987 seconds, and peak Godot native static allocation 590,235,928 bytes.
Native static allocation is not process RSS. Other frozen long-running
five-floor validation processes remain concurrently active. This is a focused
headless timing baseline, not an uncontended 60 FPS or rendered performance gate.

## Isolated Complete-Frame Delta

Implementation commit `a7bddd07e68f1bca47e0190adc6fc533abb2f9bd` overlays exactly
the three production files onto the same `54866d4` base at
`build/retained-checkout/native-hostile-query-overlay-54866d4-20261006`.
The first editor import generates translation resources; the second verified
import passes strict logs. An independent read-only review finds no actionable
issue in current-state queries, preview isolation, mandatory restore, or exact
configuration binding.

`build/floor4-phase2-hostile-query-after-120/report.json` uses the same original
uninstrumented probe harness and arguments: 120 measured frames, 12 Hub frames,
floor index 4, phase index 2, fixed 60 Hz, unit time scale, and headless rendering.
The 410-script runtime aggregate SHA-256 is
`7a665bf7d52030d162e49393e2c294b42c157b3af0ca704ce2d289a5c7ddc4ba`.
Mechanically generated `source-manifest.json` files sit beside both reports.
Their file-level comparison changes only `launch_boss_actor.gd`,
`launch_boss_runtime.gd`, and `launch_hostile_actor.gd` under
`scripts/enemies/launch/`. Authoritative content is unchanged.

Admission is still exactly 2,501 native frames. All 120 measured frames
2,502 through 2,621 pass. Both complete first/last observation hashes and fresh
physical typed-byte readbacks equal the baseline. Both archives retain the same
24 compressed chunk filenames and SHA-256 bytes across admission and measured
tapes, with no physical chunk difference. The measured tape still has 121
observations, status `INTERRUPTED`, and no recording failure. Both runtime logs
pass strict error, warning, and leak scans.

| Complete Player Advance | Mean | p95 | Maximum |
| --- | --- | --- | --- |
| Uninstrumented baseline | 55.765 ms | 59.371 ms | 80.675 ms |
| Isolated query and preview slice | 52.909 ms | 62.117 ms | 84.364 ms |

This single ambient-load comparison reduces mean Player advance by 2.856 ms
(5.12%). The p95 and maximum increase; it does not establish improved tail
latency. Wall duration changes from 7.682 to 7.361 seconds, physical retention
from 14.987 to 15.146 seconds, and peak native static allocation from
590,235,928 to 592,161,271 bytes. Two other frozen long-running five-floor
processes are active at the after-probe start; one finishes in the surrounding
validation window. Ambient load is not held constant across this comparison.
These measurements do not certify uncontended, rendered, or sustained
performance.

## Remaining Measurement

The complete-frame mean remains above the 16.667 ms budget. Profile remaining
hotspots on the next unified committed source before another optimization.
Sustained recording still requires that source to pass the separate 600-frame
tape/readback gate; this 120-frame result cannot certify background throughput.

## Unified Main-Thread Diagnostic

A separate clean `abd5b6f` archive at
`build/retained-checkout/native-unified-hotpaths-abd5b6f-20261006` includes the
query slice and committed codec immutable-reference change. It reuses the
previous mechanical diagnostic wrapper generator and expands the outer cold
normalization/full verifier, Bridge helpers, preview, and physical geometry
labels. The timer records Replay safety at outer calls; safety recursion calls
its unchanged renamed implementation directly. Production source is untouched.
The generator wraps 152 methods and discloses the stale absent
`launch_encounter_frame_authority::publish` target. The second verified import
and two-worker nesting/retention self-check pass strict logs.

`build/floor4-phase2-unified-diagnostic-120/report.json` passes with 2,501
admission frames and all measured frames 2,502 through 2,621. The instrumented
410-script aggregate is
`82498137dc36ecca4aea83e5e5f81892d3f224d1f267cc1938ee7a1d8e938eb6`.
The corrected harness retains its complete source manifest, stable source flag,
clean runtime logs, zero exit code, and no timeout. Content, complete first/last
observation hashes, and fresh physical typed-byte readbacks still match the
uninstrumented comparison. The tape has 121 observations, is `INTERRUPTED`, and
has no recording failure.

Instrumented Player advance mean is 58.388 ms, p95 64.808 ms, maximum 95.308 ms.
Native duration is 2 seconds, wall duration 8.136 seconds, retention 22.661
seconds, and peak native static allocation 593,299,844 bytes. Ambient frozen
certification continues into different scenes. Added wrappers and concurrent
timer mutex costs make this a hotspot diagnostic, not a speedup or throughput
comparison.

| Main Measurement Method | Calls | Inclusive ms / Frame | Exclusive ms / Frame |
| --- | --- | --- | --- |
| Player advance | 120 | 58.382 | 0.789 |
| Bridge prepare | 120 | 32.088 | 1.407 |
| Boss actor prepare | 120 | 12.854 | 0.019 |
| Recorder observe | 120 | 12.603 | 0.095 |
| Native cold snapshot | 120 | 6.186 | 0.047 |
| Native cold full verifier | 120 | 5.715 | 0.498 |
| Native cold normalization | 120 | 0.346 | 0.346 |
| Full Player verifier | 120 | 4.622 | 0.176 |
| Outer Replay safety | 1,440 | 7.886 | 7.886 |
| Boss complete snapshot | 3,040 | 4.531 | 4.531 |
| Void auxiliary validation | 723 | 3.752 | 3.752 |
| Boss snapshot validation | 1,080 | 10.751 | 2.847 |
| Boss physical geometry | 1,200 | 2.847 | 2.792 |
| Boss validation context | 1,080 | 2.502 | 2.502 |
| Boss restore | 360 | 10.797 | 1.853 |
| Action configure | 1,099 | 1.683 | 1.683 |
| Body/arena preview | 240 | 9.249 | 0.249 |
| Boss preview configuration | 240 | 0.016 | 0.014 |

Inclusive rows overlap and must not be added. The tiny preview-key cost does
not justify more configuration-key work. Remaining work is concentrated in
safety traversal, repeated complete Boss/auxiliary projections and validation,
and physical geometry preparation. The recorder's worker calls outer Replay
safety 960,704 times across measurement and retention, so timer mutex overhead
also affects retention. No codec-throughput conclusion follows from this run.
