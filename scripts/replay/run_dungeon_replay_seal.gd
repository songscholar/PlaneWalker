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
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const MerchantRunStateScript := preload("res://scripts/economy/merchant_run_state.gd")
const DungeonEventRunStateScript := preload(
	"res://scripts/events/dungeon_event_run_state.gd"
)
const DungeonEventDefinitionScript := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const DungeonEventRuntimeScript := preload("res://scripts/events/dungeon_event_runtime.gd")
const DungeonEventSelectorScript := preload("res://scripts/events/dungeon_event_selector.gd")
const EventRequirementServiceScript := preload("res://scripts/events/event_requirement_service.gd")
const DungeonEventConsequenceRuntimeScript := preload(
	"res://scripts/events/dungeon_event_consequence_runtime.gd"
)
const EventHealthAuthorityScript := preload("res://scripts/events/event_health_authority.gd")
const EventModifierAuthorityScript := preload("res://scripts/events/event_modifier_authority.gd")
const EventResourceAuthorityScript := preload("res://scripts/events/event_resource_authority.gd")
const EventRouteAuthorityScript := preload("res://scripts/events/event_route_authority.gd")
const EventModifierLifetimeScript := preload("res://scripts/events/event_modifier_lifetime.gd")

const SCHEMA_ID := "planewalker.run_dungeon_replay"
const SCHEMA_VERSION := 3
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
	"economy_state_digest",
	"merchant_state_digest",
	"merchant_transaction_facts",
	"merchant_audit_facts",
	"event_runtime_digest",
	"event_assignment_facts",
	"event_outcome_facts",
	"event_transaction_facts",
	"event_receipt_facts",
	"event_publication_facts",
	"floor_rule_state_digest",
	"room_completion_events_digest",
	"floor_transitions",
	"snapshot_digest",
]
const EVENT_SEAL_FIELDS: Array[String] = [
	"event_runtime_digest", "event_assignment_facts", "event_outcome_facts",
	"event_transaction_facts", "event_receipt_facts", "event_publication_facts",
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
const EVENT_RUNTIME_FIELDS: Array[String] = [
	"schema_id", "schema_version", "active_node_key", "active_event_id",
	"encounter_success_by_transaction", "emitted_fact_ids", "pending_facts",
	"publication_ledger", "publication_digest", "consequence_runtime",
]
const EVENT_CONSEQUENCE_FIELDS: Array[String] = [
	"schema_id", "schema_version", "completed_transaction_ids", "publications",
	"integrity_failure", "participant_snapshots", "revision",
]
const EVENT_PARTICIPANT_FIELDS: Array[String] = [
	"economy", "event_state", "health", "modifier", "resource", "route",
]
const EVENT_PUBLICATION_FIELDS: Array[String] = [
	"transaction_id", "phase", "result_key", "pending_kind",
]
const EVENT_LEDGER_FIELDS: Array[String] = [
	"chain_hash", "fact_id", "payload", "status",
]
const EVENT_PENDING_FACT_FIELDS: Array[String] = [
	"fact_id", "payload",
]
const FLOOR_TRANSITION_FIELDS: Array[String] = [
	"sequence", "from_floor_id", "to_floor_id", "completed_plan_digest",
]
const MERCHANT_TRANSACTION_FIELDS: Array[String] = [
	"sequence", "floor_id", "node_id", "merchant_id", "transaction_id", "kind",
	"offer_id", "reward_id", "service_id", "cost_kind", "amount",
	"economy_revision", "inventory_revision",
]
const MERCHANT_AUDIT_FIELDS: Array[String] = [
	"floor_id", "node_id", "merchant_id", "sold_offer_ids", "reroll_count",
	"completed_transaction_ids", "service_completed_transaction_ids",
]
const VALID_ROOM_FACT_TYPES: Array[String] = ["room_entered", "room_cleared"]
const STABLE_ID_PATTERN := "^[a-z0-9][a-z0-9_:-]{0,95}$"
const SHA256_PATTERN := "^[a-f0-9]{64}$"

var _event_publication_secret := ""


func _init(event_publication_secret: String = "") -> void:
	# Modern snapshots require the original runtime's secret, including empty ledgers.
	# The default is retained only for reading legacy schema-3 empty event histories.
	_event_publication_secret = event_publication_secret


func capture(
	registry: Variant,
	floor_plan: Dictionary,
	route_prefix: Array,
	room_fact_inputs: Array,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	dungeon_event_runtime: Variant,
	floor_transitions: Array,
	floor_rule_state: Dictionary = {},
	run_events: Array = []
) -> Dictionary:
	if not dungeon_event_runtime is Dictionary:
		return {}
	if not EventModifierLifetimeScript.history_matches_plan(run_events, floor_plan):
		return {}
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
	if not _run_economy_is_valid(run_economy, registry):
		return {}
	if not _merchant_state_is_valid(merchant_state):
		return {}
	var merchant_facts := _merchant_transaction_facts(merchant_state)
	var merchant_audit := _merchant_audit_facts(merchant_state)
	if (
		merchant_facts.is_empty() and not _merchant_transactions_are_empty(merchant_state)
		or merchant_audit.is_empty() and not (merchant_state.get("nodes", []) as Array).is_empty()
		or not _economy_merchant_pair_is_consistent(run_economy, merchant_facts)
	):
		return {}
	var economy_digest := ReplayRecorderScript.value_digest(run_economy)
	var merchant_digest := ReplayRecorderScript.value_digest(merchant_state)
	var event_result := _event_replay_facts(
		registry, floor_plan, route_prefix, room_result["facts"] as Array,
		dungeon_event_runtime, run_economy
	)
	var floor_rule_digest := ReplayRecorderScript.value_digest(floor_rule_state)
	if (
		not _is_sha256(economy_digest)
		or not _is_sha256(merchant_digest)
		or not bool(event_result.get("ok", false))
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
		"economy_state_digest": economy_digest,
		"merchant_state_digest": merchant_digest,
		"merchant_transaction_facts": merchant_facts.duplicate(true),
		"merchant_audit_facts": merchant_audit.duplicate(true),
		"event_runtime_digest": str(event_result["runtime_digest"]),
		"event_assignment_facts": (event_result["assignment_facts"] as Array).duplicate(true),
		"event_outcome_facts": (event_result["outcome_facts"] as Array).duplicate(true),
		"event_transaction_facts": (event_result["transaction_facts"] as Array).duplicate(true),
		"event_receipt_facts": (event_result["receipt_facts"] as Array).duplicate(true),
		"event_publication_facts": (event_result["publication_facts"] as Array).duplicate(true),
		"floor_rule_state_digest": floor_rule_digest,
		"room_completion_events_digest": ReplayRecorderScript.value_digest(run_events),
		"floor_transitions": floor_transitions.duplicate(true),
	}
	result["snapshot_digest"] = snapshot_digest(result)
	return result if _is_sha256(result["snapshot_digest"]) else {}


func validate(
	value: Dictionary,
	registry: Variant,
	floor_plan: Dictionary,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	dungeon_event_runtime: Variant,
	floor_rule_state: Dictionary = {},
	run_events: Array = []
) -> Dictionary:
	var legacy_empty_history := value.has("event_resolution_digest")
	var expected_fields := SNAPSHOT_FIELDS.duplicate()
	if not value.has("room_completion_events_digest"):
		expected_fields.erase("room_completion_events_digest")
		if not run_events.is_empty():
			return _failure(&"ROOM_COMPLETION_HISTORY_MISSING")
	if legacy_empty_history:
		for field: String in EVENT_SEAL_FIELDS:
			expected_fields.erase(field)
		expected_fields.append("event_resolution_digest")
	if not _has_exact_fields(value, expected_fields):
		return _failure(&"INVALID_FIELDS")
	if not ReplaySafeValueScript.is_supported(value):
		return _failure(&"UNSAFE_VALUE")
	if not _is_sha256(value.get("snapshot_digest")):
		return _failure(&"INVALID_SHAPE")
	if str(value["snapshot_digest"]) != snapshot_digest(value):
		return _failure(&"SNAPSHOT_DIGEST_MISMATCH")
	if not EventModifierLifetimeScript.history_matches_plan(run_events, floor_plan):
		return _failure(&"ROOM_COMPLETION_HISTORY_INVALID")
	if value.has("room_completion_events_digest") and (
		not _is_sha256(value["room_completion_events_digest"])
		or value["room_completion_events_digest"] != ReplayRecorderScript.value_digest(run_events)
	):
		return _failure(&"ROOM_COMPLETION_HISTORY_DRIFT")
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
		or not value["merchant_transaction_facts"] is Array
		or not value["merchant_audit_facts"] is Array
		or not _is_sha256(value["plan_digest"])
		or not _is_sha256(value["economy_state_digest"])
		or not _is_sha256(value["merchant_state_digest"])
		or not _is_sha256(value["floor_rule_state_digest"])
	):
		return _failure(&"INVALID_SHAPE")
	if legacy_empty_history:
		if not _is_sha256(value["event_resolution_digest"]):
			return _failure(&"INVALID_SHAPE")
	else:
		if not _is_sha256(value["event_runtime_digest"]):
			return _failure(&"INVALID_SHAPE")
		for field: String in EVENT_SEAL_FIELDS:
			if field != "event_runtime_digest" and not value[field] is Array:
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
	if not _run_economy_is_valid(run_economy, registry):
		return _failure(&"ECONOMY_STATE_INVALID")
	if ReplayRecorderScript.value_digest(run_economy) != str(value["economy_state_digest"]):
		return _failure(&"ECONOMY_STATE_DRIFT")
	if not _merchant_state_is_valid(merchant_state):
		return _failure(&"MERCHANT_STATE_INVALID")
	var merchant_facts := _merchant_transaction_facts(merchant_state)
	if merchant_facts != value["merchant_transaction_facts"]:
		return _failure(&"MERCHANT_TRANSACTION_DRIFT", _first_array_drift(
			value["merchant_transaction_facts"] as Array, merchant_facts, "transactions"
		))
	if not _economy_merchant_pair_is_consistent(run_economy, merchant_facts):
		return _failure(&"MERCHANT_ECONOMY_DRIFT")
	var audit_drift := _merchant_audit_drift(
		value["merchant_audit_facts"] as Array,
		_merchant_audit_facts(merchant_state)
	)
	if not audit_drift.is_empty():
		return audit_drift
	if ReplayRecorderScript.value_digest(merchant_state) != str(value["merchant_state_digest"]):
		return _failure(&"MERCHANT_STATE_DRIFT")
	var event_validation := _validate_event_seal(
		value, registry, floor_plan, run_economy, dungeon_event_runtime
	)
	if not bool(event_validation.get("ok", false)):
		return event_validation
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


func _validate_event_seal(
	value: Dictionary,
	registry: Variant,
	plan: Dictionary,
	run_economy: Dictionary,
	event_value: Variant
) -> Dictionary:
	var route_prefix := value["route_prefix"] as Array
	if value.has("event_resolution_digest"):
		# Read the pre-event schema-3 shape only when its history was empty.
		if (
			not event_value is Array
			or not (event_value as Array).is_empty()
			or str(value["event_resolution_digest"]) != ReplayRecorderScript.value_digest([])
		):
			return _failure(&"EVENT_RESOLUTION_INVALID")
		for fact: Dictionary in value["room_facts"]:
			if str(fact["room_type"]) == "event" and str(fact["fact_type"]) == "room_cleared":
				return _failure(&"EVENT_RESOLUTION_INVALID")
		return {"ok": true, "code": &"OK"}
	if not event_value is Dictionary:
		return _failure(&"EVENT_RUNTIME_INVALID")
	var event_result := _event_replay_facts(
		registry, plan, route_prefix, value["room_facts"] as Array,
		event_value as Dictionary, run_economy
	)
	if not bool(event_result.get("ok", false)):
		return _failure(&"EVENT_RUNTIME_INVALID", event_result.get("context", {}) as Dictionary)
	for fact_check: Dictionary in [
		{"field": "event_assignment_facts", "actual": event_result["assignment_facts"], "code": &"EVENT_ASSIGNMENT_DRIFT"},
		{"field": "event_outcome_facts", "actual": event_result["outcome_facts"], "code": &"EVENT_OUTCOME_DRIFT"},
		{"field": "event_transaction_facts", "actual": event_result["transaction_facts"], "code": &"EVENT_TRANSACTION_DRIFT"},
		{"field": "event_receipt_facts", "actual": event_result["receipt_facts"], "code": &"EVENT_RECEIPT_DRIFT"},
		{"field": "event_publication_facts", "actual": event_result["publication_facts"], "code": &"EVENT_PUBLICATION_DRIFT"},
	]:
		if value[fact_check["field"]] != fact_check["actual"]:
			return _failure(fact_check["code"], {"field": fact_check["field"]})
	if str(event_result["runtime_digest"]) != str(value["event_runtime_digest"]):
		return _failure(&"EVENT_RUNTIME_DRIFT")
	return {"ok": true, "code": &"OK"}


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


