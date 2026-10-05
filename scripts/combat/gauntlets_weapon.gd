class_name GauntletsWeapon
extends Node2D

signal payload_result_reported(action_token: int, generation: int, result: Dictionary)
signal impact_feedback_requested(action_token: int, generation: int, fact: Dictionary)

const GauntletsHitExecutionScript := preload("res://scripts/combat/gauntlets_hit_execution.gd")
const GauntletsZoneExecutionScript := preload("res://scripts/combat/gauntlets_zone_execution.gd")
const GauntletsComboAuraScript := preload("res://scripts/combat/gauntlets_combo_aura.gd")
const WEAPON_ID := &"gauntlets"
const SNAPSHOT_SCHEMA_VERSION := 1
const PROFILE_ID := "gauntlets_launch_v1"
const VALID_ACTION_IDS: Array[String] = [
	"punch_1",
	"punch_2",
	"punch_3",
	"punch_4",
	"punch_5",
	"charged_heavy",
	"dodge_counter",
	"space_time_shatter",
	"primordial_collapse_punch",
]
const VALID_KINDS: Array[String] = ["hitbox", "shockwave"]
const FEEDBACK_FACT_LIMIT := 256
const CALLBACK_CLAIM_LIMIT := 512
const RUNTIME_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version", "profile_action", "profile_action_released", "prepared_payloads",
	"owned_payloads", "progress_claims", "progress_claim_order", "damage_claims",
	"damage_claim_order", "reported_claims", "reported_claim_order", "feedback_facts",
	"invulnerability_active", "invulnerability_source_id",
]
const PAYLOAD_SNAPSHOT_FIELDS: Array[String] = [
	"payload_type", "token", "generation", "global_position", "snapshot",
]

@export var owner_path: NodePath
@export var base_attack: float = 6.0
@export var attack_speed: float = 1.0
@export var character_attack_scale: float = 1.0
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 1.5

var _result_sink: Object
var _profile_action: Dictionary = {}
var _profile_action_released: bool = false
var _prepared_payloads: Array[Dictionary] = []
var _owned_payloads: Array[Node] = []
var _owned_payload_identity: Dictionary = {}
var _progress_claims: Dictionary = {}
var _progress_claim_order: Array[String] = []
var _damage_claims: Dictionary = {}
var _damage_claim_order: Array[String] = []
var _reported_claims: Dictionary = {}
var _reported_claim_order: Array[String] = []
var _feedback_facts: Array[Dictionary] = []
var _invulnerability_health: Node
var _invulnerability_source_id: StringName = &""
var _combo_slow_aura: Node


func weapon_id() -> StringName:
	return WEAPON_ID


func _ready() -> void:
	var owner_health := _owner_health()
	if owner_health != null and owner_health.has_signal("died"):
		var callback := Callable(self, "_on_owner_died")
		if not owner_health.is_connected("died", callback):
			owner_health.connect("died", callback)


func configure_result_sink(sink: Object) -> bool:
	if sink == null or not is_instance_valid(sink) or not sink.has_method("handle_payload_result"):
		return false
	_result_sink = sink
	return true


func begin_profile_action(definition: Dictionary) -> Dictionary:
	_prune_owned_payloads()
	if is_profile_action_active() or not _definition_is_valid(definition):
		return {}
	var prepared: Array[Dictionary] = []
	for descriptor_value: Variant in definition["payload_descriptors"]:
		var descriptor := descriptor_value as Dictionary
		var payload := _prepare_hit_payload(descriptor, definition)
		if payload.is_empty():
			_free_prepared(prepared)
			return {}
		prepared.append(payload)
	if (
		bool(definition.get("invulnerable_during_cast", false))
		and str(definition.get("action_id", "")) == "primordial_collapse_punch"
	):
		if not _acquire_cast_invulnerability(int(definition["token"]), int(definition["generation"])):
			_free_prepared(prepared)
			return {}
	_profile_action = definition.duplicate(true)
	_profile_action_released = false
	_prepared_payloads = prepared
	return definition.duplicate(true)


func release_profile_action() -> bool:
	if _profile_action.is_empty() or _profile_action_released:
		return false
	var parent := get_tree().current_scene if is_inside_tree() else null
	if parent == null:
		return false
	if (
		bool(_profile_action.get("invulnerable_during_cast", false))
		and str(_profile_action.get("action_id", "")) == "dodge_counter"
		and _invulnerability_source_id == &""
		and not _acquire_cast_invulnerability(
			int(_profile_action["token"]),
			int(_profile_action["generation"])
		)
	):
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
		_clear_payloads_for_action(token, generation, false)
	_clear_profile_action()


