extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Catalog := preload("res://scripts/presentation/ui_art_catalog.gd")
const Events := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const ChallengeRewards := preload("res://scripts/progression/challenge_reward_catalog.gd")

const REQUIRED := {
	"weapons": ["sword", "bow", "gun", "staff", "gauntlets"],
	"time_abilities": ["stop", "rewind", "accelerate", "rift"],
	"player_effects": ["weapon_arc", "arrow_trail", "muzzle_flash", "spell_burst", "time_ring", "rift_bloom"],
	"player_projectiles": ["arrow", "bullet", "staff_arcane", "staff_fire", "staff_ice", "staff_lightning"],
	"held_weapons": ["sword", "bow", "gun", "gauntlets", "staff_arcane", "staff_fire", "staff_ice", "staff_lightning"],
	"room_types": ["entry", "unknown", "combat", "elite", "treasure", "shop", "event", "boss", "rest"],
	"event_art": Events.EVENT_IDS,
	"npc_portraits": ["odysseus", "elara", "sibyl", "hermes", "phia", "morpheus", "nemesis", "vera"],
	"ending_art": ["return_of_order", "embrace_of_void", "balance_of_ashes", "shattered_freedom", "echo_of_primordial"],
	"challenge_rewards": ChallengeRewards.IDS,
	"controls": ["decline_contract", "play", "pause", "copy", "paste", "export", "delete", "back", "settings", "bindings", "restart", "quit", "build", "import", "refresh", "next", "screenshot", "account", "storage", "community", "content", "sharing"],
	"mode_art": ["boss_rush", "daily_boss", "authored_challenges", "training", "endless"],
	"final_ui_frames": ["panel", "panel_active", "panel_danger", "divider", "badge", "cursor", "chrome_panel", "chrome_button", "chrome_focus"],
}
const CONTENT_BATCHES := ["items", "blessings", "curses", "talents"]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var report: Dictionary = Catalog.validate()
	suite.assert_true(bool(report.get("ok", false)), "pixel asset catalog validates generated slice")
	suite.assert_true((report.get("errors", []) as Array).is_empty(), "pixel asset catalog has no errors")
	var inventory: Dictionary = Catalog.load_inventory()
	suite.assert_equal(inventory.get("contact_sheet"), "pixel_asset_contact_sheet.png", "inventory keeps the contact sheet")
	suite.assert_true(FileAccess.file_exists("res://assets/production/ui/pixel_asset_contact_sheet.png"), "pixel asset contact sheet exists")
	for batch_id: String in REQUIRED:
		for asset_id: String in REQUIRED[batch_id]:
			var row := Catalog.asset(StringName(batch_id), StringName(asset_id))
			suite.assert_true(not row.is_empty(), "%s/%s is declared" % [batch_id, asset_id])
			var path := Catalog.texture_path(StringName(batch_id), StringName(asset_id))
			suite.assert_true(FileAccess.file_exists(path), "%s/%s texture path resolves" % [batch_id, asset_id])
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			suite.assert_true(image != null and not image.is_empty(), "%s/%s raster loads" % [batch_id, asset_id])
			if image == null or image.is_empty():
				continue
			var expected_size: Vector2i = {"event_art": Vector2i(96, 64), "npc_portraits": Vector2i(64, 64), "ending_art": Vector2i(128, 72)}.get(batch_id, Vector2i(32, 32))
			suite.assert_equal(image.get_width(), expected_size.x * 4, "%s/%s has four authored frames" % [batch_id, asset_id])
			suite.assert_equal(image.get_height(), expected_size.y, "%s/%s keeps the authored frame height" % [batch_id, asset_id])
			var imported := load(path) as Texture2D
			suite.assert_true(imported != null and imported.get_size() == Vector2(image.get_size()), "%s/%s imports exact raster dimensions" % [batch_id, asset_id])
			suite.assert_equal(FileAccess.get_sha256(path), str(row.get("sha256", "")), "%s/%s hash is stable" % [batch_id, asset_id])
		var missing := Catalog.asset(StringName(batch_id), &"missing")
		suite.assert_true(missing.is_empty(), "%s rejects undeclared asset ids" % batch_id)
	for batch_id: String in CONTENT_BATCHES:
		var found: Dictionary = {}
		for batch_value: Variant in inventory.get("batches", []):
			if batch_value is Dictionary and str(batch_value.get("id", "")) == batch_id:
				found = (batch_value as Dictionary)
				break
		suite.assert_equal(found.get("status", ""), "generated", "%s content icons are generated" % batch_id)
		suite.assert_true((found.get("assets", []) as Array).size() > 0, "%s content icon batch is non-empty" % batch_id)
	for batch_id: String in ["actors", "enemies", "rooms"]:
		for batch_value: Variant in inventory.get("batches", []):
			if not batch_value is Dictionary or str(batch_value.get("id", "")) != batch_id:
				continue
			for row: Dictionary in batch_value.get("assets", []):
				var path := Catalog.texture_path(StringName(batch_id), StringName(row.id))
				suite.assert_true(FileAccess.file_exists(path), "existing world atlas resolves outside UI directory: " + path)
				suite.assert_equal(FileAccess.get_sha256(path), row.sha256, "existing world atlas is authenticated: " + path)
	var glyph_families: Dictionary = {}
	for batch_id: String in CONTENT_BATCHES + ["mode_art"]:
		for batch_value: Variant in inventory.get("batches", []):
			if not batch_value is Dictionary or str(batch_value.get("id", "")) != batch_id:
				continue
			for asset_value: Variant in batch_value.get("assets", []):
				if asset_value is Dictionary and asset_value.has("glyph_family"):
					glyph_families[int(asset_value.glyph_family)] = true
	suite.assert_true(glyph_families.size() >= 12, "content and mode icon batches expose twelve semantic glyph families")
	var font_batch: Dictionary = {}
	for batch_value: Variant in inventory.get("batches", []):
		if batch_value is Dictionary and str(batch_value.get("id", "")) == "font":
			font_batch = batch_value
			break
	suite.assert_equal(font_batch.get("status", ""), "vendored", "font batch is bundled for offline distribution")
	for font_id: String in ["noto_sans_sc_regular", "pixelify_sans_regular"]:
		var font := load(Catalog.texture_path(&"font", StringName(font_id))) as Font
		suite.assert_true(font != null and font.has_char(65), "bundled font covers Latin text: " + font_id)
		if font != null and font_id == "noto_sans_sc_regular":
			suite.assert_true(font.has_char(0x65F6) and font.has_char(0x7A7A), "bundled body font covers Chinese time and space glyphs")
	suite.finish(get_tree())
