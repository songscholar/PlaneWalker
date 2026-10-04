extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/launch_enemy_runtime.gd")
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.has_method("accept_damage_fact"), "Ruins domain accepts authoritative Health damage facts")
	if runtime.has_method("accept_damage_fact"):
		_test_shell_cycle(implementation)
		_test_wraith_interrupt(implementation)
	suite.finish(get_tree())


static func strider_definition() -> Dictionary:
	var charge := Actions.action()
	charge.id = "stone_shell_strider.shell_charge"
	charge.handler_id = "charge"
	charge.active_frames = 12
	charge.cooldown_frames = 180
	charge.distance_max_px = 48.0
	charge.geometry = [{"shape": "line", "origin_offset": {"x": 0.0, "y": 0.0}, "aim_offset_degrees": 0.0, "radius": 8.0, "length": 48.0}]
	charge.hit_schedule[0].damage = 15.0
	charge.parameters = {"travel_px": 48.0, "speed_px_per_second": 240.0, "knockback_px": 0.0}
	var bite := Actions.action()
	bite.id = "stone_shell_strider.bite"
	bite.active_frames = 5
	bite.recovery_frames = 20
	bite.cooldown_frames = 120
	bite.weight = 6
	bite.distance_max_px = 24.0
	bite.geometry = [{"shape": "cone", "origin_offset": {"x": 0.0, "y": 0.0}, "aim_offset_degrees": 0.0, "radius": 12.0, "length": 24.0}]
	bite.hit_schedule[0].damage = 10.0
	bite.parameters.knockback_px = 0.0
	return {"id": "stone_shell_strider", "actor_kind": "enemy", "runtime_kind": "stone_shell_strider", "max_hp": 120.0, "defense": 0.0, "move_speed": 72.0, "actions": [charge, bite]}


static func wraith_definition() -> Dictionary:
	var detonation := Actions.action()
	detonation.id = "ruins_wraith.spirit_detonation"
	detonation.warning_frames = 60
	detonation.active_frames = 6
	detonation.recovery_frames = 20
	detonation.cooldown_frames = 0
	detonation.distance_max_px = 32.0
	detonation.geometry = [{"shape": "circle", "origin_offset": {"x": 0.0, "y": 0.0}, "aim_offset_degrees": 0.0, "radius": 32.0, "length": 0.0}]
	detonation.hit_schedule[0].damage = 20.0
	detonation.parameters.knockback_px = 0.0
	return {"id": "ruins_wraith", "actor_kind": "enemy", "runtime_kind": "ruins_wraith", "max_hp": 50.0, "defense": 0.0, "move_speed": 80.0, "actions": [detonation]}


func _runtime(implementation: Script, definition: Dictionary) -> RefCounted:
	var runtime: RefCounted = implementation.new()
	var identity := Actions.identity()
	identity["seed"] = 42
	suite.assert_true(runtime.configure(definition, identity).ok, "Ruins species accepts its own concrete action kit")
	return runtime


func _fact(id: String, frame: int, amount: float, hp_after: float) -> Dictionary:
	return {"fact_id": id, "runtime_frame": frame, "target_source_id": "hostile:test-a", "amount": amount, "hp_after": hp_after}


func _test_shell_cycle(implementation: Script) -> void:
	var runtime := _runtime(implementation, strider_definition())
	if runtime.snapshot().is_empty():
		return
	suite.assert_true(runtime.accept_damage_fact(_fact("shell-hit-1", 0, 12.0, 108.0)).ok, "first actual hit opens bounded shell cycle")
	suite.assert_equal(runtime.snapshot().mechanism_state.shell_remaining_frames, 120, "shell begins at exactly 120 accepted frames")
	suite.assert_equal(runtime.species_damage_taken_multiplier(), 0.30, "closed shell reduces actual incoming damage")
	runtime.accept_damage_fact(_fact("shell-hit-2", 0, 12.0, 96.0))
	suite.assert_equal(runtime.snapshot().mechanism_state.shell_remaining_frames, 120, "second hit does not restart shell")
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.accept_damage_fact(_fact("shell-hit-2", 0, 12.0, 84.0)).ok, "duplicate Health fact rejects")
	suite.assert_equal(runtime.snapshot(), before, "duplicate fact cannot mutate shell expenditure or claims")
	for frame: int in range(1, 121):
		suite.assert_true(runtime.advance_frame(frame, Actions.context(frame), false).ok, "shell lifetime advances with accepted frame")
	suite.assert_equal(runtime.snapshot().mechanism_state.shell_remaining_frames, 0, "shell ends after exactly 120 accepted frames")
	suite.assert_equal(runtime.snapshot().mechanism_state.open_remaining_frames, 30, "shell expiry creates 30-frame exposure")
	suite.assert_equal(runtime.species_damage_taken_multiplier(), 1.30, "open shell exposes native damage multiplier")
	runtime.accept_damage_fact(_fact("open-hit", 120, 10.0, 86.0))
	suite.assert_equal(runtime.snapshot().mechanism_state.open_remaining_frames, 30, "open-state hit cannot close or restart shell")
	for frame: int in range(121, 151):
		runtime.advance_frame(frame, Actions.context(frame), false)
	suite.assert_equal(runtime.species_damage_taken_multiplier(), 1.0, "exposure expires without permanent vulnerability")
	runtime.accept_damage_fact(_fact("shell-hit-3", 150, 10.0, 76.0))
	suite.assert_equal(runtime.snapshot().mechanism_state.shell_cycle, 2, "later hit opens next once-owned shell cycle")
	var corrupted: Dictionary = runtime.snapshot()
	corrupted.mechanism_state.open_remaining_frames = 30
	suite.assert_true(not runtime.restore_snapshot(corrupted), "simultaneous closed and open shell state rejects")


func _test_wraith_interrupt(implementation: Script) -> void:
	var runtime := _runtime(implementation, wraith_definition())
	if runtime.snapshot().is_empty():
		return
	suite.assert_true(runtime.request_action("ruins_wraith.spirit_detonation", Actions.context()).ok, "wraith commits full 60-frame detonation warning")
	for frame: int in range(1, 11):
		runtime.advance_frame(frame, Actions.context(frame), false)
	runtime.accept_damage_fact(_fact("wraith-hit-1", 10, 7.0, 43.0))
	suite.assert_equal(runtime.snapshot().action.phase, "WARNING", "less than fifteen damage preserves warned detonation")
	var interrupted: Dictionary = runtime.accept_damage_fact(_fact("wraith-hit-2", 10, 8.0, 35.0))
	suite.assert_true(interrupted.ok and not interrupted.retired_generations.is_empty(), "cumulative fifteen damage retires every committed threat")
	suite.assert_equal(runtime.snapshot().mechanism_state.stagger_remaining_frames, 30, "wraith interruption enters exactly thirty-frame stagger")
	suite.assert_equal(runtime.snapshot().action.phase, "IDLE", "interrupted warning cannot reach active explosion")
	for frame: int in range(11, 41):
		var result: Dictionary = runtime.advance_frame(frame, Actions.context(frame), false)
		suite.assert_true(result.hit_facts.is_empty(), "stagger emits zero explosion damage")
	suite.assert_equal(runtime.snapshot().mechanism_state.stagger_remaining_frames, 0, "wraith stagger ends at bounded accepted frame")
	suite.assert_true(runtime.request_action("ruins_wraith.spirit_detonation", Actions.context(40)).ok, "wraith may warn again after stagger")
	runtime.accept_damage_fact(_fact("wraith-lethal", 40, 50.0, 0.0))
	var after_kill: Dictionary = runtime.advance_frame(41, Actions.context(41), false)
	suite.assert_true(after_kill.hit_facts.is_empty(), "pre-active final Health kill cancels all explosion hits")
