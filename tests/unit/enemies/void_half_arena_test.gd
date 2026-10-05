extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const Action := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	_test_room_half(Vector2.ZERO)
	_test_room_half(Vector2(704, -384))
	_test_legacy_warning()
	_test_enrage_alternation()
	suite.finish(get_tree())


func _configured(origin: Vector2) -> RefCounted:
	var parser := Definition.new()
	parser.configure(Content.boss("void_throne"))
	var runtime := Runtime.new()
	suite.assert_true(runtime.configure(parser.runtime_projection(), _identity()).ok, "real Void definition configures")
	suite.assert_true(runtime.configure_arena_origin(_point(origin)), "translated room origin binds")
	suite.assert_true(runtime.accept_damage_fact({"fact_id": "half-phase", "runtime_frame": 0, "target_source_id": "void-half", "amount": 2400.0, "hp_after": 600.0}).ok, "accepted body damage enters real third phase")
	for frame: int in range(1, 62):
		suite.assert_true(runtime.advance_frame(frame, _context(frame, origin), false).ok, "accepted phase warning advances")
	return runtime


func _test_room_half(origin: Vector2) -> void:
	var runtime := _configured(origin)
	var result: Dictionary = runtime.request_action("voidking_void_end", _context(61, origin))
	suite.assert_true(result.ok and result.threat_facts.size() == 3, "Void End warns exactly one room half and two circles")
	if not result.ok:
		return
	var line: Dictionary = result.threat_facts[0]
	suite.assert_equal(line.origin, _point(origin + Vector2(0, 90)), "marked half anchors to room top edge independent of Boss position")
	suite.assert_equal(line.aim_direction, _point(Vector2.RIGHT), "room half retains fixed horizontal direction")
	suite.assert_close(line.radius, 90.0, "marked half reaches the entire180px room half")
	suite.assert_close(line.length, 640.0, "marked half spans full room width")
	var registry := Threats.new()
	for fact: Dictionary in result.threat_facts:
		suite.assert_true(registry.register_fact(Action.native_threat_fact(fact)), "real registry admits declared half primitive")
	for x: int in [16, 160, 320, 480, 624]:
		suite.assert_true(registry.contains_point(origin + Vector2(x, 24), 61) and registry.contains_point(origin + Vector2(x, 168), 61), "full marked half has no unannounced edge gap")
	for x: int in [296, 320, 344]:
		for y: int in [228, 270, 318]:
			suite.assert_true(registry.nearest_threat_distance(origin + Vector2(x, y), 61) >= 14.0, "opposite half retains48px route with realPlayer radius")
	var before: Dictionary = runtime.snapshot()
	var encoded := Replay.encode_replay_json(before)
	var twin := _configured(origin)
	suite.assert_true(encoded.ok and twin.restore_snapshot(Replay.decode_replay_json(encoded.json).replay), "new half warning reconstructs typed cold state")
	suite.assert_equal(twin.snapshot(), before, "fresh translated half warning retains exact cold state")
	var forged := before.duplicate(true)
	forged.action.committed_origin.x += 1.0
	forged.action.committed_target.x += 1.0
	for fact: Dictionary in forged.action.committed_geometry:
		fact.origin.x += 1.0
		fact.target_point.x += 1.0
	suite.assert_true(not twin.can_restore_snapshot(forged), "forged room anchor fails strict cold preflight")
	var hit := {}
	for frame: int in range(62, 142):
		var moved := _context(frame, origin)
		moved.source_position = _point(origin + Vector2(480, 280))
		moved.target_position = _point(origin + Vector2(320, 270))
		var advanced: Dictionary = runtime.advance_frame(frame, moved, false)
		suite.assert_true(advanced.ok, "warned half advances despite real actors moving")
		if not advanced.hit_facts.is_empty():
			hit = advanced.hit_facts[0]
	suite.assert_true(not hit.is_empty() and hit.geometry == result.threat_facts, "full80framewarning produces the originally marked geometry")
	suite.assert_true(runtime.can_restore_native_snapshot(runtime.snapshot()), "active anchored cast passes auxiliary native cold agreement")


