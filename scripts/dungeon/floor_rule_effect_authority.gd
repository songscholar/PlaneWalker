class_name FloorRuleEffectAuthority
extends RefCounted

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const FACT_FIELDS: Array[String] = [
	"fact_type",
	"rule_id",
	"room_id",
	"runtime_frame",
	"cycle_index",
	"zone_id",
	"source_kind",
	"source_id",
	"payload",
]
const DAMAGE_PAYLOAD_FIELDS: Array[String] = [
	"amount",
	"damage_type",
	"target_scope",
	"nonlethal",
	"minimum_remaining_hp",
]
const MODIFIER_PAYLOAD_FIELDS: Array[String] = [
	"modifier_id",
	"target_scope",
	"duration_frames",
	"values",
	"operation",
]
const DAMAGE_TYPES := {
	"physical": DamageInfoScript.DamageType.PHYSICAL,
	"time": DamageInfoScript.DamageType.TIME,
	"void": DamageInfoScript.DamageType.VOID,
	"fire": DamageInfoScript.DamageType.FIRE,
	"ice": DamageInfoScript.DamageType.ICE,
	"lightning": DamageInfoScript.DamageType.LIGHTNING,
}

var _player: Node
var _room_scene_host: Node
var _committed_effect_ids: Dictionary = {}


func configure(player: Node, room_scene_host: Node) -> bool:
	if not _player_contract_is_valid(player) or not _room_host_contract_is_valid(room_scene_host):
		return false
	_player = player
	_room_scene_host = room_scene_host
	_committed_effect_ids.clear()
	return true


func is_configured() -> bool:
	return (
		_player_contract_is_valid(_player)
		and _room_host_contract_is_valid(_room_scene_host)
	)


func reset() -> void:
	_player = null
	_room_scene_host = null
	_committed_effect_ids.clear()


func reset_runtime_state() -> bool:
	_committed_effect_ids.clear()
	return is_configured()


func commit_floor_rule_effects(facts: Array) -> bool:
	if not is_configured():
		return false
	if facts.is_empty():
		return true
	var plans: Array[Dictionary] = []
	var batch_ids: Dictionary = {}
	for fact_value: Variant in facts:
		if not fact_value is Dictionary:
			return false
		var plan := _validated_plan((fact_value as Dictionary).duplicate(true))
		if plan.is_empty():
			return false
		var effect_id := str(plan["effect_id"])
		if batch_ids.has(effect_id):
			return false
		batch_ids[effect_id] = true
		plans.append(plan)

	var health := _player.get_node_or_null("HealthComponent")
	if health == null:
		return false
	var reward_before_value: Variant = health.call("reward_effect_snapshot")
	var floor_before_value: Variant = _player.call("floor_rule_effect_snapshot")
	if (
		not reward_before_value is Dictionary
		or (reward_before_value as Dictionary).is_empty()
		or not floor_before_value is Dictionary
		or (floor_before_value as Dictionary).is_empty()
	):
		return false
	var reward_before := (reward_before_value as Dictionary).duplicate(true)
	var floor_before := (floor_before_value as Dictionary).duplicate(true)

	for plan: Dictionary in plans:
		var effect_id := str(plan["effect_id"])
		if _committed_effect_ids.has(effect_id):
			continue
		if not _apply_plan(plan):
			_restore_player(health, reward_before, floor_before)
			return false
	for plan: Dictionary in plans:
		_committed_effect_ids[str(plan["effect_id"])] = true
	return true


