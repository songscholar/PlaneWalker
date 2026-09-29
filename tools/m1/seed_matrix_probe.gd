extends Node

const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const MainScene := preload("res://scenes/main.tscn")

const CHOICE_DURATION_PROXY_MS := 8000
const MAX_WAIT_FRAMES := 180
const PROBE_VERSION := "2.0.0"

var _original_save_path: String
var _original_persistent: Dictionary
var _probe_save_path := "/tmp/planewalker_m1_seed_matrix_probe_%d.json" % OS.get_process_id()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var seed_start := int(OS.get_environment("PLANEWALKER_M1_SEED_START"))
	var seed_count := int(OS.get_environment("PLANEWALKER_M1_SEED_COUNT"))
	var output_path := OS.get_environment("PLANEWALKER_M1_RAW_OUTPUT")
	if seed_count <= 0 or output_path.is_empty():
		push_error("M1 seed probe requires a positive seed count and output path")
		get_tree().quit(2)
		return

	_original_save_path = GameState.save_path
	_original_persistent = GameState.persistent.duplicate(true)
	GameState.save_path = _probe_save_path
	GameState.reset_persistent_data(true)
	var runs: Array[Dictionary] = []
	for seed_value: int in range(seed_start, seed_start + seed_count):
		runs.append(await _run_seed(seed_value))
	_restore_profile_state()
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("M1 seed probe could not open output path: %s" % output_path)
		get_tree().quit(3)
		return
	file.store_string(JSON.stringify({"probe_version": PROBE_VERSION, "runs": runs}, "  ", false) + "\n")
	file.close()
	get_tree().quit(0)


func _run_seed(seed_value: int) -> Dictionary:
	_reset_probe_state()
	var result := {
		"seed": seed_value,
		"terminal_state": "technical_failure",
		"room_sequence": [],
		"encounter_ids": [],
		"spawn_sequences": [],
		"reward_offers": [],
		"selected_choices": [],
		"choice_snapshots": [],
		"failure_codes": [],
		"duration_proxy_ms": 0,
	}
	var main: Node = MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var room := main.get_node_or_null("CombatRoom01")
	var host := main.get_node_or_null("RunRuntimeHost")
	if room == null or host == null or not bool(host.get("_active")):
		_add_failure(result, "runtime_boot_failed")
		await _cleanup_main(main)
		return result
	var panel := host.get_node_or_null("ChoiceLayer/ChoicePanelV2")
	room.set("spawn_warning_duration", 0.0)
	room.visible = true
	room.process_mode = Node.PROCESS_MODE_INHERIT
	var started: Variant = host.call("start_run", {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["time_stop", "time_rewind"],
		"difficulty": "normal",
		"seed": seed_value,
	})
	if started == null or not bool(started.get("ok")):
		_add_failure(result, "runtime_start_failed")
		await _cleanup_main(main)
		return result
	await get_tree().process_frame
	if not bool(room.get("_authored_runtime_enabled")):
		_add_failure(result, "authored_runtime_disabled")
		await _cleanup_main(main)
		return result
	var facade: RefCounted = host.get("_facade")

	for room_number: int in range(1, 5):
		if not await _wait_for_phase(facade, RunPhaseScript.Value.COMBAT_ACTIVE):
			_add_failure(result, "room_%d_combat_phase_timeout" % room_number)
			break
		var room_definition: Dictionary = facade.call("current_room_definition")
		_record_room(result, room_definition)
		var wave_sequences: Array = []
		var wave_count := _wave_count(facade, room_definition, seed_value, room_number)
		for wave_index: int in range(wave_count):
			var enemies := await _wait_for_spawned_enemies(room)
			if enemies.is_empty():
				_add_failure(result, "room_%d_wave_%d_spawn_timeout" % [room_number, wave_index + 1])
				break
			var identities: Array[String] = []
			for enemy: Node in enemies:
				identities.append(str(enemy.get_meta("encounter_enemy_id", "")))
			wave_sequences.append(identities)
			await _defeat_spawned_enemies(enemies)
		result["spawn_sequences"].append(wave_sequences)
		if not result["failure_codes"].is_empty():
			break
		if not await _wait_for_offer(facade):
			_add_failure(result, "room_%d_offer_timeout" % room_number)
			break
		var snapshot: Dictionary = facade.call("snapshot")
		var offer: Dictionary = snapshot.get("open_offer", {})
		var option_ids: Array[String] = []
		for option_value: Variant in offer.get("options", []):
			if option_value is Dictionary:
				option_ids.append(str(option_value.get("option_id", "")))
		result["reward_offers"].append(option_ids)
		var buttons := _option_buttons(panel)
		if buttons.is_empty() or option_ids.is_empty():
			_add_failure(result, "room_%d_offer_not_selectable" % room_number)
			break
		result["selected_choices"].append(option_ids[0])
		buttons[0].pressed.emit()
		result["duration_proxy_ms"] += CHOICE_DURATION_PROXY_MS
		await get_tree().process_frame
		var post_choice_snapshot: Dictionary = facade.call("snapshot")
		var post_choice_build: Dictionary = (post_choice_snapshot.get("build", {}) as Dictionary).duplicate(true)
		result["choice_snapshots"].append({
			"choice_id": option_ids[0],
			"revision": int(post_choice_snapshot.get("revision", -1)),
			"outcome": "no_state_change" if option_ids[0] == "decline_contract" else "applied",
			"build": post_choice_build,
		})

	if result["failure_codes"].is_empty():
		if not await _wait_for_phase(facade, RunPhaseScript.Value.BOSS_ACTIVE):
			_add_failure(result, "boss_phase_timeout")
		else:
			var boss_definition: Dictionary = facade.call("current_room_definition")
			_record_room(result, boss_definition)
			var boss_waves: Array = []
			var boss_wave_count := _wave_count(facade, boss_definition, seed_value, 5)
			for wave_index: int in range(boss_wave_count):
				var enemies := await _wait_for_spawned_enemies(room)
				if enemies.is_empty():
					_add_failure(result, "boss_wave_%d_spawn_timeout" % (wave_index + 1))
					break
				var identities: Array[String] = []
				for enemy: Node in enemies:
					identities.append(str(enemy.get_meta("encounter_enemy_id", "")))
				boss_waves.append(identities)
				await _defeat_spawned_enemies(enemies)
			result["spawn_sequences"].append(boss_waves)
			await get_tree().process_frame
			var final_snapshot: Dictionary = facade.call("snapshot")
			if int(final_snapshot.get("phase", -1)) != RunPhaseScript.Value.VICTORY:
				_add_failure(result, "victory_not_reached")

	if result["failure_codes"].is_empty():
		result["terminal_state"] = "victory"
	await _cleanup_main(main)
	return result


func _record_room(result: Dictionary, definition: Dictionary) -> void:
	result["room_sequence"].append(int(definition.get("room_number", 0)))
	result["encounter_ids"].append(str(definition.get("encounter_id", "")))
	var target_min := int(definition.get("target_seconds_min", 0))
	var target_max := int(definition.get("target_seconds_max", 0))
	result["duration_proxy_ms"] += int(round((target_min + target_max) * 500.0))


func _wave_count(facade: RefCounted, room_definition: Dictionary, seed_value: int, room_number: int) -> int:
	var catalog: RefCounted = facade.call("encounter_catalog")
	var encounter: Dictionary = catalog.call(
		"encounter_definition",
		str(room_definition.get("encounter_id", "")),
		seed_value,
		room_number
	)
	return encounter.get("waves", []).size()


func _wait_for_phase(facade: RefCounted, expected_phase: int) -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		var snapshot: Dictionary = facade.call("snapshot")
		if int(snapshot.get("phase", -1)) == expected_phase:
			return true
		await get_tree().process_frame
	return false


func _wait_for_offer(facade: RefCounted) -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		var snapshot: Dictionary = facade.call("snapshot")
		if not (snapshot.get("open_offer", {}) as Dictionary).is_empty():
			return true
		await get_tree().process_frame
	return false


func _wait_for_spawned_enemies(room: Node) -> Array[Node]:
	var enemies_root := room.get_node("Enemies")
	for _frame: int in range(MAX_WAIT_FRAMES):
		var children: Array[Node] = []
		for child: Node in enemies_root.get_children():
			if not child.is_queued_for_deletion():
				children.append(child)
		if not children.is_empty():
			return children
		await get_tree().process_frame
	return []


func _defeat_spawned_enemies(enemies: Array[Node]) -> void:
	for enemy: Node in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		EventBus.entity_died.emit(enemy, null)
		enemy.queue_free()
	await get_tree().process_frame


func _option_buttons(panel: Control) -> Array[Button]:
	var buttons: Array[Button] = []
	if panel == null:
		return buttons
	var container := panel.get_node_or_null("SafeArea/Center/PanelRoot/Content/OptionsContainer")
	if container == null:
		return buttons
	for child: Node in container.get_children():
		if child is Button:
			buttons.append(child as Button)
	return buttons


func _add_failure(result: Dictionary, code: String) -> void:
	if not result["failure_codes"].has(code):
		result["failure_codes"].append(code)


func _cleanup_main(main: Node) -> void:
	get_tree().paused = false
	if main != null and is_instance_valid(main):
		main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if CombatFeedback != null and CombatFeedback.has_method("reset_transient_feedback"):
		CombatFeedback.call("reset_transient_feedback")
	await get_tree().process_frame
	await get_tree().process_frame
	_reset_probe_state()


func _reset_probe_state() -> void:
	get_tree().paused = false


func _restore_profile_state() -> void:
	_reset_probe_state()
	GameState.save_path = _original_save_path
	GameState.persistent = _original_persistent.duplicate(true)
	if FileAccess.file_exists(_probe_save_path):
		DirAccess.remove_absolute(_probe_save_path)
