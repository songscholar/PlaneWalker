extends Node

const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const SaveMigrationRegistryScript := preload("res://scripts/save/save_migration_registry.gd")
const SaveResultScript := preload("res://scripts/save/save_result.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const RuntimeUserDataPathScript := preload("res://scripts/save/runtime_user_data_path.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const ContentSnapshotScript := preload("res://scripts/content/content_snapshot_provider.gd")
const MetaFactoryScript := preload("res://scripts/progression/meta_catalog_factory.gd")
const ProfileServiceScript := preload("res://scripts/progression/profile_runtime_service.gd")
const ActualCompatibilityScript := preload("res://scripts/save/actual_content_compatibility_ledger.gd")
const ActiveContentMigrationScript := preload("res://scripts/save/active_content_migration_authority.gd")
const SavePathsScript := preload("res://scripts/save/save_path_policy.gd")

const SAVE_GAME_VERSION := "0.4.0-dev"
const DEFAULT_PROFILE_ID := "slot_1"
const DEFAULT_SAVE_DOMAIN := "base"
const DEFAULT_SETTINGS := {
	"locale": "zh_CN",
	"master_volume": 0.85,
	"master_muted": false,
	"music_volume": 0.80,
	"sfx_volume": 0.90,
	"dialogue_volume": 0.90,
	"camera_shake_enabled": true,
	"hit_flash_enabled": true,
	"reduced_motion": false,
	"text_scale": 1.0,
	"high_contrast_danger": false,
	"subtitles_enabled": true,
	"subtitle_scale": 1.0,
	"ranged_charge_mode": "hold",
	"damage_received_multiplier": 1.0,
	"enemy_telegraph_scale": 1.0,
}
const SETTING_IDS: Array[String] = [
	"locale",
	"master_volume",
	"master_muted",
	"music_volume",
	"sfx_volume",
	"dialogue_volume",
	"camera_shake_enabled",
	"hit_flash_enabled",
	"reduced_motion",
	"text_scale",
	"high_contrast_danger",
	"subtitles_enabled",
	"subtitle_scale",
	"ranged_charge_mode",
	"damage_received_multiplier",
	"enemy_telegraph_scale",
]

signal setting_changed(setting_id: StringName, value: Variant)

var save_path: String = "user://plane_walker_save.json"
var persistent: Dictionary = {}
var _save_service: RefCounted
var _save_service_path: String = ""
var _profile_runtime: RefCounted
var _profile_catalog: RefCounted
var _content_binding: Dictionary = {}
var _profile_save_domain := DEFAULT_SAVE_DOMAIN


func _ready() -> void:
	if save_path == "user://plane_walker_save.json":
		save_path = RuntimeUserDataPathScript.resolve_default(save_path, "plane_walker_save.json")
	persistent = _default_persistent_data()
	if _ensure_save_service().ok:
		var loaded = _save_service.load_settings()
		if loaded.ok:
			persistent.settings = _settings_payload(loaded.payload)


func activate_profile_content(registry: RefCounted, save_domain: String = DEFAULT_SAVE_DOMAIN) -> Dictionary:
	if save_path.is_empty() or not registry is ContentRegistryScript or not SavePathsScript.validate_id(save_domain).ok:
		return {"ok": false, "code": &"INVALID_ARGUMENT", "context": {}}
	var binding := ContentSnapshotScript.snapshot(registry)
	if binding.is_empty():
		return {"ok": false, "code": &"CONTENT_UNAVAILABLE", "context": {}}
	if _profile_runtime != null and _save_service_path == save_path and binding == _content_binding and save_domain == _profile_save_domain:
		return {"ok": true, "code": &"OK", "context": {}}
	var factory := MetaFactoryScript.from_registry(registry, &"LAUNCH" if save_domain == DEFAULT_SAVE_DOMAIN else &"EXPANSION")
	if not factory.ok:
		return factory
	var catalog: RefCounted = factory.context.catalog
	var service := SaveServiceScript.new()
	var configured = service.configure(_save_service_root_path(), SAVE_GAME_VERSION, binding)
	if not configured.ok or not service.enable_meta_profile(catalog).ok:
		return {"ok": false, "code": &"CONFIGURATION_INVALID", "context": {}}
	var inspected = service.inspect_profile(DEFAULT_PROFILE_ID, save_domain)
	if inspected.code == &"CONTENT_MISMATCH" and save_domain == DEFAULT_SAVE_DOMAIN:
		var sources := ActualCompatibilityScript.trusted_sources(binding, catalog.fingerprint())
		var trusted := sources.duplicate(true)
		sources.append(_legacy_content_snapshot())
		var matched := false
		for prior: Dictionary in sources:
			var source := SaveServiceScript.new()
			if not source.configure(_save_service_root_path(), SAVE_GAME_VERSION, prior).ok or not source.enable_meta_profile(catalog).ok:
				continue
			var legacy = source.inspect_profile(DEFAULT_PROFILE_ID, DEFAULT_SAVE_DOMAIN)
			if not legacy.ok:
				continue
			if not legacy.payload.payload.get("active_run_state", {}).is_empty() or not legacy.payload.payload.get("native_run_checkpoint", {}).is_empty():
				if prior not in trusted:
					return {"ok": false, "code": &"NATIVE_CONTENT_MIGRATION_REQUIRED", "context": {"stage": "untrusted_active_source", "source_snapshot": prior.duplicate(true)}}
				var compatible := ActiveContentMigrationScript.verify(source, catalog, DEFAULT_PROFILE_ID, DEFAULT_SAVE_DOMAIN, binding, self)
				if not compatible.ok:
					compatible.context["source_snapshot"] = prior.duplicate(true)
					return compatible
			var rebound = source.rebind_profile_content(DEFAULT_PROFILE_ID, DEFAULT_SAVE_DOMAIN, prior, binding, legacy.payload)
			if not rebound.ok:
				return {"ok": false, "code": rebound.code, "context": rebound.metadata.duplicate(true)}
			service = source
			matched = true
			break
		if not matched:
			return {"ok": false, "code": inspected.code, "context": inspected.metadata.duplicate(true)}
	var old_save := _save_service
	var old_path := _save_service_path
	var old_catalog := _profile_catalog
	var old_binding := _content_binding.duplicate(true)
	var old_domain := _profile_save_domain
	var old_persistent := persistent.duplicate(true)
	_save_service = service
	_save_service_path = save_path
	_profile_catalog = catalog
	_content_binding = binding.duplicate(true)
	_profile_save_domain = save_domain
	if save_domain == DEFAULT_SAVE_DOMAIN and inspected.code == &"NOT_FOUND" and FileAccess.file_exists(save_path) and not _import_legacy_persistent():
		_save_service = old_save
		_save_service_path = old_path
		_profile_catalog = old_catalog
		_content_binding = old_binding
		_profile_save_domain = old_domain
		persistent = old_persistent
		return {"ok": false, "code": &"LEGACY_IMPORT_FAILED", "context": {}}
	var runtime := ProfileServiceScript.new()
	var activated := runtime.configure(catalog, service, DEFAULT_PROFILE_ID, save_domain)
	if not activated.ok:
		_save_service = old_save
		_save_service_path = old_path
		_profile_catalog = old_catalog
		_content_binding = old_binding
		_profile_save_domain = old_domain
		persistent = old_persistent
		return activated
	_profile_runtime = runtime
	refresh_profile_state()
	return activated


func profile_runtime_service() -> RefCounted:
	return _profile_runtime if _save_service_path == save_path else null


func active_profile_domain() -> String:
	return _profile_save_domain if profile_runtime_service() != null else ""


func refresh_profile_state() -> bool:
	var service := profile_runtime_service()
	if service == null:
		return false
	var profile: Dictionary = service.snapshot()
	var payload: Dictionary = service.payload()
	payload["meta_profile_state"] = profile.duplicate(true)
	for field: String in ProfileServiceScript.MIRROR_FIELDS:
		payload[field] = profile[field].duplicate(true) if profile[field] is Array or profile[field] is Dictionary else profile[field]
	payload["runs_completed"] = int(profile.statistics.finished_runs)
	payload["victories"] = int(profile.statistics.victories)
	persistent = _compose_persistent_values(payload, normalized_settings())
	return true


func set_setting(setting_id: String, value: Variant) -> bool:
	var settings: Dictionary = persistent.get("settings", {})
	settings[setting_id] = value
	persistent["settings"] = settings
	if not SETTING_IDS.has(setting_id):
		return false
	var service_result = _ensure_save_service()
	if not service_result.ok:
		return false
	var save_result = _save_service.save_settings(_settings_payload(settings))
	if not save_result.ok:
		return false
	setting_changed.emit(StringName(setting_id), value)
	return true


func get_setting(setting_id: String, default_value: Variant = null) -> Variant:
	return persistent.get("settings", {}).get(setting_id, default_value)


func normalized_settings() -> Dictionary:
	var settings_value: Variant = persistent.get("settings", {})
	var settings := settings_value as Dictionary if settings_value is Dictionary else {}
	return _settings_payload(settings)


func load_persistent() -> bool:
	if profile_runtime_service() != null:
		return refresh_profile_state()
	var service_result = _ensure_save_service()
	if not service_result.ok:
		return false
	var profile_result = _save_service.load_profile(DEFAULT_PROFILE_ID, DEFAULT_SAVE_DOMAIN)
	var settings_result = _save_service.load_settings()

	if profile_result.ok:
		if not settings_result.ok and settings_result.code != &"NOT_FOUND":
			return false
		persistent = _compose_persistent(profile_result.payload, settings_result)
		return true

	if profile_result.code != &"NOT_FOUND":
		return false
	if FileAccess.file_exists(save_path):
		return _import_legacy_persistent()
	if settings_result.ok:
		persistent = _compose_persistent({}, settings_result)
		return true
	if settings_result.code == &"NOT_FOUND":
		persistent = _default_persistent_data()
	return false


func save_persistent() -> bool:
	if profile_runtime_service() != null:
		return false
	var service_result = _ensure_save_service()
	if not service_result.ok:
		return false
	var snapshot := persistent.duplicate(true)
	var settings_value: Variant = snapshot.get("settings", {})
	var settings := settings_value as Dictionary if settings_value is Dictionary else {}
	snapshot.erase("settings")
	var settings_result = _save_service.save_settings(_settings_payload(settings))
	if not settings_result.ok:
		return false
	var profile_result = _save_service.save_profile(
		DEFAULT_PROFILE_ID,
		DEFAULT_SAVE_DOMAIN,
		snapshot
	)
	return profile_result.ok


func reset_persistent_data(delete_file: bool = false) -> void:
	if profile_runtime_service() != null:
		return
	persistent = _default_persistent_data()
	if not delete_file:
		return
	var service_result = _ensure_save_service()
	if service_result.ok:
		_save_service.reset_profile(DEFAULT_PROFILE_ID, DEFAULT_SAVE_DOMAIN)
		var default_settings := _settings_payload(persistent["settings"])
		for _generation: int in range(3):
			_save_service.save_settings(default_settings)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _ensure_save_service():
	if save_path.is_empty():
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {"field": "save_path", "reason": "invalid_data_directory"})
	if _save_service != null and _save_service_path == save_path:
		return SaveResultScript.success()
	var service = SaveServiceScript.new()
	var configured = service.configure(
		_save_service_root_path(),
		SAVE_GAME_VERSION,
		_base_content_snapshot()
	)
	if not configured.ok:
		return configured
	_save_service = service
	_save_service_path = save_path
	_profile_runtime = null
	_profile_catalog = null
	_content_binding.clear()
	return configured


