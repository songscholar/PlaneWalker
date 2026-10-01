class_name TimeGuardianCharacterRuntime
extends "res://scripts/player/characters/character_runtime.gd"

const CharacterPayloadExecutionScript := preload(
	"res://scripts/combat/character_payload_execution.gd"
)
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

const CHARACTER_ID := &"time_guardian"
const PROFILE_ID := "time_guardian_launch_v1"
const STRATEGY_SNAPSHOT_SCHEMA_VERSION := 1
const STRATEGY_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"runtime_kind",
	"configured",
	"last_runtime_frame",
	"revision",
	"resource_value",
	"run_id",
	"run_revision",
	"owner_character_generation",
	"skill_cooldown_until_frame",
	"skill_action",
	"guard_resolved",
	"fortress_until_frame",
	"fortress_shockwave_armed",
	"ward_claims",
	"ward_consumption_claims",
	"mastery_claims",
	"rebuke_until_frame",
	"rebuke_source_token",
	"rebuke_from_full_ward",
	"stop_exposure_claims",
	"rift_anchor_claims",
	"next_payload_generation",
]

var _run_id: StringName = &""
var _run_revision: int = 0
var _owner_character_generation: int = 1
var _skill_cooldown_until_frame: int = -1
var _skill_action: Dictionary = {}
var _guard_resolved: bool = false
var _fortress_until_frame: int = -1
var _fortress_shockwave_armed: bool = false
var _ward_claims: Array[String] = []
var _ward_consumption_claims: Array[String] = []
var _mastery_claims: Array[String] = []
var _rebuke_until_frame: int = -1
var _rebuke_source_token: int = 0
var _rebuke_from_full_ward: bool = false
var _stop_exposure_claims: Array[int] = []
var _rift_anchor_claims: Array[int] = []
var _next_payload_generation: int = 1


func _init() -> void:
	_runtime_kind = &"time_guardian"


func configure(owner: Node, profile: Variant, talents: PackedStringArray) -> bool:
	if profile == null or not profile is RefCounted or not profile.has_method("snapshot"):
		return false
	var profile_value: Variant = profile.call("snapshot")
	if (
		not profile_value is Dictionary
		or str((profile_value as Dictionary).get("character_id", "")) != str(CHARACTER_ID)
		or str((profile_value as Dictionary).get("runtime_kind", "")) != "time_guardian"
		or str(((profile_value as Dictionary).get("character_skill", {}) as Dictionary).get("handler_id", "")) != "chrono_fortress"
	):
		return false
	if not super.configure(owner, profile, talents):
		return false
	_reset_strategy_state()
	_revision = 0
	return true


func reset_runtime_state(_reason: StringName) -> void:
	if not _configured:
		return
	super.reset_runtime_state(_reason)
	_reset_strategy_state()


func advance_frame(context: Dictionary) -> Array[Dictionary]:
	if not _valid_next_frame(context):
		return []
	var runtime_frame := int(context["runtime_frame"])
	super.advance_frame(context)
	var events: Array[Dictionary] = []

	if _rebuke_until_frame >= 0 and runtime_frame >= _rebuke_until_frame:
		_clear_rebuke()
		events.append(_event(&"rebuke_window_expired", runtime_frame, 0, {}))
	if _fortress_until_frame >= 0 and runtime_frame >= _fortress_until_frame:
		_fortress_until_frame = -1
		_fortress_shockwave_armed = false
		_skill_action.clear()
		events.append(_event(&"fortress_expired", runtime_frame, 0, {
			"movement_multiplier": 1.0,
		}))

	if (
		not _skill_action.is_empty()
		and not bool(_skill_action.get("committed", false))
		and runtime_frame >= int(_skill_action.get("fortress_check_frame", 0))
	):
		var check_frame := int(_skill_action["fortress_check_frame"])
		var token := int(_skill_action.get("token", 0))
		var energy_value: Variant = context.get("time_energy", -1.0)
		var ward_cost := _fortress_ward_cost()
		if (
			_finite_number(energy_value)
			and float(energy_value) >= _skill_energy_cost()
			and int(_resource_value) >= ward_cost
		):
			_resource_value = int(_resource_value) - ward_cost
			_fortress_until_frame = check_frame + _skill_parameter_int("duration_frames")
			_skill_cooldown_until_frame = check_frame + _skill_parameter_int(
				"fortress_cooldown_frames"
			)
			_skill_action["committed"] = true
			_skill_action["fortress_until_frame"] = _fortress_until_frame
			events.append(_resource_event(check_frame, token, &"fortress_cost"))
			events.append(_event(&"time_energy_spend_requested", check_frame, token, {
				"amount": _skill_energy_cost(),
				"reason": &"chrono_fortress",
			}))
			events.append(_event(&"fortress_committed", check_frame, token, {
				"active_until_frame": _fortress_until_frame,
				"movement_multiplier": _skill_parameter_float("movement_multiplier"),
				"frontal_reduction": _skill_parameter_float("frontal_reduction"),
				"frontal_cone_degrees": _skill_parameter_float("frontal_cone_degrees"),
			}))
			events.append(_cooldown_event(
				check_frame,
				_skill_parameter_int("fortress_cooldown_frames"),
				&"fortress_committed"
			))
		else:
			_skill_action.clear()
			_skill_cooldown_until_frame = check_frame + _ordinary_cooldown_frames()
			events.append(_event(&"fortress_resource_check_failed", check_frame, token, {
				"required_ward": ward_cost,
				"required_energy": _skill_energy_cost(),
			}))
			events.append(_cooldown_event(
				check_frame,
				_ordinary_cooldown_frames(),
				&"fortress_resource_check_failed"
			))
		_revision += 1
	return events


func plan_character_skill(intent: Dictionary, context: Dictionary) -> Dictionary:
	if intent.is_empty() and context.is_empty():
		return {"ok": false, "code": "unsupported"}
	if not _configured or not _valid_skill_intent(intent) or not _valid_live_context(context):
		return {"ok": false, "code": "invalid_context"}
	var edge := StringName(str(intent["edge"]))
	var runtime_frame := int(context["runtime_frame"])
	if edge == &"pressed":
		if not _skill_action.is_empty():
			return {"ok": false, "code": "action_active"}
		if _skill_cooldown_until_frame >= 0 and runtime_frame < _skill_cooldown_until_frame:
			return {"ok": false, "code": "cooldown_active"}
		return {
			"ok": true,
			"code": "planned",
			"plan": {
				"skill_id": &"chrono_fortress",
				"action_mode": &"begin_guard",
				"runtime_frame": runtime_frame,
				"fortress_check_frame": runtime_frame + _hold_threshold_frames(),
				"run_id": StringName(context["run_id"]),
				"run_revision": int(context["run_revision"]),
				"owner_character_generation": int(context["owner_character_generation"]),
				"strategy_revision": _revision,
			},
		}
	if _skill_action.is_empty() or bool(_skill_action.get("committed", false)):
		return {"ok": false, "code": "no_releasable_guard"}
	return {
		"ok": true,
		"code": "planned",
		"plan": {
			"skill_id": &"chrono_fortress",
			"action_mode": &"release_guard",
			"runtime_frame": runtime_frame,
			"run_id": StringName(context["run_id"]),
			"run_revision": int(context["run_revision"]),
			"owner_character_generation": int(context["owner_character_generation"]),
			"guard_token": int(_skill_action.get("token", 0)),
			"strategy_revision": _revision,
		},
	}


func commit_character_skill(plan: Dictionary, token: int) -> Dictionary:
	if plan.is_empty():
		return {"ok": false, "code": "unsupported"}
	if not _valid_skill_plan(plan) or token <= 0:
		return {"ok": false, "code": "invalid_plan"}
	if not _bind_run(
		StringName(plan["run_id"]),
		int(plan["run_revision"]),
		int(plan["owner_character_generation"])
	):
		return {"ok": false, "code": "stale_run"}
	var action_mode := StringName(plan["action_mode"])
	var events: Array[Dictionary] = []
	if action_mode == &"begin_guard":
		_skill_action = plan.duplicate(true)
		_skill_action["token"] = token
		_skill_action["committed"] = false
		_guard_resolved = false
	else:
		var frame := int(plan["runtime_frame"])
		var guard_token := int(_skill_action.get("token", 0))
		_skill_action.clear()
		_skill_cooldown_until_frame = frame + _ordinary_cooldown_frames()
		events.append(_cooldown_event(frame, _ordinary_cooldown_frames(), &"guard_released"))
		events.append(_event(&"guard_released", frame, guard_token, {
			"resolved": _guard_resolved,
		}))
	_revision += 1
	return {
		"ok": true,
		"code": "accepted",
		"events": events,
		"context": {
			"skill_id": &"chrono_fortress",
			"action_mode": action_mode,
		},
	}


func character_action_cancellation_state() -> Dictionary:
	return {
		"active": not _skill_action.is_empty(),
		"committed": bool(_skill_action.get("committed", false)),
	}


func cancel_uncommitted_action(_reason: StringName) -> Dictionary:
	if _skill_action.is_empty():
		return {"ok": true, "cancelled": false}
	if bool(_skill_action.get("committed", false)):
		return {"ok": true, "cancelled": false}
	_skill_action.clear()
	if _guard_resolved:
		_skill_cooldown_until_frame = maxi(_last_runtime_frame, 0) + _ordinary_cooldown_frames()
	_revision += 1
	return {"ok": true, "cancelled": true}


func before_damage(damage_context: Dictionary) -> Dictionary:
	if damage_context.is_empty():
		return {"ok": true, "decision": {}}
	var normalized := _normalized_damage_context(damage_context)
	if normalized.is_empty():
		return {"ok": false, "decision": {}}
	var runtime_frame := int(normalized["runtime_frame"])
	var claim_key := _hostile_claim_key(
		StringName(normalized["hostile_source_id"]),
		int(normalized["attack_generation"])
	)
	var eligible := not bool(normalized["bypasses_character_defense"])
	var guard_kind := &"none"
	var guard_multiplier := 1.0
	var prevented := false
	var grant_ward := false
	if eligible and not _skill_action.is_empty() and not bool(_skill_action.get("committed", false)):
		var held_frame := runtime_frame - int(_skill_action.get("runtime_frame", runtime_frame))
		if held_frame <= _perfect_last_frame():
			guard_kind = &"perfect"
			guard_multiplier = 0.0
			prevented = true
		elif held_frame <= _normal_last_frame():
			guard_kind = &"normal"
			guard_multiplier = 0.5
		else:
			guard_kind = &"closed"
		grant_ward = guard_kind in [&"perfect", &"normal"] and not _ward_claims.has(claim_key)

	var fortress_multiplier := 1.0
	if eligible and _fortress_active(runtime_frame):
		grant_ward = grant_ward or not _ward_claims.has(claim_key)
		if _inside_fortress_cone(
			normalized["facing_direction"] as Vector2,
			normalized["incoming_direction"] as Vector2
		):
			fortress_multiplier = 1.0 - _skill_parameter_float("frontal_reduction")

	var ward_before := int(_resource_value)
	var consume_ward := (
		1
		if (
			eligible
			and not prevented
			and ward_before > 0
			and not _ward_consumption_claims.has(claim_key)
		)
		else 0
	)
	var ward_multiplier := 1.0 - _passive_parameter_float("damage_reduction") if consume_ward > 0 else 1.0
	var combined_multiplier := guard_multiplier * fortress_multiplier * ward_multiplier
	var decision := {
		"decision_id": &"time_guardian_defense",
		"character_id": CHARACTER_ID,
		"runtime_frame": runtime_frame,
		"character_revision": _revision,
		"hostile_source_id": normalized["hostile_source_id"],
		"attack_generation": normalized["attack_generation"],
		"claim_key": claim_key,
		"guard_kind": guard_kind,
		"prevented": prevented,
		"guard_multiplier": guard_multiplier,
		"fortress_multiplier": fortress_multiplier,
		"ward_multiplier": ward_multiplier,
		"combined_multiplier": combined_multiplier,
		"consume_ward": consume_ward,
		"grant_ward": grant_ward,
		"ward_before": ward_before,
		"run_id": _run_id,
		"run_revision": _run_revision,
	}
	return {"ok": true, "decision": decision}


func after_damage(damage_context: Dictionary) -> Array[Dictionary]:
	if (
		not _context_matches_run(damage_context)
		or typeof(damage_context.get("runtime_frame")) != TYPE_INT
		or int(damage_context["runtime_frame"]) != _last_runtime_frame
		or typeof(damage_context.get("applied")) != TYPE_BOOL
		or not bool(damage_context["applied"])
		or not damage_context.get("decision") is Dictionary
		or not _finite_number(damage_context.get("finalized_damage"))
	):
		return []
	var decision := damage_context["decision"] as Dictionary
	if (
		StringName(str(decision.get("decision_id", ""))) != &"time_guardian_defense"
		or int(decision.get("runtime_frame", -1)) != _last_runtime_frame
		or int(decision.get("character_revision", -1)) != _revision
		or StringName(str(decision.get("run_id", ""))) != _run_id
		or int(decision.get("run_revision", -1)) != _run_revision
	):
		return []
	var claim_key := str(decision.get("claim_key", ""))
	if claim_key.is_empty():
		return []
	var events: Array[Dictionary] = []
	var changed_resource := false
	var first_consumption_resolution := not _ward_consumption_claims.has(claim_key)
	if first_consumption_resolution:
		_ward_consumption_claims.append(claim_key)
		_ward_consumption_claims.sort()
	if int(decision.get("consume_ward", 0)) == 1 and first_consumption_resolution:
		if int(_resource_value) <= 0:
			return []
		_rebuke_from_full_ward = int(decision.get("ward_before", 0)) >= int(
			(_profile_snapshot.get("resource", {}) as Dictionary).get("maximum", 3)
		)
		_resource_value = int(_resource_value) - 1
		_rebuke_until_frame = _last_runtime_frame + _passive_parameter_int("rebuke_window_frames")
		_rebuke_source_token = int(decision.get("attack_generation", 0))
		changed_resource = true
		events.append(_event(&"rebuke_window_opened", _last_runtime_frame, 0, {
			"active_until_frame": _rebuke_until_frame,
			"hostile_source_id": decision.get("hostile_source_id", &""),
			"attack_generation": int(decision.get("attack_generation", 0)),
			"from_full_ward": _rebuke_from_full_ward,
		}))
	if bool(decision.get("grant_ward", false)) and not _ward_claims.has(claim_key):
		_ward_claims.append(claim_key)
		_ward_claims.sort()
		var maximum := int((_profile_snapshot.get("resource", {}) as Dictionary).get("maximum", 3))
		if int(_resource_value) < maximum:
			_resource_value = int(_resource_value) + 1
			changed_resource = true
	if _fortress_active(_last_runtime_frame) and int(_resource_value) >= int(
		(_profile_snapshot.get("resource", {}) as Dictionary).get("maximum", 3)
	):
		_fortress_shockwave_armed = true
	var guard_kind := StringName(str(decision.get("guard_kind", "none")))
	if guard_kind in [&"perfect", &"normal"]:
		_guard_resolved = true
		events.append(_event(&"character_guard_resolved", _last_runtime_frame, 0, {
			"guard_kind": guard_kind,
			"prevented": bool(decision.get("prevented", false)),
			"hostile_source_id": decision.get("hostile_source_id", &""),
			"attack_generation": int(decision.get("attack_generation", 0)),
		}))
	if changed_resource:
		events.append(_resource_event(_last_runtime_frame, 0, &"character_defense"))
	if not events.is_empty():
		_revision += 1
	return events


