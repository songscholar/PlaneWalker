# Plane Walker Wave 4C Pixel Presentation and Combat Feedback Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: Execution evidence
- Applies To: M1 Pixel Proxy, core animation, combat audio, hit/danger/time-power/camera/VFX/UI feedback
- Implementation Status: Wave 4C M1 technical scope complete; final repository Gate `PASS`
- Owner: UI and pixel presentation lane
- Depends On: `AGENTS.md`, Wave 4C design and implementation plan
- Last Verified: 2026-09-28
- Rollback Point: focused Wave 4C commit recorded in Git history

## Outcome

The M1 runtime now replaces actor greybox polygons at runtime with role-specific programmatic Pixel Proxy silhouettes. The existing `CombatFeedback` autoload is the live coordinator in every main/runtime scene and installs proxies without changing gameplay scenes, collision, attack ranges, action clocks, encounter data, or seeded RNG.

Delivered presentation coverage:

- Player: idle, move, attack, dash, time cast, hit, heal, death, dash afterimage, and committed-rewind path afterimages.
- Ordinary enemies and elite Tank: distinct Chaser/Shooter/Tank silhouettes, move, windup, recovery, hit, death, elite crown/ring language.
- Chrono Warden: largest clock silhouette, phase marks, exposed split core, frozen Time Stop grid, phase luminance, action-family windup cues, recovery, hit, and death.
- Hit feedback: 3-frame light, 5-frame finisher, 6-frame heavy, and 2-frame player-hurt profiles; bounded camera trauma; hard-edge flash; pixel damage text; synthesized impact cues.
- Time feedback: cyan scan-band Time Stop and indigo reverse-chevron Rewind overlays, distinct animation, distinct PCM signatures, and distinct afterimage behavior.
- Danger feedback: amber/red role language, windup pose, telegraph-compatible danger crown, ordinary/elite warning tone, and three Boss action-family pitch groups.
- UI feedback: outlined, tag-colored, pixel-snapped, stepped damage numbers and persistent low-HP edge warning.

## Pixel and audio contracts

- Logical canvas remains 640×360 and project integer scaling remains unchanged.
- Pixel Proxy uses a two-logical-pixel screen unit, compensates for the combat camera's `0.5` zoom, and forces `TEXTURE_FILTER_NEAREST` on proxy and replaced source visuals.
- Attack blade/lunge and dash displacement/stretch read four-direction weapon/facing state without mutating player position, velocity, weapon angle, or Boss state.
- Proxy installation is idempotent and hides the temporary polygon only after binding succeeds.
- Audio uses repository-local deterministic mono 16-bit PCM generated into `AudioStreamWAV` resources at 22,050 Hz.
- `default_bus_layout.tres` defines a dedicated `SFX` bus routed to `Master`.
- Headless validation records cue dispatch but suppresses platform audio playback allocation. Interactive builds use an eight-voice pool.
- Voice completion, run end, combat-scene removal, production reset, and autoload teardown stop voices and clear stream references.
- Hit pause uses a monotonic microsecond deadline instead of rendered-frame counting or `SceneTreeTimer`; 30, 60, and 144 FPS schedules resolve at the same real-time duration and leave no timer/function-state residue.
- Camera shake, hit flash, and reduced motion are runtime-configurable. Reduced motion suppresses camera shake and afterimages and makes continuous overlay motion static.

## Independent review remediation

The 2026-09-28 review found and closed four release-priority defects:

1. Floating damage text now converts actor world coordinates through the active viewport canvas transform. A real `Camera2D` regression uses position `(640, 360)` and zoom `0.5`.
2. Player attack blade/lunge and dash stretch/displacement now use read-only weapon angle and facing across right, down, left, and up. Tests prove the proxy does not change gameplay position, velocity, weapon angle, or Boss UI state.
3. Hit pause now uses monotonic real time and is independent of render FPS.
4. Boss phase, exposure, and Time Stop now change marks, core shape, luminance, and texture pattern rather than relying on color alone.

The same pass also fixed proxy screen sizing at camera zoom `0.5`, added runtime camera-shake/hit-flash/reduced-motion gates, and cached typed actor capabilities outside the per-frame path.

The final P2 closure additionally proves:

- dash/rewind afterimages inherit the source proxy's action scale and camera inverse scale, retain the same screen footprint at zoom `0.5`, and snap to the shared world-pixel unit;
- camera shake, hit flash, and reduced motion have localized pause-menu controls and persist through `GameState` save/load;
- legacy saves without the new keys merge to shake/flash enabled and reduced motion disabled;
- `CombatFeedback` reloads persistent options at startup and receives subsequent setting changes immediately;
- actor velocity capability, player, and player health references are cached, with no `get_property_list()` call remaining in the per-frame presentation paths.

