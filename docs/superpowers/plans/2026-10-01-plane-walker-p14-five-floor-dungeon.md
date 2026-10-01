# Plane Walker P14 Five-Floor Dungeon Implementation Plan

- Status: Active / Current
- Document Role: Current P14 implementation plan
- Authority Level: Executable work breakdown under the approved P14 Five-Floor Dungeon Design
- Applies To: Five floors, FloorPlan generation, thirty streamed room scenes, floor rules, economy, merchants, events, map and interaction UI, Save/Replay, simulation, and certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`, `docs/current/2026-10-01-p13b-launch-content-evidence.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-10-01
- Exit Gate: Exact P14 content counts, deterministic routes, atomic lifecycle/economy/events, thirty valid player-facing room scenes, Save/Replay, controller UI, simulation, and complete repository validation pass

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a deterministic five-floor Launch dungeon with meaningful route choices, thirty streamed hand-authored room scenes, floor rules, economy, merchants, events, complete interaction UI, and sealed Save/Replay behavior.

**Architecture:** ContentRegistry owns five floor definitions, thirty room templates, fifteen regular plus three special events, five merchants, and one economy profile. A pure `FloorPlanGenerator` produces a versioned layered DAG from isolated SeedService channels; RunState and FloorPlan own route selection, while `RoomSceneHost` stages one validated scene at a time. Economy, merchant, event, treasure, rest, floor-rule, Save, Replay, ViewState, and UI systems use stable IDs and two-phase transactions.

**Tech Stack:** Godot 4.6.1, typed GDScript, JSON Schema Draft 2020-12, Content Pack v2, SeedService, PackedScene streaming, strict ViewState contracts, scene tests, Python simulations, localization CSV, and local Git commits.

## Global Constraints

- Exact floor IDs are `floor_ruins_of_remnant`, `floor_void_forest`, `floor_time_rift`, `floor_plane_forge`, and `floor_throne_of_void`.
- Exact room split is `10 combat / 5 elite / 3 treasure / 2 shop / 3 event / 5 boss-room / 2 rest`.
- Exact secondary content is `15 regular events / 3 special events / 5 merchants / 1 Launch economy profile`.
- Every selected floor path contains six to nine actionable rooms including the Boss; the entry staging node is not actionable.
- M1 keeps the frozen five-room linear adapter. Launch/Expansion use FloorPlan.
- P14 does not claim P15's twenty-two enemy behaviors, elite affixes, or five Boss behavior kits.
- Stable content IDs, deterministic seeds, atomic commands, offline operation, controller support, accessibility settings, localization, Save, Replay, and rollback are mandatory.
- Formal status remains `M1 Candidate — External Validation Pending`; authentic human playtests remain `0 / 20`.
- P14 does not claim line coverage, installed export templates, packaged startup, signing, remote push, store configuration, or publication.

---

### Task 1: P14A — Close floor, room, event, merchant, and economy content authority

**Files:**
- Create: `data/schemas/floor_definition_v1.schema.json`
- Create: `data/schemas/room_template_v1.schema.json`
- Create: `data/schemas/dungeon_event_v1.schema.json`
- Create: `data/schemas/merchant_definition_v1.schema.json`
- Create: `data/schemas/economy_profile_v1.schema.json`
- Create: `data/content_packs/base/content/floors.json`
- Create: `data/content_packs/base/content/room_templates.json`
- Create: `data/content_packs/base/content/dungeon_events.json`
- Create: `data/content_packs/base/content/merchants.json`
- Create: `data/content_packs/base/content/economy_profiles.json`
- Create: `scripts/dungeon/floor_definition.gd`
- Create: `scripts/dungeon/room_template_definition.gd`
- Create: `scripts/dungeon/dungeon_event_definition.gd`
- Create: `scripts/dungeon/merchant_definition.gd`
- Create: `scripts/dungeon/economy_profile.gd`
- Modify: `scripts/content/content_registry.gd`
- Modify: `docs/contracts/content-pack-v2.md`
- Modify: `data/content_packs/base/pack.json`
- Modify: `data/content_packs/base/localization/translations.csv`
- Modify: `data/localization/translations.csv`
- Create: `tests/contract/content_schema/p14_dungeon_content_contract_test.gd`
- Create: `tests/contract/content_schema/p14_dungeon_content_contract_test.tscn`
- Create: `tests/contract/content_schema/test_p14_dungeon_schemas.py`
- Modify: `tests/contract/content_schema/content_pack_contract_test.gd`
- Modify: `tests/contract/content_schema/content_registry_test.gd`
- Modify: `tests/unit/content/content_pack_resolver_test.gd`
- Modify: `tools/validate_project.sh`
- Modify: `tools/test_ci_contract.sh`

**Interfaces:**
- Consumes: exact IDs, counts, bounds, and closed consequence/merchant/economy operations from the approved P14 design.
- Produces: normalized parsers with `configure(source: Dictionary) -> Dictionary`, immutable `snapshot() -> Dictionary`, ContentRegistry lookup methods `resolve_floor`, `resolve_room_template`, `resolve_dungeon_event`, `resolve_merchant`, and `resolve_economy_profile`, plus ordered `get_floor_definitions(availability)`.

- [x] **Step 1: Write failing exact-count, exact-ID, schema, and cross-reference tests**

Add exact assertions:

