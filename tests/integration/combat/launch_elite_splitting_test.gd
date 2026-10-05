extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Scene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
const Player := preload("res://scenes/player/player.tscn")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Save := preload("res://scripts/save/save_service.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Rules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")
var suite: RefCounted

class TerminalBridge:
	extends "res://scripts/enemies/launch/hostile_frame_bridge.gd"
	var victim: Node2D
	var armed := false
	var sword_victim: Node2D
	var produced := false
	func prepare_frame(ticket: Dictionary) -> bool:
		if armed:
			var info := Damage.from_plan({"run_id": "run-splitting", "target_id": "split-owner", "hostile_source_id": "domain:splitting-terminal", "attack_generation": 1, "action_token": 1, "amount": 1000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})
			if victim.health.take_damage(info) <= 0.0:
				return false
		var hitbox: Node = _player.get_node("SwordWeapon/Hitbox")
		if is_instance_valid(sword_victim) and hitbox.is_active():
			produced = true
			sword_victim.get_node("Hurtbox").receive_hit(hitbox.get("_active_damage_info").copy_for_source(hitbox))
		return super.prepare_frame(ticket)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var world := _world()
	await get_tree().physics_frame
	suite.assert_close(world.actor.health.max_hp, 160.0, "actual Splitting mother keeps elite HP distinct from ordinary80HP base")
	await _capture(world, "mother")
	world.bridge.armed = true
	_assert_late_rollback(world, "actual native mother death and paired reservation")
	suite.assert_true(world.player.advance_action_frame(), "actual elite final native body death accepts complete Player frame")
	world.bridge.armed = false
	suite.assert_true(world.actor.health.dead and world.actor.health.current_hp == 0.0 and world.actor.launch_runtime_snapshot().runtime.terminal, "Splitting reservation requires actual final native death")
	var rows: Array = world.effects.summon_snapshot().rows
	suite.assert_true(rows.size() == 2 and rows.all(func(row: Dictionary): return row.phase == "WARNING" and row.spawn_warning_frames == 30 and row.lifetime_frames == 480 and not row.retire_on_owner_death), "final native Splitting death reserves exactly two ordinary child warnings before mother retirement")
	if rows.size() == 2:
		await _capture(world, "warning")
		await _test_cold(world, "warning")
		for _frame: int in range(2, 31):
			suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().is_empty(), "orphan copies retain every accepted spawn-warning frame")
		_assert_late_rollback(world, "actual two ordinary copy births")
		suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().size() == 2, "full30-frame warning materializes exactly two native ordinary copy bodies")
		for child: Node2D in world.effects.native_summon_actors().values():
			suite.assert_close(child.health.max_hp, 26.4, "actual ordinary Sentinel copy has33% ordinary80HP")
			suite.assert_close(child.get("_launch_definition").actions[0].hit_schedule[0].damage, 12.0, "actual copy retains full ordinary damage")
			suite.assert_true(child.launch_affix_snapshot().is_empty() and child.get_meta("summoned") and not child.get_meta("reward_eligible"), "actual copy has no recursive affix or independent reward")
		await _capture(world, "active")
		await _test_cold(world, "active")
		await _test_attack_and_sword(world)
	await _dispose(world)
	if OS.get_environment("ELITE_SPLITTING_TEST_REVISION") != "9":
		await _test_external_death_and_lifetime()
		await _test_blocked_admission()
		await _test_paired_cues()
		await _test_every_legal_parent()
		await _test_global_capacity()
		await _test_prevented_and_nonlethal()
	suite.finish(get_tree())


func _world(companion: String = "", revision: int = -1, enemy_id: String = "shattered_sentinel") -> Dictionary:
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var scene: PackedScene = Scene if enemy_id == "shattered_sentinel" else load("res://data/content_packs/base/assets/enemies/launch/enemy_%s.tscn" % enemy_id)
	var actor := scene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(320, 180)
	var rows: Array = [Content.affix("splitting")]
	if not companion.is_empty():
		rows.append(Content.affix(companion))
	if revision < 0 and OS.get_environment("ELITE_SPLITTING_TEST_REVISION") == "9":
		revision = 9
	var configured: Dictionary = actor.configure_launch_affixes(rows, 5) if revision < 0 else actor.configure_launch_affixes(rows, 5, revision)
	suite.assert_true(configured.ok, "actual Splitting source compiles before its native elite")
	var parser := Definition.new()
	parser.configure(Content.enemy(enemy_id))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), {"run_id": "run-splitting", "hostile_source_id": "split-owner", "next_generation_floor": 1, "runtime_frame": 0, "seed": 43}).ok, "actual Splitting native elite configures")
	var template := {}
	for candidate: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if candidate.id == "room_combat_open_field":
			template = candidate
	suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "actual Splitting owns validated native room motion")
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-splitting")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 43}), "actual Splitting Player owns production Sword profile")
	player.global_position = Vector2(600, 300)
	player.health.acquire_invulnerability_source(&"splitting_fixture")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-splitting", 0) and effects.configure_native_payloads(root) and effects.configure_native_summon_room(room, template), "actual Splitting shared authority owns native orphan fallback room")
	var bridge := TerminalBridge.new()
	bridge.victim = actor
	var registry := Registry.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects) and player.configure_hostile_frame_participant(bridge), "actual Splitting binds full Player native frame authority")
	return {"room": room, "actor": actor, "player": player, "root": root, "effects": effects, "bridge": bridge, "registry": registry, "enemy_id": enemy_id}


func _dispose(world: Dictionary) -> void:
	world.player.configure_hostile_frame_participant(null)
	world.effects.dispose_native_effects()
	for node: Variant in [world.actor, world.player, world.root, world.room] + world.get("extra_owners", []):
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame


func _cold(world: Dictionary) -> Dictionary:
	var children := {}
	for source: String in world.effects.native_summon_actors():
		children[source] = world.effects.native_summon_actors()[source].native_cold_snapshot(func(_source: Node): return {})
	return {"player": world.player.full_player_replay_snapshot(), "actor": world.actor.native_cold_snapshot(func(_source: Node): return {}) if is_instance_valid(world.actor) else {}, "children": children, "effects": world.effects.launch_transaction_snapshot(), "threats": world.registry.snapshot()}


func _assert_late_rollback(world: Dictionary, label: String) -> void:
	var before := _cold(world)
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not suite.expect_rejected_player_frame(world.player), "late World rejection refuses " + label)
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_equal(_cold(world), before, "late World rejection restores complete Player, mother, children and work: " + label)


func _test_cold(world: Dictionary, label: String) -> void:
	var encoded: Dictionary = Replay.encode_replay_json(_cold(world))
	suite.assert_true(encoded.ok, "native copy %s aggregate admits typed persistence" % label)
	if not encoded.ok:
		return
	var value: Dictionary = Replay.decode_replay_json(encoded.json).replay
	for mutation: String in ["erased_claim", "foreign_owner", "parent", "hp", "third_slot", "future", "warning", "ttl", "revision", "pair"]:
		var forged: Dictionary = value.effects.duplicate(true)
		match mutation:
			"erased_claim": forged.summons.claims.clear()
			"foreign_owner": forged.summons.rows[0].parent_source_id = "foreign-owner"
			"parent": forged.summons.rows[0].parent_definition_id = "void_spore"
			"hp": forged.summons.rows[0].projection.max_hp += 1.0
			"third_slot": forged.summons.rows[0].slot_index = 2
			"future": forged.summons.rows[0].request_frame += 1
			"warning": forged.summons.rows[0].spawn_warning_frames = 29
			"ttl": forged.summons.rows[0].lifetime_frames = 479
			"revision": forged.summons.rows[0].projection.copy_contract.origin_affixes.native_revision = 9
			"pair": forged.summons.rows.pop_back()
		suite.assert_true(not world.effects.can_restore_launch_transaction_snapshot(forged), "native copy cold rejects " + mutation)
	var twin := _world("", -1, str(world.enemy_id))
	twin.player.configure_hostile_frame_participant(null)
	var restored: bool = twin.player.restore_full_player_replay_snapshot(value.player)
	var owners := {}
	var actors: Array = []
	if not value.actor.is_empty():
		restored = twin.actor.restore_native_cold_snapshot(value.actor, func(_binding: Dictionary): return null) and restored
		owners["split-owner"] = twin.actor
		actors.append(twin.actor)
	else:
		twin.actor.free()
		twin.actor = null
	restored = twin.effects.bind_native_targets(owners, {"player:1": twin.player}) and twin.effects.restore_native_summon_snapshot(value.effects.summons) and restored
	if restored:
		for source: String in value.children:
			restored = twin.effects.native_summon_actors()[source].restore_native_cold_snapshot(value.children[source], func(_binding: Dictionary): return null) and restored
		restored = twin.effects.restore_launch_transaction_snapshot(value.effects) and twin.bridge.configure(twin.player, twin.registry, actors, twin.effects) and twin.bridge.call("_restore_registry", value.threats) and twin.player.configure_hostile_frame_participant(twin.bridge) and restored
	suite.assert_true(restored, "fresh native %s copy aggregate reconstructs dead mother and real orphan children" % label)
	if restored:
		suite.assert_equal(_cold(twin), value, "fresh native %s copy retains exact typed aggregate" % label)
		suite.assert_true(twin.player.advance_action_frame(), "fresh native %s copy accepts original next frame" % label)
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var directory := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("elite_splitting")
	var binding := ContentSnapshot.snapshot(registry)
	var service := Save.new()
	service.configure(directory, "test-splitting", binding)
	var slot := "split_" + label.sha256_text().substr(0, 20)
	suite.assert_true(service.save_profile(slot, "base", {"codec": encoded.json}).ok, "actual SaveService writes native copy aggregate: " + label)
	var fresh := Save.new()
	fresh.configure(directory, "test-splitting", binding)
	var recovered = fresh.inspect_profile(slot, "base")
	suite.assert_true(recovered.ok and Replay.decode_replay_json(recovered.payload.payload.codec).replay == value, "physical copy recovery retains exact state")
	await _dispose(twin)


func _test_attack_and_sword(world: Dictionary) -> void:
	var child: Node2D = world.effects.native_summon_actors().values()[0]
	world.player.health.release_invulnerability_source(&"splitting_fixture")
	world.player.global_position = child.global_position + Vector2(14, 0)
	await get_tree().physics_frame
	var hp_before := float(world.player.health.current_hp)
	for _frame: int in range(150):
		suite.assert_true(world.player.advance_action_frame(), "actual ordinary copies accept their species warning and attack")
		if world.player.health.current_hp < hp_before:
			break
	suite.assert_close(hp_before - float(world.player.health.current_hp), 12.0, "actual ordinary copied Sentinel attacks real Player with full ordinary damage")
	world.player.health.acquire_invulnerability_source(&"splitting_fixture")
	for _frame: int in range(12):
		suite.assert_true(world.player.advance_action_frame(), "copy Player hit recovery accepts native frame")
	world.player.global_position = child.global_position - Vector2(42, 0)
	await get_tree().physics_frame
	suite.assert_true(world.player.advance_action_frame({"aim": Vector2.RIGHT}), "actual Player aims production Sword at real copied body")
	world.bridge.sword_victim = child
	var committed: bool = world.player.try_action(&"weapon_primary") and world.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
	suite.assert_true(committed, "production Sword commits copied-body attack")
	if not committed:
		return
	for _frame: int in range(32):
		var weapon: Dictionary = world.player.weapon_action_coordinator.snapshot()
		if weapon.phase == "WINDUP" and int(weapon.phase_frame) + 1 == int(weapon.plan.phases[weapon.phase_index].duration_frames):
			break
		suite.assert_true(world.player.advance_action_frame(), "production Sword advances copied-body windup")
	_assert_late_rollback(world, "actual production Sword copy lethal")
	suite.assert_true(world.bridge.produced, "real Sword DamageInfo reaches real copied Hurtbox")
	suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().size() == 1, "compensated production Sword retires only its copied body")
	suite.assert_equal(world.effects.summon_snapshot().rows.size(), 2, "child death cannot recursively split or repeat mother's once-only reservation")


func _test_external_death_and_lifetime() -> void:
	var world := _world()
	await get_tree().physics_frame
	suite.assert_true(world.effects.bind_native_targets({"split-owner": world.actor}, {"player:1": world.player}), "external Splitting binds real source before final body death")
	var info := Damage.from_plan({"run_id": "run-splitting", "target_id": "split-owner", "hostile_source_id": "domain:external-splitting", "attack_generation": 1, "action_token": 1, "amount": 1000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})
	suite.assert_true(world.actor.health.take_damage(info) > 0.0 and world.effects.capture_native_terminal_split(world.actor, world.actor.get("_death_receipt"), {"player:1": world.player}), "actual out-of-frame final death reserves orphan copies before principal retirement")
	suite.assert_true(world.effects.capture_native_terminal_split(world.actor, world.actor.get("_death_receipt"), {"player:1": world.player}) and world.effects.summon_snapshot().rows.size() == 2, "duplicate final native callback keeps exactly one two-copy claim")
	world.bridge.retire_actor("split-owner")
	world.actor.queue_free()
	await get_tree().process_frame
	for frame: int in range(1, 510):
		suite.assert_true(world.player.advance_action_frame(), "orphan copy continues native accepted frame%d without mother body" % frame)
		if frame == 30:
			suite.assert_equal(world.effects.native_summon_actors().size(), 2, "out-of-frame copies use complete30-frame warning and fallback room")
		if frame == 509:
			suite.assert_equal(world.effects.native_summon_actors().size(), 2, "orphan copies retain final frame before exact480-frame TTL")
	world.actor = null
	_assert_late_rollback(world, "exact orphan copy TTL retirement")
	suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().is_empty() and world.effects.work_snapshot().records.is_empty(), "exact480-frame TTL retires real orphan bodies, warnings and room work")
	await _test_cold(world, "expired")
	await _dispose(world)


func _test_blocked_admission() -> void:
	var world := _world()
	await get_tree().physics_frame
	world.bridge.armed = true
	suite.assert_true(world.player.advance_action_frame(), "blocked copy source accepts final death")
	world.bridge.armed = false
	var row: Dictionary = world.effects.summon_snapshot().rows[0]
	var frozen: Dictionary = row.position.duplicate(true)
	world.player.global_position = Vector2(float(frozen.x), float(frozen.y))
	await get_tree().physics_frame
	for _frame: int in range(60):
		suite.assert_true(world.player.advance_action_frame(), "collision-blocked native copy accepts frame")
	suite.assert_true(world.effects.summon_snapshot().rows[0].phase == "PENDING" and world.effects.native_summon_actors().size() == 1, "blocked copy waits independently while safe sibling materializes")
	suite.assert_equal(world.effects.summon_snapshot().rows[0].position, frozen, "blocked copy keeps original frozen position")
	await _test_cold(world, "pending")
	world.player.global_position = Vector2(600, 300)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(world.player.advance_action_frame(), "cleared frozen copy slot begins new complete warning")
	var warning: int = world.effects.summon_snapshot().rows[0].warning_frame
	for _frame: int in range(29):
		suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().size() == 1, "deferred copy cannot shorten repeated30-frame warning")
	suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().size() == 2 and world.effects.summon_snapshot().rows[0].birth_frame == warning + 30, "deferred copy materializes original lease after full warning")
	await _dispose(world)


func _test_paired_cues() -> void:
	var contrast: Variant = GameState.get_setting("high_contrast_danger", false)
	var scale_setting: Variant = GameState.get_setting("enemy_telegraph_scale", 1.0)
	GameState.set_setting("high_contrast_danger", true)
	GameState.set_setting("enemy_telegraph_scale", 1.5)
	for companion: String in ["shielded", "teleporting", "chaining", "anchored", "regenerating", "frenzy", "fortified"]:
		var world := _world(companion)
		var cue: Node2D = world.actor.get_node("EliteSplittingCue")
		suite.assert_true(cue.visible and cue.get_snapshot().visual_scale == 1.5 and cue.get_snapshot().high_contrast, "actual legal paired Splitting cue obeys accessibility")
		for name: String in ["EliteShieldCue", "EliteTeleportCue", "EliteChainingCue"]:
			var other := world.actor.get_node_or_null(name) as Node2D
			if other != null and other.visible:
				suite.assert_true(cue.position.distance_to(other.position) >= 40.0, "enlarged legal paired cues keep separate readable geometry")
		await _capture(world, "pair-" + companion)
		await _dispose(world)
	GameState.set_setting("high_contrast_danger", contrast)
	GameState.set_setting("enemy_telegraph_scale", scale_setting)


func _test_every_legal_parent() -> void:
	for source: Dictionary in Content.read_catalog("enemies.json"):
		if Rules.CHILD_OWNER_IDS.has(source.id):
			continue
		var world := _world("", -1, str(source.id))
		await get_tree().physics_frame
		world.bridge.armed = true
		suite.assert_true(world.player.advance_action_frame(), "every legal native parent accepts final Splitting death: " + str(source.id))
		world.bridge.armed = false
		for _frame: int in range(30):
			suite.assert_true(world.player.advance_action_frame(), "every legal native parent retains full copy warning: " + str(source.id))
		suite.assert_equal(world.effects.native_summon_actors().size(), 2, "every legal native parent births two original-species bodies: " + str(source.id))
		for child: Node2D in world.effects.native_summon_actors().values():
			suite.assert_true(child.get("_launch_definition").runtime_kind == source.id and child.launch_affix_snapshot().is_empty() and not child.get_meta("reward_eligible"), "actual legal species copy keeps ordinary behavior and zero reward")
		await _test_cold(world, "species_" + str(source.id))
		for _frame: int in range(479):
			suite.assert_true(world.player.advance_action_frame(), "every legal ordinary species accepts deterministic lifetime frame: " + str(source.id))
		suite.assert_equal(world.effects.native_summon_actors().size(), 2, "every legal species retains both real bodies through last480-frame lifetime boundary")
		suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().is_empty(), "every legal species retires its real copied bodies at exact TTL: " + str(source.id))
		suite.assert_equal(world.effects.summon_snapshot().rows.size(), 2, "every legal species terminal lifecycle has no recursive copy reservation")
		await _dispose(world)


func _test_global_capacity() -> void:
	var world := _world()
	var owners := {"split-owner": world.actor}
	var extras: Array[Node2D] = []
	var positions: Array[Vector2] = [Vector2(180, 100), Vector2(460, 100), Vector2(180, 260), Vector2(460, 260)]
	for index: int in range(4):
		var actor := Scene.instantiate() as Node2D
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		add_child(actor)
		actor.global_position = positions[index]
		var source := "split-cap-%d" % index
		actor.configure_launch_affixes([Content.affix("splitting")], 5)
		var parser := Definition.new()
		parser.configure(Content.enemy())
		suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), {"run_id": "run-splitting", "hostile_source_id": source, "next_generation_floor": 1, "runtime_frame": 0, "seed": 43}).ok and actor.configure_launch_room_motion(world.room, world.effects.get("_summons").get("_fallback_template")).ok, "capacity fixture owns actual configured Splitting elite")
		owners[source] = actor
		extras.append(actor)
		suite.assert_true(world.bridge.register_actor(actor), "capacity fixture registers actual mother in Player authority")
	world.extra_owners = extras
	await get_tree().physics_frame
	suite.assert_true(world.effects.bind_native_targets(owners, {"player:1": world.player}), "global capacity binds every actual Splitting mother")
	for source: String in owners:
		var actor: Node2D = owners[source]
		var info := Damage.from_plan({"run_id": "run-splitting", "target_id": source, "hostile_source_id": "domain:split-capacity", "attack_generation": 1, "action_token": 1, "amount": 1000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})
		suite.assert_true(actor.health.take_damage(info) > 0.0 and world.effects.capture_native_terminal_split(actor, actor.get("_death_receipt"), {"player:1": world.player}) and world.bridge.retire_actor(source), "actual competing mother reserves one atomic pair and retires once")
	var rows: Array = world.effects.summon_snapshot().rows
	suite.assert_true(rows.size() == 10 and rows.filter(func(row: Dictionary): return row.phase == "WARNING").size() == 8 and rows.filter(func(row: Dictionary): return row.phase == "PENDING").size() == 2, "five actual mothers retain ten copy leases under shared eight-warning budget")
	for frame: int in range(1, 510):
		suite.assert_true(world.player.advance_action_frame(), "actual global copy capacity accepts native frame%d" % frame)
		if frame == 30 or frame == 509:
			suite.assert_equal(world.effects.native_summon_actors().size(), 8, "exact shared capacity has eight actual copied bodies")
	suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().is_empty(), "first eight actual copies retire at exact480-frame TTL")
	for frame: int in range(511, 540):
		suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().is_empty(), "deferred pair retains fresh thirty-frame warning after budget opens")
	suite.assert_true(world.player.advance_action_frame() and world.effects.native_summon_actors().size() == 2, "deferred mother pair materializes after full restarted warning")
	suite.assert_equal(world.effects.summon_snapshot().claims.size(), 5, "five mothers retain exactly five once-only split claims")
	await _dispose(world)


func _test_prevented_and_nonlethal() -> void:
	var world := _world()
	world.effects.bind_native_targets({"split-owner": world.actor}, {"player:1": world.player})
	var info := Damage.from_plan({"run_id": "run-splitting", "target_id": "split-owner", "hostile_source_id": "domain:split-prevented", "attack_generation": 1, "action_token": 1, "amount": 20.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})
	world.actor.health.acquire_invulnerability_source(&"split-prevented-fixture")
	suite.assert_close(world.actor.health.take_damage(info), 0.0, "prevented actual Splitting damage cannot cause terminal reservation")
	world.actor.health.release_invulnerability_source(&"split-prevented-fixture")
	suite.assert_true(not world.effects.capture_native_terminal_split(world.actor, "invented", {"player:1": world.player}), "nonfinal actual mother cannot authenticate external terminal callback")
	suite.assert_close(world.actor.health.take_damage(info), 20.0, "same unspent native fact retries as real nonlethal body damage")
	suite.assert_true(world.player.advance_action_frame() and world.effects.summon_snapshot().rows.is_empty(), "accepted nonlethal mother damage creates no hidden copy work")
	await _dispose(world)


func _capture(world: Dictionary, label: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		suite.assert_equal(pixels.get_size(), resolution, "native Splitting capture keeps exact resolution")
		var ratio := resolution.x / 640.0
		var nodes: Array = world.effects.get("_summons").get("_warnings").values() if label == "warning" else world.effects.native_summon_actors().values() if label == "active" else [world.actor.get_node("EliteSplittingCue")]
		for node: Node2D in nodes:
			var centre: Vector2 = node.global_position * ratio
			node.visible = false
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var absent := get_viewport().get_texture().get_image()
			node.visible = true
			var changed := 0
			for y: int in range(maxi(0, int(centre.y - 23 * ratio)), mini(pixels.get_height(), int(centre.y + 23 * ratio))):
				for x: int in range(maxi(0, int(centre.x - 23 * ratio)), mini(pixels.get_width(), int(centre.x + 23 * ratio))):
					changed += int(pixels.get_pixel(x, y) != absent.get_pixel(x, y))
			suite.assert_true(changed > 40, "real Splitting cue, warning or ordinary atlas contributes visible native pixels")
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var output := "res://build/visual-evidence/native-elite-affixes/splitting-%s-%dx%d.png" % [label, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "actual native Splitting capture retained")
