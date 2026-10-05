class_name SwordWeapon
extends Node2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const Targets := preload("res://scripts/combat/weapon_target_policy.gd")
const WEAPON_ID := &"sword"
const MAX_COMMITTED_GUARD_RESOLUTION_IDS := 512
const MAX_RESOLUTION_ID_LENGTH := 96

@export var owner_path: NodePath
@export var base_attack: float = 30.0
@export var attack_speed: float = 1.0
@export var character_attack_scale: float = 1.0
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 1.5

@onready var hitbox: Node = $Hitbox
@onready var owner_player: Node = get_node(owner_path)

var combo_finisher_multiplier_bonus: float = 0.0
var heavy_damage_multiplier_bonus: float = 0.0
var heavy_execute_multiplier_bonus: float = 0.0
var heavy_execute_threshold: float = 0.3
var low_hp_damage_multiplier_bonus: float = 0.0
var low_hp_threshold: float = 0.35
var _combo_index: int = 0
var _attacking: bool = false
var _active: bool = false
var _current_attack: Dictionary = {}
var _guard_active: bool = false
var _guard_elapsed_frames: int = 0
var _guard_parameters: Dictionary = {}
var _last_guard_result: Dictionary = {}
var _launch_effect_events: Array[Dictionary] = []
var _launch_payloads: Array[Dictionary] = []
var _next_launch_payload_id: int = 1
var _guard_generation: int = 0
var _guard_commit_epoch: int = 0
var _committed_guard_resolution_ids: Dictionary = {}
var _next_fallback_attack_generation: int = 1
var _active_damage_attack_generation: int = 0
var _active_damage_action_token: int = 0

const LIGHT_COMBO: Array[Dictionary] = [
	{"multiplier": 0.8, "windup": 0.10, "active": 0.08, "recovery": 0.18, "finisher": false},
	{"multiplier": 1.0, "windup": 0.12, "active": 0.08, "recovery": 0.20, "finisher": false},
	{"multiplier": 1.3, "windup": 0.16, "active": 0.10, "recovery": 0.28, "finisher": true},
]


func _exit_tree() -> void:
	_clear_launch_payloads()


func weapon_id() -> StringName:
	return WEAPON_ID


func reset_runtime_state() -> void:
	cancel_attack()
	reset_combo()
	_last_guard_result.clear()
	_launch_effect_events.clear()
	_guard_generation = 0
	_guard_commit_epoch += 1
	_committed_guard_resolution_ids.clear()
	_next_fallback_attack_generation = 1
	_clear_launch_payloads()


func attack_definition(heavy: bool = false) -> Dictionary:
	var data: Dictionary
	if heavy:
		data = {"multiplier": 2.0, "windup": 0.35, "active": 0.12, "recovery": 0.45, "finisher": false}
	else:
		data = LIGHT_COMBO[_combo_index]
	return {
		"heavy": heavy,
		"finisher": bool(data["finisher"]),
		"multiplier": float(data["multiplier"]),
		"knockback": 260.0 if heavy else 120.0,
		"tags": ["attack:heavy", "weapon:sword"] if heavy else (
			["attack:finisher", "weapon:sword"]
			if bool(data["finisher"])
			else ["weapon:sword"]
		),
		"windup_frames": _seconds_to_frames(float(data["windup"])),
		"active_frames": _seconds_to_frames(float(data["active"])),
		"recovery_frames": _seconds_to_frames(float(data["recovery"])),
		"recovery_cancel_frame": _seconds_to_frames(0.24 if heavy else 0.10),
		"movement_multiplier": 0.2 if heavy else 0.55,
		"combo_reset_frames": maxi(1, ceili(0.8 * Engine.physics_ticks_per_second)),
		"character_attack_scale": character_attack_scale,
		"attack_speed": attack_speed,
		"crit_chance": crit_chance,
		"crit_multiplier": crit_multiplier,
	}


func begin_attack(heavy: bool = false) -> Dictionary:
	return begin_profile_attack(attack_definition(heavy))


func begin_profile_attack(definition: Dictionary) -> Dictionary:
	if _attacking or not _valid_profile_attack(definition):
		return {}
	_current_attack = definition.duplicate(true)
	_attacking = true
	_active = false
	if not bool(_current_attack["heavy"]) and bool(_current_attack.get("advance_combo", true)):
		_combo_index = (_combo_index + 1) % LIGHT_COMBO.size()
	return _current_attack.duplicate(true)


func is_attacking() -> bool:
	return _attacking


func enter_active_phase() -> bool:
	return enter_profile_active_phase(_current_attack)


func enter_profile_active_phase(definition: Dictionary) -> bool:
	if not _attacking or _active or not _valid_profile_attack(definition):
		return false
	_current_attack = definition.duplicate(true)
	_active = true
	var payload_kind := str(_current_attack.get("payload_kind", "hitbox"))
	if payload_kind == "guard":
		_guard_active = true
		_guard_generation += 1
		_guard_commit_epoch += 1
		_committed_guard_resolution_ids.clear()
		_guard_elapsed_frames = 0
		_guard_parameters = (_current_attack.get("payload_parameters", {}) as Dictionary).duplicate(true)
		return true
	if not bool(_current_attack.get("damaging", true)):
		return true
	var action_identity := _damage_action_identity()
	var damage_info := _build_damage_info(_current_attack, action_identity)
	if damage_info == null:
		return false
	if payload_kind in ["zone", "wave"]:
		return _spawn_launch_payload(payload_kind, _current_attack, damage_info)
	_active_damage_attack_generation = int(action_identity["attack_generation"])
	_active_damage_action_token = int(action_identity["action_token"])
	hitbox.activate(damage_info)
	return true


func _build_damage_info(
	definition: Dictionary,
	action_identity: Dictionary = {}
) -> RefCounted:
	var frozen_identity := action_identity.duplicate(true)
	if frozen_identity.is_empty():
		frozen_identity = _damage_action_identity()
	if not _valid_damage_action_identity(frozen_identity):
		return null
	var effective_multiplier := float(definition["multiplier"])
	var heavy := bool(definition["heavy"])
	var finisher := bool(definition["finisher"])
	if heavy:
		effective_multiplier *= 1.0 + heavy_damage_multiplier_bonus
	elif finisher:
		effective_multiplier *= 1.0 + combo_finisher_multiplier_bonus
	if low_hp_damage_multiplier_bonus > 0.0 and _owner_hp_ratio() <= low_hp_threshold:
		effective_multiplier *= 1.0 + low_hp_damage_multiplier_bonus

	var profile_tags: Array[String] = []
	for tag: Variant in definition["tags"] as Array:
		profile_tags.append(str(tag))
	if heavy:
		if heavy_execute_multiplier_bonus > 0.0:
			profile_tags.append("talent:ruin_execute")
	return DamageInfoScript.from_plan({
		"run_id": &"legacy_run",
		"target_id": &"pending_target",
		"hostile_source_id": &"player_sword",
		"attack_generation": int(frozen_identity["attack_generation"]),
		"action_token": int(frozen_identity["action_token"]),
		"amount": base_attack * effective_multiplier,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": self,
		"attacker": owner_player,
		"knockback": Vector2.RIGHT.rotated(global_rotation) * float(definition["knockback"]),
		"tags": profile_tags,
	})


func _damage_action_identity() -> Dictionary:
	if owner_player != null and owner_player.has_method("weapon_damage_action_identity"):
		var identity_value: Variant = owner_player.call("weapon_damage_action_identity")
		if identity_value is Dictionary:
			var identity: Dictionary = identity_value
			if (
				StringName(str(identity.get("weapon_id", ""))) == WEAPON_ID
				and _valid_damage_action_identity(identity)
			):
				return {
					"attack_generation": int(identity["attack_generation"]),
					"action_token": int(identity["action_token"]),
				}
	var fallback_generation := _next_fallback_attack_generation
	_next_fallback_attack_generation += 1
	return {
		"attack_generation": fallback_generation,
		"action_token": fallback_generation,
	}


func _valid_damage_action_identity(value: Dictionary) -> bool:
	return (
		typeof(value.get("attack_generation")) == TYPE_INT
		and int(value["attack_generation"]) > 0
		and typeof(value.get("action_token")) == TYPE_INT
		and int(value["action_token"]) > 0
	)


func leave_active_phase() -> void:
	_active = false
	_active_damage_attack_generation = 0
	_active_damage_action_token = 0
	_guard_active = false
	_guard_elapsed_frames = 0
	_guard_parameters.clear()
	hitbox.deactivate()


func finish_attack() -> void:
	leave_active_phase()
	_attacking = false
	_current_attack.clear()


func cancel_attack() -> void:
	finish_attack()


func cancel_for_gameplay_rewind() -> bool:
	var guard := gameplay_rewind_committed_payload_guard()
	cancel_attack()
	return gameplay_rewind_committed_payload_guard() == guard


func gameplay_rewind_snapshot() -> Dictionary:
	return {
		"profile": _profile_runtime_snapshot(),
		"committed_payload_guard": gameplay_rewind_committed_payload_guard(),
	}


func restore_gameplay_rewind_snapshot_for_rollback(value: Dictionary) -> bool:
	if (
		not value.get("profile") is Dictionary
		or not value.get("committed_payload_guard") is Dictionary
		or value["committed_payload_guard"] != gameplay_rewind_committed_payload_guard()
	):
		return false
	var before := gameplay_rewind_snapshot()
	if not restore_profile_runtime_snapshot((value["profile"] as Dictionary).duplicate(true)):
		return false
	if gameplay_rewind_snapshot() == value:
		return true
	restore_profile_runtime_snapshot((before["profile"] as Dictionary).duplicate(true))
	return false


