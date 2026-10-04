# Native Training Arena Implementation Plan

- Status: Completed / Historical
- Document Role: Historical completed training arena implementation plan
- Authority Level: Execution below approved P16R
- Applies To: Training coordinator, arena, native UI and T-05
- Owner: Project training implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16r-training-arena-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Headless 3/3 and native bilingual arena gates verified locally
- Completion Evidence: `docs/current/2026-10-05-p16r-training-arena-evidence.md`
- Exit Gate: Actual training controls and Boss conversion pass native headless and rendering gates

> **For agentic workers:** Use the existing scene runner, independent review and precise staging paths.

**Goal:** Make all six authored training drills usable in an independent native arena.

**Architecture:** TrainingFlowCoordinator owns NativeTrainingFlow, TrainingArena, Camera2D and TrainingPanelView. TrainingRuntime remains the issued frame observer; Profile persists only sealed observations. The actual Boss engine supplies T-05 conversion state.

**Tech Stack:** Godot 4.6, GDScript, existing Registry/Player/Profile, original raster PNG assets.

## Global Constraints

- Main and translations are parent-owned; send API/key requirements to parent.
- Preserve pending physical observations before changing selection, resetting or returning.
- Use the actual Boss scene and action engine, with no production test helpers.
- Pause only the owned training Player during configuration.
- Scan logs; an exit code without clean scripts/leaks is insufficient.
- Do not edit P16P/shared Profile until its coordinated atomic foundation commit completes.

### Task 1: Independent arena and usable controls

Files: create `scripts/training/training_flow_coordinator.gd`, `scripts/training/training_arena.gd`, `scripts/training/training_panel_view.gd`, `scenes/training/training_target.tscn`, `tools/generate_training_assets.py`, `data/content_packs/base/assets/training/*`, `tests/integration/training/training_arena_flow_test.gd/.tscn`.

Interfaces: `configure(registry, service)`, `open(task_id = "")`, `close()`, `is_training_active()`, `closed`; read-only `training_player()`, `training_panel()`, `training_arena()` for native integration evidence.

- [x] Write the missing coordinator RED and actual selector/reset/back/save-refusal tests.
- [x] Generate original 640x360 raster floor, target/Boss sprites and symbolic tool icons with provenance.
- [x] Implement the independent walls, camera, native controls and safe selection lifecycle.
- [x] Verify actual keyboard/controller controls and durable objective projection.

Run: `./tools/run_tests.sh --filter training_arena_flow --timeout 30`.
Expected RED: named missing coordinator boundary. Expected GREEN: actual scene and physical lifecycle pass, with no script errors/leaks.

### Task 2: Actual T-05 conversion

Files: modify `scripts/training/native_training_flow.gd`, `scripts/training/training_runtime.gd`, `scripts/progression/profile_runtime_service.gd`, training arena/coordinator and their focused tests after coordinated P16P commit.

Interfaces: optional actual Boss provider during training bootstrap; service-issued binding freezes actual Boss/Health; successful Stop target contact produces one sealed `boss_conversion` objective.

- [x] Add RED for real Boss conversion, idle/foreign/stale/refused-frame rejection and physical reward retry.
- [x] Instantiate actual Chrono Warden and derive conversion from exact native source, exposure and action delay.
- [x] Pass T-05 physical reload/reward-once and unaffected P16P regressions.
- [x] Independently review and fix findings.

### Task 3: Native visual and interaction evidence

- [x] Render real Chinese/English 640x360 and 1280x720 windows at text scale 1.0/1.5.
- [x] Inspect nonblank arena, Player/target/Boss assets and text containment; fix discovered issues.
- [x] Record commands, logs, screenshots and limitations in `docs/current/2026-10-05-p16r-training-arena-evidence.md`.
- [x] Parent adds index entries; pass governance, dependency audit and diff checks.
- [x] Commit precise arena/UI/assets/tests/docs paths and report stable integration API.
