extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")
const RunViewStateProjectorScript := preload("res://scripts/application/run_view_state_projector.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_live_view_revision_is_independent(suite)
	_test_phase_flags_and_optional_payloads(suite)
	_test_new_run_resets_view_revision(suite)
	_test_invalid_inputs_are_rejected(suite)
	suite.finish(get_tree())


func _test_live_view_revision_is_independent(suite) -> void:
	var projector = RunViewStateProjectorScript.new()
	var authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	var player := _player_snapshot()
	var first = projector.project(authoritative, _room_definition(1, "combat"), player, null, 60000, {})
	suite.assert_true(first.ok, "combat runtime projects a valid view state")
	if not first.ok:
		return
	var first_view: Dictionary = first.context["view_state"]
	suite.assert_true(RunViewStateScript.validate(first_view).ok, "projected combat view validates")
	suite.assert_equal(first_view["revision"], 0, "first view revision begins at zero")
	suite.assert_equal(first_view["phase"], "COMBAT_ACTIVE", "numeric run phase maps to the view contract")
	suite.assert_equal(first_view["room"]["index"], 1, "authoritative room index projects")
	suite.assert_equal(first_view["build"]["archetype_scores"], {"time_stop_burst": 2}, "build archetypes map to view scores")

	player["hp"] = 120.0
	player["energy"] = 45.0
	player["time_slots"][0]["cooldown"] = 3.5
	var second = projector.project(authoritative, _room_definition(1, "combat"), player, null, 61000, {})
	suite.assert_true(second.ok, "live player changes project under the same authoritative revision")
	var second_view: Dictionary = second.context["view_state"]
	suite.assert_equal(second_view["revision"], 1, "view revision advances independently")
	suite.assert_equal(authoritative["revision"], 7, "projection never mutates authoritative revision")
	suite.assert_close(second_view["player"]["hp"], 120.0, "live hp projects")
	suite.assert_equal(
		second_view["player"]["time_slots"],
		[
			{"ability_id": "stop", "action_id": "time_stop", "cooldown": 3.5},
			{"ability_id": "rift", "action_id": "time_rift", "cooldown": 4.5},
		],
		"equipped slot order and strict action mapping project"
	)
	suite.assert_equal(second_view["run_time_ms"], 61000, "live run time projects")

	second.context["view_state"]["player"]["hp"] = 1.0
	second.context["view_state"]["player"]["time_slots"][0]["ability_id"] = "changed"
	second.context["view_state"]["player"]["time_slots"].reverse()
	second.context["view_state"]["build"]["items"].append("forged")
	var latest: Dictionary = projector.latest_view_state()
	suite.assert_close(latest["player"]["hp"], 120.0, "returned context is isolated from projector state")
	suite.assert_equal(latest["player"]["time_slots"][0]["ability_id"], "stop", "projected slot dictionaries are deep copied")
	suite.assert_equal(latest["player"]["time_slots"][1]["ability_id"], "rift", "projected slot order is isolated")
	suite.assert_true(not latest["build"]["items"].has("forged"), "nested build arrays are deep copied")
	suite.assert_equal(player["time_slots"][0]["ability_id"], "stop", "projection never mutates player slot input")


func _test_phase_flags_and_optional_payloads(suite) -> void:
	var projector = RunViewStateProjectorScript.new()
	var selection_state := _authoritative(RunPhaseScript.Value.SELECTION_ACTIVE)
	selection_state["open_offer"] = {
		"schema_version": 1,
		"offer_id": "view-offer",
		"revision": 7,
		"category": "item",
		"title_key": "UI_CHOOSE_REWARD",
		"can_skip": false,
		"options": [],
	}
	var selection = projector.project(selection_state, _room_definition(1, "combat"), _player_snapshot(), null, 62000, {})
	suite.assert_true(selection.ok, "selection phase projects")
	if not selection.ok:
		return
	var selection_view: Dictionary = selection.context["view_state"]
	suite.assert_true(selection_view["ui_flags"]["show_hud"], "selection keeps the HUD visible")
	suite.assert_true(not selection_view["ui_flags"]["accept_gameplay_input"], "selection blocks gameplay input")
	suite.assert_equal(selection_view["selection"]["offer_id"], "view-offer", "selection payload projects")

	var paused_state := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	paused_state["suspended"] = true
	var paused = projector.project(paused_state, _room_definition(2, "combat"), _player_snapshot(), null, 63000, {"show_pause": true})
	var paused_view: Dictionary = paused.context["view_state"]
	suite.assert_true(paused_view["ui_flags"]["show_pause"], "pause flag projects")
	suite.assert_true(not paused_view["ui_flags"]["accept_gameplay_input"], "suspension blocks gameplay input")

	var boss_state := _authoritative(RunPhaseScript.Value.BOSS_ACTIVE)
	boss_state["current_room"] = 5
	var boss = projector.project(
		boss_state,
		_room_definition(5, "boss"),
		_player_snapshot(),
		_boss_snapshot(),
		360000,
		{}
	)
	suite.assert_true(boss.ok, "boss phase projects")
	var boss_view: Dictionary = boss.context["view_state"]
	suite.assert_equal(boss_view["boss"]["phase_index"], 2, "boss phase index projects")
	suite.assert_true(boss_view["ui_flags"]["accept_gameplay_input"], "active boss phase accepts input")

	var terminal_state := _authoritative(RunPhaseScript.Value.DEFEAT)
	terminal_state["result"] = {"result": "death", "rooms_cleared": 1}
	var terminal = projector.project(terminal_state, _room_definition(1, "combat"), _player_snapshot(), null, 64000, {})
	var terminal_view: Dictionary = terminal.context["view_state"]
	suite.assert_true(not terminal_view["ui_flags"]["show_hud"], "terminal phase hides combat HUD")
	suite.assert_true(not terminal_view["ui_flags"]["accept_gameplay_input"], "terminal phase blocks input")
	suite.assert_equal(terminal_view["result"]["result"], "death", "terminal result projects")


func _test_new_run_resets_view_revision(suite) -> void:
	var projector = RunViewStateProjectorScript.new()
	var first = projector.project(_authoritative(RunPhaseScript.Value.COMBAT_ACTIVE), _room_definition(1, "combat"), _player_snapshot(), null, 1, {})
	suite.assert_true(first.ok, "first run projects before revision assertions")
	if not first.ok:
		return
	suite.assert_equal(first.context["view_state"]["revision"], 0, "first run starts at view revision zero")
	var next_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	next_authoritative["run_id"] = "view-run-two"
	var second = projector.project(next_authoritative, _room_definition(1, "combat"), _player_snapshot(), null, 1, {})
	suite.assert_true(second.ok, "second run projects before revision assertions")
	if not second.ok:
		return
	suite.assert_equal(second.context["view_state"]["revision"], 0, "new run id resets the view revision baseline")
	suite.assert_equal(projector.latest_view_state()["run_id"], "view-run-two", "latest state belongs to the new run")


func _test_invalid_inputs_are_rejected(suite) -> void:
	var projector = RunViewStateProjectorScript.new()
	var missing_run_id := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	missing_run_id["run_id"] = ""
	var invalid_run = projector.project(missing_run_id, _room_definition(1, "combat"), _player_snapshot(), null, 0, {})
	suite.assert_equal(invalid_run.code, &"INVALID_ARGUMENT", "empty run id is rejected")
	suite.assert_equal(invalid_run.context.get("field", ""), "authoritative.run_id", "invalid run reports its field")

	var invalid_player := _player_snapshot()
	invalid_player["hp"] = 999.0
	var invalid_view = projector.project(_authoritative(RunPhaseScript.Value.COMBAT_ACTIVE), _room_definition(1, "combat"), invalid_player, null, 0, {})
	suite.assert_equal(invalid_view.code, &"INVALID_ARGUMENT", "invalid projected player state is rejected")
	suite.assert_true(projector.latest_view_state().is_empty(), "failed projection does not replace the latest valid view")

	var mismatched_slot := _player_snapshot()
	mismatched_slot["time_slots"][1]["action_id"] = "time_rewind"
	var invalid_slot = projector.project(_authoritative(RunPhaseScript.Value.COMBAT_ACTIVE), _room_definition(1, "combat"), mismatched_slot, null, 0, {})
	suite.assert_equal(invalid_slot.code, &"INVALID_ARGUMENT", "projector rejects canonical/action slot mismatches")
	suite.assert_true(projector.latest_view_state().is_empty(), "invalid slot projection does not replace projector state")


func _authoritative(phase: int) -> Dictionary:
	return {
		"schema_version": 1,
		"run_id": "view-run",
		"revision": 7,
		"phase": phase,
		"suspended": false,
		"run_seed": 20260929,
		"current_room": 1,
		"room_total": 5,
		"run_time_ms": 0,
		"build": {
			"items": ["frozen_burst"],
			"blessings": ["bls_stop_weakpoint"],
			"curses": [],
			"talents": [],
			"reward_history": [],
			"archetypes": {"time_stop_burst": 2},
			"dominant_archetype": "time_stop_burst",
		},
		"open_offer": {},
		"consumed_offer_ids": [],
		"result": {},
		"config": {},
	}


func _room_definition(index: int, room_type: String) -> Dictionary:
	return {
		"room_number": index,
		"type": room_type,
		"reward_kind": "none" if room_type == "boss" else "starter",
	}


func _player_snapshot() -> Dictionary:
	return {
		"hp": 160.0,
		"max_hp": 200.0,
		"energy": 72.0,
		"max_energy": 100.0,
		"action_state": "FREE",
		"time_slots": [
			{"ability_id": "stop", "action_id": "time_stop", "cooldown": 0.0},
			{"ability_id": "rift", "action_id": "time_rift", "cooldown": 4.5},
		],
	}


func _boss_snapshot() -> Dictionary:
	return {
		"boss_id": "chrono_warden",
		"name_key": "BOSS_NAME_CHRONO_WARDEN",
		"hp": 315.0,
		"max_hp": 420.0,
		"phase_index": 2,
		"phase_total": 3,
	}