P2 verification additionally ran the pause-menu and persistence subchecks in `reward_system_smoke`, the M1 runtime smoke, and both localization validators. All assertions passed. Reward smoke retains only its previously classified ObjectDB exit warning; no new leak or runtime error was introduced.

Focused verification:

```bash
godot --headless --path . res://tests/presentation/combat_feedback_runtime_test.tscn
godot --headless --path . res://tests/contract/presentation/pixel_canvas_test.tscn
godot --headless --path . res://tests/combat/boss_action_state_test.tscn
godot --headless --path . res://tests/combat/boss_telegraph_test.tscn
godot --headless --path . res://tests/smoke/m1_runtime_smoke_test.tscn
```

All five scenes passed. No script error, parse error, ObjectDB leak, or RID leak was found. The two Boss scenes emitted only the existing macOS headless certificate diagnostic.

## Focused headless evidence

Command:

```bash
godot --headless --verbose --path . --scene tests/presentation/combat_feedback_runtime_test.tscn
```

Result:

- All Pixel Proxy, animation, profile, audio, cleanup, overlay, and floating-text assertions passed.
- No `SCRIPT ERROR`, parse error, ObjectDB leak, or RID leak.
- The cleanup regression starts overlapping synthesized cues, calls the production reset, and proves zero active voices and zero assigned voice streams.

Additional focused commands:

```bash
godot --headless --verbose --path . --scene tests/combat/boss_telegraph_test.tscn
godot --headless --verbose --path . --scene tests/combat/enemy_attack_timing_test.tscn
godot --headless --verbose --path . --scene tests/reward_system_smoke.tscn
```

Result:

- Boss and ordinary-enemy tests passed without new leaks.
- Legacy reward smoke passed its hit-pause restoration regression.
- Reward smoke retains only its pre-existing classified timer/ObjectDB exit warning.

## Full scene-suite evidence

Command:

```bash
./tools/run_tests.sh
```

Result:

- 33/33 discovered Godot scene tests passed.
- 0 failed scenes.
- 1 known classified leak warning: legacy `tests/reward_system_smoke.tscn`.
- Evidence log directory: `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-tests.9bvBpo`.

The passing suite includes Pixel Canvas, Wave 4C feedback, Boss action/telegraph, elite active mechanic, enemy timing, Rewind Echo, rewind cancellation/transaction, Time Stop resistance, M1 runtime smoke, HUD, application, dungeon, reward, and telemetry scenes.

## Unified validation evidence

Command:

```bash
./tools/validate_project.sh
```

Wave 4C integration result:

- Shell/CI contract passed with 33 discovered scenes.
- Localization contracts passed: 7 tests.
- Playtest data contracts passed: 13 tests.
- M1 release-gate contracts passed: 11 tests.
- Bootstrap import passed with only classified sandbox environment diagnostics.
- Strict clean second import passed without project errors.

The earlier validation-specific telemetry output-path regression was subsequently isolated and repaired before the formal M1 candidate. It is no longer an open Wave 4C or repository Gate failure.

Final trusted candidate:

- Commit: `79a20fd183fb57b8bdf62019ab80ff3f6e430635`
- Repository Gate: `PASS`
- 30-seed matrix digest: `ba174ad596f7f2babe0fe632554af6394dd18042597abc3d93332a1cf3cbe678`
- Authoritative repetitions: two; exact digest match
- Authentic human sessions: `0 / 20`
- Matching structured observations: `0 / 20`
- Experience tuning authorized: `false`

## Stability coordination

The Wave 4D lane reran its authoritative 30-seed matrix twice after the production audio lifecycle fix. Both passes matched digest `ba174ad596f7f2babe0fe632554af6394dd18042597abc3d93332a1cf3cbe678` and completed without `AudioStreamWAV`, `AudioStreamPlaybackWAV`, ObjectDB, or RID leakage. This validates the exact rapid `main.queue_free()` plus five-frame cleanup path that originally exposed the issue.

## Known limitations

- Pixel Proxy and synthesized PCM are production-capable M1 placeholders, not final authored character sheets or mastered audio.
- Subjective mix balance, controller rumble, and human response/readability scores remain Wave 4D external-playtest evidence.
- Authentic external evidence is `0 / 20`; no subjective experience tuning or `M1 Go` claim is authorized from repository/synthetic evidence.

## Retention decision

Retain the implementation. It is isolated behind presentation interfaces, preserves gameplay contracts, has clean rollback boundaries, and gives final art/audio a stable replacement surface without reworking combat logic.
