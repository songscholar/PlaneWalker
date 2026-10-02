class_name RoomSceneHost
extends Node

signal room_transitioned(receipt: Dictionary)
signal room_transition_failed(context: Dictionary)

const RoomSceneContractScript := preload("res://scripts/dungeon/room_scene_contract.gd")
const RoomTemplateDefinitionScript := preload("res://scripts/dungeon/room_template_definition.gd")
const TRANSITION_TICKET_SCHEMA_VERSION := 1
const TRANSITION_TICKET_FIELDS: Array[String] = [
	"schema_version",
	"host_instance_id",
	"ticket_id",
	"prior_instance_generation",
	"target_content_id",
	"target_node_id",
]

var _active_root: Node
var _active_room: Node2D
var _active_content_id: String = ""
var _active_generation: int = 0
var _pending_transition: Dictionary = {}
var _next_ticket_id: int = 1

var _loader: Callable
var _instantiator: Callable
var _contract_validator: Callable
var _binding_adapter: Callable
var _activation_adapter: Callable


func configure_loader(loader: Callable) -> bool:
	if not loader.is_valid():
		return false
	_loader = loader
	return true


func configure_instantiator(instantiator: Callable) -> bool:
	if not instantiator.is_valid():
		return false
	_instantiator = instantiator
	return true


func configure_contract_validator(validator: Callable) -> bool:
	if not validator.is_valid():
		return false
	_contract_validator = validator
	return true


func configure_binding_adapter(adapter: Callable) -> bool:
	if not adapter.is_valid():
		return false
	_binding_adapter = adapter
	return true


func configure_activation_adapter(adapter: Callable) -> bool:
	if not adapter.is_valid():
		return false
	_activation_adapter = adapter
	return true


func clear_test_adapters() -> void:
	_loader = Callable()
	_instantiator = Callable()
	_contract_validator = Callable()
	_binding_adapter = Callable()
	_activation_adapter = Callable()


func transition_to(node: Dictionary, template: Dictionary, context: Dictionary) -> Dictionary:
	var prepared := prepare_transition(node, template, context)
	if not bool(prepared.get("ok", false)):
		return prepared
	var committed := commit_transition(prepared["ticket"] as Dictionary)
	if not bool(committed.get("ok", false)):
		return committed
	return confirm_transition(prepared["ticket"] as Dictionary)


