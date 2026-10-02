class_name RoomSceneContract
extends RefCounted

const LaunchRoomSceneScript := preload("res://scripts/dungeon/launch_room_scene.gd")
const RoomTemplateDefinitionScript := preload("res://scripts/dungeon/room_template_definition.gd")

const DESIGN_CANVAS := Rect2(0.0, 0.0, 640.0, 360.0)
const MIN_DOOR_CLEAR_WIDTH := 32.0
const REQUIRED_ANCHORS: Array[String] = [
	"PlayerEntry",
	"PlayerExit",
	"CameraBounds",
	"DoorAnchors",
	"EncounterAnchors",
	"InteractionAnchors",
	"FloorRuleAnchors",
	"PixelProxyLayer",
]
const ENCOUNTER_ROOM_TYPES: Array[String] = ["combat", "elite", "boss"]
const INTERACTION_KIND_BY_ROOM_TYPE := {
	"treasure": "treasure",
	"shop": "shop",
	"event": "event",
	"rest": "rest",
}


static func validate(scene: Variant, template: Dictionary) -> Dictionary:
	if not scene is Node2D or not is_instance_valid(scene):
		return _failure(&"ROOM_SCENE_INVALID", "scene", "expected_node2d")
	var template_result: Dictionary = RoomTemplateDefinitionScript.new().configure(template)
	if not bool(template_result.get("ok", false)):
		return {
			"ok": false,
			"code": &"ROOM_TEMPLATE_INVALID",
			"context": (template_result.get("context", {}) as Dictionary).duplicate(true),
		}
	var normalized: Dictionary = template_result["definition"]
	var room := scene as Node2D
	if room.get_script() != LaunchRoomSceneScript:
		return _failure(&"ROOM_SCENE_INVALID", "script", "launch_room_scene_required")
	var scripted_nodes := _scripted_nodes(room)
	if scripted_nodes.size() != 1 or scripted_nodes[0] != room:
		return _failure(&"ROOM_SCENE_INVALID", "script", "exactly_one_room_script_required")
	if not room.has_method("room_contract_snapshot"):
		return _failure(&"ROOM_SCENE_INVALID", "script", "contract_snapshot_missing")
	var identity_value: Variant = room.call("room_contract_snapshot")
	if not identity_value is Dictionary:
		return _failure(&"ROOM_SCENE_INVALID", "identity", "expected_dictionary")
	var identity := identity_value as Dictionary
	if str(identity.get("content_id", "")) != str(normalized["id"]):
		return _failure(&"ROOM_SCENE_INVALID", "content_id", "template_mismatch")
	if str(identity.get("room_type", "")) != str(normalized["room_type"]):
		return _failure(&"ROOM_SCENE_INVALID", "room_type", "template_mismatch")
	if identity.get("design_size") != Vector2i(640, 360):
		return _failure(&"ROOM_SCENE_INVALID", "design_size", "expected_640x360")

	var anchors: Dictionary = {}
	for anchor_name: String in REQUIRED_ANCHORS:
		var matches := room.find_children(anchor_name, "", true, false)
		if matches.size() != 1:
			return _failure(
				&"ROOM_SCENE_INVALID",
				anchor_name,
				"missing" if matches.is_empty() else "duplicate"
			)
		anchors[anchor_name] = matches[0]
	if not anchors["PlayerEntry"] is Marker2D or not anchors["PlayerExit"] is Marker2D:
		return _failure(&"ROOM_SCENE_INVALID", "player_anchors", "marker2d_required")
	for container_name: String in [
		"DoorAnchors", "EncounterAnchors", "InteractionAnchors", "FloorRuleAnchors",
	]:
		if not anchors[container_name] is Node2D:
			return _failure(&"ROOM_SCENE_INVALID", container_name, "node2d_required")
	if not anchors["PixelProxyLayer"] is Node2D:
		return _failure(&"ROOM_SCENE_INVALID", "PixelProxyLayer", "node2d_required")

	var camera_bounds := _camera_bounds(anchors["CameraBounds"] as Node)
	if camera_bounds.size.x <= 0.0 or camera_bounds.size.y <= 0.0:
		return _failure(&"ROOM_SCENE_INVALID", "CameraBounds", "rectangle_required")
	if not _rect_is_inside(camera_bounds, DESIGN_CANVAS):
		return _failure(&"ROOM_SCENE_INVALID", "CameraBounds", "outside_design_canvas")
	var expected_camera := _rect_from_dictionary(normalized["camera_bounds"] as Dictionary)
	if not _rect_is_equal(camera_bounds, expected_camera):
		return _failure(&"ROOM_SCENE_INVALID", "CameraBounds", "template_mismatch")

	var player_spawn := _first_anchor_of_kind(normalized["spawn_anchors"] as Array, "player")
	if player_spawn.is_empty():
		return _failure(&"ROOM_SCENE_INVALID", "PlayerEntry", "template_anchor_missing")
	if not _position_matches(anchors["PlayerEntry"] as Marker2D, player_spawn["position"]):
		return _failure(&"ROOM_SCENE_INVALID", "PlayerEntry", "template_mismatch")
	var exit_anchor := _first_anchor_of_kind(normalized["interaction_anchors"] as Array, "exit")
	if exit_anchor.is_empty():
		return _failure(&"ROOM_SCENE_INVALID", "PlayerExit", "template_anchor_missing")
	if not _position_matches(anchors["PlayerExit"] as Marker2D, exit_anchor["position"]):
		return _failure(&"ROOM_SCENE_INVALID", "PlayerExit", "template_mismatch")

	var doors_result := _validate_anchor_container(
		anchors["DoorAnchors"] as Node2D,
		normalized["door_anchors"] as Array,
		true
	)
	if not bool(doors_result.get("ok", false)):
		return doors_result
	var expected_encounters: Array = []
	for spawn_value: Variant in normalized["spawn_anchors"] as Array:
		var spawn := spawn_value as Dictionary
		if str(spawn.get("kind", "")) != "player":
			expected_encounters.append(spawn)
	var encounters_result := _validate_anchor_container(
		anchors["EncounterAnchors"] as Node2D,
		expected_encounters,
		false
	)
	if not bool(encounters_result.get("ok", false)):
		return encounters_result
	if ENCOUNTER_ROOM_TYPES.has(str(normalized["room_type"])) and expected_encounters.is_empty():
		return _failure(&"ROOM_SCENE_INVALID", "EncounterAnchors", "room_type_anchor_required")
	var interactions_result := _validate_anchor_container(
		anchors["InteractionAnchors"] as Node2D,
		normalized["interaction_anchors"] as Array,
		false
	)
	if not bool(interactions_result.get("ok", false)):
		return interactions_result
	var required_interaction_kind := str(INTERACTION_KIND_BY_ROOM_TYPE.get(
		str(normalized["room_type"]), ""
	))
	if (
		not required_interaction_kind.is_empty()
		and _first_anchor_of_kind(
			normalized["interaction_anchors"] as Array,
			required_interaction_kind
		).is_empty()
	):
		return _failure(&"ROOM_SCENE_INVALID", "InteractionAnchors", "room_type_anchor_required")
	var floor_rule_children := _marker_children(anchors["FloorRuleAnchors"] as Node2D)
	if floor_rule_children.is_empty():
		return _failure(&"ROOM_SCENE_INVALID", "FloorRuleAnchors", "safe_zone_anchor_required")
	var safe_zone_ids: Dictionary = {}
	var safe_zone_rects: Array[Rect2] = []
	for zone_value: Variant in normalized["accessibility_safe_hazard_zones"] as Array:
		var zone := zone_value as Dictionary
		safe_zone_ids[str(zone["id"])] = true
		safe_zone_rects.append(_rect_from_dictionary(zone["bounds"] as Dictionary))
	for marker: Marker2D in floor_rule_children:
		var marker_id := _anchor_id(marker)
		if marker_id.is_empty() or not safe_zone_ids.has(marker_id):
			return _failure(&"ROOM_SCENE_INVALID", "FloorRuleAnchors", "unknown_safe_zone")
	var hazard_result := _validate_hazard_zones(
		anchors["FloorRuleAnchors"] as Node2D,
		safe_zone_rects
	)
	if not bool(hazard_result.get("ok", false)):
		return hazard_result

	return {
		"ok": true,
		"code": &"OK",
		"context": {
			"content_id": str(normalized["id"]),
			"room_type": str(normalized["room_type"]),
			"camera_bounds": camera_bounds,
			"anchor_names": REQUIRED_ANCHORS.duplicate(),
		},
	}


static func _scripted_nodes(root: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.get_script() != null:
			nodes.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	return nodes


static func _camera_bounds(anchor: Node) -> Rect2:
	if anchor.has_method("contract_bounds"):
		var method_value: Variant = anchor.call("contract_bounds")
		if method_value is Rect2:
			return method_value as Rect2
	if anchor.has_meta("bounds"):
		var meta_value: Variant = anchor.get_meta("bounds")
		if meta_value is Rect2:
			return meta_value as Rect2
		if meta_value is Dictionary:
			return _rect_from_dictionary(meta_value as Dictionary)
	if anchor is Area2D:
		var collisions := anchor.find_children("*", "CollisionShape2D", true, false)
		var collision: Node = collisions[0] if not collisions.is_empty() else null
		if collision is CollisionShape2D:
			var shape := (collision as CollisionShape2D).shape
			if shape is RectangleShape2D:
				var size := (shape as RectangleShape2D).size
				var center := (anchor as Area2D).position + (collision as CollisionShape2D).position
				return Rect2(center - size * 0.5, size)
	return Rect2()


static func _validate_anchor_container(
	container: Node2D,
	expected_values: Array,
	require_door_clearance: bool
) -> Dictionary:
	var markers := _marker_children(container)
	if markers.size() != expected_values.size():
		return _failure(&"ROOM_SCENE_INVALID", container.name, "anchor_count_mismatch")
	var markers_by_id: Dictionary = {}
	for marker: Marker2D in markers:
		var marker_id := _anchor_id(marker)
		if marker_id.is_empty() or markers_by_id.has(marker_id):
			return _failure(&"ROOM_SCENE_INVALID", container.name, "invalid_or_duplicate_anchor_id")
		if require_door_clearance:
			var clear_width_value: Variant = marker.get_meta("clear_width", 0.0)
			if (
				typeof(clear_width_value) not in [TYPE_INT, TYPE_FLOAT]
				or float(clear_width_value) < MIN_DOOR_CLEAR_WIDTH
			):
				return _failure(&"ROOM_SCENE_INVALID", container.name, "door_clearance_too_narrow")
		markers_by_id[marker_id] = marker
	for expected_value: Variant in expected_values:
		if not expected_value is Dictionary:
			return _failure(&"ROOM_SCENE_INVALID", container.name, "template_anchor_invalid")
		var expected := expected_value as Dictionary
		var expected_id := str(expected.get("id", ""))
		if not markers_by_id.has(expected_id):
			return _failure(&"ROOM_SCENE_INVALID", container.name, "template_anchor_missing")
		var marker := markers_by_id[expected_id] as Marker2D
		if not _position_matches(marker, expected.get("position", {})):
			return _failure(&"ROOM_SCENE_INVALID", container.name, "template_position_mismatch")
		var expected_kind := str(expected.get("kind", ""))
		if not expected_kind.is_empty() and str(marker.get_meta("kind", "")) != expected_kind:
			return _failure(&"ROOM_SCENE_INVALID", container.name, "template_kind_mismatch")
	return {"ok": true, "code": &"OK", "context": {}}


static func _marker_children(container: Node2D) -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	for child: Node in container.get_children():
		if child is Marker2D:
			markers.append(child as Marker2D)
	return markers


static func _validate_hazard_zones(container: Node2D, safe_zone_rects: Array[Rect2]) -> Dictionary:
	var hazard_nodes := container.find_children("HazardZone*", "Area2D", false, false)
	if hazard_nodes.size() < 3:
		return _failure(&"ROOM_SCENE_INVALID", container.name, "hazard_zone_count_too_low")
	var seen_ids: Dictionary = {}
	for hazard_value: Variant in hazard_nodes:
		var hazard := hazard_value as Area2D
		var zone_id := str(hazard.get_meta("zone_id", "")).strip_edges()
		if zone_id.is_empty() or seen_ids.has(zone_id):
			return _failure(&"ROOM_SCENE_INVALID", container.name, "invalid_or_duplicate_hazard_id")
		seen_ids[zone_id] = true
		var collisions := hazard.find_children("*", "CollisionShape2D", true, false)
		if collisions.size() != 1:
			return _failure(&"ROOM_SCENE_INVALID", zone_id, "one_collision_shape_required")
		var collision := collisions[0] as CollisionShape2D
		if collision.shape is not RectangleShape2D:
			return _failure(&"ROOM_SCENE_INVALID", zone_id, "rectangle_collision_required")
		var rectangle := collision.shape as RectangleShape2D
		var bounds := Rect2(
			hazard.position + collision.position - rectangle.size * 0.5,
			rectangle.size
		)
		if not _rect_is_inside(bounds, DESIGN_CANVAS):
			return _failure(&"ROOM_SCENE_INVALID", zone_id, "hazard_outside_design_canvas")
		for safe_zone: Rect2 in safe_zone_rects:
			if bounds.intersects(safe_zone):
				return _failure(&"ROOM_SCENE_INVALID", zone_id, "hazard_overlaps_safe_zone")
	return {"ok": true, "code": &"OK", "context": {}}


static func _anchor_id(marker: Marker2D) -> String:
	return str(marker.get_meta("anchor_id", str(marker.name))).strip_edges()


static func _position_matches(marker: Marker2D, position_value: Variant) -> bool:
	if not position_value is Dictionary:
		return false
	var expected := position_value as Dictionary
	if not expected.has("x") or not expected.has("y"):
		return false
	return marker.position.is_equal_approx(Vector2(float(expected["x"]), float(expected["y"])))


static func _first_anchor_of_kind(values: Array, kind: String) -> Dictionary:
	for value: Variant in values:
		if value is Dictionary and str((value as Dictionary).get("kind", "")) == kind:
			return (value as Dictionary).duplicate(true)
	return {}


static func _rect_from_dictionary(value: Dictionary) -> Rect2:
	for field: String in ["x", "y", "width", "height"]:
		if not value.has(field) or typeof(value[field]) not in [TYPE_INT, TYPE_FLOAT]:
			return Rect2()
	return Rect2(
		float(value["x"]),
		float(value["y"]),
		float(value["width"]),
		float(value["height"])
	)


static func _rect_is_inside(inner: Rect2, outer: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x
		and inner.position.y >= outer.position.y
		and inner.end.x <= outer.end.x
		and inner.end.y <= outer.end.y
	)


static func _rect_is_equal(left: Rect2, right: Rect2) -> bool:
	return left.position.is_equal_approx(right.position) and left.size.is_equal_approx(right.size)


static func _failure(code: StringName, field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"context": {"field": field, "reason": reason},
	}
