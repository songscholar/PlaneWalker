extends Node

const CharacterPayloadExecutionScript := preload(
	"res://scripts/combat/character_payload_execution.gd"
)
const CharacterRuntimeFactoryScript := preload(
	"res://scripts/player/characters/character_runtime_factory.gd"
)
const CharacterRuntimeProfileScript := preload(
	"res://scripts/player/characters/character_runtime_profile.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PROFILE_CATALOG_PATH := (
	"res://data/content_packs/base/content/character_runtime_profiles.json"
)

var _suite
var _definition: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_definition = _load_definition("wanderer_launch_v1")
	_test_factory_uses_real_wanderer_strategy()
	_test_path_mark_boundaries_and_room_claims()
	_test_wayfarer_time_conversion_and_forgiveness_descriptors()
	_test_waypoint_recall_boundaries_snapshot_and_reset()
	_suite.finish(get_tree())


func _test_factory_uses_real_wanderer_strategy() -> void:
	var runtime: Variant = CharacterRuntimeFactoryScript.create(&"wanderer")
	_suite.assert_true(runtime is RefCounted, "factory creates Wanderer strategy")
	_suite.assert_equal(
		str(runtime.get_script().resource_path),
		"res://scripts/player/characters/wanderer_character_runtime.gd",
		"Launch Wanderer uses its real strategy subclass"
	)


func _test_path_mark_boundaries_and_room_claims() -> void:
	var fixture := _runtime_fixture()
	var runtime: RefCounted = fixture.runtime
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 0}), [], "frame zero advances")
	var room_events: Array = runtime.on_room_started(_room(&"room-1", 1))
	_suite.assert_equal(room_events.size(), 1, "room start produces one typed event")

	var first: Array = runtime.on_weapon_mastery_confirmed(_mastery(1, 10, &"sword", {}))
	_suite.assert_equal(int(runtime.snapshot().resource_value), 1, "first room mastery grants one mark")
	_suite.assert_equal(int(runtime.snapshot().path_progress), 0, "first room mark leaves zero progress")
	_suite.assert_true(_all_typed(first), "first mark events are replay safe")

	runtime.on_weapon_mastery_confirmed(_mastery(1, 11, &"bow", {}))
	_suite.assert_equal(int(runtime.snapshot().path_progress), 1, "progress reaches one")
	runtime.on_weapon_mastery_confirmed(_mastery(1, 12, &"gun", {}))
	_suite.assert_equal(int(runtime.snapshot().path_progress), 2, "progress reaches two")
	runtime.on_weapon_mastery_confirmed(_mastery(1, 13, &"staff", {}))
	_suite.assert_equal(int(runtime.snapshot().resource_value), 2, "third progress grants a mark")
	_suite.assert_equal(int(runtime.snapshot().path_progress), 0, "mark gain resets progress")

	var duplicate_before: Dictionary = runtime.snapshot()
	_suite.assert_equal(
		runtime.on_weapon_mastery_confirmed(_mastery(1, 13, &"staff", {})),
		[],
		"duplicate mastery token is ignored"
	)
	_suite.assert_equal(runtime.snapshot(), duplicate_before, "duplicate mastery is zero mutation")

	for token: int in range(14, 30):
		runtime.on_weapon_mastery_confirmed(_mastery(1, token, &"gauntlets", {}))
	_suite.assert_equal(int(runtime.snapshot().resource_value), 5, "Path Marks cap at five")
	_suite.assert_true(int(runtime.snapshot().path_progress) <= 2, "progress remains bounded at cap")

	var stale_before: Dictionary = runtime.snapshot()
	_suite.assert_equal(runtime.on_room_cleared(_room(&"room-1", 2)), [], "stale room revision rejects")
	_suite.assert_equal(runtime.snapshot(), stale_before, "stale room callback is zero mutation")
	var clear_events: Array = runtime.on_room_cleared(_room(&"room-1", 1))
	_suite.assert_true(_event_exists(clear_events, &"health_restore_requested"), "room clear requests mark heal")
	_suite.assert_close(
		float(_event_context(clear_events, &"health_restore_requested").get("amount", 0.0)),
		10.0,
		"room clear heals two per unspent mark"
	)
	_suite.assert_equal(
		int((runtime.on_run_terminal({"run_id": &"run-a", "run_revision": 1}).summary as Dictionary).get("memory_fragment", 0)),
		1,
		"terminal summary banks one cleared room"
	)
	fixture.owner.free()


