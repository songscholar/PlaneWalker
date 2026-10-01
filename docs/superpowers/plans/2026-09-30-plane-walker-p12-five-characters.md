# Plane Walker P12 Five Complete Characters Implementation Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: Executable P12 work breakdown under the approved five-character design
- Applies To: Character runtime profiles, fresh Stats, character actions, weapon mastery, five character mechanics, fifteen talents, Launch selection, HUD, presentation, replay, 150 loadouts, simulations, and certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-30-plane-walker-p12-five-characters-design.md`, `docs/superpowers/specs/2026-09-29-plane-walker-p11-five-weapons-design.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-10-01
- Implementation Status: Design approved at `3057c7c`; P12A character-profile authority certified at `61eaae6`; Task 2A immutable damage committed at `3d45885`; irreversible HP authority committed at `6761ede`; rollback-safe Gameplay Rewind committed at `87eb931`; Task 2B fixed-frame transactional authority certified at `bc6e9eb`; Task 2C atomic character runtime shell committed at `3d2c6de`; Task 2D is next
- Exit Gate: Six milestone-aware character profiles, five complete Launch character runtimes, fifteen character talents, character UI/replay, all 150 loadouts, deterministic 4500-sample reports, full repository validation, and honest local evidence pass

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver five complete, mechanically distinct characters through one deterministic character-runtime authority and certify every `5 characters × 5 weapons × 6 time pairs = 150` Launch loadout without changing the frozen M1 Wanderer.

**Architecture:** ContentRegistry resolves a versioned `character_runtime_profile` beside the weapon profile. `PlayerCharacterRuntime` owns one character strategy and one frame-driven `CharacterActionCoordinator`; `PlayerController.advance_action_frame(frame_intents)` is the single gameplay clock for TimeManager, action state, TimeAction, character, weapon, Rewind sampling, and committed world payloads. Immutable `DamageResolution`, transactional Rewind/TimeAction contracts, stable hostile identities, `HostileThreatRegistry`, and `WorldPayloadAuthority` keep gameplay state independent from presentation and make live play and Replay use the same authoritative path.

**Tech Stack:** Godot 4.6.1, typed GDScript, JSON Schema, Content Pack v2, CSV localization, deterministic run-seed channels, scene-based tests, Python report contracts, and local Git commits.

## Global Constraints

- Formal status remains `M1 Candidate — External Validation Pending`; authentic human playtests remain `0 / 20`.
- `wanderer_m1_v1` preserves current M1/CURRENT/NEXT stats, actions, facts, HUD, replay, and Quick Start behavior.
- Launch config remains exactly one character, one weapon, and two distinct time abilities.
- Primordial Knight has one formal weapon; Time Lord has exactly the two equipped time abilities.
- Character Runtime, CharacterActionCoordinator, TimeManager, RewindRecorder, and WorldPayloadAuthority own no gameplay `_process()` or wall clock; `PlayerController.advance_action_frame(frame_intents)` is the only authoritative 60 Hz gameplay frame pump. `_process()` may project visuals only.
- Rejected character actions and conversions are atomic.
- Damage resolves in the fixed order `validity/immunity -> weapon defense -> character guard/Fortress/Ward -> accessibility multiplier -> flat defense -> finalized damage`. A `DamageResolution.is_prevented()` result changes no HP and publishes no generic damage/hit/resource fact.
- Character self-cost HP uses a monotonic `irreversible_hp_loss_total` and `revision`; Rewind target HP is `snapshot_hp - (current_total - snapshot_total)` clamped to the current valid range.
- Rewind and time skills use prepare/commit/rollback transactions. No prepare path consumes snapshots, clears actions, spends resources, changes cooldowns, appends Replay events, or spawns payloads.
- Every hostile hit carries deterministic `hostile_source_id`, `attack_generation`, and `hit_index`; runtime instance IDs are never Replay identities.
- Gameplay risk reads unscaled hostile facts from `HostileThreatRegistry`. `CombatTelegraph2D` projects those facts and may apply accessibility-only visual scaling without changing risk geometry.
- Mastery deduplication uses `(generation, action_token, mastery_family)`, not `mastery_id`, target, pellet, zone tick, or presentation payload.
- Input arbitration is exactly Dash -> equipped Time -> Character Skill -> Weapon. A committed higher-priority action consumes lower-priority same-frame press edges; rejected actions fall through without mutating latches.
- Gameplay Rewind never restores committed world payloads; Replay checkpoints reconstruct them exactly; reset, death, terminal, and loadout replacement invalidate their owning generation.
- Character costs, mastery claims, room banking, world consequences, and consumed resources are irreversible through Rewind unless the existing Rewind contract explicitly says otherwise.
- Character echoes, zones, damage ticks, and talent effects are non-recursive and cannot mint mastery or character resources.
- Every shared manifest, Registry, Host, Player, replay, UI contract, and assembly file has one integration owner at a time.
- GDScript line coverage remains `not collected (godot_line_coverage_unsupported)` until a real provider exists.
- Export contracts do not certify installed templates, packaged startup, signing, publication, or credentials.
- Launch Run Talents remain exactly fifteen: three frozen M1 talent IDs routed to Wanderer at Launch plus twelve new IDs. The certification matrix covers all `5 characters x 2^3 subsets = 40` legal character-talent subsets without creating extra talent definitions.

---

## Authoritative interfaces and implementation order

Tasks must execute in order because later character work consumes these exact contracts:

```gdscript
# scripts/combat/damage_info.gd
class_name DamageInfo
static func from_plan(plan: Dictionary) -> DamageInfo
func copy_for_source(new_source: Node) -> DamageInfo
func snapshot() -> Dictionary

# scripts/combat/damage_resolution.gd
class_name DamageResolution
static func prevented(reason: StringName, context: Dictionary) -> DamageResolution
static func applied(final_amount: float, context: Dictionary) -> DamageResolution
func is_prevented() -> bool
func finalized_damage() -> float
func snapshot() -> Dictionary

# scripts/player/characters/irreversible_character_ledger.gd
class_name IrreversibleCharacterLedger
func configure_run(run_id: StringName) -> bool
func reset_for_run(run_id: StringName) -> void
func record_hp_loss(amount: float, reason: StringName, source_token: int, source_generation: int) -> Dictionary
func hp_loss_state() -> Dictionary # {irreversible_hp_loss_total, revision}
func snapshot() -> Dictionary
func restore_replay_snapshot(value: Dictionary) -> bool
func restore_transaction_snapshot(value: Dictionary) -> bool

# scripts/combat/health_component.gd
func resolve_and_apply_damage(
	damage_info: DamageInfo,
	weapon_decision: Dictionary = {},
	character_decision: Dictionary = {}
) -> DamageResolution
func lose_health_irreversible(
	amount: float,
	reason: StringName,
	source_token: int,
	source_generation: int
) -> DamageResolution
func hp_loss_state() -> Dictionary
func transaction_snapshot() -> Dictionary
func restore_transaction_snapshot(value: Dictionary) -> bool

# scripts/time_system/rewind_recorder.gd
func configure_run(run_id: StringName) -> bool
func prepare_rewind_transaction() -> Dictionary
func commit_rewind_transaction(ticket: Dictionary) -> bool
func rollback_rewind_transaction(ticket: Dictionary) -> Dictionary

# scripts/time_system/time_action_transaction.gd
class_name TimeActionTransaction
func prepare(token: int, generation: int, frame: int, run_id: StringName, ability_id: StringName, pre_context: Dictionary) -> Dictionary
func commit(ticket: Dictionary) -> Dictionary
func rollback(ticket: Dictionary) -> Dictionary # exact restored prepare snapshot or failure

# scripts/combat/hostile_threat_registry.gd
class_name HostileThreatRegistry
func publish(fact: Dictionary) -> bool
func retire(hostile_source_id: StringName, attack_generation: int) -> bool
func fact_snapshot(hostile_source_id: StringName, attack_generation: int) -> Dictionary
func contains_point(point: Vector2, frame: int) -> bool
func nearest_hostile_distance(point: Vector2, frame: int) -> float

# scripts/combat/world_payload_authority.gd
class_name WorldPayloadAuthority
func commit_payload(descriptor: Dictionary) -> Dictionary
func contains(payload_id: StringName) -> bool
func replay_snapshot() -> Dictionary
func restore_replay_snapshot(value: Dictionary) -> bool
func invalidate_generation(run_id: StringName, owner_character_generation: int, reason: StringName) -> Dictionary

# scripts/time_system/time_manager.gd
func advance_frame(runtime_frame: int) -> void
func prepare_time_action(token: int, generation: int, frame: int, run_id: StringName, ability_id: StringName, pre_context: Dictionary) -> Dictionary
func commit_time_action(ticket: Dictionary) -> Dictionary
func rollback_time_action(ticket: Dictionary) -> Dictionary
```

`PlayerController.advance_action_frame(frame_intents)` advances in the exact order: increment frame and validate the ordered intent envelope; `TimeManager.advance_frame(runtime_frame)`; `PlayerActionState`; `TimeActionTransaction`; `CharacterActionCoordinator`; `WeaponActionCoordinator`; `WorldPayloadAuthority`; six-frame Rewind sampling; stale token/generation expiry and committed-fact publication; then at most one accepted action through priority arbitration. Live play, tests, simulation, and Replay call this same method.

The six profile rows are exact content, not suggested tuning:

| Profile | HP/ATK/DEF/Move | AtkSpd/Crit/CritMult | Time max/regen | `dash_duration_frames/dash_cooldown_frames/dash_speed/dash_cost_kind:dash_cost/dash_invulnerable_frames` |
|---|---|---|---|---|
| `wanderer_m1_v1` | `200/30/0/220` | `1.00/0.05/1.50` | `100/2` | `17f/27f/520/none:0/12f` |
| `wanderer_launch_v1` | `200/30/0/220` | `1.00/0.05/1.50` | `100/2` | `17f/27f/520/none:0/12f` |
| `time_guardian_launch_v1` | `240/27/10/190` | `0.90/0.04/1.50` | `120/2` | `18f/30f/500/none:0/12f` |
| `void_walker_launch_v1` | `160/32/0/235` | `1.05/0.08/1.60` | `90/2` | `15f/24f/560/none:0/11f` |
| `primordial_knight_launch_v1` | `230/31/8/200` | `0.90/0.05/1.55` | `110/2` | `18f/30f/490/none:0/10f` |
| `time_lord_launch_v1` | `175/24/2/205` | `0.95/0.05/1.50` | `160/4` | `16f/27f/520/none:0/12f` |

All frame counts are authoritative at 60 fps. Schema and content tests compare every numeric field exactly and reject omitted defaults.

---

### Task 1: P12A character-profile content authority

**Files:**
- Create: `data/schemas/character_runtime_profile_v1.schema.json`
- Create: `data/content_packs/base/content/character_runtime_profiles.json`
- Create: `scripts/player/characters/character_runtime_profile.gd`
- Modify: `data/content_packs/base/content/characters.json`
- Modify: `data/content_packs/base/content/talents.json`
- Modify: `data/content_packs/base/localization/translations.csv`
- Modify: `data/localization/translations.csv`
- Modify: `data/content_packs/base/pack.json`
- Modify: `data/schemas/content_entry_v2.schema.json`
- Modify: `scripts/content/content_registry.gd`
- Modify: `scripts/application/run_loadout_policy.gd`
- Modify: `tools/validate_project.sh`
- Create: `tests/contract/content_schema/character_runtime_profile_contract_test.gd`
- Create: `tests/contract/content_schema/character_runtime_profile_contract_test.tscn`
- Create: `tests/contract/content_schema/character_runtime_profile_ingestion_test.gd`
- Create: `tests/contract/content_schema/character_runtime_profile_ingestion_test.tscn`
- Create: `tests/contract/content_schema/test_character_runtime_profile_schema.py`
- Modify: `tests/contract/content_schema/content_registry_test.gd`
- Modify: `tests/contract/content_schema/loadout_catalog_contract_test.gd`
- Modify: `tests/unit/application/run_loadout_policy_test.gd`
- Modify: `tests/unit/content/content_pack_resolver_test.gd`

**Interfaces:**
- Consumes: canonical character definitions, milestone, and ContentRegistry pack loading.
- Produces: `CharacterRuntimeProfile.from_definition(definition)`, `ContentRegistry.get_character_runtime_profile(profile_id)`, `ContentRegistry.resolve_character_runtime_profile(character_id, milestone)`, and accepted loadout field `character_profile`.

- [x] **Step 1: Write failing profile and 150-policy contracts**

```gdscript
const CHARACTERS := [
	"wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord",
]
const WEAPONS := ["sword", "bow", "gun", "staff", "gauntlets"]
const TIME_PAIRS := [
	["stop", "rewind"], ["stop", "rift"], ["stop", "accelerate"],
	["rewind", "rift"], ["rewind", "accelerate"], ["rift", "accelerate"],
]

func test_launch_resolves_every_character_weapon_time_tuple() -> void:
	var accepted := 0
	for character_id: String in CHARACTERS:
		for weapon_id: String in WEAPONS:
			for time_pair: Array in TIME_PAIRS:
				var result = policy.validate(_launch_config(character_id, weapon_id, time_pair), registry)
				assert_true(result.ok, "%s/%s/%s" % [character_id, weapon_id, time_pair])
				assert_eq(result.context.loadout.character_profile.character_id, character_id)
				accepted += 1
	assert_eq(accepted, 150)

func _launch_config(character_id: String, weapon_id: String, time_pair: Array) -> Dictionary:
	return {
		"milestone": "LAUNCH",
		"character_id": character_id,
		"weapon_id": weapon_id,
		"enabled_time_skills": time_pair.duplicate(),
	}
```

Also reject missing/duplicate profile IDs, availability widening, mismatched character references, non-finite stats, unknown handlers, missing weapon/time coverage, unknown talent IDs, and a Launch profile resolving in M1.

Validate the catalog with a real Draft 2020-12 validator. Handler parameter dictionaries are closed per handler: every required key and exact v1 value is present, unknown keys are rejected, and `wanderer_m1_v1` requires empty/zero `none` payloads. Real temporary Content Pack fixtures cover empty or misspelled compatibility IDs, category and availability widening, missing/back-reference errors, missing or wrong Talent definitions, and character-only fields placed on another category.

