class_name ProductionHostileFrameBridge
extends "res://scripts/enemies/launch/hostile_frame_bridge.gd"

var native_boundary_ready: Callable
var _configuring_roster := false


func register_actor(actor: Node2D) -> bool:
	_configuring_roster = true
	var accepted := super.register_actor(actor)
	_configuring_roster = false
	return accepted


func is_ready_for_frame(frame: int) -> bool:
	return (_configuring_roster or not native_boundary_ready.is_valid() or native_boundary_ready.call()) and super.is_ready_for_frame(frame)


func begin_frame(frame: int) -> Dictionary:
	if native_boundary_ready.is_valid() and not native_boundary_ready.call():
		return {}
	return super.begin_frame(frame)
