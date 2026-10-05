# Native Hostile Cache Retention Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: HostileActionCoordinator, LaunchSummonAuthority and EnemySpatialRuntime
- Owner: Gameplay performance lane
- Depends On: `docs/superpowers/specs/2026-10-05-native-performance-probe-design.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: Cache contracts and focused native regressions passed; whole-game performance pending

## Delivered Behavior

The summon and spatial runtimes retain at most four fully accepted catalog
projections, keyed by the complete current raw JSON bytes. The action coordinator
retains at most four fully accepted configurations, keyed by typed bytes for the
complete authored definition and initial identity. All three caches synchronize
shared access with a Mutex, store detached native typed bytes and decode fresh
instance dictionaries. Failed sources never populate the caches. Eviction is
bounded FIFO; no persistent gameplay state or file cache is introduced.

Changed inputs execute the complete existing cold parser. Integral JSON floats
still normalize to integer counters; fractional values, booleans and foreign
fields retain their cold refusal verdicts. Returned snapshots, normalized action
dictionaries, authored source dictionaries and one instance's catalog cannot
mutate another instance or a retained cache entry. Run/frame/pending admission,
active snapshot restoration, native ownership, receipts and rollback validation
continue through their existing validators.

## Verification

- Catalog missing-cache assertion RED: `build/native-hostile-catalog-cache-assertion-red` on base `c1a24d4d6dc59df976e6717c5f487bdc4428ad40`, with exactly the missing summon/spatial cache assertions. Its earlier runtime-error fixture log is not counted as meaningful RED.
- Action missing-cache assertion RED: `build/native-action-config-cache-red-20261006`, with authentic Boss parsing accepted and the required positive configuration cache absent.
- Catalog final GREEN: `build/native-hostile-catalog-cache-green-20261006`, including all three raw-source catalog keys, malformed and typed mutations, changed valid sources, instance isolation, pending admission, bounded eviction and five concurrent workers.
- Action/contract/coordinator final GREEN: `build/native-action-config-regression-final-20261006`, three scenes covering cold/warm complete verdicts and normalization, owner identity isolation, normalized definition/action mutation, active restore and typed geometry forgery, eviction and five concurrent workers.
- Spatial native/lifecycle/domain GREEN: `build/native-hostile-cache-spatial-20261006`, three scenes.
- Summon native admission/lifecycle/terminal roster/weapon input/domain GREEN: `build/native-hostile-cache-summon-20261006`, six scenes.
- Native cold checkpoint GREEN: `build/native-hostile-cache-checkpoint-20261006`, one scene.
- Launch Boss runtime GREEN: `build/native-hostile-cache-boss-20261006`, one scene.

All 15 final scene executions passed the repository's stdout plus Godot log
validator, including script errors and native object/RID leaks. Godot was
`4.6.1.stable.official.14d19694e`. The stock runner reports line coverage as
unsupported; these scene counts are not a coverage percentage.

The initial action test incorrectly expected integral floats to fail. The cold
parser already intentionally accepts these JSON numeric values, as covered by
the preexisting action contract test. The corrected cache test asserts complete
cold/warm result and state equality, and independently rejects fractional and
boolean values. That fixture correction is not claimed as a runtime bug fix.

## Native Measurements

Before checkout: `build/retained-checkout/catalog-cache-c1a24d4-before`.
After snapshot: `build/retained-checkout/cache-after-c1a24d4-20261006`.
Both derive from base `c1a24d4d6dc59df976e6717c5f487bdc4428ad40`.
An independent runtime file comparison found exactly these three changed `.gd`
sources across `scripts` and `autoload`: the summon authority, spatial runtime
and action coordinator. The after snapshot has no independent Git revision;
the report retains its complete runtime source fingerprint instead.

| Actual Main Boss Sample | Frames | Player Mean Before/After | Player p95 Before/After | Wall Duration Before/After |
| --- | --- | --- | --- | --- |
| Floor index 0 | 180 | 29.494 / 16.310 ms | 52.732 / 33.472 ms | 6.187 / 3.765 s |
| Floor index 2 | 600 | 49.035 / 35.111 ms | 86.602 / 65.046 ms | 33.743 / 25.637 s |

Floor 0 reports: before `build/catalog-before-20261006/report.json` within the
before checkout and after `build/cache-after-20261006-floor0/report.json` within
the after snapshot. Floor 2 reports: before
`build/cache-before-20261006-floor2/report.json` and after
`build/cache-after-20261006-floor2/report.json` in their respective snapshots.
Each wrapper scanned both logs, verified consecutive actual accepted Player
frames, finished the recording as INTERRUPTED, reopened the physical tape and
compared its first and last measured observations exactly.

For each pair the content fingerprint, encounter, observed peak counts, tape
sample count and first/last tape hashes were identical. Floor 0 observed one
actor, four constructs, two threats and one zone; Floor 2 observed one actor,
one projectile, two threats and one zone. These samples had no summons and do
not claim saturation. Native durations were 3 and 10 seconds, at 60 native Hz,
time scale 1.0. Fixed-fps wall acceleration, headless rendering, survival and
prerequisite route fixtures are explicit. Concurrent local work may influence
wall timings. Mean reduction was 44.7% and 28.4% for the combined change;
individual catalog/action contributions are not separately attributed.

The raw fresh import emitted missing generated translation errors before
creating resources. A second import and both subsequent native measurements
passed strict dual-log validation. This retains the repository's current
two-import procedure and does not certify a clean first-import log.

## Source Identity

- Before runtime aggregate: `2f7f63481648971db80d445586aecf4a4a5bc1326efd19568bee39952cc2ea20`.
- After runtime aggregate: `04b187eccc3781941a659cd0558867370d70ea547089ecfaa79cdab6ee30e51f`.
- EnemySpatialRuntime SHA-256: `f144e252d756676b2c4bc37be979b5d657ecf6fbecc262f367848afd14a9a1c9`.
- LaunchSummonAuthority SHA-256: `2bee46c569f1b8e327e94c6a42bde0da2fd17ac582d6f05f36d6a796f74c7dee`.
- HostileActionCoordinator SHA-256: `73b57cb7877234353b51adb3c9176a3b9b272e70935a1eb5dba256f65e3f8e7f`.

## Remaining Work And Recovery

This milestone does not certify 60 Hz, long sessions, the five-floor victory,
750 native Boss/loadout cases, rendered UI, clean line coverage, exports or
human playtesting. Floor 2 remains above the 16.67 ms frame budget. Repeated
full snapshot validation and arena reconstruction remain candidates for the
next measured optimization. More than four distinct action owner identities
can evict the configuration cache and reduce hit rate; eviction changes cost
only, since every miss runs complete cold validation.

Retain the focused local cache commit. Its parent is the rollback point; a local
revert of the three runtimes and two cache tests restores the prior parsing
cost after dependent performance work is accounted for. No remote push,
publication, account use or paid service was performed.
