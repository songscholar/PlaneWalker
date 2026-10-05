# Native Main Performance Probe Evidence

- Status: Verified development probe / Final certification pending
- Document Role: Current
- Authority Level: Verification evidence below approved native performance specification
- Applies To: Actual Main, Hub, combat and independent automatic recording
- Owner: Plane Walker verification lane
- Last Verified: 2026-10-06
- Depends On: `docs/superpowers/specs/2026-10-05-native-performance-probe-design.md`

## Executable Probe

`tools/p15/native_performance_probe.py` launches actual production Main with an
isolated physical Profile. It visits all nine functions across three Hub
districts and measures consecutive Player frames with the real automatic
NativeRunReplayRecorder. Production physics stays at 60Hz and unit time scale.
`--fixed-fps 60` changes wall scheduling, not native ability durations.
Survival invulnerability and any prerequisite route fixtures are declared.

The measured tape starts after optional real Sword phase admission. Every frame
must produce exactly one new observation with a consecutive actual Player
frame. A fresh disk store reads the first and last samples byte-exactly after
flush and explicit INTERRUPTED completion. The report records independent
Player, Host, scheduler, observer and optional render timings, actual concurrent
objects, content fingerprints and native memory. Python rejects false success,
malformed distributions, invalid scheduling, invented render timings, missing
physical samples and human/FPS claims. Runtime errors and leaks fail the run.

## Development Results

The runtime source is the Git archive of `38423c7`, with only the new probe
overlaid. This is development evidence; the final coherent-source certification
must use a fresh untouched archive. Both runs use headless Godot, 120 distinct
actual frames (2000 native milliseconds), and 12 Hub sampling frames. Both
finish with clean logs, exact physical first/last observations, and 121 total
automatic tape observations including the initial boundary.

| Actual encounter | Player mean | Player p95 | Player maximum | Combat wall time | Observed load |
| --- | ---: | ---: | ---: | ---: | --- |
| Floor 1 combat | 20526 us | 26590 us | 49749 us | 2857516 us | 3 actors, 1 threat |
| Floor 1 Boss, phase 0 | 22727 us | 29809 us | 47840 us | 3193770 us | 1 actor, 4 constructs, 2 threats, 1 zone |

Reports and both stdout/engine logs are under
`build/retained-checkout/audit-38423c7/build/native-performance-smoke-green/`
and `build/retained-checkout/audit-38423c7/build/native-performance-boss-smoke/`.
The first development run reached all samples but failed audio-drain cleanup;
it remains failed. The corrected tool waits for native playback retirement
using bounded wall-clock polling, which both successful runs verify.

Five Python contracts pass. The original missing-executable RED and first
GREEN logs are `build/native-performance-contract-red.log` and
`build/native-performance-contract-green.log`.

These short samples do not certify 60 FPS, worst-case saturation, human play,
unassisted victory, a 45-minute recording, rendering or later Boss phases.
Longer runs must retain unique actual samples and observed load rather than
substitute repeated tape values or hypothetical concurrency.

## Current Frame Diagnosis

The isolated checkout
`build/retained-checkout/native-recorder-profile-be58030-20261006` starts at
`be580300a80888882d70dff5ac0863c3ed7359d6`. Five consecutive diagnostic
runs add progressively finer timing inside Player, hostile bridge, recorder,
Boss runtime and native geometry methods. These edits remain only in that
checkout. The final diff is seven files, 121 added lines and two replaced lines;
production source does not contain the instrumentation.

Reports are retained at `build/profile/report.json`,
`build/profile-player/report.json`, `build/profile-bridge/report.json`,
`build/profile-boss/report.json` and `build/profile-geometry/report.json`
inside that checkout. All explicitly set `diagnostic_instrumented: true`.
Each records 600 distinct accepted floor-2 Boss phase-0 Player frames,
independent automatic recording and exact fresh physical first/last readback.
All five have identical first/last tape hashes and strict clean stdout/engine
logs. No source was changed during an individual run.

The Player diagnostic gives the following mean elapsed wall times. Substeps
include their nested work and must not be added again to parent totals.

| Player frame step | Mean |
| --- | ---: |
| Intent validation and preflight | 0.400 ms |
| Transaction preimage | 0.242 ms |
| Hostile begin and event buffers | 0.657 ms |
| Native clocks and character preparation | 0.139 ms |
| Weapon and character commit | 0.119 ms |
| World, rewind, intents and movement | 0.085 ms |
| Hostile preparation | 16.020 ms |
| Buffer commit and fact baseline | 5.267 ms |
| Native publication and automatic recording | 7.549 ms |
| Entire Player advance | 30.557 ms |

Within recording, native cold snapshot creation/validation averages 4.100 ms,
Player validation 1.558 ms and detached latest-observation copying 0.655 ms.
The final nested Boss diagnostic records 4,552 full-validation contexts,
3,411 positive cache hits, 1,141 uncached accepted snapshots and 570 fresh
configurations. Context encoding totals 459.706 ms, snapshot encoding
621.563 ms, uncached validation 1,161.474 ms and configuration 467.572 ms.
Native Boss geometry inspection totals 767.369 ms across 5,691 calls and is
already included in its enclosing frame work.

These measurements identify hostile preparation, repeated transaction
validation and native recording as remaining costs. They do not justify
skipping validation or claim a verified optimization. They ran headless with
fixed-FPS scheduling during parallel matrix/scene validation; elapsed timings
include instrumentation and host contention. The 16.667 ms rendered target,
late phases, sustained recording and bounded memory remain pending separate
uninstrumented certification.
