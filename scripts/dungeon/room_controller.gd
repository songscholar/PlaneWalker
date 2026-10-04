class_name RoomController
extends Node2D

signal authored_runtime_failed(context: Dictionary)

const CHARACTER_BOSS_EXPOSURE_REPLAY_SCHEMA_VERSION := 1
const CHARACTER_BOSS_EXPOSURE_REPLAY_FIELDS := ["schema_version", "participants"]
const CHARACTER_BOSS_EXPOSURE_PARTICIPANT_FIELDS := [
	"hostile_source_id",
	"hostile_identity",
	"snapshot",
]

@export var room_id: StringName = &"combat_room_01"
@export var enemy_scenes: Array[PackedScene] = []
@export var boss_scene: PackedScene
@export var spawn_warning_scene: PackedScene
@export var reward_marker_path: NodePath
@export var run_director_path: NodePath
@export var rooms_per_floor: int = 5
@export var spawn_warning_duration: float = 0.45
@export var curse_offer_rooms: Array[int] = [4]
@export var elite_rooms: Array[int] = [3]
@export var event_rooms: Array[int] = [2]
@export var auto_start: bool = true

@onready var spawn_points: Node2D = $SpawnPoints
@onready var boss_spawn_point: Marker2D = $BossSpawnPoint
@onready var enemies_root: Node2D = $Enemies
@onready var reward_marker: Node = get_node_or_null(reward_marker_path)
@onready var _encounter_runner: Node = get_node_or_null("EncounterRunner")
@onready var _player_health: Node = get_node_or_null("Player/HealthComponent")

var _room_runtime: Node
var _encounter_catalog: RefCounted
var _authored_runtime_enabled: bool = false
var _authored_runtime_failure: Dictionary = {}
var _current_room_definition: Dictionary = {}
var _hostile_identity_scope: Dictionary = {}
var _hostile_spawn_ordinals: Dictionary = {}
var _hostile_threat_registry: RefCounted
var _character_boss_exposure_replay_authority: RefCounted
var _cleared: bool = false
var _alive_enemies: int:
	get:
		if _encounter_runner != null and _encounter_runner.has_method("alive_count"):
			return int(_encounter_runner.call("alive_count"))
		return 0


func _ready() -> void:
	if _encounter_runner != null:
		_encounter_runner.call("configure", enemies_root)
	if reward_marker != null and reward_marker is Label:
		reward_marker.text = tr("UI_REWARD_MARKER")
	if _player_health != null and _player_health.has_signal("died") and not _player_health.died.is_connected(_on_player_died):
		_player_health.died.connect(_on_player_died)
	if auto_start:
		call_deferred("begin_run")


func encounter_runner() -> Node:
	return _encounter_runner


func configure_hostile_threat_authority(
	hostile_identity_scope_value: Dictionary,
	registry: RefCounted
) -> bool:
	if (
		str(hostile_identity_scope_value.get("run_id", "")).strip_edges().is_empty()
		or registry == null
		or not registry.has_method("register_fact")
		or not registry.has_method("retire")
		or not registry.has_method("retire_source")
		or not registry.has_method("clear")
	):
		return false
	retire_hostile_threats()
	_hostile_identity_scope = hostile_identity_scope_value.duplicate(true)
	_hostile_threat_registry = registry
	return true


func hostile_threat_registry() -> RefCounted:
	return _hostile_threat_registry


func configure_character_boss_exposure_replay_authority(authority: RefCounted) -> bool:
	if authority == null:
		return false
	if (
		_character_boss_exposure_replay_authority != null
		and _character_boss_exposure_replay_authority != authority
	):
		return false
	_character_boss_exposure_replay_authority = authority
	var participants := _character_boss_exposure_participants()
	if not bool(participants.get("ok", false)):
		return false
	for participant_value: Variant in (participants.get("participants", {}) as Dictionary).values():
		var participant := participant_value as Node
		if not bool(participant.call(
			"configure_character_boss_exposure_replay_authority",
			authority
		)):
			return false
	return true


func character_boss_exposure_runtime_frame() -> int:
	return _hostile_runtime_frame()


