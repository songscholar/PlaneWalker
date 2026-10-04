# Native Training Flow Implementation Plan

- Status: Active / Current
- Document Role: Current focused native training implementation plan
- Authority Level: Execution below the approved P16P training specification
- Applies To: Native sandbox bootstrap, sealed task observations and physical Profile rewards
- Owner: Project training implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16p-native-training-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Native foundation verified; focused atomic commit pending
- Exit Gate: Real native actions, 150 sandbox loadouts, physical retry and exact owned lifecycle pass

> **For agentic workers:** Use the existing scene runner for each RED/GREEN gate and an independent review before committing.

**Goal:** Complete native action training without fabricating rewards or consuming a launch receipt.

**Architecture:** TrainingRuntime observes the real Player's committed frames. ProfileRuntimeService authenticates only its issued adapter and persists the selected TutorialRuntime task. NativeTrainingFlow owns an independent scene and reset/retirement lifecycle.

**Tech Stack:** Godot 4.6, GDScript, actual Registry profiles and physical JSON Profile saves.

## Global Constraints

- Do not modify Main, GameState, Host, shared UI, Registry or Base Pack.
- Configure sandbox profiles through the existing Player Launch pipeline.
- Freeze the actual World owner and refuse public receipt submission.
- T-05 is unavailable until reusable native Boss conversion exists.
- Use exact paths when staging; no remote push or publication.

### Task 1: Authenticated native sandbox and rewards

Files: `scripts/training/training_runtime.gd`, `scripts/training/native_training_flow.gd`, `scripts/progression/profile_runtime_service.gd`, `scripts/onboarding/tutorial_runtime.gd`, `tests/integration/training/native_training_flow_test.gd` and its scene.

Interfaces: `NativeTrainingFlow.configure(registry, service)`, `start(request) -> {ok, context: {player, adapter}}`, `process_pending_observations()`, `reset_attempt()`, `close()`; Profile service `bind_training(player, task_id, seed)`, `observe_training(adapter, revision)`, `retire_training()`; runtime `prepared_observation`, `native_checkpoint`, `confirm_saved`, `detach`.

- [x] Write actual-native integration assertions and run the missing-endpoint RED (`Tg4JK1`).
- [x] Configure independent Launch Player/World and service-issued successful-frame observer.
- [x] Persist only selected-task progress after the primary file promotes; retain observations on failed writes.
- [x] Verify actual actions, physical retry, repeated claim refusal, death/reset and native World detach/refusal (`yWJFjY`). Clock rollback and extended retirement gate follow before certification.
- [x] Verify all 150 sandbox combinations and five actual weapon action drills (`yWJFjY`).
- [x] Review implementation independently; fix HOLD and seed/task identity findings, then pass final native gate (`qW9dFc`).
- [ ] Record evidence, update documentation index and commit exact owned files.

Run: `./tools/run_tests.sh --filter native_training_flow --timeout 60`.
Expected RED: named missing native training flow assertion.
Expected GREEN: every native, physical persistence and sandbox assertion passes,
with no script errors or leak warnings; injected frame refusals are documented.

### Follow-on integration gates

Main's Hub training route and actual P15 Boss conversion drill remain separately
owned milestones. This slice exposes concrete bootstrap and retirement APIs for
those owners and cannot certify their unfinished routes.