func _test_wayfarer_time_conversion_and_forgiveness_descriptors() -> void:
	for weapon_id: StringName in [&"sword", &"bow", &"gun", &"staff", &"gauntlets"]:
		var fixture := _runtime_fixture()
		var runtime: RefCounted = fixture.runtime
		runtime.advance_frame({"runtime_frame": 0})
		runtime.on_room_started(_room(&"room-1", 1))
		runtime.on_weapon_mastery_confirmed(_mastery(1, 1, weapon_id, {}))
		runtime.advance_frame({"runtime_frame": 1})
		var reservation: Dictionary = runtime.before_time_skill({
			"ability_id": &"stop",
			"token": 20,
			"generation": 1,
			"runtime_frame": 1,
			"run_id": &"run-a",
			"run_revision": 1,
		})
		_suite.assert_true(bool(reservation.get("ok", false)), "time conversion reservation succeeds")
		var events: Array = runtime.after_time_skill({
			"ability_id": &"stop",
			"token": 20,
			"generation": 1,
			"runtime_frame": 1,
			"run_id": &"run-a",
			"run_revision": 1,
			"character_decision": reservation.get("decision", {}),
		})
		_suite.assert_equal(int(runtime.snapshot().resource_value), 0, "committed time skill consumes one mark")
		_suite.assert_equal(int(runtime.snapshot().wayfarer_until_frame), 241, "Stop opens exact 240-frame window")
		_suite.assert_true(_event_exists(events, &"character_resource_changed"), "mark spend is typed")

		runtime.advance_frame({"runtime_frame": 240})
		var conversion: Array = runtime.on_weapon_mastery_confirmed(_mastery(
			1, 2, weapon_id, {"runtime_frame": 240, "maximum_hp": 200.0}
		))
		_suite.assert_true(_event_exists(conversion, &"time_energy_restore_requested"), "Wayfarer restores energy")
		_suite.assert_close(
			float(_event_context(conversion, &"time_energy_restore_requested").get("amount", 0.0)),
			6.0,
			"Wayfarer energy amount is exact"
		)
		_suite.assert_close(
			float(_event_context(conversion, &"health_restore_requested").get("amount", 0.0)),
			4.0,
			"Wayfarer heal is two percent maximum HP"
		)
		var forgiveness := _event_context(conversion, &"weapon_forgiveness_granted")
		_assert_forgiveness(weapon_id, forgiveness)
		_suite.assert_equal(int(runtime.snapshot().path_progress), 0, "Wayfarer mastery cannot also add progress")
		fixture.owner.free()

	var expiry_fixture := _runtime_fixture()
	var expiry_runtime: RefCounted = expiry_fixture.runtime
	expiry_runtime.advance_frame({"runtime_frame": 0})
	expiry_runtime.on_room_started(_room(&"room-1", 1))
	expiry_runtime.on_weapon_mastery_confirmed(_mastery(1, 1, &"sword", {}))
	expiry_runtime.advance_frame({"runtime_frame": 1})
	var decision: Dictionary = expiry_runtime.before_time_skill({
		"ability_id": &"rewind", "token": 2, "generation": 1,
		"runtime_frame": 1, "run_id": &"run-a", "run_revision": 1,
	})
	expiry_runtime.after_time_skill({
		"ability_id": &"rewind", "token": 2, "generation": 1,
		"runtime_frame": 1, "run_id": &"run-a", "run_revision": 1,
		"character_decision": decision.decision,
	})
	expiry_runtime.advance_frame({"runtime_frame": 180})
	_suite.assert_true(int(expiry_runtime.snapshot().wayfarer_until_frame) > 0, "window is active on frame 180")
	expiry_runtime.advance_frame({"runtime_frame": 181})
	_suite.assert_equal(int(expiry_runtime.snapshot().wayfarer_until_frame), -1, "window expires on frame 181")
	expiry_fixture.owner.free()


func _test_waypoint_recall_boundaries_snapshot_and_reset() -> void:
	var fixture := _runtime_fixture()
	var runtime: RefCounted = fixture.runtime
	runtime.advance_frame({"runtime_frame": 10})
	var placement: Dictionary = runtime.plan_character_skill(
		{"id": &"character_skill", "edge": &"pressed", "held_frames": 0},
		_skill_context(10, 30.0, Vector2(100, 40))
	)
	_suite.assert_true(bool(placement.get("ok", false)), "exact 30 energy accepts placement")
	_suite.assert_true(runtime.commit_character_skill(placement.plan, 5).ok, "placement action commits")
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 15}), [], "windup frame five has no payload")
	var placed: Array = runtime.advance_frame({"runtime_frame": 16})
	_suite.assert_true(_event_exists(placed, &"waypoint_anchor_placed"), "sixth windup frame places anchor")
	_suite.assert_equal(runtime.snapshot().anchor_position, Vector2(100, 40), "anchor position is frozen")
	_suite.assert_equal(int(runtime.snapshot().anchor_expires_frame), 496, "anchor lasts exactly 480 frames")
	_suite.assert_true(_event_exists(placed, &"time_energy_spend_requested"), "placement returns typed energy cost")

	runtime.advance_frame({"runtime_frame": 18})
	runtime.after_damage({
		"run_id": &"run-a", "run_revision": 1, "runtime_frame": 18,
		"source_kind": &"enemy", "finalized_damage": 40.0,
		"prevented": false, "irreversible": false,
	})
	runtime.advance_frame({"runtime_frame": 19})
	runtime.after_damage({
		"run_id": &"run-a", "run_revision": 1, "runtime_frame": 19,
		"source_kind": &"self_cost", "finalized_damage": 100.0,
		"prevented": false, "irreversible": true,
	})
	runtime.advance_frame({"runtime_frame": 28})
	runtime.advance_frame({"runtime_frame": 29})
	var recall: Dictionary = runtime.plan_character_skill(
		{"id": &"character_skill", "edge": &"pressed", "held_frames": 0},
		_skill_context(29, 30.0, Vector2(900, 900))
	)
	_suite.assert_true(bool(recall.get("ok", false)), "active anchor accepts recall")
	_suite.assert_true(runtime.commit_character_skill(recall.plan, 6).ok, "recall action commits")
	var recalled: Array = runtime.advance_frame({"runtime_frame": 35})
	var recall_context := _event_context(recalled, &"waypoint_recall_requested")
	_suite.assert_equal(recall_context.get("target_position"), Vector2(100, 40), "recall returns frozen anchor position")
	_suite.assert_close(float(recall_context.get("heal_amount", 0.0)), 10.0, "recall heals 25 percent enemy damage only")
	_suite.assert_equal(int(runtime.snapshot().skill_cooldown_until_frame), 755, "recall starts exact 720-frame cooldown")
	_suite.assert_equal(runtime.snapshot().anchor_active, false, "recall consumes anchor")

	var target: Dictionary = runtime.snapshot()
	runtime.advance_frame({"runtime_frame": 47})
	_suite.assert_true(runtime.can_restore_snapshot(target), "Wanderer snapshot validates")
	_suite.assert_true(runtime.restore_snapshot(target), "Wanderer snapshot restores")
	_suite.assert_equal(runtime.snapshot(), target, "Wanderer restore is exact")

	runtime.reset_runtime_state(&"loadout_replacement")
	var reset: Dictionary = runtime.snapshot()
	_suite.assert_equal(reset.last_runtime_frame, -1, "reset clears frame")
	_suite.assert_equal(reset.resource_value, 0, "reset clears Path Marks")
	_suite.assert_equal(reset.anchor_active, false, "reset clears anchor")
	_suite.assert_equal(reset.mastery_claims, [], "reset clears mastery claims")
	fixture.owner.free()


