extends "res://tests/integration/combat/daily_boss_native_test.gd"

const DailyCatalog := preload("res://scripts/modes/daily_boss_catalog.gd")
const DailySession := preload("res://scripts/modes/daily_boss_session.gd")
const DailyReward := preload("res://scripts/modes/daily_reward_state.gd")
const DailyRules := preload("res://scripts/community/local_run_record_rules.gd")


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	for schema: int in [1, 2]:
		await _migrate_physical(schema)
	_suite.finish(get_tree())


func _migrate_physical(schema: int) -> void:
	var fixture := _daily_fixture("condition-migration-%d" % schema)
	var catalog := DailyCatalog.new()
	catalog.configure(_registry)
	var state := DailySession.empty(catalog.legacy_fingerprint())
	var current_day := catalog.day_index(_clock)
	for day: int in range(current_day - 20, current_day):
		var run := DailySession.run_id("daily_owner", day, 1)
		var source := "daily-" + run.sha256_text().substr(0, 40)
		var result := {"attempt": 1, "run_id": run, "status": "VICTORY", "elapsed_frames": 120, "remaining_hp_milli": 100000, "hostile_source_id": source, "death_receipt": "hostile_defeat:" + (run + "|" + source).sha256_text().substr(0, 40), "native_digest": "a".repeat(64), "damage_events": 1}
		state.days.append({"day_index": day, "day_key": catalog.projection_for_day(day).day_key, "attempts": 1, "results": [result], "best": result.duplicate(true)})
		state.reward_state = DailyReward.award(state.reward_state, day, "VICTORY", 1)
	var old_definition: Dictionary = catalog.call("_projection_for_day", current_day, true)
	state.days.append({"day_index": current_day, "day_key": old_definition.day_key, "attempts": 1, "results": [], "best": {}})
	state.latest_day = current_day
	state.active = {"day_index": current_day, "attempt": 1, "run_id": DailySession.run_id("daily_owner", current_day, 1), "definition": old_definition.duplicate(true), "elapsed_frames": 17, "damage_events": 3}
	var expected_wallet: Dictionary = state.reward_state.duplicate(true)
	if schema == 1:
		state.schema_version = 1
		state.erase("archived_rewards")
		state.erase("reward_state")
		state.active.erase("damage_events")
		for day: Dictionary in state.days:
			for result: Dictionary in day.results:
				result.erase("damage_events")
			day.best = DailySession.best(day.results)
	else:
		var purchase := DailyReward.purchase(state.reward_state, "daily_weapon_skin")
		_suite.assert_true(purchase.ok, "old-schema2 migration fixture owns a legitimately purchased reward")
		state.reward_state = purchase.state
		expected_wallet = state.reward_state.duplicate(true)
	var identity: Dictionary = fixture.service.local_record_storage_identity()
	var id := "daily_" + DailyRules.canonical({"profile_id": identity.profile_id, "save_domain": identity.save_domain, "content_snapshot": identity.content_snapshot, "mode_fingerprint": catalog.legacy_fingerprint()}).sha256_text().substr(0, 26)
	var storage := Save.new()
	_suite.assert_true(storage.configure(fixture.root.path_join("daily"), "0.4.0-dev", identity.content_snapshot).ok and storage.save_profile(id, "local", {"daily_session": state}).ok, "actual legacy condition fingerprint saves physically")
	var old_primary: Dictionary = storage.inspect_profile(id, "local").payload.duplicate(true)
	var flow := _daily_flow(fixture)
	_suite.assert_equal(flow.snapshot().schema_version, 2, "actual old physical aggregate migrates to current schema")
	_suite.assert_equal(flow.snapshot().mode_fingerprint, catalog.fingerprint(), "actual old physical aggregate binds new condition fingerprint")
	_suite.assert_equal(flow.snapshot().active.definition, old_definition, "interrupted legacy challenge retains exact admitted Boss and Build")
	_suite.assert_true(not flow.start().ok and flow.preview().remaining_attempts == 2, "migration cannot refund or duplicate the admitted legacy attempt")
	_suite.assert_equal(flow.snapshot().reward_state, expected_wallet, "migration preserves authenticated wallet purchases and entitlements")
	_suite.assert_equal(storage.inspect_profile(id, "local").payload, old_primary, "new fingerprint migration retains the original physical rollback point")
	_suite.assert_true(flow.abandon().ok, "migrated cold legacy admission resolves once through authentic abandonment")
	_suite.assert_true(flow.start().ok, "resolved legacy admission permits next current native challenge")
	_suite.assert_equal(flow.snapshot().active.definition, catalog.projection(_clock), "next admission uses the current eight-condition calendar")
	_suite.assert_true(flow.abandon().ok, "current native attempt settles after legacy upgrade")
	var accepted: Dictionary = flow.snapshot()
	await _daily_dispose(flow)
	flow = _daily_flow(fixture)
	_suite.assert_equal(flow.snapshot(), accepted, "current physical aggregate cold-reloads without replaying migration")
	_suite.assert_equal(flow.preview().remaining_attempts, 1, "physical upgrade and reload preserve both consumed attempts")
	await _daily_dispose(flow)