func _validated_plan(fact: Dictionary) -> Dictionary:
	if not _has_exact_fields(fact, FACT_FIELDS):
		return {}
	if (
		typeof(fact["fact_type"]) != TYPE_STRING
		or str(fact["fact_type"]) not in ["damage", "modifier"]
		or typeof(fact["rule_id"]) != TYPE_STRING
		or str(fact["rule_id"]).is_empty()
		or typeof(fact["room_id"]) != TYPE_STRING
		or str(fact["room_id"]).is_empty()
		or typeof(fact["runtime_frame"]) != TYPE_INT
		or int(fact["runtime_frame"]) < 0
		or typeof(fact["cycle_index"]) != TYPE_INT
		or int(fact["cycle_index"]) < 0
		or typeof(fact["zone_id"]) != TYPE_STRING
		or str(fact["zone_id"]).is_empty()
		or typeof(fact["source_kind"]) != TYPE_STRING
		or str(fact["source_kind"]) != "floor_rule"
		or typeof(fact["source_id"]) != TYPE_STRING
		or str(fact["source_id"]).is_empty()
		or str(fact["source_id"]).length() > 64
		or not fact["payload"] is Dictionary
	):
		return {}
	var room := _room_scene_host.call("active_room") as Node2D
	if room == null or not is_instance_valid(room) or not room.has_method("floor_rule_configuration"):
		return {}
	var configuration_value: Variant = room.call("floor_rule_configuration")
	if not configuration_value is Dictionary:
		return {}
	var configuration := configuration_value as Dictionary
	if str(configuration.get("room_id", "")) != str(fact["room_id"]):
		return {}
	var zone_bounds: Variant = _zone_bounds(configuration, str(fact["zone_id"]))
	if zone_bounds == null:
		return {}
	var payload := fact["payload"] as Dictionary
	var operation := ""
	if str(fact["fact_type"]) == "damage":
		if not _valid_damage_payload(payload):
			return {}
	else:
		if not _valid_modifier_payload(payload):
			return {}
		operation = str(payload["operation"])
	var effect_id := "%s|%d|%s|%s" % [
		str(fact["source_id"]),
		int(fact["runtime_frame"]),
		str(fact["fact_type"]),
		operation,
	]
	return {
		"effect_id": effect_id,
		"fact": fact.duplicate(true),
		"room": room,
		"zone_bounds": zone_bounds,
	}


func _valid_damage_payload(payload: Dictionary) -> bool:
	if not _has_only_fields(payload, DAMAGE_PAYLOAD_FIELDS, ["target_ids"]):
		return false
	if (
		typeof(payload.get("amount")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(payload.get("amount", 0.0)))
		or float(payload.get("amount", 0.0)) <= 0.0
		or float(payload.get("amount", 0.0)) > 12.0
		or typeof(payload.get("damage_type")) != TYPE_STRING
		or not DAMAGE_TYPES.has(str(payload.get("damage_type", "")))
		or typeof(payload.get("target_scope")) != TYPE_STRING
		or str(payload.get("target_scope", "")) != "player_in_zone"
		or typeof(payload.get("nonlethal")) != TYPE_BOOL
		or not bool(payload.get("nonlethal", false))
		or typeof(payload.get("minimum_remaining_hp")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(payload.get("minimum_remaining_hp", 0.0)))
		or float(payload.get("minimum_remaining_hp", 0.0)) < 1.0
	):
		return false
	return _valid_target_ids(payload)


func _valid_modifier_payload(payload: Dictionary) -> bool:
	if not _has_only_fields(payload, MODIFIER_PAYLOAD_FIELDS, ["target_ids"]):
		return false
	if (
		typeof(payload.get("modifier_id")) != TYPE_STRING
		or str(payload.get("modifier_id", "")).is_empty()
		or typeof(payload.get("target_scope")) != TYPE_STRING
		or str(payload.get("target_scope", "")) != "player_in_zone"
		or typeof(payload.get("duration_frames")) != TYPE_INT
		or int(payload.get("duration_frames", -1)) < 0
		or typeof(payload.get("operation")) != TYPE_STRING
		or str(payload.get("operation", "")) not in ["apply", "remove"]
		or not payload.get("values") is Dictionary
	):
		return false
	var values := payload["values"] as Dictionary
	if str(payload["operation"]) == "apply" and values.is_empty():
		return false
	if str(payload["operation"]) == "remove" and not values.is_empty():
		return false
	return _valid_target_ids(payload)


func _valid_target_ids(payload: Dictionary) -> bool:
	if not payload.has("target_ids"):
		return true
	if not payload["target_ids"] is Array:
		return false
	var seen: Dictionary = {}
	for target_value: Variant in payload["target_ids"] as Array:
		if (
			typeof(target_value) != TYPE_STRING
			or str(target_value).is_empty()
			or seen.has(str(target_value))
		):
			return false
		seen[str(target_value)] = true
	return true


func _apply_plan(plan: Dictionary) -> bool:
	var fact := plan["fact"] as Dictionary
	var payload := fact["payload"] as Dictionary
	if str(fact["fact_type"]) == "modifier" and str(payload["operation"]) == "remove":
		return bool(_player.call(
			"apply_floor_rule_modifier",
			StringName(str(fact["source_id"])),
			StringName(str(payload["modifier_id"])),
			&"remove",
			{}
		))
	if not _targets_player(payload) or not _player_is_in_zone(
		plan["room"] as Node2D,
		plan["zone_bounds"] as Rect2
	):
		return true
	if str(fact["fact_type"]) == "modifier":
		return bool(_player.call(
			"apply_floor_rule_modifier",
			StringName(str(fact["source_id"])),
			StringName(str(payload["modifier_id"])),
			&"apply",
			(payload["values"] as Dictionary).duplicate(true)
		))
	return _apply_damage(fact, payload, plan["room"] as Node2D)


