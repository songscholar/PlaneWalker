class_name HubSceneHost
extends Node2D

signal function_requested(function_id: String, epoch: int)
signal district_changed(district_id: String, epoch: int)

const Result := preload("res://scripts/application/command_result.gd")
const DistrictScene := preload("res://scripts/hub/hub_district_scene.gd")
const DEFINITIONS_PATH := "res://data/content_packs/base/content/hub_districts.json"

var _active: Node2D
var _definition: Dictionary = {}
var _epoch := 0
var _interaction_enabled := true


func install_district(definition: Dictionary):
	if not is_inside_tree() or not _authored_definition(definition):
		return Result.failure(&"INVALID_ARGUMENT", _epoch, {"field": "hub_district"})
	if definition == _definition and is_instance_valid(_active):
		return Result.success(_epoch)
	var scene: Variant = load(str(definition.scene_path))
	if not scene is PackedScene:
		return Result.failure(&"CONTENT_NOT_AVAILABLE", _epoch)
	var candidate: Node = scene.instantiate()
	if not candidate is DistrictScene or not candidate.populate(definition):
		candidate.free()
		return Result.failure(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", _epoch)
	_epoch += 1
	var epoch := _epoch
	if is_instance_valid(_active):
		remove_child(_active)
		_active.queue_free()
	_active = candidate
	_definition = definition.duplicate(true)
	add_child(_active)
	_active.set_interaction_enabled(_interaction_enabled)
	_active.function_requested.connect(func(id: String): request_function(id, epoch))
	district_changed.emit(str(definition.id), epoch)
	return Result.success(epoch)


func request_function(id: String, expected_epoch: int):
	if not _interaction_enabled or get_tree().paused or not is_instance_valid(_active) or expected_epoch != _epoch:
		return Result.failure(&"INVALID_PHASE", _epoch)
	if not _active.function_ids().has(id):
		return Result.failure(&"INVALID_ARGUMENT", _epoch, {"field": "function_id"})
	function_requested.emit(id, _epoch)
	return Result.success(_epoch)


func set_interaction_enabled(value: bool) -> void:
	_interaction_enabled = value
	if is_instance_valid(_active):
		_active.set_interaction_enabled(value)


func refresh_localization() -> void:
	if is_instance_valid(_active):
		_active.refresh_localization()


func snapshot() -> Dictionary:
	return {
		"district_id": str(_definition.get("id", "")), "epoch": _epoch,
		"arrival": Vector2(_definition.get("arrival", {}).get("x", 0), _definition.get("arrival", {}).get("y", 0)),
		"walker_position": _active.walker_position() if is_instance_valid(_active) else Vector2.ZERO,
		"function_ids": _active.function_ids() if is_instance_valid(_active) else [],
		"interaction_enabled": _interaction_enabled,
	}


func reachable_position(value: Vector2) -> bool:
	return value.is_finite() and DistrictScene.WALK_BOUNDS.has_point(value)


func _authored_definition(value: Dictionary) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFINITIONS_PATH))
	if not parsed is Array:
		return false
	for definition: Dictionary in parsed:
		if definition.get("id") == value.get("id"):
			return definition == value
	return false
