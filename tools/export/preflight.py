#!/usr/bin/env python3
"""Validate Plane Walker's tracked export contract and local Godot toolchain."""

from __future__ import annotations

import argparse
import copy
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any, Sequence


EXIT_PASS = 0
EXIT_CONTRACT_ERROR = 2
EXIT_ENVIRONMENT_BLOCKED = 3

MANIFEST_RELATIVE_PATH = Path("data/toolchain/export_targets.json")
EXPECTED_SCHEMA_VERSION = "1.0.0"
EXPECTED_TARGET_IDS = (
    "windows-x86_64",
    "linux-x86_64",
    "macos-universal",
)


def parse_godot_config(path: Path) -> dict[str, dict[str, str]]:
    """Parse the scalar subset of Godot text configs used by this contract."""

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


def validate_contract(project_root: Path) -> dict[str, object]:
    """Validate only tracked repository configuration; never inspect the host."""

    root = project_root.expanduser().resolve()
    issues: list[dict[str, str]] = []
    manifest = _load_manifest(root / MANIFEST_RELATIVE_PATH, issues)
    godot_contract = manifest.get("godot") if isinstance(manifest, dict) else None
    if not isinstance(godot_contract, dict):
        _add_issue(
            issues,
            "manifest_godot_invalid",
            "error",
            "manifest godot must be an object",
        )
        godot_contract = {}

    project_feature = _required_string(
        godot_contract,
        "project_feature",
        issues,
        "manifest_godot_invalid",
    )
    version_prefix = _required_string(
        godot_contract,
        "version_prefix",
        issues,
        "manifest_godot_invalid",
    )
    template_version = _required_string(
        godot_contract,
        "template_version_directory",
        issues,
        "manifest_godot_invalid",
    )

    project_config = _load_config(root / "project.godot", issues, "project_config_invalid")
    export_config = _load_config(
        root / "export_presets.cfg",
        issues,
        "export_presets_invalid",
    )
    _validate_project_config(root, project_config, project_feature, issues)
    presets = _index_presets(export_config, issues)

    raw_targets = manifest.get("targets") if isinstance(manifest, dict) else None
    if not isinstance(raw_targets, list):
        _add_issue(
            issues,
            "manifest_targets_invalid",
            "error",
            "manifest targets must be an array",
        )
        raw_targets = []

    actual_target_ids = [
        target.get("id") if isinstance(target, dict) else None
        for target in raw_targets
    ]
    if actual_target_ids != list(EXPECTED_TARGET_IDS):
        _add_issue(
            issues,
            "target_set_mismatch",
            "error",
            "targets must be ordered as " + ", ".join(EXPECTED_TARGET_IDS),
        )

    targets: list[dict[str, object]] = []
    seen_target_ids: set[str] = set()
    for index, raw_target in enumerate(raw_targets):
        targets.append(
            _validate_target(
                root,
                index,
                raw_target,
                presets,
                seen_target_ids,
                issues,
            )
        )

    report: dict[str, object] = {
        "schema_version": EXPECTED_SCHEMA_VERSION,
        "mode": "contract",
        "status": "error" if issues else "pass",
        "project_root": str(root),
        "manifest": MANIFEST_RELATIVE_PATH.as_posix(),
        "godot": {
            "required_project_feature": project_feature,
            "required_version_prefix": version_prefix,
            "template_version_directory": template_version,
            "binary": None,
            "detected_version": None,
            "templates_dir": None,
            "status": "not_checked",
        },
        "targets": targets,
        "issues": issues,
    }
    return report


