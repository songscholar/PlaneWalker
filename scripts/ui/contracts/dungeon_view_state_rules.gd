class_name DungeonViewStateRules
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
static var _regex_cache: Dictionary = {}


static func header(value: Variant, fields: Array) -> bool:
	return value is Dictionary and exact(value, fields) and value.get("schema_version") == 1 and integer(value.get("schema_version")) and integer(value.get("revision")) and int(value["revision"]) >= 0 and identifier(value.get("run_id"))


static func exact(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


static func identifier(value: Variant) -> bool:
	return _matches(value, "^[a-zA-Z0-9][a-zA-Z0-9_:.\\-]{0,191}$")


static func key(value: Variant, empty_allowed: bool = false) -> bool:
	return (empty_allowed and typeof(value) == TYPE_STRING and value.is_empty()) or _matches(value, "^[A-Z][A-Z0-9_]{1,127}$")


static func availability(value: Dictionary, field: String = "available") -> bool:
	return typeof(value.get(field)) == TYPE_BOOL and key(value.get("disabled_reason_key"), bool(value.get(field, false))) and (not bool(value.get(field, false)) or str(value.get("disabled_reason_key", "")).is_empty())


static func accept(value: Dictionary):
	return CommandResultScript.success(int(value["revision"]), {"view_state": value.duplicate(true)})


static func reject(value: Variant, field: String):
	var revision := 0
	if value is Dictionary and integer(value.get("revision")):
		revision = int(value["revision"])
	return CommandResultScript.failure(&"INVALID_ARGUMENT", maxi(0, revision), {"field": field})


static func _matches(value: Variant, pattern: String) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	if not _regex_cache.has(pattern):
		var compiled := RegEx.new()
		if compiled.compile(pattern) != OK:
			return false
		_regex_cache[pattern] = compiled
	return (_regex_cache[pattern] as RegEx).search(value) != null
