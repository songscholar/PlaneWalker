class_name LegacyRunAdapter
extends Node

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunViewStateProjectorScript := preload("res://scripts/application/run_view_state_projector.gd")
const ChoicePanelScene := preload("res://scenes/ui/choice_panel_v2.tscn")
const CombatHudScene := preload("res://scenes/ui/combat_hud_v2.tscn")

const RUNTIME_FACADE_PATH := "res://scripts/application/run_runtime_facade.gd"
const HUD_RENDER_INTERVAL := 0.1
const LEGACY_SELECTION_NAMES: Array[StringName] = [
	&"RewardSelection",
	&"CurseSelection",
	&"EventSelection",
]

@export var enabled: bool = false
@export var room_controller_path: NodePath
@export_file("*.json") var manifest_path: String = "res://data/content_manifest.json"

var _active: bool = false
var _facade: RefCounted
var _room_controller: Node
var _player: Node
var _projector: RefCounted
var _hud_layer: CanvasLayer
var _legacy_hud: Node
var _legacy_hud_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT
var _legacy_hud_visible: bool = true
var _legacy_hud_state_captured: bool = false
var _hud_render_accumulator: float = 0.0
var _choice_layer: CanvasLayer
var _choice_panel: Control
var _active_run_id: String = ""
var _run_serial: int = 0
var _last_tree_paused: bool = false
var _selection_safety_active: bool = false
var _player_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_tree_paused = get_tree().paused
	if not enabled:
		return
	_room_controller = get_node_or_null(room_controller_path)
	if _room_controller == null:
		return
	_player = _room_controller.get_node_or_null("Player")
	if _player == null:
		return
	_legacy_hud = _room_controller.get_node_or_null("CombatHUD")
	_facade = _create_facade()
	if _facade == null:
		return
	var booted = _facade.boot(manifest_path)
	if not booted.ok:
		return
	if _create_hud_layer():
		_set_legacy_hud_enabled(false)
	_create_choice_layer()
	_disable_legacy_selection_views()
	_connect_runtime_signals()
	_active = true


func _process(delta: float) -> void:
	if not _active or _facade == null:
		return
	var tree_paused := get_tree().paused
	if tree_paused != _last_tree_paused:
		_last_tree_paused = tree_paused
		var state := _facade.snapshot() as Dictionary
		if _matches_active_run(state) and not RunPhaseScript.is_terminal(int(state.get("phase", -1))):
			if tree_paused:
				_facade.pause_run()
			else:
				_facade.resume_run()

	if _hud_layer == null or _projector == null or _active_run_id.is_empty():
		return
	_hud_render_accumulator += maxf(0.0, delta)
	if _hud_render_accumulator < HUD_RENDER_INTERVAL:
		return
	_hud_render_accumulator = fmod(_hud_render_accumulator, HUD_RENDER_INTERVAL)
	_render_live_hud()


func _create_facade() -> RefCounted:
	if not ResourceLoader.exists(RUNTIME_FACADE_PATH):
		return null
	var facade_script: Script = load(RUNTIME_FACADE_PATH)
	if facade_script == null:
		return null
	return facade_script.new() as RefCounted


func _create_hud_layer() -> bool:
	if _hud_layer != null:
		return true
	var hud_instance := CombatHudScene.instantiate()
	if hud_instance == null:
		return false
	if not hud_instance is CanvasLayer or not hud_instance.has_method("render"):
		hud_instance.free()
		return false
	_projector = RunViewStateProjectorScript.new()
	if _projector == null:
		hud_instance.free()
		return false
	_hud_layer = hud_instance as CanvasLayer
	_hud_layer.name = "HudLayer"
	_hud_layer.layer = 10
	_hud_layer.visible = false
	add_child(_hud_layer)
	return true


func _create_choice_layer() -> void:
	if _choice_layer != null:
		return
	_choice_layer = CanvasLayer.new()
	_choice_layer.name = "ChoiceLayer"
	_choice_layer.layer = 20
	add_child(_choice_layer)
	_choice_panel = ChoicePanelScene.instantiate() as Control
	_choice_layer.add_child(_choice_panel)
	_choice_panel.option_chosen.connect(_on_option_chosen)


func _disable_legacy_selection_views() -> void:
	for view_name: StringName in LEGACY_SELECTION_NAMES:
		var view := _room_controller.get_node_or_null(NodePath(str(view_name)))
		if view == null:
			continue
		view.process_mode = Node.PROCESS_MODE_DISABLED
		if view is CanvasItem:
			(view as CanvasItem).visible = false
		view.queue_free()


func _connect_runtime_signals() -> void:
	if not EventBus.run_started.is_connected(_on_run_started):
		EventBus.run_started.connect(_on_run_started)
	if not EventBus.room_started.is_connected(_on_room_started):
		EventBus.room_started.connect(_on_room_started)
	if not EventBus.room_cleared.is_connected(_on_room_cleared):
		EventBus.room_cleared.connect(_on_room_cleared)
	if not EventBus.run_ended.is_connected(_on_run_ended):
		EventBus.run_ended.connect(_on_run_ended)


func _on_run_started(run_data: Dictionary) -> void:
	if not _active:
		return
	var next_facade := _create_facade()
	if next_facade == null:
		return
	var booted = next_facade.boot(manifest_path)
	if not booted.ok:
		return
	_run_serial += 1
	var config := {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": str(run_data.get("character_id", "wanderer")),
		"weapon_id": str(run_data.get("weapon_id", "sword")),
		"enabled_time_skills": ["time_stop", "time_rewind"],
		"difficulty": str(run_data.get("difficulty", "normal")),
		"seed": int(GameState.run_seed),
	}
	var run_id := "m1-%d-%d" % [int(GameState.run_seed), _run_serial]
	var started = next_facade.start_run(config, run_id)
	if not started.ok:
		return
	if _room_controller.has_method("configure_authored_runtime"):
		var configured: bool = _room_controller.call(
			"configure_authored_runtime",
			next_facade.room_plan(),
			next_facade.encounter_catalog(),
			int(GameState.run_seed)
		)
		if not configured:
			return
	_set_selection_safety(false)
	if _choice_panel != null:
		_choice_panel.close_panel()
	_facade = next_facade
	_active_run_id = run_id
	_last_tree_paused = get_tree().paused
	_hud_render_accumulator = 0.0


func _on_room_started(_room_id: StringName) -> void:
	if not _can_handle_lifecycle():
		return
	var state := _facade.snapshot() as Dictionary
	if int(state.get("phase", -1)) != RunPhaseScript.Value.ROOM_ENTERING:
		return
	if int(state.get("current_room", 0)) != GameState.current_room:
		return
	var entered = _facade.enter_current_room()
	if not entered.ok:
		return
	var room_definition := _facade.current_room_definition() as Dictionary
	GameState.set_current_room_type(StringName(str(room_definition.get("type", "combat"))))


func _on_room_cleared(_room_id: StringName) -> void:
	if not _can_handle_lifecycle():
		return
	var state := _facade.snapshot() as Dictionary
	if int(state.get("current_room", 0)) != GameState.current_room:
		return
	match int(state.get("phase", -1)):
		RunPhaseScript.Value.COMBAT_ACTIVE:
			_open_room_offer()
		RunPhaseScript.Value.BOSS_ACTIVE:
			_complete_boss_run()


func _open_room_offer() -> void:
	var completed = _facade.complete_current_room()
	if not completed.ok:
		return
	var offer: Dictionary = completed.context.get("offer", {}).duplicate(true)
	if offer.is_empty():
		return
	_set_selection_safety(true)
	var rendered = _choice_panel.render(offer)
	if not rendered.ok:
		_set_selection_safety(false)


func _complete_boss_run() -> void:
	var context := {
		"result": "floor_cleared",
		"floor": GameState.current_floor,
		"rooms_cleared": GameState.current_room,
		"current_room": GameState.current_room,
		"run_time": GameState.run_timer,
		"rewards": GameState.current_run.get("rewards", []).duplicate(true),
		"blessings": GameState.current_run.get("blessings", []).duplicate(true),
		"talent_choices": GameState.current_run.get("talent_choices", []).duplicate(true),
		"curses": GameState.current_run.get("curses", []).duplicate(true),
	}
	var completed = _facade.boss_defeated(context)
	if not completed.ok:
		return
	if _choice_panel != null:
		_choice_panel.close_panel()
	_set_selection_safety(false)
	GameState.end_run(context)


