# Native Boss Modifier Teardown

- Status: Verified Locally / Gameplay certification pending
- Document Role: Current native lifecycle repair evidence
- Authority Level: Below the full product completion specification
- Applies To: Void, Time Sovereign and Forge Player modifier teardown
- Owner: Project integration lead
- Depends On: [Full product completion design](../superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md)
- Last Verified: 2026-10-06

## Root Cause and Retained Behavior

Native challenge flow exit can dispose effects after the surviving Boss node
has already left the scene tree. The Void, Time and Forge modifier synchronizers
queried its `get_world_2d()` even when clearing a source-owned Player modifier.
Godot reported `Condition "!is_inside_tree()" is true` and disposal returned
false, leaving the authentic Void Devour modifier installed.

Each synchronizer now permits removal from a Player with the matching current
run and uses only that Boss's source and modifier key. Cleanup does not require
a live arena world, is idempotent and preserves foreign owners. Forge removal
also does not require a retained nonempty arena snapshot. Synchronizing new
effects requires both nodes inside the tree and the same live `World2D`;
two detached nodes cannot pass by comparing two null worlds.

## Focused Evidence

Commands use Godot `4.6.1.stable.official.14d19694e` and the production scene
runner, which validates stdout and engine logs and rejects unexpected engine
errors, script/deferred failures and object/resource leaks.

| Scene | Result | Retained Log Directory |
|---|---|---|
| `native_boss_modifier_teardown_test.tscn` before runtime fix | RED: detached-world errors, owned cleanup failures and two-detached apply acceptance | `build/native-modifier-teardown-red` |
| `native_boss_modifier_teardown_test.tscn` after runtime fix | GREEN: all assertions pass; strict logs clean | `build/native-modifier-teardown-green` |
| Existing `void_auxiliary_lifecycle_test.tscn` | GREEN: all assertions pass; strict logs clean | `build/native-modifier-teardown-lifecycle` |
| Existing `boss_rush_carried_test.tscn` | GREEN: all assertions pass; strict logs clean | `build/native-modifier-teardown-boss-rush` |

The new regression covers authentic production actors for all three affected
Bosses, foreign source and current-run refusal, idempotency, other-world
application refusal, one or two detached nodes, and real effect disposal after
an authenticated Devour damage receipt installs the native output debuff.

The three pinned Python requirement files passed `pip-audit` with no known
vulnerabilities. `git diff --check` passed. Repository documentation governance
is independently owned and still reports two metadata violations in the
concurrent auxiliary-cache plan; this teardown evidence has no new violations.

```bash
TEST_LOG_DIR=build/native-modifier-teardown-green tools/run_tests.sh --filter native_boss_modifier_teardown --timeout 120
TEST_LOG_DIR=build/native-modifier-teardown-lifecycle tools/run_tests.sh --filter void_auxiliary_lifecycle --timeout 300
TEST_LOG_DIR=build/native-modifier-teardown-boss-rush tools/run_tests.sh --filter boss_rush_carried --timeout 300
```

## Limits and Rollback

This focused evidence does not certify the combined gameplay milestone, UI
finish, exports or the entire test inventory. Stock Godot reports
`godot_line_coverage_unsupported`; no line-coverage percentage is claimed.
No UI runtime, assets, gameplay rules or source-owned damage receipts changed.
The repair and regression are retained together as a focused local commit and
can be reverted as a unit.