```gdscript
suite.assert_equal(floors.map(func(row): return row["id"]), EXPECTED_FLOOR_IDS, "five floors keep exact order")
suite.assert_equal(room_templates.filter(func(row): return row["room_type"] == "combat").size(), 10, "ten combat templates")
suite.assert_equal(room_templates.filter(func(row): return row["room_type"] == "elite").size(), 5, "five elite templates")
suite.assert_equal(room_templates.filter(func(row): return row["room_type"] == "treasure").size(), 3, "three treasure templates")
suite.assert_equal(room_templates.filter(func(row): return row["room_type"] == "shop").size(), 2, "two shop templates")
suite.assert_equal(room_templates.filter(func(row): return row["room_type"] == "event").size(), 3, "three event templates")
suite.assert_equal(room_templates.filter(func(row): return row["room_type"] == "boss").size(), 5, "five boss-room templates")
suite.assert_equal(room_templates.filter(func(row): return row["room_type"] == "rest").size(), 2, "two rest templates")
suite.assert_equal(events.filter(func(row): return not bool(row.get("special", false))).size(), 15, "fifteen regular events")
suite.assert_equal(events.filter(func(row): return bool(row.get("special", false))).size(), 3, "three special events")
suite.assert_equal(merchants.size(), 5, "five merchant identities")
suite.assert_equal(economy_profiles.map(func(row): return row["id"]), ["launch_economy_v1"], "one Launch economy profile")
```

Mutation tests reject unknown root fields, duplicate IDs, missing or nested localization, invalid floor order, unsupported room type, scene paths outside `res://data/content_packs/base/assets/rooms/launch/`, missing anchors, incompatible floor/rule references, invalid route bounds, invalid merchant services, negative prices, executable strings, unknown event requirement/consequence operations, non-scalar arguments, missing option requirements, parser state retained after a failed reconfiguration, and manifest hash drift. Resolver tests freeze `15` manifest files, `152` generic definitions, `59` specialized definitions, and `211` total definitions.

- [x] **Step 2: Run RED for each independent filter**

```bash
./tools/run_tests.sh --filter p14_dungeon_content_contract
./tools/run_tests.sh --filter content_pack_contract
./tools/run_tests.sh --filter content_registry
./tools/run_tests.sh --filter content_pack_resolver
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_p14_dungeon_schemas
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate_localization.py
bash tools/test_ci_contract.sh
```

Expected: P14 tests fail because schemas, content, parsers, and Registry routes do not exist; pre-existing contracts remain green.

- [x] **Step 3: Implement closed normalized parsers and Registry routing**

Every parser follows one shape:

```gdscript
class_name FloorDefinition
extends RefCounted

var _snapshot: Dictionary = {}

func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	var normalized := _normalize(source)
	var error := _validation_error(normalized)
	if not error.is_empty():
		return {"ok": false, "code": &"FLOOR_DEFINITION_INVALID", "context": error}
	_snapshot = normalized.duplicate(true)
	return {"ok": true, "definition": snapshot()}

func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)
```

`ContentRegistry` dispatches the five specialized categories before generic `_v2_entry_error()` validation, parses all candidate definitions before activation, validates all cross-references against the same candidate pack, stores normalized immutable dictionaries, and exposes deep-copy lookups. The generic v2 schema and generic categories remain frozen. `get_floor_definitions()` sorts by authoritative `order`, not ID. It must not read these JSON files outside pack loading.

`docs/contracts/content-pack-v2.md` records registered specialized schemas as legal manifest rows with the same integrity, isolation, localization, no-executable-content, and activation guarantees. P14 encounter references validate against the exact adapter taxonomy in the design until P15 supplies real behavior definitions.

- [x] **Step 4: Author exact content, localization, and integrity hashes**

Populate the exact catalogs from the P14 design. Event consequences use only the closed operations:

```text
resource_delta | health_delta | reward_draft | curse_add | curse_remove
temporary_modifier | map_reveal | encounter_start | route_skip | narrative_flag
```

Merchant services use only:

```text
purchase_reward | heal | cleanse_curse | reroll | weapon_upgrade
health_trade | route_reveal | sell_reward
```

Add every name, description, option, outcome, rule, merchant, service, floor, and room key to both localization catalogs, then refresh the Base Pack manifest hashes.

- [x] **Step 5: Run GREEN, review, and commit**

```bash
./tools/run_tests.sh --filter p14_dungeon_content_contract
./tools/run_tests.sh --filter content_pack_contract
./tools/run_tests.sh --filter content_registry
./tools/run_tests.sh --filter content_pack_resolver
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_p14_dungeon_schemas
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate_localization.py
bash tools/test_ci_contract.sh
git diff --check
git add -- data/schemas/floor_definition_v1.schema.json data/schemas/room_template_v1.schema.json data/schemas/dungeon_event_v1.schema.json data/schemas/merchant_definition_v1.schema.json data/schemas/economy_profile_v1.schema.json data/content_packs/base/content/floors.json data/content_packs/base/content/room_templates.json data/content_packs/base/content/dungeon_events.json data/content_packs/base/content/merchants.json data/content_packs/base/content/economy_profiles.json scripts/dungeon/floor_definition.gd scripts/dungeon/room_template_definition.gd scripts/dungeon/dungeon_event_definition.gd scripts/dungeon/merchant_definition.gd scripts/dungeon/economy_profile.gd scripts/content/content_registry.gd docs/contracts/content-pack-v2.md data/content_packs/base/pack.json data/content_packs/base/localization/translations.csv data/localization/translations.csv tests/contract/content_schema/p14_dungeon_content_contract_test.gd tests/contract/content_schema/p14_dungeon_content_contract_test.tscn tests/contract/content_schema/test_p14_dungeon_schemas.py tests/contract/content_schema/content_pack_contract_test.gd tests/contract/content_schema/content_registry_test.gd tests/unit/content/content_pack_resolver_test.gd tools/validate_project.sh tools/test_ci_contract.sh
git commit -m "feat(dungeon): close p14 content authority"
```

---

### Task 2: P14B — Build the pure deterministic FloorPlan generator

**Files:**
- Modify: `scripts/core/seed_service.gd`
- Create: `scripts/dungeon/floor_plan.gd`
- Create: `scripts/dungeon/floor_plan_generator.gd`
- Create: `scripts/dungeon/reward_policy_protocol.gd`
- Create: `tests/unit/dungeon/floor_plan_test.gd`
- Create: `tests/unit/dungeon/floor_plan_test.tscn`
- Create: `tests/unit/dungeon/floor_plan_generator_test.gd`
- Create: `tests/unit/dungeon/floor_plan_generator_test.tscn`
- Modify: `tests/unit/core/seed_service_test.gd`

