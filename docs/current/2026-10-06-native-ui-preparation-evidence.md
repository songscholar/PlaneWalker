# Native UI Preparation Audit

- Status: Prepared / Current
- Document Role: Current read-only UI preparation and source audit
- Authority Level: Preparation evidence below the approved UI design
- Applies To: Native UI ownership, existing contracts and future font vendoring
- Owner: Project integration lead
- Depends On: [UI design](../superpowers/specs/2026-10-06-native-ui-finish-design.md), [UI implementation plan](../superpowers/plans/2026-10-06-native-ui-finish.md)
- Last Verified: 2026-10-06
- Implementation Status: Not started; no UI runtime, art, font or test implementation in this preparation milestone

## Scope And Evidence Boundary

The inspected production UI source is commit
`8011d1bfa86c8cb1fbc266226ba67a324249ee6e`. The existing native interaction
flows and tests listed below are reusable foundations, not proof of finished
presentation or a new passing test run. The 49-state registry and 784-image
matrix remain planned; this audit produced neither. UI implementation starts
only after the integration lead records the gameplay milestone passing.

Read-only network inspection retrieved official Google Fonts metadata,
licenses and font binaries into process memory. It created no font files,
asset files, project dependencies or resource manifests. Standard SFNT table
records and their bounds were inspected to read actual binary names/versions;
Git blob SHA-1 and whole-file SHA-256 were checked. The preparation hashes
identify the exact observed bytes and must be checked again against the
actual files retained by Task 1.

## Official Font Sources

| Font | Official binary | Observed binary identity | Bytes | SHA-256 | Git blob SHA-1 |
|---|---|---|---:|---|---|
| Noto Sans SC | [NotoSansSC[wght].ttf](https://github.com/google/fonts/blob/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf) | `Version 2.004-H2;hotconv 1.0.118;makeotfexe 2.5.65603` | 17,772,300 | `a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da` | `fb0637bafbcd804fe32152370a1225990745b4bc` |
| Pixelify Sans | [PixelifySans[wght].ttf](https://github.com/google/fonts/blob/main/ofl/pixelifysans/PixelifySans%5Bwght%5D.ttf) | `Version 1.000` | 79,160 | `9ba86cd010a4de309d263ceff8e8044092c9db7efda869620cb9ff1c4389e8a5` | `2d7eb388ee499fbcf3e992723ec409c095640104` |

The immutable binary read sources are the GitHub
[Noto blob](https://api.github.com/repos/google/fonts/git/blobs/fb0637bafbcd804fe32152370a1225990745b4bc)
and [Pixelify blob](https://api.github.com/repos/google/fonts/git/blobs/2d7eb388ee499fbcf3e992723ec409c095640104).
The `main` links above describe official filenames, not immutable releases.

Noto's name records are family `Noto Sans SC Thin`, subfamily `Regular` and
PostScript `NotoSansSC-Thin`. Google Fonts metadata declares variable weight
100-900 and the upstream
[noto-cjk source commit](https://github.com/notofonts/noto-cjk/tree/523d033d6cb47f4a80c58a35753646f5c3608a78).
Pixelify's records are family `Pixelify Sans`, subfamily `Regular` and
PostScript `PixelifySans-Regular`. Metadata declares variable weight 400-700
and the upstream
[Pixelify source commit](https://github.com/eifetx/Pixelify-Sans/tree/39df74aba80df8157546034b878e8be1eb565ced).
Noto supplies Simplified Chinese and body text. Pixelify has Latin/extended
Latin/Cyrillic coverage and cannot serve as the Chinese font. No shipping
localization glyph coverage was certified here; Task 1 must check the actual
vendored FontFiles against all shipping CSV code points through Godot.

| Complete official license | Version / copyright | Bytes / line endings | SHA-256 | Git blob SHA-1 |
|---|---|---|---|---|
| [Noto OFL.txt](https://github.com/google/fonts/blob/main/ofl/notosanssc/OFL.txt) | SIL OFL 1.1; Adobe 2014-2021; Reserved Font Name `Source` | 4,388 / LF | `1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9` | `1c9f43281b8f216c5461fe9ac729afbade7724e4` |
| [Pixelify OFL.txt](https://github.com/google/fonts/blob/main/ofl/pixelifysans/OFL.txt) | SIL OFL 1.1; Pixelify Sans Project Authors 2021 | 4,488 / CRLF | `b66ba46f511a851ab09998b5a5a9fdbb102545a3864cb993095e1745996873a7` | `6aa5bfbae9e8654b83e5fff942b9540830403022` |

Both full license texts were read. Vendoring must bundle the complete
copyright/license notices, retain upstream identity and obey the OFL terms,
including the restriction on selling fonts alone and Reserved Font Names for
modified fonts. A filesystem rename to the plan's `NotoSansSC.ttf` or
`PixelifySans.ttf` does not modify the internal font family. Preserve exact
license bytes, including Pixelify's CRLF, in the future manifest.

## Existing Contract And Focus Owners

`scripts/ui/dungeon_panel_view.gd` owns the shared panel lifecycle. Its
`render` validates and copies the state, rejects stale revisions, preserves
an equal visible snapshot, resets submission state and increments `_epoch`
before rebuilding rows. It applies accessibility, links a native focus ring
and opens or recovers the active scope. `_activate_action` rejects stale
epochs, duplicate submission, hidden owners and disabled controls. Closing
restores the prior focus through FocusCoordinator. Shared chrome changes
must preserve `panel_root`, `rows_container`, `scroll`, `footer` and
`back_button`, or provide a verified equivalent before dependent pages run.

Hub selectors, build/share draft fields, footer actions and epoch callbacks
belong to `scripts/ui/hub_panel_view.gd`. The stale plan-tail path
`scripts/hub/hub_panel_view.gd` was corrected. Training flow ownership is
`scripts/training/training_flow_coordinator.gd`; tutorial flow ownership is
`scripts/onboarding/tutorial_flow_coordinator.gd`.

Ending credits already exist. `NarrativeViewModel.credits` projects
`mode == "credits"`, the authored `ending.credits_key`,
`close_available == false` and the existing skip action.
`NarrativeFlowCoordinator.show_selected_credits`/`resume_selected_credits`
and Main bind completion to the selected-ending receipt. The finish task
adds composition and actual license entries while retaining that flow.

Remap conflicts already cause an atomic service swap. InputRemapPanel's
successful `SWAPPED` result displays `UI_BINDING_CONFLICT_SWAPPED`, closes
capture and recovers the first binding focus. A distinct retained
`remap_conflict` visual fixture and polished status are still required. The
plan does not add a confirmation policy or new binding command.

## Complete 49-State Map

Paths below are repository-relative; tests named in the last column exist
unless explicitly described as future finish tests. They identify the
regressions to run after implementation, not results of this audit. Every
group requires the planned four resolutions, two locales and two text scales.

| State ids | Count | Production owner and read-only source | Focus entry / preserved command contract | Existing regressions |
|---|---:|---|---|---|
| `combat`, `low_hp`, `boss`, `active_item_cooldown`, `build_status`, `map_inset` | 6 | `scripts/ui/views/combat_hud_view.gd`, `scenes/ui/combat_hud_v2.tscn`; RunViewState schema 5 and validated DungeonMapViewState for inset | Noninteractive CanvasLayer; preserve `show_hud`, phase, exact copied snapshot and strict run/revision refusal | `tests/ui/combat_hud_v2_scene_test.gd`, `run_view_state_contract_test.gd`; loadout/time/replay contracts |
| `council_district`, `craft_district`, `rift_district` | 3 | `scripts/hub/hub_flow_coordinator.gd`, `hub_district_scene.gd`, `hub_scene_host.gd`; three `scenes/hub/` scenes, district definitions and HubViewState | Walk/interact; mapped menu/focus-next opens toolbar scope at DistrictSelector; travel preserves epoch and restores selector | `tests/ui/main_hub_visual_test.gd`, `hub_native_visual_test.gd`; `tests/integration/ui/hub_scene_streaming_test.gd`, `main_hub_flow_test.gd` |
| `council`, `forge` | 2 | `scripts/ui/hub_panel_view.gd`; HubViewState nodes/forge/currencies | First available command or Back; selected weapon, exact cost and command id/revision/epoch remain authoritative | `tests/integration/ui/main_hub_commands_test.gd`; Main Hub visual tests |
| `gateway` | 1 | HubPanelView, existing launch/candidate loadout scripts/scenes; HubViewState.loadout, RunLoadoutCatalog/RunConfig | Character selector first, then weapon/time pair; exactly two equipped time slots and reachable launch/resume footer | `tests/ui/launch_loadout_panel_test.gd`, `candidate_loadout_panel_test.gd`; `tests/integration/ui/launch_loadout_flow_test.gd` |
| `meditation` | 1 | HubPanelView; HubViewState.builds | Build name then save, share code then actions; preserve `_name_draft`/`_share_draft` across rebuilds | `tests/integration/ui/main_build_sharing_test.gd`; `tests/integration/save/hub_build_sharing_test.gd`; `tests/ui/build_sharing_visual_test.gd` |
| `archive`, `gallery`, `mirror` | 3 | HubPanelView, `scripts/ui/hub_cosmetics_panel.gd`; HubViewState collections/cosmetics | Available collection actions/Back; gallery reward navigation restores Hub scope | `tests/integration/ui/main_cosmetics_test.gd`, `main_local_records_test.gd`, `main_challenge_rewards_test.gd`; `tests/ui/local_records_visual_test.gd` |
| `training_function`, `merchant_function` | 2 | HubPanelView training/providers branches and HubFlow; HubViewState dialogue/providers | Existing tutorial route or provider-refresh commands, exact provider id and Hub focus return; Platform opens from Mirror | Main Hub commands/flow; `tests/integration/training/main_training_flow_test.gd`; local-record/provider tests |
| `choice_item`, `choice_blessing`, `choice_curse` | 3 | `scripts/ui/views/choice_panel_view.gd`, `scenes/ui/choice_panel_v2.tscn`; SelectionOffer | First option; replacement confirmation focuses Cancel; retain offer id/revision/submission and mandatory dismissal rules | `tests/ui/choice_panel_v2_scene_test.gd`; selection/replay/controller contracts |
| `route_map` | 1 | `scripts/ui/dungeon_map_panel.gd`, `route_choice_panel.gd`, their scenes; DungeonMapViewState | Details focus is presentation-only; activation emits existing edge id/expected revision; hidden nodes remain unknown | `tests/ui/dungeon_map_panel_test.gd`, `route_choice_panel_test.gd`, `p14_panel_visual_contract_test.gd`; P14 controller flow |
| `shop` | 1 | `scripts/ui/merchant_panel.gd`, `scenes/ui/merchant_panel.tscn`; MerchantViewState | First available offer/action; exact price, action/offer id/revision and leave policy | `tests/ui/merchant_panel_test.gd`; P14 visual/controller flows |
| `event` | 1 | `scripts/ui/dungeon_event_panel.gd`, its scene; DungeonEventViewState | Available choices/actions/Back according to pending/reward state; preserve source revision | `tests/ui/dungeon_event_panel_test.gd`; native event/runtime integrations |
| `narrative` | 1 | `scripts/ui/narrative_panel_view.gd`; narrative flow/view model and NarrativeViewState | First available action; Back only when `close_available`; reveal never changes source state | `tests/integration/narrative/main_narrative_flow_test.gd`, `narrative_flow_coordinator_test.gd`; narrative checkpoint tests |
| `floor_transition` | 1 | `scripts/ui/floor_transition_panel.gd`, its scene; FloorTransitionViewState | Explicit transition command; never auto-accept | `tests/ui/floor_transition_panel_test.gd`; dungeon/controller flows |
| `defeat`, `victory` | 2 | `scripts/ui/run_end_overlay.gd`, inline Main nodes; terminal RunPhase and EventBus.run_ended result | RestartButton, Hub return or save retry; `_presented_run_id` guard; no standalone result ViewState today | `tests/integration/ui/main_player_lifecycle_test.gd`; Main narrative and terminal checkpoint flows |
| `ending_credits` | 1 | NarrativePanelView, NarrativeViewModel.credits and narrative coordinator; NarrativeViewState `mode=credits`, authored ending key | Existing skip action, unavailable generic close, chosen-ending receipt and cold-resume flow | Main narrative flow/checkpoint and terminal fragment traversal tests |
| `pause` | 1 | `scripts/ui/pause_menu.gd`, inline Main nodes | `show_pause` focuses Resume; nested settings/remap restores prior owner | `tests/integration/ui/controller_focus_flow_test.gd`, `accessibility_settings_flow_test.gd`, `main_player_lifecycle_test.gd` |
| `settings` | 1 | `scripts/ui/accessibility_settings_panel.gd`, its scene; GameState setting definitions/AccessibilityRuntime | First setting, native ring and Back; preserve live language/text scale/reduced motion and stored keys | `tests/integration/ui/accessibility_settings_panel_test.gd`, `accessibility_settings_flow_test.gd` |
| `remap_capture`, `remap_conflict` | 2 | `scripts/ui/input_remap_panel.gd`, its scene; InputRemapService and input label codec | First binding; capture readiness frame/B cancel; existing `SWAPPED` status and first-binding recovery | `tests/integration/ui/input_remap_panel_test.gd`; `tests/unit/input/input_remap_service_test.gd` |
| `tutorial_list` | 1 | `scripts/ui/tutorial_panel.gd`, scene; onboarding coordinator and TutorialViewState | Available lesson skip/toggles/training/Back and existing revisions | `tests/ui/tutorial_panel_test.gd`; tutorial coordinator/native-adapter integration tests |
| `tutorial_hint` | 1 | `scripts/ui/tutorial_hint_presenter.gd`, scene; TutorialViewState | Nonblocking; no modal focus; successful-frame display duration/context clearing | Tutorial panel captures and onboarding contracts |
| `training_arena` | 1 | `scripts/training/training_panel_view.gd`, `training_flow_coordinator.gd`, `training_arena.gd`; progress/request/resource copies | Coordinator focuses task selector; practice closes scope; return restores it; existing play/reset/back signals | `tests/integration/training/main_training_flow_test.gd`, `training_arena_flow_test.gd`, `native_training_flow_test.gd` |
| `boss_rush`, `stage_clear` | 2 | `scripts/modes/boss_rush_panel_view.gd`, coordinator presentation; existing exact request/session/active/paused/pending/save-error dictionary | Available start/resume/continue/next/carried-choice/retry/reload then Back; pending return lock | `tests/ui/boss_rush_visual_test.gd`; Main/native/carried/checkpoint Boss Rush tests |
| `daily` | 1 | `scripts/modes/daily_boss_panel_view.gd`, coordinator presentation; preview/condition keys/content names | DailyCommands stays outside details scroll; available native actions, abandon-aware Back and pending lock | `tests/ui/daily_boss_visual_test.gd`; Main/native/build/reward/checkpoint daily tests |
| `authored` | 1 | `scripts/modes/authored_challenge_panel_view.gd`, coordinator presentation; strict preview/session/catalog validation | ChallengeSelector first when available; AuthoredCommands outside scroll; pending close refusal | `tests/ui/authored_challenge_visual_test.gd`; Main/coordinator/native/build/checkpoint authored tests |
| `endless` | 1 | `scripts/modes/endless_panel_view.gd`, coordinator presentation; EndlessSession.valid and BossRushCatalog.valid_request | Available start/resume/continue/next/retry/reload/Back | `tests/modes/endless_native_test.gd`, `endless_coordinator_test.gd`, `endless_session_test.gd`, `endless_checkpoint_test.gd` |
| `mode_result` | 1 | All four existing mode panels/coordinators and terminal preview/session histories | Each actual mode's retry/save/return policy and terminal identity | Existing Boss Rush/daily/authored visual matrices include victory; future Task 8 mode finish coverage must retain terminal variants |
| `challenge_rewards` | 1 | `scripts/ui/challenge_rewards_panel.gd`; exact ProfileRuntimeService.challenge_reward_view model plus epoch/revision | Native reward checkbox/refresh/Back; actual equip policy and Gallery focus return | `tests/integration/ui/main_challenge_rewards_test.gd`; `tests/ui/challenge_equipment_visual_test.gd`; equipment integration tests |
| `replay_empty`, `replay_playback` | 2 | `scripts/replay/player_replay_library_panel.gd`; actual library rows/snapshot/current_world and local revision | Empty import/Back; actual ReplayPicture SubViewport, ReplayTimeline, speed/actions and native dialog cancel/stale-delete refusal | `tests/replay/player_replay_library_panel_test.gd`; `tests/integration/ui/main_replay_library_test.gd` |
| `platform`, `platform_offline` | 2 | `scripts/platform/platform_panel.gd`; PlatformServiceCoordinator model/section/revision | SectionSelector first, optional name, actions/Back; actual capabilities/status and offline navigation | `tests/platform/platform_panel_test.gd`, `offline_platform_test.gd`; `tests/integration/ui/main_product_modes_test.gd` |
| `mods`, `mod_rejected` | 2 | `scripts/ui/content_management_panel.gd`; installed/activation/locked/diagnostics/entitlements/epoch dictionary | Available install/refresh/check/remove/Back; locked exit remains reachable; native FileDialog and real quarantine diagnostics | `tests/ui/content_management_panel_test.gd`; content-manager contract/integration tests |

Counts are HUD 6, Hub 12, run panels 7, progress/results 4, settings 4,
onboarding 3, modes 7, replay 2 and platform/content 4, totaling 49. State ids
must be group-prefixed in the future registry. RoomInteractionPanel/rest
states and all four mode result variants are additional useful captures;
they do not replace any minimum state. This audit located full-resolution
visual matrices for Boss Rush, daily and authored challenges, but no
equivalent dedicated endless visual matrix.

The four mode coordinators each build their own text HUD. Task 3's normal
CombatHud changes cannot finish those scenes. Task 8 explicitly replaces
their presentation using copied Player/Boss/session facts and the planned
validated ModeCombatHud adapter while preserving native gameplay flow.

## Concrete Parallel Ownership

Task 1 resources and Task 2 shared Theme/components must pass before the
three page lanes start. Every new test named below remains future work.

| Lane | Exclusive files and deliverables | Handoffs and sequencing |
|---|---|---|
| Integration lead | Task 1 art/font generation, recipes/binaries/license manifests; Task 2 shared Theme/catalog/chrome/components; shared contracts, localization CSVs, `scripts/main.gd`, `scenes/main.tscn`, `project.godot`; Task 10 registry/capture/verification/final evidence | Integrates worker assembly, common-contract and localization patches; owns final clean-checkout/input/export certification. No page lane edits shared chrome/catalog or Main independently. |
| Combat | Task 3 `combat_hud_view.gd`/scene, new build inspector/map inset and their scoped tests; Task 8 four mode panel scripts and coordinator presentation sections, challenge_rewards_panel, pure mode-HUD adapter/view/scenes and mode visual tests | Sends Pause build-tab assembly request to lead/Run lane. Sends new ModeCombatHudViewState contract to lead. Task 8 waits for Task 5 RewardCard and Task 6 ResultSummary; no native mode-flow or combat-authority edits. |
| Hub/product | Task 4 HubPanelView, HubFlow/district presentation, HubCosmeticsPanel, launch/candidate loadout scripts/scenes, new hub-page builders and Hub/build/local-record tests; then Task 9 replay/platform/content panel layouts and their scoped tests/scenes | Keeps all Hub commands/drafts in existing owner. Sends Main routing/assembly changes to lead. Existing local-record tests stay in this lane for both Tasks 4 and 9. |
| Run/accessibility | Tasks 5/6 choice/map/route/merchant/room/event/narrative/result/transition scripts/scenes; new RewardCard/RouteGraph/ResultSummary and tests; then Task 7 pause/settings/remap/tutorial/hint/training presentation and scoped tests | Publishes RewardCard/ResultSummary interfaces before Combat Task 8. Sends inline Main replacement/localization to lead. Task 7 waits for Task 3 build inspector. Training/onboarding coordinator mutation remains with existing gameplay ownership. |

The lead reviews exact file lists before each focused commit. Workers send
shared-file changes as integration requests, retain actual assertion RED
and scoped GREEN evidence, then run the current command/focus regressions.
The final matrix authenticates the final committed source and assets rather
than attributing historical fixture screenshots to a new candidate.

## Preparation Validation

The 2026-10-06 preparation checked existing source contracts, owned paths,
focus entry points and regression filenames. It read and hash-verified both
official font binaries and both complete licenses in memory. Documentation
governance is the applicable check for this documentation-only milestone:
`PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json --json`
passed with zero violations on 2026-10-06, and `git diff --check` passed.
No UI test run, visual capture, controller hardware validation or product
completion claim is made by this record.
