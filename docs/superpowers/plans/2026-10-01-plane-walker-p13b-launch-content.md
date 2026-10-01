# Plane Walker P13B Complete Launch Pools Implementation Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: Executable P13B work breakdown under the approved P13B Launch Content Design
- Applies To: Exact `50 / 28 / 18 / 15` Launch pools, typed effects, atomic reward selection, active items, live talents, drafting, UI, Replay, simulations, and certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-01-plane-walker-p13b-launch-content-design.md`, `docs/current/2026-10-01-p13a-launch-archetype-authority-evidence.md`, `docs/contracts/content-pack-v2.md`
- Last Verified: 2026-10-01
- Implementation Status: Task 1 is next; P13A authority is certified at `4fbf9b1`, and no P13B runtime or count completion is claimed yet
- Exit Gate: Exact Launch counts, every effect executable and bounded, reward selection atomic, eight active items player-facing, fifteen talents data-authoritative and live-installable, deterministic drafting/build formation/Replay, 150-loadout regression, and full repository validation pass

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the exact complete Launch item, blessing, curse, and talent pools through one typed effect and reward-transaction authority without changing the frozen M1/CURRENT/NEXT behavior.

**Architecture:** ContentRegistry validates category-specific item mode and active-handler fields plus a closed scalar effect catalog. `PlayerRewardEffectRuntime` prepares and atomically commits persistent and trigger effects; `ActiveItemRuntime` owns one equipped active item; character talents consume versioned definition values. RunRuntimeFacade and RunRuntimeHost use a reserve/apply/commit transaction so BuildState and live player state cannot diverge.

**Tech Stack:** Godot 4.6.1, typed GDScript, JSON Schema Draft 2020-12, Content Pack v2, deterministic SeedService channels, CSV localization, scene-based unit/contract/integration tests, Python content contracts, and local Git commits.

## Global Constraints

- Exact Launch counts are `50 items`, `28 blessings`, `18 curses`, and `15 talents`; items split into `42 passive` and `8 active`.
- The only top-level build archetypes remain the exact P13A eight in approved order.
- M1/CURRENT/NEXT remain restricted to `freeze_burst`, `rewind_echo`, and `accelerated_combo` plus explicit utility content.
- The fifteen P12 character talent identities remain exact and cannot be replaced by a competing talent catalog.
- Every added effect requires bounds, stack rule, category allow-list, one live consumer, focused tests, UI summary, and deterministic snapshot behavior.
- One active item is equipped at a time. Replacement is explicit and reversible.
- Reward selection is atomic across player state, BuildState, offer consumption, and exactly-once event publication.
- Formal status remains `M1 Candidate — External Validation Pending`; authentic human playtests remain `0 / 20`.
- P13B does not claim line coverage, installed export templates, packaged startup, signing, remote push, store configuration, or publication.

---

### Task 1: Close Launch pool schema and exact identity contract

**Files:**
- Modify: `data/schemas/content_entry_v2.schema.json`
- Create: `scripts/items/active_item_definition.gd`
- Modify: `scripts/content/content_registry.gd`
- Create: `tests/contract/content_schema/launch_pool_contract_test.gd`
- Create: `tests/contract/content_schema/launch_pool_contract_test.tscn`
- Modify: `tests/contract/content_schema/content_pack_contract_test.gd`
- Modify: `tests/contract/content_schema/content_registry_test.gd`
- Modify: `tools/validate_project.sh`

**Interfaces:**
- Consumes: exact IDs and category rules in the approved P13B design.
- Produces: `ActiveItemDefinition.configure(definition) -> Dictionary`, `snapshot() -> Dictionary`, category-specific item validation, and one executable exact-count contract.

- [ ] **Step 1: Write failing exact-count and active-field tests**

The Launch pool test must define the exact ID arrays from P13B §3 and assert:

```gdscript
suite.assert_equal(items.size(), 50, "Launch has exactly fifty items")
suite.assert_equal(items.filter(func(row): return row["item_mode"] == "passive").size(), 42, "forty-two passive items")
suite.assert_equal(items.filter(func(row): return row["item_mode"] == "active").size(), 8, "eight active items")
suite.assert_equal(blessings.size(), 28, "Launch has exactly twenty-eight blessings")
suite.assert_equal(curses.size(), 18, "Launch has exactly eighteen curses")
suite.assert_equal(talents.size(), 15, "Launch keeps exactly fifteen talents")
```

Mutation cases must reject active fields on passive/non-item entries, missing handler, unknown handler, cooldown outside `1..3600`, non-scalar parameters, script-like values, active item without one archetype, passive item tagged active, and exact-ID drift.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter "launch_pool_contract|content_pack_contract|content_registry"
```

Expected: FAIL because item-mode and active-handler fields do not exist and the Launch pools are incomplete.

- [ ] **Step 3: Implement the closed active definition parser**

`ActiveItemDefinition` requires these fields and rejects every unknown field after generic content normalization:

```gdscript
const HANDLER_IDS := [
	"absolute_zero", "paradox_beacon", "gravity_snare", "redline_injector",
	"blood_price", "aegis_reversal", "railshot", "army_of_yesterday",
]

func snapshot() -> Dictionary:
	return {
		"id": _id,
		"archetype": _archetype,
		"active_handler_id": _handler_id,
		"cooldown_frames": _cooldown_frames,
		"active_parameters": _parameters.duplicate(true),
	}
```

Add `item_mode`, `active_handler_id`, `cooldown_frames`, and `active_parameters` to the generic schema and Registry allow-list. The Registry invokes this parser only for active items and rejects active-only fields everywhere else.

- [ ] **Step 4: Run parser and schema GREEN without weakening the expected count failure**

```bash
./tools/run_tests.sh --filter "content_pack_contract|content_registry"
./tools/run_tests.sh --filter launch_pool_contract
```

Expected: schema/Registry cases PASS; exact Launch count cases still FAIL until Tasks 3–6 populate the pools.

- [ ] **Step 5: Commit**

```bash
git add -- data/schemas/content_entry_v2.schema.json scripts/items/active_item_definition.gd scripts/content/content_registry.gd tests/contract/content_schema/launch_pool_contract_test.gd tests/contract/content_schema/launch_pool_contract_test.tscn tests/contract/content_schema/content_pack_contract_test.gd tests/contract/content_schema/content_registry_test.gd tools/validate_project.sh
git commit -m "feat(content): close launch pool contract"
```

---

### Task 2: Build typed effect plans and atomic reward selection

**Files:**
- Modify: `data/content/effect_catalog.json`
- Modify: `scripts/content/effects/effect_definition.gd`
- Modify: `scripts/content/effects/effect_handler_catalog.gd`
- Create: `scripts/items/player_reward_effect_runtime.gd`
- Modify: `scripts/items/item_effect.gd`
- Modify: `scripts/application/run_runtime_facade.gd`
- Modify: `scripts/application/run_runtime_host.gd`
- Modify: `scripts/application/run_orchestrator.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `tests/unit/content/effect_handler_catalog_test.gd`
- Create: `tests/unit/items/player_reward_effect_runtime_test.gd`
- Create: `tests/unit/items/player_reward_effect_runtime_test.tscn`
- Modify: `tests/integration/application/run_runtime_host_test.gd`
- Modify: `tests/reward_system_smoke.gd`

**Interfaces:**
- Consumes: normalized content definition and immutable player/run snapshots.
- Produces: `prepare(definition, player_snapshot)`, `commit(plan, player)`, `rollback(receipt, player)`, `reserve_selection()`, `commit_reserved_selection()`, and `cancel_reserved_selection()`.

- [ ] **Step 1: Write failure-injection tests**

Cover invalid effect, missing target, non-finite value, capability rejection, trigger failure, authoritative commit failure, transition failure, duplicate submit, stale revision, rollback failure, and exactly-once event publication. Every failure asserts the offer, player snapshot, BuildState, revision, and published facts equal the pre-selection values.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter "effect_handler_catalog|player_reward_effect_runtime|run_runtime_host|reward_system_smoke"
```

- [ ] **Step 3: Add effect runtime domains**

Every effect-catalog row gains one closed `runtime_domain`:

```text
stats | health | time | weapon | character | trigger
```

`PlayerRewardEffectRuntime.prepare()` sorts effect IDs, validates catalog bounds/category/domain, stages persistent domains before triggers, and returns a digest-sealed plan. `commit()` records reversible before-values for every persistent domain; trigger effects execute only after persistent commits. `rollback()` restores in reverse order and verifies the exact pre-snapshot.

- [ ] **Step 4: Split selection into reserve/apply/commit**

`RunRuntimeFacade.reserve_selection(offer_id, option_id, revision)` resolves but does not consume. Host prepares and commits the player plan, then calls `commit_reserved_selection(reservation_id)`. Any failure calls `cancel_reserved_selection()` and effect rollback. EventBus publishes only after both commits and transition success.

- [ ] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter "effect_handler_catalog|item_effect|player_reward_effect_runtime|run_authority_contract|run_runtime_host|reward_system_smoke"
git diff --check
git add -- data/content/effect_catalog.json scripts/content/effects/effect_definition.gd scripts/content/effects/effect_handler_catalog.gd scripts/items/player_reward_effect_runtime.gd scripts/items/item_effect.gd scripts/application/run_runtime_facade.gd scripts/application/run_runtime_host.gd scripts/application/run_orchestrator.gd scripts/player/player_controller.gd tests/unit/content/effect_handler_catalog_test.gd tests/unit/items/player_reward_effect_runtime_test.gd tests/unit/items/player_reward_effect_runtime_test.tscn tests/integration/application/run_runtime_host_test.gd tests/reward_system_smoke.gd
git commit -m "feat(rewards): apply content effects atomically"
```

---

### Task 3: Populate and execute the exact fifty-item pool

**Files:**
- Modify: `data/content_packs/base/content/items.json`
- Modify: `data/items/mvp_items.json`
- Modify: `data/content/effect_catalog.json`
- Modify: `data/content_packs/base/localization/translations.csv`
- Modify: `data/localization/translations.csv`
- Modify: `data/content_packs/base/pack.json`
- Modify: `scripts/items/item_effect.gd`
- Modify: `tests/contract/content_schema/launch_pool_contract_test.gd`
- Modify: `tests/unit/items/item_effect_test.gd`
- Create: `tests/integration/items/launch_passive_item_execution_test.gd`
- Create: `tests/integration/items/launch_passive_item_execution_test.tscn`

**Interfaces:**
- Consumes: Task 1 item schema and Task 2 effect transaction.
- Produces: exact 42 passive identities with executable effects plus eight schema-valid active identities reserved for Task 7 runtime activation.

- [ ] **Step 1: Add failing exact-ID, role, coverage, and execution tests**

Tests read the exact §3.1 IDs, assert `42 passive / 8 active`, one active per archetype, six exact utilities, all route item roles, localization, manifest hash, non-empty passive effects, and at least one observed state change for every passive item on a compatible Launch player fixture.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter "launch_pool_contract|item_effect|launch_passive_item_execution"
```

- [ ] **Step 3: Author the thirty missing item definitions and migrate the twenty existing rows**

Use the exact IDs, route, role, and P/A classification from P13B §3.1. Existing utility entries add `generalist`, `utility`, and `passive`; existing route items add `passive`; all approved earlier availability values remain and Launch/Expansion are appended. New passives use only cataloged effects with a live compatible target. Active rows carry their Task 1 handler metadata and no passive-only trigger.

- [ ] **Step 4: Add localized player-facing copy and effect summaries**

Both translation catalogs receive exact name/description keys plus any new `EFFECT_<ID>` summaries. Descriptions state trigger, benefit, cost, duration/cooldown, and cap without exposing internal IDs.

- [ ] **Step 5: Update integrity hash, run GREEN, and commit**

```bash
./tools/run_tests.sh --filter "launch_pool_contract|content_registry|content_pack_contract|effect_handler_catalog|item_effect|launch_passive_item_execution|draft_service"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
git diff --check
git add -- data/content_packs/base/content/items.json data/items/mvp_items.json data/content/effect_catalog.json data/content_packs/base/localization/translations.csv data/localization/translations.csv data/content_packs/base/pack.json scripts/items/item_effect.gd tests/contract/content_schema/launch_pool_contract_test.gd tests/unit/items/item_effect_test.gd tests/integration/items/launch_passive_item_execution_test.gd tests/integration/items/launch_passive_item_execution_test.tscn
git commit -m "feat(items): complete launch item pool"
```

---

### Task 4: Complete twenty-eight blessings and eighteen curses

**Files:**
- Modify: `data/content_packs/base/content/blessings.json`
- Modify: `data/content_packs/base/content/curses.json`
- Modify: `data/blessings/mvp_blessings.json`
- Modify: `data/curses/mvp_curses.json`
- Modify: `data/content/effect_catalog.json`
- Modify: `data/content_packs/base/localization/translations.csv`
- Modify: `data/localization/translations.csv`
- Modify: `data/content_packs/base/pack.json`
- Modify: `tests/contract/content_schema/launch_pool_contract_test.gd`
- Create: `tests/integration/items/launch_blessing_curse_execution_test.gd`
- Create: `tests/integration/items/launch_blessing_curse_execution_test.tscn`

**Interfaces:**
- Consumes: Task 2 atomic effect runtime and exact IDs in P13B §3.2–3.3.
- Produces: twenty-eight positive persistent blessing definitions and eighteen bounded tradeoff curse definitions.

- [ ] **Step 1: Write failing count, route, tradeoff, and execution tests**

For each route assert at least one blessing starter, two blessing payoffs across combined content, exactly two route curses with role `risk`, and at least one positive plus one negative normalized effect per curse. General entries require empty archetype plus `generalist + utility`.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter "launch_pool_contract|launch_blessing_curse_execution"
```

- [ ] **Step 3: Author exact blessing and curse catalogs**

Use the exact §3.2 and §3.3 IDs. Migrate the four existing blessings and six existing curses without changing approved M1 behavior. Every new scalar effect is added to the catalog with bounded values and a live Task 2 runtime domain in the same diff.

- [ ] **Step 4: Add localization and update manifest hashes**

Both translation catalogs and Base Pack hashes must match current bytes. Copy must state curse upside and downside separately and never imply a Boss hard-control effect.

- [ ] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter "launch_pool_contract|content_registry|content_pack_contract|effect_handler_catalog|launch_blessing_curse_execution|launch_draft_archetype"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
git diff --check
git add -- data/content_packs/base/content/blessings.json data/content_packs/base/content/curses.json data/blessings/mvp_blessings.json data/curses/mvp_curses.json data/content/effect_catalog.json data/content_packs/base/localization/translations.csv data/localization/translations.csv data/content_packs/base/pack.json tests/contract/content_schema/launch_pool_contract_test.gd tests/integration/items/launch_blessing_curse_execution_test.gd tests/integration/items/launch_blessing_curse_execution_test.tscn
git commit -m "feat(content): complete blessing and curse pools"
```

---

### Task 5: Make all fifteen character talents data-authoritative and live-installable

**Files:**
- Modify: `data/content_packs/base/content/talents.json`
- Modify: `data/content/effect_catalog.json`
- Modify: `data/content_packs/base/pack.json`
- Modify: `scripts/player/characters/character_talent_state.gd`
- Modify: `scripts/player/characters/player_character_runtime.gd`
- Modify: each file under `scripts/player/characters/*_character_runtime.gd` that configures `CharacterTalentState`
- Modify: `scripts/player/player_loadout_runtime.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/application/run_loadout_policy.gd`
- Modify: `scripts/rewards/draft_service.gd`
- Modify: `tests/characters/character_talent_state_test.gd`
- Modify: `tests/contract/content_schema/character_runtime_profile_ingestion_test.gd`
- Modify: `tests/unit/application/run_loadout_policy_test.gd`
- Modify: `tests/unit/rewards/draft_service_test.gd`
- Create: `tests/integration/characters/live_talent_installation_test.gd`
- Create: `tests/integration/characters/live_talent_installation_test.tscn`

**Interfaces:**
- Consumes: selected talent definitions resolved by ContentRegistry.
- Produces: `CharacterTalentState.configure(character_id, selected_ids, definitions)`, `install_talent(definition)`, content-derived modifier snapshots, and character-filtered talent offers.

- [ ] **Step 1: Write failing content/runtime parity tests**

For all fifteen talents assert exact character scope, non-empty bounded effects, canonical order, baseline-to-selected modifier delta, forty subsets, live install, duplicate rejection, cross-character rejection, rollback, snapshot, Replay, reset, and content mutation detection.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter "character_talent_state|character_runtime_profile_ingestion|run_loadout_policy|draft_service|live_talent_installation"
```

- [ ] **Step 3: Move selected talent values into content definitions**

Add talent-only effect IDs for every selected modifier delta. `CharacterTalentState` keeps immutable per-character baseline maps, applies selected content effect values in canonical order, and rejects any effect not in that character's closed allow-list. Remove `selected.has(...)` value duplication after parity tests pass.

- [ ] **Step 4: Route definitions through loadout and reward paths**

`RunLoadoutPolicy` resolves exact definitions for selected loadout talents. `DraftService` filters talent offers to `state_snapshot.config.character_id`. `PlayerCharacterRuntime.install_talent()` prepares a replacement talent state and swaps only after the strategy accepts the new snapshot.

- [ ] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter "character_talent_state|character_runtime_profile_ingestion|run_loadout_policy|draft_service|live_talent_installation|character_runtime_replay"
git diff --check
git add -- data/content_packs/base/content/talents.json data/content/effect_catalog.json data/content_packs/base/pack.json scripts/player/characters/character_talent_state.gd scripts/player/characters/player_character_runtime.gd scripts/player/characters/wanderer_character_runtime.gd scripts/player/characters/time_guardian_character_runtime.gd scripts/player/characters/void_walker_character_runtime.gd scripts/player/characters/primordial_knight_character_runtime.gd scripts/player/characters/time_lord_character_runtime.gd scripts/player/player_loadout_runtime.gd scripts/player/player_controller.gd scripts/application/run_loadout_policy.gd scripts/rewards/draft_service.gd tests/characters/character_talent_state_test.gd tests/contract/content_schema/character_runtime_profile_ingestion_test.gd tests/unit/application/run_loadout_policy_test.gd tests/unit/rewards/draft_service_test.gd tests/integration/characters/live_talent_installation_test.gd tests/integration/characters/live_talent_installation_test.tscn
git commit -m "feat(talents): source launch modifiers from content"
```

---

### Task 6: Implement eight active items, input, HUD, feedback, and replacement

**Files:**
- Create: `scripts/items/active_item_runtime.gd`
- Create: `scripts/items/active_item_handlers.gd`
- Modify: `scripts/player/player_controller.gd`
- Modify: `scripts/player/player_loadout_runtime.gd`
- Modify: `scripts/input/input_profile_store.gd`
- Modify: `scripts/input/input_remap_service.gd`
- Modify: `project.godot`
- Modify: `scripts/application/run_view_state_projector.gd`
- Modify: `scripts/ui/contracts/run_view_state.gd`
- Modify: `scripts/ui/views/combat_hud_view.gd`
- Modify: `scenes/ui/combat_hud_v2.tscn`
- Modify: `autoload/combat_feedback.gd`
- Modify: `scripts/presentation/pixel_proxy_actor.gd`
- Create: `tests/unit/items/active_item_runtime_test.gd`
- Create: `tests/unit/items/active_item_runtime_test.tscn`
- Create: `tests/integration/items/active_item_player_integration_test.gd`
- Create: `tests/integration/items/active_item_player_integration_test.tscn`
- Modify: `tests/contract/input/input_contract_test.gd`
- Modify: `tests/ui/combat_hud_v2_scene_test.gd`
- Modify: `tests/ui/run_view_state_contract_test.gd`

**Interfaces:**
- Consumes: active item definition and semantic `active_item` intent.
- Produces: deterministic plan/commit/cooldown state, one equipped slot, replacement decision, localized HUD state, and accessible feedback cues.

- [ ] **Step 1: Write failing handler, cooldown, input, UI, and rollback tests**

Each of the eight handlers must prove accepted activation, exact resource/cost, cooldown boundary, repeated-input rejection, stale token/generation rejection, reset, snapshot/restore, and one archetype-specific observable. Add controller-only replacement and reduced-motion/flash/contrast assertions.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter "active_item|input_contract|run_view_state|combat_hud"
```

- [ ] **Step 3: Implement closed active handlers**

`ActiveItemHandlers` matches only the eight approved handler IDs. Every plan contains handler ID, content ID, archetype, token, generation, frame, cooldown, normalized parameters, resource claims, and deterministic payload descriptors. Boss responses use exposure/safety/counter/resource/facing conversions and never hard-control a Boss.

- [ ] **Step 4: Add input, one-slot replacement, HUD, and feedback**

Add remappable `active_item`, one active slot in player snapshots, explicit replacement state in the choice flow, and HUD ready/cooldown projection. Feedback routes through existing accessibility budgets and localized subtitles.

- [ ] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter "active_item|input_contract|input_remap|run_view_state|combat_hud|choice_panel|combat_feedback"
git diff --check
git add -- scripts/items/active_item_runtime.gd scripts/items/active_item_handlers.gd scripts/player/player_controller.gd scripts/player/player_loadout_runtime.gd scripts/input/input_profile_store.gd scripts/input/input_remap_service.gd project.godot scripts/application/run_view_state_projector.gd scripts/ui/contracts/run_view_state.gd scripts/ui/views/combat_hud_view.gd scenes/ui/combat_hud_v2.tscn autoload/combat_feedback.gd scripts/presentation/pixel_proxy_actor.gd tests/unit/items/active_item_runtime_test.gd tests/unit/items/active_item_runtime_test.tscn tests/integration/items/active_item_player_integration_test.gd tests/integration/items/active_item_player_integration_test.tscn tests/contract/input/input_contract_test.gd tests/ui/combat_hud_v2_scene_test.gd tests/ui/run_view_state_contract_test.gd
git commit -m "feat(items): add launch active item runtime"
```

---

### Task 7: Seal Replay, save compatibility, drafts, and player-facing choice flow

**Files:**
- Modify: `scripts/replay/full_player_replay.gd`
- Modify: `scripts/application/run_view_state_projector.gd`
- Modify: `scripts/ui/contracts/run_view_state.gd`
- Modify: `scripts/ui/choice_panel_v2.gd`
- Modify: `scenes/ui/choice_panel_v2.tscn`
- Modify: `scripts/save/save_migration_registry.gd`
- Modify: `tests/replay/full_player_replay_test.gd`
- Modify: `tests/replay/character_runtime_replay_test.gd`
- Modify: `tests/unit/save/save_migration_registry_test.gd`
- Modify: `tests/unit/rewards/launch_draft_archetype_test.gd`
- Modify: `tests/ui/choice_panel_v2_scene_test.gd`
- Create: `tests/integration/content/launch_reward_flow_test.gd`
- Create: `tests/integration/content/launch_reward_flow_test.tscn`

**Interfaces:**
- Consumes: completed pools, effect digest, active snapshot, live talent state, and authoritative BuildState.
- Produces: deterministic Replay/save envelopes and a complete localized three-option/replacement flow.

- [ ] **Step 1: Write failing round-trip and divergence tests**

Cover all eight routes, passive effects, curse tradeoffs, live talent install, active cooldown, replacement, content fingerprint drift, unknown handler/effect, stale prefix, old snapshot defaulting, and locale refresh with stable IDs.

- [ ] **Step 2: Run RED**

```bash
./tools/run_tests.sh --filter "full_player_replay|character_runtime_replay|save_migration|launch_draft_archetype|choice_panel|launch_reward_flow"
```

- [ ] **Step 3: Extend canonical snapshots and migrations**

Replay seals normalized effect digest, passive runtime state, active state, selected live talents, BuildState route scores, and reward fact prefix. Save migration supplies explicit empty active/effect defaults for old compatible snapshots and rejects future or malformed schemas.

- [ ] **Step 4: Complete ChoicePanel summaries and replacement state**

Render localized archetype, role, rarity, effect summaries, active cooldown, and replacement warning. Controller focus order includes confirm, replace, decline, and back without trapping focus.

- [ ] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter "full_player_replay|character_runtime_replay|save_migration|launch_draft_archetype|choice_panel|launch_reward_flow"
git diff --check
git add -- scripts/replay/full_player_replay.gd scripts/application/run_view_state_projector.gd scripts/ui/contracts/run_view_state.gd scripts/ui/choice_panel_v2.gd scenes/ui/choice_panel_v2.tscn scripts/save/save_migration_registry.gd tests/replay/full_player_replay_test.gd tests/replay/character_runtime_replay_test.gd tests/unit/save/save_migration_registry_test.gd tests/unit/rewards/launch_draft_archetype_test.gd tests/ui/choice_panel_v2_scene_test.gd tests/integration/content/launch_reward_flow_test.gd tests/integration/content/launch_reward_flow_test.tscn
git commit -m "feat(rewards): seal launch reward flow"
```

---

### Task 8: Add deterministic build-formation and 150-loadout pool certification

**Files:**
- Create: `tools/run_launch_pool_simulation.py`
- Create: `tests/contract/simulation/test_launch_pool_report.py`
- Create: `tests/smoke/launch_pool_loadout_matrix_smoke_test.gd`
- Create: `tests/smoke/launch_pool_loadout_matrix_smoke_test.tscn`
- Modify: `tools/validate_project.sh`

**Interfaces:**
- Consumes: canonical Base Pack, eight profiles, five characters, five weapons, six time pairs, and thirty fixed seeds.
- Produces: deterministic synthetic report and runtime smoke evidence for route formation and representative content execution.

- [ ] **Step 1: Write failing report and runtime-matrix tests**

The report must contain exact content digests, counts, eight route summaries, thirty seeds, build-formation success/failure reasons, option exposure, effect execution counts, active usage, curse tradeoffs, and `synthetic: true`, `human_playtests: 0`. The runtime matrix applies representative starter/payoff/risk/talent/active content across all 150 loadouts.

- [ ] **Step 2: Run RED**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.simulation.test_launch_pool_report
./tools/run_tests.sh --filter launch_pool_loadout_matrix
```

