# Native recorder observation on/off evidence

Date: 2026-10-06. This is a diagnostic comparison of the native performance probe. It is not an optimization claim, an FPS certificate, or a production behavior change.

## Scope and source identity

Both successful runs used the same detached diagnostic clone at:

`build/retained-checkout/native-recorder-compare-e1b0265-20261006`

The clone started from revision `e1b0265a51bfbdbb6634ea28ed384b5dda7af663` and ran the same real-time 60 Hz input, Boss floor 4 phase 2 encounter, Forward+ renderer, Metal driver, and 120-frame measurement after admission at Player frames 2502 through 2621. Both reports retain the same content aggregate fingerprint `39a346d5367c10553562fe08b6b8871457e7a5e3d7b4c176841827e89aa5edb6`, the same base pack fingerprint `c099e9be0d3e5d7ce4020012c08e1b0a9b63ae8c48f0156c570d5a23cd44163d`, and the same runtime source hash `8a4509a6420045548ef9fc7d771c79ebdb834951c7f0466243bf59f5cfe477c6`.

The diagnostic clone only adds an environment-gated switch that skips `NativeRunReplayRecorder` observation calls. It preserves recorder activation, tape identity, finish status, and gameplay state. These diagnostic edits were not applied to the production checkout.

## Results

| Measurement | Observation on | Observation off | Delta off vs on |
| --- | ---: | ---: | ---: |
| Player advance mean | 34,669.817 us | 31,602.233 us | -8.85% |
| Frame work mean | 37,386.958 us | 34,515.425 us | -7.68% |
| Frame wall mean | 45,378.183 us | 37,081.358 us | -18.28% |
| Observer mean | 5,524.575 us | 453.975 us | diagnostic branch difference |
| Peak RSS | 1,561,460,736 B | 707,280,896 B | -854,179,840 B |

Both runs accepted 120/120 frames and reported the same sample range, encounter, backend, content fingerprint, and native duration (2,000 ms). The on run retained 120 samples and 121 tape observations (start plus 120 frames), with exact first/last physical readback. The off run retained zero observations and no sample hashes, while still producing a valid `INTERRUPTED` tape manifest with no recorder failure. That zero-observation result is the intended diagnostic boundary; it must not be used as a production replay configuration.

## Artifacts and verification

On report:

`build/retained-checkout/native-recorder-compare-e1b0265-20261006/build/recorder-on-phase2-120/report.json`

Report SHA-256: `a18e97178135ca237b8c8287daa6807b8b1961ec533148257548de370ab708eb`

Source-manifest SHA-256: `a427d78408024e66af86e55e3e0f74f0580dd7e23448e7cd8f5d6acbaff1c114`

Paired stdout/Godot log SHA-256: `a41c1eff52452d2063000b7bba662538460fea2bc2754ae8ead386d92447f21a`

Off report:

`build/retained-checkout/native-recorder-compare-e1b0265-20261006/build/recorder-off-phase2-120/report.json`

Report SHA-256: `d899989438691b5ba85ab06562adf113cfa298af61502f486c43dd7797466671`

Source-manifest SHA-256: `d2be3864a26927ee913dc41b971d9d9994d19f190e5da28130b72d74aa259eda`

Paired stdout/Godot log SHA-256: `aa7a359208a4ee3c0893f3e075be1f7e4f7d44b5960c999af84f7278f72a1734`

Both paired log sets pass `tools/runtime_log_validation.py` and the native report validator. The differing source-manifest and report/log digests are expected because each run has a distinct output path, process identity, timing sample, and observation mode; the recorded runtime source and content fingerprints are identical.

## Retained failed boundary

An earlier diagnostic clone at `native-recorder-compare-9fd36ef-20261006` was based on stale source `9fd36ef184c79b29b0dc1eac5dd09fe0a6d8f3c3`. Its probe never produced a report: Godot failed during startup with `ContentRegistry._specialized_definition_parse_result` reporting `Invalid call. Nonexistent function 'new' in base 'GDScript'`, followed by the probe type error at `_run` line 54. That failure is retained as a stale-source diagnostic boundary and is unrelated to the successful current-head renderer comparison.
