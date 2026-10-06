# Native Renderer Comparison Evidence

- Status: Measured / CPU optimization and 60 FPS gates open
- Document Role: Same-source Metal and OpenGL Compatibility comparison
- Authority Level: Below approved full-product completion contract
- Applies To: Actual production Main, fifth-floor Void Boss phase two
- Owner: Plane Walker performance lane
- Depends On: `2026-10-06-mode-cohort-rendered-performance-evidence.md`
- Last Verified: 2026-10-06

## Frozen Source and Measurement

An independent clean clone is retained at
`build/retained-checkout/native-backend-9fd36ef-20261006/`, detached at
`9fd36ef184c79b29b0dc1eac5dd09fe0a6d8f3c3`. Both measurements execute the
same 426 runtime GDScript files with aggregate SHA-256
`e575ade393bdd44eae344c114c22e6f48b6526e86d39f615ffc4dddb0a7d4c53`.
Their complete runtime file hash maps match, stay stable, and declare no
coverage instrumentation. The tracked clone stays clean after both runs.

The runtime aggregate covers `scripts/` and `autoload/`, so the independent
probe harness hashes are also retained:

| Harness | SHA-256 |
| --- | --- |
| `tools/p15/native_performance_probe.py` | `c34a475d538517619b79558cdf79f07bb479890eb5522d6d1bf66184073f4839` |
| `tools/p15/native_performance_probe.gd` | `266461cc98035882128b03c88da5fed13f07ce93957da7198cb7ed90b7400a95` |
| `tools/p15/native_performance_probe.tscn` | `9339c45404e28c4b4762098c1b81222f78d1c4a69c3aadedec9a6a4344d47e66` |

Both execute Godot 4.6.1 debug, SHA-256
`ad304ee206ac9a0ab8407365e767ec33fe78d9455ff9dcace207c053e2651667`.
The initial editor import diagnostics remain separate; the second import
and all four measured stdout/engine logs pass strict validation. All other
project agents finish their current Godot children before this quiet window
and resume only after both measured processes exit. No personal process is
paused. Measurements are sequential, Metal first, OpenGL second.

Inside the frozen clone, each command uses the same settings and scripted
actual Player inputs:

```sh
python3 tools/p15/native_performance_probe.py \
  --output build/phase2-metal-120/report.json \
  --frames 120 --hub-frames 120 --boss-floor 4 --phase 2 \
  --real-time --rendered --rendering-method forward_plus --timeout 900
python3 tools/p15/native_performance_probe.py \
  --output build/phase2-opengl-120/report.json \
  --frames 120 --hub-frames 120 --boss-floor 4 --phase 2 \
  --real-time --rendered --rendering-method gl_compatibility --timeout 900
```

Both independently visit the nine Hub functions, use the declared route and
survival fixtures, reach phase two after 2,501 actual accepted frames, and
sample exactly frames 2,502-2,621, 120/120. Content snapshots, encounter,
scheduler, sample range, and observed peak counts match. Content aggregate is
`39a346d5367c10553562fe08b6b8871457e7a5e3d7b4c176841827e89aa5edb6`.
Both use 60 native Hz, time scale 1, and real wall time.

## Actual Backend and Costs

Metadata is obtained directly from RenderingServer and DisplayServer. The
requested backend must equal the actual method for the v4 report to pass.

| Field | Metal | OpenGL Compatibility |
| --- | --- | --- |
| Actual method | `forward_plus` | `gl_compatibility` |
| Actual driver | `metal` | `opengl3` |
| Adapter | Apple M4 Pro (Apple9) | Apple M4 Pro |
| API version | 4.0 | 4.1 Metal - 91.7 |
| Display server | macOS | macOS |

| Metric | Metal mean ms | Metal p95 ms | OpenGL mean ms | OpenGL p95 ms |
| --- | ---: | ---: | ---: | ---: |
| Player CPU advance | 33.981 | 37.753 | 33.467 | 38.214 |
| Same-frame CPU work | 36.638 | 46.632 | 36.072 | 47.318 |
| Host process | 2.655 | 11.036 | 2.604 | 11.010 |
| Render wait | 2.331 | 2.773 | 5.093 | 9.735 |
| Observer work | 5.485 | 6.344 | 5.405 | 6.642 |
| Complete-frame wall | 44.540 | 54.423 | 46.643 | 58.896 |

The Player timer wraps `advance_action_frame()` on the main thread. It
includes synchronous subscribers, including automatic recording, and is not
a pure movement-only timer. Frame-work wraps Player plus host processing.
Complete wall time additionally includes physics/render waits and observer
work. Render wait is a frame synchronization observation, not a direct GPU
execution timer. These quantities must not be combined as GPU milliseconds.

OpenGL Player mean is 1.51% lower in this bounded pair; complete wall mean
is 4.72% higher. Switching backend does not remove the roughly 33-34 ms
main-thread Player cost. CPU state handling and synchronous recording are
the next profiling targets. This evidence does not identify the dominant
individual function yet.

Each sample observes one Actor and one threat, zero projectiles, zones,
constructs, or summons. Process RSS peaks are 1,385,791,488 bytes for Metal
and 1,640,366,080 bytes for OpenGL, with 1,238 and 1,187 valid samples;
Metal has one unavailable process-end sample. These are whole-process debug
observations, not renderer-only allocation measurements.

## Retained Physical Evidence and Limits

| Artifact under frozen clone | SHA-256 |
| --- | --- |
| `build/phase2-metal-120/report.json` | `642b32d72822cfc9d94d7956dd4fe1fb3678c9f0af87761cade2dfa20cc2cf9f` |
| `build/phase2-metal-120/source-manifest.json` | `f03f3f83f5ec43505d2d81b90563bd4fec6d11d209c612586e2cc35740ffaa6d` |
| `build/phase2-opengl-120/report.json` | `b4285636e4a5bbbbbc236f881ada16e6a6c80e80947f8e8388cfda88b33d0e2d` |
| `build/phase2-opengl-120/source-manifest.json` | `207964c0c991b84ef44327c8d5cd309292ceaf4db2c8bf403b4c2ea37dcc3ece` |

Each reloaded recording contains 121 observations, exactly 120 measured
samples, `INTERRUPTED` status, and byte-exact first/last endpoints against its
own actual in-memory observation. Endpoint hashes differ between runs because
recording/run identity is independently created; cross-run byte equality is
not claimed. Metal endpoints are
`8b7b8ab43674e54121d4568336b5ae14de29b4a9a522acc5c2743a64b83dfe11` and
`196d184f40a5185c08ba7cd115c7141374372fe997ae0c7a4bea3cfc9f9bae66`.
OpenGL endpoints are
`1652e536e3b8aa5750ddd2c79a57992e7bda4e682b5c9115b5758c561e51c61d` and
`7e766c230024eb77f6579eeb0f8cf4f084dd8df7af05fdb34d0c23943f5ada7f`.

Both backends launch and complete the bounded native workload on this Mac.
The result does not establish a general Mac incompatibility, certify other
Macs or Windows/Linux, or exclude Mac-specific CPU behavior. It is one
120-frame run per backend, not repeated randomized benchmarking, release
build performance, peak-density coverage, sustained 60 FPS, a 45-minute
soak, an unassisted victory, or human testing. Both complete-frame costs
remain above 16.667 ms. Final performance certification remains open.
