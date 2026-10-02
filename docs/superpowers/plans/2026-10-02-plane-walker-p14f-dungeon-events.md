# Plane Walker P14F Dungeon Events Implementation Plan

- Status: Active / Current
- Document Role: Current P14F implementation plan
- Authority Level: Executable P14F work breakdown under the approved P14 Five-Floor Dungeon Design
- Applies To: Fifteen regular events, three special events, exact operation contracts, deterministic selection, event state, atomic consequences, pending reward/combat continuations, UI-safe ViewState, Save/Replay, smoke testing, and certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`, `docs/superpowers/plans/2026-10-01-plane-walker-p14-five-floor-dungeon.md`, `docs/current/2026-10-02-p14e-launch-economy-merchants-evidence.md`, `docs/contracts/content-pack-v2.md`, `docs/contracts/save-service-v3.md`
- Last Verified: 2026-10-02
- Exit Gate: All eighteen events and every option execute through real handlers or exact authored requirement rejection; pending continuations, atomic rollback, Save/Replay, full smoke matrix, and complete repository validation pass

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all fifteen regular and three special Launch dungeon events as deterministic, atomic, Save/Replay-safe, UI-ready runtimes with real consequences and no identity-only handlers.

**Architecture:** FloorPlan event nodes remain deterministic event slots. Their generated `event_id` is the stable primary candidate; `DungeonEventSelector` evaluates the complete authored pool at room entry and `DungeonEventRunState.selected_event_by_node` freezes the actual assignment without rewriting the FloorPlan generation digest. A coordinator composes pure selection, strict event state, typed consequence participants, pending reward/combat continuations, one RunState state sink, exactly-once publication, and strict Save/Replay restoration.

**Tech Stack:** Godot 4.6.1 GDScript, JSON Schema Draft 2020-12, ContentRegistry v2, RunState/RunOrchestrator/RunRuntimeFacade, RunEconomyState, PlayerRewardEffectRuntime, FloorPlan, SaveEnvelope schema 3, RunDungeonReplaySeal schema 3, scene-based test runner, Python contract tests.

## Global Constraints

- Preserve the exact catalog of fifteen regular and three special events.
- Use `event_outcome_v1:<event_id>:<node_id>` as the isolated outcome channel.
- Event assignment, option choice, outcome, pending continuation, and completed transaction IDs survive Save/Replay without rerolling.
- One event transaction changes Player, BuildState, economy, FloorPlan, flags, modifiers, and encounter state only through one atomic RunState commit.
- Recoverable failures restore all participants byte-identically in reverse commit order; failed compensation enters a typed integrity terminal path.
- `hidden_until_commit` exposes no outcome key, reward ID, consequence argument, or resolved variant ID before commit.
- Combat and reward-draft events remain pending until their authenticated continuation completes.
- Formal M1 remains `M1 Candidate — External Validation Pending`; authentic external playtests remain `0 / 20`.

---

### Task 1: Close event data and operation contracts

**Files:**
- Modify: `data/schemas/dungeon_event_v1.schema.json`
- Modify: `data/content_packs/base/content/dungeon_events.json`
- Modify: `data/content_packs/base/pack.json`
- Modify: `scripts/dungeon/dungeon_event_definition.gd`
- Modify: `tests/contract/content_schema/p14_dungeon_content_contract_test.gd`
- Modify: `tests/contract/content_schema/test_p14_dungeon_schemas.py`
- Modify: `tests/contract/content_schema/content_pack_contract_test.gd`
- Modify: `tests/contract/content_schema/content_registry_test.gd`

**Interfaces:**
- Produces normalized options with `outcomes: Array[Dictionary]`; every outcome has `id`, `weight`, `outcome_key`, and `consequences`.

- [x] **Step 1: Write failing exact-argument tests**

Add table-driven missing-field, extra-field, wrong-type, and out-of-range cases for:

```text
resource_min(resource, amount)
health_min(amount)
health_max_ratio(ratio)
gold_min(amount)
has_reward_tag(tag)
lacks_curse(curse_id)
narrative_flag(flag, value)
floor_index_min(value)
resource_delta(resource, amount)
health_delta(amount, nonlethal)
reward_draft(pool_id, count)
curse_add(curse_id)
curse_remove(curse_id)
temporary_modifier(modifier_id, duration_rooms, magnitude)
map_reveal(depth)
encounter_start(encounter_id)
route_skip(rooms)
```

- [x] **Step 2: Run RED**

```bash
python3 -m unittest tests.contract.content_schema.test_p14_dungeon_schemas
./tools/run_tests.sh --filter p14_dungeon_content_contract
./tools/run_tests.sh --filter content_registry
```

- [x] **Step 3: Implement the closed schema, parser, references, and weighted outcomes**

Replace option-level outcome authority with stable `outcomes`, require positive weights, close every curse/reward-pool/modifier/resource/encounter reference, add real multi-variant authored outcomes where visibility is hidden, and refresh Base Pack hashes.

- [x] **Step 4: Run GREEN and commit `feat(events): close dungeon event contracts`**

**Completed:** `c2fea34 feat(events): close dungeon event contracts`

**Focused verification (2026-10-02):**

```text
python3 -m unittest tests.contract.content_schema.test_p14_dungeon_schemas
PASS — 16 tests

./tools/run_tests.sh --filter p14_dungeon_content_contract
PASS — 1 scene, 0 failures, 0 known leak warnings

./tools/run_tests.sh --filter content_pack_contract
PASS — 1 scene, 0 failures, 0 known leak warnings

./tools/run_tests.sh --filter content_registry
PASS — 1 scene, 0 failures, 0 known leak warnings
```

---

### Task 2: Implement deterministic event selection

**Files:**
- Create: `scripts/events/dungeon_event_selector.gd`
- Create: `tests/unit/events/dungeon_event_selector_test.gd`
- Create: `tests/unit/events/dungeon_event_selector_test.tscn`

**Interfaces:**
- Consumes `select(event_definitions: Array, context: Dictionary) -> Dictionary` with run/floor/node seed facts, primary candidate, repeat history, health, economy, build, resources, flags, and meta facts.
- Produces `{ok, event_id, channel, roll, eligible_ids, predicate_facts}` without mutation.

- [x] **Step 1: Write RED coverage for all eighteen events**

Cover eligible/ineligible states, floor bounds, availability, three repeat policies, eight predicates, exact special priority, weighted regular selection, primary-candidate ordering, byte equality, and seed/node/floor isolation.

- [x] **Step 2: Run `./tools/run_tests.sh --filter dungeon_event_selector` and require RED**

- [x] **Step 3: Implement the pure selector**

Evaluate special events in this order: `event_void_whispers`, `event_perfect_rewind`, `event_old_reunion`. If none qualify, perform a stable weighted regular roll. Return `NO_ELIGIBLE_EVENT` for an empty pool.

- [x] **Step 4: Run the filter three times and commit `feat(events): select launch dungeon events`**

**Completed:** `bdecd9e feat(events): select launch dungeon events`

**Focused verification (2026-10-02):**

```text
./tools/run_tests.sh --filter dungeon_event_selector
PASS — 3 consecutive runs; each run discovered 1 scene with 0 failures and 0 known leak warnings
```

---

### Task 3: Implement strict event run state

**Files:**
- Create: `scripts/events/dungeon_event_run_state.gd`
- Create: `tests/unit/events/dungeon_event_run_state_test.gd`
- Create: `tests/unit/events/dungeon_event_run_state_test.tscn`

**Interfaces:**
- Produces `snapshot`, `can_restore_snapshot`, `restore_snapshot`, `assign_event`, `reserve_option`, `mark_pending_reward`, `mark_pending_encounter`, `resolve_option`, `dismiss_result`, and `rollback_transaction`.

- [x] **Step 1: Write state-machine RED tests**

Assert `unassigned -> open -> reserved -> pending_reward|pending_encounter|resolved -> dismissed`, plus stale/tampered/duplicate rejection, once-per-run/floor/repeatable behavior, sorted completed IDs, pending round trip, result retention, fingerprint drift, and byte-identical rollback.

- [x] **Step 2: Run `./tools/run_tests.sh --filter dungeon_event_run_state` and require RED**

- [x] **Step 3: Implement the exact snapshot**

```text
schema_id, schema_version, content_fingerprint, selected_event_by_node,
seen_run_event_ids, seen_floor_event_keys, resolved_outcomes, pending_transaction,
pending_reward, pending_encounter, completed_transaction_ids, narrative_flags,
temporary_modifiers, revision
```

- [x] **Step 4: Run GREEN and commit `feat(events): add dungeon event state`**

**Completed:** `6902483 feat(events): add dungeon event state`

**Focused verification (2026-10-02):**

```text
./tools/run_tests.sh --filter dungeon_event_run_state
PASS — 1 scene, 0 failures, 0 known leak warnings
```

---

### Task 4: Implement requirements and atomic consequences

**Files:**
- Create: `scripts/events/event_requirement_service.gd`
- Create: `scripts/events/event_resource_authority.gd`
- Create: `scripts/events/event_health_authority.gd`
- Create: `scripts/events/event_modifier_authority.gd`
- Create: `scripts/events/event_route_authority.gd`
- Create: `scripts/events/dungeon_event_consequence_runtime.gd`
- Create: `tests/unit/events/event_requirement_service_test.gd`
- Create: `tests/unit/events/event_requirement_service_test.tscn`
- Create: `tests/unit/events/dungeon_event_consequence_runtime_test.gd`
- Create: `tests/unit/events/dungeon_event_consequence_runtime_test.tscn`

**Interfaces:**
- Produces `prepare_consequences`, `commit_consequences`, `rollback_consequences`, `snapshot`, `can_restore_snapshot`, and `restore_snapshot`.

- [x] **Step 1: Write RED tests for eight requirements, ten consequences, and every failure stage**

- [x] **Step 2: Run requirement and consequence filters and require RED**

- [x] **Step 3: Implement fixed ordering**

```text
requirements -> costs -> Player/Build -> economy -> map/route -> flags/modifiers
-> reward/encounter reservation -> RunState sink -> exactly-once publication
```

`route_skip(rooms)` prevalidates the complete lowest-choice-order viable chain before mutation, then performs a legal FloorPlan traversal one selected edge at a time. It must traverse exactly the authored `rooms` edge count; every intermediate destination becomes visited and cleared, the final destination becomes visited but remains uncleared as the landing room, and no traversed node is represented as abandoned. Any chain that would enter or pass through a Boss, rest, or shop room, or that has fewer than the authored number of edges, is rejected atomically with the original FloorPlan byte-identical. The successful operation returns one authenticated receipt covering the ordered edge chain and rollback snapshot.

`map_reveal(depth)` treats the authored `arguments.depth` as authoritative rather than using a fixed reveal distance. Preparation validates `depth`, reveals every reachable node within one through `depth` forward edge traversals from the current node, and records the authored depth and exact revealed node IDs in the authenticated receipt so commit, rollback, Save, and Replay cannot reinterpret it.

- [x] **Step 4: Run GREEN and commit `feat(events): execute atomic event consequences`**

**Completed:** `7bf2d81 feat(events): execute atomic event consequences`

**Focused verification (2026-10-02):**

```text
./tools/run_tests.sh --filter event_requirement_service
PASS — 1 scene, 0 failures, 0 known leak warnings

