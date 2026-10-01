extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SaveResultScript := preload("res://scripts/save/save_result.gd")
const SaveMigrationRegistryScript := preload("res://scripts/save/save_migration_registry.gd")

const LEGACY_FIXTURE_PATH := "res://tests/fixtures/save/legacy_v0.json"
const MIGRATED_FIXTURE_PATH := "res://tests/fixtures/save/migration_expected_v1.json"

var _nondeterministic_counter: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_registration_requires_adjacent_versions(suite)
	_test_adjacent_steps_run_in_order(suite)
	_test_source_and_step_inputs_are_isolated(suite)
	_test_nondeterministic_steps_fail_closed(suite)
	_test_missing_and_forward_paths_are_rejected(suite)
	_test_legacy_v0_migrates_to_v1(suite)
	_test_legacy_v0_migrates_through_v2_defaults(suite)
	_test_default_v1_to_v2_adds_runtime_defaults(suite)
	_test_default_v1_to_v2_preserves_valid_runtime_state(suite)
	_test_default_v1_to_v2_rejects_malformed_runtime_state(suite)
	suite.finish(get_tree())


func _test_registration_requires_adjacent_versions(suite) -> void:
	var registry = SaveMigrationRegistryScript.new(false)
	var gap = registry.register_migration(0, 2, Callable(self, "_step_zero_to_one"))
	suite.assert_true(not gap.ok, "migration registry rejects version gaps")
	suite.assert_equal(gap.code, &"INVALID_ARGUMENT", "version gaps are invalid arguments")

	var first = registry.register_migration(0, 1, Callable(self, "_step_zero_to_one"))
	suite.assert_true(first.ok, "adjacent migration registration succeeds")
	var duplicate = registry.register_migration(0, 1, Callable(self, "_step_zero_to_one"))
	suite.assert_true(not duplicate.ok, "duplicate source migrations are rejected")


func _test_adjacent_steps_run_in_order(suite) -> void:
	var registry = SaveMigrationRegistryScript.new(false)
	registry.register_migration(0, 1, Callable(self, "_step_zero_to_one"))
	registry.register_migration(1, 2, Callable(self, "_step_one_to_two"))

	var result = registry.migrate({"schema_version": 0, "trace": []}, 2)
	suite.assert_true(result.ok, "complete adjacent migration chain succeeds")
	if not result.ok:
		return
	suite.assert_equal(result.payload.get("schema_version"), 2, "migration reaches requested schema")
	suite.assert_equal(result.payload.get("trace"), ["0-1", "1-2"], "migration steps execute in order")
	suite.assert_equal(result.metadata.get("step_zero"), true, "first migration metadata is retained")
	suite.assert_equal(result.metadata.get("step_one"), true, "second migration metadata is retained")
	suite.assert_equal(result.migrated_from, 0, "result records original schema")
	suite.assert_equal(result.migrated_to, 2, "result records final schema")


func _test_source_and_step_inputs_are_isolated(suite) -> void:
	var registry = SaveMigrationRegistryScript.new(false)
	registry.register_migration(0, 1, Callable(self, "_mutating_step"))
	var source := {
		"schema_version": 0,
		"nested": {"values": ["original"]},
	}
	var context := {"nested": {"value": "context-original"}}

	var result = registry.migrate(source, 1, context)
	suite.assert_true(result.ok, "mutating migration succeeds against isolated inputs")
	suite.assert_equal(source["nested"]["values"], ["original"], "migration never mutates source document")
	suite.assert_equal(context["nested"]["value"], "context-original", "migration never mutates caller context")
	if result.ok:
		var migrated: Dictionary = result.payload
		migrated["nested"]["values"].append("result-mutated")
		suite.assert_equal(source["nested"]["values"], ["original"], "result payload is isolated from source")


func _test_nondeterministic_steps_fail_closed(suite) -> void:
	_nondeterministic_counter = 0
	var registry = SaveMigrationRegistryScript.new(false)
	registry.register_migration(0, 1, Callable(self, "_nondeterministic_step"))

	var result = registry.migrate({"schema_version": 0}, 1)
	suite.assert_true(not result.ok, "nondeterministic migration is rejected")
	suite.assert_equal(result.code, &"MIGRATION_FAILED", "nondeterminism is a migration failure")
	suite.assert_equal(result.metadata.get("from_version"), 0, "failure identifies source step")
	suite.assert_equal(result.metadata.get("to_version"), 1, "failure identifies target step")


func _test_missing_and_forward_paths_are_rejected(suite) -> void:
	var registry = SaveMigrationRegistryScript.new(false)
	var missing = registry.migrate({"schema_version": 0}, 1)
	suite.assert_true(not missing.ok, "missing migration path fails")
	suite.assert_equal(missing.code, &"MIGRATION_UNAVAILABLE", "missing path has explicit result code")

	var forward = registry.migrate({"schema_version": 2}, 1)
	suite.assert_true(not forward.ok, "newer save cannot be migrated backwards")
	suite.assert_equal(forward.code, &"FORWARD_VERSION", "newer save uses forward-version refusal")


func _test_legacy_v0_migrates_to_v1(suite) -> void:
	var legacy := _read_json(LEGACY_FIXTURE_PATH, suite)
	var expected := _read_json(MIGRATED_FIXTURE_PATH, suite)
	if legacy.is_empty() or expected.is_empty():
		return
	var original := legacy.duplicate(true)
	var registry = SaveMigrationRegistryScript.new()

	var result = registry.migrate(legacy, 1, {
		"profile_id": "slot_1",
		"save_domain": "base",
	})
	suite.assert_true(result.ok, "legacy v0 profile migrates to schema v1")
	suite.assert_equal(legacy, original, "legacy migration preserves source fixture")
	if not result.ok:
		return
	suite.assert_equal(result.source_kind, &"legacy_v0", "legacy result records source kind")
	suite.assert_equal(result.migrated_from, 0, "legacy result records v0 source")
	suite.assert_equal(result.migrated_to, 1, "legacy result records v1 target")
	suite.assert_equal(result.payload.get("schema_version"), 1, "legacy migration emits schema v1 state")
	suite.assert_equal(result.payload.get("payload"), expected.get("payload"), "legacy progress matches v1 fixture payload")
	var expected_settings := {
		"locale": "en",
		"master_volume": 0.4,
		"master_muted": true,
		"music_volume": 0.8,
		"sfx_volume": 0.9,
		"dialogue_volume": 0.9,
		"camera_shake_enabled": false,
		"hit_flash_enabled": false,
		"reduced_motion": true,
		"text_scale": 1.0,
		"high_contrast_danger": false,
		"subtitles_enabled": true,
		"subtitle_scale": 1.0,
		"ranged_charge_mode": "hold",
		"damage_received_multiplier": 1.0,
		"enemy_telegraph_scale": 1.0,
	}
	suite.assert_equal(
		result.metadata.get("settings_payload"),
		expected_settings,
		"legacy global settings are separated and expanded with Current defaults"
	)
	suite.assert_true(not result.payload.get("payload", {}).has("settings"), "profile payload excludes global settings")


