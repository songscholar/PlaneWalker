# GDScript Line Coverage Gate

- Status: Runtime provider implemented; full-suite certification active
- Last Verified: 2026-10-05
- Verified Engine: Godot `4.6.1.stable.official.14d19694e`

## Measurement definition

Plane Walker accepts only GDScript **line coverage** backed by runtime line
hits. The denominator is the provider's set of executable source lines. The
numerator is the subset observed during test execution. Every file is tied to
the exact tested source through SHA-256.

The following are deliberately rejected as coverage:

- passed scene count;
- discovered test count;
- script load or parse count;
- Godot `--profiling` timing totals;
- aggregate percentages without per-file executable and covered line sets.

## Godot 4.6.1 capability evidence

The installed editor build exposes `--debug`, `--breakpoints`, and
`--profiling`, but `godot --help` exposes no line-coverage output option. A
headless test run with `--debug --profiling` prints timing output ending in an
`ACCUMULATED` total; it does not emit executable lines or line-hit counts.
Therefore the stock binary cannot produce the evidence required by this gate.

Reproduce the capability check with:

```bash
godot --version
godot --help | grep -E -- '--coverage|--profiling|--breakpoints'
```

## Collector behavior

`collect_gdscript_coverage.py` always writes an atomic JSON report. Without a
trusted provider report it exits `3` and records `status: unavailable`. This is
a normal test-run outcome but remains a certification blocker. An invalid or
stale provider report exits `4` and fails the test runner.

`tools/run_tests.sh` retains the report as:

```text
$TEST_LOG_DIR/gdscript-coverage.json
```

Detached checkout certification reads that artifact directly, verifies the
trusted collector identity, provider-report digest, line sets, derived counts,
per-file rates, and source digests against the detached checkout. It ignores
stdout claims such as `Code coverage: collected` when the artifact is absent,
inconsistent, or attributed to a different collector.

## Runtime Provider

`instrumented_provider.py` uses pinned MIT-licensed `gdtoolkit` 4.5.0 to identify
executable statement lines in every script under `autoload/` and `scripts/`.
It copies the project, imports twice, installs a counter through Godot's native
`ConfigFile`, instruments only the copy, and runs the existing scene runner.
The copy excludes Git, imports, build outputs, generated translations and
Python caches. Symbolic links and occupied evidence directories are refused.

Statement starts and evaluated class/static/onready initializers form the
denominator. Comments, blank lines, compile-time constants, declaration heads
and structural delimiters do not. Multiline statements belong to their
statement-start line. Unexecuted scripts remain in the report with zero hits.
Per-script constant names preserve inherited GDScript classes, and the counter
exits after existing autoloads so cleanup lines are observed. Invalid syntax,
runtime failures, leaks, stale manifests, unknown hits and changing original
sources refuse measurement. Tests cover actual Godot execution, inheritance,
inferred property types, branches, loops, lambdas, input-event configuration,
autoload cleanup and intentionally unvisited code.

The shared line set uses a Godot Mutex for native recording workers and the main
thread. A real five-thread regression retains all 20,000 distinct line IDs; the
unlocked collector lost IDs and aborted in the native dictionary implementation.
Exit snapshots the protected set before serialization. Instrumentation affects
timing, so its recording stress results do not certify uninstrumented throughput.

Provision and run inside the repository:

```bash
python3 -m venv build/toolchain/gdscript-coverage-venv
build/toolchain/gdscript-coverage-venv/bin/python -m pip install -r requirements-coverage.txt
build/toolchain/gdscript-coverage-venv/bin/python -m tools.coverage.instrumented_provider \
  --output-dir build/coverage/full-suite
```

The evidence directory must be empty or absent. It retains the isolated project,
exact original-source manifest, per-process physical hits, per-scene logs, raw
provider report and normalized `gdscript-coverage.json`. `--filter` is available
for focused development checks; a filtered result does not certify full-suite
coverage. The tool checks source hashes against the original project after
execution, so measure an immutable committed checkout during parallel work.

To run both the uninstrumented suite and the complete instrumented suite through
the validation/certification path, set an absolute provisioned interpreter:

```bash
GDSCRIPT_COVERAGE_PYTHON="$PWD/build/toolchain/gdscript-coverage-venv/bin/python" \
  ./tools/validate_project.sh
```

Detached certification inherits that explicit environment setting and runs the
provider against its own checked-out sources. It verifies the normalized report
through the existing collector. Without the setting, coverage remains honestly
unavailable; an installed provider alone does not prove its full test gate passed.

## Provider Contract

A provider must run the test scenes with runtime instrumentation and
write schema `1.0.0` JSON containing:

- `language: GDScript` and `metric: line`;
- provider name, version, and `mode: instrumented_runtime`;
- a non-empty `files` list;
- project-relative `.gd` paths and source SHA-256 values;
- non-empty `executable_lines` and subset `covered_lines` for every file.

Pass the raw provider report to the runner with:

```bash
GDSCRIPT_COVERAGE_PROVIDER_REPORT=/absolute/path/provider-report.json \
  TEST_LOG_DIR=/absolute/path/test-logs \
  ./tools/run_tests.sh
```

P7/P9 clean checkout certification remains pending until the full runtime
provider and the other export/startup gates pass on the exact committed revision.
