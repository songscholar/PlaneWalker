class_name GunWeapon
extends Node2D

signal projectile_hit_confirmed(action_token: int, outcome_index: int, target: Node)
signal action_hit_confirmed(action_token: int, target: Node)
signal resource_reward_requested(action_token: int, reward_id: StringName, amount: float)

const GunProjectileScene := preload("res://scenes/combat/gun_projectile.tscn")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const WEAPON_ID := &"gun"
const PIXELS_PER_TILE := 64.0
const RUNTIME_SNAPSHOT_SCHEMA_VERSION := 1
const PROFILE_ID := "gun_launch_v1"
const REWIND_WINDOW_INTERACTION_ID := &"bow_rewind_echo"
const VALID_ACTION_IDS: Array[String] = [
	"normal_fire",
	"aimed_fire",
	"shotgun_fire",
	"reload",
	"time_load",
	"void_penetration",
]
const PROJECTILE_KINDS: Array[String] = ["projectile", "projectile_trail"]
const PASSIVE_KINDS: Array[String] = ["resource_action", "buff"]

@export var owner_path: NodePath
@export var base_attack: float = 15.0
@export var attack_speed: float = 0.9

var _profile_action: Dictionary = {}
var _profile_action_released: bool = false
var _profile_action_shared_claims: Dictionary = {}
var _prepared_projectiles: Array[Dictionary] = []
var _owned_projectiles: Array[Node] = []
var _invulnerability_health: Node
var _invulnerability_source_id: StringName = &""


func weapon_id() -> StringName:
	return WEAPON_ID


func begin_profile_action(definition: Dictionary) -> Dictionary:
	if is_profile_action_active() or not _definition_is_valid(definition):
		return {}
	_profile_action_shared_claims = {}
	var rewind_generation := _rewind_generation(definition)
	if rewind_generation < 0:
		return {}
	var prepared: Array[Dictionary] = []
	for descriptor_value: Variant in definition["payload_descriptors"]:
		var descriptor := descriptor_value as Dictionary
		var kind := str(descriptor.get("kind", ""))
		if kind in PROJECTILE_KINDS:
			var projectile := _prepare_projectile(descriptor, definition)
			if projectile.is_empty():
				_free_prepared(prepared)
				_profile_action_shared_claims.clear()
				return {}
			prepared.append(projectile)
		elif kind not in PASSIVE_KINDS:
			_free_prepared(prepared)
			_profile_action_shared_claims.clear()
			return {}
	if bool(definition.get("invulnerable_during_cast", false)):
		if not _acquire_cast_invulnerability(int(definition["token"])):
			_free_prepared(prepared)
			_profile_action_shared_claims.clear()
			return {}
	if rewind_generation > 0 and not _claim_rewind_generation(rewind_generation):
		_free_prepared(prepared)
		_release_cast_invulnerability()
		_profile_action_shared_claims.clear()
		return {}
	_profile_action = definition.duplicate(true)
	_prepared_projectiles = prepared
	_profile_action_released = false
	return definition.duplicate(true)


func release_profile_action() -> bool:
	if _profile_action.is_empty() or _profile_action_released:
		return false
	var current_scene := get_tree().current_scene
	if not _prepared_projectiles.is_empty() and current_scene == null:
		return false
	for prepared: Dictionary in _prepared_projectiles:
		var node_value: Variant = prepared.get("node")
		if not is_instance_valid(node_value) or not node_value is Node2D:
			return false
	for prepared: Dictionary in _prepared_projectiles:
		var projectile := prepared["node"] as Node2D
		current_scene.add_child(projectile)
		projectile.global_position = prepared["global_position"]
		_owned_projectiles.append(projectile)
	_prepared_projectiles.clear()
	_profile_action_released = true
	return true


func is_profile_action_active() -> bool:
	return not _profile_action.is_empty()


func cancel_profile_action() -> void:
	var token := int(_profile_action.get("token", 0))
	_free_prepared(_prepared_projectiles)
	if token > 0:
		_clear_projectiles_for_token(token)
	_clear_profile_action()


func cancel_for_gameplay_rewind() -> bool:
	var guard := gameplay_rewind_committed_payload_guard()
	_free_prepared(_prepared_projectiles)
	_prepared_projectiles.clear()
	_clear_profile_action()
	return gameplay_rewind_committed_payload_guard() == guard


func gameplay_rewind_snapshot() -> Dictionary:
	var full := runtime_snapshot()
	if full.is_empty():
		return {}
	return {
		"profile_action": (full["profile_action"] as Dictionary).duplicate(true),
		"profile_action_released": bool(full["profile_action_released"]),
		"prepared_projectiles": (full["prepared_projectiles"] as Array).duplicate(true),
		"action_claims_by_token": (full["action_claims_by_token"] as Dictionary).duplicate(true),
		"committed_payload_guard": gameplay_rewind_committed_payload_guard(),
	}


func restore_gameplay_rewind_snapshot_for_rollback(value: Dictionary) -> bool:
	if (
		not value.get("profile_action") is Dictionary
		or typeof(value.get("profile_action_released")) != TYPE_BOOL
		or not value.get("prepared_projectiles") is Array
		or not value.get("action_claims_by_token") is Dictionary
		or not value.get("committed_payload_guard") is Dictionary
		or value["committed_payload_guard"] != gameplay_rewind_committed_payload_guard()
	):
		return false
	var target_full := runtime_snapshot()
	if target_full.is_empty():
		return false
	target_full["profile_action"] = (value["profile_action"] as Dictionary).duplicate(true)
	target_full["profile_action_released"] = bool(value["profile_action_released"])
	target_full["phase_state"] = (
		"idle"
		if (value["profile_action"] as Dictionary).is_empty()
		else ("released" if bool(value["profile_action_released"]) else "prepared")
	)
	target_full["prepared_projectiles"] = (value["prepared_projectiles"] as Array).duplicate(true)
	target_full["action_claims_by_token"] = (value["action_claims_by_token"] as Dictionary).duplicate(true)
	if not _runtime_snapshot_shape_is_valid(target_full):
		return false
	var claims := _duplicate_claims_by_token(value["action_claims_by_token"] as Dictionary)
	var staged: Array[Dictionary] = []
	for payload_value: Variant in value["prepared_projectiles"] as Array:
		var prepared := _stage_projectile_snapshot(payload_value, claims, false)
		if prepared.is_empty():
			_free_prepared(staged)
			return false
		staged.append(prepared)
	var action := value["profile_action"] as Dictionary
	if (
		not action.is_empty()
		and bool(action.get("invulnerable_during_cast", false))
		and not _acquire_cast_invulnerability(int(action.get("token", 0)))
	):
		_free_prepared(staged)
		return false
	_free_prepared(_prepared_projectiles)
	_prepared_projectiles = staged
	_profile_action = action.duplicate(true)
	_profile_action_released = bool(value["profile_action_released"])
	_profile_action_shared_claims = claims.get(str(int(action.get("token", 0))), {})
	return gameplay_rewind_snapshot() == value


func gameplay_rewind_committed_payload_guard() -> Dictionary:
	_prune_owned_projectiles()
	var instance_ids: Array[int] = []
	var payloads: Array[Dictionary] = []
	var claims_by_token: Dictionary = {}
	for projectile: Node in _owned_projectiles:
		var payload := _owned_projectile_runtime_snapshot(projectile)
		if payload.is_empty() or not _merge_action_claims_snapshot(claims_by_token, payload):
			return {}
		instance_ids.append(projectile.get_instance_id())
		payloads.append(payload)
	return {
		"instance_ids": instance_ids,
		"owned_projectiles": payloads,
		"action_claims_by_token": claims_by_token,
	}


func finish_profile_action() -> void:
	_free_prepared(_prepared_projectiles)
	_clear_profile_action()


func reset_runtime_state() -> void:
	cancel_profile_action()
	_clear_owned_projectiles()
	_release_cast_invulnerability()


func prepared_projectile_snapshots_for_test() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for prepared: Dictionary in _prepared_projectiles:
		var node_value: Variant = prepared.get("node")
		if is_instance_valid(node_value) and node_value.has_method("execution_snapshot"):
			result.append((node_value.call("execution_snapshot") as Dictionary).duplicate(true))
	return result


func prepared_projectile_count_for_test() -> int:
	return _prepared_projectiles.size()


func owned_projectile_count_for_test() -> int:
	_prune_owned_projectiles()
	return _owned_projectiles.size()


func owned_projectiles_for_test() -> Array[Node]:
	_prune_owned_projectiles()
	return _owned_projectiles.duplicate()


func runtime_snapshot() -> Dictionary:
	_prune_owned_projectiles()
	var prepared_projectiles: Array[Dictionary] = []
	var owned_projectiles: Array[Dictionary] = []
	var claims_by_token: Dictionary = {}
	if not _profile_action.is_empty():
		claims_by_token[str(int(_profile_action.get("token", 0)))] = _profile_action_shared_claims.duplicate(true)
	for prepared: Dictionary in _prepared_projectiles:
		var snapshot := _prepared_projectile_runtime_snapshot(prepared)
		if snapshot.is_empty() or not _merge_action_claims_snapshot(claims_by_token, snapshot):
			return {}
		prepared_projectiles.append(snapshot)
	for projectile: Node in _owned_projectiles:
		var snapshot := _owned_projectile_runtime_snapshot(projectile)
		if snapshot.is_empty() or not _merge_action_claims_snapshot(claims_by_token, snapshot):
			return {}
		owned_projectiles.append(snapshot)
	return {
		"schema_version": RUNTIME_SNAPSHOT_SCHEMA_VERSION,
		"profile_action": _profile_action.duplicate(true),
		"profile_action_released": _profile_action_released,
		"phase_state": (
			"idle"
			if _profile_action.is_empty()
			else ("released" if _profile_action_released else "prepared")
		),
		"prepared_projectiles": prepared_projectiles,
		"owned_projectiles": owned_projectiles,
		"action_claims_by_token": claims_by_token,
	}


func can_restore_runtime_snapshot(value: Dictionary) -> bool:
	var staged := _stage_runtime_snapshot(value)
	if not bool(staged.get("ok", false)):
		return false
	_free_staged_runtime_projectiles(staged)
	return true


func restore_runtime_snapshot(value: Dictionary) -> bool:
	var target_staged := _stage_runtime_snapshot(value)
	if not bool(target_staged.get("ok", false)):
		return false
	var current := runtime_snapshot()
	if current.is_empty():
		_free_staged_runtime_projectiles(target_staged)
		return false
	if current == value:
		_free_staged_runtime_projectiles(target_staged)
		return true
	var rollback_staged := _stage_runtime_snapshot(current)
	if not bool(rollback_staged.get("ok", false)):
		_free_staged_runtime_projectiles(target_staged)
		return false
	if _install_staged_runtime_snapshot(value, target_staged) and runtime_snapshot() == value:
		_free_staged_runtime_projectiles(rollback_staged)
		return true
	_discard_current_runtime_projectiles()
	if _install_staged_runtime_snapshot(current, rollback_staged) and runtime_snapshot() == current:
		return false
	_free_staged_runtime_projectiles(rollback_staged)
	reset_runtime_state()
	return false


func _prepared_projectile_runtime_snapshot(prepared: Dictionary) -> Dictionary:
	var node_value: Variant = prepared.get("node")
	var position_value: Variant = prepared.get("global_position")
	if (
		not node_value is Node2D
		or not is_instance_valid(node_value)
		or not position_value is Vector2
		or not (node_value as Node).has_method("execution_snapshot")
	):
		return {}
	return _projectile_runtime_snapshot(node_value as Node2D, position_value as Vector2)


func _owned_projectile_runtime_snapshot(projectile: Node) -> Dictionary:
	if not projectile is Node2D or not is_instance_valid(projectile) or not projectile.has_method("execution_snapshot"):
		return {}
	return _projectile_runtime_snapshot(projectile as Node2D, (projectile as Node2D).global_position)


func _projectile_runtime_snapshot(projectile: Node2D, position: Vector2) -> Dictionary:
	var execution_value: Variant = projectile.call("execution_snapshot")
	var width := _projectile_width_pixels(projectile)
	if not execution_value is Dictionary or width <= 0.0:
		return {}
	return {
		"kind": "projectile",
		"global_position": position,
		"hit_width_pixels": width,
		"execution": (execution_value as Dictionary).duplicate(true),
	}


func _merge_action_claims_snapshot(claims_by_token: Dictionary, payload: Dictionary) -> bool:
	var execution_value: Variant = payload.get("execution")
	if not execution_value is Dictionary:
		return false
	var execution := execution_value as Dictionary
	var token := int(execution.get("action_token", 0))
	var claims_value: Variant = execution.get("action_claims")
	if token <= 0 or not claims_value is Dictionary:
		return false
	var key := str(token)
	if claims_by_token.has(key) and claims_by_token[key] != claims_value:
		return false
	claims_by_token[key] = (claims_value as Dictionary).duplicate(true)
	return true


func _stage_runtime_snapshot(value: Dictionary) -> Dictionary:
	if not _runtime_snapshot_shape_is_valid(value):
		return {"ok": false}
	var claims_by_token := _duplicate_claims_by_token(value["action_claims_by_token"] as Dictionary)
	var prepared: Array[Dictionary] = []
	var owned: Array[Dictionary] = []
	for payload_value: Variant in value["prepared_projectiles"] as Array:
		var staged_payload := _stage_projectile_snapshot(payload_value, claims_by_token, false)
		if staged_payload.is_empty():
			_free_prepared(prepared)
			return {"ok": false}
		prepared.append(staged_payload)
	for payload_value: Variant in value["owned_projectiles"] as Array:
		var staged_payload := _stage_projectile_snapshot(payload_value, claims_by_token, true)
		if staged_payload.is_empty():
			_free_prepared(prepared)
			_free_prepared(owned)
			return {"ok": false}
		owned.append(staged_payload)
	return {
		"ok": true,
		"prepared": prepared,
		"owned": owned,
		"claims_by_token": claims_by_token,
	}


func _stage_projectile_snapshot(
	value: Variant,
	claims_by_token: Dictionary,
	released: bool
) -> Dictionary:
	if not value is Dictionary:
		return {}
	var payload := value as Dictionary
	if not _has_exact_fields(payload, ["kind", "global_position", "hit_width_pixels", "execution"]):
		return {}
	var position_value: Variant = payload.get("global_position")
	var width_value: Variant = payload.get("hit_width_pixels")
	var execution_value: Variant = payload.get("execution")
	if (
		str(payload.get("kind", "")) != "projectile"
		or not position_value is Vector2
		or not _finite_vector(position_value as Vector2)
		or typeof(width_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(width_value))
		or float(width_value) <= 0.0
		or not execution_value is Dictionary
	):
		return {}
	var execution := execution_value as Dictionary
	var token := int(execution.get("action_token", 0))
	var token_key := str(token)
	if token <= 0 or not claims_by_token.has(token_key) or execution.get("action_claims") != claims_by_token[token_key]:
		return {}
	var projectile = GunProjectileScene.instantiate()
	if not projectile.has_method("restore_execution_snapshot") or not bool(projectile.call("restore_execution_snapshot", execution)):
		projectile.free()
		return {}
	projectile.call("bind_action_claims", claims_by_token[token_key])
	projectile.call("prepare_restored_tree_attachment", released)
	projectile.source = self
	projectile.owner_entity = _owner_player()
	projectile.projectile_hit_confirmed.connect(_on_projectile_hit_confirmed.bind(projectile))
	projectile.action_hit_confirmed.connect(_on_action_hit_confirmed.bind(projectile))
	projectile.resource_reward_requested.connect(_on_resource_reward_requested.bind(projectile))
	_configure_projectile_width(projectile, float(width_value) / PIXELS_PER_TILE)
	return {
		"node": projectile,
		"global_position": position_value,
	}


func _runtime_snapshot_shape_is_valid(value: Dictionary) -> bool:
	if (
		not _has_exact_fields(value, ["schema_version", "profile_action", "profile_action_released", "phase_state", "prepared_projectiles", "owned_projectiles", "action_claims_by_token"])
		or int(value.get("schema_version", -1)) != RUNTIME_SNAPSHOT_SCHEMA_VERSION
		or not value.get("profile_action") is Dictionary
		or typeof(value.get("profile_action_released")) != TYPE_BOOL
		or str(value.get("phase_state", "")) not in ["idle", "prepared", "released"]
		or not value.get("prepared_projectiles") is Array
		or not value.get("owned_projectiles") is Array
		or not _valid_claims_by_token(value.get("action_claims_by_token"))
	):
		return false
	var action := value["profile_action"] as Dictionary
	var phase_state := str(value["phase_state"])
	var released := bool(value["profile_action_released"])
	if not action.is_empty() and not _definition_is_valid(action):
		return false
	match phase_state:
		"idle":
			if not action.is_empty() or released or not (value["prepared_projectiles"] as Array).is_empty():
				return false
		"prepared":
			if action.is_empty() or released:
				return false
			if (value["prepared_projectiles"] as Array).size() != _projectile_descriptor_count(action):
				return false
		"released":
			if action.is_empty() or not released or not (value["prepared_projectiles"] as Array).is_empty():
				return false
	var claims_by_token := value["action_claims_by_token"] as Dictionary
	if not action.is_empty() and not claims_by_token.has(str(int(action.get("token", 0)))):
		return false
	var seen: Dictionary = {}
	var known_tokens: Dictionary = {}
	if not action.is_empty():
		known_tokens[str(int(action.get("token", 0)))] = true
	for collection_value: Variant in [value["prepared_projectiles"], value["owned_projectiles"]]:
		for payload_value: Variant in collection_value as Array:
			if not payload_value is Dictionary:
				return false
			var payload := payload_value as Dictionary
			var execution_value: Variant = payload.get("execution")
			if not execution_value is Dictionary:
				return false
			var execution := execution_value as Dictionary
			var token := int(execution.get("action_token", 0))
			var token_key := str(token)
			var identity := "%d:%s:%d" % [
				token,
				str(execution.get("descriptor_id", "")),
				int(execution.get("outcome_index", -1)),
			]
			if seen.has(identity) or not claims_by_token.has(token_key) or execution.get("action_claims") != claims_by_token[token_key]:
				return false
			seen[identity] = true
			known_tokens[token_key] = true
	for token_key_value: Variant in claims_by_token.keys():
		if not known_tokens.has(str(token_key_value)):
			return false
	if phase_state == "prepared" and not _prepared_projectiles_match_action(value["prepared_projectiles"] as Array, action):
		return false
	if phase_state == "released" and not _released_projectiles_match_action(value["owned_projectiles"] as Array, action):
		return false
	return true


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _prepared_projectiles_match_action(payloads: Array, action: Dictionary) -> bool:
	var descriptors := _projectile_descriptors(action)
	if payloads.size() != descriptors.size():
		return false
	for index: int in range(payloads.size()):
		var payload := payloads[index] as Dictionary
		var actual := payload.get("execution", {}) as Dictionary
		var expected_execution := _projectile_execution(
			descriptors[index] as Dictionary,
			action,
			(actual.get("direction", Vector2.RIGHT) as Vector2).normalized()
		)
		expected_execution["action_claims"] = (actual.get("action_claims", {}) as Dictionary).duplicate(true)
		var expected = GunProjectileScene.instantiate()
		if not bool(expected.call("configure_execution", expected_execution)):
			expected.free()
			return false
		expected.direction = actual.get("direction", Vector2.RIGHT)
		var expected_snapshot: Dictionary = expected.call("execution_snapshot")
		expected.free()
		if actual != expected_snapshot:
			return false
	return true


