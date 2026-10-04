extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const ProjectionScript := preload("res://scripts/progression/meta_run_projection.gd")
const Applicator := preload("res://scripts/progression/meta_stats_applicator.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const Playback := preload("res://scripts/replay/replay_player.gd")

var suite: RefCounted
var registry: RefCounted
var catalog: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	registry = Registry.new()
	var report: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "real launch registry loads for native permanent integration")
	if report.has_blocking_errors():
		suite.finish(get_tree())
		return
	catalog = Factory.load_base().context.catalog
	var profile := Fixtures.profile(catalog)
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		profile.forge_state[weapon].level = 5
	var projection: Dictionary = ProjectionScript.from_profile(profile, catalog).context.projection
	var player := await _spawn_player()
	var config := _config("time_guardian", "sword", ["stop", "rewind"], projection)
	suite.assert_true(player.configure_loadout(config), "native Player accepts authenticated permanent launch projection")
	var expected: Dictionary = Applicator.prepare(config.character_profile, {}, "sword", projection, catalog).context.stats
	suite.assert_equal(player.stats.snapshot(), expected, "permanent stats are installed before native components and reward baseline")
	suite.assert_close(player.get_node("HealthComponent").max_hp, expected.max_hp, "native Health receives the permanent HP total")
	suite.assert_equal(player.reward_effect_snapshot().stats, expected, "run-start reward baseline contains the installed permanent stats")
	var before: Dictionary = player.full_player_replay_snapshot()
	for mutation: String in ["digest", "rehash", "unknown", "wrong_type", "m1"]:
		var bad := config.duplicate(true)
		match mutation:
			"digest": bad.meta_run_projection.projection_digest = "0".repeat(64)
			"rehash":
				bad.meta_run_projection.stat_bonuses.attack = 0.01
				bad.meta_run_projection["projection_digest"] = ProjectionScript.digest(bad.meta_run_projection)
			"unknown": bad.meta_run_projection.hidden_bonus = 1
			"wrong_type": bad.meta_run_projection = true
			"m1": bad.milestone = "M1"
		suite.assert_true(not player.configure_loadout(bad), "invalid frozen projection refuses before native mutation: " + mutation)
		suite.assert_equal(player.full_player_replay_snapshot(), before, "failed permanent loadout is atomic: " + mutation)
	suite.assert_true(player.configure_loadout(config), "repeated native construction accepts the same frozen projection")
	suite.assert_equal(player.stats.snapshot(), expected, "repeat construction derives from author base without stacking")
	var detached := config.duplicate(true)
	detached.meta_run_projection.stat_bonuses.max_hp = 0.50
	suite.assert_equal(player.loadout_runtime.snapshot().meta_run_projection, projection, "native config owns a detached immutable permanent projection")
	await _test_void_damage(player)
	await _test_replay(player, config, projection)
	await _test_matrix(player, projection)
	player.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _test_void_damage(player: Node) -> void:
	suite.assert_true(player.advance_action_frame(), "native damage is observed after the first committed character frame")
	var health: Node = player.get_node("HealthComponent")
	var initial: Dictionary = player.reward_effect_snapshot()
	var void_damage := _damage(player, Damage.DamageType.VOID)
	var resolution: RefCounted = health.resolve_and_apply_damage(void_damage)
	suite.assert_close(resolution.finalized_damage(), 100.0 * 0.98 - float(player.stats.defense), "native Void damage applies the frozen two-percent resistance: %s" % str(resolution.snapshot()))
	suite.assert_true(player.restore_reward_effect_snapshot(initial), "native damage fixture restores its baseline")
	suite.assert_close(health.take_damage(_damage(player, Damage.DamageType.PHYSICAL)), 100.0 - float(player.stats.defense), "physical damage receives no unearned Void resistance")
	suite.assert_true(player.restore_reward_effect_snapshot(initial), "physical damage fixture restores its baseline")


func _test_replay(player: Node, config: Dictionary, projection: Dictionary) -> void:
	var identity: Dictionary = player.full_player_replay_identity()
	suite.assert_equal(identity.get("meta_projection_digest"), projection.projection_digest, "Replay identity binds non-stat permanent policies as well as final Stats")
	var snapshot: Dictionary = player.full_player_replay_snapshot()
	suite.assert_equal(snapshot.schema_version, 8, "Meta launch uses an explicit Replay schema while historical Launch keeps version seven")
	var recorder = Recorder.new()
	suite.assert_true(recorder.start_full_player_recording(identity, 42).ok, "Meta launch identity passes the real Replay contract")
	var intents := {"dash": [], "time": [], "weapon": [], "character": [], "movement": Vector2.ZERO, "aim": Vector2.RIGHT, "meta": {"source": "meta_player_launch_test", "target_frame": int(snapshot.frame), "frame": int(snapshot.frame)}}
	suite.assert_true(recorder.record_full_player_frame(snapshot, intents, []).ok, "Meta initial checkpoint records through the native Replay recorder")
	var finished: Dictionary = recorder.finish_full_player_recording()
	suite.assert_true(finished.ok, "Meta Replay serialization completes")
	var encoded: Dictionary = Recorder.encode_replay_json(finished.replay)
	suite.assert_true(encoded.ok, "native Meta Replay serializes actual vectors and StringNames through the JSON codec")
	var playback = Playback.new()
	suite.assert_true(playback.load_full_player_replay_json(encoded.json, identity).ok, "Meta Replay round-trips through the real JSON contract and playback loader")
	var target := await _spawn_player()
	suite.assert_true(target.configure_loadout(config), "fresh native Replay target reconstructs the frozen projection")
	while target.owner_character_generation() < int(identity.owner_character_generation):
		suite.assert_true(target.configure_loadout(config), "fresh Replay target reproduces the canonical generation before checkpoint restore")
	suite.assert_true(target.restore_full_player_replay_snapshot(snapshot), "fresh native Meta target accepts the saved checkpoint")
	suite.assert_equal(target.full_player_replay_snapshot(), snapshot, "native Meta checkpoint round-trip preserves all participants")
	suite.assert_true(playback.restore_full_player_frame(target, 0).ok, "decoded Meta Replay restores the native target")
	var forged := snapshot.duplicate(true)
	forged.schema_version = 7
	suite.assert_true(not target.restore_full_player_replay_snapshot(forged), "Meta checkpoint cannot silently downgrade to the historical Launch contract")
	forged = snapshot.duplicate(true)
	forged.identity.meta_projection_digest = "0".repeat(64)
	suite.assert_true(not target.restore_full_player_replay_snapshot(forged), "rehashed or foreign permanent identity cannot replace the target's frozen launch")
	var plain := config.duplicate(true)
	plain.erase("meta_run_projection")
	suite.assert_true(target.configure_loadout(plain), "historical launch without Meta remains supported")
	suite.assert_equal(target.full_player_replay_snapshot().schema_version, 7, "plain launch keeps its existing Replay schema")
	suite.assert_true(not target.restore_full_player_replay_snapshot(snapshot), "different permanent policy cannot restore a Meta checkpoint")
	target.queue_free()
	await get_tree().process_frame


func _test_matrix(player: Node, projection: Dictionary) -> void:
	var count := 0
	var time_ids := ["accelerate", "rewind", "rift", "stop"]
	for character: String in ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]:
		for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
			for first: int in range(4):
				for second: int in range(first + 1, 4):
					var config := _config(character, weapon, [time_ids[first], time_ids[second]], projection)
					suite.assert_true(player.configure_loadout(config), "actual native Player assembles canonical permanent loadout " + character + "/" + weapon)
					var expected: Dictionary = Applicator.prepare(config.character_profile, {}, weapon, projection, catalog).context.stats
					suite.assert_equal(player.stats.snapshot(), expected, "native matrix permanent totals match independent author-base preparation")
					count += 1
	suite.assert_equal(count, 150, "native permanent integration exercises five characters, five weapons and six time pairs")


func _config(character: String, weapon: String, time_pair: Array, projection: Dictionary) -> Dictionary:
	return {"schema_version": 1, "milestone": "LAUNCH", "character_id": character, "character_profile": registry.resolve_character_runtime_profile(StringName(character), &"LAUNCH"), "character_talents": [], "weapon_id": weapon, "weapon_profile": registry.resolve_weapon_runtime_profile(StringName(weapon), &"LAUNCH"), "enabled_time_skills": time_pair, "difficulty": "normal", "seed": 42, "meta_run_projection": projection.duplicate(true)}


func _damage(player: Node, kind: int) -> RefCounted:
	return Damage.from_plan({"run_id": str(player.current_run_id()), "target_id": "player", "hostile_source_id": "enemy-void-probe", "attack_generation": 1, "action_token": 1, "amount": 100.0, "damage_type": kind, "knockback": Vector2.LEFT, "tags": [], "can_crit": false})


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	return player