func prepare_transition(node: Dictionary, template: Dictionary, context: Dictionary) -> Dictionary:
	if not _pending_transition.is_empty():
		return _reject(_failure(
			&"ROOM_SCENE_TRANSITION_BUSY",
			"transition",
			"pending_ticket_exists"
		))
	var authority := _validate_authority(node, template, context)
	if not bool(authority.get("ok", false)):
		return _reject(authority)
	var normalized_template: Dictionary = authority["template"]
	var scene_path := str(normalized_template["scene_path"])
	var resource_value: Variant = (
		_loader.call(scene_path)
		if _loader.is_valid()
		else ResourceLoader.load(scene_path, "PackedScene")
	)
	if resource_value == null:
		return _reject(_failure(&"ROOM_SCENE_LOAD_FAILED", "scene_path", scene_path))
	var instance_value: Variant = (
		_instantiator.call(resource_value)
		if _instantiator.is_valid()
		else _instantiate_resource(resource_value)
	)
	if not instance_value is Node2D:
		_dispose_if_node(instance_value)
		return _reject(_failure(&"ROOM_SCENE_INSTANTIATION_FAILED", "scene", "expected_node2d"))

	var staged_room := instance_value as Node2D
	var staged_root := Node2D.new()
	staged_root.name = "StagedRoomRoot"
	staged_root.process_mode = Node.PROCESS_MODE_DISABLED
	staged_root.add_child(staged_room)
	var contract_value: Variant = (
		_contract_validator.call(staged_room, normalized_template)
		if _contract_validator.is_valid()
		else RoomSceneContractScript.validate(staged_room, normalized_template)
	)
	var contract_result := _normalized_result(contract_value, &"ROOM_SCENE_CONTRACT_FAILED")
	if not bool(contract_result.get("ok", false)):
		_dispose_detached(staged_root)
		return _reject(contract_result)

	var bind_value: Variant = (
		_binding_adapter.call(staged_room, node.duplicate(true), normalized_template.duplicate(true), context.duplicate(true))
		if _binding_adapter.is_valid()
		else _bind_scene(staged_room, node, normalized_template, context)
	)
	var bind_result := _normalized_result(bind_value, &"ROOM_SCENE_BIND_FAILED")
	if not bool(bind_result.get("ok", false)):
		_dispose_detached(staged_root)
		return _reject(bind_result)

	var prepared_value: Variant = (
		_activation_adapter.call(staged_room, true)
		if _activation_adapter.is_valid()
		else _prepare_scene_activation(staged_room)
	)
	var prepared_result := _normalized_result(prepared_value, &"ROOM_SCENE_ACTIVATION_FAILED")
	if not bool(prepared_result.get("ok", false)):
		_dispose_detached(staged_root)
		return _reject(prepared_result)
	var ticket := {
		"schema_version": TRANSITION_TICKET_SCHEMA_VERSION,
		"host_instance_id": get_instance_id(),
		"ticket_id": _next_ticket_id,
		"prior_instance_generation": _active_generation,
		"target_content_id": str(normalized_template["id"]),
		"target_node_id": str(node["id"]),
	}
	_next_ticket_id += 1
	_pending_transition = {
		"ticket": ticket.duplicate(true),
		"stage": "prepared",
		"root": staged_root,
		"room": staged_room,
		"prior_root": _active_root,
		"prior_room": _active_room,
		"prior_content_id": _active_content_id,
		"prior_generation": _active_generation,
		"node": node.duplicate(true),
		"template": normalized_template.duplicate(true),
		"context": context.duplicate(true),
	}
	return {
		"ok": true,
		"code": &"OK",
		"ticket": ticket.duplicate(true),
		"context": {
			"target_content_id": str(normalized_template["id"]),
			"target_node_id": str(node["id"]),
		},
	}


func commit_transition(ticket: Dictionary) -> Dictionary:
	if not _ticket_matches_pending(ticket):
		return _reject(_failure(&"ROOM_SCENE_TICKET_INVALID", "ticket", "mismatch"))
	if str(_pending_transition.get("stage", "")) != "prepared":
		return _reject(_failure(&"ROOM_SCENE_TICKET_INVALID", "ticket", "already_committed"))
	if int(ticket["prior_instance_generation"]) != _active_generation:
		return _reject(_failure(
			&"ROOM_SCENE_TICKET_STALE",
			"ticket.prior_instance_generation",
			"stale"
		))
	var staged_root := _pending_transition["root"] as Node
	var staged_room := _pending_transition["room"] as Node2D
	var node := _pending_transition["node"] as Dictionary
	var normalized_template := _pending_transition["template"] as Dictionary
	var previous_root := _active_root
	var previous_room := _active_room
	var previous_content_id := _active_content_id
	var previous_generation := _active_generation
	staged_root.name = "ActiveRoomRoot"
	staged_root.process_mode = Node.PROCESS_MODE_INHERIT
	add_child(staged_root)
	var activation_value: Variant = (
		_activation_adapter.call(staged_room, false)
		if _activation_adapter.is_valid()
		else _activate_scene(staged_room)
	)
	var activation_result := _normalized_result(
		activation_value,
		&"ROOM_SCENE_ACTIVATION_FAILED"
	)
	if not bool(activation_result.get("ok", false)):
		remove_child(staged_root)
		_dispose_detached(staged_root)
		_pending_transition.clear()
		return _reject(activation_result)

	_active_root = staged_root
	_active_room = staged_room
	_active_content_id = str(normalized_template["id"])
	_active_generation += 1
	if previous_room != null and is_instance_valid(previous_room):
		if previous_room.has_method("deactivate_room"):
			previous_room.call("deactivate_room")
	if previous_root != null and is_instance_valid(previous_root):
		if previous_root.get_parent() == self:
			remove_child(previous_root)
		previous_root.process_mode = Node.PROCESS_MODE_DISABLED
	var receipt := {
		"prior_content_id": previous_content_id,
		"target_content_id": _active_content_id,
		"prior_instance_generation": previous_generation,
		"target_instance_generation": _active_generation,
		"target_node_id": str(node["id"]),
		"target_instance_id": staged_room.get_instance_id(),
	}
	_pending_transition["stage"] = "committed"
	_pending_transition["receipt"] = receipt.duplicate(true)
	return {"ok": true, "code": &"OK", "receipt": receipt, "context": {}}


