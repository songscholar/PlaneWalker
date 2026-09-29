class_name ContentPackResolver
extends RefCounted

const ValidationReportScript := preload("res://scripts/content/content_validation_report.gd")


func resolve(descriptors: Array, game_version: String):
	var report = ValidationReportScript.new()
	_set_resolution_metadata(report, [], [], [])
	var grouped: Dictionary = {}
	for descriptor_value: Variant in descriptors:
		if not descriptor_value is Dictionary:
			report.add_error("Content pack descriptor must be a dictionary", {}, true)
			continue
		var descriptor: Dictionary = (descriptor_value as Dictionary).duplicate(true)
		var pack_id := str(descriptor.get("pack_id", ""))
		if pack_id.is_empty():
			report.add_error(
				"Content pack descriptor has no pack id",
				{"descriptor": descriptor},
				bool(descriptor.get("required_pack", false))
			)
			continue
		if not grouped.has(pack_id):
			grouped[pack_id] = []
		(grouped[pack_id] as Array).append(descriptor)

	var descriptor_map: Dictionary = {}
	var isolated: Dictionary = {}
	var duplicate_ids: Array = grouped.keys()
	duplicate_ids.sort()
	for pack_id_value: Variant in duplicate_ids:
		var pack_id := str(pack_id_value)
		var group: Array = grouped[pack_id]
		if group.size() > 1:
			var blocks := false
			for duplicate_value: Variant in group:
				blocks = blocks or bool((duplicate_value as Dictionary).get("required_pack", false))
			report.add_error(
				"Duplicate content pack id",
				{"pack_id": pack_id, "count": group.size()},
				blocks
			)
			isolated[pack_id] = true
			continue
		descriptor_map[pack_id] = (group[0] as Dictionary).duplicate(true)

	if report.has_blocking_errors():
		_set_resolution_metadata(report, [], _sorted_keys(isolated), [])
		return report

	var pack_ids: Array = descriptor_map.keys()
	pack_ids.sort()
	for pack_id_value: Variant in pack_ids:
		var pack_id := str(pack_id_value)
		var descriptor: Dictionary = descriptor_map[pack_id]
		if not _version_satisfies(game_version, str(descriptor.get("game_version_range", ""))):
			_reject_pack(
				report,
				descriptor,
				isolated,
				"Content pack is incompatible with this game version",
				{"pack_id": pack_id, "game_version": game_version, "required_range": descriptor.get("game_version_range", "")}
			)

	_propagate_dependency_failures(report, descriptor_map, isolated)
	if report.has_blocking_errors():
		_set_resolution_metadata(report, [], _sorted_keys(isolated), [])
		return report

	var order_result := _topological_order(descriptor_map, isolated)
	var cycle_ids: Array[String] = order_result["cycle_ids"]
	if not cycle_ids.is_empty():
		var cycle_blocks := false
		for pack_id: String in cycle_ids:
			cycle_blocks = cycle_blocks or bool((descriptor_map[pack_id] as Dictionary).get("required_pack", false))
		for pack_id: String in cycle_ids:
			isolated[pack_id] = true
		report.add_error(
			"Content pack dependency cycle detected",
			{"pack_ids": cycle_ids.duplicate()},
			cycle_blocks
		)
		if cycle_blocks:
			_set_resolution_metadata(report, [], _sorted_keys(isolated), [])
			return report
		_propagate_dependency_failures(report, descriptor_map, isolated)
		if report.has_blocking_errors():
			_set_resolution_metadata(report, [], _sorted_keys(isolated), [])
			return report
		order_result = _topological_order(descriptor_map, isolated)

	var activation_order: Array[String] = order_result["order"]
	var active_descriptors: Array[Dictionary] = []
	for pack_id: String in activation_order:
		active_descriptors.append((descriptor_map[pack_id] as Dictionary).duplicate(true))
	report.loaded_count = active_descriptors.size()
	_set_resolution_metadata(report, activation_order, _sorted_keys(isolated), active_descriptors)
	return report


func _propagate_dependency_failures(report, descriptor_map: Dictionary, isolated: Dictionary) -> void:
	var changed := true
	while changed:
		changed = false
		var pack_ids: Array = descriptor_map.keys()
		pack_ids.sort()
		for pack_id_value: Variant in pack_ids:
			var pack_id := str(pack_id_value)
			if isolated.has(pack_id):
				continue
			var descriptor: Dictionary = descriptor_map[pack_id]
			for dependency_value: Variant in descriptor.get("dependencies", []):
				if not dependency_value is Dictionary:
					_reject_pack(report, descriptor, isolated, "Content pack dependency record is invalid", {"pack_id": pack_id})
					changed = true
					break
				var dependency: Dictionary = dependency_value
				var dependency_id := str(dependency.get("pack_id", ""))
				if not bool(dependency.get("required", true)) and (not descriptor_map.has(dependency_id) or isolated.has(dependency_id)):
					continue
				if not descriptor_map.has(dependency_id) or isolated.has(dependency_id):
					_reject_pack(
						report,
						descriptor,
						isolated,
						"Content pack dependency is unavailable",
						{"pack_id": pack_id, "dependency_id": dependency_id}
					)
					changed = true
					break
				var dependency_descriptor: Dictionary = descriptor_map[dependency_id]
				if not _version_satisfies(str(dependency_descriptor.get("pack_version", "")), str(dependency.get("version_range", ""))):
					_reject_pack(
						report,
						descriptor,
						isolated,
						"Content pack dependency version is incompatible",
						{
							"pack_id": pack_id,
							"dependency_id": dependency_id,
							"dependency_version": dependency_descriptor.get("pack_version", ""),
							"required_range": dependency.get("version_range", ""),
						}
					)
					changed = true
					break


