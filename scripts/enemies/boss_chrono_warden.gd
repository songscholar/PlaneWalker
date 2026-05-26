extends "res://scripts/enemies/enemy_base.gd"
class_name BossChronoWarden

const FragmentScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const TimeCrackScript := preload("res://scripts/enemies/boss_time_crack.gd")

@export var projectile_scene: PackedScene
@export var radial_projectile_count: int = 8
@export var exposed_defense_penalty: float = 3.0
@export var slam_windup: float = 0.75
@export var slam_recovery: float = 0.9
@export var slam_radius: float = 72.0
@export var fragment_count: int = 2
@export var crack_arm_delay: float = 1.15

var _base_defense: float = 0.0
var _pattern_timer: float = 0.0
var _exposed: bool = false
var _phase: int = 1
var _aimed_burst_next: bool = false
var _special_index: int = 0
var _slam_timer: float = 0.0
var _slam_recovery_timer: float = 0.0
var _exposure_sources: Dictionary = {}


func _ready() -> void:
	max_hp = 420.0
	attack = 16.0
	defense = 3.0
	move_speed = 78.0
	attack_range = 54.0
	attack_cooldown = 1.1
	_base_defense = defense
	super()
	add_to_group("bosses")
	health.damaged.connect(_on_boss_damaged)


func _tick_ai(delta: float) -> void:
	_update_phase()
	_tick_slam(delta)
	_pattern_timer = maxf(0.0, _pattern_timer - delta)
	if global_position.distance_to(target.global_position) > attack_range:
		_move_toward_target(0.7)
	else:
		velocity = _knockback_velocity
		move_and_slide()
		_try_melee_attack()
	if _pattern_timer <= 0.0:
		_pattern_timer = _pattern_interval()
		_run_next_pattern()


func _tick_slam(delta: float) -> void:
	if _slam_timer > 0.0:
		_slam_timer = maxf(0.0, _slam_timer - delta)
		if _slam_timer <= 0.0:
			_resolve_slam()
	if _slam_recovery_timer > 0.0:
		_slam_recovery_timer = maxf(0.0, _slam_recovery_timer - delta)
		if _slam_recovery_timer <= 0.0:
			_remove_exposure_source(&"slam_recovery")


func _run_next_pattern() -> void:
	match _special_index % 4:
		0:
			_start_slam()
		1:
			if _phase >= 2:
				_summon_fragments()
			else:
				_fire_radial_burst()
		2:
			if _phase >= 2:
				_create_time_crack()
			else:
				_fire_aimed_or_radial_burst()
		_:
			_fire_aimed_or_radial_burst()
	_special_index += 1


func _fire_aimed_or_radial_burst() -> void:
	if _phase >= 2 and _aimed_burst_next:
		_fire_aimed_burst()
	else:
		_fire_radial_burst()
	_aimed_burst_next = not _aimed_burst_next


func _update_phase() -> void:
	var hp_ratio: float = health.current_hp / maxf(1.0, health.max_hp)
	var next_phase := 1
	if hp_ratio <= 0.25:
		next_phase = 3
	elif hp_ratio <= 0.55:
		next_phase = 2
	if next_phase == _phase:
		return
	_phase = next_phase
	radial_projectile_count = 10 if _phase == 2 else 12
	move_speed = 92.0 if _phase == 2 else 108.0
	_restore_visual_color()


func _pattern_interval() -> float:
	if _exposed:
		return 3.0
	if _phase == 3:
		return 1.55
	if _phase == 2:
		return 1.9
	return 2.4


func _fire_radial_burst() -> void:
	if projectile_scene == null:
		return
	for index: int in range(radial_projectile_count):
		var angle := TAU * float(index) / float(radial_projectile_count)
		var projectile := projectile_scene.instantiate()
		projectile.global_position = global_position + Vector2.RIGHT.rotated(angle) * 34.0
		projectile.direction = Vector2.RIGHT.rotated(angle)
		projectile.damage = attack * 0.65
		get_parent().add_child(projectile)


func _fire_aimed_burst() -> void:
	if projectile_scene == null or target == null:
		return
	var base_direction := global_position.direction_to(target.global_position)
	var spread := 0.18 if _phase == 2 else 0.28
	var shot_count := 3 if _phase == 2 else 5
	for index: int in range(shot_count):
		var centered_index := float(index) - float(shot_count - 1) * 0.5
		var projectile := projectile_scene.instantiate()
		projectile.global_position = global_position + base_direction * 34.0
		projectile.direction = base_direction.rotated(centered_index * spread)
		projectile.speed = 230.0 if _phase == 2 else 260.0
		projectile.damage = attack * 0.7
		get_parent().add_child(projectile)