func _event_replay_facts(
	registry: Variant,
	plan: Dictionary,
	route_prefix: Array,
	room_facts: Array,
	event_runtime: Dictionary,
	run_economy: Dictionary
) -> Dictionary:
	if (
		registry == null
		or not registry is Object
		or not registry.has_method("resolve_dungeon_event")
		or not ReplaySafeValueScript.is_supported(event_runtime)
		or not _has_exact_fields(event_runtime, EVENT_RUNTIME_FIELDS)
		or typeof(event_runtime.get("schema_id")) != TYPE_STRING
		or str(event_runtime.get("schema_id", ""))
		!= "planewalker.dungeon_event_runtime"
		or typeof(event_runtime.get("schema_version")) != TYPE_INT
		or int(event_runtime.get("schema_version", 0)) != 1
		or typeof(event_runtime.get("active_node_key")) != TYPE_STRING
		or typeof(event_runtime.get("active_event_id")) != TYPE_STRING
		or not event_runtime.get("encounter_success_by_transaction") is Dictionary
		or not event_runtime.get("consequence_runtime") is Dictionary
	):
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "runtime"})
	var consequence := event_runtime["consequence_runtime"] as Dictionary
	if (
		not _has_exact_fields(consequence, EVENT_CONSEQUENCE_FIELDS)
		or typeof(consequence.get("schema_id")) != TYPE_STRING
		or str(consequence.get("schema_id", ""))
		!= "planewalker.dungeon_event_consequence_runtime"
		or typeof(consequence.get("schema_version")) != TYPE_INT
		or int(consequence.get("schema_version", 0)) != 1
		or typeof(consequence.get("revision")) != TYPE_INT
		or int(consequence.get("revision", -1)) < 0
		or not consequence.get("integrity_failure") is Dictionary
		or not (consequence.get("integrity_failure", {}) as Dictionary).is_empty()
		or not consequence.get("participant_snapshots") is Dictionary
		or not consequence.get("completed_transaction_ids") is Array
		or not consequence.get("publications") is Array
	):
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "consequence_runtime"})
	var participants := consequence["participant_snapshots"] as Dictionary
	if (
		not _has_exact_fields(participants, EVENT_PARTICIPANT_FIELDS)
		or not participants.get("event_state") is Dictionary
	):
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "participant_snapshots"})
	for participant: String in EVENT_PARTICIPANT_FIELDS:
		if not participants.get(participant) is Dictionary:
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "participant_snapshots.%s" % participant})
	var event_state := participants["event_state"] as Dictionary
	var content_fingerprint := str(event_state.get("content_fingerprint", ""))
	var state_candidate = DungeonEventRunStateScript.new()
	if (
		not bool(state_candidate.configure(content_fingerprint).get("ok", false))
		or not state_candidate.can_restore_snapshot(event_state)
	):
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "event_state"})
	if not _event_runtime_restores(registry, plan, run_economy, event_runtime):
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "runtime_authorities"})

	var nodes_by_id := _nodes_by_id(plan)
	var route_node_ids := _route_node_ids(plan, route_prefix)
	var nodes_by_floor := {str(plan.get("floor_id", "")): nodes_by_id}
	var floor_authority: Dictionary = {}
	var assignments := event_state.get("selected_event_by_node", {}) as Dictionary
	var assignment_keys: Array[String] = []
	for key_value: Variant in assignments.keys():
		assignment_keys.append(str(key_value))
	assignment_keys.sort()
	var assignment_facts: Array[Dictionary] = []
	var assignment_by_transaction: Dictionary = {}
	var expected_receipt_ids: Array[String] = []
	for sequence: int in range(assignment_keys.size()):
		var node_key := assignment_keys[sequence]
		var assignment := assignments[node_key] as Dictionary
		var node_id := str(assignment.get("node_id", ""))
		var floor_id := str(assignment.get("floor_id", ""))
		var floor_index := FloorDefinitionScript.FLOOR_IDS.find(floor_id)
		var current_floor_index := int(plan.get("floor_index", -1))
		var phase := str(assignment.get("phase", ""))
		if (
			node_key != "%s:%s" % [floor_id, node_id]
			or floor_index < 0
			or floor_index > current_floor_index
			or int(assignment.get("floor_index", -1)) != floor_index
			or (floor_index == current_floor_index and not route_node_ids.has(node_id))
			or (floor_index < current_floor_index and phase not in ["resolved", "dismissed"])
		):
			return _failure(&"EVENT_RUNTIME_INVALID", {
				"field": "selected_event_by_node", "node_key": node_key,
			})
		if not nodes_by_floor.has(floor_id):
			if floor_authority.is_empty():
				floor_authority = _authority_bundle(registry)
			if not bool(floor_authority.get("ok", false)):
				return _failure(&"EVENT_RUNTIME_INVALID", {"field": "selected_event_by_node.floor"})
			var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
				int(plan.get("run_seed", 0)),
				(floor_authority["floors"] as Array)[floor_index],
				floor_authority["templates"] as Array
			)
			if not bool(generated.get("ok", false)):
				return _failure(&"EVENT_RUNTIME_INVALID", {"field": "selected_event_by_node.floor"})
			nodes_by_floor[floor_id] = _nodes_by_id(generated["plan"] as Dictionary)
		var assignment_nodes := nodes_by_floor[floor_id] as Dictionary
		if (
			not assignment_nodes.has(node_id)
			or str((assignment_nodes[node_id] as Dictionary).get("room_type", "")) != "event"
		):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "selected_event_by_node.node"})
		var authored := _authored_event_selection(
			registry,
			str(assignment.get("event_id", "")),
			str(assignment.get("option_id", "")),
			str(assignment.get("outcome_id", ""))
		)
		if not bool(authored.get("ok", false)):
			return _failure(&"EVENT_RUNTIME_INVALID", {
				"field": "selected_event_by_node.authored", "node_key": node_key,
			})
		if phase != "open":
			var outcome := authored.get("outcome", {}) as Dictionary
			if (
				outcome.is_empty()
				or str(assignment.get("outcome_key", ""))
				!= str(outcome.get("outcome_key", ""))
			):
				return _failure(&"EVENT_RUNTIME_INVALID", {
					"field": "selected_event_by_node.outcome", "node_key": node_key,
				})
		var definition := authored["definition"] as Dictionary
		if (
			str(assignment.get("repeat_policy", "")) != str(definition.get("repeat_policy", ""))
			or int(assignment.get("floor_index", -1)) + 1 < int(definition.get("floor_min", 1))
			or int(assignment.get("floor_index", -1)) + 1 > int(definition.get("floor_max", 5))
		):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "selected_event_by_node.definition"})
		var definition_digest := ReplayRecorderScript.value_digest(definition)
		if not _is_sha256(definition_digest):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "definition_digest"})
		var fact := assignment.duplicate(true)
		fact["sequence"] = sequence
		fact["node_key"] = node_key
		fact["primary_event_id"] = str(
			(assignment_nodes[node_id] as Dictionary).get("event_id", "")
		)
		fact["definition_digest"] = definition_digest
		assignment_facts.append(fact)
		var transaction_id := str(assignment.get("transaction_id", ""))
		if not transaction_id.is_empty():
			if assignment_by_transaction.has(transaction_id):
				return _failure(&"EVENT_RUNTIME_INVALID", {"field": "transaction_id"})
			var pending_kind := ""
			var route_skip_rooms := 0
			var authored_outcome := authored["outcome"] as Dictionary
			for operation_value: Variant in authored_outcome.get("consequences", []):
				var operation := str((operation_value as Dictionary).get("operation", ""))
				if operation == "reward_draft":
					pending_kind = "reward"
				elif operation == "encounter_start":
					pending_kind = "encounter"
				elif operation == "route_skip":
					route_skip_rooms = int((operation_value as Dictionary)["arguments"]["rooms"])
			if phase not in ["open", "reserved"]:
				expected_receipt_ids.append(transaction_id)
			assignment_by_transaction[transaction_id] = {
				"node_key": node_key,
				"assignment": assignment.duplicate(true),
				"pending_kind": pending_kind,
				"route_skip_rooms": route_skip_rooms,
			}

	var outcomes := event_state.get("resolved_outcomes", []) as Array
	var outcome_facts: Array[Dictionary] = []
	var outcome_by_transaction: Dictionary = {}
	for sequence: int in range(outcomes.size()):
		var outcome_value: Variant = outcomes[sequence]
		if not outcome_value is Dictionary:
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "resolved_outcomes"})
		var outcome := outcome_value as Dictionary
		var transaction_id := str(outcome.get("transaction_id", ""))
		if not assignment_by_transaction.has(transaction_id):
			return _failure(&"EVENT_RUNTIME_INVALID", {
				"field": "resolved_outcomes.transaction_id",
			})
		var assignment := (
			assignment_by_transaction[transaction_id] as Dictionary
		)["assignment"] as Dictionary
		if (
			str(outcome.get("node_key", ""))
			!= str((assignment_by_transaction[transaction_id] as Dictionary)["node_key"])
			or str(outcome.get("event_id", "")) != str(assignment.get("event_id", ""))
			or str(outcome.get("option_id", "")) != str(assignment.get("option_id", ""))
			or str(outcome.get("outcome_id", "")) != str(assignment.get("outcome_id", ""))
			or str(outcome.get("outcome_key", "")) != str(assignment.get("outcome_key", ""))
			or str(outcome.get("result_key", "")) != str(assignment.get("result_key", ""))
		):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "resolved_outcomes.identity"})
		var fact := outcome.duplicate(true)
		fact["sequence"] = sequence
		outcome_facts.append(fact)
		outcome_by_transaction[transaction_id] = outcome.duplicate(true)

	var state_completed_value: Variant = _sorted_stable_ids(
		event_state.get("completed_transaction_ids")
	)
	if state_completed_value == null:
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "completed_transaction_ids"})
	var state_completed := state_completed_value as Array
	var transaction_facts: Array[Dictionary] = []
	for sequence: int in range(state_completed.size()):
		var transaction_id := str(state_completed[sequence])
		if not outcome_by_transaction.has(transaction_id):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "completed_transaction_ids"})
		var outcome := outcome_by_transaction[transaction_id] as Dictionary
		transaction_facts.append({
			"sequence": sequence,
			"transaction_id": transaction_id,
			"node_key": str(outcome.get("node_key", "")),
			"event_id": str(outcome.get("event_id", "")),
			"option_id": str(outcome.get("option_id", "")),
			"outcome_id": str(outcome.get("outcome_id", "")),
			"result_key": str(outcome.get("result_key", "")),
		})

	var receipt_ids_value: Variant = _sorted_stable_ids(
		consequence.get("completed_transaction_ids")
	)
	if receipt_ids_value == null:
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "consequence.completed"})
	var receipt_ids := receipt_ids_value as Array
	expected_receipt_ids.sort()
	if receipt_ids != expected_receipt_ids:
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "receipt_completion"})
	if int(consequence.get("revision", -1)) != receipt_ids.size():
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "consequence.revision"})
	var publications := consequence.get("publications", []) as Array
	if publications.size() != receipt_ids.size():
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "consequence.publications"})
	var receipt_facts: Array[Dictionary] = []
	var receipt_by_transaction: Dictionary = {}
	for sequence: int in range(publications.size()):
		var publication_value: Variant = publications[sequence]
		if not publication_value is Dictionary:
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "consequence.publications"})
		var publication := publication_value as Dictionary
		var transaction_id := str(publication.get("transaction_id", ""))
		for field: String in EVENT_PUBLICATION_FIELDS:
			if typeof(publication.get(field)) != TYPE_STRING:
				return _failure(&"EVENT_RUNTIME_INVALID", {"field": "consequence.publications"})
		if (
			not _has_exact_fields(publication, EVENT_PUBLICATION_FIELDS)
			or sequence >= receipt_ids.size()
			or transaction_id != str(receipt_ids[sequence])
			or not assignment_by_transaction.has(transaction_id)
			or str(publication.get("phase", ""))
			not in ["resolved", "pending_reward", "pending_encounter"]
		):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "consequence.publications"})
		var assignment := (
			assignment_by_transaction[transaction_id] as Dictionary
		)["assignment"] as Dictionary
		if str(publication.get("result_key", "")) != str(assignment.get("outcome_key", "")):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "consequence.result_key"})
		var phase := str(publication.get("phase", ""))
		var pending_kind := str(publication.get("pending_kind", ""))
		var authored_pending_kind := str(
			(assignment_by_transaction[transaction_id] as Dictionary)["pending_kind"]
		)
		var assignment_phase := str(assignment.get("phase", ""))
		if (
			(phase == "resolved" and not pending_kind.is_empty())
			or (phase == "pending_reward" and pending_kind != "reward")
			or (phase == "pending_encounter" and pending_kind != "encounter")
			or pending_kind != authored_pending_kind
			or (assignment_phase.begins_with("pending_") and assignment_phase != phase)
		):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "consequence.pending_kind"})
		var fact := publication.duplicate(true)
		fact["sequence"] = sequence
		receipt_facts.append(fact)
		receipt_by_transaction[transaction_id] = publication.duplicate(true)
	for transaction_id_value: Variant in state_completed:
		if not receipt_by_transaction.has(str(transaction_id_value)):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "receipt_completion"})
	var skipped_node_ids := _event_route_skip_intermediates(
		plan, route_node_ids, nodes_by_id, assignment_by_transaction,
		receipt_by_transaction, participants["route"] as Dictionary
	)
	for fact: Dictionary in room_facts:
		if str(fact["room_type"]) != "event" or str(fact["fact_type"]) != "room_cleared":
			continue
		var node_id := str(fact["node_id"])
		var node_key := "%s:%s" % [str(plan["floor_id"]), node_id]
		if not assignments.has(node_key) and not skipped_node_ids.has(node_id):
			return _failure(&"EVENT_RUNTIME_INVALID", {
				"field": "selected_event_by_node.missing_cleared_event", "node_key": node_key,
			})

	var expected_payloads := _expected_event_publication_payloads(
		assignments,
		receipt_by_transaction,
		event_runtime.get("encounter_success_by_transaction", {}) as Dictionary
	)
	if expected_payloads.is_empty() and not assignments.is_empty():
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "publication_payloads"})
	var publication_result := _event_publication_facts(
		event_runtime, expected_payloads
	)
	if not bool(publication_result.get("ok", false)):
		return publication_result
	var active_node_key := str(event_runtime.get("active_node_key", ""))
	var active_event_id := str(event_runtime.get("active_event_id", ""))
	if active_node_key.is_empty() != active_event_id.is_empty():
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "active_event"})
	if not active_node_key.is_empty() and (
		not assignments.has(active_node_key)
		or str((assignments[active_node_key] as Dictionary).get("event_id", ""))
		!= active_event_id
	):
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "active_event"})
	var runtime_digest := ReplayRecorderScript.value_digest(event_runtime)
	if not _is_sha256(runtime_digest):
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "runtime_digest"})
	return {
		"ok": true,
		"code": &"OK",
		"runtime_digest": runtime_digest,
		"assignment_facts": assignment_facts,
		"outcome_facts": outcome_facts,
		"transaction_facts": transaction_facts,
		"receipt_facts": receipt_facts,
		"publication_facts": publication_result["facts"],
	}


