extends Node

const ItemEffectScript := preload("res://scripts/items/item_effect.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const ITEM_EFFECT_SOURCE_PATH := "res://scripts/items/item_effect.gd"
const PLAYER_CONTROLLER_SOURCE_PATH := "res://scripts/player/player_controller.gd"

const LEGACY_WEAPON_EFFECTS := {
	"combo_finisher_multiplier_bonus": 0.35,
	"heavy_damage_multiplier_bonus": 0.4,
	"heavy_execute_multiplier_bonus": 0.5,
	"heavy_execute_threshold": 0.3,
	"low_hp_damage_multiplier_bonus": 0.45,
	"bow_charge_rate_bonus": 0.25,
	"bow_full_charge_damage_multiplier_bonus": 0.35,
	"bow_pierce_bonus": 1,
}

var _suite


class WeaponEffectPlayer extends Node:
	var routed_effects: Dictionary = {}
	var routed_modifier_bonuses: Array[Dictionary] = []
	var modifier_values: Dictionary = {}
	var stats_sync_count: int = 0


	func apply_weapon_effect(effect_id: StringName, value: Variant) -> bool:
		routed_effects[str(effect_id)] = value
		return true


	func apply_weapon_modifier_bonus(
		capability: StringName,
		value: Variant,
		base_value: float,
		required_weapon_id: StringName = &""
	) -> bool:
		var capability_id := str(capability)
		routed_modifier_bonuses.append({
			"capability": capability_id,
			"value": value,
			"base_value": base_value,
			"weapon_id": str(required_weapon_id),
		})
		modifier_values[capability_id] = (
			float(modifier_values.get(capability_id, base_value)) + float(value)
		)
		return true


	func _apply_stats_to_components(_preserve_current: bool) -> void:
		stats_sync_count += 1


class PlayerWithoutWeaponEffectApi extends Node:
	var stats_sync_count: int = 0


	func _apply_stats_to_components(_preserve_current: bool) -> void:
		stats_sync_count += 1


class FakeLoadoutRuntime extends Node:
	var equipped_weapon_id: StringName = &"sword"


	func has_weapon(id: StringName) -> bool:
		return id != &"" and id == equipped_weapon_id


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_legacy_weapon_effects_use_player_api()
	_test_bow_add_stack_effects_accumulate_capabilities()
	_test_player_bow_capability_bridge_accumulates()
	_test_player_rejects_bow_capabilities_for_non_bow_loadout()
	_test_missing_player_api_fails_safely()
	_test_item_effect_does_not_reach_weapon_nodes()
	_suite.finish(get_tree())


func _test_legacy_weapon_effects_use_player_api() -> void:
	var player := WeaponEffectPlayer.new()
	ItemEffectScript.apply_to_player(player, LEGACY_WEAPON_EFFECTS)
	_suite.assert_equal(
		player.routed_effects,
		{
			"combo_finisher_multiplier_bonus": 0.35,
			"heavy_damage_multiplier_bonus": 0.4,
			"heavy_execute_multiplier_bonus": 0.5,
			"heavy_execute_threshold": 0.3,
			"low_hp_damage_multiplier_bonus": 0.45,
		},
		"legacy sword reward hooks retain the player weapon-effect API"
	)
	_suite.assert_equal(
		player.routed_modifier_bonuses,
		[
			{"capability": "weapon.charge_rate", "value": 0.25, "base_value": 1.0, "weapon_id": "bow"},
			{"capability": "weapon.full_charge_damage", "value": 0.35, "base_value": 1.0, "weapon_id": "bow"},
			{"capability": "weapon.pierce", "value": 1, "base_value": 0.0, "weapon_id": "bow"},
		],
		"legacy bow effects map to declared modifier capabilities"
	)
	_suite.assert_equal(player.stats_sync_count, 1, "weapon effects retain component stat synchronization")
	player.free()


func _test_bow_add_stack_effects_accumulate_capabilities() -> void:
	var player := WeaponEffectPlayer.new()
	ItemEffectScript.apply_to_player(player, {
		"bow_charge_rate_bonus": 0.25,
		"bow_full_charge_damage_multiplier_bonus": 0.35,
		"bow_pierce_bonus": 1,
	})
	ItemEffectScript.apply_to_player(player, {
		"bow_charge_rate_bonus": 0.15,
		"bow_full_charge_damage_multiplier_bonus": 0.20,
		"bow_pierce_bonus": 2,
	})
	_suite.assert_equal(
		player.modifier_values,
		{
			"weapon.charge_rate": 1.4,
			"weapon.full_charge_damage": 1.55,
			"weapon.pierce": 3.0,
		},
		"multiple additive bow items preserve every bonus instead of replacing the prior item"
	)
	player.free()


func _test_player_bow_capability_bridge_accumulates() -> void:
	var player = PlayerControllerScript.new()
	var loadout := FakeLoadoutRuntime.new()
	loadout.equipped_weapon_id = &"bow"
	player.loadout_runtime = loadout
	var capabilities := PackedStringArray([
		"weapon.charge_rate",
		"weapon.full_charge_damage",
		"weapon.pierce",
	])
	var bounds: Dictionary = player.call("_modifier_bounds_for", capabilities)
	_suite.assert_equal(
		bounds,
		{
			"weapon.charge_rate": {"minimum": 0.0, "maximum": 6.0},
			"weapon.full_charge_damage": {"minimum": 0.0, "maximum": 11.0},
			"weapon.pierce": {"minimum": 0.0, "maximum": 20.0},
		},
		"player declares bounds for every migrated bow capability"
	)
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(capabilities, bounds),
		"player bow capability bridge fixture configures"
	)
	player.weapon_modifier_state = modifiers
	for _item_index: int in range(2):
		ItemEffectScript._apply_weapon_effects(player, {
			"bow_charge_rate_bonus": 0.25,
			"bow_full_charge_damage_multiplier_bonus": 0.35,
			"bow_pierce_bonus": 1,
		})
	var snapshot: Dictionary = modifiers.snapshot()
	_suite.assert_close(
		float(snapshot.get("weapon.charge_rate", NAN)),
		1.5,
		"player accumulates repeated charge-rate bonuses"
	)
	_suite.assert_close(
		float(snapshot.get("weapon.full_charge_damage", NAN)),
		1.7,
		"player accumulates repeated full-charge damage bonuses"
	)
	_suite.assert_close(
		float(snapshot.get("weapon.pierce", NAN)),
		2.0,
		"player accumulates repeated pierce bonuses"
	)
	loadout.free()
	player.free()


func _test_player_rejects_bow_capabilities_for_non_bow_loadout() -> void:
	var player = PlayerControllerScript.new()
	var loadout := FakeLoadoutRuntime.new()
	loadout.equipped_weapon_id = &"sword"
	player.loadout_runtime = loadout
	var capabilities := PackedStringArray([
		"weapon.charge_rate",
		"weapon.full_charge_damage",
		"weapon.pierce",
	])
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(capabilities, player.call("_modifier_bounds_for", capabilities)),
		"non-Bow gating fixture configures"
	)
	_suite.assert_true(modifiers.apply(&"weapon.charge_rate", 1.1), "gating fixture seeds charge rate")
	_suite.assert_true(modifiers.apply(&"weapon.full_charge_damage", 1.2), "gating fixture seeds full-charge damage")
	_suite.assert_true(modifiers.apply(&"weapon.pierce", 2.0), "gating fixture seeds pierce")
	player.weapon_modifier_state = modifiers
	var before: Dictionary = modifiers.snapshot()
	ItemEffectScript._apply_weapon_effects(player, {
		"bow_charge_rate_bonus": 0.25,
		"bow_full_charge_damage_multiplier_bonus": 0.35,
		"bow_pierce_bonus": 1,
	})
	_suite.assert_equal(
		modifiers.snapshot(),
		before,
		"Bow-specific item effects cannot mutate the modifier state while Sword is equipped"
	)
	loadout.free()
	player.free()


func _test_missing_player_api_fails_safely() -> void:
	var player := PlayerWithoutWeaponEffectApi.new()
	ItemEffectScript.apply_to_player(player, LEGACY_WEAPON_EFFECTS)
	_suite.assert_equal(player.stats_sync_count, 1, "missing weapon API leaves the remaining item pipeline usable")
	player.free()


func _test_item_effect_does_not_reach_weapon_nodes() -> void:
	var source := FileAccess.get_file_as_string(ITEM_EFFECT_SOURCE_PATH)
	_suite.assert_true(not source.is_empty(), "item effect source is readable")
	_suite.assert_true(
		not source.contains("player.sword_weapon"),
		"item effects do not directly access the sword presentation node"
	)
	_suite.assert_true(
		not source.contains("player.bow_weapon"),
		"item effects do not directly access the bow presentation node"
	)
	var player_source := FileAccess.get_file_as_string(PLAYER_CONTROLLER_SOURCE_PATH)
	_suite.assert_true(not player_source.is_empty(), "player controller source is readable")
	for direct_write: String in [
		"bow_weapon.charge_rate_bonus",
		"bow_weapon.full_charge_damage_multiplier_bonus",
		"bow_weapon.pierce_bonus",
		"bow_weapon.cancel_charge",
	]:
		_suite.assert_true(
			not player_source.contains(direct_write),
			"legacy bow effects do not write presentation state: %s" % direct_write
		)
