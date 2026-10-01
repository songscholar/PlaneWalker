extends Node

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const CharacterActionCoordinatorScript := preload(
	"res://scripts/player/characters/character_action_coordinator.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class CharacterCoordinatorProbe extends RefCounted:
	var accept_intents: bool = false
	var attempts: Array[Dictionary] = []
	var cancellation_reasons: Array[StringName] = []
	var current_generation: int = 3
	var current_token: int = 7
	var uncommitted: bool = false


	func try_character_skill(intent: Variant, context: Variant) -> Dictionary:
		attempts.append({
			"intent": (intent as Dictionary).duplicate(true),
			"context": (context as Dictionary).duplicate(true),
		})
		if not accept_intents:
			return {"ok": false, "code": "REJECTED", "events": [], "context": {}}
		uncommitted = true
		return {
			"ok": true,
			"code": "OK",
			"events": [],
			"context": {"generation": current_generation, "token": current_token},
		}


	func owns_action(generation: int, token: int) -> bool:
		return generation == current_generation and token == current_token


	func has_uncommitted_action() -> bool:
		return uncommitted


	func cancel_uncommitted_action(reason: StringName) -> bool:
		cancellation_reasons.append(reason)
		uncommitted = false
		return true


class PriorityPlayer extends PlayerControllerScript:
	var accepted_actions: Dictionary = {}
	var accepted_weapon_actions: Dictionary = {}
	var action_attempts: Array[StringName] = []
	var weapon_attempts: Array[StringName] = []
	var declared_weapon_order: Array[StringName] = [
		&"weapon_secondary",
		&"weapon_primary",
		&"weapon_utility",
		&"weapon_skill",
		&"weapon_ultimate",
	]


	func try_action(action_id: StringName) -> bool:
		action_attempts.append(action_id)
		return bool(accepted_actions.get(action_id, false))


	func _submit_normalized_weapon_intent(intent: Dictionary) -> bool:
		var action_id := StringName(str(intent.get("id", "")))
		weapon_attempts.append(action_id)
		return bool(accepted_weapon_actions.get(action_id, false))


	func _weapon_semantic_priority_order() -> Array[StringName]:
		return declared_weapon_order.duplicate()


class CancellableRuntimeProbe extends RefCounted:
	var last_runtime_frame: int = -1
	var revision: int = 0
	var active: bool = true
	var committed: bool = false
	var cancel_reasons: Array[StringName] = []
	var reset_reasons: Array[StringName] = []


	func advance_frame(context: Dictionary) -> Array[Dictionary]:
		last_runtime_frame = int(context.get("runtime_frame", -1))
		revision += 1
		return []


	func snapshot() -> Dictionary:
		return {
			"last_runtime_frame": last_runtime_frame,
			"revision": revision,
			"active": active,
			"committed": committed,
			"cancel_reasons": cancel_reasons.duplicate(),
			"reset_reasons": reset_reasons.duplicate(),
		}


	func can_restore_snapshot(value: Dictionary) -> bool:
		return (
			value.size() == 6
			and typeof(value.get("last_runtime_frame")) == TYPE_INT
			and typeof(value.get("revision")) == TYPE_INT
			and typeof(value.get("active")) == TYPE_BOOL
			and typeof(value.get("committed")) == TYPE_BOOL
			and value.get("cancel_reasons") is Array
			and value.get("reset_reasons") is Array
		)


	func restore_snapshot(value: Dictionary) -> bool:
		if not can_restore_snapshot(value):
			return false
		last_runtime_frame = int(value["last_runtime_frame"])
		revision = int(value["revision"])
		active = bool(value["active"])
		committed = bool(value["committed"])
		cancel_reasons = (value["cancel_reasons"] as Array).duplicate()
		reset_reasons = (value["reset_reasons"] as Array).duplicate()
		return snapshot() == value


	func reset_runtime_state(reason: StringName) -> void:
		last_runtime_frame = -1
		revision += 1
		active = false
		committed = false
		reset_reasons.append(reason)


	func character_action_cancellation_state() -> Dictionary:
		return {"active": active, "committed": committed}


	func cancel_uncommitted_action(reason: StringName) -> Dictionary:
		if not active or committed:
			return {"ok": true, "cancelled": false}
		active = false
		revision += 1
		cancel_reasons.append(reason)
		return {"ok": true, "cancelled": true}


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_dash_acceptance_suppresses_every_lower_priority_edge()
	_test_rejection_falls_through_in_exact_slot_and_profile_order()
	_test_character_acceptance_suppresses_weapon_and_owns_release()
	_test_suppressed_or_unowned_character_release_never_reaches_coordinator()
	_test_character_cancellation_boundary_clears_owned_hold()
	await _test_dash_hitstun_rewind_death_reset_and_loadout_boundaries()
	_suite.finish(get_tree())


func _test_dash_acceptance_suppresses_every_lower_priority_edge() -> void:
	var fixture := _fixture()
	var player := fixture.player as PriorityPlayer
	var coordinator := fixture.coordinator as CharacterCoordinatorProbe
	player.accepted_actions[&"dash"] = true
	_suite.assert_true(player.call("_apply_frame_intents", _all_edges()), "priority arbitration completes")
	_suite.assert_equal(player.action_attempts, [&"dash"], "accepted Dash stops all lower-priority attempts")
	_suite.assert_equal(coordinator.attempts, [], "accepted Dash never submits Character Skill")
	_suite.assert_equal(player.weapon_attempts, [], "accepted Dash never submits a weapon edge")
	var arbitration: Dictionary = player.priority_arbitration_snapshot()
	_suite.assert_equal(
		arbitration.get("accepted", {}).get("id"),
		"dash",
		"arbitration records Dash as the winner"
	)
	_suite.assert_equal(
		_statuses(arbitration),
		["accepted", "priority_suppressed", "priority_suppressed", "priority_suppressed", "priority_suppressed", "priority_suppressed"],
		"every lower-priority same-frame edge is explicitly suppressed"
	)
	_free_fixture(fixture)


func _test_rejection_falls_through_in_exact_slot_and_profile_order() -> void:
	var fixture := _fixture()
	var player := fixture.player as PriorityPlayer
	var coordinator := fixture.coordinator as CharacterCoordinatorProbe
	player.accepted_weapon_actions[&"weapon_primary"] = true
	_suite.assert_true(player.call("_apply_frame_intents", _all_edges()), "fallthrough arbitration completes")
	_suite.assert_equal(
		player.action_attempts,
		[&"dash", &"time_slot_1", &"time_slot_2"],
		"rejected Dash falls through Time slots in fixed slot order"
	)
	_suite.assert_equal(coordinator.attempts.size(), 1, "rejected Time slots fall through to Character Skill")
	_suite.assert_equal(
		player.weapon_attempts,
		[&"weapon_secondary", &"weapon_primary"],
		"rejected Character falls through weapon semantics in profile declaration order"
	)
	var arbitration: Dictionary = player.priority_arbitration_snapshot()
	_suite.assert_equal(
		arbitration.get("accepted", {}).get("id"),
		"weapon_primary",
		"first accepted declared weapon semantic wins"
	)
	_suite.assert_equal(
		_statuses(arbitration),
		["rejected", "rejected", "rejected", "rejected", "rejected", "accepted"],
		"rejected attempts mutate no suppression state and continue"
	)
	_free_fixture(fixture)


func _test_character_acceptance_suppresses_weapon_and_owns_release() -> void:
	var fixture := _fixture()
	var player := fixture.player as PriorityPlayer
	var coordinator := fixture.coordinator as CharacterCoordinatorProbe
	coordinator.accept_intents = true
	_suite.assert_true(
		player.call("_apply_frame_intents", {
			"character": [_intent(&"character_skill", &"pressed", 0, &"hold")],
			"weapon": [_intent(&"weapon_primary", &"pressed", 0, &"press")],
		}),
		"Character press arbitration completes"
	)
	_suite.assert_equal(coordinator.attempts.size(), 1, "Character press reaches its coordinator once")
	_suite.assert_equal(player.weapon_attempts, [], "accepted Character press suppresses weapon input")
	_suite.assert_true(
		bool(player.character_input_owner_snapshot().get("active", false)),
		"accepted Character press installs hold ownership"
	)

	_suite.assert_true(
		player.call("_apply_frame_intents", {
			"character": [_intent(&"character_skill", &"released", 31, &"hold")],
		}),
		"owned Character release arbitration completes"
	)
	_suite.assert_equal(coordinator.attempts.size(), 2, "owned release returns to the same coordinator")
	_suite.assert_equal(
		coordinator.attempts[1].intent.get("edge"),
		&"released",
		"coordinator receives the semantic release edge"
	)
	_suite.assert_true(
		not bool(player.character_input_owner_snapshot().get("active", true)),
		"physical release clears hold ownership"
	)
	_free_fixture(fixture)


func _test_suppressed_or_unowned_character_release_never_reaches_coordinator() -> void:
	var fixture := _fixture()
	var player := fixture.player as PriorityPlayer
	var coordinator := fixture.coordinator as CharacterCoordinatorProbe
	coordinator.accept_intents = true
	player.accepted_actions[&"dash"] = true
	player.call("_apply_frame_intents", {
		"dash": [_intent(&"dash", &"pressed", 0, &"press")],
		"character": [_intent(&"character_skill", &"pressed", 0, &"hold")],
	})
	_suite.assert_equal(coordinator.attempts, [], "suppressed Character press creates no coordinator state")
	_suite.assert_true(
		not bool(player.character_input_owner_snapshot().get("active", true)),
		"suppressed Character press creates no hold owner"
	)
	player.accepted_actions.clear()
	player.call("_apply_frame_intents", {
		"character": [_intent(&"character_skill", &"released", 12, &"hold")],
	})
	_suite.assert_equal(coordinator.attempts, [], "unowned release never reaches a coordinator")
	_suite.assert_equal(
		_statuses(player.priority_arbitration_snapshot()),
		["unowned_edge"],
		"unowned release is recorded and discarded instead of buffered"
	)
	_free_fixture(fixture)


func _test_character_cancellation_boundary_clears_owned_hold() -> void:
	var fixture := _fixture()
	var player := fixture.player as PriorityPlayer
	var coordinator := fixture.coordinator as CharacterCoordinatorProbe
	coordinator.accept_intents = true
	player.call("_apply_frame_intents", {
		"character": [_intent(&"character_skill", &"pressed", 0, &"hold")],
	})
	_suite.assert_true(
		player.call("_cancel_uncommitted_character_action", &"gameplay_rewind"),
		"Gameplay Rewind cancellation boundary succeeds"
	)
	_suite.assert_equal(
		coordinator.cancellation_reasons,
		[&"gameplay_rewind"],
		"typed cancellation reason reaches the owning coordinator"
	)
	_suite.assert_true(
		not bool(player.character_input_owner_snapshot().get("active", true)),
		"cancellation clears controller hold ownership"
	)
	_free_fixture(fixture)


func _test_dash_hitstun_rewind_death_reset_and_loadout_boundaries() -> void:
	var dash := await _spawn_player_with_uncommitted_character()
	_suite.assert_true(dash.player.call("_begin_dash"), "Dash commits after cancelling uncommitted Character action")
	_suite.assert_equal(dash.runtime.cancel_reasons, [&"dash"], "Dash uses its typed cancellation boundary")
	await get_tree().create_timer(0.25).timeout
	await _free_player(dash.player)
	dash.clear()

	var hitstun := await _spawn_player_with_uncommitted_character()
	_suite.assert_true(hitstun.player.apply_hitstun_frames(5), "hitstun commits after Character cancellation")
	_suite.assert_equal(hitstun.runtime.cancel_reasons, [&"hitstun"], "hitstun cancels before transition")
	await _free_player(hitstun.player)
	hitstun.clear()

	var rewind := await _spawn_player_with_uncommitted_character()
	var target := {
		"run_id": rewind.player.current_run_id(),
		"position": Vector2(24.0, 36.0),
		"velocity": Vector2.ZERO,
		"facing": Vector2.RIGHT,
	}
	_suite.assert_true(
		rewind.player.install_gameplay_rewind_state(target),
		"Gameplay Rewind installs after Character cancellation"
	)
	_suite.assert_equal(
		rewind.runtime.cancel_reasons,
		[&"gameplay_rewind"],
		"Gameplay Rewind cancels before restoring player movement"
	)
	await _free_player(rewind.player)
	rewind.clear()

	var death := await _spawn_player_with_uncommitted_character()
	death.player.call("_on_died", null)
	_suite.assert_equal(death.runtime.cancel_reasons, [&"player_died"], "death clears uncommitted Character action")
	_suite.assert_true(
		not bool(death.player.character_input_owner_snapshot().get("active", true)),
		"death clears Character input ownership"
	)
	await _free_player(death.player)
	death.clear()

	var reset := await _spawn_player_with_uncommitted_character()
	_suite.assert_true(reset.player.reset_runtime_state(), "runtime reset completes with pending Character action")
	_suite.assert_equal(
		reset.runtime.cancel_reasons,
		[&"player_runtime_reset"],
		"runtime reset cancels before coordinator reset"
	)
	_suite.assert_equal(
		reset.runtime.reset_reasons,
		[&"player_runtime_reset"],
		"runtime reset still reaches the coordinator reset contract"
	)
	await _free_player(reset.player)
	reset.clear()

	var replacement := await _spawn_player_with_uncommitted_character()
	var accepted_config: Dictionary = replacement.player.loadout_runtime.snapshot()
	_suite.assert_true(
		replacement.player.configure_loadout(accepted_config),
		"loadout replacement completes after old Character cancellation"
	)
	_suite.assert_equal(
		replacement.runtime.cancel_reasons,
		[&"loadout_replacement"],
		"loadout replacement cancels the old coordinator before swapping it"
	)
	_suite.assert_true(
		not bool(replacement.player.character_input_owner_snapshot().get("active", true)),
		"loadout replacement clears the old hold owner"
	)
	await _free_player(replacement.player)
	replacement.clear()


func _fixture() -> Dictionary:
	var player := PriorityPlayer.new()
	var coordinator := CharacterCoordinatorProbe.new()
	player.character_action_coordinator = coordinator
	return {"player": player, "coordinator": coordinator}


func _spawn_player_with_uncommitted_character() -> Dictionary:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var runtime := CancellableRuntimeProbe.new()
	var coordinator := CharacterActionCoordinatorScript.new()
	_suite.assert_true(coordinator.configure(runtime), "boundary probe coordinator configures")
	coordinator.set("_current_token", 7)
	coordinator.set("_next_token", 8)
	coordinator.set("_committed_plan", {"skill_id": "boundary_probe"})
	player.character_action_coordinator = coordinator
	player.set("_character_skill_input_owner", {"generation": 1, "token": 7})
	return {"player": player, "runtime": runtime}


func _free_player(player: Node) -> void:
	player.queue_free()
	await get_tree().process_frame


func _free_fixture(fixture: Dictionary) -> void:
	(fixture.player as PriorityPlayer).free()


func _all_edges() -> Dictionary:
	return {
		"dash": [_intent(&"dash", &"pressed", 0, &"press")],
		"time": [
			_intent(&"time_slot_2", &"pressed", 0, &"press"),
			_intent(&"time_slot_1", &"pressed", 0, &"press"),
		],
		"character": [_intent(&"character_skill", &"pressed", 0, &"hold")],
		"weapon": [
			_intent(&"weapon_primary", &"pressed", 0, &"press"),
			_intent(&"weapon_secondary", &"pressed", 0, &"press"),
		],
	}


func _intent(
	action_id: StringName,
	edge: StringName,
	held_frames: int,
	mode: StringName
) -> Dictionary:
	return {
		"id": action_id,
		"edge": edge,
		"held_frames": held_frames,
		"mode": mode,
	}


func _statuses(snapshot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for decision_value: Variant in snapshot.get("decisions", []) as Array:
		result.append(str((decision_value as Dictionary).get("status", "")))
	return result