func confirm_transition(ticket: Dictionary) -> Dictionary:
	if not _ticket_matches_pending(ticket):
		return _failure(&"ROOM_SCENE_TICKET_INVALID", "ticket", "mismatch")
	if str(_pending_transition.get("stage", "")) != "committed":
		return _failure(&"ROOM_SCENE_TICKET_INVALID", "ticket", "not_committed")
	var prior_root_value: Variant = _pending_transition.get("prior_root")
	if prior_root_value is Node and is_instance_valid(prior_root_value):
		_dispose_detached(prior_root_value as Node)
	var receipt: Dictionary = (_pending_transition.get("receipt", {}) as Dictionary).duplicate(true)
	_pending_transition.clear()
	room_transitioned.emit(receipt.duplicate(true))
	return {"ok": true, "code": &"OK", "receipt": receipt, "context": {}}


func rollback_transition(ticket: Dictionary) -> Dictionary:
	if not _ticket_matches_pending(ticket):
		return _failure(&"ROOM_SCENE_TICKET_INVALID", "ticket", "mismatch")
	if str(_pending_transition.get("stage", "prepared")) == "committed":
		return _rollback_committed_transition(ticket)
	var staged_root_value: Variant = _pending_transition.get("root")
	if staged_root_value is Node and is_instance_valid(staged_root_value):
		_dispose_detached(staged_root_value as Node)
	_pending_transition.clear()
	return {
		"ok": true,
		"code": &"OK",
		"context": {
			"rolled_back_ticket_id": int(ticket["ticket_id"]),
			"active_instance_generation": _active_generation,
		},
	}


func _rollback_committed_transition(ticket: Dictionary) -> Dictionary:
	var prior_root_value: Variant = _pending_transition.get("prior_root")
	var prior_room_value: Variant = _pending_transition.get("prior_room")
	var prior_generation := int(_pending_transition.get("prior_generation", 0))
	if prior_generation > 0 and (
		not prior_root_value is Node or not is_instance_valid(prior_root_value)
	):
		return _failure(&"ROOM_SCENE_COMPENSATION_FAILED", "prior_root", "missing")
	if _active_room != null and is_instance_valid(_active_room) and _active_room.has_method("deactivate_room"):
		_active_room.call("deactivate_room")
	if _active_root != null and is_instance_valid(_active_root):
		_dispose_detached(_active_root)
	var prior_root: Node = prior_root_value as Node if prior_root_value is Node else null
	var prior_room: Node2D = prior_room_value as Node2D if prior_room_value is Node2D else null
	if prior_root != null:
		add_child(prior_root)
		prior_root.process_mode = Node.PROCESS_MODE_INHERIT
	if prior_room != null and is_instance_valid(prior_room):
		var activation_value: Variant = (
			_activation_adapter.call(prior_room, false)
			if _activation_adapter.is_valid()
			else _activate_scene(prior_room)
		)
		var activation_result := _normalized_result(
			activation_value, &"ROOM_SCENE_COMPENSATION_FAILED"
		)
		if not bool(activation_result.get("ok", false)):
			return _failure(&"ROOM_SCENE_COMPENSATION_FAILED", "prior_room", "activation_rejected")
	_active_root = prior_root
	_active_room = prior_room
	_active_content_id = str(_pending_transition.get("prior_content_id", ""))
	_active_generation = prior_generation
	_pending_transition.clear()
	return {
		"ok": true,
		"code": &"OK",
		"context": {
			"rolled_back_ticket_id": int(ticket["ticket_id"]),
			"active_instance_generation": _active_generation,
		},
	}


