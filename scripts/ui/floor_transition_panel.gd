class_name FloorTransitionPanel
extends "res://scripts/ui/dungeon_panel_view.gd"

signal floor_transition_requested(expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/floor_transition_view_state.gd")


func _validate(state: Dictionary):
	return Contract.validate(state)


func _render_state() -> void:
	title_label.text = tr("UI_FLOOR_TRANSITION")
	summary_label.text = tr("UI_GOLD_FMT") % int(_state["gold"])
	_add_text(tr("UI_FLOOR_COMPLETE_FMT") % tr(_state["completed_name_key"]))
	_add_text(tr("UI_NEXT_FLOOR_FMT") % tr(_state["next_name_key"]))
	_add_action("next_floor", tr("UI_ENTER_FLOOR"), "", _state["available"], "" if _state["available"] else "UI_ROUTE_UNAVAILABLE", _request_transition.bind(int(_state["revision"])))


func _request_transition(revision: int) -> void:
	floor_transition_requested.emit(revision)
