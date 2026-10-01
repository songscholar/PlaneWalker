class_name CharacterWeaponTimeMatrixRunner
extends RefCounted

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunViewStateProjectorScript := preload(
	"res://scripts/application/run_view_state_projector.gd"
)
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")

const REQUIRED_LAUNCH_REPLAY_SCHEMA_VERSION := 4
const MAX_ACTION_FRAMES := 96
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
const WEAPONS: Array[StringName] = [
	&"sword",
	&"bow",
	&"gun",
	&"staff",
	&"gauntlets",
]
const TIME_PAIRS: Array[Array] = [
	[&"stop", &"rewind"],
	[&"stop", &"rift"],
	[&"stop", &"accelerate"],
	[&"rewind", &"rift"],
	[&"rewind", &"accelerate"],
	[&"rift", &"accelerate"],
]
const CHARACTER_PROFILE_IDS := {
	&"wanderer": "wanderer_launch_v1",
	&"time_guardian": "time_guardian_launch_v1",
	&"void_walker": "void_walker_launch_v1",
	&"primordial_knight": "primordial_knight_launch_v1",
	&"time_lord": "time_lord_launch_v1",
}
const MASTERY_IDS := {
	&"sword": &"sword_perfect_guard",
	&"bow": &"bow_full_charge_weakpoint",
	&"gun": &"gun_perfect_reload",
	&"staff": &"staff_ordered_combination",
	&"gauntlets": &"gauntlets_dodge_counter",
}

var _host: Node
var _registry: RefCounted
var _suite


func run(host: Node, suite, character_id: StringName) -> void:
	_host = host
	_suite = suite
	_registry = ContentRegistryScript.new()
	_suite.assert_true(
		CHARACTER_PROFILE_IDS.has(character_id),
		"%s is one of the five canonical Launch characters" % str(character_id)
	)
	if not CHARACTER_PROFILE_IDS.has(character_id):
		return
	var report: RefCounted = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(
		not report.call("has_blocking_errors"),
		"%s matrix loads the authoritative Base Pack" % str(character_id)
	)
	if report.call("has_blocking_errors"):
		return

	var configured_cases := await _verify_real_player_configuration_matrix(character_id)
	_suite.assert_equal(
		configured_cases,
		30,
		"%s configures all five weapons by six time pairs on the real Player" % str(character_id)
	)
	if configured_cases != 30:
		return

	# Task 8 depends on the Task 6 character ViewState and Task 7 Player Replay
	# schema. Fail closed once, before the expensive repeated matrix, when either
	# shared authority is absent.
	if not await _shared_p12_contracts_are_ready(character_id):
		return

	var case_index := 0
	for weapon_id: StringName in WEAPONS:
		for time_pair: Array in TIME_PAIRS:
			var seed_value := 20261001 + case_index
			var first := await _run_case(
				character_id,
				weapon_id,
				time_pair,
				seed_value,
				1
			)
			var second := await _run_case(
				character_id,
				weapon_id,
				time_pair,
				seed_value,
				2
			)
			var label := _case_label(character_id, weapon_id, time_pair)
			_suite.assert_true(not first.is_empty(), "%s first deterministic run completes" % label)
			_suite.assert_true(not second.is_empty(), "%s repeated deterministic run completes" % label)
			if not first.is_empty() and not second.is_empty():
				_suite.assert_equal(
					first.get("pre_reset_digest"),
					second.get("pre_reset_digest"),
					"%s repeated seed preserves the pre-reset digest" % label
				)
				_suite.assert_equal(
					first.get("pre_reset"),
					second.get("pre_reset"),
					"%s repeated seed preserves pre-reset evidence" % label
				)
				_suite.assert_equal(
					first.get("post_reset_digest"),
					second.get("post_reset_digest"),
					"%s repeated seed preserves the clean-reset digest" % label
				)
				_suite.assert_equal(
					first.get("post_reset"),
					second.get("post_reset"),
					"%s repeated seed preserves clean-reset evidence" % label
				)
			case_index += 1
	_suite.assert_equal(
		case_index,
		30,
		"%s executes exactly five weapons by six canonical time pairs twice" % str(character_id)
	)
	_suite.assert_true(
		_host.get_tree().get_nodes_in_group("time_rifts").is_empty(),
		"%s matrix leaves no shared Time Rift nodes" % str(character_id)
	)


