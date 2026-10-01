class_name BossTimeCrack
extends Area2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const HostileTelegraphFactScript := preload("res://scripts/combat/hostile_telegraph_fact.gd")

@export var arm_delay: float = 1.15
@export var radius: float = 54.0
@export var damage: float = 18.0

var _time_stopped: bool = false
var _timer: float = 0.0
var _exploded: bool = false
var _visual: Polygon2D
var _time_stop_token_sequence: int = 0
var _time_stop_sources: Dictionary = {}
var _run_id: StringName = &""
var hostile_source_id: StringName = &""
var attack_generation: int = 0
var _attack_owner: Node
var _attack_identity_locked: bool = false
var _hostile_threat_registry: RefCounted
var _hostile_runtime_frame_provider: Callable
var _registered_threat_fact: Dictionary = {}


func _ready() -> void:
	add_to_group("time_stoppable")
	add_to_group("boss_hazards")
	monitoring = false
	_timer = arm_delay
	_build_shape()


func _process(delta: float) -> void:
	if _exploded or _time_stopped:
		return
	_timer -= delta
	if _visual != null:
		_visual.modulate.a = clampf(1.0 - (_timer / maxf(arm_delay, 0.001)), 0.25, 1.0)
	if _timer <= 0.0:
		_explode()


func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_time_stop_token_sequence += 1
	var source_id := StringName("legacy_time_stop_%d_%d" % [get_instance_id(), _time_stop_token_sequence])
	apply_time_stop_source(source_id, duration)
	get_tree().create_timer(duration, false).timeout.connect(clear_time_stop_source.bind(source_id))


func apply_time_stop_source(source_id: StringName, duration: float) -> void:
	if source_id == &"" or duration <= 0.0:
		return
	_time_stop_sources[source_id] = true
	_recompute_time_stop()


func clear_time_stop_source(source_id: StringName) -> void:
	_time_stop_sources.erase(source_id)
	_recompute_time_stop()


func _recompute_time_stop() -> void:
	_time_stopped = not _time_stop_sources.is_empty()


func is_time_stopped() -> bool:
	return _time_stopped


func has_exploded() -> bool:
	return _exploded


func remaining_time() -> float:
	return _timer


func _build_shape() -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape
	add_child(collision)

	_visual = Polygon2D.new()
	var points := PackedVector2Array()
	for index: int in range(12):
		var point_radius := radius if index % 2 == 0 else radius * 0.72
		points.append(Vector2.RIGHT.rotated(TAU * float(index) / 12.0) * point_radius)
	_visual.polygon = points
	_visual.color = Color(0.35, 0.75, 1.0, 0.35)
	add_child(_visual)


func _explode() -> void:
	if _exploded or not _attack_identity_locked:
		return
	_exploded = true
	monitoring = true
	if _visual != null:
		_visual.color = Color(0.7, 0.95, 1.0, 0.95)
	var players: Array[Node] = []
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player is Node2D:
			players.append(player)
	players.sort_custom(func(left: Node, right: Node) -> bool:
		return str(_target_identity(left, "player")) < str(_target_identity(right, "player"))
	)
	var hit_index := 0
	for player: Node in players:
		if (player as Node2D).global_position.distance_to(global_position) <= radius:
			var health := player.get_node_or_null("HealthComponent")
			if health != null:
				var damage_info := DamageInfoScript.from_plan({
					"run_id": _run_id,
					"target_id": _target_identity(player, "player"),
					"hostile_source_id": hostile_source_id,
					"attack_generation": attack_generation,
					"hit_index": hit_index,
					"action_token": attack_generation,
					"amount": damage,
					"damage_type": DamageInfoScript.DamageType.TIME,
					"source": self,
					"attacker": _attack_owner if _attack_owner != null and is_instance_valid(_attack_owner) else self,
					"can_crit": true,
					"crit_chance": 0.0,
					"crit_multiplier": 1.5,
					"knockback": Vector2.ZERO,
					"tags": ["boss:time_crack", "time:hazard"],
					"source_generation": attack_generation,
					"control_effect": {},
				})
				if damage_info != null:
					health.take_damage(damage_info)
					hit_index += 1
	_retire_threat_fact()
	await get_tree().create_timer(0.18).timeout
	if is_inside_tree():
		queue_free()


func configure_attack_identity(
	run_id: StringName,
	source_id: StringName,
	generation: int,
	attack_owner: Node = null
) -> bool:
	var normalized_run_id := str(run_id).strip_edges()
	var normalized_source_id := str(source_id).strip_edges()
	if (
		_attack_identity_locked
		or normalized_run_id.is_empty()
		or normalized_run_id.length() > 64
		or normalized_source_id.is_empty()
		or normalized_source_id.length() > 64
		or generation <= 0
	):
		return false
	var configured_run_id := StringName(normalized_run_id)
	var configured_source_id := StringName(normalized_source_id)
	if _hostile_threat_registry != null:
		var fact := _threat_fact(configured_source_id, generation)
		if fact.is_empty() or not bool(_hostile_threat_registry.call("register_fact", fact)):
			return false
		_registered_threat_fact = fact.duplicate(true)
	_run_id = configured_run_id
	hostile_source_id = configured_source_id
	attack_generation = generation
	_attack_owner = attack_owner
	_attack_identity_locked = true
	return true


func configure_hostile_threat_authority(
	registry: RefCounted,
	runtime_frame_provider: Callable = Callable()
) -> bool:
	if (
		registry == null
		or not registry.has_method("register_fact")
		or not registry.has_method("retire")
		or not runtime_frame_provider.is_valid()
		or _attack_identity_locked
	):
		return false
	_hostile_threat_registry = registry
	_hostile_runtime_frame_provider = runtime_frame_provider
	return true


func _threat_fact(source_id: StringName, generation: int) -> Dictionary:
	var active_from := _hostile_runtime_frame()
	var active_frames := maxi(1, ceili(maxf(0.0, arm_delay) * 60.0))
	return HostileTelegraphFactScript.create({
		"hostile_source_id": source_id,
		"attack_generation": generation,
		"shape": "target_circle",
		"origin": global_position,
		"aim_direction": Vector2.RIGHT,
		"target_point": global_position,
		"summon_slots": [],
		"radius": radius,
		"length": 0.0,
		"active_from_frame": active_from,
		"active_through_frame": active_from + active_frames - 1,
	})


func _hostile_runtime_frame() -> int:
	if _hostile_runtime_frame_provider.is_valid():
		var value: Variant = _hostile_runtime_frame_provider.call()
		if typeof(value) == TYPE_INT and int(value) >= 0:
			return int(value)
	return maxi(0, int(Engine.get_physics_frames()))


func _retire_threat_fact() -> bool:
	if _registered_threat_fact.is_empty():
		return false
	var source_id := StringName(str(_registered_threat_fact.get("hostile_source_id", "")))
	var generation := int(_registered_threat_fact.get("attack_generation", 0))
	_registered_threat_fact.clear()
	if _hostile_threat_registry == null:
		return true
	return bool(_hostile_threat_registry.call("retire", source_id, generation))


func _exit_tree() -> void:
	_retire_threat_fact()


func tick_identities_for_test(target_count: int) -> Array[Dictionary]:
	if not _attack_identity_locked or target_count <= 0:
		return []
	var result: Array[Dictionary] = []
	for index: int in range(target_count):
		result.append({
			"hostile_source_id": hostile_source_id,
			"attack_generation": attack_generation,
			"hit_index": index,
		})
	return result


func attack_identity_snapshot() -> Dictionary:
	if not _attack_identity_locked:
		return {}
	return {
		"run_id": _run_id,
		"hostile_source_id": hostile_source_id,
		"attack_generation": attack_generation,
	}


func _target_identity(node: Node, fallback: String) -> StringName:
	if node != null and is_instance_valid(node):
		for key: StringName in [&"stable_target_id", &"stable_target_key"]:
			if node.has_meta(key):
				var value := str(node.get_meta(key)).strip_edges()
				if not value.is_empty():
					return StringName(value)
		var node_name := str(node.name).strip_edges()
		if not node_name.is_empty() and not node_name.begins_with("@"):
			return StringName(node_name)
	return StringName(fallback)
