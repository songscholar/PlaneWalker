class_name LaunchHostileIds
extends RefCounted

const ENEMY_FLOORS := {
	"shattered_sentinel": 1, "corrosive_moth": 1, "stone_shell_strider": 1, "ruins_wraith": 1, "rift_watcher": 1,
	"void_hunter": 2, "void_archer": 2, "bramble_mage": 2, "void_spore": 2, "forest_caller": 2, "shadow_lurker": 2,
	"chrono_guard": 3, "rift_weaver": 3, "blink_striker": 3, "rewind_priest": 3, "chrono_storm_elemental": 3, "eternal_hound": 3,
	"forge_titan": 4, "void_web_weaver": 4, "phase_ranger": 4, "chaos_amalgam": 4, "plane_ripper": 4,
}
const BOSS_IDS: Array[String] = ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]
const AFFIX_IDS: Array[String] = ["frenzy", "fortified", "regenerating", "teleporting", "splitting", "shielded", "nullified", "anchored", "chaining", "mirroring"]
const SUMMON_IDS: Array[String] = ["mini_wraith", "small_void_spore", "void_firefly", "void_beetle", "hunter_echo", "ranger_echo", "timeline_echo", "void_sapling", "elite_mirror"]
const FLOOR_IDS: Array[String] = ["floor_ruins_of_remnant", "floor_void_forest", "floor_time_rift", "floor_plane_forge", "floor_throne_of_void"]
const PROFILE_IDS: Array[String] = ["encounter_profile_ruins_adapter_v1", "encounter_profile_forest_adapter_v1", "encounter_profile_rift_adapter_v1", "encounter_profile_forge_adapter_v1", "encounter_profile_throne_adapter_v1"]
const BOSS_ENCOUNTER_IDS: Array[String] = ["boss_encounter_ruin_king_adapter_v1", "boss_encounter_forest_heart_adapter_v1", "boss_encounter_time_sovereign_adapter_v1", "boss_encounter_forge_colossus_adapter_v1", "boss_encounter_void_throne_adapter_v1"]


static func enemy_ids() -> Array[String]:
	var result: Array[String] = []
	for key: String in ENEMY_FLOORS:
		result.append(key)
	return result
