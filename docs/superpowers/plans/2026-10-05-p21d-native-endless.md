# P21D Native Endless Implementation Plan

- Status: Verified / integration pending
- Document Role: Current focused implementation plan
- Authority Level: Below the native endless specification
- Applies To: Mode state, native five-floor composition, atomic recovery and UI
- Owner: Plane Walker implementation team
- Depends On: `../specs/2026-10-05-p21d-native-endless-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Actual native encounter and cold-recovery tests, fault/CAS tests and controller tests pass with clean scanned logs

**Goal:** Play repeated production five-floor dungeons with carried resources.

**Architecture:** EndlessSession owns bounded identities and summaries.
EndlessProfileService atomically saves session and private native Profile through
CAS. EndlessRuntimeHost/EndlessEncounterDriver retain production dungeon behavior
and apply the declared immutable scaling. NativeEndlessFlow owns lifecycle and
EndlessCoordinator exposes native controller menus.

**Tech Stack:** Godot 4.6.1, GDScript, SeedService and SaveService.

## Global Constraints

- Exactly five authored floors per cycle; rolling capacity of 32 summaries.
- Cycles continue beyond 160 floors with saturated scaling and bounded counters.
- HP multiplier <= 3.0 and damage multiplier <= 2.0; native roster <= 8.
- Source Profile, Main, Hub, localization and shared runtimes are integration-owned.
- No external credentials, ordinary currency rewards or commercial operations.

## Task 1: Closed State And Atomic Save

Files: `scripts/modes/endless_session.gd`, `endless_profile_service.gd`,
`tests/modes/endless_session_test.gd` and scene.

- [x] Define ResourceLoader missing-mode RED and invalid cycle/request/codec cases.
- [x] Run `./tools/run_tests.sh --filter endless_session --timeout 60` and retain RED.
- [x] Implement `empty(fingerprint)`, `valid(value, profile_id)` and
  `cycle_seed(seed, cycle)` with strict budgets and deep copies.
- [x] Implement CAS Profile persistence, stale-primary refusal and cycle retirement.
- [x] Run focused GREEN before native composition.

## Task 2: Native Dungeon And Carry

Files: `scripts/modes/endless_encounter_driver.gd`, `endless_runtime_host.gd`,
`native_endless_flow.gd`, `tests/modes/endless_native_test.gd` and scene.

- [x] Define actual native spawn/rollback/death and cold checkpoint RED.
- [x] Compose real Controller, Host, SceneHost, floor rules and dungeon panels.
- [x] Apply bounded actor projections before native binding and cold restore.
- [x] Preserve typed Build and reward effects at verified five-floor victory.
- [x] Verify actual encounter and native reload without source Profile writes.

## Task 3: Recovery And Controller

Files: `scripts/modes/endless_coordinator.gd`, `endless_panel_view.gd`,
`tests/modes/endless_checkpoint_test.gd`, `endless_coordinator_test.gd` and scenes.

- [x] Verify pre/post-promotion faults, stale writers, retry and reload.
- [x] Build controller focus, pause, next-cycle and save-and-return controls.
- [x] Retain exact commands/logs, integration instructions and localization snippet.
- [x] Run focused tests and `git diff --check`; integration owner commits and
  performs combined clean-checkout certification.
