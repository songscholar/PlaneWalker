extends Node

const CharacterTalentStateScript := preload(
	"res://scripts/player/characters/character_talent_state.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const TALENTS := {
	&"wanderer": [&"tal_eternity_reserve", &"tal_ruin_execute", &"tal_steel_recover"],
	&"time_guardian": [&"widened_guard", &"fortress_core", &"temporal_rebuke"],
	&"void_walker": [&"deep_debt", &"bounded_devour", &"risk_step"],
	&"primordial_knight": [&"resonant_plate", &"echo_forge", &"realm_collapse"],
	&"time_lord": [&"codex_margin", &"efficient_inscription", &"dominion_cadence"],
}

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_catalog_and_all_forty_subsets()
	_test_atomic_rejection_and_character_scope()
	_test_freeze_snapshot_restore_and_reset()
	_suite.finish(get_tree())


func _test_catalog_and_all_forty_subsets() -> void:
	var catalog: Dictionary = CharacterTalentStateScript.canonical_catalog()
	_suite.assert_equal(catalog.size(), 5, "talent catalog has exactly five character routes")
	var identities: Array[String] = []
	var case_count := 0
	for character_value: Variant in TALENTS.keys():
		var character_id := StringName(character_value)
		var expected_ids: Array = TALENTS[character_id]
		_suite.assert_equal(catalog.get(character_id, []), expected_ids, "catalog preserves canonical talent order")
		for talent_id: StringName in expected_ids:
			identities.append(str(talent_id))
		for subset: PackedStringArray in _all_subsets(expected_ids):
			var state = CharacterTalentStateScript.new()
			_suite.assert_true(state.configure(character_id, subset), "every canonical talent subset configures")
			var expected_canonical: Array[String] = []
			for talent_id: StringName in expected_ids:
				if subset.has(str(talent_id)):
					expected_canonical.append(str(talent_id))
			_suite.assert_equal(state.selected_talent_ids(), expected_canonical, "subset canonicalizes to declared order")
			_assert_exact_vector(character_id, expected_canonical, state.modifier_snapshot())
			case_count += 1
	identities.sort()
	var unique_identities := identities.duplicate()
	for index: int in range(unique_identities.size() - 1, 0, -1):
		if unique_identities[index] == unique_identities[index - 1]:
			unique_identities.remove_at(index)
	_suite.assert_equal(case_count, 40, "five routes enumerate exactly forty talent subsets")
	_suite.assert_equal(unique_identities.size(), 15, "catalog exposes exactly fifteen unique talent identities")


func _test_atomic_rejection_and_character_scope() -> void:
	var state = CharacterTalentStateScript.new()
	_suite.assert_true(state.configure(&"time_lord", PackedStringArray(["dominion_cadence", "codex_margin"])), "unordered Time Lord subset configures")
	var before: Dictionary = state.snapshot()
	_suite.assert_true(not state.configure(&"time_lord", PackedStringArray(["codex_margin", "codex_margin"])), "duplicate talent is rejected")
	_suite.assert_equal(state.snapshot(), before, "duplicate rejection is atomic")
	_suite.assert_true(not state.configure(&"time_lord", PackedStringArray(["deep_debt"])), "cross-character talent is rejected")
	_suite.assert_equal(state.snapshot(), before, "cross-character rejection is atomic")
	_suite.assert_true(not state.configure(&"unknown", PackedStringArray()), "unknown character route is rejected")
	_suite.assert_equal(state.snapshot(), before, "unknown route rejection is atomic")


func _test_freeze_snapshot_restore_and_reset() -> void:
	var state = CharacterTalentStateScript.new()
	_suite.assert_true(state.configure(&"time_lord", PackedStringArray(["codex_margin", "efficient_inscription", "dominion_cadence"])), "full Time Lord talent route configures")
	var frozen: Dictionary = state.freeze_for_commit(&"time_action", 9, 4)
	_suite.assert_equal(frozen.get("selected_talent_ids", []), ["codex_margin", "efficient_inscription", "dominion_cadence"], "commit freeze captures canonical identities")
	_suite.assert_equal((frozen.get("modifiers", {}) as Dictionary).get("pair_window_frames"), 420, "commit freeze captures applied values")
	(frozen["modifiers"] as Dictionary)["pair_window_frames"] = 1
	_suite.assert_equal(int(state.modifier_snapshot().get("pair_window_frames", 0)), 420, "commit freeze cannot alias authoritative talent modifiers")
	var exact: Dictionary = state.snapshot()
	_suite.assert_true(state.can_restore_snapshot(exact), "talent snapshot validates")
	state.reset_runtime_state(&"room_transition")
	_suite.assert_true(int(state.snapshot().revision) > int(exact.revision), "reset advances state revision")
	_suite.assert_equal(state.selected_talent_ids(), exact.selected_talent_ids, "reset preserves run talent selection")
	_suite.assert_true(state.restore_snapshot(exact), "checkpoint restore reinstalls exact revision")
	_suite.assert_equal(state.snapshot(), exact, "checkpoint restore is byte-for-byte exact")
	_suite.assert_equal(state.freeze_for_commit(&"", 9, 4), {}, "invalid commit kind fails closed")
	_suite.assert_equal(state.freeze_for_commit(&"time_action", 0, 4), {}, "invalid commit token fails closed")


func _assert_exact_vector(character_id: StringName, selected: Array[String], modifiers: Dictionary) -> void:
	match character_id:
		&"wanderer":
			_suite.assert_equal(int(modifiers.get("wayfarer_energy_restore", 0)), 8 if selected.has("tal_eternity_reserve") else 6, "Wanderer energy modifier is exact")
			_suite.assert_equal(int(modifiers.get("wayfarer_bonus_progress", -1)), 1 if selected.has("tal_ruin_execute") else 0, "Wanderer progress modifier is exact")
			_suite.assert_equal(int(modifiers.get("max_hp_bonus", -1)), 20 if selected.has("tal_steel_recover") else 0, "Wanderer HP modifier is exact")
			_suite.assert_equal(int(modifiers.get("room_clear_hp_per_mark", 0)), 3 if selected.has("tal_steel_recover") else 2, "Wanderer room heal modifier is exact")
		&"time_guardian":
			_suite.assert_equal(int(modifiers.get("perfect_last_frame", 0)), 11 if selected.has("widened_guard") else 8, "Guardian perfect window is exact")
			_suite.assert_equal(int(modifiers.get("fortress_ward_cost", 0)), 2 if selected.has("fortress_core") else 3, "Guardian Ward cost is exact")
			_suite.assert_close(float(modifiers.get("rebuke_echo_multiplier", 0.0)), 1.0 if selected.has("temporal_rebuke") else 0.75, "Guardian echo is exact")
			_suite.assert_equal(int(modifiers.get("cooldown_reduction_frames", 0)), 45 if selected.has("temporal_rebuke") else 30, "Guardian cooldown reduction is exact")
		&"void_walker":
			_suite.assert_equal(int(modifiers.get("debt_cap", 0)), 120 if selected.has("deep_debt") else 100, "Void debt cap is exact")
			_suite.assert_close(float(modifiers.get("devour_heal_ratio", 0.0)), 0.18 if selected.has("bounded_devour") else 0.15, "Void healing is exact")
			_suite.assert_equal(int(modifiers.get("risk_radius", 0)), 288 if selected.has("risk_step") else 240, "Void risk radius is exact")
		&"primordial_knight":
			_suite.assert_equal(int(modifiers.get("armor_recovery_extension_frames", -1)), 12 if selected.has("resonant_plate") else 0, "Knight armor extension is exact")
			_suite.assert_close(float(modifiers.get("echo_multiplier", 0.0)), 1.0 if selected.has("echo_forge") else 0.75, "Knight echo is exact")
			_suite.assert_equal(int(modifiers.get("instability_frames", 0)), 600 if selected.has("realm_collapse") else 480, "Knight instability is exact")
		&"time_lord":
			_suite.assert_equal(int(modifiers.get("pair_window_frames", 0)), 420 if selected.has("codex_margin") else 300, "Time Lord pair window is exact")
			_suite.assert_equal(int(modifiers.get("infusion_energy_cost", 0)), 5 if selected.has("efficient_inscription") else 10, "Time Lord Infusion cost is exact")
			_suite.assert_equal(int(modifiers.get("dominion_energy_cost", 0)), 45 if selected.has("dominion_cadence") else 60, "Time Lord Dominion cost is exact")
			_suite.assert_equal(int(modifiers.get("dominion_cooldown_frames", 0)), 360 if selected.has("dominion_cadence") else 480, "Time Lord Dominion cooldown is exact")


func _all_subsets(ids: Array) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for mask: int in range(8):
		var subset := PackedStringArray()
		for bit: int in range(3):
			if mask & (1 << (2 - bit)):
				subset.append(str(ids[bit]))
		result.append(subset)
	return result
