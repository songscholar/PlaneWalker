class_name RunBuildState
extends RefCounted

const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")

const M1_ARCHETYPE_IDS: Array[String] = [
	"freeze_burst",
	"rewind_echo",
	"accelerated_combo",
]
const M1_COMPATIBLE_MILESTONES: Array[String] = ["M1", "CURRENT", "NEXT"]
const CONTENT_COLLECTIONS := {
	"item": "items",
	"blessing": "blessings",
	"curse": "curses",
	"talent": "talents",
}
const TRANSACTION_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"milestone",
	"archetype_order",
	"items",
	"blessings",
	"curses",
	"talents",
	"reward_history",
	"archetypes",
	"dominant_archetype",
]

var items: Array[String] = []
var blessings: Array[String] = []
var curses: Array[String] = []
var talents: Array[String] = []
var reward_history: Array[Dictionary] = []
var archetypes: Dictionary = {}
var dominant_archetype: String = ""
var milestone: String = "M1"
var _archetype_order: Array[String] = []


func _init() -> void:
	reset()


func reset(p_milestone: String = "M1") -> void:
	items.clear()
	blessings.clear()
	curses.clear()
	talents.clear()
	reward_history.clear()
	milestone = p_milestone
	_archetype_order = (
		M1_ARCHETYPE_IDS.duplicate()
		if M1_COMPATIBLE_MILESTONES.has(milestone)
		else ArchetypeProfileScript.ARCHETYPE_IDS.duplicate()
	)
	archetypes.clear()
	for archetype_id: String in _archetype_order:
		archetypes[archetype_id] = 0
	dominant_archetype = ""


func record_item(reward_data: Dictionary) -> void:
	_apply_typed_definition("item", reward_data)


func record_blessing(blessing_data: Dictionary) -> void:
	_apply_typed_definition("blessing", blessing_data)


func record_curse(curse_data: Dictionary) -> void:
	_apply_typed_definition("curse", curse_data)


func record_talent(talent_data: Dictionary) -> void:
	_apply_typed_definition("talent", talent_data)


func validate_definition(definition: Dictionary) -> Dictionary:
	var content_id := str(definition.get("id", ""))
	if content_id.is_empty():
		return {"ok": false, "field": "definition.id", "reason": "missing"}
	var category := str(definition.get("category", ""))
	if category == "contract" and content_id == "decline_contract":
		return {"ok": true, "field": "", "reason": ""}
	if not CONTENT_COLLECTIONS.has(category):
		return {"ok": false, "field": "definition.category", "reason": "unsupported"}
	if selected_ids().has(content_id):
		return {"ok": false, "field": "definition.id", "reason": "duplicate"}
	var archetype_value: Variant = definition.get("archetype", "")
	if typeof(archetype_value) != TYPE_STRING:
		return {"ok": false, "field": "definition.archetype", "reason": "type"}
	var archetype_id := str(archetype_value)
	if not archetype_id.is_empty() and not _archetype_order.has(archetype_id):
		return {"ok": false, "field": "definition.archetype", "reason": "unknown"}
	return {"ok": true, "field": "", "reason": ""}


func apply_definition(definition: Dictionary) -> Dictionary:
	var validation := validate_definition(definition)
	if not bool(validation.get("ok", false)):
		return validation.duplicate(true)
	var content_id := str(definition.get("id", ""))
	var category := str(definition.get("category", ""))
	if category == "contract":
		return {
			"ok": true,
			"changed": false,
			"content_id": content_id,
			"category": category,
			"archetype": "",
			"dominant_archetype": dominant_archetype,
		}
	var target: Array[String] = get(str(CONTENT_COLLECTIONS[category]))
	target.append(content_id)
	var stored_definition := definition.duplicate(true)
	reward_history.append(stored_definition)
	var archetype_id := str(definition.get("archetype", ""))
	var score_before := 0
	var score_after := 0
	if not archetype_id.is_empty():
		score_before = int(archetypes[archetype_id])
		score_after = score_before + 1
		archetypes[archetype_id] = score_after
		dominant_archetype = _find_dominant_archetype()
	return {
		"ok": true,
		"changed": true,
		"content_id": content_id,
		"category": category,
		"archetype": archetype_id,
		"score_before": score_before,
		"score_after": score_after,
		"dominant_archetype": dominant_archetype,
	}


func selected_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.append_array(items)
	ids.append_array(blessings)
	ids.append_array(curses)
	ids.append_array(talents)
	return ids


func to_dictionary() -> Dictionary:
	return {
		"items": items.duplicate(),
		"blessings": blessings.duplicate(),
		"curses": curses.duplicate(),
		"talents": talents.duplicate(),
		"reward_history": reward_history.duplicate(true),
		"archetypes": archetypes.duplicate(true),
		"dominant_archetype": dominant_archetype,
	}


func transaction_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": milestone,
		"archetype_order": _archetype_order.duplicate(),
		"items": items.duplicate(),
		"blessings": blessings.duplicate(),
		"curses": curses.duplicate(),
		"talents": talents.duplicate(),
		"reward_history": reward_history.duplicate(true),
		"archetypes": archetypes.duplicate(true),
		"dominant_archetype": dominant_archetype,
	}