func _test_legacy_warning() -> void:
	var runtime := _configured(Vector2.ZERO)
	var old: Dictionary = runtime.snapshot()
	var parser := Definition.new()
	parser.configure(Content.boss("void_throne"))
	var legacy := Action.new()
	var identity := _identity()
	identity.erase("seed")
	legacy.configure({"id": "void_throne", "actor_kind": "boss", "actions": parser.runtime_projection().actions}, identity)
	for frame: int in range(1, 62):
		legacy.advance_frame(frame, _context(frame, Vector2.ZERO))
	legacy.request_action("voidking_void_end", _context(61, Vector2.ZERO))
	old.action = legacy.snapshot()
	old.mechanism_state.last_action_id = "voidking_void_end"
	old.mechanism_state.consecutive_actions = 1
	old.schema_version = 7
	old.erase("void_half_index")
	var upgraded: Dictionary = runtime.normalize_native_snapshot(old)
	suite.assert_true(not upgraded.is_empty() and upgraded.schema_version == 8, "exact historical schema7 upgrades to finite half counter")
	if upgraded.is_empty():
		return
	suite.assert_equal(upgraded.action, old.action, "migration preserves already warned historical source geometry")
	suite.assert_true(runtime.restore_snapshot(upgraded), "authenticated historical warning restores actual runtime")
	var forged: Dictionary = old.duplicate(true)
	forged.action.committed_geometry[0].origin.x += 1.0
	suite.assert_true(runtime.normalize_native_snapshot(forged).is_empty(), "forged historical warning cannot gain migration authority")
	for frame: int in range(62, 257):
		suite.assert_true(runtime.advance_frame(frame, _context(frame, Vector2.ZERO), false).ok, "historical warned cast advances without changed geometry")
	suite.assert_true(runtime.can_restore_native_snapshot(runtime.snapshot()), "historical active cast retains strict auxiliary agreement after migration")
	var next: Dictionary = runtime.request_action("voidking_void_bolt", _context(256, Vector2.ZERO))
	suite.assert_true(next.ok and runtime.snapshot().action.definition_digest != old.action.definition_digest, "idle migration adopts new room recipe for later actions")


func _test_enrage_alternation() -> void:
	var runtime := _configured(Vector2.ZERO)
	for frame: int in range(62, 10801):
		if not runtime.advance_frame(frame, _context(frame, Vector2.ZERO), false).ok:
			suite.assert_true(false, "all authored accepted frames reach enrage threshold")
			return
	var first: Dictionary = runtime.request_action("voidking_enrage_zero", _context(10800, Vector2.ZERO))
	suite.assert_true(first.ok and first.threat_facts[0].origin == {"x": 0.0, "y": 90.0}, "first committed enrage marks top half")
	var warning: Dictionary = runtime.snapshot()
	suite.assert_equal(warning.void_half_index, 1, "accepted warning consumes exactly one finite alternating index")
	suite.assert_true(runtime.restore_snapshot(warning), "real enrage warning reconstructs its accepted parity")
	var forged := warning.duplicate(true)
	forged.void_half_index = 2
	suite.assert_true(not runtime.can_restore_snapshot(forged), "forged enrage parity fails cold preflight")
	for frame: int in range(10801, 10891):
		suite.assert_true(runtime.advance_frame(frame, _context(frame, Vector2.ZERO), false).ok, "full enrage warning accepts real frames")
	runtime.cancel_action(&"fixture_next_normal_action")
	suite.assert_true(runtime.request_action("voidking_void_bolt", _context(10890, Vector2.ZERO)).ok, "intervening real action obeys consecutive-use policy")
	runtime.cancel_action(&"fixture_wait_authored_cooldown")
	for frame: int in range(10891, 11821):
		suite.assert_true(runtime.advance_frame(frame, _context(frame, Vector2.ZERO), false).ok, "accepted cooldown retains first enrage parity")
	var second: Dictionary = runtime.request_action("voidking_enrage_zero", _context(11820, Vector2.ZERO))
	suite.assert_true(second.ok and second.threat_facts[0].origin == {"x": 640.0, "y": 270.0} and second.threat_facts[0].aim_direction == {"x": -1.0, "y": 0.0}, "second committed enrage marks opposite room half across intervening action")
	suite.assert_equal(runtime.snapshot().void_half_index, 2, "second warning commits deterministic finite counter")
	suite.assert_true(runtime.can_restore_native_snapshot(runtime.snapshot()), "second enrage parity is a strict native cold boundary")
	var interrupted: Dictionary = runtime.accept_void_arena_damage({"fact_id": "half-core-break", "run_id": "run-half", "owner_source_id": "void-half", "construct_id": "void_plane_core:1:0", "runtime_frame": 11821, "amount": 100.0})
	suite.assert_true(interrupted.ok and not interrupted.retired_generations.is_empty() and runtime.snapshot().action.phase == "IDLE", "accepted real corebreak interrupts pending opposite enrage half")
	suite.assert_equal(runtime.snapshot().void_half_index, 2, "interrupted warned half cannot refund its accepted parity")


func _identity() -> Dictionary:
	return {"run_id": "run-half", "hostile_source_id": "void-half", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}


func _context(frame: int, origin: Vector2) -> Dictionary:
	return {"runtime_frame": frame, "source_position": _point(origin + Vector2(480, 144)), "target_position": _point(origin + Vector2(600, 280)), "facing_direction": _point(Vector2.RIGHT), "target_id": "player"}


func _point(value: Vector2) -> Dictionary:
	return {"x": float(value.x), "y": float(value.y)}