Run the same 150 canonical tuples for both `LAUNCH` and `EXPANSION`. For every canonical unordered pair, the reversed serialization must fail with `INVALID_ARGUMENT/noncanonical_time_pair`, proving the accepted space is 150 rather than 300 ordered duplicates.

Add a table-driven assertion over the six authoritative rows in `Authoritative interfaces and implementation order`. The JSON must contain every base-stat and mobility key explicitly; parser defaults are forbidden for attack speed, critical values, Time values, Dash frames/speed/cost/invulnerability, or the `none:0` Wanderer Dash-cost marker.

- [x] **Step 2: Run contracts and confirm RED**

```bash
./tools/run_tests.sh --filter character_runtime_profile
./tools/run_tests.sh --filter loadout_catalog
./tools/run_tests.sh --filter run_loadout_policy
```

Expected: FAIL because the profile category and resolver do not exist.

- [x] **Step 3: Implement the strict profile parser**

```gdscript
class_name CharacterRuntimeProfile
extends RefCounted

var profile_id: StringName
var profile_version: int
var character_id: StringName
var availability: PackedStringArray
var runtime_kind: StringName
var base_stats: Dictionary
var mobility: Dictionary
var resource: Dictionary
var passive: Dictionary
var character_skill: Dictionary
var weapon_mastery: Dictionary
var time_interactions: Dictionary
var presentation: Dictionary
var capabilities: PackedStringArray
var talent_ids: PackedStringArray

static func from_definition(definition: Dictionary) -> CharacterRuntimeProfile:
	var profile := CharacterRuntimeProfile.new()
	var result := profile.configure(definition)
	return profile if bool(result.get("ok", false)) else null
```

Add the exact six profiles from the table above and register their manifest SHA-256 values. Every entry keeps the Content Pack v2 envelope `id`, `category=character_runtime_profile`, `availability`, `name_key`, `description_key`, `tags`, `compatibility`, and `effects`, then the closed typed profile fields; it cannot bypass localization, handler, manifest, cross-reference, or digest validation. `character_runtime_profile_v1.schema.json` requires every numeric field and constrains frame fields to integers; P12 requires `dash_cost_kind: "none"` with `dash_cost: 0` explicitly.

- [x] **Step 4: Resolve character and weapon profiles together**

`RunLoadoutPolicy.validate()` must return deep-copied `character`, `character_profile`, `weapon`, `weapon_profile`, and `time_abilities`. An empty compatibility dictionary means unrestricted; a present compatibility field must be non-empty, reference known content with matching category and availability, and fail during pack ingestion rather than at first run. Unsupported `archetype_ids` or `modes` constraints fail closed. Policy accepts only the canonical unordered time-pair serialization.

- [x] **Step 5: Run content and policy gates**

```bash
./tools/run_tests.sh --filter character_runtime_profile
./tools/run_tests.sh --filter content_registry
./tools/run_tests.sh --filter content_pack_resolver
./tools/run_tests.sh --filter loadout_catalog
./tools/run_tests.sh --filter run_loadout_policy
./tools/run_tests.sh --filter content_pack_contract
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_character_runtime_profile_schema
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
```

Expected: PASS with exactly six character profiles, fifteen registered Talent identities, 72 Base Pack definitions, exactly 150 accepted canonical tuples in each of Launch and Expansion, and all 150 reversed duplicates rejected in each milestone.

- [x] **Step 6: Commit**

```bash
git add -- data/schemas/character_runtime_profile_v1.schema.json data/content_packs/base/content/character_runtime_profiles.json data/content_packs/base/content/characters.json data/content_packs/base/content/talents.json data/content_packs/base/localization/translations.csv data/localization/translations.csv data/content_packs/base/pack.json data/schemas/content_entry_v2.schema.json scripts/content/content_registry.gd scripts/application/run_loadout_policy.gd scripts/player/characters/character_runtime_profile.gd tools/validate_project.sh tests/contract/content_schema/character_runtime_profile_contract_test.gd tests/contract/content_schema/character_runtime_profile_contract_test.tscn tests/contract/content_schema/character_runtime_profile_ingestion_test.gd tests/contract/content_schema/character_runtime_profile_ingestion_test.tscn tests/contract/content_schema/test_character_runtime_profile_schema.py tests/contract/content_schema/content_registry_test.gd tests/contract/content_schema/loadout_catalog_contract_test.gd tests/unit/application/run_loadout_policy_test.gd tests/unit/content/content_pack_resolver_test.gd
git commit -m "feat(characters): add p12 runtime profile authority"
```

Completed at implementation commit `61eaae6`; local certification is recorded in `docs/current/2026-09-30-p12a-character-profile-authority-evidence.md`.

### Task 2A: P12B immutable damage and irreversible Rewind transaction

**Files:**
- Create: `scripts/combat/damage_resolution.gd`
- Create: `scripts/player/characters/irreversible_character_ledger.gd`
- Modify: `scripts/combat/damage_info.gd`
- Modify: `scripts/combat/damage_calculator.gd`
- Modify: `scripts/combat/health_component.gd`
- Modify: `scripts/combat/hurtbox.gd`
- Modify: `scripts/combat/sword_weapon.gd`
- Modify: `scripts/combat/bow_weapon.gd`
- Modify: `scripts/combat/gauntlets_hit_execution.gd`
- Modify: `scripts/combat/gauntlets_zone_execution.gd`
- Modify: `scripts/combat/gun_projectile.gd`
- Modify: `scripts/combat/player_arrow.gd`
- Modify: `scripts/combat/staff_projectile.gd`
- Modify: `scripts/combat/staff_spell_zone.gd`
- Modify: `scripts/enemies/enemy_base.gd`
- Modify: `scripts/enemies/enemy_projectile.gd`
- Modify: `scripts/enemies/enemy_tank.gd`
- Modify: `scripts/enemies/boss_time_crack.gd`
- Modify: `scripts/enemies/boss_chrono_warden.gd`
- Modify: `scripts/time_system/rewind_echo_runtime.gd`
- Modify: `scripts/time_system/rewind_recorder.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/player/player_action_state.gd`
- Modify: `scripts/application/run_runtime_host.gd`
- Create: `tests/combat/damage_resolution_test.gd`
- Create: `tests/combat/damage_resolution_test.tscn`
- Create: `tests/characters/irreversible_character_ledger_test.gd`
- Create: `tests/characters/irreversible_character_ledger_test.tscn`
- Modify: `tests/combat/health_component_test.gd`
- Modify: `tests/combat/sword_launch_runtime_test.gd`
- Modify: `tests/combat/sword_m1_parity_test.gd`
- Modify: `tests/combat/damage_vulnerability_runtime_test.gd`
- Modify: `tests/combat/staff_damage_pipeline_test.gd`
- Modify: `tests/contract/events/combat_event_publication_test.gd`
- Modify: `tests/time/rewind_transaction_test.gd`
- Modify: `tests/time/rewind_action_cancellation_test.gd`
- Modify: `tests/time/time_loadout_runtime_test.gd`
- Modify: `tests/replay/weapon_restore_observable_atomicity_test.gd`
- Modify: `tests/integration/application/run_runtime_host_test.gd`

**Interfaces:**
- Consumes: validated `DamageInfo`, weapon-defense decision, character-defense decision, accessibility multiplier, flat defense, and current irreversible HP-loss state.
- Produces: immutable `DamageInfo.from_plan(plan)`, `HealthComponent.resolve_and_apply_damage(damage_info, weapon_decision, character_decision)`, immutable `DamageResolution`, monotonic `IrreversibleCharacterLedger.hp_loss_state()`, authoritative run identity injected by `RunRuntimeHost`, rollback-capable `PlayerActionState` snapshots, and `RewindRecorder.prepare_rewind_transaction()`, `commit_rewind_transaction(ticket)`, and `rollback_rewind_transaction(ticket)`.

The typed defense-decision envelope has exactly `prevented`, `multiplier`, `prevent_reason`, `guard_kind`, and `commit_context`. `{}` means no defense. `prevented=true` requires `multiplier=1.0`; otherwise `multiplier` must be finite and in `0.0..1.0`. Unknown keys, conflicting prevention fields, invalid types, and out-of-range values fail without HP, fact, guard-resource, or action-state side effects. Sword and later character defenses first plan decisions, then commit their guard/resource/mastery facts only after `HealthComponent` accepts the resolution.

- [x] **Step 1: Write failing damage-order and prevention tests**

```gdscript
func test_prevented_damage_has_no_hp_or_generic_fact_side_effect() -> void:
	var before_hp := health.current_hp
	var resolution: DamageResolution = health.resolve_and_apply_damage(
		_damage_plan(100.0),
		{"prevented": true, "guard_kind": "sword_perfect"},
		{}
	)
	assert_true(resolution.is_prevented())
	assert_eq(health.current_hp, before_hp)
	assert_eq(damage_applied_facts.size(), 0)
	assert_eq(hit_confirmed_facts.size(), 0)
	assert_eq(void_debt_facts.size(), 0)
	assert_eq(guard_mastery_facts.size(), 1)

func test_damage_stages_execute_in_contract_order() -> void:
	health.damage_received_multiplier = 0.50
	health.defense = 3.0
	var resolution := health.resolve_and_apply_damage(
		_damage_plan(100.0),
		{"multiplier": 0.80, "guard_kind": "weapon_normal"},
		{"multiplier": 0.50, "guard_kind": "guardian_normal"}
	)
	var snapshot := resolution.snapshot()
	assert_eq(snapshot.original_amount, 100.0)
	assert_eq(snapshot.post_weapon_defense_amount, 80.0)
	assert_eq(snapshot.post_character_defense_amount, 40.0)
	assert_eq(snapshot.post_accessibility_amount, 20.0)
	assert_eq(snapshot.post_defense_amount, 17.0)
	assert_eq(snapshot.finalized_damage, 17.0)

func _damage_plan(amount: float) -> DamageInfo:
	return DamageInfo.from_plan({
		"run_id": "run-a",
		"target_id": "player",
		"hostile_source_id": "enemy-a",
		"attack_generation": 1,
		"action_token": 1,
		"amount": amount,
		"damage_type": DamageInfo.DamageType.PHYSICAL,
		"tags": ["enemy:melee"],
	})
```

Also assert invalid/immunity short-circuit, Sword perfect guard never performs one-damage-then-heal, normal guard and Fortress/Ward compose once, accessibility cannot turn prevented damage into damage, final zero is legal only through `prevented`, and `DamageResolution.snapshot()` rejects mutation of its source context.

The focused suite includes `test_damage_info_from_plan_deep_freezes_source_collections`, `test_damage_resolution_snapshot_has_exact_fields_and_isolation`, `test_malformed_defense_decision_is_side_effect_free`, `test_dead_and_invulnerable_targets_return_prevented_resolution`, `test_unguardable_and_irreversible_tags_bypass_defense_decisions`, and `test_resolution_id_does_not_use_instance_identity`. Update Sword Launch parity so a perfect guard applies zero damage, preserves HP, never writes `refunded_damage`, and still commits exactly one Intent/guard fact. Keep `HealthComponent.take_damage()` as a float-returning compatibility wrapper over the new resolver while all callers migrate to immutable plans.

- [x] **Step 2: Write failing irreversible-loss and Rewind rollback tests**

```gdscript
func test_rewind_subtracts_irreversible_loss_since_snapshot() -> void:
	health.current_hp = 120.0
	recorder.record_snapshot_for_test()
	health.lose_health_irreversible(32.0, &"void_devour", 7, 3)
	var ticket := recorder.prepare_rewind_transaction()
	assert_eq(ticket.target_hp, 88.0)

func test_failed_rewind_restores_actions_payload_and_history() -> void:
	var before := _complete_runtime_snapshot()
	var ticket := recorder.prepare_rewind_transaction()
	_force_safe_action_restore_failure()
	assert_false(recorder.commit_rewind_transaction(ticket))
	assert_eq(_complete_runtime_snapshot(), before)

func _complete_runtime_snapshot() -> Dictionary:
	return {
		"position": player.global_position,
		"hp": health.current_hp,
		"safe_action": player.get_rewind_safe_action_state(),
		"rewind_samples": recorder.snapshots_for_test(),
	}

func _force_safe_action_restore_failure() -> void:
	recorder.set_restore_fault_for_test(&"safe_action")
```

Snapshots store both `irreversible_hp_loss_total` and `revision`. Target HP is `clampf(snapshot_hp - (current_total - snapshot_total), 0.0, current_max_hp)`. Reject negative deltas, run-ID mismatch, revision regression, duplicate stable claims, stale ticket, and duplicate commit/rollback. Terminal state rejects Rewind prepare, but terminal and irreversible HP losses are still recorded in the ledger rather than rejected.

Ledger tests also cover actual-loss rather than requested overkill, healing monotonicity, terminal claims, invalid non-finite/empty/negative claims, forged Replay roots, and new-run invalidation. Rewind tests cover prepare zero side effects, participant-revision drift, exact rollback of HP/dead/position/velocity/facing/action/history, committed-payload preservation, uncommitted-action cancellation only after successful validation, and run identity supplied by `RunRuntimeHost` rather than a test-only fixture.

- [ ] **Step 3: Run focused tests and confirm RED**

```bash
./tools/run_tests.sh --filter damage_resolution
./tools/run_tests.sh --filter irreversible_character_ledger
./tools/run_tests.sh --filter health_component
./tools/run_tests.sh --filter rewind_transaction
./tools/run_tests.sh --filter rewind_action_cancellation
./tools/run_tests.sh --filter sword_launch_runtime
./tools/run_tests.sh --filter sword_m1_parity
```

Expected: FAIL because prevention is still mutation-plus-refund and Rewind does not carry the irreversible ledger or rollback ticket.

- [x] **Step 4: Implement immutable resolution and ordered application**

`DamageInfo` deep-freezes a validated plan. Existing constructor call sites migrate to complete plans rather than constructing and assigning fields later. Container getters and `snapshot()` return copies. `copy_for_source()` is the only source-substitution path. `HealthComponent.resolve_and_apply_damage()` creates one `DamageResolution`; only an applied result subtracts HP and publishes `damaged`, `damage_applied`, or `hit_confirmed`. `take_damage()` remains the compatibility wrapper returning the finalized float.

