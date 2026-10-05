extends "res://tests/integration/progression/meta_player_launch_test.gd"

const Main := preload("res://scenes/main.tscn")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Rewards := preload("res://scripts/progression/challenge_reward_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Arena := preload("res://scripts/modes/native_boss_arena_builder.gd")
const RushCatalog := preload("res://scripts/modes/boss_rush_catalog.gd")
const World := preload("res://scripts/replay/player_replay_world.gd")
const PixelProxy := preload("res://scripts/presentation/pixel_proxy_actor.gd")
const Health := preload("res://scripts/combat/health_component.gd")


func _run() -> void:
	suite = Suite.new()
	registry = Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	catalog = Factory.from_registry(registry).context.catalog
	var reward_catalog := Rewards.new()
	reward_catalog.configure()
	var collection := _reward_collection(reward_catalog)
	var root := Paths.resolve_default("user://p26-equipment", "p26-equipment")
	var save := Save.new()
	save.configure(root, "0.4.0-dev", Content.snapshot(registry))
	var service := Service.new()
	suite.assert_true(service.configure(catalog, save, "equipment", "base", {"meta_profile_state": Fixtures.profile(catalog), "challenge_reward_collection": collection}).ok, "previously authority-tested reward fixture configures")
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node = main.get_node("CombatRoom01/Player")
	if not player.has_method("challenge_reward_projection_snapshot"):
		suite.assert_true(false, "selected challenge equipment must reach actual native Player and frozen run identity")
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	host.set_process(false)
	player.set_physics_process(false)
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4711}
	var started: Variant = host.start_profile_run(config, service, int(service.snapshot().revision))
	suite.assert_true(started.ok, "production Host freezes authenticated owned equipment before native launch: " + str(started))
	if not started.ok:
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var projection: Dictionary = service.challenge_reward_projection().context.projection
	var meta: Dictionary = host.runtime_snapshot().resources.meta_run_projection
	suite.assert_true(Rules.same(meta.get("challenge_reward_projection", {}), projection) and Rules.same(player.challenge_reward_projection_snapshot(), projection), "run resources and actual Player carry the exact frozen reward projection")
	var base: Dictionary = Applicator.prepare(registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), {}, "sword", meta, catalog).context.stats
	suite.assert_close(player.stats.move_speed, float(base.move_speed) * 1.15, "boots modify actual Stats movement after permanent author-base derivation")
	suite.assert_close(player.mobility_snapshot().dash_speed, 520.0 * 1.2, "boots modify actual dash mobility without rewriting author catalog")
	suite.assert_true(not service.equip_challenge_reward("walker_proof", false, int(service.snapshot().revision)).ok, "equipment cannot change during an active ordinary run")
	var before: Dictionary = player.full_player_replay_snapshot()
	var forged: Dictionary = player.loadout_runtime.snapshot()
	forged.challenge_reward_projection.modifiers.dash_speed_multiplier = 10.0
	suite.assert_true(not player.configure_loadout(forged) and player.full_player_replay_snapshot() == before, "caller mutation refuses atomically before native mobility changes")
	var repeat: Dictionary = player.loadout_runtime.snapshot()
	var repeated_player := await _spawn_player()
	repeated_player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	repeated_player.collision_mask = 0
	await get_tree().physics_frame
	suite.assert_true(repeated_player.configure_loadout(repeat) and repeated_player.configure_loadout(repeat) and is_equal_approx(repeated_player.stats.move_speed, float(base.move_speed) * 1.15) and is_equal_approx(repeated_player.mobility_snapshot().dash_speed, 624.0), "repeat loadout reconstructs challenge effects once")
	suite.assert_true(repeated_player.advance_action_frame({"movement": Vector2.RIGHT, "aim": Vector2.RIGHT}), "equipped movement executes an actual native frame")
	suite.assert_close(repeated_player.velocity.x, float(base.move_speed) * 1.15, "boots drive actual committed native velocity")
	suite.assert_true(repeated_player.try_action(&"dash"), "equipped dash executes actual action arbitration")
	suite.assert_close(repeated_player.full_player_replay_snapshot().player_state.dash_velocity.length(), 624.0, "authored boots drive physical dash velocity")
	repeated_player.queue_free()
	await get_tree().process_frame
	var proxy := player.get_node_or_null("PixelProxyActor")
	if proxy == null:
		proxy = PixelProxy.new()
		player.add_child(proxy)
		proxy.bind_actor(player)
	proxy.call("_advance_animation", 0.0)
	var presentation: Dictionary = proxy.get_snapshot_for_test().get("challenge_rewards", {})
	suite.assert_true(Rules.same(presentation, projection.presentation), "actual pixel presentation applies frozen character weapon frame title and decoration selections")
	suite.assert_true(proxy.apply_cosmetic("wanderer.default") and proxy.get_node("ProductionActorAtlas").modulate == Color(0.75, 1.0, 0.79, 1.0), "Main free-cosmetic atlas application preserves the selected challenge tint immediately")
	await _test_challenge_replay(player)
	var saved = host.checkpoint_profile_run(int(service.snapshot().revision))
	suite.assert_true(saved.ok, "actual equipment native checkpoint persists: " + str(saved))
	var frozen: Dictionary = player.full_player_replay_identity()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var cold := Service.new()
	suite.assert_true(cold.configure(catalog, save, "equipment", "base").ok, "physical Profile reload validates equipped ownership")
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	host = main.get_node("RunRuntimeHost")
	player = main.get_node("CombatRoom01/Player")
	host.set_process(false)
	player.set_physics_process(false)
	var restored = host.restore_profile_checkpoint(cold, int(cold.snapshot().revision))
	suite.assert_true(restored.ok and player.full_player_replay_identity() == frozen and Rules.same(player.challenge_reward_projection_snapshot(), projection), "fresh native cold checkpoint retains exact frozen equipment identity: " + str({"ok": restored.ok, "code": restored.code, "context": restored.context}))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_challenge_damage(meta)
	suite.finish(get_tree())


func _reward_collection(reward_catalog: RefCounted) -> Dictionary:
	var collection: Dictionary = reward_catalog.empty_collection()
	collection.owned_ids = ["daily_archive_decoration", "daily_character_color", "daily_walker_frame", "daily_weapon_skin", "eternal_traveler", "speedwalker_boots", "walker_proof"]
	collection.equipped_ids = collection.owned_ids.duplicate()
	collection.source_receipts = [{"mode_id": "boss_rush_carried", "source_id": "tested-native-boss-fixture", "source_digest": "a".repeat(64), "owned_ids": ["speedwalker_boots", "walker_proof"]}, {"mode_id": "daily_boss", "source_id": "tested-native-daily-fixture", "source_digest": "b".repeat(64), "owned_ids": ["daily_archive_decoration", "daily_character_color", "daily_walker_frame", "daily_weapon_skin", "eternal_traveler"]}]
	return collection


func _test_challenge_replay(player: Node) -> void:
	var identity: Dictionary = player.full_player_replay_identity()
	suite.assert_true(identity.has("challenge_reward_projection") and Recorder.validate_full_player_identity(identity) == identity, "real replay identity authenticates frozen equipment")
	var bad := identity.duplicate(true)
	bad.mobility.dash_speed += 1.0
	suite.assert_true(Recorder.validate_full_player_identity(bad).is_empty(), "replay refuses modified canonical dash mobility even when reward selection is valid")
	bad = identity.duplicate(true)
	bad.challenge_reward_projection.content_snapshot = {}
	suite.assert_true(Recorder.validate_full_player_identity(bad).is_empty(), "imported equipment identity rejects absent content binding")
	var recorder := Recorder.new()
	var snapshot: Dictionary = player.full_player_replay_snapshot()
	suite.assert_equal(snapshot.schema_version, 9, "equipment uses explicit replay schema nine while historical Meta remains eight")
	var downgraded := snapshot.duplicate(true)
	downgraded.schema_version = 8
	suite.assert_true(not player.restore_full_player_replay_snapshot(downgraded), "equipped checkpoint refuses silent historical schema downgrade")
	var intents := {"dash": [], "time": [], "weapon": [], "character": [], "movement": Vector2.ZERO, "aim": Vector2.RIGHT, "meta": {"source": "challenge_equipment_test", "target_frame": int(snapshot.frame), "frame": int(snapshot.frame)}}
	suite.assert_true(recorder.start_full_player_recording(identity, 4711).ok and recorder.record_full_player_frame(snapshot, intents, []).ok, "equipment-bearing native snapshot records")
	var finished: Dictionary = recorder.finish_full_player_recording()
	var encoded: Dictionary = Recorder.encode_replay_json(finished.replay)
	var playback := Playback.new()
	suite.assert_true(encoded.ok and playback.load_full_player_replay_json(encoded.json, identity).ok, "equipment replay physically round-trips through JSON and playback")
	var world := World.new()
	add_child(world)
	var target := world.create_player()
	suite.assert_true(target.configure_replay_view_identity(identity) and playback.restore_full_player_frame(target, 0).ok, "isolated viewer reconstructs authenticated equipped mobility and exact recorded identity")
	world.queue_free()
	await get_tree().process_frame


func _test_challenge_damage(meta: Dictionary) -> void:
	var rush := RushCatalog.new()
	rush.configure(registry)
	var stage := Node2D.new()
	add_child(stage)
	var arena := Arena.build(stage, registry, rush.stage(0), {"seed": 42, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}, "challenge-damage", "challenge", "challenge-damage")
	suite.assert_true(arena.ok, "actual native Boss arena constructs for equipment damage")
	if arena.ok:
		var player: Node = arena.player
		player.set_physics_process(false)
		suite.assert_true(player.configure_loadout(_config("wanderer", "sword", ["stop", "rewind"], meta)), "damage fixture installs exact frozen equipment on actual Player")
		var info := Damage.from_plan({"run_id": "challenge-damage", "target_id": str(arena.boss.get_meta("stable_target_id")), "hostile_source_id": "challenge-proof-hit", "attack_generation": 1, "action_token": 1, "amount": 100.0, "damage_type": Damage.DamageType.PHYSICAL, "source": player, "attacker": player, "knockback": Vector2.ZERO, "tags": [], "can_crit": false})
		var actual: float = arena.boss.health.take_damage(info)
		suite.assert_close(actual, 115.0 - arena.boss.health.defense, "Walker Proof changes actual bound Boss damage by authored fifteen percent")
		var ordinary := Node2D.new()
		ordinary.add_to_group("bosses")
		stage.add_child(ordinary)
		var health := Health.new()
		ordinary.add_child(health)
		suite.assert_close(health.take_damage(info), 100.0, "ordinary actor cannot become a Boss by group spoofing and receives baseline damage")
		arena.effects.dispose_native_effects()
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