func gameplay_rewind_committed_payload_guard() -> Dictionary:
	var instance_ids: Array[int] = []
	for state: Dictionary in _launch_payloads:
		var node_value: Variant = state.get("node")
		if node_value is Node and is_instance_valid(node_value):
			instance_ids.append((node_value as Node).get_instance_id())
	return {
		"instance_ids": instance_ids,
		"launch": launch_runtime_snapshot(),
		"effect_events": _launch_effect_events.duplicate(true),
	}


func reset_combo() -> void:
	_combo_index = 0


func advance_launch_state(frame_count: int) -> void:
	if frame_count <= 0:
		return
	if _guard_active:
		_guard_elapsed_frames += frame_count
	for index: int in range(_launch_payloads.size() - 1, -1, -1):
		var state: Dictionary = _launch_payloads[index]
		state["elapsed_frames"] = int(state.get("elapsed_frames", 0)) + frame_count
		state["remaining_frames"] = maxi(0, int(state.get("remaining_frames", 0)) - frame_count)
		if int(state["remaining_frames"]) <= 0:
			_free_launch_payload_at(index)
		else:
			_update_launch_payload_transform(state)
			_launch_payloads[index] = state


func drain_launch_effect_events() -> Array[Dictionary]:
	var drained := _launch_effect_events.duplicate(true)
	_launch_effect_events.clear()
	return drained


func last_guard_result_for_test() -> Dictionary:
	return _last_guard_result.duplicate(true)


func launch_payload_snapshots_for_test() -> Array[Dictionary]:
	return _launch_payload_snapshots()


func launch_runtime_snapshot() -> Dictionary:
	return {
		"guard_active": _guard_active,
		"guard_generation": _guard_generation,
		"guard_elapsed_frames": _guard_elapsed_frames,
		"guard_parameters": _guard_parameters.duplicate(true),
		"last_guard_result": _last_guard_result.duplicate(true),
		"committed_guard_resolution_ids": _sorted_dictionary_keys(
			_committed_guard_resolution_ids
		),
		"next_fallback_attack_generation": _next_fallback_attack_generation,
		"payloads": _launch_payload_snapshots(),
	}


func restore_launch_runtime_snapshot(value: Dictionary) -> bool:
	if not _valid_launch_runtime_snapshot(value):
		return false
	_guard_commit_epoch += 1
	_clear_launch_payloads()
	_guard_active = bool(value["guard_active"])
	_guard_generation = int(value["guard_generation"])
	_guard_elapsed_frames = int(value["guard_elapsed_frames"])
	_guard_parameters = (value["guard_parameters"] as Dictionary).duplicate(true)
	_last_guard_result = (value["last_guard_result"] as Dictionary).duplicate(true)
	_committed_guard_resolution_ids.clear()
	for resolution_id: String in _string_array(value["committed_guard_resolution_ids"]):
		_committed_guard_resolution_ids[resolution_id] = true
	_next_fallback_attack_generation = int(value["next_fallback_attack_generation"])
	_launch_effect_events.clear()
	for payload_value: Variant in value["payloads"] as Array:
		var payload: Dictionary = payload_value
		var restored := _spawn_launch_payload_from_snapshot(payload)
		if not restored:
			_clear_launch_payloads()
			_guard_active = false
			_guard_generation = 0
			_guard_elapsed_frames = 0
			_guard_parameters.clear()
			_last_guard_result.clear()
			_committed_guard_resolution_ids.clear()
			_next_fallback_attack_generation = 1
			return false
	return true


func can_restore_launch_runtime_snapshot(value: Dictionary) -> bool:
	return _valid_launch_runtime_snapshot(value)


func can_restore_profile_runtime_snapshot(value: Dictionary) -> bool:
	return _valid_profile_runtime_snapshot(value)


func restore_profile_runtime_snapshot(value: Dictionary) -> bool:
	if not _valid_profile_runtime_snapshot(value):
		return false
	cancel_attack()
	_combo_index = int(value["combo_index"])
	_attacking = bool(value["attacking"])
	_active = bool(value["active"])
	_current_attack = (value["current_attack"] as Dictionary).duplicate(true)
	_active_damage_attack_generation = int(value["damage_attack_generation"])
	_active_damage_action_token = int(value["damage_action_token"])
	if _attacking and _active and str(_current_attack.get("payload_kind", "hitbox")) == "hitbox":
		var restored_damage := _build_damage_info(_current_attack, {
			"attack_generation": _active_damage_attack_generation,
			"action_token": _active_damage_action_token,
		})
		if restored_damage == null:
			cancel_attack()
			return false
		hitbox.activate(restored_damage)
	return true


func _profile_runtime_snapshot() -> Dictionary:
	return {
		"combo_index": _combo_index,
		"attacking": _attacking,
		"active": _active,
		"current_attack": _current_attack.duplicate(true),
		"damage_attack_generation": _active_damage_attack_generation,
		"damage_action_token": _active_damage_action_token,
	}


func _seconds_to_frames(seconds: float) -> int:
	var timing_scale := 1.0 / maxf(0.2, attack_speed)
	return maxi(1, ceili(seconds * timing_scale * Engine.physics_ticks_per_second))


