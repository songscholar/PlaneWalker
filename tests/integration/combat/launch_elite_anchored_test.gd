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
	await _test_displacement_and_admission()
	await _test_recovery_and_time()
	await _test_rejected_control_frame()
	await _test_whole_player_frame()
	await _test_cold_and_history()
	await _test_regeneration_combination()
	suite.finish(get_tree())


func _test_displacement_and_admission() -> void:
	var actor := _actor()
	actor.apply_knockback(Vector2(120, 0))
	suite.assert_equal(actor.get("_knockback_velocity"), Vector2.ZERO, "actual Anchored elite refuses weapon displacement")
	var state: Dictionary = actor.launch_affix_runtime_snapshot()
	suite.assert_true(state.has("anchored") and not state.get("anchored", {}).is_empty(), "actual Anchored elite owns authoritative poise and recovery state")
	_hit(actor, 1)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 1, "actual admitted launch damage records one control")
	_hit(actor, 1)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 1, "duplicate damage fact cannot mint control poise")
	_hit(actor, 2, {"action_token": 1})
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 1, "reused action token cannot mint a second control")
	_hit(actor, 3, {"source_generation": 2})
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 1, "stale source generation cannot admit control")
	_hit(actor, 4, {"control_effect": {"kind": "launch", "displacement_pixels": -1.0}})
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 1, "malformed negative launch displacement cannot admit control")
	_hit(actor, 5, {"amount": 0.0})
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 1, "zero actual damage cannot mint control poise")
	_hit(actor, 6, {"control_effect": {}})
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 1, "ordinary physical hit cannot mint launch poise")
	for generation: int in range(7, 10):
		_hit(actor, generation)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.poise, 80, "four admitted controls accumulate the authored eighty poise")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 0, "subthreshold controls cannot pause native actions")
	_hit(actor, 10)
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.poise, 0, "fifth admitted control spends the authored hundred poise")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 20, "fifth admitted control owns twenty recovery frames")
	actor.queue_free()
	await get_tree().process_frame


func _actor(native_revision: int = -1, regeneration: bool = false) -> Node2D:
	var actor: Node2D = Scene.instantiate()
	add_child(actor)
	var affixes: Array = [Content.affix("anchored")]
	if regeneration:
		affixes.append(Content.affix("regenerating"))
	var configured: Dictionary = actor.configure_launch_affixes(affixes, 3) if native_revision < 0 else actor.configure_launch_affixes(affixes, 3, native_revision)
	suite.assert_true(configured.ok, "canonical Anchored affix compiles before the real Actor")
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := Fixture.identity()
	identity.hostile_source_id = "anchored-test"
	identity.seed = 42
	actor.set_meta("encounter_spawn_id", &"anchored-test")
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), identity).ok, "canonical Anchored elite definition configures")
	actor.global_position = Vector2(100, 100)
	var payloads := Node2D.new()
	actor.add_child(payloads)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(payloads)
	actor.set_meta("fixture_effects", effects)
	actor.set_meta("fixture_registry", Registry.new())
	return actor


