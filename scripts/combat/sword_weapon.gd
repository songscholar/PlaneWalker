class_name SwordWeapon
extends Node2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const WEAPON_ID := &"sword"

@export var owner_path: NodePath
@export var base_attack: float = 30.0
@export var attack_speed: float = 1.0

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
var _perfect_guard_damage_ids: Dictionary = {}

const LIGHT_COMBO: Array[Dictionary] = [
	{"multiplier": 0.8, "windup": 0.10, "active": 0.08, "recovery": 0.18, "finisher": false},
	{"multiplier": 1.0, "windup": 0.12, "active": 0.08, "recovery": 0.20, "finisher": false},
	{"multiplier": 1.3, "windup": 0.16, "active": 0.10, "recovery": 0.28, "finisher": true},
]


func _ready() -> void:
	if not EventBus.damage_about_to_apply.is_connected(_on_damage_about_to_apply):
		EventBus.damage_about_to_apply.connect(_on_damage_about_to_apply)
	if not EventBus.damage_applied.is_connected(_on_damage_applied):
		EventBus.damage_applied.connect(_on_damage_applied)


func _exit_tree() -> void:
	if EventBus.damage_about_to_apply.is_connected(_on_damage_about_to_apply):
		EventBus.damage_about_to_apply.disconnect(_on_damage_about_to_apply)
	if EventBus.damage_applied.is_connected(_on_damage_applied):
		EventBus.damage_applied.disconnect(_on_damage_applied)
	_clear_launch_payloads()


func weapon_id() -> StringName:
	return WEAPON_ID


func reset_runtime_state() -> void:
	cancel_attack()
	reset_combo()
	_last_guard_result.clear()
	_launch_effect_events.clear()
	_perfect_guard_damage_ids.clear()
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
		_guard_elapsed_frames = 0
		_guard_parameters = (_current_attack.get("payload_parameters", {}) as Dictionary).duplicate(true)
		return true
	if not bool(_current_attack.get("damaging", true)):
		return true
	var damage_info := _build_damage_info(_current_attack)
	if damage_info == null:
		return false
	if payload_kind in ["zone", "wave"]:
		return _spawn_launch_payload(payload_kind, _current_attack, damage_info)
	hitbox.activate(damage_info)
	return true


func _build_damage_info(definition: Dictionary) -> RefCounted:
	var effective_multiplier := float(definition["multiplier"])
	var heavy := bool(definition["heavy"])
	var finisher := bool(definition["finisher"])
	if heavy:
		effective_multiplier *= 1.0 + heavy_damage_multiplier_bonus
	elif finisher:
		effective_multiplier *= 1.0 + combo_finisher_multiplier_bonus
	if low_hp_damage_multiplier_bonus > 0.0 and _owner_hp_ratio() <= low_hp_threshold:
		effective_multiplier *= 1.0 + low_hp_damage_multiplier_bonus

	var damage_info := DamageInfoScript.new(base_attack * effective_multiplier, DamageInfoScript.DamageType.PHYSICAL, self, owner_player)
	var profile_tags: Array[String] = []
	for tag: Variant in definition["tags"] as Array:
		profile_tags.append(str(tag))
	damage_info.tags = profile_tags
	damage_info.knockback = Vector2.RIGHT.rotated(global_rotation) * float(definition["knockback"])
	if heavy:
		if heavy_execute_multiplier_bonus > 0.0:
			damage_info.tags.append("talent:ruin_execute")
	return damage_info


func leave_active_phase() -> void:
	_active = false
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
		"guard_elapsed_frames": _guard_elapsed_frames,
		"guard_parameters": _guard_parameters.duplicate(true),
		"last_guard_result": _last_guard_result.duplicate(true),
		"payloads": _launch_payload_snapshots(),
	}


