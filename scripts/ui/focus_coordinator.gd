extends Node

const MAX_SCOPE_DEPTH := 16

var _frames: Array[Dictionary] = []


func open_scope(scope: Node, initial_focus: Control) -> void:
	if scope == null or not is_instance_valid(scope):
		return
	_remove_existing_scope(scope)
	var previous_owner := get_viewport().gui_get_focus_owner()
	_frames.append({
		"scope": weakref(scope),
		"initial_focus": weakref(initial_focus) if initial_focus != null else null,
		"previous_owner": weakref(previous_owner) if previous_owner != null else null,
	})
	while _frames.size() > MAX_SCOPE_DEPTH:
		_frames.pop_front()
	call_deferred(
		"_focus_first_valid",
		weakref(scope),
		weakref(initial_focus) if initial_focus != null else null
	)


func close_scope(scope: Node) -> void:
	var index := _frame_index(scope)
	if index < 0:
		return
	var was_top := index == _frames.size() - 1
	var frame: Dictionary = _frames[index]
	_frames.remove_at(index)
	if not was_top:
		_clear_removed_scope_references(scope, index)
		return
	call_deferred("_restore_after_close", frame.get("previous_owner"))


func recover(scope: Node, fallback: Control) -> void:
	if active_scope() != scope:
		return
	var owner := get_viewport().gui_get_focus_owner()
	if _is_focusable(owner) and _belongs_to_scope(owner, scope):
		return
	call_deferred(
		"_focus_first_valid",
		weakref(scope),
		weakref(fallback) if fallback != null else null
	)


func link_ring(controls: Array[Control], horizontal: bool) -> void:
	var valid: Array[Control] = []
	for control: Control in controls:
		if _is_focusable(control):
			valid.append(control)
	if valid.is_empty():
		return
	for index: int in range(valid.size()):
		var control := valid[index]
		var previous := valid[(index - 1 + valid.size()) % valid.size()]
		var next := valid[(index + 1) % valid.size()]
		var previous_path := control.get_path_to(previous)
		var next_path := control.get_path_to(next)
		control.focus_previous = previous_path
		control.focus_next = next_path
		if horizontal:
			control.focus_neighbor_left = previous_path
			control.focus_neighbor_right = next_path
		else:
			control.focus_neighbor_top = previous_path
			control.focus_neighbor_bottom = next_path


func active_scope() -> Node:
	_prune_invalid_frames()
	if _frames.is_empty():
		return null
	return _weak_object(_frames[-1].get("scope")) as Node


func _focus_first_valid(scope_reference: WeakRef, initial_reference: Variant) -> void:
	var scope := _weak_object(scope_reference) as Node
	if scope == null or active_scope() != scope:
		return
	var initial := _weak_object(initial_reference) as Control
	var target: Control = initial if _is_focusable(initial) and _belongs_to_scope(initial, scope) else _first_focusable(scope)
	if target != null:
		target.grab_focus()
	else:
		get_viewport().gui_release_focus()


func _restore_after_close(previous_reference: Variant) -> void:
	var previous := _weak_object(previous_reference) as Control
	var scope := active_scope()
	if _is_focusable(previous) and (scope == null or _belongs_to_scope(previous, scope)):
		previous.grab_focus()
		return
	if scope != null and not _frames.is_empty():
		var initial := _weak_object(_frames[-1].get("initial_focus")) as Control
		_focus_first_valid(weakref(scope), weakref(initial) if initial != null else null)
		return
	get_viewport().gui_release_focus()


func _first_focusable(root: Node) -> Control:
	for child: Node in root.get_children():
		if child is Control and _is_focusable(child):
			return child as Control
		var nested := _first_focusable(child)
		if nested != null:
			return nested
	return null


func _is_focusable(control: Variant) -> bool:
	if not control is Control or not is_instance_valid(control):
		return false
	var typed := control as Control
	if not typed.is_inside_tree() or not typed.is_visible_in_tree():
		return false
	if typed.focus_mode == Control.FOCUS_NONE:
		return false
	if typed is BaseButton and (typed as BaseButton).disabled:
		return false
	return true


func _belongs_to_scope(control: Control, scope: Node) -> bool:
	return control == scope or scope.is_ancestor_of(control)


func _frame_index(scope: Node) -> int:
	if scope == null:
		return -1
	for index: int in range(_frames.size() - 1, -1, -1):
		if _weak_object(_frames[index].get("scope")) == scope:
			return index
	return -1


func _remove_existing_scope(scope: Node) -> void:
	var index := _frame_index(scope)
	if index >= 0:
		_frames.remove_at(index)


func _clear_removed_scope_references(scope: Node, start_index: int) -> void:
	for index: int in range(start_index, _frames.size()):
		var previous := _weak_object(_frames[index].get("previous_owner")) as Control
		if previous != null and _belongs_to_scope(previous, scope):
			_frames[index]["previous_owner"] = null


func _prune_invalid_frames() -> void:
	for index: int in range(_frames.size() - 1, -1, -1):
		if _weak_object(_frames[index].get("scope")) == null:
			_frames.remove_at(index)


func _weak_object(reference: Variant) -> Object:
	if reference == null or not reference is WeakRef:
		return null
	return (reference as WeakRef).get_ref()
