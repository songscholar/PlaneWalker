extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")
const RunViewStateProjectorScript := preload("res://scripts/application/run_view_state_projector.gd")

const M1_ARCHETYPE_SCORES := {
	"freeze_burst": 2,
	"rewind_echo": 0,
	"accelerated_combo": 0,
}
const LAUNCH_ARCHETYPE_SCORES := {
	"freeze_burst": 2,
	"rewind_echo": 0,
	"rift_trap": 0,
	"accelerated_combo": 0,
	"low_hp_void": 0,
	"perfect_guard": 0,
	"piercing_barrage": 0,
	"echo_legion": 0,
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_live_view_revision_is_independent(suite)
	_test_character_presentations_project_to_union(suite)
	_test_weapon_presentations_project_to_union(suite)
	_test_phase_flags_and_optional_payloads(suite)
	_test_new_run_resets_view_revision(suite)
	_test_archetype_projection_contract(suite)
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
	suite.assert_equal(first_view["build"]["archetype_scores"], M1_ARCHETYPE_SCORES, "M1 build archetypes map to the exact view-score domain")
	suite.assert_equal(first_view["character_state"]["character_id"], "time_lord", "character presentation projects")
	suite.assert_equal(first_view["character_state"]["status_id"], "primer", "Time Lord Primer projects as a short status")

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
	suite.assert_equal(
		second_view["weapon_state"],
		{
			"weapon_id": "gun",
			"action_id": "reload",
			"phase": "RESOURCE_ACTION",
			"meter_kind": "reload",
			"meter_current": 28,
			"meter_max": 48,
			"status_id": "perfect_reload",
			"status_stacks": 1,
			"status_remaining": 0,
			"secondary_id": "time_load",
			"secondary_value": 240,
		},
		"Gun reload and Time Load project into the generic weapon union"
	)
	suite.assert_true(not second_view["player"].has("weapon"), "raw weapon presentation is removed from player view data")

	second.context["view_state"]["player"]["hp"] = 1.0
	second.context["view_state"]["player"]["time_slots"][0]["ability_id"] = "changed"
	second.context["view_state"]["player"]["time_slots"].reverse()
	second.context["view_state"]["build"]["items"].append("forged")
	second.context["view_state"]["weapon_state"]["meter_current"] = 0
	var latest: Dictionary = projector.latest_view_state()
	suite.assert_close(latest["player"]["hp"], 120.0, "returned context is isolated from projector state")
	suite.assert_equal(latest["player"]["time_slots"][0]["ability_id"], "stop", "projected slot dictionaries are deep copied")
	suite.assert_equal(latest["player"]["time_slots"][1]["ability_id"], "rift", "projected slot order is isolated")
	suite.assert_true(not latest["build"]["items"].has("forged"), "nested build arrays are deep copied")
	suite.assert_equal(latest["weapon_state"]["meter_current"], 28, "projected weapon state is isolated")
	suite.assert_equal(player["time_slots"][0]["ability_id"], "stop", "projection never mutates player slot input")
	suite.assert_equal(player["weapon"]["runtime"]["reload_frame"], 28, "projection never mutates raw weapon presentation")
	suite.assert_equal(player["character"]["primer_ability_id"], "stop", "projection never mutates raw character presentation")


func _test_character_presentations_project_to_union(suite) -> void:
	var cases: Array[Dictionary] = [
		{"run_id": "wanderer-character-view", "source": _wanderer_character_presentation(), "meter": "path_marks", "status": "anchor"},
		{"run_id": "guardian-character-view", "source": _guardian_character_presentation(), "meter": "ward", "status": "fortress"},
		{"run_id": "void-character-view", "source": _void_character_presentation(), "meter": "void_debt", "status": "corruption"},
		{"run_id": "knight-character-view", "source": _knight_character_presentation(), "meter": "resonance", "status": "echo_pending"},
		{"run_id": "lord-character-view", "source": _time_lord_character_presentation(), "meter": "codex_pages", "status": "primer"},
	]
	var projector = RunViewStateProjectorScript.new()
	for case: Dictionary in cases:
		var authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
		authoritative["run_id"] = case["run_id"]
		var player := _player_snapshot()
		player["character"] = (case["source"] as Dictionary).duplicate(true)
		var result = projector.project(authoritative, _room_definition(1, "combat"), player, null, 1, {})
		suite.assert_true(result.ok, "%s presentation projects" % case["run_id"])
		if result.ok:
			var state: Dictionary = result.context["view_state"]["character_state"]
			suite.assert_equal(state["meter_kind"], case["meter"], "%s meter projects" % case["run_id"])
			suite.assert_equal(state["status_id"], case["status"], "%s status projects" % case["run_id"])
			suite.assert_true(RunViewStateScript.validate(result.context["view_state"]).ok, "%s union validates" % case["run_id"])

	var m1_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	m1_authoritative["run_id"] = "m1-character-view"
	var m1_player := _player_snapshot()
	m1_player["character"] = {"runtime_kind": "wanderer_m1_compat"}
	var m1_result = projector.project(m1_authoritative, _room_definition(1, "combat"), m1_player, null, 1, {})
	suite.assert_true(m1_result.ok, "M1 compatibility character presentation projects")
	if m1_result.ok:
		suite.assert_equal(m1_result.context["view_state"]["character_state"], null, "M1 compatibility keeps the character HUD hidden")

	var invalid_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	invalid_authoritative["run_id"] = "invalid-character-view"
	var invalid_player := _player_snapshot()
	invalid_player["character"]["primer_ability_id"] = "time_stop"
	var invalid_result = projector.project(invalid_authoritative, _room_definition(1, "combat"), invalid_player, null, 1, {})
	suite.assert_equal(invalid_result.code, &"INVALID_ARGUMENT", "invalid Primer presentation is rejected")


func _test_weapon_presentations_project_to_union(suite) -> void:
	var projector = RunViewStateProjectorScript.new()
	var bow_player := _player_snapshot()
	bow_player["weapon"] = _bow_weapon_presentation()
	var bow_result = projector.project(
		_authoritative(RunPhaseScript.Value.COMBAT_ACTIVE),
		_room_definition(1, "combat"),
		bow_player,
		null,
		1,
		{}
	)
	suite.assert_true(bow_result.ok, "Bow presentation projects")
	if bow_result.ok:
		var bow_state: Dictionary = bow_result.context["view_state"]["weapon_state"]
		suite.assert_equal(bow_state["weapon_id"], "bow", "Bow union keeps canonical weapon id")
		suite.assert_equal(bow_state["meter_kind"], "charge", "Bow union uses charge meter")
		suite.assert_equal(bow_state["meter_current"], 30.0, "Bow union projects charge frames")
		suite.assert_equal(bow_state["meter_max"], 48.0, "Bow union projects maximum charge")
		suite.assert_equal(bow_state["status_id"], "charging", "Bow hold projects charging status")
		suite.assert_equal(bow_state["secondary_id"], "hold", "Bow exposes bounded hold progress")
	for neutral_phase: String in ["ACTIVE", "RECOVERY"]:
		var neutral_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
		neutral_authoritative["run_id"] = "bow-neutral-%s-view-run" % neutral_phase.to_lower()
		var neutral_bow_player := _player_snapshot()
		var neutral_bow := _bow_weapon_presentation()
		neutral_bow["action_id"] = "temporal_arrow"
		neutral_bow["phase"] = neutral_phase
		neutral_bow["charge_frames"] = 0.0
		neutral_bow["full_charge"] = false
		neutral_bow["runtime"]["action_id"] = "temporal_arrow"
		neutral_bow["runtime"]["phase"] = neutral_phase
		neutral_bow["runtime"]["charge_frames"] = 0.0
		neutral_bow["runtime"]["full_charge"] = false
		neutral_bow_player["weapon"] = neutral_bow
		var neutral_result = projector.project(
			neutral_authoritative,
			_room_definition(1, "combat"),
			neutral_bow_player,
			null,
			2,
			{}
		)
		suite.assert_true(neutral_result.ok, "Bow %s presentation projects through RunViewState" % neutral_phase)
		if neutral_result.ok:
			var neutral_view: Dictionary = neutral_result.context["view_state"]
			var neutral_state: Dictionary = neutral_view["weapon_state"]
			suite.assert_equal(neutral_state["status_id"], "acting", "Bow %s uses neutral acting status" % neutral_phase)
			suite.assert_equal(neutral_state["status_stacks"], 0, "Bow %s neutral acting status has zero stacks" % neutral_phase)
			suite.assert_true(RunViewStateScript.validate(neutral_view).ok, "Bow %s output satisfies the RunViewState contract" % neutral_phase)

	var sword_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	sword_authoritative["run_id"] = "sword-view-run"
	var sword_player := _player_snapshot()
	sword_player["weapon"] = _sword_weapon_presentation()
	var sword_result = projector.project(
		sword_authoritative,
		_room_definition(1, "combat"),
		sword_player,
		null,
		2,
		{}
	)
	suite.assert_true(sword_result.ok, "Sword presentation projects")
	if sword_result.ok:
		var sword_state: Dictionary = sword_result.context["view_state"]["weapon_state"]
		suite.assert_equal(sword_state["weapon_id"], "sword", "Sword union keeps canonical weapon id")
		suite.assert_equal(sword_state["meter_kind"], "counter", "Sword union uses counter readiness meter")
		suite.assert_equal(sword_state["meter_current"], 1.0, "ready Sword exposes counter readiness")
		suite.assert_equal(sword_state["status_id"], "counter_ready", "ready Sword exposes counter status")
		suite.assert_equal(sword_state["secondary_id"], "combo", "Sword combo is a generic secondary value")
		suite.assert_equal(sword_state["secondary_value"], 2.0, "Sword combo step projects without a top-level legacy field")

	var perfect_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	perfect_authoritative["run_id"] = "perfect-reload-view-run"
	var perfect_player := _player_snapshot()
	perfect_player["weapon"]["runtime"]["reload_frame"] = 40
	perfect_player["weapon"]["runtime"]["reload_window"] = {
		"segment": "locked_complete",
		"dash_cancellable": false,
		"perfect_confirm": false,
		"complete": false,
	}
	perfect_player["weapon"]["runtime"]["time_load_source"] = "perfect_reload"
	perfect_player["weapon"]["runtime"]["time_load_remaining_frames"] = 300
	var perfect_result = projector.project(
		perfect_authoritative,
		_room_definition(1, "combat"),
		perfect_player,
		null,
		3,
		{}
	)
	suite.assert_true(perfect_result.ok, "perfect reload recovery projects")
	if perfect_result.ok:
		var perfect_state: Dictionary = perfect_result.context["view_state"]["weapon_state"]
		suite.assert_equal(perfect_state["status_id"], "perfect_reload", "perfect reload source survives the replacement recovery tail")
		suite.assert_equal(perfect_state["secondary_id"], "time_load", "perfect reload also exposes its free Time Load")
		suite.assert_equal(perfect_state["secondary_value"], 300, "free Time Load duration remains visible")

	var staff_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	staff_authoritative["run_id"] = "staff-view-run"
	var staff_player := _player_snapshot()
	staff_player["weapon"] = _staff_weapon_presentation()
	var staff_result = projector.project(
		staff_authoritative,
		_room_definition(1, "combat"),
		staff_player,
		null,
		4,
		{}
	)
	suite.assert_true(staff_result.ok, "Staff presentation projects")
	if staff_result.ok:
		var staff_state: Dictionary = staff_result.context["view_state"]["weapon_state"]
		suite.assert_equal(staff_state["weapon_id"], "staff", "Staff union keeps canonical weapon id")
		suite.assert_equal(staff_state["meter_kind"], "mana", "Staff union uses its Mana meter")
		suite.assert_equal(staff_state["meter_current"], 74.0, "Staff current Mana projects")
		suite.assert_equal(staff_state["meter_max"], 100.0, "Staff maximum Mana projects")
		suite.assert_equal(staff_state["status_id"], "sequence_ready", "runtime combo element exposes the sequence window")
		suite.assert_equal(staff_state["status_remaining"], 180, "runtime combo remaining frames project")
		suite.assert_equal(staff_state["secondary_id"], "element", "Staff exposes its current element generically")
		suite.assert_equal(staff_state["secondary_value"], 3, "runtime Lightning maps to stable element code three")

	var legacy_staff_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	legacy_staff_authoritative["run_id"] = "legacy-staff-view-run"
	var legacy_staff_player := _player_snapshot()
	legacy_staff_player["weapon"] = _legacy_staff_weapon_presentation()
	var legacy_staff_result = projector.project(
		legacy_staff_authoritative,
		_room_definition(1, "combat"),
		legacy_staff_player,
		null,
		5,
		{}
	)
	suite.assert_true(legacy_staff_result.ok, "legacy Staff presentation aliases remain supported")
	if legacy_staff_result.ok:
		var legacy_staff_state: Dictionary = legacy_staff_result.context["view_state"]["weapon_state"]
		suite.assert_equal(legacy_staff_state["meter_current"], 63.0, "legacy Staff Mana still projects")
		suite.assert_equal(legacy_staff_state["status_id"], "sequence_ready", "legacy sequence fields still project")
		suite.assert_equal(legacy_staff_state["status_remaining"], 90, "legacy sequence remaining frames still project")
		suite.assert_equal(legacy_staff_state["secondary_value"], 2, "legacy Ice maps to stable element code two")

	var fire_staff_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	fire_staff_authoritative["run_id"] = "fire-staff-view-run"
	var fire_staff_player := _player_snapshot()
	fire_staff_player["weapon"] = _staff_weapon_presentation()
	fire_staff_player["weapon"]["runtime"]["element"] = "fire"
	fire_staff_player["weapon"]["runtime"]["combo_element"] = ""
	fire_staff_player["weapon"]["runtime"]["combo_remaining_frames"] = 0
	var fire_staff_result = projector.project(
		fire_staff_authoritative,
		_room_definition(1, "combat"),
		fire_staff_player,
		null,
		6,
		{}
	)
	suite.assert_true(fire_staff_result.ok, "runtime Fire presentation projects without a combo window")
	if fire_staff_result.ok:
		var fire_staff_state: Dictionary = fire_staff_result.context["view_state"]["weapon_state"]
		suite.assert_equal(fire_staff_state["status_id"], "element_fire", "Fire readiness projects its localized status id")
		suite.assert_equal(fire_staff_state["status_remaining"], 0, "closed combo window has no remaining duration")
		suite.assert_equal(fire_staff_state["secondary_value"], 1, "runtime Fire maps to stable element code one")

	var gauntlets_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	gauntlets_authoritative["run_id"] = "gauntlets-view-run"
	var gauntlets_player := _player_snapshot()
	gauntlets_player["weapon"] = _gauntlets_weapon_presentation()
	var gauntlets_result = projector.project(
		gauntlets_authoritative,
		_room_definition(1, "combat"),
		gauntlets_player,
		null,
		7,
		{}
	)
	suite.assert_true(gauntlets_result.ok, "Gauntlets presentation projects")
	if gauntlets_result.ok:
		var gauntlets_state: Dictionary = gauntlets_result.context["view_state"]["weapon_state"]
		suite.assert_equal(gauntlets_state["weapon_id"], "gauntlets", "Gauntlets union keeps canonical weapon id")
		suite.assert_equal(gauntlets_state["meter_kind"], "combo", "active Gauntlets pressure uses the Combo meter")
		suite.assert_equal(gauntlets_state["meter_current"], 15, "Gauntlets Combo count projects")
		suite.assert_equal(gauntlets_state["meter_max"], 30, "Gauntlets Combo meter reaches its final tier at thirty")
		suite.assert_equal(gauntlets_state["status_id"], "combo_active", "five-plus Combo exposes active pressure")
		suite.assert_equal(gauntlets_state["status_remaining"], 77, "Gauntlets timeout remains readable")
		suite.assert_equal(gauntlets_state["secondary_id"], "combo", "Gauntlets keeps the exact Combo as secondary state")
		suite.assert_equal(gauntlets_state["secondary_value"], 15, "Gauntlets exact Combo count is preserved")

	var counter_authoritative := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	counter_authoritative["run_id"] = "gauntlets-counter-view-run"
	var counter_player := _player_snapshot()
	counter_player["weapon"] = _gauntlets_weapon_presentation()
	counter_player["weapon"]["runtime"]["counter_ready"] = true
	var counter_result = projector.project(
		counter_authoritative,
		_room_definition(1, "combat"),
		counter_player,
		null,
		8,
		{}
	)
	suite.assert_true(counter_result.ok, "live Gauntlets Counter window projects")
	if counter_result.ok:
		var counter_state: Dictionary = counter_result.context["view_state"]["weapon_state"]
		suite.assert_equal(counter_state["meter_kind"], "counter", "live Counter window replaces the Combo meter")
		suite.assert_equal(counter_state["meter_current"], 1, "live Counter window projects ready state")
		suite.assert_equal(counter_state["meter_max"], 1, "Counter readiness uses a binary meter")
		suite.assert_equal(counter_state["status_id"], "counter_ready", "live Counter window projects its localized status")


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


func _test_archetype_projection_contract(suite) -> void:
	var launch_projector = RunViewStateProjectorScript.new()
	var launch := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	launch["run_id"] = "launch-archetype-view"
	launch["config"]["milestone"] = "LAUNCH"
	launch["build"]["archetypes"] = LAUNCH_ARCHETYPE_SCORES.duplicate(true)
	var launch_result = launch_projector.project(
		launch,
		_room_definition(1, "combat"),
		_player_snapshot(),
		null,
		1,
		{}
	)
	suite.assert_true(launch_result.ok, "Launch authoritative build projects")
	if launch_result.ok:
		suite.assert_equal(
			launch_result.context["view_state"]["build"]["archetype_scores"],
			LAUNCH_ARCHETYPE_SCORES,
			"Launch projection preserves exactly the eight-key score domain"
		)

	var invalid_cases: Array[Dictionary] = []
	var unknown_score := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	unknown_score["build"]["archetypes"]["time_stop_burst"] = 1
	invalid_cases.append({"state": unknown_score, "label": "unknown score key"})
	var negative_score := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	negative_score["build"]["archetypes"]["freeze_burst"] = -1
	invalid_cases.append({"state": negative_score, "label": "negative score"})
	var infinite_score := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	infinite_score["build"]["archetypes"]["freeze_burst"] = INF
	invalid_cases.append({"state": infinite_score, "label": "infinite score"})
	var nan_score := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	nan_score["build"]["archetypes"]["freeze_burst"] = NAN
	invalid_cases.append({"state": nan_score, "label": "NaN score"})
	var outside_dominant := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	outside_dominant["build"]["dominant_archetype"] = "rift_trap"
	invalid_cases.append({"state": outside_dominant, "label": "dominant archetype outside score domain"})
	var internal_dominant := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	internal_dominant["build"]["dominant_archetype"] = "time_stop_burst"
	invalid_cases.append({"state": internal_dominant, "label": "internal mechanic dominant tag"})
	var launch_with_m1_domain := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	launch_with_m1_domain["config"]["milestone"] = "LAUNCH"
	invalid_cases.append({"state": launch_with_m1_domain, "label": "Launch milestone with M1 score domain"})

	for invalid_case: Dictionary in invalid_cases:
		_assert_invalid_build_projection(suite, invalid_case["state"] as Dictionary, str(invalid_case["label"]))


func _assert_invalid_build_projection(suite, authoritative: Dictionary, label: String) -> void:
	var projector = RunViewStateProjectorScript.new()
	var baseline := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	baseline["run_id"] = "baseline-%s" % label.replace(" ", "-")
	var valid = projector.project(baseline, _room_definition(1, "combat"), _player_snapshot(), null, 1, {})
	suite.assert_true(valid.ok, "%s fixture starts from a valid projection" % label)
	if not valid.ok:
		return
	var latest_before: Dictionary = projector.latest_view_state()
	authoritative["run_id"] = baseline["run_id"]
	var rejected = projector.project(authoritative, _room_definition(1, "combat"), _player_snapshot(), null, 2, {})
	suite.assert_equal(rejected.code, &"INVALID_ARGUMENT", "%s is rejected at the projection boundary" % label)
	suite.assert_equal(projector.latest_view_state(), latest_before, "%s cannot overwrite the latest valid view" % label)


func _test_invalid_inputs_are_rejected(suite) -> void:
	var projector = RunViewStateProjectorScript.new()
	var missing_run_id := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	missing_run_id["run_id"] = ""
	var invalid_run = projector.project(missing_run_id, _room_definition(1, "combat"), _player_snapshot(), null, 0, {})
	suite.assert_equal(invalid_run.code, &"INVALID_ARGUMENT", "empty run id is rejected")
	suite.assert_equal(invalid_run.context.get("field", ""), "authoritative.run_id", "invalid run reports its field")

	var missing_milestone := _authoritative(RunPhaseScript.Value.COMBAT_ACTIVE)
	missing_milestone["config"].erase("milestone")
	var invalid_milestone = projector.project(missing_milestone, _room_definition(1, "combat"), _player_snapshot(), null, 0, {})
	suite.assert_equal(invalid_milestone.code, &"INVALID_ARGUMENT", "missing authoritative milestone is rejected")
	suite.assert_equal(
		invalid_milestone.context.get("field", ""),
		"authoritative.config.milestone",
		"missing milestone reports its exact field"
	)

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

	var unknown_weapon := _player_snapshot()
	unknown_weapon["weapon"]["weapon_id"] = "laser"
	unknown_weapon["weapon"]["runtime"]["weapon_id"] = "laser"
	var invalid_weapon = projector.project(_authoritative(RunPhaseScript.Value.COMBAT_ACTIVE), _room_definition(1, "combat"), unknown_weapon, null, 0, {})
	suite.assert_equal(invalid_weapon.code, &"INVALID_ARGUMENT", "projector rejects unknown weapon presentations")
	suite.assert_true(projector.latest_view_state().is_empty(), "unknown weapon does not replace projector state")

	var negative_ammo := _player_snapshot()
	negative_ammo["weapon"]["action_id"] = ""
	negative_ammo["weapon"]["phase"] = "READY"
	negative_ammo["weapon"]["runtime"]["action_id"] = ""
	negative_ammo["weapon"]["runtime"]["phase"] = "READY"
	negative_ammo["weapon"]["runtime"]["ammo"] = -1
	var invalid_ammo = projector.project(_authoritative(RunPhaseScript.Value.COMBAT_ACTIVE), _room_definition(1, "combat"), negative_ammo, null, 0, {})
	suite.assert_equal(invalid_ammo.code, &"INVALID_ARGUMENT", "projector rejects negative Gun ammunition")

	var non_finite_time_load := _player_snapshot()
	non_finite_time_load["weapon"]["runtime"]["time_load_remaining_frames"] = INF
	var invalid_time_load = projector.project(_authoritative(RunPhaseScript.Value.COMBAT_ACTIVE), _room_definition(1, "combat"), non_finite_time_load, null, 0, {})
	suite.assert_equal(invalid_time_load.code, &"INVALID_ARGUMENT", "projector rejects non-finite Gun Time Load state")

	var invalid_gauntlets_cases: Array[Dictionary] = [
		{"field": "combo_count", "value": -1, "message": "negative Gauntlets Combo"},
		{"field": "combo_count", "value": "15", "message": "non-numeric Gauntlets Combo"},
		{"field": "combo_count", "value": 1000, "message": "Gauntlets Combo above the Profile maximum"},
		{"field": "combo_remaining_frames", "value": INF, "message": "non-finite Gauntlets timeout"},
		{"field": "combo_remaining_frames", "value": 1.5, "message": "fractional Gauntlets timeout"},
		{"field": "counter_ready", "value": 1, "message": "non-boolean Gauntlets counter readiness"},
		{"field": "chain_step", "value": 5, "message": "Gauntlets chain step above the Profile maximum"},
	]
	for invalid_case: Dictionary in invalid_gauntlets_cases:
		var invalid_gauntlets := _player_snapshot()
		invalid_gauntlets["weapon"] = _gauntlets_weapon_presentation()
		invalid_gauntlets["weapon"]["runtime"][str(invalid_case["field"])] = invalid_case["value"]
		var invalid_gauntlets_result = projector.project(
			_authoritative(RunPhaseScript.Value.COMBAT_ACTIVE),
			_room_definition(1, "combat"),
			invalid_gauntlets,
			null,
			0,
			{}
		)
		suite.assert_equal(
			invalid_gauntlets_result.code,
			&"INVALID_ARGUMENT",
			"projector rejects %s" % str(invalid_case["message"])
		)


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
			"archetypes": M1_ARCHETYPE_SCORES.duplicate(true),
			"dominant_archetype": "freeze_burst",
		},
		"open_offer": {},
		"consumed_offer_ids": [],
		"result": {},
		"config": {"milestone": "M1"},
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
		"weapon": _gun_weapon_presentation(),
		"character": _time_lord_character_presentation(),
		"time_slots": [
			{"ability_id": "stop", "action_id": "time_stop", "cooldown": 0.0},
			{"ability_id": "rift", "action_id": "time_rift", "cooldown": 4.5},
		],
	}


