class_name PlatformProvider
extends RefCounted

const OPERATIONS := ["status", "identity", "set_display_name", "achievements", "unlock_achievement", "cloud_write", "cloud_read", "cloud_list", "cloud_remove", "share_cloud", "submit_score", "leaderboard", "friends", "presence", "set_presence", "discover_content", "entitlements", "share_build", "share_replay", "capture_screenshot"]
const CAPABILITIES := ["identity", "achievements", "cloud_storage", "leaderboards", "friends_presence", "workshop", "entitlements", "screenshots_share"]


func perform(_operation: String, _request: Dictionary = {}) -> Dictionary:
	return failure(&"UNSUPPORTED_OPERATION")


func status() -> Dictionary:
	return perform("status")


func identity() -> Dictionary:
	return perform("identity")


func set_display_name(value: String) -> Dictionary:
	return perform("set_display_name", {"display_name": value})


func achievements() -> Dictionary:
	return perform("achievements")


func unlock_achievement(id: String) -> Dictionary:
	return perform("unlock_achievement", {"id": id})


func cloud_write(key: String, value: Dictionary, expected_digest: String = "") -> Dictionary:
	return perform("cloud_write", {"key": key, "value": value, "expected_digest": expected_digest})


func cloud_read(key: String) -> Dictionary:
	return perform("cloud_read", {"key": key})


func cloud_list() -> Dictionary:
	return perform("cloud_list")


func cloud_remove(key: String, expected_digest: String = "") -> Dictionary:
	return perform("cloud_remove", {"key": key, "expected_digest": expected_digest})


func share_cloud(key: String) -> Dictionary:
	return perform("share_cloud", {"key": key})


func storage_identity() -> Dictionary:
	return {}


func submit_score(board_id: String, entry_id: String, score: int, elapsed_ms: int) -> Dictionary:
	return perform("submit_score", {"board_id": board_id, "entry_id": entry_id, "score": score, "elapsed_ms": elapsed_ms})


func leaderboard(board_id: String = "runs", scope: String = "local", limit: int = 20) -> Dictionary:
	return perform("leaderboard", {"board_id": board_id, "scope": scope, "limit": limit})


func friends() -> Dictionary:
	return perform("friends")


func presence() -> Dictionary:
	return perform("presence")


func set_presence(activity: String) -> Dictionary:
	return perform("set_presence", {"activity": activity})


func discover_content() -> Dictionary:
	return perform("discover_content")


func entitlements() -> Dictionary:
	return perform("entitlements")


func share_build(build: Dictionary) -> Dictionary:
	return perform("share_build", {"build": build})


func share_replay(package: Dictionary) -> Dictionary:
	return perform("share_replay", {"package": package})


func capture_screenshot(image: Image) -> Dictionary:
	return perform("capture_screenshot", {"image": image})


static func success(context: Dictionary = {}, state: String = "OFFLINE") -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true), "status": state}


static func failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true), "status": "OFFLINE"}
