# Replay Safety Leaf Traversal Evidence

- Status: Focused Verified / Full gameplay performance pending
- Document Role: Current retained behavioral and local cost evidence
- Authority Level: Below approved full-product completion contract
- Applies To: Generic Replay value verdicts and authenticated native snapshot cost
- Owner: Project integration lead
- Last Verified: 2026-10-06
- Depends On: `2026-10-06-replay-safety-leaf-plan.md`

## Retained Behavior

Only `ReplayRecorder.replay_value_is_safe()` changes. Godot 4.6.1's existing
NIL-through-STRING_NAME whitelist is handled directly, including finite checks
for every Float. Array and Dictionary primitive leaves avoid recursive calls;
nested containers and Packed values retain the complete prior rules. Dictionary
iteration no longer allocates a keys Array. There is no shared state, cached
verdict, schema, digest or format change.

The new scene covers every `TYPE_MAX` category at the root and inside Array,
Dictionary and mixed containers. It retains allowed keys, rejected keys,
mutable/Packed alias rechecking, freed Object refusal despite equal null
serialization, empty Object-typed containers, 48 nested levels, nonfinite
geometry's existing verdicts and concurrent worker calls. Behavioral baseline
and candidate each pass 1/1 with matching strict stdout/engine logs:

- `build/replay-safety-leaf-behavior-before/`
- `build/replay-safety-leaf-behavior-green/`

Neighboring scenarios pass 12/12: ten `run_replay` scenarios, one
`native_recording_snapshot` scenario and one `full_player_replay` scenario.
Their directories are `build/replay-safety-leaf-run-replay-regressions/`,
`build/replay-safety-leaf-native-recording-regressions/` and
`build/replay-safety-leaf-full-player-regressions/`. Both logs of each individual
scene pass `runtime_log_validation.py --test-suite-scopes`; exact declared
refusal diagnostics remain permitted only within their completed test scopes.
Two independent read-only reviews found no actionable issues in this slice.
An additional independent run of the complete new scene passes 1/1 with both
strict logs at `build/test-evidence/replay-safety-leaf-independent-green/`;
its Recorder and test hashes exactly match the retained candidate below.

## Actual Physical Snapshot Cost

The build-only diagnostic authenticates compressed/raw hashes from the actual
failed native tape, then measures its frame-2501 native keyframe. It contains
106,244 typed bytes with SHA-256
`dec318dc43a2f7777413b0b48c04ab7acc3e3835a5f577315ba80e81db49cd7c`.
Typed input bytes are unchanged after all operations. Each measurement uses 20
actual calls on the same machine and engine, with strict clean runtime logs.

| Operation | Original Mean us | Candidate Mean us | Original Median us | Candidate Median us |
| --- | ---: | ---: | ---: | ---: |
| Native safety traversal | 3475.85 | 1061.70 | 3476 | 1055 |
| Complete native validation | 5918.85 | 3525.20 | 5467 | 3066 |
| Complete Player safety traversal | 39778.70 | 12932.95 | 39694 | 12899 |

The focused <=2,000 us local native-safety gate is RED before and GREEN after.
This measures one authenticated snapshot, not FPS, sustained throughput or a
portable CI wall-time requirement. The 49 diagnostic verdict checks are
fixture checks, not 49 different Variant categories.

All artifacts remain under `build/native-cold-cost-20261006/`. The original
candidate JSON was recovered structurally from the unchanged original stdout
after a later run reused its old output filename. Both original stdout and
engine logs remain intact. The diagnostic now refuses existing output paths.
The initial `--script` attempt failed to load project autoloads and is retained
as a failure; only normal scene-entry runs count toward this evidence.

| Retained Source or Artifact | SHA-256 |
| --- | --- |
| Original Recorder at `f013a6f` | `4347869f62ef7ee2df48a2bd400fa7565a24b1db095ac36ea4e5264766d6ab90` |
| Candidate Recorder | `c1f456ae25c203b1fee6b4aab3d422b4ebad5c31b3113aaa010698d5ddc28f98` |
| Behavioral test | `8d0a0757b1e788631f04d01c3aaa22cd52f432214c8d1e5a176cab3a00b28bf5` |
| `original-candidate-report.json` | `e75387c91166e8ac0204490cb016995a4f1bae4b5a872f19572fa989e5e3b7be` |
| `production-green-report.json` | `b828ae83cfaaf19e6a7d5614ca89470d27e9c5bff2ca2623ec0089f05687cbf2` |
| Final diagnostic `probe.gd` | `0b29c500443f275a48e19b217deb0f51ead489c22b3642420046813556c4868d` |

## Remaining Gates

Uninstrumented complete native frames must be remeasured on the integrated
committed source. Complete native matrix, clean validation, line coverage,
rendered performance, 45-minute recording, load/memory tests, UI polish and
human playtests remain separate gates. Human playtests remain 0/20.
