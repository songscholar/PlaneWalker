extends Node

const EffectHandlerCatalogScript := preload(
	"res://scripts/content/effects/effect_handler_catalog.gd"
)
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const ItemEffectScript := preload("res://scripts/items/item_effect.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const PlayerRewardEffectRuntimeScript := preload(
	"res://scripts/items/player_reward_effect_runtime.gd"
)
const StatsScript := preload("res://scripts/core/stats.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const TimeManagerScript := preload("res://scripts/time_system/time_manager.gd")
const WeaponModifierStateScript := preload(
	"res://scripts/combat/weapons/weapon_modifier_state.gd"
)

var _suite


class FakeLoadoutRuntime extends Node:
	var equipped_weapon_id: StringName = &"sword"


	func has_weapon(weapon_id: StringName) -> bool:
		return weapon_id == equipped_weapon_id


class FakeWeaponRuntime extends RefCounted:
	var modifiers: RefCounted
	var reject_apply: bool = false


	func _init(next_modifiers: RefCounted) -> void:
		modifiers = next_modifiers


	func apply_modifier(capability: StringName, value: Variant) -> bool:
		if reject_apply:
			return false
		return bool(modifiers.call("apply", capability, value))


	func snapshot() -> Dictionary:
		return {"modifiers": modifiers.call("snapshot")}


	func restore_snapshot(value: Dictionary) -> bool:
		if value.size() != 1 or not value.get("modifiers") is Dictionary:
			return false
		return bool(modifiers.call(
			"restore_snapshot",
			(value["modifiers"] as Dictionary).duplicate(true)
		))


class RewardSignalRecorder extends RefCounted:
	var healed_count: int = 0
	var energy_count: int = 0
	var player: Node
	var health: Node
	var nested_begin_accepted: bool = false

	func record_healed(_amount: float, _current_hp: float) -> void:
		healed_count += 1

	func record_energy(_current: float, _maximum: float) -> void:
		energy_count += 1
		if player != null and health != null:
			health.set("max_hp", 50.0)
			nested_begin_accepted = bool(player.call("reward_effect_begin_publication"))


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_health_reward_invulnerability_rolls_back_only_owned_tokens()
	_test_time_reward_snapshot_restores_energy_and_passives()
	_test_player_adapter_applies_all_domains_and_rejects_mismatch()
	_test_runtime_restores_full_player_snapshot_after_weapon_failure()
	_test_reward_feedback_waits_for_transaction_commit()
	_test_item_effect_and_player_entrypoints_return_transaction_results()
	_suite.finish(get_tree())


func _test_health_reward_invulnerability_rolls_back_only_owned_tokens() -> void:
	var health = HealthComponentScript.new()
	add_child(health)
	_suite.assert_true(
		health.call("acquire_invulnerability_source", &"external_guard"),
		"health fixture acquires an unrelated invulnerability source"
	)
	var before: Dictionary = health.call("reward_effect_snapshot")
	_suite.assert_true(
		bool(health.call("apply_reward_invulnerability", 1.0)),
		"reward invulnerability starts"
	)
	_suite.assert_true(
		health.call("reward_effect_snapshot") != before,
		"reward invulnerability changes its stable reward snapshot"
	)
	_suite.assert_true(
		bool(health.call("restore_reward_effect_snapshot", before.duplicate(true))),
		"health reward snapshot restores"
	)
	_suite.assert_equal(
		health.call("reward_effect_snapshot"),
		before,
		"health restore is byte-equivalent"
	)
	_suite.assert_true(bool(health.get("invulnerable")), "external source survives reward rollback")
	_suite.assert_true(
		health.call("release_invulnerability_source", &"external_guard"),
		"external source remains independently releasable"
	)
	_suite.assert_true(not bool(health.get("invulnerable")), "reward timer was cancelled by rollback")
	health.queue_free()


func _test_time_reward_snapshot_restores_energy_and_passives() -> void:
	var time_manager = TimeManagerScript.new()
	add_child(time_manager)
	time_manager.set("energy", 42.0)
	time_manager.set("time_stop_duration_bonus", 0.5)
	time_manager.set("rewind_echo_enabled", true)
	time_manager.set("time_rift_radius_bonus", 12.0)
	time_manager.set("low_energy_threshold", 25.0)
	var before: Dictionary = time_manager.call("reward_effect_snapshot")
	time_manager.set("energy", 3.0)
	time_manager.set("max_energy", 180.0)
	time_manager.set("time_stop_duration_bonus", 9.0)
	time_manager.set("rewind_echo_enabled", false)
	time_manager.set("time_rift_radius_bonus", 99.0)
	time_manager.set("low_energy_threshold", 80.0)
	_suite.assert_true(
		bool(time_manager.call("restore_reward_effect_snapshot", before.duplicate(true))),
		"time reward snapshot restores"
	)
	_suite.assert_equal(
		time_manager.call("reward_effect_snapshot"),
		before,
		"time restore covers energy, maximum, revision, and every passive"
	)
	var invalid := before.duplicate(true)
	invalid["time_stop_cost_multiplier"] = NAN
	_suite.assert_true(
		not bool(time_manager.call("restore_reward_effect_snapshot", invalid)),
		"time restore rejects non-finite modifiers"
	)
	_suite.assert_equal(
		time_manager.call("reward_effect_snapshot"),
		before,
		"rejected time restore is mutation-free"
	)
	time_manager.queue_free()


func _test_player_adapter_applies_all_domains_and_rejects_mismatch() -> void:
	var fixture := _player_fixture()
	var player: Node = fixture["player"]
	var snapshot: Dictionary = player.call("reward_effect_snapshot")
	var leaked := snapshot.duplicate(true)
	(leaked["stats"] as Dictionary)["max_hp"] = 9999.0
	_suite.assert_equal(
		player.call("reward_effect_snapshot"),
		snapshot,
		"player reward snapshot is deeply isolated"
	)
	for effect_case: Dictionary in [
		{"effect_id": "max_hp_bonus", "value": 20.0, "domain": "stats"},
		{"effect_id": "healing_multiplier", "value": 0.5, "domain": "health"},
		{"effect_id": "time_stop_duration_bonus", "value": 0.75, "domain": "time"},
		{"effect_id": "attack_multiplier", "value": 1.25, "domain": "weapon"},
		{"effect_id": "dash_invulnerable_bonus", "value": 0.08, "domain": "character"},
		{"effect_id": "time_energy_restore", "value": 10.0, "domain": "trigger"},
	]:
		var operation := _operation(effect_case["effect_id"], effect_case["value"])
		var result: Dictionary = player.call("reward_effect_apply_operation", operation)
		_suite.assert_true(
			bool(result.get("ok", false)),
			"%s operation applies through the real Player adapter" % effect_case["domain"]
		)
	var before_mismatch: Dictionary = player.call("reward_effect_snapshot")
	var mismatch := _operation("max_hp_bonus", 5.0)
	mismatch["runtime_domain"] = "trigger"
	var rejected: Dictionary = player.call("reward_effect_apply_operation", mismatch)
	_suite.assert_true(not bool(rejected.get("ok", false)), "domain mismatch is rejected")
	_suite.assert_equal(
		player.call("reward_effect_snapshot"),
		before_mismatch,
		"rejected operation is mutation-free"
	)
	_free_player_fixture(fixture)


func _test_runtime_restores_full_player_snapshot_after_weapon_failure() -> void:
	var fixture := _player_fixture()
	var player: Node = fixture["player"]
	var runtime = PlayerRewardEffectRuntimeScript.new()
	var before: Dictionary = player.call("reward_effect_snapshot")
	var prepared: Dictionary = runtime.call("prepare", {
		"id": "adapter_atomic_failure",
		"category": "item",
		"effects": {
			"max_hp_bonus": 20.0,
			"attack_multiplier": 1.25,
		},
	}, before)
	_suite.assert_true(bool(prepared.get("ok", false)), "atomic failure plan prepares")
	(fixture["weapon_runtime"] as FakeWeaponRuntime).reject_apply = true
	var result: Dictionary = runtime.call(
		"commit",
		(prepared.get("plan", {}) as Dictionary).duplicate(true),
		player
	)
	_suite.assert_equal(
		StringName(str(result.get("code", ""))),
		&"COMMIT_FAILED_ROLLED_BACK",
		"weapon rejection reports a successful full rollback"
	)
	_suite.assert_equal(
		player.call("reward_effect_snapshot"),
		before,
		"weapon failure restores stats and every other Player reward domain"
	)
	_free_player_fixture(fixture)


func _test_reward_feedback_waits_for_transaction_commit() -> void:
	var fixture := _player_fixture()
	var player: Node = fixture["player"]
	var health: Node = fixture["health"]
	var time_manager: Node = fixture["time_manager"]
	var recorder := RewardSignalRecorder.new()
	recorder.player = player
	recorder.health = health
	health.set("current_hp", 50.0)
	time_manager.set("energy", 20.0)
	health.connect("healed", recorder.record_healed)
	time_manager.connect("energy_changed", recorder.record_energy)

	_suite.assert_true(bool(player.call("reward_effect_begin_publication")), "reward feedback transaction begins")
	_suite.assert_true(bool((player.call("reward_effect_apply_operation", _operation("heal", 15.0)) as Dictionary).get("ok", false)), "heal trigger commits state")
	_suite.assert_true(bool((player.call("reward_effect_apply_operation", _operation("time_energy_restore", 10.0)) as Dictionary).get("ok", false)), "energy trigger commits state")
	_suite.assert_equal(recorder.healed_count, 0, "heal feedback is buffered before authority commit")
	_suite.assert_equal(recorder.energy_count, 0, "energy feedback is buffered before authority commit")
	_suite.assert_true(bool(player.call("reward_effect_publication_can_commit")), "buffered feedback preflight passes")
	_suite.assert_true(bool(player.call("reward_effect_commit_publication")), "buffered feedback commits")
	_suite.assert_equal(recorder.healed_count, 1, "heal feedback publishes once after commit")
	_suite.assert_equal(recorder.energy_count, 1, "energy feedback publishes once after commit")
	_suite.assert_true(not recorder.nested_begin_accepted, "feedback publication rejects reentrant reward transactions")

	health.set("max_hp", 100.0)
	health.set("current_hp", 50.0)
	time_manager.set("energy", 20.0)
	var before: Dictionary = player.call("reward_effect_snapshot")
	_suite.assert_true(bool(player.call("reward_effect_begin_publication")), "rollback feedback transaction begins")
	player.call("reward_effect_apply_operation", _operation("heal", 15.0))
	player.call("reward_effect_apply_operation", _operation("time_energy_restore", 10.0))
	_suite.assert_true(bool(player.call("restore_reward_effect_snapshot", before.duplicate(true))), "reward state restores while feedback remains buffered")
	_suite.assert_true(bool(player.call("reward_effect_rollback_publication")), "buffered feedback rolls back")
	_suite.assert_equal(player.call("reward_effect_snapshot"), before, "feedback rollback preserves exact restored state")
	_suite.assert_equal(recorder.healed_count, 1, "rolled-back heal feedback is never published")
	_suite.assert_equal(recorder.energy_count, 1, "rolled-back energy feedback is never published")

	if health.is_connected("healed", recorder.record_healed):
		health.disconnect("healed", recorder.record_healed)
	if time_manager.is_connected("energy_changed", recorder.record_energy):
		time_manager.disconnect("energy_changed", recorder.record_energy)
	_free_player_fixture(fixture)


func _test_item_effect_and_player_entrypoints_return_transaction_results() -> void:
	var fixture := _player_fixture()
	var player: Node = fixture["player"]
	var item_result: Dictionary = ItemEffectScript.apply_to_player(
		player,
		{"max_hp_bonus": 10.0, "time_stop_duration_bonus": 0.25},
		"adapter_item",
		"item"
	)
	_suite.assert_true(bool(item_result.get("ok", false)), "ItemEffect returns a commit result")
	var reward_result: Dictionary = player.call("apply_reward", {
		"id": "adapter_reward",
		"category": "item",
		"effects": {"dash_invulnerable_bonus": 0.05},
	})
	_suite.assert_true(bool(reward_result.get("ok", false)), "apply_reward returns a transaction result")
	var curse_result: Dictionary = player.call("apply_curse", {
		"id": "adapter_curse",
		"category": "curse",
		"effects": {"healing_multiplier": 0.5},
	})
	_suite.assert_true(bool(curse_result.get("ok", false)), "apply_curse returns a transaction result")
	_free_player_fixture(fixture)


func _operation(effect_id: String, value: Variant) -> Dictionary:
	var descriptor: Dictionary = EffectHandlerCatalogScript.new().effect_descriptor(
		StringName(effect_id)
	)
	return {
		"effect_id": effect_id,
		"runtime_domain": str(descriptor.get("runtime_domain", "")),
		"value": value,
		"stack_rule": str(descriptor.get("stack_rule", "")),
		"weapon_capabilities": (
			descriptor.get("weapon_capabilities", []) as Array
		).duplicate(true),
	}


func _player_fixture() -> Dictionary:
	var player = PlayerControllerScript.new()
	player.stats = StatsScript.new()
	var health = HealthComponentScript.new()
	add_child(health)
	health.call("configure_from_stats", player.stats)
	var time_manager = TimeManagerScript.new()
	add_child(time_manager)
	time_manager.call("configure_from_stats", player.stats)
	time_manager.set("energy", 50.0)
	var loadout := FakeLoadoutRuntime.new()
	var modifiers = WeaponModifierStateScript.new()
	var capabilities := PackedStringArray([
		"weapon.attack_speed",
		"weapon.damage",
	])
	var bounds := {
		"weapon.attack_speed": {"minimum": 0.2, "maximum": 5.0},
		"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
	}
	_suite.assert_true(modifiers.configure(capabilities, bounds), "adapter modifier fixture configures")
	var weapon_runtime := FakeWeaponRuntime.new(modifiers)
	player.health = health
	player.time_manager = time_manager
	player.loadout_runtime = loadout
	player.weapon_modifier_state = modifiers
	player.weapon_runtime = weapon_runtime
	return {
		"player": player,
		"health": health,
		"time_manager": time_manager,
		"loadout": loadout,
		"modifiers": modifiers,
		"weapon_runtime": weapon_runtime,
	}


func _free_player_fixture(fixture: Dictionary) -> void:
	(fixture["health"] as Node).queue_free()
	(fixture["time_manager"] as Node).queue_free()
	(fixture["loadout"] as Node).free()
	(fixture["player"] as Node).free()
