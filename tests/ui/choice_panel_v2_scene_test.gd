extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ChoicePanelScene := preload("res://scenes/ui/choice_panel_v2.tscn")
const FixturesScript := preload("res://scripts/ui/fixtures/selection_offer_fixtures.gd")

var _suite
var _intents: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	get_window().size = Vector2i(640, 360)
	var panel := ChoicePanelScene.instantiate()
	add_child(panel)
	await get_tree().process_frame
	panel.option_chosen.connect(_on_option_chosen)

	_suite.assert_true(panel.get_node_or_null("Player") == null, "choice panel has no Player dependency")
	_suite.assert_true(panel.get_node_or_null("CombatRoom") == null, "choice panel has no CombatRoom dependency")

	var item_offer := FixturesScript.load_fixture("res://tests/fixtures/ui/choice_item_three.json")
	_suite.assert_true(not item_offer.is_empty(), "item fixture loads")
	if item_offer.is_empty():
		await _finish_after_free(panel)
		return
	var item_result = panel.render(item_offer)
	_suite.assert_true(item_result.ok, "item offer renders")
	if not item_result.ok:
		await _finish_after_free(panel)
		return
	await get_tree().process_frame
	_suite.assert_true(panel.visible, "render opens choice panel")
	_suite.assert_true(panel.panel_root.size.x <= 608.0, "panel fits the 16-pixel safe area at 640 width")
	_suite.assert_true(panel.options_container.size.x <= 576.0, "three cards fit inside the panel content width")
	_suite.assert_equal(_buttons(panel).size(), 3, "item offer renders three option buttons")
	_suite.assert_true(not _card_label(_buttons(panel)[0], "NameLabel").text.is_empty(), "item option renders visible text")
	_suite.assert_equal(
		_card_label(_buttons(panel)[0], "DescriptionLabel").autowrap_mode,
		TextServer.AUTOWRAP_WORD_SMART,
		"item description uses word-safe wrapping"
	)
	_suite.assert_equal(_buttons(panel)[0].get_meta("content_id"), "frozen_burst", "item content binds to its button")
	var stale_item_button: Button = _buttons(panel)[0]

	_buttons(panel)[0].pressed.emit()
	_suite.assert_equal(_intents.size(), 1, "first click emits one intent")
	_suite.assert_equal(_intents[0], {
		"offer_id": "offer-item-room-1",
		"option_id": "choose-frozen-burst",
		"revision": 7,
	}, "intent contains only offer, option, and revision")
	_suite.assert_true(_buttons(panel).all(func(button: Button) -> bool: return button.disabled), "first click disables all options")

	_buttons(panel)[1].pressed.emit()
	_suite.assert_equal(_intents.size(), 1, "second click cannot double submit")

	panel.show_rejection("CHOICE_REJECTED_RETRY")
	_suite.assert_true(panel.visible, "rejection keeps panel open")
	_suite.assert_true(panel.error_label.visible, "rejection displays error label")
	_suite.assert_equal(panel.error_label.text, "CHOICE_REJECTED_RETRY", "rejection message key renders")
	_suite.assert_true(_buttons(panel).all(func(button: Button) -> bool: return not button.disabled), "rejection re-enables valid options")

	_buttons(panel)[1].pressed.emit()
	_suite.assert_equal(_intents.size(), 2, "retry emits one new intent")
	_suite.assert_equal(_intents[1]["option_id"], "choose-rewind-echo", "retry emits selected option")

	var duplicate_result = panel.render(item_offer)
	_suite.assert_true(not duplicate_result.ok, "same offer revision is rejected")
	_suite.assert_equal(duplicate_result.code, &"STALE_REVISION", "duplicate revision reports stable error code")

	var older_item_offer := item_offer.duplicate(true)
	older_item_offer["revision"] = 6
	var older_result = panel.render(older_item_offer)
	_suite.assert_true(not older_result.ok, "older revision for same offer is rejected")
	_suite.assert_equal(older_result.code, &"STALE_REVISION", "older revision reports stable error code")

	var contract_offer := FixturesScript.load_fixture("res://tests/fixtures/ui/choice_contract_three.json")
	_suite.assert_true(not contract_offer.is_empty(), "contract fixture loads")
	if contract_offer.is_empty():
		await _finish_after_free(panel)
		return
	var contract_result = panel.render(contract_offer)
	_suite.assert_true(contract_result.ok, "different offer resets revision baseline")
	_suite.assert_equal(_buttons(panel).size(), 3, "contract offer renders three option buttons")
	var intent_count_before_stale_press := _intents.size()
	stale_item_button.pressed.emit()
	_suite.assert_equal(_intents.size(), intent_count_before_stale_press, "removed buttons cannot submit against a newer offer")
	_suite.assert_true(_buttons(panel)[0].has_theme_stylebox_override("normal"), "first risk option has explicit styling")
	_suite.assert_true(_buttons(panel)[1].has_theme_stylebox_override("normal"), "second risk option has explicit styling")
	_suite.assert_equal(_buttons(panel)[2].get_meta("option_id"), "decline_contract", "contract includes safe decline option")
	_suite.assert_equal(_buttons(panel)[2].get_meta("choice_tone"), "safe", "decline option uses safe visual tone")

	var active_offer := item_offer.duplicate(true)
	active_offer["offer_id"] = "offer-active-replacement"
	active_offer["revision"] = 8
	active_offer["options"][0]["content_id"] = "paradox_beacon"
	active_offer["options"][0]["option_id"] = "paradox_beacon"
	active_offer["options"][0]["name_key"] = "PARADOX_BEACON_NAME"
	active_offer["options"][0]["description_key"] = "PARADOX_BEACON_DESC"
	active_offer["options"][0]["role_key"] = "ROLE_RISK"
	active_offer["options"][0]["rarity"] = "rare"
	active_offer["options"][0]["effect_summary_keys"] = ["INPUT_ACTION_ACTIVE_ITEM"]
	active_offer["options"][0]["active_item"] = {
		"cooldown_frames": 900,
		"replacement_required": true,
		"equipped_content_id": "absolute_zero_device",
		"equipped_name_key": "ABSOLUTE_ZERO_DEVICE_NAME",
	}
	var active_result = panel.render(active_offer)
	_suite.assert_true(active_result.ok, "active-item offer renders")
	await get_tree().process_frame
	var active_button: Button = _buttons(panel)[0]
	_suite.assert_equal(
		_card_label(active_button, "ModeLabel").text,
		tr("INPUT_ACTION_ACTIVE_ITEM"),
		"active card identifies its one-slot item mode"
	)
	_suite.assert_equal(
		_card_label(active_button, "CooldownLabel").text,
		tr("HUD_WEAPON_COOLDOWN_FMT") % 15.0,
		"active card converts its frame cooldown to seconds"
	)
	_suite.assert_true(
		_card_label(active_button, "MetaLabel").text.contains(tr("ROLE_RISK")),
		"active card keeps its gameplay role visible"
	)
	_suite.assert_true(
		_card_label(active_button, "MetaLabel").text.contains(tr("RARITY_RARE")),
		"active card keeps its rarity visible"
	)
	_suite.assert_true(
		not _card_label(active_button, "EffectLabel").text.is_empty(),
		"active card keeps an effect summary visible"
	)

	var intent_count_before_replacement := _intents.size()
	active_button.pressed.emit()
	await get_tree().process_frame
	_suite.assert_equal(
		_intents.size(),
		intent_count_before_replacement,
		"occupied active slot requires confirmation before emitting an intent"
	)
	_suite.assert_true(panel.replacement_panel.visible, "replacement confirmation becomes visible")
	_suite.assert_true(not panel.options_container.visible, "replacement confirmation temporarily hides choices")
	_suite.assert_true(
		panel.panel_root.size.y <= 328.0,
		"replacement confirmation stays inside the 16-pixel safe area at 360 height"
	)
	_suite.assert_true(
		panel.replacement_label.text.contains(tr("ABSOLUTE_ZERO_DEVICE_NAME"))
		and panel.replacement_label.text.contains(tr("PARADOX_BEACON_NAME")),
		"replacement confirmation names both equipped and offered items"
	)
	_suite.assert_equal(
		get_viewport().gui_get_focus_owner(),
		panel.replacement_cancel_button,
		"replacement confirmation starts on the reversible cancel action"
	)
	_send_action(&"ui_right")
	await _frames(2)
	_suite.assert_equal(
		get_viewport().gui_get_focus_owner(),
		panel.replacement_confirm_button,
		"controller moves from cancel to confirm in explicit order"
	)
	_send_action(&"ui_right")
	await _frames(2)
	_suite.assert_equal(
		get_viewport().gui_get_focus_owner(),
		panel.replacement_cancel_button,
		"replacement confirmation focus ring wraps"
	)
	panel.replacement_cancel_button.pressed.emit()
	await get_tree().process_frame
	_suite.assert_true(not panel.replacement_panel.visible, "cancel closes replacement confirmation")
	_suite.assert_true(panel.options_container.visible, "cancel restores the choice cards")
	_suite.assert_equal(
		get_viewport().gui_get_focus_owner(),
		active_button,
		"cancel restores focus to the proposed active item"
	)

	active_button.pressed.emit()
	await get_tree().process_frame
	panel.replacement_confirm_button.pressed.emit()
	_suite.assert_equal(_intents.size(), intent_count_before_replacement + 1, "confirm emits one active-item intent")
	_suite.assert_equal(_intents[-1]["option_id"], "paradox_beacon", "confirm emits the proposed active item")

	var long_text_offer := contract_offer.duplicate(true)
	long_text_offer["offer_id"] = "offer-contract-long-text"
	long_text_offer["options"][0]["description_key"] = "Attack much faster, but maximum health is substantially reduced for the rest of this run."
	var long_text_result = panel.render(long_text_offer)
	_suite.assert_true(long_text_result.ok, "long-text offer renders")
	await get_tree().process_frame
	var description_label := _card_label(_buttons(panel)[0], "DescriptionLabel")
	_suite.assert_equal(
		description_label.text,
		"Attack much faster, but maximum health is substantially reduced for the rest of this run.",
		"risk description remains complete"
	)
	_suite.assert_true(description_label.get_line_count() > 1, "long risk description wraps onto multiple lines")
	_suite.assert_true(panel.panel_root.size.y <= 328.0, "wrapped cards remain inside the 16-pixel vertical safe area")
	var locale_offer := active_offer.duplicate(true)
	locale_offer.offer_id = "locale-active-offer"
	_suite.assert_true(panel.render(locale_offer).ok, "locale replacement acceptance opens a fresh authentic active offer")
	TranslationServer.set_locale("en")
	await _frames(2)
	var retained_button: Button = _buttons(panel)[0]
	_suite.assert_equal(_card_label(retained_button, "NameLabel").text, tr("PARADOX_BEACON_NAME"), "open choice refreshes its name when locale changes")
	retained_button.pressed.emit()
	await _frames(1)
	var before_locale_confirm := _intents.size()
	TranslationServer.set_locale("zh_CN")
	await _frames(2)
	_suite.assert_true(panel.replacement_panel.visible, "locale refresh retains pending active-item replacement")
	_suite.assert_equal(panel.replacement_confirm_button.text, tr("PARADOX_BEACON_NAME"), "locale refresh updates replacement confirmation")
	_suite.assert_equal(get_viewport().gui_get_focus_owner(), panel.replacement_cancel_button, "locale refresh preserves confirmation focus")
	_suite.assert_equal(_buttons(panel)[0], retained_button, "locale refresh retains button identity and scroll position")
	panel.replacement_confirm_button.pressed.emit()
	TranslationServer.set_locale("en")
	await _frames(2)
	retained_button.pressed.emit()
	_suite.assert_equal(_intents.size(), before_locale_confirm + 1, "locale refresh cannot reset the one-shot submission guard")
	_suite.assert_true(_buttons(panel).all(func(button: Button) -> bool: return button.disabled), "locale refresh retains all submitted disabled choices")

	panel.close_panel()
	_suite.assert_true(not panel.visible, "close hides choice panel")
	_suite.assert_equal(_buttons(panel).size(), 0, "close clears generated buttons")

	panel.queue_free()
	await get_tree().process_frame
	_suite.finish(get_tree())


func _buttons(panel: Node) -> Array[Node]:
	return panel.options_container.get_children()


func _card_label(button: Button, label_name: String) -> Label:
	return button.find_child(label_name, true, false) as Label


func _on_option_chosen(offer_id: String, option_id: String, revision: int) -> void:
	_intents.append({
		"offer_id": offer_id,
		"option_id": option_id,
		"revision": revision,
	})


func _finish_after_free(panel: Node) -> void:
	panel.queue_free()
	await get_tree().process_frame
	_suite.finish(get_tree())


func _send_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)


func _frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame
