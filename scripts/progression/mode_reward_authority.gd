extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Daily := preload("res://scripts/modes/daily_boss_session.gd")
const Rush := preload("res://scripts/modes/boss_rush_carried_rules.gd")
const Catalog := preload("res://scripts/progression/challenge_reward_catalog.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const SOURCE_PATHS := {"res://scripts/modes/native_boss_rush_flow.gd": "boss_rush_carried", "res://scripts/modes/native_daily_boss_flow.gd": "daily_boss"}

var _registry: RefCounted
var _identity: Dictionary = {}
var _sources: Dictionary = {}
var _catalog: RefCounted


func configure(registry: RefCounted, identity: Dictionary) -> bool:
	var catalog := Catalog.new()
	if not registry is Registry or not Meta.exact_fields(identity, ["profile_id", "save_domain", "content_snapshot"]) or not Rules.same(Content.snapshot(registry), identity.content_snapshot) or not catalog.configure():
		return false
	_registry = registry
	_identity = identity.duplicate(true)
	_catalog = catalog
	return true


func attach(source: Node) -> Dictionary:
	if _registry == null or not is_instance_valid(source) or not source.is_inside_tree() or not source.has_method("mode_reward_storage_scope") or not source.get_script() is Script or not SOURCE_PATHS.has(source.get_script().resource_path):
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	var scope: Variant = source.call("mode_reward_storage_scope")
	if not _valid_scope(scope):
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	_sources[SOURCE_PATHS[source.get_script().resource_path]] = {"source": weakref(source), "scope": scope.duplicate(true)}
	return _success({})


func prepare(mode_id: String, collection: Dictionary) -> Dictionary:
	if not _sources.has(mode_id) or not Rules.same(Content.snapshot(_registry), _identity.content_snapshot) or not _catalog.valid_collection(collection):
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	var source: Node = _sources[mode_id].source.get_ref()
	var scope: Dictionary = _sources[mode_id].scope
	if not is_instance_valid(source) or not Rules.same(source.call("mode_reward_storage_scope"), scope):
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	var save := Save.new()
	if not save.configure(scope.root_path, "0.4.0-dev", scope.content_snapshot).ok:
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	# Inspect the promoted primary; a pending file cannot authorize ownership.
	var primary = save.inspect_profile(scope.save_id, scope.save_domain)
	if not primary.ok:
		return _failure(primary.code)
	var key := "daily_session" if mode_id == "daily_boss" else "boss_rush_session"
	var physical: Dictionary = primary.payload.payload
	if not Meta.exact_fields(physical, [key, "active_item_state", "active_run_state", "reward_effect_state"]) or not Rules.same(physical.active_item_state, Envelope.empty_active_item_state()) or physical.active_run_state != {} or physical.reward_effect_state != {}:
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	var payload := {key: physical[key]}
	var aggregate := Daily.validated_reward_aggregate(payload, scope.source_owner_id, scope.mode_fingerprint, _registry) if mode_id == "daily_boss" else Rush.validated_reward_aggregate(payload, scope.source_owner_id, scope.mode_fingerprint, _registry)
	if not aggregate.get("ok", false):
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	var owned: Array[String] = []
	for id: String in aggregate.entitlement_ids + aggregate.owned_ids:
		if _catalog.definition(id).is_empty():
			return _failure(&"MODE_REWARD_CONTENT_INVALID")
		if not owned.has(id):
			owned.append(id)
	owned.sort()
	var result := collection.duplicate(true)
	var previous: Dictionary = {}
	for row: Dictionary in result.source_receipts:
		if row.mode_id == mode_id:
			previous = row
	for id: String in previous.get("owned_ids", []):
		if not owned.has(id):
			return _failure(&"MODE_REWARD_SOURCE_REGRESSION")
	if Rules.same(owned, previous.get("owned_ids", [])):
		return _success({"collection": result, "duplicate": true, "aggregate": aggregate})
	if not previous.is_empty():
		result.source_receipts.erase(previous)
	var receipt := {"mode_id": mode_id, "source_id": aggregate.source_id, "source_digest": Rules.canonical(aggregate).sha256_text(), "owned_ids": owned}
	result.source_receipts.append(receipt)
	result.source_receipts.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.mode_id) < str(right.mode_id))
	for id: String in owned:
		if not result.owned_ids.has(id):
			result.owned_ids.append(id)
	result.owned_ids.sort()
	if not _catalog.valid_collection(result):
		return _failure(&"MODE_REWARD_COLLECTION_INVALID")
	return _success({"collection": result, "duplicate": false, "command_id": "mode-reward:" + Rules.canonical(receipt).sha256_text().substr(0, 40), "aggregate": aggregate})


func _valid_scope(value: Variant) -> bool:
	return Meta.exact_fields(value, ["root_path", "save_id", "save_domain", "source_owner_id", "source_save_domain", "content_snapshot", "mode_fingerprint"]) and value.root_path is String and not value.root_path.is_empty() and value.save_id is String and value.save_domain == "local" and value.source_owner_id == _identity.profile_id and value.source_save_domain == _identity.save_domain and Rules.same(value.content_snapshot, _identity.content_snapshot) and Meta.fingerprint_valid(value.mode_fingerprint)


static func _success(context: Dictionary) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
