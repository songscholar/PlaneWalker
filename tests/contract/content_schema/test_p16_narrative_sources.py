import copy
import csv
import json
import unittest
from collections import Counter
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[3]
CONTENT = ROOT / "data/content_packs/base/content"
FLOOR_BOSSES = {
    "floor_ruins_of_remnant": "ruin_king",
    "floor_void_forest": "forest_heart",
    "floor_time_rift": "time_sovereign",
    "floor_plane_forge": "forge_colossus",
    "floor_throne_of_void": "void_throne",
}


class P16NarrativeSourcesTest(unittest.TestCase):
    def setUp(self):
        source_path = CONTENT / "narrative_sources.json"
        schema_path = ROOT / "data/schemas/narrative_source_definition_v1.schema.json"
        self.assertTrue(source_path.is_file(), "Authored narrative sources exist")
        self.assertTrue(schema_path.is_file(), "Closed narrative source schema exists")
        self.rows = json.loads(source_path.read_text())
        schema = json.loads(schema_path.read_text())
        Draft202012Validator.check_schema(schema)
        self.validator = Draft202012Validator(schema)

    def test_sources_have_finite_unique_identity_and_valid_schema(self):
        self.assertEqual(Counter(row["source_kind"] for row in self.rows), {
            "phia_marker": 5, "walker_letter": 3, "heart_fragment": 5,
        })
        for field in ["id", "source_receipt_id", "location_id"]:
            self.assertEqual(len({row[field] for row in self.rows}), 13)
        for row in self.rows:
            self.assertEqual(list(self.validator.iter_errors(row)), [])
            self.assertEqual(row["consumption_scope"], "profile")
            self.assertEqual(row["effects"], {})
            self.assertEqual(row["id"], "source_" + row["source_receipt_id"])

    def test_floor_bound_sources_and_heart_requirements_are_authored(self):
        for kind, size in [("phia_marker", 5), ("walker_letter", 3), ("heart_fragment", 5)]:
            rows = [row for row in self.rows if row["source_kind"] == kind]
            self.assertEqual({row["sequence"] for row in rows}, set(range(1, size + 1)))
            for row in rows:
                self.assertEqual(row["source_receipt_id"], f"{kind}_{row['sequence']}")
                self.assertIn(row["floor_id"], FLOOR_BOSSES)
                if kind == "phia_marker":
                    self.assertEqual(row["floor_id"], "floor_ruins_of_remnant")
                if kind == "heart_fragment":
                    self.assertEqual(row["requirements"], [{
                        "kind": "boss_defeated", "id": FLOOR_BOSSES[row["floor_id"]], "value": 1,
                    }])
        hearts = [row for row in self.rows if row["source_kind"] == "heart_fragment"]
        self.assertEqual({row["floor_id"] for row in hearts}, set(FLOOR_BOSSES))
        self.assertEqual(len(json.loads((CONTENT / "narrative_definitions.json").read_text())), 57)

    def test_nested_unknown_fields_and_bad_receipts_are_rejected(self):
        for row in self.rows:
            for mutate in ["extra", "fraction", "unknown_floor", "wrong_scope", "wrong_kind"]:
                bad = copy.deepcopy(row)
                if mutate == "extra":
                    bad["extra_reward"] = 100
                elif mutate == "fraction":
                    bad["sequence"] = 1.5
                elif mutate == "unknown_floor":
                    bad["floor_id"] = "floor_unknown"
                elif mutate == "wrong_scope":
                    bad["consumption_scope"] = "run"
                else:
                    bad["source_kind"] = "currency"
                self.assertFalse(self.validator.is_valid(bad), mutate)
            for index in range(len(row["requirements"])):
                bad = copy.deepcopy(row)
                bad["requirements"][index]["grant_shards"] = 50
                self.assertFalse(self.validator.is_valid(bad))

    def test_every_authored_source_has_identical_complete_bilingual_text(self):
        localizations = []
        for path in [ROOT / "data/localization/translations.csv", ROOT / "data/content_packs/base/localization/translations.csv"]:
            with path.open(newline="") as stream:
                entries = list(csv.DictReader(stream))
            localizations.append({row["keys"]: row for row in entries})
        for source in self.rows:
            for field in ["name_key", "description_key", "text_key"]:
                key = source[field]
                for locale in localizations:
                    self.assertIn(key, locale)
                    self.assertTrue(locale[key]["en"].strip())
                    self.assertTrue(locale[key]["zh_CN"].strip())
                self.assertEqual(localizations[0][key], localizations[1][key])


if __name__ == "__main__":
    unittest.main()
