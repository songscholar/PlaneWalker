extends Node

const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunViewStateProjectorScript := preload("res://scripts/application/run_view_state_projector.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const WEAPONS := ["sword", "bow", "gun", "staff", "gauntlets"]
const PROFILE_IDS := {
	"sword": "sword_launch_v1",
	"bow": "bow_launch_v1",
	"gun": "gun_launch_v1",
	"staff": "staff_launch_v1",
	"gauntlets": "gauntlets_launch_v1",
}
const ADAPTER_NODE_NAMES := {
	"sword": "SwordWeapon",
	"bow": "BowWeapon",
	"gun": "GunWeapon",
	"staff": "StaffWeapon",
	"gauntlets": "GauntletsWeapon",
}
const TIME_PAIRS := [
	["stop", "rewind"],
	["stop", "rift"],
	["stop", "accelerate"],
	["rewind", "rift"],
	["rewind", "accelerate"],
	["rift", "accelerate"],
]
const MAX_ACTION_FRAMES := 240
const LAUNCH_ARCHETYPE_SCORES := {
	"freeze_burst": 0,
	"rewind_echo": 0,
	"rift_trap": 0,
	"accelerated_combo": 0,
	"low_hp_void": 0,
	"perfect_guard": 0,
	"piercing_barrage": 0,
	"echo_legion": 0,
}


var _suite
var _profiles: Dictionary = {}
var _time_started: Dictionary = {}
var _time_ended: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_profiles = _profile_catalog()
	_suite.assert_equal(_profiles.size(), 5, "matrix resolves all five authoritative Launch profiles")
	EventBus.time_skill_started.connect(_on_time_skill_started)
	EventBus.time_skill_ended.connect(_on_time_skill_ended)
	var case_index := 0
	for weapon_id: String in WEAPONS:
		for time_pair: Array in TIME_PAIRS:
			var seed_value := 20260901 + case_index
			var first := await _run_case(weapon_id, time_pair, seed_value, 1)
			var second := await _run_case(weapon_id, time_pair, seed_value, 2)
			var label := _case_label(weapon_id, time_pair)
			_suite.assert_true(not first.is_empty(), "%s first deterministic run completes" % label)
			_suite.assert_true(not second.is_empty(), "%s repeated deterministic run completes" % label)
			_suite.assert_equal(str(first.get("pre_reset_digest", "")).length(), 64, "%s first run records a pre-reset digest" % label)
			_suite.assert_equal(str(first.get("post_reset_digest", "")).length(), 64, "%s first run records a post-reset clean digest" % label)
			_suite.assert_equal(first.get("pre_reset_digest"), second.get("pre_reset_digest"), "%s same seed produces the same pre-reset digest" % label)
			_suite.assert_equal(first.get("pre_reset"), second.get("pre_reset"), "%s same seed produces the same pre-reset evidence" % label)
			_suite.assert_equal(first.get("post_reset_digest"), second.get("post_reset_digest"), "%s same seed produces the same post-reset digest" % label)
			_suite.assert_equal(first.get("post_reset"), second.get("post_reset"), "%s same seed produces the same post-reset evidence" % label)
			case_index += 1
	_suite.assert_equal(case_index, 30, "matrix executes five weapons by six legal time pairs")
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "matrix leaves no shared Time Rift nodes")
	EventBus.time_skill_started.disconnect(_on_time_skill_started)
	EventBus.time_skill_ended.disconnect(_on_time_skill_ended)
	_suite.finish(get_tree())


