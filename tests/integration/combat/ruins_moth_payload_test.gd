extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_corrosive_moth.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const RoomScene := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Coordinator := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const ContentRegistry := preload("res://scripts/content/content_registry.gd")
const RiftScene := preload("res://scenes/time/time_rift.tscn")
const PayloadProjection := preload("res://scripts/enemies/launch/launch_hostile_payload_projection.gd")

class RejectedFrameBridge extends "res://scripts/enemies/launch/hostile_frame_bridge.gd":
	var kill_actor: Node2D
	var kill_at := 31
	var reject_at := -1
	var time_source_at := -1
	var payload_effects: RefCounted

	func begin_frame(frame: int) -> Dictionary:
		var ticket := super.begin_frame(frame)
		if not ticket.is_empty() and frame == kill_at and is_instance_valid(kill_actor):
			kill_actor.get_node("HealthComponent").lose_health(1000.0, null)
		if not ticket.is_empty() and frame == time_source_at:
			time_source_at = -1
			for node: Node2D in payload_effects.native_payload_nodes():
				node.apply_time_stop_source(&"rollback-stop", 2.0 / 60.0)
		return ticket

	func finalize_frame_publication(publication: Dictionary) -> bool:
		if publication.ticket.runtime_frame == reject_at:
			reject_at = -1
			return false
		return super.finalize_frame_publication(publication)

var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	get_viewport().size = Vector2i(640, 360)
	var authority := Effects.new()
	suite.assert_true(authority.has_method("configure_native_payloads"), "Moth requires actual native projectile and pool projections in the hostile effect authority")
	if authority.has_method("configure_native_payloads"):
		await _test_native_payload(false)
		await _test_native_payload(true)
		await _test_native_death_warning()
		await _test_elite_lanes()
	suite.finish(get_tree())


func _template() -> Dictionary:
	var values: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	for value: Dictionary in values:
		if value.id == "room_combat_open_field":
			return value.duplicate(true)
	return {}


