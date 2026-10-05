# P24 Offline Platform Evidence

- Status: Verified backend and native panel; Main integration owned by parent
- Document Role: Current
- Authority Level: Milestone validation evidence under standing project authorization
- Applies To: Eight offline platform capabilities and native platform panel
- Owner: Plane Walker project owner
- Depends On: `../superpowers/specs/2026-10-05-p24-offline-platform-design.md`, `../superpowers/plans/2026-10-05-p24-offline-platform-plan.md`
- Last Verified: 2026-10-05

## Delivered

PlatformProvider defines all eight capabilities and returns detached structured
results: `{ok, code, context, status}`. OfflinePlatformProvider persists identity,
display name, achievement IDs, cloud cache, local rankings and presence through
SaveService. Storage binds profile, save domain and actual content snapshot;
all optional capabilities remain usable without network credentials.

PlatformStateStore reloads the physical primary before operations and uses
compare-exchange writes. Only the exact promoted primary reconciles a failed
write. JSON integer/float round trips use normalized canonical digests. Unknown
platform state versions, stale writers, invalid inputs and symlink scopes refuse.

PlatformLocalArtifacts inspects configured local data-only content through the
existing installer, adapts OfflineEntitlementProvider fixtures and exports real
build codes, verified PlayerReplayPackage and streamed whole-run JSON, and PNG
screenshots. Streamed packages use RunReplayStreamStore's pure package validator
before export, with no archive or Profile writes during validation. Export paths
derive from hashes under the owned platform directory. There is no purchase,
download, arbitrary script activation or caller-selected export destination.

ComposedPlatformProvider keeps local storage authoritative. Validated optional
identity, friends, presence and global/friend rankings may replace their views.
Other operations require an acknowledged response. Structured failures or
malformed successes retain the local result with OFFLINE_FALLBACK status.
Adapter implementations must return structured failures; Godot cannot catch
arbitrary script runtime faults in an injected adapter.

PlatformPanel provides account, storage, community, content and sharing views.
PlatformServiceCoordinator validates Profile scope and panel revision, then
creates bounded compressed Profile backups or exports them through share_cloud.
The panel uses DungeonPanelView focus scopes and epoch guards, supports keyboard
and controller input, and displays real empty offline friends/content states.
Both English and Simplified Chinese strings are in platform.csv.

## Integration API

```gdscript
var offline := preload("res://scripts/platform/offline_platform_provider.gd").new()
var configured := offline.configure(platform_root, game_version, binding, profile_id, save_domain)
offline.attach_local_records(local_records)
offline.configure_local_content(local_directories, entitlement_rows, owned_tags)
var provider := preload("res://scripts/platform/composed_platform_provider.gd").new()
provider.configure(offline) # The optional adapter is the second argument.
var panel := preload("res://scripts/platform/platform_panel.gd").new()
platform_layer.add_child(panel)
panel.configure(provider, profile_service)
panel.coordinator().attach_replay_library(replay_library)
panel.open()
```

Main owns the layer, Hub entry point, closed signal and service lifetime. The
panel exposes `open`, `is_open`, `handle_input`, `close_panel`, `closed`,
`select_section`, `submit_command`, `coordinator` and `set_screenshot_source`.
An injected screenshot source returns Image; native rendering can use the
viewport texture. Headless mode disables screenshot capture unless a source is
injected. Register both generated platform translations in project.godot.

Provider convenience methods: status, storage_identity, identity,
set_display_name, achievements, unlock_achievement, cloud_write, cloud_read,
cloud_list, cloud_remove, share_cloud, submit_score, leaderboard, friends,
presence, set_presence, discover_content, entitlements, share_build,
share_replay and capture_screenshot. Request and response bodies are documented
by the typed signatures and exact validators in scripts/platform.

## Validation

RED: build/platform-red recorded two missing-provider assertion failures.
build/platform-panel-red recorded the missing native-panel assertion failure.
build/platform-stream-red recorded refusal of authenticated streamed replay
packages before shared validation and routed export support were added.

GREEN command:

```sh
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot TEST_LOG_DIR=build/platform-stream-final-green tools/run_tests.sh --filter tests/platform/
```

Result: 4 scenes passed, 0 failed. Godot 4.6.1. All engine and stdout logs were
scanned for script/parse errors, leaks, orphan nodes and ERROR lines; no matches.
The runner reports actual line coverage unsupported by this Godot build.

- offline_platform_test: restart persistence, idempotent unlocks, all six Save
  fault points, cloud digest/conflict/path/object/byte limits, deterministic
  rankings, content/Mod isolation, presence, detached responses and competing
  primary promotion/retry without lost achievement IDs.
- platform_composition_test: absent/failing/malformed optional adapters,
  detached remote views, safe local discovery, fixture ownership, actual build
  files, decodable PNG dimensions and actual Player replay package export and
  decoder verification, with wrong-domain replay refusal.
- platform_panel_test: actual physical Profile source, native name-save button,
  stale button/revision refusal, cloud backup with verified payload digests,
  physical export, cold provider restart and controller navigation/cancel/reopen.
- platform_stream_share_test: storage-complete authenticated interrupted tape
  from an actual Player snapshot, physical export/import observation fidelity,
  malformed chunk and version refusal, and ReplayLibraryRouter export through
  the actual Profile-bound platform coordinator. This storage test does not
  assert a native room terminal or complete-run gameplay recording.

## Bounds and Retention

Maximum achievements: 256; cloud keys: 64; individual cloud JSON: 64 KiB;
platform state JSON: 1 MiB; local boards: 16; entries per synthetic board: 100.
Real settled Run rankings use the existing authenticated LocalRunRecords board.
Screenshots allow at most 4096 pixels per side and 4194304 total pixels.
Normal exports allow 16 MiB per file; whole-run replay packages allow 96 MiB,
with 256 MiB total and 100 files. Local discovery has
at most 64 configured sources. Compressed Profile source is bounded to 8 MiB;
its encoded cloud record must fit the 64 KiB cache contract. Oversize operations
return capacity failures without changing Profile or platform state.

The remaining external step is supplying a real platform SDK/transport and
credentials. Main/Hub integration, translation import and rendered resolution
QA are covered by the parent milestone. No local commit was made by this lane;
the parent owns focused staging and milestone retention.
