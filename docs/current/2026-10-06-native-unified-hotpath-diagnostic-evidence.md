# Native Unified Hotpath Diagnostic Evidence

- Status: Verified / Current
- Document Role: Current frozen-source diagnostic attribution evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Main-thread and worker attribution in the actual floor-four phase-two native path
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-native-boss-ui-query-evidence.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: Diagnostic only; no FPS, rendered, soak, coverage or human certification

## Reproducible Source

The retained source archive is
`build/retained-checkout/native-unified-hotpaths-10a3e96-20261006`, frozen from
`10a3e965c55e29ba02c103c081fe785e32503c42`. Its production manifest is
`build/diagnostic-production-source-manifest.json` inside the archive. The
production runtime aggregate before instrumentation is
`1b12c8ca4d09490ba9aa58e692f4d0767531eedff87f74bd670daa74acf3dfe2`.
The mechanically instrumented runtime aggregate is
`662863c5f0ea10c8454e529476d2e30a98f5d36d7375291630d2f673e18af1a8`.

The archived generator `tools/p15/instrument_hotpaths.cjs` wraps 170 methods.
`build/diagnostic-wrapper-manifest.json` discloses two absent targets: the stale
frame-authority `publish` label and a nonexistent Void auxiliary
`_can_restore_snapshot_uncached`. Void auxiliary validation remains inline in
its measured public method. A second import and the two-worker nesting and
retention self-check pass strict runtime-log validation. The self-check JSON is
`build/diagnostic-store-selfcheck.json` inside the archive.

## Accepted Actual Frames

The report is archived at
`build/floor4-phase2-unified-diagnostic-120/report.json`. After 2,501 actual
Sword admission frames, all 120 measured frames from 2,502 through 2,621 pass.
The report has zero failures, stable runtime source, clean paired logs, process
exit zero and no timeout. Godot is `4.6.1.stable.official.14d19694e`.

The physical recording retains 121 tape observations, 120 samples,
`INTERRUPTED` status and no recording failure. Fresh physical first and last
snapshots match exactly. Their hashes are respectively
`99ac84d00d33f0adcaa628441a2a97cbc9446ec9b31661db83cf60a4e798aca4`
and `28a6598b75adc82640b0a850c5c326a2b8558f971c84d8d296ca5f45c0c11f79`,
matching earlier 120-frame endpoint evidence. This endpoint comparison does
not certify every archived byte of a separate run.

Measured Player advance mean/p95/maximum are 48.937/53.159/82.572 ms. Measured
wall time is 6.936 seconds; physical retention takes 20.206 seconds. Peak native
static allocation is 593,826,286 bytes. The survival fixture and prerequisite
route fixture remain disclosed. Hub waits are 12 frames in this frozen source;
the later production Player lifecycle fix is outside this diagnostic.

## Attribution

All costs below are milliseconds per measured main-thread frame. Inclusive
costs overlap; summing them would double-count nested work.

| Method | Calls | Inclusive | Exclusive |
| --- | ---: | ---: | ---: |
| Bridge prepare | 120 | 30.522 | 1.404 |
| Boss Actor prepare | 120 | 12.056 | 0.017 |
| Recorder observe | 120 | 6.936 | 0.087 |
| Native cold verifier | 120 | 3.211 | 0.428 |
| Void auxiliary complete snapshot | 3,179 | 4.120 | 4.120 |
| Boss restore validation | 1,080 | 10.497 | 2.940 |
| Replay safety | 1,562 | 2.927 | 2.927 |
| Void auxiliary validation | 723 | 3.414 | 2.576 |
| Boss validation context | 1,080 | 2.490 | 2.490 |
| Action configure | 1,099 | 1.712 | 1.712 |
| Boss complete snapshot | 2,660 | 4.136 | 0.399 |
| Boss physical geometry | 1,200 | 0.902 | 0.570 |

The Boss UI endpoint takes 20 calls and 0.059 inclusive ms per frame; its input
query takes 0.0025 ms per frame. Geometry and pickup wrappers each take 1,441
calls at approximately 0.15 inclusive ms per frame. Event-checkpoint lookup
takes 122 calls and 0.280 ms per frame.

## Limits

