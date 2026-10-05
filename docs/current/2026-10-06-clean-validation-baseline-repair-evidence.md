# Clean Validation Baseline Repairs

- Status: Focused Verified / Complete validation pending
- Document Role: Current focused implementation evidence
- Authority Level: Below the approved full-product completion specification
- Applies To: Native fixtures, refusal diagnostics, corrupted-input recovery and retained clean validation
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
Full Main certification was pending at that interruption. Later native victory
and settlement evidence is retained separately in
`2026-10-06-native-five-floor-victory-evidence.md`.

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

## Phase-Shift Checkpoint Audio Teardown

The broader save regression run retained 25 passing scenes and one strict
failure in `native_phase_shift_checkpoint_test`. Its assertions printed PASS,
but both independent logs recorded `ERROR: Player is inactive` at the test's
`_dispose` override when it queried a stopped MusicDirector deck.
The original RED remains at
`build/replay-cache-save-regressions/tests__integration__save__native_phase_shift_checkpoint_test.stdout.log`
and its adjacent `.godot.log`.

The fixture now uses the existing event teardown pattern:
`has_stream_playback()` guards acquisition of each weak playback reference.
All physical Ranger landing, checkpoint continuation, ordinary Sword, paid
Rewind and historical schema assertions remain. The asynchronous playback
release wait and final release assertion also remain unchanged. Production
audio behavior and the global log policy are unchanged.

Three focused reruns passed strict stdout and independent engine-log checks:

- `build/test-evidence/phase-shift-audio-cleanup-green/phase-shift/`: 1/1
- `build/test-evidence/phase-shift-audio-cleanup-green/natural-elite/`: 1/1
- `build/test-evidence/phase-shift-audio-cleanup-green/hound-sigil/`: 1/1

The adjacent scenes exercise the same inherited physical checkpoint fixture.
These ordinary scene runs do not measure runtime line coverage or certify the
complete product. The immutable `be58030` validator retained this pre-repair
failure on its original source; its completed result is recorded below.

## Completed Frozen be58030 Baseline

The detached `build/retained-checkout/certify-be58030` checkout completed its
entire ordinary validator at revision
`be580300a80888882d70dff5ac0863c3ed7359d6`, without source overlays. Its final
Git status is clean. The 408 runtime scripts retain aggregate SHA-256
`acf7d0096c540baf5bec4ed336b1ae03f9f0c0e4445515368fc84b73e921da30`.

Python/CI, documentation, localization/content, export and coverage contracts,
both Godot imports, native content-pack export contracts and the 30-seed dungeon
simulation passed. All 485 discovered ordinary scenes completed: 481 strict
PASS, four strict failures, zero timeouts. Each failed scene printed successful
assertions but retained unexpected engine errors in both independent logs:

| Scene | Retained strict failure | Current repair evidence |
| --- | --- | --- |
| `native_phase_shift_checkpoint_test` | Inactive audio playback query in teardown | `49e8101`, three focused GREEN scenes above |
| `run_orchestrator_test` | Two unscoped intentional BuildState rollback errors | Exact test scopes, five focused GREEN scenes below |
| `input_profile_store_test` | Corrupted-file `JSON.parse_string` engine diagnostics | Structured parser, five focused GREEN scenes below |
| `input_remap_service_test` | The same corrupted-file parser diagnostic during legacy recovery | The same focused parser repair below |

The actual five-floor Main scene and all 150 P14 domain loadout combinations
passed. The effective Main timeout was 7,200 seconds; the P14 loadout matrix
minimum was 600 seconds. These are execution caps, not measured gameplay or FPS
results. Neither scene timed out. The runner's generic timeout text would print
the configured 300-second value rather than a scene's raised cap.

Top-level stdout remains at
`build/certification-be58030-validation.stdout.log`, SHA-256
`2e5deb9408bed0f8c1feb3073e2d834437de9bebce775dcb1671df877c8118e6`.
All paired scene logs remain in the checkout's
`build/clean-validation/scene-tests/`. The full validator exits 1 and never enters
instrumented line coverage. Its ordinary coverage report has
`status=unavailable`, no provider, and `line_rate=null`; it is not zero measured
coverage or full-suite coverage evidence. This is a completed failed historical
baseline, not certification of the later integrated source.

## Orchestrator Integrity Refusal Scope

Current-source RED at `build/test-evidence/orchestrator-refusal-scope-red/`
reproduces both deliberate unrecoverable BuildState rollback diagnostics. Its
assertions pass, but strict stdout and Godot-log validation correctly fails.

Only the fixture changes. Each failing command now uses the existing exact
`TestSuite.expect_engine_error` Callable with its original error message, one
occurrence, and the command's actual `ok=false` response. Both original
`INTEGRITY_FAILURE`, rollback-stage and consumed-offer assertions remain. The
production Orchestrator and global log policy are unchanged.

Focused GREEN under
`build/test-evidence/orchestrator-refusal-scope-green/` passes both strict logs:

- `orchestrator/`: 1/1 Orchestrator scene, including both rollback scopes
- `facade/`: 1/1 RunRuntimeFacade scene
- `state/`: 3/3 RunState, merchant state and dungeon-event state scenes

The five successful scenes do not replace the four failures retained in the
original frozen validator or establish runtime line coverage.

## Corrupted Input JSON Recovery

Current-source RED under `build/test-evidence/input-corrupt-json-red/` reproduces
both frozen input failures independently in `profile/` and `remap/`. The
fixtures deliberately write malformed primary or backup files and correctly
recover a verified profile, but `JSON.parse_string` emits engine errors for the
malformed text. Both assertion sets pass while both strict scene runs fail.

`InputProfileStore._load_candidate()` now uses a `JSON` instance and checks its
`parse()` status before reading Dictionary data. A parse failure or non-object
root returns the original `CORRUPT` result and `reason=json`. The existing
normalization, schema validation, recovery order and migration path remain.
No expected-error scope or global error suppression is added for corrupt data.

Existing tests remain unchanged. Five focused scenes under
`build/test-evidence/input-corrupt-json-green/` pass both strict stdout and
Godot-log validation:

- `profile/`: 1/1, including corrupt primary/backup recovery across schemas 1-4
- `remap/`: 1/1, including atomic legacy recovery and migration
- `codec/`: 1/1 input-binding codec
- `actions/`: 1/1 input action contract
- `panel/`: 1/1 actual input remap panel

Verified-primary preservation, explicit recovery/migration provenance and
applied keyboard/controller bindings retain their existing assertions. These
focused results repair the later source; the immutable failed baseline and
full integrated validation/coverage boundary remain as recorded above.
