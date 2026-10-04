# Local Export Tools

`preflight.py --mode local` checks the tracked export contract and each selected
official Godot template. `build_exports.py --templates-dir PATH` uses a copied
self-contained editor below `build/toolchain/export-editor/`, so the supplied
template directory is also the directory Godot reads. It never installs templates
in a personal Godot directory. macOS editor copies retain the complete upstream
application bundle; moving only its executable can fail macOS signature checks.

`python3 tools/export/fetch_templates.py` downloads the official Godot 4.6.1
archive using resumable HTTP ranges. Its release size and SHA-256 are pinned
from the upstream release metadata. Completed ranges remain in the project
cache; only a full digest match promotes the archive. Installation validates
ZIP paths, version and the complete selected macOS/Linux/Windows release set
before replacing the project template directory. No personal installation is
modified. Use `--workers` to control concurrent transfers.

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

This package is an explicit editor-runtime fallback, not a release-template
export. The startup check does not certify five-floor combat, visual layouts,
controller flows, other platforms, signing, or notarization. Godot itself may
create its default empty macOS engine data directory; application persistence
uses the isolated directory. Formal release exports remain pending until the
official templates are available and the normal export certification passes.

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