func _test_native_payload(with_wall: bool) -> void:
	var registry := ContentRegistry.new()
	var report: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "native Moth test loads the actual content registry")
	if report.has_blocking_errors():
		return
	var player := PlayerScene.instantiate() as Node2D
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "character_talents": [], "weapon_id": "sword", "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}
	suite.assert_true(player.configure_loadout(config) and player.configure_run(&"run-p15"), "actual Launch Wanderer owns real Character damage contracts")
	player.global_position = Vector2(160, 100)
	player.set_meta(&"stable_target_key", "player")
	var room := RoomScene.instantiate() as Node2D
	add_child(room)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var actor := ActorScene.instantiate() as Node2D
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = Vector2(100, 100)
	suite.assert_true(CombatFeedback.ensure_actor_proxy_for_test(actor) == null and actor.get_node_or_null("PixelProxyActor") == null, "owned native Moth raster cannot be covered by a legacy actor proxy")
	var parser := Enemy.new()
	parser.configure(Content.enemy("corrosive_moth"))
	var identity := {"run_id": "run-p15", "hostile_source_id": "hostile-moth-native", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok and actor.configure_launch_room_motion(room, _template()).ok, "actual Moth scene binds authored body and native room bounds")
	var native_root := Node2D.new()
	add_child(native_root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-p15") and effects.configure_native_payloads(native_root), "native payload owner is independent of the static room and parent actor")
	var threats := Threats.new()
	var context := {"runtime_frame": 0, "source_position": {"x": 100.0, "y": 100.0}, "target_position": {"x": 160.0, "y": 100.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player"}
	var started: Dictionary = actor.get("_launch_runtime").request_action("corrosive_moth.corrosive_spit", context)
	for fact: Dictionary in started.threat_facts:
		threats.register_fact(Coordinator.native_threat_fact(fact))
	var bridge := RejectedFrameBridge.new()
	bridge.kill_actor = actor
	bridge.payload_effects = effects
	suite.assert_true(bridge.configure(player, threats, [actor], effects) and player.configure_hostile_frame_participant(bridge), "native Moth effects participate in the actual Player transaction")
	var wall: StaticBody2D
	if with_wall:
		wall = StaticBody2D.new()
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(4, 64)
		collider.shape = shape
		wall.add_child(collider)
		add_child(wall)
		wall.global_position = Vector2(125, 100)
	await get_tree().physics_frame
	var health := player.get_node("HealthComponent")
	var initial_hp: float = health.current_hp
	var damage_seen: Array = []
	var listener := func(_info: RefCounted, target: Node, amount: float):
		if target == player:
			damage_seen.append(amount)
	EventBus.hit_confirmed.connect(listener)
	var impact_frame := -1
	var retired_parent := false
	for frame: int in range(1, 190):
		if frame == 31 and not with_wall:
			var native: Node2D = effects.native_payload_nodes()[0]
			var body: CollisionShape2D = native.get_node("CollisionShape2D")
			var before: Dictionary = effects.snapshot()
			body.disabled = true
			suite.assert_true(not suite.expect_rejected_player_frame(player, {}, "Hostile frame preparation rejected runtime frame"), "disabled native projectile shape cannot commit an authoritative collision frame")
			suite.assert_equal(effects.snapshot(), before, "native shape rejection restores clock and pending death work")
			body.disabled = false
		if frame in [30, 32] or (frame == 43 and not with_wall):
			var before: Dictionary = effects.snapshot()
			var before_nodes: int = effects.native_payload_nodes().size()
			bridge.reject_at = frame
			if frame == 32:
				bridge.time_source_at = frame
			suite.assert_true(not suite.expect_rejected_player_frame(player), "late native Moth frame rejection compensates projections and time sources")
			suite.assert_equal(effects.snapshot(), before, "frame rollback restores the complete native payload domain")
			suite.assert_equal(effects.native_payload_nodes().size(), before_nodes, "failed reservation restores the exact active native body count")
			for node: Node2D in effects.native_payload_nodes():
				suite.assert_equal(node.get_node("RiftReceiver").collision_layer, 1, "native retirement rollback restores Rift reception")
		var accepted: bool = player.advance_action_frame()
		suite.assert_true(accepted, "actual Player accepts native Moth payload frame %d" % frame)
		if not accepted:
			break
		var payload: Dictionary = effects.payload_snapshot()
		if frame < 30:
			suite.assert_true(payload.projectiles.is_empty() and health.current_hp == initial_hp, "full thirty-frame warning emits no projectile or damage")
		if frame == 30:
			suite.assert_equal(payload.projectiles.size(), 1, "first active scheduled hit creates one real projectile body")
			suite.assert_true(effects.native_payload_nodes()[0].get_node("Sprite2D").texture != null, "native damaging projectile has its original visible raster")
			var before_reconfigure: Dictionary = effects.snapshot()
			var before_nodes: Array[Node2D] = effects.native_payload_nodes()
			suite.assert_true(not effects.configure("run-rebound", 300), "live native payloads reject reconfiguration")
			suite.assert_equal(effects.snapshot(), before_reconfigure, "failed native reconfiguration preserves the effects run clock and payload authority")
			suite.assert_equal(effects.native_payload_nodes(), before_nodes, "failed native reconfiguration preserves exact native projection ownership")
			if not with_wall:
				for detached: Node2D in [native_root, player, effects.native_payload_nodes()[0]]:
					var parent := detached.get_parent()
					var effect_context := {"run_id": "run-p15", "runtime_frame": 31, "threat_registry": threats, "actors": {}, "targets": {"player": player}}
					parent.remove_child(detached)
					var rejected: Dictionary = effects.prepare_effects([], effect_context)
					suite.assert_true(not rejected.ok, "detached native payload root or target cannot prepare a damaging frame")
					if rejected.ok:
						effects.rollback(rejected.ticket)
					parent.add_child(detached)
					suite.assert_equal(effects.snapshot(), before_reconfigure, "detached native geometry rejection preserves the payload domain")
					var prepared_geometry: Dictionary = effects.prepare_effects([], effect_context)
					suite.assert_true(prepared_geometry.ok, "reattached native geometry prepares the exact next frame")
					if prepared_geometry.ok:
						parent.remove_child(detached)
						suite.assert_true(not effects.can_commit(prepared_geometry.ticket), "native geometry detached after preparation rejects commit")
						parent.add_child(detached)
						suite.assert_true(effects.rollback(prepared_geometry.ticket), "reattached geometry compensates its uncommitted native ticket")
				_test_projection_lifetime(payload.projectiles[0], effects)
				await _capture_native("moth-projectile-640x360")
		if frame == 31:
			retired_parent = actor.launch_runtime_snapshot().runtime.terminal
			suite.assert_true(retired_parent and payload.projectiles.size() == 1 and payload.zones.size() == 1, "final death releases actor while independent projectile and warned death pool remain authoritative")
		if impact_frame < 0:
			for zone: Dictionary in payload.zones:
				if zone.definition.kind == "impact_pool":
					impact_frame = frame
					if not with_wall:
						player.global_position = Vector2(zone.definition.position.x, zone.definition.position.y)
		if impact_frame > 0 and frame > impact_frame + 120:
			break
		await get_tree().physics_frame
	if with_wall:
		suite.assert_equal(damage_seen, [], "real wall contact produces no Player hit through the wall")
		suite.assert_equal(health.current_hp, initial_hp, "blocked acid projectile cannot damage the Player behind the wall")
	else:
		suite.assert_equal(damage_seen, [8.0, 3.0, 3.0], "actual Launch Character receives one projectile contact and exactly two finite acid ticks")
		suite.assert_equal(health.current_hp, initial_hp - 14.0, "native Character contracts settle the authored Moth damage")
	suite.assert_true(retired_parent and impact_frame > 30, "native impact happens during flight after parent terminal death")
	suite.assert_equal(effects.payload_snapshot().projectiles, [], "projectile native owner releases completed flight")
	suite.assert_equal(effects.payload_snapshot().zones, [], "all native acid and warning pools retire at their finite clocks")
	EventBus.hit_confirmed.disconnect(listener)
	player.configure_hostile_frame_participant(null)
	player.queue_free()
	if is_instance_valid(actor):
		actor.queue_free()
	native_root.queue_free()
	room.queue_free()
	if wall != null:
		wall.queue_free()
	await get_tree().process_frame


func _test_projection_lifetime(record: Dictionary, owner: RefCounted) -> void:
	var probe := PayloadProjection.new()
	var has_contract := probe.has_method("native_projection_is_ready")
	suite.assert_true(has_contract, "native payload child lifetime has a guarded readiness contract")
	probe.free()
	if not has_contract:
		return
	for child: String in ["CollisionShape2D", "Sprite2D", "RiftReceiver", "RiftReceiver/CollisionShape2D"]:
		var node := PayloadProjection.new()
		suite.assert_true(node.configure_payload(owner, record.id, record.definition), "lifetime probe configures original native payload children")
		add_child(node)
		suite.assert_true(bool(node.call("project_record", record, 30)), "complete payload children project an accepted record")
		node.get_node(child).free()
		suite.assert_true(not bool(node.call("native_projection_is_ready")) and not node.native_definition_matches(record.definition), "freed payload child rejects without a script error")
		suite.assert_true(not bool(node.call("project_record", record, 30)), "damaged native payload projection fails explicitly")
		node.free()


func _test_native_death_warning() -> void:
	var player := PlayerScene.instantiate() as Node2D
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.set_meta(&"stable_target_key", "player")
	player.global_position = Vector2(100, 100)
	var actor := ActorScene.instantiate() as Node2D
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = Vector2(100, 100)
	var parser := Enemy.new()
	parser.configure(Content.enemy("corrosive_moth"))
	var identity := {"run_id": "run-p15", "hostile_source_id": "hostile-moth-warned-death", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	actor.configure_launch_definition(parser.runtime_projection(), identity)
	var room := RoomScene.instantiate() as Node2D
	add_child(room)
	actor.configure_launch_room_motion(room, _template())
	var native_root := Node2D.new()
	add_child(native_root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(native_root)
	var bridge := RejectedFrameBridge.new()
	bridge.kill_actor = actor
	bridge.kill_at = 1
	bridge.reject_at = 1
	bridge.payload_effects = effects
	suite.assert_true(bridge.configure(player, Threats.new(), [actor], effects) and player.configure_hostile_frame_participant(bridge), "warned death pool binds an actual native terminal transaction")
	await get_tree().physics_frame
	var initial_actor: Dictionary = actor.launch_runtime_snapshot()
	suite.assert_true(not suite.expect_rejected_player_frame(player), "late rejection compensates lethal Health and death reservation together")
	suite.assert_equal(actor.launch_runtime_snapshot(), initial_actor, "rejected death cannot keep its reserved generation, terminal flag or lost Health")
	suite.assert_equal(effects.payload_snapshot().zones, [], "rejected death cannot leave a damaging native pool")
	var health := player.get_node("HealthComponent")
	var initial_hp: float = health.current_hp
	for frame: int in range(1, 35):
		if frame == 10:
			effects.native_payload_nodes()[0].apply_time_stop_source(&"stop-death-warning", 2.0 / 60.0)
		var accepted: bool = player.advance_action_frame()
		suite.assert_true(accepted, "native warned death and Stop accept frame %d" % frame)
		if not accepted:
			break
		if frame < 33:
			suite.assert_equal(health.current_hp, initial_hp, "death pool preserves its complete thirty-frame warning plus two stopped frames")
		else:
			suite.assert_equal(health.current_hp, initial_hp - 5.0, "native death pool applies exactly one authored five-damage pulse")
		if frame == 9:
			await _capture_native("moth-warned-death-640x360")
		await get_tree().physics_frame
	suite.assert_equal(effects.payload_snapshot().zones, [], "warned death releases its native pending work after the one pulse")
	player.configure_hostile_frame_participant(null)
	player.queue_free()
	if is_instance_valid(actor):
		actor.queue_free()
	native_root.queue_free()
	room.queue_free()
	await get_tree().process_frame


func _test_elite_lanes() -> void:
	var player := PlayerScene.instantiate() as Node2D
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.set_meta(&"stable_target_key", "player")
	player.global_position = Vector2(160, 100)
	var actor := ActorScene.instantiate() as Node2D
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = Vector2(100, 100)
	var parser := Enemy.new()
	parser.configure(Content.enemy("corrosive_moth"))
	var identity := {"run_id": "run-p15", "hostile_source_id": "hostile-moth-elite", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	actor.configure_launch_definition(parser.runtime_projection("elite"), identity)
	var room := RoomScene.instantiate() as Node2D
	add_child(room)
	actor.configure_launch_room_motion(room, _template())
	var native_root := Node2D.new()
	add_child(native_root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(native_root)
	var threats := Threats.new()
	var context := {"runtime_frame": 0, "source_position": {"x": 100.0, "y": 100.0}, "target_position": {"x": 160.0, "y": 100.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player"}
	var started: Dictionary = actor.get("_launch_runtime").request_action("corrosive_moth.corrosive_barrage", context)
	for fact: Dictionary in started.threat_facts:
		threats.register_fact(Coordinator.native_threat_fact(fact))
	var bridge := RejectedFrameBridge.new()
	bridge.kill_actor = actor
	bridge.kill_at = 48
	bridge.payload_effects = effects
	bridge.configure(player, threats, [actor], effects)
	player.configure_hostile_frame_participant(bridge)
	await get_tree().physics_frame
	var rift: Area2D
	for frame: int in range(1, 50):
		if frame == 34:
			player.global_position.y = 220.0
		if frame == 36:
			rift = RiftScene.instantiate()
			rift.radius = 24.0
			rift.slow_multiplier = 0.5
			rift.configure_world_payload_identity(&"p15-native-moth-rift")
			add_child(rift)
			rift.global_position = effects.native_payload_nodes()[0].global_position
		var accepted: bool = player.advance_action_frame()
		suite.assert_true(accepted, "native elite Moth lane schedule accepts frame %d" % frame)
		if not accepted:
			break
		var projectiles: Array = effects.payload_snapshot().projectiles
		if rift != null:
			rift.advance_frame(frame)
		if frame == 38:
			suite.assert_true(projectiles[0].control.sources.any(func(row: Dictionary) -> bool: return row.kind == "rift" and row.magnitude == 0.5), "actual native Rift Area overlap reaches the independent projectile control authority")
		if frame in [35, 41, 47]:
			suite.assert_equal(projectiles.size(), 1 + (frame - 35) / 6, "each elite scheduled lane independently reserves its actual flight body")
			var latest: Dictionary = projectiles.back().definition
			suite.assert_equal(latest.generation, 7 + (frame - 35) / 6, "elite projectile uses its separately committed lane generation")
			suite.assert_equal(latest.damage, 7.5, "native elite flight preserves the actual elite action damage projection")
			var angle := Vector2(latest.direction.x, latest.direction.y).angle()
			suite.assert_close(rad_to_deg(angle), float(-15 + ((frame - 35) / 6) * 15), "moving Player cannot retarget the elite frozen warning lanes", 0.001)
			if frame == 47:
				await _capture_native("moth-elite-three-lanes-640x360")
		await get_tree().physics_frame
	suite.assert_equal(effects.payload_snapshot().projectiles.size(), 3, "all three independently frozen elite lanes remain after final native parent death")
	player.configure_hostile_frame_participant(null)
	player.queue_free()
	if is_instance_valid(actor):
		actor.queue_free()
	native_root.queue_free()
	room.queue_free()
	if rift != null:
		rift.queue_free()
	await get_tree().process_frame


func _capture_native(name: String) -> void:
	var directory := OS.get_environment("PLANEWALKER_P15_VISUAL_DIR")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var rendered: Image = get_viewport().get_texture().get_image()
	suite.assert_true(rendered != null and not rendered.is_empty(), "actual native Moth raster scene renders pixels")
	if rendered == null or rendered.is_empty():
		return
	var colors: Dictionary = {}
	for y: int in range(0, rendered.get_height(), 4):
		for x: int in range(0, rendered.get_width(), 4):
			colors[rendered.get_pixel(x, y).to_rgba32()] = true
	suite.assert_true(colors.size() > 8, "actual native Moth raster screenshot is nonblank")
	suite.assert_equal(rendered.save_png(directory.path_join(name + ".png")), OK, "native Moth screenshot saves")
