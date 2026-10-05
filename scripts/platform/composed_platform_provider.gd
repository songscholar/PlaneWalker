class_name ComposedPlatformProvider
extends "res://scripts/platform/platform_provider.gd"

const Rules := preload("res://scripts/platform/platform_rules.gd")
const Offline := preload("res://scripts/platform/offline_platform_provider.gd")
const LOCAL_ONLY := ["status", "discover_content", "entitlements", "share_cloud", "share_build", "share_replay", "capture_screenshot"]
const REMOTE_READS := ["identity", "friends", "presence", "leaderboard"]
var _offline: RefCounted
var _optional: RefCounted
var _last_failure := ""
var _last_operation := ""
var _last_status := "OFFLINE"
var _busy := false


func configure(offline: RefCounted, optional: RefCounted = null) -> Dictionary:
	if _busy or not offline is Offline or not offline.status().ok or optional != null and not optional.has_method("perform"):
		return failure(&"INVALID_ARGUMENT")
	_offline = offline
	_optional = optional
	_last_failure = ""
	_last_status = "OFFLINE"
	return success()


func perform(operation: String, request: Dictionary = {}) -> Dictionary:
	if _busy or _offline == null:
		return failure(&"BUSY" if _busy else &"NOT_CONFIGURED")
	if operation == "status":
		if not request.is_empty():
			return failure(&"INVALID_ARGUMENT")
		return success({"capabilities": CAPABILITIES.duplicate(), "mode": _last_status, "last_failure": _last_failure, "last_operation": _last_operation, "local_authority": true}, _last_status)
	_busy = true
	var local: Dictionary = _offline.perform(operation, request.duplicate(true))
	if not local.ok or _optional == null or operation in LOCAL_ONLY or operation == "leaderboard" and request.get("scope") == "local":
		_busy = false
		return local
	var remote: Variant = _optional.call("perform", operation, request.duplicate(true))
	_last_operation = operation
	if not Rules.valid_response(operation, remote) or operation == "leaderboard" and (remote.context.board_id != request.board_id or remote.context.scope != request.scope or remote.context.entries.size() > request.limit):
		_last_failure = str(remote.get("code", "PROVIDER_RESPONSE_INVALID")) if remote is Dictionary and remote.get("ok") == false else "PROVIDER_RESPONSE_INVALID"
		_last_status = "OFFLINE_FALLBACK"
		local.status = _last_status
		local.context["provider_failure"] = _last_failure
		_busy = false
		return local
	_last_failure = ""
	_last_status = "ONLINE"
	_busy = false
	return success(remote.context if operation in REMOTE_READS else local.context, "ONLINE")


func storage_identity() -> Dictionary:
	return _offline.storage_identity() if _offline != null else {}
