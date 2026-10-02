class_name DungeonEventSelector
extends RefCounted

const SeedServiceScript := preload("res://scripts/core/seed_service.gd")

const SPECIAL_PRIORITY: Array[String] = [
	"event_void_whispers",
	"event_perfect_rewind",
	"event_old_reunion",
]
const REPEAT_POLICIES: Array[String] = ["once_per_run", "once_per_floor", "repeatable"]
const PREDICATE_IDS: Array[String] = [
	"always",
	"low_health",
	"has_curse",
	"no_curse",
	"rich",
	"poor",
	"perfect_rewind_available",
	"old_reunion_eligible",
]
const LOW_HEALTH_RATIO := 0.30
const RICH_GOLD_MIN := 200
const POOR_GOLD_MAX := 50


func select(event_definitions: Array, context: Dictionary) -> Dictionary:
	var channel := _selection_channel(context)
	var predicate_facts: Dictionary = {}
	var eligible_specials: Dictionary = {}
	var eligible_regulars: Array[Dictionary] = []
	for value: Variant in event_definitions:
		if not value is Dictionary:
			continue
		var definition := value as Dictionary
		if not _has_selection_fields(definition):
			continue
		var event_id := str(definition["id"])
		var predicate_fact := _predicate_fact(
			str(definition["trigger_predicate_id"]),
			context
		)
		predicate_facts[event_id] = predicate_fact
		if not _definition_is_eligible(definition, context, predicate_fact):
			continue
		if bool(definition["special"]):
			eligible_specials[event_id] = definition
		else:
			eligible_regulars.append(definition)

	var ordered_special_ids: Array[String] = []
	for event_id: String in SPECIAL_PRIORITY:
		if eligible_specials.has(event_id):
			ordered_special_ids.append(event_id)
	var ordered_regulars := _ordered_regulars(eligible_regulars, str(context.get("primary_event_id", "")))
	var eligible_ids := ordered_special_ids.duplicate()
	for definition: Dictionary in ordered_regulars:
		eligible_ids.append(str(definition["id"]))

	if not ordered_special_ids.is_empty():
		return _success(
			ordered_special_ids[0],
			channel,
			-1,
			eligible_ids,
			predicate_facts
		)
	if ordered_regulars.is_empty():
		return {
			"ok": false,
			"code": &"NO_ELIGIBLE_EVENT",
			"event_id": "",
			"channel": channel,
			"roll": -1,
			"eligible_ids": [],
			"predicate_facts": predicate_facts,
			"context": {},
		}

	var total_weight := 0
	for definition: Dictionary in ordered_regulars:
		total_weight += int(definition["weight"])
	if total_weight <= 0:
		return {
			"ok": false,
			"code": &"NO_ELIGIBLE_EVENT",
			"event_id": "",
			"channel": channel,
			"roll": -1,
			"eligible_ids": [],
			"predicate_facts": predicate_facts,
			"context": {},
		}
	var roll := posmod(
		SeedServiceScript.derive_seed(
			int(context.get("run_seed", 0)),
			StringName(channel),
			int(context.get("floor_index", 0)),
			0,
			0
		),
		total_weight
	)
	var cursor := 0
	for definition: Dictionary in ordered_regulars:
		cursor += int(definition["weight"])
		if roll < cursor:
			return _success(
				str(definition["id"]),
				channel,
				roll,
				eligible_ids,
				predicate_facts
			)
	return {
		"ok": false,
		"code": &"NO_ELIGIBLE_EVENT",
		"event_id": "",
		"channel": channel,
		"roll": -1,
		"eligible_ids": [],
		"predicate_facts": predicate_facts,
		"context": {},
	}


func _has_selection_fields(definition: Dictionary) -> bool:
	for field: String in [
		"id", "availability", "special", "floor_min", "floor_max", "weight",
		"repeat_policy", "trigger_predicate_id",
	]:
		if not definition.has(field):
			return false
	return (
		typeof(definition["id"]) == TYPE_STRING
		and not str(definition["id"]).is_empty()
		and definition["availability"] is Array
		and typeof(definition["special"]) == TYPE_BOOL
		and _integer_number(definition["floor_min"])
		and _integer_number(definition["floor_max"])
		and _integer_number(definition["weight"])
		and int(definition["weight"]) > 0
		and typeof(definition["repeat_policy"]) == TYPE_STRING
		and REPEAT_POLICIES.has(str(definition["repeat_policy"]))
		and typeof(definition["trigger_predicate_id"]) == TYPE_STRING
		and PREDICATE_IDS.has(str(definition["trigger_predicate_id"]))
	)


func _definition_is_eligible(
	definition: Dictionary,
	context: Dictionary,
	predicate_fact: Dictionary
) -> bool:
	if not (definition["availability"] as Array).has(str(context.get("availability", ""))):
		return false
	var floor_index_value: Variant = context.get("floor_index", null)
	if typeof(floor_index_value) != TYPE_INT:
		return false
	var floor_index := int(floor_index_value)
	if floor_index < 0 or floor_index > 4:
		return false
	var authored_floor_number := floor_index + 1
	if (
		authored_floor_number < int(definition["floor_min"])
		or authored_floor_number > int(definition["floor_max"])
	):
		return false
	var event_id := str(definition["id"])
	match str(definition["repeat_policy"]):
		"once_per_run":
			if _string_array(context.get("seen_run_event_ids", [])).has(event_id):
				return false
		"once_per_floor":
			var floor_key := "%s:%s" % [str(context.get("floor_id", "")), event_id]
			if _string_array(context.get("seen_floor_event_keys", [])).has(floor_key):
				return false
	return bool(predicate_fact.get("eligible", false))


func _ordered_regulars(
	definitions: Array[Dictionary],
	primary_event_id: String
) -> Array[Dictionary]:
	var ordered := definitions.duplicate(true)
	ordered.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_id := str(a["id"])
			var b_id := str(b["id"])
			if a_id == primary_event_id:
				return b_id != primary_event_id
			if b_id == primary_event_id:
				return false
			return a_id < b_id
	)
	return ordered


func _predicate_fact(predicate_id: String, context: Dictionary) -> Dictionary:
	var eligible := false
	var facts: Dictionary = {}
	match predicate_id:
		"always":
			eligible = true
		"low_health":
			var health := context.get("health", {}) as Dictionary
			var maximum := float(health.get("maximum", 0.0))
			var ratio := float(health.get("current", maximum)) / maximum if maximum > 0.0 else 1.0
			facts = {"ratio": ratio, "maximum_ratio": LOW_HEALTH_RATIO}
			eligible = ratio <= LOW_HEALTH_RATIO
		"has_curse":
			var curse_ids := _curse_ids(context)
			facts = {"curse_count": curse_ids.size()}
			eligible = not curse_ids.is_empty()
		"no_curse":
			var curse_ids := _curse_ids(context)
			facts = {"curse_count": curse_ids.size()}
			eligible = curse_ids.is_empty()
		"rich":
			var gold := _gold(context)
			facts = {"gold": gold, "minimum": RICH_GOLD_MIN}
			eligible = gold >= RICH_GOLD_MIN
		"poor":
			var gold := _gold(context)
			facts = {"gold": gold, "maximum": POOR_GOLD_MAX}
			eligible = gold <= POOR_GOLD_MAX
		"perfect_rewind_available":
			var meta := context.get("meta", {}) as Dictionary
			eligible = bool(meta.get("perfect_rewind_available", false))
			facts = {"value": eligible}
		"old_reunion_eligible":
			var meta := context.get("meta", {}) as Dictionary
			eligible = bool(meta.get("old_reunion_eligible", false))
			facts = {"value": eligible}
	return {
		"predicate_id": predicate_id,
		"eligible": eligible,
		"facts": facts,
	}


func _gold(context: Dictionary) -> int:
	return int((context.get("economy", {}) as Dictionary).get("gold", 0))


func _curse_ids(context: Dictionary) -> Array[String]:
	var build := context.get("build", {}) as Dictionary
	return _string_array(build.get("curse_ids", []))


func _string_array(value: Variant) -> Array[String]:
	var strings: Array[String] = []
	if not value is Array:
		return strings
	for entry: Variant in value:
		if typeof(entry) == TYPE_STRING:
			strings.append(str(entry))
	return strings


func _integer_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == floorf(float(value))
	)


func _selection_channel(context: Dictionary) -> String:
	return "event_selection_v1:%s:%s" % [
		str(context.get("floor_id", "")),
		str(context.get("node_id", "")),
	]


func _success(
	event_id: String,
	channel: String,
	roll: int,
	eligible_ids: Array[String],
	predicate_facts: Dictionary
) -> Dictionary:
	return {
		"ok": true,
		"code": &"OK",
		"event_id": event_id,
		"channel": channel,
		"roll": roll,
		"eligible_ids": eligible_ids.duplicate(),
		"predicate_facts": predicate_facts.duplicate(true),
		"context": {},
	}
