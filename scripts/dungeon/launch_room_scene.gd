class_name LaunchRoomScene
extends Node2D

const DESIGN_SIZE := Vector2i(640, 360)
const ROOM_TYPES: Array[String] = ["combat", "elite", "treasure", "shop", "event", "boss", "rest"]
const FLOOR_PRESENTATION := {
	"floor_ruins_of_remnant": {
		"palette_id": "palette_ruins_of_remnant",
		"environment_rule_id": "rule_crumbling_ground",
		"base_color": Color("28313b"),
		"accent_color": Color("c7a86b"),
	},
	"floor_void_forest": {
		"palette_id": "palette_void_forest",
		"environment_rule_id": "rule_void_spores",
		"base_color": Color("182d2a"),
		"accent_color": Color("9a65d8"),
	},
	"floor_time_rift": {
		"palette_id": "palette_time_rift",
		"environment_rule_id": "rule_temporal_distortion",
		"base_color": Color("162840"),
		"accent_color": Color("b8efff"),
	},
	"floor_plane_forge": {
		"palette_id": "palette_plane_forge",
		"environment_rule_id": "rule_forge_vents",
		"base_color": Color("3a201b"),
		"accent_color": Color("ff8d43"),
	},
	"floor_throne_of_void": {
		"palette_id": "palette_throne_of_void",
		"environment_rule_id": "rule_collapsing_plane",
		"base_color": Color("17131f"),
		"accent_color": Color("f4f0ff"),
	},
}

@export var content_id: StringName = &""
@export_enum("combat", "elite", "treasure", "shop", "event", "boss", "rest") var room_type: String = "combat"

var _bound: bool = false
var _active: bool = false
var _binding_generation: int = 0
var _binding: Dictionary = {}


func room_contract_snapshot() -> Dictionary:
	return {
		"content_id": str(content_id),
		"room_type": room_type,
		"design_size": DESIGN_SIZE,
	}


func bind_room(node: Dictionary, template: Dictionary, context: Dictionary) -> Dictionary:
	if _active:
		return _failure(&"ROOM_BIND_REJECTED", "phase", "active")
	if not _binding_is_valid(node, template, context):
		return _failure(&"ROOM_BIND_REJECTED", "binding", "invalid")
	_binding_generation += 1
	_binding = {
		"node_id": str(node["id"]),
		"content_id": str(template["id"]),
		"room_type": str(template["room_type"]),
		"floor_id": str(context["floor_id"]),
		"palette_id": str(context["palette_id"]),
		"environment_rule_id": str(context["environment_rule_id"]),
		"room_seed": int(context["room_seed"]),
		"binding_generation": _binding_generation,
		"reduced_motion": bool(context.get("reduced_motion", false)),
		"hit_flash_enabled": bool(context.get("hit_flash_enabled", true)),
	}
	_apply_floor_palette()
	_bound = true
	return {"ok": true, "code": &"OK", "context": binding_snapshot()}


func prepare_activation() -> Dictionary:
	if not _bound or _active:
		return _failure(&"ROOM_ACTIVATION_REJECTED", "phase", "not_bound_or_active")
	return {"ok": true, "code": &"OK", "context": binding_snapshot()}


func activate_room() -> Dictionary:
	var prepared := prepare_activation()
	if not bool(prepared.get("ok", false)):
		return prepared
	_active = true
	process_mode = Node.PROCESS_MODE_INHERIT
	return {"ok": true, "code": &"OK", "context": binding_snapshot()}


func deactivate_room() -> void:
	_active = false
	process_mode = Node.PROCESS_MODE_DISABLED


func binding_snapshot() -> Dictionary:
	return {
		"bound": _bound,
		"active": _active,
		"binding": _binding.duplicate(true),
	}


func presentation_snapshot() -> Dictionary:
	if not _bound:
		return {
			"bound": false,
			"palette_id": "",
			"environment_rule_id": "",
			"base_color": Color.TRANSPARENT,
			"accent_color": Color.TRANSPARENT,
			"hazard_cue": {},
		}
	var floor_presentation := FLOOR_PRESENTATION[_binding["floor_id"]] as Dictionary
	var reduced_motion := bool(_binding["reduced_motion"])
	return {
		"bound": true,
		"palette_id": str(_binding["palette_id"]),
		"environment_rule_id": str(_binding["environment_rule_id"]),
		"base_color": floor_presentation["base_color"],
		"accent_color": floor_presentation["accent_color"],
		"hazard_cue": {
			"visual_mode": "static_outline" if reduced_motion else "animated",
			"motion_enabled": not reduced_motion,
			"flash_enabled": bool(_binding["hit_flash_enabled"]) and not reduced_motion,
			"high_contrast_outline": true,
			"subtitle_required": true,
		},
	}


