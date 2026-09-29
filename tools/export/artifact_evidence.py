#!/usr/bin/env python3
"""Deterministic hashing and fatal-log classification for Godot exports."""

from __future__ import annotations

import hashlib
import os
import re
from pathlib import Path
from typing import Sequence


FAILURE_SIGNATURES = (
    (
        "script_error",
        re.compile(r"SCRIPT ERROR:|Parse Error:|Failed to load script"),
    ),
    (
        "resource_error",
        re.compile(r"Failed loading resource|Cannot open file .*\.(?:gd|tscn|tres)"),
    ),
    (
        "invalid_call",
        re.compile(r"Invalid (?:call|get|set)(?:\.| )"),
    ),
    (
        "object_leak",
        re.compile(r"ObjectDB instances leaked at exit|RID allocations leaked at exit"),
    ),
    (
        "assertion_failure",
        re.compile(r"Assertion failed|Smoke test failed"),
    ),
    (
        "engine_error",
        re.compile(r"^ERROR:"),
    ),
)


def describe_artifact(
    path: Path,
    project_root: Path,
    expected_kind: str,
) -> dict[str, object]:
    """Return deterministic evidence for one validated build artifact."""

    root = project_root.expanduser().resolve()
    unresolved_artifact = path.expanduser().absolute()
    if unresolved_artifact.is_symlink():
        raise ValueError(f"artifact root must not be a symbolic link: {unresolved_artifact}")
    artifact = unresolved_artifact.resolve(strict=False)
    try:
        relative = artifact.relative_to(root).as_posix()
    except ValueError as error:
        raise ValueError(f"artifact is outside project root: {artifact}") from error

    if expected_kind == "file":
        if not artifact.is_file() or artifact.is_symlink():
            raise ValueError(f"expected file artifact: {relative}")
        digest, size = _hash_file(artifact)
        return {
            "kind": "file",
            "path": relative,
            "sha256": digest,
            "digest_algorithm": "sha256",
            "size_bytes": size,
            "file_count": 1,
            "symlink_count": 0,
        }

    if expected_kind != "directory":
        raise ValueError(f"unsupported artifact kind: {expected_kind}")
    if not artifact.is_dir() or artifact.is_symlink():
        raise ValueError(f"expected directory artifact: {relative}")
    return _describe_directory(artifact, relative)


def scan_export_logs(paths: Sequence[Path]) -> list[dict[str, object]]:
    """Return de-duplicated fatal signatures from export logs."""

    failures: list[dict[str, object]] = []
    seen: set[tuple[str, str, str]] = set()
    for path in paths:
        display_path = str(path)
        if not path.is_file():
            key = ("log_missing", display_path, "")
            if key not in seen:
                seen.add(key)
                failures.append({
                    "code": "log_missing",
                    "path": display_path,
                    "line_number": 0,
                    "line": "",
                })
            continue
        for line_number, raw_line in enumerate(
            path.read_text(encoding="utf-8", errors="replace").splitlines(),
            start=1,
        ):
            line = raw_line.strip()
            for code, pattern in FAILURE_SIGNATURES:
                if not pattern.search(line):
                    continue
                key = (code, display_path, line)
                if key in seen:
                    continue
                seen.add(key)
                failures.append({
                    "code": code,
                    "path": display_path,
                    "line_number": line_number,
                    "line": line,
                })
    return failures


def _describe_directory(directory: Path, relative: str) -> dict[str, object]:
    entries: list[tuple[str, str, Path]] = []
    for directory_path, directory_names, file_names in os.walk(
        directory,
        topdown=True,
        followlinks=False,
    ):
        current = Path(directory_path)
        retained_directories: list[str] = []
        for name in directory_names:
            entry = current / name
            if entry.is_symlink():
                entries.append((entry.relative_to(directory).as_posix(), "L", entry))
            else:
                retained_directories.append(name)
        directory_names[:] = retained_directories
        for name in file_names:
            entry = current / name
            entry_type = "L" if entry.is_symlink() else "F"
            entries.append((entry.relative_to(directory).as_posix(), entry_type, entry))

    tree_digest = hashlib.sha256()
    size_bytes = 0
    file_count = 0
    symlink_count = 0
    for entry_path, entry_type, entry in sorted(entries, key=lambda item: item[0]):
        path_bytes = entry_path.encode("utf-8")
        tree_digest.update(entry_type.encode("ascii"))
        tree_digest.update(len(path_bytes).to_bytes(8, "big"))
        tree_digest.update(path_bytes)
        if entry_type == "L":
            target_bytes = os.readlink(entry).encode("utf-8")
            tree_digest.update(len(target_bytes).to_bytes(8, "big"))
            tree_digest.update(target_bytes)
            symlink_count += 1
            continue
        file_digest, file_size = _hash_file(entry)
        tree_digest.update(bytes.fromhex(file_digest))
        size_bytes += file_size
        file_count += 1

    if not entries:
        raise ValueError(f"expected non-empty directory artifact: {relative}")
    return {
        "kind": "directory",
        "path": relative,
        "sha256": tree_digest.hexdigest(),
        "digest_algorithm": "sha256-tree-v1",
        "size_bytes": size_bytes,
        "file_count": file_count,
        "symlink_count": symlink_count,
    }


def _hash_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size
