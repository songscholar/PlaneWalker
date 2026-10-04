#!/usr/bin/env python3
"""Authenticate and launch the host-compatible release artifact in isolation."""

from __future__ import annotations

import argparse
import json
import os
import platform
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path

from artifact_evidence import describe_artifact, scan_export_logs
from preflight import validate_contract, write_json_atomic

EXPECTED_CHECKS = [
    "production_boot", "native_hub_first_screen", "hub_craft", "hub_rift",
    "hub_council", "navigation_preserves_profile", "gateway_panel",
    "gateway_launch_control", "durable_native_launch", "production_combat_route",
    "native_combat_actors", "durable_combat_checkpoint",
]
HOST_TARGETS = {"Darwin": "macos-universal", "Linux": "linux-x86_64", "Windows": "windows-x86_64"}


def verify_packaged_startup(
    project_root: Path, export_report: Path, evidence_output: Path,
    log_dir: Path, timeout_seconds: int = 60,
) -> tuple[dict[str, object], int]:
    root = project_root.resolve()
    logs = _project_path(root, log_dir)
    output = _project_path(root, evidence_output)
    report: dict[str, object] = {
        "schema_version": "1.0.0", "status": "failed",
        "classification": "packaged_startup_failed", "full_product_certified": False,
        "host_system": platform.system(), "target_id": None,
        "unexecuted_target_ids": [], "command": None, "exit_code": None,
        "artifact_evidence": None, "startup": None, "logs": None, "failure": "",
    }

    def finish(failure: str, code: int = 4):
        report["failure"] = failure
        if code == 3:
            report["status"] = "blocked"
            report["classification"] = "host_artifact_unavailable"
        write_json_atomic(output, json.dumps(report, indent=2, sort_keys=True) + "\n")
        return report, code

    contract = validate_contract(root)
    if contract["status"] != "pass" or timeout_seconds <= 0:
        return finish("invalid_contract")
    try:
        source = json.loads(_project_path(root, export_report).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return finish("export_report_invalid")
    if not isinstance(source, dict) or source.get("status") != "pass" or not isinstance(source.get("targets"), list):
        return finish("export_report_invalid")
    expected = {target["id"]: target for target in contract["targets"]}
    targets = source["targets"]
    seen = set()
    for target in targets:
        if not isinstance(target, dict) or not isinstance(target.get("id"), str) or target["id"] in seen:
            return finish("export_report_invalid")
        seen.add(target["id"])
        spec = expected.get(target["id"])
        if spec is None or target.get("status") != "pass" or any(target.get(key) != spec[key] for key in ["artifact", "artifact_kind"]):
            return finish("export_report_invalid")
    target_id = HOST_TARGETS.get(platform.system())
    report["target_id"] = target_id
    report["unexecuted_target_ids"] = [target["id"] for target in targets if target["id"] != target_id]
    target = next((value for value in targets if value["id"] == target_id), None)
    if target is None:
        return finish("host_artifact_unavailable", 3)
    artifact = _project_path(root, Path(target["artifact"]))
    try:
        before = describe_artifact(artifact, root, target["artifact_kind"])
        if before != target.get("artifact_evidence"):
            return finish("artifact_changed")
        executable = _executable(artifact, target_id)
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException):
        return finish("artifact_invalid")
    report["artifact_evidence"] = before
    logs.mkdir(parents=True, exist_ok=True)
    stdout = logs / "stdout.log"
    engine = logs / "engine.log"
    for path in [stdout, engine]:
        if path.exists():
            path.unlink()
    with tempfile.TemporaryDirectory(prefix="empty-startup-", dir=logs) as temporary:
        empty = Path(temporary)
        native_report = empty / "startup.json"
        environment = dict(os.environ)
        environment["PLANEWALKER_USER_DATA_DIR"] = str(empty / "isolated-user-data")
        environment["PLANEWALKER_STARTUP_REPORT"] = str(native_report)
        command = [str(executable), "--headless", "--log-file", str(engine), "--", "--plane-walker-startup-check"]
        report["command"] = command
        try:
            with stdout.open("w", encoding="utf-8") as handle:
                completed = subprocess.run(command, cwd=empty, env=environment, stdout=handle,
                                           stderr=subprocess.STDOUT, timeout=timeout_seconds, check=False)
            report["exit_code"] = completed.returncode
        except subprocess.TimeoutExpired:
            return finish("startup_timeout")
        except OSError:
            return finish("startup_process_error")
        failures = scan_export_logs([stdout, engine])
        report["logs"] = {"stdout": str(stdout), "engine": str(engine), "failures": failures}
        try:
            after = describe_artifact(artifact, root, target["artifact_kind"])
        except (OSError, ValueError):
            return finish("artifact_changed_during_startup")
        if after != before:
            return finish("artifact_changed_during_startup")
        if failures:
            return finish("runtime_log_failure")
        if completed.returncode != 0:
            return finish("startup_process_failed")
        try:
            native = json.loads(native_report.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return finish("startup_result_invalid")
        if not _valid_native_result(native):
            return finish("startup_result_invalid")
        report["startup"] = native
        write_json_atomic(logs / "native-startup.json", json.dumps(native, indent=2, sort_keys=True) + "\n")
    report["status"] = "pass"
    report["classification"] = "host_packaged_startup_verified"
    return finish("", 0)


def _valid_native_result(value: object) -> bool:
    fields = {"schema_id", "schema_version", "status", "engine_version", "checks", "failure", "content_snapshot"}
    if not isinstance(value, dict) or set(value) != fields or type(value["schema_version"]) is not int:
        return False
    if value["schema_id"] != "planewalker.packaged_startup" or value["schema_version"] != 1 or value["status"] != "pass" or value["failure"] != "" or value["checks"] != EXPECTED_CHECKS:
        return False
    if not isinstance(value["engine_version"], str) or not value["engine_version"].startswith("4.6.1-"):
        return False
    snapshot = value["content_snapshot"]
    if not isinstance(snapshot, dict) or set(snapshot) != {"aggregate_sha256", "packs"} or not _sha(snapshot["aggregate_sha256"]):
        return False
    packs = snapshot["packs"]
    if not isinstance(packs, list) or not packs:
        return False
    ids = set()
    for pack in packs:
        if not isinstance(pack, dict) or set(pack) != {"pack_id", "pack_version", "schema_version", "fingerprint_sha256"}:
            return False
        if not isinstance(pack["pack_id"], str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", pack["pack_id"]) or pack["pack_id"] in ids or not isinstance(pack["pack_version"], str) or not pack["pack_version"]:
            return False
        if type(pack["schema_version"]) not in [int, float] or not 1 <= pack["schema_version"] <= 2147483647 or not float(pack["schema_version"]).is_integer() or not _sha(pack["fingerprint_sha256"]):
            return False
        ids.add(pack["pack_id"])
    return True


def _sha(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value) is not None


def _executable(artifact: Path, target_id: str) -> Path:
    if target_id != "macos-universal":
        return artifact
    with (artifact / "Contents/Info.plist").open("rb") as handle:
        name = plistlib.load(handle)["CFBundleExecutable"]
    if not isinstance(name, str) or Path(name).name != name:
        raise ValueError("invalid bundle executable")
    executable = artifact / "Contents/MacOS" / name
    executable.resolve().relative_to(artifact)
    if not executable.is_file() or executable.is_symlink():
        raise ValueError("missing bundle executable")
    return executable


def _project_path(root: Path, path: Path) -> Path:
    value = (root / path).resolve()
    value.relative_to(root)
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--export-report", type=Path, required=True)
    parser.add_argument("--evidence-output", type=Path, default=Path("build/export-evidence/packaged-startup.json"))
    parser.add_argument("--log-dir", type=Path, default=Path("build/export-evidence/packaged-startup-logs"))
    parser.add_argument("--timeout-seconds", type=int, default=60)
    args = parser.parse_args()
    report, code = verify_packaged_startup(args.project_root, args.export_report, args.evidence_output, args.log_dir, args.timeout_seconds)
    print(json.dumps(report, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