func pending_transition_ticket() -> Dictionary:
	if _pending_transition.is_empty():
		return {}
	return (_pending_transition["ticket"] as Dictionary).duplicate(true)


func floor_rule_configuration(ticket: Dictionary) -> Dictionary:
	if not _ticket_matches_pending(ticket):
		return {}
	var room_value: Variant = _pending_transition.get("room")
	if (
		not room_value is Node2D
		or not is_instance_valid(room_value)
		or not (room_value as Node2D).has_method("floor_rule_configuration")
	):
		return {}
	var value: Variant = (room_value as Node2D).call("floor_rule_configuration")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func active_room() -> Node2D:
	return _active_room if _active_room != null and is_instance_valid(_active_room) else null


func active_snapshot() -> Dictionary:
	return {
		"content_id": _active_content_id,
		"instance_generation": _active_generation,
		"instance_id": (
			_active_room.get_instance_id()
			if _active_room != null and is_instance_valid(_active_room)
			else 0
		),
	}


func reset() -> void:
	if not _pending_transition.is_empty():
		var disposed_ids: Dictionary = {}
		for key: String in ["root", "prior_root"]:
			var root_value: Variant = _pending_transition.get(key)
			if root_value is Node and is_instance_valid(root_value):
				var instance_id := (root_value as Node).get_instance_id()
				if not disposed_ids.has(instance_id):
					disposed_ids[instance_id] = true
					_dispose_detached(root_value as Node)
		_pending_transition.clear()
		_active_root = null
		_active_room = null
	if _active_room != null and is_instance_valid(_active_room):
		if _active_room.has_method("deactivate_room"):
			_active_room.call("deactivate_room")
	if _active_root != null and is_instance_valid(_active_root):
		if _active_root.get_parent() == self:
			remove_child(_active_root)
		_dispose_detached(_active_root)
	_active_root = null
	_active_room = null
	_active_content_id = ""
	_active_generation = 0
	_next_ticket_id = 1


func _ticket_matches_pending(ticket: Dictionary) -> bool:
	if _pending_transition.is_empty() or not _has_exact_fields(ticket, TRANSITION_TICKET_FIELDS):
		return false
	if (
		typeof(ticket["schema_version"]) != TYPE_INT
		or int(ticket["schema_version"]) != TRANSITION_TICKET_SCHEMA_VERSION
		or typeof(ticket["host_instance_id"]) != TYPE_INT
		or int(ticket["host_instance_id"]) != get_instance_id()
		or typeof(ticket["ticket_id"]) != TYPE_INT
		or int(ticket["ticket_id"]) <= 0
		or typeof(ticket["prior_instance_generation"]) != TYPE_INT
		or typeof(ticket["target_content_id"]) != TYPE_STRING
		or typeof(ticket["target_node_id"]) != TYPE_STRING
	):
		return false
	return ticket == (_pending_transition["ticket"] as Dictionary)


