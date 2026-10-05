# P21C Authored Challenges Implementation Plan

- Status: Approved / Current
- Document Role: Current focused implementation plan
- Authority Level: Execution plan beneath the authored challenge specification
- Applies To: Catalog, pure sessions, actual native flow, physical saves and UI
- Owner: Runtime integration lane
- Depends On: `../specs/2026-10-05-p21c-authored-challenges-design.md`
- Last Verified: 2026-10-05

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

- [ ] Add RED catalog tests for five unique weapons and canonical detached data.
- [ ] Run `./tools/run_tests.sh --filter authored_challenge --timeout 120` and retain missing-boundary failure.
- [ ] Implement configure(registry), entries(), definition(id), stage(id,index), request(id,index), build_definitions(id), fingerprint().
- [ ] Add RED session assertions for each objective boundary, forged receipts, ordered three stages, practice best exclusion and retained best after pruning.
- [ ] Implement empty(), valid(), normalized(), objective_passed(), best(), result identity/receipt validation.
- [ ] Run the focused catalog/session scenes and inspect logs before retention.

## Task 2: Physical Native Flow

Files: `scripts/modes/native_authored_challenge_flow.gd`,
`tests/integration/combat/authored_challenge_native_test.gd`,
`tests/integration/save/authored_challenge_checkpoint_test.gd` and scenes.

- [ ] Define failing actual arena admission, complete actual Build effects and weapon collision assertions.
- [ ] Define failing real terminal/forged notice and all three ordered stage assertions.
- [ ] Implement configure(), preview(), start(set_id), next_stage(), continue_session(), abandon(), save_and_return(), retry_save(), retry_native(), reload_saved_session(), close(), current_player(), current_boss().
- [ ] Test before/after promotion faults, lost/identical CAS, reentrancy, cold ACTIVE/STAGE_CLEAR, practice status, terminal retry, history pruning, best retention and ordinary Profile isolation.
- [ ] Run combat/checkpoint focused scenes and scan script/resource/leak logs.

## Task 3: Actual Player Entry And Native QA

Files: `scripts/modes/authored_challenge_coordinator.gd`,
`scripts/modes/authored_challenge_panel_view.gd`,
`assets/production/localization/authored_challenges.csv`,
`tests/integration/ui/main_authored_challenges_test.gd`,
`tests/integration/ui/authored_challenge_layout_test.gd` and scenes.

- [ ] Define missing Main/Hub entry RED, retired-control and controller-pause tests.
- [ ] Implement the agreed Coordinator interface and fixed visible command area.
- [ ] Root integrates authored_challenges_requested, translation registration, mode locks, pause/music and Hub return.
- [ ] Verify five selectors, objectives/Build/route/history, native pause/next, retry/reload, return and stale callbacks.
- [ ] Capture eight native viewport/locale/text-scale combinations with loaded production atlases and nonblank pixel assertions.
- [ ] Run all authored suites, existing Daily/Rush regressions, localization, document governance, diff checks and read-only dependency audit.
- [ ] Write honest milestone evidence, index with Root and commit precise file lists.
