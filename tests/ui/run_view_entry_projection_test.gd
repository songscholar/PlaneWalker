extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Projector := preload("res://scripts/application/run_view_state_projector.gd")
const Contract := preload("res://scripts/ui/contracts/run_view_state.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	GameState.save_path = OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("entry_projection/save.json")
	var main := Main.instantiate()
	add_child(main)
	await _frames(3)
	main.get_node("HubFlowCoordinator").hide_hub()
	main.call("_show_start_menu")
	var config: Dictionary = main.call("_build_run_config")
	config.seed = 20261006
	suite.assert_true(main.call("_launch_run", config, false), "entry projection reads an actual deterministic LAUNCH run")
	var host := main.get_node("RunRuntimeHost")
	var source: Dictionary = host.call("runtime_snapshot")
	var snapshot := source.duplicate(true)
	var room: Dictionary = host.get("_facade").call("current_room_definition")
	var player: Dictionary = host.call("_player_ui_snapshot")
	var before := player.duplicate(true)
	var projector := Projector.new()
	var projected = projector.project(source, room, player, null, 0)
	if not projected.ok:
		print("ENTRY_PROJECTION_DIAGNOSTIC ", JSON.stringify({"code": projected.code, "context": projected.context, "current_room": source.get("current_room"), "current_floor": source.get("current_floor"), "run_seed": source.get("run_seed"), "floor_plan": source.get("floor_plan"), "config": source.get("config")}))
	suite.assert_true(projected.ok, "verified dungeon entry has a typed HUD projection with zero rooms traversed")
	if projected.ok:
		var view: Dictionary = projected.context.view_state
		suite.assert_equal(view.room.index, 0, "entry retains the actual zero room index")
		suite.assert_equal(view.room.type, "entry", "entry derives its type from the authoritative entry node")
		suite.assert_true(tr(view.room.title_key) != view.room.title_key, "entry room has a localized name")
		for field: String in ["combat", "negative", "positive_entry", "combat_phase"]:
			var invalid := view.duplicate(true)
			match field:
				"combat": invalid.room.type = "combat"
				"negative": invalid.room.index = -1
				"positive_entry": invalid.room.index = 1
				"combat_phase": invalid.phase = "COMBAT_ACTIVE"
			suite.assert_true(not Contract.validate(invalid).ok, "entry extension refuses invalid projected " + field)
	for mutation: String in ["room_definition", "node_type", "node_layer", "duplicate", "missing", "route", "seed", "floor", "digest"]:
		var forged := snapshot.duplicate(true)
		var definition := room.duplicate(true)
		match mutation:
			"room_definition": definition = {"type": "combat", "runtime_mode": "launch"}
			"route": forged.floor_plan.selected_edge_ids = ["spoofed_edge"]
			"duplicate": forged.floor_plan.nodes.append(forged.floor_plan.nodes[0].duplicate(true))
			"seed": forged.run_seed += 1
			"floor": forged.current_floor += 1
			"digest": forged.floor_plan.generation_digest = "forged"
			_:
				for node: Dictionary in forged.floor_plan.nodes:
					if node.id == "entry":
						match mutation:
							"node_type": node.room_type = "combat"
							"node_layer": node.layer = 1
							"missing": node.id = "fake_entry"
		var refused = Projector.new().project(forged, definition, player, null, 0)
		suite.assert_true(not refused.ok, "entry projection refuses spoofed " + mutation)
	suite.assert_equal(source, snapshot, "entry presentation does not normalize authoritative state")
	suite.assert_equal(player, before, "entry presentation does not normalize native player state")
	main.queue_free()
	await _frames(3)
	suite.finish(get_tree())


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
