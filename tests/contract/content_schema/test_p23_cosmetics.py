import copy
import hashlib
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator
from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
PACK = ROOT / "data/content_packs/base"
SCHEMAS = ROOT / "data/schemas"


class CosmeticContractsTest(unittest.TestCase):
    def test_authored_catalog_and_raster_provenance(self):
        rows = json.loads((PACK / "content/cosmetics.json").read_text())
        schema = json.loads((SCHEMAS / "cosmetic_definition_v1.schema.json").read_text())
        validator = Draft202012Validator(schema)
        self.assertEqual(len(rows), 15)
        self.assertEqual(len({row["cosmetic_id"] for row in rows}), 15)
        manifest = json.loads((PACK / "assets/cosmetics/manifest.json").read_text())
        self.assertEqual(manifest["provenance"]["license"], "CC0-1.0")
        self.assertFalse(manifest["provenance"]["third_party_art"])
        self.assertTrue((ROOT / manifest["provenance"]["generator"]).is_file())
        for row in rows:
            self.assertEqual(list(validator.iter_errors(row)), [])
            asset = ROOT / row["atlas_path"].removeprefix("res://")
            self.assertEqual(hashlib.sha256(asset.read_bytes()).hexdigest(), row["atlas_sha256"])
            with Image.open(asset) as image:
                self.assertEqual(image.size, (192, 288))
                self.assertEqual(image.mode, "RGBA")
                for state in range(6):
                    for frame in range(4):
                        self.assertIsNotNone(image.crop((frame * 48, state * 48, (frame + 1) * 48, (state + 1) * 48)).getbbox())
            malformed = copy.deepcopy(row)
            malformed["effects"]["attack"] = 100
            self.assertFalse(validator.is_valid(malformed))
            malformed = copy.deepcopy(row)
            malformed["price"] = 1
            self.assertFalse(validator.is_valid(malformed))
        for character in {row["character_id"] for row in rows}:
            variants = [row for row in rows if row["character_id"] == character]
            self.assertEqual({row["unlock_route"] for row in variants}, {"default", "return", "victory"})
            self.assertEqual(len({row["atlas_sha256"] for row in variants}), 3)

    def test_collection_schema_closes_nested_equipment(self):
        schema = json.loads((SCHEMAS / "cosmetic_collection_v1.schema.json").read_text())
        validator = Draft202012Validator(schema)
        value = {"schema_id": "cosmetic_collection_v1", "schema_version": 1, "catalog_fingerprint": "a" * 64,
                 "claimed_ids": ["wanderer.return"], "equipped_by_character": {"wanderer": "wanderer.return"}}
        self.assertTrue(validator.is_valid(value))
        for field in value:
            missing = copy.deepcopy(value)
            del missing[field]
            self.assertFalse(validator.is_valid(missing))
        for field, replacement in [("claimed_ids", ["wanderer.default"]),
                                   ("claimed_ids", ["wanderer.return", "wanderer.return"]),
                                   ("equipped_by_character", {"wanderer": "time_lord.return"}),
                                   ("equipped_by_character", {"unknown": "wanderer.return"})]:
            malformed = copy.deepcopy(value)
            malformed[field] = replacement
            self.assertFalse(validator.is_valid(malformed))

    def test_base_pack_declares_every_cosmetic_dependency(self):
        pack = json.loads((PACK / "pack.json").read_text())
        self.assertIn("content/cosmetics.json", pack["content_manifest"])
        self.assertIn("localization/cosmetics.csv", pack["localization_sources"])
        for asset in (PACK / "assets/cosmetics").iterdir():
            if asset.suffix not in (".png", ".json", ".txt"):
                continue
            relative = str(asset.relative_to(PACK))
            self.assertIn(relative, pack["asset_manifest"])
            self.assertEqual(pack["integrity_hashes"][relative], hashlib.sha256(asset.read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()
