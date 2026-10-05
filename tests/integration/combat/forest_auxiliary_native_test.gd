extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Boss := preload("res://data/content_packs/base/assets/bosses/launch/boss_forest_heart.tscn")
const Player := preload("res://scenes/player/player.tscn")
const Room := preload("res://data/content_packs/base/assets/rooms/launch/room_boss_forest_heart.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const IDENTITY := {"run_id": "run-forest-aux", "hostile_source_id": "forest-aux-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _flowers()
	await _seed_cancel()
	await _seed_burst()
	await _cage()
	await _cage_placement()
	await _drain()
	await _erosion()
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		for construct: String in ["root", "sac", "cage"]:
			await _normal_weapon(weapon, construct)
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
	parser.configure(Content.boss("forest_heart"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), IDENTITY).ok, "Forest auxiliary binds production Boss")
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_forest_heart":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "Forest auxiliary binds physical production room")
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-forest-aux")
	player.global_position = Vector2(600, 180)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-forest-aux", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "Forest auxiliary shares real accepted-frame bridge")
	await get_tree().physics_frame
	return {"room": room, "actor": actor, "player": player, "root": root, "effects": effects, "registry": registry, "bridge": bridge, "runtime": actor.get("_launch_runtime")}


func _flowers() -> void:
	var f := await _fixture()
	var state: Dictionary = f.runtime.forest_auxiliary_snapshot()
	suite.assert_equal(state.sacs.size(), 4, "production Boss creates four HP30 native sacs")
	suite.assert_equal(f.actor.get_node("AuxiliaryConstructs").get_child_count(), 7, "four sacs and three flowers are actual uncounted bodies")
	f.player.global_position = Vector2(96, 180)
	f.player.health.lose_health(42.0, f.player)
	var before: Dictionary = f.actor.launch_runtime_snapshot()
	var player_before: Dictionary = f.player.health.transaction_snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(1)
	suite.assert_true(f.bridge.prepare_frame(ticket), "actual flower prepares accepted heal")
	suite.assert_equal(f.player.health.current_hp, f.player.health.max_hp - 22.0, "actual flower heals20 through HealthComponent")
	suite.assert_true(f.bridge.rollback_frame(ticket), "actual flower heal rolls back refused frame")
	suite.assert_true(f.player.health.restore_transaction_snapshot(player_before), "outer Player owner restores refused flower health")
	suite.assert_equal(f.actor.launch_runtime_snapshot(), before, "flower refusal restores exact unspent state")
	suite.assert_equal(f.player.health.transaction_snapshot(), player_before, "flower refusal restores actual Player HP and ledger")
	suite.assert_true(_step(f, 1) and _step(f, 2), "same flower retries then remains consumed")
	suite.assert_equal(f.player.health.current_hp, f.player.health.max_hp - 22.0, "used flower cannot repeat heal on next frame")
	f.player.health.heal(1000.0)
	f.player.health.lose_health(7.0, f.player)
	f.player.global_position = Vector2(320, 288)
	suite.assert_true(_step(f, 3), "partially missing HP consumes second flower")
	suite.assert_equal(f.runtime.forest_auxiliary_snapshot().flowers[1].heal_amount, 7.0, "flower retains actual partial7HP heal")
	f.player.global_position = Vector2(544, 180)
	suite.assert_true(_step(f, 4) and not f.runtime.forest_auxiliary_snapshot().flowers[2].used, "full health preserves remaining flower")
	await _cold(f)
	await _capture(f, "flowers")
	await _dispose(f)


