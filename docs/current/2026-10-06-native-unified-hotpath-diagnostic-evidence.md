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
