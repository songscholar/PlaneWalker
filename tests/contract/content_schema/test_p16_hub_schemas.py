import copy
import csv
import json
import unittest
from collections import Counter
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[3]
CONTENT = ROOT / "data/content_packs/base/content"
SCHEMAS = ROOT / "data/schemas"
CATALOGS = {
    "meta_node": "meta_nodes.json",
    "hub_district": "hub_districts.json",
    "forge_definition": "forge_definitions.json",
    "narrative_definition": "narrative_definitions.json",
    "tutorial_definition": "tutorial_definitions.json",
}
WEAPONS = {"sword", "bow", "gun", "staff", "gauntlets"}
NPCS = {"odysseus", "elara", "sibyl", "hermes", "phia", "morpheus", "nemesis", "vera"}
ARTIFACTS = {
    "wardens_badge", "primordial_child_drawing", "void_eroded_saber", "loom_thread",
    "forgekeeper_mask", "stonekeeper_memory", "void_baptism_flask",
    "amplification_core_shard", "walker_demise_letter", "unfinished_weaving",
}
ENDINGS = {
    "return_of_order", "embrace_of_void", "balance_of_ashes",
    "shattered_freedom", "echo_of_primordial",
}


class P16HubSchemasTest(unittest.TestCase):
    def catalog(self, category):
        path = CONTENT / CATALOGS[category]
        self.assertTrue(path.is_file(), f"Missing authoritative P16 catalog: {path}")
        return json.loads(path.read_text())

    def validator(self, category):
        path = SCHEMAS / f"{category}_v1.schema.json"
        self.assertTrue(path.is_file(), f"Missing closed P16 schema: {path}")
        schema = json.loads(path.read_text())
        Draft202012Validator.check_schema(schema)
        return Draft202012Validator(schema)

    def test_authoritative_catalogs_match_closed_schemas(self):
        for category in CATALOGS:
            with self.subTest(category=category):
                entries = self.catalog(category)
                validator = self.validator(category)
                self.assertIsInstance(entries, list)
                self.assertGreater(len(entries), 0)
                self.assertEqual(len({row["id"] for row in entries}), len(entries))
                for entry in entries:
                    self.assertEqual(entry["category"], category)
                    self.assertEqual(entry["effects"], {})
                    self.assertEqual(list(validator.iter_errors(entry)), [])

    def test_unknown_fields_are_rejected_at_every_authored_object_depth(self):
        for category in CATALOGS:
            validator = self.validator(category)
            representatives = {}
            for row in self.catalog(category):
                representatives.setdefault(row.get("definition_kind", category), row)
            for kind, row in representatives.items():
                for path in object_paths(row):
                    mutated = copy.deepcopy(row)
                    cursor = mutated
                    for component in path:
                        cursor = cursor[component]
                    cursor["unexpected_field"] = True
                    with self.subTest(category=category, kind=kind, path=path):
                        self.assertFalse(validator.is_valid(mutated))

    def test_all_forty_two_meta_nodes_have_legal_costs_and_acyclic_prerequisites(self):
        rows = self.catalog("meta_node")
        self.assertEqual(len(rows), 42)
        self.assertEqual(Counter(row["branch"] for row in rows), {"W": 10, "C": 8, "L": 10, "F": 8, "P": 6})
        index = {row["node_id"]: row for row in rows}
        self.assertEqual(set(index), {
            f"{branch}-{number:02d}"
            for branch, count in {"W": 10, "C": 8, "L": 10, "F": 8, "P": 6}.items()
            for number in range(1, count + 1)
        })
        self.assertEqual(index["P-04"]["prerequisites"], ["P-01", "L-09"])
        self.assertEqual(index["L-10"]["cost"], {"chronos_shards": 40, "existential_imprints": 5})
        self.assertEqual(sum(row["cost"]["existential_imprints"] for row in rows), 5)
        visiting, visited = set(), set()

        def visit(node_id):
            self.assertNotIn(node_id, visiting, "Meta prerequisite cycle")
            if node_id in visited:
                return
            visiting.add(node_id)
            for prerequisite in index[node_id]["prerequisites"]:
                self.assertIn(prerequisite, index)
                visit(prerequisite)
            visiting.remove(node_id)
            visited.add(node_id)

        totals = Counter()
        for node_id, row in index.items():
            self.assertEqual(row["id"], "meta_" + node_id.lower().replace("-", "_"))
            visit(node_id)
            for effect in row["meta_effects"]:
                if effect["kind"] == "stat_bonus":
                    totals[effect["stat"]] += effect["magnitude"]
        self.assertEqual(dict(totals), {"max_hp": 0.05, "entrance_healing": 0.02, "void_reduction": 0.02, "attack": 0.03, "attack_speed": 0.02})
        self.assertLessEqual(sum(totals.values()), 0.15)

    def test_three_districts_expose_exactly_nine_native_functions(self):
        rows = self.catalog("hub_district")
        self.assertEqual({row["district_id"] for row in rows}, {"hub_council", "hub_craft", "hub_rift"})
        self.assertEqual(len(rows), 3)
        expected = {
            "hub_council": {"council", "archive", "gateway"},
            "hub_craft": {"training", "forge", "meditation"},
            "hub_rift": {"merchant", "gallery", "mirror"},
        }
        all_functions = []
        for row in rows:
            self.assertEqual({item["id"] for item in row["functions"]}, expected[row["district_id"]])
            self.assertEqual(row["id"], row["district_id"])
            for item in row["functions"]:
                self.assertIn(item["npc_id"], NPCS)
                all_functions.append(item["id"])
        self.assertEqual(len(all_functions), len(set(all_functions)))
        self.assertEqual(len(all_functions), 9)

    def test_forge_preserves_five_weapons_and_fifteen_preferences_without_extra_combat_procs(self):
        rows = self.catalog("forge_definition")
        weapons = [row for row in rows if row["definition_kind"] == "weapon"]
        enchants = [row for row in rows if row["definition_kind"] == "enchantment"]
        self.assertEqual({row["weapon_id"] for row in weapons}, WEAPONS)
        self.assertEqual(len(weapons), 5)
        self.assertEqual({row["enchantment_id"] for row in enchants}, {f"EN-{number:02d}" for number in range(1, 16)})
        self.assertEqual(len(enchants), 15)
        for row in weapons:
            self.assertEqual([level["level"] for level in row["levels"]], [1, 2, 3, 4, 5])
            self.assertEqual([level["cost"]["chronos_shards"] for level in row["levels"]], [5, 10, 20, 35, 50])
            self.assertEqual([level["attack_bonus"] for level in row["levels"]], [0.01] * 5)
            self.assertEqual(row["proficiency_thresholds"], [0, 100, 300, 700, 1500])
            self.assertEqual(set(row["enchantment_ids"]), {item["enchantment_id"] for item in enchants})
            self.assertEqual(row["void_temper_costs"], [{"chronos_shards": 30, "existential_imprints": 0}, {"chronos_shards": 0, "existential_imprints": 3}])
        index = {row["enchantment_id"]: row for row in enchants}
        self.assertEqual({index[key]["exclusive_group"] for key in ["EN-01", "EN-02", "EN-03"]}, {"element"})
        self.assertEqual({index[key]["exclusive_group"] for key in ["EN-04", "EN-05"]}, {"time_void"})
        self.assertEqual(index["EN-14"]["unlock_cost"]["existential_imprints"], 5)
        for row in enchants:
            self.assertEqual(row["effect_policy"], "reward_preference_and_training")

    def test_narrative_has_complete_canonical_collections_arcs_and_ending_eligibility(self):
        rows = self.catalog("narrative_definition")
        kinds = {}
        for row in rows:
            kinds.setdefault(row["definition_kind"], []).append(row)
        self.assertEqual({row["npc_id"] for row in kinds["npc"]}, NPCS)
        self.assertEqual(len(kinds["npc"]), 8)
        for row in kinds["npc"]:
            self.assertEqual(row["depth_thresholds"], [20, 40, 60, 80, 100])
            self.assertEqual(len(row["dialogue_nodes"]), 13)
            self.assertEqual(len({node["id"] for node in row["dialogue_nodes"]}), 13)
        self.assertEqual({row["artifact_id"] for row in kinds["artifact"]}, ARTIFACTS)
        self.assertEqual(len(kinds["artifact"]), 10)
        expected_records = {f"E{floor}-{record}" for floor in range(1, 6) for record in range(1, (5 if floor == 1 else 4) + 1)}
        self.assertEqual({row["record_id"] for row in kinds["environment_record"]}, expected_records)
        self.assertEqual(len(kinds["environment_record"]), 21)
        self.assertEqual({row["storyline_id"] for row in kinds["hidden_line"]}, {"primordial_whispers", "walkers_song", "voice_of_void"})
        self.assertEqual(len(kinds["hidden_line"]), 3)
        for line in kinds["hidden_line"]:
            self.assertEqual([step["index"] for step in line["steps"]], [1, 2, 3, 4, 5])
            self.assertEqual(len({step["source_receipt_id"] for step in line["steps"]}), 5)
        self.assertEqual({row["ending_id"] for row in kinds["ending"]}, ENDINGS)
        self.assertEqual(len(kinds["ending"]), 5)
        endings = {row["ending_id"]: row for row in kinds["ending"]}
        self.assertEqual(endings["shattered_freedom"]["requirements"], [])
        self.assertEqual(endings["echo_of_primordial"]["requirements"], [
            {"kind": "all_hidden_lines_complete", "id": "all", "value": 3},
            {"kind": "all_npc_affinity_min", "id": "all", "value": 80},
            {"kind": "artifact_count_min", "id": "all", "value": 10},
            {"kind": "record_count_min", "id": "all", "value": 21},
            {"kind": "vera_conversation_count_min", "id": "vera", "value": 5},
        ])
        self.assertEqual(len([row for row in kinds["choice"] if row["choice_family"] == "nemesis"]), 5)
        self.assertEqual(len([row for row in kinds["choice"] if row["choice_family"] == "vera"]), 5)

    def test_tutorials_use_receipts_and_explicit_optional_assistance(self):
        rows = self.catalog("tutorial_definition")
        lessons = [row for row in rows if row["definition_kind"] == "lesson"]
        hints = [row for row in rows if row["definition_kind"] == "hint"]
        tasks = [row for row in rows if row["definition_kind"] == "training_task"]
        assistance = [row for row in rows if row["definition_kind"] == "assisted_run"]
        self.assertEqual(len(lessons), 10)
        self.assertEqual({row["sequence"] for row in lessons}, set(range(1, 11)))
        self.assertEqual({row["hint_id"] for row in hints}, {f"TIP-{number:03d}" for number in range(1, 16)})
        self.assertEqual(len(hints), 15)
        self.assertEqual({row["task_id"] for row in tasks}, {f"T-{number:02d}" for number in range(1, 7)})
        self.assertEqual([row["reward"]["chronos_shards"] for row in tasks], [3, 5, 5, 8, 15, 20])
        self.assertEqual([row["incoming_damage_multiplier"] for row in assistance], [0.8, 0.9, 1.0])
        self.assertEqual([row["warning_scale"] for row in assistance], [1.25, 1.1, 1.0])
        for row in assistance:
            self.assertFalse(row["ranked_eligible"])
            self.assertFalse(row["default_enabled"])
        for row in lessons + tasks:
            self.assertGreater(len(row["receipt_requirements"]), 0)
            self.assertTrue(row["repeatable"])
            self.assertTrue(row["skippable"])

    def test_narrative_sources_are_unique_and_optional_vera_defer_is_side_effect_free(self):
        rows = self.catalog("narrative_definition")
        districts = {row["district_id"] for row in self.catalog("hub_district")}
        receipts = []
        balance_choices = []
        for row in rows:
            if "source_receipt_id" in row:
                receipts.append(row["source_receipt_id"])
            if row["definition_kind"] == "npc":
                self.assertIn(row["district_id"], districts)
                nodes = row["dialogue_nodes"]
                self.assertEqual(Counter(node["trigger"]["kind"] for node in nodes), {
                    "npc_intro": 1, "first_death": 1, "floor_completed": 5,
                    "affinity_min": 5, "npc_depth_read": 1,
                })
                for node in nodes:
                    self.assertEqual(len({choice["id"] for choice in node["choices"]}), len(node["choices"]))
                    self.assertTrue(all(choice["once"] for choice in node["choices"]))
                    for choice in node["choices"]:
                        balance_choices.extend((node["id"], flag) for flag in choice["flags"] if flag.startswith("balance_choice_"))
            if row["definition_kind"] == "hidden_line":
                for step in row["steps"]:
                    receipts.append(step["source_receipt_id"])
                    if step["index"] > 1:
                        self.assertIn({"kind": "hidden_step_complete", "id": row["storyline_id"], "value": step["index"] - 1}, step["requirements"])
            if row["definition_kind"] == "choice":
                self.assertEqual(row["consumption_scope"], "profile")
                if row["choice_family"] == "vera":
                    self.assertEqual(row["floor_id"], "floor_throne_of_void")
                    self.assertEqual(row["temporary_max_hp_cost"], 5)
                    options = {choice["id"]: choice for choice in row["options"]}
                    self.assertGreaterEqual(options["listen"]["affinity_delta"] * 5, 80)
                    self.assertTrue(options["listen"]["consumes_source"])
                    self.assertEqual(options["defer"]["affinity_delta"], 0)
                    self.assertEqual(options["defer"]["faction_delta"], {"faction_id": "none", "value": 0})
                    self.assertEqual(options["defer"]["flags"], [])
                    self.assertFalse(options["defer"]["consumes_source"])
        self.assertEqual(len(receipts), len(set(receipts)))
        self.assertEqual(len({source for source, _ in balance_choices}), 3)
        self.assertEqual(len({flag for _, flag in balance_choices}), 3)

    def test_every_p16_localization_reference_has_chinese_and_english_text(self):
        path = ROOT / "data/content_packs/base/localization/translations.csv"
        with path.open(newline="") as handle:
            localized = list(csv.DictReader(handle))
        keys = [row["keys"] for row in localized]
        self.assertEqual(len(keys), len(set(keys)), "Duplicate localization key")
        translations = {row["keys"]: row for row in localized}
        legacy_path = ROOT / "data/localization/translations.csv"
        with legacy_path.open(newline="") as handle:
            legacy_translations = {row["keys"]: row for row in csv.DictReader(handle)}
        for category in CATALOGS:
            for entry in self.catalog(category):
                for key in localization_keys(entry):
                    with self.subTest(category=category, entry=entry["id"], key=key):
                        self.assertTrue(key in translations, f"Missing P16 localization key: {key}")
                        self.assertTrue(translations[key]["en"].strip())
                        self.assertTrue(translations[key]["zh_CN"].strip())
                        self.assertEqual(translations[key], legacy_translations.get(key), "P16 texts differ between localization sources")


def object_paths(value, path=()):
    if isinstance(value, dict):
        yield path
        for key, child in value.items():
            yield from object_paths(child, (*path, key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from object_paths(child, (*path, index))


def localization_keys(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key.endswith("_key"):
                yield child
            else:
                yield from localization_keys(child)
    elif isinstance(value, list):
        for child in value:
            yield from localization_keys(child)


if __name__ == "__main__":
    unittest.main()
