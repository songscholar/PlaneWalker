# GDScript Line Coverage Gate

- Status: Blocked on a trusted runtime instrumentation provider
- Last Verified: 2026-09-29
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

## Provider boundary

A future provider must run the test scenes with runtime instrumentation and
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

Until such a provider is checked in or provisioned reproducibly, P7/P9 clean
checkout certification must continue to report coverage as pending.
