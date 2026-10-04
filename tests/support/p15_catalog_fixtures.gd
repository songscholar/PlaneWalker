extends RefCounted

const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const EncounterFixtures := preload("res://tests/support/p15_encounter_fixtures.gd")
const THREAT_COSTS := {
	"shattered_sentinel": 1, "corrosive_moth": 1, "stone_shell_strider": 2, "ruins_wraith": 2, "rift_watcher": 2,
	"void_hunter": 2, "void_archer": 2, "bramble_mage": 3, "void_spore": 1, "forest_caller": 4, "shadow_lurker": 3,
	"chrono_guard": 3, "rift_weaver": 4, "blink_striker": 3, "rewind_priest": 4, "chrono_storm_elemental": 4, "eternal_hound": 3,
	"forge_titan": 4, "void_web_weaver": 5, "phase_ranger": 3, "chaos_amalgam": 5, "plane_ripper": 5,
}
const ROSTERS := [
	[
		["sentinel_line", ["shattered_sentinel", "shattered_sentinel", "shattered_sentinel"]],
		["watcher_guard", ["shattered_sentinel", "shattered_sentinel", "rift_watcher"]],
		["moth_crossfire", ["corrosive_moth", "corrosive_moth", "shattered_sentinel"]],
		["wraith_shell", ["ruins_wraith", "stone_shell_strider"]],
		["ruin_full", ["shattered_sentinel", "shattered_sentinel", "corrosive_moth", "rift_watcher"]],
		["sentinel_trial", ["shattered_sentinel", "shattered_sentinel"]],
		["shell_trial", ["stone_shell_strider", "shattered_sentinel"]],
		["watcher_trial", ["rift_watcher", "shattered_sentinel"]],
	],
	[
		["hunter_archer", ["void_hunter", "void_hunter", "void_archer"]],
		["bramble_spores", ["bramble_mage", "void_spore", "void_spore", "void_spore"]],
		["caller_archer", ["forest_caller", "void_archer"]],
		["lurker_hunter", ["shadow_lurker", "void_hunter"]],
		["forest_full", ["void_hunter", "void_archer", "bramble_mage", "void_spore", "void_spore"]],
		["hunter_trial", ["void_hunter", "void_archer"]],
		["bramble_trial", ["bramble_mage", "void_spore"]],
		["caller_trial", ["forest_caller", "void_spore"]],
	],
	[
		["guard_priest", ["chrono_guard", "rewind_priest"]],
		["weaver_blink", ["rift_weaver", "blink_striker"]],
		["hound_pack", ["eternal_hound", "eternal_hound", "eternal_hound"]],
		["storm_archer", ["chrono_storm_elemental", "void_archer", "void_archer"]],
		["rift_full", ["chrono_guard", "rift_weaver", "blink_striker"]],
		["guard_trial", ["chrono_guard", "void_archer"]],
		["blink_trial", ["blink_striker", "rift_weaver"]],
		["storm_trial", ["chrono_storm_elemental", "void_archer"]],
	],
	[
		["titan_ranger", ["forge_titan", "phase_ranger"]],
		["web_titan", ["void_web_weaver", "forge_titan"]],
		["chaos_crossfire", ["chaos_amalgam", "void_archer"]],
		["ripper_pack", ["plane_ripper", "void_hunter", "void_hunter"]],
		["forge_full", ["forge_titan", "phase_ranger", "void_web_weaver"]],
		["titan_trial", ["forge_titan", "phase_ranger"]],
		["chaos_trial", ["chaos_amalgam", "void_archer"]],
		["ripper_trial", ["plane_ripper", "void_hunter"]],
	],
	[
		["throne_front", ["chrono_guard", "forge_titan"]],
		["throne_lanes", ["phase_ranger", "void_archer", "void_archer"]],
		["throne_mirror", ["chaos_amalgam", "blink_striker"]],
		["throne_space", ["plane_ripper", "rift_weaver"]],
		["throne_guard", ["chrono_guard", "void_web_weaver", "rewind_priest"]],
		["throne_titan_trial", ["forge_titan", "chrono_guard"]],
		["throne_chaos_trial", ["chaos_amalgam", "blink_striker"]],
		["throne_blink_trial", ["blink_striker", "chrono_guard"]],
	],
]


class RegistryFixture extends RefCounted:
	var rows: Dictionary = {}

	func get_by_category(category: StringName, _availability: StringName = &"") -> Array:
		return rows.get(str(category), []).duplicate(true)

	func get_content(content_id: StringName) -> Dictionary:
		for category_rows: Array in rows.values():
			for row: Dictionary in category_rows:
				if row.id == str(content_id):
					return row.duplicate(true)
		return {}


