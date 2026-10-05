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
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Save := preload("res://scripts/save/save_service.gd")
var suite: RefCounted

class RefusingShieldActor:
	extends "res://scripts/enemies/launch/launch_hostile_actor.gd"
	var refuse_lethal := true
	func prepare_hostile_lethal_transition(info: RefCounted, amount: float) -> Dictionary:
		return {"ok": false} if refuse_lethal else super.prepare_hostile_lethal_transition(info, amount)

class WeaponHitBridge:
	extends "res://scripts/enemies/launch/hostile_frame_bridge.gd"
	var source_player: Node2D
	var victim: Node2D
	var delivered := 0
	func prepare_frame(ticket: Dictionary) -> bool:
		var hitbox: Node = source_player.get_node("SwordWeapon/Hitbox")
		if hitbox.is_active():
			delivered += 1
			victim.get_node("Hurtbox").receive_hit(hitbox.get("_active_damage_info").copy_for_source(hitbox))
		return super.prepare_frame(ticket)

class AnchorShieldBridge:
	extends "res://scripts/enemies/launch/hostile_frame_bridge.gd"
	var victim: Node2D
	var damage_info: RefCounted
	func prepare_frame(ticket: Dictionary) -> bool:
		victim.get_node("HealthComponent").take_damage(damage_info)
		return super.prepare_frame(ticket)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var actor := _actor()
	var health: Node = actor.get_node("HealthComponent")
	suite.assert_close(health.take_damage(_damage(1, 20.0)), 0.0, "native thirty-percent shield absorbs actual Health damage")
	suite.assert_close(health.current_hp, 160.0, "fully absorbed native hit cannot remove body HP")
	var state: Dictionary = actor.launch_affix_runtime_snapshot()
	suite.assert_true(state.has("shielded") and not state.get("shielded", {}).is_empty(), "native Shielded owns an authoritative absorption pool")
	if not state.has("shielded"):
		actor.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	suite.assert_close(state.shielded.current_pool, 28.0, "actual native hit consumes twenty from the authored forty-eight shield")
	suite.assert_close(health.take_damage(_damage(1, 20.0)), 0.0, "duplicate actual hit identity cannot consume shield again")
	suite.assert_equal(actor.launch_affix_runtime_snapshot(), state, "duplicate shield hit cannot mint a receipt or alter the pool")
	suite.assert_close(health.take_damage(_damage(2, 40.0)), 12.0, "broken shield retains exact overflow damage after absorption")
	suite.assert_close(health.current_hp, 148.0, "actual overflow removes only twelve body HP")
	suite.assert_close(actor.get_damage_taken_multiplier(), 1.20, "actual shield break grants bounded native exposure")
	suite.assert_close(health.take_damage(_damage(3, 10.0)), 12.0, "subsequent exposed native hit reaches body Health")
	var cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(actor.native_cold_snapshot(func(_source: Node): return {})).json).replay
	var twin := _actor()
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "typed cold Actor retains shield break clock and exact Health")
	suite.assert_equal(twin.launch_affix_runtime_snapshot(), actor.launch_affix_runtime_snapshot(), "cold shield pool and admission receipts are exact")
	var forged := cold.duplicate(true)
	forged.actor.affix_runtime.shielded.current_pool = 1.0
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "forged shield pool cannot diverge from admitted damage receipts")
	forged = cold.duplicate(true)
	forged.actor.affix_runtime.shielded.damage_claims.clear()
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "cold shield break cannot lose its original admitted damage")
	await _physical_roundtrip(actor)
	for frame: int in range(1, 45):
		_tick(actor, frame)
	suite.assert_close(actor.get_damage_taken_multiplier(), 1.20, "shield exposure retains its final authored frame")
	_tick(actor, 45)
	suite.assert_close(actor.get_damage_taken_multiplier(), 1.0, "shield exposure expires after forty-five frames")
	actor.apply_time_stop_source(&"stop:shield", 25.0)
	for frame: int in range(46, 1200):
		_tick(actor, frame)
	suite.assert_close(actor.launch_affix_runtime_snapshot().shielded.current_pool, 0.0, "shield regeneration cannot happen before its complete accepted-frame deadline")
	var before: Dictionary = actor.launch_transaction_snapshot()
	var prepared: Dictionary = actor.prepare_launch_frame(1200, _context(actor, 1200))
	suite.assert_true(prepared.ok and actor.commit_launch_frame(prepared.ticket) and actor.rollback_launch_frame(prepared.ticket), "refused shield regeneration candidate compensates its native clock")
	suite.assert_equal(actor.launch_transaction_snapshot(), before, "refused regeneration restores exact pool, Health and source claims")
	_tick(actor, 1200)
	suite.assert_close(actor.launch_affix_runtime_snapshot().shielded.current_pool, 48.0, "shield regenerates once at its complete unscaled deadline during Stop")
	suite.assert_true(actor.launch_affix_runtime_snapshot().shielded.regeneration_used, "native shield seals its once-only regeneration receipt")
	actor.clear_time_stop_source(&"stop:shield")
	suite.assert_close(health.take_damage(_damage(4, 50.0)), 2.0, "regenerated shield retains exact second-break overflow")
	for frame: int in range(1201, 2401):
		_tick(actor, frame)
	suite.assert_close(actor.launch_affix_runtime_snapshot().shielded.current_pool, 0.0, "second break cannot regenerate an unbounded shield")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().shielded.regenerated_frame, 1200, "second break cannot replace the authenticated regeneration identity")
	for target: Node2D in [actor, twin]:
		target.queue_free()
	await get_tree().process_frame
	await _test_damage_boundary()
	await _test_pairs_and_history()
	await _test_absorbed_anchor_control()
	await _test_outer_frame()
	await _test_actual_player_weapon_frame()
	await _test_presentation()
	suite.finish(get_tree())


