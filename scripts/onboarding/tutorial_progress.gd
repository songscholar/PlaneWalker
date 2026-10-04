class_name TutorialProgress
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Content := preload("res://scripts/onboarding/tutorial_catalog.gd")
const PROGRESS_PREFIX := "onboarding-progress:"
const WATERMARK_PREFIX := "onboarding-watermark:"
const CLAIM_PREFIX := "training-claim:"


static func decode(profile: Dictionary, content: RefCounted) -> Dictionary:
	var validator := Profile.new()
	if profile.is_empty() or content == null or not validator.configure(content.call("meta_catalog"), profile):
		return Candidate.failure(&"PROFILE_INVALID")
	var counters: Dictionary = {}
	var watermarks: Dictionary = {}
	var claims: Array = []
	var guided: Dictionary = {}
	for marker: String in profile.completed_command_ids:
		var parts := marker.split(":")
		if marker.begins_with(PROGRESS_PREFIX):
			if parts.size() == 4 and parts[1] == "guided":
				if not guided.is_empty() or not canonical_positive(parts[2], int(profile.launch_sequence)) or not canonical_positive(parts[3], 3) or int(parts[2]) < int(parts[3]):
					return Candidate.failure(&"TUTORIAL_PROGRESS_INVALID")
				guided = {"launch_sequence": int(parts[2]), "guided_sequence": int(parts[3])}
			elif parts.size() == 4 and parts[1] == "hint":
				var hint: Dictionary = content.call("definition", "hint", parts[2])
				var key := "hint:" + parts[2]
				if hint.is_empty() or counters.has(key) or not canonical_positive(parts[3], int(hint.maximum_displays)) or not profile.tutorial_state.seen_hints.has(parts[2]):
					return Candidate.failure(&"TUTORIAL_PROGRESS_INVALID")
				counters[key] = int(parts[3])
			elif parts.size() == 5 and parts[1] in ["lesson", "task"]:
				var kind := "lesson" if parts[1] == "lesson" else "training_task"
				var row: Dictionary = content.call("definition", kind, parts[2])
				var requirement := requirement_for(row, parts[3])
				var key := "%s:%s:%s" % [parts[1], parts[2], parts[3]]
				if requirement.is_empty() or counters.has(key) or not canonical_positive(parts[4], int(requirement.count)):
					return Candidate.failure(&"TUTORIAL_PROGRESS_INVALID")
				counters[key] = int(parts[4])
			else:
				return Candidate.failure(&"TUTORIAL_PROGRESS_INVALID")
		elif marker.begins_with(WATERMARK_PREFIX):
			if parts.size() != 4 or parts[1] not in Content.CONTEXT_IDS or watermarks.has(parts[1]) or not canonical_positive(parts[2], Catalog.MAX_VALUE) or not canonical_positive(parts[3], Catalog.MAX_VALUE) or parts[1] == "normal_run" and int(parts[2]) > int(profile.launch_sequence):
				return Candidate.failure(&"TUTORIAL_WATERMARK_INVALID")
			watermarks[parts[1]] = {"session_sequence": int(parts[2]), "action_sequence": int(parts[3])}
		elif marker.begins_with(CLAIM_PREFIX):
			if parts.size() != 2 or content.call("definition", "training_task", parts[1]).is_empty() or claims.has(parts[1]):
				return Candidate.failure(&"TRAINING_CLAIM_INVALID")
			claims.append(parts[1])
	for lesson: Dictionary in content.call("definitions", "lesson"):
		var completed: bool = profile.tutorial_state.completed_lessons.has(lesson.lesson_id)
		var skipped: bool = profile.tutorial_state.skipped_lessons.has(lesson.lesson_id)
		if completed and skipped or not _objective_consistent(lesson, "lesson", lesson.lesson_id, completed, skipped, counters, watermarks):
			return Candidate.failure(&"TUTORIAL_PROGRESS_INVALID")
		if completed or has_objective_counters(counters, "lesson", lesson.lesson_id):
			for prerequisite: String in lesson.prerequisite_lesson_ids:
				if not profile.tutorial_state.completed_lessons.has(prerequisite) and not profile.tutorial_state.skipped_lessons.has(prerequisite):
					return Candidate.failure(&"TUTORIAL_PREREQUISITE_INVALID")
	for task: Dictionary in content.call("definitions", "training_task"):
		if not _objective_consistent(task, "task", task.task_id, claims.has(task.task_id), false, counters, watermarks):
			return Candidate.failure(&"TRAINING_PROGRESS_INVALID")
	for key: String in counters:
		if key.begins_with("hint:") and watermarks.is_empty():
			return Candidate.failure(&"TUTORIAL_WATERMARK_INVALID")
	if not guided.is_empty() and guided.guided_sequence != profile.tutorial_state.guided_runs_completed:
		return Candidate.failure(&"TUTORIAL_GUIDED_INVALID")
	return Candidate.success({"counters": counters, "watermarks": watermarks, "training_claims": claims, "guided": guided})


static func canonical_positive(value: String, maximum: int) -> bool:
	return value.is_valid_int() and str(value.to_int()) == value and value.to_int() >= 1 and value.to_int() <= maximum


static func requirement_for(row: Dictionary, action_id: String) -> Dictionary:
	for requirement: Dictionary in row.get("receipt_requirements", []):
		if requirement.action_id == action_id:
			return requirement.duplicate(true)
	return {}


static func has_objective_counters(counters: Dictionary, kind: String, id: String) -> bool:
	for key: String in counters:
		if key.begins_with("%s:%s:" % [kind, id]):
			return true
	return false


static func replace_marker(candidate: Dictionary, prefix: String, marker: String = "") -> void:
	var retained: Array = []
	for source: String in candidate.completed_command_ids:
		if not source.begins_with(prefix):
			retained.append(source)
	if not marker.is_empty():
		retained.append(marker)
	retained.sort()
	candidate.completed_command_ids = retained


static func _objective_consistent(row: Dictionary, kind: String, id: String, completed: bool, skipped: bool, counters: Dictionary, watermarks: Dictionary) -> bool:
	var any_counter := has_objective_counters(counters, kind, id)
	if skipped:
		return not any_counter
	if not any_counter:
		return true
	var full := true
	for requirement: Dictionary in row.receipt_requirements:
		if not watermarks.has(requirement.context_id):
			return false
		full = full and counters.get("%s:%s:%s" % [kind, id, requirement.action_id], 0) == int(requirement.count)
	return full == completed
