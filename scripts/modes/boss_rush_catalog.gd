extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Encounters := preload("res://scripts/dungeon/launch_encounter_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const SOURCE := "res://assets/production/modes/boss_rush.json"
const BOSSES := ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]

var _definition: Dictionary = {}
var _stages: Array = []


func configure(registry: RefCounted, carried: bool = false) -> bool:
	if not registry is Registry:
		return false
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not Catalog.exact_fields(source, ["schema_version", "mode_id", "name_key", "preset", "stages"]) or source.schema_version != 1 or source.mode_id != "boss_rush" or source.name_key != "UI_MODE_BOSS_RUSH" or source.preset != "fresh_stage" or not source.stages is Array or source.stages.size() != 5:
		return false
	var encounters := Encounters.new()
	if not encounters.configure(registry).ok:
		return false
	var bosses: Dictionary = {}
	for id: String in BOSSES:
		bosses[id] = encounters.enemy_definition(id)
	var stages: Array = []
	for index: int in range(5):
		var row: Variant = source.stages[index]
		if not Catalog.exact_fields(row, ["boss_id", "room_template_id"]) or row.boss_id != BOSSES[index] or not bosses.has(row.boss_id):
			return false
		var definition: Dictionary = {}
		for field: String in Definition.FIELDS:
			if not bosses[row.boss_id].has(field):
				return false
			definition[field] = bosses[row.boss_id][field]
		var parsed := Definition.new()
		var template: Dictionary = registry.resolve_room_template(StringName(row.room_template_id))
		template.erase("pack_id")
		template.erase("pack_version")
		if not parsed.configure(definition).ok or template.get("room_type") != "boss" or not ResourceLoader.exists(str(template.get("scene_path", ""))) or not ResourceLoader.exists(str(bosses[row.boss_id].get("scene", ""))):
			return false
		var projection := parsed.runtime_projection()
		if carried:
			var scaled := Definition.difficulty_projection(projection, 1.2, 1.1)
			if not scaled.ok:
				return false
			projection = scaled.definition
		stages.append({"boss_id": row.boss_id, "boss_scene": bosses[row.boss_id].scene, "runtime_definition": projection, "template": template})
	_definition = source.duplicate(true)
	if carried:
		_definition.preset = "carried"
		_definition["rules"] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/production/modes/boss_rush_carried.json"))
	_stages = stages
	return true


func fingerprint() -> String:
	return Rules.canonical(_definition).sha256_text()


func stage(index: int) -> Dictionary:
	return _stages[index].duplicate(true) if index >= 0 and index < _stages.size() else {}


static func valid_request(value: Variant) -> bool:
	if not Catalog.exact_fields(value, ["character_id", "weapon_id", "time_abilities", "seed", "accessibility_assists"]) or value.character_id not in Catalog.CHARACTER_IDS or value.weapon_id not in Catalog.WEAPON_IDS or not Catalog.bounded_int(value.seed, 0, Catalog.MAX_VALUE) or not value.time_abilities is Array or value.time_abilities.size() != 2 or value.time_abilities[0] not in Catalog.TIME_IDS or value.time_abilities[1] not in Catalog.TIME_IDS or value.time_abilities[0] == value.time_abilities[1] or not Catalog.exact_fields(value.accessibility_assists, ["damage_received_multiplier", "enemy_telegraph_scale"]):
		return false
	return value.accessibility_assists.damage_received_multiplier in [1.0, 0.8, 0.6] and value.accessibility_assists.enemy_telegraph_scale in [1.0, 1.25, 1.5]


static func empty_session(fingerprint_value: String) -> Dictionary:
	return {"schema_version": 1, "mode_fingerprint": fingerprint_value, "session_sequence": 0, "run_id": "", "request": {}, "stage_index": 0, "status": "IDLE", "elapsed_frames": 0, "completed_stages": [], "continued": false}


static func valid_session(value: Variant, fingerprint_value: String, profile_id: String) -> bool:
	if not Catalog.exact_fields(value, ["schema_version", "mode_fingerprint", "session_sequence", "run_id", "request", "stage_index", "status", "elapsed_frames", "completed_stages", "continued"]) or value.schema_version != 1 or value.mode_fingerprint != fingerprint_value or not Catalog.bounded_int(value.session_sequence, 0, Catalog.MAX_VALUE) or not Catalog.bounded_int(value.stage_index, 0, 4) or value.status not in ["IDLE", "ACTIVE", "STAGE_CLEAR", "VICTORY", "DEFEAT"] or not Catalog.bounded_int(value.elapsed_frames, 0, Catalog.MAX_VALUE) or not value.completed_stages is Array or value.completed_stages.size() > 5 or not value.continued is bool:
		return false
	if value.status == "IDLE":
		return Rules.same(value, empty_session(fingerprint_value))
	if value.session_sequence < 1 or value.run_id != "boss-rush-%s-%d" % [profile_id, int(value.session_sequence)] or not valid_request(value.request):
		return false
	var total := 0
	for index: int in range(value.completed_stages.size()):
		var row: Variant = value.completed_stages[index]
		var stage_run := "%s-stage-%d" % [value.run_id, index + 1]
		var source := "rush-%s" % stage_run.sha256_text().substr(0, 40)
		if not Catalog.exact_fields(row, ["stage_index", "boss_id", "run_id", "hostile_source_id", "death_receipt", "frames", "native_digest"]) or row.stage_index != index or row.boss_id != BOSSES[index] or row.run_id != stage_run or row.hostile_source_id != source or row.death_receipt != "hostile_defeat:%s" % (stage_run + "|" + source).sha256_text().substr(0, 40) or not Catalog.bounded_int(row.frames, 1, Catalog.MAX_VALUE) or not Catalog.fingerprint_valid(row.native_digest):
			return false
		total += int(row.frames)
	if total > value.elapsed_frames:
		return false
	var expected: int = int(value.stage_index) + (1 if value.status in ["STAGE_CLEAR", "VICTORY"] else 0)
	return value.completed_stages.size() == expected and (value.status != "VICTORY" or value.stage_index == 4) and (value.status != "STAGE_CLEAR" or value.stage_index < 4)
