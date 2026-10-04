class_name TutorialCatalog
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const COMMON_FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "effects", "definition_kind", "text_key"]
const KIND_FIELDS := {
	"lesson": ["lesson_id", "sequence", "trigger_id", "prerequisite_lesson_ids", "receipt_requirements", "repeatable", "skippable", "reward"],
	"hint": ["hint_id", "trigger_id", "style", "maximum_displays", "display_frames", "semantic_action_ids", "suppressible"],
	"training_task": ["task_id", "receipt_requirements", "repeatable", "skippable", "reward", "reward_once"],
	"assisted_run": ["sequence", "incoming_damage_multiplier", "warning_scale", "ranked_eligible", "default_enabled"],
}
const COUNTS := {"lesson": 10, "hint": 15, "training_task": 6, "assisted_run": 3}
const ACTION_IDS := ["move", "dash", "weapon_primary", "time_slot_1", "reward_select", "merchant_purchase", "hostile_warning_observed", "boss_conversion", "build_open", "event_choice", "forge_upgrade", "launch_loadout_change", "interact", "weapon_skill"]
const CONTEXT_IDS := ["normal_run", "hub", "training_drill"]

var _meta: RefCounted
var _rows: Dictionary = {}
var _by_kind: Dictionary = {}
var _triggers: Array = []


func configure(entries: Array, meta_catalog: RefCounted) -> Dictionary:
	_meta = null
	_rows.clear()
	_by_kind.clear()
	_triggers.clear()
	var validator := Profile.new()
	if entries.size() != 34 or not validator.configure(meta_catalog):
		return Candidate.failure(&"TUTORIAL_CONTENT_INVALID")
	var rows: Dictionary = {}
	var by_kind: Dictionary = {}
	var triggers: Array = []
	for kind: String in COUNTS:
		by_kind[kind] = []
	for row: Variant in entries:
		if not row is Dictionary or row.get("definition_kind") not in KIND_FIELDS or not Catalog.exact_fields(row, COMMON_FIELDS + KIND_FIELDS[row.definition_kind]) or not _common_valid(row) or not _definition_valid(row, meta_catalog):
			return Candidate.failure(&"TUTORIAL_CONTENT_INVALID")
		var kind: String = row.definition_kind
		var id: String = str(int(row.sequence)) if kind == "assisted_run" else str(row.get({"lesson": "lesson_id", "hint": "hint_id", "training_task": "task_id"}[kind]))
		if rows.has(kind + ":" + id):
			return Candidate.failure(&"TUTORIAL_CONTENT_INVALID", {"id": row.id})
		rows[kind + ":" + id] = row.duplicate(true)
		by_kind[kind].append(id)
		if row.has("trigger_id") and not triggers.has(row.trigger_id):
			triggers.append(row.trigger_id)
	for kind: String in COUNTS:
		if by_kind[kind].size() != COUNTS[kind]:
			return Candidate.failure(&"TUTORIAL_COUNT_INVALID")
		by_kind[kind].sort()
	var sequences: Array = []
	for id: String in by_kind.lesson:
		var lesson: Dictionary = rows["lesson:" + id]
		if sequences.has(lesson.sequence):
			return Candidate.failure(&"TUTORIAL_SEQUENCE_INVALID")
		sequences.append(lesson.sequence)
		for prerequisite: String in lesson.prerequisite_lesson_ids:
			if not rows.has("lesson:" + prerequisite) or rows["lesson:" + prerequisite].sequence >= lesson.sequence:
				return Candidate.failure(&"TUTORIAL_PREREQUISITE_INVALID")
	_meta = meta_catalog
	_rows = rows
	_by_kind = by_kind
	_triggers = triggers
	return Candidate.success()


func definition(kind: String, id: String) -> Dictionary:
	return (_rows.get(kind + ":" + id, {}) as Dictionary).duplicate(true)


func definitions(kind: String) -> Array:
	var rows: Array = []
	for id: String in _by_kind.get(kind, []):
		rows.append(definition(kind, id))
	return rows


func has_trigger(id: String) -> bool:
	return _triggers.has(id)


func meta_catalog() -> RefCounted:
	return _meta


