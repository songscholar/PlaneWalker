extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const EffectDefinitionScript := preload("res://scripts/content/effects/effect_definition.gd")
const EffectHandlerCatalogScript := preload("res://scripts/content/effects/effect_handler_catalog.gd")

const SOURCE_PATHS: Array[String] = [
	"res://data/items/mvp_items.json",
	"res://data/blessings/mvp_blessings.json",
	"res://data/curses/mvp_curses.json",
	"res://data/talents/mvp_talents.json",
]
const SOURCE_CATEGORIES := {
	"res://data/items/mvp_items.json": "item",
	"res://data/blessings/mvp_blessings.json": "blessing",
	"res://data/curses/mvp_curses.json": "curse",
	"res://data/talents/mvp_talents.json": "talent",
}
const RUNTIME_DOMAIN_BY_EFFECT := {
	"attack_multiplier": "weapon",
	"attack_speed_multiplier": "weapon",
	"bow_charge_rate_bonus": "weapon",
	"bow_full_charge_damage_multiplier_bonus": "weapon",
	"bow_pierce_bonus": "weapon",
	"combo_finisher_multiplier_bonus": "weapon",
	"dash_invulnerable_bonus": "character",
	"defense_bonus": "stats",
	"heal": "trigger",
	"healing_multiplier": "health",
	"heavy_damage_multiplier_bonus": "weapon",
	"heavy_execute_multiplier_bonus": "weapon",
	"heavy_execute_threshold": "weapon",
	"invulnerable_duration": "trigger",
	"low_energy_regen_multiplier": "time",
	"low_energy_threshold": "time",
	"low_hp_damage_multiplier_bonus": "weapon",
	"max_hp_bonus": "stats",
	"max_hp_multiplier": "stats",
	"rewind_cost_multiplier": "time",
	"rewind_echo_enabled": "time",
	"rewind_heal": "time",
	"rewind_path_hit_multiplier": "time",
	"rewind_self_damage": "time",
	"time_accelerate_cost_multiplier": "time",
	"time_accelerate_duration_bonus": "time",
	"time_accelerate_multiplier_bonus": "time",
	"time_energy_max_bonus": "stats",
	"time_energy_regen_bonus": "stats",
	"time_energy_regen_multiplier": "stats",
	"time_energy_restore": "trigger",
	"time_rift_cost_multiplier": "time",
	"time_rift_duration_bonus": "time",
	"time_rift_radius_bonus": "time",
	"time_rift_slow_bonus": "time",
	"time_stop_cost_multiplier": "time",
	"time_stop_duration_bonus": "time",
	"time_stop_self_damage": "time",
	"time_stop_weakpoint_damage_bonus": "time",
	"time_stop_weakpoint_duration": "time",
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var catalog = EffectHandlerCatalogScript.new()
	_test_catalog_covers_current_effects(suite, catalog)
	_test_runtime_domain_authority(suite, catalog)
	_test_known_effects_and_context(suite, catalog)
	_test_script_like_and_unknown_ids(suite, catalog)
	_test_scalar_types_and_numeric_bounds(suite, catalog)
	_test_weapon_capability_mappings(suite, catalog)
	_test_weapon_capability_schema_fails_closed(suite)
	_test_deterministic_normalization(suite, catalog)
	_test_snapshot_isolation(suite, catalog)
	_test_missing_catalog_fails_closed(suite)
	suite.finish(get_tree())


func _test_catalog_covers_current_effects(suite, catalog) -> void:
	var load_report = catalog.load_report()
	suite.assert_true(not load_report.has_blocking_errors(), "tracked effect catalog loads")
	var expected_ids := _current_effect_ids(suite)
	var snapshot: Array[Dictionary] = catalog.snapshot()
	var actual_ids: Array[String] = []
	var required_fields: Array[String] = [
		"effect_id",
		"value_type",
		"minimum",
		"maximum",
		"stack_rule",
		"allowed_categories",
		"runtime_domain",
	]
	for row: Dictionary in snapshot:
		actual_ids.append(str(row.get("effect_id", "")))
		for field: String in required_fields:
			suite.assert_true(row.has(field), "catalog row %s contains %s" % [row.get("effect_id", ""), field])
	suite.assert_equal(actual_ids, expected_ids, "catalog covers exactly the current M1 effect ids")
	suite.assert_equal(actual_ids.size(), 40, "current M1 content exposes forty effect ids")
	for path: String in SOURCE_PATHS:
		var entries := _read_content_entries(path, suite)
		for entry: Dictionary in entries:
			var effects: Dictionary = entry.get("effects", {})
			var report = catalog.validate_effects(effects, {"category": SOURCE_CATEGORIES[path]})
			suite.assert_true(
				not report.has_blocking_errors(),
				"current content %s in %s validates" % [entry.get("id", ""), SOURCE_CATEGORIES[path]]
			)
			if not effects.is_empty():
				suite.assert_true(
					not catalog.normalize_effects(effects).is_empty(),
					"current content %s normalizes" % entry.get("id", "")
				)


func _test_runtime_domain_authority(suite, catalog) -> void:
	var snapshot: Array[Dictionary] = catalog.snapshot()
	var actual_domains: Dictionary = {}
	for row: Dictionary in snapshot:
		actual_domains[str(row.get("effect_id", ""))] = str(row.get("runtime_domain", ""))
	suite.assert_equal(
		actual_domains,
		RUNTIME_DOMAIN_BY_EFFECT,
		"every current effect has one exact runtime domain"
	)
	suite.assert_true(
		catalog.has_method("runtime_domain_for"),
		"catalog exposes runtime-domain lookup for typed effect planning"
	)
	if catalog.has_method("runtime_domain_for"):
		suite.assert_equal(
			str(catalog.call("runtime_domain_for", &"heal")),
			"trigger",
			"known effects expose their runtime domain"
		)
		suite.assert_equal(
			str(catalog.call("runtime_domain_for", &"unknown_effect")),
			"",
			"unknown effects expose no runtime domain"
		)
		suite.assert_equal(
			str(catalog.call("runtime_domain_for", &"res://hostile.gd")),
			"",
			"script-like effect ids expose no runtime domain"
		)
	suite.assert_true(
		catalog.has_method("effect_descriptor"),
		"catalog exposes a canonical effect descriptor for runtime planning"
	)
	if catalog.has_method("effect_descriptor"):
		var descriptor: Dictionary = catalog.call("effect_descriptor", &"attack_multiplier")
		suite.assert_equal(descriptor.get("runtime_domain"), "weapon", "descriptor exposes runtime domain")
		suite.assert_equal(descriptor.get("stack_rule"), "multiply", "descriptor exposes stack rule")
		suite.assert_equal(descriptor.get("value_type"), "number", "descriptor exposes value type")
		suite.assert_equal(
			(descriptor.get("weapon_capabilities", []) as Array).size(),
			5,
			"descriptor exposes declared weapon capability routes"
		)
		descriptor["runtime_domain"] = "mutated"
		(descriptor.get("weapon_capabilities", []) as Array).clear()
		var repeated_descriptor: Dictionary = catalog.call("effect_descriptor", &"attack_multiplier")
		suite.assert_equal(
			repeated_descriptor.get("runtime_domain"),
			"weapon",
			"descriptor mutation cannot change catalog authority"
		)
		suite.assert_equal(
			(repeated_descriptor.get("weapon_capabilities", []) as Array).size(),
			5,
			"descriptor capability rows are deep copied"
		)
		suite.assert_equal(
			catalog.call("effect_descriptor", &"unknown_effect"),
			{},
			"unknown effects expose no descriptor"
		)

	var definition_source := {
		"effect_id": "fixture_domain_effect",
		"value_type": "number",
		"minimum": 0.0,
		"maximum": 1.0,
		"stack_rule": "add",
		"allowed_categories": ["item"],
		"runtime_domain": "stats",
	}
	var valid_definition = EffectDefinitionScript.new()
	suite.assert_true(
		bool(valid_definition.configure(definition_source).get("ok", false)),
		"known runtime domains configure"
	)
	var missing_domain: Dictionary = definition_source.duplicate(true)
	missing_domain.erase("runtime_domain")
	var missing_result: Dictionary = EffectDefinitionScript.new().configure(missing_domain)
	suite.assert_equal(
		missing_result.get("context", {}).get("reason"),
		"missing",
		"missing runtime domain fails closed"
	)
	var unknown_domain: Dictionary = definition_source.duplicate(true)
	unknown_domain["runtime_domain"] = "world"
	var unknown_result: Dictionary = EffectDefinitionScript.new().configure(unknown_domain)
	suite.assert_equal(
		unknown_result.get("context", {}).get("reason"),
		"unsupported",
		"unknown runtime domain fails closed"
	)


func _test_known_effects_and_context(suite, catalog) -> void:
	var item_report = catalog.validate_effects(
		{"heal": 20.0, "attack_multiplier": 1.18},
		{"category": "item"}
	)
	suite.assert_true(not item_report.has_blocking_errors(), "known item effects validate")

	var blessing_report = catalog.validate_effects(
		{"time_stop_weakpoint_damage_bonus": 0.35, "time_stop_weakpoint_duration": 3.0},
		{"category": "blessing"}
	)
	suite.assert_true(not blessing_report.has_blocking_errors(), "known blessing effects validate")

	var wrong_category = catalog.validate_effects({"heal": 20.0}, {"category": "curse"})
	suite.assert_true(wrong_category.has_blocking_errors(), "effect category compatibility fails closed")

	var missing_category = catalog.validate_effects({"heal": 20.0}, {})
	suite.assert_true(missing_category.has_blocking_errors(), "missing content category fails closed")


func _test_script_like_and_unknown_ids(suite, catalog) -> void:
	for effect_id: String in [
		"res://arbitrary.gd",
		"folder/effect",
		"folder\\effect",
		"../attack_multiplier",
		"arbitrary.gd",
		"unknown_effect",
	]:
		var report = catalog.validate_effects({effect_id: 1.0}, {"category": "item"})
		suite.assert_true(report.has_blocking_errors(), "unsafe or unknown effect id %s is rejected" % effect_id)

	var non_string_id = catalog.validate_effects({42: 1.0}, {"category": "item"})
	suite.assert_true(non_string_id.has_blocking_errors(), "non-string effect id is rejected")


func _test_scalar_types_and_numeric_bounds(suite, catalog) -> void:
	suite.assert_true(
		catalog.validate_effects({"rewind_echo_enabled": true}, {"category": "item"}).blocking_errors.is_empty(),
		"boolean effect accepts bool"
	)
	suite.assert_true(
		catalog.validate_effects({"rewind_echo_enabled": 1}, {"category": "item"}).has_blocking_errors(),
		"boolean effect rejects number"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": "1.18"}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects string"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": {}}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects dictionaries"
	)
	suite.assert_true(
		catalog.validate_effects({"bow_pierce_bonus": 1.5}, {"category": "item"}).has_blocking_errors(),
		"integer effect rejects fractional values"
	)
	suite.assert_true(
		catalog.validate_effects({"bow_pierce_bonus": 2.0}, {"category": "item"}).blocking_errors.is_empty(),
		"integer effect accepts integral JSON numbers"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": NAN}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects NaN"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": INF}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects infinity"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": 5.01}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects values above its maximum"
	)
	suite.assert_true(
		catalog.validate_effects({"max_hp_bonus": -1.0}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects values below its minimum"
	)
	suite.assert_true(
		catalog.validate_effects({"defense_bonus": -2.0}, {"category": "curse"}).blocking_errors.is_empty(),
		"signed defense bonus preserves the current curse"
	)


func _test_weapon_capability_mappings(suite, catalog) -> void:
	var damage_routes: Array[Dictionary] = catalog.weapon_capability_routes({"attack_multiplier": 1.25})
	suite.assert_equal(damage_routes.size(), 5, "generic damage effects declare one route per launch weapon")
	var routed_weapons: Array[String] = []
	for route: Dictionary in damage_routes:
		routed_weapons.append(str(route.get("weapon_id", "")))
		suite.assert_equal(route.get("capability"), "weapon.damage", "generic damage targets the damage capability")
		suite.assert_close(float(route.get("base_value", NAN)), 1.0, "generic damage starts from identity")
		suite.assert_equal(route.get("stack_rule"), "multiply", "generic damage preserves multiplicative stacking")
	suite.assert_equal(
		routed_weapons,
		["bow", "gauntlets", "gun", "staff", "sword"],
		"five-weapon routes are deterministic"
	)
	var sword_routes: Array[Dictionary] = catalog.weapon_capability_routes({
		"combo_finisher_multiplier_bonus": 0.35,
		"heavy_execute_threshold": 0.3,
	})
	suite.assert_equal(
		sword_routes,
		[
			{
				"effect_id": "combo_finisher_multiplier_bonus",
				"weapon_id": "sword",
				"capability": "weapon.combo_finisher_damage",
				"base_value": 0.0,
				"stack_rule": "add",
				"value": 0.35,
			},
			{
				"effect_id": "heavy_execute_threshold",
				"weapon_id": "sword",
				"capability": "weapon.heavy_execute_threshold",
				"base_value": 0.3,
				"stack_rule": "replace",
				"value": 0.3,
			},
		],
		"Sword reward semantics are represented by declared capabilities"
	)
	suite.assert_true(
		catalog.weapon_capability_routes({"attack_multiplier": 6.0}).is_empty(),
		"invalid effect values cannot produce executable routes"
	)


func _test_weapon_capability_schema_fails_closed(suite) -> void:
	var source := {
		"effect_id": "fixture_weapon_bonus",
		"value_type": "number",
		"minimum": 0.0,
		"maximum": 5.0,
		"stack_rule": "add",
		"allowed_categories": ["item"],
		"runtime_domain": "weapon",
		"weapon_capabilities": [
			{"weapon_id": "sword", "capability": "weapon.damage", "base_value": 1.0},
		],
	}
	var valid = EffectDefinitionScript.new()
	suite.assert_true(
		bool(valid.configure(source).get("ok", false)),
		"numeric stackable effects accept explicit weapon capability mappings"
	)

	var duplicate_weapon: Dictionary = source.duplicate(true)
	duplicate_weapon["weapon_capabilities"].append(
		{"weapon_id": "sword", "capability": "weapon.attack_speed", "base_value": 1.0}
	)
	var duplicate_result: Dictionary = EffectDefinitionScript.new().configure(duplicate_weapon)
	suite.assert_equal(
		duplicate_result.get("context", {}).get("reason"),
		"duplicate",
		"one effect cannot ambiguously route twice to the same weapon"
	)

	var boolean_mapping: Dictionary = source.duplicate(true)
	boolean_mapping["value_type"] = "boolean"
	boolean_mapping["minimum"] = null
	boolean_mapping["maximum"] = null
	var boolean_result: Dictionary = EffectDefinitionScript.new().configure(boolean_mapping)
	suite.assert_equal(
		boolean_result.get("context", {}).get("reason"),
		"numeric_effect_required",
		"boolean effects cannot become numeric weapon modifiers"
	)

	var trigger_mapping: Dictionary = source.duplicate(true)
	trigger_mapping["stack_rule"] = "trigger"
	var trigger_result: Dictionary = EffectDefinitionScript.new().configure(trigger_mapping)
	suite.assert_equal(
		trigger_result.get("context", {}).get("reason"),
		"unsupported_stack_rule",
		"trigger effects cannot declare persistent weapon capabilities"
	)

	var invalid_base: Dictionary = source.duplicate(true)
	invalid_base["weapon_capabilities"][0]["base_value"] = INF
	var base_result: Dictionary = EffectDefinitionScript.new().configure(invalid_base)
	suite.assert_equal(
		base_result.get("context", {}).get("reason"),
		"non_finite",
		"weapon capability bases reject non-finite values"
	)


func _test_deterministic_normalization(suite, catalog) -> void:
	var source := {
		"rewind_echo_enabled": true,
		"bow_pierce_bonus": 2.0,
		"attack_multiplier": 1,
	}
	var normalized: Dictionary = catalog.normalize_effects(source)
	suite.assert_equal(
		normalized.keys(),
		["attack_multiplier", "bow_pierce_bonus", "rewind_echo_enabled"],
		"normalized effect ids are sorted"
	)
	suite.assert_true(typeof(normalized["attack_multiplier"]) == TYPE_FLOAT, "number effects normalize to float")
	suite.assert_true(typeof(normalized["bow_pierce_bonus"]) == TYPE_INT, "integer effects normalize to int")
	suite.assert_true(typeof(normalized["rewind_echo_enabled"]) == TYPE_BOOL, "boolean effects remain bool")

	normalized["attack_multiplier"] = 4.0
	var repeated: Dictionary = catalog.normalize_effects(source)
	suite.assert_close(float(repeated["attack_multiplier"]), 1.0, "normalized dictionaries are isolated")
	suite.assert_true(catalog.normalize_effects({"unknown_effect": 1.0}).is_empty(), "invalid normalization fails closed")


func _test_snapshot_isolation(suite, catalog) -> void:
	var first: Array[Dictionary] = catalog.snapshot()
	var second: Array[Dictionary] = catalog.snapshot()
	suite.assert_true(not first.is_empty(), "catalog snapshot is populated")
	if first.is_empty() or second.is_empty():
		return
	first[0]["effect_id"] = "mutated"
	(first[1]["allowed_categories"] as Array).append("mutated")
	suite.assert_true(str(second[0]["effect_id"]) != "mutated", "snapshot rows are deep copied")
	suite.assert_true(not (second[1]["allowed_categories"] as Array).has("mutated"), "snapshot category arrays are isolated")
	suite.assert_equal(catalog.snapshot(), second, "snapshot mutation cannot change catalog authority")


func _test_missing_catalog_fails_closed(suite) -> void:
	var missing = EffectHandlerCatalogScript.new("res://tests/fixtures/content/does_not_exist_effect_catalog.json")
	suite.assert_true(missing.load_report().has_blocking_errors(), "missing catalog reports a blocking error")
	suite.assert_true(
		missing.validate_effects({"attack_multiplier": 1.0}, {"category": "item"}).has_blocking_errors(),
		"validation cannot proceed without a trusted catalog"
	)
	suite.assert_true(missing.normalize_effects({"attack_multiplier": 1.0}).is_empty(), "missing catalog normalization fails closed")


func _current_effect_ids(suite) -> Array[String]:
	var ids: Dictionary = {}
	for path: String in SOURCE_PATHS:
		for entry: Dictionary in _read_content_entries(path, suite):
			var effects: Dictionary = entry.get("effects", {})
			for effect_id_value: Variant in effects.keys():
				ids[str(effect_id_value)] = true
	var result: Array[String] = []
	for effect_id_value: Variant in ids.keys():
		result.append(str(effect_id_value))
	result.sort()
	return result


func _read_content_entries(path: String, suite) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "current content source %s opens" % path)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	suite.assert_true(parsed is Array, "current content source %s is an array" % path)
	if not parsed is Array:
		return []
	var entries: Array[Dictionary] = []
	for entry_value: Variant in parsed:
		if entry_value is Dictionary:
			entries.append((entry_value as Dictionary).duplicate(true))
	return entries
