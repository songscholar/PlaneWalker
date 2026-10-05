# Native Actor Candidate Construction Evidence

- Status: Focused Verified / Integrated performance pending
- Document Role: Current gameplay performance evidence
- Authority Level: Below AGENTS.md and native performance probe specification
- Applies To: LaunchHostileActor frame candidate construction and ownership
- Owner: Native observation lane
- Last Verified: 2026-10-06
- Depends On: `docs/current/2026-10-06-native-actor-candidate-plan.md`

## Change and Preserved Boundaries

`prepare_launch_frame` now calls one private `_actor_frame_candidate` helper.
It constructs the after dictionary in the original field order using the fresh
runtime/status/position/knockback/credit and optional affix-runtime replacements.
It separately deep-copies unchanged weapon claims/order, metadata, room motion
and optional affix configuration. Scalars and deliberately shared Node identities
retain their original types and values.

The production change owns only `launch_hostile_actor.gd`. It preserves every
complete outward/retained ticket and batch deep copy, full ticket equality,
typed restore validation, all Boss postprocessing, commit/rollback/publication,
schemas, history capacities and gameplay values. BossActor, BossRuntime and
Bridge remain outside this slice's ownership. UI production remains unstarted.

## Actual Behavioral Receipts

The actual native scene is
`tests/integration/combat/actor_frame_candidate_test.tscn`. It instantiates an
ordinary Shattered Sentinel, Shielded Sentinel, all five authored Boss actors,
and an additional ordinary body with a real blocking collider. Every actor binds
its validated native room, real burn source/attacker Nodes, weapon claims, nested
metadata and populated sequence/knockback/credit values.

For each actor, three actual frames compare complete typed before/after bytes
against the original deep-copy-and-replacement construction. This covers 24
prepared/compensated/retried/published frame workflows. It verifies unchanged
live authority before commitment, exact after installation, complete compensation,
deterministic retry fields and refusal to reuse a published ticket. Actual body
contact retains the exact collider Node. Burn entry copies retain the exact live
source and attacker Nodes; deep container copying must not clone these objects.

Mutating actual returned before, after, batch and Health branches cannot change
the retained ticket or live actor. Before/after siblings and returned batch/ticket
batch remain independent. Complete equality refuses forged candidates while the
pristine independently retained ticket stays accepted. The actual constructor is
also exercised before the outward copies: nested unchanged metadata, room bounds,
weapon claims/order and affix ids/pending arrays remain independently owned.

Retained commands and outcomes:

| Receipt | Result | Runner stdout |
|---|---|---|
| Initial fixture setup | Failed; invalid enemy-kind and unsupported room catalog lookup | `build/native-actor-candidate-20261006-baseline.stdout.log` |
| Corrected original construction | Actual scene PASS before production edits | `build/native-actor-candidate-20261006-baseline-acceptance.stdout.log` |
| First candidate | Actual scene PASS | `build/native-actor-candidate-20261006-candidate.stdout.log` |
| Final strengthened candidate fixture | Actual scene PASS | `build/native-actor-candidate-20261006-final.stdout.log` |
| Eight focused neighbors | Eight actual scenes PASS | `build/native-actor-candidate-20261006-neighbors.stdout.log` |
| Retrospective final fixture against original Actor | Exactly eight missing-constructor assertions; all behavior assertions pass | Frozen original checkout receipt described below |

The initial fixture failure is retained and is not optimization RED evidence.
The explicitly selected construction-microbenchmark alternative records a valid
original behavioral baseline and compares both constructors in the candidate
process. The final fixture additionally requires the actual new constructor to
exist and checks deeper affix-array ownership.

After implementation, the final strengthened fixture was copied unchanged into
`build/retained-checkout/actor-candidate-original-37d5918-20261006`, a Git archive
of commit `37d5918987b26823bf8e9955640074943c5c5d11`. Its Actor retains the
original `98341a4...` hash; only the new fixture/scene overlay the frozen source.
After resource import, the actual final fixture exits 1 with exactly eight
missing-helper assertions, one for each actual actor context. Both raw logs are
identical, no other assertion fails, and strict classification rejects every
additional engine/script/parse/leak error. This is retrospective detection
evidence collected after production implementation. The earlier baseline PASS
remains a PASS; this slice does not claim strict original RED-before-code ordering.
Subsequent slices require meaningful RED before production edits under AGENTS.md.

The first frozen attempt lacked ignored translation/resource import artifacts;
its failure logs and the first import's missing-translation diagnostics remain
retained. A second import validates cleanly before the accepted retrospective
run. These preparation failures are not treated as optimization RED.

The final command is:

```sh
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot \
TEST_LOG_DIR=build/native-actor-candidate-20261006/final \
  bash tools/run_tests.sh --filter actor_frame_candidate --timeout 120
```

The retrospective command from the frozen original checkout is:

```sh
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot \
TEST_LOG_DIR=build/native-actor-candidate-retrospective-red-acceptance \
  bash tools/run_tests.sh --filter actor_frame_candidate --timeout 120
```

