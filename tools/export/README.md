# Local Export Tools

`preflight.py --mode local` checks the tracked export contract and each selected
official Godot template. `build_exports.py --templates-dir PATH` uses a copied
self-contained editor below `build/toolchain/export-editor/`, so the supplied
template directory is also the directory Godot reads. It never installs templates
in a personal Godot directory. macOS editor copies retain the complete upstream
application bundle; moving only its executable can fail macOS signature checks.

The enabled `addons/content_pack_source_export` plugin preserves each content
pack's original declared bytes beside Godot's imported textures, compiled scenes
and translations. This lets exported runtime content keep the same SHA-256
descriptor authentication as source checkouts. Malformed descriptors or changed
sources produce export error logs; Godot may still exit zero, so build acceptance
must include the tools' log scan. Real fixture PCK and actual Main/Profile gates
are recorded in `docs/current/2026-10-05-content-pack-export-evidence.md`.

`python3 tools/export/fetch_templates.py` downloads the official Godot 4.6.1
archive using resumable HTTP ranges. Its release size and SHA-256 are pinned
from the upstream release metadata. Completed ranges remain in the project
cache; only a full digest match promotes the archive. Installation validates
ZIP paths, version and the complete selected macOS/Linux/Windows release set
before replacing the project template directory. No personal installation is
modified. Use `--workers` to control concurrent transfers.
The CLI prefers curl's IPv4 transport when available; `--transport urllib`
selects the standard-library backend. Both enforce the same exact response
range, length and final archive digest before installation.

## Offline macOS Fallback

When release templates are unavailable, build a local package from an installed
Godot binary whose version and SHA-256 appear in
`data/toolchain/m1_godot_toolchains.json`:

```sh
python3 tools/export/portable_runtime.py \
  --godot-bin /Applications/Godot.app/Contents/MacOS/Godot \
  --output-dir build/portable/PlaneWalker-macos-local \
  --evidence-output build/export-evidence/portable-report.json
```

Choose an empty output directory. The tool preserves prior candidates and refuses
untrusted executables. It copies the official application bundle, extracts the
runtime's own MIT and third-party notices, exports a PCK, and starts its real Main
scene for 300 headless iterations. `PlaneWalker.command` runs that PCK without a
source-project path or gameplay test harness. The launcher uses
`PLANEWALKER_USER_DATA_DIR` to keep application saves and input profiles below its
own `user-data/` directory.

The report includes artifact hashes, runtime provenance, commands, and log scans.
Only the known macOS system-CA diagnostic with its original callsite is classified
as environmental. Script/resource errors, other engine errors, and leaks fail
the build even if Godot exits zero.

This package is an explicit editor-runtime fallback. The startup check does not
certify five-floor combat, visual layouts, controller flows, other platforms,
signing, or notarization. Godot itself may create its default empty macOS engine
data directory; application persistence uses the isolated directory. Formal
release exports use official templates and the normal export certification.

## Retained Detached Builds

The clean-checkout certifier can retain authenticated release artifacts before
deleting its temporary checkout and run the existing host startup verifier:

```sh
python3 tools/export/certify_checkout.py \
  --commit HEAD \
  --godot-bin /Applications/Godot.app/Contents/MacOS/Godot \
  --templates-dir build/toolchain/godot-4.6.1/templates/4.6.1.stable \
  --artifact-dir build/certified/current-candidate \
  --verify-packaged-startup \
  --evidence-output build/export-evidence/current-candidate.json \
  --log-dir build/export-evidence/current-candidate-logs
```

Use an empty artifact directory and a fresh log directory. Existing packages
are refused before validation. Each artifact is authenticated against the export
report before copying, then hashed again in both locations. Relative internal
bundle links and executable modes survive; escaping paths/links and changed
bytes fail retention. The report's `retained_path` values locate the surviving
packages, while startup reports/logs are copied under the supplied log directory.

Startup executes the release artifact from an empty directory with isolated
application data, without a source-project path. Passing this host check clears
only `packaged_startup`; missing real line coverage still blocks certification.
Other platforms, complete gameplay and human feedback require their own evidence.
The certifier's `--godot-bin` also selects the editor for clean validation.

## Linux Guest Startup

`verify_linux_guest_startup.py` authenticates a retained Linux x86_64 executable
against its export report, then runs the real Main startup check in a Linux amd64
Docker guest. Supply an already installed immutable public image with a glibc
runtime. The verifier does not pull images or use personal Docker credentials.
For retained certifier output, `--artifact-root` is the retained directory whose
`build/linux/PlaneWalker.x86_64` was copied from the clean checkout:

```sh
python3 tools/export/verify_linux_guest_startup.py \
  --export-report build/export-evidence/current-candidate-logs/export-report.json \
  --artifact-root build/certified/current-candidate \
  --docker-host unix:///var/run/docker.sock \
  --image debian@sha256:ACTUAL_INSTALLED_IMMUTABLE_DIGEST \
  --evidence-output build/export-evidence/current-linux-guest.json \
  --log-dir build/export-evidence/current-linux-guest-logs
```

On Docker Desktop, pass its actual local Unix socket. Every run requires a fresh
log directory. The container receives only the executable as a read-only mount
and writable fresh logs; source files are not mounted. It has no network,
capabilities or writable root filesystem, and uses isolated temporary data.
Both Docker's inspected image ID and repository digest appear in the report.

Missing Docker, daemon or image produce typed blocked evidence. Changed
artifacts, architecture/digest mismatches, runtime errors/leaks and malformed or
incomplete native results fail. Passing evidence is explicitly
`linux_guest_packaged_startup_verified`, with `actual_linux_host_verified=false`
and `full_product_certified=false`. It cannot substitute for Linux display/input
QA, actual Linux or Windows host startup, complete gameplay, or human feedback.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  tests.contract.export.test_linux_guest_startup \
  tests.contract.export.test_packaged_startup
```

## Runtime Data Directory

Default GameState and input-profile paths read `PLANEWALKER_USER_DATA_DIR` first,
then `PLANEWALKER_TEST_DATA_DIR`. Values must be absolute filesystem paths;
relative paths and `res://`/`user://` values leave persistence unconfigured.
Explicit save paths and input-store roots are preserved. Without either
environment variable, normal Godot `user://` behavior remains.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s tests/contract/export -p 'test_*.py'
./tools/run_tests.sh --filter runtime_user_data_directory --timeout 30
```
