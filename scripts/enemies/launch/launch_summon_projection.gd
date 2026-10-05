class_name LaunchSummonProjection
extends RefCounted

const Definition := preload("res://scripts/enemies/launch/summon_definition.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const SAFE_HANDLERS := ["melee", "charge", "projectile_volley", "zone", "blink"]


static func create(source: Dictionary, parent: Dictionary = {}) -> Dictionary:
	var parser := Definition.new()
	if not parser.configure(source).ok:
		return _failure()
	var summon := parser.snapshot()
	var action := _attack(summon)
	var hp := float(summon.max_hp)
	var speed := float(summon.move_speed)
	var bound_parent := {}
	var harmless := false
	if summon.id == "elite_mirror":
		if not Ids.ENEMY_FLOORS.has(parent.get("id")) or parent.get("actor_kind") != "enemy" or not Contract.number_in_range(parent.get("max_hp"), 1.0, 1000000.0) or not parent.get("actions") is Array:
			return _failure()
		bound_parent = parent.duplicate(true)
		hp = maxf(1.0, float(parent.max_hp) * float(summon.hp_fraction))
		speed = float(parent.move_speed)
		harmless = true
		for candidate: Dictionary in parent.actions:
			if not candidate.hit_schedule.any(func(hit: Dictionary): return float(hit.damage) > 0.0):
				continue
			if candidate.handler_id not in SAFE_HANDLERS:
				return _failure()
			action = candidate.duplicate(true)
			action.id = "elite_mirror.attack"
			action.warning_frames = maxi(int(action.warning_frames), int(summon.attack_warning_frames))
			action.cue_id = "hostile_elite_mirror_attack"
			for hit: Dictionary in action.hit_schedule:
				hit.damage = float(hit.damage) * float(summon.damage_multiplier)
			harmless = false
			break
		if harmless:
			action.geometry = []
			action.hit_schedule = []
	var parsed: Dictionary = Contract.create(action, "summon")
	if not parsed.ok:
		return _failure()
	return {"ok": true, "definition": {"id": summon.id, "actor_kind": "summon", "runtime_kind": summon.id, "max_hp": hp, "defense": 0.0, "move_speed": speed, "collision_radius_px": float(summon.collision_radius_px), "actions": [parsed.definition], "mechanisms": {"harmless": harmless}, "summon_contract": {"definition": summon, "parent": bound_parent}}}


static func _attack(summon: Dictionary) -> Dictionary:
	var kind := str(summon.attack.kind)
	if kind == "parent_first_damaging":
		kind = "melee"
	var parameters := {"knockback_px": 0.0}
	if kind == "charge":
		parameters = {"travel_px": float(summon.attack.range_px), "speed_px_per_second": float(summon.move_speed), "knockback_px": 0.0}
	elif kind == "projectile_volley":
		parameters = {"speed_px_per_second": 128.0, "lifetime_frames": ceili(float(summon.attack.range_px) * 60.0 / 128.0), "pierce_count": 0}
	return {"id": str(summon.id) + ".attack", "handler_id": kind, "warning_frames": int(summon.attack_warning_frames), "active_frames": int(summon.attack.active_frames), "recovery_frames": int(summon.attack.recovery_frames), "idle_frames": 15, "cooldown_frames": int(summon.attack.cooldown_frames), "weight": 10, "max_consecutive": 1, "distance_min_px": 0.0, "distance_max_px": float(summon.attack.range_px), "geometry": [{"shape": "circle" if kind == "melee" else "line", "origin_offset": {"x": 0.0, "y": 0.0}, "aim_offset_degrees": 0.0, "radius": float(summon.attack.range_px) if kind == "melee" else 4.0, "length": float(summon.attack.range_px) if kind != "melee" else 0.0}], "hit_schedule": [{"offset_frame": 0, "hit_index": 0, "damage": float(summon.damage), "damage_type": "void"}], "parameters": parameters, "cue_id": "hostile_" + str(summon.id) + "_attack"}


static func _failure() -> Dictionary:
	return {"ok": false, "code": &"SUMMON_PROJECTION_INVALID"}
