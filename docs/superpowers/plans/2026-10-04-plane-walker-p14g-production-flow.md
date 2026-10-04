# Plane Walker P14G Production Flow Implementation Plan

- Status: Active / Current
- Document Role: Current P14G production assembly plan
- Authority Level: Implementation under the approved P14 five-floor design
- Applies To: Native dungeon panels, semantic commands, physical rewards, controller focus, and production Main assembly
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`
- Last Verified: 2026-10-04
- Exit Gate: Native five-floor interactions, focused panels and controller tests, Save/Replay regressions, graphical resolution checks, and the unified repository gate pass with a reviewed local commit.

**Goal:** Connect the existing six strict dungeon panels to real room, route, merchant, reward, rest, event, and floor lifecycle commands.

**Architecture:** Main owns a DungeonFlowCoordinator. RunRuntimeHost remains the production command boundary; RunOrchestrator remains the state writer. A dedicated interaction service prepares deterministic rewards and compensates Player/Build/RunState failures. Views receive projected dictionaries and emit semantic commands only.

**Tech Stack:** Godot 4.6.1, native Controls, ContentRegistry v2, existing Save v3 and Replay contracts.

## Execution

- [x] Inspect and preserve the current event persistence, ViewState, and panel implementations.
- [x] Verify the failing production entry/focus/duplicate-submission test with `./tools/run_tests.sh --filter p14_controller_flow`.
- [x] Add `scripts/application/dungeon_flow_coordinator.gd` and Main assembly, then verify a native route button streams the first room.
- [x] Add deterministic room rewards, rest choices, exact merchant service prices and event reward continuation commands through Host/Facade authorities.
- [x] Extend integration tests through treasure/rest/shop/event/floor transition, stale commands, compensation, and terminal cleanup.
- [x] Add all new localization keys through the CSV catalogs and refresh the Base Pack integrity hash.
- [ ] Run focused panel, projection, lifecycle, Save/Replay, controller, and visual tests; run the unified repository gate after integration.
- [ ] Record certification evidence and a focused reversible local commit. Continue to P14H and P15 under standing authorization.

Focused production and visual evidence is retained in `docs/current/2026-10-04-p14g-production-flow-evidence.md`. The complete combined gate and reviewed integration commit remain owned by the integration lead.

## Boundaries

M1 stays on its verified linear flow. Launch uses the approved FloorPlan and streamed room host. Human playtest counts remain authentic. P15 owns final enemy and Boss behavior. Signing, remote publication, and commercial decisions remain external operations.
