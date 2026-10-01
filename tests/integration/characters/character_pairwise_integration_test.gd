extends Node

const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const REQUIRED_LAUNCH_REPLAY_SCHEMA_VERSION := 5
const CHARACTERS: Array[StringName] = [
	&"wanderer",
	&"time_guardian",
	&"void_walker",
	&"primordial_knight",
	&"time_lord",
]
const WEAPONS: Array[StringName] = [
	&"sword",
	&"bow",
	&"gun",
	&"staff",
	&"gauntlets",
]
const TIME_PAIRS: Array[Array] = [
	[&"stop", &"rewind"],
	[&"stop", &"rift"],
	[&"stop", &"accelerate"],
	[&"rewind", &"rift"],
	[&"rewind", &"accelerate"],
	[&"rift", &"accelerate"],
]

var _registry: RefCounted
var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report: RefCounted = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(
		not report.call("has_blocking_errors"),
		"pairwise fixture loads the authoritative Base Pack"
	)
	var rows := _pairwise_rows()
	_assert_exact_pairwise_coverage(rows)
	if not report.call("has_blocking_errors") and await _shared_contracts_are_ready():
		for row: Dictionary in rows:
			await _run_pairwise_case(row)
	_suite.finish(get_tree())


func _pairwise_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for character_index: int in range(CHARACTERS.size()):
		for time_pair_index: int in range(TIME_PAIRS.size()):
			var weapon_index := (character_index + time_pair_index) % WEAPONS.size()
			rows.append({
				"character_index": character_index,
				"character_id": CHARACTERS[character_index],
				"weapon_index": weapon_index,
				"weapon_id": WEAPONS[weapon_index],
				"time_pair_index": time_pair_index,
				"time_pair": TIME_PAIRS[time_pair_index].duplicate(true),
			})
	return rows


func _assert_exact_pairwise_coverage(rows: Array[Dictionary]) -> void:
	var character_weapon: Dictionary = {}
	var character_pair: Dictionary = {}
	var weapon_pair: Dictionary = {}
	for row: Dictionary in rows:
		var character_id := str(row["character_id"])
		var weapon_id := str(row["weapon_id"])
		var pair_index := int(row["time_pair_index"])
		character_weapon["%s:%s" % [character_id, weapon_id]] = true
		character_pair["%s:%d" % [character_id, pair_index]] = true
		weapon_pair["%s:%d" % [weapon_id, pair_index]] = true
	_suite.assert_equal(rows.size(), 30, "pairwise formula emits exactly thirty rows")
	_suite.assert_equal(
		character_weapon.size(),
		25,
		"pairwise rows cover all twenty-five character by weapon relationships"
	)
	_suite.assert_equal(
		character_pair.size(),
		30,
		"pairwise rows cover all thirty character by time-pair relationships"
	)
	_suite.assert_equal(
		weapon_pair.size(),
		30,
		"pairwise rows cover all thirty weapon by time-pair relationships"
	)


func _shared_contracts_are_ready() -> bool:
	var player := await _spawn_player()
	var configured: bool = player.configure_loadout(
		_config(&"wanderer", &"sword", TIME_PAIRS[0], 20261031)
	)
	_suite.assert_true(configured, "pairwise Replay prerequisite probe configures")
	var schema_version := 0
	if configured:
		schema_version = int(player.full_player_replay_snapshot().get("schema_version", 0))
	_suite.assert_equal(
		schema_version,
		REQUIRED_LAUNCH_REPLAY_SCHEMA_VERSION,
		"pairwise integration requires Task 7 Player Replay schema 5"
	)
	var boss := BossScene.instantiate()
	var boss_contract_ready := (
		boss.has_method("extend_character_boss_exposure")
		and boss.has_method("character_boss_exposure_snapshot")
		and boss.has_method("reset_character_boss_exposure_state")
	)
	_suite.assert_true(
		boss_contract_ready,
		"pairwise integration requires Chrono Warden character exposure authority"
	)
	boss.free()
	await _free_player(player)
	return (
		configured
		and schema_version == REQUIRED_LAUNCH_REPLAY_SCHEMA_VERSION
		and boss_contract_ready
	)