func _validate_authority(
	node: Dictionary,
	template: Dictionary,
	context: Dictionary
) -> Dictionary:
	for field: String in ["id", "template_id", "room_type"]:
		if typeof(node.get(field)) != TYPE_STRING or str(node[field]).is_empty():
			return _failure(&"ROOM_SCENE_AUTHORITY_REJECTED", "node.%s" % field, "invalid")
	var template_result: Dictionary = RoomTemplateDefinitionScript.new().configure(template)
	if not bool(template_result.get("ok", false)):
		return {
			"ok": false,
			"code": &"ROOM_SCENE_AUTHORITY_REJECTED",
			"context": (template_result.get("context", {}) as Dictionary).duplicate(true),
		}
	var normalized: Dictionary = template_result["definition"]
	if (
		str(node["template_id"]) != str(normalized["id"])
		or str(node["room_type"]) != str(normalized["room_type"])
	):
		return _failure(&"ROOM_SCENE_AUTHORITY_REJECTED", "node", "template_mismatch")
	for field: String in ["floor_id", "palette_id", "environment_rule_id"]:
		if typeof(context.get(field)) != TYPE_STRING or str(context[field]).is_empty():
			return _failure(&"ROOM_SCENE_AUTHORITY_REJECTED", "context.%s" % field, "invalid")
	if typeof(context.get("room_seed")) != TYPE_INT:
		return _failure(&"ROOM_SCENE_AUTHORITY_REJECTED", "context.room_seed", "invalid")
	if not (normalized["floor_ids"] as Array).has(str(context["floor_id"])):
		return _failure(&"ROOM_SCENE_AUTHORITY_REJECTED", "context.floor_id", "template_mismatch")
	if not (normalized["supported_environment_rule_ids"] as Array).has(
		str(context["environment_rule_id"])
	):
		return _failure(
			&"ROOM_SCENE_AUTHORITY_REJECTED",
			"context.environment_rule_id",
			"template_mismatch"
		)
	return {"ok": true, "code": &"OK", "template": normalized, "context": {}}


func _instantiate_resource(resource_value: Variant) -> Variant:
	if resource_value is PackedScene:
		return (resource_value as PackedScene).instantiate()
	return null


func _bind_scene(
	room: Node2D,
	node: Dictionary,
	template: Dictionary,
	context: Dictionary
) -> Variant:
	if not room.has_method("bind_room"):
		return _failure(&"ROOM_SCENE_BIND_FAILED", "script", "bind_room_missing")
	return room.call(
		"bind_room",
		node.duplicate(true),
		template.duplicate(true),
		context.duplicate(true)
	)


func _prepare_scene_activation(room: Node2D) -> Variant:
	if not room.has_method("prepare_activation"):
		return _failure(
			&"ROOM_SCENE_ACTIVATION_FAILED",
			"script",
			"prepare_activation_missing"
		)
	return room.call("prepare_activation")


func _activate_scene(room: Node2D) -> Variant:
	if not room.has_method("activate_room"):
		return _failure(&"ROOM_SCENE_ACTIVATION_FAILED", "script", "activate_room_missing")
	return room.call("activate_room")


func _normalized_result(value: Variant, fallback_code: StringName) -> Dictionary:
	if value is bool:
		return (
			{"ok": true, "code": &"OK", "context": {}}
			if bool(value)
			else _failure(fallback_code, "adapter", "rejected")
		)
	if not value is Dictionary:
		return _failure(fallback_code, "adapter", "invalid_result")
	var result := (value as Dictionary).duplicate(true)
	if not result.has("ok") or typeof(result["ok"]) != TYPE_BOOL:
		return _failure(fallback_code, "adapter", "invalid_result")
	if not bool(result["ok"]):
		result["code"] = fallback_code
		if not result.get("context") is Dictionary:
			result["context"] = {}
		return result
	result["code"] = &"OK"
	if not result.get("context") is Dictionary:
		result["context"] = {}
	return result


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _reject(failure: Dictionary) -> Dictionary:
	var result := failure.duplicate(true)
	if not result.has("ok"):
		result["ok"] = false
	if not result.get("context") is Dictionary:
		result["context"] = {}
	room_transition_failed.emit((result["context"] as Dictionary).duplicate(true))
	return result


func _dispose_if_node(value: Variant) -> void:
	if value is Node and is_instance_valid(value):
		var node := value as Node
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


func _dispose_detached(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


func _failure(code: StringName, field: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "context": {"field": field, "reason": reason}}
