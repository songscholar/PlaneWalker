class_name GauntletsComboAura
extends Node2D

const PIXELS_PER_TILE := 64.0
const RADIUS_TILES := 2.0
const SLOW_MULTIPLIER := 0.85
const VISUAL_RING_COUNT := 2
const AURA_COLOR := Color(0.24, 0.92, 1.0, 0.72)
const AURA_FILL_COLOR := Color(0.08, 0.42, 0.56, 0.12)

var source_generation: int = 0
var owner_entity: Node

var _source_id: StringName = &""
var _affected_targets: Dictionary = {}
var _execution_active: bool = false
var _visual_clock: float = 0.0


func _ready() -> void:
	add_to_group("gauntlets_combo_auras")
	show_behind_parent = true
	z_index = -2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(_execution_active)
	set_physics_process(_execution_active)
	queue_redraw()


func _process(delta: float) -> void:
	if not _execution_active:
		return
	_visual_clock += maxf(0.0, delta)
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if not _execution_active:
		return
	if not _owner_is_alive():
		_retire()
		return
	_refresh_targets()


func configure_execution(owner: Node, generation: int) -> bool:
	reset_execution_state()
	if owner == null or not is_instance_valid(owner) or generation <= 0:
		return false
	owner_entity = owner
	source_generation = generation
	_source_id = StringName("gauntlets_combo_aura:%d" % generation)
	_execution_active = true
	_visual_clock = 0.0
	set_process(is_inside_tree())
	set_physics_process(is_inside_tree())
	queue_redraw()
	return true


func advance_execution_for_test(frames: int) -> void:
	if not _execution_active or frames <= 0:
		return
	for _frame: int in range(frames):
		if not _owner_is_alive():
			_retire()
			return
		_refresh_targets()


func execution_snapshot() -> Dictionary:
	if not _execution_active:
		return {}
	var target_ids: Array[int] = []
	for target_id: Variant in _affected_targets:
		target_ids.append(int(target_id))
	target_ids.sort()
	return {
		"source_generation": source_generation,
		"source_id": _source_id,
		"radius_tiles": RADIUS_TILES,
		"slow_multiplier": SLOW_MULTIPLIER,
		"target_ids": target_ids,
		"execution_active": _execution_active,
		"visual_visible": visible and _execution_active,
		"visual_radius_pixels": RADIUS_TILES * PIXELS_PER_TILE,
		"visual_ring_count": VISUAL_RING_COUNT,
	}


func reset_execution_state() -> void:
	_clear_targets()
	_execution_active = false
	_visual_clock = 0.0
	set_process(false)
	set_physics_process(false)
	source_generation = 0
	owner_entity = null
	_source_id = &""
	queue_redraw()


func _refresh_targets() -> void:
	if not is_inside_tree():
		return
	var current: Dictionary = {}
	var radius_pixels := RADIUS_TILES * PIXELS_PER_TILE
	for target: Node in get_tree().get_nodes_in_group("enemies"):
		if target == null or not is_instance_valid(target) or not target is Node2D:
			continue
		if (target as Node2D).global_position.distance_to(global_position) > radius_pixels + 0.001:
			continue
		var target_id := _stable_target_id(target)
		current[target_id] = target
		if target.has_method("apply_time_rift"):
			target.call("apply_time_rift", _source_id, SLOW_MULTIPLIER)
	for target_id: Variant in _affected_targets:
		if current.has(target_id):
			continue
		_clear_target(_affected_targets[target_id])
	_affected_targets = current


func _clear_targets() -> void:
	for target_value: Variant in _affected_targets.values():
		_clear_target(target_value)
	_affected_targets.clear()


func _clear_target(target_value: Variant) -> void:
	if (
		is_instance_valid(target_value)
		and target_value is Node
		and (target_value as Node).has_method("clear_time_rift")
	):
		(target_value as Node).call("clear_time_rift", _source_id)


func _owner_is_alive() -> bool:
	if owner_entity == null or not is_instance_valid(owner_entity):
		return false
	var health := owner_entity.get_node_or_null("HealthComponent")
	return health == null or not bool(health.get("dead"))


func _stable_target_id(target: Node) -> int:
	if target.has_meta("stable_target_id"):
		var value: Variant = target.get_meta("stable_target_id")
		if typeof(value) == TYPE_INT and int(value) > 0:
			return int(value)
	return target.get_instance_id()


func _retire() -> void:
	_clear_targets()
	_execution_active = false
	set_process(false)
	set_physics_process(false)
	queue_redraw()
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()


func _draw() -> void:
	if not _execution_active:
		return
	var radius := RADIUS_TILES * PIXELS_PER_TILE
	var pulse_step := float(int(_visual_clock * 8.0) % 3) * 2.0
	draw_circle(Vector2.ZERO, radius, AURA_FILL_COLOR)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, AURA_COLOR, 2.0, false)
	draw_arc(Vector2.ZERO, radius - 8.0 - pulse_step, 0.0, TAU, 64, AURA_COLOR.darkened(0.2), 2.0, false)
	for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		var marker_center := direction * radius
		draw_rect(Rect2(marker_center - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color.WHITE, true)


func _exit_tree() -> void:
	reset_execution_state()
