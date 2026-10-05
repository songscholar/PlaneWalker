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
const Chaining := preload("res://scripts/enemies/launch/launch_elite_chaining_runtime.gd")
var suite: RefCounted

class DamageBridge:
	extends "res://scripts/enemies/launch/hostile_frame_bridge.gd"
	var victim: Node2D
	var attacker: Node2D
	var damage_frames: Array[int] = [1]
	var amount := 1.0
	var repeated := false
	var produced_facts: Array[Dictionary] = []
	func prepare_frame(ticket: Dictionary) -> bool:
		if int(ticket.runtime_frame) in damage_frames:
			var info := Damage.from_plan({"source": attacker, "attacker": attacker, "run_id": "runtime", "target_id": str(victim.hostile_source_id), "hostile_source_id": "player:chaining", "attack_generation": int(ticket.runtime_frame), "action_token": int(ticket.runtime_frame), "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false})
			if info == null or not info.is_valid():
				return false
			victim.get_node("HealthComponent").take_damage(info)
			if repeated:
				victim.get_node("HealthComponent").take_damage(info)
		var accepted := super.prepare_frame(ticket)
		if accepted:
			for actor: Node2D in _actors.values():
				for fact: Dictionary in actor.prepared_launch_frame_batch().get("hit_facts", []):
					produced_facts.append(fact.duplicate(true))
		return accepted

class SwordBridge:
	extends "res://scripts/enemies/launch/hostile_frame_bridge.gd"
	var victim: Node2D
	var attacker: Node2D
	var delivered := 0
	func prepare_frame(ticket: Dictionary) -> bool:
		var hitbox: Node = attacker.get_node("SwordWeapon/Hitbox")
		if hitbox.is_active():
			delivered += 1
			victim.get_node("Hurtbox").receive_hit(hitbox.get("_active_damage_info").copy_for_source(hitbox))
		return super.prepare_frame(ticket)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _test_two_allies_and_timing()
	await _test_whole_player_rollback()
	await _test_authentication_and_history()
	await _test_strongest_and_native_attack()
	await _test_actual_sword_frame()
	await _test_pair_presentation()
	await _test_terminal_and_no_allies()
	await _test_outside_frame_lifetime()
	_test_bounded_receipts()
	suite.finish(get_tree())


func _actor(id: String, position: Vector2, affix: String = "", revision: int = -1, companion: String = "") -> Node2D:
	var actor: Node2D = Scene.instantiate()
	add_child(actor)
	actor.global_position = position
	if not affix.is_empty():
		if revision < 0 and OS.get_environment("ELITE_CHAINING_TEST_REVISION") == "7":
			revision = 7
		var rows: Array = [Content.affix(affix)]
		if not companion.is_empty():
			rows.append(Content.affix(companion))
		var installed: Dictionary = actor.configure_launch_affixes(rows, 3) if revision < 0 else actor.configure_launch_affixes(rows, 3, revision)
		suite.assert_true(installed.ok, "native %s affix configures" % affix)
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := Fixture.identity()
	identity.hostile_source_id = id
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite" if not affix.is_empty() else "enemy"), identity).ok, "native ally/source %s configures" % id)
	return actor


func _world(actors: Array, source: Node2D, actual_sword: bool = false) -> Dictionary:
	var player: Node2D = Player.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(600, 100)
	player.health.acquire_invulnerability_source(&"chaining_fixture")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var bridge: RefCounted = SwordBridge.new() if actual_sword else DamageBridge.new()
	bridge.victim = source
	bridge.attacker = player
	suite.assert_true(bridge.configure(player, Registry.new(), actors, effects) and player.configure_hostile_frame_participant(bridge), "real Player binds whole native source and recipient transaction")
	return {"player": player, "root": root, "effects": effects, "bridge": bridge}


func _attack(actor: Node2D) -> float:
	return float(actor.get("_launch_runtime").control_modifiers().get("attack_multiplier", 1.0))


func _test_two_allies_and_timing() -> void:
	var source := _actor("chain:source", Vector2(100, 100), "chaining")
	var a := _actor("chain:a", Vector2(120, 100))
	var b := _actor("chain:b", Vector2(100, 120))
	var c := _actor("chain:c", Vector2(160, 100))
	var far := _actor("chain:far", Vector2(197, 100))
	var actors := [source, a, b, c, far]
	for actor: Node2D in actors:
		suite.assert_true(actor.get("_launch_runtime").add_control_source("fixture_pause", "stop", 500, 1.0), "fixture pauses primary actions without stopping accepted clocks")
	var world := _world(actors, source)
	world.bridge.damage_frames.assign([1, 2, 120, 121])
	suite.assert_true(world.player.advance_action_frame(), "first actual Player damage and native grant settle together")
	suite.assert_close(source.get_node("HealthComponent").current_hp, 159.0, "first grant is backed by actual accepted Player body damage")
	suite.assert_close(_attack(a), 1.15, "nearest first ally gets authored attack buff")
	suite.assert_close(_attack(b), 1.15, "distance tie uses stable ally identity and grants second buff")
	suite.assert_close(_attack(c), 1.0, "third nearby ally exceeds recipient cap")
	suite.assert_close(_attack(far), 1.0, "97 pixel ally is outside authored96 pixel radius")
	suite.assert_close(_attack(source), 1.0, "Chaining never buffs its own owner")
	var state: Dictionary = source.launch_affix_runtime_snapshot().get("chaining", {})
	suite.assert_true(not state.is_empty(), "Chaining needs authentic bounded damage and grant receipts")
	if not state.is_empty():
		suite.assert_equal(state.grants.size(), 1, "accepted Health damage owns one grant")
		if not state.grants.is_empty():
			suite.assert_equal(state.grants[0].recipients.map(func(row: Dictionary): return row.id), ["chain:a", "chain:b"], "native grant retains deterministic selected recipient identities")
			suite.assert_true(not source.get("_affix_runtime").accept_chaining_player_damage(1, str(state.grants[0].fact_id), {"x": 100.0, "y": 100.0}), "replayed accepted damage receipt cannot create another grant")
			suite.assert_equal(source.launch_affix_runtime_snapshot().chaining, state, "duplicate Chaining identity leaves complete source state unchanged")
	var cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(source.native_cold_snapshot(func(_node: Node): return {})).json).replay
	var twin := _actor("chain:source", Vector2(100, 100), "chaining")
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "typed source cold state retains accepted grant identity and cooldown")
	suite.assert_equal(twin.launch_affix_runtime_snapshot(), source.launch_affix_runtime_snapshot(), "source grant and damage receipt state reconstruct exactly")
	if cold.actor.affix_runtime.has("chaining"):
		for corruption: String in ["erase_grant", "future_settlement", "outside_radius", "self_recipient", "pending_settlement"]:
			var forged := cold.duplicate(true)
			match corruption:
				"erase_grant": forged.actor.affix_runtime.chaining.grants.clear()
				"future_settlement": forged.actor.affix_runtime.chaining.grants[0].settled_frame = 2
				"outside_radius": forged.actor.affix_runtime.chaining.grants[0].recipients[0].position.x = 300.0
				"self_recipient": forged.actor.affix_runtime.chaining.grants[0].recipients[0].id = "chain:source"
				"pending_settlement": forged.actor.affix_runtime.chaining.grants[0].settled_frame = -1
			suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "cold Chaining refuses forged %s" % corruption)
	var ally_cold: Dictionary = Replay.decode_replay_json(Replay.encode_replay_json(a.native_cold_snapshot(func(_node: Node): return {})).json).replay
	var ally_twin := _actor("chain:a", Vector2(120, 100))
	suite.assert_true(ally_twin.restore_native_cold_snapshot(ally_cold, func(_binding: Dictionary): return null), "typed recipient cold state retains actual control authority")
	suite.assert_close(_attack(ally_twin), 1.15, "restored native recipient retains strongest-only attack buff")
	suite.assert_equal(ally_twin.native_cold_snapshot(func(_node: Node): return {}), ally_cold, "recipient control identity and expiry reconstruct exactly")
	await _physical_roundtrip([cold, ally_cold])
	ally_twin.queue_free()
	twin.queue_free()
	for frame: int in range(2, 91):
		suite.assert_true(world.player.advance_action_frame(), "native accepted Chaining clock advances frame %d" % frame)
	suite.assert_close(_attack(a), 1.15, "buff remains effective through all90 accepted frames while Stop is active")
	suite.assert_true(world.player.advance_action_frame(), "native buff expires on frame91")
	suite.assert_close(_attack(a), 1.0, "buff expires before frame91 action preparation")
	for frame: int in range(92, 122):
		suite.assert_true(world.player.advance_action_frame(), "native cooldown advances frame %d" % frame)
	suite.assert_close(_attack(a), 1.15, "new accepted damage at frame121 renews buff after complete120-frame cooldown")
	state = source.launch_affix_runtime_snapshot().get("chaining", {})
	if not state.is_empty():
		suite.assert_equal(state.grants.size(), 2, "cooldown hits at2 and120 cannot mint grants")
	await _presentation(source, world, actors)
	await _dispose(world, actors)