func _hit(actor: Node2D, generation: int, overrides: Dictionary = {}) -> void:
	var plan := {"run_id": "run-p15", "target_id": "anchored-test", "hostile_source_id": "player:1", "attack_generation": generation, "action_token": generation, "source_generation": generation, "amount": 1.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:gauntlets"], "can_crit": false, "control_effect": {"kind": "launch", "displacement_pixels": 48.0}}
	plan.merge(overrides, true)
	actor.get_node("HealthComponent").take_damage(Damage.from_plan(plan))


func _context(actor: Node2D, frame: int) -> Dictionary:
	var context := Fixture.context(frame)
	context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
	context.target_position = {"x": actor.global_position.x + 500.0, "y": actor.global_position.y}
	return context


func _prepare_effect(actor: Node2D, prepared: Dictionary, frame: int) -> Dictionary:
	if not prepared.ok:
		return {"ok": false}
	var effects: RefCounted = actor.get_meta("fixture_effects")
	return effects.prepare_effects([{"hostile_source_id": str(actor.hostile_source_id), "batch": prepared.batch}], {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": actor.get_meta("fixture_registry"), "actors": {str(actor.hostile_source_id): actor}, "targets": {}})


func _tick(actor: Node2D, frame: int) -> void:
	var health: Node = actor.get_node("HealthComponent")
	var health_ticket: Dictionary = health.begin_frame_signal_transaction(frame)
	var prepared: Dictionary = actor.prepare_launch_frame(frame, _context(actor, frame))
	var effect: Dictionary = _prepare_effect(actor, prepared, frame)
	var effects: RefCounted = actor.get_meta("fixture_effects")
	suite.assert_true(not health_ticket.is_empty() and prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "native Anchored candidate accepts frame %d: %s" % [frame, str(prepared.get("context", {}))])
	if not prepared.ok or not effect.ok:
		return
	var publication: Dictionary = health.prepare_frame_signal_publication(health_ticket)
	suite.assert_true(not publication.is_empty() and health.finalize_frame_signal_publication(publication) and actor.publish_launch_frame(prepared.ticket) and effects.publish_effects(effect.ticket), "native Anchored frame publishes after actual Health and effect seal")
	health.publish_prepared_frame_signals()


func _test_recovery_and_time() -> void:
	var actor := _actor()
	var request_context := Fixture.context(0)
	suite.assert_true(actor.get("_launch_runtime").request_action("shattered_sentinel.shield_sweep", request_context).ok, "actual elite enters the authored shield warning")
	for fact: Dictionary in actor.native_cold_threat_facts():
		suite.assert_true(actor.get_meta("fixture_registry").register_fact(fact), "actual authored warning owns registered native threat geometry")
	for frame: int in range(1, 6):
		_tick(actor, frame)
	var action: Dictionary = actor.launch_runtime_snapshot().runtime.action
	for generation: int in range(1, 6):
		_hit(actor, generation)
	var position := actor.global_position
	actor.apply_time_stop_source(&"stop:anchor", 10.0 / 60.0)
	for frame: int in range(6, 16):
		_tick(actor, frame)
	suite.assert_true(actor.is_time_stopped(), "Anchored retains Stop through its final authored accepted frame")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 20, "actual Stop pauses Anchor recovery budget")
	suite.assert_equal(actor.global_position, position, "actual Stop and Anchor recovery pause physical Actor movement")
	for frame: int in range(16, 36):
		_tick(actor, frame)
	suite.assert_true(not actor.is_time_stopped(), "actual Stop releases while Anchor recovery continues")
	var paused_action: Dictionary = actor.launch_runtime_snapshot().runtime.action
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 0, "all twenty unpaused accepted frames spend Anchor recovery")
	suite.assert_equal(paused_action.phase, "WARNING", "threshold recovery preserves the actual in-flight warning phase")
	suite.assert_equal(paused_action.commit_frame, action.commit_frame, "Anchor recovery cannot recommit an existing warning")
	suite.assert_equal(paused_action.paused_frames, int(action.paused_frames) + 30, "Stop and Anchor each extend accepted warning lifetime once")
	var extended_geometry: Array = action.committed_geometry.duplicate(true)
	for fact: Dictionary in extended_geometry:
		fact.active_through_frame += 30
	suite.assert_equal(paused_action.committed_geometry, extended_geometry, "threshold recovery retains original warning geometry with the exact lifetime extension")
	suite.assert_equal(paused_action.geometry_generations, action.geometry_generations, "threshold recovery retains original damage ownership")
	_tick(actor, 36)
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.action.paused_frames, paused_action.paused_frames, "warning resumes on the first frame after recovery")
	var normal := _actor()
	var slowed := _actor()
	slowed.apply_time_rift(&"rift:anchor", 0.4)
	_tick(normal, 1)
	_tick(slowed, 1)
	suite.assert_true(slowed.is_time_rifted(), "Anchored retains actual Rift source ownership")
	suite.assert_close(slowed.global_position.distance_to(Vector2(100, 100)), normal.global_position.distance_to(Vector2(100, 100)) * 0.4, "actual Rift still slows Anchored native Actor motion")
	slowed.clear_time_rift(&"rift:anchor")
	suite.assert_true(not slowed.is_time_rifted(), "clearing Rift retains canonical source lifecycle")
	actor.queue_free()
	normal.queue_free()
	slowed.queue_free()
	await get_tree().process_frame