./tools/run_tests.sh --filter event_resource_authority
PASS — 1 scene, 0 failures, 0 known leak warnings

./tools/run_tests.sh --filter dungeon_event_consequence_runtime
PASS — 1 scene, 0 failures, 0 known leak warnings
```

The final review also verifies zero-side-effect preparation, `RunEconomyState` as the sole gold writer, restore-invalidated capabilities, strict FloorPlan route restoration, exact rollback, typed malformed-ticket rejection, reverse compensation, and integrity-terminal escalation.

---

### Task 5: Implement event runtime and UI-safe view state

**Files:**
- Create: `scripts/events/dungeon_event_runtime.gd`
- Create: `tests/integration/events/dungeon_event_runtime_test.gd`
- Create: `tests/integration/events/dungeon_event_runtime_test.tscn`

**Interfaces:**
- Produces `open_event`, `view_state`, `choose_option`, `complete_reward`, `complete_encounter`, `dismiss_result`, `snapshot`, and `restore_snapshot`.

- [x] **Step 1: Write RED tests for reopen, disabled options, redaction, weighted outcome, pending continuations, restore, duplicate choice, result dismissal, and exactly-once facts**

- [x] **Step 2: Run `./tools/run_tests.sh --filter dungeon_event_runtime` and require RED**

- [x] **Step 3: Implement UI-safe fields only**

```text
phase, event_id, name_key, description_key, prompt_key,
options[id,label_key,eligible,disabled_reason_key,outcome_visibility,visible_preview],
revision, result_key, pending_kind
```

- [x] **Step 4: Run GREEN and commit `feat(events): coordinate dungeon event flow`**

**Completed:** `ba45f57 feat(events): coordinate dungeon event flow`

**Focused verification (2026-10-02):**

```text
./tools/run_tests.sh --filter dungeon_event_runtime
PASS — 2 consecutive runs; each run discovered 1 scene with 0 failures and 0 known leak warnings
```

Final review also verifies synchronous publication reentry rejection, durable pending-fact retry, same-secret restore and wrong-secret rejection, sealed publication ledger integrity, pending/emitted partition tamper rejection, authoritative encounter success facts, and zero-based floor requirement context.

---

### Task 6: Integrate RunState, Facade, Host, Director, and RoomRuntime

**Files:**
- Modify: `scripts/application/run_state.gd`
- Modify: `scripts/application/run_orchestrator.gd`
- Modify: `scripts/application/run_runtime_facade.gd`
- Modify: `scripts/application/run_runtime_host.gd`
- Modify: `scripts/dungeon/run_director.gd`
- Modify: `scripts/dungeon/room_runtime.gd`
- Modify: `autoload/event_bus.gd`
- Create: `tests/integration/application/event_facade_flow_test.gd`
- Create: `tests/integration/application/event_facade_flow_test.tscn`
- Create: `tests/integration/application/event_room_lifecycle_test.gd`
- Create: `tests/integration/application/event_room_lifecycle_test.tscn`

**Interfaces:**
- Produces `open_current_event`, `event_view_state`, `choose_current_event_option`, `complete_current_event_reward`, `complete_current_event_encounter`, and `dismiss_current_event`.

- [ ] **Step 1: Write real Base Pack and generated-FloorPlan RED tests**

Cover the Launch production path, not only direct Facade calls: `RunRuntimeHost.start_run()` must create, configure, attach, and connect a `RoomRuntime` for FloorPlan runs; the Host and RoomRuntime must have one explicit `room_started` publication owner; event rooms cannot clear before an authenticated pending continuation resolves and the result is dismissed. Restore coverage must prove that actual selected-event overlay is rebuilt without changing the generated FloorPlan digest.

- [ ] **Step 2: Implement `RunState.commit_event_transaction_state` and `RunOrchestrator.commit_event_transaction` with full candidate prevalidation**

Make the complete `dungeon_event_state` snapshot the sole event authority in RunState. Include assignment, repeat history, resolved outcomes, pending transaction/reward/encounter, completed transaction IDs, flags, modifiers, and event revision in the main RunState snapshot, floor transaction snapshot, strict candidate validation, rollback, reset, Save restoration, and Replay-facing state. Remove or migrate the legacy shallow `seen_event_ids` source so two event histories cannot drift.

- [ ] **Step 3: Integrate Launch Host/RoomRuntime ownership, selected-event overlay, and clear gating**

The FloorPlan node `event_id` remains only the deterministic primary candidate and stays inside the generation digest. After `DungeonEventSelector` freezes the actual assignment, RunDirector and Facade must overlay that selected event into the runtime room definition without mutating the FloorPlan; restore must reconstruct the same overlay from `dungeon_event_state`. The Launch Host production path must create and connect RoomRuntime before entering the first FloorPlan room, and RoomRuntime may clear an event room only after the authenticated reward/encounter continuation resolves and the resolved result is dismissed.

- [ ] **Step 4: Run event Facade/lifecycle plus floor lifecycle GREEN and commit `feat(events): integrate launch event runtime`**

---

### Task 7: Seal Save and Replay

**Files:**
- Modify: `scripts/save/save_envelope.gd`
- Modify: `scripts/replay/run_dungeon_replay_seal.gd`
- Modify: `tests/unit/save/save_envelope_test.gd`
- Create: `tests/unit/save/event_save_restore_test.gd`
- Create: `tests/unit/save/event_save_restore_test.tscn`
- Modify: `tests/replay/run_dungeon_replay_test.gd`

- [ ] **Step 1: Write RED tests for open, reserved, pending reward, pending encounter, resolved, and dismissed snapshots plus re-signed Replay drift**

- [ ] **Step 2: Reconstruct strict event candidates in Save and seal actual selection/outcome/receipt facts in Replay**

- [ ] **Step 3: Run event save, SaveEnvelope, and dungeon Replay GREEN and commit `feat(replay): seal launch dungeon events`**

---

### Task 8: Execute all events and certify P14F

**Files:**
- Create: `tests/smoke/events/all_dungeon_events_smoke_test.gd`
- Create: `tests/smoke/events/all_dungeon_events_smoke_test.tscn`
- Modify: `docs/superpowers/plans/2026-10-01-plane-walker-p14-five-floor-dungeon.md`
- Modify: `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`
- Modify: `docs/README.md`
- Create: `docs/current/2026-10-02-p14f-dungeon-events-evidence.md`

- [ ] **Step 1: Enumerate all eighteen events and every option**

Every option executes a real handler to terminal or authenticated pending state, or returns its exact authored requirement rejection. Identity-only handlers, silent no-ops, unknown IDs, missing publication, and un-restorable pending state fail.

- [ ] **Step 2: Run all P14F focused filters plus `run_dungeon_replay`**

- [ ] **Step 3: Run `git diff --check` and `./tools/validate_project.sh`; scan logs for all unregistered errors/leaks**

- [ ] **Step 4: Record exact counts/logs/rollback point and commit `docs(p14): certify dungeon events`**

## Plan self-review

- Spec coverage: selection, predicates, repeat policies, weighted outcomes, every operation, pending reward/combat, UI-safe state, integration, Save, Replay, smoke, and certification each have an owner.
- Placeholder scan: no deferred implementation markers remain.
- Type consistency: selector output feeds event state; consequence receipts feed the coordinator; coordinator state feeds RunState, Save, Replay, and ViewState using the same stable IDs and revisions.
- Scope isolation: Tasks 1–3 touch disjoint files and may run in parallel. Task 4 depends on Tasks 1 and 3. Task 5 depends on Tasks 2–4. Tasks 6–8 run sequentially under one integration owner.
