class_name PlayerReplayPackage
extends RefCounted

const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const Playback := preload("res://scripts/replay/replay_player.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const FIELDS: Array[String] = ["schema_id", "schema_version", "game_version", "content_snapshot", "save_domain", "recording_json", "recording_sha256", "id"]
const SCHEMA_ID := "planewalker.player_replay_package"
const MAX_PACKAGE_BYTES := Recorder.MAX_JSON_PAYLOAD_BYTES * 2 + 65536


static func create(replay: Dictionary, game_version: String, binding: Dictionary, domain: String) -> Dictionary:
	if game_version.strip_edges().is_empty() or not Paths.validate_id(domain).ok or not Envelope._content_snapshot_error(binding).is_empty():
		return _failure(&"REPLAY_PACKAGE_SCOPE_INVALID")
	var verified := Playback.new().load_full_player_replay(replay, replay.get("identity", {}))
	if not verified.ok:
		return verified
	var encoded: Dictionary = Recorder.encode_replay_json(replay)
	if not encoded.ok:
		return encoded
	var package := {"schema_id": SCHEMA_ID, "schema_version": 1, "game_version": game_version, "content_snapshot": binding.duplicate(true), "save_domain": domain, "recording_json": encoded.json, "recording_sha256": str(encoded.json).sha256_text()}
	package["id"] = Recorder.value_digest(package)
	return _success({"package": package})


static func decode(encoded: String, game_version: String, binding: Dictionary, domain: String) -> Dictionary:
	if encoded.is_empty() or encoded.to_utf8_buffer().size() > MAX_PACKAGE_BYTES:
		return _failure(&"REPLAY_PACKAGE_SIZE_INVALID")
	var value: Variant = JSON.parse_string(encoded)
	return validate(value, game_version, binding, domain)


static func validate(value: Variant, game_version: String, binding: Dictionary, domain: String) -> Dictionary:
	if not value is Dictionary or value.size() != FIELDS.size():
		return _failure(&"REPLAY_PACKAGE_INVALID")
	for field: String in FIELDS:
		if not value.has(field):
			return _failure(&"REPLAY_PACKAGE_INVALID")
	if value.schema_id != SCHEMA_ID or typeof(value.schema_version) not in [TYPE_INT, TYPE_FLOAT] or value.schema_version != 1 or value.game_version != game_version or value.save_domain != domain or not value.content_snapshot is Dictionary or Envelope.canonical_json(value.content_snapshot) != Envelope.canonical_json(binding):
		return _failure(&"REPLAY_PACKAGE_INCOMPATIBLE")
	if not value.recording_json is String or value.recording_json.is_empty() or value.recording_json.to_utf8_buffer().size() > MAX_PACKAGE_BYTES or value.recording_sha256 != value.recording_json.sha256_text() or not valid_id(value.id):
		return _failure(&"REPLAY_PACKAGE_DIGEST_INVALID")
	var identity_source: Dictionary = value.duplicate(true)
	identity_source.erase("id")
	identity_source.schema_version = 1
	# JSON changes integral metadata types; content identity uses its JSON canonical form.
	identity_source.content_snapshot = binding.duplicate(true)
	if Recorder.value_digest(identity_source) != value.id:
		return _failure(&"REPLAY_PACKAGE_DIGEST_INVALID")
	var decoded := Recorder.decode_replay_json(value.recording_json)
	if not decoded.ok:
		return decoded
	var replay: Dictionary = decoded.replay
	var verified := Playback.new().load_full_player_replay(replay, replay.get("identity", {}))
	if not verified.ok:
		return verified
	var package: Dictionary = value.duplicate(true)
	package.schema_version = 1
	package.content_snapshot = binding.duplicate(true)
	return _success({"package": package, "replay": replay, "summary": Recorder.full_player_replay_summary(replay)})


static func valid_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and Recorder._is_sha256(value)


static func _success(context: Dictionary) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
