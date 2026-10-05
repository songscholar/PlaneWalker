# Threaded Runtime Coverage Evidence

- Status: Focused Verified / Full measurement active
- Document Role: Current verification infrastructure evidence
- Authority Level: Below the full-product verification contract
- Applies To: Exact-source runtime line collection during background replay writes
- Owner: Project integration lead
- Depends On: `../superpowers/specs/2026-10-05-p22c-streamed-run-replay-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Real concurrent line marks retain every distinct hit and existing provider regressions pass

## Finding And Fix

Automatic replay adds a native Godot Thread. The previous coverage collector
mutated one shared Dictionary from all executing threads without protection.
A real four-worker plus main-thread fixture requested 20,000 distinct line IDs.
The RED retained 19,050 and aborted with exit -6 and a native recursive-mutex
exception during Dictionary teardown. This invalidates unlocked concurrent
coverage, regardless of a scene's apparent pass output.

The collector now uses a Godot Mutex around updates and copies the protected
set before exit serialization. No application runtime or line denominator is
changed. The actual concurrent fixture retains the sorted IDs 1 through 20,000
exactly, with clean engine output. Existing real-runtime instrumentation,
isolated-copy, inheritance, autoload cleanup, malformed-hit and source-binding
tests also pass: 6/6 in
`tests.contract.coverage.test_instrumented_provider`.

## Limits

This proves the collector's concurrent integrity; it does not prove full-suite
coverage or its threshold. Complete measurement must use an immutable committed
checkout. Instrumentation changes execution timing, so capacity and sustained
recording throughput require separate uninstrumented evidence.