func _owner_hp_ratio() -> float:
	var health_component := owner_player.get_node_or_null("HealthComponent")
	if health_component == null:
		return 1.0
	return float(health_component.current_hp) / maxf(1.0, float(health_component.max_hp))


func _valid_profile_attack(definition: Dictionary) -> bool:
	var damaging := bool(definition.get("damaging", true))
	if (
		typeof(definition.get("heavy")) != TYPE_BOOL
		or typeof(definition.get("finisher")) != TYPE_BOOL
		or typeof(definition.get("multiplier")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(definition.get("multiplier", 0.0)))
		or (damaging and float(definition.get("multiplier", 0.0)) <= 0.0)
		or (not damaging and float(definition.get("multiplier", 0.0)) < 0.0)
		or typeof(definition.get("knockback")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(definition.get("knockback", 0.0)))
		or float(definition.get("knockback", -1.0)) < 0.0
		or not definition.get("tags") is Array
		or not _valid_character_combat_stats(definition)
	):
		return false
	var tags: Array = definition["tags"]
	if tags.is_empty():
		return false
	for tag: Variant in tags:
		if typeof(tag) not in [TYPE_STRING, TYPE_STRING_NAME] or str(tag).is_empty():
			return false
	return true


func _valid_character_combat_stats(definition: Dictionary) -> bool:
	for field: String in ["character_attack_scale", "attack_speed", "crit_chance", "crit_multiplier"]:
		var value: Variant = definition.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return (
		float(definition["character_attack_scale"]) > 0.0
		and float(definition["attack_speed"]) > 0.0
		and float(definition["crit_chance"]) >= 0.0
		and float(definition["crit_chance"]) <= 1.0
		and float(definition["crit_multiplier"]) >= 1.0
	)


func plan_damage_defense(damage_info: RefCounted) -> Dictionary:
	if damage_info == null:
		return {}
	var damage_identity := _guard_damage_identity(damage_info)
	if damage_identity.is_empty():
		return {}
	return _guard_decision_for_context(float(damage_info.amount), damage_identity)


func commit_damage_defense(decision: Dictionary, resolution: RefCounted) -> bool:
	if not can_commit_damage_defense(decision, resolution):
		return false
	var context: Dictionary = decision["commit_context"]
	var resolution_snapshot: Dictionary = resolution.call("snapshot")
	_committed_guard_resolution_ids[str(resolution_snapshot["resolution_id"])] = true
	_trim_committed_guard_resolution_ids()
	_last_guard_result = {
		"blocked_damage": float(context["blocked_damage"]),
		"block_multiplier": float(context["block_multiplier"]),
		"perfect": bool(context["perfect"]),
		"intent_gain": float(context["intent_gain"]),
	}
	_launch_effect_events.append({
		"type": "guard_resolved",
		"blocked_damage": float(context["blocked_damage"]),
		"block_multiplier": float(context["block_multiplier"]),
		"perfect": bool(context["perfect"]),
		"intent_gain": float(context["intent_gain"]),
	})
	return true


func can_commit_damage_defense(decision: Dictionary, resolution: RefCounted) -> bool:
	return _valid_damage_defense_commit(decision, resolution)


