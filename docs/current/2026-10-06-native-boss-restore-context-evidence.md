# Native Boss Restore Context Evidence

- Status: Implemented / Focused verified
- Document Role: Current Boss restore classification optimization and diagnostic attribution
- Authority Level: Below approved full-product completion contract
- Applies To: Complete Boss restore, current/historical Action classification
- Owner: Project integration lead
- Depends On: [Gameplay completion plan](../superpowers/plans/2026-10-06-gameplay-ui-product-completion.md)
- Last Verified: 2026-10-06
- Certification Status: No frame-budget, rendered, saturation, soak, UI or human certification

## Observed Cost And Design

The actual Main diagnostic at frozen native-enabled `f85c84d` accepts all
120 measured frames and observes 120 native preparations and zero public
preparations. Its report is retained at
`build/retained-checkout/native-enabled-hotpaths-f85c84d-20261006/build/floor4-phase2-native-enabled-diagnostic-120/report.json`,
SHA-256 `3455018600668fdc19bc055db168ec030c07b395b370c58f0d358f6870b5cdc8`.
Strict runtime logs, runtime source stability, actual PID/RSS binding and
physical typed recording endpoints pass. The diagnostic has timers and caller
edges, so its costs attribute work and cannot certify production performance.

Mean measured work is 45.289 ms and mean frame wall time is 53.972 ms;
work p95 is 62.533 ms and wall p95 is 75.180 ms. Recorder safety traversal
consumes 3.125 ms per measured frame. Boss configuration-context encoding
consumes approximately 3.045 ms per frame, Boss snapshot encoding 2.898 ms,
and Void auxiliary snapshot work 2.225 ms. Inclusive parent/child totals must
not be added to these exclusive costs.

Boss restore first performs its existing complete `can_restore_snapshot`
validation, then `_action_for_snapshot` constructs an independent current
Action and, when required, an independent historical candidate. The previous
legacy classification separately encoded the complete live configuration to
read a cached current-regime template digest. That current digest already
exists in the freshly configured current candidate.

The candidate selector now writes its current definition digest to a local
classification dictionary before trying current/historical restoration. Both
legacy flags compare against that digest. The selected historical Action's
digest is never used as the current classification authority. The selector's
ordering, independent mutable Action ownership, parent/auxiliary restore
checks, validation caches and external snapshot refusals remain exact.

## Executable RED And GREEN

The existing five-Boss legacy fixture now counts live validation-context
encodings as well as independent Action constructions. Valid RED is
`build/boss-legacy-digest-context-red`. It has exactly 56 assertion failures,
all reporting two context encodings where one is required, across current
and historical Void/Time restoration boundaries. Its stdout SHA-256 is
`ee5ab995ad72405c0f467fb078461326e9393cabe99d6a5ca8b75b30e3a7aa7c`.
No script, parse or leak failure explains RED.

GREEN is `build/boss-legacy-digest-context-green`, with stdout SHA-256
`31d2c6ce473319bd9b389b9f9af5ceb6eea678a637282aa49dd2fed1a3d69f60`.
Every warm and repeated restore encodes exactly one context. Current actions
still require one mutable candidate; historical actions require two. Exact
typed Boss/auxiliary bytes, legacy flags, next-frame outputs, independently
owned instances, rejection and reconfiguration scenarios pass.

| Regression | Retained directory | Result |
| --- | --- | --- |
| Complete five-Boss current/historical classification | `build/boss-legacy-digest-context-green` | Pass |
| Action validation templates | `build/boss_action_validation_template-boss-digest` | Pass |
| Complete Boss snapshot validation cache | `build/boss_snapshot_validation_cache-boss-digest` | Pass |
| Parent and auxiliary restore ownership | `build/boss_parent_restore-boss-digest` | Pass |
| Native combat physical checkpoint | `build/native_combat_checkpoint-boss-digest` | Pass |
| Actual Main native cold resume | `build/main_native_resume-boss-digest` | Pass |
| Native recording snapshot and refusals | `build/native_recording_snapshot-boss-digest` | Pass |

