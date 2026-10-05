class_name PixelProxyActor
extends Node2D

signal cue_requested(cue_id: StringName, world_position: Vector2, intensity: float)

const AfterimageScript := preload("res://scripts/presentation/pixel_proxy_afterimage.gd")
const ActorAtlasScript := preload("res://scripts/presentation/actor_atlas_projection.gd")
const PIXEL_UNIT := 2
const SCREEN_PIXEL_UNIT := 2.0
const FLASH_BUDGET_WINDOW_SECONDS := 1.0
const MAX_FLASH_EVENTS_PER_WINDOW := 3
const ACTIVE_ITEM_HANDLER_IDS: Array[StringName] = [
	&"absolute_zero",
	&"paradox_beacon",
	&"gravity_snare",
	&"redline_injector",
	&"blood_price",
	&"aegis_reversal",
	&"railshot",
	&"army_of_yesterday",
]

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
const CHARACTER_VISUAL_PROFILES := {
	"wanderer": {
		"palette_id": "wanderer_cyan",
		"primary": Color(0.08, 0.72, 0.86),
		"secondary": Color(0.035, 0.12, 0.18),
		"accent": Color(0.82, 0.98, 1.0),
		"danger": Color(1.0, 0.32, 0.22),
		"footprint": Vector2i(24, 32),
		"resource_aura": Color(0.22, 0.94, 1.0),
		"skill_cue_id": "waypoint_recall",
		"damage_cue_id": "wanderer_stagger",
		"cue_budget": 4,
	},
	"time_guardian": {
		"palette_id": "guardian_gold",
		"primary": Color(0.22, 0.56, 0.82),
		"secondary": Color(0.04, 0.10, 0.22),
		"accent": Color(1.0, 0.82, 0.28),
		"danger": Color(1.0, 0.38, 0.18),
		"footprint": Vector2i(28, 34),
		"resource_aura": Color(1.0, 0.82, 0.28),
		"skill_cue_id": "chrono_fortress",
		"damage_cue_id": "guardian_ward_break",
		"cue_budget": 3,
	},
	"void_walker": {
		"palette_id": "void_magenta",
		"primary": Color(0.58, 0.16, 0.82),
		"secondary": Color(0.10, 0.02, 0.18),
		"accent": Color(0.96, 0.42, 1.0),
		"danger": Color(1.0, 0.20, 0.42),
		"footprint": Vector2i(24, 34),
		"resource_aura": Color(0.84, 0.22, 1.0),
		"skill_cue_id": "void_devour",
		"damage_cue_id": "void_corruption_hit",
		"cue_budget": 3,
	},
	"primordial_knight": {
		"palette_id": "primordial_iron",
		"primary": Color(0.58, 0.62, 0.68),
		"secondary": Color(0.08, 0.10, 0.14),
		"accent": Color(1.0, 0.54, 0.18),
		"danger": Color(1.0, 0.24, 0.12),
		"footprint": Vector2i(30, 36),
		"resource_aura": Color(1.0, 0.50, 0.16),
		"skill_cue_id": "realm_cleave",
		"damage_cue_id": "primordial_armor_hit",
		"cue_budget": 3,
	},
	"time_lord": {
		"palette_id": "codex_indigo",
		"primary": Color(0.28, 0.30, 0.82),
		"secondary": Color(0.04, 0.05, 0.18),
		"accent": Color(0.60, 0.96, 1.0),
		"danger": Color(1.0, 0.36, 0.66),
		"footprint": Vector2i(26, 34),
		"resource_aura": Color(0.48, 0.60, 1.0),
		"skill_cue_id": "codex_dominion",
		"damage_cue_id": "codex_page_break",
		"cue_budget": 2,
	},
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
var _flash_budget_elapsed: float = 0.0
var _flash_events_accepted: int = 0
var _flash_events_rejected: int = 0
var _bound: bool = false
var _last_boss_action: String = "NONE"
var _last_boss_phase: String = "IDLE"
var _afterimage_count: int = 0
var _facing := Vector2.RIGHT
var _attack_direction := Vector2.RIGHT
var _screen_action_offset := Vector2.ZERO
var _action_scale := Vector2.ONE
var _hit_flash_enabled: bool = true
var _reduced_motion: bool = false
var _boss_phase: int = 1
var _boss_exposed: bool = false
var _boss_time_stopped: bool = false
var _boss_core_shape: String = "sealed"
var _boss_texture_pattern: String = "flowing_ticks"
var _boss_luminance: float = 1.0
var _has_committed_facing_property: bool = false
var _has_velocity_property: bool = false
var _has_exposure_sources_property: bool = false
var _player_weapon_snapshot: Dictionary = {}
var _weapon_id: String = ""
var _weapon_phase: String = "READY"
var _weapon_action_id: String = ""
var _weapon_snapshot_available: bool = false
var _bow_tension: float = 0.0
var _bow_charge_tier: String = ""
var _staff_element: String = ""
var _presentation_animation_id: String = ""
var _presentation_vfx_id: String = ""
var _presentation_cue_remaining: float = 0.0
var _character_profile_id: String = ""
var _character_profile: Dictionary = {}
var _character_resource_ratio: float = 0.0
var _character_cue_kind: String = ""
var _character_success_remaining: float = 0.0
var _character_rejection_remaining: float = 0.0
var _high_contrast_character_feedback: bool = false
var _active_item_cue_id: String = ""
var _active_item_cue_kind: String = ""
var _active_item_cue_remaining: float = 0.0
var _actor_atlas: Sprite2D
var _cosmetic_id := ""
var _challenge_rewards: Dictionary = {}


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
	_has_committed_facing_property = actor is EnemyBase
	_has_velocity_property = actor is CharacterBody2D
	_has_exposure_sources_property = actor is BossChronoWarden
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
	_refresh_player_weapon_presentation()
	_refresh_character_presentation()
	_update_presentation_facing()
	_update_boss_presentation_state()
	_apply_pixel_transform()
	_sync_actor_atlas()
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
	if normalized == &"hit" and _hit_flash_enabled:
		_request_hit_flash()
	_refresh_player_weapon_presentation()
	_update_presentation_facing()
	_apply_pixel_transform()
	queue_redraw()


func play_weapon_cue(animation_id: StringName, vfx_id: StringName) -> void:
	_presentation_animation_id = str(animation_id)
	_presentation_vfx_id = str(vfx_id)
	_presentation_cue_remaining = _weapon_cue_duration()
	play_action(&"attack", _presentation_cue_remaining)


static func character_profile_snapshot(character_id: StringName) -> Dictionary:
	var profile_value: Variant = CHARACTER_VISUAL_PROFILES.get(str(character_id), {})
	return (profile_value as Dictionary).duplicate(true) if profile_value is Dictionary else {}


func play_character_cue(skill_id: StringName, accepted: bool) -> bool:
	if _character_profile.is_empty() or str(skill_id) != str(_character_profile.get("skill_cue_id", "")):
		return false
	if accepted:
		_character_cue_kind = "success"
		_character_rejection_remaining = 0.0
		_character_success_remaining = 0.34
		play_action(&"cast", _character_success_remaining)
	else:
		_character_cue_kind = "rejected"
		_character_success_remaining = 0.0
		_character_rejection_remaining = 0.65
		_action_remaining = 0.0
		if _state in [&"cast", &"time_stop", &"time_rewind"]:
			_state = &"idle"
		queue_redraw()
	return true


func play_active_item_cue(handler_id: StringName, accepted: bool) -> bool:
	if _role != "player" or handler_id not in ACTIVE_ITEM_HANDLER_IDS:
		return false
	_active_item_cue_id = str(handler_id)
	_active_item_cue_kind = "success" if accepted else "rejected"
	_active_item_cue_remaining = 0.34 if accepted else 0.65
	if accepted:
		play_action(&"cast", _active_item_cue_remaining)
	else:
		_action_remaining = 0.0
		if _state in [&"cast", &"time_stop", &"time_rewind"]:
			_state = &"idle"
	queue_redraw()
	return true


func spawn_afterimage(world_position: Vector2, lifetime: float = 0.22) -> Node2D:
	if _reduced_motion or _actor == null or not is_instance_valid(_actor) or _actor.get_parent() == null:
		return null
	var afterimage := AfterimageScript.new()
	_actor.get_parent().add_child(afterimage)
	var canvas_scale := _canvas_scale()
	var canvas_inverse_scale := Vector2(1.0 / canvas_scale.x, 1.0 / canvas_scale.y)
	var world_pixel_unit := Vector2(
		SCREEN_PIXEL_UNIT / canvas_scale.x,
		SCREEN_PIXEL_UNIT / canvas_scale.y
	)
	afterimage.global_position = Vector2(
		snappedf(world_position.x, world_pixel_unit.x),
		snappedf(world_position.y, world_pixel_unit.y)
	)
	afterimage.z_index = maxi(0, _actor.z_index - 1)
	afterimage.configure(
		_role,
		_palette["primary"],
		_palette["accent"],
		_footprint,
		_action_scale,
		canvas_inverse_scale,
		world_pixel_unit,
		lifetime
	)
	_afterimage_count += 1
	return afterimage


func advance_animation_for_test(delta: float) -> void:
	_advance_animation(maxf(0.0, delta))


func set_feedback_options(hit_flash_enabled: bool, reduced_motion: bool) -> void:
	_hit_flash_enabled = hit_flash_enabled
	_reduced_motion = reduced_motion
	if not _hit_flash_enabled:
		_flash_remaining = 0.0
	queue_redraw()


func set_character_feedback_options(high_contrast: bool) -> void:
	_high_contrast_character_feedback = high_contrast
	queue_redraw()


func get_snapshot_for_test() -> Dictionary:
	var canvas_scale := _canvas_scale()
	var world_pixel_unit := SCREEN_PIXEL_UNIT / canvas_scale.x
	return {
		"role": _role,
		"palette_id": str(_palette.get("id", "")),
		"pixel_unit": PIXEL_UNIT,
		"screen_pixel_unit": SCREEN_PIXEL_UNIT,
		"world_pixel_unit": world_pixel_unit,
		"texture_filter": texture_filter,
		"footprint": _footprint,
		"state": str(_state),
		"position": position,
		"pixel_snapped": is_equal_approx(fmod(absf(position.x), SCREEN_PIXEL_UNIT / canvas_scale.x), 0.0)
			and is_equal_approx(fmod(absf(position.y), SCREEN_PIXEL_UNIT / canvas_scale.y), 0.0),
		"screen_footprint": Vector2(_footprint) * scale * canvas_scale,
		"facing": _facing,
		"attack_direction": _attack_direction,
		"screen_action_offset": _screen_action_offset,
		"action_scale": _action_scale,
		"flash_active": _flash_remaining > 0.0,
		"flash_events_accepted": _flash_events_accepted,
		"flash_events_rejected": _flash_events_rejected,
		"reduced_motion": _reduced_motion,
		"velocity_capability_cached": _has_velocity_property,
		"weapon_snapshot_available": _weapon_snapshot_available,
		"weapon_id": _weapon_id,
		"weapon_phase": _weapon_phase,
		"weapon_action_id": _weapon_action_id,
		"weapon_visual": _weapon_visual_kind(),
		"bow_tension": _bow_tension,
		"bow_charge_tier": _bow_charge_tier,
		"gun_muzzle_visible": _gun_muzzle_visible(),
		"gun_reload_marker_visible": _gun_reload_marker_visible(),
		"gun_perfect_ring_visible": _gun_perfect_ring_visible(),
		"gun_time_load_active": _gun_time_load_active(),
		"staff_element": _staff_element,
		"staff_cast_circle_visible": _staff_cast_circle_visible(),
		"staff_zone_boundary_visible": _staff_zone_boundary_visible(),
		"staff_combination_signature_visible": _staff_combination_signature_visible(),
		"presentation_animation_id": _presentation_animation_id,
		"presentation_vfx_id": _presentation_vfx_id,
		"character_profile_id": _character_profile_id,
		"character_resource_ratio": _character_resource_ratio,
		"character_skill_cue_id": str(_character_profile.get("skill_cue_id", "")),
		"character_damage_cue_id": str(_character_profile.get("damage_cue_id", "")),
		"character_cue_budget": int(_character_profile.get("cue_budget", 0)),
		"character_cue_kind": _character_cue_kind,
		"character_success_active": _character_success_remaining > 0.0,
		"character_rejection_active": _character_rejection_remaining > 0.0,
		"high_contrast_character_feedback": _high_contrast_character_feedback,
		"active_item_cue_id": _active_item_cue_id,
		"active_item_cue_kind": _active_item_cue_kind,
		"active_item_cue_active": _active_item_cue_remaining > 0.0,
		"high_contrast_active_item_feedback": _high_contrast_character_feedback,
		"gauntlets_lead_fist": _gauntlets_lead_fist(),
		"gauntlets_punch_wind_visible": _gauntlets_punch_wind_visible(),
		"gauntlets_counter_line_visible": _gauntlets_counter_line_visible(),
		"melee_slash_visible": _state == &"attack" and _weapon_visual_kind() == "sword",
		"boss_phase_marks": _boss_phase,
		"boss_core_shape": _boss_core_shape,
		"boss_texture_pattern": _boss_texture_pattern,
		"boss_luminance": _boss_luminance,
		"afterimage_count": _afterimage_count,
		"actor_atlas": _actor_atlas.snapshot() if _actor_atlas != null else {},
		"challenge_rewards": _challenge_rewards.duplicate(true),
	}


func _process(delta: float) -> void:
	if not _bound or _actor == null or not is_instance_valid(_actor):
		return
	_advance_animation(delta)


func _advance_animation(delta: float) -> void:
	_advance_flash_budget(delta)
	if not _reduced_motion:
		_phase_clock += delta
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	_presentation_cue_remaining = maxf(0.0, _presentation_cue_remaining - delta)
	_character_success_remaining = maxf(0.0, _character_success_remaining - delta)
	_character_rejection_remaining = maxf(0.0, _character_rejection_remaining - delta)
	_active_item_cue_remaining = maxf(0.0, _active_item_cue_remaining - delta)
	if _character_success_remaining <= 0.0 and _character_rejection_remaining <= 0.0:
		_character_cue_kind = ""
	if _active_item_cue_remaining <= 0.0:
		_active_item_cue_id = ""
		_active_item_cue_kind = ""
	if _presentation_cue_remaining <= 0.0:
		_presentation_animation_id = ""
		_presentation_vfx_id = ""
	_refresh_player_weapon_presentation()
	_refresh_character_presentation()
	if _action_remaining > 0.0:
		_action_remaining = maxf(0.0, _action_remaining - delta)
	elif _state != &"death":
		_derive_state_from_actor()
	_update_presentation_facing()
	_update_boss_presentation_state()
	_apply_pixel_transform()
	_sync_actor_atlas()
	queue_redraw()


func _sync_actor_atlas() -> void:
	if _role != "player":
		return
	if _actor_atlas == null:
		_actor_atlas = ActorAtlasScript.new()
		_actor_atlas.name = "ProductionActorAtlas"
		_actor_atlas.z_index = -1
		add_child(_actor_atlas)
	var actor_id := _character_profile_id if not _character_profile_id.is_empty() else "wanderer"
	if not _actor_atlas.configure(actor_id, _cosmetic_id):
		return
	_actor_atlas.present(_state, _facing, _phase_clock, _flash_remaining > 0.0, _reduced_motion)
	_refresh_challenge_rewards()


func _refresh_challenge_rewards() -> void:
	_challenge_rewards = {}
	if _actor.has_method("challenge_reward_presentation_snapshot"):
		_challenge_rewards = _actor.challenge_reward_presentation_snapshot()
	var tint: Array = _challenge_rewards.get("tint", [])
	if not tint.is_empty():
		_actor_atlas.modulate *= Color(tint[0], tint[1], tint[2], tint[3])


func apply_cosmetic(cosmetic_id: String) -> bool:
	if _role != "player" or _actor_atlas == null:
		return false
	_refresh_character_presentation()
	var actor_id := _character_profile_id if not _character_profile_id.is_empty() else "wanderer"
	var previous := _cosmetic_id
	if not _actor_atlas.configure(actor_id, cosmetic_id):
		_actor_atlas.configure(actor_id, previous)
		return false
	_cosmetic_id = cosmetic_id
	_actor_atlas.present(_state, _facing, _phase_clock, _flash_remaining > 0.0, _reduced_motion)
	_refresh_challenge_rewards()
	return true


func _derive_state_from_actor() -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	if _role == "player":
		if _player_weapon_action_is_presented():
			_state = &"attack"
			return
		if _actor.has_method("get_player_ui_snapshot"):
			var snapshot: Dictionary = _actor.get_player_ui_snapshot()
			match str(snapshot.get("action_state", "FREE")):
				"ATTACK_WINDUP", "ATTACK_ACTIVE", "ATTACK_RECOVERY":
					if not _weapon_snapshot_available:
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
	if _has_velocity_property and (_actor.get("velocity") as Vector2).length_squared() > 64.0:
		_state = &"move"
	else:
		_state = &"idle"


func _update_presentation_facing() -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	var direction := _facing
	if _role == "player":
		if _state == &"attack" and _player_weapon_action_is_presented():
			var weapon_facing := _player_weapon_facing()
			if weapon_facing.length_squared() > 0.001:
				direction = weapon_facing
			elif _actor.has_method("get_rewind_facing"):
				direction = _actor.get_rewind_facing()
		elif _actor.has_method("get_rewind_facing"):
			direction = _actor.get_rewind_facing()
	elif _has_committed_facing_property:
		var committed: Variant = _actor.get("_committed_attack_direction")
		if committed is Vector2:
			direction = committed
	elif _has_velocity_property:
		var actor_velocity: Variant = _actor.get("velocity")
		if actor_velocity is Vector2 and (actor_velocity as Vector2).length_squared() > 0.001:
			direction = actor_velocity
	if direction.length_squared() <= 0.001:
		return
	_facing = _cardinal_direction(direction)
	if _state == &"attack":
		_attack_direction = _facing


func _refresh_player_weapon_presentation() -> void:
	if _role != "player" or _actor == null or not is_instance_valid(_actor):
		return
	if not _actor.has_method("weapon_presentation_snapshot"):
		_clear_player_weapon_presentation()
		return
	var snapshot_value: Variant = _actor.call("weapon_presentation_snapshot")
	if not snapshot_value is Dictionary:
		_clear_player_weapon_presentation()
		return
	var next_snapshot := snapshot_value as Dictionary
	if not next_snapshot.has("phase") or not next_snapshot.has("action_id"):
		_clear_player_weapon_presentation()
		return
	_player_weapon_snapshot = next_snapshot.duplicate(true)
	_weapon_id = str(_player_weapon_snapshot.get("weapon_id", ""))
	_weapon_phase = str(_player_weapon_snapshot.get("phase", "READY"))
	_weapon_action_id = str(_player_weapon_snapshot.get("action_id", ""))
	_bow_tension = (
		clampf(float(_player_weapon_snapshot.get("charge_ratio", 0.0)), 0.0, 1.0)
		if _weapon_id == "bow"
		else 0.0
	)
	_bow_charge_tier = _resolve_bow_charge_tier() if _weapon_id == "bow" else ""
	var runtime_value: Variant = _player_weapon_snapshot.get("runtime", {})
	var runtime: Dictionary = (
		(runtime_value as Dictionary)
		if runtime_value is Dictionary
		else {}
	)
	_staff_element = (
		str(runtime.get(
			"element",
			runtime.get(
				"current_element",
				_player_weapon_snapshot.get("current_element", "fire")
			)
		))
		if _weapon_id == "staff"
		else ""
	)
	_weapon_snapshot_available = true


func _clear_player_weapon_presentation() -> void:
	_player_weapon_snapshot.clear()
	_weapon_id = ""
	_weapon_phase = "READY"
	_weapon_action_id = ""
	_weapon_snapshot_available = false
	_bow_tension = 0.0
	_bow_charge_tier = ""
	_staff_element = ""


func _refresh_character_presentation() -> void:
	if _role != "player" or _actor == null or not is_instance_valid(_actor):
		return
	if not _actor.has_method("character_presentation_snapshot"):
		_clear_character_presentation()
		return
	var snapshot_value: Variant = _actor.call("character_presentation_snapshot")
	if not snapshot_value is Dictionary:
		_clear_character_presentation()
		return
	var snapshot := snapshot_value as Dictionary
	var profile_id := str(snapshot.get("runtime_kind", snapshot.get("character_id", "")))
	if profile_id == "wanderer_m1_compat":
		_clear_character_presentation()
		return
	var profile_value: Variant = CHARACTER_VISUAL_PROFILES.get(profile_id, {})
	if not profile_value is Dictionary or (profile_value as Dictionary).is_empty():
		_clear_character_presentation()
		return
	if _character_profile_id != profile_id:
		_cosmetic_id = ""
	_character_profile_id = profile_id
	_character_profile = (profile_value as Dictionary).duplicate(true)
	_palette = {
		"id": str(_character_profile["palette_id"]),
		"primary": _character_profile["primary"],
		"secondary": _character_profile["secondary"],
		"accent": _character_profile["accent"],
		"danger": _character_profile["danger"],
	}
	_footprint = _character_profile["footprint"] as Vector2i
	var current_value: Variant = snapshot.get("resource_value", 0)
	var maximum_value: Variant = snapshot.get("resource_maximum", _character_default_meter_max(profile_id))
	if typeof(current_value) in [TYPE_INT, TYPE_FLOAT] and typeof(maximum_value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(current_value)) and is_finite(float(maximum_value)) and float(maximum_value) > 0.0:
		_character_resource_ratio = clampf(float(current_value) / float(maximum_value), 0.0, 1.0)
	else:
		_character_resource_ratio = 0.0


func _clear_character_presentation() -> void:
	_cosmetic_id = ""
	_character_profile_id = ""
	_character_profile.clear()
	_character_resource_ratio = 0.0
	_palette = (PALETTES["player"] as Dictionary).duplicate(true)
	_footprint = FOOTPRINTS["player"]


func _character_default_meter_max(profile_id: String) -> int:
	match profile_id:
		"wanderer":
			return 5
		"void_walker":
			return 100
		_:
			return 3


func _player_weapon_action_is_presented() -> bool:
	return (
		_weapon_snapshot_available
		and not _weapon_action_id.is_empty()
		and _weapon_phase in ["HOLD", "WINDUP", "ACTIVE", "RESOURCE_ACTION", "RECOVERY"]
	)


func _weapon_visual_kind() -> String:
	match _weapon_id:
		"sword":
			return "sword"
		"bow":
			return "bow"
		"gun":
			return "gun"
		"staff":
			return "staff"
		"gauntlets":
			return "gauntlets"
		_:
			return ""


func _request_hit_flash() -> bool:
	if _flash_events_accepted >= MAX_FLASH_EVENTS_PER_WINDOW:
		_flash_events_rejected += 1
		return false
	_flash_events_accepted += 1
	_flash_remaining = maxf(_flash_remaining, 0.10)
	return true


func _advance_flash_budget(delta: float) -> void:
	_flash_budget_elapsed += maxf(0.0, delta)
	if _flash_budget_elapsed < FLASH_BUDGET_WINDOW_SECONDS:
		return
	_flash_budget_elapsed = fmod(_flash_budget_elapsed, FLASH_BUDGET_WINDOW_SECONDS)
	_flash_events_accepted = 0
	_flash_events_rejected = 0


func _weapon_cue_duration() -> float:
	if _presentation_animation_id == "gauntlets_ultimate":
		return 0.34
	if _presentation_animation_id in ["gauntlets_charged", "gauntlets_counter", "gauntlets_uppercut", "gauntlets_skill"]:
		return 0.26
	return 0.22


func _gauntlets_lead_fist() -> String:
	if _weapon_id != "gauntlets":
		return ""
	if _presentation_animation_id.begins_with("gauntlets_left_"):
		return "left"
	if _presentation_animation_id.begins_with("gauntlets_right_"):
		return "right"
	match _presentation_animation_id:
		"gauntlets_counter", "gauntlets_uppercut":
			return "right"
		"gauntlets_charged", "gauntlets_skill", "gauntlets_ultimate":
			return "both"
	match _weapon_action_id:
		"punch_1", "punch_3":
			return "left"
		"punch_2", "punch_4", "punch_5", "dodge_counter":
			return "right"
		"charged_heavy", "space_time_shatter", "primordial_collapse_punch":
			return "both"
	var runtime_value: Variant = _player_weapon_snapshot.get("runtime", {})
	if runtime_value is Dictionary:
		return "left" if int((runtime_value as Dictionary).get("chain_step", 0)) % 2 == 0 else "right"
	return "left"


func _gauntlets_punch_wind_visible() -> bool:
	return (
		_weapon_id == "gauntlets"
		and _presentation_cue_remaining > 0.0
		and _presentation_vfx_id in ["gauntlets_jab_wind", "gauntlets_hook_wind", "gauntlets_uppercut"]
	)


func _gauntlets_counter_line_visible() -> bool:
	return (
		_weapon_id == "gauntlets"
		and _presentation_cue_remaining > 0.0
		and _presentation_vfx_id == "gauntlets_counter_line"
	)


func _gun_muzzle_visible() -> bool:
	return (
		_weapon_id == "gun"
		and _weapon_phase == "ACTIVE"
		and _weapon_action_id in ["normal_fire", "aimed_fire", "shotgun_fire", "void_penetration"]
	)


func _gun_reload_marker_visible() -> bool:
	return (
		_weapon_id == "gun"
		and _weapon_action_id == "reload"
		and _weapon_phase in ["WINDUP", "RESOURCE_ACTION", "RECOVERY"]
	)


func _gun_perfect_ring_visible() -> bool:
	if not _gun_reload_marker_visible() or _weapon_phase != "RESOURCE_ACTION":
		return false
	var window_value: Variant = _player_weapon_snapshot.get("reload_window", {})
	return (
		window_value is Dictionary
		and str((window_value as Dictionary).get("segment", "")) == "perfect"
		and bool((window_value as Dictionary).get("perfect_confirm", false))
	)


func _gun_time_load_active() -> bool:
	return (
		_weapon_id == "gun"
		and int(_player_weapon_snapshot.get("time_load_remaining_frames", 0)) > 0
	)


func _staff_cast_circle_visible() -> bool:
	return (
		_weapon_id == "staff"
		and _weapon_phase in ["WINDUP", "ACTIVE"]
		and _weapon_action_id in ["charged_element", "planar_collapse", "primordial_wrath"]
	)


func _staff_zone_boundary_visible() -> bool:
	return (
		_weapon_id == "staff"
		and _weapon_action_id in ["planar_collapse", "primordial_wrath"]
		and _weapon_phase in ["ACTIVE", "RECOVERY"]
	)


func _staff_combination_signature_visible() -> bool:
	var runtime_value: Variant = _player_weapon_snapshot.get("runtime", {})
	var runtime: Dictionary = (
		(runtime_value as Dictionary)
		if runtime_value is Dictionary
		else {}
	)
	var remaining_frames := int(runtime.get(
		"combo_remaining_frames",
		runtime.get(
			"sequence_remaining_frames",
			_player_weapon_snapshot.get("sequence_remaining_frames", 0)
		)
	))
	var pending_combo_value: Variant = runtime.get("pending_combo", {})
	var pending_combo := (
		(pending_combo_value as Dictionary)
		if pending_combo_value is Dictionary
		else {}
	)
	return (
		_weapon_id == "staff"
		and (
			remaining_frames > 0
			or not str(_player_weapon_snapshot.get("combination_id", "")).is_empty()
			or not pending_combo.is_empty()
		)
	)


func _resolve_bow_charge_tier() -> String:
	if bool(_player_weapon_snapshot.get("full_charge", false)) or _bow_tension >= 0.98:
		return "full"
	if _bow_tension >= 0.67:
		return "high"
	if _bow_tension >= 0.34:
		return "medium"
	return "low"


func _player_weapon_facing() -> Vector2:
	var facing_value: Variant = _player_weapon_snapshot.get("facing")
	if not facing_value is Vector2:
		var runtime_value: Variant = _player_weapon_snapshot.get("runtime", {})
		if runtime_value is Dictionary:
			facing_value = (runtime_value as Dictionary).get("facing")
	if facing_value is Vector2:
		var facing := facing_value as Vector2
		if facing.is_finite():
			return facing
	return Vector2.ZERO


func _cardinal_direction(direction: Vector2) -> Vector2:
	if absf(direction.x) >= absf(direction.y):
		return Vector2(1.0 if direction.x >= 0.0 else -1.0, 0.0)
	return Vector2(0.0, 1.0 if direction.y >= 0.0 else -1.0)


func _update_boss_presentation_state() -> void:
	if _role != "boss" or _actor == null or not _actor.has_method("get_boss_ui_snapshot"):
		return
	var snapshot: Dictionary = _actor.get_boss_ui_snapshot()
	var action := str(snapshot.get("action", "NONE"))
	var phase := str(snapshot.get("phase", "IDLE"))
	_boss_phase = clampi(int(snapshot.get("boss_phase", 1)), 1, 3)
	_boss_exposed = bool(snapshot.get("exposed", false))
	_boss_time_stopped = false
	if _actor.has_method("is_time_stopped"):
		_boss_time_stopped = bool(_actor.is_time_stopped())
	if _has_exposure_sources_property:
		var sources: Variant = _actor.get("_exposure_sources")
		if sources is Dictionary:
			_boss_time_stopped = _boss_time_stopped or (sources as Dictionary).has(&"time_stop")
	_boss_core_shape = "split" if _boss_exposed else "sealed"
	_boss_texture_pattern = "frozen_grid" if _boss_time_stopped else "flowing_ticks"
	_boss_luminance = 1.0 + float(_boss_phase - 1) * 0.12
	if _boss_exposed:
		_boss_luminance += 0.16
	if _boss_time_stopped:
		_boss_luminance += 0.12
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
			if not _reduced_motion:
				offset.y = sin(_phase_clock * 5.0) * 1.4
		&"move":
			if not _reduced_motion:
				offset.y = -absf(sin(_phase_clock * 12.0)) * 2.0
				target_scale = Vector2(1.04, 0.96)
		&"attack":
			if _weapon_visual_kind() == "bow":
				offset = _facing * (-2.0 if _weapon_phase == "HOLD" else 2.0)
				if not _reduced_motion:
					target_scale = Vector2(1.03, 0.98) if absf(_facing.x) > 0.0 else Vector2(0.98, 1.03)
			elif _weapon_visual_kind() == "gun":
				offset = _facing * (-2.0 if _weapon_phase == "ACTIVE" else 0.0)
				if not _reduced_motion and _weapon_phase == "ACTIVE":
					target_scale = Vector2(1.04, 0.98) if absf(_facing.x) > 0.0 else Vector2(0.98, 1.04)
			elif _weapon_visual_kind() == "gauntlets":
				offset = _facing * (4.0 if _presentation_animation_id == "gauntlets_counter" else 2.0)
				if not _reduced_motion:
					target_scale = Vector2(1.1, 0.92) if absf(_facing.x) > 0.0 else Vector2(0.92, 1.1)
			elif _weapon_visual_kind() in ["sword", "staff"]:
				offset = _facing * 2.0
				target_scale = Vector2(1.08, 0.94) if absf(_facing.x) > 0.0 else Vector2(0.94, 1.08)
		&"dash":
			offset = _facing * (2.0 if _reduced_motion else 4.0)
			if not _reduced_motion:
				target_scale = Vector2(1.16, 0.86) if absf(_facing.x) > 0.0 else Vector2(0.86, 1.16)
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
	_screen_action_offset = Vector2(snappedf(offset.x, SCREEN_PIXEL_UNIT), snappedf(offset.y, SCREEN_PIXEL_UNIT))
	_action_scale = target_scale
	var canvas_scale := _canvas_scale()
	var world_pixel := Vector2(SCREEN_PIXEL_UNIT / canvas_scale.x, SCREEN_PIXEL_UNIT / canvas_scale.y)
	position = Vector2(
		snappedf(_screen_action_offset.x / canvas_scale.x, world_pixel.x),
		snappedf(_screen_action_offset.y / canvas_scale.y, world_pixel.y)
	)
	scale = target_scale * Vector2(1.0 / canvas_scale.x, 1.0 / canvas_scale.y)


func _draw() -> void:
	if not _bound:
		return
	var primary: Color = _palette["primary"]
	var secondary: Color = _palette["secondary"]
	var accent: Color = _palette["accent"]
	if _role == "boss" and _boss_luminance > 1.0:
		primary = primary.lightened(clampf((_boss_luminance - 1.0) * 0.55, 0.0, 0.35))
		accent = accent.lightened(clampf((_boss_luminance - 1.0) * 0.35, 0.0, 0.25))
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
	if _role == "player" and not _character_profile.is_empty():
		_draw_character_profile_cues()
	if _role == "player" and _active_item_cue_remaining > 0.0:
		_draw_active_item_cue()


func _draw_shadow() -> void:
	var width := float(_footprint.x - 4)
	var y := float(_footprint.y) * 0.45
	draw_rect(Rect2(Vector2(-width * 0.5, y), Vector2(width, 4)), Color(0.0, 0.0, 0.0, 0.45), true)


func _draw_player(primary: Color, secondary: Color, accent: Color) -> void:
	if _actor_atlas == null or not _actor_atlas.visible:
		draw_rect(Rect2(-10, -10, 20, 24), secondary, true)
		draw_rect(Rect2(-8, -14, 16, 12), primary, true)
		draw_rect(Rect2(-4, -12, 8, 6), accent, true)
		draw_rect(Rect2(-12, 0, 4, 12), primary.darkened(0.2), true)
		draw_rect(Rect2(8, 0, 4, 12), primary.darkened(0.2), true)
	var weapon_tint: Array = _challenge_rewards.get("weapon_tint", [])
	if not weapon_tint.is_empty():
		accent = Color(weapon_tint[0], weapon_tint[1], weapon_tint[2], weapon_tint[3])
	draw_set_transform(Vector2.ZERO, _facing.angle(), Vector2.ONE)
	if _weapon_visual_kind() == "bow":
		_draw_player_bow(accent)
	elif _weapon_visual_kind() == "gun":
		_draw_player_gun(accent)
	elif _weapon_visual_kind() == "staff":
		_draw_player_staff(accent)
	elif _weapon_visual_kind() == "gauntlets":
		_draw_player_gauntlets(accent)
	elif _weapon_visual_kind() == "sword" and _state == &"attack":
		draw_rect(Rect2(10, -4, 18, 4), accent, true)
		draw_rect(Rect2(24, -8, 4, 12), Color.WHITE, true)
	elif _weapon_visual_kind() == "sword":
		draw_rect(Rect2(10, 2, 14, 4), accent.darkened(0.15), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_challenge_rewards()


func _draw_challenge_rewards() -> void:
	var frame: String = _challenge_rewards.get("frame_id", "")
	if not frame.is_empty():
		var color := Color(0.96, 0.84, 0.3) if frame == "daily_walker_frame" else Color(0.35, 0.95, 0.74)
		for corner: Vector2 in [Vector2(-18, -22), Vector2(18, -22), Vector2(-18, 20), Vector2(18, 20)]:
			var inward := Vector2(-signf(corner.x), -signf(corner.y))
			draw_line(corner, corner + Vector2(inward.x * 6.0, 0), color, 2.0)
			draw_line(corner, corner + Vector2(0, inward.y * 6.0), color, 2.0)
	if not str(_challenge_rewards.get("title_id", "")).is_empty():
		draw_rect(Rect2(-6, -29, 12, 3), Color(0.96, 0.84, 0.3), true)
		draw_rect(Rect2(-2, -33, 4, 4), Color(0.84, 0.98, 1.0), true)
	if not str(_challenge_rewards.get("decoration_id", "")).is_empty():
		draw_rect(Rect2(-24, 7, 6, 8), Color(0.24, 0.85, 0.7), true)
		draw_line(Vector2(-23, 10), Vector2(-19, 10), Color.WHITE, 1.0)


func _draw_character_profile_cues() -> void:
	var aura_color := _character_profile.get("resource_aura", Color.WHITE) as Color
	if _character_resource_ratio > 0.0:
		var radius := 17.0 + roundf(_character_resource_ratio * 5.0)
		draw_arc(Vector2.ZERO, radius, -PI * 0.5, -PI * 0.5 + TAU * _character_resource_ratio, 20, Color(aura_color, 0.8), 2.0, false)
	match _character_profile_id:
		"time_guardian":
			draw_rect(Rect2(-14, -6, 4, 18), aura_color, true)
		"void_walker":
			draw_colored_polygon(PackedVector2Array([Vector2(-13, -12), Vector2(-7, -18), Vector2(-3, -12)]), aura_color)
		"primordial_knight":
			draw_rect(Rect2(-14, -12, 5, 24), aura_color.darkened(0.2), true)
		"time_lord":
			draw_rect(Rect2(-15, -14, 6, 10), aura_color, false, 2.0)
		"wanderer":
			draw_rect(Rect2(-12, -16, 8, 3), aura_color, true)
	if _character_rejection_remaining > 0.0:
		var rejection_color := Color.WHITE if _high_contrast_character_feedback else _palette["danger"] as Color
		draw_line(Vector2(-9, -9), Vector2(9, 9), rejection_color, 3.0)
		draw_line(Vector2(9, -9), Vector2(-9, 9), rejection_color, 3.0)
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 16, rejection_color, 2.0, false)


func _draw_active_item_cue() -> void:
	var cue_color := Color.WHITE if _high_contrast_character_feedback else _palette["accent"] as Color
	if _active_item_cue_kind == "rejected":
		cue_color = Color.WHITE if _high_contrast_character_feedback else _palette["danger"] as Color
		draw_line(Vector2(-12, -18), Vector2(12, 6), cue_color, 3.0)
		draw_line(Vector2(12, -18), Vector2(-12, 6), cue_color, 3.0)
		return
	var pulse := 0.0 if _reduced_motion else sin(_phase_clock * 16.0) * 2.0
	var radius := 22.0 + pulse
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, cue_color, 2.0, false)
	match _active_item_cue_id:
		"absolute_zero", "gravity_snare":
			draw_line(Vector2(-radius, 0), Vector2(radius, 0), cue_color, 2.0)
			draw_line(Vector2(0, -radius), Vector2(0, radius), cue_color, 2.0)
		"paradox_beacon", "army_of_yesterday":
			draw_arc(Vector2.ZERO, radius - 6.0, -PI * 0.75, PI * 0.75, 14, cue_color, 2.0, false)
		"redline_injector", "blood_price":
			draw_colored_polygon(PackedVector2Array([Vector2(-5, -radius), Vector2(8, -6), Vector2(0, -6), Vector2(6, radius), Vector2(-9, 2), Vector2(-1, 2)]), cue_color)
		"aegis_reversal":
			draw_polyline(PackedVector2Array([Vector2(0, -radius), Vector2(radius - 5, -9), Vector2(radius - 8, 12), Vector2(0, radius), Vector2(-radius + 8, 12), Vector2(-radius + 5, -9), Vector2(0, -radius)]), cue_color, 2.0)
		"railshot":
			draw_line(Vector2(-radius, 0), Vector2(radius, 0), cue_color, 4.0)