func can_restore_transaction_snapshot(value: Dictionary) -> bool:
	if value.size() != TRANSACTION_SNAPSHOT_FIELDS.size():
		return false
	for field: String in TRANSACTION_SNAPSHOT_FIELDS:
		if not value.has(field):
			return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != 1
		or typeof(value["milestone"]) != TYPE_STRING
		or not value["archetype_order"] is Array
		or not value["reward_history"] is Array
		or not value["archetypes"] is Dictionary
		or typeof(value["dominant_archetype"]) != TYPE_STRING
	):
		return false
	var expected_order: Array[String] = (
		M1_ARCHETYPE_IDS.duplicate()
		if M1_COMPATIBLE_MILESTONES.has(str(value["milestone"]))
		else ArchetypeProfileScript.ARCHETYPE_IDS.duplicate()
	)
	var restored_order: Array[String] = []
	for archetype_value: Variant in value["archetype_order"]:
		if typeof(archetype_value) != TYPE_STRING:
			return false
		restored_order.append(str(archetype_value))
	if restored_order != expected_order:
		return false
	var selected_categories: Dictionary = {}
	var selected_count := 0
	for category: String in CONTENT_COLLECTIONS:
		var collection := str(CONTENT_COLLECTIONS[category])
		if not value[collection] is Array:
			return false
		for content_id_value: Variant in value[collection]:
			if typeof(content_id_value) != TYPE_STRING or str(content_id_value).is_empty():
				return false
			var content_id := str(content_id_value)
			if selected_categories.has(content_id):
				return false
			selected_categories[content_id] = category
			selected_count += 1
	if (value["reward_history"] as Array).size() != selected_count:
		return false
	var recomputed_archetypes: Dictionary = {}
	for archetype_id: String in expected_order:
		recomputed_archetypes[archetype_id] = 0
	var history_ids: Dictionary = {}
	for history_value: Variant in value["reward_history"]:
		if not history_value is Dictionary:
			return false
		var history := history_value as Dictionary
		if (
			typeof(history.get("id")) != TYPE_STRING
			or str(history["id"]).is_empty()
			or typeof(history.get("category")) != TYPE_STRING
			or typeof(history.get("archetype")) != TYPE_STRING
			or not history.get("effects") is Dictionary
		):
			return false
		var history_id := str(history["id"])
		var history_category := str(history["category"])
		if (
			not CONTENT_COLLECTIONS.has(history_category)
			or not selected_categories.has(history_id)
			or str(selected_categories[history_id]) != history_category
			or history_ids.has(history_id)
		):
			return false
		history_ids[history_id] = true
		var history_archetype := str(history["archetype"])
		if not history_archetype.is_empty():
			if not recomputed_archetypes.has(history_archetype):
				return false
			recomputed_archetypes[history_archetype] = (
				int(recomputed_archetypes[history_archetype]) + 1
			)
	if history_ids.size() != selected_count:
		return false
	for content_id: String in selected_categories:
		if not history_ids.has(content_id):
			return false
	var restored_archetypes := value["archetypes"] as Dictionary
	if restored_archetypes.size() != expected_order.size():
		return false
	var best_id := ""
	var best_count := 0
	for archetype_id: String in expected_order:
		if (
			typeof(restored_archetypes.get(archetype_id)) != TYPE_INT
			or int(restored_archetypes[archetype_id]) != int(recomputed_archetypes[archetype_id])
		):
			return false
		var count := int(restored_archetypes[archetype_id])
		if count > best_count:
			best_id = archetype_id
			best_count = count
	if str(value["dominant_archetype"]) != best_id:
		return false
	return true


func restore_transaction_snapshot(value: Dictionary) -> bool:
	if not can_restore_transaction_snapshot(value):
		return false
	milestone = str(value["milestone"])
	_archetype_order.clear()
	for archetype_value: Variant in value["archetype_order"]:
		_archetype_order.append(str(archetype_value))
	items.assign(value["items"])
	blessings.assign(value["blessings"])
	curses.assign(value["curses"])
	talents.assign(value["talents"])
	reward_history.clear()
	for history_value: Variant in value["reward_history"]:
		reward_history.append((history_value as Dictionary).duplicate(true))
	archetypes = (value["archetypes"] as Dictionary).duplicate(true)
	dominant_archetype = str(value["dominant_archetype"])
	return transaction_snapshot() == value


static func from_run(run_data: Dictionary) -> RefCounted:
	var state = load("res://scripts/progression/run_build_state.gd").new()
	var config: Dictionary = run_data.get("config", {})
	state.reset(str(config.get("milestone", "M1")))
	for reward: Dictionary in run_data.get("rewards", []):
		state.record_item(reward)
	for blessing: Dictionary in run_data.get("blessings", []):
		state.record_blessing(blessing)
	for curse: Dictionary in run_data.get("curses", []):
		state.record_curse(curse)
	for talent: Dictionary in run_data.get("talent_choices", []):
		state.record_talent(talent)
	return state


func _apply_typed_definition(category: String, source: Dictionary) -> void:
	var definition := source.duplicate(true)
	definition["category"] = category
	apply_definition(definition)


func _find_dominant_archetype() -> String:
	var best_id := ""
	var best_count := 0
	for archetype_id: String in _archetype_order:
		var count := int(archetypes.get(archetype_id, 0))
		if count > best_count:
			best_id = archetype_id
			best_count = count
	return best_id
