class_name UiArtCatalog
extends RefCounted

const INVENTORY_PATH := "res://assets/production/ui/pixel_asset_inventory.json"
const ROOT_PATH := "res://assets/production/ui/"
const Events := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const ChallengeRewards := preload("res://scripts/progression/challenge_reward_catalog.gd")
const REQUIRED_GENERATED := {
	"weapons": ["sword", "bow", "gun", "staff", "gauntlets"],
	"time_abilities": ["stop", "rewind", "accelerate", "rift"],
	"player_effects": ["weapon_arc", "arrow_trail", "muzzle_flash", "spell_burst", "time_ring", "rift_bloom"],
	"player_projectiles": ["arrow", "bullet", "staff_arcane", "staff_fire", "staff_ice", "staff_lightning"],
	"room_types": ["entry", "unknown", "combat", "elite", "treasure", "shop", "event", "boss", "rest"],
	"event_art": Events.EVENT_IDS,
	"npc_portraits": ["odysseus", "elara", "sibyl", "hermes", "phia", "morpheus", "nemesis", "vera"],
	"ending_art": ["return_of_order", "embrace_of_void", "balance_of_ashes", "shattered_freedom", "echo_of_primordial"],
	"challenge_rewards": ChallengeRewards.IDS,
	"controls": ["decline_contract", "play", "pause", "copy", "paste", "export", "delete", "back", "settings", "bindings", "restart", "quit", "build", "import", "refresh", "next", "screenshot", "account", "storage", "community", "content", "sharing"],
	"mode_art": ["boss_rush", "daily_boss", "authored_challenges", "training", "endless"],
	"final_ui_frames": ["panel", "panel_active", "panel_danger", "divider", "badge", "cursor", "chrome_panel", "chrome_button", "chrome_focus"],
}
const REQUIRED_CONTENT_BATCHES := ["items", "blessings", "curses", "talents"]
const FRAME_SIZES := {"event_art": Vector2i(96, 64), "npc_portraits": Vector2i(64, 64), "ending_art": Vector2i(128, 72)}


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
	if value.has("source_manifest"):
		return "res://assets/production/" + str(value.get("path", ""))
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
			var expected_size: Vector2i = FRAME_SIZES.get(batch_id, Vector2i(32, 32))
			if int(value.get("frame_width", 0)) != expected_size.x or int(value.get("frame_height", 0)) != expected_size.y or int(value.get("frame_count", 0)) != 4:
				errors.append("asset frame dimensions or count mismatch: %s" % path)
	for batch_id: String in REQUIRED_CONTENT_BATCHES:
		var found := false
		for batch_value: Variant in inventory.get("batches", []):
			if batch_value is Dictionary and str(batch_value.get("id", "")) == batch_id:
				found = true
				if str(batch_value.get("status", "")) != "generated" or (batch_value.get("assets", []) as Array).is_empty():
					errors.append("content batch is not generated: %s" % batch_id)
				break
		if not found:
			errors.append("missing content batch: %s" % batch_id)
	for font_id: String in ["noto_sans_sc_regular", "pixelify_sans_regular"]:
		var font := asset(&"font", StringName(font_id))
		if font.is_empty():
			errors.append("missing bundled font: %s" % font_id)
			continue
		for path_field: String in ["path", "license_path"]:
			var font_path := ROOT_PATH + str(font.get(path_field, ""))
			var digest_field := "sha256" if path_field == "path" else "license_sha256"
			if not FileAccess.file_exists(font_path) or FileAccess.get_sha256(font_path) != str(font.get(digest_field, "")):
				errors.append("bundled font or license hash mismatch: %s" % font_path)
	return {"ok": errors.is_empty(), "errors": errors, "inventory": inventory}
