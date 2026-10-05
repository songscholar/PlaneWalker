extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Fixture := preload("res://tests/support/p15_action_fixtures.gd")
const Scene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Player := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var actor := _actor()
	var health: Node = actor.get_node("HealthComponent")
	var heals: Array = []
	health.healed.connect(func(amount: float, hp: float): heals.append([amount, hp]))
	health.take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:regeneration", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 100.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:bow"], "can_crit": false}))
	for frame: int in range(1, 120):
		_tick(actor, frame)
	suite.assert_close(health.current_hp, 60.0, "native regeneration never runs before all120 accepted frames")
	var before: Dictionary = actor.launch_transaction_snapshot()
	var effects: RefCounted = actor.get_meta("fixture_effects")
	var signal_ticket: Dictionary = health.begin_frame_signal_transaction(120)
	var prepared: Dictionary = actor.prepare_launch_frame(120, _context(actor, 120))
	var effect: Dictionary = _prepare_effect(actor, prepared, 120)
	suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "actual native regeneration candidate commits at120")
	suite.assert_close(health.current_hp, 64.8, "actual elite Health heals exactlythreepercentof160maxHP")
	suite.assert_equal(heals, [], "candidate heal observation stays unpublished")
	suite.assert_true(effects.rollback_effects(effect.ticket) and health.rollback_frame_signal_transaction(signal_ticket) and actor.restore_launch_transaction_snapshot(before), "rejected healing frame restores actual Health and spending clock")
	suite.assert_close(health.current_hp, 60.0, "rejected regeneration cannot mint Health")
	if not actor.has_method("launch_affix_runtime_snapshot"):
		suite.assert_true(false, "regeneration needs authoritative bounded affix clock and spending state")
		actor.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	_tick(actor, 120)
	suite.assert_equal(heals.size(), 1, "retried accepted regeneration publishes one authentic heal")
	if heals.size() == 1:
		suite.assert_close(float(heals[0][0]), 4.8, "accepted actual Health observation has authored regeneration amount")
		suite.assert_close(float(heals[0][1]), 64.8, "accepted actual Health observation carries post-heal Health")
	var cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(actor.native_cold_snapshot(func(_source: Node): return {})).json).replay
	var twin := _actor()
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "typed cold rebuild retains actual native healing expenditure")
	suite.assert_equal(twin.launch_affix_runtime_snapshot(), actor.launch_affix_runtime_snapshot(), "cold regeneration clock and bounded spend are exact")
	await _physical_roundtrip(actor, 2)
	var forged := cold.duplicate(true)
	forged.actor.affix_runtime.regeneration.healed_total = 1000.0
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "forged regeneration above encounter cap refuses")
	forged = cold.duplicate(true)
	forged.actor.affix_runtime.regeneration.elapsed_frames = 1
	forged.actor.affix_runtime.regeneration.last_heal_frame = 1
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "forged regeneration cannot heal before its authored120frame boundary")
	forged = cold.duplicate(true)
	forged.actor.affix_runtime.terminal = true
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "affix terminal and native species terminal must agree")
	for frame: int in range(121, 180):
		_tick(actor, frame)
	var heavy := Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:regeneration", "hostile_source_id": "player:1", "attack_generation": 3, "action_token": 3, "amount": 1.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["attack:heavy"], "can_crit": false})
	health.take_damage(heavy)
	for frame: int in range(180, 300):
		_tick(actor, frame)
	suite.assert_close(health.current_hp, 63.8, "authentic heavy hit interrupts regeneration for120 accepted frames")
	for frame: int in range(300, 1501):
		_tick(actor, frame)
	suite.assert_close(actor.launch_affix_runtime_snapshot().regeneration.healed_total, 48.0, "encounter healing expenditure stops at thirtypercentofmaxHP")
	suite.assert_close(health.current_hp, 107.0, "native regeneration cap cannot add Health beyond48total")
	var capped: Dictionary = actor.launch_affix_runtime_snapshot()
	for frame: int in range(1501, 1621):
		_tick(actor, frame)
	suite.assert_close(actor.launch_affix_runtime_snapshot().regeneration.healed_total, capped.regeneration.healed_total, "further accepted clocks cannot replenish consumed encounter budget")
	await _physical_roundtrip(actor, 2)
	actor.queue_free()
	twin.queue_free()
	await get_tree().process_frame
	await _test_in_frame_heavy()
	await _test_shared_healing()
	await _test_whole_player_frame()
	await _test_legacy_and_pause()
	suite.finish(get_tree())


func _actor(revision: int = 2) -> Node2D:
	var actor: Node2D = Scene.instantiate()
	add_child(actor)
	suite.assert_true(actor.configure_launch_affixes([Content.affix("regenerating")], 1, revision).ok, "canonical regeneration affix configures")
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := Fixture.identity()
	identity.hostile_source_id = "hostile:regeneration"
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), identity).ok, "actual native regenerating elite configures")
	actor.global_position = Vector2(100, 100)
	var payloads := Node2D.new()
	actor.add_child(payloads)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(payloads)
	actor.set_meta("fixture_effects", effects)
	actor.set_meta("fixture_registry", Registry.new())
	return actor


func _context(actor: Node2D, frame: int) -> Dictionary:
	var context := Fixture.context(frame)
	context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
	context.target_position = {"x": actor.global_position.x + 500.0, "y": actor.global_position.y}
	return context


func _tick(actor: Node2D, frame: int) -> void:
	var health: Node = actor.get_node("HealthComponent")
	var health_ticket: Dictionary = health.begin_frame_signal_transaction(frame)
	var prepared: Dictionary = actor.prepare_launch_frame(frame, _context(actor, frame))
	var effect: Dictionary = _prepare_effect(actor, prepared, frame)
	var effects: RefCounted = actor.get_meta("fixture_effects")
	suite.assert_true(not health_ticket.is_empty() and prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "native regeneration accepts sealed frame %d: %s" % [frame, str(prepared.get("context", {}))])
	if not prepared.ok:
		return
	var publication: Dictionary = health.prepare_frame_signal_publication(health_ticket)
	suite.assert_true(not publication.is_empty() and health.finalize_frame_signal_publication(publication) and actor.publish_launch_frame(prepared.ticket) and effects.publish_effects(effect.ticket), "native heal commits through actual Health publication boundary")
	health.publish_prepared_frame_signals()


