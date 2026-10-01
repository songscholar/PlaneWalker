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
	_definition = _load_definition("primordial_knight_launch_v1")
	_test_factory_mastery_and_resonance_cap()
	_test_formal_commitment_armor_echo_and_rewind_authority()
	_test_commitment_rejection_and_atomic_rollback()
	_test_realm_cleave_boundaries_and_instability()
	_test_time_interactions_talents_snapshot_and_reset()
	_suite.finish(get_tree())


func _test_factory_mastery_and_resonance_cap() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture.runtime
	_suite.assert_equal(str(runtime.get_script().resource_path), "res://scripts/player/characters/primordial_knight_character_runtime.gd", "factory creates the real Primordial Knight strategy")
	runtime.advance_frame({"runtime_frame": 0})
	runtime.on_room_started(_room())
	for token: int in [1, 2, 3, 4]:
		runtime.on_weapon_mastery_confirmed(_mastery(token, &"sword"))
	_suite.assert_equal(int(runtime.snapshot().resource_value), 3, "Resonance clamps at three")
	var before: Dictionary = runtime.snapshot()
	_suite.assert_equal(runtime.on_weapon_mastery_confirmed(_mastery(4, &"sword")), [], "duplicate generation/token/family claim is ignored")
	_suite.assert_equal(runtime.snapshot(), before, "duplicate mastery has zero mutation")
	fixture.owner.free()


func _test_formal_commitment_armor_echo_and_rewind_authority() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture.runtime
	runtime.advance_frame({"runtime_frame": 0})
	runtime.on_room_started(_room())
	for token: int in [1, 2, 3]:
		runtime.on_weapon_mastery_confirmed(_mastery(token, &"sword"))
	var events: Array = runtime.on_weapon_action_committed(_weapon_commit(&"sword", &"charged_slash", 20, 30, false, true))
	_suite.assert_true(_event_exists(events, &"character_resource_changed"), "formal commitment reserves all Resonance atomically")
	_suite.assert_equal(int(runtime.snapshot().resource_value), 0, "three stacks are consumed once")
	var armor: Dictionary = runtime.before_damage(_damage(0, []))
	_suite.assert_close(float((armor.decision as Dictionary).get("combined_multiplier", 1.0)), 0.65, "committed windup armor reduces eligible enemy damage by 35 percent")
	var bypass: Dictionary = runtime.before_damage(_damage(0, ["unguardable"]))
	_suite.assert_close(float((bypass.decision as Dictionary).get("combined_multiplier", 0.0)), 1.0, "unguardable damage bypasses Resonance armor")

	var committed: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_gameplay_rewind_snapshot(committed), "gameplay Rewind validates without deleting committed world payload")
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 15}), [], "echo waits through recovery")
	var released: Array = runtime.advance_frame({"runtime_frame": 16})
	var descriptor := _event_context(released, &"world_payload_requested").get("descriptor", {}) as Dictionary
	_suite.assert_true(CharacterPayloadExecutionScript.is_world_payload_descriptor(descriptor), "planar echo descriptor is replay safe")
	_suite.assert_close(float((descriptor.parameters as Dictionary).get("damage_multiplier", 0.0)), 0.75, "planar echo uses 0.75x approved payload")
	_suite.assert_equal((descriptor.tags as Array), ["character_echo", "no_character_facts", "no_mastery", "no_resource", "non_recursive", "world_owned"], "planar echo is explicitly non-recursive and world-owned")
	fixture.owner.free()


func _test_commitment_rejection_and_atomic_rollback() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture.runtime
	runtime.advance_frame({"runtime_frame": 0})
	runtime.on_room_started(_room())
	for token: int in [1, 2, 3]:
		runtime.on_weapon_mastery_confirmed(_mastery(token, &"sword"))
	var before: Dictionary = runtime.snapshot()
	_suite.assert_equal(runtime.on_weapon_action_committed(_weapon_commit(&"sword", &"charged_slash", 20, 29, false, true)), [], "under-threshold Sword action is not a commitment")
	_suite.assert_equal(runtime.snapshot(), before, "commitment-tier rejection preserves Resonance")
	var malformed: Dictionary = _weapon_commit(&"sword", &"charged_slash", 20, 30, false, true)
	malformed.plan["payload_descriptors"] = [{"damage": NAN}]
	_suite.assert_equal(runtime.on_weapon_action_committed(malformed), [], "malformed approved payload rejects")
	_suite.assert_equal(runtime.snapshot(), before, "payload construction failure rolls back reservation and action state")
	fixture.owner.free()


