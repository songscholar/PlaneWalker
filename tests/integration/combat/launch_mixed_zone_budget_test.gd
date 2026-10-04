extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Semantics := preload("res://scripts/enemies/launch/launch_semantic_effect_authority.gd")
const Payloads := preload("res://scripts/enemies/launch/launch_hostile_payload_runtime.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _test_native_shared_capacity()
	suite.finish(get_tree())


func _test_native_shared_capacity() -> void:
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(500.0, 100.0)
	var health := player.get_node("HealthComponent")
	health.current_hp = 100.0
	health.defense = 0.0
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-p15", 35)
	effects.configure_native_payloads(root)
	var fixture := _mixed_fixture()
	suite.assert_true(effects.restore_launch_transaction_snapshot(fixture), "closed mixed fixture restores twelve native semantic zones and one queued death pool")
	suite.assert_equal(effects.native_semantic_nodes().size(), 12, "mixed fixture contains twelve real native zone projections")
	suite.assert_equal(effects.native_payload_nodes().size(), 0, "pending death pool reserves work without becoming visible or damaging")
	var oversized := fixture.duplicate(true)
	oversized.payloads.zones[0].phase = "WARNING"
	oversized.payloads.zones[0].activated_frame = 35
	suite.assert_true(not effects.can_restore_launch_transaction_snapshot(oversized), "separately valid child states cannot exceed the shared twelve-zone room cap")
	var threats := Threats.new()
	var semantics := Semantics.new()
	for fact: Dictionary in semantics.threat_facts_for_snapshot(fixture.semantics):
		threats.register_fact(fact)
	var observations: Array = []
	var listener := func(amount: float, hp: float): observations.append([amount, hp])
	health.damaged.connect(listener)
	for frame: int in range(36, 68):
		var before := effects.snapshot()
		var health_before: Dictionary = health.transaction_snapshot()
		var context := {"run_id": "run-p15", "runtime_frame": frame, "threat_registry": threats, "actors": {}, "targets": {"player": player}}
		var prepared: Dictionary = effects.prepare_effects([], context)
		suite.assert_true(prepared.ok, "mixed native capacity advances accepted frame %d: %s" % [frame, str(prepared.get("context", {}))])
		if not prepared.ok:
			health.discard_transaction_snapshot(health_before)
			break
		suite.assert_true(effects.commit(prepared.ticket).ok, "mixed capacity commits both native child authorities")
		if frame in [37, 67]:
			suite.assert_equal(observations, [], "candidate admission or damage publishes no native observation")
			suite.assert_true(effects.rollback(prepared.ticket) and health.restore_transaction_snapshot(health_before), "mixed native admission or damage rejects without consuming work or HP")
			suite.assert_equal(effects.snapshot(), before, "mixed rejection preserves queued work and complete warning clock")
			prepared = effects.prepare_effects([], context)
			suite.assert_true(prepared.ok and effects.commit(prepared.ticket).ok, "same mixed capacity frame retries once")
		suite.assert_true(effects.publish_effect_observations(prepared.ticket), "mixed capacity publishes only accepted native state")
		if frame == 36:
			suite.assert_equal(effects.payload_snapshot().zones[0].phase, "PENDING", "payload cannot take a slot while all twelve semantic zones remain visible")
		if frame == 37:
			suite.assert_equal(effects.native_semantic_nodes().size(), 0, "expired semantic zones release their shared native slots")
			suite.assert_equal(effects.payload_snapshot().zones[0].phase, "WARNING", "freed slot admits the queued death pool into a fresh warning")
			suite.assert_equal(effects.payload_snapshot().zones[0].age, 0, "queued age never consumes the admitted warning")
		if frame < 67:
			suite.assert_equal(health.current_hp, 100.0, "queued hazard retains its full thirty-frame admission warning")
		suite.assert_true(effects.native_semantic_nodes().size() + effects.native_payload_nodes().size() <= 12, "real mixed native projections respect the shared room cap")
		health.discard_transaction_snapshot(health_before)
	suite.assert_equal(health.current_hp, 92.0, "admitted real death pool damages only after its complete new warning")
	suite.assert_equal(observations, [[8.0, 92.0]], "mixed queued damage publishes once after rejection and retry")
	suite.assert_equal(effects.work_snapshot().records, {}, "accepted last native hazard retirement clears both work sources")
	health.damaged.disconnect(listener)
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _mixed_fixture() -> Dictionary:
	var effects := Effects.new()
	effects.configure("run-p15", 35)
	var result := effects.snapshot()
	var semantics := Semantics.new()
	for index: int in range(12):
		var source := {"hostile_source_id": "hostile:semantic-%d" % index, "attack_generation": 1, "action_id": "forge_titan.overheat_explosion", "runtime_frame": 35}
		var origin := {"x": 100.0 + index * 16.0, "y": 100.0}
		var fact := {"hostile_source_id": source.hostile_source_id, "attack_generation": 1, "shape": "circle", "origin": origin, "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": origin, "summon_slots": [], "radius": 8.0, "length": 0.0, "active_from_frame": 35, "active_through_frame": 36}
		result.semantics.zones.append(semantics._zone(source, fact, 0, 0.0, "fire", 0, 2, 60, 1.0, 0))
	var payloads := Payloads.new()
	payloads.configure("run-p15", 35)
	var request := {"kind": "death_pool", "run_id": "run-p15", "hostile_source_id": "hostile:dead-moth", "runtime_frame": 35, "attack_generation": 1, "position": {"x": 500.0, "y": 100.0}, "bounds": {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0}, "parameters": {"warning_frames": 30, "radius": 16.0, "damage": 8.0}}
	suite.assert_true(payloads.reserve_death_pool(request, 0).ok, "closed pending native death-pool fixture reserves no shared visible slot")
	result.payloads = payloads.snapshot()
	return result