func capture_character_boss_exposure_replay_state() -> Dictionary:
	if _character_boss_exposure_replay_authority == null:
		return {}
	var resolved := _character_boss_exposure_participants()
	if not bool(resolved.get("ok", false)):
		return {}
	var participants_by_id := resolved.get("participants", {}) as Dictionary
	var source_ids: Array[String] = []
	for source_value: Variant in participants_by_id.keys():
		source_ids.append(str(source_value))
	source_ids.sort()
	var snapshots: Array[Dictionary] = []
	for source_value: String in source_ids:
		var participant := participants_by_id.get(source_value) as Node
		var snapshot_value: Variant = participant.call("character_boss_exposure_snapshot")
		var hostile_identity_value: Variant = participant.call("hostile_identity_snapshot")
		if (
			not snapshot_value is Dictionary
			or (snapshot_value as Dictionary).is_empty()
			or not hostile_identity_value is Dictionary
			or (hostile_identity_value as Dictionary).is_empty()
		):
			return {}
		snapshots.append({
			"hostile_source_id": source_value,
			"hostile_identity": (hostile_identity_value as Dictionary).duplicate(true),
			"snapshot": (snapshot_value as Dictionary).duplicate(true),
		})
	return {
		"schema_version": CHARACTER_BOSS_EXPOSURE_REPLAY_SCHEMA_VERSION,
		"participants": snapshots,
	}


func can_restore_character_boss_exposure_replay_state(
	value: Dictionary,
	authority: RefCounted
) -> bool:
	return not _validated_character_boss_exposure_replay_state(value, authority).is_empty()


func restore_character_boss_exposure_replay_state(
	value: Dictionary,
	authority: RefCounted
) -> bool:
	var normalized := _validated_character_boss_exposure_replay_state(value, authority)
	if normalized.is_empty():
		return false
	var before := capture_character_boss_exposure_replay_state()
	if before.is_empty():
		return false
	var resolved := _character_boss_exposure_participants()
	if not bool(resolved.get("ok", false)):
		return false
	var participants_by_id := resolved.get("participants", {}) as Dictionary
	for entry_value: Variant in normalized["participants"] as Array:
		var entry := entry_value as Dictionary
		var source_id := str(entry["hostile_source_id"])
		var participant := participants_by_id.get(source_id) as Node
		if not bool(participant.call(
			"restore_character_boss_exposure_replay_snapshot",
			(entry["snapshot"] as Dictionary).duplicate(true),
			authority
		)):
			_restore_character_boss_exposure_replay_state_unchecked(before, authority)
			return false
	if capture_character_boss_exposure_replay_state() == normalized:
		return true
	_restore_character_boss_exposure_replay_state_unchecked(before, authority)
	return false


func configure_authored_runtime(
	room_runtime: Node,
	encounter_catalog: RefCounted,
	hostile_identity_scope_value: Dictionary = {}
) -> bool:
	_disconnect_room_runtime()
	_authored_runtime_enabled = true
	_authored_runtime_failure.clear()
	_current_room_definition.clear()
	_hostile_spawn_ordinals.clear()
	if not hostile_identity_scope_value.is_empty():
		_hostile_identity_scope = hostile_identity_scope_value.duplicate(true)
	if room_runtime == null or encounter_catalog == null or _encounter_runner == null:
		_record_runtime_failure({
			"result": "runtime_error",
			"runtime_error_code": "AUTHORED_RUNTIME_CONFIGURATION_FAILED",
			"runtime_error_context": {
				"has_runtime": room_runtime != null,
				"has_catalog": encounter_catalog != null,
				"has_runner": _encounter_runner != null,
			},
		})
		return false
	_room_runtime = room_runtime
	_encounter_catalog = encounter_catalog
	if not _room_runtime.spawn_warning_requested.is_connected(_on_authored_spawn_warning):
		_room_runtime.spawn_warning_requested.connect(_on_authored_spawn_warning)
	if not _room_runtime.spawn_requested.is_connected(_on_authored_spawn_requested):
		_room_runtime.spawn_requested.connect(_on_authored_spawn_requested)
	if not _room_runtime.room_started.is_connected(_on_runtime_room_started):
		_room_runtime.room_started.connect(_on_runtime_room_started)
	if not _room_runtime.room_cleared.is_connected(_on_runtime_room_cleared):
		_room_runtime.room_cleared.connect(_on_runtime_room_cleared)
	if not _room_runtime.runtime_failed.is_connected(_on_runtime_failed):
		_room_runtime.runtime_failed.connect(_on_runtime_failed)
	return true


