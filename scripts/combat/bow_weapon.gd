class_name BowWeapon
extends Node2D

const ArrowScene := preload("res://scenes/combat/player_arrow.tscn")
const WEAPON_ID := &"bow"
const PIXELS_PER_CELL := 64.0
const LAUNCH_PROFILE_ID := "bow_launch_v1"
const RUNTIME_SNAPSHOT_SCHEMA_VERSION := 1
const LAUNCH_ACTION_IDS: Array[String] = [
	"precision_draw",
	"scatter_shot",
	"focus_step",
	"temporal_arrow",
	"starfall_arrow_rain",
]

@export var owner_path: NodePath
@export var base_attack: float = 30.0
@export var attack_speed: float = 1.0

@onready var owner_player: Node2D = get_node(owner_path)

var _profile_shot: Dictionary = {}
var _profile_shot_released: bool = false
var _profile_action: Dictionary = {}
var _profile_action_released: bool = false
var _profile_action_shared_claims: Dictionary = {}
var _starfall_schedule: Dictionary = {}
var _starfall_targets: Dictionary = {}
var _starfall_source_id: StringName = &""
var _starfall_elapsed_frames: int = 0
var _starfall_invulnerability_health: Node
var _starfall_invulnerability_source_id: StringName = &""


func weapon_id() -> StringName:
	return WEAPON_ID


func reset_runtime_state() -> void:
	_clear_spawned_projectiles()
	cancel_profile_shot()
	cancel_profile_action()


func _exit_tree() -> void:
	_clear_starfall_schedule()
	_clear_spawned_projectiles()


func begin_profile_shot(definition: Dictionary) -> Dictionary:
	if is_profile_action_active() or not _profile_definition_is_valid(definition):
		return {}
	var direction: Vector2 = definition["direction"]
	if direction.length_squared() <= 0.001:
		direction = Vector2.RIGHT.rotated(global_rotation)
	_profile_shot = definition.duplicate(true)
	_profile_shot["direction"] = direction.normalized()
	_profile_shot_released = false
	return _profile_shot.duplicate(true)


func release_profile_shot() -> bool:
	if _profile_shot.is_empty() or _profile_shot_released:
		return false
	var arrow := ArrowScene.instantiate()
	var direction: Vector2 = _profile_shot["direction"]
	arrow.global_position = global_position + direction * 28.0
	arrow.direction = direction
	arrow.damage = float(_profile_shot["damage"])
	arrow.speed = float(_profile_shot["speed"])
	arrow.pierce = int(_profile_shot["pierce"])
	arrow.full_charge = bool(_profile_shot["full_charge"])
	arrow.time_energy_restore = float(_profile_shot["time_energy_restore"])
	arrow.action_token = int(_profile_shot["token"])
	arrow.energy_reward_once_per_action = bool(
		_profile_shot.get("energy_reward_once_per_action", false)
	)
	arrow.attack_tags.clear()
	for tag_value: Variant in _profile_shot["tags"]:
		var tag := str(tag_value)
		if not tag.is_empty() and not arrow.attack_tags.has(tag):
			arrow.attack_tags.append(tag)
	arrow.source = self
	arrow.owner_entity = owner_player
	var current_scene := get_tree().current_scene
	if current_scene == null:
		arrow.free()
		return false
	current_scene.add_child(arrow)
	_profile_shot_released = true
	return true


func is_profile_action_active() -> bool:
	return not _profile_shot.is_empty() or not _profile_action.is_empty()


func cancel_profile_shot() -> void:
	_profile_shot.clear()
	_profile_shot_released = false


func finish_profile_shot() -> void:
	cancel_profile_shot()


func begin_profile_action(definition: Dictionary) -> Dictionary:
	if is_profile_action_active() or not _launch_definition_is_valid(definition):
		return {}
	_profile_action = definition.duplicate(true)
	_profile_action["_execution_base_attack"] = base_attack
	_profile_action_released = false
	_profile_action_shared_claims = {}
	_clear_starfall_schedule()
	return definition.duplicate(true)


func release_profile_action() -> bool:
	if _profile_action.is_empty() or _profile_action_released or get_tree().current_scene == null:
		return false
	var rewind_preflight := _prepare_rewind_phantoms(_profile_action)
	if not bool(rewind_preflight.get("ok", false)):
		return false
	var rewind_descriptors: Array = rewind_preflight.get("descriptors", [])
	var descriptors: Array = _profile_action["payload_descriptors"]
	var prepared_main: Array[Dictionary] = []
	var has_non_projectile := false
	for descriptor_value: Variant in descriptors:
		var descriptor: Dictionary = descriptor_value
		match str(descriptor["kind"]):
			"projectile", "projectile_trail":
				var prepared := _prepare_projectile(descriptor, _profile_action)
				if prepared.is_empty():
					_free_prepared_projectiles(prepared_main)
					return false
				prepared_main.append(prepared)
			"movement", "zone_schedule":
				has_non_projectile = true
				if not _non_projectile_can_execute(descriptor):
					_free_prepared_projectiles(prepared_main)
					return false
			_:
				_free_prepared_projectiles(prepared_main)
				return false
	var prepared_rewind: Array[Dictionary] = []
	for descriptor_value: Variant in rewind_descriptors:
		var prepared := _prepare_projectile(descriptor_value, _profile_action)
		if prepared.is_empty():
			_free_prepared_projectiles(prepared_main)
			_free_prepared_projectiles(prepared_rewind)
			return false
		prepared_rewind.append(prepared)
	var claim_required := bool(rewind_preflight.get("claim_required", false))
	if claim_required and has_non_projectile:
		_free_prepared_projectiles(prepared_main)
		_free_prepared_projectiles(prepared_rewind)
		return false
	if claim_required and not _claim_rewind_generation(int(rewind_preflight["generation"])):
		_free_prepared_projectiles(prepared_rewind)
		prepared_rewind.clear()
	var current_scene := get_tree().current_scene
	for prepared: Dictionary in prepared_main:
		_attach_prepared_projectile(prepared, current_scene)
	for prepared: Dictionary in prepared_rewind:
		_attach_prepared_projectile(prepared, current_scene)
	for descriptor_value: Variant in descriptors:
		var descriptor: Dictionary = descriptor_value
		var succeeded := true
		match str(descriptor["kind"]):
			"movement":
				succeeded = _execute_movement(descriptor)
			"zone_schedule":
				succeeded = _start_starfall_schedule(descriptor, _profile_action)
		if not succeeded:
			_clear_starfall_schedule()
			_clear_projectiles_for_action_token(int(_profile_action["token"]))
			return false
	_profile_action_released = true
	return true


