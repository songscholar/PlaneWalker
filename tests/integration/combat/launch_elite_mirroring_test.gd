extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Scene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
const Player := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Summons := preload("res://scripts/enemies/launch/launch_summon_authority.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Save := preload("res://scripts/save/save_service.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
var suite: RefCounted

class SwordBridge:
	extends "res://scripts/enemies/launch/hostile_frame_bridge.gd"
	var victim: Node2D
	var produced := false
	func prepare_frame(ticket: Dictionary) -> bool:
		var hitbox: Node = _player.get_node("SwordWeapon/Hitbox")
		if is_instance_valid(victim) and hitbox.is_active():
			produced = true
			victim.get_node("Hurtbox").receive_hit(hitbox.get("_active_damage_info").copy_for_source(hitbox))
		return super.prepare_frame(ticket)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var world := _world()
	await get_tree().physics_frame
	var accepted := true
	for frame: int in range(1, 900):
		if not _advance(world, frame):
			accepted = false
			break
	suite.assert_true(accepted, "actual Mirroring owner accepts every frame before its complete900-frame interval")
	suite.assert_true(world.effects.snapshot().summons.rows.is_empty(), "actual Mirroring cannot create hidden early summon work")
	if accepted:
		_assert_late_rollback(world, "native mirror reservation")
		suite.assert_true(_advance(world, 900), "actual Mirroring accepts reservation boundary")
		var rows: Array = world.effects.snapshot().summons.rows
		suite.assert_true(rows.size() == 1 and rows[0].phase == "WARNING", "actual900-frame Mirroring interval needs one visible native summon warning")
		if rows.size() == 1:
			suite.assert_equal(rows[0].spawn_warning_frames, 40, "native mirror owns its authored forty-frame warning")
			suite.assert_equal(world.actor.launch_mirroring_reservations().size(), 1, "accepted owner keeps exactly one sealed scheduling receipt")
			suite.assert_true(world.actor.prepared_launch_mirroring_reservation().is_empty(), "accepted publication cannot replay private mirror reservation")
			await _test_cold(world, "warning")
			await _presentation(world, "warning")
			for frame: int in range(901, 940):
				suite.assert_true(_advance(world, frame) and world.effects.native_summon_actors().is_empty(), "actual mirror cannot materialize before its full warning at frame%d" % frame)
			_assert_late_rollback(world, "native mirror birth")
			suite.assert_true(_advance(world, 940), "actual mirror birth boundary settles")
			suite.assert_equal(world.effects.native_summon_actors().size(), 1, "actual940-frame Mirroring materializes one real support body")
			if world.effects.native_summon_actors().size() == 1:
				var child: Node2D = world.effects.native_summon_actors().values()[0]
				suite.assert_close(child.health.max_hp, 16.0, "real mirror uses twenty percent ordinary80HP parent, excluding160HP elite scaling")
				suite.assert_close(child.get("_launch_definition").actions[0].hit_schedule[0].damage, 6.0, "real mirror uses fifty percent ordinary12damage parent, excluding elite scaling")
				suite.assert_true(child.get_meta("summoned") and not child.get_meta("reward_eligible") and child.launch_affix_snapshot().is_empty() and child.get("_launch_definition").actions.size() == 1, "real mirror has no affix, recursion or independent reward")
				await _test_cold(world, "active")
				await _presentation(world, "active")
				await _test_actual_attack_and_sword(world, child)
	await _dispose(world)
	if accepted and OS.get_environment("ELITE_MIRRORING_TEST_REVISION") != "8":
		await _test_blocked_cap_and_retirement()
		await _test_harmless_parent()
		await _test_global_budget_and_lifetime()
		await _test_paired_cues()
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
	var rows: Array = [Content.affix("mirroring")]
	if not companion.is_empty():
		rows.append(Content.affix(companion))
	if revision < 0 and OS.get_environment("ELITE_MIRRORING_TEST_REVISION") == "8":
		revision = 8
	var configured: Dictionary = actor.configure_launch_affixes(rows, 4) if revision < 0 else actor.configure_launch_affixes(rows, 4, revision)
	suite.assert_true(configured.ok, "actual Mirroring compiles before canonical native elite")
	var parser := Definition.new()
	parser.configure(Content.enemy(enemy_id))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), {"run_id": "run-mirroring", "hostile_source_id": "mirror-owner", "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}).ok, "actual Mirroring elite configures")
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_combat_open_field":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "actual Mirroring owns validated native room")
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-mirroring")
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "actual Mirroring Player owns production Sword profile")
	player.global_position = Vector2(600, 300)
	player.health.acquire_invulnerability_source(&"mirroring_fixture")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-mirroring", 0)
	effects.configure_native_payloads(root)
	var bridge := SwordBridge.new()
	var registry := Registry.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects) and player.configure_hostile_frame_participant(bridge), "actual Mirroring binds full Player and shared native summon frame authority")
	return {"room": room, "actor": actor, "player": player, "root": root, "effects": effects, "bridge": bridge, "registry": registry}


func _advance(world: Dictionary, frame: int) -> bool:
	return int(world.player.get("_runtime_frame")) + 1 == frame and world.player.advance_action_frame()


func _cold(world: Dictionary) -> Dictionary:
	var children := {}
	for source: String in world.effects.native_summon_actors():
		children[source] = world.effects.native_summon_actors()[source].native_cold_snapshot(func(_source: Node): return {})
	var actors := {"mirror-owner": world.actor.native_cold_snapshot(func(_source: Node): return {})}
	for owner: Node2D in world.get("extra_owners", []):
		actors[str(owner.hostile_source_id)] = owner.native_cold_snapshot(func(_source: Node): return {})
	return {"player": world.player.full_player_replay_snapshot(), "actors": actors, "children": children, "effects": world.effects.launch_transaction_snapshot(), "threats": world.registry.snapshot()}


func _assert_late_rollback(world: Dictionary, label: String) -> void:
	var before := _cold(world)
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not suite.expect_rejected_player_frame(world.player), "late World rejection refuses " + label)
	world.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_equal(_cold(world), before, "late World rejection restores complete Player, owner, children and native work: " + label)


func _test_cold(world: Dictionary, label: String) -> void:
	var cold := _cold(world)
	var encoded: Dictionary = Replay.encode_replay_json(cold)
	suite.assert_true(encoded.ok, "actual mirror %s aggregate admits typed replay persistence" % label)
	if not encoded.ok:
		return
	var value: Dictionary = Replay.decode_replay_json(encoded.json).replay
	suite.assert_true(Summons.valid_mirroring_cold_bindings(value.effects.summons, value.actors), "actual mirror %s cold cross-validates owner scheduling ledger" % label)
	for mutation: String in ["erased_claim", "foreign_owner", "position", "future", "parent"]:
		var forged := value.duplicate(true)
		match mutation:
			"erased_claim": forged.effects.summons.claims.clear()
			"foreign_owner": forged.effects.summons.rows[0].parent_source_id = "foreign-owner"
			"position": forged.effects.summons.rows[0].position.x += 1.0
			"future": forged.effects.summons.rows[0].request_frame += 1
			"parent": forged.effects.summons.rows[0].parent_definition_id = "void_spore"
		suite.assert_true(not Summons.valid_mirroring_cold_bindings(forged.effects.summons, forged.actors), "native mirror %s cold refuses %s" % [label, mutation])
	var twin := _world()
	twin.player.configure_hostile_frame_participant(null)
	var restored: bool = twin.player.restore_full_player_replay_snapshot(value.player) and twin.actor.restore_native_cold_snapshot(value.actors["mirror-owner"], func(_binding: Dictionary): return null) and twin.effects.bind_native_targets({"mirror-owner": twin.actor}, {"player:1": twin.player}) and twin.effects.restore_native_summon_snapshot(value.effects.summons)
	if restored:
		for source: String in value.children:
			if not twin.effects.native_summon_actors()[source].restore_native_cold_snapshot(value.children[source], func(_binding: Dictionary): return null):
				restored = false
		if not twin.effects.bind_native_targets({"mirror-owner": twin.actor}, {"player:1": twin.player}) or not twin.effects.restore_launch_transaction_snapshot(value.effects) or not twin.bridge.configure(twin.player, twin.registry, [twin.actor], twin.effects) or not twin.bridge.call("_restore_registry", value.threats) or not twin.player.configure_hostile_frame_participant(twin.bridge):
			restored = false
	suite.assert_true(restored, "fresh native mirror %s cold aggregate reconstructs actual Player, owner and child" % label)
	if restored:
		suite.assert_equal(_cold(twin), value, "fresh actual mirror %s recovery keeps exact typed state" % label)
		var frame := int(twin.player.get("_runtime_frame")) + 1
		suite.assert_true(_advance(twin, frame), "restored actual mirror %s accepts original next native frame" % label)
	await _physical_roundtrip(value, label)
	await _dispose(twin)


func _physical_roundtrip(value: Dictionary, label: String) -> void:
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var directory := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("elite_mirroring")
	var binding := ContentSnapshot.snapshot(registry)
	var service := Save.new()
	service.configure(directory, "test-mirroring", binding)
	var encoded := Replay.encode_replay_json(value)
	suite.assert_true(service.save_profile("mirror_" + label, "base", {"codec": encoded.json}).ok, "actual SaveService writes typed mirror %s aggregate" % label)
	var fresh := Save.new()
	fresh.configure(directory, "test-mirroring", binding)
	var recovered = fresh.inspect_profile("mirror_" + label, "base")
	suite.assert_true(recovered.ok and Replay.decode_replay_json(recovered.payload.payload.codec).replay == value, "fresh physical recovery retains exact native mirror %s aggregate" % label)


func _test_actual_attack_and_sword(world: Dictionary, child: Node2D) -> void:
	suite.assert_true(world.actor.get("_launch_runtime").add_control_source("isolate-mirror-attack", "stop", 240, 1.0), "actual mirror attack gate pauses parent independently")
	world.player.health.release_invulnerability_source(&"mirroring_fixture")
	world.player.global_position = child.global_position + Vector2(14, 0)
	await get_tree().physics_frame
	var hp_before := float(world.player.health.current_hp)
	for _index: int in range(70):
		var frame := int(world.player.get("_runtime_frame")) + 1
		suite.assert_true(_advance(world, frame), "actual mirror executes complete native attack warning")
		if world.player.health.current_hp < hp_before:
			break
	suite.assert_close(hp_before - float(world.player.health.current_hp), 6.0, "real mirror first damaging action hurts Player for half ordinary parent damage")
	world.player.health.acquire_invulnerability_source(&"mirroring_fixture")
	for _index: int in range(12):
		suite.assert_true(world.player.advance_action_frame(), "actual Player accepts complete mirror hit recovery")
	world.player.global_position = child.global_position - Vector2(42, 0)
	await get_tree().physics_frame
	suite.assert_true(world.player.advance_action_frame({"aim": Vector2.RIGHT}), "actual Player aims production Sword at mirror body")
	world.bridge.victim = child
	var committed: bool = world.player.try_action(&"weapon_primary") and world.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
	suite.assert_true(committed, "production Sword commits real mirror weapon hit")
	if not committed:
		return
	var countdown := 32
	while countdown > 0:
		var weapon: Dictionary = world.player.weapon_action_coordinator.snapshot()
		if weapon.phase == "WINDUP" and int(weapon.phase_frame) + 1 == int(weapon.plan.phases[weapon.phase_index].duration_frames):
			break
		suite.assert_true(world.player.advance_action_frame(), "production Sword advances mirror contact windup")
		countdown -= 1
	suite.assert_true(countdown > 0, "production Sword reaches actual mirror active boundary")
	_assert_late_rollback(world, "actual Sword mirror hit")
	suite.assert_true(world.bridge.produced, "actual registered Sword DamageInfo reaches real mirror Hurtbox")
	suite.assert_true(world.player.advance_action_frame(), "original production Sword hit retries once after mirror compensation")
	suite.assert_true(world.effects.native_summon_actors().is_empty(), "accepted Sword retires low-HP mirror through ordinary actual body settlement")
	suite.assert_true(world.effects.summon_snapshot().rows[0].phase == "RETIRED" and world.effects.work_snapshot().records.is_empty(), "accepted mirror death retires summon encounter work without independent reward")


