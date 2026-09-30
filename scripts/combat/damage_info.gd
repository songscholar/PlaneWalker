class_name DamageInfo
extends RefCounted

enum DamageType { PHYSICAL, TIME, VOID, FIRE, ICE, LIGHTNING }

const PLAN_FIELDS: Array[String] = [
	"run_id",
	"target_id",
	"hostile_source_id",
	"attack_generation",
	"hit_index",
	"action_token",
	"amount",
	"damage_type",
	"source",
	"attacker",
	"can_crit",
	"crit_chance",
	"crit_multiplier",
	"knockback",
	"tags",
	"source_generation",
	"control_effect",
]
const REQUIRED_PLAN_FIELDS: Array[String] = [
	"run_id",
	"target_id",
	"hostile_source_id",
	"attack_generation",
	"action_token",
	"amount",
	"damage_type",
	"tags",
]
const MAX_ID_LENGTH := 64
const MAX_CONTAINER_DEPTH := 8

var _run_id: StringName = &""
var _target_id: StringName = &""
var _hostile_source_id: StringName = &""
var _attack_generation: int = 0
var _hit_index: int = 0
var _action_token: int = 0
var _amount: float = 0.0
var _damage_type: DamageType = DamageType.PHYSICAL
var _source: Node
var _attacker: Node
var _can_crit: bool = true
var _crit_chance: float = 0.0
var _crit_multiplier: float = 1.5
var _knockback: Vector2 = Vector2.ZERO
var _tags: Array[String] = []
var _source_generation: int = 0
var _control_effect: Dictionary = {}
var _valid := false

var run_id: StringName:
	get:
		return _run_id

var target_id: StringName:
	get:
		return _target_id

var hostile_source_id: StringName:
	get:
		return _hostile_source_id

var attack_generation: int:
	get:
		return _attack_generation

var hit_index: int:
	get:
		return _hit_index

var action_token: int:
	get:
		return _action_token

var amount: float:
	get:
		return _amount

var damage_type: DamageType:
	get:
		return _damage_type

var source: Node:
	get:
		return _source

var attacker: Node:
	get:
		return _attacker

var can_crit: bool:
	get:
		return _can_crit

var crit_chance: float:
	get:
		return _crit_chance

var crit_multiplier: float:
	get:
		return _crit_multiplier

var knockback: Vector2:
	get:
		return _knockback

var tags: Array[String]:
	get:
		return _copy_tags(_tags)

var source_generation: int:
	get:
		return _source_generation

var control_effect: Dictionary:
	get:
		return _control_effect.duplicate(true)


func _init(
	p_amount: float = 0.0,
	p_damage_type: DamageType = DamageType.PHYSICAL,
	p_source: Node = null,
	p_attacker: Node = null
) -> void:
	# The positional constructor is a compatibility boundary only. It installs
	# one complete immutable value; subsequent mutation is intentionally absent.
	var legacy := {
		"run_id": &"",
		"target_id": &"",
		"hostile_source_id": &"",
		"attack_generation": 0,
		"hit_index": 0,
		"action_token": 0,
		"amount": p_amount,
		"damage_type": int(p_damage_type),
		"source": p_source,
		"attacker": p_attacker,
		"can_crit": true,
		"crit_chance": 0.0,
		"crit_multiplier": 1.5,
		"knockback": Vector2.ZERO,
		"tags": [],
		"source_generation": 0,
		"control_effect": {},
	}
	if _validated_snapshot(legacy, false).is_empty():
		push_error("DamageInfo legacy constructor rejected invalid input")
		return
	_install_snapshot(legacy)


static func from_plan(plan: Dictionary) -> DamageInfo:
	var normalized := _validated_snapshot(plan, true)
	if normalized.is_empty():
		return null
	var info := DamageInfo.new()
	info._install_snapshot(normalized)
	return info


func is_valid() -> bool:
	return _valid


func copy_for_source(new_source: Node) -> DamageInfo:
	if not _valid:
		return null
	var copied := DamageInfo.new()
	var copied_snapshot := _snapshot_internal()
	copied_snapshot["source"] = new_source
	copied._install_snapshot(copied_snapshot)
	return copied


func snapshot() -> Dictionary:
	return _snapshot_internal().duplicate(true) if _valid else {}


func _install_snapshot(value: Dictionary) -> void:
	_run_id = StringName(str(value["run_id"]))
	_target_id = StringName(str(value["target_id"]))
	_hostile_source_id = StringName(str(value["hostile_source_id"]))
	_attack_generation = int(value["attack_generation"])
	_hit_index = int(value["hit_index"])
	_action_token = int(value["action_token"])
	_amount = float(value["amount"])
	_damage_type = int(value["damage_type"]) as DamageType
	_source = value["source"] as Node
	_attacker = value["attacker"] as Node
	_can_crit = bool(value["can_crit"])
	_crit_chance = float(value["crit_chance"])
	_crit_multiplier = float(value["crit_multiplier"])
	_knockback = value["knockback"] as Vector2
	_tags = _normalized_tags(value["tags"])
	_source_generation = int(value["source_generation"])
	_control_effect = (value["control_effect"] as Dictionary).duplicate(true)
	_valid = true


func _snapshot_internal() -> Dictionary:
	return {
		"run_id": _run_id,
		"target_id": _target_id,
		"hostile_source_id": _hostile_source_id,
		"attack_generation": _attack_generation,
		"hit_index": _hit_index,
		"action_token": _action_token,
		"amount": _amount,
		"damage_type": int(_damage_type),
		"source": _source,
		"attacker": _attacker,
		"can_crit": _can_crit,
		"crit_chance": _crit_chance,
		"crit_multiplier": _crit_multiplier,
		"knockback": _knockback,
		"tags": _copy_tags(_tags),
		"source_generation": _source_generation,
		"control_effect": _control_effect.duplicate(true),
	}


static func _validated_snapshot(source_plan: Dictionary, require_identity: bool) -> Dictionary:
	if source_plan.is_empty() or not _has_only_fields(source_plan, PLAN_FIELDS):
		return {}
	if require_identity:
		for field: String in REQUIRED_PLAN_FIELDS:
			if not source_plan.has(field):
				return {}

	var run_id_value: Variant = source_plan.get("run_id", &"")
	var target_id_value: Variant = source_plan.get("target_id", &"")
	var hostile_source_id_value: Variant = source_plan.get("hostile_source_id", &"")
	if not _valid_id(run_id_value, require_identity):
		return {}
	if not _valid_id(target_id_value, require_identity):
		return {}
	if not _valid_id(hostile_source_id_value, require_identity):
		return {}

	var attack_generation_value: Variant = source_plan.get("attack_generation", 0)
	var hit_index_value: Variant = source_plan.get("hit_index", 0)
	var action_token_value: Variant = source_plan.get("action_token", 0)
	var source_generation_value: Variant = source_plan.get("source_generation", 0)
	if not _nonnegative_int(attack_generation_value):
		return {}
	if not _nonnegative_int(hit_index_value):
		return {}
	if not _nonnegative_int(action_token_value):
		return {}
	if not _nonnegative_int(source_generation_value):
		return {}

	var amount_value: Variant = source_plan.get("amount", 0.0)
	var crit_chance_value: Variant = source_plan.get("crit_chance", 0.0)
	var crit_multiplier_value: Variant = source_plan.get("crit_multiplier", 1.5)
	if not _nonnegative_number(amount_value):
		return {}
	if not _nonnegative_number(crit_chance_value):
		return {}
	if not _nonnegative_number(crit_multiplier_value):
		return {}

	var damage_type_value: Variant = source_plan.get("damage_type", DamageType.PHYSICAL)
	if typeof(damage_type_value) != TYPE_INT:
		return {}
	var damage_type_int := int(damage_type_value)
	if damage_type_int < DamageType.PHYSICAL or damage_type_int > DamageType.LIGHTNING:
		return {}

	var source_value: Variant = source_plan.get("source")
	var attacker_value: Variant = source_plan.get("attacker")
	if source_value != null and not source_value is Node:
		return {}
	if attacker_value != null and not attacker_value is Node:
		return {}
	var can_crit_value: Variant = source_plan.get("can_crit", true)
	if typeof(can_crit_value) != TYPE_BOOL:
		return {}
	var knockback_value: Variant = source_plan.get("knockback", Vector2.ZERO)
	if typeof(knockback_value) != TYPE_VECTOR2 or not _finite_vector2(knockback_value as Vector2):
		return {}
	var tags_value: Variant = source_plan.get("tags", [])
	if not _valid_tags(tags_value):
		return {}
	var control_effect_value: Variant = source_plan.get("control_effect", {})
	if typeof(control_effect_value) != TYPE_DICTIONARY:
		return {}
	if not _valid_container_value(control_effect_value, 0):
		return {}

	return {
		"run_id": StringName(str(run_id_value).strip_edges()),
		"target_id": StringName(str(target_id_value).strip_edges()),
		"hostile_source_id": StringName(str(hostile_source_id_value).strip_edges()),
		"attack_generation": int(attack_generation_value),
		"hit_index": int(hit_index_value),
		"action_token": int(action_token_value),
		"amount": float(amount_value),
		"damage_type": damage_type_int,
		"source": source_value,
		"attacker": attacker_value,
		"can_crit": bool(can_crit_value),
		"crit_chance": float(crit_chance_value),
		"crit_multiplier": float(crit_multiplier_value),
		"knockback": knockback_value,
		"tags": _normalized_tags(tags_value),
		"source_generation": int(source_generation_value),
		"control_effect": (control_effect_value as Dictionary).duplicate(true),
	}


static func _has_only_fields(value: Dictionary, allowed: Array[String]) -> bool:
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return false
		if not allowed.has(str(key)):
			return false
	return true


static func _valid_id(value: Variant, required: bool) -> bool:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return false
	var normalized := str(value).strip_edges()
	if required and normalized.is_empty():
		return false
	return normalized.length() <= MAX_ID_LENGTH


static func _nonnegative_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


static func _nonnegative_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var parsed := float(value)
	return is_finite(parsed) and parsed >= 0.0


static func _finite_vector2(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _valid_tags(value: Variant) -> bool:
	if not value is Array and not value is PackedStringArray:
		return false
	for tag: Variant in value:
		if typeof(tag) != TYPE_STRING and typeof(tag) != TYPE_STRING_NAME:
			return false
		if str(tag).strip_edges().is_empty():
			return false
	return true


static func _normalized_tags(value: Variant) -> Array[String]:
	var normalized: Array[String] = []
	for tag: Variant in value:
		normalized.append(str(tag))
	return normalized


static func _copy_tags(value: Array[String]) -> Array[String]:
	var copied: Array[String] = []
	copied.assign(value)
	return copied


static func _valid_container_value(value: Variant, depth: int) -> bool:
	if depth > MAX_CONTAINER_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_VECTOR2:
			return _finite_vector2(value as Vector2)
		TYPE_VECTOR2I, TYPE_RECT2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
			return true
		TYPE_COLOR:
			var color_value := value as Color
			return (
				is_finite(color_value.r)
				and is_finite(color_value.g)
				and is_finite(color_value.b)
				and is_finite(color_value.a)
			)
		TYPE_VECTOR3:
			var vector3_value := value as Vector3
			return is_finite(vector3_value.x) and is_finite(vector3_value.y) and is_finite(vector3_value.z)
		TYPE_VECTOR4:
			var vector4_value := value as Vector4
			return (
				is_finite(vector4_value.x)
				and is_finite(vector4_value.y)
				and is_finite(vector4_value.z)
				and is_finite(vector4_value.w)
			)
		TYPE_RECT2:
			var rect_value := value as Rect2
			return _finite_vector2(rect_value.position) and _finite_vector2(rect_value.size)
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			for item: Variant in value:
				if not _valid_container_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in (value as Dictionary).keys():
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					return false
				if not _valid_container_value((value as Dictionary)[key], depth + 1):
					return false
			return true
		_:
			return false