func cancel_profile_action() -> void:
	_profile_action.clear()
	_profile_action_released = false
	_profile_action_shared_claims = {}
	_clear_starfall_schedule()


func finish_profile_action() -> void:
	_profile_action.clear()
	_profile_action_released = false
	_profile_action_shared_claims = {}
	_clear_starfall_schedule()


func advance_profile_action_frames(frames: int) -> void:
	if frames > 0:
		_advance_starfall_schedule(frames)


func advance_profile_action_for_test(frames: int) -> void:
	advance_profile_action_frames(frames)


func runtime_snapshot() -> Dictionary:
	var arrows: Array[Dictionary] = []
	if is_inside_tree():
		for arrow: Node in get_tree().get_nodes_in_group("player_arrows"):
			if (
				arrow == null
				or not is_instance_valid(arrow)
				or arrow.is_queued_for_deletion()
				or arrow.get("source") != self
				or not arrow is Node2D
				or not arrow.has_method("execution_snapshot")
			):
				continue
			arrows.append({
				"global_position": (arrow as Node2D).global_position,
				"execution": (arrow.call("execution_snapshot") as Dictionary).duplicate(true),
			})
	arrows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_execution := left["execution"] as Dictionary
		var right_execution := right["execution"] as Dictionary
		var left_key := "%012d:%08d:%s" % [int(left_execution.get("action_token", 0)), int(left_execution.get("outcome_index", 0)), str(left_execution.get("descriptor_id", ""))]
		var right_key := "%012d:%08d:%s" % [int(right_execution.get("action_token", 0)), int(right_execution.get("outcome_index", 0)), str(right_execution.get("descriptor_id", ""))]
		return left_key < right_key
	)
	var claims_by_token: Dictionary = {}
	for arrow_snapshot: Dictionary in arrows:
		var execution := arrow_snapshot["execution"] as Dictionary
		var token_key := str(int(execution.get("action_token", 0)))
		var claims := (execution.get("interaction_claims", {}) as Dictionary).duplicate(true)
		if claims_by_token.has(token_key) and claims_by_token[token_key] != claims:
			return {}
		claims_by_token[token_key] = claims
	if not _profile_action.is_empty():
		claims_by_token[str(int(_profile_action.get("token", 0)))] = _profile_action_shared_claims.duplicate(true)
	return {
		"schema_version": RUNTIME_SNAPSHOT_SCHEMA_VERSION,
		"phase_state": _runtime_phase_state(),
		"profile_shot": _profile_shot.duplicate(true),
		"profile_shot_released": _profile_shot_released,
		"profile_action": _profile_action.duplicate(true),
		"profile_action_released": _profile_action_released,
		"shared_claims": _profile_action_shared_claims.duplicate(true),
		"claims_by_token": claims_by_token,
		"starfall_schedule": _starfall_schedule.duplicate(true),
		"starfall_source_id": str(_starfall_source_id),
		"starfall_elapsed_frames": _starfall_elapsed_frames,
		"starfall_targets": _starfall_target_snapshot(),
		"starfall_invulnerability_active": _starfall_invulnerability_source_id != &"",
		"arrows": arrows,
	}


func can_restore_runtime_snapshot(value: Dictionary) -> bool:
	var staged := _stage_runtime_snapshot(value)
	if not bool(staged.get("ok", false)):
		return false
	_free_staged_arrows(staged)
	return true


func restore_runtime_snapshot(value: Dictionary) -> bool:
	var target_staged := _stage_runtime_snapshot(value)
	if not bool(target_staged.get("ok", false)):
		return false
	var current := runtime_snapshot()
	if current.is_empty():
		_free_staged_arrows(target_staged)
		return false
	if current == value:
		_free_staged_arrows(target_staged)
		return true
	var rollback_staged := _stage_runtime_snapshot(current)
	if not bool(rollback_staged.get("ok", false)):
		_free_staged_arrows(target_staged)
		return false
	if _install_runtime_snapshot(value, target_staged) and runtime_snapshot() == value:
		_free_staged_arrows(rollback_staged)
		return true
	_discard_runtime_state()
	if _install_runtime_snapshot(current, rollback_staged) and runtime_snapshot() == current:
		return false
	_free_staged_arrows(rollback_staged)
	reset_runtime_state()
	return false


func _runtime_phase_state() -> String:
	if not _profile_action.is_empty():
		return "action_released" if _profile_action_released else "action_prepared"
	if not _profile_shot.is_empty():
		return "shot_released" if _profile_shot_released else "shot_prepared"
	return "idle"


func _stage_runtime_snapshot(value: Dictionary) -> Dictionary:
	if not _runtime_snapshot_shape_is_valid(value):
		return {"ok": false}
	var arrows: Array[Dictionary] = []
	for arrow_value: Variant in value["arrows"] as Array:
		if not arrow_value is Dictionary:
			_free_prepared_projectiles(arrows)
			return {"ok": false}
		var arrow_snapshot := arrow_value as Dictionary
		var position_value: Variant = arrow_snapshot.get("global_position")
		var execution_value: Variant = arrow_snapshot.get("execution")
		if not position_value is Vector2 or not _finite_vector(position_value as Vector2) or not execution_value is Dictionary:
			_free_prepared_projectiles(arrows)
			return {"ok": false}
		var arrow := ArrowScene.instantiate()
		if not arrow.has_method("restore_execution_snapshot") or not bool(arrow.call("restore_execution_snapshot", execution_value)):
			arrow.free()
			_free_prepared_projectiles(arrows)
			return {"ok": false}
		arrow.set("source", self)
		arrow.set("owner_entity", owner_player)
		arrows.append({"node": arrow, "global_position": position_value})
	return {"ok": true, "arrows": arrows}


