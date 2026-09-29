# Plane Walker P2 Atomic SaveService Implementation Plan

- Status: Completed / Historical
- Document Role: Historical implementation record
- Authority Level: Preserved P2 persistence implementation record
- Applies To: Atomic profile/settings persistence, migration, recovery, compatibility, and GameState routing
- Owner: Project integration lead
- Depends On: `AGENTS.md`, `docs/contracts/save-service-v1.md`, `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`
- Last Verified: 2026-09-29
- Implementation Status: P2 implementation and certification are complete
- Completion Evidence: `docs/current/2026-09-29-p2-atomic-save-evidence.md` and commits `cb6e9ef`, `e153475`, `1ecc716`, `6e3b922`, `72093bd`, and `8852a21`

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven development when available. Implement tasks in order, keep file ownership isolated, and review every focused commit before integration.

**Goal:** Replace `GameState`'s destructive single-file JSON persistence with a versioned, integrity-checked, profile-isolated SaveService that atomically stages writes, rotates two backups, recovers corruption, rejects forward versions, and preserves the current M1 settings/progression behavior.

**Architecture:** Pure `RefCounted` save-domain objects own canonical serialization, migration, path policy, file transactions, and structured results. `GameState` remains a temporary compatibility caller and may only submit or consume deep-copied dictionaries; P4 will later retire its remaining run-state ownership. Content compatibility is represented by a deterministic snapshot provider so P3 can replace the base fixture without changing the save format.

**Tech Stack:** Godot 4.6.1, typed GDScript, JSON envelopes, SHA-256 via `HashingContext`, Godot `FileAccess`/`DirAccess`, scene-based contract and integration tests.

## Global Constraints

- Current save schema is `1`; legacy `{version: 1, persistent: ...}` documents are treated as legacy schema `0`.
- Save integrity detects corruption; it is not represented as cryptographic anti-cheat.
- Profile and domain IDs must match `^[a-z0-9][a-z0-9_-]{0,31}$`.
- `FORWARD_VERSION` and `CONTENT_MISMATCH` never fall back to an older backup.
- The service never writes default data while recovery is unresolved.
- Production save data contains no private identity, platform credentials, or arbitrary script paths.
- Tests use `PLANEWALKER_TEST_DATA_DIR`; no shared fixed temporary path.
- Existing settings, run summary, localization, pause, CombatFeedback, and M1 flows must remain compatible.

---

### Task 1: Freeze Save Contracts and Destructive Fixtures

**Files:**
- Create: `docs/contracts/save-service-v1.md`
- Create: `data/schemas/save_profile_v1.schema.json`
- Create: `data/schemas/save_settings_v1.schema.json`
- Create: `tests/fixtures/save/legacy_v0.json`
- Create: `tests/fixtures/save/forward_v2.json`
- Create: `tests/fixtures/save/corrupt_truncated.json`
- Create: `tests/fixtures/save/corrupt_integrity.json`
- Create: `tests/fixtures/save/profile_v1.json`
- Create: `tests/fixtures/save/migration_expected_v1.json`
- Test: `tests/contract/save/save_contract_test.gd`
- Test: `tests/contract/save/save_contract_test.tscn`

**Interfaces:**
- Consumes: Approved P2 contract in `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`.
- Produces: Frozen envelope fields, error codes, fixture meanings, and profile/domain constraints used by all later tasks.

- [ ] **Step 1: Write the failing contract test**

```gdscript
func _run() -> void:
	var suite = TestSuiteScript.new()
	var schema := _load_json("res://data/schemas/save_profile_v1.schema.json")
	suite.assert_equal(schema.get("$id"), "planewalker://schemas/save-profile/1.0.0", "profile schema id")
	suite.assert_true(schema.get("required", []).has("integrity"), "profile envelope requires integrity")
	suite.assert_true(FileAccess.file_exists("res://tests/fixtures/save/legacy_v0.json"), "legacy fixture exists")
	suite.finish(get_tree())
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `./tools/run_tests.sh --filter save_contract`

Expected: FAIL because the schemas and fixtures do not exist.

- [ ] **Step 3: Add exact schemas, fixtures, and contract documentation**

The profile schema must require:

```json
["magic", "schema_version", "document_kind", "profile_id", "save_domain", "sequence", "game_version", "created_at_utc", "saved_at_utc", "content_snapshot", "payload", "integrity"]
```

The integrity object is exactly:

```json
{"algorithm": "sha256", "digest": "64 lowercase hexadecimal characters"}
```

- [ ] **Step 4: Run the contract test**

Run: `./tools/run_tests.sh --filter save_contract`

Expected: PASS with no script errors or leaks.

- [ ] **Step 5: Commit the frozen contract**

```bash
git add docs/contracts/save-service-v1.md data/schemas/save_profile_v1.schema.json data/schemas/save_settings_v1.schema.json tests/fixtures/save tests/contract/save
git commit -m "docs(save): freeze atomic save contracts"
```

---

### Task 2: Implement Structured Results, Path Policy, and Canonical Envelope

**Files:**
- Create: `scripts/save/save_result.gd`
- Create: `scripts/save/save_path_policy.gd`
- Create: `scripts/save/save_envelope.gd`
- Test: `tests/unit/save/save_envelope_test.gd`
- Test: `tests/unit/save/save_envelope_test.tscn`

**Interfaces:**
- Consumes: Task 1 envelope and error-code contract.
- Produces: `SaveResult`, validated path construction, canonical JSON, SHA-256 digest creation, envelope validation, and deep-copy guarantees.

- [ ] **Step 1: Write failing result, path, and envelope tests**

```gdscript
var result = SaveResultScript.success({"nested": {"value": 1}})
var copied := result.payload
copied["nested"]["value"] = 9
suite.assert_equal(result.payload["nested"]["value"], 1, "result payload is isolated")

suite.assert_true(PathPolicyScript.is_valid_id("slot_1"), "slot id accepted")
suite.assert_true(not PathPolicyScript.is_valid_id("../slot_1"), "path traversal rejected")

var envelope := EnvelopeScript.create_profile(
	&"slot_1", &"base", 1, {"value": 3}, _content_snapshot(),
	"0.5.0-dev", "2026-09-28T08:00:00Z", "2026-09-28T08:00:00Z"
)
suite.assert_true(EnvelopeScript.validate(envelope, &"slot_1", &"base").ok, "valid envelope passes")
envelope["payload"]["value"] = 4
suite.assert_equal(EnvelopeScript.validate(envelope, &"slot_1", &"base").code, &"CORRUPT", "payload tampering fails")
```

- [ ] **Step 2: Run the unit test and confirm it fails**

Run: `./tools/run_tests.sh --filter save_envelope`

Expected: FAIL because save-domain scripts are missing.

- [ ] **Step 3: Implement `SaveResult`**

Expose constants `OK`, `NOT_FOUND`, `RECOVERED`, `INVALID_ARGUMENT`, `IO_ERROR`, `CORRUPT`, `FORWARD_VERSION`, `MIGRATION_UNAVAILABLE`, `MIGRATION_FAILED`, `CONTENT_MISMATCH`, and `BUSY`. Factory methods must deep-copy payload, metadata, and diagnostics.

- [ ] **Step 4: Implement path validation**

```gdscript
static func is_valid_id(value: String) -> bool:
	return ID_PATTERN.search(value) != null

static func profile_directory(root_path: String, profile_id: String, save_domain: String) -> String:
	assert(is_valid_id(profile_id) and is_valid_id(save_domain))
	return root_path.path_join("profiles").path_join(profile_id).path_join(save_domain)
```

- [ ] **Step 5: Implement canonical envelope hashing**

Use `JSON.stringify(value, "", true)` for stable key order. Remove `integrity` from a deep copy before hashing the entire envelope with SHA-256. Validate magic, schema, kind, profile, domain, sequence, timestamps, content snapshot, payload, algorithm, and digest.

- [ ] **Step 6: Run the unit test**

Run: `./tools/run_tests.sh --filter save_envelope`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/save/save_result.gd scripts/save/save_path_policy.gd scripts/save/save_envelope.gd tests/unit/save
git commit -m "feat(save): add canonical save envelope"
```

---

### Task 3: Implement Ordered Migration Registry and Legacy Import

**Files:**
- Create: `scripts/save/save_migration_registry.gd`
- Create: `scripts/save/migrations/save_migration_v0_to_v1.gd`
- Test: `tests/unit/save/save_migration_registry_test.gd`
- Test: `tests/unit/save/save_migration_registry_test.tscn`

**Interfaces:**
- Consumes: `SaveResult` and Task 1 fixtures.
- Produces: deterministic adjacent-version migration with no source mutation and the legacy GameState document importer.

- [ ] **Step 1: Write failing migration tests**

Cover duplicate step rejection, non-adjacent step rejection, missing step, thrown migration, non-Dictionary output, wrong target version, source immutability, deterministic repeated output, and forward-version refusal.

```gdscript
var source := {"version": 1, "persistent": {"runs_completed": 2}}
var first = registry.migrate(source, 1)
var second = registry.migrate(source, 1)
suite.assert_true(first.ok and second.ok, "legacy fixture migrates")
suite.assert_equal(first.payload, second.payload, "migration is deterministic")
suite.assert_equal(source, {"version": 1, "persistent": {"runs_completed": 2}}, "source is unchanged")
```

