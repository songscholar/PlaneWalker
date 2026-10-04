# Native Narrative Flow Implementation Plan

- Status: Approved / Current
- Document Role: Current focused native narrative implementation plan
- Authority Level: Task execution below the P16O narrative flow specification
- Applies To: Native coordinator, strict view projection, occurrence markers and integration tests
- Owner: Project narrative implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16o-native-narrative-flow-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Native implementation and focused contact/recovery QA complete; production Main handoff tracked by its own evidence
- Exit Gate: Real room contact and durable ending/credits flow, stale/refusal tests, localized native rendering and scanned logs pass

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make authored narrative, final heart contact, ending choice and separately saved credits usable through the native game.

**Architecture:** A coordinator freezes actual service/Run/Player/Room ownership and delegates every domain command to ProfileRuntimeService. Strict projected panels present authored content only after confirmed saves. Main owns terminal combat suppression, settlement and return to Hub.

**Tech Stack:** Godot 4.6.1, native Control/Area2D, existing physical Profile service and authored Registry content.

## Global Constraints

- Create new implementation/test/docs files only; do not edit Main/Host/Profile/RoomSceneHost.
- Never grant the last heart fragment without actual service-issued Area2D Player contact.
- Ending selection and credits completion are distinct durable facts.
- Use current authored Registry content and original generated raster markers.
- Exact local commits only, no push or public publication.

### Task 1: Native Narrative Boundary

**Files:**
- Create: `scripts/narrative/narrative_flow_coordinator.gd`
- Create: `scripts/narrative/narrative_view_model.gd`
- Create: `scripts/ui/contracts/narrative_view_state.gd`
- Create: `scripts/ui/narrative_panel_view.gd`
- Create: `scripts/narrative/narrative_occurrence_marker.gd`
- Create: `tests/integration/narrative/narrative_flow_coordinator_test.gd`
- Create: `tests/integration/narrative/narrative_flow_coordinator_test.tscn`

**Interfaces:**
- Consumes: Actual Registry/Profile/Host/RoomSceneHost/Player/runtime parent.
- Produces: configure/bind_active_run/terminal_victory/retire_active_run/open_dialogue/show_selected_credits and ending_selected/credits_completed signals.

- [x] Write and run missing-coordinator RED using the real native integration boundary.
- [x] Implement detached strict dialogue, story, choice, ending and credits views.
- [x] Implement issued occurrence contact and participant/generation guards.
- [x] Implement saved final choice signal, settlement handoff and distinct credits save.
- [x] Test actual Player contact, physical save failures, stale callbacks and resume.
- [x] Verify native bilingual layout/controller/raster rendering and focused regressions.
- [x] Record evidence/API/Main requirements, complete document metadata, dependency audit and precise commit; parent owns shared index/governance integration.
