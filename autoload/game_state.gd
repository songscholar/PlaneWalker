extends Node

const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")

enum GamePhase {
	BOOT,
	HUB,
	RUN_START,
	DUNGEON,
	ROOM_CLEAR,
	SELECTION,
	BOSS_FIGHT,
	DEATH,
	RUN_END,
	PAUSED,
}

var phase: GamePhase = GamePhase.BOOT
var current_floor: int = 1
var current_room: int = 0
var run_seed: int = 0
var run_timer: float = 0.0
var death_count: int = 0

var current_run: Dictionary = {}
var last_run_result: Dictionary = {}
var save_path: String = "user://plane_walker_save.json"
var persistent: Dictionary = {}
var build_state: RefCounted


func _ready() -> void:
	phase = GamePhase.BOOT
	build_state = RunBuildStateScript.new()
	EventBus.entity_died.connect(_on_entity_died)
	load_persistent()


func _process(delta: float) -> void:
	if phase == GamePhase.DUNGEON or phase == GamePhase.BOSS_FIGHT:
		run_timer += delta


func start_run(run_config: Dictionary = {}) -> void:
	if build_state == null:
		build_state = RunBuildStateScript.new()
	build_state.reset()
	current_floor = 1
	current_room = 0
	run_timer = 0.0
	last_run_result = {}
	run_seed = int(run_config.get("seed", Time.get_unix_time_from_system()))
	current_run = {
		"character_id": run_config.get("character_id", "wanderer"),
		"weapon_id": run_config.get("weapon_id", "sword"),
		"difficulty": run_config.get("difficulty", "normal"),
		"inventory": [],
		"active_blessings": [],
		"active_curses": [],
		"talents": [],
		"currencies": {},
		"events": [],
		"stats": {"kills": 0},
		"archetypes": {},
		"dominant_archetype": "",
		"curse_offer_pending": false,
		"current_room_type": "combat",
	}
	set_phase(GamePhase.DUNGEON)
	EventBus.run_started.emit(current_run)
	EventBus.publish(EventBus.RUN_STARTED, current_run)


func end_run(result: Dictionary) -> void:
	if phase == GamePhase.RUN_END or phase == GamePhase.DEATH:
		return
	var enriched_result := _enrich_run_result(result)
	last_run_result = enriched_result.duplicate(true)
	_record_run_summary(enriched_result)
	save_persistent()
	set_phase(GamePhase.RUN_END)
	EventBus.run_ended.emit(enriched_result)
	EventBus.publish(EventBus.RUN_ENDED, enriched_result)


func fail_run(killer: Variant = null) -> void:
	if phase == GamePhase.RUN_END or phase == GamePhase.DEATH:
		return
	death_count += 1
	var result := _enrich_run_result({
		"result": "death",
		"floor": current_floor,
		"rooms_cleared": max(0, current_room - 1),
		"current_room": current_room,
		"run_time": run_timer,
		"killer": killer,
		"rewards": current_run.get("rewards", []),
		"blessings": current_run.get("blessings", []),
		"talent_choices": current_run.get("talent_choices", []),
		"curses": current_run.get("curses", []),
	})
	last_run_result = result.duplicate(false)
	_record_run_summary(result)
	save_persistent()
	set_phase(GamePhase.DEATH)
	EventBus.run_ended.emit(result)
	EventBus.publish(EventBus.RUN_ENDED, result)


func add_run_reward(reward_data: Dictionary) -> void:
	if current_run.is_empty():
		return
	build_state.record_item(reward_data)
	var inventory: Array = current_run.get("inventory", [])
	inventory.append(reward_data.get("id", ""))
	current_run["inventory"] = inventory

	var rewards: Array = current_run.get("rewards", [])
	rewards.append(reward_data.duplicate(true))
	current_run["rewards"] = rewards
	_record_reward_archetype(reward_data)
	_sync_build_state_to_run()


func add_run_curse(curse_data: Dictionary) -> void:
	if current_run.is_empty():
		return
	build_state.record_curse(curse_data)
	var active_curses: Array = current_run.get("active_curses", [])
	active_curses.append(curse_data.get("id", ""))
	current_run["active_curses"] = active_curses

	var curses: Array = current_run.get("curses", [])
	curses.append(curse_data.duplicate(true))
	current_run["curses"] = curses
	_sync_build_state_to_run()


func add_run_blessing(blessing_data: Dictionary) -> void:
	if current_run.is_empty():
		return
	build_state.record_blessing(blessing_data)
	var active_blessings: Array = current_run.get("active_blessings", [])
	active_blessings.append(blessing_data.get("id", ""))
	current_run["active_blessings"] = active_blessings

	var blessings: Array = current_run.get("blessings", [])
	blessings.append(blessing_data.duplicate(true))
	current_run["blessings"] = blessings
	_record_reward_archetype(blessing_data)
	_sync_build_state_to_run()


func add_run_talent(talent_data: Dictionary) -> void:
	if current_run.is_empty():
		return
	build_state.record_talent(talent_data)
	var talents: Array = current_run.get("talents", [])
	talents.append(talent_data.get("id", ""))
	current_run["talents"] = talents

	var talent_choices: Array = current_run.get("talent_choices", [])
	talent_choices.append(talent_data.duplicate(true))
	current_run["talent_choices"] = talent_choices
	_record_reward_archetype(talent_data)
	_sync_build_state_to_run()


func add_run_event(event_data: Dictionary) -> void:
	if current_run.is_empty():
		return
	var events: Array = current_run.get("events", [])
	events.append(event_data.duplicate(true))
	current_run["events"] = events


func set_curse_offer_pending(pending: bool) -> void:
	if current_run.is_empty():
		return
	current_run["curse_offer_pending"] = pending


func is_curse_offer_pending() -> bool:
	return bool(current_run.get("curse_offer_pending", false))


func set_current_room_type(room_type: StringName) -> void:
	if current_run.is_empty():
		return
	current_run["current_room_type"] = str(room_type)


func get_current_room_type() -> String:
	return str(current_run.get("current_room_type", "combat"))


func get_dominant_archetype() -> String:
	return str(current_run.get("dominant_archetype", ""))


func get_build_state_snapshot() -> Dictionary:
	if build_state == null:
		return {}
	return build_state.to_dictionary()


func get_run_kill_count() -> int:
	return int(current_run.get("stats", {}).get("kills", 0))


func set_setting(setting_id: String, value: Variant) -> void:
	var settings: Dictionary = persistent.get("settings", {})
	settings[setting_id] = value
	persistent["settings"] = settings
	save_persistent()


func get_setting(setting_id: String, default_value: Variant = null) -> Variant:
	return persistent.get("settings", {}).get(setting_id, default_value)


func load_persistent() -> bool:
	if not FileAccess.file_exists(save_path):
		persistent = _default_persistent_data()
		return false

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning("Could not open save file: %s" % save_path)
		persistent = _default_persistent_data()
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file is not valid JSON data: %s" % save_path)
		persistent = _default_persistent_data()
		return false

	var payload: Dictionary = parsed
	var loaded_persistent: Variant = payload.get("persistent", payload)
	if typeof(loaded_persistent) != TYPE_DICTIONARY:
		persistent = _default_persistent_data()
		return false

	persistent = _merge_persistent_defaults(_default_persistent_data(), loaded_persistent)
	return true


func save_persistent() -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save file: %s" % save_path)
		return false

	var payload := {
		"version": 1,
		"persistent": persistent,
	}
	file.store_string(JSON.stringify(payload, "\t"))
	return true


func reset_persistent_data(delete_file: bool = false) -> void:
	persistent = _default_persistent_data()
	if delete_file and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _record_reward_archetype(reward_data: Dictionary) -> void:
	var archetype := str(reward_data.get("archetype", ""))
	if archetype.is_empty():
		return
	var archetypes: Dictionary = current_run.get("archetypes", {})
	archetypes[archetype] = int(archetypes.get(archetype, 0)) + 1
	current_run["archetypes"] = archetypes
	current_run["dominant_archetype"] = _find_dominant_archetype(archetypes)


func _sync_build_state_to_run() -> void:
	if build_state == null:
		return
	current_run["build_state"] = build_state.to_dictionary()


func _on_entity_died(entity: Node, _killer: Variant) -> void:
	if current_run.is_empty() or entity == null:
		return
	if not entity.is_in_group("enemies") and not entity.is_in_group("bosses"):
		return
	var stats: Dictionary = current_run.get("stats", {})
	stats["kills"] = int(stats.get("kills", 0)) + 1
	current_run["stats"] = stats


func _enrich_run_result(result: Dictionary) -> Dictionary:
	var enriched := result.duplicate(true)
	enriched["kills"] = int(enriched.get("kills", get_run_kill_count()))
	var stats: Dictionary = current_run.get("stats", {}).duplicate(true)
	stats["kills"] = int(enriched["kills"])
	enriched["stats"] = stats
	return enriched


func _find_dominant_archetype(archetypes: Dictionary) -> String:
	var best_id := ""
	var best_count := -1
	for archetype: String in archetypes.keys():
		var count := int(archetypes[archetype])
		if count > best_count:
			best_id = archetype
			best_count = count
	return best_id


func set_phase(next_phase: GamePhase) -> void:
	phase = next_phase


func _record_run_summary(result: Dictionary) -> void:
	var rooms_cleared := int(result.get("rooms_cleared", 0))
	persistent["runs_completed"] = int(persistent.get("runs_completed", 0)) + 1
	persistent["best_rooms_cleared"] = maxi(int(persistent.get("best_rooms_cleared", 0)), rooms_cleared)
	if str(result.get("result", "")) == "floor_cleared":
		persistent["victories"] = int(persistent.get("victories", 0)) + 1
	persistent["last_run_summary"] = {
		"result": result.get("result", ""),
		"floor": result.get("floor", current_floor),
		"rooms_cleared": rooms_cleared,
		"current_room": result.get("current_room", current_room),
		"run_time": result.get("run_time", run_timer),
		"kills": result.get("kills", 0),
		"rewards": result.get("rewards", []),
		"blessings": result.get("blessings", []),
		"talent_choices": result.get("talent_choices", []),
		"curses": result.get("curses", []),
	}


func _default_persistent_data() -> Dictionary:
	return {
		"chronos_shards": 0,
		"existential_imprints": 0,
		"unlocked_nodes": [],
		"discovered_items": [],
		"unlocked_characters": [],
		"unlocked_weapons": [],
		"weapon_proficiency": {},
		"npc_affinity": {},
		"unlocked_achievements": [],
		"cosmetics": {},
		"settings": {},
		"runs_completed": 0,
		"victories": 0,
		"best_rooms_cleared": 0,
		"last_run_summary": {},
	}


func _merge_persistent_defaults(defaults: Dictionary, loaded: Dictionary) -> Dictionary:
	var merged := defaults.duplicate(true)
	for key: Variant in loaded.keys():
		if typeof(loaded[key]) == TYPE_DICTIONARY and typeof(merged.get(key)) == TYPE_DICTIONARY:
			merged[key] = _merge_persistent_defaults(merged[key], loaded[key])
		else:
			merged[key] = loaded[key]
	return merged