func _event_route_skip_intermediates(
	plan: Dictionary,
	route_node_ids: Array[String],
	nodes_by_id: Dictionary,
	assignment_by_transaction: Dictionary,
	receipt_by_transaction: Dictionary,
	route_authority: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	var route_completed := route_authority["completed_transaction_ids"] as Array
	for transaction_id: String in assignment_by_transaction:
		var selection := assignment_by_transaction[transaction_id] as Dictionary
		var assignment := selection["assignment"] as Dictionary
		var rooms := int(selection["route_skip_rooms"])
		if (
			rooms < 1
			or str(assignment["floor_id"]) != str(plan["floor_id"])
			or not receipt_by_transaction.has(transaction_id)
			or not route_completed.has(transaction_id)
		):
			continue
		var source_index := route_node_ids.find(str(assignment["node_id"]))
		if source_index < 0 or source_index + rooms >= route_node_ids.size():
			continue
		var intermediates: Array[String] = []
		var legal_path := true
		for offset: int in range(1, rooms + 1):
			var node_id := route_node_ids[source_index + offset]
			var node := nodes_by_id[node_id] as Dictionary
			if (
				EventRouteAuthorityScript.RESTRICTED_ROOM_TYPES.has(str(node["room_type"]))
				or not bool(node["visited"])
				or (offset < rooms and not bool(node["cleared"]))
			):
				legal_path = false
				break
			# The landing room is entered, not skipped, and always needs its own history.
			if offset < rooms:
				intermediates.append(node_id)
		if legal_path:
			for node_id: String in intermediates:
				result[node_id] = true
	return result


func _event_runtime_restores(
	registry: Variant,
	plan: Dictionary,
	run_economy: Dictionary,
	event_runtime: Dictionary
) -> bool:
	var consequence_snapshot := event_runtime["consequence_runtime"] as Dictionary
	var participants := consequence_snapshot["participant_snapshots"] as Dictionary
	var resource_snapshot := participants["resource"] as Dictionary
	var health_snapshot := participants["health"] as Dictionary
	var modifier_snapshot := participants["modifier"] as Dictionary
	var route_snapshot := participants["route"] as Dictionary
	var event_snapshot := participants["event_state"] as Dictionary
	if (
		participants["economy"] != run_economy
		or not resource_snapshot.get("resources") is Dictionary
		or typeof(health_snapshot.get("current")) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(health_snapshot.get("maximum")) not in [TYPE_INT, TYPE_FLOAT]
		or not modifier_snapshot.get("curse_ids") is Array
		or not modifier_snapshot.get("narrative_flags") is Dictionary
		or not modifier_snapshot.get("temporary_modifiers") is Array
		or modifier_snapshot["narrative_flags"] != event_snapshot["narrative_flags"]
		or modifier_snapshot["temporary_modifiers"] != event_snapshot["temporary_modifiers"]
		or not route_snapshot.get("plan") is Dictionary
		or route_snapshot["plan"] != plan
		or not registry.has_method("get_by_category")
	):
		return false
	var resource = EventResourceAuthorityScript.new()
	var health = EventHealthAuthorityScript.new()
	var economy = RunEconomyStateScript.new()
	var modifier = EventModifierAuthorityScript.new()
	var route = EventRouteAuthorityScript.new()
	var event_state = DungeonEventRunStateScript.new()
	var profile_value: Variant = registry.call(
		"resolve_economy_profile", StringName(str(run_economy["profile_id"]))
	)
	var profile := _closed_definition(profile_value, EconomyProfileScript.ROOT_FIELDS)
	if (
		profile.is_empty()
		or not resource.configure((resource_snapshot["resources"] as Dictionary).duplicate(true))
		or not resource.restore_snapshot(resource_snapshot.duplicate(true))
		or resource.snapshot() != resource_snapshot
		or not health.configure(float(health_snapshot["current"]), float(health_snapshot["maximum"]))
		or not health.restore_snapshot(health_snapshot.duplicate(true))
		or health.snapshot() != health_snapshot
		or not bool(economy.configure(profile, int(run_economy["initial_gold"])).get("ok", false))
		or not economy.restore_snapshot(run_economy.duplicate(true))
		or economy.snapshot() != run_economy
		or not modifier.configure(
			(modifier_snapshot["curse_ids"] as Array).duplicate(),
			(modifier_snapshot["narrative_flags"] as Dictionary).duplicate(true),
			(modifier_snapshot["temporary_modifiers"] as Array).duplicate(true)
		)
		or not modifier.restore_snapshot(modifier_snapshot.duplicate(true))
		or modifier.snapshot() != modifier_snapshot
		or not route.configure(plan.duplicate(true))
		or not route.restore_snapshot(route_snapshot.duplicate(true))
		or route.snapshot() != route_snapshot
		or not bool(event_state.configure(str(event_snapshot["content_fingerprint"])).get("ok", false))
		or not event_state.restore_snapshot(event_snapshot.duplicate(true))
		or event_state.snapshot() != event_snapshot
	):
		return false
	var consequence = DungeonEventConsequenceRuntimeScript.new()
	if (
		not consequence.configure(resource, health, economy, modifier, route, event_state)
		or not consequence.restore_snapshot(consequence_snapshot.duplicate(true))
		or consequence.snapshot() != consequence_snapshot
	):
		return false
	var definitions_value: Variant = registry.call("get_by_category", &"dungeon_event", &"LAUNCH")
	if not definitions_value is Array or (definitions_value as Array).is_empty():
		return false
	var definitions: Array[Dictionary] = []
	for definition_value: Variant in definitions_value as Array:
		var definition := _closed_definition(definition_value, DungeonEventDefinitionScript.ROOT_FIELDS)
		if definition.is_empty():
			return false
		definitions.append(definition)
	var runtime = DungeonEventRuntimeScript.new()
	return (
		runtime.configure(
			definitions, DungeonEventSelectorScript.new(), event_state,
			EventRequirementServiceScript.new(), consequence,
			func() -> Dictionary: return {},
			func(_command: Dictionary, _revision: int) -> Dictionary: return {},
			func(_fact_id: String, _payload: Dictionary) -> bool: return false,
			_event_publication_secret
		)
		and runtime.restore_snapshot(event_runtime.duplicate(true))
		and runtime.snapshot() == event_runtime
	)


func _authored_event_selection(
	registry: Variant,
	event_id: String,
	option_id: String,
	outcome_id: String
) -> Dictionary:
	var definition_value: Variant = registry.call(
		"resolve_dungeon_event", StringName(event_id)
	)
	if not definition_value is Dictionary or (definition_value as Dictionary).is_empty():
		return _failure(&"EVENT_RUNTIME_INVALID")
	var definition := definition_value as Dictionary
	if (
		str(definition.get("category", "")) != "dungeon_event"
		or str(definition.get("id", "")) != event_id
	):
		return _failure(&"EVENT_RUNTIME_INVALID")
	if option_id.is_empty() and outcome_id.is_empty():
		return {"ok": true, "definition": definition.duplicate(true), "option": {}, "outcome": {}}
	if option_id.is_empty() or outcome_id.is_empty():
		return _failure(&"EVENT_RUNTIME_INVALID")
	for option_value: Variant in definition.get("options", []):
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		if str(option.get("id", "")) != option_id:
			continue
		for outcome_value: Variant in option.get("outcomes", []):
			if (
				outcome_value is Dictionary
				and str((outcome_value as Dictionary).get("id", "")) == outcome_id
			):
				return {
					"ok": true,
					"definition": definition.duplicate(true),
					"option": option.duplicate(true),
					"outcome": (outcome_value as Dictionary).duplicate(true),
				}
	return _failure(&"EVENT_RUNTIME_INVALID")


func _expected_event_publication_payloads(
	assignments: Dictionary,
	receipts: Dictionary,
	encounter_success: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	var required_encounter_ids: Array[String] = []
	for node_key_value: Variant in assignments.keys():
		var node_key := str(node_key_value)
		var assignment := assignments[node_key_value] as Dictionary
		var event_id := str(assignment.get("event_id", ""))
		result["event_opened:%s:%s" % [node_key, event_id]] = {
			"kind": "event_opened", "event_id": event_id, "node_key": node_key,
		}
		var transaction_id := str(assignment.get("transaction_id", ""))
		if transaction_id.is_empty():
			continue
		if receipts.has(transaction_id):
			var receipt := receipts[transaction_id] as Dictionary
			result["event_committed:%s" % transaction_id] = {
				"kind": "event_committed",
				"event_id": event_id,
				"node_key": node_key,
				"phase": str(receipt.get("phase", "")),
				"pending_kind": str(receipt.get("pending_kind", "")),
				"result_key": str(receipt.get("result_key", "")),
			}
			var pending_kind := str(receipt.get("pending_kind", ""))
			var phase := str(assignment.get("phase", ""))
			if pending_kind == "reward" and phase in ["resolved", "dismissed"]:
				result["event_reward_completed:%s" % transaction_id] = {
					"kind": "event_reward_completed",
					"event_id": event_id,
					"node_key": node_key,
					"result_key": str(assignment.get("outcome_key", "")),
				}
			elif pending_kind == "encounter" and phase in ["resolved", "dismissed"]:
				required_encounter_ids.append(transaction_id)
				if not encounter_success.has(transaction_id):
					return {}
				result["event_encounter_completed:%s" % transaction_id] = {
					"kind": "event_encounter_completed",
					"event_id": event_id,
					"node_key": node_key,
					"result_key": str(assignment.get("outcome_key", "")),
					"success": bool(encounter_success[transaction_id]),
				}
		if str(assignment.get("phase", "")) == "dismissed":
			result["event_dismissed:%s" % transaction_id] = {
				"kind": "event_dismissed",
				"event_id": event_id,
				"node_key": node_key,
				"result_key": str(assignment.get("result_key", "")),
			}
	var actual_encounter_ids: Array[String] = []
	for key_value: Variant in encounter_success.keys():
		if typeof(encounter_success[key_value]) != TYPE_BOOL:
			return {}
		actual_encounter_ids.append(str(key_value))
	required_encounter_ids.sort()
	actual_encounter_ids.sort()
	return result if required_encounter_ids == actual_encounter_ids else {}


func _event_publication_facts(
	event_runtime: Dictionary,
	expected_payloads: Dictionary
) -> Dictionary:
	if (
		not event_runtime.get("emitted_fact_ids") is Array
		or not event_runtime.get("pending_facts") is Array
		or not event_runtime.get("publication_ledger") is Array
		or not _is_sha256(event_runtime.get("publication_digest"))
	):
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "publication"})
	var emitted_value: Variant = _sorted_stable_ids(event_runtime["emitted_fact_ids"])
	if emitted_value == null:
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "emitted_fact_ids"})
	var emitted := emitted_value as Array
	if emitted != event_runtime["emitted_fact_ids"]:
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "emitted_fact_ids"})
	var pending_by_id: Dictionary = {}
	var previous_pending_id := ""
	for pending_value: Variant in event_runtime["pending_facts"] as Array:
		if not pending_value is Dictionary:
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "pending_facts"})
		var pending := pending_value as Dictionary
		var fact_id := str(pending.get("fact_id", ""))
		if (
			not _has_exact_fields(pending, EVENT_PENDING_FACT_FIELDS)
			or not pending.get("payload") is Dictionary
			or fact_id.is_empty()
			or pending_by_id.has(fact_id)
			or emitted.has(fact_id)
			or (not previous_pending_id.is_empty() and fact_id <= previous_pending_id)
		):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "pending_facts"})
		pending_by_id[fact_id] = (pending["payload"] as Dictionary).duplicate(true)
		previous_pending_id = fact_id
	var ledger := event_runtime["publication_ledger"] as Array
	if ledger.size() != emitted.size() + pending_by_id.size():
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "publication_ledger"})
	var facts: Array[Dictionary] = []
	var recorded_ids: Array[String] = []
	var previous_fact_id := ""
	for sequence: int in range(ledger.size()):
		var entry_value: Variant = ledger[sequence]
		if not entry_value is Dictionary:
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "publication_ledger"})
		var entry := entry_value as Dictionary
		var fact_id := str(entry.get("fact_id", ""))
		var status := str(entry.get("status", ""))
		if (
			not _has_exact_fields(entry, EVENT_LEDGER_FIELDS)
			or not _is_sha256(entry.get("chain_hash"))
			or not entry.get("payload") is Dictionary
			or not expected_payloads.has(fact_id)
			or entry["payload"] != expected_payloads[fact_id]
			or (not previous_fact_id.is_empty() and fact_id <= previous_fact_id)
			or (status == "emitted" and not emitted.has(fact_id))
			or (status == "pending" and not pending_by_id.has(fact_id))
			or status not in ["emitted", "pending"]
		):
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "publication_ledger"})
		if status == "pending" and pending_by_id[fact_id] != entry["payload"]:
			return _failure(&"EVENT_RUNTIME_INVALID", {"field": "pending_payload"})
		var fact := entry.duplicate(true)
		fact["sequence"] = sequence
		facts.append(fact)
		recorded_ids.append(fact_id)
		previous_fact_id = fact_id
	var expected_ids: Array[String] = []
	for fact_id_value: Variant in expected_payloads.keys():
		expected_ids.append(str(fact_id_value))
	expected_ids.sort()
	if recorded_ids != expected_ids:
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "publication_fact_ids"})
	if (
		not ledger.is_empty()
		and str(event_runtime["publication_digest"])
		!= str((ledger[-1] as Dictionary).get("chain_hash", ""))
	):
		return _failure(&"EVENT_RUNTIME_INVALID", {"field": "publication_digest"})
	return {"ok": true, "code": &"OK", "facts": facts}


