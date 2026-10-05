# Native Main Performance Probe Evidence

- Status: Verified development probe / Final certification pending
- Document Role: Current
- Authority Level: Verification evidence below approved native performance specification
- Applies To: Actual Main, Hub, combat and independent automatic recording
- Owner: Plane Walker verification lane
- Last Verified: 2026-10-05
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
