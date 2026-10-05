# Native Test Physics Space Evidence

- Status: Focused Verified / Current
- Document Role: Current focused regression evidence
- Authority Level: Below approved full-product specification
- Applies To: Manually advanced Player fixtures and strict native runtime logs
- Owner: Plane Walker integration lead
- Depends On: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05
- Evidence Classification: Automated native fixture verification; no human playtest or full-product certification

## Reproduction

The weapon-coordinator fixture disables Player processing before adding it to the
tree, then manually advances Dash. The default CollisionObject2D disable mode
removes its body from the physics space. Godot reports `body->get_space()` null
from `move_and_collide`, although the older assertion-only suite finishes PASS.
The strict runtime scanner correctly rejects that result.

RED is retained under `build/test-evidence/player-weapon-space-red/`. Its stdout
and engine log both contain the actual physics error from the buffered Dash
scenario. This is an unexpected engine error, not an intentional refusal.

## Repair And Verification

The weapon and meta Player fixtures now declare
`CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE` before disabling processing, matching
the existing replay fixture. Manual actions retain a real physics body. The
weapon fixture asserts that its RID belongs to a physical space before actions.
Production Player processing and collision defaults are unchanged.

All three focused scenes pass with strict stdout and engine-log scans:

- `tests/combat/player_weapon_coordinator_integration_test.tscn`, including the original buffered Dash reproduction.
- `tests/integration/progression/meta_player_launch_test.tscn`, including the 150 permanent-loadout fixture combinations.
- `tests/integration/progression/challenge_equipment_test.tscn`, which reuses the meta Player fixture and advances actual movement.

GREEN logs are retained under `build/test-evidence/player-weapon-space-green/`,
`build/test-evidence/meta-player-space-green/` and
`build/test-evidence/challenge-equipment-space-green/`. Each suite reports one
passing scene, no runtime errors and no leaks. Runtime line coverage was not
collected by these stock Godot runs; combined clean-checkout certification remains
pending.
