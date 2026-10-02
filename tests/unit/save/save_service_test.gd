extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const DraftServiceScript := preload("res://scripts/rewards/draft_service.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const M1RoomPlanScript := preload("res://scripts/dungeon/m1_room_plan.gd")
const RunStateScript := preload("res://scripts/application/run_state.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")

const GAME_VERSION := "0.4.0-dev"
const PROFILE_ID := "slot_1"
const SAVE_DOMAIN := "base"
const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"
const FLOOR_IDS: Array[String] = [
	"floor_ruins_of_remnant",
	"floor_void_forest",
	"floor_time_rift",
	"floor_plane_forge",
	"floor_throne_of_void",
]

var _test_root: String = ""
var _clock_tick: int = 0
var _fault_target: StringName = &""
var _fault_root: String = ""
var _reentrant_service: RefCounted
var _reentrant_result: RefCounted
var _reentrant_attempted: bool = false
var _observed_fault_points: Array[StringName] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_root = _unique_test_root()
	_remove_tree(_test_root)

	_test_first_save_and_settings_isolation(suite)
	_test_v1_profile_and_settings_migrate_on_production_load(suite)
	_test_v2_profile_and_settings_rewrite_to_v3(suite)
	_test_v2_active_launch_runs_rewrite_to_v3(suite)
	_test_native_v3_active_run_round_trip(suite)
	_test_real_consumed_draft_offer_id_round_trip(suite)
	_test_unsafe_active_launch_migration_refuses_recovery(suite)
	_test_floor_plan_digest_corruption_fails_closed(suite)
	await _test_real_launch_player_reward_state_survives_disk_round_trip(suite)
	_test_profile_and_domain_isolation(suite)
	_test_three_save_backup_order(suite)
	_test_all_fault_points_are_stable(suite)
	_test_pending_corruption_fails_before_promotion(suite)
	_test_fault_before_promotion_preserves_primary_and_pending_recovers(suite)
	_test_primary_corruption_recovers_from_backup_one(suite)
	_test_backup_two_recovery_and_all_corrupt_result(suite)
	_test_forward_version_refuses_backup_fallback(suite)
	_test_content_mismatch_refuses_backup_fallback(suite)
	_test_write_reentry_returns_busy(suite)
	_test_path_traversal_is_rejected(suite)

	_remove_tree(_test_root)
	suite.finish(get_tree())


func _test_real_launch_player_reward_state_survives_disk_round_trip(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report: RefCounted = registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], GAME_VERSION, &"LAUNCH")
	suite.assert_true(
		not report.call("has_blocking_errors"),
		"real SaveService fixture loads the Launch Base Pack"
	)
	if report.call("has_blocking_errors"):
		return
	var source := await _spawn_launch_sword_player(registry, suite, 7101)
	var active_definition: Dictionary = registry.call(
		"get_content",
		&"absolute_zero_device"
	)
	suite.assert_true(
		bool(source.call("equip_active_item", active_definition).get("ok", false)),
		"real SaveService fixture equips a configured active item"
	)
	suite.assert_true(
		bool(source.call("activate_equipped_active_item").get("ok", false)),
		"real SaveService fixture commits an active-item receipt"
	)
	var active_state: Dictionary = source.call("active_item_snapshot")
	var committed_receipts := active_state.get("committed_receipts", {}) as Dictionary
	suite.assert_true(
		not committed_receipts.is_empty(),
		"real active-item snapshot contains a committed receipt"
	)
	var reward_state: Dictionary = source.call("reward_effect_snapshot")
	var sword_runtime := (
		(reward_state.get("weapon", {}) as Dictionary).get("runtime", {}) as Dictionary
	)
	var accumulators := sword_runtime.get("resource_regen_frame_accumulators", {}) as Dictionary
	suite.assert_true(
		not accumulators.is_empty(),
		"configured Launch Sword snapshot contains dynamic regen accumulators"
	)
	for resource_id: Variant in accumulators.keys():
		suite.assert_equal(
			typeof(accumulators[resource_id]),
			TYPE_INT,
			"source Sword accumulator %s is an integer" % str(resource_id)
		)

	var service = _new_service(
		"real_launch_player_round_trip",
		_content_snapshot("d"),
		suite
	)
	var saved = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {
		"active_item_state": active_state,
		"reward_effect_state": reward_state,
	})
	suite.assert_true(
		saved.ok,
		"real Launch Player runtime payload writes through SaveService: %s"
		% str(saved.to_dictionary())
	)
	var loaded = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(
		loaded.ok,
		"real Launch Player runtime payload loads from disk: %s"
		% str(loaded.to_dictionary())
	)
	if loaded.ok:
		var loaded_active := loaded.payload.get("active_item_state", {}) as Dictionary
		var loaded_reward := loaded.payload.get("reward_effect_state", {}) as Dictionary
		suite.assert_true(
			bool(source.get("active_item_runtime").call(
				"can_restore_snapshot",
				loaded_active
			)),
			"loaded active-item state remains restorable after JSON scalar normalization"
		)
		var loaded_receipts := loaded_active.get("committed_receipts", {}) as Dictionary
		suite.assert_true(
			not loaded_receipts.is_empty(),
			"committed active-item receipt survives the physical JSON round trip"
		)
		suite.assert_equal(
			((loaded_receipts.get("1", {}) as Dictionary).get("plan", {}) as Dictionary).get(
				"digest"
			),
			((committed_receipts.get("1", {}) as Dictionary).get("plan", {}) as Dictionary).get(
				"digest"
			),
			"committed active-item receipt preserves its authoritative plan digest"
		)
		var loaded_runtime := (
			(loaded_reward.get("weapon", {}) as Dictionary).get("runtime", {}) as Dictionary
		)
		var loaded_accumulators := (
			loaded_runtime.get("resource_regen_frame_accumulators", {}) as Dictionary
		)
		for resource_id: Variant in loaded_accumulators.keys():
			suite.assert_equal(
				typeof(loaded_accumulators[resource_id]),
				TYPE_INT,
				"loaded Sword accumulator %s is normalized to TYPE_INT" % str(resource_id)
			)
		var target := await _spawn_launch_sword_player(registry, suite, 7102)
		suite.assert_true(
			target.call("restore_reward_effect_snapshot", loaded_reward),
			"fresh real Player restores the loaded Sword reward runtime"
		)
		suite.assert_equal(
			target.call("reward_effect_snapshot"),
			reward_state,
			"fresh real Player reproduces the exact pre-save reward snapshot"
		)
		await _free_player(target)
	await _free_player(source)


func _test_v1_profile_and_settings_migrate_on_production_load(suite) -> void:
	var service = _new_service("v1_production_migration", _content_snapshot("f"), suite)
	var profile_saved = service.save_profile(
		PROFILE_ID,
		SAVE_DOMAIN,
		{"runs_completed": 4}
	)
	suite.assert_true(profile_saved.ok, "v2 profile fixture saves before downgrade")
	var legacy_profile := _read_json(
		_profile_path("v1_production_migration", "primary.json"),
		suite
	)
	legacy_profile["schema_version"] = 1
	(legacy_profile["payload"] as Dictionary).erase("active_item_state")
	(legacy_profile["payload"] as Dictionary).erase("reward_effect_state")
	_resign(legacy_profile)
	_write_text(
		_profile_path("v1_production_migration", "primary.json"),
		JSON.stringify(legacy_profile, "", true, true)
	)
	var loaded_profile = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(
		loaded_profile.ok,
		"SaveService production load migrates schema v1 profile: %s" % str(loaded_profile.to_dictionary())
	)
	suite.assert_equal(
		loaded_profile.payload.get("active_item_state"),
		_empty_active_item_state(),
		"production profile migration installs explicit empty active-item state"
	)
	suite.assert_equal(
		loaded_profile.payload.get("reward_effect_state"),
		{},
		"production profile migration installs explicit empty reward-effect state"
	)
	suite.assert_equal(
		loaded_profile.payload.get("active_run_state"),
		{},
		"production profile migration installs explicit empty active-run state"
	)

	var settings_payload := _settings_payload("en", 0.6)
	var settings_saved = service.save_settings(settings_payload)
	suite.assert_true(settings_saved.ok, "v2 settings fixture saves before downgrade")
	var settings_path := _case_root("v1_production_migration").path_join(
		"global/settings/primary.json"
	)
	var legacy_settings := _read_json(settings_path, suite)
	legacy_settings["schema_version"] = 1
	_resign(legacy_settings)
	_write_text(settings_path, JSON.stringify(legacy_settings, "", true, true))
	var loaded_settings = service.load_settings()
	suite.assert_true(
		loaded_settings.ok,
		"SaveService production load migrates schema v1 settings: %s" % str(loaded_settings.to_dictionary())
	)
	suite.assert_equal(
		loaded_settings.payload,
		settings_payload,
		"settings migration preserves the exact settings payload without profile defaults"
	)
	suite.assert_equal(
		_read_json(settings_path, suite).get("schema_version"),
		3.0,
		"production settings migration rewrites the primary as schema v3"
	)


