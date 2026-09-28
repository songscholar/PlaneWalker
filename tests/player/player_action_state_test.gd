extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_normal_input_buffer()
	_test_combo_input_buffer()
	_test_buffered_input_priority()
	_test_invalid_inputs_are_rejected()
	_test_free_actions()
	_test_attack_phase_transitions()
	_test_attack_phase_completion_is_owner_driven()
	_test_attack_active_rejections()
	_test_attack_recovery_cancel_window()
	_test_safe_reset_clears_transient_state()
	_test_clear_buffered_inputs()
	_test_dash_rejects_attack()
	_test_hitstun_blocks_actions_until_complete()
	_test_priority_interrupts()
	_test_dead_is_terminal()
	_test_duration_and_frame_queries()
	_suite.finish(get_tree())


func _test_normal_input_buffer() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.buffer_input(&"attack")
	for frame: int in range(PlayerActionStateScript.INPUT_BUFFER_FRAMES):
		_suite.assert_true(action_state.has_buffered_input(&"attack"), "normal input remains buffered on frame %d" % frame)
		action_state.advance_frame()
	_suite.assert_true(not action_state.has_buffered_input(&"attack"), "normal input expires on frame 8")

	action_state.buffer_input(&"dash")
	_suite.assert_true(action_state.consume_buffered_input(&"dash"), "buffered input can be consumed")
	_suite.assert_true(not action_state.consume_buffered_input(&"dash"), "consumed input cannot be consumed twice")


func _test_combo_input_buffer() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.buffer_input(&"combo", PlayerActionStateScript.COMBO_BUFFER_FRAMES)
	for frame: int in range(PlayerActionStateScript.COMBO_BUFFER_FRAMES):
		_suite.assert_true(action_state.has_buffered_input(&"combo"), "combo input remains buffered on frame %d" % frame)
		action_state.advance_frame()
	_suite.assert_true(not action_state.has_buffered_input(&"combo"), "combo input expires on frame 12")


func _test_buffered_input_priority() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.buffer_input(&"attack")
	action_state.buffer_input(&"dash")
	action_state.buffer_input(&"time_cast")
	_suite.assert_equal(
		action_state.consume_highest_priority_buffered_input(),
		&"dash",
		"dash wins simultaneous buffered inputs regardless of insertion order"
	)
	_suite.assert_equal(
		action_state.consume_highest_priority_buffered_input(),
		&"time_cast",
		"time cast wins over attack after dash is consumed"
	)
	_suite.assert_equal(
		action_state.consume_highest_priority_buffered_input(),
		&"attack",
		"attack remains available after higher-priority inputs are consumed"
	)

	var stunned_state = PlayerActionStateScript.new()
	stunned_state.transition_to(PlayerActionStateScript.State.HITSTUN, 2)
	stunned_state.buffer_input(&"dash")
	_suite.assert_equal(
		stunned_state.consume_highest_priority_buffered_input(),
		&"",
		"blocked actions remain buffered while hitstun is active"
	)
	_suite.assert_true(stunned_state.has_buffered_input(&"dash"), "blocked buffered action is not discarded")
	stunned_state.advance_frame()
	stunned_state.advance_frame()
	_suite.assert_equal(
		stunned_state.consume_highest_priority_buffered_input(),
		&"dash",
		"buffered dash becomes consumable when hitstun completes"
	)


func _test_invalid_inputs_are_rejected() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.buffer_input(&"")
	_suite.assert_true(not action_state.has_buffered_input(&""), "empty action ids are not buffered")
	_suite.assert_true(
		not action_state.transition_to(PlayerActionStateScript.State.TIME_CAST, 0),
		"zero-frame non-terminal states are rejected"
	)
	_suite.assert_true(
		not action_state.transition_to(PlayerActionStateScript.State.DASH, -1),
		"negative-duration non-terminal states are rejected"
	)
	_suite.assert_equal(action_state.current_state, PlayerActionStateScript.State.FREE, "invalid transitions do not mutate state")


func _test_free_actions() -> void:
	var action_state = PlayerActionStateScript.new()
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_WINDUP), "free allows attack")
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.DASH), "free allows dash")
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.TIME_CAST), "free allows time cast")


func _test_attack_phase_transitions() -> void:
	var action_state = PlayerActionStateScript.new()
	_suite.assert_true(action_state.transition_to(PlayerActionStateScript.State.ATTACK_WINDUP, 3), "attack windup starts from free")
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_ACTIVE), "windup advances to active")
	_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_RECOVERY), "windup cannot skip active")
	_suite.assert_true(action_state.transition_to(PlayerActionStateScript.State.ATTACK_ACTIVE, 2), "attack active follows windup")
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_RECOVERY), "active advances to recovery")


func _test_attack_phase_completion_is_owner_driven() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_WINDUP, 2)
	action_state.advance_frame()
	action_state.advance_frame()
	_suite.assert_true(action_state.is_state_complete(), "windup completion remains observable")
	_suite.assert_equal(action_state.elapsed_state_frames(), 2, "completed windup stops at its configured duration")
	action_state.advance_frame()
	_suite.assert_equal(action_state.elapsed_state_frames(), 2, "completed windup frame counter remains clamped")
	_suite.assert_equal(
		action_state.current_state,
		PlayerActionStateScript.State.ATTACK_WINDUP,
		"windup does not auto-return to free"
	)
	_suite.assert_true(
		action_state.transition_to(PlayerActionStateScript.State.ATTACK_ACTIVE, 1),
		"owner advances completed windup"
	)
	action_state.advance_frame()
	_suite.assert_true(action_state.is_state_complete(), "active completion remains observable")
	_suite.assert_equal(action_state.elapsed_state_frames(), 1, "completed active frame counter stops at its configured duration")
	action_state.advance_frame()
	_suite.assert_equal(action_state.elapsed_state_frames(), 1, "completed active frame counter remains clamped")
	_suite.assert_equal(
		action_state.current_state,
		PlayerActionStateScript.State.ATTACK_ACTIVE,
		"active does not auto-return to free"
	)
	_suite.assert_true(
		action_state.transition_to(PlayerActionStateScript.State.ATTACK_RECOVERY, 2, 1),
		"owner advances completed active phase"
	)


func _test_attack_active_rejections() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_WINDUP, 3)
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_ACTIVE, 3)
	_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.DASH), "attack active rejects dash")
	_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_WINDUP), "attack active rejects another attack")


func _test_attack_recovery_cancel_window() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_WINDUP, 2)
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_ACTIVE, 2)
	_suite.assert_true(action_state.transition_to(PlayerActionStateScript.State.ATTACK_RECOVERY, 8, 3), "attack recovery starts")
	for frame: int in range(3):
		_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.DASH), "recovery rejects dash before cancel frame %d" % frame)
		action_state.advance_frame()
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.DASH), "recovery accepts dash at cancel frame")
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.TIME_CAST), "recovery accepts time cast at cancel frame")
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_WINDUP), "recovery accepts combo attack at cancel frame")


func _test_safe_reset_clears_transient_state() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_WINDUP, 1)
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_ACTIVE, 1)
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_RECOVERY, 8, 2)
	action_state.advance_frame()
	action_state.advance_frame()
	action_state.buffer_input(&"dash")
	action_state.buffer_input(&"time_cast")
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.DASH), "setup opens recovery cancel window")
	_suite.assert_true(action_state.force_safe_reset(), "non-terminal action state can reset safely")
	_suite.assert_equal(action_state.current_state, PlayerActionStateScript.State.FREE, "safe reset returns to free")
	_suite.assert_true(not action_state.is_state_complete(), "free state is never complete")
	_suite.assert_true(not action_state.has_buffered_input(&"dash"), "safe reset clears dash buffer")
	_suite.assert_true(not action_state.has_buffered_input(&"time_cast"), "safe reset clears time-cast buffer")

	action_state.transition_to(PlayerActionStateScript.State.ATTACK_WINDUP, 1)
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_ACTIVE, 1)
	action_state.transition_to(PlayerActionStateScript.State.ATTACK_RECOVERY, 2)
	_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.DASH), "safe reset clears the prior recovery cancel window")

	var dead_state = PlayerActionStateScript.new()
	dead_state.transition_to(PlayerActionStateScript.State.DEAD, 0)
	_suite.assert_true(not dead_state.force_safe_reset(), "dead state rejects safe reset")
	_suite.assert_equal(dead_state.current_state, PlayerActionStateScript.State.DEAD, "safe reset does not revive dead state")


func _test_clear_buffered_inputs() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.buffer_input(&"attack")
	action_state.buffer_input(&"dash")
	action_state.clear_buffered_inputs()
	_suite.assert_true(not action_state.has_buffered_input(&"attack"), "explicit buffer clear removes attack")
	_suite.assert_true(not action_state.has_buffered_input(&"dash"), "explicit buffer clear removes dash")


func _test_dash_rejects_attack() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.transition_to(PlayerActionStateScript.State.DASH, 4)
	_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_WINDUP), "dash rejects attack")


func _test_hitstun_blocks_actions_until_complete() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.transition_to(PlayerActionStateScript.State.HITSTUN, 3)
	for frame: int in range(3):
		_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_WINDUP), "hitstun rejects attack on frame %d" % frame)
		_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.DASH), "hitstun rejects dash on frame %d" % frame)
		_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.TIME_CAST), "hitstun rejects time cast on frame %d" % frame)
		action_state.advance_frame()
	_suite.assert_equal(action_state.current_state, PlayerActionStateScript.State.FREE, "hitstun completion returns to free")
	_suite.assert_true(action_state.can_transition_to(PlayerActionStateScript.State.ATTACK_WINDUP), "actions resume after hitstun")


func _test_priority_interrupts() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.transition_to(PlayerActionStateScript.State.DASH, 6)
	_suite.assert_true(action_state.transition_to(PlayerActionStateScript.State.HITSTUN, 3), "hitstun interrupts dash")
	_suite.assert_true(action_state.transition_to(PlayerActionStateScript.State.DEAD, 0), "dead interrupts hitstun")


func _test_dead_is_terminal() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.transition_to(PlayerActionStateScript.State.DEAD, 0)
	for _frame: int in range(30):
		action_state.advance_frame()
	_suite.assert_equal(action_state.current_state, PlayerActionStateScript.State.DEAD, "dead never advances back to free")
	_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.FREE), "dead rejects free transition")
	_suite.assert_true(not action_state.can_transition_to(PlayerActionStateScript.State.HITSTUN), "dead rejects hitstun transition")


func _test_duration_and_frame_queries() -> void:
	var action_state = PlayerActionStateScript.new()
	action_state.transition_to(PlayerActionStateScript.State.TIME_CAST, 2)
	_suite.assert_equal(action_state.elapsed_state_frames(), 0, "new state begins at frame zero")
	_suite.assert_equal(action_state.remaining_state_frames(), 2, "new state reports full remaining duration")
	action_state.advance_frame()
	_suite.assert_equal(action_state.elapsed_state_frames(), 1, "state elapsed frames advance")
	_suite.assert_equal(action_state.remaining_state_frames(), 1, "state remaining frames decrease")
	action_state.advance_frame()
	_suite.assert_equal(action_state.current_state, PlayerActionStateScript.State.FREE, "duration completion returns non-terminal state to free")
	_suite.assert_equal(action_state.elapsed_state_frames(), 0, "free resets elapsed state frames")
	_suite.assert_equal(action_state.remaining_state_frames(), 0, "free has no remaining state duration")
