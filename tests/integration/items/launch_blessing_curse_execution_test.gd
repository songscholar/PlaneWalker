extends Node

const EffectHandlerCatalogScript := preload(
	"res://scripts/content/effects/effect_handler_catalog.gd"
)
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const StatsScript := preload("res://scripts/core/stats.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const TimeManagerScript := preload("res://scripts/time_system/time_manager.gd")
const WeaponModifierStateScript := preload(
	"res://scripts/combat/weapons/weapon_modifier_state.gd"
)

const LAUNCH_CATALOG_PATH := "res://data/content/launch_pool_catalog.json"
const BLESSINGS_PATH := "res://data/content_packs/base/content/blessings.json"
const CURSES_PATH := "res://data/content_packs/base/content/curses.json"
const BLESSING_MIRROR_PATH := "res://data/blessings/mvp_blessings.json"
const CURSE_MIRROR_PATH := "res://data/curses/mvp_curses.json"
const WEAPON_IDS: Array[String] = ["bow", "gauntlets", "gun", "staff", "sword"]
const ARCHETYPE_IDS: Array[String] = [
	"freeze_burst",
	"rewind_echo",
	"rift_trap",
	"accelerated_combo",
	"low_hp_void",
	"perfect_guard",
	"piercing_barrage",
	"echo_legion",
]
const HARMFUL_EFFECT_MARKERS: Array[String] = [
	"self_damage",
	"damage_taken",
	"vulnerability",
	"fragility",
	"penalty",
	"health_loss",
	"hp_loss",
	"resource_drain",
	"energy_drain",
]
const COST_EFFECT_MARKERS: Array[String] = [
	"cost_multiplier",
	"cooldown_multiplier",
]
const FROZEN_BLESSING_EFFECTS := {
	"bls_stop_weakpoint": {
		"time_stop_weakpoint_damage_bonus": 0.35,
		"time_stop_weakpoint_duration": 3.0,
	},
	"bls_rewind_path": {
		"rewind_cost_multiplier": 0.9,
		"rewind_heal": 18.0,
		"rewind_path_hit_multiplier": 0.5,
	},
	"bls_sword_tempo": {
		"attack_speed_multiplier": 1.08,
		"combo_finisher_multiplier_bonus": 0.2,
	},
	"bls_survive_thread": {
		"max_hp_bonus": 20.0,
		"time_energy_max_bonus": 15.0,
		"invulnerable_duration": 0.8,
	},
}
const FROZEN_LEGACY_CURSES := {
	"blood_rewind": {
		"availability": ["M1"],
		"archetype": "",
		"role": "utility",
		"effects": {"rewind_heal": 45.0, "rewind_self_damage": 18.0},
	},
	"brittle_vitality": {
		"availability": ["NEXT"],
		"archetype": "",
		"role": "utility",
		"effects": {"attack_multiplier": 1.25, "healing_multiplier": 0.5},
	},
	"glass_tempo": {
		"availability": ["M1"],
		"archetype": "",
		"role": "utility",
		"effects": {"attack_speed_multiplier": 1.25, "max_hp_multiplier": 0.78},
	},
	"narrow_escape": {
		"availability": ["NEXT"],
		"archetype": "",
		"role": "utility",
		"effects": {"dash_invulnerable_bonus": 0.15, "defense_bonus": -2.0},
	},
	"overclocked_stasis": {
		"availability": ["M1"],
		"archetype": "",
		"role": "utility",
		"effects": {"time_stop_duration_bonus": 1.2, "time_stop_self_damage": 12.0},
	},
	"starving_clock": {
		"availability": ["NEXT"],
		"archetype": "",
		"role": "utility",
		"effects": {"time_energy_max_bonus": 40.0, "time_energy_regen_multiplier": 0.5},
	},
}

var _suite
var _effect_catalog: RefCounted


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
	_effect_catalog = EffectHandlerCatalogScript.new()
	var launch_catalog_value: Variant = _read_json(LAUNCH_CATALOG_PATH)
	var blessings_value: Variant = _read_json(BLESSINGS_PATH)
	var curses_value: Variant = _read_json(CURSES_PATH)
	var blessing_mirror_value: Variant = _read_json(BLESSING_MIRROR_PATH)
	var curse_mirror_value: Variant = _read_json(CURSE_MIRROR_PATH)
	if (
		launch_catalog_value is Dictionary
		and blessings_value is Array
		and curses_value is Array
		and blessing_mirror_value is Array
		and curse_mirror_value is Array
	):
		var launch_catalog := launch_catalog_value as Dictionary
		var blessings := blessings_value as Array
		var curses := curses_value as Array
		var blessing_targets: Array = launch_catalog.get("blessings", [])
		var curse_targets: Array = launch_catalog.get("curses", [])
		_test_exact_population(blessings, curses, blessing_targets, curse_targets)
		_test_route_distribution(blessings, curses, blessing_targets, curse_targets)
		_test_frozen_content(blessings, curses)
		_test_mirror_parity(
			blessings,
			curses,
			blessing_mirror_value as Array,
			curse_mirror_value as Array,
			blessing_targets,
			curse_targets
		)
	_suite.finish(get_tree())


func _test_exact_population(
	blessings: Array,
	curses: Array,
	blessing_targets: Array,
	curse_targets: Array
) -> void:
	_suite.assert_equal(blessing_targets.size(), 28, "Launch target contains twenty-eight blessings")
	_suite.assert_equal(curse_targets.size(), 18, "Launch target contains eighteen curses")
	_suite.assert_equal(blessings.size(), 28, "Base Pack contains exactly twenty-eight blessings")
	_suite.assert_equal(
		curses.size(),
		FROZEN_LEGACY_CURSES.size() + 18,
		"Base Pack contains eighteen Launch curses plus six frozen M1/NEXT curses"
	)
	var blessings_by_id := _index_by_id(blessings)
	var curses_by_id := _index_by_id(curses)
	for target_value: Variant in blessing_targets:
		if target_value is Dictionary:
			_test_target_definition(
				blessings_by_id,
				target_value as Dictionary,
				"blessing"
			)
	for target_value: Variant in curse_targets:
		if target_value is Dictionary:
			_test_target_definition(curses_by_id, target_value as Dictionary, "curse")


func _test_target_definition(
	definitions_by_id: Dictionary,
	target: Dictionary,
	category: String
) -> void:
	var content_id := str(target.get("id", ""))
	var definition_value: Variant = definitions_by_id.get(content_id, {})
	_suite.assert_true(
		definition_value is Dictionary and not (definition_value as Dictionary).is_empty(),
		"%s %s exists in the Base Pack" % [category, content_id]
	)
	if not definition_value is Dictionary or (definition_value as Dictionary).is_empty():
		return
	var definition := definition_value as Dictionary
	var archetype := str(target.get("archetype", ""))
	_suite.assert_equal(str(definition.get("category", "")), category, "%s category is exact" % content_id)
	_suite.assert_equal(str(definition.get("archetype", "")), archetype, "%s archetype is exact" % content_id)
	_suite.assert_equal(str(definition.get("role", "")), str(target.get("role", "")), "%s role is exact" % content_id)
	var availability_value: Variant = definition.get("availability", [])
	_suite.assert_true(
		availability_value is Array
		and (availability_value as Array).has("LAUNCH")
		and (availability_value as Array).has("EXPANSION"),
		"%s is available in Launch and Expansion" % content_id
	)
	var tags_value: Variant = definition.get("tags", [])
	var compatibility_value: Variant = definition.get("compatibility", {})
	_suite.assert_true(tags_value is Array, "%s tags are an array" % content_id)
	_suite.assert_true(compatibility_value is Dictionary, "%s compatibility is a dictionary" % content_id)
	if tags_value is Array and compatibility_value is Dictionary:
		var tags := tags_value as Array
		var route_ids_value: Variant = (compatibility_value as Dictionary).get("archetype_ids", [])
		if archetype.is_empty():
			_suite.assert_true(tags.has("generalist") and tags.has("utility"), "%s is explicitly generalist utility" % content_id)
			_suite.assert_true(route_ids_value is Array and (route_ids_value as Array).is_empty(), "%s has no hidden route scope" % content_id)
		else:
			_suite.assert_true(tags.has(archetype), "%s carries its route tag" % content_id)
			_suite.assert_true(not tags.has("generalist") and not tags.has("utility"), "%s is not mislabeled as utility" % content_id)
			_suite.assert_equal(route_ids_value, [archetype], "%s has exact route compatibility" % content_id)
	_test_effect_contract_and_execution(definition, category)


func _test_effect_contract_and_execution(definition: Dictionary, category: String) -> void:
	var content_id := str(definition.get("id", ""))
	var effects_value: Variant = definition.get("effects", {})
	_suite.assert_true(
		effects_value is Dictionary and not (effects_value as Dictionary).is_empty(),
		"%s has executable effects" % content_id
	)
	if not effects_value is Dictionary or (effects_value as Dictionary).is_empty():
		return
	var effects := effects_value as Dictionary
	var validation = _effect_catalog.call(
		"validate_effects",
		effects.duplicate(true),
		{"category": category}
	)
	_suite.assert_true(
		validation != null
		and validation.has_method("has_blocking_errors")
		and not bool(validation.call("has_blocking_errors")),
		"%s effects are allowed, bounded, and typed for %s" % [content_id, category]
	)
	var normalized: Dictionary = _effect_catalog.call("normalize_effects", effects.duplicate(true))
	_suite.assert_equal(normalized.size(), effects.size(), "%s effects normalize without loss" % content_id)
	var polarities: Array[String] = []
	for effect_id_value: Variant in normalized.keys():
		var effect_id := str(effect_id_value)
		var descriptor: Dictionary = _effect_catalog.call(
			"effect_descriptor",
			StringName(effect_id)
		)
		var polarity := _effect_polarity(effect_id, normalized[effect_id], descriptor)
		_suite.assert_true(not polarity.is_empty(), "%s effect %s has classifiable gameplay polarity" % [content_id, effect_id])
		if not polarity.is_empty() and not polarities.has(polarity):
			polarities.append(polarity)
	if category == "blessing":
		_suite.assert_true(polarities.has("positive"), "%s contains a positive modifier" % content_id)
		_suite.assert_true(not polarities.has("negative"), "%s hides no negative cost" % content_id)
	else:
		_suite.assert_true(polarities.has("positive"), "%s exposes an upside" % content_id)
		_suite.assert_true(polarities.has("negative"), "%s exposes a downside" % content_id)

	var compatible_weapon := _compatible_weapon(effects)
	_suite.assert_true(not compatible_weapon.is_empty(), "%s has one compatible weapon route" % content_id)
	if compatible_weapon.is_empty():
		return
	var fixture := _player_fixture(StringName(compatible_weapon))
	_suite.assert_true(not fixture.is_empty(), "%s Player fixture configures" % content_id)
	if fixture.is_empty():
		return
	var player: Node = fixture["player"]
	var health: Node = fixture["health"]
	var time_manager: Node = fixture["time_manager"]
	health.set("current_hp", 50.0)
	time_manager.set("energy", 20.0)
	var before: Dictionary = player.call("reward_effect_snapshot")
	var result: Dictionary = (
		player.call("apply_curse", definition.duplicate(true))
		if category == "curse"
		else player.call("apply_reward", definition.duplicate(true))
	)
	_suite.assert_true(bool(result.get("ok", false)), "%s applies atomically: %s" % [content_id, str(result)])
	if bool(result.get("ok", false)):
		var receipt_value: Variant = result.get("receipt", {})
		_suite.assert_true(receipt_value is Dictionary, "%s returns an effect receipt" % content_id)
		if receipt_value is Dictionary:
			_suite.assert_equal(
				int((receipt_value as Dictionary).get("operation_count", -1)),
				effects.size(),
				"%s executes every normalized operation" % content_id
			)
		_suite.assert_true(
			player.call("reward_effect_snapshot") != before,
			"%s produces an observable Player state change" % content_id
		)
	_free_player_fixture(fixture)


func _test_route_distribution(
	blessings: Array,
	curses: Array,
	blessing_targets: Array,
	curse_targets: Array
) -> void:
	var blessing_ids := _id_set(blessing_targets)
	var curse_ids := _id_set(curse_targets)
	var launch_blessings := blessings.filter(
		func(row): return row is Dictionary and blessing_ids.has(str(row.get("id", "")))
	)
	var launch_curses := curses.filter(
		func(row): return row is Dictionary and curse_ids.has(str(row.get("id", "")))
	)
	for archetype: String in ARCHETYPE_IDS:
		var route_blessings := launch_blessings.filter(
			func(row): return str(row.get("archetype", "")) == archetype
		)
		_suite.assert_equal(route_blessings.size(), 3, "%s has three Launch blessings" % archetype)
		_suite.assert_equal(
			route_blessings.filter(func(row): return str(row.get("role", "")) == "starter").size(),
			1,
			"%s has one blessing starter" % archetype
		)
		_suite.assert_equal(
			route_blessings.filter(func(row): return str(row.get("role", "")) == "payoff").size(),
			2,
			"%s has two blessing payoffs" % archetype
		)
		var route_curses := launch_curses.filter(
			func(row): return str(row.get("archetype", "")) == archetype
		)
		_suite.assert_equal(route_curses.size(), 2, "%s has two Launch curses" % archetype)
		_suite.assert_true(
			route_curses.all(func(row): return str(row.get("role", "")) == "risk"),
			"%s curses all use the risk role" % archetype
		)
	_suite.assert_equal(
		launch_blessings.filter(func(row): return str(row.get("archetype", "")).is_empty()).size(),
		4,
		"Launch has four general utility blessings"
	)
	_suite.assert_equal(
		launch_curses.filter(func(row): return str(row.get("archetype", "")).is_empty()).size(),
		2,
		"Launch has two general utility curses"
	)


func _test_frozen_content(blessings: Array, curses: Array) -> void:
	var blessings_by_id := _index_by_id(blessings)
	for content_id_value: Variant in FROZEN_BLESSING_EFFECTS.keys():
		var content_id := str(content_id_value)
		var definition: Dictionary = blessings_by_id.get(content_id, {})
		_suite.assert_true(not definition.is_empty(), "%s frozen blessing remains present" % content_id)
		if definition.is_empty():
			continue
		var availability_value: Variant = definition.get("availability", [])
		_suite.assert_true(
			availability_value is Array and (availability_value as Array).has("M1"),
			"%s preserves M1 availability" % content_id
		)
		_suite.assert_equal(
			definition.get("effects", {}),
			FROZEN_BLESSING_EFFECTS[content_id],
			"%s preserves approved M1 effects" % content_id
		)
	var curses_by_id := _index_by_id(curses)
	for content_id_value: Variant in FROZEN_LEGACY_CURSES.keys():
		var content_id := str(content_id_value)
		var definition: Dictionary = curses_by_id.get(content_id, {})
		_suite.assert_true(not definition.is_empty(), "%s frozen curse remains present" % content_id)
		if definition.is_empty():
			continue
		var expected: Dictionary = FROZEN_LEGACY_CURSES[content_id]
		for field: String in ["availability", "archetype", "role", "effects"]:
			_suite.assert_equal(
				definition.get(field),
				expected[field],
				"%s preserves frozen %s" % [content_id, field]
			)


func _test_mirror_parity(
	blessings: Array,
	curses: Array,
	blessing_mirror: Array,
	curse_mirror: Array,
	blessing_targets: Array,
	curse_targets: Array
) -> void:
	_suite.assert_equal(blessing_mirror.size(), 28, "Blessing mirror contains twenty-eight definitions")
	_suite.assert_equal(
		curse_mirror.size(),
		FROZEN_LEGACY_CURSES.size() + 18,
		"Curse mirror contains Launch and frozen legacy definitions"
	)
	var blessing_source := _index_by_id(blessings)
	var curse_source := _index_by_id(curses)
	var blessing_mirror_by_id := _index_by_id(blessing_mirror)
	var curse_mirror_by_id := _index_by_id(curse_mirror)
	for target_value: Variant in blessing_targets:
		if target_value is Dictionary:
			_assert_mirror_effects(
				str((target_value as Dictionary).get("id", "")),
				blessing_source,
				blessing_mirror_by_id,
				"blessing"
			)
	for target_value: Variant in curse_targets:
		if target_value is Dictionary:
			_assert_mirror_effects(
				str((target_value as Dictionary).get("id", "")),
				curse_source,
				curse_mirror_by_id,
				"curse"
			)
	for content_id_value: Variant in FROZEN_LEGACY_CURSES.keys():
		_assert_mirror_effects(
			str(content_id_value),
			curse_source,
			curse_mirror_by_id,
			"legacy curse"
		)


func _assert_mirror_effects(
	content_id: String,
	source_by_id: Dictionary,
	mirror_by_id: Dictionary,
	label: String
) -> void:
	var source_value: Variant = source_by_id.get(content_id, {})
	var mirror_value: Variant = mirror_by_id.get(content_id, {})
	_suite.assert_true(
		source_value is Dictionary and not (source_value as Dictionary).is_empty(),
		"%s %s exists in the source catalog" % [label, content_id]
	)
	_suite.assert_true(
		mirror_value is Dictionary and not (mirror_value as Dictionary).is_empty(),
		"%s %s exists in the compatibility mirror" % [label, content_id]
	)
	if (
		source_value is Dictionary
		and mirror_value is Dictionary
		and not (source_value as Dictionary).is_empty()
		and not (mirror_value as Dictionary).is_empty()
	):
		_suite.assert_equal(
			(mirror_value as Dictionary).get("effects", {}),
			(source_value as Dictionary).get("effects", {}),
			"%s %s effects match the authoritative source" % [label, content_id]
		)


func _effect_polarity(
	effect_id: String,
	value: Variant,
	descriptor: Dictionary
) -> String:
	if descriptor.is_empty():
		return ""
	if typeof(value) == TYPE_BOOL:
		return "positive" if bool(value) and not _contains_marker(effect_id, HARMFUL_EFFECT_MARKERS) else ""
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return ""
	var numeric := float(value)
	var stack_rule := str(descriptor.get("stack_rule", ""))
	if _contains_marker(effect_id, COST_EFFECT_MARKERS):
		if is_equal_approx(numeric, 1.0):
			return ""
		return "positive" if numeric < 1.0 else "negative"
	if _contains_marker(effect_id, HARMFUL_EFFECT_MARKERS):
		if stack_rule in ["multiply", "replace"]:
			if is_equal_approx(numeric, 1.0):
				return ""
			return "positive" if numeric < 1.0 else "negative"
		if is_zero_approx(numeric):
			return ""
		return "negative" if numeric > 0.0 else "positive"
	if stack_rule == "multiply":
		if is_equal_approx(numeric, 1.0):
			return ""
		return "positive" if numeric > 1.0 else "negative"
	if stack_rule in ["add", "maximum", "trigger"]:
		if is_zero_approx(numeric):
			return ""
		return "positive" if numeric > 0.0 else "negative"
	if stack_rule == "replace":
		var mappings_value: Variant = descriptor.get("weapon_capabilities", [])
		if mappings_value is Array and (mappings_value as Array).size() == 1:
			var mapping_value: Variant = (mappings_value as Array)[0]
			if mapping_value is Dictionary:
				var base_value := float((mapping_value as Dictionary).get("base_value", numeric))
				if is_equal_approx(numeric, base_value):
					return ""
				return "positive" if numeric > base_value else "negative"
	return ""


func _contains_marker(effect_id: String, markers: Array[String]) -> bool:
	for marker: String in markers:
		if effect_id.contains(marker):
			return true
	return false


func _compatible_weapon(effects: Dictionary) -> String:
	var allowed: Array[String] = WEAPON_IDS.duplicate()
	var has_weapon_effect := false
	for effect_id_value: Variant in effects.keys():
		var descriptor: Dictionary = _effect_catalog.call(
			"effect_descriptor",
			StringName(str(effect_id_value))
		)
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
		bounds[capability] = (
			PlayerControllerScript.WEAPON_MODIFIER_BOUNDS[capability_value] as Dictionary
		).duplicate(true)
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
		"weapon_runtime": weapon_runtime,
	}


func _free_player_fixture(fixture: Dictionary) -> void:
	(fixture["health"] as Node).queue_free()
	(fixture["time_manager"] as Node).queue_free()
	(fixture["loadout"] as Node).free()
	(fixture["player"] as Node).free()


func _index_by_id(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row_value: Variant in rows:
		if row_value is Dictionary:
			var content_id := str((row_value as Dictionary).get("id", ""))
			_suite.assert_true(not content_id.is_empty(), "content row has an id")
			_suite.assert_true(not result.has(content_id), "content id %s is unique" % content_id)
			if not content_id.is_empty() and not result.has(content_id):
				result[content_id] = (row_value as Dictionary).duplicate(true)
	return result


func _id_set(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row_value: Variant in rows:
		if row_value is Dictionary:
			result[str((row_value as Dictionary).get("id", ""))] = true
	return result


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
