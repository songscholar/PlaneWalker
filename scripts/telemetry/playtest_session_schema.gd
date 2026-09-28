class_name PlaytestSessionSchema
extends RefCounted

const VERSION := "1.0.0"
const INPUT_DEVICES := ["keyboard_mouse", "controller", "mixed", "automation"]
const ROOM_TYPES := ["combat", "elite", "boss", "event", "merchant", "rest"]
const ROOM_RESULTS := ["cleared", "failed", "abandoned", "skipped"]
const FAILURE_PHASES := ["setup", "exploration", "combat", "choice", "boss", "result"]
const CHOICE_TYPES := ["item", "blessing", "curse", "talent", "weapon", "time_ability"]
const OUTCOMES := ["completed", "death", "abandoned", "technical_failure"]
const HUMAN_COLLECTION_METHODS := ["observed_playtest", "imported_observation"]
const SYNTHETIC_COLLECTION_METHODS := ["automated_fixture", "simulation"]
const REQUIRED_FIELDS := [
	"schema_version",
	"session_id",
	"evidence",
	"build",
	"run",
	"timing",
	"rooms",
	"damage",
	"failures",
	"build_choices",
	"terminal_result",
]


static func validate(session: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	_require_fields(session, REQUIRED_FIELDS, "$", errors)
	if session.get("schema_version") != VERSION:
		_add_error(errors, "unsupported-schema-version", "$.schema_version", "expected %s" % VERSION)
	if not _is_anonymous_session_id(session.get("session_id")):
		_add_error(errors, "invalid-session-id", "$.session_id", "expected pws_ plus 32 lowercase hex characters")
	_validate_evidence(session.get("evidence"), errors)
	_validate_build(session.get("build"), errors)
	_validate_run(session.get("run"), errors)
	_validate_timing(session.get("timing"), errors)
	_validate_rooms(session.get("rooms"), errors)
	_validate_damage(session.get("damage"), errors)
	_validate_failures(session.get("failures"), errors)
	_validate_choices(session.get("build_choices"), errors)
	_validate_terminal_result(session.get("terminal_result"), errors)
	return errors


static func _validate_evidence(value: Variant, errors: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_error(errors, "invalid-type", "$.evidence", "expected object")
		return
	var evidence: Dictionary = value
	_require_fields(evidence, ["source", "synthetic", "collection_method"], "$.evidence", errors)
	var source := str(evidence.get("source", ""))
	var synthetic: Variant = evidence.get("synthetic")
	var method := str(evidence.get("collection_method", ""))
	if source != "human" and source != "synthetic":
		_add_error(errors, "invalid-enum", "$.evidence.source", "expected human or synthetic")
	if not synthetic is bool:
		_add_error(errors, "invalid-type", "$.evidence.synthetic", "expected boolean")
	if source == "human" and (synthetic != false or not method in HUMAN_COLLECTION_METHODS):
		_add_error(errors, "evidence-mismatch", "$.evidence", "human evidence must remain non-synthetic")
	if source == "synthetic" and (synthetic != true or not method in SYNTHETIC_COLLECTION_METHODS):
		_add_error(errors, "evidence-mismatch", "$.evidence", "synthetic evidence must remain marked synthetic")


static func _validate_build(value: Variant, errors: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_error(errors, "invalid-type", "$.build", "expected object")
		return
	var build: Dictionary = value
	_require_fields(build, ["version", "commit", "content_version"], "$.build", errors)
	_nonempty_string(build.get("version"), "$.build.version", errors)
	_nonempty_string(build.get("content_version"), "$.build.content_version", errors)
	var commit := str(build.get("commit", ""))
	if not _matches_pattern(commit, "^[0-9a-f]{7,40}$"):
		_add_error(errors, "invalid-commit", "$.build.commit", "expected 7-40 lowercase hex characters")


static func _validate_run(value: Variant, errors: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_error(errors, "invalid-type", "$.run", "expected object")
		return
	var run: Dictionary = value
	_require_fields(run, ["seed", "input_device"], "$.run", errors)
	_integer(run.get("seed"), "$.run.seed", errors)
	if not str(run.get("input_device", "")) in INPUT_DEVICES:
		_add_error(errors, "invalid-enum", "$.run.input_device", "unsupported input device")


static func _validate_timing(value: Variant, errors: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_error(errors, "invalid-type", "$.timing", "expected object")
		return
	var timing: Dictionary = value
	_require_fields(timing, ["started_at_utc", "ended_at_utc", "duration_ms"], "$.timing", errors)
	_utc_timestamp(timing.get("started_at_utc"), "$.timing.started_at_utc", errors)
	_utc_timestamp(timing.get("ended_at_utc"), "$.timing.ended_at_utc", errors)
	_nonnegative_integer(timing.get("duration_ms"), "$.timing.duration_ms", errors)


static func _validate_rooms(value: Variant, errors: Array[Dictionary]) -> void:
	if not value is Array:
		_add_error(errors, "invalid-type", "$.rooms", "expected array")
		return
	for index: int in value.size():
		var room_value: Variant = value[index]
		var path := "$.rooms[%d]" % index
		if not room_value is Dictionary:
			_add_error(errors, "invalid-type", path, "expected object")
			continue
		var room: Dictionary = room_value
		_require_fields(room, ["room_id", "room_type", "room_index", "entered_at_ms", "completed_at_ms", "duration_ms", "result"], path, errors)
		_identifier(room.get("room_id"), "%s.room_id" % path, errors)
		if not str(room.get("room_type", "")) in ROOM_TYPES:
			_add_error(errors, "invalid-enum", "%s.room_type" % path, "unsupported room type")
		_nonnegative_integer(room.get("room_index"), "%s.room_index" % path, errors)
		_nonnegative_integer(room.get("entered_at_ms"), "%s.entered_at_ms" % path, errors)
		_nonnegative_integer(room.get("completed_at_ms"), "%s.completed_at_ms" % path, errors)
		_nonnegative_integer(room.get("duration_ms"), "%s.duration_ms" % path, errors)
		if room.get("entered_at_ms") is int and room.get("completed_at_ms") is int and room.get("duration_ms") is int:
			if int(room.completed_at_ms) - int(room.entered_at_ms) != int(room.duration_ms):
				_add_error(errors, "timing-mismatch", path, "duration must equal completed minus entered")
		if not str(room.get("result", "")) in ROOM_RESULTS:
			_add_error(errors, "invalid-enum", "%s.result" % path, "unsupported room result")


static func _validate_damage(value: Variant, errors: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_error(errors, "invalid-type", "$.damage", "expected object")
		return
	var damage: Dictionary = value
	_require_fields(damage, ["dealt", "taken", "hits_dealt", "hits_taken"], "$.damage", errors)
	for field: String in ["dealt", "taken", "hits_dealt", "hits_taken"]:
		_nonnegative_integer(damage.get(field), "$.damage.%s" % field, errors)


static func _validate_failures(value: Variant, errors: Array[Dictionary]) -> void:
	if not value is Array:
		_add_error(errors, "invalid-type", "$.failures", "expected array")
		return
	for index: int in value.size():
		var failure_value: Variant = value[index]
		var path := "$.failures[%d]" % index
		if not failure_value is Dictionary:
			_add_error(errors, "invalid-type", path, "expected object")
			continue
		var failure: Dictionary = failure_value
		_require_fields(failure, ["code", "phase", "room_index", "at_ms"], path, errors)
		_identifier(failure.get("code"), "%s.code" % path, errors)
		if not str(failure.get("phase", "")) in FAILURE_PHASES:
			_add_error(errors, "invalid-enum", "%s.phase" % path, "unsupported failure phase")
		_integer_at_least(failure.get("room_index"), "%s.room_index" % path, -1, errors)
		_nonnegative_integer(failure.get("at_ms"), "%s.at_ms" % path, errors)


static func _validate_choices(value: Variant, errors: Array[Dictionary]) -> void:
	if not value is Array:
		_add_error(errors, "invalid-type", "$.build_choices", "expected array")
		return
	for index: int in value.size():
		var choice_value: Variant = value[index]
		var path := "$.build_choices[%d]" % index
		if not choice_value is Dictionary:
			_add_error(errors, "invalid-type", path, "expected object")
			continue
		var choice: Dictionary = choice_value
		_require_fields(choice, ["choice_type", "choice_id", "room_index", "at_ms"], path, errors)
		if not str(choice.get("choice_type", "")) in CHOICE_TYPES:
			_add_error(errors, "invalid-enum", "%s.choice_type" % path, "unsupported choice type")
		_identifier(choice.get("choice_id"), "%s.choice_id" % path, errors)
		_integer_at_least(choice.get("room_index"), "%s.room_index" % path, -1, errors)
		_nonnegative_integer(choice.get("at_ms"), "%s.at_ms" % path, errors)


static func _validate_terminal_result(value: Variant, errors: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_error(errors, "invalid-type", "$.terminal_result", "expected object")
		return
	var result: Dictionary = value
	_require_fields(result, ["outcome", "floor", "room_index", "duration_ms", "cause"], "$.terminal_result", errors)
	if not str(result.get("outcome", "")) in OUTCOMES:
		_add_error(errors, "invalid-enum", "$.terminal_result.outcome", "unsupported outcome")
	_nonnegative_integer(result.get("floor"), "$.terminal_result.floor", errors)
	_integer_at_least(result.get("room_index"), "$.terminal_result.room_index", -1, errors)
	_nonnegative_integer(result.get("duration_ms"), "$.terminal_result.duration_ms", errors)
	_identifier(result.get("cause"), "$.terminal_result.cause", errors)


static func _require_fields(value: Dictionary, fields: Array, path: String, errors: Array[Dictionary]) -> void:
	for field: String in fields:
		if not value.has(field):
			_add_error(errors, "missing-field", "%s.%s" % [path, field], "required field is absent")


static func _is_anonymous_session_id(value: Variant) -> bool:
	if not value is String:
		return false
	var session_id: String = value
	if session_id.length() != 36 or not session_id.begins_with("pws_"):
		return false
	return session_id.substr(4).is_valid_hex_number(false) and session_id == session_id.to_lower()


static func _nonempty_string(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	if not value is String or str(value).strip_edges().is_empty():
		_add_error(errors, "invalid-string", path, "expected non-blank string")


static func _utc_timestamp(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	if not value is String or not _matches_pattern(str(value), "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?Z$"):
		_add_error(errors, "invalid-timestamp", path, "expected UTC ISO-8601 timestamp")


static func _identifier(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	if not value is String or not _matches_pattern(str(value), "^[a-z0-9_][a-z0-9_.-]*$"):
		_add_error(errors, "invalid-identifier", path, "expected lowercase data identifier")


static func _integer(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	if not value is int:
		_add_error(errors, "invalid-type", path, "expected integer")


static func _nonnegative_integer(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	_integer_at_least(value, path, 0, errors)


static func _integer_at_least(value: Variant, path: String, minimum: int, errors: Array[Dictionary]) -> void:
	if not value is int:
		_add_error(errors, "invalid-type", path, "expected integer")
	elif int(value) < minimum:
		_add_error(errors, "out-of-range", path, "expected value >= %d" % minimum)


static func _add_error(errors: Array[Dictionary], code: String, path: String, message: String) -> void:
	errors.append({"code": code, "path": path, "message": message})


static func _matches_pattern(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	return regex.search(value) != null
