extends "res://scripts/enemies/enemy_base.gd"
class_name EnemyTank

enum TankAction {
	NONE,
	MELEE,
	OVERLOAD_PULSE,
}

const OVERLOAD_ACTION_ID := "OVERLOAD_PULSE"
const OVERLOAD_COOLDOWN_SEQUENCE: Array[float] = [5.0, 6.0, 7.0]

@export var overload_radius: float = 96.0
@export var overload_damage_multiplier: float = 1.25
@export var overload_windup: float = 0.9
@export var overload_recovery: float = 0.65

@onready var combat_telegraph: Node2D = $CombatTelegraph2D

var _tank_action: TankAction = TankAction.NONE
var _overload_cooldown_remaining: float = 0.0
var _overload_cooldown_index: int = 0
var _overload_resolution_count: int = 0


func _init() -> void:
	attack_windup = 0.75
	attack_recovery = 0.80


func _ready() -> void:
	max_hp = 150.0
	attack = 18.0
	defense = 2.0
	move_speed = 70.0
	attack_range = 44.0
	attack_cooldown = 1.35
	super()


func _tick_ai(_delta: float) -> void:
	if _try_begin_overload_pulse():
		return
	if global_position.distance_to(target.global_position) <= attack_range:
		_try_begin_primary_attack()
		return
	_move_toward_target()


func _tick_additional_action_timers(delta: float) -> void:
	if not _is_elite:
		return
	_overload_cooldown_remaining = maxf(0.0, _overload_cooldown_remaining - delta)


func _try_begin_primary_attack() -> bool:
	if _tank_action != TankAction.NONE:
		return false
	_tank_action = TankAction.MELEE
	if super():
		return true
	_tank_action = TankAction.NONE
	return false


func _try_begin_overload_pulse(ignore_cooldown: bool = false) -> bool:
	if not _is_elite or _tank_action != TankAction.NONE or attack_phase() != AttackPhase.READY:
		return false
	if not ignore_cooldown and _overload_cooldown_remaining > 0.0:
		return false
	if target == null or not is_instance_valid(target):
		return false
	if global_position.distance_to(target.global_position) > overload_radius:
		return false
	if _commit_hostile_attack().is_empty():
		return false
	_tank_action = TankAction.OVERLOAD_PULSE
	_committed_attack_direction = global_position.direction_to(target.global_position)
	if _committed_attack_direction.is_zero_approx():
		_committed_attack_direction = Vector2.RIGHT
	if not _show_overload_telegraph():
		_committed_attack_generation = 0
		_tank_action = TankAction.NONE
		return false
	_set_attack_phase(AttackPhase.WINDUP, overload_windup)
	velocity = Vector2.ZERO
	return true


func _resolve_primary_attack() -> void:
	if _tank_action == TankAction.OVERLOAD_PULSE:
		_resolve_overload_pulse()
		return
	super()


func _resolve_overload_pulse() -> void:
	_overload_resolution_count += 1
	combat_telegraph.clear_telegraph()
	if _committed_attack_generation <= 0:
		return
	var candidates: Array[Node] = []
	for candidate: Node in get_tree().get_nodes_in_group("player"):
		if candidate is Node2D:
			candidates.append(candidate)
	candidates.sort_custom(func(left: Node, right: Node) -> bool:
		return str(_stable_damage_identity(left, "player")) < str(_stable_damage_identity(right, "player"))
	)
	var hit_index := 0
	for candidate: Node in candidates:
		if global_position.distance_to((candidate as Node2D).global_position) > overload_radius:
			continue
		var health_component := candidate.get_node_or_null("HealthComponent")
		if health_component == null:
			continue
		var damage_info := DamageInfoScript.from_plan({
			"run_id": _damage_run_id(),
			"target_id": _stable_damage_identity(candidate, "player"),
			"hostile_source_id": hostile_source_id,
			"attack_generation": _committed_attack_generation,
			"hit_index": hit_index,
			"action_token": _committed_attack_generation,
			"amount": attack * overload_damage_multiplier,
			"damage_type": DamageInfoScript.DamageType.PHYSICAL,
			"source": self,
			"attacker": self,
			"can_crit": true,
			"crit_chance": 0.0,
			"crit_multiplier": 1.5,
			"knockback": global_position.direction_to((candidate as Node2D).global_position) * 240.0,
			"tags": ["enemy:area", "elite:overload_pulse"],
			"source_generation": _committed_attack_generation,
			"control_effect": {},
		})
		if damage_info == null:
			continue
		health_component.take_damage(damage_info)
		hit_index += 1
	_schedule_next_overload_cooldown()

func _active_attack_recovery_duration() -> float:
	if _tank_action == TankAction.OVERLOAD_PULSE:
		return overload_recovery
	return super()


func _on_attack_phase_clock_updated() -> void:
	if _tank_action == TankAction.OVERLOAD_PULSE and attack_phase() == AttackPhase.WINDUP:
		combat_telegraph.set_remaining_time(_attack_phase_remaining)


func _on_attack_sequence_completed() -> void:
	_tank_action = TankAction.NONE
	combat_telegraph.clear_telegraph()


func _on_attack_runtime_cancelled() -> void:
	_tank_action = TankAction.NONE
	if combat_telegraph != null:
		combat_telegraph.clear_telegraph()


func _on_elite_modifier_applied() -> void:
	_overload_cooldown_index = 0
	_schedule_next_overload_cooldown()


func _schedule_next_overload_cooldown() -> void:
	_overload_cooldown_remaining = OVERLOAD_COOLDOWN_SEQUENCE[_overload_cooldown_index]
	_overload_cooldown_index = (_overload_cooldown_index + 1) % OVERLOAD_COOLDOWN_SEQUENCE.size()


func _show_overload_telegraph() -> bool:
	var fact := _register_committed_hostile_threat(
		"circle",
		global_position,
		_committed_attack_direction,
		target.global_position,
		[],
		overload_radius,
		0.0,
		overload_windup + overload_recovery
	)
	if fact.is_empty():
		return _hostile_threat_registry == null
	return bool(combat_telegraph.project_fact(fact, OVERLOAD_ACTION_ID, overload_windup))


func _exit_tree() -> void:
	cancel_active_attack()
	retire_hostile_identity(&"tree_exit")
	super()


func force_overload_pulse_for_test() -> bool:
	return _try_begin_overload_pulse(true)


func pulse_identities_for_test(target_count: int) -> Array[Dictionary]:
	if target_count <= 0:
		return []
	var committed := _commit_hostile_attack()
	if committed.is_empty():
		return []
	var generation := int(committed["attack_generation"])
	var result: Array[Dictionary] = []
	for index: int in range(target_count):
		result.append(_hostile_hit_identity(generation, index))
	return result


func set_overload_cooldown_for_test(value: float) -> void:
	_overload_cooldown_remaining = maxf(0.0, value)


func advance_action_for_test(delta: float) -> void:
	if _time_stopped:
		return
	_tick_attack_phase(maxf(0.0, delta))


func get_elite_action_snapshot_for_test() -> Dictionary:
	return {
		"action": _tank_action_name(),
		"phase": _attack_phase_name(),
		"phase_remaining": _attack_phase_remaining,
		"cooldown_remaining": _overload_cooldown_remaining,
		"resolution_count": _overload_resolution_count,
		"telegraph": combat_telegraph.get_snapshot(),
	}


func _tank_action_name() -> String:
	match _tank_action:
		TankAction.MELEE:
			return "MELEE"
		TankAction.OVERLOAD_PULSE:
			return OVERLOAD_ACTION_ID
	return "NONE"


func _attack_phase_name() -> String:
	match attack_phase():
		AttackPhase.WINDUP:
			return "WINDUP"
		AttackPhase.RECOVERY:
			return "RECOVERY"
	return "READY"


func _restore_visual_color() -> void:
	if _is_elite:
		visual.color = Color(1.0, 0.86, 0.22)
		return
	visual.color = Color(0.75, 0.35, 0.95)
