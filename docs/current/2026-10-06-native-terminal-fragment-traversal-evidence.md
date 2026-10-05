# Native Terminal Fragment Traversal

- Status: Verified Locally / Full gameplay certification pending
- Document Role: Current native terminal interaction repair evidence
- Authority Level: Below the full product completion specification
- Applies To: Main terminal movement and authenticated narrative occurrence contact
- Owner: Project integration lead
- Depends On: [Gameplay then UI completion plan](../superpowers/plans/2026-10-06-gameplay-ui-product-completion.md)
- Last Verified: 2026-10-06

## Root Cause and Repair

The actual fragment sensor has radius 48. A Player's body can overlap that
sensor while its center is still outside the radius. NarrativeFlow submitted
the collection command at that first overlap, but the unchanged Profile
service correctly refused it with `OCCURRENCE_INVALID`: its authenticated
contact contract requires both overlap and a center distance at most 48.

That early refusal started the coordinator's existing 1000ms wall-clock retry
delay. At fixed 60 FPS, the 300-frame traversal test could finish before that
wall-clock deadline, even though the actual Player had reached and overlapped
the fragment. Under normal timing collection succeeded later, but the initial
legitimate approach still emitted the erroneous refusal.

`process_pending_contact()` now waits for both actual overlap and center
distance within `Service.OCCURRENCE_RADIUS` before submitting a command. The
Profile's complete receipt, source, room, token, run and Player authentication
checks remain authoritative. The wall-clock retry behavior is unchanged.
Terminal movement continues through the actual `NarrativeFlow` and
`CharacterBody2D.move_and_collide()` without advancing gameplay clocks.

## Focused Evidence

The new `main_terminal_fragment_traversal_test.tscn` uses explicitly synthetic
combat and Boss receipts to reach the production terminal flow quickly. Those
prerequisites are not combat certification. After terminal installation, the
test never teleports the Player: ordinary movement inputs take the actual
body from the authored `(160, 280)` entry toward the real Area2D fragment at
`(608, 180)`. Its existing physical collection command saves the fifth heart
fragment and opens the story panel. Input is released at completion.

| Check | Result | Retained Evidence |
|---|---|---|
| Current native collision refresh | GREEN, strict logs clean | `build/native-terminal-diagnosis-collision` |
| Existing Main narrative before repair | GREEN; this older fixture used a teleport for final contact | `build/native-terminal-diagnosis-existing-narrative` |
| Full ordinary approach before repair | RED, one `OCCURRENCE_INVALID` at frame 110 | `build/native-terminal-diagnosis-standard-red` |
| Fixed-60 approach before repair | RED, uncollected after 300 frames with actual overlap and 356ms retry delay remaining | `build/native-terminal-diagnosis-fixed` |
| Ordinary approach after repair | GREEN, collected at frame 113; no rejections; strict logs clean | `build/native-terminal-traversal-standard-green` |
| Fixed-60 approach after repair | GREEN, collected at frame 113; no rejections; strict logs clean | `build/native-terminal-traversal-fixed-green` |
| Seven narrative/profile/checkpoint/domain scenes | GREEN, 7 passed and 0 failed; strict logs clean | `build/native-terminal-traversal-narrative-regressions` |

Every successful traversal preserves the exact terminal Run state and the
Player action, time, weapon, character, rewind and World replay clocks.
Diagnostics label `prerequisite_route_synthetic: true` and
`combat_certification: false`, and retain positions, actual overlap, refusals,
elapsed wall time and retry deadline. Timings are diagnostic, not performance
certification. Godot version: `4.6.1.stable.official.14d19694e`.

```bash
TEST_LOG_DIR=build/native-terminal-diagnosis-collision tools/run_tests.sh --filter native_void_collision_refresh --timeout 300
TEST_LOG_DIR=build/native-terminal-traversal-standard-green tools/run_tests.sh --filter main_terminal_fragment_traversal --timeout 300
TEST_LOG_DIR=build/native-terminal-traversal-narrative-regressions tools/run_tests.sh --filter narrative --timeout 300
```

The fixed-60 run uses the same focused scene with `godot --headless
--fixed-fps 60`, isolated test/user/cache directories and explicit `--log-file`.
Both its stdout and engine log pass `tools/runtime_log_validation.py`.
The three pinned requirement files pass `pip-audit` with no known
vulnerabilities, and `git diff --check` passes.

## Limits and Rollback

The earlier in-flight long Main process reached five actual Boss victories
over 12,153 accepted frames, but its terminal collection failed. That run's
older loaded collision code and terminal failure remain diagnostic evidence;
it cannot certify the current source. No complete five-floor run was repeated
for this focused repair. The integration lead owns that frozen certification.

No UI runtime or assets changed. The UI phase still requires the gameplay
gate to pass. Stock Godot provides no line-coverage evidence. This one-line
repair, its regression and this evidence are retained as a focused local
commit, reversible as a unit.
