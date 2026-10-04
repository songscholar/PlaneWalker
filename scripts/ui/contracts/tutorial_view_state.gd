class_name TutorialViewState
extends RefCounted

const Rules := preload("res://scripts/ui/contracts/dungeon_view_state_rules.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Content := preload("res://scripts/onboarding/tutorial_catalog.gd")
const Projector := preload("res://scripts/onboarding/tutorial_projector.gd")
const FIELDS := ["schema_version", "revision", "run_id", "family", "first_time_ability", "suppressed", "guided_selected", "guided_policy_available", "guided_available", "mode_change_available", "training_available", "guided_sequence", "incoming_damage_multiplier", "warning_scale", "ranked_eligible", "lessons", "training_tasks"]
const LESSON_FIELDS := ["lesson_id", "sequence", "name_key", "text_key", "status_key", "recall_available", "skip_available", "requirements", "actions"]
const TASK_FIELDS := ["task_id", "name_key", "text_key", "reward_shards", "claimed", "requirements", "actions"]
const HINT_FIELDS := ["schema_version", "revision", "run_id", "hint_id", "name_key", "text_key", "style", "display_frames", "family", "first_time_ability", "actions"]
const STATUS_KEYS := ["UI_TUTORIAL_READY", "UI_TUTORIAL_LOCKED", "UI_TUTORIAL_DONE", "UI_TUTORIAL_SKIPPED"]


static func validate(value: Variant):
	if not Rules.header(value, FIELDS) or not _input_header(value):
		return Rules.reject(value, "root")
	var state: Dictionary = value
	for field: String in ["suppressed", "guided_selected", "guided_policy_available", "guided_available", "mode_change_available", "training_available", "ranked_eligible"]:
		if not state[field] is bool:
			return Rules.reject(value, field)
	if not Catalog.bounded_int(state.guided_sequence, 1, 4) or state.mode_change_available != (state.training_available and state.guided_policy_available) or state.guided_available != (state.guided_sequence <= 3 and state.mode_change_available):
		return Rules.reject(value, "guided_sequence")
	var index: int = state.guided_sequence - 1
	var damage := 1.0
	var warning := 1.0
	if state.guided_selected:
		if index > 2 or not state.guided_policy_available:
			return Rules.reject(value, "guided_selected")
		damage = [0.8, 0.9, 1.0][index]
		warning = [1.25, 1.10, 1.0][index]
	if not Catalog.finite_number(state.incoming_damage_multiplier, damage, damage) or not Catalog.finite_number(state.warning_scale, warning, warning) or state.ranked_eligible == state.guided_selected:
		return Rules.reject(value, "guided_policy")
	if not state.lessons is Array or state.lessons.size() != 10 or not state.training_tasks is Array or state.training_tasks.size() != 6:
		return Rules.reject(value, "content_count")
	var ids: Array = []
	for position: int in range(10):
		var lesson: Variant = state.lessons[position]
		if not Rules.exact(lesson, LESSON_FIELDS) or not Rules.identifier(lesson.lesson_id) or ids.has(lesson.lesson_id) or not Catalog.bounded_int(lesson.sequence, position + 1, position + 1) or not Rules.key(lesson.name_key) or not Rules.key(lesson.text_key) or lesson.status_key not in STATUS_KEYS or lesson.recall_available != true or not lesson.recall_available is bool or not lesson.skip_available is bool or lesson.skip_available != (lesson.status_key in STATUS_KEYS.slice(0, 2)) or not _requirements(lesson.requirements) or not actions_valid(lesson.actions, state.first_time_ability) or not _actions_match(lesson):
			return Rules.reject(value, "lesson")
		if lesson.status_key == "UI_TUTORIAL_DONE" and not _requirements_satisfied(lesson.requirements):
			return Rules.reject(value, "lesson_progress")
		ids.append(lesson.lesson_id)
	for position: int in range(6):
		var task: Variant = state.training_tasks[position]
		var reward: int = [3, 5, 5, 8, 15, 20][position]
		if not Rules.exact(task, TASK_FIELDS) or task.task_id != "T-%02d" % (position + 1) or not Rules.key(task.name_key) or not Rules.key(task.text_key) or not Catalog.bounded_int(task.reward_shards, reward, reward) or not task.claimed is bool or not _requirements(task.requirements) or not actions_valid(task.actions, state.first_time_ability) or not _actions_match(task):
			return Rules.reject(value, "training_task")
		if task.claimed and not _requirements_satisfied(task.requirements):
			return Rules.reject(value, "training_progress")
	return Rules.accept(state)


static func validate_hint(value: Variant):
	if not Rules.header(value, HINT_FIELDS) or not _input_header(value) or not Rules.identifier(value.hint_id) or not Rules.key(value.name_key) or not Rules.key(value.text_key) or value.style not in ["instant", "status", "context", "hub", "death"] or not Catalog.bounded_int(value.display_frames, 180 if value.style == "instant" else 0, 180 if value.style == "instant" else 0) or not actions_valid(value.actions, value.first_time_ability):
		return Rules.reject(value, "hint")
	return Rules.accept(value)


static func actions_valid(value: Variant, first_time_ability: String) -> bool:
	if not value is Array or value.size() > Content.ACTION_IDS.size():
		return false
	var seen: Array = []
	for action: Variant in value:
		if not Rules.exact(action, ["semantic_action_id", "ability_id", "bindings"]) or action.semantic_action_id not in Content.ACTION_IDS or seen.has(action.semantic_action_id) or action.ability_id != (first_time_ability if action.semantic_action_id == "time_slot_1" else "") or not action.bindings is Array:
			return false
		seen.append(action.semantic_action_id)
		var expected: Array = Projector.INPUT_ACTIONS.get(action.semantic_action_id, [])
		if action.bindings.size() != expected.size():
			return false
		for index: int in range(expected.size()):
			var binding: Variant = action.bindings[index]
			if not Rules.exact(binding, ["action_id", "labels"]) or binding.action_id != expected[index] or not binding.labels is Array or binding.labels.size() > 16:
				return false
			for label: Variant in binding.labels:
				if not label is String or label.is_empty() or label.length() > 128:
					return false
	return true


static func _input_header(value: Dictionary) -> bool:
	return Catalog.bounded_int(value.revision, 0, Catalog.MAX_VALUE) and value.family in ["keyboard_mouse", "controller"] and value.first_time_ability in Catalog.TIME_IDS


static func _requirements(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > Content.ACTION_IDS.size():
		return false
	var seen: Array = []
	for row: Variant in value:
		if not Rules.exact(row, ["action_id", "count", "current", "context_id"]) or row.action_id not in Content.ACTION_IDS or seen.has(row.action_id) or row.context_id not in Content.CONTEXT_IDS or not Catalog.bounded_int(row.count, 1, 100) or not Catalog.bounded_int(row.current, 0, int(row.count)):
			return false
		seen.append(row.action_id)
	return true


static func _actions_match(row: Dictionary) -> bool:
	if row.actions.size() != row.requirements.size():
		return false
	for index: int in range(row.requirements.size()):
		if row.actions[index].semantic_action_id != row.requirements[index].action_id:
			return false
	return true


static func _requirements_satisfied(rows: Array) -> bool:
	for row: Dictionary in rows:
		if row.current != row.count:
			return false
	return true