func _on_option_chosen(offer_id: String, option_id: String, revision: int) -> void:
	if not _can_handle_lifecycle() or _choice_panel == null:
		return
	if _player == null or not is_instance_valid(_player) or not _player.has_method("apply_reward"):
		_choice_panel.show_rejection("CHOICE_REJECTED")
		return
	var result = _facade.submit_selection(offer_id, option_id, revision)
	if not result.ok:
		_choice_panel.show_rejection(_rejection_message_key(result))
		return
	var definition: Dictionary = result.context.get("definition", {}).duplicate(true)
	var transitioned = _facade.complete_transition()
	if not transitioned.ok:
		_choice_panel.show_rejection(_rejection_message_key(transitioned))
		return
	if str(definition.get("id", "")) != "decline_contract":
		_player.apply_reward(definition)
		_mirror_definition_to_game_state(definition)
	_choice_panel.close_panel()
	_set_selection_safety(false)
	EventBus.reward_selected.emit(definition)


func _mirror_definition_to_game_state(definition: Dictionary) -> void:
	match str(definition.get("category", "")):
		"item":
			GameState.add_run_reward(definition)
		"blessing":
			GameState.add_run_blessing(definition)
		"curse":
			GameState.add_run_curse(definition)
		"talent":
			GameState.add_run_talent(definition)


func _on_run_ended(result: Dictionary) -> void:
	if not _active or _facade == null or _active_run_id.is_empty():
		return
	var state := _facade.snapshot() as Dictionary
	if not _matches_active_run(state):
		return
	if not RunPhaseScript.is_terminal(int(state.get("phase", -1))):
		if str(result.get("result", "")) == "death" or GameState.phase == GameState.GamePhase.DEATH:
			_facade.player_died(result)
		elif int(state.get("phase", -1)) == RunPhaseScript.Value.BOSS_ACTIVE:
			_facade.boss_defeated(result)
	if _choice_panel != null:
		_choice_panel.close_panel()
	_set_selection_safety(false)


func _set_selection_safety(active_selection: bool) -> void:
	if active_selection:
		if _selection_safety_active:
			return
		_selection_safety_active = true
		if _player != null and is_instance_valid(_player):
			if _player.has_method("cancel_transient_actions"):
				_player.call("cancel_transient_actions")
			_player_process_mode = _player.process_mode
			_player.process_mode = Node.PROCESS_MODE_DISABLED
		_clear_hostile_transients()
		if GameState.phase != GameState.GamePhase.DEATH and GameState.phase != GameState.GamePhase.RUN_END:
			GameState.set_phase(GameState.GamePhase.SELECTION)
		return
	if not _selection_safety_active:
		return
	if _player != null and is_instance_valid(_player):
		_player.process_mode = _player_process_mode
	_selection_safety_active = false


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
	if _hud_layer == null or _projector == null or _facade == null:
		return
	var authoritative := _facade.snapshot() as Dictionary
	if not _matches_active_run(authoritative):
		return
	if not _facade.has_method("current_room_definition"):
		_fallback_to_legacy_hud()
		return
	var room_definition := _facade.current_room_definition() as Dictionary
	var player_snapshot := _player_ui_snapshot()
	var boss_snapshot: Variant = _boss_ui_snapshot()
	var projected = _projector.project(
		authoritative,
		room_definition,
		player_snapshot,
		boss_snapshot,
		roundi(GameState.run_timer * 1000.0),
		{"show_pause": get_tree().paused}
	)
	if not projected.ok:
		_fallback_to_legacy_hud()
		return
	var view_state: Dictionary = projected.context.get("view_state", {})
	var rendered = _hud_layer.render(view_state)
	if not rendered.ok:
		_fallback_to_legacy_hud()
		return
	_hud_layer.visible = true