**Interfaces:**
- Consumes: normalized floor and room-template definitions.
- Produces: `SeedService.derive_node_seed(run_seed, floor_id, node_id, channel, roll_index) -> int`, `FloorPlan.configure(snapshot)`, `FloorPlan.select_edge(edge_id, expected_revision)`, and `FloorPlanGenerator.generate(run_seed, floor_definition, room_templates) -> Dictionary`.

- [x] **Step 1: Write failing seed-isolation and plan-invariant tests**

Test node-context isolation explicitly:

```gdscript
var before := SeedServiceScript.derive_node_seed(7001, &"floor_time_rift", &"layer_03_left", &"room_template", 0)
var unrelated := SeedServiceScript.derive_node_seed(7001, &"floor_time_rift", &"layer_03_right", &"room_template", 0)
var repeated := SeedServiceScript.derive_node_seed(7001, &"floor_time_rift", &"layer_03_left", &"room_template", 0)
suite.assert_equal(before, repeated, "node channel is stable")
suite.assert_true(before != unrelated, "sibling nodes own isolated channels")
```

For seeds `20261001..20261030`, assert byte-identical plans, exact floor length, one entry/Boss, DAG reachability, equal entry-to-Boss path length, two or three choices at branch layers, no more than three consecutive combat/elite rooms, rest rules, event/shop/treasure guarantees, template compatibility, and stable digest. Mutation tests reject cycles, orphan nodes, backward edges, duplicate IDs, unknown content, mismatched digest, stale revision, repeated selection, and a selected edge whose sibling is not abandoned.

- [x] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter seed_service
./tools/run_tests.sh --filter floor_plan
./tools/run_tests.sh --filter floor_plan_generator
```

Expected: new APIs and tests fail; existing SeedService behavior remains green after adding the failing assertions.

- [x] **Step 3: Implement immutable plan validation and atomic selection**

`FloorPlan.select_edge()` returns a command dictionary and mutates only after complete validation:

```gdscript
func select_edge(edge_id: StringName, expected_revision: int) -> Dictionary:
	if expected_revision != _revision:
		return {"ok": false, "code": &"STALE_REVISION", "revision": _revision}
	var transition := _prepared_transition(edge_id)
	if transition.is_empty():
		return {"ok": false, "code": &"ROUTE_SELECTION_INVALID", "revision": _revision}
	_selected_edge_ids.append(str(edge_id))
	_abandoned_node_ids = transition["abandoned_node_ids"].duplicate()
	_current_node_id = StringName(transition["destination_node_id"])
	_revision += 1
	return {"ok": true, "new_revision": _revision, "node_id": _current_node_id}
```

Validation reconstructs every path and budget from nodes/edges; cached summaries are never trusted without recomputation.

- [x] **Step 4: Implement deterministic layered generation**

The generator uses explicit node IDs (`entry`, `layer_01_a`, `layer_01_b`, ..., `boss`), node-specific seed channels, bounded retries, and no recursive seed mutation. It first selects route-type budgets, then topology, then compatible templates, then references. It computes the digest from canonical stable data without revision/visited flags.

If a floor cannot be generated in eight deterministic attempts, return:

```gdscript
{
	"ok": false,
	"code": &"FLOOR_PLAN_GENERATION_FAILED",
	"context": {"run_seed": run_seed, "floor_id": floor_definition["id"], "attempts": 8},
}
```

- [x] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter seed_service
./tools/run_tests.sh --filter floor_plan
./tools/run_tests.sh --filter floor_plan_generator
git diff --check
git add -- scripts/core/seed_service.gd scripts/dungeon/floor_plan.gd scripts/dungeon/floor_plan_generator.gd tests/unit/dungeon/floor_plan_test.gd tests/unit/dungeon/floor_plan_test.tscn tests/unit/dungeon/floor_plan_generator_test.gd tests/unit/dungeon/floor_plan_generator_test.tscn tests/unit/core/seed_service_test.gd
git commit -m "feat(dungeon): generate deterministic floor plans"
```

---

### Task 3: P14C — Integrate FloorPlan with RunState, lifecycle, Save v3, and Replay

**Files:**
- Modify: `scripts/application/run_state.gd`
- Modify: `scripts/application/run_orchestrator.gd`
- Modify: `scripts/application/run_runtime_facade.gd`
- Modify: `scripts/application/run_runtime_host.gd`
- Modify: `scripts/dungeon/room_runtime.gd`
- Modify: `scripts/dungeon/run_director.gd`
- Create: `scripts/save/migrations/save_migration_v2_to_v3.gd`
- Modify: `scripts/save/save_migration_registry.gd`
- Modify: `scripts/save/save_envelope.gd`
- Modify: `scripts/save/save_service.gd`
- Modify: `autoload/game_state.gd`
- Create: `scripts/replay/run_dungeon_replay_seal.gd`
- Create: `tests/unit/application/run_floor_plan_state_test.gd`
- Create: `tests/unit/application/run_floor_plan_state_test.tscn`
- Create: `tests/integration/application/run_floor_lifecycle_test.gd`
- Create: `tests/integration/application/run_floor_lifecycle_test.tscn`
- Modify: `tests/unit/save/save_migration_registry_test.gd`
- Modify: `tests/unit/save/save_service_test.gd`
- Modify: `tests/integration/save/game_state_save_integration_test.gd`
- Create: `tests/replay/run_dungeon_replay_test.gd`
- Create: `tests/replay/run_dungeon_replay_test.tscn`

**Interfaces:**
- Consumes: Task 2 FloorPlan and existing authoritative run commands.
- Produces: `start_floor`, `select_route`, `enter_floor_node`, `complete_floor_node`, `complete_floor`, FloorPlan Save snapshots, schema v2-to-v3 migration, and `RunDungeonReplaySeal` validation.

- [ ] **Step 1: Write failing lifecycle, migration, and Replay tests**

Tests cover five-floor progression, stale/duplicate selection, wrong-node completion, floor transition, final Boss victory, M1 five-room parity, Save v3 round-trip, v2 migration without active Launch run, v2 active Launch run fail-closed, content fingerprint drift, plan digest drift, event/economy prefix drift, and atomic recovery from a rejected node transition.

The run snapshot must contain:

```gdscript
for field: String in [
	"current_floor_index", "floor_plan", "completed_floor_ids", "run_economy",
	"seen_event_ids", "merchant_state", "floor_rule_state",
]:
	suite.assert_true(snapshot.has(field), "Launch run snapshot seals %s" % field)
```

- [ ] **Step 2: Run RED for each filter**

```bash
./tools/run_tests.sh --filter run_floor_plan_state
./tools/run_tests.sh --filter run_floor_lifecycle
./tools/run_tests.sh --filter save_migration_registry
./tools/run_tests.sh --filter save_service
./tools/run_tests.sh --filter game_state_save_integration
./tools/run_tests.sh --filter run_dungeon_replay
./tools/run_tests.sh --filter m1_room_plan
```

- [ ] **Step 3: Add FloorPlan transaction state and Launch lifecycle commands**

RunState owns one `FloorPlan` snapshot and exposes strict transaction snapshots. RunOrchestrator is the sole phase/floor/node writer. A successful route selection follows:

```text
validate open route choice + expected revision
-> reserve selected edge
-> commit FloorPlan selection
-> advance RunState node/revision
-> publish route_selected once
-> request RoomSceneHost transition
```

Scene load failure compensates the authoritative selection from the transaction snapshot before any publication. M1 continues to resolve `M1RoomPlan.definitions()` and never constructs a FloorPlan.

- [ ] **Step 4: Activate Save schema v3 and dungeon Replay sealing**

`SaveMigrationV2ToV3` adds exact empty P14 fields only to profiles with no active Launch run. For a saved active Launch run that lacks `floor_plan`, return `MIGRATION_UNSAFE_ACTIVE_RUN`. Settings migrate by version only. SaveEnvelope v3 validates FloorPlan, economy, event, merchant, and floor-rule fields through JSON-boundary normalization before returning runtime data.

`RunDungeonReplaySeal` stores generator version, plan digest, route prefix, room facts, economy ledger digest, event resolution digest, and floor transitions. Validation authenticates the historical bytes before normalization and rejects unknown generator versions.

- [ ] **Step 5: Run GREEN, full related regression, and commit**

```bash
./tools/run_tests.sh --filter run_floor_plan_state
./tools/run_tests.sh --filter run_floor_lifecycle
./tools/run_tests.sh --filter save_migration_registry
./tools/run_tests.sh --filter save_envelope
./tools/run_tests.sh --filter save_service
./tools/run_tests.sh --filter game_state_save_integration
./tools/run_tests.sh --filter run_dungeon_replay
./tools/run_tests.sh --filter m1_room_plan
./tools/run_tests.sh --filter run_authority_contract
git diff --check
git add -- scripts/application/run_state.gd scripts/application/run_orchestrator.gd scripts/application/run_runtime_facade.gd scripts/application/run_runtime_host.gd scripts/dungeon/room_runtime.gd scripts/dungeon/run_director.gd scripts/save/migrations/save_migration_v2_to_v3.gd scripts/save/save_migration_registry.gd scripts/save/save_envelope.gd scripts/save/save_service.gd autoload/game_state.gd scripts/replay/run_dungeon_replay_seal.gd tests/unit/application/run_floor_plan_state_test.gd tests/unit/application/run_floor_plan_state_test.tscn tests/integration/application/run_floor_lifecycle_test.gd tests/integration/application/run_floor_lifecycle_test.tscn tests/unit/save/save_migration_registry_test.gd tests/unit/save/save_service_test.gd tests/integration/save/game_state_save_integration_test.gd tests/replay/run_dungeon_replay_test.gd tests/replay/run_dungeon_replay_test.tscn
git commit -m "feat(dungeon): integrate five-floor lifecycle"
```

---

### Task 4: P14D — Stream thirty room scenes and implement five floor rules

**Files:**
- Create: `scripts/dungeon/room_scene_contract.gd`
- Create: `scripts/dungeon/room_scene_host.gd`
- Create: `scripts/dungeon/launch_room_scene.gd`
- Create: `scripts/dungeon/floor_rule_runtime.gd`
- Create: `scripts/dungeon/floor_rules/crumbling_ground_rule.gd`
- Create: `scripts/dungeon/floor_rules/void_spores_rule.gd`
- Create: `scripts/dungeon/floor_rules/temporal_distortion_rule.gd`
- Create: `scripts/dungeon/floor_rules/forge_vents_rule.gd`
- Create: `scripts/dungeon/floor_rules/collapsing_plane_rule.gd`
- Create: `data/content_packs/base/assets/rooms/launch/launch_room_base.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_pillared_hall.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_split_chambers.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_open_field.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_l_corner.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_crossroads.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_high_ground.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_void_grove.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_ring.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_bridge.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/combat/room_combat_clockwork.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/elite/room_elite_arena.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/elite/room_elite_guard_corridor.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/elite/room_elite_altar_defense.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/elite/room_elite_trap_arena.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/elite/room_elite_twin_hall.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/treasure/room_treasure_vault.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/treasure/room_treasure_wishing_pool.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/treasure/room_treasure_chronovault.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/shop/room_shop_wayfarer_tent.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/shop/room_shop_chrono_emporium.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/event/room_event_shrine.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/event/room_event_crossroads.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/event/room_event_mirror_hall.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/boss/room_boss_ruin_king.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/boss/room_boss_forest_heart.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/boss/room_boss_time_sovereign.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/boss/room_boss_forge_colossus.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/boss/room_boss_void_throne.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/rest/room_rest_campfire.tscn`
- Create: `data/content_packs/base/assets/rooms/launch/rest/room_rest_sanctuary.tscn`
- Modify: `data/content_packs/base/pack.json`
- Modify: `tests/unit/content/content_pack_resolver_test.gd`
- Modify: `scenes/rooms/combat_room_01.tscn`
- Create: `tests/contract/dungeon/room_scene_contract_test.gd`
- Create: `tests/contract/dungeon/room_scene_contract_test.tscn`
- Create: `tests/integration/dungeon/room_scene_host_test.gd`
- Create: `tests/integration/dungeon/room_scene_host_test.tscn`
- Create: `tests/integration/dungeon/floor_rule_runtime_test.gd`
- Create: `tests/integration/dungeon/floor_rule_runtime_test.tscn`
- Create: `tests/visual/p14_room_visual_contract_test.gd`
- Create: `tests/visual/p14_room_visual_contract_test.tscn`

**Interfaces:**
- Consumes: room template definitions, FloorPlan target nodes, Player/World authorities, and accessibility settings.
- Produces: `RoomSceneContract.validate(scene, template)`, `RoomSceneHost.transition_to(node, template, context)`, and five deterministic floor-rule runtimes with `configure`, `advance_frame`, `snapshot`, `can_restore_snapshot`, `restore_snapshot`, and `reset`.

- [ ] **Step 1: Write failing scene-contract, transition-failure, and hazard tests**

Every scene must expose exact named anchors:

```text
PlayerEntry
PlayerExit
CameraBounds
DoorAnchors
EncounterAnchors
InteractionAnchors
FloorRuleAnchors
PixelProxyLayer
```

Tests instantiate all thirty scenes, verify one room script, valid camera bounds inside the `640 x 360` design canvas, accessible collision/door widths, category-required anchors, no missing resources, and correct content ID metadata. Host tests inject load, instantiate, contract, bind, and activation failure and assert the previous room and RunState remain exact. Floor-rule tests assert warning frames, bounded active frames, typed damage/modifier routing, cleanup, reduced-motion alternatives, no surprise instant death, Save/Replay round-trip, and zero late notifications on rejected transactions.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter room_scene_contract
./tools/run_tests.sh --filter room_scene_host
./tools/run_tests.sh --filter floor_rule_runtime
./tools/run_tests.sh --filter p14_room_visual_contract
```

- [ ] **Step 3: Implement staged scene transition and shared room base**

`RoomSceneHost.transition_to()` instantiates under a detached staging root, validates and binds before changing the active root, and disposes the staged root on any failure. A successful commit attaches the staged root, activates the camera and input boundary, then retires the old root. It returns a receipt containing prior/target content IDs and instance generations for compensation tests.

`LaunchRoomScene` binds a floor palette and exposes category handlers but never writes RunState.

- [ ] **Step 4: Author all thirty player-facing scenes and five rules**

Use native Node2D/Control/CollisionShape2D/Marker2D structures, real door and spawn anchors, restrained pixel-proxy geometry, floor palette overlays, and category-specific interactions. Do not duplicate runtime logic in scene scripts. Each floor rule uses deterministic node channels and an authoritative integer frame clock; visual animation derives from that state.

Declare all thirty room scenes plus the shared base in the Base Pack `asset_manifest` and add their exact SHA-256 entries to `integrity_hashes`. Loading a room whose bytes no longer match the activated pack fingerprint fails before instantiation.

The M1 room scene keeps its existing gameplay and may adopt only the shared contract adapter needed for host compatibility.

- [ ] **Step 5: Run GREEN, inspect affected scenes, and commit**

```bash
./tools/run_tests.sh --filter room_scene_contract
./tools/run_tests.sh --filter room_scene_host
./tools/run_tests.sh --filter floor_rule_runtime
./tools/run_tests.sh --filter p14_room_visual_contract
./tools/run_tests.sh --filter m1_room_plan
./tools/run_tests.sh --filter room_runtime
git diff --check
git add -- scripts/dungeon/room_scene_contract.gd scripts/dungeon/room_scene_host.gd scripts/dungeon/launch_room_scene.gd scripts/dungeon/floor_rule_runtime.gd scripts/dungeon/floor_rules data/content_packs/base/assets/rooms/launch data/content_packs/base/pack.json tests/unit/content/content_pack_resolver_test.gd scenes/rooms/combat_room_01.tscn tests/contract/dungeon/room_scene_contract_test.gd tests/contract/dungeon/room_scene_contract_test.tscn tests/integration/dungeon/room_scene_host_test.gd tests/integration/dungeon/room_scene_host_test.tscn tests/integration/dungeon/floor_rule_runtime_test.gd tests/integration/dungeon/floor_rule_runtime_test.tscn tests/visual/p14_room_visual_contract_test.gd tests/visual/p14_room_visual_contract_test.tscn
git commit -m "feat(dungeon): stream launch room scenes"
```

---

### Task 5: P14E — Implement atomic economy and five merchants

**Files:**
- Create: `scripts/economy/run_economy_state.gd`
- Create: `scripts/economy/shop_price_service.gd`
- Create: `scripts/economy/merchant_inventory_service.gd`
- Create: `scripts/economy/merchant_runtime.gd`
- Modify: `scripts/application/run_state.gd`
- Modify: `scripts/application/run_runtime_facade.gd`
- Modify: `scripts/application/run_runtime_host.gd`
- Modify: `scripts/dungeon/room_runtime.gd`
- Create: `tests/unit/economy/run_economy_state_test.gd`
- Create: `tests/unit/economy/run_economy_state_test.tscn`
- Create: `tests/unit/economy/shop_price_service_test.gd`
- Create: `tests/unit/economy/shop_price_service_test.tscn`
- Create: `tests/unit/economy/merchant_inventory_service_test.gd`
- Create: `tests/unit/economy/merchant_inventory_service_test.tscn`
- Create: `tests/integration/economy/merchant_runtime_test.gd`
- Create: `tests/integration/economy/merchant_runtime_test.tscn`

**Interfaces:**
- Consumes: `launch_economy_v1`, merchant definitions, content compatibility, PlayerRewardEffectRuntime, and FloorPlan node context.
- Produces: deterministic inventories, stable offer IDs, `prepare_transaction`, `commit_transaction`, `rollback_transaction`, `purchase`, `reroll`, `sell`, `heal`, `cleanse`, `upgrade`, `health_trade`, and `route_reveal`.

- [ ] **Step 1: Write failing pricing, inventory, and failure-injection tests**

Cover every merchant, floor, rarity, reroll count, compatibility filter, sold state, Save/Replay restore, insufficient gold/health, stale inventory revision, duplicate transaction ID, reward failure, authority failure, rollback failure, recovery, cap/overflow decay, and deterministic inventory reopening. Assert no balance, Player, inventory, or publication change on recoverable failure.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter run_economy_state
./tools/run_tests.sh --filter shop_price_service
./tools/run_tests.sh --filter merchant_inventory_service
./tools/run_tests.sh --filter merchant_runtime
```