func _prepare_effect(actor: Node2D, prepared: Dictionary, frame: int) -> Dictionary:
	if not prepared.ok:
		return {"ok": false}
	var effects: RefCounted = actor.get_meta("fixture_effects")
	return effects.prepare_effects([{"hostile_source_id": str(actor.hostile_source_id), "batch": prepared.batch}], {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": actor.get_meta("fixture_registry"), "actors": {str(actor.hostile_source_id): actor}, "targets": {}})


func _hit(actor: Node2D, amount: float, generation: int, heavy: bool = false) -> void:
	actor.get_node("HealthComponent").take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:regeneration", "hostile_source_id": "player:1", "attack_generation": generation, "action_token": generation, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["attack:heavy"] if heavy else ["weapon:bow"], "can_crit": false}))


func _test_in_frame_heavy() -> void:
	var actor := _actor()
	var health: Node = actor.get_node("HealthComponent")
	_hit(actor, 100.0, 1)
	for frame: int in range(1, 120):
		_tick(actor, frame)
	var before: Dictionary = actor.launch_transaction_snapshot()
	var effects: RefCounted = actor.get_meta("fixture_effects")
	var health_ticket: Dictionary = health.begin_frame_signal_transaction(120)
	_hit(actor, 1.0, 2, true)
	var prepared: Dictionary = actor.prepare_launch_frame(120, _context(actor, 120))
	var effect: Dictionary = _prepare_effect(actor, prepared, 120)
	suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "authentic in-frame heavyhit commits before sameframe regeneration preview")
	suite.assert_close(health.current_hp, 59.0, "sameframe authenticated heavyhit interrupts the scheduled regeneration")
	suite.assert_true(effects.rollback_effects(effect.ticket) and health.rollback_frame_signal_transaction(health_ticket) and actor.restore_launch_transaction_snapshot(before), "late rejection restores in-flight heavy damage and regeneration interruption together")
	health_ticket = health.begin_frame_signal_transaction(120)
	_hit(actor, 1.0, 2, true)
	prepared = actor.prepare_launch_frame(120, _context(actor, 120))
	effect = _prepare_effect(actor, prepared, 120)
	suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "sameframe heavyhit retry reuses authentic damage identity after rollback")
	var publication: Dictionary = health.prepare_frame_signal_publication(health_ticket)
	suite.assert_true(health.finalize_frame_signal_publication(publication) and actor.publish_launch_frame(prepared.ticket) and effects.publish_effects(effect.ticket), "sameframe heavyhit seals actual native Health transaction")
	health.publish_prepared_frame_signals()
	for frame: int in range(121, 241):
		_tick(actor, frame)
	suite.assert_close(health.current_hp, 59.0, "all120frames after in-flight heavyhit remain regeneration-interrupted")
	for frame: int in range(241, 361):
		_tick(actor, frame)
	suite.assert_close(health.current_hp, 63.8, "first later authored regeneration boundary resumes within its encounter cap")
	actor.queue_free()
	await get_tree().process_frame


func _test_whole_player_frame() -> void:
	var actor := _actor()
	var health: Node = actor.get_node("HealthComponent")
	_hit(actor, 100.0, 1)
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(600.0, 100.0)
	player.health.acquire_invulnerability_source(&"regeneration_fixture")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects) and player.configure_hostile_frame_participant(bridge), "actual native Player binds authoritative elite regeneration participant")
	var heals: Array = []
	health.healed.connect(func(amount: float, hp: float): heals.append([amount, hp]))
	for _step: int in range(119):
		suite.assert_true(player.advance_action_frame(), "actual Player frame advances native elite regeneration")
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var player_before: Dictionary = player.full_player_replay_snapshot()
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not player.advance_action_frame(), "actual late World fault rejects native regeneration frame120")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "wholeframe rejection preserves Health/spending/claims/speciesclock")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "wholeframe regeneration rejection preserves complete native Player")
	suite.assert_equal(heals, [], "late World rejection publishes no native healing observation")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(), "actual Player retries native regeneration at sameacceptedframe")
	suite.assert_close(health.current_hp, 64.8, "native accepted Player frame reaches actual healed elite Health")
	suite.assert_equal(heals.size(), 1, "actual native Player frame publishes healing once after complete seal")
	player.configure_hostile_frame_participant(null)
	actor.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _test_shared_healing() -> void:
	for missing_hp: float in [1.0, 7.0]:
		var recipient := _actor()
		for frame: int in range(1, 91):
			_tick(recipient, frame)
		var watcher: Node2D = Scene.instantiate()
		add_child(watcher)
		var parser := Definition.new()
		parser.configure(Content.enemy("rift_watcher"))
		var identity := Fixture.identity()
		identity.hostile_source_id = "hostile:watcher"
		identity.runtime_frame = 90
		identity.seed = 42
		suite.assert_true(watcher.configure_launch_definition(parser.runtime_projection(), identity).ok, "actual support joins the same native accepted clock")
		watcher.global_position = recipient.global_position + Vector2(20.0, 0.0)
		var support_context := _context(watcher, 90)
		support_context.target_position = {"x": recipient.global_position.x, "y": recipient.global_position.y}
		suite.assert_true(watcher.get("_launch_runtime").request_action("rift_watcher.nourish", support_context).ok, "authentic support warning schedules healing at regeneration boundary")
		var actors := {"hostile:regeneration": recipient, "hostile:watcher": watcher}
		for frame: int in range(91, 120):
			_shared_healing_step(recipient, actors, frame)
		_hit(recipient, missing_hp, 1)
		var before: Dictionary = recipient.launch_transaction_snapshot()
		_shared_healing_step(recipient, actors, 120, true)
		suite.assert_equal(recipient.launch_transaction_snapshot(), before, "late rejection refunds competing support and regeneration spending exactly")
		_shared_healing_step(recipient, actors, 120)
		var actual_regeneration := maxf(0.0, missing_hp - 5.0)
		suite.assert_close(recipient.get_node("HealthComponent").current_hp, 160.0, "authentic shared healing restores only native missing Health")
		suite.assert_close(recipient.launch_affix_runtime_snapshot().regeneration.healed_total, actual_regeneration, "regeneration budget charges actual gain after sameframe support healing")
		suite.assert_equal(recipient.launch_affix_runtime_snapshot().regeneration.last_heal_frame, 120 if actual_regeneration > 0.0 else -1, "zeroactual regeneration cannot forge a lasthealed clock")
		suite.assert_true(not recipient.settle_launch_affix_heal(120, 4.8, 0.0), "published native frame refuses stale healing expenditure refund")
		recipient.queue_free()
		watcher.queue_free()
		await get_tree().process_frame


func _shared_healing_step(recipient: Node2D, actors: Dictionary, frame: int, rollback: bool = false) -> void:
	var effects: RefCounted = recipient.get_meta("fixture_effects")
	var pairs: Array[Dictionary] = []
	var batches: Array[Dictionary] = []
	for source: String in actors:
		var actor: Node2D = actors[source]
		var before: Dictionary = actor.launch_transaction_snapshot()
		var prepared: Dictionary = actor.prepare_launch_frame(frame, _context(actor, frame))
		suite.assert_true(prepared.ok, "simultaneous support/affix actors prepare a sealed native frame %s/%d: %s" % [source, frame, str(prepared.get("context", {}))])
		if not prepared.ok:
			for pair: Dictionary in pairs:
				pair.actor.rollback_launch_frame(pair.ticket)
			return
		pairs.append({"actor": actor, "ticket": prepared.ticket, "before": before})
		batches.append({"hostile_source_id": source, "batch": prepared.batch})
	var effect: Dictionary = effects.prepare_effects(batches, {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": recipient.get_meta("fixture_registry"), "actors": actors, "targets": {}})
	suite.assert_true(effect.ok, "shared support and native regeneration prepare actual Health sink")
	for pair: Dictionary in pairs:
		suite.assert_true(pair.actor.commit_launch_frame(pair.ticket), "shared support/affix candidate actor commits")
	suite.assert_true(effects.commit_effects(effect.ticket).ok, "shared healing uses authentic bounded native Health requests")
	if rollback:
		suite.assert_true(effects.rollback_effects(effect.ticket), "shared actual Health and semantic ledgers compensate on late rejection")
		for pair: Dictionary in pairs:
			suite.assert_true(pair.actor.rollback_launch_frame(pair.ticket) and pair.actor.restore_launch_transaction_snapshot(pair.before), "shared affix and support candidate clocks/Health compensate on rejection")
		return
	for pair: Dictionary in pairs:
		suite.assert_true(pair.actor.publish_launch_frame(pair.ticket), "shared candidate actor publishes after native effects seal")
	suite.assert_true(effects.publish_effects(effect.ticket), "shared support and regeneration release actual Health observations")


func _test_legacy_and_pause() -> void:
	var legacy := _actor(1)
	_hit(legacy, 100.0, 1)
	for frame: int in range(1, 121):
		_tick(legacy, frame)
	suite.assert_close(legacy.get_node("HealthComponent").current_hp, 60.0, "closed staticV1 regenerating metadata retains original no-heal behavior")
	var cold: Dictionary = legacy.native_cold_snapshot(func(_source: Node): return {})
	var twin := _actor(1)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "closed staticV1 compiler restores its exact historical signature")
	await _physical_roundtrip(legacy, 1)
	var actor := _actor()
	suite.assert_true(not actor.can_restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "old compiler cannot silently acquire a new native regeneration clock")
	_hit(actor, 100.0, 1)
	actor.apply_time_stop_source(&"stop:regeneration", 30.0 / 60.0)
	for frame: int in range(1, 31):
		_tick(actor, frame)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().regeneration.elapsed_frames, 0, "source-owned regeneration pauses throughout actual Stop")
	for frame: int in range(31, 151):
		_tick(actor, frame)
	suite.assert_close(actor.get_node("HealthComponent").current_hp, 64.8, "paused regeneration resumes after all120unpaused authoredframes")
	_hit(actor, 1000.0, 3)
	suite.assert_true(actor.launch_affix_runtime_snapshot().terminal and actor.launch_runtime_snapshot().runtime.terminal, "published actual final death closes affix and species clocks together")
	legacy.queue_free()
	twin.queue_free()
	if is_instance_valid(actor):
		actor.queue_free()
	await get_tree().process_frame