func _run_economy_is_valid(value: Dictionary, registry: Variant) -> bool:
	if (
		registry == null
		or not registry is Object
		or not registry.has_method("resolve_economy_profile")
	):
		return false
	var profile_id_value: Variant = value.get("profile_id")
	if typeof(profile_id_value) != TYPE_STRING:
		return false
	var profile_value: Variant = registry.call(
		"resolve_economy_profile", StringName(str(profile_id_value))
	)
	if not profile_value is Dictionary or (profile_value as Dictionary).is_empty():
		return false
	var profile := _closed_definition(
		profile_value as Dictionary, EconomyProfileScript.ROOT_FIELDS
	)
	if profile.is_empty():
		return false
	var candidate = RunEconomyStateScript.new()
	var configured: Dictionary = candidate.configure(
		profile, int(value.get("initial_gold", -1))
	)
	return bool(configured.get("ok", false)) and candidate.can_restore_snapshot(value)


func _merchant_state_is_valid(value: Dictionary) -> bool:
	var fingerprint_value: Variant = value.get("content_fingerprint")
	if typeof(fingerprint_value) != TYPE_STRING:
		return false
	var candidate = MerchantRunStateScript.new()
	var configured: Dictionary = candidate.configure(str(fingerprint_value))
	return bool(configured.get("ok", false)) and candidate.can_restore_snapshot(value)


