class_name NarrativeRuntime
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Content := preload("res://scripts/narrative/narrative_catalog.gd")
const Predicates := preload("res://scripts/narrative/narrative_predicates.gd")
const Endings := preload("res://scripts/narrative/ending_evaluator.gd")
const ACTIVE_FIELDS := ["run_id", "launch_sequence", "floor_id", "boss_ids", "max_hp", "current_hp"]
const EXPOSURE_FIELDS := ["run_id", "launch_sequence", "from_frame", "through_frame", "void_active_frames"]
const WATERMARK_PREFIX := "void-watermark:"
const ENDING_PREFIX := "ending-choice:"

var _content: RefCounted
var _endings: RefCounted
var _pickups: Dictionary = {}


func configure(entries: Array, sources: Array, meta_catalog: RefCounted) -> Dictionary:
	_content = null
	_endings = null
	_pickups.clear()
	if sources.size() != 13:
		return Candidate.failure(&"NARRATIVE_SOURCE_COUNT_INVALID")
	var content := Content.new()
	var configured := content.configure(entries, meta_catalog, sources)
	if not configured.ok:
		return configured
	var endings := Endings.new()
	configured = endings.configure(entries, meta_catalog, sources)
	if not configured.ok:
		return configured
	var pickups: Dictionary = {}
	for kind: String in ["artifact", "environment_record", "source"]:
		for row: Dictionary in content.definitions(kind):
			pickups[row.source_receipt_id] = {"kind": kind, "definition": row}
	for row: Dictionary in content.definitions("hidden_line"):
		for step: Dictionary in row.steps:
			pickups[step.source_receipt_id] = {"kind": "hidden_line", "definition": row, "step": step}
	_content = content
	_endings = endings
	_pickups = pickups
	return Candidate.success()


func prepare_command(profile: Dictionary, command: Dictionary, expected_revision: int, native_context: Dictionary = {}) -> Dictionary:
	if _content == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	var fields: Array = {
		"narrative_dialogue": ["command_id", "kind", "npc_id", "node_id", "choice_id"],
		"narrative_collect": ["command_id", "kind", "source_receipt_id"],
		"narrative_choice": ["command_id", "kind", "definition_id", "choice_id"],
		"narrative_ending": ["command_id", "kind", "ending_id"],
		"narrative_credits": ["command_id", "kind", "ending_id"],
	}.get(command.get("kind"), [])
	if fields.is_empty():
		return Candidate.failure(&"COMMAND_INVALID")
	var valid := Candidate.validate(profile, _content.meta_catalog(), command, fields, expected_revision)
	if not valid.ok:
		return valid
	var candidate := profile.duplicate(true)
	var result: Dictionary
	match command.kind:
		"narrative_dialogue":
			if not native_context.is_empty():
				return Candidate.failure(&"CONTEXT_INVALID")
			result = _dialogue(candidate, command)
		"narrative_collect":
			if not _active_context_valid(profile, native_context):
				return Candidate.failure(&"ACTIVE_CONTEXT_INVALID")
			result = _collect(candidate, command, native_context)
		"narrative_choice":
			if not _active_context_valid(profile, native_context):
				return Candidate.failure(&"ACTIVE_CONTEXT_INVALID")
			result = _choice(candidate, command, native_context)
		"narrative_ending": result = _ending(candidate, command, native_context)
		"narrative_credits":
			if not native_context.is_empty():
				return Candidate.failure(&"CONTEXT_INVALID")
			result = _credits(candidate, command)
	if not result.ok or result.context.get("deferred", false):
		return result
	return Candidate.finish(candidate, _content.meta_catalog(), command.command_id, result.context)


func dialogue_view(profile: Dictionary, npc_id: String) -> Dictionary:
	var normalized := _profile(profile)
	if normalized.is_empty():
		return Candidate.failure(&"PROFILE_INVALID")
	var definition: Dictionary = _content.definition("npc_" + npc_id)
	if definition.is_empty():
		return Candidate.failure(&"NPC_UNKNOWN")
	var nodes: Array = []
	for node: Dictionary in definition.dialogue_nodes:
		var consumed: bool = normalized.narrative_state.consumed_sources.has("dialogue:" + str(node.id))
		var missing := Predicates.missing(node.requirements, normalized, _content)
		if node.trigger.kind != "npc_intro" and not Predicates.satisfied(node.trigger, normalized, _content):
			missing.push_front(node.trigger.duplicate(true))
		nodes.append({"node_id": node.id, "text_key": node.text_key, "choices": node.choices.duplicate(true), "consumed": consumed, "available": consumed or missing.is_empty(), "missing_requirements": missing})
	return Candidate.success({"npc_id": npc_id, "affinity": normalized.npc_affinity[npc_id], "nodes": nodes})


