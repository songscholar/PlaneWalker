# Player Replay And Save P1/P2 Implementation Plan

- Status: Completed / Historical
- Document Role: Historical implementation plan and execution record
- Authority Level: Replay and save P1/P2 execution record
- Applies To: Launch full-player Replay schema 6 and SaveEnvelope schema 2
- Owner: Project integration lead
- Depends On: AGENTS.md, docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md
- Last Verified: 2026-10-01
- Implementation Status: Completed locally; Launch Replay schema 6, frozen M1 Replay schema 2, atomic full-player restore, SaveEnvelope schema 2, production v1 migration, and real Launch Player/Sword/active-item disk round-trip pass their focused gates
- Completion Evidence: This historical execution record, the focused implementation commit containing it, and the GREEN filters listed in Task 6; full repository certification is recorded by the P13B evidence document
- Exit Gate: Replay and Save focused suites, documentation governance, diff checks, and Godot error/leak scans pass with M1 schema v2 bytes preserved

> **For agentic workers:** Execute each task with RED/GREEN verification and keep Run-level reward-seal authority files out of scope.

**Goal:** Make Launch full-player replay stable across mid-recording rewards, fail closed on unverifiable legacy reward state and forged talent definitions, restore atomically without transient notifications, and activate save schema v2 in production.

**Architecture:** Launch identity becomes an immutable loadout/configuration baseline while mutable reward and talent state remains in the replay snapshot. Launch v4/v5 cannot prove the absence of time-only or dash-invulnerability rewards because those domains were not sealed, so every Launch v4/v5 Replay fails closed. Full-player restore separates pure validation from silent mutation and publishes only after a successful complete commit. Save schema v2 is the production envelope target and v1 migration adds explicit active-item and reward-effect fields.

**Tech Stack:** Godot 4, GDScript, deterministic replay snapshots, project `TestSuite`, save-envelope migrations.

## Global Constraints

- Do not modify `RunState`, `RunOrchestrator`, `RunRuntimeFacade`, or Run-level reward-seal tests/files.
- Preserve Wanderer M1 replay schema v2 identity and behavior exactly.
- Define failing tests before implementation and run focused filters after every subsystem.
- Reject data that cannot be proven lossless; never invent reward state during replay migration.
- Stage only explicitly listed files and never use `git add .`.

---

### Task 1: Stabilize Launch replay identity

**Files:**
- Modify: `tests/replay/character_runtime_replay_test.gd`
- Modify: `scripts/player/player_controller.gd`

**Interfaces:**
- Produces: immutable `_launch_replay_identity_baseline: Dictionary`
- Produces: `full_player_replay_identity() -> Dictionary` that remains live for M1 and returns the captured baseline for Launch.

- [x] Add a test that starts recording, applies a passive reward, installs a talent, equips/activates an active item, and records subsequent frames while asserting that the identity digest never changes.
- [x] Run `./tools/run_tests.sh --filter character_runtime_replay` and confirm the new test fails on identity drift.
- [x] Capture the Launch identity after successful loadout configuration, include it in configuration rollback state, and clear/rebuild it when the run/loadout changes.
- [x] Relax Launch snapshot validation so initial talents are a subset of live talents and mutable reward stats are validated against mutable state rather than the frozen identity.
- [x] Re-run the focused replay test and confirm PASS with zero script errors/leaks.

### Task 2: Reject forged talent authority

**Files:**
- Modify: `tests/replay/character_runtime_replay_test.gd`
- Modify: `scripts/player/player_controller.gd`

**Interfaces:**
- Consumes: `res://data/content_packs/base/content/talents.json`
- Produces: pure local-catalog validation for both replay talent-definition copies.

- [x] Add a RED test that changes both `live_talent_state.talent_definitions` and `character_state.runtime.talent_definitions`, recomputes all replay digests, and expects restore rejection.
- [x] Load and canonicalize Base Pack talent definitions in the Player validation path.
- [x] Require both replay definition copies to match each other and the local authoritative definition for every selected talent.
- [x] Run `./tools/run_tests.sh --filter character_runtime_replay` and confirm the forged snapshot is rejected.

### Task 3: Fail closed on unverifiable v4/v5 reward state

**Files:**
- Modify: `tests/replay/character_runtime_replay_test.gd`
- Modify: `scripts/replay/replay_recorder.gd`

**Interfaces:**
- Produces: an authenticated fail-closed boundary for all Launch v4/v5 Replay documents.

- [x] Add authenticated v4/v5 fixtures plus reward-bearing variants and recompute their historical digests.
- [x] Prove the original compatibility premise infeasible: v4/v5 do not seal reward_effect_state.time or reward_effect_state.character, so a nominally reward-free document is byte-identical to one carrying only time-duration/cost or dash-invulnerable-bonus rewards.
- [x] Remove unconditional reward-state synthesis and reject every Launch v4/v5 document with FULL_PLAYER_REPLAY_MIGRATION_INVALID.
- [x] Preserve the caller-owned Replay bytes on rejection and keep Wanderer M1 schema behavior unchanged.

### Task 4: Restore full-player snapshots atomically and silently

**Files:**
- Modify: `tests/replay/character_runtime_replay_test.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify only if required by pure validation: health, time, or weapon-modifier replay participant scripts.

**Interfaces:**
- Produces: `can_restore_reward_effect_snapshot(value: Dictionary) -> bool`
- Produces: `restore_reward_effect_snapshot(value: Dictionary, publish_signals: bool = true) -> bool`
- Consumes: every replay participant's `can_restore_*` method and world-payload transaction restore API.

- [x] Add signal counters and a late-participant-invalid RED test; assert failed restore emits no health, time, stats, or weapon notification and state is exactly unchanged.
- [x] Prevalidate every participant, including reward, health, world, time, action, character, weapon, rewind, intent, and player-owned state, before mutation.
- [x] Stage world state, apply all participants silently, commit only after complete success, then publish one coherent final state.
- [x] Preserve exact rollback and disable physics if rollback itself cannot restore the prior snapshot.
- [x] Run `full_player_replay`, `character_runtime_replay`, and `character_external_fact_replay` filters.

### Task 5: Activate SaveEnvelope v2 end to end

**Files:**
- Modify: `scripts/save/save_envelope.gd`
- Modify as required: `autoload/game_state.gd`, `scripts/save/save_service.gd`
- Modify: save migration, save service, and GameState tests.

**Interfaces:**
- Produces: `SaveEnvelope.SCHEMA_VERSION == 2`
- Consumes: registered `SaveMigrationV1ToV2` and validates migrated production documents before import.

- [x] Add production round-trip tests that load an actual v1 document through GameState/SaveService and verify explicit empty `active_item_state` and `reward_effect_state` in the v2 result.
- [x] Change future-version tests from schema 2 to schema 3 and add malformed v1/v2 rejection cases.
- [x] Raise the production envelope version to 2 and ensure the existing import pipeline migrates v1 before strict envelope validation.
- [x] Run `save_migration`, `save_service`, and `game_state` filters.

### Task 6: Final regression gate and commit

**Files:**
- Verify all files modified by Tasks 1-5.

- [x] Run each required focused filter separately: `full_player_replay`, `character_runtime_replay`, `character_external_fact_replay`, `save_migration`, `save_service`, and `game_state`.
- [x] Scan output for parse errors, script errors, assertion failures, and leaked nodes/resources.
- [x] Run `git diff --check` and inspect `git diff --stat` plus the exact diff.
- [x] Stage only owned Player Replay/Save files, excluding Run-level reward-seal files.
- [x] Commit with a focused message and report the commit hash, tests, and limitations to the parent agent.