func _run_case(
	weapon_id: String,
	time_pair: Array,
	seed_value: int,
	repetition: int
) -> Dictionary:
	var label := "%s repetition %d" % [_case_label(weapon_id, time_pair), repetition]
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "%s starts without stale Time Rifts" % label)
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var configured: bool = player.configure_loadout(_config(weapon_id, time_pair, seed_value))
	_suite.assert_true(configured, "%s configures the authoritative Launch loadout" % label)
	if not configured:
		await _free_player(player)
		return {}

	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0
	manager.time_stop_duration = 0.02
	manager.time_rift_duration = 0.02
	manager.time_accelerate_duration = 0.02
	if time_pair.has("rewind"):
		player.rewind_recorder.clear_snapshots()
		player.rewind_recorder._record_snapshot()

	var ready_presentation: Dictionary = player.weapon_presentation_snapshot()
	_suite.assert_equal(ready_presentation.get("weapon_id"), weapon_id, "%s presentation exposes the equipped weapon" % label)
	_suite.assert_equal(ready_presentation.get("profile_id"), PROFILE_IDS[weapon_id], "%s presentation exposes the Launch profile" % label)
	_suite.assert_equal(ready_presentation.get("phase"), "READY", "%s begins in READY" % label)
	var ready_view := _project_view(player, weapon_id, time_pair, seed_value, 0)
	_suite.assert_true(bool(ready_view.get("ok", false)), "%s READY presentation produces valid ViewState" % label)

	manager.energy = manager.max_energy
	var representative_action := &"weapon_primary" if weapon_id in ["bow", "gun"] else &"weapon_skill"
	_suite.assert_true(player.try_action(representative_action), "%s commits representative weapon action" % label)
	var active_presentation: Dictionary = player.weapon_presentation_snapshot()
	_suite.assert_true(active_presentation.get("phase") != "READY", "%s representative action enters coordinator authority" % label)
	var active_view := _project_view(player, weapon_id, time_pair, seed_value, 1)
	_suite.assert_true(
		bool(active_view.get("ok", false)),
		"%s active presentation produces valid ViewState: %s from %s" % [
			label,
			str(active_view),
			str(active_presentation),
		]
	)
	if weapon_id in ["bow", "gun"]:
		_suite.assert_true(
			bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")),
			"%s releases the representative %s hold" % [label, weapon_id]
		)
	var active_weapon_evidence := _advance_weapon_to_active(player, weapon_id, label)
	_suite.assert_true(
		int((active_weapon_evidence.get("payloads", {}) as Dictionary).get("total_count", 0)) > 0,
		"%s ACTIVE phase owns at least one real payload node" % label
	)
	_finish_weapon_action(player, "%s representative weapon action completes" % label)

	var time_fact_baseline := _time_fact_snapshot(time_pair)
	var time_ability_evidence: Array[Dictionary] = []
	for ability_value: Variant in time_pair:
		var ability_id := str(ability_value)
		var action_id := StringName("time_%s" % ability_id)
		var starts_before := _start_count(action_id)
		var ends_before := _end_count(action_id)
		manager.energy = manager.max_energy
		_suite.assert_true(player.try_action(action_id), "%s commits equipped %s" % [label, ability_id])
		var start_scene := _time_scene_snapshot(player, manager, time_pair)
		_suite.assert_true(
			_ability_start_is_observable(ability_id, start_scene),
			"%s %s start mutates observable scene state" % [label, ability_id]
		)
		_finish_time_cast(player, "%s completes %s cast" % [label, ability_id])
		player.cancel_active_time_effects(&"p11h_matrix_fact_boundary")
		await get_tree().process_frame
		await get_tree().process_frame
		var end_scene := _time_scene_snapshot(player, manager, time_pair)
		var started_delta := _start_count(action_id) - starts_before
		var ended_delta := _end_count(action_id) - ends_before
		_suite.assert_equal(started_delta, 1, "%s publishes exactly one %s start fact" % [label, ability_id])
		_suite.assert_equal(ended_delta, 1, "%s publishes exactly one %s end fact" % [label, ability_id])
		_suite.assert_true(_time_scene_is_clean(end_scene), "%s %s end leaves clean scene state" % [label, ability_id])
		time_ability_evidence.append({
			"ability_id": ability_id,
			"action_id": str(action_id),
			"started_delta": started_delta,
			"ended_delta": ended_delta,
			"start_scene": start_scene,
			"end_scene": end_scene,
		})

	var post_cast_view := _project_view(player, weapon_id, time_pair, seed_value, 2)
	_suite.assert_true(bool(post_cast_view.get("ok", false)), "%s post-cast presentation produces valid ViewState" % label)
	var persistent_payloads := _weapon_payload_evidence(player, weapon_id)
	var time_facts_before_reset := _time_fact_delta_snapshot(time_pair, time_fact_baseline)
	var pre_reset := _pre_reset_summary(
		player,
		manager,
		post_cast_view.get("view_state", {}),
		weapon_id,
		time_pair,
		seed_value,
		active_weapon_evidence,
		persistent_payloads,
		time_ability_evidence,
		time_facts_before_reset
	)

	player.reset_runtime_state()
	await get_tree().process_frame
	await get_tree().process_frame
	var terminal_view := _project_view(player, weapon_id, time_pair, seed_value, 3)
	_suite.assert_true(bool(terminal_view.get("ok", false)), "%s reset presentation produces valid ViewState" % label)
	_assert_clean_reset(player, manager, label)
	_suite.assert_equal(
		_time_fact_delta_snapshot(time_pair, time_fact_baseline),
		time_facts_before_reset,
		"%s first reset publishes no new time lifecycle facts" % label
	)
	var first_clean := _post_reset_summary(
		player,
		manager,
		player.get_player_ui_snapshot(),
		weapon_id,
		time_pair,
		seed_value,
		time_facts_before_reset
	)

	player.reset_runtime_state()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_clean_reset(player, manager, "%s second reset" % label)
	_suite.assert_equal(
		_time_fact_delta_snapshot(time_pair, time_fact_baseline),
		time_facts_before_reset,
		"%s second reset publishes no new time lifecycle facts" % label
	)
	var second_clean := _post_reset_summary(
		player,
		manager,
		player.get_player_ui_snapshot(),
		weapon_id,
		time_pair,
		seed_value,
		time_facts_before_reset
	)
	_suite.assert_equal(second_clean, first_clean, "%s consecutive resets are functionally idempotent" % label)

	var result := {
		"pre_reset_digest": _value_digest(pre_reset),
		"pre_reset": pre_reset,
		"post_reset_digest": _value_digest(first_clean),
		"post_reset": first_clean,
	}
	await _free_player(player)
	return result


