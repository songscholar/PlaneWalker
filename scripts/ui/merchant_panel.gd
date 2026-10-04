class_name MerchantPanel
extends "res://scripts/ui/dungeon_panel_view.gd"

signal merchant_action_requested(action_id: StringName, offer_id: StringName, expected_revision: int)
signal leave_requested(expected_revision: int)

const Contract := preload("res://scripts/ui/contracts/merchant_view_state.gd")


func _validate(state: Dictionary):
	return Contract.validate(state)


func _render_state() -> void:
	title_label.text = tr(_state["name_key"])
	summary_label.text = tr("UI_GOLD_FMT") % int(_state["gold"])
	_add_text(tr(_state["intro_key"]))
	_add_text(tr(_state["description_key"]))
	for offer: Dictionary in _state["offers"]:
		var label := "%s  |  %s" % [tr(offer["name_key"]), tr("UI_PRICE_FMT") % int(offer["price"])]
		var detail := "%s  |  %s" % [tr("RARITY_%s" % str(offer["rarity"]).to_upper()), tr(offer["description_key"])]
		if offer["sold"]:
			detail += "  |  %s" % tr("UI_SOLD")
		_add_action(offer["offer_id"], label, detail, offer["available"], offer["disabled_reason_key"], _request_merchant_action.bind(&"purchase_reward", StringName(offer["offer_id"]), int(_state["revision"])))
	for service: Dictionary in _state["services"]:
		var price_key := "UI_HEALTH_PRICE_FMT" if service["cost_kind"] == "health" else "UI_PRICE_FMT"
		var label := "%s  |  %s" % [tr(service["label_key"]), tr(price_key) % int(service["price"])]
		_add_action(service["action_id"], label, "", service["available"], service["disabled_reason_key"], _request_merchant_action.bind(StringName(service["action_id"]), StringName(service["target_id"]), int(_state["revision"])))
	_add_action("leave", tr("UI_ROOM_LEAVE"), "", true, "", _request_leave.bind(int(_state["revision"])))


func _request_merchant_action(action_id: StringName, offer_id: StringName, revision: int) -> void:
	merchant_action_requested.emit(action_id, offer_id, revision)


func _request_leave(revision: int) -> void:
	leave_requested.emit(revision)
