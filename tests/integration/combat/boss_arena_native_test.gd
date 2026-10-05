extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const BossScene := preload("res://data/content_packs/base/assets/bosses/launch/boss_ruin_king.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const GunScene := preload("res://scenes/combat/gun_projectile.tscn")
const ArrowScene := preload("res://scenes/combat/player_arrow.tscn")
const Staff := preload("res://scripts/combat/staff_projectile.gd")
const Gauntlets := preload("res://scripts/combat/gauntlets_hit_execution.gd")
const Hitbox := preload("res://scripts/combat/hitbox.gd")
const RoomScene := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var actor := _actor()
	actor.global_position = Vector2(320.0, 180.0)
	var arena := actor.get_node_or_null("ArenaConstructs")
	suite.assert_true(arena != null and arena.get_child_count() == 4, "actual Ruin Boss owns four physical destructible cover pillars")
	if arena != null:
		for cover: Node in arena.get_children():
			suite.assert_true(cover is StaticBody2D and cover.get_node_or_null("Hurtbox") is Area2D and cover.has_method("native_construct_snapshot"), "each declared cover has a native obstacle, weapon collider and authoritative HP projection")
			suite.assert_true(not cover.is_in_group("enemies") and not cover.is_in_group("bosses") and cover.native_construct_snapshot().current_hp == 80.0, "cover owns authored HP without another counted enemy or Boss receipt")
			var point: Vector2 = cover.global_position
			suite.assert_true(absf(point.x - 320.0) - 14.0 >= 24.0 and point.x - 14.0 >= 48.0 and point.y - 14.0 >= 48.0 and 640.0 - point.x - 14.0 >= 48.0 and 360.0 - point.y - 14.0 >= 48.0, "canonical cover placement preserves the48px central corridor and open perimeter")
		await _capture_native(actor, "intact")
		await _test_damage_transaction(actor)
	actor.queue_free()
	await get_tree().process_frame
	await _test_projection_tampering()
	await _test_weapons()
	await _test_charge_collision()
	await _test_beam_cover()
	await _test_aftershock()
	await _test_aftershock("phase")
	await _test_aftershock("death")
	await _test_aftershock("impact", 1.25)
	await _test_aftershock("impact", 0.8)
	await _test_enrage_cover_retirement()
	suite.finish(get_tree())


func _actor() -> Node2D:
	var actor := BossScene.instantiate() as Node2D
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var parser := Definition.new()
	parser.configure(Content.boss("ruin_king"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-p15", "hostile_source_id": "hostile-ruin-arena", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}).ok, "native arena fixture binds the authored Ruin Boss")
	return actor


func _player() -> Node2D:
	var player := PlayerScene.instantiate() as Node2D
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(220.0, 120.0)
	return player


func _damage(player: Node2D, token: int, amount: float = 16.0) -> RefCounted:
	return Damage.from_plan({"run_id": "run-p15", "target_id": "pending_cover", "hostile_source_id": "player:sword", "attack_generation": token, "action_token": token, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})


func _test_damage_transaction(actor: Node2D) -> void:
	var player := _player()
	actor.global_position = Vector2(100.0, 120.0)
	var cover := actor.get_node("ArenaConstructs/Cover0")
	var cover_hurtbox := cover.get_node("Hurtbox")
	var effects := Effects.new()
	effects.configure("run-p15")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "four native cover targets share one Boss frame participant")
	var context := {"runtime_frame": 1, "source_position": {"x": 100.0, "y": 120.0}, "target_position": {"x": 220.0, "y": 120.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}
	cover.get_node("CollisionShape2D").shape.radius += 1.0
	suite.assert_true(not actor.prepare_launch_frame(1, context).ok and cover_hurtbox.receive_hit(_damage(player, 1)) == 0.0, "tampered actual cover geometry rejects frame preparation and weapon damage")
	cover.get_node("CollisionShape2D").shape.radius -= 1.0
	var before: Dictionary = actor.launch_runtime_snapshot()
	var deaths: Array = []
	actor.hostile_final_death.connect(func(source: StringName, receipt: String): deaths.append([source, receipt]))
	var ticket: Dictionary = bridge.begin_frame(1)
	for token: int in range(1, 6):
		suite.assert_equal(cover_hurtbox.receive_hit(_damage(player, token)), 16.0, "distinct native weapon damage reduces authoritative cover HP")
		suite.assert_equal(cover_hurtbox.receive_hit(_damage(player, token)), 0.0, "native cover damage rejects duplicate identities")
	suite.assert_true(cover.native_construct_snapshot().broken and cover.collision_layer == 0 and cover_hurtbox.collision_layer == 0, "candidate broken cover retires both actual collision layers")
	suite.assert_equal(actor.health.current_hp, 800.0, "independent cover HP never becomes unintended Boss body damage")
	suite.assert_true(bridge.prepare_frame(ticket) and bridge.rollback_frame(ticket), "native cover destruction compensates a rejected Player sibling frame")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "cover rejection restores complete domain and Boss Health")
	suite.assert_true(cover.collision_layer == 1 and cover_hurtbox.collision_layer == 4 and cover.native_construct_snapshot().current_hp == 80.0, "cover rejection restores actual obstacle and weapon colliders")
	ticket = bridge.begin_frame(1)
	for token: int in range(1, 6):
		cover_hurtbox.receive_hit(_damage(player, token))
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "same five cover damage identities accept after complete rollback")
	await _capture_native(actor, "broken")
	suite.assert_equal(deaths, [], "accepted cover destruction publishes no counted enemy or Boss death")
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var twin := _actor()
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh actual Boss restores complete current arena cold state")
	suite.assert_equal(twin.native_arena_snapshot(), actor.native_arena_snapshot(), "cold restore preserves authoritative cover HP and all claims")
	suite.assert_equal(twin.get_node("ArenaConstructs/Cover0").collision_layer, 0, "cold restore never resurrects a broken cover")
	suite.assert_equal(twin.get_node("ArenaConstructs/Cover0").get_meta("stable_target_id"), cover.get_meta("stable_target_id"), "cold native construct retains a deterministic weapon target ID without Node-instance identity")
	var forged := cold.duplicate(true)
	forged.actor.runtime.arena_state.covers[0].current_hp = 1.0
	suite.assert_true(not twin.can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "re-signed cover HP inconsistent with accepted damage ledger rejects")
	var legacy := cold.duplicate(true)
	legacy.actor.runtime.erase("arena_state")
	legacy.actor.runtime.schema_version = 1
	suite.assert_true(twin.restore_native_cold_snapshot(legacy, func(_binding: Dictionary): return null), "exact historical Ruin runtime version1 receives the declared initial arena migration")
	suite.assert_equal(twin.get_node("ArenaConstructs/Cover0").native_construct_snapshot().current_hp, 80.0, "historical runtime had no arena state and initializes its declared cover recipe")
	legacy.actor.runtime.arena_state = cold.actor.runtime.arena_state
	suite.assert_true(not twin.can_restore_native_cold_snapshot(legacy, func(_binding: Dictionary): return null), "historical version1 carrying undeclared arena data cannot be normalized")
	twin.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_projection_tampering() -> void:
	for mutation: String in ["cover_visibility", "sprite_visibility", "debris_frame", "transparent", "scale", "atlas", "offset"]:
		var actor := _actor()
		var player := _player()
		var cover: Node2D = actor.get_node("ArenaConstructs/Cover0")
		var artwork: Sprite2D = cover.get_child(2)
		match mutation:
			"cover_visibility": cover.visible = false
			"sprite_visibility": artwork.visible = false
			"debris_frame": artwork.frame = 2
			"transparent": artwork.modulate = Color(1.0, 1.0, 1.0, 0.0)
			"scale": artwork.scale = Vector2(2.0, 1.0)
			"atlas": artwork.texture = preload("res://assets/production/constructs/time_watch.png")
			"offset": artwork.position += Vector2.ONE
		var context := {"runtime_frame": 1, "source_position": {"x": 0.0, "y": 0.0}, "target_position": {"x": 220.0, "y": 120.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}
		suite.assert_true(not actor.prepare_launch_frame(1, context).ok and cover.get_node("Hurtbox").receive_hit(_damage(player, 1)) == 0.0, "actual cover artwork tampering rejects both frame and collision: " + mutation)
		actor.queue_free()
		player.queue_free()
		await get_tree().process_frame


func _capture_native(actor: Node2D, pose: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		var background := pixels.get_pixel(0, 0).to_rgba32()
		for cover: Node2D in actor.get_node("ArenaConstructs").get_children():
			var colors: Dictionary = {}
			var foreground := 0
			for y: int in range(int(cover.global_position.y) - 32, int(cover.global_position.y) + 18):
				for x: int in range(int(cover.global_position.x) - 22, int(cover.global_position.x) + 22):
					var point := Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))
					var color := pixels.get_pixelv(point).to_rgba32()
					colors[color] = true
					foreground += int(color != background)
			suite.assert_true(colors.size() >= 4 and foreground > (30 if cover.native_construct_snapshot().broken else 250), "native cover renders substantial authored raster pixels at " + str(resolution))
		var output := "res://build/visual-evidence/p15b-native-arena/ruin-cover-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native Ruin cover screenshot is retained")


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true


func _test_weapons() -> void:
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		var actor := _actor()
		var player := _player()
		var payload: Node2D
		var payload_results: Array = []
		var execution := {"action_token": 14, "descriptor_id": "cover_probe", "outcome_index": 0, "deterministic_seed": 42, "damage": 16.0, "base_attack": 16.0, "speed": 240.0, "max_range_pixels": 240.0}
		match weapon:
			"sword":
				payload = Hitbox.new()
				player.get_node("SwordWeapon").add_child(payload)
				payload.activate(_damage(player, 14))
			"gun":
				payload = GunScene.instantiate()
				payload.owner_entity = player
				payload.source = player
				execution.merge({"source_action_id": "normal_fire", "pierce": 0, "pierce_mode": "limited", "damage_type": Damage.DamageType.PHYSICAL, "time_damage_ratio": 0.0, "trail": {}, "time_interactions": [], "boss_conversion": {}, "resource_reward": {}, "action_claims": {}, "tags": ["weapon:gun"]})
				suite.assert_true(payload.configure_execution(execution), "real Gun cover payload binds")
				add_child(payload)
			"bow":
				payload = ArrowScene.instantiate()
				payload.owner_entity = player
				payload.source = player
				execution.merge({"source_action_id": "quick_shot", "pierce": 0, "pierce_mode": "limited", "full_charge": false, "time_energy_restore": 0.0, "energy_reward_once_per_action": true, "time_damage_ratio": 0.0, "trail": {}, "first_hit_control": {}, "time_interactions": [], "boss_conversion": {}, "tags": ["weapon:bow"]})
				suite.assert_true(payload.configure_execution(execution), "real Bow cover arrow binds")
				add_child(payload)
			"staff":
				payload = Staff.new()
				payload.owner_entity = player
				payload.source = player
				execution.merge({"source_action_id": "arcane_bolt", "generation": 5, "element_id": "fire", "target_deduplication": "per_action_target", "effect_descriptor": {}, "combination": {}, "chain": {}})
				suite.assert_true(payload.configure_execution(execution), "real Staff cover projectile binds")
				add_child(payload)
			"gauntlets":
				payload = Gauntlets.new()
				payload.owner_entity = player
				payload.source = player
				suite.assert_true(payload.configure_execution({"action_token": 15, "generation": 5, "source_action_id": "punch_1", "descriptor_id": "cover_punch", "outcome_index": 0, "deterministic_seed": 42, "kind": "hitbox", "parameters": {"damage_multiplier": 1.0, "combo_eligible": false, "energy_eligible": false, "stop_extension_eligible": false}, "base_attack": 16.0, "direction": Vector2.RIGHT, "target_deduplication": "per_action_target", "progress_claims": {}, "progress_claim_order": [], "damage_claims": {}, "damage_claim_order": []}), "real Gauntlets cover hit binds")
				payload.owner_entity = player
				payload.source = player
				add_child(payload)
		payload.process_mode = Node.PROCESS_MODE_DISABLED
		var cover := actor.get_node("ArenaConstructs/Cover0")
		payload.global_position = cover.global_position - Vector2(16.0, 0.0)
		if weapon == "gauntlets":
			payload.payload_result.connect(func(_token: int, _generation: int, result: Dictionary) -> void: payload_results.append(result))
			suite.assert_true(payload._target_inside_geometry(cover), "actual Gauntlets fixture places the cover inside its authored hit geometry")
		payload.call("_on_area_entered", cover.get_node("Hurtbox"))
		if weapon == "gauntlets":
			await get_tree().process_frame
		var hp: float = cover.native_construct_snapshot().current_hp
		suite.assert_true(hp < 80.0, "actual " + weapon + " collision reduces domain-owned cover HP: " + str(payload_results))
		payload.call("_on_area_entered", cover.get_node("Hurtbox"))
		if weapon == "gauntlets":
			await get_tree().process_frame
		suite.assert_equal(cover.native_construct_snapshot().current_hp, hp, "actual " + weapon + " collision deduplicates this construct target")
		payload.queue_free()
		player.queue_free()
		actor.queue_free()
		await get_tree().process_frame


