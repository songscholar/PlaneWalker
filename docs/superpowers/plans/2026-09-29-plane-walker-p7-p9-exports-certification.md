# Plane Walker P7/P9 Export Certification Foundation Implementation Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: P7/P9 export-contract and clean-certification foundation plan
- Applies To: Windows, Linux/Steam Deck, and macOS export presets, offline preflight, clean checkout, coverage, and packaged startup
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Scope: First independent P7/P9 slice only; repository export contract and local toolchain preflight
- Exit Gate: Tracked Windows, Linux/Steam Deck, and macOS release presets pass an offline contract; local preflight refuses to report readiness when Godot or export templates are absent
- Not Claimed By This Slice: Successful platform exports, packaged startup, signing, notarization, Steam upload, or complete detached-worktree certification

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a deterministic, offline-runnable contract for the three required desktop exports and a tested local preflight that distinguishes repository defects from missing local toolchain components.

**Architecture:** A tracked JSON manifest is the authoritative export-target contract. A standard-library Python tool parses the manifest, `project.godot`, and `export_presets.cfg`, then optionally inspects the local Godot executable and export-template directory; contract mode never requires network access or installed templates, while local mode fails closed with structured blocker codes. The existing project validation entrypoint runs the Python unit contract and contract-mode preflight so CI continuously protects the tracked configuration.

**Tech Stack:** Godot 4.6.1, Godot export presets, Python 3 standard library, `unittest`, Bash, GitHub Actions validation entrypoint.

## Global Constraints

- Windows, Linux/Steam Deck, and macOS are the required P7 export targets.
- Godot runtime compatibility remains pinned to project feature `4.6`; the current verified executable is `4.6.1.stable.official.14d19694e`.
- The preflight must run without network access and must not install or download anything.
- Missing export templates, signing identities, notarization credentials, Steam identities, and publication accounts are blockers or external operations, never successful evidence.
- Build outputs live below `build/` and remain untracked.
- Exit code zero is insufficient for later real exports; later slices must scan Godot logs and verify artifacts before recording evidence.
- This task must not modify the currently dirty application, reward, curse, or save paths.
- Every report uses stable target IDs and structured issue codes so later detached-checkout certification can consume it without parsing prose.

---

## File Structure

- `data/toolchain/export_targets.json` — authoritative Godot version, template directory, target, preset, artifact, and template-file contract.
- `tools/export/preflight.py` — pure contract validation plus optional local executable/template inspection and deterministic JSON reporting.
- `tests/contract/export/test_export_preflight.py` — repository, fixture, local blocker, local ready, and CLI behavior tests.
- `export_presets.cfg` — tracked release presets named by the manifest; the existing macOS debug preset remains available.
- `tools/validate_project.sh` — invokes the export unit contract and contract-mode report.
- `tests/contract/export/test_export_preflight.py` — also asserts the export contract is part of the one-command validation path.
- `.gitignore` — excludes generated `build/` artifacts.

### Task 1: Add the offline export contract and local preflight

**Files:**

- Create: `data/toolchain/export_targets.json`
- Create: `tools/export/preflight.py`
- Create: `tests/contract/export/test_export_preflight.py`
- Modify: `export_presets.cfg`
- Modify: `tools/validate_project.sh`
- Modify: `.gitignore`

**Interfaces:**

- Consumes: `project.godot`, `export_presets.cfg`, optional `GODOT_BIN`, optional `GODOT_EXPORT_TEMPLATES_DIR`.
- Produces: `validate_contract(project_root: Path) -> dict[str, object]`.
- Produces: `validate_local_environment(report: dict[str, object], godot_bin: str, templates_dir: Path | None) -> dict[str, object]`.
- Produces CLI: `python3 tools/export/preflight.py --mode contract|local [--project-root PATH] [--godot-bin PATH] [--templates-dir PATH] [--json-output PATH]`.
- Exit `0`: every requested check passed.
- Exit `2`: tracked repository contract is invalid.
- Exit `3`: tracked contract passed but the local executable or templates are missing/incompatible.

- [ ] **Step 1: Write the failing export-contract tests**

Create `tests/contract/export/test_export_preflight.py` with tests that import the exact public functions above and assert these cases:

```python
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
EXPORT_TOOLS = PROJECT_ROOT / "tools" / "export"
sys.path.insert(0, str(EXPORT_TOOLS))

from preflight import validate_contract, validate_local_environment  # noqa: E402


class ExportPreflightContractTest(unittest.TestCase):
    def test_repository_contract_declares_all_release_targets(self) -> None:
        report = validate_contract(PROJECT_ROOT)
        self.assertEqual(report["status"], "pass", report["issues"])
        self.assertEqual(
            [target["id"] for target in report["targets"]],
            ["windows-x86_64", "linux-x86_64", "macos-universal"],
        )

    def test_missing_preset_is_a_repository_error(self) -> None:
        with self.fixture_project() as root:
            presets = root / "export_presets.cfg"
            presets.write_text(
                presets.read_text(encoding="utf-8").replace('name="Linux Release"', 'name="Removed Linux"'),
                encoding="utf-8",
            )
            report = validate_contract(root)
        self.assertEqual(report["status"], "error")
        self.assertIn("preset_missing", {issue["code"] for issue in report["issues"]})

    def test_export_path_must_remain_below_build(self) -> None:
        with self.fixture_project() as root:
            manifest_path = root / "data" / "toolchain" / "export_targets.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["targets"][0]["artifact"] = "../PlaneWalker.exe"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            report = validate_contract(root)
        self.assertEqual(report["status"], "error")
        self.assertIn("unsafe_export_path", {issue["code"] for issue in report["issues"]})

    def test_local_mode_reports_missing_templates_as_blocked(self) -> None:
        with self.fixture_project() as root, tempfile.TemporaryDirectory() as temp:
            fake_godot = self.make_fake_godot(Path(temp), "4.6.1.stable.official.test")
            report = validate_local_environment(
                validate_contract(root), str(fake_godot), Path(temp) / "templates"
            )
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(
            {issue["code"] for issue in report["issues"]},
            {"template_missing"},
        )

    def test_local_mode_passes_with_matching_fake_toolchain(self) -> None:
        with self.fixture_project() as root, tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            fake_godot = self.make_fake_godot(temp_path, "4.6.1.stable.official.test")
            templates = temp_path / "templates"
            templates.mkdir()
            for name in ("windows_release_x86_64.exe", "linux_release.x86_64", "macos.zip"):
                (templates / name).write_bytes(b"fixture")
            report = validate_local_environment(validate_contract(root), str(fake_godot), templates)
        self.assertEqual(report["status"], "pass", report["issues"])

    def fixture_project(self):
        owner = self

        class Fixture:
            def __enter__(self) -> Path:
                self.temp = tempfile.TemporaryDirectory()
                root = Path(self.temp.name)
                (root / "data" / "toolchain").mkdir(parents=True)
                (root / "scenes").mkdir()
                for relative in (
                    Path("project.godot"),
                    Path("export_presets.cfg"),
                    Path("data/toolchain/export_targets.json"),
                ):
                    shutil.copy2(owner.PROJECT_ROOT / relative, root / relative)
                (root / "scenes" / "main.tscn").write_text("[gd_scene format=3]\n", encoding="utf-8")
                return root

            def __exit__(self, exc_type, exc, traceback) -> None:
                self.temp.cleanup()

        return Fixture()

    @staticmethod
    def make_fake_godot(directory: Path, version: str) -> Path:
        path = directory / "godot"
        path.write_text(f"#!/usr/bin/env bash\nprintf '%s\\n' '{version}'\n", encoding="utf-8")
        path.chmod(0o755)
        return path
```

- [ ] **Step 2: Run the tests and capture the expected failure**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.export.test_export_preflight
```

Expected: import failure for `preflight` because the tool does not exist yet.

- [ ] **Step 3: Add the authoritative target manifest and release presets**

Create `data/toolchain/export_targets.json` exactly as follows:

```json
{
  "schema_version": "1.0.0",
  "godot": {
    "project_feature": "4.6",
    "version_prefix": "4.6.1.stable.official.",
    "template_version_directory": "4.6.1.stable"
  },
  "targets": [
    {
      "id": "windows-x86_64",
      "preset": "Windows Release",
      "platform": "Windows Desktop",
      "artifact": "build/windows/PlaneWalker.exe",
      "template_files": ["windows_release_x86_64.exe"]
    },
    {
      "id": "linux-x86_64",
      "preset": "Linux Release",
      "platform": "Linux/BSD",
      "artifact": "build/linux/PlaneWalker.x86_64",
      "template_files": ["linux_release.x86_64"]
    },
    {
      "id": "macos-universal",
      "preset": "macOS Release",
      "platform": "macOS",
      "artifact": "build/macos/PlaneWalker.app",
      "template_files": ["macos.zip"]
    }
  ]
}
```

Append three release presets to `export_presets.cfg`. Each preset must use `export_filter="all_resources"`, the manifest artifact path, empty custom-template overrides, and these target-specific values:

```ini
[preset.1]
name="Windows Release"
platform="Windows Desktop"
export_path="build/windows/PlaneWalker.exe"

[preset.1.options]
binary_format/architecture="x86_64"
binary_format/embed_pck=false

[preset.2]
name="Linux Release"
platform="Linux/BSD"
export_path="build/linux/PlaneWalker.x86_64"

[preset.2.options]
binary_format/architecture="x86_64"

[preset.3]
name="macOS Release"
platform="macOS"
export_path="build/macos/PlaneWalker.app"

[preset.3.options]
binary_format/architecture="universal"
codesign/codesign=0
notarization/notarization=0
```

Use the complete common preset keys already present in preset 0; do not leave a section dependent on undocumented parser defaults. Add `build/` to `.gitignore`.

- [ ] **Step 4: Implement deterministic contract parsing and local inspection**

Create `tools/export/preflight.py` with these concrete rules:

```python
EXIT_PASS = 0
EXIT_CONTRACT_ERROR = 2
EXIT_ENVIRONMENT_BLOCKED = 3

def validate_contract(project_root: Path) -> dict[str, object]:
    # Load UTF-8 JSON and the two Godot text configs.
    # Require schema_version == "1.0.0" and exactly the three ordered target IDs.
    # Require project config/features to contain the manifest project_feature.
    # Require run/main_scene to be a res:// path whose file exists.
    # Require unique preset names and one exact preset/platform/artifact match per target.
    # Resolve each artifact against project_root and reject paths outside project_root/build.
    # Return status="error" when any repository issue exists; otherwise status="pass".

def validate_local_environment(
    report: dict[str, object], godot_bin: str, templates_dir: Path | None
) -> dict[str, object]:
    # Preserve repository errors and do not inspect the environment after a contract failure.
    # Resolve a path-like godot_bin directly or a command name with shutil.which.
    # Run [godot, "--version"] with a 10-second timeout.
    # Require the output to start with godot.version_prefix.
    # Resolve templates_dir from the explicit argument, GODOT_EXPORT_TEMPLATES_DIR,
    # or the OS-specific Godot export_templates/<template_version_directory> directory.
    # Add one template_missing issue per absent required file.
    # Return status="blocked" for executable/version/template issues; otherwise "pass".
```

The file must also implement:

```python
def parse_godot_config(path: Path) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {"": {}}
    section = ""
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            sections.setdefault(section, {})
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            sections[section][key.strip()] = value.strip()
    return sections
```

The CLI must write the same sorted, indented JSON to stdout and, when requested, atomically replace `--json-output` through a sibling temporary file. It must select the exit code from report status exactly as specified in the Interfaces section.

- [ ] **Step 5: Run the focused tests and repair only contract defects**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.export.test_export_preflight -v
python3 tools/export/preflight.py --mode contract
python3 tools/export/preflight.py --mode local
```

Expected:

- unit tests pass;
- contract mode exits `0` and reports all three targets;
- local mode exits `3` with `template_missing` because this workstation has Godot 4.6.1 but no installed export templates;
- local mode does not claim any platform export succeeded.

- [ ] **Step 6: Wire the contract into one-command validation**

Insert before Godot bootstrap import in `tools/validate_project.sh`:

```bash
printf '\n== Export contracts ==\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.export.test_export_preflight
PYTHONDONTWRITEBYTECODE=1 python3 tools/export/preflight.py \
    --mode contract \
    --json-output "${validation_log_dir}/export-preflight.json"
```

Add assertions to `tests/contract/export/test_export_preflight.py`:

```python
def test_project_validation_runs_the_export_contract(self) -> None:
    validation_script = (PROJECT_ROOT / "tools" / "validate_project.sh").read_text(
        encoding="utf-8"
    )
    self.assertIn(
        "python3 -m unittest tests.contract.export.test_export_preflight",
        validation_script,
    )
    self.assertIn("python3 tools/export/preflight.py", validation_script)
```

- [ ] **Step 7: Run shell, unit, and project-level regression checks**

Run:

```bash
bash -n tools/validate_project.sh
./tools/test_ci_contract.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.export.test_export_preflight -v
./tools/validate_project.sh
git diff --check
```

Expected: all checks pass; Godot import and scene logs contain no new unclassified errors; the generated contract report identifies repository readiness without asserting local template readiness.

- [ ] **Step 8: Commit only this slice**

```bash
git add \
  .gitignore \
  data/toolchain/export_targets.json \
  docs/superpowers/plans/2026-09-29-plane-walker-p7-p9-exports-certification.md \
  export_presets.cfg \
  tests/contract/export/test_export_preflight.py \
  tools/export/preflight.py \
  tools/validate_project.sh
git diff --cached --check
git commit -m "feat(export): add reproducible toolchain preflight"
```

Expected: the commit excludes all concurrent application, reward, curse, save, and generated-file changes.

## Self-Review

- Spec coverage: this slice covers the tracked three-platform contract and local readiness honesty required before real P7 exports and P9 clean-checkout certification.
- Scope boundary: actual exports, artifact hashes, packaged startup, and detached-worktree orchestration remain later independent slices and are not reported as complete here.
- Type consistency: both tests and CLI use `validate_contract(Path) -> dict` and `validate_local_environment(dict, str, Path | None) -> dict`.
- Evidence integrity: contract mode proves tracked configuration only; local mode proves executable/template availability only; neither mode fabricates a built artifact.
- External boundary: macOS signing/notarization, Steam identity, remote upload, store publication, and private credentials remain external operations.
