extends Node

const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const ABILITY_IDS := ["stop", "rewind", "rift", "accelerate"]
const LOADOUTS := [
	["stop", "rewind"],
	["stop", "rift"],
	["stop", "accelerate"],
	["rewind", "rift"],
	["rewind", "accelerate"],
	["rift", "accelerate"],
]


var _suite
var _time_started: Dictionary = {}
var _time_ended: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_expired_rift_cleanup_paths()
	EventBus.time_skill_started.connect(_on_time_skill_started)
	EventBus.time_skill_ended.connect(_on_time_skill_ended)
	var selected_loadouts := _selected_loadouts()
	var expected_counts: Dictionary = {}
	for ability_id: String in ABILITY_IDS:
		expected_counts[ability_id] = 0
	for pair: Array in selected_loadouts:
		await _certify_pair(pair)
		for ability_id: String in pair:
			expected_counts[ability_id] = int(expected_counts[ability_id]) + 1
	for ability_id: String in ABILITY_IDS:
		var action_id := StringName("time_%s" % ability_id)
		_suite.assert_equal(_start_count(action_id), expected_counts[ability_id], "%s starts once in each containing pair" % ability_id)
		_suite.assert_equal(_end_count(action_id), expected_counts[ability_id], "%s ends once in each containing pair" % ability_id)
	EventBus.time_skill_started.disconnect(_on_time_skill_started)
	EventBus.time_skill_ended.disconnect(_on_time_skill_ended)
	_suite.finish(get_tree())


func _selected_loadouts() -> Array:
	var pair_filter := OS.get_environment("PLANEWALKER_TIME_PAIR").strip_edges()
	if pair_filter.is_empty():
		return LOADOUTS
	for pair: Array in LOADOUTS:
		if pair_filter == "%s,%s" % [pair[0], pair[1]]:
			return [pair]
	_suite.assert_true(false, "PLANEWALKER_TIME_PAIR selects one canonical unordered pair")
	return []