func _runtime_snapshot_shape_is_valid(value: Dictionary) -> bool:
	var expected_fields: Array[String] = [
		"schema_version", "phase_state", "profile_shot", "profile_shot_released",
		"profile_action", "profile_action_released", "shared_claims", "claims_by_token",
		"starfall_schedule", "starfall_source_id", "starfall_elapsed_frames",
		"starfall_targets", "starfall_invulnerability_active", "arrows",
	]
	if (
		not _has_exact_fields(value, expected_fields)
		or int(value.get("schema_version", -1)) != RUNTIME_SNAPSHOT_SCHEMA_VERSION
		or str(value.get("phase_state", "")) not in ["idle", "shot_prepared", "shot_released", "action_prepared", "action_released"]
		or not value.get("profile_shot") is Dictionary
		or typeof(value.get("profile_shot_released")) != TYPE_BOOL
		or not value.get("profile_action") is Dictionary
		or typeof(value.get("profile_action_released")) != TYPE_BOOL
		or not value.get("shared_claims") is Dictionary
		or not value.get("claims_by_token") is Dictionary
		or not value.get("starfall_schedule") is Dictionary
		or typeof(value.get("starfall_source_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or typeof(value.get("starfall_elapsed_frames")) != TYPE_INT
		or int(value.get("starfall_elapsed_frames", -1)) < 0
		or not value.get("starfall_targets") is Array
		or typeof(value.get("starfall_invulnerability_active")) != TYPE_BOOL
		or not value.get("arrows") is Array
	):
		return false
	var shot := value["profile_shot"] as Dictionary
	var action := value["profile_action"] as Dictionary
	if not shot.is_empty() and not _profile_definition_is_valid(shot):
		return false
	if not action.is_empty() and not _launch_definition_is_valid(action):
		return false
	var state := str(value["phase_state"])
	if state == "idle" and (not shot.is_empty() or not action.is_empty() or bool(value["profile_shot_released"]) or bool(value["profile_action_released"])):
		return false
	if state.begins_with("shot_") and (shot.is_empty() or not action.is_empty() or bool(value["profile_shot_released"]) != state.ends_with("released")):
		return false
	if state.begins_with("action_") and (action.is_empty() or not shot.is_empty() or bool(value["profile_action_released"]) != state.ends_with("released")):
		return false
	if state != "idle" and not state.begins_with("shot_") and not state.begins_with("action_"):
		return false
	var schedule := value["starfall_schedule"] as Dictionary
	if not schedule.is_empty():
		if action.is_empty() or str(action.get("action_id", "")) != "starfall_arrow_rain" or not bool(value["profile_action_released"]):
			return false
		if not _has_exact_fields(schedule, ["descriptor", "definition", "next_wave_index", "frames_until_next", "wave_count", "wave_interval_frames"]):
			return false
		if schedule["definition"] != action or not schedule["descriptor"] is Dictionary:
			return false
		if int(schedule["next_wave_index"]) < 1 or int(schedule["next_wave_index"]) > int(schedule["wave_count"]):
			return false
		if str(value["starfall_source_id"]).is_empty():
			return false
	elif not (value["starfall_targets"] as Array).is_empty() or not str(value["starfall_source_id"]).is_empty() or int(value["starfall_elapsed_frames"]) != 0 or bool(value["starfall_invulnerability_active"]):
		return false
	if not _valid_claims_by_token(value["claims_by_token"]):
		return false
	if not _valid_starfall_target_snapshot(value["starfall_targets"]):
		return false
	var claims_by_token := value["claims_by_token"] as Dictionary
	if not action.is_empty():
		var action_token_key := str(int(action.get("token", 0)))
		if not claims_by_token.has(action_token_key) or claims_by_token[action_token_key] != value["shared_claims"]:
			return false
	elif not (value["shared_claims"] as Dictionary).is_empty():
		return false
	for arrow_value: Variant in value["arrows"] as Array:
		if not arrow_value is Dictionary:
			return false
		var arrow_snapshot := arrow_value as Dictionary
		if not _has_exact_fields(arrow_snapshot, ["global_position", "execution"]):
			return false
		var execution_value: Variant = arrow_snapshot["execution"]
		if not execution_value is Dictionary:
			return false
		var execution := execution_value as Dictionary
		var token_key := str(int(execution.get("action_token", 0)))
		if (
			not claims_by_token.has(token_key)
			or not execution.get("interaction_claims") is Dictionary
			or claims_by_token[token_key] != execution["interaction_claims"]
		):
			return false
	return true


func _install_runtime_snapshot(value: Dictionary, staged: Dictionary) -> bool:
	var arrows := staged.get("arrows", []) as Array
	var parent := get_tree().current_scene if is_inside_tree() else null
	if not arrows.is_empty() and parent == null:
		return false
	_discard_runtime_state()
	_profile_shot = (value["profile_shot"] as Dictionary).duplicate(true)
	_profile_shot_released = bool(value["profile_shot_released"])
	_profile_action = (value["profile_action"] as Dictionary).duplicate(true)
	_profile_action_released = bool(value["profile_action_released"])
	var claims_by_token := (value["claims_by_token"] as Dictionary).duplicate(true)
	_profile_action_shared_claims = (
		(claims_by_token.get(str(int(_profile_action.get("token", 0))), {}) as Dictionary).duplicate(true)
		if not _profile_action.is_empty()
		else (value["shared_claims"] as Dictionary).duplicate(true)
	)
	for prepared_value: Variant in arrows:
		var prepared := prepared_value as Dictionary
		var arrow := prepared["node"] as Node2D
		parent.add_child(arrow)
		arrow.global_position = prepared["global_position"]
		var token_claims := claims_by_token.get(str(int(arrow.get("action_token"))), {}) as Dictionary
		if not bool(arrow.call("activate_restored_execution_state", token_claims)):
			return false
	_starfall_schedule = (value["starfall_schedule"] as Dictionary).duplicate(true)
	_starfall_source_id = StringName(str(value["starfall_source_id"]))
	_starfall_elapsed_frames = int(value["starfall_elapsed_frames"])
	if not _starfall_schedule.is_empty():
		if not _restore_starfall_targets(value["starfall_targets"]):
			return false
		if bool(value["starfall_invulnerability_active"]):
			var parameters := ((_starfall_schedule["descriptor"] as Dictionary)["parameters"] as Dictionary)
			_apply_starfall_invulnerability(parameters)
			if _starfall_invulnerability_source_id == &"":
				return false
	staged["arrows"] = []
	return true


func _discard_runtime_state() -> void:
	_clear_starfall_schedule()
	_clear_spawned_projectiles_immediately()
	_profile_shot.clear()
	_profile_shot_released = false
	_profile_action.clear()
	_profile_action_released = false
	_profile_action_shared_claims.clear()


func _clear_spawned_projectiles_immediately() -> void:
	if not is_inside_tree():
		return
	for arrow: Node in get_tree().get_nodes_in_group("player_arrows"):
		if arrow != null and is_instance_valid(arrow) and arrow.get("source") == self:
			if arrow.has_method("reset_execution_state"):
				arrow.call("reset_execution_state")
			arrow.free()


func _free_staged_arrows(staged: Dictionary) -> void:
	var arrows_value: Variant = staged.get("arrows", [])
	if arrows_value is Array:
		_free_prepared_projectiles(_dictionary_array(arrows_value))
	staged["arrows"] = []


func _starfall_target_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for state_value: Variant in _starfall_targets.values():
		if not state_value is Dictionary:
			return []
		var state := state_value as Dictionary
		var target_value: Variant = state.get("target")
		if typeof(target_value) != TYPE_OBJECT or not is_instance_valid(target_value):
			return []
		result.append({
			"target_id": _stable_target_id(target_value as Node),
			"erosion_stacks": int(state.get("erosion_stacks", 0)),
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left["target_id"]) < int(right["target_id"]))
	return result


func _restore_starfall_targets(value: Variant) -> bool:
	if not value is Array:
		return false
	_starfall_targets.clear()
	var parameters := ((_starfall_schedule["descriptor"] as Dictionary)["parameters"] as Dictionary)
	var slow_ratio := clampf(float(parameters.get("slow_ratio", 0.0)), 0.0, 0.9)
	for state_value: Variant in value as Array:
		var state := state_value as Dictionary
		var target := _target_by_stable_id(int(state["target_id"]))
		if target == null:
			return false
		if slow_ratio > 0.0:
			if not target.has_method("apply_time_rift"):
				return false
			target.call("apply_time_rift", _starfall_source_id, 1.0 - slow_ratio)
		_starfall_targets[target.get_instance_id()] = {"target": target, "erosion_stacks": int(state["erosion_stacks"])}
		_set_starfall_erosion_meta(
			target,
			int(state["erosion_stacks"]),
			_starfall_time_damage_per_stack(parameters)
		)
	return true


func _valid_claims_by_token(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for token_value: Variant in value as Dictionary:
		if int(str(token_value)) <= 0 or not (value as Dictionary)[token_value] is Dictionary:
			return false
		for claim_value: Variant in ((value as Dictionary)[token_value] as Dictionary):
			if str(claim_value).is_empty() or ((value as Dictionary)[token_value] as Dictionary)[claim_value] != true:
				return false
	return true


func _valid_starfall_target_snapshot(value: Variant) -> bool:
	if not value is Array:
		return false
	var previous := 0
	for state_value: Variant in value as Array:
		if not state_value is Dictionary:
			return false
		var state := state_value as Dictionary
		if (
			not _has_exact_fields(state, ["target_id", "erosion_stacks"])
			or typeof(state.get("target_id")) != TYPE_INT
			or typeof(state.get("erosion_stacks")) != TYPE_INT
			or int(state["target_id"]) <= previous
			or int(state.get("erosion_stacks", -1)) < 0
		):
			return false
		previous = int(state["target_id"])
	return true


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item: Variant in value as Array:
			if item is Dictionary:
				result.append(item as Dictionary)
	return result


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


func _stable_target_id(target: Node) -> int:
	if target.has_meta("stable_target_id"):
		return int(target.get_meta("stable_target_id"))
	if target.has_meta("encounter_spawn_id"):
		return maxi(1, str(target.get_meta("encounter_spawn_id")).hash())
	return target.get_instance_id()


func _target_by_stable_id(target_id: int) -> Node:
	if target_id <= 0 or not is_inside_tree():
		return null
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if candidate != null and is_instance_valid(candidate) and _stable_target_id(candidate) == target_id:
			return candidate
	return null


func _spawn_projectile(descriptor: Dictionary, definition: Dictionary) -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false
	var prepared := _prepare_projectile(descriptor, definition)
	if prepared.is_empty():
		return false
	_attach_prepared_projectile(prepared, current_scene)
	return true


func _prepare_projectile(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	var parameters: Dictionary = descriptor["parameters"]
	var direction_value: Variant = parameters.get("direction", definition.get("aim_direction", Vector2.RIGHT))
	if not direction_value is Vector2 or (direction_value as Vector2).length_squared() <= 0.001:
		return {}
	var direction := (direction_value as Vector2).normalized()
	var arrow := ArrowScene.instantiate()
	var spawn_position := global_position + direction * 28.0
	if parameters.get("spawn_position") is Vector2:
		spawn_position = parameters["spawn_position"]
	arrow.global_position = spawn_position
	arrow.direction = direction
	arrow.source = self
	arrow.owner_entity = owner_player
	var frozen_base_attack := float(definition.get("_execution_base_attack", base_attack))
	var execution := {
		"action_token": int(definition["token"]),
		"source_action_id": str(definition["action_id"]),
		"descriptor_id": str(descriptor["descriptor_id"]),
		"outcome_index": int(descriptor["outcome_index"]),
		"deterministic_seed": int(descriptor["seed"]),
		"damage": _projectile_damage(parameters, frozen_base_attack),
		"base_attack": frozen_base_attack,
		"speed": _projectile_speed(parameters),
		"max_range_pixels": _projectile_range(parameters),
		"pierce": int(parameters.get("pierce", 0)),
		"pierce_mode": str(parameters.get("pierce_mode", "limited")),
		"full_charge": bool(parameters.get("full_charge", false)),
		"time_energy_restore": float(parameters.get("time_energy_restore", 0.0)),
		"energy_reward_once_per_action": bool(parameters.get("energy_reward_once_per_action", false)),
		"time_damage_ratio": clampf(float(parameters.get("time_damage_ratio", 0.0)), 0.0, 1.0),
		"trail": _dictionary_copy(parameters.get("trail", {})),
		"first_hit_control": _dictionary_copy(parameters.get("first_hit_control", {})),
		"time_interactions": _time_interactions_for_projectile(definition),
		"boss_conversion": _dictionary_copy(definition.get("boss_conversion", {})),
		"interaction_claims": _profile_action_shared_claims,
		"tags": _projectile_tags(parameters, definition),
	}
	if not bool(arrow.call("configure_execution", execution)):
		arrow.free()
		return {}
	return {"node": arrow, "global_position": spawn_position}


func _attach_prepared_projectile(prepared: Dictionary, parent: Node) -> void:
	var arrow: Node2D = prepared["node"]
	parent.add_child(arrow)
	arrow.global_position = prepared["global_position"]


func _free_prepared_projectiles(prepared_projectiles: Array[Dictionary]) -> void:
	for prepared: Dictionary in prepared_projectiles:
		var arrow_value: Variant = prepared.get("node")
		if is_instance_valid(arrow_value) and arrow_value is Node:
			(arrow_value as Node).free()
	prepared_projectiles.clear()


func _non_projectile_can_execute(descriptor: Dictionary) -> bool:
	match str(descriptor["kind"]):
		"movement":
			return owner_player is CharacterBody2D
		"zone_schedule":
			return _starfall_schedule.is_empty()
	return false


func _execute_movement(descriptor: Dictionary) -> bool:
	if not owner_player is CharacterBody2D:
		return false
	var parameters: Dictionary = descriptor["parameters"]
	if (
		str(parameters.get("collision_mode", "")) != "swept"
		or bool(parameters.get("invulnerable", true))
	):
		return false
	var direction_value: Variant = parameters.get("direction")
	if not direction_value is Vector2 or (direction_value as Vector2).length_squared() <= 0.001:
		return false
	var distance := float(parameters.get("distance_pixels", 0.0))
	if not is_equal_approx(distance, 96.0):
		return false
	(owner_player as CharacterBody2D).move_and_collide((direction_value as Vector2).normalized() * distance)
	return true


func _start_starfall_schedule(descriptor: Dictionary, definition: Dictionary) -> bool:
	if not _starfall_schedule.is_empty():
		return false
	var parameters: Dictionary = descriptor["parameters"]
	_starfall_schedule = {
		"descriptor": descriptor.duplicate(true),
		"definition": definition.duplicate(true),
		"next_wave_index": 0,
		"frames_until_next": 0,
		"wave_count": int(parameters["wave_count"]),
		"wave_interval_frames": int(parameters["wave_interval_frames"]),
	}
	_starfall_source_id = StringName("bow_starfall_%d_%d" % [
		int(definition["token"]),
		int(descriptor["outcome_index"]),
	])
	_starfall_elapsed_frames = 0
	_apply_starfall_invulnerability(parameters)
	_refresh_starfall_targets()
	if not _release_next_starfall_wave():
		_clear_starfall_schedule()
		return false
	return true


func _advance_starfall_schedule(frames: int) -> void:
	if frames <= 0 or _starfall_schedule.is_empty():
		return
	for _frame: int in range(frames):
		if _starfall_schedule.is_empty():
			return
		_starfall_elapsed_frames += 1
		_refresh_starfall_targets()
		_advance_starfall_erosion()
		var remaining := int(_starfall_schedule["frames_until_next"])
		if remaining > 0:
			_starfall_schedule["frames_until_next"] = remaining - 1
		if int(_starfall_schedule["frames_until_next"]) <= 0:
			if not _release_next_starfall_wave():
				_clear_starfall_schedule()


func _release_next_starfall_wave() -> bool:
	if _starfall_schedule.is_empty():
		return false
	var wave_index := int(_starfall_schedule["next_wave_index"])
	var wave_count := int(_starfall_schedule["wave_count"])
	if wave_index >= wave_count:
		_clear_starfall_schedule()
		return true
	var descriptor: Dictionary = _starfall_schedule["descriptor"]
	var definition: Dictionary = _starfall_schedule["definition"]
	var parameters: Dictionary = descriptor["parameters"]
	var scheduled_arrows: Array = parameters["arrows"]
	var target_point: Vector2 = definition["target_point"]
	for arrow_value: Variant in scheduled_arrows:
		var arrow_definition: Dictionary = arrow_value
		if int(arrow_definition["wave_index"]) != wave_index:
			continue
		var offset := _starfall_offset(
			int(arrow_definition["seed"]),
			float(arrow_definition.get("maximum_offset_cells", 1.5)) * PIXELS_PER_CELL
		)
		var arrow_descriptor := {
			"descriptor_id": str(descriptor["descriptor_id"]),
			"kind": "projectile",
			"outcome_index": int(arrow_definition["outcome_index"]),
			"seed": int(arrow_definition["seed"]),
			"parameters": {
				"direction": Vector2.DOWN,
				"spawn_position": target_point + offset + Vector2.UP * 128.0,
				"damage_multiplier": float(parameters.get("arrow_damage_multiplier", 1.2)),
				"resolved_damage_multiplier": float(parameters.get(
					"resolved_arrow_damage_multiplier",
					parameters.get("arrow_damage_multiplier", 1.2)
				)),
				"time_damage_ratio": float(parameters.get("time_damage_ratio", 0.6)),
				"speed_cells_per_second": float(parameters.get("fall_speed_cells_per_second", 24.0)),
				"range_pixels": 256.0,
				"tags": ["weapon:bow", "attack:starfall", "target_deduplication:per_projectile"],
			},
		}
		if not _spawn_projectile(arrow_descriptor, definition):
			return false
	_starfall_schedule["next_wave_index"] = wave_index + 1
	_starfall_schedule["frames_until_next"] = int(_starfall_schedule["wave_interval_frames"])
	return true


func _prepare_rewind_phantoms(definition: Dictionary) -> Dictionary:
	var interaction := _time_interaction(definition, "bow_echo_arrows")
	if interaction.is_empty():
		return {"ok": true, "claim_required": false, "descriptors": []}
	if str(definition.get("action_id", "")) == "starfall_arrow_rain":
		return {"ok": true, "claim_required": false, "descriptors": []}
	var rewind_echo_generation := int(interaction.get("rewind_echo_generation", 0))
	if rewind_echo_generation <= 0:
		return {"ok": true, "claim_required": false, "descriptors": []}
	var descriptors: Array = definition["payload_descriptors"]
	var main_descriptor: Dictionary = {}
	for descriptor_value: Variant in descriptors:
		var descriptor: Dictionary = descriptor_value
		if str(descriptor["kind"]) in ["projectile", "projectile_trail"]:
			main_descriptor = descriptor
			break
	if main_descriptor.is_empty():
		return {"ok": false}
	var main_parameters: Dictionary = main_descriptor["parameters"]
	var main_direction: Vector2 = definition["aim_direction"]
	var count := int(interaction.get("phantom_count", 3))
	var multiplier := float(interaction.get("damage_multiplier", 0.5))
	if count <= 0 or count > 16 or not is_finite(multiplier) or multiplier <= 0.0:
		return {"ok": false}
	var phantom_descriptors_value: Variant = interaction.get("phantom_descriptors", [])
	var phantom_descriptors: Array = phantom_descriptors_value if phantom_descriptors_value is Array else []
	var angle_offsets_value: Variant = interaction.get("angle_offsets_degrees", [-15.0, 0.0, 15.0])
	var angle_offsets: Array = angle_offsets_value if angle_offsets_value is Array else [-15.0, 0.0, 15.0]
	var prepared: Array[Dictionary] = []
	var used_outcomes: Dictionary = {}
	var maximum_main_outcome := -1
	for descriptor_value: Variant in descriptors:
		var descriptor: Dictionary = descriptor_value
		var outcome := int(descriptor["outcome_index"])
		used_outcomes[outcome] = true
		maximum_main_outcome = maxi(maximum_main_outcome, outcome)
	for index: int in range(count):
		var frozen_phantom: Dictionary = (
			phantom_descriptors[index]
			if index < phantom_descriptors.size() and phantom_descriptors[index] is Dictionary
			else {}
		)
		var angle_offset := float(frozen_phantom.get(
			"angle_offset_degrees",
			angle_offsets[index] if index < angle_offsets.size() else 0.0
		))
		var phantom_parameters := main_parameters.duplicate(true)
		phantom_parameters["direction"] = main_direction.rotated(deg_to_rad(angle_offset))
		for damage_field: String in ["damage", "damage_multiplier", "resolved_damage_multiplier"]:
			if phantom_parameters.has(damage_field):
				phantom_parameters[damage_field] = float(phantom_parameters[damage_field]) * multiplier
		var trail := _dictionary_copy(phantom_parameters.get("trail", {}))
		if trail.has("tick_damage_multiplier"):
			trail["tick_damage_multiplier"] = float(trail["tick_damage_multiplier"]) * multiplier
			phantom_parameters["trail"] = trail
		phantom_parameters["time_damage_ratio"] = 1.0
		phantom_parameters["time_energy_restore"] = 0.0
		phantom_parameters["energy_reward_once_per_action"] = false
		phantom_parameters["tags"] = [
			"weapon:bow",
			"time:rewind_phantom",
			"non_recursive:time_interaction",
		]
		var phantom_outcome := int(frozen_phantom.get(
			"outcome_index",
			maximum_main_outcome + index + 1
		))
		if phantom_outcome <= maximum_main_outcome or used_outcomes.has(phantom_outcome):
			return {"ok": false}
		used_outcomes[phantom_outcome] = true
		var phantom_descriptor := {
			"descriptor_id": "%s_rewind" % str(main_descriptor["descriptor_id"]),
			"kind": "projectile",
			"outcome_index": phantom_outcome,
			"seed": int(frozen_phantom.get("seed", _fallback_seed(int(definition["token"]), index))),
			"parameters": phantom_parameters,
		}
		if not _payload_descriptor_is_valid(phantom_descriptor):
			return {"ok": false}
		prepared.append(phantom_descriptor)
	return {
		"ok": true,
		"claim_required": true,
		"generation": rewind_echo_generation,
		"descriptors": prepared,
	}


func _claim_rewind_generation(generation: int) -> bool:
	return (
		owner_player != null
		and owner_player.has_method("claim_weapon_time_interaction")
		and bool(owner_player.call("claim_weapon_time_interaction", &"bow_rewind_echo", generation))
	)


func _time_interactions_for_projectile(definition: Dictionary) -> Array:
	var result: Array = []
	var interactions_value: Variant = definition.get("time_interactions", [])
	if not interactions_value is Array:
		return result
	for interaction_value: Variant in interactions_value:
		if interaction_value is Dictionary:
			result.append((interaction_value as Dictionary).duplicate(true))
	return result


func _time_interaction(definition: Dictionary, effect: String) -> Dictionary:
	for interaction_value: Variant in _time_interactions_for_projectile(definition):
		var interaction: Dictionary = interaction_value
		if (
			str(interaction.get("interaction_id", "")) == effect
			or str(interaction.get("effect", "")) == effect
		):
			return interaction.duplicate(true)
	return {}


func _projectile_damage(parameters: Dictionary, frozen_base_attack: float) -> float:
	if parameters.has("damage"):
		return float(parameters["damage"])
	return frozen_base_attack * float(parameters.get(
		"resolved_damage_multiplier",
		parameters.get("damage_multiplier", 1.0)
	))


func _projectile_speed(parameters: Dictionary) -> float:
	if parameters.has("speed_pixels_per_second"):
		return float(parameters["speed_pixels_per_second"])
	return float(parameters.get("speed_cells_per_second", 1.0)) * PIXELS_PER_CELL


func _projectile_range(parameters: Dictionary) -> float:
	if parameters.has("range_pixels"):
		return float(parameters["range_pixels"])
	if parameters.has("range_cells"):
		return float(parameters["range_cells"]) * PIXELS_PER_CELL
	return 0.0


func _projectile_tags(parameters: Dictionary, definition: Dictionary) -> Array[String]:
	var result: Array[String] = ["weapon:bow", "action:%s" % str(definition["action_id"])]
	var tags_value: Variant = parameters.get("tags", [])
	if tags_value is Array:
		for tag_value: Variant in tags_value:
			var tag := str(tag_value)
			if not tag.is_empty() and not result.has(tag):
				result.append(tag)
	for interaction_value: Variant in _time_interactions_for_projectile(definition):
		var interaction: Dictionary = interaction_value
		match str(interaction.get("interaction_id", interaction.get("id", ""))):
			"stop", "bow_stopped_target_burst":
				result.append("time:stop_interaction")
			"accelerate", "bow_charge_speed":
				result.append("time:accelerate_interaction")
			"rift", "bow_rift_penetration":
				result.append("time:rift_interaction")
	return result


func _apply_starfall_invulnerability(parameters: Dictionary) -> void:
	if owner_player == null or not bool(parameters.get("invulnerable", false)):
		return
	var fallback_frames := int(parameters.get("wave_count", 10)) * int(parameters.get("wave_interval_frames", 9))
	var frames := int(parameters.get("invulnerability_frames", fallback_frames))
	if frames <= 0:
		return
	var health := owner_player.get_node_or_null("HealthComponent")
	if health == null or not health.has_method("acquire_invulnerability_source"):
		return
	var source_id := StringName("%s_invulnerability" % str(_starfall_source_id))
	if bool(health.call("acquire_invulnerability_source", source_id)):
		_starfall_invulnerability_health = health
		_starfall_invulnerability_source_id = source_id


func _clear_starfall_invulnerability() -> void:
	if (
		_starfall_invulnerability_source_id != &""
		and is_instance_valid(_starfall_invulnerability_health)
		and _starfall_invulnerability_health.has_method("release_invulnerability_source")
	):
		_starfall_invulnerability_health.call(
			"release_invulnerability_source",
			_starfall_invulnerability_source_id
		)
	_starfall_invulnerability_health = null
	_starfall_invulnerability_source_id = &""


func _refresh_starfall_targets() -> void:
	if _starfall_schedule.is_empty() or not is_inside_tree():
		return
	var descriptor: Dictionary = _starfall_schedule["descriptor"]
	var definition: Dictionary = _starfall_schedule["definition"]
	var parameters: Dictionary = descriptor["parameters"]
	var center: Vector2 = definition["target_point"]
	var radius := float(parameters.get("radius_cells", 0.0)) * PIXELS_PER_CELL
	var slow_ratio := clampf(float(parameters.get("slow_ratio", 0.0)), 0.0, 0.9)
	var active: Dictionary = {}
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if (
			not is_instance_valid(enemy)
			or not enemy is Node2D
			or (enemy as Node2D).global_position.distance_to(center) > radius
		):
			continue
		var enemy_id := enemy.get_instance_id()
		active[enemy_id] = enemy
		if not _starfall_targets.has(enemy_id):
			_starfall_targets[enemy_id] = {"target": enemy, "erosion_stacks": 0}
			if slow_ratio > 0.0 and enemy.has_method("apply_time_rift"):
				enemy.call("apply_time_rift", _starfall_source_id, 1.0 - slow_ratio)
	for enemy_id: Variant in _starfall_targets.keys():
		if not active.has(enemy_id):
			_clear_starfall_target(int(enemy_id))


func _advance_starfall_erosion() -> void:
	if _starfall_schedule.is_empty():
		return
	var parameters: Dictionary = (_starfall_schedule["descriptor"] as Dictionary)["parameters"]
	var erosion_value: Variant = parameters.get("time_erosion", {})
	if not erosion_value is Dictionary:
		return
	var erosion: Dictionary = erosion_value
	var interval := int(erosion.get("stack_interval_frames", 0))
	var maximum := int(erosion.get("maximum_stacks", 0))
	var per_stack := _starfall_time_damage_per_stack(parameters)
	if interval <= 0 or maximum <= 0 or _starfall_elapsed_frames % interval != 0:
		return
	for enemy_id: Variant in _starfall_targets.keys():
		var state: Dictionary = _starfall_targets[enemy_id]
		var target_value: Variant = state.get("target")
		if not is_instance_valid(target_value) or not target_value is Node:
			_clear_starfall_target(int(enemy_id))
			continue
		state["erosion_stacks"] = mini(maximum, int(state.get("erosion_stacks", 0)) + 1)
		_starfall_targets[enemy_id] = state
		_set_starfall_erosion_meta(target_value, int(state["erosion_stacks"]), per_stack)


func _set_starfall_erosion_meta(target: Node, stacks: int, per_stack: float) -> void:
	var sources_value: Variant = target.get_meta("bow_time_erosion_sources", {})
	var sources: Dictionary = (sources_value as Dictionary).duplicate(true) if sources_value is Dictionary else {}
	sources[str(_starfall_source_id)] = {
		"stacks": maxi(0, stacks),
		"time_damage_taken_per_stack": maxf(0.0, per_stack),
	}
	target.set_meta("bow_time_erosion_sources", sources)


func _starfall_time_damage_per_stack(parameters: Dictionary) -> float:
	var erosion_value: Variant = parameters.get("time_erosion", {})
	if not erosion_value is Dictionary:
		return 0.0
	var value: Variant = (erosion_value as Dictionary).get("time_damage_taken_per_stack", 0.0)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return 0.0
	return maxf(0.0, float(value))


func _clear_starfall_target(enemy_id: int) -> void:
	if not _starfall_targets.has(enemy_id):
		return
	var state: Dictionary = _starfall_targets[enemy_id]
	var target_value: Variant = state.get("target")
	_starfall_targets.erase(enemy_id)
	if not is_instance_valid(target_value) or not target_value is Node:
		return
	var target: Node = target_value
	if target.has_method("clear_time_rift"):
		target.call("clear_time_rift", _starfall_source_id)
	var sources_value: Variant = target.get_meta("bow_time_erosion_sources", {})
	if sources_value is Dictionary:
		var sources: Dictionary = (sources_value as Dictionary).duplicate(true)
		sources.erase(str(_starfall_source_id))
		if sources.is_empty():
			target.remove_meta("bow_time_erosion_sources")
		else:
			target.set_meta("bow_time_erosion_sources", sources)


func _clear_starfall_schedule() -> void:
	_clear_starfall_invulnerability()
	for enemy_id: Variant in _starfall_targets.keys():
		_clear_starfall_target(int(enemy_id))
	_starfall_targets.clear()
	_starfall_schedule.clear()
	_starfall_source_id = &""
	_starfall_elapsed_frames = 0


func _clear_spawned_projectiles() -> void:
	if not is_inside_tree():
		return
	for arrow: Node in get_tree().get_nodes_in_group("player_arrows"):
		if (
			is_instance_valid(arrow)
			and not arrow.is_queued_for_deletion()
			and arrow.get("source") == self
		):
			arrow.queue_free()


func _clear_projectiles_for_action_token(action_token: int) -> void:
	if not is_inside_tree():
		return
	for arrow: Node in get_tree().get_nodes_in_group("player_arrows"):
		if (
			is_instance_valid(arrow)
			and not arrow.is_queued_for_deletion()
			and arrow.get("source") == self
			and int(arrow.get("action_token")) == action_token
		):
			arrow.queue_free()


func _launch_definition_is_valid(definition: Dictionary) -> bool:
	for field: String in [
		"token",
		"profile_id",
		"weapon_id",
		"action_id",
		"semantic_action",
		"aim_direction",
		"target_point",
		"payload_descriptors",
		"time_interactions",
		"boss_conversion",
	]:
		if not definition.has(field):
			return false
	if typeof(definition["token"]) != TYPE_INT or int(definition["token"]) <= 0:
		return false
	if str(definition["profile_id"]) != LAUNCH_PROFILE_ID or str(definition["weapon_id"]) != "bow":
		return false
	if str(definition["action_id"]) not in LAUNCH_ACTION_IDS:
		return false
	if not definition["aim_direction"] is Vector2 or not definition["target_point"] is Vector2:
		return false
	if (definition["aim_direction"] as Vector2).length_squared() <= 0.001:
		return false
	if not definition["payload_descriptors"] is Array or (definition["payload_descriptors"] as Array).is_empty():
		return false
	if not definition["time_interactions"] is Array or not definition["boss_conversion"] is Dictionary:
		return false
	for descriptor_value: Variant in definition["payload_descriptors"]:
		if not descriptor_value is Dictionary or not _payload_descriptor_is_valid(descriptor_value):
			return false
	return true


func _payload_descriptor_is_valid(descriptor: Dictionary) -> bool:
	for field: String in ["descriptor_id", "kind", "outcome_index", "seed", "parameters"]:
		if not descriptor.has(field):
			return false
	if str(descriptor["descriptor_id"]).is_empty():
		return false
	if typeof(descriptor["outcome_index"]) != TYPE_INT or int(descriptor["outcome_index"]) < 0:
		return false
	if typeof(descriptor["seed"]) != TYPE_INT or not descriptor["parameters"] is Dictionary:
		return false
	var parameters: Dictionary = descriptor["parameters"]
	match str(descriptor["kind"]):
		"projectile", "projectile_trail":
			var direction_value: Variant = parameters.get("direction")
			if not direction_value is Vector2 or (direction_value as Vector2).length_squared() <= 0.001:
				return false
			if not _positive_number(parameters.get("damage", parameters.get("damage_multiplier", 0.0))):
				return false
			if not _positive_number(parameters.get("speed_pixels_per_second", parameters.get("speed_cells_per_second", 0.0))):
				return false
			return true
		"movement":
			return (
				parameters.get("direction") is Vector2
				and (parameters["direction"] as Vector2).length_squared() > 0.001
				and is_equal_approx(float(parameters.get("distance_pixels", 0.0)), 96.0)
				and str(parameters.get("collision_mode", "")) == "swept"
				and typeof(parameters.get("invulnerable")) == TYPE_BOOL
				and not bool(parameters["invulnerable"])
			)
		"zone_schedule":
			return _starfall_parameters_are_valid(parameters)
	return false


func _starfall_parameters_are_valid(parameters: Dictionary) -> bool:
	if (
		int(parameters.get("wave_count", 0)) != 10
		or int(parameters.get("wave_interval_frames", 0)) != 9
		or int(parameters.get("arrows_per_wave", 0)) != 3
		or not parameters.get("arrows") is Array
	):
		return false
	var arrows: Array = parameters["arrows"]
	if arrows.size() != 30:
		return false
	var wave_counts: Dictionary = {}
	for arrow_value: Variant in arrows:
		if not arrow_value is Dictionary:
			return false
		var arrow: Dictionary = arrow_value
		if (
			typeof(arrow.get("wave_index")) != TYPE_INT
			or int(arrow["wave_index"]) < 0
			or int(arrow["wave_index"]) >= 10
			or typeof(arrow.get("arrow_index")) != TYPE_INT
			or int(arrow["arrow_index"]) < 0
			or int(arrow["arrow_index"]) >= 3
			or typeof(arrow.get("outcome_index")) != TYPE_INT
			or typeof(arrow.get("seed")) != TYPE_INT
			or not _positive_number(arrow.get("maximum_offset_cells", 0.0))
		):
			return false
		var wave_index := int(arrow["wave_index"])
		wave_counts[wave_index] = int(wave_counts.get(wave_index, 0)) + 1
	for wave_index: int in range(10):
		if int(wave_counts.get(wave_index, 0)) != 3:
			return false
	return true


func _dictionary_copy(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _fallback_seed(token: int, index: int) -> int:
	var mixed := token * 1_103_515_245 + (index + 1) * 12_345
	return absi(mixed) & 0x7fffffff


func _starfall_offset(seed: int, maximum_radius_pixels: float) -> Vector2:
	var random := RandomNumberGenerator.new()
	random.seed = seed
	var angle := random.randf_range(0.0, TAU)
	var radius := sqrt(random.randf()) * maximum_radius_pixels
	return Vector2.RIGHT.rotated(angle) * radius


func _positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


func _profile_definition_is_valid(definition: Dictionary) -> bool:
	for field: String in [
		"token",
		"direction",
		"damage",
		"speed",
		"pierce",
		"full_charge",
		"time_energy_restore",
		"energy_reward_once_per_action",
		"tags",
		"source_action_id",
	]:
		if not definition.has(field):
			return false
	if typeof(definition["token"]) != TYPE_INT or int(definition["token"]) <= 0:
		return false
	if not definition["direction"] is Vector2:
		return false
	if not _finite_non_negative(definition["damage"]) or float(definition["damage"]) <= 0.0:
		return false
	if not _finite_non_negative(definition["speed"]) or float(definition["speed"]) <= 0.0:
		return false
	if typeof(definition["pierce"]) != TYPE_INT or int(definition["pierce"]) < 0:
		return false
	if typeof(definition["full_charge"]) != TYPE_BOOL:
		return false
	if not _finite_non_negative(definition["time_energy_restore"]):
		return false
	if typeof(definition["energy_reward_once_per_action"]) != TYPE_BOOL:
		return false
	if not definition["tags"] is Array or str(definition["source_action_id"]).is_empty():
		return false
	return true


func _finite_non_negative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0
