extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Action := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Boss := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
var suite: RefCounted


class CountingBoss extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var fresh_action_calls := 0
	var action_validation_calls := 0

	func _make_action(phase_index: int, enraged: bool, room_half: bool = true, current_time_responses: bool = true) -> RefCounted:
		fresh_action_calls += 1
		return super._make_action(phase_index, enraged, room_half, current_time_responses)

	func _validation_action_matches(template: Dictionary, value: Dictionary) -> bool:
		action_validation_calls += 1
		return super._validation_action_matches(template, value)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for row: Dictionary in Content.read_catalog("bosses.json"):
		var parser := Definition.new()
		suite.assert_true(parser.configure(row).ok, "validation-only fixture consumes actual Boss " + row.id)
		var identity := Actions.identity()
		identity.seed = 42
		var runtime := CountingBoss.new()
		suite.assert_true(runtime.configure(parser.runtime_projection(), identity).ok, "actual Boss configures independent mutable gameplay authority")
		var initial := runtime.snapshot()
		suite.assert_true(runtime.call("_can_restore_snapshot_uncached", initial), "first full Boss validation passes complete cold authority")
		runtime.fresh_action_calls = 0
		for _repeat: int in range(8):
			suite.assert_true(runtime.call("_can_restore_snapshot_uncached", initial), "repeated complete Boss validation retains every original guard")
		suite.assert_equal(runtime.fresh_action_calls, 0, "repeated validation-only observations avoid fresh mutable Action configuration: " + row.id)
		suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(initial), "full repeated validation does not change any typed gameplay state")
		if runtime.has_method("_action_validation_template"):
			_test_regimes(runtime, row.id)
			_test_boss_boundaries(parser.runtime_projection(), identity)
			if row.id in ["void_throne", "time_sovereign"]:
				_test_boss_boundaries(parser.runtime_projection(), identity, true)
			_test_live_authority(runtime, initial)
			_test_bounds_and_failure(runtime, initial)
			_test_concurrency(runtime, initial)
			var previous: RefCounted = runtime.get("_action")
			suite.assert_true(runtime.restore_snapshot(initial) and not is_same(runtime.get("_action"), previous), "actual restoration still creates an independent mutable Action")
			var alternate := identity.duplicate(true)
			alternate.hostile_source_id = "other-template-owner"
			suite.assert_true(runtime.configure(parser.runtime_projection(), alternate).ok and runtime.get("_action_validation_cache").is_empty() and not runtime.can_restore_snapshot(initial), "reconfiguration clears templates and refuses previous owner")
	suite.finish(get_tree())


