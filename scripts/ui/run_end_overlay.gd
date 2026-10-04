class_name RunEndOverlay
extends CanvasLayer

signal hub_return_requested
const Phase := preload("res://scripts/application/run_phase.gd")

@onready var panel: PanelContainer = $Panel
@onready var result_label: Label = $Panel/Margin/VBox/ResultLabel
@onready var restart_button: Button = $Panel/Margin/VBox/RestartButton
var _profile_return := false
var _host: Node
var _presented_run_id := ""


func _ready() -> void:
	_host = get_parent().get_node_or_null("RunRuntimeHost")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	restart_button.text = tr("UI_RESTART_RUN")
	EventBus.run_ended.connect(_on_run_ended)
	restart_button.pressed.connect(_restart_run)


func _on_run_ended(run_id: String, result: Dictionary, _revision: int) -> void:
	if _host != null:
		var native: Dictionary = _host.runtime_snapshot()
		if native.get("run_id") != run_id or not Phase.is_terminal(int(native.get("phase", -1))):
			return
	if _presented_run_id == run_id:
		return
	_presented_run_id = run_id
	var outcome := str(result.get("result", ""))
	var title := tr("UI_RUN_COMPLETE") if outcome in ["floor_cleared", "victory"] else tr("UI_RUN_FAILED")
	result_label.text = "%s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s" % [
		title,
		tr("UI_ROOM_REACHED"), result.get("current_room", result.get("rooms_cleared", 0)),
		tr("UI_ROOMS_CLEARED"), result.get("rooms_cleared", 0),
		tr("UI_KILLS"), result.get("kills", 0),
		tr("UI_TIME"), _format_time(float(result.get("run_time", 0.0))),
		tr("UI_ITEMS"), _names_for(result.get("rewards", [])),
		tr("UI_BLESSINGS"), _names_for(result.get("blessings", [])),
		tr("UI_TALENTS"), _names_for(result.get("talent_choices", [])),
		tr("UI_CURSES"), _names_for(result.get("curses", [])),
	]
	visible = true
	FocusCoordinator.open_scope(self, restart_button)


func _restart_run() -> void:
	if _profile_return:
		hub_return_requested.emit()
		return
	FocusCoordinator.close_scope(self)
	get_tree().reload_current_scene()


func configure_profile_return(value: bool) -> void:
	_profile_return = value
	restart_button.text = tr("UI_RETURN_HUB") if value else tr("UI_RESTART_RUN")


func show_save_pending() -> void:
	restart_button.text = tr("UI_RETRY")
	restart_button.tooltip_text = tr("UI_SETTLEMENT_RETRY")


func show_victory_save_retry() -> void:
	show_save_pending()
	result_label.text = tr("UI_SETTLEMENT_RETRY")
	visible = true
	FocusCoordinator.open_scope(self, restart_button)


func hide_overlay() -> void:
	FocusCoordinator.close_scope(self)
	visible = false
	restart_button.tooltip_text = ""
	configure_profile_return(_profile_return)


func _format_time(seconds: float) -> String:
	var total_seconds := maxi(0, roundi(seconds))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func _names_for(entries: Array) -> String:
	if entries.is_empty():
		return "-"
	var names: Array[String] = []
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			var dict := entry as Dictionary
			names.append(tr(str(dict.get("name", dict.get("id", "unknown")))))
		else:
			names.append(str(entry))
	return ", ".join(names)