func cancel_for_gameplay_rewind() -> bool:
	var guard := gameplay_rewind_committed_payload_guard()
	_free_prepared(_prepared_payloads)
	_prepared_payloads.clear()
	_clear_profile_action()
	return gameplay_rewind_committed_payload_guard() == guard


func gameplay_rewind_snapshot() -> Dictionary:
	var full := runtime_snapshot()
	if full.is_empty():
		return {}
	return {
		"profile_action": (full["profile_action"] as Dictionary).duplicate(true),
		"profile_action_released": bool(full["profile_action_released"]),
		"prepared_payloads": (full["prepared_payloads"] as Array).duplicate(true),
		"committed_payload_guard": gameplay_rewind_committed_payload_guard(),
	}


func restore_gameplay_rewind_snapshot_for_rollback(value: Dictionary) -> bool:
	if (
		not value.get("profile_action") is Dictionary
		or typeof(value.get("profile_action_released")) != TYPE_BOOL
		or not value.get("prepared_payloads") is Array
		or not value.get("committed_payload_guard") is Dictionary
		or value["committed_payload_guard"] != gameplay_rewind_committed_payload_guard()
	):
		return false
	var current := runtime_snapshot()
	if current.is_empty():
		return false
	var target := current.duplicate(true)
	target["profile_action"] = (value["profile_action"] as Dictionary).duplicate(true)
	target["profile_action_released"] = bool(value["profile_action_released"])
	target["prepared_payloads"] = (value["prepared_payloads"] as Array).duplicate(true)
	if not can_restore_runtime_snapshot(target):
		return false
	var dependencies := {
		"source": self,
		"owner_entity": _owner_player(),
		"progress_claims": _progress_claims,
		"progress_claim_order": _progress_claim_order,
		"damage_claims": _damage_claims,
		"damage_claim_order": _damage_claim_order,
	}
	var staged: Array[Dictionary] = []
	for entry_value: Variant in value["prepared_payloads"] as Array:
		var prepared := _restore_payload_entry(entry_value as Dictionary, dependencies)
		if prepared.is_empty():
			_free_prepared(staged)
			return false
		staged.append(prepared)
	var action := value["profile_action"] as Dictionary
	if (
		not action.is_empty()
		and bool(action.get("invulnerable_during_cast", false))
		and not _acquire_cast_invulnerability(
			int(action.get("token", 0)),
			int(action.get("generation", 0))
		)
	):
		_free_prepared(staged)
		return false
	_free_prepared(_prepared_payloads)
	_prepared_payloads = staged
	_profile_action = action.duplicate(true)
	_profile_action_released = bool(value["profile_action_released"])
	return gameplay_rewind_snapshot() == value


func gameplay_rewind_committed_payload_guard() -> Dictionary:
	_prune_owned_payloads()
	var instance_ids: Array[int] = []
	var payloads: Array[Dictionary] = []
	for payload: Node in _owned_payloads:
		var payload_type := "zone" if payload.is_in_group("gauntlets_zones") else "hit"
		var entry := _payload_snapshot_entry(
			payload,
			(payload as Node2D).global_position if payload is Node2D else Vector2.ZERO,
			payload_type
		)
		if entry.is_empty():
			return {}
		instance_ids.append(payload.get_instance_id())
		payloads.append(entry)
	return {
		"instance_ids": instance_ids,
		"owned_payloads": payloads,
		"progress_claims": _progress_claims.duplicate(true),
		"progress_claim_order": _progress_claim_order.duplicate(),
		"damage_claims": _damage_claims.duplicate(true),
		"damage_claim_order": _damage_claim_order.duplicate(),
		"reported_claims": _reported_claims.duplicate(true),
		"reported_claim_order": _reported_claim_order.duplicate(),
		"feedback_facts": _feedback_facts.duplicate(true),
	}


func finish_profile_action() -> void:
	var token := int(_profile_action.get("token", 0))
	var generation := int(_profile_action.get("generation", 0))
	_free_prepared(_prepared_payloads)
	_prepared_payloads.clear()
	if token > 0 and generation > 0:
		_clear_payloads_for_action(token, generation, true)
	_clear_profile_action()


func reset_runtime_state() -> void:
	_free_prepared(_prepared_payloads)
	_prepared_payloads.clear()
	_clear_owned_payloads()
	_clear_combo_slow_aura()
	_progress_claims.clear()
	_progress_claim_order.clear()
	_damage_claims.clear()
	_damage_claim_order.clear()
	_reported_claims.clear()
	_reported_claim_order.clear()
	_feedback_facts.clear()
	_clear_profile_action()


