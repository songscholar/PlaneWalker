# Gameplay Engineering Preflight Evidence

- Status: In progress / Failed engineering preflight
- Document Role: Current gameplay and runtime coverage preflight evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Frozen gameplay scenes, native five-floor flow and source-bound diagnostic evidence
- Owner: Project integration lead
- Depends On: [Gameplay completion plan](../superpowers/plans/2026-10-06-gameplay-ui-product-completion.md)
- Last Verified: 2026-10-06
- Certification Status: Not a final clean-checkout, full-coverage, performance, visual-quality or human-playtest certificate

## Frozen Source

The preflight source is
`build/retained-checkout/gameplay-certification-d195fe7-20261006/`, at explicitly
authenticated revision `d195fe786f326fa89c913f1156a6abc972556f9e`. Its 599 scoped
runtime, scene, content and native-runner files still match the complete Git
tree. The runtime source SHA-256 is
`0a0f1413e94685c9d3887871d444751b91d871eb174baa0009cfb3de787dcf59`.
The 413 runtime scripts in the instrumentation manifest also retain their
original source digests; 411 contain executable statements.

This retained archive resolves Git through its parent repository. Its source
authentication is valid, but it is engineering preflight evidence, not an
independent checkout certification. Final certification must use a separate
Git clone of the final committed source and rerun every required gate there.
Every build path below is relative to this frozen preflight checkout unless
explicitly identified as a live-workspace correction.

## Complete Ordinary Scene Suite

`build/full-scenes-preflight-wrapper.log` retains the original full ordinary
result: **517 passed, 1 failed, 518 total**, process exit 1. Independent strict
stdout/engine-log validation agrees: 517 pairs pass and the sole failed pair is
`tests/integration/combat/void_burn_snapshot_query_test.tscn`. A final PASS text
does not override the runtime invalid-access errors in that test.

The live-workspace correction is commit `0db1352`, which passes the actual
prepared ticket to the internal Void fallback and retains its ownership,
immutability and rollback assertions. Focused ordinary and instrumented GREEN
evidence is documented in
[Coverage fixture fixes](2026-10-06-coverage-fixture-fixes-evidence.md).
That correction is not retroactively substituted into the frozen full-suite
result.

The original full scene suite also passes its 150/150 P14
character/weapon/time loadout matrix and its controller flow through all five
floors. The loadout smoke matrix proves the tested loadout workflow; it does
not stand in for the separate 750 native Boss-combat cases.

## Actual Five-Floor Flow

`build/p15-five-floor-native-run.json` reports `synthetic=false`,
`complete=true`, 21 rooms and 12153 accepted frames. The actual Main scene
defeats `ruin_king`, `forest_heart`, `time_sovereign`, `forge_colossus`, and
`void_throne`, reaches `shattered_freedom`, and verifies the physical
fresh-profile victory settlement. Its failure list is empty.

The ordinary report and the independently executed instrumented report at
`build/full-runtime-coverage-preflight/project-copy/build/p15-five-floor-native-run.json`
are byte-identical. Both have SHA-256
`a744f898fbf147a0f0a6b339175eafc539be6ab0ad68febe047c628d8f3e3b06`
and both stdout/engine-log pairs pass strict validation.

The report declares `survival_fixture=p15_full_run_survival_fixture`,
`unassisted_victory=false`, and `human_playtests=0`. It proves actual native
room, combat, route, ending and physical settlement integration under that
fixture. It does not certify difficulty balance or a real player completing
the game without assistance.

## Native Boss Cases

The source-bound first canonical pilot reaches final Boss HP 0 after 797
accepted frames, with report SHA-256
`8d1f68b9d740e42d9f37953a51ad72411781a9f15995495808d93b16baed3d8d`.
The historical case 338,
`void_walker|bow|stop+rift|forge_colossus`, passes after 2051 frames with all
three authored damage phases, two paid Time casts, a cold restoration and
exact continuation. Its report SHA-256 is
`1a2bfa15706f155f697a236fee03d361a4dbfd6ba97fe1419a7e17561b264335`.

The complete 750-case request was deliberately stopped while performance work
continued. Exactly 63 individually validated source-bound receipts remain
under `build/native-750-logs/`. There is no complete 750-case aggregate and no
750/750 success claim. These receipts cannot be resumed against changed
runtime source or mixed into a later source's certificate.

## Instrumented Preflight

The original complete instrumented suite has finished against the authenticated
frozen source. Its log is
`build/full-runtime-coverage-preflight/scene-suite.stdout.log`. Strict aggregate
validation reports **512 passed, 6 failed, 518 total**. The six failures are the
unchanged Void fixture runtime error and five bounded 300-second timeouts:
`local_run_records_test`, `native_combat_checkpoint_test`,
`native_content_migration_test`, the five-floor `p14_controller_flow_test`, and
the 150-case `p14_dungeon_loadout_matrix_smoke_test`. The failed run report is
retained at `build/full-runtime-coverage-preflight/run.json` with status
`failed`; no partial hit union is promoted to a coverage certificate.

The Void failure is a fixture contract mismatch (`runtime_frame` and `ok` are
read from the public wrapper instead of its prepared ticket). Its exact paired
logs retain the two invalid-access errors. The five timeout pairs contain no
script or engine runtime errors; their processes were terminated at the stated
budget. The completed 512 scenes retain 513 physical runtime-hit reports, and
the instrumented manifest remains authenticated at
`5413dfd3367e8daeb207d3391e8cb84ca3f34dc3492ac9351c0794b329996b54`.

Unchanged 900-second diagnostics reuse the exact same instrumented project and
original-source manifest. All three save tests pass their complete assertions,
strict log pairs and physical runtime-hit validation. Their respective
covered original-line counts are 6354, 32088 and 28197, each with one physical
process report. The live-workspace runner fix, commit `3ae8804`, grants only
these three instrumented scenes a minimum 900-second budget while preserving
their ordinary budgets and all assertions. Its complete coverage contract
suite passes 16/16. See the fixture evidence for exact diagnostic paths and
RED/GREEN artifacts.

The unchanged controller workflow also passes its own 900-second diagnosis,
with one physical runtime report covering 29601 original lines and a strict
log-pair pass. A separate live-workspace follow-up gives this verified
instrumented scene the same 900-second minimum while keeping its ordinary
300-second budget. It is applied only after confirming that no main-workspace
scene runner is active. The complete coverage contract suite with all four
budgets passes 17/17, with a fresh dependency audit finding no known
vulnerabilities. Exact artifacts are listed in the fixture evidence.

The independent P14 dungeon matrix diagnosis reused the exact instrumented
project and manifest with a 900-second budget. It reached 120/150 real
character/weapon/time workflows before the watchdog terminated it, with no
script or engine errors in either paired log and no physical report because the
process did not exit normally. Its retained RED evidence is under
`build/p14-dungeon-instrumented-rerun-20261006/`; it is a timing diagnostic,
not a successful matrix or coverage result.

These focused passes do not repair the original full run. A partial union of
runtime reports is diagnostic evidence only; neither scene success counts nor
an incomplete line-hit union may be presented as full coverage.

## Remaining Gates

The final committed revision still requires complete ordinary and instrumented
validation, source authenticity, export/startup, replay and save migration,
controller and resolution QA, performance and local distributable verification
in an independent Git clone. The 16.667 ms performance budget has not been
certified by this preflight. UI/art completion is tracked by the presentation
lanes, and human playtesting remains zero.