func _reject_pack(
	report,
	descriptor: Dictionary,
	isolated: Dictionary,
	message: String,
	context: Dictionary
) -> void:
	var pack_id := str(descriptor.get("pack_id", ""))
	var blocking := bool(descriptor.get("required_pack", false))
	report.add_error(message, context, blocking)
	isolated[pack_id] = true


func _topological_order(descriptor_map: Dictionary, isolated: Dictionary) -> Dictionary:
	var indegree: Dictionary = {}
	var dependants: Dictionary = {}
	for pack_id_value: Variant in descriptor_map.keys():
		var pack_id := str(pack_id_value)
		if isolated.has(pack_id):
			continue
		indegree[pack_id] = 0
		dependants[pack_id] = []
	for pack_id_value: Variant in indegree.keys():
		var pack_id := str(pack_id_value)
		var descriptor: Dictionary = descriptor_map[pack_id]
		for dependency_value: Variant in descriptor.get("dependencies", []):
			var dependency: Dictionary = dependency_value
			var dependency_id := str(dependency.get("pack_id", ""))
			if not indegree.has(dependency_id):
				continue
			indegree[pack_id] = int(indegree[pack_id]) + 1
			(dependants[dependency_id] as Array).append(pack_id)

	var available: Array[String] = []
	for pack_id_value: Variant in indegree.keys():
		var pack_id := str(pack_id_value)
		if int(indegree[pack_id]) == 0:
			available.append(pack_id)
	_sort_pack_ids(available, descriptor_map)
	var order: Array[String] = []
	while not available.is_empty():
		var pack_id: String = available.pop_front()
		order.append(pack_id)
		var child_ids: Array = dependants[pack_id]
		child_ids.sort()
		for child_value: Variant in child_ids:
			var child_id := str(child_value)
			indegree[child_id] = int(indegree[child_id]) - 1
			if int(indegree[child_id]) == 0:
				available.append(child_id)
		_sort_pack_ids(available, descriptor_map)

	var cycle_ids: Array[String] = []
	for pack_id_value: Variant in indegree.keys():
		var pack_id := str(pack_id_value)
		if not order.has(pack_id):
			cycle_ids.append(pack_id)
	cycle_ids.sort()
	return {"order": order, "cycle_ids": cycle_ids}


func _sort_pack_ids(pack_ids: Array[String], descriptor_map: Dictionary) -> void:
	pack_ids.sort_custom(
		func(left: String, right: String) -> bool:
			var left_order := int((descriptor_map[left] as Dictionary).get("load_order", 0))
			var right_order := int((descriptor_map[right] as Dictionary).get("load_order", 0))
			if left_order == right_order:
				return left < right
			return left_order < right_order
	)


func _version_satisfies(version: String, version_range: String) -> bool:
	var parsed_version := _parse_version(version)
	if parsed_version.is_empty() or version_range.strip_edges().is_empty():
		return false
	if version_range.strip_edges() == "*":
		return true
	for token_value: Variant in version_range.split(" ", false):
		var token := str(token_value).strip_edges()
		if token.is_empty():
			continue
		var operator := "="
		var expected_text := token
		for candidate: String in [">=", "<=", ">", "<", "="]:
			if token.begins_with(candidate):
				operator = candidate
				expected_text = token.substr(candidate.length())
				break
		var expected := _parse_version(expected_text)
		if expected.is_empty():
			return false
		var comparison := _compare_versions(parsed_version, expected)
		match operator:
			">=":
				if comparison < 0:
					return false
			"<=":
				if comparison > 0:
					return false
			">":
				if comparison <= 0:
					return false
			"<":
				if comparison >= 0:
					return false
			_:
				if comparison != 0:
					return false
	return true


func _parse_version(value: String) -> Array[int]:
	var core := value.strip_edges().get_slice("-", 0)
	var parts := core.split(".", false)
	if parts.size() != 3:
		return []
	var parsed: Array[int] = []
	for part_value: Variant in parts:
		var part := str(part_value)
		if not part.is_valid_int() or int(part) < 0:
			return []
		parsed.append(int(part))
	return parsed


func _compare_versions(left: Array[int], right: Array[int]) -> int:
	for index: int in range(3):
		if left[index] < right[index]:
			return -1
		if left[index] > right[index]:
			return 1
	return 0


func _set_resolution_metadata(
	report,
	activation_order: Array,
	isolated_pack_ids: Array,
	active_descriptors: Array
) -> void:
	report.set_meta("activation_order", activation_order.duplicate())
	report.set_meta("isolated_pack_ids", isolated_pack_ids.duplicate())
	report.set_meta("active_descriptors", active_descriptors.duplicate(true))


func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values.keys():
		result.append(str(value))
	result.sort()
	return result
