extends Node

const CharacterActionCoordinatorScript := preload(
	"res://scripts/player/characters/character_action_coordinator.gd"
)
const CharacterRuntimeFactoryScript := preload(
	"res://scripts/player/characters/character_runtime_factory.gd"
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
const SUPPORTED_RUNTIME_KINDS: Array[String] = [
	"wanderer_m1_compat",
	"wanderer",
	"time_guardian",
	"void_walker",
	"primordial_knight",
	"time_lord",
]


class SkillRuntime extends RefCounted:
	var revision: int = 0
	var reject_plan_after_mutation: bool = false
	var reject_commit_after_mutation: bool = false
	var malformed_advance_after_mutation: bool = false
	var malformed_after_damage_after_mutation: bool = false
	var restore_fault_mode: StringName = &""
	var restore_call_count: int = 0


	func advance_frame(context: Dictionary) -> Variant:
		revision += int(context.get("runtime_frame", 0)) + 1
		if malformed_advance_after_mutation:
			return {"malformed": true}
		return []


	func plan_character_skill(_intent: Dictionary, _context: Dictionary) -> Dictionary:
		if reject_plan_after_mutation:
			revision += 10
			return {"ok": false, "code": "rejected_plan"}
		return {"ok": true, "plan": {"skill_id": "test_skill", "nested": {"value": 7}}}


	func commit_character_skill(_plan: Dictionary, _token: int) -> Dictionary:
		if reject_commit_after_mutation:
			revision += 20
			return {"ok": false, "code": "rejected_commit"}
		revision += 1
		return {"ok": true, "context": {"committed": true}}


	func before_damage(_context: Dictionary) -> Dictionary:
		return {"ok": true, "decision": {}}


	func after_damage(_context: Dictionary) -> Variant:
		if malformed_after_damage_after_mutation:
			revision += 30
			return {"malformed": true}
		return []


	func on_weapon_action_committed(_context: Dictionary) -> Array[Dictionary]:
		return []


	func on_weapon_mastery_confirmed(_context: Dictionary) -> Array[Dictionary]:
		return []


	func before_time_skill(_context: Dictionary) -> Dictionary:
		return {"ok": true, "decision": {}}


	func after_time_skill(_context: Dictionary) -> Array[Dictionary]:
		return []


	func on_room_started(_context: Dictionary) -> Array[Dictionary]:
		return []


	func on_room_cleared(_context: Dictionary) -> Array[Dictionary]:
		return []


	func on_run_terminal(_context: Dictionary) -> Dictionary:
		return {"ok": true, "summary": {}}


	func reset_runtime_state(_reason: StringName) -> void:
		revision = 0


	func snapshot() -> Dictionary:
		return {"revision": revision}


	func can_restore_snapshot(value: Dictionary) -> bool:
		return value.size() == 1 and typeof(value.get("revision")) == TYPE_INT


	func restore_snapshot(value: Dictionary) -> bool:
		if not can_restore_snapshot(value):
			return false
		restore_call_count += 1
		if restore_fault_mode == &"partial_then_successful_rollback":
			if restore_call_count == 1:
				revision = int(value["revision"]) + 100
				return false
			revision = int(value["revision"])
			return true
		if restore_fault_mode == &"partial_then_reject_rollback":
			revision = int(value["revision"]) + 100 * restore_call_count
			return false
		revision = int(value["revision"])
		return true


	func presentation_snapshot() -> Dictionary:
		return {"revision": revision}


var _suite
var _definitions: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_definitions = _load_definitions()
	_test_factory_accepts_only_six_runtime_kinds()
	_test_authoritative_profile_and_canonical_talent_installation()
	_test_invalid_configuration_is_atomic()
	_test_fixed_frame_defaults_and_lifecycle_shell_are_pure()
	_test_snapshot_restore_and_presentation_are_exact_and_isolated()
	_test_replay_neutral_reanchor_is_strictly_scoped()
	_test_production_wrapper_propagates_malformed_events_for_exact_rollback()
	_test_production_wrapper_restore_failure_is_exact_or_fail_closed()
	_test_coordinator_generation_token_and_rejection_atomicity()
	_suite.finish(get_tree())


func _test_factory_accepts_only_six_runtime_kinds() -> void:
	for runtime_kind: String in SUPPORTED_RUNTIME_KINDS:
		var strategy: Variant = CharacterRuntimeFactoryScript.create(runtime_kind)
		_suite.assert_true(strategy is RefCounted, "factory creates %s strategy" % runtime_kind)
		if strategy is RefCounted:
			_suite.assert_equal(
				str(strategy.call("runtime_kind")),
				runtime_kind,
				"factory strategy retains %s identity" % runtime_kind
			)
	_suite.assert_equal(CharacterRuntimeFactoryScript.create("unknown"), null, "unknown kind is rejected")
	_suite.assert_equal(CharacterRuntimeFactoryScript.create(7), null, "non-string kind is rejected")


func _test_authoritative_profile_and_canonical_talent_installation() -> void:
	var owner := Node.new()
	var profile: Variant = _profile("wanderer_launch_v1")
	var selected := ["tal_steel_recover", "tal_eternity_reserve"]
	var runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		runtime.configure(owner, profile, selected, _talent_definitions(selected)),
		"valid profile and subset configure"
	)
	_suite.assert_equal(
		runtime.selected_talent_ids(),
		["tal_eternity_reserve", "tal_steel_recover"],
		"selected talents use authoritative profile order"
	)
	selected.append("tal_ruin_execute")
	profile.presentation["meter_id"] = "forged"
	profile.base_stats["attack"] = 999
	var installed: Dictionary = runtime.profile_snapshot()
	_suite.assert_equal(installed.presentation.meter_id, "path_marks", "profile presentation is isolated")
	_suite.assert_equal(installed.base_stats.attack, 30, "profile stats are isolated")
	_suite.assert_equal(runtime.selected_talent_ids().size(), 2, "talent input is isolated")
	owner.free()


func _test_invalid_configuration_is_atomic() -> void:
	var owner := Node.new()
	var wanderer: Variant = _profile("wanderer_launch_v1")
	var invalid_cases: Array = [
		[null, wanderer, []],
		[owner, null, []],
		[owner, wanderer, ["tal_eternity_reserve", "tal_eternity_reserve"]],
		[owner, wanderer, ["unknown_talent"]],
		[owner, wanderer, ["widened_guard"]],
		[owner, wanderer, [7]],
	]
	for index: int in range(invalid_cases.size()):
		var runtime = PlayerCharacterRuntimeScript.new()
		var before: Dictionary = runtime.snapshot()
		var args: Array = invalid_cases[index]
		_suite.assert_true(
			not runtime.configure(args[0], args[1], args[2]),
			"invalid configuration %d is rejected" % index
		)
		_suite.assert_equal(runtime.snapshot(), before, "invalid configuration is zero-mutation")

	var forged_definition := _definition("wanderer_launch_v1")
	forged_definition["runtime_kind"] = "unsupported"
	var forged_profile = CharacterRuntimeProfileScript.new()
	_suite.assert_true(
		not bool(forged_profile.configure(forged_definition).get("ok", false)),
		"profile parser rejects an unknown runtime kind before installation"
	)
	owner.free()


func _test_fixed_frame_defaults_and_lifecycle_shell_are_pure() -> void:
	var owner := Node.new()
	var runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(runtime.configure(owner, _profile("time_guardian_launch_v1"), []), "runtime configures")
	var before: Dictionary = runtime.snapshot()
	_suite.assert_equal(runtime.advance_frame({}), [], "frame without authority is rejected without events")
	_suite.assert_equal(runtime.snapshot(), before, "invalid frame is zero-mutation")
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 4}), [], "authoritative frame advances")
	_suite.assert_equal(runtime.snapshot().strategy.last_runtime_frame, 4, "strategy owns fixed-frame cursor")
	var advanced: Dictionary = runtime.snapshot()
	_suite.assert_equal(runtime.advance_frame({"runtime_frame": 4}), [], "stale frame is rejected without events")
	_suite.assert_equal(runtime.snapshot(), advanced, "stale frame is zero-mutation")

	_suite.assert_equal(
		runtime.plan_character_skill({}, {}),
		{"ok": false, "code": "unsupported"},
		"shell skill plan is explicitly unsupported"
	)
	_suite.assert_equal(
		runtime.commit_character_skill({}, 1),
		{"ok": false, "code": "unsupported"},
		"shell skill commit is explicitly unsupported"
	)
	_suite.assert_equal(runtime.before_damage({}), {"ok": true, "decision": {}}, "damage pre-hook defaults")
	_suite.assert_equal(runtime.after_damage({}), [], "damage post-hook defaults")
	_suite.assert_equal(runtime.on_weapon_action_committed({}), [], "weapon action hook defaults")
	_suite.assert_equal(runtime.on_weapon_mastery_confirmed({}), [], "weapon mastery hook defaults")
	_suite.assert_equal(runtime.before_time_skill({}), {"ok": true, "decision": {}}, "time pre-hook defaults")
	_suite.assert_equal(runtime.after_time_skill({}), [], "time post-hook defaults")
	_suite.assert_equal(runtime.on_room_started({}), [], "room-start hook defaults")
	_suite.assert_equal(runtime.on_room_cleared({}), [], "room-clear hook defaults")
	_suite.assert_equal(runtime.on_run_terminal({}), {"ok": true, "summary": {}}, "terminal hook defaults")
	_suite.assert_equal(runtime.snapshot(), advanced, "unsupported and default hooks are gameplay-pure")
	owner.free()


func _test_snapshot_restore_and_presentation_are_exact_and_isolated() -> void:
	var owner := Node.new()
	var runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(runtime.configure(owner, _profile("wanderer_m1_v1"), []), "M1 runtime configures")
	var m1_presentation: Dictionary = runtime.presentation_snapshot()
	_suite.assert_equal(
		m1_presentation,
		{
			"profile_id": "wanderer_m1_v1",
			"profile_version": 1,
			"character_id": "wanderer",
			"runtime_kind": "wanderer_m1_compat",
			"selected_talent_ids": [],
			"palette_id": "wanderer",
			"meter_id": "none",
			"skill_cue_id": "none",
			"resource_id": "none",
			"resource_minimum": 0,
			"resource_maximum": 0,
			"resource_value": 0,
			"character_skill_id": "none",
		},
		"M1 presentation projection is exact"
	)

	var target: Dictionary = runtime.snapshot()
	runtime.advance_frame({"runtime_frame": 8})
	_suite.assert_true(runtime.can_restore_snapshot(target), "prior runtime snapshot validates")
	_suite.assert_true(runtime.restore_snapshot(target), "prior runtime snapshot restores")
	_suite.assert_equal(runtime.snapshot(), target, "runtime restore is exact")

	var exposed := runtime.snapshot()
	(exposed["profile"] as Dictionary).presentation.meter_id = "forged"
	(exposed["selected_talent_ids"] as Array).append("forged")
	_suite.assert_equal(runtime.snapshot(), target, "snapshot output is deeply isolated")
	var forged := target.duplicate(true)
	forged["unknown"] = true
	var before_rejection := runtime.snapshot()
	_suite.assert_true(not runtime.restore_snapshot(forged), "unknown snapshot field is rejected")
	_suite.assert_equal(runtime.snapshot(), before_rejection, "forged restore is zero-mutation")
	owner.free()

	var launch_owner := Node.new()
	var launch_runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		launch_runtime.configure(
			launch_owner,
			_profile("time_lord_launch_v1"),
			["dominion_cadence"],
			_talent_definitions(["dominion_cadence"])
		),
		"Launch runtime configures"
	)
	var launch_presentation: Dictionary = launch_runtime.presentation_snapshot()
	_suite.assert_equal(launch_presentation.meter_id, "codex_pages", "Launch meter is profile-authoritative")
	_suite.assert_equal(launch_presentation.resource_minimum, 0, "Launch meter minimum is exact")
	_suite.assert_equal(launch_presentation.resource_maximum, 3, "Launch meter maximum is exact")
	_suite.assert_equal(launch_presentation.resource_value, 0, "Launch meter initial value is exact")
	_suite.assert_equal(launch_presentation.skill_cue_id, "codex_dominion", "Launch cue is exact")
	_suite.assert_equal(launch_presentation.selected_talent_ids, ["dominion_cadence"], "Launch talent projection is exact")
	launch_owner.free()


func _test_replay_neutral_reanchor_is_strictly_scoped() -> void:
	var owner := Node.new()
	var m1_runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		m1_runtime.configure(owner, _profile("wanderer_m1_v1"), []),
		"M1 neutral reanchor fixture configures"
	)
	_suite.assert_true(
		m1_runtime.can_reanchor_replay_neutral_frame(12),
		"M1 Wanderer remains replay-neutral"
	)

	var launch_runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		launch_runtime.configure(owner, _profile("wanderer_launch_v1"), []),
		"Launch Wanderer neutral reanchor fixture configures"
	)
	_suite.assert_true(
		launch_runtime.can_reanchor_replay_neutral_frame(24),
		"talent-free Launch Wanderer with initial resource is replay-neutral"
	)
	_suite.assert_true(
		launch_runtime.reanchor_replay_neutral_frame(24),
		"neutral Launch Wanderer reanchors"
	)
	_suite.assert_equal(
		int((launch_runtime.snapshot().get("strategy", {}) as Dictionary).get(
			"last_runtime_frame",
			-1
		)),
		24,
		"Launch neutral reanchor installs the requested strategy frame"
	)
	_suite.assert_true(
		not launch_runtime.can_reanchor_replay_neutral_frame(-1),
		"negative replay frame is never neutral"
	)
	var before_negative_reanchor := launch_runtime.snapshot()
	_suite.assert_true(
		not launch_runtime.reanchor_replay_neutral_frame(-1),
		"negative replay frame cannot reanchor"
	)
	_suite.assert_equal(
		launch_runtime.snapshot(),
		before_negative_reanchor,
		"negative replay frame rejection is zero-mutation"
	)

	var talented_runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		talented_runtime.configure(
			owner,
			_profile("wanderer_launch_v1"),
			["tal_eternity_reserve"],
			_talent_definitions(["tal_eternity_reserve"])
		),
		"talented Launch Wanderer fixture configures"
	)
	_assert_runtime_reanchor_rejected(
		talented_runtime,
		"Launch Wanderer with a talent"
	)

	var same_character_definition := _definition("wanderer_launch_v1")
	same_character_definition["id"] = "wanderer_other_v1"
	var same_character_profile = CharacterRuntimeProfileScript.from_definition(
		same_character_definition
	)
	_suite.assert_true(
		same_character_profile != null,
		"same-character alternate Profile fixture parses"
	)
	var same_character_other_profile = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		same_character_other_profile.configure(owner, same_character_profile, []),
		"same-character alternate Profile fixture configures"
	)
	_assert_runtime_reanchor_rejected(
		same_character_other_profile,
		"same-character non-authorized Profile"
	)

	var other_profile_runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		other_profile_runtime.configure(owner, _profile("time_guardian_launch_v1"), []),
		"other Launch character fixture configures"
	)
	_assert_runtime_reanchor_rejected(other_profile_runtime, "other Launch character Profile")

	var resource_runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		resource_runtime.configure(owner, _profile("wanderer_launch_v1"), []),
		"resource drift fixture configures"
	)
	var resource_changed := resource_runtime.snapshot()
	(resource_changed["strategy"] as Dictionary)["resource_value"] = 1
	_suite.assert_true(
		resource_runtime.restore_snapshot(resource_changed),
		"resource drift fixture installs a valid non-initial resource"
	)
	_assert_runtime_reanchor_rejected(resource_runtime, "Launch Wanderer with changed resource")

	var faulted_runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		faulted_runtime.configure(owner, _profile("wanderer_launch_v1"), []),
		"runtime fault fixture configures"
	)
	faulted_runtime.set("_restore_integrity_ok", false)
	_assert_runtime_reanchor_rejected(faulted_runtime, "runtime restore-integrity failure")

	var action_runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		action_runtime.configure(owner, _profile("wanderer_launch_v1"), []),
		"active Character action fixture configures"
	)
	var coordinator = CharacterActionCoordinatorScript.new()
	_suite.assert_true(coordinator.configure(action_runtime), "Launch runtime installs in coordinator")
	_suite.assert_true(
		coordinator.can_reanchor_replay_neutral_runtime_frame(24),
		"idle Launch Character coordinator is replay-neutral"
	)
	_suite.assert_true(
		coordinator.reanchor_replay_neutral_runtime_frame(24),
		"idle Launch Character coordinator reanchors"
	)
	_suite.assert_equal(coordinator.runtime_frame(), 24, "coordinator installs the replay frame")
	_suite.assert_equal(
		int((((coordinator.snapshot().get("runtime", {}) as Dictionary).get(
			"strategy",
			{}
		) as Dictionary).get("last_runtime_frame", -1))),
		24,
		"coordinator reanchors the nested Launch Character strategy"
	)
	var idle_action := coordinator.action_snapshot()

	var current_token_only := idle_action.duplicate(true)
	current_token_only["next_token"] = 2
	current_token_only["current_token"] = 1
	current_token_only["committed_plan"] = {}
	current_token_only["revision"] = int(current_token_only["revision"]) + 1
	_suite.assert_true(
		coordinator.restore_action_snapshot(current_token_only),
		"current-token-only fault fixture installs"
	)
	var before_token_rejection := coordinator.snapshot()
	var before_token_action_rejection := coordinator.action_snapshot()
	_suite.assert_true(
		not coordinator.can_reanchor_replay_neutral_runtime_frame(24),
		"current Character token alone rejects neutral reanchor"
	)
	_suite.assert_true(
		not coordinator.reanchor_replay_neutral_runtime_frame(24),
		"current Character token alone cannot reanchor"
	)
	_suite.assert_equal(
		coordinator.snapshot(),
		before_token_rejection,
		"current-token reanchor rejection preserves coordinator runtime state"
	)
	_suite.assert_equal(
		coordinator.action_snapshot(),
		before_token_action_rejection,
		"current-token reanchor rejection preserves action authority"
	)

	_suite.assert_true(
		coordinator.restore_action_snapshot(idle_action),
		"idle Character action authority restores"
	)
	coordinator.set("_committed_plan", {"skill_id": "future_launch_skill"})
	var before_plan_rejection := coordinator.snapshot()
	var before_plan_action_rejection := coordinator.action_snapshot()
	_suite.assert_true(
		not coordinator.can_reanchor_replay_neutral_runtime_frame(24),
		"committed Character plan alone rejects neutral reanchor"
	)
	_suite.assert_true(
		not coordinator.reanchor_replay_neutral_runtime_frame(24),
		"committed Character plan alone cannot reanchor"
	)
	_suite.assert_equal(
		coordinator.snapshot(),
		before_plan_rejection,
		"committed-plan reanchor rejection preserves coordinator runtime state"
	)
	_suite.assert_equal(
		coordinator.action_snapshot(),
		before_plan_action_rejection,
		"committed-plan reanchor rejection preserves action authority"
	)

	coordinator.set("_committed_plan", {})
	var active_action := coordinator.action_snapshot()
	active_action["next_token"] = 2
	active_action["current_token"] = 1
	active_action["committed_plan"] = {"skill_id": "future_launch_skill"}
	active_action["revision"] = int(active_action["revision"]) + 1
	_suite.assert_true(
		coordinator.restore_action_snapshot(active_action),
		"active Character action fixture installs"
	)
	var before_active_rejection := coordinator.snapshot()
	_suite.assert_true(
		not coordinator.can_reanchor_replay_neutral_runtime_frame(24),
		"current Character token and committed plan reject neutral reanchor"
	)
	_suite.assert_true(
		not coordinator.reanchor_replay_neutral_runtime_frame(24),
		"active Character action cannot reanchor"
	)
	_suite.assert_equal(
		coordinator.snapshot(),
		before_active_rejection,
		"active Character action reanchor rejection is zero-mutation"
	)
	_suite.assert_equal(
		coordinator.action_snapshot(),
		active_action,
		"active Character action reanchor rejection preserves action authority"
	)
	owner.free()