func configure_checkpoint_runtime(room_runtime: Node, encounter_catalog: RefCounted) -> bool:
	if not configure_authored_runtime(room_runtime, encounter_catalog):
		return false
	var retained: Dictionary = room_runtime.snapshot()
	_current_room_definition = retained.room_definition.duplicate(true)
	_cleared = bool(retained.room_terminal) and retained.failure.is_empty()
	if reward_marker != null:
		reward_marker.visible = _cleared
	return true


func begin_run() -> Variant:
	return begin_current_room()


func start_room() -> Variant:
	return begin_current_room()


func begin_current_room() -> Variant:
	if _room_runtime == null or not is_instance_valid(_room_runtime):
		return null
	return _room_runtime.call("begin_current_room")


func authored_runtime_failure() -> Dictionary:
	return _authored_runtime_failure.duplicate(true)


func _disconnect_room_runtime() -> void:
	if _room_runtime == null or not is_instance_valid(_room_runtime):
		_room_runtime = null
		return
	if _room_runtime.spawn_warning_requested.is_connected(_on_authored_spawn_warning):
		_room_runtime.spawn_warning_requested.disconnect(_on_authored_spawn_warning)
	if _room_runtime.spawn_requested.is_connected(_on_authored_spawn_requested):
		_room_runtime.spawn_requested.disconnect(_on_authored_spawn_requested)
	if _room_runtime.room_started.is_connected(_on_runtime_room_started):
		_room_runtime.room_started.disconnect(_on_runtime_room_started)
	if _room_runtime.room_cleared.is_connected(_on_runtime_room_cleared):
		_room_runtime.room_cleared.disconnect(_on_runtime_room_cleared)
	if _room_runtime.runtime_failed.is_connected(_on_runtime_failed):
		_room_runtime.runtime_failed.disconnect(_on_runtime_failed)
	_room_runtime = null


func _on_runtime_room_started(_active_room_id: StringName, _revision: int) -> void:
	_cleared = false
	_authored_runtime_failure.clear()
	_hostile_spawn_ordinals.clear()
	if reward_marker != null:
		reward_marker.visible = false
	_clear_enemy_nodes()
	var runtime_snapshot: Dictionary = _room_runtime.call("snapshot")
	_current_room_definition = runtime_snapshot.get("room_definition", {}).duplicate(true)
	if _encounter_runner != null and _encounter_runner.has_method("set_timing_override"):
		_encounter_runner.call(
			"set_timing_override",
			0.0 if spawn_warning_duration <= 0.0 else -1.0
		)


func _on_runtime_room_cleared(_active_room_id: StringName, _revision: int) -> void:
	if _cleared:
		return
	_cleared = true
	retire_hostile_threats()
	if reward_marker != null:
		reward_marker.visible = true


func _on_runtime_failed(context: Dictionary) -> void:
	_record_runtime_failure(context)


func _on_authored_spawn_warning(spawn_definition: Dictionary, duration: float) -> void:
	var marker := _spawn_marker_for(spawn_definition)
	if marker == null:
		return
	var radius := 44.0 if str(spawn_definition.get("enemy_id", "")) == "chrono_warden" else 24.0
	var offset: Dictionary = spawn_definition.get("spawn_offset", {})
	_show_spawn_warning(marker.global_position + Vector2(float(offset.get("x", 0.0)), float(offset.get("y", 0.0))), radius, duration)


