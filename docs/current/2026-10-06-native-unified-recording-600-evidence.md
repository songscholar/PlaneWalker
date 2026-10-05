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
