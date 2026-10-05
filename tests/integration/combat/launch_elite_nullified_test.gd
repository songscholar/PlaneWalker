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
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Player := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var actor := _actor()
	actor.apply_time_rift(&"rift:nullified", 0.10)
	suite.assert_close(actor.get("_launch_runtime").control_modifiers().movement_multiplier, 0.70, "native Nullified Rift retains slowdown at the authored 0.70 movement floor")
	actor.clear_time_rift(&"rift:nullified")
	actor.apply_time_rift(&"rift:weak", 0.85)
	suite.assert_close(actor.get("_launch_runtime").control_modifiers().movement_multiplier, 0.85, "Nullified cannot strengthen an already weaker slowdown")
	actor.clear_time_rift(&"rift:weak")
	var requested: Dictionary = actor.get("_launch_runtime").request_action("shattered_sentinel.shield_sweep", Fixture.context(0))
	suite.assert_true(requested.ok, "native Nullified Actor owns the actual authored attack warning")
	for fact: Dictionary in actor.native_cold_threat_facts():
		suite.assert_true(actor.get_meta("fixture_registry").register_fact(fact), "native warning geometry publishes its original ownership")
	var original_action: Dictionary = actor.launch_runtime_snapshot().runtime.action
	actor.apply_time_stop_source(&"stop:nullified", 180.0 / 60.0)
	var accepted: Dictionary = actor.launch_affix_runtime_snapshot()
	suite.assert_true(accepted.has("nullified") and not accepted.get("nullified", {}).is_empty(), "native Nullified owns its bounded delay and exposure receipts")
	if not accepted.has("nullified"):
		actor.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	actor.apply_time_stop_source(&"stop:nullified", 600.0 / 60.0)
	suite.assert_equal(actor.launch_affix_runtime_snapshot(), accepted, "duplicate Stop source cannot extend delay or stack vulnerability")
	for frame: int in range(1, 31):
		_tick(actor, frame)
		suite.assert_true(actor.is_time_stopped(), "converted Stop retains every one of its thirty delay frames")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.action.paused_frames, 30, "native warning clock spends exactly thirty converted Stop frames")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.action.committed_geometry[0].active_through_frame, int(original_action.committed_geometry[0].active_through_frame) + 30, "native threat warning expiry extends with the accepted delay")
	suite.assert_close(actor.get_damage_taken_multiplier(), 1.0, "delay frames cannot create premature exposure")
	_tick(actor, 31)
	suite.assert_true(not actor.is_time_stopped(), "converted long Stop releases action after thirty frames")
	suite.assert_close(actor.get_damage_taken_multiplier(), 1.20, "first post-delay frame opens the bounded native vulnerability")
	var health: Node = actor.get_node("HealthComponent")
	suite.assert_close(health.take_damage(_damage(1, Damage.DamageType.TIME, ["weapon:staff", "time:rift"])), 12.0, "Nullified retains actual TIME damage during exposure")
	suite.assert_close(health.take_damage(_damage(2, Damage.DamageType.PHYSICAL, ["weapon:bow", "echo"])), 12.0, "Nullified retains actual echo damage during exposure")
	var cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(actor.native_cold_snapshot(func(_source: Node): return {})).json).replay
	var twin := _actor()
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "typed cold restore retains active Nullified exposure and native Health")
	suite.assert_equal(twin.launch_affix_runtime_snapshot(), actor.launch_affix_runtime_snapshot(), "cold Nullified receipts and timing are exact")
	var forged := cold.duplicate(true)
	forged.actor.affix_runtime.nullified.sources[0].delay_through_frame += 1
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "forged delay beyond thirty frames refuses before mutation")
	forged = cold.duplicate(true)
	forged.actor.affix_runtime.nullified.stop_claims.clear()
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "active converted Stop cannot lose its source admission receipt")
	await _physical_roundtrip(actor)
	var before: Dictionary = actor.launch_transaction_snapshot()
	var prepared: Dictionary = actor.prepare_launch_frame(32, _context(actor, 32))
	suite.assert_true(prepared.ok and actor.commit_launch_frame(prepared.ticket) and actor.rollback_launch_frame(prepared.ticket), "rejected Nullified candidate restores accepted action and exposure clocks")
	suite.assert_true(actor.launch_transaction_snapshot() == before, "rejected candidate restores exact native Actor and Health")
	for frame: int in range(32, 61):
		_tick(actor, frame)
	suite.assert_close(actor.get_damage_taken_multiplier(), 1.20, "native exposure remains through the final thirty-frame boundary")
	_tick(actor, 61)
	suite.assert_close(actor.get_damage_taken_multiplier(), 1.0, "native exposure expires without persistent damage inflation")
	accepted = actor.launch_affix_runtime_snapshot()
	actor.apply_time_stop_source(&"stop:nullified", 180.0 / 60.0)
	suite.assert_equal(actor.launch_affix_runtime_snapshot(), accepted, "expired Stop receipt prevents a stale source from reminting conversion")
	actor.apply_time_stop_source(&"stop:cancel", 180.0 / 60.0)
	suite.assert_true(actor.is_time_stopped(), "new Stop source independently converts")
	actor.clear_time_stop_source(&"stop:cancel")
	suite.assert_true(not actor.is_time_stopped(), "source cancellation clears its active delay and exposure")
	var historical := _actor(3)
	historical.apply_time_rift(&"rift:historical", 0.10)
	suite.assert_close(historical.get("_launch_runtime").control_modifiers().movement_multiplier, 0.40, "historical revision three retains its original generic Rift behavior")
	historical.apply_time_stop_source(&"stop:historical", 180.0 / 60.0)
	suite.assert_true(not historical.launch_affix_runtime_snapshot().has("nullified"), "historical actor cannot silently gain native Nullified receipts")
	suite.assert_true(not twin.can_restore_native_cold_snapshot(historical.native_cold_snapshot(func(_source: Node): return {}), func(_binding: Dictionary): return null), "historical compiler signature cannot masquerade as current native behavior")
	for target: Node2D in [actor, twin, historical]:
		target.queue_free()
	await get_tree().process_frame
	await _test_whole_player_frame()
	await _test_native_combinations()
	await _test_presentation()
	suite.finish(get_tree())


