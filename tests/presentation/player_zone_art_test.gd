extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const StaffScene := preload("res://scenes/combat/staff_spell_zone.tscn")
const Gauntlets := preload("res://scripts/combat/gauntlets_zone_execution.gd")
const STAFF_IDS := ["ice_zone", "planar_collapse", "seeded_sequence", "steam_burst", "crystal_thunder", "reverse_steam", "thunder_flare", "thunder_crystal", "blazing_storm"]
const GAUNTLET_IDS := ["space_time_shatter", "primordial_collapse", "charged_heavy_shockwave", "rewind_counter_shockwave"]


func _ready() -> void:
	call_deferred("_run")


static func staff_execution(identity: String) -> Dictionary:
	var mode := identity if identity in ["ice_zone", "planar_collapse", "seeded_sequence"] else "combination"
	var parameters := {"radius_tiles": 1.0, "duration_frames": 120, "tick_interval_frames": 12, "damage_multiplier": 0.0}
	if identity == "planar_collapse":
		parameters.merge({"void_erosion_duration_frames": 120, "void_erosion_damage_multiplier": 0.0})
	elif identity == "seeded_sequence":
		parameters.merge({"count": 10, "elements": ["fire", "ice", "lightning"]})
	elif mode == "combination":
		var kind := "zone" if identity == "blazing_storm" else "chain_delayed_explosions" if identity == "thunder_flare" else "chain_delayed_crystals" if identity == "thunder_crystal" else "staged_zone_explosion" if identity == "reverse_steam" else "delayed_explosion" if identity == "crystal_thunder" else "explosion"
		parameters = {"combo_id": identity, "combo_kind": kind, "combo_parameters": {"radius_tiles": 1.0, "freeze_radius_tiles": 1.0, "explosion_radius_tiles": 1.5, "delay_frames": 12, "ice_surface_duration_frames": 108, "duration_frames": 120, "tick_interval_frames": 12, "origins": [Vector2(20, 30), Vector2(80, 90)]}}
	return {"action_token": 41, "generation": 7, "source_action_id": "zone_art", "descriptor_id": identity, "outcome_index": 0, "deterministic_seed": 20261006, "mode": mode, "parameters": parameters, "base_attack": 9.0}


static func gauntlets_execution(identity: String) -> Dictionary:
	return {"action_token": 42, "generation": 8, "source_action_id": "zone_art", "descriptor_id": identity, "outcome_index": 0, "deterministic_seed": 20261006, "mode": identity, "parameters": {"radius_tiles": 1.5, "duration_frames": 120, "tick_interval_frames": 12, "damage_multiplier": 0.0}, "base_attack": 6.0}


func _run() -> void:
	var suite := Suite.new()
	for identity: String in STAFF_IDS + GAUNTLET_IDS:
		var is_staff := identity in STAFF_IDS
		var zone: Node2D = StaffScene.instantiate() if is_staff else Gauntlets.new()
		zone.process_mode = Node.PROCESS_MODE_DISABLED
		var execution := staff_execution(identity) if is_staff else gauntlets_execution(identity)
		suite.assert_true(zone.configure_execution(execution), "actual native zone configures " + identity)
		add_child(zone)
		var before: Dictionary = zone.execution_snapshot()
		var visual := zone.get_node_or_null("ProductionZoneAtlas")
		suite.assert_true(visual != null, identity + " has production raster zone projection")
		if visual != null:
			visual.sync_from_owner()
			var sprite := visual.get_node_or_null("Primary") as Sprite2D
			suite.assert_true(sprite != null and sprite.visible and sprite.texture != null, identity + " shows a source atlas")
			if sprite != null and sprite.texture != null:
				suite.assert_equal(sprite.texture.resource_path, "res://assets/production/ui/player_zones/%s.png" % identity, "native zone selects exact mode/combination identity")
				suite.assert_equal(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "native zone has pixel edges")
				suite.assert_equal(sprite.frame, 0, "native zone pose follows execution clock")
				var radius := 64.0 if is_staff else 96.0
				suite.assert_equal(sprite.scale, Vector2.ONE * radius / 30.0, "native zone art uses actual authored radius")
				if identity in ["thunder_flare", "thunder_crystal"]:
					suite.assert_equal(visual.get_child_count(), 2, "chain zone shows every frozen origin")
					suite.assert_equal(sprite.global_position, Vector2(20, 30), "first chain origin is absolute native position")
					suite.assert_equal(visual.get_child(1).global_position, Vector2(80, 90), "second chain origin is absolute native position")
			visual.set_reduced_motion(true)
			visual.sync_from_owner()
			if sprite != null: suite.assert_equal(sprite.frame, 0, "reduced motion keeps stable zone pose")
			suite.assert_equal(zone.execution_snapshot(), before, "zone projection preserves full native execution snapshot")
			zone.advance_execution_for_test(1 if identity == "steam_burst" else 6)
			var advanced: Dictionary = zone.execution_snapshot()
			visual.set_reduced_motion(false)
			visual.sync_from_owner()
			if identity == "steam_burst":
				suite.assert_true(not visual.visible, "one-frame explosion retires with its actual native payload")
			elif sprite != null:
				suite.assert_equal(sprite.frame, 1, "zone pose uses accepted execution frames")
			suite.assert_equal(zone.execution_snapshot(), advanced, "zone animation never advances native execution")
			if identity in ["ice_zone", "space_time_shatter"]:
				var cold: Node2D = StaffScene.instantiate() if is_staff else Gauntlets.new()
				cold.process_mode = Node.PROCESS_MODE_DISABLED
				add_child(cold)
				var restored: bool = cold.restore_execution_snapshot(advanced) if is_staff else cold.restore_execution_snapshot(advanced, {})
				suite.assert_true(restored, "cold native zone restores original execution")
				var cold_visual: Node = cold.get_node("ProductionZoneAtlas")
				cold_visual.sync_from_owner()
				suite.assert_equal(cold_visual.get_node("Primary").frame, 1, "restored zone resumes accepted visual phase")
				suite.assert_equal(cold.execution_snapshot(), advanced, "restored artwork preserves exact cold snapshot")
				cold.queue_free()
			zone.reset_execution_state()
			visual.sync_from_owner()
			suite.assert_true(not visual.visible, "reset suppresses retired zone art")
		zone.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	var unknown: Node2D = StaffScene.instantiate()
	unknown.process_mode = Node.PROCESS_MODE_DISABLED
	var forged := staff_execution("blazing_storm")
	forged.parameters.combo_id = "unknown"
	suite.assert_true(unknown.configure_execution(forged), "native zone accepts generic combination fixture")
	add_child(unknown)
	var rejected_visual := unknown.get_node_or_null("ProductionZoneAtlas")
	if rejected_visual != null:
		rejected_visual.sync_from_owner()
		suite.assert_true(not rejected_visual.visible, "unknown combination cannot borrow a friendly spell identity")
	unknown.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