func _test_v2_profile_and_settings_rewrite_to_v3(suite) -> void:
	var service = _new_service("v2_production_migration", _content_snapshot("0"), suite)
	suite.assert_true(service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"runs_completed": 9}).ok, "v3 profile fixture saves before v2 downgrade")
	var profile_path := _profile_path("v2_production_migration", "primary.json")
	var legacy_profile := _read_json(profile_path, suite)
	legacy_profile["schema_version"] = 2
	(legacy_profile["payload"] as Dictionary).erase("active_run_state")
	_resign(legacy_profile)
	_write_text(profile_path, JSON.stringify(legacy_profile, "", true, true))
	var loaded_profile = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(loaded_profile.ok, "schema v2 profile migrates through the production reader")
	suite.assert_equal(loaded_profile.payload.get("active_run_state"), {}, "v2 profile gains no-active-run sentinel")
	suite.assert_equal(_read_json(profile_path, suite).get("schema_version"), 3.0, "migrated profile primary rewrites as schema v3")

	var settings_payload := _settings_payload("zh_CN", 0.55)
	suite.assert_true(service.save_settings(settings_payload).ok, "v3 settings fixture saves before v2 downgrade")
	var settings_path := _case_root("v2_production_migration").path_join("global/settings/primary.json")
	var legacy_settings := _read_json(settings_path, suite)
	legacy_settings["schema_version"] = 2
	_resign(legacy_settings)
	_write_text(settings_path, JSON.stringify(legacy_settings, "", true, true))
	var loaded_settings = service.load_settings()
	suite.assert_true(loaded_settings.ok, "schema v2 settings migrate through the production reader")
	suite.assert_equal(loaded_settings.payload, settings_payload, "v2 settings payload remains lossless")
	suite.assert_equal(_read_json(settings_path, suite).get("schema_version"), 3.0, "migrated settings primary rewrites as schema v3")


func _test_v2_active_launch_runs_rewrite_to_v3(suite) -> void:
	for floor_index: int in [0, 2]:
		var case_name := "v2_active_launch_floor_%d" % floor_index
		var plan := _generated_floor_plan(floor_index)
		suite.assert_true(not plan.is_empty(), "%s generates its complete FloorPlan" % case_name)
		if plan.is_empty():
			continue
		var active_run := _active_run_fixture("LAUNCH", plan)
		var service = _new_service(case_name, _content_snapshot("%x" % (floor_index + 5)), suite)
		suite.assert_true(
			service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"active_run_state": active_run}).ok,
			"%s writes a native v3 setup fixture" % case_name
		)
		var profile_path := _profile_path(case_name, "primary.json")
		var legacy_profile := _read_json(profile_path, suite)
		legacy_profile["schema_version"] = 2
		_resign(legacy_profile)
		_write_text(profile_path, JSON.stringify(legacy_profile, "", true, true))

		var loaded = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
		suite.assert_true(
			loaded.ok,
			"%s migrates a complete active Launch run: %s" % [case_name, str(loaded.to_dictionary())]
		)
		if loaded.ok:
			suite.assert_equal(
				loaded.payload.get("active_run_state"),
				active_run,
				"%s preserves the complete P14 state" % case_name
			)
		suite.assert_equal(
			_read_json(profile_path, suite).get("schema_version"),
			3.0,
			"%s rewrites the migrated primary as schema v3" % case_name
		)


func _test_native_v3_active_run_round_trip(suite) -> void:
	var plan := _generated_floor_plan()
	suite.assert_true(not plan.is_empty(), "SaveService active-run fixture generates a FloorPlan")
	if plan.is_empty():
		return
	var active_run := _active_run_fixture("LAUNCH", plan)
	var service = _new_service("active_run_round_trip", _content_snapshot("3"), suite)
	var saved = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"active_run_state": active_run})
	suite.assert_true(saved.ok, "native v3 active run writes to disk: %s" % str(saved.to_dictionary()))
	var loaded = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(loaded.ok, "native v3 active run loads from disk: %s" % str(loaded.to_dictionary()))
	if loaded.ok:
		suite.assert_equal(loaded.payload.get("active_run_state"), active_run, "active RunState and FloorPlan survive SaveService JSON I/O")


func _test_real_consumed_draft_offer_id_round_trip(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report: RefCounted = registry.load_packs(
		[{"path": "res://data/content_packs/base/pack.json", "required": true}],
		GAME_VERSION,
		&"M1"
	)
	suite.assert_true(not report.has_blocking_errors(), "real DraftService Save fixture loads the M1 Base Pack")
	if report.has_blocking_errors():
		return
	var state = RunStateScript.new()
	state.reset_domain({"milestone": "M1", "seed": 20261002}, "run-save-service-draft")
	state.current_room = 1
	state.revision = 1
	var rooms: Array[Dictionary] = M1RoomPlanScript.definitions()
	var created = DraftServiceScript.new().create_offer(registry, state.snapshot(), rooms[0])
	suite.assert_true(created.ok, "real DraftService creates the persisted offer")
	if not created.ok:
		return
	var offer := created.context.get("offer", {}) as Dictionary
	var offer_id := str(offer.get("offer_id", ""))
	suite.assert_true(offer_id.contains(":"), "production DraftService offer ID uses its composite format")
	state.open_offer = offer.duplicate(true)
	suite.assert_true(state.mark_offer_consumed(offer_id), "RunState records the real consumed offer ID")
	state.open_offer = {}
	var active_run: Dictionary = state.snapshot()
	var service = _new_service("real_draft_offer_round_trip", _content_snapshot("e"), suite)
	var saved = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"active_run_state": active_run})
	suite.assert_true(saved.ok, "consumed DraftService offer writes through SaveService: %s" % str(saved.to_dictionary()))
	var loaded = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(loaded.ok, "consumed DraftService offer reloads through SaveService: %s" % str(loaded.to_dictionary()))
	if loaded.ok:
		suite.assert_equal(
			loaded.payload.get("active_run_state"),
			active_run,
			"DraftService to RunState snapshot remains lossless after disk round trip"
		)


func _test_unsafe_active_launch_migration_refuses_recovery(suite) -> void:
	var service = _new_service("unsafe_active_launch", _content_snapshot("4"), suite)
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "backup"})
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "primary"})
	var primary_path := _profile_path("unsafe_active_launch", "primary.json")
	var legacy := _read_json(primary_path, suite)
	legacy["schema_version"] = 2
	legacy["payload"]["active_run_state"] = _legacy_active_run("LAUNCH")
	_resign(legacy)
	var legacy_bytes := JSON.stringify(legacy, "", true, true)
	_write_text(primary_path, legacy_bytes)

	var result = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(result.code, &"MIGRATION_UNSAFE_ACTIVE_RUN", "unsafe active Launch migration keeps its public typed failure")
	suite.assert_true(result.player_notice_required, "unsafe active Launch migration requires a player notice")
	suite.assert_equal(_read_text(primary_path), legacy_bytes, "unsafe active Launch bytes remain untouched")
	suite.assert_equal(_quarantine_file_count("unsafe_active_launch"), 0, "unsafe migration never quarantines or rolls back to a backup")


func _test_floor_plan_digest_corruption_fails_closed(suite) -> void:
	var plan := _generated_floor_plan()
	if plan.is_empty():
		suite.assert_true(false, "digest corruption fixture generates")
		return
	var service = _new_service("floor_plan_digest_corruption", _content_snapshot("5"), suite)
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"active_run_state": _active_run_fixture("LAUNCH", plan)})
	var primary_path := _profile_path("floor_plan_digest_corruption", "primary.json")
	var corrupted := _read_json(primary_path, suite)
	corrupted["payload"]["active_run_state"]["floor_plan"]["generation_digest"] = "0".repeat(64)
	_resign(corrupted)
	_write_text(primary_path, JSON.stringify(corrupted, "", true, true))
	var result = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(result.code, &"CORRUPT", "valid envelope integrity cannot hide FloorPlan digest drift")
	suite.assert_true(_quarantine_file_count("floor_plan_digest_corruption") >= 1, "digest-drifted primary is preserved in quarantine")


func _test_first_save_and_settings_isolation(suite) -> void:
	var service = _new_service("first_save", _content_snapshot("1"), suite)
	var first = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"runs_completed": 1})
	suite.assert_true(first.ok, "first profile save succeeds")
	suite.assert_equal(first.metadata.get("sequence"), 0, "first profile sequence starts at zero")
	suite.assert_true(FileAccess.file_exists(_profile_path("first_save", "primary.json")), "first save creates primary")
	suite.assert_true(not FileAccess.file_exists(_profile_path("first_save", "backup_1.json")), "first save does not invent backup one")

	var loaded = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(loaded.ok, "first profile loads")
	suite.assert_equal(
		loaded.payload,
		_native_profile_payload({"runs_completed": 1.0}),
		"profile payload round trips through canonical JSON with v3 runtime defaults"
	)

	var settings_payload := _settings_payload("en", 0.65)
	settings_payload["text_scale"] = 1.5
	settings_payload["ranged_charge_mode"] = "toggle"
	settings_payload["damage_received_multiplier"] = 0.8
	var settings_saved = service.save_settings(settings_payload)
	suite.assert_true(settings_saved.ok, "global settings save succeeds")
	suite.assert_equal(service.load_settings().payload, settings_payload, "global settings round trip independently")

	var reset = service.reset_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(reset.ok, "profile reset succeeds")
	suite.assert_equal(service.load_profile(PROFILE_ID, SAVE_DOMAIN).code, &"NOT_FOUND", "reset removes only requested profile")
	suite.assert_equal(service.load_settings().payload, settings_payload, "profile reset preserves global settings")

	service.save_settings(_settings_payload("zh_CN", 0.5))
	_write_text(_case_root("first_save").path_join("global/settings/primary.json"), "settings-corrupt")
	var recovered_settings = service.load_settings()
	suite.assert_equal(recovered_settings.code, &"RECOVERED", "global settings use the same recovery policy")
	suite.assert_equal(recovered_settings.source_kind, &"backup_1", "global settings recover from their own backup")
	suite.assert_equal(recovered_settings.payload, settings_payload, "global settings backup retains previous preferences")


