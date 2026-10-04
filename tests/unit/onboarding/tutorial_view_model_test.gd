extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Remap := preload("res://scripts/input/input_remap_service.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/onboarding/tutorial_view_model.gd") as Script
	var contract := load("res://scripts/ui/contracts/tutorial_view_state.gd") as Script
	suite.assert_true(implementation != null and contract != null, "native tutorial projection and strict presentation contract exist")
	if implementation != null and contract != null:
		_test_view(implementation, contract)
	suite.finish(get_tree())


func _test_view(implementation: Script, contract: Script) -> void:
	var catalog := Fixtures.catalog()
	var profile := Fixtures.profile(catalog)
	var input := Remap.new()
	input.configure()
	var model: RefCounted = implementation.new()
	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/tutorial_definitions.json"))
	suite.assert_true(model.configure(entries, catalog, input).ok, "view model consumes actual authored tutorial definitions and current InputMap")
	var before := profile.duplicate(true)
	var projected: Dictionary = model.project(profile, "profile-main", "keyboard_mouse", "rewind")
	suite.assert_true(projected.ok, "fresh Profile projects a usable lesson and training view")
	if not projected.ok:
		return
	var state: Dictionary = projected.context.view_state
	suite.assert_true(contract.validate(state).ok, "actual authored presentation passes its strict contract")
	suite.assert_equal(profile, before, "view projection cannot change tutorial progress or currency")
	suite.assert_equal(state.lessons.size(), 10, "all authored lessons are present")
	suite.assert_equal(state.lessons[0].lesson_id, "movement_dodge", "lesson order uses authored sequence rather than alphabetical identifiers")
	suite.assert_equal(state.lessons[9].sequence, 10, "last lesson keeps authored sequence")
	suite.assert_equal(state.lessons[0].requirements[0].current, 0, "new objectives show actual zero progress")
	suite.assert_true(not state.guided_selected and state.ranked_eligible, "ordinary mode is initially available without implicit assistance")
	suite.assert_true(state.training_available and state.mode_change_available, "Hub Profile can choose mode and training")
	var total := 0
	for task: Dictionary in state.training_tasks:
		total += int(task.reward_shards)
	suite.assert_equal(total, 56, "training view shows exactly the six first-time rewards")
	for sequence: int in range(1, 4):
		profile.tutorial_state.guided_runs_completed = sequence - 1
		var guided: Dictionary = model.project(profile, "profile-main", "controller", "rift", true)
		suite.assert_true(guided.ok, "explicit guided choice projects authored protection")
		if guided.ok:
			suite.assert_close(guided.context.view_state.incoming_damage_multiplier, [0.8, 0.9, 1.0][sequence - 1], "guided damage protection is exact")
			suite.assert_true(not guided.context.view_state.ranked_eligible, "each explicit guided run is unranked")
	profile.tutorial_state.guided_runs_completed = 3
	suite.assert_true(not model.project(profile, "profile-main", "controller", "rift", true).ok, "completed guided program cannot silently create a fourth assisted run")
	profile = before.duplicate(true)
	profile.tutorial_state.completed_lessons = ["movement_dodge"]
	var legacy: Dictionary = model.project(profile, "profile-main", "keyboard_mouse", "stop")
	suite.assert_true(legacy.ok, "migrated completed lessons project without invented action history")
	if legacy.ok:
		suite.assert_equal(legacy.context.view_state.lessons[0].requirements[0].current, 3, "legacy completed objectives show satisfied count")
		suite.assert_true(not legacy.context.view_state.lessons[0].skip_available, "completed lesson cannot offer a second skip")
	var corrupt := state.duplicate(true)
	corrupt.private_domain = profile
	suite.assert_true(not contract.validate(corrupt).ok, "presentation rejects unknown root fields")
	corrupt = state.duplicate(true)
	corrupt.lessons[0].requirements[0].current = 1000
	suite.assert_true(not contract.validate(corrupt).ok, "presentation rejects progress above authored target")
	corrupt = state.duplicate(true)
	corrupt.lessons[0].actions[0].bindings[0].action_id = "delete_profile"
	suite.assert_true(not contract.validate(corrupt).ok, "presentation cannot invent unrelated input actions")
	corrupt = state.duplicate(true)
	corrupt.lessons.reverse()
	suite.assert_true(not contract.validate(corrupt).ok, "presentation rejects reordered lesson sequence")
	corrupt = state.duplicate(true)
	corrupt.lessons[0].status_key = "UI_TUTORIAL_DONE"
	corrupt.lessons[0].skip_available = false
	suite.assert_true(not contract.validate(corrupt).ok, "completed lesson requires satisfied objectives")
	corrupt = state.duplicate(true)
	corrupt.training_tasks[0].claimed = true
	suite.assert_true(not contract.validate(corrupt).ok, "claimed training reward requires satisfied objectives")
	var saved := InputMap.action_get_events(&"dash")
	InputMap.action_erase_events(&"dash")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	InputMap.action_add_event(&"dash", key)
	var refreshed: Dictionary = model.project(before, "profile-main", "keyboard_mouse", "stop")
	if refreshed.ok:
		suite.assert_equal(refreshed.context.view_state.lessons[0].actions[1].bindings[0].labels, ["K"], "native lesson labels refresh from real remapped InputMap")
	else:
		suite.assert_true(false, "current remapped InputMap remains projectable")
	InputMap.action_erase_events(&"dash")
	for event: InputEvent in saved:
		InputMap.action_add_event(&"dash", event)
	var hint: Dictionary = entries.filter(func(row: Dictionary) -> bool: return row.definition_kind == "hint")[0]
	var hint_view: Dictionary = model.project_hint(hint, before.revision, "native-run", "controller", "rift")
	suite.assert_true(hint_view.ok and contract.validate_hint(hint_view.context.view_state).ok, "saved authored hint projects a strict native presentation")
	var changed_hint := hint.duplicate(true)
	changed_hint.text_key = "FORGED_TEXT"
	suite.assert_true(not model.project_hint(changed_hint, before.revision, "native-run", "controller", "rift").ok, "caller cannot substitute authored saved hint content")