Sword and character guards return typed defense decisions instead of mutating `DamageInfo.amount`. Sword perfect guard commits zero generic damage and no refund. Bow Starfall erosion becomes an explicit target-side modifier query instead of a `damage_about_to_apply` mutation. `damage_about_to_apply` remains a read-only observation event until its later versioned replacement; repository tests scan every listener and reject writes to the input object. Guard/mastery facts publish from the owning defense runtime after the resolution is accepted even when the generic result is prevented.

The immutable snapshot contains exactly `resolution_id`, `run_id`, `target_id`, `hostile_source_id`, `attack_generation`, `action_token`, `original_amount`, `post_weapon_defense_amount`, `post_character_defense_amount`, `post_accessibility_amount`, `post_defense_amount`, `finalized_damage`, `prevented`, `prevent_reason`, `guard_kind`, `irreversible`, and `tags`. `prevented` fixes finalized damage at zero. A positive non-prevented attack that survives percentage stages retains the existing minimum-one rule after flat defense. Self-cost, corruption, terminal, and explicitly unguardable tags bypass weapon/character defense but still produce a resolution and, when marked irreversible, one ledger claim.

- [x] **Step 5: Run damage gates and commit the immutable pipeline**

```bash
./tools/run_tests.sh --filter damage_resolution
./tools/run_tests.sh --filter health_component
./tools/run_tests.sh --filter sword_launch_runtime
./tools/run_tests.sh --filter sword_m1_parity
./tools/run_tests.sh --filter damage_vulnerability_runtime
./tools/run_tests.sh --filter staff_damage_pipeline
./tools/run_tests.sh --filter combat_event_publication
./tools/run_tests.sh --filter bow
./tools/run_tests.sh --filter gun
./tools/run_tests.sh --filter staff
./tools/run_tests.sh --filter gauntlets
git diff --check
```

Expected: PASS with true zero-damage prevention, immutable inputs/results, preserved M1 damage numbers, and no listener mutating `DamageInfo`.

```bash
git add -- scripts/combat/damage_resolution.gd scripts/combat/damage_info.gd scripts/combat/damage_calculator.gd scripts/combat/health_component.gd scripts/combat/hurtbox.gd scripts/combat/sword_weapon.gd scripts/combat/bow_weapon.gd scripts/combat/gauntlets_hit_execution.gd scripts/combat/gauntlets_zone_execution.gd scripts/combat/gun_projectile.gd scripts/combat/player_arrow.gd scripts/combat/staff_projectile.gd scripts/combat/staff_spell_zone.gd scripts/enemies/enemy_base.gd scripts/enemies/enemy_projectile.gd scripts/enemies/enemy_tank.gd scripts/enemies/boss_time_crack.gd scripts/enemies/boss_chrono_warden.gd scripts/time_system/rewind_echo_runtime.gd tests/combat/damage_resolution_test.gd tests/combat/damage_resolution_test.tscn tests/combat/health_component_test.gd tests/combat/sword_launch_runtime_test.gd tests/combat/sword_m1_parity_test.gd tests/combat/damage_vulnerability_runtime_test.gd tests/combat/staff_damage_pipeline_test.gd tests/contract/events/combat_event_publication_test.gd
git commit -m "fix(combat): install immutable damage resolution"
```

- [x] **Step 6: Implement and certify monotonic irreversible HP state**

`IrreversibleCharacterLedger` owns `run_id`, a monotonic actual-loss total, revision, and stable claim map keyed by `run_id:reason:source_generation:source_token`. Duplicate, non-finite, non-positive, empty-reason, invalid-token, stale-run, and forged-root claims fail without mutation. Healing and Gameplay Rewind never reduce the total. Reset installs a new run identity and invalidates old claims. Replay restore may install a fully validated snapshot; transaction rollback may install only the exact frozen pre-transaction snapshot.

`HealthComponent.lose_health_irreversible()` records the actual HP removed, including terminal loss, before death publication. `TimeManager._take_self_damage()` uses this path with a unique compatibility token/generation until Task 2B replaces it with the authoritative TimeAction transaction identity. `RunRuntimeHost` injects one stable run ID into Player, Health, Ledger, and Rewind rather than allowing tests to invent a separate identity path.

Implemented in `6761ede`. The ledger validates exact claim maps and SHA-256 roots, supports explicit single-use transaction freeze/restore/discard, and rejects stale-run, duplicate, malformed, non-finite, and forged state without mutation. Health records actual overkill loss before `damaged`, `entity_died`, and `died`; generic irreversible `DamageInfo` and TimeManager self-costs share the same authority. `RunRuntimeHost` installs run identity before loadout reset, and new runs invalidate both prior claims and Rewind history. Focused gates passed and the full scene suite completed at `117 / 117`; the only warning remains the pre-existing `reward_system_smoke.tscn` ObjectDB leak.

```bash
./tools/run_tests.sh --filter irreversible_character_ledger
./tools/run_tests.sh --filter health_component
./tools/run_tests.sh --filter time_loadout_runtime
./tools/run_tests.sh --filter run_runtime_host
./tools/run_tests.sh --filter rewind_transaction
git diff --check
git add -- scripts/player/characters/irreversible_character_ledger.gd scripts/combat/health_component.gd scripts/time_system/time_manager.gd scripts/player/player_controller.gd scripts/application/run_runtime_host.gd tests/characters/irreversible_character_ledger_test.gd tests/characters/irreversible_character_ledger_test.tscn tests/combat/health_component_test.gd tests/time/time_loadout_runtime_test.gd tests/time/rewind_transaction_test.gd tests/integration/application/run_runtime_host_test.gd
git commit -m "feat(health): add irreversible hp ledger"
```

- [x] **Step 7: Implement three-phase Gameplay Rewind**

Prepare freezes ticket/run/history revisions; current and snapshot ledger state; position, facing, velocity, HP/dead, safe action, PlayerActionState/coordinator state, snapshot history, and the pre-return origin used by later Time Lord conversions. It has zero side effects. Target HP applies the irreversible-loss formula and rejects negative ledger deltas, revision regression, terminal revival, non-finite values, stale tickets, and participant drift.

Commit validates every participant before installing any state. Gameplay Rewind cancels only uncommitted actions and preserves committed projectiles/zones/world payloads. Samples are consumed and lifecycle/cost/cooldown events publish only after all installs succeed. Any install failure rolls Player, Health, ActionState, coordinator/runtime, and history back to the exact frozen before-state; rollback itself is single-use and rejects stale/foreign tickets.

Implemented in `87eb931`. Prepare has zero side effects and freezes the complete participant/history revision set. Commit preflights every participant before the first install; stale tickets discard only their frozen ledger transaction and preserve history or participant state created after prepare. Seven injected failure stages restore Time, Health and the irreversible ledger, Player, PlayerActionState, WeaponActionCoordinator/runtime, and Rewind history to the exact frozen before-state. Terminal/dead players cannot be revived, history is consumed only after participant installs succeed, and observable lifecycle/health/resource/cooldown events publish only after final verification.

All five weapon paths now cancel only action-local uncommitted state while guarding committed projectiles, zones, waves, claims, and the same payload Node instances. A successful Gameplay Rewind deliberately marks the current P11 weapon Replay capture `GAMEPLAY_REWIND_UNSUPPORTED`; `weapon_replay_snapshot()` then returns empty instead of manufacturing an untrustworthy checkpoint. Replay schema 4 and authoritative reconstruction through `WorldPayloadAuthority` remain owned by Task 2B and Task 7.

- [x] **Step 8: Run Rewind and adjacent gates**

```bash
./tools/run_tests.sh --filter damage_resolution
./tools/run_tests.sh --filter irreversible_character_ledger
./tools/run_tests.sh --filter health_component
./tools/run_tests.sh --filter rewind
./tools/run_tests.sh --filter rewind_action_cancellation
./tools/run_tests.sh --filter sword_m1_parity
./tools/run_tests.sh --filter weapon_restore_observable_atomicity
./tools/run_tests.sh --filter combat_event_publication
./tools/run_tests.sh --filter run_runtime_host
git diff --check
```

Expected: PASS; a prevented hit leaves HP and generic fact counts unchanged, and every failed Rewind is byte-for-byte state preserving.

Verified on Godot `4.6.1`. Focused gates passed for PlayerActionState, WeaponActionCoordinator, Rewind transaction/cancellation/echo, Time loadout runtime, observable weapon restore atomicity, combat-event publication, both time/loadout matrix smokes, all five weapon runtimes and real payload paths, and Staff/Gauntlets Replay fact variants. The full scene suite passed `117 / 117` with `0` failures; the only warning remains the pre-existing `reward_system_smoke.tscn` ObjectDB leak. `git diff --check` also passed.

- [x] **Step 9: Commit the rollback-safe Gameplay Rewind**

Completed in `87eb931` (`fix(time): make gameplay rewind rollback-safe`). The committed scope includes the Rewind/Health/Time/Player transaction authorities, PlayerActionState, WeaponActionCoordinator and base runtime contracts, five weapon adapters and runtimes, semantic input routing, and all adjacent regression coverage required by the stricter adapter contract.

### Task 2B: P12B fixed-frame time actions and world-payload authority

**Files:**
- Create: `scripts/time_system/time_action_transaction.gd`
- Create: `scripts/combat/world_payload_authority.gd`
- Create: `scripts/player/characters/character_action_contract.gd`
- Create: `scripts/player/characters/character_action_coordinator.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `scripts/time_system/rewind_recorder.gd`
- Modify: `scripts/time_system/time_rift.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/replay/replay_recorder.gd`
- Modify: `scripts/replay/replay_player.gd`
- Modify: `autoload/event_bus.gd`
- Create: `tests/time/time_manager_fixed_frame_test.gd`
- Create: `tests/time/time_manager_fixed_frame_test.tscn`
- Create: `tests/time/time_action_transaction_test.gd`
- Create: `tests/time/time_action_transaction_test.tscn`
- Create: `tests/combat/world_payload_authority_test.gd`
- Create: `tests/combat/world_payload_authority_test.tscn`
- Create: `tests/characters/character_action_coordinator_test.gd`
- Create: `tests/characters/character_action_coordinator_test.tscn`
- Modify: `tests/time/time_loadout_runtime_test.gd`
- Modify: `tests/time/rewind_transaction_test.gd`
- Modify: `tests/replay/weapon_restore_observable_atomicity_test.gd`

**Interfaces:**
- Consumes: `PlayerController` frame/run identity and owner-character generation, authoritative energy/cooldown state, Rewind prepare context, and typed payload descriptors.
- Produces: the no-op-safe base `CharacterActionCoordinator`, `TimeManager.advance_frame(runtime_frame)`, TimeAction prepare/commit/rollback, `time_skill_committed(ability_id, token, generation, frame, run_id, context)`, and `WorldPayloadAuthority` gameplay-Rewind/Replay/reset semantics.

- [x] **Step 1: Write failing unified-frame tests**

```gdscript
const PlayerScene := preload("res://scenes/player/player.tscn")

func test_live_and_replay_advance_identical_time_state() -> void:
	var live := _configured_player()
	var replay := _configured_player()
	for frame in 360:
		live.advance_action_frame({})
		replay.advance_action_frame(_empty_replay_frame(frame).frame_intents)
	assert_eq(live.time_manager.replay_snapshot(), replay.time_manager.replay_snapshot())

func test_process_does_not_mutate_gameplay_state() -> void:
	var before := time_manager.replay_snapshot()
	time_manager._process(10.0)
	assert_eq(time_manager.replay_snapshot(), before)

func _configured_player() -> Node:
	var value := PlayerScene.instantiate()
	add_child(value)
	return value

func _empty_replay_frame(frame: int) -> Dictionary:
	return {"frame": frame, "frame_intents": {}}
```

Cover Stop duration, Accelerate duration, Rift duration/ticks, fixed-point energy regeneration, four cooldowns, Rewind samples exactly every six frames, character windows, and exact 60-frame = one-second behavior. Tests must call the same `PlayerController.advance_action_frame(frame_intents)` path for live and Replay.

- [x] **Step 2: Write failing TimeAction and world-payload tests**

```gdscript
func test_rewind_prepare_freezes_pre_return_position() -> void:
	var ticket := time_manager.prepare_time_action(8, 4, 120, &"run-a", &"rewind", {
		"pre_return_position": Vector2(300, 120),
	})
	player.global_position = Vector2.ZERO
	var committed := time_manager.commit_time_action(ticket)
	assert_eq(committed.context.pre_return_position, Vector2(300, 120))

func test_time_action_rollback_returns_exact_prepare_snapshot() -> void:
	var ticket := time_manager.prepare_time_action(9, 4, 121, &"run-a", &"stop", {})
	var rolled_back := time_manager.rollback_time_action(ticket)
	assert_true(rolled_back.ok)
	assert_eq(rolled_back.restored_snapshot, ticket.prepared_snapshot)

func test_world_payload_has_three_distinct_restore_semantics() -> void:
	var committed := payloads.commit_payload(_rift_descriptor(3))
	_apply_gameplay_rewind()
	assert_true(payloads.contains(committed.payload_id))
	var replay_state := payloads.replay_snapshot()
	var cleared := payloads.invalidate_generation(&"run-a", 3, &"loadout_replacement")
	assert_true(cleared.ok)
	assert_true(payloads.restore_replay_snapshot(replay_state))
	assert_eq(payloads.replay_snapshot(), replay_state)

func _rift_descriptor(owner_generation: int) -> Dictionary:
	return {
		"payload_id": "run-a:%d:rift:8:1" % owner_generation,
		"handler_id": "time_rift",
		"run_id": "run-a",
		"owner_character_generation": owner_generation,
		"payload_family": "rift",
		"source_token": 8,
		"payload_generation": 1,
		"transform": Transform2D.IDENTITY,
		"geometry": {"center": Vector2.ZERO, "radius": 96.0},
		"remaining_frames": 120,
		"claims": [],
		"tags": ["world_owned"],
		"parameters": {},
	}

func _apply_gameplay_rewind() -> void:
	var ticket := recorder.prepare_rewind_transaction()
	assert_false(ticket.is_empty())
	assert_true(recorder.commit_rewind_transaction(ticket))
```

Reject duplicate token/generation, wrong run/frame, commit without prepare, stale rollback, malformed descriptor, unknown payload factory, generation reuse after reset, and partial Rift restore. `TimeManager.replay_snapshot()` must include Stop, Accelerate, Rewind window, four cooldowns, energy revision, Rift source sequence, and complete active-Rift descriptors.

- [x] **Step 3: Run focused tests and confirm RED**

```bash
./tools/run_tests.sh --filter time_manager_fixed_frame
./tools/run_tests.sh --filter time_action_transaction
./tools/run_tests.sh --filter world_payload_authority
./tools/run_tests.sh --filter time_loadout_runtime
./tools/run_tests.sh --filter weapon_restore_observable_atomicity
```

Expected: FAIL because TimeManager still mutates from `_process()`, no unified committed fact exists, and active Rifts are absent from the Replay snapshot.

- [x] **Step 4: Create the base coordinator and move gameplay clocks to the fixed frame pump**

Create `CharacterActionContract` and a no-op-safe `CharacterActionCoordinator` before wiring the pump; Task 2C adds profile strategies without changing this frame interface. `PlayerController` owns `owner_character_generation`, initializes it to one, and advances it only when an atomic character activation commits, so WorldPayloadAuthority never depends on a later runtime class. `TimeManager.advance_frame(runtime_frame)` uses an integer frame and fixed-point regeneration remainder; it owns cooldowns, Stop, Accelerate, Rewind windows, and Rift lifetime. `PlayerController.advance_action_frame(frame_intents)` then advances PlayerActionState, TimeActionTransaction, CharacterActionCoordinator, WeaponActionCoordinator, and deterministic payload lifetimes in the specified order. `RewindRecorder.advance_frame(runtime_frame)` samples only when the frame reaches the six-frame cadence. `_process()` methods may update interpolation/visuals only and are asserted gameplay-pure.

- [x] **Step 5: Implement TimeAction exactly-once and fact publication**

Prepare validates ability selection and freezes immutable pre-context plus the complete participant snapshot. Commit spends energy, starts cooldown, applies the ability, then publishes exactly one `time_skill_committed`; failure rolls back every resource, cooldown, payload, and Replay prefix. `rollback(ticket)` returns `{ok, restored_snapshot, code}` and the restored snapshot must equal `ticket.prepared_snapshot` exactly. Rewind commits the prepared pre-return position and never recaptures it after movement.

- [x] **Step 6: Implement WorldPayloadAuthority and Rift Replay reconstruction**

Stable payload IDs use `run_id:owner_character_generation:payload_family:source_token:payload_generation`. Descriptors freeze handler ID, owner, source action/time token and generation, transform, gameplay geometry, remaining frames, hit/claim set, non-recursive tags, and deterministic parameters. Gameplay Rewind preserves committed descriptors/nodes and never installs the Replay snapshot. Replay restore validates and stages all descriptors off-tree before atomically replacing nodes. Reset/loadout/death calls `invalidate_generation(outgoing_run_id, outgoing_character_generation, reason)` and clears only that exact owner generation, including its Rifts; it rejects stale callbacks without touching another run or generation and returns removed stable IDs plus the new invalidation revision.

- [x] **Step 7: Run time, Replay, and matrix regressions**

```bash
./tools/run_tests.sh --filter time_manager_fixed_frame
./tools/run_tests.sh --filter time_action_transaction
./tools/run_tests.sh --filter world_payload_authority
./tools/run_tests.sh --filter rewind
./tools/run_tests.sh --filter replay
./tools/run_tests.sh --filter weapon_time_loadout_matrix
```

Expected: PASS with identical live/Replay terminal digests and exact active-Rift reconstruction.

Certification evidence recorded on 2026-09-30:

- Full Player Replay records semantic movement/aim/action intents, active Rift checkpoints, committed TimeAction facts, exact terminal snapshots, and failure-atomic playback rollback.
- Fixed-frame movement uses an explicit `1 / 60` integration step and Replay identity seals `move_speed`, so nonzero movement replays exactly and rejects mismatched movement profiles.
- Health, Time, and Weapon observer publications prepare/finalize together and publish only after World commit; rejected or lethal self-damage frames restore HP, death state, irreversible ledgers, TimeAction cursors, and all participant snapshots without leaking observer prefixes.
- World invalidation tombstones compact to one generation watermark per run while preserving permanent stale-generation rejection, monotonic invalidation revision, transaction rollback, and Replay restore.
- Legacy P11 schema-v6 Replay snapshots missing `energy_regen_remainder` authenticate before migration, migrate to the strict current Time snapshot, rebuild event/prefix/frame/terminal hashes, and remain tamper-evident.
- `./tools/run_tests.sh --filter replay`: `6 passed, 0 failed`, `0` leak warnings.
- Task 2B focused matrix (`time_manager_fixed_frame`, `time_action_transaction`, `world_payload_authority`, `player_fixed_frame_authority`, `health_component`, `rewind`, `player_action_runtime`, `player_loadout_runtime`, `time_loadout_runtime`, `run_runtime_host`, `player_semantic_weapon_input`, and `sword_launch_runtime`): all passed with `0` leak warnings.
- `./tools/run_tests.sh`: `123 passed, 0 failed`; only the pre-existing `reward_system_smoke` ObjectDB leak remains.
- Full-run log scan found no GDScript `SCRIPT ERROR` or script parse error; `git diff --check` passed.

- [x] **Step 8: Commit**

```bash
git add -- scripts/time_system/time_action_transaction.gd scripts/combat/world_payload_authority.gd scripts/player/characters/character_action_contract.gd scripts/player/characters/character_action_coordinator.gd scripts/time_system/time_manager.gd scripts/time_system/rewind_recorder.gd scripts/time_system/time_rift.gd scripts/player/player_controller.gd scripts/replay/replay_recorder.gd scripts/replay/replay_player.gd autoload/event_bus.gd tests/time/time_manager_fixed_frame_test.gd tests/time/time_manager_fixed_frame_test.tscn tests/time/time_action_transaction_test.gd tests/time/time_action_transaction_test.tscn tests/combat/world_payload_authority_test.gd tests/combat/world_payload_authority_test.tscn tests/characters/character_action_coordinator_test.gd tests/characters/character_action_coordinator_test.tscn tests/time/time_loadout_runtime_test.gd tests/time/rewind_transaction_test.gd tests/replay/weapon_restore_observable_atomicity_test.gd
git commit -m "feat(time): unify fixed-frame transactional authority"
```

Committed as `bc6e9eb` (`feat(time): unify fixed-frame transactional authority`).

### Task 2C: P12B runtime shell, fresh Stats, and atomic assembly

**Files:**
- Create: `scripts/player/characters/character_runtime.gd`
- Create: `scripts/player/characters/player_character_runtime.gd`
- Create: `scripts/player/characters/character_runtime_factory.gd`
- Modify: `scripts/player/characters/character_action_contract.gd`
- Modify: `scripts/player/characters/character_action_coordinator.gd`
- Modify: `scripts/core/stats.gd`
- Modify: `scripts/combat/sword_weapon.gd`
- Modify: `scripts/combat/bow_weapon.gd`
- Modify: `scripts/combat/gun_weapon.gd`
- Modify: `scripts/combat/staff_weapon.gd`
- Modify: `scripts/combat/gauntlets_weapon.gd`
- Modify: `scripts/combat/weapons/sword_weapon_runtime.gd`
- Modify: `scripts/combat/weapons/bow_weapon_runtime.gd`
- Modify: `scripts/combat/weapons/gun_weapon_runtime.gd`
- Modify: `scripts/combat/weapons/staff_weapon_runtime.gd`
- Modify: `scripts/combat/weapons/gauntlets_weapon_runtime.gd`
- Modify: `scripts/player/player_loadout_runtime.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/application/run_runtime_host.gd`
- Modify: `scripts/player/player_action_state.gd`
- Modify: `tests/characters/character_action_coordinator_test.gd`
- Modify: `tests/characters/character_action_coordinator_test.tscn`
- Create: `tests/characters/player_character_runtime_test.gd`
- Create: `tests/characters/player_character_runtime_test.tscn`
- Modify: `tests/player/player_loadout_runtime_test.gd`
- Modify: `tests/integration/application/run_runtime_host_test.gd`
- Modify: `tests/combat/sword_m1_parity_test.gd`
- Modify: `tests/combat/sword_weapon_runtime_test.gd`
- Modify: `tests/combat/bow_weapon_runtime_test.gd`
- Modify: `tests/combat/gun_weapon_runtime_test.gd`
- Modify: `tests/combat/staff_weapon_runtime_test.gd`
- Modify: `tests/combat/gauntlets_weapon_runtime_test.gd`

**Interfaces:**
- Consumes: authoritative character profile, selected talents, Player owner, and Player frame/lifecycle hooks.
- Produces: atomic `configure_character(profile, talents)`, `Stats.apply_profile(base_stats)`, `PlayerController.apply_mobility_profile(mobility)`, `advance_frame(context)`, `try_character_skill(intent, context)`, lifecycle hooks, `snapshot()`, `restore_snapshot()`, and `presentation_snapshot()`.

- [x] **Step 1: Write failing fresh-state and rollback tests**

```gdscript
func test_failed_character_swap_preserves_complete_prior_runtime() -> void:
	var before := player.character_runtime_snapshot()
	assert_false(player.configure_loadout(_config_with_forged_character_profile()))
	assert_eq(player.character_runtime_snapshot(), before)
	assert_eq(player.stats.attack, 30.0)

func test_new_run_rebuilds_stats_before_rewards() -> void:
	player.stats.attack = 999.0
	assert_true(player.configure_loadout(_guardian_config()))
	assert_eq(player.stats.attack, 27.0)
	assert_eq(player.stats.attack_speed, 0.90)
	assert_eq(player.stats.crit_chance, 0.04)
	assert_eq(player.mobility_snapshot(), {
		"dash_duration_frames": 18,
		"dash_cooldown_frames": 30,
		"dash_speed": 500.0,
		"dash_cost_kind": "none",
		"dash_cost": 0.0,
		"dash_invulnerable_frames": 12,
	})

func _guardian_config() -> Dictionary:
	return {
		"milestone": "LAUNCH",
		"character_id": "time_guardian",
		"character_profile": registry.resolve_character_runtime_profile(
			&"time_guardian", &"LAUNCH"
		),
		"weapon_id": "sword",
		"weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"),
		"enabled_time_skills": ["stop", "rewind"],
		"character_talents": [],
	}

func _config_with_forged_character_profile() -> Dictionary:
	var value := _guardian_config()
	value.character_profile = (value.character_profile as Dictionary).duplicate(true)
	value.character_profile.base_stats.attack = 999.0
	return value
```

Cover all six exact profile rows, including attack speed, critical chance/multiplier, Time max/regen, and every Dash field. Cover health/current HP, energy/max/regen, weapon runtime, PlayerActionState, character runtime, presentation, and Replay-prefix rollback. Reject missing numeric keys instead of falling back to `Stats` or Player constants.

- [x] **Step 2: Confirm RED**

```bash
./tools/run_tests.sh --filter player_character_runtime
./tools/run_tests.sh --filter player_loadout_runtime
./tools/run_tests.sh --filter run_runtime_host
./tools/run_tests.sh --filter sword_m1_parity
```

- [x] **Step 3: Implement the runtime shell**

```gdscript
class_name CharacterRuntime
extends RefCounted

func configure(_owner: Node, _profile: CharacterRuntimeProfile, _talents: PackedStringArray) -> bool: return false
func reset_runtime_state(_reason: StringName) -> void: pass
func advance_frame(_context: Dictionary) -> Array[Dictionary]: return []
func plan_character_skill(_intent: Dictionary, _context: Dictionary) -> Dictionary: return {"ok": false, "code": "unsupported"}
func commit_character_skill(_plan: Dictionary, _token: int) -> Dictionary: return {"ok": false, "code": "unsupported"}
func before_damage(_damage_context: Dictionary) -> Dictionary: return {"ok": true, "decision": {}}
func after_damage(_damage_context: Dictionary) -> Array[Dictionary]: return []
func on_weapon_action_committed(_action_context: Dictionary) -> Array[Dictionary]: return []
func on_weapon_mastery_confirmed(_mastery_context: Dictionary) -> Array[Dictionary]: return []
func before_time_skill(_time_context: Dictionary) -> Dictionary: return {"ok": true, "decision": {}}
func after_time_skill(_time_context: Dictionary) -> Array[Dictionary]: return []
func on_room_started(_room_context: Dictionary) -> Array[Dictionary]: return []
func on_room_cleared(_room_context: Dictionary) -> Array[Dictionary]: return []
func on_run_terminal(_run_context: Dictionary) -> Dictionary: return {"ok": true, "summary": {}}
func snapshot() -> Dictionary: return {}
func restore_snapshot(_snapshot: Dictionary) -> bool: return false
func presentation_snapshot() -> Dictionary: return {}
```

The coordinator deep-copies committed plans, uses generation/token floors, never advances from `_process()`, and publishes nothing on rejection.

- [x] **Step 4: Add fresh Stats and mobility reconstruction plus universal weapon scaling**

Add `Stats.apply_profile(base_stats)` and `Stats.snapshot()`. Replace Player Dash constants as gameplay authority with an installed mobility snapshot containing integer `dash_duration_frames`, `dash_cooldown_frames`, `dash_invulnerable_frames`, finite `dash_speed`, and the explicit P12 pair `dash_cost_kind: "none"` / `dash_cost: 0`. Rebuild Stats and mobility before health/energy sync and before run-local rewards. Freeze `character_attack_scale = stats.attack / 30.0`, attack speed, critical chance, and critical multiplier into every weapon plan/payload so Wanderer remains exact and all five weapons respond consistently.

- [x] **Step 5: Install character and weapon atomically**

The Host injects both profiles. `PlayerController.configure_loadout()` validates and assembles both runtimes before disconnecting the prior runtime. Candidate assembly does not change `owner_character_generation`; successful atomic activation increments it exactly once and injects the committed run ID/generation into Character Runtime and WorldPayloadAuthority. Failed character activation, weapon activation, adapter activation, health sync, or energy sync restores the exact prior generation and state.

- [x] **Step 6: Run shell and parity gates**

```bash
./tools/run_tests.sh --filter character_action_coordinator
./tools/run_tests.sh --filter player_character_runtime
./tools/run_tests.sh --filter player_loadout_runtime
./tools/run_tests.sh --filter run_runtime_host
./tools/run_tests.sh --filter sword_m1_parity
./tools/run_tests.sh --filter sword_weapon_runtime
./tools/run_tests.sh --filter bow_weapon_runtime
./tools/run_tests.sh --filter gun_weapon_runtime
./tools/run_tests.sh --filter staff_weapon_runtime
./tools/run_tests.sh --filter gauntlets_weapon_runtime
./tools/run_tests.sh --filter weapon_time_loadout_matrix
```

Expected: M1 and the certified P11 30-loadout matrix remain green; each Launch profile reports the exact stats/mobility row above after two fresh-run reconstructions.

- [x] **Step 7: Commit**

```bash
git add -- scripts/player/characters/character_runtime.gd scripts/player/characters/player_character_runtime.gd scripts/player/characters/character_runtime_factory.gd scripts/player/characters/character_action_contract.gd scripts/player/characters/character_action_coordinator.gd scripts/core/stats.gd scripts/combat/sword_weapon.gd scripts/combat/bow_weapon.gd scripts/combat/gun_weapon.gd scripts/combat/staff_weapon.gd scripts/combat/gauntlets_weapon.gd scripts/combat/weapons/sword_weapon_runtime.gd scripts/combat/weapons/bow_weapon_runtime.gd scripts/combat/weapons/gun_weapon_runtime.gd scripts/combat/weapons/staff_weapon_runtime.gd scripts/combat/weapons/gauntlets_weapon_runtime.gd scripts/player/player_loadout_runtime.gd scripts/player/player_controller.gd scripts/application/run_runtime_host.gd scripts/player/player_action_state.gd tests/characters/character_action_coordinator_test.gd tests/characters/character_action_coordinator_test.tscn tests/characters/player_character_runtime_test.gd tests/characters/player_character_runtime_test.tscn tests/player/player_loadout_runtime_test.gd tests/integration/application/run_runtime_host_test.gd tests/combat/sword_m1_parity_test.gd tests/combat/sword_weapon_runtime_test.gd tests/combat/bow_weapon_runtime_test.gd tests/combat/gun_weapon_runtime_test.gd tests/combat/staff_weapon_runtime_test.gd tests/combat/gauntlets_weapon_runtime_test.gd
git commit -m "feat(characters): add atomic character runtime shell"
```

**Task 2C evidence — 2026-10-01:**

- Commit: `3d2c6de feat(characters): add atomic character runtime shell`.
- Added six-kind Character Runtime construction, strict strategy snapshots, lifecycle hooks, generation/token authority, and fail-closed restore integrity.
- Rebuilt `Stats`, mobility, Health, Time Energy, Character Runtime, and five weapon adapters from the authoritative milestone-aware Character Profile on every accepted activation.
- Sealed Character Profile, talents, Stats, mobility, and Character action authority into Full Player Replay schema v2; legacy v1 Replay/frame/snapshot inputs reject explicitly.
- Preserved Weapon Replay through a narrow replay-neutral allowlist for talent-free, resource-initial Wanderer M1/Launch shells; every other Profile, talent, resource drift, action token/plan, invalid frame, or restore-integrity fault rejects without mutation.
- Certified fixed-at-press character combat attributes through Sword, Bow, Gun, Staff, and Gauntlets, including Hold-to-Release live-context refresh and Sword M1 plan-integrity rejection.
- Full repository scene gate: `125 passed, 0 failed, 125 total`; one pre-existing `reward_system_smoke` ObjectDB leak warning remains allowlisted.
- Godot headless launch exited `0`; no `SCRIPT ERROR`, `Parse Error`, unexpected ObjectDB leak, or RID leak was detected. `git diff --check` passed before commit.

### Task 2D: P12B semantic input, mastery families, and deterministic hooks

**Files:**
- Modify: `project.godot`
- Modify: `scripts/input/input_action_contract.gd`
- Modify: `scripts/input/weapon_intent_router.gd`
- Modify: `scripts/input/input_binding_codec.gd`
- Modify: `scripts/input/input_profile_store.gd`
- Modify: `scripts/input/input_remap_service.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/player/characters/character_action_coordinator.gd`
- Modify: `autoload/event_bus.gd`
- Modify: `scripts/combat/weapons/weapon_runtime.gd`
- Modify: `scripts/combat/weapons/sword_weapon_runtime.gd`
- Modify: `scripts/combat/weapons/bow_weapon_runtime.gd`
- Modify: `scripts/combat/weapons/gun_weapon_runtime.gd`
- Modify: `scripts/combat/weapons/staff_weapon_runtime.gd`
- Modify: `scripts/combat/weapons/gauntlets_weapon_runtime.gd`
- Modify: `scripts/combat/damage_calculator.gd`
- Create: `tests/fixtures/input/input_profile_v2.json`
- Create: `tests/contract/input/character_skill_input_test.gd`
- Create: `tests/contract/input/character_skill_input_test.tscn`
- Modify: `tests/contract/input/weapon_intent_router_test.gd`
- Modify: `tests/unit/input/input_binding_codec_test.gd`
- Modify: `tests/unit/input/input_remap_service_test.gd`
- Modify: `tests/unit/input/input_profile_store_test.gd`
- Create: `tests/characters/weapon_mastery_fact_test.gd`
- Create: `tests/characters/weapon_mastery_fact_test.tscn`
- Modify: `tests/contract/events/combat_event_publication_test.gd`
- Modify: `tests/integration/ui/input_remap_panel_test.gd`
- Create: `tests/combat/damage_calculator_test.gd`
- Create: `tests/combat/damage_calculator_test.tscn`

**Interfaces:**
- Consumes: schema-1 fixed-action saves, a real schema-2 semantic fixture, raw input edges, committed weapon results, stable seed/context, and typed combat facts.
- Produces: schema-3 semantic `character_skill`, exact Dash -> Time -> Character -> Weapon arbitration, and `CharacterActionCoordinator.confirm_weapon_mastery(fact) -> bool` deduplicated by `(generation, action_token, mastery_family)`.

- [ ] **Step 1: Write failing migration and exactly-once tests**

```gdscript
func test_character_skill_binding_round_trips() -> void:
	var router := WeaponIntentRouter.new()
	var source := _load_v2_fixture()
	var weapon_primary_before: Dictionary = source.bindings.weapon_primary.duplicate(true)
	var migrated := router.migrate_profile(source)
	assert_eq(migrated.schema_version, 3)
	assert_eq(migrated.bindings.weapon_primary, weapon_primary_before)
	assert_eq(migrated.bindings.character_skill, {
		"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_C}],
		"controller": [{"type": "joypad_button", "button_index": 8}],
	})

func _load_v2_fixture() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/input/input_profile_v2.json"
	))
	assert_true(value is Dictionary)
	return (value as Dictionary).duplicate(true)

func test_multi_hit_action_publishes_one_mastery() -> void:
	for target_id in [11, 12, 13]:
		_confirm_mastery(&"gun", &"gun", &"gun_magazine_finisher", 9, 44, target_id)
	assert_eq(mastery_facts.size(), 1)

func test_same_token_different_mastery_ids_share_one_family_claim() -> void:
	_confirm_mastery(&"gun", &"gun", &"gun_perfect_reload", 9, 44, 11)
	_confirm_mastery(&"gun", &"gun", &"gun_magazine_finisher", 9, 44, 12)
	assert_eq(mastery_facts.size(), 1)

func _confirm_mastery(
	weapon_id: StringName,
	mastery_family: StringName,
	mastery_id: StringName,
	generation: int,
	action_token: int,
	target_id: int
) -> void:
	coordinator.confirm_weapon_mastery({
		"weapon_id": weapon_id,
		"mastery_family": mastery_family,
		"mastery_id": mastery_id,
		"action_id": &"weapon_primary",
		"generation": generation,
		"action_token": action_token,
		"target_id": target_id,
		"context": {},
	})
```

Load `tests/fixtures/input/input_profile_v2.json` from disk rather than constructing only an in-memory approximation. Cover the exact recovery order: verified `input_profile_v3.json`, verified `backup_3.json`, verified v2 primary/backup, then verified v1 primary/backup. Also cover schema `1 -> 2 -> 3` with no direct `1 -> 3`, schema `2 -> 3`, corrupt-primary recovery, atomic schema-3 promotion/round trip, saved-remap priority over defaults, controller binding, conflict rejection, hold/toggle equivalence, stale tokens, echo recursion, pellet/zone deduplication, and no mastery from rejected actions. Extend joypad-button codec validation to inclusive `0..31`; assert button 31 round-trips, button 32 rejects, and a fixture occupying every button `0..31` returns `NO_REACHABLE_CHARACTER_SKILL` without modifying the v2 source.

Add simultaneous-edge cases proving: accepted Dash consumes Time/Character/Weapon press edges; rejected Dash falls through to Time; accepted Time consumes Character/Weapon; rejected Time falls through to Character; accepted Character consumes Weapon; Character hold release returns only to its owning coordinator; loadout replacement/death/reset clears every pending latch and buffered lower-priority action.

- [ ] **Step 2: Confirm RED**

```bash
./tools/run_tests.sh --filter character_skill_input
./tools/run_tests.sh --filter weapon_mastery_fact
./tools/run_tests.sh --filter combat_event_publication
./tools/run_tests.sh --filter input_remap
```

- [ ] **Step 3: Add semantic input and typed facts**

Advance the input profile to schema 3. Schema 1 must first pass through the existing schema-2 semantic mapping and only then receive the schema-3 character field; schema 2 migrates directly and preserves every existing binding record byte-for-byte. Try keyboard `C` and controller button `8` first. If occupied, choose the first unowned printable physical keycode in ascending order after `C` and the first unowned controller button in `8, 0..31` order. If either finite family is exhausted, return `NO_REACHABLE_CHARACTER_SKILL`, preserve the verified v2 source, and do not promote a partial v3 file. Retire runtime listening/binding requirements for the four fixed legacy time actions after migration while preserving canonical fixed-ID mapping for old replay/config data.

```gdscript
signal weapon_mastery_confirmed(weapon_id: StringName, mastery_family: StringName, mastery_id: StringName, action_id: StringName, token: int, generation: int, target_id: int, context: Dictionary)
signal character_skill_committed(character_id: StringName, skill_id: StringName, token: int, context: Dictionary)
signal character_resource_changed(character_id: StringName, resource_id: StringName, current: float, maximum: float, reason: StringName)
signal character_conversion_resolved(character_id: StringName, conversion_id: StringName, token: int, context: Dictionary)
```

Use one explicit mastery claim per `(generation, token, mastery_family)`. The five family IDs are the canonical weapon IDs `sword`, `bow`, `gun`, `staff`, and `gauntlets`. A different `mastery_id`, target, hit index, pellet, arrow, chain, zone tick, echo, status, or presentation event cannot mint a second claim.

- [ ] **Step 4: Implement priority and cancellation policy**

Sample each semantic edge once. Try Dash, then `time_slot_1`, then `time_slot_2`, then Character Skill, then weapon semantics in profile declaration order. A successful commit records every lower-priority same-frame edge as `priority_suppressed` and discards it; suppressed edges are never buffered. A rejection falls through without state mutation. Dash cancels an uncommitted character windup/hold; hitstun and Gameplay Rewind cancel every uncommitted character phase before their own transition. Guardian cancellation before a guard resolution spends no Ward/energy and starts no cooldown; cancellation after a perfect/normal resolution preserves its fact/Ward and starts the 240-frame ordinary cooldown; committed Fortress, Waypoint anchor, Devour/Cleave payload, and armed Dominion remain authoritative and are never refunded by cancellation.

- [ ] **Step 5: Replace global critical randomness**

`DamageCalculator` accepts a frozen deterministic critical outcome or seeded roll context. Tests reject unseeded character/150-matrix paths; legacy non-gameplay fixtures pass an explicit deterministic `critical_outcome` rather than invoking global randomness.

```gdscript
func test_seeded_critical_is_repeatable_and_source_has_no_global_randf() -> void:
	var context := {"seed": 4127, "channel": "damage_critical", "roll_index": 0}
	var first := DamageCalculator.calculate(_critical_fixture(), 0.0, context)
	var second := DamageCalculator.calculate(_critical_fixture(), 0.0, context)
	assert_eq(first, second)
	var source := FileAccess.get_file_as_string("res://scripts/combat/damage_calculator.gd")
	assert_false(source.contains("randf("))

func _critical_fixture() -> DamageInfo:
	var info := DamageInfo.new(100.0, DamageInfo.DamageType.PHYSICAL)
	info.can_crit = true
	info.crit_chance = 0.25
	info.crit_multiplier = 1.5
	return info
```

- [ ] **Step 6: Run input, event, weapon, and deterministic regressions**

```bash
./tools/run_tests.sh --filter input
./tools/run_tests.sh --filter character_skill_input
./tools/run_tests.sh --filter player_semantic_weapon_input
./tools/run_tests.sh --filter combat_event_publication
./tools/run_tests.sh --filter weapon_mastery_fact
./tools/run_tests.sh --filter weapon_action_coordinator
./tools/run_tests.sh --filter damage_calculator
./tools/run_tests.sh --filter gun
./tools/run_tests.sh --filter staff
./tools/run_tests.sh --filter gauntlets
```

- [ ] **Step 7: Commit**

```bash
git add -- project.godot scripts/input/input_action_contract.gd scripts/input/weapon_intent_router.gd scripts/input/input_binding_codec.gd scripts/input/input_profile_store.gd scripts/input/input_remap_service.gd scripts/player/player_controller.gd scripts/player/characters/character_action_coordinator.gd autoload/event_bus.gd scripts/combat/weapons/weapon_runtime.gd scripts/combat/weapons/sword_weapon_runtime.gd scripts/combat/weapons/bow_weapon_runtime.gd scripts/combat/weapons/gun_weapon_runtime.gd scripts/combat/weapons/staff_weapon_runtime.gd scripts/combat/weapons/gauntlets_weapon_runtime.gd scripts/combat/damage_calculator.gd tests/fixtures/input/input_profile_v2.json tests/contract/input/character_skill_input_test.gd tests/contract/input/character_skill_input_test.tscn tests/contract/input/weapon_intent_router_test.gd tests/unit/input/input_binding_codec_test.gd tests/unit/input/input_remap_service_test.gd tests/unit/input/input_profile_store_test.gd tests/characters/weapon_mastery_fact_test.gd tests/characters/weapon_mastery_fact_test.tscn tests/contract/events/combat_event_publication_test.gd tests/integration/ui/input_remap_panel_test.gd tests/combat/damage_calculator_test.gd tests/combat/damage_calculator_test.tscn
git commit -m "feat(characters): add character input and mastery facts"
```

### Task 2E: P12B stable hostile identity and unscaled threat facts

**Files:**
- Create: `scripts/combat/hostile_telegraph_fact.gd`
- Create: `scripts/combat/hostile_threat_registry.gd`
- Modify: `scripts/combat/damage_info.gd`
- Modify: `scripts/fx/combat_telegraph_2d.gd`
- Modify: `scripts/enemies/enemy_base.gd`
- Modify: `scripts/enemies/enemy_chaser.gd`
- Modify: `scripts/enemies/enemy_shooter.gd`
- Modify: `scripts/enemies/enemy_projectile.gd`
- Modify: `scripts/enemies/enemy_tank.gd`
- Modify: `scripts/enemies/boss_time_crack.gd`
- Modify: `scripts/enemies/boss_chrono_warden.gd`
- Modify: `scripts/dungeon/room_controller.gd`
- Modify: `scripts/application/run_runtime_host.gd`
- Create: `tests/combat/hostile_attack_identity_test.gd`
- Create: `tests/combat/hostile_attack_identity_test.tscn`
- Create: `tests/combat/hostile_threat_registry_test.gd`
- Create: `tests/combat/hostile_threat_registry_test.tscn`
- Modify: `tests/combat/enemy_projectile_test.gd`
- Modify: `tests/combat/boss_telegraph_test.gd`
- Modify: `tests/unit/dungeon/encounter_runner_test.gd`

**Interfaces:**
- Consumes: deterministic run/room/spawn identity, accepted hostile attack start, immutable unscaled geometry, and active frame bounds.
- Produces: `EnemyBase.configure_hostile_identity(source_id, next_generation_floor)`, `DamageInfo.hostile_source_id`, `DamageInfo.attack_generation`, `DamageInfo.hit_index`, and `HostileThreatRegistry` queries that never depend on presentation scale.

- [ ] **Step 1: Write failing hostile identity tests**

```gdscript
func test_projectiles_from_one_burst_share_generation_and_have_unique_hit_index() -> void:
	var burst := _spawn_shooter_burst(&"run7:room2:spawn4", 3)
	assert_eq(burst.map(func(p): return p.hostile_source_id), [
		&"run7:room2:spawn4", &"run7:room2:spawn4", &"run7:room2:spawn4",
	])
	assert_eq(burst.map(func(p): return p.attack_generation), [1, 1, 1])
	assert_eq(burst.map(func(p): return p.hit_index), [0, 1, 2])

func test_next_attack_increments_generation_without_instance_identity() -> void:
	var enemy := _configured_enemy(&"run7:room2:spawn4")
	assert_eq(enemy.begin_attack_for_test().attack_generation, 1)
	assert_eq(enemy.begin_attack_for_test().attack_generation, 2)
	assert_false(str(enemy.hostile_source_id).contains(str(enemy.get_instance_id())))

func _configured_enemy(source_id: StringName) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.configure_hostile_identity(source_id, 1)
	return enemy

func _spawn_shooter_burst(source_id: StringName, pellet_count: int) -> Array[Dictionary]:
	var shooter := EnemyShooter.new()
	shooter.configure_hostile_identity(source_id, 1)
	return shooter.projectile_identities_for_test(pellet_count)
```

Cover melee, Chaser, Shooter burst/projectile, Tank pulse, Time Crack tick, Chrono Warden melee/area/summon, reset, death, room transition, and Replay reconstruction. `attack_generation` increments only when a new attack plan, projectile launch, or zone tick commits; retries, every pellet in one burst, every target in one zone tick, and repeated collision from one projectile keep that committed generation.

- [ ] **Step 2: Write failing threat/presentation separation tests**

```gdscript
func test_accessibility_scale_does_not_change_gameplay_risk() -> void:
	var fact := _circle_fact(&"tank-a", 9, Vector2.ZERO, 96.0, 100, 154)
	assert_true(registry.publish(fact))
	var expected_visual_radius := {1.0: 96.0, 1.25: 120.0, 1.5: 144.0}
	for scale in [1.0, 1.25, 1.5]:
		telegraph.project_fact(fact)
		telegraph.set_accessibility_visual_scale(scale)
		assert_true(registry.contains_point(Vector2(95, 0), 120))
		assert_false(registry.contains_point(Vector2(97, 0), 120))
		assert_eq(telegraph.get_snapshot().visual_radius, expected_visual_radius[scale])

func test_summon_slots_remain_unscaled_domain_data() -> void:
	var fact := _circle_fact(&"warden-a", 4, Vector2.ZERO, 64.0, 200, 240)
	fact.summon_slots = [Vector2(-64, 0), Vector2(64, 0)]
	assert_true(registry.publish(fact))
	assert_eq(registry.fact_snapshot(&"warden-a", 4).summon_slots, fact.summon_slots)

func _circle_fact(
	source_id: StringName,
	generation: int,
	origin: Vector2,
	radius: float,
	from_frame: int,
	through_frame: int
) -> Dictionary:
	return {
		"hostile_source_id": source_id,
		"attack_generation": generation,
		"shape": "circle",
		"origin": origin,
		"aim_direction": Vector2.RIGHT,
		"target_point": origin,
		"summon_slots": [],
		"radius": radius,
		"length": 0.0,
		"active_from_frame": from_frame,
		"active_through_frame": through_frame,
	}
```

Cover circle, cone, line, and Rift-authorized geometry; inclusive `active_from_frame..active_through_frame` boundaries; duplicate source/generation rejection; retirement; stable nearest-hostile distance; visual scales `1.0`, `1.25`, and `1.5`; and absence of gameplay reads from `CombatTelegraph2D.get_snapshot()`.

- [ ] **Step 3: Run focused tests and confirm RED**

```bash
./tools/run_tests.sh --filter hostile_attack_identity
./tools/run_tests.sh --filter hostile_threat_registry
./tools/run_tests.sh --filter enemy_projectile
./tools/run_tests.sh --filter boss_telegraph
./tools/run_tests.sh --filter encounter_runner
```

Expected: FAIL because hostile producers default to token/generation zero and risk geometry currently lives in the scaled presentation node.

- [ ] **Step 4: Install deterministic source and attack identity**

`RoomController` derives `hostile_source_id` from encounter identity, room generation, spawn slot, and spawn ordinal. Summons derive a child ID from the parent source and deterministic summon sequence. `EnemyBase` owns a monotonic next-generation floor. Shooter copies one burst generation into its pellets and assigns `hit_index` by authored order; an independently launched projectile gets a new generation. Tank, Time Crack, and Chrono Warden reuse one generation across all targets of one pulse/tick, then allocate the next generation for the next tick. `get_instance_id()` remains allowed only for local signal bookkeeping, never serialized identity.

- [ ] **Step 5: Publish immutable hostile facts and project visuals**

`HostileTelegraphFact` contains exactly `hostile_source_id`, `attack_generation`, `shape`, `origin`, `aim_direction`, `target_point`, `summon_slots`, `radius`, `length`, `active_from_frame`, and `active_through_frame`. It validates unscaled geometry and the inclusive active range. `HostileThreatRegistry` is the only risk-query authority used by Void Walker. `CombatTelegraph2D.project_fact()` copies the fact and applies accessibility scaling only to drawn geometry. Clearing/cancelling the attack retires the matching fact.

- [ ] **Step 6: Run hostile, accessibility, Boss, and Replay gates**

```bash
./tools/run_tests.sh --filter hostile_attack_identity
./tools/run_tests.sh --filter hostile_threat_registry
./tools/run_tests.sh --filter enemy
./tools/run_tests.sh --filter boss_telegraph
./tools/run_tests.sh --filter chrono_warden
./tools/run_tests.sh --filter accessibility
./tools/run_tests.sh --filter replay
```

Expected: PASS with identical gameplay threat answers at all three visual scales.

- [ ] **Step 7: Commit**

```bash
git add -- scripts/combat/hostile_telegraph_fact.gd scripts/combat/hostile_threat_registry.gd scripts/combat/damage_info.gd scripts/fx/combat_telegraph_2d.gd scripts/enemies/enemy_base.gd scripts/enemies/enemy_chaser.gd scripts/enemies/enemy_shooter.gd scripts/enemies/enemy_projectile.gd scripts/enemies/enemy_tank.gd scripts/enemies/boss_time_crack.gd scripts/enemies/boss_chrono_warden.gd scripts/dungeon/room_controller.gd scripts/application/run_runtime_host.gd tests/combat/hostile_attack_identity_test.gd tests/combat/hostile_attack_identity_test.tscn tests/combat/hostile_threat_registry_test.gd tests/combat/hostile_threat_registry_test.tscn tests/combat/enemy_projectile_test.gd tests/combat/boss_telegraph_test.gd tests/unit/dungeon/encounter_runner_test.gd
git commit -m "feat(combat): add deterministic hostile threat authority"
```

### Task 3: P12C Wanderer and Time Guardian

**Files:**
- Create: `scripts/player/characters/wanderer_character_runtime.gd`
- Create: `scripts/player/characters/time_guardian_character_runtime.gd`
- Create: `scripts/combat/character_payload_execution.gd`
- Create: `tests/characters/character_payload_execution_test.gd`
- Create: `tests/characters/character_payload_execution_test.tscn`
- Create: `tests/characters/wanderer_character_runtime_test.gd`
- Create: `tests/characters/wanderer_character_runtime_test.tscn`
- Create: `tests/characters/time_guardian_character_runtime_test.gd`
- Create: `tests/characters/time_guardian_character_runtime_test.tscn`
- Modify: `scripts/combat/health_component.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/time_system/time_manager.gd`

**Interfaces:**
- Consumes: room facts, immutable `DamageResolution` defense decisions, mastery-family facts, semantic character skill, committed TimeAction facts, irreversible ledger state, and equipped time context.
- Produces: Path Marks/Waypoint Recall and Ward/Bulwark/Fortress with snapshot-safe payloads.

- [ ] **Step 1: Write Wanderer boundary tests**

Cover progress `0/1/2/3`, marks `0/1/5/6`, first mark per room, time-skill reservation, 180/240-frame windows, energy/heal caps, room-clear heal, anchor `479/480`, cooldown `719/720`, insufficient energy, death, reset, Rewind non-refund, and stale anchor callbacks. Assert the bounded forgiveness descriptors exactly: Sword next recovery `-4f` with minimum `1f`; Bow full threshold `48 -> 44`; Gun next perfect window `28..35 -> 26..37`; Staff combo window `+60f` capped at `360f`; Gauntlets combo timeout `+30f` capped at `150f`.

- [ ] **Step 2: Write Time Guardian boundary tests**

Cover guard frames `8/9/23/24`, perfect/normal/closed damage, the ordinary guard `240`-frame cooldown, Ward `0/1/3/4`, one `(hostile_source_id, attack_generation)` claim, 35% Ward reduction, 180-frame Rebuke, 30-frame longer-time-cooldown reduction, Fortress hold `29/30`, exact cost `3 Ward + 40 energy`, duration `180`, cooldown `600`, frontal cone `120 degrees`, movement multiplier `0.70`, damage reduction `0.50`, three-Ward mastery shockwave radius `192` and `1.0x ATK`, Stop conversion Boss exposure `+30f` once per Stop generation, transaction rollback, and multi-hit caps.

- [ ] **Step 3: Confirm RED**

```bash
./tools/run_tests.sh --filter wanderer_character
./tools/run_tests.sh --filter time_guardian_character
```

- [ ] **Step 4: Implement Path Mark and Waypoint Recall exactly**

Use source-owned anchor generation and `IrreversibleCharacterLedger`. The runtime returns decisions; PlayerController owns teleport/health application. Room and committed TimeAction facts carry run ID and revision so old-room callbacks fail closed. Rewind prepare freezes the anchor-return HP calculation and cannot refund the 30-energy placement cost or consumed marks.

- [ ] **Step 5: Implement Ward and Bulwark/Fortress exactly**

HealthComponent asks the active character runtime for a validated character-defense decision before finalizing `DamageResolution`. Perfect guard returns `prevented`; normal guard returns multiplier `0.50`; Ward and Fortress compose at most once in the declared stage. Self/terminal/unguardable tags bypass Ward. Rebuke and shockwave commit through `WorldPayloadAuthority` with non-recursive/no-mastery/no-resource tags.

- [ ] **Step 6: Run focused and adjacent regressions**

```bash
./tools/run_tests.sh --filter wanderer_character
./tools/run_tests.sh --filter time_guardian_character
./tools/run_tests.sh --filter health_component
./tools/run_tests.sh --filter rewind
./tools/run_tests.sh --filter time_loadout_runtime
./tools/run_tests.sh --filter sword_m1_parity
```

- [ ] **Step 7: Commit**

```bash
git add -- scripts/player/characters/wanderer_character_runtime.gd scripts/player/characters/time_guardian_character_runtime.gd scripts/combat/character_payload_execution.gd scripts/combat/health_component.gd scripts/player/player_controller.gd scripts/time_system/time_manager.gd tests/characters/character_payload_execution_test.gd tests/characters/character_payload_execution_test.tscn tests/characters/wanderer_character_runtime_test.gd tests/characters/wanderer_character_runtime_test.tscn tests/characters/time_guardian_character_runtime_test.gd tests/characters/time_guardian_character_runtime_test.tscn
git commit -m "feat(characters): add wanderer and time guardian"
```

### Task 4: P12D Void Walker and Primordial Knight

**Files:**
- Create: `scripts/player/characters/void_walker_character_runtime.gd`
- Create: `scripts/player/characters/primordial_knight_character_runtime.gd`
- Create: `scripts/combat/void_devour_execution.gd`
- Create: `scripts/combat/planar_echo_execution.gd`
- Create: `tests/characters/void_walker_character_runtime_test.gd`
- Create: `tests/characters/void_walker_character_runtime_test.tscn`
- Create: `tests/characters/primordial_knight_character_runtime_test.gd`
- Create: `tests/characters/primordial_knight_character_runtime_test.tscn`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/combat/health_component.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `scripts/combat/world_payload_authority.gd`

**Interfaces:**
- Consumes: applied `DamageResolution`, `HostileThreatRegistry` unscaled queries, mastery-family/commitment facts, immutable weapon payload descriptors, `IrreversibleCharacterLedger`, `WorldPayloadAuthority`, and committed TimeAction facts.
- Produces: Void Debt/Devour and Resonance/armor/planar echo/Realm Cleave.

- [ ] **Step 1: Write Void boundaries**

Cover debt `0/59/60/99/100/101`, two-HP corruption tick per 60 authoritative frames, risk distance `239/240/241`, authorized unscaled threat/Rift facts, conversion cap 20, debt-conversion echo radius `160` and damage `0.75x ATK`, heal cap six, Devour HP cost `max(10, 20% max HP)`, energy cost 25, terminal-payment rejection, windup `24`, active `1`, recovery `30`, cooldown `480`, `4.0x` character-attack damage, 15%-confirmed-damage healing capped at 12% max HP, one cooldown reset per cast, Rift conversion echo radius `224`, Rewind non-refund, and reset cleanup.

- [ ] **Step 2: Write Knight boundaries**

Cover Resonance `0/1/3/4`, one mastery-family claim per token/generation, commitment-tier rejection, three-stack reservation, action-windup armor reduction `0.35`, payload construction rollback, echo `0.75x` on the first frame after recovery, no recursion, world ownership through gameplay Rewind, Replay reconstruction, Rift echo area/length `x1.25` with unchanged damage, and Realm Cleave windup `36`, active `1`, recovery `30`, cooldown `540`, windup armor reduction `0.40`, cost 35 energy, damage `1.5x + 0.35x per consumed stack`, one `480`-frame instability claim per target/token, 20% approved-damage bonus, and Boss poise conversion.

- [ ] **Step 3: Confirm RED**

```bash
./tools/run_tests.sh --filter void_walker_character
./tools/run_tests.sh --filter primordial_knight_character
```

- [ ] **Step 4: Implement Void Debt and bounded Devour**

Store self-cost through `HealthComponent.lose_health_irreversible()` before applying damage. Risk predicates use only `HostileThreatRegistry` immutable geometry/generation or authorized Rift descriptors; they never read `CombatTelegraph2D`. Aggregate healing is finalized once after all target results and clamped to both cast and missing-HP caps.

- [ ] **Step 5: Implement Resonance and planar echo**

Copy only approved payload descriptors from the committed weapon plan. Echo and Realm Cleave payloads commit through `WorldPayloadAuthority`; they carry `character_echo`, original token, character generation, and no-mastery/no-resource tags. Gameplay Rewind preserves the committed echo and consumed Resonance; Replay checkpoint restore reconstructs it exactly.

- [ ] **Step 6: Run focused and weapon/Boss regressions**

```bash
./tools/run_tests.sh --filter void_walker_character
./tools/run_tests.sh --filter primordial_knight_character
./tools/run_tests.sh --filter character_payload
./tools/run_tests.sh --filter chrono_warden
./tools/run_tests.sh --filter replay
```

- [ ] **Step 7: Commit**

```bash
git add -- scripts/player/characters/void_walker_character_runtime.gd scripts/player/characters/primordial_knight_character_runtime.gd scripts/combat/void_devour_execution.gd scripts/combat/planar_echo_execution.gd scripts/player/player_controller.gd scripts/combat/health_component.gd scripts/time_system/time_manager.gd scripts/combat/world_payload_authority.gd tests/characters/void_walker_character_runtime_test.gd tests/characters/void_walker_character_runtime_test.tscn tests/characters/primordial_knight_character_runtime_test.gd tests/characters/primordial_knight_character_runtime_test.tscn
git commit -m "feat(characters): add void walker and primordial knight"
```

### Task 5: P12E Time Lord, exact pair conversions, and fifteen talents

**Files:**
- Create: `scripts/player/characters/time_lord_character_runtime.gd`
- Create: `scripts/player/characters/character_talent_state.gd`
- Modify: `data/content_packs/base/content/talents.json`
- Modify: `data/content_packs/base/pack.json`
- Modify: `data/localization/translations.csv`
- Modify: `data/content_packs/base/localization/translations.csv`
- Modify: `scripts/content/effects/effect_handler_catalog.gd`
- Modify: `scripts/items/item_effect.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `scripts/time_system/time_action_transaction.gd`
- Modify: `scripts/combat/world_payload_authority.gd`
- Create: `tests/characters/time_lord_character_runtime_test.gd`
- Create: `tests/characters/time_lord_character_runtime_test.tscn`
- Create: `tests/characters/character_talent_state_test.gd`
- Create: `tests/characters/character_talent_state_test.tscn`
- Modify: `tests/contract/content_schema/content_registry_test.gd`
- Modify: `tests/unit/items/item_effect_test.gd`
- Create: `tests/smoke/character_talent_subset_matrix_test.gd`
- Create: `tests/smoke/character_talent_subset_matrix_test.tscn`