func _merchant_transaction_facts(merchant_state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node_value: Variant in merchant_state.get("nodes", []):
		if not node_value is Dictionary:
			return []
		var node := node_value as Dictionary
		for transaction_value: Variant in node.get("transactions", []):
			if not transaction_value is Dictionary:
				return []
			var transaction := transaction_value as Dictionary
			var fact := {
				"sequence": transaction.get("sequence"),
				"floor_id": node.get("floor_id"),
				"node_id": node.get("node_id"),
				"merchant_id": node.get("merchant_id"),
				"transaction_id": transaction.get("transaction_id"),
				"kind": transaction.get("kind"),
				"offer_id": transaction.get("offer_id"),
				"reward_id": transaction.get("reward_id"),
				"service_id": transaction.get("service_id"),
				"cost_kind": transaction.get("cost_kind"),
				"amount": transaction.get("amount"),
				"economy_revision": transaction.get("economy_revision"),
				"inventory_revision": transaction.get("inventory_revision"),
			}
			if not _has_exact_fields(fact, MERCHANT_TRANSACTION_FIELDS):
				return []
			result.append(fact)
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["sequence"]) < int(right["sequence"])
	)
	for index: int in range(result.size()):
		if int(result[index].get("sequence", -1)) != index + 1:
			return []
	return result


