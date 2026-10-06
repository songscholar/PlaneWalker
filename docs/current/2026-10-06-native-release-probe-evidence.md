# Native Release Runtime Probe Evidence

- Status: Recording And Monitoring Verified / Frame budget failed
- Document Role: Current retained official release invocation and measurement evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Packaged macOS release performance harness and measurement tooling
- Owner: Project integration lead
- Depends On: `2026-10-06-native-release-probe-plan.md`
- Last Verified: 2026-10-06
- Certification Status: No FPS, rendered, saturation, soak, coverage or human certification

## Runtime And Package Binding

The verified official macOS template archive at
`build/toolchain/godot-4.6.1/templates/4.6.1.stable/macos.zip` has SHA-256
`a6d51d2b650091ab7073c15e9e6faf01c0e972648edb2e99952735c6befae00e`.
Its release executable has SHA-256
`aa1a4febbb87876717d6d2fc9b65ad0878696d1e676b64c1bb1c18775bb1f070`
and version `4.6.1.stable.official.14d19694e`.

Actual invocations reject both `--path` and `--main-pack` because the template
disables path overrides. They fail before project startup and are not gameplay
failures. Their original logs are respectively retained in the unchanged
`native-unified-9738bc5-20261006` archive's
`build/floor4-phase2-release-parent-late-600/` and the derived release archive's
`build/release-probe-main-pack-check/`.

Commit `5c19054` adds packaged-binary measurement mode and version-three monitor
metadata. It authenticates the actual macOS bundle through `CFBundleExecutable`,
the exact sole `Contents/Resources/<executable>.pck`, regular non-symlink paths,
and executable/PCK/plist hashes before and after execution. A final layout
check rejects late ambiguity. Other package layouts remain unsupported.
The source-checkout role is explicitly `harness_only`; source hashes alone do
not certify code inside a package. Existing version-one/two validators retain
their strict rules. Release zero static-memory observations are explicitly
unavailable, while positive actual RSS remains required.

Author and independent review both pass 25 focused Python contracts. Valid RED
logs retain the missing packaged mode/schema behavior and eight unrelated,
ambiguous, symlinked or misidentified layouts accepted before the binding fix.
They remain at `build/native-packaged-performance-probe-20261006/`.
An early mock failure accidentally included an inherited environment in one
local log; its entire sensitive call line was removed, and the same RED was
reproduced with numeric call-count assertions. That setup log is not accepted
RED evidence and was not committed. No environment values are retained here.

## Derived Release Harness

`build/retained-checkout/native-release-parent-9738bc5-20261006/` starts from
detached `9738bc5424d9659b3b6b1cbbe479908ea62542ad`. Its production scripts are
unchanged: 410 files, aggregate
`6bbbc931c71813cb525b4151947315ecfcf3567fa1bc93b492e7894d8f273931`.
Only the project main-scene setting selects the existing performance harness,
which instantiates actual production Main. For the version-three package,
the committed probe Python/GDScript files are mechanically overlaid with hashes
`80ce76dc9d48196f33cbe38368677272f1f8cbc0f22a3c5182547fe8a29f19a0`
and `063549c28de16adec76e880b47644b1aabd2041179167f3c1afb5fea971b42cb`.
This is a disclosed diagnostic checkout, not a clean product certification.

Second import, version-three import and both official release exports have
strict clean paired logs under `build/release-probe-export-logs/`. The original
`build/macos/PlaneWalker.app` remains intact. Its one-frame startup smoke passes
custom assertions and strict logs; raw static memory is zero. It has no RSS
measurement or performance certificate. Its report SHA-256 is
`62a7f915509bf2851d502dc4b195ab648074c7ad2c4f99d1b1c1553d483ce858`.

The later `build/macos/PlaneWalkerV3.app` uses the exact official release
executable. Its PCK hash is
`a1cf0ba2c650de97134a16622fe504cf1eed47077bd59dc3d37bc74e3396642f`;
plist hash is
`337942ea91dea8656ae14fe78fe6ea32888c63e5eb276a38e833bed144af57fc`.
The runner retains its actual command and confirms all three hashes and the
autoload layout stay stable. This diagnostic package is not a playable build.

## First Actual Release 600-Frame Result

