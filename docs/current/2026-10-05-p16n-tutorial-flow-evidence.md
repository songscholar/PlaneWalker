# P16N Native Tutorial Flow Evidence

- Status: Implemented / Current
- Document Role: Current focused native tutorial integration evidence
- Authority Level: Tutorial coordinator and physical Profile presentation boundary
- Applies To: TutorialFlowCoordinator, real Registry/Host/Player/Profile/remap integration
- Owner: Project onboarding implementation lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-05-plane-walker-p16n-tutorial-flow-design.md`, `docs/superpowers/plans/2026-10-05-plane-walker-p16n-tutorial-flow.md`
- Last Verified: 2026-10-05
- Evidence Status: Verified Locally
- Certification Status: Native coordinator verified; production Main routing owned by its milestone
- Engine: Godot 4.6.1

## Implemented

`TutorialFlowCoordinator` configures from the actual active Registry, physical
ProfileRuntimeService, Host-owned Player and InputRemapService. It owns the
native recall and saved-hint scenes in layer 42. Binding freezes native Run,
Player generation and durable launch identity and uses only the exact
service-issued adapter. `is_live_binding()` also rejects retired adapter clocks.

The coordinator publishes authored hints only from successful persisted service
results after validating the current binding again. It never publishes from
`observation_saved` callbacks. One observation is processed per frame; Hub,
tree/domain pause, review, terminal and replaced participants do not drain.

F1 toggles review. Parent Hub/pause menus may call `open_review("controller")`;
native controller B closes it. Review owns only a pause it acquired and resumes
only the same Run/Player/generation. Real InputMap remaps refresh the view.
Physical skip and suppression failures restore retry controls and preferences.
Physical publication drift clears hints and supports native participant recovery.

Production passes `guided_policy_available = false`. This separates Hub training
availability from mode policy capability and hides the unavailable selector.
Training emits an authenticated task/revision request for the native training
milestone; this coordinator creates no training receipt or reward.

## Verification

- Missing-coordinator RED: `planewalker-tests.T7C1Ae`, required implementation assertion failed.
- Base native Main GREEN: `planewalker-tests.fFx3H3`, 1/1.
- Extended physical callback/recovery GREEN: `planewalker-tests.nTCLcC`, 1/1.
- Independent review recovery fix: `planewalker-tests.rKyPNT`, 1/1, saved-callback adapter detachment preserves recovery participants across automatic drain/rebind attempts.
- Tutorial regression: `planewalker-tests.XnLVFs`, 7/7, no script errors or leaks.
- Final regression after recovery fix: `planewalker-tests.asIJ51`, 7/7, no script errors or leaks.
- Final editor import: `/private/tmp/plane-walker-p16n-import-final.log`, completed with no script errors or leaks.
- Existing pinned Python development dependency audit: `python3 -m pip_audit --disable-pip --no-deps -r requirements-dev.txt`, no known vulnerabilities; no dependency changes in this milestone.
- Real native OpenGL test: `/private/tmp/plane-walker-p16n-render.log`, all assertions passed, no script errors or leaks.
- Two screenshots under `build/visual-evidence/p16n-tutorial-flow`; sampled canvas pixels are nonblank and inspected Chinese glyphs/bounds are readable.
- `git diff --check`: passed.

The actual Main test covers physical skip/suppression and observation promotion
failures; save-before-hint order; no paused/modal draining; controller cancel;
pause ownership; committed real remap labels; no duplicate save; physical callback
drift and native recovery; retirement during saved notification; stale Player
generation and detached adapter refusal. Saved callback detachment retains the
physical recovery context until actual recovery succeeds. Existing UI regression covers bilingual
layout, text scales 1.0/1.5, four resolutions and native focus traversal.

The sandboxed graphical launch could not connect to macOS display services and
was terminated. The scoped display-enabled native rerun passed. An editor import
initially overlapped the parallel Hub coordinator's temporary Panel-name parse
error; its owner corrected that independently.

Godot line coverage is unavailable in this engine build. These are executable
scene and physical-state assertions, not a numerical coverage claim. Training,
independently frozen guided policy, death/Hub trigger occurrence adapters and
Main menu integration remain outside this coordinator's completion claim.

## Integration API

- `configure(registry, service, host, player, remap) -> Dictionary`
- `bind_active_run(player = null) -> Dictionary`
- `open_review(family = "") -> Dictionary`; family accepts keyboard_mouse/controller.
- `close()`: closes review and releases its own valid pause.
- `retire_active_run()`: retires observer and clears old hint.
- `recover_active_run() -> Dictionary`: restores physical native participants and replaces issued adapter.
- `handle_input(event) -> bool`; call before other modal handlers.
- `process_pending_observations() -> Dictionary`; automatic one-per-process-frame drain.
- `review_panel()` and `hint_presenter()` expose native presentation for integration/QA.
- `training_requested(task_id, expected_revision)` and `observation_rejected(code)` signals.

No Main/GameState/Hub files were edited by this milestone. Local commits remain
reversible and no remote push or publication is performed.
