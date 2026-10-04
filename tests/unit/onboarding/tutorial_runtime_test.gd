extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/onboarding/tutorial_runtime.gd") as Script
	suite.assert_true(implementation != null, "authoritative tutorial candidate runtime exists")
	if implementation != null:
		_test_lessons(implementation)
		_test_training_and_hints(implementation)
		_test_skip_and_guided(implementation)
		_test_malformed_progress(implementation)
		_test_receipt_boundaries(implementation)
		_test_catalog_boundaries(implementation)
		_test_all_hints(implementation)
	suite.finish(get_tree())


func _runtime(implementation: Script, catalog: RefCounted) -> RefCounted:
	var runtime: RefCounted = implementation.new()
	var configured: Dictionary = runtime.configure(_entries(), catalog)
	suite.assert_true(configured.ok, "all thirty-four actual tutorial definitions configure: " + str(configured))
	return runtime


func _test_lessons(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := _active_profile(catalog)
	var normal_sequence := 0
	var hub_sequence := 0
	for definition: Dictionary in _entries():
		if definition.definition_kind != "lesson":
			continue
		if definition.sequence == 9:
			profile.active_launch_receipt.clear()
		for requirement: Dictionary in definition.receipt_requirements:
			for count: int in range(int(requirement.count)):
				if requirement.context_id == "normal_run":
					normal_sequence += 1
				else:
					hub_sequence += 1
				var receipt := _receipt(requirement.action_id, requirement.context_id, 1, normal_sequence if requirement.context_id == "normal_run" else hub_sequence)
				var before := profile.duplicate(true)
				var result: Dictionary = runtime.prepare_observation(profile, receipt, profile.revision)
				suite.assert_true(result.ok, "real semantic lesson action prepares: " + str(definition.lesson_id) + " " + str(result))
				if result.ok:
					suite.assert_equal(profile, before, "observation preparation never mutates profile")
					profile = result.context.candidate
					suite.assert_true(not runtime.prepare_observation(profile, receipt, profile.revision).ok, "same semantic receipt cannot count twice")
		suite.assert_true(profile.tutorial_state.completed_lessons.has(definition.lesson_id), "each of ten lessons completes through semantic actions")
	suite.assert_equal(profile.tutorial_state.completed_lessons.size(), 10, "all ten authored lessons are reachable")
	suite.assert_equal(profile.chronos_shards, 1000, "normal lessons grant no progression currency")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(profile))
	suite.assert_equal(runtime.progress_view(parsed), runtime.progress_view(profile), "physical JSON preserves counts and completion")
	var before := profile.duplicate(true)
	var replay: Dictionary = runtime.replay("movement_dodge")
	suite.assert_true(replay.ok and replay.context.lesson.lesson_id == "movement_dodge", "completed lesson can be recalled without changing profile")
	suite.assert_equal(profile, before, "replay preview grants no reward and modifies no durable progress")


