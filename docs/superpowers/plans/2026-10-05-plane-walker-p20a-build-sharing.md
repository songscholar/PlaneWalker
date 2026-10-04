# Plane Walker P20A Build Sharing Implementation Plan

- Status: Implemented / Current
- Document Role: Current implementation plan
- Authority Level: P20A execution record
- Applies To: Portable build codec, authenticated Hub import/export and native controls
- Owner: Project owner
- Depends On: [P20A design](../specs/2026-10-05-plane-walker-p20a-build-sharing-design.md)
- Last Verified: 2026-10-05
- Exit Gate: All six executable criteria in the P20A specification pass

> **For agentic workers:** Execute the focused test cycle task by task under the standing authorization in `AGENTS.md`.

**Goal:** Share owned loadouts through a strict offline code in the actual Hub.

**Architecture:** A pure codec produces existing BuildLibrary values. Hub commands
reuse ProfileRuntimeService's authoritative validation and atomic persistence.
The panel presents detached results and only accesses the clipboard on command.

**Tech Stack:** Godot 4.6 GDScript, JSON, SHA-256, SaveService, native Control UI.

## Tasks

### Codec And Domain Contract

- [x] Add `tests/unit/progression/build_share_codec_test.gd` and its scene.
  Dynamically load the missing codec; require all 150 combinations to round-trip,
  reject extra fields, invalid pair/checksum/schema and oversized values.
- [x] Run `TEST_LOG_DIR=build/test-logs/p20a-codec-red tools/run_tests.sh --filter build_share_codec`;
  expect the assertion that the codec exists to fail.
- [x] Create `scripts/progression/build_share_codec.gd` with
  `static func encode(build: Dictionary) -> Dictionary` and
  `static func decode(code: Variant) -> Dictionary`. Return existing Candidate
  result dictionaries and detached `share_code`/`build` contexts.
- [x] Re-run the codec scene; require no script errors or leaks.

### Authenticated Native Import And Export

- [x] Add a physical Hub sharing scene testing export/import/restart, locked
  loadouts, stale epochs, library capacity and injected promotion failure.
- [x] Add `build_export` and `build_import` meditation operations in
  `scripts/hub/hub_runtime_facade.gd`; route decoded `build_save` to the real
  Profile service and preserve rejection codes.
- [x] Add native share field/actions in `scripts/ui/hub_panel_view.gd` and
  detached result delivery in `scripts/hub/hub_flow_coordinator.gd`.
- [x] Add localized action and rejection keys to the canonical translation CSV;
  root updates exact content bindings and retained compatibility descriptors.
- [x] Test actual Main controls, controller focus, retired callbacks and retry
  text preservation at 640x360 and 1280x720 in both locales.

### Retention

- [x] Run focused codec/Hub/production regressions and document actual evidence.
- [x] Index specification, plan and evidence in `docs/README.md`.
- [x] Commit only the reviewed P20A files; record remaining community/mode gates.
