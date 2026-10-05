extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Fixture := preload("res://tests/support/p15_action_fixtures.gd")
const Scene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const Player := preload("res://scenes/player/player.tscn")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Bow := preload("res://scenes/combat/player_arrow.tscn")
const Gun := preload("res://scenes/combat/gun_projectile.tscn")
const Staff := preload("res://scenes/combat/staff_projectile.tscn")
const Gauntlets := preload("res://scripts/combat/gauntlets_hit_execution.gd")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const ReplayWorld := preload("res://scripts/replay/player_replay_world.gd")
const BossScene := preload("res://data/content_packs/base/assets/bosses/launch/boss_time_sovereign.tscn")
const BossDefinition := preload("res://scripts/enemies/launch/boss_definition.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Save := preload("res://scripts/save/save_service.gd")
var suite: RefCounted

class RecordingActor:
	extends "res://scripts/enemies/launch/launch_hostile_actor.gd"
	var producer_info: RefCounted
	func prepare_post_defense_absorption(info: RefCounted, resolution: RefCounted) -> Dictionary:
		producer_info = info
		return super.prepare_post_defense_absorption(info, resolution)


class SwordBridge:
	extends "res://scripts/enemies/launch/hostile_frame_bridge.gd"
	var victim: Node2D
	var attacker: Node2D
	var produced := false
	func prepare_frame(ticket: Dictionary) -> bool:
		var hitbox: Node = attacker.get_node("SwordWeapon/Hitbox")
		if hitbox.is_active():
			produced = true
			var info: RefCounted = hitbox.get("_active_damage_info").copy_for_source(hitbox)
			victim.get_node("Hurtbox").receive_hit(info)
			victim.health.take_damage(info)
		return super.prepare_frame(ticket)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for weapon: String in ["bow", "gun", "staff", "gauntlets"]:
		await _test_producer(weapon)
	await _test_actual_sword_rollback()
	await _test_historical_claims_and_capacity()
	await _test_native_burn()
	await _test_semantic_ally_damage()
	await _test_partial_shield_atomicity()
	await _test_irreversible_compensation()
	await _test_boss_capacity()
	suite.finish(get_tree())


func _actor(id: String = "body-test", species: String = "shattered_sentinel", shielded: bool = false) -> Node2D:
	var actor: Node2D = Scene.instantiate()
	actor.set_script(RecordingActor)
	add_child(actor)
	actor.set_meta("encounter_spawn_id", id)
	actor.set_meta("stable_target_id", 417)
	var parser := Definition.new()
	parser.configure(Content.enemy(species))
	if shielded:
		suite.assert_true(actor.configure_launch_affixes([Content.affix("shielded")], 3).ok, "partial body fixture configures actual native shield")
	var identity := Fixture.identity()
	identity.hostile_source_id = id
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite" if shielded else "enemy"), identity).ok, "actual native body victim configures")
	return actor


func _test_producer(weapon: String) -> void:
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "real Player configures production " + weapon)
	var source: Node = player.get_node(weapon.capitalize() + "Weapon")
	var actor := _actor()
	var producer: Node
	match weapon:
		"bow": producer = Bow.instantiate()
		"gun": producer = Gun.instantiate()
		"staff": producer = Staff.instantiate()
		"gauntlets": producer = Gauntlets.new()
	producer.set("source", source)
	producer.set("owner_entity", player)
	producer.set("action_token", 7)
	if weapon in ["staff", "gauntlets"]:
		producer.set("generation", 7)
		producer.set("source_action_id", "projectile" if weapon == "staff" else "punch_1")
	if weapon in ["bow", "gun"]:
		producer.set("attack_tags", ["weapon:" + weapon])
	producer.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(producer)
	var observations: Array[float] = []
	actor.health.damaged.connect(func(amount: float, _hp: float):
		observations.append(amount)
		suite.assert_close(actor.health.current_hp, actor.launch_runtime_snapshot().runtime.mechanism_state.hp_after, "native body and species commit before actual " + weapon + " observer")
		suite.assert_true(actor.native_cold_snapshot(func(_node: Node): return {}).is_empty(), "in-flight " + weapon + " observation cannot export a native cold checkpoint")
		if observations.size() == 1:
			suite.assert_close(actor.health.take_damage(actor.get("producer_info")), 0.0, "reentrant " + weapon + " observation cannot mint body damage")
	)
	var empty_tags: Array[String] = []
	match weapon:
		"bow": producer.call("_deliver_damage", actor.get_node("Hurtbox"), 20.0, Damage.DamageType.PHYSICAL, false)
		"gun": producer.call("_deliver_damage", actor.get_node("Hurtbox"), 20.0, Damage.DamageType.PHYSICAL, empty_tags)
		"staff": producer.call("_deliver_damage_to_target", actor, 20.0, "fire", Vector2.ZERO)
		"gauntlets": producer.call("_deliver_component", actor, {"amount": 20.0, "primary": true, "type": Damage.DamageType.PHYSICAL})
	var info: RefCounted = actor.get("producer_info")
	suite.assert_true(info != null and info.is_valid(), "real " + weapon + " producer reaches actual Health")
	suite.assert_close(actor.health.current_hp, 60.0, "real " + weapon + " producer settles initial body damage")
	if info != null:
		var binding := func(node: Node): return {"path": str(player.get_path_to(node))}
		var resolver := func(value: Dictionary): return player.get_node_or_null(NodePath(value.path))
		var before: Dictionary = actor.native_cold_snapshot(binding)
		suite.assert_close(actor.health.take_damage(info), 0.0, "duplicate " + weapon + " body identity refuses before HP mutation")
		suite.assert_close(actor.health.current_hp, 60.0, "duplicate " + weapon + " body delivery cannot drift HP")
		suite.assert_equal(observations.size(), 1, "duplicate " + weapon + " body delivery cannot publish another damaged event")
		suite.assert_equal(actor.native_cold_snapshot(binding), before, "duplicate " + weapon + " keeps complete native cold state exact")
		var plan: Dictionary = info.snapshot()
		plan.run_id = "run-p15"
		plan.target_id = "body-test"
		actor.health.take_damage(Damage.from_plan(plan))
		suite.assert_equal(actor.native_cold_snapshot(binding), before, "canonical " + weapon + " receipt excludes run and target alias replay")
		var rogue := Node.new()
		add_child(rogue)
		for invalid: String in ["source", "attacker", "target", "run"]:
			plan = info.snapshot()
			plan.attack_generation += 10
			plan.run_id = "run-p15"
			plan.target_id = "body-test"
			match invalid:
				"source": plan.source = rogue
				"attacker": plan.attacker = rogue
				"target": plan.target_id = "target:other-body"
				"run": plan.run_id = "foreign-run"
			suite.assert_close(actor.health.take_damage(Damage.from_plan(plan)), 0.0, "real " + weapon + " rejects unowned " + invalid + " before body mutation")
			suite.assert_equal(actor.native_cold_snapshot(binding), before, "real " + weapon + " invalid " + invalid + " cannot drift native state")
		plan = info.snapshot()
		plan.attack_generation += 20
		var fresh := Damage.from_plan(plan)
		var decision: Dictionary = actor.prepare_hostile_body_damage(fresh, 20.0, {})
		suite.assert_true(decision.get("ok", false), "fresh " + weapon + " body admission prepares without mutation")
		suite.assert_true(not actor.commit_hostile_body_damage(fresh, 20.0, {}, decision), "public " + weapon + " call cannot forge Health-owned body commit")
		actor.set("_body_damage_commit_fault_for_test", true)
		suite.assert_close(actor.health.take_damage(fresh), 0.0, "injected " + weapon + " body commit refusal is atomic")
		suite.assert_equal(actor.native_cold_snapshot(binding), before, "refused " + weapon + " commit retains HP and every native claim")
		actor.set("_body_damage_commit_fault_for_test", false)
		var foreign_world := ReplayWorld.new()
		add_child(foreign_world)
		var foreign: Node = foreign_world.create_player()
		foreign.process_mode = Node.PROCESS_MODE_DISABLED
		foreign.configure_run(&"run-p15")
		plan = info.snapshot()
		plan.attack_generation += 30
		plan.source = foreign.get_node(weapon.capitalize() + "Weapon")
		plan.attacker = foreign
		actor.health.take_damage(Damage.from_plan(plan))
		suite.assert_equal(actor.native_cold_snapshot(binding), before, "foreign replay " + weapon + " Player cannot damage a different native world")
		foreign_world.queue_free()
		rogue.queue_free()
		if weapon in ["bow", "gun"]:
			if weapon == "bow":
				producer.call("_deliver_damage", actor.get_node("Hurtbox"), 5.0, Damage.DamageType.TIME, true)
			else:
				producer.call("_deliver_damage", actor.get_node("Hurtbox"), 5.0, Damage.DamageType.TIME, empty_tags)
			suite.assert_close(actor.health.current_hp, 55.0, "real " + weapon + " same-generation Time component settles independently")
			suite.assert_close(actor.launch_runtime_snapshot().runtime.mechanism_state.hp_after, 55.0, "real " + weapon + " Time component keeps body and species HP aligned")
			before = actor.native_cold_snapshot(binding)
			actor.health.take_damage(actor.get("producer_info"))
			suite.assert_equal(actor.native_cold_snapshot(binding), before, "real " + weapon + " Time component retains its own once-only receipt")
		var cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(actor.native_cold_snapshot(binding)).json).replay
		var twin := _actor()
		suite.assert_true(twin.restore_native_cold_snapshot(cold, resolver), "real " + weapon + " body state reconstructs typed cold invariant")
		suite.assert_equal(twin.native_cold_snapshot(binding), cold, "real " + weapon + " body receipts survive exact cold reconstruction")
		_physical_roundtrip(cold)
		twin.health.take_damage(info)
		suite.assert_equal(twin.native_cold_snapshot(binding), cold, "restored " + weapon + " body receipt still refuses its original producer identity")
		twin.queue_free()
	for node: Node in [actor, producer, player]:
		node.queue_free()
	await get_tree().process_frame


