class_name RunRuntimeHost
extends Node

const ChoicePanelScene := preload("res://scenes/ui/choice_panel_v2.tscn")
const CombatHudScene := preload("res://scenes/ui/combat_hud_v2.tscn")
const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunRuntimeFacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const RunViewStateProjectorScript := preload("res://scripts/application/run_view_state_projector.gd")
const HostileThreatRegistryScript := preload("res://scripts/combat/hostile_threat_registry.gd")
const PlayerRewardEffectRuntimeScript := preload("res://scripts/items/player_reward_effect_runtime.gd")
const ProfileServiceScript := preload("res://scripts/progression/profile_runtime_service.gd")
const RunLoadoutPolicyScript := preload("res://scripts/application/run_loadout_policy.gd")

const HUD_RENDER_INTERVAL := 0.1
const BOSS_EXPOSURE_REPLAY_CHECKPOINT_SCHEMA_VERSION := 1
const BOSS_EXPOSURE_REPLAY_CHECKPOINT_FIELDS := [
	"schema_version",
	"run_id",
	"runtime_frame",
	"boss_exposure_state",
]

@export var room_controller_path: NodePath
@export_file("*.json") var manifest_path: String = "res://data/content_packs/base/pack.json"

var _active: bool = false
var _facade: RefCounted
var _room_runtime: Node
var _room_controller: Node
var _player: Node
var _projector: RefCounted
var _hostile_threat_registry: RefCounted = HostileThreatRegistryScript.new()
var _boss_exposure_replay_authority: RefCounted = RefCounted.new()
var _hud_layer: CanvasLayer
var _choice_layer: CanvasLayer
var _choice_panel: Control
var _active_run_id: String = ""
var _published_run_id: String = ""
var _initializing_run_id: String = ""
var _pending_initial_room_started: Dictionary = {}
var _pending_initial_room_cleared: Dictionary = {}
var _pending_initial_runtime_failure: Dictionary = {}
var _route_entry_publication_active: bool = false
var _pending_route_runtime_failure: Dictionary = {}
var _ended_run_id: String = ""
var _run_serial: int = 0
var _hud_render_accumulator: float = 0.0
var _selection_safety_active: bool = false
var _dungeon_selection_active: bool = false
var _player_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT
var _room_controller_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT
var _reward_effect_runtime: RefCounted = PlayerRewardEffectRuntimeScript.new()
var _route_scene_adapter: Variant = null
var _floor_rule_effect_authority: Variant = null
var _floor_rule_frame_origin: int = -1
var _published_route_transition_ids: Dictionary = {}
var _published_floor_start_ids: Dictionary = {}
var _published_floor_completion_ids: Dictionary = {}
var _profile_service: RefCounted
var _profile_bootstrap_service: RefCounted
var _profile_start_pending := false
var _profile_publication_pending := false
var _floor_entry_recovery_pending := false
var _presentation_enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_room_controller = get_node_or_null(room_controller_path)
	if _room_controller == null:
		return
	if (
		not _room_controller.has_method("configure_character_boss_exposure_replay_authority")
		or not bool(_room_controller.call(
			"configure_character_boss_exposure_replay_authority",
			_boss_exposure_replay_authority
		))
	):
		return
	_player = _room_controller.get_node_or_null("Player")
	if _player == null:
		return
	_facade = _boot_facade()
	if _facade == null:
		return
	_create_hud_layer()
	_create_choice_layer()
	_active = true


func _process(delta: float) -> void:
	if not _active or _facade == null or _active_run_id.is_empty():
		return
	if not _selection_safety_active:
		_facade.call("advance_time", maxf(0.0, delta))
		_advance_floor_rule_from_host()
	_hud_render_accumulator += maxf(0.0, delta)
	if _hud_render_accumulator < HUD_RENDER_INTERVAL:
		return
	_hud_render_accumulator = fmod(_hud_render_accumulator, HUD_RENDER_INTERVAL)
	_render_live_hud()


func start_profile_run(config: Dictionary, service: RefCounted, expected_revision: int) -> Variant:
	if not _active or not service is ProfileServiceScript or not service.has_method("retain_active_run") or str(config.get("milestone", "")) not in ["LAUNCH", "EXPANSION"]:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"operation": "start_profile_run"})
	if not _active_run_id.is_empty() and not RunPhaseScript.is_terminal(int(runtime_snapshot().get("phase", -1))):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "start_profile_run"})
	var normalized := RunConfigScript.normalized(config)
	var validated = RunConfigScript.validate(normalized)
	if not validated.ok:
		return validated
	var loadout = RunLoadoutPolicyScript.new().validate(normalized, _facade.content_registry())
	if not loadout.ok:
		return loadout
	var prepared: Dictionary = service.call("prepare_launch", {"seed": normalized.seed, "difficulty": normalized.difficulty, "character_id": normalized.character_id, "weapon_id": normalized.weapon_id, "time_abilities": normalized.enabled_time_skills}, expected_revision, normalized)
	if not prepared.ok:
		return CommandResultScript.failure(prepared.code, _revision(), prepared.context)
	_profile_bootstrap_service = service
	var started = start_run(normalized, {"launch": prepared.context.launch, "projection": prepared.context.projection})
	_profile_bootstrap_service = null
	return started


func retry_profile_startup(service: RefCounted, expected_revision: int) -> Variant:
	if not _active or not service is ProfileServiceScript or int(service.snapshot().get("revision", -1)) != expected_revision:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"operation": "retry_profile_startup"})
	if _profile_publication_pending:
		return CommandResultScript.failure(&"NATIVE_PUBLICATION_PENDING", _revision(), {"operation": "retry_profile_startup", "published": true})
	var receipt: Dictionary = service.snapshot().active_launch_receipt
	var projection: Dictionary = service.frozen_launch_projection()
	var config: Dictionary = service.pending_launch_config()
	if receipt.is_empty() or projection.is_empty() or config.is_empty():
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "retry_profile_startup"})
	if _profile_start_pending and _profile_service == service and _active_run_id == str(receipt.run_id) and not RunPhaseScript.is_terminal(int(runtime_snapshot().get("phase", -1))):
		return _finish_profile_startup()
	if not _active_run_id.is_empty() and not RunPhaseScript.is_terminal(int(runtime_snapshot().get("phase", -1))):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "retry_profile_startup"})
	if not service.payload().get("active_run_state", {}).is_empty():
		return CommandResultScript.failure(&"NATIVE_RESTORE_REQUIRED", _revision(), {"operation": "retry_profile_startup"})
	_profile_bootstrap_service = service
	var started = start_run(config, {"launch": receipt, "projection": projection})
	_profile_bootstrap_service = null
	return started


func _finish_profile_startup() -> Variant:
	_set_selection_safety(true)
	var retained = retain_profile_run(int(_profile_service.snapshot().revision))
	if not retained.ok:
		return CommandResultScript.failure(retained.code, _revision(), {"startup_pending": true, "recovery": "retry_profile_startup", "cause": retained.context})
	_profile_start_pending = false
	_set_selection_safety(false)
	var start_snapshot := runtime_snapshot()
	var source_service := _profile_service
	var source_player := _player
	var generation := int(source_player.owner_character_generation())
	var physical: Dictionary = source_player.reward_effect_snapshot()
	_published_run_id = _active_run_id
	_initializing_run_id = ""
	EventBus.run_started.emit(_active_run_id, start_snapshot.duplicate(true))
	if not is_inside_tree() or _profile_service != source_service or _player != source_player or not is_instance_valid(source_player) or not source_player.is_inside_tree() or str(source_player.current_run_id()) != str(start_snapshot.run_id) or int(source_player.owner_character_generation()) != generation or source_player.reward_effect_snapshot() != physical or runtime_snapshot() != start_snapshot or source_service.snapshot().active_launch_receipt.get("run_id") != start_snapshot.run_id:
		_profile_publication_pending = true
		_set_selection_safety(true)
		return CommandResultScript.failure(&"NATIVE_PUBLICATION_PENDING", _revision(), {"published": true, "run_id": start_snapshot.run_id})
	_publish_floor_started_once(start_snapshot)
	return CommandResultScript.success(_revision(), {"profile_revision": int(_profile_service.snapshot().revision)})


func retain_profile_run(expected_revision: int) -> Variant:
	if _profile_service == null or _facade == null or _player == null or not _facade.configure_merchant_effect_authority(_reward_effect_runtime, _player):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "retain_profile_run"})
	var retained: Dictionary = _profile_service.call("retain_active_run", _facade.native_run_state(), _player, expected_revision)
	return CommandResultScript.success(_revision(), retained.context) if retained.ok else CommandResultScript.failure(retained.code, _revision(), {"runtime_started": true, "cause": retained.context})


func native_run_state() -> RefCounted:
	return _facade.native_run_state() if _facade != null else null


func content_registry() -> RefCounted:
	return _facade.content_registry() if _facade != null else null


func set_run_presentation_visible(value: bool) -> bool:
	if not value and not _active_run_id.is_empty() and not RunPhaseScript.is_terminal(int(runtime_snapshot().get("phase", -1))):
		return false
	_presentation_enabled = value
	if _hud_layer != null:
		_hud_layer.visible = value
	return true


