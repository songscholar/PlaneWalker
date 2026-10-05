# P22A Player Replay Archive Implementation Plan

- Status: Completed / Historical
- Document Role: Historical implementation plan
- Authority Level: Below P22A replay archive specification
- Applies To: Replay packages, SaveService archive and isolated viewing
- Owner: Project integration lead
- Depends On: `../specs/2026-10-05-p22a-player-replay-archive-design.md`
- Implementation Status: Focused archive and isolated viewing complete; whole-run capture and Hub integration remain in following scope
- Completion Evidence: `../../current/2026-10-05-p22a-player-replay-archive-evidence.md`
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

- [x] Create an actual launch Player recording fixture and assert an absent archive fails.
- [x] Run `./tools/run_tests.sh --filter player_replay_archive --timeout 90`; retain RED.
- [x] Implement exact package fields and whole-recording semantic validation.
- [x] Implement scoped atomic archive, bounds, defensive reads and stale-writer refusal.
- [x] Exercise physical reload, duplicate/import, incompatible/forged data, pending write
      failure and verified post-promotion reconciliation; require GREEN without leaks.
- [x] Retain package/storage code, tests and evidence in a focused local commit.

## Task 2: Isolated Viewing Session

Files: create `scripts/replay/player_replay_view_session.gd` and
`tests/replay/player_replay_view_session_test.gd` / `.tscn`.

Interfaces: `configure(replay, target) -> Dictionary`, `seek(index) -> Dictionary`,
`play_to_terminal() -> Dictionary`, `snapshot() -> Dictionary`.

- [x] Assert an independent actual Player can seek backward/forward and replay real
      movement/time actions; a rejecting target must restore both target and cursor.
- [x] Run `./tools/run_tests.sh --filter player_replay_view_session --timeout 90`; retain RED.
- [x] Bind the validated target identity and delegate restore/execution to ReplayPlayer.
- [x] Reject freed/changed identities; verify source Player and physical archive unchanged.
- [x] Record focused evidence and retain the viewing boundary in a local commit.

Retention evidence: `../../current/2026-10-05-p22a-player-replay-archive-evidence.md`.

## Task 3: Physical And Event Isolation

- [x] Reproduce actual same-tree EnemyTank freezing and global fact leakage;
      retain meaningful RED `2NPZK7` from the independent review finding.
- [x] Create a dedicated ReplayWorld, private typed bus and actual Player
      admission; bind the session to both target and independent world.
- [x] Scope shared Player/time/weapon group queries, payload roots and typed
      publication; preserve ordinary production event and replay contracts.
- [x] Verify all five actual weapons and Stop execute in isolated viewing,
      live actors remain unchanged, incoming live room facts cannot change
      viewing state, and tampered worlds/foreign Player admission refuse.
- [x] Require the original full-player, archive and viewing regressions plus
      five-weapon world and typed event publication regression to pass.

## Following Replay Scope

Native hostile/room/economy recording with periodic authoritative keyframes,
whole-run command capture, bounded compressed chunks, first-divergence reports,
Hub list/player controls and offline export UI complete the subsequent replay lane.
P22A alone does not satisfy the full-product replay gate.