func floor_rule_configuration() -> Dictionary:
	if not _bound:
		return {}
	var anchors := get_node_or_null("FloorRuleAnchors")
	if not anchors is Node2D:
		return {}
	var zones: Array[Dictionary] = []
	var safe_zone_ids: Array[String] = []
	for child: Node in anchors.get_children():
		if child is Marker2D and child.has_meta("bounds"):
			var safe_id := str(child.get_meta("anchor_id", ""))
			var bounds_value: Variant = child.get_meta("bounds")
			if safe_id.is_empty() or not bounds_value is Rect2:
				return {}
			zones.append(_floor_rule_zone(safe_id, bounds_value as Rect2))
			safe_zone_ids.append(safe_id)
		elif child is Area2D:
			var zone_id := str(child.get_meta("zone_id", ""))
			var collision := child.get_node_or_null("CollisionShape2D")
			if (
				zone_id.is_empty()
				or not collision is CollisionShape2D
				or not (collision as CollisionShape2D).shape is RectangleShape2D
			):
				return {}
			var size := ((collision as CollisionShape2D).shape as RectangleShape2D).size
			var center := (child as Area2D).position + (collision as CollisionShape2D).position
			zones.append(_floor_rule_zone(zone_id, Rect2(center - size * 0.5, size)))
	if zones.is_empty() or safe_zone_ids.is_empty() or zones.size() <= safe_zone_ids.size():
		return {}
	return {
		"room_id": str(_binding["node_id"]),
		"room_seed": int(_binding["room_seed"]),
		"zones": zones,
		"safe_zone_ids": safe_zone_ids,
		"reduced_motion": bool(_binding["reduced_motion"]),
		"hit_flash_enabled": bool(_binding["hit_flash_enabled"]),
	}


func category_handler() -> Node:
	if room_type in ["combat", "elite", "boss"]:
		return get_node_or_null("EncounterAnchors")
	return get_node_or_null("InteractionAnchors")


func reset_room_binding() -> void:
	deactivate_room()
	_bound = false
	_binding.clear()


func _binding_is_valid(node: Dictionary, template: Dictionary, context: Dictionary) -> bool:
	if str(content_id).is_empty() or not ROOM_TYPES.has(room_type):
		return false
	for field: String in ["id", "template_id", "room_type"]:
		if typeof(node.get(field)) != TYPE_STRING or str(node[field]).is_empty():
			return false
	for field: String in ["id", "room_type"]:
		if typeof(template.get(field)) != TYPE_STRING or str(template[field]).is_empty():
			return false
	if (
		str(node["template_id"]) != str(template["id"])
		or str(node["room_type"]) != str(template["room_type"])
		or str(template["id"]) != str(content_id)
		or str(template["room_type"]) != room_type
	):
		return false
	for field: String in ["floor_id", "palette_id", "environment_rule_id"]:
		if typeof(context.get(field)) != TYPE_STRING or str(context[field]).is_empty():
			return false
	if typeof(context.get("room_seed")) != TYPE_INT:
		return false
	var floor_id := str(context["floor_id"])
	if not FLOOR_PRESENTATION.has(floor_id):
		return false
	var presentation := FLOOR_PRESENTATION[floor_id] as Dictionary
	if (
		str(context["palette_id"]) != str(presentation["palette_id"])
		or str(context["environment_rule_id"]) != str(presentation["environment_rule_id"])
	):
		return false
	if context.has("reduced_motion") and typeof(context["reduced_motion"]) != TYPE_BOOL:
		return false
	if context.has("hit_flash_enabled") and typeof(context["hit_flash_enabled"]) != TYPE_BOOL:
		return false
	return true


func _apply_floor_palette() -> void:
	var presentation := FLOOR_PRESENTATION[_binding["floor_id"]] as Dictionary
	var pixel_layer := get_node_or_null("PixelProxyLayer")
	if pixel_layer is CanvasItem:
		(pixel_layer as CanvasItem).modulate = Color.WHITE
	var background := get_node_or_null("PixelProxyLayer/Background")
	if background is Polygon2D:
		(background as Polygon2D).color = presentation["base_color"] as Color
	for accent_path: String in [
		"PixelProxyLayer/LandmarkPrimary",
		"PixelProxyLayer/DoorVisualWest",
		"PixelProxyLayer/DoorVisualEast",
	]:
		var accent_node := get_node_or_null(accent_path)
		if accent_node is Polygon2D:
			(accent_node as Polygon2D).color = presentation["accent_color"] as Color


func _floor_rule_zone(zone_id: String, bounds: Rect2) -> Dictionary:
	return {
		"id": zone_id,
		"bounds": {
			"x": bounds.position.x,
			"y": bounds.position.y,
			"width": bounds.size.x,
			"height": bounds.size.y,
		},
	}


func _failure(code: StringName, field: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "context": {"field": field, "reason": reason}}
