extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const SwordWeaponRuntimeScript := preload("res://scripts/combat/weapons/sword_weapon_runtime.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const EXPECTED_M1_ACTIONS: Array[Dictionary] = [
	{"id": "light_1", "windup": 6, "active": 5, "recovery": 11, "cancel": 6, "multiplier": 0.8},
	{"id": "light_2", "windup": 8, "active": 5, "recovery": 12, "cancel": 6, "multiplier": 1.0},
	{"id": "light_3", "windup": 10, "active": 6, "recovery": 17, "cancel": 6, "multiplier": 1.3},
	{"id": "heavy", "windup": 21, "active": 8, "recovery": 27, "cancel": 15, "multiplier": 2.0},
]

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_character_stats_freeze_into_damage_payload()
	await _test_profile_snapshot_and_capabilities_are_isolated()
	await _test_parser_valid_m1_profile_drift_is_rejected()
	await _test_exact_m1_frame_table_and_combo_progression()
	await _test_attack_speed_preserves_legacy_fractional_tick_rounding()
	await _test_heavy_does_not_advance_light_combo()
	await _test_payload_adapter_preserves_damage_knockback_tags_and_reward_hooks()
	await _test_plan_and_commit_failures_are_atomic()
	await _test_restore_snapshot_requires_quiescent_state()
	await _test_snapshot_restore_cancel_and_reset()
	_suite.finish(get_tree())


func _test_character_stats_freeze_into_damage_payload() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var sword: Node = fixture["sword"]
	sword.base_attack = 27.0
	sword.attack_speed = 0.9
	sword.character_attack_scale = 0.9
	sword.crit_chance = 0.04
	sword.crit_multiplier = 1.6
	var plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
	var parameters := ((plan.get("payloads", []) as Array)[0] as Dictionary).get("parameters", {}) as Dictionary
	for source: Dictionary in [plan, parameters]:
		_suite.assert_close(float(source.get("character_attack_scale", 0.0)), 0.9, "Sword freezes character attack scale")
		_suite.assert_close(float(source.get("attack_speed", 0.0)), 0.9, "Sword freezes character attack speed")
		_suite.assert_close(float(source.get("crit_chance", -1.0)), 0.04, "Sword freezes character critical chance")
		_suite.assert_close(float(source.get("crit_multiplier", 0.0)), 1.6, "Sword freezes character critical multiplier")
	_suite.assert_true(bool(runtime.commit_action(plan, 90001).get("ok", false)), "Sword character-stat plan commits")
	sword.base_attack = 999.0
	sword.attack_speed = 4.0
	sword.character_attack_scale = 4.0
	sword.crit_chance = 1.0
	sword.crit_multiplier = 9.0
	runtime.on_phase_enter(plan, &"ACTIVE", 90001)
	var committed_definition := sword.get("_current_attack") as Dictionary
	_suite.assert_close(float(committed_definition.get("character_attack_scale", 0.0)), 0.9, "Sword committed definition freezes character attack scale")
	_suite.assert_close(float(committed_definition.get("crit_chance", -1.0)), 0.04, "Sword committed definition freezes critical chance")
	_suite.assert_close(float(committed_definition.get("crit_multiplier", 0.0)), 1.6, "Sword committed definition freezes critical multiplier")
	var damage_info: RefCounted = sword.hitbox.get("_active_damage_info")
	_suite.assert_true(damage_info != null, "Sword character-stat action creates a damage payload")
	if damage_info != null:
		_suite.assert_close(float(damage_info.amount), 21.6, "Sword damage keeps the frozen scaled attack")
	await _free_player(fixture["player"])


