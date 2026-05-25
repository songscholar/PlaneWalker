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


func set_phase(next_phase: GamePhase) -> void:
	phase = next_phase
