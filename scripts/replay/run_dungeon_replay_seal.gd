class_name RunDungeonReplaySeal
extends RefCounted

const ContentSnapshotProviderScript := preload(
	"res://scripts/content/content_snapshot_provider.gd"
)
const FloorDefinitionScript := preload("res://scripts/dungeon/floor_definition.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RoomTemplateDefinitionScript := preload(
	"res://scripts/dungeon/room_template_definition.gd"
)
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

const SCHEMA_ID := "planewalker.run_dungeon_replay"
const SCHEMA_VERSION := 2
const SUPPORTED_GENERATOR_VERSIONS: Array[String] = ["floor_plan_v1"]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"generator_version",
	"content_snapshot",
	"floor_id",
	"plan_digest",
	"route_prefix",
	"room_facts",
	"economy_ledger_digest",
	"event_resolution_digest",
	"floor_rule_state_digest",
	"floor_transitions",
	"snapshot_digest",
]
const ROOM_FACT_INPUT_FIELDS: Array[String] = ["node_id", "fact_type", "sequence"]
const ROOM_FACT_FIELDS: Array[String] = [
	"node_id",
	"fact_type",
	"sequence",
	"room_type",
	"template_id",
	"definition_digest",
]
const EVENT_RESOLUTION_FIELDS: Array[String] = [
	"event_id", "node_id", "option_id", "outcome_id", "sequence",
]
const FLOOR_TRANSITION_FIELDS: Array[String] = [
	"sequence", "from_floor_id", "to_floor_id", "completed_plan_digest",
]
const ECONOMY_LEDGER_FIELDS: Array[String] = [
	"transaction_id", "operation", "amount", "revision",
]
const VALID_ROOM_FACT_TYPES: Array[String] = ["room_entered", "room_cleared"]
const VALID_ECONOMY_OPERATIONS: Array[String] = [
	"gold_delta", "gold_purchase", "gold_reroll", "gold_service", "gold_decay",
]
const EVENT_OUTCOME_SCHEMA_ID := "event_outcome_v1"
const MAX_ECONOMY_AMOUNT := 1000000
const STABLE_ID_PATTERN := "^[a-z0-9][a-z0-9_:-]{0,95}$"
const SHA256_PATTERN := "^[a-f0-9]{64}$"


func capture(
	registry: Variant,
	floor_plan: Dictionary,
	route_prefix: Array,
	room_fact_inputs: Array,
	economy_ledger: Array,
	event_resolutions: Array,
	floor_transitions: Array,
	floor_rule_state: Dictionary = {}
) -> Dictionary:
	var content_snapshot := ContentSnapshotProviderScript.snapshot(registry)
	if content_snapshot.is_empty():
		return {}
	var plan_validation := _validate_plan_identity(floor_plan, registry)
	if not bool(plan_validation.get("ok", false)):
		return {}
	if not _route_prefix_is_valid(floor_plan, route_prefix):
		return {}
	var room_result := _sealed_room_facts(
		registry, floor_plan, route_prefix, room_fact_inputs
	)
	if not bool(room_result.get("ok", false)):
		return {}
	if not _economy_ledger_is_valid(economy_ledger):
		return {}
	var economy_digest := ReplayRecorderScript.value_digest(economy_ledger)
	var event_digest := _event_resolution_digest(
		registry, floor_plan, route_prefix, event_resolutions
	)
	var floor_rule_digest := ReplayRecorderScript.value_digest(floor_rule_state)
	if (
		not _is_sha256(economy_digest)
		or not _is_sha256(event_digest)
		or not _is_sha256(floor_rule_digest)
		or not ReplaySafeValueScript.is_supported(floor_rule_state)
	):
		return {}
	var transition_result := _expected_floor_transitions(floor_plan, plan_validation)
	if (
		not bool(transition_result.get("ok", false))
		or not _floor_transitions_are_valid(
			floor_transitions,
			transition_result.get("transitions", []) as Array
		)
	):
		return {}
	var result := {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"generator_version": str(floor_plan["generator_version"]),
		"content_snapshot": content_snapshot.duplicate(true),
		"floor_id": str(floor_plan["floor_id"]),
		"plan_digest": str(floor_plan["generation_digest"]),
		"route_prefix": route_prefix.duplicate(true),
		"room_facts": (room_result["facts"] as Array).duplicate(true),
		"economy_ledger_digest": economy_digest,
		"event_resolution_digest": event_digest,
		"floor_rule_state_digest": floor_rule_digest,
		"floor_transitions": floor_transitions.duplicate(true),
	}
	result["snapshot_digest"] = snapshot_digest(result)
	return result if _is_sha256(result["snapshot_digest"]) else {}


