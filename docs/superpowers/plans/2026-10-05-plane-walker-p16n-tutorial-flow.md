# Native Tutorial Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the actual tutorial UI to native gameplay and the physical Profile service without publishing unsaved or stale hints.

**Architecture:** A Node coordinator owns native presentation and service-issued adapter binding. It freezes participant identities and checks them around physical persistence. The service remains the sole progress and reward authority.

**Tech Stack:** Godot 4.6, GDScript, native CanvasLayer/Control scenes, real disk saves and existing headless scene runner.

## Global Constraints

- Standing authorization permits focused reversible workspace implementation.
- Do not edit Main, GameState or Hub in this task.
- Consume only service-issued native observations.
- Never expose guided policy before an independent frozen launch policy exists.
- Never stage unrelated dirty files or push commits.

### Task 1: Native Coordinator

**Files:**
- Create: `scripts/onboarding/tutorial_flow_coordinator.gd`
- Modify: `scripts/onboarding/tutorial_view_model.gd`
- Modify: `scripts/ui/contracts/tutorial_view_state.gd`
- Modify: `scripts/ui/tutorial_panel.gd`
- Create: `tests/integration/onboarding/tutorial_flow_coordinator_test.gd`
- Create: `tests/integration/onboarding/tutorial_flow_coordinator_test.tscn`

**Interfaces:**
- Consumes: Registry catalogs, physical Profile service, native Host/Player and remap service.
- Produces: `configure`, `bind_active_run`, `open_review`, `close`, `handle_input`, `process_pending_observations`, `retire_active_run`, `recover_active_run`, `training_requested`.

- [x] Write a missing-coordinator RED test using actual Main participants.
- [x] Run the new scene and retain its failure evidence (`planewalker-tests.T7C1Ae`).
- [x] Implement strict configuration, frozen binding, pause ownership, durable skip/suppression, native recovery and save-before-hint publication.
- [x] Separate guided policy capability from training in the existing strict view contract.
- [x] Run physical save-failure, pause, stale context, keyboard/controller and remap tests (`planewalker-tests.nTCLcC`).
- [x] Run focused tutorial/service/UI regression and scan logs for script errors and leaks (7/7 `planewalker-tests.XnLVFs`; native OpenGL PASS).
- [x] Document evidence and precise public integration API; commit only owned files.