func _test_profile_snapshot_and_capabilities_are_isolated() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var profile: RefCounted = fixture["profile"]
	_suite.assert_equal(
		_sorted_strings(runtime.capabilities()),
		[
			"weapon.attack_speed",
			"weapon.charge_rate",
			"weapon.combo_finisher_damage",
			"weapon.damage",
			"weapon.heavy_damage",
			"weapon.heavy_execute_damage",
			"weapon.heavy_execute_threshold",
			"weapon.low_hp_damage",
		],
		"runtime exposes the configured profile capabilities"
	)

	var exposed_profile: Dictionary = profile.snapshot()
	(exposed_profile["actions"] as Array)[0]["windup_frames"] = 999
	(exposed_profile["payloads"] as Array)[0]["parameters"]["damage_multiplier"] = 99.0
	var planned: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {})
	_suite.assert_true(bool(planned.get("ok", false)), "primary plans from the retained profile snapshot")
	var plan: Dictionary = planned.get("plan", {})
	_suite.assert_equal(_phase(plan, 0).get("duration_frames"), 6, "caller profile mutation cannot change runtime timing")
	_suite.assert_close(
		float((plan.get("payloads", []) as Array)[0].get("parameters", {}).get("damage_multiplier", 0.0)),
		0.8,
		"caller profile mutation cannot change runtime payloads"
	)
	_suite.assert_equal(runtime.snapshot().get("profile_id"), "sword_m1_v1", "runtime snapshot retains profile identity")
	_suite.assert_equal(runtime.snapshot().get("profile_version"), 1, "runtime snapshot retains profile version")
	await _free_player(fixture["player"])


func _test_parser_valid_m1_profile_drift_is_rejected() -> void:
	var fixture := await _fixture()
	var player: Node = fixture["player"]
	var modifiers: RefCounted = fixture["modifiers"]
	var canonical := _profile_definition()
	var action_fields: Array[String] = [
		"windup_frames",
		"active_frames",
		"recovery_frames",
		"cancel_from_frame",
		"buffer_frames",
		"movement_multiplier",
	]
	for action_index: int in range((canonical["actions"] as Array).size()):
		for field: String in action_fields:
			var drift := canonical.duplicate(true)
			var actions: Array = drift["actions"]
			var action: Dictionary = actions[action_index]
			if field == "movement_multiplier":
				action[field] = float(action[field]) + 0.05
			else:
				action[field] = int(action[field]) + 1
			actions[action_index] = action
			drift["actions"] = actions
			_assert_profile_drift_rejected(
				player,
				modifiers,
				drift,
				"%s.%s" % [str(action.get("action_id", "")), field]
			)

	for payload_index: int in range((canonical["payloads"] as Array).size()):
		for field: String in ["damage_multiplier", "knockback", "tags"]:
			var drift := canonical.duplicate(true)
			var payloads: Array = drift["payloads"]
			var payload: Dictionary = payloads[payload_index]
			var parameters: Dictionary = payload["parameters"]
			if field == "tags":
				var tags: Array = (parameters["tags"] as Array).duplicate()
				tags.append("drift:test")
				parameters[field] = tags
			else:
				parameters[field] = float(parameters[field]) + 0.1
			payload["parameters"] = parameters
			payloads[payload_index] = payload
			drift["payloads"] = payloads
			_assert_profile_drift_rejected(
				player,
				modifiers,
				drift,
				"%s.%s" % [str(payload.get("payload_id", "")), field]
			)

	for action_index: int in range((canonical["actions"] as Array).size()):
		var drift := canonical.duplicate(true)
		var actions: Array = drift["actions"]
		var action: Dictionary = actions[action_index]
		var next_action: Dictionary = actions[(action_index + 1) % actions.size()]
		action["cue_id"] = next_action["cue_id"]
		actions[action_index] = action
		drift["actions"] = actions
		_assert_profile_drift_rejected(
			player,
			modifiers,
			drift,
			"%s.cue_id" % str(action.get("action_id", ""))
		)

	for cue_index: int in range((canonical["cues"] as Array).size()):
		for field: String in ["animation_id", "vfx_id", "audio_id", "camera_id"]:
			var drift := canonical.duplicate(true)
			var cues: Array = drift["cues"]
			var cue: Dictionary = cues[cue_index]
			cue[field] = "%s_drift" % str(cue[field])
			cues[cue_index] = cue
			drift["cues"] = cues
			_assert_profile_drift_rejected(
				player,
				modifiers,
				drift,
				"%s.%s" % [str(cue.get("cue_id", "")), field]
			)
	await _free_player(player)