func _test_realm_cleave_boundaries_and_instability() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture.runtime
	runtime.advance_frame({"runtime_frame": 10})
	runtime.on_room_started(_room())
	for token: int in [1, 2, 3]:
		runtime.on_weapon_mastery_confirmed(_mastery(token, &"sword", 10))
	var planned: Dictionary = runtime.plan_character_skill({"id": &"character_skill", "edge": &"pressed", "held_frames": 0}, _skill_context(10, 35.0))
	_suite.assert_true(planned.ok, "Realm Cleave accepts exact 35 energy")
	_suite.assert_equal(int(planned.plan.commit_frame), 46, "Realm Cleave windup is 36 frames")
	_suite.assert_true(runtime.commit_character_skill(planned.plan, 50).ok, "Realm Cleave plan commits")
	var armor: Dictionary = runtime.before_damage(_damage(10, []))
	_suite.assert_close(float((armor.decision as Dictionary).get("combined_multiplier", 1.0)), 0.6, "Realm Cleave windup armor is 40 percent")
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 45}), [], "Realm Cleave has no payload before frame 36")
	var active: Array = runtime.advance_frame({"runtime_frame": 46})
	_suite.assert_true(_event_exists(active, &"time_energy_spend_requested"), "Realm Cleave spends 35 energy")
	var descriptor := _event_context(active, &"world_payload_requested").get("descriptor", {}) as Dictionary
	_suite.assert_close(float((descriptor.parameters as Dictionary).get("damage", 0.0)), 102.0, "Realm Cleave damage is 1.5x plus 0.35x per consumed stack")
	_suite.assert_equal(int((descriptor.parameters as Dictionary).get("instability_frames", 0)), 480, "three-stack Cleave carries exact instability duration")
	_suite.assert_close(float((descriptor.parameters as Dictionary).get("instability_bonus", 0.0)), 0.2, "instability bonus is 20 percent")
	var instability_context := {
		"run_id": &"run-a", "run_revision": 1, "runtime_frame": 46,
		"applied": true, "prevented": false, "source_kind": &"character_payload",
		"payload_family": &"realm_cleave", "source_token": 50,
		"target_id": 7, "finalized_damage": 102.0,
	}
	var instability: Array = runtime.after_damage(instability_context)
	_suite.assert_true(_event_exists(instability, &"planar_instability_requested"), "three-stack Cleave creates one target instability claim")
	_suite.assert_equal(runtime.after_damage(instability_context), [], "same target/token cannot duplicate instability")
	_suite.assert_equal(int(runtime.snapshot().skill_cooldown_until_frame), 586, "Realm Cleave cooldown is 540 frames from active commit")
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 76}), [], "active plus 30 recovery remains in action")
	var completed: Array = runtime.advance_frame({"runtime_frame": 77})
	_suite.assert_true(_event_exists(completed, &"character_skill_completed"), "Realm Cleave completes after active and recovery")
	fixture.owner.free()


