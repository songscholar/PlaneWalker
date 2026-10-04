extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/launch_semantic_effect_authority.gd")
	suite.assert_true(implementation != null, "native semantic effect authority exists")
	if implementation != null:
		await _test_native_heal(implementation)
		await _test_zone_budget(implementation)
		await _test_simultaneous_native_heal()
		await _test_native_priest_history()
		await _test_native_terminal_hazards()
		await _test_native_storm_death()
		await _test_native_spore_residual()
		await _test_native_status_disposal(implementation)
	suite.finish(get_tree())


func _actor(id: String, source: String) -> Node2D:
	var actor: Node2D = ActorScene.instantiate()
	add_child(actor)
	var parser := Enemy.new()
	parser.configure(Content.enemy(id))
	var identity := Fixtures.identity()
	identity.hostile_source_id = source
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok, "semantic native source configures")
	actor.global_position = Vector2(100, 100)
	return actor


func _test_native_heal(implementation: Script) -> void:
	var watcher := _actor("rift_watcher", "hostile:watcher")
	var recipient := _actor("shattered_sentinel", "hostile:recipient")
	recipient.global_position = Vector2(120, 100)
	recipient.apply_time_stop_source(&"semantic-recipient-stop", 20.0)
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(120, 100)
	var health := recipient.get_node("HealthComponent")
	health.take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:recipient", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 50.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:bow"], "can_crit": false}))
	var authority: RefCounted = implementation.new()
	suite.assert_true(authority.configure("run-p15", 0), "semantic authority accepts fixed clock")
	var root := Node2D.new()
	add_child(root)
	suite.assert_true(authority.configure_native_root(root), "semantic authority owns real native projection root")
	var registry := Registry.new()
	var actors := {"hostile:recipient": recipient, "hostile:watcher": watcher}
	var observation := Fixtures.context()
	watcher.get("_launch_runtime").request_action("rift_watcher.nourish", observation)
	var healed := 0
	for frame: int in range(1, 31):
		var tickets: Array = []
		var batches: Array = []
		for source: String in actors:
			var actor: Node2D = actors[source]
			var context := Fixtures.context(frame)
			context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
			var prepared: Dictionary = actor.prepare_launch_frame(frame, context)
			suite.assert_true(prepared.ok, "semantic actor prepares sequential frame")
			tickets.append({"actor": actor, "ticket": prepared.ticket})
			batches.append({"hostile_source_id": source, "batch": prepared.batch})
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": actors, "targets": {"player:1": player}}
		var before: Dictionary = authority.snapshot()
		var prepared: Dictionary = authority.prepare_effects(batches, context)
		suite.assert_true(prepared.ok, "actual sealed support action prepares semantic effect")
		if not prepared.ok:
			for pair: Dictionary in tickets:
				pair.actor.rollback_launch_frame(pair.ticket)
			break
		suite.assert_equal(authority.snapshot(), before, "semantic preparation is observation-only")
		var forged: Dictionary = prepared.ticket.duplicate(true)
		forged.after.runtime_frame = frame + 1
		suite.assert_true(not authority.commit(forged), "forged semantic ticket rejects atomically")
		for pair: Dictionary in tickets:
			suite.assert_true(pair.actor.commit_launch_frame(pair.ticket), "semantic actor commits before effect")
		suite.assert_true(authority.commit(prepared.ticket), "semantic effect commits its bounded state")
		for request: Dictionary in prepared.health_requests:
			suite.assert_equal(request.target_id, "hostile:recipient", "support excludes itself and Player")
			suite.assert_equal(request.amount, 5.0, "actual Watcher uses authored heal amount")
			healed += 1
		var expected_requests: int = 1 if frame == 30 else 0
		suite.assert_equal(prepared.health_requests.size(), expected_requests, "heal occurs once after the full warning")
		suite.assert_true(authority.rollback(prepared.ticket), "semantic rollback compensates counters and native projection")
		suite.assert_equal(authority.snapshot(), before, "semantic rollback preserves exact checkpoint")
		for pair: Dictionary in tickets:
			pair.actor.rollback_launch_frame(pair.ticket)
		var retry_tickets: Array = []
		var retry_batches: Array = []
		for source: String in actors:
			var actor: Node2D = actors[source]
			var retry_context := Fixtures.context(frame)
			retry_context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
			var retry: Dictionary = actor.prepare_launch_frame(frame, retry_context)
			retry_tickets.append({"actor": actor, "ticket": retry.ticket})
			retry_batches.append({"hostile_source_id": source, "batch": retry.batch})
		var retry: Dictionary = authority.prepare_effects(retry_batches, context)
		suite.assert_equal(retry.health_requests, prepared.health_requests, "same frame retry retains identical heal claim")
		for pair: Dictionary in retry_tickets:
			pair.actor.commit_launch_frame(pair.ticket)
		suite.assert_true(authority.commit(retry.ticket) and authority.can_publish(retry.ticket), "semantic retry seals before publication")
		for pair: Dictionary in retry_tickets:
			pair.actor.publish_launch_frame(pair.ticket)
		suite.assert_true(authority.publish(retry.ticket), "semantic effect publication releases its sealed ticket")
	suite.assert_equal(healed, 1, "actual support emits exactly one healing request")
	var checkpoint: Dictionary = authority.snapshot()
	suite.assert_true(authority.can_restore_transaction_snapshot(checkpoint), "semantic checkpoint validates")
	checkpoint.unowned = true
	suite.assert_true(not authority.restore_transaction_snapshot(checkpoint), "unowned semantic fields reject")
	watcher.queue_free()
	recipient.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _test_zone_budget(implementation: Script) -> void:
	var authority: RefCounted = implementation.new()
	authority.configure("run-p15")
	var root := Node2D.new()
	add_child(root)
	authority.configure_native_root(root)
	var state: Dictionary = authority.snapshot()
	state.zones.append(_zone_record("pending:first", "hostile:pending", true, 1, 4))
	for index: int in range(12):
		state.zones.append(_zone_record("active:%d" % index, "hostile:%d" % index, false, 2, 4))
	suite.assert_true(authority.restore_transaction_snapshot(state), "native budget fixture restores twelve visible zones and retained pending decision")
	for frame: int in range(1, 4):
		var prepared: Dictionary = authority.prepare_effects([], {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": Registry.new(), "actors": {}, "targets": {}})
		suite.assert_true(prepared.ok, "pending zone admission respects complete room budget")
		if not prepared.ok:
			break
		suite.assert_true(authority.commit(prepared.ticket) and authority.publish(prepared.ticket), "bounded pending zone commits natively")
		var zones: Array = authority.snapshot().zones
		suite.assert_equal(zones.filter(func(row: Dictionary): return row.phase != "PENDING").size(), 12 if frame <= 2 else 1, "later existing zones reserve capacity before pending work")
		if frame <= 2:
			suite.assert_equal(zones[0].phase, "PENDING", "full budget retains original pending decision")
		else:
			suite.assert_equal(zones[0].active_frame, 3, "delayed lifetime begins on admission")
			suite.assert_equal(zones[0].expires_frame, 3, "delayed finite lifetime remains authored")
	root.queue_free()
	await get_tree().process_frame


func _zone_record(id: String, source: String, pending: bool, lifetime: int, cap: int) -> Dictionary:
	return {"id": id, "source_id": source, "action_id": "rift_weaver.rift_make", "generation": 1, "hit_index": 0, "reserved_frame": 0, "active_frame": -1 if pending else 0, "expires_frame": -1 if pending else lifetime, "geometry": {"hostile_source_id": source, "attack_generation": 1, "shape": "circle", "origin": {"x": 120.0, "y": 100.0}, "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": {"x": 120.0, "y": 100.0}, "summon_slots": [], "radius": 19.0, "length": 0.0, "active_from_frame": 0, "active_through_frame": 100}, "initial_damage": 8.0, "damage": 8.0, "damage_type": "void", "tick_damage_type": "void", "tick_frames": 60, "warning_frames": 0, "lifetime_frames": lifetime if pending else lifetime + 1, "slow_multiplier": 0.6, "slow_frames": 60, "enemy_only_freeze": false, "owner_immunity": false, "ally_damage": false, "owner_zone_cap": cap, "phase": "PENDING" if pending else "ACTIVE"}


func _test_simultaneous_native_heal() -> void:
	var first := _actor("rift_watcher", "hostile:healer-a")
	var second := _actor("rift_watcher", "hostile:healer-b")
	var recipient := _actor("shattered_sentinel", "hostile:healed")
	var actors := {"hostile:healed": recipient, "hostile:healer-a": first, "hostile:healer-b": second}
	recipient.apply_time_stop_source(&"heal-fixture-stop", 20.0)
	var health: Node = recipient.get_node("HealthComponent")
	health.take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:healed", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 3.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:bow"], "can_crit": false}))
	var publication := {"count": 0, "amount": 0.0}
	health.healed.connect(func(amount: float, _hp: float):
		publication.count += 1
		publication.amount += amount
	)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	first.get("_launch_runtime").request_action("rift_watcher.nourish", Fixtures.context())
	second.get("_launch_runtime").request_action("rift_watcher.nourish", Fixtures.context())
	for frame: int in range(1, 31):
		var pairs: Array[Dictionary] = []
		var batches: Array[Dictionary] = []
		for id: String in actors:
			var actor: Node2D = actors[id]
			var observation := Fixtures.context(frame)
			observation.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
			var prepared: Dictionary = actor.prepare_launch_frame(frame, observation)
			suite.assert_true(prepared.ok, "multiple native healers prepare fixed frame")
			pairs.append({"actor": actor, "ticket": prepared.ticket})
			batches.append({"hostile_source_id": id, "batch": prepared.batch})
		var prepared: Dictionary = effects.prepare_effects(batches, {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": actors, "targets": {}})
		suite.assert_true(prepared.ok, "actual native heal router accepts competing support sources")
		if not prepared.ok:
			for pair: Dictionary in pairs:
				pair.actor.rollback_launch_frame(pair.ticket)
			break
		for pair: Dictionary in pairs:
			suite.assert_true(pair.actor.commit_launch_frame(pair.ticket), "native heal actor commits")
		suite.assert_true(effects.commit_effects(prepared.ticket).ok, "actual Health sink receives authored heal")
		suite.assert_equal(publication.count, 0, "native healing stays buffered until publication")
		for pair: Dictionary in pairs:
			pair.actor.publish_launch_frame(pair.ticket)
		suite.assert_true(effects.publish_effects(prepared.ticket), "actual support heal publishes once")
	suite.assert_equal(health.current_hp, health.max_hp, "same-frame healing clamps to native missing HP")
	suite.assert_equal(publication.count, 1, "competing healer with zero remaining gain emits no observation")
	suite.assert_equal(publication.amount, 3.0, "native publication reports actual positive gain")
	var semantic: Dictionary = effects.semantic_snapshot()
	suite.assert_equal(semantic.heal_recipients.get("hostile:healed", 0.0), 3.0, "shared healing budget charges actual same-frame gain")
	suite.assert_equal(semantic.heal_sources.get("hostile:healer-b", {}), {}, "later healer retains unused encounter budget")
	_injure(first, 1000.0, 2)
	suite.assert_true(_native_step(effects, actors, 31, registry), "support final death commits actual native lifecycle")
	suite.assert_equal(recipient.get("_launch_runtime").control_modifiers().get("attack_multiplier", 1.0), 0.8, "Watcher final death debuffs its actual healed recipient")
	suite.assert_equal(second.get("_launch_runtime").control_modifiers().get("attack_multiplier", 1.0), 1.0, "Watcher death does not debuff an unrelated support")
	for actor: Node2D in actors.values():
		actor.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _test_native_priest_history() -> void:
	for observed_full_hp: bool in [false, true]:
		var priest := _actor("rewind_priest", "hostile:priest")
		var recipient := _actor("shattered_sentinel", "hostile:history")
		recipient.apply_time_stop_source(&"history-fixture-stop", 20.0)
		priest.get("_launch_runtime").request_action("rewind_priest.rewind_heal", Fixtures.context())
		var root := Node2D.new()
		add_child(root)
		var effects := Effects.new()
		effects.configure("run-p15", 0)
		effects.configure_native_payloads(root)
		var registry := Registry.new()
		var actors := {"hostile:history": recipient, "hostile:priest": priest}
		if not observed_full_hp:
			_injure(recipient, 50.0, 1)
		for frame: int in range(1, 46):
			suite.assert_true(_native_step(effects, actors, frame, registry), "Priest native history accepts sequential observed frames")
			if observed_full_hp and frame == 1:
				_injure(recipient, 50.0, 1)
		var health: Node = recipient.get_node("HealthComponent")
		suite.assert_equal(health.current_hp, 54.0 if observed_full_hp else 30.0, "Priest healing uses observed historical HP and thirty percent recipient bound")
		var semantic: Dictionary = effects.semantic_snapshot()
		suite.assert_equal(semantic.heal_recipients.get("hostile:history", 0.0), 24.0 if observed_full_hp else 0.0, "Priest never fabricates a pre-observation maximum HP history")
		for actor: Node2D in actors.values():
			actor.queue_free()
		root.queue_free()
		await get_tree().process_frame


func _injure(actor: Node2D, amount: float, generation: int) -> void:
	actor.get_node("HealthComponent").take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": str(actor.hostile_source_id), "hostile_source_id": "player:1", "attack_generation": generation, "action_token": generation, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:bow"], "can_crit": false}))


func _native_step(effects: RefCounted, actors: Dictionary, frame: int, registry: RefCounted, targets: Dictionary = {}) -> bool:
	var pairs: Array[Dictionary] = []
	var batches: Array[Dictionary] = []
	for id: String in actors:
		var actor: Node2D = actors[id]
		if actor.launch_runtime_snapshot().runtime.terminal:
			continue
		var observation := Fixtures.context(frame)
		observation.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
		var prepared: Dictionary = actor.prepare_launch_frame(frame, observation)
		if not prepared.ok:
			return false
		pairs.append({"actor": actor, "ticket": prepared.ticket})
		batches.append({"hostile_source_id": id, "batch": prepared.batch})
	var prepared: Dictionary = effects.prepare_effects(batches, {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": registry, "actors": actors, "targets": targets})
	if not prepared.ok:
		for pair: Dictionary in pairs:
			pair.actor.rollback_launch_frame(pair.ticket)
		return false
	for pair: Dictionary in pairs:
		if not pair.actor.commit_launch_frame(pair.ticket):
			return false
	if not effects.commit_effects(prepared.ticket).ok:
		return false
	for pair: Dictionary in pairs:
		if not pair.actor.publish_launch_frame(pair.ticket):
			return false
	return effects.publish_effects(prepared.ticket)


func _test_native_terminal_hazards() -> void:
	var titan := _actor("forge_titan", "hostile:titan")
	var player: Node2D = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(120, 100)
	var health: Node = player.get_node("HealthComponent")
	health.max_hp = 1000.0
	health.current_hp = 1000.0
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15", 0)
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var actors := {"hostile:titan": titan}
	_injure(titan, 1000.0, 1)
	suite.assert_true(titan.get_node("HealthComponent").dead, "corpse fixture is a real final native death")
	for frame: int in range(1, 243):
		if not _native_step(effects, actors, frame, registry, {"player:1": player}):
			suite.assert_true(false, "corpse hazard accepts every finite native frame %d" % frame)
			break
		if frame == 1:
			suite.assert_equal(effects.native_semantic_nodes().size(), 2, "final Titan death retains warned explosion and finite native pool")
			suite.assert_equal(registry.snapshot().size(), 2, "death hazard warning uses independent native source generations")
		if frame == 60:
			suite.assert_equal(health.current_hp, 1000.0, "corpse explosion completes sixty continuous warning frames")
		if frame == 61:
			suite.assert_equal(health.current_hp, 960.0, "native corpse explosion applies forty damage once")
		if frame == 62:
			suite.assert_equal(health.current_hp, 952.0, "native corpse pool starts after explosion with separate warning")
	suite.assert_equal(health.current_hp, 936.0, "finite corpse pool applies exactly three authored sixty-frame ticks")
	suite.assert_equal(effects.semantic_snapshot().zones, [], "terminal work expires instead of holding the room indefinitely")
	suite.assert_equal(effects.native_semantic_nodes(), [], "expired corpse effects release native projections")
	suite.assert_equal(registry.snapshot(), [], "expired terminal effects retire native threat facts")
	titan.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _test_native_status_disposal(implementation: Script) -> void:
	var actor := _actor("shattered_sentinel", "hostile:status")
	actor.get("_launch_runtime").add_control_source("outside_buff", "attack_buff", 60, 1.15)
	var player: Node2D = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.configure_run(&"run-p15")
	player.apply_floor_rule_modifier(&"outside_rule", &"movement", &"apply", {"movement_multiplier": 0.8})
	var authority: RefCounted = implementation.new()
	authority.configure("run-p15")
	suite.assert_true(authority.bind_native_targets({"hostile:status": actor}, {"player:1": player}), "cold semantic projection binds actual actor and Player before restore")
	var state: Dictionary = authority.snapshot()
	state.statuses = [{"id": "player_status", "target_id": "player:1", "expires_frame": 60, "slow_multiplier": 0.6, "speed_multiplier": 1.0, "attack_multiplier": 1.0, "freeze_actions": false}, {"id": "actor_status", "target_id": "hostile:status", "expires_frame": 60, "slow_multiplier": 1.0, "speed_multiplier": 1.0, "attack_multiplier": 0.8, "freeze_actions": false}]
	suite.assert_true(authority.restore_transaction_snapshot(state), "cold semantic checkpoint projects actual status modifiers")
	suite.assert_close(actor.get("_launch_runtime").control_modifiers().get("attack_multiplier", 1.0), 0.92, "native restored penalty combines once with unrelated strongest buff")
	suite.assert_true(player.floor_rule_effect_snapshot().modifiers.has("launch_semantic|movement"), "native restored slow owns its exact Player modifier source")
	suite.assert_true(authority.dispose_native_effects(), "room teardown disposes native semantic effect ownership")
	suite.assert_equal(actor.get("_launch_runtime").control_modifiers().get("attack_multiplier", 1.0), 1.15, "room disposal preserves unrelated native attack buff")
	suite.assert_true(not player.floor_rule_effect_snapshot().modifiers.has("launch_semantic|movement"), "room disposal cannot leave persistent Player slowdown")
	suite.assert_true(player.floor_rule_effect_snapshot().modifiers.has("outside_rule|movement"), "room disposal preserves unrelated floor-rule modifier")
	suite.assert_equal(authority.snapshot().statuses, [], "room disposal clears authoritative finite statuses")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _semantic_player() -> Node2D:
	var player: Node2D = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(120, 100)
	player.get_node("HealthComponent").max_hp = 1000.0
	player.get_node("HealthComponent").current_hp = 1000.0
	return player


func _test_native_storm_death() -> void:
	var storm := _actor("chrono_storm_elemental", "hostile:storm")
	var player := _semantic_player()
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var receipts: Array = []
	storm.hostile_final_death.connect(func(source: StringName, receipt: String): receipts.append([source, receipt]))
	_injure(storm, 1000.0, 1)
	for frame: int in range(1, 218):
		suite.assert_true(_native_step(effects, {"hostile:storm": storm}, frame, registry, {"player:1": player}), "native Storm death pulse accepts finite frame")
		if frame == 1:
			suite.assert_equal(effects.native_semantic_nodes().size(), 1, "real final Storm death projects one independent warned pulse")
			suite.assert_equal(registry.snapshot().size(), 1, "Storm death pulse owns an actual warning registry fact")
		if frame == 35:
			suite.assert_true(not player.floor_rule_effect_snapshot().modifiers.has("launch_semantic|movement"), "Storm death pulse preserves all thirty-five warning frames")
		if frame == 36:
			suite.assert_close(player.call("_floor_rule_movement_multiplier"), 0.7, "Storm death pulse applies authored slow through native Player modifier")
		if frame == 37:
			suite.assert_equal(effects.native_semantic_nodes(), [], "single death pulse retires its projection after activation")
			suite.assert_equal(registry.snapshot(), [], "single death pulse retires its native warning fact")
		if frame == 216:
			suite.assert_close(player.call("_floor_rule_movement_multiplier"), 0.7, "Storm slow persists independently after pulse projection ends")
	suite.assert_true(not player.floor_rule_effect_snapshot().modifiers.has("launch_semantic|movement"), "finite Storm death slow cannot remain after expiry")
	suite.assert_equal(player.get_node("HealthComponent").current_hp, 1000.0, "Storm death pulse never fabricates a damaging hit")
	suite.assert_equal(receipts.size(), 1, "Storm death effect cannot duplicate counted final death")
	storm.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _test_native_spore_residual() -> void:
	var spore := _actor("void_spore", "hostile:spore")
	var player := _semantic_player()
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15")
	effects.configure_native_payloads(root)
	var registry := Registry.new()
	var started: Dictionary = spore.get("_launch_runtime").request_action("void_spore.spore_burst", Fixtures.context())
	for fact: Dictionary in started.threat_facts:
		registry.register_fact(preload("res://scripts/enemies/launch/hostile_action_coordinator.gd").native_threat_fact(fact))
	var receipts: Array = []
	spore.hostile_final_death.connect(func(source: StringName, receipt: String): receipts.append([source, receipt]))
	for frame: int in range(1, 247):
		if frame == 67:
			player.global_position = Vector2(500, 100)
		if frame == 96:
			player.global_position = Vector2(120, 100)
		suite.assert_true(_native_step(effects, {"hostile:spore": spore}, frame, registry, {"player:1": player}), "native Spore burst and residual accept finite frame")
		var hp: float = player.get_node("HealthComponent").current_hp
		if frame == 29:
			suite.assert_equal(hp, 1000.0, "Spore burst cannot hit before full thirty-frame warning")
		if frame == 30:
			suite.assert_equal(hp, 988.0, "actual Spore burst resolves one twelve-damage native hit")
		if frame == 36:
			suite.assert_true(spore.get_node("HealthComponent").dead and spore.launch_runtime_snapshot().runtime.terminal, "accepted burst consumes actual counted Spore Health exactly once")
			suite.assert_equal(effects.native_semantic_nodes().size(), 1, "consumed Spore retains independent warned residual native pool")
		if frame == 65:
			suite.assert_equal(hp, 988.0, "Spore residual receives its independent thirty-frame warning")
		if frame == 66:
			suite.assert_equal(hp, 983.0, "residual starts with actual five-point native damage")
			suite.assert_close(player.call("_floor_rule_movement_multiplier"), 0.8, "residual projects authored native slowdown")
		if frame == 67:
			suite.assert_true(not player.floor_rule_effect_snapshot().modifiers.has("launch_semantic|movement"), "leaving Spore residual removes its area-bound slowdown")
		if frame == 96:
			suite.assert_close(player.call("_floor_rule_movement_multiplier"), 0.8, "reentering residual reapplies slowdown without an extra damage tick")
			suite.assert_equal(hp, 983.0, "reentering residual preserves original tick phase")
	suite.assert_equal(player.get_node("HealthComponent").current_hp, 973.0, "Spore residual applies exactly three five-point ticks over its finite lifetime")
	suite.assert_equal(receipts.size(), 1, "Spore burst consumption publishes one counted death receipt")
	suite.assert_equal(effects.semantic_snapshot().zones, [], "Spore residual finite TTL releases room work")
	suite.assert_equal(effects.native_semantic_nodes(), [], "Spore residual finite TTL releases actual native projections")
	suite.assert_equal(registry.snapshot(), [], "Spore residual finite TTL retires actual registry facts")
	suite.assert_true(not player.floor_rule_effect_snapshot().modifiers.has("launch_semantic|movement"), "expired Spore residual cannot leave an unauthored sixty-frame slow")
	spore.queue_free()
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame
