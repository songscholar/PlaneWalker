# P21C Authored Challenges Implementation Plan

- Status: Verified Locally / Complete
- Document Role: Current focused implementation plan
- Authority Level: Execution plan beneath the authored challenge specification
- Applies To: Catalog, pure sessions, actual native flow, physical saves and UI
- Owner: Runtime integration lane
- Implementation Status: Five authored trials, actual Main entry and native bilingual layouts verified locally
- Completion Evidence: `../../current/2026-10-05-p21c-native-authored-challenges-evidence.md`
- Depends On: `../specs/2026-10-05-p21c-authored-challenges-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Five authored objective domains, actual three-Boss flows, strict physical recovery, native Main entry and controller/visual scenes pass with clean logs

> Agentic execution continues under the project's standing authorization.

**Goal:** Offer five playable authored three-Boss trials with real objectives and
durable isolated results.

**Architecture:** Reuse NativeBossArenaBuilder for scenes and frame participants.
Keep catalog/session validation node-free and mode persistence independent from
ordinary Profile. Coordinator projects strict detached data into the existing
DungeonPanelView layout; Root integrates Main/Hub entry.

**Tech Stack:** Godot 4.6.1, GDScript, first-party JSON/CSV and SaveService.

## Global Constraints

- No dependency, paid service, remote publication or external credential.
- Standardized Wanderer 100 HP; fresh stage; five fixed weapon Builds.
- Three production Bosses per set; rules use committed frames, damage and HP.
- Ten historical results per set plus retained fresh best.
- Continued practice cannot replace fresh best.
- Strict admission/stage/terminal CAS and authenticated native completion.
- Chinese/English, 640x360/1280x720 and text scales 1.0/1.5.
- Shared Main/Hub/translation registration edits belong to Root.

## Task 1: Authoritative Catalog And Objective Domain

Files: `assets/production/modes/authored_challenges.json`,
`scripts/modes/authored_challenge_catalog.gd`,
`scripts/modes/authored_challenge_session.gd`,
`tests/unit/modes/authored_challenge_catalog_test.gd`,
`tests/unit/modes/authored_challenge_session_test.gd` and their scenes.

- [x] Add RED catalog tests for five unique weapons and canonical detached data.
- [x] Run the focused catalog/session scenes and retain missing-boundary failures.
- [x] Implement configure(registry), entries(), definition(id), stage(id,index), request(id,index), build_definitions(id), fingerprint().
- [x] Add RED session assertions for each objective boundary, forged receipts, ordered three stages, practice best exclusion and retained best after pruning.
- [x] Implement empty(), valid(), normalized(), objective_passed(), ranks_before(), result identity/receipt validation and retained best projection.
- [x] Run the focused catalog/session scenes and inspect logs before retention.

## Task 2: Physical Native Flow

Files: `scripts/modes/native_authored_challenge_flow.gd`,
`tests/integration/combat/authored_challenge_native_test.gd`,
`tests/integration/save/authored_challenge_checkpoint_test.gd` and scenes.

- [x] Define failing actual arena admission, complete actual Build effects and weapon collision assertions.
- [x] Define failing real terminal/forged notice and all three ordered stage assertions.
- [x] Implement configure(), preview(), start(set_id), next_stage(), continue_session(), abandon(), save_and_return(), retry_save(), retry_native(), reload_saved_session(), close(), current_player(), current_boss().
- [x] Test before/after promotion faults, lost/identical CAS, reentrancy, cold ACTIVE/STAGE_CLEAR, practice status, terminal retry, history pruning, best retention and ordinary Profile isolation.
- [x] Run combat/checkpoint focused scenes and scan script/resource/leak logs.

## Task 3: Actual Player Entry And Native QA

Files: `scripts/modes/authored_challenge_coordinator.gd`,
`scripts/modes/authored_challenge_panel_view.gd`,
`assets/production/localization/authored_challenges.csv`,
`tests/integration/ui/main_authored_challenges_test.gd`,
`tests/ui/authored_challenge_visual_test.gd` and scenes.

- [x] Define missing Main/Hub entry RED, retired-control and controller-pause tests.
- [x] Implement the agreed Coordinator interface and fixed visible command area.
- [x] Root integrates authored_challenges_requested, translation registration, mode locks, pause/music and Hub return.
- [x] Verify five selectors, objectives/Build/route/history, native pause/next, retry/reload, return and stale callbacks.
- [x] Capture eight native viewport/locale/text-scale combinations with loaded production atlases and nonblank pixel assertions; final caption repair verified across forty screenshots.
- [x] Run all authored suites, existing Daily/Rush regressions, localization, document governance, diff checks and read-only dependency audit.
- [x] Write honest milestone evidence, index with Root and retain the precise authored-trial files in the focused local commit.
