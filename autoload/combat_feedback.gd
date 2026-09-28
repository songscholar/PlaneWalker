extends Node

const PixelProxyScript := preload("res://scripts/presentation/pixel_proxy_actor.gd")
const AudioSynthScript := preload("res://scripts/presentation/combat_audio_synth.gd")
const OverlayScript := preload("res://scripts/presentation/combat_feedback_overlay.gd")

var _restore_scale: float = 1.0
var _pause_token: int = 0
var _pause_started_usec: int = 0
var _pause_deadline_usec: int = 0
var _scan_remaining: float = 0.0
var _audio: Node
var _overlay: Control
var _overlay_layer: CanvasLayer
var _camera: Camera2D
var _camera_base_offset := Vector2.ZERO
var _camera_trauma: float = 0.0
var _camera_clock: float = 0.0
var _had_combat_actor: bool = false
var _camera_shake_enabled: bool = true
var _hit_flash_enabled: bool = true
var _reduced_motion: bool = false


const HIT_PROFILES := {
	"light": {
		"pause_frames": 3,
		"camera_trauma": 3.0,
		"audio_cue": &"hit_light",
		"flash_duration": 0.10,
	},
	"finisher": {
		"pause_frames": 5,
		"camera_trauma": 6.0,
		"audio_cue": &"hit_finisher",
		"flash_duration": 0.14,
	},
	"heavy": {
		"pause_frames": 6,
		"camera_trauma": 8.0,
		"audio_cue": &"hit_heavy",
		"flash_duration": 0.18,
	},
	"player_hurt": {
		"pause_frames": 2,
		"camera_trauma": 8.0,
		"audio_cue": &"player_hurt",
		"flash_duration": 0.20,
	},
	"generic": {
		"pause_frames": 2,
		"camera_trauma": 2.0,
		"audio_cue": &"hit_light",
		"flash_duration": 0.08,
	},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audio = AudioSynthScript.new()
	_audio.name = "CombatAudioSynth"
	add_child(_audio)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "CombatFeedbackLayer"
	_overlay_layer.layer = 90
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay_layer)
	_overlay = OverlayScript.new()
	_overlay.name = "CombatFeedbackOverlay"
	_overlay_layer.add_child(_overlay)
	_connect_event_bus()
	if not get_tree().node_removed.is_connected(_on_tree_node_removed):
		get_tree().node_removed.connect(_on_tree_node_removed)
	call_deferred("_scan_for_actors")


func _process(delta: float) -> void:
	_scan_remaining = maxf(0.0, _scan_remaining - delta)
	if _scan_remaining <= 0.0:
		_scan_remaining = 0.25
		_scan_for_actors()
	_update_low_health_overlay()
	_update_camera_feedback(delta)


func _physics_process(_delta: float) -> void:
	_update_hit_pause()


func request_hit_pause(duration: float = 0.045, scale: float = 0.12) -> void:
	if duration <= 0.0:
		return
	var now_usec := Time.get_ticks_usec()
	if _pause_deadline_usec > 0 and now_usec >= _pause_deadline_usec:
		_update_hit_pause(now_usec)
	var requested_deadline := now_usec + maxi(1, ceili(duration * 1000000.0))
	var was_inactive := _pause_deadline_usec <= now_usec
	_pause_deadline_usec = maxi(_pause_deadline_usec, requested_deadline)
	_pause_token += 1
	if was_inactive:
		_pause_started_usec = now_usec
		_restore_scale = Engine.time_scale
	Engine.time_scale = minf(Engine.time_scale, scale)


func _update_hit_pause(now_usec: int = -1) -> void:
	if _pause_deadline_usec <= 0:
		return
	var current_usec := Time.get_ticks_usec() if now_usec < 0 else now_usec
	if current_usec < _pause_deadline_usec:
		return
	Engine.time_scale = _restore_scale
	_restore_scale = 1.0
	_pause_started_usec = 0
	_pause_deadline_usec = 0


func get_hit_pause_snapshot_for_test() -> Dictionary:
	return {
		"active": _pause_deadline_usec > 0,
		"started_usec": _pause_started_usec,
		"deadline_usec": _pause_deadline_usec,
	}


func update_hit_pause_for_test(now_usec: int) -> void:
	_update_hit_pause(now_usec)


func ensure_actor_proxy_for_test(actor: Node2D) -> Node:
	return _ensure_actor_proxy(actor)


func get_hit_profile_for_test(damage_info: Variant, target_is_player: bool) -> Dictionary:
	return _hit_profile(damage_info, target_is_player)


func get_audio_contract_for_test() -> Dictionary:
	return _audio.get_contract_snapshot() if _audio != null else {}


func play_audio_cue_for_test(cue_id: StringName) -> bool:
	return bool(_audio.play_cue(cue_id)) if _audio != null else false


func preview_time_feedback_for_test(skill_id: StringName) -> void:
	if _overlay != null:
		_overlay.show_time_skill(skill_id)


func preview_hit_feedback_for_test(target_is_player: bool) -> void:
	if _overlay != null and _hit_flash_enabled:
		_overlay.show_hit(target_is_player)


func get_overlay_snapshot_for_test() -> Dictionary:
	return _overlay.get_snapshot_for_test() if _overlay != null else {}


func get_camera_feedback_snapshot_for_test() -> Dictionary:
	return {"trauma": _camera_trauma}


func set_feedback_options(options: Dictionary) -> void:
	if options.has("camera_shake_enabled"):
		_camera_shake_enabled = bool(options["camera_shake_enabled"])
	if options.has("hit_flash_enabled"):
		_hit_flash_enabled = bool(options["hit_flash_enabled"])
	if options.has("reduced_motion"):
		_reduced_motion = bool(options["reduced_motion"])
	if not _camera_shake_enabled or _reduced_motion:
		_camera_trauma = 0.0
		_restore_camera_offset()
	if _overlay != null and _overlay.has_method("set_feedback_options"):
		_overlay.set_feedback_options(_hit_flash_enabled, _reduced_motion)
	_configure_existing_proxies()


func reset_feedback_for_test() -> void:
	_reset_feedback()
	if _audio != null:
		_audio.clear_history()


func reset_transient_feedback() -> void:
	_reset_feedback()


func _connect_event_bus() -> void:
	if not EventBus.hit_confirmed.is_connected(_on_hit_confirmed):
		EventBus.hit_confirmed.connect(_on_hit_confirmed)
	if not EventBus.player_attacked.is_connected(_on_player_attacked):
		EventBus.player_attacked.connect(_on_player_attacked)
	if not EventBus.player_dashed.is_connected(_on_player_dashed):
		EventBus.player_dashed.connect(_on_player_dashed)
	if not EventBus.time_skill_started.is_connected(_on_time_skill_started):
		EventBus.time_skill_started.connect(_on_time_skill_started)
	if not EventBus.time_skill_ended.is_connected(_on_time_skill_ended):
		EventBus.time_skill_ended.connect(_on_time_skill_ended)
	if not EventBus.enemy_spawned.is_connected(_on_enemy_spawned):
		EventBus.enemy_spawned.connect(_on_enemy_spawned)
	if not EventBus.run_ended.is_connected(_on_run_ended):
		EventBus.run_ended.connect(_on_run_ended)


func _scan_for_actors() -> void:
	if not is_inside_tree():
		return
	var found_actor := false
	for actor: Node in get_tree().get_nodes_in_group("player"):
		if actor is Node2D:
			found_actor = true
			_ensure_actor_proxy(actor as Node2D)
	for actor: Node in get_tree().get_nodes_in_group("enemies"):
		if actor is Node2D:
			found_actor = true
			_ensure_actor_proxy(actor as Node2D)
	_had_combat_actor = _had_combat_actor or found_actor


func _ensure_actor_proxy(actor: Node2D) -> Node:
	if actor == null or not is_instance_valid(actor):
		return null
	var existing := actor.get_node_or_null("PixelProxyActor")
	if existing != null:
		return existing
	if actor.get_node_or_null("Visual") == null:
		return null
	var proxy := PixelProxyScript.new()
	proxy.name = "PixelProxyActor"
	actor.add_child(proxy)
	if not proxy.bind_actor(actor):
		proxy.queue_free()
		return null
	_configure_proxy(proxy)
	proxy.cue_requested.connect(_on_proxy_cue_requested)
	var time_manager := actor.get_node_or_null("TimeManager")
	if time_manager != null and time_manager.has_signal("rewind_committed"):
		var callback := _on_rewind_committed.bind(actor)
		if not time_manager.rewind_committed.is_connected(callback):
			time_manager.rewind_committed.connect(callback)
	return proxy


func _on_hit_confirmed(damage_info: Variant, target: Node, final_amount: float) -> void:
	if final_amount <= 0.0 or target == null or not is_instance_valid(target):
		return
	var target_is_player := target.is_in_group("player")
	var profile := _hit_profile(damage_info, target_is_player)
	request_hit_pause(float(profile["pause_frames"]) / maxf(1.0, Engine.physics_ticks_per_second))
	add_camera_trauma(float(profile["camera_trauma"]))
	if _audio != null:
		_audio.play_cue(profile["audio_cue"])
	if _overlay != null and _hit_flash_enabled:
		_overlay.show_hit(target_is_player, float(profile["flash_duration"]))
	if target is Node2D:
		var proxy := _ensure_actor_proxy(target as Node2D)
		if proxy != null:
			proxy.play_action(&"hit")


func _hit_profile(damage_info: Variant, target_is_player: bool) -> Dictionary:
	if target_is_player:
		return (HIT_PROFILES["player_hurt"] as Dictionary).duplicate(true)
	var tags: Array = damage_info.tags if damage_info != null and _has_property(damage_info, &"tags") else []
	if tags.has("attack:heavy"):
		return (HIT_PROFILES["heavy"] as Dictionary).duplicate(true)
	if tags.has("attack:finisher"):
		return (HIT_PROFILES["finisher"] as Dictionary).duplicate(true)
	if tags.has("weapon:sword"):
		return (HIT_PROFILES["light"] as Dictionary).duplicate(true)
	return (HIT_PROFILES["generic"] as Dictionary).duplicate(true)


func _on_player_attacked(_weapon_id: StringName) -> void:
	var player := _first_player()
	if player == null:
		return
	var proxy := _ensure_actor_proxy(player)
	if proxy != null:
		proxy.play_action(&"attack")
	if _audio != null:
		_audio.play_cue(&"sword_swing", 0.8)


func _on_player_dashed() -> void:
	var player := _first_player()
	if player == null:
		return
	var proxy := _ensure_actor_proxy(player)
	if proxy != null:
		proxy.play_action(&"dash")
		proxy.spawn_afterimage(player.global_position, 0.20)
	if _audio != null:
		_audio.play_cue(&"dash", 0.7)
	add_camera_trauma(1.0)


func _on_time_skill_started(skill_id: StringName) -> void:
	var player := _first_player()
	if player != null:
		var proxy := _ensure_actor_proxy(player)
		if proxy != null:
			proxy.play_action(skill_id)
	if _audio != null and skill_id in [&"time_stop", &"time_rewind"]:
		_audio.play_cue(skill_id, 0.9)
	if _overlay != null:
		_overlay.show_time_skill(skill_id, 0.65 if skill_id == &"time_stop" else 0.48)
	add_camera_trauma(2.0 if skill_id == &"time_stop" else 3.0)


func _on_time_skill_ended(skill_id: StringName) -> void:
	if _overlay != null:
		_overlay.finish_time_skill(skill_id)


func _on_enemy_spawned(enemy: Node) -> void:
	if enemy is Node2D:
		call_deferred("_ensure_actor_proxy", enemy as Node2D)


func _on_proxy_cue_requested(cue_id: StringName, _world_position: Vector2, intensity: float) -> void:
	if _audio != null:
		_audio.play_cue(cue_id, intensity)
	if cue_id in [&"boss_windup_low", &"boss_windup_high", &"boss_windup_void"]:
		add_camera_trauma(1.5)


