# Plane Walker Save Service v3 Contract

- Status: Approved / Current
- Document Role: Current contract
- Authority Level: Atomic persistence, migration, recovery, active-run validation, and compatibility contract
- Applies To: Local profile saves, global settings, RunState/FloorPlan snapshots, migration, recovery, and content-pack compatibility
- Owner: Project integration lead
- Depends On: AGENTS.md, docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md
- Last Verified: 2026-10-01
- Schema version: 3

## 1. Guarantees

SaveService remains the sole writer for profile and settings documents. Version 3 preserves the temp write, integrity verification, backup rotation, forward-version refusal, ordered migration, corruption recovery, profile isolation, content-pack fingerprint, deterministic fixtures, and fail-closed content compatibility guarantees from v1 and v2.

All writes use canonical JSON and a SHA-256 digest over the complete envelope without its integrity member. The digest detects accidental corruption; it is not a ranked anti-cheat signature. A schema-4-or-later document returns FORWARD_VERSION before backup recovery and is never downgraded.

## 2. Native v3 profile payload

Every native v3 profile payload contains `active_item_state`, `reward_effect_state`, and `active_run_state`. `{}` is the only no-active-run sentinel. A non-empty `active_run_state` is the complete RunState snapshot, including the exact seven P14 domains: `current_floor_index`, `floor_plan`, `completed_floor_ids`, `run_economy`, `seen_event_ids`, `merchant_state`, and `floor_rule_state`.

The v3 JSON Schemas are normative for the envelope, closed RunState/FloorPlan roots, primitive and container boundaries, and top-level payload requirements. Nested active-item, reward, economy, merchant, and floor-rule objects are intentionally opaque-but-runtime-validated. SaveEnvelope, ActiveItemRuntime, ReplayRecorder, RunState, and FloorPlan remain authoritative for closed-field, type, range, state-prefix, and restore validation.

Identifier domains are explicit rather than interchangeable. Content stable IDs begin with a lowercase ASCII letter or digit and then allow lowercase ASCII letters, digits, underscore, hyphen, or period up to 96 characters. FloorPlan route IDs use the FloorPlan-compatible lowercase ASCII letter, digit, underscore, hyphen, or period alphabet at any position, also up to 96 characters. Consumed draft offers use a separate composite offer ID boundary up to 192 characters and additionally allow colon separators, matching DraftService's `<run-id>:room-<nn>:<category>:<revision>` production format. Profile IDs, save domains, and pack IDs remain path-safe and do not inherit route or offer punctuation.

## 3. FloorPlan persistence boundary

M1, CURRENT, and NEXT runs must keep all seven P14 fields at their exact empty defaults and cannot persist a FloorPlan. LAUNCH and EXPANSION may persist an empty plan only before `start_floor`, when `current_floor_index == -1` and `completed_floor_ids` is empty.

A non-empty plan must use `floor_plan_v1`, match the run seed and current floor index, name the authoritative ordered floor ID, contain closed node/edge/state arrays, and preserve the exact completed-floor prefix. Its lowercase SHA-256 `generation_digest` must equal `FloorPlan.compute_generation_digest(plan)`. Envelope integrity cannot conceal generation_digest drift, route-prefix corruption, duplicate stable IDs, malformed economy/event/merchant/floor-rule containers, or FloorPlan structural drift.

The top-level content-pack fingerprint remains the authority for floor/template content bytes. SaveEnvelope validates the generic persisted FloorPlan boundary without loading content packs; SaveService separately returns CONTENT_MISMATCH when the stored content snapshot differs from the configured snapshot.

## 4. Ordered migration

The registered 2-to-3 migration advances settings by version only. Profiles without `active_run_state` receive `{}`. Empty active-run state remains empty. Non-Launch active runs receive the exact seven empty P14 defaults without inventing a FloorPlan.

An active LAUNCH or EXPANSION v2 run without a non-empty FloorPlan cannot be reconstructed deterministically. Migration returns the public `MIGRATION_UNSAFE_ACTIVE_RUN` code, requires a player-facing recovery notice, preserves the original bytes, and does not quarantine or fall back to an older backup. Complete active runs with a FloorPlan continue through v3 boundary validation. Migration is deterministic, input-immutable, adjacent, and ordered from v0 through v3.

## 5. Recovery metadata and compatibility

Recovery order remains primary, pending, backup 1, then backup 2. Only corruption enters that recovery path. FORWARD_VERSION, CONTENT_MISMATCH, MIGRATION_UNAVAILABLE, MIGRATION_FAILED, and MIGRATION_UNSAFE_ACTIVE_RUN remain fail-closed refusals and do not silently replace the primary with an older save.

The v1 and v2 schemas, fixtures, and contracts remain historical migration authorities. `tests/fixtures/save/profile_v3.json` is the current deterministic native profile fixture; `forward_v4.json` is the forward-version refusal fixture. `save_profile_v3.schema.json` and `save_settings_v3.schema.json` are normative for the current envelope, while GDScript runtime validators are normative for opaque nested runtime payloads and cross-field state invariants.