- [ ] **Step 3: Implement deterministic pricing and inventory**

Price calculation is integer and data-driven:

```gdscript
static func price(base_price: int, floor_multiplier: float, rarity_multiplier: float, reroll_count: int, reroll_step: float) -> int:
	return maxi(1, ceili(float(base_price) * floor_multiplier * rarity_multiplier * (1.0 + float(reroll_count) * reroll_step)))
```

Inventory generation uses `merchant_inventory_v1:<merchant_id>:<node_id>:<reroll_count>`. It stores the resolved definitions and prices in the authoritative merchant node state. Reopen and Save load read stored offers rather than rerolling.

- [ ] **Step 4: Implement atomic merchant services and economy ledger**

The commit order is cost reserve, effect/service prepare, Player/route commit, economy commit, inventory sold/reroll commit, then exactly-once publication. Every receipt contains transaction ID, inventory revision, before/after economy snapshots, service receipt, and content fingerprint. Recoverable failure rolls every participant back; rollback failure enters a typed integrity terminal path.

- [ ] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter run_economy_state
./tools/run_tests.sh --filter shop_price_service
./tools/run_tests.sh --filter merchant_inventory_service
./tools/run_tests.sh --filter merchant_runtime
./tools/run_tests.sh --filter player_reward_effect_runtime
git diff --check
git add -- scripts/economy scripts/application/run_state.gd scripts/application/run_runtime_facade.gd scripts/application/run_runtime_host.gd scripts/dungeon/room_runtime.gd tests/unit/economy tests/integration/economy
git commit -m "feat(economy): add launch merchants"
```

---

### Task 6: P14F — Implement fifteen regular and three special event runtimes

**Files:**
- Create: `scripts/events/dungeon_event_selector.gd`
- Create: `scripts/events/dungeon_event_runtime.gd`
- Create: `scripts/events/dungeon_event_consequence_runtime.gd`
- Modify: `scripts/application/run_state.gd`
- Modify: `scripts/application/run_runtime_facade.gd`
- Modify: `scripts/application/run_runtime_host.gd`
- Modify: `scripts/dungeon/room_runtime.gd`
- Create: `tests/unit/events/dungeon_event_selector_test.gd`
- Create: `tests/unit/events/dungeon_event_selector_test.tscn`
- Create: `tests/unit/events/dungeon_event_consequence_runtime_test.gd`
- Create: `tests/unit/events/dungeon_event_consequence_runtime_test.tscn`
- Create: `tests/integration/events/dungeon_event_runtime_test.gd`
- Create: `tests/integration/events/dungeon_event_runtime_test.tscn`
- Create: `tests/smoke/events/all_dungeon_events_smoke_test.gd`
- Create: `tests/smoke/events/all_dungeon_events_smoke_test.tscn`

**Interfaces:**
- Consumes: normalized event definitions, run/build/player/economy/map state, encounter handoff, and node seed context.
- Produces: deterministic event selection, option eligibility, one resolved outcome, typed consequence plan/receipt, combat-event reservation, and exactly-once event facts.

- [ ] **Step 1: Write failing selection, eligibility, outcome, and rollback tests**

For all eighteen events, test at least one eligible and one ineligible state. Test floor bounds, no-repeat, special-event predicates, priority, weighted determinism, stable option order, insufficient resource/health, hidden outcome policy, route skip bounds, map reveal, reward/curse application, narrative flag, combat handoff, Save/Replay restore, duplicate option, stale revision, and injected failure at every consequence phase.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter dungeon_event_selector
./tools/run_tests.sh --filter dungeon_event_consequence_runtime
./tools/run_tests.sh --filter dungeon_event_runtime
./tools/run_tests.sh --filter all_dungeon_events_smoke
```

- [ ] **Step 3: Implement deterministic selection and closed consequence plans**

Selection checks special events first in exact catalog order, then performs a stable weighted roll over eligible regular events. The selector returns the selected stable ID and roll facts; it does not mutate run state.

Consequence plans use a fixed domain order:

```text
requirements -> costs -> player/build reward -> economy -> map/route -> flags -> encounter reservation
```

No consequence publishes before all non-combat participants commit. A combat event remains pending until the exact encounter token resolves.

- [ ] **Step 4: Implement every event and cross-event smoke matrix**

Load all eighteen definitions from ContentRegistry and execute every option against bounded fixtures. Each option must either complete through a real handler or be rejected by its documented requirement; identity-only or no-op options fail the smoke test.

- [ ] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter dungeon_event_selector
./tools/run_tests.sh --filter dungeon_event_consequence_runtime
./tools/run_tests.sh --filter dungeon_event_runtime
./tools/run_tests.sh --filter all_dungeon_events_smoke
./tools/run_tests.sh --filter run_dungeon_replay
git diff --check
git add -- scripts/events scripts/application/run_state.gd scripts/application/run_runtime_facade.gd scripts/application/run_runtime_host.gd scripts/dungeon/room_runtime.gd tests/unit/events tests/integration/events tests/smoke/events
git commit -m "feat(events): execute launch dungeon events"
```

---

### Task 7: P14G — Add route map, shop, event, treasure, rest, and floor-transition UI

**Files:**
- Modify: `scripts/application/run_view_state_projector.gd`
- Modify: `scripts/ui/contracts/run_view_state.gd`
- Create: `scripts/ui/contracts/dungeon_map_view_state.gd`
- Create: `scripts/ui/contracts/merchant_view_state.gd`
- Create: `scripts/ui/contracts/dungeon_event_view_state.gd`
- Create: `scripts/ui/dungeon_map_panel.gd`
- Create: `scripts/ui/route_choice_panel.gd`
- Create: `scripts/ui/merchant_panel.gd`
- Create: `scripts/ui/dungeon_event_panel.gd`
- Create: `scripts/ui/room_interaction_panel.gd`
- Create: `scripts/ui/floor_transition_panel.gd`
- Create: `scenes/ui/dungeon_map_panel.tscn`
- Create: `scenes/ui/route_choice_panel.tscn`
- Create: `scenes/ui/merchant_panel.tscn`
- Create: `scenes/ui/dungeon_event_panel.tscn`
- Create: `scenes/ui/room_interaction_panel.tscn`
- Create: `scenes/ui/floor_transition_panel.tscn`
- Modify: `scenes/ui/combat_hud_v2.tscn`
- Modify: `scripts/ui/views/combat_hud_view.gd`
- Create: `tests/ui/dungeon_map_panel_test.gd`
- Create: `tests/ui/dungeon_map_panel_test.tscn`
- Create: `tests/ui/merchant_panel_test.gd`
- Create: `tests/ui/merchant_panel_test.tscn`
- Create: `tests/ui/dungeon_event_panel_test.gd`
- Create: `tests/ui/dungeon_event_panel_test.tscn`
- Create: `tests/integration/ui/p14_controller_flow_test.gd`
- Create: `tests/integration/ui/p14_controller_flow_test.tscn`
- Create: `tests/visual/p14_ui_visual_contract_test.gd`
- Create: `tests/visual/p14_ui_visual_contract_test.tscn`

**Interfaces:**
- Consumes: strict projected ViewState only; UI does not read RunState, Registry, or runtime Nodes directly.
- Produces: controller-first panels and semantic commands for route, purchase/service, event option, treasure/rest choice, leave, map toggle, and floor transition.

- [ ] **Step 1: Write failing ViewState, controller focus, localization, and layout tests**

Tests reject missing/extra fields, unknown IDs, inconsistent sold/affordable state, invalid path topology, unrevealed secret data, unavailable options without disabled reason, and raw stable-ID fallbacks. Controller tests complete every flow without mouse input and verify focus restoration after decline, purchase, reroll, event result, map close, and scene transition. Visual contracts test `640 x 360`, `1280 x 720`, `1920 x 1080`, and ultrawide safe framing with long English and Chinese strings.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter dungeon_map_panel
./tools/run_tests.sh --filter merchant_panel
./tools/run_tests.sh --filter dungeon_event_panel
./tools/run_tests.sh --filter p14_controller_flow
./tools/run_tests.sh --filter p14_ui_visual_contract
```

- [ ] **Step 3: Extend projection and build native panels**

The projector maps authoritative stable IDs to localized copy, icons, color roles, cost summaries, compatibility, route knowledge, and accessibility cues. Panels emit semantic signals only:

```gdscript
signal route_requested(edge_id: StringName, expected_revision: int)
signal merchant_action_requested(action_id: StringName, offer_id: StringName, expected_revision: int)
signal event_option_requested(event_id: StringName, option_id: StringName, expected_revision: int)
signal room_choice_requested(choice_id: StringName, expected_revision: int)
signal floor_transition_requested(expected_revision: int)
```

Use native Containers, Buttons, Labels, TextureRects, and focus neighbors. Do not position labels with spaces or use decorative tables as layout.

- [ ] **Step 4: Add HUD/map integration, feedback, and accessibility alternatives**

Combat HUD shows floor number/name, current node type, gold, Boss distance, and map action without exposing hidden room types. Route/floor/hazard feedback uses existing Pixel Proxy, audio, subtitle, reduced-motion, flash, shake, contrast, and rumble budgets. Every icon has a text alternative.

- [ ] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter dungeon_map_panel
./tools/run_tests.sh --filter merchant_panel
./tools/run_tests.sh --filter dungeon_event_panel
./tools/run_tests.sh --filter p14_controller_flow
./tools/run_tests.sh --filter p14_ui_visual_contract
./tools/run_tests.sh --filter combat_hud_v2_scene
./tools/run_tests.sh --filter controller_focus_flow
./tools/run_tests.sh --filter accessibility_settings_flow
git diff --check
git add -- scripts/application/run_view_state_projector.gd scripts/ui/contracts scripts/ui/dungeon_map_panel.gd scripts/ui/route_choice_panel.gd scripts/ui/merchant_panel.gd scripts/ui/dungeon_event_panel.gd scripts/ui/room_interaction_panel.gd scripts/ui/floor_transition_panel.gd scripts/ui/views/combat_hud_view.gd scenes/ui/dungeon_map_panel.tscn scenes/ui/route_choice_panel.tscn scenes/ui/merchant_panel.tscn scenes/ui/dungeon_event_panel.tscn scenes/ui/room_interaction_panel.tscn scenes/ui/floor_transition_panel.tscn scenes/ui/combat_hud_v2.tscn tests/ui/dungeon_map_panel_test.gd tests/ui/dungeon_map_panel_test.tscn tests/ui/merchant_panel_test.gd tests/ui/merchant_panel_test.tscn tests/ui/dungeon_event_panel_test.gd tests/ui/dungeon_event_panel_test.tscn tests/integration/ui/p14_controller_flow_test.gd tests/integration/ui/p14_controller_flow_test.tscn tests/visual/p14_ui_visual_contract_test.gd tests/visual/p14_ui_visual_contract_test.tscn
git commit -m "feat(ui): add five-floor dungeon flows"
```

---

### Task 8: P14H — Certify route, economy, content, UI, and full repository behavior

**Files:**
- Create: `tools/run_dungeon_simulation.py`
- Create: `tests/contract/simulation/test_dungeon_simulation_report.py`
- Create: `tests/smoke/p14_dungeon_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/p14_dungeon_loadout_matrix_smoke_test.tscn`
- Modify: `tools/validate_project.sh`
- Create: `docs/current/2026-10-01-p14-five-floor-dungeon-evidence.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Modify: `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`
- Modify: this plan

