# Plane Walker P6 Controller and Accessibility Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: P6 controller, focus, remapping, and accessibility certification evidence
- Applies To: Current start, combat, selection, pause, result, input remapping, settings persistence, subtitles, presentation alternatives, and gameplay-assist snapshots
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p6-controller-accessibility.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Evidence Status: Verified Locally
- Certified HEAD: `fdb9b2376eaa4cb8feb66667446d8af5cf9167ea`
- P6 Integration Commit: `3f71914a5e5abc5c5bea6325976d5202fd0ebde1`
- Full Rollback Boundary: `b4e776f55a3b5d9f55a576f174d2abbd2db9a8f8`

## Completion decision

P6 is locally complete for the Current product surface. Every Current flow is operable through controller actions, modal focus is restored deterministically, remapping is recoverable and keeps both device families reachable, the complete settings payload survives legacy reads and new writes, and runtime presentation/gameplay alternatives are applied through tested interfaces.

This evidence does not claim human comfort, motor-accessibility suitability, subtitle comprehension, or coverage across real controller hardware. Those require authentic external QA. It also does not change the formal release state: M1 remains `M1 Candidate — External Validation Pending` with `0 / 20` external playtest sessions.

## Verified commit chain

| Commit | Deliverable |
|---|---|
| `94de4a4` | Defines the 14-action dual-device controller contract |
| `d95c7c7` | Adds versioned, recoverable global input profiles |
| `ccb3769` | Applies safe remaps, conflict swaps, reset, rollback, and reachability checks |
| `babd9f5` | Centralizes modal focus entry, stacking, recovery, and restoration |
| `8548d09` | Normalizes and persists the complete Current settings payload with legacy v1 compatibility |
| `3e742c1` | Adds the controller-safe in-game remapping panel |
| `adf0069` | Applies audio, text, subtitle, contrast, motion, and hold/toggle alternatives |
| `3f71914` | Integrates Start/Choice/Pause/Result focus, settings UI, assist snapshots, live telegraph scaling, and Current smoke migration |
| `fdb9b23` | Makes line-coverage evidence fail closed instead of inferring coverage from passed scenes |

## Controller and remapping contract

The Current action surface contains 14 required actions:

```text
move_up, move_down, move_left, move_right,
attack, heavy_attack, ranged_attack, dash,
time_stop, time_rewind, time_rift, time_accelerate,
interact, pause
```

Every required action retains at least one keyboard/mouse binding and one controller binding. Conflict resolution swaps occupied bindings rather than leaving an action unreachable. Reset Action and Reset All restore the project defaults.

The global input profile is independent from gameplay saves and content packs:

```text
user://plane_walker/input/input_profile_v1.json
user://plane_walker/input/pending.tmp
user://plane_walker/input/backup_1.json
```

The focused contracts verify codec round-trip behavior, atomic promotion, backup recovery, invalid-profile fallback, runtime application, conflict swapping, cancellation, localized labels, and focus restoration to the pause menu.

## Controller-only flow evidence

`tests/integration/ui/controller_focus_flow_test.tscn` drives real `Input.parse_input_event()` actions and verifies:

```text
Start ui_accept
→ Choice ui_right traversal and wrap
→ pause
→ Pause ui_cancel
→ Choice focus restore
→ Pause ui_down/ui_accept
→ Remap ui_cancel
→ Pause focus restore
→ Settings ui_cancel
→ Pause focus restore
→ Pause ui_cancel
→ Choice focus restore
→ Result ui_accept restart boundary
→ Start focus after a test-safe Main rebuild
```

Choice rejection also recovers the first enabled option. Child-modal cancel closes only the active child and never resumes the run underneath it.

## Settings and runtime alternatives

The version-1 settings document remains read-compatible with the historical six-field payload. New writes contain 16 normalized fields: locale plus 15 settings exposed by the in-game settings panel.

```text
master_volume, music_volume, sfx_volume, dialogue_volume, master_muted,
camera_shake_enabled, hit_flash_enabled, reduced_motion,
text_scale, high_contrast_danger,
subtitles_enabled, subtitle_scale,
ranged_charge_mode,
damage_received_multiplier, enemy_telegraph_scale
```

Verified runtime behavior includes:

- Master, Music, SFX, and Dialogue bus volume application;
- camera-shake, hit-flash, and reduced-motion alternatives;
- non-cumulative UI text scaling;
- subtitle enable/disable and subtitle-specific scaling independent from general UI text scale;
- high-contrast danger colors while retaining geometry and timing cues;
- hold and toggle ranged-charge modes;
- a neutral assist disclosure with no reward or progression penalty;
- run-start recording of both assist values under `accessibility_assists`;
- incoming-damage assist frozen from the run-start snapshot, so mid-run settings changes cannot drift from replay/telemetry configuration;
- telegraph geometry rescaled immediately from authored radius/length without cumulative multiplication.

## Viewport evidence

The logical presentation canvas remains `640×360` with integer scaling. Automated layout contracts verify that Start, Pause, Result, Choice, Input Remapping, Accessibility Settings, subtitles, and the V2 HUD stay inside the logical canvas and the 16-pixel settings/remap safe area.

The settings panel uses a bounded `ScrollContainer`; its neutral assist explanation has a bounded two-line layout. The subtitle presenter is bottom-anchored instead of stretching from a negative top offset.

Automated logical-layout checks are not a substitute for human readability review at physical 1280×720, 1920×1080, handheld, TV-distance, or ultrawide setups.

## Focused verification

The focused gate ran from `/tmp/planewalker-p6-focused-20260929`:

```text
input_action_contract_test
input_binding_codec_test
input_profile_store_test
input_remap_service_test
focus_coordinator_test
input_remap_panel_test
controller_focus_flow_test
accessibility_settings_panel_test
accessibility_settings_flow_test
ranged_charge_accessibility_test
health_component_test
boss_telegraph_test
combat_feedback_runtime_test
pixel_canvas_test
reward_system_smoke
```

Result:

- 15 / 15 focused scenes passed;
- no focused P6 scene reported a script error, parse error, invalid call, missing resource, ObjectDB leak, or RID leak;
- `reward_system_smoke` passed with its one previously classified legacy ObjectDB exit warning;
- localization validation passed;
- GDScript line coverage was not collected and no percentage is inferred from scene counts.

## Unified and detached verification

The active checkout and a clean detached checkout at `fdb9b2376eaa4cb8feb66667446d8af5cf9167ea` both ran:

```bash
./tools/validate_project.sh
```

Both produced the same gate result:

- Shell/CI contract passed with 56 discovered scene tests;
- documentation governance: 28 / 28 passed, zero baseline violations;
- localization contracts: 7 / 7 passed;
- playtest-data contracts: 13 / 13 passed;
- M1 release-gate contracts: 27 / 27 passed;
- GDScript coverage contracts: 5 / 5 passed;
- export contracts: 37 / 37 passed;
- bootstrap import and clean second import passed with only approved sandbox/environment diagnostics;
- Godot scene tests: 56 / 56 passed;
- one previously classified `reward_system_smoke` ObjectDB exit warning remained;
- line coverage remained `not collected (godot_line_coverage_unsupported)`.

Validation logs:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.zxuCTf
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.aLVhnT
```

Certified engine:

```text
Godot 4.6.1.stable.official.14d19694e
```

## Honest evidence boundary

Repository automation proves deterministic mappings, profile recovery, focus ownership, persistence, logical layout, signal behavior, presentation alternatives, assist snapshots, and clean-checkout reproducibility.

The following remain external validation work and are not represented as complete:

- comfort and fatigue with real controllers over full runs;
- motor-accessibility suitability across different player needs;
- subtitle comprehension, reading speed, and TV-distance readability;
- controller diversity, disconnect/reconnect behavior, and platform-specific prompts on production hardware;
- the required 20 authentic external playtest sessions;
- real Windows/Linux/macOS packaged startup, because the workstation still lacks the three Godot 4.6.1 export templates;
- real GDScript line coverage, because the current Godot binary exposes no trusted line-hit provider.

## Gate decision

P6 Controller, Focus, Remapping, and Current Accessibility is `Verified Locally`. Its implementation plan becomes a Historical regression record. P4/P5 runtime-authority and exactly-once event work remains the next active repository phase; M1 and platform publication states are unchanged.
