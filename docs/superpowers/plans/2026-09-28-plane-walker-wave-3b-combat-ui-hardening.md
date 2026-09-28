# Plane Walker Wave 3B Combat and UI Hardening Implementation Plan

- Status: Completed
- Document Role: Historical implementation record
- Implementation Status: Verified by `c4b7e04`, `9cba692`, `f8145c3`, `c13ec9f`, `8f3594d`, `5e55bd4`, and status checkpoint `66da460`
- Completed On: 2026-09-28
- Execution Authority: Superseded by `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Preservation Rule: Combat clock ownership, telegraphing, rewind cancellation, live HUD projection, and 640×360 presentation remain regression requirements.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the isolated action-state and HUD contracts to the real M1 run, add readable enemy/Boss commitment windows, and prepare a verified 640×360 integer-scaled pixel presentation without removing any future-facing content.

**Architecture:** PlayerController becomes the sole owner of player combat frames and PlayerActionState; SwordWeapon and Hitbox become synchronous effect endpoints instead of independent timer owners. EnemyBase and Chrono Warden each gain one explicit attack/action phase, so time stop can delay an existing commitment without inventing new actions. A pure RunViewStateProjector combines authoritative facade state with read-only Player/Boss runtime snapshots and emits a separate monotonic view revision for CombatHudV2.

**Tech Stack:** Godot 4.6.1, GDScript 2.0, physics-frame state machines, existing RunRuntimeFacade/RunViewState contracts, native signals, headless scene tests.

## Global Constraints

- Preserve the complete product vision; Wave 3B changes Current activation and runtime ownership, not the Next/Launch roadmap.
- M1 enables Sword, Time Stop, and Time Rewind; Bow, Time Rift, and Time Accelerate remain implemented and regression-tested but are not accepted by the M1 action dispatcher.
- One subsystem owns each clock: PlayerController owns player combat frames; EnemyBase owns ordinary enemy attack phases; Chrono Warden owns Boss action phases.
- Rewind restores position, velocity, facing, HP, and a safe action state only. It never restores energy, cooldowns, world state, consumed Offers, or defeated enemies.
- UI reads RunViewState only. CombatHudV2 must not mutate GameState, Player, Boss, RunState, or EventBus.
- View revisions are presentation-only and must never advance RunState revision or invalidate SelectionOffer revisions.
- Preserve the user's dirty `project.godot`, `scripts/main.gd`, legacy UI scripts, localization directory, content JSON, and reward-pool changes. If `project.godot` is edited, stage only the display-settings hunk with `git add -p`.
- Existing Wave 0/1/2/3A tests and `tests/reward_system_smoke.tscn` remain regression gates.
- New combat tests must scan logs for `SCRIPT ERROR`, assertion failures, ObjectDB leaks, and resources still in use.

---

## File Ownership

### Lane A: Boss commitment and time-stop interaction

- `scripts/enemies/boss_chrono_warden.gd`
- `tests/combat/boss_action_state_test.gd`
- `tests/combat/boss_action_state_test.tscn`

### Lane B: ordinary enemy telegraphs and elite resistance

- `scripts/enemies/enemy_base.gd`
- `scripts/enemies/enemy_chaser.gd`
- `scripts/enemies/enemy_shooter.gd`
- `scripts/enemies/enemy_tank.gd`
- `scripts/enemies/enemy_projectile.gd`
- `scripts/enemies/boss_time_crack.gd`
- `tests/combat/enemy_attack_timing_test.gd`
- `tests/combat/enemy_attack_timing_test.tscn`
- `tests/time/time_stop_resistance_test.gd`
- `tests/time/time_stop_resistance_test.tscn`

### Lane C: player action runtime and rewind safety

- `scripts/player/player_action_state.gd`
- `scripts/player/player_controller.gd`
- `scripts/combat/sword_weapon.gd`
- `scripts/combat/hitbox.gd`
- `scripts/time_system/time_manager.gd`
- `scripts/application/legacy_run_adapter.gd`
- `tests/player/player_action_state_test.gd`
- `tests/player/player_action_runtime_test.gd`
- `tests/player/player_action_runtime_test.tscn`
- `tests/time/rewind_transaction_test.gd`
- `tests/integration/application/legacy_run_adapter_test.gd`

### Lane D: real ViewState and CombatHudV2

- `scripts/application/run_view_state_projector.gd`
- `scripts/application/legacy_run_adapter.gd`
- `scripts/player/player_controller.gd`
- `scripts/enemies/boss_chrono_warden.gd`
- `scripts/ui/views/combat_hud_view.gd`
- `scenes/ui/combat_hud_v2.tscn`
- `tests/unit/application/run_view_state_projector_test.gd`
- `tests/unit/application/run_view_state_projector_test.tscn`
- `tests/ui/combat_hud_v2_scene_test.gd`
- `tests/integration/application/legacy_run_adapter_test.gd`

### Lane E: pixel canvas integration

- `project.godot` display-settings hunk only
- `scenes/main.tscn`
- `scenes/rooms/combat_room_01.tscn`
- `tests/contract/presentation/pixel_canvas_test.gd`
- `tests/contract/presentation/pixel_canvas_test.tscn`
- `tests/smoke/m1_runtime_smoke_test.gd`

---

### Task 1: Make player action phase completion observable

**Files:**

- Modify: `scripts/player/player_action_state.gd`
- Modify: `tests/player/player_action_state_test.gd`

**Interfaces:**

- Produces: `is_state_complete() -> bool`, `force_safe_reset() -> bool`, `clear_buffered_inputs() -> void`.
- Preserves: current transition priorities, buffer durations, and DEAD terminal behavior.

- [ ] **Step 1: Write failing completion and reset tests**

Add assertions that a completed `ATTACK_WINDUP` remains identifiable until its owner transitions it, that `ATTACK_ACTIVE` behaves the same way, and that `force_safe_reset()` clears recovery/cancel/buffer state but returns `false` for DEAD.

```gdscript
var action_state = PlayerActionStateScript.new()
action_state.transition_to(PlayerActionStateScript.State.ATTACK_WINDUP, 2)
action_state.advance_frame()
action_state.advance_frame()
_suite.assert_true(action_state.is_state_complete(), "windup completion remains observable")
_suite.assert_equal(action_state.current_state, PlayerActionStateScript.State.ATTACK_WINDUP, "windup does not auto-return to free")
_suite.assert_true(action_state.transition_to(PlayerActionStateScript.State.ATTACK_ACTIVE, 1), "owner advances completed windup")
```

- [ ] **Step 2: Run the test and confirm red**

```bash
godot --headless --path . --scene res://tests/player/player_action_state_test.tscn --log-file /tmp/planewalker_wave3b_action_state_red.log
```

Expected: parse or assertion failure because the completion/reset APIs do not exist.

- [ ] **Step 3: Implement owner-driven completion**

`advance_frame()` must stop the frame counter at the configured duration for `ATTACK_WINDUP` and `ATTACK_ACTIVE`; timed terminal-to-free behavior remains for DASH, TIME_CAST, HITSTUN, and ATTACK_RECOVERY.

```gdscript
func is_state_complete() -> bool:
	return current_state not in [State.FREE, State.DEAD] and _state_frame >= _state_duration_frames

func clear_buffered_inputs() -> void:
	_buffers.clear()

func force_safe_reset() -> bool:
	if current_state == State.DEAD:
		return false
	_buffers.clear()
	_return_to_free()
	return true
```

- [ ] **Step 4: Run focused and legacy tests**

```bash
godot --headless --path . --scene res://tests/player/player_action_state_test.tscn --log-file /tmp/planewalker_wave3b_action_state_green.log
godot --headless --path . --scene res://tests/time/rewind_transaction_test.tscn --log-file /tmp/planewalker_wave3b_rewind_baseline.log
```

- [ ] **Step 5: Commit**

```bash
git add scripts/player/player_action_state.gd tests/player/player_action_state_test.gd
git commit -m "feat: expose player action phase completion"
```

---

### Task 2: Give the Chrono Warden one exclusive action state

**Files:**

- Modify: `scripts/enemies/boss_chrono_warden.gd`
- Create: `tests/combat/boss_action_state_test.gd`
- Create: `tests/combat/boss_action_state_test.tscn`

**Interfaces:**

- Produces: `BossAction`, `BossActionPhase`, `get_boss_ui_snapshot() -> Dictionary`.
- Guarantees: at most one Boss action, no invented slam after time stop, at least 0.8 seconds of extra recovery opportunity from resisted time stop.

- [ ] **Step 1: Write failing Boss invariants**

Test idle time stop, slam-windup time stop, slam-recovery time stop, and mutual exclusion. The idle test must wait longer than the resisted delay and assert that no slam resolves.

```gdscript
boss.apply_time_stop(0.2)
await get_tree().create_timer(0.25).timeout
suite.assert_equal(boss.get_boss_ui_snapshot()["action"], "NONE", "idle time stop invents no action")
suite.assert_equal(slam_count, 0, "idle time stop resolves no slam")
```

- [ ] **Step 2: Run the test and confirm red**

```bash
godot --headless --path . --scene res://tests/combat/boss_action_state_test.tscn --log-file /tmp/planewalker_wave3b_boss_red.log
```

- [ ] **Step 3: Replace parallel slam timers with one action phase**

Use one action enum, one phase enum, one phase timer, and one pending recovery bonus. `_special_index` advances only when `_try_start_action()` succeeds.

```gdscript
enum BossAction { NONE, MELEE, SLAM, RADIAL, AIMED, SUMMON, TIME_CRACK }
enum BossActionPhase { IDLE, WINDUP, RECOVERY }

func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	var delay := minf(duration * 0.35, 1.1)
	match _action_phase:
		BossActionPhase.WINDUP:
			_action_time_remaining += delay
			_pending_recovery_bonus = maxf(_pending_recovery_bonus, 0.8)
		BossActionPhase.RECOVERY:
			_action_time_remaining += maxf(delay, 0.8)
		_:
			_pattern_timer += delay
			_pending_recovery_bonus = maxf(_pending_recovery_bonus, 0.8)
	_add_exposure_source(&"time_stop")
	get_tree().create_timer(duration).timeout.connect(_remove_exposure_source.bind(&"time_stop"))
```

- [ ] **Step 4: Run Boss, legacy smoke, and M1 smoke**

```bash
godot --headless --path . --scene res://tests/combat/boss_action_state_test.tscn --log-file /tmp/planewalker_wave3b_boss_green.log
godot --headless --path . --scene res://tests/reward_system_smoke.tscn --log-file /tmp/planewalker_wave3b_boss_legacy.log
godot --headless --path . --scene res://tests/smoke/m1_runtime_smoke_test.tscn --log-file /tmp/planewalker_wave3b_boss_m1.log
```

- [ ] **Step 5: Commit**

```bash
git add scripts/enemies/boss_chrono_warden.gd tests/combat/boss_action_state_test.gd tests/combat/boss_action_state_test.tscn
git commit -m "feat: serialize Chrono Warden actions"
```

---

### Task 3: Add ordinary-enemy telegraphs and elite time-stop resistance

**Files:**

- Modify: `scripts/enemies/enemy_base.gd`
- Modify: `scripts/enemies/enemy_chaser.gd`
- Modify: `scripts/enemies/enemy_shooter.gd`
- Modify: `scripts/enemies/enemy_tank.gd`
- Modify: `scripts/enemies/enemy_projectile.gd`
- Modify: `scripts/enemies/boss_time_crack.gd`
- Create: `tests/combat/enemy_attack_timing_test.gd`
- Create: `tests/combat/enemy_attack_timing_test.tscn`
- Create: `tests/time/time_stop_resistance_test.gd`
- Create: `tests/time/time_stop_resistance_test.tscn`

**Interfaces:**

- Produces: `AttackPhase`, `attack_phase_changed`, `is_attack_locked()`, token-safe time stop.
- Initial timings: Chaser 0.30s windup/0.30s recovery; Tank 0.75s/0.80s; Shooter 0.60s/0.45s; elite time-stop multiplier 0.5.

- [ ] **Step 1: Write failing timing and token tests**

Assert zero damage/projectiles before windup ends, one resolve at the boundary, no movement during recovery, elite recovery before normal recovery, and no early release when time-stop durations overlap.

- [ ] **Step 2: Run both tests and confirm red**

```bash
godot --headless --path . --scene res://tests/combat/enemy_attack_timing_test.tscn --log-file /tmp/planewalker_wave3b_enemy_red.log
godot --headless --path . --scene res://tests/time/time_stop_resistance_test.tscn --log-file /tmp/planewalker_wave3b_resistance_red.log
```

- [ ] **Step 3: Implement the narrow attack phase in EnemyBase**

```gdscript
enum AttackPhase { READY, WINDUP, RECOVERY }
signal attack_phase_changed(phase: AttackPhase)

