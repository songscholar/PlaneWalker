class_name IrreversibleCharacterLedger
extends RefCounted

const SCHEMA_VERSION := 1
const MAX_ID_LENGTH := 64
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"run_id",
	"irreversible_hp_loss_total",
	"revision",
	"claims",
	"claim_root",
]
const CLAIM_FIELDS: Array[String] = [
	"amount",
	"reason",
	"source_generation",
	"source_token",
	"revision",
]

var _run_id: StringName = &""
var _irreversible_hp_loss_total: float = 0.0
var _revision: int = 0
var _claims: Dictionary = {}
var _frozen_transaction_snapshot_digest: String = ""


func configure_run(run_id: StringName) -> bool:
	var normalized := _normalized_run_id(run_id)
	if normalized == &"":
		return false
	if _run_id == &"":
		_install_empty_run(normalized)
		return true
	return _run_id == normalized


func reset_for_run(run_id: StringName) -> void:
	var normalized := _normalized_run_id(run_id)
	if normalized == &"" or normalized == _run_id:
		return
	_install_empty_run(normalized)


func record_hp_loss(
	amount: float,
	reason: StringName,
	source_token: int,
	source_generation: int,
	claim_run_id: StringName = &""
) -> Dictionary:
	if _run_id == &"":
		return _failure(&"RUN_NOT_CONFIGURED")
	var expected_run_id := _run_id if claim_run_id == &"" else _normalized_run_id(claim_run_id)
	if expected_run_id == &"" or expected_run_id != _run_id:
		return _failure(&"STALE_RUN")
	if not is_finite(amount) or amount <= 0.0:
		return _failure(&"INVALID_AMOUNT")
	var normalized_reason := _normalized_reason(reason)
	if normalized_reason == &"":
		return _failure(&"INVALID_REASON")
	if source_token <= 0:
		return _failure(&"INVALID_TOKEN")
	if source_generation <= 0:
		return _failure(&"INVALID_GENERATION")
	var claim_key := _claim_key(_run_id, normalized_reason, source_generation, source_token)
	if _claims.has(claim_key):
		return _failure(&"DUPLICATE_CLAIM")
	var next_total := _irreversible_hp_loss_total + amount
	if not is_finite(next_total):
		return _failure(&"INVALID_AMOUNT")
	var next_revision := _revision + 1
	_claims[claim_key] = {
		"amount": amount,
		"reason": normalized_reason,
		"source_generation": source_generation,
		"source_token": source_token,
		"revision": next_revision,
	}
	_irreversible_hp_loss_total = next_total
	_revision = next_revision
	return {
		"ok": true,
		"code": &"RECORDED",
		"claim_key": claim_key,
		"amount": amount,
		"irreversible_hp_loss_total": _irreversible_hp_loss_total,
		"revision": _revision,
	}


func hp_loss_state() -> Dictionary:
	return {
		"irreversible_hp_loss_total": _irreversible_hp_loss_total,
		"revision": _revision,
	}


func snapshot() -> Dictionary:
	return _snapshot_value()


func freeze_transaction_snapshot() -> Dictionary:
	var value := _snapshot_value()
	_frozen_transaction_snapshot_digest = _transaction_snapshot_digest(value)
	return value


func can_restore_replay_snapshot(value: Dictionary) -> bool:
	var validated := _validated_snapshot(value)
	if validated.is_empty():
		return false
	var restored_run_id := validated["run_id"] as StringName
	return _run_id == &"" or restored_run_id == _run_id


func restore_replay_snapshot(value: Dictionary) -> bool:
	if not can_restore_replay_snapshot(value):
		return false
	var validated := _validated_snapshot(value)
	var restored_run_id := validated["run_id"] as StringName
	_install_snapshot(validated)
	_frozen_transaction_snapshot_digest = ""
	return _run_id == restored_run_id and _snapshot_value() == validated


func restore_transaction_snapshot(value: Dictionary) -> bool:
	if _run_id == &"":
		return false
	var validated := _validated_snapshot(value)
	if validated.is_empty() or validated["run_id"] != _run_id:
		return false
	var digest := _transaction_snapshot_digest(validated)
	if _frozen_transaction_snapshot_digest.is_empty() or digest != _frozen_transaction_snapshot_digest:
		return false
	_install_snapshot(validated)
	_frozen_transaction_snapshot_digest = ""
	return true


func discard_transaction_snapshot(value: Dictionary) -> bool:
	if _run_id == &"":
		return false
	var validated := _validated_snapshot(value)
	if validated.is_empty() or validated["run_id"] != _run_id:
		return false
	var digest := _transaction_snapshot_digest(validated)
	if _frozen_transaction_snapshot_digest.is_empty() or digest != _frozen_transaction_snapshot_digest:
		return false
	_frozen_transaction_snapshot_digest = ""
	return true


func _install_empty_run(run_id: StringName) -> void:
	_run_id = run_id
	_irreversible_hp_loss_total = 0.0
	_revision = 0
	_claims.clear()
	_frozen_transaction_snapshot_digest = ""


func _install_snapshot(value: Dictionary) -> void:
	_run_id = value["run_id"] as StringName
	_irreversible_hp_loss_total = float(value["irreversible_hp_loss_total"])
	_revision = int(value["revision"])
	_claims = (value["claims"] as Dictionary).duplicate(true)


func _snapshot_value() -> Dictionary:
	var claims_copy := _claims.duplicate(true)
	return {
		"schema_version": SCHEMA_VERSION,
		"run_id": _run_id,
		"irreversible_hp_loss_total": _irreversible_hp_loss_total,
		"revision": _revision,
		"claims": claims_copy,
		"claim_root": _claim_root(_run_id, claims_copy),
	}


