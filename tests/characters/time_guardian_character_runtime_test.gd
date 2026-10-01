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
	_definition = _load_definition("time_guardian_launch_v1")
	_test_factory_uses_real_guardian_strategy()
	_test_room_context_enables_passive_defensive_mastery()
	_test_guard_frame_boundaries_and_ward_claims()
	_test_ward_rebuke_and_payload_descriptors()
	_test_fortress_cost_duration_cone_and_shockwave()
	_test_snapshot_restore_and_reset()
	_suite.finish(get_tree())


func _test_factory_uses_real_guardian_strategy() -> void:
	var runtime: Variant = CharacterRuntimeFactoryScript.create(&"time_guardian")
	_suite.assert_true(runtime is RefCounted, "factory creates Time Guardian strategy")
	_suite.assert_equal(
		str(runtime.get_script().resource_path),
		"res://scripts/player/characters/time_guardian_character_runtime.gd",
		"Time Guardian uses its real strategy subclass"
	)


func _test_room_context_enables_passive_defensive_mastery() -> void:
	var owner := Node.new()
	var runtime: Variant = CharacterRuntimeFactoryScript.create(&"time_guardian")
	var profile: Variant = CharacterRuntimeProfileScript.from_definition(_definition.duplicate(true))
	_suite.assert_true(runtime.configure(owner, profile, PackedStringArray()), "passive Guardian configures")
	runtime.advance_frame({"runtime_frame": 0})
	var started: Array = runtime.on_room_started({
		"run_id": &"run-a",
		"run_revision": 1,
		"room_id": &"room-1",
		"room_revision": 1,
		"owner_character_generation": 4,
	})
	_suite.assert_true(_event_exists(started, &"guardian_room_started"), "room fact binds Guardian run identity")
	runtime.on_weapon_mastery_confirmed(_mastery(1, 1, 0, {
		"defensive_mastery": true,
		"hostile_source_id": &"enemy-a",
		"attack_generation": 1,
		"owner_character_generation": 4,
	}))
	_suite.assert_equal(int(runtime.snapshot().resource_value), 1, "defensive mastery grants Ward before skill use")
	owner.free()


func _test_guard_frame_boundaries_and_ward_claims() -> void:
	for boundary: Dictionary in [
		{"frame": 8, "kind": &"perfect", "prevented": true, "guard_multiplier": 0.0},
		{"frame": 9, "kind": &"normal", "prevented": false, "guard_multiplier": 0.5},
		{"frame": 23, "kind": &"normal", "prevented": false, "guard_multiplier": 0.5},
		{"frame": 24, "kind": &"closed", "prevented": false, "guard_multiplier": 1.0},
	]:
		var fixture := _guard_fixture()
		var runtime: RefCounted = fixture.runtime
		runtime.advance_frame({"runtime_frame": int(boundary.frame)})
		var result: Dictionary = runtime.before_damage(_damage(
			&"enemy-a", int(boundary.frame) + 1, int(boundary.frame)
		))
		_suite.assert_true(bool(result.get("ok", false)), "guard boundary decision succeeds")
		var decision := result.get("decision", {}) as Dictionary
		_suite.assert_equal(StringName(str(decision.get("guard_kind", ""))), boundary.kind, "guard frame kind is exact")
		_suite.assert_equal(bool(decision.get("prevented", false)), boundary.prevented, "guard prevented boundary is exact")
		_suite.assert_close(float(decision.get("guard_multiplier", 1.0)), float(boundary.guard_multiplier), "guard multiplier is exact")
		if boundary.kind != &"closed":
			var events: Array = runtime.after_damage(_confirmed_damage(decision, 0.0 if boundary.prevented else 12.0))
			_suite.assert_true(_event_exists(events, &"character_resource_changed"), "resolved guard grants Ward")
			_suite.assert_equal(int(runtime.snapshot().resource_value), 1, "guard grants exactly one Ward")
			var duplicate: Dictionary = runtime.before_damage(_damage(
				&"enemy-a", int(boundary.frame) + 1, int(boundary.frame)
			)).decision as Dictionary
			runtime.after_damage(_confirmed_damage(duplicate, 0.0))
			_suite.assert_equal(int(runtime.snapshot().resource_value), 1, "same hostile attack cannot grant twice")
		fixture.owner.free()

	var cooldown_fixture := _guard_fixture()
	var cooldown_runtime: RefCounted = cooldown_fixture.runtime
	cooldown_runtime.advance_frame({"runtime_frame": 23})
	var release: Dictionary = cooldown_runtime.plan_character_skill(
		{"id": &"character_skill", "edge": &"released", "held_frames": 23},
		_skill_context(23, 120.0)
	)
	_suite.assert_true(release.ok, "guard release plans")
	var released: Dictionary = cooldown_runtime.commit_character_skill(release.plan, 2)
	_suite.assert_equal(int(cooldown_runtime.snapshot().skill_cooldown_until_frame), 263, "ordinary cooldown is exact 240 frames")
	_suite.assert_true(_event_exists(released.events, &"character_cooldown_started"), "release returns cooldown event")
	cooldown_runtime.advance_frame({"runtime_frame": 262})
	_suite.assert_true(
		not cooldown_runtime.plan_character_skill(
			{"id": &"character_skill", "edge": &"pressed", "held_frames": 0},
			_skill_context(262, 120.0)
		).ok,
		"cooldown rejects frame 262"
	)
	cooldown_runtime.advance_frame({"runtime_frame": 263})
	_suite.assert_true(
		cooldown_runtime.plan_character_skill(
			{"id": &"character_skill", "edge": &"pressed", "held_frames": 0},
			_skill_context(263, 120.0)
		).ok,
		"cooldown allows frame 263"
	)
	cooldown_fixture.owner.free()


func _test_ward_rebuke_and_payload_descriptors() -> void:
	var fixture := _guard_fixture()
	var runtime: RefCounted = fixture.runtime
	var perfect: Dictionary = runtime.before_damage(_damage(&"enemy-a", 1, 0)).decision as Dictionary
	runtime.after_damage(_confirmed_damage(perfect, 0.0))
	var release: Dictionary = runtime.plan_character_skill(
		{"id": &"character_skill", "edge": &"released", "held_frames": 0},
		_skill_context(0, 120.0)
	)
	runtime.commit_character_skill(release.plan, 2)
	runtime.advance_frame({"runtime_frame": 1})
	var ward_result: Dictionary = runtime.before_damage(_damage(&"enemy-b", 2, 1))
	var ward_decision := ward_result.decision as Dictionary
	_suite.assert_close(float(ward_decision.get("ward_multiplier", 1.0)), 0.65, "Ward reduces damage by 35 percent")
	_suite.assert_equal(int(ward_decision.get("consume_ward", 0)), 1, "Ward spends one stack")
	var ward_events: Array = runtime.after_damage(_confirmed_damage(ward_decision, 13.0))
	_suite.assert_equal(int(runtime.snapshot().resource_value), 0, "resolved hit consumes Ward")
	_suite.assert_equal(int(runtime.snapshot().rebuke_until_frame), 181, "Rebuke lasts exact 180 frames")
	_suite.assert_true(_event_exists(ward_events, &"character_resource_changed"), "Ward spend is typed")

	var mastery_events: Array = runtime.on_weapon_mastery_confirmed(_mastery(1, 9, 1, {
		"attack": 27.0,
		"position": Vector2(20, 30),
		"owner_character_generation": 4,
		"equipped_time_abilities": [&"stop", &"rewind"],
		"stop_generation": 8,
		"boss_exposed": true,
	}))
	var payload_event := _event_context(mastery_events, &"world_payload_requested")
	var descriptor := payload_event.get("descriptor", {}) as Dictionary
	_suite.assert_true(
		CharacterPayloadExecutionScript.is_world_payload_descriptor(descriptor),
		"Rebuke echo is a valid world payload descriptor"
	)
	_suite.assert_close(float((descriptor.get("parameters", {}) as Dictionary).get("damage", 0.0)), 20.25, "Rebuke is 0.75 attack")
	_suite.assert_true((descriptor.get("tags", []) as Array).has("no_mastery"), "Rebuke cannot recurse into mastery")
	_suite.assert_true(_event_exists(mastery_events, &"time_cooldown_reduction_requested"), "Rebuke reduces longer time cooldown")
	_suite.assert_true(_event_exists(mastery_events, &"boss_exposure_extension_requested"), "Stop conversion extends Boss exposure")
	_suite.assert_equal(int(runtime.snapshot().rebuke_until_frame), -1, "Rebuke is one shot")
	fixture.owner.free()


