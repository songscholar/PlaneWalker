extends Node

const PixelProxyScript := preload("res://scripts/presentation/pixel_proxy_actor.gd")
const AudioSynthScript := preload("res://scripts/presentation/combat_audio_synth.gd")
const OverlayScript := preload("res://scripts/presentation/combat_feedback_overlay.gd")
const MAX_TRACKED_WEAPON_CUES := 256
const FEEDBACK_BUDGET_WINDOW_SECONDS := 1.0
const MAX_WEAPON_CUES_PER_WINDOW := 12
const MAX_CAMERA_EVENTS_PER_WINDOW := 8
const MAX_CAMERA_TRAUMA := 8.0
const MAX_SCREEN_FLASHES_PER_WINDOW := 3
const MAX_HIT_PAUSES_PER_WINDOW := 8
const MAX_HIT_AUDIO_CUES_PER_WINDOW := 12
const MAX_ACTIVE_ITEM_CUES_PER_WINDOW := 4
const KNOWN_CHARACTER_IDS: Array[String] = [
	"wanderer",
	"time_guardian",
	"void_walker",
	"primordial_knight",
	"time_lord",
]
const KNOWN_WEAPON_IDS: Array[StringName] = [
	&"sword",
	&"bow",
	&"gun",
	&"staff",
	&"gauntlets",
]
const ACTIVE_ITEM_AUDIO_CUES := {
	"absolute_zero": &"time_stop",
	"paradox_beacon": &"time_rewind",
	"gravity_snare": &"danger_windup",
	"redline_injector": &"dash",
	"blood_price": &"hit_heavy",
	"aegis_reversal": &"gauntlets_counter",
	"railshot": &"gun_aimed_fire",
	"army_of_yesterday": &"time_rewind",
}

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
var _high_contrast_danger: bool = false
var _subtitles_enabled: bool = true
var _subtitle_scale: float = 1.0
var _master_volume: float = 0.85
var _sfx_volume: float = 0.90
var _cached_player: Node2D
var _cached_player_health: HealthComponent
var _played_weapon_cues: Dictionary = {}
var _played_weapon_cue_order: Array[String] = []
var _feedback_budget_elapsed: float = 0.0
var _feedback_budget_window_started_usec: int = 0
var _weapon_cues_accepted: int = 0
var _weapon_cues_rejected: int = 0
var _camera_events_accepted: int = 0
var _camera_events_rejected: int = 0
var _screen_flashes_accepted: int = 0
var _screen_flashes_rejected: int = 0
var _hit_pauses_accepted: int = 0
var _hit_pauses_rejected: int = 0
var _hit_audio_accepted: int = 0
var _hit_audio_rejected: int = 0
var _active_item_cues_accepted: int = 0
var _active_item_cues_rejected: int = 0
var _character_cues_accepted: Dictionary = {}
var _character_cues_rejected: Dictionary = {}
var _character_feedback_snapshot: Dictionary = {}
var _active_item_feedback_snapshot: Dictionary = {}
var _last_character_priority_frame: int = -1


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
	reload_feedback_options_from_game_state()
	if not GameState.setting_changed.is_connected(_on_game_setting_changed):
		GameState.setting_changed.connect(_on_game_setting_changed)
	_connect_event_bus()
	if not get_tree().node_removed.is_connected(_on_tree_node_removed):
		get_tree().node_removed.connect(_on_tree_node_removed)
	call_deferred("_scan_for_actors")


func _process(delta: float) -> void:
	# Poll the monotonic deadline from the always-processing render loop as well as
	# physics. A low Engine.time_scale can delay physics ticks past the real-time
	# deadline, while this check never derives duration from render frame counts.
	_update_hit_pause()
	_update_feedback_budget_window()
	_scan_remaining = maxf(0.0, _scan_remaining - delta)
	if _scan_remaining <= 0.0:
		_scan_remaining = 0.25
		_scan_for_actors()
	_update_low_health_overlay()
	_update_character_priority_feedback()
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
	if _overlay != null and _hit_flash_enabled and _consume_feedback_budget(&"screen_flash"):
		_overlay.show_hit(target_is_player)


func get_overlay_snapshot_for_test() -> Dictionary:
	return _overlay.get_snapshot_for_test() if _overlay != null else {}


func get_camera_feedback_snapshot_for_test() -> Dictionary:
	return {"trauma": _camera_trauma}


func get_feedback_budget_snapshot_for_test() -> Dictionary:
	return {
		"window_seconds": FEEDBACK_BUDGET_WINDOW_SECONDS,
		"window_elapsed": _feedback_budget_elapsed,
		"window_started_usec": _feedback_budget_window_started_usec,
		"weapon_cues_accepted": _weapon_cues_accepted,
		"weapon_cues_rejected": _weapon_cues_rejected,
		"camera_events_accepted": _camera_events_accepted,
		"camera_events_rejected": _camera_events_rejected,
		"screen_flashes_accepted": _screen_flashes_accepted,
		"screen_flashes_rejected": _screen_flashes_rejected,
		"hit_pauses_accepted": _hit_pauses_accepted,
		"hit_pauses_rejected": _hit_pauses_rejected,
		"hit_audio_accepted": _hit_audio_accepted,
		"hit_audio_rejected": _hit_audio_rejected,
		"active_item_cues_accepted": _active_item_cues_accepted,
		"active_item_cues_rejected": _active_item_cues_rejected,
		"character_cues_accepted": _character_cues_accepted.duplicate(true),
		"character_cues_rejected": _character_cues_rejected.duplicate(true),
		"character_profile_limits": _character_profile_limits_snapshot(),
		"max_weapon_cues": MAX_WEAPON_CUES_PER_WINDOW,
		"max_camera_events": MAX_CAMERA_EVENTS_PER_WINDOW,
		"max_camera_trauma": MAX_CAMERA_TRAUMA,
		"max_screen_flashes": MAX_SCREEN_FLASHES_PER_WINDOW,
		"max_hit_pauses": MAX_HIT_PAUSES_PER_WINDOW,
		"max_hit_audio": MAX_HIT_AUDIO_CUES_PER_WINDOW,
		"max_active_item_cues": MAX_ACTIVE_ITEM_CUES_PER_WINDOW,
	}


func get_character_feedback_snapshot_for_test() -> Dictionary:
	return _character_feedback_snapshot.duplicate(true)


func get_active_item_feedback_snapshot_for_test() -> Dictionary:
	return _active_item_feedback_snapshot.duplicate(true)


func present_character_skill_result_for_test(
	actor: Node2D,
	character_id: StringName,
	skill_id: StringName,
	accepted: bool,
	reason: StringName
) -> bool:
	return present_character_skill_result(actor, character_id, skill_id, accepted, reason)


func present_character_skill_result(
	actor: Node2D,
	character_id: StringName,
	skill_id: StringName,
	accepted: bool,
	reason: StringName = &""
) -> bool:
	var character_key := str(character_id)
	var character_profile := PixelProxyScript.character_profile_snapshot(character_id)
	if (
		actor == null
		or not is_instance_valid(actor)
		or character_profile.is_empty()
		or str(character_profile.get("skill_cue_id", "")) != str(skill_id)
		or not _actor_character_matches(actor, character_key)
		or not _consume_character_cue_budget(character_key)
	):
		return false
	var proxy := _ensure_actor_proxy(actor)
	if proxy == null or not proxy.has_method("play_character_cue"):
		return false
	if not bool(proxy.call("play_character_cue", skill_id, accepted)):
		return false
	var audio_intensity := clampf(_master_volume * _sfx_volume, 0.0, 1.0)
	_character_feedback_snapshot = {
		"character_id": character_key,
		"skill_id": str(skill_id),
		"accepted": accepted,
		"reason": str(reason),
		"subtitle_key": (
			"HUD_CHARACTER_SKILL_ACCEPTED"
			if accepted
			else "HUD_CHARACTER_SKILL_REJECTED_%s" % str(reason).to_upper()
		),
		"subtitle_visible": _subtitles_enabled,
		"subtitle_scale": _subtitle_scale,
		"audio_intensity": audio_intensity,
		"high_contrast": _high_contrast_danger,
	}
	if accepted:
		add_camera_trauma(1.0)
	return true


func present_active_item_result_for_test(
	actor: Node2D,
	content_id: StringName,
	handler_id: StringName,
	accepted: bool,
	reason: StringName
) -> bool:
	return present_active_item_result(actor, content_id, handler_id, accepted, reason)


func present_active_item_result(
	actor: Node2D,
	content_id: StringName,
	handler_id: StringName,
	accepted: bool,
	reason: StringName = &""
) -> bool:
	var content_key := str(content_id)
	var handler_key := str(handler_id)
	if (
		actor == null
		or not is_instance_valid(actor)
		or content_key.is_empty()
		or not ACTIVE_ITEM_AUDIO_CUES.has(handler_key)
	):
		return false
	var proxy := _ensure_actor_proxy(actor)
	if proxy == null or not proxy.has_method("play_active_item_cue"):
		return false
	if not _consume_feedback_budget(&"active_item"):
		return false
	if not bool(proxy.call("play_active_item_cue", handler_id, accepted)):
		return false
	var audio_cue: StringName = ACTIVE_ITEM_AUDIO_CUES[handler_key]
	var audio_intensity := clampf(_master_volume * _sfx_volume, 0.0, 1.0)
	if accepted and _audio != null:
		_audio.play_cue(audio_cue, audio_intensity)
	_active_item_feedback_snapshot = {
		"content_id": content_key,
		"handler_id": handler_key,
		"accepted": accepted,
		"reason": str(reason),
		"subtitle_key": "%s_NAME" % content_key.to_upper(),
		"status_key": (
			"HUD_WEAPON_READY"
			if accepted
			else "HUD_WEAPON_COOLDOWN_FMT" if reason == &"cooldown_active" else "HUD_WEAPON_READY"
		),
		"subtitle_visible": _subtitles_enabled,
		"subtitle_scale": _subtitle_scale,
		"audio_cue": str(audio_cue) if accepted else "",
		"audio_intensity": audio_intensity if accepted else 0.0,
		"high_contrast": _high_contrast_danger,
		"reduced_motion": _reduced_motion,
	}
	if accepted:
		add_camera_trauma(2.0)
	return true


func advance_feedback_budget_for_test(delta: float) -> void:
	_advance_feedback_budget(maxf(0.0, delta))


func update_feedback_budget_clock_for_test(now_usec: int) -> void:
	_update_feedback_budget_window(now_usec)


func get_feedback_options_for_test() -> Dictionary:
	return {
		"camera_shake_enabled": _camera_shake_enabled,
		"hit_flash_enabled": _hit_flash_enabled,
		"reduced_motion": _reduced_motion,
		"high_contrast_danger": _high_contrast_danger,
		"subtitles_enabled": _subtitles_enabled,
		"subtitle_scale": _subtitle_scale,
		"master_volume": _master_volume,
		"sfx_volume": _sfx_volume,
	}


func get_actor_cache_snapshot_for_test() -> Dictionary:
	return {
		"player_cached": _cached_player != null and is_instance_valid(_cached_player),
		"health_cached": _cached_player_health != null and is_instance_valid(_cached_player_health),
	}


func reload_feedback_options_from_game_state() -> void:
	set_feedback_options({
		"camera_shake_enabled": bool(GameState.get_setting("camera_shake_enabled", true)),
		"hit_flash_enabled": bool(GameState.get_setting("hit_flash_enabled", true)),
		"reduced_motion": bool(GameState.get_setting("reduced_motion", false)),
		"high_contrast_danger": bool(GameState.get_setting("high_contrast_danger", false)),
		"subtitles_enabled": bool(GameState.get_setting("subtitles_enabled", true)),
		"subtitle_scale": float(GameState.get_setting("subtitle_scale", 1.0)),
		"master_volume": float(GameState.get_setting("master_volume", 0.85)),
		"sfx_volume": float(GameState.get_setting("sfx_volume", 0.90)),
	})