func _test_whole_player_rollback() -> void:
	var source := _actor("chain:rollback", Vector2(100, 100), "chaining")
	var ally := _actor("chain:ally", Vector2(120, 100))
	var world := _world([source, ally], source)
	var before: Array = [source.native_cold_snapshot(func(_node: Node): return {}), ally.native_cold_snapshot(func(_node: Node): return {})]
	var player_before: Dictionary = world.player.full_player_replay_snapshot()
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not world.player.advance_action_frame(), "late World rejection compensates actual source and selected native ally")
	suite.assert_equal(source.native_cold_snapshot(func(_node: Node): return {}), before[0], "late refusal refunds source Health, damage identity and cooldown")
	suite.assert_equal(ally.native_cold_snapshot(func(_node: Node): return {}), before[1], "late refusal refunds actual recipient control and full native state")
	suite.assert_equal(world.player.full_player_replay_snapshot(), player_before, "late Chaining refusal restores complete Player")
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(world.player.advance_action_frame(), "original Player frame retries original Chaining identity")
	suite.assert_close(_attack(ally), 1.15, "retried accepted grant admits actual ally buff once")
	await _dispose(world, [source, ally])


func _test_authentication_and_history() -> void:
	var source := _actor("chain:auth", Vector2(100, 100), "chaining")
	var ally := _actor("chain:auth-ally", Vector2(120, 100))
	var world := _world([source, ally], source)
	world.bridge.damage_frames.clear()
	var info := Damage.from_plan({"source": world.player, "attacker": world.player, "run_id": "runtime", "target_id": "chain:auth", "hostile_source_id": "player:chaining", "attack_generation": 999, "action_token": 999, "amount": 1.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false})
	suite.assert_true(info != null and info.is_valid(), "ownership refusal probe uses valid immutable Player damage")
	source.apply_weapon_hit_control(info, 1.0)
	suite.assert_true(world.player.advance_action_frame(), "forged public control call cannot claim accepted Health damage")
	suite.assert_close(_attack(ally), 1.0, "public Actor call outside Health ownership cannot grant Chaining")
	var rogue := Node.new()
	add_child(rogue)
	for mode: String in ["rogue_source", "rogue_attacker", "wrong_target", "missing_target", "prevented"]:
		var plan: Dictionary = info.snapshot()
		plan.attack_generation += 1 + ["rogue_source", "rogue_attacker", "wrong_target", "missing_target", "prevented"].find(mode)
		match mode:
			"rogue_source": plan.source = rogue
			"rogue_attacker": plan.attacker = rogue
			"wrong_target": plan.target_id = "chain:other"
			"missing_target": plan.target_id = ""
			"prevented": source.get_node("HealthComponent").invulnerable = true
		source.get_node("HealthComponent").take_damage(Damage.from_plan(plan))
		source.get_node("HealthComponent").invulnerable = false
	suite.assert_true(world.player.advance_action_frame(), "nonowned and prevented damage cannot mint native grants")
	suite.assert_close(_attack(ally), 1.0, "source/attacker/target/prevention refusal retains recipient attack")
	rogue.queue_free()
	await _dispose(world, [source, ally])
	var historical := _actor("chain:history", Vector2(100, 100), "chaining", 7)
	suite.assert_equal(historical.launch_affix_snapshot().pending_ids, ["chaining"], "historical revision7 keeps Chaining metadata-only")
	suite.assert_true(not historical.launch_affix_runtime_snapshot().has("chaining"), "historical revision7 cannot fabricate a native grant ledger")
	historical.queue_free()
	await get_tree().process_frame


