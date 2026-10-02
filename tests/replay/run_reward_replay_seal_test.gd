extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunRuntimeFacadeScript := preload("res://scripts/application/run_runtime_facade.gd")

const SEAL_PATH := "res://scripts/application/run_reward_replay_seal.gd"
const EFFECT_CATALOG_PATH := "res://data/content/effect_catalog.json"


class DriftRegistry:
	extends RefCounted

	var base: RefCounted
	var definition_overrides: Dictionary = {}
	var packs_override: Array[Dictionary] = []

	func _init(p_base: RefCounted) -> void:
		base = p_base

	func active_packs() -> Array[Dictionary]:
		if not packs_override.is_empty():
			return packs_override.duplicate(true)
		return base.call("active_packs")

	func get_content(content_id: StringName) -> Dictionary:
		var key := str(content_id)
		if definition_overrides.has(key):
			return (definition_overrides[key] as Dictionary).duplicate(true)
		return base.call("get_content", content_id)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	suite.assert_true(FileAccess.file_exists(SEAL_PATH), "Run reward Replay seal authority exists")
	var seal_script: Variant = load(SEAL_PATH) if FileAccess.file_exists(SEAL_PATH) else null
	suite.assert_true(seal_script != null, "Run reward Replay seal authority loads")
	if seal_script == null:
		suite.finish(get_tree())
		return

	var facade = RunRuntimeFacadeScript.new()
	suite.assert_true(facade.boot().ok, "Launch reward Replay fixture boots")
	var launch_started = facade.start_run(
		_config("LAUNCH", 20260917), "run-reward-replay-seal"
	)
	suite.assert_true(launch_started.ok, "Launch reward Replay fixture starts")
	if not launch_started.ok:
		suite.finish(get_tree())
		return
	suite.assert_true(facade.has_method("reward_replay_snapshot"), "Facade exposes reward Replay capture")
	suite.assert_true(
		facade.has_method("can_restore_reward_replay_snapshot"),
		"Facade exposes reward Replay preflight"
	)
	suite.assert_true(
		facade.has_method("restore_reward_replay_snapshot"),
		"Facade exposes reward Replay restore"
	)
	if not facade.has_method("reward_replay_snapshot"):
		suite.finish(get_tree())
		return

	var first_definition := _complete_and_select_effectful_reward(suite, facade, "first")
	var checkpoint: Dictionary = facade.call("reward_replay_snapshot")
	_assert_complete_seal(suite, checkpoint, first_definition, 1, "first checkpoint")
	if (checkpoint.get("reward_facts", []) as Array).is_empty():
		suite.finish(get_tree())
		return

	var second_definition := _complete_and_select_effectful_reward(suite, facade, "second")
	var current: Dictionary = facade.call("reward_replay_snapshot")
	_assert_complete_seal(suite, current, second_definition, 2, "current checkpoint")
	suite.assert_true(
		str(current.get("snapshot_digest", "")) != str(checkpoint.get("snapshot_digest", "")),
		"a later reward changes the Run reward Replay digest"
	)

	var seal: RefCounted = seal_script.new()
	var live_before: Dictionary = facade.snapshot()
	var live_seal_before: Dictionary = current.duplicate(true)
	var invalid_snapshots := _forged_snapshots(seal, current)
	for mutation: Dictionary in invalid_snapshots:
		var forged := mutation["snapshot"] as Dictionary
		suite.assert_true(
			not bool(facade.call("can_restore_reward_replay_snapshot", forged)),
			"%s fails reward Replay preflight" % str(mutation["label"])
		)
		suite.assert_true(
			not bool(facade.call("restore_reward_replay_snapshot", forged)),
			"%s fails reward Replay restore" % str(mutation["label"])
		)
		suite.assert_equal(
			facade.snapshot(),
			live_before,
			"%s cannot mutate live RunState" % str(mutation["label"])
		)
		suite.assert_equal(
			facade.call("reward_replay_snapshot"),
			live_seal_before,
			"%s cannot alter the live reward prefix" % str(mutation["label"])
		)

	_assert_current_content_drift_fails_closed(suite, facade, seal_script, current, live_before)

	suite.assert_true(
		bool(facade.call("can_restore_reward_replay_snapshot", checkpoint)),
		"a valid earlier reward checkpoint passes preflight"
	)
	suite.assert_true(
		bool(facade.call("restore_reward_replay_snapshot", checkpoint)),
		"a valid earlier reward checkpoint restores atomically"
	)
	suite.assert_equal(
		facade.call("reward_replay_snapshot"),
		checkpoint,
		"old reward checkpoint restores byte-for-byte"
	)
	var restored_build_projection := facade.snapshot().get("build", {}) as Dictionary
	var checkpoint_build := checkpoint.get("build_state", {}) as Dictionary
	for field: String in [
		"items", "blessings", "curses", "talents", "reward_history",
		"archetypes", "dominant_archetype",
	]:
		suite.assert_equal(
			restored_build_projection.get(field),
			checkpoint_build.get(field),
			"old reward checkpoint restores BuildState %s" % field
		)

	var m1 = RunRuntimeFacadeScript.new()
	suite.assert_true(m1.boot().ok, "M1 parity fixture boots")
	suite.assert_true(m1.start_run(_config("M1", 17), "run-reward-replay-m1").ok, "M1 parity run starts")
	var m1_before: Dictionary = m1.snapshot()
	suite.assert_equal(
		m1.call("reward_replay_snapshot") if m1.has_method("reward_replay_snapshot") else {},
		{},
		"M1 remains outside the Launch/Expansion reward seal"
	)
	suite.assert_true(
		not bool(m1.call("restore_reward_replay_snapshot", checkpoint)),
		"M1 refuses a Launch reward seal"
	)
	suite.assert_equal(m1.snapshot(), m1_before, "Launch seal rejection preserves M1 state")

	suite.finish(get_tree())