func _try_begin_primary_attack() -> bool:
	if _attack_phase != AttackPhase.READY or _attack_cooldown_remaining > 0.0:
		return false
	_attack_phase = AttackPhase.WINDUP
	_attack_phase_remaining = attack_windup
	_committed_attack_direction = global_position.direction_to(target.global_position)
	attack_phase_changed.emit(_attack_phase)
	return true
```

Use a monotonically increasing token dictionary for enemies, projectiles, and Boss cracks. Only the final token expiration clears `_time_stopped`.

- [ ] **Step 4: Run focused, projectile, legacy, and M1 tests**

```bash
godot --headless --path . --scene res://tests/combat/enemy_attack_timing_test.tscn --log-file /tmp/planewalker_wave3b_enemy_green.log
godot --headless --path . --scene res://tests/time/time_stop_resistance_test.tscn --log-file /tmp/planewalker_wave3b_resistance_green.log
godot --headless --path . --scene res://tests/combat/enemy_projectile_test.tscn --log-file /tmp/planewalker_wave3b_projectile.log
godot --headless --path . --scene res://tests/reward_system_smoke.tscn --log-file /tmp/planewalker_wave3b_enemy_legacy.log
godot --headless --path . --scene res://tests/smoke/m1_runtime_smoke_test.tscn --log-file /tmp/planewalker_wave3b_enemy_m1.log
```

- [ ] **Step 5: Commit**

```bash
git add scripts/enemies/enemy_base.gd scripts/enemies/enemy_chaser.gd scripts/enemies/enemy_shooter.gd scripts/enemies/enemy_tank.gd scripts/enemies/enemy_projectile.gd scripts/enemies/boss_time_crack.gd tests/combat/enemy_attack_timing_test.gd tests/combat/enemy_attack_timing_test.tscn tests/time/time_stop_resistance_test.gd tests/time/time_stop_resistance_test.tscn
git commit -m "feat: add readable enemy attack commitments"
```

---

### Task 4: Make PlayerController the single action clock

**Files:**

- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/combat/sword_weapon.gd`
- Modify: `scripts/combat/hitbox.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Create: `tests/player/player_action_runtime_test.gd`
- Create: `tests/player/player_action_runtime_test.tscn`

**Interfaces:**

- Consumes: Task 1 completion/reset API.
- Produces: `get_player_ui_snapshot()`, `cancel_transient_actions()`, `get_rewind_safe_action_state()`, `restore_rewind_safe_action_state(state)`.

- [ ] **Step 1: Write a failing real-player action test**

Cover light combo timings, heavy timing, hitbox-only-active, active-stage Dash buffering, recovery cancel, movement multipliers, HITSTUN, DEAD, and M1 rejection of Bow/Rift/Accelerate inputs without deleting those systems.

- [ ] **Step 2: Run the test and confirm red**

```bash
godot --headless --path . --scene res://tests/player/player_action_runtime_test.tscn --log-file /tmp/planewalker_wave3b_player_runtime_red.log
```

- [ ] **Step 3: Convert SwordWeapon and Hitbox to synchronous endpoints**

`SwordWeapon` exposes immutable attack definitions and synchronous phase hooks. `Hitbox.cancel()` invalidates any compatibility timer token.

```gdscript
func attack_definition(heavy: bool) -> Dictionary:
	return {
		"windup_frames": _seconds_to_frames(0.35 if heavy else _combo_windup()),
		"active_frames": _seconds_to_frames(0.12 if heavy else _combo_active()),
		"recovery_frames": _seconds_to_frames(0.45 if heavy else _combo_recovery()),
		"recovery_cancel_frame": _seconds_to_frames(0.24 if heavy else 0.10),
		"movement_multiplier": 0.2 if heavy else 0.55,
	}
```

- [ ] **Step 4: Route all M1 actions through PlayerActionState**

PlayerController advances the action model exactly once per `_physics_process()`, stores action context separately, and starts Time Stop/Rewind only after a successful `TIME_CAST` commitment. `TimeManager.try_time_stop()` returns `bool` like the other skill methods.

- [ ] **Step 5: Run player, rewind baseline, and smoke tests**

```bash
godot --headless --path . --scene res://tests/player/player_action_runtime_test.tscn --log-file /tmp/planewalker_wave3b_player_runtime_green.log
godot --headless --path . --scene res://tests/player/player_action_state_test.tscn --log-file /tmp/planewalker_wave3b_player_state_regression.log
godot --headless --path . --scene res://tests/time/rewind_transaction_test.tscn --log-file /tmp/planewalker_wave3b_player_rewind_baseline.log
godot --headless --path . --scene res://tests/reward_system_smoke.tscn --log-file /tmp/planewalker_wave3b_player_legacy.log
```

- [ ] **Step 6: Commit**

```bash
git add scripts/player/player_controller.gd scripts/combat/sword_weapon.gd scripts/combat/hitbox.gd scripts/time_system/time_manager.gd tests/player/player_action_runtime_test.gd tests/player/player_action_runtime_test.tscn
git commit -m "feat: drive player actions from one frame clock"
```

---

### Task 5: Cancel old-timeline actions on rewind and selection

**Files:**

- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/application/legacy_run_adapter.gd`
- Modify: `tests/time/rewind_transaction_test.gd`
- Modify: `tests/integration/application/legacy_run_adapter_test.gd`

**Interfaces:**

- Consumes: `cancel_transient_actions()` and rewind hooks from Task 4.
- Guarantees: rewind/selection closes Hitbox, Dash, Bow charge, action buffers, and pending sword phases; DEAD cannot be rewound into a half-alive state.

- [ ] **Step 1: Write failing mid-action rewind and selection tests**

Test rewind during WINDUP, ACTIVE, DASH, and Bow charge; wait beyond the abandoned attack duration and assert no ghost hit or attack signal. Test selection safety calling the cancellation hook exactly once per entry.

- [ ] **Step 2: Run and confirm red**

```bash
godot --headless --path . --scene res://tests/time/rewind_transaction_test.tscn --log-file /tmp/planewalker_wave3b_rewind_actions_red.log
godot --headless --path . --scene res://tests/integration/application/legacy_run_adapter_test.tscn --log-file /tmp/planewalker_wave3b_selection_cancel_red.log
```

- [ ] **Step 3: Implement idempotent cancellation**

```gdscript
func cancel_transient_actions() -> void:
	_action_generation += 1
	action_state.force_safe_reset()
	_dash_frames_remaining = 0
	_dash_velocity = Vector2.ZERO
	sword_weapon.cancel_attack()
	bow_weapon.cancel_charge()
```

LegacyRunAdapter calls it before setting Player processing to DISABLED, guarded by `has_method()` for fixture and legacy compatibility.

- [ ] **Step 4: Run rewind, adapter, M1, and legacy tests**