func _test_exact_m1_frame_table_and_combo_progression() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var light_step := 0
	for expected: Dictionary in EXPECTED_M1_ACTIONS.slice(0, 3):
		var planned: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {})
		_suite.assert_true(bool(planned.get("ok", false)), "%s plans" % expected["id"])
		var plan: Dictionary = planned.get("plan", {})
		_assert_plan(plan, expected)
		var token := 100 + light_step
		_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "%s commits" % expected["id"])
		_suite.assert_equal(runtime.snapshot().get("combo_step"), (light_step + 1) % 3, "%s advances combo exactly once" % expected["id"])
		var windup_events: Array = runtime.on_phase_enter(plan, &"WINDUP", token)
		_suite.assert_true(windup_events.is_empty(), "%s windup releases no payload" % expected["id"])
		var active_events: Array = runtime.on_phase_enter(plan, &"ACTIVE", token)
		_suite.assert_equal(active_events.size(), 2, "%s active releases one payload and one cue" % expected["id"])
		runtime.on_phase_enter(plan, &"RECOVERY", token)
		runtime.finish_action(token)
		light_step += 1

	var wrapped: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
	_suite.assert_equal(wrapped.get("action_id"), "light_1", "three committed lights wrap to the opener")
	runtime.reset_combo()
	var reset_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
	_suite.assert_equal(reset_plan.get("action_id"), "light_1", "explicit combo reset restores the opener")
	_suite.assert_equal(reset_plan.get("combo_reset_frames"), 48, "M1 combo timeout remains forty-eight frames")
	await _free_player(fixture["player"])


func _test_heavy_does_not_advance_light_combo() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var heavy_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_secondary"), {}).get("plan", {})
	_assert_plan(heavy_plan, EXPECTED_M1_ACTIONS[3])
	_suite.assert_true(bool(runtime.commit_action(heavy_plan, 201).get("ok", false)), "heavy commits")
	runtime.on_phase_enter(heavy_plan, &"ACTIVE", 201)
	runtime.on_phase_enter(heavy_plan, &"RECOVERY", 201)
	runtime.finish_action(201)
	_suite.assert_equal(runtime.snapshot().get("combo_step"), 0, "heavy does not advance the light combo")
	_suite.assert_equal(
		runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {}).get("action_id"),
		"light_1",
		"light combo still begins at the opener after heavy"
	)
	await _free_player(fixture["player"])


func _test_attack_speed_preserves_legacy_fractional_tick_rounding() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var sword: Node = fixture["sword"]
	sword.attack_speed = 1.2
	for step: int in range(3):
		var legacy: Dictionary = sword.attack_definition(false)
		var plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
		_suite.assert_equal(_phase(plan, 0).get("duration_frames"), legacy["windup_frames"], "light %d preserves legacy accelerated windup rounding" % (step + 1))
		_suite.assert_equal(_phase(plan, 1).get("duration_frames"), legacy["active_frames"], "light %d preserves legacy accelerated active rounding" % (step + 1))
		_suite.assert_equal(_phase(plan, 2).get("duration_frames"), legacy["recovery_frames"], "light %d preserves legacy accelerated recovery rounding" % (step + 1))
		_suite.assert_equal(_phase(plan, 2).get("cancel_from_frame"), legacy["recovery_cancel_frame"], "light %d preserves legacy accelerated cancel rounding" % (step + 1))
		runtime.commit_action(plan, 220 + step)
		runtime.finish_action(220 + step)

	var legacy_heavy: Dictionary = sword.attack_definition(true)
	var heavy_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_secondary"), {}).get("plan", {})
	_suite.assert_equal(_phase(heavy_plan, 0).get("duration_frames"), legacy_heavy["windup_frames"], "heavy preserves legacy accelerated windup rounding")
	_suite.assert_equal(_phase(heavy_plan, 1).get("duration_frames"), legacy_heavy["active_frames"], "heavy preserves legacy accelerated active rounding")
	_suite.assert_equal(_phase(heavy_plan, 2).get("duration_frames"), legacy_heavy["recovery_frames"], "heavy preserves legacy accelerated recovery rounding")
	_suite.assert_equal(_phase(heavy_plan, 2).get("cancel_from_frame"), legacy_heavy["recovery_cancel_frame"], "heavy preserves legacy accelerated cancel rounding")
	await _free_player(fixture["player"])


