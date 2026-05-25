extends Node

var _restore_scale: float = 1.0
var _pause_token: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func request_hit_pause(duration: float = 0.045, scale: float = 0.12) -> void:
	if duration <= 0.0:
		return
	_pause_token += 1
	var token := _pause_token
	if Engine.time_scale > 0.2:
		_restore_scale = Engine.time_scale
	Engine.time_scale = minf(Engine.time_scale, scale)
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _pause_token:
		Engine.time_scale = _restore_scale
		_restore_scale = 1.0