func _actor(revision: int = -1, companion: String = "") -> Node2D:
	var actor: Node2D = Scene.instantiate()
	add_child(actor)
	var affixes: Array = [Content.affix("nullified")]
	if not companion.is_empty():
		affixes.append(Content.affix(companion))
	var accepted: Dictionary = actor.configure_launch_affixes(affixes, 3) if revision < 0 else actor.configure_launch_affixes(affixes, 3, revision)
	suite.assert_true(accepted.ok, "canonical Nullified configuration compiles before native Actor construction")
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := Fixture.identity()
	identity.hostile_source_id = "nullified-test"
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), identity).ok, "native Nullified elite configures actual species and Health")
	actor.global_position = Vector2(100, 100)
	var payloads := Node2D.new()
	actor.add_child(payloads)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(payloads)
	actor.set_meta("fixture_effects", effects)
	actor.set_meta("fixture_registry", Registry.new())
	var target: Node2D = Player.instantiate()
	target.name = "NullifiedTarget"
	target.process_mode = Node.PROCESS_MODE_DISABLED
	actor.add_child(target)
	target.configure_run(&"run-p15")
	target.global_position = Vector2(600, 100)
	target.set_physics_process(false)
	target.get_node("TimeManager").set_process(false)
	target.get_node("RewindRecorder").set_process(false)
	target.health.acquire_invulnerability_source(&"nullified_fixture")
	return actor


func _damage(generation: int, kind: int, tags: Array) -> RefCounted:
	return Damage.from_plan({"run_id": "run-p15", "target_id": "nullified-test", "hostile_source_id": "player:1", "attack_generation": generation, "action_token": generation, "source_generation": generation, "amount": 10.0, "damage_type": kind, "tags": tags, "can_crit": false})


func _context(actor: Node2D, frame: int) -> Dictionary:
	var context := Fixture.context(frame)
	context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
	context.target_position = {"x": actor.global_position.x + 500.0, "y": actor.global_position.y}
	return context


