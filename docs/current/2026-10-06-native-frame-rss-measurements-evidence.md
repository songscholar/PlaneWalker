# Native Same-Frame and Process RSS Measurement Evidence

- Status: Focused Contracts and Actual Native Collection Verified
- Document Role: Current measurement implementation and verification evidence
- Authority Level: Below approved native performance probe specification
- Applies To: Native Main timing reports and sampled Godot process resident memory
- Owner: Plane Walker verification lane
- Last Verified: 2026-10-06
- Depends On: `docs/superpowers/specs/2026-10-05-native-performance-probe-design.md`
- Evidence Status: Verified Locally
- Certification Status: No FPS, memory budget, saturation, full gameplay or human certification

## Measurement Contract

The current probe adds `measurement_schema_version: 2` while preserving the
outer report schema and all production gameplay/recording authorities. Missing
measurement version denotes the historical version 1; its original four metrics
remain accepted. Unknown or incorrectly typed versions fail closed.

`frame_work` measures one continuous monotonic interval from Player advancement
through Host processing in that same accepted frame. `frame_wall` measures from
that same start through physics wait, optional real render wait and observer
validation. Each distribution is calculated from its actual frame intervals;
independent segment percentiles are never summed. Counts must match the unique
accepted native frame count, totals must enclose their measured constituent work,
and summed frame-wall intervals cannot exceed the complete measured wall time.

Godot announces its own process id in stdout and retains it in the report.
A separate Python thread samples that exact id at a nominal 100 ms interval:

| Platform | Standard-library collection source | Unit |
| --- | --- | --- |
| Linux | `/proc/<pid>/status` `VmRSS` | KiB converted to bytes |
| macOS | `/bin/ps -o rss= -p <pid>` | KiB converted to bytes |
| Windows | `GetProcessMemoryInfo.WorkingSetSize` via typed `ctypes` | Bytes |

RSS metadata retains platform, exact source, process id, sampling scope,
interval, valid/failed sample counts, sampled peak bytes and the last collection
error. The scope is the Godot process after its PID announcement, including
admission and physical retention; it is not restricted to the measured combat
interval. A sampled maximum is not an unsampled operating-system high-water
mark. `MEMORY_STATIC` remains a separate Godot allocation measurement and cannot
substitute for missing process RSS. Version 2 refuses zero valid RSS samples or
a process identity inconsistent with the native report. No dependency is added.

## Retained RED and GREEN

The preimplementation log is
`build/native-measurements-schema-20261006/red/stdout.log`.
The original seven contracts passed. New acceptance exposed missing same-frame
metrics, absent RSS reader/sampler APIs, and ignored invalid measurement versions:
16 tests finished with four failed assertions and eight missing-contract errors.
These are measurement implementation gaps, not failed actual RSS measurements.

The implemented contract run is
`build/native-measurements-schema-20261006/green/stdout.log`:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  tests.contract.performance.test_native_performance_probe \
  tests.contract.performance.test_native_measurements
```

All 18 tests pass, including legacy reports, typed schema rejection, timing
enclosure, exact target-PID/platform units, invalid/missing memory samples and
failed-read accounting. Existing `subprocess.run` mocks and exit/log/source/
timeout/malformed-report retention assertions remain intact. A version-2 CLI
mock retains valid sampled metadata and changes an otherwise passing native
report to failed when RSS has no valid samples. These mocks do not certify an
actual Godot process or native Windows/Linux execution.

## Actual Native Follow-Up

After the focused candidate commit, freeze that precise source in a new
workspace archive, double-import it, and run actual ordinary combat:

```sh
GODOT_BIN=<project-local-official-godot> python3 -u \
  tools/p15/native_performance_probe.py \
  --output build/native-measurements-combat120/report.json \
  --frames 120 --hub-frames 12 --timeout 7200
