class_name HubRuntimeFacade
extends RefCounted

const Registry := preload("res://scripts/content/content_registry.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const District := preload("res://scripts/content/hub_district_definition.gd")
const Loadouts := preload("res://scripts/application/run_loadout_catalog.gd")
const Policy := preload("res://scripts/application/run_loadout_policy.gd")
const Config := preload("res://scripts/application/run_config.gd")
const Projector := preload("res://scripts/hub/hub_view_state_projector.gd")
const Contract := preload("res://scripts/ui/contracts/hub_view_state.gd")
const OPERATIONS := {"meta_unlock": ["council"], "forge_upgrade": ["forge"], "enchant_preference": ["forge"], "void_temper": ["forge"], "build_save": ["meditation"], "build_remove": ["meditation"], "build_select": ["meditation", "gateway"], "select_loadout": ["meditation", "gateway"], "launch": ["gateway"], "provider_refresh": ["gateway", "merchant", "mirror"]}

var _registry: RefCounted
var _service: RefCounted
var _projector: RefCounted
var _districts: Dictionary = {}
var _district_id := ""
var _function_id := ""
var _epoch := 0
var _selection: Dictionary = {}
var _providers: Dictionary = {}
var _provider_rows: Array = []
var _busy := false


func configure(registry: RefCounted, profile_service: RefCounted, providers: Dictionary = {}) -> Dictionary:
	if _busy or not registry is Registry or not profile_service is Service:
		return _failure(&"CONFIGURATION_INVALID")
	for id: Variant in providers:
		if id not in ["daily", "leaderboard", "social"] or not providers[id] is Callable or not providers[id].is_valid():
			return _failure(&"CONFIGURATION_INVALID")
	var built := Factory.from_registry(registry)
	var snapshot: Dictionary = profile_service.snapshot()
	if not built.ok or snapshot.is_empty() or snapshot.catalog_fingerprint != built.context.catalog.fingerprint():
		return _failure(&"PROFILE_CONTENT_MISMATCH")
	var districts: Dictionary = {}
	for row: Dictionary in registry.get_catalog_entries(&"hub_district", &"LAUNCH"):
		var descriptor := District.new()
		if not descriptor.configure(row).ok or districts.has(row.id):
			return _failure(&"HUB_DISTRICT_INVALID")
		districts[row.id] = descriptor.snapshot()
	var loadouts := Loadouts.new()
	var projector := Projector.new()
	if districts.size() != 3 or not loadouts.configure(registry, &"LAUNCH") or not projector.configure(registry, built.context.catalog, loadouts):
		return _failure(&"CONTENT_INVALID")
	var selection := Config.normalized({"milestone": "LAUNCH", "character_id": snapshot.unlocked_characters[0], "weapon_id": "sword" if snapshot.unlocked_weapons.has("sword") else snapshot.unlocked_weapons[0]})
	if not _validate_selection(selection, registry, snapshot).ok:
		return _failure(&"LOADOUT_INVALID")
	var rows: Array = []
	for id: String in ["daily", "leaderboard", "social"]:
		rows.append(_unavailable_provider(id))
	if projector.project(profile_service, selection, "hub_council", "", _epoch + 1, rows).is_empty():
		return _failure(&"VIEW_STATE_INVALID")
	_registry = registry
	_service = profile_service
	_projector = projector
	_districts = districts
	_district_id = "hub_council"
	_function_id = ""
	_epoch += 1
	_selection = selection
	_providers = providers.duplicate()
	_provider_rows = rows
	return _success()


func travel(district_id: String, expected_revision: int, expected_epoch: int = -1) -> Dictionary:
	var ready := _readiness(expected_revision, expected_epoch)
	if not ready.ok:
		return ready
	if not _districts.has(district_id):
		return _failure(&"HUB_DISTRICT_UNKNOWN")
	if district_id == _district_id and _function_id.is_empty():
		return _failure(&"NO_CHANGE")
	_district_id = district_id
	_function_id = ""
	_epoch += 1
	return _success()


func command(value: Dictionary, expected_revision: int) -> Dictionary:
	if not Catalog.exact_fields(value, ["epoch", "function_id", "operation", "payload"]) or not Catalog.bounded_int(value.epoch, 0, Catalog.MAX_VALUE) or not value.function_id is String or not value.operation is String or not value.payload is Dictionary:
		return _failure(&"COMMAND_INVALID")
	var ready := _readiness(expected_revision, value.epoch)
	if not ready.ok:
		return ready
	var function := _function(value.function_id)
	if function.is_empty():
		return _failure(&"HUB_FUNCTION_UNKNOWN")
	var operation: String = value.operation
	var payload: Dictionary = value.payload.duplicate(true)
	if operation == "open":
		if not payload.is_empty():
			return _failure(&"COMMAND_INVALID")
		_function_id = function.id
		_epoch += 1
		return _success()
	if value.function_id != _function_id:
		return _failure(&"HUB_PANEL_STALE")
	if operation == "back":
		if not payload.is_empty():
			return _failure(&"COMMAND_INVALID")
		_function_id = ""
		_epoch += 1
		return _success()
	if operation != "narrative_dialogue" and (not OPERATIONS.has(operation) or not OPERATIONS[operation].has(_function_id)):
		return _failure(&"HUB_OPERATION_UNAVAILABLE")
	var result: Dictionary
	_busy = true
	match operation:
		"meta_unlock", "forge_upgrade", "enchant_preference", "void_temper", "build_save", "build_remove":
			result = _service.execute(payload, expected_revision) if payload.get("kind") == operation else _failure(&"COMMAND_INVALID")
		"narrative_dialogue":
			result = _service.execute_narrative(payload, expected_revision) if payload.get("kind") == "narrative_dialogue" and payload.get("npc_id") == function.npc_id else _failure(&"DIALOGUE_INVALID")
		"select_loadout":
			result = _select(payload)
		"build_select":
			result = _select_build(payload)
		"launch":
			result = _launch(payload)
		"provider_refresh":
			result = _refresh_provider(payload)
	_busy = false
	if result.ok:
		_epoch += 1
		result.context["view_state"] = view_state()
		result.context["epoch"] = _epoch
		result.context["revision"] = int(_service.snapshot().revision)
	return result


func view_state() -> Dictionary:
	return _projector.project(_service, _selection, _district_id, _function_id, _epoch, _provider_rows) if _projector != null else {}


func _select(value: Dictionary) -> Dictionary:
	if not Catalog.exact_fields(value, ["character_id", "weapon_id", "time_abilities", "difficulty"]):
		return _failure(&"LOADOUT_INVALID")
	var config := Config.normalized({"milestone": "LAUNCH", "character_id": value.character_id, "weapon_id": value.weapon_id, "enabled_time_skills": value.time_abilities, "difficulty": value.difficulty})
	var valid := _validate_selection(config, _registry, _service.snapshot())
	if not valid.ok:
		return valid
	_selection = config
	return {"ok": true, "code": &"OK", "context": {"run_config": config.duplicate(true)}}


func _select_build(value: Dictionary) -> Dictionary:
	if not Catalog.exact_fields(value, ["build_id"]) or not value.build_id is String:
		return _failure(&"COMMAND_INVALID")
	var resolved: Dictionary = _service.resolve_build(value.build_id)
	if not resolved.ok:
		return resolved
	var build: Dictionary = resolved.context.build
	var abilities: Array = []
	for id: String in Policy.TIME_ABILITY_ORDER:
		if build.time_abilities.has(id):
			abilities.append(id)
	return _select({"character_id": build.character_id, "weapon_id": build.weapon_id, "time_abilities": abilities, "difficulty": _selection.difficulty})


func _launch(value: Dictionary) -> Dictionary:
	if not Catalog.exact_fields(value, ["seed"]) or not Catalog.bounded_int(value.seed, 0, Catalog.MAX_VALUE):
		return _failure(&"RUN_CONFIG_INVALID")
	var snapshot: Dictionary = _service.snapshot()
	if not snapshot.active_launch_receipt.is_empty():
		return _failure(&"LAUNCH_ACTIVE")
	var config := _selection.duplicate(true)
	config.seed = int(value.seed)
	var valid := _validate_selection(config, _registry, snapshot)
	if not valid.ok:
		return valid
	return {"ok": true, "code": &"OK", "context": {"run_config": config}}


func _refresh_provider(value: Dictionary) -> Dictionary:
	if not Catalog.exact_fields(value, ["provider_id"]) or value.provider_id not in ["daily", "leaderboard", "social"]:
		return _failure(&"COMMAND_INVALID")
	var id: String = value.provider_id
	var row := _unavailable_provider(id)
	if _providers.has(id):
		var produced: Variant = (_providers[id] as Callable).call()
		if produced is Dictionary:
			var probe := view_state()
			for index: int in range(probe.providers.size()):
				if probe.providers[index].id == id:
					probe.providers[index] = produced.duplicate(true)
			if produced.get("id") == id and Contract.validate(probe).ok:
				row = produced.duplicate(true)
	for index: int in range(_provider_rows.size()):
		if _provider_rows[index].id == id:
			_provider_rows[index] = row
	return {"ok": true, "code": &"OK", "context": {"provider_status": row.status}}


func _function(id: String) -> Dictionary:
	for row: Dictionary in _districts[_district_id].functions:
		if row.id == id:
			return row.duplicate(true)
	return {}


func _readiness(revision: int, epoch: int) -> Dictionary:
	if _service == null or _busy:
		return _failure(&"BUSY" if _busy else &"NOT_CONFIGURED")
	if revision != _service.snapshot().revision:
		return _failure(&"STALE_REVISION")
	if epoch >= 0 and epoch != _epoch:
		return _failure(&"STALE_EPOCH")
	if _epoch == Catalog.MAX_VALUE:
		return _failure(&"TRANSACTION_LIMIT")
	return {"ok": true, "code": &"OK", "context": {}}


static func _validate_selection(config: Dictionary, registry: RefCounted, snapshot: Dictionary) -> Dictionary:
	if not snapshot.unlocked_characters.has(config.character_id) or not snapshot.unlocked_weapons.has(config.weapon_id):
		return {"ok": false, "code": &"LOADOUT_LOCKED", "context": {}}
	var valid = Policy.new().validate(config, registry)
	return {"ok": valid.ok, "code": valid.code, "context": valid.context.duplicate(true)}


static func _unavailable_provider(id: String) -> Dictionary:
	return {"id": id, "status": "UNAVAILABLE", "entries": [], "available": false, "reason_key": "HUB_PROVIDER_UNAVAILABLE", "cost": {"chronos_shards": 0, "existential_imprints": 0}}


func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {"view_state": view_state(), "epoch": _epoch, "revision": int(_service.snapshot().revision)}}


func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
