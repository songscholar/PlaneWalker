# Native Release Runtime Probe Evidence

- Status: Recording Verified / Monitoring and frame budget failed
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

The live PID tool repair below is independently contract-verified. Its actual
packaged release measurement remains pending and must use a new evidence
directory. Do not replace or mark the failed original report passing. The
16.667-ms frame budget independently fails. Concurrent native matrix and frozen
validation activity overlaps the original run, so editor/release differences
do not isolate a production optimization. The later Effects and owned-token
changes are not in that production source. Rendered saturation, sustained
recording, the 45-minute soak, memory acceptance, finished UI and human
playtests remain open.

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
