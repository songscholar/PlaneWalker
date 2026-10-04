extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SaveResultScript := preload("res://scripts/save/save_result.gd")
const SaveMigrationRegistryScript := preload("res://scripts/save/save_migration_registry.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")

const LEGACY_FIXTURE_PATH := "res://tests/fixtures/save/legacy_v0.json"
const MIGRATED_FIXTURE_PATH := "res://tests/fixtures/save/migration_expected_v1.json"
const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"
const FLOOR_IDS: Array[String] = [
	"floor_ruins_of_remnant",
	"floor_void_forest",
	"floor_time_rift",
	"floor_plane_forge",
	"floor_throne_of_void",
]

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
	_test_default_v2_to_v3_adds_empty_active_run(suite)
	_test_default_v2_to_v3_settings_only_advance_version(suite)
	_test_default_v2_to_v3_adds_m1_dungeon_defaults(suite)
	_test_default_v2_to_v3_preserves_complete_launch_floor_plans(suite)
	_test_legacy_event_history_does_not_invent_runtime(suite)
	_test_default_v2_to_v3_rejects_unsafe_active_launch_run(suite)
	_test_legacy_v0_migrates_through_v3_defaults(suite)
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


func _test_default_v2_to_v3_adds_empty_active_run(suite) -> void:
	var source := {
		"schema_version": 2,
		"document_kind": "profile",
		"payload": {
			"active_item_state": _empty_active_item_state(),
			"reward_effect_state": {},
			"progress": {"runs_completed": 7},
		},
	}
	var original := source.duplicate(true)
	var result = SaveMigrationRegistryScript.new().migrate(source, 3)
	_suite_result_ok(suite, result, "schema v2 profile migrates to v3")
	suite.assert_equal(source, original, "v2 to v3 migration preserves caller-owned input")
	if not result.ok:
		return
	suite.assert_equal(result.payload.get("schema_version"), 3, "v3 migration advances profile schema")
	suite.assert_equal(
		result.payload.get("payload", {}).get("active_run_state"),
		{},
		"v3 installs the explicit no-active-run sentinel"
	)
	suite.assert_equal(
		result.payload.get("payload", {}).get("progress"),
		{"runs_completed": 7},
		"v3 migration preserves unrelated progress"
	)


func _test_default_v2_to_v3_settings_only_advance_version(suite) -> void:
	var source := {
		"schema_version": 2,
		"document_kind": "settings",
		"payload": {"locale": "zh_CN"},
	}
	var result = SaveMigrationRegistryScript.new().migrate(source, 3)
	_suite_result_ok(suite, result, "schema v2 settings migrate to v3")
	if not result.ok:
		return
	suite.assert_equal(result.payload.get("schema_version"), 3, "settings schema advances to v3")
	suite.assert_equal(result.payload.get("payload"), {"locale": "zh_CN"}, "settings payload is lossless")
	suite.assert_true(
		not (result.payload.get("payload", {}) as Dictionary).has("active_run_state"),
		"settings never receive profile run state"
	)


func _test_default_v2_to_v3_adds_m1_dungeon_defaults(suite) -> void:
	var active_run := _legacy_active_run("M1")
	var source := {
		"schema_version": 2,
		"document_kind": "profile",
		"payload": {
			"active_item_state": _empty_active_item_state(),
			"reward_effect_state": {},
			"active_run_state": active_run,
		},
	}
	var result = SaveMigrationRegistryScript.new().migrate(source, 3)
	_suite_result_ok(suite, result, "active M1 run migrates with empty P14 domains")
	if not result.ok:
		return
	var migrated_run := result.payload.get("payload", {}).get("active_run_state", {}) as Dictionary
	suite.assert_equal(migrated_run.get("current_floor_index"), -1, "M1 run receives no Launch floor index")
	suite.assert_equal(migrated_run.get("floor_plan"), {}, "M1 migration never invents a FloorPlan")
	suite.assert_equal(migrated_run.get("completed_floor_ids"), [], "M1 run receives an empty floor prefix")
	suite.assert_equal(migrated_run.get("run_economy"), {}, "M1 run receives an empty economy domain")
	suite.assert_equal(migrated_run.get("seen_event_ids"), [], "M1 run receives an empty event prefix")
	suite.assert_equal(migrated_run.get("merchant_state"), {}, "M1 run receives an empty merchant domain")
	suite.assert_equal(migrated_run.get("floor_rule_state"), {}, "M1 run receives an empty floor-rule domain")
	suite.assert_equal(migrated_run.get("dungeon_event_runtime"), {}, "M1 run receives an empty event-runtime domain")


