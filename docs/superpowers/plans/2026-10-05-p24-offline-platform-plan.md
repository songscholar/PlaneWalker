# Offline Platform Implementation Plan

- Status: In Progress
- Document Role: Current
- Authority Level: Milestone implementation plan under standing project authorization
- Applies To: Offline platform services and native panel
- Owner: Plane Walker project owner
- Depends On: `../specs/2026-10-05-p24-offline-platform-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Durable offline services, native Main entry, controller return, Profile backup and authenticated sharing pass with clean Godot logs

> **For agentic workers:** Execute the checked steps in order within the standing project authorization. Commit integration is owned by the parent agent.

**Goal:** Deliver all eight offline platform capabilities behind one validated interface.

**Architecture:** PlatformProvider defines requests, responses and convenience methods. OfflinePlatformProvider coordinates a SaveService-backed state store and safe local artifact/content helpers. ComposedPlatformProvider uses the offline result whenever an optional adapter fails validation.

**Tech Stack:** Godot 4 GDScript, SaveService, DataOnlyPackInstaller, BuildShareCodec, PlayerReplayPackage.

## Global Constraints

- No network, credentials, paid services, purchases or publication.
- Preserve gameplay domain and existing community/profile authorities.
- No arbitrary scripts, caller-chosen export paths or symlink traversal.
- Bound all request collections and return defensive copies.

### Task 1: Define Behavioral Tests

Files: tests/platform/offline_platform_test.gd/.tscn,
tests/platform/platform_composition_test.gd/.tscn.

- [x] Write failing ResourceLoader.exists guards and assertions for all capabilities.
- [x] Run RED: `GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot TEST_LOG_DIR=build/platform-red tools/run_tests.sh --filter tests/platform/`.

Core assertions exercise production storage rather than an in-memory mirror:

```gdscript
var unlocked: Dictionary = provider.unlock_achievement("first_run")
suite.assert_true(unlocked.ok and unlocked.context.inserted, "first unlock commits")
suite.assert_true(provider.unlock_achievement("first_run").context.duplicate, "retry is idempotent")
var restarted: RefCounted = script.new()
restarted.configure(root, version, binding, "owner", "base")
suite.assert_equal(restarted.achievements().context.ids, ["first_run"], "restart retains achievement")
```

### Task 2: Durable Offline Service

Files: scripts/platform/platform_provider.gd, platform_rules.gd,
platform_state_store.gd, offline_platform_provider.gd.

- [x] Implement typed convenience methods and exact-field request validation.
- [x] Add bounded platform state under SaveService's local content-bound scope.
- [x] Implement identity, achievements, cloud cache, local rankings and presence.
- [x] Refuse stale writes and reconcile only the exact promoted primary.
- [x] Run offline scene GREEN; scan its stdout and engine logs.

```gdscript
var written = save.save_profile_compare_exchange(storage_id, "local", {"platform_state": candidate}, expected)
if not written.ok:
    var primary = save.inspect_profile(storage_id, "local")
    if not primary.ok or not Rules.same(primary.payload.payload.get("platform_state"), candidate):
        return failure(written.code)
```

### Task 3: Discovery, Artifacts and Optional Composition

Files: scripts/platform/platform_local_artifacts.gd,
scripts/platform/composed_platform_provider.gd.

- [x] Inspect configured data-only directories, returning bounded diagnostics.
- [x] Adapt offline entitlements and return detached fixtures.
- [x] Encode build shares, validate replay packages and export verified PNGs.
- [x] Validate optional adapter results and expose OFFLINE_FALLBACK status.
- [x] Run all platform scenes GREEN and record exact logs/results in focused evidence.

```gdscript
var local: Dictionary = offline.perform(operation, request.duplicate(true))
if not local.ok:
    return local
var remote: Variant = optional.perform(operation, request.duplicate(true))
if not Rules.valid_response(operation, remote):
    local.status = "OFFLINE_FALLBACK"
    return local
```

### Task 4: Integration Handoff

File: docs/current/2026-10-05-p24-offline-platform-evidence.md.

- [x] Document configuration, all APIs, content bounds and adapter failure behavior.
- [x] Send exact owned file list and focused test results to the parent agent.
- [ ] Parent integrates in Main/Hub and commits the completed milestone.

### Task 5: Native Platform Panel

Files: scripts/platform/platform_service_coordinator.gd, platform_panel.gd,
assets/production/localization/platform.csv, tests/platform/platform_panel_test.gd/.tscn.

- [x] Write and run RED for physical Profile backup, display-name save, stale callbacks and controller navigation.
- [x] Implement coordinator commands with revision guards and scoped compressed backups.
- [x] Implement account/storage/community/content/sharing views using DungeonPanelView.
- [x] Run all platform scenes GREEN and retain native interaction evidence.