func start_run(config: Dictionary, profile_launch: Dictionary = {}) -> Variant:
	if not _active or _room_controller == null:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "start_run"})
	var normalized := RunConfigScript.normalized(config)
	var validation = RunConfigScript.validate(normalized)
	if not validation.ok:
		return validation
	if not profile_launch.is_empty() and not _profile_launch_matches(normalized, profile_launch):
		return CommandResultScript.failure(&"INVALID_ARGUMENT", _revision(), {"field": "profile_launch"})
	if profile_launch.is_empty() and _profile_service != null and not _profile_service.snapshot().get("active_launch_receipt", {}).is_empty():
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "start_run", "cause": "LAUNCH_ACTIVE"})
	var next_facade := _facade if _active_run_id.is_empty() else _boot_facade()
	if next_facade == null:
		return CommandResultScript.failure(&"CONTENT_NOT_AVAILABLE", _revision())
	_run_serial += 1
	var run_id := str(profile_launch.get("launch", {}).get("run_id", "")) if not profile_launch.is_empty() else "run-%d-%d" % [int(normalized.get("seed", 0)), _run_serial]
	var projection: Dictionary = profile_launch.get("projection", {})
	var started = next_facade.start_run(normalized, run_id, projection)
	if not started.ok:
		return started

	_dispose_room_runtime()
	_facade = next_facade
	_profile_service = _profile_bootstrap_service if not profile_launch.is_empty() else null
	_profile_start_pending = not profile_launch.is_empty()
	_profile_publication_pending = false
	_floor_entry_recovery_pending = false
	_active_run_id = run_id
	_published_run_id = ""
	_initializing_run_id = run_id
	_pending_initial_room_started.clear()
	_pending_initial_room_cleared.clear()
	_pending_initial_runtime_failure.clear()
	_discard_route_entry_publications()
	_published_route_transition_ids.clear()
	_published_floor_start_ids.clear()
	_published_floor_completion_ids.clear()
	_floor_rule_frame_origin = -1
	_ended_run_id = ""
	_hud_render_accumulator = 0.0
	if not _reset_floor_rule_runtime_for_new_run():
		return _fail_start(
			&"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
			{"floor_rule_runtime_reset": false}
		)
	_dungeon_selection_active = false
	_set_selection_safety(false)
	if _choice_panel != null:
		_choice_panel.close_panel()

	_resolve_player_for_start()
	var accepted_snapshot := runtime_snapshot()
	var config_value: Variant = accepted_snapshot.get("config", {})
	var accepted_loadout_value: Variant = (
		next_facade.call("active_loadout")
		if next_facade.has_method("active_loadout")
		else null
	)
	if (
		_player == null
		or not is_instance_valid(_player)
		or not _player.has_method("configure_run")
		or not _player.has_method("configure_loadout")
		or not config_value is Dictionary
		or not accepted_loadout_value is Dictionary
	):
		return _fail_start(&"LOADOUT_APPLY_FAILED", {"configured": false})
	if not bool(_player.call("configure_run", StringName(run_id))):
		return _fail_start(
			&"LOADOUT_APPLY_FAILED",
			{"configured": false, "reason": "run_identity_rejected"}
		)
	var accepted_config := (config_value as Dictionary).duplicate(true)
	var accepted_loadout := accepted_loadout_value as Dictionary
	var character_profile_value: Variant = accepted_loadout.get("character_profile", {})
	var weapon_profile_value: Variant = accepted_loadout.get("weapon_profile", {})
	if not character_profile_value is Dictionary or (character_profile_value as Dictionary).is_empty():
		return _fail_start(
			&"LOADOUT_APPLY_FAILED",
			{"configured": false, "reason": "character_profile_missing"}
		)
	if not weapon_profile_value is Dictionary or (weapon_profile_value as Dictionary).is_empty():
		return _fail_start(
			&"LOADOUT_APPLY_FAILED",
			{"configured": false, "reason": "weapon_profile_missing"}
		)
	accepted_config["character_profile"] = (
		character_profile_value as Dictionary
	).duplicate(true)
	var talent_definitions: Array = (
		(accepted_loadout.get("character_talents", []) as Array).duplicate(true)
		if accepted_loadout.get("character_talents", []) is Array
		else []
	)
	var talent_ids: Array[String] = []
	for talent_value: Variant in talent_definitions:
		if not talent_value is Dictionary:
			return _fail_start(
				&"LOADOUT_APPLY_FAILED",
				{"configured": false, "reason": "talent_definition_invalid"}
			)
		talent_ids.append(str((talent_value as Dictionary).get("id", "")))
	accepted_config["character_talents"] = talent_ids
	accepted_config["character_talent_definitions"] = talent_definitions
	accepted_config["weapon_profile"] = (weapon_profile_value as Dictionary).duplicate(true)
	if not projection.is_empty():
		accepted_config["meta_run_projection"] = projection.duplicate(true)
	if not bool(_player.call("configure_loadout", accepted_config)):
		return _fail_start(&"LOADOUT_APPLY_FAILED", {"configured": false})
	if (
		_is_floor_plan_snapshot(accepted_snapshot)
		and (
			not _facade.has_method("configure_merchant_effect_authority")
			or not bool(_facade.call(
				"configure_merchant_effect_authority", _reward_effect_runtime, _player
			))
		)
	):
		return _fail_start(
			&"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
			{"merchant_effect_authority": false}
		)
	var runner_value: Variant = _room_controller.call("encounter_runner")
	if not runner_value is Node:
		return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"has_runner": false})
	var runtime_value: Variant = _facade.call("create_room_runtime", runner_value)
	if not runtime_value is Node:
		return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"has_runtime": false})
	_room_runtime = runtime_value as Node
	_room_runtime.name = "RoomRuntime"
	add_child(_room_runtime)
	if _room_controller.has_method("configure_hostile_threat_authority"):
		var authority_configured := bool(_room_controller.call(
			"configure_hostile_threat_authority",
			hostile_identity_scope(StringName(run_id)),
			_hostile_threat_registry
		))
		if not authority_configured:
			return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"threat_authority": false})
	var configured := bool(_room_controller.call(
		"configure_authored_runtime",
		_room_runtime,
		_facade.call("encounter_catalog")
	))
	if not configured:
		return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"configured": false})
	_connect_room_runtime()
	if _is_floor_plan_snapshot(accepted_snapshot):
		if not _settle_floor_entrance():
			return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"meta_floor_entrance": false})
		if _profile_start_pending:
			return _finish_profile_startup()
		var start_snapshot := runtime_snapshot()
		_published_run_id = run_id
		_initializing_run_id = ""
		EventBus.run_started.emit(run_id, start_snapshot.duplicate(true))
		_publish_floor_started_once(start_snapshot)
		return CommandResultScript.success(_revision(), started.context)
	var entered: Variant = _room_runtime.call("begin_current_room")
	if entered == null or not bool(entered.get("ok")):
		if entered != null and entered.get("code") is StringName:
			return _fail_start(
				entered.get("code") as StringName,
				(entered.get("context") as Dictionary).duplicate(true)
			)
		return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"entered": false})
	if not _pending_initial_runtime_failure.is_empty():
		return _fail_start(
			&"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
			{"runtime_failure": _pending_initial_runtime_failure.duplicate(true)}
		)
	if _pending_initial_room_started.is_empty():
		return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"room_started": false})
	if (
		not _pending_initial_room_cleared.is_empty()
		and str(_pending_initial_room_cleared.get("room_id", ""))
		!= str(_pending_initial_room_started.get("room_id", ""))
	):
		return _fail_start(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"room_event_mismatch": true})

	var start_snapshot := runtime_snapshot()
	_published_run_id = run_id
	_initializing_run_id = ""
	EventBus.run_started.emit(run_id, start_snapshot.duplicate(true))
	_publish_pending_initial_room_started(run_id)
	_publish_pending_initial_room_cleared(run_id)
	return entered


func _profile_launch_matches(config: Dictionary, context: Dictionary) -> bool:
	if _profile_bootstrap_service == null or context.size() != 2 or not context.get("launch") is Dictionary or not context.get("projection") is Dictionary:
		return false
	var launch: Dictionary = context.launch
	var profile: Dictionary = _profile_bootstrap_service.snapshot()
	return (
		str(config.milestone) in ["LAUNCH", "EXPANSION"]
		and not launch.is_empty()
		and profile.get("active_launch_receipt") == launch
		and _profile_bootstrap_service.frozen_launch_projection() == context.projection
		and _profile_bootstrap_service.pending_launch_config() == config
		and launch.get("seed") == config.seed
		and launch.get("difficulty") == config.difficulty
		and launch.get("character_id") == config.character_id
		and launch.get("weapon_id") == config.weapon_id
		and launch.get("time_abilities") == config.enabled_time_skills
		and launch.get("projection_digest") == context.projection.get("projection_digest")
	)


func pause_run() -> Variant:
	if _facade == null:
		return CommandResultScript.failure(&"INVALID_PHASE", 0)
	return _facade.call("pause_run")


func resume_run() -> Variant:
	if _facade == null:
		return CommandResultScript.failure(&"INVALID_PHASE", 0)
	return _facade.call("resume_run")


func runtime_snapshot() -> Dictionary:
	if _facade == null:
		return {}
	return (_facade.call("snapshot") as Dictionary).duplicate(true)


func dungeon_ui_context() -> Dictionary:
	var state := runtime_snapshot()
	if _facade == null or not _is_floor_plan_snapshot(state):
		return {}
	var registry: RefCounted = _facade.call("content_registry")
	if registry == null:
		return {}
	var context := {
		"state": state,
		"room": _facade.call("current_room_definition"),
		"floors": registry.call("get_floor_definitions", &"LAUNCH"),
		"content": registry.call("all_content"),
		"routes": route_choices(),
		"merchant": _facade.call("merchant_view_state"),
		"event": _facade.call("event_view_state"),
		"merchant_services": [],
		"event_reward": {},
		"interaction": {},
	}
	if _facade.has_method("merchant_service_choices"):
		context["merchant_services"] = _facade.call("merchant_service_choices")
	if _facade.has_method("event_reward_offer"):
		context["event_reward"] = _facade.call("event_reward_offer")
	if _facade.has_method("room_interaction_view_state"):
		context["interaction"] = _facade.call("room_interaction_view_state")
	return context


func set_dungeon_selection_safety(active_selection: bool) -> void:
	_dungeon_selection_active = active_selection
	_set_selection_safety(active_selection or (_choice_panel != null and _choice_panel.visible))


func choose_event_option(option_id: StringName, expected_revision: int) -> Variant:
	if _room_runtime == null or not is_instance_valid(_room_runtime):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	return _room_runtime.call("choose_current_event_option", option_id, expected_revision)


func submit_event_reward(option_id: StringName, expected_revision: int) -> Variant:
	if _facade == null or not _facade.has_method("submit_current_event_reward"):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	var result: Variant = _facade.call("submit_current_event_reward", option_id, expected_revision)
	if result != null and bool(result.get("ok")):
		if _room_runtime == null or not bool(_room_runtime.call("sync_event_result", result)):
			return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"stage": "event_reward_sync"})
	return result


