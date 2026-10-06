class_name UiArtCatalog
extends RefCounted

const INVENTORY_PATH := "res://assets/production/ui/pixel_asset_inventory.json"
const ROOT_PATH := "res://assets/production/ui/"
const REQUIRED_GENERATED := {
	"weapons": ["sword", "bow", "gun", "staff", "gauntlets"],
	"time_abilities": ["stop", "rewind", "accelerate", "rift"],
	"player_effects": ["weapon_arc", "arrow_trail", "muzzle_flash", "spell_burst", "time_ring", "rift_bloom"],
}


static func load_inventory() -> Dictionary:
	if not FileAccess.file_exists(INVENTORY_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY_PATH))
	return parsed if parsed is Dictionary else {}


static func asset(batch_id: StringName, asset_id: StringName) -> Dictionary:
	var inventory := load_inventory()
	for batch_value: Variant in inventory.get("batches", []):
		if not batch_value is Dictionary or str(batch_value.get("id", "")) != str(batch_id):
			continue
		for asset_value: Variant in batch_value.get("assets", []):
			if asset_value is Dictionary and str(asset_value.get("id", "")) == str(asset_id):
				return (asset_value as Dictionary).duplicate(true)
	return {}


static func texture_path(batch_id: StringName, asset_id: StringName) -> String:
	var value := asset(batch_id, asset_id)
	if value.is_empty():
		return ""
	return ROOT_PATH + str(value.get("path", ""))


static func validate() -> Dictionary:
	var errors: Array[String] = []
	var inventory := load_inventory()
	if inventory.is_empty():
		errors.append("pixel asset inventory is missing or invalid")
		return {"ok": false, "errors": errors}
	if str(inventory.get("schema_id", "")) != "plane_walker_pixel_asset_inventory_v1":
		errors.append("pixel asset inventory schema id is not recognized")
	if inventory.get("nearest_filter", false) != true:
		errors.append("pixel asset inventory does not require nearest filtering")
	for batch_id: String in REQUIRED_GENERATED:
		for asset_id: String in REQUIRED_GENERATED[batch_id]:
			var value := asset(StringName(batch_id), StringName(asset_id))
			if value.is_empty():
				errors.append("missing asset %s/%s" % [batch_id, asset_id])
				continue
			if str(value.get("filter", "")) != "nearest":
				errors.append("asset %s/%s is not nearest filtered" % [batch_id, asset_id])
			var path := ROOT_PATH + str(value.get("path", ""))
			if not FileAccess.file_exists(path):
				errors.append("asset path does not exist: %s" % path)
				continue
			var digest := FileAccess.get_sha256(path)
			if digest != str(value.get("sha256", "")):
				errors.append("asset hash mismatch: %s" % path)
			if int(value.get("frame_width", 0)) != 32 or int(value.get("frame_height", 0)) != 32:
				errors.append("asset frame size is not 32x32: %s" % path)
	return {"ok": errors.is_empty(), "errors": errors, "inventory": inventory}
