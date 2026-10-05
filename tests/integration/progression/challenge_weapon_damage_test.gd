extends "res://tests/integration/progression/challenge_equipment_test.gd"

const Arrow := preload("res://scripts/combat/player_arrow.gd")
const Bullet := preload("res://scripts/combat/gun_projectile.gd")
const StaffBolt := preload("res://scripts/combat/staff_projectile.gd")
const StaffZone := preload("res://scripts/combat/staff_spell_zone.gd")
const Fist := preload("res://scripts/combat/gauntlets_hit_execution.gd")
const FistZone := preload("res://scripts/combat/gauntlets_zone_execution.gd")

class SwordHitBridge:
	extends "res://scripts/enemies/launch/hostile_frame_bridge.gd"
	var source_player: Node
	var boss: Node
	var delivered := 0
	var planned_damage := 0.0
	var actual_damage := 0.0
	func prepare_frame(ticket: Dictionary) -> bool:
		var hitbox: Node = source_player.get_node("SwordWeapon/Hitbox")
		if hitbox.is_active():
			var info: RefCounted = hitbox.get("_active_damage_info").copy_for_source(hitbox)
			delivered += 1
			planned_damage = info.amount
			actual_damage = boss.get_node("Hurtbox").receive_hit(info)
		return super.prepare_frame(ticket)


func _run() -> void:
	suite = Suite.new()
	registry = Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var rewards := Rewards.new()
	rewards.configure()
	var projection := rewards.projection(_reward_collection(rewards), {"profile_id": "weapon-proof", "save_domain": "base", "content_snapshot": Content.snapshot(registry)})
	var rush := RushCatalog.new()
	rush.configure(registry)
	var stage := Node2D.new()
	add_child(stage)
	var sword_bridge := SwordHitBridge.new()
	var arena := Arena.build(stage, registry, rush.stage(0), {"seed": 42, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}, "weapon-proof", "proof", "weapon-proof", Arena.PlayerScene, sword_bridge)
	suite.assert_true(arena.ok, "real weapon reward fixture binds native Player and Boss")
	if not arena.ok:
		stage.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var player: Node = arena.player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	arena.boss.set_physics_process(false)
	var config := _config("wanderer", "sword", ["stop", "rewind"], {})
	config.erase("meta_run_projection")
	config["challenge_reward_projection"] = projection
	suite.assert_true(player.configure_loadout(config), "real weapon fixture freezes canonical owned Walker Proof")
	await _actual_sword_frame(player, arena)
	_test_other_producers(player, arena.boss)
	_test_source_isolation(player, arena.boss, stage)
	player.configure_hostile_frame_participant(null)
	arena.effects.dispose_native_effects()
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _actual_sword_frame(player: Node, arena: Dictionary) -> void:
	var bridge: SwordHitBridge = arena.bridge
	bridge.source_player = player
	bridge.boss = arena.boss
	suite.assert_true(player.get("_hostile_frame_participant") == bridge and bridge.is_ready_for_frame(int(player.priority_arbitration_snapshot().frame) + 1), "actual Sword frame joins its original native hostile transaction")
	suite.assert_true(player.try_action(&"weapon_primary") and player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "actual Player commits authored Sword light attack")
	var remaining := 32
	while remaining > 0:
		var weapon: Dictionary = player.weapon_action_coordinator.snapshot()
		if weapon.phase == "WINDUP" and int(weapon.phase_frame) + 1 == int(weapon.plan.phases[weapon.phase_index].duration_frames):
			break
		suite.assert_true(player.advance_action_frame(), "actual Sword advances its authored windup")
		remaining -= 1
	suite.assert_true(remaining > 0, "actual Sword reaches authentic damage boundary")
	var boss_before: Dictionary = arena.boss.launch_transaction_snapshot()
	var player_before: Dictionary = player.full_player_replay_snapshot()
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not suite.expect_rejected_player_frame(player) and bridge.delivered > 0, "late World refusal observes actual production Sword attack")
	suite.assert_equal(arena.boss.launch_transaction_snapshot(), boss_before, "late World refusal restores reward-modified Boss damage")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "late World refusal restores actual Sword and equipped Player")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(), "actual production Sword retries accepted native frame")
	suite.assert_close(bridge.actual_damage, bridge.planned_damage * 1.15 - arena.boss.health.defense, "actual Sword producer receives authored fifteen-percent Boss damage")
	player.configure_hostile_frame_participant(null)


func _test_other_producers(player: Node, boss: Node) -> void:
	var hurtbox: Area2D = boss.get_node("Hurtbox")
	var extra_tags: Array[String] = []
	var producers: Array[Node] = [Arrow.new(), Bullet.new(), StaffBolt.new(), StaffZone.new(), Fist.new(), FistZone.new()]
	var weapons := ["BowWeapon", "GunWeapon", "StaffWeapon", "StaffWeapon", "GauntletsWeapon", "GauntletsWeapon"]
	for index: int in range(producers.size()):
		var producer: Node = producers[index]
		producer.set("owner_entity", player)
		producer.set("source", player.get_node(weapons[index]))
		producer.set("action_token", 100 + index)
		producer.set("outcome_index", index)
		if index >= 2:
			producer.set("generation", 10 + index)
		var hp_before: float = boss.health.current_hp
		match index:
			0: producer.call("_deliver_damage", hurtbox, 40.0, Damage.DamageType.PHYSICAL, false)
			1: producer.call("_deliver_damage", hurtbox, 40.0, Damage.DamageType.PHYSICAL, extra_tags)
			2: producer.call("_deliver_damage_to_target", boss, 40.0, "physical", Vector2.ZERO)
			3: producer.call("_damage_target", boss, 40.0, "physical")
			4: producer.call("_deliver_component", boss, {"amount": 40.0, "primary": false, "type": Damage.DamageType.PHYSICAL})
			5:
				producer.set("parameters", {"damage_multiplier": 1.0, "damage_type_split": {"physical": 1.0}})
				producer.set("base_attack", 40.0)
				producer.call("_deliver_damage", boss)
		suite.assert_close(hp_before - boss.health.current_hp, 46.0 - boss.health.defense, "real %s damage producer receives Walker Proof" % weapons[index])
		producer.free()


func _test_source_isolation(player: Node, boss: Node, stage: Node) -> void:
	var outsider := Node2D.new()
	stage.add_child(outsider)
	for run_id: String in ["legacy_run", "runtime", "other-run"]:
		var info := Damage.from_plan({"run_id": run_id, "target_id": str(boss.get_meta("stable_target_id")), "hostile_source_id": "foreign-proof", "attack_generation": 200, "action_token": 200, "amount": 40.0, "damage_type": Damage.DamageType.PHYSICAL, "source": outsider, "attacker": player, "tags": [], "can_crit": false})
		var before: Dictionary = boss.launch_runtime_snapshot()
		suite.assert_close(boss.health.call("_apply_target_damage_modifiers", info, 40.0), 40.0, "foreign source/run cannot borrow reward multiplier: " + run_id)
		suite.assert_close(boss.health.take_damage(info), 0.0, "foreign source/run cannot claim native body authority: " + run_id)
		suite.assert_equal(boss.launch_runtime_snapshot(), before, "foreign source/run preserves actual Boss HP and damage receipts: " + run_id)
	var info := Damage.from_plan({"run_id": "runtime", "target_id": str(boss.get_meta("stable_target_id")), "hostile_source_id": "source-proof", "attack_generation": 201, "action_token": 201, "amount": 40.0, "damage_type": Damage.DamageType.PHYSICAL, "source": player.get_node("SwordWeapon/Hitbox"), "attacker": player, "tags": [], "can_crit": false})
	suite.assert_close(boss.health.take_damage(info), 46.0 - boss.health.defense, "bound actual weapon descendant authenticates compatibility identity")
	var world := World.new()
	add_child(world)
	var foreign_player: Node = world.create_player()
	foreign_player.configure_run(&"weapon-proof")
	var config: Dictionary = player.loadout_runtime.snapshot()
	suite.assert_true(foreign_player.configure_loadout(config), "isolated replay-world Player carries same canonical reward/run fixture")
	var foreign_info := Damage.from_plan({"run_id": "runtime", "target_id": str(boss.get_meta("stable_target_id")), "hostile_source_id": "world-proof", "attack_generation": 202, "action_token": 202, "amount": 40.0, "damage_type": Damage.DamageType.PHYSICAL, "source": foreign_player.get_node("SwordWeapon/Hitbox"), "attacker": foreign_player, "tags": [], "can_crit": false})
	var before: Dictionary = boss.launch_runtime_snapshot()
	suite.assert_close(boss.health.call("_apply_target_damage_modifiers", foreign_info, 40.0), 40.0, "matching replay-world identity cannot borrow native-world reward multiplier")
	suite.assert_close(boss.health.take_damage(foreign_info), 0.0, "matching replay-world identity cannot claim native-world body authority")
	suite.assert_equal(boss.launch_runtime_snapshot(), before, "foreign replay-world source preserves actual Boss HP and damage receipts")
	world.queue_free()