func _import_legacy_persistent() -> bool:
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var legacy_bytes := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return false
	var parsed: Variant = JSON.parse_string(legacy_bytes)
	if not parsed is Dictionary:
		return false

	var registry = SaveMigrationRegistryScript.new()
	var migration = registry.migrate(parsed, SaveEnvelopeScript.META_PROFILE_SCHEMA_VERSION if _profile_catalog != null else SaveEnvelopeScript.SCHEMA_VERSION, {
		"profile_id": DEFAULT_PROFILE_ID,
		"save_domain": DEFAULT_SAVE_DOMAIN,
		"meta_catalog": _profile_catalog,
	})
	if not migration.ok:
		return false
	var migration_document: Dictionary = migration.payload
	var profile_value: Variant = migration_document.get("payload", {})
	var settings_value: Variant = migration.metadata.get("settings_payload", {})
	if not profile_value is Dictionary or not settings_value is Dictionary:
		return false
	var profile_payload: Dictionary = profile_value
	var settings_payload := _settings_payload(settings_value)

	var settings_save = _save_service.save_settings(settings_payload)
	if not settings_save.ok:
		return false
	var profile_save = _save_service.save_profile(
		DEFAULT_PROFILE_ID,
		DEFAULT_SAVE_DOMAIN,
		profile_payload
	)
	if not profile_save.ok:
		return false
	persistent = _compose_persistent_values(profile_payload, settings_payload)
	return true


func _compose_persistent(profile_payload: Dictionary, settings_result) -> Dictionary:
	var settings_payload := _default_settings_payload()
	if settings_result.ok:
		settings_payload = _settings_payload(settings_result.payload)
	return _compose_persistent_values(profile_payload, settings_payload)


func _compose_persistent_values(profile_payload: Dictionary, settings_payload: Dictionary) -> Dictionary:
	var merged := _merge_persistent_defaults(_default_persistent_data(), profile_payload)
	merged["settings"] = _merge_persistent_defaults(_default_settings_payload(), settings_payload)
	return merged


func _settings_payload(settings: Dictionary) -> Dictionary:
	var normalized := _default_settings_payload()
	for setting_id: String in SETTING_IDS:
		if settings.has(setting_id):
			normalized[setting_id] = settings[setting_id]
	return normalized


func _default_settings_payload() -> Dictionary:
	return DEFAULT_SETTINGS.duplicate(true)


func _base_content_snapshot() -> Dictionary:
	var registry := ContentRegistryScript.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], SAVE_GAME_VERSION, &"M1")
	return {} if report.has_blocking_errors() else ContentSnapshotScript.snapshot(registry)


func _legacy_content_snapshot() -> Dictionary:
	var packs: Array = [{
		"pack_id": "base",
		"pack_version": SAVE_GAME_VERSION,
		"schema_version": 1,
		"fingerprint_sha256": "1".repeat(64),
	}]
	return {
		"aggregate_sha256": SaveEnvelopeScript.content_snapshot_digest(packs),
		"packs": packs,
	}