func _test_default_v2_to_v3_preserves_complete_launch_floor_plans(suite) -> void:
	for fixture: Dictionary in [
		{"milestone": "LAUNCH", "floor_index": 0},
		{"milestone": "LAUNCH", "floor_index": 2},
		{"milestone": "EXPANSION", "floor_index": 0},
		{"milestone": "EXPANSION", "floor_index": 2},
	]:
		var milestone := str(fixture["milestone"])
		var floor_index := int(fixture["floor_index"])
		var label := "v2 %s floor %d" % [milestone, floor_index]
		var plan := _generated_floor_plan(floor_index)
		suite.assert_true(not plan.is_empty(), "%s fixture generates" % label)
		if plan.is_empty():
			continue
		var active_run := _complete_launch_active_run(plan)
		active_run["config"]["milestone"] = milestone
		var source := {
			"schema_version": 2,
			"document_kind": "profile",
			"payload": {
				"active_item_state": _empty_active_item_state(),
				"reward_effect_state": {},
				"active_run_state": active_run.duplicate(true),
			},
		}
		(source["payload"]["active_run_state"] as Dictionary).erase("dungeon_event_runtime")
		var original := source.duplicate(true)
		var result = SaveMigrationRegistryScript.new().migrate(source, 3)
		_suite_result_ok(suite, result, "complete %s migrates to v3" % label)
		suite.assert_equal(source, original, "complete %s preserves source bytes" % label)
		if result.ok:
			suite.assert_equal(
				result.payload.get("payload", {}).get("active_run_state"),
				active_run,
				"complete %s preserves its domains and adds the empty event authority" % label
			)


func _test_legacy_event_history_does_not_invent_runtime(suite) -> void:
	var plan := _generated_floor_plan(2)
	suite.assert_true(not plan.is_empty(), "historical event migration fixture generates")
	if plan.is_empty():
		return
	for milestone: String in ["LAUNCH", "EXPANSION"]:
		for source_version: int in [1, 2]:
			var label := "v%d %s event history" % [source_version, milestone]
			var active_run := _complete_launch_active_run(plan)
			active_run["config"]["milestone"] = milestone
			active_run["seen_event_ids"] = ["event.echo", "event.hidden_cache"]
			active_run.erase("dungeon_event_runtime")
			var source := {
				"schema_version": source_version,
				"document_kind": "profile",
				"payload": {
					"active_item_state": _empty_active_item_state(),
					"reward_effect_state": {},
					"active_run_state": active_run.duplicate(true),
				},
			}
			var original := source.duplicate(true)
			var result = SaveMigrationRegistryScript.new().migrate(source, 3)
			_suite_result_ok(suite, result, "%s migrates to readable legacy v3" % label)
			suite.assert_equal(source, original, "%s preserves source bytes" % label)
			if not result.ok:
				continue
			var migrated_run := result.payload.get("payload", {}).get("active_run_state", {}) as Dictionary
			suite.assert_true(migrated_run == active_run, "%s preserves every historical domain" % label)
			suite.assert_true(
				not migrated_run.has("dungeon_event_runtime"),
				"%s does not invent an empty authority over recorded events" % label
			)


func _test_default_v2_to_v3_rejects_unsafe_active_launch_run(suite) -> void:
	for milestone: String in ["LAUNCH", "EXPANSION"]:
		var active_run := _legacy_active_run(milestone)
		var source := {
			"schema_version": 2,
			"document_kind": "profile",
			"payload": {
				"active_item_state": _empty_active_item_state(),
				"reward_effect_state": {},
				"active_run_state": active_run,
			},
		}
		var original := source.duplicate(true)
		var result = SaveMigrationRegistryScript.new().migrate(source, 3)
		suite.assert_true(not result.ok, "%s run without FloorPlan fails closed" % milestone)
		suite.assert_equal(
			result.code,
			&"MIGRATION_UNSAFE_ACTIVE_RUN",
			"%s unsafe migration has its public typed code" % milestone
		)
		suite.assert_equal(result.metadata.get("from_version"), 2, "unsafe migration identifies source version")
		suite.assert_equal(result.metadata.get("to_version"), 3, "unsafe migration identifies target version")
		suite.assert_true(result.player_notice_required, "unsafe active-run migration requires a player notice")
		suite.assert_equal(source, original, "unsafe migration preserves source bytes")


func _test_legacy_v0_migrates_through_v3_defaults(suite) -> void:
	var legacy := _read_json(LEGACY_FIXTURE_PATH, suite)
	if legacy.is_empty():
		return
	var result = SaveMigrationRegistryScript.new().migrate(legacy, 3)
	_suite_result_ok(suite, result, "legacy v0 profile migrates through schema v3")
	if not result.ok:
		return
	suite.assert_equal(result.migrated_from, 0, "legacy v3 chain records v0 source")
	suite.assert_equal(result.migrated_to, 3, "legacy v3 chain records v3 target")
	suite.assert_equal(
		result.payload.get("payload", {}).get("active_run_state"),
		{},
		"legacy v3 chain installs the no-active-run sentinel"
	)


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


func _legacy_active_run(milestone: String) -> Dictionary:
	return {
		"schema_version": 1,
		"run_id": "legacy_active_run",
		"revision": 3,
		"phase": 2,
		"suspended": false,
		"run_seed": 20261002,
		"current_floor": 1,
		"current_room": 2,
		"room_total": 5,
		"run_time_ms": 12000,
		"resources": {},
		"stats": {"kills": 2},
		"events": [],
		"build": {},
		"open_offer": {},
		"consumed_offer_ids": [],
		"result": {},
		"config": {"milestone": milestone},
	}


func _complete_launch_active_run(plan: Dictionary) -> Dictionary:
	var floor_index := int(plan.get("floor_index", -1))
	var completed_floor_ids: Array[String] = []
	for index: int in range(maxi(0, floor_index)):
		completed_floor_ids.append(FLOOR_IDS[index])
	return {
		"schema_version": 1,
		"run_id": "legacy_active_run",
		"revision": 3,
		"phase": 2,
		"suspended": false,
		"run_seed": int(plan.get("run_seed", 20261002)),
		"current_floor": floor_index + 1,
		"current_room": (plan.get("selected_edge_ids", []) as Array).size(),
		"room_total": _plan_room_total(plan),
		"run_time_ms": 12000,
		"resources": {},
		"stats": {"kills": 2},
		"events": [],
		"build": {},
		"open_offer": {},
		"consumed_offer_ids": [],
		"result": {},
		"config": {"milestone": "LAUNCH"},
		"current_floor_index": floor_index,
		"floor_plan": plan.duplicate(true),
		"completed_floor_ids": completed_floor_ids,
		"run_economy": {},
		"seen_event_ids": [],
		"merchant_state": {},
		"floor_rule_state": {},
		"dungeon_event_runtime": {},
	}


func _generated_floor_plan(floor_index: int) -> Dictionary:
	var floors := _read_json_array(FLOOR_PATH)
	var templates := _read_json_array(TEMPLATE_PATH)
	if floor_index < 0 or floor_index >= floors.size() or templates.is_empty():
		return {}
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
		20261002, floors[floor_index], templates
	)
	return (generated.get("plan", {}) as Dictionary).duplicate(true)


func _plan_room_total(plan: Dictionary) -> int:
	for node_value: Variant in plan.get("nodes", []):
		var node := node_value as Dictionary
		if str(node.get("id", "")) == str(plan.get("boss_node_id", "boss")):
			return int(node.get("layer", 0))
	return 0


func _read_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []


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
