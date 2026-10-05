# P24 Offline Platform Design

- Status: Approved
- Document Role: Current
- Authority Level: Milestone design under standing project authorization
- Applies To: Offline platform capabilities and native Hub platform panel
- Owner: Plane Walker project owner
- Depends On: `../../../AGENTS.md`, `2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-10-05

## Decision

Use one PlatformProvider interface with a durable OfflinePlatformProvider and
an optional composed provider. The interface returns detached dictionaries
with ok, code, context and status. Local operations remain authoritative;
optional transport failures return OFFLINE_FALLBACK and preserve local results.
No network client, credentials, purchases or publication are included.

Direct SDK integration would require unavailable identities. A memory-only
stub would lose achievements and storage across launches. SaveService-backed
local state provides usable behavior and matches the project's save boundary.

## Behavior

- Identity is deterministic for profile/domain and supports a durable display name.
- Achievements unlock once, survive restart and fail without changing memory on
  uncommitted writes. A promoted primary reconciles an ambiguous write.
- Cloud storage is a bounded JSON local cache with explicit local authority,
  keyed reads/writes/removal and optional expected-digest conflict detection.
- Local leaderboard entries are content/domain/profile isolated, deterministic,
  idempotent by entry id and explicitly unranked. Existing authenticated
  LocalRunRecords can be attached as the runs board.
- Friends return an empty list; presence is local and bounded.
- Workshop discovery inspects configured local directories through
  DataOnlyPackInstaller. It reports invalid candidates without activating them.
- Entitlements reuse OfflineEntitlementProvider fixtures and forbid purchase.
- Build shares reuse BuildShareCodec. Replay shares validate PlayerReplayPackage
  or the authoritative streamed-run package validator against the active binding.
  Complete streamed tape exports have the store's 96 MiB package budget.
  Screenshot hooks export bounded PNG images.
- Export names derive from content hashes, with atomic verified promotion and
  rejection of symlinks. Callers cannot choose filesystem destinations.

## Contracts

PlatformProvider.perform(operation, request) exposes typed convenience methods
for every capability. Every request is validated before local mutation or
optional-provider forwarding. Optional providers implement the same interface
and return structured failures. Successful optional responses must pass the
operation's response validator; invalid responses fall back locally.

PlatformStateStore uses SaveService compare-exchange writes in the local domain,
with a storage id derived from profile, save domain and content snapshot.
Public responses, request forwarding and fixture configuration use deep copies.
Unknown versions and corrupt platform state fail closed.

## Executable Completion Criteria

tests/platform/offline_platform_test.tscn proves durable identity, idempotent
achievements, every SaveService fault point, competing writes, cloud conflicts,
bounded invalid inputs, local ranking isolation and defensive copies.

tests/platform/platform_composition_test.tscn proves missing/failing/malformed
optional providers return a usable offline result, safe data-only discovery,
entitlement snapshots, real build and PNG exports, and invalid replay refusal.

Both scenes run through tools/run_tests.sh with distinct log directories. Logs
must contain no script errors, resource leaks or orphan nodes. Main integration
is owned by the parent agent and does not alter gameplay/save authorities.

The native PlatformPanel uses DungeonPanelView focus and epoch contracts. Its
PlatformServiceCoordinator reads the authoritative Profile service, creates
compressed bounded local backups, exports them through the provider and guards
commands by current panel revision. Account, storage, community, content and
sharing sections expose real offline data with keyboard/controller navigation.
tests/platform/platform_panel_test.tscn proves physical backup and export,
display-name persistence, stale callbacks and controller close/reopen behavior.
