# Plane Walker P11 Five Complete Weapons Implementation Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: Executable P11 work breakdown under the approved five-weapon design
- Applies To: Shared weapon action authority, Sword, Bow, Gun, Staff, Gauntlets, semantic input, profiles, facts, HUD, presentation, time interactions, Boss integration, simulations, and certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/contracts/content-pack-v2.md`, `docs/superpowers/plans/2026-09-29-plane-walker-p10-candidate-loadouts.md`
- Last Verified: 2026-09-30
- Implementation Status: P11A and P11B are locally certified; P11C Bow Candidate is certified through `0cf27da`; Launch Bow L2 is locally certified through `372455d`; P11D Launch Gun is locally certified through `e92e7f4`; P11E Launch Staff is locally certified through `f1f022d`; P11F Launch Gauntlets is locally certified through `2cfd31c`; P11G and later gates remain active
- Exit Gate: Five coordinator-owned weapons, M1/Bow parity, 30 loadout combinations, deterministic simulations, full repository validation, and honest local evidence all pass

> **For agentic workers:** REQUIRED SUB-SKILL: Use test-first implementation, one integration owner for shared files, focused commits, and a two-stage correctness/regression review for each task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver five complete weapons through one deterministic action authority without changing the certified M1 Sword profile or falsely upgrading the external M1 evidence state.

**Architecture:** `WeaponIntentRouter` emits semantic edges, `WeaponActionCoordinator` owns the single action clock and atomic transaction, and one active `WeaponRuntime` interprets a validated `WeaponRuntimeProfile`. Typed facts and immutable ViewState feed feedback, replay, and UI; weapon-specific runtimes own only distinctive resources and mechanics.

**Tech Stack:** Godot 4.6, typed GDScript, Content Pack v2 JSON, JSON Schema, CSV localization, scene-based tests, Python documentation governance, deterministic run seeds, and local Git commits.

## Global Constraints

- Formal status remains `M1 Candidate — External Validation Pending`; authentic human playtests remain `0 / 20`.
- `sword_m1_v1` covers `M1` and `CURRENT` and preserves the certified timing, damage, movement, facts, feedback timing, and reward hooks.
- `bow_candidate_v1` remains `NEXT`; Gun, Staff, and Gauntlets remain unavailable before `LAUNCH`.
- Runtime actions use `weapon_primary`, `weapon_secondary`, `weapon_utility`, `weapon_skill`, and `weapon_ultimate`; time abilities use `time_slot_1` and `time_slot_2`.
- One save/input schema version accepts legacy action IDs and migrates persisted remaps without losing keyboard, mouse, or controller bindings.
- `WeaponActionCoordinator` is the only weapon action clock and the only publisher of `weapon_action_committed`.
- Rejected actions change no resource, phase, cooldown, payload, fact, feedback cue, or replay state.
- Random spread, critical results, chains, zones, and ultimate outcomes use stable run-seed channels.
- Shared files have one integration owner at a time; weapon-specific files may proceed in parallel only after P11A contracts pass.
- The interrupted Staff `weapon_spell` draft is migration material only; it is never committed in its current schema.
- Every focused Godot run must be scanned for parser errors, runtime errors, leaks, and unexpected ObjectDB warnings.
- GDScript line coverage remains `not collected (godot_line_coverage_unsupported)` until a real provider exists.

---

### Task 1: P11A runtime-profile content authority

**Files:**
- Create: `data/schemas/weapon_runtime_profile_v1.schema.json`
- Create: `data/content_packs/base/content/weapon_runtime_profiles.json`
- Create: `scripts/combat/weapons/weapon_runtime_profile.gd`
- Modify: `data/content_packs/base/content/weapons.json`
- Modify: `data/content_packs/base/pack.json`
- Modify: `scripts/content/content_registry.gd`
- Modify: `scripts/application/run_loadout_policy.gd`
- Modify: `data/schemas/content_entry_v2.schema.json`
- Replace: `tests/contract/content_schema/staff_spell_catalog_contract_test.gd`
- Modify: `tests/contract/content_schema/content_registry_test.gd`
- Modify: `tests/contract/content_schema/loadout_catalog_contract_test.gd`

**Interfaces:**
- Consumes: `ContentRegistry.load_packs(pack_roots, game_version)` and normalized run milestone/weapon IDs.
- Produces: `WeaponRuntimeProfile.from_definition(definition) -> WeaponRuntimeProfile`, `ContentRegistry.get_weapon_runtime_profile(profile_id) -> Dictionary`, and accepted run config field `weapon_profile_id`.

- [x] **Step 1: Write failing profile and loadout contracts**

```gdscript
func test_m1_sword_resolves_exact_profile() -> void:
	var accepted := policy.validate({"milestone": "M1", "character_id": "wanderer", "weapon_id": "sword", "time_ability_ids": ["stop", "rewind"]}, registry)
	assert_true(accepted.ok)
	assert_eq(accepted.config.weapon_profile_id, "sword_m1_v1")

func test_launch_staff_profile_is_not_available_in_m1() -> void:
	var rejected := policy.validate({"milestone": "M1", "character_id": "wanderer", "weapon_id": "staff", "time_ability_ids": ["stop", "rewind"]}, registry)
	assert_false(rejected.ok)
```

- [x] **Step 2: Run contracts and confirm missing profile authority fails**

Run: `./tools/run_tests.sh --filter "content_registry|loadout_catalog|staff_spell_catalog"`

Expected: FAIL because `weapon_runtime_profiles.json`, profile lookup, or `weapon_profile_id` does not exist.

- [x] **Step 3: Implement the exact profile boundary**

```gdscript
class_name WeaponRuntimeProfile
extends RefCounted

var profile_id: StringName
var profile_version: int
var weapon_id: StringName
var availability: PackedStringArray
var actions: Dictionary
var resources: Dictionary
var capabilities: PackedStringArray

static func from_definition(definition: Dictionary) -> WeaponRuntimeProfile:
	var profile := WeaponRuntimeProfile.new()
	profile.profile_id = StringName(str(definition["id"]))
	profile.profile_version = int(definition["profile_version"])
	profile.weapon_id = StringName(str(definition["weapon_id"]))
	profile.availability = PackedStringArray(definition["availability"])
	profile.actions = definition["actions"].duplicate(true)
	profile.resources = definition.get("resources", {}).duplicate(true)
	profile.capabilities = PackedStringArray(definition.get("capabilities", []))
	return profile
```

The Registry rejects missing/duplicate IDs, unsupported semantic actions, non-positive frame windows, cancel frames beyond recovery, invalid resource bounds, unknown payload/cue IDs, weapon/profile mismatches, and availability widening.

- [x] **Step 4: Absorb the interrupted Staff data draft**

Remove the draft `weapon_spell` category from `content_entry_v2.schema.json` and `ContentRegistry.VALID_CATEGORIES`. Move reusable Staff action numbers into `staff_launch_v1`; retain bilingual spell text for P11E. Register the profile manifest and exact SHA-256 values in `pack.json`.

- [x] **Step 5: Run focused and pack-integrity tests**

Run: `./tools/run_tests.sh --filter "content_registry|content_pack_resolver|loadout_catalog|weapon_runtime_profile"`

Expected: PASS with the Base Pack active, exact manifest hashes, and fail-closed invalid fixtures.

- [x] **Step 6: Commit**

```bash
git add -- data/schemas/weapon_runtime_profile_v1.schema.json data/content_packs/base/content/weapon_runtime_profiles.json data/content_packs/base/content/weapons.json data/content_packs/base/pack.json scripts/content/content_registry.gd scripts/application/run_loadout_policy.gd data/schemas/content_entry_v2.schema.json scripts/combat/weapons/weapon_runtime_profile.gd tests/contract/content_schema
git commit -m "feat(content): add weapon runtime profiles"
```

### Task 2: P11A action contract and coordinator

**Files:**
- Create: `scripts/combat/weapons/weapon_action_contract.gd`
- Create: `scripts/combat/weapons/weapon_runtime.gd`
- Create: `scripts/combat/weapons/weapon_action_coordinator.gd`
- Create: `tests/combat/weapon_action_coordinator_test.gd`
- Create: `tests/combat/weapon_action_coordinator_test.tscn`

**Interfaces:**
- Consumes: one configured `WeaponRuntime`, immutable profile, intent dictionaries, and generation-safe frame ticks.
- Produces: `submit_intent(intent, context) -> Dictionary`, `advance_frame()`, `cancel(reason)`, `snapshot()`, `restore_safe(snapshot)`, and `presentation_snapshot()`.

- [x] **Step 1: Write failing transaction tests**

```gdscript
func test_rejected_plan_is_atomic() -> void:
	var before := coordinator.snapshot()
	assert_false(coordinator.submit_intent({"id": "weapon_secondary", "edge": "pressed"}, {}).ok)
	assert_eq(coordinator.snapshot(), before)
	assert_eq(committed_facts.size(), 0)

func test_windup_active_recovery_and_cancel_boundary() -> void:
	assert_true(coordinator.submit_intent(PRIMARY_PRESS, {}).ok)
	advance(5)
	assert_eq(coordinator.phase_name(), "WINDUP")
	advance(1)
	assert_eq(coordinator.phase_name(), "ACTIVE")
```

- [x] **Step 2: Run the coordinator scene and confirm RED**

Run: `./tools/run_tests.sh --filter weapon_action_coordinator`

Expected: FAIL because the coordinator classes are missing.

- [x] **Step 3: Implement the narrow runtime contract**

```gdscript
class_name WeaponRuntime
extends RefCounted

func configure(owner: Node, profile: WeaponRuntimeProfile, modifiers: WeaponModifierState) -> bool: return false
func plan_intent(_intent: Dictionary, _context: Dictionary) -> Dictionary: return {"ok": false, "code": "unsupported"}
func commit_action(_plan: Dictionary, _token: int) -> Dictionary: return {"ok": false, "code": "unsupported"}
func on_phase_enter(_plan: Dictionary, _phase: StringName, _token: int) -> Array[Dictionary]: return []
func cancel_action(_token: int, _reason: StringName) -> void: pass
func finish_action(_token: int) -> void: pass
func reset_runtime_state(_reason: StringName) -> void: pass
func snapshot() -> Dictionary: return {}
func restore_snapshot(_snapshot: Dictionary) -> bool: return false
func presentation_snapshot() -> Dictionary: return {}
```

`WeaponActionContract` validates finite numeric fields, immutable action tokens, hold/release edges, payload descriptors, phase timings, and half-open cancel windows. The coordinator deep-copies every committed plan and publishes no fact from a rejected plan.

- [x] **Step 4: Verify phase, buffer, cancel, stale-generation, snapshot, and exactly-once tests**

Run: `./tools/run_tests.sh --filter "weapon_action_coordinator|player_action_state"`

Expected: PASS; legacy state tests remain green while the new coordinator is still additive.

- [x] **Step 5: Commit**

```bash
git add -- scripts/combat/weapons/weapon_action_contract.gd scripts/combat/weapons/weapon_runtime.gd scripts/combat/weapons/weapon_action_coordinator.gd tests/combat/weapon_action_coordinator_test.gd tests/combat/weapon_action_coordinator_test.tscn
git commit -m "feat(combat): add weapon action coordinator"
```

### Task 3: P11A semantic input, modifiers, and typed facts

**Files:**
- Create: `scripts/input/weapon_intent_router.gd`
- Create: `scripts/combat/weapons/weapon_modifier_state.gd`
- Modify: `scripts/input/input_action_contract.gd`
- Modify: `project.godot`
- Modify: `autoload/event_bus.gd`
- Create: `tests/contract/input/weapon_intent_router_test.gd`
- Create: `tests/contract/input/weapon_intent_router_test.tscn`
- Create: `tests/combat/weapon_modifier_state_test.gd`
- Create: `tests/combat/weapon_modifier_state_test.tscn`
- Modify: `tests/contract/events/combat_event_publication_test.gd`

**Interfaces:**
- Consumes: persisted input profile, current accessibility mode, raw Godot action edges, and profile capabilities.
- Produces: semantic `{id, edge, held_frames}` intents, frozen modifier snapshots, and typed weapon facts.

- [x] **Step 1: Write failing migration, hold/toggle, and capability tests**

```gdscript
func test_legacy_attack_migrates_to_primary_without_losing_binding() -> void:
	var migrated := router.migrate_profile({"schema_version": 1, "bindings": {"attack": [KEY_J]}})
	assert_eq(migrated.schema_version, 2)
	assert_eq(migrated.bindings.weapon_primary, [KEY_J])

func test_unsupported_modifier_fails_closed() -> void:
	assert_false(modifiers.apply(&"weapon.ammo_capacity", 2.0))
	assert_eq(modifiers.snapshot(), {})
