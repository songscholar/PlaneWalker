class_name SaveMigrationV0ToV1
extends RefCounted

const SaveResultScript := preload("res://scripts/save/save_result.gd")

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


func migrate(document: Dictionary, _context: Dictionary = {}):
	if (
		document.has("magic")
		or document.has("schema_version")
		or not _is_legacy_version(document.get("version"))
		or int(document.get("version", 0)) != 1
		or not document.get("persistent") is Dictionary
	):
		return SaveResultScript.failure(&"MIGRATION_FAILED", {
			"from_version": 0,
			"to_version": 1,
			"reason": "invalid_legacy_v0_document",
		})

	var profile_payload: Dictionary = (document["persistent"] as Dictionary).duplicate(true)
	var legacy_settings: Variant = profile_payload.get("settings", {})
	if not legacy_settings is Dictionary:
		return SaveResultScript.failure(&"MIGRATION_FAILED", {
			"from_version": 0,
			"to_version": 1,
			"reason": "legacy_settings_must_be_dictionary",
		})
	profile_payload.erase("settings")

	var settings_payload := DEFAULT_SETTINGS.duplicate(true)
	for setting_id: String in DEFAULT_SETTINGS.keys():
		if (legacy_settings as Dictionary).has(setting_id):
			settings_payload[setting_id] = _deep_copy((legacy_settings as Dictionary)[setting_id])

	return SaveResultScript.success(
		{
			"schema_version": 1,
			"payload": profile_payload,
		},
		{
			"legacy_version": int(document["version"]),
			"settings_payload": settings_payload,
		}
	)


static func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


static func _is_legacy_version(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) == 1
	if typeof(value) == TYPE_FLOAT:
		return float(value) == 1.0
	return false