Each of the seven separate stdout/Godot pairs passes the strict runtime
validator with exact test-suite refusal scopes. Both modified scripts pass
the pinned GDScript AST parser; `git diff --check` passes. Independent agents
reviewed the current/historical digest equivalence and the physical RED/GREEN
logs without rerunning the measured workload. No correctness finding remains.
The three unchanged project requirements files also pass `pip-audit` with no
known vulnerabilities; the JSON receipt is
`build/boss-restore-context-dependency-audit.json`.

## Optimized Source Diagnostic

A new clean checkout is retained at
`build/retained-checkout/native-digest-hotpaths-e7e1a6d-20261006`, fixed to
`e7e1a6d635a0b1881a452e4a679e3c166c6689eb`. All 412 unmodified runtime
files match Git before instrumentation; their aggregate is
`58d3daa2df54064e5e2aa9122d13f4317c61cb9dca3af1d090c1d1d541092e97`.
The same diagnostic generator retains 245 wrappers and only its two expected
missing targets. Repeat transformation produces the identical instrumented
aggregate `8a704bed23977e35eacd0ad4f32e3968d708443123a23f78858ac192cd801bfc`.
The strict second import and two-worker nested timer self-check pass.
The initial self-check invocation selected an absent scene; its failed logs
remain retained and are excluded. The corrected invocation uses
`--script res://tools/p15/diagnostic_store_selfcheck.gd`.

The existing matrix and coverage process groups were temporarily stopped
without resetting their state, then resumed after the diagnostic. No timeout
was observed after resumption. This frees CPU for this short attribution run;
the earlier diagnostic had competing jobs, so the wall-time comparison does
not establish an isolated net optimization gain.

The new report under the clone's
`build/floor4-phase2-native-digest-diagnostic-120/` has SHA-256
`b510da87eb4b12f042b927500c537bccfe80a55c17fef0e96840213830b9b9b6`.
Its source-manifest SHA-256 is
`6231446863b4d2090f53539d6b78002a42566b1f1363019e7a865698be88d989`.
All 120 measured frames pass and all use native preparation; public count is
zero. Boss validation-context calls are 1080, compared to 1320 before this
change. The removed 240 calls are exactly two classification encodings per
measured frame. Recorder safety calls remain 1562 and Boss/auxiliary snapshot
counts remain unchanged.

| Instrumented metric | Previous diagnostic | Optimized diagnostic |
| --- | ---: | ---: |
| Mean actual same-frame work | 45.289 ms | 42.199 ms |
| Work p95 | 62.533 ms | 56.138 ms |
| Mean frame wall | 53.972 ms | 49.950 ms |
| Wall p95 | 75.180 ms | 64.735 ms |

The runtime/paired-log validator passes, the process exits zero, and source
and the official Godot executable stay unchanged. Bootstrap, final stdout,
report and sampled RSS all bind PID 80698. Actual RSS peak is 1,379,581,952
bytes with 1431 valid samples and one retained unavailable terminal sample.
Physical readback retains 121 observations, 120 measured samples, status
`INTERRUPTED` and empty failure. Complete first/last typed hashes remain
`8b7b8ab43674e54121d4568336b5ae14de29b4a9a522acc5c2743a64b83dfe11`
and `196d184f40a5185c08ba7cd115c7141374372fe997ae0c7a4bea3cfc9f9bae66`.
An independent fresh reader validates the physical profile envelope, stream
manifest and compressed chunks, then decodes the actual typed endpoints.
Its strict stdout/Godot pair passes. Sequence 1/frame 2502 and sequence
120/frame 2621 match the report; sequence/frame values remain `TYPE_INT` (2).
The tape id is
`6b5e8e566c117817485edd8ca0e62b2050e83be7eadd4f54cf7fb6f2796e89db`.
Reader and logs remain in the same diagnostic output directory under
`physical_endpoint_check.gd` and its paired logs. The reader SHA-256 is
`790c02c21dfa2d5c440f9d4eab2026594ebee0bbc8b570ba48e85a6e8ab7a0f2`.

## Remaining Work

A reduction in encoding calls is not itself a net wall-time or 60-FPS
certificate. Actual uninstrumented rendered performance, worst-case
occupancy, sustained RSS, the full 45-minute recording, final clean validation
and complete UI remain open. The previously started native matrix and
coverage lanes retain their older source identities and cannot certify this
change.
