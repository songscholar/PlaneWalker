extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var first := await _test_pattern()
	var second := await _test_pattern()
	suite.assert_equal(second, first, "same canonical seed and source reproduce identical initial Storm pattern")
	suite.finish(get_tree())


func _actor(id: String, source: String) -> Node2D:
	var actor: Node2D = ActorScene.instantiate()
	add_child(actor)
	var parser := Definition.new()
	parser.configure(Content.enemy(id))
	var identity := Fixtures.identity()
	identity.hostile_source_id = source
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok, "actual Storm participant configures")
	actor.global_position = Vector2(100, 100)
	return actor


func _test_pattern() -> Array:
	var storm := _actor("chrono_storm_elemental", "hostile:pattern")
	var friend := _actor("rift_watcher", "hostile:friend")
	friend.global_position = Vector2(88, 100)
	friend.apply_time_stop_source(&"pattern-friend-stop", 20.0)
	var friend_hp: float = friend.get_node("HealthComponent").current_hp
	var player: Node2D = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(88, 100)
	var health: Node = player.get_node("HealthComponent")
	health.max_hp = 1000.0
	health.current_hp = 1000.0
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var started: Dictionary = storm.get("_launch_runtime").request_action("chrono_storm_elemental.time_storm", Fixtures.context())
	for fact: Dictionary in started.threat_facts:
		registry.register_fact(Actions.native_threat_fact(fact))
	var actors := {"hostile:friend": friend, "hostile:pattern": storm}
	var initial: Array = []
	var left_fast := false
	for frame: int in range(1, 221):
		if frame == 41:
			player.global_position = Vector2(500, 100)
		if frame == 42:
			player.global_position = Vector2(88, 100)
		suite.assert_true(_step(effects, actors, player, registry, frame, frame == 100), "native seeded Storm advances accepted frame")
		if frame == 39:
			suite.assert_equal(health.current_hp, 1000.0, "native seeded Storm retains its full forty-frame first warning")
		if frame == 40:
			var zones: Array = effects.semantic_snapshot().zones
			zones.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.geometry.origin.x) < float(b.geometry.origin.x))
			suite.assert_true(zones.size() == 2 and zones.all(func(row: Dictionary): return row.has("storm_pattern")), "new canonical Storm zones retain bounded deterministic pattern metadata")
			if zones.size() != 2 or not zones.all(func(row: Dictionary): return row.has("storm_pattern")):
				break
			initial = [zones[0].storm_pattern, zones[1].storm_pattern]
			left_fast = bool(initial[0].initial_fast)
			suite.assert_true(left_fast != bool(initial[1].initial_fast), "actual two-zone Storm contains one fast and one slow field")
			storm.apply_time_stop_source(&"pattern-source-stop", 20.0)
			storm.cancel_active_attack()
			registry.retire_source(&"hostile:pattern")
			_assert_multiplier(player, friend, 1.25 if left_fast else 0.6)
			suite.assert_equal(health.current_hp, 990.0, "new Storm pattern retains its actual time-damage tick")
			await _capture_native(effects, "initial")
		if frame == 41:
			suite.assert_true(not player.floor_rule_effect_snapshot().modifiers.has("launch_semantic|movement"), "leaving fast or slow field removes area-bound movement effect")
		if frame in [99, 100, 129, 130]:
			var nodes: Array = effects.native_semantic_nodes()
			suite.assert_equal(nodes.size(), 2, "pattern swap keeps exactly two admitted native fields")
			for node: Node2D in nodes:
				suite.assert_true(node.has_method("presentation_snapshot"), "actual Storm raster projection exposes its warning phase")
				if node.has_method("presentation_snapshot"):
					suite.assert_equal(node.presentation_snapshot().swap_warning, frame in [100, 129], "swap warns exactly the thirty frames before its ninety-frame boundary")
			_assert_multiplier(player, friend, (0.6 if left_fast else 1.25) if frame == 130 else (1.25 if left_fast else 0.6))
			if frame == 99:
				_test_cold_projection(effects)
			if frame in [100, 130]:
				await _capture_native(effects, "warning" if frame == 100 else "swapped")
		if frame == 220:
			suite.assert_equal(effects.native_semantic_nodes(), [], "finite seeded Storm expires both real native fields")
			suite.assert_equal(registry.snapshot(), [], "finite seeded Storm retires all native hazard facts")
			suite.assert_true(not player.floor_rule_effect_snapshot().modifiers.has("launch_semantic|movement"), "expired pattern cannot retain Player speed or slow")
			suite.assert_close(friend.get("_launch_runtime").control_modifiers().movement_multiplier, 1.0, "expired pattern clears native ally movement source")
	if not initial.is_empty():
		suite.assert_equal(health.current_hp, 970.0, "pattern warning and swaps preserve exactly three time-damage ticks")
		suite.assert_equal(friend.get_node("HealthComponent").current_hp, friend_hp, "Storm ally movement effect never fabricates friendly damage")
	storm.queue_free()
	friend.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame
	return initial


func _assert_multiplier(player: Node2D, friend: Node2D, value: float) -> void:
	suite.assert_close(player.call("_floor_rule_movement_multiplier"), value, "canonical Storm fast or slow affects actual Player")
	suite.assert_close(friend.get("_launch_runtime").control_modifiers().movement_multiplier, value, "canonical Storm pattern affects actual native ally independently of Stop")


func _step(effects: RefCounted, actors: Dictionary, player: Node2D, registry: RefCounted, frame: int, retry: bool) -> bool:
	var before: Dictionary = effects.snapshot()
	var health: Node = player.get_node("HealthComponent")
	var health_before: Dictionary = health.transaction_snapshot() if retry else {}
	var batches: Array = []
	var pairs: Array = []
	for id: String in actors:
		var actor: Node2D = actors[id]
		var context := Fixtures.context(frame)
		context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
		var prepared: Dictionary = actor.prepare_launch_frame(frame, context)
		if not prepared.ok:
			return false
		pairs.append({"actor": actor, "ticket": prepared.ticket})
		batches.append({"hostile_source_id": id, "batch": prepared.batch})
	var routed: Dictionary = effects.prepare_effects(batches, {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": actors, "targets": {"player:1": player}})
	if not routed.ok:
		return false
	for pair: Dictionary in pairs:
		if not pair.actor.commit_launch_frame(pair.ticket):
			return false
	if not effects.commit_effects(routed.ticket).ok:
		return false
	if retry:
		suite.assert_true(effects.rollback_effects(routed.ticket), "candidate warned pattern rolls back actual raster and status sources")
		for pair: Dictionary in pairs:
			pair.actor.rollback_launch_frame(pair.ticket)
		suite.assert_true(health.restore_transaction_snapshot(health_before), "candidate pattern tick compensates actual native Health")
		health.discard_transaction_snapshot(health_before)
		suite.assert_equal(effects.snapshot(), before, "warned pattern retry restores complete effect checkpoint")
		return _step(effects, actors, player, registry, frame, false)
	for pair: Dictionary in pairs:
		pair.actor.publish_launch_frame(pair.ticket)
	return effects.publish_effects(routed.ticket)


func _test_cold_projection(effects: RefCounted) -> void:
	var checkpoint: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(effects.snapshot()).json).replay
	var authority: RefCounted = effects.get("_semantics")
	for change: String in ["speed", "warning", "unknown", "foreign"]:
		var forged: Dictionary = checkpoint.semantics.duplicate(true)
		match change:
			"speed": forged.zones[0].storm_pattern.fast_multiplier = 1.5
			"warning": forged.zones[0].storm_pattern.swap_warning_frames = 90
			"unknown": forged.zones[0].storm_pattern.unowned = true
			"foreign": forged.zones[0].action_id = "rift_weaver.rift_make"
		suite.assert_true(not authority.can_restore_transaction_snapshot(forged), "strict Storm checkpoint refuses " + change + " pattern data")
	var root := Node2D.new()
	add_child(root)
	var twin := Effects.new()
	twin.configure("run-p15")
	twin.configure_native_payloads(root)
	suite.assert_true(twin.restore_launch_transaction_snapshot(checkpoint), "typed replay codec cold-reconstructs actual seeded native field projections")
	suite.assert_equal(twin.snapshot(), effects.snapshot(), "cold Storm checkpoint preserves exact seed decision and phase clock")
	var current_nodes: Array = effects.native_semantic_nodes()
	var restored_nodes: Array = twin.native_semantic_nodes()
	for index: int in range(current_nodes.size()):
		suite.assert_equal(restored_nodes[index].presentation_snapshot(), current_nodes[index].presentation_snapshot(), "fresh native raster projection resumes the same pattern phase")
	var sprite: Sprite2D = current_nodes[0].get_node("Sprite2D")
	var original_texture := sprite.texture
	sprite.texture = load("res://assets/production/hostile_effects/void_pool.png")
	suite.assert_true(not authority.call("_native_matches", checkpoint.semantics), "forged native Storm pattern texture rejects before preparation")
	sprite.texture = original_texture
	var original_color := sprite.modulate
	sprite.modulate = Color.RED
	suite.assert_true(not authority.call("_native_matches", checkpoint.semantics), "forged native Storm warning color rejects before preparation")
	sprite.modulate = original_color
	var legacy := checkpoint.duplicate(true)
	for row: Dictionary in legacy.semantics.zones:
		row.erase("storm_pattern")
	suite.assert_true(twin.restore_launch_transaction_snapshot(legacy), "closed legacy V1 finite zones keep their original behavior until TTL")
	suite.assert_equal(twin.snapshot(), legacy, "legacy restore cannot invent a historical seed decision")
	root.free()


func _capture_native(effects: RefCounted, pose: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		for node: Node2D in effects.native_semantic_nodes():
			var colors: Dictionary = {}
			var foreground := 0
			var background := pixels.get_pixel(0, 0).to_rgba32()
			var origin := Vector2i(node.global_position)
			for y: int in range(origin.y - 22, origin.y + 23):
				for x: int in range(origin.x - 22, origin.x + 23):
					var point := Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))
					var color := pixels.get_pixelv(point).to_rgba32()
					colors[color] = true
					foreground += int(color != background)
			suite.assert_true(colors.size() >= 5 and foreground > 80, "native fast/slow pattern draws substantial original raster pixels")
		var output := "res://build/visual-evidence/p15d-storm-pattern/storm-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native Storm pattern screenshot is retained")
