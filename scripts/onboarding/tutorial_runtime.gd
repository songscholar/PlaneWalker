class_name TutorialRuntime
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Content := preload("res://scripts/onboarding/tutorial_catalog.gd")
const Progress := preload("res://scripts/onboarding/tutorial_progress.gd")
const RECEIPT_FIELDS := ["run_id", "session_sequence", "action_sequence", "action_id", "context_id", "trigger_ids"]

var _content: RefCounted


func configure(entries: Array, meta_catalog: RefCounted) -> Dictionary:
	_content = null
	var content := Content.new()
	var configured := content.configure(entries, meta_catalog)
	if configured.ok:
		_content = content
	return configured


func progress_view(profile: Dictionary) -> Dictionary:
	if _content == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	return Progress.decode(profile, _content)


func prepare_observation(profile: Dictionary, receipt: Dictionary, expected_revision: int) -> Dictionary:
	var decoded := _ready_profile(profile, expected_revision)
	if not decoded.ok:
		return decoded
	if not _receipt_valid(profile, receipt, decoded.context.watermarks):
		return Candidate.failure(&"TUTORIAL_RECEIPT_INVALID")
	var candidate := profile.duplicate(true)
	var counters: Dictionary = decoded.context.counters.duplicate(true)
	var completed_lessons: Array = []
	var completed_tasks: Array = []
	for lesson: Dictionary in _content.call("definitions", "lesson"):
		if profile.tutorial_state.completed_lessons.has(lesson.lesson_id) or profile.tutorial_state.skipped_lessons.has(lesson.lesson_id) or not _prerequisites_met(profile, lesson):
			continue
		if _advance(candidate, counters, lesson, "lesson", lesson.lesson_id, receipt):
			candidate.tutorial_state.completed_lessons.append(lesson.lesson_id)
			candidate.tutorial_state.completed_lessons.sort()
			completed_lessons.append(lesson.lesson_id)
	for task: Dictionary in _content.call("definitions", "training_task"):
		if decoded.context.training_claims.has(task.task_id):
			continue
		if _advance(candidate, counters, task, "task", task.task_id, receipt):
			var reward: int = task.reward.chronos_shards
			if candidate.chronos_shards > Catalog.MAX_VALUE - reward:
				return Candidate.failure(&"TRANSACTION_LIMIT")
			candidate.chronos_shards += reward
			candidate.completed_command_ids.append(Progress.CLAIM_PREFIX + str(task.task_id))
			completed_tasks.append(task.task_id)
	var hints: Array = []
	if not profile.tutorial_state.suppressed:
		for hint: Dictionary in _content.call("definitions", "hint"):
			var key := "hint:" + str(hint.hint_id)
			var displays: int = counters.get(key, int(hint.maximum_displays) if profile.tutorial_state.seen_hints.has(hint.hint_id) else 0)
			if not receipt.trigger_ids.has(hint.trigger_id) or displays >= int(hint.maximum_displays):
				continue
			displays += 1
			Progress.replace_marker(candidate, Progress.PROGRESS_PREFIX + key + ":", Progress.PROGRESS_PREFIX + key + ":" + str(displays))
			if not candidate.tutorial_state.seen_hints.has(hint.hint_id):
				candidate.tutorial_state.seen_hints.append(hint.hint_id)
				candidate.tutorial_state.seen_hints.sort()
			hints.append(hint)
	var prefix := Progress.WATERMARK_PREFIX + str(receipt.context_id) + ":"
	Progress.replace_marker(candidate, prefix, prefix + str(int(receipt.session_sequence)) + ":" + str(int(receipt.action_sequence)))
	return _finish(candidate, {"hints": hints, "completed_lessons": completed_lessons, "completed_tasks": completed_tasks})


