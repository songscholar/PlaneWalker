class_name TimeLordCharacterRuntime
extends "res://scripts/player/characters/character_runtime.gd"

const CharacterPayloadExecutionScript := preload(
	"res://scripts/combat/character_payload_execution.gd"
)
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

const CHARACTER_ID := &"time_lord"
const STRATEGY_SNAPSHOT_SCHEMA_VERSION := 1
const TIME_ABILITY_ORDER: Array[StringName] = [
	&"stop", &"rewind", &"accelerate", &"rift",
]
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
	"mastery_claims",
	"time_claims",
	"last_page_grant_frame",
	"primer_ability_id",
	"primer_pair_key",
	"primer_equipped_abilities",
	"primer_token",
	"primer_generation",
	"primer_expires_frame",
	"primer_context",
	"infusion_until_frame",
	"infusion_token",
	"dominion_pair_key",
	"dominion_until_frame",
	"dominion_token",
	"next_mastery_echo_until_frame",
	"next_mastery_echo_multiplier",
	"next_mastery_echo_token",
	"skill_cooldown_until_frame",
	"next_conversion_generation",
	"talent_state",
]

var _run_id: StringName = &""
var _run_revision: int = 0
var _owner_character_generation: int = 1
var _mastery_claims: Array[String] = []
var _time_claims: Array[String] = []
var _last_page_grant_frame: int = -1
var _primer_ability_id: StringName = &""
var _primer_pair_key: StringName = &""
var _primer_equipped_abilities: Array[String] = []
var _primer_token: int = 0
var _primer_generation: int = 0
var _primer_expires_frame: int = -1
var _primer_context: Dictionary = {}
var _infusion_until_frame: int = -1
var _infusion_token: int = 0
var _dominion_pair_key: StringName = &""
var _dominion_until_frame: int = -1
var _dominion_token: int = 0
var _next_mastery_echo_until_frame: int = -1
var _next_mastery_echo_multiplier: float = 0.0
var _next_mastery_echo_token: int = 0
var _skill_cooldown_until_frame: int = -1
var _next_conversion_generation: int = 1


func _init() -> void:
	_runtime_kind = &"time_lord"


func configure(owner: Node, profile: Variant, talents: PackedStringArray) -> bool:
	if profile == null or not profile is RefCounted or not profile.has_method("snapshot"):
		return false
	var profile_value: Variant = profile.call("snapshot")
	if (
		not profile_value is Dictionary
		or str((profile_value as Dictionary).get("character_id", "")) != str(CHARACTER_ID)
		or str((profile_value as Dictionary).get("runtime_kind", "")) != "time_lord"
		or str(((profile_value as Dictionary).get("character_skill", {}) as Dictionary).get("handler_id", "")) != "codex_dominion"
	):
		return false
	if not super.configure(owner, profile, talents):
		return false
	_reset_strategy_state()
	_revision = 0
	return true


func reset_runtime_state(reason: StringName) -> void:
	if not _configured:
		return
	super.reset_runtime_state(reason)
	_reset_strategy_state()


func advance_frame(context: Dictionary) -> Array[Dictionary]:
	if not _valid_next_frame(context):
		return []
	var runtime_frame := int(context["runtime_frame"])
	super.advance_frame(context)
	var events: Array[Dictionary] = []
	if _primer_expires_frame >= 0 and runtime_frame >= _primer_expires_frame:
		var expired_ability := _primer_ability_id
		var expired_token := _primer_token
		_clear_primer()
		events.append(_event(&"codex_primer_expired", runtime_frame, expired_token, {
			"ability_id": expired_ability,
		}))
	if _infusion_until_frame >= 0 and runtime_frame >= _infusion_until_frame:
		var expired_infusion_token := _infusion_token
		_infusion_until_frame = -1
		_infusion_token = 0
		events.append(_event(&"codex_infusion_expired", runtime_frame, expired_infusion_token, {}))
	if _dominion_until_frame >= 0 and runtime_frame >= _dominion_until_frame:
		var expired_pair := _dominion_pair_key
		var expired_dominion_token := _dominion_token
		_clear_dominion()
		events.append(_event(&"time_dominion_expired", runtime_frame, expired_dominion_token, {
			"pair_key": expired_pair,
		}))
	if _next_mastery_echo_until_frame >= 0 and runtime_frame >= _next_mastery_echo_until_frame:
		var expired_echo_token := _next_mastery_echo_token
		_clear_next_mastery_echo()
		events.append(_event(&"codex_pair_echo_expired", runtime_frame, expired_echo_token, {}))
	if not events.is_empty():
		_revision += 1
	return events


