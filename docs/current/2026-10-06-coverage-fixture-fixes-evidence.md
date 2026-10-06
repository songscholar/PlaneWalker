# Coverage Fixture Fixes Evidence

- Status: Implemented / Focused verified
- Document Role: Current test-fixture stability fixes discovered by instrumented runtime coverage
- Authority Level: Below approved full-product completion contract
- Applies To: Replay backpressure and reward smoke fixtures
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
