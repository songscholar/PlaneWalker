class_name StaffWeapon
extends Node2D

signal payload_result_reported(action_token: int, generation: int, result: Dictionary)
signal resource_reward_requested(
	action_token: int,
	claim_id: StringName,
	reward_id: StringName,
	amount: float
)

const StaffProjectileScene := preload("res://scenes/combat/staff_projectile.tscn")
const StaffSpellZoneScene := preload("res://scenes/combat/staff_spell_zone.tscn")

const PIXELS_PER_TILE := 64.0
const PROFILE_ID := "staff_launch_v1"
const VALID_ACTION_IDS: Array[String] = [
	"arcane_bolt",
	"charged_element",
	"element_cycle",
	"planar_collapse",
	"primordial_wrath",
]
const PROJECTILE_KINDS: Array[String] = ["projectile", "typed_element"]
const ZONE_KINDS: Array[String] = ["zone", "seeded_sequence"]
const CALLBACK_CLAIM_LIMIT := 512
const RESOURCE_REWARD_CLAIM_LIMIT := 128

@export var owner_path: NodePath
@export var base_attack: float = 9.0
@export var attack_speed: float = 0.85

var _result_sink: Object
var _profile_action: Dictionary = {}
var _profile_action_released: bool = false
var _prepared_payloads: Array[Dictionary] = []
var _owned_payloads: Array[Node] = []
var _owned_payload_identity: Dictionary = {}
var _callback_claims: Dictionary = {}
var _callback_claim_order: Array[String] = []
var _resource_reward_claims: Dictionary = {}
var _resource_reward_claim_order: Array[String] = []
var _payload_prune_scheduled: bool = false
var _invulnerability_health: Node
var _invulnerability_source_id: StringName = &""


func configure_result_sink(sink: Object) -> bool:
	if sink == null or not is_instance_valid(sink) or not sink.has_method("handle_payload_result"):
		return false
	_result_sink = sink
	return true


func begin_profile_action(definition: Dictionary) -> Dictionary:
	_prune_owned_payloads()
	if is_profile_action_active():
		return {}
	if not _definition_is_valid(definition):
		_report_construction_failure(definition, "definition_invalid")
		return {}
	var prepared: Array[Dictionary] = []
	for descriptor_value: Variant in definition["payload_descriptors"]:
		var descriptor := descriptor_value as Dictionary
		var prepared_payload := _prepare_payload(descriptor, definition)
		if prepared_payload.is_empty():
			_free_prepared(prepared)
			_report_construction_failure(
				definition,
				"payload_construction_failed",
				str(descriptor.get("descriptor_id", "")),
				int(descriptor.get("outcome_index", -1))
			)
			return {}
		prepared.append(prepared_payload)
	if bool(definition.get("invulnerable_during_cast", false)):
		if not _acquire_cast_invulnerability(int(definition["token"])):
			_free_prepared(prepared)
			_report_construction_failure(definition, "cast_invulnerability_unavailable")
			return {}
	_profile_action = definition.duplicate(true)
	_profile_action_released = false
	_prepared_payloads = prepared
	return definition.duplicate(true)


func release_profile_action() -> bool:
	if _profile_action.is_empty() or _profile_action_released:
		return false
	var parent := get_tree().current_scene if is_inside_tree() else null
	if parent == null and not _prepared_payloads.is_empty():
		return false
	for prepared: Dictionary in _prepared_payloads:
		var payload_value: Variant = prepared.get("node")
		if not payload_value is Node or not is_instance_valid(payload_value):
			return false
	for prepared: Dictionary in _prepared_payloads:
		_attach_payload(prepared, parent)
	_prepared_payloads.clear()
	_profile_action_released = true
	return true


func is_profile_action_active() -> bool:
	return not _profile_action.is_empty()


func cancel_profile_action() -> void:
	var token := int(_profile_action.get("token", 0))
	var generation := int(_profile_action.get("generation", 0))
	_free_prepared(_prepared_payloads)
	_prepared_payloads.clear()
	if token > 0 and generation > 0:
		_clear_status_sources_for_action(token, generation)
		_clear_payloads_for_action(token, generation)
	_clear_profile_action()


func finish_profile_action() -> void:
	_free_prepared(_prepared_payloads)
	_prepared_payloads.clear()
	_prune_owned_payloads()
	_clear_profile_action()


func reset_runtime_state() -> void:
	_free_prepared(_prepared_payloads)
	_prepared_payloads.clear()
	_clear_all_status_sources()
	_clear_owned_payloads()
	_callback_claims.clear()
	_callback_claim_order.clear()
	_resource_reward_claims.clear()
	_resource_reward_claim_order.clear()
	_clear_profile_action()


func prepared_payload_count_for_test() -> int:
	return _prepared_payloads.size()


func owned_payload_count_for_test() -> int:
	_prune_owned_payloads()
	return _owned_payloads.size()


func owned_payloads_for_test() -> Array[Node]:
	_prune_owned_payloads()
	return _owned_payloads.duplicate()


func prepared_payload_snapshots_for_test() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for prepared: Dictionary in _prepared_payloads:
		var node_value: Variant = prepared.get("node")
		if node_value is Node and is_instance_valid(node_value) and (node_value as Node).has_method("execution_snapshot"):
			result.append(((node_value as Node).call("execution_snapshot") as Dictionary).duplicate(true))
	return result


func prepared_payload_positions_for_test() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for prepared: Dictionary in _prepared_payloads:
		var position_value: Variant = prepared.get("global_position")
		if position_value is Vector2:
			result.append(position_value as Vector2)
	return result


func runtime_bookkeeping_snapshot_for_test() -> Dictionary:
	_prune_owned_payloads()
	return {
		"owned_payload_count": _owned_payloads.size(),
		"owned_payload_identity_count": _owned_payload_identity.size(),
		"callback_claim_count": _callback_claims.size(),
		"resource_reward_claim_count": _resource_reward_claims.size(),
	}


func _prepare_payload(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	var kind := str(descriptor.get("kind", ""))
	if kind in PROJECTILE_KINDS:
		return _prepare_projectile(descriptor, definition)
	if kind in ZONE_KINDS:
		return _prepare_zone(descriptor, definition)
	if kind == "resource_action":
		return {
			"node": Node.new(),
			"passive": true,
			"global_position": global_position,
			"token": int(definition["token"]),
			"generation": int(definition["generation"]),
		}
	return {}


func _prepare_projectile(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	var execution := _projectile_execution(descriptor, definition)
	if execution.is_empty():
		return {}
	var projectile := StaffProjectileScene.instantiate()
	if not bool(projectile.call("configure_execution", execution)):
		projectile.free()
		return {}
	projectile.direction = definition["aim_direction"]
	projectile.source = self
	projectile.owner_entity = _owner_player()
	projectile.payload_result.connect(_on_payload_result.bind(projectile))
	_configure_projectile_width(projectile, float((descriptor["parameters"] as Dictionary).get("hit_width_tiles", 0.3)))
	return {
		"node": projectile,
		"passive": false,
		"global_position": global_position + (definition["aim_direction"] as Vector2).normalized() * 28.0,
		"token": int(definition["token"]),
		"generation": int(definition["generation"]),
	}


func _prepare_zone(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	var execution := _zone_execution(descriptor, definition)
	if execution.is_empty():
		return {}
	var zone := StaffSpellZoneScene.instantiate()
	if not bool(zone.call("configure_execution", execution)):
		zone.free()
		return {}
	zone.payload_result.connect(_on_payload_result.bind(zone))
	zone.resource_reward_requested.connect(_on_zone_resource_reward_requested.bind(zone))
	_configure_zone_radius(zone, float(execution.get("parameters", {}).get("radius_tiles", 1.0)))
	var payload_position := global_position
	if str(definition.get("action_id", "")) == "planar_collapse":
		payload_position += (definition["aim_direction"] as Vector2).normalized() * 6.0 * PIXELS_PER_TILE
	return {
		"node": zone,
		"passive": false,
		"global_position": payload_position,
		"token": int(definition["token"]),
		"generation": int(definition["generation"]),
	}


func _projectile_execution(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	var parameters := (descriptor.get("parameters", {}) as Dictionary).duplicate(true)
	var element_definition_value: Variant = parameters.get("element_definition", {})
	if element_definition_value is Dictionary:
		for field: Variant in (element_definition_value as Dictionary):
			parameters[field] = (element_definition_value as Dictionary)[field]
	var element_id := str(parameters.get("element_id", parameters.get("element", "arcane")))
	var multiplier := float(parameters.get("resolved_damage_multiplier", parameters.get("damage_multiplier", 0.0)))
	var speed_pixels := float(parameters.get("speed", 0.0))
	if speed_pixels <= 0.0:
		speed_pixels = float(parameters.get("speed_tiles_per_second", 0.0)) * PIXELS_PER_TILE
	var range_pixels := float(parameters.get("maximum_range_pixels", 0.0))
	if range_pixels <= 0.0:
		range_pixels = float(parameters.get("maximum_range_tiles", 0.0)) * PIXELS_PER_TILE
	if range_pixels <= 0.0:
		range_pixels = 12.0 * PIXELS_PER_TILE
	var effect := parameters.duplicate(true)
	var chain: Dictionary = {}
	if element_id == "lightning":
		chain = {
			"additional_target_count": int(parameters.get("additional_target_count", 0)),
			"chain_range_tiles": float(parameters.get("chain_range_tiles", 0.0)),
			"chain_damage_multiplier": float(parameters.get("chain_damage_multiplier", 0.0)),
			"chain_order": str(parameters.get("chain_order", "")),
		}
	var combination_value: Variant = parameters.get("combination", {})
	var resolved_combination := (
		(combination_value as Dictionary).duplicate(true)
		if combination_value is Dictionary
		else {}
	)
	var rift_interaction := _interaction_by_id(
		definition.get("time_interactions", []),
		"staff_rift_combination"
	)
	if (
		not resolved_combination.is_empty()
		and not rift_interaction.is_empty()
		and str(rift_interaction.get("combo_id", "")) == str(resolved_combination.get("combo_id", ""))
	):
		resolved_combination["rift_interaction"] = rift_interaction
	return {
		"action_token": int(definition["token"]),
		"generation": int(definition["generation"]),
		"source_action_id": str(definition["action_id"]),
		"descriptor_id": str(descriptor["descriptor_id"]),
		"outcome_index": int(descriptor["outcome_index"]),
		"deterministic_seed": int(descriptor["seed"]),
		"element_id": element_id,
		"damage": float(definition["base_attack"]) * multiplier,
		"base_attack": float(definition["base_attack"]),
		"speed": speed_pixels,
		"max_range_pixels": range_pixels,
		"direction": (definition["aim_direction"] as Vector2).normalized(),
		"target_deduplication": str(descriptor.get("target_deduplication", "per_action_target")),
		"effect_descriptor": effect,
		"combination": resolved_combination,
		"chain": chain,
		"boss_conversion": (definition.get("boss_conversion", {}) as Dictionary).duplicate(true),
		"status_source_id": _status_source_id(
			int(definition["token"]),
			str(descriptor["descriptor_id"]),
			int(descriptor["outcome_index"])
		),
	}


func _zone_execution(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	var parameters := (descriptor.get("parameters", {}) as Dictionary).duplicate(true)
	var kind := str(descriptor.get("kind", ""))
	var mode := "seeded_sequence" if kind == "seeded_sequence" else "planar_collapse"
	if mode == "planar_collapse":
		parameters["tick_interval_frames"] = int(parameters.get(
			"tick_interval_frames",
			parameters.get("void_erosion_tick_interval_frames", 30)
		))
		parameters["radius_tiles"] = float(parameters.get("radius_tiles", 0.0))
		parameters["damage_multiplier"] = float(parameters.get("damage_multiplier", 0.0))
		var stop_interaction := _interaction_by_id(
			definition.get("time_interactions", []),
			"staff_stop_field"
		)
		if not stop_interaction.is_empty():
			var area_multiplier := float(stop_interaction.get("area_multiplier", 1.0))
			var duration_multiplier := float(stop_interaction.get("duration_multiplier", 1.0))
			parameters["radius_tiles"] = float(parameters["radius_tiles"]) * area_multiplier
			parameters["duration_frames"] = ceili(float(parameters.get("duration_frames", 0)) * duration_multiplier)
			parameters["void_erosion_duration_frames"] = ceili(
				float(parameters.get("void_erosion_duration_frames", 0)) * duration_multiplier
			)
			parameters["stop_interaction"] = stop_interaction
	return {
		"action_token": int(definition["token"]),
		"generation": int(definition["generation"]),
		"source_action_id": str(definition["action_id"]),
		"descriptor_id": str(descriptor["descriptor_id"]),
		"outcome_index": int(descriptor["outcome_index"]),
		"deterministic_seed": int(descriptor["seed"]),
		"mode": mode,
		"base_attack": float(definition["base_attack"]),
		"source": self,
		"owner_entity": _owner_player(),
		"boss_conversion": (definition.get("boss_conversion", {}) as Dictionary).duplicate(true),
		"status_source_id": _status_source_id(
			int(definition["token"]),
			str(descriptor["descriptor_id"]),
			int(descriptor["outcome_index"])
		),
		"parameters": parameters,
	}


func _on_payload_result(
	action_token: int,
	generation: int,
	result: Dictionary,
	payload: Node
) -> void:
	if not _payload_callback_is_live(payload, action_token, generation):
		return
	var spawn_zone_value: Variant = result.get("spawn_zone", {})
	if spawn_zone_value is Dictionary and not (spawn_zone_value as Dictionary).is_empty():
		_spawn_result_zone(action_token, generation, result, spawn_zone_value as Dictionary, payload)
	var runtime_response := _report_result(action_token, generation, result, payload)
	var confirmed_combo_value: Variant = runtime_response.get("combo", {})
	if confirmed_combo_value is Dictionary and not (confirmed_combo_value as Dictionary).is_empty():
		var confirmed_combo := (confirmed_combo_value as Dictionary).duplicate(true)
		var raw_combo_value: Variant = result.get("combination", {})
		if (
			raw_combo_value is Dictionary
			and str((raw_combo_value as Dictionary).get("combo_id", "")) == str(confirmed_combo.get("combo_id", ""))
		):
			var spatial_combo := confirmed_combo.duplicate(true)
			spatial_combo["rift_interaction"] = (
				(raw_combo_value as Dictionary).get("rift_interaction", {}) as Dictionary
			).duplicate(true)
			var rift := _intersecting_rift_interaction(spatial_combo, result)
			if not rift.is_empty():
				confirmed_combo["rift_interaction"] = rift
		_spawn_combination_zone(action_token, generation, result, confirmed_combo, payload)
	_schedule_owned_payload_prune()


func _spawn_result_zone(
	action_token: int,
	generation: int,
	result: Dictionary,
	zone_descriptor: Dictionary,
	payload: Node
) -> void:
	var parameters_value: Variant = zone_descriptor.get("parameters", {})
	if not parameters_value is Dictionary:
		return
	var dynamic_descriptor_id := str(zone_descriptor.get(
		"descriptor_id",
		"%s:zone" % str(result.get("descriptor_id", "staff"))
	))
	var execution := {
		"action_token": action_token,
		"generation": generation,
		"source_action_id": str(payload.get("source_action_id")),
		"descriptor_id": dynamic_descriptor_id,
		"outcome_index": int(result.get("outcome_index", 0)),
		"deterministic_seed": int(result.get("deterministic_seed", 0)),
		"mode": str(zone_descriptor.get("mode", "ice_zone")),
		"base_attack": float(payload.get("base_attack")),
		"source": payload.get("source"),
		"owner_entity": payload.get("owner_entity"),
		"boss_conversion": (payload.get("boss_conversion") as Dictionary).duplicate(true),
		"status_source_id": _status_source_id(
			action_token,
			dynamic_descriptor_id,
			int(result.get("outcome_index", 0))
		),
		"parameters": (parameters_value as Dictionary).duplicate(true),
	}
	_attach_dynamic_zone(execution, _result_position(result, payload.global_position))


func _spawn_combination_zone(
	action_token: int,
	generation: int,
	result: Dictionary,
	combination: Dictionary,
	payload: Node
) -> void:
	var parameters_value: Variant = combination.get("parameters", {})
	if not parameters_value is Dictionary:
		return
	var combo_parameters := (parameters_value as Dictionary).duplicate(true)
	var rift_value: Variant = combination.get("rift_interaction", {})
	if rift_value is Dictionary and not (rift_value as Dictionary).is_empty():
		var rift := rift_value as Dictionary
		_scale_combo_radii(combo_parameters, float(rift.get("area_multiplier", 1.0)))
		combo_parameters["time_damage_multiplier"] = float(rift.get("time_damage_multiplier", 0.0))
		combo_parameters["rift_source_generation"] = int(rift.get("source_generation", 0))
	var dynamic_descriptor_id := "%s:%s" % [
		str(result.get("descriptor_id", "staff")),
		str(combination.get("combo_id", "combo")),
	]
	var execution := {
		"action_token": action_token,
		"generation": generation,
		"source_action_id": str(payload.get("source_action_id")),
		"descriptor_id": dynamic_descriptor_id,
		"outcome_index": int(result.get("outcome_index", 0)),
		"deterministic_seed": int(result.get("deterministic_seed", 0)),
		"mode": "combination",
		"base_attack": float(payload.get("base_attack")),
		"source": payload.get("source"),
		"owner_entity": payload.get("owner_entity"),
		"boss_conversion": (payload.get("boss_conversion") as Dictionary).duplicate(true),
		"status_source_id": _status_source_id(
			action_token,
			dynamic_descriptor_id,
			int(result.get("outcome_index", 0))
		),
		"parameters": {
			"combo_id": str(combination.get("combo_id", "")),
			"combo_kind": str(combination.get("kind", "")),
			"combo_parameters": combo_parameters,
		},
	}
	_attach_dynamic_zone(execution, _result_position(result, payload.global_position))


func _attach_dynamic_zone(execution: Dictionary, position: Vector2) -> void:
	var parent := get_tree().current_scene if is_inside_tree() else null
	if parent == null:
		return
	var zone := StaffSpellZoneScene.instantiate()
	if not bool(zone.call("configure_execution", execution)):
		zone.free()
		return
	zone.payload_result.connect(_on_payload_result.bind(zone))
	zone.resource_reward_requested.connect(_on_zone_resource_reward_requested.bind(zone))
	_configure_zone_radius(zone, _execution_radius_tiles(execution))
	var prepared := {
		"node": zone,
		"passive": false,
		"global_position": position,
		"token": int(execution["action_token"]),
		"generation": int(execution["generation"]),
	}
	_attach_payload(prepared, parent)


func _attach_payload(prepared: Dictionary, parent: Node) -> void:
	var payload := prepared["node"] as Node
	if bool(prepared.get("passive", false)):
		payload.free()
		return
	parent.add_child(payload)
	if payload is Node2D:
		(payload as Node2D).global_position = prepared["global_position"]
	_owned_payloads.append(payload)
	_owned_payload_identity[payload.get_instance_id()] = {
		"token": int(prepared["token"]),
		"generation": int(prepared["generation"]),
	}


func _report_construction_failure(
	definition: Dictionary,
	reason: String,
	descriptor_id: String = "",
	outcome_index: int = -1
) -> void:
	var token := int(definition.get("token", 0))
	var generation := int(definition.get("generation", 0))
	if token <= 0 or generation <= 0:
		return
	_report_result(token, generation, {
		"type": "construction_failed",
		"claim_id": "construction_failed",
		"reason": reason,
		"descriptor_id": descriptor_id,
		"outcome_index": outcome_index,
	})


func _on_zone_resource_reward_requested(
	action_token: int,
	generation: int,
	claim_id: StringName,
	reward_id: StringName,
	amount: float,
	payload: Node
) -> void:
	if (
		not _payload_callback_is_live(payload, action_token, generation)
		or claim_id == &""
		or reward_id == &""
		or not is_finite(amount)
		or amount <= 0.0
	):
		return
	var key := "%d:%d:%s" % [action_token, generation, str(claim_id)]
	if not _record_bounded_claim(
		_resource_reward_claims,
		_resource_reward_claim_order,
		key,
		RESOURCE_REWARD_CLAIM_LIMIT
	):
		return
	resource_reward_requested.emit(action_token, claim_id, reward_id, amount)


func _report_result(
	action_token: int,
	generation: int,
	result: Dictionary,
	payload: Node = null
) -> Dictionary:
	var claim_id := str(result.get("claim_id", ""))
	if claim_id.is_empty():
		return {}
	var key := "%d:%d:%s" % [action_token, generation, claim_id]
	if not _record_bounded_claim(
		_callback_claims,
		_callback_claim_order,
		key,
		CALLBACK_CLAIM_LIMIT
	):
		return {}
	var frozen := result.duplicate(true)
	var runtime_response: Dictionary = {}
	if _result_sink != null and is_instance_valid(_result_sink):
		var runtime_result := _normalized_runtime_result(frozen, payload)
		if not runtime_result.is_empty():
			var response_value: Variant = _result_sink.call(
				"handle_payload_result",
				action_token,
				generation,
				runtime_result
			)
			if response_value is Dictionary:
				runtime_response = (response_value as Dictionary).duplicate(true)
	payload_result_reported.emit(action_token, generation, frozen)
	return runtime_response


func _normalized_runtime_result(result: Dictionary, payload: Node) -> Dictionary:
	var result_type := str(result.get("type", ""))
	if result_type not in ["damage_resolved", "hit_confirmed", "terminal_miss"]:
		return {}
	var descriptor_id := str(result.get("descriptor_id", ""))
	var outcome_index_value: Variant = result.get("outcome_index")
	var element_id := str(result.get("element", result.get("element_id", "")))
	if (
		descriptor_id.is_empty()
		or typeof(outcome_index_value) != TYPE_INT
		or int(outcome_index_value) < 0
		or element_id.is_empty()
	):
		return {}
	var terminal := result_type != "damage_resolved"
	var hit_value: Variant = result.get("hit", result_type == "hit_confirmed")
	var damage_value: Variant = result.get("damage", 0.0)
	if typeof(hit_value) != TYPE_BOOL or typeof(damage_value) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	var damage := float(damage_value)
	if not is_finite(damage) or damage < 0.0:
		return {}
	var hit := bool(hit_value)
	var target_id := int(result.get("target_id", -1))
	if hit and target_id < 0:
		return {}
	var normalized := result.duplicate(true)
	normalized["outcome_id"] = _runtime_outcome_id(result, descriptor_id, int(outcome_index_value), element_id)
	normalized["element"] = element_id
	normalized["target_id"] = target_id
	normalized["terminal"] = terminal
	normalized["damage"] = damage
	normalized["hit"] = hit
	normalized["resource_only"] = result_type == "damage_resolved"
	if result_type == "hit_confirmed" and hit and element_id == "lightning":
		var material := _validated_chain_target_impacts(result)
		if not bool(material.get("ok", false)):
			return {}
		normalized["chain_target_ids"] = (material.get("target_ids", []) as Array).duplicate()
		normalized["chain_origin_positions"] = (material.get("positions", []) as Array).duplicate()
	return normalized


func _runtime_outcome_id(
	result: Dictionary,
	descriptor_id: String,
	outcome_index: int,
	element_id: String
) -> String:
	var base_id := str(result.get("outcome_id", "%s:%d" % [descriptor_id, outcome_index]))
	if str(result.get("type", "")) != "damage_resolved":
		return base_id
	var frame_value: Variant = result.get("execution_frame")
	if typeof(frame_value) == TYPE_INT and int(frame_value) >= 0:
		return "%s:frame:%d:%s" % [base_id, int(frame_value), element_id]
	var scope := str(result.get("damage_scope", "derived"))
	return "%s:%s:%s" % [base_id, scope, element_id]


func _validated_chain_target_impacts(result: Dictionary) -> Dictionary:
	var target_ids_value: Variant = result.get("chain_target_ids", [])
	var impacts_value: Variant = result.get("chain_target_impacts", [])
	if not target_ids_value is Array or not impacts_value is Array:
		return {"ok": false}
	var expected_ids: Array[int] = []
	var expected_seen: Dictionary = {}
	for target_id_value: Variant in target_ids_value as Array:
		if typeof(target_id_value) != TYPE_INT:
			return {"ok": false}
		var target_id := int(target_id_value)
		if target_id <= 0 or expected_seen.has(target_id):
			return {"ok": false}
		expected_seen[target_id] = true
		expected_ids.append(target_id)
	var target_ids: Array[int] = []
	var positions: Array[Vector2] = []
	var seen: Dictionary = {}
	for impact_value: Variant in impacts_value as Array:
		if not impact_value is Dictionary:
			return {"ok": false}
		var impact := impact_value as Dictionary
		var target_id_value: Variant = impact.get("target_id")
		var position_value: Variant = impact.get("impact_position")
		if typeof(target_id_value) != TYPE_INT or not position_value is Vector2:
			return {"ok": false}
		var target_id := int(target_id_value)
		var position := position_value as Vector2
		if (
			target_id <= 0
			or seen.has(target_id)
			or not is_finite(position.x)
			or not is_finite(position.y)
		):
			return {"ok": false}
		seen[target_id] = true
		target_ids.append(target_id)
		positions.append(position)
	if target_ids != expected_ids:
		return {"ok": false}
	return {
		"ok": true,
		"target_ids": target_ids,
		"positions": positions,
	}


func _payload_callback_is_live(payload: Node, action_token: int, generation: int) -> bool:
	if payload == null or not is_instance_valid(payload) or payload.is_queued_for_deletion():
		return false
	var identity_value: Variant = _owned_payload_identity.get(payload.get_instance_id(), {})
	if not identity_value is Dictionary:
		return false
	var identity := identity_value as Dictionary
	return int(identity.get("token", 0)) == action_token and int(identity.get("generation", 0)) == generation


func _definition_is_valid(definition: Dictionary) -> bool:
	if (
		str(definition.get("profile_id", "")) != PROFILE_ID
		or str(definition.get("weapon_id", "")) != "staff"
		or str(definition.get("action_id", "")) not in VALID_ACTION_IDS
		or typeof(definition.get("token")) != TYPE_INT
		or int(definition.get("token", 0)) <= 0
		or typeof(definition.get("generation")) != TYPE_INT
		or int(definition.get("generation", 0)) <= 0
		or not definition.get("aim_direction") is Vector2
		or (definition.get("aim_direction") as Vector2).is_zero_approx()
		or not _positive_number(definition.get("base_attack"))
		or not definition.get("payload_descriptors") is Array
		or (definition.get("payload_descriptors") as Array).is_empty()
		or not definition.get("time_interactions", []) is Array
		or not definition.get("boss_conversion", {}) is Dictionary
		or typeof(definition.get("invulnerable_during_cast", false)) != TYPE_BOOL
	):
		return false
	for descriptor_value: Variant in definition["payload_descriptors"]:
		if not _descriptor_is_valid(descriptor_value, int(definition["token"]), int(definition["generation"])):
			return false
	return true


func _descriptor_is_valid(value: Variant, token: int, generation: int) -> bool:
	if not value is Dictionary:
		return false
	var descriptor := value as Dictionary
	return (
		str(descriptor.get("descriptor_id", "")).length() > 0
		and str(descriptor.get("kind", "")) in PROJECTILE_KINDS + ZONE_KINDS + ["resource_action"]
		and typeof(descriptor.get("token")) == TYPE_INT
		and int(descriptor.get("token", 0)) == token
		and typeof(descriptor.get("generation")) == TYPE_INT
		and int(descriptor.get("generation", 0)) == generation
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


func _configure_zone_radius(zone: Node, radius_tiles: float) -> void:
	if not is_finite(radius_tiles) or radius_tiles <= 0.0:
		return
	var collision := zone.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return
	var shape := collision.shape.duplicate()
	if shape is CircleShape2D:
		(shape as CircleShape2D).radius = radius_tiles * PIXELS_PER_TILE
		collision.shape = shape


func _owner_player() -> Node:
	if owner_path != NodePath(""):
		var configured_owner := get_node_or_null(owner_path)
		if configured_owner != null:
			return configured_owner
	return get_parent()


func _free_prepared(prepared_payloads: Array[Dictionary]) -> void:
	for prepared: Dictionary in prepared_payloads:
		var node_value: Variant = prepared.get("node")
		if node_value is Node and is_instance_valid(node_value):
			if (node_value as Node).has_method("reset_execution_state"):
				(node_value as Node).call("reset_execution_state")
			(node_value as Node).free()


func _clear_payloads_for_action(action_token: int, generation: int) -> void:
	_prune_owned_payloads()
	for payload: Node in _owned_payloads.duplicate():
		if payload == null or not is_instance_valid(payload):
			continue
		var identity: Dictionary = _owned_payload_identity.get(payload.get_instance_id(), {})
		if int(identity.get("token", 0)) != action_token or int(identity.get("generation", 0)) != generation:
			continue
		_owned_payload_identity.erase(payload.get_instance_id())
		_owned_payloads.erase(payload)
		if payload.has_method("reset_execution_state"):
			payload.call("reset_execution_state")
		payload.queue_free()


func _clear_owned_payloads() -> void:
	for payload: Node in _owned_payloads:
		if payload != null and is_instance_valid(payload) and not payload.is_queued_for_deletion():
			if payload.has_method("reset_execution_state"):
				payload.call("reset_execution_state")
			payload.queue_free()
	_owned_payloads.clear()
	_owned_payload_identity.clear()


func _prune_owned_payloads() -> void:
	_payload_prune_scheduled = false
	var survivors: Array[Node] = []
	var survivor_identities: Dictionary = {}
	for payload: Node in _owned_payloads:
		if payload == null or not is_instance_valid(payload) or payload.is_queued_for_deletion():
			continue
		survivors.append(payload)
		var instance_id := payload.get_instance_id()
		if _owned_payload_identity.has(instance_id):
			survivor_identities[instance_id] = _owned_payload_identity[instance_id]
	_owned_payloads = survivors
	_owned_payload_identity = survivor_identities


func _schedule_owned_payload_prune() -> void:
	if _payload_prune_scheduled:
		return
	_payload_prune_scheduled = true
	call_deferred("_prune_owned_payloads")


func _clear_profile_action() -> void:
	_profile_action.clear()
	_profile_action_released = false
	_release_cast_invulnerability()


func _exit_tree() -> void:
	reset_runtime_state()


func _positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


func _status_source_id(
	action_token: int,
	payload_descriptor_id: String,
	payload_outcome_index: int
) -> StringName:
	return StringName("staff:%d:%s:%d" % [
		action_token,
		payload_descriptor_id,
		payload_outcome_index,
	])


func _clear_status_sources_for_action(action_token: int, source_generation: int) -> void:
	if action_token <= 0 or source_generation <= 0:
		return
	_clear_matching_status_sources("staff:%d:" % action_token, source_generation)


func _clear_all_status_sources() -> void:
	_clear_matching_status_sources("staff:")


func _clear_matching_status_sources(source_prefix: String, required_generation: int = -1) -> void:
	if source_prefix.is_empty() or not is_inside_tree():
		return
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if (
			enemy == null
			or not is_instance_valid(enemy)
			or not enemy.has_method("elemental_status_snapshot")
			or not enemy.has_method("clear_owned_elemental_statuses")
		):
			continue
		var snapshot_value: Variant = enemy.call("elemental_status_snapshot")
		if not snapshot_value is Dictionary:
			continue
		var effects_value: Variant = (snapshot_value as Dictionary).get("effects", [])
		if not effects_value is Array:
			continue
		var cleared_sources: Dictionary = {}
		for effect_value: Variant in effects_value as Array:
			if not effect_value is Dictionary:
				continue
			var effect := effect_value as Dictionary
			var source_id := StringName(str(effect.get("source_id", "")))
			var generation := int(effect.get("generation", -1))
			if (
				source_id == &""
				or not str(source_id).begins_with(source_prefix)
				or (required_generation >= 0 and generation != required_generation)
			):
				continue
			var source_key := "%d:%s" % [generation, str(source_id)]
			if cleared_sources.has(source_key):
				continue
			cleared_sources[source_key] = true
			enemy.call("clear_owned_elemental_statuses", source_id, generation)


func _record_bounded_claim(
	store: Dictionary,
	order: Array[String],
	key: String,
	maximum: int
) -> bool:
	if key.is_empty() or maximum <= 0 or store.has(key):
		return false
	store[key] = true
	order.append(key)
	while order.size() > maximum:
		var expired_key: String = order.pop_front()
		store.erase(expired_key)
	return true


func _execution_radius_tiles(execution: Dictionary) -> float:
	var parameters_value: Variant = execution.get("parameters", {})
	if not parameters_value is Dictionary:
		return 1.0
	var execution_parameters := parameters_value as Dictionary
	var direct_radius := float(execution_parameters.get("radius_tiles", 0.0))
	if direct_radius > 0.0:
		return direct_radius
	var combo_value: Variant = execution_parameters.get("combo_parameters", {})
	if not combo_value is Dictionary:
		return 1.0
	var combo := combo_value as Dictionary
	return maxf(
		1.0,
		maxf(
			float(combo.get("radius_tiles", 0.0)),
			maxf(
				float(combo.get("freeze_radius_tiles", 0.0)),
				float(combo.get("explosion_radius_tiles", 0.0))
			)
		)
	)


func _stable_target_id(target: Node) -> int:
	if target.has_meta("stable_target_id"):
		return int(target.get_meta("stable_target_id"))
	var stable_key := _stable_target_key(target)
	if not stable_key.is_empty():
		return maxi(1, _stable_hash(stable_key))
	return target.get_instance_id()


func _stable_target_key(target: Node) -> String:
	if target.has_meta("stable_target_id"):
		return "stable:%s" % str(target.get_meta("stable_target_id"))
	for metadata_key: String in ["encounter_spawn_id", "spawn_id"]:
		if target.has_meta(metadata_key):
			var metadata_value := str(target.get_meta(metadata_key, ""))
			if not metadata_value.is_empty():
				return "%s:%s" % [metadata_key, metadata_value]
	if target.is_inside_tree():
		var path := str(target.get_path())
		if not path.is_empty():
			return "path:%s" % path
	return ""


func _stable_hash(material: String) -> int:
	var value := 0
	for index: int in range(material.length()):
		value = int((value * 131 + material.unicode_at(index)) % 2147483647)
	return value


func _interaction_by_id(values: Variant, interaction_id: String) -> Dictionary:
	if not values is Array:
		return {}
	for value: Variant in values as Array:
		if value is Dictionary and str((value as Dictionary).get("interaction_id", "")) == interaction_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _scale_combo_radii(combo_parameters: Dictionary, multiplier: float) -> void:
	if not is_finite(multiplier) or multiplier <= 0.0:
		return
	for field: String in ["radius_tiles", "freeze_radius_tiles", "explosion_radius_tiles"]:
		var value: Variant = combo_parameters.get(field)
		if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0:
			combo_parameters[field] = float(value) * multiplier


func _intersecting_rift_interaction(combination: Dictionary, result: Dictionary) -> Dictionary:
	var interaction_value: Variant = combination.get("rift_interaction", {})
	if not interaction_value is Dictionary:
		return {}
	var interaction := interaction_value as Dictionary
	if str(interaction.get("spatial_policy", "")) != "zone_intersection":
		return {}
	var source_generation := int(interaction.get("source_generation", 0))
	var rifts_value: Variant = interaction.get("active_rifts", [])
	var parameters_value: Variant = combination.get("parameters", {})
	if (
		source_generation <= 0
		or not rifts_value is Array
		or not parameters_value is Dictionary
	):
		return {}
	var centers := _combination_intersection_centers(combination, result)
	if centers.is_empty():
		return {}
	var combo_radius := _combination_radius_tiles(parameters_value as Dictionary) * PIXELS_PER_TILE
	for descriptor_value: Variant in rifts_value as Array:
		if not descriptor_value is Dictionary:
			continue
		var descriptor := descriptor_value as Dictionary
		var center_value: Variant = descriptor.get("center")
		var radius_value: Variant = descriptor.get("radius")
		if (
			int(descriptor.get("generation", 0)) != source_generation
			or not center_value is Vector2
			or typeof(radius_value) not in [TYPE_INT, TYPE_FLOAT]
		):
			continue
		var center := center_value as Vector2
		var radius := float(radius_value)
		if (
			not is_finite(center.x)
			or not is_finite(center.y)
			or not is_finite(radius)
			or radius <= 0.0
		):
			continue
		for combo_center: Vector2 in centers:
			if combo_center.distance_squared_to(center) <= pow(combo_radius + radius, 2.0) + 0.0001:
				return interaction.duplicate(true)
	return {}


func _combination_intersection_centers(combination: Dictionary, result: Dictionary) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	if str(combination.get("first", "")) == "lightning":
		var parameters_value: Variant = combination.get("parameters", {})
		if not parameters_value is Dictionary:
			return centers
		var origins_value: Variant = (parameters_value as Dictionary).get("origin_positions", [])
		if not origins_value is Array:
			return centers
		for origin_value: Variant in origins_value as Array:
			if not origin_value is Vector2:
				return []
			var origin := origin_value as Vector2
			if not is_finite(origin.x) or not is_finite(origin.y):
				return []
			centers.append(origin)
		return centers
	var impact_value: Variant = result.get("impact_position")
	if not impact_value is Vector2:
		return centers
	var impact := impact_value as Vector2
	if is_finite(impact.x) and is_finite(impact.y):
		centers.append(impact)
	return centers


func _combination_radius_tiles(parameters: Dictionary) -> float:
	return maxf(
		0.0,
		maxf(
			float(parameters.get("radius_tiles", 0.0)),
			maxf(
				float(parameters.get("freeze_radius_tiles", 0.0)),
				float(parameters.get("explosion_radius_tiles", 0.0))
			)
		)
	)


func _result_position(result: Dictionary, fallback: Vector2) -> Vector2:
	var value: Variant = result.get("impact_position")
	if value is Vector2:
		var position := value as Vector2
		if is_finite(position.x) and is_finite(position.y):
			return position
	return fallback


func _acquire_cast_invulnerability(token: int) -> bool:
	var owner_player := _owner_player()
	if owner_player == null:
		return false
	var health := owner_player.get_node_or_null("HealthComponent")
	if health == null or not health.has_method("acquire_invulnerability_source"):
		return false
	var source_id := StringName("staff_ultimate_cast_%d" % token)
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
