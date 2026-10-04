class_name NarrativeCatalog
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const COMMON_FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "effects", "definition_kind"]
const KIND_FIELDS := {
	"npc": ["npc_id", "district_id", "faction_id", "depth_thresholds", "dialogue_nodes", "resolution_flag"],
	"artifact": ["artifact_id", "floor_id", "source_receipt_id", "text_key", "record_tags"],
	"environment_record": ["record_id", "floor_id", "location_id", "source_receipt_id", "text_key", "record_tags"],
	"hidden_line": ["storyline_id", "requirements", "steps", "completion_flag"],
	"ending": ["ending_id", "final_choice", "resolved_boss_id", "requirements", "text_key", "credits_key", "gallery_replayable"],
	"choice": ["choice_family", "sequence", "floor_id", "source_receipt_id", "requirements", "temporary_max_hp_cost", "consumption_scope", "options"],
}
const COUNTS := {"npc": 8, "artifact": 10, "environment_record": 21, "hidden_line": 3, "ending": 5, "choice": 10}
const ENDING_CHOICES := {"return_of_order": "reassemble", "embrace_of_void": "accept", "balance_of_ashes": "coexist", "shattered_freedom": "release", "echo_of_primordial": "ask"}

var _meta: RefCounted
var _definitions: Dictionary = {}
var _by_kind: Dictionary = {}
var _sources: Dictionary = {}


func configure(entries: Array, meta_catalog: RefCounted, source_entries: Array = []) -> Dictionary:
	_meta = null
	_definitions.clear()
	_by_kind.clear()
	_sources.clear()
	var validator := Profile.new()
	if entries.size() != 57 or not validator.configure(meta_catalog):
		return Candidate.failure(&"NARRATIVE_CONTENT_INVALID")
	_meta = meta_catalog
	var definitions: Dictionary = {}
	var by_kind: Dictionary = {}
	var sources: Array = []
	for kind: String in COUNTS:
		by_kind[kind] = []
	for value: Variant in entries:
		if not value is Dictionary or not value.get("definition_kind") is String or not KIND_FIELDS.has(value.definition_kind) or not Catalog.exact_fields(value, COMMON_FIELDS + KIND_FIELDS[value.definition_kind]) or not _common_valid(value) or definitions.has(value.id) or not _definition_valid(value):
			_meta = null
			return Candidate.failure(&"NARRATIVE_CONTENT_INVALID", {"id": value.get("id") if value is Dictionary else ""})
		definitions[value.id] = value.duplicate(true)
		by_kind[value.definition_kind].append(value.id)
		var row_sources: Array = []
		if value.has("source_receipt_id"):
			row_sources.append(value.source_receipt_id)
		for step: Dictionary in value.get("steps", []):
			row_sources.append(step.source_receipt_id)
		for source: String in row_sources:
			if sources.has(source):
				_meta = null
				return Candidate.failure(&"NARRATIVE_SOURCE_DUPLICATE")
			sources.append(source)
	for kind: String in COUNTS:
		if by_kind[kind].size() != COUNTS[kind]:
			_meta = null
			return Candidate.failure(&"NARRATIVE_COUNT_INVALID")
		by_kind[kind].sort()
	_definitions = definitions
	_by_kind = by_kind
	if not source_entries.is_empty():
		var configured := _configure_sources(source_entries, sources)
		if not configured.ok:
			_meta = null
			_definitions.clear()
			_by_kind.clear()
			return configured
	return Candidate.success()


func definition(id: String) -> Dictionary:
	return (_definitions.get(id, {}) as Dictionary).duplicate(true)


func definitions(kind: String) -> Array:
	var values: Array = []
	if kind == "source":
		var ids := _sources.keys()
		ids.sort()
		for id: String in ids:
			values.append((_sources[id] as Dictionary).duplicate(true))
		return values
	for id: String in _by_kind.get(kind, []):
		values.append(definition(id))
	return values


func source_definition(source_id: String) -> Dictionary:
	return (_sources.get(source_id, {}) as Dictionary).duplicate(true)


