# Projectile Scalar Distance Evidence

- Status: Implemented / Current
- Document Role: Current focused implementation and verification evidence
- Authority Level: Below approved full-product completion contract
- Applies To: LaunchHostilePayloadRuntime and its native projection
- Owner: Gameplay performance lane
- Depends On: `docs/current/2026-10-06-projectile-scalar-distance-plan.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: No human playtest, unassisted victory, FPS or coverage certification

## Root Cause and Change

An isolated actual native Main run fails floor-four phase-two admission at frame
1466. The diagnostic baseline is the archived `959696e` checkout plus the native
narrow-query production files retained in
`build/retained-checkout/native-query-late-baseline-959696e-20261006`.

The failure is reproduced unchanged in the instrumentation copy. Its two-stage
failure evidence is retained at:

- `build/retained-checkout/native-query-late-diagnostic-959696e-20261006/build/floor4-phase2-effects-detail/`.
- `build/retained-checkout/native-query-late-diagnostic-959696e-20261006/build/floor4-phase2-payload-detail/`.

Both directories retain stdout, Godot logs, the rollback boundary, and the
detached typed `.bin` and readable `.json` rejection detail. The refusal is
`effects_can_commit`, specifically the payload candidate cold snapshot validator.
Payload ticket, before snapshot, native projection, target descriptors, repeated
contacts and landing queries all match. Effect ticket, registry, source batches,
semantic candidate/native observations, and summon ticket pass. There are no
effect damage or health records in the refused frame.

The legal diagonal direction is `(0.5927259922027588, 0.8054042458534241)`. Its
float32 normalization has a squared norm slightly above one. Integrating the
norm of the per-frame displacement produces travel `198.40001002628927` at
age 93, while the unchanged strict maximum is `128 * 93 / 60 + 0.00001 =
198.40001`. The candidate is correctly refused by that maximum-speed validator.

The runtime now retains its already calculated scalar `distance` in the motion
plan and integrates that value. This keeps the authored speed, Stop/Rift
modifiers, range clipping, direction, contacts, and retirement rules authoritative.
No validator tolerance or snapshot schema changes. Diagonal travel and derived
positions differ from the earlier erroneous integration by subpixel amounts;
that correction is intentional. Same-version replay is deterministic.

## Focused Verification

RED: `build/projectile-scalar-distance-red-20261006`. The real native projectile
is refused at offset 93, with downstream incomplete retirement. The domain test
also detects accumulated scalar error and the cold refusal. Fixture admission
and script parsing pass, with no unrelated engine or leak failure.

GREEN and regressions so far:

| Scope | Scenes | Evidence Directory |
| --- | ---: | --- |
| New domain and real native diagonal contracts | 2 | `build/projectile-scalar-distance-green-20261006` |
| Payload execution, result contracts, authority, Boss/identity/retirement, Moth and domain | 8 | `build/projectile-scalar-payload-regression-20261006` |
| Actual Player/projectile overlap | 1 | `build/projectile-scalar-overlap-regression-20261006` |
| Terminal projectile owner contact | 1 | `build/projectile-scalar-terminal-contact-regression-20261006` |
| Boss exposure checkpoint replay | 1 | `build/projectile-scalar-replay-regression-20261006` |
| Native combat cold checkpoint | 1 | `build/projectile-scalar-checkpoint-regression-20261006` |

The new domain contract advances the complete authored 120-frame lifecycle with
and without bounded Stop/Rift, validates every retained state through the
unchanged cold validator, compares travel to an independently calculated scalar
integral, rejects a trajectory-consistent forged overspeed snapshot, and restores
a historical boundary to reproduce the exact later state. The native contract
uses an actual Player collider and projectile projection. It verifies late target
movement rejection, exact domain/body rollback, identical same-frame retry,
publication and finite physical retirement.

Every listed GREEN scene passes the repository's strict stdout and Godot log
validator, including script errors and ObjectDB/RID leaks, under
`4.6.1.stable.official.14d19694e`. The stock runner reports line coverage as
unsupported. No dependency was added.

The progress-validation lane's independent read-only review found no correctness
issues in scalar ownership, typed snapshot boundaries, Stop/Rift clocks, contact
branch behavior, strict overspeed rejection, rollback/retry, or finite retirement.

All fourteen focused scenes pass. The earlier refusal runs contain no qualified
late-phase timing samples.

## Actual Main Third Phase

The uninstrumented `4735176` archive is retained at
`build/retained-checkout/projectile-scalar-after-4735176-20261006`. Its initial
editor import log is preserved, followed by a separately verified clean import
log. The runtime source digest is
`05890b7bd27f2754f476e307382218edbf82270d60639e592811cfd7ee8af9e5`.
Archived checkouts have no independent Git metadata; the report therefore keeps
an empty revision instead of inventing one.

`build/floor4-phase2-late-600/report.json` in that archive passes the actual native
Main probe and strict stdout/engine error and leak checks. Real Sword input
reaches phase index 2 in 2501 admission frames. The independent measured tape
contains the 600 unique consecutive frames 2502 through 3101 plus its initial
boundary, and fresh physical first/last readback matches exact typed bytes.
The content fingerprint is
`838c31095581b7abb79a63cb51b025d448c2ddd9d29b8ed75d2a318d8305bb2b`.

| Actual P3 Metric | Result |
| --- | --- |
| Player advance mean / p95 / max | 347.454 / 568.252 / 766.864 ms |
| Host process mean | 1.848 ms |
| Independent observer mean | 7.944 ms |
| Native duration / measurement wall duration | 10.000 / 217.078 seconds |
| Peak native static memory | 1,464,527,483 bytes |
| Peak physical counts | actors 1, projectiles 2, zones 3, threats 6; summons/constructs 0 |

The refusal is fixed, but this later workload substantially exceeds the 16.667 ms
frame budget. It is an explicit performance blocker. These headless measurements
run on a shared host with other validation workloads; they cannot certify GPU
rendering, 60 FPS, maximum concurrency, or total process RSS.

## Threaded Diagnostic

The isolated `projectile-scalar-hotpaths-4735176-20261006` archive wraps 125 methods
mechanically plus the multiline full-player validator. Its diagnostic store has
per-thread nested stacks, a Mutex, phase tags assigned at call entry, and finishes
after recording workers join and physical readback completes. A separate strict
two-worker selfcheck verifies nesting and role/phase ownership. The timing Mutex
and other host workloads add overhead; diagnostic timings are not certification.

Its `build/floor4-phase2-hotpaths-600/report.json` passes strict checks and reaches
the same admission frame, measures the same 600 frames, and retains identical
first/last typed replay hashes as the uninstrumented run. The source digest is
`cb40bf45dddf4ccfe422b844e8375a1f71f94a10bc99e6abf69b2db582ccc451`.

| Main Thread Method | Inclusive / Exclusive ms per Frame |
| --- | --- |
| Player advance | 335.224 / 2.563 |
| Refresh weapon replay fact baseline | 198.346 / 0.226 |
| Weapon replay snapshot | 198.120 / 198.120 |
| Full-player snapshot validation | 47.683 / 47.467 |
| Native recorder observation | 68.278 / 6.519 |
| Hostile bridge preparation | 46.920 / 1.939 |
| Boss runtime snapshot | 6.542 / 6.542 |
| Native cold snapshot | 7.499 / 5.325 |

Five concurrent writer threads encode five chunks with total codec inclusive time
85.584 seconds. These concurrent spans must not be added to main-thread cost.
Entry-phase tags are not an interval split for calls that cross into retention.

A SHA-verified committed physical keyframe at actual frame 2741 contains a
1,596,244-byte observation: Player 1,386,628 bytes, including 1,246,548 bytes of
weapon replay events; native state is 109,280 bytes and Run is 94,088 bytes. This
explains the priority shift to historical replay work. It is a measured later
state, not a synthetic load or a claim that history can be discarded.

## Rendered Real-Time Samples

The same uninstrumented archive also passes its rendered real-time probe at
`build/floor4-phase2-rendered-realtime-120/report.json`. Real input reaches the
same third-phase boundary, then measures the 120 unique frames 2502 through 2621
at time scale 1 and native 60 Hz. The physical tape has 121 observations, and its
fresh first/last readback matches exact typed bytes. Strict stdout and engine
error/leak checks pass.

Player advance mean / p95 / max is 266.879 / 273.224 / 388.803 ms. Two seconds of
native time take 33.150 seconds of measured wall time. Render wait averages
2.359 ms, Host processing 1.399 ms, and the independent observer 5.506 ms. Peak
native static memory is 1,228,728,011 bytes, not process RSS. Retention after the
measurement takes 16.729 seconds.

`rendered-final.png` is a nonempty 640 by 360 viewport capture taken outside the
measurement. It shows the actual floor, player, Boss third-phase HUD and controls.
Large HUD panels cover most gameplay space, so this is retained as a visual
defect for the UI lane, not as polished UI acceptance. The scheduling and CPU
results still fail the frame budget; this run cannot certify 60 FPS.

Longer sustained recording remains pending. Every probe retains its explicit
survival and prerequisite-route fixtures; none claims human playtesting,
unassisted victory, FPS certification, or line coverage.
