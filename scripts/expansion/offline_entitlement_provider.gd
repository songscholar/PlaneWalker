class_name OfflineEntitlementProvider
extends RefCounted

const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const ROW_FIELDS := ["pack_id", "entitlement_tag", "name_key", "description_key", "local_source_path"]
var _entries: Array[Dictionary] = []
var _owned_tags: Array[String] = []


func configure(entries: Array, owned_tags: Array) -> Dictionary:
	var tags: Array[String] = []
	for value: Variant in owned_tags:
		if not Descriptor._matches("^[a-z0-9][a-z0-9_.-]{0,63}$", value) or tags.has(str(value)):
			return _failure("owned_tags")
		tags.append(str(value))
	tags.sort()
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	for value: Variant in entries:
		if not value is Dictionary or value.size() != ROW_FIELDS.size():
			return _failure("entries")
		for field: String in ROW_FIELDS:
			if not value.has(field) or typeof(value[field]) != TYPE_STRING:
				return _failure(field)
		if not Descriptor._matches(Descriptor.ID_PATTERN, value.pack_id) or seen.has(value.pack_id) or not Descriptor._matches("^[a-z0-9][a-z0-9_.-]{0,63}$", value.entitlement_tag):
			return _failure("entry_identity")
		for field: String in ["name_key", "description_key"]:
			if not Descriptor._matches("^[A-Z][A-Z0-9_]{1,127}$", value[field]):
				return _failure(field)
		seen[value.pack_id] = true
		rows.append(value.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pack_id < b.pack_id)
	_entries = rows
	_owned_tags = tags
	return {"ok": true, "code": &"OK", "context": {}}


func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = _entries.duplicate(true)
	for row: Dictionary in rows:
		row["owned"] = _owned_tags.has(str(row.entitlement_tag))
	return {"status": "LOCAL_FIXTURE", "owned_tags": _owned_tags.duplicate(), "entries": rows, "supports_purchase": false}


func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"INVALID_ENTITLEMENT_FIXTURE", "context": {"field": field}}
