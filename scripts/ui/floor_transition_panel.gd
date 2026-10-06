class_name FloorTransitionPanel
extends "res://scripts/ui/dungeon_panel_view.gd"

signal floor_transition_requested(expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/floor_transition_view_state.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")


func _validate(state: Dictionary):
	return Contract.validate(state)


func _render_state() -> void:
	title_label.text = tr("UI_FLOOR_TRANSITION")
	summary_label.text = tr("UI_GOLD_FMT") % int(_state["gold"])
	var floors := HBoxContainer.new()
	floors.name = "FloorArtwork"
	floors.alignment = BoxContainer.ALIGNMENT_CENTER
	floors.add_theme_constant_override("separation", 24)
	rows_container.add_child(floors)
	for floor_id: String in [_state.completed_floor_id, _state.next_floor_id]:
		floors.add_child(Art.image(Art.floor_tile(floor_id), 64, "FloorPalettePreview"))
	_add_text(tr("UI_FLOOR_COMPLETE_FMT") % tr(_state["completed_name_key"]))
	_add_text(tr("UI_NEXT_FLOOR_FMT") % tr(_state["next_name_key"]))
	_add_action("next_floor", tr("UI_ENTER_FLOOR"), "", _state["available"], "" if _state["available"] else "UI_ROUTE_UNAVAILABLE", _request_transition.bind(int(_state["revision"])))


func _request_transition(revision: int) -> void:
	floor_transition_requested.emit(revision)
