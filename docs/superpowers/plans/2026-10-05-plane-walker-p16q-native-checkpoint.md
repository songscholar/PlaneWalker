# Native Checkpoint Implementation Plan

- Status: Approved / Current
- Document Role: Current executable native checkpoint implementation plan
- Authority Level: Below P16Q specification and project execution policy
- Applies To: Authenticated persistence, cold native reconstruction and physical tests
- Owner: Project runtime implementation lead
- Depends On: `../specs/2026-10-05-plane-walker-p16q-native-checkpoint-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Physical cold reconstruction, rollback and pending reward tests pass with scanned Godot logs; mid-combat remains explicitly unavailable

> Agentic workers execute the focused steps below under standing project authorization.

**Goal:** Recreate a durable authenticated launch in a new native Host and Player without minting another launch or settling it again.

**Architecture:** Profile persists only checkpoints captured by a native authority from real participants. Host creates a candidate facade and staged scene; Player's existing full Replay and loadout compensation APIs preserve native preimages.

**Tech Stack:** Godot 4 GDScript, existing SaveService, ReplayRecorder codec and RoomSceneHost transition tickets.

## Global Constraints

No remote writes. Do not accept arbitrary dictionary availability claims.
Reject active combat until enemy/timer reconstruction is independently tested.
Preserve exact frozen loadout, receipt, pending reward and floor recovery ledger.
Scan Godot logs for script errors and leaks; process exit alone is insufficient.

## Task 1: Physical Contract And RED

- Create `tests/integration/save/native_run_checkpoint_test.gd/.tscn`.
- [x] Instantiate production Main, create an isolated physical Profile, start a real launch and assert `host.has_method("checkpoint_profile_run")` and `host.has_method("restore_profile_checkpoint")`.
- [x] Run `TEST_LOG_DIR=build/test-logs/p16q-checkpoint/red tools/run_tests.sh --filter native_run_checkpoint --timeout 90`; require an assertion failure for the absent entry points.

## Task 2: Authoritative Capture And Persistence

- Create `scripts/save/native_run_checkpoint_authority.gd`.
- Modify `scripts/progression/profile_runtime_service.gd` after its training owner releases it.
- [x] Implement `capture(host: Node) -> Dictionary` from actual native participants and safe phase/runner/scene evidence.
- [x] Implement `retain_native_checkpoint(host: Node, expected_revision: int) -> Dictionary` and `authenticated_native_checkpoint(expected_revision: int) -> Dictionary` using the actual primary, Profile receipt and existing atomic ticket persistence.
- [x] Persist `{active_run_state, reward_effect_state, native_run_checkpoint}` in one write; compare actual Run/Player/scene after persistence and freeze on publication drift.

## Task 3: Cold Reconstruction And Compensation

- Modify `scripts/application/run_runtime_host.gd` and `run_runtime_facade.gd`.
- Add inactive restore contracts in `scripts/dungeon/room_runtime.gd` and `encounter_runner.gd`.
- [x] Expose `checkpoint_profile_run(expected_revision: int)` and `restore_profile_checkpoint(service: RefCounted, expected_revision: int)`.
- [x] Restore a candidate facade from authenticated Run, accepted native loadout, full Replay, staged current scene and room snapshot. Copy publication watermarks without gameplay signal replay.
- [x] Compensate failed native installation stages to the previous Host/Player/scene preimages and preserve the primary; arbitrary mutations inside preparation adapters before installation are outside the tested contract.

## Task 4: Verification And Retention

- [x] Destroy and recreate Main/Host/Player, reopen physical Profile, restore, and compare full Run/Replay and launch sequence.
- [x] Test pending rewards, terminal defeat, inactive room identity, live payload lifecycle, stale physical primary, tampering, failed save, failed scene activation and retry.
- [x] Run launch/save/room regressions and scan logs; record precise limitations in the current evidence document.
- [x] Record the safe native foundation and reviewed training dependency in a focused local commit.
