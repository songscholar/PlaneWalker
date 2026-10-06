class_name DungeonEventPanel
extends "res://scripts/ui/dungeon_panel_view.gd"

signal event_option_requested(event_id: StringName, option_id: StringName, expected_revision: int)
signal dismiss_requested(event_id: StringName, expected_revision: int)
signal event_reward_requested(option_id: StringName, expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/dungeon_event_view_state.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")


func _validate(state: Dictionary):
	return Contract.validate(state)


func _render_state() -> void:
	title_label.text = tr(_state["name_key"])
	summary_label.text = ""
	var artwork := Art.image(Art.icon(&"event_art", StringName(_state.event_id)), 84, "EventArtwork")
	artwork.custom_minimum_size = Vector2(126, 84)
	rows_container.add_child(artwork)
	_add_text(tr(_state["description_key"]))
	_add_text(tr(_state["prompt_key"]))
	if _state["phase"] == "open":
		for option: Dictionary in _state["options"]:
			var previews: Array[String] = []
			for key: String in option["visible_preview"]:
				previews.append(tr(key))
			if option["outcome_visibility"] == "hidden_until_commit":
				previews.append(tr("UI_OUTCOME_HIDDEN"))
			_add_action(option["id"], tr(option["label_key"]), "\n".join(previews), option["eligible"], option["disabled_reason_key"], _request_option.bind(StringName(_state["event_id"]), StringName(option["id"]), int(_state["revision"])))
	else:
		if not str(_state["result_key"]).is_empty():
			_add_text(tr(_state["result_key"]), "ResultLabel")
		if _state["phase"] in ["pending_reward", "pending_encounter"]:
			_add_text(tr("UI_EVENT_PENDING_REWARD" if _state["phase"] == "pending_reward" else "UI_EVENT_PENDING_ENCOUNTER"), "PendingLabel")
			if _state["phase"] == "pending_reward":
				var offer := _state["reward_offer"] as Dictionary
				for option: Dictionary in offer["options"]:
					var reward := _add_action(option["option_id"], tr(option["name_key"]), tr(option["description_key"]), true, "", _request_reward.bind(StringName(option["option_id"]), int(_state["revision"])))
					Art.button_icon(reward, Art.content(str(option.content_id), str(offer.category)))
				if offer["can_skip"]:
					_add_action("skip", tr("CHOICE_SKIP"), "", true, "", _request_reward.bind(&"skip", int(_state["revision"])))
		else:
			_add_action("dismiss", tr("UI_EVENT_CONTINUE"), "", true, "", _request_dismiss.bind(StringName(_state["event_id"]), int(_state["revision"])))
	if not _actions.is_empty():
		var first := _actions[0]
		first.gui_input.connect(_context_navigation.bind(first, _epoch))


func _context_navigation(event: InputEvent, action: Control, source_epoch: int) -> void:
	if source_epoch != _epoch or _submitted or not visible:
		return
	if event.is_action_pressed("ui_up") and scroll.scroll_vertical > 0:
		scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - 48)
		action.accept_event()
	elif event.is_action_pressed("ui_down") and not scroll.get_global_rect().encloses(action.get_global_rect()):
		scroll.scroll_vertical += 48
		action.accept_event()


func _request_option(event_id: StringName, option_id: StringName, revision: int) -> void:
	event_option_requested.emit(event_id, option_id, revision)


func _request_dismiss(event_id: StringName, revision: int) -> void:
	dismiss_requested.emit(event_id, revision)


func _request_reward(option_id: StringName, revision: int) -> void:
	event_reward_requested.emit(option_id, revision)