func _test_fortress_cost_duration_cone_and_shockwave() -> void:
	var fixture := _guard_fixture()
	var runtime: RefCounted = fixture.runtime
	for index: int in range(3):
		var decision: Dictionary = runtime.before_damage(_damage(StringName("enemy-%d" % index), index + 1, index)).decision as Dictionary
		runtime.after_damage(_confirmed_damage(decision, 0.0))
		runtime.advance_frame({"runtime_frame": index + 1})
	_suite.assert_equal(int(runtime.snapshot().resource_value), 3, "three unique perfect guards fill Ward")
	var pre_commit: Array = runtime.advance_frame({"runtime_frame": 29, "time_energy": 40.0})
	_suite.assert_true(not _event_exists(pre_commit, &"fortress_committed"), "hold frame 29 does not commit Fortress")
	var committed: Array = runtime.advance_frame({"runtime_frame": 30, "time_energy": 40.0})
	_suite.assert_true(_event_exists(committed, &"fortress_committed"), "hold frame 30 commits Fortress")
	_suite.assert_true(_event_exists(committed, &"time_energy_spend_requested"), "Fortress requests exact energy cost")
	_suite.assert_equal(int(runtime.snapshot().resource_value), 0, "Fortress consumes three Ward")
	_suite.assert_equal(int(runtime.snapshot().fortress_until_frame), 210, "Fortress lasts exact 180 frames")
	_suite.assert_equal(int(runtime.snapshot().skill_cooldown_until_frame), 630, "Fortress cooldown is exact 600 frames")
	_suite.assert_close(float(runtime.presentation_snapshot().movement_multiplier), 0.70, "Fortress movement is 70 percent")

	var frontal: Dictionary = runtime.before_damage(_damage(&"enemy-front", 20, 30, {
		"facing_direction": Vector2.RIGHT,
		"incoming_direction": Vector2.RIGHT,
	})).decision as Dictionary
	_suite.assert_close(float(frontal.get("fortress_multiplier", 1.0)), 0.5, "frontal Fortress reduction is 50 percent")
	var rear: Dictionary = runtime.before_damage(_damage(&"enemy-rear", 21, 30, {
		"facing_direction": Vector2.RIGHT,
		"incoming_direction": Vector2.LEFT,
	})).decision as Dictionary
	_suite.assert_close(float(rear.get("fortress_multiplier", 1.0)), 1.0, "rear hit bypasses Fortress cone")

	for index: int in range(3):
		var mastery_frame := 31 + index
		runtime.advance_frame({"runtime_frame": mastery_frame})
		runtime.on_weapon_mastery_confirmed(_mastery(1, 31 + index, mastery_frame, {
			"defensive_mastery": true,
			"hostile_source_id": StringName("fortress-%d" % index),
			"attack_generation": 30 + index,
			"attack": 27.0,
			"position": Vector2(10, 10),
			"owner_character_generation": 4,
			"equipped_time_abilities": [&"stop", &"rift"],
		}))
	_suite.assert_equal(int(runtime.snapshot().resource_value), 3, "Fortress defensive masteries refill Ward")
	_suite.assert_equal(runtime.snapshot().fortress_shockwave_armed, true, "full Fortress Ward arms shockwave")
	runtime.advance_frame({"runtime_frame": 34})
	var shockwave_events: Array = runtime.on_weapon_mastery_confirmed(_mastery(1, 40, 34, {
		"attack": 27.0,
		"position": Vector2(10, 10),
		"owner_character_generation": 4,
		"equipped_time_abilities": [&"stop", &"rift"],
	}))
	var shockwave := (_event_context(shockwave_events, &"world_payload_requested").get("descriptor", {}) as Dictionary)
	_suite.assert_equal(str(shockwave.get("payload_family", "")), "guardian_fortress_shockwave", "shockwave family is exact")
	_suite.assert_close(float((shockwave.get("geometry", {}) as Dictionary).get("radius", 0.0)), 192.0, "shockwave radius is 192")
	_suite.assert_close(float((shockwave.get("parameters", {}) as Dictionary).get("damage", 0.0)), 27.0, "shockwave is 1.0 attack")
	_suite.assert_equal(runtime.snapshot().fortress_shockwave_armed, false, "shockwave is one shot")
	fixture.owner.free()

	var failed_fixture := _guard_fixture()
	var failed: RefCounted = failed_fixture.runtime
	for index: int in range(3):
		var decision: Dictionary = failed.before_damage(_damage(StringName("failed-%d" % index), index + 1, index)).decision as Dictionary
		failed.after_damage(_confirmed_damage(decision, 0.0))
		failed.advance_frame({"runtime_frame": index + 1})
	var before_fail: Dictionary = failed.snapshot()
	var failure_events: Array = failed.advance_frame({"runtime_frame": 30, "time_energy": 39.99})
	_suite.assert_equal(int(failed.snapshot().resource_value), 3, "failed Fortress check spends no Ward")
	_suite.assert_equal(int(failed.snapshot().skill_cooldown_until_frame), 270, "failed Fortress starts ordinary cooldown")
	_suite.assert_true(_event_exists(failure_events, &"fortress_resource_check_failed"), "failed resource check is typed")
	_suite.assert_true(int(failed.snapshot().revision) > int(before_fail.revision), "failed check advances authoritative frame")
	failed_fixture.owner.free()


