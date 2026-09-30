class_name DamageResolution
extends RefCounted

const CONTEXT_FIELDS: Array[String] = [
	"run_id",
	"target_id",
	"hostile_source_id",
	"attack_generation",
	"hit_index",
	"action_token",
	"source_generation",
	"original_amount",
	"post_weapon_defense_amount",
	"post_character_defense_amount",
	"post_accessibility_amount",
	"post_defense_amount",
	"guard_kind",
	"irreversible",
	"tags",
]
const MAX_ID_LENGTH := 64

var _snapshot: Dictionary = {}


static func prevented(reason: StringName, context: Dictionary) -> DamageResolution:
	if str(reason).strip_edges().is_empty():
		return null
	var normalized := _validated_context(context)
	if normalized.is_empty():
		return null
	var resolution := new()
	resolution._install(normalized, 0.0, true, reason)
	return resolution


static func applied(final_amount: float, context: Dictionary) -> DamageResolution:
	if not is_finite(final_amount) or final_amount <= 0.0:
		return null
	var normalized := _validated_context(context)
	if normalized.is_empty():
		return null
	if not is_equal_approx(float(normalized["post_defense_amount"]), final_amount):
		return null
	var resolution := new()
	resolution._install(normalized, final_amount, false, &"")
	return resolution


func is_prevented() -> bool:
	return bool(_snapshot.get("prevented", false))


func finalized_damage() -> float:
	return float(_snapshot.get("finalized_damage", 0.0))


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _install(context: Dictionary, final_amount: float, was_prevented: bool, reason: StringName) -> void:
	var frozen_tags: Array[String] = _normalized_tags(context["tags"])
	var material := {
		"run_id": StringName(str(context["run_id"])),
		"target_id": StringName(str(context["target_id"])),
		"hostile_source_id": StringName(str(context["hostile_source_id"])),
		"attack_generation": int(context["attack_generation"]),
		"hit_index": int(context["hit_index"]),
		"action_token": int(context["action_token"]),
		"source_generation": int(context["source_generation"]),
		"original_amount": float(context["original_amount"]),
		"post_weapon_defense_amount": float(context["post_weapon_defense_amount"]),
		"post_character_defense_amount": float(context["post_character_defense_amount"]),
		"post_accessibility_amount": float(context["post_accessibility_amount"]),
		"post_defense_amount": float(context["post_defense_amount"]),
		"finalized_damage": final_amount,
		"prevented": was_prevented,
		"prevent_reason": reason,
		"guard_kind": StringName(str(context["guard_kind"])),
		"irreversible": bool(context["irreversible"]),
		"tags": frozen_tags,
	}
	var resolution_id := StringName("damage:%s" % _canonical_digest(material))
	_snapshot = {
		"resolution_id": resolution_id,
		"run_id": material["run_id"],
		"target_id": material["target_id"],
		"hostile_source_id": material["hostile_source_id"],
		"attack_generation": material["attack_generation"],
		"action_token": material["action_token"],
		"original_amount": material["original_amount"],
		"post_weapon_defense_amount": material["post_weapon_defense_amount"],
		"post_character_defense_amount": material["post_character_defense_amount"],
		"post_accessibility_amount": material["post_accessibility_amount"],
		"post_defense_amount": material["post_defense_amount"],
		"finalized_damage": material["finalized_damage"],
		"prevented": material["prevented"],
		"prevent_reason": material["prevent_reason"],
		"guard_kind": material["guard_kind"],
		"irreversible": material["irreversible"],
		"tags": _copy_tags(frozen_tags),
	}


static func _validated_context(value: Dictionary) -> Dictionary:
	if value.size() != CONTEXT_FIELDS.size():
		return {}
	for field: String in CONTEXT_FIELDS:
		if not value.has(field):
			return {}
	for key: Variant in value.keys():
		if (typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME) or not CONTEXT_FIELDS.has(str(key)):
			return {}
	if not _valid_id(value["run_id"], true):
		return {}
	if not _valid_id(value["target_id"], true):
		return {}
	if not _valid_id(value["hostile_source_id"], true):
		return {}
	if typeof(value["attack_generation"]) != TYPE_INT or int(value["attack_generation"]) < 0:
		return {}
	if typeof(value["hit_index"]) != TYPE_INT or int(value["hit_index"]) < 0:
		return {}
	if typeof(value["action_token"]) != TYPE_INT or int(value["action_token"]) < 0:
		return {}
	if typeof(value["source_generation"]) != TYPE_INT or int(value["source_generation"]) < 0:
		return {}
	for field: String in [
		"original_amount",
		"post_weapon_defense_amount",
		"post_character_defense_amount",
		"post_accessibility_amount",
		"post_defense_amount",
	]:
		if not _nonnegative_number(value[field]):
			return {}
	if not _valid_id(value["guard_kind"], false):
		return {}
	if typeof(value["irreversible"]) != TYPE_BOOL:
		return {}
	if not _valid_tags(value["tags"]):
		return {}
	return {
		"run_id": StringName(str(value["run_id"]).strip_edges()),
		"target_id": StringName(str(value["target_id"]).strip_edges()),
		"hostile_source_id": StringName(str(value["hostile_source_id"]).strip_edges()),
		"attack_generation": int(value["attack_generation"]),
		"hit_index": int(value["hit_index"]),
		"action_token": int(value["action_token"]),
		"source_generation": int(value["source_generation"]),
		"original_amount": float(value["original_amount"]),
		"post_weapon_defense_amount": float(value["post_weapon_defense_amount"]),
		"post_character_defense_amount": float(value["post_character_defense_amount"]),
		"post_accessibility_amount": float(value["post_accessibility_amount"]),
		"post_defense_amount": float(value["post_defense_amount"]),
		"guard_kind": StringName(str(value["guard_kind"]).strip_edges()),
		"irreversible": bool(value["irreversible"]),
		"tags": _normalized_tags(value["tags"]),
	}


static func _canonical_digest(value: Dictionary) -> String:
	var ordered_values: Array[Variant] = [
		str(value["run_id"]),
		str(value["target_id"]),
		str(value["hostile_source_id"]),
		int(value["attack_generation"]),
		int(value["hit_index"]),
		int(value["action_token"]),
		int(value["source_generation"]),
		float(value["original_amount"]),
		float(value["post_weapon_defense_amount"]),
		float(value["post_character_defense_amount"]),
		float(value["post_accessibility_amount"]),
		float(value["post_defense_amount"]),
		float(value["finalized_damage"]),
		bool(value["prevented"]),
		str(value["prevent_reason"]),
		str(value["guard_kind"]),
		bool(value["irreversible"]),
		value["tags"],
	]
	return JSON.stringify(ordered_values, "", false).sha256_text()


static func _valid_id(value: Variant, required: bool) -> bool:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return false
	var normalized := str(value).strip_edges()
	if required and normalized.is_empty():
		return false
	return normalized.length() <= MAX_ID_LENGTH


static func _nonnegative_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var parsed := float(value)
	return is_finite(parsed) and parsed >= 0.0


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