func _test_payload_adapter_preserves_damage_knockback_tags_and_reward_hooks() -> void:
	var fixture := await _fixture()
	var player: Node = fixture["player"]
	var sword: Node = fixture["sword"]
	var runtime: RefCounted = fixture["runtime"]
	player.health.current_hp = player.health.max_hp * 0.25
	_suite.assert_true(runtime.apply_modifier(&"weapon.combo_finisher_damage", 0.35), "finisher reward routes through its capability")
	_suite.assert_true(runtime.apply_modifier(&"weapon.heavy_damage", 0.40), "heavy reward routes through its capability")
	_suite.assert_true(runtime.apply_modifier(&"weapon.heavy_execute_damage", 0.50), "execute reward routes through its capability")
	_suite.assert_true(runtime.apply_modifier(&"weapon.heavy_execute_threshold", 0.30), "execute threshold routes through its capability")
	_suite.assert_true(runtime.apply_modifier(&"weapon.low_hp_damage", 0.45), "low-HP reward routes through its capability")
	_suite.assert_true(runtime.apply_modifier(&"weapon.damage", 1.5), "runtime accepts a declared damage capability")
	_suite.assert_true(not runtime.apply_modifier(&"weapon.ammo_capacity", 2.0), "runtime rejects an undeclared modifier capability")

	for token: int in [301, 302]:
		var setup_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
		runtime.commit_action(setup_plan, token)
		runtime.on_phase_enter(setup_plan, &"ACTIVE", token)
		runtime.on_phase_enter(setup_plan, &"RECOVERY", token)
		runtime.finish_action(token)

	var finisher_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
	_suite.assert_true(runtime.apply_modifier(&"weapon.damage", 2.0), "live modifier changes after finisher plan freeze")
	_suite.assert_true(bool(runtime.commit_action(finisher_plan, 303).get("ok", false)), "finisher commits")
	sword.set("_current_attack", {
		"heavy": false,
		"finisher": false,
		"multiplier": 99.0,
		"knockback": 999.0,
		"tags": ["forged:adapter"],
	})
	runtime.on_phase_enter(finisher_plan, &"ACTIVE", 303)
	var finisher_damage: RefCounted = sword.hitbox.get("_active_damage_info")
	_suite.assert_close(
		float(finisher_damage.amount),
		30.0 * 1.5 * 1.3 * 1.35 * 1.45,
		"finisher uses frozen generic damage plus legacy finisher and low-hp hooks"
	)
	_suite.assert_close(finisher_damage.knockback.length(), 120.0, "finisher preserves light knockback")
	_suite.assert_true(finisher_damage.tags.has("weapon:sword"), "finisher preserves sword tag")
	_suite.assert_true(finisher_damage.tags.has("attack:finisher"), "finisher preserves finisher tag")
	runtime.on_phase_enter(finisher_plan, &"RECOVERY", 303)
	runtime.finish_action(303)

	var heavy_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_secondary"), {}).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(heavy_plan, 304).get("ok", false)), "rewarded heavy commits")
	runtime.on_phase_enter(heavy_plan, &"ACTIVE", 304)
	var heavy_damage: RefCounted = sword.hitbox.get("_active_damage_info")
	_suite.assert_close(
		float(heavy_damage.amount),
		30.0 * 2.0 * 2.0 * 1.40 * 1.45,
		"heavy uses its frozen modifier and preserves heavy plus low-hp hooks"
	)
	_suite.assert_close(heavy_damage.knockback.length(), 260.0, "heavy preserves knockback")
	_suite.assert_true(heavy_damage.tags.has("weapon:sword"), "heavy preserves sword tag")
	_suite.assert_true(heavy_damage.tags.has("attack:heavy"), "heavy preserves heavy tag")
	_suite.assert_true(heavy_damage.tags.has("talent:ruin_execute"), "heavy preserves execute reward tag")
	_suite.assert_equal(heavy_damage.source, sword, "existing SwordWeapon remains the damage payload source")
	runtime.on_phase_enter(heavy_plan, &"RECOVERY", 304)
	runtime.finish_action(304)
	await _free_player(player)


