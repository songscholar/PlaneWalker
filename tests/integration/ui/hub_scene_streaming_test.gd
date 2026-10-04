extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const HubHost := preload("res://scripts/hub/hub_scene_host.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var host := HubHost.new()
	add_child(host)
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string(HubHost.DEFINITIONS_PATH))
	suite.assert_equal(definitions.size(), 3, "native shell consumes the three authored Base district definitions")
	var seen: Array = []
	var requests: Array = []
	var retired: Node2D
	host.function_requested.connect(func(id: String, epoch: int): requests.append([id, epoch]))
	for definition: Dictionary in definitions:
		suite.assert_true(host.install_district(definition).ok, "authored native district installs: " + definition.id)
		if is_instance_valid(retired):
			var count := requests.size()
			retired.function_requested.emit(str(definitions[0].functions[0].id))
			suite.assert_equal(requests.size(), count, "retired native district cannot publish through its captured epoch")
		suite.assert_equal(host.get_child_count(), 1, "only one native district remains loaded")
		var active: Node2D = host.get_child(0)
		var view: Dictionary = host.snapshot()
		suite.assert_equal(view.district_id, definition.id, "native scene identity matches the data catalog")
		suite.assert_equal(view.arrival, Vector2(definition.arrival.x, definition.arrival.y), "actual walker starts at the authored arrival")
		suite.assert_equal(active.get_node("Background").texture.get_size(), Vector2(640, 360), "district uses a real fixed-format pixel raster")
		await _walk_to(host, Vector2(320, 176))
		suite.assert_true(host.snapshot().walker_position.distance_to(Vector2(320, 176)) < 5, "actual InputMap movement reaches the center NPC")
		var paused_position: Vector2 = host.snapshot().walker_position
		get_tree().paused = true
		Input.action_press("move_left")
		for _frame: int in range(4):
			await get_tree().process_frame
		Input.action_release("move_left")
		suite.assert_equal(host.snapshot().walker_position, paused_position, "paused Hub cannot advance actual walker movement")
		suite.assert_true(not host.request_function(str(definition.functions[0].id), int(view.epoch)).ok, "paused accessible controls cannot publish")
		get_tree().paused = false
		for function: Dictionary in definition.functions:
			seen.append(function.id)
			var location := Vector2(function.position.x, function.position.y)
			suite.assert_true(host.reachable_position(location), "NPC is reachable inside the native movement bounds")
			suite.assert_true(host.request_function(function.id, int(view.epoch)).ok, "accessible focus route reaches the authored function")
			suite.assert_equal(requests.back()[0], function.id, "native route publishes the actual function identity")
			await _walk_to(host, location)
			var count := requests.size()
			var interaction := InputEventAction.new()
			interaction.action = "interact"
			interaction.pressed = true
			active._unhandled_input(interaction)
			suite.assert_equal(requests.size(), count + 1, "actual nearby walker interaction reaches the NPC")
			suite.assert_equal(requests.back()[0], function.id, "nearby interaction chooses the correct authored destination")
		var before := host.snapshot()
		suite.assert_true(not host.request_function("invented", int(view.epoch)).ok, "unknown functions cannot cross the native boundary")
		suite.assert_true(not host.request_function(str(definition.functions[0].id), int(view.epoch) - 1).ok, "retired focus controls cannot submit")
		suite.assert_equal(host.snapshot(), before, "refused native interaction cannot change district or arrival")
		var corrupt := definition.duplicate(true)
		corrupt.scene_path = "res://scenes/main.tscn"
		suite.assert_true(not host.install_district(corrupt).ok, "arbitrary scene paths refuse before replacing the current district")
		suite.assert_equal(host.snapshot(), before, "bad travel preserves the native scene")
		host.set_interaction_enabled(false)
		var count := requests.size()
		Input.action_press("move_down")
		for _frame: int in range(4):
			await get_tree().physics_frame
		Input.action_release("move_down")
		suite.assert_equal(host.snapshot().walker_position, before.walker_position, "open panel gating stops actual Hub movement")
		suite.assert_true(not host.request_function(str(definition.functions[0].id), int(view.epoch)).ok, "open panel gating refuses native controls")
		suite.assert_equal(requests.size(), count, "disabled scene publishes no interactions")
		host.set_interaction_enabled(true)
		retired = active
	seen.sort()
	suite.assert_equal(seen, ["archive", "council", "forge", "gallery", "gateway", "meditation", "merchant", "mirror", "training"], "all nine authored destinations have actual native routes")
	host.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _walk_to(host: Node2D, target: Vector2) -> void:
	for _frame: int in range(240):
		var position: Vector2 = host.snapshot().walker_position
		if position.distance_to(target) < 4:
			break
		for pair: Array in [["move_left", position.x > target.x + 2], ["move_right", position.x < target.x - 2], ["move_up", position.y > target.y + 2], ["move_down", position.y < target.y - 2]]:
			if pair[1]:
				Input.action_press(pair[0])
			else:
				Input.action_release(pair[0])
		await get_tree().physics_frame
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	await get_tree().physics_frame