`build/floor4-phase2-release-parent-late-600-v3/report.json` has SHA-256
`f8c994b6fa78bee8799c49d77d28ce816d0a8f4f2991a52279ab30371415009c`.
Actual Sword admission takes 2,501 Player frames, then every measured frame
from 2,502 through 3,101 passes. The internal native result is `pass`, failures
are empty, exit is zero, runtime source is stable, and both final logs are
strict clean. The overall retained report remains `failed` because real RSS
sampling never acquired a process identity or any valid sample.

The physical tape contains 601 observations, honestly `INTERRUPTED`, with no
recording failure. Fresh physical first/last complete typed bytes match their
measured observations; hashes match the historical editor 600-frame endpoints:
`8b7b8ab43674e54121d4568336b5ae14de29b4a9a522acc5c2743a64b83dfe11` /
`fd46d302787af37d90f09747b52e8faa08395e00b0505fc087edbc6c45ec105a`.
This proves endpoint equivalence, not all intervening bytes or unassisted play.

| Actual Release Measurement | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Player advance | 38.069 ms | 45.275 ms | 88.930 ms |
| Same-frame Player and Host | 39.260 ms | 46.654 ms | 89.705 ms |
| Same-frame wall including waits and observer | 46.762 ms | 55.586 ms | 97.337 ms |

Ten native seconds take 28.058 wall seconds; physical retention takes
7.384 seconds. Observed peaks are one actor, six threats and three zones.
Static memory is explicitly unavailable (`debug_build=false`, observed zero).
RSS has zero samples and zero process identity, not measured zero memory.
During the live run both logs remain zero bytes; the runtime PID announcement
only becomes visible when the release process exits and flushes its logs.
The existing stdout-driven sampler therefore cannot obtain useful live samples.
The tool correctly refuses the otherwise successful recording report.

## Open Acceptance

The live PID tool repair below is independently contract-verified and the new
combined package now has real RSS and exact recording evidence. The original
failed report remains unchanged. The combined run is a public-fallback baseline:
at `8011d1b` the production Bridge Script is not admitted by the native-token
checks. The subsequent [production integration milestone](2026-10-06-native-production-frame-integration-evidence.md)
verifies actual Main native admission, but its native-enabled performance
measurement remains pending.
Both the old and combined runs fail the
16.667-ms frame budget. Concurrent frozen validation activity overlaps these
runs, so their differences do not isolate a production optimization. Rendered
saturation, sustained recording, the 45-minute soak, memory acceptance,
finished UI and human playtests remain open.

## PID Bootstrap Tool Repair

The probe now writes its actual runtime PID to the runner-supplied independent
`process.pid` file before loading content or Main, explicitly flushes and
closes it, and retains the existing stdout announcement. The sampler prioritizes
the file so release stdout buffering cannot prevent live sampling. Preexisting
files/directories/symlinks refuse before launch; malformed or symlinked runtime
bootstrap files cannot substitute stdout evidence. Legacy source fixtures can
still use their original stdout path.

After exit, the version-three runner independently reads the physical file
and sole final stdout announcement, overwrites any report-supplied binding,
and requires exact equality with `native_process_id` and the sampled RSS PID.
The retained `native_pid_binding` records the identities, announcement count,
path and validation status. Missing, malformed, duplicate or conflicting
evidence fails the report. Versions one/two retain their previous validators;
positive real RSS remains mandatory for versions two/three.

Evidence is retained at `build/native-pid-bootstrap-20261006/`. The final RED
`red/baseline-valid.log` executes the preceding exact `5c19054` production
Python source against the resolved-path fixtures: six tests produce 31 actual
behavioral assertion failures with no parse/setup exceptions. This includes
the empty-stdout fixture whose independently written physical PID file must
permit sampling before the stdout flush. Earlier draft logs are diagnostic
only and are not the accepted RED.

`green/contracts-final.log` passes both Python contract modules, 31/31 tests.
`green/gdtoolkit-parse-final.log` passes the GDScript AST parse using the existing
pinned coverage virtual environment; `git diff --check` passes. Independent
read-only review repeats all 31 contracts, verifies these four exact hashes,
and reports no remaining actionable finding:

| Scoped File | SHA-256 |
| --- | --- |
| `tools/p15/native_performance_probe.py` | `c56e9b2c64423e06c1e7ef55546ae43955a9fe2a64b6c61e0ffe6108fee87b95` |
| `tools/p15/native_performance_probe.gd` | `37e2fdf2a64cd713b363856dbe6a3235aa9dcb39f78d2584c8bd3c86d41b4478` |
| `tests/contract/performance/test_native_performance_probe.py` | `e107e64c24e73562f0e49c6fdb233ec9355b5cc52120d600db367e2c3bf6a251` |
| `tests/contract/performance/test_native_measurements.py` | `f6d281e0f5d8fb92473c717774293f4bbc716a47c25da78fcc232b28bcc3c2a9` |