func _test_profile_and_domain_isolation(suite) -> void:
	var service = _new_service("scope_isolation", _content_snapshot("d"), suite)
	service.save_profile("slot_1", "base", {"scope": "slot-one-base"})
	service.save_profile("slot_2", "base", {"scope": "slot-two-base"})
	service.save_profile("slot_1", "modded", {"scope": "slot-one-modded"})

	suite.assert_equal(service.load_profile("slot_1", "base").payload.get("scope"), "slot-one-base", "base profile remains isolated")
	suite.assert_equal(service.load_profile("slot_2", "base").payload.get("scope"), "slot-two-base", "second profile remains isolated")
	suite.assert_equal(service.load_profile("slot_1", "modded").payload.get("scope"), "slot-one-modded", "mod domain remains isolated")
	service.reset_profile("slot_1", "modded")
	suite.assert_equal(service.load_profile("slot_1", "modded").code, &"NOT_FOUND", "reset removes only one domain")
	suite.assert_equal(service.load_profile("slot_1", "base").payload.get("scope"), "slot-one-base", "domain reset preserves base save")


func _test_three_save_backup_order(suite) -> void:
	var service = _new_service("backup_order", _content_snapshot("2"), suite)
	for value: int in [1, 2, 3]:
		var result = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": value})
		suite.assert_true(result.ok, "profile save %d succeeds" % value)

	var primary := _read_json(_profile_path("backup_order", "primary.json"), suite)
	var backup_one := _read_json(_profile_path("backup_order", "backup_1.json"), suite)
	var backup_two := _read_json(_profile_path("backup_order", "backup_2.json"), suite)
	suite.assert_equal(primary.get("sequence"), 2.0, "third save is primary sequence two")
	suite.assert_equal(primary.get("payload", {}).get("value"), 3.0, "primary contains newest payload")
	suite.assert_equal(backup_one.get("sequence"), 1.0, "backup one contains previous sequence")
	suite.assert_equal(backup_one.get("payload", {}).get("value"), 2.0, "backup one contains second payload")
	suite.assert_equal(backup_two.get("sequence"), 0.0, "backup two contains oldest retained sequence")
	suite.assert_equal(backup_two.get("payload", {}).get("value"), 1.0, "backup two contains first payload")

	_write_text(_profile_path("backup_order", "backup_2.json"), "corrupt-oldest-backup")
	suite.assert_true(service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 4}).ok, "save proceeds after quarantining corrupt backup two")
	suite.assert_true(_quarantine_contains("backup_order", "corrupt-oldest-backup"), "corrupt rotation destination is preserved")
	suite.assert_equal(_read_json(_profile_path("backup_order", "backup_2.json"), suite).get("payload", {}).get("value"), 2.0, "verified backup one replaces quarantined backup two")


func _test_all_fault_points_are_stable(suite) -> void:
	_observed_fault_points.clear()
	var service = _new_service("fault_points", _content_snapshot("e"), suite, Callable(self, "_record_fault"))
	var saved = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 1})
	suite.assert_true(saved.ok, "fault observation save succeeds")
	suite.assert_equal(_observed_fault_points, [
		&"after_pending_write",
		&"after_pending_verify",
		&"after_backup_2",
		&"after_backup_1",
		&"before_primary_promote",
		&"after_primary_promote",
	], "fault injector receives every stable transaction point in order")


func _test_pending_corruption_fails_before_promotion(suite) -> void:
	_fault_root = _case_root("pending_corruption")
	var service = _new_service("pending_corruption", _content_snapshot("3"), suite, Callable(self, "_corrupt_pending_fault"))
	var result = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 1})
	suite.assert_true(not result.ok, "corrupt pending transaction fails")
	suite.assert_true(result.code in [&"CORRUPT", &"IO_ERROR"], "corrupt pending returns a structured persistence failure")
	suite.assert_true(not FileAccess.file_exists(_profile_path("pending_corruption", "primary.json")), "corrupt pending is never promoted")


func _test_fault_before_promotion_preserves_primary_and_pending_recovers(suite) -> void:
	var service = _new_service("pending_recovery", _content_snapshot("4"), suite)
	suite.assert_true(service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "old"}).ok, "recovery fixture primary saves")

	_fault_target = &"before_primary_promote"
	service.set_fault_injector(Callable(self, "_targeted_fault"))
	var failed = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "pending"})
	suite.assert_true(not failed.ok, "injected pre-promotion fault fails the transaction")
	suite.assert_equal(_read_json(_profile_path("pending_recovery", "primary.json"), suite).get("payload", {}).get("value"), "old", "pre-promotion fault preserves old primary")
	suite.assert_equal(_read_json(_profile_path("pending_recovery", "pending.tmp"), suite).get("payload", {}).get("value"), "pending", "verified pending remains recoverable")

	service.set_fault_injector(Callable())
	_write_text(_profile_path("pending_recovery", "primary.json"), "primary-corrupt")
	var recovered = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(recovered.ok, "corrupt primary recovers")
	suite.assert_equal(recovered.code, &"RECOVERED", "pending recovery is reported")
	suite.assert_equal(recovered.source_kind, &"pending", "pending is first recovery candidate")
	suite.assert_equal(recovered.payload.get("value"), "pending", "pending payload is restored")
	suite.assert_true(_quarantine_contains("pending_recovery", "primary-corrupt"), "corrupt primary bytes are quarantined exactly")


func _test_primary_corruption_recovers_from_backup_one(suite) -> void:
	var service = _new_service("backup_one_recovery", _content_snapshot("5"), suite)
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 1})
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 2})
	_write_text(_profile_path("backup_one_recovery", "primary.json"), "{bad-json")

	var inspected = service.inspect_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(inspected.code, &"CORRUPT", "inspection reports corruption without recovery")
	suite.assert_true(FileAccess.file_exists(_profile_path("backup_one_recovery", "primary.json")), "inspection is non-destructive")

	var recovered = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(recovered.code, &"RECOVERED", "backup one recovery is reported")
	suite.assert_equal(recovered.source_kind, &"backup_1", "backup one is selected after absent pending")
	suite.assert_equal(recovered.payload.get("value"), 1.0, "backup one payload is restored")
	suite.assert_true(SaveEnvelopeScript.validate(_read_json(_profile_path("backup_one_recovery", "primary.json"), suite), &"profile", PROFILE_ID, SAVE_DOMAIN).ok, "repaired primary is verified")


func _test_backup_two_recovery_and_all_corrupt_result(suite) -> void:
	var service = _new_service("backup_two_recovery", _content_snapshot("6"), suite)
	for value: int in [1, 2, 3]:
		service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": value})
	_write_text(_profile_path("backup_two_recovery", "primary.json"), "broken-primary")
	_write_text(_profile_path("backup_two_recovery", "backup_1.json"), "broken-backup-one")

	var recovered = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(recovered.code, &"RECOVERED", "backup two recovery is reported")
	suite.assert_equal(recovered.source_kind, &"backup_2", "backup two is final recovery candidate")
	suite.assert_equal(recovered.payload.get("value"), 1.0, "backup two payload is restored")
	suite.assert_true(_quarantine_file_count("backup_two_recovery") >= 2, "each corrupt candidate is quarantined")

	var all_corrupt = _new_service("all_corrupt", _content_snapshot("7"), suite)
	for value: int in [1, 2, 3]:
		all_corrupt.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": value})
	for file_name: String in ["primary.json", "backup_1.json", "backup_2.json"]:
		_write_text(_profile_path("all_corrupt", file_name), "corrupt-%s" % file_name)
	var failed = all_corrupt.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(failed.code, &"CORRUPT", "all corrupt candidates fail closed")
	suite.assert_true(_quarantine_file_count("all_corrupt") >= 3, "all corrupt candidates are preserved in quarantine")


func _test_forward_version_refuses_backup_fallback(suite) -> void:
	var service = _new_service("forward_refusal", _content_snapshot("8"), suite)
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "backup"})
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "primary"})
	var future := _read_json(_profile_path("forward_refusal", "primary.json"), suite)
	future["schema_version"] = 4
	_write_text(_profile_path("forward_refusal", "primary.json"), JSON.stringify(future, "", true, true))

	var result = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(result.code, &"FORWARD_VERSION", "future primary is refused explicitly")
	suite.assert_true(FileAccess.file_exists(_profile_path("forward_refusal", "primary.json")), "future primary is not quarantined")
	suite.assert_equal(_quarantine_file_count("forward_refusal"), 0, "future primary never triggers backup rollback")


func _test_content_mismatch_refuses_backup_fallback(suite) -> void:
	var service = _new_service("content_refusal", _content_snapshot("9"), suite)
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "backup"})
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "primary"})
	var incompatible = _new_service("content_refusal", _content_snapshot("a"), suite)

	var result = incompatible.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(result.code, &"CONTENT_MISMATCH", "incompatible content snapshot is refused")
	suite.assert_equal(result.metadata.get("actual_aggregate"), _content_snapshot("9").get("aggregate_sha256"), "mismatch reports stored aggregate")
	suite.assert_equal(_quarantine_file_count("content_refusal"), 0, "content mismatch never triggers backup rollback")


func _test_write_reentry_returns_busy(suite) -> void:
	_reentrant_service = _new_service("write_reentry", _content_snapshot("b"), suite, Callable(self, "_reentrant_fault"))
	_reentrant_result = null
	_reentrant_attempted = false
	var outer = _reentrant_service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "outer"})
	suite.assert_true(outer.ok, "outer write succeeds after reentry probe")
	suite.assert_true(_reentrant_result != null, "fault callback attempted a nested write")
	if _reentrant_result != null:
		suite.assert_equal(_reentrant_result.code, &"BUSY", "nested write is rejected as busy")
	suite.assert_equal(_reentrant_service.load_profile(PROFILE_ID, SAVE_DOMAIN).payload.get("value"), "outer", "busy nested write cannot replace outer payload")


func _test_path_traversal_is_rejected(suite) -> void:
	var service = _new_service("path_safety", _content_snapshot("c"), suite)
	suite.assert_equal(service.save_profile("../slot", SAVE_DOMAIN, {}).code, &"INVALID_ARGUMENT", "profile traversal is rejected")
	suite.assert_equal(service.save_profile(PROFILE_ID, "../mod", {}).code, &"INVALID_ARGUMENT", "domain traversal is rejected")
	suite.assert_equal(service.load_profile("/absolute", SAVE_DOMAIN).code, &"INVALID_ARGUMENT", "absolute profile id is rejected")
	suite.assert_true(not DirAccess.dir_exists_absolute(_case_root("path_safety").path_join("profiles")), "invalid ids cause no profile filesystem access")


func _new_service(case_name: String, snapshot: Dictionary, suite, fault_injector: Callable = Callable()):
	var service = SaveServiceScript.new()
	var configured = service.configure(
		_case_root(case_name),
		GAME_VERSION,
		snapshot,
		Callable(self, "_clock"),
		fault_injector
	)
	suite.assert_true(configured.ok, "%s service configures" % case_name)
	return service


func _spawn_launch_sword_player(
	registry: RefCounted,
	suite,
	seed_value: int
) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	suite.assert_true(
		player.call("configure_loadout", {
			"schema_version": 1,
			"milestone": "LAUNCH",
			"character_id": "wanderer",
			"character_profile": registry.call(
				"resolve_character_runtime_profile",
				&"wanderer",
				&"LAUNCH"
			),
			"character_talents": [],
			"weapon_id": "sword",
			"weapon_profile": registry.call(
				"resolve_weapon_runtime_profile",
				&"sword",
				&"LAUNCH"
			),
			"enabled_time_skills": [&"rift", &"rewind"],
			"difficulty": "normal",
			"seed": seed_value,
		}),
		"real SaveService Launch Sword fixture configures"
	)
	return player


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _clock() -> String:
	var minute := _clock_tick % 60
	var hour := 8 + int(_clock_tick / 60)
	_clock_tick += 1
	return "2026-09-28T%02d:%02d:00Z" % [hour, minute]


func _content_snapshot(fill_character: String) -> Dictionary:
	var packs: Array = [{
		"pack_id": "base",
		"pack_version": GAME_VERSION,
		"schema_version": 1,
		"fingerprint_sha256": fill_character.repeat(64),
	}]
	return {
		"aggregate_sha256": SaveEnvelopeScript.content_snapshot_digest(packs),
		"packs": packs,
	}


func _settings_payload(locale: String, volume: float) -> Dictionary:
	return {
		"locale": locale,
		"master_volume": volume,
		"master_muted": false,
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": false,
	}


func _corrupt_pending_fault(point: StringName) -> bool:
	if point == &"after_pending_write":
		_write_text(_fault_root.path_join("profiles").path_join(PROFILE_ID).path_join(SAVE_DOMAIN).path_join("pending.tmp"), "{")
	return false


func _targeted_fault(point: StringName) -> bool:
	return point == _fault_target


func _reentrant_fault(point: StringName) -> bool:
	if point == &"after_pending_write" and not _reentrant_attempted:
		_reentrant_attempted = true
		_reentrant_result = _reentrant_service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "nested"})
	return false


func _record_fault(point: StringName) -> bool:
	_observed_fault_points.append(point)
	return false


func _unique_test_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("save_service_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])


func _case_root(case_name: String) -> String:
	return _test_root.path_join(case_name)


func _profile_path(case_name: String, file_name: String) -> String:
	return _case_root(case_name).path_join("profiles").path_join(PROFILE_ID).path_join(SAVE_DOMAIN).path_join(file_name)


func _quarantine_directory(case_name: String) -> String:
	return _profile_path(case_name, "quarantine")


func _quarantine_file_count(case_name: String) -> int:
	var directory_path := _quarantine_directory(case_name)
	if not DirAccess.dir_exists_absolute(directory_path):
		return 0
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return 0
	var count := 0
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			count += 1
		entry = directory.get_next()
	directory.list_dir_end()
	return count


func _quarantine_contains(case_name: String, expected_bytes: String) -> bool:
	var directory_path := _quarantine_directory(case_name)
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			var file := FileAccess.open(directory_path.path_join(entry), FileAccess.READ)
			if file != null:
				var contents := file.get_as_text()
				file.close()
				if contents == expected_bytes:
					directory.list_dir_end()
					return true
		entry = directory.get_next()
	directory.list_dir_end()
	return false


func _write_text(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(contents)
	file.flush()
	file.close()


func _read_json(path: String, suite) -> Dictionary:
	if not FileAccess.file_exists(path):
		suite.assert_true(false, "%s exists" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		suite.assert_true(false, "%s opens" % path)
		return {}
	var contents := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(contents)
	suite.assert_true(parsed is Dictionary, "%s parses as JSON object" % path)
	return parsed as Dictionary if parsed is Dictionary else {}


func _resign(document: Dictionary) -> void:
	var unsigned := document.duplicate(true)
	unsigned.erase("integrity")
	unsigned = JSON.parse_string(JSON.stringify(unsigned, "", true, true))
	document["integrity"] = {
		"algorithm": "sha256",
		"digest": SaveEnvelopeScript.sha256_digest(unsigned),
	}


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


func _native_profile_payload(values: Dictionary) -> Dictionary:
	var payload := values.duplicate(true)
	payload["active_item_state"] = _empty_active_item_state()
	payload["reward_effect_state"] = {}
	payload["active_run_state"] = {}
	return payload


func _active_run_fixture(milestone: String, floor_plan: Dictionary) -> Dictionary:
	var floor_index := int(floor_plan.get("floor_index", -1))
	var selected_count := (floor_plan.get("selected_edge_ids", []) as Array).size()
	var completed_floor_ids: Array[String] = []
	for index: int in range(maxi(0, floor_index)):
		completed_floor_ids.append(FLOOR_IDS[index])
	return {
		"schema_version": 1,
		"run_id": "run-save-service-v3",
		"revision": 0,
		"phase": 1,
		"suspended": false,
		"run_seed": int(floor_plan.get("run_seed", 20261001)),
		"current_floor": floor_index + 1 if floor_index >= 0 else 1,
		"current_room": selected_count,
		"room_total": _plan_room_total(floor_plan),
		"run_time_ms": 0,
		"resources": {},
		"stats": {"kills": 0},
		"events": [],
		"build": {},
		"open_offer": {},
		"consumed_offer_ids": [],
		"result": {},
		"config": {"milestone": milestone},
		"current_floor_index": floor_index,
		"floor_plan": floor_plan.duplicate(true),
		"completed_floor_ids": completed_floor_ids,
		"run_economy": {},
		"seen_event_ids": [],
		"merchant_state": {},
		"floor_rule_state": {},
	}


func _legacy_active_run(milestone: String) -> Dictionary:
	var run := _active_run_fixture(milestone, {})
	for field: String in [
		"current_floor_index", "floor_plan", "completed_floor_ids", "run_economy",
		"seen_event_ids", "merchant_state", "floor_rule_state",
	]:
		run.erase(field)
	return run


func _generated_floor_plan(floor_index: int = 0) -> Dictionary:
	var floors := _read_json_array(FLOOR_PATH)
	var templates := _read_json_array(TEMPLATE_PATH)
	if floor_index < 0 or floor_index >= floors.size() or templates.is_empty():
		return {}
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
		20261001, floors[floor_index], templates
	)
	return (generated.get("plan", {}) as Dictionary).duplicate(true)


func _read_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []


func _plan_room_total(plan: Dictionary) -> int:
	if plan.is_empty():
		return 5
	for node_value: Variant in plan.get("nodes", []):
		var node := node_value as Dictionary
		if str(node.get("id", "")) == str(plan.get("boss_node_id", "boss")):
			return int(node.get("layer", 0))
	return 0


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var contents := file.get_as_text()
	file.close()
	return contents


func _remove_tree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			_remove_tree(path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
