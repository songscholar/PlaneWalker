# Native-Enabled Runtime Measurement Evidence

- Status: Recording And Monitoring Verified / Frame budget failed
- Document Role: Current frozen editor and official release measurement evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Actual Main native-enabled source, recording, source provenance and process RSS
- Owner: Project integration lead
- Depends On: `2026-10-06-native-production-frame-integration-evidence.md`, `2026-10-06-native-release-probe-plan.md`
- Last Verified: 2026-10-06
- Certification Status: No FPS, rendered, saturation, soak, coverage, finished UI or human certification

## Frozen Source

Both measurements use detached
`f85c84d94529f05986b29b586ac592b43c0a9dd1`, which retains production
integration `f29366f` and its focused actual-Main native admission evidence.
The 412 physical runtime scripts in `scripts/` and `autoload/` have aggregate
`38750c6e8d84bd4d2bb584e151a53e398e86787670b3985fffa4e696fa0d7bb0`.
Neither measurement uses production overlays or diagnostic timers. These
unmodified measurements do not contain native/public call counters; the
separate integration evidence establishes the admitted production path.

The editor checkout is
`build/retained-checkout/native-editor-enabled-f85c84d-20261006` and the release
checkout is
`build/retained-checkout/native-release-enabled-f85c84d-20261006`.
Their independent source manifests were compared against all 412 physical
files. Source, executable and package hashes remained stable after execution.
The two 600-frame runtime invocations ran serially. Subsequent independent
physical readers ran after the release measurement exited; a short reader
overlapped the later instrumented 120-frame diagnostic, which is attribution
work and cannot certify production performance.

Earlier reports at `8011d1b` retain their original public-fallback classification,
source manifests and measured bytes. These new reports do not relabel them or
establish an isolated optimization gain.

## Official Release Preparation

The release checkout initially had clean tracked status and no `.godot` cache.
Its sole tracked change is the existing performance probe main scene:
`res://scenes/main.tscn` becomes
`res://tools/p15/native_performance_probe.tscn`. The probe instantiates real Main.
Post-run verification compares all 2,443 tracked file hashes against the
pre-import receipt and verifies the exact unchanged main-scene diff, in addition
to all 412 runtime source hashes.

The retained preparation and post-run receipts are in the release checkout's
`build/release-native-provenance/`:

- `checkout-before.json`, `source-before.json`;
- both import invocation, classification and source-after receipts;
- `export-release-invocation.json`, `source-after-export.json`,
  `export-receipt.json`;
- `post-measurement-validation.json` and its retained verification helper.

Both editor and release first import pairs exit zero and each contain 88 exact
configured translation derivative diagnostics from the same 11 valid CSV stems.
The existing classifier accepts only these setup diagnostics. No residual error,
fatal script failure or leak remains after classification. These bootstrap
logs are retained unchanged and are **not strict clean**. Both second import
pairs and the release export pair pass the strict runtime-log validator.
Editor import logs are under `build/native-enabled-import/` in its checkout;
release import/export logs are under `build/release-native-export-logs/` in its
checkout.

The official Godot 4.6.1 editor SHA-256 is
`ad304ee206ac9a0ab8407365e767ec33fe78d9455ff9dcace207c053e2651667`.
The retained official macOS template archive SHA-256 is
`a6d51d2b650091ab7073c15e9e6faf01c0e972648edb2e99952735c6befae00e`.
The actual `macOS Release` export is
`build/macos/PlaneWalkerNativeOwned.app` inside the release checkout.

| Actual Package File | Stable SHA-256 |
| --- | --- |
| `Contents/MacOS/Plane Walker- Chronicles of Collapse` | `aa1a4febbb87876717d6d2fc9b65ad0878696d1e676b64c1bb1c18775bb1f070` |
| `Contents/Resources/Plane Walker- Chronicles of Collapse.pck` | `74372653d0ebd8541fbbc8bd5b1c8f746a5ed59cf761fd7a94303c38a3c9f0b0` |
| `Contents/Info.plist` | `337942ea91dea8656ae14fe78fe6ea32888c63e5eb276a38e833bed144af57fc` |

Before and after execution, the package validator binds the exact
`CFBundleExecutable`, its sole automatically loaded PCK and regular non-symlink
paths. The official import/export receipts connect the frozen source inputs to
the observed exported package. The runner's source role remains `harness_only`:
source hashes alone do not independently certify code inside a PCK. This export
starts a diagnostic probe and is not a certified playable release.

## Actual Editor And Release Results

Both reports use 60-Hz native scheduling, time scale 1.0, fixed-FPS wall
acceleration and headless rendering. Each visits all nine functions in the
three Hub districts across 120 Hub frames. Actual Sword admission to floor 4,
Boss phase 2 takes 2,501 Player frames, then all 600 measured frames from
2,502 through 3,101 pass. The native duration is 10,000 ms. The declared
survival and prerequisite-route fixtures remain active; neither run proves an
unassisted victory or human playtest.

| Runtime / Actual Measurement | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Editor Player advance | 54.288 ms | 80.430 ms | 163.602 ms |
| Editor same-frame Player and Host | 56.157 ms | 83.931 ms | 167.446 ms |
| Editor same-frame wall including waits and observer | 66.994 ms | 95.919 ms | 177.487 ms |
| Release Player advance | 39.567 ms | 52.426 ms | 109.461 ms |
| Release same-frame Player and Host | 40.951 ms | 55.135 ms | 110.330 ms |
| Release same-frame wall including waits and observer | 49.563 ms | 67.628 ms | 118.438 ms |

The editor takes 40,197,502 wall microseconds; release takes 29,738,505. Separate
physical retention takes 9,889,537 and 8,445,021 microseconds, respectively.
Both actual same-frame work distributions exceed the 16.667-ms budget.
Measurement/report status `pass` means the bounded samples, source, logs,
recording and monitors were verified; it is **not a performance certificate**.

| Process Observation | Editor | Release |
| --- | ---: | ---: |
| Exact bootstrap / stdout / report / RSS PID | 90985 | 95768 |
| Final stdout PID announcements | 1 | 1 |
| Valid / failed RSS samples | 1,679 / 1 | 1,238 / 1 |
| Peak actual process RSS | 1,288,945,664 bytes | 1,040,121,856 bytes |
| `Performance.MEMORY_STATIC` | 710,526,321 bytes, available | observed zero, unavailable in release |

The process RSS source is actual macOS `ps.rss_kib`, sampled every 100 ms after
the runtime bootstrap announces its PID. Both records retain the failed sample
and `native process RSS sample is unavailable` error. Independent post-run
validation rereads the physical PID file and sole final stdout announcement,
matches the exact retained binding and verifies the RSS process identity.
Release static-memory zero is explicitly unavailable, not measured zero
memory. These short samples are below two billion bytes but do not establish
the sustained-memory gate.

## Physical Recording And Independent Review

Both measured tapes physically retain 601 observations, status `INTERRUPTED`
and empty recording failure. The editor measured tape id is
`09082b3d5ec01e2500e81783c9c0d82e0b8613a9a4b37cbfb617b3d212f374f8`;
release is
`389acd7241acb18c560332b5820c31fcc146e4b6687242c41a0fa415ea7864ec`.
Fresh reads compare complete first/last typed observation bytes to the actual
measured observations.

An independent real-Godot reader additionally validates each physical profile
envelope and stream manifest, reads the actual compressed chunks, decodes via
the production typed codec and checks sequence 1/frame 2,502 and sequence
600/frame 3,101. Sequence and Player frame fields remain `TYPE_INT` (2), and
both complete `var_to_bytes` hashes match:

- First: `8b7b8ab43674e54121d4568336b5ae14de29b4a9a522acc5c2743a64b83dfe11`.
- Last: `fd46d302787af37d90f09747b52e8faa08395e00b0505fc087edbc6c45ec105a`.

The independent reader and its two strict-clean stdout/Godot log pairs are
retained under `build/independent-native-enabled-f85c84d/`. It reruns neither
combat nor measurements. Original report bytes remain unchanged. The release
post-run receipt also verifies the physical compressed chunk sizes and hashes.
Endpoint verification does not establish every intervening observation or a
complete run.

| Retained File | SHA-256 |
| --- | --- |
| Editor `build/floor4-phase2-editor-native-enabled-600/report.json` | `1d4fb159fb31fd5535ac566bbb4bb6549326ef9beeae8eaba287e35080eddcc0` |
| Editor `source-manifest.json` in the same directory | `c069e940de89e2f39244a1738ded7e9864d8cbe67b5c9b83395940a7f2109430` |
| Release `build/floor4-phase2-release-native-enabled-late-600/report.json` | `06a2a2e60bc1850a10b736fbc5a80d173bb4be730c57161c222ebdf7477a242a` |
| Release `source-manifest.json` in the same directory | `d4d058668c7818eb9c79b5018fdcb2b841b178ff7a00af78820dac305437da2b` |

Author and independent review pass the report validator, strict final runtime
log pairs, physical runtime source hashes, PID/RSS binding and release package
identity/layout. Independent review additionally checks the actual bootstrap
classification, strict second imports/export and both physical typed endpoints.
No open correctness finding remains in these bounded measurement receipts.

## Remaining Gates

Observed peaks are one actor, six threats and three zones; constructs,
projectiles and summons are zero. This is late-Boss evidence, not rendered
saturation. There are no captured rendered frames or GPU/60-FPS measurements.
The actual 45-minute gameplay and concurrent recording gate, representative
worst-case Hub/combat budgets, sustained memory, complete final validation,
exact-source coverage and playable release certification remain open.

UI implementation remains gated by the complete gameplay milestone. The
[UI preparation audit](2026-10-06-native-ui-preparation-evidence.md) retains
contracts and font provenance only. The planned 49-state registry and 784-image
matrix have not been implemented or captured; this measurement milestone adds
no UI completion evidence.