func _wanderer_character_presentation() -> Dictionary:
	return {
		"runtime_kind": "wanderer",
		"runtime_frame": 120,
		"resource_value": 3,
		"path_progress": 2,
		"anchor_active": true,
		"anchor_expires_frame": 300,
		"wayfarer_active": false,
		"wayfarer_until_frame": -1,
		"skill_cooldown_until_frame": 500,
	}


func _guardian_character_presentation() -> Dictionary:
	return {
		"runtime_kind": "time_guardian",
		"runtime_frame": 120,
		"resource_value": 3,
		"guard_active": false,
		"fortress_active": true,
		"fortress_until_frame": 300,
		"rebuke_active": false,
		"rebuke_until_frame": -1,
		"skill_cooldown_until_frame": 500,
	}


func _void_character_presentation() -> Dictionary:
	return {
		"runtime_kind": "void_walker",
		"runtime_frame": 120,
		"resource_value": 75,
		"resource_maximum": 100,
		"corruption_threshold": 75,
		"corruption_active": true,
		"next_corruption_frame": 150,
		"skill_active": false,
		"skill_cooldown_until_frame": 500,
	}


func _knight_character_presentation() -> Dictionary:
	return {
		"runtime_kind": "primordial_knight",
		"runtime_frame": 120,
		"resource_value": 2,
		"armor_active": false,
		"pending_echo_count": 2,
		"skill_cooldown_until_frame": 500,
	}


