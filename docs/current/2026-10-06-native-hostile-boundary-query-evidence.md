# Native Hostile Boundary Query Evidence

- Status: Implemented / Current
- Document Role: Current focused native boundary verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Hostile Bridge run identity, frame clock and terminal observations
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-hostile-boundary-query-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Verified Boundary

Boss run identity queries read the current domain identity. Actor boundary
queries return a new three-field dictionary with current run identity, runtime
frame and terminal state. Other runtimes take one original full snapshot;
foreign actors without the native API keep the Bridge full-snapshot fallback.
Only Bridge scalar observation sites use the projection. Complete frame-start
transaction compensation, full rollback validation, physical geometry, health
publication and receipt authority remain in place.

The fallback preserves the raw frame Variant for the original summon-roster
comparison. Query output is detached, and no stored readiness certificate or
caller-controlled current-state cache is introduced. Independent read-only
review of all three production diffs found no actionable issue.

## Focused Contracts

`build/native-hostile-boundary-red` retains exactly one missing-native-API
assertion, without parse/script failures or leaks. Final GREEN in
`build/native-hostile-boundary-green` exercises the five authored Boss scenes
using counted real runtimes. Configuration, readiness and retirement take zero
complete Boss snapshots. Frame start retains exactly one full compensation
checkpoint. Actual frame advance refuses stale readiness, historical rollback
restores every complete typed Actor field, terminal mutation preserves
retirement, changed live run identity refuses foreign readiness, and authentic
state safely retries. Mutation of public query output cannot change domain
state. The ordinary enemy test retains exactly one original complete domain
snapshot when native query APIs are absent.

All 44 focused scenes pass:

| Contract | Retained Logs | Scenes |
| --- | --- | --- |
| Native boundary observation | `build/native-hostile-boundary-green` | 1 |
| Native hostile Bridge | `build/native-hostile-boundary-bridge` | 1 |
| Actor transaction and rollback | `build/native-hostile-boundary-transaction` | 1 |
| Actual Void Player frame | `build/native-hostile-boundary-void-frame` | 1 |
| Actual Boss actor | `build/native-hostile-boundary-boss-actor` | 1 |
| Enemy unit contracts | `build/native-hostile-boundary-enemies` | 39 |

Every paired stdout/Godot log passes the strict scoped runtime validator.
Bridge declares four exact expected synchronous refusal operations; Void
Player frame declares one. Each scope has the exact error message and count,
returns false, and completes in both logs. There are no unexpected runtime
errors, warnings, script/parse failures or object/RID leaks. Godot is
`4.6.1.stable.official.14d19694e`; line coverage is unsupported. Documentation
governance and diff whitespace checks pass.

## Isolated Complete-Frame Comparison

The clean `54866d4` archive at
`build/retained-checkout/native-hostile-boundary-overlay-54866d4-20261006`
contains the previous `a7bddd0` Boss actor and exactly the three boundary
production paths from `c17451f0a6f5aa9803223a52521f2d39aeda1391`. It retains the
same original uninstrumented probe harness. Its second verified editor import
passes strict paired logs. The 410-script aggregate SHA-256 is
`652af5b567eaf95ea92afef84ea58015260fc22b6811ac3487f2288f0a53f8bd`.

`build/floor4-phase2-boundary-query-after-120/report.json` passes with the
identical 120-frame, 12-Hub-frame, floor-index-4, phase-index-2, fixed-60-Hz,
unit-time-scale, headless arguments. Admission remains 2,501 real native Sword
frames. All measured frames 2,502 through 2,621 pass; the physical tape has 121
observations, is `INTERRUPTED`, has no recording failure, and freshly reads
first/last exact typed bytes. Both observation hashes and all 24 physical
compressed chunk filenames and SHA-256 bytes equal the previous query-slice
archive. Authoritative content is identical. Runtime stdout and Godot logs are
strictly clean.

Mechanically generated `source-manifest.json` and `comparison.json` sit beside
the report. The source comparison changes only `hostile_frame_bridge.gd`,
`launch_boss_runtime.gd` and `launch_hostile_actor.gd`. The original harness
checks that runtime source remains unchanged through execution.

| Complete Player Advance | Mean | p95 | Maximum |
| --- | --- | --- | --- |
| Previous query/preview slice | 52.909 ms | 62.117 ms | 84.364 ms |
| Boundary observation slice | 55.753 ms | 59.782 ms | 86.202 ms |

Mean increases by 2.844 ms (5.37%); p95 decreases by 2.335 ms and maximum
increases by 1.838 ms. Wall duration is 7.786 seconds, retention 15.866 seconds,
and peak native static allocation 593,596,713 bytes. Native static allocation
is not process RSS. Five frozen long-running smoke matrix processes and shorter
focused regressions are concurrently active during this after run; the previous
run had two long-running validation processes. Ambient load is not controlled.
This single comparison establishes exact behavior retention and does not
establish a mean or sustained speedup.

The integrated source still requires a separate 600-frame throughput gate,
rendered performance, 45-minute soak and human playtest. No content, gameplay
value, admission budget or recorder capacity changes.