func _complete_and_select_effectful_reward(
	suite,
	facade: RefCounted,
	label: String
) -> Dictionary:
	var choices: Array = facade.call("route_choices")
	suite.assert_true(not choices.is_empty(), "%s route exposes a legal choice" % label)
	if choices.is_empty():
		return {}
	var choice := choices[0] as Dictionary
	var before_route: Dictionary = facade.call("snapshot")
	var begun = facade.call(
		"begin_route_transition",
		StringName(str(choice.get("edge_id", ""))),
		int(before_route.get("revision", -1))
	)
	suite.assert_true(begun.ok, "%s route transition begins" % label)
	if not begun.ok:
		return {}
	var finalized = facade.call(
		"finalize_route_transition",
		str(begun.context.get("transition_id", "")),
		int(begun.new_revision)
	)
	suite.assert_true(finalized.ok, "%s route transition enters its selected room" % label)
	if not finalized.ok:
		return {}
	var entered_room: Dictionary = facade.call("current_room_definition")
	suite.assert_equal(
		str(entered_room.get("node_id", "")),
		str(choice.get("node_id", "")),
		"%s route enters the selected FloorPlan node" % label
	)
	var completion = facade.call("complete_current_room")
	suite.assert_true(completion.ok, "%s route room completes through FloorPlan authority" % label)
	if not completion.ok:
		return {}
	var orchestrator: RefCounted = facade.get("_orchestrator")
	var draft: RefCounted = facade.get("_draft")
	var floor_checkpoint: Dictionary = orchestrator.call("floor_transaction_snapshot")
	var state: Dictionary = facade.call("snapshot")
	var reward_kind := (
		"starter"
		if (state.get("build", {}).get("reward_history", []) as Array).is_empty()
		else "reinforcement"
	)
	var created = draft.call(
		"create_offer",
		facade.call("content_registry"),
		state,
		{
			"reward_kind": reward_kind,
			"room_number": int(state.get("current_room", 0)),
		}
	)
	suite.assert_true(created.ok, "%s completed route room creates an authoritative reward" % label)
	if not created.ok:
		return {}
	var offer := created.context.get("offer", {}) as Dictionary
	var opened = orchestrator.call("open_selection", offer)
	suite.assert_true(opened.ok, "%s reward opens through RunOrchestrator" % label)
	if not opened.ok:
		return {}
	var registry: RefCounted = facade.call("content_registry")
	var selected_option := ""
	var selected_definition: Dictionary = {}
	for option_value: Variant in offer.get("options", []):
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		var definition: Dictionary = registry.call(
			"get_content", StringName(str(option.get("content_id", "")))
		)
		if definition.get("effects", {}) is Dictionary and not (
			definition.get("effects", {}) as Dictionary
		).is_empty():
			selected_option = str(option.get("option_id", ""))
			selected_definition = definition.duplicate(true)
			break
	if selected_option.is_empty():
		var first_option := (offer.get("options", []) as Array)[0] as Dictionary
		selected_option = str(first_option.get("option_id", ""))
		selected_definition = registry.call(
			"get_content", StringName(str(first_option.get("content_id", "")))
		)
	suite.assert_true(not selected_option.is_empty(), "%s reward chooses a stable option" % label)
	var selected = facade.call(
		"submit_selection",
		str(offer.get("offer_id", "")),
		selected_option,
		int(offer.get("revision", -1))
	)
	suite.assert_true(selected.ok, "%s reward commits through authority" % label)
	if not selected.ok:
		return {}
	suite.assert_true(
		bool(orchestrator.call("restore_floor_transaction_snapshot", floor_checkpoint)),
		"%s reward fixture restores the completed FloorPlan route checkpoint" % label
	)
	return selected_definition


func _assert_complete_seal(
	suite,
	snapshot: Dictionary,
	selected_definition: Dictionary,
	expected_count: int,
	label: String
) -> void:
	suite.assert_equal(snapshot.get("schema_id"), "planewalker.run_reward_replay", "%s schema id" % label)
	suite.assert_equal(snapshot.get("schema_version"), 1, "%s schema version" % label)
	suite.assert_equal(snapshot.get("milestone"), "LAUNCH", "%s milestone" % label)
	var content_snapshot := snapshot.get("content_snapshot", {}) as Dictionary
	suite.assert_true(not str(content_snapshot.get("aggregate_sha256", "")).is_empty(), "%s seals content aggregate" % label)
	suite.assert_equal((content_snapshot.get("packs", []) as Array).size(), 1, "%s seals active pack records" % label)
	var build := snapshot.get("build_state", {}) as Dictionary
	suite.assert_equal((build.get("reward_history", []) as Array).size(), expected_count, "%s seals BuildState history" % label)
	suite.assert_equal((build.get("archetypes", {}) as Dictionary).size(), 8, "%s seals eight archetype scores" % label)
	suite.assert_true(build.has("dominant_archetype"), "%s seals dominant identity" % label)
	var facts := snapshot.get("reward_facts", []) as Array
	suite.assert_equal(facts.size(), expected_count, "%s seals ordered reward facts" % label)
	if not facts.is_empty():
		var last_fact := facts.back() as Dictionary
		suite.assert_equal(last_fact.get("id"), selected_definition.get("id"), "%s fact preserves content id" % label)
		suite.assert_equal(last_fact.get("category"), selected_definition.get("category"), "%s fact preserves category" % label)
		suite.assert_equal(last_fact.get("archetype"), selected_definition.get("archetype", ""), "%s fact preserves archetype" % label)
		suite.assert_true(last_fact.get("effects") is Dictionary, "%s fact seals normalized effects" % label)
		suite.assert_equal(str(last_fact.get("effect_digest", "")).length(), 64, "%s fact seals effect digest" % label)
	var prefix := snapshot.get("reward_prefix", {}) as Dictionary
	suite.assert_equal(prefix.get("fact_count"), expected_count, "%s prefix count" % label)
	suite.assert_equal(str(prefix.get("root_sha256", "")).length(), 64, "%s prefix root" % label)
	suite.assert_equal(str(prefix.get("digest_sha256", "")).length(), 64, "%s prefix digest" % label)
	suite.assert_equal(str(snapshot.get("snapshot_digest", "")).length(), 64, "%s terminal digest" % label)


func _forged_snapshots(seal: RefCounted, source: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var facts := source.get("reward_facts", []) as Array
	var first_fact := facts[0] as Dictionary
	var first_category := str(first_fact.get("category", ""))
	var collection: String = str({
		"item": "items",
		"blessing": "blessings",
		"curse": "curses",
		"talent": "talents",
	}[first_category])

	var unknown := source.duplicate(true)
	unknown["build_state"][collection][0] = "unknown_reward_id"
	unknown["build_state"]["reward_history"][0]["id"] = "unknown_reward_id"
	unknown["reward_facts"][0]["id"] = "unknown_reward_id"
	_reseal(seal, unknown)
	result.append({"label": "unknown content id", "snapshot": unknown})

	var reordered := source.duplicate(true)
	(reordered["reward_facts"] as Array).reverse()
	_reseal(seal, reordered)
	result.append({"label": "reward prefix reorder", "snapshot": reordered})

	var deleted := source.duplicate(true)
	(deleted["reward_facts"] as Array).pop_back()
	_reseal(seal, deleted)
	result.append({"label": "reward prefix deletion", "snapshot": deleted})

	var modified := source.duplicate(true)
	modified["reward_facts"][0]["archetype"] = "echo_legion"
	_reseal(seal, modified)
	result.append({"label": "reward fact modification", "snapshot": modified})

	var score_drift := source.duplicate(true)
	var first_archetype := str((score_drift["build_state"]["archetype_order"] as Array)[0])
	score_drift["build_state"]["archetypes"][first_archetype] = int(
		score_drift["build_state"]["archetypes"][first_archetype]
	) + 1
	_reseal(seal, score_drift)
	result.append({"label": "BuildState score drift", "snapshot": score_drift})

	var dominant_drift := source.duplicate(true)
	dominant_drift["build_state"]["dominant_archetype"] = "echo_legion"
	_reseal(seal, dominant_drift)
	result.append({"label": "BuildState dominant drift", "snapshot": dominant_drift})

	var collection_drift := source.duplicate(true)
	collection_drift["build_state"][collection][0] = "typed_collection_drift"
	_reseal(seal, collection_drift)
	result.append({"label": "BuildState typed collection drift", "snapshot": collection_drift})
	return result


func _assert_current_content_drift_fails_closed(
	suite,
	facade: RefCounted,
	seal_script: Variant,
	target: Dictionary,
	live_before: Dictionary
) -> void:
	var base_registry: RefCounted = facade.call("content_registry")
	var selected_fact := _first_effectful_fact(target.get("reward_facts", []) as Array)
	suite.assert_true(not selected_fact.is_empty(), "drift fixture finds an effectful reward fact")
	if selected_fact.is_empty():
		return
	var content_id := str(selected_fact.get("id", ""))

	var effect_drift := DriftRegistry.new(base_registry)
	var changed_definition: Dictionary = base_registry.call("get_content", StringName(content_id))
	changed_definition["effects"] = {}
	effect_drift.definition_overrides[content_id] = changed_definition
	facade.set("_registry", effect_drift)
	suite.assert_true(
		not bool(facade.call("can_restore_reward_replay_snapshot", target)),
		"current content effect drift fails closed"
	)
	suite.assert_true(
		not bool(facade.call("restore_reward_replay_snapshot", target)),
		"content effect drift cannot restore"
	)
	suite.assert_equal(facade.snapshot(), live_before, "content effect drift cannot mutate RunState")
	facade.set("_registry", base_registry)

	var fingerprint_drift := DriftRegistry.new(base_registry)
	fingerprint_drift.packs_override = base_registry.call("active_packs")
	fingerprint_drift.packs_override[0]["fingerprint_sha256"] = "0".repeat(64)
	facade.set("_registry", fingerprint_drift)
	suite.assert_true(
		not bool(facade.call("can_restore_reward_replay_snapshot", target)),
		"content fingerprint mismatch fails closed"
	)
	suite.assert_true(
		not bool(facade.call("restore_reward_replay_snapshot", target)),
		"content fingerprint mismatch cannot restore"
	)
	suite.assert_equal(facade.snapshot(), live_before, "fingerprint mismatch cannot mutate RunState")
	facade.set("_registry", base_registry)

	var effect_ids := (selected_fact.get("effects", {}) as Dictionary).keys()
	var drift_catalog_path := "user://run_reward_replay_effect_catalog_drift.json"
	var catalog_value: Variant = _read_json(EFFECT_CATALOG_PATH)
	if catalog_value is Array and not effect_ids.is_empty():
		for row_value: Variant in catalog_value:
			if row_value is Dictionary and str((row_value as Dictionary).get("effect_id", "")) == str(effect_ids[0]):
				var row := row_value as Dictionary
				if row.get("maximum") is int:
					row["maximum"] = int(row["maximum"]) + 1
				elif row.get("maximum") is float:
					row["maximum"] = float(row["maximum"]) + 1.0
				break
		var file := FileAccess.open(drift_catalog_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(catalog_value, "\t"))
			file.close()
			var drift_seal: RefCounted = seal_script.new(drift_catalog_path)
			facade.set("_reward_replay_seal", drift_seal)
			suite.assert_true(
				not bool(facade.call("can_restore_reward_replay_snapshot", target)),
				"current effect bounds drift fails closed"
			)
			suite.assert_true(
				not bool(facade.call("restore_reward_replay_snapshot", target)),
				"effect bounds drift cannot restore"
			)
			suite.assert_equal(facade.snapshot(), live_before, "effect bounds drift cannot mutate RunState")
			facade.set("_reward_replay_seal", seal_script.new())
			DirAccess.remove_absolute(ProjectSettings.globalize_path(drift_catalog_path))


func _first_effectful_fact(facts: Array) -> Dictionary:
	for fact_value: Variant in facts:
		if fact_value is Dictionary and fact_value.get("effects", {}) is Dictionary and not (
			fact_value.get("effects", {}) as Dictionary
		).is_empty():
			return (fact_value as Dictionary).duplicate(true)
	return {}


func _reseal(seal: RefCounted, snapshot: Dictionary) -> void:
	snapshot["reward_prefix"] = seal.call(
		"reward_prefix", (snapshot.get("reward_facts", []) as Array).duplicate(true)
	)
	snapshot["snapshot_digest"] = seal.call("snapshot_digest", snapshot)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	return parser.data


func _config(milestone: String, seed_value: int) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": milestone,
		"character_id": "wanderer",
		"character_talents": [],
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": seed_value,
	}
