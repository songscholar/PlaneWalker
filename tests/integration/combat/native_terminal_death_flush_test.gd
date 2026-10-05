extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"

const NativeDriver := preload("res://scripts/dungeon/native_launch_encounter_driver.gd")
const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")


func _run() -> void:
	suite = Suite.new()
	var f := await _fixture("void_spore", 2)
	# This synthetic encounter isolates two authentic same-frame terminal callbacks.
	var definition := {"id": "encounter_profile_forest_adapter_v1.multi_terminal_fixture", "floor_id": "floor_void_forest", "recipe_id": "multi_terminal_fixture", "room_type": "elite", "waves": [{"id": "terminal_wave", "delay_frames": 0, "warning_frames": 23, "spawns": [
		{"id": "terminal_0", "enemy_id": "void_spore", "spawn_slot_id": "elite_primary", "spawn_offset": {"x": -64.0, "y": 0.0}, "elite": true, "affix_ids": ["frenzy"], "mechanism_ids": []},
		{"id": "terminal_1", "enemy_id": "void_spore", "spawn_slot_id": "elite_primary", "spawn_offset": {"x": 64.0, "y": 0.0}, "elite": true, "affix_ids": ["frenzy"], "mechanism_ids": []},
	]}]}
	var encounter := Encounter.new()
	suite.assert_true(encounter.configure(definition, {"run_id": "run-summon-lifecycle", "room_id": "terminal-room", "runtime_frame": 0, "encounter_generation": 1}).ok, "same-frame terminal fixture owns real Encounter ledger")
	for frame: int in range(1, 25):
		suite.assert_true(encounter.advance_frame(frame).ok and _step(f), "same-frame fixture aligns authentic shared native clocks")
	var actors := {}
	for index: int in range(2):
		var owner: Node2D = f.actors[index]
		actors[str(owner.hostile_source_id)] = owner
		suite.assert_true(encounter.register_spawned("terminal_%d" % index, str(owner.hostile_source_id)), "same-frame fixture registers genuine principal source")
	var driver := NativeDriver.new()
	driver.set("_player", f.player)
	driver.set("_bridge", f.bridge)
	driver.set("_effects", f.effects)
	driver.set("_encounter", encounter)
	driver.set("_definition", definition)
	driver.set("_actors", actors)
	for owner: Node2D in f.actors:
		owner.hostile_final_death.connect(driver._on_actor_final_death)
	var before: Array = f.actors.map(func(owner: Node2D): return owner.launch_transaction_snapshot())
	var effects_before: Dictionary = f.effects.launch_transaction_snapshot()
	var frame := int(f.frame) + 1
	suite.assert_true(encounter.advance_frame(frame).ok, "explicit prerequisite Encounter clock enters terminal collision frame")
	var refused: Dictionary = f.bridge.begin_frame(frame)
	suite.assert_true(not refused.is_empty() and f.bridge.prepare_frame(refused), "actual shared Bridge stages refused terminal frame")
	_apply_terminal_hits(f)
	suite.assert_true(driver.get("_terminal_death_queue").is_empty(), "unpublished Health cannot queue terminal work")
	suite.assert_true(f.bridge.rollback_frame(refused), "refused terminal frame compensates both authentic body receipts")
	suite.assert_equal(f.effects.launch_transaction_snapshot(), effects_before, "refused frame leaves no child reservations or effects")
	for index: int in range(2):
		suite.assert_equal(f.actors[index].launch_transaction_snapshot(), before[index], "refused frame restores complete principal and health state")
	var accepted: Dictionary = f.bridge.begin_frame(frame)
	suite.assert_true(not accepted.is_empty() and f.bridge.prepare_frame(accepted), "exact retry stages original terminal collision frame")
	_apply_terminal_hits(f)
	suite.assert_true(_publish(f.bridge, accepted), "accepted shared frame seals and publishes both genuine terminal deaths")
	f.frame = frame
	suite.assert_true(driver.get("_terminal_death_queue").size() == 2 and encounter.snapshot().roster.size() == 2 and encounter.snapshot().defeat_ledger.is_empty(), "two same-frame terminal deaths hold original principal roster until stable Driver flush")
	suite.assert_true(driver._flush_terminal_deaths(), "stable native boundary flushes both canonical terminal child reservations")
	var after: Dictionary = encounter.snapshot()
	suite.assert_true(driver.get("_terminal_death_queue").is_empty() and driver.get("_actors").is_empty() and after.defeat_ledger.size() == 2 and f.effects.summon_snapshot().rows.size() == 4 and after.pending_work.size() == 4, "same-frame terminal flush retains exactly four unrewarded child work records before principal retirement")
	suite.assert_true(not encounter.can_complete() and after.status != "COMPLETE", "room settlement waits for all orphan child work")
	suite.assert_true(driver._flush_terminal_deaths() and f.effects.summon_snapshot().rows.size() == 4, "duplicate stable flush cannot reserve additional children")
	driver.free()
	await _dispose(f)
	suite.finish(get_tree())


func _apply_terminal_hits(f: Dictionary) -> void:
	for owner: Node2D in f.actors:
		var source := str(owner.hostile_source_id)
		var hit := Damage.from_plan({"run_id": "run-summon-lifecycle", "target_id": source, "hostile_source_id": "domain:sealed-terminal-fixture", "attack_generation": 7, "action_token": 7, "amount": 10000.0, "damage_type": Damage.DamageType.VOID, "tags": [], "can_crit": false})
		suite.assert_true(owner.get_node("HealthComponent").take_damage(hit) > 0.0 and owner.get_node("HealthComponent").dead, "explicit native collision fixture settles genuine lethal body and Health receipts")
