class_name PixelProxyActor
extends Node2D

signal cue_requested(cue_id: StringName, world_position: Vector2, intensity: float)

const AfterimageScript := preload("res://scripts/presentation/pixel_proxy_afterimage.gd")
const PIXEL_UNIT := 2

const PALETTES := {
	"player": {
		"id": "wanderer_cyan",
		"primary": Color(0.08, 0.72, 0.86),
		"secondary": Color(0.035, 0.12, 0.18),
		"accent": Color(0.82, 0.98, 1.0),
		"danger": Color(1.0, 0.32, 0.22),
	},
	"chaser": {
		"id": "chaser_red",
		"primary": Color(0.86, 0.14, 0.16),
		"secondary": Color(0.22, 0.025, 0.035),
		"accent": Color(1.0, 0.64, 0.32),
		"danger": Color(1.0, 0.9, 0.58),
	},
	"shooter": {
		"id": "shooter_amber",
		"primary": Color(0.94, 0.46, 0.08),
		"secondary": Color(0.22, 0.07, 0.015),
		"accent": Color(1.0, 0.9, 0.34),
		"danger": Color(1.0, 0.3, 0.12),
	},
	"tank": {
		"id": "tank_violet",
		"primary": Color(0.54, 0.22, 0.82),
		"secondary": Color(0.11, 0.025, 0.18),
		"accent": Color(0.92, 0.68, 1.0),
		"danger": Color(1.0, 0.78, 0.12),
	},
	"boss": {
		"id": "warden_magenta",
		"primary": Color(0.86, 0.06, 0.3),
		"secondary": Color(0.13, 0.015, 0.09),
		"accent": Color(0.24, 0.9, 1.0),
		"danger": Color(1.0, 0.7, 0.18),
	},
	"generic": {
		"id": "generic_proxy",
		"primary": Color(0.64, 0.7, 0.76),
		"secondary": Color(0.08, 0.1, 0.13),
		"accent": Color(0.9, 0.96, 1.0),
		"danger": Color(1.0, 0.45, 0.2),
	},
}

const FOOTPRINTS := {
	"player": Vector2i(24, 32),
	"chaser": Vector2i(26, 24),
	"shooter": Vector2i(24, 28),
	"tank": Vector2i(36, 36),
	"boss": Vector2i(56, 62),
	"generic": Vector2i(24, 24),
}

const ACTION_DURATIONS := {
	&"attack": 0.20,
	&"dash": 0.22,
	&"cast": 0.28,
	&"time_stop": 0.34,
	&"time_rewind": 0.40,
	&"hit": 0.12,
	&"heal": 0.26,
	&"death": 0.45,
	&"windup": 0.46,
	&"recovery": 0.28,
}

var _actor: Node2D
var _source_visual: CanvasItem
var _role: String = "generic"
var _palette: Dictionary = PALETTES["generic"]
var _footprint := Vector2i(24, 24)
var _state: StringName = &"idle"
var _action_remaining: float = 0.0
var _phase_clock: float = 0.0
var _flash_remaining: float = 0.0
var _bound: bool = false
var _last_boss_action: String = "NONE"
var _last_boss_phase: String = "IDLE"
var _afterimage_count: int = 0


func bind_actor(actor: Node2D) -> bool:
	if _bound:
		return actor == _actor
	if actor == null or not is_instance_valid(actor):
		return false
	var visual := actor.get_node_or_null("Visual") as CanvasItem
	if visual == null:
		return false
	_actor = actor
	_source_visual = visual
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_source_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_role = _resolve_role(actor)
	_palette = (PALETTES.get(_role, PALETTES["generic"]) as Dictionary).duplicate(true)
	_footprint = FOOTPRINTS.get(_role, FOOTPRINTS["generic"])
	_source_visual.visible = false
	z_index = 4
	_bound = true

	var health := actor.get_node_or_null("HealthComponent")
	if health != null:
		if health.has_signal("damaged") and not health.damaged.is_connected(_on_damaged):
			health.damaged.connect(_on_damaged)
		if health.has_signal("healed") and not health.healed.is_connected(_on_healed):
			health.healed.connect(_on_healed)
		if health.has_signal("died") and not health.died.is_connected(_on_died):
			health.died.connect(_on_died)
	if actor.has_signal("attack_phase_changed") and not actor.attack_phase_changed.is_connected(_on_attack_phase_changed):
		actor.attack_phase_changed.connect(_on_attack_phase_changed)
	queue_redraw()
	return true


