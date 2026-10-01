class_name PlayerCharacterRuntime
extends RefCounted

const CharacterRuntimeFactoryScript := preload(
	"res://scripts/player/characters/character_runtime_factory.gd"
)
const CharacterRuntimeProfileScript := preload(
	"res://scripts/player/characters/character_runtime_profile.gd"
)

const SNAPSHOT_SCHEMA_VERSION := 1
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"configured",
	"profile",
	"selected_talent_ids",
	"strategy",
]

var _configured: bool = false
var _owner_ref: WeakRef
var _profile: RefCounted
var _profile_snapshot: Dictionary = {}
var _selected_talent_ids: Array[String] = []
var _strategy: RefCounted
var _restore_integrity_ok: bool = true
var _restore_failure_reason: StringName = &""


func configure(owner: Node, profile: Variant, talents: Variant) -> bool:
	if (
		owner == null
		or not is_instance_valid(owner)
		or profile == null
		or not profile is RefCounted
		or profile.get_script() != CharacterRuntimeProfileScript
		or not profile.has_method("snapshot")
	):
		return false
	var profile_value: Variant = profile.call("snapshot")
	if not profile_value is Dictionary:
		return false
	var candidate_profile: Variant = CharacterRuntimeProfileScript.from_definition(
		(profile_value as Dictionary).duplicate(true)
	)
	if candidate_profile == null:
		return false
	var candidate_talents := _canonical_talent_subset(candidate_profile, talents)
	if not bool(candidate_talents.get("ok", false)):
		return false
	var runtime_kind := StringName(str(candidate_profile.get("runtime_kind")))
	var candidate_strategy: Variant = CharacterRuntimeFactoryScript.create(runtime_kind)
	if candidate_strategy == null or not candidate_strategy is RefCounted:
		return false
	var selected := PackedStringArray(candidate_talents.get("talents", []))
	if not bool(candidate_strategy.call("configure", owner, candidate_profile, selected)):
		return false

	_owner_ref = weakref(owner)
	_profile = candidate_profile as RefCounted
	_profile_snapshot = (_profile.call("snapshot") as Dictionary).duplicate(true)
	_selected_talent_ids.clear()
	for talent_value: Variant in selected:
		_selected_talent_ids.append(str(talent_value))
	_strategy = candidate_strategy as RefCounted
	_configured = true
	_restore_integrity_ok = true
	_restore_failure_reason = &""
	return true


func runtime_kind() -> StringName:
	return StringName(str(_profile_snapshot.get("runtime_kind", "")))


func character_id() -> StringName:
	return StringName(str(_profile_snapshot.get("character_id", "")))


func profile_id() -> StringName:
	return StringName(str(_profile_snapshot.get("id", "")))


func selected_talent_ids() -> Array[String]:
	return _selected_talent_ids.duplicate()


func profile_snapshot() -> Dictionary:
	return _profile_snapshot.duplicate(true)


func reset_runtime_state(reason: StringName) -> void:
	if _strategy != null and _restore_integrity_ok:
		_strategy.call("reset_runtime_state", reason)


func advance_frame(context: Dictionary) -> Variant:
	if _strategy == null:
		return []
	if not _restore_integrity_ok:
		return {"runtime_fault": str(_restore_failure_reason)}
	var value: Variant = _strategy.call("advance_frame", context.duplicate(true))
	return _isolated_event_result(value)


func plan_character_skill(intent: Dictionary, context: Dictionary) -> Dictionary:
	if _strategy == null or not _restore_integrity_ok:
		return {"ok": false, "code": "not_configured"}
	var value: Variant = _strategy.call(
		"plan_character_skill",
		intent.duplicate(true),
		context.duplicate(true)
	)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {
		"ok": false,
		"code": "invalid_result",
	}


func commit_character_skill(plan: Dictionary, token: int) -> Dictionary:
	if _strategy == null or not _restore_integrity_ok:
		return {"ok": false, "code": "not_configured"}
	var value: Variant = _strategy.call(
		"commit_character_skill",
		plan.duplicate(true),
		token
	)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {
		"ok": false,
		"code": "invalid_result",
	}


