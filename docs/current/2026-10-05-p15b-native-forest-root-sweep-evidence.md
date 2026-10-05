# Native Forest Root Sweep Evidence

- Status: Verified focused gate
- Document Role: Current retention evidence for the authored surviving-root sweep
- Authority Level: Evidence below the approved P15 specification
- Applies To: Frozen root selection, native warning/damage, destruction cancellation and cold compatibility
- Owner: Native Boss implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/plans/2026-10-05-native-forest-root-sweep.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`
- Last Verified: 2026-10-05

## Verified Behavior

The Forest Boss selects the nearest living, nonretired root within96px of the
Player. Stable slot order resolves equal distances. Root world positions include
the validated room translation; committed target geometry remains frozen.

Forest Boss schema3 retains arena schema2 ownership receipts, including the
ordered damage prefix and phase-retirement boundary for each committed sweep.
Current root geometry cannot bypass ownership by claiming a historical attack
generation. Explicit Boss schema1/2 normalization preserves an already committed
historical trunk-origin sweep only at the configured stationary trunk position.
Native composition supplies that trunk position from its actual Actor.

The production CombatTelegraph2D projects the root-owned cone during WARNING and
ACTIVE. High-contrast and1.5x enlarged warning settings change presentation only.
Accepted selected-root destruction retires the attack generation, hides its
warning and prevents its scheduled damage. Refusal restores the exact root HP,
ownership, threat registry and visible warning; retry applies destruction once.
Later legal Boss attacks remain active and are distinguished by DamageInfo's
attack_generation rather than incorrectly requiring that the Player never loses HP.

Actual native Health tests retain the full45-frame warning and one20-damage P1
hit. Pure tests retain the authored26-damage P2 hit, stable selection after root
retirement, frozen targets, forged-receipt refusal and historical continuation.

## Test Evidence

- Ownership RED: `build/test-evidence/forest-root-sweep-review-red`; the current root cast could falsely claim the historical trunk exemption.
- Warning RED: `build/test-evidence/forest-root-sweep-review-warning-red`; native root warning creation, cancellation and rollback were missing.
- Final Forest gate: `TEST_LOG_DIR=build/test-evidence/forest-root-sweep-review-final-forest tools/run_tests.sh --filter forest_root`,4/4 passing. Existing root burn, exposure and phase-retirement behavior passes.
- Shared Boss gate: `build/test-evidence/forest-root-sweep-review-final-boss`, `--filter launch_boss`,3/3 passing.
- Native arena gate: `build/test-evidence/forest-root-sweep-review-final-arena`, `--filter boss_arena_native`,1/1 passing.
- Replay exposure gate: `build/test-evidence/forest-root-sweep-review-final-replay`, `--filter boss_exposure_checkpoint`,1/1 passing.
- Native Metal execution: `build/test-evidence/forest-root-sweep-review-final-visual.log`, all assertions passing.
- Final stdout and Godot logs contain no script/parse errors, warnings, orphan nodes or leaks. The runner reports line coverage as unsupported by the installed Godot toolchain.

Six raster captures under `build/visual-evidence/p15b-native-arena/` retain normal
warning, enlarged high-contrast warning and accepted cancellation at640x360 and
1280x720. Dimension/color checks and visual inspection confirm nonblank output,
root-owned cone placement and removal after destruction. Existing production
root raster art and the existing telegraph component are reused; no dependency
or third-party asset was added.

## Remaining Scope

This evidence closes the focused root-sweep gate. Sacs, seeds, flowers, cages,
erosion, drain healing, sapling lifetimes, whole-Host/750-loadout certification,
long-lived per-encounter receipt budgets and retained exports remain separate
Forest/P15 and full-product gates.
