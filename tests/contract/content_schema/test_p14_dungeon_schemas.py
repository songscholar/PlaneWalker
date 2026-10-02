import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[3]
SCHEMA_ROOT = ROOT / "data/schemas"
CONTENT_ROOT = ROOT / "data/content_packs/base/content"

SCHEMA_FILES = {
    "floor_definition": "floor_definition_v1.schema.json",
    "room_template": "room_template_v1.schema.json",
    "dungeon_event": "dungeon_event_v1.schema.json",
    "merchant_definition": "merchant_definition_v1.schema.json",
    "economy_profile": "economy_profile_v1.schema.json",
}
CATALOG_FILES = {
    "floor_definition": "floors.json",
    "room_template": "room_templates.json",
    "dungeon_event": "dungeon_events.json",
    "merchant_definition": "merchants.json",
    "economy_profile": "economy_profiles.json",
}

FLOOR_IDS = [
    "floor_ruins_of_remnant",
    "floor_void_forest",
    "floor_time_rift",
    "floor_plane_forge",
    "floor_throne_of_void",
]
FLOOR_RULE_IDS = [
    "rule_crumbling_ground",
    "rule_void_spores",
    "rule_temporal_distortion",
    "rule_forge_vents",
    "rule_collapsing_plane",
]
ENCOUNTER_PROFILE_IDS = [
    "encounter_profile_ruins_adapter_v1",
    "encounter_profile_forest_adapter_v1",
    "encounter_profile_rift_adapter_v1",
    "encounter_profile_forge_adapter_v1",
    "encounter_profile_throne_adapter_v1",
]
BOSS_ENCOUNTER_IDS = [
    "boss_encounter_ruin_king_adapter_v1",
    "boss_encounter_forest_heart_adapter_v1",
    "boss_encounter_time_sovereign_adapter_v1",
    "boss_encounter_forge_colossus_adapter_v1",
    "boss_encounter_void_throne_adapter_v1",
]
ROOM_IDS_BY_TYPE = {
    "combat": [
        "room_combat_pillared_hall",
        "room_combat_split_chambers",
        "room_combat_open_field",
        "room_combat_l_corner",
        "room_combat_crossroads",
        "room_combat_high_ground",
        "room_combat_void_grove",
        "room_combat_ring",
        "room_combat_bridge",
        "room_combat_clockwork",
    ],
    "elite": [
        "room_elite_arena",
        "room_elite_guard_corridor",
        "room_elite_altar_defense",
        "room_elite_trap_arena",
        "room_elite_twin_hall",
    ],
    "treasure": [
        "room_treasure_vault",
        "room_treasure_wishing_pool",
        "room_treasure_chronovault",
    ],
    "shop": [
        "room_shop_wayfarer_tent",
        "room_shop_chrono_emporium",
    ],
    "event": [
        "room_event_shrine",
        "room_event_crossroads",
        "room_event_mirror_hall",
    ],
    "boss": [
        "room_boss_ruin_king",
        "room_boss_forest_heart",
        "room_boss_time_sovereign",
        "room_boss_forge_colossus",
        "room_boss_void_throne",
    ],
    "rest": [
        "room_rest_campfire",
        "room_rest_sanctuary",
    ],
}
REGULAR_EVENT_IDS = [
    "event_chronal_altar",
    "event_trapped_traveler",
    "event_cursed_pool",
    "event_smiths_legacy",
    "event_memory_mirror",
    "event_planar_merchant",
    "event_void_rift",
    "event_sleeping_guardian",
    "event_twisted_well",
    "event_soul_contract",
    "event_time_paradox",
    "event_sacrificial_altar",
    "event_lost_journal",
    "event_rift_garden",
    "event_final_choice",
]
SPECIAL_EVENT_IDS = [
    "event_void_whispers",
    "event_perfect_rewind",
    "event_old_reunion",
]
MERCHANT_IDS = [
    "merchant_wayfarer",
    "merchant_chronomancer",
    "merchant_forgekeeper",
    "merchant_void_broker",
    "merchant_echo_archivist",
]
REQUIREMENT_OPERATIONS = {
    "resource_min",
    "health_min",
    "health_max_ratio",
    "gold_min",
    "has_reward_tag",
    "lacks_curse",
    "narrative_flag",
    "floor_index_min",
}
CONSEQUENCE_OPERATIONS = {
    "resource_delta",
    "health_delta",
    "reward_draft",
    "curse_add",
    "curse_remove",
    "temporary_modifier",
    "map_reveal",
    "encounter_start",
    "route_skip",
    "narrative_flag",
}
EVENT_RESOURCES = {"gold", "time_shard", "forge_essence"}
EVENT_REWARD_POOLS = {"item", "blessing", "rare_item", "rare_blessing"}
EVENT_MODIFIER_IDS = {
    "chronal_grace",
    "weapon_temper",
    "past_strength",
    "paradox_echo",
    "tranquility",
    "void_bargain_power",
    "void_bargain_guard",
    "heroic_guard",
    "heroic_assault",
}
OPERATION_CONTRACTS = {
    "resource_min": ("requirement", {"resource": "time_shard", "amount": 1}, {"resource": "time_shard", "amount": -1}),
    "health_min": ("requirement", {"amount": 1.0}, {"amount": 0.0}),
    "health_max_ratio": ("requirement", {"ratio": 0.5}, {"ratio": 1.0}),
    "gold_min": ("requirement", {"amount": 1}, {"amount": 0}),
    "has_reward_tag": ("requirement", {"tag": "weapon"}, {"tag": "INVALID"}),
    "lacks_curse": ("requirement", {"curse_id": "curse_fickle_time"}, {"curse_id": "curse_unknown"}),
    "narrative_flag_requirement": ("requirement", {"flag": "met_archivist", "value": True}, {"flag": "INVALID", "value": True}),
    "floor_index_min": ("requirement", {"value": 1}, {"value": 6}),
    "resource_delta": ("consequence", {"resource": "gold", "amount": -1}, {"resource": "gold", "amount": 0}),
    "health_delta": ("consequence", {"amount": -10.0, "nonlethal": True}, {"amount": 0.0, "nonlethal": True}),
    "reward_draft": ("consequence", {"pool_id": "blessing", "count": 2}, {"pool_id": "blessing", "count": 4}),
    "curse_add": ("consequence", {"curse_id": "curse_fickle_time"}, {"curse_id": "curse_unknown"}),
    "curse_remove": ("consequence", {"curse_id": "curse_fickle_time"}, {"curse_id": "curse_unknown"}),
    "temporary_modifier": ("consequence", {"modifier_id": "chronal_grace", "duration_rooms": 3, "magnitude": 1.15}, {"modifier_id": "chronal_grace", "duration_rooms": 0, "magnitude": 1.15}),
    "map_reveal": ("consequence", {"depth": 1}, {"depth": 0}),
    "encounter_start": ("consequence", {"encounter_id": "encounter_profile_ruins_adapter_v1"}, {"encounter_id": "encounter_unknown"}),
    "route_skip": ("consequence", {"rooms": 2}, {"rooms": 3}),
    "narrative_flag_consequence": ("consequence", {"flag": "met_archivist", "value": True}, {"flag": "INVALID", "value": True}),
}
MERCHANT_SERVICES = {
    "purchase_reward",
    "heal",
    "cleanse_curse",
    "reroll",
    "weapon_upgrade",
    "health_trade",
    "route_reveal",
    "sell_reward",
}


class P14DungeonSchemasTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schemas = {
            category: json.loads((SCHEMA_ROOT / filename).read_text(encoding="utf-8"))
            for category, filename in SCHEMA_FILES.items()
        }
        cls.catalogs = {
            category: json.loads((CONTENT_ROOT / filename).read_text(encoding="utf-8"))
            for category, filename in CATALOG_FILES.items()
        }
        cls.validators = {
            category: Draft202012Validator(schema)
            for category, schema in cls.schemas.items()
        }

    def test_schemas_are_closed_valid_draft_2020_12_documents(self) -> None:
        expected_ids = {
            "floor_definition": "planewalker://schemas/floor-definition/1.0.0",
            "room_template": "planewalker://schemas/room-template/1.0.0",
            "dungeon_event": "planewalker://schemas/dungeon-event/1.0.0",
            "merchant_definition": "planewalker://schemas/merchant-definition/1.0.0",
            "economy_profile": "planewalker://schemas/economy-profile/1.0.0",
        }
        for category, schema in self.schemas.items():
            with self.subTest(category=category):
                Draft202012Validator.check_schema(schema)
                self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
                self.assertEqual(schema["$id"], expected_ids[category])
                self.assertFalse(schema["additionalProperties"])

    def test_exact_specialized_catalog_counts_categories_and_versions(self) -> None:
        self.assertEqual([row["id"] for row in self.catalogs["floor_definition"]], FLOOR_IDS)
        expected_rooms = [room_id for ids in ROOM_IDS_BY_TYPE.values() for room_id in ids]
        self.assertEqual([row["id"] for row in self.catalogs["room_template"]], expected_rooms)
        self.assertEqual(
            [row["id"] for row in self.catalogs["dungeon_event"]],
            REGULAR_EVENT_IDS + SPECIAL_EVENT_IDS,
        )
        self.assertEqual([row["id"] for row in self.catalogs["merchant_definition"]], MERCHANT_IDS)
        self.assertEqual(
            [row["id"] for row in self.catalogs["economy_profile"]],
            ["launch_economy_v1"],
        )
        self.assertEqual(sum(map(len, self.catalogs.values())), 59)

        all_ids: list[str] = []
        for category, rows in self.catalogs.items():
            for row in rows:
                with self.subTest(category=category, entry=row["id"]):
                    self.assertEqual(row["category"], category)
                    self.assertEqual(row["schema_version"], 1)
                    self.assertEqual(row["availability"], ["LAUNCH", "EXPANSION"])
                    self.assertEqual(list(self.validators[category].iter_errors(row)), [])
                all_ids.append(row["id"])
        self.assertEqual(len(all_ids), len(set(all_ids)))

    def test_catalog_localization_key_set_is_exact_and_frozen(self) -> None:
        expected = set()
        for floor_id in FLOOR_IDS:
            suffix = floor_id.removeprefix("floor_").upper()
            expected.update({f"FLOOR_{suffix}_NAME", f"FLOOR_{suffix}_DESC"})
        for room_ids in ROOM_IDS_BY_TYPE.values():
            for room_id in room_ids:
                suffix = room_id.upper()
                expected.update({f"{suffix}_NAME", f"{suffix}_DESC"})
        for event_id in REGULAR_EVENT_IDS + SPECIAL_EVENT_IDS:
            suffix = event_id.removeprefix("event_").upper()
            expected.update(
                {
                    f"EVENT_{suffix}_NAME",
                    f"EVENT_{suffix}_DESC",
                    f"EVENT_{suffix}_PROMPT",
                    f"EVENT_{suffix}_OPTION_COMMIT",
                    f"EVENT_{suffix}_OUTCOME_COMMIT",
                    f"EVENT_{suffix}_OPTION_DECLINE",
                    f"EVENT_{suffix}_OUTCOME_DECLINE",
                }
            )
        for merchant_id in MERCHANT_IDS:
            suffix = merchant_id.removeprefix("merchant_").upper()
            expected.update(
                {
                    f"MERCHANT_{suffix}_NAME",
                    f"MERCHANT_{suffix}_DESC",
                    f"MERCHANT_{suffix}_INTRO",
                    f"MERCHANT_{suffix}_FAREWELL",
                }
            )
        expected.update({"ECONOMY_LAUNCH_V1_NAME", "ECONOMY_LAUNCH_V1_DESC"})

        actual = set()
        for rows in self.catalogs.values():
            for row in rows:
                self._collect_localization_keys(row, actual)
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), 218)

    def test_floor_contract_is_exact_and_uses_closed_p14_adapters(self) -> None:
        expected = [
            (1, 6, 9, 1, 0, 0, 1, 1, 1),
            (2, 7, 10, 1, 0, 0, 1, 1, 1),
            (3, 8, 12, 1, 0, 0, 2, 1, 1),
            (4, 9, 14, 0, 1, 1, 1, 1, 1),
            (5, 7, 9, 1, 0, 0, 1, 0, 1),
        ]
        for index, (row, contract) in enumerate(zip(self.catalogs["floor_definition"], expected)):
            order, route_rooms, graph_nodes, shop_or_treasure, shop, treasure, event, rest, boss = contract
            with self.subTest(floor=row["id"]):
                self.assertEqual(row["order"], order)
                self.assertEqual((row["route_room_min"], row["route_room_max"]), (route_rooms, route_rooms))
                self.assertEqual((row["graph_node_min"], row["graph_node_max"]), (graph_nodes, graph_nodes))
                self.assertEqual(row["environment_rule_id"], FLOOR_RULE_IDS[index])
                self.assertEqual(row["encounter_profile_id"], ENCOUNTER_PROFILE_IDS[index])
                self.assertEqual(row["boss_encounter_id"], BOSS_ENCOUNTER_IDS[index])
                self.assertEqual(row["economy_profile_id"], "launch_economy_v1")
                self.assertEqual(
                    row["required_room_budgets"],
                    {
                        "shop_or_treasure_min": shop_or_treasure,
                        "shop_min": shop,
                        "treasure_min": treasure,
                        "event_min": event,
                        "rest_min": rest,
                        "boss_count": boss,
                    },
                )
                self.assertTrue(set(row["merchant_ids"]).issubset(MERCHANT_IDS))
                self.assertTrue(set(row["event_ids"]).issubset(REGULAR_EVENT_IDS + SPECIAL_EVENT_IDS))
                self.assertEqual(len(row["event_ids"]), len(set(row["event_ids"])))

    def test_floor_schema_rejects_wrong_pairings_bounds_and_unknown_adapters(self) -> None:
        validator = self.validators["floor_definition"]
        mutations = []
        for field, value in [
            ("order", 2),
            ("route_room_max", 9),
            ("graph_node_min", 8),
            ("environment_rule_id", FLOOR_RULE_IDS[1]),
            ("encounter_profile_id", "encounter_profile_custom"),
            ("boss_encounter_id", "boss_encounter_custom"),
            ("economy_profile_id", "other_economy"),
        ]:
            hostile = copy.deepcopy(self.catalogs["floor_definition"][0])
            hostile[field] = value
            mutations.append((field, hostile))
        for label, hostile in mutations:
            with self.subTest(mutation=label):
                self.assertTrue(list(validator.iter_errors(hostile)))

    def test_floor_schema_freezes_every_floor_specific_generation_contract(self) -> None:
        validator = self.validators["floor_definition"]
        coupled_fields = [
            "order",
            "route_room_min",
            "route_room_max",
            "graph_node_min",
            "graph_node_max",
            "allowed_room_types",
            "required_room_budgets",
            "environment_rule_id",
            "encounter_profile_id",
            "palette_id",
            "music_cue_id",
            "boss_room_template_id",
            "boss_encounter_id",
        ]
        rows = self.catalogs["floor_definition"]
        for row in rows:
            for field in coupled_fields:
                replacement = next(candidate for candidate in rows if candidate[field] != row[field])
                hostile = copy.deepcopy(row)
                hostile[field] = copy.deepcopy(replacement[field])
                with self.subTest(floor=row["id"], mutation=field):
                    self.assertTrue(list(validator.iter_errors(hostile)))

        floor_one_event_budget = copy.deepcopy(rows[0])
        floor_one_event_budget["required_room_budgets"]["event_min"] = 2
        self.assertTrue(list(validator.iter_errors(floor_one_event_budget)))

        floor_five_with_rest = copy.deepcopy(rows[4])
        floor_five_with_rest["allowed_room_types"].append("rest")
        self.assertTrue(list(validator.iter_errors(floor_five_with_rest)))

    def test_room_split_scene_paths_anchors_and_floor_rule_compatibility(self) -> None:
        rows = self.catalogs["room_template"]
        room_ids = {row["id"] for row in rows}
        floor_rules = dict(zip(FLOOR_IDS, FLOOR_RULE_IDS))
        for room_type, expected_ids in ROOM_IDS_BY_TYPE.items():
            self.assertEqual(
                [row["id"] for row in rows if row["room_type"] == room_type],
                expected_ids,
            )
        for row in rows:
            with self.subTest(room=row["id"]):
                self.assertRegex(
                    row["scene_path"],
                    r"^res://data/content_packs/base/assets/rooms/launch/[a-z0-9_]+\.tscn$",
                )
                self.assertGreaterEqual(len(row["door_anchors"]), 2)
                self.assertTrue(any(anchor["kind"] == "player" for anchor in row["spawn_anchors"]))
                self.assertGreaterEqual(len(row["accessibility_safe_hazard_zones"]), 1)
                self.assertTrue(set(row["floor_ids"]).issubset(FLOOR_IDS))
                self.assertEqual(
                    set(row["supported_environment_rule_ids"]),
                    {floor_rules[floor_id] for floor_id in row["floor_ids"]},
                )
                self.assertIn(row["id"], room_ids)

    def test_room_schema_rejects_external_scene_paths_missing_anchors_and_bad_types(self) -> None:
        validator = self.validators["room_template"]
        base = self.catalogs["room_template"][0]
        cases = []
        for field, value in [
            ("room_type", "corridor"),
            ("scene_path", "res://scenes/rooms/hostile.tscn"),
            ("floor_ids", ["floor_unknown"]),
            ("supported_environment_rule_ids", ["rule_unknown"]),
        ]:
            hostile = copy.deepcopy(base)
            hostile[field] = value
            cases.append((field, hostile))
        for field in ["door_anchors", "spawn_anchors", "accessibility_safe_hazard_zones"]:
            hostile = copy.deepcopy(base)
            hostile[field] = []
            cases.append((f"empty_{field}", hostile))
        mismatched_type = copy.deepcopy(base)
        mismatched_type["room_type"] = "shop"
        cases.append(("id_type_mismatch", mismatched_type))
        self.assertTrue(any(row["id"] == "room_boss_ruin_king" for row in self.catalogs["room_template"]))
        for label, hostile in cases:
            with self.subTest(mutation=label):
                self.assertTrue(list(validator.iter_errors(hostile)))

    def test_room_schema_freezes_id_type_and_floor_rule_bijections(self) -> None:
        validator = self.validators["room_template"]
        floor_rules = dict(zip(FLOOR_IDS, FLOOR_RULE_IDS))
        room_types = list(ROOM_IDS_BY_TYPE)
        for row in self.catalogs["room_template"]:
            wrong_type = copy.deepcopy(row)
            current_type_index = room_types.index(row["room_type"])
            wrong_type["room_type"] = room_types[(current_type_index + 1) % len(room_types)]
            with self.subTest(room=row["id"], mutation="room_type"):
                self.assertTrue(list(validator.iter_errors(wrong_type)))

            missing_rule = copy.deepcopy(row)
            missing_rule["supported_environment_rule_ids"].remove(
                floor_rules[row["floor_ids"][0]]
            )
            if not missing_rule["supported_environment_rule_ids"]:
                missing_rule["supported_environment_rule_ids"].append(
                    next(rule_id for rule_id in FLOOR_RULE_IDS if rule_id not in row["supported_environment_rule_ids"])
                )
            with self.subTest(room=row["id"], mutation="floor_without_rule"):
                self.assertTrue(list(validator.iter_errors(missing_rule)))

            rule_without_floor = copy.deepcopy(row)
            removed_floor = rule_without_floor["floor_ids"].pop(0)
            if not rule_without_floor["floor_ids"]:
                rule_without_floor["floor_ids"].append(
                    next(floor_id for floor_id in FLOOR_IDS if floor_id not in row["floor_ids"])
                )
            self.assertIn(floor_rules[removed_floor], rule_without_floor["supported_environment_rule_ids"])
            with self.subTest(room=row["id"], mutation="rule_without_floor"):
                self.assertTrue(list(validator.iter_errors(rule_without_floor)))

    def test_event_catalog_operations_and_deterministic_channels_are_closed(self) -> None:
        rows = self.catalogs["dungeon_event"]
        self.assertEqual([row["id"] for row in rows if not row["special"]], REGULAR_EVENT_IDS)
        self.assertEqual([row["id"] for row in rows if row["special"]], SPECIAL_EVENT_IDS)
        for row in rows:
            with self.subTest(event=row["id"]):
                self.assertEqual(row["outcome_channel"], "event_outcome_v1")
                self.assertLessEqual(row["floor_min"], row["floor_max"])
                self.assertIn(len(row["options"]), (2, 3))
                for option in row["options"]:
                    self.assertTrue(
                        {op["operation"] for op in option["requirements"]}.issubset(REQUIREMENT_OPERATIONS)
                    )
                    self.assertTrue(option["outcomes"])
                    self.assertEqual(
                        len({outcome["id"] for outcome in option["outcomes"]}),
                        len(option["outcomes"]),
                    )
                    for outcome in option["outcomes"]:
                        self.assertGreater(outcome["weight"], 0)
                        self.assertTrue(outcome["consequences"])
                        self.assertTrue(
                            {op["operation"] for op in outcome["consequences"]}.issubset(CONSEQUENCE_OPERATIONS)
                        )
                    operations = option["requirements"] + [
                        operation
                        for outcome in option["outcomes"]
                        for operation in outcome["consequences"]
                    ]
                    for operation in operations:
                        self.assertTrue(operation["arguments"])
                        self.assertTrue(
                            all(isinstance(value, (str, int, float, bool)) for value in operation["arguments"].values())
                        )
                        if operation["operation"] == "encounter_start":
                            self.assertIn(
                                operation["arguments"].get("encounter_id"),
                                ENCOUNTER_PROFILE_IDS + BOSS_ENCOUNTER_IDS,
                            )
                for option in row["options"]:
                    if option["outcome_visibility"] == "hidden_until_commit":
                        self.assertGreaterEqual(len(option["outcomes"]), 2)

    def test_event_operations_require_exact_arguments_types_and_ranges(self) -> None:
        validator = self.validators["dungeon_event"]
        for contract_name, (kind, valid_arguments, out_of_range_arguments) in OPERATION_CONTRACTS.items():
            operation = contract_name.replace("_requirement", "").replace("_consequence", "")
            valid = self._event_operation_fixture(kind, operation, valid_arguments)
            with self.subTest(operation=contract_name, mutation="valid"):
                self.assertFalse(list(validator.iter_errors(valid)))
            first_key = next(iter(valid_arguments))
            missing = copy.deepcopy(valid_arguments)
            missing.pop(first_key)
            extra = copy.deepcopy(valid_arguments)
            extra["extra"] = 1
            wrong_type = copy.deepcopy(valid_arguments)
            wrong_type[first_key] = []
            for mutation, arguments in [
                ("missing", missing),
                ("extra", extra),
                ("wrong_type", wrong_type),
                ("out_of_range", out_of_range_arguments),
            ]:
                hostile = self._event_operation_fixture(kind, operation, arguments)
                with self.subTest(operation=contract_name, mutation=mutation):
                    self.assertTrue(list(validator.iter_errors(hostile)))

    def test_event_references_close_against_launch_content(self) -> None:
        curses = json.loads((CONTENT_ROOT / "curses.json").read_text(encoding="utf-8"))
        rewards = []
        for filename in ["items.json", "blessings.json"]:
            rewards.extend(json.loads((CONTENT_ROOT / filename).read_text(encoding="utf-8")))
        launch_curse_ids = {
            row["id"] for row in curses if "LAUNCH" in row["availability"]
        }
        launch_rewards = [row for row in rewards if "LAUNCH" in row["availability"]]
        pool_members = {
            "item": [row for row in launch_rewards if row["category"] == "item"],
            "blessing": [row for row in launch_rewards if row["category"] == "blessing"],
            "rare_item": [row for row in launch_rewards if row["category"] == "item" and row["rarity"] == "rare"],
            "rare_blessing": [row for row in launch_rewards if row["category"] == "blessing" and row["rarity"] == "rare"],
        }
        self.assertEqual(set(pool_members), EVENT_REWARD_POOLS)
        self.assertTrue(all(pool_members.values()))
        for row in self.catalogs["dungeon_event"]:
            for option in row["options"]:
                for operation in option["requirements"] + [
                    consequence
                    for outcome in option["outcomes"]
                    for consequence in outcome["consequences"]
                ]:
                    arguments = operation["arguments"]
                    if "curse_id" in arguments:
                        self.assertIn(arguments["curse_id"], launch_curse_ids)
                    if "pool_id" in arguments:
                        self.assertIn(arguments["pool_id"], EVENT_REWARD_POOLS)
                        self.assertTrue(pool_members[arguments["pool_id"]])
                    if "modifier_id" in arguments:
                        self.assertIn(arguments["modifier_id"], EVENT_MODIFIER_IDS)
                    if "resource" in arguments:
                        self.assertIn(arguments["resource"], EVENT_RESOURCES)

    def test_event_schema_rejects_unknown_operations_nested_arguments_and_executable_payloads(self) -> None:
        validator = self.validators["dungeon_event"]
        base = self.catalogs["dungeon_event"][0]
        mutations = []
        unknown_requirement = copy.deepcopy(base)
        unknown_requirement["options"][0]["requirements"][0]["operation"] = "call_script"
        mutations.append(("unknown_requirement", unknown_requirement))
        unknown_consequence = copy.deepcopy(base)
        unknown_consequence["options"][0]["outcomes"][0]["consequences"][0]["operation"] = "call_method"
        mutations.append(("unknown_consequence", unknown_consequence))
        nested = copy.deepcopy(base)
        nested["options"][0]["outcomes"][0]["consequences"][0]["arguments"]["payload"] = {"nested": True}
        mutations.append(("nested_arguments", nested))
        executable_key = copy.deepcopy(base)
        executable_key["options"][0]["outcomes"][0]["consequences"][0]["arguments"]["script_path"] = "safe_id"
        mutations.append(("script_path_key", executable_key))
        executable_value = copy.deepcopy(base)
        executable_value["options"][0]["outcomes"][0]["consequences"][0]["arguments"]["resource"] = "res://hostile.gd"
        mutations.append(("script_path_value", executable_value))
        wrong_special = copy.deepcopy(base)
        wrong_special["special"] = True
        mutations.append(("regular_marked_special", wrong_special))
        for label, hostile in mutations:
            with self.subTest(mutation=label):
                self.assertTrue(list(validator.iter_errors(hostile)))

    def _event_operation_fixture(
        self,
        kind: str,
        operation: str,
        arguments: dict[str, object],
    ) -> dict[str, object]:
        fixture = copy.deepcopy(self.catalogs["dungeon_event"][0])
        for option in fixture["options"]:
            if "outcomes" not in option:
                outcome = {
                    "id": "resolved",
                    "weight": 1,
                    "outcome_key": option.pop("outcome_key"),
                    "consequences": option.pop("consequences"),
                }
                option["outcomes"] = [outcome]
        operation_row = {"operation": operation, "arguments": copy.deepcopy(arguments)}
        if kind == "requirement":
            fixture["options"][0]["requirements"] = [operation_row]
        else:
            fixture["options"][0]["outcomes"][0]["consequences"] = [operation_row]
        return fixture

    def test_merchants_use_exact_closed_services_and_shop_shells(self) -> None:
        for row in self.catalogs["merchant_definition"]:
            with self.subTest(merchant=row["id"]):
                self.assertTrue(set(row["services"]).issubset(MERCHANT_SERVICES))
                self.assertTrue(row["services"])
                self.assertTrue(
                    set(row["shop_room_template_ids"]).issubset(
                        {"room_shop_wayfarer_tent", "room_shop_chrono_emporium"}
                    )
                )
                self.assertEqual(row["economy_profile_id"], "launch_economy_v1")
                rules = row["inventory_rules"]
                self.assertLessEqual(rules["offer_count_min"], rules["offer_count_max"])
                self.assertFalse(rules["allow_duplicates"])

        validator = self.validators["merchant_definition"]
        hostile = copy.deepcopy(self.catalogs["merchant_definition"][0])
        hostile["services"] = ["execute_script"]
        self.assertTrue(list(validator.iter_errors(hostile)))
        hostile = copy.deepcopy(self.catalogs["merchant_definition"][0])
        hostile["inventory_rules"]["offer_count_min"] = -1
        self.assertTrue(list(validator.iter_errors(hostile)))

    def test_launch_economy_has_exact_bands_and_rejects_negative_or_unknown_values(self) -> None:
        profile = self.catalogs["economy_profile"][0]
        expected_bands = [
            (1, 140, 220, 100, 180, 20, 80),
            (2, 180, 280, 150, 240, 20, 90),
            (3, 240, 380, 210, 340, 20, 110),
            (4, 300, 460, 270, 420, 20, 120),
            (5, 280, 430, 250, 400, 0, 100),
        ]
        self.assertEqual(
            [
                (
                    row["floor_index"],
                    row["earned_min"],
                    row["earned_max"],
                    row["spend_min"],
                    row["spend_max"],
                    row["remainder_min"],
                    row["remainder_max"],
                )
                for row in profile["floor_income_budgets"]
            ],
            expected_bands,
        )
        self.assertEqual(len(profile["floor_multipliers"]), 5)
        self.assertEqual(len(profile["gold_caps"]), 5)
        self.assertGreater(profile["reroll_surcharge"]["increment"], 0)
        self.assertGreater(profile["gold_caps"][-1], profile["gold_caps"][0])

        validator = self.validators["economy_profile"]
        for field in ["healing", "curse_cleanse", "reroll", "weapon_upgrade"]:
            hostile = copy.deepcopy(profile)
            hostile["base_prices"][field] = -1
            with self.subTest(base_price=field):
                self.assertTrue(list(validator.iter_errors(hostile)))
        hostile = copy.deepcopy(profile)
        hostile["base_prices"]["debug_purchase"] = 1
        self.assertTrue(list(validator.iter_errors(hostile)))

    def test_all_roots_reject_unknown_fields_missing_identity_and_invalid_localization(self) -> None:
        for category, rows in self.catalogs.items():
            validator = self.validators[category]
            base = rows[0]
            for mutation, transform in [
                ("unknown_root", lambda value: value.update({"script_path": "res://hostile.gd"})),
                ("missing_id", lambda value: value.pop("id")),
                ("invalid_name_key", lambda value: value.update({"name_key": "not_localized"})),
                ("wrong_category", lambda value: value.update({"category": "item"})),
                ("wrong_version", lambda value: value.update({"schema_version": 2})),
            ]:
                hostile = copy.deepcopy(base)
                transform(hostile)
                with self.subTest(category=category, mutation=mutation):
                    self.assertTrue(list(validator.iter_errors(hostile)))

    @classmethod
    def _collect_localization_keys(cls, value: object, result: set[str]) -> None:
        if isinstance(value, dict):
            for key, nested in value.items():
                if key.endswith("_key"):
                    result.add(nested)
                cls._collect_localization_keys(nested, result)
        elif isinstance(value, list):
            for nested in value:
                cls._collect_localization_keys(nested, result)


if __name__ == "__main__":
    unittest.main()