func set_feedback_options(options: Dictionary) -> void:
	if options.has("camera_shake_enabled"):
		_camera_shake_enabled = bool(options["camera_shake_enabled"])
	if options.has("hit_flash_enabled"):
		_hit_flash_enabled = bool(options["hit_flash_enabled"])
	if options.has("reduced_motion"):
		_reduced_motion = bool(options["reduced_motion"])
	if options.has("high_contrast_danger"):
		_high_contrast_danger = bool(options["high_contrast_danger"])
	if options.has("subtitles_enabled"):
		_subtitles_enabled = bool(options["subtitles_enabled"])
	if options.has("subtitle_scale"):
		_subtitle_scale = clampf(float(options["subtitle_scale"]), 0.75, 2.0)
	if options.has("master_volume"):
		_master_volume = clampf(float(options["master_volume"]), 0.0, 1.0)
	if options.has("sfx_volume"):
		_sfx_volume = clampf(float(options["sfx_volume"]), 0.0, 1.0)
	if not _camera_shake_enabled or _reduced_motion:
		_camera_trauma = 0.0
		_restore_camera_offset()
	if _overlay != null and _overlay.has_method("set_feedback_options"):
		_overlay.set_feedback_options(_hit_flash_enabled, _reduced_motion)
	if _overlay != null and _overlay.has_method("set_danger_accessibility"):
		_overlay.set_danger_accessibility(_high_contrast_danger)
	_configure_existing_proxies()


func _on_game_setting_changed(setting_id: StringName, value: Variant) -> void:
	if setting_id not in [&"camera_shake_enabled", &"hit_flash_enabled", &"reduced_motion", &"high_contrast_danger", &"subtitles_enabled", &"subtitle_scale", &"master_volume", &"sfx_volume"]:
		return
	set_feedback_options({str(setting_id): value})


func reset_feedback_for_test() -> void:
	_reset_feedback()
	if _audio != null:
		_audio.clear_history()


func reset_transient_feedback() -> void:
	_reset_feedback()


func _connect_event_bus() -> void:
	if not EventBus.hit_confirmed.is_connected(_on_hit_confirmed):
		EventBus.hit_confirmed.connect(_on_hit_confirmed)
	if not EventBus.weapon_cue_requested.is_connected(_on_weapon_cue_requested):
		EventBus.weapon_cue_requested.connect(_on_weapon_cue_requested)
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
			_cache_player(actor as Node2D)
			_ensure_actor_proxy(actor as Node2D)
	for actor: Node in get_tree().get_nodes_in_group("enemies"):
		if actor is Node2D:
			found_actor = true
			_ensure_actor_proxy(actor as Node2D)
	_had_combat_actor = _had_combat_actor or found_actor


func _ensure_actor_proxy(actor: Node2D) -> Node:
	if actor == null or not is_instance_valid(actor):
		return null
	if actor.has_method("owns_actor_presentation") and actor.owns_actor_presentation():
		return null
	if actor.is_in_group("player"):
		_cache_player(actor)
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
	if _consume_feedback_budget(&"hit_pause"):
		request_hit_pause(float(profile["pause_frames"]) / maxf(1.0, Engine.physics_ticks_per_second))
	add_camera_trauma(float(profile["camera_trauma"]))
	if _audio != null and _consume_feedback_budget(&"hit_audio"):
		_audio.play_cue(profile["audio_cue"])
	if _overlay != null and _hit_flash_enabled and _consume_feedback_budget(&"screen_flash"):
		_overlay.show_hit(target_is_player, float(profile["flash_duration"]))
	if target is Node2D:
		var proxy := _ensure_actor_proxy(target as Node2D)
		if proxy != null:
			proxy.play_action(&"hit")


func _hit_profile(damage_info: Variant, target_is_player: bool) -> Dictionary:
	if target_is_player:
		return (HIT_PROFILES["player_hurt"] as Dictionary).duplicate(true)
	var tags: Array = damage_info.tags if damage_info is DamageInfo else []
	if tags.has("attack:heavy"):
		return (HIT_PROFILES["heavy"] as Dictionary).duplicate(true)
	if tags.has("attack:finisher"):
		return (HIT_PROFILES["finisher"] as Dictionary).duplicate(true)
	if tags.has("weapon:sword") or tags.has("weapon:gauntlets"):
		return (HIT_PROFILES["light"] as Dictionary).duplicate(true)
	return (HIT_PROFILES["generic"] as Dictionary).duplicate(true)


func _on_weapon_cue_requested(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	cue: Dictionary
) -> void:
	var cue_id := StringName(str(cue.get("cue_id", "")))
	if (
		weapon_id not in KNOWN_WEAPON_IDS
		or action_id == &""
		or token <= 0
		or cue_id == &""
	):
		return
	var deduplication_key := "%s|%s|%d|%s" % [weapon_id, action_id, token, cue_id]
	if _played_weapon_cues.has(deduplication_key):
		return
	_played_weapon_cues[deduplication_key] = true
	_played_weapon_cue_order.append(deduplication_key)
	if _played_weapon_cue_order.size() > MAX_TRACKED_WEAPON_CUES:
		_played_weapon_cues.erase(_played_weapon_cue_order.pop_front())
	if not _consume_feedback_budget(&"weapon_cue"):
		return

	var player := _first_player()
	if player != null:
		var proxy := _ensure_actor_proxy(player)
		if proxy != null:
			var animation_id := StringName(str(cue.get("animation_id", "")))
			var vfx_id := StringName(str(cue.get("vfx_id", "")))
			if proxy.has_method("play_weapon_cue"):
				proxy.play_weapon_cue(animation_id, vfx_id)
			else:
				proxy.play_action(&"attack")
	var audio_id := StringName(str(cue.get("audio_id", "")))
	if _audio != null and audio_id != &"":
		_audio.play_cue(audio_id, 0.8)
	match str(cue.get("camera_id", "")):
		"impact_medium":
			add_camera_trauma(1.0)
		"impact_heavy":
			add_camera_trauma(1.5)
		"impact_ultimate":
			add_camera_trauma(2.0)


func _on_player_dashed(_context: Dictionary) -> void:
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


func _on_time_skill_started(skill_id: StringName, _context: Dictionary) -> void:
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


func _on_time_skill_ended(skill_id: StringName, _context: Dictionary) -> void:
	if _overlay != null:
		_overlay.finish_time_skill(skill_id)


func _on_enemy_spawned(enemy: Node, _context: Dictionary) -> void:
	if enemy is Node2D:
		call_deferred("_ensure_spawned_actor_proxy", weakref(enemy))


func _ensure_spawned_actor_proxy(actor_reference: WeakRef) -> void:
	var actor: Variant = actor_reference.get_ref()
	if actor is Node2D and actor.is_inside_tree() and not actor.is_queued_for_deletion():
		_ensure_actor_proxy(actor)


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


func _on_run_ended(_run_id: String, _result: Dictionary, _revision: int) -> void:
	_reset_feedback()


func _on_tree_node_removed(node: Node) -> void:
	if node == _cached_player or node == _cached_player_health:
		_cached_player = null
		_cached_player_health = null
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
	_cached_player = null
	_cached_player_health = null
	_reset_feedback()


func add_camera_trauma(amount: float) -> void:
	if amount <= 0.0 or not _camera_shake_enabled or _reduced_motion:
		return
	if not _consume_feedback_budget(&"camera"):
		return
	_camera_trauma = minf(MAX_CAMERA_TRAUMA, maxf(_camera_trauma, amount))


func _advance_feedback_budget(delta: float) -> void:
	var base_usec := _feedback_budget_window_started_usec
	if base_usec <= 0:
		base_usec = Time.get_ticks_usec()
		_feedback_budget_window_started_usec = base_usec
	var simulated_now_usec := base_usec + maxi(
		0,
		roundi((_feedback_budget_elapsed + maxf(0.0, delta)) * 1000000.0)
	)
	_update_feedback_budget_window(simulated_now_usec)


func _update_feedback_budget_window(now_usec: int = -1) -> void:
	var current_usec := Time.get_ticks_usec() if now_usec < 0 else now_usec
	if _feedback_budget_window_started_usec <= 0:
		_feedback_budget_window_started_usec = current_usec
		_feedback_budget_elapsed = 0.0
		return
	var elapsed_usec := maxi(0, current_usec - _feedback_budget_window_started_usec)
	var window_usec := maxi(1, roundi(FEEDBACK_BUDGET_WINDOW_SECONDS * 1000000.0))
	_feedback_budget_elapsed = float(elapsed_usec % window_usec) / 1000000.0
	if elapsed_usec < window_usec:
		return
	var completed_windows := floori(float(elapsed_usec) / float(window_usec))
	_feedback_budget_window_started_usec += completed_windows * window_usec
	_reset_feedback_budget_counts()


func _consume_feedback_budget(kind: StringName) -> bool:
	match kind:
		&"weapon_cue":
			if _weapon_cues_accepted >= MAX_WEAPON_CUES_PER_WINDOW:
				_weapon_cues_rejected += 1
				return false
			_weapon_cues_accepted += 1
			return true
		&"camera":
			if _camera_events_accepted >= MAX_CAMERA_EVENTS_PER_WINDOW:
				_camera_events_rejected += 1
				return false
			_camera_events_accepted += 1
			return true
		&"screen_flash":
			if _screen_flashes_accepted >= MAX_SCREEN_FLASHES_PER_WINDOW:
				_screen_flashes_rejected += 1
				return false
			_screen_flashes_accepted += 1
			return true
		&"hit_pause":
			if _hit_pauses_accepted >= MAX_HIT_PAUSES_PER_WINDOW:
				_hit_pauses_rejected += 1
				return false
			_hit_pauses_accepted += 1
			return true
		&"hit_audio":
			if _hit_audio_accepted >= MAX_HIT_AUDIO_CUES_PER_WINDOW:
				_hit_audio_rejected += 1
				return false
			_hit_audio_accepted += 1
			return true
		&"active_item":
			if _active_item_cues_accepted >= MAX_ACTIVE_ITEM_CUES_PER_WINDOW:
				_active_item_cues_rejected += 1
				return false
			_active_item_cues_accepted += 1
			return true
	return false


func _reset_feedback_budget_counts() -> void:
	_weapon_cues_accepted = 0
	_weapon_cues_rejected = 0
	_camera_events_accepted = 0
	_camera_events_rejected = 0
	_screen_flashes_accepted = 0
	_screen_flashes_rejected = 0
	_hit_pauses_accepted = 0
	_hit_pauses_rejected = 0
	_hit_audio_accepted = 0
	_hit_audio_rejected = 0
	_active_item_cues_accepted = 0
	_active_item_cues_rejected = 0
	_character_cues_accepted.clear()
	_character_cues_rejected.clear()
	for character_id: String in KNOWN_CHARACTER_IDS:
		_character_cues_accepted[character_id] = 0
		_character_cues_rejected[character_id] = 0


func _consume_character_cue_budget(character_id: String) -> bool:
	var accepted := int(_character_cues_accepted.get(character_id, 0))
	var limit := int(PixelProxyScript.character_profile_snapshot(StringName(character_id)).get("cue_budget", 0))
	if limit <= 0 or accepted >= limit:
		_character_cues_rejected[character_id] = int(_character_cues_rejected.get(character_id, 0)) + 1
		return false
	_character_cues_accepted[character_id] = accepted + 1
	return true


