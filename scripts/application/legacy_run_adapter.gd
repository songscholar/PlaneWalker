class_name LegacyRunAdapter
extends Node

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const ChoicePanelScene := preload("res://scenes/ui/choice_panel_v2.tscn")

const RUNTIME_FACADE_PATH := "res://scripts/application/run_runtime_facade.gd"
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
	_facade = _create_facade()
	if _facade == null:
		return
	var booted = _facade.boot(manifest_path)
	if not booted.ok:
		return
	_create_choice_layer()
	_disable_legacy_selection_views()
	_connect_runtime_signals()
	_active = true


func _process(_delta: float) -> void:
	if not _active or _facade == null:
		return
	var tree_paused := get_tree().paused
	if tree_paused == _last_tree_paused:
		return
	_last_tree_paused = tree_paused
	var state := _facade.snapshot() as Dictionary
	if not _matches_active_run(state) or RunPhaseScript.is_terminal(int(state.get("phase", -1))):
		return
	if tree_paused:
		_facade.pause_run()
	else:
		_facade.resume_run()


func _create_facade() -> RefCounted:
	if not ResourceLoader.exists(RUNTIME_FACADE_PATH):
		return null
	var facade_script: Script = load(RUNTIME_FACADE_PATH)
	if facade_script == null:
		return null
	return facade_script.new() as RefCounted


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
	_set_selection_safety(false)
	if _choice_panel != null:
		_choice_panel.close_panel()
	_facade = next_facade
	_active_run_id = run_id
	_last_tree_paused = get_tree().paused


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