func _project_view(
	player: Node,
	weapon_id: String,
	time_pair: Array,
	seed_value: int,
	step: int
) -> Dictionary:
	var projector = RunViewStateProjectorScript.new()
	var projected = projector.project(
		_authoritative(weapon_id, time_pair, seed_value, step),
		{"room_number": 1, "type": "combat", "reward_kind": "starter"},
		player.get_player_ui_snapshot(),
		null,
		step * 1000,
		{}
	)
	if not projected.ok:
		return {
			"ok": false,
			"code": str(projected.code),
			"context": projected.context.duplicate(true),
		}
	var view_state: Dictionary = projected.context.get("view_state", {})
	var validation = RunViewStateScript.validate(view_state)
	return {
		"ok": bool(validation.ok),
		"code": str(validation.code),
		"context": validation.context.duplicate(true),
		"view_state": RunViewStateScript.copy_of(view_state),
	}


func _finish_weapon_action(player: Node, label: String) -> void:
	for _frame: int in range(MAX_ACTION_FRAMES):
		if player.weapon_presentation_snapshot().get("phase") == "READY":
			break
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "READY", label)


func _finish_time_cast(player: Node, label: String) -> void:
	for _frame: int in range(MAX_ACTION_FRAMES):
		if player.action_state.current_state == PlayerActionStateScript.State.FREE:
			break
		player.advance_action_frame()
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, label)


func _advance_weapon_to_active(player: Node, weapon_id: String, label: String) -> Dictionary:
	for _frame: int in range(MAX_ACTION_FRAMES):
		var presentation: Dictionary = player.weapon_presentation_snapshot()
		if str(presentation.get("phase", "")) == "ACTIVE":
			return {
				"runtime": _weapon_runtime_evidence(player),
				"payloads": _weapon_payload_evidence(player, weapon_id, true),
			}
		if str(presentation.get("phase", "")) == "READY":
			break
		player.advance_action_frame()
	_suite.assert_true(false, "%s representative weapon action reaches ACTIVE" % label)
	return {}


func _assert_clean_reset(player: Node, manager: Node, label: String) -> void:
	var presentation: Dictionary = player.weapon_presentation_snapshot()
	_suite.assert_equal(presentation.get("phase"), "READY", "%s reset returns weapon presentation to READY" % label)
	_suite.assert_equal(int(presentation.get("token", -1)), 0, "%s reset clears active weapon token" % label)
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, "%s reset returns Player action state to FREE" % label)
	_suite.assert_true(not bool(manager.get("_time_stop_active")), "%s reset clears Stop" % label)
	_suite.assert_true(not bool(manager.get("_time_accelerate_active")), "%s reset clears Accelerate" % label)
	_suite.assert_true((manager.get("_active_rifts") as Array).is_empty(), "%s reset clears Time Rift references" % label)
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "%s reset frees Time Rift nodes" % label)
	_suite.assert_true(not player.is_time_accelerated(), "%s reset clears Player acceleration" % label)
	var weapon_id := str(presentation.get("weapon_id", ""))
	_suite.assert_equal(
		int(_weapon_payload_evidence(player, weapon_id).get("total_count", -1)),
		0,
		"%s reset clears prepared and owned weapon payloads" % label
	)


func _pre_reset_summary(
	player: Node,
	manager: Node,
	view_state: Dictionary,
	weapon_id: String,
	time_pair: Array,
	seed_value: int,
	active_weapon_evidence: Dictionary,
	persistent_payloads: Dictionary,
	time_ability_evidence: Array[Dictionary],
	time_facts: Dictionary
) -> Dictionary:
	return {
		"seed": seed_value,
		"weapon_id": weapon_id,
		"time_pair": time_pair.duplicate(true),
		"active_weapon": active_weapon_evidence.duplicate(true),
		"persistent_payloads": persistent_payloads.duplicate(true),
		"weapon_runtime": _weapon_runtime_evidence(player),
		"time_abilities": time_ability_evidence.duplicate(true),
		"time_facts": time_facts.duplicate(true),
		"time_scene": _time_scene_snapshot(player, manager, time_pair),
		"view": _view_evidence(view_state),
	}


func _post_reset_summary(
	player: Node,
	manager: Node,
	ui_snapshot: Dictionary,
	weapon_id: String,
	time_pair: Array,
	seed_value: int,
	time_facts: Dictionary
) -> Dictionary:
	var presentation: Dictionary = player.weapon_presentation_snapshot()
	return {
		"seed": seed_value,
		"weapon_id": weapon_id,
		"profile_id": str(presentation.get("profile_id", "")),
		"profile_version": int(presentation.get("profile_version", 0)),
		"time_pair": time_pair.duplicate(true),
		"phase": str(presentation.get("phase", "")),
		"token": int(presentation.get("token", -1)),
		"action_state": str(ui_snapshot.get("action_state", "")),
		"time_slots": (ui_snapshot.get("time_slots", []) as Array).duplicate(true),
		"weapon_runtime": _weapon_runtime_evidence(player),
		"payloads": _weapon_payload_evidence(player, weapon_id),
		"time_scene": _time_scene_snapshot(player, manager, time_pair),
		"time_facts": time_facts.duplicate(true),
	}


func _view_evidence(view_state: Dictionary) -> Dictionary:
	return {
		"player": (view_state.get("player", {}) as Dictionary).duplicate(true),
		"weapon_state": (view_state.get("weapon_state", {}) as Dictionary).duplicate(true),
	}


