class_name TutorialProjector
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Content := preload("res://scripts/onboarding/tutorial_catalog.gd")
const INPUT_ACTIONS := {
	"move": ["move_up", "move_down", "move_left", "move_right"],
	"dash": ["dash"], "weapon_primary": ["weapon_primary"],
	"weapon_skill": ["weapon_skill"], "time_slot_1": ["time_slot_1"],
	"interact": ["interact"],
}

var _input: RefCounted


func configure(input_service: RefCounted) -> Dictionary:
	_input = null
	if input_service == null or not input_service.has_method("binding_labels"):
		return Candidate.failure(&"INPUT_SERVICE_INVALID")
	_input = input_service
	return Candidate.success()


func project(semantic_action_ids: Array, family: String, first_time_ability: String) -> Dictionary:
	if _input == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	if family not in ["keyboard_mouse", "controller"] or first_time_ability not in Catalog.TIME_IDS or semantic_action_ids.size() > Content.ACTION_IDS.size():
		return Candidate.failure(&"TUTORIAL_PROJECTION_INVALID")
	var actions: Array = []
	var seen: Array = []
	for semantic: Variant in semantic_action_ids:
		if semantic not in Content.ACTION_IDS or seen.has(semantic):
			return Candidate.failure(&"TUTORIAL_PROJECTION_INVALID")
		seen.append(semantic)
		var bindings: Array = []
		for action: String in INPUT_ACTIONS.get(semantic, []):
			var labels: Dictionary = _input.call("binding_labels", StringName(action))
			if not Catalog.exact_fields(labels, ["keyboard_mouse", "controller"]) or not labels[family] is Array:
				return Candidate.failure(&"INPUT_LABELS_INVALID")
			for label: Variant in labels[family]:
				if not label is String or label.is_empty():
					return Candidate.failure(&"INPUT_LABELS_INVALID")
			bindings.append({"action_id": action, "labels": labels[family].duplicate(true)})
		actions.append({"semantic_action_id": semantic, "ability_id": first_time_ability if semantic == "time_slot_1" else "", "bindings": bindings})
	return Candidate.success({"family": family, "actions": actions})
