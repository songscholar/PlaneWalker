extends "res://scripts/enemies/enemy_base.gd"
class_name EnemyShooter

@export var projectile_scene: PackedScene
@export var preferred_distance: float = 220.0
@export_range(1, 16, 1) var projectiles_per_burst: int = 1
@export_range(0.0, 1.0, 0.01) var burst_spread_radians: float = 0.0


func _init() -> void:
	attack_windup = 0.60
	attack_recovery = 0.45


func _ready() -> void:
	max_hp = 45.0
	attack = 8.0
	move_speed = 90.0
	attack_range = 420.0
	attack_cooldown = 1.4
	super()


func _tick_ai(_delta: float) -> void:
	var distance := global_position.distance_to(target.global_position)
	if distance < preferred_distance * 0.75:
		var away := target.global_position.direction_to(global_position)
		velocity = away * _current_move_speed() + _knockback_velocity
		move_and_slide()
	elif distance > preferred_distance * 1.25:
		_move_toward_target(0.75)
	else:
		velocity = _knockback_velocity
		move_and_slide()
	_try_shoot()


func _try_shoot() -> void:
	if projectile_scene == null:
		return
	_try_begin_primary_attack()


func _resolve_primary_attack() -> void:
	if projectile_scene == null or _committed_attack_generation <= 0:
		return
	var projectile_parent := get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_parent()
	if projectile_parent == null:
		return
	var pellet_count := maxi(1, projectiles_per_burst)
	for index: int in range(pellet_count):
		var centered_index := float(index) - float(pellet_count - 1) * 0.5
		var projectile := projectile_scene.instantiate()
		projectile.direction = _committed_attack_direction.rotated(
			centered_index * burst_spread_radians
		)
		projectile.damage = attack
		if projectile.has_method("configure_attack_identity"):
			projectile.call(
				"configure_attack_identity",
				_damage_run_id(),
				hostile_source_id,
				_committed_attack_generation,
				index,
				self
			)
		projectile_parent.add_child(projectile)
		projectile.global_position = global_position


func _primary_attack_threat_geometry() -> Dictionary:
	return {
		"shape": "line",
		"origin": global_position,
		"aim_direction": _committed_attack_direction,
		"target_point": target.global_position if target != null and is_instance_valid(target) else global_position,
		"summon_slots": [],
		"radius": 6.0,
		"length": maxf(1.0, attack_range),
		"duration": attack_windup + attack_recovery,
	}


func projectile_identities_for_test(pellet_count: int) -> Array[Dictionary]:
	if pellet_count <= 0:
		return []
	var committed := _commit_hostile_attack()
	if committed.is_empty():
		return []
	var generation := int(committed["attack_generation"])
	var result: Array[Dictionary] = []
	for index: int in range(pellet_count):
		result.append(_hostile_hit_identity(generation, index))
	return result


func _restore_visual_color() -> void:
	if _is_elite:
		visual.color = Color(1.0, 0.86, 0.22)
		return
	visual.color = Color(0.95, 0.62, 0.2)