func _assert_runtime_reanchor_rejected(runtime, label: String) -> void:
	var before: Dictionary = runtime.snapshot()
	_suite.assert_true(
		not runtime.can_reanchor_replay_neutral_frame(24),
		"%s is not replay-neutral" % label
	)
	_suite.assert_true(
		not runtime.reanchor_replay_neutral_frame(24),
		"%s cannot reanchor" % label
	)
	_suite.assert_equal(
		runtime.snapshot(),
		before,
		"%s reanchor rejection is zero-mutation" % label
	)


func _talent_definitions(ids: Array) -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TALENT_CATALOG_PATH)
	)
	var by_id: Dictionary = {}
	if parsed is Array:
		for value: Variant in parsed:
			if value is Dictionary:
				by_id[str((value as Dictionary).get("id", ""))] = (
					value as Dictionary
				).duplicate(true)
	var result: Array[Dictionary] = []
	for id_value: Variant in ids:
		var talent_id := str(id_value)
		if by_id.has(talent_id):
			result.append((by_id[talent_id] as Dictionary).duplicate(true))
	return result


func _test_production_wrapper_propagates_malformed_events_for_exact_rollback() -> void:
	var owner := Node.new()
	var runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		runtime.configure(owner, _profile("wanderer_m1_v1"), []),
		"production wrapper configures for malformed-result rollback coverage"
	)
	var strategy := SkillRuntime.new()
	runtime.set("_strategy", strategy)
	var coordinator = CharacterActionCoordinatorScript.new()
	_suite.assert_true(coordinator.configure(runtime), "production wrapper installs in coordinator")

	strategy.malformed_advance_after_mutation = true
	var before_advance: Dictionary = coordinator.snapshot()
	var rejected_advance: Dictionary = coordinator.advance_frame(1)
	_suite.assert_true(
		not bool(rejected_advance.get("ok", true)),
		"malformed wrapped frame result is rejected"
	)
	_suite.assert_equal(
		coordinator.snapshot(),
		before_advance,
		"malformed wrapped frame result rolls the production strategy back exactly"
	)

	strategy.malformed_advance_after_mutation = false
	strategy.malformed_after_damage_after_mutation = true
	var before_hook: Dictionary = coordinator.snapshot()
	var rejected_hook: Dictionary = coordinator.after_damage({})
	_suite.assert_true(
		not bool(rejected_hook.get("ok", true)),
		"malformed wrapped event hook is rejected"
	)
	_suite.assert_equal(
		coordinator.snapshot(),
		before_hook,
		"malformed wrapped event hook rolls the production strategy back exactly"
	)
	owner.free()


func _test_production_wrapper_restore_failure_is_exact_or_fail_closed() -> void:
	var owner := Node.new()
	var runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		runtime.configure(owner, _profile("wanderer_m1_v1"), []),
		"production wrapper configures for restore fault coverage"
	)
	var strategy := SkillRuntime.new()
	runtime.set("_strategy", strategy)
	var target: Dictionary = runtime.snapshot()
	strategy.revision = 7
	var before_partial_failure: Dictionary = runtime.snapshot()
	strategy.restore_fault_mode = &"partial_then_successful_rollback"
	strategy.restore_call_count = 0
	_suite.assert_true(
		not runtime.restore_snapshot(target),
		"partially mutating target restore is rejected"
	)
	_suite.assert_equal(
		runtime.snapshot(),
		before_partial_failure,
		"failed target restore rolls back to the exact prior snapshot"
	)
	_suite.assert_true(
		runtime.has_method("restore_integrity_ok"),
		"production wrapper exposes restore integrity state after exact rollback"
	)
	if runtime.has_method("restore_integrity_ok"):
		_suite.assert_true(
			bool(runtime.call("restore_integrity_ok")),
			"exact rollback preserves production wrapper integrity"
		)

	var fail_closed_runtime = PlayerCharacterRuntimeScript.new()
	_suite.assert_true(
		fail_closed_runtime.configure(owner, _profile("wanderer_m1_v1"), []),
		"second production wrapper configures for rollback rejection coverage"
	)
	var fail_closed_strategy := SkillRuntime.new()
	fail_closed_runtime.set("_strategy", fail_closed_strategy)
	var fail_closed_target: Dictionary = fail_closed_runtime.snapshot()
	fail_closed_strategy.revision = 9
	fail_closed_strategy.restore_fault_mode = &"partial_then_reject_rollback"
	fail_closed_strategy.restore_call_count = 0
	_suite.assert_true(
		not fail_closed_runtime.restore_snapshot(fail_closed_target),
		"target restore and rollback rejection fail"
	)
	_suite.assert_true(
		fail_closed_runtime.has_method("restore_integrity_ok"),
		"production wrapper exposes restore integrity state"
	)
	if fail_closed_runtime.has_method("restore_integrity_ok"):
		_suite.assert_true(
			not bool(fail_closed_runtime.call("restore_integrity_ok")),
			"rollback rejection leaves the production wrapper detectably fail-closed"
		)
	_suite.assert_true(
		not fail_closed_runtime.can_restore_snapshot(fail_closed_target),
		"fail-closed wrapper rejects further snapshot installation"
	)
	var fail_closed_coordinator = CharacterActionCoordinatorScript.new()
	_suite.assert_true(
		fail_closed_coordinator.configure(fail_closed_runtime),
		"coordinator can inspect the fail-closed production wrapper"
	)
	var fail_closed_advance: Dictionary = fail_closed_coordinator.advance_frame(1)
	_suite.assert_equal(
		fail_closed_advance.get("code"),
		&"ROLLBACK_FAILED",
		"coordinator detects fail-closed wrapper state instead of committing a frame"
	)
	owner.free()


func _test_coordinator_generation_token_and_rejection_atomicity() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	_suite.assert_true(coordinator.set_generation_floor(5), "generation floor installs")
	_suite.assert_true(coordinator.set_generation_floor(3), "lower generation floor is an idempotent success")
	_suite.assert_equal(coordinator.generation(), 5, "generation never falls below its floor")
	_suite.assert_true(coordinator.set_next_token_floor(20), "token floor installs")
	_suite.assert_true(coordinator.set_next_token_floor(4), "lower token floor is an idempotent success")
	_suite.assert_equal(coordinator.next_token(), 20, "next token never falls below its floor")
	var before_invalid_floor: Dictionary = coordinator.snapshot()
	_suite.assert_true(not coordinator.set_generation_floor(0), "invalid generation floor is rejected")
	_suite.assert_true(not coordinator.set_next_token_floor(0), "invalid token floor is rejected")
	_suite.assert_equal(coordinator.snapshot(), before_invalid_floor, "invalid floors are zero-mutation")

	var runtime := SkillRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "complete skill runtime configures")
	runtime.reject_plan_after_mutation = true
	var before_plan_rejection: Dictionary = coordinator.snapshot()
	var rejected_plan: Dictionary = coordinator.try_character_skill({}, {})
	_suite.assert_true(not bool(rejected_plan.get("ok", true)), "mutating plan rejection fails")
	_suite.assert_equal(rejected_plan.get("events", []), [], "plan rejection publishes no events")
	_suite.assert_equal(coordinator.snapshot(), before_plan_rejection, "plan rejection rolls back exactly")

	runtime.reject_plan_after_mutation = false
	runtime.reject_commit_after_mutation = true
	var before_commit_rejection: Dictionary = coordinator.snapshot()
	var rejected_commit: Dictionary = coordinator.try_character_skill({}, {})
	_suite.assert_true(not bool(rejected_commit.get("ok", true)), "mutating commit rejection fails")
	_suite.assert_equal(rejected_commit.get("events", []), [], "commit rejection publishes no events")
	_suite.assert_equal(coordinator.snapshot(), before_commit_rejection, "commit rejection rolls back exactly")

	runtime.reject_commit_after_mutation = false
	var committed: Dictionary = coordinator.try_character_skill({}, {})
	_suite.assert_true(bool(committed.get("ok", false)), "valid skill plan commits")
	_suite.assert_equal(committed.context.token, 20, "commit consumes the floored token")
	_suite.assert_equal(committed.context.generation, 5, "commit exposes the floored generation")
	var returned_plan: Dictionary = committed.context.plan
	returned_plan.nested.value = 99
	_suite.assert_equal(
		coordinator.action_snapshot().committed_plan.nested.value,
		7,
		"committed plan is immutable to callers"
	)

	_suite.assert_true(coordinator.reset_runtime_state(&"test_reset"), "reset succeeds")
	_suite.assert_equal(coordinator.generation(), 6, "reset invalidates the previous generation")
	_suite.assert_equal(coordinator.current_token(), 0, "reset clears active token")
	_suite.assert_equal(coordinator.next_token(), 21, "reset preserves token monotonicity")

	runtime.malformed_after_damage_after_mutation = true
	var before_hook_rejection: Dictionary = coordinator.snapshot()
	var rejected_hook: Dictionary = coordinator.after_damage({})
	_suite.assert_true(not bool(rejected_hook.get("ok", true)), "malformed mutating hook is rejected")
	_suite.assert_equal(rejected_hook.get("events", []), [], "hook rejection publishes no events")
	_suite.assert_equal(coordinator.snapshot(), before_hook_rejection, "hook rejection rolls back exactly")


func _load_definitions() -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	var values: Array[Dictionary] = []
	if parsed is Array:
		for value: Variant in parsed:
			if value is Dictionary:
				values.append((value as Dictionary).duplicate(true))
	return values


func _definition(profile_id: String) -> Dictionary:
	for value: Dictionary in _definitions:
		if str(value.get("id", "")) == profile_id:
			return value.duplicate(true)
	return {}


func _profile(profile_id: String):
	return CharacterRuntimeProfileScript.from_definition(_definition(profile_id))