func _seed_cancel() -> void:
	var f := await _fixture()
	f.player.global_position = Vector2(480, 136)
	_start(f, "matriarch_void_seed")
	var before: Dictionary = f.actor.launch_runtime_snapshot()
	var sac: Node2D = f.actor.get_node("AuxiliaryConstructs").get_child(1)
	var ticket: Dictionary = f.bridge.begin_frame(1)
	suite.assert_equal(sac.get_node("Hurtbox").receive_hit(_damage(f.player, 1, 30.0)), 30.0, "actual weapon breaks markedHP30 sac")
	suite.assert_true(f.runtime.snapshot().action.phase == "IDLE" and not f.registry.contains_point(Vector2(464, 136), 40), "marked sac destruction immediately retires owned seed burst")
	suite.assert_true(f.bridge.prepare_frame(ticket) and f.bridge.rollback_frame(ticket), "seed cancellation rolls back refused native frame")
	suite.assert_equal(f.actor.launch_runtime_snapshot(), before, "refused sac hit restores exact warning ownership")
	ticket = f.bridge.begin_frame(1)
	sac.get_node("Hurtbox").receive_hit(_damage(f.player, 1, 30.0))
	suite.assert_true(f.bridge.prepare_frame(ticket) and _publish(f.bridge, ticket), "same real hit retries seed cancellation")
	suite.assert_true(sac.collision_layer == 0 and not sac.is_in_group("enemies"), "destroyed sac loses collision without adding encounter reward")
	for frame: int in range(2, 42):
		if not _step(f, frame):
			suite.assert_true(false, "cancelled seed continuation frame%d" % frame)
			break
	var seed: Dictionary = f.runtime.forest_auxiliary_snapshot().seeds[0]
	suite.assert_true(seed.cancelled_frame == 1 and seed.burst_frame == -1, "accepted killed-sac seed never bursts")
	await _cold(f)
	await _capture(f, "seed-cancelled")
	await _dispose(f)


func _seed_burst() -> void:
	var f := await _fixture()
	f.player.global_position = Vector2(470, 136)
	_start(f, "matriarch_void_seed")
	for frame: int in range(1, 40):
		suite.assert_true(_step(f, frame), "seed receives entire40frame warning")
	suite.assert_equal(f.player.health.current_hp, f.player.health.max_hp, "marked sac deals no early damage")
	var historical: Dictionary = f.actor.native_cold_snapshot(func(_source: Node): return {})
	historical.actor.runtime.schema_version = 3
	historical.actor.runtime.erase("forest_auxiliary")
	suite.assert_true(f.actor.restore_native_cold_snapshot(historical, func(_binding: Dictionary): return null), "historical active seed adopts its frozen target without invented sac ownership")
	suite.assert_true(_step(f, 40), "seed burst and persistent native pool settle")
	suite.assert_equal(f.player.health.current_hp, f.player.health.max_hp - 47.0, "real seed delivers35 burst and first12damage pool tick")
	var pools: Array = f.effects.snapshot().semantics.zones.filter(func(row: Dictionary): return row.action_id.contains("forest_seed_pool"))
	suite.assert_true(pools.size() == 1 and pools[0].geometry.radius == 29.0 and pools[0].lifetime_frames == 480 and pools[0].tick_frames == 60, "owned seed pool has exact r29 TTL480 tick60")
	suite.assert_true(f.effects.can_restore_launch_transaction_snapshot(f.effects.snapshot()), "real seed effects retain valid cold transaction state")
	await _cold(f)
	await _capture(f, "seed-burst")
	await _dispose(f)


