class_name ExpansionContentManager
extends RefCounted

const Installer := preload("res://scripts/expansion/data_only_pack_installer.gd")
const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Snapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const OfflineProvider := preload("res://scripts/expansion/offline_entitlement_provider.gd")
const SELECTION_FIELDS := ["schema_version", "installed", "enabled_pack_ids"]

var _configured := false
var _busy := false
var _base_specs: Array = []
var _base_ids: Array[String] = []
var _game_version := ""
var _execution_mode: StringName = &"EXPANSION"
var _provider: Callable
var _run_lock: Callable
var _installer = Installer.new()
var _save = Save.new()
var _installed: Dictionary = {}
var _intent: Array[String] = []
var _enabled: Array[String] = []
var _registry: RefCounted
var _activation: Dictionary = {}
var _entitlements: Dictionary = {}
var _diagnostics: Array[Dictionary] = []
var _selected_fingerprints: Dictionary = {}


func configure(storage_root: String, base_specs: Array, game_version: String, execution_mode: StringName, entitlement_provider: Callable, run_lock: Callable) -> Dictionary:
	if _configured or _busy or not run_lock.is_valid() or base_specs.is_empty():
		return _failure(&"INVALID_ARGUMENT", {"field": "configuration"})
	var locked: Variant = run_lock.call()
	if typeof(locked) != TYPE_BOOL:
		return _failure(&"INVALID_RUN_LOCK")
	var base = Registry.new()
	var report = base.load_packs(base_specs, game_version, execution_mode)
	if report.has_blocking_errors() or base.active_packs().is_empty():
		return _failure(&"BASE_CONTENT_INVALID", {"errors": report.blocking_errors})
	var installed_result: Dictionary = _installer.configure(storage_root)
	if not installed_result.ok:
		return installed_result
	var saved = _save.configure(storage_root.path_join("selection"), game_version, _management_snapshot())
	if not saved.ok:
		return _failure(saved.code, saved.metadata)
	_base_specs = base_specs.duplicate(true)
	for descriptor: Dictionary in base.active_packs():
		_base_ids.append(str(descriptor.pack_id))
	_game_version = game_version
	_execution_mode = execution_mode
	_provider = entitlement_provider
	_run_lock = run_lock
	_refresh_installed()
	_refresh_entitlements()
	var retained = _save.load_profile("selection", "manager")
	var saved_fingerprints: Dictionary = {}
	if retained.ok:
		var selection: Variant = retained.payload.get("expansion_content_selection")
		if _selection_valid(selection):
			_intent.assign(selection.enabled_pack_ids)
			saved_fingerprints = selection.installed.duplicate(true)
		else:
			_diagnostics.append({"code": "INVALID_SELECTION"})
	elif retained.code != &"NOT_FOUND":
		_diagnostics.append({"code": "SELECTION_UNAVAILABLE", "reason": str(retained.code)})
	_selected_fingerprints = saved_fingerprints
	var candidate := _build_candidate(_compatible_intent(), _installed, false)
	if not candidate.ok:
		return candidate
	_publish(candidate)
	_configured = true
	return _success({"isolated": _intent != _enabled})


func refresh() -> Dictionary:
	var ready := _mutation_ready()
	if not ready.ok:
		return ready
	_busy = true
	_diagnostics.clear()
	_refresh_installed()
	_refresh_entitlements()
	var candidate := _build_candidate(_compatible_intent(), _installed, false)
	if candidate.ok:
		var still_ready := _check_run_lock()
		if still_ready.ok:
			_publish(candidate)
		else:
			candidate = still_ready
	_busy = false
	return _success({"isolated": _intent != _enabled}) if candidate.ok else candidate


func install(source_directory: String) -> Dictionary:
	var ready := _mutation_ready()
	if not ready.ok:
		return ready
	_busy = true
	var result := _install_internal(source_directory)
	_busy = false
	return result


func _install_internal(source_directory: String) -> Dictionary:
	_refresh_installed()
	var inspected := _installer.inspect(source_directory)
	if not inspected.ok:
		return inspected
	var descriptor: Dictionary = inspected.context.descriptor
	var id := str(descriptor.pack_id)
	if _base_ids.has(id):
		return _failure(&"BASE_PACK_IMMUTABLE", {"pack_id": id})
	if _installed.has(id):
		return _success({"installed": false, "pack_id": id}) if _installed[id].fingerprint_sha256 == descriptor.fingerprint_sha256 else _failure(&"PACK_ALREADY_INSTALLED", {"pack_id": id})
	var prepared := _installer.prepare(source_directory)
	if not prepared.ok:
		return prepared
	var fingerprint := str(prepared.context.descriptor.fingerprint_sha256)
	if fingerprint != str(descriptor.fingerprint_sha256):
		if prepared.context.get("prepared", false):
			_installer.discard_prepared(fingerprint)
		return _failure(&"SOURCE_CHANGED")
	var installations := _installed.duplicate(true)
	installations[id] = prepared.context.descriptor
	var validation_ids := _installation_dependency_ids(id, installations)
	var validated := _build_candidate(validation_ids, installations, true, false)
	if not validated.ok:
		if prepared.context.get("prepared", false):
			_installer.discard_prepared(fingerprint)
		return validated
	var still_ready := _check_run_lock()
	if not still_ready.ok:
		if prepared.context.get("prepared", false):
			_installer.discard_prepared(fingerprint)
		return still_ready
	var installed := _installer.commit_prepared(fingerprint) if prepared.context.get("prepared", false) else prepared
	if not installed.ok:
		return installed
	installations[id] = installed.context.descriptor
	var persisted := _persist(_intent, installations)
	if not persisted.ok:
		if installed.context.get("installed", false):
			_installer.uninstall(fingerprint)
		return persisted
	_installed = installations
	return _success({"installed": true, "pack_id": id, "fingerprint_sha256": descriptor.fingerprint_sha256})


func _installation_dependency_ids(pack_id: String, installations: Dictionary) -> Array[String]:
	var ids: Array[String] = _enabled.duplicate()
	var pending: Array[String] = [pack_id]
	while not pending.is_empty():
		var id := pending.pop_back() as String
		if _base_ids.has(id) or ids.has(id):
			continue
		ids.append(id)
		if not installations.has(id):
			continue
		for dependency: Dictionary in installations[id].dependencies:
			if dependency.required:
				pending.append(str(dependency.pack_id))
	ids.sort()
	return ids


func set_enabled(pack_ids: Array) -> Dictionary:
	var ready := _mutation_ready()
	if not ready.ok:
		return ready
	var ids := _validated_ids(pack_ids)
	if not ids.ok:
		return ids
	_busy = true
	_refresh_installed()
	_refresh_entitlements()
	var candidate := _build_candidate(ids.context.ids, _installed, true)
	if candidate.ok:
		var still_ready := _check_run_lock()
		var retained := _persist(ids.context.ids, _installed) if still_ready.ok else still_ready
		if retained.ok:
			_intent.assign(ids.context.ids)
			_diagnostics.clear()
			_publish(candidate)
		else:
			candidate = retained
	_busy = false
	return _success({"activation": activation_context()}) if candidate.ok else candidate


func uninstall(pack_id: String) -> Dictionary:
	var ready := _mutation_ready()
	if not ready.ok:
		return ready
	if _base_ids.has(pack_id):
		return _failure(&"BASE_PACK_IMMUTABLE", {"pack_id": pack_id})
	if _enabled.has(pack_id) or _intent.has(pack_id):
		return _failure(&"PACK_ENABLED", {"pack_id": pack_id})
	_busy = true
	_refresh_installed()
	if not _installed.has(pack_id):
		_busy = false
		return _failure(&"PACK_NOT_INSTALLED", {"pack_id": pack_id})
	var remaining := _installed.duplicate(true)
	var fingerprint := str(remaining[pack_id].fingerprint_sha256)
	remaining.erase(pack_id)
	var retained := _persist(_intent, remaining)
	if retained.ok:
		retained = _installer.uninstall(fingerprint)
		if retained.ok:
			_installed = remaining
	_busy = false
	return retained


