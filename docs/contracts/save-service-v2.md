# Plane Walker Save Service v2 Contract

- Status: Approved / Current
- Document Role: Current contract
- Authority Level: Atomic persistence, migration, recovery, and compatibility contract
- Applies To: Local profile saves, global settings, migration, recovery, and content-pack compatibility
- Owner: Project integration lead
- Depends On: AGENTS.md, docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md
- Last Verified: 2026-10-01
- Schema version: 2

## 1. Guarantees

SaveService is the sole writer for profile and settings documents. Version 2 preserves the v1 requirements for temp write, integrity verification, backup rotation, forward-version refusal, ordered migration, corruption recovery, profile isolation, content-pack fingerprint binding, and deterministic fixtures.

All writes use canonical JSON and a SHA-256 digest over the complete envelope without its integrity member. The digest detects accidental corruption; it is not a ranked anti-cheat signature.

## 2. Native v2 profile payload

Every native v2 profile payload contains active_item_state and reward_effect_state. A fresh active-item state is the explicit unconfigured schema-1 state. A fresh reward-effect state is an empty dictionary. A non-empty reward-effect state must contain all validated runtime domains; partial or unknown fields are corruption. Settings never receive profile runtime fields.

The v2 JSON Schemas are normative for the envelope, top-level payload requirements, and the presence of the five reward runtime domains. Nested active-item and reward runtime objects are intentionally opaque-but-runtime-validated: the schemas preserve their object boundary, while SaveEnvelope, ActiveItemRuntime, ReplayRecorder, and the concrete weapon runtimes apply the authoritative closed-field, type, range, and restore validation. Schema acceptance alone never authorizes a nested runtime payload.

## 3. Ordered migration

The registered 1 to 2 migration adds the explicit fresh runtime defaults only when a v1 profile omitted them. Existing runtime fields must already be valid and are preserved exactly. Settings advance to schema 2 without profile defaults. Migrated documents are resealed and atomically rewritten before load succeeds.

## 4. Recovery metadata

Recovery order remains primary, pending, backup 1, then backup 2. A migrated recovery candidate is repaired through the normal atomic write path. A successful RECOVERED result preserves migrated_from and migrated_to along with source kind, diagnostics, sequence, and the player-notice requirement.

## 5. Compatibility and completion

Schema 3 and later return FORWARD_VERSION and never fall back to an older backup. Schema 0 and v1 fixtures remain historical migration inputs. The authoritative native fixture is tests/fixtures/save/profile_v2.json. The current save_profile_v2.schema.json and save_settings_v2.schema.json files are normative for the envelope and required top-level domains; GDScript runtime validators are normative for opaque nested runtime payloads.