func _definition_valid(row: Dictionary, meta: RefCounted) -> bool:
	match row.definition_kind:
		"lesson":
			return Catalog.stable_id(row.lesson_id) and meta.call("has_reference", "tutorial_lesson", row.lesson_id) and row.id == "lesson_" + str(row.lesson_id) and Catalog.bounded_int(row.sequence, 1, 10) and Catalog.stable_id(row.trigger_id) and _stable_list(row.prerequisite_lesson_ids, 10) and _requirements_valid(row.receipt_requirements, "normal_run" if row.sequence <= 8 else "hub") and row.repeatable is bool and row.repeatable and row.skippable is bool and row.skippable and _reward_valid(row.reward, 0)
		"hint":
			return meta.call("has_reference", "tutorial_hint", str(row.hint_id)) and row.id == "hint_" + str(row.hint_id).to_lower().replace("-", "_") and Catalog.stable_id(row.trigger_id) and row.style in ["instant", "status", "context", "hub", "death"] and Catalog.bounded_int(row.maximum_displays, 1, 5) and Catalog.bounded_int(row.display_frames, 180 if row.style == "instant" else 0, 180 if row.style == "instant" else 0) and _stable_list(row.semantic_action_ids, ACTION_IDS.size(), ACTION_IDS) and row.suppressible is bool and row.suppressible
		"training_task":
			var ids: Array = []
			for index: int in range(1, 7):
				ids.append("T-%02d" % index)
			return row.task_id in ids and meta.call("has_reference", "training_task", str(row.task_id)) and row.id == "training_" + str(row.task_id).to_lower().replace("-", "_") and _requirements_valid(row.receipt_requirements, "training_drill") and row.repeatable is bool and row.repeatable and row.skippable is bool and row.skippable and row.reward_once is bool and row.reward_once and _reward_valid(row.reward, [3, 5, 5, 8, 15, 20][ids.find(row.task_id)])
		"assisted_run":
			if not Catalog.bounded_int(row.sequence, 1, 3):
				return false
			var index := int(row.sequence) - 1
			return row.id == "assisted_run_" + str(int(row.sequence)) and Catalog.finite_number(row.incoming_damage_multiplier, [0.8, 0.9, 1.0][index], [0.8, 0.9, 1.0][index]) and Catalog.finite_number(row.warning_scale, [1.25, 1.10, 1.0][index], [1.25, 1.10, 1.0][index]) and row.ranked_eligible is bool and not row.ranked_eligible and row.default_enabled is bool and not row.default_enabled
	return false


func _requirements_valid(value: Variant, context: String) -> bool:
	if not value is Array or value.is_empty() or value.size() > ACTION_IDS.size():
		return false
	var seen: Array = []
	for requirement: Variant in value:
		if not Catalog.exact_fields(requirement, ["action_id", "count", "context_id"]) or requirement.action_id not in ACTION_IDS or seen.has(requirement.action_id) or not Catalog.bounded_int(requirement.count, 1, 100) or requirement.context_id != context:
			return false
		seen.append(requirement.action_id)
	return true


func _reward_valid(value: Variant, shards: int) -> bool:
	return Catalog.exact_fields(value, ["chronos_shards", "existential_imprints"]) and Catalog.bounded_int(value.chronos_shards, shards, shards) and Catalog.bounded_int(value.existential_imprints, 0, 0)


func _common_valid(row: Dictionary) -> bool:
	return row.category == "tutorial_definition" and Catalog.stable_id(row.id) and Catalog.bounded_int(row.schema_version, 1, 1) and _text_key(row.name_key) and _text_key(row.description_key) and _text_key(row.text_key) and row.availability == ["LAUNCH", "EXPANSION"] and row.tags == ["launch", "hub"] and row.compatibility is Dictionary and row.compatibility.is_empty() and row.effects is Dictionary and row.effects.is_empty()


func _stable_list(value: Variant, maximum: int, allowed: Array = []) -> bool:
	if not value is Array or value.size() > maximum:
		return false
	var seen: Array = []
	for id: Variant in value:
		if not Catalog.stable_id(id) or seen.has(id) or not allowed.is_empty() and id not in allowed:
			return false
		seen.append(id)
	return true


func _text_key(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 96:
		return false
	var expression := RegEx.new()
	expression.compile("^[A-Z][A-Z0-9_]*$")
	return expression.search(value) != null
