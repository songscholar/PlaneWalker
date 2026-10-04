# Plane Walker Save Service v3 Contract

- Status: Approved / Current
- Document Role: Current contract
- Authority Level: Atomic persistence, migration, recovery, active-run validation, and compatibility contract
- Applies To: Local profile saves, global settings, RunState/FloorPlan snapshots, migration, recovery, and content-pack compatibility
- Owner: Project integration lead
- Depends On: AGENTS.md, docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md
- Last Verified: 2026-10-04
- Schema version: 3

## 1. Guarantees

SaveService remains the sole writer for profile and settings documents. Version 3 preserves the temp write, integrity verification, backup rotation, forward-version refusal, ordered migration, corruption recovery, profile isolation, content-pack fingerprint, deterministic fixtures, and fail-closed content compatibility guarantees from v1 and v2.

All writes use canonical JSON and a SHA-256 digest over the complete envelope without its integrity member. The digest detects accidental corruption; it is not a ranked anti-cheat signature. A schema-4-or-later document returns FORWARD_VERSION before backup recovery and is never downgraded.

## 2. Native v3 profile payload

Every newly created native v3 profile payload contains `active_item_state`, `reward_effect_state`, and `active_run_state`. `{}` is the only no-active-run sentinel. A non-empty active run created under current content is the complete RunState snapshot, including the exact eight P14 domains: `current_floor_index`, `floor_plan`, `completed_floor_ids`, `run_economy`, `seen_event_ids`, `dungeon_event_runtime`, `merchant_state`, and `floor_rule_state`.

An empty event runtime is legal only before event resource and health authorities are initialized and while `seen_event_ids` is empty. Clearing both the runtime and the seen-event projection cannot erase an initialized event domain. Full runtime snapshots reconstruct every participant and cross-check resources, health, economy, route, BuildState curses, narrative flags, temporary modifiers, and the seen projection before restore.

An initialized event runtime must retain an assignment for every cleared event node on the current FloorPlan. Only intermediate nodes of an authored `route_skip`, backed by completed route and consequence transactions, may omit assignments. The landing room is entered normally and requires its own event history when cleared. Replacing a completed event with a freshly initialized, otherwise restorable runtime cannot erase that history.

The v3 JSON Schemas are normative for the envelope, closed RunState/FloorPlan roots, primitive and container boundaries, and top-level payload requirements. Nested active-item, reward, economy, dungeon-event, merchant, and floor-rule objects are intentionally opaque-but-runtime-validated. SaveEnvelope, ActiveItemRuntime, ReplayRecorder, RunState, DungeonEventRuntime, and FloorPlan remain authoritative for closed-field, type, range, state-prefix, authored-content identity, authenticated publication, and restore validation.

Identifier domains are explicit rather than interchangeable. Content stable IDs begin with a lowercase ASCII letter or digit and then allow lowercase ASCII letters, digits, underscore, hyphen, or period up to 96 characters. FloorPlan route IDs use the FloorPlan-compatible lowercase ASCII letter, digit, underscore, hyphen, or period alphabet at any position, also up to 96 characters. Consumed draft offers use a separate composite offer ID boundary up to 192 characters and additionally allow colon separators, matching DraftService's `<run-id>:room-<nn>:<category>:<revision>` production format. Profile IDs, save domains, and pack IDs remain path-safe and do not inherit route or offer punctuation.

JSON runtime numbers are restored according to their schema: persisted counters use their declared integer fields, while reward-definition `effects` use the authoritative EffectHandlerCatalog descriptors. Integer talent effects such as `talent_wayfarer_energy_restore` recover their integer type; numeric multipliers and thresholds remain floats even when their value is whole. Unknown or invalid effect dictionaries retain their serialized values for the domain validator to reject, rather than being silently discarded or broadly coerced.

Native Player binding before the first reward stores `resources.player_reward_run_start_baseline`, validated by the complete Player reward-effect contract. It is immutable within the run, survives event resource updates, and restores before merchant services reconstruct the reward ledger. A newly created Player with already acquired rewards cannot serve as the original baseline. Merchant reward-mutation snapshots must agree with the stored baseline. Historical saves without the optional field remain readable; no missing baseline is fabricated from an already rewarded Player. Non-native test participants retain their established in-memory baseline and do not create native persisted baseline records.

### Event temporary-effect lifetime

`RunState.events` retains successful room completion facts with the closed fields `type`, `sequence`, `floor_id`, `floor_index`, and `node_id`. The type is `room_completed_v1`; sequences start at one and increase without gaps. A floor/node pair appears once, floors never move backwards, and future-floor facts reject. Facts on the current floor must refer to actual visited, cleared nodes in route order. Earlier-floor facts retain shape and ordered-floor validation; this v3 boundary does not reconstruct the historical routes.

The granting event room does not consume the effect's duration. Each subsequent successful clear consumes one room, including clears on later floors. Expired effects remain in the consequence history but disappear from the Player's derived attack, mitigation, and energy-regeneration layer. That layer never rewrites permanent item or reward state. Refreshing an existing modifier uses the new source transaction and duration; retrying a consumed transaction cannot refresh it.

Historical dismissed-event saves without a source-room fact receive one retained `modifier_lifetime_baseline_v1` record with `source_transaction_id` and `after_room_sequence`. Elapsed rooms absent from those historical bytes cannot be recovered; the first restoration bounds future duration from that baseline. Repeated saves and loads keep the baseline. A real source-room fact takes precedence. Invalid, duplicate, or unauthored sources reject. The granting event may be dismissed before its clear fact is committed, so that intermediate production state remains valid.

Dungeon Replay schema 3 now binds the complete event history through `room_completion_events_digest`. Capture and validation check current-floor route correspondence. Changing the history rejects with `ROOM_COMPLETION_HISTORY_DRIFT`; removing the capability while retaining history rejects with `ROOM_COMPLETION_HISTORY_MISSING`. Historical seals without the field remain readable only with an empty history. This checkpoint seal does not by itself implement gameplay playback or seeking.

## 3. FloorPlan persistence boundary

M1, CURRENT, and NEXT runs must keep all eight P14 fields at their exact empty defaults and cannot persist a FloorPlan. LAUNCH and EXPANSION may persist an empty plan only before `start_floor`, when `current_floor_index == -1` and `completed_floor_ids` is empty.

A non-empty plan must use `floor_plan_v1`, match the run seed and current floor index, name the authoritative ordered floor ID, contain closed node/edge/state arrays, and preserve the exact completed-floor prefix. Its lowercase SHA-256 `generation_digest` must equal `FloorPlan.compute_generation_digest(plan)`. Envelope integrity cannot conceal generation_digest drift, route-prefix corruption, duplicate stable IDs, malformed economy/event/merchant/floor-rule containers, or FloorPlan structural drift.

The top-level content-pack fingerprint remains the authority for floor/template content bytes. SaveEnvelope validates the generic persisted FloorPlan boundary without loading content packs; SaveService separately returns CONTENT_MISMATCH when the stored content snapshot differs from the configured snapshot.

## 4. Ordered migration

The registered 2-to-3 migration advances settings by version only. Profiles without `active_run_state` receive `{}`. Empty active-run state remains empty. Non-Launch active runs receive the exact eight empty P14 defaults without inventing a FloorPlan. A complete LAUNCH or EXPANSION v2 active run with an authenticated FloorPlan receives an empty `dungeon_event_runtime` only when its legacy `seen_event_ids` projection is empty. If that projection already records events, migration preserves the historical v3 shape without `dungeon_event_runtime`; it never invents an assignment, outcome, pending continuation, receipt, or publication fact. This compatibility shape is read-only: every newly created Launch or Expansion v3 active run must include the complete event-runtime field.

An active LAUNCH or EXPANSION v2 run without a non-empty FloorPlan cannot be reconstructed deterministically. Migration returns the public `MIGRATION_UNSAFE_ACTIVE_RUN` code, requires a player-facing recovery notice, preserves the original bytes, and does not quarantine or fall back to an older backup. Complete active runs with a FloorPlan continue through v3 boundary validation. Migration is deterministic, input-immutable, adjacent, and ordered from v0 through v3.

## 5. Validation order and content compatibility

SaveService validates a profile in this order:

1. parse the document and validate the closed envelope boundary;
2. verify the envelope SHA-256 integrity digest;
3. compare the authenticated stored content snapshot with the configured content snapshot;
4. only after content compatibility succeeds, reconstruct and validate content-dependent active-item, reward, economy, dungeon-event, merchant, floor-rule, and FloorPlan runtime authorities.

An authentic save from different content returns `CONTENT_MISMATCH` before current Base Pack definitions are used to interpret its event assignments or runtime fingerprint. It is not quarantined, replaced by a backup, or rewritten. A malformed document or invalid integrity digest remains corruption and may use the normal recovery chain. Direct `SaveEnvelope.validate()` remains a complete strict validation entry point; `SaveService` uses the boundary-only entry point solely to enforce the ordered content-compatibility decision.

## 6. Recovery metadata and compatibility

Recovery order remains primary, pending, backup 1, then backup 2. Only corruption enters that recovery path. FORWARD_VERSION, CONTENT_MISMATCH, MIGRATION_UNAVAILABLE, MIGRATION_FAILED, and MIGRATION_UNSAFE_ACTIVE_RUN remain fail-closed refusals and do not silently replace the primary with an older save.

The v1 and v2 schemas, fixtures, and contracts remain historical migration authorities. `tests/fixtures/save/profile_v3.json` is the current deterministic native profile fixture; `forward_v4.json` is the forward-version refusal fixture. `save_profile_v3.schema.json` and `save_settings_v3.schema.json` are normative for the current envelope, while GDScript runtime validators are normative for opaque nested runtime payloads and cross-field state invariants.