func _test_charge_collision() -> void:
	var actor := _actor()
	actor.global_position = Vector2(100.0, 120.0)
	var player := _player()
	var registry := Registry.new()
	var effects := Effects.new()
	effects.configure("run-p15")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "native charge binds actual arena collision participant")
	var runtime: RefCounted = actor.get("_launch_runtime")
	var started: Dictionary = runtime.request_action("guardian_charge", {"runtime_frame": 0, "source_position": {"x": 100.0, "y": 120.0}, "target_position": {"x": 220.0, "y": 120.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"})
	suite.assert_true(started.ok, "native charge commits its complete authored warning")
	for fact: Dictionary in started.threat_facts:
		registry.register_fact(Actions.native_threat_fact(fact))
	var impact_frame := -1
	for frame: int in range(1, 110):
		await get_tree().physics_frame
		var before: Dictionary = actor.launch_runtime_snapshot()
		var ticket: Dictionary = bridge.begin_frame(frame)
		if not bridge.prepare_frame(ticket):
			suite.assert_true(false, "native charge prepares frame %d" % frame)
			break
		if actor.native_arena_snapshot().covers[0].broken:
			impact_frame = frame
			suite.assert_true(runtime.is_exposed() and runtime.snapshot().mechanism_state.exposure_through_frame == frame + 59 and actor.global_position.x < 160.0, "real swept-body collision breaks only the declared cover and grants60 complete exposed frames")
			suite.assert_true(bridge.rollback_frame(ticket), "actual charge-cover contact compensates a rejected Player sibling")
			suite.assert_equal(actor.launch_runtime_snapshot(), before, "charge-cover rejection restores position, cover HP, attack and exposure")
			ticket = bridge.begin_frame(frame)
			suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "same native charge-cover collision retries once after rollback")
			break
		if not _publish(bridge, ticket):
			suite.assert_true(false, "native charge publishes frame %d" % frame)
			break
	suite.assert_true(impact_frame >= 45 and impact_frame < 105, "actual charge collides with a physical pillar during its active interval")
	suite.assert_equal(player.health.current_hp, player.health.max_hp, "pillar impact never converts into an unintended Player contact hit")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_beam_cover() -> void:
	for intact: bool in [true, false]:
		var actor := _actor()
		actor.global_position = Vector2(100.0, 120.0)
		var player := _player()
		var registry := Registry.new()
		var effects := Effects.new()
		effects.configure("run-p15")
		var bridge := Bridge.new()
		suite.assert_true(bridge.configure(player, registry, [actor], effects), "actual beam binds physical arena and Player damage authority")
		var runtime: RefCounted = actor.get("_launch_runtime")
		var started: Dictionary = runtime.request_action("guardian_rift_beam", {"runtime_frame": 0, "source_position": {"x": 100.0, "y": 120.0}, "target_position": {"x": 220.0, "y": 120.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"})
		suite.assert_true(started.ok, "native beam commits all three warned hit offsets")
		for fact: Dictionary in started.threat_facts:
			registry.register_fact(Actions.native_threat_fact(fact))
		for frame: int in range(1, 76):
			if frame == 55 and not intact:
				suite.assert_equal(actor.get_node("ArenaConstructs/Cover0/Hurtbox").receive_hit(_damage(player, 71, 80.0)), 80.0, "real Player removes beam cover before its first active offset")
			var health_before: Dictionary = player.health.runtime_state_snapshot()
			var health_checkpoint: Dictionary = player.health.transaction_snapshot()
			var state_before: Dictionary = actor.launch_runtime_snapshot()
			var effects_before: Dictionary = effects.snapshot()
			var ticket: Dictionary = bridge.begin_frame(frame)
			if not bridge.prepare_frame(ticket):
				suite.assert_true(false, "native beam prepares accepted frame%d" % frame)
				bridge.rollback_frame(ticket)
				break
			if frame == 55:
				suite.assert_true(bridge.rollback_frame(ticket), "first cover adjudication compensates a refused Player sibling")
				suite.assert_true(player.health.restore_transaction_snapshot(health_checkpoint), "outer Player owner restores its candidate Health after beam rejection")
				suite.assert_equal(player.health.runtime_state_snapshot(), health_before, "beam refusal restores actual Player HP and irreversible claims")
				suite.assert_equal(actor.launch_runtime_snapshot(), state_before, "beam refusal restores full native Boss state")
				suite.assert_equal(effects.snapshot(), effects_before, "beam refusal restores the hostile damage ledger")
				ticket = bridge.begin_frame(frame)
				suite.assert_true(bridge.prepare_frame(ticket), "same sealed beam offset retries after rejection")
			suite.assert_true(_publish(bridge, ticket), "native beam publishes frame%d" % frame)
			player.health.discard_transaction_snapshot(health_checkpoint)
			if frame in [55, 65, 75] and intact:
				suite.assert_equal(player.health.current_hp, player.health.max_hp, "real intact pillar blocks every committed beam hit")
		if not intact:
			suite.assert_true(player.health.current_hp < player.health.max_hp, "real broken pillar exposes Player to the same native beam")
		actor.queue_free()
		player.queue_free()
		await get_tree().process_frame


func _test_aftershock(ending: String = "impact", attack_multiplier: float = 1.0) -> void:
	var actor := _actor()
	actor.global_position = Vector2(100.0, 120.0)
	if attack_multiplier != 1.0:
		suite.assert_true(actor.get("_launch_runtime").add_control_source("aftershock_attack_modifier", "attack_buff" if attack_multiplier > 1.0 else "attack_debuff", 300, attack_multiplier), "native aftershock accepts its actual bounded attack modifier")
	var room := RoomScene.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	for template: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if template.id == "room_combat_open_field":
			suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "native aftershock binds its actual room bounds")
	var player := _player()
	var native_root := Node2D.new()
	add_child(native_root)
	var registry := Registry.new()
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-p15") and effects.configure_native_payloads(native_root), "native aftershock uses actual manifested payload projection")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "actual slam and secondary explosion share one accepted frame owner")
	var started: Dictionary = actor.get("_launch_runtime").request_action("guardian_fist_slam", {"runtime_frame": 0, "source_position": {"x": 100.0, "y": 120.0}, "target_position": {"x": 220.0, "y": 120.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"})
	suite.assert_true(started.ok, "native slam locks its original authored target")
	for fact: Dictionary in started.threat_facts:
		registry.register_fact(Actions.native_threat_fact(fact))
	for frame: int in range(1, 116):
		var before: Dictionary = effects.snapshot()
		var threats_before: Array = registry.snapshot()
		var health_checkpoint: Dictionary = player.health.transaction_snapshot()
		var health_before: Dictionary = player.health.runtime_state_snapshot()
		var ticket: Dictionary = bridge.begin_frame(frame)
		if not bridge.prepare_frame(ticket):
			suite.assert_true(false, "native aftershock prepares frame%d" % frame)
			bridge.rollback_frame(ticket)
			break
		if frame in [55, 75, 115]:
			suite.assert_true(bridge.rollback_frame(ticket) and player.health.restore_transaction_snapshot(health_checkpoint), "aftershock spawn, warning and hit each compensate a refused whole frame")
			suite.assert_equal(effects.snapshot(), before, "rejected aftershock transition preserves complete payload and damage ledgers")
			suite.assert_equal(registry.snapshot(), threats_before, "rejected aftershock transition restores exact native telegraph facts")
			suite.assert_equal(player.health.runtime_state_snapshot(), health_before, "rejected aftershock damage restores actual Player Health")
			ticket = bridge.begin_frame(frame)
			suite.assert_true(bridge.prepare_frame(ticket), "same aftershock transition retries once after full compensation")
		suite.assert_true(_publish(bridge, ticket), "native aftershock publishes frame%d" % frame)
		player.health.discard_transaction_snapshot(health_checkpoint)
		if frame == 55:
			suite.assert_close(player.health.current_hp, player.health.max_hp - 25.0 * attack_multiplier, "original slam uses its actual authenticated attack modifier")
			suite.assert_true(effects.payload_snapshot().zones.size() == 1 and effects.payload_snapshot().zones[0].phase == "DORMANT", "slam reserves one independently timed dormant aftershock")
			if ending != "impact":
				suite.assert_true(actor.get_node("Hurtbox").receive_hit(_damage(player, 79, 800.0 if ending == "death" else 400.0)) > 0.0, "actual Player damage commits the Boss " + ending + " before its secondary warning")
		if frame == 56 and ending != "impact":
			suite.assert_true(effects.payload_snapshot().zones.is_empty(), "actual Boss " + ending + " retires its pending aftershock before activation")
		if frame == 75 and ending == "impact":
			suite.assert_true(effects.payload_snapshot().zones.size() == 1 and effects.payload_snapshot().zones[0].phase == "WARNING" and effects.native_payload_nodes().size() == 1, "aftershock displays its own40 complete native warning frames")
			await _capture_aftershock(effects)
		if frame in [74, 114]:
			suite.assert_close(player.health.current_hp, player.health.max_hp - 25.0 * attack_multiplier, "secondary explosion cannot damage Player before its full60-frame delay")
		if frame == 115:
			suite.assert_close(player.health.current_hp, player.health.max_hp - (37.0 if ending == "impact" else 25.0) * attack_multiplier, "delayed native explosion respects actual attack modifiers and owner retirement")
			suite.assert_true(effects.payload_snapshot().zones.is_empty(), "one-shot aftershock retires its actual native hazard after accepted impact")
	actor.queue_free()
	player.queue_free()
	room.queue_free()
	native_root.queue_free()
	await get_tree().process_frame


func _capture_aftershock(effects: RefCounted) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	var payload: Node2D = effects.native_payload_nodes()[0]
	suite.assert_equal(payload.get_node("Sprite2D").texture.resource_path, "res://assets/production/hostile_effects/physical_pool.png", "native stone aftershock uses its original physical raster")
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		var colors: Dictionary = {}
		for y: int in range(88, 152):
			for x: int in range(188, 252):
				colors[pixels.get_pixelv(Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))).to_rgba32()] = true
		suite.assert_true(colors.size() >= 4, "native delayed aftershock renders nonblank original pixels at " + str(resolution))
		var output := "res://build/visual-evidence/p15b-native-arena/ruin-aftershock-warning-%dx%d.png" % [resolution.x, resolution.y]
		suite.assert_equal(pixels.save_png(output), OK, "native delayed aftershock screenshot is retained")


func _test_enrage_cover_retirement() -> void:
	var actor := _actor()
	actor.global_position = Vector2(100.0, 120.0)
	var player := _player()
	player.global_position = Vector2(220.0, 120.0)
	var cover0 := actor.get_node("ArenaConstructs/Cover0")
	var cover1 := actor.get_node("ArenaConstructs/Cover1")
	suite.assert_equal(cover0.get_node("Hurtbox").receive_hit(_damage(player, 301, 80.0)), 80.0, "enrage fixture retains one already broken physical cover")
	suite.assert_equal(cover1.get_node("Hurtbox").receive_hit(_damage(player, 302, 16.0)), 16.0, "enrage fixture retains existing partial cover damage")
	var runtime: RefCounted = actor.get("_launch_runtime")
	# Only threshold warmup is a pure fixture; the warned impact uses real native transactions.
	for frame: int in range(1, 18001):
		var context := {"runtime_frame": frame, "source_position": {"x": 100.0, "y": 120.0}, "target_position": {"x": 220.0, "y": 120.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}
		if not runtime.advance_frame(frame, context, false).ok:
			suite.assert_true(false, "enrage fixture advances every authored accepted threshold frame")
			break
	player.set("_runtime_frame", 18000)
	actor._refresh_control_visual()
	var registry := Registry.new()
	var effects := Effects.new()
	effects.configure("run-p15", 18000)
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "enrage cover fixture binds actual native state after the accepted18000-frame threshold")
	var started: Dictionary = runtime.request_action("guardian_enrage_collapse", {"runtime_frame": 18000, "source_position": {"x": 100.0, "y": 120.0}, "target_position": {"x": 220.0, "y": 120.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"})
	suite.assert_true(started.ok, "actual native enrage commits its full75-frame warning: " + str(started))
	if not started.ok:
		actor.queue_free()
		player.queue_free()
		await get_tree().process_frame
		return
	for fact: Dictionary in started.threat_facts:
		registry.register_fact(Actions.native_threat_fact(fact))
	player.global_position = Vector2(550.0, 180.0)
	var deaths: Array = []
	actor.hostile_final_death.connect(func(source: StringName, receipt: String): deaths.append([source, receipt]))
	for frame: int in range(18001, 18076):
		var before: Dictionary = actor.launch_runtime_snapshot()
		var ticket: Dictionary = bridge.begin_frame(frame)
		if not bridge.prepare_frame(ticket):
			suite.assert_true(false, "actual enrage prepares native frame%d" % frame)
			break
		if frame < 18075:
			suite.assert_true(cover1.collision_layer == 1 and cover1.native_construct_snapshot().current_hp == 64.0, "enrage never removes physical cover during its full warning")
		else:
			for cover: Node in actor.get_node("ArenaConstructs").get_children():
				suite.assert_true(cover.native_construct_snapshot().broken and cover.collision_layer == 0 and cover.get_node("Hurtbox").collision_layer == 0, "first actual enrage impact retires every surviving cover and both native collision layers")
			suite.assert_equal(actor.native_arena_snapshot().damage_claims.size(), 5, "enrage spends only the remaining HP of three live covers without a duplicate claim for old debris")
			suite.assert_true(bridge.rollback_frame(ticket), "enrage cover destruction compensates a refused whole native frame")
			suite.assert_equal(actor.launch_runtime_snapshot(), before, "enrage rejection restores exact partial HP, broken covers and damage provenance")
			suite.assert_true(cover1.collision_layer == 1 and cover1.native_construct_snapshot().current_hp == 64.0 and cover0.collision_layer == 0, "enrage rollback reconstructs actual original obstacle layers")
			ticket = bridge.begin_frame(frame)
			suite.assert_true(bridge.prepare_frame(ticket), "same native enrage impact retries after full compensation")
		suite.assert_true(_publish(bridge, ticket), "actual enrage cover frame publishes")
	suite.assert_equal(actor.health.current_hp, 800.0, "enrage cover retirement never damages its owner body")
	suite.assert_equal(deaths, [], "enrage cover destruction creates no extra counted death or reward")
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var twin := _actor()
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh actual native Boss restores the current enrage cover checkpoint")
	suite.assert_equal(twin.native_arena_snapshot(), actor.native_arena_snapshot(), "enrage cold reconstruction preserves exact cover destruction and accepted claims")
	for cover: Node in twin.get_node("ArenaConstructs").get_children():
		suite.assert_equal(cover.collision_layer, 0, "cold enrage cover checkpoint never resurrects a physical pillar")
	await _capture_native(twin, "enrage")
	twin.queue_free()
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame
