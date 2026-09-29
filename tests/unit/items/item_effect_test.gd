extends Node

const ItemEffectScript := preload("res://scripts/items/item_effect.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ITEM_EFFECT_SOURCE_PATH := "res://scripts/items/item_effect.gd"

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
	var stats_sync_count: int = 0


	func apply_weapon_effect(effect_id: StringName, value: Variant) -> bool:
		routed_effects[str(effect_id)] = value
		return true


	func _apply_stats_to_components(_preserve_current: bool) -> void:
		stats_sync_count += 1


class PlayerWithoutWeaponEffectApi extends Node:
	var stats_sync_count: int = 0


	func _apply_stats_to_components(_preserve_current: bool) -> void:
		stats_sync_count += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_legacy_weapon_effects_use_player_api()
	_test_missing_player_api_fails_safely()
	_test_item_effect_does_not_reach_weapon_nodes()
	_suite.finish(get_tree())


func _test_legacy_weapon_effects_use_player_api() -> void:
	var player := WeaponEffectPlayer.new()
	ItemEffectScript.apply_to_player(player, LEGACY_WEAPON_EFFECTS)
	_suite.assert_equal(
		player.routed_effects,
		LEGACY_WEAPON_EFFECTS,
		"all legacy sword and bow effects route through the player weapon API"
	)
	_suite.assert_equal(player.stats_sync_count, 1, "weapon effects retain component stat synchronization")
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
