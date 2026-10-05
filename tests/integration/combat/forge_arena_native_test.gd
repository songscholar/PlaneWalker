extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Boss := preload("res://data/content_packs/base/assets/bosses/launch/boss_forge_colossus.tscn")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Player := preload("res://scenes/player/player.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_boss_forge_colossus.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Save := preload("res://scripts/save/save_service.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const ContentSnapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const IDENTITY := {"run_id": "run-forge-arena", "hostile_source_id": "forge-arena-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var actor := Boss.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	suite.assert_true(actor.has_method("native_forge_arena_snapshot"), "production Forge must expose authoritative native anvils, vents and cooling pools")
	actor.queue_free()
	await get_tree().process_frame
	await _anvils()
	await _slam_and_cooling()
	await _spray()
	await _pull()
	await _eruption()
	await _lava()
	await _thrust_and_cyclone()
	await _enrage()
	suite.finish(get_tree())


func _fixture() -> Dictionary:
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := Boss.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = room.get_node("EncounterAnchors/boss_primary").global_position
	var parser := Definition.new()
	parser.configure(Content.boss("forge_colossus"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), IDENTITY).ok, "Forge binds actual production Boss")
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_forge_colossus":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "Forge binds its physical room")
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-forge-arena")
	player.health.defense = 0.0
	player.global_position = Vector2(400, 180)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-forge-arena", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "Forge enters actual native frame bridge")
	await get_tree().physics_frame
	return {"room": room, "actor": actor, "player": player, "root": root, "effects": effects, "registry": registry, "bridge": bridge, "runtime": actor.get("_launch_runtime")}


func _anvils() -> void:
	var f := await _fixture()
	var initial: Dictionary = f.actor.native_forge_arena_snapshot()
	suite.assert_true(initial.covers.size() == 4 and initial.vents.size() == 4 and initial.cooling_pools.size() == 4, "actual Forge manifests fourHP120 anvils, four fixed vents and four cooling pools")
	suite.assert_equal(initial.vent_damage_authority, "rule_forge_vents", "P14 owns one vent damage origin")
	for fixture: Area2D in f.actor.get_node("ForgeFixtures").get_children():
		suite.assert_true(fixture.collision_layer == 0 and not fixture.monitoring, "permanent fixtures never duplicate vent damage or block safe routes")
	var anvil: Node2D = f.actor.get_node("ArenaConstructs").get_child(0)
	var before: Dictionary = f.actor.launch_runtime_snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(1)
	suite.assert_equal(anvil.get_node("Hurtbox").receive_hit(_damage(f.player, 1, 150.0)), 120.0, "real authenticated legacy weapon producer consumes exactly120anvilHP")
	suite.assert_equal(f.actor.health.current_hp, 2800.0, "anvil damage never damages Bossbody")
	suite.assert_true(anvil.collision_layer == 0 and anvil.get_node("Hurtbox").collision_layer == 0, "broken actual anvil retires collision and rewardtarget")
	suite.assert_true(f.bridge.prepare_frame(ticket) and f.bridge.rollback_frame(ticket), "anvil destruction compensates a refused Worldframe")
	suite.assert_equal(f.actor.launch_runtime_snapshot(), before, "refused anvil hit restores exact runtime and receipts")
	suite.assert_equal(anvil.collision_layer, 1, "refused anvil hit restores actual bodycollision")
	ticket = f.bridge.begin_frame(1)
	anvil.get_node("Hurtbox").receive_hit(_damage(f.player, 1, 150.0))
	suite.assert_true(f.bridge.prepare_frame(ticket) and _publish(f.bridge, ticket), "same real anvil hit retries once")
	await _cold(f)
	await _capture(f, "anvil-broken")
	var position: Vector2 = anvil.global_position
	anvil.global_position.x += 1.0
	suite.assert_true(not f.actor.prepare_launch_frame(2, _context(f, 2)).ok, "tampered native Forge geometry refuses preparation")
	anvil.global_position = position
	await _dispose(f)


func _slam_and_cooling() -> void:
	var f := await _fixture()
	_start(f, "forge_hammer_slam")
	for frame: int in range(1, 48):
		suite.assert_true(_step(f, frame), "slam preserves full48frame warning")
	var hp := float(f.player.health.current_hp)
	var before: Dictionary = f.actor.launch_runtime_snapshot()
	var effects_before: Dictionary = f.effects.snapshot()
	var health_before: Dictionary = f.player.health.transaction_snapshot()
	var modifiers_before: Dictionary = f.player.floor_rule_effect_snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(48)
	suite.assert_true(f.bridge.prepare_frame(ticket), "actual slam and finite owned burn settle")
	suite.assert_equal(f.player.health.current_hp, hp - 28.0, "actual slam delivers28 without hidden initial pooldamage")
	suite.assert_equal(f.runtime.forge_arena_snapshot().burns.size(), 1, "accepted damage installs finite source-owned burn")
	suite.assert_true(f.bridge.rollback_frame(ticket) and f.player.health.restore_transaction_snapshot(health_before), "slam and PlayerHP compensate refusal")
	suite.assert_equal(f.actor.launch_runtime_snapshot(), before, "slam refusal restores exact burn state")
	suite.assert_equal(f.effects.snapshot(), effects_before, "slam refusal restores exact ground pool claims")
	suite.assert_equal(f.player.floor_rule_effect_snapshot(), modifiers_before, "slam refusal restores source modifier state")
	suite.assert_true(_step(f, 48), "same slam retries once")
	var pools: Array = f.effects.snapshot().semantics.zones
	suite.assert_true(pools.size() == 1 and pools[0].geometry.radius == 32.0 and pools[0].lifetime_frames == 180 and pools[0].damage == 8.0 and pools[0].tick_frames == 60, "real slam pool owns exact authored r32 TTL180 tick8/60")
	f.player.global_position = Vector2(600, 32)
	for frame: int in range(49, 109):
		suite.assert_true(_step(f, frame), "burn advances only through accepted native frames")
	suite.assert_equal(f.player.health.current_hp, hp - 38.0, "actual finite burn damages10 exactly60frames afterslam")
	f.player.apply_floor_rule_modifier(&"foreign_burn", &"burn", &"apply", {"movement_multiplier": 1.0})
	f.player.global_position = Vector2(320, 48)
	before = f.actor.launch_runtime_snapshot()
	modifiers_before = f.player.floor_rule_effect_snapshot()
	ticket = f.bridge.begin_frame(109)
	suite.assert_true(f.bridge.prepare_frame(ticket), "native cooling entry removes only this Bossburn")
	suite.assert_true(f.runtime.forge_arena_snapshot().burns.is_empty(), "native cooling clears finite burn domain")
	suite.assert_true(f.player.floor_rule_effect_snapshot().modifiers.has("foreign_burn|burn"), "cooling preserves foreign burnownership")
	suite.assert_true(f.bridge.rollback_frame(ticket), "cooling compensates refused frame")
	suite.assert_equal(f.actor.launch_runtime_snapshot(), before, "cooling refusal restores exact occupancy and cooldown")
	suite.assert_equal(f.player.floor_rule_effect_snapshot(), modifiers_before, "cooling refusal restores both modifierowners")
	suite.assert_true(_step(f, 109), "same cooling entry retries once")
	await _cold(f)
	await _capture(f, "cooling")
	await _dispose(f)


