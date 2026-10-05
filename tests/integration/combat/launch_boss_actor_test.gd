extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for row: Dictionary in Fixtures.read_catalog("bosses.json"):
		var path := "res://data/content_packs/base/assets/bosses/launch/boss_%s.tscn" % row.id
		suite.assert_true(ResourceLoader.exists(path, "PackedScene"), "native Boss scene exists: " + row.id)
		if not ResourceLoader.exists(path, "PackedScene"):
			continue
		var scene := load(path) as PackedScene
		suite.assert_true(scene != null, "native Boss scene loads: " + row.id)
		if scene != null:
			await _test_actor(scene, row)
			await _test_bridge(scene, row)
	suite.finish(get_tree())


func _test_actor(scene: PackedScene, definition: Dictionary) -> void:
	var actor := scene.instantiate()
	add_child(actor)
	await get_tree().process_frame
	actor.global_position = Vector2(100, 100)
	var parser := Definition.new()
	parser.configure(definition)
	var identity := Actions.identity()
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok, "actual Boss binds canonical domain: " + definition.id)
	var sprite := actor.get_node("Sprite2D") as Sprite2D
	suite.assert_true(sprite.texture != null and sprite.texture.get_size() == Vector2(320, 480), "actual Boss uses manifested original six-track raster atlas")
	suite.assert_true(not actor.get_node("Visual").visible and actor.is_in_group("bosses"), "actual Boss owns native presentation and Boss control group")
	suite.assert_close(actor.get_node("CollisionShape2D").shape.radius, float(definition.collision_radius_px), "body radius matches authored physical collision")
	suite.assert_close(actor.get_node("Hurtbox/CollisionShape2D").shape.radius, float(definition.collision_radius_px), "hittable body radius matches authored physical collision")
	await _capture_native(definition.id)
	var before: Dictionary = actor.launch_runtime_snapshot()
	actor._physics_process(4.0)
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "native Boss physics projection cannot advance gameplay")
	actor.health.died.emit(null)
	suite.assert_true(actor.launch_runtime_snapshot() == before and actor.is_in_group("bosses") and not actor.is_queued_for_deletion(), "forged public Health death cannot retire actual Boss state or control group")
	actor.apply_time_stop_source(&"stop:actual", 3.0)
	var stopped: Dictionary = actor.launch_runtime_snapshot()
	suite.assert_true(stopped.runtime.mechanism_state.exposure_through_frame == 45 and not actor.is_time_stopped(), "actual native Stop grants positive Boss exposure conversion")
	_test_conversion_endpoints(actor, definition, identity)
	stopped = actor.launch_runtime_snapshot()
	var prepared: Dictionary = actor.prepare_launch_frame(1, Actions.context(1))
	suite.assert_true(prepared.ok and actor.launch_runtime_snapshot() == stopped, "prepare leaves complete live Boss state unchanged")
	if prepared.ok:
		suite.assert_true(actor.commit_launch_frame(prepared.ticket), "native Boss frame commits staged domain")
		suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "native Boss compensates rejected frame")
		suite.assert_equal(actor.launch_runtime_snapshot(), stopped, "native Boss rollback restores complete domain and Health")
	var saved: Dictionary = actor.launch_transaction_snapshot()
	actor.apply_time_rift(&"rift:actual", 0.20)
	suite.assert_true(actor.restore_launch_transaction_snapshot(saved), "actual Health-ledger capability restores complete Boss transaction")
	suite.assert_true(not actor.restore_launch_transaction_snapshot(saved), "actual Health-ledger capability is consumed exactly once")
	var deaths: Array = []
	actor.hostile_final_death.connect(func(source: StringName, receipt: String): deaths.append([source, receipt]))
	var health := actor.get_node("HealthComponent")
	var info := Damage.from_plan({"run_id": identity.run_id, "target_id": identity.hostile_source_id, "hostile_source_id": "player:1", "attack_generation": 4, "action_token": 4, "amount": 10000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["attack:heavy"], "can_crit": false})
	health.take_damage(info)
	suite.assert_equal(deaths.size(), 1, "actual Boss final Health death emits one counted receipt")
	suite.assert_true(actor.launch_runtime_snapshot().runtime.terminal and actor.elemental_status_snapshot().source_count == 0, "actual Boss final death clears domain/control/status state")
	await get_tree().create_timer(0.3).timeout
	suite.assert_true(not is_instance_valid(actor), "bounded final death presentation retires native Boss body")
	if is_instance_valid(actor):
		actor.queue_free()
	await get_tree().process_frame