func _test_strongest_and_native_attack() -> void:
	for stronger: bool in [false, true]:
		var source := _actor("chain:attack", Vector2(100, 100), "chaining")
		var ally := _actor("chain:attacker", Vector2(120, 100))
		var world := _world([source, ally], source)
		if stronger:
			suite.assert_true(ally.get("_launch_runtime").add_control_source("fixture_stronger", "attack_buff", 100, 1.20), "existing stronger source installs native attack control")
		var context := Fixture.context(0)
		context.source_position = {"x": 120.0, "y": 100.0}
		context.target_position = {"x": 140.0, "y": 100.0}
		suite.assert_true(ally.get("_launch_runtime").request_action("shattered_sentinel.shield_sweep", context).ok, "actual ally owns its ordinary authored30-frame warning")
		for frame: int in range(1, 32):
			suite.assert_true(world.player.advance_action_frame(), "actual native attack advances authored warning frame %d" % frame)
		var multiplier := 1.20 if stronger else 1.15
		suite.assert_close(_attack(ally), multiplier, "Chaining uses strongest attack source instead of stacking multipliers")
		var facts: Array = world.bridge.produced_facts.filter(func(row: Dictionary): return row.hostile_source_id == "chain:attacker")
		suite.assert_true(not facts.is_empty(), "real native recipient emits ordinary authored hit facts")
		if not facts.is_empty():
			suite.assert_close(float(facts[0].damage), 12.0 * multiplier, "real ordinary12-damage action uses strongest multiplier once")
		await _dispose(world, [source, ally])


func _test_actual_sword_frame() -> void:
	var source := _actor("chain:sword", Vector2(100, 100), "chaining")
	var ally := _actor("chain:sword-ally", Vector2(120, 100))
	var world := _world([source, ally], source, true)
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(world.player.configure_loadout({"milestone": "LAUNCH", "seed": 42, "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH")}), "actual configured Player owns native production Sword")
	suite.assert_true(world.player.try_action(&"weapon_primary") and world.player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "production Sword commits actual light action")
	var countdown := 32
	while countdown > 0:
		var weapon: Dictionary = world.player.weapon_action_coordinator.snapshot()
		if weapon.phase == "WINDUP" and int(weapon.phase_frame) + 1 == int(weapon.plan.phases[weapon.phase_index].duration_frames):
			break
		suite.assert_true(world.player.advance_action_frame(), "production Sword advances authored preparation")
		countdown -= 1
	suite.assert_true(countdown > 0, "production Sword reaches actual active boundary")
	var before: Array = [source.native_cold_snapshot(func(_node: Node): return {}), ally.native_cold_snapshot(func(_node: Node): return {})]
	var player_before: Dictionary = world.player.full_player_replay_snapshot()
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not world.player.advance_action_frame(), "late World refusal rejects actual Sword-produced Chaining damage")
	suite.assert_true(world.bridge.delivered > 0, "actual native Sword DamageInfo reached hostile Hurtbox")
	suite.assert_equal(source.native_cold_snapshot(func(_node: Node): return {}), before[0], "actual Sword refusal restores source HP, claims and cooldown")
	suite.assert_equal(ally.native_cold_snapshot(func(_node: Node): return {}), before[1], "actual Sword refusal restores native recipient control")
	suite.assert_equal(world.player.full_player_replay_snapshot(), player_before, "actual Sword refusal restores complete Player action")
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(world.player.advance_action_frame(), "original actual Sword frame retries Chaining once")
	suite.assert_close(_attack(ally), 1.15, "accepted production Sword activates real Chaining recipient")
	suite.assert_equal(source.launch_affix_runtime_snapshot().chaining.grants.size(), 1, "production Sword owns one accepted native grant")
	await _dispose(world, [source, ally])


func _test_pair_presentation() -> void:
	var actor := _actor("chain:pair", Vector2(300, 160), "chaining", -1, "nullified")
	var old_contrast: bool = GameState.get_setting("high_contrast_danger", false)
	var old_scale: float = GameState.get_setting("enemy_telegraph_scale", 1.0)
	GameState.set_setting("high_contrast_danger", true)
	GameState.set_setting("enemy_telegraph_scale", 1.5)
	actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
	var chaining: Node2D = actor.get_node("EliteChainingCue")
	var nullified: Node2D = actor.get_node("EliteAffixCue")
	suite.assert_true(chaining.position.distance_to(nullified.position) >= 40.0, "compatible enlarged linked-lightning and clock fragment cues retain separate geometry")
	await _capture(actor, "nullified-pair-high-contrast")
	GameState.set_setting("high_contrast_danger", old_contrast)
	GameState.set_setting("enemy_telegraph_scale", old_scale)
	actor.queue_free()
	await get_tree().process_frame


func _test_terminal_and_no_allies() -> void:
	for lethal: bool in [false, true]:
		var source := _actor("chain:terminal", Vector2(100, 100), "chaining")
		var ally := _actor("chain:terminal-ally", Vector2(120, 100))
		var actors: Array = [source, ally] if lethal else [source]
		var world := _world(actors, source)
		if lethal:
			world.bridge.amount = 1000.0
		suite.assert_true(world.player.advance_action_frame(), "accepted native trigger settles finite terminal or no-ally outcome")
		var state: Dictionary = source.launch_affix_runtime_snapshot()
		suite.assert_equal(state.chaining.grants.size(), 1, "no-allies and lethal triggers retain one bounded cooldown receipt")
		if lethal:
			suite.assert_true(state.terminal and not source.get_node("EliteChainingCue").visible, "final death closes source grant admission and linked-lightning projection")
			suite.assert_close(_attack(ally), 1.15, "accepted lethal Player damage still grants its finite ally buff")
			suite.assert_true(not source.native_cold_snapshot(func(_node: Node): return {}).is_empty(), "terminal source retains accepted grant receipt in cold state")
			for frame: int in range(2, 92):
				suite.assert_true(world.player.advance_action_frame(), "orphan-free recipient clock retires finite post-death buff frame %d" % frame)
			suite.assert_close(_attack(ally), 1.0, "source death cannot turn90-frame ally buff into permanent control")
		else:
			suite.assert_equal(state.chaining.grants[0].recipients, [], "no eligible native allies seals an empty finite grant")
		await _dispose(world, [source, ally])


func _test_bounded_receipts() -> void:
	var state := Chaining.initial_state()
	var position := {"x": 100.0, "y": 100.0}
	for index: int in range(4096):
		suite.assert_true(Chaining.accept_damage(state, 1, str(index).sha256_text(), position), "bounded domain admits distinct receipt %d" % index)
	suite.assert_true(Chaining.settle_grant(state, 1, "0".sha256_text(), []), "bounded source seals its only eligible same-frame grant")
	var identity := {"runtime_frame": 0, "hostile_source_id": "chain:capacity"}
	suite.assert_true(Chaining.can_restore(state, identity, 1), "full4096 receipt ledger remains authentic reconstructible state")
	var before := state.duplicate(true)
	suite.assert_true(not Chaining.accept_damage(state, 1, "overflow".sha256_text(), position), "4097th source receipt refuses without unbounded growth")
	suite.assert_equal(state, before, "capacity refusal preserves exact bounded source ledger")


func _test_outside_frame_lifetime() -> void:
	for lethal: bool in [false, true]:
		var source := _actor("chain:outside", Vector2(100, 100), "chaining")
		var ally := _actor("chain:outside-ally", Vector2(120, 100))
		var world := _world([source, ally], source)
		world.bridge.damage_frames.clear()
		var info := Damage.from_plan({"source": world.player, "attacker": world.player, "run_id": "runtime", "target_id": "chain:outside", "hostile_source_id": "player:outside", "attack_generation": 2000, "action_token": 2000, "amount": 1000.0 if lethal else 1.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false})
		suite.assert_true(source.get_node("HealthComponent").take_damage(info) > 0.0, "actual outside-frame Health damage reaches native source")
		if not lethal:
			suite.assert_true(source.native_cold_snapshot(func(_node: Node): return {}).is_empty(), "pending native ally selection cannot become accepted cold state")
		suite.assert_true(world.player.advance_action_frame(), "next native frame advances after outside-frame Health settlement")
		suite.assert_close(_attack(ally), 1.0 if lethal else 1.15, "alive deferred source grants once; immediate retired source closes pending work")
		if lethal:
			var state: Dictionary = source.launch_affix_runtime_snapshot()
			suite.assert_true(state.terminal and state.chaining.grants[0].recipients.is_empty() and state.chaining.grants[0].settled_frame == 0, "immediate retirement seals pending receipt with no ownerless grant")
		suite.assert_true(not source.native_cold_snapshot(func(_node: Node): return {}).is_empty(), "settled or retired outside-frame source retains valid native cold state")
		await _dispose(world, [source, ally])


func _physical_roundtrip(states: Array) -> void:
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("elite_chaining")
	var binding := ContentSnapshot.snapshot(registry)
	var service := Save.new()
	service.configure(root, "test-chaining", binding)
	var encoded := Replay.encode_replay_json({"actors": states})
	suite.assert_true(encoded.ok and service.save_profile("chaining_v8", "base", {"codec": encoded.json}).ok, "actual SaveService retains source and recipient Chaining aggregate")
	var fresh := Save.new()
	fresh.configure(root, "test-chaining", binding)
	var recovered: Variant = fresh.inspect_profile("chaining_v8", "base")
	suite.assert_true(recovered.ok and Replay.decode_replay_json(recovered.payload.payload.codec).replay.actors == states, "fresh physical recovery authenticates exact source and recipient typed state")


func _presentation(source: Node2D, world: Dictionary, actors: Array) -> void:
	var cue := source.get_node_or_null("EliteChainingCue")
	suite.assert_true(cue != null and cue.visible and cue.get_snapshot().phase == "TRIGGERED", "accepted source damage projects linked-lightning icon and triggered state")
	if cue == null:
		return
	await _capture(source, "triggered")
	var old_contrast: bool = GameState.get_setting("high_contrast_danger", false)
	var old_scale: float = GameState.get_setting("enemy_telegraph_scale", 1.0)
	var before: Dictionary = source.native_cold_snapshot(func(_node: Node): return {})
	GameState.set_setting("high_contrast_danger", true)
	GameState.set_setting("enemy_telegraph_scale", 1.5)
	source.project_runtime_snapshot(source.launch_runtime_snapshot())
	suite.assert_true(cue.get_snapshot().high_contrast and cue.get_snapshot().visual_scale == 1.5, "native linked-lightning cue honors danger accessibility settings")
	suite.assert_equal(source.native_cold_snapshot(func(_node: Node): return {}), before, "Chaining presentation cannot mutate source Health or grant receipts")
	await _capture(source, "triggered-high-contrast")
	for _frame: int in range(16):
		suite.assert_true(world.player.advance_action_frame(), "native cue derives bounded cooldown from accepted clock")
	suite.assert_equal(cue.get_snapshot().phase, "COOLDOWN", "linked-lightning cue distinguishes source cooldown")
	await _capture(source, "cooldown-high-contrast")
	GameState.set_setting("high_contrast_danger", old_contrast)
	GameState.set_setting("enemy_telegraph_scale", old_scale)
	for actor: Node2D in actors:
		actor.project_runtime_snapshot(actor.launch_runtime_snapshot())


func _capture(actor: Node2D, pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		suite.assert_equal(pixels.get_size(), resolution, "native Chaining capture retains requested viewport")
		var cue: Node2D = actor.get_node("EliteChainingCue")
		var ratio := resolution.x / 640.0
		var centre: Vector2 = cue.global_position * ratio
		var radius := Vector2(16, 12) * cue.scale * ratio
		var visible_pixels := 0
		for y: int in range(maxi(0, int(centre.y - radius.y)), mini(pixels.get_height(), int(centre.y + radius.y))):
			for x: int in range(maxi(0, int(centre.x - radius.x)), mini(pixels.get_width(), int(centre.x + radius.x))):
				var ink := pixels.get_pixel(x, y)
				if (ink.r > 0.70 and ink.g > 0.70 and ink.b > 0.70) if cue.get_snapshot().high_contrast else (ink.r > 0.80 and ink.g > 0.75 and ink.b < 0.50):
					visible_pixels += 1
		suite.assert_true(visible_pixels > 10, "native linked-lightning pixels render in authored icon bounds")
		var output := "res://build/visual-evidence/native-elite-affixes/chaining-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native Chaining screenshot retained")


func _dispose(world: Dictionary, actors: Array) -> void:
	world.player.configure_hostile_frame_participant(null)
	for actor: Node2D in actors:
		actor.queue_free()
	world.player.queue_free()
	world.root.queue_free()
	await get_tree().process_frame