func _weapon_runtime_evidence(player: Node) -> Dictionary:
	var replay: Dictionary = player.weapon_replay_snapshot()
	var coordinator := replay.get("coordinator", {}) as Dictionary
	var runtime := coordinator.get("runtime", {}) as Dictionary
	var player_state := replay.get("player_weapon_state", {}) as Dictionary
	return {
		"phase": str(replay.get("phase", "")),
		"token": int(replay.get("token", -1)),
		"action_id": str((coordinator.get("plan", {}) as Dictionary).get("action_id", "")),
		"resources": (runtime.get("resources", {}) as Dictionary).duplicate(true),
		"adapter": (runtime.get("adapter", {}) as Dictionary).duplicate(true),
		"launch_adapter": (runtime.get("launch_adapter", {}) as Dictionary).duplicate(true),
		"resource_transaction": _resource_transaction_evidence(
			coordinator.get("resource_transaction", {}) as Dictionary
		),
		"facts": {
			"action_reward_claims": (player_state.get("action_reward_claims", {}) as Dictionary).duplicate(true),
			"action_ids_by_token": (player_state.get("action_ids_by_token", {}) as Dictionary).duplicate(true),
			"action_generations_by_token": (player_state.get("action_generations_by_token", {}) as Dictionary).duplicate(true),
			"action_token_order": (player_state.get("action_token_order", []) as Array).duplicate(true),
			"hit_fact_claims": (player_state.get("hit_fact_claims", {}) as Dictionary).duplicate(true),
			"resource_fact_state": (player_state.get("resource_fact_state", {}) as Dictionary).duplicate(true),
		},
	}


func _resource_transaction_evidence(transaction: Dictionary) -> Dictionary:
	var accounts: Dictionary = {}
	for account_id_value: Variant in (transaction.get("external_accounts", {}) as Dictionary).keys():
		var account_id := str(account_id_value)
		var state := (transaction.get("external_accounts", {}) as Dictionary).get(account_id_value, {}) as Dictionary
		accounts[account_id] = {
			"ok": bool(state.get("ok", false)),
			"code": str(state.get("code", "")),
			"resource_id": str(state.get("resource_id", "")),
			"current": float(state.get("current", 0.0)),
			"minimum": float(state.get("minimum", 0.0)),
			"maximum": float(state.get("maximum", 0.0)),
		}
	return {
		"configured": bool(transaction.get("configured", false)),
		"weapon_id": str(transaction.get("weapon_id", "")),
		"runtime_owned_resource_ids": (transaction.get("runtime_owned_resource_ids", []) as Array).duplicate(true),
		"external_accounts": accounts,
		"cooldowns": (transaction.get("cooldowns", {}) as Dictionary).duplicate(true),
		"committed_tokens": (transaction.get("committed_tokens", {}) as Dictionary).duplicate(true),
	}


func _weapon_payload_evidence(
	player: Node,
	weapon_id: String,
	include_transient_state: bool = false
) -> Dictionary:
	var adapter := player.get_node_or_null(str(ADAPTER_NODE_NAMES.get(weapon_id, "")))
	if adapter == null:
		return {"prepared": [], "owned": [], "prepared_count": 0, "owned_count": 0, "total_count": 0}
	var prepared: Array = []
	var owned: Array = []
	match weapon_id:
		"sword":
			if adapter.has_method("launch_payload_snapshots_for_test"):
				owned = adapter.call("launch_payload_snapshots_for_test")
		"bow":
			owned = _owned_group_execution_snapshots(player, adapter, "player_arrows", include_transient_state)
		"gun":
			if adapter.has_method("prepared_projectile_snapshots_for_test"):
				prepared = adapter.call("prepared_projectile_snapshots_for_test")
			owned = _owned_group_execution_snapshots(player, adapter, "gun_projectiles", include_transient_state)
		"staff":
			if adapter.has_method("prepared_payload_snapshots_for_test"):
				prepared = adapter.call("prepared_payload_snapshots_for_test")
			if adapter.has_method("owned_payloads_for_test"):
				owned = _execution_snapshots(adapter.call("owned_payloads_for_test"), include_transient_state)
		"gauntlets":
			if adapter.has_method("prepared_payload_snapshots_for_test"):
				prepared = adapter.call("prepared_payload_snapshots_for_test")
			if adapter.has_method("owned_payloads_for_test"):
				owned = _execution_snapshots(adapter.call("owned_payloads_for_test"), include_transient_state)
	if not include_transient_state:
		prepared = _stable_payload_snapshots(prepared)
	return {
		"prepared": prepared.duplicate(true),
		"owned": owned.duplicate(true),
		"prepared_count": prepared.size(),
		"owned_count": owned.size(),
		"total_count": prepared.size() + owned.size(),
	}


func _owned_group_execution_snapshots(
	player: Node,
	adapter: Node,
	group_name: String,
	include_transient_state: bool
) -> Array:
	var owned_nodes: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(group_name):
		if (
			is_instance_valid(node)
			and not node.is_queued_for_deletion()
			and node.get("owner_entity") == player
			and node.get("source") == adapter
		):
			owned_nodes.append(node)
	return _execution_snapshots(owned_nodes, include_transient_state)


func _execution_snapshots(nodes_value: Variant, include_transient_state: bool) -> Array:
	var result: Array = []
	if not nodes_value is Array:
		return result
	for node_value: Variant in nodes_value as Array:
		if not node_value is Node or not is_instance_valid(node_value):
			continue
		var node := node_value as Node
		if node.is_queued_for_deletion() or not node.has_method("execution_snapshot"):
			continue
		var snapshot_value: Variant = node.call("execution_snapshot")
		if snapshot_value is Dictionary:
			var snapshot := (snapshot_value as Dictionary).duplicate(true)
			if include_transient_state and node is Node2D:
				snapshot["world_position"] = (node as Node2D).global_position
			result.append(snapshot if include_transient_state else _stable_payload_snapshot(snapshot))
	return result


func _stable_payload_snapshots(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		if value is Dictionary:
			result.append(_stable_payload_snapshot(value as Dictionary))
	return result


func _stable_payload_snapshot(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field: String in [
		"action_token",
		"generation",
		"source_action_id",
		"descriptor_id",
		"outcome_id",
		"outcome_index",
		"deterministic_seed",
		"kind",
		"mode",
		"parameters",
		"damage",
		"damage_type",
		"time_damage_ratio",
		"pierce_mode",
		"element_id",
		"status_source_id",
		"source_id",
		"boss_conversion",
		"time_interactions",
	]:
		if snapshot.has(field):
			var value: Variant = snapshot[field]
			result[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result


func _time_scene_snapshot(player: Node, manager: Node, time_pair: Array) -> Dictionary:
	var context: Dictionary = manager.weapon_interaction_context()
	var cooldowns: Dictionary = {}
	for ability_value: Variant in time_pair:
		var action_id := StringName("time_%s" % str(ability_value))
		cooldowns[str(action_id)] = float(manager.get_cooldown(action_id))
	return {
		"energy": float(manager.energy),
		"max_energy": float(manager.max_energy),
		"cooldowns": cooldowns,
		"stop_active": bool(context.get("stop_active", false)),
		"rewind_echo_available": bool(context.get("rewind_echo_available", false)),
		"rift_active": bool(context.get("rift_active", false)),
		"active_rift_count": int(context.get("active_rift_count", 0)),
		"active_rifts": (context.get("active_rifts", []) as Array).duplicate(true),
		"accelerate_active": bool(context.get("accelerate_active", false)),
		"player_accelerated": player.is_time_accelerated(),
		"scene_rift_count": get_tree().get_nodes_in_group("time_rifts").size(),
	}


func _ability_start_is_observable(ability_id: String, scene: Dictionary) -> bool:
	match ability_id:
		"stop":
			return bool(scene.get("stop_active", false))
		"rewind":
			return bool(scene.get("rewind_echo_available", false))
		"rift":
			return bool(scene.get("rift_active", false)) and int(scene.get("scene_rift_count", 0)) == 1
		"accelerate":
			return bool(scene.get("accelerate_active", false)) and bool(scene.get("player_accelerated", false))
	return false


func _time_scene_is_clean(scene: Dictionary) -> bool:
	return (
		not bool(scene.get("stop_active", true))
		and not bool(scene.get("rewind_echo_available", true))
		and not bool(scene.get("rift_active", true))
		and int(scene.get("active_rift_count", -1)) == 0
		and int(scene.get("scene_rift_count", -1)) == 0
		and not bool(scene.get("accelerate_active", true))
		and not bool(scene.get("player_accelerated", true))
	)


func _time_fact_snapshot(time_pair: Array) -> Dictionary:
	var result: Dictionary = {}
	for ability_value: Variant in time_pair:
		var action_id := StringName("time_%s" % str(ability_value))
		result[str(action_id)] = {
			"started": _start_count(action_id),
			"ended": _end_count(action_id),
		}
	return result


func _time_fact_delta_snapshot(time_pair: Array, baseline: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for ability_value: Variant in time_pair:
		var action_id := StringName("time_%s" % str(ability_value))
		var before := baseline.get(str(action_id), {}) as Dictionary
		result[str(action_id)] = {
			"started": _start_count(action_id) - int(before.get("started", 0)),
			"ended": _end_count(action_id) - int(before.get("ended", 0)),
		}
	return result


func _start_count(action_id: StringName) -> int:
	return int(_time_started.get(action_id, 0))


func _end_count(action_id: StringName) -> int:
	return int(_time_ended.get(action_id, 0))


func _on_time_skill_started(action_id: StringName, _context: Dictionary) -> void:
	_time_started[action_id] = _start_count(action_id) + 1


func _on_time_skill_ended(action_id: StringName, _context: Dictionary) -> void:
	_time_ended[action_id] = _end_count(action_id) + 1


func _value_digest(value: Dictionary) -> String:
	return JSON.stringify(value, "", true).sha256_text()


func _authoritative(
	weapon_id: String,
	time_pair: Array,
	seed_value: int,
	step: int
) -> Dictionary:
	return {
		"schema_version": 1,
		"run_id": "p11h-%s-%s-%s-%d" % [weapon_id, str(time_pair[0]), str(time_pair[1]), seed_value],
		"revision": step,
		"phase": RunPhaseScript.Value.COMBAT_ACTIVE,
		"suspended": false,
		"run_seed": seed_value,
		"current_room": 1,
		"room_total": 5,
		"run_time_ms": step * 1000,
		"build": {
			"items": [],
			"blessings": [],
			"curses": [],
			"talents": [],
			"reward_history": [],
			"archetypes": LAUNCH_ARCHETYPE_SCORES.duplicate(true),
			"dominant_archetype": "",
		},
		"open_offer": {},
		"consumed_offer_ids": [],
		"result": {},
		"config": {"milestone": "LAUNCH"},
	}


func _config(weapon_id: String, time_pair: Array, seed_value: int) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": weapon_id,
		"enabled_time_skills": time_pair.duplicate(true),
		"difficulty": "normal",
		"seed": seed_value,
		"weapon_profile": (_profiles.get(weapon_id, {}) as Dictionary).duplicate(true),
	}


func _profile_catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/content_packs/base/content/weapon_runtime_profiles.json")
	)
	var result: Dictionary = {}
	if not parsed is Array:
		return result
	for definition_value: Variant in parsed as Array:
		if not definition_value is Dictionary:
			continue
		var definition := definition_value as Dictionary
		var profile_id := str(definition.get("id", ""))
		for weapon_id: String in WEAPONS:
			if profile_id == str(PROFILE_IDS[weapon_id]):
				result[weapon_id] = definition.duplicate(true)
	return result


func _case_label(weapon_id: String, time_pair: Array) -> String:
	return "%s × %s+%s" % [weapon_id, str(time_pair[0]), str(time_pair[1])]


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.cancel_transient_actions()
		var health: Node = player.get_node("HealthComponent")
		if not (health.get("_active_invulnerability_tokens") as Dictionary).is_empty():
			await get_tree().create_timer(0.55).timeout
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