**Interfaces:**
- Consumes: mastery-family facts, exactly two equipped time abilities, committed TimeAction facts, `WorldPayloadAuthority`, character-scoped talent definitions, and resource transactions.
- Produces: Codex Pages, Primer/pair conversion, Infusion/Dominion, and fifteen validated character talents.

- [ ] **Step 1: Write Codex and pair tests**

Cover Pages `0/1/3/4`, one Page per mastery family/token/generation/rate cap, Primer `299/300`, same-ability rejection, all six unordered pairs, one pair consumption, Infusion cost 10/cooldown 120 and `2.0x` next-mastery echo, Dominion hold `59/60`, exact cost `2 Pages + 60 energy`, enhanced-pair arm window `300`, cooldown `480`, Page/energy rollback, separate Staff Mana, Rewind non-refund, reset, and stale pair callbacks.

- [ ] **Step 2: Write talent content/runtime tests**

Assert exactly fifteen canonical Run Talents total: the fifteen identities and localization keys registered by Task 1 remain unchanged; Task 5 activates the three frozen M1 talents through Wanderer's Launch route and installs typed runtime modifiers for the twelve Launch identities. Verify exactly three per character, no cross-character activation, bounded values, mutually exclusive duplicates rejected, atomic application, snapshot/restore, and reset.

The executable talent-subset matrix is exactly:

```gdscript
const TALENTS := {
	&"wanderer": [&"tal_eternity_reserve", &"tal_ruin_execute", &"tal_steel_recover"],
	&"time_guardian": [&"widened_guard", &"fortress_core", &"temporal_rebuke"],
	&"void_walker": [&"deep_debt", &"bounded_devour", &"risk_step"],
	&"primordial_knight": [&"resonant_plate", &"echo_forge", &"realm_collapse"],
	&"time_lord": [&"codex_margin", &"efficient_inscription", &"dominion_cadence"],
}

func all_subsets(ids: Array[StringName]) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for mask in range(8):
		var subset := PackedStringArray()
		for bit in range(3):
			# Text mask columns map left-to-right to ids[0], ids[1], ids[2].
			if mask & (1 << (2 - bit)):
				subset.append(ids[bit])
		result.append(subset)
	return result
```

For each character the masks are `000`, `001`, `010`, `011`, `100`, `101`, `110`, and `111`: empty, each single, each pair, and all three. The test must execute `5 x 8 = 40` distinct configurations, verify canonical ID order, install/snapshot/Replay/reset, and reject every cross-character ID. It must not define a sixteenth talent.

- [ ] **Step 3: Confirm RED**

```bash
./tools/run_tests.sh --filter time_lord_character
./tools/run_tests.sh --filter character_talent_state
./tools/run_tests.sh --filter content_registry
```

- [ ] **Step 4: Implement six pair conversions with exact base/enhanced bounds**

Use a canonical unordered pair key. Each conversion delegates to typed TimeManager/WorldPayloadAuthority methods with source ID, generation, rollback, and these exact values:

| Pair | Base | Dominion-enhanced |
|---|---|---|
| Stop + Rewind | stasis zone radius `96px`, duration `90f`, hostile scalar `0.50` | `128px`, `150f`, `0.35` |
| Stop + Rift | hostile-projectile scalar `0.50`, cap `180f` | `0.35`, cap `240f` |
| Stop + Accelerate | recovery multiplier `0.80` for `90f` | `0.65` for `150f` |
| Rewind + Rift | one Rift-radius pulse at pre-return position, `1.25x ATK` | `1.75x ATK` |
| Rewind + Accelerate | next-mastery echo `0.75x ATK`, expiry `180f` | `1.10x ATK`, expiry `300f` |
| Rift + Accelerate | periodic-payload interval scalar `0.75`, cap `180f` | `0.50`, cap `240f` |

Stop durations, Rift total ticks/total damage, and enemy lock are never extended beyond the named bound. No pair handler may call an unselected third ability. Rewind pairs use the pre-return position frozen by TimeAction prepare.

- [ ] **Step 5: Activate fifteen talent handlers and capability routes**

Preserve the three current M1 talent IDs and behavior, extend them into Wanderer's Launch route through profile-scoped handlers, and attach typed bounded modifiers to the twelve Launch identities already registered by Task 1. Do not create a sixteenth identity or duplicate localization key. Update both localization catalogs only if final player-facing copy changes and refresh manifest hashes after any content edit. CharacterTalentState freezes talent modifiers at action/time commit. Time Dominion arms exactly one enhanced pair for 300 frames; it neither casts a pair at hold release nor grants an unselected ability.

- [ ] **Step 6: Run focused, content, time, item, and localization gates**

```bash
./tools/run_tests.sh --filter time_lord_character
./tools/run_tests.sh --filter character_talent_state
./tools/run_tests.sh --filter character_talent_subset_matrix
./tools/run_tests.sh --filter time_loadout_runtime
./tools/run_tests.sh --filter item_effect
./tools/run_tests.sh --filter content_registry
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
```

- [ ] **Step 7: Commit**

```bash
git add -- scripts/player/characters/time_lord_character_runtime.gd scripts/player/characters/character_talent_state.gd data/content_packs/base/content/talents.json data/content_packs/base/pack.json data/localization/translations.csv data/content_packs/base/localization/translations.csv scripts/content/effects/effect_handler_catalog.gd scripts/items/item_effect.gd scripts/time_system/time_manager.gd scripts/time_system/time_action_transaction.gd scripts/combat/world_payload_authority.gd tests/characters/time_lord_character_runtime_test.gd tests/characters/time_lord_character_runtime_test.tscn tests/characters/character_talent_state_test.gd tests/characters/character_talent_state_test.tscn tests/contract/content_schema/content_registry_test.gd tests/unit/items/item_effect_test.gd tests/smoke/character_talent_subset_matrix_test.gd tests/smoke/character_talent_subset_matrix_test.tscn
git commit -m "feat(characters): add time lord and character talents"
```

### Task 6: P12F Launch selector, character HUD, and presentation

**Files:**
- Create: `scripts/application/run_loadout_catalog.gd`
- Modify: `scripts/ui/launch_loadout_panel.gd`
- Modify: `scenes/ui/launch_loadout_panel.tscn`
- Modify: `scripts/main.gd`
- Modify: `scripts/ui/contracts/run_view_state.gd`
- Modify: `scripts/application/run_view_state_projector.gd`
- Modify: `scripts/ui/views/combat_hud_view.gd`
- Modify: `scenes/ui/combat_hud_v2.tscn`
- Modify: `scripts/presentation/pixel_proxy_actor.gd`
- Modify: `autoload/combat_feedback.gd`
- Modify: `tests/ui/launch_loadout_panel_test.gd`
- Modify: `tests/integration/ui/launch_loadout_flow_test.gd`
- Modify: `tests/integration/ui/controller_focus_flow_test.gd`
- Modify: `tests/ui/run_view_state_contract_test.gd`
- Modify: `tests/unit/application/run_view_state_projector_test.gd`
- Modify: `tests/ui/combat_hud_v2_scene_test.gd`
- Modify: `tests/presentation/combat_feedback_runtime_test.gd`

**Interfaces:**
- Consumes: immutable Registry-derived selector model and character presentation snapshots.
- Produces: stable-ID Character/Weapon/Time selectors, validated `character_state`, generic character HUD, and profile-driven proxy/feedback.

- [ ] **Step 1: Write failing 150-UI and character-state tests**

Loop all 150 selections and assert exact emitted IDs. Reject unknown character/meter/status, NaN/INF/negative values, invalid Primer, cooldown overflow, and legacy fields. Preserve selected IDs across Chinese/English refresh.

- [ ] **Step 2: Confirm RED**

```bash
./tools/run_tests.sh --filter launch_loadout_panel
./tools/run_tests.sh --filter run_view_state
./tools/run_tests.sh --filter combat_hud
./tools/run_tests.sh --filter controller_focus_flow
```

- [ ] **Step 3: Implement the compact three-selector model**

`RunLoadoutCatalog` returns ordered deep-copied entries with stable IDs, name/description keys, and legal time pairs. Replace the vertical label/control pairs with a two-column grid inside the existing 536×328 panel. Focus order is Character → Weapon → Time Pair → Start → Back.

- [ ] **Step 4: Add exact character-state union and HUD**

The schema contains only the fields in the specification. The HUD shows one meter/status/cooldown without internal IDs and rerenders cached state on locale change.

- [ ] **Step 5: Add five proxy visual profiles and cue budgets**