The original working-tree runs resolved `/opt/homebrew/bin/godot` to this same
executable, Godot `4.6.1.stable.official.14d19694e`.

Neighbors are `launch_actor_transaction`, `launch_enemy_actor`,
`hostile_frame_bridge`, `launch_boss_actor`, `boss_frame_observation`,
`launch_elite_affix`, `launch_hostile_telegraph` and
`boss_control_visual_observation`. Each uses the same scene runner with
`TEST_LOG_DIR=build/native-actor-candidate-20261006/neighbors` and timeout 180.
The runner strictly validates paired stdout/engine logs; Bridge's deliberate
refusals are restricted to declared exact completed TestSuite error scopes.
No script/parse/leak failure is accepted. Statement coverage is not certified:
the engine reports `godot_line_coverage_unsupported`.

## Actual Constructor Measurements

The final scene calls the original algorithm and the actual private candidate
constructor 1,000 times each on the same actual prepared frame snapshots. It
asserts exact typed-byte parity, requires the constructor to be observable and
records `PLANEWALKER_ACTOR_CANDIDATE_MICROBENCH` receipts. There is no timing
threshold or FPS assertion. The candidate includes dynamic `actor.call` overhead;
the original uses the fixture's direct reference call. Original runs first.

| Actual actor | Original 1,000 calls (us) | Candidate 1,000 calls (us) | Replaced old branch serialized bytes |
|---|---:|---:|---:|
| Ordinary Sentinel | 9,652 | 4,972 | 2,564 |
| Shielded Sentinel | 12,496 | 4,183 | 3,356 |
| Ruin King | 15,464 | 3,410 | 4,852 |
| Forest Heart | 25,929 | 3,499 | 8,276 |
| Time Sovereign | 14,131 | 3,513 | 4,144 |
| Forge Colossus | 22,692 | 3,367 | 7,300 |
| Void Throne | 19,029 | 3,517 | 5,948 |
| Actual contact Sentinel | 9,265 | 3,325 | 2,564 |

These are local observations under concurrent native750/validation/performance
work. The byte column is serialized size of overwritten old branches, not
measured allocation or RSS. Fixture histories are the actual early frame boundary;
this does not certify late-run retained-history costs. Timing/order/contention and
call overhead prevent interpreting these measurements as integrated frame savings.
The integration lead retains ownership of committed-source frame distributions,
saturation, long recording, rendered tests and complete gameplay gates.

## Source and Receipt Identity

The original Actor at local base `37d5918` has SHA-256
`98341a4ab96d85855d368646c2b9b9abde3b34b8c3fbf9346078a400ad84c158`.
The slice's verified Actor has SHA-256
`6eb6b1cd6e5d1442395d58474442ef60326fd3c582c41d13097233261610a4ca`.
The corrected original/candidate fixture before final strengthening has SHA-256
`3c54289bd375986270b81c473c41e44d4b5f81ddb25aa0f4f5dcc27076b5e611`.
The final fixture has SHA-256
`abae55d82f3e983a108f4560320be53d30a38b505e2f91db379d21ccc7ae740f`;
its scene has SHA-256
`7d3b962aa8a35fc5f239c9710793bc268b389444e1f3a7c6ba34f949152b34fc`.

Each valid receipt directory retains
`tests__integration__combat__actor_frame_candidate_test.stdout.log` and
`tests__integration__combat__actor_frame_candidate_test.godot.log`.
Both files in `baseline-acceptance/` have SHA-256
`1da85f1f5455934aedafc49ad97e5dba0366c0192d228426bd83d5985d87ac83`.
Both files in `final/` have SHA-256
`9c2075dd28bebc0cbd1d4fbb63b490ae1a4158f7ece5ee986e5f1940cdfdfbcc`.
Both files in the frozen original checkout's
`build/native-actor-candidate-retrospective-red-acceptance/` have SHA-256
`0d61f8a2d0a8fd9a2c8970f8b27074cd659a209efb736d25267f8a1973f45230`.
Its `build/native-actor-candidate-retrospective-red-classification.json` records
eight exact missing-helper assertions, zero other assertions/errors, matched logs
and stable original Actor/final fixture source hashes. This classification permits
only those exact failing assertion headers; it is not a passing runtime receipt.
The neighbors runner stdout has SHA-256
`e6265c7af1d2970c9f857a542cdd7ba5eb2b442fd5c321ecbf4255fa4c92acec`.

`pip_audit -r requirements-dev.txt --format json` completed with no known
vulnerabilities; its report is
`build/native-actor-candidate-20261006/dependency-audit.json`.
No dependency was added. This is focused working-tree validation and does not
replace the integration lead's frozen committed-source final certification.

The independent validation lane reviewed the production diff and actual fixture
and found no actionable issues. It confirmed fresh replacement ownership, deep
copying of unchanged containers, original typed field order/shape, preserved
ticket detachment and exact commitment/compensation behavior. The focused result
remains construction evidence, not an FPS or UI-completion verdict.