func discovery() -> Dictionary:
	var rows: Array[Dictionary] = []
	var ids: Array[String] = []
	ids.assign(_installed.keys())
	ids.sort()
	for id: String in ids:
		var descriptor: Dictionary = _installed[id]
		var tag := str(descriptor.entitlement_tag)
		var owned: bool = tag.is_empty() or _entitlements.get("owned_tags", []).has(tag)
		rows.append({"pack_id": id, "pack_version": descriptor.pack_version, "fingerprint_sha256": descriptor.fingerprint_sha256, "dependencies": descriptor.dependencies.duplicate(true), "entitlement_tag": tag, "owned": owned, "enabled": _enabled.has(id), "status": "ENABLED" if _enabled.has(id) else ("INSTALLED" if owned else "ENTITLEMENT_REQUIRED")})
	return {"installed": rows, "enabled_pack_ids": _enabled.duplicate(), "requested_pack_ids": _intent.duplicate(), "entitlements": _entitlements.duplicate(true), "diagnostics": _diagnostics.duplicate(true), "activation": activation_context()}


func activation_context() -> Dictionary:
	return _activation.duplicate(true)


func active_registry() -> RefCounted:
	return _registry


func set_selection_fault_injector(injector: Callable) -> void:
	_save.set_fault_injector(injector)


func _build_candidate(ids: Array[String], installations: Dictionary, strict: bool, enforce_entitlements: bool = true) -> Dictionary:
	var specs: Array = _base_specs.duplicate(true)
	var diagnostics: Array[Dictionary] = []
	for id: String in ids:
		var reason := ""
		if not installations.has(id):
			reason = "PACK_NOT_INSTALLED"
		elif _base_ids.has(id):
			reason = "BASE_PACK_IMMUTABLE"
		elif enforce_entitlements and not str(installations[id].entitlement_tag).is_empty() and not _entitlements.get("owned_tags", []).has(str(installations[id].entitlement_tag)):
			reason = "ENTITLEMENT_REQUIRED"
		if not reason.is_empty():
			diagnostics.append({"code": reason, "pack_id": id})
			if strict:
				return _failure(StringName(reason), {"pack_id": id})
			continue
		specs.append({"path": installations[id].source_path, "required": false, "pack_id": id})
	var candidate = Registry.new()
	var report = candidate.load_packs(specs, _game_version, _execution_mode)
	if report.has_blocking_errors():
		return _failure(&"CONTENT_CANDIDATE_INVALID", {"errors": report.blocking_errors})
	var actual_ids: Array[String] = []
	var activation_order: Array[String] = []
	var actual_specs: Array = []
	for descriptor: Dictionary in candidate.active_packs():
		var id := str(descriptor.pack_id)
		activation_order.append(id)
		actual_specs.append({"path": descriptor.source_path, "required": _base_ids.has(id), "pack_id": id})
		if not _base_ids.has(id):
			actual_ids.append(id)
	actual_ids.sort()
	if strict and actual_ids != ids:
		return _failure(&"CONTENT_CANDIDATE_INVALID", {"requested": ids.duplicate(), "activated": actual_ids, "errors": report.isolated_errors})
	for error: Dictionary in report.isolated_errors:
		diagnostics.append({"code": "CONTENT_ISOLATED", "detail": error.duplicate(true)})
	var snapshot: Dictionary = Snapshot.snapshot(candidate)
	var context := {"pack_specs": actual_specs, "content_snapshot": snapshot, "save_domain": "base" if actual_ids.is_empty() else "mod_" + str(snapshot.aggregate_sha256).substr(0, 28), "verified_play_eligible": actual_ids.is_empty(), "activation_order": activation_order}
	return {"ok": true, "code": &"OK", "context": {"registry": candidate, "enabled": actual_ids, "activation": context, "diagnostics": diagnostics}}


func _publish(candidate: Dictionary) -> void:
	_registry = candidate.context.registry
	_enabled.assign(candidate.context.enabled)
	_activation = candidate.context.activation.duplicate(true)
	for diagnostic: Dictionary in candidate.context.diagnostics:
		_diagnostics.append(diagnostic.duplicate(true))


func _persist(ids: Array[String], installations: Dictionary) -> Dictionary:
	var fingerprints: Dictionary = {}
	for id: String in installations:
		fingerprints[id] = str(installations[id].fingerprint_sha256)
	var selection := {"schema_version": 1, "installed": fingerprints, "enabled_pack_ids": ids.duplicate()}
	var result = _save.save_profile("selection", "manager", {"expansion_content_selection": selection})
	if result.ok:
		_selected_fingerprints = fingerprints.duplicate(true)
	return _success() if result.ok else _failure(result.code, result.metadata)


func _compatible_intent() -> Array[String]:
	var compatible: Array[String] = []
	for id: String in _intent:
		if _installed.has(id) and str(_selected_fingerprints.get(id, "")) == str(_installed[id].fingerprint_sha256):
			compatible.append(id)
		else:
			_diagnostics.append({"code": "SELECTED_INSTALLATION_CHANGED", "pack_id": id})
	return compatible


func _refresh_installed() -> void:
	var scanned: Dictionary = _installer.scan()
	_installed = scanned.context.get("installations", {}).duplicate(true) if scanned.ok else {}
	for diagnostic: Dictionary in scanned.context.get("diagnostics", []):
		_diagnostics.append(diagnostic.duplicate(true))
	if not scanned.ok:
		_diagnostics.append({"code": "INSTALLATION_SCAN_FAILED", "reason": str(scanned.code)})


func _refresh_entitlements() -> void:
	_entitlements = {"status": "OFFLINE_UNAVAILABLE", "owned_tags": [], "entries": [], "supports_purchase": false}
	if not _provider.is_valid():
		return
	var response: Variant = _provider.call()
	if not response is Dictionary or response.size() != 4 or response.get("status") not in ["LOCAL_FIXTURE", "VERIFIED_PLATFORM"] or not response.get("owned_tags") is Array or not response.get("entries") is Array or typeof(response.get("supports_purchase")) != TYPE_BOOL or response.supports_purchase:
		return
	var rows: Array = []
	for value: Variant in response.entries:
		if not value is Dictionary:
			return
		var row: Dictionary = value.duplicate(true)
		row.erase("owned")
		rows.append(row)
	var validator = OfflineProvider.new()
	if not validator.configure(rows, response.owned_tags).ok:
		return
	_entitlements = validator.snapshot()
	_entitlements.status = response.status


func _mutation_ready() -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _busy:
		return _failure(&"BUSY")
	return _check_run_lock()


func _check_run_lock() -> Dictionary:
	if not _run_lock.is_valid():
		return _failure(&"INVALID_RUN_LOCK")
	var locked: Variant = _run_lock.call()
	if typeof(locked) != TYPE_BOOL:
		return _failure(&"INVALID_RUN_LOCK")
	return _failure(&"RUN_ACTIVE") if locked else _success()


func _validated_ids(values: Array) -> Dictionary:
	var ids: Array[String] = []
	for value: Variant in values:
		if not Descriptor._matches(Descriptor.ID_PATTERN, value) or ids.has(str(value)):
			return _failure(&"INVALID_ARGUMENT", {"field": "pack_ids"})
		ids.append(str(value))
	ids.sort()
	return _success({"ids": ids})


func _selection_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != SELECTION_FIELDS.size() or not value.has("schema_version") or typeof(value.schema_version) not in [TYPE_INT, TYPE_FLOAT] or value.schema_version != 1 or not value.get("installed") is Dictionary or not value.get("enabled_pack_ids") is Array:
		return false
	for field: String in SELECTION_FIELDS:
		if not value.has(field):
			return false
	for id: Variant in value.installed:
		if not Descriptor._matches(Descriptor.ID_PATTERN, id) or not Descriptor._matches(Descriptor.DIGEST_PATTERN, value.installed[id]):
			return false
	var validated := _validated_ids(value.enabled_pack_ids)
	return validated.ok and validated.context.ids == value.enabled_pack_ids


func _management_snapshot() -> Dictionary:
	var packs := [{"pack_id": "expansion_management", "pack_version": "1.0.0", "schema_version": 1, "fingerprint_sha256": Descriptor.canonical_digest({"selection_schema": 1, "data_only": true})}]
	return {"packs": packs, "aggregate_sha256": Envelope.content_snapshot_digest(packs)}


func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