func plan_character_skill(intent: Dictionary, context: Dictionary) -> Dictionary:
	if (
		not _configured
		or not _valid_skill_intent(intent)
		or not _valid_live_context(context)
		or not bool(context.get("alive", false))
		or not _finite_number(context.get("time_energy"))
	):
		return {"ok": false, "code": "invalid_context"}
	var runtime_frame := int(context["runtime_frame"])
	if _skill_cooldown_until_frame >= 0 and runtime_frame < _skill_cooldown_until_frame:
		return {"ok": false, "code": "cooldown_active"}
	var held_frames := int(intent["held_frames"])
	var hold_threshold := int((_profile_snapshot.get("character_skill", {}) as Dictionary).get("hold_threshold_frames", 60))
	var mode := &"dominion" if held_frames >= hold_threshold else &"infusion"
	var modifiers := _talent_state.modifier_snapshot()
	var energy_cost := float(modifiers.get("dominion_energy_cost", 60) if mode == &"dominion" else modifiers.get("infusion_energy_cost", 10))
	if float(context["time_energy"]) < energy_cost:
		return {"ok": false, "code": "insufficient_energy"}
	var equipped: Array[String] = []
	var pair_key := &""
	if mode == &"dominion":
		equipped = _canonical_equipped_pair(context.get("equipped_time_abilities"))
		if equipped.is_empty():
			return {"ok": false, "code": "invalid_equipped_pair"}
		if int(_resource_value) < _skill_parameter_int("dominion_page_cost"):
			return {"ok": false, "code": "insufficient_pages"}
		pair_key = _pair_key(StringName(equipped[0]), StringName(equipped[1]))
	var cooldown_frames := (
		int(modifiers.get("dominion_cooldown_frames", 480))
		if mode == &"dominion"
		else _skill_cooldown_frames()
	)
	return {
		"ok": true,
		"code": "planned",
		"plan": {
			"skill_id": &"codex_dominion",
			"mode": mode,
			"runtime_frame": runtime_frame,
			"run_id": StringName(context["run_id"]),
			"run_revision": int(context["run_revision"]),
			"owner_character_generation": int(context.get("owner_character_generation", _owner_character_generation)),
			"held_frames": held_frames,
			"energy_cost": energy_cost,
			"page_cost": _skill_parameter_int("dominion_page_cost") if mode == &"dominion" else 0,
			"cooldown_frames": cooldown_frames,
			"duration_frames": _skill_parameter_int("dominion_charge_frames") if mode == &"dominion" else _skill_parameter_int("infusion_duration_frames"),
			"equipped_time_abilities": equipped,
			"pair_key": pair_key,
			"strategy_revision": _revision,
			"talent_state_revision": int(_talent_state.snapshot().get("revision", -1)),
			"talent_modifiers": modifiers,
		},
	}


func commit_character_skill(plan: Dictionary, token: int) -> Dictionary:
	if not _valid_skill_plan(plan) or token <= 0:
		return {"ok": false, "code": "invalid_plan"}
	if not _bind_run(
		StringName(plan["run_id"]),
		int(plan["run_revision"]),
		int(plan["owner_character_generation"])
	):
		return {"ok": false, "code": "stale_run"}
	var talent_freeze := _talent_state.freeze_for_commit(&"character_skill", token, 1)
	if (
		talent_freeze.is_empty()
		or int(talent_freeze.get("state_revision", -1)) != int(plan["talent_state_revision"])
		or talent_freeze.get("modifiers", {}) != plan["talent_modifiers"]
	):
		return {"ok": false, "code": "stale_talents"}
	var mode := StringName(plan["mode"])
	var runtime_frame := int(plan["runtime_frame"])
	var events: Array[Dictionary] = []
	if mode == &"dominion":
		var page_cost := int(plan["page_cost"])
		if int(_resource_value) < page_cost:
			return {"ok": false, "code": "insufficient_pages"}
		_resource_value = int(_resource_value) - page_cost
		_dominion_pair_key = StringName(plan["pair_key"])
		_dominion_until_frame = runtime_frame + int(plan["duration_frames"])
		_dominion_token = token
		events.append(_resource_event(runtime_frame, token, &"time_dominion"))
		events.append(_event(&"time_dominion_armed", runtime_frame, token, {
			"pair_key": _dominion_pair_key,
			"active_until_frame": _dominion_until_frame,
			"duration_frames": int(plan["duration_frames"]),
		}))
	else:
		_infusion_until_frame = runtime_frame + int(plan["duration_frames"])
		_infusion_token = token
		events.append(_event(&"codex_infusion_armed", runtime_frame, token, {
			"active_until_frame": _infusion_until_frame,
			"duration_frames": int(plan["duration_frames"]),
			"echo_multiplier": _skill_parameter_float("infusion_echo_multiplier"),
		}))
	_skill_cooldown_until_frame = runtime_frame + int(plan["cooldown_frames"])
	events.append(_event(&"time_energy_spend_requested", runtime_frame, token, {
		"amount": float(plan["energy_cost"]),
		"reason": mode,
	}))
	events.append(_cooldown_event(runtime_frame, int(plan["cooldown_frames"]), mode))
	_revision += 1
	return {
		"ok": true,
		"code": "committed",
		"events": events,
		"context": {
			"skill_id": &"codex_dominion",
			"mode": mode,
			"talent_freeze": talent_freeze,
		},
	}