func _actor(revision: int = -1, companion: String = "", refusing: bool = false) -> Node2D:
	var actor: Node2D = Scene.instantiate()
	if refusing:
		actor.set_script(RefusingShieldActor)
	add_child(actor)
	var affixes: Array = [Content.affix("shielded")]
	if not companion.is_empty():
		affixes.append(Content.affix(companion))
	var configured: Dictionary = actor.configure_launch_affixes(affixes, 3) if revision < 0 else actor.configure_launch_affixes(affixes, 3, revision)
	suite.assert_true(configured.ok, "canonical Shielded affix configures before actual elite body")
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := Fixture.identity()
	identity.hostile_source_id = "shielded-test"
	identity.seed = 42
	actor.set_meta("encounter_spawn_id", "shielded-test")
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), identity).ok, "native Shielded elite owns actual species and Health")
	actor.global_position = Vector2(100, 100)
	return actor


func _damage(generation: int, amount: float, tags: Array = ["weapon:sword"]) -> RefCounted:
	return Damage.from_plan({"run_id": "run-p15", "target_id": "shielded-test", "hostile_source_id": "player:1", "attack_generation": generation, "action_token": generation, "source_generation": generation, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": tags, "can_crit": false})


func _context(actor: Node2D, frame: int) -> Dictionary:
	var context := Fixture.context(frame)
	context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
	context.target_position = {"x": actor.global_position.x + 20000.0, "y": actor.global_position.y}
	return context


func _tick(actor: Node2D, frame: int) -> void:
	var prepared: Dictionary = actor.prepare_launch_frame(frame, _context(actor, frame))
	suite.assert_true(prepared.ok and actor.commit_launch_frame(prepared.ticket) and actor.publish_launch_frame(prepared.ticket), "native Shielded accepts frame%d" % frame)


func _test_damage_boundary() -> void:
	var actor := _actor()
	var health: Node = actor.get_node("HealthComponent")
	health.defense = 5.0
	suite.assert_close(health.take_damage(_damage(1, 25.0)), 0.0, "native shield consumes post-defense damage")
	suite.assert_close(actor.launch_affix_runtime_snapshot().shielded.current_pool, 28.0, "flat defense cannot be charged twice against the shield")
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	for wrong: Dictionary in [{"run_id": "other-run"}, {"target_id": "other-target"}, {"target_id": ""}, {"run_id": "legacy_run", "target_id": "pending_target"}]:
		var plan: Dictionary = _damage(99, 10.0).snapshot()
		plan.merge(wrong, true)
		suite.assert_close(health.take_damage(Damage.from_plan(plan)), 0.0, "invalid or unowned legacy shield identity refuses Health application")
		suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "invalid shield identity cannot spend a native receipt")
	actor.set("_shield_absorption_commit_fault_for_test", true)
	suite.assert_close(health.take_damage(_damage(2, 20.0)), 0.0, "failed actual absorption commit refuses Health application")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "failed native commit leaves shield and Health unchanged")
	actor.set("_shield_absorption_commit_fault_for_test", false)
	suite.assert_close(health.take_damage(_damage(2, 20.0)), 0.0, "same actual damage retries after commit failure")
	suite.assert_close(actor.launch_affix_runtime_snapshot().shielded.current_pool, 13.0, "retry spends post-defense shield once")
	var info: RefCounted = _damage(3, 5.0)
	var resolution: RefCounted = health.call("_resolve_damage", info)
	var decision: Dictionary = actor.prepare_post_defense_absorption(info, resolution)
	suite.assert_true(not actor.commit_post_defense_absorption(info, resolution, decision), "external code cannot commit a real shield decision without Health ownership")
	var fraction := _actor()
	suite.assert_close(fraction.get_node("HealthComponent").take_damage(_damage(1, 47.75)), 0.0, "native shield keeps fractional remaining absorption")
	suite.assert_close(fraction.get_node("HealthComponent").take_damage(_damage(2, 0.50)), 0.75, "post-defense shield overflow is not inflated by a second minimum-damage floor")
	var refusal := _actor(-1, "", true)
	before = refusal.native_cold_snapshot(func(_source: Node): return {})
	suite.assert_close(refusal.get_node("HealthComponent").take_damage(_damage(1, 1000.0)), 0.0, "later invalid native lethal decision refuses shield overflow")
	suite.assert_equal(refusal.native_cold_snapshot(func(_source: Node): return {}), before, "later lethal preflight failure compensates already committed absorption")
	refusal.set("refuse_lethal", false)
	suite.assert_close(refusal.get_node("HealthComponent").take_damage(_damage(1, 1000.0)), 952.0, "same real identity retries after compensated lethal refusal")
	suite.assert_true(refusal.launch_affix_runtime_snapshot().terminal and refusal.launch_affix_runtime_snapshot().shielded.current_pool == 0.0, "actual terminal Health publication closes the native shield")
	for target: Node2D in [actor, fraction, refusal]:
		target.queue_free()
	await get_tree().process_frame


