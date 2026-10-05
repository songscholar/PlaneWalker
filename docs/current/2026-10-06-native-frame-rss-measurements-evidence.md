# Native Same-Frame and Process RSS Measurement Evidence

- Status: Focused Contracts Verified / Actual native probe pending
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
At this candidate checkpoint, actual native verification is still pending.

The existing native750 matrix runs on its own untouched `abd5b6f` archive and
is unaffected. This change collects evidence; it does not lower any frame,
storage, entity or memory budget, and `fps_certified` remains false. Rendered
performance, 45-minute recording, saturation, category memory budgets and
authentic human playtests remain separate gates.
