#!/usr/bin/env python3
"""Build an explicit local fallback using a verified editor binary and PCK."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Sequence

from artifact_evidence import describe_artifact, scan_export_logs
from preflight import write_json_atomic


LAUNCHER = '''#!/bin/sh
set -eu
package_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export PLANEWALKER_USER_DATA_DIR="$package_dir/user-data"
export XDG_DATA_HOME="$package_dir/user-data"
export XDG_CACHE_HOME="$package_dir/user-data/cache"
exec "$package_dir/Godot.app/Contents/MacOS/Godot" --main-pack "$package_dir/PlaneWalker.pck" "$@"
'''
REGISTERED_CA_LINE = 'ERROR: Condition "ret != noErr" is true. Returning: ""'
REGISTERED_CA_CALLSITE = "at: get_system_ca_certificates (platform/macos/os_macos.mm:"


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def project_build_path(root: Path, path: Path) -> Path:
    resolved = (path if path.is_absolute() else root / path).resolve()
    if not resolved.is_relative_to((root / "build").resolve()) or resolved == root / "build":
        raise ValueError("output must remain inside the project's build directory")
    if not resolved.is_relative_to(root):
        raise ValueError("build directory must remain inside the project")
    return resolved


def copy_runtime(source: Path, destination: Path) -> Path:
    bundle = source.parent.parent.parent
    if source.parent.name == "MacOS" and source.parent.parent.name == "Contents" and bundle.suffix == ".app":
        copied_bundle = destination / "Godot.app"
        if not copied_bundle.exists():
            shutil.copytree(bundle, copied_bundle)
        executable = copied_bundle / "Contents/MacOS" / source.name
    else:
        executable = destination / ("Godot.exe" if source.suffix.lower() == ".exe" else "Godot")
        if not executable.exists():
            shutil.copy2(source, executable)
    if executable.is_symlink() or file_sha256(executable) != file_sha256(source):
        raise ValueError("project-local editor differs from its source binary")
    return executable


def prepare_self_contained_editor(
    root: Path,
    source_binary: Path,
    templates_dir: Path | None = None,
    template_version: str = "4.6.1.stable",
) -> Path:
    """Use Godot's documented _sc_ directory layout without personal writes."""
    root = root.resolve()
    source = source_binary.resolve(strict=True)
    source_digest = file_sha256(source)
    template_path = templates_dir.resolve(strict=True) if templates_dir is not None else None
    if not re.fullmatch(r"[a-zA-Z0-9_.-]+", template_version):
        raise ValueError("invalid template version directory")
    identity = source_digest + (str(template_path) if template_path else "") + template_version
    editor_root = project_build_path(root, Path("build/toolchain/export-editor") / hashlib.sha256(identity.encode()).hexdigest())
    editor_root.mkdir(parents=True, exist_ok=True)
    ignore_file = root / "build" / ".gdignore"
    if ignore_file.is_symlink():
        raise ValueError("build ignore marker must not be a symbolic link")
    if not ignore_file.exists():
        ignore_file.write_text("", encoding="utf-8")
    editor = copy_runtime(source, editor_root)
    marker = editor_root / "_sc_"
    if marker.is_symlink():
        raise ValueError("self-contained editor marker must not be a symbolic link")
    marker.write_text("", encoding="utf-8")
    if template_path is not None:
        link = editor_root / "editor_data" / "export_templates" / template_version
        link.parent.mkdir(parents=True, exist_ok=True)
        if link.exists() or link.is_symlink():
            if not link.is_symlink() or link.resolve() != template_path:
                raise ValueError("project-local template directory already contains unrelated files")
        else:
            link.symlink_to(template_path, target_is_directory=True)
    return editor


def classified_log_failures(paths: Sequence[Path]) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    failures = scan_export_logs(paths)
    retained: list[dict[str, object]] = []
    environmental: list[dict[str, object]] = []
    for failure in failures:
        path = Path(str(failure["path"]))
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines() if path.is_file() else []
        line_index = int(failure["line_number"]) - 1
        has_callsite = any(REGISTERED_CA_CALLSITE in line for line in lines[line_index + 1:line_index + 4])
        if failure["code"] == "engine_error" and failure["line"] == REGISTERED_CA_LINE and has_callsite:
            environmental.append({**failure, "classification": "registered_macos_ca_environment"})
        else:
            retained.append(failure)
    return retained, environmental


def run_logged(command: list[str], cwd: Path, log_dir: Path, name: str, environment: dict[str, str], timeout: int) -> dict[str, object]:
    stdout = log_dir / f"{name}.stdout.log"
    engine = log_dir / f"{name}.engine.log"
    actual_command = command + ["--log-file", str(engine)]
    with stdout.open("w", encoding="utf-8") as stream:
        completed = subprocess.run(actual_command, cwd=cwd, env=environment, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, check=False)
    failures, environmental = classified_log_failures([stdout, engine])
    result: dict[str, object] = {
        "command": actual_command, "exit_code": completed.returncode,
        "stdout": str(stdout), "engine": str(engine), "failures": failures,
        "registered_environmental_diagnostics": environmental,
    }
    if completed.returncode != 0 or failures:
        raise RuntimeError(json.dumps(result, sort_keys=True))
    return result


def build_portable_fallback(
    root: Path, source_binary: Path, output_dir: Path,
    evidence_output: Path, timeout: int = 180,
) -> tuple[dict[str, object], int]:
    from build_exports import collect_git_state

    root = root.resolve()
    output = project_build_path(root, output_dir)
    evidence = project_build_path(root, evidence_output)
    report: dict[str, object] = {
        "schema_version": "1.0.0", "status": "blocked",
        "classification": "local_editor_runtime_fallback",
        "formal_template_export": False, "repository": collect_git_state(root),
        "limitations": [
            "Uses the verified editor executable as a runtime, not a release export template.",
            "Startup checks the packaged Main scene; it does not certify a full playthrough or visual/controller behavior.",
            "Windows/Linux release exports and macOS signing/notarization remain unverified.",
            "The application save/input data is isolated; Godot may create its default empty macOS engine user-data directory.",
        ],
        "steps": [], "issues": [],
    }
    try:
        if timeout <= 0:
            raise ValueError("timeout must be positive")
        source = source_binary.resolve(strict=True)
        source_digest = file_sha256(source)
        trusted = json.loads((root / "data/toolchain/m1_godot_toolchains.json").read_text(encoding="utf-8"))
        matches = [entry for entry in trusted["toolchains"] if entry.get("sha256") == source_digest]
        if len(matches) != 1:
            raise ValueError("runtime binary is not in the tracked official toolchain allowlist")
        version = subprocess.run([str(source), "--version"], check=True, capture_output=True, text=True, timeout=10).stdout.strip()
        if version != matches[0]["version"]:
            raise ValueError("runtime version differs from its allowlisted identity")
        report["runtime_provenance"] = {**matches[0], "source_binary": str(source)}
        editor = prepare_self_contained_editor(root, source)
        output.mkdir(parents=True, exist_ok=True)
        if any(output.iterdir()):
            raise ValueError("fallback output directory must be empty; choose a new candidate directory")
        logs = project_build_path(root, Path("build/export-evidence/portable-logs") / output.name)
        logs.mkdir(parents=True, exist_ok=True)
        environment = dict(os.environ)
        environment["PLANEWALKER_USER_DATA_DIR"] = str(logs / "user-data")
        environment["XDG_DATA_HOME"] = str(logs / "user-data")
        environment["XDG_CACHE_HOME"] = str(logs / "user-data/cache")
        runtime = copy_runtime(source, output)
        if file_sha256(runtime) != source_digest:
            raise ValueError("copied runtime checksum changed")
        (output / "_sc_").write_text("", encoding="utf-8")
        launcher = output / "PlaneWalker.command"
        launcher.write_text(LAUNCHER, encoding="utf-8")
        launcher.chmod(0o755)
        licenses = output / "licenses"
        probe = [str(editor), "--headless", "--path", str(root), "--script", "res://tools/export/runtime_license_probe.gd", "--", str(licenses)]
        # Engine options must precede the script's user-argument separator.
        license_stdout = logs / "license.stdout.log"
        license_engine = logs / "license.engine.log"
        probe[probe.index("--"):probe.index("--")] = ["--log-file", str(license_engine)]
        with license_stdout.open("w", encoding="utf-8") as stream:
            license_run = subprocess.run(probe, cwd=root, env=environment, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, check=False)
        license_failures, diagnostics = classified_log_failures([license_stdout, license_engine])
        if license_run.returncode != 0 or license_failures or not (licenses / "GODOT-LICENSE.txt").is_file() or not (licenses / "THIRD-PARTY-LICENSES.json").is_file():
            raise RuntimeError(f"license extraction failed: {license_failures}")
        report["steps"].append({"kind": "license_extraction", "command": probe, "registered_environmental_diagnostics": diagnostics})
        pack = output / "PlaneWalker.pck"
        report["steps"].append(run_logged([str(editor), "--headless", "--path", str(root), "--export-pack", "macOS Release", str(pack)], root, logs, "export-pack", environment, timeout))
        report["pack_evidence"] = describe_artifact(pack, root, "file")
        report["steps"].append(run_logged([str(launcher), "--headless", "--quit-after", "300"], output, logs, "packaged-main-startup", environment, timeout))
        report["artifact_evidence"] = describe_artifact(output, root, "directory")
        report["status"] = "pass"
        code = 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, KeyError) as error:
        report["status"] = "failed"
        report["issues"].append({"code": "portable_fallback_failed", "message": str(error)})
        code = 4
    write_json_atomic(evidence, json.dumps(report, indent=2, sort_keys=True) + "\n")
    return report, code


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--godot-bin", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("build/portable/PlaneWalker-macos-local"))
    parser.add_argument("--evidence-output", type=Path, default=Path("build/export-evidence/portable-report.json"))
    parser.add_argument("--timeout-seconds", type=int, default=180)
    args = parser.parse_args(argv)
    report, code = build_portable_fallback(args.project_root, args.godot_bin, args.output_dir, args.evidence_output, args.timeout_seconds)
    print(json.dumps(report, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
