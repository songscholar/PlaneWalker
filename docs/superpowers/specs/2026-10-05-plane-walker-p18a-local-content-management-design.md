# Plane Walker P18A Local Content Management Design

- Status: Approved / Current
- Document Role: Current focused local content management specification
- Authority Level: Full Product completion specification subordinate implementation boundary
- Applies To: Local data-only Mods, DLC discovery fixtures, candidate activation and save isolation
- Implementation Status: Local installer, entitlement provider, candidate activation and physical save isolation verified; native Hub integration separate
- Owner: Project owner
- Depends On: `AGENTS.md`, Full Product completion specification, Content Pack v2 and SaveService
- Last Verified: 2026-10-05
- Approval Basis: Standing Project Authorization in `AGENTS.md`

## Scope And Authority

`ContentPackDescriptor`, `ContentPackResolver` and a fresh `ContentRegistry`
remain the only pack, dependency and definition validators. A local manager
installs immutable, hash-verified directory packages and persists an enabled
selection using the existing atomic `SaveService` in its own management root.
The actual base game Profile and Settings are never written by this service.
Pack purchase, remote publication and arbitrary executable Mods are excluded.

## Interfaces

`OfflineEntitlementProvider.configure(entries: Array, owned_tags: Array)`
validates explicit development fixture discovery. `snapshot()` returns detached
`status`, `owned_tags`, `entries` and `supports_purchase: false`. Entries have
exact fields `pack_id`, `entitlement_tag`, `name_key`, `description_key` and
`local_source_path`. Ownership is labelled `LOCAL_FIXTURE` and is never represented
as storefront verification.

`ExpansionContentManager.configure(storage_root: String, base_specs: Array,
game_version: String, execution_mode: StringName, entitlement_provider: Callable,
run_lock: Callable)` requires an authoritative run-lock callback. The callback
returns a Boolean; missing, invalid or non-Boolean callbacks refuse mutation.
An active run prevents installation, uninstall and enable-set changes.

Commands return detached `{ok, code, context}` dictionaries:

- `install(source_directory: String)` copies `pack.json` plus its declared files
  into a manager-owned staging directory, revalidates captured bytes and promotes
  the directory by rename. Existing identical installation is idempotent. Another
  fingerprint with the same pack ID requires explicit disable/uninstall first.
- `set_enabled(pack_ids: Array)` validates the whole requested candidate through
  a fresh registry and requires every requested pack to appear in actual active
  descriptors. Optional isolation is a command failure, never silent success.
- `uninstall(pack_id: String)` refuses enabled packs and preserves their dependants.
- `discovery()` reports actual installed identity, status, ownership, dependency
  metadata, enabled IDs, offline DLC discovery and validation diagnostics.
- `refresh()` rechecks physical installations and provider discovery while idle,
  preserving retained intent and isolating missing, changed or unowned optional
  packages and their dependants. Successful recovery restores the same selected
  fingerprints; it never silently accepts another package version.
- `activation_context()` returns actual pack specs, content snapshot, save domain,
  verified-play eligibility and the selected activation order. The native assembly
  must consume these specs through `ContentRegistry`; the manager does not mutate
  a live Player, Host or Profile.
- `active_registry()` returns the last fully validated candidate registry for
  native assembly only. UI uses detached discovery and activation state.

## Installation Safety

Input is a local directory using frozen Content Pack v2. The installer captures
only declared files; undeclared files are not copied or activated. Every traversed
path component is checked for symbolic links. Content sources must be JSON,
localization CSV, and assets must be JSON, PNG, OGG or WAV. Scenes, resources,
scripts, native libraries, SVG and executable paths are unsupported in this
data-only boundary. JSON assets may contain only primitive declarative data and
cannot declare script/callable/expression/resource loading fields or executable
resource path values. Registry validation applies the existing closed handler
and schema policies to every content source.

Limits: at most 256 declared files, 16 MiB per file, 64 MiB total, and a 256 KiB
descriptor. Installed destination names are full descriptor SHA-256 fingerprints.
The descriptor fingerprint and each file digest are rechecked after staging.
Candidate registry validation reads the captured staging directory; promotion
occurs only after this full validation. `prepare`, `commit_prepared` and
`discard_prepared` are the explicit installer transaction boundary.
Failed staging is removed only within the known manager-owned staging directory.

## Persistence And Offline Behavior

The manager selection payload contains schema 1, exact installed fingerprints and
sorted enabled IDs. An immutable management protocol snapshot binds the auxiliary
SaveService envelope independently of changing game content. Physical SaveService
recovery, integrity and atomic promotion semantics apply unchanged. A failed
selection write does not publish an in-memory candidate.

On restart, persisted installations and selected fingerprints are checked against
physical disk. Missing, corrupted, incompatible, unowned or dependency-invalid
optional content is isolated with diagnostics; base activation remains available.
Persisted intent is retained until an explicit successful selection command.
Provider absence or malformed responses produce `OFFLINE_UNAVAILABLE` and no
tagged entitlements. Empty-tag content always remains eligible.

When any local pack is active, gameplay save domain is `mod_` plus the first 28
hexadecimal characters of the complete active snapshot digest, fitting the frozen
32-character SavePathPolicy limit. The full snapshot remains in SaveEnvelope and
prevents hash-prefix collisions from reopening incompatible data. Zero local packs
use `base`. Local packages disable ranked/verified submission regardless of tag.

## Executable Completion Criteria

1. Real Base plus a localized optional item installs and activates through the
   registry; copied bytes remain usable after the source changes or disappears.
2. Traversal, symlink, script/scene/resource assets, executable JSON, bad digest,
   duplicate pack IDs, unknown content handlers and undeclared bytes cannot activate.
3. Dependencies require exact full candidate validity. Removing a required enabled
   dependency fails atomically; disabled uninstall is safe and deterministic.
4. Actual run lock blocks every mutation without file, selected-state or registry
   drift; malformed lock values fail closed.
5. Selection survives physical manager restart. Injected SaveService promotion
   failure leaves prior registry and durable selection coherent.
6. Local fixture entitlement enables owned tagged content; missing or invalid
   provider retains functional Base and clear offline discovery.
7. Different active fingerprints produce different isolated domains; a physical
   save in a Mod domain leaves Base bytes unchanged, and incompatible snapshots
   refuse reopening through SaveService.
8. Focused native tests pass without script errors or leaks; docs name remaining
   native management UI, packaging and external storefront gates explicitly.

## Retention Boundary

P18A certifies a local domain/provider and physical integration boundary. It does
not certify player-facing Main management UI, arbitrary Mod compatibility with
every fixed Launch pool, storefront ownership, DLC authored campaigns, cosmetics,
challenge modes, or full product release. Main integration and content-package
presentation are separate milestones.
