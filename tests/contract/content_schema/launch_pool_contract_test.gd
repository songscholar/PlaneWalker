extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const LaunchPoolCatalogScript := preload("res://scripts/content/launch_pool_catalog.gd")
const ActiveItemDefinitionScript := preload("res://scripts/items/active_item_definition.gd")
const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")
const ContentPackDescriptorScript := preload("res://scripts/content/content_pack_descriptor.gd")

const CATALOG_PATH := "res://data/content/launch_pool_catalog.json"
const BASE_ITEMS_PATH := "res://data/content_packs/base/content/items.json"
const LEGACY_ITEMS_PATH := "res://data/items/mvp_items.json"
const BASE_LOCALIZATION_PATH := "res://data/content_packs/base/localization/translations.csv"
const LEGACY_LOCALIZATION_PATH := "res://data/localization/translations.csv"
const BASE_PACK_PATH := "res://data/content_packs/base/pack.json"
const EXPECTED_ITEMS := [
	"frozen_burst", "stasis_lens", "brittle_clock", "weakpoint_prism", "frozen_afterimage", "absolute_zero_device",
	"rewind_echo", "anchor_thread", "history_blade", "echo_reservoir", "pathbreaker_lens", "paradox_beacon",
	"rift_engine", "rift_anchor", "folded_corridor", "rift_conductor", "rift_snare", "gravity_snare_device",
	"accelerated_combo", "cadence_core", "overdrive_heart", "accelerant_window", "efficient_overdrive", "redline_injector",
	"void_brink", "void_contract", "hunger_edge", "abyssal_siphon", "blood_price_relic",
	"cleaving_moment", "evasive_guard_route", "counter_battery", "warded_edge", "aegis_reversal",
	"piercing_draw", "tempo_barrage", "focused_draw", "ricochet_matrix", "railshot_module",
	"mirror_seed", "phantom_lens", "legion_core", "decoy_crown", "army_of_yesterday",
	"chronal_battery", "quickened_blade", "rewind_salve", "rift_current", "sword_edge", "tempered_guard",
]
const EXPECTED_BLESSINGS := [
	"bls_stop_weakpoint", "bls_stasis_shatter", "bls_cold_execution",
	"bls_rewind_path", "bls_anchor_memory", "bls_echo_harvest",
	"bls_folded_ground", "bls_projectile_slow", "bls_rift_bloom",
	"bls_sword_tempo", "bls_cadence_chain", "bls_overdrive_refund",
	"bls_void_threshold", "bls_hunger_conversion", "bls_bloodless_focus",
	"bls_counter_window", "bls_guard_reserve", "bls_aegis_tempo",
	"bls_piercing_line", "bls_weakpoint_refund", "bls_ballistic_clock",
	"bls_mirror_action", "bls_legion_focus", "bls_decoy_stride",
	"bls_survive_thread", "bls_chronal_reserve", "bls_wayfinder_mercy", "bls_adaptive_arsenal",
]
const EXPECTED_CURSES := [
	"curse_stasis_fracture", "curse_thaw_debt", "curse_blood_memory", "curse_erased_present",
	"curse_starved_horizon", "curse_folded_hunger", "curse_glass_cadence", "curse_burnout_clock",
	"curse_brittle_pact", "curse_empty_veins", "curse_narrow_counter", "curse_shattered_aegis",
	"curse_recoil_tax", "curse_empty_magazine", "curse_divided_self", "curse_phantom_attention",
	"curse_fickle_time", "curse_brittle_fortune",
]
const EXPECTED_TALENTS := [
	"tal_eternity_reserve", "tal_ruin_execute", "tal_steel_recover",
	"widened_guard", "fortress_core", "temporal_rebuke",
	"deep_debt", "bounded_devour", "risk_step",
	"resonant_plate", "echo_forge", "realm_collapse",
	"codex_margin", "efficient_inscription", "dominion_cadence",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_exact_target_catalog(suite)
	_test_route_distribution(suite)
	_test_live_item_pool_contract(suite)
	_test_catalog_fail_closed(suite)
	_test_active_item_definition(suite)
	_test_all_active_handler_contracts(suite)
	suite.finish(get_tree())


func _test_exact_target_catalog(suite) -> void:
	var source_value: Variant = _read_json(CATALOG_PATH, suite)
	if not source_value is Dictionary:
		return
	var parser = LaunchPoolCatalogScript.new()
	var configured: Dictionary = parser.configure(source_value as Dictionary)
	suite.assert_true(bool(configured.get("ok", false)), "Launch pool target catalog configures: %s" % str(configured.get("context", {})))
	if not bool(configured.get("ok", false)):
		return
	var snapshot: Dictionary = parser.snapshot()
	suite.assert_equal(snapshot.get("schema_version"), 1, "Launch pool catalog schema is exact")
	var items: Array = snapshot.get("items", [])
	var blessings: Array = snapshot.get("blessings", [])
	var curses: Array = snapshot.get("curses", [])
	var talents: Array = snapshot.get("talents", [])
	suite.assert_equal(_ids(items), EXPECTED_ITEMS, "Launch item target identities are exact and ordered")
	suite.assert_equal(_ids(blessings), EXPECTED_BLESSINGS, "Launch blessing target identities are exact and ordered")
	suite.assert_equal(_ids(curses), EXPECTED_CURSES, "Launch curse target identities are exact and ordered")
	suite.assert_equal(_ids(talents), EXPECTED_TALENTS, "Launch talent target identities are exact and ordered")
	suite.assert_equal(items.size(), 50, "Launch target has exactly fifty items")
	suite.assert_equal(items.filter(func(row): return row.get("item_mode") == "passive").size(), 42, "Launch target has forty-two passive items")
	suite.assert_equal(items.filter(func(row): return row.get("item_mode") == "active").size(), 8, "Launch target has eight active items")
	suite.assert_equal(blessings.size(), 28, "Launch target has twenty-eight blessings")
	suite.assert_equal(curses.size(), 18, "Launch target has eighteen curses")
	suite.assert_equal(talents.size(), 15, "Launch target has fifteen talents")
	for archetype: String in ArchetypeProfileScript.ARCHETYPE_IDS:
		var active_for_route := items.filter(
			func(row): return row.get("item_mode") == "active" and row.get("archetype") == archetype
		)
		suite.assert_equal(active_for_route.size(), 1, "%s has exactly one active item target" % archetype)
	var utility_items := items.filter(func(row): return str(row.get("archetype", "")).is_empty())
	suite.assert_equal(utility_items.size(), 6, "Launch target keeps exactly six general utility items")


func _test_route_distribution(suite) -> void:
	var source_value: Variant = _read_json(CATALOG_PATH, suite)
	if not source_value is Dictionary:
		return
	var parser = LaunchPoolCatalogScript.new()
	var configured: Dictionary = parser.configure(source_value as Dictionary)
	suite.assert_true(bool(configured.get("ok", false)), "route distribution source configures")
	if not bool(configured.get("ok", false)):
		return
	var snapshot: Dictionary = parser.snapshot()
	var items: Array = snapshot.get("items", [])
	var blessings: Array = snapshot.get("blessings", [])
	var curses: Array = snapshot.get("curses", [])
	for archetype: String in ArchetypeProfileScript.ARCHETYPE_IDS:
		var route_items := items.filter(func(row): return row.get("archetype") == archetype)
		var expected_starters := 3 if archetype in [
			"freeze_burst", "rewind_echo", "rift_trap", "accelerated_combo",
		] else 2
		suite.assert_equal(
			route_items.filter(func(row): return row.get("role") == "starter").size(),
			expected_starters,
			"%s item starter distribution is exact" % archetype
		)
		suite.assert_equal(
			route_items.filter(func(row): return row.get("role") == "payoff").size(),
			2,
			"%s item payoff distribution is exact" % archetype
		)
		suite.assert_equal(
			route_items.filter(func(row): return row.get("role") == "risk").size(),
			1,
			"%s item risk distribution is exact" % archetype
		)
		var route_blessings := blessings.filter(func(row): return row.get("archetype") == archetype)
		suite.assert_equal(
			route_blessings.filter(func(row): return row.get("role") == "starter").size(),
			1,
			"%s blessing starter distribution is exact" % archetype
		)
		suite.assert_equal(
			route_blessings.filter(func(row): return row.get("role") == "payoff").size(),
			2,
			"%s blessing payoff distribution is exact" % archetype
		)
		suite.assert_equal(
			curses.filter(func(row): return row.get("archetype") == archetype).size(),
			2,
			"%s curse risk distribution is exact" % archetype
		)


func _test_live_item_pool_contract(suite) -> void:
	var target_value: Variant = _read_json(CATALOG_PATH, suite)
	var base_value: Variant = _read_json(BASE_ITEMS_PATH, suite)
	var legacy_value: Variant = _read_json(LEGACY_ITEMS_PATH, suite)
	if not target_value is Dictionary or not base_value is Array or not legacy_value is Array:
		return
	var target_parser = LaunchPoolCatalogScript.new()
	var target_result: Dictionary = target_parser.configure(target_value as Dictionary)
	suite.assert_true(bool(target_result.get("ok", false)), "live item target catalog configures")
	if not bool(target_result.get("ok", false)):
		return
	var target_items: Array = target_parser.snapshot().get("items", [])
	var base_items := base_value as Array
	var legacy_items := legacy_value as Array
	suite.assert_equal(_ids(base_items), EXPECTED_ITEMS, "Base Pack exposes the exact ordered fifty-item Launch pool")
	suite.assert_equal(_ids(legacy_items), EXPECTED_ITEMS, "legacy mirror exposes the exact ordered fifty-item Launch pool")
	_assert_legacy_item_semantics(suite, legacy_items, base_items)
	var target_by_id := _rows_by_id(target_items)
	var base_localization := _localization_keys(BASE_LOCALIZATION_PATH, suite)
	var legacy_localization := _localization_keys(LEGACY_LOCALIZATION_PATH, suite)
	var passive_count := 0
	var active_count := 0
	for item_value: Variant in base_items:
		if not item_value is Dictionary:
			suite.assert_true(false, "every live item is a dictionary")
			continue
		var item := item_value as Dictionary
		var content_id := str(item.get("id", ""))
		var target: Dictionary = target_by_id.get(content_id, {})
		suite.assert_true(not target.is_empty(), "%s exists in the approved target catalog" % content_id)
		if target.is_empty():
			continue
		suite.assert_equal(item.get("category"), "item", "%s remains an item" % content_id)
		suite.assert_equal(item.get("archetype", ""), target.get("archetype", ""), "%s archetype is exact" % content_id)
		suite.assert_equal(item.get("role", ""), target.get("role", ""), "%s role is exact" % content_id)
		suite.assert_equal(item.get("item_mode", ""), target.get("item_mode", ""), "%s mode is exact" % content_id)
		var availability := item.get("availability", []) as Array
		suite.assert_true(availability.has("LAUNCH"), "%s is available at Launch" % content_id)
		suite.assert_true(availability.has("EXPANSION"), "%s remains available to Expansion" % content_id)
		var tags := item.get("tags", []) as Array
		var item_mode := str(item.get("item_mode", ""))
		suite.assert_true(tags.has(item_mode), "%s tags expose its item mode" % content_id)
		if item_mode == "passive":
			passive_count += 1
			suite.assert_true(not (item.get("effects", {}) as Dictionary).is_empty(), "%s passive has executable effects" % content_id)
			suite.assert_true(not item.has("active_handler_id"), "%s passive has no active handler" % content_id)
		else:
			active_count += 1
			suite.assert_true((item.get("effects", {}) as Dictionary).is_empty(), "%s active reserves execution for its handler" % content_id)
			suite.assert_true(not str(item.get("active_handler_id", "")).is_empty(), "%s active declares a handler" % content_id)
			var active_result: Dictionary = ActiveItemDefinitionScript.new().configure(item.duplicate(true))
			suite.assert_true(bool(active_result.get("ok", false)), "%s live active definition is executable: %s" % [content_id, str(active_result.get("context", {}))])
		if str(item.get("archetype", "")).is_empty():
			suite.assert_true(tags.has("generalist") and tags.has("utility") and tags.has("passive"), "%s utility tags are complete" % content_id)
		var name_key := str(item.get("name_key", ""))
		var description_key := str(item.get("description_key", ""))
		for localization: Dictionary in [base_localization, legacy_localization]:
			suite.assert_true(localization.has(name_key), "%s name is localized" % content_id)
			suite.assert_true(localization.has(description_key), "%s description is localized" % content_id)
	suite.assert_equal(passive_count, 42, "live Launch pool has exactly forty-two passives")
	suite.assert_equal(active_count, 8, "live Launch pool has exactly eight actives")
	var pack_result: Dictionary = ContentPackDescriptorScript.load_path(BASE_PACK_PATH, true)
	suite.assert_true(bool(pack_result.get("ok", false)), "Base Pack item and localization integrity hashes are current: %s" % str(pack_result.get("context", {})))


func _test_catalog_fail_closed(suite) -> void:
	var source_value: Variant = _read_json(CATALOG_PATH, suite)
	if not source_value is Dictionary:
		return
	var cases: Array[Dictionary] = [
		_case("unknown root", func(value): value["script_path"] = "res://hostile.gd"),
		_case("wrong schema", func(value): value["schema_version"] = 2),
		_case("duplicate item", func(value): value["items"].append(value["items"][0].duplicate(true))),
		_case("unknown archetype", func(value): value["items"][0]["archetype"] = "heavy_cleave"),
		_case("active utility", func(value): value["items"][44]["item_mode"] = "active"),
		_case("item role drift", func(value): value["items"][0]["role"] = "payoff"),
		_case("item route drift", func(value): value["items"][0]["archetype"] = "rewind_echo"),
		_case("blessing route drift", func(value): value["blessings"][0]["archetype"] = "rewind_echo"),
		_case("blessing role drift", func(value): value["blessings"][0]["role"] = "starter"),
		_case("curse route drift", func(value): value["curses"][0]["archetype"] = "rewind_echo"),
		_case("wrong talent owner", func(value): value["talents"][0]["character_id"] = "time_lord"),
	]
	for invalid_case: Dictionary in cases:
		var source: Dictionary = (source_value as Dictionary).duplicate(true)
		(invalid_case["mutate"] as Callable).call(source)
		var result: Dictionary = LaunchPoolCatalogScript.new().configure(source)
		suite.assert_true(not bool(result.get("ok", false)), "%s fails closed" % invalid_case["label"])


func _test_active_item_definition(suite) -> void:
	var source := _active_fixture()
	var parser = ActiveItemDefinitionScript.new()
	var configured: Dictionary = parser.configure(source)
	suite.assert_true(bool(configured.get("ok", false)), "active item definition configures")
	if bool(configured.get("ok", false)):
		var snapshot: Dictionary = parser.snapshot()
		suite.assert_equal(snapshot.get("active_handler_id"), "absolute_zero", "handler identity is stable")
		suite.assert_equal(snapshot.get("cooldown_frames"), 900, "cooldown is preserved")
		(snapshot.get("active_parameters", {}) as Dictionary)["radius"] = 9999.0
		suite.assert_equal(parser.snapshot().get("active_parameters", {}).get("radius"), 180.0, "parameter snapshot is isolated")
	var json_numeric_source := source.duplicate(true)
	json_numeric_source["cooldown_frames"] = 900.0
	suite.assert_true(
		bool(ActiveItemDefinitionScript.new().configure(json_numeric_source).get("ok", false)),
		"integral JSON numeric cooldown normalizes"
	)

	var cases: Array[Dictionary] = [
		_case("missing handler", func(value): value.erase("active_handler_id")),
		_case("unknown handler", func(value): value["active_handler_id"] = "run_script"),
		_case("zero cooldown", func(value): value["cooldown_frames"] = 0),
		_case("long cooldown", func(value): value["cooldown_frames"] = 3601),
		_case("wrong archetype", func(value): value["archetype"] = "heavy_cleave"),
		_case("wrong role", func(value): value["role"] = "payoff"),
		_case("passive mode", func(value): value["item_mode"] = "passive"),
		_case("wrong handler for route", _mutate_active_handler_mismatch),
		_case("wrong archetype for item", _mutate_active_archetype_mismatch),
		_case("valid item identity mismatch", func(value): value["id"] = "paradox_beacon"),
		_case("unknown active item", func(value): value["id"] = "other_zero_device"),
		_case("missing parameter", func(value): value["active_parameters"].erase("energy_cost")),
		_case("unknown parameter", func(value): value["active_parameters"]["script"] = "run"),
		_case("out of range", func(value): value["active_parameters"]["radius"] = 513.0),
		_case("script-like value", func(value): value["active_parameters"]["label"] = "res://hostile.gd"),
	]
	for invalid_case: Dictionary in cases:
		var value: Dictionary = source.duplicate(true)
		(invalid_case["mutate"] as Callable).call(value)
		var invalid_parser = ActiveItemDefinitionScript.new()
		var result: Dictionary = invalid_parser.configure(value)
		suite.assert_true(not bool(result.get("ok", false)), "%s fails closed" % invalid_case["label"])
		suite.assert_equal(invalid_parser.snapshot().get("id"), "", "%s leaves no stale configured identity" % invalid_case["label"])


func _test_all_active_handler_contracts(suite) -> void:
	var cases: Array[Dictionary] = [
		{"id": "absolute_zero_device", "archetype": "freeze_burst", "handler": "absolute_zero", "parameters": {"radius": 180.0, "duration_frames": 180, "weakpoint_bonus": 0.5, "energy_cost": 35.0}},
		{"id": "paradox_beacon", "archetype": "rewind_echo", "handler": "paradox_beacon", "parameters": {"rewind_frames": 180, "echo_damage_multiplier": 0.8, "energy_cost": 30.0}},
		{"id": "gravity_snare_device", "archetype": "rift_trap", "handler": "gravity_snare", "parameters": {"radius": 220.0, "duration_frames": 240, "slow_ratio": 0.45, "energy_cost": 35.0}},
		{"id": "redline_injector", "archetype": "accelerated_combo", "handler": "redline_injector", "parameters": {"duration_frames": 240, "speed_multiplier": 1.5, "health_cost_ratio": 0.12}},
		{"id": "blood_price_relic", "archetype": "low_hp_void", "handler": "blood_price", "parameters": {"duration_frames": 240, "damage_multiplier": 1.8, "health_cost_ratio": 0.18}},
		{"id": "aegis_reversal", "archetype": "perfect_guard", "handler": "aegis_reversal", "parameters": {"duration_frames": 180, "counter_multiplier": 1.5, "energy_cost": 25.0}},
		{"id": "railshot_module", "archetype": "piercing_barrage", "handler": "railshot", "parameters": {"pierce_bonus": 4, "damage_multiplier": 1.6, "ammo_refund": 2}},
		{"id": "army_of_yesterday", "archetype": "echo_legion", "handler": "army_of_yesterday", "parameters": {"echo_count": 3, "duration_frames": 300, "echo_damage_multiplier": 0.45, "energy_cost": 40.0}},
	]
	for handler_case: Dictionary in cases:
		var definition := _active_fixture_for(
			str(handler_case["id"]),
			str(handler_case["archetype"]),
			str(handler_case["handler"]),
			handler_case["parameters"] as Dictionary
		)
		var result: Dictionary = ActiveItemDefinitionScript.new().configure(definition)
		suite.assert_true(
			bool(result.get("ok", false)),
			"%s active parameter contract configures: %s" % [str(handler_case["handler"]), str(result.get("context", {}))]
		)

	var fractional_integer := _active_fixture_for(
		"railshot_module",
		"piercing_barrage",
		"railshot",
		{"pierce_bonus": 1.5, "damage_multiplier": 1.6, "ammo_refund": 2}
	)
	suite.assert_true(
		not bool(ActiveItemDefinitionScript.new().configure(fractional_integer).get("ok", false)),
		"integer active parameters reject fractional values"
	)


func _active_fixture() -> Dictionary:
	return _active_fixture_for(
		"absolute_zero_device",
		"freeze_burst",
		"absolute_zero",
		{
			"radius": 180.0,
			"duration_frames": 180,
			"weakpoint_bonus": 0.5,
			"energy_cost": 35.0,
		}
	)


func _active_fixture_for(
	content_id: String,
	archetype: String,
	handler_id: String,
	parameters: Dictionary
) -> Dictionary:
	return {
		"id": content_id,
		"category": "item",
		"availability": ["LAUNCH", "EXPANSION"],
		"name_key": "ABSOLUTE_ZERO_DEVICE_NAME",
		"description_key": "ABSOLUTE_ZERO_DEVICE_DESC",
		"tags": ["active", archetype, "risk"],
		"compatibility": {"archetype_ids": [archetype]},
		"effects": {},
		"kind": "time",
		"archetype": archetype,
		"role": "risk",
		"rarity": "rare",
		"icon_id": "content_%s" % content_id,
		"item_mode": "active",
		"active_handler_id": handler_id,
		"cooldown_frames": 900,
		"active_parameters": parameters.duplicate(true),
	}


func _ids(rows: Array) -> Array[String]:
	var result: Array[String] = []
	for row_value: Variant in rows:
		if row_value is Dictionary:
			result.append(str((row_value as Dictionary).get("id", "")))
	return result


func _rows_by_id(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row_value: Variant in rows:
		if row_value is Dictionary:
			result[str((row_value as Dictionary).get("id", ""))] = (row_value as Dictionary).duplicate(true)
	return result


func _assert_legacy_item_semantics(suite, legacy_items: Array, base_items: Array) -> void:
	var mirrored_fields: Array[String] = [
		"id", "availability", "kind", "archetype", "role", "item_mode", "effects",
	]
	var active_fields: Array[String] = [
		"active_handler_id", "cooldown_frames", "active_parameters",
	]
	for index: int in range(base_items.size()):
		var base: Dictionary = base_items[index]
		var legacy: Dictionary = legacy_items[index]
		var content_id := str(base.get("id", ""))
		suite.assert_equal(legacy.get("name"), base.get("name_key"), "%s legacy name key mirrors v2" % content_id)
		suite.assert_equal(legacy.get("description"), base.get("description_key"), "%s legacy description key mirrors v2" % content_id)
		for field: String in mirrored_fields:
			suite.assert_equal(legacy.get(field), base.get(field), "%s legacy %s mirrors v2" % [content_id, field])
		if str(base.get("item_mode", "")) == "active":
			for field: String in active_fields:
				suite.assert_equal(legacy.get(field), base.get(field), "%s legacy %s mirrors v2" % [content_id, field])


func _localization_keys(path: String, suite) -> Dictionary:
	suite.assert_true(FileAccess.file_exists(path), "%s exists" % path)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s can be opened" % path)
	if file == null:
		return {}
	var result: Dictionary = {}
	var header := file.get_csv_line()
	suite.assert_equal(Array(header), ["keys", "en", "zh_CN"], "%s localization header is exact" % path)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty() or str(row[0]).is_empty():
			continue
		result[str(row[0])] = true
	return result


func _case(label: String, mutate: Callable) -> Dictionary:
	return {"label": label, "mutate": mutate}


func _mutate_active_handler_mismatch(value: Dictionary) -> void:
	value["active_handler_id"] = "railshot"
	value["active_parameters"] = {
		"pierce_bonus": 4,
		"damage_multiplier": 1.6,
		"ammo_refund": 2,
	}


func _mutate_active_archetype_mismatch(value: Dictionary) -> void:
	value["archetype"] = "rewind_echo"
	value["tags"] = ["active", "rewind_echo", "risk"]
	value["compatibility"] = {"archetype_ids": ["rewind_echo"]}


func _read_json(path: String, suite) -> Variant:
	suite.assert_true(FileAccess.file_exists(path), "%s exists" % path)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s can be opened" % path)
	if file == null:
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	suite.assert_equal(error, OK, "%s contains valid JSON" % path)
	return parser.data if error == OK else {}