func _player_ui_snapshot() -> Dictionary:
	if _player == null or not is_instance_valid(_player):
		return {}
	if _player.has_method("get_player_ui_snapshot"):
		var snapshot: Variant = _player.call("get_player_ui_snapshot")
		return (snapshot as Dictionary).duplicate(true) if snapshot is Dictionary else {}

	var health := _player.get_node_or_null("HealthComponent")
	var time_manager := _player.get_node_or_null("TimeManager")
	if health == null or time_manager == null or not time_manager.has_method("get_cooldown"):
		return {}
	return {
		"hp": float(health.current_hp),
		"max_hp": float(health.max_hp),
		"energy": float(time_manager.energy),
		"max_energy": float(time_manager.max_energy),
		"action_state": "FREE",
		"cooldowns": {
			"time_stop": float(time_manager.get_cooldown(&"time_stop")),
			"time_rewind": float(time_manager.get_cooldown(&"time_rewind")),
		},
	}


func _boss_ui_snapshot() -> Variant:
	if _room_controller == null or not is_instance_valid(_room_controller):
		return null
	var boss: Node
	for candidate: Node in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(candidate) and _room_controller.is_ancestor_of(candidate):
			boss = candidate
			break
	if boss == null:
		return null

	var source: Dictionary = {}
	if boss.has_method("get_boss_ui_snapshot"):
		var provided: Variant = boss.call("get_boss_ui_snapshot")
		if provided is Dictionary:
			source = (provided as Dictionary).duplicate(true)
	var health := boss.get_node_or_null("HealthComponent")
	if health == null and (not source.has("hp") or not source.has("max_hp")):
		return null
	var phase_total := maxi(1, int(source.get("phase_total", 3)))
	var phase_index := clampi(int(source.get("phase_index", source.get("boss_phase", 1))), 1, phase_total)
	return {
		"boss_id": str(source.get("boss_id", "chrono_warden")),
		"name_key": str(source.get("name_key", "BOSS_NAME_CHRONO_WARDEN")),
		"hp": float(source.get("hp", health.current_hp if health != null else 0.0)),
		"max_hp": float(source.get("max_hp", health.max_hp if health != null else 1.0)),
		"phase_index": phase_index,
		"phase_total": phase_total,
	}


func _set_legacy_hud_enabled(enabled_state: bool) -> void:
	if _legacy_hud == null or not is_instance_valid(_legacy_hud):
		return
	if not _legacy_hud_state_captured:
		_legacy_hud_process_mode = _legacy_hud.process_mode
		if _legacy_hud is CanvasLayer:
			_legacy_hud_visible = (_legacy_hud as CanvasLayer).visible
		elif _legacy_hud is CanvasItem:
			_legacy_hud_visible = (_legacy_hud as CanvasItem).visible
		_legacy_hud_state_captured = true
	_legacy_hud.process_mode = _legacy_hud_process_mode if enabled_state else Node.PROCESS_MODE_DISABLED
	var visible_state := _legacy_hud_visible if enabled_state else false
	if _legacy_hud is CanvasLayer:
		(_legacy_hud as CanvasLayer).visible = visible_state
	elif _legacy_hud is CanvasItem:
		(_legacy_hud as CanvasItem).visible = visible_state


func _fallback_to_legacy_hud() -> void:
	_set_legacy_hud_enabled(true)
	if _hud_layer != null and is_instance_valid(_hud_layer):
		_hud_layer.visible = false
		_hud_layer.process_mode = Node.PROCESS_MODE_DISABLED
		_hud_layer.queue_free()
	_hud_layer = null
	_projector = null
	_hud_render_accumulator = 0.0


func _can_handle_lifecycle() -> bool:
	if not _active or _facade == null or _active_run_id.is_empty():
		return false
	if GameState.phase == GameState.GamePhase.DEATH or GameState.phase == GameState.GamePhase.RUN_END:
		return false
	var state := _facade.snapshot() as Dictionary
	return _matches_active_run(state) and not RunPhaseScript.is_terminal(int(state.get("phase", -1)))


func _matches_active_run(state: Dictionary) -> bool:
	return not _active_run_id.is_empty() and str(state.get("run_id", "")) == _active_run_id


func _rejection_message_key(result: RefCounted) -> String:
	var message_key := str(result.message_key)
	return message_key if not message_key.is_empty() else "CHOICE_REJECTED"
