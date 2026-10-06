# Rendered Native Performance Evidence

- Status: Focused Verified / Frame budget remains open
- Document Role: Current real-time rendered Main measurement evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Native Main Boss performance and strict launcher log validation
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-semantic-frame-observation-evidence.md`
- Last Verified: 2026-10-06
- Certification Status: No 60 FPS, sustained recording, full matrix or human certification

## Frozen Rendered Run

The imported detached checkout at
`build/retained-checkout/native-matrix-resume-pilot-f5d6833/` executes revision
`f5d6833cec91114bb7909bcb59c93ac8450b3bb9`. Its uninstrumented Main probe uses
real-time wall pacing, actual rendering, 60 Hz native scheduling and a named
survival fixture. The report is
`build/current-late-boss-rendered-120/report.json` inside that checkout.

All 120 requested frames are accepted. Physical first/last reads are byte-exact,
the tape contains 121 observations and the retained recording status is
`INTERRUPTED`, with empty failure. The process exits zero; runtime files and
the official Godot binary remain unchanged. The source aggregate is
`1056f5c80d20c5b663f8f38f4f3372ab09398c5d3d906d22ecc5da2c44c0f5e4`.

| Metric | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Player advance | 33.147 ms | 36.399 ms | 110.335 ms |
| Same-frame work | 34.328 ms | 38.584 ms | 111.182 ms |
| Frame wall | 41.792 ms | 45.935 ms | 118.262 ms |

Actual process RSS peaks at 1,624,358,912 bytes from 1061 valid samples; one
unavailable terminal sample remains recorded. These costs exceed the 16.667 ms
60 Hz budget. Report status `pass` means the probe's measurement/evidence
contract passed, not an FPS certificate. The report explicitly retains
`fps_certified=false`, `human_playtests=0` and `unassisted_victory=false`.

## Strict Paired Logs

Commit `dc2baeb` makes the launcher require both stdout and engine log paths as
regular, non-symlink files and routes them through the shared strict runtime
validator. Missing logs, resource/page leaks, redirection and invalid UTF-8
cannot retain an outer passing report. The native verdict remains separately
available as `native_status`; the manifest records the failed execution.

The retained frozen run passes the current report validator and strict paired
log validator. Artifact SHA-256 values are:

- Report: `9566de2af0fb2ad55632de4c371899a0ec5af33dc0947a144ab2af89459f0bca`.
- Source manifest: `493b7494b85c50fde792d3ffdae67b249c170b750c7908bdc74f24bfcbfc217b`.
- Both stdout and Godot log: `e462455c0beed8f73ec0f8e44d8c284e2870fba58dd2a0e7c5a990f97b41a955`.

This bounded source-project run establishes rendered evidence and an unresolved
frame budget. It does not replace whole-game, worst-case occupancy, 45-minute
recording, final clean-checkout or Shenzhen player-test gates.
