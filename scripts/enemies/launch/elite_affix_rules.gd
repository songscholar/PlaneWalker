class_name EliteAffixRules
extends RefCounted

const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const MIN_FLOORS := {"frenzy": 1, "fortified": 1, "regenerating": 1, "teleporting": 2, "splitting": 2, "shielded": 2, "nullified": 3, "anchored": 3, "chaining": 3, "mirroring": 4}
const EXCLUSIONS := {
	"frenzy": ["fortified"], "fortified": ["frenzy"],
	"regenerating": ["nullified", "shielded"], "teleporting": ["anchored"],
	"splitting": ["nullified", "mirroring"], "shielded": ["regenerating", "chaining"],
	"nullified": ["regenerating", "splitting"], "anchored": ["teleporting"],
	"chaining": ["shielded"], "mirroring": ["splitting"],
}
const CHILD_OWNER_IDS: Array[String] = ["ruins_wraith", "void_hunter", "void_spore", "forest_caller", "chrono_guard", "eternal_hound", "phase_ranger", "plane_ripper"]


static func legal_for(enemy_id: String, floor_index: int, affix_ids: Array) -> bool:
	if not Ids.ENEMY_FLOORS.has(enemy_id) or floor_index < 1 or floor_index > 5:
		return false
	var seen: Array[String] = []
	for affix_id: Variant in affix_ids:
		if typeof(affix_id) != TYPE_STRING or not MIN_FLOORS.has(affix_id) or floor_index < int(MIN_FLOORS[affix_id]) or seen.has(affix_id):
			return false
		if affix_id in ["splitting", "mirroring"] and CHILD_OWNER_IDS.has(enemy_id):
			return false
		for previous: String in seen:
			if EXCLUSIONS[affix_id].has(previous) or EXCLUSIONS[previous].has(affix_id):
				return false
		seen.append(affix_id)
	return true
