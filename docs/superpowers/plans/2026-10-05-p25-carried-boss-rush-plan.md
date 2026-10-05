# P25 Carried Boss Rush Implementation Plan

- Status: Approved under standing project authorization
- Document Role: Current
- Authority Level: Milestone execution plan
- Applies To: P25 carried Boss Rush implementation
- Owner: Plane Walker project owner
- Depends On: `../specs/2026-10-05-p25-carried-boss-rush-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual five-stage carry, rewards, physical save faults, native controls and difficulty projection pass with clean logs

> **For agentic workers:** Execute the authorized tasks inline and use the parent reviewer between milestones.

**Goal:** Deliver the original continuous Boss Rush rules through native gameplay.

**Architecture:** Reuse the verified arena and terminal authority. Add exact
carried-session validation and deterministic rewards, separate its durable
scope from legacy fresh sessions, and centralize Boss difficulty validation.

**Tech Stack:** Godot 4.6.1, GDScript, authoritative JSON content, SaveService.

## Global Constraints

- First normal victory unlock; five ordered bosses; HP 1.2; damage 1.1.
- Initial HP100 and gold100; heal 30 percent after each authenticated victory.
- Three interstage choices; durable carried build, HP and time energy.
- Bounded exact schema, deterministic seed, compare-exchange and retry.
- Legacy fresh-stage regression remains verified in its separate scope.
- Exit Gate: all focused and legacy mode tests pass with no script errors/leaks.

## Task 1: Validated Native Difficulty

Files: `scripts/enemies/launch/boss_definition.gd`,
`tests/unit/enemies/boss_difficulty_projection_test.gd/.tscn`.

- [x] Add a failing five-boss contract test calling
  `BossDefinition.difficulty_projection(base, 1.2, 1.1)`; assert HP, primary
  hit damage, phase overrides and auxiliary damage all change and malformed
  projections refuse.
- [x] Run `tools/run_tests.sh --filter boss_difficulty_projection` in a new
  `TEST_LOG_DIR`; require RED before implementing.
- [x] Implement the pure result `{ok, definition, context}` and authenticate its
  canonical base/multipliers in `configure_runtime_projection`.
- [x] Require GREEN and notify Endless integration of the shared API.

## Task 2: Carried Native Sessions

Files: `scripts/modes/boss_rush_carried_rules.gd`,
`scripts/modes/native_boss_rush_flow.gd`, `scripts/modes/boss_rush_catalog.gd`,
`tests/integration/combat/boss_rush_carried_test.gd/.tscn`.

- [x] Add RED assertions for unlock refusal, 100HP/100gold, scaled native Boss,
  real native death reward choices, carried HP/modifiers and cold continuation.
- [x] Add `configure(registry, service, root, carried=false)` and exact schema2
  validation; include rules in the fingerprint and storage identity.
- [x] Persist portable Player state with fresh weapon runtime, deterministic
  choices, durable reward ownership and bounded victory history.
- [ ] Verify fault-retry and stale-writer refusal against the promoted primary.

## Task 3: Native Choice and History Menu

Files: `scripts/modes/boss_rush_coordinator.gd`,
`scripts/modes/boss_rush_panel_view.gd`,
`assets/production/localization/boss_rush_carried.csv`.

- [x] Render lock state, deterministic choice buttons, carried HP/build,
  victory history and durable rewards using the existing focus scope.
- [x] Route choice IDs to `choose_reward(index)` and expose the carried
  configure option to parent Main integration.
- [x] Run all Boss Rush suites, scan every engine/stdout log and provide exact
  evidence plus parent integration interfaces for focused staging.

## Exit Gate

All focused carried-mode and legacy Boss Rush scene tests pass. Runtime,
physical save, reward selection, cold continuation, stale writer and save fault
assertions succeed; every engine/stdout log is free of script errors and leaks.
The parent completes Main/Hub entry integration, rendered QA and retention commit.
