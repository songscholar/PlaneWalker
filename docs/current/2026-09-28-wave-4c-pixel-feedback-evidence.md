# Plane Walker Wave 4C Pixel Presentation and Combat Feedback Evidence

- Status: Verified / Completed for Wave 4C
- Authority Level: Execution evidence
- Applies To: M1 Pixel Proxy, core animation, combat audio, hit/danger/time-power/camera/VFX/UI feedback
- Implementation Status: Wave 4C complete; repository-wide validation has one concurrent Wave 4A telemetry-path failure recorded below
- Owner: UI and pixel presentation lane
- Depends On: `AGENTS.md`, Wave 4C design and implementation plan
- Last Verified: 2026-09-28
- Rollback Point: focused Wave 4C commit recorded in Git history

## Outcome

The M1 runtime now replaces actor greybox polygons at runtime with role-specific programmatic Pixel Proxy silhouettes. The existing `CombatFeedback` autoload is the live coordinator in every main/runtime scene and installs proxies without changing gameplay scenes, collision, attack ranges, action clocks, encounter data, or seeded RNG.

Delivered presentation coverage:

- Player: idle, move, attack, dash, time cast, hit, heal, death, dash afterimage, and committed-rewind path afterimages.
- Ordinary enemies and elite Tank: distinct Chaser/Shooter/Tank silhouettes, move, windup, recovery, hit, death, elite crown/ring language.
- Chrono Warden: largest clock silhouette, phase-safe coloring, action-family windup cues, recovery, hit, and death.
- Hit feedback: 3-frame light, 5-frame finisher, 6-frame heavy, and 2-frame player-hurt profiles; bounded camera trauma; hard-edge flash; pixel damage text; synthesized impact cues.
- Time feedback: cyan scan-band Time Stop and indigo reverse-chevron Rewind overlays, distinct animation, distinct PCM signatures, and distinct afterimage behavior.
- Danger feedback: amber/red role language, windup pose, telegraph-compatible danger crown, ordinary/elite warning tone, and three Boss action-family pitch groups.
- UI feedback: outlined, tag-colored, pixel-snapped, stepped damage numbers and persistent low-HP edge warning.

## Pixel and audio contracts

- Logical canvas remains 640×360 and project integer scaling remains unchanged.
- Pixel Proxy uses a two-logical-pixel unit and forces `TEXTURE_FILTER_NEAREST` on proxy and replaced source visuals.
- Proxy installation is idempotent and hides the temporary polygon only after binding succeeds.
- Audio uses repository-local deterministic mono 16-bit PCM generated into `AudioStreamWAV` resources at 22,050 Hz.
- `default_bus_layout.tres` defines a dedicated `SFX` bus routed to `Master`.
- Headless validation records cue dispatch but suppresses platform audio playback allocation. Interactive builds use an eight-voice pool.
- Voice completion, run end, combat-scene removal, production reset, and autoload teardown stop voices and clear stream references.
- Hit pause uses an explicit rendered-frame budget instead of `SceneTreeTimer`, so rapid matrix exit leaves no timer or function-state residue.

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

Result before the scene-suite stage:

- Shell/CI contract passed with 33 discovered scenes.
- Localization contracts passed: 7 tests.
- Playtest data contracts passed: 13 tests.
- M1 release-gate contracts passed: 11 tests.
- Bootstrap import passed with only classified sandbox environment diagnostics.
- Strict clean second import passed without project errors.

The command then reproduced a concurrent Wave 4A telemetry output-path failure in `tests/unit/telemetry/playtest_recorder_test.tscn` under the validation-specific `user-data` directory. Its JSONL parent/path could not be opened. The same telemetry scene passed in the immediately preceding standalone 33/33 suite. Wave 4C presentation, audio, runtime smoke, import, and cleanup tests all passed inside the unified run. Evidence log directory: `/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.75wX9n`.

This failure is recorded for the integration owner and is not masked, filtered, or modified by the Wave 4C lane.

## Stability coordination

The Wave 4D lane reran its 30-seed matrix twice after the production audio lifecycle fix. Both passes completed without `AudioStreamWAV`, `AudioStreamPlaybackWAV`, ObjectDB, or RID leakage. This validates the exact rapid `main.queue_free()` plus five-frame cleanup path that originally exposed the issue.

## Known limitations

- Pixel Proxy and synthesized PCM are production-capable M1 placeholders, not final authored character sheets or mastered audio.
- Subjective mix balance, controller rumble, and human response/readability scores remain Wave 4D external-playtest evidence.
- The repository-wide validation command remains non-zero until the concurrent telemetry output-path regression is integrated; Wave 4C's own focused and full scene gates are green.

## Retention decision

Retain the implementation. It is isolated behind presentation interfaces, preserves gameplay contracts, has clean rollback boundaries, and gives final art/audio a stable replacement surface without reworking combat logic.
