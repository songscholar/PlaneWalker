# P22B Replay Library Implementation Plan

- Status: Completed
- Document Role: Historical implementation plan
- Authority Level: Below the P22B replay library specification
- Applies To: Native local replay controls, exact isolated snapshots and Hub archive entry
- Owner: Project integration lead
- Depends On: `../specs/2026-10-05-p22b-replay-library-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Native library, identity/history, physical controller, Main and supported-resolution checks pass
- Completion Evidence: `../../current/2026-10-05-p22b-replay-library-evidence.md`
- Exit Gate: Actual Player library, identity, history, native panel and Main entry scenes pass; supported native screenshots and clean import accompany retained evidence

> Agentic workers execute focused tasks under the standing project authorization.

**Goal:** Make validated local Player recordings usable from the Hub.

**Architecture:** A replay coordinator owns physical archive access, private
world admission and timeline state. A native panel owns controls and focus.
Player identity reconstruction is restricted to admitted ReplayWorld Players.

**Tech Stack:** Godot 4.6.1, GDScript, existing SaveService and ReplayPlayer.

## Constraints

- Exact game/content/save-domain binding; 20 entries and 64 MiB retained.
- No live-world publication or progression from replay viewing.
- Manual file operations are bounded and export to application-owned storage.
- Snapshot presentation does not certify whole-run input simulation.

## Task 1: Isolated Identity Reconstruction And Timeline

Files: `scripts/player/player_controller.gd`,
`scripts/replay/player_replay_library.gd`,
`tests/replay/player_replay_library_test.gd` and its scene.

- [x] Define failing actual Player library/identity tests.
- [x] Run `tools/run_tests.sh --filter player_replay_library` and retain RED.
- [x] Implement admitted Player reconstruction and physical library commands.
- [x] Verify seek, advance, end, export/reimport, remove and isolation.
- [x] Review and retain focused commit with evidence.

## Task 2: Native Library Panel And Hub

Files: `scripts/replay/player_replay_library_panel.gd`, `scripts/main.gd`,
`scripts/hub/hub_flow_coordinator.gd`, `scripts/ui/hub_panel_view.gd`,
`data/localization/translations.csv` and canonical pack translations.

- [x] Define failing Hub entry/panel controls integration tests.
- [x] Add list, import/export/remove, native viewport, seek and playback controls.
- [x] Connect Hub archive entry after daily-mode owner releases Main/Hub.
- [x] Run actual panel interaction/focus and supported-resolution checks.
- [x] Define explicit keyboard/controller menu mappings and exercise physical A/B/D-pad events, modal cancellation and stale controls.
- [x] Retain evidence and focused commit; report remaining whole-run scope.