- [ ] **Step 3: Implement deterministic simulation and matrix shards**

Use seeds `20260901..20260930`, stable sorted JSON, no wall clock, no global RNG, exact content hash inputs, and fail-closed unknown fields. Two independent report runs must be byte-identical.

- [ ] **Step 4: Run GREEN and commit**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.simulation.test_launch_pool_report
python3 tools/run_launch_pool_simulation.py --seeds 30 --output /private/tmp/planewalker-p13b-a.json
python3 tools/run_launch_pool_simulation.py --seeds 30 --output /private/tmp/planewalker-p13b-b.json
cmp /private/tmp/planewalker-p13b-a.json /private/tmp/planewalker-p13b-b.json
./tools/run_tests.sh --filter launch_pool_loadout_matrix
git diff --check
git add -- tools/run_launch_pool_simulation.py tests/contract/simulation/test_launch_pool_report.py tests/smoke/launch_pool_loadout_matrix_smoke_test.gd tests/smoke/launch_pool_loadout_matrix_smoke_test.tscn tools/validate_project.sh
git commit -m "test(content): certify launch pool formation"
```

---

### Task 9: P13B complete certification and evidence

**Files:**
- Create: `docs/current/2026-10-01-p13b-launch-content-evidence.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Modify: `docs/superpowers/specs/2026-10-01-plane-walker-p13b-launch-content-design.md`
- Modify: this plan

**Interfaces:**
- Consumes: Tasks 1–8 and complete repository validation.
- Produces: Historical plan, current evidence, exact hashes/counts, retained limitations, and P14 five-floor handoff.

- [ ] **Step 1: Run focused and complete certification**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_archetype_profile_schema tests.contract.localization.test_validate_localization tests.contract.simulation.test_launch_pool_report
./tools/run_tests.sh --filter "launch_pool|player_reward_effect_runtime|active_item|character_talent_state|launch_draft_archetype|full_player_replay|choice_panel|combat_hud"
./tools/validate_project.sh
python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
git diff --check
```

- [ ] **Step 2: Write evidence and mark Historical**

Record exact commits, `50 / 28 / 18 / 15`, `42 / 8`, eight route coverage, effect-catalog digest, Base Pack hashes, transaction failure matrix, active handlers, talent parity, 30-seed report digest, 150-loadout result, scene count, registered warnings, `0 / 20` human sessions, unsupported line coverage, and export/publication boundaries.

- [ ] **Step 3: Commit certification**

```bash
git add -- docs/current/2026-10-01-p13b-launch-content-evidence.md docs/README.md docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md docs/superpowers/specs/2026-10-01-plane-walker-p13b-launch-content-design.md docs/superpowers/plans/2026-10-01-plane-walker-p13b-launch-content.md
git commit -m "docs(content): certify p13b launch pools"
```

## P13B Exit Gate

- [ ] Exact `50 items / 28 blessings / 18 curses / 15 talents` resolve at Launch.
- [ ] Items split into exact `42 passive / 8 active`, with one active per archetype.
- [ ] Every route satisfies minimum starter/payoff/risk coverage and remains Boss-safe.
- [ ] Every scalar effect is bounded, category-valid, normalized, executable, tested, and player-facing.
- [ ] Reward selection is atomic under every injected failure phase.
- [ ] All fifteen talents are content-driven, character-scoped, live-installable, Replay-safe, and subset-certified.
- [ ] All eight active items support input, cooldown, replacement, HUD, feedback, Replay, reset, and rollback.
- [ ] Launch drafts remain deterministic, three-option, compatible, and route-complete.
- [ ] Thirty-seed formation reports are byte-identical and explicitly synthetic.
- [ ] All 150 loadouts pass representative Launch pool runtime smoke.
- [ ] M1/CURRENT/NEXT parity, formal M1 status, human-playtest count, line-coverage status, export, signing, and publication boundaries remain honest.
- [ ] Full repository validation is green with only registered warnings.