func _test_pairs_and_history() -> void:
	var frenzy := _actor(-1, "frenzy")
	frenzy.get_node("HealthComponent").take_damage(_damage(1, 20.0))
	suite.assert_close(frenzy.launch_affix_runtime_snapshot().shielded.current_pool, 24.0, "Frenzy incoming multiplier applies before native absorption")
	var fortified := _actor(-1, "fortified")
	suite.assert_close(fortified.get_node("HealthComponent").max_hp, 240.0, "compatible Fortified retains actual native maximum HP")
	suite.assert_close(fortified.launch_affix_runtime_snapshot().shielded.current_pool, 72.0, "compatible Shielded scales from actual Fortified maximum HP")
	var nullified := _actor(-1, "nullified")
	nullified.apply_time_stop_source(&"stop:shield-nullified", 3.0)
	for frame: int in range(1, 32):
		_tick(nullified, frame)
	suite.assert_close(nullified.get_node("HealthComponent").take_damage(_damage(1, 60.0, ["weapon:staff", "echo"])), 24.0, "Nullified exposure and echo still reach actual Shielded absorption and overflow")
	suite.assert_close(nullified.get_damage_taken_multiplier(), 1.40, "compatible shield and Nullified exposure combine through existing incoming modifiers")
	var historical := _actor(4)
	suite.assert_close(historical.get_node("HealthComponent").take_damage(_damage(1, 20.0)), 20.0, "historical revision four retains metadata-only Shielded damage")
	suite.assert_true(not historical.launch_affix_runtime_snapshot().has("shielded"), "historical actor cannot silently acquire native shield receipts")
	suite.assert_true(not fortified.can_restore_native_cold_snapshot(historical.native_cold_snapshot(func(_source: Node): return {}), func(_binding: Dictionary): return null), "historical compiler signature cannot masquerade as current Shielded behavior")
	for target: Node2D in [frenzy, fortified, nullified, historical]:
		target.queue_free()
	await get_tree().process_frame


func _anchor_damage(generation: int, overrides: Dictionary = {}) -> RefCounted:
	var plan: Dictionary = _damage(generation, 1.0, ["weapon:gauntlets"]).snapshot()
	plan["control_effect"] = {"kind": "launch", "displacement_pixels": 48.0}
	plan.merge(overrides, true)
	return Damage.from_plan(plan)


func _test_absorbed_anchor_control() -> void:
	var actor := _actor(-1, "anchored")
	var health: Node = actor.get_node("HealthComponent")
	var body_facts: Dictionary = actor.launch_runtime_snapshot().runtime.mechanism_state.duplicate(true)
	var uncommitted: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	actor.set("_shield_absorption_commit_fault_for_test", true)
	health.take_damage(_anchor_damage(1))
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), uncommitted, "refused shield commit cannot retain absorbed Anchor control")
	actor.set("_shield_absorption_commit_fault_for_test", false)
	var result: RefCounted = health.resolve_and_apply_damage(_anchor_damage(1))
	suite.assert_true(result.is_prevented() and result.finalized_damage() == 0.0, "fully absorbed launch retains an honest zero-body prevented resolution")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 1, "authenticated absorbed launch admits one Anchored control")
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	health.take_damage(_anchor_damage(1))
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "duplicate absorbed launch cannot spend shield or admit poise")
	for entry: Dictionary in [{"action_token": 1}, {"source_generation": 1}, {"control_effect": {"kind": "launch", "displacement_pixels": -1.0}}, {"control_effect": {}}]:
		health.take_damage(_anchor_damage(100 + actor.launch_affix_runtime_snapshot().shielded.damage_claims.size(), entry))
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 1, "stale tokens and malformed absorbed control cannot mint Anchored poise")
	for generation: int in range(2, 5):
		health.take_damage(_anchor_damage(generation))
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.poise, 80, "four legitimate absorbed launches retain eighty Anchored poise")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.mechanism_state, body_facts, "absorbed launch cannot manufacture a native body damage fact")
	suite.assert_close(health.current_hp, 160.0, "absorbed launch control does not remove body Health")
	var cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(actor.native_cold_snapshot(func(_source: Node): return {})).json).replay
	var twin := _actor(-1, "anchored")
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_source: Dictionary): return null), "typed cold pair reconstruction retains absorbed weapon controls")
	suite.assert_equal(twin.native_cold_snapshot(func(_source: Node): return {}), actor.native_cold_snapshot(func(_source: Node): return {}), "cold pair keeps exact shield, poise and token receipts")
	var ordinary := _actor()
	ordinary.get_node("HealthComponent").take_damage(_anchor_damage(1))
	suite.assert_equal(ordinary.get_weapon_hit_control_snapshot_for_test().claim_count, 0, "Shielded without Anchored retains existing fully absorbed control policy")
	var overflowing := _actor(-1, "anchored")
	suite.assert_close(overflowing.get_node("HealthComponent").take_damage(_anchor_damage(1, {"amount": 60.0})), 12.0, "partial absorbed launch retains normal body overflow")
	suite.assert_equal(overflowing.launch_affix_runtime_snapshot().anchored.control_count, 1, "overflow launch cannot admit poise twice through absorption and Health")
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(600, 100)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var bridge := AnchorShieldBridge.new()
	bridge.victim = actor
	bridge.damage_info = _anchor_damage(5)
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects) and player.configure_hostile_frame_participant(bridge), "real Player frame owns fully absorbed threshold rollback")
	before = actor.native_cold_snapshot(func(_source: Node): return {})
	var player_before: Dictionary = player.full_player_replay_snapshot()
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not player.advance_action_frame(), "late World refusal compensates absorbed Shielded Anchored threshold")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "outer refusal restores exact shield, poise, recovery and control identity")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "outer absorbed-control refusal restores complete actual Player")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(), "original absorbed threshold retries after real World refusal")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.control_count, 5, "accepted retry admits exactly five absorbed controls")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.poise, 0, "fifth absorbed control spends the authored hundred poise")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().anchored.recovery_remaining_frames, 19, "threshold owns twenty recovery frames and spends the accepted candidate once")
	suite.assert_close(health.current_hp, 160.0, "fully absorbed accepted threshold keeps actual Health intact")
	await _physical_roundtrip(actor)
	player.configure_hostile_frame_participant(null)
	for target: Node in [actor, twin, ordinary, overflowing, player, root]:
		target.queue_free()
	await get_tree().process_frame


