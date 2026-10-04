from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT_ROOT / "tools"))

from validate_localization import validate_localization  # noqa: E402


REQUIRED_DOMAIN_KEYS = (
    "ROOM_TYPE_COMBAT",
    "ROOM_TYPE_ELITE",
    "ROOM_TYPE_BOSS",
    "ROOM_TYPE_EVENT",
    "RESULT_DEATH",
    "RESULT_FLOOR_CLEARED",
)
SEMANTIC_INPUT_TRANSLATIONS = {
    "INPUT_ACTION_WEAPON_PRIMARY": ("Weapon Primary", "武器主动作"),
    "INPUT_ACTION_WEAPON_SECONDARY": ("Weapon Secondary", "武器副动作"),
    "INPUT_ACTION_WEAPON_UTILITY": ("Weapon Utility", "武器功能"),
    "INPUT_ACTION_WEAPON_SKILL": ("Weapon Skill", "武器技能"),
    "INPUT_ACTION_WEAPON_ULTIMATE": ("Weapon Ultimate", "武器终极技"),
	"INPUT_ACTION_TIME_SLOT_1": ("Time Ability 1", "时间能力 1"),
	"INPUT_ACTION_TIME_SLOT_2": ("Time Ability 2", "时间能力 2"),
	"INPUT_ACTION_CHARACTER_SKILL": ("Character Skill", "角色技能"),
}


class LocalizationContractTest(unittest.TestCase):
    def test_reads_only_configured_supplemental_runtime_catalogs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(root, [])
            self._write(root / "assets/ui.csv", "keys,en,zh_CN\nUI_EXTRA,Extra,Extra\n")
            self._write(root / "scripts/ui.gd", 'label.text = tr("UI_EXTRA")\n')
            self.assertContainsCode(validate_localization(root), "missing-code-key")
            self._write(root / "project.godot", '[internationalization]\nlocale/translations=PackedStringArray("res://assets/ui.en.translation", "res://assets/ui.zh_CN.translation")\n')
            self.assertEqual(validate_localization(root), [])

    def test_checks_missing_or_invalid_configured_catalog(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(root, [])
            self._write(root / "project.godot", '[internationalization]\nlocale/translations=PackedStringArray("res://assets/missing.en.translation")\n')
            self.assertContainsCode(validate_localization(root), "missing-catalog")
            self._write(root / "assets/missing.csv", "keys,en,zh_CN\nUI_EXTRA,%d,%s\n")
            self.assertContainsCode(validate_localization(root), "placeholder-mismatch")

    def test_rejects_ambiguous_runtime_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(root, [["UI_EXTRA", "Main", "Main"]])
            self._write(root / "assets/ui.csv", "keys,en,zh_CN\nUI_EXTRA,Extra,Extra\n")
            self._write(root / "project.godot", '[internationalization]\nlocale/translations=PackedStringArray("res://assets/ui.en.translation")\n')
            self.assertContainsCode(validate_localization(root), "duplicate-runtime-key")

    def test_rejects_configured_catalog_escape(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(root, [])
            self._write(root / "project.godot", '[internationalization]\nlocale/translations=PackedStringArray("res://../outside.en.translation")\n')
            self.assertContainsCode(validate_localization(root), "invalid-runtime-catalog-config")

    def test_semantic_input_rows_match_in_global_and_base_catalogs(self) -> None:
        catalogs = (
            PROJECT_ROOT / "data" / "localization" / "translations.csv",
            PROJECT_ROOT
            / "data"
            / "content_packs"
            / "base"
            / "localization"
            / "translations.csv",
        )
        for catalog in catalogs:
            with self.subTest(catalog=catalog):
                with catalog.open(encoding="utf-8", newline="") as handle:
                    rows = {row["keys"]: row for row in csv.DictReader(handle)}
                actual = {
                    key: (rows[key]["en"], rows[key]["zh_CN"])
                    for key in SEMANTIC_INPUT_TRANSLATIONS
                }
                self.assertEqual(actual, SEMANTIC_INPUT_TRANSLATIONS)

    def test_valid_catalog_covers_code_and_content_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(
                root,
                [
                    ["UI_TITLE", "Plane Walker", "位面行者"],
                    ["UI_SCORE_FMT", "Score %d%%", "分数 %d%%"],
                    ["ITEM_NAME", "Clock", "时钟"],
                    ["ITEM_DESC", "Attack 25% faster.", "攻击加快 25%。"],
                ],
            )
            self._write(root / "scripts" / "hud.gd", 'label.text = tr("UI_TITLE")\n')
            self._write_json(
                root / "data" / "items" / "items.json",
                [{"id": "clock", "name": "ITEM_NAME", "description": "ITEM_DESC"}],
            )

            self.assertEqual(validate_localization(root), [])

    def test_reports_duplicate_and_empty_translations(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(
                root,
                [
                    ["UI_TITLE", "Plane Walker", "位面行者"],
                    ["UI_TITLE", "Duplicate", "重复"],
                    ["UI_EMPTY_EN", "", "仅中文"],
                    ["UI_EMPTY_ZH", "English only", ""],
                ],
            )

            violations = validate_localization(root)

            self.assertContainsCode(violations, "duplicate-key")
            self.assertContainsCode(violations, "empty-en")
            self.assertContainsCode(violations, "empty-zh_CN")

    def test_reports_placeholder_order_or_type_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(
                root,
                [
                    ["GOOD", "HP %.1f / %d%%", "生命 %.1f / %d%%"],
                    ["BAD_TYPE", "Room %d", "房间 %s"],
                    ["BAD_ORDER", "%s scored %d", "%d 分属于 %s"],
                ],
            )

            violations = validate_localization(root)

            placeholder_violations = [
                violation for violation in violations if violation.code == "placeholder-mismatch"
            ]
            self.assertEqual(
                {violation.key for violation in placeholder_violations},
                {"BAD_TYPE", "BAD_ORDER"},
            )

    def test_reports_missing_literal_tr_and_content_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(root, [["KNOWN", "Known", "已知"]])
            self._write(
                root / "scripts" / "hud.gd",
                'label.text = tr("MISSING_CODE")\nlabel.text = tr(str(dynamic_key))\n',
            )
            self._write_json(
                root / "data" / "items" / "items.json",
                [
                    {
                        "id": "clock",
                        "name": "MISSING_NAME",
                        "description_key": "MISSING_DESC",
                    }
                ],
            )

            violations = validate_localization(root)

            missing = {(violation.code, violation.key) for violation in violations}
            self.assertIn(("missing-code-key", "MISSING_CODE"), missing)
            self.assertIn(("missing-content-key", "MISSING_NAME"), missing)
            self.assertIn(("missing-content-key", "MISSING_DESC"), missing)
            self.assertNotIn(("missing-code-key", "dynamic_key"), missing)

    def test_reports_keys_derived_from_archetype_and_risk_values(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(
                root,
                [
                    ["ITEM_NAME", "Clock", "时钟"],
                    ["ITEM_DESC", "A volatile clock.", "一枚不稳定的时钟。"],
                ],
            )
            self._write_json(
                root / "data" / "items" / "items.json",
                [
                    {
                        "id": "volatile_clock",
                        "name": "ITEM_NAME",
                        "description": "ITEM_DESC",
                        "archetype": "freeze_burst",
                        "risk": "time_skill",
                    }
                ],
            )

            violations = validate_localization(root)

            missing_derived = {
                violation.key
                for violation in violations
                if violation.code == "missing-derived-key"
            }
            self.assertEqual(
                missing_derived,
                {"ARCHETYPE_FREEZE_BURST", "RISK_TIME_SKILL"},
            )

    def test_ignores_schema_metadata_that_is_not_runtime_content(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(root, [])
            self._write_json(
                root / "data" / "schemas" / "session.schema.json",
                {
                    "$schema": "https://json-schema.org/draft/2020-12/schema",
                    "description": "Human-readable schema metadata, not a localization key.",
                    "properties": {
                        "description": {
                            "description": "Another schema annotation.",
                            "type": "string",
                        }
                    },
                },
            )

            self.assertEqual(validate_localization(root), [])

    def test_reports_missing_fixed_room_and_result_domain_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_catalog(root, [], include_required=False)

            violations = validate_localization(root)

            missing_required = {
                violation.key
                for violation in violations
                if violation.code == "missing-required-key"
            }
            self.assertEqual(missing_required, set(REQUIRED_DOMAIN_KEYS))

    def assertContainsCode(self, violations: list, code: str) -> None:  # noqa: N802
        self.assertIn(code, [violation.code for violation in violations])

    @staticmethod
    def _write_catalog(
        root: Path,
        rows: list[list[str]],
        include_required: bool = True,
    ) -> None:
        path = root / "data" / "localization" / "translations.csv"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["keys", "en", "zh_CN"])
            if include_required:
                writer.writerows(
                    [[key, key.replace("_", " "), key] for key in REQUIRED_DOMAIN_KEYS]
                )
            writer.writerows(rows)

    @staticmethod
    def _write(path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    @staticmethod
    def _write_json(path: Path, content: object) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(content), encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