func dismiss_event(expected_revision: int) -> Variant:
	if _room_runtime == null or not is_instance_valid(_room_runtime):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	var dismissed: Variant = _room_runtime.call("dismiss_current_event", expected_revision)
	if dismissed == null or not bool(dismissed.get("ok")):
		return dismissed
	return _room_runtime.call("complete_current_room")


func resolve_room_interaction(choice_id: StringName, expected_revision: int) -> Variant:
	if (
		_facade == null
		or _room_runtime == null
		or not _facade.has_method("resolve_current_room_interaction")
	):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	var resolved: Variant = _facade.call("resolve_current_room_interaction", choice_id, expected_revision)
	if resolved == null or not bool(resolved.get("ok")):
		return resolved
	var published: Variant = _room_runtime.call("synchronize_completed_interaction")
	if published == null or not bool(published.get("ok")):
		return CommandResultScript.failure(&"INTEGRITY_FAILURE", _revision(), {"stage": "room_interaction_sync"})
	return resolved


func leave_merchant(expected_revision: int) -> Variant:
	var validation = _validate_dungeon_revision(expected_revision)
	if not validation.ok:
		return validation
	if _room_runtime == null:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	return _room_runtime.call("leave_current_shop")


func merchant_action(action_id: StringName, target_id: StringName, expected_revision: int) -> Variant:
	var validation = _validate_dungeon_revision(expected_revision)
	if not validation.ok:
		return validation
	var state := runtime_snapshot()
	var plan := state.get("floor_plan", {}) as Dictionary
	var transaction_id := "ui_%s" % (
		"%s:%s:%s:%s:%s:%d" % [
			str(state.get("run_id", "")), str(plan.get("floor_id", "")),
			str(plan.get("current_node_id", "")), str(action_id), str(target_id), expected_revision,
		]
	).sha256_text().substr(0, 48)
	match action_id:
		&"purchase_reward":
			return _facade.call("purchase_current_merchant", transaction_id, str(target_id))
		&"reroll":
			return _facade.call("reroll_current_merchant", transaction_id)
		_:
			return _facade.call("execute_current_merchant_service", transaction_id, action_id, str(target_id))


func _validate_dungeon_revision(expected_revision: int):
	if _facade == null or not _is_floor_plan_snapshot(runtime_snapshot()):
		return CommandResultScript.failure(&"INVALID_PHASE", _revision())
	if expected_revision != _revision():
		return CommandResultScript.failure(&"STALE_REVISION", _revision())
	return CommandResultScript.success(_revision())


func configure_route_scene_adapter(adapter: Variant) -> bool:
	if typeof(adapter) == TYPE_CALLABLE:
		_route_scene_adapter = adapter
		return true
	if adapter is Object and (
		(adapter as Object).has_method("prepare_route_transition")
		or (adapter as Object).has_method("prepare_transition")
	):
		_route_scene_adapter = adapter
		return true
	return false


func configure_floor_rule_effect_authority(authority: Variant) -> bool:
	if authority is Callable and (authority as Callable).is_valid():
		_floor_rule_effect_authority = authority
		return true
	if authority is Object and (
		(authority as Object).has_method("commit_floor_rule_effects")
		or (authority as Object).has_method("commit_floor_rule_effect")
	):
		_floor_rule_effect_authority = authority
		return true
	return false


func commit_floor_rule_effects(facts: Array) -> bool:
	if _floor_rule_effect_authority is Callable:
		return bool((_floor_rule_effect_authority as Callable).call(facts.duplicate(true)))
	if _floor_rule_effect_authority is Object:
		var authority := _floor_rule_effect_authority as Object
		if authority.has_method("commit_floor_rule_effects"):
			return bool(authority.call("commit_floor_rule_effects", facts.duplicate(true)))
		if facts.size() == 1 and authority.has_method("commit_floor_rule_effect"):
			return bool(authority.call("commit_floor_rule_effect", facts[0].duplicate(true)))
	return false


func route_choices() -> Array[Dictionary]:
	if _facade == null or not _facade.has_method("route_choices"):
		return []
	return (_facade.call("route_choices") as Array).duplicate(true)


func select_route(edge_id: StringName, expected_revision: int = -1) -> Variant:
	if (
		_facade == null
		or _floor_entry_recovery_pending
		or _profile_start_pending
		or _profile_publication_pending
		or _active_run_id.is_empty()
		or _active_run_id != _published_run_id
		or not _facade.has_method("begin_route_transition")
	):
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": "select_route"}
		)
	if (
		_route_scene_adapter is Object
		and (_route_scene_adapter as Object).has_method("prepare_transition")
		and not _floor_rule_effect_authority_is_valid()
	):
		return CommandResultScript.failure(
			&"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
			_revision(),
			{"operation": "select_route", "authority": "floor_rule_effects"}
		)
	if expected_revision < 0:
		expected_revision = _revision()
	var begun: Variant = _facade.call(
		"begin_route_transition", edge_id, expected_revision
	)
	if begun == null or not bool(begun.get("ok")):
		return begun
	var begun_context: Dictionary = (begun.context as Dictionary).duplicate(true)
	var transition_id := str(begun_context.get("transition_id", ""))
	var target: Dictionary = (
		begun_context.get("target", {}) as Dictionary
	).duplicate(true)
	var adapter_context := {
		"run_id": _active_run_id,
		"transition_id": transition_id,
		"edge_id": str(edge_id),
		"target": target.duplicate(true),
		"revision": int(begun.new_revision),
		"scene_context": (begun_context.get("scene_context", {}) as Dictionary).duplicate(true),
	}
	var prepared_scene := _prepare_route_scene(target, adapter_context)
	if not bool(prepared_scene.get("ok", false)):
		var rolled_back: Variant = _facade.call(
			"rollback_route_transition", transition_id, int(begun.new_revision)
		)
		if rolled_back == null or not bool(rolled_back.get("ok")):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_revision(),
				{"stage": "route_scene_adapter_rollback", "transition_id": transition_id}
			)
		return CommandResultScript.failure(
			&"COMMIT_FAILED",
			_revision(),
			{"stage": "route_scene_adapter", "transition_id": transition_id}
		)
	var finalized: Variant = _facade.call(
		"finalize_route_transition", transition_id, int(begun.new_revision)
	)
	if finalized == null:
		_rollback_route_scene(prepared_scene, adapter_context)
		return finalized
	if not bool(finalized.get("ok")):
		var scene_rolled_back := _rollback_route_scene(prepared_scene, adapter_context)
		if not bool(scene_rolled_back.get("ok", false)):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_revision(),
				{"stage": "route_scene_prepare_rollback", "transition_id": transition_id}
			)
		var finalized_context: Dictionary = (
			finalized.context as Dictionary
		).duplicate(true)
		if not bool(finalized_context.get("route_rolled_back", false)):
			var rolled_back: Variant = _facade.call(
				"rollback_route_transition",
				transition_id,
				int(finalized.new_revision)
			)
			if rolled_back == null or not bool(rolled_back.get("ok")):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE",
					_revision(),
					{"stage": "route_finalize_rollback", "transition_id": transition_id}
				)
		return CommandResultScript.failure(
			finalized.code,
			_revision(),
			finalized_context,
			finalized.message_key
		)
	adapter_context["revision"] = int(finalized.new_revision)
	var scene_committed := _commit_route_scene(
		prepared_scene, target, adapter_context
	)
	var route_revision := int(finalized.new_revision)
	if not bool(scene_committed.get("ok", false)):
		var scene_rollback := _rollback_route_scene(prepared_scene, adapter_context)
		if not bool(scene_rollback.get("ok", false)):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE", _revision(),
				{"stage": "route_scene_commit_rollback", "transition_id": transition_id}
			)
		var authority_rollback: Variant = _facade.call(
			"rollback_route_transition", transition_id, int(finalized.new_revision)
		)
		if authority_rollback == null or not bool(authority_rollback.get("ok")):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE", _revision(),
				{"stage": "route_scene_commit_authority_rollback", "transition_id": transition_id}
			)
		return CommandResultScript.failure(
			&"COMMIT_FAILED", _revision(),
			{"stage": "route_scene_commit", "transition_id": transition_id}
		)
	var floor_rule_configuration := _floor_rule_configuration_for_scene(prepared_scene)
	if str(prepared_scene.get("adapter_kind", "")) == "room_scene_host":
		if floor_rule_configuration.is_empty():
			var missing_rule_scene_rollback := _rollback_route_scene(prepared_scene, adapter_context)
			if not bool(missing_rule_scene_rollback.get("ok", false)):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE", _revision(),
					{"stage": "floor_rule_configuration_scene_rollback", "transition_id": transition_id}
				)
			var missing_rule_authority_rollback: Variant = _facade.call(
				"rollback_route_transition", transition_id, route_revision
			)
			if missing_rule_authority_rollback == null or not bool(missing_rule_authority_rollback.get("ok")):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE", _revision(),
					{"stage": "floor_rule_configuration_authority_rollback", "transition_id": transition_id}
				)
			return CommandResultScript.failure(
				&"COMMIT_FAILED", _revision(),
				{"stage": "floor_rule_configuration", "transition_id": transition_id}
			)
		var rule_id := StringName(str(
			(adapter_context.get("scene_context", {}) as Dictionary).get(
				"environment_rule_id", ""
			)
		))
		var configured_rule: Variant = _facade.call(
			"configure_floor_rule",
			rule_id,
			floor_rule_configuration,
			_floor_rule_effect_authority,
			route_revision
		)
		if configured_rule == null or not bool(configured_rule.get("ok")):
			var rule_scene_rollback := _rollback_route_scene(prepared_scene, adapter_context)
			if not bool(rule_scene_rollback.get("ok", false)):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE", _revision(),
					{"stage": "floor_rule_scene_rollback", "transition_id": transition_id}
				)
			var rule_authority_rollback: Variant = _facade.call(
				"rollback_route_transition", transition_id, _revision()
			)
			if rule_authority_rollback == null or not bool(rule_authority_rollback.get("ok")):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE", _revision(),
					{"stage": "floor_rule_authority_rollback", "transition_id": transition_id}
				)
			return CommandResultScript.failure(
				&"COMMIT_FAILED", _revision(),
				{"stage": "floor_rule_commit", "transition_id": transition_id}
			)
		route_revision = int(configured_rule.new_revision)
		adapter_context["revision"] = route_revision
		_floor_rule_frame_origin = _host_runtime_frame()
	var confirmable: Variant = _facade.call(
		"can_confirm_route_transition", transition_id, route_revision
	)
	if confirmable == null or not bool(confirmable.get("ok")):
		var confirm_preflight_scene_rollback := _rollback_route_scene(
			prepared_scene, adapter_context
		)
		if not bool(confirm_preflight_scene_rollback.get("ok", false)):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE", _revision(),
				{"stage": "route_confirm_preflight_scene_rollback", "transition_id": transition_id}
			)
		var confirm_preflight_authority_rollback: Variant = _facade.call(
			"rollback_route_transition", transition_id, _revision()
		)
		if confirm_preflight_authority_rollback == null or not bool(confirm_preflight_authority_rollback.get("ok")):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE", _revision(),
				{"stage": "route_confirm_preflight_authority_rollback", "transition_id": transition_id}
			)
		return confirmable
	_begin_route_entry_publication_buffer()
	if _room_runtime != null and is_instance_valid(_room_runtime):
		var entered: Variant = _room_runtime.call("begin_current_room")
		if (
			entered == null
			or not bool(entered.get("ok"))
			or not _pending_route_runtime_failure.is_empty()
		):
			var entry_code := (
				str(entered.get("code"))
				if entered != null
				else "INVALID_RESULT"
			)
			if not _compensate_route_after_room_entry(
				prepared_scene, adapter_context, transition_id
			):
				return CommandResultScript.failure(
					&"INTEGRITY_FAILURE",
					_revision(),
					{"stage": "route_room_runtime_entry_rollback", "transition_id": transition_id}
				)
			return CommandResultScript.failure(
				&"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
				_revision(),
				{
					"stage": "route_room_runtime_entry",
					"transition_id": transition_id,
					"code": entry_code,
					"entry_context": entered.context.duplicate(true) if entered != null else {},
				}
			)
	var final_revision := _revision()
	adapter_context["revision"] = final_revision
	var post_entry_confirmable: Variant = _facade.call(
		"can_confirm_route_transition", transition_id, final_revision
	)
	if post_entry_confirmable == null or not bool(post_entry_confirmable.get("ok")):
		if not _compensate_route_after_room_entry(
			prepared_scene, adapter_context, transition_id
		):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_revision(),
				{"stage": "route_room_runtime_preflight_rollback", "transition_id": transition_id}
			)
		if post_entry_confirmable == null:
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_revision(),
				{"stage": "route_room_runtime_preflight", "transition_id": transition_id}
			)
		return CommandResultScript.failure(
			post_entry_confirmable.code,
			_revision(),
			(post_entry_confirmable.context as Dictionary).duplicate(true),
			post_entry_confirmable.message_key
		)
	var scene_confirmed := _confirm_route_scene(prepared_scene, adapter_context)
	if not bool(scene_confirmed.get("ok", false)):
		if not _compensate_route_after_room_entry(
			prepared_scene, adapter_context, transition_id
		):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE", _revision(),
				{"stage": "route_scene_confirm_rollback", "transition_id": transition_id}
			)
		return CommandResultScript.failure(
			&"COMMIT_FAILED", _revision(),
			{"stage": "route_scene_confirm", "transition_id": transition_id}
		)
	var confirmed: Variant = _facade.call(
		"confirm_route_transition", transition_id, final_revision
	)
	if confirmed == null or not bool(confirmed.get("ok")):
		_discard_route_entry_publications()
		return CommandResultScript.failure(
			&"INTEGRITY_FAILURE", _revision(),
			{"stage": "route_authority_confirm_after_preflight", "transition_id": transition_id}
		)
	if _published_route_transition_ids.has(transition_id):
		_discard_route_entry_publications()
		return CommandResultScript.failure(
			&"ALREADY_CONSUMED",
			_revision(),
			{"transition_id": transition_id}
		)
	_published_route_transition_ids[transition_id] = true
	var context: Dictionary = (finalized.context as Dictionary).duplicate(true)
	var floor_id := StringName(str(context.get("floor_id", "")))
	var node_id := StringName(str(context.get("node_id", "")))
	var revision := final_revision
	EventBus.route_selected.emit(
		_active_run_id, floor_id, StringName(str(edge_id)), node_id, revision
	)
	var confirmed_event_facts := (
		(confirmed.context as Dictionary).get("event_facts", []) as Array
	).duplicate(true)
	if (
		not confirmed_event_facts.is_empty()
		and (
			not _facade.has_method("publish_confirmed_route_event_facts")
			or not bool(_facade.call(
				"publish_confirmed_route_event_facts", confirmed_event_facts
			))
		)
	):
		_discard_route_entry_publications()
		return CommandResultScript.failure(
			&"INTEGRITY_FAILURE",
			_revision(),
			{"stage": "route_event_fact_publication", "transition_id": transition_id}
		)
	if _room_runtime != null and is_instance_valid(_room_runtime):
		_discard_route_entry_publications()
		EventBus.room_started.emit(_active_run_id, node_id, final_revision)
	else:
		_discard_route_entry_publications()
		# Headless transaction harnesses may exercise route publication without
		# constructing the production RoomRuntime. Production start_run always
		# owns a runtime and publishes room_started through its signal callback.
		EventBus.room_started.emit(_active_run_id, node_id, revision)
	return CommandResultScript.success(final_revision, context)