func on_weapon_mastery_confirmed(mastery_context: Dictionary) -> Array[Dictionary]:
	var normalized := _normalized_mastery(mastery_context)
	if normalized.is_empty():
		return []
	var mastery_claim := "%d:%d:%s" % [
		int(normalized["generation"]),
		int(normalized["action_token"]),
		str(normalized["mastery_family"]),
	]
	if _mastery_claims.has(mastery_claim):
		return []
	_mastery_claims.append(mastery_claim)
	_mastery_claims.sort()
	var context := normalized["context"] as Dictionary
	var runtime_frame := int(context["runtime_frame"])
	var token := int(normalized["action_token"])
	var events: Array[Dictionary] = []
	var shockwave_was_armed := _fortress_shockwave_armed

	if bool(context.get("defensive_mastery", false)):
		var source_id := StringName(str(context.get("hostile_source_id", "")))
		var attack_generation := int(context.get("attack_generation", 0))
		if source_id != &"" and attack_generation > 0:
			var defense_claim := _hostile_claim_key(source_id, attack_generation)
			if not _ward_claims.has(defense_claim):
				_ward_claims.append(defense_claim)
				_ward_claims.sort()
				var maximum := int((_profile_snapshot.get("resource", {}) as Dictionary).get("maximum", 3))
				_resource_value = mini(int(_resource_value) + 1, maximum)
				if _fortress_active(runtime_frame) and int(_resource_value) >= maximum:
					_fortress_shockwave_armed = true
				events.append(_resource_event(runtime_frame, token, &"defensive_weapon_mastery"))

	if _rebuke_until_frame >= 0 and runtime_frame < _rebuke_until_frame:
		var origin := context["position"] as Vector2
		var rift_generation := int(context.get("rift_generation", 0))
		if (
			_rebuke_from_full_ward
			and rift_generation > 0
			and typeof(context.get("rift_center")) == TYPE_VECTOR2
			and _finite_vector(context["rift_center"] as Vector2)
			and not _rift_anchor_claims.has(rift_generation)
		):
			origin = context["rift_center"] as Vector2
			_rift_anchor_claims.append(rift_generation)
			_rift_anchor_claims.sort()
		var descriptor := _payload_descriptor(
			&"guardian_rebuke_echo",
			&"character_time_echo",
			token,
			origin,
			0.01,
			float(context["attack"]) * _passive_parameter_float("rebuke_echo_multiplier"),
			{"conversion_id": &"guardian_rebuke"}
		)
		if descriptor.is_empty():
			return []
		events.append(_event(&"world_payload_requested", runtime_frame, token, {
			"descriptor": descriptor,
		}))
		events.append(_event(&"time_cooldown_reduction_requested", runtime_frame, token, {
			"selection": &"longer_equipped",
			"amount_frames": _passive_parameter_int("cooldown_reduction_frames"),
			"equipped_time_abilities": context["equipped_time_abilities"],
		}))
		var stop_generation := int(context.get("stop_generation", 0))
		if (
			stop_generation > 0
			and bool(context.get("boss_exposed", false))
			and not _stop_exposure_claims.has(stop_generation)
		):
			_stop_exposure_claims.append(stop_generation)
			_stop_exposure_claims.sort()
			events.append(_event(&"boss_exposure_extension_requested", runtime_frame, token, {
				"stop_generation": stop_generation,
				"amount_frames": 30,
			}))
		_clear_rebuke()

	if shockwave_was_armed and _fortress_active(runtime_frame):
		var shockwave := _payload_descriptor(
			&"guardian_fortress_shockwave",
			&"character_time_shockwave",
			token,
			context["position"] as Vector2,
			_skill_parameter_float("shockwave_radius"),
			float(context["attack"]) * _skill_parameter_float("shockwave_multiplier"),
			{"conversion_id": &"guardian_fortress_shockwave"}
		)
		if not shockwave.is_empty():
			events.append(_event(&"world_payload_requested", runtime_frame, token, {
				"descriptor": shockwave,
			}))
			_fortress_shockwave_armed = false

	_revision += 1
	return events


func on_room_started(room_context: Dictionary) -> Array[Dictionary]:
	if (
		not _valid_segment(room_context.get("run_id"))
		or typeof(room_context.get("run_revision")) != TYPE_INT
		or int(room_context["run_revision"]) <= 0
		or not _valid_segment(room_context.get("room_id"))
		or typeof(room_context.get("room_revision")) != TYPE_INT
		or int(room_context["room_revision"]) <= 0
		or typeof(room_context.get("owner_character_generation", 1)) != TYPE_INT
		or int(room_context.get("owner_character_generation", 1)) <= 0
	):
		return []
	var was_unbound := _run_id == &""
	if not _bind_run(
		StringName(room_context["run_id"]),
		int(room_context["run_revision"]),
		int(room_context.get("owner_character_generation", 1))
	):
		return []
	if not was_unbound:
		return []
	_revision += 1
	return [_event(&"guardian_room_started", maxi(_last_runtime_frame, 0), 0, {
		"room_id": StringName(room_context["room_id"]),
		"room_revision": int(room_context["room_revision"]),
	})]


func snapshot() -> Dictionary:
	return {
		"schema_version": STRATEGY_SNAPSHOT_SCHEMA_VERSION,
		"runtime_kind": str(_runtime_kind),
		"configured": _configured,
		"last_runtime_frame": _last_runtime_frame,
		"revision": _revision,
		"resource_value": int(_resource_value),
		"run_id": str(_run_id),
		"run_revision": _run_revision,
		"owner_character_generation": _owner_character_generation,
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
		"skill_action": _skill_action.duplicate(true),
		"guard_resolved": _guard_resolved,
		"fortress_until_frame": _fortress_until_frame,
		"fortress_shockwave_armed": _fortress_shockwave_armed,
		"ward_claims": _ward_claims.duplicate(),
		"ward_consumption_claims": _ward_consumption_claims.duplicate(),
		"mastery_claims": _mastery_claims.duplicate(),
		"rebuke_until_frame": _rebuke_until_frame,
		"rebuke_source_token": _rebuke_source_token,
		"rebuke_from_full_ward": _rebuke_from_full_ward,
		"stop_exposure_claims": _stop_exposure_claims.duplicate(),
		"rift_anchor_claims": _rift_anchor_claims.duplicate(),
		"next_payload_generation": _next_payload_generation,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	return not _validated_snapshot(value).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	var normalized := _validated_snapshot(value)
	if normalized.is_empty():
		return false
	_install_snapshot(normalized)
	return snapshot() == normalized


func restore_gameplay_rewind_snapshot(value: Dictionary) -> bool:
	return not _validated_snapshot(value).is_empty()


func presentation_snapshot() -> Dictionary:
	return {
		"runtime_kind": str(_runtime_kind),
		"resource_value": int(_resource_value),
		"guard_active": not _skill_action.is_empty() and not bool(_skill_action.get("committed", false)),
		"fortress_active": _fortress_active(_last_runtime_frame),
		"fortress_until_frame": _fortress_until_frame,
		"fortress_shockwave_armed": _fortress_shockwave_armed,
		"rebuke_active": _rebuke_until_frame > _last_runtime_frame,
		"rebuke_until_frame": _rebuke_until_frame,
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
		"movement_multiplier": (
			_skill_parameter_float("movement_multiplier")
			if _fortress_active(_last_runtime_frame)
			else 1.0
		),
	}


func _valid_skill_plan(plan: Dictionary) -> bool:
	var action_mode := StringName(str(plan.get("action_mode", "")))
	if (
		str(plan.get("skill_id", "")) != "chrono_fortress"
		or action_mode not in [&"begin_guard", &"release_guard"]
		or typeof(plan.get("runtime_frame")) != TYPE_INT
		or int(plan["runtime_frame"]) != _last_runtime_frame
		or not _valid_segment(plan.get("run_id"))
		or typeof(plan.get("run_revision")) != TYPE_INT
		or int(plan["run_revision"]) <= 0
		or typeof(plan.get("owner_character_generation")) != TYPE_INT
		or int(plan["owner_character_generation"]) <= 0
		or typeof(plan.get("strategy_revision")) != TYPE_INT
		or int(plan["strategy_revision"]) != _revision
	):
		return false
	if action_mode == &"begin_guard":
		return (
			_skill_action.is_empty()
			and typeof(plan.get("fortress_check_frame")) == TYPE_INT
			and int(plan["fortress_check_frame"]) == _last_runtime_frame + _hold_threshold_frames()
		)
	return (
		not _skill_action.is_empty()
		and not bool(_skill_action.get("committed", false))
		and typeof(plan.get("guard_token")) == TYPE_INT
		and int(plan["guard_token"]) == int(_skill_action.get("token", 0))
	)


func _normalized_damage_context(value: Dictionary) -> Dictionary:
	if (
		not _valid_live_context(value)
		or not _valid_segment(value.get("hostile_source_id"))
		or typeof(value.get("attack_generation")) != TYPE_INT
		or int(value["attack_generation"]) <= 0
		or not _finite_number(value.get("original_amount"))
		or float(value["original_amount"]) <= 0.0
		or not value.get("tags") is Array
		or typeof(value.get("facing_direction")) != TYPE_VECTOR2
		or not _finite_vector(value["facing_direction"] as Vector2)
		or typeof(value.get("incoming_direction")) != TYPE_VECTOR2
		or not _finite_vector(value["incoming_direction"] as Vector2)
	):
		return {}
	var tags: Array[String] = []
	for tag_value: Variant in value["tags"] as Array:
		if typeof(tag_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {}
		tags.append(str(tag_value))
	var bypass := false
	for bypass_tag: String in ["self_cost", "corruption", "terminal", "unguardable"]:
		if tags.has(bypass_tag):
			bypass = true
	return {
		"runtime_frame": int(value["runtime_frame"]),
		"hostile_source_id": StringName(value["hostile_source_id"]),
		"attack_generation": int(value["attack_generation"]),
		"facing_direction": value["facing_direction"],
		"incoming_direction": value["incoming_direction"],
		"bypasses_character_defense": bypass,
	}


func _normalized_mastery(value: Dictionary) -> Dictionary:
	if (
		typeof(value.get("generation")) != TYPE_INT
		or int(value["generation"]) <= 0
		or typeof(value.get("action_token")) != TYPE_INT
		or int(value["action_token"]) <= 0
		or not _valid_segment(value.get("weapon_id"))
		or StringName(value["weapon_id"]) != StringName(str(value.get("mastery_family", "")))
		or not value.get("context") is Dictionary
	):
		return {}
	var context := value["context"] as Dictionary
	if (
		not _valid_live_context(context)
		or not _context_matches_run(context)
		or not _finite_number(context.get("attack"))
		or float(context["attack"]) <= 0.0
		or typeof(context.get("position")) != TYPE_VECTOR2
		or not _finite_vector(context["position"] as Vector2)
		or not context.get("equipped_time_abilities") is Array
		or (context["equipped_time_abilities"] as Array).size() != 2
	):
		return {}
	return {
		"generation": int(value["generation"]),
		"action_token": int(value["action_token"]),
		"mastery_family": StringName(value["mastery_family"]),
		"context": context.duplicate(true),
	}


func _payload_descriptor(
	payload_family: StringName,
	handler_id: StringName,
	source_token: int,
	origin: Vector2,
	radius: float,
	damage: float,
	extra_parameters: Dictionary
) -> Dictionary:
	var parameters := {
		"damage": damage,
		"damage_type": &"time",
	}
	for key: Variant in extra_parameters.keys():
		parameters[key] = extra_parameters[key]
	var descriptor := CharacterPayloadExecutionScript.world_payload_descriptor(
		_run_id,
		_owner_character_generation,
		payload_family,
		source_token,
		_next_payload_generation,
		handler_id,
		Transform2D(0.0, origin),
		{"shape": &"circle", "center": origin, "radius": maxf(radius, 0.01)},
		2,
		[],
		["character_owned", "no_mastery", "no_resource", "non_recursive"],
		parameters
	)
	if not descriptor.is_empty():
		_next_payload_generation += 1
	return descriptor


func _inside_fortress_cone(facing: Vector2, incoming: Vector2) -> bool:
	if facing.length_squared() <= 0.000001 or incoming.length_squared() <= 0.000001:
		return false
	var half_angle := deg_to_rad(_skill_parameter_float("frontal_cone_degrees") * 0.5)
	return facing.normalized().dot(incoming.normalized()) >= cos(half_angle)


func _fortress_active(frame: int) -> bool:
	return _fortress_until_frame >= 0 and frame >= 0 and frame < _fortress_until_frame


func _valid_skill_intent(intent: Dictionary) -> bool:
	return (
		StringName(str(intent.get("id", ""))) == &"character_skill"
		and StringName(str(intent.get("edge", ""))) in [&"pressed", &"released"]
		and typeof(intent.get("held_frames")) == TYPE_INT
		and int(intent["held_frames"]) >= 0
	)


func _valid_live_context(value: Dictionary) -> bool:
	return (
		typeof(value.get("runtime_frame")) == TYPE_INT
		and int(value["runtime_frame"]) == _last_runtime_frame
		and _valid_segment(value.get("run_id"))
		and typeof(value.get("run_revision")) == TYPE_INT
		and int(value["run_revision"]) > 0
		and typeof(value.get("owner_character_generation", _owner_character_generation)) == TYPE_INT
		and int(value.get("owner_character_generation", _owner_character_generation)) > 0
		and (
			_run_id == &""
			or (
				StringName(value["run_id"]) == _run_id
				and int(value["run_revision"]) == _run_revision
			)
		)
	)


func _bind_run(run_id: StringName, run_revision: int, owner_generation: int) -> bool:
	if run_id == &"" or run_revision <= 0 or owner_generation <= 0:
		return false
	if _run_id == &"":
		_run_id = run_id
		_run_revision = run_revision
		_owner_character_generation = owner_generation
		return true
	return (
		run_id == _run_id
		and run_revision == _run_revision
		and owner_generation == _owner_character_generation
	)


func _context_matches_run(value: Dictionary) -> bool:
	return (
		_run_id != &""
		and _valid_segment(value.get("run_id"))
		and StringName(value["run_id"]) == _run_id
		and typeof(value.get("run_revision")) == TYPE_INT
		and int(value["run_revision"]) == _run_revision
	)


func _hostile_claim_key(source_id: StringName, generation: int) -> String:
	return "%s:%d" % [str(source_id), generation]


func _clear_rebuke() -> void:
	_rebuke_until_frame = -1
	_rebuke_source_token = 0
	_rebuke_from_full_ward = false


func _resource_event(frame: int, token: int, reason: StringName) -> Dictionary:
	return _event(&"character_resource_changed", frame, token, {
		"resource_id": &"ward",
		"current": int(_resource_value),
		"maximum": int((_profile_snapshot.get("resource", {}) as Dictionary).get("maximum", 3)),
		"reason": reason,
	})


func _cooldown_event(frame: int, duration: int, reason: StringName) -> Dictionary:
	return _event(&"character_cooldown_started", frame, 0, {
		"skill_id": &"chrono_fortress",
		"duration_frames": duration,
		"ready_frame": frame + duration,
		"reason": reason,
	})


func _event(event_id: StringName, frame: int, token: int, context: Dictionary) -> Dictionary:
	return CharacterPayloadExecutionScript.event(
		event_id,
		CHARACTER_ID,
		maxi(frame, 0),
		maxi(token, 0),
		maxi(_owner_character_generation, 1),
		context
	)


func _perfect_last_frame() -> int:
	return _skill_parameter_int("perfect_last_frame")


func _normal_last_frame() -> int:
	return _skill_parameter_int("normal_last_frame")


func _hold_threshold_frames() -> int:
	return int((_profile_snapshot.get("character_skill", {}) as Dictionary).get("hold_threshold_frames", 0))


func _ordinary_cooldown_frames() -> int:
	return int((_profile_snapshot.get("character_skill", {}) as Dictionary).get("cooldown_frames", 0))


func _skill_energy_cost() -> float:
	return float((_profile_snapshot.get("character_skill", {}) as Dictionary).get("energy_cost", 0.0))


func _fortress_ward_cost() -> int:
	return _skill_parameter_int("ward_cost")


func _passive_parameter_int(key: String) -> int:
	return int((((_profile_snapshot.get("passive", {}) as Dictionary).get(
		"parameters", {}
	) as Dictionary).get(key, 0)))


func _passive_parameter_float(key: String) -> float:
	return float((((_profile_snapshot.get("passive", {}) as Dictionary).get(
		"parameters", {}
	) as Dictionary).get(key, 0.0)))


func _skill_parameter_int(key: String) -> int:
	return int((((_profile_snapshot.get("character_skill", {}) as Dictionary).get(
		"parameters", {}
	) as Dictionary).get(key, 0)))


func _skill_parameter_float(key: String) -> float:
	return float((((_profile_snapshot.get("character_skill", {}) as Dictionary).get(
		"parameters", {}
	) as Dictionary).get(key, 0.0)))


func _reset_strategy_state() -> void:
	_run_id = &""
	_run_revision = 0
	_owner_character_generation = 1
	_skill_cooldown_until_frame = -1
	_skill_action.clear()
	_guard_resolved = false
	_fortress_until_frame = -1
	_fortress_shockwave_armed = false
	_ward_claims.clear()
	_ward_consumption_claims.clear()
	_mastery_claims.clear()
	_clear_rebuke()
	_stop_exposure_claims.clear()
	_rift_anchor_claims.clear()
	_next_payload_generation = 1


func _valid_next_frame(context: Dictionary) -> bool:
	return (
		_configured
		and typeof(context.get("runtime_frame")) == TYPE_INT
		and int(context["runtime_frame"]) >= 0
		and int(context["runtime_frame"]) > _last_runtime_frame
	)


func _validated_snapshot(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, STRATEGY_SNAPSHOT_FIELDS):
		return {}
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != STRATEGY_SNAPSHOT_SCHEMA_VERSION
		or str(value["runtime_kind"]) != "time_guardian"
		or typeof(value["configured"]) != TYPE_BOOL
		or bool(value["configured"]) != _configured
		or typeof(value["last_runtime_frame"]) != TYPE_INT
		or int(value["last_runtime_frame"]) < -1
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < 0
		or typeof(value["resource_value"]) != TYPE_INT
		or not _resource_value_in_profile_range(int(value["resource_value"]))
		or typeof(value["run_id"]) != TYPE_STRING
		or typeof(value["run_revision"]) != TYPE_INT
		or int(value["run_revision"]) < 0
		or typeof(value["owner_character_generation"]) != TYPE_INT
		or int(value["owner_character_generation"]) <= 0
		or typeof(value["skill_cooldown_until_frame"]) != TYPE_INT
		or int(value["skill_cooldown_until_frame"]) < -1
		or not value["skill_action"] is Dictionary
		or not ReplaySafeValueScript.is_supported(value["skill_action"])
		or typeof(value["guard_resolved"]) != TYPE_BOOL
		or typeof(value["fortress_until_frame"]) != TYPE_INT
		or int(value["fortress_until_frame"]) < -1
		or typeof(value["fortress_shockwave_armed"]) != TYPE_BOOL
		or not _valid_sorted_strings(value["ward_claims"])
		or not _valid_sorted_strings(value["ward_consumption_claims"])
		or not _valid_sorted_strings(value["mastery_claims"])
		or typeof(value["rebuke_until_frame"]) != TYPE_INT
		or int(value["rebuke_until_frame"]) < -1
		or typeof(value["rebuke_source_token"]) != TYPE_INT
		or int(value["rebuke_source_token"]) < 0
		or typeof(value["rebuke_from_full_ward"]) != TYPE_BOOL
		or not _valid_sorted_positive_ints(value["stop_exposure_claims"])
		or not _valid_sorted_positive_ints(value["rift_anchor_claims"])
		or typeof(value["next_payload_generation"]) != TYPE_INT
		or int(value["next_payload_generation"]) <= 0
	):
		return {}
	if (
		(str(value["run_id"]).is_empty()) != (int(value["run_revision"]) == 0)
		or (int(value["fortress_until_frame"]) >= 0 and not bool((value["skill_action"] as Dictionary).get("committed", false)))
		or (int(value["rebuke_until_frame"]) == -1 and (
			int(value["rebuke_source_token"]) != 0
			or bool(value["rebuke_from_full_ward"])
		))
	):
		return {}
	return value.duplicate(true)


func _install_snapshot(value: Dictionary) -> void:
	_last_runtime_frame = int(value["last_runtime_frame"])
	_revision = int(value["revision"])
	_resource_value = int(value["resource_value"])
	_run_id = StringName(value["run_id"])
	_run_revision = int(value["run_revision"])
	_owner_character_generation = int(value["owner_character_generation"])
	_skill_cooldown_until_frame = int(value["skill_cooldown_until_frame"])
	_skill_action = (value["skill_action"] as Dictionary).duplicate(true)
	_guard_resolved = bool(value["guard_resolved"])
	_fortress_until_frame = int(value["fortress_until_frame"])
	_fortress_shockwave_armed = bool(value["fortress_shockwave_armed"])
	_ward_claims.assign(value["ward_claims"])
	_ward_consumption_claims.assign(value["ward_consumption_claims"])
	_mastery_claims.assign(value["mastery_claims"])
	_rebuke_until_frame = int(value["rebuke_until_frame"])
	_rebuke_source_token = int(value["rebuke_source_token"])
	_rebuke_from_full_ward = bool(value["rebuke_from_full_ward"])
	_stop_exposure_claims.assign(value["stop_exposure_claims"])
	_rift_anchor_claims.assign(value["rift_anchor_claims"])
	_next_payload_generation = int(value["next_payload_generation"])


static func _valid_sorted_strings(value: Variant) -> bool:
	if not value is Array:
		return false
	var normalized: Array[String] = []
	for entry: Variant in value as Array:
		if typeof(entry) != TYPE_STRING or str(entry).is_empty() or normalized.has(str(entry)):
			return false
		normalized.append(str(entry))
	var sorted := normalized.duplicate()
	sorted.sort()
	return normalized == sorted


static func _valid_sorted_positive_ints(value: Variant) -> bool:
	if not value is Array:
		return false
	var normalized: Array[int] = []
	for entry: Variant in value as Array:
		if typeof(entry) != TYPE_INT or int(entry) <= 0 or normalized.has(int(entry)):
			return false
		normalized.append(int(entry))
	var sorted := normalized.duplicate()
	sorted.sort()
	return normalized == sorted


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _valid_segment(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := str(value)
	return not text.is_empty() and text == text.strip_edges() and not text.contains(":")