func restore_launch_runtime_snapshot(value: Dictionary) -> bool:
	if not _valid_launch_runtime_snapshot(value):
		return false
	_clear_launch_payloads()
	_guard_active = bool(value["guard_active"])
	_guard_elapsed_frames = int(value["guard_elapsed_frames"])
	_guard_parameters = (value["guard_parameters"] as Dictionary).duplicate(true)
	_last_guard_result = (value["last_guard_result"] as Dictionary).duplicate(true)
	_launch_effect_events.clear()
	for payload_value: Variant in value["payloads"] as Array:
		var payload: Dictionary = payload_value
		var restored := _spawn_launch_payload_from_snapshot(payload)
		if not restored:
			_clear_launch_payloads()
			_guard_active = false
			_guard_parameters.clear()
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
	if _attacking and _active and str(_current_attack.get("payload_kind", "hitbox")) == "hitbox":
		var restored_damage := _build_damage_info(_current_attack)
		if restored_damage == null:
			cancel_attack()
			return false
		hitbox.activate(restored_damage)
	return true


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
	):
		return false
	var tags: Array = definition["tags"]
	if tags.is_empty():
		return false
	for tag: Variant in tags:
		if typeof(tag) not in [TYPE_STRING, TYPE_STRING_NAME] or str(tag).is_empty():
			return false
	return true


func _on_damage_about_to_apply(damage_info: Variant, target: Node) -> void:
	if not _guard_active or target != owner_player or not damage_info is RefCounted:
		return
	var original_amount := float((damage_info as RefCounted).get("amount"))
	if not is_finite(original_amount) or original_amount <= 0.0:
		return
	var perfect_window := maxi(0, int(_guard_parameters.get("perfect_window_frames", 0)))
	var perfect := _guard_elapsed_frames < perfect_window
	var block_multiplier := clampf(
		float(_guard_parameters.get("perfect_block_multiplier" if perfect else "block_multiplier", 1.0)),
		0.0,
		1.0
	)
	var reduced_amount := original_amount * block_multiplier
	(damage_info as RefCounted).set("amount", reduced_amount)
	var blocked_damage := original_amount - reduced_amount
	var intent_gain := (
		blocked_damage * maxf(0.0, float(_guard_parameters.get("intent_per_blocked_damage", 1.0)))
		+ (maxf(0.0, float(_guard_parameters.get("perfect_intent_bonus", 0.0))) if perfect else 0.0)
	)
	_last_guard_result = {
		"blocked_damage": blocked_damage,
		"block_multiplier": block_multiplier,
		"perfect": perfect,
		"intent_gain": intent_gain,
	}
	if perfect:
		_perfect_guard_damage_ids[(damage_info as RefCounted).get_instance_id()] = true
	_launch_effect_events.append({
		"type": "guard_resolved",
		"blocked_damage": blocked_damage,
		"block_multiplier": block_multiplier,
		"perfect": perfect,
		"intent_gain": intent_gain,
	})


func _on_damage_applied(damage_info: Variant, target: Node, final_amount: float) -> void:
	if target != owner_player or not damage_info is RefCounted:
		return
	var damage_id := (damage_info as RefCounted).get_instance_id()
	if not _perfect_guard_damage_ids.erase(damage_id):
		return
	var health := owner_player.get_node_or_null("HealthComponent")
	if health != null and final_amount > 0.0:
		health.call("heal", final_amount)
	_last_guard_result["refunded_damage"] = final_amount


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
	area.collision_mask = 1
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
	var damage_info := DamageInfoScript.new(
		float(damage_snapshot.get("amount", 0.0)),
		int(damage_snapshot.get("damage_type", DamageInfoScript.DamageType.PHYSICAL)),
		self,
		owner_player
	)
	damage_info.tags = Array(damage_snapshot.get("tags", []), TYPE_STRING, "", null)
	damage_info.knockback = damage_snapshot.get("knockback", Vector2.ZERO)
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
		or typeof(value.get("guard_elapsed_frames")) != TYPE_INT
		or int(value.get("guard_elapsed_frames", -1)) < 0
		or not value.get("guard_parameters") is Dictionary
		or not value.get("last_guard_result") is Dictionary
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
			or not payload.get("damage") is Dictionary
		):
			return false
	return true


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
	):
		return false
	if not bool(value["attacking"]):
		return not bool(value["active"]) and (value["current_attack"] as Dictionary).is_empty()
	return (
		not (value["current_attack"] as Dictionary).is_empty()
		and _valid_profile_attack(value["current_attack"])
	)


func _valid_string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for child: Variant in value as Array:
		if typeof(child) not in [TYPE_STRING, TYPE_STRING_NAME] or str(child).is_empty() or seen.has(str(child)):
			return false
		seen[str(child)] = true
	return true


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for child: Variant in value as Array:
			result.append(str(child))
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
