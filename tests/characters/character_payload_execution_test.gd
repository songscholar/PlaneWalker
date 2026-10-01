extends Node

const CharacterPayloadExecutionScript := preload(
	"res://scripts/combat/character_payload_execution.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_typed_decision_and_event_are_replay_safe_and_isolated()
	_test_world_payload_descriptor_is_stable_and_closed()
	_suite.finish(get_tree())


func _test_typed_decision_and_event_are_replay_safe_and_isolated() -> void:
	var parameters := {
		"multiplier": 0.65,
		"claim_key": "enemy-a:7",
		"position": Vector2(12, 18),
	}
	var decision: Dictionary = CharacterPayloadExecutionScript.decision(
		&"time_guardian_defense",
		&"time_guardian",
		44,
		9,
		3,
		parameters
	)
	_suite.assert_true(
		CharacterPayloadExecutionScript.is_decision(decision),
		"typed decision validates"
	)
	_suite.assert_equal(decision.get("runtime_frame"), 44, "decision frame is exact")
	parameters["multiplier"] = 99.0
	_suite.assert_close(
		float((decision.get("parameters", {}) as Dictionary).get("multiplier", 0.0)),
		0.65,
		"decision parameters are isolated"
	)

	var context := {"amount": 6.0, "reason": &"wayfarer_window"}
	var event: Dictionary = CharacterPayloadExecutionScript.event(
		&"time_energy_restore_requested",
		&"wanderer",
		45,
		10,
		3,
		context
	)
	_suite.assert_true(
		CharacterPayloadExecutionScript.is_event(event),
		"typed event validates"
	)
	context["amount"] = 600.0
	_suite.assert_close(
		float((event.get("context", {}) as Dictionary).get("amount", 0.0)),
		6.0,
		"event context is isolated"
	)

	var forged := event.duplicate(true)
	forged["unknown"] = true
	_suite.assert_true(
		not CharacterPayloadExecutionScript.is_event(forged),
		"unknown event fields fail closed"
	)
	_suite.assert_equal(
		CharacterPayloadExecutionScript.event(&"bad:event", &"wanderer", 1, 0, 1, {}),
		{},
		"invalid typed event identity is rejected"
	)


func _test_world_payload_descriptor_is_stable_and_closed() -> void:
	var descriptor: Dictionary = CharacterPayloadExecutionScript.world_payload_descriptor(
		&"run-a",
		4,
		&"guardian_rebuke_echo",
		17,
		2,
		&"character_time_echo",
		Transform2D(0.0, Vector2(32, 48)),
		{"shape": "circle", "center": Vector2(32, 48), "radius": 0.01},
		1,
		["enemy-a:7"],
		["character_owned", "no_mastery", "no_resource", "non_recursive"],
		{"damage": 20.25, "damage_type": "time"}
	)
	_suite.assert_equal(
		descriptor.get("payload_id"),
		"run-a:4:guardian_rebuke_echo:17:2",
		"payload identity follows world authority format"
	)
	_suite.assert_true(
		CharacterPayloadExecutionScript.is_world_payload_descriptor(descriptor),
		"world payload descriptor validates"
	)
	_suite.assert_equal(
		descriptor.get("tags"),
		["character_owned", "no_mastery", "no_resource", "non_recursive"],
		"payload tags are canonical"
	)

	var forged := descriptor.duplicate(true)
	forged["payload_id"] = "run-a:4:guardian_rebuke_echo:17:999"
	_suite.assert_true(
		not CharacterPayloadExecutionScript.is_world_payload_descriptor(forged),
		"forged stable payload identity is rejected"
	)
	_suite.assert_equal(
		CharacterPayloadExecutionScript.world_payload_descriptor(
			&"run:a", 4, &"guardian_rebuke_echo", 17, 2,
			&"character_time_echo", Transform2D.IDENTITY,
			{"shape": "circle", "radius": 1.0}, 1, [], [], {}
		),
		{},
		"invalid run segment is rejected"
	)