func before_time_skill(time_context: Dictionary) -> Dictionary:
	if not _valid_time_context(time_context):
		return {"ok": false, "decision": {}}
	var ability_id := StringName(time_context["ability_id"])
	var equipped := _canonical_equipped_pair(time_context.get("equipped_time_abilities"))
	if equipped.is_empty() or not equipped.has(str(ability_id)):
		return {"ok": false, "decision": {}}
	var pair_key := _pair_key(StringName(equipped[0]), StringName(equipped[1]))
	var mode := &"observe"
	var conversion: Dictionary = {}
	var enhanced := false
	if _primer_ability_id == &"":
		if int(_resource_value) > 0:
			mode = &"open_primer"
	elif ability_id != _primer_ability_id and pair_key == _primer_pair_key and int(time_context["runtime_frame"]) < _primer_expires_frame:
		mode = &"resolve_pair"
		enhanced = (
			_dominion_until_frame >= 0
			and int(time_context["runtime_frame"]) < _dominion_until_frame
			and _dominion_pair_key == pair_key
		)
		conversion = _pair_conversion(pair_key, enhanced, _primer_context, time_context)
		if conversion.is_empty():
			return {"ok": false, "decision": {}}
	var talent_freeze := _talent_state.freeze_for_commit(
		&"time_action",
		int(time_context["token"]),
		int(time_context["generation"])
	)
	if talent_freeze.is_empty():
		return {"ok": false, "decision": {}}
	var decision := CharacterPayloadExecutionScript.decision(
		&"time_lord_time_conversion",
		CHARACTER_ID,
		int(time_context["runtime_frame"]),
		int(time_context["token"]),
		int(time_context["generation"]),
		{
			"ability_id": ability_id,
			"mode": mode,
			"pair_key": pair_key,
			"equipped_time_abilities": equipped,
			"primer_context": _primer_context_from(time_context),
			"conversion": conversion,
			"enhanced": enhanced,
			"strategy_revision": _revision,
			"talent_freeze": talent_freeze,
		}
	)
	return {"ok": not decision.is_empty(), "decision": decision}


func after_time_skill(time_context: Dictionary) -> Array[Dictionary]:
	if not _valid_time_context(time_context):
		return []
	var decision_value: Variant = time_context.get("character_decision")
	if not CharacterPayloadExecutionScript.is_decision(decision_value):
		return []
	var decision := decision_value as Dictionary
	var parameters := decision.get("parameters", {}) as Dictionary
	if (
		StringName(str(decision.get("decision_id", ""))) != &"time_lord_time_conversion"
		or int(decision.get("runtime_frame", -1)) != int(time_context["runtime_frame"])
		or int(decision.get("token", -1)) != int(time_context["token"])
		or int(decision.get("generation", -1)) != int(time_context["generation"])
		or int(parameters.get("strategy_revision", -1)) != _revision
		or StringName(str(parameters.get("ability_id", ""))) != StringName(time_context["ability_id"])
		or not _bind_run(StringName(time_context["run_id"]), int(time_context["run_revision"]), int(time_context.get("owner_character_generation", _owner_character_generation)))
	):
		return []
	var claim := _time_claim_key(time_context)
	if claim.is_empty() or _time_claims.has(claim):
		return []
	var mode := StringName(str(parameters.get("mode", "")))
	var runtime_frame := int(time_context["runtime_frame"])
	var token := int(time_context["token"])
	var events: Array[Dictionary] = []
	if mode == &"open_primer":
		if int(_resource_value) <= 0 or _primer_ability_id != &"":
			return []
		_primer_ability_id = StringName(time_context["ability_id"])
		_primer_pair_key = StringName(parameters["pair_key"])
		_primer_equipped_abilities = (parameters.get("equipped_time_abilities", []) as Array).duplicate()
		_primer_token = token
		_primer_generation = int(time_context["generation"])
		_primer_expires_frame = runtime_frame + _pair_window_frames()
		_primer_context = (parameters.get("primer_context", {}) as Dictionary).duplicate(true)
		events.append(_event(&"codex_primer_opened", runtime_frame, token, {
			"ability_id": _primer_ability_id,
			"pair_key": _primer_pair_key,
			"active_until_frame": _primer_expires_frame,
			"duration_frames": _pair_window_frames(),
		}))
	elif mode == &"resolve_pair":
		if (
			int(_resource_value) <= 0
			or _primer_ability_id == &""
			or StringName(time_context["ability_id"]) == _primer_ability_id
			or runtime_frame >= _primer_expires_frame
			or StringName(parameters.get("pair_key", &"")) != _primer_pair_key
			or not parameters.get("conversion") is Dictionary
			or (parameters["conversion"] as Dictionary).is_empty()
		):
			return []
		var pair_key := _primer_pair_key
		var primer_ability := _primer_ability_id
		var conversion := (parameters["conversion"] as Dictionary).duplicate(true)
		var enhanced := bool(parameters.get("enhanced", false))
		_resource_value = int(_resource_value) - 1
		_clear_primer()
		if enhanced:
			_clear_dominion()
		if StringName(str(conversion.get("conversion_id", ""))) == &"next_mastery_echo":
			var conversion_parameters := conversion.get("parameters", {}) as Dictionary
			_next_mastery_echo_until_frame = runtime_frame + int(conversion_parameters.get("expiry_frames", 0))
			_next_mastery_echo_multiplier = float(conversion_parameters.get("echo_multiplier", 0.0))
			_next_mastery_echo_token = token
		var conversion_generation := _next_conversion_generation
		_next_conversion_generation += 1
		events.append(_resource_event(runtime_frame, token, &"time_pair"))
		events.append(_event(&"time_pair_conversion_requested", runtime_frame, token, {
			"pair_key": pair_key,
			"primer_ability_id": primer_ability,
			"completion_ability_id": StringName(time_context["ability_id"]),
			"enhanced": enhanced,
			"conversion_generation": conversion_generation,
			"conversion_id": conversion["conversion_id"],
			"parameters": (conversion.get("parameters", {}) as Dictionary).duplicate(true),
		}))
		events.append(_event(&"codex_pair_resolved", runtime_frame, token, {
			"pair_key": pair_key,
			"enhanced": enhanced,
			"conversion_generation": conversion_generation,
		}))
	_time_claims.append(claim)
	_time_claims.sort()
	_revision += 1
	return events