func _merchant_transactions_are_empty(merchant_state: Dictionary) -> bool:
	for node_value: Variant in merchant_state.get("nodes", []):
		if (
			node_value is Dictionary
			and not ((node_value as Dictionary).get("transactions", []) as Array).is_empty()
		):
			return false
	return true


func _merchant_audit_facts(merchant_state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node_value: Variant in merchant_state.get("nodes", []):
		if not node_value is Dictionary:
			return []
		var node := node_value as Dictionary
		var inventory_value: Variant = node.get("inventory")
		var runtime_value: Variant = node.get("runtime")
		var service_value: Variant = node.get("service")
		if (
			not inventory_value is Dictionary
			or not runtime_value is Dictionary
			or not service_value is Dictionary
		):
			return []
		var inventory := inventory_value as Dictionary
		var runtime := runtime_value as Dictionary
		var service := service_value as Dictionary
		if typeof(inventory.get("reroll_count")) != TYPE_INT or not inventory.get("offers") is Array:
			return []
		var sold_offer_ids: Array[String] = []
		for offer_value: Variant in inventory["offers"]:
			if (
				not offer_value is Dictionary
				or typeof((offer_value as Dictionary).get("offer_id")) != TYPE_STRING
				or typeof((offer_value as Dictionary).get("sold")) != TYPE_BOOL
			):
				return []
			if bool((offer_value as Dictionary)["sold"]):
				sold_offer_ids.append(str((offer_value as Dictionary)["offer_id"]))
		sold_offer_ids.sort()
		var completed_ids: Variant = _sorted_stable_ids(
			runtime.get("completed_transaction_ids")
		)
		var service_completed_ids: Variant = _completed_ids_from_snapshot(service)
		if completed_ids == null or service_completed_ids == null:
			return []
		var fact := {
			"floor_id": node.get("floor_id"),
			"node_id": node.get("node_id"),
			"merchant_id": node.get("merchant_id"),
			"sold_offer_ids": sold_offer_ids,
			"reroll_count": int(inventory["reroll_count"]),
			"completed_transaction_ids": completed_ids,
			"service_completed_transaction_ids": service_completed_ids,
		}
		if not _has_exact_fields(fact, MERCHANT_AUDIT_FIELDS):
			return []
		result.append(fact)
	return result


func _sorted_stable_ids(value: Variant) -> Variant:
	if not value is Array:
		return null
	var result: Array[String] = []
	var seen: Dictionary = {}
	for id_value: Variant in value as Array:
		if typeof(id_value) != TYPE_STRING:
			return null
		var stable_id := str(id_value)
		if not _matches(STABLE_ID_PATTERN, stable_id) or seen.has(stable_id):
			return null
		seen[stable_id] = true
		result.append(stable_id)
	result.sort()
	return result


func _completed_ids_from_snapshot(snapshot: Dictionary) -> Variant:
	if snapshot.has("completed_transaction_ids"):
		return _sorted_stable_ids(snapshot["completed_transaction_ids"])
	var found := false
	var ids: Array[String] = []
	var seen: Dictionary = {}
	for key_value: Variant in snapshot.keys():
		var child: Variant = snapshot[key_value]
		var child_dictionaries: Array[Dictionary] = []
		if child is Dictionary:
			child_dictionaries.append(child as Dictionary)
		elif child is Array:
			for entry: Variant in child as Array:
				if entry is Dictionary:
					child_dictionaries.append(entry as Dictionary)
		for child_dictionary: Dictionary in child_dictionaries:
			var child_ids: Variant = _completed_ids_from_snapshot(child_dictionary)
			if child_ids == null:
				continue
			found = true
			for id_value: Variant in child_ids as Array:
				var transaction_id := str(id_value)
				if seen.has(transaction_id):
					continue
				seen[transaction_id] = true
				ids.append(transaction_id)
	if not found:
		return null
	ids.sort()
	return ids


func _economy_merchant_pair_is_consistent(
	run_economy: Dictionary,
	merchant_facts: Array[Dictionary]
) -> bool:
	var ledger_by_revision: Dictionary = {}
	for entry_value: Variant in run_economy.get("ledger", []):
		if not entry_value is Dictionary:
			return false
		var entry := entry_value as Dictionary
		ledger_by_revision[int(entry.get("revision", -1))] = entry
	for fact: Dictionary in merchant_facts:
		var cost_kind := str(fact.get("cost_kind", ""))
		var is_sell_payout := (
			cost_kind == "reward"
			and str(fact.get("kind", "")) == "service"
			and str(fact.get("service_id", "")) == "sell_reward"
		)
		if cost_kind != "gold" and not is_sell_payout:
			continue
		var revision := int(fact.get("economy_revision", -1))
		if not ledger_by_revision.has(revision):
			return false
		var ledger_entry := ledger_by_revision[revision] as Dictionary
		var expected_operation := (
			"gold_delta"
			if is_sell_payout
			else "gold_%s" % str(fact.get("kind", ""))
		)
		var ledger_amount := int(ledger_entry.get("amount", 0))
		if (
			str(ledger_entry.get("transaction_id", ""))
			!= str(fact.get("transaction_id", ""))
			or str(ledger_entry.get("operation", "")) != expected_operation
			or (is_sell_payout and ledger_amount <= 0)
			or (
				(ledger_amount if is_sell_payout else absi(ledger_amount))
				!= int(fact.get("amount", -1))
			)
		):
			return false
	return true


func _merchant_audit_drift(expected: Array, actual: Array) -> Dictionary:
	if expected.size() != actual.size():
		return _failure(&"MERCHANT_STATE_DRIFT", {
			"field": "nodes", "expected_count": expected.size(), "actual_count": actual.size(),
		})
	for index: int in range(expected.size()):
		if not expected[index] is Dictionary or not actual[index] is Dictionary:
			return _failure(&"MERCHANT_STATE_DRIFT", {"field": "nodes", "index": index})
		var expected_fact := expected[index] as Dictionary
		var actual_fact := actual[index] as Dictionary
		if (
			not _has_exact_fields(expected_fact, MERCHANT_AUDIT_FIELDS)
			or not _has_exact_fields(actual_fact, MERCHANT_AUDIT_FIELDS)
		):
			return _failure(&"MERCHANT_STATE_DRIFT", {
				"field": "merchant_audit_facts", "index": index,
			})
		for identity_field: String in ["floor_id", "node_id", "merchant_id"]:
			if expected_fact.get(identity_field) != actual_fact.get(identity_field):
				return _failure(&"MERCHANT_STATE_DRIFT", {
					"field": identity_field, "index": index,
				})
		var node_key := "%s:%s" % [
			str(actual_fact.get("floor_id", "")), str(actual_fact.get("node_id", "")),
		]
		if expected_fact.get("sold_offer_ids") != actual_fact.get("sold_offer_ids"):
			return _failure(&"MERCHANT_SOLD_STATE_DRIFT", {
				"field": "sold_offer_ids", "node_key": node_key,
			})
		if expected_fact.get("reroll_count") != actual_fact.get("reroll_count"):
			return _failure(&"MERCHANT_REROLL_STATE_DRIFT", {
				"field": "reroll_count", "node_key": node_key,
			})
		if (
			expected_fact.get("completed_transaction_ids")
			!= actual_fact.get("completed_transaction_ids")
			or expected_fact.get("service_completed_transaction_ids")
			!= actual_fact.get("service_completed_transaction_ids")
		):
			return _failure(&"MERCHANT_COMPLETED_TRANSACTION_DRIFT", {
				"field": "completed_transaction_ids", "node_key": node_key,
			})
	return {}


func _first_array_drift(expected: Array, actual: Array, field: String) -> Dictionary:
	var shared := mini(expected.size(), actual.size())
	for index: int in range(shared):
		if expected[index] != actual[index]:
			return {"field": field, "sequence": index + 1}
	return {
		"field": field,
		"sequence": shared + 1,
		"expected_count": expected.size(),
		"actual_count": actual.size(),
	}


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
