class_name EnemyProjectile
extends Area2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

@export var speed: float = 190.0
@export var lifetime: float = 4.0
@export var damage: float = 8.0
@export var arm_time: float = 0.18

@onready var visual: Polygon2D = $Visual

var direction: Vector2 = Vector2.RIGHT
var _time_stopped: bool = false
var _age: float = 0.0
var _armed: bool = false
var _resolved: bool = false
var _time_stop_token_sequence: int = 0
var _time_stop_sources: Dictionary = {}
var _rift_slow_multiplier: float = 1.0
var _rift_slow_sources: Dictionary = {}


func _ready() -> void:
	add_to_group("time_stoppable")
	monitoring = false
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	visual.modulate = Color(1.0, 0.95, 0.35, 0.45)


func _physics_process(delta: float) -> void:
	if _time_stopped:
		return
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	if not _armed and _age >= arm_time:
		_armed = true
		monitoring = true
		visual.modulate = Color(1.0, 0.78, 0.25, 1.0)
		visual.scale = Vector2(1.25, 1.25)
	if not _armed:
		visual.rotation += delta * 8.0
		return
	global_position += direction.normalized() * speed * _rift_slow_multiplier * delta


func _on_area_entered(area: Area2D) -> void:
	if area.has_method("receive_hit") and area.get_parent().is_in_group("player"):
		_try_hit_player(area)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_node("HealthComponent"):
		_try_hit_player(body)


func _try_hit_player(target: Node) -> void:
	if _resolved or target == null:
		return
	var damage_info := DamageInfoScript.new(damage, DamageInfoScript.DamageType.PHYSICAL, self, self)
	damage_info.tags = ["enemy:projectile"]
	if target.has_method("receive_hit"):
		_resolved = true
		target.receive_hit(damage_info)
	elif target.has_node("HealthComponent"):
		_resolved = true
		target.get_node("HealthComponent").take_damage(damage_info)
	else:
		return
	queue_free()


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


func apply_time_rift(source_id: StringName, slow_multiplier: float) -> void:
	_rift_slow_sources[source_id] = clampf(slow_multiplier, 0.1, 1.0)
	_recompute_rift_slow()


func clear_time_rift(source_id: StringName) -> void:
	_rift_slow_sources.erase(source_id)
	_recompute_rift_slow()


func _recompute_rift_slow() -> void:
	_rift_slow_multiplier = 1.0
	for source_multiplier: Variant in _rift_slow_sources.values():
		_rift_slow_multiplier = minf(_rift_slow_multiplier, float(source_multiplier))
