# Plane Walker P18A Local Content Management Evidence

- Status: Implemented / Current
- Document Role: Current focused local content management evidence
- Authority Level: Below Full Product completion specification and P18A local management specification
- Applies To: Data-only package installation, offline entitlement discovery, candidate activation and gameplay save isolation
- Owner: Project owner
- Depends On: `../superpowers/specs/2026-10-05-plane-walker-p18a-local-content-management-design.md`
- Last Verified: 2026-10-05
- Implementation Status: Local domain/provider and physical integration tests verified; real Hub management entry remains separate

## Implemented Boundary

Three native modules provide a complete local package transaction boundary:

- `DataOnlyPackInstaller` captures bounded declared bytes, validates frozen v2
  descriptor fields and exact hashes, refuses executable file kinds and JSON
  paths, rejects symlinked sources, prepares immutable staging, and promotes
  fingerprint-addressed directories after candidate validation. Cleanup unlinks
  symbolic links rather than following their targets, including hidden files.
- `OfflineEntitlementProvider` validates explicit local discovery and owned tags,
  reports `LOCAL_FIXTURE`, returns detached snapshots, and exposes no purchase.
- `ExpansionContentManager` validates actual Base plus exact selected optional
  definitions through fresh ContentRegistry instances. Requested optional
  isolation is a failed command. Its management selection uses existing atomic
  SaveService retention in a dedicated root, separate from gameplay Profile and
  Settings. Publication follows successful retention.

Every mutation, including refresh, requires the injected native run lock to be
false. No caller-provided availability Boolean is accepted. Installation validates
the new package's complete required dependency closure and the currently active
set; an unrelated broken dormant dependency does not block installation.

On physical restart or idle refresh, exact persisted fingerprints, physical
integrity, game version, dependencies and entitlement ownership are checked.
Optional failures isolate affected packages/dependants while preserving Base and
retained user intent. Entitlement recovery restores the original selected content
identity. Missing/malformed providers report `OFFLINE_UNAVAILABLE`; untagged
content remains usable.

`activation_context()` includes real pack specs, complete ContentSnapshot, actual
activation order, `verified_play_eligible`, and `save_domain`. Local content uses
`mod_<28 hex>` within the frozen 32-character ID limit; complete snapshot validation
in SaveEnvelope prevents incompatible data from opening in the same scope. Local
packages disable verified/ranked submission. Zero local content returns `base`.

## Native Verification

Command: `./tools/run_tests.sh --filter local_content_management --timeout 45`.

Logs live under the platform test temporary root
`/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/`:

- `planewalker-tests.BXPwSM`: initial missing manager/provider RED.
- `planewalker-tests.RAIY4I`: prepared installation API RED.
- `planewalker-tests.F6a6Sw`: refresh/entitlement recovery API RED.
- `planewalker-tests.flmU4C`: broken dormant dependency blocks unrelated install RED.
- `planewalker-tests.Uzlas2`: final focused native scene GREEN, all assertions
  pass, zero script errors and zero leak warnings.

The actual scene covers localized optional item definitions registered against
real Base, deterministic dependency order, idempotent installation, detached
discovery, exact run-lock refusal, enabled uninstall refusal, source deletion,
physical manager restart, pre-primary-promotion failure and reopen recovery,
entitlement revocation/recovery, malformed/missing provider fallback, native
scene and executable JSON rejection, bad digest, unsupported content field,
actual filesystem symlink rejection, 16 MiB asset bound, immutable prepared
source capture, undeclared script omission, safe symlink cleanup, incompatible
game version, corrupt optional/dependant isolation and independent install
recovery. Physical Base and Mod SaveService writes demonstrate unchanged Base
bytes and complete snapshot mismatch refusal.

Targeted shared regressions:

- Content Registry: `planewalker-tests.cv7w1z`, 1/1 GREEN, clean logs.
- Save Service: `planewalker-tests.IguqY2`, 1/1 GREEN, clean logs.
- Pack contract and resolver: two GREEN scenes in `planewalker-tests.mydYbn`.
- The same broad `content_pack` filter also included actual Main export boot.
  Its assertions pass, but ObjectDB leak scanning fails that scene during parallel
  native Main/music/encounter work. This is recorded as a combined integration
  issue, not suppressed or counted as P18A GREEN; root owns investigation.
- `npm audit --offline --json` reports zero cached vulnerabilities across four
  existing dependencies. P18A introduces no dependencies or remote calls.

Godot line coverage is unavailable; no percentage is inferred from scene counts.

## Native Integration Contract

Configure `ExpansionContentManager` with its dedicated storage root, actual Base
specs, game version, execution mode, a provider snapshot callback and an
authoritative Host/Profile run-lock callback. Hub management calls `refresh()`
while idle, renders `discovery()`, and issues `install`, `set_enabled` and
`uninstall`. Gameplay assembly must consume the reported pack specs and full
snapshot through existing content/save services; this module does not mutate a
running Host, Player or Profile.

Use `active_registry()` only in native assembly. UI consumes detached state.
`set_selection_fault_injector()` exists for native retention tests and must not
be exposed as a player command. First-party directory packages use frozen v2;
scene/resource/script packages and generic ZIP imports are unsupported here.

## Retention Review

This focused milestone is reversible by reverting its commit after accounting
for subsequent Main integration. Existing Base Pack, frozen schemas, content
contracts and gameplay Profile bytes are unchanged by the implementation.

Real Hub management UI/controller flow, actual optional campaign/cosmetic/mode
content, all-Mod gameplay matrices, exported native management workflow and
storefront ownership remain later product gates. `LOCAL_FIXTURE` is development
ownership, not an external purchase claim. No remote publication occurred.
