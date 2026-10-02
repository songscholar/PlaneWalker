extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PARSER_CASES: Array[Dictionary] = [
	{
		"label": "floor definition",
		"path": "res://scripts/dungeon/floor_definition.gd",
		"fixture": "_floor_fixture",
		"catalog": "res://data/content_packs/base/content/floors.json",
		"expected_count": 5,
	},
	{
		"label": "room template",
		"path": "res://scripts/dungeon/room_template_definition.gd",
		"fixture": "_room_fixture",
		"catalog": "res://data/content_packs/base/content/room_templates.json",
		"expected_count": 30,
	},
	{
		"label": "dungeon event",
		"path": "res://scripts/dungeon/dungeon_event_definition.gd",
		"fixture": "_event_fixture",
		"catalog": "res://data/content_packs/base/content/dungeon_events.json",
		"expected_count": 18,
	},
	{
		"label": "merchant definition",
		"path": "res://scripts/dungeon/merchant_definition.gd",
		"fixture": "_merchant_fixture",
		"catalog": "res://data/content_packs/base/content/merchants.json",
		"expected_count": 5,
	},
	{
		"label": "economy profile",
		"path": "res://scripts/dungeon/economy_profile.gd",
		"fixture": "_economy_fixture",
		"catalog": "res://data/content_packs/base/content/economy_profiles.json",
		"expected_count": 1,
	},
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	for parser_case: Dictionary in PARSER_CASES:
		_test_parser_contract(suite, parser_case)
		_test_live_catalog(suite, parser_case)
	_test_floor_fail_closed(suite)
	_test_room_fail_closed(suite)
	_test_event_fail_closed(suite)
	_test_event_exact_operation_arguments(suite)
	_test_merchant_fail_closed(suite)
	_test_economy_fail_closed(suite)
	suite.finish(get_tree())


func _test_parser_contract(suite, parser_case: Dictionary) -> void:
	var parser = _new_parser(str(parser_case["path"]), suite, str(parser_case["label"]))
	if parser == null:
		return
	var fixture: Dictionary = call(str(parser_case["fixture"]))
	var configured: Dictionary = parser.call("configure", fixture)
	suite.assert_true(
		bool(configured.get("ok", false)),
		"%s accepts its valid fixture: %s" % [parser_case["label"], str(configured.get("context", {}))]
	)
	if not bool(configured.get("ok", false)):
		return
	var returned_definition: Dictionary = configured.get("definition", {})
	returned_definition["id"] = "forged_return"
	var first_snapshot: Dictionary = parser.call("snapshot")
	first_snapshot["id"] = "forged_snapshot"
	_mutate_nested_fixture(first_snapshot)
	_mutate_nested_fixture(fixture)
	var second_snapshot: Dictionary = parser.call("snapshot")
	suite.assert_true(
		str(second_snapshot.get("id", "")) not in ["forged_return", "forged_snapshot"],
		"%s returns deep-copy identity" % parser_case["label"]
	)
	suite.assert_true(
		not _contains_forged_nested_value(second_snapshot),
		"%s returns deep-copy nested state" % parser_case["label"]
	)

	var invalid := call(str(parser_case["fixture"])) as Dictionary
	invalid["unknown_root"] = true
	var rejected: Dictionary = parser.call("configure", invalid)
	suite.assert_true(
		not bool(rejected.get("ok", false)),
		"%s rejects an unknown root field" % parser_case["label"]
	)
	suite.assert_equal(
		parser.call("snapshot"),
		{},
		"%s clears state before failed reconfiguration" % parser_case["label"]
	)


func _test_live_catalog(suite, parser_case: Dictionary) -> void:
	var catalog_value: Variant = _read_json(str(parser_case["catalog"]), suite)
	if not catalog_value is Array:
		return
	var catalog: Array = catalog_value
	suite.assert_equal(
		catalog.size(),
		int(parser_case["expected_count"]),
		"%s catalog has exact count" % parser_case["label"]
	)
	var seen: Dictionary = {}
	for index: int in range(catalog.size()):
		var row_value: Variant = catalog[index]
		suite.assert_true(row_value is Dictionary, "%s row %d is a dictionary" % [parser_case["label"], index])
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var content_id := str(row.get("id", ""))
		suite.assert_true(not content_id.is_empty() and not seen.has(content_id), "%s row IDs are unique" % parser_case["label"])
		seen[content_id] = true
		var parser = _new_parser(str(parser_case["path"]), suite, str(parser_case["label"]))
		if parser == null:
			continue
		var result: Dictionary = parser.call("configure", row.duplicate(true))
		suite.assert_true(
			bool(result.get("ok", false)),
			"%s live row %s parses: %s" % [parser_case["label"], content_id, str(result.get("context", {}))]
		)


func _test_floor_fail_closed(suite) -> void:
	var parser = _new_parser(PARSER_CASES[0]["path"], suite, "floor definition mutations")
	if parser == null:
		return
	var cases: Array[Dictionary] = [
		_case("category", func(value): value["category"] = "room_template"),
		_case("schema version", func(value): value["schema_version"] = 2),
		_case("availability enum", func(value): value["availability"] = ["M1"]),
		_case("duplicate availability", func(value): value["availability"].append("LAUNCH")),
		_case("route bounds", func(value): value["route_room_min"] = 10),
		_case("graph bounds", func(value): value["graph_node_max"] = 8),
		_case("room type enum", func(value): value["allowed_room_types"] = ["corridor"]),
		_case("exact floor budget", func(value): value["required_room_budgets"]["event_min"] = 2),
		_case("floor palette identity", func(value): value["palette_id"] = "palette_forest"),
		_case("floor music identity", func(value): value["music_cue_id"] = "music_floor_forest"),
		_case("duplicate merchant", func(value): value["merchant_ids"].append(value["merchant_ids"][0])),
		_case("negative budget", func(value): value["required_room_budgets"]["event_min"] = -1),
	]
	_assert_cases_fail(suite, parser, Callable(self, "_floor_fixture"), cases, "floor")
	var invalid_floor_five := _floor_five_fixture()
	invalid_floor_five["allowed_room_types"].append("rest")
	invalid_floor_five["required_room_budgets"]["rest_min"] = 1
	var floor_five_result: Dictionary = parser.call("configure", invalid_floor_five)
	suite.assert_true(
		not bool(floor_five_result.get("ok", false)),
		"floor rejects rest on throne floor"
	)
	suite.assert_equal(parser.call("snapshot"), {}, "floor five failure leaves empty state")


func _test_room_fail_closed(suite) -> void:
	var parser = _new_parser(PARSER_CASES[1]["path"], suite, "room template mutations")
	if parser == null:
		return
	var cases: Array[Dictionary] = [
		_case("category", func(value): value["category"] = "floor_definition"),
		_case("room type enum", func(value): value["room_type"] = "corridor"),
		_case("room identity type mismatch", func(value): value["room_type"] = "elite"),
		_case("scene prefix", func(value): value["scene_path"] = "res://scenes/hostile.tscn"),
		_case("scene suffix", func(value): value["scene_path"] = "res://data/content_packs/base/assets/rooms/launch/hostile.gd"),
		_case("duplicate floor", func(value): value["floor_ids"].append(value["floor_ids"][0])),
		_case("floor rule mismatch", func(value): value["supported_environment_rule_ids"] = ["rule_void_spores"]),
		_case("duplicate door", func(value): value["door_anchors"].append(value["door_anchors"][0].duplicate(true))),
		_case("missing player spawn", func(value): value["spawn_anchors"].clear()),
		_case("invalid bounds", func(value): value["camera_bounds"]["width"] = 0),
	]
	_assert_cases_fail(suite, parser, Callable(self, "_room_fixture"), cases, "room")


func _test_event_fail_closed(suite) -> void:
	var parser = _new_parser(PARSER_CASES[2]["path"], suite, "dungeon event mutations")
	if parser == null:
		return
	var cases: Array[Dictionary] = [
		_case("repeat policy", func(value): value["repeat_policy"] = "daily"),
		_case("regular event marked special", func(value): value["special"] = true),
		_case("trigger predicate", func(value): value["trigger_predicate_id"] = "call_script"),
		_case("floor bounds", func(value): value["floor_min"] = 6),
		_case("option count", func(value): value["options"].resize(1)),
		_case("duplicate option", func(value): value["options"].append(value["options"][0].duplicate(true))),
		_case("visibility enum", func(value): value["options"][0]["outcome_visibility"] = "always_hidden"),
		_case("unknown requirement", func(value): value["options"][0]["requirements"][0]["operation"] = "run_method"),
		_case("unknown consequence", func(value): value["options"][0]["outcomes"][0]["consequences"][0]["operation"] = "load_script"),
		_case("non scalar argument", func(value): value["options"][0]["requirements"][0]["arguments"]["amount"] = {"nested": 1}),
		_case("executable key", func(value): value["options"][0]["outcomes"][0]["consequences"][0]["arguments"]["method_name"] = "queue_free"),
		_case("executable string", func(value): value["options"][0]["outcomes"][0]["consequences"][0]["arguments"]["resource"] = "res://hostile.gd"),
		_case("zero outcome weight", func(value): value["options"][0]["outcomes"][0]["weight"] = 0),
		_case("duplicate outcome", func(value): value["options"][0]["outcomes"].append(value["options"][0]["outcomes"][0].duplicate(true))),
	]
	_assert_cases_fail(suite, parser, Callable(self, "_event_fixture"), cases, "event")


func _test_event_exact_operation_arguments(suite) -> void:
	var parser = _new_parser(PARSER_CASES[2]["path"], suite, "dungeon event operation arguments")
	if parser == null:
		return
	var contracts: Array[Dictionary] = [
		_operation_contract("requirement", "resource_min", {"resource": "time_shard", "amount": 1}, {"resource": "time_shard", "amount": -1}),
		_operation_contract("requirement", "health_min", {"amount": 1.0}, {"amount": 0.0}),
		_operation_contract("requirement", "health_max_ratio", {"ratio": 0.5}, {"ratio": 1.0}),
		_operation_contract("requirement", "gold_min", {"amount": 1}, {"amount": 0}),
		_operation_contract("requirement", "has_reward_tag", {"tag": "weapon"}, {"tag": "INVALID"}),
		_operation_contract("requirement", "lacks_curse", {"curse_id": "curse_fickle_time"}, {"curse_id": "curse_unknown"}),
		_operation_contract("requirement", "narrative_flag", {"flag": "met_archivist", "value": true}, {"flag": "INVALID", "value": true}),
		_operation_contract("requirement", "floor_index_min", {"value": 1}, {"value": 6}),
		_operation_contract("consequence", "resource_delta", {"resource": "gold", "amount": -1}, {"resource": "gold", "amount": 0}),
		_operation_contract("consequence", "health_delta", {"amount": -10.0, "nonlethal": true}, {"amount": 0.0, "nonlethal": true}),
		_operation_contract("consequence", "reward_draft", {"pool_id": "blessing", "count": 2}, {"pool_id": "blessing", "count": 4}),
		_operation_contract("consequence", "curse_add", {"curse_id": "curse_fickle_time"}, {"curse_id": "curse_unknown"}),
		_operation_contract("consequence", "curse_remove", {"curse_id": "curse_fickle_time"}, {"curse_id": "curse_unknown"}),
		_operation_contract("consequence", "temporary_modifier", {"modifier_id": "chronal_grace", "duration_rooms": 3, "magnitude": 1.15}, {"modifier_id": "chronal_grace", "duration_rooms": 0, "magnitude": 1.15}),
		_operation_contract("consequence", "map_reveal", {"depth": 1}, {"depth": 0}),
		_operation_contract("consequence", "encounter_start", {"encounter_id": "encounter_profile_ruins_adapter_v1"}, {"encounter_id": "encounter_unknown"}),
		_operation_contract("consequence", "route_skip", {"rooms": 2}, {"rooms": 3}),
		_operation_contract("consequence", "narrative_flag", {"flag": "met_archivist", "value": true}, {"flag": "INVALID", "value": true}),
	]
	for contract: Dictionary in contracts:
		var valid := _event_operation_fixture(contract)
		var accepted: Dictionary = parser.call("configure", valid)
		suite.assert_true(
			bool(accepted.get("ok", false)),
			"%s accepts its exact arguments: %s" % [contract["operation"], str(accepted.get("context", {}))]
		)
		var argument_keys: Array = (contract["valid_arguments"] as Dictionary).keys()
		var first_key := str(argument_keys[0])
		var mutations: Array[Dictionary] = [
			{"label": "missing", "arguments": (contract["valid_arguments"] as Dictionary).duplicate(true)},
			{"label": "extra", "arguments": (contract["valid_arguments"] as Dictionary).duplicate(true)},
			{"label": "wrong_type", "arguments": (contract["valid_arguments"] as Dictionary).duplicate(true)},
			{"label": "out_of_range", "arguments": (contract["out_of_range_arguments"] as Dictionary).duplicate(true)},
		]
		(mutations[0]["arguments"] as Dictionary).erase(first_key)
		(mutations[1]["arguments"] as Dictionary)["extra"] = 1
		(mutations[2]["arguments"] as Dictionary)[first_key] = []
		for mutation: Dictionary in mutations:
			var hostile_contract := contract.duplicate(true)
			hostile_contract["valid_arguments"] = mutation["arguments"]
			var result: Dictionary = parser.call("configure", _event_operation_fixture(hostile_contract))
			suite.assert_true(
				not bool(result.get("ok", false)),
				"%s rejects %s arguments" % [contract["operation"], mutation["label"]]
			)
			suite.assert_equal(parser.call("snapshot"), {}, "%s failure clears parser state" % contract["operation"])


func _operation_contract(kind: String, operation: String, valid_arguments: Dictionary, out_of_range_arguments: Dictionary) -> Dictionary:
	return {
		"kind": kind,
		"operation": operation,
		"valid_arguments": valid_arguments,
		"out_of_range_arguments": out_of_range_arguments,
	}


func _event_operation_fixture(contract: Dictionary) -> Dictionary:
	var fixture := _event_fixture()
	var operation := {
		"operation": str(contract["operation"]),
		"arguments": (contract["valid_arguments"] as Dictionary).duplicate(true),
	}
	if str(contract["kind"]) == "requirement":
		fixture["options"][0]["requirements"] = [operation]
	else:
		fixture["options"][0]["outcomes"][0]["consequences"] = [operation]
	return fixture


func _test_merchant_fail_closed(suite) -> void:
	var parser = _new_parser(PARSER_CASES[3]["path"], suite, "merchant mutations")
	if parser == null:
		return
	var cases: Array[Dictionary] = [
		_case("floor bounds", func(value): value["floor_min"] = 6),
		_case("offer bounds", func(value): value["inventory_rules"]["offer_count_min"] = 9),
		_case("duplicate content category", func(value): value["inventory_rules"]["content_categories"].append(value["inventory_rules"]["content_categories"][0])),
		_case("unknown service", func(value): value["services"] = ["execute_script"]),
		_case("unknown cost", func(value): value["accepted_costs"] = ["real_money"]),
		_case("duplicate shop room", func(value): value["shop_room_template_ids"].append(value["shop_room_template_ids"][0])),
		_case("executable portrait", func(value): value["portrait_id"] = "res://hostile.gd"),
	]
	_assert_cases_fail(suite, parser, Callable(self, "_merchant_fixture"), cases, "merchant")


func _test_economy_fail_closed(suite) -> void:
	var parser = _new_parser(PARSER_CASES[4]["path"], suite, "economy mutations")
	if parser == null:
		return
	var cases: Array[Dictionary] = [
		_case("identity", func(value): value["id"] = "premium_economy"),
		_case("negative income", func(value): value["floor_income_budgets"][0]["earned_min"] = -1),
		_case("negative price", func(value): value["base_prices"]["common_reward"] = -1),
		_case("negative multiplier", func(value): value["rarity_multipliers"]["common"] = -1.0),
		_case("sell ratio", func(value): value["sell_ratio"] = 1.5),
		_case("overflow ratio", func(value): value["overflow_decay"] = -0.1),
		_case("pity bounds", func(value): value["pity_bounds"]["rare_offer_min"] = 99),
		_case("inventory bounds", func(value): value["inventory_sizes"]["standard_min"] = 9),
	]
	_assert_cases_fail(suite, parser, Callable(self, "_economy_fixture"), cases, "economy")


func _assert_cases_fail(
	suite,
	parser,
	fixture_factory: Callable,
	cases: Array[Dictionary],
	label: String
) -> void:
	for invalid_case: Dictionary in cases:
		var fixture: Dictionary = fixture_factory.call()
		(invalid_case["mutate"] as Callable).call(fixture)
		var result: Dictionary = parser.call("configure", fixture)
		suite.assert_true(
			not bool(result.get("ok", false)),
			"%s rejects %s" % [label, invalid_case["label"]]
		)
		suite.assert_equal(parser.call("snapshot"), {}, "%s failure leaves empty state" % label)


func _new_parser(path: String, suite, label: String):
	suite.assert_true(ResourceLoader.exists(path, "Script"), "%s parser exists" % label)
	if not ResourceLoader.exists(path, "Script"):
		return null
	var script: Variant = load(path)
	suite.assert_true(script != null and script.can_instantiate(), "%s parser script loads" % label)
	if script == null or not script.can_instantiate():
		return null
	var parser = script.new()
	suite.assert_true(parser.has_method("configure"), "%s exposes configure" % label)
	suite.assert_true(parser.has_method("snapshot"), "%s exposes snapshot" % label)
	return parser


func _floor_fixture() -> Dictionary:
	return {
		"category": "floor_definition",
		"id": "floor_ruins_of_remnant",
		"schema_version": 1,
		"name_key": "FLOOR_RUINS_NAME",
		"description_key": "FLOOR_RUINS_DESCRIPTION",
		"availability": ["LAUNCH", "EXPANSION"],
		"order": 1,
		"route_room_min": 6,
		"route_room_max": 6,
		"graph_node_min": 9,
		"graph_node_max": 9,
		"allowed_room_types": ["combat", "elite", "treasure", "shop", "event", "boss", "rest"],
		"required_room_budgets": {
			"shop_or_treasure_min": 1,
			"shop_min": 0,
			"treasure_min": 0,
			"event_min": 1,
			"rest_min": 1,
			"boss_count": 1,
		},
		"environment_rule_id": "rule_crumbling_ground",
		"encounter_profile_id": "encounter_profile_ruins_adapter_v1",
		"economy_profile_id": "launch_economy_v1",
		"merchant_ids": ["merchant_wayfarer"],
		"event_ids": ["event_chronal_altar", "event_trapped_traveler"],
		"palette_id": "palette_ruins_of_remnant",
		"music_cue_id": "music_ruins_of_remnant",
		"boss_room_template_id": "room_boss_ruin_king",
		"boss_encounter_id": "boss_encounter_ruin_king_adapter_v1",
	}


func _room_fixture() -> Dictionary:
	return {
		"category": "room_template",
		"id": "room_combat_pillared_hall",
		"schema_version": 1,
		"name_key": "ROOM_COMBAT_PILLARED_HALL_NAME",
		"description_key": "ROOM_COMBAT_PILLARED_HALL_DESCRIPTION",
		"availability": ["LAUNCH", "EXPANSION"],
		"room_type": "combat",
		"scene_path": "res://data/content_packs/base/assets/rooms/launch/room_combat_pillared_hall.tscn",
		"floor_ids": ["floor_ruins_of_remnant"],
		"door_anchors": [
			{"id": "door_entry", "direction": "west", "position": {"x": 32.0, "y": 180.0}},
			{"id": "door_exit", "direction": "east", "position": {"x": 608.0, "y": 180.0}},
		],
		"camera_bounds": {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0},
		"spawn_anchors": [
			{"id": "spawn_player", "kind": "player", "position": {"x": 96.0, "y": 180.0}},
			{"id": "spawn_enemy_a", "kind": "enemy", "position": {"x": 480.0, "y": 180.0}},
		],
		"interaction_anchors": [],
		"supported_environment_rule_ids": ["rule_crumbling_ground"],
		"accessibility_safe_hazard_zones": [
			{"id": "safe_center", "bounds": {"x": 240.0, "y": 120.0, "width": 160.0, "height": 120.0}},
		],
		"thumbnail_id": "thumbnail_room_combat_pillared_hall",
		"icon_id": "icon_room_combat",
	}


func _floor_five_fixture() -> Dictionary:
	var fixture := _floor_fixture()
	fixture["id"] = "floor_throne_of_void"
	fixture["order"] = 5
	fixture["route_room_min"] = 7
	fixture["route_room_max"] = 7
	fixture["graph_node_min"] = 9
	fixture["graph_node_max"] = 9
	fixture["allowed_room_types"] = ["combat", "elite", "treasure", "shop", "event", "boss"]
	fixture["required_room_budgets"] = {
		"shop_or_treasure_min": 1,
		"shop_min": 0,
		"treasure_min": 0,
		"event_min": 1,
		"rest_min": 0,
		"boss_count": 1,
	}
	fixture["environment_rule_id"] = "rule_collapsing_plane"
	fixture["encounter_profile_id"] = "encounter_profile_throne_adapter_v1"
	fixture["palette_id"] = "palette_throne_of_void"
	fixture["music_cue_id"] = "music_throne_of_void"
	fixture["boss_room_template_id"] = "room_boss_void_throne"
	fixture["boss_encounter_id"] = "boss_encounter_void_throne_adapter_v1"
	return fixture


func _event_fixture() -> Dictionary:
	return {
		"category": "dungeon_event",
		"id": "event_chronal_altar",
		"schema_version": 1,
		"name_key": "EVENT_CHRONAL_ALTAR_NAME",
		"description_key": "EVENT_CHRONAL_ALTAR_DESCRIPTION",
		"prompt_key": "EVENT_CHRONAL_ALTAR_PROMPT",
		"availability": ["LAUNCH", "EXPANSION"],
		"special": false,
		"floor_min": 1,
		"floor_max": 5,
		"weight": 100,
		"repeat_policy": "once_per_run",
		"trigger_predicate_id": "always",
		"outcome_channel": "event_outcome_v1",
		"options": [
			{
				"id": "offer_gold",
				"label_key": "EVENT_CHRONAL_ALTAR_OFFER_LABEL",
				"outcome_visibility": "preview_exact",
				"requirements": [
					{"operation": "gold_min", "arguments": {"amount": 25}},
				],
				"outcomes": [
					{
						"id": "accepted",
						"weight": 1,
						"outcome_key": "EVENT_CHRONAL_ALTAR_OFFER_OUTCOME",
						"consequences": [
							{"operation": "resource_delta", "arguments": {"resource": "gold", "amount": -25}},
							{"operation": "reward_draft", "arguments": {"pool_id": "blessing", "count": 1}},
						],
					},
				],
			},
			{
				"id": "leave",
				"label_key": "EVENT_COMMON_LEAVE_LABEL",
				"outcome_visibility": "preview_category",
				"requirements": [
					{"operation": "floor_index_min", "arguments": {"value": 1}},
				],
				"outcomes": [
					{
						"id": "declined",
						"weight": 1,
						"outcome_key": "EVENT_COMMON_LEAVE_OUTCOME",
						"consequences": [
							{"operation": "narrative_flag", "arguments": {"flag": "chronal_altar_declined", "value": true}},
						],
					},
				],
			},
		],
	}


func _merchant_fixture() -> Dictionary:
	return {
		"category": "merchant_definition",
		"id": "merchant_wayfarer",
		"schema_version": 1,
		"name_key": "MERCHANT_WAYFARER_NAME",
		"description_key": "MERCHANT_WAYFARER_DESCRIPTION",
		"availability": ["LAUNCH", "EXPANSION"],
		"floor_min": 1,
		"floor_max": 5,
		"portrait_id": "portrait_merchant_wayfarer",
		"pixel_proxy_id": "proxy_merchant_wayfarer",
		"shop_room_template_ids": ["room_shop_wayfarer_tent"],
		"inventory_rules": {
			"offer_count_min": 3,
			"offer_count_max": 5,
			"rarity_weights": {"common": 0.45, "uncommon": 0.3, "rare": 0.18, "legendary": 0.06, "unique": 0.01},
			"content_categories": ["item", "blessing"],
			"required_tags": [],
			"allow_duplicates": false,
		},
		"services": ["purchase_reward", "heal", "reroll", "sell_reward"],
		"accepted_costs": ["gold"],
		"economy_profile_id": "launch_economy_v1",
		"intro_key": "MERCHANT_WAYFARER_INTRO",
		"farewell_key": "MERCHANT_WAYFARER_FAREWELL",
	}


func _economy_fixture() -> Dictionary:
	return {
		"category": "economy_profile",
		"id": "launch_economy_v1",
		"schema_version": 1,
		"name_key": "ECONOMY_LAUNCH_NAME",
		"description_key": "ECONOMY_LAUNCH_DESCRIPTION",
		"availability": ["LAUNCH", "EXPANSION"],
		"floor_income_budgets": [
			{"floor_index": 1, "earned_min": 140, "earned_max": 220, "spend_min": 100, "spend_max": 180, "remainder_min": 20, "remainder_max": 80},
			{"floor_index": 2, "earned_min": 180, "earned_max": 280, "spend_min": 150, "spend_max": 240, "remainder_min": 20, "remainder_max": 90},
			{"floor_index": 3, "earned_min": 240, "earned_max": 380, "spend_min": 210, "spend_max": 340, "remainder_min": 20, "remainder_max": 110},
			{"floor_index": 4, "earned_min": 300, "earned_max": 460, "spend_min": 270, "spend_max": 420, "remainder_min": 20, "remainder_max": 120},
			{"floor_index": 5, "earned_min": 280, "earned_max": 430, "spend_min": 250, "spend_max": 400, "remainder_min": 0, "remainder_max": 100},
		],
		"base_prices": {"common_reward": 50, "uncommon_reward": 80, "rare_reward": 120, "legendary_reward": 220, "healing": 40, "curse_cleanse": 100, "reroll": 40, "weapon_upgrade": 120, "route_reveal": 60},
		"rarity_multipliers": {"common": 1.0, "uncommon": 1.25, "rare": 1.6, "legendary": 2.4, "unique": 3.0},
		"floor_multipliers": [1.0, 1.15, 1.3, 1.45, 1.6],
		"reroll_surcharge": {"base_price": 40, "increment": 20, "maximum_rerolls": 4},
		"sell_ratio": 0.5,
		"curse_cleanse_cost": 120,
		"healing_cost": 60,
		"gold_caps": [500, 650, 800, 950, 1100],
		"overflow_decay": 0.25,
		"pity_bounds": {"rare_offer_min": 3, "rare_offer_max": 6},
		"inventory_sizes": {"standard_min": 3, "standard_max": 5, "premium_min": 2, "premium_max": 4},
	}


func _mutate_nested_fixture(value: Dictionary) -> void:
	for key: String in ["merchant_ids", "floor_ids", "options", "services", "floor_income_budgets"]:
		if value.get(key) is Array:
			var nested_array: Array = value[key]
			if not nested_array.is_empty() and nested_array[0] is Dictionary:
				(nested_array[0] as Dictionary)["forged_nested"] = true
			else:
				nested_array.append("forged_nested")
			return
	for key: String in ["required_room_budgets", "camera_bounds", "inventory_rules", "base_prices"]:
		if value.get(key) is Dictionary:
			(value[key] as Dictionary)["forged_nested"] = true
			return


func _contains_forged_nested_value(value: Dictionary) -> bool:
	return JSON.stringify(value).contains("forged_nested")


func _case(label: String, mutate: Callable) -> Dictionary:
	return {"label": label, "mutate": mutate}


func _read_json(path: String, suite) -> Variant:
	suite.assert_true(FileAccess.file_exists(path), "%s exists" % path)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s opens" % path)
	if file == null:
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	suite.assert_equal(error, OK, "%s contains valid JSON" % path)
	return parser.data if error == OK else {}