func play_action(action_id: StringName, duration: float = -1.0) -> void:
	var normalized := action_id
	if action_id in [&"time_stop", &"time_rewind"]:
		normalized = action_id
	elif action_id == &"time_cast":
		normalized = &"cast"
	if normalized == &"death":
		_state = normalized
		_action_remaining = ACTION_DURATIONS[&"death"] if duration <= 0.0 else duration
	elif _state != &"death":
		_state = normalized
		_action_remaining = float(ACTION_DURATIONS.get(normalized, 0.2)) if duration <= 0.0 else duration
	if normalized == &"hit":
		_flash_remaining = maxf(_flash_remaining, 0.10)
	queue_redraw()


func spawn_afterimage(world_position: Vector2, lifetime: float = 0.22) -> Node2D:
	if _actor == null or not is_instance_valid(_actor) or _actor.get_parent() == null:
		return null
	var afterimage := AfterimageScript.new()
	_actor.get_parent().add_child(afterimage)
	afterimage.global_position = Vector2(roundf(world_position.x), roundf(world_position.y))
	afterimage.z_index = maxi(0, _actor.z_index - 1)
	afterimage.configure(
		_role,
		_palette["primary"],
		_palette["accent"],
		_footprint,
		lifetime
	)
	_afterimage_count += 1
	return afterimage


func advance_animation_for_test(delta: float) -> void:
	_advance_animation(maxf(0.0, delta))


func get_snapshot_for_test() -> Dictionary:
	return {
		"role": _role,
		"palette_id": str(_palette.get("id", "")),
		"pixel_unit": PIXEL_UNIT,
		"texture_filter": texture_filter,
		"footprint": _footprint,
		"state": str(_state),
		"position": position,
		"pixel_snapped": is_equal_approx(fmod(absf(position.x), PIXEL_UNIT), 0.0)
			and is_equal_approx(fmod(absf(position.y), PIXEL_UNIT), 0.0),
		"afterimage_count": _afterimage_count,
	}


func _process(delta: float) -> void:
	if not _bound or _actor == null or not is_instance_valid(_actor):
		return
	_advance_animation(delta)


func _advance_animation(delta: float) -> void:
	_phase_clock += delta
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	if _action_remaining > 0.0:
		_action_remaining = maxf(0.0, _action_remaining - delta)
	elif _state != &"death":
		_derive_state_from_actor()
	_update_boss_presentation_state()
	_apply_pixel_transform()
	queue_redraw()


func _derive_state_from_actor() -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	if _role == "player" and _actor.has_method("get_player_ui_snapshot"):
		var snapshot: Dictionary = _actor.get_player_ui_snapshot()
		match str(snapshot.get("action_state", "FREE")):
			"ATTACK_WINDUP", "ATTACK_ACTIVE", "ATTACK_RECOVERY":
				_state = &"attack"
				return
			"DASH":
				_state = &"dash"
				return
			"TIME_CAST":
				_state = &"cast"
				return
			"HITSTUN":
				_state = &"hit"
				return
			"DEAD":
				_state = &"death"
				return
	if _has_property(_actor, &"velocity") and (_actor.get("velocity") as Vector2).length_squared() > 64.0:
		_state = &"move"
	else:
		_state = &"idle"


func _update_boss_presentation_state() -> void:
	if _role != "boss" or _actor == null or not _actor.has_method("get_boss_ui_snapshot"):
		return
	var snapshot: Dictionary = _actor.get_boss_ui_snapshot()
	var action := str(snapshot.get("action", "NONE"))
	var phase := str(snapshot.get("phase", "IDLE"))
	if phase == _last_boss_phase and action == _last_boss_action:
		return
	_last_boss_phase = phase
	_last_boss_action = action
	if phase == "WINDUP":
		play_action(&"windup", maxf(0.1, float(snapshot.get("remaining", 0.4))))
		cue_requested.emit(_boss_windup_cue(action), _actor.global_position, 1.0)
	elif phase == "RECOVERY":
		play_action(&"recovery", maxf(0.1, float(snapshot.get("remaining", 0.25))))


func _apply_pixel_transform() -> void:
	var offset := Vector2.ZERO
	var target_scale := Vector2.ONE
	match _state:
		&"idle":
			offset.y = sin(_phase_clock * 5.0) * 1.4
		&"move":
			offset.y = -absf(sin(_phase_clock * 12.0)) * 2.0
			target_scale = Vector2(1.04, 0.96)
		&"attack":
			offset.x = 2.0
			target_scale = Vector2(1.08, 0.94)
		&"dash":
			offset.x = 4.0
			target_scale = Vector2(1.16, 0.86)
		&"cast", &"time_stop", &"time_rewind":
			offset.y = -2.0
			target_scale = Vector2(0.96, 1.08)
		&"windup":
			offset.y = 2.0
			target_scale = Vector2(1.08, 0.9)
		&"recovery":
			target_scale = Vector2(0.94, 1.04)
		&"hit":
			offset.x = -2.0 if int(_phase_clock * 60.0) % 2 == 0 else 2.0
		&"death":
			offset.y = 4.0
			target_scale = Vector2(1.08, 0.72)
	position = Vector2(snappedf(offset.x, PIXEL_UNIT), snappedf(offset.y, PIXEL_UNIT))
	scale = target_scale


func _draw() -> void:
	if not _bound:
		return
	var primary: Color = _palette["primary"]
	var secondary: Color = _palette["secondary"]
	var accent: Color = _palette["accent"]
	if _flash_remaining > 0.0:
		primary = Color.WHITE
		accent = Color(1.0, 0.92, 0.62)
	_draw_shadow()
	match _role:
		"player":
			_draw_player(primary, secondary, accent)
		"chaser":
			_draw_chaser(primary, secondary, accent)
		"shooter":
			_draw_shooter(primary, secondary, accent)
		"tank":
			_draw_tank(primary, secondary, accent)
		"boss":
			_draw_boss(primary, secondary, accent)
		_:
			_draw_generic(primary, secondary, accent)
	if _state in [&"cast", &"time_stop", &"time_rewind"]:
		_draw_time_cast(accent)
	if _state == &"windup":
		_draw_danger_crown(_palette["danger"])


func _draw_shadow() -> void:
	var width := float(_footprint.x - 4)
	var y := float(_footprint.y) * 0.45
	draw_rect(Rect2(Vector2(-width * 0.5, y), Vector2(width, 4)), Color(0.0, 0.0, 0.0, 0.45), true)


func _draw_player(primary: Color, secondary: Color, accent: Color) -> void:
	draw_rect(Rect2(-10, -10, 20, 24), secondary, true)
	draw_rect(Rect2(-8, -14, 16, 12), primary, true)
	draw_rect(Rect2(-4, -12, 8, 6), accent, true)
	draw_rect(Rect2(-12, 0, 4, 12), primary.darkened(0.2), true)
	draw_rect(Rect2(8, 0, 4, 12), primary.darkened(0.2), true)
	if _state == &"attack":
		draw_rect(Rect2(10, -4, 18, 4), accent, true)
		draw_rect(Rect2(24, -8, 4, 12), Color.WHITE, true)
	else:
		draw_rect(Rect2(10, 2, 14, 4), accent.darkened(0.15), true)


func _draw_chaser(primary: Color, secondary: Color, accent: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(14, 0), Vector2(-4, -12), Vector2(-14, 0), Vector2(-4, 12)]), secondary)
	draw_colored_polygon(PackedVector2Array([Vector2(12, 0), Vector2(-2, -8), Vector2(-10, 0), Vector2(-2, 8)]), primary)
	draw_rect(Rect2(2, -2, 8, 4), accent, true)


func _draw_shooter(primary: Color, secondary: Color, accent: Color) -> void:
	draw_rect(Rect2(-10, -12, 20, 24), secondary, true)
	draw_rect(Rect2(-8, -10, 8, 20), primary, true)
	draw_rect(Rect2(2, -8, 8, 16), primary.lightened(0.12), true)
	draw_rect(Rect2(8, -2, 10, 4), accent, true)
	draw_rect(Rect2(-4, -4, 6, 8), accent.darkened(0.15), true)


func _draw_tank(primary: Color, secondary: Color, accent: Color) -> void:
	draw_rect(Rect2(-18, -16, 36, 32), secondary, true)
	draw_rect(Rect2(-14, -14, 28, 28), primary, true)
	draw_rect(Rect2(-10, -10, 20, 20), primary.lightened(0.12), false, 4.0)
	draw_rect(Rect2(-4, -4, 8, 8), accent, true)
	if _is_elite_actor():
		draw_rect(Rect2(-12, -22, 24, 4), _palette["danger"], true)
		draw_rect(Rect2(-16, -18, 4, 4), _palette["danger"], true)
		draw_rect(Rect2(12, -18, 4, 4), _palette["danger"], true)


func _draw_boss(primary: Color, secondary: Color, accent: Color) -> void:
	draw_rect(Rect2(-24, -28, 48, 54), secondary, true)
	draw_rect(Rect2(-20, -24, 40, 46), primary, true)
	draw_rect(Rect2(-14, -18, 28, 28), secondary, true)
	draw_rect(Rect2(-10, -14, 20, 20), primary.lightened(0.1), true)
	draw_rect(Rect2(-2, -12, 4, 12), accent, true)
	draw_rect(Rect2(0, -2, 10, 4), accent, true)
	draw_rect(Rect2(-28, -12, 6, 30), primary.darkened(0.1), true)
	draw_rect(Rect2(22, -12, 6, 30), primary.darkened(0.1), true)
	draw_rect(Rect2(-8, 22, 16, 8), accent.darkened(0.3), true)


func _draw_generic(primary: Color, secondary: Color, accent: Color) -> void:
	draw_rect(Rect2(-12, -12, 24, 24), secondary, true)
	draw_rect(Rect2(-8, -8, 16, 16), primary, true)
	draw_rect(Rect2(-2, -2, 4, 4), accent, true)


func _draw_time_cast(accent: Color) -> void:
	var pulse := 16.0 + float(int(_phase_clock * 20.0) % 3) * 2.0
	draw_arc(Vector2.ZERO, pulse, 0.0, TAU, 16, accent, 2.0, false)
	for index: int in range(4):
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / 4.0)
		var shard_position := direction * (pulse + 4.0)
		draw_rect(Rect2(shard_position - Vector2(2, 2), Vector2(4, 4)), accent, true)


func _draw_danger_crown(color: Color) -> void:
	var y := -float(_footprint.y) * 0.6
	draw_rect(Rect2(Vector2(-10, y), Vector2(6, 4)), color, true)
	draw_rect(Rect2(Vector2(-2, y - 4), Vector2(4, 8)), color, true)
	draw_rect(Rect2(Vector2(6, y), Vector2(6, 4)), color, true)


func _on_damaged(_amount: float, _current_hp: float) -> void:
	play_action(&"hit")


func _on_healed(_amount: float, _current_hp: float) -> void:
	play_action(&"heal")


func _on_died(_killer: Variant) -> void:
	play_action(&"death")
	if _actor != null and is_instance_valid(_actor):
		cue_requested.emit(&"enemy_death" if _role != "player" else &"player_hurt", _actor.global_position, 1.0)


func _on_attack_phase_changed(phase: int) -> void:
	match phase:
		1:
			play_action(&"windup")
			if _actor != null and is_instance_valid(_actor):
				cue_requested.emit(&"danger_windup", _actor.global_position, 0.7)
		2:
			play_action(&"recovery")


func _boss_windup_cue(action: String) -> StringName:
	match action:
		"SLAM", "MELEE":
			return &"boss_windup_low"
		"RADIAL", "AIMED":
			return &"boss_windup_high"
		"SUMMON", "TIME_CRACK":
			return &"boss_windup_void"
	return &"danger_windup"


func _resolve_role(actor: Node) -> String:
	if actor.is_in_group("bosses"):
		return "boss"
	var script_path := ""
	var actor_script: Script = actor.get_script()
	if actor_script != null:
		script_path = actor_script.resource_path.to_lower()
	if actor.is_in_group("player") or "player_controller" in script_path:
		return "player"
	if "enemy_chaser" in script_path:
		return "chaser"
	if "enemy_shooter" in script_path:
		return "shooter"
	if "enemy_tank" in script_path:
		return "tank"
	if "boss_chrono_warden" in script_path:
		return "boss"
	return "generic"


func _is_elite_actor() -> bool:
	return _actor != null and is_instance_valid(_actor) and bool(_actor.get("_is_elite"))


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