func _test_rejected_control_frame() -> void:
	var actor := _actor()
	for generation: int in range(1, 5):
		_hit(actor, generation)
	var before: Dictionary = actor.launch_transaction_snapshot()
	var health: Node = actor.get_node("HealthComponent")
	var effects: RefCounted = actor.get_meta("fixture_effects")
	var health_ticket: Dictionary = health.begin_frame_signal_transaction(1)
	_hit(actor, 5)
	suite.assert_true(actor.native_cold_snapshot(func(_source: Node): return {}).is_empty(), "in-flight future control admission cannot be exported as a cold checkpoint")
	var prepared: Dictionary = actor.prepare_launch_frame(1, _context(actor, 1))
	var effect: Dictionary = _prepare_effect(actor, prepared, 1)
	suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "authenticated in-frame threshold commits inside native candidate")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 19, "same-frame threshold uses one accepted unpaused recovery frame")
	suite.assert_true(effects.rollback_effects(effect.ticket) and health.rollback_frame_signal_transaction(health_ticket) and actor.restore_launch_transaction_snapshot(before), "late rejection compensates Health, poise, recovery and control claims")
	suite.assert_equal(actor.launch_transaction_snapshot(), before, "rejected threshold restores exact actual Actor transaction")
	health_ticket = health.begin_frame_signal_transaction(1)
	_hit(actor, 5)
	prepared = actor.prepare_launch_frame(1, _context(actor, 1))
	effect = _prepare_effect(actor, prepared, 1)
	suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "rejected threshold retries the original physical control identity")
	var publication: Dictionary = health.prepare_frame_signal_publication(health_ticket)
	suite.assert_true(health.finalize_frame_signal_publication(publication) and actor.publish_launch_frame(prepared.ticket) and effects.publish_effects(effect.ticket), "retried threshold seals actual Health publication")
	health.publish_prepared_frame_signals()
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 5, "retry admits exactly five controls after all participants seal")
	actor.queue_free()
	await get_tree().process_frame


func _test_whole_player_frame() -> void:
	var actor := _actor()
	for generation: int in range(1, 6):
		_hit(actor, generation)
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(600, 100)
	player.health.acquire_invulnerability_source(&"anchored_fixture")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects) and player.configure_hostile_frame_participant(bridge), "actual native Player owns Anchored hostile frame participation")
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var player_before: Dictionary = player.full_player_replay_snapshot()
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not suite.expect_rejected_player_frame(player), "actual late World failure rejects Anchor recovery candidate")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "whole-frame rejection preserves native Health, poise, recovery, claims and species clock")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "whole-frame Anchor rejection preserves complete native Player")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(), "actual native Player retries accepted Anchor recovery frame")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 19, "actual accepted Player frame spends recovery once")
	player.configure_hostile_frame_participant(null)
	actor.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _test_cold_and_history() -> void:
	var actor := _actor()
	for generation: int in range(1, 6):
		_hit(actor, generation)
	for frame: int in range(1, 8):
		_tick(actor, frame)
	var encoded: Dictionary = Replay.encode_replay_json(actor.native_cold_snapshot(func(_source: Node): return {}))
	var cold: Dictionary = Replay.decode_replay_json(encoded.json).replay
	var twin := _actor()
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "typed cold Actor restores exact live Anchor recovery")
	suite.assert_equal(twin.launch_affix_runtime_snapshot(), actor.launch_affix_runtime_snapshot(), "cold Anchor timeline and poise retain typed identity")
	for field: String in ["poise", "control_count", "last_threshold_elapsed_frame", "recovery_remaining_frames"]:
		var forged := cold.duplicate(true)
		forged.actor.affix_runtime.anchored[field] += 1
		suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "cold restore refuses forged Anchor %s" % field)
	var forged := cold.duplicate(true)
	forged.actor.affix_runtime.anchored.last_control_frame = int(forged.actor.affix_runtime.runtime_frame) + 1
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "accepted cold checkpoint refuses future control admission")
	forged = cold.duplicate(true)
	forged.actor.affix_runtime.anchored.elapsed_frames = int(forged.actor.affix_runtime.runtime_frame) + 1
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "cold restore refuses elapsed time beyond accepted frames")
	forged = cold.duplicate(true)
	forged.actor.affix_runtime.terminal = true
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "cold restore refuses divergent affix and native terminal state")
	await _physical_roundtrip(actor, 3)
	var legacy := _actor(2)
	legacy.apply_knockback(Vector2(120, 0))
	suite.assert_equal(legacy.get("_knockback_velocity"), Vector2(120, 0), "historical revision two retains metadata-only Anchor displacement")
	_hit(legacy, 1)
	suite.assert_true(not legacy.launch_affix_runtime_snapshot().has("anchored"), "historical revision two cannot acquire native Anchor poise")
	var historical: Dictionary = legacy.native_cold_snapshot(func(_source: Node): return {})
	var legacy_twin := _actor(2)
	suite.assert_true(legacy_twin.restore_native_cold_snapshot(historical, func(_binding: Dictionary): return null), "historical compiler restores its original closed Actor signature")
	suite.assert_true(not twin.can_restore_native_cold_snapshot(historical, func(_binding: Dictionary): return null), "historical metadata-only Anchor cannot silently migrate into current behavior")
	await _physical_roundtrip(legacy, 2)
	_hit(actor, 20, {"amount": 1000.0})
	suite.assert_true(actor.launch_affix_runtime_snapshot().terminal and actor.launch_runtime_snapshot().runtime.terminal, "published final death closes Anchor and native species clocks together")
	for target: Node2D in [actor, twin, legacy, legacy_twin]:
		if is_instance_valid(target):
			target.queue_free()
	await get_tree().process_frame


