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