func _draw_player_bow(accent: Color) -> void:
	var bow_color := accent.darkened(0.18)
	var nock_x := snappedf(18.0 - 8.0 * _bow_tension, 2.0)
	draw_polyline(
		PackedVector2Array([
			Vector2(18, -14),
			Vector2(22, -8),
			Vector2(22, 8),
			Vector2(18, 14),
		]),
		bow_color,
		2.0,
		false
	)
	draw_polyline(
		PackedVector2Array([
			Vector2(18, -14),
			Vector2(nock_x, 0),
			Vector2(18, 14),
		]),
		Color(0.88, 0.94, 1.0),
		1.0,
		false
	)
	if _state == &"attack":
		var arrow_color := Color.WHITE if _bow_charge_tier == "full" else accent
		draw_rect(Rect2(nock_x, -1, 22.0 - nock_x, 2), arrow_color, true)
		draw_colored_polygon(
			PackedVector2Array([Vector2(24, 0), Vector2(20, -4), Vector2(20, 4)]),
			arrow_color
		)


func _draw_player_gun(accent: Color) -> void:
	var gun_color := accent.darkened(0.18)
	draw_rect(Rect2(10, -4, 18, 8), gun_color, true)
	draw_rect(Rect2(14, 4, 6, 8), gun_color.darkened(0.28), true)
	draw_rect(Rect2(26, -2, 8, 4), accent, true)
	if _gun_muzzle_visible():
		draw_colored_polygon(
			PackedVector2Array([Vector2(36, 0), Vector2(44, -6), Vector2(42, 0), Vector2(44, 6)]),
			Color(1.0, 0.86, 0.34)
		)
	if _gun_reload_marker_visible():
		var reload_frame := clampi(int(_player_weapon_snapshot.get("reload_frame", 0)), 0, 48)
		var marker_x := lerpf(10.0, 34.0, float(reload_frame) / 48.0)
		draw_rect(Rect2(10, 15, 24, 2), Color(0.22, 0.3, 0.36), true)
		draw_rect(Rect2(marker_x - 1.0, 13, 2, 6), accent, true)
	if _gun_perfect_ring_visible():
		draw_arc(Vector2(22, 0), 18.0, 0.0, TAU, 16, Color(1.0, 0.88, 0.3), 2.0, false)
	if _gun_time_load_active():
		draw_arc(Vector2.ZERO, 21.0, 0.0, TAU, 16, Color(0.24, 0.94, 1.0), 2.0, false)


func _draw_player_staff(accent: Color) -> void:
	var element_color := _staff_element_color()
	draw_rect(Rect2(12, -3, 24, 5), accent.darkened(0.28), true)
	draw_rect(Rect2(32, -7, 5, 13), accent, true)
	draw_circle(Vector2(36, -9), 6.0, element_color)
	if _staff_cast_circle_visible():
		draw_arc(Vector2(22, 0), 17.0, 0.0, TAU, 18, element_color, 2.0, false)
	if _staff_zone_boundary_visible():
		draw_arc(Vector2(22, 0), 23.0, 0.0, TAU, 20, element_color.darkened(0.18), 2.0, false)
	if _staff_combination_signature_visible():
		draw_arc(Vector2(36, -9), 10.0, 0.0, TAU, 12, Color.WHITE, 1.0, false)
		draw_rect(Rect2(32, -10, 8, 2), element_color.lightened(0.25), true)


func _draw_player_gauntlets(accent: Color) -> void:
	var glove_color := accent.darkened(0.08)
	var lead_fist := _gauntlets_lead_fist()
	var left_extension := 10.0 if _state == &"attack" and lead_fist in ["left", "both"] else 0.0
	var right_extension := 10.0 if _state == &"attack" and lead_fist in ["right", "both"] else 0.0
	draw_rect(Rect2(8.0 + left_extension, -11.0, 8.0, 8.0), glove_color, true)
	draw_rect(Rect2(8.0 + right_extension, 3.0, 8.0, 8.0), glove_color.lightened(0.12), true)
	draw_rect(Rect2(14.0 + left_extension, -9.0, 4.0, 4.0), Color.WHITE, true)
	draw_rect(Rect2(14.0 + right_extension, 5.0, 4.0, 4.0), Color.WHITE, true)
	if _gauntlets_punch_wind_visible():
		var wind_y := -7.0 if lead_fist == "left" else 7.0
		for index: int in range(3):
			var line_offset := float(index) * 5.0
			draw_line(
				Vector2(20.0 + line_offset, wind_y - 5.0),
				Vector2(32.0 + line_offset, wind_y - 5.0),
				accent.lightened(0.24),
				2.0
			)
	if _gauntlets_counter_line_visible():
		for index: int in range(4):
			var line_y := -12.0 + float(index) * 8.0
			draw_line(Vector2(-28.0, line_y), Vector2(4.0, line_y), Color(0.52, 0.96, 1.0), 2.0)
	match _presentation_vfx_id:
		"gauntlets_charged_ring":
			draw_arc(Vector2(22.0, 0.0), 16.0, 0.0, TAU, 16, Color(1.0, 0.82, 0.28), 2.0, false)
		"gauntlets_shatter":
			for angle: float in [-0.6, -0.2, 0.2, 0.6]:
				draw_line(Vector2(18.0, 0.0), Vector2(38.0, 0.0).rotated(angle), accent, 2.0)
		"gauntlets_collapse":
			draw_arc(Vector2(18.0, 0.0), 18.0, 0.0, TAU, 18, accent, 2.0, false)
			draw_arc(Vector2(18.0, 0.0), 26.0, 0.0, TAU, 22, Color.WHITE, 2.0, false)


func _staff_element_color() -> Color:
	match _staff_element:
		"ice":
			return Color(0.34, 0.82, 1.0)
		"lightning":
			return Color(0.92, 0.82, 0.28)
		_:
			return Color(1.0, 0.34, 0.18)


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
	if _boss_core_shape == "split":
		draw_rect(Rect2(-8, -12, 6, 16), accent, true)
		draw_rect(Rect2(2, -12, 6, 16), accent, true)
		draw_rect(Rect2(-2, -8, 4, 4), secondary, true)
		draw_rect(Rect2(-2, 0, 4, 4), secondary, true)
	else:
		draw_rect(Rect2(-2, -12, 4, 12), accent, true)
		draw_rect(Rect2(0, -2, 10, 4), accent, true)
	draw_rect(Rect2(-28, -12, 6, 30), primary.darkened(0.1), true)
	draw_rect(Rect2(22, -12, 6, 30), primary.darkened(0.1), true)
	draw_rect(Rect2(-8, 22, 16, 8), accent.darkened(0.3), true)
	for index: int in range(_boss_phase):
		draw_rect(Rect2(-10.0 + float(index) * 8.0, -36.0, 4.0, 6.0), accent, true)
	if _boss_texture_pattern == "frozen_grid":
		for y: float in [-18.0, -6.0, 6.0, 18.0]:
			draw_rect(Rect2(-24.0, y, 48.0, 2.0), accent, true)
		draw_rect(Rect2(-16.0, -28.0, 2.0, 54.0), accent, true)
		draw_rect(Rect2(14.0, -28.0, 2.0, 54.0), accent, true)
	else:
		var tick_offset := float(int(_phase_clock * 8.0) % 3) * 4.0
		draw_rect(Rect2(-24.0 + tick_offset, 12.0, 8.0, 2.0), accent, true)


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


func _canvas_scale() -> Vector2:
	if not is_inside_tree():
		return Vector2.ONE
	var canvas_transform := get_viewport().get_canvas_transform()
	return Vector2(
		maxf(0.001, canvas_transform.x.length()),
		maxf(0.001, canvas_transform.y.length())
	)