Use profile palette/silhouette/resource aura/skill cue. Every cue respects shake, flash, motion, subtitle, contrast, and volume settings. Rejected character skills show accessible rejection without success animation.

- [ ] **Step 6: Run UI, device, localization, and resolution gates**

```bash
./tools/run_tests.sh --filter launch_loadout
./tools/run_tests.sh --filter controller_focus_flow
./tools/run_tests.sh --filter run_view_state
./tools/run_tests.sh --filter combat_hud
./tools/run_tests.sh --filter combat_feedback
./tools/run_tests.sh --filter accessibility
```

Verify 640×360, 1280×720, 1920×1080, and ultrawide safe frames with real keyboard, mouse, and controller events.

- [ ] **Step 7: Commit**

```bash
git add -- scripts/application/run_loadout_catalog.gd scripts/ui/launch_loadout_panel.gd scenes/ui/launch_loadout_panel.tscn scripts/main.gd scripts/ui/contracts/run_view_state.gd scripts/application/run_view_state_projector.gd scripts/ui/views/combat_hud_view.gd scenes/ui/combat_hud_v2.tscn scripts/presentation/pixel_proxy_actor.gd autoload/combat_feedback.gd tests/ui/launch_loadout_panel_test.gd tests/ui/run_view_state_contract_test.gd tests/ui/combat_hud_v2_scene_test.gd tests/integration/ui/launch_loadout_flow_test.gd tests/integration/ui/controller_focus_flow_test.gd tests/unit/application/run_view_state_projector_test.gd tests/presentation/combat_feedback_runtime_test.gd
git commit -m "feat(ui): add five-character launch selection"
```

### Task 7: P12F character Replay and atomic external facts

**Files:**
- Modify: `scripts/replay/replay_recorder.gd`
- Modify: `scripts/replay/replay_player.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `scripts/time_system/time_action_transaction.gd`
- Modify: `scripts/combat/world_payload_authority.gd`
- Modify: `scripts/combat/hostile_threat_registry.gd`
- Modify: `scripts/player/characters/irreversible_character_ledger.gd`
- Create: `tests/replay/character_runtime_replay_test.gd`
- Create: `tests/replay/character_runtime_replay_test.tscn`
- Create: `tests/replay/character_external_fact_replay_test.gd`
- Create: `tests/replay/character_external_fact_replay_test.tscn`
- Modify: `tests/replay/weapon_restore_observable_atomicity_test.gd`

**Interfaces:**
- Consumes: character profile/coordinator/runtime snapshots, TimeManager including active Rift descriptors, TimeAction transition state, hostile threat facts, WorldPayloadAuthority Replay descriptors, irreversible ledger roots, and validated character fact transitions.
- Produces: Replay schema with character identity, all cross-domain authority roots, atomic restore, divergence rejection, and five-character round trip.

- [ ] **Step 1: Write failing five-character replay tests**

Keep `wanderer_m1_v1` on its certified P11/M1 Replay schema and digest. For each Launch character, use Player Replay schema 4 and record mastery family, character skill, committed TimeAction, DamageResolution/room facts, active Rift/threat/world payload, checkpoint restore, replay to terminal, and exact terminal digest. Reject profile mismatch, wrong token/generation/frame/run ID, forged irreversible ledger, malformed/no-op transitions, event-prefix drift, unstable hostile identity, and stale world payloads.

Add three explicit authority cases: gameplay Rewind preserves a committed planar echo/Rift and does not recreate a previously consumed payload; Replay checkpoint restore deletes the current payload generation and reconstructs the recorded descriptors exactly; reset/loadout replacement invalidates the generation so late payload callbacks are rejected.

- [ ] **Step 2: Confirm RED**

```bash
./tools/run_tests.sh --filter character_runtime_replay
./tools/run_tests.sh --filter character_external_fact_replay
```

- [ ] **Step 3: Extend snapshot and event schema**

The schema-4 event envelope has exactly `schema_version`, `frame`, `sequence`, `capture_sequence`, `run_id`, `content_snapshot_digest`, `character_profile_id`, `character_profile_version`, `event_type`, and `payload`. Add character coordinator/runtime/talent/presentation state, TimeManager full snapshot, TimeAction token/generation floor and committed facts, DamageResolution/irreversible claim roots, hostile threat root, and sorted WorldPayloadAuthority descriptor set. TimeManager fields include energy/revision, all four cooldowns, Stop, Accelerate, Rewind window, Rift source sequence, and complete active-Rift descriptors. Existing P11 weapon replays either remain on their certified schema or fail with a precise unsupported-version code; they never load partially.

- [ ] **Step 4: Validate record-time and playback-time transitions**

Use complete before/after digest and identity checks. Invalid recording attempts do not append, consume capture sequence, refresh baseline, or mutate live state. Validate every participant before replacing any state. Failed restore rolls every participant back to the exact prior snapshot; a documented safe reset is allowed only if rollback itself proves impossible, and the test must assert the resulting empty generations.

- [ ] **Step 5: Run Replay and adjacent regressions**

```bash
./tools/run_tests.sh --filter replay
./tools/run_tests.sh --filter character_runtime_replay
./tools/run_tests.sh --filter character_external_fact_replay
./tools/run_tests.sh --filter rewind
./tools/run_tests.sh --filter time_action_transaction
./tools/run_tests.sh --filter world_payload_authority
./tools/run_tests.sh --filter hostile_attack_identity
./tools/run_tests.sh --filter weapon_time_loadout_matrix
```

- [ ] **Step 6: Commit**

```bash
git add -- scripts/replay/replay_recorder.gd scripts/replay/replay_player.gd scripts/player/player_controller.gd scripts/time_system/time_manager.gd scripts/time_system/time_action_transaction.gd scripts/combat/world_payload_authority.gd scripts/combat/hostile_threat_registry.gd scripts/player/characters/irreversible_character_ledger.gd tests/replay/character_runtime_replay_test.gd tests/replay/character_runtime_replay_test.tscn tests/replay/character_external_fact_replay_test.gd tests/replay/character_external_fact_replay_test.tscn tests/replay/weapon_restore_observable_atomicity_test.gd
git commit -m "feat(replay): add deterministic character state"
```

### Task 8: P12G 150-loadout, 40-talent-subset, simulation, and certification

**Files:**
- Create: `tests/smoke/character_weapon_time_matrix_runner.gd`
- Create: `tests/smoke/wanderer_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/wanderer_loadout_matrix_smoke_test.tscn`
- Create: `tests/smoke/time_guardian_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/time_guardian_loadout_matrix_smoke_test.tscn`
- Create: `tests/smoke/void_walker_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/void_walker_loadout_matrix_smoke_test.tscn`
- Create: `tests/smoke/primordial_knight_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/primordial_knight_loadout_matrix_smoke_test.tscn`
- Create: `tests/smoke/time_lord_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/time_lord_loadout_matrix_smoke_test.tscn`
- Create: `tests/integration/characters/character_pairwise_integration_test.gd`
- Create: `tests/integration/characters/character_pairwise_integration_test.tscn`
- Create: `tools/run_character_weapon_simulation_matrix.py`
- Create: `tests/contract/playtest/test_character_weapon_simulation_report.py`
- Create: `docs/current/2026-09-30-p12-five-characters-evidence.md`
- Modify: `docs/README.md`
- Modify: this plan

**Interfaces:**
- Consumes: five certified Launch character profiles, five weapon profiles, six time pairs, all 40 legal character-talent subsets, 30 canonical seeds, Replay, UI, Boss/room contracts, and full repository validation.
- Produces: 150 deterministic runtime results, 40 talent-subset results, 30 pairwise heavy integrations, 4500 synthetic samples, final evidence, and Historical plan conversion.

- [ ] **Step 1: Write the exact matrix contracts**

Each character shard covers five weapons × six time pairs twice. Every case starts the real Player, advances only through `advance_action_frame(frame_intents)`, commits representative mastery-family, character skill, both time abilities, validates Character/Weapon ViewState, schema-4 Launch Replay, TimeManager/Rift and WorldPayload roots, resets twice, and compares pre-reset and clean-reset digests.

- [ ] **Step 2: Certify the exact 40-case talent-subset matrix**

Run the eight masks `000..111` for each of the five character talent triples defined in Task 5. Every case installs the real profile and one canonical Sword + Stop/Rewind loadout, commits the affected character loop, checks exact cost/cooldown/window/cap changes, performs Replay record/playback and checkpoint restore, resets, and proves canonical subset identity. Assert exactly 40 unique `(character_id, talent_ids)` rows, exactly 15 total definitions, and zero cross-character activations.

- [ ] **Step 3: Add the 30-case pairwise integration**

Use:

```gdscript
var weapon_index := (character_index + time_pair_index) % WEAPONS.size()
```

Assert the set covers all 25 character×weapon pairs, all 30 character×time-pair pairs, and all 30 weapon×time-pair pairs while executing room start/clear, Chrono Warden conversion, Replay checkpoint, and terminal cleanup.

- [ ] **Step 4: Add simulation report v2 and strict contract**

The CLI accepts only `--seeds 30`. Output contains five characters, five weapons, six pairs, 4500 samples, 150 loadouts, `talent_subset_cases: 40`, character/weapon/character×weapon/loadout summaries, exact character/weapon profile and active Content Pack digests, required P11 metrics, required P12 character metrics, and synthetic disclosure. It rejects ignored character profiles, noncanonical seeds, drifted summaries, NaN/INF, unknown fields, and human-evidence claims.

- [ ] **Step 5: Run focused matrix and reports twice**

```bash
./tools/run_tests.sh --filter loadout_matrix_smoke_test
./tools/run_tests.sh --filter character_talent_subset_matrix
./tools/run_tests.sh --filter character_pairwise_integration
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.playtest.test_character_weapon_simulation_report
PYTHONDONTWRITEBYTECODE=1 python3 tools/run_character_weapon_simulation_matrix.py --seeds 30 --output /tmp/planewalker-p12-sim-a.json
PYTHONDONTWRITEBYTECODE=1 python3 tools/run_character_weapon_simulation_matrix.py --seeds 30 --output /tmp/planewalker-p12-sim-b.json
```

Expected: both JSON files are byte-identical and contain `human_playtests: 0`.

- [ ] **Step 6: Run complete certification**

```bash
./tools/validate_project.sh
./tools/run_tests.sh --filter damage_resolution
./tools/run_tests.sh --filter rewind_transaction
./tools/run_tests.sh --filter time_manager_fixed_frame
./tools/run_tests.sh --filter time_action_transaction
./tools/run_tests.sh --filter hostile_attack_identity
./tools/run_tests.sh --filter hostile_threat_registry
./tools/run_tests.sh --filter world_payload_authority
./tools/run_tests.sh --filter character_talent_subset_matrix
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance tests.contract.localization.test_validate_localization tests.contract.playtest.test_character_weapon_simulation_report
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
git diff --check
```

Expected: all gates pass with only registered warnings; GDScript line coverage and real export boundaries remain honestly reported.

- [ ] **Step 7: Write evidence and mark this plan Historical**

Record implementation commits, commands, pass counts, report content/file digests, registered warnings, `0 / 20` human playtests, unsupported line coverage, and external export/signing/publication boundaries. Update Full Product status so the next active delivery step is eight archetype mechanics and the complete launch pools.

- [ ] **Step 8: Commit certification**

```bash
git add -- tests/smoke/character_weapon_time_matrix_runner.gd tests/smoke/wanderer_loadout_matrix_smoke_test.gd tests/smoke/wanderer_loadout_matrix_smoke_test.tscn tests/smoke/time_guardian_loadout_matrix_smoke_test.gd tests/smoke/time_guardian_loadout_matrix_smoke_test.tscn tests/smoke/void_walker_loadout_matrix_smoke_test.gd tests/smoke/void_walker_loadout_matrix_smoke_test.tscn tests/smoke/primordial_knight_loadout_matrix_smoke_test.gd tests/smoke/primordial_knight_loadout_matrix_smoke_test.tscn tests/smoke/time_lord_loadout_matrix_smoke_test.gd tests/smoke/time_lord_loadout_matrix_smoke_test.tscn tests/integration/characters/character_pairwise_integration_test.gd tests/integration/characters/character_pairwise_integration_test.tscn tools/run_character_weapon_simulation_matrix.py tests/contract/playtest/test_character_weapon_simulation_report.py docs/current/2026-09-30-p12-five-characters-evidence.md docs/README.md docs/superpowers/plans/2026-09-30-plane-walker-p12-five-characters.md
git commit -m "docs(characters): certify p12 five-character runtime"
```

## P12 Exit Gate

- [ ] Six character profiles resolve only at their allowed milestones.
- [ ] Six profiles match every exact base-stat, critical, Time, and Dash field; no runtime default fills an omitted value.
- [ ] M1/CURRENT/NEXT Wanderer parity remains unchanged.
- [ ] Five Launch characters have distinct stats, resource, skill, mastery, time conversions, three talents, HUD, feedback, controller, accessibility, snapshot, reset, replay, and cleanup.
- [ ] Live, Replay, and simulation share the 60 Hz frame pump; gameplay `_process(delta)` mutation is absent.
- [ ] DamageResolution, irreversible Rewind, TimeAction, hostile identity/threat, and WorldPayloadAuthority fault-injection suites pass with exact rollback.
- [ ] All five weapons use character attack scaling while Wanderer P11 values remain exact.
- [ ] Launch UI and Policy enumerate exactly 150 legal tuples.
- [ ] Mastery dedupe is exact by `(generation, action_token, canonical weapon family)` even when mastery IDs differ.
- [ ] Input schema `1 -> 2 -> 3`, real v2 recovery/collision fixtures, and Dash -> Time -> Character -> Weapon suppression/cancellation gates pass.
- [ ] Exactly fifteen talent definitions and all 40 character-talent subsets pass install, behavior, Replay, checkpoint, and reset gates.
- [ ] Twenty-five mastery, twenty ability, thirty pairwise, five runtime shards, schema-4 Launch Replay, and frozen M1 Replay gates pass.
- [ ] Two 4500-sample synthetic reports are byte-identical.
- [ ] Full repository validation is green with only registered warnings.
- [ ] Evidence remains local and does not change M1, human-playtest, line-coverage, export, signing, or publication status.
