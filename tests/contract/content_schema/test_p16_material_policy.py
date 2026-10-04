import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[3]


class P16MaterialPolicyTest(unittest.TestCase):
    def setUp(self):
        self.policy = json.loads((ROOT / "data/content_packs/base/content/meta_material_policy.json").read_text())
        schema = json.loads((ROOT / "data/schemas/meta_material_policy_v1.schema.json").read_text())
        Draft202012Validator.check_schema(schema)
        self.validator = Draft202012Validator(schema)

    def test_authored_policy_pays_only_elite_principals(self):
        self.assertTrue(self.validator.is_valid(self.policy))
        self.assertEqual(self.policy["elite"], {"chronos_shards": 1, "existential_imprints": 0})
        for role in ("ordinary", "boss", "support"):
            self.assertEqual(self.policy[role], {"chronos_shards": 0, "existential_imprints": 0})

    def test_policy_is_closed_at_every_depth(self):
        for role in (None, "ordinary", "elite", "boss", "support"):
            changed = copy.deepcopy(self.policy)
            target = changed if role is None else changed[role]
            target["unexpected"] = True
            with self.subTest(role=role):
                self.assertFalse(self.validator.is_valid(changed))

    def test_support_boss_and_invalid_currency_are_refused(self):
        mutations = [(role, "chronos_shards", 1) for role in ("boss", "support")]
        mutations += [("elite", "chronos_shards", value) for value in (-1, 6, 0.5, True)]
        mutations += [("elite", "existential_imprints", value) for value in (-1, 2, "1", None)]
        for role, currency, value in mutations:
            changed = copy.deepcopy(self.policy)
            changed[role][currency] = value
            with self.subTest(role=role, currency=currency, value=value):
                self.assertFalse(self.validator.is_valid(changed))


if __name__ == "__main__":
    unittest.main()
