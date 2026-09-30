class_name StaffSpellZone
extends Area2D

signal payload_result(action_token: int, generation: int, result: Dictionary)
signal resource_reward_requested(
	action_token: int,
	generation: int,
	claim_id: StringName,
	reward_id: StringName,
	amount: float
)

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const PIXELS_PER_TILE := 64.0
const FIRE_BURN_DURATION_FRAMES := 240
const FIRE_BURN_TICK_INTERVAL_FRAMES := 30
const FIRE_BURN_DAMAGE_MULTIPLIER := 0.10

const VALID_MODES: Array[String] = [
	"ice_zone",
	"planar_collapse",
	"combination",
	"seeded_sequence",
]
const VALID_COMBINATION_KINDS: Array[String] = [
	"explosion",
	"zone",
	"delayed_explosion",
	"staged_zone_explosion",
	"chain_delayed_explosions",
	"chain_delayed_crystals",
]
const EXECUTION_SNAPSHOT_FIELDS: Array[String] = [
	"action_token", "generation", "source_action_id", "descriptor_id", "outcome_index",
	"deterministic_seed", "mode", "parameters", "base_attack", "status_source_id",
	"boss_conversion", "execution_frame", "duration_frames", "tick_interval_frames",
	"fractional_frames", "claims", "transient_status_target_ids", "execution_active",
	"completion_emitted",
]

var action_token: int = 0
var generation: int = 0
var source_action_id: String = ""
var descriptor_id: String = ""
var outcome_index: int = 0
var deterministic_seed: int = 0
var mode: String = ""
var parameters: Dictionary = {}
var base_attack: float = 9.0
var source: Node
var owner_entity: Node
var status_source_id: StringName = &""
var boss_conversion: Dictionary = {}

var _execution_frame: int = 0
var _duration_frames: int = 0
var _tick_interval_frames: int = 0
var _execution_active: bool = false
var _completion_emitted: bool = false
var _claims: Dictionary = {}
var _fractional_frames: float = 0.0
var _transient_status_targets: Dictionary = {}
var _transient_status_target_ids: Dictionary = {}


func _ready() -> void:
	add_to_group("staff_spell_zones")
	set_physics_process(_execution_active)


func _physics_process(delta: float) -> void:
	if not _execution_active or delta <= 0.0:
		return
	_fractional_frames += delta * 60.0
	var frames := int(floorf(_fractional_frames))
	if frames <= 0:
		return
	_fractional_frames -= float(frames)
	advance_execution_for_test(frames)


func configure_execution(execution: Dictionary) -> bool:
	reset_execution_state()
	for field: String in [
		"action_token",
		"generation",
		"source_action_id",
		"descriptor_id",
		"outcome_index",
		"deterministic_seed",
		"mode",
		"parameters",
	]:
		if not execution.has(field):
			return false
	if (
		typeof(execution["action_token"]) != TYPE_INT
		or int(execution["action_token"]) <= 0
		or typeof(execution["generation"]) != TYPE_INT
		or int(execution["generation"]) <= 0
		or str(execution["source_action_id"]).is_empty()
		or str(execution["descriptor_id"]).is_empty()
		or typeof(execution["outcome_index"]) != TYPE_INT
		or int(execution["outcome_index"]) < 0
		or typeof(execution["deterministic_seed"]) != TYPE_INT
		or str(execution["mode"]) not in VALID_MODES
		or not execution["parameters"] is Dictionary
	):
		return false
	var parsed_parameters := (execution["parameters"] as Dictionary).duplicate(true)
	var timing := _resolved_timing(str(execution["mode"]), parsed_parameters)
	if not bool(timing.get("ok", false)):
		return false

	action_token = int(execution["action_token"])
	generation = int(execution["generation"])
	source_action_id = str(execution["source_action_id"])
	descriptor_id = str(execution["descriptor_id"])
	outcome_index = int(execution["outcome_index"])
	deterministic_seed = int(execution["deterministic_seed"])
	mode = str(execution["mode"])
	parameters = parsed_parameters
	var base_attack_value: Variant = execution.get("base_attack", 9.0)
	if not _positive_number(base_attack_value):
		reset_execution_state()
		return false
	base_attack = float(base_attack_value)
	var source_value: Variant = execution.get("source")
	source = source_value as Node if source_value is Node else null
	var owner_value: Variant = execution.get("owner_entity")
	owner_entity = owner_value as Node if owner_value is Node else null
	var boss_conversion_value: Variant = execution.get("boss_conversion", {})
	if not boss_conversion_value is Dictionary:
		reset_execution_state()
		return false
	boss_conversion = (boss_conversion_value as Dictionary).duplicate(true)
	status_source_id = StringName(str(execution.get(
		"status_source_id",
		"staff:%d:%s:%d" % [action_token, descriptor_id, outcome_index]
	)))
	if status_source_id == &"":
		reset_execution_state()
		return false
	_duration_frames = int(timing["duration_frames"])
	_tick_interval_frames = int(timing["tick_interval_frames"])
	_execution_active = true
	set_physics_process(is_inside_tree())
	return true


func advance_execution_for_test(frames: int) -> void:
	if not _execution_active or frames <= 0:
		return
	for _frame: int in range(frames):
		if not _execution_active:
			break
		_execution_frame += 1
		match mode:
			"ice_zone":
				_advance_damage_zone()
			"planar_collapse":
				_advance_planar_collapse()
			"combination":
				_advance_combination()
			"seeded_sequence":
				_advance_seeded_sequence()


func execution_snapshot() -> Dictionary:
	return {
		"action_token": action_token,
		"generation": generation,
		"source_action_id": source_action_id,
		"descriptor_id": descriptor_id,
		"outcome_index": outcome_index,
		"deterministic_seed": deterministic_seed,
		"mode": mode,
		"parameters": parameters.duplicate(true),
		"base_attack": base_attack,
		"status_source_id": status_source_id,
		"boss_conversion": boss_conversion.duplicate(true),
		"execution_frame": _execution_frame,
		"duration_frames": _duration_frames,
		"tick_interval_frames": _tick_interval_frames,
		"fractional_frames": _fractional_frames,
		"claims": _sorted_string_keys(_claims),
		"transient_status_target_ids": _transient_status_ids_snapshot(),
		"execution_active": _execution_active,
		"completion_emitted": _completion_emitted,
	}


func can_restore_execution_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields(value, EXECUTION_SNAPSHOT_FIELDS):
		return false
	var staged := StaffSpellZone.new()
	var configured := staged.configure_execution(value)
	if not configured:
		staged.free()
		return false
	var frame_value: Variant = value.get("execution_frame")
	var duration_value: Variant = value.get("duration_frames")
	var interval_value: Variant = value.get("tick_interval_frames")
	var fractional_value: Variant = value.get("fractional_frames")
	var claims_value: Variant = value.get("claims")
	var transient_value: Variant = value.get("transient_status_target_ids")
	var valid := (
		typeof(frame_value) == TYPE_INT
		and int(frame_value) >= 0
		and int(frame_value) <= staged._duration_frames
		and typeof(duration_value) == TYPE_INT
		and int(duration_value) == staged._duration_frames
		and typeof(interval_value) == TYPE_INT
		and int(interval_value) == staged._tick_interval_frames
		and typeof(fractional_value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(fractional_value))
		and float(fractional_value) >= 0.0
		and float(fractional_value) < 1.0
		and _valid_claim_array(claims_value)
		and _valid_transient_status_snapshot(transient_value)
		and typeof(value.get("execution_active")) == TYPE_BOOL
		and typeof(value.get("completion_emitted")) == TYPE_BOOL
		and bool(value.get("execution_active", false)) != bool(value.get("completion_emitted", false))
	)
	if valid and bool(value.get("execution_active", false)) and int(frame_value) >= int(duration_value):
		valid = false
	if valid and bool(value.get("completion_emitted", false)) and int(frame_value) < int(duration_value):
		valid = false
	staged.free()
	return valid


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func restore_execution_snapshot(value: Dictionary) -> bool:
	if not can_restore_execution_snapshot(value):
		return false
	if not configure_execution(value):
		return false
	_execution_frame = int(value["execution_frame"])
	_fractional_frames = float(value["fractional_frames"])
	_claims.clear()
	for claim_value: Variant in value["claims"] as Array:
		_claims[str(claim_value)] = true
	_transient_status_target_ids = (value["transient_status_target_ids"] as Dictionary).duplicate(true)
	_execution_active = bool(value["execution_active"])
	_completion_emitted = bool(value["completion_emitted"])
	set_physics_process(_execution_active and is_inside_tree())
	return execution_snapshot() == value


func activate_restored_execution_state() -> bool:
	if not _execution_active or not is_inside_tree():
		return false
	if not _reapply_restored_transient_statuses():
		return false
	set_physics_process(true)
	return true


func reset_execution_state() -> void:
	_clear_all_transient_statuses()
	_execution_active = false
	_completion_emitted = false
	_claims.clear()
	_fractional_frames = 0.0
	_transient_status_target_ids.clear()
	_execution_frame = 0
	_duration_frames = 0
	_tick_interval_frames = 0
	action_token = 0
	generation = 0
	source_action_id = ""
	descriptor_id = ""
	outcome_index = 0
	deterministic_seed = 0
	mode = ""
	parameters.clear()
	base_attack = 9.0
	source = null
	owner_entity = null
	status_source_id = &""
	boss_conversion.clear()
	set_physics_process(false)


func status_source_identity() -> Dictionary:
	return {
		"source_id": status_source_id,
		"generation": generation,
		"action_token": action_token,
	}


func _advance_damage_zone() -> void:
	_maintain_ice_slow()
	if _tick_interval_frames > 0 and _execution_frame % _tick_interval_frames == 0:
		_damage_targets_in_radius(
			global_position,
			float(parameters.get("radius_tiles", 0.0)),
			base_attack * float(parameters.get("damage_multiplier", 0.0)),
			"ice"
		)
		_emit_once(
			"zone_tick:%d" % _execution_frame,
			{
				"type": "zone_tick",
				"claim_id": "zone_tick:%d:%d" % [outcome_index, _execution_frame],
				"descriptor_id": descriptor_id,
				"outcome_index": outcome_index,
				"execution_frame": _execution_frame,
				"mode": mode,
				"parameters": parameters.duplicate(true),
			}
		)
	if _execution_frame >= _duration_frames:
		_apply_status_to_targets(
			_targets_in_radius(global_position, float(parameters.get("radius_tiles", 0.0))),
			&"freeze",
			int(parameters.get("freeze_duration_frames", 0)),
			1.0
		)
		_clear_transient_status(&"slow")
		_complete_zone()