func prepare_command(profile: Dictionary, command: Dictionary, expected_revision: int) -> Dictionary:
	var decoded := _ready_profile(profile, expected_revision)
	if not decoded.ok:
		return decoded
	var fields: Array = {"tutorial_skip": ["command_id", "kind", "lesson_id"], "tutorial_suppress": ["command_id", "kind", "suppressed"]}.get(command.get("kind"), [])
	if fields.is_empty():
		return Candidate.failure(&"COMMAND_INVALID")
	var validated := Candidate.validate(profile, _content.call("meta_catalog"), command, fields, expected_revision)
	if not validated.ok:
		return validated
	var candidate := profile.duplicate(true)
	if command.kind == "tutorial_skip":
		if not command.lesson_id is String or _content.call("definition", "lesson", command.lesson_id).is_empty() or profile.tutorial_state.completed_lessons.has(command.lesson_id) or profile.tutorial_state.skipped_lessons.has(command.lesson_id):
			return Candidate.failure(&"TUTORIAL_SKIP_INVALID")
		candidate.tutorial_state.skipped_lessons.append(command.lesson_id)
		candidate.tutorial_state.skipped_lessons.sort()
		Progress.replace_marker(candidate, Progress.PROGRESS_PREFIX + "lesson:" + command.lesson_id + ":")
	else:
		if not command.suppressed is bool or command.suppressed == profile.tutorial_state.suppressed:
			return Candidate.failure(&"TUTORIAL_SUPPRESSION_INVALID")
		candidate.tutorial_state.suppressed = command.suppressed
	candidate.completed_command_ids.append(command.command_id)
	return _finish(candidate)


func replay(lesson_id: String) -> Dictionary:
	if _content == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	var lesson: Dictionary = _content.call("definition", "lesson", lesson_id)
	return Candidate.failure(&"LESSON_UNKNOWN") if lesson.is_empty() else Candidate.success({"lesson": lesson})


func guided_launch_projection(profile: Dictionary, enabled: bool) -> Dictionary:
	var decoded := progress_view(profile)
	if not decoded.ok:
		return decoded
	var projection := {"assisted": false, "ranked_eligible": true, "incoming_damage_multiplier": 1.0, "warning_scale": 1.0, "guided_sequence": 0}
	if enabled:
		var sequence := int(profile.tutorial_state.guided_runs_completed) + 1
		var row: Dictionary = _content.call("definition", "assisted_run", str(sequence))
		if row.is_empty():
			return Candidate.failure(&"GUIDED_PROGRAM_COMPLETE")
		projection = {"assisted": true, "ranked_eligible": row.ranked_eligible, "incoming_damage_multiplier": float(row.incoming_damage_multiplier), "warning_scale": float(row.warning_scale), "guided_sequence": sequence}
	return Candidate.success({"projection": projection})


func prepare_guided_completion(profile: Dictionary, receipt: Dictionary, expected_revision: int) -> Dictionary:
	var decoded := _ready_profile(profile, expected_revision)
	if not decoded.ok:
		return decoded
	if not Catalog.exact_fields(receipt, ["run_id", "launch_sequence", "guided_sequence", "terminal_reason"]) or not Catalog.stable_id(receipt.run_id) or not Catalog.bounded_int(receipt.launch_sequence, 1, Catalog.MAX_VALUE) or not Catalog.bounded_int(receipt.guided_sequence, 1, 3) or receipt.guided_sequence != int(profile.tutorial_state.guided_runs_completed) + 1 or receipt.terminal_reason not in ["death", "victory", "abandon"]:
		return Candidate.failure(&"GUIDED_RECEIPT_INVALID")
	var native: Dictionary = profile.last_settlement_receipt
	if not profile.active_launch_receipt.is_empty() or native.is_empty() or native.sequence != receipt.launch_sequence or native.run_id != receipt.run_id or native.terminal_reason != receipt.terminal_reason or not decoded.context.guided.is_empty() and receipt.launch_sequence <= decoded.context.guided.launch_sequence:
		return Candidate.failure(&"GUIDED_RECEIPT_INVALID")
	var candidate := profile.duplicate(true)
	candidate.tutorial_state.guided_runs_completed += 1
	Progress.replace_marker(candidate, Progress.PROGRESS_PREFIX + "guided:", Progress.PROGRESS_PREFIX + "guided:" + str(int(receipt.launch_sequence)) + ":" + str(int(receipt.guided_sequence)))
	return _finish(candidate)


