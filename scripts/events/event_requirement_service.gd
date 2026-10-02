class_name EventRequirementService
extends RefCounted

const OPERATIONS: Array[String] = [
	"resource_min",
	"health_min",
	"health_max_ratio",
	"gold_min",
	"has_reward_tag",
	"lacks_curse",
	"narrative_flag",
	"floor_index_min",
]


func evaluate(requirements: Array, context: Dictionary) -> Dictionary:
	var context_error := _context_error(context)
	if not context_error.is_empty():
		return _failure(&"INVALID_CONTEXT", context_error)
	var facts: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	for index: int in range(requirements.size()):
		var value: Variant = requirements[index]
		if not value is Dictionary:
			return _failure(&"INVALID_REQUIREMENT", {"index": index, "field": "requirement"})
		var requirement := value as Dictionary
		var validation := _requirement_error(requirement)
		if not validation.is_empty():
			validation["index"] = index
			return _failure(&"INVALID_REQUIREMENT", validation)
		var fact := _evaluate_one(
			index,
			str(requirement["operation"]),
			requirement["arguments"] as Dictionary,
			context
		)
		facts.append(fact)
		if not bool(fact["passed"]):
			failures.append(fact.duplicate(true))
	return {
		"ok": true,
		"code": &"OK",
		"eligible": failures.is_empty(),
		"facts": facts,
		"failures": failures,
		"context": {},
	}


func _evaluate_one(
	index: int,
	operation: String,
	arguments: Dictionary,
	context: Dictionary
) -> Dictionary:
	var actual: Variant
	var required: Variant
	var passed := false
	match operation:
		"resource_min":
			var resources := context["resources"] as Dictionary
			actual = int(resources.get(str(arguments["resource"]), 0))
			required = int(arguments["amount"])
			passed = int(actual) >= int(required)
		"health_min":
			actual = float((context["health"] as Dictionary)["current"])
			required = float(arguments["amount"])
			passed = float(actual) >= float(required)
		"health_max_ratio":
			var health := context["health"] as Dictionary
			actual = float(health["current"]) / float(health["maximum"])
			required = float(arguments["ratio"])
			passed = float(actual) <= float(required)
		"gold_min":
			actual = int(context["gold"])
			required = int(arguments["amount"])
			passed = int(actual) >= int(required)
		"has_reward_tag":
			actual = str(arguments["tag"])
			required = true
			passed = (context["reward_tags"] as Array).has(actual)
		"lacks_curse":
			actual = str(arguments["curse_id"])
			required = false
			passed = not (context["curse_ids"] as Array).has(actual)
		"narrative_flag":
			actual = (context["narrative_flags"] as Dictionary).get(
				str(arguments["flag"]),
				null
			)
			required = bool(arguments["value"])
			passed = typeof(actual) == TYPE_BOOL and bool(actual) == bool(required)
		"floor_index_min":
			actual = int(context["floor_index"])
			required = int(arguments["value"])
			passed = int(actual) >= int(required)
	return {
		"index": index,
		"operation": operation,
		"passed": passed,
		"actual": actual,
		"required": required,
		"reason_code": &"" if passed else StringName("EVENT_REQUIREMENT_%s" % operation.to_upper()),
	}


func _requirement_error(value: Dictionary) -> Dictionary:
	if _sorted_keys(value) != ["arguments", "operation"]:
		return {"field": "fields"}
	if typeof(value.get("operation")) != TYPE_STRING:
		return {"field": "operation"}
	var operation := str(value["operation"])
	if not OPERATIONS.has(operation) or not value.get("arguments") is Dictionary:
		return {"field": "operation" if not OPERATIONS.has(operation) else "arguments"}
	var arguments := value["arguments"] as Dictionary
	match operation:
		"resource_min":
			if (
				_sorted_keys(arguments) != ["amount", "resource"]
				or not _valid_id(arguments.get("resource"))
				or not _nonnegative_integer(arguments.get("amount"))
			):
				return {"field": "arguments"}
		"health_min":
			if _sorted_keys(arguments) != ["amount"] or not _nonnegative_number(arguments.get("amount")):
				return {"field": "arguments"}
		"health_max_ratio":
			if _sorted_keys(arguments) != ["ratio"] or not _ratio(arguments.get("ratio")):
				return {"field": "arguments"}
		"gold_min":
			if _sorted_keys(arguments) != ["amount"] or not _nonnegative_integer(arguments.get("amount")):
				return {"field": "arguments"}
		"has_reward_tag":
			if _sorted_keys(arguments) != ["tag"] or not _valid_id(arguments.get("tag")):
				return {"field": "arguments"}
		"lacks_curse":
			if _sorted_keys(arguments) != ["curse_id"] or not _valid_id(arguments.get("curse_id")):
				return {"field": "arguments"}
		"narrative_flag":
			if (
				_sorted_keys(arguments) != ["flag", "value"]
				or not _valid_id(arguments.get("flag"))
				or typeof(arguments.get("value")) != TYPE_BOOL
			):
				return {"field": "arguments"}
		"floor_index_min":
			if (
				_sorted_keys(arguments) != ["value"]
				or typeof(arguments.get("value")) != TYPE_INT
				or int(arguments["value"]) < 1
				or int(arguments["value"]) > 5
			):
				return {"field": "arguments"}
	return {}


func _context_error(context: Dictionary) -> Dictionary:
	for field: String in [
		"resources", "health", "gold", "reward_tags", "curse_ids",
		"narrative_flags", "floor_index",
	]:
		if not context.has(field):
			return {"field": field}
	if (
		not context["resources"] is Dictionary
		or not context["health"] is Dictionary
		or not context["reward_tags"] is Array
		or not context["curse_ids"] is Array
		or not context["narrative_flags"] is Dictionary
		or typeof(context["gold"]) != TYPE_INT
		or int(context["gold"]) < 0
		or typeof(context["floor_index"]) != TYPE_INT
		or int(context["floor_index"]) < 1
		or int(context["floor_index"]) > 5
	):
		return {"field": "context"}
	var health := context["health"] as Dictionary
	if (
		_sorted_keys(health) != ["current", "maximum"]
		or not _nonnegative_number(health.get("current"))
		or not _positive_number(health.get("maximum"))
		or float(health["current"]) > float(health["maximum"])
	):
		return {"field": "health"}
	for amount: Variant in (context["resources"] as Dictionary).values():
		if not _nonnegative_integer(amount):
			return {"field": "resources"}
	for values: Array in [context["reward_tags"] as Array, context["curse_ids"] as Array]:
		var seen: Dictionary = {}
		for entry: Variant in values:
			if not _valid_id(entry) or seen.has(str(entry)):
				return {"field": "identity_list"}
			seen[str(entry)] = true
	for value: Variant in (context["narrative_flags"] as Dictionary).values():
		if typeof(value) != TYPE_BOOL:
			return {"field": "narrative_flags"}
	return {}


func _nonnegative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


func _nonnegative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


func _positive_number(value: Variant) -> bool:
	return _nonnegative_number(value) and float(value) > 0.0


func _ratio(value: Variant) -> bool:
	return _nonnegative_number(value) and float(value) <= 1.0


func _valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).is_empty() or str(value).length() > 96:
		return false
	var regex := RegEx.new()
	return regex.compile("^[a-z0-9][a-z0-9_.:-]{0,95}$") == OK and regex.search(str(value)) != null


func _sorted_keys(value: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key_value: Variant in value.keys():
		keys.append(str(key_value))
	keys.sort()
	return keys


func _failure(code: StringName, context: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"eligible": false,
		"facts": [],
		"failures": [],
		"context": context.duplicate(true),
	}