func on_weapon_mastery_confirmed(mastery_context: Dictionary) -> Array[Dictionary]:
	var normalized := _normalized_mastery(mastery_context)
	if normalized.is_empty():
		return []
	var claim := "%d:%d:%s" % [
		int(normalized["generation"]),
		int(normalized["action_token"]),
		str(normalized["mastery_family"]),
	]
	if _mastery_claims.has(claim):
		return []
	var context := normalized["context"] as Dictionary
	var runtime_frame := int(context["runtime_frame"])
	var token := int(normalized["action_token"])
	var events: Array[Dictionary] = []
	_mastery_claims.append(claim)
	_mastery_claims.sort()
	if (
		int(_resource_value) < _resource_maximum()
		and (_last_page_grant_frame < 0 or runtime_frame >= _last_page_grant_frame + _page_rate_cap_frames())
	):
		_resource_value = int(_resource_value) + 1
		_last_page_grant_frame = runtime_frame
		events.append(_resource_event(runtime_frame, token, &"weapon_mastery"))
	if _infusion_until_frame >= 0 and runtime_frame < _infusion_until_frame and _valid_echo_source(context):
		var multiplier := _skill_parameter_float("infusion_echo_multiplier")
		events.append(_event(&"codex_infusion_echo_requested", runtime_frame, token, {
			"source_token": _infusion_token,
			"mastery_family": normalized["mastery_family"],
			"position": context["position"],
			"damage": float(context["attack"]) * multiplier,
			"damage_multiplier": multiplier,
			"damage_type": &"time",
			"tags": ["character_echo", "no_mastery", "no_resource", "non_recursive", "world_owned"],
		}))
		_infusion_until_frame = -1
		_infusion_token = 0
	if _next_mastery_echo_until_frame >= 0 and runtime_frame < _next_mastery_echo_until_frame and _valid_echo_source(context):
		events.append(_event(&"codex_pair_echo_requested", runtime_frame, token, {
			"source_token": _next_mastery_echo_token,
			"mastery_family": normalized["mastery_family"],
			"position": context["position"],
			"damage": float(context["attack"]) * _next_mastery_echo_multiplier,
			"damage_multiplier": _next_mastery_echo_multiplier,
			"damage_type": &"time",
			"tags": ["character_echo", "no_mastery", "no_resource", "non_recursive", "world_owned"],
		}))
		_clear_next_mastery_echo()
	_revision += 1
	return events


func on_room_started(room_context: Dictionary) -> Array[Dictionary]:
	if not _valid_room_context(room_context):
		return []
	var was_unbound := _run_id == &""
	if not _bind_run(StringName(room_context["run_id"]), int(room_context["run_revision"]), int(room_context.get("owner_character_generation", 1))):
		return []
	if not was_unbound:
		return []
	_revision += 1
	return [_event(&"time_lord_room_started", maxi(_last_runtime_frame, 0), 0, {
		"room_id": StringName(room_context["room_id"]),
		"room_revision": int(room_context["room_revision"]),
	})]


func on_run_terminal(run_context: Dictionary) -> Dictionary:
	if not _context_matches_run(run_context):
		return {"ok": false, "summary": {}}
	return {"ok": true, "summary": {
		"codex_pages": int(_resource_value),
		"primer_ability_id": _primer_ability_id,
		"dominion_pair_key": _dominion_pair_key,
	}}


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
		"mastery_claims": _mastery_claims.duplicate(),
		"time_claims": _time_claims.duplicate(),
		"last_page_grant_frame": _last_page_grant_frame,
		"primer_ability_id": str(_primer_ability_id),
		"primer_pair_key": str(_primer_pair_key),
		"primer_equipped_abilities": _primer_equipped_abilities.duplicate(),
		"primer_token": _primer_token,
		"primer_generation": _primer_generation,
		"primer_expires_frame": _primer_expires_frame,
		"primer_context": _primer_context.duplicate(true),
		"infusion_until_frame": _infusion_until_frame,
		"infusion_token": _infusion_token,
		"dominion_pair_key": str(_dominion_pair_key),
		"dominion_until_frame": _dominion_until_frame,
		"dominion_token": _dominion_token,
		"next_mastery_echo_until_frame": _next_mastery_echo_until_frame,
		"next_mastery_echo_multiplier": _next_mastery_echo_multiplier,
		"next_mastery_echo_token": _next_mastery_echo_token,
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
		"next_conversion_generation": _next_conversion_generation,
		"talent_state": _talent_state.snapshot(),
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	return _snapshot_is_valid(value)