func _verify_real_player_configuration_matrix(character_id: StringName) -> int:
	var configured_cases := 0
	for weapon_id: StringName in WEAPONS:
		for time_pair: Array in TIME_PAIRS:
			var player: Node = await _spawn_player()
			var label: String = _case_label(character_id, weapon_id, time_pair)
			var configured: bool = player.configure_loadout(
				_config(character_id, weapon_id, time_pair, 20261001 + configured_cases)
			)
			_suite.assert_true(configured, "%s authoritative Player configuration succeeds" % label)
			if configured:
				configured_cases += 1
				var character: Dictionary = player.character_presentation_snapshot()
				var weapon: Dictionary = player.weapon_presentation_snapshot()
				_suite.assert_equal(
					StringName(str(character.get("character_id", ""))),
					character_id,
					"%s installs the requested character runtime" % label
				)
				_suite.assert_equal(
					str(character.get("profile_id", "")),
					str(CHARACTER_PROFILE_IDS[character_id]),
					"%s installs the authoritative character profile" % label
				)
				_suite.assert_equal(
					StringName(str(weapon.get("weapon_id", ""))),
					weapon_id,
					"%s installs the requested weapon runtime" % label
				)
			await _free_player(player)
	return configured_cases


func _shared_p12_contracts_are_ready(character_id: StringName) -> bool:
	var player := await _spawn_player()
	var config := _config(character_id, &"sword", TIME_PAIRS[0], 20261001)
	var configured: bool = player.configure_loadout(config)
	_suite.assert_true(configured, "%s P12 prerequisite probe configures" % str(character_id))
	if not configured:
		await _free_player(player)
		return false
	_bind_room(player, 1)
	var frame_advanced: bool = player.advance_action_frame({})
	_suite.assert_true(
		frame_advanced,
		"%s P12 prerequisite probe reaches the fixed-frame authority" % str(character_id)
	)
	var view_result := _project_view(player, character_id, &"sword", TIME_PAIRS[0], 20261001, 1)
	var formal_character_state := (
		(view_result.get("view_state", {}) as Dictionary).get("character_state", {}) as Dictionary
	)
	var character_view_ready := (
		bool(view_result.get("ok", false))
		and not formal_character_state.is_empty()
		and StringName(str(formal_character_state.get("character_id", ""))) == character_id
	)
	_suite.assert_true(
		character_view_ready,
		"%s requires Task 6 formal character_state ViewState projection" % str(character_id)
	)

	var replay: Dictionary = player.full_player_replay_snapshot()
	var replay_schema_ready := int(replay.get("schema_version", 0)) == REQUIRED_LAUNCH_REPLAY_SCHEMA_VERSION
	_suite.assert_equal(
		int(replay.get("schema_version", 0)),
		REQUIRED_LAUNCH_REPLAY_SCHEMA_VERSION,
		"%s requires Task 7 Player Replay schema 4" % str(character_id)
	)

	var skill_ready := await _commit_character_skill(player, character_id, "prerequisite probe")
	_suite.assert_true(
		skill_ready,
		"%s character skill commits through advance_action_frame semantic input" % str(character_id)
	)
	await _free_player(player)
	return frame_advanced and character_view_ready and replay_schema_ready and skill_ready


