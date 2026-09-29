# Plane Walker P2 Atomic SaveService Evidence

- Status: Verified Locally / Current
- Document Role: Current evidence record
- Authority Level: Execution evidence
- Applies To: P2 local profile persistence, global settings, migration, recovery, profile/domain isolation, and GameState compatibility
- Implementation Status: P2 complete; P3 content snapshot integration is the current handoff
- Owner: Project integration lead
- Depends On: `AGENTS.md`, full-product completion spec, `docs/contracts/save-service-v1.md`
- Verified Commits: `cb6e9ef`, `e153475`, `1ecc716`, `6e3b922`, `72093bd`, `8852a21`
- Last Verified: 2026-09-29
- Rollback Points: every verified commit is focused and independently reversible

## Outcome

Plane Walker no longer truncates one unversioned JSON file as its persistence authority. `SaveService` now owns canonical envelopes, validated paths, atomic promotion, two verified backups, corruption quarantine, ordered recovery, schema refusal, content compatibility, global settings, profile isolation, and structured results.

`GameState` remains a temporary compatibility caller. Its historical `save_path` is read only as a legacy-import/test override. New writes are routed through `SaveService` under the derived `plane_walker/save` root, using profile `slot_1` and domain `base`.

## Verified implementation checkpoints

| Commit | Result |
|---|---|
| `cb6e9ef` | Freezes profile/settings schemas, result codes, destructive fixtures, path rules, and save-service contract tests |
| `e153475` | Adds deterministic adjacent migration registration and legacy schema-0 to schema-1 conversion |
| `1ecc716` | Adds structured results, identifier/path validation, canonical JSON, content snapshots, and SHA-256 envelope integrity |
| `6e3b922` | Adds file operations, atomic transactions, two-backup rotation, recovery, quarantine, global settings, and destructive service tests |
| `72093bd` | Routes GameState compatibility calls through SaveService, imports legacy data once, isolates settings/profile documents, and updates existing runtime tests to use unique roots |
| `8852a21` | Keeps the expected setting-write failure path structured and log-clean instead of provoking an engine filesystem error |

The implementation plan is retained at `docs/superpowers/plans/2026-09-28-plane-walker-p2-atomic-save-service.md`; the frozen contract is `docs/contracts/save-service-v1.md`.

## Persistence guarantees

The verified write transaction is:

```text
validate → canonical envelope → pending.tmp → flush/close → re-read/verify →
backup_1 to backup_2 → primary to backup_1 → atomic primary promotion →
re-read primary and compare digest
```

The destructive matrix proves:

- first save and monotonic sequence creation;
- three-save `primary`, `backup_1`, and `backup_2` ordering;
- pending-file corruption refusal before promotion;
- failure immediately before promotion leaves the previous primary readable;
- corrupt primary recovery in `pending.tmp`, `backup_1`, then `backup_2` order;
- all-corrupt failure without writing defaults;
- exact corrupt bytes retained in deterministic quarantine files;
- corrupt rotation destinations quarantined before replacement;
- forward schema and content-snapshot mismatch refuse backup rollback;
- write re-entry returns `BUSY` without replacing the outer transaction;
- traversal and invalid profile/domain identifiers cause no profile filesystem access;
- global settings use the same transaction and recovery rules without sharing profile paths;
- profiles, base/Mod domains, and settings remain isolated;
- explicit reset cannot recover pre-reset settings from the retained backup generations.

## Save-focused verification

Five scene contracts contain 37 named test cases and 268 assertions:

```text
tests/contract/save/save_contract_test.tscn
tests/unit/save/save_envelope_test.tscn
tests/unit/save/save_migration_registry_test.tscn
tests/unit/save/save_service_test.tscn
tests/integration/save/game_state_save_integration_test.tscn
```

Two independent roots were executed:

```bash
TEST_LOG_DIR=/tmp/planewalker-p2-save-a-20260929 ./tools/run_tests.sh --filter save
TEST_LOG_DIR=/tmp/planewalker-p2-save-b-20260929 ./tools/run_tests.sh --filter save
```

Result for each root:

- 5/5 save scenes passed.
- 0 failed scenes.
- 0 ObjectDB or RID leak warnings.
- Code coverage was not collected and is not inferred from scene or assertion counts.

The committed fixture set was hashed independently after both executions. Both produced:

```text
5945b31e6ca6745c0815eaaa1fb0dacaeb27ae309e2d83b4915f2f55a7dceaab
```

## Legacy compatibility and failure behavior

The GameState integration test proves:

- the historical `{version: 1, persistent: ...}` file imports once;
- the original legacy bytes remain unchanged as a recovery artifact;
- once a valid profile exists, later changes to the legacy file are ignored;
- settings and profile statistics round-trip through separate documents;
- invalid settings fail before replacing the previous profile primary;
- failed load leaves the current in-memory dictionary authoritative;
- profile and Mod-domain data cannot leak into the fixed base scope;
- old `load_persistent`, `save_persistent`, `reset_persistent_data`, `set_setting`, and `get_setting` callers remain supported;
- `setting_changed` emits only after a successful settings transaction.

The reward smoke, legacy runtime adapter, and M1 runtime smoke were moved to unique directories under `PLANEWALKER_TEST_DATA_DIR`. Their focused regressions pass; reward smoke retains only its previously classified exit leak warning.

## Source ownership and path safety

The production source scan found one save-document write primitive:

```text
scripts/save/save_file_ops.gd: FileAccess.open(path, FileAccess.WRITE)
```

`SaveService` is the only production owner that calls this primitive for profile/settings documents. `GameState.save_path` remains bounded to legacy existence checks, read-only import, explicit legacy deletion, service reconfiguration, and test isolation. It does not directly create or truncate a save document.

Profile and domain IDs must match `^[a-z0-9][a-z0-9_-]{0,31}$`. The service constructs all profile paths from validated identifiers, and destructive tests prove traversal values perform no profile filesystem access.

## Unified repository validation

The latest committed `HEAD` was checked from a detached clean clone twice with the single repository entrypoint:

```bash
./tools/validate_project.sh
```

Both executions completed successfully and produced the same gate result:

- localization Python contracts: 7/7 passed;
- playtest-data Python contracts: 13/13 passed;
- M1 release-gate Python contracts: 27/27 passed;
- export-preflight Python contracts: 10/10 passed;
- Godot bootstrap import and clean import completed without a script or resource failure;
- 45/45 discovered scene tests passed;
- no new ObjectDB leak, RID leak, invalid call, missing resource, or script error was found;
- `tests/reward_system_smoke.tscn` produced the one previously classified ObjectDB exit warning in each run.

Validation logs are retained at:

```text
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.VT0839
/var/folders/2r/hcrdmp2s4r7cxjdcrf76l_5w0000gn/T/planewalker-validation.eNLh8J
```

The repeated clean-clone result certifies that P2 persistence behavior remains reproducible after the integrated P3 content cutover, P4 authoritative-state encapsulation, P6 input-action contract, and P7/P9 export preflight commits present in the verified `HEAD`.

## P3 content snapshot handoff

P2 currently configures GameState with a deterministic base snapshot so save compatibility is stable before runtime pack assembly owns the active set.

P3 commit `4d30f5a` adds `ContentSnapshotProvider.snapshot(registry)`. It emits the exact SaveService shape:

```text
aggregate_sha256
packs[]: pack_id, pack_version, schema_version, fingerprint_sha256
```

The P3 assembly handoff is to inject that active-registry snapshot when configuring SaveService. The P2 envelope, integrity, refusal, and recovery formats do not change. A changed active pack set must continue to return `CONTENT_MISMATCH` rather than silently loading a backup from another content set.

## P4 GameState retirement boundary

P4 removes GameState's live run mirrors and mutations: phase, floor, room, seed, timer, current run, terminal result, build state, and legacy runtime transitions move to the authoritative RunOrchestrator/RunRuntimeHost path.

P4 does not reopen persistence ownership. The SaveService-backed settings/profile compatibility methods remain until their callers are migrated to a dedicated profile/settings composition boundary. Any later removal must preserve one-time legacy import, settings/profile separation, failure semantics, and the P2 regression suite.

## Known limitations

- `tests/reward_system_smoke.tscn` retains its previously classified ObjectDB exit leak. The runner allows this one named warning and fails every new leak.
- Scene execution does not produce line/branch coverage; no coverage percentage is claimed.
- GameState uses the deterministic base snapshot until P3 runtime assembly injects `ContentSnapshotProvider` output.
- Cloud sync remains an optional future provider and is not a primary persistence authority.

## Gate decision

P2 Atomic SaveService is complete. Atomic replacement, two-generation backup rotation, recovery, quarantine, refusal, migrations, isolation, and legacy compatibility are verified. P3 ContentRegistry v2 and effect runtime is the current foundation phase; P4 later removes GameState run authority without weakening this persistence boundary.