func ending_view(profile: Dictionary, native_facts: Dictionary = {}) -> Dictionary:
	return _endings.evaluate(profile, native_facts) if _endings != null else Candidate.failure(&"NOT_CONFIGURED")


func prepare_void_observation(profile: Dictionary, observation: Dictionary, expected_revision: int) -> Dictionary:
	var normalized := _profile(profile)
	if normalized.is_empty():
		return Candidate.failure(&"PROFILE_INVALID")
	if expected_revision != normalized.revision:
		return Candidate.failure(&"STALE_REVISION")
	if not Catalog.exact_fields(observation, EXPOSURE_FIELDS) or not _matching_active(normalized, observation) or not Catalog.bounded_int(observation.from_frame, 0, Catalog.MAX_VALUE) or not Catalog.bounded_int(observation.through_frame, 1, Catalog.MAX_VALUE) or observation.through_frame <= observation.from_frame or not Catalog.bounded_int(observation.void_active_frames, 0, int(observation.through_frame) - int(observation.from_frame)):
		return Candidate.failure(&"OBSERVATION_INVALID")
	var watermark := _watermark(normalized)
	if watermark.is_empty() or watermark.sequence > observation.launch_sequence:
		return Candidate.failure(&"EXPOSURE_STATE_INVALID")
	var expected_frame: int = watermark.frame if watermark.sequence == observation.launch_sequence else 0
	if observation.from_frame != expected_frame:
		return Candidate.failure(&"OBSERVATION_RETIRED")
	if normalized.revision == Catalog.MAX_VALUE or normalized.narrative_state.void_exposure_frames > Catalog.MAX_VALUE - int(observation.void_active_frames):
		return Candidate.failure(&"TRANSACTION_LIMIT")
	var candidate := normalized.duplicate(true)
	if not watermark.source_id.is_empty():
		candidate.narrative_state.consumed_sources.erase(watermark.source_id)
	candidate.narrative_state.consumed_sources.append("%s%d:%d" % [WATERMARK_PREFIX, int(observation.launch_sequence), int(observation.through_frame)])
	candidate.narrative_state.consumed_sources.sort()
	candidate.narrative_state.void_exposure_frames += int(observation.void_active_frames)
	candidate.revision += 1
	var validator := Profile.new()
	if not validator.configure(_content.meta_catalog(), candidate):
		return Candidate.failure(&"CANDIDATE_INVALID")
	# The native service counts only unpaused Void gameplay and persists this watermark with the profile.
	return Candidate.success({"candidate": validator.snapshot(), "void_active_frames": int(observation.void_active_frames)})


func _dialogue(candidate: Dictionary, command: Dictionary) -> Dictionary:
	if not command.npc_id is String or not command.node_id is String or not command.choice_id is String:
		return Candidate.failure(&"DIALOGUE_INVALID")
	var npc: Dictionary = _content.definition("npc_" + str(command.npc_id))
	if npc.is_empty():
		return Candidate.failure(&"NPC_UNKNOWN")
	for node: Dictionary in npc.dialogue_nodes:
		if node.id != command.node_id:
			continue
		var source := "dialogue:" + str(node.id)
		if candidate.narrative_state.consumed_sources.has(source):
			return Candidate.failure(&"SOURCE_CONSUMED")
		if not Predicates.missing(node.requirements, candidate, _content).is_empty() or node.trigger.kind != "npc_intro" and not Predicates.satisfied(node.trigger, candidate, _content):
			return Candidate.failure(&"PREREQUISITE_MISSING")
		for choice: Dictionary in node.choices:
			if choice.id == command.choice_id:
				_apply_effect(candidate, npc.npc_id, choice)
				_consume(candidate, source)
				for flag: String in choice.flags:
					if flag.begins_with("balance_choice_") and not candidate.narrative_state.balance_choice_sources.has(source):
						candidate.narrative_state.balance_choice_sources.append(source)
						candidate.narrative_state.balance_choice_sources.sort()
				return Candidate.success({"source_id": source, "text_key": node.text_key})
	return Candidate.failure(&"DIALOGUE_INVALID")


func _collect(candidate: Dictionary, command: Dictionary, context: Dictionary) -> Dictionary:
	if not command.source_receipt_id is String or not _pickups.has(command.source_receipt_id):
		return Candidate.failure(&"SOURCE_UNKNOWN")
	var pickup: Dictionary = _pickups[command.source_receipt_id]
	var definition: Dictionary = pickup.step if pickup.kind == "hidden_line" else pickup.definition
	var source := ("source:" if pickup.kind == "source" else "pickup:") + str(command.source_receipt_id)
	if candidate.narrative_state.consumed_sources.has(source):
		return Candidate.failure(&"SOURCE_CONSUMED")
	if context.floor_id != definition.floor_id:
		return Candidate.failure(&"SOURCE_FLOOR_INVALID")
	if pickup.kind == "hidden_line":
		if candidate.narrative_state.hidden_steps[pickup.definition.storyline_id] + 1 != definition.index or not Predicates.missing(pickup.definition.requirements + definition.requirements, candidate, _content).is_empty():
			return Candidate.failure(&"PREREQUISITE_MISSING")
		candidate.narrative_state.hidden_steps[pickup.definition.storyline_id] = int(definition.index)
		if definition.index == 5:
			_append_id(candidate.narrative_state.flags, pickup.definition.completion_flag)
	elif pickup.kind == "source":
		for requirement: Dictionary in definition.requirements:
			if not context.boss_ids.has(requirement.id):
				return Candidate.failure(&"PREREQUISITE_MISSING")
		if definition.source_kind == "heart_fragment":
			_append_id(candidate.narrative_state.heart_fragments, definition.floor_id)
	elif pickup.kind == "artifact":
		_append_id(candidate.narrative_state.artifacts, definition.artifact_id)
	else:
		_append_id(candidate.narrative_state.environment_records, definition.record_id)
	_consume(candidate, source)
	return Candidate.success({"source_id": source, "text_key": definition.text_key})


func _choice(candidate: Dictionary, command: Dictionary, context: Dictionary) -> Dictionary:
	if not command.definition_id is String or not command.choice_id is String:
		return Candidate.failure(&"CHOICE_INVALID")
	var definition: Dictionary = _content.definition(command.definition_id)
	if definition.is_empty() or definition.definition_kind != "choice":
		return Candidate.failure(&"CHOICE_INVALID")
	var source := "choice:" + str(definition.source_receipt_id)
	if candidate.narrative_state.consumed_sources.has(source):
		return Candidate.failure(&"SOURCE_CONSUMED")
	if context.floor_id != definition.floor_id or not Predicates.missing(definition.requirements, candidate, _content).is_empty():
		return Candidate.failure(&"PREREQUISITE_MISSING")
	var count: int = candidate.narrative_state.vera_conversations if definition.choice_family == "vera" else candidate.narrative_state.nemesis_choices.size()
	if int(definition.sequence) != count + 1:
		return Candidate.failure(&"CHOICE_SEQUENCE_INVALID")
	for option: Dictionary in definition.options:
		if option.id != command.choice_id:
			continue
		if not option.consumes_source:
			return Candidate.success({"deferred": true, "temporary_max_hp_cost": 0})
		var effect: Dictionary = {}
		if definition.temporary_max_hp_cost > 0:
			var maximum := float(context.max_hp) - float(definition.temporary_max_hp_cost)
			if maximum <= 0.0:
				return Candidate.failure(&"TEMPORARY_CAPACITY_INSUFFICIENT")
			effect = {"kind": "temporary_max_hp_cost", "amount": int(definition.temporary_max_hp_cost), "run_id": context.run_id, "launch_sequence": int(context.launch_sequence), "before": {"max_hp": float(context.max_hp), "current_hp": float(context.current_hp)}, "after": {"max_hp": maximum, "current_hp": minf(float(context.current_hp), maximum)}}
		_apply_effect(candidate, definition.choice_family, option)
		if definition.choice_family == "vera":
			candidate.narrative_state.vera_conversations += 1
		else:
			candidate.narrative_state.nemesis_choices.append(option.id)
		_consume(candidate, source)
		return Candidate.success({"source_id": source, "run_effect": effect})
	return Candidate.failure(&"CHOICE_INVALID")


func _ending(candidate: Dictionary, command: Dictionary, context: Dictionary) -> Dictionary:
	if not command.ending_id is String:
		return Candidate.failure(&"ENDING_INVALID")
	var view: Dictionary = _endings.evaluate(candidate, context)
	if not view.ok:
		return view
	var markers: Array = []
	for source: String in candidate.narrative_state.consumed_sources:
		if source.begins_with(ENDING_PREFIX):
			markers.append(source)
	if markers.size() > 1:
		return Candidate.failure(&"ENDING_STATE_INVALID")
	var marker_expression := RegEx.new()
	marker_expression.compile("^ending-choice:([0-9]+):([a-z_]+)$")
	for source: String in markers:
		var parsed := marker_expression.search(source)
		if parsed == null or not Catalog.bounded_int(parsed.get_string(1).to_int(), 1, int(candidate.launch_sequence)) or _content.definition("ending_" + parsed.get_string(2)).is_empty() or source != "%s%d:%s" % [ENDING_PREFIX, parsed.get_string(1).to_int(), parsed.get_string(2)]:
			return Candidate.failure(&"ENDING_STATE_INVALID")
		if parsed.get_string(1).to_int() >= int(context.get("launch_sequence", 0)):
			return Candidate.failure(&"SOURCE_CONSUMED")
	for ending: Dictionary in view.context.endings:
		if ending.ending_id == command.ending_id and ending.eligible:
			for source: String in markers:
				candidate.narrative_state.consumed_sources.erase(source)
			_consume(candidate, "%s%d:%s" % [ENDING_PREFIX, int(context.launch_sequence), command.ending_id])
			_append_id(candidate.narrative_state.endings, command.ending_id)
			return Candidate.success({"ending_id": command.ending_id, "text_key": ending.text_key, "credits_key": ending.credits_key})
	return Candidate.failure(&"ENDING_LOCKED")


func _credits(candidate: Dictionary, command: Dictionary) -> Dictionary:
	if not command.ending_id is String or not candidate.narrative_state.endings.has(command.ending_id):
		return Candidate.failure(&"ENDING_UNDISCOVERED")
	if candidate.narrative_state.credits_completed.has(command.ending_id):
		return Candidate.failure(&"SOURCE_CONSUMED")
	_append_id(candidate.narrative_state.credits_completed, command.ending_id)
	return Candidate.success({"ending_id": command.ending_id})


func _profile(value: Dictionary) -> Dictionary:
	var validator := Profile.new()
	return validator.snapshot() if _content != null and not value.is_empty() and validator.configure(_content.meta_catalog(), value) else {}


static func _apply_effect(candidate: Dictionary, npc_id: String, effect: Dictionary) -> void:
	candidate.npc_affinity[npc_id] = mini(100, int(candidate.npc_affinity[npc_id]) + int(effect.affinity_delta))
	if effect.faction_delta.faction_id != "none":
		var id: String = effect.faction_delta.faction_id
		candidate.faction_standing[id] = clampi(int(candidate.faction_standing[id]) + int(effect.faction_delta.value), -100, 100)
	for flag: String in effect.flags:
		_append_id(candidate.narrative_state.flags, flag)


static func _consume(candidate: Dictionary, source: String) -> void:
	_append_id(candidate.narrative_state.consumed_sources, source)


static func _append_id(values: Array, id: String) -> void:
	if not values.has(id):
		values.append(id)
		values.sort()


static func _matching_active(profile: Dictionary, context: Dictionary) -> bool:
	var receipt: Dictionary = profile.active_launch_receipt
	return not receipt.is_empty() and context.get("run_id") == receipt.run_id and Catalog.bounded_int(context.get("launch_sequence"), 1, Catalog.MAX_VALUE) and context.launch_sequence == receipt.sequence


static func _active_context_valid(profile: Dictionary, value: Dictionary) -> bool:
	if not Catalog.exact_fields(value, ACTIVE_FIELDS) or not _matching_active(profile, value) or value.floor_id not in Catalog.FLOOR_IDS or not Catalog.finite_number(value.max_hp, 0.000001, 1000000.0) or not Catalog.finite_number(value.current_hp, 0.000001, float(value.max_hp)) or not value.boss_ids is Array or value.boss_ids.size() > 5:
		return false
	var seen: Array = []
	for id: Variant in value.boss_ids:
		if id not in Catalog.BOSS_IDS or seen.has(id):
			return false
		seen.append(id)
	return true


static func _watermark(profile: Dictionary) -> Dictionary:
	var result := {"sequence": 0, "frame": 0, "source_id": ""}
	var expression := RegEx.new()
	expression.compile("^void-watermark:([0-9]+):([0-9]+)$")
	for source: String in profile.narrative_state.consumed_sources:
		if not source.begins_with(WATERMARK_PREFIX):
			continue
		var parsed := expression.search(source)
		if parsed == null or not result.source_id.is_empty():
			return {}
		var sequence := parsed.get_string(1).to_int()
		var frame := parsed.get_string(2).to_int()
		if not Catalog.bounded_int(sequence, 1, int(profile.launch_sequence)) or not Catalog.bounded_int(frame, 1, Catalog.MAX_VALUE) or source != "%s%d:%d" % [WATERMARK_PREFIX, sequence, frame]:
			return {}
		result = {"sequence": sequence, "frame": frame, "source_id": source}
	return result