func restore_snapshot(value: Dictionary) -> bool:
	if not _snapshot_is_valid(value):
		return false
	var before_talent: Dictionary = _talent_state.snapshot()
	if not _talent_state.restore_snapshot((value["talent_state"] as Dictionary).duplicate(true)):
		return false
	_install_snapshot(value)
	if snapshot() == value:
		return true
	_talent_state.restore_snapshot(before_talent)
	return false


func restore_gameplay_rewind_snapshot(value: Dictionary) -> bool:
	# Pages, Primer, Infusion, Dominion, pair effects, and cooldown claims are
	# irreversible gameplay facts. Rewind validates the snapshot but never installs it.
	return _snapshot_is_valid(value)


func presentation_snapshot() -> Dictionary:
	var modifiers := _talent_state.modifier_snapshot()
	return {
		"runtime_kind": str(_runtime_kind),
		"resource_value": int(_resource_value),
		"primer_ability_id": _primer_ability_id,
		"primer_expires_frame": _primer_expires_frame,
		"infusion_until_frame": _infusion_until_frame,
		"dominion_pair_key": _dominion_pair_key,
		"dominion_until_frame": _dominion_until_frame,
		"pair_window_frames": int(modifiers.get("pair_window_frames", 300)),
		"infusion_energy_cost": int(modifiers.get("infusion_energy_cost", 10)),
		"dominion_energy_cost": int(modifiers.get("dominion_energy_cost", 60)),
		"dominion_cooldown_frames": int(modifiers.get("dominion_cooldown_frames", 480)),
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
	}


func character_action_cancellation_state() -> Dictionary:
	return {"active": false, "committed": false}


func cancel_uncommitted_action(_reason: StringName) -> Dictionary:
	return {"ok": true, "cancelled": false}


func _pair_conversion(pair_key: StringName, enhanced: bool, first: Dictionary, second: Dictionary) -> Dictionary:
	var merged := first.duplicate(true)
	for key: Variant in second.keys():
		merged[key] = second[key]
	match pair_key:
		&"stop+rewind":
			var origin_value: Variant = merged.get("pre_return_position")
			if typeof(origin_value) != TYPE_VECTOR2 or not _finite_vector(origin_value as Vector2):
				return {}
			return {"conversion_id": &"stasis_zone", "parameters": {
				"origin": origin_value,
				"radius": 128.0 if enhanced else 96.0,
				"duration_frames": 150 if enhanced else 90,
				"hostile_speed_scalar": 0.35 if enhanced else 0.50,
				"damage": 0.0,
			}}
		&"stop+rift":
			return {"conversion_id": &"rift_projectile_slow", "parameters": {
				"hostile_projectile_speed_scalar": 0.35 if enhanced else 0.50,
				"overlap_cap_frames": 240 if enhanced else 180,
				"stop_until_frame": int(merged.get("stop_until_frame", -1)),
				"rift_until_frame": int(merged.get("rift_until_frame", -1)),
			}}
		&"stop+accelerate":
			return {"conversion_id": &"recovery_acceleration", "parameters": {
				"recovery_multiplier": 0.65 if enhanced else 0.80,
				"duration_frames": 150 if enhanced else 90,
				"minimum_recovery_frames": 1,
				"activates_at_stop_end_frame": int(merged.get("stop_until_frame", -1)),
			}}
		&"rewind+rift":
			var pulse_origin_value: Variant = merged.get("pre_return_position")
			var radius_value: Variant = merged.get("rift_radius")
			var attack_value: Variant = merged.get("attack")
			if (
				typeof(pulse_origin_value) != TYPE_VECTOR2
				or not _finite_vector(pulse_origin_value as Vector2)
				or not _finite_number(radius_value)
				or float(radius_value) <= 0.0
				or not _finite_number(attack_value)
				or float(attack_value) <= 0.0
			):
				return {}
			var pulse_multiplier := 1.75 if enhanced else 1.25
			return {"conversion_id": &"rift_rewind_pulse", "parameters": {
				"origin": pulse_origin_value,
				"radius": float(radius_value),
				"damage_multiplier": pulse_multiplier,
				"damage": float(attack_value) * pulse_multiplier,
				"damage_type": &"time",
				"one_hit_per_target": true,
				"knockback": 0.0,
			}}
		&"rewind+accelerate":
			return {"conversion_id": &"next_mastery_echo", "parameters": {
				"echo_multiplier": 1.10 if enhanced else 0.75,
				"expiry_frames": 300 if enhanced else 180,
				"non_recursive": true,
				"one_target_claim": true,
			}}
		&"accelerate+rift":
			return {"conversion_id": &"rift_tick_acceleration", "parameters": {
				"tick_interval_multiplier": 0.50 if enhanced else 0.75,
				"overlap_cap_frames": 240 if enhanced else 180,
				"preserve_tick_count": true,
				"preserve_total_damage": true,
			}}
	return {}


func _primer_context_from(time_context: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field: String in [
		"pre_return_position",
		"stop_until_frame",
		"rift_until_frame",
		"rift_generation",
		"rift_radius",
		"attack",
	]:
		if time_context.has(field):
			result[field] = time_context[field]
	return result


func _normalized_mastery(value: Dictionary) -> Dictionary:
	if (
		not _configured
		or typeof(value.get("generation")) != TYPE_INT
		or int(value["generation"]) <= 0
		or typeof(value.get("action_token")) != TYPE_INT
		or int(value["action_token"]) <= 0
		or not _valid_segment(value.get("weapon_id"))
		or not _valid_segment(value.get("mastery_family"))
		or StringName(value["weapon_id"]) != StringName(value["mastery_family"])
		or not (_profile_snapshot.get("weapon_mastery", {}) as Dictionary).has(str(value["weapon_id"]))
		or not value.get("context") is Dictionary
	):
		return {}
	var context := value["context"] as Dictionary
	if not _valid_live_context(context) or not _context_matches_run(context):
		return {}
	return {
		"weapon_id": StringName(value["weapon_id"]),
		"mastery_family": StringName(value["mastery_family"]),
		"generation": int(value["generation"]),
		"action_token": int(value["action_token"]),
		"context": context.duplicate(true),
	}


func _valid_echo_source(context: Dictionary) -> bool:
	return (
		bool(context.get("approved_echo", false))
		and _finite_number(context.get("attack"))
		and float(context["attack"]) > 0.0
		and typeof(context.get("position")) == TYPE_VECTOR2
		and _finite_vector(context["position"] as Vector2)
	)


func _valid_time_context(value: Dictionary) -> bool:
	return (
		_valid_live_context(value)
		and StringName(str(value.get("ability_id", ""))) in TIME_ABILITY_ORDER
		and typeof(value.get("token")) == TYPE_INT
		and int(value["token"]) > 0
		and typeof(value.get("generation")) == TYPE_INT
		and int(value["generation"]) > 0
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
		and (_run_id == &"" or (StringName(value["run_id"]) == _run_id and int(value["run_revision"]) == _run_revision))
	)


func _valid_room_context(value: Dictionary) -> bool:
	return (
		_valid_segment(value.get("run_id"))
		and typeof(value.get("run_revision")) == TYPE_INT
		and int(value["run_revision"]) > 0
		and _valid_segment(value.get("room_id"))
		and typeof(value.get("room_revision")) == TYPE_INT
		and int(value["room_revision"]) > 0
	)


func _valid_skill_intent(intent: Dictionary) -> bool:
	return (
		StringName(str(intent.get("id", ""))) == &"character_skill"
		and StringName(str(intent.get("edge", ""))) == &"released"
		and typeof(intent.get("held_frames")) == TYPE_INT
		and int(intent["held_frames"]) >= 0
	)


func _valid_skill_plan(plan: Dictionary) -> bool:
	if (
		not _configured
		or StringName(str(plan.get("skill_id", ""))) != &"codex_dominion"
		or StringName(str(plan.get("mode", ""))) not in [&"infusion", &"dominion"]
		or typeof(plan.get("runtime_frame")) != TYPE_INT
		or int(plan["runtime_frame"]) != _last_runtime_frame
		or not _valid_segment(plan.get("run_id"))
		or typeof(plan.get("run_revision")) != TYPE_INT
		or int(plan["run_revision"]) <= 0
		or typeof(plan.get("owner_character_generation")) != TYPE_INT
		or int(plan["owner_character_generation"]) <= 0
		or typeof(plan.get("held_frames")) != TYPE_INT
		or int(plan["held_frames"]) < 0
		or not _finite_number(plan.get("energy_cost"))
		or typeof(plan.get("page_cost")) != TYPE_INT
		or typeof(plan.get("cooldown_frames")) != TYPE_INT
		or int(plan["cooldown_frames"]) <= 0
		or typeof(plan.get("duration_frames")) != TYPE_INT
		or int(plan["duration_frames"]) <= 0
		or typeof(plan.get("strategy_revision")) != TYPE_INT
		or int(plan["strategy_revision"]) != _revision
		or typeof(plan.get("talent_state_revision")) != TYPE_INT
		or not plan.get("talent_modifiers") is Dictionary
		or plan["talent_modifiers"] != _talent_state.modifier_snapshot()
	):
		return false
	var mode := StringName(plan["mode"])
	if mode == &"infusion":
		return (
			float(plan["energy_cost"]) == float(_talent_state.modifier_snapshot().get("infusion_energy_cost", 10))
			and int(plan["page_cost"]) == 0
			and int(plan["cooldown_frames"]) == _skill_cooldown_frames()
			and int(plan["duration_frames"]) == _skill_parameter_int("infusion_duration_frames")
		)
	var equipped := _canonical_equipped_pair(plan.get("equipped_time_abilities"))
	return (
		not equipped.is_empty()
		and StringName(str(plan.get("pair_key", ""))) == _pair_key(StringName(equipped[0]), StringName(equipped[1]))
		and float(plan["energy_cost"]) == float(_talent_state.modifier_snapshot().get("dominion_energy_cost", 60))
		and int(plan["page_cost"]) == _skill_parameter_int("dominion_page_cost")
		and int(plan["cooldown_frames"]) == int(_talent_state.modifier_snapshot().get("dominion_cooldown_frames", 480))
		and int(plan["duration_frames"]) == _skill_parameter_int("dominion_charge_frames")
	)


func _canonical_equipped_pair(value: Variant) -> Array[String]:
	if not value is Array and not value is PackedStringArray:
		return []
	var requested: Array[StringName] = []
	for ability_value: Variant in value:
		if typeof(ability_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return []
		var ability_id := StringName(str(ability_value))
		if ability_id not in TIME_ABILITY_ORDER or requested.has(ability_id):
			return []
		requested.append(ability_id)
	if requested.size() != 2:
		return []
	var result: Array[String] = []
	for ability_id: StringName in TIME_ABILITY_ORDER:
		if requested.has(ability_id):
			result.append(str(ability_id))
	return result


func _pair_key(first: StringName, second: StringName) -> StringName:
	var ordered := _canonical_equipped_pair([first, second])
	return StringName("%s+%s" % [ordered[0], ordered[1]]) if ordered.size() == 2 else &""


func _time_claim_key(value: Dictionary) -> String:
	if not _valid_time_context(value):
		return ""
	return "%d:%d:%s" % [int(value["generation"]), int(value["token"]), str(value["ability_id"])]


func _bind_run(run_id: StringName, run_revision: int, owner_generation: int) -> bool:
	if run_id == &"" or run_revision <= 0 or owner_generation <= 0:
		return false
	if _run_id == &"":
		_run_id = run_id
		_run_revision = run_revision
		_owner_character_generation = owner_generation
		return true
	return run_id == _run_id and run_revision == _run_revision and owner_generation == _owner_character_generation


func _context_matches_run(value: Dictionary) -> bool:
	return (
		_run_id != &""
		and _valid_segment(value.get("run_id"))
		and StringName(value["run_id"]) == _run_id
		and typeof(value.get("run_revision")) == TYPE_INT
		and int(value["run_revision"]) == _run_revision
	)


func _resource_event(frame: int, token: int, reason: StringName) -> Dictionary:
	return _event(&"character_resource_changed", frame, token, {
		"resource_id": &"codex_pages",
		"current": int(_resource_value),
		"maximum": _resource_maximum(),
		"reason": reason,
	})


func _cooldown_event(frame: int, duration: int, reason: StringName) -> Dictionary:
	return _event(&"character_cooldown_started", frame, 0, {
		"skill_id": &"codex_dominion",
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


func _clear_primer() -> void:
	_primer_ability_id = &""
	_primer_pair_key = &""
	_primer_equipped_abilities.clear()
	_primer_token = 0
	_primer_generation = 0
	_primer_expires_frame = -1
	_primer_context.clear()


func _clear_dominion() -> void:
	_dominion_pair_key = &""
	_dominion_until_frame = -1
	_dominion_token = 0


func _clear_next_mastery_echo() -> void:
	_next_mastery_echo_until_frame = -1
	_next_mastery_echo_multiplier = 0.0
	_next_mastery_echo_token = 0


func _resource_maximum() -> int:
	return int((_profile_snapshot.get("resource", {}) as Dictionary).get("maximum", 3))


func _page_rate_cap_frames() -> int:
	return int((((_profile_snapshot.get("passive", {}) as Dictionary).get("parameters", {}) as Dictionary).get("page_rate_cap_frames", 60)))


func _pair_window_frames() -> int:
	return int(_talent_state.modifier_snapshot().get("pair_window_frames", 300))


func _skill_parameter_int(key: String) -> int:
	return int((((_profile_snapshot.get("character_skill", {}) as Dictionary).get("parameters", {}) as Dictionary).get(key, 0)))


func _skill_parameter_float(key: String) -> float:
	return float((((_profile_snapshot.get("character_skill", {}) as Dictionary).get("parameters", {}) as Dictionary).get(key, 0.0)))


func _skill_cooldown_frames() -> int:
	return int((_profile_snapshot.get("character_skill", {}) as Dictionary).get("cooldown_frames", 0))


func _reset_strategy_state() -> void:
	_run_id = &""
	_run_revision = 0
	_owner_character_generation = 1
	_mastery_claims.clear()
	_time_claims.clear()
	_last_page_grant_frame = -1
	_clear_primer()
	_infusion_until_frame = -1
	_infusion_token = 0
	_clear_dominion()
	_clear_next_mastery_echo()
	_skill_cooldown_until_frame = -1
	_next_conversion_generation = 1


func _valid_next_frame(context: Dictionary) -> bool:
	return (
		_configured
		and typeof(context.get("runtime_frame")) == TYPE_INT
		and int(context["runtime_frame"]) >= 0
		and int(context["runtime_frame"]) > _last_runtime_frame
	)


func _snapshot_is_valid(value: Dictionary) -> bool:
	if not _has_exact_fields(value, STRATEGY_SNAPSHOT_FIELDS):
		return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != STRATEGY_SNAPSHOT_SCHEMA_VERSION
		or typeof(value["runtime_kind"]) != TYPE_STRING
		or StringName(value["runtime_kind"]) != _runtime_kind
		or typeof(value["configured"]) != TYPE_BOOL
		or bool(value["configured"]) != _configured
		or typeof(value["last_runtime_frame"]) != TYPE_INT
		or int(value["last_runtime_frame"]) < -1
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < 0
		or typeof(value["resource_value"]) != TYPE_INT
		or int(value["resource_value"]) < 0
		or int(value["resource_value"]) > _resource_maximum()
		or typeof(value["run_id"]) != TYPE_STRING
		or typeof(value["run_revision"]) != TYPE_INT
		or int(value["run_revision"]) < 0
		or typeof(value["owner_character_generation"]) != TYPE_INT
		or int(value["owner_character_generation"]) <= 0
		or not value["mastery_claims"] is Array
		or not value["time_claims"] is Array
		or typeof(value["last_page_grant_frame"]) != TYPE_INT
		or typeof(value["primer_ability_id"]) != TYPE_STRING
		or not str(value["primer_ability_id"]).is_empty() and StringName(value["primer_ability_id"]) not in TIME_ABILITY_ORDER
		or typeof(value["primer_pair_key"]) != TYPE_STRING
		or not value["primer_equipped_abilities"] is Array
		or typeof(value["primer_token"]) != TYPE_INT
		or typeof(value["primer_generation"]) != TYPE_INT
		or typeof(value["primer_expires_frame"]) != TYPE_INT
		or not value["primer_context"] is Dictionary
		or typeof(value["infusion_until_frame"]) != TYPE_INT
		or typeof(value["infusion_token"]) != TYPE_INT
		or typeof(value["dominion_pair_key"]) != TYPE_STRING
		or typeof(value["dominion_until_frame"]) != TYPE_INT
		or typeof(value["dominion_token"]) != TYPE_INT
		or typeof(value["next_mastery_echo_until_frame"]) != TYPE_INT
		or not _finite_number(value["next_mastery_echo_multiplier"])
		or float(value["next_mastery_echo_multiplier"]) < 0.0
		or typeof(value["next_mastery_echo_token"]) != TYPE_INT
		or typeof(value["skill_cooldown_until_frame"]) != TYPE_INT
		or typeof(value["next_conversion_generation"]) != TYPE_INT
		or int(value["next_conversion_generation"]) <= 0
		or not value["talent_state"] is Dictionary
		or not _talent_state.can_restore_snapshot(value["talent_state"] as Dictionary)
		or not ReplaySafeValueScript.is_supported(value)
	):
		return false
	var primer_empty := str(value["primer_ability_id"]).is_empty()
	if primer_empty != str(value["primer_pair_key"]).is_empty():
		return false
	if primer_empty:
		if int(value["primer_token"]) != 0 or int(value["primer_generation"]) != 0 or int(value["primer_expires_frame"]) != -1 or not (value["primer_context"] as Dictionary).is_empty():
			return false
	else:
		if int(value["primer_token"]) <= 0 or int(value["primer_generation"]) <= 0 or int(value["primer_expires_frame"]) <= int(value["last_runtime_frame"]):
			return false
		var primer_pair := _canonical_equipped_pair(value["primer_equipped_abilities"])
		if primer_pair.is_empty() or StringName(value["primer_pair_key"]) != _pair_key(StringName(primer_pair[0]), StringName(primer_pair[1])):
			return false
	return true


func _install_snapshot(value: Dictionary) -> void:
	_last_runtime_frame = int(value["last_runtime_frame"])
	_revision = int(value["revision"])
	_resource_value = int(value["resource_value"])
	_run_id = StringName(value["run_id"])
	_run_revision = int(value["run_revision"])
	_owner_character_generation = int(value["owner_character_generation"])
	_mastery_claims.assign(value["mastery_claims"])
	_time_claims.assign(value["time_claims"])
	_last_page_grant_frame = int(value["last_page_grant_frame"])
	_primer_ability_id = StringName(value["primer_ability_id"])
	_primer_pair_key = StringName(value["primer_pair_key"])
	_primer_equipped_abilities.assign(value["primer_equipped_abilities"])
	_primer_token = int(value["primer_token"])
	_primer_generation = int(value["primer_generation"])
	_primer_expires_frame = int(value["primer_expires_frame"])
	_primer_context = (value["primer_context"] as Dictionary).duplicate(true)
	_infusion_until_frame = int(value["infusion_until_frame"])
	_infusion_token = int(value["infusion_token"])
	_dominion_pair_key = StringName(value["dominion_pair_key"])
	_dominion_until_frame = int(value["dominion_until_frame"])
	_dominion_token = int(value["dominion_token"])
	_next_mastery_echo_until_frame = int(value["next_mastery_echo_until_frame"])
	_next_mastery_echo_multiplier = float(value["next_mastery_echo_multiplier"])
	_next_mastery_echo_token = int(value["next_mastery_echo_token"])
	_skill_cooldown_until_frame = int(value["skill_cooldown_until_frame"])
	_next_conversion_generation = int(value["next_conversion_generation"])


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _valid_segment(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := str(value)
	return not text.is_empty() and text == text.strip_edges() and text.length() <= 64 and not text.contains("\n") and not text.contains("\r") and not text.contains("\t")


static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	for key: Variant in value.keys():
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not fields.has(str(key)):
			return false
	return true
