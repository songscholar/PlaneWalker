class_name TutorialPanel
extends "res://scripts/ui/dungeon_panel_view.gd"

signal lesson_skip_requested(lesson_id: StringName, expected_revision: int)
signal hint_suppression_requested(suppressed: bool, expected_revision: int)
signal guided_mode_requested(enabled: bool, expected_revision: int)
signal training_requested(task_id: StringName, expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/tutorial_view_state.gd")
const Text := preload("res://scripts/ui/tutorial_presentation_text.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
var _selected_lesson := ""
var _hint_toggle: CheckBox
var _mode_selector: OptionButton


func _ready() -> void:
	super._ready()
	Art.button_icon(back_button, Art.icon(&"controls", &"back"))


func _validate(state: Dictionary):
	return Contract.validate(state)


func _render_state() -> void:
	title_label.text = tr("UI_TUTORIAL_TITLE")
	summary_label.text = ""
	summary_label.visible = false
	_hint_toggle = CheckBox.new()
	_hint_toggle.name = "HintToggle"
	_hint_toggle.text = tr("UI_TUTORIAL_HINTS")
	_hint_toggle.button_pressed = not _state.suppressed
	_hint_toggle.add_theme_font_size_override("font_size", 12)
	_hint_toggle.set_meta("action_id", "tutorial_hints")
	_hint_toggle.set_meta("available", true)
	_hint_toggle.pressed.connect(_activate_action.bind(_hint_toggle, _request_suppression, _epoch))
	rows_container.add_child(_hint_toggle)
	_actions.append(_hint_toggle)
	_mode_selector = null
	if _state.guided_policy_available:
		_mode_selector = OptionButton.new()
		_mode_selector.name = "RunMode"
		_mode_selector.add_item(tr("UI_TUTORIAL_NORMAL"), 0)
		_mode_selector.add_item(tr("UI_TUTORIAL_GUIDED"), 1)
		_mode_selector.set_item_disabled(1, not _state.guided_available and not _state.guided_selected)
		_mode_selector.select(1 if _state.guided_selected else 0)
		_mode_selector.disabled = not _state.mode_change_available
		_mode_selector.set_meta("action_id", "tutorial_mode")
		_mode_selector.set_meta("available", _state.mode_change_available)
		_mode_selector.add_theme_font_size_override("font_size", 12)
		_mode_selector.item_selected.connect(_request_mode.bind(_epoch))
		rows_container.add_child(_mode_selector)
		_actions.append(_mode_selector)
	if _state.guided_selected:
		_add_text(tr("UI_TUTORIAL_POLICY") % [int(roundf(_state.incoming_damage_multiplier * 100.0)), int(roundf(_state.warning_scale * 100.0))], "GuidedPolicy")
		_add_text(tr("UI_TUTORIAL_UNRANKED"), "RankedStatus")
	elif _state.guided_sequence == 4:
		_add_text(tr("UI_TUTORIAL_GUIDED_COMPLETE"), "GuidedStatus")
	if not _state.training_available:
		_add_text(tr("UI_TUTORIAL_ACTIVE_RUN"), "RunModeReason")
	var selected: Dictionary = _state.lessons[0]
	for lesson: Dictionary in _state.lessons:
		if lesson.lesson_id == _selected_lesson:
			selected = lesson
	_selected_lesson = selected.lesson_id
	var selected_row := HBoxContainer.new()
	selected_row.add_theme_constant_override("separation", 12)
	rows_container.add_child(selected_row)
	selected_row.add_child(Art.image(Art.icon(&"mode_art", &"training"), 48, "LessonArtwork"))
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 4)
	selected_row.add_child(detail)
	var name_label := _label(tr(selected.name_key), "SelectedLessonName", 14)
	name_label.add_theme_color_override("font_color", Color("e5bd69"))
	detail.add_child(name_label)
	detail.add_child(_label(tr(selected.text_key), "SelectedLessonText", 12))
	_add_text(Text.progress_text(selected.requirements, selected.actions), "SelectedLessonProgress")
	_add_meter(rows_container, selected.requirements, "SelectedLessonMeter")
	var bindings := Text.bindings_text(selected.actions)
	if not bindings.is_empty():
		_add_text(bindings, "SelectedLessonBindings")
	var skip := _add_action("skip:" + selected.lesson_id, tr("UI_TUTORIAL_SKIP"), "", selected.skip_available, "" if selected.skip_available else selected.status_key, _request_skip.bind(StringName(selected.lesson_id), int(_state.revision)))
	Art.button_icon(skip, Art.icon(&"controls", &"next"))
	_add_text(tr("UI_TUTORIAL_LESSONS"), "LessonsHeading")
	for lesson: Dictionary in _state.lessons:
		var recall := _add_action("lesson:" + lesson.lesson_id, "%02d  %s" % [int(lesson.sequence), tr(lesson.name_key)], tr(lesson.status_key), true, "", _recall_lesson.bind(lesson.lesson_id))
		Art.button_icon(recall, Art.icon(&"controls", &"play"))
		if lesson.lesson_id == _selected_lesson:
			recall.add_theme_color_override("font_color", Color("e5bd69"))
		elif lesson.status_key == "UI_TUTORIAL_DONE":
			recall.add_theme_color_override("font_color", Color("79baa1"))
	_add_text(tr("UI_TUTORIAL_TRAINING"), "TrainingHeading")
	for task: Dictionary in _state.training_tasks:
		var reward := tr("UI_TUTORIAL_REWARD_CLAIMED") if task.claimed else tr("UI_TUTORIAL_REWARD") % int(task.reward_shards)
		var description := tr(task.text_key) + "\n" + Text.progress_text(task.requirements, task.actions) + "\n" + reward
		var training := _add_action("training:" + task.task_id, tr(task.name_key), description, _state.training_available, "" if _state.training_available else "UI_TUTORIAL_ACTIVE_RUN", _request_training.bind(StringName(task.task_id), int(_state.revision)))
		Art.button_icon(training, Art.icon(&"mode_art", &"training"))
		_add_meter(training.get_parent(), task.requirements, "TrainingMeter_" + str(task.task_id))


func _add_meter(parent: Node, requirements: Array, meter_name: String) -> void:
	var totals := Vector2.ZERO
	for row: Dictionary in requirements:
		totals += Vector2(row.current, row.count)
	var meter := ProgressBar.new()
	meter.name = meter_name
	meter.custom_minimum_size = Vector2(0, 6)
	meter.show_percentage = false
	meter.max_value = maxf(1, totals.y)
	meter.value = totals.x
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("79baa1")
	meter.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("242d2d")
	meter.add_theme_stylebox_override("background", background)
	parent.add_child(meter)


func show_rejection(message_key: String) -> void:
	super.show_rejection(message_key)
	if not _state.is_empty():
		_hint_toggle.button_pressed = not _state.suppressed
		if _mode_selector != null:
			_mode_selector.select(1 if _state.guided_selected else 0)


func _recall_lesson(id: String) -> void:
	_selected_lesson = id
	_epoch += 1
	_submitted = false
	_clear_rows()
	_render_state()
	_apply_accessibility()
	var controls := _focus_controls()
	FocusCoordinator.link_ring(controls, false)
	FocusCoordinator.recover(self, controls[0])


func _request_skip(id: StringName, revision: int) -> void:
	lesson_skip_requested.emit(id, revision)


func _request_suppression() -> void:
	hint_suppression_requested.emit(not _hint_toggle.button_pressed, int(_state.revision))


func _request_mode(index: int, source_epoch: int) -> void:
	if (index == 1) == _state.guided_selected:
		return
	_activate_action(_mode_selector, _emit_mode.bind(index == 1), source_epoch)


func _emit_mode(enabled: bool) -> void:
	guided_mode_requested.emit(enabled, int(_state.revision))


func _request_training(id: StringName, revision: int) -> void:
	training_requested.emit(id, revision)
