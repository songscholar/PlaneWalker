# Plane Walker P20A Native Build Sharing Design

- Status: Approved / Current
- Document Role: Current build sharing specification
- Authority Level: Full Product implementation boundary
- Applies To: Offline portable loadouts, strict import and native meditation controls
- Owner: Project owner
- Depends On: `AGENTS.md`, BuildLibrary and HubRuntimeFacade
- Last Verified: 2026-10-05
- Approval Basis: Standing Project Authorization in `AGENTS.md`

## Portable Format

`BuildShareCodec.encode(build: Dictionary)` returns `{ok, code, context}` with
`context.share_code`. The build has the five exact BuildLibrary fields. The
portable payload has `schema_version: 1`, `name`, `character_id`, `weapon_id`,
and sorted `time_abilities`. Sender IDs, progress, currency, entitlements and
executable data cannot appear. The envelope is `PW1.<base64 UTF-8 JSON>.<SHA256>`.
Its SHA-256 detects transcription errors; it is not identity authentication.
The complete text is at most 1024 characters. Decode requires canonical base64,
canonical JSON, the exact schema and known five-character/five-weapon/four-time
IDs. Names use the existing 64-character, nonempty, no-NUL limit.

`decode(code: Variant)` returns a detached BuildLibrary build with deterministic
`share-<first 32 checksum hex>` identity. Sorting the time pair makes export
deterministic and import idempotent. Noncanonical, oversized, corrupted, unknown,
duplicate-pair or extra-field payloads refuse without script errors.

## Native Commands

Meditation adds `build_export` with exact `{build_id}` and `build_import` with
exact `{command_id, share_code}`. The facade owns revision/epoch checks. Export
resolves the sender's current owned build. Import passes the decoded build to
the real `ProfileRuntimeService.execute` as `build_save`; unlocks, capacity,
reserved command IDs, atomic storage and rollback remain authoritative there.
An identical already imported build returns `NO_CHANGE` without writing.

Native controls show a selectable share-code field and explicit copy, paste and
import commands. Clipboard access occurs only from the user's button action.
Controller focus includes the new field/actions. A save failure retains entered
text and displays a localized error, allowing the same import to retry.

## Executable Completion Criteria

1. All 150 canonical loadouts round-trip, including Unicode names.
2. Equal builds with different sender IDs/time ordering export the same code.
3. Malformed/large/base64/JSON/schema/checksum/type inputs fail closed.
4. Native Hub export and import use actual Profile storage, survive restart,
   and never grant locked loadouts or mutate currency/progression.
5. Save failure preserves source text, library, revision and durable bytes.
6. Actual Main meditation controls, stale callbacks, controller focus and
   English/Chinese rendering pass focused tests with no runtime errors/leaks.
