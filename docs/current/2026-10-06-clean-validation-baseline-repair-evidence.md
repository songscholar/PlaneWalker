# Clean Validation Baseline Repairs

- Status: Focused Verified / Complete validation pending
- Document Role: Current focused implementation evidence
- Authority Level: Below the approved full-product completion specification
- Applies To: Native combat damage fixtures, event teardown and retained clean validation
- Owner: Plane Walker integration team
- Last Verified: 2026-10-06
- Depends On: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`

## Retained Immutable Baseline

Detached checkout `build/retained-checkout/certify-c1a24d4` passed Python
contracts, both imports, native content-pack export contracts and the 30-seed
dungeon simulation. Its scene discovery found 478 tests. The baseline was
deliberately stopped after known failures; it is not a complete validation.

The retained top-level log is
`build/certification-c1a24d4-validation.stdout.log`; per-scene stdout and engine
logs remain under the checkout's `build/clean-validation/scene-tests`.
At termination the log recorded 196 scenes started, 188 completed OK and
seven non-OK records. Six are genuine baseline test failures:

| Scene | Failure | Focused repair evidence |
| --- | --- | --- |
| `p16_registry_activation_test` | Outdated counts and unreachable template closure validation | Registry fix `41403b1`, content schema suite 14/14 |
| `boss_rush_carried_test` | Detached Boss cleanup queried a missing world | Runtime fix `fe03eaf`, combined rerun 1/1 |
| `boss_wall_native_test` | Damage fixture used an unauthenticated target identity | Exact Boss identity, focused rerun 1/1 |
| `forest_auxiliary_native_test` | Damage fixture used an unauthenticated target identity | Retained identity constant, focused rerun 1/1 |
| `ruin_debris_native_test` | Damage fixture used an unauthenticated target identity | Exact Boss identity, focused rerun 1/1 |
| `production_event_encounter_test` | Teardown queried inactive music playback | `has_stream_playback()` guard, focused RED then GREEN 1/1 |

The seventh non-OK record is `p15_five_floor_run_test`, exit 143 after the
duplicate old-revision Main run was deliberately interrupted. This is not a
product failure verdict. The final started scene, `main_content_management_test`,
has no completion receipt because the whole baseline validator was stopped.
Full Main certification remains pending on a repaired immutable revision.

## Repairs Preserve The Assertions

The three combat helpers now address the authenticated Boss identity. Runtime
hit authentication, all phase transitions, wall/debris geometry checks and
actual sword/bow contact assertions remain intact. Forest's real weapon checks
pass without relaxing collision or damage validation.

Event teardown uses `has_stream_playback()` before acquiring a playback
reference. Its existing asynchronous release wait and final assertion still
require every active music playback to be released. The current-revision RED
contains `ERROR: Player is inactive`, despite the test's assertions reporting
PASS; the strict runner correctly refuses it.

Focused evidence directories:

- `build/test-evidence/native-damage-fixtures-green/boss-wall/`
- `build/test-evidence/native-damage-fixtures-green/forest/`
- `build/test-evidence/native-damage-fixtures-green/ruin/`
- `build/test-evidence/production-event-teardown-red/`
- `build/test-evidence/production-event-teardown-green/`
- `build/test-evidence/detached-boss-rush-combined-green/`

All five repaired-scene reruns pass stdout and independent engine-log checks
without script failures or leaks. Earlier RED logs are preserved.

## Coverage Boundary

The stopped baseline never entered the instrumented coverage phase. Ordinary
Godot scene runs truthfully report native line coverage as unsupported; their
generated inventory reports are not runtime coverage measurements.

The separate `c1a24d4` provider preflight instruments all 407 original runtime
scripts but executes only `seed_service_test`. Its 4,208/88,404 line hits
(4.76%) prove provider execution for that one scene, not full-suite coverage.
The report is retained at `build/coverage/c1a24d4-provider-preflight/run.json`.
Complete validation and actual full-suite coverage require a fresh committed
checkout containing the combined repairs and performance changes.

## Additional Facade Refusal Scope

The focused `run_runtime_facade_test` deliberately injects both Draft close and
authority rollback failure. Its `INTEGRITY_FAILURE` and retained committed
phase assertions passed, but its exact intentional engine error was unscoped.
The strict runner correctly rejected the RED retained at
`build/test-evidence/runtime-query-host-regressions/`.

The test now uses the existing `TestSuite.expect_engine_error` Callable with
the exact single message and returns the command's actual `ok=false`. Both
original command-code and phase assertions remain. The focused 1/1 GREEN at
`build/test-evidence/facade-expected-rollback-green/` passes both independent
logs. No Facade runtime behavior or global log allowlist changed for this fix.
