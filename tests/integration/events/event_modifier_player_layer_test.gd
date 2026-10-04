extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const SuiteScript := preload("res://tests/support/test_suite.gd")
const ATTACK_MODIFIERS := ["weapon_temper", "past_strength", "paradox_echo", "void_bargain_power", "heroic_assault"]
const GUARD_MODIFIERS := ["chronal_grace", "void_bargain_guard", "heroic_guard"]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = SuiteScript.new()
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	suite.assert_true(player.has_method("sync_event_temporary_modifiers"), "Player exposes the temporary event projection boundary")
	if player.has_method("sync_event_temporary_modifiers"):
		_test_all_authored_modifiers(player, suite)
		_test_projection_rejection(player, suite)
		_test_permanent_reward_and_restore(player, suite)
		_test_real_damage_and_regeneration(player, suite)
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _test_all_authored_modifiers(player: Node, suite: RefCounted) -> void:
	var baseline: Dictionary = player.call("reward_effect_snapshot")
	var attack := float(player.get("stats").get("attack"))
	var all_ids: Array = ATTACK_MODIFIERS + GUARD_MODIFIERS + ["tranquility"]
	for modifier_id: String in all_ids:
		var projection := [_entry(modifier_id, 1.25, "tx_%s" % modifier_id)]
		suite.assert_true(player.call("sync_event_temporary_modifiers", projection), "%s projects into real Player components" % modifier_id)
		suite.assert_close(player.call("get_effective_attack"), attack * (1.25 if ATTACK_MODIFIERS.has(modifier_id) else 1.0), "%s has its declared attack behavior" % modifier_id)
		suite.assert_close(player.call("get_damage_taken_multiplier"), 0.8 if GUARD_MODIFIERS.has(modifier_id) else 1.0, "%s has its declared mitigation behavior" % modifier_id)
		suite.assert_close(player.get_node("TimeManager").call("event_energy_regen_multiplier"), 1.25 if modifier_id == "tranquility" else 1.0, "%s has its declared regeneration behavior" % modifier_id)
		suite.assert_close(player.get_node("SwordWeapon").get("base_attack"), player.call("get_effective_attack"), "%s reaches the physical sword adapter" % modifier_id)
		suite.assert_equal(player.call("reward_effect_snapshot"), baseline, "%s leaves permanent reward state unchanged" % modifier_id)
		suite.assert_true(player.call("sync_event_temporary_modifiers", projection), "%s synchronizes idempotently" % modifier_id)
		suite.assert_close(player.call("get_effective_attack"), attack * (1.25 if ATTACK_MODIFIERS.has(modifier_id) else 1.0), "%s cannot double its magnitude on re-synchronization" % modifier_id)
		suite.assert_true(player.call("sync_event_temporary_modifiers", []), "%s expires through an empty authenticated projection" % modifier_id)
		suite.assert_close(player.call("get_effective_attack"), attack, "%s expiry restores permanent attack" % modifier_id)
		suite.assert_equal(player.call("event_temporary_modifier_snapshot"), [], "%s expiry retires its source" % modifier_id)
		suite.assert_true(player.call("sync_event_temporary_modifiers", projection), "%s can be acquired after expiry" % modifier_id)
	player.call("sync_event_temporary_modifiers", [])


func _test_projection_rejection(player: Node, suite: RefCounted) -> void:
	var valid := [_entry("weapon_temper", 1.1, "tx_temper"), _entry("heroic_guard", 1.2, "tx_guard")]
	suite.assert_true(player.call("sync_event_temporary_modifiers", valid), "independent event sources compose")
	var before: Array = player.call("event_temporary_modifier_snapshot")
	var attack: float = player.call("get_effective_attack")
	var malformed: Array = [
		[_entry("unknown", 1.1, "tx_unknown")],
		[_entry("weapon_temper", 1.1, "")],
		[_entry("weapon_temper", 1.1, "invalid source")],
		[_entry("weapon_temper", 0.0, "tx_zero")],
		[_entry("weapon_temper", -1.0, "tx_negative")],
		[_entry("weapon_temper", 10.1, "tx_large")],
		[_entry("weapon_temper", INF, "tx_infinite")],
		[_entry("weapon_temper", NAN, "tx_nan")],
		[_entry("weapon_temper", 1.1, "tx_a"), _entry("weapon_temper", 1.2, "tx_b")],
		[_entry("weapon_temper", 1.1, "tx_same"), _entry("heroic_guard", 1.2, "tx_same")],
		[{"modifier_id": "weapon_temper", "magnitude": 1.1, "source_transaction_id": "tx_extra", "effects": {"attack": 10000}}],
	]
	for candidate: Array in malformed:
		suite.assert_true(not player.call("sync_event_temporary_modifiers", candidate), "invalid event projection is rejected")
		suite.assert_equal(player.call("event_temporary_modifier_snapshot"), before, "rejection preserves all installed sources")
		suite.assert_close(player.call("get_effective_attack"), attack, "rejection cannot partially change attack")
	var copied: Array = player.call("event_temporary_modifier_snapshot")
	copied[0]["magnitude"] = 9.0
	suite.assert_equal(player.call("event_temporary_modifier_snapshot"), before, "projection snapshots cannot mutate installed sources")
	player.call("sync_event_temporary_modifiers", [])


func _test_permanent_reward_and_restore(player: Node, suite: RefCounted) -> void:
	var before: Dictionary = player.call("reward_effect_snapshot")
	var original_attack := float(player.get("stats").get("attack"))
	var projection := [_entry("past_strength", 1.15, "tx_past")]
	player.call("sync_event_temporary_modifiers", projection)
	var reward: Dictionary = player.call("apply_reward", {"id": "event_layer_reward", "category": "item", "effects": {"attack_multiplier": 1.2}})
	suite.assert_true(reward.get("ok", false), "permanent reward applies while an event effect is active")
	suite.assert_close(player.get("stats").get("attack"), original_attack, "permanent weapon reward keeps its established stat boundary")
	suite.assert_close(player.get("weapon_modifier_state").call("snapshot").get("weapon.damage"), 1.2, "permanent weapon multiplier remains in its own authority")
	suite.assert_close(player.call("get_effective_attack"), original_attack * 1.15, "event attack remains independent from the permanent weapon multiplier")
	suite.assert_true(player.call("restore_reward_effect_snapshot", before, false), "permanent reward snapshot restores under the event layer")
	suite.assert_true(player.call("sync_event_temporary_modifiers", projection), "Dungeon restore can project its authority after permanent restoration")
	suite.assert_close(player.call("get_effective_attack"), original_attack * 1.15, "restoration cannot compound the temporary multiplier")
	player.call("sync_event_temporary_modifiers", [])
	suite.assert_equal(player.call("reward_effect_snapshot"), before, "expiry preserves the restored permanent state")


func _test_real_damage_and_regeneration(player: Node, suite: RefCounted) -> void:
	var health := player.get_node("HealthComponent")
	var time := player.get_node("TimeManager")
	player.call("sync_event_temporary_modifiers", [_entry("heroic_guard", 1.2, "tx_real_guard")])
	var hp_before := float(health.get("current_hp"))
	var damage := DamageInfoScript.from_plan({
		"run_id": "standalone", "target_id": "player", "hostile_source_id": "enemy-event-layer",
		"attack_generation": 1, "action_token": 1, "amount": 24.0,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL, "can_crit": false,
		"tags": ["enemy:melee"],
	})
	var applied: float = health.call("take_damage", damage)
	suite.assert_close(applied, 20.0, "guard changes actual incoming hostile damage")
	suite.assert_close(health.get("current_hp"), hp_before - 20.0, "guard preserves the corresponding real HP")
	player.call("sync_event_temporary_modifiers", [_entry("tranquility", 1.25, "tx_real_tranquility")])
	time.set("energy", 50.0)
	var base_regen := float(time.get("energy_regen"))
	for frame: int in range(1, 61):
		suite.assert_true(time.call("advance_frame", frame), "regeneration advances through the authoritative frame clock")
	suite.assert_close(time.get("energy"), 50.0 + base_regen * 1.25, "tranquility affects real fixed-frame energy recovery")
	suite.assert_close(time.get("energy_regen"), base_regen, "tranquility never overwrites the permanent regeneration value")
	player.call("sync_event_temporary_modifiers", [])


func _entry(modifier_id: String, magnitude: float, source: String) -> Dictionary:
	return {"modifier_id": modifier_id, "magnitude": magnitude, "source_transaction_id": source}