func _cage() -> void:
	var f := await _fixture()
	_phase2(f)
	f.player.global_position = Vector2(360, 220)
	var start := int(f.runtime.snapshot().runtime_frame)
	_start(f, "matriarch_void_cage")
	for frame: int in range(start + 1, start + 71):
		suite.assert_true(_step(f, frame), "cage preserves70frame warning")
	var cages: Array = f.runtime.forest_auxiliary_snapshot().cages
	suite.assert_equal(cages.size(), 3, "real cage creates exactly threeHP50 physical walls")
	if cages.size() != 3:
		await _dispose(f)
		return
	suite.assert_true(cages.all(func(row: Dictionary): return row.current_hp == 50.0 and row.lifetime_frames == 300), "cageHP and TTL are authored values")
	var pulse: Array = f.effects.snapshot().semantics.zones.filter(func(row: Dictionary): return row.action_id.contains("forest_cage_pulse"))
	suite.assert_true(pulse.size() == 1 and pulse[0].warning_frames == 30 and pulse[0].damage == 8.0, "real cage inner pulse independently warns30frames")
	await _capture(f, "cage-warning")
	var born := int(cages[0].spawn_frame)
	for frame: int in range(born + 1, born + 30):
		suite.assert_true(_step(f, frame), "cage pulse preserves own warning")
	var hp := float(f.player.health.current_hp)
	suite.assert_true(_step(f, born + 30), "actual inner pulse resolves after warning")
	suite.assert_equal(f.player.health.current_hp, hp - 8.0, "real cage pulse loses8PlayerHP")
	f.player.health.acquire_invulnerability_source(&"cage-test")
	suite.assert_true(f.runtime.add_control_source("cage-clock-fixture", "stop", 180, 1.0), "primary recovery pause preserves independent accepted cage lifetime")
	f.player.global_position = Vector2(600, 180)
	var wall: Node2D = f.actor.get_node("AuxiliaryConstructs").get_child(7)
	var ticket: Dictionary = f.bridge.begin_frame(born + 31)
	wall.get_node("Hurtbox").receive_hit(_damage(f.player, 2, 50.0))
	suite.assert_true(f.bridge.prepare_frame(ticket) and f.bridge.rollback_frame(ticket), "cage wall destruction compensates refused frame")
	suite.assert_equal(wall.collision_layer, 1, "cage wall refusal restores physical barrier")
	ticket = f.bridge.begin_frame(born + 31)
	wall.get_node("Hurtbox").receive_hit(_damage(f.player, 2, 50.0))
	suite.assert_true(f.bridge.prepare_frame(ticket) and _publish(f.bridge, ticket), "actual wallHP50 hit retries")
	for frame: int in range(born + 32, born + 261):
		if not _step(f, frame):
			suite.assert_true(false, "cage accepted continuation frame%d" % frame)
			break
	var collapse: Array = f.effects.snapshot().semantics.zones.filter(func(row: Dictionary): return row.action_id.contains("forest_cage_collapse"))
	suite.assert_true(collapse.size() == 2 and collapse.all(func(row: Dictionary): return row.warning_frames == 40 and row.damage == 15.0), "only two surviving segments reserve40frame15damage collapse")
	await _cold(f)
	for frame: int in range(born + 261, born + 300):
		suite.assert_true(_step(f, frame), "cage collapse accepts full warning lifetime")
	f.player.health.release_invulnerability_source(&"cage-test")
	f.player.global_position = Vector2(cages[1].position.x, cages[1].position.y)
	hp = float(f.player.health.current_hp)
	suite.assert_true(_step(f, born + 300), "real surviving segment collapse resolves after40warning frames")
	suite.assert_equal(f.player.health.current_hp, hp - 15.0, "actual native segment collapse delivers15damage")
	suite.assert_true(f.runtime.forest_auxiliary_snapshot().cages.filter(func(row: Dictionary): return row.attack_generation == cages[0].attack_generation).all(func(row: Dictionary): return row.expired), "physical cage expires at300accepted frames")
	await _dispose(f)