func _configure_sources(entries: Array, existing_sources: Array) -> Dictionary:
	if entries.size() != 13:
		return Candidate.failure(&"NARRATIVE_SOURCE_COUNT_INVALID")
	var fields := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "effects", "source_kind", "sequence", "source_receipt_id", "floor_id", "location_id", "requirements", "text_key", "consumption_scope"]
	var counts := {"phia_marker": 0, "walker_letter": 0, "heart_fragment": 0}
	var sources: Dictionary = {}
	var locations: Array = []
	var heart_floors: Array = []
	for row: Variant in entries:
		if not Catalog.exact_fields(row, fields) or row.category != "narrative_source_definition" or not Catalog.bounded_int(row.schema_version, 1, 1) or not _text_key(row.name_key) or not _text_key(row.description_key) or not _text_key(row.text_key) or row.availability != ["LAUNCH", "EXPANSION"] or row.tags != ["launch", "narrative"] or not row.compatibility is Dictionary or not row.compatibility.is_empty() or not row.effects is Dictionary or not row.effects.is_empty() or row.source_kind not in counts or not Catalog.bounded_int(row.sequence, 1, 3 if row.source_kind == "walker_letter" else 5):
			return Candidate.failure(&"NARRATIVE_SOURCE_INVALID")
		if row.source_receipt_id != "%s_%d" % [row.source_kind, int(row.sequence)] or row.id != "source_" + str(row.source_receipt_id) or sources.has(row.source_receipt_id) or existing_sources.has(row.source_receipt_id) or row.floor_id not in Catalog.FLOOR_IDS or not Catalog.stable_id(row.location_id) or locations.has(row.location_id) or row.consumption_scope != "profile" or not _predicates_valid(row.requirements):
			return Candidate.failure(&"NARRATIVE_SOURCE_INVALID")
		if row.source_kind == "heart_fragment":
			if row.requirements.size() != 1 or row.requirements[0].kind != "boss_defeated" or row.requirements[0].id != {"floor_ruins_of_remnant": "ruin_king", "floor_void_forest": "forest_heart", "floor_time_rift": "time_sovereign", "floor_plane_forge": "forge_colossus", "floor_throne_of_void": "void_throne"}[row.floor_id] or heart_floors.has(row.floor_id):
				return Candidate.failure(&"NARRATIVE_SOURCE_INVALID")
			heart_floors.append(row.floor_id)
		elif not row.requirements.is_empty() or row.source_kind == "phia_marker" and row.floor_id != "floor_ruins_of_remnant":
			return Candidate.failure(&"NARRATIVE_SOURCE_INVALID")
		sources[row.source_receipt_id] = row.duplicate(true)
		locations.append(row.location_id)
		counts[row.source_kind] += 1
	if counts != {"phia_marker": 5, "walker_letter": 3, "heart_fragment": 5}:
		return Candidate.failure(&"NARRATIVE_SOURCE_COUNT_INVALID")
	_sources = sources
	return Candidate.success()


func meta_catalog() -> RefCounted:
	return _meta


func predicate_valid(value: Variant) -> bool:
	if not Catalog.exact_fields(value, ["kind", "id", "value"]) or not value.kind is String or not Catalog.stable_id(value.id) or not Catalog.bounded_int(value.value, 0, Catalog.MAX_VALUE):
		return false
	match value.kind:
		"npc_intro": return value.id in Catalog.NPC_IDS and value.value == 1
		"first_death": return value.id == "all" and value.value == 1
		"floor_completed": return value.id in Catalog.FLOOR_IDS and value.value == 1
		"boss_defeated": return value.id in Catalog.BOSS_IDS and value.value == 1
		"affinity_min": return value.id in Catalog.NPC_IDS and value.value <= 100
		"npc_depth_read", "npc_depth_incomplete": return value.id in Catalog.NPC_IDS and value.value <= 5
		"record_collected": return _reference("environment_record", value.id) and value.value == 1
		"artifact_collected": return _reference("artifact", value.id) and value.value == 1
		"flag_set": return _reference("narrative_flag", value.id) and value.value == 1
		"hidden_step_complete": return value.id in Catalog.HIDDEN_LINE_IDS and value.value <= 5
		"phia_markers_min": return value.id == "phia" and value.value <= 5
		"related_letter_count_min": return value.id == "walkers" and value.value <= 3
		"void_exposure_frames_min": return value.id == "all"
		"nemesis_spared_min": return value.id == "nemesis" and value.value <= 5
		"vera_conversation_count_min": return value.id == "vera" and value.value <= 5
		"heart_fragment_count_min": return value.id == "all" and value.value <= 5
		"balance_choice_count_min": return value.id == "all" and value.value <= 3
		"all_hidden_lines_complete": return value.id == "all" and value.value == 3
		"all_npc_affinity_min": return value.id == "all" and value.value <= 100
		"artifact_count_min": return value.id == "all" and value.value <= 10
		"record_count_min": return value.id == "all" and value.value <= 21
	return false


