class_name ContentSnapshotProvider
extends RefCounted

const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const PACK_ID_PATTERN := "^[a-z0-9][a-z0-9_-]{0,63}$"
const SHA256_PATTERN := "^[a-f0-9]{64}$"
const SNAPSHOT_FIELDS: Array[String] = [
	"pack_id",
	"pack_version",
	"schema_version",
	"fingerprint_sha256",
]


static func snapshot(registry: Variant) -> Dictionary:
	if registry == null or not registry is Object or not registry.has_method("active_packs"):
		return {}
	var source_value: Variant = registry.call("active_packs")
	if not source_value is Array or (source_value as Array).is_empty():
		return {}
	var pack_ids: Dictionary = {}
	var packs: Array[Dictionary] = []
	for source_pack_value: Variant in source_value:
		if not source_pack_value is Dictionary:
			return {}
		var source_pack: Dictionary = source_pack_value
		var pack := {
			"pack_id": source_pack.get("pack_id"),
			"pack_version": source_pack.get("pack_version"),
			"schema_version": source_pack.get("schema_version"),
			"fingerprint_sha256": source_pack.get("fingerprint_sha256"),
		}
		if not _pack_is_valid(pack):
			return {}
		var pack_id := str(pack["pack_id"])
		if pack_ids.has(pack_id):
			return {}
		pack_ids[pack_id] = true
		packs.append(pack)
	_sort_packs(packs)
	var aggregate := SaveEnvelopeScript.content_snapshot_digest(packs)
	if aggregate.is_empty():
		return {}
	return {
		"aggregate_sha256": aggregate,
		"packs": packs.duplicate(true),
	}


static func _pack_is_valid(pack: Dictionary) -> bool:
	if pack.size() != SNAPSHOT_FIELDS.size():
		return false
	for field: String in SNAPSHOT_FIELDS:
		if not pack.has(field):
			return false
	if not _matches(PACK_ID_PATTERN, pack["pack_id"]):
		return false
	if typeof(pack["pack_version"]) != TYPE_STRING or str(pack["pack_version"]).is_empty():
		return false
	if not _is_positive_integer(pack["schema_version"]):
		return false
	return _matches(SHA256_PATTERN, pack["fingerprint_sha256"])


static func _sort_packs(packs: Array[Dictionary]) -> void:
	packs.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return _sort_key(left) < _sort_key(right)
	)


static func _sort_key(pack: Dictionary) -> String:
	return "%s\u001f%s\u001f%010d\u001f%s" % [
		str(pack["pack_id"]),
		str(pack["pack_version"]),
		int(pack["schema_version"]),
		str(pack["fingerprint_sha256"]),
	]


static func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	return regex.search(str(value)) != null


static func _is_positive_integer(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floorf(numeric) and numeric >= 1.0
