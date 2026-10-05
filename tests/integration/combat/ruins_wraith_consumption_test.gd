extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_ruins_wraith.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Definitions := preload("res://tests/unit/enemies/ruins_enemy_mechanisms_test.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var actor := ActorScene.instantiate()
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var identity := Actions.identity()
	identity["seed"] = 42
	suite.assert_true(actor.configure_launch_definition(Definitions.wraith_definition(), identity).ok, "real authored Wraith configures")
	var corrupted: Dictionary = actor.launch_runtime_snapshot().runtime.duplicate(true)
	corrupted.mechanism_state.detonation_consumed = true
	suite.assert_true(not (actor.get("_launch_runtime") as RefCounted).can_restore_snapshot(corrupted), "consumed mechanism cannot restore as a live Wraith without terminal domain")
	suite.assert_true(actor.has_method("prepared_launch_frame_consumes_actor"), "native Wraith seals terminal consumption before effects commit")
	if actor.has_method("prepared_launch_frame_consumes_actor"):
		await _test_sealed_consumption_and_retry(actor)
		await _test_player_bridge_consumption()
	actor.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _test_sealed_consumption_and_retry(actor: Node2D) -> void:
	var player := PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(120, 100)
	actor.global_position = Vector2(100, 100)
	var player_health := player.get_node("HealthComponent")
	var health := actor.get_node("HealthComponent")
	var registry: RefCounted = Registry.new()
	var effects: RefCounted = Effects.new()
	effects.configure("run-p15")
	var receipts: Array = []
	actor.hostile_final_death.connect(func(source_id: StringName, receipt_id: String): receipts.append([source_id, receipt_id]))
	var hits: Array = []
	var observed := func(_info: RefCounted, target: Node, amount: float):
		if target == player:
			hits.append(amount)
	EventBus.hit_confirmed.connect(observed)
	var consumed := false
	for frame: int in range(1, 150):
		var checkpoint: Dictionary = actor.launch_transaction_snapshot()
		var player_checkpoint: Dictionary = player_health.transaction_snapshot()
		var prepared: Dictionary = actor.prepare_launch_frame(frame, Actions.context(frame))
		suite.assert_true(prepared.ok, "Wraith prepares real fixed-frame warning, explosion, and consumption")
		if not prepared.ok:
			actor.restore_launch_transaction_snapshot(checkpoint)
			player_health.discard_transaction_snapshot(player_checkpoint)
			break
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": {"hostile:test-a": actor}, "targets": {"player:1": player}}
		var batches := [{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}]
		var has_consumption: bool = not prepared.batch.mechanism_requests.is_empty()
		if has_consumption:
			suite.assert_true(actor.prepared_launch_frame_consumes_actor(), "actor exposes authenticated sealed terminal intent")
			suite.assert_equal(receipts, [], "terminal intent publishes no premature final-death receipt")
			var forged := batches.duplicate(true)
			forged[0].batch.mechanism_requests[0].attack_generation += 1
			suite.assert_true(not effects.prepare_effects(forged, context).ok, "changed consumption lineage rejects before Health mutation")
		var effect: Dictionary = effects.prepare_effects(batches, context)
		suite.assert_true(effect.ok, "native effect authority validates actual sealed Wraith batch")
		if not effect.ok:
			actor.rollback_launch_frame(prepared.ticket)
			actor.restore_launch_transaction_snapshot(checkpoint)
			player_health.discard_transaction_snapshot(player_checkpoint)
			break
		suite.assert_true(actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "native Wraith frame commits real domain and Health")
		if has_consumption:
			suite.assert_true(health.dead and actor.launch_runtime_snapshot().runtime.terminal, "self-consumption commits dead Health and terminal domain together")
			suite.assert_equal(receipts, [], "self-consumption death stays buffered until publication")
			var terminal_candidate: Dictionary = actor.launch_runtime_snapshot().runtime.duplicate(true)
			suite.assert_true(effects.rollback_effects(effect.ticket) and actor.rollback_launch_frame(prepared.ticket), "rejected final frame discards effects and terminal candidate")
			suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "frame-start Health and actor restore after consumed candidate")
			suite.assert_true(player_health.restore_transaction_snapshot(player_checkpoint), "same frame restores Player frozen damage ledger")
			suite.assert_true(health.is_alive() and not actor.launch_runtime_snapshot().runtime.terminal, "consumption compensation restores counted live Wraith")
			suite.assert_equal(receipts, [], "consumption compensation emits zero defeat receipts")
			checkpoint = actor.launch_transaction_snapshot()
			player_checkpoint = player_health.transaction_snapshot()
			prepared = actor.prepare_launch_frame(frame, Actions.context(frame))
			effect = effects.prepare_effects([{"hostile_source_id": "hostile:test-a", "batch": prepared.batch}], context)
			suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "exact-frame retry accepts one real consumption")
			suite.assert_equal(actor.launch_runtime_snapshot().runtime, terminal_candidate, "retry reconstructs identical terminal intent and lineage")
			var terminal_checkpoint: Dictionary = actor.launch_transaction_snapshot()
			var combined := terminal_checkpoint.duplicate(true)
			combined.health = checkpoint.health.duplicate(true)
			suite.assert_true(not actor.can_restore_launch_transaction_snapshot(combined), "consumed terminal actor cannot restore with an earlier live Health checkpoint")
			suite.assert_true(actor.discard_launch_transaction_snapshot(terminal_checkpoint), "actual consumed terminal Health checkpoint remains valid")
		suite.assert_true(actor.publish_launch_frame(prepared.ticket) and effects.publish_effect_observations(effect.ticket), "sealed Wraith frame publishes actual observations once")
		actor.discard_launch_transaction_snapshot(checkpoint)
		player_health.discard_transaction_snapshot(player_checkpoint)
		if has_consumption:
			consumed = true
			suite.assert_equal(receipts.size(), 1, "one authentic self-consumption emits one final death receipt")
			var expected := "hostile_defeat:%s" % ("run-p15|hostile:test-a").sha256_text().substr(0, 40)
			suite.assert_equal(receipts[0], [&"hostile:test-a", expected], "self-consumption retains canonical stable native death lineage")
			suite.assert_true(registry.snapshot().is_empty(), "consumption retires all detonation threats")
			suite.assert_equal(hits, [20.0], "self-consumption creates no fabricated attack observation")
			suite.assert_true(not actor.prepare_launch_frame(frame + 1, Actions.context(frame + 1)).ok, "terminal Wraith cannot explode again")
			suite.assert_true(not effects.publish_effect_observations(effect.ticket), "published consumption cannot replay its death observation")
			break
	suite.assert_true(consumed, "real authored Wraith reaches terminal self-consumption")
	EventBus.hit_confirmed.disconnect(observed)
	player.queue_free()
	await get_tree().process_frame