func prepared_payload_count_for_test() -> int:
	return _prepared_payloads.size()


func prepared_payload_snapshots_for_test() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for prepared: Dictionary in _prepared_payloads:
		var payload_value: Variant = prepared.get("node")
		if payload_value is Node and is_instance_valid(payload_value) and (payload_value as Node).has_method("execution_snapshot"):
			result.append(((payload_value as Node).call("execution_snapshot") as Dictionary).duplicate(true))
	return result


func owned_payload_count_for_test() -> int:
	_prune_owned_payloads()
	return _owned_payloads.size()


func owned_payloads_for_test() -> Array[Node]:
	_prune_owned_payloads()
	return _owned_payloads.duplicate()


func feedback_facts_for_test() -> Array[Dictionary]:
	return _feedback_facts.duplicate(true)


func runtime_snapshot() -> Dictionary:
	_prune_owned_payloads()
	var prepared_payloads: Array[Dictionary] = []
	for prepared: Dictionary in _prepared_payloads:
		var entry := _payload_snapshot_entry(prepared.get("node"), prepared.get("global_position", Vector2.ZERO), "hit")
		if not entry.is_empty():
			prepared_payloads.append(entry)
	var owned_payloads: Array[Dictionary] = []
	for payload: Node in _owned_payloads:
		var payload_type := "zone" if payload.is_in_group("gauntlets_zones") else "hit"
		var entry := _payload_snapshot_entry(payload, (payload as Node2D).global_position if payload is Node2D else Vector2.ZERO, payload_type)
		if not entry.is_empty():
			owned_payloads.append(entry)
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"profile_action": _profile_action.duplicate(true),
		"profile_action_released": _profile_action_released,
		"prepared_payloads": prepared_payloads,
		"owned_payloads": owned_payloads,
		"progress_claims": _progress_claims.duplicate(true),
		"progress_claim_order": _progress_claim_order.duplicate(),
		"damage_claims": _damage_claims.duplicate(true),
		"damage_claim_order": _damage_claim_order.duplicate(),
		"reported_claims": _reported_claims.duplicate(true),
		"reported_claim_order": _reported_claim_order.duplicate(),
		"feedback_facts": _feedback_facts.duplicate(true),
		"invulnerability_active": _invulnerability_source_id != &"",
		"invulnerability_source_id": str(_invulnerability_source_id),
	}


func can_restore_runtime_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields(value, RUNTIME_SNAPSHOT_FIELDS):
		return false
	if (
		int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION
		or not value.get("profile_action") is Dictionary
		or typeof(value.get("profile_action_released")) != TYPE_BOOL
		or not value.get("prepared_payloads") is Array
		or not value.get("owned_payloads") is Array
		or not value.get("progress_claims") is Dictionary
		or not value.get("progress_claim_order") is Array
		or not value.get("damage_claims") is Dictionary
		or not value.get("damage_claim_order") is Array
		or not value.get("reported_claims") is Dictionary
		or not value.get("reported_claim_order") is Array
		or not value.get("feedback_facts") is Array
		or (value.get("feedback_facts") as Array).size() > FEEDBACK_FACT_LIMIT
		or typeof(value.get("invulnerability_active")) != TYPE_BOOL
		or typeof(value.get("invulnerability_source_id")) != TYPE_STRING
		or not _variant_numbers_are_finite(value)
	):
		return false
	if (
		not _valid_claim_snapshot(value["progress_claims"], value["progress_claim_order"], CALLBACK_CLAIM_LIMIT)
		or not _valid_claim_snapshot(value["damage_claims"], value["damage_claim_order"], CALLBACK_CLAIM_LIMIT)
		or not _valid_claim_snapshot(value["reported_claims"], value["reported_claim_order"], CALLBACK_CLAIM_LIMIT)
	):
		return false
	var profile_action := value["profile_action"] as Dictionary
	var released := bool(value["profile_action_released"])
	if profile_action.is_empty():
		if released or not (value["prepared_payloads"] as Array).is_empty():
			return false
	elif not _definition_is_valid(profile_action):
		return false
	if released and not (value["prepared_payloads"] as Array).is_empty():
		return false
	if not released and not profile_action.is_empty() and (value["prepared_payloads"] as Array).size() != (profile_action["payload_descriptors"] as Array).size():
		return false
	for prepared_value: Variant in value["prepared_payloads"]:
		if not _valid_payload_snapshot_entry(prepared_value, "hit"):
			return false
	for owned_value: Variant in value["owned_payloads"]:
		if not _valid_payload_snapshot_entry(owned_value):
			return false
	var invulnerability_active := bool(value["invulnerability_active"])
	var source_id := str(value["invulnerability_source_id"])
	if invulnerability_active != (not source_id.is_empty()):
		return false
	if invulnerability_active:
		if profile_action.is_empty() or source_id != "gauntlets_cast:%d:%d" % [int(profile_action["token"]), int(profile_action["generation"])]:
			return false
	return true