func _test_default_v1_to_v2_adds_runtime_defaults(suite) -> void:
	var source := {
		"schema_version": 1,
		"payload": {
			"profile_id": "slot_1",
			"progress": {"runs_completed": 3},
		},
	}
	var original := source.duplicate(true)
	var registry = SaveMigrationRegistryScript.new()

	var first = registry.migrate(source, 2)
	var second = registry.migrate(source, 2)
	_suite_result_ok(suite, first, "schema v1 profile migrates to v2")
	_suite_result_ok(suite, second, "schema v1 migration is repeatable")
	suite.assert_equal(source, original, "schema v1 migration preserves the caller-owned document")
	if not first.ok or not second.ok:
		return
	suite.assert_equal(first.to_dictionary(), second.to_dictionary(), "schema v1 migration is deterministic")
	suite.assert_equal(first.payload.get("schema_version"), 2, "schema v1 migration emits schema v2")
	var payload := first.payload.get("payload", {}) as Dictionary
	suite.assert_equal(
		payload.get("active_item_state"),
		_empty_active_item_state(),
		"schema v2 adds an explicit empty active-item state"
	)
	suite.assert_equal(
		payload.get("reward_effect_state"),
		{},
		"schema v2 adds an explicit empty reward-effect state"
	)
	suite.assert_equal(
		payload.get("progress"),
		{"runs_completed": 3},
		"schema v2 preserves unrelated profile progress"
	)


func _test_legacy_v0_migrates_through_v2_defaults(suite) -> void:
	var legacy := _read_json(LEGACY_FIXTURE_PATH, suite)
	if legacy.is_empty():
		return
	var original := legacy.duplicate(true)
	var result = SaveMigrationRegistryScript.new().migrate(legacy, 2)
	_suite_result_ok(suite, result, "legacy v0 profile migrates through schema v2")
	suite.assert_equal(legacy, original, "multi-step default migration preserves legacy source")
	if not result.ok:
		return
	suite.assert_equal(result.migrated_from, 0, "multi-step default migration records v0 source")
	suite.assert_equal(result.migrated_to, 2, "multi-step default migration records v2 target")
	var payload := result.payload.get("payload", {}) as Dictionary
	suite.assert_equal(
		payload.get("active_item_state"),
		_empty_active_item_state(),
		"legacy chain receives the explicit empty active-item default"
	)
	suite.assert_equal(payload.get("reward_effect_state"), {}, "legacy chain receives reward defaults")


func _test_default_v1_to_v2_preserves_valid_runtime_state(suite) -> void:
	var active_state := _empty_active_item_state()
	var reward_state := _reward_effect_state()
	var source := {
		"schema_version": 1,
		"payload": {
			"active_item_state": active_state.duplicate(true),
			"reward_effect_state": reward_state.duplicate(true),
		},
	}
	var result = SaveMigrationRegistryScript.new().migrate(source, 2)
	_suite_result_ok(suite, result, "schema v1 preserves valid explicit runtime fields")
	if not result.ok:
		return
	var payload := result.payload.get("payload", {}) as Dictionary
	suite.assert_equal(payload.get("active_item_state"), active_state, "valid active state is preserved")
	suite.assert_equal(payload.get("reward_effect_state"), reward_state, "valid reward state is preserved")
	(payload["reward_effect_state"] as Dictionary)["mutated"] = true
	suite.assert_true(
		not (source["payload"] as Dictionary)["reward_effect_state"].has("mutated"),
		"migrated runtime defaults do not alias caller-owned dictionaries"
	)


func _test_default_v1_to_v2_rejects_malformed_runtime_state(suite) -> void:
	for invalid_case: Dictionary in [
		{"label": "active item wrong type", "field": "active_item_state", "value": []},
		{"label": "active item malformed dictionary", "field": "active_item_state", "value": {}},
		{"label": "reward effect wrong type", "field": "reward_effect_state", "value": []},
		{"label": "reward effect unknown fields", "field": "reward_effect_state", "value": {"unknown": true}},
	]:
		var payload := {}
		payload[invalid_case["field"]] = invalid_case["value"]
		var source := {"schema_version": 1, "payload": payload}
		var original := source.duplicate(true)
		var result = SaveMigrationRegistryScript.new().migrate(source, 2)
		suite.assert_true(not result.ok, "%s fails closed" % invalid_case["label"])
		suite.assert_equal(result.code, &"MIGRATION_FAILED", "%s has a typed migration failure" % invalid_case["label"])
		suite.assert_equal(source, original, "%s preserves the source document" % invalid_case["label"])