func _advance_planar_collapse() -> void:
	var radius_tiles := float(parameters.get("radius_tiles", 0.0))
	if _execution_frame == 1:
		var targets := _targets_in_radius(global_position, radius_tiles)
		_damage_targets(targets, base_attack * float(parameters.get("damage_multiplier", 0.0)) * 0.5, "time")
		_damage_targets(targets, base_attack * float(parameters.get("damage_multiplier", 0.0)) * 0.5, "void")
		for target: Node in targets:
			if target.is_in_group("bosses"):
				_apply_status(
					target,
					&"slow",
					int(parameters.get("boss_slow_duration_frames", 0)),
					float(parameters.get("boss_slow_multiplier", 1.0)),
					30,
					float(parameters.get("boss_slow_multiplier", 1.0))
				)
			else:
				_apply_status(
					target,
					&"freeze",
					int(parameters.get("ordinary_freeze_frames", 0)),
					1.0
				)
	var erosion_duration := int(parameters.get("void_erosion_duration_frames", 0))
	if (
		_execution_frame <= erosion_duration
		and _tick_interval_frames > 0
		and _execution_frame % _tick_interval_frames == 0
	):
		_damage_targets_in_radius(
			global_position,
			radius_tiles,
			base_attack * float(parameters.get("void_erosion_damage_multiplier", 0.0)),
			"void"
		)
		_emit_once(
			"zone_tick:%d" % _execution_frame,
			{
				"type": "zone_tick",
				"claim_id": "zone_tick:%d:%d" % [outcome_index, _execution_frame],
				"descriptor_id": descriptor_id,
				"outcome_index": outcome_index,
				"execution_frame": _execution_frame,
				"mode": mode,
				"parameters": parameters.duplicate(true),
			}
		)
	if _execution_frame >= _duration_frames:
		_complete_zone()


func _advance_combination() -> void:
	var combo_id := str(parameters.get("combo_id", ""))
	var combo_kind := str(parameters.get("combo_kind", ""))
	var combo_parameters := parameters.get("combo_parameters", {}) as Dictionary
	var trigger_frame := _combination_trigger_frame(combo_kind, combo_parameters)
	if combo_id == "reverse_steam" and _execution_frame == 1:
		_apply_status_to_targets(
			_targets_in_radius(global_position, float(combo_parameters.get("freeze_radius_tiles", 0.0))),
			&"freeze",
			int(combo_parameters.get("freeze_duration_frames", 0)),
			1.0
		)
	if _execution_frame == trigger_frame:
		_execute_combination_trigger(combo_id, combo_kind, combo_parameters)
		_emit_once(
			"combination_resolved",
			{
				"type": "combination_resolved",
				"claim_id": "combination:%d:%s" % [outcome_index, combo_id],
				"descriptor_id": descriptor_id,
				"outcome_index": outcome_index,
				"execution_frame": _execution_frame,
				"combo_id": combo_id,
				"combo_kind": combo_kind,
				"parameters": combo_parameters.duplicate(true),
			}
		)
	if combo_kind == "zone" and _tick_interval_frames > 0 and _execution_frame % _tick_interval_frames == 0:
		_execute_combination_zone_tick(combo_id, combo_parameters)
		_emit_once(
			"combination_tick:%d" % _execution_frame,
			{
				"type": "zone_tick",
				"claim_id": "combination_tick:%d:%d" % [outcome_index, _execution_frame],
				"descriptor_id": descriptor_id,
				"outcome_index": outcome_index,
				"execution_frame": _execution_frame,
				"mode": "combination",
				"combo_id": combo_id,
				"parameters": combo_parameters.duplicate(true),
			}
		)
	if combo_id == "crystal_thunder" and _execution_frame >= trigger_frame:
		_maintain_transient_status(
			&"slow",
			_targets_in_radius(global_position, float(combo_parameters.get("radius_tiles", 0.0))),
			float(combo_parameters.get("ice_surface_move_speed_multiplier", 1.0)),
			float(combo_parameters.get("ice_surface_move_speed_multiplier", 1.0))
		)
	if _execution_frame >= _duration_frames:
		_clear_all_transient_statuses()
		_complete_zone()


func _advance_seeded_sequence() -> void:
	if _tick_interval_frames <= 0 or _execution_frame % _tick_interval_frames != 0:
		return
	var tick_index := (_execution_frame / _tick_interval_frames) - 1
	var count := int(parameters.get("count", 0))
	if tick_index < 0 or tick_index >= count:
		return
	var elements: Array = parameters.get("elements", [])
	var tick_seed := _derived_tick_seed(deterministic_seed, tick_index)
	var element_index := posmod(tick_seed, elements.size())
	var element_id := str(elements[element_index])
	_damage_targets_in_radius(
		global_position,
		float(parameters.get("radius_tiles", 0.0)),
		base_attack * float(parameters.get("damage_multiplier", 0.0)),
		element_id
	)
	_restore_time_energy_tick(tick_index)
	_emit_once(
		"ultimate_tick:%d" % tick_index,
		{
			"type": "ultimate_tick",
			"claim_id": "ultimate_tick:%d:%d" % [outcome_index, tick_index],
			"descriptor_id": descriptor_id,
			"outcome_index": outcome_index,
			"execution_frame": _execution_frame,
			"tick_index": tick_index,
			"tick_seed": tick_seed,
			"element_id": element_id,
		}
	)
	if tick_index + 1 >= count:
		_complete_zone()


func _complete_zone() -> void:
	if _completion_emitted:
		return
	_completion_emitted = true
	_execution_active = false
	_clear_all_transient_statuses()
	set_physics_process(false)
	_emit_once(
		"zone_complete",
		{
			"type": "zone_complete",
			"claim_id": "zone_complete:%d" % outcome_index,
			"descriptor_id": descriptor_id,
			"outcome_index": outcome_index,
			"execution_frame": _execution_frame,
			"mode": mode,
			"terminal": true,
		}
	)
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()


func _emit_once(claim: String, result: Dictionary) -> void:
	if _claims.has(claim):
		return
	_claims[claim] = true
	payload_result.emit(action_token, generation, result.duplicate(true))


func _resolved_timing(zone_mode: String, zone_parameters: Dictionary) -> Dictionary:
	match zone_mode:
		"ice_zone":
			var duration := int(zone_parameters.get("duration_frames", 0))
			var interval := int(zone_parameters.get("tick_interval_frames", 0))
			if (
				duration <= 0
				or interval <= 0
				or interval > duration
				or not _positive_number(zone_parameters.get("radius_tiles"))
				or not _non_negative_number(zone_parameters.get("damage_multiplier"))
			):
				return {"ok": false}
			return {"ok": true, "duration_frames": duration, "tick_interval_frames": interval}
		"planar_collapse":
			var field_duration := int(zone_parameters.get("duration_frames", 0))
			var erosion_duration := int(zone_parameters.get("void_erosion_duration_frames", field_duration))
			var interval := int(zone_parameters.get(
				"tick_interval_frames",
				zone_parameters.get("void_erosion_tick_interval_frames", 0)
			))
			if (
				field_duration <= 0
				or erosion_duration <= 0
				or interval <= 0
				or interval > erosion_duration
				or not _positive_number(zone_parameters.get("radius_tiles"))
				or not _non_negative_number(zone_parameters.get("damage_multiplier"))
				or not _non_negative_number(zone_parameters.get("void_erosion_damage_multiplier", 0.0))
			):
				return {"ok": false}
			return {
				"ok": true,
				"duration_frames": maxi(field_duration, erosion_duration),
				"tick_interval_frames": interval,
			}
		"seeded_sequence":
			var count := int(zone_parameters.get("count", 0))
			var interval := int(zone_parameters.get("tick_interval_frames", 0))
			var elements_value: Variant = zone_parameters.get("elements", [])
			if count <= 0 or interval <= 0 or not elements_value is Array or (elements_value as Array).is_empty():
				return {"ok": false}
			for element_value: Variant in elements_value as Array:
				if str(element_value) not in ["fire", "ice", "lightning"]:
					return {"ok": false}
			return {"ok": true, "duration_frames": count * interval, "tick_interval_frames": interval}
		"combination":
			var combo_id := str(zone_parameters.get("combo_id", ""))
			var combo_kind := str(zone_parameters.get("combo_kind", ""))
			var combo_value: Variant = zone_parameters.get("combo_parameters", {})
			if combo_id.is_empty() or combo_kind not in VALID_COMBINATION_KINDS or not combo_value is Dictionary:
				return {"ok": false}
			var combo_parameters := combo_value as Dictionary
			var trigger := _combination_trigger_frame(combo_kind, combo_parameters)
			var duration := trigger
			var interval := 0
			if combo_kind == "zone":
				duration = int(combo_parameters.get("duration_frames", 0))
				interval = int(combo_parameters.get("tick_interval_frames", 0))
				if duration <= 0 or interval <= 0 or interval > duration:
					return {"ok": false}
			elif combo_kind == "delayed_explosion" and combo_id == "crystal_thunder":
				duration = trigger + int(combo_parameters.get("ice_surface_duration_frames", 0))
			if trigger <= 0:
				return {"ok": false}
			return {"ok": true, "duration_frames": maxi(trigger, duration), "tick_interval_frames": interval}
	return {"ok": false}


func _combination_trigger_frame(combo_kind: String, combo_parameters: Dictionary) -> int:
	match combo_kind:
		"explosion", "zone":
			return 1
		"delayed_explosion", "staged_zone_explosion", "chain_delayed_explosions", "chain_delayed_crystals":
			return int(combo_parameters.get("delay_frames", 0))
	return 0


func _derived_tick_seed(base_seed: int, tick_index: int) -> int:
	var mixed := int(base_seed) * 1103515245 + (tick_index + 1) * 12345
	return posmod(mixed, 2147483647)


func _execute_combination_trigger(
	combo_id: String,
	_combo_kind: String,
	combo_parameters: Dictionary
) -> void:
	match combo_id:
		"steam_burst":
			var steam_targets := _targets_in_radius(global_position, float(combo_parameters.get("radius_tiles", 0.0)))
			_execute_split_explosion(
				global_position,
				float(combo_parameters.get("radius_tiles", 0.0)),
				float(combo_parameters.get("damage_multiplier", 0.0)),
				combo_parameters
			)
			_apply_combo_time_damage(steam_targets, combo_parameters)
			_apply_status_to_targets(
				steam_targets,
				&"blind",
				int(combo_parameters.get("blind_duration_frames", 0)),
				float(combo_parameters.get("blind_miss_chance", 0.0))
			)
		"crystal_thunder":
			var targets := _targets_in_radius(global_position, float(combo_parameters.get("radius_tiles", 0.0)))
			_damage_targets(targets, base_attack * float(combo_parameters.get("ice_damage_multiplier", 0.0)), "ice")
			_damage_targets(targets, base_attack * float(combo_parameters.get("lightning_damage_multiplier", 0.0)), "lightning")
			_apply_combo_time_damage(targets, combo_parameters)
		"reverse_steam":
			var reverse_targets := _targets_in_radius(global_position, float(combo_parameters.get("explosion_radius_tiles", 0.0)))
			_execute_split_explosion(
				global_position,
				float(combo_parameters.get("explosion_radius_tiles", 0.0)),
				float(combo_parameters.get("explosion_damage_multiplier", 0.0)),
				combo_parameters
			)
			_apply_combo_time_damage(reverse_targets, combo_parameters)
			_apply_status_to_targets(
				reverse_targets,
				&"blind",
				int(combo_parameters.get("blind_duration_frames", 0)),
				float(combo_parameters.get("blind_miss_chance", 0.0))
			)
		"thunder_flare":
			_execute_origin_explosions(
				combo_parameters,
				base_attack * float(combo_parameters.get("fire_damage_multiplier", 0.0)),
				"fire",
				&"",
				0
			)
		"thunder_crystal":
			_execute_origin_explosions(
				combo_parameters,
				base_attack * float(combo_parameters.get("ice_damage_multiplier", 0.0)),
				"ice",
				&"freeze",
				int(combo_parameters.get("freeze_duration_frames", 0))
			)


func _execute_combination_zone_tick(combo_id: String, combo_parameters: Dictionary) -> void:
	if combo_id != "blazing_storm":
		return
	var tick_index := (_execution_frame / maxi(1, _tick_interval_frames)) - 1
	var targets := _targets_in_radius(global_position, float(combo_parameters.get("radius_tiles", 0.0)))
	if tick_index % 2 == 0:
		_damage_targets(targets, base_attack * float(combo_parameters.get("fire_damage_multiplier", 0.0)), "fire")
		if bool(combo_parameters.get("apply_burn", false)):
			_apply_status_to_targets(
				targets,
				&"burn",
				FIRE_BURN_DURATION_FRAMES,
				base_attack * FIRE_BURN_DAMAGE_MULTIPLIER,
				FIRE_BURN_TICK_INTERVAL_FRAMES
			)
	else:
		_damage_targets(targets, base_attack * float(combo_parameters.get("lightning_damage_multiplier", 0.0)), "lightning")
	_apply_combo_time_damage(targets, combo_parameters)


func _execute_split_explosion(
	origin: Vector2,
	radius_tiles: float,
	damage_multiplier: float,
	combo_parameters: Dictionary
) -> void:
	var targets := _targets_in_radius(origin, radius_tiles)
	var split_value: Variant = combo_parameters.get("damage_split", {})
	var split := split_value as Dictionary if split_value is Dictionary else {}
	_damage_targets(targets, base_attack * damage_multiplier * float(split.get("fire", 0.5)), "fire", origin)
	_damage_targets(targets, base_attack * damage_multiplier * float(split.get("ice", 0.5)), "ice", origin)


func _execute_origin_explosions(
	combo_parameters: Dictionary,
	amount: float,
	damage_element: String,
	status_effect: StringName,
	status_duration_frames: int
) -> void:
	var origins_value: Variant = combo_parameters.get("origin_positions", [])
	if not origins_value is Array:
		return
	var radius_tiles := float(combo_parameters.get("radius_tiles", 0.0))
	for origin_value: Variant in origins_value as Array:
		if not origin_value is Vector2:
			continue
		var targets := _targets_in_radius(origin_value as Vector2, radius_tiles)
		_damage_targets(targets, amount, damage_element, origin_value as Vector2)
		_apply_combo_time_damage(targets, combo_parameters)
		if status_effect != &"":
			_apply_status_to_targets(targets, status_effect, status_duration_frames, 1.0)


func _maintain_ice_slow() -> void:
	_maintain_transient_status(
		&"slow",
		_targets_in_radius(global_position, float(parameters.get("radius_tiles", 0.0))),
		float(parameters.get("move_speed_multiplier", 1.0)),
		float(parameters.get("attack_speed_multiplier", 1.0))
	)


func _maintain_transient_status(
	effect_id: StringName,
	targets: Array[Node],
	magnitude: float,
	attack_speed_multiplier: float
) -> void:
	var effect_key := str(effect_id)
	var previous_value: Variant = _transient_status_targets.get(effect_key, {})
	var previous := previous_value as Dictionary if previous_value is Dictionary else {}
	var current: Dictionary = {}
	for target: Node in targets:
		var target_id := _stable_target_id(target)
		current[target_id] = target
		_apply_status(target, effect_id, 2, magnitude, 30, attack_speed_multiplier)
	for target_id_value: Variant in previous:
		if current.has(target_id_value):
			continue
		_clear_status(previous[target_id_value] as Node, effect_id)
	_transient_status_targets[effect_key] = current
	var current_ids: Array[int] = []
	for target_id_value: Variant in current:
		current_ids.append(int(target_id_value))
	current_ids.sort()
	_transient_status_target_ids[effect_key] = current_ids


func _clear_transient_status(effect_id: StringName) -> void:
	var effect_key := str(effect_id)
	var targets_value: Variant = _transient_status_targets.get(effect_key, {})
	if targets_value is Dictionary:
		for target_value: Variant in targets_value as Dictionary:
			var target: Variant = (targets_value as Dictionary).get(target_value)
			if typeof(target) == TYPE_OBJECT and is_instance_valid(target):
				_clear_status(target as Node, effect_id)
	_transient_status_targets.erase(effect_key)
	_transient_status_target_ids.erase(effect_key)


func _clear_all_transient_statuses() -> void:
	var effects := _transient_status_target_ids.keys()
	for effect_value: Variant in _transient_status_targets.keys():
		if effect_value not in effects:
			effects.append(effect_value)
	for effect_value: Variant in effects:
		_clear_transient_status(StringName(str(effect_value)))


func _reapply_restored_transient_statuses() -> bool:
	_transient_status_targets.clear()
	for effect_value: Variant in _transient_status_target_ids:
		var effect_id := StringName(str(effect_value))
		var targets: Dictionary = {}
		for target_id_value: Variant in _transient_status_target_ids[effect_value] as Array:
			var target := _target_by_stable_id(int(target_id_value))
			if target == null:
				_rollback_restored_transient_statuses()
				return false
			targets[int(target_id_value)] = target
			var magnitude := 1.0
			var attack_speed_multiplier := 1.0
			if effect_id == &"slow" and mode == "ice_zone":
				magnitude = float(parameters.get("move_speed_multiplier", 1.0))
				attack_speed_multiplier = float(parameters.get("attack_speed_multiplier", 1.0))
			elif effect_id == &"slow" and mode == "combination":
				var combo_parameters := parameters.get("combo_parameters", {}) as Dictionary
				magnitude = float(combo_parameters.get("ice_surface_move_speed_multiplier", 1.0))
				attack_speed_multiplier = magnitude
			if not _apply_status(target, effect_id, 2, magnitude, 30, attack_speed_multiplier):
				_transient_status_targets[str(effect_id)] = targets
				_rollback_restored_transient_statuses()
				return false
		_transient_status_targets[str(effect_id)] = targets
	return true


func _rollback_restored_transient_statuses() -> void:
	for effect_value: Variant in _transient_status_targets:
		var effect_id := StringName(str(effect_value))
		var targets_value: Variant = _transient_status_targets[effect_value]
		if not targets_value is Dictionary:
			continue
		for target_value: Variant in targets_value as Dictionary:
			var target: Variant = (targets_value as Dictionary)[target_value]
			if typeof(target) == TYPE_OBJECT and is_instance_valid(target):
				_clear_status(target as Node, effect_id)
	_transient_status_targets.clear()
	_transient_status_target_ids.clear()


func _target_by_stable_id(target_id: int) -> Node:
	if target_id <= 0 or not is_inside_tree():
		return null
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if candidate != null and is_instance_valid(candidate) and _stable_target_id(candidate) == target_id:
			return candidate
	return null


func _transient_status_ids_snapshot() -> Dictionary:
	var result: Dictionary = {}
	var effects: Array[String] = []
	for effect_value: Variant in _transient_status_target_ids:
		effects.append(str(effect_value))
	effects.sort()
	for effect: String in effects:
		var ids: Array[int] = []
		var ids_value: Variant = _transient_status_target_ids.get(effect, [])
		if ids_value is Array:
			for id_value: Variant in ids_value as Array:
				ids.append(int(id_value))
		ids.sort()
		result[effect] = ids
	return result


func _sorted_string_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _valid_claim_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	var previous := ""
	for item: Variant in value as Array:
		if typeof(item) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var claim := str(item)
		if claim.is_empty() or seen.has(claim) or (not previous.is_empty() and claim <= previous):
			return false
		seen[claim] = true
		previous = claim
	return true