func _spray() -> void:
	var f := await _fixture()
	f.player.global_position = f.actor.global_position + Vector2(80, 0)
	_start(f, "forge_furnace_spray")
	for frame: int in range(1, 66):
		suite.assert_true(_step(f, frame), "spray retains35warning and0/15/30hit timing")
	suite.assert_equal(f.player.health.current_hp, f.player.health.max_hp - 36.0, "actual locked spray delivers three12damage hits")
	var pools: Array = f.effects.snapshot().semantics.zones
	suite.assert_true(pools.size() == 1 and pools[0].geometry.shape == "cone" and pools[0].geometry.length == 96.0 and pools[0].geometry.radius == 32.0 and pools[0].lifetime_frames == 120, "actual spray creates one lockedcone96x32 poolTTL120")
	await _dispose(f)


func _pull() -> void:
	var f := await _fixture()
	_phase(f, 1200.0)
	var start := int(f.runtime.snapshot().runtime_frame)
	f.player.global_position = f.actor.global_position + Vector2(80, 0)
	_start(f, "forge_furnace_devour")
	for frame: int in range(start + 1, start + 56):
		suite.assert_true(_step(f, frame), "devour receives full55frame warning")
	var origin: Vector2 = f.player.global_position
	f.player._apply_frame_movement(Vector2.ZERO)
	suite.assert_true(is_equal_approx(origin.distance_to(f.player.global_position), 32.0 / 60.0), "actual collision movement pulls at exactly32px/sec")
	var pull: Vector2 = f.player._floor_rule_pull_velocity()
	suite.assert_true(is_equal_approx(pull.length(), 32.0) and pull.x < 0.0, "devour direction stays toward frozen origin")
	for recovery: int in range(20):
		f.player.action_state.advance_frame()
	origin = f.player.global_position
	f.player._apply_frame_movement(Vector2.RIGHT)
	suite.assert_true(f.player.global_position.x > origin.x, "ordinary movement escapes capped pull")
	suite.assert_true(not f.player.apply_floor_rule_modifier(&"invalid_pull", &"pull", &"apply", {"pull_x": 1.0, "pull_y": 0.0, "pull_speed": 33.0}), "source modifier rejects pull above32")
	f.player.global_position = f.actor.global_position + Vector2(8, 0)
	var hp := float(f.player.health.current_hp)
	suite.assert_true(_step(f, start + 56), "actual devour innerentry settles")
	suite.assert_equal(f.player.health.current_hp, hp - 40.0, "inner r16 damages40 once independent from outertick")
	suite.assert_true(_step(f, start + 57), "devour inner occupancy continues")
	suite.assert_equal(f.player.health.current_hp, hp - 40.0, "inner occupancy never repeats40damage")
	await _cold(f)
	await _capture(f, "devour")
	await _dispose(f)


func _eruption() -> void:
	var f := await _fixture()
	_phase(f, 1200.0)
	var start := int(f.runtime.snapshot().runtime_frame)
	f.player.global_position = Vector2(400, 180)
	_start(f, "forge_eruption")
	for frame: int in range(start + 1, start + 66):
		suite.assert_true(_step(f, frame), "eruption preserves65frame warning")
	var pools: Array = f.effects.snapshot().semantics.zones
	suite.assert_equal(pools.size(), 6, "actual eruption creates six finite ground pools")
	for first: Dictionary in pools:
		suite.assert_true(first.geometry.radius == 24.0 and first.lifetime_frames == 120, "eruption pool retains authored r24 TTL120")
		for second: Dictionary in pools:
			if first.id != second.id:
				suite.assert_true(Vector2(first.geometry.origin.x, first.geometry.origin.y).distance_to(Vector2(second.geometry.origin.x, second.geometry.origin.y)) >= 32.0, "actual eruption circles preserve authored spacing")
	suite.assert_equal(f.player.health.current_hp, f.player.health.max_hp, "actual sixcircle union retains48px centerescape route")
	await _capture(f, "eruption")
	_phase(f, 1000.0)
	suite.assert_true(f.effects.snapshot().semantics.zones.is_empty(), "next form retires prior owned groundhazards")
	suite.assert_equal(f.runtime.forge_arena_snapshot().cooling_pools.size(), 4, "form transition keeps four permanent cooling pools")
	await _dispose(f)


func _lava() -> void:
	var f := await _fixture()
	f.player.global_position = f.actor.global_position + Vector2(80, 0)
	_start(f, "forge_lava_toss")
	for frame: int in range(1, 48):
		suite.assert_true(_step(f, frame), "marked lava receives47frame warning")
	suite.assert_true(f.effects.payload_snapshot().zones.is_empty() and f.effects.payload_snapshot().projectiles.size() == 1, "lava launch creates projectile but no invented originpool")
	var found := false
	for frame: int in range(48, 100):
		await get_tree().physics_frame
		if not _step(f, frame):
			break
		if not f.effects.payload_snapshot().zones.is_empty():
			found = true
			var pool: Dictionary = f.effects.payload_snapshot().zones[0].definition
			suite.assert_true(pool.radius == 32.0 and pool.lifetime_frames == 300 and pool.damage == 8.0 and pool.tick_frames == 60, "actual impact creates authored r32 TTL300 lava pool")
			suite.assert_true(Vector2(pool.position.x, pool.position.y).distance_to(f.actor.global_position) > 32.0, "lava pool uses real projectile impactposition")
			break
	suite.assert_true(found, "actual lava projectile contacts native Player and creates impactpool")
	await _cold(f)
	await _capture(f, "lava-impact")
	await _dispose(f)


func _thrust_and_cyclone() -> void:
	var f := await _fixture()
	_phase(f, 2200.0)
	var start := int(f.runtime.snapshot().runtime_frame)
	f.player.global_position = f.actor.global_position + Vector2(40, 0)
	_start(f, "forge_forged_thrust")
	for frame: int in range(start + 1, start + 31):
		suite.assert_true(_step(f, frame), "thrust receives30frame warning")
	suite.assert_equal(f.player.health.current_hp, f.player.health.max_hp - 36.0, "actual thrust damages36")
	suite.assert_true(f.player.get("_knockback_velocity").x > 0.0, "authored32knockback reaches actual Player reaction")
	await _dispose(f)
	f = await _fixture()
	_phase(f, 2200.0)
	start = int(f.runtime.snapshot().runtime_frame)
	f.player.global_position = f.actor.global_position + Vector2(80, 0)
	f.player.health.acquire_invulnerability_source(&"cyclone-fixture")
	_start(f, "forge_forged_cyclone")
	for frame: int in range(start + 1, start + 42):
		suite.assert_true(_step(f, frame), "cyclone receives42frame warning")
	var origin: Vector2 = f.actor.global_position
	suite.assert_true(_step(f, start + 42), "cyclone begins native movement")
	suite.assert_close(origin.distance_to(f.actor.global_position), 48.0 / 60.0, "actual cyclone follows48px/sec frozen route", 0.0001)
	f.player.global_position = origin + Vector2(-80, 0)
	origin = f.actor.global_position
	suite.assert_true(_step(f, start + 43) and f.actor.global_position.x > origin.x, "cyclone cannot retarget frozen route after Playermoves")
	await _capture(f, "cyclone")
	await _dispose(f)


func _enrage() -> void:
	var f := await _fixture()
	var original: Array = f.runtime.forge_arena_snapshot().cooling_pools
	for frame: int in range(1, 12601):
		if not f.runtime.advance_frame(frame, _context(f, frame), false).ok:
			suite.assert_true(false, "actual Forge advances entire12600frame enrageclock")
			break
	suite.assert_true(f.runtime.snapshot().mechanism_state.enraged, "authored12600frame boundary enters enrage")
	f.actor.project_runtime_snapshot(f.actor.launch_runtime_snapshot())
	f.effects.dispose_native_effects()
	f.effects = Effects.new()
	f.effects.configure("run-forge-arena", 12600)
	f.effects.configure_native_payloads(f.root)
	f.player.set("_runtime_frame", 12600)
	f.bridge = Bridge.new()
	suite.assert_true(f.bridge.configure(f.player, f.registry, [f.actor], f.effects), "enraged aggregate binds equal acceptednativeclocks")
	f.player.global_position = Vector2(320, 80)
	_start(f, "forge_enrage_ultimate")
	for frame: int in range(12601, 12681):
		suite.assert_true(_step(f, frame), "ultimate retains full80frame warning")
	suite.assert_equal(f.player.health.current_hp, f.player.health.max_hp, "ultimate cooling-pool corridor remains safe from actualstripdamage")
	var pools: Array = f.effects.snapshot().semantics.zones
	suite.assert_true(pools.size() == 3 and pools.all(func(row: Dictionary): return row.lifetime_frames == 300), "ultimate creates exactlythree finiteTTL300strippools")
	suite.assert_equal(f.runtime.forge_arena_snapshot().cooling_pools, original, "enrage preserves actual permanentcoolingpools")
	for frame: int in range(12681, 12741):
		suite.assert_true(_step(f, frame), "ultimate pool firsttick advances acceptedclock")
	suite.assert_equal(f.player.health.current_hp, f.player.health.max_hp, "cooling corridor remains safe from finitepoolticks")
	await _cold(f)
	await _capture(f, "enrage")
	await _dispose(f)


func _phase(f: Dictionary, amount: float) -> void:
	var frame := int(f.runtime.snapshot().runtime_frame) + 1
	var ticket: Dictionary = f.bridge.begin_frame(frame)
	suite.assert_true(f.actor.get_node("Hurtbox").receive_hit(_damage(f.player, frame + 1000, amount)) > 0.0, "phase fixture authenticates the actual Forge principal target")
	suite.assert_true(f.bridge.prepare_frame(ticket) and _publish(f.bridge, ticket), "real Boss damage starts noheal formtransition")
	var after_hp := float(f.actor.health.current_hp)
	for clock: int in range(frame + 1, frame + 61):
		suite.assert_true(_step(f, clock), "form receives full60frame phasecue")
	suite.assert_equal(f.actor.health.current_hp, after_hp, "Forge transformationneverheals")


func _context(f: Dictionary, frame: int) -> Dictionary:
	var delta: Vector2 = f.actor.global_position.direction_to(f.player.global_position)
	return {"runtime_frame": frame, "source_position": {"x": f.actor.global_position.x, "y": f.actor.global_position.y}, "target_position": {"x": f.player.global_position.x, "y": f.player.global_position.y}, "facing_direction": {"x": delta.x, "y": delta.y}, "target_id": "player:1"}


func _start(f: Dictionary, action: String) -> void:
	var cancelled: Dictionary = f.runtime.cancel_action(&"fixture_select")
	for generation: int in cancelled.retired_generations:
		f.registry.retire(f.actor.hostile_source_id, generation)
	var started: Dictionary = f.runtime.request_action(action, _context(f, int(f.runtime.snapshot().runtime_frame)))
	suite.assert_true(started.ok, "production Forge admits selected " + action)
	for fact: Dictionary in started.get("threat_facts", []):
		suite.assert_true(f.registry.register_fact(Actions.native_threat_fact(fact)), "real Forge warning enters native registry")
	f.actor.project_runtime_snapshot(f.actor.launch_runtime_snapshot())


func _step(f: Dictionary, frame: int) -> bool:
	var ticket: Dictionary = f.bridge.begin_frame(frame)
	if ticket.is_empty() or not f.bridge.prepare_frame(ticket) or not _publish(f.bridge, ticket):
		print("FORGE_NATIVE_REFUSAL frame=", frame, " action=", f.runtime.snapshot().action.action_id)
		if not ticket.is_empty():
			f.bridge.rollback_frame(ticket)
		return false
	return true


func _cold(f: Dictionary) -> void:
	var cold: Dictionary = f.actor.native_cold_snapshot(func(_source: Node): return {})
	suite.assert_true(not cold.is_empty() and f.actor.can_restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "actual Forge cold snapshot validates at accepted boundary")
	if cold.is_empty():
		return
	var encoded := Replay.encode_replay_json(cold)
	suite.assert_true(encoded.ok and Replay.decode_replay_json(encoded.json).replay == cold, "typed Replay codec preserves exact Forge arena and burn receipts")
	var registry := ContentRegistry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var binding := ContentSnapshot.snapshot(registry)
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("forge_arena")
	var storage := Save.new()
	storage.configure(root, "test-forge", binding)
	suite.assert_true(storage.save_profile("forge_v6", "base", {"codec": encoded.json}).ok, "physical SaveService stores exact Forge native aggregate")
	var fresh := Save.new()
	fresh.configure(root, "test-forge", binding)
	var primary: Variant = fresh.inspect_profile("forge_v6", "base")
	suite.assert_true(primary.ok and Replay.decode_replay_json(primary.payload.payload.codec).replay == cold, "fresh physical recovery retains exact Forge arena")
	var forged := cold.duplicate(true)
	forged.actor.runtime.forge_arena_state.covers[0].current_hp += 1.0
	suite.assert_true(not f.actor.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "native cold state rejects inventedanvilHP")
	suite.assert_true(f.actor.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "cold restore reconstructs actual Forge physical state")
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(room)
	var twin := Boss.instantiate() as Node2D
	twin.process_mode = Node.PROCESS_MODE_DISABLED
	twin.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	world.add_child(twin)
	twin.global_position = f.actor.global_position
	var parser := Definition.new()
	parser.configure(Content.boss("forge_colossus"))
	twin.configure_launch_definition(parser.runtime_projection(), IDENTITY)
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_forge_colossus":
			twin.configure_launch_room_motion(room, template)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh physical Forge reconstructs every declared nativeconstruct")
	suite.assert_equal(twin.native_forge_arena_snapshot(), f.actor.native_forge_arena_snapshot(), "fresh cold Forge retains exact finite burn and cooling provenance")
	world.queue_free()
	await get_tree().process_frame


func _capture(f: Dictionary, pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		for holder: String in ["ArenaConstructs", "ForgeFixtures"]:
			for body: Node2D in f.actor.get_node(holder).get_children():
				var colors: Dictionary = {}
				var center := Vector2i(body.global_position * Vector2(pixels.get_size()) / Vector2(640, 360))
				var extent := ceili(20.0 * float(pixels.get_width()) / 640.0)
				for y: int in range(maxi(0, center.y - extent), mini(pixels.get_height(), center.y + extent)):
					for x: int in range(maxi(0, center.x - extent), mini(pixels.get_width(), center.x + extent)):
						colors[pixels.get_pixel(x, y).to_rgba32()] = true
				suite.assert_true(colors.size() >= 4, "actual Forge fixture raster is nonblank at " + str(resolution))
		var path := "res://build/visual-evidence/forge-arena/native-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		suite.assert_equal(pixels.save_png(path), OK, "native Forge screenshot retained")


func _dispose(f: Dictionary) -> void:
	suite.assert_true(f.effects.dispose_native_effects(), "Forge disposal retires native payload and semantic ownership")
	var modifiers: Dictionary = f.player.floor_rule_effect_snapshot().modifiers
	suite.assert_true(not modifiers.has("forge_burn:forge-arena-owner|burn") and not modifiers.has("launch_forge_pull|pull"), "disposed native Forge leaves no owned burn or pullmodifier")
	for key: String in ["actor", "player", "root", "room"]:
		f[key].queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _damage(player: Node2D, token: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": IDENTITY.run_id, "target_id": IDENTITY.hostile_source_id, "hostile_source_id": "player:sword", "attack_generation": token, "action_token": token, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true
