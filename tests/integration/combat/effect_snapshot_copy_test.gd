extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Player := preload("res://scenes/player/player.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const RUN := "run-effect-snapshot-copy"
var suite: RefCounted
var redundant_inputs: Array[String] = []
var observations: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var path := OS.get_environment("PLANEWALKER_EFFECT_SNAPSHOT_PROBE")
	if path.is_empty():
		_empty_workflows(Effects)
		await _authored_workflow(Effects)
		print("PLANEWALKER_EFFECTS_SNAPSHOT_COPY_PROBE ", JSON.stringify({"instrumented": false, "copy_traversal_certified": false}))
		suite.finish(get_tree())
		return
	suite.assert_true(path.begins_with("res://build/"), "actual snapshot instrumentation is supplied")
	var instrumented: Script = load(path) if path.begins_with("res://build/") else null
	suite.assert_true(instrumented != null, "actual instrumented Effects compiles")
	if instrumented != null:
		var native_empty: Dictionary = _empty_workflows(Effects)
		var probe_empty: Dictionary = _empty_workflows(instrumented)
		suite.assert_equal(var_to_bytes(probe_empty), var_to_bytes(native_empty), "transformed and untransformed empty workflows preserve complete typed bytes")
		var native_rich: Dictionary = await _authored_workflow(Effects)
		var probe_rich: Dictionary = await _authored_workflow(instrumented)
		suite.assert_equal(var_to_bytes(probe_rich), var_to_bytes(native_rich), "transformed and untransformed authored workflows preserve complete typed bytes")
		print("PLANEWALKER_EFFECTS_SNAPSHOT_COPY_PROBE ", JSON.stringify({"observations": observations, "redundant_inputs": redundant_inputs}))
		suite.assert_equal(redundant_inputs.size(), 0, "snapshot never deep-copies overwritten retained child branches")
	suite.finish(get_tree())


func _empty_workflows(implementation: Script) -> Dictionary:
	var authority: RefCounted = implementation.new()
	_check(authority, "unconfigured")
	suite.assert_true(authority.configure(RUN), "actual Effects configures")
	_check(authority, "configured")
	var registry := Registry.new()
	var context := {"run_id": RUN, "runtime_frame": 1, "threat_registry": registry, "actors": {}, "targets": {}}
	var before: Dictionary = authority.snapshot()
	var prepared: Dictionary = authority.prepare_effects([], context)
	suite.assert_true(prepared.ok, "actual empty frame prepares")
	if not prepared.ok:
		return {}
	suite.assert_true(authority.commit_effects(prepared.ticket).ok, "actual empty frame commits")
	_check(authority, "committed")
	var forged: Dictionary = prepared.ticket.duplicate(true)
	forged.after.claims.append("forged".sha256_text())
	suite.assert_true(not authority.can_publish_effects(forged), "full ticket equality rejects mutated candidate")
	suite.assert_true(authority.rollback_effects(prepared.ticket), "actual Effects compensates")
	_check(authority, "compensated")
	suite.assert_equal(var_to_bytes(authority.snapshot()), var_to_bytes(before), "compensation retains complete original typed snapshot")
	var retry: Dictionary = authority.prepare_effects([], context)
	suite.assert_true(retry.ok, "same actual frame retries")
	if not retry.ok:
		return {}
	suite.assert_equal(var_to_bytes(retry.ticket.after), var_to_bytes(prepared.ticket.after), "deterministic retry retains complete candidate")
	suite.assert_true(authority.commit_effects(retry.ticket).ok and authority.publish_effect_observations(retry.ticket), "actual retry commits and publishes")
	suite.assert_true(not authority.can_commit_effects(retry.ticket), "published ticket cannot be reused")
	_check(authority, "published")
	var restored: Dictionary = authority.snapshot()
	for index: int in range(32):
		restored.claims.append(("retained-claim-%d" % index).sha256_text())
	var reordered := {}
	for key: String in ["summons", "claims", "semantics", "run_id", "payloads", "runtime_frame", "schema_version"]:
		reordered[key] = restored[key]
	suite.assert_true(authority.restore_launch_transaction_snapshot(reordered), "actual reordered complete restore validates")
	_check(authority, "reordered-restored")
	suite.assert_equal(authority.snapshot().keys(), reordered.keys(), "accepted restored key order is preserved")
	var pristine := var_to_bytes(authority.snapshot())
	var returned: Dictionary = authority.snapshot()
	returned.claims.clear()
	returned.payloads.claims.append("outside".sha256_text())
	returned.semantics.spatial.rows.append({"outside": true})
	returned.summons.rows.append({"outside": true})
	suite.assert_equal(var_to_bytes(authority.snapshot()), pristine, "outward mutation leaves original live composition unchanged")
	suite.assert_equal(authority.snapshot().claims.size(), 32, "returned claims are deeply isolated")
	var encoded := Replay.encode_replay_json(reordered)
	suite.assert_true(encoded.ok, "actual typed JSON codec accepts full Effects snapshot")
	var decoded := Replay.decode_replay_json(encoded.json)
	suite.assert_true(decoded.ok and authority.restore_launch_transaction_snapshot(decoded.replay), "actual typed JSON restore validates")
	_check(authority, "json-restored")
	return {"before": before, "after": authority.snapshot()}


func _authored_workflow(implementation: Script) -> Dictionary:
	var room: Node2D = Room.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var template := {}
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if row.id == "room_combat_open_field":
			template = row
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	suite.assert_true(player.configure_run(StringName(RUN)), "actual Player binds authored snapshot run")
	player.global_position = Vector2(160, 180)
	player.health.acquire_invulnerability_source(&"snapshot-fixture")
	var root := Node2D.new()
	add_child(root)
	var authority: RefCounted = implementation.new()
	suite.assert_true(authority.configure(RUN) and authority.configure_native_payloads(root) and authority.configure_native_summon_room(room, template), "actual composed Effects owns native roots and room")
	var actors := {}
	var registry := Registry.new()
	for id: String in ["corrosive_moth", "rewind_priest", "forest_caller"]:
		var actor: Node2D = load("res://data/content_packs/base/assets/enemies/launch/enemy_%s.tscn" % id).instantiate()
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		add_child(actor)
		actor.global_position = Vector2(100, 160 + actors.size() * 20)
		var definition := Enemy.new()
		suite.assert_true(definition.configure(Content.enemy(id)).ok, "actual authored snapshot definition validates " + id)
		var source := "snapshot-" + id
		suite.assert_true(actor.configure_launch_definition(definition.runtime_projection(), {"run_id": RUN, "hostile_source_id": source, "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}).ok and actor.configure_launch_room_motion(room, template).ok, "actual authored snapshot actor configures " + id)
		actors[source] = actor
	suite.assert_true(authority.bind_native_targets(actors, {"player:1": player}), "actual composed Effects binds authored targets")
	for entry: Array in [["corrosive_moth", "corrosive_moth.corrosive_spit"], ["rewind_priest", "rewind_priest.rewind_heal"], ["forest_caller", "forest_caller.void_call"]]:
		var actor: Node2D = actors["snapshot-" + entry[0]]
		var started: Dictionary = actor.get("_launch_runtime").request_action(entry[1], _actor_context(actor, player, 0))
		suite.assert_true(started.ok, "actual authored snapshot action begins " + entry[1] + ": " + str(started))
		for fact: Dictionary in started.get("threat_facts", []):
			registry.register_fact(Actions.native_threat_fact(fact))
	await get_tree().physics_frame
	var frames := 0
	var source_order := actors.keys()
	source_order.sort()
	for frame: int in range(1, 47):
		var pairs: Array[Dictionary] = []
		var batches: Array[Dictionary] = []
		for source: String in source_order:
			var actor: Node2D = actors[source]
			var prepared: Dictionary = actor.prepare_launch_frame(frame, _actor_context(actor, player, frame))
			suite.assert_true(prepared.ok, "real authored actor prepares snapshot frame")
			if prepared.ok:
				pairs.append({"actor": actor, "ticket": prepared.ticket})
				batches.append({"hostile_source_id": source, "batch": prepared.batch})
		var prepared: Dictionary = authority.prepare_effects(batches, {"run_id": RUN, "runtime_frame": frame, "threat_registry": registry, "actors": actors, "targets": {"player:1": player}})
		suite.assert_true(prepared.ok, "real authored effects prepare snapshot frame %d: %s" % [frame, str(prepared) if not prepared.ok else "accepted"])
		if not prepared.ok:
			for pair: Dictionary in pairs:
				pair.actor.rollback_launch_frame(pair.ticket)
			break
		for pair: Dictionary in pairs:
			suite.assert_true(pair.actor.commit_launch_frame(pair.ticket), "real authored actor commits snapshot frame")
		suite.assert_true(authority.commit_effects(prepared.ticket).ok, "real authored effects commit snapshot frame")
		for pair: Dictionary in pairs:
			suite.assert_true(pair.actor.publish_launch_frame(pair.ticket), "real authored actor publishes snapshot frame")
		suite.assert_true(authority.publish_effect_observations(prepared.ticket), "real authored effects publish snapshot frame")
		frames = frame
		if frame == 30:
			for node: Node2D in authority.native_payload_nodes():
				node.apply_time_stop_source(&"snapshot-payload-stop", 10.0)
	var retained: Dictionary = authority.snapshot()
	suite.assert_equal(frames, 46, "actual rich fixture completes all authored frames")
	suite.assert_true(not retained.payloads.projectiles.is_empty(), "real authored payload snapshot is populated")
	suite.assert_true(not retained.semantics.histories.is_empty(), "real authored semantic history snapshot is populated")
	suite.assert_true(not retained.summons.rows.is_empty(), "real authored summon snapshot is populated")
	_check(authority, "authored-histories")
	var pristine := var_to_bytes(authority.snapshot())
	var outward: Dictionary = authority.snapshot()
	if not outward.payloads.projectiles.is_empty():
		outward.payloads.projectiles[0].control.sources.clear()
	for history: Dictionary in outward.semantics.histories.values():
		if not history.frames.is_empty():
			history.frames[0].hp = -1.0
	if not outward.summons.rows.is_empty():
		outward.summons.rows[0].projection.clear()
	suite.assert_equal(var_to_bytes(authority.snapshot()), pristine, "nested authored outward mutations cannot alter any child authority")
	var summons: Dictionary = authority.summon_snapshot()
	summons.claims.append("direct-child-claim".sha256_text())
	suite.assert_true(authority.restore_native_summon_snapshot(summons), "direct real summon restore updates fresh child authority")
	suite.assert_true(authority.get("_state").get("summons", {}) != authority.summon_snapshot(), "direct child restore leaves retained envelope stale")
	_check(authority, "fresh-child-over-stale-cache")
	suite.assert_true(authority.snapshot().summons.claims.has("direct-child-claim".sha256_text()), "full public snapshot reads fresh child over cached value")
	var result: Dictionary = authority.snapshot()
	suite.assert_true(authority.dispose_native_effects(), "actual fixture disposes native child ownership")
	for actor: Node2D in actors.values():
		actor.queue_free()
	player.queue_free()
	root.queue_free()
	room.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return result


func _actor_context(actor: Node2D, player: Node2D, frame: int) -> Dictionary:
	return {"runtime_frame": frame, "source_position": {"x": actor.global_position.x, "y": actor.global_position.y}, "target_position": {"x": player.global_position.x, "y": player.global_position.y}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}


func _original(authority: RefCounted) -> Dictionary:
	var result: Dictionary = authority.get("_state").duplicate(true)
	if not result.is_empty():
		result["payloads"] = authority.payload_snapshot()
		result["semantics"] = authority.semantic_snapshot()
		result["summons"] = authority.summon_snapshot()
	return result


func _check(authority: RefCounted, label: String) -> void:
	var before := var_to_bytes(authority.get("_state"))
	var children_before := var_to_bytes([authority.payload_snapshot(), authority.semantic_snapshot(), authority.summon_snapshot()])
	var reference := _original(authority)
	var probed := authority.has_method("_pw_reset_snapshot_copy_probe")
	if probed:
		authority.call("_pw_reset_snapshot_copy_probe")
	var actual: Dictionary = authority.snapshot()
	suite.assert_equal(var_to_bytes(actual), var_to_bytes(reference), "complete original typed snapshot parity " + label)
	suite.assert_equal(actual.keys(), reference.keys(), "original snapshot field order " + label)
	suite.assert_equal(var_to_bytes(authority.get("_state")), before, "snapshot leaves retained live authority unchanged " + label)
	suite.assert_equal(var_to_bytes([authority.payload_snapshot(), authority.semantic_snapshot(), authority.summon_snapshot()]), children_before, "snapshot leaves every actual child authority unchanged " + label)
	if probed:
		var copied: Array = authority.call("_pw_snapshot_copy_probe_inputs")
		for key: String in copied:
			redundant_inputs.append(label + ":" + key)
		observations.append({"state": label, "copied_branches": copied, "snapshot_bytes": var_to_bytes(actual).size()})
