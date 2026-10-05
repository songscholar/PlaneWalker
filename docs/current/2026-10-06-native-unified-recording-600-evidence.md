# Unified Native 600-Frame Recording Evidence

- Status: Recording Verified / Frame budget failed
- Document Role: Current retained actual late-phase sustained recording result
- Authority Level: Below approved full-product completion contract
- Applies To: Uninstrumented production Main recording and frame-budget evidence
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Depends On: `2026-10-06-replay-codec-immutable-reference-evidence.md`, `2026-10-06-native-hostile-frame-query-evidence.md`

The unchanged `bf00573` archive at
`build/retained-checkout/native-unified-bf00573-20261006/` runs the actual
production Main, Sword, fifth-floor Void phase two. Admission takes 2,501
actual Player frames. The following 600 consecutive frames, 2,502 through
3,101, all commit and record. The probe uses a declared survival fixture and
prerequisite-route fixture, headless fixed-fps scheduling, 60 Hz native frames
and unit time scale. It does not establish unassisted victory or human play.

`build/floor4-phase2-unified-late-600/report.json` within that archive is PASS
for its executable recording criteria. Its source manifest is unchanged before
and after execution, uninstrumented, exit 0, no timeout, and both actual runtime
logs pass strict error/leak validation. Aggregate runtime source SHA-256 is
`7c749a7c223100d56adfbbff3ee090c6b9186b7e36e1526273062df8bb73e869`.
Report SHA-256 is
`27a1987d262bbdcfb0b95fa97d2c050c637327d3ea4a1d598b5f6ae3ae445e51`.

The physical tape contains 601 observations including the initial observation.
It is honestly classified `INTERRUPTED`, with no recording failure. A fresh
physical read of both endpoints exactly matches their complete native typed
bytes. First observation SHA-256 is
`99ac84d00d33f0adcaa628441a2a97cbc9446ec9b31661db83cf60a4e798aca4`;
last is `8395465a716fa82d504a697824e46d4c1f662adbcf855c9bb4fe8c28dd3fa21f`.

| Actual Measurement | Result |
| --- | ---: |
| Player advance mean | 72.623 ms |
| Player advance p95 | 112.143 ms |
| Player advance maximum | 147.544 ms |
| Measured native duration | 10 seconds |
| Measured wall duration | 50.410 seconds |
| Retention duration | 11.019 seconds |
| Peak native static allocation | 700,758,286 bytes |
| Observed actors / threats / zones | 1 / 6 / 3 |

The earlier native capacity failure on `54866d4` is repaired in this bounded
600-frame scenario. The complete-frame 16.667 ms budget still fails. This run
does not certify 45-minute throughput, rendered FPS, peak entity loads or
memory limits. Later leaf and boundary changes require separate integrated
source measurements. UI polish is pending and human playtests remain 0/20.

## Leaf and Boundary Integrated Follow-Up

An unchanged `ee642a7` archive at
`build/retained-checkout/native-unified-ee642a7-20261006/` includes the leaf
and native-boundary repairs. Its actual fifth-floor phase-two probe admits
2,501 frames, then strictly passes all 600 measured frames with 601 durable
observations, an `INTERRUPTED` tape, no recording failure and fresh byte-exact
physical endpoints. Exit is zero, source is stable and uninstrumented, no
timeout occurs, and both runtime logs are strict clean. Runtime source aggregate
is `698bd708cfdb4c3820d38da6edee9e3cb7c3c3b1c72ed6b9f56e929745ce8da6`.
The report at `build/floor4-phase2-leaf-boundary-late-600/report.json` has SHA-256
`7d3cb4d6440ae66f9c33e2f7d96e57cb8c58319da9433df96a1d7142d87c85ff`.

Player mean/p95/maximum are 64.680 / 93.924 / 136.540 ms. Measured wall time
is 45.482 seconds, retention is 9.754 seconds and peak native static allocation
is 690,500,735 bytes. Observed concurrency remains 1 actor, 6 threats and
3 zones. This independently successful recording still fails the frame budget.
Ambient native matrix processes continue; these values are observations, not
an isolated portable performance guarantee.

Whole endpoint hashes differ from the original `bf00573` run. The authenticated
comparison at `build/native-leaf-boundary-comparison-20261006/` selects each
unique actual 601-observation tape, authenticates compressed/raw hashes, applies
the actual first delta and matches both reconstructed endpoints against each
report's measured hashes. At both endpoints, native/run/room/scene/publication/
intents/cosmetic_id subtrees are individually exact native typed bytes. All
54 differences are Player bookkeeping: action/world-payload revision offset
+108, and rewind sample sequences/history revision/next sample sequence offset
+18. The offsets remain constant through the measured interval. This is not
whole-observation byte equivalence; startup scheduling is under investigation.

The comparison's first attempt selected the earlier prerequisite tape and
failed; its logs remain intact and do not count toward success. Corrected and
then independently hash-authenticated attempts exit zero with clean paired
logs. Final report SHA-256 is
`5f16906e498a3d16ce4c80914cf97a74d87b1a9073c2d6d61e098cfc97536156`;
final diagnostic script SHA-256 is
`2f246442bb435ab83ff3930e1c21eef0e50b3dbcd124080e74e8de93c3ff9fbf`.

The first archive import reports the known missing generated CSV translation
derivatives; a second import completes with strict clean paired logs. An initial
import invocation using a nonexistent log parent crashes in Godot's logger
before project execution; creating the parent resolves it. These setup
attempts are not gameplay success evidence. Later geometry, historical-event
checkpoint and UI-query repairs still require integrated native measurements.