static func registry() -> RefCounted:
	var result := RegistryFixture.new()
	var enemies: Array[Dictionary] = []
	var bosses: Array[Dictionary] = []
	var affixes: Array[Dictionary] = []
	var profiles: Array[Dictionary] = []
	for enemy_id: String in Ids.enemy_ids():
		enemies.append({"id": enemy_id, "category": "enemy_definition", "scene": "assets/enemies/launch/enemy_%s.tscn" % enemy_id, "threat_cost": THREAT_COSTS[enemy_id], "floor_index": Ids.ENEMY_FLOORS[enemy_id]})
	for boss_id: String in Ids.BOSS_IDS:
		bosses.append({"id": boss_id, "category": "boss_definition", "scene": "assets/bosses/launch/boss_%s.tscn" % boss_id, "floor_index": Ids.BOSS_IDS.find(boss_id) + 1})
	for affix_id: String in Ids.AFFIX_IDS:
		affixes.append({"id": affix_id, "category": "elite_affix_definition"})
	for floor_index: int in range(5):
		profiles.append(profile(floor_index))
	result.rows = {
		"enemy_definition": enemies, "boss_definition": bosses, "elite_affix_definition": affixes,
		"launch_encounter_profile": profiles,
		"room_template": [
			{"id": "room_combat_open_field", "category": "room_template", "room_type": "combat"},
			{"id": "room_combat_split_chambers", "category": "room_template", "room_type": "combat"},
			{"id": "room_elite_arena", "category": "room_template", "room_type": "elite"},
		],
	}
	return result


static func profile(floor_index: int) -> Dictionary:
	var recipes: Array[Dictionary] = []
	var references: Array[String] = [Ids.BOSS_IDS[floor_index]]
	var budget: int = [6, 8, 9, 10, 11][floor_index]
	for index: int in range(8):
		var recipe_id: String = ROSTERS[floor_index][index][0]
		var elite := index >= 5
		var wave_spawns: Array[Dictionary] = []
		var waves: Array[Dictionary] = []
		var wave_threat := 0
		for ordinal: int in range(ROSTERS[floor_index][index][1].size()):
			var enemy_id: String = ROSTERS[floor_index][index][1][ordinal]
			if not references.has(enemy_id):
				references.append(enemy_id)
			var is_elite := elite and ordinal == 0
			var cost: int = THREAT_COSTS[enemy_id] + (3 if is_elite else 0)
			if not wave_spawns.is_empty() and wave_threat + cost > budget + (3 if elite else 0):
				waves.append(_wave(recipe_id, waves.size(), wave_spawns, floor_index))
				wave_spawns = []
				wave_threat = 0
			var spawn := EncounterFixtures.spawn("%s_spawn_%d" % [recipe_id, ordinal + 1])
			spawn.enemy_id = enemy_id
			spawn.elite = is_elite
			spawn.affix_ids = (["frenzy"] if floor_index < 2 else ["frenzy", "chaining"]) if is_elite else []
			spawn.spawn_offset = {"x": float((wave_spawns.size() % 3 - 1) * 64), "y": float((wave_spawns.size() / 3) * 64)}
			wave_spawns.append(spawn)
			wave_threat += cost
		waves.append(_wave(recipe_id, waves.size(), wave_spawns, floor_index))
		recipes.append({
			"id": recipe_id, "room_type": "elite" if elite else "combat",
			"template_ids": ["room_elite_arena"] if elite else ["room_combat_split_chambers" if index == 4 else "room_combat_open_field"],
			"threat_budget": budget + (3 if elite else 0), "waves": waves,
		})
	references.sort()
	return {
		"category": "launch_encounter_profile", "id": Ids.PROFILE_IDS[floor_index], "schema_version": 1,
		"name_key": "P15_PROFILE_%d_NAME" % floor_index, "description_key": "P15_PROFILE_%d_DESC" % floor_index,
		"availability": ["LAUNCH", "EXPANSION"], "tags": ["launch_hostile"], "compatibility": {}, "references": references,
		"floor_id": Ids.FLOOR_IDS[floor_index], "boss_id": Ids.BOSS_IDS[floor_index], "boss_encounter_id": Ids.BOSS_ENCOUNTER_IDS[floor_index], "recipes": recipes,
	}


static func _wave(recipe_id: String, index: int, spawns: Array, floor_index: int) -> Dictionary:
	return {"id": "%s_wave_%d" % [recipe_id, index + 1], "delay_frames": 0 if index == 0 else 15, "warning_frames": 30 if floor_index == 0 else 23, "spawns": spawns.duplicate(true)}
