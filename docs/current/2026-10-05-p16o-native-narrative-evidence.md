# P16O Native Narrative Evidence

- Status: Approved / Current
- Document Role: Current focused native narrative implementation evidence
- Authority Level: Verification evidence below P16O
- Applies To: Narrative coordinator, issued physical occurrences, strict panel projection and durable ending/credits handoff
- Owner: Project narrative implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16o-native-narrative-flow-design.md`, `docs/superpowers/plans/2026-10-05-plane-walker-p16o-native-narrative-flow.md`
- Last Verified: 2026-10-05
- Implementation Status: Native coordinator and focused integration verified; whole-game completion is not asserted
- Exit Gate: Actual contact, physical save refusal/recovery, native bilingual rendering and scanned focused logs pass

## Implemented Boundary

`NarrativeFlowCoordinator.configure(registry, service, host, room_scene_host,
actual_player, combat_runtime_parent)` requires the actual production classes,
Host-owned Player and the already-enabled physical narrative service. The public
flow includes `bind_active_run`, `retire_active_run`, `terminal_victory`,
`open_dialogue`, `show_selected_credits`, `resume_selected_credits`,
`recover_active_run`, `panel`, and `process_pending_contact`.

`ending_selected(ending_id, receipt)` follows successful persistence and native
identity checks. Main performs settlement before `show_selected_credits`.
`credits_completed(ending_id, receipt)` follows a separate successful Profile
write. A saved ending whose callback was retired is recovered from the exact
launch-sequence source marker without choosing twice.

The five modes consume strict detached contracts. Locked unvisited story content
shows only a requirement count. Full Profile objects and domain effect payloads
cannot enter the presentation contract. Buttons retain revision and panel epoch;
stale Profile refusal refreshes the authoritative controls.

Final victory installs the service-issued heart_fragment_5 Area2D at the current
actual boss room's room_exit marker. Collection checks real physics overlap and
is not granted by terminal transition, proximity alone, or fabricated signals.
Neutral terminal motion uses actual CharacterBody2D.move_and_collide. The Player
body remains in physics via an owned KEEP_ACTIVE disable mode while ordinary
Player processing remains disabled; retirement restores its original mode.

## Verification

- Missing coordinator RED: `planewalker-tests.JvNsx3` failed the missing boundary assertion as intended, without leaks.
- Expanded actual Main/Host/Profile/Registry/Player/RoomSceneHost integration: `planewalker-tests.FX8w0G` passed without script errors or leaks.
- Final focused native/Main/physical-service/domain regression: `planewalker-tests.fgynd8`, 5/5 passed. Sandboxed macOS CA-certificate discovery emits the existing platform-only warning; no script errors or leaks occur.
- Tests include no-contact refusal, actual source and Nemesis choice, physical write failures, stale native controls, callback health drift, exact native recovery, blocked rebind during recovery, final heart contact, independent ending and credits failures, retired saved-ending handoff and credits resume.
- Terminal motion compares the full Player replay snapshot with only position removed; every other action/time/weapon/replay/health field is unchanged. Actual Run and reward snapshots are unchanged. External pause blocks movement.
- Actual OpenGL 1280x720 render passed: `/private/tmp/plane-walker-p16o-render-final.log`.
- Expanded actual OpenGL 640x360 render in Chinese and English passed: `/private/tmp/plane-walker-p16o-render-640.log`.
- Inspected nonblank screenshots: `build/visual-evidence/p16o-native-narrative/dialogue-saved.png`, `dialogue-saved-en.png`, `actual-heart-marker.png`, `ending-choices.png`, `ending-choices-en.png`, `credits-pending.png`, `credits-pending-en.png`. Native panel text fits its safe area and scrolls; authored pixel marker renders.
- Existing pinned Python development dependencies audited with `python3 -m pip_audit --disable-pip --no-deps -r requirements-dev.txt`: no known vulnerabilities. The required public advisory query used narrow network access after the sandbox DNS refusal.
- `git diff --check` passed. Documentation metadata is complete; parent owns index entries and consolidated governance run.
- Parent independent review found and fixed the terminal story Back escape and stale-story revision trap. Terminal story now requires Continue; both ordinary and terminal stories reproject their already-saved subject/text after stale refusal. Expanded regression `planewalker-tests.zs7puD` passed without script errors/leaks. `python3 tools/document_governance.py` passed with zero violations after shared index integration.
- Follow-up actual OpenGL 640x360 run passed cleanly: `/private/tmp/plane-walker-p16o-render-review-final.log`, with no script errors, warnings, or leaked resources. Inspected `build/visual-evidence/p16o-native-narrative/terminal-story.png` and `terminal-story-en.png`; saved terminal text wraps correctly and exposes Continue with no Back escape.

The deterministic five-floor integration fixture now uses the shared
NativeLaunchRoute fixture's real route selection, reward commits, room handoffs
and floor entry commands. It stops at each cleared Boss boundary rather than
directly rewriting phases, floor rules or scene bindings. Combat completion and
Boss source receipts remain fixtures; this is not five-Boss Player combat
coverage. A retired ending callback leaves full native publication pending.
The regression reloads the physical Profile into a fresh Main and restores its
authenticated native checkpoint, asserting the complete Player codec, canonical
Run and Profile revision before a new coordinator emits one saved-ending handoff.
Focused regression evidence is recorded in
`2026-10-05-native-narrative-regression-evidence.md`.

## Reversible Decisions And Limits

Current templates expose one authored interaction anchor. Eligible floor sources
are presented one at a time at room_exit after a real room is cleared; actual
boss hearts take priority. Distinct location_id environments, story recall
archive, cinematic credits timing and final room art/audio are later production
milestones. The original small pixel markers are generated locally as raster
ImageTextures, introduce no external asset licensing or dependency changes, and
can be replaced independently of narrative domain state.

This milestone does not prove full Launch visual certification, controller
hardware coverage, clean-checkout distributable certification, or Expansion
completion. Root owns Main integration, localization keys, gameplay/terminal
presentation and consolidated milestone review. No remote push or publication
is performed.
