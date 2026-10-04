class_name RoomInteractionPanel
extends "res://scripts/ui/dungeon_panel_view.gd"

signal room_choice_requested(choice_id: StringName, expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/room_interaction_view_state.gd")


func _validate(state: Dictionary):
	return Contract.validate(state)


func _render_state() -> void:
	title_label.text = tr(_state["name_key"])
	summary_label.text = ""
	_add_text(tr(_state["description_key"]))
	for choice: Dictionary in _state["choices"]:
		_add_action(choice["id"], tr(choice["label_key"]), tr(choice["description_key"]), choice["available"], choice["disabled_reason_key"], _request_choice.bind(StringName(choice["id"]), int(_state["revision"])))


func _request_choice(choice_id: StringName, revision: int) -> void:
	room_choice_requested.emit(choice_id, revision)