func _tick(actor: Node2D, frame: int) -> void:
	var health: Node = actor.get_node("HealthComponent")
	var health_ticket: Dictionary = health.begin_frame_signal_transaction(frame)
	var prepared: Dictionary = actor.prepare_launch_frame(frame, _context(actor, frame))
	var effects: RefCounted = actor.get_meta("fixture_effects")
	var effect: Dictionary = effects.prepare_effects([{"hostile_source_id": str(actor.hostile_source_id), "batch": prepared.batch}], {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": actor.get_meta("fixture_registry"), "actors": {str(actor.hostile_source_id): actor}, "targets": {"player:1": actor.get_node("NullifiedTarget")}}) if prepared.ok else {"ok": false}
	suite.assert_true(not health_ticket.is_empty() and prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "native Nullified candidate accepts frame %d: actor=%s, effects=%s" % [frame, str(prepared.get("context", {})), str(effect.get("context", {}))])
	if not prepared.ok or not effect.ok:
		return
	var publication: Dictionary = health.prepare_frame_signal_publication(health_ticket)
	suite.assert_true(not publication.is_empty() and health.finalize_frame_signal_publication(publication) and actor.publish_launch_frame(prepared.ticket) and effects.publish_effects(effect.ticket), "native Nullified frame publishes after actual Health and effects seal")
	health.publish_prepared_frame_signals()


func _physical_roundtrip(actor: Node2D) -> void:
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("elite_nullified")
	var binding := ContentSnapshot.snapshot(registry)
	var storage := Save.new()
	storage.configure(root, "test-nullified", binding)
	var state: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var encoded := Replay.encode_replay_json(state)
	suite.assert_true(encoded.ok and storage.save_profile("nullified_v4", "base", {"codec": encoded.json}).ok, "actual SaveService retains typed Nullified aggregate")
	var fresh := Save.new()
	fresh.configure(root, "test-nullified", binding)
	var primary: Variant = fresh.inspect_profile("nullified_v4", "base")
	suite.assert_true(primary.ok and Replay.decode_replay_json(primary.payload.payload.codec).replay == state, "fresh physical recovery authenticates exact Nullified clocks and Health")


func _test_whole_player_frame() -> void:
	var actor := _actor()
	var player: Node2D = actor.get_node("NullifiedTarget")
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(player.configure_loadout({"milestone": "LAUNCH", "seed": 42, "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH")}), "native player owns an actual configured Stop ability")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, actor.get_meta("fixture_registry"), [actor], actor.get_meta("fixture_effects")) and player.configure_hostile_frame_participant(bridge), "native Player binds Nullified hostile frame participation")
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var player_before: Dictionary = player.full_player_replay_snapshot()
	var intents := {"dash": [], "weapon": [], "character": [], "movement": Vector2.ZERO, "aim": Vector2.RIGHT, "time": [{"id": "time_slot_1", "edge": "pressed", "mode": "press", "held_frames": 0}]}
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not suite.expect_rejected_player_frame(player, intents), "late World failure rejects the actual Stop and Nullified candidate")
	suite.assert_true(actor.native_cold_snapshot(func(_source: Node): return {}) == before, "whole-frame rejection preserves native Stop receipts, exposure and Health")
	suite.assert_true(player.full_player_replay_snapshot() == player_before, "whole-frame rejection preserves native Player energy and ability state")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(intents), "native Player retries the original actual Stop frame")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().nullified.stop_claims.size(), 1, "accepted whole-frame retry admits one actual Stop source")
	suite.assert_true(actor.is_time_stopped(), "accepted actual Stop delays the native Nullified Actor")
	player.configure_hostile_frame_participant(null)
	actor.queue_free()
	await get_tree().process_frame