```bash
godot --headless --path . --scene res://tests/time/rewind_transaction_test.tscn --log-file /tmp/planewalker_wave3b_rewind_actions_green.log
godot --headless --path . --scene res://tests/integration/application/legacy_run_adapter_test.tscn --log-file /tmp/planewalker_wave3b_selection_cancel_green.log
godot --headless --path . --scene res://tests/smoke/m1_runtime_smoke_test.tscn --log-file /tmp/planewalker_wave3b_selection_m1.log
```

- [ ] **Step 5: Commit**

```bash
git add scripts/player/player_controller.gd scripts/application/legacy_run_adapter.gd tests/time/rewind_transaction_test.gd tests/integration/application/legacy_run_adapter_test.gd
git commit -m "fix: cancel abandoned combat actions safely"
```

---

### Task 6: Project real runtime data into RunViewState

**Files:**

- Create: `scripts/application/run_view_state_projector.gd`
- Create: `tests/unit/application/run_view_state_projector_test.gd`
- Create: `tests/unit/application/run_view_state_projector_test.tscn`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/enemies/boss_chrono_warden.gd`

**Interfaces:**

- Consumes: facade snapshot, room definition, `get_player_ui_snapshot()`, optional `get_boss_ui_snapshot()`, and `GameState.run_timer` supplied by the adapter.
- Produces: `project(authoritative, room, player, boss, run_time_ms, ui_context) -> CommandResult` with `context["view_state"]`.

- [ ] **Step 1: Write failing projector tests**

Assert exact phase-name mapping, room/build mapping, boss optionality, selection/pause/terminal flags, deep copies, and independent monotonic view revisions when HP changes under the same authoritative revision.

- [ ] **Step 2: Run and confirm red**

```bash
godot --headless --path . --scene res://tests/unit/application/run_view_state_projector_test.tscn --log-file /tmp/planewalker_wave3b_projector_red.log
```

- [ ] **Step 3: Implement the pure projector**

```gdscript
func project(authoritative: Dictionary, room: Dictionary, player: Dictionary, boss: Variant, run_time_ms: int, ui_context: Dictionary):
	_view_revision += 1
	var view_state := {
		"schema_version": 1,
		"run_id": str(authoritative["run_id"]),
		"revision": _view_revision,
		"phase": _phase_name(int(authoritative["phase"])),
		"suspended": bool(authoritative["suspended"]),
		"run_time_ms": maxi(0, run_time_ms),
		"room": _room_view(authoritative, room),
		"player": player.duplicate(true),
		"build": _build_view(authoritative["build"]),
		"boss": boss.duplicate(true) if boss is Dictionary else null,
		"selection": ui_context.get("selection"),
		"result": authoritative.get("result"),
		"ui_flags": _ui_flags(authoritative, ui_context),
	}
	return CommandResultScript.success(_view_revision, {"view_state": view_state})
```

The projector defines the complete mapping locally so it does not add presentation helpers to the domain enum:

```gdscript
func _phase_name(phase: int) -> String:
	match phase:
		RunPhaseScript.Value.BOOT: return "BOOT"
		RunPhaseScript.Value.HUB: return "HUB"
		RunPhaseScript.Value.RUN_PREPARING: return "RUN_PREPARING"
		RunPhaseScript.Value.ROOM_ENTERING: return "ROOM_ENTERING"
		RunPhaseScript.Value.COMBAT_ACTIVE: return "COMBAT_ACTIVE"
		RunPhaseScript.Value.ROOM_RESOLVING: return "ROOM_RESOLVING"
		RunPhaseScript.Value.SELECTION_ACTIVE: return "SELECTION_ACTIVE"
		RunPhaseScript.Value.ROOM_TRANSITION: return "ROOM_TRANSITION"
		RunPhaseScript.Value.BOSS_ACTIVE: return "BOSS_ACTIVE"
		RunPhaseScript.Value.VICTORY: return "VICTORY"
		RunPhaseScript.Value.DEFEAT: return "DEFEAT"
		_: return "BOOT"
