#!/usr/bin/env python3
"""Run honest, uninstrumented production Main timing and recording evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from runtime_log_validation import validate_logs  # noqa: E402

METRICS = {"player_advance", "host_process", "physics_wait", "observer"}
FRAME_METRICS = {"frame_work", "frame_wall"}
COUNTS = {"actors", "summons", "projectiles", "zones", "constructs", "threats"}
RSS_SOURCES = {"linux": "proc.status.VmRSS_kib", "darwin": "ps.rss_kib", "win32": "GetProcessMemoryInfo.WorkingSetSize"}
RSS_SCOPE = "godot_process_after_pid_announcement"


def _validate_runtime_logs(stdout_path: Path, engine_path: Path) -> None:
    """Require both producer streams and apply the shared strict log contract."""
    for path in (stdout_path, engine_path):
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"required runtime log is missing or redirected: {path}")
    validate_logs([stdout_path, engine_path])


def _number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def _metric(value, count):
    if not isinstance(value, dict) or value.get("count") != count or type(value.get("count")) is not int:
        raise ValueError("timing sample count differs from actual accepted frames")
    for key in ["total_usec", "mean_usec", "p50_usec", "p95_usec", "maximum_usec"]:
        if not _number(value.get(key)):
            raise ValueError("timings must be finite nonnegative numbers")
    if not value["p50_usec"] <= value["p95_usec"] <= value["maximum_usec"] or not math.isclose(value["mean_usec"] * count, value["total_usec"], rel_tol=1e-6, abs_tol=0.01):
        raise ValueError("timing distribution is internally inconsistent")


def validate_report(value):
    if not isinstance(value, dict) or type(value.get("schema_version")) is not int or value.get("schema_version") != 1 or value.get("report_kind") != "actual_native_main_performance" or value.get("status") != "pass":
        raise ValueError("actual native Main performance report did not pass")
    if value.get("human_playtests") != 0 or value.get("unassisted_victory") is not False or value.get("fps_certified") is not False or value.get("survival_fixture") != "native_performance_survival_fixture":
        raise ValueError("performance samples cannot claim human, unassisted or FPS certification")
    count = value.get("accepted_frames")
    if type(count) is not int or not 1 <= count <= 162000 or count != value.get("requested_frames") or value.get("failures") != []:
        raise ValueError("every requested actual native frame must pass")
    scheduler = value.get("scheduler", {})
    if scheduler.get("physics_ticks_per_second") != 60 or type(scheduler.get("physics_ticks_per_second")) is not int or scheduler.get("native_hz") != 60 or type(scheduler.get("native_hz")) is not int or type(scheduler.get("time_scale")) not in (int, float) or scheduler.get("time_scale") != 1.0 or type(scheduler.get("wall_accelerated")) is not bool:
        raise ValueError("production 60Hz native scheduling with unit time scale must be explicit")
    snapshot = value.get("content_snapshot", {})
    packs = snapshot.get("packs", [])
    if not re.fullmatch(r"[0-9a-f]{64}", str(snapshot.get("aggregate_sha256", ""))) or not isinstance(packs, list) or not packs:
        raise ValueError("actual authoritative content fingerprint is required")
    for pack in packs:
        if not isinstance(pack, dict) or not isinstance(pack.get("pack_id"), str) or not pack["pack_id"] or not isinstance(pack.get("pack_version"), str) or not pack["pack_version"] or not re.fullmatch(r"[0-9a-f]{64}", str(pack.get("fingerprint_sha256", ""))):
            raise ValueError("every actual content pack must retain its identity and fingerprint")
    encounter = value.get("encounter", {})
    if type(value.get("prerequisite_route_fixture")) is not bool or type(encounter.get("floor_index")) is not int or not 0 <= encounter["floor_index"] <= 4 or encounter.get("room_type") not in {"combat", "elite", "boss"} or not isinstance(encounter.get("node_id"), str) or not encounter["node_id"]:
        raise ValueError("actual native encounter and prerequisite fixture classification are required")
    if not _number(value.get("native_duration_ms")) or not math.isclose(value["native_duration_ms"], count * 1000 / 60, abs_tol=0.01) or not _number(value.get("wall_duration_usec")):
        raise ValueError("native and elapsed wall durations must be separate and consistent")
    frames = value.get("sample_frames", {})
    if any(type(frames.get(key)) is not int for key in ["first", "last", "unique_count"]) or frames["first"] < 0 or frames["last"] - frames["first"] + 1 != count or frames["unique_count"] != count:
        raise ValueError("measured samples must be unique consecutive actual Player frames")
    measurement_version = value.get("measurement_schema_version", 1)
    if type(measurement_version) is not int or measurement_version not in (1, 2, 3):
        raise ValueError("unsupported native measurement schema")
    metrics = value.get("metrics", {})
    required_metrics = METRICS | FRAME_METRICS if measurement_version >= 2 else METRICS
    if not isinstance(metrics, dict) or set(metrics) != required_metrics:
        raise ValueError("independent Player, Host, physics and observer metrics are required")
    for metric in metrics.values():
        _metric(metric, count)
    if type(value.get("rendered")) is not bool:
        raise ValueError("render availability must be explicit")
    if value["rendered"]:
        _metric(value.get("render_wait"), count)
    elif value.get("render_wait") != {"count": 0}:
        raise ValueError("headless runs cannot invent render timings")
    if measurement_version >= 2:
        work = metrics["frame_work"]["total_usec"]
        wall = metrics["frame_wall"]["total_usec"]
        enclosed_work = metrics["player_advance"]["total_usec"] + metrics["host_process"]["total_usec"]
        enclosed_wall = work + metrics["physics_wait"]["total_usec"] + metrics["observer"]["total_usec"]
        if value["rendered"]:
            enclosed_wall += value["render_wait"]["total_usec"]
        if work < enclosed_work or wall < enclosed_wall or wall > value["wall_duration_usec"]:
            raise ValueError("same-frame intervals must enclose actual measured work and waits")
        _validate_process_rss(value)
    peaks = value.get("observed_peak_counts", {})
    if not isinstance(peaks, dict) or set(peaks) != COUNTS or any(type(count) is not int or count < 0 for count in peaks.values()) or peaks["actors"] < 1:
        raise ValueError("actual nonnegative observed native concurrency is required")
    recording = value.get("recording", {})
    if recording.get("status") != "INTERRUPTED" or type(recording.get("actual_sample_count")) is not int or recording.get("actual_sample_count") != count or type(recording.get("total_tape_observations")) is not int or recording.get("total_tape_observations") != count + 1 or recording.get("failure") != "" or recording.get("physical_first_exact") is not True or recording.get("physical_last_exact") is not True:
        raise ValueError("physical recording readback and honest incomplete classification are required")
    for key in ["first_sha256", "last_sha256"]:
        if not re.fullmatch(r"[0-9a-f]{64}", str(recording.get(key, ""))):
            raise ValueError("exact retained sample hashes are required")
    hub = value.get("hub", {})
    if type(hub.get("frames")) is not int or hub["frames"] < 1 or type(hub.get("visited_functions")) is not int or hub["visited_functions"] < 9:
        raise ValueError("actual three-district nine-function Hub measurement is required")
    _metric(hub.get("scheduler_and_render_wait"), hub["frames"])
    if not _number(hub.get("wall_duration_usec")):
        raise ValueError("actual Hub duration and native memory observation are required")
    peak_static = value.get("peak_native_static_bytes")
    if type(peak_static) is not int or peak_static < 0 or measurement_version < 3 and peak_static == 0:
        raise ValueError("actual Hub duration and native memory observation are required")
    if measurement_version == 3:
        monitor = value.get("native_static_monitor")
        if type(value.get("debug_build")) is not bool or not isinstance(monitor, dict) or set(monitor) != {"source", "available", "reason"} or monitor["source"] != "Performance.MEMORY_STATIC" or type(monitor["available"]) is not bool:
            raise ValueError("runtime build and static monitor availability must be explicit")
        if monitor["available"] != (peak_static > 0) or monitor["reason"] != ("" if monitor["available"] else "release_build") or not monitor["available"] and value["debug_build"]:
            raise ValueError("only a release zero observation can declare the static monitor unavailable")
        _validate_native_pid_binding(value)
    return value


def _validate_native_pid_binding(value):
    binding = value.get("native_pid_binding")
    fields = {"source", "bootstrap_path", "bootstrap_process_id", "stdout_process_id", "stdout_announcement_count", "sampled_process_id", "status", "failure"}
    if not isinstance(binding, dict) or set(binding) != fields or binding["source"] != "runtime_bootstrap_file_and_final_stdout" or type(binding["bootstrap_path"]) is not str or not binding["bootstrap_path"] or binding["status"] != "pass" or binding["failure"] != "":
        raise ValueError("v3 requires a verified runtime bootstrap and final stdout PID binding")
    if type(binding["stdout_announcement_count"]) is not int or binding["stdout_announcement_count"] != 1:
        raise ValueError("exactly one final stdout native PID announcement is required")
    process_id = value.get("native_process_id")
    for field in ["bootstrap_process_id", "stdout_process_id", "sampled_process_id"]:
        if type(binding[field]) is not int or not 1 <= binding[field] <= 4294967295 or binding[field] != process_id:
            raise ValueError("bootstrap, stdout, report and sampled native process identities must agree")
    if value.get("process_rss", {}).get("process_id") != binding["sampled_process_id"]:
        raise ValueError("the retained PID binding must match actual process RSS samples")


def _read_bootstrap_process_id(path):
    if any(part.is_symlink() for part in [path, *path.parents]) or not path.is_file():
        raise ValueError("runtime bootstrap PID must be a regular non-symlink file")
    with path.open(encoding="ascii") as stream:
        text = stream.read(64)
    if not re.fullmatch(r"[1-9][0-9]{0,9}\n?", text) or int(text) > 4294967295:
        raise ValueError("runtime bootstrap file must contain one positive native process id")
    return int(text)


def _collect_native_pid_binding(pid_path, stdout_path, value):
    binding = {"source": "runtime_bootstrap_file_and_final_stdout", "bootstrap_path": str(pid_path), "bootstrap_process_id": 0, "stdout_process_id": 0, "stdout_announcement_count": 0, "sampled_process_id": value.get("process_rss", {}).get("process_id", 0), "status": "pass", "failure": ""}
    value["native_pid_binding"] = binding
    try:
        binding["bootstrap_process_id"] = _read_bootstrap_process_id(pid_path)
        announcements = [line for line in stdout_path.read_text(encoding="utf-8").splitlines() if line.startswith("NATIVE_PERFORMANCE_PROCESS_PID")]
        binding["stdout_announcement_count"] = len(announcements)
        if len(announcements) == 1:
            match = re.fullmatch(r"NATIVE_PERFORMANCE_PROCESS_PID ([1-9][0-9]{0,9})", announcements[0])
            if match is not None:
                binding["stdout_process_id"] = int(match[1])
        _validate_native_pid_binding(value)
    except (OSError, UnicodeError, ValueError) as error:
        binding["status"] = "failed"
        binding["failure"] = str(error)[:300]


def _validate_process_rss(value):
    rss = value.get("process_rss")
    if not isinstance(rss, dict) or type(rss.get("platform")) is not str or rss["platform"] not in RSS_SOURCES or rss.get("source") != RSS_SOURCES[rss["platform"]] or rss.get("scope") != RSS_SCOPE:
        raise ValueError("actual platform process RSS source and sampling scope are required")
    for key in ["process_id", "sample_interval_ms", "valid_sample_count", "peak_bytes"]:
        if type(rss.get(key)) is not int or rss[key] < 1:
            raise ValueError("process RSS requires positive real samples, bytes and native identity")
    if type(rss.get("failed_sample_count")) is not int or rss["failed_sample_count"] < 0 or type(value.get("native_process_id")) is not int or value["native_process_id"] != rss["process_id"]:
        raise ValueError("process RSS samples must belong to the exact native Godot process")


def _read_process_rss(process_id, platform):
    if type(process_id) is not int or not 1 <= process_id <= 4294967295:
        raise ValueError("native process id must be positive")
    if platform == "linux":
        text = Path(f"/proc/{process_id}/status").read_text(encoding="ascii")
        match = re.search(r"^VmRSS:\s+([0-9]+)\s+kB$", text, re.MULTILINE)
        result = int(match[1]) * 1024 if match else 0
    elif platform == "darwin":
        completed = subprocess.run(["/bin/ps", "-o", "rss=", "-p", str(process_id)], text=True, capture_output=True, timeout=1, check=False)
        text = completed.stdout.strip()
        result = int(text) * 1024 if completed.returncode == 0 and re.fullmatch(r"[0-9]+", text) else 0
    elif platform == "win32":
        import ctypes
        from ctypes import wintypes

        class ProcessMemoryCounters(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] + [(name, ctypes.c_size_t) for name in ["PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage"]]

        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        psapi = ctypes.WinDLL("psapi", use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.CloseHandle.restype = wintypes.BOOL
        psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(ProcessMemoryCounters), wintypes.DWORD]
        psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
        handle = kernel.OpenProcess(0x0400 | 0x0010, False, process_id)
        if not handle:
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            counters = ProcessMemoryCounters()
            counters.cb = ctypes.sizeof(counters)
            if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
                raise ctypes.WinError(ctypes.get_last_error())
            result = int(counters.WorkingSetSize)
        finally:
            kernel.CloseHandle(handle)
    else:
        raise OSError("process RSS sampling is unavailable on this platform")
    if result <= 0:
        raise OSError("native process RSS sample is unavailable")
    return result


class _ProcessRssSampler:
    def __init__(self, stdout_path, platform=None):
        self.stdout_path = stdout_path
        self.pid_path = stdout_path.with_name("process.pid")
        self.platform = sys.platform if platform is None else platform
        self.process_id = 0
        self.valid_samples = 0
        self.failed_samples = 0
        self.peak_bytes = 0
        self.last_error = ""
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="native-process-rss", daemon=True)

    def start(self):
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self._thread.ident is not None:
            self._thread.join()

    def _run(self):
        while not self._stop.is_set():
            self._sample()
            self._stop.wait(0.1)

    def _sample(self):
        try:
            if not self.process_id:
                if self.pid_path.exists() or self.pid_path.is_symlink():
                    self.process_id = _read_bootstrap_process_id(self.pid_path)
                else:
                    with self.stdout_path.open(encoding="utf-8") as stream:
                        text = stream.read(65536)
                    ids = re.findall(r"^NATIVE_PERFORMANCE_PROCESS_PID ([0-9]+)$", text, re.MULTILINE)
                    if len(ids) != 1 or not 1 <= int(ids[0]) <= 4294967295:
                        return
                    self.process_id = int(ids[0])
            resident = _read_process_rss(self.process_id, self.platform)
            self.peak_bytes = max(self.peak_bytes, resident)
            self.valid_samples += 1
        except (OSError, UnicodeError, ValueError, subprocess.TimeoutExpired) as error:
            self.failed_samples += 1
            self.last_error = str(error)[:300]

    def snapshot(self):
        return {"platform": self.platform, "source": RSS_SOURCES.get(self.platform, "unavailable"), "scope": RSS_SCOPE, "process_id": self.process_id, "sample_interval_ms": 100, "valid_sample_count": self.valid_samples, "failed_sample_count": self.failed_samples, "peak_bytes": self.peak_bytes, "last_error": self.last_error}


def _runtime_sources():
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for directory in ["scripts", "autoload"] for path in sorted((ROOT / directory).rglob("*.gd"))}


def _file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1048576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _macos_package_plist(binary_argument, resource_argument):
    binary = binary_argument.absolute()
    resource = resource_argument.absolute()
    for path in [binary, resource]:
        if any(part.is_symlink() for part in [path, *path.parents]):
            raise ValueError("packaged executable and PCK paths must not contain symlinks")
    binary = binary.resolve()
    resource = resource.resolve()
    contents = binary.parent.parent
    bundle = contents.parent
    if binary.parent.name != "MacOS" or contents.name != "Contents" or bundle.suffix != ".app":
        raise ValueError("packaged mode currently requires a native macOS application bundle")
    plist = contents / "Info.plist"
    if not plist.is_file() or plist.is_symlink():
        raise ValueError("the package must contain a regular Info.plist")
    try:
        with plist.open("rb") as stream:
            metadata = plistlib.load(stream)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise ValueError("package Info.plist is unreadable or malformed") from error
    if not isinstance(metadata, dict) or metadata.get("CFBundleExecutable") != binary.name:
        raise ValueError("Info.plist must bind the exact packaged executable")
    expected = contents / "Resources" / (binary.name + ".pck")
    if resource != expected:
        raise ValueError("the PCK must be the executable's automatically loaded bundle resource")
    for directory in [expected.parent, binary.parent, bundle]:
        packs = [path for path in directory.iterdir() if path.suffix.lower() == ".pck"]
        if packs != ([expected] if directory == expected.parent else []):
            raise ValueError("the bundle must contain exactly one unambiguous automatically loaded PCK")
    return plist


def _source_identity(sources):
    git_root = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT, text=True, capture_output=True, check=False)
    own_checkout = git_root.returncode == 0 and Path(git_root.stdout.strip()).resolve() == ROOT
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, capture_output=True, check=False) if own_checkout else None
    return {"revision": revision.stdout.strip() if revision is not None and revision.returncode == 0 else "", "runtime_source_sha256": hashlib.sha256(json.dumps(sources, sort_keys=True, separators=(",", ":")).encode()).hexdigest(), "instrumented": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--hub-frames", type=int, default=120)
    parser.add_argument("--boss-floor", type=int, default=-1, choices=[-1, 0, 1, 2, 3, 4])
    parser.add_argument("--phase", type=int, default=0, choices=[0, 1, 2])
    parser.add_argument("--real-time", action="store_true", help="keep wall-clock pacing; otherwise use Godot fixed-fps scheduling")
    parser.add_argument("--rendered", action="store_true")
    parser.add_argument("--timeout", type=int, default=28800)
    parser.add_argument("--packaged-binary", type=Path, help="run an exported package whose own main scene is the probe")
    parser.add_argument("--packaged-resource", type=Path, help="authenticate the exported package's PCK alongside its executable")
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "build") or output.exists():
        parser.error("output must be a new path under this project's build directory")
    if not 1 <= args.frames <= 162000 or not 9 <= args.hub_frames <= 162000 or args.phase > 0 and args.boss_floor < 0 or args.timeout <= 0:
        parser.error("invalid bounded native duration, scheduler or Boss phase")
    if args.packaged_binary is not None:
        if args.packaged_resource is None:
            parser.error("--packaged-binary requires --packaged-resource")
        binary = args.packaged_binary.resolve()
        resource = args.packaged_resource.resolve()
        if not binary.is_file() or not os.access(binary, os.X_OK) or not resource.is_file():
            parser.error("the packaged executable and PCK must exist and the executable must be runnable")
        try:
            package_plist = _macos_package_plist(args.packaged_binary, args.packaged_resource)
        except ValueError as error:
            parser.error(str(error))
    else:
        if args.packaged_resource is not None:
            parser.error("--packaged-resource requires --packaged-binary")
        godot = shutil.which(os.environ.get("GODOT_BIN", "godot"))
        if not godot:
            parser.error("GODOT_BIN must identify a real Godot executable")
        binary = Path(godot).resolve()
        resource = None
        if not binary.is_file():
            parser.error("GODOT_BIN must identify an existing Godot executable")
    output.parent.mkdir(parents=True, exist_ok=True)
    pid_path = output.with_name("process.pid")
    if pid_path.exists() or pid_path.is_symlink():
        parser.error("runtime bootstrap PID path must be new and must not be a symlink")
    environment = dict(os.environ)
    environment["PLANEWALKER_PERFORMANCE_PID_FILE"] = str(pid_path)
    environment.update({"PLANEWALKER_PERFORMANCE_OUTPUT": str(output), "PLANEWALKER_PERFORMANCE_FRAMES": str(args.frames), "PLANEWALKER_PERFORMANCE_HUB_FRAMES": str(args.hub_frames), "PLANEWALKER_PERFORMANCE_BOSS_FLOOR": str(args.boss_floor), "PLANEWALKER_PERFORMANCE_PHASE": str(args.phase), "PLANEWALKER_PERFORMANCE_WALL_ACCELERATED": str(not args.real_time).lower(), "PLANEWALKER_PERFORMANCE_RENDERED": str(args.rendered).lower(), "PLANEWALKER_TEST_DATA_DIR": str(output.parent / "isolated-files"), "PLANEWALKER_USER_DATA_DIR": str(output.parent / "isolated-files"), "XDG_DATA_HOME": str(output.parent / "isolated-data")})
    for key in ["PLANEWALKER_COVERAGE_HITS_DIR", "PLANEWALKER_COVERAGE_MANIFEST_SHA256", "GDSCRIPT_COVERAGE_PROVIDER_REPORT"]:
        environment.pop(key, None)
    stdout_path = output.parent / "stdout.log"
    engine_path = output.parent / "godot.log"
    command = [str(binary)]
    if resource is None:
        command.extend(["--path", str(ROOT)])
    command.extend(["--log-file", str(engine_path)])
    if not args.real_time:
        command.extend(["--fixed-fps", "60"])
    if not args.rendered:
        command.append("--headless")
    if resource is None:
        command.append("res://tools/p15/native_performance_probe.tscn")
    sources = _runtime_sources()
    source_identity = _source_identity(sources)
    source_identity.update(runtime_kind="packaged_binary" if resource is not None else "source_project", source_checkout_role="harness_only" if resource is not None else "executed_project", godot_binary=str(binary), godot_binary_sha256=_file_sha256(binary), command=command)
    if resource is not None:
        source_identity.update(packaged_resource=str(resource), packaged_resource_sha256=_file_sha256(resource), packaged_resource_binding="macos_bundle_autoload", package_info_plist=str(package_plist), package_info_plist_sha256=_file_sha256(package_plist))
    manifest_path = output.with_name("source-manifest.json")
    manifest_path.write_text(json.dumps({**source_identity, "runtime_files_sha256": sources}, indent=2, sort_keys=True) + "\n")
    result = None
    timed_out = False
    rss_sampler = _ProcessRssSampler(stdout_path)
    try:
        with stdout_path.open("w", encoding="utf-8") as stream:
            rss_sampler.start()
            result = subprocess.run(command, cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT, timeout=args.timeout, check=False)
    except subprocess.TimeoutExpired:
        timed_out = True
        raise
    finally:
        rss_sampler.stop()
        source_identity["runtime_source_stable"] = _runtime_sources() == sources
        source_identity["process_exit_code"] = result.returncode if result is not None else None
        source_identity["timed_out"] = timed_out
        for path, field in [(binary, "godot_binary")] + ([(resource, "packaged_resource"), (package_plist, "package_info_plist")] if resource is not None else []):
            try:
                final_digest = _file_sha256(path)
            except OSError:
                final_digest = ""
            source_identity[field + "_final_sha256"] = final_digest
            source_identity[field + "_stable"] = final_digest == source_identity[field + "_sha256"]
        if resource is not None:
            try:
                source_identity["packaged_layout_stable"] = _macos_package_plist(args.packaged_binary, args.packaged_resource) == package_plist
            except (OSError, ValueError):
                source_identity["packaged_layout_stable"] = False
        try:
            _validate_runtime_logs(stdout_path, engine_path)
            source_identity["runtime_logs_clean"] = True
            source_identity["runtime_log_failure"] = ""
        except ValueError as error:
            source_identity["runtime_logs_clean"] = False
            source_identity["runtime_log_failure"] = str(error)[:300]
        execution_ok = result is not None and result.returncode == 0 and source_identity["runtime_source_stable"] and source_identity["runtime_logs_clean"] and source_identity["godot_binary_stable"] and source_identity.get("packaged_resource_stable", True) and source_identity.get("package_info_plist_stable", True) and source_identity.get("packaged_layout_stable", True)
        manifest_path.write_text(json.dumps({**source_identity, "runtime_files_sha256": sources, "execution_status": "pass" if execution_ok else "failed"}, indent=2, sort_keys=True) + "\n")
        if output.is_file():
            retained = json.loads(output.read_text())
            retained["native_status"] = retained.get("status")
            retained["process_rss"] = rss_sampler.snapshot()
            if retained.get("measurement_schema_version") == 3:
                _collect_native_pid_binding(pid_path, stdout_path, retained)
            if not execution_ok:
                retained["status"] = "failed"
            elif retained.get("status") == "pass":
                try:
                    if resource is not None and retained.get("measurement_schema_version") != 3:
                        raise ValueError("packaged measurements require explicit v3 runtime build and monitor metadata")
                    validate_report(retained)
                except ValueError as error:
                    retained["status"] = "failed"
                    retained["validation_failure"] = str(error)
            retained["source"] = source_identity
            output.write_text(json.dumps(retained, indent=2, sort_keys=True) + "\n")
    if result.returncode or not source_identity["runtime_logs_clean"]:
        raise SystemExit(f"actual native performance run failed; inspect {stdout_path}")
    if not source_identity["runtime_source_stable"]:
        raise SystemExit("runtime sources changed during native performance measurement")
    if not source_identity["godot_binary_stable"] or not source_identity.get("packaged_resource_stable", True) or not source_identity.get("package_info_plist_stable", True) or not source_identity.get("packaged_layout_stable", True):
        raise SystemExit("runtime executable, packaged PCK, Info.plist or bundle layout changed during native performance measurement")
    report = validate_report(json.loads(output.read_text()))
    print(json.dumps({"report": str(output), "measurement_schema_version": report.get("measurement_schema_version", 1), "accepted_frames": report["accepted_frames"], "native_duration_ms": report["native_duration_ms"], "wall_duration_usec": report["wall_duration_usec"], "player_advance": report["metrics"]["player_advance"], "frame_work": report["metrics"].get("frame_work"), "frame_wall": report["metrics"].get("frame_wall"), "process_rss": report.get("process_rss"), "observed_peak_counts": report["observed_peak_counts"]}, indent=2))


if __name__ == "__main__":
    main()