func _run_case(
	character_id: StringName,
	weapon_id: StringName,
	time_pair: Array,
	seed_value: int,
	repetition: int
) -> Dictionary:
	var label := "%s repetition %d" % [
		_case_label(character_id, weapon_id, time_pair),
		repetition,
	]
	var player := await _spawn_player()
	var configured: bool = player.configure_loadout(
		_config(character_id, weapon_id, time_pair, seed_value)
	)
	_suite.assert_true(configured, "%s configures the authoritative Launch loadout" % label)
	if not configured:
		await _free_player(player)
		return {}
	_bind_room(player, 1)
	_suite.assert_true(player.advance_action_frame({}), "%s binds the first runtime frame" % label)

	var mastery := _commit_mastery(player, weapon_id, time_pair, seed_value)
	_suite.assert_true(bool(mastery.get("ok", false)), "%s commits one mastery-family fact" % label)
	_suite.assert_true(
		await _commit_character_skill(player, character_id, label),
		"%s commits the representative character skill" % label
	)

	var time_evidence: Array[Dictionary] = []
	for ability_value: Variant in time_pair:
		var ability_id := StringName(str(ability_value))
		var committed := await _commit_time_ability(player, ability_id, label)
		_suite.assert_true(
			bool(committed.get("ok", false)),
			"%s commits equipped %s through semantic input" % [label, str(ability_id)]
		)
		time_evidence.append(committed)

	var projected := _project_view(
		player,
		character_id,
		weapon_id,
		time_pair,
		seed_value,
		2
	)
	_suite.assert_true(bool(projected.get("ok", false)), "%s validates RunViewState" % label)
	var view_state := projected.get("view_state", {}) as Dictionary
	_suite.assert_equal(
		StringName(str((view_state.get("character_state", {}) as Dictionary).get(
			"character_id", ""
		))),
		character_id,
		"%s formal Character ViewState keeps the selected character" % label
	)
	_suite.assert_equal(
		StringName(str((view_state.get("weapon_state", {}) as Dictionary).get("weapon_id", ""))),
		weapon_id,
		"%s formal Weapon ViewState keeps the selected weapon" % label
	)

	var replay: Dictionary = player.full_player_replay_snapshot()
	_suite.assert_equal(
		int(replay.get("schema_version", 0)),
		REQUIRED_LAUNCH_REPLAY_SCHEMA_VERSION,
		"%s records Launch Player Replay schema 4" % label
	)
	var manager: Node = player.get_node("TimeManager")
	var world: Node = player.get_node("WorldPayloadAuthority")
	var time_root: Dictionary = manager.call("replay_snapshot")
	var world_root: Dictionary = world.call("replay_snapshot")
	_suite.assert_equal(
		replay.get("time_manager_state"),
		time_root,
		"%s Replay authenticates the exact TimeManager root" % label
	)
	_suite.assert_equal(
		replay.get("world_payload_state"),
		world_root,
		"%s Replay authenticates the exact WorldPayload root" % label
	)

	var pre_reset := {
		"seed": seed_value,
		"character": player.character_presentation_snapshot(),
		"weapon": player.weapon_presentation_snapshot(),
		"mastery": mastery,
		"time_abilities": time_evidence,
		"time_root": time_root,
		"world_root": world_root,
		"view": {
			"character_state": (view_state.get("character_state", {}) as Dictionary).duplicate(true),
			"weapon_state": (view_state.get("weapon_state", {}) as Dictionary).duplicate(true),
		},
		"replay": replay,
	}

	_suite.assert_true(player.reset_runtime_state(), "%s first reset succeeds" % label)
	await _host.get_tree().process_frame
	var first_clean := _clean_reset_summary(player)
	_assert_clean_reset(player, label)
	_suite.assert_true(player.reset_runtime_state(), "%s second reset succeeds" % label)
	await _host.get_tree().process_frame
	var second_clean := _clean_reset_summary(player)
	_assert_clean_reset(player, "%s second reset" % label)
	_suite.assert_equal(second_clean, first_clean, "%s consecutive reset projections are idempotent" % label)

	var result := {
		"pre_reset": pre_reset,
		"pre_reset_digest": _value_digest(pre_reset),
		"post_reset": first_clean,
		"post_reset_digest": _value_digest(first_clean),
	}
	await _free_player(player)
	return result


func _commit_mastery(
	player: Node,
	weapon_id: StringName,
	time_pair: Array,
	seed_value: int
) -> Dictionary:
	var replay: Dictionary = player.full_player_replay_snapshot()
	var generation := int(player.character_action_coordinator.call("generation"))
	var action_token := 1000 + seed_value % 1000
	var context := {
		"runtime_frame": int(replay.get("frame", 1)),
		"run_id": player.current_run_id(),
		"run_revision": player.owner_character_generation(),
		"owner_character_generation": player.owner_character_generation(),
		"maximum_hp": float(player.get_node("HealthComponent").get("max_hp")),
		"attack": float(player.stats.attack),
		"position": player.global_position,
		"equipped_time_abilities": time_pair.duplicate(true),
		"approved_echo": true,
		"defensive_mastery": true,
		"hostile_source_id": &"matrix_hostile",
		"attack_generation": action_token,
	}
	var result: Dictionary = player.character_action_coordinator.call(
		"on_weapon_mastery_confirmed",
		{
			"weapon_id": weapon_id,
			"mastery_family": weapon_id,
			"mastery_id": MASTERY_IDS[weapon_id],
			"action_id": &"matrix_mastery",
			"generation": generation,
			"action_token": action_token,
			"target_id": action_token,
			"context": context,
		}
	)
	var ok := bool(result.get("ok", false))
	if ok:
		ok = player.apply_character_runtime_events(result.get("events", []) as Array)
	return {
		"ok": ok,
		"weapon_id": str(weapon_id),
		"mastery_family": str(weapon_id),
		"mastery_id": str(MASTERY_IDS[weapon_id]),
		"action_token": action_token,
		"generation": generation,
		"character": player.character_presentation_snapshot(),
	}


func _commit_character_skill(
	player: Node,
	character_id: StringName,
	label: String
) -> bool:
	var manager: Node = player.get_node("TimeManager")
	manager.set("energy", manager.get("max_energy"))
	if character_id == &"time_guardian":
		if not player.advance_action_frame(_character_intent(&"pressed", 0, &"hold")):
			return false
		if _accepted_action_id(player) != &"character_skill":
			return false
		for _frame: int in range(8):
			if not player.advance_action_frame({}):
				return false
		if not player.advance_action_frame(_character_intent(&"released", 8, &"hold")):
			return false
		return _accepted_action_id(player) == &"character_skill"
	if character_id == &"time_lord":
		# A hold-style skill must own the press before the release can commit the
		# tap/hold decision. Current production input fails closed here until the
		# Task 5/6 semantic hold route is installed.
		if not player.advance_action_frame(_character_intent(&"pressed", 0, &"hold")):
			return false
		for held_frames: int in range(1, 13):
			if not player.advance_action_frame(
				_character_intent(&"held", held_frames, &"hold")
			):
				return false
		if not player.advance_action_frame(_character_intent(&"released", 12, &"hold")):
			return false
		return _accepted_action_id(player) == &"character_skill"
	if not player.advance_action_frame(_character_intent(&"pressed", 0, &"press")):
		return false
	var accepted := _accepted_action_id(player) == &"character_skill"
	if not accepted:
		return false
	for _frame: int in range(MAX_ACTION_FRAMES):
		var action := player.character_runtime_snapshot().get("action", {}) as Dictionary
		if (action.get("committed_plan", {}) as Dictionary).is_empty():
			break
		if not player.advance_action_frame({}):
			_suite.assert_true(false, "%s character skill frame advances" % label)
			return false
	return true


func _commit_time_ability(player: Node, ability_id: StringName, label: String) -> Dictionary:
	var manager: Node = player.get_node("TimeManager")
	manager.set("energy", manager.get("max_energy"))
	if ability_id == &"rewind":
		player.rewind_recorder.clear_snapshots()
		player.rewind_recorder._record_snapshot()
	var action_id := StringName("time_%s" % str(ability_id))
	var advanced: bool = player.advance_action_frame(_time_intent(action_id))
	var accepted := advanced and _accepted_action_id(player) == action_id
	var start_time: Dictionary = manager.call("replay_snapshot")
	var start_world: Dictionary = player.get_node("WorldPayloadAuthority").call("replay_snapshot")
	if accepted:
		for _frame: int in range(MAX_ACTION_FRAMES):
			if player.action_state.current_state == PlayerActionStateScript.State.FREE:
				break
			if not player.advance_action_frame({}):
				accepted = false
				break
	_suite.assert_true(advanced, "%s %s fixed frame advances" % [label, str(ability_id)])
	return {
		"ok": accepted,
		"ability_id": str(ability_id),
		"action_id": str(action_id),
		"time_root": start_time,
		"world_root": start_world,
	}


func _project_view(
	player: Node,
	character_id: StringName,
	weapon_id: StringName,
	time_pair: Array,
	seed_value: int,
	step: int
) -> Dictionary:
	var player_snapshot: Dictionary = player.get_player_ui_snapshot()
	player_snapshot["character"] = player.character_presentation_snapshot()
	var projected = RunViewStateProjectorScript.new().project(
		_authoritative(character_id, weapon_id, time_pair, seed_value, step),
		{"room_number": 1, "type": "combat", "reward_kind": "starter"},
		player_snapshot,
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


func _clean_reset_summary(player: Node) -> Dictionary:
	var manager: Node = player.get_node("TimeManager")
	var world: Node = player.get_node("WorldPayloadAuthority")
	var time_root: Dictionary = manager.call("replay_snapshot")
	var world_root: Dictionary = world.call("replay_snapshot")
	return {
		"character": player.character_presentation_snapshot(),
		"weapon": player.weapon_presentation_snapshot(),
		"action_state": int(player.action_state.current_state),
		"time": {
			"stop_active": bool(time_root.get("stop_active", true)),
			"accelerate_active": bool(time_root.get("accelerate_active", true)),
			"rewind_window_remaining": float(time_root.get("rewind_window_remaining", -1.0)),
			"active_rifts": (time_root.get("active_rifts", []) as Array).duplicate(true),
		},
		"world_descriptor_count": (world_root.get("descriptors", []) as Array).size(),
	}


func _assert_clean_reset(player: Node, label: String) -> void:
	var manager: Node = player.get_node("TimeManager")
	var world: Node = player.get_node("WorldPayloadAuthority")
	var time_root: Dictionary = manager.call("replay_snapshot")
	var world_root: Dictionary = world.call("replay_snapshot")
	_suite.assert_equal(
		player.action_state.current_state,
		PlayerActionStateScript.State.FREE,
		"%s returns PlayerActionState to FREE" % label
	)
	_suite.assert_true(not bool(time_root.get("stop_active", true)), "%s clears Stop" % label)
	_suite.assert_true(not bool(time_root.get("accelerate_active", true)), "%s clears Accelerate" % label)
	_suite.assert_true(
		(time_root.get("active_rifts", []) as Array).is_empty(),
		"%s clears TimeManager Rift descriptors" % label
	)
	_suite.assert_true(
		(world_root.get("descriptors", []) as Array).is_empty(),
		"%s clears WorldPayload descriptors" % label
	)
	_suite.assert_true(
		_host.get_tree().get_nodes_in_group("time_rifts").is_empty(),
		"%s clears Time Rift nodes" % label
	)


func _config(
	character_id: StringName,
	weapon_id: StringName,
	time_pair: Array,
	seed_value: int
) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": str(character_id),
		"character_profile": _registry.call(
			"resolve_character_runtime_profile", character_id, &"LAUNCH"
		),
		"character_talents": [],
		"weapon_id": str(weapon_id),
		"weapon_profile": _registry.call(
			"resolve_weapon_runtime_profile", weapon_id, &"LAUNCH"
		),
		"enabled_time_skills": time_pair.duplicate(true),
		"difficulty": "normal",
		"seed": seed_value,
	}


func _authoritative(
	character_id: StringName,
	weapon_id: StringName,
	time_pair: Array,
	seed_value: int,
	step: int
) -> Dictionary:
	return {
		"schema_version": 1,
		"run_id": "p12g-%s-%s-%s-%s-%d" % [
			str(character_id),
			str(weapon_id),
			str(time_pair[0]),
			str(time_pair[1]),
			seed_value,
		],
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
		"config": {
			"milestone": "LAUNCH",
			"character_id": str(character_id),
			"weapon_id": str(weapon_id),
			"enabled_time_skills": time_pair.duplicate(true),
		},
	}


func _character_intent(edge: StringName, held_frames: int, mode: StringName) -> Dictionary:
	return {
		"character": [{
			"id": &"character_skill",
			"edge": edge,
			"held_frames": held_frames,
			"mode": mode,
		}],
	}


func _time_intent(action_id: StringName) -> Dictionary:
	return {
		"time": [{
			"id": action_id,
			"edge": &"pressed",
			"held_frames": 0,
			"mode": &"press",
		}],
	}


func _accepted_action_id(player: Node) -> StringName:
	var accepted := player.priority_arbitration_snapshot().get("accepted", {}) as Dictionary
	return StringName(str(accepted.get("id", "")))


func _bind_room(player: Node, revision: int) -> void:
	EventBus.room_started.emit(
		str(player.current_run_id()),
		StringName("p12-matrix-room-%d" % revision),
		revision
	)


func _case_label(character_id: StringName, weapon_id: StringName, time_pair: Array) -> String:
	return "%s × %s × %s+%s" % [
		str(character_id),
		str(weapon_id),
		str(time_pair[0]),
		str(time_pair[1]),
	]


func _value_digest(value: Dictionary) -> String:
	return JSON.stringify(value, "", true).sha256_text()


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_host.add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await _host.get_tree().process_frame
	return player


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame
