# Plane Walker P14G Production Flow Evidence

- Status: Implemented / Current
- Document Role: Current focused evidence record
- Authority Level: P14G native dungeon production assembly and interaction verification
- Applies To: Main, Host commands, six dungeon panels, selection safety, controller focus, localization, and five-floor progression
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/plans/2026-10-04-plane-walker-p14g-production-flow.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`
- Last Verified: 2026-10-04
- Evidence Status: Verified Locally
- Certification Status: Complete combined repository gate and reviewed integration commit pending

## Production assembly

Main assembles DungeonFlowCoordinator and six strict native panels for route, map, merchant, event, treasure/rest, and floor transition. RunRuntimeHost exposes revision-checked semantic commands. The panels receive projected state, retire submitted controls, and hand controller focus back through FocusCoordinator. Tab and joystick Back open the map; closing an interaction leaves an explicit map control and allows Interact to reopen it.

Selection freezes the Player, combat controller, authoritative time, and floor-rule advancement. Reward selection owns the existing reward panel and suspends dungeon panels. Launch reward completion returns to the FloorPlan route choices. Physical rest and treasure interactions synchronize RoomRuntime publication after the authority commits, avoiding a second completion.

Two production regressions were reproduced and repaired: a cleared room's floor rule was ticking during reward/route resolution, and pending event UI rejected the authentic empty final-result key before its reward continuation completed. The native five-floor test also exposed leaked enemy damage/death SceneTreeTimers when streamed rooms retired their nodes. Node-owned tween intervals preserve the original 0.08-second flash and 0.2-second death delay and retire with the node.

## Native five-floor verification

`tests/integration/ui/p14_controller_flow_test.tscn` uses the actual Main scene, streamed rooms, Player, reward panel, and Host commands. It clicks native controls through all five authored floors and reaches the terminal final-boss result. It verifies controller focus, map/back/reopen, duplicate retired controls, translation changes, reward safety, rest healing after physical damage, a merchant purchase/service, pending event rewards, all six required room types, floor transitions, and terminal UI cleanup.

For reproducible combat completion it disables AI movement and defeats hostile HealthComponents, allowing their real death signals and EncounterRunner waves to progress. This proves production flow and scene integration; it is synthetic combat and provides no player balance or difficulty evidence. A recoverable rejected event consequence must preserve the exact authoritative snapshot, display feedback, restore decline, and allow the run to continue.

The focused Godot 4.6.1 runs passed with zero unknown leaks and no script errors:

| Filter | Passed scenes | Log directory |
|---|---:|---|
| `p14_controller_flow` | 1 | `/tmp/planewalker-p14g-controller-tween-green` |
| `dungeon_event_panel` | 1 | `/tmp/planewalker-p14g-event-pending-green` |
| `dungeon_view_state_projection` | 1 | `/tmp/planewalker-p14g-projection-pending-green` |
| `enemy_attack_timing` | 1 | `/tmp/planewalker-p14g-enemy-timing-green` |
| `health_component` | 1 | `/tmp/planewalker-p14g-health-green` |
| `hostile_attack_identity` | 1 | `/tmp/planewalker-p14g-hostile-identity-green` |
| `save_envelope` | 1 | `/tmp/planewalker-save-gauntlets-frame-green` |

Earlier focused panel and Save suites passed 12 and 4 scenes respectively in `/tmp/planewalker-p14g-panels-final` and `/tmp/planewalker-p14g-save-suite-final`. The later pending-event and canonical weapon-field regressions are verified separately in the table above. Actual JSON Save round trips preserve descriptor-defined integer reward effects, bow starfall elapsed frames, and gauntlets combo timeout cap while retaining authored floating-point multipliers.

## Visual and localization verification

The graphical panel contract test completed successfully and retained 48 screenshots in `build/p14-ui-screenshots/`: six panels, Chinese/English, and 640x360, 1280x720, 1920x1080, and 3440x1440. It checks safe areas, usable scroll space, wrapped labels, and actual nonempty rendered pixels. The final graphical engine log is `/tmp/planewalker-p14g-panel-screenshots-final.godot.log`. Compact route and merchant screenshots and the wide event screenshot were visually inspected. The insufficient-gold fixture uses the production translation key.

Both localization catalogs contain the production panel captions, availability reasons, services, rarity labels, and format strings. Base Pack hashes are refreshed. `tools/validate_localization.py` passed after the catalog changes.

## Remaining boundaries

### Save continuation repairs

The native controller flow now continues both current and legacy temporary-effect histories through real route/room commands, the next merchant, and three subsequent clears, with physical JSON saves and fresh Player/Facade restoration. The original run-start reward baseline is persisted before the first reward, including saves before the first shop. This fixes the reproduced `LEDGER_PLAYER_MISMATCH` failure without reapplying acquired rewards as a baseline. Merchant restoration also normalizes the JSON definition ledger into a typed array before domain validation.

Malformed baseline snapshots reject before replacing the saved JSON, RunState, permanent Player effects, or temporary effects. Focused GREEN logs are `planewalker-tests.0Rf1XE`; the earlier baseline failure is retained in `planewalker-tests.KCuD80`, and the subsequent typed-array failure in `planewalker-tests.sPWC8y`. These focused results do not replace the final combined gate.

### Certification boundaries

- The integration owner must run the complete combined repository gate and record a reviewed local commit before promoting this focused evidence to full certification.
- P14H owns the strict 150-loadout five-floor Save/Replay and simulation matrix.
- The test does not certify final P15 enemy/boss behavior, event temporary-effect lifetime, final art/audio, or a complete packaged release.
- Authentic human playtests remain 0/20. GDScript line coverage remains `godot_line_coverage_unsupported`.
- Public release, signing, external credentials, and commercial decisions remain outside this record.