func _test_training_and_hints(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := Fixtures.profile(catalog)
	var action_sequence := 0
	for action: String in ["move", "dash", "weapon_primary", "time_slot_1", "boss_conversion", "weapon_skill"]:
		action_sequence += 1
		var result: Dictionary = runtime.prepare_observation(profile, _receipt(action, "training_drill", 1, action_sequence), profile.revision)
		suite.assert_true(result.ok, "actual training semantic action prepares")
		if result.ok:
			profile = result.context.candidate
	suite.assert_equal(profile.chronos_shards, 1056, "six first-completion rewards grant exactly 3+5+5+8+15+20")
	for definition: Dictionary in _entries():
		if definition.definition_kind == "training_task":
			suite.assert_true(profile.completed_command_ids.has("training-claim:" + str(definition.task_id)), "each authored training task has one permanent claim")
	for action: String in ["move", "dash", "weapon_primary", "time_slot_1", "boss_conversion", "weapon_skill"]:
		action_sequence += 1
		var result: Dictionary = runtime.prepare_observation(profile, _receipt(action, "training_drill", 1, action_sequence), profile.revision)
		suite.assert_true(result.ok, "practice remains repeatable after first reward")
		if result.ok:
			profile = result.context.candidate
	suite.assert_equal(profile.chronos_shards, 1056, "repeat drills never pay twice")
	var hint: Dictionary
	for definition: Dictionary in _entries():
		if definition.id == "hint_tip_003":
			hint = definition
	for index: int in range(4):
		var receipt := _receipt("", "hub", 1, index + 1)
		receipt.trigger_ids = [hint.trigger_id]
		var result: Dictionary = runtime.prepare_observation(profile, receipt, profile.revision)
		suite.assert_true(result.ok, "distinct trusted hint condition prepares")
		if result.ok:
			suite.assert_equal(result.context.hints.size(), 1 if index < 3 else 0, "hint respects exact authored maximum displays")
			profile = result.context.candidate
	var history_size: int = profile.completed_command_ids.size()
	for sequence: int in range(5, 105):
		var result: Dictionary = runtime.prepare_observation(profile, _receipt("interact", "hub", 1, sequence), profile.revision)
		suite.assert_true(result.ok, "idle semantic receipts remain supported")
		if result.ok:
			profile = result.context.candidate
	suite.assert_equal(profile.completed_command_ids.size(), history_size, "watermark replaces one token instead of accumulating per-action history")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(profile))
	suite.assert_true(not runtime.prepare_observation(parsed, _receipt("interact", "hub", 1, 104), parsed.revision).ok, "hint/action dedup survives physical JSON")
	var next: Dictionary = runtime.prepare_observation(profile, _receipt("interact", "hub", 2, 1), profile.revision)
	suite.assert_true(next.ok, "new trusted Hub session starts at action one")
	if next.ok:
		profile = next.context.candidate
	suite.assert_true(not runtime.prepare_observation(profile, _receipt("interact", "hub", 1, 105), profile.revision).ok, "retired Hub session cannot append unseen actions")


func _test_skip_and_guided(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := Fixtures.profile(catalog)
	var before := profile.duplicate(true)
	var result: Dictionary = runtime.prepare_command(profile, {"command_id": "skip", "kind": "tutorial_skip", "lesson_id": "movement_dodge"}, 0)
	suite.assert_true(result.ok, "lessons can be skipped without a payment or assisted launch")
	if result.ok:
		profile = result.context.candidate
	suite.assert_equal(profile.chronos_shards, before.chronos_shards, "skip cannot spend or mint shards")
	suite.assert_equal(profile.tutorial_state.guided_runs_completed, 0, "skip does not silently enable assistance")
	suite.assert_true(not runtime.prepare_command(profile, {"command_id": "skip-again", "kind": "tutorial_skip", "lesson_id": "movement_dodge"}, profile.revision).ok, "duplicate skip changes no profile state")
	result = runtime.prepare_command(profile, {"command_id": "suppress", "kind": "tutorial_suppress", "suppressed": true}, profile.revision)
	suite.assert_true(result.ok, "suppression is a durable binary command")
	if result.ok:
		profile = result.context.candidate
	var receipt := _receipt("interact", "hub", 1, 1)
	receipt.trigger_ids = ["first_training_entry"]
	result = runtime.prepare_observation(profile, receipt, profile.revision)
	suite.assert_true(result.ok and result.context.hints.is_empty(), "suppressed hints do not display or consume a seen marker")
	if result.ok:
		profile = result.context.candidate
	suite.assert_true(profile.tutorial_state.seen_hints.is_empty(), "suppression preserves unseen hints for later recall")
	for sequence: int in range(1, 4):
		var normal: Dictionary = runtime.guided_launch_projection(profile, false)
		suite.assert_true(normal.ok and not normal.context.projection.assisted and normal.context.projection.ranked_eligible, "normal mode is available immediately")
		var projection: Dictionary = runtime.guided_launch_projection(profile, true)
		suite.assert_true(projection.ok, "explicit assisted launch is available for next authored run")
		if projection.ok:
			suite.assert_equal(projection.context.projection.incoming_damage_multiplier, [0.8, 0.9, 1.0][sequence - 1], "guided damage policy is exact")
			suite.assert_equal(projection.context.projection.warning_scale, [1.25, 1.10, 1.0][sequence - 1], "guided warning policy is exact")
			suite.assert_true(not projection.context.projection.ranked_eligible, "all assisted runs exclude ranked/challenge eligibility")
		profile.launch_sequence = sequence
		profile.last_settlement_receipt = {"schema_id": "meta_settlement_receipt_v1", "sequence": sequence, "run_id": "guided-" + str(sequence), "terminal_reason": "death", "shards": 0, "imprints": 0, "soul_reserve": 0, "digest": "a".repeat(64)}
		var completion := {"run_id": "guided-" + str(sequence), "launch_sequence": sequence, "guided_sequence": sequence, "terminal_reason": "death"}
		result = runtime.prepare_guided_completion(profile, completion, profile.revision)
		suite.assert_true(result.ok, "matching authentic guided terminal run completes once")
		if result.ok:
			profile = result.context.candidate
			suite.assert_true(not runtime.prepare_guided_completion(profile, completion, profile.revision).ok, "one terminal guided run cannot increment twice")
			if sequence < 3:
				var forged_next := completion.duplicate(true)
				forged_next.guided_sequence += 1
				suite.assert_true(not runtime.prepare_guided_completion(profile, forged_next, profile.revision).ok, "same terminal cannot masquerade as the next guided run")
	suite.assert_true(not runtime.guided_launch_projection(profile, true).ok, "a fourth guided run is unavailable")
	suite.assert_true(runtime.guided_launch_projection(profile, false).ok, "normal launch remains available after guided program")


func _test_malformed_progress(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var fresh := Fixtures.profile(catalog)
	for marker: String in ["onboarding-progress:lesson:movement_dodge:move:4", "onboarding-progress:lesson:movement_dodge:move:01", "onboarding-progress:hint:TIP-003:0", "onboarding-watermark:online:1:1", "onboarding-watermark:hub:1:01", "onboarding-progress:lesson:fake:move:1", "training-claim:T-99"]:
		var corrupt := fresh.duplicate(true)
		corrupt.completed_command_ids = [marker]
		var before := corrupt.duplicate(true)
		suite.assert_true(not runtime.progress_view(corrupt).ok, "unknown, noncanonical or out-of-bounds progress refuses: " + marker)
		suite.assert_equal(corrupt, before, "malformed progress cannot mutate the profile")
	var duplicate := fresh.duplicate(true)
	duplicate.completed_command_ids = ["onboarding-watermark:hub:1:1", "onboarding-watermark:hub:2:1"]
	suite.assert_true(not runtime.progress_view(duplicate).ok, "same context has only one current watermark")
	var incomplete := fresh.duplicate(true)
	incomplete.completed_command_ids = ["onboarding-progress:lesson:movement_dodge:dash:1", "onboarding-progress:lesson:movement_dodge:move:3", "onboarding-watermark:normal_run:1:4"]
	suite.assert_true(not runtime.progress_view(incomplete).ok, "full counters without matching completed lesson refuse")
	var contradictory := fresh.duplicate(true)
	contradictory.tutorial_state.completed_lessons = ["movement_dodge"]
	contradictory.completed_command_ids = ["onboarding-progress:lesson:movement_dodge:move:1", "onboarding-watermark:normal_run:1:1"]
	suite.assert_true(not runtime.progress_view(contradictory).ok, "partial native counter contradicting completed lesson refuses")
	for prefix: String in ["onboarding-progress:", "onboarding-watermark:", "training-claim:"]:
		suite.assert_true(not runtime.prepare_command(fresh, {"command_id": prefix + "fake", "kind": "tutorial_skip", "lesson_id": "movement_dodge"}, 0).ok, "public command cannot forge tutorial namespace")
	var receipt := _receipt("move", "normal_run", 1, 1)
	suite.assert_true(not runtime.prepare_observation(fresh, receipt, 0).ok, "a normal-run receipt requires the matching active launch")
	var malformed := _entries()
	malformed[0].receipt_requirements[0].extra_reward = 100
	suite.assert_true(not runtime.configure(malformed, catalog).ok, "unknown nested content effects refuse")
	suite.assert_true(not runtime.progress_view(fresh).ok, "failed configuration cannot retain stale tutorial content")


func _test_receipt_boundaries(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := _active_profile(catalog)
	suite.assert_true(not runtime.progress_view({}).ok, "empty profile refuses without creating fresh progress")
	var premature_guided := {"run_id": "tutorial-run", "launch_sequence": 1, "guided_sequence": 1, "terminal_reason": "death"}
	suite.assert_true(not runtime.prepare_guided_completion(profile, premature_guided, profile.revision).ok, "active launch cannot authenticate an early guided terminal claim")
	var observed: Dictionary = runtime.prepare_observation(profile, _receipt("move", "normal_run", 1, 1), 0)
	suite.assert_true(observed.ok, "first movement prepares partial progress")
	if not observed.ok:
		return
	profile = observed.context.candidate
	var before := profile.duplicate(true)
	suite.assert_true(not runtime.prepare_observation(profile, _receipt("move", "normal_run", 1, 2), 0).ok, "stale revision refuses before counting action")
	suite.assert_true(not runtime.prepare_observation(profile, _receipt("move", "hub", 1, 1), profile.revision).ok, "Hub receipt cannot advance while launch is active")
	var foreign := _receipt("move", "normal_run", 1, 2)
	foreign.run_id = "other-run"
	suite.assert_true(not runtime.prepare_observation(profile, foreign, profile.revision).ok, "foreign run cannot count lesson actions")
	for triggers: Array in [["first_hostile", "first_hostile"], ["not-authored"]]:
		var bad := _receipt("move", "normal_run", 1, 2)
		bad.trigger_ids = triggers
		suite.assert_true(not runtime.prepare_observation(profile, bad, profile.revision).ok, "duplicate and unknown triggers refuse")
	suite.assert_equal(profile, before, "receipt refusals preserve profile")
	observed = runtime.prepare_observation(profile, _receipt("move", "normal_run", 1, 50), profile.revision)
	suite.assert_true(observed.ok, "authenticated sequence gaps remain observable")
	if observed.ok:
		profile = observed.context.candidate
		var decoded: Dictionary = runtime.progress_view(profile)
		suite.assert_equal(decoded.context.counters["lesson:movement_dodge:move"], 2, "sequence gaps grant only one actual observation")
	var skipped: Dictionary = runtime.prepare_command(profile, {"command_id": "skip-partial", "kind": "tutorial_skip", "lesson_id": "movement_dodge"}, profile.revision)
	suite.assert_true(skipped.ok, "partial lesson may be skipped")
	if skipped.ok:
		profile = skipped.context.candidate
		for marker: String in profile.completed_command_ids:
			suite.assert_true(not marker.begins_with("onboarding-progress:lesson:movement_dodge:"), "skip retires partial counters")
	var legacy := Fixtures.profile(catalog)
	legacy.tutorial_state.completed_lessons = ["movement_dodge"]
	legacy.tutorial_state.seen_hints = ["TIP-003"]
	legacy.completed_command_ids = ["training-claim:T-01"]
	suite.assert_true(runtime.progress_view(legacy).ok, "legacy completion and hint exhaustion remain readable without native counters")
	var hint := _receipt("", "hub", 1, 1)
	hint.trigger_ids = ["health_below_half"]
	observed = runtime.prepare_observation(legacy, hint, legacy.revision)
	suite.assert_true(observed.ok and observed.context.hints.is_empty(), "legacy seen hint does not reappear without its old display count")
	var corrupted := profile.duplicate(true)
	corrupted.tutorial_state.completed_lessons = ["movement_dodge"]
	suite.assert_true(not runtime.progress_view(corrupted).ok, "completed and skipped objectives cannot overlap")
	var guided := Fixtures.profile(catalog)
	guided.launch_sequence = 2
	guided.completed_command_ids = ["onboarding-progress:guided:1:1"]
	suite.assert_true(not runtime.progress_view(guided).ok, "guided watermark must agree with completed program count")
	var capacity := _active_profile(catalog)
	capacity.chronos_shards = 2147483647
	capacity.active_launch_receipt.clear()
	capacity.completed_command_ids = ["onboarding-progress:task:T-01:move:1", "onboarding-watermark:training_drill:1:1"]
	suite.assert_true(not runtime.prepare_observation(capacity, _receipt("dash", "training_drill", 1, 2), capacity.revision).ok, "training currency overflow refuses candidate")


func _test_catalog_boundaries(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	for kind: String in ["duplicate_sequence", "late_prerequisite", "unknown_action", "unknown_context", "reward_mint", "assisted_power", "extra_hint", "default_assistance", "malformed_sequence"]:
		var rows := _entries()
		match kind:
			"duplicate_sequence": rows[1].sequence = rows[0].sequence
			"late_prerequisite": rows[0].prerequisite_lesson_ids = [rows[1].lesson_id]
			"unknown_action": rows[0].receipt_requirements[0].action_id = "grant_currency"
			"unknown_context": rows[0].receipt_requirements[0].context_id = "online"
			"reward_mint": rows[25].reward.chronos_shards = 100
			"assisted_power": rows[31].incoming_damage_multiplier = 0.0
			"extra_hint": rows[10].maximum_displays = 100
			"default_assistance": rows[31].default_enabled = true
			"malformed_sequence": rows[31].sequence = {}
		suite.assert_true(not runtime.configure(rows, catalog).ok, "closed tutorial catalog refuses " + kind)
		suite.assert_true(not runtime.progress_view(Fixtures.profile(catalog)).ok, "bad catalog clears prior usable runtime")
		suite.assert_true(runtime.configure(_entries(), catalog).ok, "valid definitions can reconfigure after refusal")


func _test_all_hints(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := Fixtures.profile(catalog)
	var sequence := 0
	for hint: Dictionary in _entries():
		if hint.definition_kind != "hint":
			continue
		for display: int in range(int(hint.maximum_displays) + 1):
			sequence += 1
			var receipt := _receipt("", "hub", 1, sequence)
			receipt.trigger_ids = [hint.trigger_id]
			var result: Dictionary = runtime.prepare_observation(profile, receipt, profile.revision)
			suite.assert_true(result.ok, "every authored hint reaches its finite display budget")
			if result.ok:
				suite.assert_equal(result.context.hints.size(), 1 if display < int(hint.maximum_displays) else 0, "exact hint budget applies to " + str(hint.hint_id))
				profile = result.context.candidate
	suite.assert_equal(profile.tutorial_state.seen_hints.size(), 15, "all fifteen hints are reachable")
	suite.assert_equal(profile.chronos_shards, 1000, "hints never change reward currency")


func _entries() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/tutorial_definitions.json"))


func _active_profile(catalog: RefCounted) -> Dictionary:
	var profile := Fixtures.profile(catalog)
	profile.launch_sequence = 1
	profile.active_launch_receipt = {"schema_id": "meta_launch_receipt_v1", "sequence": 1, "run_id": "tutorial-run", "difficulty": "normal", "seed": 73, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["rewind", "stop"], "projection_digest": "a".repeat(64)}
	return profile


func _receipt(action_id: String, context_id: String, session: int, action_sequence: int) -> Dictionary:
	return {"run_id": "tutorial-run" if context_id == "normal_run" else "", "session_sequence": session, "action_sequence": action_sequence, "action_id": action_id, "context_id": context_id, "trigger_ids": []}