func restore_runtime_snapshot(value: Dictionary) -> bool:
	if not can_restore_runtime_snapshot(value):
		return false
	var previous := runtime_snapshot()
	if previous == value:
		return true
	if not _apply_runtime_snapshot(value):
		_apply_runtime_snapshot(previous)
		return false
	if runtime_snapshot() != value:
		_apply_runtime_snapshot(previous)
		return false
	return true


func set_combo_slow_aura(active: bool, source_generation: int) -> bool:
	if not active:
		if _combo_slow_aura == null or not is_instance_valid(_combo_slow_aura):
			_combo_slow_aura = null
			return true
		if source_generation > 0 and int(_combo_slow_aura.get("source_generation")) != source_generation:
			return false
		_clear_combo_slow_aura()
		return true
	if source_generation <= 0:
		return false
	if (
		_combo_slow_aura != null
		and is_instance_valid(_combo_slow_aura)
		and int(_combo_slow_aura.get("source_generation")) == source_generation
	):
		return true
	_clear_combo_slow_aura()
	var aura = GauntletsComboAuraScript.new()
	if not bool(aura.call("configure_execution", _owner_player(), source_generation)):
		aura.free()
		return false
	add_child(aura)
	aura.position = Vector2.ZERO
	_combo_slow_aura = aura
	return true


func advance_combo_slow_aura_for_test(frames: int) -> void:
	if _combo_slow_aura != null and is_instance_valid(_combo_slow_aura):
		_combo_slow_aura.call("advance_execution_for_test", frames)


func combo_slow_aura_snapshot_for_test() -> Dictionary:
	if _combo_slow_aura == null or not is_instance_valid(_combo_slow_aura):
		_combo_slow_aura = null
		return {}
	return (_combo_slow_aura.call("execution_snapshot") as Dictionary).duplicate(true)