```

Retain paired strict runtime logs, version-2 report, source manifest, real
actors, both new 120-sample distributions, exact physical recording endpoints
and actual RSS sampling metadata. Ambient native matrix and full-validation
workers must be disclosed; no isolated performance improvement is claimed.
The focused candidate was retained in `e7ce2c1` and tested without overlays at
`build/retained-checkout/native-measurements-e7ce2c1-20261006`.
Fresh import one emitted 88 exact configured missing-translation messages for
11 valid catalogs. Its stdout and engine error lists are identical, the existing
bootstrap classifier leaves zero residual errors, and import two passes strict
paired-log validation.

The actual probe command above exits zero. Both native stdout and engine logs
pass `tools/runtime_log_validation.py`; no script, engine error or object/RID
leak occurs. The uninstrumented source manifest records stable runtime bytes,
no timeout and aggregate SHA-256
`1b12c8ca4d09490ba9aa58e692f4d0767531eedff87f74bd670daa74acf3dfe2`.
The archive has no independent Git metadata, so the report honestly leaves its
embedded revision empty; the retained archive identifies the source commit.

The production Main launches seed 4, Wanderer/Sword, Stop+Accelerate and reaches
floor-zero combat node `layer_01_a`, with three real actors and one threat. All
120 requested frames are accepted exactly once, frames 1 through 120, at native
60 Hz and unit time scale. Headless fixed-fps wall acceleration is explicit.
The physical tape retains 121 observations, honestly `INTERRUPTED`, no recording
failure, and exact fresh physical reads of both complete native typed endpoints.

| Actual Measurement | Mean | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Player advancement | 10.047 ms | 16.021 ms | 28.287 ms |
| Same-frame Player + Host interval | 10.554 ms | 16.418 ms | 28.819 ms |
| Same-frame wall interval | 11.794 ms | 17.911 ms | 30.802 ms |

Measured native duration is 2 seconds and measured wall duration is 1.415473
seconds. Exact physical retention takes 1.025984 seconds. macOS Godot PID 99265
has 70 valid RSS samples, zero failed samples and a sampled peak of 720,453,632
bytes from `ps.rss_kib`. The distinct Godot static-allocation peak is
403,728,245 bytes. RSS includes process admission/Hub/retention in its declared
scope, so the two peaks are not category-equivalent measurements.

The actual report SHA-256 is
`8d842917f7b22686c535d0977ae42ea2fc7bb90d9ffe0c8c0c9034a21c370776`.
Its source manifest SHA-256 is
`21d30902328b3a8e29bd2745edb94506fd267f164e818c3aa6a343c98df83ab2`.
Probe Python/GDScript source digests are respectively
`e8f3b47fa13b7d2bacdf0274cf77bb57bd12b2ed86e32da17969d42d5ad42f09`
and `51911c8ef1b62c8e6efd0755612674f5e61d4004d5f2e6d476c0544f5a65f230`.
All artifacts are below the archive's `build/native-measurements-combat120/`,
including the ambient-process snapshot. Five native matrix workers and a clean
full-validation worker were active. This is collection verification under that
observed contention, not an isolated performance-improvement comparison.

The observed frame-wall p95 exceeds 16.667 ms. No FPS, rendering, sustained
45-minute, saturation or whole-game/category memory certification follows from
this 120-frame sample. Actual Windows/Linux RSS collection remains untested on
those native platforms; Python tests cover declared sources and Linux/macOS
reader contracts without mislabeling mocks as native execution.

Independent read-only review of `e7ce2c1` by the progress-validation and root
lanes found no actionable collector issue. They checked report compatibility,
same-frame intervals, exact target PID and units, Windows ABI and handle cleanup,
sampler finalization and failed-report retention. The full validator now includes
`tests.contract.performance.test_native_measurements` alongside the historical
performance contracts. All 45 tests in that exact validator contract batch pass;
the log is retained at
`build/native-measurements-schema-20261006/green/validator-contracts.stdout.log`.

The existing native750 matrix runs on its own untouched `abd5b6f` archive and
is unaffected. This change collects evidence; it does not lower any frame,
storage, entity or memory budget, and `fps_certified` remains false. Rendered
performance, 45-minute recording, saturation, category memory budgets and
authentic human playtests remain separate gates.