This is tool acceptance only. No new package was exported or measured during
this repair, and no FPS, release-memory, rendered, soak, full native matrix,
unassisted-play or human claim follows from these contract results.

## Combined Commit Public-Fallback Release 600

After the repair was committed as `8011d1bfa86c8cb1fbc266226ba67a324249ee6e`,
the combined diagnostic checkout is retained at
`build/retained-checkout/native-release-combined-8011d1b-20261006/`.
It includes owned-token commit `86aef36` and the PID repair. It is a detached
worktree of that exact commit with no production overlay. The sole tracked
override changes `project.godot` from production Main to the existing probe
main scene, which instantiates production Main. All 411 production
`scripts`/`autoload` GDScript files remain unchanged before and after execution;
their aggregate is
`76bd12d806174d13d8747c503033fb3ccf0e11aabc5014390ada856f68637896`.

This source contains the token implementation but production Main does not
exercise it. `NativeLaunchEncounterDriver` constructs its embedded
`ProductionBridge` Script, while `_uses_native_actor_frame` requires exact
`HostileFrameBridge` Script identity and Actor `_native_frame_bridge_binding`
requires the same identity. The embedded Script therefore takes the original
public ticket fallback. This run is an actual public-fallback baseline, not a
measurement of the token path after production activation. Production native
Bridge integration is verified by the later separately retained milestone;
an actual admitted-token measurement remains pending.

The first import exits zero but is explicitly not strict clean: both original
logs have 88 setup diagnostics, all missing/generated translation resource
errors. The raw pair and `build/release-pid-provenance/import-1-classification.json`
remain retained. The second import and official `macOS Release` export both
exit zero and pass strict independent paired scans. These logs are under
`build/release-pid-export-logs/`; no first-import error was suppressed or
misclassified as clean.

The self-contained official editor executable has SHA-256
`ad304ee206ac9a0ab8407365e767ec33fe78d9455ff9dcace207c053e2651667`.
The exported `build/macos/PlaneWalkerPidBound.app` has the same official release
executable and plist hashes recorded above, while its PCK hash is
`7cecfc3cadf405ee1814ef27beae67a966e1a961e21e1e654a2bbb097db85740`.
The runtime's actual command, exact bundle autoload binding, all three hashes
and layout remain stable. `build/release-pid-provenance/source-before.json`
and `export-receipt.json` retain the source, override, toolchain and export
chain separately; a `harness_only` runtime manifest alone does not authenticate
the source inside a PCK. This diagnostic package is not a playable distribution.

`build/floor4-phase2-release-combined-late-600/report.json` has SHA-256
`8261deb7fd9b2f344725807d515241c46cde453943a75c2d02dd5c1d0cb4d040`.
Its source manifest has SHA-256
`38edd5d1cc060be69f34a6f8d8e9893e57a0be00eeacfd0d97b3abf36e444f3b`.
The process exits zero and its final stdout/engine pair is strict clean. Real
Sword admission takes 2,501 frames, followed by 600 accepted consecutive
frames from 2,502 through 3,101. Both native and retained measurement status
are `pass`, with no custom failure. That status certifies these measurement
contracts, not the separate gameplay performance gate.

The physical tape has 601 observations, honestly `INTERRUPTED`, with no
recording failure. Fresh complete typed first/last readback is exact, with the
same historical endpoint hashes recorded above. Retention takes 8.030 seconds.
Author post-run verification revalidates the report, paired logs, fixed source,
bundle binding and package hashes in `build/release-pid-provenance/post-run-verification.json`.
Independent read-only review repeats report/schema validation, exact PID and
RSS binding, all 411 source hashes before/after, the package's three hashes
and sole autoload layout, and all final paired scans. Its separate
`build/independent-release-combined-8011d1b/physical_endpoint_check.gd` uses
real Godot to read the original 601-observation `INTERRUPTED` archive without
mutating it: sequence 1/600 has integer Player frames 2,502/3,101 and complete
`var_to_bytes` hashes equal the historical endpoints. The retained
`physical-endpoints.stdout.log`/`physical-endpoints.godot.log` pair is strict
clean and exits zero. It does not rerun combat or modify the source, report or
archive. This independently verifies measurement and physical recording,
not token activation or the performance budget.

