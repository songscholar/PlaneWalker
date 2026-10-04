class_name EndingEvaluator
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Content := preload("res://scripts/narrative/narrative_catalog.gd")
const Predicates := preload("res://scripts/narrative/narrative_predicates.gd")
const FACT_FIELDS := ["run_id", "launch_sequence", "terminal_reason", "boss_ids"]

var _content: RefCounted


func configure(entries: Array, meta_catalog: RefCounted, source_entries: Array = []) -> Dictionary:
	_content = null
	var content := Content.new()
	var result := content.configure(entries, meta_catalog, source_entries)
	if result.ok:
		_content = content
	return result


func evaluate(profile: Dictionary, run_facts: Dictionary) -> Dictionary:
	if _content == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	var validator := Profile.new()
	if profile.is_empty() or not validator.configure(_content.meta_catalog(), profile):
		return Candidate.failure(&"PROFILE_INVALID")
	var normalized := validator.snapshot()
	if not run_facts.is_empty() and not _facts_valid(run_facts):
		return Candidate.failure(&"RUN_FACTS_INVALID")
	# Only the profile service supplies facts authenticated against the native terminal run.
	var victory := _matching_victory(normalized, run_facts)
	var choices: Array = []
	for definition: Dictionary in _content.definitions("ending"):
		var missing: Array = Predicates.missing(definition.requirements, normalized, _content)
		if not victory:
			missing.push_front({"kind": "canonical_victory", "id": "void_throne", "value": 1})
		choices.append({"ending_id": definition.ending_id, "final_choice": definition.final_choice, "name_key": definition.name_key, "text_key": definition.text_key, "credits_key": definition.credits_key, "eligible": missing.is_empty(), "missing_requirements": missing, "discovered": normalized.narrative_state.endings.has(definition.ending_id), "credits_completed": normalized.narrative_state.credits_completed.has(definition.ending_id)})
	return Candidate.success({"endings": choices, "victory": victory})


func _matching_victory(profile: Dictionary, facts: Dictionary) -> bool:
	if facts.is_empty() or facts.terminal_reason != "victory" or not facts.boss_ids.has("void_throne"):
		return false
	var receipt: Dictionary = profile.active_launch_receipt if not profile.active_launch_receipt.is_empty() else profile.last_settlement_receipt
	return not receipt.is_empty() and receipt.run_id == facts.run_id and receipt.sequence == facts.launch_sequence and (not receipt.has("terminal_reason") or receipt.terminal_reason == "victory")


static func _facts_valid(value: Dictionary) -> bool:
	if not Catalog.exact_fields(value, FACT_FIELDS) or not Catalog.stable_id(value.run_id) or not Catalog.bounded_int(value.launch_sequence, 1, Catalog.MAX_VALUE) or value.terminal_reason not in ["death", "victory", "abandon"] or not value.boss_ids is Array or value.boss_ids.size() > 5:
		return false
	var seen: Array = []
	for id: Variant in value.boss_ids:
		if id not in Catalog.BOSS_IDS or seen.has(id):
			return false
		seen.append(id)
	return true
