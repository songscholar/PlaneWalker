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


class LocalizationContractTest(unittest.TestCase):
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