func validate(
	value: Dictionary,
	registry: Variant,
	floor_plan: Dictionary,
	economy_ledger: Array,
	event_resolutions: Array,
	floor_rule_state: Dictionary = {}
) -> Dictionary:
	if not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return _failure(&"INVALID_FIELDS")
	if not ReplaySafeValueScript.is_supported(value):
		return _failure(&"UNSAFE_VALUE")
	if not _is_sha256(value.get("snapshot_digest")):
		return _failure(&"INVALID_SHAPE")
	if str(value["snapshot_digest"]) != snapshot_digest(value):
		return _failure(&"SNAPSHOT_DIGEST_MISMATCH")
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != SCHEMA_ID
		or typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SCHEMA_VERSION
		or typeof(value["generator_version"]) != TYPE_STRING
		or typeof(value["floor_id"]) != TYPE_STRING
		or not value["content_snapshot"] is Dictionary
		or not value["route_prefix"] is Array
		or not value["room_facts"] is Array
		or not value["floor_transitions"] is Array
		or not _is_sha256(value["plan_digest"])
		or not _is_sha256(value["economy_ledger_digest"])
		or not _is_sha256(value["event_resolution_digest"])
		or not _is_sha256(value["floor_rule_state_digest"])
	):
		return _failure(&"INVALID_SHAPE")
	var generator_version := str(value["generator_version"])
	if not SUPPORTED_GENERATOR_VERSIONS.has(generator_version):
		return _failure(&"GENERATOR_VERSION_UNSUPPORTED", {
			"generator_version": generator_version,
		})
	var current_content := ContentSnapshotProviderScript.snapshot(registry)
	if current_content.is_empty() or current_content != value["content_snapshot"]:
		return _failure(&"CONTENT_FINGERPRINT_MISMATCH")
	var plan_validation := _validate_plan_identity(floor_plan, registry)
	if (
		not bool(plan_validation.get("ok", false))
		or str(floor_plan.get("generator_version", "")) != generator_version
		or str(floor_plan.get("floor_id", "")) != str(value["floor_id"])
		or str(floor_plan.get("generation_digest", "")) != str(value["plan_digest"])
	):
		return _failure(&"PLAN_DIGEST_MISMATCH")
	var route_prefix := value["route_prefix"] as Array
	if not _route_prefix_is_valid(floor_plan, route_prefix):
		return _failure(&"ROUTE_PREFIX_INVALID")
	var room_inputs := _room_fact_inputs(value["room_facts"] as Array)
	if room_inputs.is_empty() and not (value["room_facts"] as Array).is_empty():
		return _failure(&"ROOM_FACT_INVALID")
	var room_result := _sealed_room_facts(
		registry, floor_plan, route_prefix, room_inputs
	)
	if not bool(room_result.get("ok", false)):
		return _failure(
			StringName(str(room_result.get("code", "ROOM_FACT_INVALID"))),
			room_result.get("context", {}) as Dictionary
		)
	if (room_result["facts"] as Array) != value["room_facts"]:
		return _failure(&"ROOM_DEFINITION_DRIFT")
	if not _economy_ledger_is_valid(economy_ledger):
		return _failure(&"ECONOMY_LEDGER_INVALID")
	if ReplayRecorderScript.value_digest(economy_ledger) != str(value["economy_ledger_digest"]):
		return _failure(&"ECONOMY_LEDGER_DRIFT")
	var event_digest := _event_resolution_digest(
		registry, floor_plan, route_prefix, event_resolutions
	)
	if not _is_sha256(event_digest):
		return _failure(&"EVENT_RESOLUTION_INVALID")
	if event_digest != str(value["event_resolution_digest"]):
		return _failure(&"EVENT_RESOLUTION_DRIFT")
	if (
		not ReplaySafeValueScript.is_supported(floor_rule_state)
		or ReplayRecorderScript.value_digest(floor_rule_state)
		!= str(value["floor_rule_state_digest"])
	):
		return _failure(&"FLOOR_RULE_STATE_DRIFT")
	var transition_result := _expected_floor_transitions(floor_plan, plan_validation)
	if (
		not bool(transition_result.get("ok", false))
		or not _floor_transitions_are_valid(
			value["floor_transitions"] as Array,
			transition_result.get("transitions", []) as Array
		)
	):
		return _failure(&"FLOOR_TRANSITION_INVALID")
	return {
		"ok": true,
		"code": &"OK",
		"snapshot": value.duplicate(true),
	}


func snapshot_digest(value: Dictionary) -> String:
	var digest_source := value.duplicate(true)
	digest_source.erase("snapshot_digest")
	return ReplayRecorderScript.value_digest(digest_source)


func _validate_plan_identity(plan: Dictionary, registry: Variant) -> Dictionary:
	var authority := _authority_bundle(registry)
	if not bool(authority.get("ok", false)):
		return _failure(&"PLAN_INVALID")
	var generator_version_value: Variant = plan.get("generator_version")
	if typeof(generator_version_value) != TYPE_STRING:
		return _failure(&"PLAN_INVALID")
	var generator_version := str(generator_version_value)
	if not SUPPORTED_GENERATOR_VERSIONS.has(generator_version):
		return _failure(&"GENERATOR_VERSION_UNSUPPORTED")
	if (
		typeof(plan.get("run_seed")) != TYPE_INT
		or typeof(plan.get("floor_id")) != TYPE_STRING
		or str(plan.get("floor_id", "")).is_empty()
		or not _is_sha256(plan.get("generation_digest"))
		or not plan.get("nodes") is Array
		or not plan.get("edges") is Array
		or not plan.get("selected_edge_ids") is Array
	):
		return _failure(&"PLAN_INVALID")
	var floor_id := str(plan["floor_id"])
	var floor_index := FloorDefinitionScript.FLOOR_IDS.find(floor_id)
	if floor_index < 0:
		return _failure(&"PLAN_INVALID")
	var floors := authority["floors"] as Array
	var templates := authority["templates"] as Array
	var floor := floors[floor_index] as Dictionary
	var configured_plan = FloorPlanScript.new()
	var configured: Dictionary = configured_plan.configure(plan, floor, templates)
	if not bool(configured.get("ok", false)):
		return _failure(&"PLAN_INVALID", configured.get("context", {}) as Dictionary)
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
		int(plan["run_seed"]), floor, templates
	)
	if not bool(generated.get("ok", false)):
		return _failure(&"PLAN_INVALID")
	var canonical_plan := generated["plan"] as Dictionary
	if (
		str(plan["generation_digest"]) != FloorPlanScript.compute_generation_digest(plan)
		or str(plan["generation_digest"]) != str(canonical_plan["generation_digest"])
	):
		return _failure(&"PLAN_DIGEST_MISMATCH")
	return {
		"ok": true,
		"code": &"OK",
		"floor_index": floor_index,
		"floors": floors.duplicate(true),
		"templates": templates.duplicate(true),
		"canonical_plan": canonical_plan.duplicate(true),
	}


func _authority_bundle(registry: Variant) -> Dictionary:
	if (
		registry == null
		or not registry is Object
		or not registry.has_method("get_floor_definitions")
		or not registry.has_method("get_by_category")
	):
		return _failure(&"PLAN_INVALID")
	var floors_value: Variant = registry.call("get_floor_definitions", &"LAUNCH")
	var templates_value: Variant = registry.call(
		"get_by_category", &"room_template", &"LAUNCH"
	)
	if (
		not floors_value is Array
		or not templates_value is Array
		or (floors_value as Array).size() != FloorDefinitionScript.FLOOR_IDS.size()
		or (templates_value as Array).is_empty()
	):
		return _failure(&"PLAN_INVALID")
	var floors: Array[Dictionary] = []
	for index: int in range((floors_value as Array).size()):
		var floor_source := _closed_definition(
			(floors_value as Array)[index], FloorDefinitionScript.ROOT_FIELDS
		)
		var floor_result: Dictionary = FloorDefinitionScript.new().configure(floor_source)
		if (
			not bool(floor_result.get("ok", false))
			or str((floor_result.get("definition", {}) as Dictionary).get("id", ""))
			!= FloorDefinitionScript.FLOOR_IDS[index]
			or int((floor_result.get("definition", {}) as Dictionary).get("order", 0))
			!= index + 1
		):
			return _failure(&"PLAN_INVALID")
		floors.append(
			(floor_result.get("definition", {}) as Dictionary).duplicate(true)
		)
	var templates: Array[Dictionary] = []
	var template_ids: Dictionary = {}
	for template_value: Variant in templates_value as Array:
		var template_source := _closed_definition(
			template_value, RoomTemplateDefinitionScript.ROOT_FIELDS
		)
		var template_result: Dictionary = RoomTemplateDefinitionScript.new().configure(
			template_source
		)
		if not bool(template_result.get("ok", false)):
			return _failure(&"PLAN_INVALID")
		var template := template_result.get("definition", {}) as Dictionary
		var template_id := str(template.get("id", ""))
		if template_id.is_empty() or template_ids.has(template_id):
			return _failure(&"PLAN_INVALID")
		template_ids[template_id] = true
		templates.append(template.duplicate(true))
	return {
		"ok": true,
		"code": &"OK",
		"floors": floors,
		"templates": templates,
	}


func _closed_definition(value: Variant, fields: Array[String]) -> Dictionary:
	if not value is Dictionary:
		return {}
	var result: Dictionary = {}
	for field: String in fields:
		if not (value as Dictionary).has(field):
			return {}
		var field_value: Variant = (value as Dictionary)[field]
		result[field] = (
			field_value.duplicate(true)
			if field_value is Array or field_value is Dictionary
			else field_value
		)
	return result


func _route_prefix_is_valid(plan: Dictionary, route_prefix: Array) -> bool:
	var selected_edges := plan.get("selected_edge_ids", []) as Array
	if route_prefix.size() != selected_edges.size():
		return false
	var edges_by_id: Dictionary = {}
	for edge_value: Variant in plan.get("edges", []):
		if not edge_value is Dictionary:
			return false
		var edge := edge_value as Dictionary
		var edge_id := str(edge.get("id", ""))
		if edge_id.is_empty() or edges_by_id.has(edge_id):
			return false
		edges_by_id[edge_id] = edge
	var current_node_id := str(plan.get("entry_node_id", ""))
	var seen: Dictionary = {}
	for index: int in range(route_prefix.size()):
		if typeof(route_prefix[index]) != TYPE_STRING:
			return false
		var edge_id := str(route_prefix[index])
		if edge_id != str(selected_edges[index]) or seen.has(edge_id) or not edges_by_id.has(edge_id):
			return false
		var edge := edges_by_id[edge_id] as Dictionary
		if bool(edge.get("locked", false)) or str(edge.get("source_node_id", "")) != current_node_id:
			return false
		seen[edge_id] = true
		current_node_id = str(edge.get("destination_node_id", ""))
	return current_node_id == str(plan.get("current_node_id", ""))


func _sealed_room_facts(
	registry: Variant,
	plan: Dictionary,
	route_prefix: Array,
	room_fact_inputs: Array
) -> Dictionary:
	if (
		registry == null
		or not registry is Object
		or not registry.has_method("resolve_room_template")
	):
		return _failure(&"ROOM_DEFINITION_DRIFT")
	var route_node_ids := _route_node_ids(plan, route_prefix)
	if route_node_ids.is_empty() and not route_prefix.is_empty():
		return _failure(&"ROUTE_PREFIX_INVALID")
	var nodes_by_id := _nodes_by_id(plan)
	if nodes_by_id.is_empty():
		return _failure(&"ROOM_FACT_INVALID")
	var expected_inputs: Array[Dictionary] = []
	var facts: Array[Dictionary] = []
	for node_id: String in route_node_ids:
		if not nodes_by_id.has(node_id):
			return _failure(&"ROOM_FACT_INVALID", {"node_id": node_id})
		var node := nodes_by_id[node_id] as Dictionary
		if not bool(node.get("visited", false)):
			return _failure(&"ROOM_FACT_INVALID", {"node_id": node_id})
		var template_id := str(node.get("template_id", ""))
		var definition_value: Variant = registry.call(
			"resolve_room_template", StringName(template_id)
		)
		if not definition_value is Dictionary or (definition_value as Dictionary).is_empty():
			return _failure(&"ROOM_DEFINITION_DRIFT", {"template_id": template_id})
		var definition := definition_value as Dictionary
		if (
			str(definition.get("id", "")) != template_id
			or str(definition.get("room_type", "")) != str(node.get("room_type", ""))
		):
			return _failure(&"ROOM_DEFINITION_DRIFT", {"template_id": template_id})
		var definition_digest := ReplayRecorderScript.value_digest(definition)
		if not _is_sha256(definition_digest):
			return _failure(&"ROOM_DEFINITION_DRIFT", {"template_id": template_id})
		_append_room_fact(
			expected_inputs,
			facts,
			node,
			"room_entered",
			definition_digest
		)
		if bool(node.get("cleared", false)):
			_append_room_fact(
				expected_inputs,
				facts,
				node,
				"room_cleared",
				definition_digest
			)
	var normalized_inputs := _normalized_room_fact_inputs(room_fact_inputs)
	if not bool(normalized_inputs.get("ok", false)):
		return normalized_inputs
	if (normalized_inputs["inputs"] as Array) != expected_inputs:
		return _failure(&"ROOM_FACT_INVALID")
	return {"ok": true, "code": &"OK", "facts": facts}


func _append_room_fact(
	inputs: Array[Dictionary],
	facts: Array[Dictionary],
	node: Dictionary,
	fact_type: String,
	definition_digest: String
) -> void:
	var sequence := inputs.size()
	var node_id := str(node.get("id", ""))
	inputs.append({
		"node_id": node_id,
		"fact_type": fact_type,
		"sequence": sequence,
	})
	facts.append({
		"node_id": node_id,
		"fact_type": fact_type,
		"sequence": sequence,
		"room_type": str(node.get("room_type", "")),
		"template_id": str(node.get("template_id", "")),
		"definition_digest": definition_digest,
	})


func _normalized_room_fact_inputs(room_fact_inputs: Array) -> Dictionary:
	var inputs: Array[Dictionary] = []
	for index: int in range(room_fact_inputs.size()):
		var input_value: Variant = room_fact_inputs[index]
		if not input_value is Dictionary:
			return _failure(&"ROOM_FACT_INVALID", {"index": index})
		var input := input_value as Dictionary
		if (
			not _has_exact_fields(input, ROOM_FACT_INPUT_FIELDS)
			or typeof(input.get("node_id")) != TYPE_STRING
			or str(input.get("node_id", "")).is_empty()
			or typeof(input.get("fact_type")) != TYPE_STRING
			or not VALID_ROOM_FACT_TYPES.has(str(input.get("fact_type", "")))
			or typeof(input.get("sequence")) != TYPE_INT
			or int(input["sequence"]) != index
		):
			return _failure(&"ROOM_FACT_INVALID", {"index": index})
		inputs.append(input.duplicate(true))
	return {"ok": true, "code": &"OK", "inputs": inputs}


func _room_fact_inputs(room_facts: Array) -> Array:
	var result: Array[Dictionary] = []
	for fact_value: Variant in room_facts:
		if not fact_value is Dictionary:
			return []
		var fact := fact_value as Dictionary
		if not _has_exact_fields(fact, ROOM_FACT_FIELDS):
			return []
		result.append({
			"node_id": fact["node_id"],
			"fact_type": fact["fact_type"],
			"sequence": fact["sequence"],
		})
	return result


func expected_event_outcome_id(
	definition: Dictionary,
	node_id: String,
	option_id: String
) -> String:
	if node_id.is_empty() or option_id.is_empty():
		return ""
	var selected_option: Dictionary = {}
	for option_value: Variant in definition.get("options", []):
		if (
			option_value is Dictionary
			and str((option_value as Dictionary).get("id", "")) == option_id
		):
			selected_option = (option_value as Dictionary).duplicate(true)
			break
	if selected_option.is_empty():
		return ""
	var outcome_digest := ReplayRecorderScript.value_digest({
		"schema_id": EVENT_OUTCOME_SCHEMA_ID,
		"event_id": str(definition.get("id", "")),
		"node_id": node_id,
		"option_id": option_id,
		"outcome_channel": str(definition.get("outcome_channel", "")),
		"outcome_key": str(selected_option.get("outcome_key", "")),
		"consequences": selected_option.get("consequences", []).duplicate(true),
	})
	return (
		"%s:%s" % [EVENT_OUTCOME_SCHEMA_ID, outcome_digest]
		if _is_sha256(outcome_digest)
		else ""
	)


func _event_resolution_digest(
	registry: Variant,
	plan: Dictionary,
	route_prefix: Array,
	event_resolutions: Array
) -> String:
	if (
		registry == null
		or not registry is Object
		or not registry.has_method("resolve_dungeon_event")
		or not ReplaySafeValueScript.is_supported(event_resolutions)
	):
		return ""
	var nodes_by_id := _nodes_by_id(plan)
	var route_node_ids := _route_node_ids(plan, route_prefix)
	var expected_event_node_ids: Array[String] = []
	for node_id: String in route_node_ids:
		if not nodes_by_id.has(node_id):
			return ""
		var route_node := nodes_by_id[node_id] as Dictionary
		if (
			str(route_node.get("room_type", "")) == "event"
			and bool(route_node.get("cleared", false))
		):
			expected_event_node_ids.append(node_id)
	if event_resolutions.size() != expected_event_node_ids.size():
		return ""
	var sealed: Array[Dictionary] = []
	var seen_nodes: Dictionary = {}
	for index: int in range(event_resolutions.size()):
		var resolution_value: Variant = event_resolutions[index]
		if not resolution_value is Dictionary:
			return ""
		var resolution := resolution_value as Dictionary
		if not _has_exact_fields(resolution, EVENT_RESOLUTION_FIELDS):
			return ""
		if typeof(resolution.get("sequence")) != TYPE_INT or int(resolution["sequence"]) != index:
			return ""
		for field: String in ["event_id", "node_id", "option_id", "outcome_id"]:
			if typeof(resolution.get(field)) != TYPE_STRING or str(resolution[field]).is_empty():
				return ""
		var event_id := str(resolution["event_id"])
		var node_id := str(resolution["node_id"])
		if (
			node_id != expected_event_node_ids[index]
			or seen_nodes.has(node_id)
			or not nodes_by_id.has(node_id)
		):
			return ""
		seen_nodes[node_id] = true
		var node := nodes_by_id[node_id] as Dictionary
		if (
			str(node.get("room_type", "")) != "event"
			or not bool(node.get("cleared", false))
			or str(node.get("event_id", "")) != event_id
		):
			return ""
		var definition_value: Variant = registry.call(
			"resolve_dungeon_event", StringName(event_id)
		)
		if not definition_value is Dictionary or (definition_value as Dictionary).is_empty():
			return ""
		var definition := definition_value as Dictionary
		if (
			str(definition.get("id", "")) != event_id
			or str(definition.get("category", "")) != "dungeon_event"
		):
			return ""
		var option_found := false
		for option_value: Variant in definition.get("options", []):
			if option_value is Dictionary and str((option_value as Dictionary).get("id", "")) == str(resolution["option_id"]):
				option_found = true
				break
		if not option_found:
			return ""
		if str(resolution["outcome_id"]) != expected_event_outcome_id(
			definition,
			node_id,
			str(resolution["option_id"])
		):
			return ""
		var definition_digest := ReplayRecorderScript.value_digest(definition)
		if not _is_sha256(definition_digest):
			return ""
		var sealed_resolution := resolution.duplicate(true)
		sealed_resolution["definition_digest"] = definition_digest
		sealed.append(sealed_resolution)
	return ReplayRecorderScript.value_digest(sealed)


func _economy_ledger_is_valid(ledger: Array) -> bool:
	if not ReplaySafeValueScript.is_supported(ledger):
		return false
	var transaction_ids: Dictionary = {}
	for index: int in range(ledger.size()):
		var entry_value: Variant = ledger[index]
		if not entry_value is Dictionary:
			return false
		var entry := entry_value as Dictionary
		if not _has_exact_fields(entry, ECONOMY_LEDGER_FIELDS):
			return false
		var transaction_id := str(entry.get("transaction_id", ""))
		if (
			typeof(entry.get("transaction_id")) != TYPE_STRING
			or not _matches(STABLE_ID_PATTERN, transaction_id)
			or transaction_ids.has(transaction_id)
			or typeof(entry.get("operation")) != TYPE_STRING
			or not VALID_ECONOMY_OPERATIONS.has(str(entry["operation"]))
			or typeof(entry.get("amount")) != TYPE_INT
			or int(entry["amount"]) == 0
			or absi(int(entry["amount"])) > MAX_ECONOMY_AMOUNT
			or typeof(entry.get("revision")) != TYPE_INT
			or int(entry["revision"]) != index + 1
		):
			return false
		transaction_ids[transaction_id] = true
	return true


