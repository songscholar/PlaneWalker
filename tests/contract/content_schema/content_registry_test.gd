extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const ContentSnapshotProviderScript := preload("res://scripts/content/content_snapshot_provider.gd")
const EffectHandlerCatalogScript := preload("res://scripts/content/effects/effect_handler_catalog.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")
const CharacterRuntimeProfileScript := preload("res://scripts/player/characters/character_runtime_profile.gd")
const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")
const EXPECTED_BASE_CATEGORY_COUNTS := {
	"character": 5,
	"character_runtime_profile": 6,
	"weapon": 5,
	"weapon_runtime_profile": 7,
	"archetype_profile": 8,
	"time_ability": 4,
	"item": 50,
	"blessing": 28,
	"curse": 24,
	"talent": 15,
	"floor_definition": 5,
	"room_template": 30,
	"dungeon_event": 18,
	"merchant_definition": 5,
	"economy_profile": 1,
	"enemy_definition": 22,
	"boss_definition": 5,
	"summon_definition": 9,
	"elite_affix_definition": 10,
	"launch_encounter_profile": 5,
	"launch_encounter_extension": 2,
	"meta_node": 42,
	"hub_district": 3,
	"forge_definition": 20,
	"narrative_definition": 57,
	"narrative_source_definition": 13,
	"tutorial_definition": 34,
	"cosmetic_definition": 15,
}
const EXPECTED_FLOOR_IDS: Array[String] = [
	"floor_ruins_of_remnant",
	"floor_void_forest",
	"floor_time_rift",
	"floor_plane_forge",
	"floor_throne_of_void",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_project_base_pack_v2(suite)
	_test_p14_specialized_registry_contract(suite)
	_test_specialized_nested_localization_and_reference_closure(suite)
	_test_required_specialized_pack_failure_is_atomic(suite)
	_test_optional_pack_isolation(suite)
	_test_required_invalid_pack_blocks(suite)
	_test_project_manifest(suite)
	_test_fixture_manifest(suite)
	_test_file_and_root_errors(suite)
	_test_manifest_validation(suite)
	_test_m1_source_failures_are_blocking(suite)
	_test_m1_declarations_are_complete(suite)
	_test_override_validation(suite)
	_test_duplicate_ids(suite)
	_test_required_fields(suite)
	_test_next_content_isolation(suite)
	_test_identity_effect_boundary(suite)
	_test_effect_capability_profile_validation(suite)
	_test_active_item_entry_boundary(suite)
	_test_launch_reward_routing_boundary(suite)
	_test_archetype_profile_entry_boundary(suite)
	_test_archetype_reference_closure(suite)
	suite.finish(get_tree())


func _test_project_base_pack_v2(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": "res://data/content_packs/base/pack.json", "required": true}],
		"0.4.0-dev",
		&"M1"
	)
	suite.assert_true(not report.has_blocking_errors(), "project base pack activates: %s" % str(report.blocking_errors))
	if report.has_blocking_errors():
		return
	suite.assert_equal(report.active_pack_count, 1, "project base pack is the only active pack")
	suite.assert_equal(report.loaded_count, _expected_base_content_total(), "project base pack count matches its exact category contract")
	for category: String in EXPECTED_BASE_CATEGORY_COUNTS:
		suite.assert_equal(
			report.content_count_by_category.get(category),
			EXPECTED_BASE_CATEGORY_COUNTS[category],
			"base pack %s count is exact" % category
		)
	suite.assert_equal(report.metadata.get("activation_order"), ["base"], "base activation order is recorded")
	suite.assert_true(registry.has_method("get_archetype_profiles"), "Registry exposes milestone-aware archetype queries")
	suite.assert_true(registry.has_method("get_archetype_profile"), "Registry exposes archetype identity lookup")
	if registry.has_method("get_archetype_profiles") and registry.has_method("get_archetype_profile"):
		var launch_profiles: Array = registry.call("get_archetype_profiles", &"LAUNCH")
		var launch_ids: Array[String] = []
		for profile_value: Variant in launch_profiles:
			if profile_value is Dictionary:
				launch_ids.append(str((profile_value as Dictionary).get("archetype_id", "")))
		suite.assert_equal(launch_ids, ArchetypeProfileScript.ARCHETYPE_IDS, "Launch resolves the exact ordered archetype taxonomy")
		suite.assert_true(
			(registry.call("get_archetype_profiles", &"M1") as Array).is_empty(),
			"Launch archetype profiles do not widen M1"
		)
		var freeze_profile: Dictionary = registry.call("get_archetype_profile", &"freeze_burst")
		suite.assert_equal(freeze_profile.get("archetype_id"), "freeze_burst", "archetype lookup resolves by stable identity")
		suite.assert_true(not freeze_profile.has("pack_id"), "archetype lookup strips pack provenance")
		suite.assert_true(not freeze_profile.has("category"), "archetype lookup returns the runtime snapshot instead of its content envelope")
	var sword_profile: Dictionary = registry.get_weapon_runtime_profile(&"sword_m1_v1")
	suite.assert_equal(sword_profile.get("weapon_id"), "sword", "profile lookup resolves its weapon")
	suite.assert_equal(sword_profile.get("availability"), ["CURRENT", "M1"], "M1 Sword profile covers CURRENT and M1")
	suite.assert_true(not sword_profile.has("kind"), "runtime profile lookup removes generic content envelope fields")
	suite.assert_true(not sword_profile.has("pack_id"), "runtime profile lookup removes pack provenance before runtime use")
	suite.assert_true(
		bool(WeaponRuntimeProfileScript.new().configure(sword_profile).get("ok", false)),
		"runtime profile lookup returns an exact parser-ready snapshot"
	)
	suite.assert_equal(
		_action_by_id(sword_profile, "light_1").get("cooldown_frames"),
		0,
		"canonical registry profiles serialize omitted cooldowns as zero"
	)
	var m1_character_profile: Dictionary = registry.get_character_runtime_profile(&"wanderer_m1_v1")
	suite.assert_equal(m1_character_profile.get("character_id"), "wanderer", "character profile lookup resolves its character")
	suite.assert_equal(m1_character_profile.get("availability"), ["CURRENT", "M1", "NEXT"], "M1 Wanderer profile remains milestone-isolated")
	suite.assert_equal(m1_character_profile.get("runtime_kind"), "wanderer_m1_compat", "M1 Wanderer uses the compatibility runtime")
	suite.assert_true(not m1_character_profile.has("pack_id"), "character runtime profile strips pack provenance")
	suite.assert_true(
		bool(CharacterRuntimeProfileScript.new().configure(m1_character_profile).get("ok", false)),
		"character profile lookup returns an exact parser-ready snapshot"
	)
	var launch_character_profile: Dictionary = registry.resolve_character_runtime_profile(&"time_lord", &"LAUNCH")
	suite.assert_equal(launch_character_profile.get("id"), "time_lord_launch_v1", "milestone resolver returns one Launch character profile")
	suite.assert_true(registry.resolve_character_runtime_profile(&"time_lord", &"M1").is_empty(), "Launch character profile cannot resolve in M1")
	launch_character_profile["base_stats"]["max_hp"] = 999
	suite.assert_equal(
		registry.resolve_character_runtime_profile(&"time_lord", &"LAUNCH").get("base_stats", {}).get("max_hp"),
		175.0,
		"character profile resolver returns deep copies"
	)

	var bow_candidate: Dictionary = registry.get_weapon_runtime_profile(&"bow_candidate_v1")
	var candidate_draw := _action_by_id(bow_candidate, "candidate_draw")
	suite.assert_equal(
		candidate_draw.get("cooldown_frames"),
		21,
		"Bow candidate draw preserves the authoritative 0.35-second cooldown"
	)
	suite.assert_equal(
		candidate_draw.get("maximum_hold_frames"),
		54,
		"Bow candidate maximum charge is Profile authoritative"
	)
	suite.assert_true(
		bow_candidate.get("capabilities", []).has("weapon.full_charge_damage"),
		"Bow candidate declares the migrated full-charge modifier capability"
	)
	var bow_launch: Dictionary = registry.get_weapon_runtime_profile(&"bow_launch_v1")
	var precision_draw := _action_by_id(bow_launch, "precision_draw")
	suite.assert_equal(
		precision_draw.get("cooldown_frames"),
		0,
		"Launch precision draw relies on tier recovery instead of Candidate cooldown"
	)
	suite.assert_equal(
		precision_draw.get("maximum_hold_frames"),
		228,
		"Launch precision draw preserves the three-second full-charge hold"
	)
	suite.assert_equal(
		_payload_by_id(bow_launch, "bow_launch_arrow").get("parameters", {}).get("full_charge_frames"),
		48,
		"Launch precision draw reaches full charge at frame forty-eight"
	)
	suite.assert_true(
		bow_launch.get("capabilities", []).has("weapon.full_charge_damage"),
		"Launch Bow preserves the migrated full-charge modifier capability"
	)
	suite.assert_equal(
		_action_by_id(bow_launch, "scatter_shot").get("cooldown_frames"),
		120,
		"Launch scatter cooldown is Profile authoritative"
	)
	suite.assert_equal(
		_action_by_id(bow_launch, "focus_step").get("cooldown_frames"),
		0,
		"Launch utility without a declared cooldown normalizes to zero"
	)
	suite.assert_equal(
		_action_by_id(bow_launch, "temporal_arrow").get("cooldown_frames"),
		300,
		"Temporal Arrow cooldown is Profile authoritative"
	)
	suite.assert_equal(
		_action_by_id(bow_launch, "temporal_arrow").get("resource_costs", {}).get("time_energy"),
		30.0,
		"Temporal Arrow Time Energy cost is Profile authoritative"
	)
	suite.assert_equal(
		_action_by_id(bow_launch, "starfall_arrow_rain").get("cooldown_frames"),
		900,
		"Starfall cooldown is Profile authoritative"
	)
	suite.assert_equal(
		_action_by_id(bow_launch, "starfall_arrow_rain").get("resource_costs", {}).get("time_energy"),
		70.0,
		"Starfall Time Energy cost is Profile authoritative"
	)

	var frozen_burst: Dictionary = registry.get_content(&"frozen_burst")
	suite.assert_equal(frozen_burst.get("pack_id"), "base", "v2 content records owning pack")
	suite.assert_equal(frozen_burst.get("archetype"), "freeze_burst", "v2 content uses authoritative freeze archetype")
	suite.assert_equal(registry.get_content(&"rift_snare").get("archetype"), "rift_trap", "v2 content uses authoritative rift archetype")
	suite.assert_equal(registry.get_content(&"piercing_draw").get("archetype"), "piercing_barrage", "v2 content uses authoritative ranged archetype")
	suite.assert_equal(registry.get_content(&"tal_ruin_execute").get("archetype"), "", "M1 character talent remains a generalist instead of leaking a Launch-only route")
	suite.assert_true(registry.get_content(&"piercing_draw").get("availability", []).has("NEXT"), "future bow content remains preserved")
	suite.assert_equal(registry.get_by_category(&"item", &"M1").size(), 8, "M1 item eligibility remains unchanged")
	suite.assert_true(not registry.get_by_tag(&"piercing_barrage", &"NEXT").is_empty(), "tag query exposes normalized route")

	var snapshot: Dictionary = ContentSnapshotProviderScript.snapshot(registry)
	suite.assert_equal(snapshot.get("packs", []).size(), 1, "activated registry produces one save snapshot row")
	if not snapshot.get("packs", []).is_empty():
		suite.assert_equal(snapshot.get("packs", [])[0].get("pack_id"), "base", "save snapshot identifies base pack")
	suite.assert_equal(str(snapshot.get("aggregate_sha256", "")).length(), 64, "save snapshot has aggregate sha256")

	var active_copy: Array[Dictionary] = registry.active_packs()
	active_copy[0]["pack_id"] = "mutated"
	suite.assert_equal(registry.active_packs()[0].get("pack_id"), "base", "active pack getter returns deep copies")


func _test_p14_specialized_registry_contract(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": "res://data/content_packs/base/pack.json", "required": true}],
		"0.4.0-dev",
		&"LAUNCH"
	)
	suite.assert_true(not report.has_blocking_errors(), "P14 specialized Base Pack activates: %s" % str(report.blocking_errors))
	if report.has_blocking_errors():
		return
	for method_name: String in [
		"resolve_floor",
		"resolve_room_template",
		"resolve_dungeon_event",
		"resolve_merchant",
		"resolve_economy_profile",
		"get_floor_definitions",
	]:
		suite.assert_true(registry.has_method(method_name), "Registry exposes %s" % method_name)
	if not registry.has_method("get_floor_definitions"):
		return
	var floors: Array = registry.call("get_floor_definitions", &"LAUNCH")
	var floor_ids: Array[String] = []
	for floor_value: Variant in floors:
		if floor_value is Dictionary:
			floor_ids.append(str((floor_value as Dictionary).get("id", "")))
	suite.assert_equal(floor_ids, EXPECTED_FLOOR_IDS, "floor API preserves authoritative order instead of ID order")
	suite.assert_true(
		(registry.call("get_floor_definitions", &"M1") as Array).is_empty(),
		"Launch floors do not widen M1"
	)
	if floors.is_empty():
		return
	var mutated_floor: Dictionary = (floors[0] as Dictionary).duplicate(true)
	mutated_floor["merchant_ids"] = ["mutated_merchant"]
	floors[0] = mutated_floor
	var fresh_floors: Array = registry.call("get_floor_definitions", &"LAUNCH")
	suite.assert_true(
		not ((fresh_floors[0] as Dictionary).get("merchant_ids", []) as Array).has("mutated_merchant"),
		"ordered floor API returns deep copies"
	)
	var resolved_floor: Dictionary = registry.call("resolve_floor", &"floor_ruins_of_remnant")
	resolved_floor["required_room_budgets"] = {"mutated": 999}
	suite.assert_true(
		not (registry.call("resolve_floor", &"floor_ruins_of_remnant") as Dictionary)
			.get("required_room_budgets", {}).has("mutated"),
		"specialized resolver returns a deep copy"
	)
	suite.assert_equal(
		(registry.call("resolve_room_template", &"room_combat_pillared_hall") as Dictionary).get("category"),
		"room_template",
		"room resolver enforces its specialized category"
	)
	suite.assert_equal(
		(registry.call("resolve_dungeon_event", &"event_chronal_altar") as Dictionary).get("category"),
		"dungeon_event",
		"event resolver enforces its specialized category"
	)
	suite.assert_equal(
		(registry.call("resolve_merchant", &"merchant_wayfarer") as Dictionary).get("category"),
		"merchant_definition",
		"merchant resolver enforces its specialized category"
	)
	suite.assert_equal(
		(registry.call("resolve_economy_profile", &"launch_economy_v1") as Dictionary).get("category"),
		"economy_profile",
		"economy resolver enforces its specialized category"
	)


func _test_specialized_nested_localization_and_reference_closure(suite) -> void:
	var registry = ContentRegistryScript.new()
	suite.assert_true(
		registry.has_method("_nested_localization_error"),
		"Registry exposes one recursive specialized localization boundary"
	)
	if registry.has_method("_nested_localization_error"):
		var nested_source := {
			"name_key": "KNOWN_NAME",
			"options": [
				{
					"label_key": "KNOWN_OPTION",
					"outcomes": [
						{"id": "success", "outcome_key": "KNOWN_OUTCOME"},
					],
				},
			],
		}
		var known_keys := {
			"KNOWN_NAME": true,
			"KNOWN_OPTION": true,
			"KNOWN_OUTCOME": true,
		}
		suite.assert_equal(
			registry.call("_nested_localization_error", nested_source, known_keys),
			{},
			"recursive localization accepts every known nested key"
		)
		var missing_keys: Dictionary = known_keys.duplicate(true)
		missing_keys.erase("KNOWN_OUTCOME")
		var localization_error: Dictionary = registry.call(
			"_nested_localization_error",
			nested_source,
			missing_keys
		)
		suite.assert_equal(
			localization_error.get("field"),
			"options[0].outcomes[0].outcome_key",
			"recursive localization identifies the exact nested field"
		)
		suite.assert_equal(
			localization_error.get("reason"),
			"missing_localization",
			"recursive localization fails closed on missing keys"
		)

	var report = registry.load_packs(
		[{"path": "res://data/content_packs/base/pack.json", "required": true}],
		"0.4.0-dev",
		&"LAUNCH"
	)
	if report.has_blocking_errors():
		return
	var definitions: Array[Dictionary] = registry.all_content()
	for index: int in range(definitions.size()):
		if str(definitions[index].get("id", "")) != "floor_ruins_of_remnant":
			continue
		var broken_floor: Dictionary = definitions[index].duplicate(true)
		broken_floor["economy_profile_id"] = "missing_economy_profile"
		definitions[index] = broken_floor
		break
	var reference_error: Dictionary = registry.call(
		"_first_reference_error",
		definitions,
		_known_ids(definitions)
	)
	suite.assert_equal(reference_error.get("content_id"), "floor_ruins_of_remnant", "cross-reference error identifies the floor")
	suite.assert_equal(reference_error.get("field"), "economy_profile_id", "cross-reference error identifies the specialized field")
	suite.assert_equal(reference_error.get("reference_id"), "missing_economy_profile", "cross-reference error identifies the missing target")

	var launch_curse_ids: Array[String] = []
	for curse_value: Variant in registry.get_by_category(&"curse", &"LAUNCH"):
		if curse_value is Dictionary:
			launch_curse_ids.append(str((curse_value as Dictionary).get("id", "")))
	var launch_reward_pools := {
		"item": registry.get_by_category(&"item", &"LAUNCH"),
		"blessing": registry.get_by_category(&"blessing", &"LAUNCH"),
		"rare_item": _content_with_rarity(registry.get_by_category(&"item", &"LAUNCH"), "rare"),
		"rare_blessing": _content_with_rarity(registry.get_by_category(&"blessing", &"LAUNCH"), "rare"),
	}
	var closed_resources: Array[String] = ["gold", "time_shard", "forge_essence"]
	var closed_modifiers: Array[String] = [
		"chronal_grace", "weapon_temper", "past_strength", "paradox_echo",
		"tranquility", "void_bargain_power", "void_bargain_guard", "heroic_guard",
		"heroic_assault",
	]
	for pool_id: String in launch_reward_pools:
		suite.assert_true(not (launch_reward_pools[pool_id] as Array).is_empty(), "%s resolves a real Launch reward pool" % pool_id)
	for event_value: Variant in registry.get_by_category(&"dungeon_event", &"LAUNCH"):
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		for option_value: Variant in event.get("options", []):
			if not option_value is Dictionary:
				continue
			var option: Dictionary = option_value
			for outcome_value: Variant in option.get("outcomes", []):
				if not outcome_value is Dictionary:
					continue
				for consequence_value: Variant in (outcome_value as Dictionary).get("consequences", []):
					if not consequence_value is Dictionary:
						continue
					var arguments: Dictionary = (consequence_value as Dictionary).get("arguments", {})
					if arguments.has("curse_id"):
						suite.assert_true(launch_curse_ids.has(str(arguments["curse_id"])), "event curse reference closes against Launch content")
					if arguments.has("pool_id"):
						suite.assert_true(launch_reward_pools.has(str(arguments["pool_id"])), "event reward pool reference is closed")
					if arguments.has("resource"):
						suite.assert_true(closed_resources.has(str(arguments["resource"])), "event resource reference is closed")
					if arguments.has("modifier_id"):
						suite.assert_true(closed_modifiers.has(str(arguments["modifier_id"])), "event modifier reference is closed")


func _test_required_specialized_pack_failure_is_atomic(suite) -> void:
	var source_rows: Variant = _read_json_value("res://data/content_packs/base/content/floors.json")
	if not source_rows is Array or (source_rows as Array).is_empty():
		suite.assert_true(false, "atomic failure fixture can read a P14 floor definition")
		return
	var valid_floor: Dictionary = ((source_rows as Array)[0] as Dictionary).duplicate(true)
	var invalid_floor: Dictionary = valid_floor.duplicate(true)
	invalid_floor["id"] = "floor_atomic_invalid"
	invalid_floor["schema_version"] = 2
	var test_data_root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if test_data_root.is_empty():
		test_data_root = OS.get_temp_dir().path_join("planewalker-tests")
	var root_path := test_data_root.path_join("p14_atomic_registry_pack")
	var content_path := root_path.path_join("content/floors.json")
	var localization_path := root_path.path_join("localization/translations.csv")
	var pack_path := root_path.path_join("pack.json")
	var absolute_content_dir := ProjectSettings.globalize_path(content_path.get_base_dir())
	var absolute_localization_dir := ProjectSettings.globalize_path(localization_path.get_base_dir())
	suite.assert_equal(DirAccess.make_dir_recursive_absolute(absolute_content_dir), OK, "atomic fixture content directory exists")
	suite.assert_equal(DirAccess.make_dir_recursive_absolute(absolute_localization_dir), OK, "atomic fixture localization directory exists")
	var content_text := JSON.stringify([valid_floor, invalid_floor], "\t")
	var localization_text := FileAccess.get_file_as_string("res://data/content_packs/base/localization/translations.csv")
	suite.assert_true(_write_text(content_path, content_text), "atomic fixture writes specialized definitions")
	suite.assert_true(_write_text(localization_path, localization_text), "atomic fixture writes localization authority")
	var pack := {
		"pack_id": "p14_atomic_failure",
		"pack_version": "1.0.0",
		"schema_version": 2,
		"game_version_range": ">=0.4.0-dev <1.0.0",
		"dependencies": [],
		"load_order": 0,
		"content_manifest": ["content/floors.json"],
		"localization_sources": ["localization/translations.csv"],
		"asset_manifest": [],
		"integrity_hashes": {
			"content/floors.json": _sha256_text(content_text),
			"localization/translations.csv": _sha256_text(localization_text),
		},
		"entitlement_tag": "",
	}
	suite.assert_true(_write_text(pack_path, JSON.stringify(pack, "\t")), "atomic fixture writes its pack descriptor")
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": pack_path, "required": true}],
		"0.4.0-dev",
		&"LAUNCH"
	)
	suite.assert_true(report.has_blocking_errors(), "one invalid specialized definition blocks a required pack")
	suite.assert_equal(report.loaded_count, 0, "failed required specialized pack reports no loaded definitions")
	suite.assert_true(registry.all_content().is_empty(), "failed required specialized pack exposes no partial candidate definitions")
	suite.assert_true(registry.active_packs().is_empty(), "failed required specialized pack exposes no active descriptor")