func _test_outer_frame() -> void:
	var actor := _actor()
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(600, 100)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "actual hostile bridge owns native shield frame compensation")
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var ticket: Dictionary = bridge.begin_frame(1)
	actor.get_node("HealthComponent").take_damage(_damage(1, 60.0))
	suite.assert_true(bridge.prepare_frame(ticket) and bridge.rollback_frame(ticket), "rejected outer Player candidate compensates shield break and overflow")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "outer rejection restores exact Health, shield pool and claim identity")
	ticket = bridge.begin_frame(1)
	suite.assert_close(actor.get_node("HealthComponent").take_damage(_damage(1, 60.0)), 12.0, "original native shield hit retries after enclosing frame refusal")
	suite.assert_true(bridge.prepare_frame(ticket), "native shield retry prepares the accepted frame")
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	suite.assert_true(not publication.is_empty() and bridge.finalize_frame_publication(publication) and bridge.seal_frame_publication(publication), "actual shield frame publishes only after Health and hostile participants seal")
	bridge.publish_prepared_frame()
	suite.assert_equal(actor.launch_affix_runtime_snapshot().shielded.damage_claims.size(), 1, "accepted outer retry publishes one native shield admission")
	await _physical_roundtrip(actor)
	for target: Node in [actor, player, root]:
		target.queue_free()
	await get_tree().process_frame


func _physical_roundtrip(actor: Node2D) -> void:
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("elite_shielded")
	var binding := ContentSnapshot.snapshot(registry)
	var storage := Save.new()
	storage.configure(root, "test-shielded", binding)
	var state: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var encoded := Replay.encode_replay_json(state)
	suite.assert_true(encoded.ok and storage.save_profile("shielded_v5", "base", {"codec": encoded.json}).ok, "actual SaveService retains typed native shield aggregate")
	var fresh := Save.new()
	fresh.configure(root, "test-shielded", binding)
	var primary: Variant = fresh.inspect_profile("shielded_v5", "base")
	suite.assert_true(primary.ok and Replay.decode_replay_json(primary.payload.payload.codec).replay == state, "fresh physical recovery authenticates exact native shield Health and receipt state")


func _test_actual_player_weapon_frame() -> void:
	var actor := _actor()
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(600, 100)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(player.configure_loadout({"milestone": "LAUNCH", "seed": 42, "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH")}), "actual configured Player owns the production Launch Sword damage producer")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var bridge := WeaponHitBridge.new()
	bridge.source_player = player
	bridge.victim = actor
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects) and player.configure_hostile_frame_participant(bridge), "actual Sword frame binds native shield and late World compensation")
	suite.assert_true(player.try_action(&"weapon_primary") and player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "actual Sword creates a committed native light attack")
	var countdown := 32
	while countdown > 0:
		var weapon: Dictionary = player.weapon_action_coordinator.snapshot()
		if weapon.phase == "WINDUP" and int(weapon.phase_frame) + 1 == int(weapon.plan.phases[weapon.phase_index].duration_frames):
			break
		suite.assert_true(player.advance_action_frame(), "actual Sword advances every authored preparation frame")
		countdown -= 1
	suite.assert_true(countdown > 0, "actual Sword reaches its authentic active-frame boundary")
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var player_before: Dictionary = player.full_player_replay_snapshot()
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not player.advance_action_frame(), "late World fault rejects actual Sword-produced shield damage")
	suite.assert_true(bridge.delivered > 0, "native shield refusal fixture delivered the actual production Sword DamageInfo")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "late actual Player rejection restores shield pool, claims and Health")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "late shield rejection restores the complete actual Player and Sword state")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(), "original actual Sword frame retries after World rejection")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().shielded.damage_claims.size(), 1, "actual Sword retry admits exactly one native shield receipt")
	suite.assert_true(actor.launch_affix_runtime_snapshot().shielded.current_pool < 48.0, "actual production Sword reaches Shielded absorption")
	suite.assert_close(actor.get_node("HealthComponent").current_hp, 160.0, "actual fully absorbed Sword leaves body Health intact")
	player.configure_hostile_frame_participant(null)
	for target: Node in [actor, player, root]:
		target.queue_free()
	await get_tree().process_frame


func _test_presentation() -> void:
	var actor := _actor()
	var cue := actor.get_node_or_null("EliteShieldCue")
	suite.assert_true(cue != null and cue.visible, "native Shielded owns the authored gold shield contour")
	if cue == null:
		actor.queue_free()
		await get_tree().process_frame
		return
	suite.assert_equal(cue.get_snapshot().phase, "INTACT", "gold contour presents the intact native shield")
	await _capture("intact")
	actor.get_node("HealthComponent").take_damage(_damage(1, 60.0))
	suite.assert_equal(cue.get_snapshot().phase, "BROKEN", "actual shield break presents a distinct cracked contour")
	await _capture("broken")
	var before: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var old_contrast: bool = GameState.get_setting("high_contrast_danger", false)
	var old_scale: float = GameState.get_setting("enemy_telegraph_scale", 1.0)
	GameState.set_setting("high_contrast_danger", true)
	GameState.set_setting("enemy_telegraph_scale", 1.5)
	actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
	suite.assert_true(cue.get_snapshot().high_contrast and cue.get_snapshot().visual_scale == 1.5, "native gold contour honors danger accessibility settings")
	suite.assert_equal(actor.native_cold_snapshot(func(_source: Node): return {}), before, "shield accessibility cannot alter accepted absorption state")
	await _capture("broken-high-contrast")
	GameState.set_setting("high_contrast_danger", old_contrast)
	GameState.set_setting("enemy_telegraph_scale", old_scale)
	actor.queue_free()
	await get_tree().process_frame
	var pair := _actor(-1, "nullified")
	pair.apply_time_stop_source(&"stop:shield-presentation", 3.0)
	for frame: int in range(1, 32):
		_tick(pair, frame)
	pair.get_node("HealthComponent").take_damage(_damage(1, 60.0))
	GameState.set_setting("high_contrast_danger", true)
	GameState.set_setting("enemy_telegraph_scale", 1.5)
	pair.project_runtime_snapshot(pair.launch_runtime_snapshot())
	suite.assert_true(pair.get_node("EliteAffixCue").position.distance_to(pair.get_node("EliteShieldCue").position) >= 40.0, "compatible clock and shield cues retain separate enlarged geometry")
	await _capture("nullified-pair-high-contrast")
	GameState.set_setting("high_contrast_danger", old_contrast)
	GameState.set_setting("enemy_telegraph_scale", old_scale)
	pair.queue_free()
	await get_tree().process_frame


func _capture(pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		suite.assert_equal(pixels.get_size(), resolution, "native shield capture retains the requested viewport")
		var ratio := resolution.x / 640.0
		var cue_pixels := 0
		var background := pixels.get_pixel(0, 0)
		for y: int in range(int(42 * ratio), int(86 * ratio)):
			for x: int in range(int(60 * ratio), int(144 * ratio)):
				if pixels.get_pixel(x, y).is_equal_approx(background):
					continue
				cue_pixels += 1
		suite.assert_true(cue_pixels > 15, "actual native shield cue raster is nonblank inside its framed bounds")
		var output := "res://build/visual-evidence/native-elite-affixes/shielded-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native Shielded screenshot retained")