func _on_authored_spawn_requested(spawn_definition: Dictionary) -> void:
	if not _authored_runtime_enabled or _encounter_catalog == null or _room_runtime == null:
		_reject_authored_spawn(spawn_definition, &"AUTHORED_RUNTIME_UNAVAILABLE")
		return
	if not _encounter_runner.native_launch_snapshot().is_empty():
		if not _encounter_runner.spawn_native_actor(spawn_definition):
			_reject_authored_spawn(spawn_definition, &"NATIVE_SPAWN_REGISTRATION_REJECTED")
		return
	var enemy_id := str(spawn_definition.get("enemy_id", ""))
	var enemy_definition: Dictionary = _encounter_catalog.call("enemy_definition", enemy_id)
	var scene_path := str(enemy_definition.get("scene", ""))
	var marker := _spawn_marker_for(spawn_definition)
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_reject_authored_spawn(spawn_definition, &"ENEMY_SCENE_UNAVAILABLE")
		return
	var scene_resource := ResourceLoader.load(scene_path)
	if not scene_resource is PackedScene:
		_reject_authored_spawn(spawn_definition, &"ENEMY_SCENE_UNAVAILABLE")
		return
	if marker == null:
		_reject_authored_spawn(spawn_definition, &"SPAWN_SLOT_UNAVAILABLE")
		return
	var enemy := (scene_resource as PackedScene).instantiate()
	if not enemy is Node2D:
		enemy.free()
		_reject_authored_spawn(spawn_definition, &"ENEMY_ROOT_NOT_NODE_2D")
		return
	var mechanism_ids: Array = spawn_definition.get("mechanism_ids", []).duplicate()
	enemy.set_meta("encounter_enemy_id", enemy_id)
	enemy.set_meta("encounter_spawn_id", str(spawn_definition.get("id", "")))
	enemy.set_meta("encounter_mechanism_ids", mechanism_ids)
	if not _configure_spawned_hostile_identity(enemy, spawn_definition):
		enemy.free()
		_reject_authored_spawn(spawn_definition, &"HOSTILE_IDENTITY_REJECTED")
		return
	enemies_root.add_child(enemy)
	(enemy as Node2D).global_position = marker.global_position
	if mechanism_ids.has("overload_pulse") and enemy.has_method("apply_elite_modifier"):
		enemy.call("apply_elite_modifier")
	if not bool(_room_runtime.call("register_spawned", enemy, spawn_definition)):
		enemy.queue_free()
		_reject_authored_spawn(spawn_definition, &"SPAWN_REGISTRATION_REJECTED")
		return
	_bind_enemy_lifecycle(enemy)
	EventBus.enemy_spawned.emit(enemy, {
		"boss": enemy.is_in_group("bosses"),
		"summoned": false,
	})