func _test_identity_effect_boundary(suite) -> void:
	var registry = ContentRegistryScript.new()
	var effect_catalog = EffectHandlerCatalogScript.new()
	var localization_keys := {
		"TEST_CHARACTER_NAME": true,
		"TEST_CHARACTER_DESC": true,
	}
	var identity := {
		"id": "test_character",
		"category": "character",
		"availability": ["NEXT"],
		"name_key": "TEST_CHARACTER_NAME",
		"description_key": "TEST_CHARACTER_DESC",
		"tags": ["test"],
		"compatibility": {},
		"effects": {},
	}
	suite.assert_equal(
		registry.call("_v2_entry_error", identity, effect_catalog, localization_keys),
		{},
		"identity content accepts an empty declarative effect set"
	)
	var executable_identity := identity.duplicate(true)
	executable_identity["effects"] = {"attack_multiplier": 1.1}
	var error: Dictionary = registry.call(
		"_v2_entry_error",
		executable_identity,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(error.get("field"), "effects", "identity content rejects effect execution")
	suite.assert_equal(error.get("reason"), "unsupported_category", "identity effect rejection is explicit")


func _test_active_item_entry_boundary(suite) -> void:
	var registry = ContentRegistryScript.new()
	var effect_catalog = EffectHandlerCatalogScript.new()
	var localization_keys := {
		"ABSOLUTE_ZERO_DEVICE_NAME": true,
		"ABSOLUTE_ZERO_DEVICE_DESC": true,
	}
	var active_item := {
		"id": "absolute_zero_device",
		"category": "item",
		"availability": ["LAUNCH", "EXPANSION"],
		"name_key": "ABSOLUTE_ZERO_DEVICE_NAME",
		"description_key": "ABSOLUTE_ZERO_DEVICE_DESC",
		"tags": ["active", "freeze_burst", "risk"],
		"compatibility": {"archetype_ids": ["freeze_burst"]},
		"effects": {},
		"kind": "time",
		"archetype": "freeze_burst",
		"role": "risk",
		"rarity": "rare",
		"icon_id": "content_absolute_zero_device",
		"item_mode": "active",
		"active_handler_id": "absolute_zero",
		"cooldown_frames": 900,
		"active_parameters": {
			"radius": 180.0,
			"duration_frames": 180,
			"weakpoint_bonus": 0.5,
			"energy_cost": 35.0,
		},
	}
	suite.assert_equal(
		registry.call("_v2_entry_error", active_item, effect_catalog, localization_keys),
		{},
		"closed active item definition validates at the Registry boundary"
	)
	suite.assert_true(
		registry.has_method("_active_item_parse_result"),
		"Registry exposes one canonical active-item parse path"
	)
	if registry.has_method("_active_item_parse_result"):
		var floating_integral_item: Dictionary = active_item.duplicate(true)
		floating_integral_item["cooldown_frames"] = 900.0
		floating_integral_item["active_parameters"]["duration_frames"] = 180.0
		var parse_result: Dictionary = registry.call("_active_item_parse_result", floating_integral_item)
		var canonical: Dictionary = parse_result.get("snapshot", {})
		suite.assert_true(bool(parse_result.get("ok", false)), "Registry canonical parser accepts integral numeric input")
		suite.assert_equal(typeof(canonical.get("cooldown_frames")), TYPE_INT, "canonical cooldown is stored as an integer")
		suite.assert_equal(
			typeof(canonical.get("active_parameters", {}).get("duration_frames")),
			TYPE_INT,
			"canonical integral active parameter is stored as an integer"
		)

	var passive_with_handler := active_item.duplicate(true)
	passive_with_handler["item_mode"] = "passive"
	var passive_error: Dictionary = registry.call(
		"_v2_entry_error",
		passive_with_handler,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(passive_error.get("field"), "active_handler_id", "passive item rejects active-only handler")

	var blessing_with_active_fields := active_item.duplicate(true)
	blessing_with_active_fields["category"] = "blessing"
	var category_error: Dictionary = registry.call(
		"_v2_entry_error",
		blessing_with_active_fields,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(category_error.get("field"), "item_mode", "non-item content rejects item-mode fields")

	var malformed_parameters := active_item.duplicate(true)
	malformed_parameters["active_parameters"] = {"script": "res://hostile.gd"}
	var parameter_error: Dictionary = registry.call(
		"_v2_entry_error",
		malformed_parameters,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(parameter_error.get("field"), "active_parameters", "active parameters fail closed")


func _test_launch_reward_routing_boundary(suite) -> void:
	var registry = ContentRegistryScript.new()
	var effect_catalog = EffectHandlerCatalogScript.new()
	var localization_keys := {
		"TEST_ITEM_NAME": true,
		"TEST_ITEM_DESC": true,
	}
	var routed_item := _archetype_reward_definition(
		"routed_launch_item",
		"freeze_burst",
		["LAUNCH"]
	)
	suite.assert_equal(
		registry.call("_v2_entry_error", routed_item, effect_catalog, localization_keys),
		{},
		"Launch route content declares matching archetype tags and compatibility"
	)

	var generalist_wrong_role: Dictionary = routed_item.duplicate(true)
	generalist_wrong_role["archetype"] = ""
	generalist_wrong_role["role"] = "starter"
	generalist_wrong_role["tags"] = ["generalist", "utility"]
	generalist_wrong_role["compatibility"] = {}
	var wrong_role_error: Dictionary = registry.call(
		"_v2_entry_error",
		generalist_wrong_role,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(wrong_role_error.get("field"), "role", "generalist Launch content identifies its invalid role")

	var generalist_missing_tags: Dictionary = generalist_wrong_role.duplicate(true)
	generalist_missing_tags["role"] = "utility"
	generalist_missing_tags["tags"] = ["test"]
	var missing_tags_error: Dictionary = registry.call(
		"_v2_entry_error",
		generalist_missing_tags,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(missing_tags_error.get("field"), "tags", "generalist Launch content requires both contract tags")

	var routed_without_scope: Dictionary = routed_item.duplicate(true)
	routed_without_scope["compatibility"] = {}
	var route_scope_error: Dictionary = registry.call(
		"_v2_entry_error",
		routed_without_scope,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(
		route_scope_error.get("field"),
		"compatibility.archetype_ids",
		"Launch route content requires exact archetype compatibility"
	)

	var curse_wrong_role: Dictionary = routed_item.duplicate(true)
	curse_wrong_role["category"] = "curse"
	var curse_role_error: Dictionary = registry.call(
		"_v2_entry_error",
		curse_wrong_role,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(curse_role_error.get("field"), "role", "Launch route curses require the risk role")

	var launch_talent := {
		"id": "widened_guard",
		"category": "talent",
		"availability": ["LAUNCH"],
		"name_key": "TEST_ITEM_NAME",
		"description_key": "TEST_ITEM_DESC",
		"tags": ["character", "time_guardian"],
		"compatibility": {},
		"effects": {},
		"kind": "guard",
		"archetype": "",
		"role": "route",
	}
	var missing_owner_error: Dictionary = registry.call(
		"_v2_entry_error",
		launch_talent,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(
		missing_owner_error.get("field"),
		"compatibility.character_ids",
		"Launch talents require exactly one character owner"
	)

	var mismatched_talent: Dictionary = launch_talent.duplicate(true)
	mismatched_talent["compatibility"] = {"character_ids": ["void_walker"]}
	var mismatch_error: Dictionary = registry.call(
		"_v2_entry_error",
		mismatched_talent,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(mismatch_error.get("reason"), "owner_mismatch", "canonical Launch talent cannot change owner")

	var valid_talent: Dictionary = launch_talent.duplicate(true)
	valid_talent["compatibility"] = {"character_ids": ["time_guardian"]}
	suite.assert_equal(
		registry.call("_v2_entry_error", valid_talent, effect_catalog, localization_keys),
		{},
		"Launch talent accepts its exact approved character owner"
	)


func _test_effect_capability_profile_validation(suite) -> void:
	var effect_catalog = EffectHandlerCatalogScript.new()
	var unsupported_profile := {
		"id": "sword_fixture_v1",
		"category": "weapon_runtime_profile",
		"availability": ["LAUNCH"],
		"weapon_id": "sword",
		"capabilities": ["weapon.damage"],
	}
	var existing_item := {
		"id": "fixture_sword_combo",
		"category": "item",
		"availability": ["LAUNCH"],
		"compatibility": {"weapon_ids": ["sword"]},
		"effects": {"combo_finisher_multiplier_bonus": 0.35},
	}
	var registry = ContentRegistryScript.new()
	registry.set("_definitions", {"fixture_sword_combo": existing_item})
	var unsupported_profiles: Array[Dictionary] = [unsupported_profile]
	var unsupported_error: Dictionary = registry.call(
		"_first_effect_capability_error",
		unsupported_profiles,
		effect_catalog
	)
	suite.assert_equal(
		unsupported_error.get("reason"),
		"unsupported_capability",
		"a newly activated profile is checked against effects from already active packs"
	)
	suite.assert_equal(
		unsupported_error.get("profile_id"),
		"sword_fixture_v1",
		"capability activation errors identify the incompatible profile"
	)
	suite.assert_equal(
		unsupported_error.get("capability"),
		"weapon.combo_finisher_damage",
		"capability activation errors identify the missing contract"
	)

	var supported_profile: Dictionary = unsupported_profile.duplicate(true)
	supported_profile["capabilities"] = ["weapon.combo_finisher_damage", "weapon.damage"]
	var supported_profiles: Array[Dictionary] = [supported_profile]
	suite.assert_equal(
		registry.call(
			"_first_effect_capability_error",
			supported_profiles,
			effect_catalog
		),
		{},
		"profiles declaring every applicable capability pass activation"
	)

	var bow_only_item := {
		"id": "fixture_bow_damage",
		"category": "item",
		"availability": ["LAUNCH"],
		"compatibility": {"weapon_ids": ["bow"]},
		"effects": {"attack_multiplier": 1.2},
	}
	registry.set("_definitions", {"fixture_bow_damage": bow_only_item})
	var bow_profile := {
		"id": "bow_fixture_v1",
		"category": "weapon_runtime_profile",
		"availability": ["LAUNCH"],
		"weapon_id": "bow",
		"capabilities": ["weapon.damage"],
	}
	var incompatible_profiles: Array[Dictionary] = [unsupported_profile, bow_profile]
	suite.assert_equal(
		registry.call(
			"_first_effect_capability_error",
			incompatible_profiles,
			effect_catalog
		),
		{},
		"weapon compatibility excludes capability routes that cannot be selected"
	)

	var zero_route_item := {
		"id": "fixture_bow_sword_only_effect",
		"category": "item",
		"availability": ["LAUNCH"],
		"compatibility": {"weapon_ids": ["bow"]},
		"effects": {"combo_finisher_multiplier_bonus": 0.35},
	}
	registry.set("_definitions", {"fixture_bow_sword_only_effect": zero_route_item})
	var zero_route_error: Dictionary = registry.call(
		"_first_effect_capability_error",
		incompatible_profiles,
		effect_catalog
	)
	suite.assert_equal(
		zero_route_error.get("reason"),
		"no_executable_route",
		"declared weapon compatibility cannot activate when every effect route targets another weapon"
	)
	suite.assert_equal(
		zero_route_error.get("weapon_id"),
		"bow",
		"zero-route activation identifies the unsupported declared weapon"
	)

	registry.set("_definitions", {"fixture_bow_damage": bow_only_item})
	var missing_profiles: Array[Dictionary] = [unsupported_profile]
	var missing_profile_error: Dictionary = registry.call(
		"_first_effect_capability_error",
		missing_profiles,
		effect_catalog
	)
	suite.assert_equal(
		missing_profile_error.get("reason"),
		"compatible_profile_missing",
		"declared weapon compatibility requires an overlapping milestone runtime profile"
	)
	suite.assert_equal(
		missing_profile_error.get("weapon_id"),
		"bow",
		"missing-profile activation identifies the declared weapon"
	)

	var generic_bow_item := {
		"id": "fixture_bow_defense",
		"category": "item",
		"availability": ["LAUNCH"],
		"compatibility": {"weapon_ids": ["bow"]},
		"effects": {"defense_bonus": 4.0},
	}
	var next_only_bow_profile: Dictionary = bow_profile.duplicate(true)
	next_only_bow_profile["availability"] = ["NEXT"]
	registry.set("_definitions", {"fixture_bow_defense": generic_bow_item})
	var generic_missing_profiles: Array[Dictionary] = [unsupported_profile, next_only_bow_profile]
	var generic_missing_error: Dictionary = registry.call(
		"_first_effect_capability_error",
		generic_missing_profiles,
		effect_catalog
	)
	suite.assert_equal(
		generic_missing_error.get("reason"),
		"compatible_profile_missing",
		"generic effects still require a same-milestone profile for every explicitly compatible weapon"
	)
	suite.assert_equal(
		generic_missing_error.get("weapon_id"),
		"bow",
		"generic-effect profile errors identify the declared weapon"
	)
	var generic_supported_profiles: Array[Dictionary] = [unsupported_profile, bow_profile]
	suite.assert_equal(
		registry.call(
			"_first_effect_capability_error",
			generic_supported_profiles,
			effect_catalog
		),
		{},
		"generic effects pass when the explicitly compatible weapon has a same-milestone profile"
	)


func _action_by_id(profile: Dictionary, action_id: String) -> Dictionary:
	for action_value: Variant in profile.get("actions", []):
		if action_value is Dictionary and str((action_value as Dictionary).get("action_id", "")) == action_id:
			return (action_value as Dictionary).duplicate(true)
	return {}


func _payload_by_id(profile: Dictionary, payload_id: String) -> Dictionary:
	for payload_value: Variant in profile.get("payloads", []):
		if payload_value is Dictionary and str((payload_value as Dictionary).get("payload_id", "")) == payload_id:
			return (payload_value as Dictionary).duplicate(true)
	return {}


func _test_optional_pack_isolation(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[
			{"path": "res://data/content_packs/base/pack.json", "required": true},
			{"path": "res://tests/fixtures/content_packs/invalid_script/pack.json", "required": false},
		],
		"0.4.0-dev",
		&"M1"
	)
	suite.assert_true(not report.has_blocking_errors(), "invalid optional pack does not block base content")
	suite.assert_true(report.isolated_pack_ids.has("fixture_invalid_script"), "invalid optional pack is isolated")
	suite.assert_equal(report.active_pack_count, 1, "only base remains active")
	suite.assert_equal(report.loaded_count, _expected_base_content_total(), "optional pack failure cannot remove base definitions")
	suite.assert_true(registry.get_content(&"fixture_scripted_edge").is_empty(), "hostile optional entry is not indexed")


func _test_required_invalid_pack_blocks(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": "res://tests/fixtures/content_packs/invalid_script/pack.json", "required": true}],
		"0.4.0-dev",
		&"M1"
	)
	suite.assert_true(report.has_blocking_errors(), "invalid required pack blocks activation")
	suite.assert_true(registry.all_content().is_empty(), "blocked activation exposes no partial content")
	suite.assert_true(registry.active_packs().is_empty(), "blocked activation exposes no partial packs")


func _test_project_manifest(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_manifest("res://data/content_manifest.json")
	suite.assert_true(not report.has_blocking_errors(), "project manifest loads M1 content")
	suite.assert_true(report.loaded_count > 0, "project manifest reports loaded definitions")

	var frozen_burst: Dictionary = registry.get_content(&"frozen_burst")
	suite.assert_equal(frozen_burst["name_key"], "FROZEN_BURST_NAME", "legacy name normalizes")
	suite.assert_equal(frozen_burst["description_key"], "FROZEN_BURST_DESC", "legacy description normalizes")
	suite.assert_true(frozen_burst["availability"].has("M1"), "M1 item is enabled")

	suite.assert_true(registry.get_content(&"piercing_draw")["availability"].has("NEXT"), "bow content is preserved as next")
	suite.assert_true(registry.get_content(&"rift_snare")["availability"].has("NEXT"), "rift content is preserved as next")
	var launch_only_item: Dictionary = registry.get_content(&"stasis_lens")
	suite.assert_equal(
		launch_only_item.get("availability"),
		["LAUNCH", "EXPANSION"],
		"legacy item rows preserve explicit multi-milestone availability"
	)
	suite.assert_true(
		not launch_only_item.get("availability", []).has("NEXT"),
		"Launch-only legacy rows do not inherit the source NEXT default"
	)
	var m1_items: Array[Dictionary] = registry.get_by_category(&"item", &"M1")
	suite.assert_true(m1_items.all(func(entry): return not str(entry["id"]).contains("piercing")), "M1 item query excludes bow route")
	var m1_talents: Array[Dictionary] = registry.get_by_category(&"talent", &"M1")
	suite.assert_equal(m1_talents.size(), 3, "real M1 talent pool supports three choices")
	suite.assert_true(m1_talents.all(func(entry): return str(entry["archetype"]) != "rift_control"), "M1 talent pool excludes rift route")
	suite.assert_equal(registry.get_content(&"tal_eternity_reserve")["role"], "utility", "manifest override makes eternity reserve generic")

	var copied: Dictionary = registry.get_content(&"frozen_burst")
	copied["effects"]["time_stop_duration_bonus"] = 999.0
	suite.assert_close(
		float(registry.get_content(&"frozen_burst")["effects"]["time_stop_duration_bonus"]),
		0.75,
		"content getter returns deep copies"
	)

	var all_content: Array[Dictionary] = registry.all_content()
	var ids: Dictionary = {}
	for entry: Dictionary in all_content:
		ids[str(entry["id"])] = true
	suite.assert_equal(ids.size(), all_content.size(), "project registry ids are globally unique")


func _test_fixture_manifest(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_manifest("res://tests/fixtures/content/test_manifest.json")
	suite.assert_true(not report.has_blocking_errors(), "fixture manifest loads")
	suite.assert_equal(report.loaded_count, 3, "fixture manifest counts loaded definitions")
	suite.assert_true(registry.get_content(&"fixture_starter")["availability"].has("M1"), "fixture M1 id is enabled")
	suite.assert_equal(
		registry.get_content(&"fixture_utility")["availability"],
		["LAUNCH", "EXPANSION"],
		"entry availability takes priority over the source default"
	)
	suite.assert_equal(
		registry.get_content(&"fixture_default")["availability"],
		["NEXT"],
		"entries without availability continue to use the source default"
	)


func _test_file_and_root_errors(suite) -> void:
	var missing_registry = ContentRegistryScript.new()
	var missing_report = missing_registry.load_entries(
		"res://tests/fixtures/content/does_not_exist.json",
		&"item",
		&"M1",
		[]
	)
	suite.assert_true(missing_report.has_blocking_errors(), "missing M1 source is blocking")

	var malformed_registry = ContentRegistryScript.new()
	var malformed_report = malformed_registry.load_entries(
		"res://tests/fixtures/content/test_manifest.json",
		&"item",
		&"M1",
		[]
	)
	suite.assert_true(malformed_report.has_blocking_errors(), "non-array source root is blocking")


func _test_manifest_validation(suite) -> void:
	var schema_registry = ContentRegistryScript.new()
	var schema_report = schema_registry.load_manifest(
		"res://tests/fixtures/content/invalid_manifest_schema.json"
	)
	suite.assert_true(schema_report.has_blocking_errors(), "fractional manifest schema is rejected")

	var source_registry = ContentRegistryScript.new()
	var source_report = source_registry.load_manifest(
		"res://tests/fixtures/content/invalid_manifest_source.json"
	)
	suite.assert_true(source_report.has_blocking_errors(), "manifest source fields require strict types")
	suite.assert_true(source_registry.all_content().is_empty(), "invalid manifest source is not loaded")

	var category_registry = ContentRegistryScript.new()
	var category_report = category_registry.load_entries(
		"res://tests/fixtures/content/valid_items.json",
		&"itme",
		&"NEXT",
		["fixture_starter"]
	)
	suite.assert_true(category_report.has_blocking_errors(), "unknown content category is rejected")
	suite.assert_true(category_registry.all_content().is_empty(), "misspelled category is not indexed")

	var invalid_availability := {
		"id": "invalid_availability",
		"name": "INVALID_AVAILABILITY_NAME",
		"description": "INVALID_AVAILABILITY_DESC",
		"availability": ["LAUNCH", "LAUNCH"],
		"effects": {},
	}
	suite.assert_equal(
		source_registry.call("_first_invalid_field", invalid_availability),
		"availability",
		"legacy row availability rejects duplicate or malformed milestones"
	)


func _test_m1_source_failures_are_blocking(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/does_not_exist.json",
		&"item",
		&"NEXT",
		["required_m1_entry"]
	)
	suite.assert_true(report.has_blocking_errors(), "missing NEXT source with declared M1 ids is blocking")


func _test_m1_declarations_are_complete(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/valid_items.json",
		&"item",
		&"NEXT",
		["fixture_starter", "ghost_m1_entry"]
	)
	suite.assert_true(report.has_blocking_errors(), "missing manifest M1 id blocks startup")
	suite.assert_true(registry.get_content(&"ghost_m1_entry").is_empty(), "missing M1 id is not synthesized")


func _test_override_validation(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/valid_items.json",
		&"item",
		&"NEXT",
		["fixture_starter"],
		null,
		{"fixture_starter": {"role": false}}
	)
	suite.assert_true(report.has_blocking_errors(), "non-string milestone override is rejected")
	suite.assert_equal(
		registry.get_content(&"fixture_starter").get("role", ""),
		"starter",
		"invalid override does not coerce garbage into content"
	)


func _test_duplicate_ids(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/duplicate_ids.json",
		&"item",
		&"M1",
		[]
	)
	suite.assert_true(report.has_blocking_errors(), "duplicate M1 ids are blocking")
	suite.assert_equal(registry.all_content().size(), 1, "duplicate definition is omitted")


func _test_required_fields(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/missing_required_field.json",
		&"item",
		&"M1",
		[]
	)
	suite.assert_true(report.has_blocking_errors(), "missing M1 fields are blocking")
	suite.assert_equal(report.blocking_errors.size(), 4, "all required field failures are reported")
	suite.assert_true(registry.all_content().is_empty(), "invalid M1 definitions are omitted")


func _test_next_content_isolation(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/missing_required_field.json",
		&"item",
		&"NEXT",
		[]
	)
	suite.assert_true(not report.has_blocking_errors(), "invalid next content does not block M1")
	suite.assert_equal(report.isolated_errors.size(), 4, "invalid next content is isolated")
	suite.assert_true(registry.all_content().is_empty(), "isolated next definitions are not indexed")


func _test_archetype_profile_entry_boundary(suite) -> void:
	var registry = ContentRegistryScript.new()
	var effect_catalog = EffectHandlerCatalogScript.new()
	var localization_keys := {
		"ARCHETYPE_FREEZE_BURST_NAME": true,
		"ARCHETYPE_FREEZE_BURST_DESC": true,
		"ARCHETYPE_FREEZE_BURST_BOSS_RESPONSE": true,
		"TEST_ITEM_NAME": true,
		"TEST_ITEM_DESC": true,
	}
	var profile := _archetype_profile_definition("freeze_burst", ["LAUNCH", "EXPANSION"])
	suite.assert_equal(
		registry.call("_v2_entry_error", profile, effect_catalog, localization_keys),
		{},
		"generic v2 validation accepts a parser-valid archetype profile"
	)

	var leaked_item := _archetype_reward_definition("profile_field_leak", "freeze_burst", ["LAUNCH"])
	leaked_item["archetype_id"] = "freeze_burst"
	var leak_error: Dictionary = registry.call(
		"_v2_entry_error",
		leaked_item,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(leak_error.get("field"), "archetype_id", "profile-only field leak identifies the field")
	suite.assert_equal(
		leak_error.get("reason"),
		"category_specific_field",
		"profile-only fields are rejected explicitly on ordinary content"
	)

	var empty_compatibility := _archetype_reward_definition("empty_archetype_scope", "freeze_burst", ["LAUNCH"])
	empty_compatibility["compatibility"] = {"archetype_ids": []}
	var compatibility_error: Dictionary = registry.call(
		"_v2_entry_error",
		empty_compatibility,
		effect_catalog,
		localization_keys
	)
	suite.assert_equal(
		compatibility_error.get("field"),
		"compatibility.archetype_ids",
		"empty archetype compatibility fails on the exact field"
	)
	suite.assert_equal(compatibility_error.get("reason"), "empty", "empty archetype compatibility fails closed")


func _test_archetype_reference_closure(suite) -> void:
	var registry = ContentRegistryScript.new()
	var launch_profile := _archetype_profile_definition("freeze_burst", ["LAUNCH", "EXPANSION"])
	var known_reward := _archetype_reward_definition("known_freeze_reward", "freeze_burst", ["LAUNCH"])
	var known_definitions: Array[Dictionary] = [launch_profile, known_reward]
	suite.assert_equal(
		registry.call(
			"_first_reference_error",
			known_definitions,
			_known_ids(known_definitions)
		),
		{},
		"known archetype resolves against an available profile"
	)

	var missing_reward := _archetype_reward_definition("missing_profile_reward", "freeze_burst", ["LAUNCH"])
	var missing_definitions: Array[Dictionary] = [missing_reward]
	var missing_error: Dictionary = registry.call(
		"_first_reference_error",
		missing_definitions,
		_known_ids(missing_definitions)
	)
	suite.assert_true(not missing_error.is_empty(), "a known archetype without its profile fails closed")
	suite.assert_equal(missing_error.get("content_id"), "missing_profile_reward", "missing-profile error identifies content")
	suite.assert_equal(missing_error.get("field"), "archetype", "missing-profile error identifies the archetype field")

	var unknown_reward := _archetype_reward_definition("unknown_profile_reward", "time_stop_burst", ["LAUNCH"])
	var unknown_definitions: Array[Dictionary] = [launch_profile, unknown_reward]
	var unknown_error: Dictionary = registry.call(
		"_first_reference_error",
		unknown_definitions,
		_known_ids(unknown_definitions)
	)
	suite.assert_true(not unknown_error.is_empty(), "unknown top-level archetype fails closed")
	suite.assert_equal(unknown_error.get("field"), "archetype", "unknown archetype failure identifies the field")

	var expansion_profile := _archetype_profile_definition("freeze_burst", ["EXPANSION"])
	var widened_reward := _archetype_reward_definition("widened_profile_reward", "freeze_burst", ["LAUNCH"])
	var widened_definitions: Array[Dictionary] = [expansion_profile, widened_reward]
	var widened_error: Dictionary = registry.call(
		"_first_reference_error",
		widened_definitions,
		_known_ids(widened_definitions)
	)
	suite.assert_true(not widened_error.is_empty(), "content cannot widen archetype profile availability")
	suite.assert_equal(widened_error.get("milestone"), "LAUNCH", "availability error identifies the widened milestone")

	var scoped_reward := _archetype_reward_definition("scoped_profile_reward", "freeze_burst", ["LAUNCH"])
	scoped_reward["compatibility"] = {"archetype_ids": ["freeze_burst"]}
	var scoped_definitions: Array[Dictionary] = [launch_profile, scoped_reward]
	suite.assert_equal(
		registry.call(
			"_first_reference_error",
			scoped_definitions,
			_known_ids(scoped_definitions)
		),
		{},
		"known compatibility archetype resolves through the profile catalog"
	)
	var missing_scope_reward := _archetype_reward_definition("missing_scope_reward", "", ["LAUNCH"])
	missing_scope_reward["compatibility"] = {"archetype_ids": ["echo_legion"]}
	var missing_scope_definitions: Array[Dictionary] = [launch_profile, missing_scope_reward]
	var missing_scope_error: Dictionary = registry.call(
		"_first_reference_error",
		missing_scope_definitions,
		_known_ids(missing_scope_definitions)
	)
	suite.assert_true(not missing_scope_error.is_empty(), "compatibility archetype requires a profile")
	suite.assert_equal(
		missing_scope_error.get("field"),
		"compatibility.archetype_ids",
		"compatibility reference failure identifies the exact field"
	)


func _archetype_profile_definition(id: String, milestones: Array) -> Dictionary:
	return {
		"id": "archetype_%s_v1" % id,
		"category": "archetype_profile",
		"availability": milestones.duplicate(),
		"name_key": "ARCHETYPE_FREEZE_BURST_NAME",
		"description_key": "ARCHETYPE_FREEZE_BURST_DESC",
		"tags": ["build_route", "control"],
		"compatibility": {},
		"effects": {},
		"references": [],
		"profile_version": 1,
		"archetype_id": id,
		"mechanic_tags": ["stop", "slow", "weakpoint", "burst"],
		"starter_min": 3,
		"payoff_min": 2,
		"risk_min": 1,
		"boss_conversion_id": "boss_weakpoint_exposure",
		"boss_response_key": "ARCHETYPE_FREEZE_BURST_BOSS_RESPONSE",
	}


func _archetype_reward_definition(id: String, archetype: String, milestones: Array) -> Dictionary:
	return {
		"id": id,
		"category": "item",
		"availability": milestones.duplicate(),
		"name_key": "TEST_ITEM_NAME",
		"description_key": "TEST_ITEM_DESC",
		"tags": ["test", "generalist", "utility"] if archetype.is_empty() else ["test", archetype],
		"compatibility": {} if archetype.is_empty() else {"archetype_ids": [archetype]},
		"effects": {},
		"kind": "utility",
		"archetype": archetype,
		"role": "utility" if archetype.is_empty() else "starter",
		"rarity": "common",
		"icon_id": "content_%s" % id,
		"references": [],
	}


func _content_with_rarity(content: Array, rarity: String) -> Array:
	var result: Array = []
	for value: Variant in content:
		if value is Dictionary and str((value as Dictionary).get("rarity", "")) == rarity:
			result.append(value)
	return result


func _known_ids(definitions: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for definition: Dictionary in definitions:
		result[str(definition.get("id", ""))] = true
	return result


func _read_json_value(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return JSON.parse_string(file.get_as_text())


func _write_text(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return true


func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(value.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _expected_base_content_total() -> int:
	var total := 0
	for category: String in EXPECTED_BASE_CATEGORY_COUNTS:
		total += int(EXPECTED_BASE_CATEGORY_COUNTS[category])
	return total
