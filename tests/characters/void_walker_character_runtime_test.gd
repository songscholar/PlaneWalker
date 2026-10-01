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
const HostileThreatRegistryScript := preload(
	"res://scripts/combat/hostile_threat_registry.gd"
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
	_definition = _load_definition("void_walker_launch_v1")
	_test_factory_and_debt_boundaries()
	_test_fixed_frame_corruption_and_stop_pause()
	_test_unscaled_risk_conversion_and_rift_cost()
	_test_devour_cost_payload_healing_and_rewind_authority()
	_test_snapshot_talents_and_reset()
	_suite.finish(get_tree())


func _test_factory_and_debt_boundaries() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture.runtime
	_suite.assert_equal(
		str(runtime.get_script().resource_path),
		"res://scripts/player/characters/void_walker_character_runtime.gd",
		"factory creates the real Void Walker strategy"
	)
	runtime.advance_frame({"runtime_frame": 0})
	runtime.on_room_started(_room())
	for amount: float in [59.0, 40.0, 1.0, 1.0]:
		runtime.after_damage(_damage(amount, &"enemy"))
	_suite.assert_equal(int(runtime.snapshot().resource_value), 100, "Void Debt clamps at 100")
	var before: Dictionary = runtime.snapshot()
	runtime.after_damage(_damage(1.0, &"corruption"))
	_suite.assert_equal(runtime.snapshot(), before, "corruption cannot recursively mint debt")
	fixture.owner.free()


func _test_fixed_frame_corruption_and_stop_pause() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture.runtime
	runtime.advance_frame({"runtime_frame": 0})
	runtime.on_room_started(_room())
	runtime.after_damage(_damage(60.0, &"enemy"))
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 29}), [], "corruption is quiet before frame 30")
	var tick_30: Array = runtime.advance_frame({"runtime_frame": 30})
	_suite.assert_true(_event_exists(tick_30, &"irreversible_health_loss_requested"), "frame 30 emits one corruption tick")
	_suite.assert_close(float(_event_context(tick_30, &"irreversible_health_loss_requested").get("amount", 0.0)), 1.0, "corruption tick is one HP")

	runtime.advance_frame({"runtime_frame": 31})
	var stop_decision: Dictionary = runtime.before_time_skill(_time(&"stop", 31, 10, 1, {
		"stop_until_frame": 90,
	}))
	_suite.assert_true(stop_decision.ok, "owned Stop conversion plans")
	var stopped: Array = runtime.after_time_skill(_time(&"stop", 31, 10, 1, {
		"stop_until_frame": 90,
		"character_decision": stop_decision.decision,
	}))
	_suite.assert_true(_event_exists(stopped, &"void_time_conversion_committed"), "Stop conversion is typed")
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 90}), [], "owned Stop pauses corruption through its end")
	var resumed: Array = runtime.advance_frame({"runtime_frame": 120})
	_suite.assert_true(_event_exists(resumed, &"irreversible_health_loss_requested"), "corruption resumes on the authoritative budget")
	fixture.owner.free()


func _test_unscaled_risk_conversion_and_rift_cost() -> void:
	for sample: Dictionary in [
		{"distance": 239.0, "converts": true},
		{"distance": 240.0, "converts": true},
		{"distance": 241.0, "converts": false},
	]:
		var fixture := _fixture()
		var runtime: RefCounted = fixture.runtime
		var registry: RefCounted = HostileThreatRegistryScript.new()
		_suite.assert_true(registry.register_fact(_circle_fact()), "risk fixture registers immutable hostile geometry")
		runtime.advance_frame({"runtime_frame": 0})
		runtime.on_room_started(_room())
		runtime.after_damage(_damage(20.0, &"enemy"))
		var events: Array = runtime.on_weapon_mastery_confirmed(_mastery(1, 1, {
			"position": Vector2(1.0 + float(sample.distance), 0.0),
			"hostile_threat_registry": registry,
		}))
		_suite.assert_equal(_event_exists(events, &"world_payload_requested"), bool(sample.converts), "risk distance %s is exact" % sample.distance)
		if bool(sample.converts):
			var descriptor := _event_context(events, &"world_payload_requested").get("descriptor", {}) as Dictionary
			_suite.assert_true(CharacterPayloadExecutionScript.is_world_payload_descriptor(descriptor), "conversion descriptor is replay safe")
			_suite.assert_close(float((descriptor.geometry as Dictionary).get("radius", 0.0)), 160.0, "base Void echo radius is 160")
			_suite.assert_close(float((descriptor.parameters as Dictionary).get("damage", 0.0)), 30.0, "base Void echo is 0.75x attack")
			_suite.assert_close(float(_event_context(events, &"health_restore_requested").get("amount", 0.0)), 6.0, "conversion healing is capped at six")
		fixture.owner.free()

	var rift_fixture := _fixture()
	var rift_runtime: RefCounted = rift_fixture.runtime
	rift_runtime.advance_frame({"runtime_frame": 0})
	rift_runtime.on_room_started(_room())
	rift_runtime.after_damage(_damage(30.0, &"enemy"))
	var decision: Dictionary = rift_runtime.before_time_skill(_time(&"rift", 0, 9, 2, {
		"rift_generation": 7,
		"rift_center": Vector2(800, 800),
		"rift_radius": 96.0,
	}))
	rift_runtime.after_time_skill(_time(&"rift", 0, 9, 2, {
		"rift_generation": 7,
		"rift_center": Vector2(800, 800),
		"rift_radius": 96.0,
		"character_decision": decision.decision,
	}))
	var rift_events: Array = rift_runtime.on_weapon_mastery_confirmed(_mastery(2, 2, {
		"position": Vector2(800, 800),
		"rift_generation": 7,
	}))
	var rift_descriptor := _event_context(rift_events, &"world_payload_requested").get("descriptor", {}) as Dictionary
	_suite.assert_close(float((rift_descriptor.geometry as Dictionary).get("radius", 0.0)), 224.0, "authorized Rift raises only echo radius")
	_suite.assert_equal(int(rift_runtime.snapshot().resource_value), 0, "Rift conversion consumes 20 conversion debt plus 10 Rift debt")
	rift_fixture.owner.free()


func _test_devour_cost_payload_healing_and_rewind_authority() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture.runtime
	runtime.advance_frame({"runtime_frame": 10})
	runtime.on_room_started(_room())
	var rejected: Dictionary = runtime.plan_character_skill(
		{"id": &"character_skill", "edge": &"pressed", "held_frames": 0},
		_skill_context(10, 25.0, 20.0, 100.0)
	)
	_suite.assert_true(not rejected.ok, "Devour rejects terminal self-payment")
	var planned: Dictionary = runtime.plan_character_skill(
		{"id": &"character_skill", "edge": &"pressed", "held_frames": 0},
		_skill_context(10, 25.0, 21.0, 100.0)
	)
	_suite.assert_true(planned.ok, "Devour accepts when frozen cost leaves one HP")
	_suite.assert_close(float(planned.plan.health_cost), 20.0, "Devour freezes max(10, 20% max HP)")
	_suite.assert_true(runtime.commit_character_skill(planned.plan, 40).ok, "Devour plan commits")
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 33}), [], "Devour remains cancellable through windup frame 23")
	var active: Array = runtime.advance_frame({"runtime_frame": 34})
	_suite.assert_true(_event_exists(active, &"irreversible_health_loss_requested"), "active frame requests irreversible HP loss")
	_suite.assert_true(_event_exists(active, &"time_energy_spend_requested"), "active frame spends 25 energy")
	var descriptor := _event_context(active, &"world_payload_requested").get("descriptor", {}) as Dictionary
	_suite.assert_close(float((descriptor.parameters as Dictionary).get("damage", 0.0)), 128.0, "Devour deals 4x character attack")

	runtime.after_damage(_devour_result(34, 40, 50.0, false))
	runtime.after_damage(_devour_result(34, 40, 70.0, true))
	var rewind_target: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_gameplay_rewind_snapshot(rewind_target), "gameplay Rewind validates but does not install irreversible character state")
	var completed: Array = runtime.advance_frame({"runtime_frame": 65})
	_suite.assert_close(float(_event_context(completed, &"health_restore_requested").get("amount", 0.0)), 12.0, "Devour aggregate heal is capped at 12% max HP once")
	_suite.assert_true(_event_exists(completed, &"character_cooldown_reset_requested"), "one or more kills reset cooldown once per cast")
	fixture.owner.free()


func _test_snapshot_talents_and_reset() -> void:
	var fixture := _fixture(PackedStringArray(["deep_debt", "bounded_devour", "risk_step"]))
	var runtime: RefCounted = fixture.runtime
	runtime.advance_frame({"runtime_frame": 0})
	runtime.on_room_started(_room())
	runtime.after_damage(_damage(140.0, &"enemy"))
	_suite.assert_equal(int(runtime.snapshot().resource_value), 120, "Deep Debt raises the cap to 120")
	_suite.assert_equal(int(runtime.presentation_snapshot().corruption_threshold), 75, "Deep Debt raises corruption threshold to 75")
	_suite.assert_equal(int(runtime.presentation_snapshot().risk_radius), 288, "Risk Step raises proximity radius to 288")
	var exact: Dictionary = runtime.snapshot()
	runtime.advance_frame({"runtime_frame": 1})
	_suite.assert_true(runtime.can_restore_snapshot(exact), "Void snapshot validates")
	_suite.assert_true(runtime.restore_snapshot(exact), "Void Replay restore is exact")
	runtime.reset_runtime_state(&"loadout_replacement")
	var reset: Dictionary = runtime.snapshot()
	_suite.assert_equal(reset.resource_value, 0, "reset clears Void Debt")
	_suite.assert_equal(reset.mastery_claims, [], "reset clears mastery claims")
	_suite.assert_equal(reset.skill_action, {}, "reset clears Devour")
	fixture.owner.free()


func _fixture(talents: PackedStringArray = PackedStringArray()) -> Dictionary:
	var owner := Node.new()
	var profile: Variant = CharacterRuntimeProfileScript.from_definition(_definition.duplicate(true))
	var runtime: Variant = CharacterRuntimeFactoryScript.create(&"void_walker")
	_suite.assert_true(profile != null, "Void Walker profile parses")
	_suite.assert_true(runtime.configure(owner, profile, talents), "Void Walker runtime configures")
	return {"owner": owner, "runtime": runtime}


func _room() -> Dictionary:
	return {"run_id": &"run-a", "run_revision": 1, "room_id": &"room-1", "room_revision": 1, "owner_character_generation": 4}


func _damage(amount: float, source_kind: StringName) -> Dictionary:
	return {"run_id": &"run-a", "run_revision": 1, "runtime_frame": 0, "applied": true, "prevented": false, "source_kind": source_kind, "finalized_damage": amount, "irreversible": source_kind != &"enemy", "source_token": 1, "source_generation": 1}


func _mastery(generation: int, token: int, extra: Dictionary) -> Dictionary:
	var context := {"run_id": &"run-a", "run_revision": 1, "owner_character_generation": 4, "runtime_frame": 0, "attack": 40.0, "current_hp": 50.0, "maximum_hp": 100.0}
	for key: Variant in extra.keys():
		context[key] = extra[key]
	return {"weapon_id": &"sword", "mastery_family": &"sword", "generation": generation, "action_token": token, "context": context}


func _time(ability_id: StringName, frame: int, token: int, generation: int, extra: Dictionary) -> Dictionary:
	var value := {"ability_id": ability_id, "runtime_frame": frame, "token": token, "generation": generation, "run_id": &"run-a", "run_revision": 1, "owner_character_generation": 4}
	for key: Variant in extra.keys():
		value[key] = extra[key]
	return value


func _skill_context(frame: int, energy: float, hp: float, maximum_hp: float) -> Dictionary:
	return {"runtime_frame": frame, "run_id": &"run-a", "run_revision": 1, "owner_character_generation": 4, "alive": true, "time_energy": energy, "current_hp": hp, "maximum_hp": maximum_hp, "position": Vector2(30, 20), "aim_direction": Vector2.RIGHT, "attack": 32.0}


func _devour_result(frame: int, token: int, damage: float, killed: bool) -> Dictionary:
	return {"run_id": &"run-a", "run_revision": 1, "runtime_frame": frame, "applied": true, "prevented": false, "source_kind": &"character_payload", "payload_family": &"void_devour", "source_token": token, "source_generation": 4, "finalized_damage": damage, "target_killed": killed}


func _circle_fact() -> Dictionary:
	return {"hostile_source_id": &"enemy-a", "attack_generation": 1, "shape": &"circle", "origin": Vector2.ZERO, "aim_direction": Vector2.RIGHT, "target_point": Vector2.ZERO, "summon_slots": [], "radius": 1.0, "length": 1.0, "active_from_frame": 0, "active_through_frame": 100}


func _event_exists(events: Array, event_id: StringName) -> bool:
	for event: Dictionary in events:
		if StringName(str(event.get("event_id", ""))) == event_id:
			return true
	return false


func _event_context(events: Array, event_id: StringName) -> Dictionary:
	for event: Dictionary in events:
		if StringName(str(event.get("event_id", ""))) == event_id:
			return (event.get("context", {}) as Dictionary).duplicate(true)
	return {}


func _load_definition(profile_id: String) -> Dictionary:
	var file := FileAccess.open(PROFILE_CATALOG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return {}
	for value: Variant in parsed:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == profile_id:
			return (value as Dictionary).duplicate(true)
	return {}