func _start_slam() -> void:
	if _slam_timer > 0.0 or _slam_recovery_timer > 0.0:
		return
	_slam_timer = slam_windup
	visual.scale = Vector2(1.18, 1.18)
	visual.color = Color(1.0, 0.72, 0.18)


func _resolve_slam() -> void:
	if target != null and is_instance_valid(target) and global_position.distance_to(target.global_position) <= slam_radius:
		var health_component := target.get_node_or_null("HealthComponent")
		if health_component != null:
			var damage_info := DamageInfoScript.new(attack * 1.6, DamageInfoScript.DamageType.PHYSICAL, self, self)
			damage_info.tags = ["boss:slam", "enemy:melee"]
			damage_info.knockback = global_position.direction_to(target.global_position) * 260.0
			health_component.take_damage(damage_info)
	_slam_recovery_timer = slam_recovery
	_add_exposure_source(&"slam_recovery")
	visual.scale = Vector2.ONE


func _summon_fragments() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for index: int in range(fragment_count):
		var fragment := FragmentScene.instantiate()
		parent.add_child(fragment)
		fragment.global_position = global_position + Vector2.RIGHT.rotated(TAU * float(index) / maxf(1.0, float(fragment_count))) * 86.0
		if fragment.has_method("apply_elite_modifier") and _phase >= 3:
			fragment.apply_elite_modifier(1.25, 1.1, 1.0)
		EventBus.enemy_spawned.emit(fragment)
		EventBus.publish(EventBus.ENEMY_SPAWNED, {"enemy": fragment, "summoned": true})


func _create_time_crack() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	var crack := TimeCrackScript.new()
	crack.arm_delay = crack_arm_delay
	crack.radius = 58.0 if _phase >= 3 else 50.0
	crack.damage = attack * 1.15
	parent.add_child(crack)
	var crack_position := target.global_position if target != null and is_instance_valid(target) else global_position
	crack.global_position = crack_position
	return crack


func force_slam_for_test() -> void:
	_start_slam()


func force_summon_fragments_for_test() -> void:
	_summon_fragments()


func force_time_crack_for_test() -> Node:
	return _create_time_crack()


func _restore_visual_color() -> void:
	if _exposed:
		visual.color = Color(0.3, 0.85, 1.0)
	elif _phase == 3:
		visual.color = Color(1.0, 0.1, 0.55)
	elif _phase == 2:
		visual.color = Color(1.0, 0.35, 0.25)
	else:
		visual.color = Color(0.95, 0.15, 0.35)


func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	var resisted_delay := minf(duration * 0.35, 1.1)
	_pattern_timer += resisted_delay
	_slam_timer += resisted_delay
	_slam_recovery_timer += resisted_delay
	_add_exposure_source(&"time_stop")
	await get_tree().create_timer(duration).timeout
	_remove_exposure_source(&"time_stop")


func apply_time_rift(slow_multiplier: float) -> void:
	super.apply_time_rift(slow_multiplier)
	_add_exposure_source(&"time_rift")
	_pattern_timer = maxf(_pattern_timer, 1.2)


func clear_time_rift() -> void:
	super.clear_time_rift()
	if _rift_slow_sources == 0:
		_remove_exposure_source(&"time_rift")


func _add_exposure_source(source_id: StringName) -> void:
	_exposure_sources[source_id] = int(_exposure_sources.get(source_id, 0)) + 1
	_refresh_exposed_state()


func _remove_exposure_source(source_id: StringName) -> void:
	if not _exposure_sources.has(source_id):
		return
	var remaining := int(_exposure_sources[source_id]) - 1
	if remaining <= 0:
		_exposure_sources.erase(source_id)
	else:
		_exposure_sources[source_id] = remaining
	_refresh_exposed_state()


func _refresh_exposed_state() -> void:
	_set_exposed(not _exposure_sources.is_empty())


func _set_exposed(value: bool) -> void:
	_exposed = value
	health.defense = maxf(0.0, _base_defense - exposed_defense_penalty) if _exposed else _base_defense
	_restore_visual_color()


func _on_boss_damaged(_amount: float, _current_hp: float) -> void:
	_update_phase()