func _test_regimes(runtime: RefCounted, boss_id: String) -> void:
	var context: PackedByteArray = runtime.call("_snapshot_validation_context")
	for phase_index: int in range(runtime.get("_definition").phases.size()):
		for enraged: bool in [false, true]:
			for room_half: bool in [false, true]:
				for current_time: bool in [false, true]:
					var original: RefCounted = runtime.call("_make_action", phase_index, enraged, room_half, current_time)
					suite.assert_true(original != null, "cold authentic regime remains independently configurable")
					if original == null:
						continue
					var template: Dictionary = runtime.call("_action_validation_template", phase_index, enraged, room_half, current_time, context)
					var expected: Dictionary = original.snapshot_validation_template()
					suite.assert_equal(var_to_bytes(template), var_to_bytes(expected), "template retains exact cold normalized authority: " + boss_id)
					_assert_frozen(template)
					var idle: Dictionary = original.snapshot()
					suite.assert_true(_matches(template, idle), "pure validator accepts actual cold configured idle regime")
					var action: Dictionary = original.get("_definition").actions[0]
					suite.assert_true(original.request_action(str(action.id), Actions.context()).ok, "actual regime commits an authored action for pure validation")
					var warning: Dictionary = original.snapshot()
					suite.assert_true(_matches(template, warning), "pure validator retains actual current and historical warning geometry")
					for field: String in ["schema_version", "last_runtime_frame", "next_generation_floor", "decision_index", "commit_frame", "idle_through_frame", "paused_frames"]:
						var forged := warning.duplicate(true)
						forged[field] = float(forged[field])
						suite.assert_true(not _matches(template, forged), "pure validator retains exact integer guard: " + field)
					for field: String in ["definition_digest", "phase", "action_id"]:
						var forged := warning.duplicate(true)
						forged[field] = "foreign"
						suite.assert_true(not _matches(template, forged), "pure validator rejects foreign action authority: " + field)
					var forged := warning.duplicate(true)
					forged.target_id = "different-valid-target"
					suite.assert_true(_matches(template, forged), "pure Action validator preserves original stable target identifier acceptance")
					forged.target_id = ""
					suite.assert_true(not _matches(template, forged), "pure Action validator retains nonempty target identifier guard")
					forged.target_id = 1
					suite.assert_true(not _matches(template, forged), "pure Action validator retains String target identifier guard")
					forged = warning.duplicate(true)
					forged.identity.hostile_source_id = "foreign-owner"
					suite.assert_true(not _matches(template, forged), "pure validator cannot admit another owner")
					forged = warning.duplicate(true)
					forged.committed_geometry[0].radius += 1.0
					suite.assert_true(not _matches(template, forged), "pure validator retains exact authored committed geometry")
					forged = warning.duplicate(true)
					forged.unexpected = true
					suite.assert_true(not _matches(template, forged), "pure validator refuses unknown snapshot fields")
					forged = warning.duplicate(true)
					forged.erase("cooldowns")
					suite.assert_true(not _matches(template, forged), "pure validator refuses missing snapshot fields")
					runtime.fresh_action_calls = 0
					var repeated: Dictionary = runtime.call("_action_validation_template", phase_index, enraged, room_half, current_time, context)
					suite.assert_true(is_same(template, repeated) and runtime.fresh_action_calls == 0, "warm private template reuses only immutable data")
					_test_action_boundaries(original, template, action)
					_check_bounds(runtime)


func _test_action_boundaries(original: RefCounted, template: Dictionary, action: Dictionary) -> void:
	var active_start := int(action.warning_frames)
	var recovery_start := active_start + int(action.active_frames)
	var end_frame := recovery_start + int(action.recovery_frames)
	var boundaries := [active_start - 1, active_start, recovery_start - 1, recovery_start, end_frame - 1, end_frame]
	for frame: int in range(1, end_frame + 1):
		suite.assert_true(original.advance_frame(frame, Actions.context(frame)).ok, "authentic current or historical regime advances every action clock")
		if frame not in boundaries:
			continue
		var snapshot: Dictionary = original.snapshot()
		suite.assert_true(_matches(template, snapshot) and original.can_restore_snapshot(snapshot), "pure and live validators agree through warning, active, recovery and retirement")
		var fresh := Action.new()
		suite.assert_true(fresh.configure(original.get("_definition"), snapshot.identity).ok and fresh.restore_snapshot(snapshot), "independent mutable Action restores each original regime boundary")
		suite.assert_equal(var_to_bytes(fresh.snapshot()), var_to_bytes(snapshot), "all typed action clocks, geometry and hit claims survive boundary restoration")
		var next: Dictionary = original.advance_frame(frame + 1, Actions.context(frame + 1))
		suite.assert_equal(fresh.advance_frame(frame + 1, Actions.context(frame + 1)), next, "restored current and historical next hit/effect/retirement batches are exact")
		suite.assert_true(original.restore_snapshot(snapshot), "authentic action resumes its own original boundary")


func _test_boss_boundaries(definition: Dictionary, identity: Dictionary, historical: bool = false) -> void:
	var runtime := CountingBoss.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "complete Boss boundary fixture configures actual authority")
	if historical:
		if definition.id == "void_throne":
			runtime.set("_action", runtime.call("_make_action", 0, false, false, true))
			runtime.set("_legacy_void_action", true)
		else:
			runtime.set("_action", runtime.call("_make_action", 0, false, true, false))
			runtime.set("_legacy_time_action", true)
	var action: Dictionary = definition.actions[0]
	suite.assert_true(runtime.request_action(str(action.id), Actions.context()).ok, "complete Boss commits actual first authored action")
	var active_start := int(action.warning_frames)
	var recovery_start := active_start + int(action.active_frames)
	var end_frame := recovery_start + int(action.recovery_frames)
	var boundaries := [0, active_start - 1, active_start, recovery_start - 1, recovery_start, end_frame - 1, end_frame]
	for frame: int in range(end_frame + 1):
		if frame > 0:
			suite.assert_true(runtime.advance_frame(frame, Actions.context(frame), false).ok, "complete Boss accepts actual sequential action clock")
		if frame not in boundaries:
			continue
		var snapshot: Dictionary = runtime.snapshot()
		suite.assert_true(runtime.can_restore_native_snapshot(snapshot), "complete Boss template result retains strict auxiliary and receipt checks at every action boundary")
		runtime.action_validation_calls = 0
		suite.assert_true(runtime.call("_can_restore_snapshot_uncached", snapshot), "each full accepted boundary independently validates its Action authority")
		suite.assert_equal(runtime.action_validation_calls, 1, "complete Boss validation checks the selected Action template once")
		var fresh := Boss.new()
		suite.assert_true(fresh.configure(definition, identity).ok and fresh.restore_snapshot(snapshot), "independent complete Boss restores current or historical warning, active, recovery and ended state")
		suite.assert_equal(var_to_bytes(fresh.snapshot()), var_to_bytes(snapshot), "complete typed Boss and auxiliary state survives current or historical action boundary restoration")
		suite.assert_equal(fresh.advance_frame(frame + 1, Actions.context(frame + 1), false), runtime.advance_frame(frame + 1, Actions.context(frame + 1), false), "complete restored Boss next frame retains actual action and auxiliary outputs")
		suite.assert_true(runtime.restore_snapshot(snapshot), "complete Boss returns to its authentic current boundary")


func _test_live_authority(runtime: RefCounted, initial: Dictionary) -> void:
	var source: Dictionary = runtime.get("_definition").duplicate(true)
	var previous: PackedByteArray = runtime.call("_snapshot_validation_context")
	runtime.get("_definition").actions[0].warning_frames += 1
	var changed: PackedByteArray = runtime.call("_snapshot_validation_context")
	suite.assert_true(changed != previous and not runtime.can_restore_snapshot(initial), "direct definition mutation invalidates both complete and template verdicts")
	runtime.set("_definition", source.duplicate(true))
	suite.assert_true(runtime.call("_can_restore_snapshot_uncached", initial), "authentic source restores full cold validation")
	runtime.fresh_action_calls = 0
	runtime.get("_definition").actions[0].warning_frames = float(source.actions[0].warning_frames)
	changed = runtime.call("_snapshot_validation_context")
	suite.assert_true(changed != previous and runtime.call("_can_restore_snapshot_uncached", initial) and runtime.fresh_action_calls > 0, "numerically equal typed source change builds independently normalized authority")
	runtime.set("_definition", source.duplicate(true))
	var origin: Dictionary = runtime.get("_arena_origin").duplicate(true)
	suite.assert_true(runtime.call("_can_restore_snapshot_uncached", initial), "original origin has complete accepted authority")
	runtime.fresh_action_calls = 0
	runtime.get("_arena_origin").x += 1.0
	changed = runtime.call("_snapshot_validation_context")
	runtime.call("_can_restore_snapshot_uncached", initial)
	suite.assert_true(changed != previous and runtime.fresh_action_calls > 0, "direct live origin mutation cannot reuse a prior template context")
	runtime.set("_arena_origin", origin)
	suite.assert_true(runtime.call("_can_restore_snapshot_uncached", initial), "restored configured authority remains fully accepted")
	suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(initial), "authority observations leave complete typed gameplay state unchanged")


