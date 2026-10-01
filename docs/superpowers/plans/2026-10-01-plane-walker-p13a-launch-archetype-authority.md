# Plane Walker P13A Launch Archetype Authority Implementation Plan

- Status: Active / Current
- Document Role: Current implementation plan
- Authority Level: Executable P13A work breakdown under the approved Full Product Completion Design
- Applies To: Eight Launch archetype identities, content cross-references, milestone-aware draft routing, build-state validation, UI projection, tests, and local certification
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`, `docs/0_深度收敛与系统职责设计.md`, `docs/contracts/content-pack-v2.md`, `docs/current/2026-09-30-p12-five-characters-evidence.md`
- Last Verified: 2026-10-01
- Implementation Status: Tasks 1-2 complete locally; Task 3 milestone-aware drafting is next
- Exit Gate: Exactly eight versioned Launch archetype profiles resolve through ContentRegistry, every non-empty content archetype reference is validated, M1 drafting remains byte-for-byte compatible, Launch drafting is milestone-aware, build/UI state rejects unknown archetypes, and the complete repository gate remains green

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish one data-driven authority for the eight Launch archetypes so the upcoming 50-item, 28-blessing, 18-curse, and 15-talent pools cannot introduce competing IDs or draft invalid build routes.

**Architecture:** A closed `archetype_profile_v1` content category defines the eight top-level build identities, minimum starter/payoff/risk coverage, mechanic tags, and Boss-response conversion. `ContentRegistry` validates every `archetype`, tag, and compatibility reference against those profiles before activation. `DraftService`, `RunBuildState`, and `RunViewState` consume only Registry-derived archetype IDs while preserving the frozen three-route M1 behavior.

**Tech Stack:** Godot 4.6.1, typed GDScript, JSON Schema Draft 2020-12, Content Pack v2, CSV localization, deterministic DraftService seeds, scene-based tests, Python schema contracts, and local Git commits.

## Global Constraints

- The only top-level archetype IDs are `freeze_burst`, `rewind_echo`, `rift_trap`, `accelerated_combo`, `low_hp_void`, `perfect_guard`, `piercing_barrage`, and `echo_legion`.
- `heavy_cleave`, `evasive_guard`, `reload_burst`, `area_control`, weapon IDs, character IDs, and effect-handler IDs remain mechanic tags, never top-level archetypes.
- Each archetype profile requires `starter_min=3`, `payoff_min=2`, and `risk_min=1`.
- M1 continues to draft only `freeze_burst`, `rewind_echo`, and `accelerated_combo`; no Launch-only route may leak into M1/CURRENT/NEXT.
- Launch and Expansion enumerate all eight archetypes in the exact order defined by the approved completion design.
- Empty `archetype` remains legal only for content explicitly tagged `utility` and `generalist`; every Launch pool entry added after P13A must use one authoritative archetype or that exact utility marker.
- Boss responses convert control into readable exposure, safety, counter, resource, or facing windows; no archetype may hard-control a Boss.
- Formal status remains `M1 Candidate — External Validation Pending`; authentic human playtests remain `0 / 20`.
- P13A does not claim the final Launch pool counts. P13B closes `50 / 28 / 18 / 15` with real effects and runtime tests.

---

### Task 1: Closed archetype profile schema and catalog

**Files:**
- Create: `data/schemas/archetype_profile_v1.schema.json`
- Create: `data/content_packs/base/content/archetype_profiles.json`
- Create: `scripts/progression/archetype_profile.gd`
- Create: `tests/contract/content_schema/test_archetype_profile_schema.py`
- Create: `tests/contract/content_schema/archetype_profile_contract_test.gd`
- Create: `tests/contract/content_schema/archetype_profile_contract_test.tscn`
- Modify: `data/localization/translations.csv`
- Modify: `data/content_packs/base/localization/translations.csv`

**Interfaces:**
- Consumes: the eight IDs and Boss-response rows in the approved Full Product Completion Design.
- Produces: `ArchetypeProfile.configure(definition) -> Dictionary`, `snapshot() -> Dictionary`, `ARCHETYPE_IDS`, and eight closed content definitions.

- [x] **Step 1: Write failing Python schema tests**

Add a Draft 2020-12 contract that requires exactly these scalar/profile fields:

```python
EXPECTED_IDS = [
    "freeze_burst", "rewind_echo", "rift_trap", "accelerated_combo",
    "low_hp_void", "perfect_guard", "piercing_barrage", "echo_legion",
]

def test_exact_catalog_and_closed_values(self):
    self.assertEqual([row["archetype_id"] for row in self.catalog], EXPECTED_IDS)
    for row in self.catalog:
        self.assertEqual(row["category"], "archetype_profile")
        self.assertEqual(row["profile_version"], 1)
        self.assertEqual(row["availability"], ["LAUNCH", "EXPANSION"])
        self.assertEqual(row["starter_min"], 3)
        self.assertEqual(row["payoff_min"], 2)
        self.assertEqual(row["risk_min"], 1)
        self.assertEqual(list(self.validator.iter_errors(row)), [])
```

Mutations for unknown root fields, a ninth ID, duplicate mechanic tags, missing Boss response, non-integer minimums, minimums below the required values, unknown conversion IDs, M1 availability, arbitrary effects, and 65-character IDs must fail.

- [x] **Step 2: Write failing GDScript parser tests**

The scene test asserts exact ordered IDs and these Boss conversion IDs:

```gdscript
const BOSS_CONVERSIONS := {
	"freeze_burst": "boss_weakpoint_exposure",
	"rewind_echo": "boss_rewind_path_strike",
	"rift_trap": "boss_projectile_window",
	"accelerated_combo": "boss_combo_break",
	"low_hp_void": "boss_execute_warning",
	"perfect_guard": "boss_counter_window",
	"piercing_barrage": "boss_weakpoint_ammo_refund",
	"echo_legion": "boss_facing_lure",
}
```

`snapshot()` must deep-copy `mechanic_tags`, preserve authored order, strip pack provenance, and reject mutations that omit `starter`, `payoff`, or `risk` coverage.

- [x] **Step 3: Run tests and confirm RED**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_archetype_profile_schema
./tools/run_tests.sh --filter archetype_profile_contract
```

Expected: FAIL because the schema, parser, and catalog do not exist.

- [x] **Step 4: Implement schema, parser, catalog, and localization**

`ArchetypeProfile` exposes this exact snapshot:

```gdscript
{
	"id": String,
	"profile_version": 1,
	"archetype_id": String,
	"availability": ["LAUNCH", "EXPANSION"],
	"mechanic_tags": Array[String],
	"starter_min": 3,
	"payoff_min": 2,
	"risk_min": 1,
	"boss_conversion_id": String,
	"boss_response_key": String,
}
```

The eight rows use localized name, description, and Boss-response keys in both catalogs. `effects` is an empty object and the root schema uses `additionalProperties: false`.