func _released_projectiles_match_action(payloads: Array, action: Dictionary) -> bool:
	var current_token := int(action.get("token", 0))
	var expected_identities: Dictionary = {}
	for descriptor: Dictionary in _projectile_descriptors(action):
		expected_identities["%s:%d" % [str(descriptor.get("descriptor_id", "")), int(descriptor.get("outcome_index", -1))]] = true
	for payload_value: Variant in payloads:
		var execution := ((payload_value as Dictionary).get("execution", {}) as Dictionary)
		if int(execution.get("action_token", 0)) != current_token:
			continue
		var identity := "%s:%d" % [str(execution.get("descriptor_id", "")), int(execution.get("outcome_index", -1))]
		if not expected_identities.has(identity):
			return false
	return true


func _projectile_descriptors(action: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for descriptor_value: Variant in action.get("payload_descriptors", []) as Array:
		if descriptor_value is Dictionary and str((descriptor_value as Dictionary).get("kind", "")) in PROJECTILE_KINDS:
			result.append(descriptor_value as Dictionary)
	return result


func _projectile_descriptor_count(action: Dictionary) -> int:
	return _projectile_descriptors(action).size()


func _valid_claims_by_token(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for token_value: Variant in (value as Dictionary).keys():
		var token_text := str(token_value)
		if not token_text.is_valid_int() or int(token_text) <= 0 or not _valid_claim_dictionary((value as Dictionary)[token_value]):
			return false
	return true


func _valid_claim_dictionary(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for claim_key: Variant in (value as Dictionary).keys():
		if typeof(claim_key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(claim_key).is_empty() or (value as Dictionary)[claim_key] != true:
			return false
	return true


func _duplicate_claims_by_token(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for token_key: Variant in value.keys():
		result[str(token_key)] = (value[token_key] as Dictionary).duplicate(true)
	return result


func _install_staged_runtime_snapshot(value: Dictionary, staged: Dictionary) -> bool:
	var owned := staged.get("owned", []) as Array
	var parent := get_tree().current_scene if is_inside_tree() else null
	if not owned.is_empty() and parent == null:
		return false
	_discard_current_runtime_projectiles()
	_profile_action = (value["profile_action"] as Dictionary).duplicate(true)
	_profile_action_released = bool(value["profile_action_released"])
	var claims_by_token := staged.get("claims_by_token", {}) as Dictionary
	var active_token_key := str(int(_profile_action.get("token", 0)))
	_profile_action_shared_claims = claims_by_token.get(active_token_key, {})
	_prepared_projectiles = _dictionary_array(staged.get("prepared", []))
	for prepared_value: Variant in owned:
		var prepared := prepared_value as Dictionary
		var projectile := prepared["node"] as Node2D
		parent.add_child(projectile)
		projectile.global_position = prepared["global_position"]
		_owned_projectiles.append(projectile)
	if not _profile_action.is_empty() and bool(_profile_action.get("invulnerable_during_cast", false)):
		if not _acquire_cast_invulnerability(int(_profile_action.get("token", 0))):
			return false
	staged["prepared"] = []
	staged["owned"] = []
	return true


func _discard_current_runtime_projectiles() -> void:
	for prepared: Dictionary in _prepared_projectiles:
		var node_value: Variant = prepared.get("node")
		if node_value is Node and is_instance_valid(node_value):
			(node_value as Node).free()
	_prepared_projectiles.clear()
	for projectile: Node in _owned_projectiles:
		if projectile != null and is_instance_valid(projectile):
			projectile.free()
	_owned_projectiles.clear()
	_clear_profile_action()


func _free_staged_runtime_projectiles(staged: Dictionary) -> void:
	var prepared_value: Variant = staged.get("prepared", [])
	if prepared_value is Array:
		_free_prepared(_dictionary_array(prepared_value))
	var owned_value: Variant = staged.get("owned", [])
	if owned_value is Array:
		_free_prepared(_dictionary_array(owned_value))
	staged["prepared"] = []
	staged["owned"] = []


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item: Variant in value as Array:
			if item is Dictionary:
				result.append(item as Dictionary)
	return result


func _projectile_width_pixels(projectile: Node2D) -> float:
	var collision := projectile.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null or not collision.shape is CircleShape2D:
		return 0.0
	return (collision.shape as CircleShape2D).radius * 2.0


func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


func profile_definition_valid_for_test(definition: Dictionary) -> bool:
	return _definition_is_valid(definition)


func projectile_execution_for_test(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	var parameters_value: Variant = descriptor.get("parameters", {})
	if not parameters_value is Dictionary:
		return {}
	var direction_value: Variant = (parameters_value as Dictionary).get("direction", definition.get("aim_direction"))
	if not direction_value is Vector2 or (direction_value as Vector2).length_squared() <= 0.001:
		return {}
	return _projectile_execution(descriptor, definition, (direction_value as Vector2).normalized())


func _prepare_projectile(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	var parameters_value: Variant = descriptor.get("parameters", {})
	if not parameters_value is Dictionary:
		return {}
	var parameters := parameters_value as Dictionary
	var direction_value: Variant = parameters.get("direction", definition.get("aim_direction"))
	if not direction_value is Vector2 or (direction_value as Vector2).length_squared() <= 0.001:
		return {}
	var direction := (direction_value as Vector2).normalized()
	var projectile = GunProjectileScene.instantiate()
	var execution := _projectile_execution(descriptor, definition, direction)
	if execution.is_empty() or not bool(projectile.call("configure_execution", execution)):
		projectile.free()
		return {}
	projectile.direction = direction
	projectile.source = self
	projectile.owner_entity = _owner_player()
	projectile.projectile_hit_confirmed.connect(_on_projectile_hit_confirmed.bind(projectile))
	projectile.action_hit_confirmed.connect(_on_action_hit_confirmed.bind(projectile))
	projectile.resource_reward_requested.connect(_on_resource_reward_requested.bind(projectile))
	_configure_projectile_width(projectile, float(parameters.get("hit_width_tiles", 0.2)))
	return {
		"node": projectile,
		"global_position": global_position + direction * 28.0,
	}


func _projectile_execution(
	descriptor: Dictionary,
	definition: Dictionary,
	direction: Vector2
) -> Dictionary:
	var parameters := (descriptor.get("parameters", {}) as Dictionary).duplicate(true)
	var action_id := str(definition.get("action_id", ""))
	var resolved_multiplier := float(parameters.get(
		"resolved_damage_multiplier",
		parameters.get("damage_multiplier", 0.0)
	))
	if not is_finite(resolved_multiplier) or resolved_multiplier <= 0.0:
		return {}
	var void_ratio := clampf(float(parameters.get("void_damage_ratio", 0.0)), 0.0, 1.0)
	var time_ratio := clampf(float(parameters.get("time_damage_ratio", 0.0)), 0.0, 1.0)
	var damage_type := DamageInfoScript.DamageType.PHYSICAL
	var damage_multiplier := resolved_multiplier
	var time_damage_multiplier := float(parameters.get("time_damage_multiplier", 0.0))
	if action_id == "void_penetration":
		if void_ratio <= 0.0 or time_ratio <= 0.0 or not is_equal_approx(void_ratio + time_ratio, 1.0):
			return {}
		damage_type = DamageInfoScript.DamageType.VOID
		damage_multiplier = resolved_multiplier * void_ratio
		time_damage_multiplier = resolved_multiplier * time_ratio
	elif time_damage_multiplier <= 0.0:
		time_damage_multiplier = float(parameters.get("time_damage_ratio", 0.0))
	var pierce_value := int(parameters.get("pierce", 0))
	var unlimited_pierce := bool(parameters.get("unlimited_pierce", false)) or pierce_value < 0
	var interactions := (definition.get("time_interactions", []) as Array).duplicate(true)
	var trail := _resolved_trail(parameters, interactions, action_id)
	var boss_conversion := (definition.get("boss_conversion", {}) as Dictionary).duplicate(true)
	if not boss_conversion.is_empty():
		boss_conversion["poise_damage"] = (
			float(definition["base_attack"])
			* float(boss_conversion.get("poise_multiplier", 1.0))
		)
	return {
		"action_token": int(definition["token"]),
		"source_action_id": action_id,
		"descriptor_id": str(descriptor["descriptor_id"]),
		"outcome_index": int(descriptor["outcome_index"]),
		"deterministic_seed": int(descriptor["seed"]),
		"damage": float(definition["base_attack"]) * damage_multiplier,
		"base_attack": float(definition["base_attack"]),
		"speed": float(parameters.get("speed_tiles_per_second", 0.0)) * PIXELS_PER_TILE,
		"max_range_pixels": float(parameters.get("maximum_range_tiles", 0.0)) * PIXELS_PER_TILE,
		"pierce": maxi(0, pierce_value),
		"pierce_mode": "unlimited" if unlimited_pierce else "limited",
		"damage_type": damage_type,
		"time_damage_ratio": time_damage_multiplier,
		"critical_chance_bonus": float(parameters.get("critical_chance_bonus", 0.0)),
		"knockback_pixels": float(parameters.get("knockback_tiles", 0.0)) * PIXELS_PER_TILE,
		"penetration_explosion": _resolved_explosion(parameters),
		"vulnerability": _resolved_vulnerability(parameters),
		"trail": trail,
		"time_interactions": interactions,
		"boss_conversion": boss_conversion,
		"resource_reward": {},
		"action_claims": _profile_action_shared_claims,
		"tags": [
			"weapon:gun",
			"action:%s" % action_id,
			"target_deduplication:%s" % str(descriptor.get("target_deduplication", "per_action_token")),
		],
	}


func _resolved_trail(parameters: Dictionary, interactions: Array, action_id: String) -> Dictionary:
	var trail_value: Variant = parameters.get("trail", {})
	var trail := (trail_value as Dictionary).duplicate(true) if trail_value is Dictionary else {}
	for interaction_value: Variant in interactions:
		if not interaction_value is Dictionary:
			continue
		var interaction := interaction_value as Dictionary
		if str(interaction.get("interaction_id", "")) != "gun_rift_trail":
			continue
		trail = {
			"duration_frames": int(interaction.get("duration_frames", 0)),
			"width_tiles": float(interaction.get("width_tiles", 0.0)),
			"tick_interval_frames": int(interaction.get("tick_interval_frames", 0)),
			"damage_multiplier": float(interaction.get("damage_multiplier", 0.0)),
			"damage_type": str(interaction.get("damage_type", "time")),
		}
		break
	if trail.is_empty():
		return {}
	return {
		"duration_frames": int(trail.get("duration_frames", 0)),
		"width_pixels": float(trail.get("width_tiles", 0.0)) * PIXELS_PER_TILE,
		"tick_interval_frames": int(trail.get("tick_interval_frames", 0)),
		"tick_damage_multiplier": float(trail.get("damage_multiplier", 0.0)),
		"damage_type": str(trail.get("damage_type", "void" if action_id == "void_penetration" else "time")),
	}


func _resolved_explosion(parameters: Dictionary) -> Dictionary:
	var value: Variant = parameters.get("penetration_explosion", {})
	if not value is Dictionary or (value as Dictionary).is_empty():
		return {}
	var explosion := value as Dictionary
	return {
		"radius_pixels": float(explosion.get("radius_tiles", 0.0)) * PIXELS_PER_TILE,
		"damage_multiplier": float(explosion.get("damage_multiplier", 0.0)),
		"damage_type": str(explosion.get("damage_type", "void")),
	}


func _resolved_vulnerability(parameters: Dictionary) -> Dictionary:
	var value: Variant = parameters.get("vulnerability", {})
	if not value is Dictionary or (value as Dictionary).is_empty():
		return {}
	var vulnerability := value as Dictionary
	return {
		"duration_frames": int(vulnerability.get("duration_frames", 0)),
		"damage_taken_bonus": float(vulnerability.get("damage_taken_bonus", 0.0)),
	}


func _rewind_generation(definition: Dictionary) -> int:
	var generation := 0
	for interaction_value: Variant in definition.get("time_interactions", []):
		if not interaction_value is Dictionary:
			return -1
		var interaction := interaction_value as Dictionary
		if str(interaction.get("interaction_id", "")) != "gun_rewind_free_shot":
			continue
		if generation > 0:
			return -1
		var generation_value: Variant = interaction.get("rewind_generation")
		if (
			typeof(generation_value) != TYPE_INT
			or int(generation_value) <= 0
			or typeof(interaction.get("one_shot_claim")) != TYPE_BOOL
			or not bool(interaction.get("one_shot_claim", false))
		):
			return -1
		generation = int(generation_value)
	return generation


func _claim_rewind_generation(generation: int) -> bool:
	var owner_player := _owner_player()
	return (
		generation > 0
		and owner_player != null
		and owner_player.has_method("claim_weapon_time_interaction")
		and bool(owner_player.call(
			"claim_weapon_time_interaction",
			REWIND_WINDOW_INTERACTION_ID,
			generation
		))
	)


func _definition_is_valid(definition: Dictionary) -> bool:
	if (
		str(definition.get("profile_id", "")) != PROFILE_ID
		or str(definition.get("weapon_id", "")) != "gun"
		or str(definition.get("action_id", "")) not in VALID_ACTION_IDS
		or typeof(definition.get("token")) != TYPE_INT
		or int(definition.get("token", 0)) <= 0
		or not definition.get("aim_direction") is Vector2
		or (definition.get("aim_direction") as Vector2).length_squared() <= 0.001
		or typeof(definition.get("base_attack")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(definition.get("base_attack", 0.0)))
		or float(definition.get("base_attack", 0.0)) <= 0.0
		or not definition.get("payload_descriptors") is Array
		or (definition.get("payload_descriptors") as Array).is_empty()
		or not definition.get("time_interactions", []) is Array
		or not definition.get("boss_conversion", {}) is Dictionary
		or typeof(definition.get("invulnerable_during_cast", false)) != TYPE_BOOL
		or _rewind_generation(definition) < 0
	):
		return false
	for descriptor_value: Variant in definition["payload_descriptors"]:
		if not _descriptor_is_valid(descriptor_value, int(definition["token"])):
			return false
	return true


func _descriptor_is_valid(value: Variant, token: int) -> bool:
	if not value is Dictionary:
		return false
	var descriptor := value as Dictionary
	return (
		str(descriptor.get("descriptor_id", "")).length() > 0
		and str(descriptor.get("kind", "")) in PROJECTILE_KINDS + PASSIVE_KINDS
		and typeof(descriptor.get("token")) == TYPE_INT
		and int(descriptor.get("token", 0)) == token
		and typeof(descriptor.get("outcome_index")) == TYPE_INT
		and int(descriptor.get("outcome_index", -1)) >= 0
		and typeof(descriptor.get("seed")) == TYPE_INT
		and descriptor.get("parameters", {}) is Dictionary
	)


func _configure_projectile_width(projectile: Node, width_tiles: float) -> void:
	if not is_finite(width_tiles) or width_tiles <= 0.0:
		return
	var collision := projectile.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return
	var shape := collision.shape.duplicate()
	if shape is CircleShape2D:
		(shape as CircleShape2D).radius = width_tiles * PIXELS_PER_TILE * 0.5
		collision.shape = shape


func _owner_player() -> Node:
	if owner_path != NodePath(""):
		var configured_owner := get_node_or_null(owner_path)
		if configured_owner != null:
			return configured_owner
	return get_parent()


func _acquire_cast_invulnerability(token: int) -> bool:
	var owner_player := _owner_player()
	if owner_player == null:
		return false
	var health := owner_player.get_node_or_null("HealthComponent")
	if health == null or not health.has_method("acquire_invulnerability_source"):
		return false
	var source_id := StringName("gun_void_cast_%d" % token)
	if not bool(health.call("acquire_invulnerability_source", source_id)):
		return false
	_invulnerability_health = health
	_invulnerability_source_id = source_id
	return true


func _release_cast_invulnerability() -> void:
	if (
		_invulnerability_source_id != &""
		and is_instance_valid(_invulnerability_health)
		and _invulnerability_health.has_method("release_invulnerability_source")
	):
		_invulnerability_health.call("release_invulnerability_source", _invulnerability_source_id)
	_invulnerability_health = null
	_invulnerability_source_id = &""


func _free_prepared(prepared: Array[Dictionary]) -> void:
	for entry: Dictionary in prepared:
		var node_value: Variant = entry.get("node")
		if is_instance_valid(node_value) and node_value is Node:
			(node_value as Node).free()
	prepared.clear()


func _clear_projectiles_for_token(token: int) -> void:
	for projectile: Node in _owned_projectiles:
		if (
			is_instance_valid(projectile)
			and not projectile.is_queued_for_deletion()
			and int(projectile.get("action_token")) == token
		):
			if projectile.has_method("reset_execution_state"):
				projectile.call("reset_execution_state")
			else:
				projectile.queue_free()
	_prune_owned_projectiles()


func _clear_owned_projectiles() -> void:
	for projectile: Node in _owned_projectiles:
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			continue
		if projectile.has_method("reset_execution_state"):
			projectile.call("reset_execution_state")
		else:
			projectile.queue_free()
	_owned_projectiles.clear()


func _prune_owned_projectiles() -> void:
	var active: Array[Node] = []
	for projectile: Node in _owned_projectiles:
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			active.append(projectile)
	_owned_projectiles = active


func _clear_profile_action() -> void:
	_profile_action.clear()
	_profile_action_released = false
	_profile_action_shared_claims = {}
	_release_cast_invulnerability()


func _projectile_callback_is_live(projectile: Node, action_token: int) -> bool:
	return (
		is_instance_valid(projectile)
		and not projectile.is_queued_for_deletion()
		and _owned_projectiles.has(projectile)
		and int(projectile.get("action_token")) == action_token
		and projectile.get("source") == self
		and projectile.get("owner_entity") == _owner_player()
	)


func _on_projectile_hit_confirmed(
	action_token: int,
	outcome_index: int,
	target: Node,
	projectile: Node
) -> void:
	if (
		not _projectile_callback_is_live(projectile, action_token)
		or int(projectile.get("outcome_index")) != outcome_index
	):
		return
	projectile_hit_confirmed.emit(action_token, outcome_index, target)


func _on_action_hit_confirmed(action_token: int, target: Node, projectile: Node) -> void:
	if not _projectile_callback_is_live(projectile, action_token):
		return
	action_hit_confirmed.emit(action_token, target)


func _on_resource_reward_requested(
	action_token: int,
	reward_id: StringName,
	amount: float,
	projectile: Node
) -> void:
	if not _projectile_callback_is_live(projectile, action_token):
		return
	resource_reward_requested.emit(action_token, reward_id, amount)


func _exit_tree() -> void:
	reset_runtime_state()