func _valid_transient_status_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for effect_value: Variant in value as Dictionary:
		var effect := str(effect_value)
		if effect.is_empty() or effect != "slow":
			return false
		var ids_value: Variant = (value as Dictionary)[effect_value]
		if not ids_value is Array:
			return false
		var seen: Dictionary = {}
		var previous := 0
		for id_value: Variant in ids_value as Array:
			if typeof(id_value) != TYPE_INT or int(id_value) <= 0 or seen.has(int(id_value)):
				return false
			if not seen.is_empty() and int(id_value) <= previous:
				return false
			seen[int(id_value)] = true
			previous = int(id_value)
	return true


func _apply_status_to_targets(
	targets: Array[Node],
	effect_id: StringName,
	duration_frames: int,
	magnitude: float,
	tick_interval_frames: int = 30,
	attack_speed_multiplier: float = -1.0
) -> void:
	for target: Node in targets:
		_apply_status(
			target,
			effect_id,
			duration_frames,
			magnitude,
			tick_interval_frames,
			attack_speed_multiplier
		)


func _apply_status(
	target: Node,
	effect_id: StringName,
	duration_frames: int,
	magnitude: float,
	tick_interval_frames: int = 30,
	attack_speed_multiplier: float = -1.0
) -> bool:
	if (
		target == null
		or not is_instance_valid(target)
		or status_source_id == &""
		or duration_frames <= 0
		or not target.has_method("apply_elemental_status")
	):
		return false
	if effect_id in [&"freeze", &"blind"] and not _boss_control_is_allowed(target):
		return false
	if effect_id == &"blind" and not _ensure_elemental_blind_seed(target):
		return false
	return bool(target.call(
		"apply_elemental_status",
		effect_id,
		status_source_id,
		generation,
		duration_frames,
		magnitude,
		maxi(1, tick_interval_frames),
		attack_speed_multiplier,
		source,
		owner_entity
	))


func _boss_control_is_allowed(target: Node) -> bool:
	if not target.is_in_group("bosses") or boss_conversion.is_empty():
		return true
	if not target.has_method("get_boss_ui_snapshot"):
		return false
	var snapshot_value: Variant = target.call("get_boss_ui_snapshot")
	if not snapshot_value is Dictionary:
		return false
	var snapshot := snapshot_value as Dictionary
	var phase := str(snapshot.get("phase", ""))
	if phase == "WINDUP" and bool(boss_conversion.get("preserve_committed_active_attack", true)):
		return false
	var conversion_state := "EXPOSED" if bool(snapshot.get("exposed", false)) else phase
	var allowed_value: Variant = boss_conversion.get("allowed_states", ["RECOVERY", "EXPOSED"])
	return allowed_value is Array and conversion_state in (allowed_value as Array)


func _apply_combo_time_damage(targets: Array[Node], combo_parameters: Dictionary) -> void:
	var multiplier := float(combo_parameters.get("time_damage_multiplier", 0.0))
	if multiplier <= 0.0:
		return
	_damage_targets(targets, base_attack * multiplier, "time")


func _restore_time_energy_tick(tick_index: int) -> void:
	var amount := float(parameters.get("time_energy_return_per_tick", 0.0))
	if amount <= 0.0:
		return
	resource_reward_requested.emit(
		action_token,
		generation,
		StringName("staff_ultimate_tick:%d" % tick_index),
		&"time_energy",
		amount
	)


func _clear_status(target: Node, effect_id: StringName) -> void:
	if target == null or not is_instance_valid(target) or not target.has_method("clear_elemental_status"):
		return
	target.call("clear_elemental_status", effect_id, status_source_id, generation)


func _damage_targets_in_radius(
	origin: Vector2,
	radius_tiles: float,
	amount: float,
	damage_element: String
) -> void:
	_damage_targets(_targets_in_radius(origin, radius_tiles), amount, damage_element, origin)


func _damage_targets(
	targets: Array[Node],
	amount: float,
	damage_element: String,
	origin_position: Vector2 = Vector2.INF
) -> void:
	if amount <= 0.0:
		return
	for target: Node in targets:
		_damage_target(target, amount, damage_element, origin_position)


func _damage_target(
	target: Node,
	amount: float,
	damage_element: String,
	origin_position: Vector2 = Vector2.INF
) -> float:
	if target == null or not is_instance_valid(target) or amount <= 0.0:
		return 0.0
	var target_id := _stable_target_id(target)
	if target_id <= 0:
		return 0.0
	var claim := "damage:%d:%s:%d:%s:%d" % [
		outcome_index,
		mode,
		_execution_frame,
		damage_element,
		target_id,
	]
	if _claims.has(claim):
		return 0.0
	_claims[claim] = true
	var damage_type := DamageInfoScript.DamageType.PHYSICAL
	match damage_element:
		"fire":
			damage_type = DamageInfoScript.DamageType.FIRE
		"ice":
			damage_type = DamageInfoScript.DamageType.ICE
		"lightning":
			damage_type = DamageInfoScript.DamageType.LIGHTNING
		"time":
			damage_type = DamageInfoScript.DamageType.TIME
		"void":
			damage_type = DamageInfoScript.DamageType.VOID
	var damage_info = DamageInfoScript.from_plan({
		"run_id": &"runtime",
		"target_id": _damage_target_id(target),
		"hostile_source_id": StringName("player:staff_zone:%d:%d" % [action_token, generation]),
		"attack_generation": maxi(1, generation + _execution_frame),
		"hit_index": outcome_index,
		"action_token": action_token,
		"amount": amount,
		"damage_type": damage_type,
		"source": source,
		"attacker": owner_entity,
		"tags": ["weapon:staff", "action:%s" % source_action_id, "element:%s" % damage_element],
		"source_generation": generation,
	})
	if damage_info == null:
		return 0.0
	var resolved_damage := 0.0
	var hurtbox := target.get_node_or_null("Hurtbox")
	if hurtbox != null and hurtbox.has_method("receive_hit"):
		resolved_damage = float(hurtbox.call("receive_hit", damage_info))
	elif target.has_method("receive_hit"):
		resolved_damage = float(target.call("receive_hit", damage_info))
	else:
		var health := target.get_node_or_null("HealthComponent")
		if health != null and health.has_method("take_damage"):
			resolved_damage = float(health.call("take_damage", damage_info))
	var impact := (target as Node2D).global_position if target is Node2D else global_position
	var origin := origin_position if origin_position != Vector2.INF else global_position
	payload_result.emit(action_token, generation, {
		"type": "damage_resolved",
		"claim_id": claim,
		"descriptor_id": descriptor_id,
		"outcome_index": outcome_index,
		"outcome_id": "%s:%d" % [descriptor_id, outcome_index],
		"execution_frame": _execution_frame,
		"mode": mode,
		"target_id": target_id,
		"element_id": damage_element,
		"element": damage_element,
		"terminal": false,
		"hit": resolved_damage > 0.0,
		"damage": maxf(0.0, resolved_damage),
		"impact_position": impact,
		"origin_position": origin,
	}.duplicate(true))
	return resolved_damage


func _targets_in_radius(origin: Vector2, radius_tiles: float) -> Array[Node]:
	var result: Array[Node] = []
	if not is_inside_tree() or radius_tiles <= 0.0:
		return result
	var maximum_distance_squared := pow(radius_tiles * PIXELS_PER_TILE, 2.0)
	var seen: Dictionary = {}
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if candidate == null or not is_instance_valid(candidate) or not candidate is Node2D:
			continue
		var target_id := _stable_target_id(candidate)
		if target_id <= 0 or seen.has(target_id):
			continue
		if origin.distance_squared_to((candidate as Node2D).global_position) > maximum_distance_squared + 0.001:
			continue
		seen[target_id] = true
		result.append(candidate)
	result.sort_custom(func(left: Node, right: Node) -> bool:
		return _stable_target_id(left) < _stable_target_id(right)
	)
	return result


func _stable_target_id(target: Node) -> int:
	if target.has_meta("stable_target_id"):
		return int(target.get_meta("stable_target_id"))
	var stable_key := _stable_target_key(target)
	if not stable_key.is_empty():
		return maxi(1, _stable_hash(stable_key))
	return target.get_instance_id()


func _damage_target_id(target: Node) -> StringName:
	if target != null and target.has_meta("stable_target_id"):
		var value: Variant = target.get_meta("stable_target_id")
		if typeof(value) == TYPE_INT and int(value) > 0:
			return StringName("target:%d" % int(value))
	for metadata_key: String in ["encounter_spawn_id", "spawn_id"]:
		if target != null and target.has_meta(metadata_key):
			var metadata_value := str(target.get_meta(metadata_key, "")).strip_edges()
			if not metadata_value.is_empty() and metadata_value.length() <= 56:
				return StringName("target:%s" % metadata_value)
	return &"pending_target"


func _ensure_elemental_blind_seed(target: Node) -> bool:
	if target.has_meta("elemental_status_seed_initialized"):
		return true
	if not target.has_method("configure_elemental_status_seed"):
		return false
	var target_key := _stable_target_key(target)
	if target_key.is_empty():
		return false
	var resolved_seed := _stable_hash("%d|%s" % [deterministic_seed, target_key])
	target.call("configure_elemental_status_seed", resolved_seed, 0.30)
	target.set_meta("elemental_status_seed_initialized", resolved_seed)
	target.set_meta("elemental_status_seed_material", target_key)
	return true


func _stable_target_key(target: Node) -> String:
	if target.has_meta("stable_target_id"):
		return "stable:%s" % str(target.get_meta("stable_target_id"))
	for metadata_key: String in ["encounter_spawn_id", "spawn_id"]:
		if target.has_meta(metadata_key):
			var metadata_value := str(target.get_meta(metadata_key, ""))
			if not metadata_value.is_empty():
				return "%s:%s" % [metadata_key, metadata_value]
	if target.is_inside_tree():
		var path := str(target.get_path())
		if not path.is_empty():
			return "path:%s" % path
	return ""


func _stable_hash(material: String) -> int:
	var value := 0
	for index: int in range(material.length()):
		value = int((value * 131 + material.unicode_at(index)) % 2147483647)
	return value


func _exit_tree() -> void:
	_clear_all_transient_statuses()


func _positive_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


func _non_negative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0
