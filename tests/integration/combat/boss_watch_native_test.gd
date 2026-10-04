extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const BossScene := preload("res://data/content_packs/base/assets/bosses/launch/boss_time_sovereign.tscn")
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
var suite: RefCounted


class ImpostorPlayer extends Node2D:
	func current_run_id() -> StringName:
		return &"run-p15"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _test_native_watch()
	await _test_actual_weapon_payloads()
	await _test_buffered_watch_lethal()
	suite.finish(get_tree())


func _test_native_watch() -> void:
	var actor := BossScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = Vector2(100.0, 100.0)
	var parser := Definition.new()
	parser.configure(Content.boss("time_sovereign"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-p15", "hostile_source_id": "hostile-watch", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}).ok, "actual Time Sovereign binds canonical watch owner")
	var watch := actor.get_node_or_null("WatchHurtbox") as Area2D
	suite.assert_true(watch != null and watch.has_method("receive_hit"), "native watch has an actual weapon-targetable child proxy")
	if watch == null:
		actor.queue_free()
		await get_tree().process_frame
		return
	var health := actor.get_node("HealthComponent")
	health.defense = 0.0
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(140.0, 100.0)
	var registry := Registry.new()
	var effects := Effects.new()
	effects.configure("run-p15")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "native watch shares one Boss frame participant")
	var runtime: RefCounted = actor.get("_launch_runtime")
	var context := {"runtime_frame": 0, "source_position": {"x": 100.0, "y": 100.0}, "target_position": {"x": 140.0, "y": 100.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player"}
	var started: Dictionary = runtime.request_action("traitor_self_rewind", context)
	for fact: Dictionary in started.threat_facts:
		registry.register_fact(Actions.native_threat_fact(fact))
	actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
	var projection: Dictionary = actor.native_watch_snapshot()
	suite.assert_true(projection.hittable and projection.cast_generation == 7 and projection.current_hp == 80.0, "real watch projects the authored eighty damage interrupt threshold")
	suite.assert_true(watch.get_parent() == actor and actor.get_node("Hurtbox").collision_layer == 0 and watch.collision_layer == 4, "one native Boss target owns the only active weapon Hurtbox")
	suite.assert_true(actor.is_in_group("enemies") and not watch.is_in_group("enemies") and watch.get_node_or_null("HealthComponent") == null, "watch cannot become an extra roster body or independent reward source")
	await _capture_native(actor, "warning")
	var watch_shape := watch.get_node("CollisionShape2D") as CollisionShape2D
	watch_shape.shape.radius += 1.0
	var geometry_before: Dictionary = actor.launch_runtime_snapshot()
	var geometry_context := context.duplicate(true)
	geometry_context.runtime_frame = 1
	suite.assert_true(not actor.prepare_launch_frame(1, geometry_context).ok and actor.launch_runtime_snapshot() == geometry_before, "tampered actual watch collision fails before advancing Boss state")
	watch_shape.shape.radius -= 1.0
	var outsider := Node.new()
	add_child(outsider)
	var forged := Damage.from_plan({"run_id": "runtime", "target_id": "hostile-watch", "hostile_source_id": "foreign", "attack_generation": 99, "action_token": 99, "amount": 16.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:gun"], "can_crit": false, "source": outsider, "attacker": outsider})
	suite.assert_equal(watch.receive_hit(forged), 0.0, "legacy runtime marker requires a real Player bound to this Boss run")
	outsider.queue_free()
	var impostor := ImpostorPlayer.new()
	add_child(impostor)
	var impersonated := forged.snapshot()
	impersonated.attacker = impostor
	impersonated.source = impostor
	suite.assert_equal(watch.receive_hit(Damage.from_plan(impersonated)), 0.0, "matching current_run_id method cannot impersonate the actual Player script")
	impostor.queue_free()
	var before: Dictionary = actor.launch_runtime_snapshot()
	var watch_before: Dictionary = actor.native_watch_snapshot()
	var published: Array = []
	var listener := func(amount: float, hp: float): published.append([amount, hp])
	health.damaged.connect(listener)
	var deaths: Array = []
	actor.hostile_final_death.connect(func(source: StringName, receipt: String): deaths.append([source, receipt]))
	var ticket: Dictionary = bridge.begin_frame(1)
	_damage_watch(watch, player)
	suite.assert_equal(health.current_hp, 1920.0, "five weapon damage identities carry accepted watch damage to real Boss Health")
	suite.assert_true(runtime.snapshot().mechanism_state.rewind.cancelled and runtime.snapshot().action.phase == "IDLE", "eighty cumulative actual watch damage cancels the native rewind")
	suite.assert_equal(actor.native_watch_snapshot().current_hp, 0.0, "native broken watch projects zero interrupt HP")
	suite.assert_equal(published, [], "candidate watch damage cannot publish before Player frame acceptance")
	suite.assert_true(bridge.prepare_frame(ticket) and bridge.rollback_frame(ticket), "native watch interruption compensates a rejected Player sibling")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "watch rejection restores real Boss Health and complete cast state")
	suite.assert_equal(actor.native_watch_snapshot(), watch_before, "watch rejection reconstructs its complete native projection")
	suite.assert_equal(published, [], "rejected watch damage emits no public observation")
	ticket = bridge.begin_frame(1)
	_damage_watch(watch, player)
	suite.assert_true(bridge.prepare_frame(ticket), "same five native watch identities retry after rollback")
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	suite.assert_true(not publication.is_empty() and bridge.finalize_frame_publication(publication) and bridge.seal_frame_publication(publication), "accepted watch interruption seals real Boss damage")
	bridge.publish_prepared_frame()
	suite.assert_equal(published.size(), 5, "accepted watch interruption publishes five actual damage observations once")
	suite.assert_equal(deaths, [], "watch destruction cannot publish an independent counted death")
	suite.assert_equal(runtime.snapshot().mechanism_state.phase_transition_until_frame, 55, "watch break retains the complete fifty-five-frame punishment from accepted frame one")
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var twin := BossScene.instantiate() as Node2D
	twin.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(twin)
	twin.configure_launch_definition(parser.runtime_projection(), cold.identity)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh native Boss restores the accepted broken-watch cold state")
	suite.assert_equal(twin.native_watch_snapshot(), actor.native_watch_snapshot(), "cold reconstruction preserves watch HP, identity and cast interruption")
	suite.assert_equal(twin.get_node("WatchHurtbox").collision_layer, 4, "cold reconstruction restores one actual hittable watch proxy")
	await _capture_native(actor, "broken")
	for frame: int in range(2, 56):
		context.runtime_frame = frame
		suite.assert_true(runtime.advance_frame(frame, context, false).ok, "watch punishment retains accepted frame %d" % frame)
	suite.assert_true(not runtime.request_action("traitor_temporal_slash", context).ok, "watch break still prevents attack on its fifty-fifth accepted punishment frame")
	context.runtime_frame = 56
	suite.assert_true(runtime.advance_frame(56, context, false).ok and runtime.request_action("traitor_temporal_slash", context).ok, "watch break permits a fresh authored warning only after all fifty-five punishment frames")
	health.damaged.disconnect(listener)
	actor.queue_free()
	twin.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_actual_weapon_payloads() -> void:
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		var actor := BossScene.instantiate() as Node2D
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(actor)
		actor.global_position = Vector2(140.0, 100.0)
		actor.set_meta("stable_target_id", 701)
		var parser := Definition.new()
		parser.configure(Content.boss("time_sovereign"))
		actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-p15", "hostile_source_id": "hostile-watch", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42})
		actor.get_node("HealthComponent").defense = 0.0
		var player := PlayerScene.instantiate() as Node2D
		player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(player)
		player.configure_run(&"run-p15")
		player.global_position = Vector2(100.0, 100.0)
		var runtime: RefCounted = actor.get("_launch_runtime")
		var context := {"runtime_frame": 0, "source_position": {"x": 140.0, "y": 100.0}, "target_position": {"x": 100.0, "y": 100.0}, "facing_direction": {"x": -1.0, "y": 0.0}, "target_id": "player"}
		runtime.request_action("traitor_self_rewind", context)
		actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
		var payload: Node2D
		match weapon:
			"sword":
				payload = Hitbox.new()
				add_child(payload)
				payload.activate(Damage.from_plan({"run_id": "run-p15", "target_id": "pending_target", "hostile_source_id": "player:sword", "attack_generation": 11, "action_token": 11, "amount": 16.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player}))
			"gun":
				payload = GunScene.instantiate()
				payload.owner_entity = player
				payload.source = player
				var execution := _ranged_execution()
				execution.merge({"source_action_id": "normal_fire", "pierce": 0, "pierce_mode": "limited", "damage_type": Damage.DamageType.PHYSICAL, "time_damage_ratio": 0.0, "trail": {}, "time_interactions": [], "boss_conversion": {}, "resource_reward": {}, "action_claims": {}, "tags": ["weapon:gun"]})
				suite.assert_true(payload.configure_execution(execution), "real Gun payload binds")
				add_child(payload)
			"bow":
				payload = ArrowScene.instantiate()
				payload.owner_entity = player
				payload.source = player
				var execution := _ranged_execution()
				execution.merge({"source_action_id": "quick_shot", "pierce": 0, "pierce_mode": "limited", "full_charge": false, "time_energy_restore": 0.0, "energy_reward_once_per_action": true, "time_damage_ratio": 0.0, "trail": {}, "first_hit_control": {}, "time_interactions": [], "boss_conversion": {}, "tags": ["weapon:bow"]})
				suite.assert_true(payload.configure_execution(execution), "real Bow arrow binds")
				add_child(payload)
			"staff":
				payload = Staff.new()
				payload.owner_entity = player
				payload.source = player
				var execution := _ranged_execution()
				execution.merge({"source_action_id": "arcane_bolt", "generation": 5, "element_id": "fire", "target_deduplication": "per_action_target", "effect_descriptor": {}, "combination": {}, "chain": {}})
				suite.assert_true(payload.configure_execution(execution), "real Staff projectile binds")
				add_child(payload)
			"gauntlets":
				payload = Gauntlets.new()
				payload.owner_entity = player
				payload.source = player
				suite.assert_true(payload.configure_execution({"action_token": 15, "generation": 5, "source_action_id": "punch_1", "descriptor_id": "watch_punch", "outcome_index": 0, "deterministic_seed": 42, "kind": "hitbox", "parameters": {"damage_multiplier": 1.0, "combo_eligible": false, "energy_eligible": false, "stop_extension_eligible": false}, "base_attack": 16.0, "direction": Vector2.RIGHT, "target_deduplication": "per_action_target", "progress_claims": {}, "progress_claim_order": [], "damage_claims": {}, "damage_claim_order": []}), "real Gauntlets hit execution binds")
				add_child(payload)
		payload.process_mode = Node.PROCESS_MODE_DISABLED
		payload.global_position = player.global_position
		var watch := actor.get_node("WatchHurtbox") as Area2D
		payload.call("_on_area_entered", watch)
		var amount: float = 2000.0 - float(actor.get_node("HealthComponent").current_hp)
		suite.assert_true(amount > 0.0 and is_equal_approx(float(runtime.snapshot().mechanism_state.rewind.weakpoint_damage), amount), "actual " + weapon + " native collision settles real Health and watch threshold")
		payload.call("_on_area_entered", watch)
		suite.assert_equal(actor.get_node("HealthComponent").current_hp, 2000.0 - amount, "actual " + weapon + " native collision deduplicates one Boss target")
		payload.queue_free()
		actor.queue_free()
		player.queue_free()
		await get_tree().process_frame


func _ranged_execution() -> Dictionary:
	return {"action_token": 14, "descriptor_id": "watch_probe", "outcome_index": 0, "deterministic_seed": 42, "damage": 16.0, "base_attack": 16.0, "speed": 240.0, "max_range_pixels": 240.0}


func _test_buffered_watch_lethal() -> void:
	var actor := BossScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = Vector2(100.0, 100.0)
	var parser := Definition.new()
	parser.configure(Content.boss("time_sovereign"))
	actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-p15", "hostile_source_id": "hostile-watch", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42})
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(140.0, 100.0)
	var effects := Effects.new()
	effects.configure("run-p15")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "native lethal watch fixture binds one Boss participant")
	var deaths: Array = []
	actor.hostile_final_death.connect(func(source: StringName, receipt: String): deaths.append([source, receipt]))
	var before: Dictionary = actor.launch_runtime_snapshot()
	var ticket: Dictionary = bridge.begin_frame(1)
	var info := Damage.from_plan({"run_id": "run-p15", "target_id": "hostile-watch", "hostile_source_id": "player:1", "attack_generation": 61, "action_token": 61, "amount": 5000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})
	actor.get_node("WatchHurtbox").receive_hit(info)
	suite.assert_true(actor.get_node("HealthComponent").dead and bridge.prepare_frame(ticket), "buffered lethal watch damage still prepares the real native Boss terminal frame")
	suite.assert_equal(actor.get_node("WatchHurtbox").collision_layer, 0, "candidate terminal watch projection retires its actual collision")
	suite.assert_true(bridge.rollback_frame(ticket), "buffered lethal watch state compensates rejection")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "lethal rejection restores the entire live Boss domain and Health")
	suite.assert_equal(actor.get_node("WatchHurtbox").collision_layer, 4, "lethal rejection restores actual watch collision")
	suite.assert_equal(deaths, [], "lethal rejection cannot publish an extra watch or Boss reward")
	ticket = bridge.begin_frame(1)
	actor.get_node("WatchHurtbox").receive_hit(info)
	suite.assert_true(bridge.prepare_frame(ticket), "buffered native lethal watch retry prepares once")
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	suite.assert_true(not publication.is_empty() and bridge.finalize_frame_publication(publication) and bridge.seal_frame_publication(publication), "native lethal watch seals one final Boss death")
	bridge.publish_prepared_frame()
	suite.assert_equal(deaths.size(), 1, "accepted native lethal watch publishes exactly one counted Boss death")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _damage_watch(watch: Area2D, player: Node2D) -> void:
	var token := 0
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		token += 1
		var info := Damage.from_plan({"run_id": "run-p15", "target_id": "hostile-watch", "hostile_source_id": "player:1", "attack_generation": token, "action_token": token, "amount": 16.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:" + weapon], "can_crit": false, "source": player, "attacker": player})
		suite.assert_equal(watch.receive_hit(info), 16.0, "native watch accepts immutable " + weapon + " damage")
		suite.assert_equal(watch.receive_hit(info), 0.0, "native watch rejects duplicate " + weapon + " damage unchanged")


func _capture_native(actor: Node2D, pose: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var original := actor.global_position
	actor.global_position = Vector2(200.0, 140.0)
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		var colors: Dictionary = {}
		var foreground := 0
		var background := pixels.get_pixel(0, 0).to_rgba32()
		for y: int in range(126, 154):
			for x: int in range(186, 214):
				var point := Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))
				var color := pixels.get_pixelv(point).to_rgba32()
				colors[color] = true
				foreground += int(color != background)
		suite.assert_true(colors.size() >= 5 and foreground > 200, "native watch draws substantial original raster pixels")
		var output := "res://build/visual-evidence/p15b-native-watch/time-watch-%s-%dx%d.png" % [pose, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native watch screenshot is retained")
	actor.global_position = original