- [x] **Step 5: Run GREEN and commit**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_archetype_profile_schema
./tools/run_tests.sh --filter archetype_profile_contract
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.localization.test_validate_localization
python3 tools/validate_localization.py
git diff --check
git add -- data/schemas/archetype_profile_v1.schema.json data/content_packs/base/content/archetype_profiles.json scripts/progression/archetype_profile.gd tests/contract/content_schema/test_archetype_profile_schema.py tests/contract/content_schema/archetype_profile_contract_test.gd tests/contract/content_schema/archetype_profile_contract_test.tscn data/localization/translations.csv data/content_packs/base/localization/translations.csv
git commit -m "feat(builds): add launch archetype profiles"
```

---

### Task 2: ContentRegistry integration and cross-reference closure

**Files:**
- Modify: `data/schemas/content_entry_v2.schema.json`
- Modify: `data/content_packs/base/pack.json`
- Modify: `scripts/content/content_registry.gd`
- Modify: `tests/contract/content_schema/content_registry_test.gd`
- Modify: `tests/contract/content_schema/content_pack_contract_test.gd`
- Modify: `tests/contract/content_schema/test_archetype_profile_schema.py`
- Modify: `tests/unit/content/content_pack_resolver_test.gd`
- Modify: `tools/validate_project.sh`

**Interfaces:**
- Consumes: Task 1 `ArchetypeProfile` and eight profile definitions.
- Produces: `get_archetype_profile(archetype_id)`, `get_archetype_profiles(milestone)`, strict `archetype` and `compatibility.archetype_ids` validation, and one manifest-backed source.

- [x] **Step 1: Write failing Registry and pack tests**

Update the real Base Pack expectations from 72 to 80 definitions and assert `archetype_profile: 8`. Add cases proving:

```gdscript
suite.assert_equal(
	registry.get_archetype_profiles(&"LAUNCH").map(func(row): return row["archetype_id"]),
	ArchetypeProfileScript.ARCHETYPE_IDS,
	"Launch resolves the exact ordered eight-archetype taxonomy"
)
suite.assert_true(registry.get_archetype_profiles(&"M1").is_empty(), "Launch profiles do not widen M1")
suite.assert_equal(registry.get_content(&"frozen_burst")["archetype"], "freeze_burst", "existing content resolves a profile")
```

Temporary packs with `time_stop_burst`, `piercing_draw`, missing profiles, unavailable profiles, empty `compatibility.archetype_ids`, and archetype-profile-only fields on an item must fail before activation.

- [x] **Step 2: Run Registry tests and confirm RED**

```bash
./tools/run_tests.sh --filter content_registry
./tools/run_tests.sh --filter content_pack_contract
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_archetype_profile_schema
```

Expected: FAIL because `archetype_profile` is not a valid category and references are not checked.

- [x] **Step 3: Add generic entry and Registry support**

Add `archetype_profile` to category enums and close these fields to that category only:

```text
archetype_id, mechanic_tags, starter_min, payoff_min, risk_min,
boss_conversion_id, boss_response_key
```

`ContentRegistry._first_reference_error()` validates each non-empty `archetype`, each `compatibility.archetype_ids` entry, and each archetype-like tag against an available profile. Empty archetypes require both `utility` and `generalist` tags once content is available at Launch/Expansion; M1/NEXT legacy rows retain their existing behavior until P13B migration.

`get_archetype_profile()` and `get_archetype_profiles()` return parser-ready deep copies with pack envelope fields removed.

- [x] **Step 4: Register the source and integrity digest**

Add `content/archetype_profiles.json` to the Base Pack manifest and compute its SHA-256. Run the real pack through M1 and Launch activation; both must load the same eight identities while milestone queries keep them Launch/Expansion-only.

- [x] **Step 5: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter content_registry
./tools/run_tests.sh --filter content_pack_contract
./tools/run_tests.sh --filter content_pack_resolver
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_archetype_profile_schema
git diff --check
git add -- data/schemas/content_entry_v2.schema.json data/content_packs/base/pack.json scripts/content/content_registry.gd tests/contract/content_schema/content_registry_test.gd tests/contract/content_schema/content_pack_contract_test.gd tests/contract/content_schema/test_archetype_profile_schema.py tests/unit/content/content_pack_resolver_test.gd tools/validate_project.sh
git commit -m "feat(content): validate launch archetype references"
```

---

### Task 3: Milestone-aware drafting with frozen M1 parity

**Files:**
- Modify: `scripts/rewards/draft_service.gd`
- Modify: `tests/fixtures/content/draft_entries.json`
- Modify: `tests/unit/rewards/draft_service_test.gd`
- Create: `tests/unit/rewards/launch_draft_archetype_test.gd`
- Create: `tests/unit/rewards/launch_draft_archetype_test.tscn`

**Interfaces:**
- Consumes: `state_snapshot.config.milestone`, Registry archetype profiles, and milestone-filtered reward definitions.
- Produces: deterministic M1 three-route drafts, Launch eight-route starter/reinforcement policy, and fail-closed insufficient-pool diagnostics.

- [ ] **Step 1: Write failing M1 parity and Launch routing tests**

Keep the existing 1000-seed M1 starter assertion unchanged. Add an eight-route fixture with three starters, two payoffs, and one risk row per archetype. For every canonical seed `20260901..20260930`, assert:

```gdscript
var state := _state(seed, 1, "LAUNCH")
var result = service.create_offer(registry, state, _launch_starter_room())
suite.assert_true(result.ok, "Launch starter draft succeeds")
suite.assert_equal(result.context["offer"]["options"].size(), 3, "choice load stays bounded")
suite.assert_true(
	_option_archetypes(service, result.context["offer"]).all(
		func(value): return ArchetypeProfileScript.ARCHETYPE_IDS.has(value)
	),
	"every option uses the authoritative taxonomy"
)
```

Reinforcement requires one dominant payoff, one alternative starter, and one utility/safety option. Unknown milestone, unknown dominant archetype, unavailable profile, insufficient coverage, owned-content exhaustion, and noncanonical cached offer identity fail without altering the offer cache.

- [ ] **Step 2: Run DraftService tests and confirm RED**

```bash
./tools/run_tests.sh --filter draft_service
./tools/run_tests.sh --filter launch_draft_archetype
```

Expected: M1 remains green and the Launch tests fail because drafting is hard-coded to M1 and three routes.

- [ ] **Step 3: Implement milestone routing**

Read the milestone from `state_snapshot.config.milestone`, defaulting to `M1` only when the field is absent for legacy tests. Query reward categories and archetype profiles at that milestone. Replace `STARTER_ARCHETYPES` with:

```gdscript
const M1_ARCHETYPES := ["freeze_burst", "rewind_echo", "accelerated_combo"]

func _allowed_archetypes(registry, milestone: StringName) -> Array[String]:
	if milestone == &"M1":
		return M1_ARCHETYPES.duplicate()
	var ids: Array[String] = []
	for profile: Dictionary in registry.get_archetype_profiles(milestone):
		ids.append(str(profile["archetype_id"]))
	return ids
```

The public offer remains exactly three options. Seed channels include milestone and profile digest so M1 sequences remain unchanged and Launch sequences are deterministic.

- [ ] **Step 4: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter draft_service
./tools/run_tests.sh --filter launch_draft_archetype
./tools/run_tests.sh --filter reward_system_smoke
git diff --check
git add -- scripts/rewards/draft_service.gd tests/fixtures/content/draft_entries.json tests/unit/rewards/draft_service_test.gd tests/unit/rewards/launch_draft_archetype_test.gd tests/unit/rewards/launch_draft_archetype_test.tscn
git commit -m "feat(rewards): route drafts through launch archetypes"
```

---

### Task 4: Build-state and HUD archetype contracts

**Files:**
- Modify: `scripts/progression/run_build_state.gd`
- Modify: `scripts/application/run_orchestrator.gd`
- Modify: `scripts/application/run_view_state_projector.gd`
- Modify: `scripts/ui/contracts/run_view_state.gd`
- Modify: `scripts/ui/views/combat_hud_view.gd`
- Modify: `tests/contract/application/run_state_snapshot_contract_test.gd`
- Modify: `tests/contract/application/run_authority_contract_test.gd`
- Modify: `tests/unit/application/run_view_state_projector_test.gd`
- Modify: `tests/ui/run_view_state_contract_test.gd`
- Modify: `tests/ui/combat_hud_v2_scene_test.gd`

**Interfaces:**
- Consumes: resolved content definition, authoritative archetype IDs, and immutable RunState snapshots.
- Produces: exact eight-key archetype scores, deterministic dominant route, and localized player-facing HUD identity.

- [ ] **Step 1: Write failing build and UI tests**

After a selected definition is applied, increment only its authoritative archetype score. Utilities with an empty archetype increment no route. Ties resolve by the approved profile order. Unknown keys, negative/non-finite scores, a dominant ID outside the score map, and internal mechanic tags in `dominant_archetype` fail closed.

The HUD must render `ARCHETYPE_<ID>_NAME` and never display the raw ID. Locale refresh changes the visible label while preserving the cached stable ID.

- [ ] **Step 2: Run tests and confirm RED**

```bash
./tools/run_tests.sh --filter run_state_snapshot_contract
./tools/run_tests.sh --filter run_authority_contract
./tools/run_tests.sh --filter run_view_state
./tools/run_tests.sh --filter combat_hud
```

- [ ] **Step 3: Implement strict build projection**

Initialize all eight score keys to zero for Launch/Expansion and the frozen three keys for M1. `RunBuildState.apply_definition(definition)` accepts only content resolved by the Registry, appends the stable ID to the correct collection, increments a non-empty archetype once, recomputes dominant route by score then approved order, and returns an immutable change fact.

`RunViewState` validates the exact milestone-specific score domain. `CombatHudView` uses the localized archetype name key supplied by the projector.

- [ ] **Step 4: Run GREEN and commit**

```bash
./tools/run_tests.sh --filter run_state_snapshot_contract
./tools/run_tests.sh --filter run_authority_contract
./tools/run_tests.sh --filter run_view_state
./tools/run_tests.sh --filter combat_hud
./tools/run_tests.sh --filter choice_panel
git diff --check
git add -- scripts/progression/run_build_state.gd scripts/application/run_orchestrator.gd scripts/application/run_view_state_projector.gd scripts/ui/contracts/run_view_state.gd scripts/ui/views/combat_hud_view.gd tests/contract/application/run_state_snapshot_contract_test.gd tests/contract/application/run_authority_contract_test.gd tests/unit/application/run_view_state_projector_test.gd tests/ui/run_view_state_contract_test.gd tests/ui/combat_hud_v2_scene_test.gd
git commit -m "feat(ui): project authoritative build archetypes"
```

---

### Task 5: P13A certification and P13B handoff

**Files:**
- Create: `docs/current/2026-10-01-p13a-launch-archetype-authority-evidence.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Modify: this plan

