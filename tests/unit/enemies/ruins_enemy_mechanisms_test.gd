extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
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
		_test_authored_shell_and_interrupt(implementation)
	suite.finish(get_tree())


static func strider_definition() -> Dictionary:
	var parser := Enemy.new()
	return parser.runtime_projection() if parser.configure(Content.enemy("stone_shell_strider")).ok else {}


static func wraith_definition() -> Dictionary:
	var parser := Enemy.new()
	return parser.runtime_projection() if parser.configure(Content.enemy("ruins_wraith")).ok else {}


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


func _test_authored_shell_and_interrupt(implementation: Script) -> void:
	var shell := strider_definition()
	shell.mechanisms.shell_frames = 60
	shell.mechanisms.shell_damage_multiplier = 0.5
	shell.mechanisms.open_frames = 15
	shell.mechanisms.open_damage_multiplier = 1.1
	var runtime := _runtime(implementation, shell)
	if runtime.snapshot().is_empty():
		return
	runtime.accept_damage_fact(_fact("authored-shell", 0, 10.0, 110.0))
	suite.assert_equal(runtime.snapshot().mechanism_state.shell_remaining_frames, 60, "shell uses authored lifetime")
	suite.assert_equal(runtime.species_damage_taken_multiplier(), 0.5, "shell uses authored damage multiplier")
	for frame: int in range(1, 61):
		runtime.advance_frame(frame, Actions.context(frame), false)
	suite.assert_equal(runtime.snapshot().mechanism_state.open_remaining_frames, 15, "exposure uses authored lifetime")
	suite.assert_equal(runtime.species_damage_taken_multiplier(), 1.1, "exposure uses authored damage multiplier")
	var bad: Dictionary = runtime.snapshot()
	bad.mechanism_state.open_remaining_frames = 16
	suite.assert_true(not runtime.can_restore_snapshot(bad), "exposure cannot restore beyond the authored bound")
	var wraith := wraith_definition()
	wraith.mechanisms.windup_interrupt_damage = 10.0
	wraith.mechanisms.stagger_frames = 45
	var interrupted := _runtime(implementation, wraith)
	interrupted.request_action("ruins_wraith.spirit_detonation", Actions.context())
	suite.assert_true(interrupted.accept_damage_fact(_fact("authored-interrupt", 0, 10.0, 40.0)).ok, "authored interrupt threshold accepts authenticated damage")
	suite.assert_equal(interrupted.snapshot().mechanism_state.stagger_remaining_frames, 45, "authored interrupt threshold creates authored stagger")
	var motion: Dictionary = interrupted.motion_for_frame(1, Actions.context(1))
	suite.assert_equal(motion.displacement, {"x": 0.0, "y": 0.0}, "stagger prevents actual pursuit movement")