func start_next_floor(expected_revision: int = -1) -> Variant:
	if _facade == null or not _facade.has_method("start_next_floor"):
		return CommandResultScript.failure(
			&"INVALID_PHASE", _revision(), {"operation": "start_next_floor"}
		)
	if expected_revision >= 0 and expected_revision != _revision():
		return CommandResultScript.failure(&"STALE_REVISION", _revision())
	if _floor_entry_recovery_pending or _profile_publication_pending or _profile_start_pending:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "start_next_floor"})
	var started: Variant = _facade.call("start_next_floor")
	if started != null and bool(started.get("ok")):
		if not _settle_floor_entrance():
			_floor_entry_recovery_pending = true
			_set_selection_safety(true)
			return CommandResultScript.failure(&"COMMIT_FAILED", _revision(), {"operation": "meta_floor_entrance", "recovery": "retry_floor_entrance"})
		_publish_floor_started_once(runtime_snapshot())
		return CommandResultScript.success(_revision(), started.context)
	return started


func retry_floor_entrance() -> Variant:
	if _profile_start_pending or _profile_publication_pending:
		return CommandResultScript.failure(&"INVALID_PHASE", _revision(), {"operation": "retry_floor_entrance"})
	if not _settle_floor_entrance():
		return CommandResultScript.failure(&"COMMIT_FAILED", _revision(), {"operation": "meta_floor_entrance"})
	if _floor_entry_recovery_pending:
		_floor_entry_recovery_pending = false
		_set_selection_safety(false)
	_publish_floor_started_once(runtime_snapshot())
	return CommandResultScript.success(_revision())


func _settle_floor_entrance() -> bool:
	if _facade == null:
		return false
	return bool(_facade.apply_meta_floor_entrance(_player).ok)


func room_plan() -> Array[Dictionary]:
	if _facade == null:
		return []
	return _facade.call("room_plan")


func encounter_catalog() -> RefCounted:
	if _facade == null:
		return null
	return _facade.call("encounter_catalog")


func hostile_threat_registry() -> RefCounted:
	return _hostile_threat_registry


func capture_boss_exposure_replay_checkpoint() -> Dictionary:
	if (
		_active_run_id.is_empty()
		or _room_controller == null
		or not is_instance_valid(_room_controller)
		or not _room_controller.has_method("capture_character_boss_exposure_replay_state")
		or not _room_controller.has_method("character_boss_exposure_runtime_frame")
	):
		return {}
	var state_value: Variant = _room_controller.call("capture_character_boss_exposure_replay_state")
	if not state_value is Dictionary or (state_value as Dictionary).is_empty():
		return {}
	var runtime_frame := int(_room_controller.call("character_boss_exposure_runtime_frame"))
	if runtime_frame < 0:
		return {}
	return {
		"schema_version": BOSS_EXPOSURE_REPLAY_CHECKPOINT_SCHEMA_VERSION,
		"run_id": _active_run_id,
		"runtime_frame": runtime_frame,
		"boss_exposure_state": (state_value as Dictionary).duplicate(true),
	}