func _test_expired_rift_cleanup_paths() -> void:
	var player := PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0
	manager.time_rift_duration = 0.02
	_suite.assert_true(manager.try_time_rift(player.global_position), "expired-Rift fixture commits")
	var active_rifts := get_tree().get_nodes_in_group("time_rifts")
	_suite.assert_equal(active_rifts.size(), 1, "expired-Rift fixture owns one Rift")
	if active_rifts.size() == 1:
		player.advance_action_frame()
		player.advance_action_frame()
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "expired Rift leaves the scene tree")
	manager.cancel_all_time_effects(&"expired_rift_cancel")
	manager.reset_runtime_state()
	_suite.assert_true((manager.get("_active_rifts") as Array).is_empty(), "cancel/reset prunes expired Rift references")
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _certify_pair(pair: Array) -> void:
	var label := str(pair)
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "%s starts without a stale Rift" % label)
	var player := PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	_suite.assert_true(player.configure_loadout(_config(pair)), "%s configures through NEXT" % label)
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0
	manager.time_stop_duration = 0.04
	manager.time_rift_duration = 0.04
	manager.time_accelerate_duration = 0.04
	if pair.has("rewind"):
		player.rewind_recorder.clear_snapshots()
		player.rewind_recorder._record_snapshot()

	var baselines: Dictionary = {}
	for ability_id: String in ABILITY_IDS:
		var action_id := StringName("time_%s" % ability_id)
		baselines[action_id] = {
			"started": _start_count(action_id),
			"ended": _end_count(action_id),
		}

	for ability_id: String in pair:
		var action_id := StringName("time_%s" % ability_id)
		_suite.assert_true(player.try_action(action_id), "%s commits equipped %s" % [label, ability_id])
		_finish_time_cast(player, "%s completes %s cast" % [label, ability_id])

	for ability_id: String in ABILITY_IDS:
		var action_id := StringName("time_%s" % ability_id)
		var baseline: Dictionary = baselines[action_id]
		if pair.has(ability_id):
			_suite.assert_equal(
				_start_count(action_id),
				int(baseline["started"]) + 1,
				"%s publishes one %s start" % [label, ability_id]
			)
			continue
		manager.energy = manager.max_energy
		var energy_before: float = manager.energy
		var cooldown_before: float = manager.get_cooldown(action_id)
		var action_state_before: int = player.action_state.current_state
		var facts_before := _fact_total()
		var rifts_before := get_tree().get_nodes_in_group("time_rifts").size()
		var accelerated_before: bool = player.is_time_accelerated()
		_suite.assert_true(not player.try_action(action_id), "%s rejects unequipped %s" % [label, ability_id])
		_suite.assert_close(manager.energy, energy_before, "%s rejected %s preserves energy" % [label, ability_id])
		_suite.assert_close(
			manager.get_cooldown(action_id),
			cooldown_before,
			"%s rejected %s preserves cooldown" % [label, ability_id]
		)
		_suite.assert_equal(
			player.action_state.current_state,
			action_state_before,
			"%s rejected %s preserves the action clock" % [label, ability_id]
		)
		_suite.assert_equal(_fact_total(), facts_before, "%s rejected %s publishes zero facts" % [label, ability_id])
		_suite.assert_equal(
			get_tree().get_nodes_in_group("time_rifts").size(),
			rifts_before,
			"%s rejected %s spawns no Rift" % [label, ability_id]
		)
		_suite.assert_equal(
			player.is_time_accelerated(),
			accelerated_before,
			"%s rejected %s changes no acceleration" % [label, ability_id]
		)

	player.cancel_active_time_effects(&"matrix_smoke_cleanup")
	await get_tree().process_frame
	player.cancel_active_time_effects(&"matrix_smoke_idempotence")
	await get_tree().create_timer(0.08).timeout
	for ability_id: String in ABILITY_IDS:
		var action_id := StringName("time_%s" % ability_id)
		var baseline: Dictionary = baselines[action_id]
		var expected_delta := 1 if pair.has(ability_id) else 0
		_suite.assert_equal(
			_start_count(action_id),
			int(baseline["started"]) + expected_delta,
			"%s preserves exactly-once %s start after cleanup" % [label, ability_id]
		)
		_suite.assert_equal(
			_end_count(action_id),
			int(baseline["ended"]) + expected_delta,
			"%s publishes exactly one %s end" % [label, ability_id]
		)

	_suite.assert_true(not bool(manager.get("_time_stop_active")), "%s leaves no active Stop" % label)
	_suite.assert_true(not bool(manager.get("_time_accelerate_active")), "%s leaves no active Accelerate manager state" % label)
	_suite.assert_true(not player.is_time_accelerated(), "%s leaves no Player acceleration" % label)
	_suite.assert_true((manager.get("_active_rifts") as Array).is_empty(), "%s leaves no manager Rift reference" % label)
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "%s leaves no Rift node" % label)

	var counts_before_free := _fact_total()
	var health: Node = player.get_node("HealthComponent")
	if not (health.get("_active_invulnerability_tokens") as Dictionary).is_empty():
		await get_tree().create_timer(0.55).timeout
	player.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.08).timeout
	_suite.assert_true(not is_instance_valid(player), "%s frees its Player fixture" % label)
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "%s stays Rift-free after fixture disposal" % label)
	_suite.assert_equal(_fact_total(), counts_before_free, "%s stale callbacks publish no extra lifecycle facts" % label)


func _finish_time_cast(player: Node, label: String) -> void:
	for _frame: int in range(24):
		if player.action_state.current_state == PlayerActionStateScript.State.FREE:
			break
		player.advance_action_frame()
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, label)


func _config(ability_ids: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ability_ids.duplicate(true),
		"difficulty": "normal",
		"seed": 20260929,
	}


func _fact_total() -> Dictionary:
	return {
		"started": _time_started.duplicate(true),
		"ended": _time_ended.duplicate(true),
	}


func _start_count(skill_id: StringName) -> int:
	return int(_time_started.get(skill_id, 0))


func _end_count(skill_id: StringName) -> int:
	return int(_time_ended.get(skill_id, 0))


func _on_time_skill_started(skill_id: StringName, _context: Dictionary) -> void:
	_time_started[skill_id] = _start_count(skill_id) + 1


func _on_time_skill_ended(skill_id: StringName, _context: Dictionary) -> void:
	_time_ended[skill_id] = _end_count(skill_id) + 1