func _character_profile_limits_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for character_id: String in KNOWN_CHARACTER_IDS:
		result[character_id] = int(PixelProxyScript.character_profile_snapshot(StringName(character_id)).get("cue_budget", 0))
	return result


func _actor_character_matches(actor: Node, expected_character_id: String) -> bool:
	if not actor.has_method("character_presentation_snapshot"):
		return false
	var value: Variant = actor.call("character_presentation_snapshot")
	return value is Dictionary and str((value as Dictionary).get("runtime_kind", "")) == expected_character_id


func _update_character_priority_feedback() -> void:
	var player := _first_player()
	if player == null or not player.has_method("priority_arbitration_snapshot"):
		return
	var arbitration_value: Variant = player.call("priority_arbitration_snapshot")
	if not arbitration_value is Dictionary:
		return
	var arbitration := arbitration_value as Dictionary
	var frame := int(arbitration.get("frame", -1))
	var decisions_value: Variant = arbitration.get("decisions", [])
	if frame < 0 or not decisions_value is Array:
		return
	if frame == _last_character_priority_frame:
		return
	_last_character_priority_frame = frame
	for index: int in range((decisions_value as Array).size()):
		var decision_value: Variant = (decisions_value as Array)[index]
		if not decision_value is Dictionary:
			continue
		var decision := decision_value as Dictionary
		if str(decision.get("category", "")) != "character" or str(decision.get("edge", "")) != "pressed":
			continue
		var presentation_value: Variant = player.call("character_presentation_snapshot") if player.has_method("character_presentation_snapshot") else {}
		if not presentation_value is Dictionary:
			return
		var character_id := StringName(str((presentation_value as Dictionary).get("runtime_kind", "")))
		var skill_id := StringName(str(PixelProxyScript.character_profile_snapshot(character_id).get("skill_cue_id", "")))
		var status := str(decision.get("status", "rejected"))
		present_character_skill_result(
			player,
			character_id,
			skill_id,
			status == "accepted",
			&"" if status == "accepted" else StringName(status)
		)


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
	var health := _cached_player_health
	if health == null or not is_instance_valid(health):
		_overlay.set_low_health_ratio(1.0)
		return
	_overlay.set_low_health_ratio(float(health.current_hp) / maxf(1.0, float(health.max_hp)))


func _first_player() -> Node2D:
	if not is_inside_tree():
		return null
	if _cached_player != null and is_instance_valid(_cached_player):
		return _cached_player
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		_cache_player(player)
	return player


func _reset_feedback() -> void:
	_pause_token += 1
	_pause_started_usec = 0
	_pause_deadline_usec = 0
	if Engine.time_scale < 1.0 or _restore_scale != 1.0:
		Engine.time_scale = _restore_scale
	_restore_scale = 1.0
	_camera_trauma = 0.0
	_feedback_budget_elapsed = 0.0
	_feedback_budget_window_started_usec = Time.get_ticks_usec()
	_reset_feedback_budget_counts()
	_played_weapon_cues.clear()
	_played_weapon_cue_order.clear()
	_character_feedback_snapshot.clear()
	_active_item_feedback_snapshot.clear()
	_last_character_priority_frame = -1
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
	_played_weapon_cues.clear()
	_played_weapon_cue_order.clear()
	_restore_camera_offset()
	if _audio != null and is_instance_valid(_audio) and _audio.has_method("stop_all"):
		_audio.stop_all()


func _restore_camera_offset() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.offset = _camera_base_offset
	_camera = null
	_camera_base_offset = Vector2.ZERO


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
	if proxy != null and proxy.has_method("set_character_feedback_options"):
		proxy.call("set_character_feedback_options", _high_contrast_danger)


func _cache_player(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	_cached_player = player
	_cached_player_health = player.get_node_or_null("HealthComponent") as HealthComponent
