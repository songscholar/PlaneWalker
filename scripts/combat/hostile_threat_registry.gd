class_name HostileThreatRegistry
extends RefCounted

const HostileTelegraphFactScript := preload("res://scripts/combat/hostile_telegraph_fact.gd")

var _facts_by_key: Dictionary = {}


func register_fact(value: Variant) -> bool:
	var fact: Dictionary = HostileTelegraphFactScript.create(value)
	if fact.is_empty():
		return false
	var key := HostileTelegraphFactScript.identity_key(fact)
	if key.is_empty() or _facts_by_key.has(key):
		return false
	_facts_by_key[key] = fact.duplicate(true)
	return true


func retire(hostile_source_id: StringName, attack_generation: int) -> bool:
	var key := _identity_key(hostile_source_id, attack_generation)
	if key.is_empty() or not _facts_by_key.has(key):
		return false
	_facts_by_key.erase(key)
	return true


func extend_fact_through(
	hostile_source_id: StringName,
	attack_generation: int,
	expected_through_frame: int,
	new_through_frame: int
) -> bool:
	var key := _identity_key(hostile_source_id, attack_generation)
	if key.is_empty() or not _facts_by_key.has(key) or new_through_frame <= expected_through_frame:
		return false
	var fact: Dictionary = _facts_by_key[key]
	if int(fact["active_through_frame"]) != expected_through_frame:
		return false
	var extended := fact.duplicate(true)
	extended["active_through_frame"] = new_through_frame
	var validated: Dictionary = HostileTelegraphFactScript.create(extended)
	if validated.is_empty():
		return false
	_facts_by_key[key] = validated
	return true


func retire_source(hostile_source_id: StringName) -> int:
	if hostile_source_id == &"":
		return 0
	var retired := 0
	for key_value: Variant in _facts_by_key.keys():
		var fact := _facts_by_key[key_value] as Dictionary
		if StringName(str(fact["hostile_source_id"])) == hostile_source_id:
			_facts_by_key.erase(key_value)
			retired += 1
	return retired


func clear() -> void:
	_facts_by_key.clear()


func fact_snapshot(hostile_source_id: StringName, attack_generation: int) -> Dictionary:
	var key := _identity_key(hostile_source_id, attack_generation)
	if key.is_empty() or not _facts_by_key.has(key):
		return {}
	return (_facts_by_key[key] as Dictionary).duplicate(true)


func snapshot() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var keys: Array = _facts_by_key.keys()
	keys.sort()
	for key_value: Variant in keys:
		rows.append((_facts_by_key[key_value] as Dictionary).duplicate(true))
	return rows


func contains_point(point: Vector2, runtime_frame: int) -> bool:
	return nearest_threat_distance(point, runtime_frame) <= 0.0


func nearest_threat_distance(point: Vector2, runtime_frame: int) -> float:
	if not _finite_vector(point) or runtime_frame < 0:
		return INF
	var nearest := INF
	for fact_value: Variant in _facts_by_key.values():
		var fact := fact_value as Dictionary
		if not _is_active(fact, runtime_frame):
			continue
		nearest = minf(nearest, _distance_to_fact(point, fact))
	return nearest


func _distance_to_fact(point: Vector2, fact: Dictionary) -> float:
	var shape := str(fact["shape"])
	var origin := fact["origin"] as Vector2
	var radius := float(fact["radius"])
	match shape:
		"circle", "ring":
			return maxf(0.0, point.distance_to(origin) - radius)
		"target_circle":
			return maxf(0.0, point.distance_to(fact["target_point"] as Vector2) - radius)
		"summon_slots":
			var nearest := INF
			for slot: Vector2 in fact["summon_slots"] as Array:
				nearest = minf(nearest, maxf(0.0, point.distance_to(slot) - radius))
			return nearest
		"line":
			var endpoint := origin + (fact["aim_direction"] as Vector2) * float(fact["length"])
			return maxf(0.0, _distance_to_segment(point, origin, endpoint) - radius)
		"rift":
			var endpoint := fact["target_point"] as Vector2
			if endpoint.is_equal_approx(origin):
				endpoint = origin + (fact["aim_direction"] as Vector2) * float(fact["length"])
			return maxf(0.0, _distance_to_segment(point, origin, endpoint) - radius)
		"cone":
			return _distance_to_cone(point, fact)
	return INF


func _distance_to_cone(point: Vector2, fact: Dictionary) -> float:
	var origin := fact["origin"] as Vector2
	var direction := fact["aim_direction"] as Vector2
	var length := float(fact["length"])
	var endpoint_radius := float(fact["radius"])
	var relative := point - origin
	var forward := relative.dot(direction)
	if forward < 0.0:
		return relative.length()
	if forward > length:
		return point.distance_to(origin + direction * length)
	var lateral := absf(relative.dot(direction.orthogonal()))
	var allowed := endpoint_radius * (forward / length)
	return maxf(0.0, lateral - allowed)


func _is_active(fact: Dictionary, runtime_frame: int) -> bool:
	return (
		runtime_frame >= int(fact["active_from_frame"])
		and runtime_frame <= int(fact["active_through_frame"])
	)


func _identity_key(hostile_source_id: StringName, attack_generation: int) -> String:
	if hostile_source_id == &"" or attack_generation <= 0:
		return ""
	return "%s#%d" % [str(hostile_source_id), attack_generation]


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
