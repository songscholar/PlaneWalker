extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_enemy_runtime.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_stone_shell_strider.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Registry := preload("res://scripts/content/content_registry.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")

var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	_test_cycle_and_restore()
	await _test_native_shock()
	suite.finish(get_tree())


func _definition() -> Dictionary:
	var parser := Enemy.new()
	return parser.runtime_projection("elite") if parser.configure(Content.enemy("stone_shell_strider")).ok else {}


func _identity() -> Dictionary:
	return {"run_id": "run-p15", "hostile_source_id": "hostile-ruins-strider-elite", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}


func _context(frame: int) -> Dictionary:
	var result := Actions.context(frame)
	result.target_id = "player"
	return result


func _damage(id: String, frame: int) -> Dictionary:
	return {"fact_id": id, "runtime_frame": frame, "target_source_id": _identity().hostile_source_id, "amount": 1.0, "hp_after": 119.0}


func _test_cycle_and_restore() -> void:
	var runtime := Runtime.new()
	suite.assert_true(runtime.configure(_definition(), _identity()).ok, "native elite consumes all three actual Strider actions")
	var corrupt := runtime.snapshot()
	corrupt.mechanism_state.shell_shock_used = true
	suite.assert_true(not runtime.can_restore_snapshot(corrupt), "elite shock expenditure cannot exist before its first shell cycle")
	suite.assert_true(not runtime.request_action("stone_shell_strider.shell_shock", _context(0)).ok, "elite shock cannot warn outside an authenticated shell cycle")
	suite.assert_true(runtime.accept_damage_fact(_damage("shock-cycle-1", 0)).ok, "real damage fact opens elite shell cycle")
	var first_ready: int = runtime.snapshot().mechanism_state.first_attack_ready_frame
	for frame: int in range(1, maxi(1, first_ready) + 1):
		suite.assert_true(runtime.advance_frame(frame, _context(frame)).ok, "elite automatic selection advances through seeded ready gate")
	suite.assert_equal(runtime.snapshot().action.action_id, "stone_shell_strider.shell_shock", "elite automatic selection reserves its one shell shock before base attacks exhaust the shell")
	if runtime.snapshot().action.action_id != "stone_shell_strider.shell_shock":
		return
	corrupt = runtime.snapshot()
	corrupt.mechanism_state.shell_shock_used = false
	suite.assert_true(not runtime.can_restore_snapshot(corrupt), "committed elite shock cannot restore with an unspent same-cycle claim")
	var start: int = runtime.snapshot().runtime_frame
	runtime.add_control_source("stop-shell-shock", "stop", 3, 1.0)
	for frame: int in range(start + 1, start + 4):
		var stopped: Dictionary = runtime.advance_frame(frame, _context(frame), false)
		suite.assert_equal(stopped.phase, "WARNING", "Stop preserves committed shell shock warning and cycle claim")
		suite.assert_true(stopped.hit_facts.is_empty() and runtime.snapshot().mechanism_state.shell_shock_used, "Stop cannot spend or reset an additional shock")
	for frame: int in range(start + 4, 151):
		runtime.advance_frame(frame, _context(frame), false)
	suite.assert_true(not runtime.request_action("stone_shell_strider.shell_shock", _context(150)).ok, "finished shell cannot mint a second shock")
	runtime.accept_damage_fact(_damage("shock-cycle-2", 150))
	suite.assert_equal(runtime.snapshot().mechanism_state.shell_cycle, 2, "new authenticated shell cycle resets only its own shock claim")
	suite.assert_true(not runtime.snapshot().mechanism_state.shell_shock_used, "later cycle has a fresh bounded claim")
	for frame: int in range(151, start + 301):
		runtime.advance_frame(frame, _context(frame), false)
	suite.assert_true(not runtime.request_action("stone_shell_strider.shell_shock", _context(start + 300)).ok, "expired shell does not bypass action cooldown or cycle ownership")
	runtime.accept_damage_fact(_damage("shock-cycle-3", start + 300))
	suite.assert_true(runtime.request_action("stone_shell_strider.shell_shock", _context(start + 300)).ok, "third shell after authored cooldown can own one new shock")
	suite.assert_true(not runtime.request_action("stone_shell_strider.shell_shock", _context(start + 300)).ok, "shock claim is reserved at warning commitment")
	var short_definition := _definition()
	short_definition.mechanisms.shell_frames = 60
	short_definition.mechanisms.open_frames = 15
	var short_cycle := Runtime.new()
	short_cycle.configure(short_definition, _identity())
	short_cycle.accept_damage_fact(_damage("short-cycle-1", 0))
	short_cycle.request_action("stone_shell_strider.shell_shock", _context(0))
	for frame: int in range(1, 76):
		short_cycle.advance_frame(frame, _context(frame), false)
	suite.assert_equal(short_cycle.snapshot().action.phase, "RECOVERY", "authored short shell may end before its committed shock recovers")
	short_cycle.accept_damage_fact(_damage("short-cycle-2", 75))
	var overlapping: Dictionary = short_cycle.snapshot()
	suite.assert_true(short_cycle.can_restore_snapshot(overlapping), "previous shock recovery remains valid while a new authored shell cycle begins")
	suite.assert_equal(overlapping.mechanism_state.shell_shock_cycle, 1, "recovering shock retains its original cycle lineage")
	suite.assert_true(overlapping.mechanism_state.shell_cycle == 2 and not overlapping.mechanism_state.shell_shock_used, "new shell owns an unspent claim without rewriting the prior action")


func _test_native_shock() -> void:
	var registry := Registry.new()
	var report: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "real Launch content loads for native Guardian damage contract")
	if report.has_blocking_errors():
		return
	var player := PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "time_guardian", "character_profile": registry.resolve_character_runtime_profile(&"time_guardian", &"LAUNCH"), "character_talents": [], "weapon_id": "sword", "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}
	suite.assert_true(player.configure_loadout(config) and player.configure_run(&"run-p15"), "native Player installs real Launch Guardian and conforming run identity")
	player.global_position = Vector2(120, 100)
	var actor := ActorScene.instantiate()
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	suite.assert_true(actor.configure_launch_definition(_definition(), _identity()).ok, "native actor installs actual elite Strider projection")
	actor.global_position = Vector2(100, 100)
	var incoming := Damage.from_plan({"run_id": "run-p15", "target_id": _identity().hostile_source_id, "hostile_source_id": "player", "attack_generation": 1, "hit_index": 0, "action_token": 1, "amount": 10.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false})
	suite.assert_true(actor.get_node("HealthComponent").take_damage(incoming) > 0.0, "actual native Health hit opens the elite shell cycle")
	await get_tree().physics_frame
	var threats := Threats.new()
	var effects := Effects.new()
	effects.configure("run-p15", 0)
	var health := player.get_node("HealthComponent")
	var before_hp: float = health.current_hp
	var authored_elite_damage: float = _definition().actions[2].hit_schedule[0].damage
	var damage_expected := maxf(0.0, authored_elite_damage - float(player.stats.defense))
	var observed: Array = []
	var listener := func(_info: RefCounted, target: Node, amount: float):
		if target == player:
			observed.append(amount)
	EventBus.hit_confirmed.connect(listener)
	var shock_committed := false
	var shock_hit := false
	var retried_reservation := false
	for frame: int in range(1, 125):
		suite.assert_true(player.advance_action_frame(), "real Guardian commits its native Character frame")
		var checkpoint: Dictionary = actor.launch_transaction_snapshot()
		var observation := _context(frame)
		observation.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
		observation.target_position = {"x": player.global_position.x, "y": player.global_position.y}
		var prepared: Dictionary = actor.prepare_launch_frame(frame, observation)
		suite.assert_true(prepared.ok, "native elite actor prepares authored shock cycle")
		if not prepared.ok:
			actor.restore_launch_transaction_snapshot(checkpoint)
			break
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": threats, "actors": {_identity().hostile_source_id: actor}, "targets": {"player": player}}
		var effect: Dictionary = effects.prepare_effects([{"hostile_source_id": _identity().hostile_source_id, "batch": prepared.batch}], context)
		suite.assert_true(effect.ok, "elite shock authenticates actual circle and native Player target")
		if not effect.ok:
			actor.rollback_launch_frame(prepared.ticket)
			actor.restore_launch_transaction_snapshot(checkpoint)
			break
		suite.assert_true(actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "actual shock state and native Health effects commit")
		var action: Dictionary = actor.launch_runtime_snapshot().runtime.action
		if action.action_id == "stone_shell_strider.shell_shock" and not retried_reservation:
			retried_reservation = true
			var after_reservation: Dictionary = actor.launch_runtime_snapshot().runtime
			suite.assert_true(effects.rollback_effects(effect.ticket) and actor.rollback_launch_frame(prepared.ticket) and actor.restore_launch_transaction_snapshot(checkpoint), "rejected native shock warning restores its cycle claim and real threats")
			suite.assert_true(not actor.launch_runtime_snapshot().runtime.mechanism_state.shell_shock_used, "native compensation removes rejected warning expenditure")
			checkpoint = actor.launch_transaction_snapshot()
			prepared = actor.prepare_launch_frame(frame, observation)
			effect = effects.prepare_effects([{"hostile_source_id": _identity().hostile_source_id, "batch": prepared.batch}], context)
			suite.assert_true(prepared.ok and effect.ok and actor.commit_launch_frame(prepared.ticket) and effects.commit_effects(effect.ticket).ok, "same native shock reservation frame retries")
			suite.assert_equal(actor.launch_runtime_snapshot().runtime, after_reservation, "retry preserves exact cycle, committed warning and attack generations")
		if action.action_id == "stone_shell_strider.shell_shock":
			shock_committed = true
			if action.phase == "WARNING":
				suite.assert_equal(health.current_hp, before_hp, "all forty authored warning frames deal zero shock damage")
			if not prepared.batch.hit_facts.is_empty():
				shock_hit = true
				suite.assert_equal(observed, [], "native shock hit stays buffered before publication")
		suite.assert_true(actor.publish_launch_frame(prepared.ticket) and effects.publish_effect_observations(effect.ticket), "accepted native shock publishes one buffered hit")
		actor.discard_launch_transaction_snapshot(checkpoint)
		if shock_hit:
			suite.assert_close(health.current_hp, before_hp - damage_expected, "actual Launch Guardian takes authored elite shock damage minus its native defense")
			suite.assert_equal(observed, [damage_expected], "one shell shock emits one real finalized hit")
			if action.phase == "RECOVERY":
				break
	suite.assert_true(shock_committed and shock_hit and retried_reservation, "native elite executes actual shell shock and compensates a rejected reservation")
	EventBus.hit_confirmed.disconnect(listener)
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame
