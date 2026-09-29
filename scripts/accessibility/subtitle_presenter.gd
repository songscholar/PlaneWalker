class_name SubtitlePresenter
extends PanelContainer

const BASE_FONT_SIZE := 16

var _label: Label
var _hide_timer: Timer
var _settings: Dictionary = {}
var _cue_key: StringName = &""
var _speaker_key: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
	add_child(_label)
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_hide_timer.timeout.connect(_on_hide_timeout)
	add_child(_hide_timer)
	_settings = GameState.normalized_settings().duplicate(true)
	visible = false


func apply_accessibility_settings(settings: Dictionary) -> void:
	_settings = settings.duplicate(true)
	if _label != null:
		_label.add_theme_font_size_override(
			"font_size",
			maxi(1, roundi(BASE_FONT_SIZE * float(_settings.get("subtitle_scale", 1.0))))
		)
	if not bool(_settings.get("subtitles_enabled", true)):
		visible = false


func present(
	cue_key: StringName,
	duration: float,
	speaker_key: StringName = &""
) -> void:
	_settings = GameState.normalized_settings().duplicate(true)
	apply_accessibility_settings(_settings)
	_cue_key = cue_key
	_speaker_key = speaker_key
	_hide_timer.stop()
	if not bool(_settings.get("subtitles_enabled", true)) or cue_key.is_empty():
		visible = false
		return
	var cue_text := tr(str(cue_key))
	_label.text = cue_text if speaker_key.is_empty() else "%s: %s" % [tr(str(speaker_key)), cue_text]
	visible = true
	if duration <= 0.0:
		visible = false
		return
	_hide_timer.start(duration)


func clear() -> void:
	if _hide_timer != null:
		_hide_timer.stop()
	visible = false
	_cue_key = &""
	_speaker_key = &""
	if _label != null:
		_label.text = ""


func get_snapshot_for_test() -> Dictionary:
	return {
		"visible": visible,
		"cue_key": str(_cue_key),
		"speaker_key": str(_speaker_key),
		"text": "" if _label == null else _label.text,
		"font_size": 0 if _label == null else _label.get_theme_font_size("font_size"),
		"dialogue_volume": float(_settings.get("dialogue_volume", 0.90)),
	}


func _on_hide_timeout() -> void:
	visible = false
