extends "res://tests/integration/combat/launch_elite_shielded_test.gd"

const Bow := preload("res://scenes/combat/player_arrow.tscn")
const Gun := preload("res://scenes/combat/gun_projectile.tscn")
const Staff := preload("res://scenes/combat/staff_projectile.tscn")
const Gauntlets := preload("res://scripts/combat/gauntlets_hit_execution.gd")
const ReplayWorld := preload("res://scripts/replay/player_replay_world.gd")

class RecordingShieldActor:
	extends "res://scripts/enemies/launch/launch_hostile_actor.gd"
	var producer_info: RefCounted
	func prepare_post_defense_absorption(info: RefCounted, resolution: RefCounted) -> Dictionary:
		producer_info = info
		return super.prepare_post_defense_absorption(info, resolution)

class SpoofPlayer:
	extends Node2D
	func current_run_id() -> StringName:
		return &"run-p15"


func _run() -> void:
	suite = Suite.new()
	for weapon: String in ["bow", "gun", "staff", "gauntlets"]:
		await _test_producer(weapon)
	await _test_historical_component_identity()
	await _test_actual_player_weapon_frame()
	suite.finish(get_tree())


func _producer_actor() -> Node2D:
	var actor: Node2D = Scene.instantiate()
	actor.set_script(RecordingShieldActor)
	add_child(actor)
	actor.global_position = Vector2(100, 100)
	actor.set_meta("encounter_spawn_id", "shielded-test")
	suite.assert_true(actor.configure_launch_affixes([Content.affix("shielded")], 3).ok, "actual weapon victim installs native shield before species")
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := Fixture.identity()
	identity.hostile_source_id = "shielded-test"
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), identity).ok, "actual weapon victim owns authored native elite Health")
	return actor


func _test_producer(weapon_id: String) -> void:
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(player.configure_loadout({"milestone": "LAUNCH", "seed": 42, "character_id": "wanderer", "weapon_id": weapon_id, "enabled_time_skills": ["stop", "rewind"], "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(StringName(weapon_id), &"LAUNCH")}), "actual Player configures production%sweapon source" % weapon_id)
	var source: Node = player.get_node(weapon_id.capitalize() + "Weapon")
	var actor := _producer_actor()
	if weapon_id == "gauntlets":
		actor.set_meta("stable_target_id", 417)
	var producer: Node
	match weapon_id:
		"bow": producer = Bow.instantiate()
		"gun": producer = Gun.instantiate()
		"staff": producer = Staff.instantiate()
		"gauntlets": producer = Gauntlets.new()
	producer.set("source", source)
	producer.set("owner_entity", player)
	producer.set("action_token", 7)
	if weapon_id in ["staff", "gauntlets"]:
		producer.set("generation", 7)
		producer.set("source_action_id", "projectile" if weapon_id == "staff" else "punch_1")
	if weapon_id in ["bow", "gun"]:
		producer.set("attack_tags", ["weapon:" + weapon_id])
	producer.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(producer)
	var no_extra_tags: Array[String] = []
	match weapon_id:
		"bow": producer.call("_deliver_damage", actor.get_node("Hurtbox"), 20.0, Damage.DamageType.PHYSICAL, false)
		"gun": producer.call("_deliver_damage", actor.get_node("Hurtbox"), 20.0, Damage.DamageType.PHYSICAL, no_extra_tags)
		"staff": producer.call("_deliver_damage_to_target", actor, 20.0, "fire", Vector2.ZERO)
		"gauntlets": producer.call("_deliver_component", actor, {"amount": 20.0, "primary": true, "type": Damage.DamageType.PHYSICAL})
	var info: RefCounted = actor.get("producer_info")
	var target_id := &"target:417" if weapon_id == "gauntlets" else (&"pending_target" if weapon_id == "gun" else &"target:shielded-test")
	suite.assert_true(info != null and info.run_id == &"runtime" and info.target_id == target_id, "actual%sproducer emits its production compatibility identity" % weapon_id)
	suite.assert_close(actor.get_node("HealthComponent").current_hp, 160.0, "actual%sproducer fully absorbed hit cannot remove body Health" % weapon_id)
	suite.assert_close(actor.launch_affix_runtime_snapshot().shielded.current_pool, 28.0, "actual%sproducer reaches native shield once" % weapon_id)
	if info != null:
		var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
		actor.get_node("HealthComponent").take_damage(info)
		suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "duplicate actual%sproducer identity cannot spend shield twice" % weapon_id)
		var rogue := Node.new()
		add_child(rogue)
		var plan: Dictionary = info.snapshot()
		plan.source = rogue
		plan.attack_generation += 1
		var forged := Damage.from_plan(plan)
		actor.get_node("HealthComponent").take_damage(forged)
		suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "unowned%scompatibility source cannot spend shield despite actual Player attacker" % weapon_id)
		var spoof := SpoofPlayer.new()
		add_child(spoof)
		spoof.add_to_group("player")
		plan = info.snapshot()
		plan.source = spoof
		plan.attacker = spoof
		plan.attack_generation += 2
		forged = Damage.from_plan(plan)
		actor.get_node("HealthComponent").take_damage(forged)
		suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "group and run-method spoof cannot impersonate actual%sPlayer authority" % weapon_id)
		var world := ReplayWorld.new()
		add_child(world)
		var foreign: Node2D = world.create_player()
		foreign.configure_run(&"run-p15")
		plan = info.snapshot()
		plan.source = foreign.get_node(weapon_id.capitalize() + "Weapon")
		plan.attacker = foreign
		plan.attack_generation += 3
		forged = Damage.from_plan(plan)
		actor.get_node("HealthComponent").take_damage(forged)
		suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "isolated replay%sPlayer cannot hit a different native world" % weapon_id)
		for wrong_target: String in ["target:other-hostile", "target:418", ""]:
			plan = info.snapshot()
			plan.attack_generation += 4
			plan.target_id = wrong_target
			actor.get_node("HealthComponent").take_damage(Damage.from_plan(plan))
			suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "owned%sproducer cannot claim foreign or absent native target" % weapon_id)
		for target: Node in [rogue, spoof, world]:
			target.queue_free()
		if weapon_id in ["bow", "gun"]:
			if weapon_id == "bow":
				producer.call("_deliver_damage", actor.get_node("Hurtbox"), 5.0, Damage.DamageType.TIME, true)
			else:
				producer.call("_deliver_damage", actor.get_node("Hurtbox"), 5.0, Damage.DamageType.TIME, no_extra_tags)
			suite.assert_close(actor.launch_affix_runtime_snapshot().shielded.current_pool, 23.0, "actual%sTime component shares its hit generation but consumes five additional shield" % weapon_id)
			suite.assert_equal(actor.launch_affix_runtime_snapshot().shielded.damage_claims.size(), 2, "actual%sbase and Time damage retain independent once-only component receipts" % weapon_id)
			before = actor.native_cold_snapshot(func(_source: Node): return {})
			actor.get_node("HealthComponent").take_damage(actor.get("producer_info"))
			suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "duplicate actual%sTime component cannot consume shield twice" % weapon_id)
			var twin := _producer_actor()
			suite.assert_true(twin.restore_native_cold_snapshot(Replay.decode_replay_json(Replay.encode_replay_json(before).json).replay, func(_binding: Dictionary): return null), "typed%scomponent shield state reconstructs exact native receipt identity" % weapon_id)
			suite.assert_equal(twin.native_cold_snapshot(func(_source: Node): return {}), before, "cold%scomponent pool and receipt state stay exact" % weapon_id)
			twin.queue_free()
	for target: Node in [producer, actor, player]:
		target.queue_free()
	await get_tree().process_frame


func _test_historical_component_identity() -> void:
	for revision: int in [5, 6]:
		var historical := _actor(revision)
		var info: RefCounted = _damage(1, 20.0)
		historical.get_node("HealthComponent").take_damage(info)
		var plan: Dictionary = info.snapshot()
		plan.damage_type = Damage.DamageType.TIME
		plan.amount = 5.0
		historical.get_node("HealthComponent").take_damage(Damage.from_plan(plan))
		suite.assert_close(historical.launch_affix_runtime_snapshot().shielded.current_pool, 28.0, "historical revision%d retains its original single-hit component identity" % revision)
		var cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(historical.native_cold_snapshot(func(_source: Node): return {})).json).replay
		var twin := _actor(revision)
		suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "historical revision%d restores its original native shield receipt" % revision)
		var current := _actor()
		suite.assert_true(not current.can_restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "historical revision%d receipt cannot silently adopt new component identity" % revision)
		for target: Node in [historical, twin, current]:
			target.queue_free()
		await get_tree().process_frame
