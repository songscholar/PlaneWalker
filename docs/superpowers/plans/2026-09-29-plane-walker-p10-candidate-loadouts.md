# Plane Walker P10 Candidate Loadouts Implementation Plan

- Status: Completed / Historical
- Document Role: Historical implementation record
- Authority Level: Preserved P10A candidate-loadout regression evidence
- Applies To: Data-driven character/weapon/time-ability identities, candidate availability, authoritative run-loadout validation, player runtime activation, two-slot HUD presentation, and local candidate-lab verification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-09-29
- Implementation Status: Verified locally; canonical catalogs, authoritative policy, per-run player activation, Bow/Rift/Accelerate candidate runtime, two-slot HUD, Candidate Lab, six legal time pairs, reset, M1 isolation, and exactly-once facts pass the focused and unified repository gates
- Completion Evidence: Commits `e36f78d90ebda19b6bb7464db8a28d6814d12c9c`, `f60a4222e2c2237ad4026b5bf68e95171017a5f8`, `f8aa3a23c1ac4afab5a028096dd8dc0a582b6ce1`, `fd4812a821874032709bf97aaa53eee5d88482d1`, `1295b59319258a8555a8eec3c27b9a2a593f686d`, `0971f84fbedbbb7c2a6d461720b9e8793e521c3f`, `7d9d1699fe71ef5ecc5efdb0a8cf1c4b38dbc0b2`, `f732f705fbd0590d1a52334c2693038822b1730b`, and `4173b4fa70a0a8137e89e16d45f54846e759878b`; see [P10A candidate-loadout evidence](../../current/2026-09-29-p10-candidate-loadouts-evidence.md)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the existing Bow, Time Rift, and Time Accelerate prototypes into data-driven, fail-closed candidate loadouts while preserving the default M1 run and its external-evidence gate.

**Architecture:** Content Pack v2 owns stable character, weapon, and time-ability identities. `RunLoadoutPolicy` validates a normalized `RunConfig` against the active registry before `RunOrchestrator` mutates authoritative state. `RunRuntimeHost` applies the accepted loadout once to `PlayerController`; the player remains the single action owner and gates weapon/time intents by equipped IDs. Presentation reads two generic ability slots from immutable ViewState instead of hard-coding Stop/Rewind.

**Tech Stack:** Godot 4.6, typed GDScript, Content Pack v2 JSON, CSV localization, the existing scene-test harness, Python documentation governance, and shell validation scripts.

## Global Constraints

- Formal status remains `M1 Candidate — External Validation Pending`; authentic human playtests remain `0 / 20`.
- Bow, Time Rift, and Time Accelerate are candidate implementations, not evidence-based Current promotion.
- Default quick start remains `wanderer + sword + stop + rewind` in milestone `M1`.
- A run equips exactly one registered character, one registered weapon, and exactly two different registered time abilities.
- Unknown IDs, duplicate time abilities, category mismatches, unavailable content, or malformed definitions fail before RunState revision or Player mutation.
- `RunOrchestrator` remains the only RunState writer. No GameState run mirror, generic EventBus API, or EventBus-driven domain transition may return.
- Only equipped actions may commit. Rejected or unequipped actions consume no resource, start no cooldown, spawn nothing, and publish no typed gameplay fact.
- All registry definitions, validation contexts, configs, snapshots, and ViewState payloads cross boundaries as deep copies.
- M1 reward pools, five-room plan, deterministic seed probes, and existing accessibility settings remain isolated from candidate availability.
- P7/P9 line coverage, export templates, packaged startup, signing, publication, and platform credentials remain honest external blockers.

---

## File Map

### New authoritative units

- `scripts/application/run_loadout_policy.gd`: validates loadout identities, categories, availability, uniqueness, and returns frozen definitions.
- `scripts/player/player_loadout_runtime.gd`: stores the accepted player loadout and answers equipped-action queries without owning run phase.
- `data/content_packs/base/content/characters.json`: authoritative five-character identity catalog.
- `data/content_packs/base/content/weapons.json`: authoritative five-weapon identity catalog and candidate availability.
- `data/content_packs/base/content/time_abilities.json`: authoritative four-ability identity catalog and candidate availability.
- `scenes/ui/candidate_loadout_panel.tscn` and `scripts/ui/candidate_loadout_panel.gd`: controller-safe local candidate selector that emits a config intent and labels the route as non-promoted.

### Shared integration points

- `scripts/application/run_config.gd`: structural validation for supported milestones and exactly two distinct skill IDs.
- `scripts/application/run_runtime_facade.gd`: performs registry-backed loadout validation before starting the orchestrator.
- `scripts/application/run_runtime_host.gd`: applies the accepted config to the player before the first room begins.
- `scripts/player/player_controller.gd`: routes equipped weapon and time actions through the existing single action clock.
- `scripts/time_system/time_manager.gd`: exposes atomic can/try/cancel operations for all four time abilities.
- `scripts/time_system/time_rift.gd`: owns one rift source ID, affects bodies and enemy projectiles, and ends exactly once.
- `scripts/enemies/enemy_base.gd` and `scripts/enemies/enemy_projectile.gd`: track rift slow sources by ID and recompute the effective multiplier.
- `scripts/application/run_view_state_projector.gd`, `scripts/ui/contracts/run_view_state.gd`, `scripts/ui/views/combat_hud_view.gd`, and `scenes/ui/combat_hud_v2.tscn`: render two configuration-driven time slots.
- `scripts/main.gd` and `scenes/main.tscn`: preserve Quick Start and add a separately labelled candidate-lab entry.

---

### Task 1: Register authoritative loadout content

**Files:**
- Create: `data/content_packs/base/content/characters.json`
- Create: `data/content_packs/base/content/weapons.json`
- Create: `data/content_packs/base/content/time_abilities.json`
- Modify: `data/content_packs/base/pack.json`
- Modify: `data/content_packs/base/localization/translations.csv`
- Modify: `scripts/content/content_registry.gd`
- Test: `tests/contract/content_schema/loadout_catalog_contract_test.gd`
- Test: `tests/contract/content_schema/loadout_catalog_contract_test.tscn`

**Interfaces:**
- Consumes: Content Pack v2 definitions and `ContentRegistry.get_content()` / `get_by_category()`.
- Produces: five `character`, five `weapon`, and four `time_ability` definitions with stable IDs and milestone availability arrays.

- [ ] **Step 1: Write the failing catalog contract**

```gdscript
const EXPECTED_CHARACTERS := [
    "primordial_knight", "time_guardian", "time_lord", "void_walker", "wanderer",
]
const EXPECTED_WEAPONS := ["bow", "gauntlets", "gun", "staff", "sword"]
const EXPECTED_TIME_ABILITIES := ["accelerate", "rewind", "rift", "stop"]

func _assert_catalog(registry: RefCounted) -> void:
    _suite.assert_equal(_ids(registry.get_by_category(&"character")), EXPECTED_CHARACTERS, "five characters are canonical")
    _suite.assert_equal(_ids(registry.get_by_category(&"weapon")), EXPECTED_WEAPONS, "five weapons are canonical")
    _suite.assert_equal(_ids(registry.get_by_category(&"time_ability")), EXPECTED_TIME_ABILITIES, "four time abilities are canonical")
    _suite.assert_true(registry.get_content(&"sword")["availability"].has("M1"), "Sword remains M1")
    _suite.assert_true(not registry.get_content(&"bow")["availability"].has("M1"), "Bow does not leak into M1")
    _suite.assert_true(not registry.get_content(&"rift")["availability"].has("M1"), "Rift does not leak into M1")
    _suite.assert_true(not registry.get_content(&"accelerate")["availability"].has("M1"), "Accelerate does not leak into M1")
```

- [ ] **Step 2: Run the contract and verify the missing catalogs fail**

Run: `./tools/run_tests.sh --filter loadout_catalog_contract`

Expected: FAIL because the base pack has no character, weapon, or time-ability sources.

- [ ] **Step 3: Add the canonical definitions**

Use these exact IDs and availability boundaries:

```text
characters:
  wanderer: M1,CURRENT,NEXT,LAUNCH,EXPANSION
  time_guardian,void_walker,primordial_knight,time_lord: LAUNCH,EXPANSION
weapons:
  sword: M1,CURRENT,NEXT,LAUNCH,EXPANSION
  bow: NEXT,LAUNCH,EXPANSION
  gun,staff,gauntlets: LAUNCH,EXPANSION
time abilities:
  stop,rewind: M1,CURRENT,NEXT,LAUNCH,EXPANSION
  rift,accelerate: NEXT,LAUNCH,EXPANSION
```

Each entry uses its category, localized name/description keys, stable tags, empty compatibility, and empty effects. Update the registry so empty effects are accepted for identity categories while non-empty unsupported effects still fail closed through the effect catalog.

- [ ] **Step 4: Run content, localization, and catalog contracts**

Run:

```bash
./tools/run_tests.sh --filter loadout_catalog_contract
./tools/run_tests.sh --filter content_registry
./tools/run_tests.sh --filter content_pack_contract
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
```

Expected: all pass with exact `5 / 5 / 4` catalog counts and no missing localization keys.

- [ ] **Step 5: Commit the catalog boundary**

```bash
git add -- data/content_packs/base/content/characters.json data/content_packs/base/content/weapons.json data/content_packs/base/content/time_abilities.json data/content_packs/base/pack.json data/content_packs/base/localization/translations.csv scripts/content/content_registry.gd tests/contract/content_schema/loadout_catalog_contract_test.gd tests/contract/content_schema/loadout_catalog_contract_test.tscn
git diff --cached --check
git commit -m "feat(content): register canonical loadout catalog"
```

### Task 2: Validate run loadouts before authoritative mutation

**Files:**
- Create: `scripts/application/run_loadout_policy.gd`
- Create: `tests/unit/application/run_loadout_policy_test.gd`
- Create: `tests/unit/application/run_loadout_policy_test.tscn`
- Modify: `scripts/application/run_config.gd`
- Modify: `scripts/application/run_runtime_facade.gd`
- Modify: `tests/unit/application/contracts_test.gd`
- Modify: `tests/unit/application/run_runtime_facade_test.gd`

**Interfaces:**
- Consumes: normalized config and an active `ContentRegistry`.
- Produces: `validate(config, registry) -> CommandResult` with `context.loadout` containing deep-copied character, weapon, and two time-ability definitions.

- [ ] **Step 1: Write failing structural and registry-backed tests**

```gdscript
func _test_exactly_two_distinct_skills() -> void:
    var one := _config()
    one["enabled_time_skills"] = ["stop"]
    _suite.assert_equal(RunConfigScript.validate(one).code, &"INVALID_ARGUMENT", "one skill is rejected")
    var duplicate := _config()
    duplicate["enabled_time_skills"] = ["stop", "stop"]
    _suite.assert_equal(RunConfigScript.validate(duplicate).code, &"INVALID_ARGUMENT", "duplicate skills are rejected")

func _test_milestone_availability() -> void:
    _suite.assert_true(_policy.validate(_config(), _registry).ok, "M1 default validates")
    var bow_m1 := _config()
    bow_m1["weapon_id"] = "bow"
    _suite.assert_equal(_policy.validate(bow_m1, _registry).code, &"CONTENT_NOT_AVAILABLE", "M1 Bow is unavailable")
```

Also cover unknown IDs, wrong categories, Rift/Accelerate in M1, all three local candidate presets in `NEXT`, immutable result definitions, and failure before revision changes.

- [ ] **Step 2: Run the policy tests and verify failure**

Run: `./tools/run_tests.sh --filter run_loadout_policy`

Expected: FAIL because `RunLoadoutPolicy` does not exist and RunConfig accepts invalid skill arrays.

- [ ] **Step 3: Implement the policy**

```gdscript
class_name RunLoadoutPolicy
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")

func validate(config: Dictionary, registry: RefCounted):
    var milestone := str(config.get("milestone", ""))
    var character := _definition(registry, str(config.get("character_id", "")), "character", milestone)
    if character.is_empty():
        return _failure("character_id", config.get("character_id", ""))
    var weapon := _definition(registry, str(config.get("weapon_id", "")), "weapon", milestone)
    if weapon.is_empty():
        return _failure("weapon_id", config.get("weapon_id", ""))
    var skill_ids: Array = config.get("enabled_time_skills", [])
    if skill_ids.size() != 2 or str(skill_ids[0]) == str(skill_ids[1]):
        return CommandResultScript.failure(&"INVALID_ARGUMENT", 0, {"field": "enabled_time_skills"})
    var abilities: Array[Dictionary] = []
    for skill_id: Variant in skill_ids:
        var ability := _definition(registry, str(skill_id), "time_ability", milestone)
        if ability.is_empty():
            return _failure("enabled_time_skills", skill_id)
        abilities.append(ability)
    return CommandResultScript.success(0, {
        "loadout": {
            "character": character,
            "weapon": weapon,
            "time_abilities": abilities,
        },
    })
```

`RunRuntimeFacade.start_run()` must call the policy before `_orchestrator.start_run()`. Failure returns the policy error without changing phase, revision, room plan, or draft state.

- [ ] **Step 4: Run focused application tests**

Run:

```bash
./tools/run_tests.sh --filter run_loadout_policy
./tools/run_tests.sh --filter contracts_test
./tools/run_tests.sh --filter run_runtime_facade
```

Expected: all pass; failed loadouts leave the facade in HUB at its previous revision.

- [ ] **Step 5: Commit the policy boundary**

```bash
git add -- scripts/application/run_loadout_policy.gd scripts/application/run_config.gd scripts/application/run_runtime_facade.gd tests/unit/application/run_loadout_policy_test.gd tests/unit/application/run_loadout_policy_test.tscn tests/unit/application/contracts_test.gd tests/unit/application/run_runtime_facade_test.gd
git diff --cached --check
git commit -m "feat(runtime): validate authoritative run loadouts"
```

### Task 3: Apply equipped loadout to the player exactly once

**Files:**
- Create: `scripts/player/player_loadout_runtime.gd`
- Create: `tests/player/player_loadout_runtime_test.gd`
- Create: `tests/player/player_loadout_runtime_test.tscn`
- Modify: `scripts/application/run_runtime_host.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scenes/player/player.tscn`
- Modify: `tests/integration/application/run_runtime_host_test.gd`

**Interfaces:**
- Consumes: accepted normalized run config.
- Produces: `PlayerLoadoutRuntime.configure(config)`, `weapon_id()`, `time_ability_ids()`, `has_weapon(id)`, and `has_time_ability(id)`.

- [ ] **Step 1: Write failing loadout-isolation tests**

```gdscript
func _test_m1_equipment_isolation(player: Node) -> void:
    _suite.assert_true(player.configure_loadout(_config("sword", ["stop", "rewind"])), "M1 loadout applies")
    _suite.assert_true(player.try_action(&"attack"), "equipped Sword commits")
    player.cancel_transient_actions()
    _suite.assert_true(not player.try_action(&"ranged_attack"), "unequipped Bow is rejected")
    _suite.assert_true(not player.try_action(&"time_rift"), "unequipped Rift is rejected")
```

Cover reconfiguration clearing Bow charge, weapon cooldown, time cooldowns, Rift instances, acceleration, and buffered inputs before the second run.

- [ ] **Step 2: Run and verify the tests fail**

Run: `./tools/run_tests.sh --filter player_loadout_runtime`

Expected: FAIL because the Player has no authoritative loadout component and M1 ranged input can begin Bow charge.

- [ ] **Step 3: Implement loadout activation and host sequencing**

`RunRuntimeHost.start_run()` must:

1. validate and start through the facade;
2. obtain the accepted config from the fresh authoritative snapshot;
3. call `player.configure_loadout(config)` before creating or beginning `RoomRuntime`;
4. fail the run with `LOADOUT_APPLY_FAILED` if player activation fails;
5. publish `run_started` only after player activation and first-room initialization succeed according to the existing lifecycle contract.

The controller must route all weapon inputs through `try_action()` and consult `PlayerLoadoutRuntime` before any weapon or time-manager method is called.

- [ ] **Step 4: Run host, action, and event regressions**

Run:

```bash
./tools/run_tests.sh --filter player_loadout_runtime
./tools/run_tests.sh --filter run_runtime_host
./tools/run_tests.sh --filter player_action_runtime
./tools/run_tests.sh --filter combat_event_publication
```

Expected: all pass; the default M1 run cannot use Bow, Rift, or Accelerate.

- [ ] **Step 5: Commit player activation**

```bash
git add -- scripts/player/player_loadout_runtime.gd scripts/player/player_controller.gd scenes/player/player.tscn scripts/application/run_runtime_host.gd tests/player/player_loadout_runtime_test.gd tests/player/player_loadout_runtime_test.tscn tests/integration/application/run_runtime_host_test.gd
git diff --cached --check
git commit -m "feat(player): activate equipped loadouts"
```

### Task 4: Route Rift and Accelerate through the single action clock

**Files:**
- Create: `tests/time/time_loadout_runtime_test.gd`
- Create: `tests/time/time_loadout_runtime_test.tscn`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/time_system/time_manager.gd`
- Modify: `scripts/time_system/time_rift.gd`
- Modify: `scripts/enemies/enemy_base.gd`
- Modify: `scripts/enemies/enemy_projectile.gd`
- Modify: `tests/player/player_action_runtime_test.gd`
- Modify: `tests/contract/events/combat_event_publication_test.gd`

**Interfaces:**
- Consumes: equipped time-ability IDs and the existing `PlayerActionState.TIME_CAST` transition.
- Produces: atomic `can_use(skill_id, context)` / `try_use(skill_id, context)` / `cancel_all_time_effects(reason)` behavior for all four abilities.

- [ ] **Step 1: Write the failing six-combination matrix**

```gdscript
const LOADOUTS := [
    ["stop", "rewind"],
    ["stop", "rift"],
    ["stop", "accelerate"],
    ["rewind", "rift"],
    ["rewind", "accelerate"],
    ["rift", "accelerate"],
]

func _assert_equipped_pair(player: Node, equipped: Array[String]) -> void:
    for ability_id: String in ["stop", "rewind", "rift", "accelerate"]:
        var committed := player.try_action(StringName("time_" + ability_id))
        _suite.assert_equal(committed, equipped.has(ability_id), "%s follows equipped state" % ability_id)
        player.cancel_transient_actions()
```

Add targeted tests for recovery buffering, no active-frame skip, insufficient energy, cooldown rejection, death rejection, Rift projectile slowing, overlapping Rift source recomputation, and stale timer cleanup.

- [ ] **Step 2: Run the matrix and verify candidate actions fail**

Run: `./tools/run_tests.sh --filter time_loadout_runtime`

Expected: FAIL because Rift and Accelerate remain rejected by `PlayerController.try_action()`.

- [ ] **Step 3: Implement generic time-skill dispatch**

Use canonical IDs `stop`, `rewind`, `rift`, and `accelerate` in config/content, while preserving EventBus fact IDs `time_stop`, `time_rewind`, `time_rift`, and `time_accelerate` for the existing typed contract. `PlayerController` maps the canonical equipped ID to the existing action ID and commits through `_request_time_skill()`.

Rift uses a unique source ID:

```gdscript
func apply_time_rift(source_id: StringName, multiplier: float) -> void:
    _rift_sources[source_id] = clampf(multiplier, 0.1, 1.0)
    _recompute_rift_slow()

func clear_time_rift(source_id: StringName) -> void:
    _rift_sources.erase(source_id)
    _recompute_rift_slow()
```

The Rift scene connects both body and area enter/exit signals so enemy projectiles receive and release the same source. Expiration and cancellation share one idempotent end path that publishes one `time_skill_ended` fact.

Accelerate uses an effect token and explicit cancellation. A stale timer may not clear a later effect or publish a duplicate end fact.

- [ ] **Step 4: Run time, player, event, and cleanup tests**

Run:

```bash
./tools/run_tests.sh --filter time_loadout_runtime
./tools/run_tests.sh --filter player_action_runtime
./tools/run_tests.sh --filter time_stop_resistance
./tools/run_tests.sh --filter combat_event_publication
```

Expected: all six pairs commit only their two equipped abilities; rejected abilities leave energy, cooldowns, nodes, and facts unchanged.

- [ ] **Step 5: Commit the four-ability runtime**

```bash
git add -- scripts/player/player_controller.gd scripts/time_system/time_manager.gd scripts/time_system/time_rift.gd scripts/enemies/enemy_base.gd scripts/enemies/enemy_projectile.gd tests/time/time_loadout_runtime_test.gd tests/time/time_loadout_runtime_test.tscn tests/player/player_action_runtime_test.gd tests/contract/events/combat_event_publication_test.gd
git diff --cached --check
git commit -m "feat(time): complete candidate ability runtime"
```

### Task 5: Make the HUD render two data-driven ability slots

**Files:**
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/application/run_view_state_projector.gd`
- Modify: `scripts/ui/contracts/run_view_state.gd`
- Modify: `scripts/ui/views/combat_hud_view.gd`
- Modify: `scenes/ui/combat_hud_v2.tscn`
- Modify: `scripts/ui/fixtures/run_view_state_fixtures.gd`
- Modify: `tests/fixtures/ui/hud_combat.json`
- Modify: `tests/fixtures/ui/hud_low_hp.json`
- Modify: `tests/fixtures/ui/hud_boss.json`
- Modify: `tests/ui/run_view_state_contract_test.gd`
- Modify: `tests/ui/combat_hud_v2_scene_test.gd`

**Interfaces:**
- Consumes: player snapshot `time_slots: [{ability_id, action_id, cooldown}]` with exactly two entries.
- Produces: validated immutable ViewState and two localized HUD slot labels.

- [ ] **Step 1: Write failing ViewState and HUD tests**

```gdscript
var player := fixture["player"] as Dictionary
player["time_slots"] = [
    {"ability_id": "stop", "action_id": "time_stop", "cooldown": 0.0},
    {"ability_id": "rift", "action_id": "time_rift", "cooldown": 4.5},
]
_suite.assert_true(hud.render(fixture).ok, "candidate slots render")
_suite.assert_true(hud.skill_slot_labels[0].text.contains(tr("TIME_ABILITY_STOP_NAME")), "first slot is localized")
_suite.assert_true(hud.skill_slot_labels[1].text.contains(tr("TIME_ABILITY_RIFT_NAME")), "second slot is localized")
```

Reject missing, duplicate, unknown, or more-than-two slot definitions at the ViewState boundary.

- [ ] **Step 2: Run UI contracts and verify hard-coded labels fail**

Run:

```bash
./tools/run_tests.sh --filter run_view_state_contract
./tools/run_tests.sh --filter combat_hud_v2_scene
```

Expected: FAIL because the HUD owns fixed Stop/Rewind labels and the player snapshot has no slot metadata.

- [ ] **Step 3: Implement the generic slot contract**

`PlayerController.get_player_ui_snapshot()` returns two slots in configured order. `RunViewState.validate()` requires exactly two distinct `ability_id` and `action_id` values with non-negative cooldowns. `CombatHudView` maps each canonical ID to `TIME_ABILITY_<ID>_NAME` and preserves the existing ready/cooldown wording.

- [ ] **Step 4: Run HUD, localization, and pixel-canvas regressions**

Run:

```bash
./tools/run_tests.sh --filter run_view_state_contract
./tools/run_tests.sh --filter combat_hud_v2_scene
./tools/run_tests.sh --filter pixel_canvas
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
```

Expected: all pass at 640×360 in English and Chinese.

- [ ] **Step 5: Commit data-driven HUD slots**

```bash
git add -- scripts/player/player_controller.gd scripts/application/run_view_state_projector.gd scripts/ui/contracts/run_view_state.gd scripts/ui/views/combat_hud_view.gd scenes/ui/combat_hud_v2.tscn scripts/ui/fixtures/run_view_state_fixtures.gd tests/fixtures/ui/hud_combat.json tests/fixtures/ui/hud_low_hp.json tests/fixtures/ui/hud_boss.json tests/ui/run_view_state_contract_test.gd tests/ui/combat_hud_v2_scene_test.gd
git diff --cached --check
git commit -m "feat(ui): render equipped time ability slots"
```

### Task 6: Add a controller-safe local candidate lab

**Files:**
- Create: `scripts/ui/candidate_loadout_panel.gd`
- Create: `scenes/ui/candidate_loadout_panel.tscn`
- Create: `tests/ui/candidate_loadout_panel_test.gd`
- Create: `tests/ui/candidate_loadout_panel_test.tscn`
- Modify: `scripts/main.gd`
- Modify: `scenes/main.tscn`
- Modify: `data/localization/translations.csv`
- Modify: `tests/integration/ui/controller_focus_flow_test.gd`
- Modify: `tests/smoke/m1_runtime_smoke_test.gd`

**Interfaces:**
- Consumes: three frozen candidate presets and FocusCoordinator.
- Produces: `candidate_requested(config: Dictionary)`; caller receives a deep copy and launches milestone `NEXT` without changing Quick Start defaults.

- [ ] **Step 1: Write failing candidate-panel tests**

The panel exposes these exact presets:

```text
Bow Candidate: wanderer + bow + stop + rewind
Rift Candidate: wanderer + sword + stop + rift
Accelerate Candidate: wanderer + sword + stop + accelerate
```

Tests assert:

- the title and warning explicitly say Candidate / 未正式晋升;
- opening focuses the first preset;
- controller navigation forms a closed ring through all presets and Back;
- emitted configs use milestone `NEXT` and are deep copies;
- closing restores focus to the Candidate Lab button;
- Quick Start still builds the exact M1 default config.

- [ ] **Step 2: Run panel and M1 smoke tests and verify failure**

Run:

```bash
./tools/run_tests.sh --filter candidate_loadout_panel
./tools/run_tests.sh --filter controller_focus_flow
./tools/run_tests.sh --filter m1_runtime_smoke
```

Expected: the panel test fails because no candidate UI exists; M1 smoke remains green before implementation.

- [ ] **Step 3: Implement the isolated candidate entry**

Add a `Candidate Lab` button below Quick Start. It opens the panel but never changes `_build_run_config()`. Candidate selection passes its config to the same `RunRuntimeHost.start_run()` path and closes the panel only after a successful start. Rejection leaves the panel open with a localized failure message.

- [ ] **Step 4: Run controller, accessibility, M1, and candidate tests**

Run:

```bash
./tools/run_tests.sh --filter candidate_loadout_panel
./tools/run_tests.sh --filter controller_focus_flow
./tools/run_tests.sh --filter accessibility_settings_flow
./tools/run_tests.sh --filter m1_runtime_smoke
```

Expected: all pass; M1 config and candidate configs remain separate.

- [ ] **Step 5: Commit the candidate lab**

```bash
git add -- scripts/ui/candidate_loadout_panel.gd scenes/ui/candidate_loadout_panel.tscn scripts/main.gd scenes/main.tscn data/localization/translations.csv tests/ui/candidate_loadout_panel_test.gd tests/ui/candidate_loadout_panel_test.tscn tests/integration/ui/controller_focus_flow_test.gd tests/smoke/m1_runtime_smoke_test.gd
git diff --cached --check
git commit -m "feat(ui): add local candidate loadout lab"
```

### Task 7: Certify six time pairs and preserve exactly-once facts

**Files:**
- Create: `tests/smoke/time_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/time_loadout_matrix_smoke_test.tscn`
- Modify: `tests/contract/events/combat_event_publication_test.gd`
- Modify: `tools/test_ci_contract.sh`
- Modify: `tools/validate_project.sh` only if stable discovery requires an explicit contract update

**Interfaces:**
- Consumes: all six unordered time-ability pairs through milestone `NEXT`.
- Produces: a deterministic smoke result proving both equipped abilities commit, both unequipped abilities reject, and lifecycle facts remain exactly once.

- [ ] **Step 1: Write the failing six-pair smoke test**

For every pair:

1. create a fresh Player and configure the pair;
2. supply a rewind snapshot when the pair contains Rewind;
3. commit each equipped ability once;
4. assert the other two actions reject;
5. assert exactly one start and one end fact for each committed ability;
6. assert rejected actions publish zero facts;
7. cancel/free the fixture and assert no Rift node, acceleration state, timer callback, or ObjectDB leak remains.

- [ ] **Step 2: Run the matrix and verify any lifecycle gaps fail**

Run: `./tools/run_tests.sh --filter time_loadout_matrix_smoke`

Expected: FAIL until all four ability cleanup and fact paths meet the shared contract.

