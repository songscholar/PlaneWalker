# Content Pack Export Integrity Evidence

- Status: Approved / Current
- Document Role: Current focused native content-pack export verification
- Authority Level: Verification evidence below full-product execution policy
- Applies To: Original content bytes, native resource remaps and packed Main/Profile boot
- Owner: Project verification lane
- Depends On: `AGENTS.md`, `tools/export/README.md`, `docs/current/2026-10-05-p17a-actor-atlases-evidence.md`
- Last Verified: 2026-10-05
- Implementation Status: Original-byte preservation, authenticated packed content and focused packed native workflows verified
- Exit Gate: Complete descriptor integrity and native imported resources coexist in a real PCK; malformed inputs fail the export log gate

## Defect And Repair

The original macOS Debug PCK omitted Base pack PNG, scene and CSV source bytes
after Godot imported or compiled them. ContentPackDescriptor correctly refused
the first absent hashed PNG (`assets/enemies/launch/acid_pool.png`). Separately,
the Hub validator treated a compiled scene remap as a missing raw file.

The enabled project export plugin authenticates each descriptor under
`res://data/content_packs`, validates the exact bytes it will emit against the
declared SHA-256 hashes, then adds those original paths without remapping.
Godot's imported textures, compiled scenes and generated translations are still
exported normally. Runtime content-pack authentication is unchanged. Hub scene
availability now uses ResourceLoader's PackedScene-aware existence check while
retaining its fixed scene path allowlist and strict native scene contract.

The plugin reports any malformed descriptor or changed source as an export
error before adding authenticated source files. Godot may still exit zero after
EditorExportPlatform reports an error, so the existing export tools' complete
log scan remains part of acceptance. No exit-code-only acceptance is introduced.

## Verification

- Packed RED: `/private/tmp/plane-walker-raw-export-red-runtime.log` refuses complete Base integrity and Launch activation because the raw PNG is absent. No script errors or leaks.
- Focused real export contracts: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.export.test_content_pack_source_export -v`, 3/3 GREEN. A fresh fixture exports and starts its PCK with authenticated PNG/scene/CSV bytes plus native Texture2D/PackedScene loading; changed bytes and escaping declared paths fail the same export log gate used by packaging.
- Source Main/Profile boot contract: `planewalker-tests.NtKVIP`, 1/1 GREEN, no script errors or leaks.
- Actual complete macOS Debug PCK: `/private/tmp/plane-walker-raw-export-green-3.pck`, 76 declared source files authenticated and preserved; export log `/private/tmp/plane-walker-raw-export-green-3.log`.
- Packed complete Base hashes, Launch activation, native texture/scene and actual Main/Profile/Hub: `/private/tmp/plane-walker-raw-export-green-3-runtime.log`, PASS.
- Packed five actual Player atlases and full replay snapshot neutrality: `/private/tmp/plane-walker-packed-players-green-3.log`, PASS.
- Packed Main cold native restore, durable tutorial observation and failure retry: `/private/tmp/plane-walker-packed-resume-green-3.log`, PASS.
- Packed Main Hub-to-training transition and sandbox lifecycle: `/private/tmp/plane-walker-packed-training-green-3.log`, PASS.
- Existing classified log scanner reports no failures across these five actual export/runtime logs. Each contains only the already registered macOS system-CA diagnostic at its exact callsite; it is not generalized to other engine errors. No script errors or leaks were observed.

The fixture runtime does not write a game Profile. Actual production Profile
tests use separate temporary `PLANEWALKER_TEST_DATA_DIR` paths. The copied
self-contained editor keeps editor settings inside the project's build toolchain.

## Limits And Rollback

This focused repair certifies the recorded PCK workflows, not a clean-checkout
release-template distributable, full five-floor combat, hardware controllers,
signing or publication. Current source changes after the recorded export need a
fresh package before receiving new build evidence. Parent owns consolidated
indexing and milestone retention. Disabling the project plugin reverses export
source preservation; runtime descriptor authentication remains strict.