func _empty_active_item_state() -> Dictionary:
	return {
		"schema_version": 1,
		"configured": false,
		"definition": {},
		"generation": 0,
		"next_token": 1,
		"current_frame": -1,
		"cooldown_end_frame": -1,
		"handler_state": {},
		"committed_receipts": {},
	}


func _reward_effect_state() -> Dictionary:
	return {
		"schema_version": 1,
		"stats": {
			"max_hp": 100.0,
			"attack": 10.0,
			"defense": 0.0,
			"move_speed": 200.0,
			"attack_speed": 1.0,
			"crit_chance": 0.05,
			"crit_multiplier": 1.5,
			"time_energy_max": 100.0,
			"time_energy_regen": 2.0,
		},
		"health": {
			"current_hp": 100.0,
			"max_hp": 100.0,
			"defense": 0.0,
			"healing_multiplier": 1.0,
			"dead": false,
			"invulnerable": false,
			"invulnerability_token": 0,
			"reward_invulnerability_tokens": [],
			"reward_invulnerability_remaining": {},
		},
		"time": {
			"energy": 100.0,
			"max_energy": 100.0,
			"resource_revision": 1,
			"time_stop_duration_bonus": 0.0,
			"time_stop_cost_multiplier": 1.0,
			"time_stop_weakpoint_damage_bonus": 0.0,
			"time_stop_weakpoint_duration": 0.0,
			"time_stop_self_damage": 0.0,
			"rewind_cost_multiplier": 1.0,
			"rewind_heal": 0.0,
			"rewind_echo_enabled": false,
			"rewind_path_hit_multiplier": 0.0,
			"rewind_self_damage": 0.0,
			"time_rift_cost_multiplier": 1.0,
			"time_rift_duration_bonus": 0.0,
			"time_rift_radius_bonus": 0.0,
			"time_rift_slow_bonus": 0.0,
			"time_accelerate_cost_multiplier": 1.0,
			"time_accelerate_duration_bonus": 0.0,
			"time_accelerate_multiplier_bonus": 0.0,
			"low_energy_regen_multiplier": 1.0,
			"low_energy_threshold": 30.0,
		},
		"weapon": {"modifiers": {}, "runtime": {}},
		"character": {"dash_invulnerable_bonus": 0.0},
	}


func _suite_result_ok(suite, result, message: String) -> void:
	suite.assert_true(result.ok, "%s: %s" % [message, str(result.to_dictionary())])


func _step_zero_to_one(document: Dictionary, _context: Dictionary):
	var migrated := document.duplicate(true)
	var trace: Array = migrated.get("trace", []).duplicate()
	trace.append("0-1")
	migrated["trace"] = trace
	migrated["schema_version"] = 1
	return SaveResultScript.success(migrated, {"step_zero": true})


func _step_one_to_two(document: Dictionary, _context: Dictionary):
	var migrated := document.duplicate(true)
	var trace: Array = migrated.get("trace", []).duplicate()
	trace.append("1-2")
	migrated["trace"] = trace
	migrated["schema_version"] = 2
	return SaveResultScript.success(migrated, {"step_one": true})


func _mutating_step(document: Dictionary, context: Dictionary):
	document["nested"]["values"].append("step-mutated")
	context["nested"]["value"] = "step-mutated"
	document["schema_version"] = 1
	return SaveResultScript.success(document)


func _nondeterministic_step(document: Dictionary, _context: Dictionary):
	_nondeterministic_counter += 1
	var migrated := document.duplicate(true)
	migrated["schema_version"] = 1
	migrated["nonce"] = _nondeterministic_counter
	return SaveResultScript.success(migrated)


func _read_json(path: String, suite) -> Dictionary:
	if not FileAccess.file_exists(path):
		suite.assert_true(false, "%s exists" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s is readable" % path)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	suite.assert_true(parsed is Dictionary, "%s parses as an object" % path)
	return parsed as Dictionary if parsed is Dictionary else {}
