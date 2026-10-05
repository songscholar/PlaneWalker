extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Catalog := preload("res://scripts/modes/daily_boss_catalog.gd")
const Session := preload("res://scripts/modes/daily_boss_session.gd")
const Reward := preload("res://scripts/modes/daily_reward_state.gd")


func _ready() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var catalog := Catalog.new()
	suite.assert_true(catalog.configure(registry), "production daily catalog configures")
	var state := Session.empty(catalog.fingerprint())
	suite.assert_equal(state.schema_version, 2, "daily physical aggregate has explicit reward schema")
	if int(state.schema_version) != 2:
		suite.finish(get_tree())
		return
	for day: int in range(65):
		var result := _result(day, "VICTORY", 0)
		state.days.append({"day_index": day, "day_key": catalog.projection_for_day(day).day_key, "attempts": 1, "results": [result], "best": result.duplicate(true)})
		state.latest_day = day
		state.reward_state = Reward.award(state.reward_state, day, "VICTORY", 0)
		Session.trim_archive(state)
	suite.assert_true(Session.valid(state, catalog, "daily-rewards"), "rolling history retains authenticated lifetime accounting")
	suite.assert_equal(state.days.size(), 31, "daily results remain bounded")
	suite.assert_equal(state.reward_state.tokens, 65, "archive rollover does not erase credits")
	var proof: Dictionary = Session.validated_reward_aggregate({"daily_session": state}, "daily-rewards", catalog.fingerprint(), registry)
	suite.assert_true(proof.ok and proof.lifetime_victories == 65 and proof.entitlement_ids.has("eternal_traveler"), "shared reward authority reads a physical aggregate proof")
	var forged := state.duplicate(true)
	forged.days[0].results[0].damage_events = 1
	forged.days[0].best = forged.days[0].results[0].duplicate(true)
	forged.reward_state.tokens += 1
	suite.assert_true(not Session.valid(forged, catalog, "daily-rewards"), "aggregate rejects reward totals detached from terminal results")
	var legacy := {"schema_version": 1, "mode_fingerprint": catalog.fingerprint(), "latest_day": 4, "days": [], "active": {}}
	var old_result := _result(4, "VICTORY", 0)
	old_result.erase("damage_events")
	legacy.days.append({"day_index": 4, "day_key": catalog.projection_for_day(4).day_key, "attempts": 1, "results": [old_result], "best": old_result.duplicate(true)})
	var migrated: Dictionary = Session.migrate(legacy, catalog, "daily-rewards")
	suite.assert_true(migrated.ok and migrated.state.reward_state.gold == 50 and migrated.state.reward_state.perfect_day == -1, "legacy victory migrates once without inventing flawless evidence")
	suite.finish(get_tree())


func _result(day: int, status: String, damages: int) -> Dictionary:
	var run := Session.run_id("daily-rewards", day, 1)
	var source := "daily-" + run.sha256_text().substr(0, 40)
	return {"attempt": 1, "run_id": run, "status": status, "elapsed_frames": 60, "remaining_hp_milli": 100000, "hostile_source_id": source, "death_receipt": "hostile_defeat:" + (run + "|" + source).sha256_text().substr(0, 40), "native_digest": "a".repeat(64), "damage_events": damages}