def validate_local_environment(
    report: dict[str, object],
    godot_bin: str,
    templates_dir: Path | None,
) -> dict[str, object]:
    """Extend a passing repository report with local executable/template checks."""

    result = copy.deepcopy(report)
    result["mode"] = "local"
    if result.get("status") == "error":
        return result

    issues = result.get("issues")
    targets = result.get("targets")
    godot = result.get("godot")
    if not isinstance(issues, list) or not isinstance(targets, list) or not isinstance(godot, dict):
        raise ValueError("contract report has an invalid shape")

    resolved_godot = _resolve_executable(godot_bin)
    godot["binary"] = str(resolved_godot) if resolved_godot else None
    godot["status"] = "blocked"
    if resolved_godot is None:
        _add_issue(
            issues,
            "godot_not_found",
            "blocked",
            f"Godot executable was not found or is not runnable: {godot_bin}",
        )
    else:
        try:
            completed = subprocess.run(
                [str(resolved_godot), "--version"],
                check=False,
                capture_output=True,
                text=True,
                timeout=10,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            _add_issue(
                issues,
                "godot_version_unreadable",
                "blocked",
                f"Godot version check failed: {error}",
            )
        else:
            detected_version = completed.stdout.strip().splitlines()
            version = detected_version[0].strip() if detected_version else ""
            godot["detected_version"] = version or None
            required_prefix = str(godot.get("required_version_prefix") or "")
            if completed.returncode != 0 or not version:
                _add_issue(
                    issues,
                    "godot_version_unreadable",
                    "blocked",
                    f"Godot --version exited {completed.returncode} without a version",
                )
            elif not version.startswith(required_prefix):
                _add_issue(
                    issues,
                    "godot_version_mismatch",
                    "blocked",
                    f"Godot {version} does not match required prefix {required_prefix}",
                )
            else:
                godot["status"] = "ready"

    resolved_templates = _resolve_templates_dir(godot, templates_dir)
    godot["templates_dir"] = str(resolved_templates)
    for target in targets:
        if not isinstance(target, dict):
            continue
        target["template_status"] = "ready"
        template_files = target.get("template_files")
        if not isinstance(template_files, list):
            target["template_status"] = "missing"
            continue
        for template_name in template_files:
            template_path = resolved_templates / str(template_name)
            if template_path.is_file():
                continue
            target["template_status"] = "missing"
            _add_issue(
                issues,
                "template_missing",
                "blocked",
                f"{target.get('id', 'unknown')} requires {template_path}",
                target=str(target.get("id", "unknown")),
            )

    result["status"] = "blocked" if issues else "pass"
    return result


def _load_manifest(path: Path, issues: list[dict[str, str]]) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        _add_issue(
            issues,
            "manifest_missing",
            "error",
            f"export manifest does not exist: {path}",
        )
        return {}
    except (OSError, json.JSONDecodeError) as error:
        _add_issue(
            issues,
            "manifest_invalid",
            "error",
            f"export manifest cannot be loaded: {error}",
        )
        return {}
    if not isinstance(value, dict):
        _add_issue(
            issues,
            "manifest_invalid",
            "error",
            "export manifest root must be an object",
        )
        return {}
    if value.get("schema_version") != EXPECTED_SCHEMA_VERSION:
        _add_issue(
            issues,
            "manifest_schema_unsupported",
            "error",
            f"schema_version must be {EXPECTED_SCHEMA_VERSION}",
        )
    return value


def _load_config(
    path: Path,
    issues: list[dict[str, str]],
    issue_code: str,
) -> dict[str, dict[str, str]]:
    try:
        return parse_godot_config(path)
    except (OSError, UnicodeError) as error:
        _add_issue(
            issues,
            issue_code,
            "error",
            f"cannot read {path}: {error}",
        )
        return {"": {}}


def _validate_project_config(
    root: Path,
    config: dict[str, dict[str, str]],
    required_feature: str,
    issues: list[dict[str, str]],
) -> None:
    application = config.get("application", {})
    features_value = application.get("config/features", "")
    features = re.findall(r'"([^"]+)"', features_value)
    if required_feature and required_feature not in features:
        _add_issue(
            issues,
            "project_feature_mismatch",
            "error",
            f"project.godot config/features must include {required_feature}",
        )

    main_scene = _unquote(application.get("run/main_scene", ""))
    if not main_scene.startswith("res://"):
        _add_issue(
            issues,
            "main_scene_invalid",
            "error",
            "project.godot run/main_scene must be a res:// path",
        )
        return
    scene_path = root / main_scene.removeprefix("res://")
    if not scene_path.is_file():
        _add_issue(
            issues,
            "main_scene_missing",
            "error",
            f"configured main scene does not exist: {main_scene}",
        )


def _index_presets(
    config: dict[str, dict[str, str]],
    issues: list[dict[str, str]],
) -> dict[str, dict[str, str]]:
    presets: dict[str, dict[str, str]] = {}
    for section_name, values in config.items():
        if not re.fullmatch(r"preset\.\d+", section_name):
            continue
        name = _unquote(values.get("name", ""))
        if not name:
            _add_issue(
                issues,
                "preset_name_missing",
                "error",
                f"{section_name} has no name",
            )
            continue
        if name in presets:
            _add_issue(
                issues,
                "preset_name_duplicate",
                "error",
                f"export preset name is duplicated: {name}",
            )
            continue
        presets[name] = values
    return presets


def _validate_target(
    root: Path,
    index: int,
    raw_target: object,
    presets: dict[str, dict[str, str]],
    seen_target_ids: set[str],
    issues: list[dict[str, str]],
) -> dict[str, object]:
    if not isinstance(raw_target, dict):
        _add_issue(
            issues,
            "target_invalid",
            "error",
            f"target at index {index} must be an object",
        )
        return {
            "id": f"invalid-{index}",
            "preset": "",
            "platform": "",
            "artifact": "",
            "template_files": [],
            "contract_status": "error",
            "template_status": "not_checked",
        }

    issue_count_before = len(issues)
    target_id = _target_string(raw_target, "id", index, issues)
    preset_name = _target_string(raw_target, "preset", index, issues)
    platform_name = _target_string(raw_target, "platform", index, issues)
    artifact = _target_string(raw_target, "artifact", index, issues)
    template_files = raw_target.get("template_files")
    if (
        not isinstance(template_files, list)
        or not template_files
        or any(not isinstance(item, str) or not item for item in template_files)
    ):
        _add_issue(
            issues,
            "target_template_files_invalid",
            "error",
            f"target {target_id or index} template_files must contain file names",
            target=target_id,
        )
        template_files = []
    elif any(PurePosixPath(item).name != item for item in template_files):
        _add_issue(
            issues,
            "target_template_files_invalid",
            "error",
            f"target {target_id or index} template_files must not contain directories",
            target=target_id,
        )

    if target_id in seen_target_ids:
        _add_issue(
            issues,
            "target_id_duplicate",
            "error",
            f"target id is duplicated: {target_id}",
            target=target_id,
        )
    seen_target_ids.add(target_id)

    if not _is_safe_build_artifact(root, artifact):
        _add_issue(
            issues,
            "unsafe_export_path",
            "error",
            f"target {target_id or index} artifact must remain below build/: {artifact}",
            target=target_id,
        )

    preset = presets.get(preset_name)
    if preset is None:
        _add_issue(
            issues,
            "preset_missing",
            "error",
            f"target {target_id or index} requires export preset {preset_name}",
            target=target_id,
        )
    else:
        actual_platform = _unquote(preset.get("platform", ""))
        actual_artifact = _unquote(preset.get("export_path", ""))
        export_filter = _unquote(preset.get("export_filter", ""))
        if actual_platform != platform_name:
            _add_issue(
                issues,
                "preset_platform_mismatch",
                "error",
                f"preset {preset_name} platform is {actual_platform}, expected {platform_name}",
                target=target_id,
            )
        if actual_artifact != artifact:
            _add_issue(
                issues,
                "preset_export_path_mismatch",
                "error",
                f"preset {preset_name} export_path is {actual_artifact}, expected {artifact}",
                target=target_id,
            )
        if export_filter != "all_resources":
            _add_issue(
                issues,
                "preset_export_filter_mismatch",
                "error",
                f"preset {preset_name} must use export_filter=all_resources",
                target=target_id,
            )

    return {
        "id": target_id,
        "preset": preset_name,
        "platform": platform_name,
        "artifact": artifact,
        "template_files": list(template_files),
        "contract_status": "error" if len(issues) > issue_count_before else "pass",
        "template_status": "not_checked",
    }


def _required_string(
    value: dict[str, Any],
    key: str,
    issues: list[dict[str, str]],
    issue_code: str,
) -> str:
    result = value.get(key)
    if isinstance(result, str) and result:
        return result
    _add_issue(
        issues,
        issue_code,
        "error",
        f"manifest godot.{key} must be a non-empty string",
    )
    return ""


def _target_string(
    target: dict[str, Any],
    key: str,
    index: int,
    issues: list[dict[str, str]],
) -> str:
    value = target.get(key)
    if isinstance(value, str) and value:
        return value
    _add_issue(
        issues,
        "target_field_invalid",
        "error",
        f"target at index {index} requires non-empty string {key}",
    )
    return ""


def _is_safe_build_artifact(root: Path, artifact: str) -> bool:
    if not artifact or PurePosixPath(artifact).is_absolute():
        return False
    build_root = (root / "build").resolve()
    artifact_path = (root / artifact).resolve()
    try:
        artifact_path.relative_to(build_root)
    except ValueError:
        return False
    return artifact_path != build_root


def _resolve_executable(command: str) -> Path | None:
    expanded = Path(command).expanduser()
    if expanded.is_absolute() or "/" in command or "\\" in command:
        candidate = expanded.resolve()
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
        return None
    found = shutil.which(command)
    return Path(found).resolve() if found else None


def _resolve_templates_dir(godot: dict[str, object], explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit.expanduser().resolve()
    configured = os.environ.get("GODOT_EXPORT_TEMPLATES_DIR")
    if configured:
        return Path(configured).expanduser().resolve()

    version = str(godot.get("template_version_directory") or "")
    system = platform.system()
    if system == "Darwin":
        base = Path.home() / "Library/Application Support/Godot/export_templates"
    elif system == "Windows":
        app_data = os.environ.get("APPDATA")
        base = (
            Path(app_data) / "Godot/export_templates"
            if app_data
            else Path.home() / "AppData/Roaming/Godot/export_templates"
        )
    else:
        xdg_data_home = os.environ.get("XDG_DATA_HOME")
        base = (
            Path(xdg_data_home) / "godot/export_templates"
            if xdg_data_home
            else Path.home() / ".local/share/godot/export_templates"
        )
    return (base / version).resolve()


def _unquote(value: str) -> str:
    if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
        try:
            decoded = json.loads(value)
        except json.JSONDecodeError:
            return value[1:-1]
        return decoded if isinstance(decoded, str) else value
    return value


def _add_issue(
    issues: list[dict[str, str]],
    code: str,
    category: str,
    message: str,
    *,
    target: str = "",
) -> None:
    issue = {
        "code": code,
        "category": category,
        "message": message,
    }
    if target:
        issue["target"] = target
    issues.append(issue)


def _write_json_atomic(path: Path, text: str) -> None:
    destination = path.expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            dir=destination.parent,
            prefix=f".{destination.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            handle.write(text)
            temporary_path = Path(handle.name)
        os.replace(temporary_path, destination)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate Plane Walker export configuration and local toolchain readiness.",
    )
    parser.add_argument(
        "--mode",
        choices=("contract", "local"),
        default="contract",
        help="contract checks tracked files; local also checks Godot and export templates",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
    )
    parser.add_argument(
        "--godot-bin",
        default=os.environ.get("GODOT_BIN", "godot"),
    )
    parser.add_argument("--templates-dir", type=Path)
    parser.add_argument("--json-output", type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    report = validate_contract(args.project_root)
    if args.mode == "local":
        report = validate_local_environment(
            report,
            args.godot_bin,
            args.templates_dir,
        )

    rendered = json.dumps(
        report,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ) + "\n"
    if args.json_output is not None:
        _write_json_atomic(args.json_output, rendered)
    sys.stdout.write(rendered)

    if report.get("status") == "pass":
        return EXIT_PASS
    if report.get("status") == "error":
        return EXIT_CONTRACT_ERROR
    return EXIT_ENVIRONMENT_BLOCKED


if __name__ == "__main__":
    raise SystemExit(main())
