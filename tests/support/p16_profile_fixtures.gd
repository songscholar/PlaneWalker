extends RefCounted


static func meta_entries() -> Array:
	var rows := [
		["W-01", 5, [], [_stat("max_hp", 0.02)]],
		["W-02", 10, ["W-01"], [_stat("max_hp", 0.01)]],
		["W-03", 20, ["W-02"], [_stat("max_hp", 0.02)]],
		["W-04", 8, ["W-01"], [_stat("entrance_healing", 0.02)]],
		["W-05", 15, ["W-04"], [_stat("void_reduction", 0.02)]],
		["W-06", 30, ["W-03"], [_option("safe_training_reset"), _option("death_analysis")]],
		["W-07", 10, [], [{"kind": "soul_retention", "value": 0.5}]],
		["W-08", 20, ["W-07"], [{"kind": "soul_retention", "value": 0.7}]],
		["W-09", 5, ["W-05"], [_option("free_hub_rest")]],
		["W-10", 25, ["W-06"], [_option("next_room_content_preview")]],
		["C-01", 5, [], [_stat("attack", 0.02)]],
		["C-02", 12, ["C-01"], [_stat("attack", 0.01)]],
		["C-03", 25, ["C-02"], [_option("archetype_shortlists")]],
		["C-04", 8, [], [_stat("attack_speed", 0.01)]],
		["C-05", 15, ["C-04"], [_stat("attack_speed", 0.01)]],
		["C-06", 20, ["C-04"], [_option("dodge_parry_drill")]],
		["C-07", 15, ["C-05"], [_option("hostile_timing_comparison")]],
		["C-08", 50, ["C-03", "C-06"], [_option("complete_boss_drills")]],
		["L-01", 5, [], [_option("ruins_runes_basic")]],
		["L-02", 10, ["L-01"], [_option("ruins_runes_complete"), _option("rift_runes_basic")]],
		["L-03", 20, ["L-02"], [_option("all_runes_complete")]],
		["L-04", 8, ["L-01"], [_option("hostile_role_preview")]],
		["L-05", 12, ["L-02"], [_option("rift_landmark_hints")]],
		["L-06", 18, ["L-03"], [_option("floor_safety_annotations")]],
		["L-07", 3, [], [_option("cross_linked_archive")]],
		["L-08", 10, ["L-07"], [_option("extra_build_presets")]],
		["L-09", 12, ["L-08"], [{"kind": "hub_discount", "value": 0.1}]],
		["L-10", 40, ["L-06", "L-09"], [_option("floor_content_preview")], 5],
		["F-01", 5, [], [_option("weapon_forging")]],
		["F-02", 10, ["F-01"], [_option("first_enchantment")]],
		["F-03", 20, ["F-02"], [_option("second_enchantment")]],
		["F-04", 25, ["F-02"], [_option("void_temper")]],
		["F-05", 12, ["F-01"], [_option("forge_preference_recall")]],
		["F-06", 30, ["F-03", "F-05"], [_option("enchantment_comparison"), _option("craft_library")]],
		["F-07", 5, [], [_option("basic_recovery_recipes")]],
		["F-08", 15, ["F-07"], [_option("advanced_recovery_recipes")]],
		["P-01", 3, [], [_option("council_missions")]],
		["P-02", 8, ["P-01", "L-01"], [_option("phia_guidance")]],
		["P-03", 15, ["P-01"], [_option("character_drills")]],
		["P-04", 12, ["P-01", "L-09"], [_option("extra_merchant_options"), _option("five_run_gift")]],
		["P-05", 25, ["P-03"], [_option("first_narrative_companion")]],
		["P-06", 40, ["P-05"], [_option("second_narrative_companion")]],
	]
	var entries: Array = []
	for row: Array in rows:
		entries.append({
			"id": row[0], "branch": str(row[0]).left(1),
			"cost": {"chronos_shards": row[1], "existential_imprints": row[4] if row.size() > 4 else 0},
			"prerequisites": row[2], "effects": row[3],
		})
	return entries


static func _stat(stat: String, magnitude: float) -> Dictionary:
	return {"kind": "stat_bonus", "stat": stat, "magnitude": magnitude}


static func _option(id: String) -> Dictionary:
	return {"kind": "option", "option_id": id}