func _drain() -> void:
	var f := await _fixture()
	_phase2(f)
	f.player.global_position = Vector2(400, 144)
	var start := int(f.runtime.snapshot().runtime_frame)
	_start(f, "matriarch_drain_roots")
	for frame: int in range(start + 1, start + 50):
		suite.assert_true(_step(f, frame), "drain preserves50frame locked lane warning")
	var before: Dictionary = f.actor.launch_runtime_snapshot()
	var player_before: Dictionary = f.player.health.transaction_snapshot()
	var hp := float(f.actor.health.current_hp)
	var ticket: Dictionary = f.bridge.begin_frame(start + 50)
	suite.assert_true(f.bridge.prepare_frame(ticket), "real drain hit prepares actual-loss body healing")
	suite.assert_equal(f.actor.health.current_hp, hp + 5.0, "actual5PlayerHP loss heals5BossHP")
	suite.assert_true(f.bridge.rollback_frame(ticket), "real drain health and cap receipts roll back")
	suite.assert_true(f.player.health.restore_transaction_snapshot(player_before), "outer Player owner restores refused drain health")
	suite.assert_equal(f.actor.launch_runtime_snapshot(), before, "drain refusal restores exact Boss state and budgets")
	suite.assert_equal(f.player.health.transaction_snapshot(), player_before, "drain refusal restores exact Player loss")
	suite.assert_true(_step(f, start + 50), "same drain identity retries after refusal")
	f.player.health.acquire_invulnerability_source(&"drain-test")
	for frame: int in range(start + 51, start + 96):
		suite.assert_true(_step(f, frame), "drain offsets15 30 45 accept")
	suite.assert_equal(f.actor.health.current_hp, hp + 5.0, "invulnerable drain ticks grant zero healing")
	suite.assert_equal(f.runtime.forest_auxiliary_snapshot().drain_healed_total, 5.0, "drain cap spends actual accepted health gain only")
	var events: Array = f.runtime.forest_auxiliary_snapshot().events.filter(func(row: Dictionary): return row.kind == "drain")
	suite.assert_true(events.size() == 4 and events[1].actual_loss == 0.0, "all four drain outcomes retain honest deduplicated receipts")
	await _cold(f)
	await _dispose(f)


func _cage_placement() -> void:
	var f := await _fixture()
	_phase2(f)
	f.player.global_position = Vector2(360, 220)
	var start := int(f.runtime.snapshot().runtime_frame)
	_start(f, "matriarch_void_cage")
	for frame: int in range(start + 1, start + 70):
		suite.assert_true(_step(f, frame), "cage safe admission retains warning")
	var obstacle := StaticBody2D.new()
	obstacle.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 12)
	collision.shape = shape
	obstacle.add_child(collision)
	add_child(obstacle)
	obstacle.global_position = Vector2(344, 244)
	await get_tree().physics_frame
	suite.assert_true(_step(f, start + 70), "occupied cage segment delays activation while accepted time continues")
	suite.assert_true(f.runtime.snapshot().action.phase == "WARNING" and f.runtime.forest_auxiliary_snapshot().cages.is_empty(), "occupied segment cannot create an unavoidable physical cage")
	obstacle.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	var before: Dictionary = f.actor.launch_runtime_snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(start + 71)
	suite.assert_true(f.bridge.prepare_frame(ticket), "freed cage safely commits after preserved warning")
	obstacle = StaticBody2D.new()
	obstacle.collision_layer = 1
	collision = CollisionShape2D.new()
	collision.shape = shape.duplicate()
	obstacle.add_child(collision)
	add_child(obstacle)
	obstacle.global_position = Vector2(344, 244)
	await get_tree().physics_frame
	suite.assert_true(f.bridge.prepare_frame_publication(ticket).is_empty(), "new physical obstruction refuses late cage publication")
	suite.assert_true(f.bridge.rollback_frame(ticket), "late cage obstruction compensates constructs and pulse warning")
	suite.assert_equal(f.actor.launch_runtime_snapshot(), before, "late cage refusal restores exact immutable decision")
	obstacle.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	suite.assert_true(_step(f, start + 71), "safe cage retries after late refusal")
	await _dispose(f)


func _erosion() -> void:
	var f := await _fixture()
	# Advance the deterministic encounter clock into its authored enrage regime.
	var checkpoint: Dictionary = f.actor.call("_actor_state")
	checkpoint.runtime.runtime_frame = 16200
	checkpoint.runtime.action.last_runtime_frame = 16200
	checkpoint.runtime.control.runtime_frame = 16200
	checkpoint.runtime.conversion.runtime_frame = 16200
	checkpoint.runtime.arena_state.runtime_frame = 16200
	checkpoint.runtime.forest_auxiliary.runtime_frame = 16200
	checkpoint.runtime.mechanism_state.enraged = true
	checkpoint.runtime.mechanism_state.action_enraged = false
	suite.assert_true(f.actor.call("_restore_actor_state", checkpoint), "enrage fixture uses native validated encounter snapshot")
	f.player.set("_runtime_frame", 16200)
	f.effects.dispose_native_effects()
	f.effects = Effects.new()
	f.effects.configure("run-forest-aux", 16200)
	f.effects.configure_native_payloads(f.root)
	f.bridge = Bridge.new()
	suite.assert_true(f.bridge.configure(f.player, f.registry, [f.actor], f.effects), "enrage fixture rebinds accepted-frame authorities")
	f.player.health.acquire_invulnerability_source(&"erosion-test")
	f.player.global_position = Vector2(320, 220)
	var start := 16200
	_start(f, "matriarch_enrage_dissolution")
	for frame: int in range(start + 1, start + 81):
		suite.assert_true(_step(f, frame), "edge erosion receives full80frame warning")
	suite.assert_equal(f.runtime.forest_auxiliary_snapshot().erosion_steps, 1, "first enrage creates one16px edge erosion step")
	suite.assert_equal(f.actor.get_node("AuxiliaryConstructs").get_child_count(), 11, "edge erosion creates four native perimeter barriers")
	suite.assert_true(f.actor.get_node("AuxiliaryConstructs").get_child(7).collision_layer == 1, "erosion blocks actual movement through eroded perimeter")
	await _cold(f)
	await _capture(f, "erosion")
	var ticket: Dictionary = f.bridge.begin_frame(start + 81)
	f.actor.get_node("Hurtbox").receive_hit(_damage(f.player, 100, 1400.0))
	suite.assert_true(f.bridge.prepare_frame(ticket) and _publish(f.bridge, ticket), "Forest source death retires auxiliary constructs and semantic zones")
	suite.assert_true(f.effects.snapshot().semantics.zones.is_empty(), "terminal Forest owns no remaining harmful pools")
	for construct: StaticBody2D in f.actor.get_node("AuxiliaryConstructs").get_children():
		suite.assert_true(construct.collision_layer == 0 and not construct.visible, "source death clears every auxiliary collision and visual")
	await _dispose(f)


func _phase2(f: Dictionary) -> void:
	f.actor.get_node("Hurtbox").receive_hit(_damage(f.player, 900, 600.0))
	for frame: int in range(1, 62):
		suite.assert_true(_step(f, frame), "P2 enters through authentic600damage and transition cue")
	suite.assert_equal(f.actor.health.current_hp, 800.0, "P2 fixture preserves authentic trunkHP800")


func _normal_weapon(weapon: String, construct: String) -> void:
	var f := await _fixture()
	var index := 0
	if construct == "cage":
		_phase2(f)
		f.player.global_position = Vector2(360, 220)
		var start := int(f.runtime.snapshot().runtime_frame)
		_start(f, "matriarch_void_cage")
		for frame: int in range(start + 1, start + 71):
			suite.assert_true(_step(f, frame), "real weapon fixture creates authored cage")
		index = 7
	f.actor.process_mode = Node.PROCESS_MODE_INHERIT
	f.actor.set_process(false)
	f.actor.set_physics_process(false)
	f.player.process_mode = Node.PROCESS_MODE_INHERIT
	f.player.set_physics_process(false)
	f.player.get_node("TimeManager").set_process(false)
	f.player.get_node("RewindRecorder").set_process(false)
	suite.assert_true(f.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": f.player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "normal%sloadout binds Forest construct weapon producer" % weapon)
	var holder: Node = f.actor.get_node("ArenaConstructs" if construct == "root" else "AuxiliaryConstructs")
	var target: Node2D = holder.get_child(index)
	var hp := float(target.native_construct_snapshot().current_hp)
	f.player.global_position = target.global_position - Vector2(42, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}) and f.player.try_action(&"weapon_primary"), "normal%sinput attacks actual Forest construct" % weapon)
	for frame: int in range(120):
		if frame == 40:
			f.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
		suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}), "normal%sForest action accepts frame%d" % [weapon, frame])
		await get_tree().physics_frame
	suite.assert_true(float(target.native_construct_snapshot().current_hp) < hp, "normal%sphysical input damages real%sHurtbox" % [weapon, construct])
	suite.assert_true(not f.actor.get_node("AuxiliaryConstructs").get_child(4).is_in_group("enemies"), "normal weapons preserve flower as uncounted pickup")
	f.player.cancel_transient_actions()
	await _dispose(f)


func _start(f: Dictionary, action: String) -> void:
	var cancelled: Dictionary = f.runtime.cancel_action(&"fixture_select")
	for generation: int in cancelled.retired_generations:
		f.registry.retire(f.actor.hostile_source_id, generation)
	var frame := int(f.runtime.snapshot().runtime_frame)
	var delta: Vector2 = f.actor.global_position.direction_to(f.player.global_position)
	var context := {"runtime_frame": frame, "source_position": {"x": f.actor.global_position.x, "y": f.actor.global_position.y}, "target_position": {"x": f.player.global_position.x, "y": f.player.global_position.y}, "facing_direction": {"x": delta.x, "y": delta.y}, "target_id": "player:1"}
	var result: Dictionary = f.runtime.request_action(action, context)
	suite.assert_true(result.ok, "production runtime admits selected " + action)
	for fact: Dictionary in result.get("threat_facts", []):
		suite.assert_true(f.registry.register_fact(Actions.native_threat_fact(fact)), "real frozen warning joins actual threat registry")
	f.actor.project_runtime_snapshot(f.actor.launch_runtime_snapshot())


func _step(f: Dictionary, frame: int) -> bool:
	var ticket: Dictionary = f.bridge.begin_frame(frame)
	if ticket.is_empty() or not f.bridge.prepare_frame(ticket) or not _publish(f.bridge, ticket):
		if not f.get("printed_failure", false):
			print("FOREST_NATIVE_REFUSAL frame=", frame, " phase=", f.runtime.snapshot().action.phase)
			f["printed_failure"] = true
		if not ticket.is_empty():
			f.bridge.rollback_frame(ticket)
		return false
	return true


func _cold(f: Dictionary) -> void:
	var cold: Dictionary = f.actor.native_cold_snapshot(func(_source: Node): return {})
	suite.assert_true(not cold.is_empty() and f.actor.can_restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "native auxiliary cold state validates at accepted boundary")
	if cold.is_empty():
		return
	var forged := cold.duplicate(true)
	forged.actor.runtime.forest_auxiliary.sacs[0].current_hp -= 1.0
	suite.assert_true(not f.actor.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "native cold state rejects invented sacHP")
	suite.assert_true(f.actor.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "native cold reconstruction retains all auxiliary state")
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
	parser.configure(Content.boss("forest_heart"))
	twin.configure_launch_definition(parser.runtime_projection(), IDENTITY)
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_boss_forest_heart":
			twin.configure_launch_room_motion(room, template)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh physical Boss reconstructs all auxiliary constructs")
	suite.assert_equal(twin.get("_launch_runtime").forest_auxiliary_snapshot(), f.runtime.forest_auxiliary_snapshot(), "fresh auxiliary cold reconstruction is exact")
	world.queue_free()
	await get_tree().process_frame


func _capture(f: Dictionary, pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		for construct: Node2D in f.actor.get_node("AuxiliaryConstructs").get_children():
			var colors: Dictionary = {}
			var center := Vector2i(construct.global_position * Vector2(pixels.get_size()) / Vector2(640, 360))
			var extent := ceili(16.0 * float(pixels.get_width()) / 640.0)
			for y: int in range(maxi(0, center.y - extent), mini(pixels.get_height(), center.y + extent)):
				for x: int in range(maxi(0, center.x - extent), mini(pixels.get_width(), center.x + extent)):
					colors[pixels.get_pixel(x, y).to_rgba32()] = true
			suite.assert_true(colors.size() >= 3, "actual Forest auxiliary raster renders at " + str(resolution))
		var output := "res://build/visual-evidence/p15b-native-arena/forest-aux-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native Forest auxiliary screenshot retained")


func _dispose(f: Dictionary) -> void:
	f.effects.dispose_native_effects()
	for key: String in ["actor", "player", "root", "room"]:
		f[key].queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _damage(player: Node2D, token: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": "run-forest-aux", "target_id": "forest-test-target", "hostile_source_id": "player:sword", "attack_generation": token, "action_token": token, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true