```

- [x] **Step 2: Run focused tests and confirm RED**

Run: `./tools/run_tests.sh --filter "weapon_intent_router|weapon_modifier_state|combat_event_publication|input_action_contract"`

- [x] **Step 3: Implement semantic compatibility and additive facts**

```gdscript
signal weapon_action_committed(weapon_id: StringName, action_id: StringName, token: int, context: Dictionary)
signal weapon_resource_changed(weapon_id: StringName, resource_id: StringName, current: float, maximum: float, reason: StringName)
signal weapon_hit_confirmed(weapon_id: StringName, action_id: StringName, token: int, target_id: int, context: Dictionary)
```

Legacy actions remain accepted only through the router. `WeaponModifierState.freeze_for_action()` returns a deep copy and rejects NaN, infinity, unknown capabilities, and invalid bounds.

- [x] **Step 4: Run input, controller, event, and accessibility regressions**

Run: `./tools/run_tests.sh --filter "input|accessibility|controller|combat_event_publication|weapon_modifier_state"`

Expected: PASS with keyboard/mouse and controller coverage for every required semantic action.

- [x] **Step 5: Commit**

```bash
git add -- scripts/input/weapon_intent_router.gd scripts/input/input_action_contract.gd scripts/combat/weapons/weapon_modifier_state.gd project.godot autoload/event_bus.gd tests/contract/input tests/combat/weapon_modifier_state_test.gd tests/combat/weapon_modifier_state_test.tscn tests/contract/events/combat_event_publication_test.gd
git commit -m "feat(input): add semantic weapon intents"
```

### Task 4: P11B migrate Sword with certified M1 parity

**Files:**
- Create: `scripts/combat/weapons/sword_weapon_runtime.gd`
- Modify: `scripts/combat/sword_weapon.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/player/player_action_state.gd`
- Modify: `scripts/player/player_loadout_runtime.gd`
- Modify: `scenes/player/player.tscn`
- Modify: `scripts/items/item_effect.gd`
- Modify: `autoload/combat_feedback.gd`
- Modify: `scripts/presentation/pixel_proxy_actor.gd`
- Modify: `tests/player/player_action_runtime_test.gd`
- Modify: `tests/reward_system_smoke.gd`
- Modify: `tests/time/rewind_action_cancellation_test.gd`

**Interfaces:**
- Consumes: `sword_m1_v1`, coordinator semantic intents, `Stats.attack`, and frozen modifiers.
- Produces: the exact existing three-light/heavy M1 behavior through the shared coordinator plus Sword presentation state.

- [x] **Step 1: Add parity assertions for exact M1 frame tables and facts**

```gdscript
const M1_EXPECTED := [
	{"id": "light_1", "windup": 6, "active": 5, "recovery": 11, "cancel": 6, "multiplier": 0.8},
	{"id": "light_2", "windup": 8, "active": 5, "recovery": 12, "cancel": 6, "multiplier": 1.0},
	{"id": "light_3", "windup": 10, "active": 6, "recovery": 17, "cancel": 6, "multiplier": 1.3},
	{"id": "heavy", "windup": 21, "active": 8, "recovery": 27, "cancel": 15, "multiplier": 2.0},
]
```

- [x] **Step 2: Run parity tests against the old path and record GREEN baseline**

Run: `./tools/run_tests.sh --filter "player_action_runtime|reward_system_smoke|rewind_action_cancellation|combat_event_publication"`

- [x] **Step 3: Route Sword through the coordinator**

`PlayerController` owns no Sword action fields. It delegates semantic intents, frame advance, movement multiplier, cancel, reset, snapshot, and presentation reads to the coordinator. `SwordWeapon` becomes a payload adapter used by `SwordWeaponRuntime`; it does not publish facts or own an action clock.

- [x] **Step 4: Preserve release-frame feedback timing**

Bind swing animation/audio/VFX to the profile Active cue, not to the earlier transaction fact. Replace Pixel Proxy child-name lookup with `presentation_snapshot().facing`.

- [x] **Step 5: Run focused and M1 repository gates**

Run: `./tools/run_tests.sh --filter "player_action|sword|reward_system_smoke|combat_feedback|rewind_action|m1"`

Expected: all prior M1 values and behaviors pass unchanged.

- [x] **Step 6: Commit**

```bash
git add -- scripts/combat/weapons/sword_weapon_runtime.gd scripts/combat/sword_weapon.gd scripts/player scripts/items/item_effect.gd scenes/player/player.tscn autoload/combat_feedback.gd scripts/presentation/pixel_proxy_actor.gd tests/player tests/time/rewind_action_cancellation_test.gd tests/reward_system_smoke.gd
git commit -m "refactor(combat): migrate sword to weapon coordinator"
```

### Task 5: P11C migrate and complete Bow

**Files:**
- Modify: `data/content_packs/base/content/weapon_runtime_profiles.json`
- Modify: `data/content_packs/base/pack.json`
- Create: `scripts/combat/weapons/bow_weapon_runtime.gd`
- Modify: `scripts/combat/bow_weapon.gd`
- Modify: `scripts/combat/health_component.gd`
- Modify: `scripts/combat/player_arrow.gd`
- Modify: `scripts/combat/weapons/weapon_action_coordinator.gd`
- Modify: `scripts/combat/weapons/weapon_runtime.gd`
- Modify: `scripts/enemies/boss_chrono_warden.gd`
- Modify: `scripts/enemies/enemy_base.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `autoload/combat_feedback.gd`
- Modify: `scripts/presentation/pixel_proxy_actor.gd`
- Modify: `tests/player/ranged_charge_accessibility_test.gd`
- Create: `tests/combat/bow_weapon_runtime_test.gd`
- Create: `tests/combat/bow_weapon_runtime_test.tscn`
- Create: `tests/combat/bow_boss_conversion_test.gd`
- Create: `tests/combat/bow_boss_conversion_test.tscn`
- Create: `tests/combat/bow_launch_execution_test.gd`
- Create: `tests/combat/bow_launch_execution_test.tscn`
- Create: `tests/contract/content_schema/bow_launch_profile_contract_test.gd`
- Create: `tests/contract/content_schema/bow_launch_profile_contract_test.tscn`
- Modify: `tests/contract/content_schema/content_registry_test.gd`
- Create: `tests/player/player_launch_bow_integration_test.gd`
- Create: `tests/player/player_launch_bow_integration_test.tscn`
- Create: `tests/time/bow_time_interaction_context_test.gd`
- Create: `tests/time/bow_time_interaction_context_test.tscn`

**Interfaces:**
- Consumes: `bow_candidate_v1` or `bow_launch_v1`, semantic press/release intents, aim context, modifiers, and time context.
- Produces: deterministic arrows/scatter/rain/trails, charge ViewState, typed facts, and snapshot-safe Bow state.

- [x] **Step 1: Freeze P10 candidate boundaries in failing coordinator tests**

Assert 0.15-second minimum charge, 0.9-second full charge, 0.35-second cooldown, 0.75–1.75 damage interpolation, 440–680 speed, 0.98 full-charge threshold, +1 pierce, six energy restore, hold/toggle equivalence, and atomic undercharge rejection.

- [x] **Step 2: Remove Bow `_process()` authority and implement coordinator-owned charge**

The runtime stores no wall-clock seconds; held frames, cooldown frames, Dash cancel, release, and replay snapshots are coordinator driven.

Candidate certification is recorded in `docs/current/2026-09-29-p11c-bow-candidate-evidence.md`. The checked step covers Candidate charge ownership and legacy-clock retirement only; Launch cooldown/resource execution remains part of Step 3.

- [x] **Step 3: Add launch scatter, skill, ultimate, and four time interactions**

Every projectile and zone carries one action token and target-deduplication context. Seeded spread uses a stable channel containing run seed, token, and pellet/arrow index.