func _bind_enemy_lifecycle(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var health := enemy.get_node_or_null("HealthComponent")
	if health != null and health.has_signal("died"):
		var death_callback := _on_registered_enemy_died.bind(enemy)
		if not health.died.is_connected(death_callback):
			health.died.connect(death_callback)
	if enemy.has_signal("enemy_summoned"):
		var summon_callback := Callable(self, "_on_enemy_summoned")
		if not enemy.is_connected("enemy_summoned", summon_callback):
			enemy.connect("enemy_summoned", summon_callback)


func _on_enemy_summoned(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if _room_runtime == null or not is_instance_valid(_room_runtime):
		enemy.queue_free()
		return
	if not _configure_spawned_hostile_identity(enemy, {"id": "summoned", "spawn_slot_id": "summoned"}):
		enemy.queue_free()
		return
	if not bool(_room_runtime.call("register_spawned", enemy, {"summoned": true})):
		enemy.queue_free()
		return
	_bind_enemy_lifecycle(enemy)


func _on_registered_enemy_died(_killer: Variant, enemy: Node) -> void:
	if _room_runtime != null and is_instance_valid(_room_runtime):
		_room_runtime.call("report_entity_died", enemy)


func _reject_authored_spawn(spawn_definition: Dictionary, reason: StringName) -> void:
	if _room_runtime != null and is_instance_valid(_room_runtime):
		_room_runtime.call("reject_spawn", spawn_definition, reason)


func _spawn_marker_for(spawn_definition: Dictionary) -> Node2D:
	if _encounter_catalog == null:
		return null
	var slot: Dictionary = _encounter_catalog.call(
		"spawn_slot",
		str(spawn_definition.get("spawn_slot_id", ""))
	)
	var node_path := NodePath(str(slot.get("node_path", "")))
	var native_scene: Node2D = _encounter_runner.native_launch_scene()
	if native_scene != null:
		return native_scene.get_node_or_null(node_path) as Node2D
	return get_node_or_null(node_path) as Node2D


static func hostile_source_id_for_spawn(
	scope: Dictionary,
	active_room_id: StringName,
	encounter_id: StringName,
	spawn_definition: Dictionary,
	spawn_ordinal: int
) -> StringName:
	var run_id := str(scope.get("run_id", "")).strip_edges()
	var room_value := str(active_room_id).strip_edges()
	var encounter_value := str(encounter_id).strip_edges()
	var spawn_id := str(spawn_definition.get("id", "")).strip_edges()
	var slot_id := str(spawn_definition.get("spawn_slot_id", "")).strip_edges()
	if (
		run_id.is_empty()
		or room_value.is_empty()
		or encounter_value.is_empty()
		or spawn_id.is_empty()
		or slot_id.is_empty()
		or spawn_ordinal < 0
	):
		return &""
	var material := "%s|%s|%s|%s|%s|%d" % [
		run_id,
		room_value,
		encounter_value,
		spawn_id,
		slot_id,
		spawn_ordinal,
	]
	return StringName("hostile:%s" % material.sha256_text().substr(0, 40))


func _configure_spawned_hostile_identity(enemy: Node, spawn_definition: Dictionary) -> bool:
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_method("configure_hostile_identity"):
		return false
	if enemy.has_method("hostile_identity_snapshot"):
		var existing_value: Variant = enemy.call("hostile_identity_snapshot")
		if (
			existing_value is Dictionary
			and bool((existing_value as Dictionary).get("active", false))
			and StringName(str((existing_value as Dictionary).get("hostile_source_id", ""))) != &""
		):
			if not _configure_spawned_hostile_threat_authority(enemy):
				return false
			if not _configure_character_boss_exposure_participant(enemy):
				return false
			_configure_hostile_run_metadata(enemy)
			return true
	var runtime_snapshot: Dictionary = (
		_room_runtime.call("snapshot")
		if _room_runtime != null and _room_runtime.has_method("snapshot")
		else {}
	)
	var scope := _hostile_identity_scope.duplicate(true)
	if str(scope.get("run_id", "")).strip_edges().is_empty():
		scope["run_id"] = StringName("seed-%d" % int(runtime_snapshot.get("run_seed", 0)))
	var room_value := StringName(str(runtime_snapshot.get("room_id", room_id)))
	var encounter_value := StringName(str(_current_room_definition.get("encounter_id", "encounter")))
	var ordinal := _next_hostile_spawn_ordinal(spawn_definition)
	var source_id := hostile_source_id_for_spawn(
		scope,
		room_value,
		encounter_value,
		spawn_definition,
		ordinal
	)
	if source_id == &"" or not bool(enemy.call("configure_hostile_identity", source_id, 1)):
		return false
	if not _configure_spawned_hostile_threat_authority(enemy):
		return false
	if not _configure_character_boss_exposure_participant(enemy):
		return false
	enemy.set_meta("hostile_source_id", source_id)
	_configure_hostile_run_metadata(enemy, scope)
	return true


func _configure_spawned_hostile_threat_authority(enemy: Node) -> bool:
	if _hostile_threat_registry == null:
		return true
	if not enemy.has_method("configure_hostile_threat_authority"):
		return false
	return bool(enemy.call(
		"configure_hostile_threat_authority",
		_hostile_threat_registry,
		Callable(self, "_hostile_runtime_frame")
	))


func _configure_character_boss_exposure_participant(enemy: Node) -> bool:
	if not enemy.has_method("character_boss_exposure_snapshot"):
		return true
	if (
		_character_boss_exposure_replay_authority == null
		or not enemy.has_method("configure_character_boss_exposure_replay_authority")
		or not enemy.has_method("can_restore_character_boss_exposure_replay_snapshot")
		or not enemy.has_method("restore_character_boss_exposure_replay_snapshot")
	):
		return false
	return bool(enemy.call(
		"configure_character_boss_exposure_replay_authority",
		_character_boss_exposure_replay_authority
	))


func _character_boss_exposure_participants() -> Dictionary:
	var participants: Dictionary = {}
	if enemies_root == null:
		return {"ok": true, "participants": participants}
	for enemy: Node in enemies_root.get_children():
		if not enemy.has_method("character_boss_exposure_snapshot"):
			continue
		if (
			not enemy.has_method("hostile_identity_snapshot")
			or not enemy.has_method("restore_hostile_identity_snapshot")
			or not enemy.has_method("configure_character_boss_exposure_replay_authority")
			or not enemy.has_method("can_restore_character_boss_exposure_replay_snapshot")
			or not enemy.has_method("restore_character_boss_exposure_replay_snapshot")
		):
			return {"ok": false, "participants": {}}
		var identity_value: Variant = enemy.call("hostile_identity_snapshot")
		if not identity_value is Dictionary:
			return {"ok": false, "participants": {}}
		var identity := identity_value as Dictionary
		var source_id := str(identity.get("hostile_source_id", "")).strip_edges()
		if source_id.is_empty() or not bool(identity.get("active", false)) or participants.has(source_id):
			return {"ok": false, "participants": {}}
		participants[source_id] = enemy
	return {"ok": true, "participants": participants}


func _validated_character_boss_exposure_replay_state(
	value: Dictionary,
	authority: RefCounted
) -> Dictionary:
	if (
		authority == null
		or authority != _character_boss_exposure_replay_authority
		or not _dictionary_has_exact_fields(value, CHARACTER_BOSS_EXPOSURE_REPLAY_FIELDS)
		or typeof(value.get("schema_version")) != TYPE_INT
		or int(value["schema_version"]) != CHARACTER_BOSS_EXPOSURE_REPLAY_SCHEMA_VERSION
		or not value.get("participants") is Array
	):
		return {}
	var resolved := _character_boss_exposure_participants()
	if not bool(resolved.get("ok", false)):
		return {}
	var participants_by_id := resolved.get("participants", {}) as Dictionary
	var entries := value["participants"] as Array
	if entries.size() != participants_by_id.size():
		return {}
	var normalized_entries: Array[Dictionary] = []
	var previous_source_id := ""
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			return {}
		var entry := entry_value as Dictionary
		if (
			not _dictionary_has_exact_fields(entry, CHARACTER_BOSS_EXPOSURE_PARTICIPANT_FIELDS)
			or typeof(entry.get("hostile_source_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
			or not entry.get("hostile_identity") is Dictionary
			or not entry.get("snapshot") is Dictionary
		):
			return {}
		var source_id := str(entry["hostile_source_id"]).strip_edges()
		if (
			source_id.is_empty()
			or (not previous_source_id.is_empty() and source_id <= previous_source_id)
			or not participants_by_id.has(source_id)
		):
			return {}
		var participant := participants_by_id.get(source_id) as Node
		var hostile_identity := entry["hostile_identity"] as Dictionary
		if (
			hostile_identity.size() != 3
			or typeof(hostile_identity.get("hostile_source_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
			or str(hostile_identity.get("hostile_source_id", "")) != source_id
			or typeof(hostile_identity.get("next_generation_floor")) != TYPE_INT
			or int(hostile_identity.get("next_generation_floor", 0)) <= 0
			or typeof(hostile_identity.get("active")) != TYPE_BOOL
			or not bool(hostile_identity.get("active", false))
		):
			return {}
		var current_identity := participant.call("hostile_identity_snapshot") as Dictionary
		if (
			str(current_identity.get("hostile_source_id", "")) != source_id
			or not bool(current_identity.get("active", false))
		):
			return {}
		var exposure_snapshot := (entry["snapshot"] as Dictionary).duplicate(true)
		var exposure_identity := exposure_snapshot.get("identity", {}) as Dictionary
		if (
			str(exposure_identity.get("hostile_source_id", "")) != source_id
			or int(exposure_identity.get("hostile_next_generation_floor", 0))
			!= int(hostile_identity["next_generation_floor"])
		):
			return {}
		if not bool(participant.call(
			"can_restore_character_boss_exposure_replay_snapshot",
			exposure_snapshot,
			authority
		)):
			return {}
		previous_source_id = source_id
		normalized_entries.append({
			"hostile_source_id": source_id,
			"hostile_identity": hostile_identity.duplicate(true),
			"snapshot": exposure_snapshot,
		})
	return {
		"schema_version": CHARACTER_BOSS_EXPOSURE_REPLAY_SCHEMA_VERSION,
		"participants": normalized_entries,
	}


func _restore_character_boss_exposure_replay_state_unchecked(
	value: Dictionary,
	authority: RefCounted
) -> bool:
	var resolved := _character_boss_exposure_participants()
	if not bool(resolved.get("ok", false)):
		return false
	var participants_by_id := resolved.get("participants", {}) as Dictionary
	var restored := true
	for entry_value: Variant in value.get("participants", []) as Array:
		if not entry_value is Dictionary:
			restored = false
			continue
		var entry := entry_value as Dictionary
		var participant := participants_by_id.get(str(entry.get("hostile_source_id", ""))) as Node
		if (
			participant == null
			or not bool(participant.call(
				"restore_character_boss_exposure_replay_snapshot",
				(entry.get("snapshot", {}) as Dictionary).duplicate(true),
				authority
			))
		):
			restored = false
	return restored


func _dictionary_has_exact_fields(value: Dictionary, expected_fields: Array) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field_value: Variant in expected_fields:
		if not value.has(str(field_value)):
			return false
	return true


func _hostile_runtime_frame() -> int:
	if _player_health != null and is_instance_valid(_player_health):
		var player := _player_health.get_parent()
		if player != null:
			var value: Variant = player.get("_runtime_frame")
			if typeof(value) == TYPE_INT and int(value) >= 0:
				return int(value)
	return maxi(0, int(Engine.get_physics_frames()))


func _configure_hostile_run_metadata(enemy: Node, scope: Dictionary = {}) -> void:
	var source_scope := scope if not scope.is_empty() else _hostile_identity_scope
	var run_id := str(source_scope.get("run_id", "")).strip_edges()
	if not run_id.is_empty():
		enemy.set_meta("run_id", StringName(run_id))
	var runtime_snapshot: Dictionary = (
		_room_runtime.call("snapshot")
		if _room_runtime != null and _room_runtime.has_method("snapshot")
		else {}
	)
	var active_room_id := str(runtime_snapshot.get("room_id", room_id)).strip_edges()
	var encounter_id := str(_current_room_definition.get("encounter_id", "encounter")).strip_edges()
	if not active_room_id.is_empty():
		enemy.set_meta("room_id", StringName(active_room_id))
	if not encounter_id.is_empty():
		enemy.set_meta("encounter_id", StringName(encounter_id))


func _next_hostile_spawn_ordinal(spawn_definition: Dictionary) -> int:
	var key := "%s|%s" % [
		str(spawn_definition.get("id", "summoned")),
		str(spawn_definition.get("spawn_slot_id", "summoned")),
	]
	var ordinal := int(_hostile_spawn_ordinals.get(key, 0))
	_hostile_spawn_ordinals[key] = ordinal + 1
	return ordinal


func _show_spawn_warning(spawn_position: Vector2, radius: float, duration: float) -> void:
	if spawn_warning_scene == null:
		return
	var warning := spawn_warning_scene.instantiate()
	warning.radius = radius
	warning.duration = maxf(0.0, duration)
	add_child(warning)
	warning.global_position = spawn_position


func _on_player_died(killer: Variant) -> void:
	if _room_runtime != null and is_instance_valid(_room_runtime):
		_room_runtime.call("report_player_died", killer)
	_clear_enemy_nodes()
	if reward_marker != null:
		reward_marker.visible = false


func _record_runtime_failure(context: Dictionary) -> void:
	if not _authored_runtime_failure.is_empty():
		return
	_authored_runtime_failure = context.duplicate(true)
	_clear_enemy_nodes()
	if reward_marker != null:
		reward_marker.visible = false
	authored_runtime_failed.emit(_authored_runtime_failure.duplicate(true))


func _clear_enemy_nodes() -> void:
	if enemies_root == null:
		if _hostile_threat_registry != null:
			_hostile_threat_registry.call("clear")
		return
	for enemy: Node in enemies_root.get_children():
		if enemy.has_method("cancel_active_attack"):
			enemy.call("cancel_active_attack")
		if enemy.has_method("retire_hostile_identity"):
			enemy.call("retire_hostile_identity", &"room_teardown")
		if not enemy.is_queued_for_deletion():
			enemy.queue_free()
	if _hostile_threat_registry != null:
		_hostile_threat_registry.call("clear")


func retire_hostile_threats() -> void:
	_clear_enemy_nodes()