func _test_blocked_cap_and_retirement() -> void:
	var world := _world()
	for frame: int in range(1, 901):
		suite.assert_true(_advance(world, frame), "blocked mirror fixture reaches real reservation")
	var row: Dictionary = world.effects.summon_snapshot().rows[0]
	var frozen: Dictionary = row.position.duplicate(true)
	world.player.global_position = Vector2(float(frozen.x), float(frozen.y))
	await get_tree().physics_frame
	for frame: int in range(901, 1801):
		suite.assert_true(_advance(world, frame), "collision-blocked mirror scheduling accepts native frame%d" % frame)
	suite.assert_true(world.effects.summon_snapshot().rows.size() == 1 and world.effects.summon_snapshot().rows[0].phase == "PENDING" and world.effects.native_summon_actors().is_empty(), "second900frame receipt cannot exceed one queued or alive mirror per owner")
	suite.assert_equal(world.effects.summon_snapshot().rows[0].position, frozen, "blocked mirror keeps its original deterministic frozen slot")
	suite.assert_equal(world.actor.launch_mirroring_reservations().size(), 2, "blocked optional scheduling keeps both spent owner intervals")
	world.player.global_position = Vector2(500, 100)
	await get_tree().physics_frame
	suite.assert_true(_advance(world, 1801), "unblocked mirror begins complete replacement warning")
	suite.assert_equal(world.effects.summon_snapshot().rows[0].warning_frame, 1801, "deferred mirror owns a new full40frame warning")
	for frame: int in range(1802, 1841):
		suite.assert_true(_advance(world, frame) and world.effects.native_summon_actors().is_empty(), "deferred mirror cannot shorten warning")
	suite.assert_true(_advance(world, 1841) and world.effects.native_summon_actors().size() == 1, "deferred mirror materializes after complete new warning")
	suite.assert_true(world.actor.health.take_damage(Damage.from_plan({"run_id": "run-mirroring", "target_id": "mirror-owner", "hostile_source_id": "domain:owner-retirement", "attack_generation": 1, "action_token": 1, "amount": 1000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})) > 0.0, "actual native owner reaches final terminal body loss")
	suite.assert_true(_advance(world, 1842) and world.effects.native_summon_actors().is_empty() and world.effects.work_snapshot().records.is_empty(), "native owner final death retires mirror and all owned combat work")
	await _dispose(world)


func _test_harmless_parent() -> void:
	var world := _world("", -1, "rift_watcher")
	for frame: int in range(1, 941):
		suite.assert_true(_advance(world, frame), "actual nondamaging RiftWatcher mirror cannot stall native frame%d" % frame)
	suite.assert_equal(world.effects.native_summon_actors().size(), 1, "actual nondamaging ordinary parent still materializes one authentic mirror")
	if world.effects.native_summon_actors().size() == 1:
		var child: Node2D = world.effects.native_summon_actors().values()[0]
		var definition: Dictionary = child.get("_launch_definition")
		suite.assert_true(definition.mechanisms.harmless and definition.actions[0].geometry.is_empty() and definition.actions[0].hit_schedule.is_empty(), "nondamaging parent mirror carries no inherited healing, slowing or hidden damage action")
		world.actor.get("_launch_runtime").add_control_source("harmless-mirror-parent-isolation", "stop", 60, 1.0)
		world.player.health.release_invulnerability_source(&"mirroring_fixture")
		world.player.global_position = child.global_position + Vector2(14, 0)
		var hp := float(world.player.health.current_hp)
		for frame: int in range(941, 971):
			suite.assert_true(_advance(world, frame) and child.launch_runtime_snapshot().runtime.action.phase == "IDLE", "actual harmless mirror never selects an attack or support action")
		suite.assert_close(world.player.health.current_hp, hp, "actual harmless mirror cannot invent damage against vulnerable Player")
	await _dispose(world)


func _test_global_budget_and_lifetime() -> void:
	var world := _world()
	world["extra_owners"] = []
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var template := {}
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if row.id == "room_combat_open_field":
			template = row
	for index: int in range(8):
		var owner := Scene.instantiate() as Node2D
		owner.process_mode = Node.PROCESS_MODE_DISABLED
		owner.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		add_child(owner)
		owner.global_position = Vector2(100 + (index % 4) * 110, 80 + (index / 4) * 160)
		suite.assert_true(owner.configure_launch_affixes([Content.affix("mirroring")], 4).ok and owner.configure_launch_definition(parser.runtime_projection("elite"), {"run_id": "run-mirroring", "hostile_source_id": "mirror-budget-%d" % index, "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}).ok and owner.configure_launch_room_motion(world.room, template).ok, "independent native mirror budget owner%d configures" % index)
		world.extra_owners.append(owner)
	suite.assert_true(world.bridge.configure(world.player, world.registry, [world.actor] + world.extra_owners, world.effects), "nine actual mirror owners share one Player and eight-child authority")
	for frame: int in range(1, 901):
		suite.assert_true(_advance(world, frame), "nine native mirror owners accept complete scheduling interval")
	var rows: Array = world.effects.summon_snapshot().rows
	suite.assert_true(rows.size() == 9 and rows.filter(func(row: Dictionary): return row.phase == "WARNING").size() == 8 and rows.filter(func(row: Dictionary): return row.phase == "PENDING").size() == 1, "nine authentic mirrors reserve eight visible slots and one pending lease")
	for frame: int in range(901, 941):
		suite.assert_true(_advance(world, frame), "global mirror capacity preserves full native warnings")
	suite.assert_equal(world.effects.native_summon_actors().size(), 8, "MIRROR admission never exceeds actual global eight-body capacity")
	for owner: Node2D in [world.actor] + world.extra_owners:
		owner.get("_launch_runtime").add_control_source("mirror-lifetime-isolation", "stop", 600, 1.0)
	for child: Node2D in world.effects.native_summon_actors().values():
		child.get("_launch_runtime").add_control_source("mirror-lifetime-isolation", "stop", 600, 1.0)
	for frame: int in range(941, 1420):
		suite.assert_true(_advance(world, frame) and world.effects.native_summon_actors().size() == 8, "actual paused mirror remains alive through479 accepted lifetime frames")
	_assert_late_rollback(world, "actual eight-mirror TTL expiry and deferred admission")
	suite.assert_true(_advance(world, 1420) and world.effects.native_summon_actors().is_empty(), "actual mirrors expire exactly480 frames after birth despite owner and child Stop")
	rows = world.effects.summon_snapshot().rows
	suite.assert_true(rows.filter(func(row: Dictionary): return row.phase == "RETIRED").size() == 8 and rows.filter(func(row: Dictionary): return row.phase == "WARNING" and row.warning_frame == 1420).size() == 1 and world.effects.work_snapshot().records.size() == 1, "eight TTL retirements release combat and room work while pending mirror starts full warning")
	for frame: int in range(1421, 1460):
		suite.assert_true(_advance(world, frame) and world.effects.native_summon_actors().is_empty(), "global capacity release cannot shorten pending mirror warning")
	suite.assert_true(_advance(world, 1460) and world.effects.native_summon_actors().size() == 1, "ninth actual mirror materializes after full forty-frame replacement warning")
	await _dispose(world)


func _test_paired_cues() -> void:
	for companion: String in ["nullified", "shielded", "teleporting", "chaining"]:
		var world := _world(companion)
		var old_contrast: bool = GameState.get_setting("high_contrast_danger", false)
		var old_scale: float = GameState.get_setting("enemy_telegraph_scale", 1.0)
		GameState.set_setting("high_contrast_danger", true)
		GameState.set_setting("enemy_telegraph_scale", 1.5)
		var before := _cold(world)
		world.actor.project_runtime_snapshot(world.actor.launch_runtime_snapshot())
		var cue: Node2D = world.actor.get_node("EliteMirroringCue")
		var other: Node2D = world.actor.get_node({"nullified": "EliteAffixCue", "shielded": "EliteShieldCue", "teleporting": "EliteTeleportCue", "chaining": "EliteChainingCue"}[companion])
		suite.assert_true(cue.position.distance_to(other.position) >= 44.0 and cue.get_snapshot().high_contrast and cue.get_snapshot().visual_scale == 1.5, "compatible enlarged mirror and %s cues keep separate geometry" % companion)
		suite.assert_equal(_cold(world), before, "mirror accessibility presentation cannot mutate native state")
		await _capture(world.actor, companion + "-pair-high-contrast")
		GameState.set_setting("high_contrast_danger", old_contrast)
		GameState.set_setting("enemy_telegraph_scale", old_scale)
		await _dispose(world)


func _presentation(world: Dictionary, label: String) -> void:
	var cue: Node2D = world.actor.get_node("EliteMirroringCue")
	suite.assert_true(cue.visible and cue.get_snapshot().phase == ("SCHEDULED" if label == "warning" else "COOLDOWN"), "actual mirror owner projects distinct native %s state" % label)
	await _capture(world.actor, label, world)


func _capture(actor: Node2D, label: String, world: Dictionary = {}) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		suite.assert_equal(pixels.get_size(), resolution, "actual mirror native capture retains requested dimensions")
		var cue: Node2D = actor.get_node("EliteMirroringCue")
		var ratio := resolution.x / 640.0
		var centre: Vector2 = cue.global_position * ratio
		var radius := Vector2(16, 13) * cue.scale * ratio
		var visible_pixels := 0
		var cue_state: Dictionary = cue.get_snapshot()
		var ink := Color.WHITE if cue_state.high_contrast else Color(0.93, 0.68, 0.83)
		if cue_state.phase == "COOLDOWN":
			ink = Color(0.75, 0.75, 0.75) if cue_state.high_contrast else Color(0.63, 0.75, 0.73)
		for y: int in range(maxi(0, int(centre.y - radius.y)), mini(pixels.get_height(), int(centre.y + radius.y))):
			for x: int in range(maxi(0, int(centre.x - radius.x)), mini(pixels.get_width(), int(centre.x + radius.x))):
				var color := pixels.get_pixel(x, y)
				if absf(color.r - ink.r) + absf(color.g - ink.g) + absf(color.b - ink.b) < 0.15:
					visible_pixels += 1
		suite.assert_true(visible_pixels > 10, "outlined native mirror pixels render in authored cue bounds")
		if not world.is_empty() and label == "warning":
			var warning: Node2D = world.effects.get("_summons").get("_warnings").values()[0]
			var warning_center: Vector2 = warning.global_position * ratio
			warning.visible = false
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var without_warning := get_viewport().get_texture().get_image()
			warning.visible = true
			var changed := 0
			for y: int in range(maxi(0, int(warning_center.y - 20 * ratio)), mini(pixels.get_height(), int(warning_center.y + 20 * ratio))):
				for x: int in range(maxi(0, int(warning_center.x - 20 * ratio)), mini(pixels.get_width(), int(warning_center.x + 20 * ratio))):
					changed += int(pixels.get_pixel(x, y) != without_warning.get_pixel(x, y))
			suite.assert_true(changed > 40, "actual frozen native mirror spawn warning contributes visible raster pixels")
		if not world.is_empty() and label == "active":
			var child: Node2D = world.effects.native_summon_actors().values()[0]
			var child_center: Vector2 = child.global_position * ratio
			var mirror_pixels := 0
			for y: int in range(maxi(0, int(child_center.y - 16 * ratio)), mini(pixels.get_height(), int(child_center.y + 16 * ratio))):
				for x: int in range(maxi(0, int(child_center.x - 16 * ratio)), mini(pixels.get_width(), int(child_center.x + 16 * ratio))):
					var color := pixels.get_pixel(x, y)
					mirror_pixels += int(absf(color.r - 194.0 / 255.0) + absf(color.g - 222.0 / 255.0) + absf(color.b - 244.0 / 255.0) < 0.06)
			suite.assert_true(mirror_pixels > 40, "actual elite_mirror atlas renders its own colored body pixels")
		var output := "res://build/visual-evidence/native-elite-affixes/mirroring-%s-%dx%d.png" % [label, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native mirror screenshot retained")


func _dispose(world: Dictionary) -> void:
	world.player.configure_hostile_frame_participant(null)
	world.effects.dispose_native_effects()
	for node: Variant in [world.actor, world.player, world.root, world.room] + world.get("extra_owners", []):
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