func _test_regeneration_combination() -> void:
	var actor := _actor(3, true)
	_hit(actor, 1, {"amount": 100.0, "control_effect": {}})
	for frame: int in range(1, 101):
		_tick(actor, frame)
	for generation: int in range(2, 7):
		_hit(actor, generation)
	for frame: int in range(101, 121):
		_tick(actor, frame)
	suite.assert_close(actor.get_node("HealthComponent").current_hp, 59.8, "revision three regeneration continues through Anchor action recovery")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().regeneration.elapsed_frames, 120, "Anchor cannot freeze a compatible regeneration expenditure clock")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 0, "compatible affixes spend the same twenty unpaused accepted recovery frames")
	actor.queue_free()
	await get_tree().process_frame


func _physical_roundtrip(actor: Node2D, revision: int) -> void:
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var root := Paths.resolve_default("user://elite-anchored", "elite-anchored")
	var binding := ContentSnapshot.snapshot(registry)
	var storage := Save.new()
	suite.assert_true(storage.configure(root, "test-elite-anchored", binding).ok, "physical Anchor checkpoint binds authenticated launch content")
	var state := {"actor": actor.native_cold_snapshot(func(_source: Node): return {}), "effects": actor.get_meta("fixture_effects").launch_transaction_snapshot(), "threats": actor.get_meta("fixture_registry").snapshot()}
	revision = int(state.actor.actor.affixes.native_revision)
	var encoded := Replay.encode_replay_json(state)
	var id := "elite_anchor_v%d" % revision
	suite.assert_true(encoded.ok and storage.save_profile(id, "base", {"native_elite_actor_codec": encoded.json}).ok, "actual SaveService retains typed native Anchor aggregate")
	var reopened := Save.new()
	reopened.configure(root, "test-elite-anchored", binding)
	var primary: Variant = reopened.inspect_profile(id, "base")
	suite.assert_true(primary.ok, "fresh SaveService authenticates physical native Anchor primary")
	if not primary.ok:
		return
	var decoded := Replay.decode_replay_json(primary.payload.payload.native_elite_actor_codec)
	suite.assert_true(decoded.ok and decoded.replay == state, "physical Anchor codec retains typed Health, poise, recovery and claims")
	var replicas: Array[Node2D] = []
	for _branch: int in range(2):
		var restored := _actor(revision)
		suite.assert_true(restored.restore_native_cold_snapshot(decoded.replay.actor, func(_source: Node): return null), "fresh Actor restores authenticated Anchor checkpoint")
		suite.assert_true(restored.get_meta("fixture_effects").restore_launch_transaction_snapshot(decoded.replay.effects), "fresh Anchor branch restores native effect claim ledger")
		for fact: Dictionary in decoded.replay.threats:
			suite.assert_true(restored.get_meta("fixture_registry").register_fact(fact), "fresh Anchor branch restores original physical threat ownership")
		replicas.append(restored)
	var start: int = int(state.actor.actor.runtime.runtime_frame) + 1
	for frame: int in range(start, start + 15):
		for restored: Node2D in replicas:
			_tick(restored, frame)
	suite.assert_equal(replicas[0].native_cold_snapshot(func(_source: Node): return {}), replicas[1].native_cold_snapshot(func(_source: Node): return {}), "physical fresh branches continue exact accepted Anchor and species state")
	for restored: Node2D in replicas:
		restored.queue_free()
	await get_tree().process_frame
