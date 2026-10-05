# Auxiliary Snapshot Validation Cache Implementation Plan

- Status: Implemented / Current
- Document Role: Current focused implementation plan
- Authority Level: Below approved full-product completion contract
- Applies To: VoidArenaRuntime, ForgeArenaRuntime and ForestAuxiliaryRuntime
- Owner: Gameplay performance lane
- Depends On: `docs/superpowers/specs/2026-10-05-native-performance-probe-design.md`
- Last Verified: 2026-10-06
- Evidence Status: Verified Locally
- Certification Status: Focused cache and native regressions passed; no performance certification

> Agent execution: implement this focused milestone inline, preserving the parent agent's ownership of Boss, Player, and Main.

**Goal:** Reduce repeated auxiliary cold reconstruction while preserving all accepted and rejected snapshot verdicts.

**Architecture:** Use the established Void auxiliary pattern: four-entry, positive-only FIFO caches, synchronized by a static Mutex. Cache exact typed candidate bytes together with immutable configuration context and the committed-boundary mode; retain the existing cold validator as the miss authority.

**Tech Stack:** Godot 4.6.1 GDScript, headless scene tests, native Python performance probe.

## Constraints

- Only Void arena, Forge arena, Forest auxiliary, their cache test, and this milestone's evidence are owned here.
- Preserve integral-float acceptance where the existing contract permits it.
- Do not equate general restore with accepted-boundary restore.
- Do not publish, push, or claim unsupported line coverage or a 60Hz performance pass.
- Compare frozen uninstrumented sources; instrumentation provides diagnosis only.

## Validation Cache

Files:

- Modify `scripts/enemies/launch/void_arena_runtime.gd`.
- Modify `scripts/enemies/launch/forge_arena_runtime.gd`.
- Modify `scripts/enemies/launch/forest_auxiliary_runtime.gd`.
- Create `tests/unit/enemies/auxiliary_snapshot_validation_cache_test.gd` and `.tscn`.

Interface remains `can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool`.

- [x] Add an authentic three-domain test that warms accepted snapshots, checks typed cache storage, checks cold/warm verdict equality for forged fields, separates staged and committed events, changes identity and origin, checks eviction, mutation isolation, and parallel cloned readers.
- [x] Run `TEST_LOG_DIR=build/auxiliary-cache-red-20261006 tools/run_tests.sh --filter auxiliary_snapshot_validation_cache_test`; require a test assertion failure proving accepted snapshots are not yet cached.
- [x] Preserve each current body as `_can_restore_snapshot_uncached`. Use the wrapper below, with domain-specific context.

```gdscript
func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _initial.is_empty():
		return false
	var context := _validation_context
	var encoded := var_to_bytes(value)
	if _validation_cache_contains(context, encoded, accepted_boundary):
		return true
	if not _can_restore_snapshot_uncached(value, accepted_boundary):
		return false
	_cache_validated_snapshot(context, encoded, accepted_boundary)
	return true
```

Void context uses `[_definition, _initial, _state.get("arena_origin")]`. Forge uses `[_definition, _initial]`; its initial already contains the bound origin. Forest uses `[_initial, _state.get("arena_origin")]`; its replay methods consume the initial state and fixed authored rules.

Compute `_validation_context = var_to_bytes(context_fields)` after successful
configuration and every successful origin bind. Void clears it at configuration
start because its established failure policy clears the domain; Forge and Forest
retain their established previous-domain failure policy. Ordinary frame advance
and valid same-origin restore leave these context fields unchanged.

```gdscript
static func _validation_cache_contains(context: PackedByteArray, encoded: PackedByteArray, accepted_boundary: bool) -> bool:
	_validation_cache_mutex.lock()
	for row: Dictionary in _validation_cache:
		if row.accepted_boundary == accepted_boundary and row.context == context and row.snapshot == encoded:
			_validation_cache_mutex.unlock()
			return true
	_validation_cache_mutex.unlock()
	return false


static func _cache_validated_snapshot(context: PackedByteArray, encoded: PackedByteArray, accepted_boundary: bool) -> void:
	_validation_cache_mutex.lock()
	for row: Dictionary in _validation_cache:
		if row.accepted_boundary == accepted_boundary and row.context == context and row.snapshot == encoded:
			_validation_cache_mutex.unlock()
			return
	if _validation_cache.size() == MAX_VALIDATION_CACHE:
		_validation_cache.pop_front()
	_validation_cache.append({"context": context, "snapshot": encoded, "accepted_boundary": accepted_boundary})
	_validation_cache_mutex.unlock()
```

- [x] Run the cache test GREEN and the three existing domain tests; inspect both stdout and engine logs for script errors and leaks.
- [x] Run native Boss arenas, checkpoint, and replay integration regressions relevant to these domains.
- [x] Freeze parent-approved before sources and after sources differing only in the three runtime files. Run native probes on floors 1, 3 and 4, corresponding to the three affected Boss domains; compare source manifests, replay boundary hashes, sample counts, content digests, encounter identity, and peak physical counts.
- [x] Record exact commands, logs, timings, limitations, and rollback revision in `docs/current/2026-10-06-auxiliary-snapshot-cache-evidence.md`.
- [x] Review `git diff --check`, commit only owned files, and send the parent the commit and evidence paths for the shared documentation index.
