extends Node

const CharacterActionCoordinatorScript := preload(
	"res://scripts/player/characters/character_action_coordinator.gd"
)
const CharacterRuntimeProfileScript := preload(
	"res://scripts/player/characters/character_runtime_profile.gd"
)
const PlayerCharacterRuntimeScript := preload(
	"res://scripts/player/characters/player_character_runtime.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_CATALOG_PATH := (
	"res://data/content_packs/base/content/character_runtime_profiles.json"
)
const TALENT_CATALOG_PATH := "res://data/content_packs/base/content/talents.json"
const CHARACTER_ORDER: Array[StringName] = [
	&"wanderer",
	&"time_guardian",
	&"void_walker",
	&"primordial_knight",
	&"time_lord",
]
const PROFILE_IDS := {
	&"wanderer": "wanderer_launch_v1",
	&"time_guardian": "time_guardian_launch_v1",
	&"void_walker": "void_walker_launch_v1",
	&"primordial_knight": "primordial_knight_launch_v1",
	&"time_lord": "time_lord_launch_v1",
}
const TALENTS := {
	&"wanderer": [&"tal_eternity_reserve", &"tal_ruin_execute", &"tal_steel_recover"],
	&"time_guardian": [&"widened_guard", &"fortress_core", &"temporal_rebuke"],
	&"void_walker": [&"deep_debt", &"bounded_devour", &"risk_step"],
	&"primordial_knight": [&"resonant_plate", &"echo_forge", &"realm_collapse"],
	&"time_lord": [&"codex_margin", &"efficient_inscription", &"dominion_cadence"],
}

var _suite
var _profile_definitions: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_profile_definitions = _load_dictionary_array(PROFILE_CATALOG_PATH)
	_test_exact_launch_talent_catalog()
	_test_all_forty_runtime_subsets()
	_suite.finish(get_tree())


func _test_exact_launch_talent_catalog() -> void:
	var definitions := _load_dictionary_array(TALENT_CATALOG_PATH)
	var actual_ids: Array[String] = []
	for definition: Dictionary in definitions:
		actual_ids.append(str(definition.get("id", "")))
	actual_ids.sort()
	var expected_ids: Array[String] = []
	for character_id: StringName in CHARACTER_ORDER:
		for talent_id: StringName in TALENTS[character_id]:
			expected_ids.append(str(talent_id))
	expected_ids.sort()
	_suite.assert_equal(definitions.size(), 15, "Launch talent content contains exactly fifteen definitions")
	_suite.assert_equal(actual_ids, expected_ids, "Launch talent content contains only the approved identities")


func _test_all_forty_runtime_subsets() -> void:
	var observed_cases: Dictionary = {}
	for character_index: int in range(CHARACTER_ORDER.size()):
		var character_id := CHARACTER_ORDER[character_index]
		var profile = _profile(str(PROFILE_IDS[character_id]))
		_suite.assert_true(profile != null, "%s Launch profile parses" % str(character_id))
		if profile == null:
			continue
		var talent_ids: Array = TALENTS[character_id]
		for mask: int in range(8):
			var expected := _subset(talent_ids, mask)
			var supplied := expected.duplicate()
			supplied.reverse()
			var owner := Node.new()
			var runtime = PlayerCharacterRuntimeScript.new()
			var label := "%s/%03d" % [str(character_id), mask]
			_suite.assert_true(
				runtime.configure(owner, profile, PackedStringArray(supplied)),
				"%s configures the real character runtime" % label
			)
			_suite.assert_equal(
				runtime.selected_talent_ids(),
				expected,
				"%s canonicalizes talent order" % label
			)
			_suite.assert_equal(
				runtime.presentation_snapshot().get("selected_talent_ids", []),
				expected,
				"%s exposes the exact HUD talent identity" % label
			)

			var coordinator = CharacterActionCoordinatorScript.new()
			_suite.assert_true(coordinator.configure(runtime), "%s installs in the coordinator" % label)
			var replay_checkpoint: Dictionary = coordinator.snapshot()
			var advanced: Dictionary = coordinator.advance_frame(mask + 1, {})
			_suite.assert_true(bool(advanced.get("ok", false)), "%s advances on the fixed frame pump" % label)
			_suite.assert_true(
				coordinator.snapshot() != replay_checkpoint,
				"%s produces state for Replay rollback" % label
			)
			_suite.assert_true(
				coordinator.restore_replay_snapshot(replay_checkpoint),
				"%s restores through the Replay path" % label
			)
			_suite.assert_equal(
				coordinator.snapshot(),
				replay_checkpoint,
				"%s Replay restore is exact" % label
			)

			_suite.assert_true(
				coordinator.reset_runtime_state(&"talent_subset_matrix"),
				"%s resets through production authority" % label
			)
			_suite.assert_equal(
				runtime.selected_talent_ids(),
				expected,
				"%s reset preserves the run talent subset" % label
			)

			var before_rejection: Dictionary = runtime.snapshot()
			var foreign_character := CHARACTER_ORDER[(character_index + 1) % CHARACTER_ORDER.size()]
			var foreign_talent := str((TALENTS[foreign_character] as Array)[0])
			_suite.assert_true(
				not runtime.configure(owner, profile, PackedStringArray([foreign_talent])),
				"%s rejects a cross-character talent" % label
			)
			_suite.assert_equal(
				runtime.snapshot(),
				before_rejection,
				"%s cross-character rejection is atomic" % label
			)

			var case_key := "%s:%s" % [str(character_id), ",".join(expected)]
			_suite.assert_true(not observed_cases.has(case_key), "%s is a unique subset case" % label)
			observed_cases[case_key] = true
			owner.free()

	_suite.assert_equal(observed_cases.size(), 40, "five characters certify exactly forty talent subsets")


func _subset(talent_ids: Array, mask: int) -> Array[String]:
	var result: Array[String] = []
	for bit: int in range(3):
		if mask & (1 << bit):
			result.append(str(talent_ids[bit]))
	return result


func _profile(profile_id: String):
	for definition: Dictionary in _profile_definitions:
		if str(definition.get("id", "")) == profile_id:
			return CharacterRuntimeProfileScript.from_definition(definition.duplicate(true))
	return null


func _load_dictionary_array(path: String) -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result: Array[Dictionary] = []
	if parsed is Array:
		for value: Variant in parsed:
			if value is Dictionary:
				result.append((value as Dictionary).duplicate(true))
	return result