```

- [ ] **Step 4: Run contract and projector tests**

```bash
godot --headless --path . --scene res://tests/unit/application/run_view_state_projector_test.tscn --log-file /tmp/planewalker_wave3b_projector_green.log
godot --headless --path . --scene res://tests/ui/run_view_state_contract_test.tscn --log-file /tmp/planewalker_wave3b_view_contract.log
```

- [ ] **Step 5: Commit**

```bash
git add scripts/application/run_view_state_projector.gd scripts/player/player_controller.gd scripts/enemies/boss_chrono_warden.gd tests/unit/application/run_view_state_projector_test.gd tests/unit/application/run_view_state_projector_test.tscn
git commit -m "feat: project live run view state"
```

---

### Task 7: Mount and localize CombatHudV2 in the real run

**Files:**

- Modify: `scripts/application/legacy_run_adapter.gd`
- Modify: `scripts/ui/views/combat_hud_view.gd`
- Modify: `scenes/ui/combat_hud_v2.tscn`
- Modify: `tests/ui/combat_hud_v2_scene_test.gd`
- Modify: `tests/integration/application/legacy_run_adapter_test.gd`

**Interfaces:**

- Consumes: Task 6 projector and read-only UI snapshots.
- Produces: one HudLayer below ChoiceLayer, 10 Hz live render, safe fallback to legacy CombatHUD when V2 boot/projection fails.

- [ ] **Step 1: Write failing runtime-HUD and localization tests**

Assert HudV2 exists only after successful V2 boot, legacy HUD is disabled only then, same authoritative revision can produce newer HP/energy/cooldown/time views, locale switching re-renders cached state, and all controls fit a 640×360 safe area.

- [ ] **Step 2: Run and confirm red**

```bash
godot --headless --path . --scene res://tests/ui/combat_hud_v2_scene_test.tscn --resolution 640x360 --log-file /tmp/planewalker_wave3b_hud_red.log
godot --headless --path . --scene res://tests/integration/application/legacy_run_adapter_test.tscn --log-file /tmp/planewalker_wave3b_hud_adapter_red.log
```

- [ ] **Step 3: Create HudLayer and render projected state**

Adapter creates `HudLayer` at layer 10 and ChoiceLayer at layer 20. Its always-processing loop accumulates delta and renders every 0.1 seconds. It never mutates authoritative revision.

- [ ] **Step 4: Remove hardcoded display words using existing localization keys**

Use `UI_PAUSED`, `UI_TIME`, `HUD_WEAPON_READY`, `HUD_WEAPON_COOLDOWN_FMT`, `HUD_BUILD_UNFORMED`, `HUD_BUILD_FMT`, `ROOM_TYPE_*`, `BOSS_NAME_CHRONO_WARDEN`, and `ARCHETYPE_*`. Do not edit the protected localization directory in this task.

- [ ] **Step 5: Run HUD, adapter, M1, and ChoicePanel tests**

```bash
godot --headless --path . --scene res://tests/ui/combat_hud_v2_scene_test.tscn --resolution 640x360 --log-file /tmp/planewalker_wave3b_hud_green.log
godot --headless --path . --scene res://tests/integration/application/legacy_run_adapter_test.tscn --log-file /tmp/planewalker_wave3b_hud_adapter_green.log
godot --headless --path . --scene res://tests/smoke/m1_runtime_smoke_test.tscn --log-file /tmp/planewalker_wave3b_hud_m1.log
godot --headless --path . --scene res://tests/ui/choice_panel_v2_scene_test.tscn --resolution 640x360 --log-file /tmp/planewalker_wave3b_choice_640.log
```

- [ ] **Step 6: Commit**

```bash
git add scripts/application/legacy_run_adapter.gd scripts/ui/views/combat_hud_view.gd scenes/ui/combat_hud_v2.tscn tests/ui/combat_hud_v2_scene_test.gd tests/integration/application/legacy_run_adapter_test.gd
git commit -m "feat: connect live CombatHudV2"
```

---

### Task 8: Establish the 640×360 integer-scaled pixel canvas

**Files:**

- Modify selected hunk: `project.godot`
- Modify: `scenes/main.tscn`
- Modify: `scenes/rooms/combat_room_01.tscn`
- Create: `tests/contract/presentation/pixel_canvas_test.gd`
- Create: `tests/contract/presentation/pixel_canvas_test.tscn`
- Modify: `tests/smoke/m1_runtime_smoke_test.gd`

**Interfaces:**

- Produces: 640×360 logical viewport, `canvas_items` stretch, integer scale mode, responsive menu/HUD/Choice layout, centered Camera2D for the existing 1280×720 greybox world.

- [ ] **Step 1: Write a failing presentation contract**

```gdscript
suite.assert_equal(ProjectSettings.get_setting("display/window/size/viewport_width"), 640, "logical width is 640")
suite.assert_equal(ProjectSettings.get_setting("display/window/size/viewport_height"), 360, "logical height is 360")
suite.assert_equal(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items", "2D stretch is enabled")
suite.assert_equal(ProjectSettings.get_setting("display/window/stretch/scale_mode"), "integer", "integer scaling prevents blur")
```

- [ ] **Step 2: Run and confirm red**

```bash
godot --headless --path . --scene res://tests/contract/presentation/pixel_canvas_test.tscn --log-file /tmp/planewalker_wave3b_pixel_red.log
```

- [ ] **Step 3: Apply display settings and responsive layout**

Change only these settings in `project.godot`:

```ini
window/size/viewport_width=640
window/size/viewport_height=360
window/stretch/mode="canvas_items"
window/stretch/scale_mode="integer"
```

Add a centered Camera2D that shows the current 1280×720 greybox at 0.5 zoom. Convert main-menu fixed offsets to anchors/containers; do not rescale gameplay physics or content data in this task.

- [ ] **Step 4: Run 640×360, 1280×720, and 1920×1080 checks**

```bash
godot --headless --path . --scene res://tests/contract/presentation/pixel_canvas_test.tscn --log-file /tmp/planewalker_wave3b_pixel_green.log
godot --headless --path . --scene res://tests/smoke/m1_runtime_smoke_test.tscn --resolution 640x360 --log-file /tmp/planewalker_wave3b_pixel_640.log
godot --headless --path . --scene res://tests/ui/combat_hud_v2_scene_test.tscn --resolution 1280x720 --log-file /tmp/planewalker_wave3b_pixel_720.log
godot --headless --path . --scene res://tests/ui/combat_hud_v2_scene_test.tscn --resolution 1920x1080 --log-file /tmp/planewalker_wave3b_pixel_1080.log
```

- [ ] **Step 5: Stage only owned hunks and commit**

```bash
git add scenes/main.tscn scenes/rooms/combat_room_01.tscn tests/contract/presentation/pixel_canvas_test.gd tests/contract/presentation/pixel_canvas_test.tscn tests/smoke/m1_runtime_smoke_test.gd
git add -p project.godot
git diff --cached --name-only
git commit -m "feat: establish 640x360 pixel canvas"
```

The cached diff must contain only the four display settings from `project.godot`; reject all other hunks.

---

## Final Verification

- [ ] Run editor import:

```bash
godot --headless --editor --path . --quit --log-file /tmp/planewalker_wave3b_import.log
```

- [ ] Run every discovered test scene and require exit code 0:

```bash
for scene in $(rg --files tests -g '*.tscn' | sort); do
	godot --headless --path . --scene "res://$scene" --log-file "/tmp/$(basename "$scene" .tscn)_wave3b_final.log"
done
```

- [ ] Scan all Wave 3B logs:

```bash
rg -n "SCRIPT ERROR|Smoke test failed|expected .* got|ObjectDB instances leaked|resources still in use" /tmp/*wave3b*.log
```

Only the previously known legacy `reward_system_smoke` ObjectDB warning may remain. New Wave 3B scenes must have no leak or resource warning.

- [ ] Update the staged-development spec:

```text
Historical outcome: Wave 3B combat/UI hardening is verified. Wave 4A–4D, formal M1 decision, post-M1 promotion, and the remaining full-product program are governed by `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`.
```