func _test_native_combinations() -> void:
	var frenzy := _actor(-1, "frenzy")
	_warn(frenzy)
	frenzy.apply_time_stop_source(&"stop:frenzy", 3.0)
	for frame: int in range(1, 32):
		_tick(frenzy, frame)
	suite.assert_close(frenzy.get_node("HealthComponent").take_damage(_damage(1, Damage.DamageType.TIME, ["weapon:staff"])), 14.4, "Nullified exposure retains the native Frenzy incoming multiplier")
	var anchor := _actor(-1, "anchored")
	_warn(anchor)
	for generation: int in range(1, 6):
		var plan := {"run_id": "run-p15", "target_id": "nullified-test", "hostile_source_id": "player:1", "attack_generation": generation, "action_token": generation, "source_generation": generation, "amount": 1.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:gauntlets"], "can_crit": false, "control_effect": {"kind": "launch", "displacement_pixels": 48.0}}
		anchor.get_node("HealthComponent").take_damage(Damage.from_plan(plan))
	suite.assert_equal(anchor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 20, "actual weapon launches enter native combined Anchor recovery")
	anchor.apply_time_stop_source(&"stop:anchor", 3.0)
	for frame: int in range(1, 31):
		_tick(anchor, frame)
	suite.assert_equal(anchor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 20, "Nullified converted Stop pauses compatible Anchor recovery for every delay frame")
	for frame: int in range(31, 51):
		_tick(anchor, frame)
	suite.assert_equal(anchor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 0, "compatible Anchor spends its full twenty recovery frames after Nullified delay")
	suite.assert_close(anchor.get_damage_taken_multiplier(), 1.20, "compatible Anchor recovery retains the Nullified vulnerability window")
	var cold: Dictionary = anchor.native_cold_snapshot(func(_source: Node): return {})
	var restored := _actor(-1, "anchored")
	suite.assert_true(restored.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "combined native Anchor and Nullified restore exact independent clocks")
	var forged := cold.duplicate(true)
	forged.actor.affix_runtime.nullified.sources[0].applied_frame = int(cold.actor.runtime.runtime_frame) + 1
	suite.assert_true(not restored.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "cold combined actor refuses future Stop admission")
	forged = cold.duplicate(true)
	forged.actor.affix_runtime.terminal = true
	suite.assert_true(not restored.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "cold combined actor refuses terminal divergence or active terminal Stop")
	anchor.get_node("HealthComponent").take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "nullified-test", "hostile_source_id": "player:1", "attack_generation": 99, "action_token": 99, "source_generation": 99, "amount": 10000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false}))
	suite.assert_true(anchor.launch_affix_runtime_snapshot().terminal and anchor.launch_affix_runtime_snapshot().nullified.sources.is_empty(), "actual terminal Health publication retires every active Nullified delay and exposure")
	for actor: Node2D in [frenzy, anchor, restored]:
		actor.queue_free()
	await get_tree().process_frame


func _test_presentation() -> void:
	var actor := _actor()
	_warn(actor)
	var cue := actor.get_node_or_null("EliteAffixCue")
	suite.assert_true(cue != null and cue.visible, "native Nullified owns its authored clock fragment cue")
	if cue == null:
		actor.queue_free()
		await get_tree().process_frame
		return
	suite.assert_equal(cue.get_snapshot().phase, "READY", "native clock fragment distinguishes its resting phase")
	await _capture("ready")
	actor.apply_time_stop_source(&"stop:visual", 3.0)
	suite.assert_equal(cue.get_snapshot().phase, "DELAY", "actual Stop presents the accepted delay cue immediately")
	await _capture("delay")
	for frame: int in range(1, 32):
		_tick(actor, frame)
	suite.assert_equal(cue.get_snapshot().phase, "EXPOSED", "native clock fragment distinguishes the bounded exposure")
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var old_contrast: bool = GameState.get_setting("high_contrast_danger", false)
	var old_scale: float = GameState.get_setting("enemy_telegraph_scale", 1.0)
	GameState.set_setting("high_contrast_danger", true)
	GameState.set_setting("enemy_telegraph_scale", 1.5)
	actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
	suite.assert_true(cue.get_snapshot().high_contrast and cue.get_snapshot().visual_scale == 1.5, "native clock fragment honors actual danger accessibility settings")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "clock fragment accessibility cannot alter accepted combat state")
	await _capture("exposed-high-contrast")
	GameState.set_setting("high_contrast_danger", old_contrast)
	GameState.set_setting("enemy_telegraph_scale", old_scale)
	actor.clear_time_stop_source(&"stop:visual")
	suite.assert_equal(cue.get_snapshot().phase, "READY", "actual Stop cancellation restores the resting clock fragment")
	actor.queue_free()
	await get_tree().process_frame


func _warn(actor: Node2D) -> void:
	suite.assert_true(actor.get("_launch_runtime").request_action("shattered_sentinel.shield_sweep", Fixture.context(0)).ok, "native combined affix retains the actual authored species warning")
	for fact: Dictionary in actor.native_cold_threat_facts():
		suite.assert_true(actor.get_meta("fixture_registry").register_fact(fact), "combined warning owns its native threat geometry")


func _capture(pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var output := "res://build/visual-evidence/native-elite-affixes/nullified-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(get_viewport().get_texture().get_image().save_png(output), OK, "native Nullified screenshot retained")