The implemented Launch profile keeps Candidate isolation and adds the four-tier `0–14 / 15–29 / 30–47 / 48+` primary, 48-frame full charge, 228-frame automatic release, Scatter Shot, swept Focus Step, Temporal Arrow, and coordinator-driven Starfall. Stop, Rewind, Accelerate, and Rift resolve through immutable interaction descriptors and live release-time context where required. Chrono Warden control converts to recovery/exposure/poise pressure without interrupting a committed active attack. Complete numeric-authority rejection, death cleanup, Rewind payload identity, Temporal phantom scaling, WINDUP rejection, and failed-release rollback pass their regression tests.

- [x] **Step 4: Run Bow, accessibility, snapshot, feedback, and candidate gates**

Run each literal filter separately:

```bash
./tools/run_tests.sh --filter bow
./tools/run_tests.sh --filter ranged_charge_accessibility
./tools/run_tests.sh --filter combat_feedback_runtime
./tools/run_tests.sh --filter candidate_loadout_panel
./tools/run_tests.sh --filter weapon_action_coordinator
./tools/run_tests.sh --filter rewind_action_cancellation
./tools/run_tests.sh --filter player_loadout_runtime
./tools/run_tests.sh --filter health_component
```

This step verifies deterministic payload planning/execution, coordinator ownership, accessibility, feedback, Candidate isolation, cancellation, lifecycle cleanup, and snapshot safety. Formal replay serialization belongs to Task 9 and is not claimed by the P11C Launch Bow gate.

Final evidence: all eight literal focused filters pass with zero failed scenes and zero new leak warnings; the complete suite and `validate_project.sh` both pass `82 / 82` scenes with only the registered `reward_system_smoke` ObjectDB warning. See `docs/current/2026-09-29-p11c-bow-launch-evidence.md`.

- [x] **Step 5: Commit**

```bash
git add -- \
  data/content_packs/base/content/weapon_runtime_profiles.json \
  data/content_packs/base/pack.json \
  scripts/combat/bow_weapon.gd \
  scripts/combat/health_component.gd \
  scripts/combat/player_arrow.gd \
  scripts/combat/weapons/bow_weapon_runtime.gd \
  scripts/combat/weapons/weapon_action_coordinator.gd \
  scripts/combat/weapons/weapon_runtime.gd \
  scripts/enemies/boss_chrono_warden.gd \
  scripts/enemies/enemy_base.gd \
  scripts/player/player_controller.gd \
  scripts/time_system/time_manager.gd \
  tests/combat/bow_boss_conversion_test.gd \
  tests/combat/bow_boss_conversion_test.tscn \
  tests/combat/bow_launch_execution_test.gd \
  tests/combat/bow_launch_execution_test.tscn \
  tests/combat/bow_weapon_runtime_test.gd \
  tests/contract/content_schema/bow_launch_profile_contract_test.gd \
  tests/contract/content_schema/bow_launch_profile_contract_test.tscn \
  tests/contract/content_schema/content_registry_test.gd \
  tests/player/player_launch_bow_integration_test.gd \
  tests/player/player_launch_bow_integration_test.tscn \
  tests/time/bow_time_interaction_context_test.gd \
  tests/time/bow_time_interaction_context_test.tscn
git commit -m "feat(weapon): complete launch bow runtime"

git add -- \
  docs/current/2026-09-29-p11c-bow-launch-evidence.md \
  docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md \
  docs/README.md
git commit -m "docs(weapon): certify launch bow runtime"
```

The runtime commit is `372455d`; the following documentation commit records its local certification.

### Task 6: P11D implement Gun

**Files:**
- Create: `scripts/combat/weapons/gun_weapon_runtime.gd`
- Create: `scripts/combat/gun_projectile.gd`
- Create: `scenes/combat/gun_projectile.tscn`
- Create: `tests/combat/gun_weapon_runtime_test.gd`
- Create: `tests/combat/gun_weapon_runtime_test.tscn`
- Modify: `scripts/ui/contracts/run_view_state.gd`
- Modify: `scripts/application/run_view_state_projector.gd`
- Modify: `scripts/ui/views/combat_hud_view.gd`
- Modify: `autoload/combat_feedback.gd`

**Interfaces:**
- Consumes: `gun_launch_v1`, aim context, six-round ammo state, time context, and Boss resistance context.
- Produces: normal/aimed/shotgun actions, reload/perfect reload, Time Load, Void Penetration, Gun HUD, facts, feedback, and snapshots.

- [x] **Step 1: Write exact boundary tests**

Cover hold 17/18, ammo 0/1/2/6/7, reload frames 7/8/27/28/35/36/39/40/48, active/free Time Load, ultimate 59/60, projectile construction failure, and multi-pellet deduplication.

- [x] **Step 2: Implement atomic ammunition and reload transactions**

Empty primary starts reload only. Shotgun rejects at one round. Perfect reload fills to seven, grants free Time Load, leaves active cooldown untouched, and enters four recovery frames.

- [x] **Step 3: Implement Gun payloads, time interactions, Boss conversion, HUD, and feedback**

All pellets share the committed action token; target hits deduplicate per pellet and resource/fact effects deduplicate per action where required.

- [x] **Step 4: Run Gun and shared regressions**

Run: `./tools/run_tests.sh --filter "gun|weapon_action_coordinator|run_view_state|combat_feedback|chrono_warden"`

- [x] **Step 5: Commit**

```bash
git add -- scripts/combat/weapons/gun_weapon_runtime.gd scripts/combat/gun_projectile.gd scenes/combat/gun_projectile.tscn tests/combat/gun_weapon_runtime_test.gd tests/combat/gun_weapon_runtime_test.tscn scripts/ui/contracts/run_view_state.gd scripts/application/run_view_state_projector.gd scripts/ui/views/combat_hud_view.gd autoload/combat_feedback.gd
git commit -m "feat(weapon): add complete gun runtime"
```

Execution record: implementation commit `e92e7f4` completed the authoritative Gun Profile, atomic ammunition/reload loop, normal/aimed/shotgun actions, Time Load, Void Penetration, deterministic projectiles, four time interactions, Chrono Warden conversion, HUD, feedback, typed facts, snapshot/reset lifecycle, and M1/NEXT isolation. The focused Gun gate passed `5 / 5`; adjacent Sword/Bow/action regressions passed `18 / 18`; the complete suite and final validation each passed `88 / 88` with only the registered `reward_system_smoke` ObjectDB warning. Evidence is retained in `docs/current/2026-09-29-p11d-gun-launch-evidence.md`.

### Task 7: P11E implement Staff and elemental status runtime

**Files:**
- Create: `scripts/combat/weapons/staff_weapon_runtime.gd`
- Create: `scripts/combat/elemental_status_runtime.gd`
- Create: `scripts/combat/staff_projectile.gd`
- Create: `scripts/combat/staff_spell_zone.gd`
- Create: `scenes/combat/staff_projectile.tscn`
- Create: `scenes/combat/staff_spell_zone.tscn`
- Create: `tests/combat/staff_weapon_runtime_test.gd`
- Create: `tests/combat/staff_weapon_runtime_test.tscn`
- Create: `tests/combat/elemental_status_runtime_test.gd`
- Create: `tests/combat/elemental_status_runtime_test.tscn`
- Modify: `scripts/enemies/enemy_base.gd`
- Modify: `scripts/enemies/boss_chrono_warden.gd`
- Modify: `data/content_packs/base/localization/translations.csv`
- Modify: `data/localization/translations.csv`

**Interfaces:**
- Consumes: `staff_launch_v1`, 100 Mana/3-per-second resource, ordered element state, aim/seed/time/Boss contexts.
- Produces: basic/charged spells, six ordered combinations, source-aware statuses/zones, collapse/ultimate, Staff HUD, facts, feedback, and snapshots.

- [x] **Step 1: Write Mana, sequence, status, and deterministic payload tests**

Cover 30-frame charge, Fire 20, Ice 25, Lightning 18, atomic combination reservation/refund, 300-frame window, same-element rejection, six ordered pairs, bounded two-percent Mana return, deterministic chain order, overlapping sources, cleanup, and Boss freeze/blind conversions.

- [x] **Step 2: Implement source-aware status ownership**

Each status is keyed by `(effect_id, source_id, generation)`. Removing one source cannot clear another; death, room disposal, phase transition, and run reset remove all owned sources.

- [x] **Step 3: Implement Staff runtime and payloads through the coordinator**

No Staff `_process()` owns an action clock. Mana regeneration is a deterministic resource tick, and every random ultimate outcome comes from a stable seeded channel.

- [x] **Step 4: Complete Staff HUD, feedback, localization, time, and Boss contracts**

Update both localization catalogs identically for shared keys and refresh the Base Pack localization hash only after final text is stable.

- [x] **Step 5: Run Staff, content, enemy, Boss, localization, and replay gates**

Run: `./tools/run_tests.sh --filter "staff|elemental_status|content_registry|localization|chrono_warden|replay"`

Execution record: the final Staff gate passed `7 / 7` at `planewalker-tests.6ks5Ap` with zero leak warnings. The final repository gate passed at `planewalker-validation.1Wdg8l`, including `97 / 97` Godot scenes, documentation `30 / 30` with zero violations, localization `8 / 8`, playtest data `13 / 13`, M1 release gate `27 / 27`, coverage contracts `5 / 5`, export contracts `37 / 37` in contract mode, and clean bootstrap/import checks. The only registered suite warning is `reward_system_smoke`; final static and independent reviews found no P0, P1, or P2 blocker. Replay serialization remains P11G scope and is not claimed by the P11E evidence.

- [x] **Step 6: Commit**

```bash
git add -- scripts/combat/weapons/staff_weapon_runtime.gd scripts/combat/elemental_status_runtime.gd scripts/combat/staff_projectile.gd scripts/combat/staff_spell_zone.gd scenes/combat/staff_projectile.tscn scenes/combat/staff_spell_zone.tscn tests/combat/staff_weapon_runtime_test.gd tests/combat/staff_weapon_runtime_test.tscn tests/combat/elemental_status_runtime_test.gd tests/combat/elemental_status_runtime_test.tscn scripts/enemies data/content_packs/base/localization/translations.csv data/localization/translations.csv data/content_packs/base/pack.json
git commit -m "feat(weapon): add complete staff runtime"
```

Implementation commit `f1f022d` completed the authoritative Staff Profile, Mana and element sequencing, six ordered combinations, real projectile/zone/status execution, four time interactions, Chrono Warden conversion, Player/HUD/feedback integration, snapshot/reset cleanup, bounded ledgers, and Launch/Expansion isolation. Evidence is retained in `docs/current/2026-09-29-p11e-staff-launch-evidence.md`.

### Task 8: P11F implement Gauntlets and Boss poise mapping

**Files:**
- Create: `scripts/combat/weapons/gauntlets_weapon_runtime.gd`
- Create: `scripts/combat/weapons/gauntlets_combo_state.gd`
- Create: `tests/combat/gauntlets_weapon_runtime_test.gd`
- Create: `tests/combat/gauntlets_weapon_runtime_test.tscn`
- Create: `tests/combat/gauntlets_combo_state_test.gd`
- Create: `tests/combat/gauntlets_combo_state_test.tscn`
- Modify: `scripts/combat/damage_info.gd`
- Modify: `scripts/combat/health_component.gd`
- Modify: `scripts/enemies/enemy_base.gd`
- Modify: `scripts/enemies/boss_chrono_warden.gd`
- Modify: `autoload/combat_feedback.gd`

**Interfaces:**
- Consumes: `gauntlets_launch_v1`, Dash completion token, hit confirmations, damage notifications, time context, and Boss poise boundary.
- Produces: five-hit chain, cross-chain Combo tiers, heavy/counter/skill/ultimate, controlled launch/poise, HUD, facts, feedback, and snapshots.

- [x] **Step 1: Write chain/Combo separation and boundary tests**

Cover five action definitions, 120-frame Combo timeout, tier edges 4/5, 9/10, 14/15, 19/20, 29/30, damage reset, Dash retention, counter 7/8/9, action-token target deduplication, and non-recursive echoes.

- [x] **Step 2: Implement combo state and action runtime**

Attack-speed tiers affect only future plans. Critical/time-damage/resource modifiers are frozen at commit. Unsupported Boss launch becomes deterministic displacement or poise contribution.

- [x] **Step 3: Implement four time interactions and cleanup**

Stop extensions cap at 30 frames per source; Rewind counter window lasts 120 frames; Accelerate echoes every third eligible primary hit without recursion; Rift consumes immutable high-Combo modifiers.

- [x] **Step 4: Run Gauntlets, damage, Boss, feedback, reset, and replay gates**

Run: `./tools/run_tests.sh --filter "gauntlets|damage_info|health_component|chrono_warden|combat_feedback|rewind|replay"`

- [x] **Step 5: Commit**

```bash
git add -- scripts/combat/weapons/gauntlets_weapon_runtime.gd scripts/combat/weapons/gauntlets_combo_state.gd tests/combat/gauntlets_weapon_runtime_test.gd tests/combat/gauntlets_weapon_runtime_test.tscn tests/combat/gauntlets_combo_state_test.gd tests/combat/gauntlets_combo_state_test.tscn scripts/combat/damage_info.gd scripts/combat/health_component.gd scripts/enemies autoload/combat_feedback.gd
git commit -m "feat(weapon): add complete gauntlets runtime"
```

Execution record: P11F Launch Gauntlets is certified at implementation commit `2cfd31c`. The final Gauntlets gate passed `6 / 6` with zero leak warnings at `planewalker-tests.gKEXxs`. The final repository gate passed at `planewalker-validation.vp6gcQ`, including `103 / 103` Godot scenes, documentation `30 / 30` with zero violations, localization `8 / 8`, playtest data `13 / 13`, M1 release gate `27 / 27`, coverage contracts `5 / 5`, export contracts `37 / 37` in contract mode, and clean bootstrap/import checks. The only registered suite warning is `reward_system_smoke`. Final reviews reported no P0/P1 blocker. Formal product status remains `M1 Candidate — External Validation Pending`, authentic external playtests remain `0 / 20`, and replay plus cross-weapon player-entry UI remain P11G scope.

### Task 9: P11G cross-weapon UI, modifiers, replay, accessibility, and legacy removal

**Files:**
- Modify: `scripts/items/item_effect.gd`
- Modify: `scripts/application/run_view_state_projector.gd`
- Modify: `scripts/ui/contracts/run_view_state.gd`
- Modify: `scripts/ui/views/combat_hud_view.gd`
- Modify: `scripts/presentation/pixel_proxy_actor.gd`
- Modify: `scripts/presentation/combat_audio_synth.gd`
- Modify: `autoload/combat_feedback.gd`
- Modify: `autoload/event_bus.gd`
- Modify: `scripts/replay/replay_recorder.gd`
- Modify: `scripts/replay/replay_player.gd`
- Modify: `tests/ui/run_view_state_contract_test.gd`
- Modify: `tests/unit/application/run_view_state_projector_test.gd`
- Modify: `tests/presentation/combat_feedback_runtime_test.gd`
- Create: `tests/replay/weapon_runtime_replay_test.gd`
- Create: `tests/replay/weapon_runtime_replay_test.tscn`

**Interfaces:**
- Consumes: weapon presentation snapshots, typed facts, modifier capabilities, accessibility settings, and deterministic action/resource snapshots.
- Produces: validated `weapon_state` union, generic weapon HUD, correct proxy/audio/VFX routing, deterministic replay, and no legacy Sword/Bow branches.

