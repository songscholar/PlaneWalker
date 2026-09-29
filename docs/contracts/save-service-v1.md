# Plane Walker Save Service v1 Contract

- Status: Approved implementation contract for P2
- Schema version: `1`
- Applies to: local profile saves, global settings, migration, recovery, and later content-pack compatibility
- Authority: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md` section 7.3 and P2 exit gate
- Last verified: 2026-09-28

## 1. Purpose and trust boundary

SaveService is the only infrastructure component allowed to create, replace, rotate, recover, or reset persistent save documents. Gameplay and UI provide validated dictionary snapshots; they do not open save files directly.

Version 1 guarantees **temp write**, **integrity verification**, **backup rotation**, **forward-version refusal**, **ordered migration**, **corruption recovery**, **profile isolation**, **content-pack fingerprint** binding, and **deterministic fixtures**.

The SHA-256 digest detects accidental corruption and inconsistent writes. It is not proof against a player who controls the local machine and can recompute an unkeyed digest. Ranked trust must later use replay/state verification and provider-backed attestation rather than an embedded client secret.

## 2. Documents and paths

Two document kinds exist:

- `profile`: slot-scoped progression and resumable game state. It is bound to a content snapshot.
- `settings`: global user preferences shared by all profiles. It is not bound to gameplay content.

Normative layout:

```text
user://plane_walker/save/
├── profiles/<profile_id>/<save_domain>/
│   ├── primary.json
│   ├── pending.tmp
│   ├── backup_1.json
│   ├── backup_2.json
│   └── quarantine/
└── global/settings/
    ├── primary.json
    ├── pending.tmp
    ├── backup_1.json
    ├── backup_2.json
    └── quarantine/
```

`profile_id` and `save_domain` must match `^[a-z0-9][a-z0-9_-]{0,31}$`. Separators, dots, absolute paths, and traversal segments are rejected before any filesystem call. The default domain is `base`; future Mod operation uses a separate domain and never overwrites the base profile.

Global settings are deliberately outside profile directories. Recovering or resetting one profile must not roll back language, audio, input, or accessibility preferences.

## 3. Profile envelope

A profile document contains exactly these top-level fields:

```json
{
  "magic": "PWSAVE",
  "schema_version": 1,
  "document_kind": "profile",
  "profile_id": "slot_1",
  "save_domain": "base",
  "sequence": 12,
  "game_version": "0.4.0-dev",
  "created_at_utc": "2026-09-28T08:00:00Z",
  "saved_at_utc": "2026-09-28T09:00:00Z",
  "content_snapshot": {
    "aggregate_sha256": "<64 lowercase hex characters>",
    "packs": []
  },
  "payload": {},
  "integrity": {
    "algorithm": "sha256",
    "digest": "<64 lowercase hex characters>"
  }
}
```

`sequence` is monotonically increased after each committed save. `created_at_utc` remains stable for the lifetime of the profile. The content snapshot is a stable, sorted representation of every active pack and contains `pack_id`, `pack_version`, `schema_version`, and `fingerprint_sha256`.

The aggregate content fingerprint is SHA-256 over canonical JSON `{ "packs": sorted_packs }`. Packs are sorted by ID, version, schema version, then fingerprint, so input discovery order cannot alter the result.

## 4. Settings envelope

Settings use the same magic, schema, sequence, version, timestamps, payload, and integrity fields. `document_kind` is `settings`. A settings document has no `profile_id`, `save_domain`, or `content_snapshot`.

The version 1 payload contains the current runtime preferences:

- `locale`
- `master_volume`
- `master_muted`
- `camera_shake_enabled`
- `hit_flash_enabled`
- `reduced_motion`

Migration fills missing values from approved defaults before schema validation.

## 5. Canonical JSON and integrity

Canonical serialization is `JSON.stringify(value, "", true, true)`: no indentation, sorted dictionary keys, and full-precision floats. UTF-8 bytes are hashed.

To calculate document integrity:

1. Deep-copy the complete envelope.
2. Remove the top-level `integrity` field.
3. Canonically serialize the remaining dictionary.
4. Calculate lowercase SHA-256 hex.
5. Store `{ "algorithm": "sha256", "digest": result }`.

Integrity covers headers, timestamps, content snapshot, and payload. Unknown algorithms, missing fields, malformed hex, or mismatched digests are corruption.

## 6. Atomic write protocol

Only one write transaction may run at a time. A second request returns `BUSY` without touching disk.

The required transaction is:

1. Validate identifiers, payload, schema, and content snapshot in memory.
2. Build a new envelope and write canonical bytes to `pending.tmp` in the same directory as `primary.json`.
3. Flush and close the temp file.
4. Reopen `pending.tmp`; parse it and repeat schema and integrity verification.
5. Copy the current valid `backup_1` through a verified staging file into `backup_2`.
6. Copy the current valid primary through a verified staging file into `backup_1`.
7. Replace primary by renaming the verified temp file. Primary must never be deleted before this rename.
8. Reopen primary and require its digest to match the transaction envelope before reporting success.

A failure before step 7 leaves the old primary readable. A failure after step 7 may leave changed backups, but primary is either the old complete file or the new complete file. Only a verified primary participates in normal backup rotation; corrupt bytes go to quarantine instead.

## 7. Load, refusal, and corruption recovery

Candidate evaluation order is primary, pending temp, backup 1, then backup 2, but recovery candidates are consulted only after primary is proven corrupt.

The following conditions are not corruption and must not trigger backup rollback:

- A structurally valid primary with `schema_version` greater than the supported version returns `FORWARD_VERSION`.
- A structurally valid primary whose content snapshot is incompatible with the active pack set returns `CONTENT_MISMATCH`.
- A lower schema with no complete migration chain returns `MIGRATION_UNAVAILABLE`.

For actual corruption:

1. Preserve the exact source bytes in `quarantine/` with candidate kind, reason, and deterministic sequence in the filename.
2. Validate each recovery candidate completely, including magic, document kind, profile/domain, schema, digest, and content snapshot.
3. Select the first valid compatible candidate.
4. Restore it through the atomic write protocol rather than copying over primary directly.
5. Return `RECOVERED` with source and diagnostics so the UI can notify the player.

If no candidate is usable, return `CORRUPT`. The caller may operate with in-memory defaults, but neither caller nor service may overwrite the damaged files automatically. Reset is a separate explicit operation.

## 8. Schema versions and ordered migration

The historical `user://plane_walker_save.json` format is schema `0`, even though it contains the legacy field `"version": 1`. It has no `PWSAVE` envelope and must never be mistaken for schema 1.

Migrations are registered as exact adjacent steps, such as `0 -> 1`. Each step:

- receives a deep copy and returns a new dictionary;
- must set the expected next `schema_version`;
- performs no file I/O, clock reads, random calls, or Autoload mutation;
- preserves unknown data only in an explicitly supported extension namespace;
- is deterministic for identical input.

Missing steps, duplicate starting versions, non-adjacent registration, exceptions, non-dictionary output, or an incorrect output version return a migration failure without modifying the source file.

Migration of schema 0 separates legacy `persistent.settings` into the global settings document. All other persistent fields become the profile payload. A successful migrated profile is committed atomically, retaining the legacy source as a recoverable backup or diagnostic copy.

## 9. Result contract

Save operations return a structured result with `ok`, `code`, deep-copied payload/metadata, diagnostics, source kind, migration versions, and whether player notice is required.

Required codes are:

```text
OK, NOT_FOUND, RECOVERED, INVALID_ARGUMENT, IO_ERROR, CORRUPT,
FORWARD_VERSION, MIGRATION_UNAVAILABLE, MIGRATION_FAILED,
CONTENT_MISMATCH, BUSY
```

`RECOVERED` is successful but requires a player notice. `NOT_FOUND` is not corruption. Callers choose defaults without creating a file until an explicit save occurs.

## 10. Deterministic fixtures and P2 exit gate

Committed deterministic fixtures use fixed timestamps, sequences, versions, pack hashes, payloads, and expected digests. They include:

- historical schema 0 input;
- valid schema 1 profile and migration output;
- future schema refusal;
- truncated, bad-header, and bad-integrity corruption;
- equivalent pack sets in different orders;
- a changed pack set with a different aggregate fingerprint.

Tests inject their root path, clock, and fault points. They never share the production `user://` root or a fixed cross-process `/tmp` filename.

P2 is complete only when destructive fixtures prove atomic replacement, two-generation backup rotation, recovery, quarantine preservation, forward refusal, ordered deterministic migration, profile/domain isolation, global settings isolation, and content-pack mismatch behavior. Exit code zero alone is insufficient; Godot logs must also contain no script errors, invalid calls, missing resources, or new object leaks.
