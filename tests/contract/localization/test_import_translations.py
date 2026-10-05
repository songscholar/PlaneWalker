from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "tools/validate_import_translations.py"
classifier = None
if MODULE_PATH.is_file():
    spec = importlib.util.spec_from_file_location("import_translation_classifier", MODULE_PATH)
    classifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(classifier)


class ImportTranslationsTest(unittest.TestCase):
    def require_classifier(self):
        self.assertIsNotNone(classifier, "configured CSV import classifier must exist")
        return classifier

    def project(self, root: Path, catalogs: list[str]) -> None:
        resources = []
        for catalog in catalogs:
            path = root / catalog
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("keys,en,zh_CN\nTITLE,Title,Chinese\n", encoding="utf-8")
            resources.extend(f'"res://{catalog[:-4]}.{locale}.translation"' for locale in ["en", "zh_CN"])
        (root / "project.godot").write_text(
            '[internationalization]\nlocale/translations=PackedStringArray(' + ", ".join(resources) + ")\n",
            encoding="utf-8",
        )

    def misses(self, stem: str, locales=("en", "zh_CN")) -> list[str]:
        return [f"ERROR: Failed loading resource: res://{stem}.{locale}.translation." for locale in locales]

    def test_bootstrap_accepts_all_configured_csv_pairs(self):
        api = self.require_classifier()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.project(root, ["data/localization/translations.csv", "assets/production/localization/community.csv"])
            errors = self.misses("data/localization/translations") + self.misses("assets/production/localization/community")
            remaining, regenerated = api.classify(root, "bootstrap", errors)
            self.assertEqual(remaining, [])
            self.assertEqual(len(regenerated), 2)

    def test_clean_import_and_unknown_csv_resources_remain_errors(self):
        api = self.require_classifier()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.project(root, ["data/localization/translations.csv"])
            configured = self.misses("data/localization/translations")
            unknown = self.misses("assets/production/localization/unconfigured")
            self.assertEqual(api.classify(root, "clean", configured)[0], configured)
            self.assertEqual(api.classify(root, "bootstrap", unknown)[0], unknown)

    def test_partial_language_pair_and_unconfigured_sibling_fail(self):
        api = self.require_classifier()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.project(root, ["data/localization/translations.csv"])
            partial = self.misses("data/localization/translations", ("en",))
            with self.assertRaisesRegex(ValueError, "both generated translations"):
                api.classify(root, "bootstrap", partial)
            project = root / "project.godot"
            project.write_text(project.read_text().replace(', "res://data/localization/translations.zh_CN.translation"', ""))
            with self.assertRaises(ValueError):
                api.classify(root, "bootstrap", self.misses("data/localization/translations"))

    def test_absent_invalid_or_escaping_csv_cannot_be_waived(self):
        api = self.require_classifier()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.project(root, ["data/localization/translations.csv"])
            source = root / "data/localization/translations.csv"
            for text in ["invalid,header\n", "keys,en,zh_CN\nTITLE,,Chinese\n"]:
                source.write_text(text)
                with self.assertRaises(ValueError):
                    api.classify(root, "bootstrap", self.misses("data/localization/translations"))
            source.unlink()
            with self.assertRaises(ValueError):
                api.classify(root, "bootstrap", self.misses("data/localization/translations"))
            (root / "project.godot").write_text('[internationalization]\nlocale/translations=PackedStringArray("res://../escape.en.translation")\n')
            with self.assertRaises(ValueError):
                api.classify(root, "bootstrap", self.misses("../escape", ("en",)))


if __name__ == "__main__":
    unittest.main()
