extends Node

const ItemEffectScript := preload("res://scripts/items/item_effect.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const ITEM_EFFECT_SOURCE_PATH := "res://scripts/items/item_effect.gd"
const PLAYER_CONTROLLER_SOURCE_PATH := "res://scripts/player/player_controller.gd"

var _suite


class CapabilityRoutePlayer extends Node:
	var equipped_weapon_id: StringName = &"sword"
	var routed_effects: Array[Dictionary] = []


	func apply_weapon_capability_effect(
		capability: StringName,
		value: Variant,
		base_value: float,
		stack_rule: StringName,
		required_weapon_id: StringName
	) -> bool:
		if required_weapon_id != equipped_weapon_id:
			return false
		routed_effects.append({
			"capability": str(capability),
			"value": value,
			"base_value": base_value,
			"stack_rule": str(stack_rule),
			"weapon_id": str(required_weapon_id),
		})
		return true


class PlayerWithoutWeaponCapabilityApi extends Node:
	var stats_sync_count: int = 0


	func _apply_stats_to_components(_preserve_current: bool) -> void:
		stats_sync_count += 1


class FakeLoadoutRuntime extends Node:
	var equipped_weapon_id: StringName = &"sword"


	func has_weapon(id: StringName) -> bool:
		return id != &"" and id == equipped_weapon_id


class FakeWeaponRuntime extends RefCounted:
	var modifiers: RefCounted


	func _init(next_modifiers: RefCounted) -> void:
		modifiers = next_modifiers


	func apply_modifier(capability: StringName, value: Variant) -> bool:
		return bool(modifiers.call("apply", capability, value))


class FailingSyncWeaponRuntime extends RefCounted:
	var modifiers: RefCounted
	var fail_on_capability: StringName
	var synchronized_values: Dictionary = {}


	func _init(next_modifiers: RefCounted, next_fail_on_capability: StringName) -> void:
		modifiers = next_modifiers
		fail_on_capability = next_fail_on_capability


	func apply_modifier(capability: StringName, value: Variant) -> bool:
		if capability == fail_on_capability:
			return false
		if not bool(modifiers.call("apply", capability, value)):
			return false
		synchronized_values[str(capability)] = float(value)
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_five_weapon_effects_route_to_capabilities()
	_test_stack_rules_and_bounds_are_atomic()
	_test_multiple_capability_routes_are_atomic()
	_test_runtime_sync_failure_rolls_back_batch()
	_test_weapon_capability_ownership_tracks_equipment()
	_test_missing_player_api_fails_safely()
	_test_legacy_weapon_write_apis_are_removed()
	_suite.finish(get_tree())


func _test_five_weapon_effects_route_to_capabilities() -> void:
	var cases: Array[Dictionary] = [
		{
			"weapon_id": &"sword",
			"effects": {"combo_finisher_multiplier_bonus": 0.35},
			"expected": {
				"capability": "weapon.combo_finisher_damage",
				"value": 0.35,
				"base_value": 0.0,
				"stack_rule": "add",
				"weapon_id": "sword",
			},
		},
		{
			"weapon_id": &"bow",
			"effects": {"bow_charge_rate_bonus": 0.25},
			"expected": {
				"capability": "weapon.charge_rate",
				"value": 0.25,
				"base_value": 1.0,
				"stack_rule": "add",
				"weapon_id": "bow",
			},
		},
		{
			"weapon_id": &"gun",
			"effects": {"attack_multiplier": 1.2},
			"expected": {
				"capability": "weapon.damage",
				"value": 1.2,
				"base_value": 1.0,
				"stack_rule": "multiply",
				"weapon_id": "gun",
			},
		},
		{
			"weapon_id": &"staff",
			"effects": {"attack_speed_multiplier": 1.15},
			"expected": {
				"capability": "weapon.attack_speed",
				"value": 1.15,
				"base_value": 1.0,
				"stack_rule": "multiply",
				"weapon_id": "staff",
			},
		},
		{
			"weapon_id": &"gauntlets",
			"effects": {"attack_multiplier": 1.25},
			"expected": {
				"capability": "weapon.damage",
				"value": 1.25,
				"base_value": 1.0,
				"stack_rule": "multiply",
				"weapon_id": "gauntlets",
			},
		},
	]
	for case: Dictionary in cases:
		var player := CapabilityRoutePlayer.new()
		player.equipped_weapon_id = case["weapon_id"]
		ItemEffectScript._apply_weapon_effects(player, case["effects"])
		_suite.assert_equal(
			player.routed_effects,
			[case["expected"]],
			"%s weapon effects route through their declared capability" % str(case["weapon_id"])
		)
		player.free()


func _test_stack_rules_and_bounds_are_atomic() -> void:
	var fixture := _player_fixture(
		&"sword",
		PackedStringArray([
			"weapon.combo_finisher_damage",
			"weapon.damage",
			"weapon.heavy_damage",
			"weapon.heavy_execute_threshold",
		]),
		{
			"weapon.combo_finisher_damage": {"minimum": 0.0, "maximum": 10.0},
			"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
			"weapon.heavy_damage": {"minimum": 0.0, "maximum": 10.0},
			"weapon.heavy_execute_threshold": {"minimum": 0.0, "maximum": 1.0},
		}
	)
	var player: Node = fixture["player"]
	var modifiers: RefCounted = fixture["modifiers"]
	_suite.assert_true(
		player.call("apply_weapon_capability_effect", &"weapon.damage", 1.5, 1.0, &"multiply", &"sword"),
		"first multiplier applies"
	)
	_suite.assert_true(
		player.call("apply_weapon_capability_effect", &"weapon.damage", 1.2, 1.0, &"multiply", &"sword"),
		"second multiplier stacks"
	)
	_suite.assert_true(
		player.call("apply_weapon_capability_effect", &"weapon.combo_finisher_damage", 0.35, 0.0, &"add", &"sword"),
		"first additive bonus applies"
	)
	_suite.assert_true(
		player.call("apply_weapon_capability_effect", &"weapon.combo_finisher_damage", 0.20, 0.0, &"add", &"sword"),
		"second additive bonus stacks"
	)
	_suite.assert_true(
		player.call("apply_weapon_capability_effect", &"weapon.heavy_execute_threshold", 0.3, 0.3, &"replace", &"sword"),
		"replace rule applies"
	)
	var before_rejection: Dictionary = modifiers.call("snapshot")
	_suite.assert_true(
		not player.call("apply_weapon_capability_effect", &"weapon.damage", 20.0, 1.0, &"multiply", &"sword"),
		"combined values outside capability bounds are rejected"
	)
	_suite.assert_equal(modifiers.call("snapshot"), before_rejection, "range rejection is atomic")
	_suite.assert_true(
		not player.call("apply_weapon_capability_effect", &"weapon.heavy_damage", 1.0, -1.0, &"add", &"sword"),
		"out-of-range capability bases are rejected even when the combined value would be valid"
	)
	_suite.assert_equal(modifiers.call("snapshot"), before_rejection, "base rejection is atomic")
	_suite.assert_close(float(before_rejection.get("weapon.damage", NAN)), 1.8, "multipliers compose multiplicatively")
	_suite.assert_close(
		float(before_rejection.get("weapon.combo_finisher_damage", NAN)),
		0.55,
		"bonuses compose additively"
	)
	_suite.assert_close(
		float(before_rejection.get("weapon.heavy_execute_threshold", NAN)),
		0.3,
		"replacement effects store the normalized value"
	)
	_free_player_fixture(fixture)


func _test_multiple_capability_routes_are_atomic() -> void:
	var fixture := _player_fixture(
		&"sword",
		PackedStringArray(["weapon.combo_finisher_damage", "weapon.damage"]),
		{
			"weapon.combo_finisher_damage": {"minimum": 0.0, "maximum": 10.0},
			"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
		}
	)
	var player: Node = fixture["player"]
	var modifiers: RefCounted = fixture["modifiers"]
	_suite.assert_true(
		player.call("apply_weapon_capability_effect", &"weapon.combo_finisher_damage", 1.0, 0.0, &"add", &"sword"),
		"atomic multi-route fixture establishes a prior combo bonus"
	)
	var before: Dictionary = modifiers.call("snapshot")
	ItemEffectScript._apply_weapon_effects(player, {
		"attack_multiplier": 1.2,
		"combo_finisher_multiplier_bonus": 10.0,
	})
	_suite.assert_equal(
		modifiers.call("snapshot"),
		before,
		"a later invalid capability route rolls the entire item effect batch back"
	)
	_free_player_fixture(fixture)


func _test_runtime_sync_failure_rolls_back_batch() -> void:
	var fixture := _player_fixture(
		&"sword",
		PackedStringArray(["weapon.damage", "weapon.combo_finisher_damage"]),
		{
			"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
			"weapon.combo_finisher_damage": {"minimum": 0.0, "maximum": 10.0},
		}
	)
	var player: Node = fixture["player"]
	var modifiers: RefCounted = fixture["modifiers"]
	_suite.assert_true(
		modifiers.call("apply", &"weapon.damage", 1.1),
		"runtime-sync rollback fixture seeds a prior modifier"
	)
	var runtime := FailingSyncWeaponRuntime.new(modifiers, &"weapon.combo_finisher_damage")
	player.set("weapon_runtime", runtime)
	var before: Dictionary = modifiers.call("snapshot")
	_suite.assert_true(
		not player.call("apply_weapon_capability_effects", [
			{
				"capability": "weapon.damage",
				"value": 1.2,
				"base_value": 1.0,
				"stack_rule": "multiply",
				"weapon_id": "sword",
			},
			{
				"capability": "weapon.combo_finisher_damage",
				"value": 0.35,
				"base_value": 0.0,
				"stack_rule": "add",
				"weapon_id": "sword",
			},
		]),
		"a runtime synchronization rejection fails the whole item batch"
	)
	_suite.assert_equal(
		modifiers.call("snapshot"),
		before,
		"runtime synchronization failure restores the exact modifier snapshot"
	)
	_suite.assert_close(
		float(runtime.synchronized_values.get("weapon.damage", NAN)),
		1.1,
		"runtime synchronization side effects are compensated to the prior value"
	)
	_free_player_fixture(fixture)


func _test_weapon_capability_ownership_tracks_equipment() -> void:
	var fixture := _player_fixture(
		&"sword",
		PackedStringArray(["weapon.combo_finisher_damage", "weapon.damage"]),
		{
			"weapon.combo_finisher_damage": {"minimum": 0.0, "maximum": 10.0},
			"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
		}
	)
	var player: Node = fixture["player"]
	var loadout: Node = fixture["loadout"]
	var modifiers: RefCounted = fixture["modifiers"]
	ItemEffectScript._apply_weapon_effects(player, {"combo_finisher_multiplier_bonus": 0.35})
	var sword_snapshot: Dictionary = modifiers.call("snapshot")
	_suite.assert_close(
		float(sword_snapshot.get("weapon.combo_finisher_damage", NAN)),
		0.35,
		"equipped Sword owns its capability bonus"
	)
	loadout.equipped_weapon_id = &"bow"
	ItemEffectScript._apply_weapon_effects(player, {"combo_finisher_multiplier_bonus": 0.20})
	_suite.assert_equal(
		modifiers.call("snapshot"),
		sword_snapshot,
		"switching away prevents stale Sword capability mutation"
	)
	ItemEffectScript._apply_weapon_effects(player, {"attack_multiplier": 1.25})
	_suite.assert_close(
		float((modifiers.call("snapshot") as Dictionary).get("weapon.damage", NAN)),
		1.25,
		"generic weapon effects follow the newly equipped weapon"
	)
	_free_player_fixture(fixture)


func _test_missing_player_api_fails_safely() -> void:
	var player := PlayerWithoutWeaponCapabilityApi.new()
	ItemEffectScript.apply_to_player(player, {"bow_charge_rate_bonus": 0.25})
	_suite.assert_equal(player.stats_sync_count, 1, "missing capability API leaves the remaining item pipeline usable")
	player.free()


func _test_legacy_weapon_write_apis_are_removed() -> void:
	var item_source := FileAccess.get_file_as_string(ITEM_EFFECT_SOURCE_PATH)
	_suite.assert_true(not item_source.is_empty(), "item effect source is readable")
	_suite.assert_true(not item_source.contains("LEGACY_"), "item effects no longer maintain hard-coded legacy maps")
	_suite.assert_true(
		not item_source.contains("\"apply_weapon_effect\"")
		and not item_source.contains(".apply_weapon_effect("),
		"item effects no longer call the legacy weapon-effect API"
	)
	var player_source := FileAccess.get_file_as_string(PLAYER_CONTROLLER_SOURCE_PATH)
	_suite.assert_true(not player_source.is_empty(), "player controller source is readable")
	_suite.assert_true(
		not player_source.contains("func apply_weapon_effect("),
		"player controller removes the legacy weapon-effect API"
	)
	for direct_write: String in [
		"sword_weapon.combo_finisher_multiplier_bonus",
		"sword_weapon.heavy_damage_multiplier_bonus",
		"sword_weapon.heavy_execute_multiplier_bonus",
		"sword_weapon.heavy_execute_threshold",
		"sword_weapon.low_hp_damage_multiplier_bonus",
		"bow_weapon.charge_rate_bonus",
		"bow_weapon.full_charge_damage_multiplier_bonus",
		"bow_weapon.pierce_bonus",
	]:
		_suite.assert_true(
			not player_source.contains(direct_write),
			"Player does not write presentation-owned weapon fields: %s" % direct_write
		)


func _player_fixture(
	weapon_id: StringName,
	capabilities: PackedStringArray,
	bounds: Dictionary
) -> Dictionary:
	var player = PlayerControllerScript.new()
	var loadout := FakeLoadoutRuntime.new()
	loadout.equipped_weapon_id = weapon_id
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(modifiers.configure(capabilities, bounds), "modifier fixture configures")
	player.loadout_runtime = loadout
	player.weapon_modifier_state = modifiers
	player.weapon_runtime = FakeWeaponRuntime.new(modifiers)
	return {"player": player, "loadout": loadout, "modifiers": modifiers}


func _free_player_fixture(fixture: Dictionary) -> void:
	(fixture["loadout"] as Node).free()
	(fixture["player"] as Node).free()
