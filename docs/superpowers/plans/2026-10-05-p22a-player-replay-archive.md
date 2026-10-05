# P22A Player Replay Archive Implementation Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: Below P22A replay archive specification
- Applies To: Replay packages, SaveService archive and isolated viewing
- Owner: Project integration lead
- Depends On: `../specs/2026-10-05-p22a-player-replay-archive-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Native recording, physical archive reload/fault/stale-writer and isolated actual Player seek/playback tests pass with clean logs; evidence records the remaining full-run tape and Hub scope.

> For agentic workers: Execute focused tasks with their failing tests and retention commits.

**Goal:** Preserve validated player recordings locally and expose safe import,
export, seek and verified playback boundaries.

**Architecture:** A package validator delegates replay semantics to ReplayPlayer;
an archive delegates physical writes to SaveService; an isolated viewing session
delegates restore and deterministic execution to ReplayPlayer.

**Tech Stack:** Godot 4.6.1, existing safe Variant codec, SaveService and native tests.

## Global Constraints

- Exact game/content/domain compatibility; object-enabled Variant decoding is forbidden.
- Twenty entries, sixty-four MiB total encoded data, existing sixteen-MiB binary codec ceiling.
- Failed or stale writes preserve committed state; no ordinary Meta or leaderboard write.
- Full hostile/room tape and automatic native capture remain separately tracked replay scope.

## Task 1: Package And Physical Archive

Files: create `scripts/replay/player_replay_package.gd`,
`scripts/replay/player_replay_archive.gd`, and
`tests/replay/player_replay_archive_test.gd` / `.tscn`.

Interfaces: `configure(root_path, game_version, content_snapshot, profile_id,
save_domain, fault_injector) -> Dictionary`, `store(replay) -> Dictionary`,
`import_json(encoded) -> Dictionary`, `export_json(id) -> Dictionary`,
`load_replay(id) -> Dictionary`, `remove(id) -> Dictionary`,
`snapshot() -> Dictionary`, `reload() -> Dictionary`.

- [ ] Create an actual launch Player recording fixture and assert an absent archive fails.
- [ ] Run `./tools/run_tests.sh --filter player_replay_archive --timeout 90`; retain RED.
- [ ] Implement exact package fields and whole-recording semantic validation.
- [ ] Implement scoped atomic archive, bounds, defensive reads and stale-writer refusal.
- [ ] Exercise physical reload, duplicate/import, incompatible/forged data, pending write
      failure and verified post-promotion reconciliation; require GREEN without leaks.
- [ ] Retain package/storage code, tests and evidence in a focused local commit.

## Task 2: Isolated Viewing Session

Files: create `scripts/replay/player_replay_view_session.gd` and
`tests/replay/player_replay_view_session_test.gd` / `.tscn`.

Interfaces: `configure(replay, target) -> Dictionary`, `seek(index) -> Dictionary`,
`play_to_terminal() -> Dictionary`, `snapshot() -> Dictionary`.

- [ ] Assert an independent actual Player can seek backward/forward and replay real
      movement/time actions; a rejecting target must restore both target and cursor.
- [ ] Run `./tools/run_tests.sh --filter player_replay_view_session --timeout 90`; retain RED.
- [ ] Bind the validated target identity and delegate restore/execution to ReplayPlayer.
- [ ] Reject freed/changed identities; verify source Player and physical archive unchanged.
- [ ] Record focused evidence and retain the viewing boundary in a local commit.

## Following Replay Scope

Native hostile/room/economy recording with periodic authoritative keyframes,
whole-run command capture, bounded compressed chunks, first-divergence reports,
Hub list/player controls and offline export UI complete the subsequent replay lane.
P22A alone does not satisfy the full-product replay gate.
