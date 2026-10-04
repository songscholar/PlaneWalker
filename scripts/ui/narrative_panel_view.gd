class_name NarrativePanelView
extends "res://scripts/ui/dungeon_panel_view.gd"

signal action_requested(action_id: String, expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/narrative_view_state.gd")


func _validate(value: Dictionary):
	return Contract.validate(value)


func _render_state() -> void:
	title_label.text = tr(_state.title_key)
	summary_label.text = ""
	summary_label.visible = false
	back_button.visible = _state.close_available
	if not str(_state.text_key).is_empty():
		_add_text(tr(_state.text_key), "NarrativeText")
	for row: Dictionary in _state.rows:
		var description := tr(row.text_key) if not str(row.text_key).is_empty() else ""
		if row.missing_count > 0:
			description = "%s: %d" % [tr("UI_NARRATIVE_NEEDS"), row.missing_count]
		_add_action(str(row.action_id), tr(row.name_key), description, row.available, "", action_requested.emit.bind(str(row.action_id), int(_state.revision)))


func _request_close() -> void:
	if not _state.get("close_available", false):
		return
	super._request_close()


func _focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for control: Control in _actions:
		if not (control as Button).disabled:
			controls.append(control)
	if back_button.visible:
		controls.append(back_button)
	if controls.is_empty():
		controls.append(back_button)
	return controls
