"""Fetch and install the pinned official export templates inside the project."""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit
import zipfile
from pathlib import Path, PurePosixPath

VERSION = "4.6.1.stable"
URL = "https://github.com/godotengine/godot-builds/releases/download/4.6.1-stable/Godot_v4.6.1-stable_export_templates.tpz"
SIZE = 1249771228
SHA256 = "e6d372afd4fdfaae9571eb5e3568afcd96ce6db9a569244034154faf0ac69875"
TEMPLATE_FILES = ("version.txt", "macos.zip", "linux_release.x86_64", "windows_release_x86_64.exe")


def _digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def download_archive(url: str, size: int, sha256: str, cache: Path, workers: int = 8,
                     chunk_size: int = 8 * 1024 * 1024, transport: str = "urllib") -> Path:
    if size <= 0 or workers <= 0 or chunk_size <= 0:
        raise ValueError("download dimensions must be positive")
    if transport not in ("urllib", "curl"):
        raise ValueError("unknown download transport")
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / "templates.tpz"
    if target.is_file() and target.stat().st_size == size and _digest(target) == sha256:
        return target

    def fetch(index: int) -> Path:
        start, end = index * chunk_size, min(size, (index + 1) * chunk_size) - 1
        part = cache / f"part-{index:06d}"
        length = end - start + 1
        for attempt in range(5):
            existing = part.stat().st_size if part.is_file() else 0
            if existing > length:
                raise ValueError(f"cached range {index} exceeds its expected size")
            if existing == length:
                return part
            offset = start + existing
            request = urllib.request.Request(url, headers={
                "Range": f"bytes={offset}-{end}", "Accept-Encoding": "identity",
                "User-Agent": "PlaneWalker-export-tool/1.0",
            })
            try:
                if transport == "curl":
                    _curl_range(url, offset, end, size, part)
                    return part
                with urllib.request.urlopen(request, timeout=60) as response:
                    expected = f"bytes {offset}-{end}/{size}"
                    if response.status != 206 or response.headers.get("Content-Range") != expected:
                        raise ValueError(f"invalid HTTP range response for {offset}-{end}")
                    if int(response.headers.get("Content-Length", "-1")) != end - offset + 1:
                        raise ValueError("invalid HTTP range content length")
                    with part.open("ab") as destination:
                        remaining = end - offset + 1
                        while remaining:
                            block = response.read(min(1024 * 1024, remaining))
                            if not block:
                                raise OSError("incomplete HTTP range transfer")
                            destination.write(block)
                            remaining -= len(block)
                        destination.flush()
                        os.fsync(destination.fileno())
                return part
            except (OSError, urllib.error.URLError):
                if attempt == 4:
                    raise
                time.sleep(min(2 ** attempt, 8))
        raise RuntimeError("range retries exhausted")

    count = (size + chunk_size - 1) // chunk_size
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        parts = list(executor.map(fetch, range(count)))
    candidate = cache / "templates.assembling"
    with candidate.open("wb") as output:
        for part in parts:
            with part.open("rb") as source:
                shutil.copyfileobj(source, output)
        output.flush()
        os.fsync(output.fileno())
    if candidate.stat().st_size != size or _digest(candidate) != sha256:
        candidate.unlink()
        raise ValueError("official template SHA-256 verification failed")
    candidate.replace(target)
    return target


def _curl_range(url: str, start: int, end: int, size: int, part: Path) -> None:
    temporary = part.with_suffix(".receiving")
    result = subprocess.run([
        "curl", "-4", "--silent", "--show-error", "--location", "--fail",
        "--connect-timeout", "10", "--max-time", "90", "--range", f"{start}-{end}",
        "--header", "Accept-Encoding: identity", "--output", str(temporary),
        "--write-out", "%{json}\n%{header_json}", url,
    ], capture_output=True, text=True, timeout=100, check=False)
    decoder = json.JSONDecoder()
    try:
        metadata, consumed = decoder.raw_decode(result.stdout)
        headers = json.loads(result.stdout[consumed:].strip())
    except (ValueError, TypeError) as error:
        raise OSError("curl did not return transfer metadata") from error
    if metadata.get("response_code") != 206 or headers.get("content-range") != [f"bytes {start}-{end}/{size}"]:
        if result.returncode:
            raise OSError(f"curl range transfer failed ({result.returncode})")
        raise ValueError("invalid HTTP range response from curl")
    if headers.get("content-length") != [str(end - start + 1)]:
        raise ValueError("invalid HTTP range content length from curl")
    received = temporary.stat().st_size if temporary.is_file() else 0
    if received > end - start + 1:
        raise ValueError("HTTP range transfer exceeds its expected size")
    if received:
        with temporary.open("rb") as source, part.open("ab") as destination:
            shutil.copyfileobj(source, destination)
            destination.flush()
            os.fsync(destination.fileno())
    if temporary.exists():
        temporary.unlink()
    if received != end - start + 1:
        raise OSError("incomplete HTTP range transfer from curl")


def install_templates(archive: Path, output: Path) -> None:
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as source:
        for item in source.infolist():
            path = PurePosixPath(item.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in item.filename or stat.S_ISLNK(item.external_attr >> 16):
                raise ValueError("unsafe template archive path")
        names = source.namelist()
        required = ["templates/" + name for name in TEMPLATE_FILES]
        if any(names.count(name) != 1 for name in required):
            raise ValueError("missing or duplicate export template")
        if source.read("templates/version.txt").decode("utf-8").strip() != VERSION:
            raise ValueError("export template version does not match the pinned runtime")
        temporary = Path(tempfile.mkdtemp(prefix=".templates-", dir=output.parent))
        try:
            for name in TEMPLATE_FILES:
                destination = temporary / name
                with source.open("templates/" + name) as stream, destination.open("wb") as target:
                    shutil.copyfileobj(stream, target)
                if name == "linux_release.x86_64":
                    destination.chmod(0o755)
            # Keep the previous installation recoverable until the new directory exists.
            backup = None
            if output.exists():
                backup = Path(tempfile.mkdtemp(prefix=".previous-templates-", dir=output.parent))
                backup.rmdir()
                output.replace(backup)
            try:
                temporary.replace(output)
            except OSError:
                if backup is not None:
                    backup.replace(output)
                raise
            if backup is not None:
                shutil.rmtree(backup)
        finally:
            if temporary.exists():
                shutil.rmtree(temporary)


def resolve_release_url() -> str:
    result = subprocess.run([
        "curl", "-4", "--silent", "--show-error", "--location", "--head", "--fail",
        "--connect-timeout", "10", "--max-time", "40", "--retry", "2",
        "--output", os.devnull, "--write-out", "%{json}", URL,
    ], capture_output=True, text=True, timeout=130, check=False)
    if result.returncode:
        raise OSError(f"official release redirect failed ({result.returncode})")
    metadata = json.loads(result.stdout)
    resolved = metadata.get("url_effective", "")
    parsed = urlsplit(resolved)
    if parsed.scheme != "https" or parsed.hostname != "release-assets.githubusercontent.com":
        raise ValueError("official release redirected to an unexpected host")
    return resolved


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=root / "build/toolchain/godot-4.6.1/range-cache")
    parser.add_argument("--output", type=Path, default=root / "build/toolchain/godot-4.6.1/templates" / VERSION)
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--transport", choices=("urllib", "curl"), default="curl" if shutil.which("curl") else "urllib")
    args = parser.parse_args()
    print(f"Fetching official Godot {VERSION}: {SIZE} bytes, SHA-256 {SHA256}", flush=True)
    url = resolve_release_url() if args.transport == "curl" else URL
    archive = download_archive(url, SIZE, SHA256, args.cache, workers=args.workers, transport=args.transport)
    install_templates(archive, args.output)
    print(f"Verified export templates installed: {args.output}", flush=True)


if __name__ == "__main__":
    main()
