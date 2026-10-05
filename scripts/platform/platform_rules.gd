extends RefCounted

const Provider := preload("res://scripts/platform/platform_provider.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const MAX_ACHIEVEMENTS := 256
const MAX_CLOUD_KEYS := 64
const MAX_CLOUD_BYTES := 65536
const MAX_STATE_BYTES := 1048576
const MAX_BOARDS := 16
const MAX_BOARD_ENTRIES := 100
const MAX_SCORE := 2147483647
const ACTIVITIES := ["offline", "hub", "playing", "paused", "replay", "challenge", "boss_rush", "endless"]


static func fields(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for field: String in expected:
		if not value.has(field):
			return false
	return true


static func id(value: Variant) -> bool:
	return Paths.validate_id(value).ok


static func display_name(value: Variant) -> bool:
	if not value is String or value.is_empty() or value != value.strip_edges() or value.length() > 64:
		return false
	for index: int in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127:
			return false
	return true


static func integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high


static func digest(value: Variant, empty_allowed: bool = false) -> bool:
	if not value is String:
		return false
	if empty_allowed and value.is_empty():
		return true
	if value.length() != 64:
		return false
	for index: int in value.length():
		if value.unicode_at(index) not in range(48, 58) and value.unicode_at(index) not in range(97, 103):
			return false
	return true


static func safe_json(value: Variant, depth: int = 0) -> bool:
	if depth > 16:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING:
			return value.length() <= MAX_CLOUD_BYTES and not value.to_utf8_buffer().has(0)
		TYPE_ARRAY:
			if value.size() > 1024:
				return false
			for child: Variant in value:
				if not safe_json(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 1024:
				return false
			for key: Variant in value:
				if not key is String or key.length() > 128 or key.to_utf8_buffer().has(0) or not safe_json(value[key], depth + 1):
					return false
			return true
	return false


static func bounded_json(value: Variant, limit: int = MAX_CLOUD_BYTES) -> bool:
	return safe_json(value) and Envelope.canonical_json(value).to_utf8_buffer().size() <= limit


static func same(left: Variant, right: Variant) -> bool:
	return canonical(left) == canonical(right)


static func canonical(value: Variant) -> String:
	var encoded := Envelope.canonical_json(value)
	return Envelope.canonical_json(JSON.parse_string(encoded)) if not encoded.is_empty() else ""


static func json_digest(value: Variant) -> String:
	return canonical(value).sha256_text()


static func valid_request(operation: String, request: Dictionary) -> bool:
	match operation:
		"status", "identity", "achievements", "cloud_list", "friends", "presence", "discover_content", "entitlements":
			return request.is_empty()
		"set_display_name":
			return fields(request, ["display_name"]) and display_name(request.display_name)
		"unlock_achievement":
			return fields(request, ["id"]) and id(request.id)
		"cloud_write":
			return fields(request, ["key", "value", "expected_digest"]) and id(request.key) and request.value is Dictionary and bounded_json(request.value) and digest(request.expected_digest, true)
		"cloud_read", "share_cloud":
			return fields(request, ["key"]) and id(request.key)
		"cloud_remove":
			return fields(request, ["key", "expected_digest"]) and id(request.key) and digest(request.expected_digest, true)
		"submit_score":
			return fields(request, ["board_id", "entry_id", "score", "elapsed_ms"]) and id(request.board_id) and id(request.entry_id) and integer(request.score, 0, MAX_SCORE) and integer(request.elapsed_ms, 1, MAX_SCORE)
		"leaderboard":
			return fields(request, ["board_id", "scope", "limit"]) and id(request.board_id) and request.scope in ["local", "global", "friends"] and integer(request.limit, 1, MAX_BOARD_ENTRIES)
		"set_presence":
			return fields(request, ["activity"]) and request.activity in ACTIVITIES
		"share_build":
			return fields(request, ["build"]) and request.build is Dictionary and bounded_json(request.build)
		"share_replay":
			return fields(request, ["package"]) and request.package is Dictionary
		"capture_screenshot":
			return fields(request, ["image"]) and request.image is Image and not request.image.is_empty() and request.image.get_width() <= 4096 and request.image.get_height() <= 4096 and request.image.get_width() * request.image.get_height() <= 4194304
	return false


static func storage_path_safe(value: String) -> bool:
	if value.is_empty() or value.begins_with("res://") or not (value.begins_with("user://") or value.is_absolute_path()) or value.contains("\\"):
		return false
	for component: String in value.split("/"):
		if component in [".", ".."]:
			return false
	var absolute := ProjectSettings.globalize_path(value).simplify_path()
	var current := "/"
	for component: String in absolute.trim_prefix("/").split("/"):
		var parent := DirAccess.open(current)
		if parent != null and parent.is_link(component):
			return false
		current = current.path_join(component)
	return true


static func valid_state(value: Variant, identity_id: String) -> bool:
	if not fields(value, ["schema_version", "identity", "achievements", "cloud", "boards", "presence"]) or not integer(value.schema_version, 1, 1) or not fields(value.identity, ["id", "display_name"]) or value.identity.id != identity_id or not display_name(value.identity.display_name):
		return false
	if not value.achievements is Array or value.achievements.size() > MAX_ACHIEVEMENTS or not value.cloud is Dictionary or value.cloud.size() > MAX_CLOUD_KEYS or not value.boards is Dictionary or value.boards.size() > MAX_BOARDS or value.presence not in ACTIVITIES:
		return false
	var previous := ""
	for achievement: Variant in value.achievements:
		if not id(achievement) or achievement <= previous:
			return false
		previous = achievement
	for key: Variant in value.cloud:
		var entry: Variant = value.cloud[key]
		if not id(key) or not fields(entry, ["value", "digest"]) or not entry.value is Dictionary or not bounded_json(entry.value) or not digest(entry.digest) or entry.digest != json_digest(entry.value):
			return false
	for board_id: Variant in value.boards:
		var entries: Variant = value.boards[board_id]
		if not id(board_id) or not entries is Array or entries.size() > MAX_BOARD_ENTRIES:
			return false
		var seen: Dictionary = {}
		var prior: Dictionary = {}
		for entry: Variant in entries:
			if not fields(entry, ["id", "score", "elapsed_ms", "display_name"]) or not id(entry.id) or seen.has(entry.id) or not integer(entry.score, 0, MAX_SCORE) or not integer(entry.elapsed_ms, 1, MAX_SCORE) or not display_name(entry.display_name) or not prior.is_empty() and ranks_before(entry, prior):
				return false
			seen[entry.id] = true
			prior = entry
	return bounded_json(value, MAX_STATE_BYTES)


static func ranks_before(left: Dictionary, right: Dictionary) -> bool:
	if left.score != right.score:
		return left.score > right.score
	if left.elapsed_ms != right.elapsed_ms:
		return left.elapsed_ms < right.elapsed_ms
	return left.id < right.id


static func valid_response(operation: String, value: Variant) -> bool:
	if not value is Dictionary or not value.get("ok", false) is bool or not value.ok or not value.get("context") is Dictionary or str(value.get("code", "")) != "OK" or not bounded_json(value.context, MAX_STATE_BYTES):
		return false
	var context: Dictionary = value.context
	match operation:
		"identity":
			return fields(context, ["id", "display_name"]) and id(context.id) and display_name(context.display_name)
		"friends":
			if not fields(context, ["entries"]) or not context.entries is Array or context.entries.size() > 100:
				return false
			var seen: Dictionary = {}
			for friend: Variant in context.entries:
				if not fields(friend, ["id", "display_name", "activity"]) or not id(friend.id) or seen.has(friend.id) or not display_name(friend.display_name) or friend.activity not in ACTIVITIES:
					return false
				seen[friend.id] = true
			return true
		"presence":
			return fields(context, ["activity"]) and context.activity in ACTIVITIES
		"leaderboard":
			if not fields(context, ["board_id", "scope", "ranked", "entries"]) or not id(context.board_id) or context.scope not in ["global", "friends"] or context.ranked != true or not context.entries is Array or context.entries.size() > MAX_BOARD_ENTRIES:
				return false
			var seen: Dictionary = {}
			var prior: Dictionary = {}
			for entry: Variant in context.entries:
				if not fields(entry, ["id", "score", "elapsed_ms", "display_name"]) or not id(entry.id) or seen.has(entry.id) or not integer(entry.score, 0, MAX_SCORE) or not integer(entry.elapsed_ms, 1, MAX_SCORE) or not display_name(entry.display_name) or not prior.is_empty() and ranks_before(entry, prior):
					return false
				seen[entry.id] = true
				prior = entry
			return true
	return fields(context, ["acknowledged"]) and context.acknowledged == true
