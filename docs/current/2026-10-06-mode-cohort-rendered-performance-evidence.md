# Mode Cohort Rendered Performance Evidence

- Status: Measured / 60 FPS and soak gates open
- Document Role: Current frozen production Main later-phase frame-cost evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Fifth-floor Void Boss phase two and nine-function Hub
- Owner: Plane Walker performance lane
- Depends On: `2026-10-06-void-checkpoint-projection-evidence.md`; `2026-10-06-mode-product-ui-finish-evidence.md`
- Last Verified: 2026-10-06

## Exact Executed Cohort

An independent `git clone --no-local --no-checkout` is retained at
`build/retained-checkout/mode-product-bb7d419-20261006/`, then detached at
`bb7d4199b2f7c07044bad7a1370a41a24313d912`. Its 425 physical runtime GDScript
files have aggregate SHA-256
`81851ecfb09ec569bf6b5991a817f31f7032009f956f567025d9db9e3a8680d8`.
The clone has a clean tracked worktree. The probe explicitly strips coverage
environment variables and declares `instrumented: false`.

This aggregate contains the current gameplay and visual cohort, including
`1e8144f` Void immutable history and the graphical run/mode interfaces. It is
not an isolated before/after measurement of that one optimization. The actual
executed manifest, rather than the source checkout's earlier name or a
microbenchmark, defines its scope.

The native executable is Godot 4.6.1 debug at
`/Applications/Godot.app/Contents/MacOS/Godot`, SHA-256
`ad304ee206ac9a0ab8407365e767ec33fe78d9455ff9dcace207c053e2651667`.
Its log identifies Metal 4.0, Forward+, Apple M4 Pro (Apple9). This renderer is
different from the OpenGL Compatibility UI captures; their costs are not
combined or treated as a same-renderer comparison.

The first clean editor import reports missing generated translation resources
before importing their CSV sources. That initial import diagnostic is retained
beside the clone. The actual subsequent probe logs contain no resource/script
errors, and their strict paired validation passes. Initial import messages are
not relabeled as a clean import or included in runtime certification.

## Actual Runtime Measurement

The exact command inside the frozen clone is:

```sh
python3 tools/p15/native_performance_probe.py \
  --output build/floor4-phase2-rendered-realtime-120/report.json \
  --frames 120 --hub-frames 120 --boss-floor 4 --phase 2 \
  --real-time --rendered --timeout 900
```

Other agents' Godot jobs stop at scene boundaries for this window; their
current children finish before measurement. Their suites resume afterwards.
No unrelated system process is paused. The production probe first visits all
nine actual Hub functions, then its declared prerequisite route and survival
fixtures use actual Player inputs to reach Void phase two after 2,501 native
frames. The requested sample is 120 consecutive accepted frames 2,502-2,621.

| Metric | Mean ms | p95 ms | Maximum ms |
| --- | ---: | ---: | ---: |
| Actual Player advance | 33.316 | 36.637 | 47.360 |
| Same-frame work | 35.866 | 44.917 | 50.299 |
| Same-frame wall | 43.661 | 53.016 | 66.947 |

Native duration is 2,000 ms; measured wall duration is 5,239,457 us. The
scheduler remains 60 native Hz, 60 physics ticks per second, time scale 1.0,
and `wall_accelerated: false`. Peak observed concurrency in this bounded
sample is one Actor and one threat, with zero zones, projectiles, constructs,
or summons. It does not certify a later peak-density workload.

The actual Godot process PID 71888 is bound by the bootstrap file, exactly one
stdout announcement, and the RSS sampler. It retains 1,195 valid RSS samples
and one unavailable sample. Peak process RSS is 1,642,823,680 bytes; the
debug-only `Performance.MEMORY_STATIC` peak is 617,949,655 bytes. These are
distinct allocation observations. The 120 Hub wait samples have mean
8.225 ms and p95 16.459 ms, including scheduler/render wait, with 4,014,753 us
wall duration across the actual Hub visit and wait procedure.

## Physical Evidence and Limits

The v3 report and independent `source-manifest.json` are retained under
`build/floor4-phase2-rendered-realtime-120/` inside the clone. Report SHA-256 is
`ba788e1bbf0bd4666c1e19ba4ca241644bba42ee071918ef174e56fbd32f9da4`;
manifest SHA-256 is
`73aa8374382f157b4a782cce981d4cf4175e7dbb23bcceefd56cd2ce87d26ee1`.
The automatic probe and a separate strict paired stdout/engine-log validation
both pass, with stable source and executable hashes, exit zero, no failures,
and no engine object leaks.

The physically reloaded recording contains 121 tape observations and exactly
120 sample frames. It remains `INTERRUPTED`; both physical endpoints match.
First sample SHA-256 is
`9fc362c561c49b17f1ff4c4829cc8435f5645d6d8dff1b3efc4d8b2c48fedb5e`;
last sample SHA-256 is
`5ed1cdd3312c4933e01bfb261abcb31ad90c71413d9a4851b4058d9270101b9d`.
Content aggregate is
`39a346d5367c10553562fe08b6b8871457e7a5e3d7b4c176841827e89aa5edb6`.

The observed Player and complete frame costs exceed the 16.667 ms frame
budget. This is not sustained 60 FPS, a 45-minute soak, an unassisted victory,
or human playtesting. Earlier 600-frame rendered cohorts differ in source,
recording endpoints, and observed peak concurrency, so these values do not
establish a directly attributable speedup over them. The single warm-query
microbenchmark in the dependent document also does not establish a total-frame
improvement. Performance work and final product certification remain open.
