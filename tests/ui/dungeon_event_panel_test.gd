extends "res://tests/ui/p14_panel_test_base.gd"


func _init() -> void:
	panel_kind = "event"
	panel_scene = "res://scenes/ui/dungeon_event_panel.tscn"
	command_signal = "event_option_requested"

var _dismissals: Array = []
var _rewards: Array = []


func _extra_checks(panel: Control) -> void:
	var state := FixturesScript.event_state()
	state["revision"] = 6
	state["phase"] = "pending_reward"
	state["pending_kind"] = "reward"
	state["result_key"] = ""
	state["reward_offer"] = FixturesScript.reward_offer(6)
	_suite.assert_true(panel.call("render", state).ok, "pending reward renders before its final result is published")
	await get_tree().process_frame
	panel.connect("event_reward_requested", _capture_reward)
	var reward_actions: Array = panel.call("action_controls")
	_suite.assert_equal(reward_actions.size(), 1, "pending rewards expose only their authenticated reward options")
	var event_commands := _commands.size()
	(reward_actions[0] as Button).pressed.emit()
	(reward_actions[0] as Button).pressed.emit()
	_suite.assert_equal(_rewards, [[&"choose-frozen-burst", 6]], "pending reward keeps its revision and cannot submit twice")
	_suite.assert_equal(_commands.size(), event_commands, "reward selection cannot repeat the original event option")
	state["revision"] = 7
	state["phase"] = "pending_encounter"
	state["pending_kind"] = "encounter"
	state.erase("reward_offer")
	_suite.assert_true(panel.call("render", state).ok, "pending encounter renders before its final result is published")
	await get_tree().process_frame
	_suite.assert_true(panel.find_children("Action_*", "Button", true, false).is_empty(), "pending combat cannot dismiss or bypass the encounter")
	state["revision"] = 8
	state["phase"] = "resolved"
	state["pending_kind"] = ""
	state["result_key"] = "EVENT_CHRONAL_ALTAR_OUTCOME_COMMIT"
	_suite.assert_true(panel.call("render", state).ok, "authenticated resolved result exposes continuation")
	await get_tree().process_frame
	panel.connect("dismiss_requested", _capture_dismiss)
	var actions: Array = panel.call("action_controls")
	(actions[0] as Button).pressed.emit()
	_suite.assert_equal(_dismissals, [[&"event_chronal_altar", 8]], "resolved dismissal retains event and authoritative revision")


func _capture_dismiss(event_id: StringName, revision: int) -> void:
	_dismissals.append([event_id, revision])


func _capture_reward(option_id: StringName, revision: int) -> void:
	_rewards.append([option_id, revision])