The bootstrap file, sole final stdout announcement, native report and RSS
sampler all bind PID `57691`. A retained live observation shows both logs still
at zero bytes while the bootstrap already permits a real `ps.rss_kib` memory
read. The final sampler has 1,262 valid observations and one failed process
read; peak RSS is 1,060,651,008 bytes (1,011.516 MiB). This is the whole native
process after bootstrap, including Hub, phase admission, measured frames and
retention; it is not an isolated 600-frame memory bound or memory-budget pass.
The release static monitor remains explicitly unavailable: observed zero,
`debug_build=false`, reason `release_build`.

| Combined Release Measurement | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Player advance | 39.643 ms | 51.547 ms | 135.564 ms |
| Same-frame Player and Host | 40.984 ms | 53.341 ms | 138.753 ms |
| Same-frame wall including waits and observer | 49.117 ms | 64.665 ms | 155.815 ms |

Ten native seconds take 29.471 measured wall seconds. Peaks remain one actor,
six threats and three zones; the fixture does not establish saturation. Five
concurrent frozen `replay-codec-immutable-4a8fc6f` Godot workers consume about
99 percent CPU each in the retained process snapshot. No controlled net CPU
or editor/release improvement follows from these runs. Recording and actual
monitoring pass; the 16.667-ms frame budget fails, `fps_certified=false`,
`unassisted_victory=false`, and `human_playtests=0`.

## Combined Commit Public-Fallback Editor 600

The completed uninstrumented editor run is retained in
`build/retained-checkout/native-editor-combined-8011d1b-20261006/`, a clean
detached checkout of the same `8011d1b` commit. Its tracked worktree is clean;
the existing probe scene is selected directly by the actual command rather
than through a project-setting override. The manifest identifies the executed
source project, `/Applications/Godot.app/Contents/MacOS/Godot`, the same
official editor executable hash recorded above, and 411 runtime source files
with aggregate
`76bd12d806174d13d8747c503033fb3ccf0e11aabc5014390ada856f68637896`.
This is the same historical public-fallback source, not the later
native-enabled production integration.

The report is `build/floor4-phase2-editor-combined-late-600/report.json`,
SHA-256 `dac4c003f2a6ab5ac08fbe63a583182c3abb8801626b102985aedb759eac3c75`;
its `source-manifest.json` has SHA-256
`3a35655cc6b961a0b92015d6ad30fbd539a841f7df42c4dd7b5933a014bf7e8c`.
It exits zero, accepts all 600 consecutive frames 2,502-3,101 after 2,501
admission frames and has no custom failure. Both status fields are `pass`.
The first-import raw logs retain 88 diagnostics each and are not claimed
strict clean. The second-import and final measurement stdout/engine pairs
independently pass the strict runtime-log validator.

Read-only post-run validation repeats the actual report validator, compares
all 411 current runtime hashes to the manifest, checks the editor executable
hash, and requires the report's source identity to equal the manifest's
retained source identity. Independently recollecting the physical bootstrap
file and sole final stdout announcement reproduces the exact saved binding.
PID `61695` agrees across bootstrap, stdout, native report and RSS sampler.
No source, report, archive or process state was mutated by that review.

The physical recording retains 601 observations with status `INTERRUPTED`,
no recording failure, and exact typed first/last readback with the same
historical endpoint hashes above. Retention takes 8.909 seconds. Real RSS has
1,599 valid samples, zero failed reads and a peak of 1,309,032,448 bytes over
the whole post-bootstrap process. Unlike the release build, the editor's
native static monitor is available, with raw peak 726,327,573 bytes. Neither
observation is an isolated 600-frame memory acceptance or memory-budget pass.

| Combined Editor Measurement | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Player advance | 52.900 ms | 76.035 ms | 113.128 ms |
| Same-frame Player and Host | 54.673 ms | 78.873 ms | 114.119 ms |
| Same-frame wall including waits and observer | 64.873 ms | 91.804 ms | 152.464 ms |

Ten native seconds take 38.925 measured wall seconds. The same one-actor,
six-threat, three-zone scene is not saturation evidence. Concurrent frozen
validation activity overlapped the editor/release runs, so their differences
are not a controlled source or runtime optimization comparison. Recording,
source stability and monitoring contracts pass; the 16.667-ms frame budget
fails. Rendered/FPS, sustained recording, soak, UI and human certification
remain absent. A new frozen native-enabled editor/release measurement must
retain its own source commit and reports after production integration.
