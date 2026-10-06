# Coverage Fixture Fixes Evidence

- Status: Implemented / Focused verified
- Document Role: Current test-fixture stability fixes discovered by instrumented runtime coverage
- Authority Level: Below approved full-product completion contract
- Applies To: Replay backpressure, reward smoke and Void candidate fallback fixtures
- Owner: Project integration lead
- Depends On: [Gameplay completion plan](../superpowers/plans/2026-10-06-gameplay-ui-product-completion.md)
- Last Verified: 2026-10-06
- Certification Status: Does not certify full coverage, gameplay completion, performance, UI or human playtesting

## Failures Found

The retained coverage checkout at `9738bc5424d9659b3b6b1cbbe479908ea62542ad`
ran the unchanged scene suite with the runtime line provider. Two tests failed
under instrumentation:

- `native_run_replay_backpressure_test` waited for the background writer's
  physical promotion callback for 600 process frames. The recorder worker was
  slower under AST wrappers and never reached the callback before the fixed
  polling loop ended. Four prior uninstrumented retained runs of this same
  scenario passed.
- `reward_system_smoke` kept a `HealthComponent` reference while a full-charge
  bow arrow defeated the default target. `EnemyBase` removes the target from
  the enemy group and queues it for deletion after 0.2 seconds; the polling
  helper then read `current_hp` from the freed object.

These were test-harness failures. No production gameplay code was changed to
weaken recorder capacity, death retirement, ownership or validation behavior.

## Focused Fixes

`tests/replay/native_run_replay_backpressure_test.gd` now waits up to eight
wall-clock seconds and yields both a process frame and a 1 ms timer. It still
requires the injected callback and `pending_write` state, then retains the
original bounded backlog, single rejection, failed tape and 120-observation
assertions.

`tests/reward_system_smoke.gd` gives only the bow smoke target a 1000 HP
fixture. The same full-charge arrow still has to damage the live target,
restore time energy and create floating damage text; it simply cannot reach
the production delayed-death queue before those assertions complete.

## Verification

| Scope | Artifact | Result |
| --- | --- | --- |
| Backpressure ordinary scene | `build/backpressure-test-fixed` | 1 passed, strict pair pass |
| Backpressure instrumented scene | `build/backpressure-coverage-fixed/run.json` | provider status `pass`, runtime report 1 |
| Reward ordinary scene | `build/reward-smoke-fixed-1791256751` | 1 passed, strict pair pass |
| Reward instrumented scene | `build/reward-smoke-coverage-fixed-1791256906/run.json` | provider status `pass`, runtime report 1 |

The focused instrumented reports contain no `SCRIPT ERROR`, invalid-access,
ObjectDB or RID leak. The two modified scripts pass `git diff --check` and the
pinned GDScript AST parser. The complete coverage checkout remains an older
source identity and still has to finish its scene suite; these focused reports
do not convert it into a current full-coverage certificate.

## Void Candidate Fallback Fixture

The unchanged complete scene preflight at `d195fe7` finds a third fixture
failure in `void_burn_snapshot_query_test`. Its direct fallback call passes the
public `{ok, ticket, batch}` result to `_prepare_native_void_frame`, which
expects the prepared ticket itself. Missing `runtime_frame` and then missing
`ok` produce script errors even though the test prints its final PASS marker.
The strict paired log validator correctly rejects this result. The frozen
preflight remains unchanged and retains this failure.

The fixed test passes `result.ticket.duplicate(true)` to the fallback and
checks its internal success response separately from the public result.
It also compares the complete candidate ticket bytes before and after the
fallback, retaining the typed state, batch, independently owned arena preview
and rollback assertions. No production fallback or log rule is weakened.

Ordinary RED and GREEN evidence is retained in
`build/void-burn-fallback-fixture-red-20261006.log` and
`build/void-burn-fallback-fixture-green-20261006.log`; the latter passes 1/1 with
strict paired logs. The first instrumented attempt passes its scene but the
provider correctly rejects a concurrent original-source change in
`launch_hostile_actor.gd`. That refused report remains under
`build/void-burn-fallback-fixture-20261006/green-instrumented/`.

A separate stable Git clone at
`build/retained-checkout/void-burn-fallback-focused-20261006/` starts at
`bfa78a06c90ebc5244a7660c5eaa631ef79b63a9` and applies only this test correction.
Its `build/void-burn-green-instrumented/run.json` reports provider status
`pass`, one physical runtime report, 1/1 tested scene and verified original
source digests. Both scene logs pass strict validation. The run report SHA-256
is `37fe7eb8364953ae01116a11e661a5cdeef29ca3d239993814701c0d0ca1e02e`.
The changed fixture also passes the pinned GDScript AST parser and
`git diff --check`. The pinned development, coverage and production-art
requirements audit reports no known vulnerabilities in
`build/void-burn-fallback-fixture-20261006/dependency-audit.json`; no dependencies
change. This focused correction does not certify a complete scene
suite, full line coverage, FPS, final source or human playtesting.