func _test_player_bridge_consumption() -> void:
	var player := PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(120, 100)
	var actor := ActorScene.instantiate()
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var identity := Actions.identity()
	identity["seed"] = 42
	actor.configure_launch_definition(Definitions.wraith_definition(), identity)
	actor.global_position = Vector2(100, 100)
	var health := actor.get_node("HealthComponent")
	var registry: RefCounted = Registry.new()
	var effects: RefCounted = Effects.new()
	effects.configure("run-p15")
	var bridge: RefCounted = Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects) and player.configure_hostile_frame_participant(bridge), "real Player binds Wraith and effects through production bridge")
	var receipts: Array = []
	actor.hostile_final_death.connect(func(source_id: StringName, receipt_id: String): receipts.append([source_id, receipt_id]))
	var guard := 120
	while actor.launch_runtime_snapshot().runtime.action.phase == "IDLE" and guard > 0:
		suite.assert_true(player.advance_action_frame(), "Player frame selects Wraith warning")
		guard -= 1
	if guard <= 0:
		suite.assert_true(false, "Wraith action begins within authored startup bound")
	else:
		var action: Dictionary = Definitions.wraith_definition().actions[0]
		var consumption_frame: int = actor.launch_runtime_snapshot().runtime.action.commit_frame + action.warning_frames + action.active_frames
		for _step: int in range(action.warning_frames + action.active_frames):
			if int(player.get("_runtime_frame")) >= consumption_frame - 1:
				break
			var advanced: bool = player.advance_action_frame()
			suite.assert_true(advanced, "real Player completes warned Wraith explosion")
			if not advanced:
				break
		suite.assert_equal(int(player.get("_runtime_frame")), consumption_frame - 1, "native consumption reaches the exact bounded terminal frame")
		var before: Dictionary = actor.launch_runtime_snapshot()
		var before_registry: Array = registry.snapshot()
		player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
		suite.assert_true(not suite.expect_rejected_player_frame(player), "late World rejection compensates staged self-consumption")
		suite.assert_equal(actor.launch_runtime_snapshot(), before, "late World rejection restores exact active Wraith and live Health")
		suite.assert_equal(registry.snapshot(), before_registry, "late World rejection restores detonation threat ownership")
		suite.assert_equal(receipts, [], "late World rejection publishes no death receipt")
		player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
		suite.assert_true(player.advance_action_frame(), "production bridge retries Wraith consumption at the same frame")
		suite.assert_true(health.dead and actor.launch_runtime_snapshot().runtime.terminal, "accepted Player frame commits terminal Wraith Health")
		suite.assert_equal(receipts.size(), 1, "production bridge publishes one canonical defeat receipt")
		suite.assert_true((bridge.get("_actors") as Dictionary).is_empty(), "terminal native roster retires before presentation body removal")
		suite.assert_true(player.advance_action_frame(), "next Player frame advances with consumed Wraith retired")
		suite.assert_equal(receipts.size(), 1, "next frame cannot repeat Wraith settlement lineage")
	player.configure_hostile_frame_participant(null)
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame
