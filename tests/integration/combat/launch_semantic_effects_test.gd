extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/launch_semantic_effect_authority.gd")
	suite.assert_true(implementation != null, "native semantic effect authority exists")
	if implementation != null:
		await _test_native_heal(implementation)
		await _test_zone_budget(implementation)
		await _test_simultaneous_native_heal()
	suite.finish(get_tree())


func _actor(id: String, source: String) -> Node2D:
	var actor: Node2D = ActorScene.instantiate()
	add_child(actor)
	var parser := Enemy.new()
	parser.configure(Content.enemy(id))
	var identity := Fixtures.identity()
	identity.hostile_source_id = source
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok, "semantic native source configures")
	actor.global_position = Vector2(100, 100)
	return actor


func _test_native_heal(implementation: Script) -> void:
	var watcher := _actor("rift_watcher", "hostile:watcher")
	var recipient := _actor("shattered_sentinel", "hostile:recipient")
	recipient.global_position = Vector2(120, 100)
	recipient.apply_time_stop_source(&"semantic-recipient-stop", 20.0)
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(120, 100)
	var health := recipient.get_node("HealthComponent")
	health.take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:recipient", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 50.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:bow"], "can_crit": false}))
	var authority: RefCounted = implementation.new()
	suite.assert_true(authority.configure("run-p15", 0), "semantic authority accepts fixed clock")
	var root := Node2D.new()
	add_child(root)
	suite.assert_true(authority.configure_native_root(root), "semantic authority owns real native projection root")
	var registry := Registry.new()
	var actors := {"hostile:recipient": recipient, "hostile:watcher": watcher}
	var observation := Fixtures.context()
	watcher.get("_launch_runtime").request_action("rift_watcher.nourish", observation)
	var healed := 0
	for frame: int in range(1, 31):
		var tickets: Array = []
		var batches: Array = []
		for source: String in actors:
			var actor: Node2D = actors[source]
			var context := Fixtures.context(frame)
			context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
			var prepared: Dictionary = actor.prepare_launch_frame(frame, context)
			suite.assert_true(prepared.ok, "semantic actor prepares sequential frame")
			tickets.append({"actor": actor, "ticket": prepared.ticket})
			batches.append({"hostile_source_id": source, "batch": prepared.batch})
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": actors, "targets": {"player:1": player}}
		var before: Dictionary = authority.snapshot()
		var prepared: Dictionary = authority.prepare_effects(batches, context)
		suite.assert_true(prepared.ok, "actual sealed support action prepares semantic effect")
		if not prepared.ok:
			for pair: Dictionary in tickets:
				pair.actor.rollback_launch_frame(pair.ticket)
			break
		suite.assert_equal(authority.snapshot(), before, "semantic preparation is observation-only")
		var forged: Dictionary = prepared.ticket.duplicate(true)
		forged.after.runtime_frame = frame + 1
		suite.assert_true(not authority.commit(forged), "forged semantic ticket rejects atomically")
		for pair: Dictionary in tickets:
			suite.assert_true(pair.actor.commit_launch_frame(pair.ticket), "semantic actor commits before effect")
		suite.assert_true(authority.commit(prepared.ticket), "semantic effect commits its bounded state")
		for request: Dictionary in prepared.health_requests:
			suite.assert_equal(request.target_id, "hostile:recipient", "support excludes itself and Player")
			suite.assert_equal(request.amount, 5.0, "actual Watcher uses authored heal amount")
			healed += 1
		var expected_requests: int = 1 if frame == 30 else 0
		suite.assert_equal(prepared.health_requests.size(), expected_requests, "heal occurs once after the full warning")
		suite.assert_true(authority.rollback(prepared.ticket), "semantic rollback compensates counters and native projection")
		suite.assert_equal(authority.snapshot(), before, "semantic rollback preserves exact checkpoint")
		for pair: Dictionary in tickets:
			pair.actor.rollback_launch_frame(pair.ticket)
		var retry_tickets: Array = []
		var retry_batches: Array = []
		for source: String in actors:
			var actor: Node2D = actors[source]
			var retry_context := Fixtures.context(frame)
			retry_context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
			var retry: Dictionary = actor.prepare_launch_frame(frame, retry_context)
			retry_tickets.append({"actor": actor, "ticket": retry.ticket})
			retry_batches.append({"hostile_source_id": source, "batch": retry.batch})
		var retry: Dictionary = authority.prepare_effects(retry_batches, context)
		suite.assert_equal(retry.health_requests, prepared.health_requests, "same frame retry retains identical heal claim")
		for pair: Dictionary in retry_tickets:
			pair.actor.commit_launch_frame(pair.ticket)
		suite.assert_true(authority.commit(retry.ticket) and authority.can_publish(retry.ticket), "semantic retry seals before publication")
		for pair: Dictionary in retry_tickets:
			pair.actor.publish_launch_frame(pair.ticket)
		suite.assert_true(authority.publish(retry.ticket), "semantic effect publication releases its sealed ticket")
	suite.assert_equal(healed, 1, "actual support emits exactly one healing request")
	var checkpoint: Dictionary = authority.snapshot()
	suite.assert_true(authority.can_restore_transaction_snapshot(checkpoint), "semantic checkpoint validates")
	checkpoint.unowned = true
	suite.assert_true(not authority.restore_transaction_snapshot(checkpoint), "unowned semantic fields reject")
	watcher.queue_free()
	recipient.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _test_zone_budget(implementation: Script) -> void:
	var authority: RefCounted = implementation.new()
	authority.configure("run-p15")
	var root := Node2D.new()
	add_child(root)
	authority.configure_native_root(root)
	var state: Dictionary = authority.snapshot()
	state.zones.append(_zone_record("pending:first", "hostile:pending", true, 1, 4))
	for index: int in range(12):
		state.zones.append(_zone_record("active:%d" % index, "hostile:%d" % index, false, 2, 4))
	suite.assert_true(authority.restore_transaction_snapshot(state), "native budget fixture restores twelve visible zones and retained pending decision")
	for frame: int in range(1, 4):
		var prepared: Dictionary = authority.prepare_effects([], {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": Registry.new(), "actors": {}, "targets": {}})
		suite.assert_true(prepared.ok, "pending zone admission respects complete room budget")
		if not prepared.ok:
			break
		suite.assert_true(authority.commit(prepared.ticket) and authority.publish(prepared.ticket), "bounded pending zone commits natively")
		var zones: Array = authority.snapshot().zones
		suite.assert_equal(zones.filter(func(row: Dictionary): return row.phase != "PENDING").size(), 12 if frame <= 2 else 1, "later existing zones reserve capacity before pending work")
		if frame <= 2:
			suite.assert_equal(zones[0].phase, "PENDING", "full budget retains original pending decision")
		else:
			suite.assert_equal(zones[0].active_frame, 3, "delayed lifetime begins on admission")
			suite.assert_equal(zones[0].expires_frame, 3, "delayed finite lifetime remains authored")
	root.queue_free()
	await get_tree().process_frame


func _zone_record(id: String, source: String, pending: bool, lifetime: int, cap: int) -> Dictionary:
	return {"id": id, "source_id": source, "action_id": "rift_weaver.rift_make", "generation": 1, "hit_index": 0, "reserved_frame": 0, "active_frame": -1 if pending else 0, "expires_frame": -1 if pending else lifetime, "geometry": {"hostile_source_id": source, "attack_generation": 1, "shape": "circle", "origin": {"x": 120.0, "y": 100.0}, "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": {"x": 120.0, "y": 100.0}, "summon_slots": [], "radius": 19.0, "length": 0.0, "active_from_frame": 0, "active_through_frame": 100}, "damage": 8.0, "damage_type": "void", "tick_frames": 60, "warning_frames": 0, "lifetime_frames": lifetime if pending else lifetime + 1, "slow_multiplier": 0.6, "slow_frames": 60, "enemy_only_freeze": false, "owner_immunity": false, "ally_damage": false, "owner_zone_cap": cap, "phase": "PENDING" if pending else "ACTIVE"}


func _test_simultaneous_native_heal() -> void:
	var first := _actor("rift_watcher", "hostile:healer-a")
	var second := _actor("rift_watcher", "hostile:healer-b")
	var recipient := _actor("shattered_sentinel", "hostile:healed")
	var actors := {"hostile:healed": recipient, "hostile:healer-a": first, "hostile:healer-b": second}
	recipient.apply_time_stop_source(&"heal-fixture-stop", 20.0)
	var health: Node = recipient.get_node("HealthComponent")
	health.take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:healed", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 3.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:bow"], "can_crit": false}))
	var publication := {"count": 0, "amount": 0.0}
	health.healed.connect(func(amount: float, _hp: float):
		publication.count += 1
		publication.amount += amount
	)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	first.get("_launch_runtime").request_action("rift_watcher.nourish", Fixtures.context())
	second.get("_launch_runtime").request_action("rift_watcher.nourish", Fixtures.context())
	for frame: int in range(1, 31):
		var pairs: Array[Dictionary] = []
		var batches: Array[Dictionary] = []
		for id: String in actors:
			var actor: Node2D = actors[id]
			var observation := Fixtures.context(frame)
			observation.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
			var prepared: Dictionary = actor.prepare_launch_frame(frame, observation)
			suite.assert_true(prepared.ok, "multiple native healers prepare fixed frame")
			pairs.append({"actor": actor, "ticket": prepared.ticket})
			batches.append({"hostile_source_id": id, "batch": prepared.batch})
		var prepared: Dictionary = effects.prepare_effects(batches, {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": actors, "targets": {}})
		suite.assert_true(prepared.ok, "actual native heal router accepts competing support sources")
		if not prepared.ok:
			for pair: Dictionary in pairs:
				pair.actor.rollback_launch_frame(pair.ticket)
			break
		for pair: Dictionary in pairs:
			suite.assert_true(pair.actor.commit_launch_frame(pair.ticket), "native heal actor commits")
		suite.assert_true(effects.commit_effects(prepared.ticket).ok, "actual Health sink receives authored heal")
		suite.assert_equal(publication.count, 0, "native healing stays buffered until publication")
		for pair: Dictionary in pairs:
			pair.actor.publish_launch_frame(pair.ticket)
		suite.assert_true(effects.publish_effects(prepared.ticket), "actual support heal publishes once")
	suite.assert_equal(health.current_hp, health.max_hp, "same-frame healing clamps to native missing HP")
	suite.assert_equal(publication.count, 1, "competing healer with zero remaining gain emits no observation")
	suite.assert_equal(publication.amount, 3.0, "native publication reports actual positive gain")
	var semantic: Dictionary = effects.semantic_snapshot()
	suite.assert_equal(semantic.heal_recipients.get("hostile:healed", 0.0), 3.0, "shared healing budget charges actual same-frame gain")
	suite.assert_equal(semantic.heal_sources.get("hostile:healer-b", {}), {}, "later healer retains unused encounter budget")
	for actor: Node2D in actors.values():
		actor.queue_free()
	root.queue_free()
	await get_tree().process_frame