func _test_time_interactions_talents_snapshot_and_reset() -> void:
	var fixture := _fixture(PackedStringArray(["resonant_plate", "echo_forge", "realm_collapse"]))
	var runtime: RefCounted = fixture.runtime
	runtime.advance_frame({"runtime_frame": 0})
	runtime.on_room_started(_room())
	for token: int in [1, 2, 3]:
		runtime.on_weapon_mastery_confirmed(_mastery(token, &"sword"))
	var rift_decision: Dictionary = runtime.before_time_skill(_time(&"rift", 0, 8, 2, {"rift_generation": 9, "rift_center": Vector2(90, 40)}))
	runtime.after_time_skill(_time(&"rift", 0, 8, 2, {"rift_generation": 9, "rift_center": Vector2(90, 40), "character_decision": rift_decision.decision}))
	runtime.on_weapon_action_committed(_weapon_commit(&"sword", &"charged_slash", 22, 30, false, true, {"rift_generation": 9, "rift_center": Vector2(90, 40)}))
	var released: Array = runtime.advance_frame({"runtime_frame": 16})
	var descriptor := _event_context(released, &"world_payload_requested").get("descriptor", {}) as Dictionary
	_suite.assert_close(float((descriptor.parameters as Dictionary).get("damage_multiplier", 0.0)), 1.0, "Echo Forge raises echo multiplier to one")
	_suite.assert_close(float((descriptor.geometry as Dictionary).get("area_scale", 0.0)), 1.25, "authorized Rift scales echo area or length by 1.25")
	_suite.assert_equal((descriptor.transform as Transform2D).origin, Vector2(90, 40), "authorized Rift anchors one echo at its center")

	var exact: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.can_restore_snapshot(exact), "Knight snapshot validates")
	_suite.assert_true(runtime.restore_snapshot(exact), "Knight Replay restore is exact")
	_suite.assert_equal(int(runtime.presentation_snapshot().armor_recovery_extension_frames), 12, "Resonant Plate extends armor twelve recovery frames")
	_suite.assert_equal(int(runtime.presentation_snapshot().instability_frames), 600, "Realm Collapse extends instability to 600 frames")
	runtime.reset_runtime_state(&"loadout_replacement")
	var reset: Dictionary = runtime.snapshot()
	_suite.assert_equal(reset.resource_value, 0, "reset clears Resonance")
	_suite.assert_equal(reset.pending_echoes, [], "reset clears pending echoes")
	fixture.owner.free()


func _fixture(talents: PackedStringArray = PackedStringArray()) -> Dictionary:
	var owner := Node.new()
	var profile: Variant = CharacterRuntimeProfileScript.from_definition(_definition.duplicate(true))
	var runtime: Variant = CharacterRuntimeFactoryScript.create(&"primordial_knight")
	_suite.assert_true(profile != null, "Primordial Knight profile parses")
	_suite.assert_true(runtime.configure(owner, profile, talents), "Primordial Knight runtime configures")
	return {"owner": owner, "runtime": runtime}


func _room() -> Dictionary:
	return {"run_id": &"run-a", "run_revision": 1, "room_id": &"room-1", "room_revision": 1, "owner_character_generation": 5}


func _mastery(token: int, family: StringName, frame: int = 0) -> Dictionary:
	return {"weapon_id": family, "mastery_family": family, "generation": 1, "action_token": token, "context": {"run_id": &"run-a", "run_revision": 1, "owner_character_generation": 5, "runtime_frame": frame}}


func _weapon_commit(weapon_id: StringName, action_id: StringName, token: int, held_frames: int, full_charge: bool, include_payload: bool, extra: Dictionary = {}) -> Dictionary:
	var payloads: Array = [{"descriptor_id": "approved-strike", "kind": "melee", "parameters": {"damage": 100.0, "range": 64.0}}] if include_payload else []
	var value := {"run_id": &"run-a", "run_revision": 1, "owner_character_generation": 5, "runtime_frame": 0, "weapon_id": weapon_id, "action_id": action_id, "action_token": token, "generation": 1, "held_frames": held_frames, "full_charge": full_charge, "position": Vector2(12, 4), "plan": {"weapon_id": weapon_id, "action_id": action_id, "phases": [{"phase": "WINDUP", "duration_frames": 5}, {"phase": "ACTIVE", "duration_frames": 1}, {"phase": "RECOVERY", "duration_frames": 10}], "payload_descriptors": payloads}}
	for key: Variant in extra.keys():
		value[key] = extra[key]
	return value


func _damage(frame: int, tags: Array) -> Dictionary:
	return {"runtime_frame": frame, "run_id": &"run-a", "run_revision": 1, "original_amount": 20.0, "source_kind": &"enemy", "tags": tags}


func _skill_context(frame: int, energy: float) -> Dictionary:
	return {"runtime_frame": frame, "run_id": &"run-a", "run_revision": 1, "owner_character_generation": 5, "alive": true, "time_energy": energy, "position": Vector2(10, 10), "attack": 40.0}


func _time(ability_id: StringName, frame: int, token: int, generation: int, extra: Dictionary) -> Dictionary:
	var value := {"ability_id": ability_id, "runtime_frame": frame, "token": token, "generation": generation, "run_id": &"run-a", "run_revision": 1, "owner_character_generation": 5}
	for key: Variant in extra.keys():
		value[key] = extra[key]
	return value


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