func _run_pairwise_case(row: Dictionary) -> void:
	var character_id := StringName(str(row["character_id"]))
	var weapon_id := StringName(str(row["weapon_id"]))
	var time_pair := row["time_pair"] as Array
	var case_index := int(row["character_index"]) * TIME_PAIRS.size() + int(
		row["time_pair_index"]
	)
	var label := "%s × %s × %s+%s" % [
		str(character_id),
		str(weapon_id),
		str(time_pair[0]),
		str(time_pair[1]),
	]
	var player := await _spawn_player()
	var configured: bool = player.configure_loadout(
		_config(character_id, weapon_id, time_pair, 20261031 + case_index)
	)
	_suite.assert_true(configured, "%s configures the real Player" % label)
	if not configured:
		await _free_player(player)
		return

	var room_id := StringName("pairwise-room-%02d" % case_index)
	EventBus.room_started.emit(str(player.current_run_id()), room_id, 1)
	_suite.assert_true(player.advance_action_frame({}), "%s enters the room on the fixed frame" % label)

	var boss := BossScene.instantiate()
	boss.set_physics_process(false)
	var hostile_source_id := StringName("hostile:pairwise:%02d" % case_index)
	_suite.assert_true(
		boss.configure_hostile_identity(hostile_source_id, 1),
		"%s configures stable Chrono Warden identity" % label
	)
	boss.set_meta("run_id", player.current_run_id())
	boss.set_meta("room_id", room_id)
	boss.set_meta("encounter_id", StringName("encounter-%02d" % case_index))
	boss.set_meta("encounter_spawn_id", StringName("spawn-%02d" % case_index))
	boss.set_meta("encounter_enemy_id", &"chrono_warden")
	add_child(boss)
	await get_tree().process_frame
	var stop_generation := case_index + 1
	boss.apply_time_stop_source(StringName("pairwise-stop-%02d" % case_index), 0.5)
	_suite.assert_true(
		boss.call("extend_character_boss_exposure", stop_generation, 30),
		"%s executes Chrono Warden Stop exposure conversion" % label
	)
	boss.clear_time_stop_source(StringName("pairwise-stop-%02d" % case_index))
	var boss_checkpoint: Dictionary = boss.call("character_boss_exposure_snapshot")
	_suite.assert_equal(
		int(boss_checkpoint.get("claimed_stop_generation_floor", 0)),
		stop_generation,
		"%s captures the converted Boss generation" % label
	)

	var checkpoint: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_equal(
		int(checkpoint.get("schema_version", 0)),
		REQUIRED_LAUNCH_REPLAY_SCHEMA_VERSION,
		"%s captures Player Replay schema 5" % label
	)
	_suite.assert_true(player.advance_action_frame({}), "%s diverges after checkpoint" % label)
	_suite.assert_true(
		player.restore_full_player_replay_snapshot(checkpoint),
		"%s restores the Player Replay checkpoint atomically" % label
	)
	_suite.assert_equal(
		player.full_player_replay_snapshot(),
		checkpoint,
		"%s restore reproduces the exact Player checkpoint" % label
	)

	EventBus.room_cleared.emit(str(player.current_run_id()), room_id, 2)
	_suite.assert_true(player.reset_runtime_state(), "%s terminal cleanup resets Player" % label)
	boss.call("reset_character_boss_exposure_state")
	var terminal_boss: Dictionary = boss.call("character_boss_exposure_snapshot")
	_suite.assert_equal(
		int(terminal_boss.get("remaining_tail_frames", -1)),
		0,
		"%s terminal cleanup clears Boss exposure duration" % label
	)
	_suite.assert_true(
		(player.get_node("WorldPayloadAuthority").call("replay_snapshot").get(
			"descriptors", []
		) as Array).is_empty(),
		"%s terminal cleanup clears world payload descriptors" % label
	)
	boss.queue_free()
	await get_tree().process_frame
	await _free_player(player)


func _config(
	character_id: StringName,
	weapon_id: StringName,
	time_pair: Array,
	seed_value: int
) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": str(character_id),
		"character_profile": _registry.call(
			"resolve_character_runtime_profile", character_id, &"LAUNCH"
		),
		"character_talents": [],
		"weapon_id": str(weapon_id),
		"weapon_profile": _registry.call(
			"resolve_weapon_runtime_profile", weapon_id, &"LAUNCH"
		),
		"enabled_time_skills": time_pair.duplicate(true),
		"difficulty": "normal",
		"seed": seed_value,
	}


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	return player


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