func _ready_profile(profile: Dictionary, expected_revision: int) -> Dictionary:
	var decoded := progress_view(profile)
	if not decoded.ok:
		return decoded
	if profile.revision != expected_revision:
		return Candidate.failure(&"STALE_REVISION")
	if profile.revision == Catalog.MAX_VALUE:
		return Candidate.failure(&"TRANSACTION_LIMIT")
	return decoded


func _finish(candidate: Dictionary, context: Dictionary = {}) -> Dictionary:
	candidate.completed_command_ids.sort()
	candidate.revision += 1
	var decoded := progress_view(candidate)
	if not decoded.ok:
		return Candidate.failure(&"CANDIDATE_INVALID", {"cause": decoded.code})
	var validator := Profile.new()
	if not validator.configure(_content.call("meta_catalog"), candidate):
		return Candidate.failure(&"CANDIDATE_INVALID")
	var result := context.duplicate(true)
	result.candidate = validator.snapshot()
	return Candidate.success(result)


func _receipt_valid(profile: Dictionary, receipt: Dictionary, watermarks: Dictionary) -> bool:
	if not Catalog.exact_fields(receipt, RECEIPT_FIELDS) or not receipt.run_id is String or not receipt.context_id is String or receipt.context_id not in Content.CONTEXT_IDS or not Catalog.bounded_int(receipt.session_sequence, 1, Catalog.MAX_VALUE) or not Catalog.bounded_int(receipt.action_sequence, 1, Catalog.MAX_VALUE) or not receipt.action_id is String or receipt.action_id not in Content.ACTION_IDS + [""] or not receipt.trigger_ids is Array or receipt.trigger_ids.size() > 25:
		return false
	var seen: Array = []
	for trigger: Variant in receipt.trigger_ids:
		if not trigger is String or not _content.call("has_trigger", trigger) or seen.has(trigger):
			return false
		seen.append(trigger)
	if receipt.action_id.is_empty() and receipt.trigger_ids.is_empty():
		return false
	if receipt.context_id == "normal_run":
		if profile.active_launch_receipt.is_empty() or receipt.run_id != profile.active_launch_receipt.run_id or receipt.session_sequence != profile.active_launch_receipt.sequence:
			return false
	elif not receipt.run_id.is_empty() or not profile.active_launch_receipt.is_empty():
		return false
	var watermark: Dictionary = watermarks.get(receipt.context_id, {})
	if watermark.is_empty():
		return receipt.action_sequence == 1
	if receipt.session_sequence < watermark.session_sequence:
		return false
	if receipt.session_sequence > watermark.session_sequence:
		return receipt.action_sequence == 1
	return receipt.action_sequence > watermark.action_sequence


func _prerequisites_met(profile: Dictionary, lesson: Dictionary) -> bool:
	for id: String in lesson.prerequisite_lesson_ids:
		if not profile.tutorial_state.completed_lessons.has(id) and not profile.tutorial_state.skipped_lessons.has(id):
			return false
	return true


func _advance(candidate: Dictionary, counters: Dictionary, row: Dictionary, kind: String, id: String, receipt: Dictionary) -> bool:
	var requirement := Progress.requirement_for(row, receipt.action_id)
	if requirement.is_empty() or requirement.context_id != receipt.context_id:
		return false
	var key := "%s:%s:%s" % [kind, id, receipt.action_id]
	var count: int = mini(int(counters.get(key, 0)) + 1, int(requirement.count))
	counters[key] = count
	Progress.replace_marker(candidate, Progress.PROGRESS_PREFIX + key + ":", Progress.PROGRESS_PREFIX + key + ":" + str(count))
	for objective: Dictionary in row.receipt_requirements:
		if counters.get("%s:%s:%s" % [kind, id, objective.action_id], 0) != int(objective.count):
			return false
	return true