func _fixture_world(actors: Array, weapon: String = "staff") -> Dictionary:
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(600, 100)
	player.health.acquire_invulnerability_source(&"body_fixture")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "actual body effect fixture binds production " + weapon)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), actors, effects) and player.configure_hostile_frame_participant(bridge), "native body effect fixture binds actual whole-frame authority")
	return {"player": player, "root": root, "effects": effects, "bridge": bridge}


func _test_native_burn() -> void:
	var actor := _actor()
	var world := _fixture_world([actor])
	var source: Node = world.player.get_node("StaffWeapon")
	suite.assert_true(actor.apply_elemental_status(&"burn", &"staff:body-burn", 2, 4, 7.0, 1, -1.0, source, world.player), "actual native status retains registered Staff and real Player handles")
	suite.assert_true(world.player.advance_action_frame(), "actual native Staff burn settles through sealed Actor and shared Router")
	suite.assert_close(actor.health.current_hp, 73.0, "registered native Staff burn removes seven real body HP")
	suite.assert_close(actor.launch_runtime_snapshot().runtime.mechanism_state.hp_after, 73.0, "native Staff burn keeps species HP aligned")
	var info: RefCounted = actor.get("producer_info")
	suite.assert_true(info != null and info.source == source and info.attacker == world.player and info.tags.has("status:burn"), "actual Router retains native Staff burn identity and authority")
	var binding := func(node: Node): return {"path": str(world.player.get_path_to(node))}
	var resolver := func(value: Dictionary): return world.player.get_node_or_null(NodePath(value.path))
	var cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(actor.native_cold_snapshot(binding)).json).replay
	var twin := _actor()
	suite.assert_true(twin.restore_native_cold_snapshot(cold, resolver), "typed native Staff burn keeps damage receipt and live source binding")
	_physical_roundtrip(cold)
	if info != null:
		twin.health.take_damage(info)
		suite.assert_equal(twin.native_cold_snapshot(binding), cold, "restored native Staff burn cannot apply original tick twice")
	var player_before: Dictionary = world.player.full_player_replay_snapshot()
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not world.player.advance_action_frame(), "late World refusal compensates second real Staff burn tick")
	suite.assert_equal(actor.native_cold_snapshot(binding), cold, "burn refusal restores actual HP, status clock and native receipts")
	suite.assert_equal(world.player.full_player_replay_snapshot(), player_before, "burn refusal restores complete actual Player")
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(world.player.advance_action_frame(), "same native Staff burn tick retries after full compensation")
	suite.assert_close(actor.health.current_hp, 66.0, "retried Staff burn tick settles once")
	for node: Node in [actor, twin, world.player, world.root]:
		node.queue_free()
	await get_tree().process_frame


func _test_semantic_ally_damage() -> void:
	var victim := _actor()
	victim.global_position = Vector2(140, 100)
	victim.apply_time_stop_source(&"body_zone_fixture", 5.0)
	var owner := _actor("body:bramble", "bramble_mage")
	owner.global_position = Vector2(100, 100)
	var context := Fixture.context(0)
	context.source_position = {"x": 100.0, "y": 100.0}
	context.target_position = {"x": 140.0, "y": 100.0}
	suite.assert_true(owner.get("_launch_runtime").request_action("bramble_mage.bramble_growth", context).ok, "actual native Bramble Mage owns its authored zone action")
	var world := _fixture_world([owner, victim])
	var applied := false
	for _frame: int in range(60):
		suite.assert_true(world.player.advance_action_frame(), "actual native Bramble zone advances its authored warning")
		if victim.health.current_hp < 80.0:
			applied = true
			break
	suite.assert_true(applied, "actual shared semantic Router delivers authored friendly zone damage")
	suite.assert_close(victim.health.current_hp, 72.0, "native Bramble zone deals eight real ally body damage")
	suite.assert_close(victim.launch_runtime_snapshot().runtime.mechanism_state.hp_after, 72.0, "source-free semantic ally damage keeps species and body HP aligned")
	suite.assert_close(owner.health.current_hp, owner.health.max_hp, "native Bramble caster keeps authored owner immunity")
	var info: RefCounted = victim.get("producer_info")
	suite.assert_true(info != null and info.source == null and info.attacker == null and info.run_id == &"run-p15", "actual native semantic zone retains source-free run-owned damage identity")
	var cold: Dictionary = victim.native_cold_snapshot(func(_node: Node): return {})
	var twin := _actor()
	suite.assert_true(twin.restore_native_cold_snapshot(Replay.decode_replay_json(Replay.encode_replay_json(cold).json).replay, func(_value: Dictionary): return null), "native ally-zone damage reconstructs actual cold body contract")
	if info != null:
		victim.health.take_damage(info)
		suite.assert_equal(victim.native_cold_snapshot(func(_node: Node): return {}), cold, "actual semantic ally-zone duplicate cannot drift HP or receipts")
	for node: Node in [owner, victim, twin, world.player, world.root]:
		node.queue_free()
	await get_tree().process_frame


func _test_partial_shield_atomicity() -> void:
	var actor := _actor("body-test", "shattered_sentinel", true)
	var world := _fixture_world([actor], "sword")
	var info := Damage.from_plan({"run_id": "runtime", "target_id": "body-test", "hostile_source_id": "player:body-shield", "attack_generation": 1, "action_token": 1, "amount": 60.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "source": world.player.get_node("SwordWeapon"), "attacker": world.player, "can_crit": false})
	var before: Dictionary = actor.native_cold_snapshot(func(_node: Node): return {})
	actor.set("_body_damage_commit_fault_for_test", true)
	suite.assert_close(actor.health.take_damage(info), 0.0, "partial native shield body-commit failure refuses damage")
	suite.assert_equal(actor.native_cold_snapshot(func(_node: Node): return {}), before, "partial native shield refusal refunds absorption pool and its claim")
	suite.assert_true(not actor.health.hostile_body_application_is_active(), "body commit refusal leaves no transient Health application ownership")
	actor.set("_body_damage_commit_fault_for_test", false)
	suite.assert_close(actor.health.take_damage(info), 12.0, "same partial native shield hit retries its remaining twelve body damage")
	suite.assert_close(actor.health.current_hp, 148.0, "partial native shield overflow keeps actual body HP")
	suite.assert_close(actor.launch_runtime_snapshot().runtime.mechanism_state.hp_after, 148.0, "partial native shield overflow keeps species HP aligned")
	var accepted: Dictionary = actor.native_cold_snapshot(func(_node: Node): return {})
	actor.health.take_damage(info)
	suite.assert_equal(actor.native_cold_snapshot(func(_node: Node): return {}), accepted, "partial native shield retry admits absorption and body exactly once")
	for node: Node in [actor, world.player, world.root]:
		node.queue_free()
	await get_tree().process_frame


func _test_actual_sword_rollback() -> void:
	var actor := _actor()
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(600, 100)
	player.health.acquire_invulnerability_source(&"body_fixture")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "actual native body probe configures production Sword")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var bridge := SwordBridge.new()
	bridge.victim = actor
	bridge.attacker = player
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects) and player.configure_hostile_frame_participant(bridge), "actual Sword body probe binds full Player/native transaction")
	suite.assert_true(player.try_action(&"weapon_primary") and player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "real Sword accepts authored light action")
	var countdown := 32
	while countdown > 0:
		var state: Dictionary = player.weapon_action_coordinator.snapshot()
		if state.phase == "WINDUP" and int(state.phase_frame) + 1 == int(state.plan.phases[state.phase_index].duration_frames):
			break
		suite.assert_true(player.advance_action_frame(), "real Sword advances body probe preparation")
		countdown -= 1
	suite.assert_true(countdown > 0, "real Sword reaches authored body-hit boundary")
	var before: Dictionary = actor.native_cold_snapshot(func(_node: Node): return {})
	var player_before: Dictionary = player.full_player_replay_snapshot()
	var observations: Array[float] = []
	actor.health.damaged.connect(func(amount: float, _hp: float): observations.append(amount))
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not player.advance_action_frame() and bridge.produced, "late World refusal rejects actual Sword-produced repeated body hit")
	suite.assert_equal(actor.native_cold_snapshot(func(_node: Node): return {}), before, "late Sword refusal refunds body HP, native claims and controls")
	suite.assert_true(not actor.health.hostile_body_application_is_active() and actor.health.get("_hostile_body_commit_context").is_empty(), "late Sword compensation retains no transient native body receipt ownership")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "late Sword refusal restores complete actual Player")
	suite.assert_true(observations.is_empty(), "refused real Sword publishes no damaged observations")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(), "same actual Sword body receipt retries its original accepted frame")
	suite.assert_equal(observations.size(), 1, "actual Sword duplicate settles exactly one native body observation")
	suite.assert_close(actor.health.current_hp, actor.launch_runtime_snapshot().runtime.mechanism_state.hp_after, "accepted real Sword leaves body and species HP aligned")
	for node: Node in [actor, player, root]:
		node.queue_free()
	await get_tree().process_frame


func _physical_roundtrip(cold: Dictionary) -> void:
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var directory := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if directory.is_empty():
		directory = ProjectSettings.globalize_path("res://build/test-evidence/native-body-userdata")
	directory = directory.path_join("native_body")
	var binding := ContentSnapshot.snapshot(registry)
	var service := Save.new()
	service.configure(directory, "test-body", binding)
	var encoded := Replay.encode_replay_json({"actor": cold})
	suite.assert_true(encoded.ok and service.save_profile("native_body_v2", "base", {"codec": encoded.json}).ok, "actual SaveService writes typed native body receipt fixture")
	var fresh := Save.new()
	fresh.configure(directory, "test-body", binding)
	var recovered: Variant = fresh.inspect_profile("native_body_v2", "base")
	suite.assert_true(recovered.ok and Replay.decode_replay_json(recovered.payload.payload.codec).replay.actor == cold, "fresh physical recovery retains exact typed native body fixture")


func _test_irreversible_compensation() -> void:
	var actor := _actor()
	var plan := {"run_id": "run-p15", "target_id": "body-test", "hostile_source_id": "domain:irreversible", "attack_generation": 1, "action_token": 1, "source_generation": 1, "amount": 3.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["irreversible"], "can_crit": false}
	suite.assert_close(actor.health.take_damage(Damage.from_plan(plan)), 3.0, "actual native Health settles one run-owned irreversible body loss")
	var accepted: Dictionary = actor.native_cold_snapshot(func(_node: Node): return {})
	plan.hit_index = 1
	suite.assert_close(actor.health.take_damage(Damage.from_plan(plan)), 0.0, "existing irreversible ledger denies a new body hit index for the same source claim")
	suite.assert_equal(actor.native_cold_snapshot(func(_node: Node): return {}), accepted, "irreversible refusal compensates newly prepared native body state exactly")
	suite.assert_true(not actor.health.hostile_body_application_is_active() and actor.health.get("_hostile_body_commit_context").is_empty(), "irreversible refusal closes all transient native body ownership")
	actor.queue_free()
	await get_tree().process_frame


func _test_boss_capacity() -> void:
	var actor: Node2D = BossScene.instantiate()
	add_child(actor)
	actor.global_position = Vector2(100, 100)
	var parser := BossDefinition.new()
	parser.configure(Content.boss("time_sovereign"))
	var identity := Fixture.identity()
	identity.hostile_source_id = "body-boss"
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok, "actual native Boss configures strict body ledger capacity")
	var runtime: RefCounted = actor.get("_launch_runtime")
	for index: int in range(10000):
		suite.assert_true(runtime.accept_damage_fact({"fact_id": "body-boss-capacity:%d" % index, "runtime_frame": 0, "target_source_id": "body-boss", "amount": 0.000001, "hp_after": float(actor.health.max_hp) - float(index + 1) * 0.000001}).ok, "native Boss accepts bounded fixture receipt %d" % index)
	actor.health.current_hp = float(runtime.snapshot().mechanism_state.hp_current)
	var before: Dictionary = actor.native_cold_snapshot(func(_node: Node): return {})
	var info := Damage.from_plan({"run_id": "run-p15", "target_id": "body-boss", "hostile_source_id": "domain:boss-capacity", "attack_generation": 10001, "action_token": 10001, "amount": 1.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})
	suite.assert_close(actor.health.take_damage(info), 0.0, "10001st actual native Boss body receipt refuses its finite admission boundary")
	suite.assert_equal(actor.native_cold_snapshot(func(_node: Node): return {}), before, "full native Boss body ledger refuses without evicting settled identities or changing HP")
	suite.assert_true(actor.restore_native_cold_snapshot(Replay.decode_replay_json(Replay.encode_replay_json(before).json).replay, func(_binding: Dictionary): return null), "full native Boss body state reconstructs strict typed cold contract")
	actor.queue_free()
	await get_tree().process_frame


func _test_historical_claims_and_capacity() -> void:
	var actor := _actor()
	var info := Damage.from_plan({"run_id": "run-p15", "target_id": "body-test", "hostile_source_id": "player:historic", "attack_generation": 1, "action_token": 1, "amount": 20.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})
	var runtime: RefCounted = actor.get("_launch_runtime")
	var old_id := JSON.stringify(["run-p15", "body-test", "player:historic", 1, 0]).sha256_text()
	suite.assert_true(runtime.accept_damage_fact({"fact_id": old_id, "runtime_frame": 0, "target_source_id": "body-test", "amount": 20.0, "hp_after": 60.0}).ok, "historical species fixture records its original opaque single-component identity")
	actor.health.current_hp = 60.0
	var historical: Dictionary = actor.native_cold_snapshot(func(_node: Node): return {})
	var twin := _actor()
	suite.assert_true(twin.restore_native_cold_snapshot(historical, func(_binding: Dictionary): return null), "current native body boundary retains exact historical cold state")
	twin.health.take_damage(info)
	var plan: Dictionary = info.snapshot()
	plan.damage_type = Damage.DamageType.TIME
	twin.health.take_damage(Damage.from_plan(plan))
	suite.assert_equal(twin.native_cold_snapshot(func(_node: Node): return {}), historical, "historical accepted identity retains original shared component exclusion")
	for index: int in range(1, 4096):
		var hp: float = 60.0 - float(index) * 0.000001
		suite.assert_true(runtime.accept_damage_fact({"fact_id": "body-capacity:%d" % index, "runtime_frame": 0, "target_source_id": "body-test", "amount": 0.000001, "hp_after": hp}).ok, "native species accepts bounded fixture receipt %d" % index)
	actor.health.current_hp = float(runtime.snapshot().mechanism_state.hp_after)
	var full: Dictionary = actor.native_cold_snapshot(func(_node: Node): return {})
	suite.assert_true(twin.restore_native_cold_snapshot(full, func(_binding: Dictionary): return null), "full4096-receipt native species state reconstructs typed contract")
	plan.attack_generation = 4097
	plan.damage_type = Damage.DamageType.PHYSICAL
	suite.assert_close(actor.health.take_damage(Damage.from_plan(plan)), 0.0, "4097th actual Health receipt refuses before native capacity drift")
	suite.assert_equal(actor.native_cold_snapshot(func(_node: Node): return {}), full, "full native body claim capacity cannot mutate Health or domain state")
	for node: Node in [actor, twin]:
		node.queue_free()
	await get_tree().process_frame