func _test_conversion_endpoints(actor: Node, definition: Dictionary, identity: Dictionary) -> void:
	for field: String in ["room_id", "encounter_id", "encounter_spawn_id"]:
		actor.set_meta(field, "native-boss-" + field)
	actor.set_meta("run_id", identity.run_id)
	actor.set_meta("encounter_enemy_id", definition.id)
	for method: String in ["apply_weapon_control_conversion", "extend_character_boss_exposure", "character_boss_exposure_snapshot", "character_boss_exposure_identity", "can_restore_character_boss_exposure_snapshot", "restore_character_boss_exposure_snapshot", "configure_character_boss_exposure_replay_authority", "can_restore_character_boss_exposure_replay_snapshot", "restore_character_boss_exposure_replay_snapshot", "get_boss_ui_snapshot"]:
		suite.assert_true(actor.has_method(method), "actual Boss supplies required Player endpoint: " + method)
		if not actor.has_method(method):
			return
	suite.assert_true(actor.apply_weapon_control_conversion(&"weapon:actual", 12, 8, 0.0), "actual exposed Boss converts a new weapon source")
	var after: Dictionary = actor.launch_runtime_snapshot()
	suite.assert_true(not actor.apply_weapon_control_conversion(&"weapon:actual", 12, 8, 0.0) and actor.launch_runtime_snapshot() == after, "actual Boss deduplicates weapon conversion source")
	suite.assert_true(actor.extend_character_boss_exposure(1, 18), "actual Boss accepts exact Character Stop exposure tail")
	var exposure: Dictionary = actor.character_boss_exposure_snapshot()
	suite.assert_true(exposure.schema_version == 1 and exposure.remaining_tail_frames == 18 and exposure.tail_state == "pending", "Character exposure preserves existing schema-one pending tail")
	suite.assert_true(not actor.extend_character_boss_exposure(1, 18) and not actor.extend_character_boss_exposure(2, 31), "Character source generation and extension caps are strict")
	suite.assert_true(actor.restore_character_boss_exposure_snapshot(exposure), "ordinary exact Character exposure checkpoint remains compatible")
	var forged := exposure.duplicate(true)
	forged.identity.encounter_enemy_id = "foreign-boss"
	suite.assert_true(not actor.restore_character_boss_exposure_snapshot(forged) and actor.character_boss_exposure_snapshot() == exposure, "Character exposure rejects foreign physical Boss identity unchanged")
	var authority := RefCounted.new()
	suite.assert_true(actor.configure_character_boss_exposure_replay_authority(authority), "native Boss binds opaque exposure Replay authority")
	suite.assert_true(not actor.can_restore_character_boss_exposure_replay_snapshot(exposure, RefCounted.new()), "foreign opaque authority cannot preflight Character rollback")
	suite.assert_true(actor.can_restore_character_boss_exposure_replay_snapshot(exposure, authority), "bound opaque authority preflights exact Character exposure")
	var ui: Dictionary = actor.get_boss_ui_snapshot()
	suite.assert_true(ui.has("action") and ui.has("phase") and ui.has("remaining") and ui.has("boss_phase") and ui.has("exposed") and ui.get("maximum_hp") == definition.max_hp and ui.get("phase_total") == definition.phases.size(), "Boss UI preserves legacy fields and adds actual authored phase/Health facts")
	var action: Dictionary = definition.actions[0]
	var runtime: RefCounted = actor.get("_launch_runtime")
	var context := Actions.context(0)
	context.target_position.x = 100.0 + maxf(float(action.distance_min_px), minf(40.0, float(action.distance_max_px)))
	suite.assert_true(runtime.request_action(action.id, context).ok, "actual Boss conversion gate begins an authored committed warning")
	var warning: Dictionary = actor.launch_runtime_snapshot()
	suite.assert_true(not actor.apply_weapon_control_conversion(&"weapon:warning", 12, 8, 20.0) and actor.launch_runtime_snapshot() == warning, "weapon conversion preserves actual committed Boss warning")
	suite.assert_true(not actor.apply_elemental_status(&"freeze", &"staff:warning", 1, 60, 0.0), "Staff freeze preserves committed warning")
	var snapshot: Dictionary = runtime.snapshot()
	for frame: int in range(1, int(action.warning_frames) + int(action.active_frames) + 1):
		var next := context.duplicate(true)
		next.runtime_frame = frame
		runtime.advance_frame(frame, next, false)
	suite.assert_true(runtime.snapshot().action.phase == "RECOVERY", "actual Boss enters authored recovery conversion window")
	var delay := int(runtime.snapshot().mechanism_state.delay_remaining_frames)
	suite.assert_true(actor.apply_elemental_status(&"freeze", &"staff:actual", 1, 60, 0.0) and not actor.is_elementally_frozen(), "actual Staff freeze becomes positive recovery extension")
	suite.assert_equal(runtime.snapshot().mechanism_state.delay_remaining_frames, delay + 12, "actual Staff freeze conversion adds exactly twelve frames")
	suite.assert_true(actor.apply_elemental_status(&"blind", &"staff:actual", 2, 60, 0.5), "actual Staff blind becomes positive recovery extension")
	suite.assert_equal(runtime.snapshot().mechanism_state.delay_remaining_frames, delay + 20, "actual Staff blind conversion adds exactly eight frames")
	suite.assert_close(actor.get("elemental_status_runtime").blind_chance(), 0.0, "Boss conversion never introduces random active-hit failure")
	var hit := Damage.from_plan({"run_id": identity.run_id, "target_id": identity.hostile_source_id, "hostile_source_id": "player:1", "attack_generation": 3, "action_token": 3, "amount": 1.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:gauntlets"], "can_crit": false})
	var effect := {"kind": "launch", "conversion_id": "gauntlets_poised_launch", "airborne": false, "active_attack_policy": "preserve_committed", "interrupt_active_attack": false, "allowed_states": ["RECOVERY", "EXPOSED"], "poise_damage": 10.0, "boss_poise_multiplier": 1.40, "displacement_pixels": 0.0, "source_id": "gauntlet:actual"}
	suite.assert_true(actor._resolve_weapon_hit_control(effect, hit, 1.0), "actual Gauntlets use authored positive poise conversion")
	suite.assert_close(runtime.snapshot().conversion.poise, 14.0, "actual Gauntlets retain exact 1.40 Boss poise factor")
	suite.assert_true(runtime.restore_snapshot(snapshot), "native endpoint fixture restores full pre-advance frame for transaction gate: " + definition.id)


func _test_bridge(scene: PackedScene, definition: Dictionary) -> void:
	var player := PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(140, 100)
	var actor := scene.instantiate()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = Vector2(100, 100)
	var parser := Definition.new()
	parser.configure(definition)
	var identity := Actions.identity()
	identity.seed = 42
	actor.configure_launch_definition(parser.runtime_projection(), identity)
	var effects := Effects.new()
	effects.configure("run-p15")
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "actual Boss participates in Player hostile frame bridge")
	var before: Dictionary = actor.launch_runtime_snapshot()
	var damaged: Array = []
	actor.health.damaged.connect(func(amount: float, hp: float): damaged.append([amount, hp]))
	var ticket: Dictionary = bridge.begin_frame(1)
	actor.health.take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:test-a", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 10.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false, "source": player, "attacker": player}))
	actor.apply_time_stop_source(&"bridge:stop", 3.0)
	suite.assert_true(bridge.prepare_frame(ticket), "actual Boss and real effect authority prepare one native Player frame")
	suite.assert_equal(damaged, [], "actual Boss damage observation remains buffered before Player acceptance")
	suite.assert_true(bridge.rollback_frame(ticket), "actual Boss bridge compensates refused Player sibling")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "actual bridge restores complete Boss HP/claims/control/action/conversion clocks")
	suite.assert_equal(registry.snapshot(), [], "actual Boss refusal restores real threat fact prefix")
	suite.assert_equal(damaged, [], "actual Boss refusal publishes no native damage fact")
	ticket = bridge.begin_frame(1)
	suite.assert_true(bridge.prepare_frame(ticket), "restored actual Boss frame retries deterministically")
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	suite.assert_true(not publication.is_empty() and bridge.finalize_frame_publication(publication) and bridge.seal_frame_publication(publication), "actual Boss accepted frame seals every native sibling")
	bridge.publish_prepared_frame()
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.runtime_frame, 1, "accepted Player bridge advances one actual Boss frame")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _capture_native(id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		var colors: Dictionary = {}
		var foreground := 0
		var background := pixels.get_pixel(0, 0).to_rgba32()
		for y: int in range(60, 140):
			for x: int in range(60, 140):
				var point := Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))
				var color := pixels.get_pixelv(point).to_rgba32()
				colors[color] = true
				if color != background:
					foreground += 1
		suite.assert_true(colors.size() >= 5 and foreground > 300, "actual native Boss scene draws substantial nonblank raster pixels: " + id)
		var output := "res://build/visual-evidence/p15b-native-boss-foundation/%s-%dx%d.png" % [id, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "actual native Boss screenshot is retained")