func _test_snapshot_restore_and_reset() -> void:
	var fixture := _guard_fixture()
	var runtime: RefCounted = fixture.runtime
	runtime.advance_frame({"runtime_frame": 4})
	var target: Dictionary = runtime.snapshot()
	runtime.advance_frame({"runtime_frame": 5})
	_suite.assert_true(runtime.can_restore_snapshot(target), "Guardian snapshot validates")
	_suite.assert_true(runtime.restore_snapshot(target), "Guardian snapshot restores")
	_suite.assert_equal(runtime.snapshot(), target, "Guardian restore is exact")
	var forged := target.duplicate(true)
	forged["unknown"] = true
	var before_reject: Dictionary = runtime.snapshot()
	_suite.assert_true(not runtime.restore_snapshot(forged), "unknown snapshot field rejects")
	_suite.assert_equal(runtime.snapshot(), before_reject, "forged restore is zero mutation")
	runtime.reset_runtime_state(&"death")
	_suite.assert_equal(runtime.snapshot().last_runtime_frame, -1, "reset clears frame")
	_suite.assert_equal(runtime.snapshot().resource_value, 0, "reset clears Ward")
	_suite.assert_equal(runtime.snapshot().ward_claims, [], "reset clears hostile claims")
	fixture.owner.free()


func _guard_fixture() -> Dictionary:
	var owner := Node.new()
	var runtime: Variant = CharacterRuntimeFactoryScript.create(&"time_guardian")
	var profile: Variant = CharacterRuntimeProfileScript.from_definition(_definition.duplicate(true))
	_suite.assert_true(profile != null, "Guardian profile parses")
	_suite.assert_true(runtime.configure(owner, profile, PackedStringArray()), "Guardian runtime configures")
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 0}), [], "Guardian frame zero advances")
	var plan: Dictionary = runtime.plan_character_skill(
		{"id": &"character_skill", "edge": &"pressed", "held_frames": 0},
		_skill_context(0, 120.0)
	)
	_suite.assert_true(plan.ok, "guard press plans")
	_suite.assert_true(runtime.commit_character_skill(plan.plan, 1).ok, "guard press commits")
	return {"owner": owner, "runtime": runtime}


func _damage(source_id: StringName, attack_generation: int, frame: int, extra: Dictionary = {}) -> Dictionary:
	var value := {
		"runtime_frame": frame,
		"run_id": &"run-a",
		"run_revision": 1,
		"hostile_source_id": source_id,
		"attack_generation": attack_generation,
		"original_amount": 20.0,
		"tags": [],
		"facing_direction": Vector2.RIGHT,
		"incoming_direction": Vector2.RIGHT,
	}
	for key: Variant in extra.keys():
		value[key] = extra[key]
	return value


func _confirmed_damage(decision: Dictionary, finalized_damage: float) -> Dictionary:
	return {
		"runtime_frame": int(decision.get("runtime_frame", 0)),
		"run_id": &"run-a",
		"run_revision": 1,
		"decision": decision.duplicate(true),
		"finalized_damage": finalized_damage,
		"prevented": bool(decision.get("prevented", false)),
		"applied": true,
	}


func _mastery(generation: int, token: int, frame: int, extra: Dictionary) -> Dictionary:
	var context := {
		"runtime_frame": frame,
		"run_id": &"run-a",
		"run_revision": 1,
		"owner_character_generation": int(extra.get("owner_character_generation", 1)),
		"attack": float(extra.get("attack", 27.0)),
		"position": extra.get("position", Vector2.ZERO),
		"equipped_time_abilities": extra.get("equipped_time_abilities", [&"stop", &"rewind"]),
	}
	for key: Variant in extra.keys():
		context[key] = extra[key]
	return {
		"weapon_id": &"sword",
		"mastery_family": &"sword",
		"mastery_id": &"sword_perfect_guard",
		"action_id": &"weapon_primary",
		"generation": generation,
		"action_token": token,
		"target_id": 1,
		"context": context,
	}


func _skill_context(frame: int, energy: float) -> Dictionary:
	return {
		"runtime_frame": frame,
		"run_id": &"run-a",
		"run_revision": 1,
		"owner_character_generation": 4,
		"time_energy": energy,
		"alive": true,
		"position": Vector2.ZERO,
	}


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
