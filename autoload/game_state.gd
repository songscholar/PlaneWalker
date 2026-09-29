extends Node

const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const SaveMigrationRegistryScript := preload("res://scripts/save/save_migration_registry.gd")
const SaveResultScript := preload("res://scripts/save/save_result.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")

const SAVE_GAME_VERSION := "0.4.0-dev"
const DEFAULT_PROFILE_ID := "slot_1"
const DEFAULT_SAVE_DOMAIN := "base"
const SETTING_IDS: Array[String] = [
	"locale",
	"master_volume",
	"master_muted",
	"camera_shake_enabled",
	"hit_flash_enabled",
	"reduced_motion",
]

signal setting_changed(setting_id: StringName, value: Variant)

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
var _save_service: RefCounted
var _save_service_path: String = ""


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


func set_setting(setting_id: String, value: Variant) -> bool:
	var settings: Dictionary = persistent.get("settings", {})
	settings[setting_id] = value
	persistent["settings"] = settings
	if not SETTING_IDS.has(setting_id):
		return false
	var service_result = _ensure_save_service()
	if not service_result.ok:
		return false
	var save_result = _save_service.save_settings(_settings_payload(settings))
	if not save_result.ok:
		return false
	setting_changed.emit(StringName(setting_id), value)
	return true


func get_setting(setting_id: String, default_value: Variant = null) -> Variant:
	return persistent.get("settings", {}).get(setting_id, default_value)


func load_persistent() -> bool:
	var service_result = _ensure_save_service()
	if not service_result.ok:
		return false
	var profile_result = _save_service.load_profile(DEFAULT_PROFILE_ID, DEFAULT_SAVE_DOMAIN)
	var settings_result = _save_service.load_settings()

	if profile_result.ok:
		if not settings_result.ok and settings_result.code != &"NOT_FOUND":
			return false
		persistent = _compose_persistent(profile_result.payload, settings_result)
		return true

	if profile_result.code != &"NOT_FOUND":
		return false
	if FileAccess.file_exists(save_path):
		return _import_legacy_persistent()
	if settings_result.ok:
		persistent = _compose_persistent({}, settings_result)
		return true
	if settings_result.code == &"NOT_FOUND":
		persistent = _default_persistent_data()
	return false


func save_persistent() -> bool:
	var service_result = _ensure_save_service()
	if not service_result.ok:
		return false
	var snapshot := persistent.duplicate(true)
	var settings_value: Variant = snapshot.get("settings", {})
	var settings := settings_value as Dictionary if settings_value is Dictionary else {}
	snapshot.erase("settings")
	var settings_result = _save_service.save_settings(_settings_payload(settings))
	if not settings_result.ok:
		return false
	var profile_result = _save_service.save_profile(
		DEFAULT_PROFILE_ID,
		DEFAULT_SAVE_DOMAIN,
		snapshot
	)
	return profile_result.ok


func reset_persistent_data(delete_file: bool = false) -> void:
	persistent = _default_persistent_data()
	if not delete_file:
		return
	var service_result = _ensure_save_service()
	if service_result.ok:
		_save_service.reset_profile(DEFAULT_PROFILE_ID, DEFAULT_SAVE_DOMAIN)
		var default_settings := _settings_payload(persistent["settings"])
		for _generation: int in range(3):
			_save_service.save_settings(default_settings)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _ensure_save_service():
	if _save_service != null and _save_service_path == save_path:
		return SaveResultScript.success()
	var service = SaveServiceScript.new()
	var configured = service.configure(
		_save_service_root_path(),
		SAVE_GAME_VERSION,
		_base_content_snapshot()
	)
	if not configured.ok:
		return configured
	_save_service = service
	_save_service_path = save_path
	return configured


func _import_legacy_persistent() -> bool:
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var legacy_bytes := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return false
	var parsed: Variant = JSON.parse_string(legacy_bytes)
	if not parsed is Dictionary:
		return false

	var registry = SaveMigrationRegistryScript.new()
	var migration = registry.migrate(parsed, SaveEnvelopeScript.SCHEMA_VERSION, {
		"profile_id": DEFAULT_PROFILE_ID,
		"save_domain": DEFAULT_SAVE_DOMAIN,
	})
	if not migration.ok:
		return false
	var migration_document: Dictionary = migration.payload
	var profile_value: Variant = migration_document.get("payload", {})
	var settings_value: Variant = migration.metadata.get("settings_payload", {})
	if not profile_value is Dictionary or not settings_value is Dictionary:
		return false
	var profile_payload: Dictionary = profile_value
	var settings_payload := _settings_payload(settings_value)

	var settings_save = _save_service.save_settings(settings_payload)
	if not settings_save.ok:
		return false
	var profile_save = _save_service.save_profile(
		DEFAULT_PROFILE_ID,
		DEFAULT_SAVE_DOMAIN,
		profile_payload
	)
	if not profile_save.ok:
		return false
	persistent = _compose_persistent_values(profile_payload, settings_payload)
	return true


func _compose_persistent(profile_payload: Dictionary, settings_result) -> Dictionary:
	var settings_payload := _default_settings_payload()
	if settings_result.ok:
		settings_payload = _settings_payload(settings_result.payload)
	return _compose_persistent_values(profile_payload, settings_payload)


func _compose_persistent_values(profile_payload: Dictionary, settings_payload: Dictionary) -> Dictionary:
	var merged := _merge_persistent_defaults(_default_persistent_data(), profile_payload)
	merged["settings"] = _merge_persistent_defaults(_default_settings_payload(), settings_payload)
	return merged


func _settings_payload(settings: Dictionary) -> Dictionary:
	var normalized := _default_settings_payload()
	for setting_id: String in SETTING_IDS:
		if settings.has(setting_id):
			normalized[setting_id] = settings[setting_id]
	return normalized


func _default_settings_payload() -> Dictionary:
	return {
		"locale": "zh_CN",
		"master_volume": 0.85,
		"master_muted": false,
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": false,
	}


func _base_content_snapshot() -> Dictionary:
	var packs: Array = [{
		"pack_id": "base",
		"pack_version": SAVE_GAME_VERSION,
		"schema_version": 1,
		"fingerprint_sha256": "1".repeat(64),
	}]
	return {
		"aggregate_sha256": SaveEnvelopeScript.content_snapshot_digest(packs),
		"packs": packs,
	}


func _save_service_root_path() -> String:
	return save_path.get_base_dir().path_join("plane_walker").path_join("save")


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
		"settings": _default_settings_payload(),
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
