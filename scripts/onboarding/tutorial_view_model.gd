class_name TutorialViewModel
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Content := preload("res://scripts/onboarding/tutorial_catalog.gd")
const Progress := preload("res://scripts/onboarding/tutorial_progress.gd")
const Projector := preload("res://scripts/onboarding/tutorial_projector.gd")
const Contract := preload("res://scripts/ui/contracts/tutorial_view_state.gd")
var _content: RefCounted
var _projector: RefCounted


func configure(entries: Array, meta_catalog: RefCounted, input_service: RefCounted) -> Dictionary:
	_content = null
	_projector = null
	var content := Content.new()
	var projector := Projector.new()
	if not content.configure(entries, meta_catalog).ok or not projector.configure(input_service).ok:
		return Candidate.failure(&"TUTORIAL_VIEW_CONFIGURATION_INVALID")
	_content = content
	_projector = projector
	return Candidate.success()


func project(profile: Dictionary, profile_id: String, family: String, first_time_ability: String, guided_selected: bool = false) -> Dictionary:
	if _content == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	var decoded := Progress.decode(profile, _content)
	if not decoded.ok or not Catalog.stable_id(profile_id):
		return Candidate.failure(&"TUTORIAL_VIEW_INVALID")
	var sequence: int = int(profile.tutorial_state.guided_runs_completed) + 1
	var policy: Dictionary = _content.definition("assisted_run", str(sequence))
	if guided_selected and policy.is_empty():
		return Candidate.failure(&"GUIDED_PROGRAM_COMPLETE")
	var mode_available: bool = profile.active_launch_receipt.is_empty()
	var state := {"schema_version": 1, "revision": int(profile.revision), "run_id": profile_id, "family": family, "first_time_ability": first_time_ability, "suppressed": profile.tutorial_state.suppressed, "guided_selected": guided_selected, "guided_available": not policy.is_empty() and mode_available, "mode_change_available": mode_available, "training_available": mode_available, "guided_sequence": sequence, "incoming_damage_multiplier": float(policy.incoming_damage_multiplier) if guided_selected else 1.0, "warning_scale": float(policy.warning_scale) if guided_selected else 1.0, "ranked_eligible": not guided_selected, "lessons": [], "training_tasks": []}
	var lessons: Array = _content.definitions("lesson")
	lessons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.sequence < b.sequence)
	for lesson: Dictionary in lessons:
		var complete: bool = profile.tutorial_state.completed_lessons.has(lesson.lesson_id)
		var skipped: bool = profile.tutorial_state.skipped_lessons.has(lesson.lesson_id)
		var status := "UI_TUTORIAL_READY"
		for prerequisite: String in lesson.prerequisite_lesson_ids:
			if not profile.tutorial_state.completed_lessons.has(prerequisite) and not profile.tutorial_state.skipped_lessons.has(prerequisite):
				status = "UI_TUTORIAL_LOCKED"
		if complete:
			status = "UI_TUTORIAL_DONE"
		elif skipped:
			status = "UI_TUTORIAL_SKIPPED"
		var requirements := _requirements(lesson, "lesson", lesson.lesson_id, complete, decoded.context.counters)
		var actions: Dictionary = _projector.project(_action_ids(requirements), family, first_time_ability)
		if not actions.ok:
			return actions
		state.lessons.append({"lesson_id": lesson.lesson_id, "sequence": int(lesson.sequence), "name_key": lesson.name_key, "text_key": lesson.text_key, "status_key": status, "recall_available": true, "skip_available": not complete and not skipped, "requirements": requirements, "actions": actions.context.actions})
	for task: Dictionary in _content.definitions("training_task"):
		var claimed: bool = decoded.context.training_claims.has(task.task_id)
		var requirements := _requirements(task, "task", task.task_id, claimed, decoded.context.counters)
		var actions: Dictionary = _projector.project(_action_ids(requirements), family, first_time_ability)
		if not actions.ok:
			return actions
		state.training_tasks.append({"task_id": task.task_id, "name_key": task.name_key, "text_key": task.text_key, "reward_shards": int(task.reward.chronos_shards), "claimed": claimed, "requirements": requirements, "actions": actions.context.actions})
	var validated = Contract.validate(state)
	return Candidate.success({"view_state": state.duplicate(true)}) if validated.ok else Candidate.failure(&"TUTORIAL_VIEW_INVALID", validated.context)


func project_hint(hint: Dictionary, revision: int, run_id: String, family: String, first_time_ability: String) -> Dictionary:
	if _content == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	if not hint.get("hint_id") is String or hint != _content.definition("hint", hint.hint_id):
		return Candidate.failure(&"TUTORIAL_HINT_INVALID")
	var actions: Dictionary = _projector.project(hint.semantic_action_ids, family, first_time_ability)
	if not actions.ok:
		return actions
	var state := {"schema_version": 1, "revision": revision, "run_id": run_id, "hint_id": hint.hint_id, "name_key": hint.name_key, "text_key": hint.text_key, "style": hint.style, "display_frames": int(hint.display_frames), "family": family, "first_time_ability": first_time_ability, "actions": actions.context.actions}
	var validated = Contract.validate_hint(state)
	return Candidate.success({"view_state": state.duplicate(true)}) if validated.ok else Candidate.failure(&"TUTORIAL_HINT_INVALID", validated.context)


func _requirements(row: Dictionary, kind: String, id: String, complete: bool, counters: Dictionary) -> Array:
	var result: Array = []
	for authored: Dictionary in row.receipt_requirements:
		var requirement := authored.duplicate(true)
		requirement.count = int(requirement.count)
		requirement.current = requirement.count if complete else int(counters.get("%s:%s:%s" % [kind, id, requirement.action_id], 0))
		result.append(requirement)
	return result


func _action_ids(requirements: Array) -> Array:
	var result: Array = []
	for row: Dictionary in requirements:
		result.append(row.action_id)
	return result