func _failure(code: StringName) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"irreversible_hp_loss_total": _irreversible_hp_loss_total,
		"revision": _revision,
	}


static func _validated_snapshot(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return {}
	if typeof(value["schema_version"]) != TYPE_INT or int(value["schema_version"]) != SCHEMA_VERSION:
		return {}
	var run_id := _normalized_run_id(value["run_id"])
	if run_id == &"":
		return {}
	if not _nonnegative_finite_number(value["irreversible_hp_loss_total"]):
		return {}
	if typeof(value["revision"]) != TYPE_INT or int(value["revision"]) < 0:
		return {}
	if not value["claims"] is Dictionary:
		return {}
	if not _is_sha256(value["claim_root"]):
		return {}

	var revision := int(value["revision"])
	var source_claims := value["claims"] as Dictionary
	if source_claims.size() != revision:
		return {}
	var claims: Dictionary = {}
	var claims_by_revision: Array[Dictionary] = []
	claims_by_revision.resize(revision)
	for claim_key_value: Variant in source_claims.keys():
		if typeof(claim_key_value) != TYPE_STRING and typeof(claim_key_value) != TYPE_STRING_NAME:
			return {}
		var claim_key := str(claim_key_value)
		var claim_value: Variant = source_claims[claim_key_value]
		if not claim_value is Dictionary:
			return {}
		var claim := claim_value as Dictionary
		if not _has_exact_fields(claim, CLAIM_FIELDS):
			return {}
		if not _positive_finite_number(claim["amount"]):
			return {}
		var reason := _normalized_reason(claim["reason"])
		if reason == &"":
			return {}
		if typeof(claim["source_token"]) != TYPE_INT or int(claim["source_token"]) <= 0:
			return {}
		if typeof(claim["source_generation"]) != TYPE_INT or int(claim["source_generation"]) <= 0:
			return {}
		if typeof(claim["revision"]) != TYPE_INT:
			return {}
		var claim_revision := int(claim["revision"])
		if claim_revision <= 0 or claim_revision > revision or not claims_by_revision[claim_revision - 1].is_empty():
			return {}
		var source_token := int(claim["source_token"])
		var source_generation := int(claim["source_generation"])
		if claim_key != _claim_key(run_id, reason, source_generation, source_token):
			return {}
		var normalized_claim := {
			"amount": float(claim["amount"]),
			"reason": reason,
			"source_generation": source_generation,
			"source_token": source_token,
			"revision": claim_revision,
		}
		claims[claim_key] = normalized_claim
		claims_by_revision[claim_revision - 1] = normalized_claim

	var calculated_total := 0.0
	for claim: Dictionary in claims_by_revision:
		calculated_total += float(claim["amount"])
		if not is_finite(calculated_total):
			return {}
	if calculated_total != float(value["irreversible_hp_loss_total"]):
		return {}
	var claim_root := str(value["claim_root"])
	if claim_root != _claim_root(run_id, claims):
		return {}
	return {
		"schema_version": SCHEMA_VERSION,
		"run_id": run_id,
		"irreversible_hp_loss_total": calculated_total,
		"revision": revision,
		"claims": claims,
		"claim_root": claim_root,
	}


static func _claim_root(run_id: StringName, claims: Dictionary) -> String:
	var keys: Array[String] = []
	for key: Variant in claims.keys():
		keys.append(str(key))
	keys.sort()
	var canonical_claims: Array[Variant] = []
	for key: String in keys:
		var claim := claims[key] as Dictionary
		canonical_claims.append([
			key,
			float(claim["amount"]),
			str(claim["reason"]),
			int(claim["source_generation"]),
			int(claim["source_token"]),
			int(claim["revision"]),
		])
	return JSON.stringify([SCHEMA_VERSION, str(run_id), canonical_claims], "", false).sha256_text()


static func _transaction_snapshot_digest(value: Dictionary) -> String:
	return JSON.stringify([
		int(value["schema_version"]),
		str(value["run_id"]),
		float(value["irreversible_hp_loss_total"]),
		int(value["revision"]),
		str(value["claim_root"]),
	], "", false).sha256_text()


static func _claim_key(
	run_id: StringName,
	reason: StringName,
	source_generation: int,
	source_token: int
) -> String:
	return "%s:%s:%d:%d" % [str(run_id), str(reason), source_generation, source_token]


static func _normalized_run_id(value: Variant) -> StringName:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return &""
	var normalized := str(value).strip_edges()
	if normalized.is_empty() or normalized.length() > MAX_ID_LENGTH or normalized.contains(":"):
		return &""
	return StringName(normalized)


static func _normalized_reason(value: Variant) -> StringName:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return &""
	var normalized := str(value).strip_edges()
	if normalized.is_empty() or normalized.length() > MAX_ID_LENGTH:
		return &""
	return StringName(normalized)


static func _has_exact_fields(value: Dictionary, expected_fields: Array[String]) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field: String in expected_fields:
		if not value.has(field):
			return false
	for key: Variant in value.keys():
		if (typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME) or not expected_fields.has(str(key)):
			return false
	return true


static func _positive_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number > 0.0


static func _nonnegative_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0


static func _is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return false
	var text := str(value)
	if text.length() != 64:
		return false
	for index: int in range(text.length()):
		if "0123456789abcdef".find(text.substr(index, 1)) < 0:
			return false
	return true
