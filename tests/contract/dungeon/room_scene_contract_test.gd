extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RoomSceneContractScript := preload("res://scripts/dungeon/room_scene_contract.gd")

const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"
const FLOOR_PRESENTATION := {
	"floor_ruins_of_remnant": ["palette_ruins_of_remnant", "rule_crumbling_ground"],
	"floor_void_forest": ["palette_void_forest", "rule_void_spores"],
	"floor_time_rift": ["palette_time_rift", "rule_temporal_distortion"],
	"floor_plane_forge": ["palette_plane_forge", "rule_forge_vents"],
	"floor_throne_of_void": ["palette_throne_of_void", "rule_collapsing_plane"],
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var templates := _load_templates()
	suite.assert_equal(templates.size(), 30, "P14D exposes exactly thirty room templates")
	for index: int in range(templates.size()):
		var template := templates[index] as Dictionary
		var packed_value: Variant = load(str(template["scene_path"]))
		suite.assert_true(packed_value is PackedScene, "%s loads as PackedScene" % template["id"])
		if not packed_value is PackedScene:
			continue
		var room := (packed_value as PackedScene).instantiate()
		var result: Dictionary = RoomSceneContractScript.validate(room, template)
		suite.assert_true(bool(result.get("ok", false)), "%s satisfies RoomSceneContract" % template["id"])
		if room.has_method("bind_room"):
			var floor_id := str((template["floor_ids"] as Array)[0])
			var presentation: Array = FLOOR_PRESENTATION[floor_id]
			var bound: Dictionary = room.call("bind_room", {
				"id": "node-%02d" % index,
				"template_id": str(template["id"]),
				"room_type": str(template["room_type"]),
			}, template, {
				"floor_id": floor_id,
				"palette_id": str(presentation[0]),
				"environment_rule_id": str(presentation[1]),
				"room_seed": 20261002 + index,
				"reduced_motion": true,
				"hit_flash_enabled": true,
			})
			suite.assert_true(bool(bound.get("ok", false)), "%s binds the closed floor palette" % template["id"])
			var snapshot: Dictionary = room.call("presentation_snapshot")
			suite.assert_equal(snapshot.get("palette_id"), str(presentation[0]), "%s exposes its palette" % template["id"])
			suite.assert_equal(snapshot.get("hazard_cue", {}).get("visual_mode"), "static_outline", "%s uses a static reduced-motion hazard cue" % template["id"])
			suite.assert_true(not bool(snapshot.get("hazard_cue", {}).get("flash_enabled", true)), "%s suppresses flashes in reduced-motion mode" % template["id"])
		room.free()

	if not templates.is_empty():
		_test_rejections(suite, templates[0] as Dictionary)
	suite.finish(get_tree())


func _test_rejections(suite, template: Dictionary) -> void:
	var packed := load(str(template["scene_path"])) as PackedScene
	var missing_exit := packed.instantiate()
	var exit_anchor := missing_exit.get_node("PlayerExit")
	missing_exit.remove_child(exit_anchor)
	exit_anchor.free()
	var missing_result: Dictionary = RoomSceneContractScript.validate(missing_exit, template)
	suite.assert_true(not bool(missing_result.get("ok", true)), "contract rejects a missing required anchor")
	missing_exit.free()

	var narrow_door := packed.instantiate()
	var door := narrow_door.get_node("DoorAnchors").get_child(0) as Marker2D
	door.set_meta("clear_width", 16)
	var narrow_result: Dictionary = RoomSceneContractScript.validate(narrow_door, template)
	suite.assert_true(not bool(narrow_result.get("ok", true)), "contract rejects inaccessible door clearance")
	narrow_door.free()

	var wrong_identity := packed.instantiate()
	wrong_identity.set("content_id", &"room_combat_open_field")
	var identity_result: Dictionary = RoomSceneContractScript.validate(wrong_identity, template)
	suite.assert_true(not bool(identity_result.get("ok", true)), "contract rejects content identity drift")
	wrong_identity.free()

	var hazard_overlap := packed.instantiate()
	var hazard := hazard_overlap.get_node("FloorRuleAnchors/HazardZone1") as Area2D
	hazard.position = Vector2(320, 180)
	var hazard_result: Dictionary = RoomSceneContractScript.validate(hazard_overlap, template)
	suite.assert_true(not bool(hazard_result.get("ok", true)), "contract rejects hazard collision over a declared safe zone")
	hazard_overlap.free()


func _load_templates() -> Array:
	var file := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if file == null:
		return []
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value as Array if value is Array else []