func _physical_roundtrip(actor: Node2D, revision: int) -> void:
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var root := Paths.resolve_default("user://elite-regeneration", "elite-regeneration")
	var binding := ContentSnapshot.snapshot(registry)
	var storage := Save.new()
	suite.assert_true(storage.configure(root, "test-elite-regeneration", binding).ok, "physical elite checkpoint uses actual authenticated content binding")
	var state := {"actor": actor.native_cold_snapshot(func(_source: Node): return {}), "effects": actor.get_meta("fixture_effects").launch_transaction_snapshot(), "threats": actor.get_meta("fixture_registry").snapshot()}
	var encoded := Replay.encode_replay_json(state)
	var id := "elite_regen_v%d" % revision
	suite.assert_true(encoded.ok and storage.save_profile(id, "base", {"native_elite_actor_codec": encoded.json}).ok, "actual physical SaveService retains typed elite affix aggregate")
	var reopened := Save.new()
	reopened.configure(root, "test-elite-regeneration", binding)
	var primary: Variant = reopened.inspect_profile(id, "base")
	suite.assert_true(primary.ok, "fresh SaveService authenticates the actual primary elite checkpoint")
	if not primary.ok:
		return
	var decoded := Replay.decode_replay_json(primary.payload.payload.native_elite_actor_codec)
	suite.assert_true(decoded.ok and decoded.replay == state, "physical serialization preserves actual affix clocks/Health/claims without JSON type loss")
	var replicas: Array = []
	for _branch: int in range(2):
		var restored := _actor(revision)
		suite.assert_true(restored.restore_native_cold_snapshot(decoded.replay.actor, func(_source: Node): return null), "new native Actor cold restores physical affix checkpoint")
		suite.assert_true(restored.get_meta("fixture_effects").restore_launch_transaction_snapshot(decoded.replay.effects), "physical affix branch restores native effect claim ledger")
		for fact: Dictionary in decoded.replay.threats:
			suite.assert_true(restored.get_meta("fixture_registry").register_fact(fact), "physical affix branch restores original threat registry")
		replicas.append(restored)
	var frame := int(state.actor.actor.runtime.runtime_frame) + 1
	for restored: Node2D in replicas:
		_tick(restored, frame)
	suite.assert_equal(replicas[0].native_cold_snapshot(func(_source: Node): return {}), replicas[1].native_cold_snapshot(func(_source: Node): return {}), "fresh physical native branches continue exact affix/Health/species state")
	for restored: Node2D in replicas:
		restored.queue_free()
	await get_tree().process_frame