func _time_lord_character_presentation() -> Dictionary:
	return {
		"runtime_kind": "time_lord",
		"runtime_frame": 120,
		"resource_value": 2,
		"primer_ability_id": "stop",
		"primer_expires_frame": 419,
		"infusion_until_frame": -1,
		"dominion_until_frame": -1,
		"skill_cooldown_until_frame": 240,
	}


func _gun_weapon_presentation() -> Dictionary:
	return {
		"weapon_id": "gun",
		"action_id": "reload",
		"phase": "RESOURCE_ACTION",
		"phase_frame": 20,
		"phase_duration_frames": 32,
		"runtime": {
			"weapon_id": "gun",
			"action_id": "reload",
			"phase": "RESOURCE_ACTION",
			"ammo": 2,
			"ammo_maximum": 6,
			"reload_frame": 28,
			"reload_window": {
				"segment": "perfect",
				"dash_cancellable": true,
				"perfect_confirm": true,
				"complete": false,
			},
			"time_load_source": "active",
			"time_load_remaining_frames": 240,
		},
	}


func _bow_weapon_presentation() -> Dictionary:
	return {
		"weapon_id": "bow",
		"action_id": "precision_draw",
		"phase": "HOLD",
		"charge_frames": 30.0,
		"maximum_charge_frames": 48.0,
		"charge_ratio": 0.625,
		"full_charge": false,
		"runtime": {
			"weapon_id": "bow",
			"action_id": "precision_draw",
			"phase": "HOLD",
			"charge_frames": 30.0,
			"maximum_charge_frames": 48.0,
			"full_charge": false,
		},
	}


func _sword_weapon_presentation() -> Dictionary:
	return {
		"weapon_id": "sword",
		"action_id": "",
		"phase": "READY",
		"runtime": {
			"weapon_id": "sword",
			"action_id": "",
			"phase": "READY",
			"combo_step": 2,
			"combo_reset_frames": 48,
		},
	}


func _staff_weapon_presentation() -> Dictionary:
	return {
		"weapon_id": "staff",
		"action_id": "",
		"phase": "READY",
		"runtime": {
			"weapon_id": "staff",
			"action_id": "",
			"phase": "READY",
			"mana": 74.0,
			"mana_maximum": 100.0,
			"element": "lightning",
			"combo_element": "ice",
			"combo_remaining_frames": 180,
			"current_element": "fire",
			"sequence_first_element": "",
			"sequence_remaining_frames": 0,
		},
	}


func _legacy_staff_weapon_presentation() -> Dictionary:
	return {
		"weapon_id": "staff",
		"action_id": "",
		"phase": "READY",
		"runtime": {
			"weapon_id": "staff",
			"action_id": "",
			"phase": "READY",
			"mana": 63.0,
			"mana_maximum": 100.0,
			"current_element": "ice",
			"sequence_first_element": "lightning",
			"sequence_remaining_frames": 90,
		},
	}


func _gauntlets_weapon_presentation() -> Dictionary:
	return {
		"weapon_id": "gauntlets",
		"action_id": "",
		"phase": "READY",
		"runtime": {
			"weapon_id": "gauntlets",
			"action_id": "",
			"phase": "READY",
			"chain_step": 3,
			"combo_count": 15,
			"combo_remaining_frames": 77,
			"counter_ready": false,
		},
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
