# Plane Walker P3 ContentRegistry v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven development when available. Implement tasks in order, keep file ownership isolated, and review every focused commit before integration. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make versioned JSON content packs the single authoritative source for gameplay definitions, validate all references/localization/effects before activation, expose deterministic pack fingerprints to saves, and retire the remaining hard-coded reward fallbacks.

**Architecture:** A pure content domain loads pack descriptors, validates dependencies and integrity, normalizes entries, and activates only packs that are safe for the selected execution mode. A closed declarative effect catalog validates content data without allowing arbitrary scripts. Existing `ContentRegistry` query methods remain compatible while their backing store changes to activated packs.

**Tech Stack:** Godot 4.6.1, typed GDScript, JSON Schema documents, SHA-256 via `HashingContext`, scene-based contract/unit/integration tests.

## Global Constraints

- The base game, first-party updates, Mods, and DLC use one pack envelope and one validation pipeline.
- Pack IDs match `^[a-z0-9][a-z0-9_-]{0,63}$`; content IDs may additionally contain `.`. Both remain stable after release.
- Content data cannot name or execute arbitrary GDScript paths.
- Dependency order is deterministic; cycles, duplicate IDs, incompatible versions, and missing dependencies fail closed.
- Invalid optional packs are isolated; an invalid required base pack blocks boot.
- Presentation/localization randomness never consumes gameplay RNG.
- `ContentRegistry.get_content`, `get_by_category`, and `all_content` continue returning deep copies.
- Save snapshots use activated pack IDs, versions, schema versions, and deterministic digests.
- Existing M1 content, encounters, drafting behavior, and release-gate evidence remain reproducible.

---

### Task 1: Freeze Content-Pack and Entry Contracts

**Files:**
- Create: `docs/contracts/content-pack-v2.md`
- Create: `data/schemas/content_pack_v2.schema.json`
- Create: `data/schemas/content_entry_v2.schema.json`
- Create: `tests/fixtures/content_packs/valid_base/pack.json`
- Create: `tests/fixtures/content_packs/valid_base/content/items.json`
- Create: `tests/fixtures/content_packs/invalid_script/pack.json`
- Create: `tests/fixtures/content_packs/invalid_script/content/items.json`
- Create: `tests/contract/content_schema/content_pack_contract_test.gd`
- Create: `tests/contract/content_schema/content_pack_contract_test.tscn`

**Interfaces:**
- Consumes: Full-product content-pack contract in `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`.
- Produces: Frozen pack fields, entry fields, ID policy, availability values, and arbitrary-script rejection used by later tasks.

- [ ] **Step 1: Write the failing pack contract test**

```gdscript
func _run() -> void:
	var suite = TestSuiteScript.new()
	var pack_schema := _load_json("res://data/schemas/content_pack_v2.schema.json")
	var entry_schema := _load_json("res://data/schemas/content_entry_v2.schema.json")
	suite.assert_equal(pack_schema.get("$id"), "planewalker://schemas/content-pack/2.0.0", "pack schema id")
	suite.assert_equal(entry_schema.get("$id"), "planewalker://schemas/content-entry/2.0.0", "entry schema id")
	suite.assert_true(pack_schema.get("required", []).has("integrity_hashes"), "pack requires integrity hashes")
	suite.assert_true(entry_schema.get("properties", {}).has("effects"), "entry declares effects")
	suite.assert_true(FileAccess.file_exists("res://tests/fixtures/content_packs/valid_base/pack.json"), "valid fixture exists")
	suite.finish(get_tree())
```

- [ ] **Step 2: Run the contract test and confirm red**

Run: `./tools/run_tests.sh --filter content_pack_contract`

Expected: FAIL because the schemas and fixtures do not exist.

- [ ] **Step 3: Define the exact pack envelope**

The pack schema requires:

```json
["pack_id", "pack_version", "schema_version", "game_version_range", "dependencies", "load_order", "content_manifest", "localization_sources", "asset_manifest", "integrity_hashes", "entitlement_tag"]
```

The entry schema requires stable IDs, category, availability, `name_key`, `description_key`, tags, compatibility, and a Dictionary of declarative effect IDs to JSON scalar values. It sets `additionalProperties` to `false` at the entry root and contains no script-path field.

- [ ] **Step 4: Add valid and hostile fixtures**

The valid fixture contains one `item` named `fixture_chronal_edge`. The hostile fixture adds `script_path: "res://evil.gd"` and must be rejected by later runtime validation.

- [ ] **Step 5: Run and commit the frozen contract**

Run: `./tools/run_tests.sh --filter content_pack_contract`

Expected: PASS with zero script errors or leaks.

Commit:

```bash
git add docs/contracts/content-pack-v2.md data/schemas/content_pack_v2.schema.json data/schemas/content_entry_v2.schema.json tests/fixtures/content_packs tests/contract/content_schema/content_pack_contract_test.gd tests/contract/content_schema/content_pack_contract_test.tscn
git commit -m "test(content): freeze content pack v2 contracts"
```

---

### Task 2: Implement Pack Descriptor, Integrity, and Dependency Resolution

**Files:**
- Create: `scripts/content/content_pack_descriptor.gd`
- Create: `scripts/content/content_pack_resolver.gd`
- Create: `tests/unit/content/content_pack_resolver_test.gd`
- Create: `tests/unit/content/content_pack_resolver_test.tscn`
- Create: `tests/fixtures/content_packs/dependency_chain/`
- Create: `tests/fixtures/content_packs/dependency_cycle/`

**Interfaces:**
- Consumes: Task 1 pack contract.
- Produces: `ContentPackDescriptor.load_path(path) -> Dictionary`, `canonical_digest() -> String`, and `ContentPackResolver.resolve(descriptors, game_version) -> ContentValidationReport` with ordered active descriptors in report metadata.

- [ ] **Step 1: Write failing resolver tests**

Cover canonical digest stability, bad digest, duplicate pack ID, missing dependency, dependency cycle, incompatible game version, stable `load_order` tie-breaking, and optional-pack isolation.

```gdscript
var resolved = resolver.resolve([base_pack, update_pack], "0.5.0-dev")
suite.assert_true(not resolved.has_blocking_errors(), "valid dependency chain resolves")
suite.assert_equal(resolved.metadata["activation_order"], ["base", "first_party_update"], "dependency order is deterministic")
```

- [ ] **Step 2: Run and confirm red**

Run: `./tools/run_tests.sh --filter content_pack_resolver`

Expected: FAIL because descriptor and resolver scripts are missing.

- [ ] **Step 3: Implement canonical descriptor loading**

Load `pack.json`, reject unknown root fields, normalize dependency records to `{pack_id, version_range, required}`, sort manifest paths and integrity keys, and compute SHA-256 over canonical JSON excluding stored integrity digests.

- [ ] **Step 4: Implement deterministic topological resolution**

Required base-pack failures populate `blocking_errors`. Optional Mod/DLC failures populate `isolated_errors` and exclude only the unsafe pack plus dependants. Stable ordering is dependency order, ascending `load_order`, then `pack_id`.

- [ ] **Step 5: Run and commit**

Run: `./tools/run_tests.sh --filter content_pack_resolver`

Expected: PASS.

Commit:

```bash
git add scripts/content/content_pack_descriptor.gd scripts/content/content_pack_resolver.gd tests/unit/content tests/fixtures/content_packs/dependency_chain tests/fixtures/content_packs/dependency_cycle
git commit -m "feat(content): resolve versioned content packs"
```

---

### Task 3: Implement the Declarative Effect Catalog

**Files:**
- Create: `scripts/content/effects/effect_definition.gd`
- Create: `scripts/content/effects/effect_handler_catalog.gd`
- Create: `data/content/effect_catalog.json`
- Create: `tests/unit/content/effect_handler_catalog_test.gd`
- Create: `tests/unit/content/effect_handler_catalog_test.tscn`

**Interfaces:**
- Consumes: Content entry `effects` dictionaries.
- Produces: `validate_effects(effects, context) -> ContentValidationReport`, `normalize_effects(effects) -> Dictionary`, and an immutable catalog snapshot. It does not execute arbitrary code.

- [ ] **Step 1: Write failing effect-catalog tests**

Cover every effect ID already present in M1 JSON, numeric bounds, integer-only effects, unknown effect rejection, non-finite number rejection, context compatibility, deterministic normalization, and deep-copy isolation.

```gdscript
var valid = catalog.validate_effects({"attack_multiplier": 1.18, "heal": 20.0}, {"category": "item"})
suite.assert_true(not valid.has_blocking_errors(), "known effects validate")
var invalid = catalog.validate_effects({"res://arbitrary.gd": 1}, {"category": "item"})
suite.assert_true(invalid.has_blocking_errors(), "script-like effect ids fail closed")
```

- [ ] **Step 2: Run and confirm red**

Run: `./tools/run_tests.sh --filter effect_handler_catalog`

Expected: FAIL because the catalog is missing.

- [ ] **Step 3: Add the closed effect catalog**

Each catalog row contains `effect_id`, `value_type`, `minimum`, `maximum`, `stack_rule`, and allowed content categories. Include all current effect IDs discovered from `data/items`, `data/blessings`, `data/curses`, and `data/talents`; do not add speculative runtime effects.

- [ ] **Step 4: Validate without executing content code**

Reject `/`, `\\`, `.gd`, `..`, unknown IDs, wrong scalar types, NaN/Inf, and out-of-range values. Sort effect IDs before returning normalized data.

- [ ] **Step 5: Run and commit**

Run: `./tools/run_tests.sh --filter effect_handler_catalog`

Expected: PASS.

Commit:

```bash
git add scripts/content/effects data/content/effect_catalog.json tests/unit/content/effect_handler_catalog_test.gd tests/unit/content/effect_handler_catalog_test.tscn
git commit -m "feat(content): validate declarative gameplay effects"
```

---

### Task 4: Upgrade ContentRegistry and Create the Base Pack

**Files:**
- Modify: `scripts/content/content_registry.gd`
- Modify: `scripts/content/content_validation_report.gd`
- Create: `scripts/content/content_snapshot_provider.gd`
- Create: `data/content_packs/base/pack.json`
- Create: `data/content_packs/base/content_manifest.json`
- Move or copy with verified parity: existing M1 JSON sources under `data/content_packs/base/content/`
- Modify: `tests/contract/content_schema/content_registry_test.gd`
- Create: `tests/unit/content/content_snapshot_provider_test.gd`
- Create: `tests/unit/content/content_snapshot_provider_test.tscn`

**Interfaces:**
- Consumes: Pack resolver and effect catalog.
- Produces: `load_packs(pack_paths, game_version, execution_mode)`, compatibility `load_manifest(path)`, category/tag/availability queries, cross-reference validation, and `ContentSnapshotProvider.snapshot(registry) -> Dictionary` for SaveService.

- [ ] **Step 1: Add failing activation and snapshot tests**

Cover base-pack activation, optional-pack isolation, global content-ID uniqueness, localization-key presence, effect validation, asset/reference validation, execution-mode eligibility, deep-copy getters, stable snapshots, and changed-pack digest detection.

- [ ] **Step 2: Run and confirm red**

Run:

```bash
./tools/run_tests.sh --filter content_registry
./tools/run_tests.sh --filter content_snapshot_provider
```

Expected: snapshot test fails and pack activation assertions fail.

- [ ] **Step 3: Upgrade the validation report**

Add deep-copied `metadata`, `active_pack_count`, `isolated_pack_ids`, and `content_count_by_category` without changing existing error arrays.

- [ ] **Step 4: Implement pack activation and entry validation**

Activate resolved packs in order, reject duplicate IDs across packs, validate availability/tags/localization/effects/references before indexing, and record each definition's owning `pack_id` and `pack_version`. Compatibility `load_manifest` wraps the legacy manifest as a base-pack adapter only until Task 5 removes callers.

- [ ] **Step 5: Implement deterministic save snapshot**

Return the exact frozen SaveService snapshot shape:

```gdscript
{
	"aggregate_sha256": "<sha256>",
	"packs": [{"pack_id": "base", "pack_version": "1.0.0", "schema_version": 2, "fingerprint_sha256": "<sha256>"}]
}
```

Pack rows are sorted by `pack_id`; callers receive deep copies.

- [ ] **Step 6: Run parity and commit**

Run:

```bash
./tools/run_tests.sh --filter content
./tools/run_tests.sh --filter draft_service
./tools/run_tests.sh --filter legacy_run_adapter
```

Expected: all pass with unchanged M1 offer IDs and deterministic ordering.

Commit only the Task 4 files with precise paths:

```bash
git commit -m "feat(content): activate validated base content pack"
```

---

### Task 5: Retire Hard-Coded Reward Sources and Integrate Runtime Boot

**Files:**
- Modify: `scripts/application/run_runtime_facade.gd`
- Modify: `scripts/ui/reward_selection.gd`
- Modify: `scripts/ui/curse_selection.gd`
- Modify: `scripts/ui/event_selection.gd`
- Modify: `scripts/ui/combat_hud.gd`
- Refactor: `scripts/rewards/reward_pool.gd`
- Refactor: `scripts/rewards/blessing_pool.gd`
- Refactor: `scripts/rewards/talent_pool.gd`
- Refactor: `scripts/curses/curse_pool.gd`
- Remove after parity: `scripts/rewards/reward_data_loader.gd`
- Modify: `tests/reward_system_smoke.gd`
- Create: `tests/integration/content/content_runtime_cutover_test.gd`
- Create: `tests/integration/content/content_runtime_cutover_test.tscn`

**Interfaces:**
- Consumes: Activated `ContentRegistry` and current deterministic `DraftService`.
- Produces: One authoritative registry instance for runtime content; compatibility pool wrappers may format labels but may not contain gameplay definitions or fallback arrays.

- [ ] **Step 1: Write the failing runtime-cutover test**

Assert that boot fails on an invalid base pack, succeeds on the valid base pack, all M1 rewards originate from `pack_id == "base"`, legacy pool files contain no definition arrays, and a selected option preserves the exact canonical registry definition.

- [ ] **Step 2: Run and confirm red**

Run: `./tools/run_tests.sh --filter content_runtime_cutover`

Expected: FAIL because UI compatibility pools still load JSON independently and contain fallback definitions.

- [ ] **Step 3: Inject the registry into selection paths**

The facade owns boot and activation. Selection views receive canonical offers/definitions and stop opening content JSON files. Pool wrappers retain only localization label helpers required by legacy scenes.

- [ ] **Step 4: Delete hard-coded gameplay definition arrays**

Remove `REWARDS`, `BLESSINGS`, `TALENTS`, and `CURSES` after parity tests prove all IDs, fields, ordering, and M1 eligibility come from the base pack.

- [ ] **Step 5: Run focused and smoke regression tests**

Run:

```bash
./tools/run_tests.sh --filter content_runtime_cutover
./tools/run_tests.sh --filter reward_system_smoke
./tools/run_tests.sh --filter run_runtime_facade
./tools/run_tests.sh --filter m1_runtime_smoke
```

Expected: all pass and the Reward smoke introduces no new leak.

- [ ] **Step 6: Commit**

Use exact Task 5 paths and commit:

```bash
git commit -m "refactor(content): make registry the only runtime source"
```

---

### Task 6: Certify P3 and Freeze P4/P5 Handoffs

**Files:**
- Create: `docs/current/2026-09-29-p3-content-registry-evidence.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Modify: `tools/validate_project.sh`

**Interfaces:**
- Consumes: All P3 code, data, and tests.
- Produces: P3 completion evidence, SaveService snapshot-provider handoff, P4 single-RunState boundary, and P5 single-publication boundary.

- [ ] **Step 1: Add P3 tests to the validation entrypoint**

Ensure the full command discovers all new `.tscn` tests and runs a content-pack source audit:

```bash
rg -n 'const (REWARDS|BLESSINGS|TALENTS|CURSES)|RewardDataLoader|script_path' scripts data/content_packs
```

Expected: no hard-coded gameplay definition arrays, no legacy loader use, and no executable script field in activated content.

- [ ] **Step 2: Run clean validation twice**

Run:

```bash
TEST_LOG_DIR=/tmp/planewalker-p3-a ./tools/validate_project.sh
TEST_LOG_DIR=/tmp/planewalker-p3-b ./tools/validate_project.sh
```

Expected: all contract/unit/integration/smoke suites pass; content snapshot digests match.

- [ ] **Step 3: Record exact evidence**

Document commit IDs, activated packs, schema versions, aggregate digest, test counts, isolated-fixture behavior, known warnings, rollback point, SaveService integration contract, and external Mod/DLC entitlement boundaries.

- [ ] **Step 4: Commit certification**

```bash
git add docs/current/2026-09-29-p3-content-registry-evidence.md docs/README.md docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md tools/validate_project.sh
git commit -m "docs(content): certify P3 registry v2"
```

## Definition of Done

- JSON content packs are the only gameplay-definition source.
- Required base-pack failures block boot; invalid optional packs are isolated with diagnostics.
- Dependency, version, integrity, localization, asset, reference, eligibility, and effect validation fail closed.
- Content data cannot execute arbitrary scripts.
- SaveService receives a deterministic activated-pack fingerprint.
- Current M1 offer generation and encounter behavior remain deterministic.
- Hard-coded reward arrays and the fallback data loader are removed.
- Full project validation passes twice from clean state with matching content digests.