- [ ] **Step 2: Run the test and confirm failure**

Run: `./tools/run_tests.sh --filter save_migration_registry`

Expected: FAIL because the registry is missing.

- [ ] **Step 3: Implement adjacent migration registration**

`register_step(from_version, to_version, migration)` accepts only `to_version == from_version + 1`, rejects duplicate `from_version`, and returns a structured result rather than asserting.

- [ ] **Step 4: Implement migration execution**

Each step receives a deep copy, must return a Dictionary with the exact next `schema_version`, and is applied until `target_version`. Exceptions and invalid results return `MIGRATION_FAILED`; gaps return `MIGRATION_UNAVAILABLE`.

- [ ] **Step 5: Implement legacy v0 to profile payload v1**

Convert `{version: 1, persistent: {...}}` into a migration document with `schema_version: 1` and the original persistent dictionary under `payload.persistent`. Do not invent content IDs or silently delete unknown legacy keys.

- [ ] **Step 6: Run the migration tests**

Run: `./tools/run_tests.sh --filter save_migration_registry`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/save/save_migration_registry.gd scripts/save/migrations tests/unit/save/save_migration_registry_test.*
git commit -m "feat(save): add deterministic save migrations"
```

---

### Task 4: Implement Atomic Writes, Backup Rotation, and Recovery

**Files:**
- Create: `scripts/save/save_file_ops.gd`
- Create: `scripts/save/save_service.gd`
- Test: `tests/unit/save/save_service_test.gd`
- Test: `tests/unit/save/save_service_test.tscn`

**Interfaces:**
- Consumes: Envelope, result, path, and migration APIs from Tasks 2–3.
- Produces: `configure`, `save_profile`, `load_profile`, `inspect_profile`, `reset_profile`, `save_settings`, and `load_settings`.

- [ ] **Step 1: Write destructive failing tests**

Use a unique directory under `PLANEWALKER_TEST_DATA_DIR`. Cover first save, three-save backup order, temp corruption, fault injection before promotion, primary corruption recovery, backup-2 recovery, future-version refusal without fallback, content mismatch without fallback, all-corrupt result, quarantine, write re-entry, and path traversal.

- [ ] **Step 2: Run the service test and confirm failure**

Run: `./tools/run_tests.sh --filter save_service`

Expected: FAIL because SaveService is missing.

- [ ] **Step 3: Implement `SaveFileOps`**

Wrap directory creation, UTF-8 read/write, flush/close, copy, rename, remove, and quarantine operations. The injected fault callable receives stable points: `after_pending_write`, `after_pending_verify`, `after_backup_2`, `after_backup_1`, `before_primary_promote`, and `after_primary_promote`.

- [ ] **Step 4: Implement profile save transaction**

```text
validate inputs → build next sequence envelope → write pending.tmp → close →
re-read and validate pending → copy verified backup_1 to backup_2 →
copy verified primary to backup_1 → promote pending to primary →
re-read primary and compare digest → success
```

Keep the previous primary readable until the final promotion. A failed transaction returns a structured error and never writes defaults.

- [ ] **Step 5: Implement load and recovery policy**

Validate primary first. Immediately return `FORWARD_VERSION` or `CONTENT_MISMATCH` without checking backups. Only corruption triggers quarantine and the order `pending.tmp → backup_1 → backup_2`. A recovered document is promoted through a verified repair path and returns `RECOVERED` with `source_kind` metadata.

- [ ] **Step 6: Implement global settings storage**

Settings use `global/settings` and the same envelope/transaction/recovery rules, but are independent of profiles and save domains.

- [ ] **Step 7: Run service tests**

Run: `./tools/run_tests.sh --filter save_service`

Expected: PASS with zero unexpected leaks.

- [ ] **Step 8: Commit**

```bash
git add scripts/save/save_file_ops.gd scripts/save/save_service.gd tests/unit/save/save_service_test.*
git commit -m "feat(save): add atomic profile persistence"
```

---

### Task 5: Integrate GameState Compatibility and One-Time Legacy Import

**Files:**
- Modify: `autoload/game_state.gd`
- Modify: `tests/reward_system_smoke.gd`
- Modify: `tests/integration/application/legacy_run_adapter_test.gd`
- Modify: `tests/smoke/m1_runtime_smoke_test.gd`
- Create: `tests/integration/save/game_state_save_integration_test.gd`
- Create: `tests/integration/save/game_state_save_integration_test.tscn`

**Interfaces:**
- Consumes: `SaveService` public API.
- Produces: Backward-compatible `load_persistent`, `save_persistent`, and `reset_persistent_data` methods backed by the new service.

- [ ] **Step 1: Write failing integration tests**

Cover one-time legacy import, global settings persistence, profile statistics persistence, failure preserving in-memory authoritative data, profile isolation, base/Mod domain isolation, and old caller compatibility.

- [ ] **Step 2: Run the integration test and confirm failure**

Run: `./tools/run_tests.sh --filter game_state_save_integration`

Expected: FAIL because GameState still performs direct file I/O.

- [ ] **Step 3: Add a SaveService compatibility instance to GameState**

Keep `save_path` only as a deprecated test/import override during P2. Derive the service root from its parent directory, use profile `slot_1` and domain `base`, and expose a deterministic base content snapshot until P3 supplies the active-pack snapshot.

- [ ] **Step 4: Route settings and persistent profile calls**

`set_setting()` updates memory, calls `save_settings`, and emits only after a successful write. `save_persistent()` deep-copies profile data. Failed writes return false without replacing the existing primary. `load_persistent()` commits loaded data to memory only after a successful or recovered result.

- [ ] **Step 5: Import the legacy file once**

If the new profile is absent and the legacy path exists, migrate it, save the new profile, and preserve the legacy bytes as an import artifact or backup. Never import again once a valid new profile exists.

- [ ] **Step 6: Update existing tests to use isolated directories**

Preserve all previous assertions for pause settings, accessibility flags, run counts, summaries, M1 lifecycle, and cleanup. Tests must not share profile paths.

- [ ] **Step 7: Run focused regression tests**

Run:

```bash
./tools/run_tests.sh --filter game_state_save_integration
./tools/run_tests.sh --filter reward_system_smoke
./tools/run_tests.sh --filter legacy_run_adapter
./tools/run_tests.sh --filter m1_runtime_smoke
```

Expected: all focused tests pass; only the already-classified legacy Reward smoke warning may remain.

- [ ] **Step 8: Commit**

```bash
git add autoload/game_state.gd tests/reward_system_smoke.gd tests/integration/application/legacy_run_adapter_test.gd tests/smoke/m1_runtime_smoke_test.gd tests/integration/save
git commit -m "refactor(save): route GameState through SaveService"
```

---

### Task 6: P2 Full Validation and Completion Evidence

**Files:**
- Create: `docs/current/2026-09-28-p2-atomic-save-evidence.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md`

**Interfaces:**
- Consumes: All P2 code and tests.
- Produces: P2 completion evidence and the frozen P3 handoff contract.

- [ ] **Step 1: Run the complete validation entrypoint**

Run: `./tools/validate_project.sh`

Expected: localization, playtest, M1, imports, and every discovered scene pass; no new leak classification is added.

- [ ] **Step 2: Run destructive save tests twice from clean test roots**

Run:

```bash
TEST_LOG_DIR=/tmp/planewalker-p2-save-a ./tools/run_tests.sh --filter save
TEST_LOG_DIR=/tmp/planewalker-p2-save-b ./tools/run_tests.sh --filter save
```

Expected: identical fixture digests and all save tests pass both times.

- [ ] **Step 3: Verify source ownership and path safety**

Run:

```bash
rg -n 'FileAccess\.open\(.*WRITE|save_path' autoload scripts
rg -n 'pending\.tmp|backup_1|backup_2|FORWARD_VERSION|CONTENT_MISMATCH' scripts/save tests
```

Expected: production persistence writes are owned by SaveService; compatibility references are documented and bounded.

- [ ] **Step 4: Write completion evidence**

Record exact commits, schema version, test counts, destructive scenarios, known warning status, rollback point, P3 fingerprint-provider handoff, and P4 GameState retirement boundary.

- [ ] **Step 5: Commit evidence and status**

```bash
git add docs/current/2026-09-28-p2-atomic-save-evidence.md docs/README.md docs/superpowers/specs/2026-09-28-plane-walker-full-product-completion-design.md
git commit -m "docs(save): certify P2 atomic persistence"
```

## Definition of Done

- No production code truncates the only primary save directly.
- Temp content is closed, re-read, and integrity-validated before promotion.
- Two verified backups rotate in the correct order.
- Corruption recovery, quarantine, and all-corrupt behavior are tested.
- Future schema and incompatible content never fall back to older backups.
- Migration steps are adjacent, deterministic, and source-immutable.
- Profiles, Mod domains, and global settings are isolated.
- Legacy M1 settings and progression migrate exactly once.
- P2 tests and the full project validation pass from clean state.