func _on_rewind_committed(transaction: Dictionary, actor: Node2D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var proxy := _ensure_actor_proxy(actor)
	if proxy == null:
		return
	var raw_path: Variant = transaction.get("path_samples", [])
	if not raw_path is Array:
		return
	var samples: Array = raw_path
	if samples.is_empty():
		return
	var stride := maxi(1, ceili(float(samples.size()) / 6.0))
	for index: int in range(0, samples.size(), stride):
		if samples[index] is Vector2:
			proxy.spawn_afterimage(samples[index], 0.34)


func _on_run_ended(_result: Dictionary) -> void:
	_reset_feedback()


func _on_tree_node_removed(_node: Node) -> void:
	if _had_combat_actor:
		call_deferred("_cleanup_if_no_combat_actors")


func _cleanup_if_no_combat_actors() -> void:
	if not is_inside_tree():
		return
	if not get_tree().get_nodes_in_group("player").is_empty():
		return
	if not get_tree().get_nodes_in_group("enemies").is_empty():
		return
	_had_combat_actor = false
	_reset_feedback()


func add_camera_trauma(amount: float) -> void:
	if not _camera_shake_enabled or _reduced_motion:
		return
	_camera_trauma = maxf(_camera_trauma, maxf(0.0, amount))


func _update_camera_feedback(delta: float) -> void:
	_camera_clock += delta
	if not _camera_shake_enabled or _reduced_motion:
		_camera_trauma = 0.0
		_restore_camera_offset()
		return
	var active_camera := get_viewport().get_camera_2d()
	if active_camera != _camera:
		_restore_camera_offset()
		_camera = active_camera
		_camera_base_offset = _camera.offset if _camera != null else Vector2.ZERO
	if _camera == null or not is_instance_valid(_camera):
		_camera = null
		_camera_trauma = maxf(0.0, _camera_trauma - delta * 18.0)
		return
	_camera_trauma = maxf(0.0, _camera_trauma - delta * 18.0)
	if _camera_trauma <= 0.01:
		_camera.offset = _camera_base_offset
		return
	var amplitude := minf(10.0, _camera_trauma)
	var shake := Vector2(sin(_camera_clock * 83.0), cos(_camera_clock * 71.0)) * amplitude
	_camera.offset = _camera_base_offset + Vector2(roundf(shake.x), roundf(shake.y))


func _update_low_health_overlay() -> void:
	if _overlay == null:
		return
	var player := _first_player()
	if player == null:
		_overlay.set_low_health_ratio(1.0)
		return
	var health := player.get_node_or_null("HealthComponent")
	if health == null or not _has_property(health, &"current_hp") or not _has_property(health, &"max_hp"):
		_overlay.set_low_health_ratio(1.0)
		return
	_overlay.set_low_health_ratio(float(health.current_hp) / maxf(1.0, float(health.max_hp)))


func _first_player() -> Node2D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as Node2D


func _reset_feedback() -> void:
	_pause_token += 1
	_pause_started_usec = 0
	_pause_deadline_usec = 0
	if Engine.time_scale < 1.0 or _restore_scale != 1.0:
		Engine.time_scale = _restore_scale
	_restore_scale = 1.0
	_camera_trauma = 0.0
	_restore_camera_offset()
	if _audio != null and _audio.has_method("stop_all"):
		_audio.stop_all()
	if _overlay != null:
		_overlay.clear_feedback()


func _exit_tree() -> void:
	_pause_token += 1
	_pause_started_usec = 0
	_pause_deadline_usec = 0
	Engine.time_scale = _restore_scale
	_restore_scale = 1.0
	_restore_camera_offset()
	if _audio != null and is_instance_valid(_audio) and _audio.has_method("stop_all"):
		_audio.stop_all()


func _restore_camera_offset() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = _camera_base_offset
	_camera = null
	_camera_base_offset = Vector2.ZERO


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _configure_existing_proxies() -> void:
	if not is_inside_tree():
		return
	for actor: Node in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemies"):
		var proxy := actor.get_node_or_null("PixelProxyActor")
		if proxy != null:
			_configure_proxy(proxy)


func _configure_proxy(proxy: Node) -> void:
	if proxy != null and proxy.has_method("set_feedback_options"):
		proxy.set_feedback_options(_hit_flash_enabled, _reduced_motion)