- [ ] **Step 3: Repair only observed matrix defects**

Do not introduce a second event recorder or generic bus. Fix the semantic commit/end path that caused each failure, then rerun the single pair before rerunning all six.

- [ ] **Step 4: Run focused and unified verification**

Run:

```bash
./tools/run_tests.sh --filter loadout_catalog_contract
./tools/run_tests.sh --filter run_loadout_policy
./tools/run_tests.sh --filter player_loadout_runtime
./tools/run_tests.sh --filter time_loadout_runtime
./tools/run_tests.sh --filter time_loadout_matrix_smoke
./tools/run_tests.sh --filter candidate_loadout_panel
./tools/run_tests.sh --filter combat_event_publication
./tools/run_tests.sh --filter m1_runtime_smoke
VALIDATION_LOG_DIR=/tmp/planewalker-p10a-validation ./tools/validate_project.sh
git diff --check
```

Expected: every focused test and the full stable scene inventory pass; the only allowed warning remains the registered `reward_system_smoke` ObjectDB warning.

- [ ] **Step 5: Commit matrix certification**

```bash
git add -- tests/smoke/time_loadout_matrix_smoke_test.gd tests/smoke/time_loadout_matrix_smoke_test.tscn tests/contract/events/combat_event_publication_test.gd tools/test_ci_contract.sh tools/validate_project.sh
git diff --cached --check
git commit -m "test(loadout): certify candidate time matrix"
```

### Task 8: Publish truthful P10A evidence

**Files:**
- Create: `docs/current/2026-09-29-p10-candidate-loadouts-evidence.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Modify: `docs/superpowers/plans/2026-09-29-plane-walker-p10-candidate-loadouts.md`
- Test: `tests/contract/documentation/test_document_governance.py`

**Interfaces:**
- Consumes: exact commits, focused logs, unified validation log, and candidate matrix results.
- Produces: `Verified Locally / Current` evidence while the implementation plan becomes `Completed / Historical`.

- [ ] **Step 1: Record exact evidence without promotion language**

The evidence must state:

- P10A candidate loadouts are implemented and locally verified;
- Quick Start and M1 evidence remain unchanged;
- Bow/Rift/Accelerate are not formally promoted to Current;
- authentic playtest evidence remains `0 / 20`;
- line coverage, export templates, packaged startup, signing, platform credentials, and publication remain pending where applicable.

- [ ] **Step 2: Run documentation governance**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.documentation.test_document_governance
PYTHONDONTWRITEBYTECODE=1 python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
```

Expected: zero violations, zero baselined, zero new, zero stale.

- [ ] **Step 3: Run final repository validation and inspect status**

Run:

```bash
VALIDATION_LOG_DIR=/tmp/planewalker-p10a-final ./tools/validate_project.sh
git diff --check
git status --short
```

Expected: full validation passes and only the P10A evidence/status files remain uncommitted.

- [ ] **Step 4: Commit P10A certification**

```bash
git add -- docs/current/2026-09-29-p10-candidate-loadouts-evidence.md docs/README.md docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md docs/superpowers/plans/2026-09-29-plane-walker-p10-candidate-loadouts.md tests/contract/documentation/test_document_governance.py
git diff --cached --check
git commit -m "docs(loadout): certify P10 candidate lab"
```

## Plan Self-Review

- Scope coverage: authoritative IDs, availability, validation, runtime activation, four time abilities, M1 Bow isolation, HUD, controller UI, six time pairs, exactly-once facts, and truthful evidence all have explicit tasks.
- Dependency order: catalogs precede policy; policy precedes player mutation; player activation precedes candidate abilities and UI; matrix certification follows all runtime work.
- Shared ownership: `run_runtime_host.gd`, `player_controller.gd`, the base pack manifest, and shared ViewState contracts have one integration owner per task.
- Type consistency: content IDs are `stop`, `rewind`, `rift`, and `accelerate`; input/fact IDs remain `time_stop`, `time_rewind`, `time_rift`, and `time_accelerate` through an explicit mapping.
- Evidence integrity: no task changes formal M1 status or invents human, export, coverage, platform, signing, or publication evidence.
- Placeholder scan: every task contains concrete files, commands, assertions, and completion criteria.