func _save_service_root_path() -> String:
	return save_path.get_base_dir().path_join("plane_walker").path_join("save")


func record_run_summary(result: Dictionary) -> bool:
	if profile_runtime_service() != null:
		return false
	var rooms_cleared := int(result.get("rooms_cleared", 0))
	persistent["runs_completed"] = int(persistent.get("runs_completed", 0)) + 1
	persistent["best_rooms_cleared"] = maxi(int(persistent.get("best_rooms_cleared", 0)), rooms_cleared)
	if str(result.get("result", "")) == "floor_cleared":
		persistent["victories"] = int(persistent.get("victories", 0)) + 1
	persistent["last_run_summary"] = {
		"result": result.get("result", ""),
		"floor": result.get("floor", 1),
		"rooms_cleared": rooms_cleared,
		"current_room": result.get("current_room", 0),
		"run_time": result.get("run_time", 0.0),
		"kills": result.get("kills", 0),
		"rewards": result.get("rewards", []).duplicate(true),
		"blessings": result.get("blessings", []).duplicate(true),
		"talent_choices": result.get("talent_choices", []).duplicate(true),
		"curses": result.get("curses", []).duplicate(true),
	}
	return save_persistent()


func _default_persistent_data() -> Dictionary:
	return {
		"chronos_shards": 0,
		"existential_imprints": 0,
		"unlocked_nodes": [],
		"discovered_items": [],
		"unlocked_characters": [],
		"unlocked_weapons": [],
		"weapon_proficiency": {},
		"npc_affinity": {},
		"unlocked_achievements": [],
		"cosmetics": {},
		"settings": _default_settings_payload(),
		"runs_completed": 0,
		"victories": 0,
		"best_rooms_cleared": 0,
		"last_run_summary": {},
		"active_item_state": SaveEnvelopeScript.empty_active_item_state(),
		"reward_effect_state": {},
		"active_run_state": {},
	}


func _merge_persistent_defaults(defaults: Dictionary, loaded: Dictionary) -> Dictionary:
	var merged := defaults.duplicate(true)
	for key: Variant in loaded.keys():
		if typeof(loaded[key]) == TYPE_DICTIONARY and typeof(merged.get(key)) == TYPE_DICTIONARY:
			merged[key] = _merge_persistent_defaults(merged[key], loaded[key])
		else:
			merged[key] = loaded[key]
	return merged
