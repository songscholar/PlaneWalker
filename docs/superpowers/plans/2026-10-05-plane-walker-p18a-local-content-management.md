# Plane Walker P18A Local Content Management Implementation Plan

- Status: Approved / Current
- Document Role: Current executable local content management implementation plan
- Authority Level: P18A specification subordinate execution plan
- Applies To: `scripts/expansion`, focused native tests and P18A evidence
- Owner: Project owner
- Depends On: `../specs/2026-10-05-plane-walker-p18a-local-content-management-design.md`
- Last Verified: 2026-10-05
- Exit Gate: Real Base plus optional localized packages install, survive physical restart and selection faults, reject unsafe inputs, and preserve physical Base/Mod saves with clean native logs

> **For agentic workers:** Execute the focused tasks below inline with the native test runner. Standing project authorization covers this implementation.

**Goal:** Provide safe offline directory package installation, complete candidate activation, DLC fixture discovery and isolated gameplay save domains.

**Architecture:** Capture and verify immutable directory packages; validate enabled candidates through fresh ContentRegistry instances; publish candidates only after auxiliary atomic SaveService retention. Use explicit offline entitlements and an injected native run lock.

**Tech Stack:** Godot 4 GDScript, Content Pack v2, SHA-256, native FileAccess/DirAccess and existing SaveService.

## Global Constraints

- No arbitrary GDScript, executable resources, scene loading or purchases from local packages.
- Base definitions, closed handlers and dependency contracts remain authoritative.
- Every gameplay Mod domain fits SavePathPolicy's 32-character ID limit and binds the complete ContentSnapshot.
- No edits to Main, Base Pack, localization CSV, Profile schema or root documentation index in this lane.

## Task 1: Native Contract And RED Gate

**Files:** `tests/integration/expansion/local_content_management_test.gd`, `.tscn`.

**Interfaces:** Construct `OfflineEntitlementProvider` and `ExpansionContentManager`; configure with physical test storage and real Base; assert `install`, `set_enabled`, `uninstall`, `discovery`, `activation_context` and `active_registry`.

- [x] Create native fixture writer for optional localized data-only items and exact pack hashes.
- [x] Assert owned/absent/malformed provider responses; pack source isolation; dependencies; run locks; executable resource refusal; physical restart and promotion failure.
- [x] Assert physical Base/Mod SaveService isolation and content mismatch refusal.
- [x] Run `./tools/run_tests.sh --filter local_content_management --timeout 45`; retain missing implementation RED logs.

## Task 2: Local Installer And Provider

**Files:** `scripts/expansion/data_only_pack_installer.gd`, `offline_entitlement_provider.gd`.

**Interfaces:** Installer `configure(root: String)`, `install(source_directory: String)`, `scan()`, `uninstall(fingerprint: String)` return `{ok, code, context}`. Provider `configure(entries: Array, owned_tags: Array)` and `snapshot()` return detached status and discovery.

- [x] Reject symbolic-link components and unsupported file kinds before reading payloads; enforce descriptor/file/total limits.
- [x] Capture descriptor plus only declared source bytes; compare each digest; write fingerprint-owned staging; validate descriptor again; rename to final directory.
- [x] Scan deterministic physical installations and preserve invalid-entry diagnostics; refuse duplicate pack identities at manager boundary.
- [x] Validate exact offline catalog/owned tags and return labelled local fixture discovery with purchase unsupported.
- [x] Run focused native gate and inspect actual Godot logs for errors/leaks.

## Task 3: Atomic Manager And Save Domain

**Files:** `scripts/expansion/expansion_content_manager.gd`, focused test extensions.

**Interfaces:** Public APIs and native callbacks are frozen by P18A specification. SaveService selection uses profile `selection`, domain `manager`, manager-owned protocol snapshot.

- [x] Configure Base first, discover installations, restore physical selected fingerprints and validate offline entitlement status.
- [x] Build fresh registry using Base plus exact requested local specs; reject any silently isolated requested pack.
- [x] Persist selected IDs/fingerprints before candidate registry publication; preserve prior state on failed writes.
- [x] Prevent all mutations while authoritative run lock is true or malformed; refuse enabled uninstall and conflicting same-ID installation.
- [x] Expose detached discovery/specs/content snapshot; derive deterministic Mod domain and verified eligibility.
- [x] Run focused tests, content registry/resolver regression and save-domain integration; scan logs and capture counts.

## Task 4: Evidence And Focused Commit

**Files:** `docs/current/2026-10-05-p18a-local-content-management-evidence.md`, this plan and specification.

- [x] Record RED/GREEN paths, physical restart/failure evidence and explicit native UI/external platform limits.
- [x] Review focused diff and governance metadata.
- [x] Stage exact P18A files and create reversible local commit; report API and index handoff to root.