func _apply_damage(fact: Dictionary, payload: Dictionary, _source: Node2D) -> bool:
	var health := _player.get_node_or_null("HealthComponent")
	if health == null or not health.has_method("lose_health"):
		return false
	var current_hp_value: Variant = health.get("current_hp")
	if typeof(current_hp_value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var multiplier := 1.0
	var multiplier_value: Variant = health.get("damage_received_multiplier")
	if typeof(multiplier_value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(multiplier_value)):
		multiplier = maxf(0.0, float(multiplier_value))
	var minimum_hp := float(payload["minimum_remaining_hp"])
	var amount := minf(
		float(payload["amount"]) * multiplier,
		maxf(0.0, float(current_hp_value) - minimum_hp)
	)
	if amount <= 0.0:
		return true
	var applied_value: Variant = health.call(
		"lose_health",
		amount,
		StringName("%s:%d" % [str(fact["source_id"]), int(fact["runtime_frame"])])
	)
	return (
		typeof(applied_value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(applied_value))
		and float(health.get("current_hp")) >= minimum_hp
	)


func _restore_player(
	health: Node,
	reward_snapshot: Dictionary,
	floor_snapshot: Dictionary
) -> bool:
	var floor_ok := bool(_player.call(
		"restore_floor_rule_effect_snapshot",
		floor_snapshot.duplicate(true)
	))
	var reward_ok := bool(health.call(
		"restore_reward_effect_snapshot",
		reward_snapshot.duplicate(true),
		false
	))
	if not floor_ok or not reward_ok:
		push_error("Floor-rule effect authority rollback failed")
	return floor_ok and reward_ok


func _targets_player(payload: Dictionary) -> bool:
	if not payload.has("target_ids"):
		return true
	return (payload["target_ids"] as Array).has("player")


func _player_is_in_zone(room: Node2D, bounds: Rect2) -> bool:
	return bounds.has_point(room.to_local(_player.global_position))


func _zone_bounds(configuration: Dictionary, zone_id: String) -> Variant:
	var zones_value: Variant = configuration.get("zones")
	if not zones_value is Array:
		return null
	for zone_value: Variant in zones_value as Array:
		if not zone_value is Dictionary:
			return null
		var zone := zone_value as Dictionary
		if str(zone.get("id", "")) != zone_id:
			continue
		var bounds_value: Variant = zone.get("bounds")
		if not bounds_value is Dictionary:
			return null
		var bounds := bounds_value as Dictionary
		for field: String in ["x", "y", "width", "height"]:
			if (
				typeof(bounds.get(field)) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(bounds.get(field, 0.0)))
			):
				return null
		if float(bounds["width"]) <= 0.0 or float(bounds["height"]) <= 0.0:
			return null
		return Rect2(
			float(bounds["x"]),
			float(bounds["y"]),
			float(bounds["width"]),
			float(bounds["height"])
		)
	return null


func _player_contract_is_valid(player: Node) -> bool:
	return (
		player != null
		and is_instance_valid(player)
		and player.has_method("current_run_id")
		and player.has_method("floor_rule_effect_snapshot")
		and player.has_method("restore_floor_rule_effect_snapshot")
		and player.has_method("apply_floor_rule_modifier")
		and player.get_node_or_null("HealthComponent") != null
		and player.get_node("HealthComponent").has_method("reward_effect_snapshot")
		and player.get_node("HealthComponent").has_method("restore_reward_effect_snapshot")
	)


func _room_host_contract_is_valid(room_scene_host: Node) -> bool:
	return (
		room_scene_host != null
		and is_instance_valid(room_scene_host)
		and room_scene_host.has_method("active_room")
	)


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _has_only_fields(
	value: Dictionary,
	required_fields: Array[String],
	optional_fields: Array[String]
) -> bool:
	for field: String in required_fields:
		if not value.has(field):
			return false
	for key_value: Variant in value.keys():
		var field := str(key_value)
		if field not in required_fields and field not in optional_fields:
			return false
	return true
