# Clean Serial Import Recovery

- Status: Focused Verified / Current
- Document Role: Current clean-import correctness retention evidence
- Authority Level: Below approved full-product and P7/P9 specifications
- Applies To: Fresh Godot 4.6.1 bootstrap and clean second import
- Owner: Plane Walker integration lead
- Last Verified: 2026-10-05
- Depends On: `../../AGENTS.md`, `../superpowers/plans/2026-09-29-plane-walker-p7-p9-exports-certification.md`

## Reproduced Failure

The immutable `1f147e6` certification stopped at bootstrap import with exit134,
before scene tests, line coverage, exports or packaged startup. The retained
logs are under `build/certified/1f147e6-source/build/evidence/logs/validation/`.
The operating-system crash report identifies WorkerThread7, an invalid allocator
free, and ResourceImporterCSVTranslation::import through ResourceSaver::save,
EditorNode::_resource_saved and EditorFileSystem::update_files. Missing initial
translation derivatives are expected bootstrap diagnostics; the process abort
is not an approved diagnostic.

## Recovery And Evidence

Commit `7a85597` sets `editor/import/use_multiple_threads=false` in the project.
The setting serializes editor import jobs without changing gameplay threading
or content bytes. A fresh `git clone --no-local --no-hardlinks` at that exact
detached commit started with no generated import cache and clean Git state.

Both `godot --headless --editor --import` phases exited0. Bootstrap rebuilt all
eleven CSV source pairs. The existing `tools.validate_import_translations`
classifier verified their generated derivatives and left no unclassified
errors. The second import had no errors. Both logs have no script/parse errors
or ObjectDB/RID leak signatures, and the checkout remains clean afterward.

Logs: `build/certified/7a85597-import-source/build/evidence/serial-import-*`.
The clone is retained locally for inspection. This repairs the reproduced
import crash; it does not claim universal absence of upstream importer defects.

The project requirements audit also completed:16 resolved packages from
`requirements-dev.txt`, `requirements-production-art.txt` and
`requirements-coverage.txt`, with zero known vulnerabilities. JSON evidence:
`build/toolchain/dependency-audit-2026-10-05.json`. Its tool and cache are scoped
to the project build/toolchain directory.

## Remaining Gates

Complete validation, exact-source instrumented coverage, retained release
exports and packaged startup still require a new combined immutable-source run.
The prior failed certification remains failed and is not overwritten. New
Summon, Void auxiliary and elite work must be retained before certifying their
combined final source.
