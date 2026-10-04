extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Definition := preload("res://tests/unit/enemies/launch_enemy_runtime_test.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
	suite.assert_true(implementation != null, "P15 native hostile effect authority exists")
	if implementation != null:
		await _test_actual_player_damage(implementation)
		await _test_moving_actor_burn(implementation)
		await _test_registry_cas_and_missed_geometry(implementation)
	suite.finish(get_tree())


func _test_actual_player_damage(implementation: Script) -> void:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	suite.assert_true(player.configure_run(&"run-p15"), "real Player installs hostile run identity")
	player.global_position = Vector2(120, 100)
	var health := player.get_node("HealthComponent")
	health.current_hp = 100.0
	health.defense = 0.0
	var actor := ActorScene.instantiate()
	add_child(actor)
	await get_tree().process_frame
	var identity := Actions.identity()
	identity["seed"] = 42
	suite.assert_true(actor.configure_launch_definition(Definition.definition(), identity).ok, "native Sentinel installs verified projection")
	actor.global_position = Vector2(100, 100)
	var registry: RefCounted = Registry.new()
	var authority: RefCounted = implementation.new()
	suite.assert_true(authority.configure("run-p15", 0), "native effect authority configures accepted clock")
	var observations: Array = []
	var observed := func(info: RefCounted, target: Node, _amount: float) -> void:
		if target == player:
			observations.append(health.published_damage_observation_context(info))
	var callback_context: Dictionary = {}
	var reentry: Array = []
	var reentrant := func(_info: RefCounted, target: Node, _amount: float) -> void:
		if target == player:
			reentry.append(authority.prepare_effects([], callback_context).ok)
	EventBus.hit_confirmed.connect(observed)
	EventBus.hit_confirmed.connect(reentrant)
	var did_hit := false
	for frame: int in range(1, 121):
		var actor_checkpoint: Dictionary = actor.launch_transaction_snapshot()
		var player_checkpoint: Dictionary = health.transaction_snapshot()
		var prepared: Dictionary = actor.prepare_launch_frame(frame, Actions.context(frame))
		suite.assert_true(prepared.ok, "actor prepares production frame")
		if not prepared.ok:
			break
		var batches := [{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}]
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": {"hostile:test-a": actor}, "targets": {"player:1": player, "hostile:test-a": actor}}
		if not prepared.batch.hit_facts.is_empty():
			var before_hp: float = health.current_hp
			var forged := batches.duplicate(true)
			forged[0].batch.hit_facts[0].damage = 999.0
			suite.assert_true(not authority.prepare_effects(forged, context).ok, "forged damage cannot replace sealed native action batch")
			suite.assert_equal(health.current_hp, before_hp, "rejected batch does not mutate real Health")
		var effect: Dictionary = authority.prepare_effects(batches, context)
		suite.assert_true(effect.ok, "native effect preflight validates production action batch")
		if not effect.ok:
			actor.rollback_launch_frame(prepared.ticket)
			actor.discard_launch_transaction_snapshot(actor_checkpoint)
			health.discard_transaction_snapshot(player_checkpoint)
			break
		suite.assert_true(actor.can_commit_launch_frame(prepared.ticket) and authority.can_commit_effects(effect.ticket), "actor and effect preflight accept before mutation")
		suite.assert_true(actor.commit_launch_frame(prepared.ticket), "native actor candidate commits")
		suite.assert_true(authority.commit_effects(effect.ticket).ok, "native effect applies registered geometry and real Health damage")
		if not prepared.batch.hit_facts.is_empty():
			did_hit = true
			suite.assert_equal(health.current_hp, 88.0, "paired sweep deals twelve damage once to actual Player")
			suite.assert_true(authority.rollback_effects(effect.ticket), "effect compensation restores registry claims and native signal buffers")
			suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "actor frame compensates")
			suite.assert_true(actor.restore_launch_transaction_snapshot(actor_checkpoint), "actor owner restores source Health and domain")
			suite.assert_true(health.restore_transaction_snapshot(player_checkpoint), "outer Player Health owner restores HP and ledger")
			suite.assert_equal(health.current_hp, 100.0, "rolled-back actual Player damage restores HP")
			var retried: Dictionary = actor.prepare_launch_frame(frame, Actions.context(frame))
			batches[0].batch = retried.batch
			var retry: Dictionary = authority.prepare_effects(batches, context)
			suite.assert_true(retry.ok and actor.commit_launch_frame(retried.ticket) and authority.commit_effects(retry.ticket).ok, "same accepted frame retries without consuming hit claim")
			suite.assert_equal(observations, [], "rolled-back and unsealed native damage publishes no public hit")
			callback_context.merge(context, true)
			callback_context.runtime_frame = frame + 1
			suite.assert_true(authority.can_publish_effects(retry.ticket), "native effect publication is sealed before observations")
			suite.assert_true(actor.publish_launch_frame(retried.ticket) and authority.publish_effects(retry.ticket), "retry publishes actual sealed damage once")
			suite.assert_equal(health.current_hp, 88.0, "retry retains exactly one real damage application")
			suite.assert_equal(observations.size(), 1, "real native hit publishes exactly one public observation")
			if observations.size() == 1:
				suite.assert_equal(observations[0].hp_before, 100.0, "native public hit retains settled pre-hit HP")
				suite.assert_equal(observations[0].hp_after, 88.0, "native public hit retains settled post-hit HP")
			suite.assert_equal(reentry, [false], "effect publication blocks callback frame reentry")
			break
		else:
			suite.assert_true(authority.can_publish_effects(effect.ticket), "warning effect batch seals publication")
			suite.assert_true(actor.publish_launch_frame(prepared.ticket) and authority.publish_effects(effect.ticket), "warning frame publishes")
			actor.discard_launch_transaction_snapshot(actor_checkpoint)
			health.discard_transaction_snapshot(player_checkpoint)
	suite.assert_true(did_hit, "seeded native Sentinel executes real scheduled hit")
	EventBus.hit_confirmed.disconnect(observed)
	EventBus.hit_confirmed.disconnect(reentrant)
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_registry_cas_and_missed_geometry(implementation: Script) -> void:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(-100, 100)
	var health := player.get_node("HealthComponent")
	health.current_hp = 100.0
	var actor := ActorScene.instantiate()
	add_child(actor)
	await get_tree().process_frame
	var identity := Actions.identity()
	identity["seed"] = 42
	actor.configure_launch_definition(Definition.definition(), identity)
	actor.global_position = Vector2(100, 100)
	var registry: RefCounted = Registry.new()
	var authority: RefCounted = implementation.new()
	authority.configure("run-p15", 0)
	var checked_stale := false
	var checked_extension := false
	var checked_miss := false
	for frame: int in range(1, 121):
		var checkpoint: Dictionary = actor.launch_transaction_snapshot()
		var prepared: Dictionary = actor.prepare_launch_frame(frame, Actions.context(frame))
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": {"hostile:test-a": actor}, "targets": {"player:1": player}}
		var effect: Dictionary = authority.prepare_effects([{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}], context)
		suite.assert_true(effect.ok, "missed geometry scenario prepares sealed native batch")
		if not effect.ok:
			actor.rollback_launch_frame(prepared.ticket)
			actor.restore_launch_transaction_snapshot(checkpoint)
			break
		if not checked_stale and not prepared.batch.threat_facts.is_empty():
			checked_stale = true
			var before: Array = registry.snapshot()
			registry.register_fact(effect.ticket.registry_after[0])
			suite.assert_true(not authority.can_commit(effect.ticket), "registry mutation after preflight rejects atomic commit")
			suite.assert_true(authority.rollback(effect.ticket), "stale registry compensates staged native batch")
			suite.assert_equal(registry.snapshot(), before, "stale registry restores exact preflight snapshot")
			actor.rollback_launch_frame(prepared.ticket)
			actor.restore_launch_transaction_snapshot(checkpoint)
			checkpoint = actor.launch_transaction_snapshot()
			prepared = actor.prepare_launch_frame(frame, Actions.context(frame))
			effect = authority.prepare_effects([{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}], context)
		if not checked_extension and not prepared.batch.threat_extensions.is_empty():
			checked_extension = true
			var before: Array = registry.snapshot()
			suite.assert_true(actor.commit_launch_frame(prepared.ticket) and authority.commit(effect.ticket).ok, "Stop extends real native threat expiry transactionally")
			suite.assert_equal(int(registry.snapshot()[0].active_through_frame), int(before[0].active_through_frame) + 1, "Stop changes expiry by exactly one accepted frame")
			authority.rollback(effect.ticket)
			actor.rollback_launch_frame(prepared.ticket)
			actor.restore_launch_transaction_snapshot(checkpoint)
			suite.assert_equal(registry.snapshot(), before, "Stop rejection restores threat expiry and claim geometry")
			checkpoint = actor.launch_transaction_snapshot()
			prepared = actor.prepare_launch_frame(frame, Actions.context(frame))
			effect = authority.prepare_effects([{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}], context)
		suite.assert_true(actor.commit_launch_frame(prepared.ticket) and authority.commit(effect.ticket).ok, "native miss and pause frames commit")
		suite.assert_true(authority.can_publish(effect.ticket) and actor.publish_launch_frame(prepared.ticket) and authority.publish(effect.ticket), "native miss and pause publications seal")
		actor.discard_launch_transaction_snapshot(checkpoint)
		if not prepared.batch.threat_facts.is_empty():
			actor.apply_time_stop_source(&"stop:authority", 2.0 / 60.0)
		if not prepared.batch.hit_facts.is_empty():
			checked_miss = true
			suite.assert_equal(health.current_hp, 100.0, "registered frozen geometry misses real displaced Player")
			break
	suite.assert_true(checked_stale and checked_extension and checked_miss, "native scenario reaches stale registry, paused expiry, and missed hit gates")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_moving_actor_burn(implementation: Script) -> void:
	var actor := ActorScene.instantiate()
	add_child(actor)
	await get_tree().process_frame
	var identity := Actions.identity()
	identity["seed"] = 42
	suite.assert_true(actor.configure_launch_definition(Definition.definition(), identity).ok, "moving burn target installs native runtime")
	actor.global_position = Vector2(100, 100)
	var expired_source := Node2D.new()
	add_child(expired_source)
	suite.assert_true(actor.apply_elemental_status(&"burn", &"staff:burn", 2, 30, 7.0, 1, -1.0, expired_source, expired_source), "burn retains typed source ownership")
	expired_source.free()
	var health := actor.get_node("HealthComponent")
	var checkpoint: Dictionary = actor.launch_transaction_snapshot()
	var observations := Actions.context(1)
	observations.target_position = {"x": 200.0, "y": 100.0}
	var prepared: Dictionary = actor.prepare_launch_frame(1, observations)
	suite.assert_true(prepared.ok and prepared.batch.status_tick_requests.size() == 1, "retired burn source still schedules one native tick")
	var registry: RefCounted = Registry.new()
	var authority: RefCounted = implementation.new()
	authority.configure("run-p15", 0)
	var context := {"run_id": "run-p15", "runtime_frame": 1, "threat_registry": registry, "actors": {"hostile:test-a": actor}, "targets": {"hostile:test-a": actor}}
	var effect: Dictionary = authority.prepare_effects([{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}], context)
	suite.assert_true(effect.ok, "native burn preflight accepts expired source handles")
	if effect.ok:
		suite.assert_true(authority.can_commit(effect.ticket), "burn preflight accepts frame-start actor transform")
		suite.assert_true(actor.commit_launch_frame(prepared.ticket), "burn target commits deterministic pursuit")
		suite.assert_true(actor.global_position.x > 100.0, "native burn target really moves during accepted frame")
		var committed: Dictionary = authority.commit(effect.ticket)
		suite.assert_true(committed.ok, "burn effect accepts sealed actor displacement after native commit")
		if committed.ok:
			suite.assert_equal(health.current_hp, 73.0, "retired source burn applies exactly seven real Health damage")
		suite.assert_true(authority.rollback(effect.ticket), "burn authority compensates source claims and signal ownership")
		suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "moving burn actor compensates prepared state")
	else:
		actor.rollback_launch_frame(prepared.ticket)
	suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "burn frame owner restores status clock and Health ledger")
	suite.assert_equal(health.current_hp, 80.0, "burn rejection or rollback restores HP")
	suite.assert_equal(actor.global_position, Vector2(100, 100), "burn rollback restores exact frame-start transform")
	suite.assert_equal(actor.elemental_status_runtime.transaction_snapshot().entries.values()[0].elapsed_frames, 0, "burn rollback restores tick schedule")
	actor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
