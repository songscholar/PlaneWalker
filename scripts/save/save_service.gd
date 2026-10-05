class_name SaveService
extends RefCounted

const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const SaveFileOpsScript := preload("res://scripts/save/save_file_ops.gd")
const SaveMigrationRegistryScript := preload("res://scripts/save/save_migration_registry.gd")
const SavePathPolicyScript := preload("res://scripts/save/save_path_policy.gd")
const SaveResultScript := preload("res://scripts/save/save_result.gd")
const MetaProfileScript := preload("res://scripts/progression/meta_profile_state.gd")

const PRIMARY_FILE := "primary.json"
const PENDING_FILE := "pending.tmp"
const BACKUP_ONE_FILE := "backup_1.json"
const BACKUP_TWO_FILE := "backup_2.json"
const QUARANTINE_DIRECTORY := "quarantine"

const FAULT_POINTS: Array[StringName] = [
	&"after_pending_write",
	&"after_pending_verify",
	&"after_backup_2",
	&"after_backup_1",
	&"before_primary_promote",
	&"after_primary_promote",
]

var _configured: bool = false
var _root_path: String = ""
var _game_version: String = ""
var _content_snapshot: Dictionary = {}
var _clock: Callable
var _fault_injector: Callable
var _write_active: bool = false
var _file_ops = SaveFileOpsScript.new()
var _meta_catalog: RefCounted


func configure(
	root_path: String,
	game_version: String,
	content_snapshot: Dictionary,
	clock: Callable = Callable(),
	fault_injector: Callable = Callable()
):
	if _write_active:
		return _busy("configure")
	if root_path.strip_edges().is_empty():
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {"field": "root_path", "reason": "empty"})
	if game_version.strip_edges().is_empty():
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {"field": "game_version", "reason": "empty"})
	var snapshot_validation = SaveEnvelopeScript.create_profile(
		"slot_1",
		"base",
		0,
		game_version,
		"2000-01-01T00:00:00Z",
		"2000-01-01T00:00:00Z",
		content_snapshot,
		{}
	)
	if not snapshot_validation.ok:
		return snapshot_validation

	_root_path = ProjectSettings.globalize_path(root_path)
	_game_version = game_version
	_content_snapshot = (snapshot_validation.payload.get("content_snapshot", {}) as Dictionary).duplicate(true)
	_clock = clock if clock.is_valid() else Callable(self, "_system_utc_now")
	_fault_injector = fault_injector
	_meta_catalog = null
	_configured = true
	return SaveResultScript.success({}, {
		"root_path": _root_path,
		"game_version": _game_version,
	})


func set_fault_injector(fault_injector: Callable) -> void:
	_fault_injector = fault_injector


func configured_content_snapshot() -> Dictionary:
	return _content_snapshot.duplicate(true) if _configured else {}


func enable_meta_profile(catalog: RefCounted):
	var validator = MetaProfileScript.new()
	if not _configured or _write_active or not validator.configure(catalog):
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {"field": "meta_catalog"})
	_meta_catalog = catalog
	return SaveResultScript.success()


func save_profile(profile_id: String, save_domain: String, payload: Dictionary):
	var readiness = _validate_profile_request(profile_id, save_domain)
	if not readiness.ok:
		return readiness
	if _write_active:
		return _busy("save_profile")
	_write_active = true
	var result = _save_profile_internal(profile_id, save_domain, payload)
	_write_active = false
	return result


func save_profile_compare_exchange(profile_id: String, save_domain: String, payload: Dictionary, expected_primary: Dictionary):
	var readiness = _validate_profile_request(profile_id, save_domain)
	if not readiness.ok:
		return readiness
	if _write_active:
		return _busy("save_profile_compare_exchange")
	_write_active = true
	var result = _save_profile_internal(profile_id, save_domain, payload, expected_primary)
	_write_active = false
	return result


func load_profile(profile_id: String, save_domain: String = "base"):
	var readiness = _validate_profile_request(profile_id, save_domain)
	if not readiness.ok:
		return readiness
	return _load_scope(_profile_directory(profile_id, save_domain), &"profile", profile_id, save_domain)


func inspect_profile(profile_id: String, save_domain: String = "base"):
	var readiness = _validate_profile_request(profile_id, save_domain)
	if not readiness.ok:
		return readiness
	return _inspect_primary(_profile_directory(profile_id, save_domain), &"profile", profile_id, save_domain)


func rebind_profile_content(
	profile_id: String,
	save_domain: String,
	prior_snapshot: Dictionary,
	target_snapshot: Dictionary,
	expected_primary: Dictionary
):
	var readiness = _validate_profile_request(profile_id, save_domain)
	if not readiness.ok:
		return readiness
	if _write_active:
		return _busy("rebind_profile_content")
	if not _same_json(prior_snapshot, _content_snapshot):
		return SaveResultScript.failure(&"CONTENT_MISMATCH", {"reason": "configured_prior_snapshot"})
	var validated = SaveEnvelopeScript.create_profile(
		profile_id, save_domain, 0, _game_version,
		"2000-01-01T00:00:00Z", "2000-01-01T00:00:00Z", target_snapshot, {}
	)
	if not validated.ok:
		return validated
	_write_active = true
	var result = _rebind_profile_content_internal(
		profile_id, save_domain, validated.payload.content_snapshot.duplicate(true),
		expected_primary.duplicate(true)
	)
	_write_active = false
	return result


func _rebind_profile_content_internal(
	profile_id: String, save_domain: String, target_snapshot: Dictionary,
	expected_primary: Dictionary
):
	var directory := _profile_directory(profile_id, save_domain)
	var actual = _inspect_primary(directory, &"profile", profile_id, save_domain)
	if not actual.ok:
		if actual.code != &"NOT_FOUND" or not expected_primary.is_empty():
			return actual if actual.code != &"NOT_FOUND" else SaveResultScript.failure(
				&"INVALID_ARGUMENT", {"reason": "expected_primary_missing"}
			)
		for filename: String in [PENDING_FILE, BACKUP_ONE_FILE, BACKUP_TWO_FILE]:
			if FileAccess.file_exists(directory.path_join(filename)):
				return SaveResultScript.failure(&"INVALID_ARGUMENT", {"reason": "source_recovery_files_present"})
		_content_snapshot = target_snapshot.duplicate(true)
		return SaveResultScript.success({}, {"committed": false, "source_kind": "absent", "reconciled_committed_write": false})
	if expected_primary.is_empty() or not _same_json(actual.payload, expected_primary):
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {"reason": "expected_primary_stale"})
	if _content_snapshot_matches(target_snapshot):
		return SaveResultScript.success(actual.payload.payload, {"committed": false, "source_kind": "primary", "sequence": int(actual.payload.sequence), "reconciled_committed_write": false})
	var created = SaveEnvelopeScript.create_profile(
		profile_id, save_domain, int(actual.payload.sequence) + 1, _game_version,
		str(actual.payload.created_at_utc), _now(), target_snapshot,
		actual.payload.payload, _meta_catalog
	)
	if not created.ok:
		return created
	if not _same_json(created.payload.payload, actual.payload.payload):
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {"reason": "content_rebinding_changes_payload"})
	var committed = _commit_envelope(
		directory, created.payload, &"profile", profile_id, save_domain, true,
		target_snapshot, actual.payload
	)
	var reconciled := false
	if not committed.ok:
		# A target-compatible pending or backup file cannot prove migration committed.
		var primary = _read_and_validate(
			directory.path_join(PRIMARY_FILE), &"profile", profile_id, save_domain,
			target_snapshot
		)
		if not primary.ok or not _same_json(primary.payload, created.payload):
			return committed
		reconciled = true
	_content_snapshot = target_snapshot.duplicate(true)
	return SaveResultScript.success(created.payload.payload, {
		"committed": true, "source_kind": "primary", "sequence": int(created.payload.sequence),
		"digest": _document_digest(created.payload), "reconciled_committed_write": reconciled,
	})


func reset_profile(profile_id: String, save_domain: String = "base"):
	var readiness = _validate_profile_request(profile_id, save_domain)
	if not readiness.ok:
		return readiness
	if _write_active:
		return _busy("reset_profile")
	_write_active = true
	var result = _file_ops.remove_tree(_profile_directory(profile_id, save_domain))
	_write_active = false
	return result


func save_settings(payload: Dictionary):
	var readiness = _require_configured()
	if not readiness.ok:
		return readiness
	if _write_active:
		return _busy("save_settings")
	_write_active = true
	var result = _save_settings_internal(payload)
	_write_active = false
	return result


func load_settings():
	var readiness = _require_configured()
	if not readiness.ok:
		return readiness
	return _load_scope(_settings_directory(), &"settings", "", "")


func _save_profile_internal(profile_id: String, save_domain: String, payload: Dictionary, expected_primary: Variant = null):
	var directory_path := _profile_directory(profile_id, save_domain)
	var existing = _inspect_primary(directory_path, &"profile", profile_id, save_domain)
	if expected_primary != null and not _primary_matches(existing, expected_primary):
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {"reason": "expected_primary_stale"})
	var sequence := 0
	var created_at := ""
	if existing.ok:
		var existing_document: Dictionary = existing.payload
		sequence = int(existing_document["sequence"]) + 1
		created_at = str(existing_document["created_at_utc"])
	elif existing.code != &"NOT_FOUND":
		return existing

	var saved_at := _now()
	if created_at.is_empty():
		created_at = saved_at
	var created = SaveEnvelopeScript.create_profile(
		profile_id,
		save_domain,
		sequence,
		_game_version,
		created_at,
		saved_at,
		_content_snapshot,
		payload,
		_meta_catalog
	)
	if not created.ok:
		return created
	var transaction = _commit_envelope(
		directory_path,
		created.payload,
		&"profile",
		profile_id,
		save_domain,
		true,
		{},
		expected_primary
	)
	if not transaction.ok:
		return transaction
	return SaveResultScript.success(
		payload,
		{
		"sequence": sequence,
		"digest": created.payload.get("integrity", {}).get("digest", ""),
		"path": directory_path.path_join(PRIMARY_FILE),
		"source_kind": "primary",
		}
	)


func _save_settings_internal(payload: Dictionary):
	var directory_path := _settings_directory()
	var existing = _inspect_primary(directory_path, &"settings", "", "")
	var sequence := 0
	var created_at := ""
	if existing.ok:
		var existing_document: Dictionary = existing.payload
		sequence = int(existing_document["sequence"]) + 1
		created_at = str(existing_document["created_at_utc"])
	elif existing.code != &"NOT_FOUND":
		return existing

	var saved_at := _now()
	if created_at.is_empty():
		created_at = saved_at
	var created = SaveEnvelopeScript.create_settings(
		sequence,
		_game_version,
		created_at,
		saved_at,
		payload
	)
	if not created.ok:
		return created
	var transaction = _commit_envelope(directory_path, created.payload, &"settings", "", "", true)
	if not transaction.ok:
		return transaction
	return SaveResultScript.success(payload, {
		"sequence": sequence,
		"digest": created.payload.get("integrity", {}).get("digest", ""),
		"path": directory_path.path_join(PRIMARY_FILE),
		"source_kind": "primary",
	})


func _commit_envelope(
	directory_path: String,
	document: Dictionary,
	document_kind: StringName,
	profile_id: String,
	save_domain: String,
	rotate_backups: bool,
	target_content_snapshot: Dictionary = {},
	expected_primary: Variant = null
):
	var directory_result = _file_ops.ensure_directory(directory_path)
	if not directory_result.ok:
		return directory_result
	var pending_path := directory_path.path_join(PENDING_FILE)
	var primary_path := directory_path.path_join(PRIMARY_FILE)
	var serialized := SaveEnvelopeScript.canonical_json(document)
	if serialized.is_empty():
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {"field": "document", "reason": "canonical_json"})

	var pending_write = _file_ops.write_utf8(pending_path, serialized)
	if not pending_write.ok:
		return pending_write
	var fault_result = _inject_fault(&"after_pending_write")
	if not fault_result.ok:
		return fault_result

	var pending_validation = _read_and_validate(pending_path, document_kind, profile_id, save_domain, target_content_snapshot)
	if not pending_validation.ok:
		return pending_validation
	if _document_digest(pending_validation.payload) != _document_digest(document):
		return SaveResultScript.failure(&"CORRUPT", {
			"path": pending_path,
			"reason": "pending_digest_mismatch",
		})
	fault_result = _inject_fault(&"after_pending_verify")
	if not fault_result.ok:
		return fault_result

	if rotate_backups:
		var backup_one_path := directory_path.path_join(BACKUP_ONE_FILE)
		var backup_two_path := directory_path.path_join(BACKUP_TWO_FILE)
		var rotate_two = _rotate_verified_candidate(
			backup_one_path,
			backup_two_path,
			document_kind,
			profile_id,
			save_domain,
			&"backup_1"
		)
		if not rotate_two.ok:
			return rotate_two
		fault_result = _inject_fault(&"after_backup_2")
		if not fault_result.ok:
			return fault_result

		var rotate_one = _rotate_verified_candidate(
			primary_path,
			backup_one_path,
			document_kind,
			profile_id,
			save_domain,
			&"primary"
		)
		if not rotate_one.ok:
			return rotate_one
		fault_result = _inject_fault(&"after_backup_1")
		if not fault_result.ok:
			return fault_result

	fault_result = _inject_fault(&"before_primary_promote")
	if not fault_result.ok:
		return fault_result
	if expected_primary != null:
		var preimage = _inspect_primary(directory_path, document_kind, profile_id, save_domain)
		if not _primary_matches(preimage, expected_primary):
			return SaveResultScript.failure(&"INVALID_ARGUMENT", {"reason": "expected_primary_stale"})
	var promote = _file_ops.rename_file(pending_path, primary_path)
	if not promote.ok:
		return promote
	fault_result = _inject_fault(&"after_primary_promote")
	if not fault_result.ok:
		return fault_result

	var primary_validation = _read_and_validate(primary_path, document_kind, profile_id, save_domain, target_content_snapshot)
	if not primary_validation.ok:
		return primary_validation
	if _document_digest(primary_validation.payload) != _document_digest(document):
		return SaveResultScript.failure(&"CORRUPT", {
			"path": primary_path,
			"reason": "primary_digest_mismatch",
		})
	return SaveResultScript.success(primary_validation.payload, {
		"path": primary_path,
		"digest": _document_digest(document),
	})


func _primary_matches(actual: RefCounted, expected: Dictionary) -> bool:
	return actual.code == &"NOT_FOUND" if expected.is_empty() else actual.ok and _same_json(actual.payload, expected)


func _rotate_verified_candidate(
	source_path: String,
	destination_path: String,
	document_kind: StringName,
	profile_id: String,
	save_domain: String,
	source_kind: StringName
):
	if not FileAccess.file_exists(source_path):
		return SaveResultScript.success({}, {"rotated": false, "source_kind": source_kind})
	var source_validation = _read_and_validate(source_path, document_kind, profile_id, save_domain)
	if not source_validation.ok:
		if source_validation.code != &"CORRUPT":
			return source_validation
		var quarantined = _quarantine_candidate(source_path, source_path.get_base_dir(), source_kind, source_validation)
		if not quarantined.ok:
			return quarantined
		return SaveResultScript.success({}, {
			"rotated": false,
			"source_kind": source_kind,
			"quarantined": true,
		})

	var staging_path := "%s.rotate.tmp" % destination_path
	var remove_staging = _file_ops.remove_file(staging_path)
	if not remove_staging.ok:
		return remove_staging
	var copied = _file_ops.copy_file(source_path, staging_path)
	if not copied.ok:
		return copied
	var staging_validation = _read_and_validate(staging_path, document_kind, profile_id, save_domain)
	if not staging_validation.ok:
		_file_ops.remove_file(staging_path)
		return staging_validation
	if _document_digest(staging_validation.payload) != _document_digest(source_validation.payload):
		_file_ops.remove_file(staging_path)
		return SaveResultScript.failure(&"CORRUPT", {
			"path": staging_path,
			"reason": "rotation_digest_mismatch",
		})
	if FileAccess.file_exists(destination_path):
		var existing_destination = _read_and_validate(
			destination_path,
			document_kind,
			profile_id,
			save_domain
		)
		if not existing_destination.ok:
			if existing_destination.code != &"CORRUPT":
				_file_ops.remove_file(staging_path)
				return existing_destination
			var destination_kind := &"backup_2" if destination_path.ends_with(BACKUP_TWO_FILE) else &"backup_1"
			var quarantined_destination = _quarantine_candidate(
				destination_path,
				destination_path.get_base_dir(),
				destination_kind,
				existing_destination
			)
			if not quarantined_destination.ok:
				_file_ops.remove_file(staging_path)
				return quarantined_destination
	var remove_destination = _file_ops.remove_file(destination_path)
	if not remove_destination.ok:
		_file_ops.remove_file(staging_path)
		return remove_destination
	var promoted = _file_ops.rename_file(staging_path, destination_path)
	if not promoted.ok:
		return promoted
	var destination_validation = _read_and_validate(destination_path, document_kind, profile_id, save_domain)
	if not destination_validation.ok:
		return destination_validation
	if _document_digest(destination_validation.payload) != _document_digest(source_validation.payload):
		return SaveResultScript.failure(&"CORRUPT", {
			"path": destination_path,
			"reason": "rotated_destination_digest_mismatch",
		})
	return SaveResultScript.success({}, {
		"rotated": true,
		"source_path": source_path,
		"path": destination_path,
	})


func _load_scope(directory_path: String, document_kind: StringName, profile_id: String, save_domain: String):
	var primary = _inspect_primary(directory_path, document_kind, profile_id, save_domain)
	if primary.ok:
		var migrated_from := int(primary.metadata.get(
			"migrated_from",
			SaveEnvelopeScript.SCHEMA_VERSION
		))
		var migrated_to := int(primary.metadata.get("migrated_to", migrated_from))
		if migrated_from < migrated_to:
			if _write_active:
				return _busy("migrate_%s" % str(document_kind))
			_write_active = true
			var rewrite = _commit_envelope(
				directory_path,
				primary.payload,
				document_kind,
				profile_id,
				save_domain,
				migrated_to == SaveEnvelopeScript.META_PROFILE_SCHEMA_VERSION
			)
			_write_active = false
			if not rewrite.ok:
				return rewrite
		return _payload_result(
			primary.payload,
			&"OK",
			&"primary",
			primary.diagnostics,
			primary.metadata
		)
	if primary.code != &"CORRUPT":
		return primary
	if _write_active:
		return _busy("recover_%s" % str(document_kind))
	_write_active = true
	var recovered = _recover_corrupt_scope(directory_path, document_kind, profile_id, save_domain, primary)
	_write_active = false
	return recovered


func _recover_corrupt_scope(
	directory_path: String,
	document_kind: StringName,
	profile_id: String,
	save_domain: String,
	primary_failure
):
	var diagnostics: Array[Dictionary] = []
	diagnostics.append(_diagnostic_for(&"primary", primary_failure))
	var primary_path := directory_path.path_join(PRIMARY_FILE)
	var quarantined_primary = _quarantine_candidate(primary_path, directory_path, &"primary", primary_failure)
	if not quarantined_primary.ok:
		return quarantined_primary

	var candidates: Array[Dictionary] = [
		{"source_kind": &"pending", "path": directory_path.path_join(PENDING_FILE)},
		{"source_kind": &"backup_1", "path": directory_path.path_join(BACKUP_ONE_FILE)},
		{"source_kind": &"backup_2", "path": directory_path.path_join(BACKUP_TWO_FILE)},
	]
	for candidate: Dictionary in candidates:
		var candidate_path := str(candidate["path"])
		var source_kind: StringName = candidate["source_kind"]
		if not FileAccess.file_exists(candidate_path):
			continue
		var validation = _read_and_validate(candidate_path, document_kind, profile_id, save_domain)
		if validation.ok:
			var repair = _commit_envelope(
				directory_path,
				validation.payload,
				document_kind,
				profile_id,
				save_domain,
				false
			)
			if not repair.ok:
				return repair
			var metadata := {
				"source_kind": source_kind,
				"player_notice_required": true,
				"sequence": int(validation.payload.get("sequence", 0)),
				"path": directory_path.path_join(PRIMARY_FILE),
				"migrated_from": int(validation.metadata.get(
					"migrated_from",
					SaveEnvelopeScript.SCHEMA_VERSION
				)),
				"migrated_to": int(validation.metadata.get(
					"migrated_to",
					SaveEnvelopeScript.SCHEMA_VERSION
				)),
			}
			return SaveResultScript.success(
				validation.payload.get("payload", {}),
				metadata,
				diagnostics,
				&"RECOVERED"
			)

		diagnostics.append(_diagnostic_for(source_kind, validation))
		if validation.code == &"CORRUPT":
			var quarantined_candidate = _quarantine_candidate(candidate_path, directory_path, source_kind, validation)
			if not quarantined_candidate.ok:
				return quarantined_candidate

	return SaveResultScript.failure(&"CORRUPT", {
		"path": primary_path,
		"reason": "no_usable_recovery_candidate",
		"player_notice_required": true,
	}, diagnostics)


func _inspect_primary(directory_path: String, document_kind: StringName, profile_id: String, save_domain: String):
	return _read_and_validate(directory_path.path_join(PRIMARY_FILE), document_kind, profile_id, save_domain)


func _read_and_validate(path: String, document_kind: StringName, profile_id: String, save_domain: String, expected_content_snapshot: Dictionary = {}):
	var read_result = _file_ops.read_utf8(path)
	if not read_result.ok:
		return read_result
	var parser := JSON.new()
	var parse_error := parser.parse(str(read_result.payload))
	if parse_error != OK or not parser.data is Dictionary:
		return SaveResultScript.failure(&"CORRUPT", {
			"path": path,
			"field": "document",
			"reason": "json_parse",
			"parse_error": parse_error,
			"parse_message": parser.get_error_message(),
			"parse_line": parser.get_error_line(),
		})
	var document: Dictionary = parser.data
	var boundary = SaveEnvelopeScript.validate_document_boundary(
		document, document_kind, profile_id, save_domain, _target_version(document_kind)
	)
	if not boundary.ok:
		boundary.metadata["path"] = path
		return boundary
	var required_snapshot := _content_snapshot if expected_content_snapshot.is_empty() else expected_content_snapshot
	var content_matches := _content_snapshot_matches(boundary.payload.get("content_snapshot", {})) if expected_content_snapshot.is_empty() else _same_json(boundary.payload.get("content_snapshot", {}), required_snapshot)
	if document_kind == &"profile" and not content_matches:
		var actual_snapshot: Dictionary = boundary.payload.get("content_snapshot", {})
		return SaveResultScript.failure(&"CONTENT_MISMATCH", {
			"path": path,
			"expected_aggregate": required_snapshot.get("aggregate_sha256", ""),
			"actual_aggregate": actual_snapshot.get("aggregate_sha256", ""),
		})
	var validation = SaveEnvelopeScript.validate(document, document_kind, profile_id, save_domain, _meta_catalog)
	if not validation.ok:
		validation.metadata["path"] = path
		return validation
	var migrated_from := int(document.get("schema_version", SaveEnvelopeScript.SCHEMA_VERSION))
	if migrated_from < _target_version(document_kind):
		var migration = SaveMigrationRegistryScript.new().migrate(
			document if _target_version(document_kind) >= 4 else validation.payload,
			_target_version(document_kind),
			{"profile_id": profile_id, "save_domain": save_domain, "meta_catalog": _meta_catalog}
		)
		if not migration.ok:
			migration.metadata["path"] = path
			return migration
		var resealed = SaveEnvelopeScript.reseal_current(migration.payload, _meta_catalog)
		if not resealed.ok:
			resealed.metadata["path"] = path
			return resealed
		validation = SaveEnvelopeScript.validate(
			resealed.payload,
			document_kind,
			profile_id,
			save_domain,
			_meta_catalog
		)
		if not validation.ok:
			validation.metadata["path"] = path
			return validation
	return SaveResultScript.success(validation.payload, {
		"path": path,
		"sequence": int(validation.payload.get("sequence", 0)),
		"digest": _document_digest(validation.payload),
		"migrated_from": migrated_from,
		"migrated_to": int(validation.payload.get("schema_version", migrated_from)),
	})


func _target_version(document_kind: StringName) -> int:
	return SaveEnvelopeScript.META_PROFILE_SCHEMA_VERSION if document_kind == &"profile" and _meta_catalog != null else SaveEnvelopeScript.SCHEMA_VERSION


func _quarantine_candidate(
	path: String,
	directory_path: String,
	source_kind: StringName,
	failure
):
	var reason := "%s-%s" % [
		str(failure.metadata.get("field", "document")),
		str(failure.metadata.get("reason", failure.code)),
	]
	return _file_ops.quarantine(
		path,
		directory_path.path_join(QUARANTINE_DIRECTORY),
		source_kind,
		reason
	)


func _payload_result(
	document: Dictionary,
	code: StringName,
	source_kind: StringName,
	diagnostics: Array[Dictionary] = [],
	source_metadata: Dictionary = {}
):
	var metadata := source_metadata.duplicate(true)
	metadata["source_kind"] = source_kind
	metadata["sequence"] = int(document.get("sequence", 0))
	metadata["digest"] = _document_digest(document)
	return SaveResultScript.success(
		document.get("payload", {}),
		metadata,
		diagnostics,
		code
	)


func _diagnostic_for(source_kind: StringName, failure) -> Dictionary:
	return {
		"source_kind": str(source_kind),
		"code": str(failure.code),
		"metadata": failure.metadata.duplicate(true),
	}


func _inject_fault(point: StringName):
	if not FAULT_POINTS.has(point):
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {
			"field": "fault_point",
			"value": str(point),
		})
	if not _fault_injector.is_valid():
		return SaveResultScript.success()
	var response: Variant = _fault_injector.call(point)
	var should_fail := false
	if typeof(response) == TYPE_BOOL:
		should_fail = bool(response)
	elif typeof(response) == TYPE_INT:
		should_fail = int(response) != 0
	elif typeof(response) == TYPE_STRING:
		should_fail = not str(response).is_empty()
	if not should_fail:
		return SaveResultScript.success()
	return SaveResultScript.failure(&"IO_ERROR", {
		"operation": "fault_injection",
		"fault_point": str(point),
	})


func _validate_profile_request(profile_id: String, save_domain: String):
	var readiness = _require_configured()
	if not readiness.ok:
		return readiness
	var profile_validation = SavePathPolicyScript.validate_id(profile_id, &"profile_id")
	if not profile_validation.ok:
		return profile_validation
	return SavePathPolicyScript.validate_id(save_domain, &"save_domain")


func _require_configured():
	if not _configured:
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {
			"field": "service",
			"reason": "not_configured",
		})
	return SaveResultScript.success()


func _busy(operation: String):
	return SaveResultScript.failure(&"BUSY", {"operation": operation})


func _profile_directory(profile_id: String, save_domain: String) -> String:
	return _root_path.path_join("profiles").path_join(profile_id).path_join(save_domain)


func _settings_directory() -> String:
	return _root_path.path_join("global").path_join("settings")


func _content_snapshot_matches(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	return SaveEnvelopeScript.canonical_json(value) == SaveEnvelopeScript.canonical_json(_content_snapshot)


func _same_json(left: Variant, right: Variant) -> bool:
	var left_json := SaveEnvelopeScript.canonical_json(left)
	var right_json := SaveEnvelopeScript.canonical_json(right)
	return not left_json.is_empty() and not right_json.is_empty() and JSON.parse_string(left_json) == JSON.parse_string(right_json)


func _document_digest(document: Dictionary) -> String:
	var integrity: Variant = document.get("integrity", {})
	if not integrity is Dictionary:
		return ""
	return str((integrity as Dictionary).get("digest", ""))


func _now() -> String:
	var value: Variant = _clock.call()
	return str(value)


func _system_utc_now() -> String:
	return "%sZ" % Time.get_datetime_string_from_system(true, false)