Timer and mutex instrumentation adds work and can change worker scheduling.
These numbers guide the next focused implementation; they do not establish a
throughput improvement or 60 FPS. The frozen source is stable, but a later
production milestone must repeat uninstrumented native and rendered gates.
Sustained throughput, the 45-minute soak, visual UI acceptance and human
playtesting remain open.

## Latest Integrated Attribution

The clean detached source `26a5d98129461b19ed87e40fdb837224bcc47441` is retained
at `build/retained-checkout/native-unified-hotpaths-26a5d98-20261006/`.
Before instrumentation, its 410 runtime scripts have aggregate
`122604a98b824db92cb5078616f1b231715a139cdd6758ac06a0a6ec9b4070cd`.
The copied mechanical generator adds Actor ticket, current-state comparison,
control/arena projection, Action template, rewind and physical replay-read
labels. It supports the current one-level constructor defaults in signatures
and correctly names the encounter publication methods. It wraps 191 methods;
the sole absent target is Void auxiliary `_can_restore_snapshot_uncached`,
whose real validation remains inline in the measured public method.
Generator SHA-256 is
`d928073c8ec01c38be53409e71214ae31887543daa7362f148abc0318bda79da`.
The unchanged per-thread timer has SHA-256
`676676f8102949f5cb3fa21e0a500543db083bc06d7c1cb2507866a569f0f312`.
The second import and actual two-worker self-check pass strict paired logs.

The report at `build/floor4-phase2-latest-diagnostic-120/report.json` has
SHA-256 `11b1e2248ea20bf2b30933978e8594b1eb25a167fb583eca4deab20b046fe737`.
Its instrumented runtime aggregate is
`deaf61c10953296f5889632c14f54a8fd1e7cf249a9ac168e5226906baedb099`.
Actual Sword admission remains 2,501 frames; all 120 measured frames from
2,502 through 2,621 accept. Both final runtime logs are strict clean, source
is stable, exit is zero and there is no timeout. The physical tape retains
121 observations, `INTERRUPTED` status, no recording failure and fresh exact
typed endpoint reads. The first hash is
`8b7b8ab43674e54121d4568336b5ae14de29b4a9a522acc5c2743a64b83dfe11`;
the last is `196d184f40a5185c08ba7cd115c7141374372fe997ae0c7a4bea3cfc9f9bae66`.
This is not a full tape comparison or unassisted victory.

| Main Measurement Method | Calls | Inclusive ms / Frame | Exclusive ms / Frame |
| --- | ---: | ---: | ---: |
| Player advance | 120 | 43.776 | 0.717 |
| Bridge prepare | 120 | 27.343 | 1.366 |
| Boss Actor prepare | 120 | 10.896 | 0.016 |
| Boss complete restore | 360 | 9.752 | 1.801 |
| Boss snapshot validation | 1,080 | 9.317 | 2.793 |
| Boss validation context | 1,080 | 2.399 | 2.399 |
| Actor private body/arena preview | 240 | 8.162 | 0.239 |
| Void auxiliary complete snapshot | 1,595 | 2.076 | 2.076 |
| Void auxiliary validation | 723 | 3.309 | 2.482 |
| Actor base prepare | 120 | 5.320 | 1.281 |
| Actor complete ticket match | 480 | 0.627 | 0.627 |
| Recorder observe | 120 | 6.322 | 0.082 |
| Outer Replay safety | 1,562 | 2.931 | 2.931 |

Player mean/p95/maximum are 43.782 / 49.495 / 74.209 ms; same-frame work is
45.138 / 50.483 / 75.797 ms and same-frame wall is
52.358 / 57.555 / 87.531 ms. Measured wall duration is 6.283 seconds for two
native seconds; retention takes 19.729 seconds. Sampled macOS process RSS is
1,385,070,592 bytes across admission and retention, with 1,546 valid samples
and one unavailable sample. The headless measured peak load is one actor,
one threat and zero zones. Concurrent native matrix/certification processes
and instrumentation remain explicit. These values guide narrow fixes; they
certify neither an optimization speedup nor the frame, saturation, sustained,
rendered, memory, UI or human gates. The independent uninstrumented 600-frame
follow-up is retained in the linked [unified recording evidence](2026-10-06-native-unified-recording-600-evidence.md);
its complete-frame budget still fails.
