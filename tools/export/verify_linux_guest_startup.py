#!/usr/bin/env python3
"""Authenticate and launch a Linux release artifact in an isolated Docker guest."""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

from artifact_evidence import describe_artifact, scan_export_logs
from preflight import validate_contract, write_json_atomic
from verify_packaged_startup import _project_path, _valid_native_result


def verify_linux_guest_startup(
    project_root: Path, export_report: Path, artifact_root: Path,
    evidence_output: Path, log_dir: Path, docker_bin: str, docker_host: str,
    image: str, timeout_seconds: int = 90,
) -> tuple[dict[str, object], int]:
    root = project_root.resolve()
    output = _project_path(root, evidence_output)
    logs = _project_path(root, log_dir)
    report: dict[str, object] = {
        "schema_version": "1.0.0", "status": "failed",
        "classification": "linux_guest_packaged_startup_failed",
        "full_product_certified": False, "actual_linux_host_verified": False,
        "host_system": platform.system(), "guest_platform": "linux/amd64",
        "target_id": "linux-x86_64", "unexecuted_target_ids": [],
        "docker_server": None, "docker_image": None, "command": None,
        "exit_code": None, "artifact_evidence": None, "startup": None,
        "logs": None, "failure": "",
    }

    def finish(failure: str, code: int = 4):
        report["failure"] = failure
        if code == 3:
            report["status"] = "blocked"
            report["classification"] = "linux_guest_environment_unavailable"
        write_json_atomic(output, json.dumps(report, indent=2, sort_keys=True) + "\n")
        return report, code

    contract = validate_contract(root)
    if contract["status"] != "pass":
        return finish("invalid_contract")
    if (type(timeout_seconds) is not int or timeout_seconds <= 0
            or not re.fullmatch(r"[a-z0-9][a-z0-9._:/-]*@sha256:[a-f0-9]{64}", image)
            or not docker_host.startswith("unix://")):
        return finish("invalid_guest_configuration")
    try:
        artifacts = _project_path(root, artifact_root)
        source = json.loads(_project_path(root, export_report).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return finish("export_report_invalid")
    if (not isinstance(source, dict) or source.get("status") != "pass"
            or not isinstance(source.get("targets"), list) or not source["targets"]):
        return finish("export_report_invalid")
    specs = {target["id"]: target for target in contract["targets"]}
    seen = set()
    selected = None
    for target in source["targets"]:
        if not isinstance(target, dict) or not isinstance(target.get("id"), str) or target["id"] in seen:
            return finish("export_report_invalid")
        seen.add(target["id"])
        spec = specs.get(target["id"])
        if (spec is None or target.get("status") != "pass"
                or any(target.get(key) != spec[key] for key in ["artifact", "artifact_kind"])):
            return finish("export_report_invalid")
        if target["id"] == "linux-x86_64":
            selected = target
    report["unexecuted_target_ids"] = sorted(seen - {"linux-x86_64"})
    if selected is None:
        return finish("linux_artifact_unavailable", 3)
    try:
        artifact = artifacts / str(selected["artifact"])
        before = describe_artifact(artifact, artifacts, "file")
        if before != selected.get("artifact_evidence"):
            return finish("artifact_changed")
    except (OSError, ValueError):
        return finish("artifact_invalid")
    if any("," in str(path) for path in [artifact, logs]):
        return finish("invalid_guest_configuration")
    report["artifact_evidence"] = before
    docker = shutil.which(docker_bin)
    if docker is None:
        return finish("docker_unavailable", 3)
    logs.mkdir(parents=True, exist_ok=True)
    if any(logs.iterdir()):
        return finish("log_destination_occupied")
    stdout = logs / "stdout.log"
    engine = logs / "engine.log"
    native_path = logs / "native-startup.json"
    environment = {key: value for key, value in os.environ.items() if not key.startswith("DOCKER_")}
    with tempfile.TemporaryDirectory(prefix="empty-docker-config-", dir=logs) as temporary:
        # Explicit empty configuration prevents inherited Docker credentials or contexts.
        prefix = [docker, "--config", temporary, "--host", docker_host]
        server = _inspect(prefix + ["version", "--format", "{{json .Server}}"], environment)
        if (not isinstance(server, dict) or not isinstance(server.get("Version"), str)
                or not server["Version"] or server.get("Os") != "linux"):
            return finish("docker_daemon_unavailable", 3)
        report["docker_server"] = server
        inspected = _inspect(prefix + ["image", "inspect", image, "--format", "{{json .}}"], environment)
        if inspected is None:
            return finish("docker_image_unavailable", 3)
        if (not isinstance(inspected, dict) or inspected.get("Os") != "linux"
                or inspected.get("Architecture") != "amd64"
                or not isinstance(inspected.get("RepoDigests"), list)
                or image not in inspected.get("RepoDigests", [])
                or not isinstance(inspected.get("Id"), str)
                or not re.fullmatch(r"sha256:[a-f0-9]{64}", inspected["Id"])):
            return finish("docker_image_invalid", 3)
        report["docker_image"] = {
            "requested_digest": image, "image_id": inspected["Id"],
            "os": inspected["Os"], "architecture": inspected["Architecture"],
        }
        name = "planewalker-startup-" + uuid.uuid4().hex
        command = prefix + [
            "run", "--rm", "--name", name, "--pull=never", "--platform", "linux/amd64",
            "--network", "none", "--read-only", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges", "--pids-limit", "256",
            "--memory", "512m", "--cpus", "2", "--user", f"{os.getuid()}:{os.getgid()}",
            "--tmpfs", "/tmp:rw,nosuid,size=128m", "--workdir", "/tmp",
            "--mount", f"type=bind,source={artifact},target=/artifact/PlaneWalker.x86_64,readonly",
            "--mount", f"type=bind,source={logs},target=/output",
            "--env", "PLANEWALKER_USER_DATA_DIR=/tmp/isolated-user-data",
            "--env", "PLANEWALKER_STARTUP_REPORT=/output/native-startup.json",
            "--env", "XDG_DATA_HOME=/tmp/engine-data",
            "--env", "XDG_CONFIG_HOME=/tmp/engine-config",
            "--env", "XDG_CACHE_HOME=/tmp/engine-cache",
            "--entrypoint", "/artifact/PlaneWalker.x86_64",
            image, "--headless", "--log-file",
            "/output/engine.log", "--", "--plane-walker-startup-check",
        ]
        report["command"] = command
        try:
            with stdout.open("w", encoding="utf-8") as handle:
                completed = subprocess.run(command, env=environment, stdout=handle,
                                           stderr=subprocess.STDOUT, timeout=timeout_seconds, check=False)
            report["exit_code"] = completed.returncode
        except (subprocess.TimeoutExpired, OSError) as error:
            try:
                subprocess.run(prefix + ["rm", "--force", name], env=environment,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15, check=False)
            except (subprocess.TimeoutExpired, OSError):
                pass
            return finish("startup_timeout" if isinstance(error, subprocess.TimeoutExpired) else "startup_process_error")
    failures = scan_export_logs([stdout, engine])
    report["logs"] = {"stdout": str(stdout), "engine": str(engine), "failures": failures}
    try:
        if describe_artifact(artifact, artifacts, "file") != before:
            return finish("artifact_changed_during_startup")
    except (OSError, ValueError):
        return finish("artifact_changed_during_startup")
    if failures:
        return finish("runtime_log_failure")
    if completed.returncode != 0:
        return finish("startup_process_failed")
    try:
        native = json.loads(native_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return finish("startup_result_invalid")
    if not _valid_native_result(native):
        return finish("startup_result_invalid")
    report["startup"] = native
    report["status"] = "pass"
    report["classification"] = "linux_guest_packaged_startup_verified"
    return finish("", 0)


def _inspect(command: list[str], environment: dict[str, str]) -> object:
    try:
        completed = subprocess.run(command, env=environment, capture_output=True, text=True,
                                   timeout=15, check=False)
        return json.loads(completed.stdout) if completed.returncode == 0 else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--export-report", type=Path, required=True)
    parser.add_argument("--artifact-root", type=Path, default=Path("."))
    parser.add_argument("--evidence-output", type=Path, default=Path("build/export-evidence/linux-guest-startup.json"))
    parser.add_argument("--log-dir", type=Path, default=Path("build/export-evidence/linux-guest-startup-logs"))
    parser.add_argument("--docker-bin", default="docker")
    parser.add_argument("--docker-host", default="unix:///var/run/docker.sock")
    parser.add_argument("--image", required=True, help="already installed immutable repository@sha256:digest")
    parser.add_argument("--timeout-seconds", type=int, default=90)
    args = parser.parse_args()
    report, code = verify_linux_guest_startup(
        args.project_root, args.export_report, args.artifact_root, args.evidence_output,
        args.log_dir, args.docker_bin, args.docker_host, args.image, args.timeout_seconds,
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
