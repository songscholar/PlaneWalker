class_name CharacterRuntime
extends RefCounted

const CharacterRuntimeProfileScript := preload(
	"res://scripts/player/characters/character_runtime_profile.gd"
)
const SNAPSHOT_SCHEMA_VERSION := 1
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"runtime_kind",
	"configured",
	"last_runtime_frame",
	"revision",
	"resource_value",
]

var _runtime_kind: StringName = &""
var _configured: bool = false
var _owner_ref: WeakRef
var _profile_snapshot: Dictionary = {}
var _selected_talent_ids: PackedStringArray = PackedStringArray()
var _last_runtime_frame: int = -1
var _revision: int = 0
var _resource_value: Variant = 0


func _init(runtime_kind_value: StringName = &"") -> void:
	_runtime_kind = runtime_kind_value


func runtime_kind() -> StringName:
	return _runtime_kind


func configure(owner: Node, profile: Variant, talents: PackedStringArray) -> bool:
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
	var profile_snapshot := (profile_value as Dictionary).duplicate(true)
	if (
		_runtime_kind == &""
		or StringName(str(profile_snapshot.get("runtime_kind", ""))) != _runtime_kind
	):
		return false
	var allowed_talents: Array = profile_snapshot.get("talent_ids", [])
	var installed_talents: Array[String] = []
	for talent_id: String in talents:
		if (
			talent_id.is_empty()
			or installed_talents.has(talent_id)
			or not allowed_talents.has(talent_id)
		):
			return false
		installed_talents.append(talent_id)
	var resource_value: Variant = 0
	var resource: Variant = profile_snapshot.get("resource", {})
	if resource is Dictionary:
		resource_value = int((resource as Dictionary).get("initial", 0))

	_owner_ref = weakref(owner)
	_profile_snapshot = profile_snapshot
	_selected_talent_ids = talents.duplicate()
	_last_runtime_frame = -1
	_revision = 0
	_resource_value = resource_value
	_configured = true
	return true


func reset_runtime_state(_reason: StringName) -> void:
	if not _configured:
		return
	_last_runtime_frame = -1
	var resource: Variant = _profile_snapshot.get("resource", {})
	_resource_value = (
		int((resource as Dictionary).get("initial", 0))
		if resource is Dictionary
		else 0
	)
	_revision += 1


func advance_frame(context: Dictionary) -> Array[Dictionary]:
	if not _configured or typeof(context.get("runtime_frame")) != TYPE_INT:
		return []
	var runtime_frame := int(context["runtime_frame"])
	if runtime_frame < 0 or runtime_frame <= _last_runtime_frame:
		return []
	_last_runtime_frame = runtime_frame
	_revision += 1
	return []


func plan_character_skill(_intent: Dictionary, _context: Dictionary) -> Dictionary:
	return {"ok": false, "code": "unsupported"}


func commit_character_skill(_plan: Dictionary, _token: int) -> Dictionary:
	return {"ok": false, "code": "unsupported"}


func before_damage(_damage_context: Dictionary) -> Dictionary:
	return {"ok": true, "decision": {}}


func after_damage(_damage_context: Dictionary) -> Array[Dictionary]:
	return []


func on_weapon_action_committed(_action_context: Dictionary) -> Array[Dictionary]:
	return []


func on_weapon_mastery_confirmed(_mastery_context: Dictionary) -> Array[Dictionary]:
	return []


func before_time_skill(_time_context: Dictionary) -> Dictionary:
	return {"ok": true, "decision": {}}


func after_time_skill(_time_context: Dictionary) -> Array[Dictionary]:
	return []


func on_room_started(_room_context: Dictionary) -> Array[Dictionary]:
	return []


func on_room_cleared(_room_context: Dictionary) -> Array[Dictionary]:
	return []


func on_run_terminal(_run_context: Dictionary) -> Dictionary:
	return {"ok": true, "summary": {}}


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"runtime_kind": str(_runtime_kind),
		"configured": _configured,
		"last_runtime_frame": _last_runtime_frame,
		"revision": _revision,
		"resource_value": _resource_value,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return false
	return (
		typeof(value["schema_version"]) == TYPE_INT
		and int(value["schema_version"]) == SNAPSHOT_SCHEMA_VERSION
		and typeof(value["runtime_kind"]) == TYPE_STRING
		and StringName(str(value["runtime_kind"])) == _runtime_kind
		and typeof(value["configured"]) == TYPE_BOOL
		and bool(value["configured"]) == _configured
		and typeof(value["last_runtime_frame"]) == TYPE_INT
		and int(value["last_runtime_frame"]) >= -1
		and typeof(value["revision"]) == TYPE_INT
		and int(value["revision"]) >= 0
		and typeof(value["resource_value"]) == TYPE_INT
		and _resource_value_in_profile_range(int(value["resource_value"]))
	)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_last_runtime_frame = int(value["last_runtime_frame"])
	_revision = int(value["revision"])
	_resource_value = value["resource_value"]
	return snapshot() == value


func presentation_snapshot() -> Dictionary:
	return {
		"runtime_kind": str(_runtime_kind),
		"resource_value": _resource_value,
	}


func can_reanchor_replay_neutral_frame(runtime_frame: int) -> bool:
	var profile_id := str(_profile_snapshot.get("id", ""))
	if (
		not _configured
		or runtime_frame < 0
		or not _selected_talent_ids.is_empty()
		or str(_profile_snapshot.get("character_id", "")) != "wanderer"
		or not (
			(profile_id == "wanderer_m1_v1" and _runtime_kind == &"wanderer_m1_compat")
			or (profile_id == "wanderer_launch_v1" and _runtime_kind == &"wanderer")
		)
	):
		return false
	var resource := _profile_snapshot.get("resource", {}) as Dictionary
	if int(_resource_value) != int(resource.get("initial", 0)):
		return false
	if profile_id == "wanderer_m1_v1":
		return (
			StringName(str(resource.get("resource_id", ""))) == &"none"
			and StringName(str(resource.get("handler_id", ""))) == &"none"
		)
	return (
		StringName(str(resource.get("resource_id", ""))) == &"path_marks"
		and StringName(str(resource.get("handler_id", ""))) == &"path_marks"
	)


func reanchor_replay_neutral_frame(runtime_frame: int) -> bool:
	if not can_reanchor_replay_neutral_frame(runtime_frame):
		return false
	_last_runtime_frame = runtime_frame
	_revision += 1
	return true


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


func _resource_value_in_profile_range(value: int) -> bool:
	if not _configured:
		return value == 0
	var resource: Variant = _profile_snapshot.get("resource", {})
	if not resource is Dictionary:
		return false
	return (
		value >= int((resource as Dictionary).get("minimum", 0))
		and value <= int((resource as Dictionary).get("maximum", 0))
	)