func _valid_damage_defense_commit(decision: Dictionary, resolution: RefCounted) -> bool:
	if (
		not _guard_active
		or resolution == null
		or not resolution.has_method("snapshot")
		or not _has_exact_dictionary_fields(decision, [
			"prevented", "multiplier", "prevent_reason", "guard_kind", "commit_context",
		])
		or not decision["commit_context"] is Dictionary
	):
		return false
	var context: Dictionary = decision["commit_context"]
	if not _has_exact_dictionary_fields(context, [
		"weapon_id",
		"guard_commit_epoch",
		"guard_generation",
		"guard_elapsed_frames",
		"run_id",
		"target_id",
		"hostile_source_id",
		"attack_generation",
		"action_token",
		"tags",
		"original_amount",
		"blocked_damage",
		"block_multiplier",
		"perfect",
		"intent_gain",
	]):
		return false
	if (
		typeof(context["weapon_id"]) != TYPE_STRING_NAME
		or context["weapon_id"] != WEAPON_ID
		or typeof(context["guard_commit_epoch"]) != TYPE_INT
		or int(context["guard_commit_epoch"]) != _guard_commit_epoch
		or typeof(context["guard_generation"]) != TYPE_INT
		or int(context["guard_generation"]) != _guard_generation
		or typeof(context["guard_elapsed_frames"]) != TYPE_INT
		or int(context["guard_elapsed_frames"]) != _guard_elapsed_frames
		or typeof(context["perfect"]) != TYPE_BOOL
	):
		return false
	for field: String in ["original_amount", "blocked_damage", "block_multiplier", "intent_gain"]:
		if typeof(context[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(context[field])):
			return false
	var original_amount := float(context["original_amount"])
	var damage_identity := _guard_identity_from_context(context)
	if original_amount <= 0.0 or damage_identity.is_empty():
		return false
	var expected := _guard_decision_for_context(original_amount, damage_identity)
	if expected != decision:
		return false
	var snapshot_value: Variant = resolution.call("snapshot")
	if not snapshot_value is Dictionary:
		return false
	return _resolution_matches_guard_decision(snapshot_value as Dictionary, decision, context)


func _guard_decision_for_context(original_amount: float, damage_identity: Dictionary) -> Dictionary:
	if (
		not _guard_active
		or _guard_generation <= 0
		or not is_finite(original_amount)
		or original_amount <= 0.0
		or not _valid_guard_damage_identity(damage_identity)
	):
		return {}
	var perfect_window := maxi(0, int(_guard_parameters.get("perfect_window_frames", 0)))
	var perfect := _guard_elapsed_frames < perfect_window
	var block_multiplier := clampf(
		float(_guard_parameters.get("perfect_block_multiplier" if perfect else "block_multiplier", 1.0)),
		0.0,
		1.0
	)
	var blocked_damage := original_amount - original_amount * block_multiplier
	var intent_gain := (
		blocked_damage * maxf(0.0, float(_guard_parameters.get("intent_per_blocked_damage", 1.0)))
		+ (maxf(0.0, float(_guard_parameters.get("perfect_intent_bonus", 0.0))) if perfect else 0.0)
	)
	return {
		"prevented": perfect,
		"multiplier": 1.0 if perfect else block_multiplier,
		"prevent_reason": &"sword_perfect" if perfect else &"",
		"guard_kind": &"sword_perfect" if perfect else &"sword_normal",
		"commit_context": {
			"weapon_id": WEAPON_ID,
			"guard_commit_epoch": _guard_commit_epoch,
			"guard_generation": _guard_generation,
			"guard_elapsed_frames": _guard_elapsed_frames,
			"run_id": damage_identity["run_id"],
			"target_id": damage_identity["target_id"],
			"hostile_source_id": damage_identity["hostile_source_id"],
			"attack_generation": damage_identity["attack_generation"],
			"action_token": damage_identity["action_token"],
			"tags": (damage_identity["tags"] as Array).duplicate(),
			"original_amount": original_amount,
			"blocked_damage": blocked_damage,
			"block_multiplier": block_multiplier,
			"perfect": perfect,
			"intent_gain": intent_gain,
		},
	}


func _guard_damage_identity(damage_info: RefCounted) -> Dictionary:
	var run_id := StringName(str(damage_info.run_id))
	if run_id == &"":
		run_id = &"legacy"
	var target_id := _canonical_guard_target_id(StringName(str(damage_info.target_id)))
	var hostile_source_id := StringName(str(damage_info.hostile_source_id))
	if hostile_source_id == &"":
		hostile_source_id = &"legacy_source"
	return {
		"run_id": run_id,
		"target_id": target_id,
		"hostile_source_id": hostile_source_id,
		"attack_generation": maxi(1, int(damage_info.attack_generation)),
		"action_token": maxi(1, int(damage_info.action_token)),
		"tags": (damage_info.tags as Array).duplicate(),
	}


func _canonical_guard_target_id(target_id: StringName) -> StringName:
	if target_id == &"pending_target" and owner_player != null:
		for key: StringName in [&"stable_target_id", &"stable_target_key", &"encounter_spawn_id"]:
			if owner_player.has_meta(key):
				var value := str(owner_player.get_meta(key)).strip_edges()
				if not value.is_empty():
					return StringName(value)
	if target_id != &"":
		return target_id
	return StringName(owner_player.name if owner_player != null else "legacy_target")


func _guard_identity_from_context(context: Dictionary) -> Dictionary:
	var identity := {
		"run_id": context.get("run_id"),
		"target_id": context.get("target_id"),
		"hostile_source_id": context.get("hostile_source_id"),
		"attack_generation": context.get("attack_generation"),
		"action_token": context.get("action_token"),
		"tags": (context.get("tags", []) as Array).duplicate() if context.get("tags", []) is Array else [],
	}
	return identity if _valid_guard_damage_identity(identity) else {}


func _valid_guard_damage_identity(value: Dictionary) -> bool:
	if not _has_exact_dictionary_fields(value, [
		"run_id", "target_id", "hostile_source_id", "attack_generation", "action_token", "tags",
	]):
		return false
	for field: String in ["run_id", "target_id", "hostile_source_id"]:
		if typeof(value[field]) != TYPE_STRING_NAME or StringName(value[field]) == &"":
			return false
	if (
		typeof(value["attack_generation"]) != TYPE_INT
		or int(value["attack_generation"]) <= 0
		or typeof(value["action_token"]) != TYPE_INT
		or int(value["action_token"]) <= 0
		or not value["tags"] is Array
	):
		return false
	for tag: Variant in value["tags"] as Array:
		if typeof(tag) not in [TYPE_STRING, TYPE_STRING_NAME] or str(tag).is_empty():
			return false
	return true


func _resolution_matches_guard_decision(
	snapshot: Dictionary,
	decision: Dictionary,
	context: Dictionary
) -> bool:
	var resolution_id := str(snapshot.get("resolution_id", ""))
	if (
		resolution_id.is_empty()
		or resolution_id.length() > MAX_RESOLUTION_ID_LENGTH
		or _committed_guard_resolution_ids.has(resolution_id)
	):
		return false
	for field: String in ["run_id", "target_id", "hostile_source_id"]:
		if StringName(str(snapshot.get(field, ""))) != StringName(context[field]):
			return false
	for field: String in ["attack_generation", "action_token"]:
		if typeof(snapshot.get(field)) != TYPE_INT or int(snapshot[field]) != int(context[field]):
			return false
	if (
		not snapshot.get("tags", []) is Array
		or (snapshot.get("tags", []) as Array) != (context["tags"] as Array)
		or not is_equal_approx(
			float(snapshot.get("original_amount", -1.0)),
			float(context["original_amount"])
		)
		or not is_equal_approx(
			float(snapshot.get("post_weapon_defense_amount", -1.0)),
			0.0 if bool(context["perfect"]) else (
				float(context["original_amount"]) * float(decision["multiplier"])
			)
		)
	):
		return false
	if not bool(context["perfect"]):
		return true
	return (
		bool(snapshot.get("prevented", false))
		and StringName(str(snapshot.get("prevent_reason", ""))) == &"sword_perfect"
		and StringName(str(snapshot.get("guard_kind", ""))) == &"sword_perfect"
		and is_zero_approx(float(snapshot.get("finalized_damage", -1.0)))
	)


func _trim_committed_guard_resolution_ids() -> void:
	while _committed_guard_resolution_ids.size() > MAX_COMMITTED_GUARD_RESOLUTION_IDS:
		var keys := _committed_guard_resolution_ids.keys()
		if keys.is_empty():
			return
		_committed_guard_resolution_ids.erase(keys[0])


func _has_exact_dictionary_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _spawn_launch_payload(
	kind: String,
	definition: Dictionary,
	damage_info: RefCounted,
	remaining_frames_override: int = -1,
	elapsed_frames_override: int = 0,
	hit_target_keys_override: Array[String] = [],
	world_origin_override: Variant = null,
	world_direction_override: Variant = null
) -> bool:
	var parameters: Dictionary = (definition.get("payload_parameters", {}) as Dictionary).duplicate(true)
	var duration_frames := maxi(
		1,
		remaining_frames_override if remaining_frames_override > 0 else int(parameters.get("duration_frames", 1))
	)
	var area := Area2D.new()
	area.name = "Sword%s%d" % [kind.capitalize(), _next_launch_payload_id]
	area.collision_layer = 0
	area.collision_mask = Targets.PLAYER_ATTACK_MASK
	area.monitoring = true
	area.monitorable = false
	area.top_level = true
	var collision := CollisionShape2D.new()
	if kind == "zone":
		var circle := CircleShape2D.new()
		circle.radius = maxf(1.0, float(parameters.get("radius_pixels", 64.0)))
		collision.shape = circle
	else:
		var rectangle := RectangleShape2D.new()
		var range_pixels := maxf(1.0, float(parameters.get("range_pixels", 320.0)))
		rectangle.size = Vector2(
			maxf(1.0, float(parameters.get("thickness_pixels", 64.0))),
			maxf(1.0, float(parameters.get("width_pixels", 96.0)))
		)
		collision.shape = rectangle
	area.add_child(collision)
	add_child(area)
	var world_origin := global_position if world_origin_override == null else world_origin_override as Vector2
	var world_direction := (
		Vector2.RIGHT.rotated(global_rotation)
		if world_direction_override == null
		else (world_direction_override as Vector2).normalized()
	)
	area.global_position = world_origin
	area.global_rotation = world_direction.angle()
	var payload_id := _next_launch_payload_id
	_next_launch_payload_id += 1
	area.area_entered.connect(_on_launch_payload_area_entered.bind(payload_id))
	_launch_payloads.append({
		"id": payload_id,
		"node": area,
		"kind": kind,
		"parameters": parameters,
		"remaining_frames": duration_frames,
		"elapsed_frames": maxi(0, elapsed_frames_override),
		"world_origin": world_origin,
		"world_direction": world_direction,
		"damage_info": damage_info,
		"hit_target_keys": hit_target_keys_override.duplicate(),
	})
	_update_launch_payload_transform(_launch_payloads.back())
	return true


func _spawn_launch_payload_from_snapshot(snapshot_value: Dictionary) -> bool:
	var definition := {
		"payload_parameters": (snapshot_value.get("parameters", {}) as Dictionary).duplicate(true),
	}
	var damage_snapshot: Dictionary = snapshot_value.get("damage", {})
	var damage_info := DamageInfoScript.from_plan({
		"run_id": damage_snapshot.get("run_id", &""),
		"target_id": damage_snapshot.get("target_id", &""),
		"hostile_source_id": damage_snapshot.get("hostile_source_id", &""),
		"attack_generation": damage_snapshot.get("attack_generation", 0),
		"action_token": damage_snapshot.get("action_token", 0),
		"amount": float(damage_snapshot.get("amount", 0.0)),
		"damage_type": int(damage_snapshot.get("damage_type", DamageInfoScript.DamageType.PHYSICAL)),
		"source": self,
		"attacker": owner_player,
		"tags": Array(damage_snapshot.get("tags", []), TYPE_STRING, "", null),
		"knockback": damage_snapshot.get("knockback", Vector2.ZERO),
	})
	if damage_info == null:
		return false
	return _spawn_launch_payload(
		str(snapshot_value.get("kind", "")),
		definition,
		damage_info,
		int(snapshot_value.get("remaining_frames", 0)),
		int(snapshot_value.get("elapsed_frames", 0)),
		_string_array(snapshot_value.get("hit_target_keys", [])),
		snapshot_value.get("world_origin"),
		snapshot_value.get("world_direction")
	)


func _on_launch_payload_area_entered(area: Area2D, payload_id: int) -> void:
	for index: int in range(_launch_payloads.size()):
		var state: Dictionary = _launch_payloads[index]
		if int(state.get("id", 0)) != payload_id:
			continue
		var target_key := _stable_target_key(area)
		var hit_target_keys: Array = state.get("hit_target_keys", [])
		if target_key.is_empty() or hit_target_keys.has(target_key) or not area.has_method("receive_hit"):
			return
		hit_target_keys.append(target_key)
		state["hit_target_keys"] = hit_target_keys
		_launch_payloads[index] = state
		var damage_info: RefCounted = state["damage_info"]
		area.call("receive_hit", damage_info.copy_for_source(state["node"]))
		return


func _launch_payload_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for state: Dictionary in _launch_payloads:
		var damage_info: RefCounted = state["damage_info"]
		var payload_node: Node2D = state.get("node")
		result.append({
			"kind": str(state.get("kind", "")),
			"position": payload_node.global_position if payload_node != null and is_instance_valid(payload_node) else Vector2.ZERO,
			"parameters": (state.get("parameters", {}) as Dictionary).duplicate(true),
			"remaining_frames": int(state.get("remaining_frames", 0)),
			"elapsed_frames": int(state.get("elapsed_frames", 0)),
			"world_origin": state.get("world_origin", Vector2.ZERO),
			"world_direction": state.get("world_direction", Vector2.RIGHT),
			"hit_target_keys": (state.get("hit_target_keys", []) as Array).duplicate(),
			"damage": {
				"run_id": damage_info.get("run_id"),
				"target_id": damage_info.get("target_id"),
				"hostile_source_id": damage_info.get("hostile_source_id"),
				"attack_generation": int(damage_info.get("attack_generation")),
				"action_token": int(damage_info.get("action_token")),
				"amount": float(damage_info.get("amount")),
				"damage_type": int(damage_info.get("damage_type")),
				"tags": (damage_info.get("tags") as Array).duplicate(),
				"knockback": damage_info.get("knockback"),
			},
		})
	return result


func _valid_launch_runtime_snapshot(value: Dictionary) -> bool:
	if (
		typeof(value.get("guard_active")) != TYPE_BOOL
		or typeof(value.get("guard_generation")) != TYPE_INT
		or int(value.get("guard_generation", -1)) < 0
		or typeof(value.get("guard_elapsed_frames")) != TYPE_INT
		or int(value.get("guard_elapsed_frames", -1)) < 0
		or not value.get("guard_parameters") is Dictionary
		or not value.get("last_guard_result") is Dictionary
		or not _valid_string_array(
			value.get("committed_guard_resolution_ids"),
			MAX_COMMITTED_GUARD_RESOLUTION_IDS,
			MAX_RESOLUTION_ID_LENGTH
		)
		or typeof(value.get("next_fallback_attack_generation")) != TYPE_INT
		or int(value.get("next_fallback_attack_generation", 0)) <= 0
		or not value.get("payloads") is Array
	):
		return false
	for payload_value: Variant in value["payloads"] as Array:
		if not payload_value is Dictionary:
			return false
		var payload: Dictionary = payload_value
		if (
			str(payload.get("kind", "")) not in ["zone", "wave"]
			or typeof(payload.get("remaining_frames")) != TYPE_INT
			or int(payload.get("remaining_frames", 0)) <= 0
			or typeof(payload.get("elapsed_frames")) != TYPE_INT
			or int(payload.get("elapsed_frames", -1)) < 0
			or not payload.get("world_origin") is Vector2
			or not payload.get("world_direction") is Vector2
			or not _valid_string_array(payload.get("hit_target_keys"))
			or not payload.get("parameters") is Dictionary
			or not _valid_launch_damage_snapshot(payload.get("damage"))
		):
			return false
	return true


func _valid_launch_damage_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var damage: Dictionary = value
	if not _has_exact_dictionary_fields(damage, [
		"run_id",
		"target_id",
		"hostile_source_id",
		"attack_generation",
		"action_token",
		"amount",
		"damage_type",
		"tags",
		"knockback",
	]):
		return false
	return DamageInfoScript.from_plan({
		"run_id": damage["run_id"],
		"target_id": damage["target_id"],
		"hostile_source_id": damage["hostile_source_id"],
		"attack_generation": damage["attack_generation"],
		"action_token": damage["action_token"],
		"amount": damage["amount"],
		"damage_type": damage["damage_type"],
		"source": self,
		"attacker": owner_player,
		"tags": damage["tags"],
		"knockback": damage["knockback"],
	}) != null


func _update_launch_payload_transform(state: Dictionary) -> void:
	if str(state.get("kind", "")) != "wave":
		return
	var node: Node2D = state.get("node")
	if node == null or not is_instance_valid(node):
		return
	var parameters: Dictionary = state.get("parameters", {})
	var duration_frames := maxi(1, int(parameters.get("duration_frames", 1)))
	var progress := clampf(float(state.get("elapsed_frames", 0)) / float(duration_frames), 0.0, 1.0)
	var origin: Vector2 = state.get("world_origin", Vector2.ZERO)
	var direction: Vector2 = state.get("world_direction", Vector2.RIGHT)
	node.global_position = origin + direction * (float(parameters.get("range_pixels", 320.0)) * progress)
	node.global_rotation = direction.angle()


func _stable_target_key(area: Area2D) -> String:
	if area.has_method("stable_entity_key"):
		var method_key := str(area.call("stable_entity_key"))
		if not method_key.is_empty():
			return "method:%s" % method_key
	if area.has_meta("stable_entity_key"):
		var metadata_key := str(area.get_meta("stable_entity_key"))
		if not metadata_key.is_empty():
			return "meta:%s" % metadata_key
	var entity := area.get_parent()
	if entity != null and entity.has_meta("stable_entity_key"):
		var entity_key := str(entity.get_meta("stable_entity_key"))
		if not entity_key.is_empty():
			return "entity:%s" % entity_key
	return "path:%s" % str(area.get_path()) if area.is_inside_tree() else ""


func _valid_profile_runtime_snapshot(value: Dictionary) -> bool:
	if (
		typeof(value.get("combo_index")) != TYPE_INT
		or int(value.get("combo_index", -1)) not in range(LIGHT_COMBO.size())
		or typeof(value.get("attacking")) != TYPE_BOOL
		or typeof(value.get("active")) != TYPE_BOOL
		or not value.get("current_attack") is Dictionary
		or typeof(value.get("damage_attack_generation")) != TYPE_INT
		or typeof(value.get("damage_action_token")) != TYPE_INT
	):
		return false
	var current_attack: Dictionary = value["current_attack"]
	var requires_damage_identity := (
		bool(value["attacking"])
		and bool(value["active"])
		and str(current_attack.get("payload_kind", "hitbox")) == "hitbox"
		and bool(current_attack.get("damaging", true))
	)
	var damage_identity := {
		"attack_generation": int(value["damage_attack_generation"]),
		"action_token": int(value["damage_action_token"]),
	}
	if requires_damage_identity != _valid_damage_action_identity(damage_identity):
		return false
	if not requires_damage_identity and (
		int(value["damage_attack_generation"]) != 0
		or int(value["damage_action_token"]) != 0
	):
		return false
	if not bool(value["attacking"]):
		return not bool(value["active"]) and current_attack.is_empty()
	return (
		not current_attack.is_empty()
		and _valid_profile_attack(current_attack)
	)


func _valid_string_array(value: Variant, maximum_size: int = -1, maximum_length: int = -1) -> bool:
	if not value is Array:
		return false
	if maximum_size >= 0 and (value as Array).size() > maximum_size:
		return false
	var seen: Dictionary = {}
	for child: Variant in value as Array:
		if (
			typeof(child) not in [TYPE_STRING, TYPE_STRING_NAME]
			or str(child).is_empty()
			or (maximum_length >= 0 and str(child).length() > maximum_length)
			or seen.has(str(child))
		):
			return false
		seen[str(child)] = true
	return true


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for child: Variant in value as Array:
			result.append(str(child))
	return result


func _sorted_dictionary_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in value.keys():
		result.append(str(key))
	result.sort()
	return result


func _free_launch_payload_at(index: int) -> void:
	if index < 0 or index >= _launch_payloads.size():
		return
	var node: Node = _launch_payloads[index].get("node")
	_launch_payloads.remove_at(index)
	if node != null and is_instance_valid(node):
		node.queue_free()


func _clear_launch_payloads() -> void:
	for index: int in range(_launch_payloads.size() - 1, -1, -1):
		_free_launch_payload_at(index)