**Interfaces:**
- Consumes: Tasks 1-4 implementation commits and complete repository validation.
- Produces: Historical P13A plan, current evidence, and an explicit P13B next step for the real `50 / 28 / 18 / 15` Launch pools.

- [ ] **Step 1: Run focused and complete certification**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.contract.content_schema.test_archetype_profile_schema tests.contract.documentation.test_document_governance tests.contract.localization.test_validate_localization
./tools/run_tests.sh --filter archetype_profile
./tools/run_tests.sh --filter content_registry
./tools/run_tests.sh --filter draft_service
./tools/run_tests.sh --filter launch_draft_archetype
./tools/run_tests.sh --filter run_view_state
./tools/validate_project.sh
python3 tools/document_governance.py --baseline tools/document_governance_baseline.json
git diff --check
```

Expected: all tests pass with only the registered `reward_system_smoke.tscn` warning; line coverage and export boundaries remain honestly unavailable/external.

- [ ] **Step 2: Write evidence and mark Historical**

Record exact commits, eight IDs, schema/catalog digests, M1 parity results, Launch 30-seed draft determinism, scene count, registered warning, `0 / 20` human playtests, and external export/signing/publication boundaries. Mark this plan `Completed / Historical` with `Completion Evidence` metadata.

- [ ] **Step 3: Commit certification**

```bash
git add -- docs/current/2026-10-01-p13a-launch-archetype-authority-evidence.md docs/README.md docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md docs/superpowers/plans/2026-10-01-plane-walker-p13a-launch-archetype-authority.md
git commit -m "docs(builds): certify p13a archetype authority"
```

## P13A Exit Gate

- [ ] Exactly eight Launch/Expansion archetype profiles exist in approved order.
- [ ] The schema, parser, generic entry contract, Registry, pack manifest, localization, and integrity hashes agree.
- [ ] Unknown, unavailable, duplicate, empty, or mechanic-tag archetype references fail before pack activation.
- [ ] M1 drafting remains restricted to the frozen three routes with deterministic parity.
- [ ] Launch drafting reads all eight routes through the Registry and keeps three-option choice load.
- [ ] RunBuildState, Replay snapshots, ViewState, and HUD accept only the milestone-specific archetype domain.
- [ ] P13A does not claim the final Launch pool counts; P13B owns the real `50 / 28 / 18 / 15` content and effect certification.
- [ ] Full repository validation is green with only registered warnings.
- [ ] Evidence remains local and does not change M1, human-playtest, line-coverage, export, signing, or publication status.
