# Parallel Gameplay Verification Evidence

- Status: Active / Focused evidence retained
- Document Role: Current parallel gameplay verification and rendered measurement record
- Authority Level: Below the approved gameplay-first completion plan
- Applies To: Frozen source gates, native recording, late Boss rendering and remaining UI sequencing
- Owner: Project integration lead
- Depends On: [Gameplay completion plan](../superpowers/plans/2026-10-06-gameplay-ui-product-completion.md), [Native performance probe](../superpowers/specs/2026-10-05-native-performance-probe-design.md)
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: Focused collection only; full gameplay, performance, UI and human gates remain open

## Parallel Ownership

The current session uses the integration lead plus three workers. The workers
own resumable native matrix execution, complete Player replay safety traversal and
fresh-source gameplay verification. Runtime and scene authority remain with
their existing owners. Shared UI assets, Theme and Main assembly remain with
the integration lead when the gameplay milestone passes.

The former `abd5b6f` matrix has no final producer or aggregate report. Its
five shard logs contain 517 completed case markers, no observed case failure,
and an unfinished next case in each shard. A completed log marker does not
substitute for the full physical case report, so this run does not pass the
750-case gate. The cause of its abrupt termination is not retained.

The former `9738bc5` clean certification has now terminated. Its ordinary
suite passed 510/510 scenes; the instrumented suite passed 508/510, with no
scene timeout. The two failures are `native_run_replay_backpressure_test` and
`reward_system_smoke`, both repaired in later source. No complete collected
line-coverage report exists for that failed suite. Its old execution record
has been updated to failed rather than left running. Neither older checkout
certifies current source.

## Rendered Late Boss Measurement

The fresh retained checkout is
`build/retained-checkout/current-native-pilot-ea35dc7-20261006`, bound to
`ea35dc7f907370ddb68fe0d0659ba6b9be06f381`. It contains 412 uninstrumented
runtime scripts with aggregate SHA-256
`58d3daa2df54064e5e2aa9122d13f4317c61cb9dca3af1d090c1d1d541092e97`.
After bootstrap import and a strictly clean second import, the lead ran:

```sh
python3 -u tools/p15/native_performance_probe.py \
  --output build/current-late-boss-rendered-120/report.json \
  --frames 120 --hub-frames 12 --boss-floor 4 --phase 2 \
  --real-time --rendered --timeout 1800
```

This is a source-project debug build using the actual macOS Metal Forward+
renderer selected by the current project, not a release package or the
Compatibility renderer proposed for the future UI work. The native clock is
60 Hz, time scale 1.0, and wall acceleration is false. The prerequisite route
and survival fixture remain explicit. This is neither unassisted victory nor
human playtesting. A separate headless five-floor gate and focused scene
checks ran on the same machine, so this measurement is not an isolated
before/after performance comparison.

Main visits all nine Hub functions, enters floor 4's actual Boss node, and
reaches phase index 2 through 2501 production Sword frames. All 120 measured
frames are accepted uniquely, from frame 2502 through 2621. The physical
recording has 121 observations, status `INTERRUPTED`, no failure, and byte-exact
first/last readback from a fresh store. Bootstrap, stdout, report and RSS all
bind Godot PID 93443. The process exits zero, the executable and runtime source
remain stable, and both runtime logs pass the strict validator.

| Actual metric | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Player advancement, including automatic recording | 35.543 ms | 37.865 ms | 121.124 ms |
| Same-frame Player and Host work | 36.780 ms | 39.703 ms | 122.041 ms |
| Same-frame wall interval | 44.590 ms | 48.718 ms | 129.691 ms |
| Render wait | 2.290 ms | 2.501 ms | 15.563 ms |

The measured 2 native seconds take 5.350893 wall seconds. Physical retention
takes 8.683889 seconds separately. Sampled RSS peaks at 1,676,312,576 bytes,
with 1147 valid samples and one retained unavailable terminal sample. Godot's
distinct static-allocation peak is 592,111,779 bytes. The observed measured
load has one actor and one threat, and zero projectiles, summons, constructs
or zones; this does not demonstrate saturation. RSS includes admission and
retention in its declared process scope.

Artifacts are beneath the checkout's `build/current-late-boss-rendered-120/`:

- Report SHA-256: `156b8e372e8a3d095fac877c182ea77e2e244196e67c1556d81d2532482f6bc7`.
- Source-manifest SHA-256: `0d7f60fa7d57daef7ee99718d0ac903045173eca74aef90be51753baed4c1831`.
- First observation SHA-256: `1652e536e3b8aa5750ddd2c79a57992e7bda4e682b5c9115b5758c561e51c61d`.
- Last observation SHA-256: `7e766c230024eb77f6579eeb0f8cf4f084dd8df7af05fdb34d0c23943f5ada7f`.

The wall p95 remains well above the 16.667 ms frame budget. A successful
collection report is not a 60-FPS certificate. This short sample cannot pass
45-minute recording, bounded sustained memory, release performance or full
rendered load. Desktop screenshot inspection was unavailable because the Mac
was locked; rendering execution is not visual UI acceptance.

## Remaining Gates

The same frozen `ea35dc7` source now passes three focused gates, recorded in
`build/current-ea35dc7-minimal-gates-execution.json`, SHA-256
`57976f4f0f3ca87c898634081e2c62f907804bd03d8e9500c1aeba8fac9eda50`.
Both retained checkouts remain clean at the same source after execution.

| Focused gate | Actual result | Scope limit |
| --- | --- | --- |
| Main five-floor ordinary production input | 21 rooms, 12,153 frames, 165 damage observations, all five Boss receipts in authored order, ending `shattered_freedom`, credits and fresh physical settlement pass | Declared survival invulnerability; not unassisted or human victory |
| Native canonical case 0 | Wanderer, Sword, Stop+Rewind, Ruin King; 797 frames; 1/1 with no error | Full 750 matrix remains incomplete |
| Bow time interaction instrumented coverage | 1/1 scene; all 412 original script hashes match the provider manifest; 8627/89272 executable lines hit | 9.6637% is this single-scene sanity only, not full-suite coverage |

The five-floor report has SHA-256
`a744f898fbf147a0f0a6b339175eafc539be6ab0ad68febe047c628d8f3e3b06`.
Its physical Profile envelope has SHA-256
`8b119d17a2cf3e1464f279686cd7e3d48e869483be365d4ea69f863f9828ff5b`;
an independent read verifies victories and finished runs equal 1, an empty
active launch receipt, the exact last settlement, final heart fragment and
saved ending/credits. Every focused scene passes paired strict logs.

The native pilot report has SHA-256
`a276df4377eb4a775b2184f1ab3f3b4aa7fbca46f9440b050414431f7af2141d`.
The coverage sanity retained its source hashes, executed line sets and a
normalized report; two scripts have no executable statements and are not
fabricated as uncovered code. Initial launches before clean import, and one
unsupported CLI flag invocation, remain explicitly excluded setup failures.

New replay and matrix implementation work is outside this frozen source and
requires its own focused regressions and later combined certification.
The full 750 native cases, current-source full line coverage,
sustained recording/load, finished UI, final exports and authentic human
playtesting remain open. This milestone does not open UI implementation.
