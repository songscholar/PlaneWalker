class_name NarrativeViewModel
extends RefCounted

const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Contract := preload("res://scripts/ui/contracts/narrative_view_state.gd")


func dialogue(profile: Dictionary, run_id: String, definition: Dictionary, context: Dictionary) -> Dictionary:
	var state := _base(profile, run_id, "dialogue", str(definition.npc_id), str(definition.name_key))
	for node: Dictionary in context.nodes:
		# Unavailable story nodes expose only their requirement count, never unrevealed text.
		if not node.available:
			state.rows.append(_row("locked:" + str(node.node_id), str(node.node_id), "", "UI_NARRATIVE_NEEDS", "", false, false, node.missing_requirements.size()))
			continue
		for choice: Dictionary in node.choices:
			state.rows.append(_row("dialogue:" + str(node.node_id) + ":" + str(choice.id), str(node.node_id), str(choice.id), str(choice.text_key), str(node.text_key), not node.consumed, node.consumed, 0))
	return _finish(state)


func choice(profile: Dictionary, run_id: String, definition: Dictionary) -> Dictionary:
	var state := _base(profile, run_id, "choice", str(definition.id), str(definition.name_key))
	state.text_key = str(definition.description_key)
	for option: Dictionary in definition.options:
		state.rows.append(_row("choice:" + str(option.id), "", str(option.id), str(option.text_key), "", true, false, 0))
	return _finish(state)


func endings(profile: Dictionary, run_id: String, context: Dictionary) -> Dictionary:
	var state := _base(profile, run_id, "ending", "endings", "UI_NARRATIVE_ENDINGS")
	state.close_available = false
	for ending: Dictionary in context.endings:
		var revealed: bool = ending.eligible or ending.discovered
		state.rows.append(_row("ending:" + str(ending.ending_id), "", str(ending.ending_id), str(ending.name_key) if revealed else "UI_NARRATIVE_NEEDS", str(ending.text_key) if revealed else "", ending.eligible, false, ending.missing_requirements.size()))
	return _finish(state)


func story(profile: Dictionary, run_id: String, subject_id: String, text_key: String) -> Dictionary:
	var state := _base(profile, run_id, "story", subject_id, "UI_NARRATIVE_COLLECTED")
	state.text_key = text_key
	state.rows.append(_row("continue", "", "", "UI_NARRATIVE_CONTINUE", "", true, false, 0))
	return _finish(state)


func credits(profile: Dictionary, run_id: String, ending: Dictionary) -> Dictionary:
	var state := _base(profile, run_id, "credits", str(ending.ending_id), "UI_NARRATIVE_CREDITS")
	state.close_available = false
	state.text_key = str(ending.credits_key)
	state.rows.append(_row("credits:" + str(ending.ending_id), "", str(ending.ending_id), "UI_NARRATIVE_SKIP_CREDITS", "", true, false, 0))
	return _finish(state)


func _base(profile: Dictionary, run_id: String, mode: String, subject: String, title: String) -> Dictionary:
	return {"schema_version": 1, "revision": int(profile.revision), "run_id": run_id, "mode": mode, "subject_id": subject, "title_key": title, "text_key": "", "close_available": true, "rows": []}


func _row(action: String, node: String, choice_id: String, name_key: String, text_key: String, available: bool, consumed: bool, missing_count: int) -> Dictionary:
	return {"action_id": action, "node_id": node, "choice_id": choice_id, "name_key": name_key, "text_key": text_key, "available": available, "consumed": consumed, "missing_count": missing_count}


func _finish(state: Dictionary) -> Dictionary:
	var valid = Contract.validate(state)
	return Candidate.success({"view_state": state.duplicate(true)}) if valid.ok else Candidate.failure(&"NARRATIVE_VIEW_INVALID", valid.context)
