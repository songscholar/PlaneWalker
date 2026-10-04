extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")


func _ready() -> void:
	var suite := Suite.new()
	var codec := load("res://scripts/progression/build_share_codec.gd") as Script
	suite.assert_true(codec != null, "portable build share codec exists")
	if codec != null:
		var count := 0
		for character: String in Catalog.CHARACTER_IDS:
			for weapon: String in Catalog.WEAPON_IDS:
				for first: int in range(4):
					for second: int in range(first + 1, 4):
						var build := {"id": "sender", "name": "Loadout", "character_id": character, "weapon_id": weapon, "time_abilities": [Catalog.TIME_IDS[second], Catalog.TIME_IDS[first]]}
						var before := build.duplicate(true)
						var encoded: Dictionary = codec.encode(build)
						suite.assert_equal(build, before, "export leaves caller-owned build unchanged")
						suite.assert_true(encoded.ok, "every canonical loadout exports")
						if not encoded.ok:
							continue
						var decoded: Dictionary = codec.decode(encoded.context.share_code)
						suite.assert_true(decoded.ok, "every canonical loadout imports")
						if not decoded.ok:
							continue
						build.time_abilities.sort()
						build.id = decoded.context.build.id
						suite.assert_equal(decoded.context.build, build, "codec retains exact portable loadout")
						suite.assert_equal(codec.encode(decoded.context.build), encoded, "re-export is canonical and independent from sender ID")
						count += 1
		suite.assert_equal(count, 150, "150 canonical loadouts round-trip")
		var sample := {"id": "sender", "name": String.chr(0x914D) + String.chr(0x88C5), "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
		var encoded: Dictionary = codec.encode(sample)
		var unicode_decoded: Dictionary = codec.decode(encoded.context.share_code) if encoded.ok else {}
		suite.assert_true(unicode_decoded.get("ok", false) and unicode_decoded.context.get("build", {}).get("name") == sample.name, "Unicode names survive UTF-8 serialization")
		if encoded.ok:
			var code: String = encoded.context.share_code
			var parts := code.split(".")
			suite.assert_true(not codec.decode(code.left(-1) + ("0" if code.right(1) != "0" else "1")).ok, "changed checksum refuses")
			suite.assert_true(not codec.decode("PW2." + parts[1] + "." + parts[2]).ok, "unknown envelope version refuses")
			var payload: Dictionary = JSON.parse_string(Marshalls.base64_to_utf8(parts[1]))
			payload.schema_version = 1
			payload["currency"] = 1000
			suite.assert_true(not codec.decode(_code(payload)).ok, "extra progress fields refuse even with valid checksum")
			payload.erase("currency")
			payload.schema_version = true
			suite.assert_true(not codec.decode(_code(payload)).ok, "Boolean schema is invalid")
			payload.schema_version = 1
			payload.time_abilities = ["stop", "stop"]
			suite.assert_true(not codec.decode(_code(payload)).ok, "duplicate time pair refuses")
			payload.time_abilities = ["stop", "rewind"]
			suite.assert_true(not codec.decode(_code(payload)).ok, "unsorted noncanonical pair refuses")
			payload.time_abilities.sort()
			payload.character_id = "locked_unknown"
			suite.assert_true(not codec.decode(_code(payload)).ok, "unknown character refuses")
		for bad: Variant in [null, true, 1, {}, [], "", "PW1.@@@@.1234", "PW1." + "A".repeat(2000), " " + str(encoded.context.get("share_code", ""))]:
			suite.assert_true(not codec.decode(bad).ok, "malformed external value refuses")
		for field: String in ["id", "name", "character_id", "weapon_id", "time_abilities"]:
			var missing := sample.duplicate(true)
			missing.erase(field)
			suite.assert_true(not codec.encode(missing).ok, "missing build field refuses")
		sample.name = " ".repeat(3)
		suite.assert_true(not codec.encode(sample).ok, "blank name refuses")
		sample.name = "A".repeat(65)
		suite.assert_true(not codec.encode(sample).ok, "name is bounded")
	suite.finish(get_tree())


func _code(payload: Dictionary) -> String:
	var json := JSON.stringify(payload, "", true, true)
	return "PW1.%s.%s" % [Marshalls.utf8_to_base64(json), json.sha256_text()]
