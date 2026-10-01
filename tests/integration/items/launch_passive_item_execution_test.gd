extends Node

const EffectHandlerCatalogScript := preload("res://scripts/content/effects/effect_handler_catalog.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const StatsScript := preload("res://scripts/core/stats.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const TimeManagerScript := preload("res://scripts/time_system/time_manager.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")

const ITEMS_PATH := "res://data/content_packs/base/content/items.json"
const WEAPON_IDS: Array[String] = ["bow", "gauntlets", "gun", "staff", "sword"]

var _suite


class FakeLoadoutRuntime extends Node:
	var equipped_weapon_id: StringName = &"sword"

	func has_weapon(weapon_id: StringName) -> bool:
		return weapon_id == equipped_weapon_id


class FakeWeaponRuntime extends RefCounted:
	var modifiers: RefCounted

	func _init(next_modifiers: RefCounted) -> void:
		modifiers = next_modifiers

	func apply_modifier(capability: StringName, value: Variant) -> bool:
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


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var source_value: Variant = _read_json(ITEMS_PATH)
	if source_value is Array:
		var passives: Array = (source_value as Array).filter(
			func(entry): return entry is Dictionary and str(entry.get("item_mode", "")) == "passive"
		)
		_suite.assert_equal(passives.size(), 42, "Launch execution matrix contains exactly forty-two passive items")
		for definition_value: Variant in passives:
			if definition_value is Dictionary:
				_test_passive_definition(definition_value as Dictionary)
	_suite.finish(get_tree())


func _test_passive_definition(definition: Dictionary) -> void:
	var content_id := str(definition.get("id", ""))
	var effects_value: Variant = definition.get("effects", {})
	_suite.assert_true(effects_value is Dictionary and not (effects_value as Dictionary).is_empty(), "%s has effects to execute" % content_id)
	if not effects_value is Dictionary or (effects_value as Dictionary).is_empty():
		return
	var compatible_weapon := _compatible_weapon(effects_value as Dictionary)
	_suite.assert_true(not compatible_weapon.is_empty(), "%s has a compatible weapon route" % content_id)
	if compatible_weapon.is_empty():
		return
	var fixture := _player_fixture(StringName(compatible_weapon))
	if fixture.is_empty():
		_suite.assert_true(false, "%s player fixture configures" % content_id)
		return
	var player: Node = fixture["player"]
	var health: Node = fixture["health"]
	var time_manager: Node = fixture["time_manager"]
	health.set("current_hp", 50.0)
	time_manager.set("energy", 20.0)
	var before: Dictionary = player.call("reward_effect_snapshot")
	var result: Dictionary = player.call("apply_reward", definition.duplicate(true))
	_suite.assert_true(bool(result.get("ok", false)), "%s applies atomically: %s" % [content_id, str(result)])
	if bool(result.get("ok", false)):
		var after: Dictionary = player.call("reward_effect_snapshot")
		_suite.assert_true(after != before, "%s produces an observable compatible Player state change" % content_id)
	_free_player_fixture(fixture)


func _compatible_weapon(effects: Dictionary) -> String:
	var allowed: Array[String] = WEAPON_IDS.duplicate()
	var has_weapon_effect := false
	var catalog = EffectHandlerCatalogScript.new()
	for effect_id_value: Variant in effects.keys():
		var descriptor: Dictionary = catalog.effect_descriptor(StringName(str(effect_id_value)))
		var mappings_value: Variant = descriptor.get("weapon_capabilities", [])
		if not mappings_value is Array or (mappings_value as Array).is_empty():
			continue
		has_weapon_effect = true
		var effect_weapons: Array[String] = []
		for mapping_value: Variant in mappings_value as Array:
			if mapping_value is Dictionary:
				var weapon_id := str((mapping_value as Dictionary).get("weapon_id", ""))
				if not weapon_id.is_empty() and not effect_weapons.has(weapon_id):
					effect_weapons.append(weapon_id)
		allowed = allowed.filter(func(weapon_id): return effect_weapons.has(weapon_id))
	if has_weapon_effect and allowed.is_empty():
		return ""
	allowed.sort()
	return allowed[0] if not allowed.is_empty() else "sword"


func _player_fixture(weapon_id: StringName) -> Dictionary:
	var player = PlayerControllerScript.new()
	player.stats = StatsScript.new()
	var health = HealthComponentScript.new()
	add_child(health)
	health.call("configure_from_stats", player.stats)
	var time_manager = TimeManagerScript.new()
	add_child(time_manager)
	time_manager.call("configure_from_stats", player.stats)
	var loadout := FakeLoadoutRuntime.new()
	loadout.equipped_weapon_id = weapon_id
	var modifiers = WeaponModifierStateScript.new()
	var capabilities := PackedStringArray()
	var bounds: Dictionary = {}
	for capability_value: Variant in PlayerControllerScript.WEAPON_MODIFIER_BOUNDS.keys():
		var capability := str(capability_value)
		capabilities.append(capability)
		bounds[capability] = (PlayerControllerScript.WEAPON_MODIFIER_BOUNDS[capability_value] as Dictionary).duplicate(true)
	if not modifiers.configure(capabilities, bounds):
		health.queue_free()
		time_manager.queue_free()
		loadout.free()
		player.free()
		return {}
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


func _read_json(path: String) -> Variant:
	_suite.assert_true(FileAccess.file_exists(path), "%s exists" % path)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	_suite.assert_true(file != null, "%s can be opened" % path)
	if file == null:
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	_suite.assert_equal(error, OK, "%s contains valid JSON" % path)
	return parser.data if error == OK else {}