func _test_plan_and_commit_failures_are_atomic() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var sword: Node = fixture["sword"]
	var before: Dictionary = runtime.snapshot()
	var rejected: Dictionary = runtime.plan_intent(_intent(&"weapon_utility"), {})
	_suite.assert_true(not bool(rejected.get("ok", false)), "unsupported utility plan is rejected")
	_suite.assert_equal(runtime.snapshot(), before, "plan rejection is read-only")

	var plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
	_suite.assert_true(not bool(runtime.commit_action(plan, 0).get("ok", false)), "non-positive token is rejected")
	_suite.assert_equal(runtime.snapshot(), before, "invalid token does not change runtime")

	_suite.assert_true(not sword.begin_attack(false).is_empty(), "dirty adapter begins an external action")
	var dirty_before: Dictionary = runtime.snapshot()
	_suite.assert_true(not bool(runtime.commit_action(plan, 401).get("ok", false)), "busy adapter rejects runtime commit")
	_suite.assert_equal(runtime.snapshot(), dirty_before, "busy adapter rejection does not advance runtime combo or token")
	sword.cancel_attack()
	sword.reset_combo()

	var forged_plan := plan.duplicate(true)
	forged_plan["action_id"] = "light_3"
	_suite.assert_true(not bool(runtime.commit_action(forged_plan, 402).get("ok", false)), "stale or forged combo plan is rejected")
	_suite.assert_equal(runtime.snapshot(), before, "forged plan rejection remains atomic")

	var forged_base_attack := plan.duplicate(true)
	forged_base_attack["base_attack_snapshot"] = 999.0
	_suite.assert_true(
		not bool(runtime.commit_action(forged_base_attack, 403).get("ok", false)),
		"forged M1 base attack snapshot is rejected"
	)
	_suite.assert_equal(runtime.snapshot(), before, "forged base attack rejection remains atomic")

	var forged_root_stats := plan.duplicate(true)
	forged_root_stats["crit_multiplier"] = 9.0
	_suite.assert_true(
		not bool(runtime.commit_action(forged_root_stats, 404).get("ok", false)),
		"forged M1 root character stats are rejected"
	)
	_suite.assert_equal(runtime.snapshot(), before, "forged root stats rejection remains atomic")

	var forged_payload := plan.duplicate(true)
	((forged_payload["payloads"] as Array)[0]["parameters"] as Dictionary)["damage_multiplier"] = 99.0
	_suite.assert_true(
		not bool(runtime.commit_action(forged_payload, 405).get("ok", false)),
		"forged M1 payload definition is rejected"
	)
	_suite.assert_equal(runtime.snapshot(), before, "forged payload rejection remains atomic")

	var forged_character_snapshot := plan.duplicate(true)
	(forged_character_snapshot["character_stats_snapshot"] as Dictionary)["attack_speed"] = 4.0
	forged_character_snapshot["attack_speed"] = 4.0
	((forged_character_snapshot["payloads"] as Array)[0]["parameters"] as Dictionary)["attack_speed"] = 4.0
	_suite.assert_true(
		not bool(runtime.commit_action(forged_character_snapshot, 406).get("ok", false)),
		"forged M1 character snapshot is rejected even when mirrored into the payload"
	)
	_suite.assert_equal(runtime.snapshot(), before, "forged character snapshot rejection remains atomic")
	await _free_player(fixture["player"])


func _test_restore_snapshot_requires_quiescent_state() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var sword: Node = fixture["sword"]
	var first: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
	runtime.commit_action(first, 451)
	runtime.finish_action(451)
	var safe_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_equal(safe_snapshot.get("combo_step"), 1, "safe snapshot retains committed combo progress")

	var unsafe_snapshots: Array[Dictionary] = []
	var with_token := safe_snapshot.duplicate(true)
	with_token["active_token"] = 9
	unsafe_snapshots.append({"name": "active token", "snapshot": with_token})
	var with_phase := safe_snapshot.duplicate(true)
	with_phase["active_phase"] = "WINDUP"
	unsafe_snapshots.append({"name": "non-ready phase", "snapshot": with_phase})
	var with_plan := safe_snapshot.duplicate(true)
	with_plan["active_plan"] = {"action_id": "light_1"}
	unsafe_snapshots.append({"name": "active plan", "snapshot": with_plan})
	var with_modifiers := safe_snapshot.duplicate(true)
	with_modifiers["modifier_snapshot"] = {"weapon.damage": 1.0}
	unsafe_snapshots.append({"name": "active modifier snapshot", "snapshot": with_modifiers})
	var with_active_adapter := safe_snapshot.duplicate(true)
	(with_active_adapter["adapter"] as Dictionary)["active"] = true
	unsafe_snapshots.append({"name": "active adapter", "snapshot": with_active_adapter})
	var with_attacking_adapter := safe_snapshot.duplicate(true)
	(with_attacking_adapter["adapter"] as Dictionary)["attacking"] = true
	unsafe_snapshots.append({"name": "attacking adapter", "snapshot": with_attacking_adapter})
	var with_current_attack := safe_snapshot.duplicate(true)
	(with_current_attack["adapter"] as Dictionary)["current_attack"] = {"heavy": false}
	unsafe_snapshots.append({"name": "adapter current attack", "snapshot": with_current_attack})
	var with_mismatched_combo := safe_snapshot.duplicate(true)
	(with_mismatched_combo["adapter"] as Dictionary)["combo_index"] = 2
	unsafe_snapshots.append({"name": "adapter combo mismatch", "snapshot": with_mismatched_combo})

	for unsafe_case: Dictionary in unsafe_snapshots:
		runtime.reset_runtime_state(&"restore_test_reset")
		_suite.assert_true(runtime.restore_snapshot(safe_snapshot), "safe baseline restores before rejection case")
		var before: Dictionary = runtime.snapshot()
		_suite.assert_true(
			not runtime.restore_snapshot(unsafe_case["snapshot"]),
			"restore rejects %s" % unsafe_case["name"]
		)
		_suite.assert_equal(runtime.snapshot(), before, "rejected %s snapshot is atomic" % unsafe_case["name"])
		_suite.assert_true(not sword.is_attacking(), "rejected %s snapshot leaves adapter idle" % unsafe_case["name"])
		_suite.assert_true(not sword.hitbox.is_active(), "rejected %s snapshot leaves hitbox closed" % unsafe_case["name"])

	runtime.reset_runtime_state(&"restore_test_final")
	_suite.assert_true(runtime.restore_snapshot(safe_snapshot), "quiescent snapshot remains accepted")
	_suite.assert_equal(runtime.snapshot().get("combo_step"), 1, "quiescent restore preserves combo progression")
	_suite.assert_equal(int(sword.get("_combo_index")), 1, "adapter combo index follows restored runtime combo")
	await _free_player(fixture["player"])


func _test_snapshot_restore_cancel_and_reset() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var sword: Node = fixture["sword"]
	var first: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
	runtime.commit_action(first, 501)
	runtime.on_phase_enter(first, &"ACTIVE", 501)
	runtime.on_phase_enter(first, &"RECOVERY", 501)
	runtime.finish_action(501)
	var saved: Dictionary = runtime.snapshot()
	(saved["modifier_snapshot"] as Dictionary)["weapon.damage"] = 99.0
	_suite.assert_true(not runtime.snapshot().get("modifier_snapshot", {}).has("weapon.damage"), "returned snapshot is isolated")

	var second: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
	runtime.commit_action(second, 502)
	runtime.on_phase_enter(second, &"ACTIVE", 502)
	runtime.on_phase_enter(second, &"RECOVERY", 502)
	runtime.finish_action(502)
	_suite.assert_equal(runtime.snapshot().get("combo_step"), 2, "fixture advances beyond saved combo state")

	var safe_saved := saved.duplicate(true)
	(safe_saved["modifier_snapshot"] as Dictionary).clear()
	_suite.assert_true(runtime.restore_snapshot(safe_saved), "safe runtime snapshot restores")
	_suite.assert_equal(runtime.snapshot().get("combo_step"), 1, "restore recovers combo step")
	_suite.assert_equal(
		runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {}).get("action_id"),
		"light_2",
		"restored adapter and runtime agree on the next combo action"
	)

	var restored_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary"), {}).get("plan", {})
	runtime.commit_action(restored_plan, 503)
	runtime.on_phase_enter(restored_plan, &"ACTIVE", 503)
	_suite.assert_true(sword.hitbox.is_active(), "active payload is open before cancellation")
	runtime.cancel_action(999, &"stale")
	_suite.assert_true(sword.hitbox.is_active(), "stale token cannot cancel the payload")
	runtime.cancel_action(503, &"matching")
	_suite.assert_true(not sword.hitbox.is_active(), "matching token cancels the payload")
	_suite.assert_equal(runtime.snapshot().get("combo_step"), 2, "ordinary cancellation preserves committed combo progression")

	runtime.reset_runtime_state(&"new_run")
	_suite.assert_equal(runtime.snapshot().get("combo_step"), 0, "new-run reset clears combo")
	_suite.assert_equal(runtime.snapshot().get("active_token"), 0, "new-run reset clears active token")
	_suite.assert_true(not sword.is_attacking(), "new-run reset clears adapter attack state")
	_suite.assert_true(not sword.hitbox.is_active(), "new-run reset closes adapter hitbox")
	await _free_player(fixture["player"])


func _fixture() -> Dictionary:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var profile = WeaponRuntimeProfileScript.new()
	var profile_result: Dictionary = profile.configure(_profile_definition())
	_suite.assert_true(bool(profile_result.get("ok", false)), "authoritative sword_m1_v1 profile configures")
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(
			PackedStringArray([
				"weapon.attack_speed",
				"weapon.charge_rate",
				"weapon.combo_finisher_damage",
				"weapon.damage",
				"weapon.heavy_damage",
				"weapon.heavy_execute_damage",
				"weapon.heavy_execute_threshold",
				"weapon.low_hp_damage",
			]),
			{
				"weapon.attack_speed": {"minimum": 0.2, "maximum": 5.0},
				"weapon.charge_rate": {"minimum": 0.0, "maximum": 6.0},
				"weapon.combo_finisher_damage": {"minimum": 0.0, "maximum": 10.0},
				"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
				"weapon.heavy_damage": {"minimum": 0.0, "maximum": 10.0},
				"weapon.heavy_execute_damage": {"minimum": 0.0, "maximum": 10.0},
				"weapon.heavy_execute_threshold": {"minimum": 0.0, "maximum": 1.0},
				"weapon.low_hp_damage": {"minimum": 0.0, "maximum": 10.0},
			}
		),
		"Sword modifier state configures from profile capabilities"
	)
	var runtime = SwordWeaponRuntimeScript.new()
	_suite.assert_true(
		runtime.bind_adapter(player.get_node("SwordWeapon")),
		"Sword runtime accepts the explicit real payload adapter"
	)
	_suite.assert_true(runtime.configure(player, profile, modifiers), "Sword runtime configures with real payload adapter")
	return {
		"player": player,
		"sword": player.get_node("SwordWeapon"),
		"profile": profile,
		"modifiers": modifiers,
		"runtime": runtime,
	}


func _profile_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == "sword_m1_v1":
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _assert_profile_drift_rejected(
	player: Node,
	modifiers: RefCounted,
	definition: Dictionary,
	label: String
) -> void:
	var profile = WeaponRuntimeProfileScript.new()
	var profile_result: Dictionary = profile.configure(definition)
	_suite.assert_true(
		bool(profile_result.get("ok", false)),
		"%s drift remains parser-valid" % label
	)
	if not bool(profile_result.get("ok", false)):
		return
	var runtime = SwordWeaponRuntimeScript.new()
	_suite.assert_true(
		runtime.bind_adapter(player.get_node("SwordWeapon")),
		"drift fixture binds the payload adapter explicitly"
	)
	_suite.assert_true(
		not runtime.configure(player, profile, modifiers),
		"Sword runtime rejects parser-valid %s drift" % label
	)
	_suite.assert_true(
		not bool(runtime.snapshot().get("configured", false)),
		"rejected %s drift never activates the runtime" % label
	)


func _intent(intent_id: StringName) -> Dictionary:
	return {"id": str(intent_id), "edge": "pressed"}


func _assert_plan(plan: Dictionary, expected: Dictionary) -> void:
	_suite.assert_equal(plan.get("action_id"), expected["id"], "%s action id matches" % expected["id"])
	_suite.assert_equal(_phase(plan, 0).get("phase"), "WINDUP", "%s begins with windup" % expected["id"])
	_suite.assert_equal(_phase(plan, 0).get("duration_frames"), expected["windup"], "%s windup frames match" % expected["id"])
	_suite.assert_equal(_phase(plan, 1).get("phase"), "ACTIVE", "%s has active phase" % expected["id"])
	_suite.assert_equal(_phase(plan, 1).get("duration_frames"), expected["active"], "%s active frames match" % expected["id"])
	_suite.assert_equal(_phase(plan, 2).get("phase"), "RECOVERY", "%s has recovery phase" % expected["id"])
	_suite.assert_equal(_phase(plan, 2).get("duration_frames"), expected["recovery"], "%s recovery frames match" % expected["id"])
	_suite.assert_equal(_phase(plan, 2).get("cancel_from_frame"), expected["cancel"], "%s cancel boundary matches" % expected["id"])
	_suite.assert_close(float(_phase(plan, 0).get("movement_multiplier", 0.0)), float(expected["movement"] if expected.has("movement") else (0.2 if expected["id"] == "heavy" else 0.55)), "%s movement multiplier matches" % expected["id"])
	_suite.assert_close(
		float((plan.get("payloads", []) as Array)[0].get("parameters", {}).get("damage_multiplier", 0.0)),
		float(expected["multiplier"]),
		"%s damage multiplier matches" % expected["id"]
	)


func _phase(plan: Dictionary, index: int) -> Dictionary:
	var phases_value: Variant = plan.get("phases", [])
	if not phases_value is Array or index < 0 or index >= (phases_value as Array).size():
		return {}
	var phase_value: Variant = (phases_value as Array)[index]
	return (phase_value as Dictionary).duplicate(true) if phase_value is Dictionary else {}


func _sorted_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _free_player(player: Node) -> void:
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