func _definition_valid(row: Dictionary) -> bool:
	match row.definition_kind:
		"npc": return _npc_valid(row)
		"artifact":
			return row.id == "artifact_" + str(row.artifact_id) and _reference("artifact", row.artifact_id) and row.floor_id in Catalog.FLOOR_IDS and row.source_receipt_id == "artifact_pickup_" + str(row.artifact_id) and _text_key(row.text_key) and _stable_list(row.record_tags, 8, false)
		"environment_record":
			var ids: Array = []
			for floor_number: int in range(1, 6):
				for number: int in range(1, 6 if floor_number == 1 else 5):
					ids.append("E%d-%d" % [floor_number, number])
			return row.record_id in ids and row.id == "record_" + str(row.record_id).to_lower().replace("-", "_") and _reference("environment_record", row.record_id) and row.floor_id in Catalog.FLOOR_IDS and Catalog.stable_id(row.location_id) and row.source_receipt_id == "observe_" + str(row.location_id) and _text_key(row.text_key) and _stable_list(row.record_tags, 8, false)
		"hidden_line": return _hidden_valid(row)
		"ending":
			return row.ending_id in ENDING_CHOICES and row.id == "ending_" + str(row.ending_id) and _reference("ending", row.ending_id) and row.final_choice == ENDING_CHOICES[row.ending_id] and row.resolved_boss_id == "void_throne" and _predicates_valid(row.requirements) and (row.requirements.is_empty() == (row.ending_id == "shattered_freedom")) and _text_key(row.text_key) and _text_key(row.credits_key) and row.gallery_replayable is bool and row.gallery_replayable
		"choice": return _choice_valid(row)
	return false


func _npc_valid(row: Dictionary) -> bool:
	if row.npc_id not in Catalog.NPC_IDS or row.id != "npc_" + str(row.npc_id) or row.district_id not in ["hub_council", "hub_craft", "hub_rift"] or row.faction_id not in Catalog.FACTION_IDS or not row.depth_thresholds is Array or row.depth_thresholds.size() != 5 or row.resolution_flag != str(row.npc_id) + "_resolution" or not _reference("narrative_flag", row.resolution_flag) or not row.dialogue_nodes is Array or row.dialogue_nodes.size() != 13:
		return false
	for index: int in range(5):
		if not Catalog.bounded_int(row.depth_thresholds[index], (index + 1) * 20, (index + 1) * 20):
			return false
	var ids: Array = [str(row.npc_id) + "_intro", str(row.npc_id) + "_first_death", str(row.npc_id) + "_resolution"]
	for index: int in range(1, 6):
		ids.append("%s_floor_%d" % [row.npc_id, index])
		ids.append("%s_depth_%d" % [row.npc_id, index])
	var seen: Array = []
	var choice_ids: Array = []
	for node: Variant in row.dialogue_nodes:
		if not Catalog.exact_fields(node, ["id", "text_key", "trigger", "requirements", "choices"]) or node.id not in ids or seen.has(node.id) or not _text_key(node.text_key) or not predicate_valid(node.trigger) or not _predicates_valid(node.requirements) or not node.choices is Array or node.choices.is_empty() or node.choices.size() > 4:
			return false
		seen.append(node.id)
		for choice: Variant in node.choices:
			if not Catalog.exact_fields(choice, ["id", "text_key", "affinity_delta", "faction_delta", "flags", "once"]) or not _effect_valid(choice) or not choice.once is bool or not choice.once or choice_ids.has(choice.id):
				return false
			choice_ids.append(choice.id)
	return true


func _hidden_valid(row: Dictionary) -> bool:
	if row.storyline_id not in Catalog.HIDDEN_LINE_IDS or row.id != "hidden_" + str(row.storyline_id) or row.completion_flag != str(row.storyline_id) + "_complete" or not _reference("narrative_flag", row.completion_flag) or not _predicates_valid(row.requirements) or not row.steps is Array or row.steps.size() != 5:
		return false
	for index: int in range(5):
		var step: Variant = row.steps[index]
		if not Catalog.exact_fields(step, ["id", "index", "source_receipt_id", "floor_id", "requirements", "text_key"]) or step.id != "%s_step_%d" % [row.storyline_id, index + 1] or not Catalog.bounded_int(step.index, index + 1, index + 1) or step.source_receipt_id != "hidden_%s_%d" % [row.storyline_id, index + 1] or step.floor_id not in Catalog.FLOOR_IDS or not _predicates_valid(step.requirements) or not _text_key(step.text_key):
			return false
	return true


func _choice_valid(row: Dictionary) -> bool:
	if row.choice_family not in ["nemesis", "vera"] or not Catalog.bounded_int(row.sequence, 1, 5) or row.id != "choice_%s_%d" % [row.choice_family, int(row.sequence)] or row.floor_id not in Catalog.FLOOR_IDS or row.source_receipt_id != "%s_%d" % ["nemesis_encounter" if row.choice_family == "nemesis" else "vera_conversation", int(row.sequence)] or not _predicates_valid(row.requirements) or not Catalog.bounded_int(row.temporary_max_hp_cost, 0 if row.choice_family == "nemesis" else 5, 0 if row.choice_family == "nemesis" else 5) or row.consumption_scope != "profile" or not row.options is Array or row.options.size() != 2:
		return false
	var expected := ["attack", "spare"] if row.choice_family == "nemesis" else ["defer", "listen"]
	var seen: Array = []
	for option: Variant in row.options:
		if not Catalog.exact_fields(option, ["id", "text_key", "affinity_delta", "faction_delta", "flags", "spared", "consumes_source"]) or not _effect_valid(option) or option.id not in expected or seen.has(option.id) or not option.spared is bool or not option.consumes_source is bool or option.spared != (option.id == "spare") or option.consumes_source != (option.id != "defer"):
			return false
		if option.id == "defer" and (option.affinity_delta != 0 or not option.flags.is_empty() or option.faction_delta.faction_id != "none" or option.faction_delta.value != 0):
			return false
		seen.append(option.id)
	return true


func _effect_valid(value: Dictionary) -> bool:
	if not Catalog.stable_id(value.id) or not _text_key(value.text_key) or not Catalog.bounded_int(value.affinity_delta, 0, 16) or not Catalog.exact_fields(value.faction_delta, ["faction_id", "value"]) or value.faction_delta.faction_id not in Catalog.FACTION_IDS + ["none"] or not Catalog.bounded_int(value.faction_delta.value, -10, 10) or value.faction_delta.faction_id == "none" and value.faction_delta.value != 0 or not _stable_list(value.flags, 8, true):
		return false
	for flag: String in value.flags:
		if not _reference("narrative_flag", flag):
			return false
	return true


func _predicates_valid(values: Variant) -> bool:
	if not values is Array or values.size() > 16:
		return false
	var seen: Array = []
	for value: Variant in values:
		if not predicate_valid(value) or seen.has(value):
			return false
		seen.append(value)
	return true


func _common_valid(row: Dictionary) -> bool:
	return row.category == "narrative_definition" and Catalog.stable_id(row.id) and Catalog.bounded_int(row.schema_version, 1, 1) and _text_key(row.name_key) and _text_key(row.description_key) and row.availability == ["LAUNCH", "EXPANSION"] and row.tags == ["launch", "hub"] and row.compatibility is Dictionary and row.compatibility.is_empty() and row.effects is Dictionary and row.effects.is_empty()


func _reference(category: String, id: Variant) -> bool:
	return id is String and _meta != null and _meta.call("has_reference", category, id)


static func _stable_list(value: Variant, maximum: int, allow_empty: bool) -> bool:
	if not value is Array or value.size() > maximum or not allow_empty and value.is_empty():
		return false
	var seen: Array = []
	for id: Variant in value:
		if not Catalog.stable_id(id) or seen.has(id):
			return false
		seen.append(id)
	return true


static func _text_key(value: Variant) -> bool:
	if not value is String or value.length() < 2 or value.length() > 128:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[A-Z][A-Z0-9_]+$")
	return pattern.search(value) != null