func _expected_floor_transitions(
	plan: Dictionary,
	plan_validation: Dictionary
) -> Dictionary:
	if not bool(plan_validation.get("ok", false)):
		return _failure(&"FLOOR_TRANSITION_INVALID")
	var floor_index := int(plan_validation.get("floor_index", -1))
	var floors := plan_validation.get("floors", []) as Array
	var templates := plan_validation.get("templates", []) as Array
	if floor_index < 0 or floor_index >= floors.size():
		return _failure(&"FLOOR_TRANSITION_INVALID")
	var transitions: Array[Dictionary] = []
	for index: int in range(floor_index + 1):
		var completed_digest := ""
		if index > 0:
			var prior_generated: Dictionary = FloorPlanGeneratorScript.new().generate(
				int(plan.get("run_seed", 0)),
				floors[index - 1] as Dictionary,
				templates
			)
			if not bool(prior_generated.get("ok", false)):
				return _failure(&"FLOOR_TRANSITION_INVALID")
			completed_digest = str(
				(prior_generated["plan"] as Dictionary).get("generation_digest", "")
			)
			if not _is_sha256(completed_digest):
				return _failure(&"FLOOR_TRANSITION_INVALID")
		transitions.append({
			"sequence": index,
			"from_floor_id": (
				"" if index == 0 else str((floors[index - 1] as Dictionary).get("id", ""))
			),
			"to_floor_id": str((floors[index] as Dictionary).get("id", "")),
			"completed_plan_digest": completed_digest,
		})
	return {"ok": true, "code": &"OK", "transitions": transitions}


func _floor_transitions_are_valid(transitions: Array, expected: Array) -> bool:
	if not ReplaySafeValueScript.is_supported(transitions):
		return false
	for index: int in range(transitions.size()):
		var transition_value: Variant = transitions[index]
		if not transition_value is Dictionary:
			return false
		var transition := transition_value as Dictionary
		if not _has_exact_fields(transition, FLOOR_TRANSITION_FIELDS):
			return false
		if (
			typeof(transition.get("sequence")) != TYPE_INT
			or int(transition["sequence"]) != index
			or typeof(transition.get("from_floor_id")) != TYPE_STRING
			or typeof(transition.get("to_floor_id")) != TYPE_STRING
			or str(transition["to_floor_id"]).is_empty()
			or typeof(transition.get("completed_plan_digest")) != TYPE_STRING
		):
			return false
		var completed_digest := str(transition["completed_plan_digest"])
		if index == 0 and not completed_digest.is_empty():
			return false
		if index > 0 and not _is_sha256(completed_digest):
			return false
	return transitions == expected


func _route_node_ids(plan: Dictionary, route_prefix: Array) -> Array[String]:
	var edges_by_id: Dictionary = {}
	for edge_value: Variant in plan.get("edges", []):
		if edge_value is Dictionary:
			edges_by_id[str((edge_value as Dictionary).get("id", ""))] = edge_value
	var result: Array[String] = []
	for edge_id_value: Variant in route_prefix:
		var edge_id := str(edge_id_value)
		if not edges_by_id.has(edge_id):
			return []
		result.append(str((edges_by_id[edge_id] as Dictionary).get("destination_node_id", "")))
	return result


func _nodes_by_id(plan: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for node_value: Variant in plan.get("nodes", []):
		if not node_value is Dictionary:
			return {}
		var node := node_value as Dictionary
		var node_id := str(node.get("id", ""))
		if node_id.is_empty() or result.has(node_id):
			return {}
		result[node_id] = node
	return result


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(SHA256_PATTERN) == OK and regex.search(str(value)) != null


func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(str(value)) != null


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
