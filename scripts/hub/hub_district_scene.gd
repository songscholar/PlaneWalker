class_name HubDistrictScene
extends Node2D

signal function_requested(function_id: String)

const NPC_IDS := ["odysseus", "elara", "sibyl", "hermes", "phia", "morpheus", "nemesis", "vera"]
const PortraitTexture := preload("res://data/content_packs/base/assets/hub/hub_portraits.png")
const WALK_BOUNDS := Rect2(64, 144, 544, 172)
const WALK_SPEED := 96.0
const INTERACTION_RADIUS := 48.0

@export var district_id := ""

var _definition: Dictionary = {}
var _walker: CharacterBody2D
var _functions: Dictionary = {}
var _interaction_enabled := true


func populate(definition: Dictionary) -> bool:
	if not _definition.is_empty() or definition.get("id") != district_id or not definition.get("functions") is Array or definition.functions.size() != 3:
		return false
	_definition = definition.duplicate(true)
	_walker = CharacterBody2D.new()
	_walker.name = "Walker"
	_walker.collision_layer = 0
	_walker.collision_mask = 0
	_walker.position = Vector2(definition.arrival.x, definition.arrival.y)
	_walker.add_child(_sprite(8))
	add_child(_walker)
	for function: Dictionary in definition.functions:
		var marker := Node2D.new()
		marker.name = str(function.id)
		marker.position = Vector2(function.position.x, function.position.y)
		marker.add_child(_sprite(NPC_IDS.find(function.npc_id)))
		var label := Label.new()
		label.name = "NameLabel"
		label.position = Vector2(-64, -42)
		label.size = Vector2(128, 18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = tr("NPC_%s_NAME" % str(function.npc_id).to_upper())
		label.add_theme_font_size_override("font_size", 10)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_child(label)
		add_child(marker)
		_functions[function.id] = marker
	refresh_localization()
	return true


func _physics_process(_delta: float) -> void:
	if not _interaction_enabled or _walker == null or not visible or get_tree().paused or FocusCoordinator.active_scope() != null:
		return
	_walker.velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * WALK_SPEED
	_walker.move_and_slide()
	_walker.position = _walker.position.clamp(WALK_BOUNDS.position, WALK_BOUNDS.end)


func _unhandled_input(event: InputEvent) -> void:
	if not _interaction_enabled or not visible or get_tree().paused or FocusCoordinator.active_scope() != null or not event.is_action_pressed("interact"):
		return
	var nearest := ""
	var distance := INTERACTION_RADIUS
	for id: String in _functions:
		var candidate: float = _walker.position.distance_to((_functions[id] as Node2D).position)
		if candidate <= distance:
			nearest = id
			distance = candidate
	if not nearest.is_empty():
		function_requested.emit(nearest)
		get_viewport().set_input_as_handled()


func set_interaction_enabled(value: bool) -> void:
	_interaction_enabled = value
	if _walker != null:
		_walker.velocity = Vector2.ZERO


func walker_position() -> Vector2:
	return _walker.position if _walker != null else Vector2.ZERO


func function_ids() -> Array:
	return _functions.keys().duplicate()


func refresh_localization() -> void:
	for function: Dictionary in _definition.get("functions", []):
		var label: Label = (_functions[function.id] as Node2D).get_node("NameLabel")
		label.text = tr("NPC_%s_NAME" % str(function.npc_id).to_upper())
		label.add_theme_font_size_override("font_size", roundi(10 * clampf(float(GameState.get_setting("text_scale", 1.0)), 1.0, 1.5)))


func _sprite(index: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = PortraitTexture
	sprite.hframes = 9
	sprite.frame = index
	sprite.position.y = -12
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite
