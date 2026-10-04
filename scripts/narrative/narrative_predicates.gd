class_name NarrativePredicates
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const FLOOR_BOSSES := {"floor_ruins_of_remnant": "ruin_king", "floor_void_forest": "forest_heart", "floor_time_rift": "time_sovereign", "floor_plane_forge": "forge_colossus", "floor_throne_of_void": "void_throne"}


static func missing(requirements: Array, profile: Dictionary, content: RefCounted) -> Array:
	var values: Array = []
	for requirement: Dictionary in requirements:
		if not satisfied(requirement, profile, content):
			values.append(requirement.duplicate(true))
	return values


static func satisfied(value: Dictionary, profile: Dictionary, content: RefCounted) -> bool:
	if not content.predicate_valid(value):
		return false
	var narrative: Dictionary = profile.narrative_state
	match value.kind:
		"npc_intro": return narrative.consumed_sources.has("dialogue:" + str(value.id) + "_intro")
		"first_death": return profile.statistics.deaths >= value.value
		"floor_completed": return profile.completed_boss_ids.has(FLOOR_BOSSES[value.id])
		"boss_defeated": return profile.completed_boss_ids.has(value.id)
		"affinity_min": return profile.npc_affinity[value.id] >= value.value
		"npc_depth_read": return depth_read(profile, value.id) >= value.value
		"npc_depth_incomplete": return depth_read(profile, value.id) < value.value
		"record_collected": return narrative.environment_records.has(value.id)
		"artifact_collected": return narrative.artifacts.has(value.id)
		"flag_set": return narrative.flags.has(value.id)
		"hidden_step_complete": return narrative.hidden_steps[value.id] >= value.value
		"phia_markers_min": return _authored_source_count(narrative.consumed_sources, content, "phia_marker") >= value.value
		"related_letter_count_min": return _authored_source_count(narrative.consumed_sources, content, "walker_letter") >= value.value
		"void_exposure_frames_min": return narrative.void_exposure_frames >= value.value
		"nemesis_spared_min": return narrative.nemesis_choices.count("spare") >= value.value
		"vera_conversation_count_min": return narrative.vera_conversations >= value.value
		"heart_fragment_count_min": return narrative.heart_fragments.size() >= value.value
		"balance_choice_count_min": return _balance_sources(profile, content).size() >= value.value
		"all_hidden_lines_complete":
			for id: String in Catalog.HIDDEN_LINE_IDS:
				if narrative.hidden_steps[id] != 5:
					return false
			return true
		"all_npc_affinity_min":
			for id: String in Catalog.NPC_IDS:
				if profile.npc_affinity[id] < value.value:
					return false
			return true
		"artifact_count_min": return narrative.artifacts.size() >= value.value
		"record_count_min": return narrative.environment_records.size() >= value.value
	return false


static func depth_read(profile: Dictionary, npc_id: String) -> int:
	var count := 0
	for number: int in range(1, 6):
		if not profile.narrative_state.consumed_sources.has("dialogue:%s_depth_%d" % [npc_id, number]):
			break
		count += 1
	return count


static func _authored_source_count(sources: Array, content: RefCounted, kind: String) -> int:
	var count := 0
	for source: Dictionary in content.definitions("source"):
		if source.source_kind == kind and sources.has("source:" + str(source.source_receipt_id)):
			count += 1
	return count


static func _balance_sources(profile: Dictionary, content: RefCounted) -> Array:
	var sources: Array = []
	for npc: Dictionary in content.definitions("npc"):
		for node: Dictionary in npc.dialogue_nodes:
			var source := "dialogue:" + str(node.id)
			if not profile.narrative_state.balance_choice_sources.has(source):
				continue
			for choice: Dictionary in node.choices:
				for flag: String in choice.flags:
					if flag.begins_with("balance_choice_") and profile.narrative_state.flags.has(flag) and not sources.has(source):
						sources.append(source)
	return sources