**Interfaces:**
- Consumes: Tasks 1–7 and the complete repository gate.
- Produces: deterministic synthetic route/economy report, 150-loadout dungeon smoke, visual/controller evidence, Historical plan, exact hashes/counts, retained limitations, and P15 handoff.

- [ ] **Step 1: Write failing simulation-report and 150-loadout tests**

The Python report uses seeds `20261001..20261030`, all five floors, stable sorted JSON, no wall clock, and contains:

```text
synthetic: true
human_playtests: 0
content_digest
generator_version
30 seeds
150 floor summaries
route-path distributions
room-type distributions
floor-rule exposure
merchant/event exposure
gold earned/spent/remainder bands
invalid-plan count
negative-balance count
all-buy count
```

The Godot matrix runs all 150 character/weapon/time loadouts through representative route selection, one room of every type, one floor rule, one merchant transaction, one event consequence, floor transition, Save, and Replay restore.

- [ ] **Step 2: Run RED**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.simulation.test_dungeon_simulation_report
./tools/run_tests.sh --filter p14_dungeon_loadout_matrix
```

- [ ] **Step 3: Implement deterministic simulation and validation entrypoints**

`run_dungeon_simulation.py` imports only JSON content and a pure Python mirror of the documented generator/economy contracts. The test cross-checks canonical Godot fixture digests rather than claiming the Python mirror is runtime authority. Two output runs must be byte-identical:

```bash
python3 tools/run_dungeon_simulation.py --seeds 30 --output /private/tmp/planewalker-p14-a.json
python3 tools/run_dungeon_simulation.py --seeds 30 --output /private/tmp/planewalker-p14-b.json
cmp /private/tmp/planewalker-p14-a.json /private/tmp/planewalker-p14-b.json
```

Add both the simulation contract and loadout smoke to `tools/validate_project.sh`.

- [ ] **Step 4: Run focused certification and the full gate**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_p14_dungeon_schemas
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.simulation.test_dungeon_simulation_report
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
./tools/run_tests.sh --filter p14_dungeon_content_contract
./tools/run_tests.sh --filter floor_plan_generator
./tools/run_tests.sh --filter run_floor_lifecycle
./tools/run_tests.sh --filter room_scene_contract
./tools/run_tests.sh --filter floor_rule_runtime
./tools/run_tests.sh --filter merchant_runtime
./tools/run_tests.sh --filter all_dungeon_events_smoke
./tools/run_tests.sh --filter p14_controller_flow
./tools/run_tests.sh --filter run_dungeon_replay
./tools/run_tests.sh --filter p14_dungeon_loadout_matrix
./tools/validate_project.sh
python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
git diff --check
```

Expected: every discovered scene passes, no unregistered leak/error appears, deterministic reports match, and only previously registered warnings remain.

- [ ] **Step 5: Write evidence, mark Historical, review, and commit**

Record exact commits, content counts, file hashes, generator version/digest, 30-seed report hash, route/economy distributions, 150-loadout result, scene count, registered warnings, Save/Replay versions, `0 / 20` human sessions, unsupported line coverage, export/publication boundaries, and P15 adapter limitations. Change this plan to `Completed / Historical`, mark the P14 spec implemented/certified, update README and the Completion Spec, and keep P15 explicitly next.

```bash
git add -- tools/run_dungeon_simulation.py tests/contract/simulation/test_dungeon_simulation_report.py tests/smoke/p14_dungeon_loadout_matrix_smoke_test.gd tests/smoke/p14_dungeon_loadout_matrix_smoke_test.tscn tools/validate_project.sh docs/current/2026-10-01-p14-five-floor-dungeon-evidence.md docs/README.md docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md docs/superpowers/plans/2026-10-01-plane-walker-p14-five-floor-dungeon.md
git commit -m "docs(dungeon): certify p14 five-floor program"
```

## P14 Exit Gate

- [ ] Exact five floor definitions load in approved order.
- [ ] Exact thirty room templates resolve with the `10 / 5 / 3 / 2 / 3 / 5 / 2` split.
- [ ] Exact fifteen regular events, three special events, five merchants, and one economy profile resolve and localize.
- [ ] FloorPlan generation is deterministic, context-isolated, acyclic, reachable, path-length correct, and budget complete.
- [ ] M1 five-room behavior remains frozen through its compatibility adapter.
- [ ] Launch RunState, room lifecycle, route selection, floor transition, and final victory are atomic.
- [ ] Save v3 and dungeon Replay reject drift and round-trip valid authoritative state.
- [ ] All thirty scenes stream, validate, fit supported viewports, and present player-facing content.
- [ ] All five floor rules are bounded, telegraphed, accessible, Replay-safe, and cleaned up.
- [ ] Economy and all five merchants are deterministic, atomic, and exploit-resistant.
- [ ] All eighteen events have executable options and deterministic outcomes.
- [ ] Map, route, shop, event, treasure, rest, floor transition, HUD, keyboard/mouse, controller, and accessibility flows pass.
- [ ] Thirty-seed reports are byte-identical and explicitly synthetic.
- [ ] All 150 loadouts pass representative P14 runtime smoke.
- [ ] P15 enemy, elite-affix, and Boss behavior limitations remain honestly labeled.
- [ ] Formal M1, human-playtest, coverage, export, signing, and publication boundaries remain honest.
- [ ] Full repository validation is green with only registered warnings.