- [ ] **Step 1: Write union, replay, cue-deduplication, and accessibility tests**

Reject unknown weapon/meter/status combinations, NaN/infinite/negative meters, duplicate cue facts, mismatched replay profile versions, and high-frequency flash/shake outside accessibility limits.

- [ ] **Step 2: Move every item effect to `WeaponModifierState` capabilities**

Remove direct writes to `player.sword_weapon` and `player.bow_weapon`. Content validation rejects unsupported effect-to-capability mappings before activation.

- [ ] **Step 3: Retire legacy facts and presentation fallbacks**

Remove `player_attacked` after all five runtimes and consumers use typed facts/cues. Remove generic `sword_swing` routing and every `SwordWeapon` child lookup.

- [ ] **Step 4: Verify HUD at all required resolutions and input modes**

Run visual/interaction checks at 640×360, 1280×720, 1920×1080, and ultrawide safe frames for keyboard/mouse, controller, hold, and toggle modes.

- [ ] **Step 5: Run cross-system tests and commit**

Run: `./tools/run_tests.sh --filter "run_view_state|combat_feedback|pixel_proxy|replay|accessibility|item_effect"`

```bash
git add -- scripts/items scripts/application scripts/ui scripts/presentation scripts/replay autoload tests/ui tests/unit/application tests/presentation tests/replay
git commit -m "refactor(weapons): unify cross-weapon presentation"
```

### Task 10: P11H 30-loadout matrix, simulations, documentation, and certification

**Files:**
- Modify: `tests/smoke/time_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/weapon_time_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/weapon_time_loadout_matrix_smoke_test.tscn`
- Create: `tools/run_weapon_simulation_matrix.py`
- Create: `tests/contract/playtest/test_weapon_simulation_report.py`
- Create: `docs/current/2026-09-29-p11-five-weapons-evidence.md`
- Modify: `docs/README.md`
- Modify: this plan

**Interfaces:**
- Consumes: five registered weapon profiles, six unordered legal time pairs, fixed seeds, full repository validation, and honest external-evidence boundaries.
- Produces: 30 deterministic loadout results, 30-seed weapon metrics, clean reset/replay evidence, and a locally verified P11 retention report.

- [ ] **Step 1: Write the matrix contract**

```gdscript
const WEAPONS := [&"sword", &"bow", &"gun", &"staff", &"gauntlets"]
const TIME_PAIRS := [
	[&"stop", &"rewind"], [&"stop", &"rift"], [&"stop", &"accelerate"],
	[&"rewind", &"rift"], [&"rewind", &"accelerate"], [&"rift", &"accelerate"],
]
```

Each case starts a run, commits representative weapon actions and both time abilities, validates HUD state, resets cleanly, and repeats with the same terminal digest.

- [ ] **Step 2: Add deterministic simulation reporting**

The report records DPS, risk uptime, starvation, burst, area coverage, status uptime, perfect-reload value, Staff combination frequency, and Gauntlets Combo retention. It reports observations; it does not claim authentic human playtest evidence.

- [ ] **Step 3: Run focused matrix twice and compare digests**

Run: `./tools/run_tests.sh --filter weapon_time_loadout_matrix`

Run: `PYTHONDONTWRITEBYTECODE=1 python3 tools/run_weapon_simulation_matrix.py --seeds 30 --output /tmp/planewalker-p11-sim-a.json`

Run the same command with `/tmp/planewalker-p11-sim-b.json`; expected SHA-256 digests are identical.

- [ ] **Step 4: Run full repository gates**

Run: `./tools/validate_project.sh`

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance tests.contract.localization.test_localization_contract tests.contract.playtest.test_weapon_simulation_report`

Run: `PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json`

Run: `git diff --check`

Expected: all tests pass; logs contain no parser/runtime/leak errors and only explicitly registered warnings.

- [ ] **Step 5: Write evidence without overstating external validation**

Record exact commits, commands, pass counts, digests, registered warnings, `0 / 20` authentic human playtests, unsupported GDScript line coverage, and outstanding export/signing/publication credentials.

- [ ] **Step 6: Mark this plan historical and commit certification**

```bash
git add -- tests/smoke tools/run_weapon_simulation_matrix.py tests/contract/playtest docs/current/2026-09-29-p11-five-weapons-evidence.md docs/README.md docs/superpowers/plans/2026-09-29-plane-walker-p11-five-weapons.md
git commit -m "docs(weapons): certify P11 five-weapon runtime"
```

## P11 Exit Gate

- Five weapons use one coordinator and no weapon-specific action ownership remains in `PlayerController`.
- M1 Sword and P10 Bow candidate parity pass before their expanded profiles are accepted.
- Gun, Staff, and Gauntlets are complete at LAUNCH/EXPANSION and unavailable earlier.
- Every weapon has input, resource/rhythm, primary/secondary/utility as applicable, skill, ultimate, four time interactions, Chrono Warden conversion, HUD, feedback, controller, accessibility, snapshot, reset, and replay coverage.
- The 30 loadout matrix and two-run deterministic digests pass.
- Full validation is green with only registered warnings.
- P11 evidence remains local and does not change the M1 external-validation status.
