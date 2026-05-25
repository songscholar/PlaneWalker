extends Node

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
var persistent: Dictionary = {
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
}


func _ready() -> void:
	phase = GamePhase.BOOT


func _process(delta: float) -> void:
	if phase == GamePhase.DUNGEON or phase == GamePhase.BOSS_FIGHT:
		run_timer += delta


func start_run(run_config: Dictionary = {}) -> void:
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
		"stats": {},
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
	last_run_result = result.duplicate(true)
	set_phase(GamePhase.RUN_END)
	EventBus.run_ended.emit(result)
	EventBus.publish(EventBus.RUN_ENDED, result)


func fail_run(killer: Variant = null) -> void:
	if phase == GamePhase.RUN_END or phase == GamePhase.DEATH:
		return
	death_count += 1
	var result := {
		"result": "death",
		"floor": current_floor,
		"rooms_cleared": max(0, current_room - 1),
		"current_room": current_room,
		"run_time": run_timer,
		"killer": killer,
		"rewards": current_run.get("rewards", []),
		"curses": current_run.get("curses", []),
	}
	last_run_result = result.duplicate(false)
	set_phase(GamePhase.DEATH)
	EventBus.run_ended.emit(result)
	EventBus.publish(EventBus.RUN_ENDED, result)


func add_run_reward(reward_data: Dictionary) -> void:
	if current_run.is_empty():
		return
	var inventory: Array = current_run.get("inventory", [])
	inventory.append(reward_data.get("id", ""))
	current_run["inventory"] = inventory

	var rewards: Array = current_run.get("rewards", [])
	rewards.append(reward_data.duplicate(true))
	current_run["rewards"] = rewards
	_record_reward_archetype(reward_data)


func add_run_curse(curse_data: Dictionary) -> void:
	if current_run.is_empty():
		return
	var active_curses: Array = current_run.get("active_curses", [])
	active_curses.append(curse_data.get("id", ""))
	current_run["active_curses"] = active_curses

	var curses: Array = current_run.get("curses", [])
	curses.append(curse_data.duplicate(true))
	current_run["curses"] = curses


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


func _record_reward_archetype(reward_data: Dictionary) -> void:
	var archetype := str(reward_data.get("archetype", ""))
	if archetype.is_empty():
		return
	var archetypes: Dictionary = current_run.get("archetypes", {})
	archetypes[archetype] = int(archetypes.get(archetype, 0)) + 1
	current_run["archetypes"] = archetypes
	current_run["dominant_archetype"] = _find_dominant_archetype(archetypes)


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