func _test_bounds_and_failure(runtime: RefCounted, initial: Dictionary) -> void:
	var before: int = runtime.get("_action_validation_cache").size()
	var source: Dictionary = runtime.get("_definition").duplicate(true)
	runtime.get("_definition").actions[0].warning_frames = -1
	var invalid_context: PackedByteArray = runtime.call("_snapshot_validation_context")
	suite.assert_true(runtime.call("_action_validation_template", 0, false, true, true, invalid_context).is_empty() and not runtime.call("_can_restore_snapshot_uncached", initial), "failed action configuration follows full cold refusal")
	suite.assert_equal(runtime.get("_action_validation_cache").size(), before, "failed source never populates the template cache")
	for entry: Dictionary in runtime.get("_action_validation_cache"):
		suite.assert_true(entry.context != invalid_context, "negative source cannot acquire retained validation authority")
	runtime.set("_definition", source)
	runtime.call("_clear_snapshot_validation_cache")
	var oversized := PackedByteArray()
	oversized.resize(Boss.MAX_ACTION_VALIDATION_TEMPLATE_BYTES + 1)
	runtime.fresh_action_calls = 0
	for _repeat: int in range(2):
		var template: Dictionary = runtime.call("_action_validation_template", 0, false, true, true, oversized)
		suite.assert_true(not template.is_empty() and _matches(template, initial.action), "oversized context still executes complete configured validation")
	suite.assert_true(runtime.get("_action_validation_cache").is_empty() and runtime.get("_action_validation_cache_bytes") == 0 and runtime.fresh_action_calls == 2, "oversized sources retain zero bytes and use independent uncached configurations")
	suite.assert_true(runtime.call("_can_restore_snapshot_uncached", initial), "bounded normal source still validates after oversized fallback")
	_check_bounds(runtime)


func _test_concurrency(runtime: RefCounted, initial: Dictionary) -> void:
	suite.assert_true(runtime.call("_can_restore_snapshot_uncached", initial), "concurrent fixture warms complete legitimate authority")
	var threads: Array[Thread] = []
	runtime.fresh_action_calls = 0
	for _worker: int in range(3):
		var thread := Thread.new()
		threads.append(thread)
		suite.assert_equal(thread.start(func() -> bool:
			for _step: int in range(12):
				if not runtime.call("_can_restore_snapshot_uncached", initial):
					return false
				var forged := initial.duplicate(true)
				forged.action.schema_version = 1.0
				if runtime.call("_can_restore_snapshot_uncached", forged):
					return false
			return true), OK, "concurrent pure-template validation worker starts")
	for thread: Thread in threads:
		suite.assert_true(thread.wait_to_finish(), "concurrent complete validation retains authentic and typed forged verdicts")
	_check_bounds(runtime)
	suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(initial), "concurrent validation leaves all typed gameplay state unchanged")


func _matches(template: Dictionary, snapshot: Dictionary) -> bool:
	return Action.can_restore_snapshot_with_authority(snapshot, template.actions, template.actor_kind, template.identity, template.definition_digest)


func _assert_frozen(value: Variant) -> void:
	if value is Dictionary or value is Array:
		suite.assert_true(value.is_read_only(), "all retained template containers are recursively read-only")
		for child: Variant in value.values() if value is Dictionary else value:
			_assert_frozen(child)
	else:
		suite.assert_true(typeof(value) != TYPE_OBJECT, "validation templates cannot retain mutable Action or scene objects")


func _check_bounds(runtime: RefCounted) -> void:
	var entries: Array = runtime.get("_action_validation_cache")
	var total := 0
	suite.assert_true(entries.size() <= Boss.MAX_ACTION_VALIDATION_CACHE, "validation template retention remains within four entries")
	for entry: Dictionary in entries:
		total += int(entry.bytes)
		suite.assert_true(entry.context is PackedByteArray and entry.bytes == entry.context.size() + var_to_bytes(entry.template).size() and entry.bytes <= Boss.MAX_ACTION_VALIDATION_TEMPLATE_BYTES, "retained source and immutable authority obey exact encoded byte limit")
	suite.assert_true(total == runtime.get("_action_validation_cache_bytes") and total <= Boss.MAX_ACTION_VALIDATION_CACHE_BYTES, "encoded template storage stays within its aggregate byte bound")
