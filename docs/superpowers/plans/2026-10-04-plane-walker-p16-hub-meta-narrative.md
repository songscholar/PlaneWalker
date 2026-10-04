# Plane Walker P16 Hub, Meta, and Narrative Implementation Plan

- Status: Approved / Current
- Document Role: Current P16 implementation plan
- Authority Level: Executable plan beneath the P16 Hub, Meta, and Narrative specification
- Applies To: Isolated progression domains, content catalogs, native Hub, narrative, onboarding, migration, Replay, and P16 certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`
- Last Verified: 2026-10-04
- Exit Gate: Complete P16 domain, content, native interaction, migration, Replay, visual, and offline import/export certification recorded in focused evidence and reviewed local commits

> **For agentic workers:** Execute each boundary with focused RED/GREEN tests and an independent review. Standing project authorization permits execution and local integration commits; unavailable skill names do not block the repository's existing test workflow.

**Goal:** Deliver the three-district Hub, all progression/content, first-run lessons, NPC arcs, and five endings with durable offline Save and complete native interaction paths.

**Architecture:** RefCounted profile and narrative authorities prepare complete candidates, while one profile service persists before publication. A native Hub coordinator projects authority state and streams one district. Immutable MetaRunProjection is installed before capturing the Player run-start reward baseline.

**Tech Stack:** Godot 4.6.1, GDScript, native Control scenes, data-pack JSON/schema validation, Python contract tools, physical SaveService, existing Replay and focus helpers.

## Global Constraints

- Specification: `docs/superpowers/specs/2026-10-04-plane-walker-p16-hub-meta-narrative-design.md`.
- Canonical playable/weapon/Boss IDs, M1 behavior, four time abilities and six legal time pairs remain authoritative.
- Meta single-stat totals are at most 5%; Meta direct combat benefit is at most 15%; combined permanent benefit is at most 30%.
- Every success uses revision validation, one authored source, defensive snapshots, deterministic source receipts, and physical JSON tests.
- Do not activate shared Registry, Save, Player, or Main changes before their independent domain tests pass and current integration freeze ends.
- Integration lead owns precise-list local commits. Do not stage unrelated dirty-worktree changes.

## Task 1 / P16A: Isolated profile and Meta domain

Files: create `scripts/progression/meta_profile_state.gd`, `scripts/progression/meta_progression_catalog.gd`, `scripts/progression/meta_run_projection.gd`; create `tests/unit/progression/meta_profile_state_test.gd` and scene, `meta_progression_catalog_test.gd` and scene, `meta_run_projection_test.gd` and scene; create `tests/support/p16_profile_fixtures.gd`. At this boundary the fixtures carry explicit authored definitions; production content activation belongs to Task 2.

Interfaces: `MetaProfileState.configure(catalog: RefCounted, value: Dictionary = {}) -> bool`, `snapshot() -> Dictionary`, `can_restore_snapshot(value: Dictionary) -> bool`, `restore_snapshot(value: Dictionary) -> bool`, `prepare_command(command: Dictionary, expected_revision: int) -> Dictionary`, `commit_candidate(ticket: Dictionary) -> Dictionary`; `MetaProgressionCatalog.configure(entries: Array, reference_ids: Dictionary = {}) -> Dictionary`, `definition(id: StringName) -> Dictionary`; `MetaRunProjection.from_profile(profile: Dictionary, catalog: RefCounted) -> Dictionary`, `validate(value: Dictionary, catalog: RefCounted) -> bool`.

- [x] Add a test that buys W-01 with five shards, repeats the same command, submits a stale revision, and restores a malformed nested currency/proficiency entry. Verify failure preserves the entire snapshot and no caller dictionary aliases state:

```gdscript
var before: Dictionary = state.snapshot()
var ticket: Dictionary = state.prepare_command({"command_id": "buy-w01", "kind": "meta_unlock", "node_id": "W-01"}, before["revision"])
suite.assert_true(ticket.ok, "authored cost and prerequisites prepare")
suite.assert_equal(state.snapshot(), before, "preparation cannot spend")
suite.assert_true(state.commit_candidate(ticket.context.ticket).ok, "candidate commits once")
suite.assert_true(not state.commit_candidate(ticket.context.ticket).ok, "duplicate commit cannot mint or spend")
```

- [x] Run `tools/run_tests.sh --filter meta_profile_state`; retain the missing-script/contract RED result.
- [x] Implement exact snapshot fields, ID/type/finite bounds, canonical lists, immutable owner-bound tickets, expected revision, one-time purchases, and atomic restore. Derive bounded launch effects from the forty-two authored definitions; implement `validate` to refuse out-of-budget projection rather than silently clamp content.
- [x] Run the three Task 1 filters; verify JSON.parse_string(JSON.stringify(snapshot)) restores identical semantic state. Record focused logs and review the exact file diff before a local Task 1 commit.

Task 1 focused evidence: `docs/current/2026-10-04-p16a-profile-domain-evidence.md`. Production content, shared Save/Player/Main activation, and all later tasks remain pending.

## Task 2 / P16B: Authoritative catalogs and reconciliation

Files: create `data/content_packs/base/content/meta_nodes.json`, `hub_districts.json`, `forge_definitions.json`, `narrative_definitions.json`, `tutorial_definitions.json`; create corresponding `data/schemas/*_v1.schema.json`; extend `scripts/content/content_registry.gd`, `data/schemas/content_entry_v2.schema.json`, `data/content_packs/base/pack.json`, `docs/contracts/content-pack-v2.md`; create `tests/contract/content_schema/test_p16_progression_schemas.py` and `p16_content_contract_test.gd`/scene.

Interfaces: Registry categories `meta_node`, `hub_district`, `forge_definition`, `narrative_definition`, `tutorial_definition`; every specialized entry uses schema_version 1 and closed domain fields. Domain catalogs consume Registry projections, never duplicate production tables.

- [ ] Write exact-count tests for 42 Meta nodes, 3 districts/9 unique functions, 5 weapon forge definitions/15 enchant options, 8 NPC arcs, 10 artifacts, 21 environment records, 3 five-step hidden lines, 5 endings, 10 lessons/15 hints. Refuse cycles, missing F-09, unknown playable/Boss IDs, untranslated strings, and bonuses beyond specification caps.
- [ ] Run `python3 -m unittest tests/contract/content_schema/test_p16_progression_schemas.py`; retain RED before adding content.
- [ ] Author all specified costs/prerequisites/effects; update closed schemas and Registry ingestion. Add complete Chinese/English lines to both existing localization sources and refresh pack hashes with the repository's hash workflow. Translate only runtime strings, keeping IDs stable.
- [ ] Run schema/content filters and `python3 tools/validate_localization.py`; publish exact authored totals and the ID/legacy reconciliation table in focused P16 evidence before the local content commit.

## Task 3 / P16C: Launch and settlement authority

Files: create `scripts/progression/run_settlement_authority.gd`, `scripts/progression/profile_runtime_service.gd`; create `tests/unit/progression/run_settlement_authority_test.gd`/scene and `tests/integration/progression/settlement_save_retry_test.gd`/scene; later adapt `autoload/game_state.gd` and the current Main terminal handler using the reviewed service endpoint.

Interfaces: `ProfileRuntimeService.configure(save_service: RefCounted, catalog: RefCounted, profile_id: String, save_domain: String) -> Dictionary`, `execute(command: Dictionary, expected_revision: int) -> Dictionary`, `begin_launch(config: Dictionary, expected_revision: int) -> Dictionary`, `settle_terminal(run_state: Dictionary, source_receipts: Array, expected_revision: int) -> Dictionary`; `RunSettlementAuthority.prepare(profile: Dictionary, launch_receipt: Dictionary, terminal_run: Dictionary, receipts: Array) -> Dictionary` returns candidate and immutable settlement receipt inside context.

- [ ] Write normal/partial-death/full-victory formula assertions, first-Boss imprints, difficulty rounding, stale/duplicate receipt, abandoned-run refusal, summon/material deduplication, and synthetic legacy summary import that grants no currency.
- [ ] Run settlement filter and retain RED. Add a SaveFileOps failure double that fails the candidate write; verify currency/statistics and last-settlement sequence remain unchanged, then retry actual physical JSON once and verify a second retry changes nothing:

```gdscript
var prior: Dictionary = service.snapshot()
files.fail_next_write = true
suite.assert_true(not service.settle_terminal(terminal, receipts, prior.revision).ok, "write failure refuses settlement")
suite.assert_equal(service.snapshot(), prior, "write failure cannot mint profile rewards")
suite.assert_true(service.settle_terminal(terminal, receipts, prior.revision).ok, "durable retry settles once")
```

- [ ] Implement persisted monotonic launch sequence/active receipt and single-envelope candidate writes before live publication. Import actual terminal/floor/Boss facts; retain active terminal state until final ending interaction can resume. Keep compatibility mirrors derived from nested state.
- [ ] Run focused settlement/native Save integration, inspect malformed receipts and write-failure logs, document the crash/retry behavior, and commit the domain/service boundary.

## Task 4 / P16D: Forge, proficiency, build library, and drills

Files: create `scripts/progression/forge_runtime.gd`, `weapon_proficiency_runtime.gd`, `build_library.gd`, `scripts/training/training_runtime.gd`; create corresponding `tests/unit/progression/*_test.gd`/scenes and `tests/integration/training/training_player_flow_test.gd`/scene. Consume five real Player profiles and reusable P15 action definitions through adapters.

Interfaces: all state changes are `ProfileRuntimeService.execute` commands with kind `forge_upgrade`, `enchant_preference`, `void_temper`, `build_save`, `build_remove`, or `training_claim`; `TrainingRuntime.configure(player: Node, config: Dictionary, drill: Dictionary) -> bool`, `observe_action(receipt: Dictionary) -> Dictionary`, `reset_attempt() -> bool`, `snapshot() -> Dictionary`.

- [ ] Write forge costs/levels/caps, duplicate spend, incompatible enchantments, proficiency thresholds, 32-build limit, legal loadout restore, and six one-time training reward tests. Practice deaths must leave launch sequence/settlement/statistics unchanged.
- [ ] Run forge/build/training filters to RED. Implement deterministic no-loss forge acquisition, preference-only enchant routing, and training with real Player action receipts/refill/reset.
- [ ] Verify all 150 legal sandbox loadouts, five weapon drills, and complete Boss drill phases. A replayed or reset drill receipt cannot claim a second reward. Retain native evidence and commit after review.

## Task 5 / P16E: Narrative and five endings

Files: create `scripts/narrative/narrative_catalog.gd`, `narrative_state.gd`, `narrative_runtime.gd`, `ending_evaluator.gd`; create `tests/unit/narrative/narrative_runtime_test.gd`/scene and `ending_evaluator_test.gd`/scene; create `tests/integration/narrative/narrative_save_flow_test.gd`/scene. Localized content is the Task 2 catalog extended with all authored dialogue text, journal steps, ending scenes, and credits.

Interfaces: `NarrativeRuntime.configure(catalog: RefCounted, profile_service: RefCounted) -> bool`, `available_dialogue(npc_id: StringName, run_context: Dictionary) -> Dictionary`, `choose(choice_id: StringName, source_receipt: Dictionary, expected_revision: int) -> Dictionary`; `EndingEvaluator.available_choices(profile: Dictionary, run_facts: Dictionary) -> Array`, `choose(ending_id: StringName, profile: Dictionary, run_facts: Dictionary) -> Dictionary`.

- [ ] Write a table-driven eligible/ineligible case for every exact ending predicate. Shattered Freedom must remain available after authentic victory, and no ending appears before it. Test all eight affinity thresholds, fifteen hidden-line steps, twenty-one environment records, ten artifacts, Nemesis spare sequence, and Vera cost/duplicate/refusal/reload.
- [ ] Run narrative/ending filters to RED. Implement closed dialogue predicate/effect operations, consumed source IDs, cumulative gameplay-frame exposure, deterministic record grants, and fact-only ending evaluation.
- [ ] Persist pending final choice and separate credits completion; verify physical JSON resume at dialogue choice, Vera payment, hidden line completion, ending choice and interrupted credits. Run negative tests for invented/unowned flags before committing.

## Task 6 / P16F: Tutorials and guided launches

Files: create `scripts/onboarding/tutorial_runtime.gd`, `tutorial_projector.gd`, native `scripts/ui/tutorial_panel.gd`/scene; create `tests/unit/onboarding/tutorial_runtime_test.gd`/scene and `tests/integration/ui/tutorial_controller_flow_test.gd`/scene.

Interfaces: `TutorialRuntime.configure(catalog: RefCounted, profile_service: RefCounted) -> bool`, `observe(receipt: Dictionary) -> Dictionary`, `skip(lesson_id: StringName, expected_revision: int) -> Dictionary`, `replay(lesson_id: StringName) -> Dictionary`, `guided_launch_projection(run_number: int) -> Dictionary`.

- [ ] Write semantic action progression, controller/input remap, skip/replay/suppression, no repeated hint, locale/text scale, and guided protection/ranked exclusion cases. Verify pause/menu/Hub time never advances void-exposure or timed drill progress.
- [ ] Run tutorial filter to RED. Implement all ten lessons/fifteen implemented-topic hints, InputMap-aware captions, and explicit optional 0.80/0.90/1.0 assisted run projections.
- [ ] Verify three guided runs, immediate normal-mode access, no affinity/currency reward for skip, and persisted tutorial resume before committing.

## Task 7 / P16G: Native Hub and terminal-to-relaunch workflow

Files: create `scripts/hub/hub_runtime_facade.gd`, `hub_scene_host.gd`, `hub_flow_coordinator.gd`, `scripts/ui/contracts/hub_view_state.gd`, `hub_view_state_projector.gd`, `scenes/hub/hub_council.tscn`, `hub_craft.tscn`, `hub_rift.tscn` and native projected panels; create pixel raster assets under `data/content_packs/base/assets/hub/`; adapt `scenes/main.tscn` and `scripts/main.gd` only after upstream GREEN. Create `tests/integration/ui/p16_hub_controller_flow_test.gd`/scene and `tests/ui/p16_hub_visual_contract_test.gd`/scene.

Interfaces: `HubRuntimeFacade.boot(profile_service: RefCounted, providers: Dictionary) -> Dictionary`, `travel(district_id: StringName, expected_revision: int) -> Dictionary`, `command(value: Dictionary, expected_revision: int) -> Dictionary`, `view_state() -> RefCounted`; scene host installs one district from authored descriptors. Provider failures yield the authored local status and do not block launch/profile/narrative.

- [ ] Write actual native interaction through nine functions, map/back/focus travel, retired buttons, affordability/prerequisite refusal, and death/victory return then relaunch. The test must inspect live profile and Player state, not merely visible labels.
- [ ] Run native Hub filter to RED. Build districts/rasters and focused panels using existing FocusCoordinator/localization/safe-area patterns; wire service commands and local provider views. Capture immutable meta projection before run-start permanent-reward baseline.
- [ ] Capture/inspect Chinese/English screenshots at 640x360, 1280x720, 1920x1080, 3440x1440 at text scale 1.0/1.5. Verify nonblank rendered pixels, reachable NPCs, no clipping, safe-area/focus, one loaded district, and reduced motion. Record asset provenance/licensing and native flow evidence before committing.

## Task 8 / P16H: Schema migration, Replay, and combined certification

Files: create `scripts/save/migrations/save_migration_v3_to_v4.gd`, `data/schemas/save_profile_v4.schema.json`; extend `save_envelope.gd`, migration registry, SaveService and GameState compatibility composition; extend Replay recorder/player and existing Player helpers only for versioned meta/narrative participants; create `tests/integration/save/meta_profile_migration_test.gd`/scene, `tests/replay/meta_run_projection_replay_test.gd`/scene, `tools/run_meta_simulation.py`, `docs/current/2026-10-04-p16-hub-meta-narrative-evidence.md`; update current docs index/contracts.

Interfaces: profile envelope schema 4 contains strict `meta_profile_state`; settings retain their current schema. Authentication precedes migration. In-flight old runs get empty no-benefit MetaRunProjection; live profile purchase/settlement cannot execute in replay playback.

- [ ] Write authenticated current/legacy/malformed/newer-version migration tests, mirror contradiction, actual JSON round trip, write failure/backup recovery, caller immutability, and active-run no-benefit compatibility. Add active/max meta Save/Replay tests for all 150 loadouts and physical bounded effects.
- [ ] Run migration/meta Replay filters to RED. Integrate isolated validators, explicit legacy-ID mapping, immutable run projection, and separate fake profile for replay/simulation. Never populate an old run from current unlocked Meta nodes.
- [ ] Run `tools/validate_project.sh`, full Godot suite, Python contracts, deterministic progression/narrative simulations, native screenshots, and clean offline import/export/launch. Scan engine logs for errors/leaks as well as process status.
- [ ] Record authored counts, all focus/visual/Save/Replay evidence, exact balance budget maxima, known human/external limitations, and reviewed focused commits. P16 is certified only after this complete gate; proceed to later authorized milestones under the integration lead.

## Ownership and First Implementation Boundary

The first independently executable boundary is Task 1. It creates only new `scripts/progression/meta_*` files and isolated tests/fixtures; it needs no changes to shared Registry, Save, Player, GameState, or Main. The integration lead can implement this domain while the hostile-frame bridge and P14/P15 validation continue. Shared production activation waits for isolated GREEN and a released source freeze.