func before_damage(damage_context: Dictionary) -> Dictionary:
	return _decision_hook(&"before_damage", damage_context)


func after_damage(damage_context: Dictionary) -> Variant:
	return _event_hook(&"after_damage", damage_context)


func on_weapon_action_committed(action_context: Dictionary) -> Variant:
	return _event_hook(&"on_weapon_action_committed", action_context)


func on_weapon_mastery_confirmed(mastery_context: Dictionary) -> Variant:
	return _event_hook(&"on_weapon_mastery_confirmed", mastery_context)


func before_time_skill(time_context: Dictionary) -> Dictionary:
	return _decision_hook(&"before_time_skill", time_context)


func after_time_skill(time_context: Dictionary) -> Variant:
	return _event_hook(&"after_time_skill", time_context)


func on_room_started(room_context: Dictionary) -> Variant:
	return _event_hook(&"on_room_started", room_context)


func on_room_cleared(room_context: Dictionary) -> Variant:
	return _event_hook(&"on_room_cleared", room_context)


func on_run_terminal(run_context: Dictionary) -> Dictionary:
	if _strategy == null or not _restore_integrity_ok:
		return {"ok": false, "summary": {}}
	var value: Variant = _strategy.call("on_run_terminal", run_context.duplicate(true))
	return (value as Dictionary).duplicate(true) if value is Dictionary else {
		"ok": false,
		"summary": {},
	}


func snapshot() -> Dictionary:
	var strategy_snapshot: Dictionary = {}
	if _strategy != null:
		var strategy_value: Variant = _strategy.call("snapshot")
		if strategy_value is Dictionary:
			strategy_snapshot = (strategy_value as Dictionary).duplicate(true)
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"configured": _configured,
		"profile": _profile_snapshot.duplicate(true),
		"selected_talent_ids": _selected_talent_ids.duplicate(),
		"strategy": strategy_snapshot,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _restore_integrity_ok or not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SNAPSHOT_SCHEMA_VERSION
		or typeof(value["configured"]) != TYPE_BOOL
		or bool(value["configured"]) != _configured
		or not value["profile"] is Dictionary
		or not value["selected_talent_ids"] is Array
		or not value["strategy"] is Dictionary
	):
		return false
	if not _configured:
		return (
			(value["profile"] as Dictionary).is_empty()
			and (value["selected_talent_ids"] as Array).is_empty()
			and (value["strategy"] as Dictionary).is_empty()
		)
	if (
		_profile == null
		or _strategy == null
		or value["profile"] != _profile_snapshot
		or value["selected_talent_ids"] != _selected_talent_ids
	):
		return false
	var accepted: Variant = _strategy.call(
		"can_restore_snapshot",
		(value["strategy"] as Dictionary).duplicate(true)
	)
	return typeof(accepted) == TYPE_BOOL and bool(accepted)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	if not _configured:
		return snapshot() == value
	var before_value: Variant = _strategy.call("snapshot")
	if not before_value is Dictionary:
		return false
	var before := (before_value as Dictionary).duplicate(true)
	var restored: Variant = _strategy.call(
		"restore_snapshot",
		(value["strategy"] as Dictionary).duplicate(true)
	)
	if (
		typeof(restored) == TYPE_BOOL
		and bool(restored)
		and _strategy_snapshot_matches(value["strategy"] as Dictionary)
		and snapshot() == value
	):
		return true
	var rollback_value: Variant = _strategy.call("restore_snapshot", before.duplicate(true))
	if (
		typeof(rollback_value) != TYPE_BOOL
		or not bool(rollback_value)
		or not _strategy_snapshot_matches(before)
	):
		_restore_integrity_ok = false
		_restore_failure_reason = &"strategy_restore_rollback_failed"
	return false


func restore_integrity_ok() -> bool:
	return _restore_integrity_ok


func restore_failure_reason() -> StringName:
	return _restore_failure_reason


func presentation_snapshot() -> Dictionary:
	if not _configured or _strategy == null or not _restore_integrity_ok:
		return {}
	var resource := _profile_snapshot.get("resource", {}) as Dictionary
	var skill := _profile_snapshot.get("character_skill", {}) as Dictionary
	var presentation := _profile_snapshot.get("presentation", {}) as Dictionary
	var strategy_presentation_value: Variant = _strategy.call("presentation_snapshot")
	var strategy_presentation := (
		(strategy_presentation_value as Dictionary).duplicate(true)
		if strategy_presentation_value is Dictionary
		else {}
	)
	return {
		"profile_id": str(_profile_snapshot.get("id", "")),
		"profile_version": int(_profile_snapshot.get("profile_version", 0)),
		"character_id": str(_profile_snapshot.get("character_id", "")),
		"runtime_kind": str(_profile_snapshot.get("runtime_kind", "")),
		"selected_talent_ids": _selected_talent_ids.duplicate(),
		"palette_id": str(presentation.get("palette_id", "")),
		"meter_id": str(presentation.get("meter_id", "")),
		"skill_cue_id": str(presentation.get("skill_cue_id", "")),
		"resource_id": str(resource.get("resource_id", "")),
		"resource_minimum": int(resource.get("minimum", 0)),
		"resource_maximum": int(resource.get("maximum", 0)),
		"resource_value": int(strategy_presentation.get(
			"resource_value",
			resource.get("initial", 0)
		)),
		"character_skill_id": str(skill.get("skill_id", "")),
	}


func can_reanchor_replay_neutral_frame(runtime_frame: int) -> bool:
	var profile_id := str(_profile_snapshot.get("id", ""))
	return (
		_configured
		and _restore_integrity_ok
		and str(_profile_snapshot.get("character_id", "")) == "wanderer"
		and profile_id in ["wanderer_m1_v1", "wanderer_launch_v1"]
		and _selected_talent_ids.is_empty()
		and _strategy != null
		and _strategy.has_method("can_reanchor_replay_neutral_frame")
		and bool(_strategy.call("can_reanchor_replay_neutral_frame", runtime_frame))
	)


func reanchor_replay_neutral_frame(runtime_frame: int) -> bool:
	return (
		can_reanchor_replay_neutral_frame(runtime_frame)
		and bool(_strategy.call("reanchor_replay_neutral_frame", runtime_frame))
	)


func _decision_hook(method_name: StringName, context: Dictionary) -> Dictionary:
	if _strategy == null or not _restore_integrity_ok:
		return {"ok": false, "decision": {}}
	var value: Variant = _strategy.call(method_name, context.duplicate(true))
	return (value as Dictionary).duplicate(true) if value is Dictionary else {
		"ok": false,
		"decision": {},
	}


func _event_hook(method_name: StringName, context: Dictionary) -> Variant:
	if _strategy == null:
		return []
	if not _restore_integrity_ok:
		return {"runtime_fault": str(_restore_failure_reason)}
	return _isolated_event_result(_strategy.call(method_name, context.duplicate(true)))


static func _isolated_event_result(value: Variant) -> Variant:
	if value is Array:
		return (value as Array).duplicate(true)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return value


func _strategy_snapshot_matches(value: Dictionary) -> bool:
	if _strategy == null:
		return false
	var current_value: Variant = _strategy.call("snapshot")
	return current_value is Dictionary and current_value == value


static func _canonical_talent_subset(profile: Variant, talents: Variant) -> Dictionary:
	if not talents is Array and not talents is PackedStringArray:
		return {"ok": false}
	var requested: Array[String] = []
	for talent_value: Variant in talents:
		if typeof(talent_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {"ok": false}
		var talent_id := str(talent_value).strip_edges()
		if talent_id.is_empty() or requested.has(talent_id):
			return {"ok": false}
		requested.append(talent_id)
	var allowed: PackedStringArray = profile.get("talent_ids")
	for talent_id: String in requested:
		if not allowed.has(talent_id):
			return {"ok": false}
	var canonical: Array[String] = []
	for talent_id: String in allowed:
		if requested.has(talent_id):
			canonical.append(talent_id)
	return {"ok": true, "talents": canonical}


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
