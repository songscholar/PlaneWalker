from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
COLLECTOR = PROJECT_ROOT / "tools" / "coverage" / "collect_gdscript_coverage.py"


class GDScriptCoverageCollectorContractTest(unittest.TestCase):
    def test_stock_godot_without_line_provider_fails_closed_with_retained_report(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            godot = write_fake_godot(root, include_coverage_flag=False)
            output = root / "artifacts" / "gdscript-coverage.json"

            result = run_collector(root, godot, output)
            report = read_json(output)

        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(report["status"], "unavailable")
        self.assertEqual(report["classification"], "godot_line_coverage_unsupported")
        self.assertEqual(report["language"], "GDScript")
        self.assertEqual(report["metric"], "line")
        self.assertFalse(report["capabilities"]["godot_cli_line_coverage"])
        self.assertFalse(report["capabilities"]["scene_counts_are_coverage"])
        self.assertIn("4.6.1.stable.test", report["engine"]["version"])
        self.assertIn("not collected", result.stdout)

    def test_verified_instrumented_line_hits_are_normalized_as_real_coverage(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "scripts" / "example.gd"
            source.parent.mkdir(parents=True)
            source.write_text(
                "extends RefCounted\n\nfunc value(flag: bool) -> int:\n"
                "\tif flag:\n\t\treturn 1\n\treturn 0\n",
                encoding="utf-8",
            )
            provider = root / "provider.json"
            provider.write_text(
                json.dumps(
                    provider_report(
                        source,
                        executable_lines=[3, 4, 5, 6],
                        covered_lines=[3, 4, 5],
                    )
                ),
                encoding="utf-8",
            )
            output = root / "artifacts" / "gdscript-coverage.json"
            godot = write_fake_godot(root, include_coverage_flag=False)

            result = run_collector(root, godot, output, provider)
            report = read_json(output)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["status"], "collected")
        self.assertEqual(report["classification"], "verified_instrumented_line_coverage")
        self.assertEqual(report["summary"]["files"], 1)
        self.assertEqual(report["summary"]["executable_lines"], 4)
        self.assertEqual(report["summary"]["covered_lines"], 3)
        self.assertEqual(report["summary"]["line_rate"], 0.75)
        self.assertEqual(report["files"][0]["path"], "scripts/example.gd")
        self.assertEqual(report["files"][0]["missing_lines"], [6])
        self.assertIn("collected", result.stdout)

    def test_aggregate_counts_without_per_line_hits_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            provider = root / "provider.json"
            provider.write_text(
                json.dumps(
                    {
                        "schema_version": "1.0.0",
                        "status": "collected",
                        "language": "GDScript",
                        "metric": "line",
                        "provider": {
                            "name": "scene-counter",
                            "version": "1",
                            "mode": "scene_execution_counts",
                        },
                        "summary": {"covered_lines": 48, "executable_lines": 48},
                    }
                ),
                encoding="utf-8",
            )
            output = root / "gdscript-coverage.json"
            godot = write_fake_godot(root, include_coverage_flag=False)

            result = run_collector(root, godot, output, provider)
            report = read_json(output)

        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertEqual(report["status"], "invalid")
        self.assertEqual(report["classification"], "provider_report_invalid")
        self.assertIn("instrumented_runtime", report["issues"][0]["message"])

    def test_source_digest_drift_rejects_stale_line_hits(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "scripts" / "example.gd"
            source.parent.mkdir(parents=True)
            source.write_text("extends RefCounted\nfunc value() -> int:\n\treturn 1\n", encoding="utf-8")
            report_value = provider_report(source, executable_lines=[2, 3], covered_lines=[2, 3])
            report_value["files"][0]["source_sha256"] = "0" * 64
            provider = root / "provider.json"
            provider.write_text(json.dumps(report_value), encoding="utf-8")
            output = root / "gdscript-coverage.json"
            godot = write_fake_godot(root, include_coverage_flag=False)

            result = run_collector(root, godot, output, provider)
            report = read_json(output)

        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertEqual(report["status"], "invalid")
        self.assertEqual(report["issues"][0]["code"], "source_digest_mismatch")

    def test_non_utf8_source_fails_closed_with_retained_report(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "scripts" / "invalid.gd"
            source.parent.mkdir(parents=True)
            source.write_bytes(b"extends RefCounted\n\xff\n")
            provider = root / "provider.json"
            provider.write_text(
                json.dumps(
                    provider_report(
                        source,
                        executable_lines=[1],
                        covered_lines=[1],
                    )
                ),
                encoding="utf-8",
            )
            output = root / "gdscript-coverage.json"
            godot = write_fake_godot(root, include_coverage_flag=False)

            result = run_collector(root, godot, output, provider)
            report = read_json(output)

        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertEqual(report["status"], "invalid")
        self.assertEqual(report["issues"][0]["code"], "coverage_source_unreadable")


def run_collector(
    root: Path,
    godot: Path,
    output: Path,
    provider: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(COLLECTOR),
        "--project-root",
        str(root),
        "--godot-bin",
        str(godot),
        "--output",
        str(output),
    ]
    if provider is not None:
        command.extend(["--provider-report", str(provider)])
    return subprocess.run(command, capture_output=True, text=True, check=False)


def write_fake_godot(root: Path, *, include_coverage_flag: bool) -> Path:
    path = root / "godot"
    help_line = "  --coverage FILE  collect line coverage" if include_coverage_flag else "  --profiling  profile scripts"
    path.write_text(
        "#!/usr/bin/env bash\n"
        "set -eu\n"
        "case \"${1:-}\" in\n"
        "  --version) printf '%s\\n' '4.6.1.stable.test' ;;\n"
        f"  --help) printf '%s\\n' '{help_line}' ;;\n"
        "  *) exit 2 ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    path.chmod(0o755)
    return path


def provider_report(
    source: Path,
    *,
    executable_lines: list[int],
    covered_lines: list[int],
) -> dict[str, object]:
    return {
        "schema_version": "1.0.0",
        "status": "collected",
        "language": "GDScript",
        "metric": "line",
        "provider": {
            "name": "fixture-instrumenter",
            "version": "1.0.0",
            "mode": "instrumented_runtime",
        },
        "files": [
            {
                "path": source.relative_to(source.parents[1]).as_posix(),
                "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "executable_lines": executable_lines,
                "covered_lines": covered_lines,
            }
        ],
    }


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