func restore_boss_exposure_replay_checkpoint(value: Dictionary) -> bool:
	if (
		_active_run_id.is_empty()
		or _room_controller == null
		or not is_instance_valid(_room_controller)
		or not _dictionary_has_exact_fields(value, BOSS_EXPOSURE_REPLAY_CHECKPOINT_FIELDS)
		or typeof(value.get("schema_version")) != TYPE_INT
		or int(value["schema_version"]) != BOSS_EXPOSURE_REPLAY_CHECKPOINT_SCHEMA_VERSION
		or typeof(value.get("run_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(value["run_id"]) != _active_run_id
		or typeof(value.get("runtime_frame")) != TYPE_INT
		or int(value["runtime_frame"]) < 0
		or not value.get("boss_exposure_state") is Dictionary
		or not _room_controller.has_method("can_restore_character_boss_exposure_replay_state")
		or not _room_controller.has_method("restore_character_boss_exposure_replay_state")
	):
		return false
	var state := (value["boss_exposure_state"] as Dictionary).duplicate(true)
	if not bool(_room_controller.call(
		"can_restore_character_boss_exposure_replay_state",
		state,
		_boss_exposure_replay_authority
	)):
		return false
	return bool(_room_controller.call(
		"restore_character_boss_exposure_replay_state",
		state,
		_boss_exposure_replay_authority
	))


static func hostile_identity_scope(run_id: StringName) -> Dictionary:
	var normalized := str(run_id).strip_edges()
	if normalized.is_empty() or normalized.length() > 64:
		return {}
	return {"run_id": StringName(normalized)}


func _dictionary_has_exact_fields(value: Dictionary, expected_fields: Array) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field_value: Variant in expected_fields:
		if not value.has(str(field_value)):
			return false
	return true


func choice_panel() -> Control:
	return _choice_panel


func _boot_facade() -> RefCounted:
	var facade := RunRuntimeFacadeScript.new()
	var booted = facade.boot(manifest_path)
	return facade if booted.ok else null


func _create_hud_layer() -> void:
	var instance := CombatHudScene.instantiate()
	if not instance is CanvasLayer or not instance.has_method("render"):
		instance.free()
		return
	_projector = RunViewStateProjectorScript.new()
	_hud_layer = instance as CanvasLayer
	_hud_layer.name = "HudLayer"
	_hud_layer.layer = 10
	add_child(_hud_layer)


func _create_choice_layer() -> void:
	_choice_layer = CanvasLayer.new()
	_choice_layer.name = "ChoiceLayer"
	_choice_layer.layer = 20
	add_child(_choice_layer)
	_choice_panel = ChoicePanelScene.instantiate() as Control
	_choice_layer.add_child(_choice_panel)
	_choice_panel.option_chosen.connect(_on_option_chosen)


func _connect_room_runtime() -> void:
	if not _room_runtime.room_started.is_connected(_on_room_started):
		_room_runtime.room_started.connect(_on_room_started)
	if not _room_runtime.room_cleared.is_connected(_on_room_cleared):
		_room_runtime.room_cleared.connect(_on_room_cleared)
	if not _room_runtime.terminal_committed.is_connected(_on_terminal_committed):
		_room_runtime.terminal_committed.connect(_on_terminal_committed)
	if not _room_runtime.runtime_failed.is_connected(_on_runtime_failed):
		_room_runtime.runtime_failed.connect(_on_runtime_failed)


func _dispose_room_runtime() -> void:
	_retire_hostile_threats()
	if _room_runtime == null or not is_instance_valid(_room_runtime):
		_room_runtime = null
		return
	if _room_runtime.room_started.is_connected(_on_room_started):
		_room_runtime.room_started.disconnect(_on_room_started)
	if _room_runtime.room_cleared.is_connected(_on_room_cleared):
		_room_runtime.room_cleared.disconnect(_on_room_cleared)
	if _room_runtime.terminal_committed.is_connected(_on_terminal_committed):
		_room_runtime.terminal_committed.disconnect(_on_terminal_committed)
	if _room_runtime.runtime_failed.is_connected(_on_runtime_failed):
		_room_runtime.runtime_failed.disconnect(_on_runtime_failed)
	_room_runtime.queue_free()
	_room_runtime = null


func _on_room_started(active_room_id: StringName, revision: int) -> void:
	var state := runtime_snapshot()
	var run_id := str(state.get("run_id", ""))
	if run_id.is_empty() or run_id != _active_run_id:
		return
	if _route_entry_publication_active:
		return
	if run_id == _initializing_run_id:
		if _pending_initial_room_started.is_empty():
			_pending_initial_room_started = {
				"run_id": run_id,
				"room_id": active_room_id,
				"revision": revision,
			}
		return
	if run_id != _published_run_id:
		return
	EventBus.room_started.emit(run_id, active_room_id, revision)


func _on_room_cleared(active_room_id: StringName, revision: int) -> void:
	var state := runtime_snapshot()
	var run_id := str(state.get("run_id", ""))
	if run_id.is_empty() or run_id != _active_run_id:
		return
	if _route_entry_publication_active:
		return
	if run_id == _initializing_run_id:
		if _pending_initial_room_cleared.is_empty():
			_pending_initial_room_cleared = {
				"run_id": run_id,
				"room_id": active_room_id,
				"revision": revision,
			}
		return
	if run_id != _published_run_id:
		return
	_publish_room_cleared(run_id, active_room_id, revision)
	_publish_floor_completed_if_new(state, revision)


func _on_terminal_committed(context: Dictionary, _revision: int) -> void:
	if _route_entry_publication_active:
		return
	_retire_hostile_threats()
	_cancel_player_time_effects(&"run_terminal")
	_publish_terminal_result(context)


func _on_runtime_failed(context: Dictionary) -> void:
	if _route_entry_publication_active:
		if _pending_route_runtime_failure.is_empty():
			_pending_route_runtime_failure = context.duplicate(true)
		return
	var state := runtime_snapshot()
	var run_id := str(state.get("run_id", ""))
	if not run_id.is_empty() and run_id == _active_run_id and run_id == _initializing_run_id:
		if _pending_initial_runtime_failure.is_empty():
			_pending_initial_runtime_failure = context.duplicate(true)
		return
	if _choice_panel != null:
		_choice_panel.close_panel()
	_set_selection_safety(false)
	_retire_hostile_threats()
	_cancel_player_time_effects(&"runtime_failed")
	_publish_terminal_result(context)


func _begin_route_entry_publication_buffer() -> void:
	_discard_route_entry_publications()
	_route_entry_publication_active = true


func _discard_route_entry_publications() -> void:
	_route_entry_publication_active = false
	_pending_route_runtime_failure.clear()


func _open_offer(offer_value: Variant) -> void:
	if not offer_value is Dictionary or (offer_value as Dictionary).is_empty() or _choice_panel == null:
		return
	_set_selection_safety(true)
	var rendered = _choice_panel.render(_choice_offer_for_player(offer_value as Dictionary))
	if not rendered.ok:
		_set_selection_safety(false)


func _choice_offer_for_player(offer: Dictionary) -> Dictionary:
	var presented := offer.duplicate(true)
	if (
		_facade == null
		or _player == null
		or not _facade.has_method("content_registry")
		or not _player.has_method("active_item_snapshot")
	):
		return presented
	var registry_value: Variant = _facade.call("content_registry")
	if not registry_value is RefCounted or not (registry_value as RefCounted).has_method("get_content"):
		return presented
	var active_value: Variant = _player.call("active_item_snapshot")
	if not active_value is Dictionary:
		return presented
	var equipped_active := active_value as Dictionary
	var equipped_definition := equipped_active.get("definition", {}) as Dictionary
	var equipped_content_id := str(equipped_definition.get("id", ""))
	var equipped_name_key := equipped_content_id
	if not equipped_content_id.is_empty():
		var equipped_content_value: Variant = (registry_value as RefCounted).call(
			"get_content",
			StringName(equipped_content_id)
		)
		if equipped_content_value is Dictionary:
			equipped_name_key = str(
				(equipped_content_value as Dictionary).get("name_key", equipped_content_id)
			)
	var options := presented.get("options", []) as Array
	for index: int in range(options.size()):
		var option_value: Variant = options[index]
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		var definition_value: Variant = (registry_value as RefCounted).call(
			"get_content",
			StringName(str(option.get("content_id", "")))
		)
		if (
			not definition_value is Dictionary
			or str((definition_value as Dictionary).get("item_mode", "")) != "active"
		):
			continue
		var definition := definition_value as Dictionary
		option["active_item"] = {
			"cooldown_frames": int(definition.get("cooldown_frames", 0)),
			"replacement_required": bool(equipped_active.get("configured", false)),
			"equipped_content_id": equipped_content_id,
			"equipped_name_key": equipped_name_key,
		}
		if (option.get("effect_summary_keys", []) as Array).is_empty():
			option["effect_summary_keys"] = ["INPUT_ACTION_ACTIVE_ITEM"]
		options[index] = option
	presented["options"] = options
	return presented


func _on_option_chosen(offer_id: String, option_id: String, revision: int) -> void:
	if _is_floor_plan_snapshot(runtime_snapshot()):
		_submit_launch_reward(offer_id, option_id, revision)
		return
	if (
		_facade == null
		or _choice_panel == null
		or _player == null
		or _reward_effect_runtime == null
		or not _facade.has_method("reserve_selection")
		or not _facade.has_method("commit_reserved_selection")
		or not _facade.has_method("cancel_reserved_selection")
	):
		return
	var reserved = _facade.call("reserve_selection", offer_id, option_id, revision)
	if not reserved.ok:
		_choice_panel.show_rejection(_rejection_message_key(reserved))
		return
	var reservation_id := str(reserved.context.get("reservation_id", ""))
	var definition: Dictionary = reserved.context.get("definition", {}).duplicate(true)
	var is_active_item_selection := str(definition.get("item_mode", "")) == "active"
	var is_talent_selection := str(definition.get("category", "")) == "talent"
	var receipt: Dictionary = {}
	var active_item_before: Dictionary = {}
	var talent_before: Dictionary = {}
	var publication_started := false
	if str(definition.get("id", "")) != "decline_contract":
		if is_talent_selection:
			if (
				not _player.has_method("character_talent_transaction_snapshot")
				or not _player.has_method("restore_character_talent_transaction_snapshot")
				or not _player.has_method("install_character_talent")
			):
				_facade.call("cancel_reserved_selection", reservation_id)
				_choice_panel.show_rejection("CHOICE_REJECTED")
				return
			var talent_before_value: Variant = _player.call(
				"character_talent_transaction_snapshot"
			)
			if (
				not talent_before_value is Dictionary
				or (talent_before_value as Dictionary).is_empty()
			):
				_facade.call("cancel_reserved_selection", reservation_id)
				_choice_panel.show_rejection("CHOICE_REJECTED")
				return
			talent_before = (talent_before_value as Dictionary).duplicate(true)
			if not bool(_player.call(
				"install_character_talent",
				definition.duplicate(true)
			)):
				_facade.call("cancel_reserved_selection", reservation_id)
				_choice_panel.show_rejection("CHOICE_REJECTED")
				return
		elif is_active_item_selection:
			if (
				not _player.has_method("active_item_snapshot")
				or not _player.has_method("equip_active_item")
				or not _player.has_method("full_player_replay_snapshot")
				or not _player.has_method("restore_full_player_replay_snapshot")
			):
				_facade.call("cancel_reserved_selection", reservation_id)
				_choice_panel.show_rejection("CHOICE_REJECTED")
				return
			var active_item_before_value: Variant = _player.call(
				"full_player_replay_snapshot"
			)
			var current_active_value: Variant = _player.call("active_item_snapshot")
			if (
				not active_item_before_value is Dictionary
				or (active_item_before_value as Dictionary).is_empty()
				or not current_active_value is Dictionary
			):
				_facade.call("cancel_reserved_selection", reservation_id)
				_choice_panel.show_rejection("CHOICE_REJECTED")
				return
			active_item_before = (active_item_before_value as Dictionary).duplicate(true)
			var replace_existing := bool(
				(current_active_value as Dictionary).get("configured", false)
			)
			var equip_value: Variant = _player.call(
				"equip_active_item",
				definition.duplicate(true),
				replace_existing
			)
			if not equip_value is Dictionary or not bool((equip_value as Dictionary).get("ok", false)):
				_facade.call("cancel_reserved_selection", reservation_id)
				_choice_panel.show_rejection("CHOICE_REJECTED")
				return
		elif (
			not _player.has_method("reward_effect_snapshot")
			or not _player.has_method("reward_effect_begin_publication")
			or not _player.has_method("reward_effect_publication_can_commit")
			or not _player.has_method("reward_effect_commit_publication")
			or not _player.has_method("reward_effect_rollback_publication")
			or not bool(_player.call("reward_effect_begin_publication"))
		):
			_facade.call("cancel_reserved_selection", reservation_id)
			_choice_panel.show_rejection("CHOICE_REJECTED")
			return
		else:
			publication_started = true
			var snapshot_value: Variant = _player.call("reward_effect_snapshot")
			if not snapshot_value is Dictionary or (snapshot_value as Dictionary).is_empty():
				_facade.call("cancel_reserved_selection", reservation_id)
				if not bool(_player.call("reward_effect_rollback_publication")):
					_fail_reward_integrity({"stage": "player_snapshot"})
				else:
					_choice_panel.show_rejection("CHOICE_REJECTED")
				return
			var prepared: Dictionary = _reward_effect_runtime.call(
				"prepare",
				definition.duplicate(true),
				(snapshot_value as Dictionary).duplicate(true)
			)
			if not bool(prepared.get("ok", false)):
				_facade.call("cancel_reserved_selection", reservation_id)
				if not bool(_player.call("reward_effect_rollback_publication")):
					_fail_reward_integrity({
						"stage": "player_prepare",
						"effect_result": prepared.duplicate(true),
					})
				else:
					_choice_panel.show_rejection("CHOICE_REJECTED")
				return
			var player_commit: Dictionary = _reward_effect_runtime.call(
				"commit",
				(prepared.get("plan", {}) as Dictionary).duplicate(true),
				_player
			)
			if not bool(player_commit.get("ok", false)):
				_facade.call("cancel_reserved_selection", reservation_id)
				var publication_rollback_ok := bool(_player.call(
					"reward_effect_rollback_publication"
				))
				publication_started = false
				if (
					StringName(str(player_commit.get("code", ""))) == &"ROLLBACK_FAILED"
					or not publication_rollback_ok
				):
					_fail_reward_integrity({
						"stage": "player_commit",
						"effect_result": player_commit.duplicate(true),
						"publication_rollback_ok": publication_rollback_ok,
					})
				else:
					_choice_panel.show_rejection("CHOICE_REJECTED")
				return
			receipt = (player_commit.get("receipt", {}) as Dictionary).duplicate(true)
			if not bool(_player.call("reward_effect_publication_can_commit")):
				_facade.call("cancel_reserved_selection", reservation_id)
				var rolled_back: Dictionary = _reward_effect_runtime.call(
					"rollback",
					receipt.duplicate(true),
					_player
				)
				var publication_rollback_ok := bool(_player.call(
					"reward_effect_rollback_publication"
				))
				publication_started = false
				if not bool(rolled_back.get("ok", false)) or not publication_rollback_ok:
					_fail_reward_integrity({
						"stage": "player_publication_preflight",
						"rollback_result": rolled_back.duplicate(true),
						"publication_rollback_ok": publication_rollback_ok,
					})
				else:
					_choice_panel.show_rejection("CHOICE_REJECTED")
				return
	var committed = _facade.call("commit_reserved_selection", reservation_id)
	if not committed.ok:
		_facade.call("cancel_reserved_selection", reservation_id)
		var state_rollback_ok := true
		if is_talent_selection and not talent_before.is_empty():
			state_rollback_ok = bool(_player.call(
				"restore_character_talent_transaction_snapshot",
				talent_before.duplicate(true)
			))
		elif is_active_item_selection and not active_item_before.is_empty():
			state_rollback_ok = bool(_player.call(
				"restore_full_player_replay_snapshot",
				active_item_before.duplicate(true)
			))
		elif not receipt.is_empty():
			var rolled_back: Dictionary = _reward_effect_runtime.call(
				"rollback",
				receipt.duplicate(true),
				_player
			)
			state_rollback_ok = bool(rolled_back.get("ok", false))
		var publication_rollback_ok := true
		if publication_started:
			publication_rollback_ok = bool(_player.call(
				"reward_effect_rollback_publication"
			))
			publication_started = false
		if not state_rollback_ok or not publication_rollback_ok:
			_fail_reward_integrity({
				"stage": "authority_commit",
				"authority_code": str(committed.code),
				"state_rollback_ok": state_rollback_ok,
				"publication_rollback_ok": publication_rollback_ok,
			})
			return
		if committed.code == &"INTEGRITY_FAILURE":
			_fail_reward_integrity({
				"stage": "authority_commit",
				"authority_code": str(committed.code),
				"authority_context": committed.context.duplicate(true),
			})
			return
		_choice_panel.show_rejection(_rejection_message_key(committed))
		return
	if publication_started:
		if not bool(_player.call("reward_effect_commit_publication")):
			_fail_reward_integrity({
				"stage": "player_publication_commit",
				"authority_revision": int(committed.new_revision),
			})
			return
		publication_started = false
	var selection_revision := int(committed.context.get("selection_revision", committed.new_revision))
	var selection_state := runtime_snapshot()
	var run_id := str(selection_state.get("run_id", ""))
	if not run_id.is_empty() and run_id == _active_run_id and run_id == _published_run_id:
		EventBus.reward_selected.emit(run_id, definition.duplicate(true), selection_revision)
	_choice_panel.close_panel()
	_set_selection_safety(false)
	if _room_runtime != null and is_instance_valid(_room_runtime):
		_room_runtime.call_deferred("begin_current_room")


func _submit_launch_reward(offer_id: String, option_id: String, revision: int) -> void:
	if _facade == null or _choice_panel == null or not _facade.has_method("commit_current_reward"):
		return
	var committed: Variant = _facade.call("commit_current_reward", offer_id, option_id, revision)
	if committed == null or not bool(committed.get("ok")):
		_choice_panel.show_rejection(_rejection_message_key(committed) if committed is RefCounted else "CHOICE_REJECTED")
		return
	var definition := (committed.context.get("definition", {}) as Dictionary).duplicate(true)
	if not definition.is_empty():
		EventBus.reward_selected.emit(_active_run_id, definition, int(committed.new_revision))
	_choice_panel.close_panel()
	_set_selection_safety(_dungeon_selection_active)


func _fail_reward_integrity(context: Dictionary) -> void:
	var terminal_context := {
		"result": "runtime_error",
		"reason": "reward_transaction_integrity",
		"context": context.duplicate(true),
	}
	if _facade != null and _facade.has_method("player_died"):
		var terminal = _facade.call("player_died", terminal_context)
		if terminal != null and terminal.ok:
			_on_terminal_committed(terminal_context, int(terminal.new_revision))
			return
	if _choice_panel != null:
		_choice_panel.show_rejection("CHOICE_REJECTED")
	_set_selection_safety(true)


func _publish_terminal_result(authoritative_result: Dictionary) -> void:
	var state := runtime_snapshot()
	var run_id := str(state.get("run_id", ""))
	if (
		run_id.is_empty()
		or run_id != _active_run_id
		or run_id != _published_run_id
		or _ended_run_id == run_id
	):
		return
	var phase := int(state.get("phase", -1))
	if not RunPhaseScript.is_terminal(phase):
		return
	_ended_run_id = run_id
	var result := _terminal_result(state, authoritative_result)
	EventBus.run_ended.emit(run_id, result.duplicate(true), int(state.get("revision", 0)))


func _terminal_result(state: Dictionary, authoritative_result: Dictionary) -> Dictionary:
	var result_value: Variant = state.get("result", {})
	var result := (result_value as Dictionary).duplicate(true) if result_value is Dictionary else {}
	if result.is_empty():
		result = authoritative_result.duplicate(true)

	var phase := int(state.get("phase", -1))
	var outcome := str(result.get("result", ""))
	if phase == RunPhaseScript.Value.VICTORY or outcome == "victory":
		outcome = "floor_cleared"
	elif outcome.is_empty():
		outcome = "death" if phase == RunPhaseScript.Value.DEFEAT else "runtime_error"

	var current_room := int(state.get("current_room", 0))
	var rooms_cleared := current_room if phase == RunPhaseScript.Value.VICTORY else maxi(0, current_room - 1)
	var stats_value: Variant = state.get("stats", {})
	var stats: Dictionary = (stats_value as Dictionary).duplicate(true) if stats_value is Dictionary else {}
	var build_value: Variant = state.get("build", {})
	var build: Dictionary = (build_value as Dictionary).duplicate(true) if build_value is Dictionary else {}
	var categorized := _categorized_history(build)

	result["result"] = outcome
	result["floor"] = int(state.get("current_floor", 1))
	result["rooms_cleared"] = int(result.get("rooms_cleared", rooms_cleared))
	result["current_room"] = int(result.get("current_room", current_room))
	result["run_time"] = float(state.get("run_time_ms", 0)) / 1000.0
	result["kills"] = int(result.get("kills", stats.get("kills", 0)))
	result["stats"] = stats
	result["rewards"] = categorized["items"]
	result["blessings"] = categorized["blessings"]
	result["talent_choices"] = categorized["talents"]
	result["curses"] = categorized["curses"]
	result["run_id"] = str(state.get("run_id", ""))
	result["revision"] = int(state.get("revision", 0))
	return result


func _categorized_history(build: Dictionary) -> Dictionary:
	var categorized := {
		"items": [],
		"blessings": [],
		"curses": [],
		"talents": [],
	}
	var history_value: Variant = build.get("reward_history", [])
	if not history_value is Array:
		return categorized
	for entry_value: Variant in history_value:
		if not entry_value is Dictionary:
			continue
		var entry := (entry_value as Dictionary).duplicate(true)
		match str(entry.get("category", "")):
			"item":
				categorized["items"].append(entry)
			"blessing":
				categorized["blessings"].append(entry)
			"curse":
				categorized["curses"].append(entry)
			"talent":
				categorized["talents"].append(entry)
	return categorized


func _fail_start(code: StringName, context: Dictionary) -> Variant:
	var failure_context := {
		"result": "runtime_error",
		"runtime_error_code": str(code),
		"runtime_error_context": context.duplicate(true),
	}
	var state := runtime_snapshot()
	if _facade != null and not RunPhaseScript.is_terminal(int(state.get("phase", -1))):
		_facade.call("player_died", failure_context)
	_dispose_room_runtime()
	_initializing_run_id = ""
	_pending_initial_room_started.clear()
	_pending_initial_room_cleared.clear()
	_pending_initial_runtime_failure.clear()
	if _choice_panel != null:
		_choice_panel.close_panel()
	_set_selection_safety(false)
	if _profile_start_pending:
		_set_selection_safety(true)
		return CommandResultScript.failure(code, _revision(), {"startup_pending": true, "recovery": "retry_profile_startup", "cause": context})
	_publish_terminal_result(failure_context)
	return CommandResultScript.failure(code, _revision(), context)


func _resolve_player_for_start() -> void:
	if _player != null and is_instance_valid(_player):
		return
	if _room_controller != null and is_instance_valid(_room_controller):
		_player = _room_controller.get_node_or_null("Player")


func _retire_hostile_threats() -> void:
	if _room_controller != null and is_instance_valid(_room_controller) and _room_controller.has_method("retire_hostile_threats"):
		_room_controller.call("retire_hostile_threats")
	elif _hostile_threat_registry != null:
		_hostile_threat_registry.call("clear")


func _publish_pending_initial_room_started(run_id: String) -> void:
	if str(_pending_initial_room_started.get("run_id", "")) != run_id:
		_pending_initial_room_started.clear()
		return
	var room_id := StringName(str(_pending_initial_room_started.get("room_id", "")))
	var revision := int(_pending_initial_room_started.get("revision", 0))
	_pending_initial_room_started.clear()
	EventBus.room_started.emit(run_id, room_id, revision)


func _publish_pending_initial_room_cleared(run_id: String) -> void:
	if _pending_initial_room_cleared.is_empty():
		return
	if str(_pending_initial_room_cleared.get("run_id", "")) != run_id:
		_pending_initial_room_cleared.clear()
		return
	var room_id := StringName(str(_pending_initial_room_cleared.get("room_id", "")))
	var revision := int(_pending_initial_room_cleared.get("revision", 0))
	_pending_initial_room_cleared.clear()
	_publish_room_cleared(run_id, room_id, revision)


func _publish_room_cleared(run_id: String, room_id: StringName, revision: int) -> void:
	EventBus.room_cleared.emit(run_id, room_id, revision)
	var state := runtime_snapshot()
	if _is_floor_plan_snapshot(state) and int(state.get("phase", -1)) == RunPhaseScript.Value.ROOM_RESOLVING:
		var room := (_facade.call("current_room_definition") as Dictionary)
		if str(room.get("room_type", "")) in ["combat", "elite"] and _facade.has_method("open_current_room_reward"):
			var opened: Variant = _facade.call("open_current_room_reward", _revision())
			if opened != null and bool(opened.get("ok")):
				state = runtime_snapshot()
	if int(state.get("phase", -1)) == RunPhaseScript.Value.SELECTION_ACTIVE:
		_open_offer(state.get("open_offer", {}))


func _prepare_route_scene(target: Dictionary, context: Dictionary) -> Dictionary:
	if target.is_empty() or str(target.get("scene_path", "")).is_empty():
		return {"ok": false, "code": &"ROOM_SCENE_TARGET_INVALID"}
	var result: Variant = null
	if typeof(_route_scene_adapter) == TYPE_CALLABLE:
		result = (_route_scene_adapter as Callable).call(
			target.duplicate(true), context.duplicate(true)
		)
		return {
			"ok": _adapter_result_ok(result),
			"adapter_kind": "callable",
			"ticket": {},
		}
	elif _route_scene_adapter is Object and (
		_route_scene_adapter as Object
	).has_method("prepare_route_transition"):
		result = (_route_scene_adapter as Object).call(
			"prepare_route_transition", target.duplicate(true), context.duplicate(true)
		)
		var normalized := _adapter_result_dictionary(result)
		normalized["adapter_kind"] = "route_protocol"
		return normalized
	elif _route_scene_adapter is Object and (
		_route_scene_adapter as Object
	).has_method("prepare_transition"):
		var template: Dictionary = (target.get("template", {}) as Dictionary).duplicate(true)
		var node := {
			"id": str(target.get("node_id", "")),
			"template_id": str(target.get("template_id", "")),
			"room_type": str(target.get("room_type", "")),
		}
		result = (_route_scene_adapter as Object).call(
			"prepare_transition",
			node,
			template,
			(context.get("scene_context", {}) as Dictionary).duplicate(true)
		)
		var normalized := _adapter_result_dictionary(result)
		normalized["adapter_kind"] = "room_scene_host"
		return normalized
	else:
		return {"ok": false, "code": &"ROOM_SCENE_ADAPTER_INVALID"}


func _commit_route_scene(
	prepared: Dictionary,
	target: Dictionary,
	context: Dictionary
) -> Dictionary:
	var kind := str(prepared.get("adapter_kind", ""))
	if kind == "callable":
		return {"ok": true}
	if not _route_scene_adapter is Object:
		return {"ok": false}
	var ticket: Dictionary = (prepared.get("ticket", {}) as Dictionary).duplicate(true)
	var result: Variant = null
	if kind == "route_protocol" and (_route_scene_adapter as Object).has_method("commit_route_transition"):
		result = (_route_scene_adapter as Object).call(
			"commit_route_transition", ticket, target.duplicate(true), context.duplicate(true)
		)
	elif kind == "room_scene_host" and (_route_scene_adapter as Object).has_method("commit_transition"):
		result = (_route_scene_adapter as Object).call("commit_transition", ticket)
	return _adapter_result_dictionary(result)


func _confirm_route_scene(prepared: Dictionary, context: Dictionary) -> Dictionary:
	var kind := str(prepared.get("adapter_kind", ""))
	if kind == "callable":
		return {"ok": true}
	if not _route_scene_adapter is Object:
		return {"ok": false}
	var ticket: Dictionary = (prepared.get("ticket", {}) as Dictionary).duplicate(true)
	var result: Variant = null
	if kind == "route_protocol" and (_route_scene_adapter as Object).has_method("confirm_route_transition"):
		result = (_route_scene_adapter as Object).call(
			"confirm_route_transition", ticket, context.duplicate(true)
		)
	elif kind == "room_scene_host" and (_route_scene_adapter as Object).has_method("confirm_transition"):
		result = (_route_scene_adapter as Object).call("confirm_transition", ticket)
	return _adapter_result_dictionary(result)


func _rollback_route_scene(prepared: Dictionary, context: Dictionary) -> Dictionary:
	var kind := str(prepared.get("adapter_kind", ""))
	if kind == "callable":
		return {"ok": true}
	if not _route_scene_adapter is Object:
		return {"ok": false}
	var ticket: Dictionary = (prepared.get("ticket", {}) as Dictionary).duplicate(true)
	var result: Variant = null
	if kind == "route_protocol" and (_route_scene_adapter as Object).has_method("rollback_route_transition"):
		result = (_route_scene_adapter as Object).call(
			"rollback_route_transition", ticket, context.duplicate(true)
		)
	elif kind == "room_scene_host" and (_route_scene_adapter as Object).has_method("rollback_transition"):
		result = (_route_scene_adapter as Object).call("rollback_transition", ticket)
	return _adapter_result_dictionary(result)


func _compensate_route_after_room_entry(
	prepared_scene: Dictionary,
	adapter_context: Dictionary,
	transition_id: String
) -> bool:
	var scene_rollback := _rollback_route_scene(prepared_scene, adapter_context)
	var scene_rollback_ok := bool(scene_rollback.get("ok", false))
	var authority_rollback: Variant = _facade.call(
		"rollback_route_transition", transition_id, _revision()
	)
	var authority_rollback_ok := (
		authority_rollback != null and bool(authority_rollback.get("ok"))
	)
	var runtime_rollback_ok := false
	if authority_rollback_ok:
		runtime_rollback_ok = _rollback_room_runtime_entry()
	_discard_route_entry_publications()
	_floor_rule_frame_origin = -1
	return scene_rollback_ok and authority_rollback_ok and runtime_rollback_ok


func _rollback_room_runtime_entry() -> bool:
	if _room_runtime == null or not is_instance_valid(_room_runtime):
		return true
	if _room_runtime.has_method("rollback_route_entry"):
		return bool(_room_runtime.call("rollback_route_entry"))
	if (
		_facade == null
		or not _facade.has_method("create_room_runtime")
		or _room_controller == null
		or not is_instance_valid(_room_controller)
		or not _room_controller.has_method("encounter_runner")
		or not _room_controller.has_method("configure_authored_runtime")
	):
		return false
	var runner_value: Variant = _room_controller.call("encounter_runner")
	if not runner_value is Node:
		return false
	if (runner_value as Node).has_method("cancel"):
		(runner_value as Node).call("cancel")
	_dispose_room_runtime()
	var runtime_value: Variant = _facade.call("create_room_runtime", runner_value)
	if not runtime_value is Node:
		return false
	_room_runtime = runtime_value as Node
	_room_runtime.name = "RoomRuntime"
	add_child(_room_runtime)
	if not bool(_room_controller.call(
		"configure_authored_runtime",
		_room_runtime,
		_facade.call("encounter_catalog")
	)):
		_dispose_room_runtime()
		return false
	_connect_room_runtime()
	return true


func _floor_rule_configuration_for_scene(prepared: Dictionary) -> Dictionary:
	if not _route_scene_adapter is Object:
		return {}
	var ticket: Dictionary = (prepared.get("ticket", {}) as Dictionary).duplicate(true)
	var adapter := _route_scene_adapter as Object
	if adapter.has_method("floor_rule_configuration"):
		var value: Variant = adapter.call("floor_rule_configuration", ticket)
		return (value as Dictionary).duplicate(true) if value is Dictionary else {}
	return {}


func _advance_floor_rule_from_host() -> void:
	if (
		_facade == null
		or _room_controller == null
		or not _room_controller.has_method("character_boss_exposure_runtime_frame")
		or not _facade.has_method("advance_floor_rule_frame")
	):
		return
	var state := runtime_snapshot()
	if int(state.get("phase", -1)) not in [
		RunPhaseScript.Value.COMBAT_ACTIVE,
		RunPhaseScript.Value.BOSS_ACTIVE,
		RunPhaseScript.Value.ROOM_ACTIVE,
	]:
		return
	var floor_rule_state: Dictionary = state.get("floor_rule_state", {})
	if floor_rule_state.is_empty():
		_floor_rule_frame_origin = -1
		return
	var authority_frame := _host_runtime_frame()
	if _floor_rule_frame_origin < 0:
		_floor_rule_frame_origin = authority_frame - int(floor_rule_state.get("runtime_frame", -1)) - 1
	var runtime_frame := authority_frame - _floor_rule_frame_origin
	if runtime_frame <= int(floor_rule_state.get("runtime_frame", -1)):
		return
	var advanced: Variant = _facade.call(
		"advance_floor_rule_frame",
		runtime_frame,
		{},
		int(state.get("revision", -1))
	)
	if advanced == null or not _adapter_result_ok(advanced):
		_fail_floor_rule_frame_advance(advanced, runtime_frame)


func _reset_floor_rule_runtime_for_new_run() -> bool:
	if _route_scene_adapter is Object:
		var adapter := _route_scene_adapter as Object
		if (
			adapter.has_method("prepare_transition")
			and adapter.has_method("active_snapshot")
			and adapter.has_method("reset")
		):
			adapter.call("reset")
	if _floor_rule_effect_authority is Object:
		var authority := _floor_rule_effect_authority as Object
		if authority.has_method("reset_runtime_state"):
			return bool(authority.call("reset_runtime_state"))
	return true


func _fail_floor_rule_frame_advance(result: Variant, runtime_frame: int) -> void:
	var state := runtime_snapshot()
	if RunPhaseScript.is_terminal(int(state.get("phase", -1))):
		return
	var code := "INVALID_RESULT"
	var failure_context: Dictionary = {}
	if result is Dictionary:
		code = str((result as Dictionary).get("code", code))
		var dictionary_context: Variant = (result as Dictionary).get("context", {})
		if dictionary_context is Dictionary:
			failure_context = (dictionary_context as Dictionary).duplicate(true)
	elif result is Object:
		code = str((result as Object).get("code"))
		var object_context: Variant = (result as Object).get("context")
		if object_context is Dictionary:
			failure_context = (object_context as Dictionary).duplicate(true)
	var terminal_context := {
		"result": "runtime_error",
		"reason": "floor_rule_frame_advance",
		"runtime_frame": runtime_frame,
		"floor_rule_error_code": code,
		"floor_rule_error_context": failure_context,
	}
	_floor_rule_frame_origin = -1
	if _facade == null or not _facade.has_method("player_died"):
		_on_runtime_failed(terminal_context)
		return
	var terminal: Variant = _facade.call("player_died", terminal_context)
	if terminal != null and _adapter_result_ok(terminal):
		_on_terminal_committed(terminal_context, int(terminal.get("new_revision")))
		return
	_on_runtime_failed(terminal_context)


func _host_runtime_frame() -> int:
	if (
		_room_controller != null
		and _room_controller.has_method("character_boss_exposure_runtime_frame")
	):
		return int(_room_controller.call("character_boss_exposure_runtime_frame"))
	return maxi(0, int(Engine.get_physics_frames()))


func _floor_rule_effect_authority_is_valid() -> bool:
	if _floor_rule_effect_authority is Callable:
		return (_floor_rule_effect_authority as Callable).is_valid()
	return (
		_floor_rule_effect_authority is Object
		and (
			(_floor_rule_effect_authority as Object).has_method("commit_floor_rule_effects")
			or (_floor_rule_effect_authority as Object).has_method("commit_floor_rule_effect")
		)
	)


func _adapter_result_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		var result := (value as Dictionary).duplicate(true)
		if not result.has("ok"):
			result["ok"] = false
		return result
	return {"ok": _adapter_result_ok(value)}


func _adapter_result_ok(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	if value is Dictionary:
		return bool((value as Dictionary).get("ok", false))
	if value is Object:
		return bool((value as Object).get("ok"))
	return false


func _publish_floor_started_once(state: Dictionary) -> void:
	var plan: Dictionary = state.get("floor_plan", {})
	var run_id := str(state.get("run_id", ""))
	var floor_id := str(plan.get("floor_id", ""))
	var floor_index := int(state.get("current_floor_index", -1))
	if run_id.is_empty() or floor_id.is_empty() or floor_index < 0:
		return
	var event_id := "%s:%s:%d" % [run_id, floor_id, floor_index]
	if _published_floor_start_ids.has(event_id):
		return
	_published_floor_start_ids[event_id] = true
	EventBus.floor_started.emit(
		run_id, StringName(floor_id), floor_index, int(state.get("revision", 0))
	)


func _publish_floor_completed_if_new(state: Dictionary, revision: int) -> void:
	var run_id := str(state.get("run_id", ""))
	var completed: Array = state.get("completed_floor_ids", [])
	if run_id.is_empty() or completed.is_empty():
		return
	var floor_id := str(completed[-1])
	var floor_index := completed.size() - 1
	var event_id := "%s:%s:%d" % [run_id, floor_id, floor_index]
	if _published_floor_completion_ids.has(event_id):
		return
	_published_floor_completion_ids[event_id] = true
	EventBus.floor_completed.emit(
		run_id, StringName(floor_id), floor_index, revision
	)


func _is_floor_plan_snapshot(state: Dictionary) -> bool:
	return str(state.get("config", {}).get("milestone", "")) in [
		"LAUNCH", "EXPANSION",
	]


func _set_selection_safety(active_selection: bool) -> void:
	if not active_selection and (_floor_entry_recovery_pending or _profile_publication_pending):
		return
	if active_selection:
		if _selection_safety_active:
			return
		_selection_safety_active = true
		if _player != null and is_instance_valid(_player):
			if _player.has_method("cancel_transient_actions"):
				_player.call("cancel_transient_actions")
			if _player.has_method("cancel_active_time_effects"):
				_player.call("cancel_active_time_effects", &"selection_opened")
			_player_process_mode = _player.process_mode
			_player.process_mode = Node.PROCESS_MODE_DISABLED
		_clear_hostile_transients()
		if _room_controller != null and is_instance_valid(_room_controller):
			_room_controller_process_mode = _room_controller.process_mode
			_room_controller.process_mode = Node.PROCESS_MODE_DISABLED
		return
	if not _selection_safety_active:
		return
	if _player != null and is_instance_valid(_player):
		_player.process_mode = _player_process_mode
	if _room_controller != null and is_instance_valid(_room_controller):
		_room_controller.process_mode = _room_controller_process_mode
	_selection_safety_active = false


func _cancel_player_time_effects(reason: StringName) -> void:
	if _player != null and is_instance_valid(_player) and _player.has_method("cancel_active_time_effects"):
		_player.call("cancel_active_time_effects", reason)


func _clear_hostile_transients() -> void:
	for node: Node in get_tree().get_nodes_in_group("time_stoppable"):
		if node == _player or node.is_in_group("enemies"):
			continue
		if not node.is_queued_for_deletion():
			node.queue_free()
	for node: Node in get_tree().get_nodes_in_group("boss_hazards"):
		if not node.is_queued_for_deletion():
			node.queue_free()


func _render_live_hud() -> void:
	if not _presentation_enabled or _hud_layer == null or _projector == null or _facade == null:
		return
	var authoritative := runtime_snapshot()
	if str(authoritative.get("run_id", "")) != _active_run_id:
		return
	var room_definition := _facade.call("current_room_definition") as Dictionary
	var projected = _projector.project(
		authoritative,
		room_definition,
		_player_ui_snapshot(),
		_boss_ui_snapshot(),
		int(authoritative.get("run_time_ms", 0)),
		{"show_pause": get_tree().paused}
	)
	if projected.ok:
		_hud_layer.call("render", projected.context.get("view_state", {}))


func _player_ui_snapshot() -> Dictionary:
	if _player == null or not is_instance_valid(_player):
		return {}
	if _player.has_method("get_player_ui_snapshot"):
		var provided: Variant = _player.call("get_player_ui_snapshot")
		return (provided as Dictionary).duplicate(true) if provided is Dictionary else {}
	return {}


func _boss_ui_snapshot() -> Variant:
	for candidate: Node in get_tree().get_nodes_in_group("bosses"):
		if not is_instance_valid(candidate) or not _room_controller.is_ancestor_of(candidate):
			continue
		var source: Dictionary = {}
		if candidate.has_method("get_boss_ui_snapshot"):
			var provided: Variant = candidate.call("get_boss_ui_snapshot")
			if provided is Dictionary:
				source = (provided as Dictionary).duplicate(true)
		var health := candidate.get_node_or_null("HealthComponent")
		if health == null and (not source.has("hp") or not source.has("max_hp")):
			return null
		var phase_total := maxi(1, int(source.get("phase_total", 3)))
		return {
			"boss_id": str(source.get("boss_id", "chrono_warden")),
			"name_key": str(source.get("name_key", "BOSS_NAME_CHRONO_WARDEN")),
			"hp": float(source.get("hp", health.current_hp if health != null else 0.0)),
			"max_hp": float(source.get("max_hp", health.max_hp if health != null else 1.0)),
			"phase_index": clampi(int(source.get("phase_index", source.get("boss_phase", 1))), 1, phase_total),
			"phase_total": phase_total,
		}
	return null


func _rejection_message_key(result: RefCounted) -> String:
	var message_key := str(result.message_key)
	return message_key if not message_key.is_empty() else "CHOICE_REJECTED"


func _revision() -> int:
	return int(runtime_snapshot().get("revision", 0))
