from __future__ import annotations

import contextlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Iterator


PROJECT_ROOT = Path(__file__).resolve().parents[3]
EXPORT_TOOLS = PROJECT_ROOT / "tools" / "export"
sys.path.insert(0, str(EXPORT_TOOLS))

from preflight import validate_contract, validate_local_environment  # noqa: E402


EXPECTED_TARGET_IDS = [
    "windows-x86_64",
    "linux-x86_64",
    "macos-universal",
]
EXPECTED_TEMPLATE_FILES = (
    "windows_release_x86_64.exe",
    "linux_release.x86_64",
    "macos.zip",
)


class ExportPreflightContractTest(unittest.TestCase):
    def test_repository_contract_declares_all_release_targets(self) -> None:
        report = validate_contract(PROJECT_ROOT)

        self.assertEqual(report["status"], "pass", report["issues"])
        self.assertEqual(
            [target["id"] for target in report["targets"]],
            EXPECTED_TARGET_IDS,
        )
        self.assertEqual(report["mode"], "contract")
        self.assertEqual(report["godot"]["status"], "not_checked")

    def test_missing_preset_is_a_repository_error(self) -> None:
        with fixture_project() as root:
            presets = root / "export_presets.cfg"
            presets.write_text(
                presets.read_text(encoding="utf-8").replace(
                    'name="Linux Release"',
                    'name="Removed Linux"',
                ),
                encoding="utf-8",
            )

            report = validate_contract(root)

        self.assertEqual(report["status"], "error")
        self.assertIn("preset_missing", issue_codes(report))

    def test_export_path_must_remain_below_build(self) -> None:
        with fixture_project() as root:
            manifest_path = root / "data" / "toolchain" / "export_targets.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["targets"][0]["artifact"] = "../PlaneWalker.exe"
            manifest_path.write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )

            report = validate_contract(root)

        self.assertEqual(report["status"], "error")
        self.assertIn("unsafe_export_path", issue_codes(report))

    def test_preset_platform_and_artifact_must_match_manifest(self) -> None:
        with fixture_project() as root:
            presets = root / "export_presets.cfg"
            text = presets.read_text(encoding="utf-8")
            text = text.replace('platform="Linux/BSD"', 'platform="Windows Desktop"')
            text = text.replace(
                'export_path="build/linux/PlaneWalker.x86_64"',
                'export_path="build/linux/Wrong.x86_64"',
            )
            presets.write_text(text, encoding="utf-8")

            report = validate_contract(root)

        self.assertEqual(report["status"], "error")
        self.assertIn("preset_platform_mismatch", issue_codes(report))
        self.assertIn("preset_export_path_mismatch", issue_codes(report))

    def test_file_exports_must_embed_the_pck(self) -> None:
        with fixture_project() as root:
            presets = root / "export_presets.cfg"
            presets.write_text(
                presets.read_text(encoding="utf-8").replace(
                    "binary_format/embed_pck=true",
                    "binary_format/embed_pck=false",
                    1,
                ),
                encoding="utf-8",
            )

            report = validate_contract(root)

        self.assertEqual(report["status"], "error")
        self.assertIn("preset_embed_pck_required", issue_codes(report))

    def test_local_mode_reports_missing_templates_as_blocked(self) -> None:
        with fixture_project() as root, tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            fake_godot = make_fake_godot(
                temp_path,
                "4.6.1.stable.official.test",
            )

            report = validate_local_environment(
                validate_contract(root),
                str(fake_godot),
                temp_path / "templates",
            )

        self.assertEqual(report["status"], "blocked")
        self.assertEqual(issue_codes(report), {"template_missing"})
        self.assertEqual(report["godot"]["status"], "ready")
        self.assertEqual(
            [target["template_status"] for target in report["targets"]],
            ["missing", "missing", "missing"],
        )

    def test_local_mode_rejects_an_incompatible_godot_version(self) -> None:
        with fixture_project() as root, tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            fake_godot = make_fake_godot(
                temp_path,
                "4.5.2.stable.official.test",
            )
            templates = make_templates(temp_path)

            report = validate_local_environment(
                validate_contract(root),
                str(fake_godot),
                templates,
            )

        self.assertEqual(report["status"], "blocked")
        self.assertIn("godot_version_mismatch", issue_codes(report))
        self.assertEqual(report["godot"]["status"], "blocked")

    def test_local_mode_passes_with_matching_fake_toolchain(self) -> None:
        with fixture_project() as root, tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            fake_godot = make_fake_godot(
                temp_path,
                "4.6.1.stable.official.test",
            )
            templates = make_templates(temp_path)

            report = validate_local_environment(
                validate_contract(root),
                str(fake_godot),
                templates,
            )

        self.assertEqual(report["status"], "pass", report["issues"])
        self.assertEqual(report["mode"], "local")
        self.assertEqual(report["godot"]["status"], "ready")
        self.assertEqual(
            [target["template_status"] for target in report["targets"]],
            ["ready", "ready", "ready"],
        )

    def test_contract_cli_writes_the_same_json_report_to_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            output_path = Path(temp) / "preflight.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(EXPORT_TOOLS / "preflight.py"),
                    "--mode",
                    "contract",
                    "--project-root",
                    str(PROJECT_ROOT),
                    "--json-output",
                    str(output_path),
                ],
                cwd=PROJECT_ROOT,
                check=False,
                capture_output=True,
                text=True,
            )

            stdout_report = json.loads(result.stdout)
            file_report = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stdout_report, file_report)
        self.assertEqual(stdout_report["status"], "pass")

    def test_project_validation_runs_the_export_contracts(self) -> None:
        validation_script = (PROJECT_ROOT / "tools" / "validate_project.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("tests.contract.export.test_export_preflight", validation_script)
        self.assertIn("tests.contract.export.test_export_executor", validation_script)
        self.assertIn("python3 tools/export/preflight.py", validation_script)

    def test_local_cli_uses_exit_three_for_environment_blockers(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            fake_godot = make_fake_godot(
                temp_path,
                "4.6.1.stable.official.test",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(EXPORT_TOOLS / "preflight.py"),
                    "--mode",
                    "local",
                    "--project-root",
                    str(PROJECT_ROOT),
                    "--godot-bin",
                    str(fake_godot),
                    "--templates-dir",
                    str(temp_path / "templates"),
                ],
                cwd=PROJECT_ROOT,
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "blocked")


def issue_codes(report: dict[str, object]) -> set[str]:
    return {
        str(issue["code"])
        for issue in report["issues"]
        if isinstance(issue, dict)
    }


@contextlib.contextmanager
def fixture_project() -> Iterator[Path]:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        (root / "data" / "toolchain").mkdir(parents=True)
        (root / "scenes").mkdir()
        for relative in (
            Path("project.godot"),
            Path("export_presets.cfg"),
            Path("data/toolchain/export_targets.json"),
        ):
            shutil.copy2(PROJECT_ROOT / relative, root / relative)
        (root / "scenes" / "main.tscn").write_text(
            "[gd_scene format=3]\n",
            encoding="utf-8",
        )
        yield root


def make_fake_godot(directory: Path, version: str) -> Path:
    path = directory / "godot"
    path.write_text(
        "#!/usr/bin/env bash\n"
        "set -eu\n"
        f"printf '%s\\n' '{version}'\n",
        encoding="utf-8",
    )
    path.chmod(0o755)
    return path


def make_templates(directory: Path) -> Path:
    templates = directory / "templates"
    templates.mkdir()
    for name in EXPECTED_TEMPLATE_FILES:
        (templates / name).write_bytes(b"fixture")
    return templates


if __name__ == "__main__":
    unittest.main()