func _runtime_fixture() -> Dictionary:
	var owner := Node.new()
	var runtime: Variant = CharacterRuntimeFactoryScript.create(&"wanderer")
	var profile: Variant = CharacterRuntimeProfileScript.from_definition(_definition.duplicate(true))
	_suite.assert_true(profile != null, "Wanderer profile parses")
	_suite.assert_true(runtime.configure(owner, profile, PackedStringArray()), "Wanderer runtime configures")
	return {"owner": owner, "runtime": runtime}


func _room(room_id: StringName, revision: int) -> Dictionary:
	return {
		"run_id": &"run-a",
		"run_revision": 1,
		"room_id": room_id,
		"room_revision": revision,
	}


func _mastery(generation: int, token: int, family: StringName, extra: Dictionary) -> Dictionary:
	var context := {
		"runtime_frame": int(extra.get("runtime_frame", 0)),
		"run_id": &"run-a",
		"run_revision": 1,
		"maximum_hp": float(extra.get("maximum_hp", 200.0)),
	}
	for key: Variant in extra.keys():
		context[key] = extra[key]
	return {
		"weapon_id": family,
		"mastery_family": family,
		"mastery_id": StringName("%s_test" % str(family)),
		"action_id": &"weapon_primary",
		"generation": generation,
		"action_token": token,
		"target_id": 1,
		"context": context,
	}


func _skill_context(frame: int, energy: float, position: Vector2) -> Dictionary:
	return {
		"runtime_frame": frame,
		"run_id": &"run-a",
		"run_revision": 1,
		"owner_character_generation": 1,
		"time_energy": energy,
		"alive": true,
		"position": position,
	}


func _assert_forgiveness(weapon_id: StringName, value: Dictionary) -> void:
	_suite.assert_equal(StringName(str(value.get("weapon_id", ""))), weapon_id, "forgiveness weapon is exact")
	_suite.assert_equal(int(value.get("expires_after_frames", 0)), 180, "forgiveness lasts 180 frames")
	match weapon_id:
		&"sword":
			_suite.assert_equal(value.get("recovery_reduction_frames"), 4, "Sword forgiveness is -4 frames")
			_suite.assert_equal(value.get("minimum_recovery_frames"), 1, "Sword keeps one recovery frame")
		&"bow":
			_suite.assert_equal(value.get("full_charge_frames"), 44, "Bow threshold is 44")
		&"gun":
			_suite.assert_equal(value.get("perfect_start_frame"), 26, "Gun start is 26")
			_suite.assert_equal(value.get("perfect_end_frame"), 37, "Gun end is 37")
		&"staff":
			_suite.assert_equal(value.get("window_extension_frames"), 60, "Staff extends 60")
			_suite.assert_equal(value.get("window_cap_frames"), 360, "Staff caps at 360")
		&"gauntlets":
			_suite.assert_equal(value.get("combo_extension_frames"), 30, "Gauntlets extend 30")
			_suite.assert_equal(value.get("combo_cap_frames"), 150, "Gauntlets cap at 150")


func _all_typed(events: Array) -> bool:
	for event_value: Variant in events:
		if not event_value is Dictionary or not CharacterPayloadExecutionScript.is_event(event_value):
			return false
	return true


func _event_exists(events: Array, event_id: StringName) -> bool:
	return not _event_context(events, event_id).is_empty()


func _event_context(events: Array, event_id: StringName) -> Dictionary:
	for event_value: Variant in events:
		if event_value is Dictionary and StringName(str((event_value as Dictionary).get("event_id", ""))) == event_id:
			return ((event_value as Dictionary).get("context", {}) as Dictionary).duplicate(true)
	return {}


func _load_definition(profile_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	for value: Variant in parsed:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == profile_id:
			return (value as Dictionary).duplicate(true)
	return {}
