# Plane Walker P15 Launch Enemies and Five Boss Kits Implementation Plan

- Status: Active / Current
- Document Role: Current P15 implementation plan
- Authority Level: Executable P15 work breakdown under the approved P15 enemy/Boss specification
- Applies To: Twenty-two Launch enemies, ten elite affixes, nine summons, five complete Bosses, deterministic encounters, hostile authority, assets, Save/Replay, and local certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p15-enemies-bosses-design.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p14-five-floor-dungeon-design.md`, `docs/contracts/content-pack-v2.md`, `docs/contracts/save-service-v3.md`
- Last Verified: 2026-10-04
- Exit Gate: Every P15 mechanism, real five-floor routing, atomic Save/Replay, content and assets, 750 production loadout/Boss cases, deterministic synthetic traces, and complete local validation pass

> **For agentic workers:** Use available collaboration agents to execute isolated tasks and review their outputs. Steps use checkbox (`- [ ]`) syntax for tracking; the project's standing authorization permits execution without another approval pause.

**Goal:** Replace every Launch enemy/Boss adapter with distinct, data-driven, fully tested behavior while preserving the verified M1 slice.

**Architecture:** ContentRegistry loads closed hostile definitions. Pure domain coordinators compute fixed-frame action, species, affix, arena, and encounter state; native adapters apply validated effects and project raster animation. An optional participant in the Player frame transaction owns atomic live/Replay advancement and world restoration.

**Tech Stack:** Godot 4.6.1 GDScript, JSON Schema Draft 2020-12, ContentRegistry v2, SeedService, AStarGrid2D, DamageInfo/HealthComponent, HostileThreatRegistry, SaveEnvelope schema 4, Launch full-player Replay schema 7, RunDungeonReplaySeal schema 4, Python and native scene tests.

## Global Constraints

- Implement exactly twenty-two Launch ordinary/elite definitions, ten affixes, nine summon definitions, five Bosses, forty encounter recipes, five floor profiles, and five Boss encounters.
- Keep the P14 floor/profile/room/Boss encounter IDs unchanged and resolve Launch references through actual definitions.
- Preserve M1 catalog, enemies, `overload_pulse`, Chrono Warden, timing, rewards, and regression behavior.
- Launch gameplay advances at exactly 60 Hz through sequential accepted Player frames; no delta AI, Timer-based gameplay, Engine-frame fallback, global RNG, or presentation-state writer.
- Warning floors: floor-one enemy 30f; later enemy 23f; first Boss 40f; Bosses two-four 30f; final Boss 25f. Damaging recovery floors: enemy 15f, Boss 20f.
- One registered threat per source/generation; distinct independently positioned geometry requires distinct generations. Do not use `ring` for a safe-center annulus.
- Keep all payload, healing, shield, revival, safe-route, action-concurrency, and exactly-once bounds from the specification.
- Default HealthComponent/M1 behavior remains unchanged; only authenticated Launch lethal decisions may create nonterminal hostile life states.
- Existing room/economy authorities own reward settlement; summons/illusions/split children yield no separate currency or reward.
- All assets are local, manifested, hashed, and license-recorded; all player text is localized and fits supported resolutions.
- Formal M1 remains `M1 Candidate — External Validation Pending`; authentic external playtests remain `0 / 20`.
- Commit only explicit task files after tests and `git diff --check`; never use `git add .`, push, or public publication.

## Shared Test and Interface Conventions

Native tests use `tests/support/test_suite.gd`, run in a scene named `*_test.tscn`, call a deferred `_run`, and end with `suite.finish(get_tree())`. New tests use dynamic `load` with an explicit assertion so a missing implementation is an intentional failing assertion rather than an unreported parse error. Each `.tscn` is a Node with its corresponding script resource. Parser success is `{ok: true, definition: Dictionary, context: {}}`; failure is `{ok: false, code: StringName, context: Dictionary}` and clears prior parser state. Returned data is deeply isolated.

Create `tests/support/p15_hostile_fixtures.gd` with these exact static APIs:

```gdscript
static func enemy(enemy_id: String = "shattered_sentinel") -> Dictionary
static func boss(boss_id: String = "ruin_king") -> Dictionary
static func affix(affix_id: String = "frenzy") -> Dictionary
static func action(action_id: String = "shattered_sentinel.shield_sweep") -> Dictionary
static func context(frame: int, source_id: String = "hostile:test-a") -> Dictionary
static func read_catalog(relative_name: String) -> Array
```

`enemy`, `boss`, and `affix` read the real Base Pack file and return a matching deep copy; before the catalog exists they return `{}` and tests assert the catalog's absence as RED. `action` looks up a real action in either actor catalog. `context` creates a JSON-safe domain observation with `runtime_frame`, stable run/floor/node/encounter/source IDs, Player position/facing/HP, room bounds, empty time sources, and stable actor observations. Fixture helpers cannot synthesize successful effects, death, rewards, or restored content. Production tests instantiate real scene actors and Player, not an identity-only substitute.

Every native command below has expected RED: at least one named assertion failure before implementation, and expected GREEN: all matching scenes pass, zero unexpected errors/leaks. The full import runs before checks that require new global classes/resources. Generic `ERROR:` and `String formatting error` must be scanned as well as `SCRIPT ERROR:`; a zero process exit is insufficient.

### Task 1 / P15A: Close hostile data, schemas, and canonical identities

**Files:**
- Create: `data/schemas/hostile_action_v1.schema.json`, `enemy_definition_v1.schema.json`, `boss_definition_v1.schema.json`, `elite_affix_v1.schema.json`, `summon_definition_v1.schema.json`, `launch_encounter_profile_v1.schema.json`
- Create: `data/content_packs/base/content/enemies.json`, `bosses.json`, `elite_affixes.json`, `summons.json`, `launch_encounters.json`
- Create: `scripts/enemies/launch/hostile_action_contract.gd`, `enemy_definition.gd`, `boss_definition.gd`, `elite_affix_definition.gd`, `summon_definition.gd`
- Create: `scripts/dungeon/launch_encounter_profile.gd`
- Create: `tests/support/p15_hostile_fixtures.gd`
- Create: `tests/contract/content_schema/p15_hostile_content_contract_test.gd` and `.tscn`, `tests/contract/content_schema/test_p15_hostile_schemas.py`
- Modify: `scripts/content/content_registry.gd`, `data/content_packs/base/localization/translations.csv`, `tools/validate_project.sh`
- Defer: `data/content_packs/base/pack.json` activation until the corresponding native runtime, scene, assets, and production routing tests pass in Tasks 3-11.

**Interfaces:**
- Every parser provides `configure(source: Dictionary) -> Dictionary` and `snapshot() -> Dictionary`.
- `HostileActionContract.create(source: Dictionary, actor_kind: String) -> Dictionary` normalizes exact action fields; `handler_ids() -> Array[String]` exposes the closed list.
- ContentRegistry registers five new specialized categories without changing generic reward/weapon fields; registry lookup uses the existing `get_content(id)` and `get_by_category(category)` APIs.

- [ ] **Step 1: Add executable failing contract tests.**

```gdscript
var implementation := load("res://scripts/enemies/launch/enemy_definition.gd")
suite.assert_true(implementation != null, "P15 EnemyDefinition implementation exists")
if implementation != null:
	var parser = implementation.new()
	var row := P15HostileFixtures.enemy("stone_shell_strider")
	suite.assert_true(not row.is_empty(), "real strider content exists")
	if not row.is_empty():
		row["unknown_runtime_script"] = "res://untrusted.gd"
		suite.assert_true(not parser.configure(row).ok, "arbitrary runtime scripts reject")
		suite.assert_equal(parser.snapshot(), {}, "failed configure clears state")
```

Python mutation cases remove every required field, add unknown fields at every nested boundary, pass Boolean-as-number, NaN/Infinity where applicable, invalid frames, reversed ranges, unsupported handler/parameters, mismatched floor/Boss identity, duplicate IDs, invalid affix exclusions, missing localization, and unsupported compatibility. Canonical assertions use the exact ID tables in specification sections 2, 5-8; count ordinary definitions independently of summons.

- [ ] **Step 2: Run RED.**

```bash
python3 -m unittest tests.contract.content_schema.test_p15_hostile_schemas
./tools/run_tests.sh --filter p15_hostile_content_contract
```

- [ ] **Step 3: Implement strict definitions and author complete data.**

The common action record follows this real shield-sweep payload; normalize finite px values, integer frames, hit indices, and handler parameters without coercing invalid types:

```json
{
  "id": "shattered_sentinel.shield_sweep",
  "handler_id": "melee",
  "warning_frames": 30,
  "active_frames": 8,
  "recovery_frames": 25,
  "idle_frames": 15,
  "cooldown_frames": 150,
  "weight": 10,
  "max_consecutive": 1,
  "distance_min_px": 0,
  "distance_max_px": 29,
  "geometry": [
    {"shape": "cone", "origin_offset": {"x": 0, "y": 0}, "aim_offset_degrees": -45, "radius": 29, "length": 29},
    {"shape": "cone", "origin_offset": {"x": 0, "y": 0}, "aim_offset_degrees": 45, "radius": 29, "length": 29}
  ],
  "hit_schedule": [{"offset_frame": 0, "hit_index": 0, "damage": 12, "damage_type": "physical"}],
  "parameters": {"knockback_px": 19},
  "cue_id": "hostile_stone_sweep"
}
```

Use spec values for every base/elite/Boss action; include all 48 primary Boss moves and four counter responses. Freeze an action field set and per-handler parameter field set in schema/parser tests. Since `triple_blink` has hit offset 54, its active range must include offset 54; normalize its spec interval to 58 frames before ingestion. Content can be validated directly by its parser before activation. Keep new JSON outside the active content manifest until its native scene, assets, and runtime are verified; no unresolved scene references or inert handlers may enter the active Base Pack. Refresh only activated pack hashes.

- [ ] **Step 4: Run GREEN plus registry/localization/import regression.**

```bash
godot --headless --path . --editor --import
python3 -m unittest tests.contract.content_schema.test_p15_hostile_schemas
./tools/run_tests.sh --filter p15_hostile_content_contract
./tools/run_tests.sh --filter content_registry
./tools/run_tests.sh --filter content_pack_contract
python3 tools/validate_localization.py
git diff --check
```

- [ ] **Step 5: Commit explicit files with `feat(enemies): define launch hostile content contracts`.** Do not stage unrelated P14 working-tree changes.

### Task 2 / P15B: Implement fixed-frame actions and transactional effects

**Files:**
- Create: `scripts/enemies/launch/hostile_action_coordinator.gd`, `launch_enemy_runtime.gd`, `launch_boss_runtime.gd`, `hostile_frame_bridge.gd`, `launch_hostile_effect_authority.gd`
- Create: `tests/unit/enemies/hostile_action_coordinator_test.gd` and `.tscn`, `hostile_frame_bridge_test.gd` and `.tscn`
- Create: `tests/integration/combat/launch_hostile_atomic_frame_test.gd` and `.tscn`
- Modify: `scripts/combat/hostile_threat_registry.gd`, `scripts/combat/health_component.gd`, `scripts/player/player_controller.gd`
- Modify: `tests/combat/hostile_threat_registry_test.gd`, `tests/combat/health_component_test.gd`
- Create: `tests/combat/launch_lethal_transition_test.gd` and `.tscn`

**Interfaces:**
- Coordinator: `configure(definition: Dictionary, identity: Dictionary) -> Dictionary`, `request_action(action_id: String, context: Dictionary) -> Dictionary`, `advance_frame(runtime_frame: int, observations: Dictionary) -> Dictionary`, `cancel(reason: StringName) -> Dictionary`, `snapshot() -> Dictionary`, `can_restore_snapshot(value: Dictionary) -> bool`, `restore_snapshot(value: Dictionary) -> bool`.
- Enemy/Boss runtime: same configure/advance/snapshot/restore surface; `request_action` is the only test-selection hook and calls the real coordinator.
- Bridge: `prepare_frame(runtime_frame: int, observations: Dictionary) -> Dictionary`, `commit_prepared_frame(ticket: Dictionary) -> Dictionary`, `publish_prepared_frame(ticket: Dictionary) -> bool`, `rollback_prepared_frame(ticket: Dictionary) -> bool`, `snapshot() -> Dictionary`, `restore_snapshot(value: Dictionary, authority: Object) -> bool`.
- Effect authority: `prepare_effects(batch: Array, context: Dictionary) -> Dictionary`, `commit_effects(ticket: Dictionary) -> Dictionary`, `rollback_effects(ticket: Dictionary) -> bool`, `publish_effects(ticket: Dictionary) -> bool`.
- Registry: `extend_fact_through(source_id: StringName, generation: int, expected_through_frame: int, new_through_frame: int) -> bool`.
- HealthComponent optional owner hooks: `prepare_hostile_lethal_transition(damage_info: RefCounted, hp_before: float, final_amount: float) -> Dictionary`, `commit_hostile_lethal_transition(ticket: Dictionary) -> bool`; absent hooks execute current behavior.
- Player: `configure_hostile_frame_participant(participant: Object) -> bool`; no configured participant means current frame behavior.

- [ ] **Step 1: Write RED edge-frame, geometry, transaction, and lethal tests.**

```gdscript
var coordinator = load("res://scripts/enemies/launch/hostile_action_coordinator.gd").new()
suite.assert_true(coordinator.configure(P15HostileFixtures.enemy(), identity).ok, "configure")
suite.assert_true(coordinator.request_action("shattered_sentinel.shield_sweep", context).ok, "commit warning")
for frame: int in range(1, 30):
	var outcome: Dictionary = coordinator.advance_frame(frame, observations)
	suite.assert_equal(outcome.hit_facts.size(), 0, "warning causes no damage")
var before: Dictionary = coordinator.snapshot()
suite.assert_true(not coordinator.advance_frame(29, observations).ok, "duplicate frame rejects")
suite.assert_equal(coordinator.snapshot(), before, "rejected frame is pure")
suite.assert_equal(coordinator.advance_frame(30, observations).hit_facts.size(), 1, "first active hit")
```

Also test registration failure, changed expiry compare-and-swap, invalid target shape, denied effect, partial health/roster commit, failed compensation, reentrant publication, Player fixed-frame rejection, and pause. First lethal Guard/Hound hit must emit zero died/room-death facts and preserve counted roster; second final hit emits exactly one.

- [ ] **Step 2: Run RED using the coordinator, bridge, and lethal scene filters.**

```bash
./tools/run_tests.sh --filter hostile_action_coordinator
./tools/run_tests.sh --filter hostile_frame_bridge
./tools/run_tests.sh --filter launch_lethal_transition
```

- [ ] **Step 3: Implement the sequential-frame state machine, generation allocation, and compensation.**

Use the real phase boundary calculation, never decrement floating-point seconds:

```gdscript
const PHASES := ["IDLE", "WARNING", "ACTIVE", "RECOVERY"]

static func action_phase(elapsed: int, action: Dictionary) -> String:
	var warning := int(action["warning_frames"])
	var active_end := warning + int(action["active_frames"])
	var recovery_end := active_end + int(action["recovery_frames"])
	if elapsed < warning:
		return "WARNING"
	if elapsed < active_end:
		return "ACTIVE"
	if elapsed < recovery_end:
		return "RECOVERY"
	return "IDLE"
```

Coordinator snapshot includes frame, action phase/elapsed, action ID/digest, committed target/aim/geometry, next generation floor, scheduled/resolved hit identities, cooldowns, decision index, and source lifetimes. Prepare on isolated copies; publish only after every participant preflight/commit. Registry extension validates unchanged geometry and strictly larger expiry. Add the HealthComponent hook before any HP/death publication; default hooks cannot activate for Player/M1. Player bridge snapshots and rollback join the existing frame transaction and world signal buffers; no independent physics callback.

- [ ] **Step 4: Run GREEN and M1 regression filters.**

```bash
./tools/run_tests.sh --filter hostile_action_coordinator
./tools/run_tests.sh --filter hostile_frame_bridge
./tools/run_tests.sh --filter launch_hostile_atomic_frame
./tools/run_tests.sh --filter launch_lethal_transition
./tools/run_tests.sh --filter hostile_threat_registry
./tools/run_tests.sh --filter full_player
./tools/run_tests.sh --filter boss_exposure
```

- [ ] **Step 5: Commit `feat(enemies): execute atomic hostile action frames` with only this task's files.**

### Task 3 / P15C: Implement the five Ruins species and native adapter

**Files:**
- Create: `scripts/enemies/launch/launch_hostile_actor.gd`, `launch_hostile_payload.gd`, `enemy_mechanism_handlers.gd`
- Create: `tests/unit/enemies/ruins_enemy_mechanisms_test.gd` and `.tscn`
- Create: `tests/integration/combat/launch_enemy_actor_test.gd` and `.tscn`
- Create: five scenes under `data/content_packs/base/assets/enemies/launch/`: `enemy_shattered_sentinel.tscn`, `enemy_corrosive_moth.tscn`, `enemy_stone_shell_strider.tscn`, `enemy_ruins_wraith.tscn`, `enemy_rift_watcher.tscn`
- Modify: `scripts/enemies/launch/launch_enemy_runtime.gd`, `scripts/enemies/launch/launch_hostile_effect_authority.gd`, `data/content_packs/base/pack.json`

**Interfaces:**
- Actor: `configure_launch_definition(definition: Dictionary, context: Dictionary) -> Dictionary`, `launch_runtime_snapshot() -> Dictionary`, `project_runtime_snapshot(value: Dictionary) -> bool`; existing hostile/time/weapon endpoint signatures are preserved.
- Room motion: `configure_launch_room_motion(room: Node2D, template: Dictionary) -> Dictionary`, `launch_room_motion_snapshot() -> Dictionary`. Validate the actual room through `RoomSceneContract`; accept translation-only transforms and freeze global CameraBounds. Consume `EnemyDefinition.runtime_projection.collision_radius_px` for independent body/hurt shapes and inset centre limits. Before each prepared frame, reject moved/freed rooms, changed bounds, scaled actors, and changed native body geometry. The Wraith may bypass internal collisions only after this boundary is configured; clip all resulting movement to the frozen inset bounds. Native actor checkpoints carry the same immutable room-motion descriptor and cannot restore a foreign descriptor or an out-of-bounds position.
- Mechanism handlers: `prepare_mechanism(runtime_kind: String, state: Dictionary, observations: Dictionary) -> Dictionary` returns isolated next state and effects; unknown runtime kind rejects.
- Payload: `configure_payload(descriptor: Dictionary, authority: Object) -> bool`, `payload_snapshot() -> Dictionary`, `retire(reason: StringName) -> void`.

- [ ] **Step 1: Write failing distinct-mechanism and real damage tests.**

```gdscript
var shell_before := strider.snapshot()
strider.accept_damage_fact({"fact_id": "hit-1", "amount": 12.0, "frame": 1})
suite.assert_equal(strider.snapshot().mechanism_state.shell_remaining_frames, 120, "shell begins once")
strider.accept_damage_fact({"fact_id": "hit-2", "amount": 12.0, "frame": 2})
suite.assert_equal(strider.snapshot().mechanism_state.shell_remaining_frames, 120, "more hits do not restart shell")
suite.assert_equal(shell_before.definition_id, "stone_shell_strider", "real species profile")
```

Define `LaunchEnemyRuntime.accept_damage_fact(value: Dictionary) -> Dictionary` in this task; facts require unique fact ID, positive finite amount, accepted frame, target source, and resulting HP from HealthComponent. Cover sentinel retreat, moth pool and warned death burst, shell/open boundaries, wraith interrupt/cancel, watcher target/cap/death debuff, each elite move, and actor `_physics_process` gameplay purity. Real integration compares Player HP, damage generation/hit index, registry geometry, and runtime state through HealthComponent.

The room-motion RED test is `tests/integration/combat/ruins_wraith_room_motion_test.gd`/scene. Instantiate `room_combat_open_field.tscn` with its actual JSON template, offset the room, and place a native internal wall. Verify configured Wraith crossing, unconfigured Wraith and configured Strider collision, each outer corner's authored-radius margin, unchanged collision masks, preparation purity, rollback and exact-frame retry, malformed room rejection, and immutable checkpoint/transform/shape guards. Run `./tools/run_tests.sh --filter ruins_wraith_room_motion --timeout 60` before implementation, then the Ruins, native actor, effect and Player bridge regressions.

- [ ] **Step 2: Run RED: `./tools/run_tests.sh --filter ruins_enemy_mechanisms` and `--filter launch_enemy_actor`.**
- [ ] **Step 3: Implement the species state table and production adapters.**

```gdscript
const RUINS_RUNTIME_KINDS := {
	"shattered_sentinel": "retreat_after_sweep",
	"corrosive_moth": "corrosive_impact_and_death",
	"stone_shell_strider": "bounded_shell_open_cycle",
	"ruins_wraith": "interruptible_terminal_detonation",
	"rift_watcher": "capped_ally_nourish",
}
```

Install each concrete mechanism using the exact frame/HP/effect values in spec section5. Actors may inherit EnemyBase damage helpers but override all delta/timer gameplay endpoints with domain-owned source maps and frame lifetimes. They do not call `super._physics_process`. Stage payload creation inside the effect authority; retire owner payloads and modifiers on cancellation. Native scenes include HealthComponent, collision, raster Sprite2D, hit/hurt targeting, and telegraph projection; the old Polygon2D may exist as a hidden compatibility binding, never as the final actor art.

- [ ] **Step 4: Run GREEN, existing enemy/M1 smoke, and `git diff --check`.**
- [ ] **Step 5: Commit `feat(enemies): implement ruins launch enemy kits`.**

### Task 4 / P15D: Implement six Forest species and bounded summons

**Files:**
- Create: `tests/unit/enemies/forest_enemy_mechanisms_test.gd` and `.tscn`, `hostile_summon_budget_test.gd` and `.tscn`
- Create: six scenes `enemy_void_hunter.tscn`, `enemy_void_archer.tscn`, `enemy_bramble_mage.tscn`, `enemy_void_spore.tscn`, `enemy_forest_caller.tscn`, `enemy_shadow_lurker.tscn` in the Launch enemy asset directory
- Create: `scripts/enemies/launch/hostile_spawn_ledger.gd`
- Modify: `enemy_mechanism_handlers.gd`, `launch_enemy_runtime.gd`, `launch_hostile_effect_authority.gd`, `launch_hostile_payload.gd`, `data/content_packs/base/pack.json`

**Interfaces:**
- Spawn ledger: `reserve_spawn(parent_source_id: String, parent_generation: int, child_index: int, definition_id: String, lifetime_frames: int) -> Dictionary`, `commit_spawn(ticket: Dictionary) -> bool`, `cancel_owner(source_id: String) -> Array`, `snapshot() -> Dictionary`, `restore_snapshot(value: Dictionary) -> bool`.
- Child source: `hostile:<sha256(parent_source|parent_generation|child_index).substr(0,40)>`; no scene instance IDs.

- [ ] **Step 1: Write RED tests for every Forest base/elite mechanism and recursive/lifetime limits.**

```gdscript
var first: Dictionary = ledger.reserve_spawn("hostile:caller", 3, 0, "void_firefly", 900)
suite.assert_true(first.ok, "first summon reservation accepts")
suite.assert_true(ledger.commit_spawn(first.ticket), "summon commits once")
suite.assert_true(not ledger.commit_spawn(first.ticket), "duplicate ticket rejects")
suite.assert_true(not ledger.reserve_spawn("hostile:caller", 3, 0, "void_firefly", 900).ok, "same child identity cannot respawn")
```

Include visible flank silhouette, locked archer lanes, gap cage collision, 30f child-chain warnings, chain depth5, interrupted Caller summon, owner cancellation, burrow max180f, marked landing reachable by all five weapons, and visible trap bounds.

- [ ] **Step 2: Run RED: `./tools/run_tests.sh --filter forest_enemy_mechanisms` and `--filter hostile_summon_budget`.**
- [ ] **Step 3: Implement exact Forest handler/state records and support profiles.**

```gdscript
const FOREST_STATE_KINDS := {
	"void_hunter": "visible_flank",
	"void_archer": "obstacle_aware_kite",
	"bramble_mage": "bounded_bramble_and_gap_cage",
	"void_spore": "warned_chain_and_once_split",
	"forest_caller": "capped_owner_bound_summon",
	"shadow_lurker": "bounded_visible_burrow",
}
```

Summons use strict subset capabilities and parent-bound ledger state. Chains reserve child warning rather than recursively invoking immediate damage. All six species and elite moves execute against real Player/construct targets; implement the nine summon definitions used by later tasks now so their parsers/runtime subsets are closed.

- [ ] **Step 4: Run GREEN plus actor/atomic-frame regression; validate pack hashes and localization.**
- [ ] **Step 5: Commit `feat(enemies): implement forest kits and bounded summons`.**

### Task 5 / P15E: Implement six Rift species and nonterminal life states

**Files:**
- Create: `tests/unit/enemies/rift_enemy_mechanisms_test.gd` and `.tscn`, `hostile_nonterminal_life_test.gd` and `.tscn`
- Create: six scenes `enemy_chrono_guard.tscn`, `enemy_rift_weaver.tscn`, `enemy_blink_striker.tscn`, `enemy_rewind_priest.tscn`, `enemy_chrono_storm_elemental.tscn`, `enemy_eternal_hound.tscn`
- Create: `scripts/enemies/launch/hostile_life_state.gd`, `hostile_health_history.gd`
- Modify: `enemy_mechanism_handlers.gd`, `launch_enemy_runtime.gd`, `launch_hostile_effect_authority.gd`, `hostile_spawn_ledger.gd`, `data/content_packs/base/pack.json`

**Interfaces:**
- Life state: `prepare_lethal_transition(context: Dictionary) -> Dictionary`, `commit_lethal_transition(ticket: Dictionary) -> bool`, `advance_frame(frame: int) -> Dictionary`, `finalize_sigil(sigil_id: String, hit_identity: Dictionary) -> Dictionary`, strict snapshot/restore.
- History: `record(frame: int, source_id: String, hp: float, position: Vector2) -> bool`, `sample_before(source_id: String, frame: int) -> Dictionary`, fixed180f bounded storage.

- [ ] **Step 1: Write RED proving revivals stay counted and cannot reward twice.**

```gdscript
var prepared: Dictionary = life.prepare_lethal_transition(lethal_context)
suite.assert_true(prepared.ok, "hound first lethal transition prepares")
suite.assert_true(life.commit_lethal_transition(prepared.ticket), "dormancy commits")
suite.assert_equal(life.snapshot().state, "DORMANT", "first lethal is nonterminal")
suite.assert_equal(life.snapshot().revivals_remaining, 0, "revival consumed before publication")
suite.assert_true(not life.commit_lethal_transition(prepared.ticket), "lethal replay rejects")
```

Test Guard90f/54HP recovery, Hound300f/sigil12HP/35HP reformation, support heal cannot reset flags, priest history cannot revive finalized targets, blink landing+strike warnings, Rift transit reduction, storm switch warnings, no Player time/input lock, and GameplayRewind ignoring hostile life state.

- [ ] **Step 2: Run RED with `rift_enemy_mechanisms` and `hostile_nonterminal_life` filters.**
- [ ] **Step 3: Implement six Rift handlers and authenticate HealthComponent's optional lethal tickets.**

```gdscript
const LIFE_STATES := ["ALIVE", "RECOVERING", "DORMANT", "FINAL"]
const GUARD_RECOVERY_FRAMES := 90
const HOUND_DORMANT_FRAMES := 300
const HOUND_SIGIL_HP := 12.0
```

Ticket binds source ID, exact HP-before, incoming hit identity, life revision, next state, once-only flag, and resulting HP. Validation runs before final health publication; no asynchronous revival callback. Dormant actors remain pending encounter work. Sigil target damage finalizes exactly its parent with no extra currency/kill receipt. Restore validates state/frame/HP/sigil consistency.

- [ ] **Step 4: Run GREEN plus HealthComponent, Replay health, room lifecycle, and all earlier enemy tests.**
- [ ] **Step 5: Commit `feat(enemies): implement rift kits and hostile life states`.**

### Task 6 / P15F: Implement five Forge kits, ten affixes, and forty compositions

**Files:**
- Create: `scripts/enemies/launch/elite_affix_runtime.gd`
- Create: `scripts/dungeon/launch_encounter_catalog.gd`, `launch_encounter_runtime.gd`
- Create: five scenes `enemy_forge_titan.tscn`, `enemy_void_web_weaver.tscn`, `enemy_phase_ranger.tscn`, `enemy_chaos_amalgam.tscn`, `enemy_plane_ripper.tscn`
- Create: `tests/unit/enemies/forge_enemy_mechanisms_test.gd` and `.tscn`, `elite_affix_runtime_test.gd` and `.tscn`
- Create: `tests/unit/dungeon/launch_encounter_catalog_test.gd` and `.tscn`, `launch_encounter_runtime_test.gd` and `.tscn`
- Modify: `enemy_mechanism_handlers.gd`, `launch_enemy_runtime.gd`, `launch_hostile_effect_authority.gd`, `data/content_packs/base/pack.json`

**Interfaces:**
- Affix runtime: `configure(definitions: Array, owner: Dictionary) -> Dictionary`, `select_affixes(candidates: Array, context: Dictionary) -> Dictionary`, `advance_frame(frame: int, observations: Dictionary) -> Dictionary`, strict snapshot/restore.
- Catalog: `configure(registry: RefCounted) -> Dictionary`, `encounter_definition(encounter_id: String, run_seed: int = 0, room_number: int = 0, room_type: String = "") -> Dictionary`, `enemy_definition(enemy_id: String) -> Dictionary`, `spawn_slot(slot_id: String) -> Dictionary`.
- Launch runner provides the existing EncounterRunner signals and `configure`, `start_encounter`, `cancel`, `register_spawned`, `reject_spawn`, `notify_entity_defeated`, `snapshot`; it adds `advance_frame(frame: int, observations: Dictionary) -> Dictionary` and pending payload/life accounting.

- [ ] **Step 1: Write RED for mechanisms, all legal affix pairs, profile references, and premature completion.**

```gdscript
suite.assert_true(not affixes.configure([frenzy, fortified], owner).ok, "symmetric excluded pair rejects")
suite.assert_true(affixes.configure([nullified, anchored], owner).ok, "legal pair accepts")
var stop_result: Dictionary = affixes.apply_time_source(stop_source)
suite.assert_true(stop_result.granted_delay_frames >= 30, "nullified retains positive Stop conversion")
suite.assert_true(not runner.can_complete(), "dormant sigil keeps encounter active")
```

Define `EliteAffixRuntime.apply_time_source(source: Dictionary) -> Dictionary` and `LaunchEncounterRuntime.can_complete() -> bool` here. Test Titan overheat/corpse warning, breakable nonstacking links, full-flight arrow visibility, face switch locking, portal team rules/transit cooldown/safe arrival, once-only split/mirror, capped regen/shield, and deterministic40recipe coverage.

- [ ] **Step 2: Run RED with `forge_enemy_mechanisms`, `elite_affix_runtime`, `launch_encounter_catalog`, and `launch_encounter_runtime` filters.**
- [ ] **Step 3: Implement Forge state, affix operations, and deterministic compositions.**

```gdscript
const ROOM_BUDGETS := {
	"counted_actors": 8,
	"summons": 8,
	"projectiles": 32,
	"damaging_zones": 12,
	"constructs": 8,
	"links": 3,
	"portal_pairs": 1,
}
```

Reserve against complete room budgets before actor/payload publication. Use the exact rosters in specification section 8, split oversized threat rosters into at most three deterministic waves, and validate five combat and three elite recipes per profile. Actor spawn positions derive from active Launch EncounterAnchors and AStarGrid2D. Generate affix sets with seeded decision indices and strict symmetric exclusion closure. Reject unsupported or missing profiles.

- [ ] **Step 4: Run GREEN, 30 canonical repeated-seed recipe/affix digest tests, all 22 species tests, and pack regression.**
- [ ] **Step 5: Commit `feat(enemies): complete launch rosters affixes and encounters`.**

### Task 7 / P15G: Implement Ruin King and Forest Heart

**Files:**
- Create: `scripts/enemies/launch/launch_boss_actor.gd`, `boss_conversion_state.gd`, `boss_arena_handlers.gd`
- Create: `data/content_packs/base/assets/bosses/launch/boss_ruin_king.tscn`, `boss_forest_heart.tscn`
- Create: `tests/unit/enemies/ruin_king_boss_test.gd` and `.tscn`, `forest_heart_boss_test.gd` and `.tscn`, `boss_conversion_state_test.gd` and `.tscn`
- Modify: `launch_boss_runtime.gd`, `launch_hostile_effect_authority.gd`, `data/content_packs/base/pack.json`

**Interfaces:**
- Boss runtime adds `accept_damage_fact(value: Dictionary) -> Dictionary`, `arena_hit(construct_id: String, hit_identity: Dictionary, damage: float) -> Dictionary`, `boss_terminal_receipt() -> Dictionary`.
- Conversion state implements the exact existing Warden Character exposure schema1 surface and `apply_weapon_control_conversion`; public actor delegation preserves all signatures.
- Arena handlers: `prepare_arena_effect(handler_id: String, arena_state: Dictionary, request: Dictionary) -> Dictionary`.

- [ ] **Step 1: Write RED for every one of each Boss's eight moves, P2/enrage, arena destruction, and time/weapon conversions.**

```gdscript
var pulse: Dictionary = boss.request_action("guardian_rift_pulse", context)
suite.assert_true(pulse.ok, "real P2 pulse commits")
var committed := boss.snapshot()
boss.apply_time_stop_source(&"stop:test", 3.0)
suite.assert_equal(boss.snapshot().action.committed_geometry, committed.action.committed_geometry, "Stop preserves aim")
suite.assert_true(boss.snapshot().action.warning_remaining_frames > committed.action.warning_remaining_frames, "Stop extends warning")
```

Actor time methods delegate to the pure domain Boss source map. Arena tests prove wall gaps, safe perimeter, cover-blocked beam, charge crash60f exposure, permanent root destruction, seed-cancel by sac destruction, one-use flower healing, and drain heal based on accepted HP loss. Test all five weapon endpoint families against both Bosses, including stationary trunk Staff/Gauntlets conversion.

- [ ] **Step 2: Run RED with `ruin_king_boss`, `forest_heart_boss`, and `boss_conversion_state` filters.**
- [ ] **Step 3: Implement the sixteen concrete Boss moves and shared conversion component.**

```gdscript
const BOSS_PHASE_THRESHOLDS := {
	"ruin_king": [0.60],
	"forest_heart": [0.60],
}
const CHARACTER_EXPOSURE_SCHEMA_VERSION := 1
const CHARACTER_EXPOSURE_MAX_EXTENSION_FRAMES := 30
const CHARACTER_EXPOSURE_MAX_ACTIVE_CLAIMS := 32
```

Use spec7.1/7.2 action recipes, not Warden delegation. Phase/arena changes preflight in the same hostile frame; interrupted moves cancel owned pending facts before new phase projection. Arena cover/root/sac/flower state is authoritative and participates in snapshots. Every action has real geometry/effects and remains test-selectable through the production coordinator.

- [ ] **Step 4: Run GREEN plus existing Warden exposure, weapon control, elemental status, and hostile atomic-frame tests.**
- [ ] **Step 5: Commit `feat(bosses): implement ruins and forest boss kits`.**

### Task 8 / P15H: Implement Time Sovereign and Forge Colossus

**Files:**
- Create: `data/content_packs/base/assets/bosses/launch/boss_time_sovereign.tscn`, `boss_forge_colossus.tscn`
- Create: `tests/unit/enemies/time_sovereign_boss_test.gd` and `.tscn`, `forge_colossus_boss_test.gd` and `.tscn`
- Create: `scripts/enemies/launch/boss_time_response_runtime.gd`
- Modify: `launch_boss_runtime.gd`, `boss_arena_handlers.gd`, `boss_conversion_state.gd`, `launch_hostile_effect_authority.gd`, `data/content_packs/base/pack.json`

**Interfaces:**
- Response runtime: `observe_committed_time_action(fact: Dictionary) -> Dictionary`, `advance_frame(frame: int, observations: Dictionary) -> Dictionary`, `claim_conversion(hit_fact: Dictionary) -> Dictionary`, strict snapshot/restore.
- Time facts require authentic run ID, ability ID, action generation, accepted frame, and sealed world context; duplicate input events cannot queue counters.

- [ ] **Step 1: Write RED for nineteen moves, four counters, history caps, stationary forms, and all six time pairs.**

```gdscript
var first := responses.observe_committed_time_action(stop_committed_fact)
suite.assert_true(first.ok, "authentic Stop queues response")
suite.assert_true(not responses.observe_committed_time_action(stop_committed_fact).ok, "generation counter deduplicates")
suite.assert_true(first.response.warning_frames >= 45, "counter is readable")
suite.assert_equal(first.response.removes_player_source, false, "paid Stop source persists")
```

`removes_player_source` is an explicit Boolean in normalized counter results. Test watch40/80damage interrupts, capped self-rewind150/300HP and monotonic phase, accelerated six-hit shatter, Rift paid lifetime, all three Forge forms from one HP bar, cooling pool source cleanup, capped pull, coordinated P14vents, and enrage preserving safe routes.

- [ ] **Step 2: Run RED with `time_sovereign_boss` and `forge_colossus_boss` filters.**
- [ ] **Step 3: Implement source-generation responses and Forge form transitions.**

```gdscript
const RESPONSE_IDS := {
	"stop": "traitor.counter_stop",
	"rewind": "traitor.counter_rewind",
	"accelerate": "traitor.counter_accelerate",
	"rift": "traitor.counter_rift",
}
const FORGE_PHASE_THRESHOLDS := [0.60, 0.25]
const SELF_REWIND_CAST_HEAL_CAP := 150.0
const SELF_REWIND_ENCOUNTER_HEAL_CAP := 300.0
```

Four counters defer until primary recovery, reserve warning budget, and grant documented payoff windows. Forge stage replacement retires its prior hazards before form-owned new ones. Complete every original named move in spec7.3/7.4, including enrage variants, without extraHP or immunity. Pixel forms may still be provisional until Task11 but must already have separate native scene projection states.

- [ ] **Step 4: Run GREEN, all Boss conversion tests, P14 floor-rule interaction tests, and earlier Boss regression.**
- [ ] **Step 5: Commit `feat(bosses): implement time and forge behavior kits`.**

### Task 9 / P15I: Implement Void Throne and final narrative receipts

**Files:**
- Create: `data/content_packs/base/assets/bosses/launch/boss_void_throne.tscn`
- Create: `tests/unit/enemies/void_throne_boss_test.gd` and `.tscn`, `boss_terminal_receipt_test.gd` and `.tscn`
- Modify: `launch_boss_runtime.gd`, `boss_arena_handlers.gd`, `boss_conversion_state.gd`, `launch_hostile_effect_authority.gd`, `data/content_packs/base/pack.json`

**Interfaces:**
- `boss_terminal_receipt()` returns only finalized versioned `boss_id`, phase history, accepted battleframes, P3damage facts, P3Rewind generations, core-round claims, action/contentdigests, and defeatidentity.
- Arena `core_break` facts bind core ID, round, hitidentity, HPbefore/after, owner, acceptedframe, and once-only bodydamage/exposureclaim.

- [ ] **Step 1: Write RED for all thirteen moves, three phases, cores, and final receipt.**

```gdscript
var first: Dictionary = boss.arena_hit("plane_core_0", hit_identity, 100.0)
suite.assert_true(first.ok, "core breaks through production arena damage")
suite.assert_equal(first.body_damage, 100.0, "core grants bounded body damage")
suite.assert_true(not boss.arena_hit("plane_core_0", hit_identity, 100.0).ok, "same core hit cannot duplicate")
suite.assert_equal(boss.snapshot().arena.core_round_max, 2, "core rounds finite")
```

Cover Player-dead P3 transition, once-only 30% healing, melee-reachable cores, paid time actions during tear, finite devour debuffs, shard energy claims, denominator-safe HP thresholds, denial/zero safe corridors and core interrupts, and exactly-once defeat receipts with summon/hazard cleanup.

- [ ] **Step 2: Run RED with `void_throne_boss` and `boss_terminal_receipt` filters.**
- [ ] **Step 3: Implement the final kit and stable facts for later narrative/progression.**

```gdscript
const VOID_PHASE_THRESHOLDS := [0.60, 0.20]
const PLANE_CORE_HP := 100.0
const PLANE_CORE_BODY_DAMAGE := 100.0
const PLANE_CORE_EXPOSURE_FRAMES := 60
const PLANE_CORE_ROUND_MAX := 2
```

Existing narrative and reward authorities consume the Boss terminal receipt. Produce that receipt only after real HealthComponent final death and complete retirement of owned payloads. Every requested move executes through geometry and DamageInfo, including large area attacks; Player HP, energy, and inventory retain their normal authorities.

- [ ] **Step 4: Run GREEN, all five Boss suites, every time-pair conversion, and room-terminal reward regression.**
- [ ] **Step 5: Commit `feat(bosses): complete void throne encounter`.**

### Task 10 / P15J: Bind production routing and versioned Save/Replay

**Files:**
- Create: `scripts/replay/hostile_replay_seal.gd`, `scripts/save/migrations/save_migration_v3_to_v4.gd`
- Create: `data/schemas/save_profile_v4.schema.json`, `save_settings_v4.schema.json`, `docs/contracts/save-service-v4.md`
- Create: `tests/unit/save/hostile_save_restore_test.gd` and `.tscn`, `tests/replay/launch_hostile_replay_test.gd` and `.tscn`
- Create: `tests/integration/dungeon/launch_hostile_routing_test.gd` and `.tscn`
- Modify: `scripts/dungeon/encounter_catalog.gd`, `room_controller.gd`, `room_runtime.gd`, `scripts/application/run_runtime_host.gd`, `run_runtime_facade.gd`, `run_orchestrator.gd`, `run_state.gd`, `scripts/main.gd`
- Modify: `scripts/save/save_envelope.gd`, `save_service.gd`, `save_migration_registry.gd`, `scripts/replay/replay_recorder.gd`, `replay_player.gd`, `run_dungeon_replay_seal.gd`, `scripts/player/player_controller.gd`, `tests/contract/content_schema/content_pack_contract_test.gd`

**Interfaces:**
- Seal: `capture(runtime: RefCounted, content_snapshot: Dictionary) -> Dictionary`, `validate(value: Dictionary, registry: RefCounted) -> Dictionary`, `prepare_restore(value: Dictionary, authority: Object) -> Dictionary`, `commit_restore(ticket: Dictionary, authority: Object) -> bool`, `rollback_restore(ticket: Dictionary, authority: Object) -> bool`.
- Host: `capture_hostile_replay_checkpoint() -> Dictionary`, `restore_hostile_replay_checkpoint(value: Dictionary) -> bool`; authorized restoration validates run/floor/node/content, binds staged actors, then installs atomically.
- RoomRuntime selects the M1 or Launch runner before beginning and retains existing externally observed room signals; event-combat continuation follows the active Launch mode.

- [ ] **Step 1: Write RED for each mid-action/life/arena checkpoint and production adapter removal.**

```gdscript
var before: Dictionary = host.capture_hostile_replay_checkpoint()
var corrupt := before.duplicate(true)
corrupt["actors"][0]["action"]["next_generation_floor"] = 0
suite.assert_true(not host.restore_hostile_replay_checkpoint(corrupt), "corrupt generation rejects")
suite.assert_equal(host.capture_hostile_replay_checkpoint(), before, "world remains byte-identical")
suite.assert_equal(published_facts, [], "rejected restore publishes nothing")
```

Test warning/active/recovery, Stop/Rift, shell, burrow, dormancy, splits, phase/core breaks, and pending waves/deaths. Cover v3 inactive/M1/between-room migration, active adapter migration refusal, legacy Replay fingerprint mismatch, unknown profiles, staged spawn failure, failed rollback, the exact accepted fact prefix, and Gameplay Rewind isolation. Main tests stream every Boss room and at least one combat, elite, and event-combat room per floor, asserting the actual species and Boss IDs.

- [ ] **Step 2: Run RED with `hostile_save_restore`, `launch_hostile_replay`, and `launch_hostile_routing` filters.**
- [ ] **Step 3: Integrate strict hostile restoration and explicit schemas.**

```gdscript
const HOSTILE_SEAL_SCHEMA_VERSION := 1
const SAVE_SCHEMA_VERSION := 4
const FULL_PLAYER_LAUNCH_SCHEMA_VERSION := 7
const RUN_DUNGEON_REPLAY_SCHEMA_VERSION := 4
```

Preserve weapon Replay 6 and M1 full-player Replay 2. Reject interpreting P14 adapter combat as a P15 fight. Remove Launch `_launch_adapter_source` resolution after the actual catalog and Main tests pass. Bind the spawn resolver to active LaunchSceneHost anchors and grid. Preserve P14 transaction, event publication, and floor hazard revision contracts. Document exact migration and incompatibility recovery paths and refresh pack content fingerprint fixtures.

- [ ] **Step 4: Run GREEN plus all Save, Replay, room lifecycle, event continuation, and M1 regression filters.**
- [ ] **Step 5: Commit `feat(enemies): integrate launch hostile save replay and routing`.**

### Task 11 / P15K: Complete raster assets, audio, HUD, and accessibility

**Files:**
- Create: `tools/generate_p15_hostile_assets.py`, `assets/sources/p15/provenance.json`, `scripts/enemies/launch/launch_hostile_presentation.gd`
- Create: real actor atlases and closed cue/music assets under `data/content_packs/base/assets/enemies/launch/`, `assets/bosses/launch/`, `assets/audio/launch_hostiles/`
- Create: `tests/visual/p15_hostile_visual_contract_test.gd` and `.tscn`, `tests/ui/launch_boss_hud_test.gd` and `.tscn`
- Modify: `scripts/presentation/combat_audio_synth.gd`, `scripts/ui/contracts/run_view_state.gd`, `scripts/application/run_view_state_projector.gd`, `scripts/ui/views/combat_hud_view.gd`, `scripts/accessibility/accessibility_runtime.gd`, `data/content_packs/base/pack.json`, `data/content_packs/base/localization/translations.csv`, all 27 Launch actor scenes

**Interfaces:**
- Presentation: `configure(definition: Dictionary, accessibility: Dictionary) -> bool`, `project_snapshot(runtime_snapshot: Dictionary) -> bool`, `presentation_snapshot() -> Dictionary`.
- Generator command: `python3 tools/generate_p15_hostile_assets.py --output data/content_packs/base/assets --provenance assets/sources/p15/provenance.json`; output paths and hashes are deterministic and repeat identically.

- [ ] **Step 1: Write RED for atlas existence/nonblank pixels, exact animation tracks, cue/localization closure, and presentation purity.**

```gdscript
var state_before: Dictionary = actor.launch_runtime_snapshot()
presentation.configure(definition, {"reduced_motion": true, "high_contrast": true})
presentation.project_snapshot(state_before)
suite.assert_equal(actor.launch_runtime_snapshot(), state_before, "accessibility is gameplay-pure")
suite.assert_equal(presentation.presentation_snapshot().warning_mode, "static_outline", "warning retains nonmotion cue")
```

Asset tests inspect Image pixels, frame bounds, and unique silhouettes; empty or transparent atlases fail. HUD tests assert local names, phase/enrage state, text fit, and controller pause/restart focus. Audio tests assert five distinct Boss loop stems and seven warning/impact/death cue families, subtitles with audio off, and bounded rumble.

- [ ] **Step 2: Run RED with `p15_hostile_visual_contract` and `launch_boss_hud` filters.**
- [ ] **Step 3: Generate original raster/audio assets, wire frame-bound animation, and strict HUD projection.**

```gdscript
const ENEMY_ANIMATION_FRAMES := {
	"idle": 2, "move": 4, "warning": 3, "active": 2,
	"recovery": 2, "hit": 1, "death": 4,
}
const AUDIO_FAMILIES := ["stone", "acid", "root", "shadow", "clock", "metal", "void"]
```

Add all special tracks from specification section 11, saved generation recipes/hashes, CC0 original provenance, and local manifest references. Bind visible Sprite2D atlases with nearest pixel filtering. Frame callbacks affect presentation only. High-contrast boundaries preserve collider dimensions and registered threat facts.

- [ ] **Step 4: Run GREEN and capture the visual matrix using native Godot:**

```bash
godot --path . tests/visual/p15_hostile_visual_contract_test.tscn -- --p15-screenshots
./tools/run_tests.sh --filter p15_hostile_visual_contract
./tools/run_tests.sh --filter launch_boss_hud
python3 tools/validate_localization.py
```

Screenshot outputs under `build/p15-hostile-screenshots` cover all 22 normal/elite actors, Boss phases/actions/time responses, 640x360/1280x720/1920x1080/2560x1080, zh_CN/en, and normal/reduced-motion/high-contrast modes. Inspect representative frames and automatic pixel/overlap checks; record actual image paths in the evidence. Controller interaction QA uses real inputs and the complete five-floor flow.

- [ ] **Step 5: Commit `feat(presentation): finish launch hostile assets and feedback`.**

### Task 12 / P15L: Certify the full hostile milestone

**Files:**
- Create: `tools/run_p15_hostile_matrix.py`, `tools/p15/hostile_matrix_probe.gd`, `hostile_matrix_probe.tscn`
- Create: `tests/smoke/p15_hostile_loadout_matrix_test.gd` and `.tscn`, `tests/integration/dungeon/p15_five_floor_run_test.gd` and `.tscn`
- Create: `docs/current/2026-10-04-p15-enemies-bosses-evidence.md`
- Modify: this plan, specification, `docs/README.md`, `tools/validate_project.sh`, and CI content/matrix configuration files discovered during integration

**Interfaces:**
- Matrix driver: `--seed-count 30 --loadout-count 150 --boss-count 5 --output <path>`; different canonical counts reject.
- Scene probe emits a versioned JSON trace including actual accepted facts, content fingerprint, hostile checkpoint digests, allocation peak, errors/leaks, and terminal result.

- [ ] **Step 1: Write RED for exact coverage, repeatability, 750 production cases, and full five-floor actual content.**

```gdscript
suite.assert_equal(report["synthetic_case_count"], 22500, "30 x 150 x 5 domain traces")
suite.assert_equal(report["production_case_count"], 750, "150 x 5 actual SceneTree cases")
suite.assert_equal(report["launch_warden_fallback_count"], 0, "no compatibility Boss fallback")
suite.assert_equal(report["unwarned_hit_count"], 0, "every hit has committed warning")
suite.assert_equal(report["replay_divergence_count"], 0, "real checkpoint and fact-prefix replay")
```

Reports fail when any authored action, mechanism, affix pair, arena, or time conversion has zero coverage, or when distinct production cases collapse into one fixture.

- [ ] **Step 2: Run RED with `p15_hostile_loadout_matrix` and `p15_five_floor_run` filters.**
- [ ] **Step 3: Implement real probes and separate synthetic reports.**

```python
EXPECTED_SYNTHETIC_CASES = 30 * 150 * 5
EXPECTED_PRODUCTION_CASES = 150 * 5
REPORT_KIND = "synthetic_hostile_behavior_and_production_contract_evidence"
```

Domain traces compare byte-identical repeated outputs for 30 canonical seeds and adversarial payload/life budgets. The 750 production cases instantiate real Player/loadouts and native Bosses, drive committed inputs and actual collision/effect authority, and verify damage, every phase/arena transition, positive conversions, and terminal cleanup. Test drivers select moves or control input while production authorities write HP, damage, death, rewards, and room completion. Capture Save/Replay mid-action and inject one failure at each commit step.

- [ ] **Step 4: Run final GREEN and clean certification.**

```bash
python3 tools/run_p15_hostile_matrix.py --seed-count 30 --loadout-count 150 --boss-count 5 --output build/p15-hostile-matrix.json
./tools/run_tests.sh --filter p15_hostile_loadout_matrix
./tools/run_tests.sh --filter p15_five_floor_run
./tools/validate_project.sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
git diff --check
```

Run the existing `tools/export/certify_checkout.py` through its documented CLI after the milestone commit. Record actual detached-checkout/import/test/export/startup evidence and any blocked steps with their real status. Scan all engine/stdout logs for generic errors and unexpected ObjectDB/RID leaks. Only registered warnings may remain.

- [ ] **Step 5: Commit `test(enemies): certify complete launch hostile milestone` and write one nonblocking retention review.**

Evidence records exact implementation commits, counts, digests, focused/full test results, actual screenshots, the production/synthetic matrix distinction, Save/Replay migrations, rollback point, export/template/coverage blockers, and the authentic human evidence boundary. After certification, mark this plan Completed/Historical and continue the next authorized full-product milestone.

## Self-Review and Execution Ownership

### Executed Foundation / 2026-10-04

- [x] Closed action contract and fixed-frame action coordinator reached focused RED-to-GREEN, including strict mid-active checkpoints and existing native telegraph conversion.
- [x] Closed Launch profile parser, catalog, canonical affix exclusions, and fixed-frame encounter domain reached focused RED-to-GREEN.
- [x] Fixed-frame Stop/Rift/weakpoint/vulnerability source maps and strict control checkpoints reached focused RED-to-GREEN.
- [x] First inactive native Sentinel scene, nineteen-pixel/forty-eight-frame retreat domain, original raster generator, real Health/Hurtbox damage, and native status/frame compensation reached focused RED-to-GREEN. This is a partial actor slice, not completed authoritative Launch content or global frame atomicity.
- [x] Partial evidence recorded in `docs/current/2026-10-04-p15-hostile-foundation-evidence.md` with tested APIs and explicit production limits.
- [x] Authoritative Enemy/Boss/Affix/Summon data and closed parsers/schemas are present; five real profiles and forty recipes, bilingual profile keys, inactive source and actual template/actor-reference validation reached focused RED-to-GREEN on 2026-10-05.
- [x] Native Strider charge/contact and elite once-cycle shell shock execute real Health effects; shell-shock selection, cycle lineage, Stop, native reservation compensation and actual Launch Guardian damage passed isolated gates. Complete Ruins kits and affix/production routing gates remain open.
- [x] Native Moth kiting, finite frozen single/three-lane projectiles, real swept collisions, independent impact/death acid pools and Stop/Rift sources execute actual Launch Character damage with whole-frame compensation. Owned raster presentation rejects the legacy proxy; corrected OpenGL screenshots were inspected at 640x360. Complete visual/audio kits and production routing remain open.
- [x] Optional native room frame authority synchronizes active/queued payloads before accepted completion, with schema-2 queue budgets and schema-1 active-only migration. Actual Moth parent death cannot clear its room before final acid retirement; spawn/death/impact/completion rejection, queue caps, exact effects ownership and callback reentry passed. Complete native spawn/router installation, persistent Save/Replay and future-species native saturation remain open.
- [x] Specialized ContentRegistry ingestion and Base Pack data activation verified separately at `5bee8ef` for 431 records/40 recipes; this is data-boundary activation and does not certify unimplemented native kits.
- [ ] Complete Task 2 live effect/bridge atomicity, time sources, and nonterminal HealthComponent integration.
- [ ] Complete Tasks 3-12 native species, Bosses, assets, routing, Save/Replay, and certification.

Self-review on 2026-10-04 maps every P15 specification section to Tasks 1-12. Closed IDs and data are Task 1; frame/geometry/lethal atomicity Task 2; all 22 base/elite kits Tasks 3-6; ten affixes and forty recipes Task 6; all 48 Boss moves and four responses Tasks 7-9; native production routing, Save 4, and Replay 7 Task 10; raster/audio/UI/accessibility Task 11; 30 seeds, 150 loadouts, 750 production cases, and clean certification Task 12. Unchecked steps claim no runtime completion.

Coordination boundary: the Launch hostile worker owns new `enemies/launch`, Launch catalog/runner, hostile JSON/schema, and their tests. The integration lead owns shared Main, RunRuntimeHost, RunRuntimeFacade, RunOrchestrator/RunState, Player frame bridge installation, Save/Replay versioning, and UI changes. Agree on exact interfaces before each shared-file edit. Read current P14 work before integration and stage only owned files. P15 implementation starts with Task 1's failing tests while the lead finishes P14H; Launch activation waits for P14 certification.