func _prepare_hit_payload(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	var execution := _hit_execution(descriptor, definition)
	if execution.is_empty():
		return {}
	var payload = GauntletsHitExecutionScript.new()
	if not bool(payload.call("configure_execution", execution)):
		payload.free()
		return {}
	payload.payload_result.connect(_on_payload_result.bind(payload))
	payload.execution_finished.connect(_on_hit_execution_finished.bind(payload))
	return {
		"node": payload,
		"global_position": global_position,
		"token": int(definition["token"]),
		"generation": int(definition["generation"]),
	}


func _hit_execution(descriptor: Dictionary, definition: Dictionary) -> Dictionary:
	return {
		"action_token": int(definition["token"]),
		"generation": int(definition["generation"]),
		"source_action_id": str(definition["action_id"]),
		"descriptor_id": str(descriptor["descriptor_id"]),
		"outcome_id": str(descriptor.get("outcome_id", "%s:%d" % [str(descriptor["descriptor_id"]), int(descriptor["outcome_index"])])),
		"outcome_index": int(descriptor["outcome_index"]),
		"deterministic_seed": int(descriptor["seed"]),
		"kind": str(descriptor["kind"]),
		"parameters": (descriptor["parameters"] as Dictionary).duplicate(true),
		"base_attack": float(definition["base_attack"]),
		"direction": (definition["aim_direction"] as Vector2).normalized(),
		"target_deduplication": str(descriptor.get("target_deduplication", "per_action_target")),
		"boss_conversion": (definition.get("boss_conversion", {}) as Dictionary).duplicate(true),
		"source": self,
		"owner_entity": _owner_player(),
		"progress_claims": _progress_claims,
		"progress_claim_order": _progress_claim_order,
		"damage_claims": _damage_claims,
		"damage_claim_order": _damage_claim_order,
	}


func _on_payload_result(
	action_token: int,
	generation: int,
	result: Dictionary,
	payload: Node
) -> void:
	if not _payload_callback_is_live(payload, action_token, generation):
		return
	var claim_id := str(result.get("claim_id", ""))
	if claim_id.is_empty():
		return
	var report_key := "%d:%d:%s" % [action_token, generation, claim_id]
	if _reported_claims.has(report_key):
		return
	while _reported_claim_order.size() >= CALLBACK_CLAIM_LIMIT:
		var expired_key: String = _reported_claim_order.pop_front()
		_reported_claims.erase(expired_key)
	_reported_claims[report_key] = true
	_reported_claim_order.append(report_key)
	var frozen := result.duplicate(true)
	var zone_value: Variant = frozen.get("spawn_zone", {})
	if zone_value is Dictionary and not (zone_value as Dictionary).is_empty():
		_spawn_zone(action_token, generation, frozen, zone_value as Dictionary, payload)
	var runtime_response: Dictionary = {}
	if _result_sink != null and is_instance_valid(_result_sink):
		var response_value: Variant = _result_sink.call("handle_payload_result", action_token, generation, frozen.duplicate(true))
		if response_value is Dictionary:
			runtime_response = (response_value as Dictionary).duplicate(true)
	_record_feedback_fact(action_token, generation, frozen, payload)
	if not bool(frozen.get("is_echo", false)):
		var echo_value: Variant = runtime_response.get("echo_descriptor", {})
		if echo_value is Dictionary and not (echo_value as Dictionary).is_empty():
			_spawn_echo(action_token, generation, frozen, echo_value as Dictionary, payload)
	payload_result_reported.emit(action_token, generation, frozen)


func _on_hit_execution_finished(action_token: int, generation: int, payload: Node) -> void:
	if not _payload_callback_is_live(payload, action_token, generation):
		return
	if (
		str(_profile_action.get("action_id", "")) == "dodge_counter"
		and int(_profile_action.get("token", 0)) == action_token
		and int(_profile_action.get("generation", 0)) == generation
	):
		_release_cast_invulnerability()


func _spawn_echo(
	action_token: int,
	generation: int,
	result: Dictionary,
	descriptor_value: Dictionary,
	payload: Node
) -> void:
	var descriptor := descriptor_value.duplicate(true)
	var parameters_value: Variant = descriptor.get("parameters", {})
	if not parameters_value is Dictionary:
		return
	var parameters := (parameters_value as Dictionary).duplicate(true)
	parameters["combo_eligible"] = false
	parameters["energy_eligible"] = false
	parameters["stop_extension_eligible"] = false
	parameters["recursive_echo"] = false
	parameters["is_echo"] = true
	descriptor["parameters"] = parameters
	descriptor["token"] = action_token
	descriptor["generation"] = generation
	var definition := {
		"token": action_token,
		"generation": generation,
		"action_id": str(payload.get("source_action_id")),
		"aim_direction": payload.get("direction"),
		"base_attack": float(payload.get("base_attack")),
		"boss_conversion": {},
	}
	if not _descriptor_is_valid(descriptor, action_token, generation):
		return
	var prepared := _prepare_hit_payload(descriptor, definition)
	if prepared.is_empty():
		return
	prepared["global_position"] = result.get("impact_position", payload.global_position)
	var parent := get_tree().current_scene if is_inside_tree() else null
	if parent != null:
		_attach_payload(prepared, parent)
	else:
		_free_prepared([prepared])


func _spawn_zone(
	action_token: int,
	generation: int,
	_result: Dictionary,
	zone_descriptor: Dictionary,
	payload: Node
) -> void:
	var parameters_value: Variant = zone_descriptor.get("parameters", {})
	if not parameters_value is Dictionary:
		return
	var execution := {
		"action_token": action_token,
		"generation": generation,
		"source_action_id": str(payload.get("source_action_id")),
		"descriptor_id": str(zone_descriptor.get("descriptor_id", "%s:zone" % str(payload.get("descriptor_id")))),
		"outcome_id": str(zone_descriptor.get("outcome_id", "%s:zone" % str(payload.get("outcome_id")))),
		"outcome_index": int(zone_descriptor.get("outcome_index", payload.get("outcome_index"))),
		"deterministic_seed": int(zone_descriptor.get("seed", payload.get("deterministic_seed"))),
		"mode": str((parameters_value as Dictionary).get("mode", "space_time_shatter")),
		"parameters": (parameters_value as Dictionary).duplicate(true),
		"base_attack": float(payload.get("base_attack")),
		"source": self,
		"owner_entity": _owner_player(),
	}
	var zone = GauntletsZoneExecutionScript.new()
	if not bool(zone.call("configure_execution", execution)):
		zone.free()
		return
	zone.payload_result.connect(_on_payload_result.bind(zone))
	var prepared := {
		"node": zone,
		"global_position": zone_descriptor.get("position", payload.global_position),
		"token": action_token,
		"generation": generation,
	}
	var parent := get_tree().current_scene if is_inside_tree() else null
	if parent != null:
		_attach_payload(prepared, parent)
	else:
		_free_prepared([prepared])


func _attach_payload(prepared: Dictionary, parent: Node) -> void:
	var payload := prepared["node"] as Node
	parent.add_child(payload)
	if payload is Node2D:
		(payload as Node2D).global_position = prepared["global_position"]
	_owned_payloads.append(payload)
	_owned_payload_identity[payload.get_instance_id()] = {
		"token": int(prepared["token"]),
		"generation": int(prepared["generation"]),
	}


func _record_feedback_fact(
	action_token: int,
	generation: int,
	result: Dictionary,
	payload: Node
) -> void:
	if not bool(result.get("hit", false)):
		return
	var fact := {
		"weapon_id": "gauntlets",
		"action_id": str(payload.get("source_action_id")),
		"action_token": action_token,
		"generation": generation,
		"descriptor_id": str(result.get("descriptor_id", "")),
		"outcome_index": int(result.get("outcome_index", -1)),
		"target_id": int(result.get("target_id", -1)),
		"damage": float(result.get("damage", 0.0)),
		"impact_position": result.get("impact_position", Vector2.ZERO),
		"deterministic_seed": int(result.get("deterministic_seed", 0)),
		"is_echo": bool(result.get("is_echo", false)),
		"impact_tier": _impact_tier(str(payload.get("source_action_id"))),
	}
	_feedback_facts.append(fact)
	while _feedback_facts.size() > FEEDBACK_FACT_LIMIT:
		_feedback_facts.pop_front()
	impact_feedback_requested.emit(action_token, generation, fact.duplicate(true))


func _impact_tier(action_id: String) -> String:
	if action_id == "primordial_collapse_punch":
		return "ultimate"
	if action_id in ["punch_5", "charged_heavy", "dodge_counter", "space_time_shatter"]:
		return "heavy"
	if action_id in ["punch_3", "punch_4"]:
		return "medium"
	return "light"


func _definition_is_valid(definition: Dictionary) -> bool:
	if (
		str(definition.get("profile_id", "")) != PROFILE_ID
		or str(definition.get("weapon_id", "")) != "gauntlets"
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
		and str(descriptor.get("kind", "")) in VALID_KINDS
		and typeof(descriptor.get("token")) == TYPE_INT
		and int(descriptor.get("token", 0)) == token
		and typeof(descriptor.get("generation")) == TYPE_INT
		and int(descriptor.get("generation", 0)) == generation
		and typeof(descriptor.get("outcome_index")) == TYPE_INT
		and int(descriptor.get("outcome_index", -1)) >= 0
		and typeof(descriptor.get("seed")) == TYPE_INT
		and str(descriptor.get("target_deduplication", "per_action_target")) == "per_action_target"
		and descriptor.get("parameters", {}) is Dictionary
	)


func _owner_player() -> Node:
	if owner_path != NodePath(""):
		var configured_owner := get_node_or_null(owner_path)
		if configured_owner != null:
			return configured_owner
	return get_parent()


func _owner_health() -> Node:
	var owner_player := _owner_player()
	return owner_player.get_node_or_null("HealthComponent") if owner_player != null else null


func _acquire_cast_invulnerability(token: int, generation: int) -> bool:
	var owner_player := _owner_player()
	if owner_player == null:
		return false
	var health := owner_player.get_node_or_null("HealthComponent")
	if health == null or not health.has_method("acquire_invulnerability_source"):
		return false
	var source_id := StringName("gauntlets_cast:%d:%d" % [token, generation])
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


func _clear_combo_slow_aura() -> void:
	if _combo_slow_aura != null and is_instance_valid(_combo_slow_aura):
		if _combo_slow_aura.has_method("reset_execution_state"):
			_combo_slow_aura.call("reset_execution_state")
		_combo_slow_aura.queue_free()
	_combo_slow_aura = null


func _on_owner_died(_killer: Variant) -> void:
	_clear_combo_slow_aura()
	_release_cast_invulnerability()


func _payload_callback_is_live(payload: Node, action_token: int, generation: int) -> bool:
	if payload == null or not is_instance_valid(payload) or payload.is_queued_for_deletion():
		return false
	var identity_value: Variant = _owned_payload_identity.get(payload.get_instance_id(), {})
	if not identity_value is Dictionary:
		return false
	var identity := identity_value as Dictionary
	return int(identity.get("token", 0)) == action_token and int(identity.get("generation", 0)) == generation


func _clear_payloads_for_action(token: int, generation: int, preserve_zones: bool) -> void:
	for payload: Node in _owned_payloads.duplicate():
		if payload == null or not is_instance_valid(payload):
			continue
		var identity: Dictionary = _owned_payload_identity.get(payload.get_instance_id(), {})
		if int(identity.get("token", 0)) != token or int(identity.get("generation", 0)) != generation:
			continue
		if preserve_zones and payload.is_in_group("gauntlets_zones"):
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
	var survivors: Array[Node] = []
	var identities: Dictionary = {}
	for payload: Node in _owned_payloads:
		if payload == null or not is_instance_valid(payload) or payload.is_queued_for_deletion():
			continue
		survivors.append(payload)
		var instance_id := payload.get_instance_id()
		if _owned_payload_identity.has(instance_id):
			identities[instance_id] = _owned_payload_identity[instance_id]
	_owned_payloads = survivors
	_owned_payload_identity = identities


func _payload_snapshot_entry(payload_value: Variant, world_position: Variant, payload_type: String) -> Dictionary:
	if (
		not payload_value is Node
		or not is_instance_valid(payload_value)
		or not (payload_value as Node).has_method("execution_snapshot")
		or not world_position is Vector2
	):
		return {}
	var payload := payload_value as Node
	var snapshot_value: Variant = payload.call("execution_snapshot")
	if not snapshot_value is Dictionary:
		return {}
	return {
		"payload_type": payload_type,
		"token": int(payload.get("action_token")),
		"generation": int(payload.get("generation")),
		"global_position": world_position,
		"snapshot": (snapshot_value as Dictionary).duplicate(true),
	}


func _valid_payload_snapshot_entry(value: Variant, expected_type: String = "") -> bool:
	if not value is Dictionary:
		return false
	var entry := value as Dictionary
	if not _has_exact_fields(entry, PAYLOAD_SNAPSHOT_FIELDS):
		return false
	var payload_type := str(entry.get("payload_type", ""))
	if (
		payload_type not in ["hit", "zone"]
		or (not expected_type.is_empty() and payload_type != expected_type)
		or typeof(entry.get("token")) != TYPE_INT
		or int(entry.get("token", 0)) <= 0
		or typeof(entry.get("generation")) != TYPE_INT
		or int(entry.get("generation", 0)) <= 0
		or not entry.get("global_position") is Vector2
		or not entry.get("snapshot") is Dictionary
	):
		return false
	var payload_snapshot := entry["snapshot"] as Dictionary
	if (
		int(entry["token"]) != int(payload_snapshot.get("action_token", 0))
		or int(entry["generation"]) != int(payload_snapshot.get("generation", 0))
	):
		return false
	var payload = GauntletsZoneExecutionScript.new() if payload_type == "zone" else GauntletsHitExecutionScript.new()
	var valid := bool(payload.call("can_restore_execution_snapshot", payload_snapshot.duplicate(true)))
	payload.free()
	return valid


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _apply_runtime_snapshot(value: Dictionary) -> bool:
	if not can_restore_runtime_snapshot(value):
		return false
	var parent := get_tree().current_scene if is_inside_tree() else null
	if not (value["owned_payloads"] as Array).is_empty() and parent == null:
		return false
	var next_progress_claims := (value["progress_claims"] as Dictionary).duplicate(true)
	var next_progress_order: Array = (value["progress_claim_order"] as Array).duplicate()
	var next_damage_claims := (value["damage_claims"] as Dictionary).duplicate(true)
	var next_damage_order: Array = (value["damage_claim_order"] as Array).duplicate()
	var dependencies := {
		"source": self,
		"owner_entity": _owner_player(),
		"progress_claims": next_progress_claims,
		"progress_claim_order": next_progress_order,
		"damage_claims": next_damage_claims,
		"damage_claim_order": next_damage_order,
	}
	var staged_prepared: Array[Dictionary] = []
	for entry_value: Variant in value["prepared_payloads"]:
		var restored := _restore_payload_entry(entry_value as Dictionary, dependencies)
		if restored.is_empty():
			_free_prepared(staged_prepared)
			return false
		staged_prepared.append(restored)
	var staged_owned: Array[Dictionary] = []
	for entry_value: Variant in value["owned_payloads"]:
		var restored := _restore_payload_entry(entry_value as Dictionary, dependencies)
		if restored.is_empty():
			_free_prepared(staged_prepared)
			_free_prepared(staged_owned)
			return false
		staged_owned.append(restored)
	var wants_invulnerability := bool(value["invulnerability_active"])
	var desired_source_id := StringName(str(value["invulnerability_source_id"]))
	var keep_invulnerability := wants_invulnerability and desired_source_id == _invulnerability_source_id
	var staged_invulnerability_health: Node = null
	if wants_invulnerability and not keep_invulnerability:
		staged_invulnerability_health = _owner_health()
		if (
			staged_invulnerability_health == null
			or not staged_invulnerability_health.has_method("acquire_invulnerability_source")
			or not bool(staged_invulnerability_health.call("acquire_invulnerability_source", desired_source_id))
		):
			_free_prepared(staged_prepared)
			_free_prepared(staged_owned)
			return false
	_free_prepared(_prepared_payloads)
	_prepared_payloads.clear()
	_clear_owned_payloads()
	if not keep_invulnerability:
		_release_cast_invulnerability()
		if wants_invulnerability:
			_invulnerability_health = staged_invulnerability_health
			_invulnerability_source_id = desired_source_id
	_progress_claims = next_progress_claims
	_progress_claim_order = next_progress_order
	_damage_claims = next_damage_claims
	_damage_claim_order = next_damage_order
	_reported_claims = (value["reported_claims"] as Dictionary).duplicate(true)
	_reported_claim_order = (value["reported_claim_order"] as Array).duplicate()
	_feedback_facts = (value["feedback_facts"] as Array).duplicate(true)
	_profile_action = (value["profile_action"] as Dictionary).duplicate(true)
	_profile_action_released = bool(value["profile_action_released"])
	_prepared_payloads = staged_prepared
	for prepared: Dictionary in staged_owned:
		_attach_payload(prepared, parent)
	return true


func _restore_payload_entry(entry: Dictionary, dependencies: Dictionary) -> Dictionary:
	var payload_type := str(entry["payload_type"])
	var payload = GauntletsZoneExecutionScript.new() if payload_type == "zone" else GauntletsHitExecutionScript.new()
	if payload is Node2D:
		(payload as Node2D).global_position = entry["global_position"]
	if not bool(payload.call(
		"restore_execution_snapshot",
		(entry["snapshot"] as Dictionary).duplicate(true),
		dependencies
	)):
		payload.free()
		return {}
	payload.payload_result.connect(_on_payload_result.bind(payload))
	if payload_type == "hit":
		payload.execution_finished.connect(_on_hit_execution_finished.bind(payload))
	return {
		"node": payload,
		"global_position": entry["global_position"],
		"token": int(entry["token"]),
		"generation": int(entry["generation"]),
	}


func _valid_claim_snapshot(claims_value: Variant, order_value: Variant, limit: int) -> bool:
	if not claims_value is Dictionary or not order_value is Array:
		return false
	var claims := claims_value as Dictionary
	var order := order_value as Array
	if claims.size() != order.size() or order.size() > limit:
		return false
	var seen: Dictionary = {}
	for key_value: Variant in order:
		if typeof(key_value) != TYPE_STRING or str(key_value).is_empty() or seen.has(str(key_value)) or not claims.has(str(key_value)):
			return false
		if typeof(claims[str(key_value)]) != TYPE_BOOL or not bool(claims[str(key_value)]):
			return false
		seen[str(key_value)] = true
	return true


func _variant_numbers_are_finite(value: Variant) -> bool:
	if value is Vector2:
		return is_finite((value as Vector2).x) and is_finite((value as Vector2).y)
	if typeof(value) == TYPE_FLOAT:
		return is_finite(float(value))
	if value is Dictionary:
		for child: Variant in (value as Dictionary).values():
			if not _variant_numbers_are_finite(child):
				return false
	if value is Array:
		for child: Variant in value:
			if not _variant_numbers_are_finite(child):
				return false
	return true


func _free_prepared(prepared_payloads: Array) -> void:
	for prepared_value: Variant in prepared_payloads:
		if not prepared_value is Dictionary:
			continue
		var node_value: Variant = (prepared_value as Dictionary).get("node")
		if node_value is Node and is_instance_valid(node_value):
			if (node_value as Node).has_method("reset_execution_state"):
				(node_value as Node).call("reset_execution_state")
			(node_value as Node).free()
	prepared_payloads.clear()


func _clear_profile_action() -> void:
	_profile_action.clear()
	_profile_action_released = false
	_release_cast_invulnerability()


func _exit_tree() -> void:
	reset_runtime_state()


func _positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0
