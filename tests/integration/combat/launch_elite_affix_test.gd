extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Fixture := preload("res://tests/support/p15_action_fixtures.gd")
const Scene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Player := preload("res://scenes/player/player.tscn")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var probe: Node2D = Scene.instantiate()
	add_child(probe)
	suite.assert_true(probe.has_method("configure_launch_affixes"), "actual elite Actor must configure canonical native affix execution")
	if not probe.has_method("configure_launch_affixes"):
		probe.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	probe.queue_free()
	await get_tree().process_frame
	await _test_static("frenzy", 160.0, 73.6, 1.2, 10.0)
	await _test_static("fortified", 240.0, 51.2, 1.0, 8.0)
	await _test_configuration_rejection()
	await _test_signature_binding()
	suite.finish(get_tree())


func _actor(ids: Array, source: String = "hostile:affix", floor: int = 1) -> Node2D:
	var actor: Node2D = Scene.instantiate()
	add_child(actor)
	var rows: Array = []
	for id: String in ids:
		rows.append(Content.affix(id))
	suite.assert_true(actor.configure_launch_affixes(rows, floor).ok, "canonical native affix definitions configure before Actor initialization")
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := Fixture.identity()
	identity.hostile_source_id = source
	identity.seed = 42
	var configured: Dictionary = actor.configure_launch_definition(parser.runtime_projection("elite"), identity)
	suite.assert_true(configured.ok, "actual elite body configures derived affix authority: " + str(configured))
	actor.global_position = Vector2(100, 100)
	return actor


func _test_static(id: String, hp: float, speed: float, incoming: float, knockback: float) -> void:
	var actor := _actor([id])
	if actor.launch_runtime_snapshot().runtime.is_empty():
		actor.queue_free()
		await get_tree().process_frame
		return
	var health: Node = actor.get_node("HealthComponent")
	suite.assert_close(health.max_hp, hp, "canonical affix changes actual elite Health capacity once")
	suite.assert_close(actor.move_speed, speed, "canonical affix changes actual movement speed")
	suite.assert_close(actor.get_damage_taken_multiplier(), incoming, "canonical affix reaches native incoming damage authority")
	suite.assert_close(actor.get_node("CollisionShape2D").shape.radius, 9.0, "affix and elite silhouette retain authored collision radius")
	suite.assert_close(actor.get_node("Sprite2D").scale.x, 1.15, "elite has authored visual-only silhouette scale")
	actor.apply_knockback(Vector2(10, 0))
	suite.assert_close(actor.get("_knockback_velocity").x, knockback, "actual knockback uses canonical bounded resistance")
	actor.set("_knockback_velocity", Vector2.ZERO)
	var checkpoint: Dictionary = actor.launch_transaction_snapshot()
	var context := Fixture.context(1)
	context.target_position = {"x": 500.0, "y": 100.0}
	var prepared: Dictionary = actor.prepare_launch_frame(1, context)
	suite.assert_true(prepared.ok, "native affix prepares deterministic physical movement")
	if prepared.ok:
		suite.assert_close(float(prepared.ticket.after.position.x) - 100.0, speed / 60.0, "accepted native displacement uses affix speed")
		suite.assert_true(actor.commit_launch_frame(prepared.ticket), "native affix candidate commits")
		suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "native affix candidate compensates")
		suite.assert_equal(actor.launch_transaction_snapshot(), checkpoint, "rejected frame preserves complete affix authority and Health")
	health.discard_transaction_snapshot(checkpoint.health)
	health.take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:affix", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 10.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:bow"], "can_crit": false}))
	suite.assert_close(health.current_hp, hp - 10.0 * incoming, "native Health applies affix vulnerability with authored zero defense")
	var runtime: RefCounted = actor.get("_launch_runtime")
	var started: Dictionary = runtime.request_action("shattered_sentinel.shield_sweep", Fixture.context())
	suite.assert_true(started.ok, "derived elite affix action submits its actual warning")
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.global_position = Vector2(120, 100)
	var player_health: Node = player.get_node("HealthComponent")
	player_health.max_hp = 1000.0
	player_health.current_hp = 1000.0
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	for geometry: Dictionary in started.threat_facts:
		registry.register_fact(Actions.native_threat_fact(geometry))
	var hit_damage := 0.0
	for frame: int in range(1, 31):
		context = Fixture.context(frame)
		context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
		prepared = actor.prepare_launch_frame(frame, context)
		suite.assert_true(prepared.ok, "derived elite warning advances sealed native frame")
		if not prepared.ok:
			break
		if frame < 30:
			suite.assert_equal(prepared.batch.hit_facts, [], "frenzy preserves all thirty authored warning frames")
		for hit: Dictionary in prepared.batch.hit_facts:
			hit_damage = float(hit.damage)
		var routed: Dictionary = effects.prepare_effects([{"hostile_source_id": "hostile:affix", "batch": prepared.batch}], {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": {"hostile:affix": actor}, "targets": {"player:1": player}})
		suite.assert_true(routed.ok, "native Router authenticates derived elite affix hit")
		if not routed.ok:
			actor.rollback_launch_frame(prepared.ticket)
			break
		suite.assert_true(actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(routed.ticket).ok and actor.publish_launch_frame(prepared.ticket) and effects.publish_effects(routed.ticket), "actual affix Actor, Router and Health commit and publish")
	suite.assert_close(hit_damage, 18.75 if id == "frenzy" else 15.0, "native hit facts multiply elite and affix damage exactly once")
	suite.assert_close(player_health.current_hp, 981.25 if id == "frenzy" else 985.0, "actual Player Health receives the affix-scaled native Router strike once")
	var encoded: Dictionary = Replay.encode_replay_json(actor.native_cold_snapshot(func(_source: Node): return {}))
	var cold: Dictionary = Replay.decode_replay_json(encoded.json).replay
	var twin := _actor([id])
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "typed cold native restore reconstructs derived affix state and actual Health")
	suite.assert_equal(twin.native_cold_snapshot(func(_source: Node): return {}), cold, "cold restore preserves exact affix configuration and warning phase")
	var forged := cold.duplicate(true)
	forged.actor.affixes.damage_taken_multiplier = 2.0
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "forged fixed affix multiplier refuses before native restoration")
	actor.queue_free()
	twin.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _test_configuration_rejection() -> void:
	for rows: Array in [[Content.affix("frenzy"), Content.affix("fortified")], [Content.affix("frenzy"), Content.affix("frenzy")]]:
		var actor: Node2D = Scene.instantiate()
		add_child(actor)
		var report: Dictionary = actor.configure_launch_affixes(rows, 1)
		var parser := Definition.new()
		parser.configure(Content.enemy())
		var identity := Fixture.identity()
		identity.seed = 42
		suite.assert_true(not report.ok or not actor.configure_launch_definition(parser.runtime_projection("elite"), identity).ok, "mutually excluded or duplicate affixes fail before actor initialization")
		actor.queue_free()
	var actor: Node2D = Scene.instantiate()
	add_child(actor)
	var forged := Content.affix("frenzy")
	forged.parameters.damage_multiplier = 3.0
	suite.assert_true(not actor.configure_launch_affixes([forged], 1).ok, "noncanonical affix parameters refuse at configuration boundary")
	actor.queue_free()
	await get_tree().process_frame


func _test_signature_binding() -> void:
	var actor := _actor(["chaining"], "hostile:affix", 3)
	suite.assert_equal(actor.launch_affix_snapshot().pending_ids, ["chaining"], "dynamic-only affix remains explicit pending native scope")
	var saved: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	saved.actor.erase("affixes")
	var legacy: Node2D = Scene.instantiate()
	add_child(legacy)
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := Fixture.identity()
	identity.hostile_source_id = "hostile:affix"
	identity.seed = 42
	suite.assert_true(legacy.configure_launch_definition(parser.runtime_projection("elite"), identity).ok, "closed original elite configures without affix compiler")
	suite.assert_true(not legacy.can_restore_native_cold_snapshot(saved, func(_binding: Dictionary): return null), "pending-only affine signature prevents stripped-extension downgrade without stat differences")
	var left := _actor(["frenzy", "anchored"], "hostile:ordered", 3)
	var right := _actor(["anchored", "frenzy"], "hostile:ordered", 3)
	suite.assert_equal(left.launch_runtime_snapshot().runtime.definition_digest, right.launch_runtime_snapshot().runtime.definition_digest, "canonical pair compiler is independent of supplied row order")
	actor.queue_free()
	legacy.queue_free()
	left.queue_free()
	right.queue_free()
	await get_tree().process_frame
