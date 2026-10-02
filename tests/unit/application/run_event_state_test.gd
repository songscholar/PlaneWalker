extends Node

const ConsequenceRuntimeScript := preload("res://scripts/events/dungeon_event_consequence_runtime.gd")
const DungeonEventRuntimeScript := preload("res://scripts/events/dungeon_event_runtime.gd")
const DungeonEventRunStateScript := preload("res://scripts/events/dungeon_event_run_state.gd")
const DungeonEventSelectorScript := preload("res://scripts/events/dungeon_event_selector.gd")
const EventHealthAuthorityScript := preload("res://scripts/events/event_health_authority.gd")
const EventModifierAuthorityScript := preload("res://scripts/events/event_modifier_authority.gd")
const EventRequirementServiceScript := preload("res://scripts/events/event_requirement_service.gd")
const EventResourceAuthorityScript := preload("res://scripts/events/event_resource_authority.gd")
const EventRouteAuthorityScript := preload("res://scripts/events/event_route_authority.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const MerchantRunStateScript := preload("res://scripts/economy/merchant_run_state.gd")
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const CONTENT_FINGERPRINT := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"
const ECONOMY_PATH := "res://data/content_packs/base/content/economy_profiles.json"
const EVENT_PATH := "res://data/content_packs/base/content/dungeon_events.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var floors := _load_json_array(FLOOR_PATH)
	var templates := _load_json_array(TEMPLATE_PATH)
	if floors.is_empty() or templates.is_empty():
		suite.assert_true(false, "event RunState fixtures load")
		suite.finish(get_tree())
		return
	_test_initialization_snapshot_and_restore(suite, floors[0], templates)
	_test_atomic_event_candidate_commit(suite, floors[0], templates)
	_test_pending_route_rejects_external_commit(suite, floors[0], templates)
	suite.finish(get_tree())


func _test_initialization_snapshot_and_restore(suite, floor: Dictionary, templates: Array) -> void:
	var blank = _started_orchestrator("run-event-state-reset")
	var blank_snapshot: Dictionary = blank.snapshot()
	suite.assert_equal(blank_snapshot.get("dungeon_event_runtime"), {}, "reset leaves event runtime uninitialized")
	suite.assert_equal(blank_snapshot.get("seen_event_ids"), [], "compatibility event projection starts empty")

	var fixture := _event_room_fixture(suite, floor, templates, "run-event-state-init")
	if fixture.is_empty():
		return
	var orchestrator = fixture["orchestrator"]
	var runtime_snapshot := fixture["runtime_snapshot"] as Dictionary
	var snapshot: Dictionary = orchestrator.snapshot()
	suite.assert_equal(snapshot.get("dungeon_event_runtime"), runtime_snapshot, "main snapshot owns complete event runtime")
	suite.assert_equal(snapshot.get("seen_event_ids"), [], "seen events derive from nested event state")
	var floor_snapshot: Dictionary = orchestrator.floor_transaction_snapshot()
	suite.assert_equal(floor_snapshot.get("dungeon_event_runtime"), runtime_snapshot, "floor rollback owns complete event runtime")

	var seen_drift := floor_snapshot.duplicate(true)
	seen_drift["seen_event_ids"] = ["event_forged"]
	var before_reject: Dictionary = orchestrator.floor_transaction_snapshot()
	suite.assert_true(not orchestrator.can_restore_floor_transaction_snapshot(seen_drift), "seen-event projection cannot drift")
	suite.assert_true(not orchestrator.restore_floor_transaction_snapshot(seen_drift), "seen-event drift cannot restore")
	suite.assert_equal(orchestrator.floor_transaction_snapshot(), before_reject, "projection rejection is byte-atomic")

	var event_drift := floor_snapshot.duplicate(true)
	_event_state(event_drift["dungeon_event_runtime"])["content_fingerprint"] = "b".repeat(64)
	suite.assert_true(not orchestrator.restore_floor_transaction_snapshot(event_drift), "nested event fingerprint drift rejects")
	suite.assert_equal(orchestrator.floor_transaction_snapshot(), before_reject, "runtime rejection is byte-atomic")

	var canonical: Dictionary = orchestrator.snapshot()
	suite.assert_true(orchestrator.restore_launch_run_snapshot(canonical, floor, templates), "main snapshot restores event runtime")
	var main_seen_drift := canonical.duplicate(true)
	main_seen_drift["seen_event_ids"] = ["event_forged"]
	suite.assert_true(not orchestrator.restore_launch_run_snapshot(main_seen_drift, floor, templates), "main restore rejects seen drift")
	suite.assert_equal(orchestrator.snapshot(), canonical, "rejected main restore is byte-atomic")


func _test_atomic_event_candidate_commit(suite, floor: Dictionary, templates: Array) -> void:
	var fixture := _event_room_fixture(suite, floor, templates, "run-event-state-commit")
	if fixture.is_empty():
		return
	var orchestrator = fixture["orchestrator"]
	var node := fixture["node"] as Dictionary
	var before_event := _event_state(orchestrator.snapshot()["dungeon_event_runtime"])
	var event_id := str(node.get("event_id", "event_cursed_pool"))
	var assigned_event := _assigned_event_snapshot(
		before_event,
		str(orchestrator.snapshot()["floor_plan"]["floor_id"]),
		int(orchestrator.snapshot()["current_floor_index"]),
		str(node["id"]),
		event_id
	)
	var assigned_runtime := _runtime_snapshot(
		orchestrator.snapshot()["floor_plan"], orchestrator.snapshot()["run_economy"],
		assigned_event, str(node["id"]), event_id, orchestrator.snapshot()["build"]
	)
	var before_revision: int = orchestrator.revision()
	var committed = orchestrator.commit_event_transaction(
		_candidate(orchestrator, assigned_runtime), before_revision
	)
	suite.assert_true(committed.ok, "complete five-domain event candidate commits")
	suite.assert_equal(committed.new_revision, before_revision + 1, "event transaction advances once")
	var after: Dictionary = orchestrator.snapshot()
	suite.assert_equal(after["dungeon_event_runtime"], assigned_runtime, "event runtime installs exactly")
	suite.assert_equal(after["seen_event_ids"], assigned_event["seen_run_event_ids"], "seen events recompute from nested state")

	var exact := _candidate(orchestrator, assigned_runtime)
	var missing := exact.duplicate(true)
	missing.erase("resources")
	_assert_candidate_rejected(suite, orchestrator, missing, "missing candidate field")
	var extra := exact.duplicate(true)
	extra["unknown"] = true
	_assert_candidate_rejected(suite, orchestrator, extra, "extra candidate field")

	var event_drift := exact.duplicate(true)
	_event_state(event_drift["dungeon_event_runtime"])["content_fingerprint"] = "b".repeat(64)
	_assert_candidate_rejected(suite, orchestrator, event_drift, "event candidate drift")
	var economy_drift := exact.duplicate(true)
	economy_drift["run_economy"]["balance"] = int(economy_drift["run_economy"]["balance"]) + 1
	_assert_candidate_rejected(suite, orchestrator, economy_drift, "economy candidate drift")
	var floor_drift := exact.duplicate(true)
	floor_drift["floor_plan"]["generation_digest"] = "forged"
	_assert_candidate_rejected(suite, orchestrator, floor_drift, "floor candidate drift")
	var resource_drift := exact.duplicate(true)
	resource_drift["resources"]["resource"]["resources"]["time_shard"] = 999
	_assert_candidate_rejected(suite, orchestrator, resource_drift, "resource candidate drift")
	var build_drift := exact.duplicate(true)
	build_drift["build"]["dominant_archetype"] = "forged"
	_assert_candidate_rejected(suite, orchestrator, build_drift, "build candidate drift")
	var curse_drift := exact.duplicate(true)
	_modifier_state(curse_drift["dungeon_event_runtime"])["curse_ids"] = ["curse_fickle_time"]
	_assert_candidate_rejected(suite, orchestrator, curse_drift, "modifier build-curse drift")
	var flags_drift := exact.duplicate(true)
	_modifier_state(flags_drift["dungeon_event_runtime"])["narrative_flags"] = {"forged": true}
	_assert_candidate_rejected(suite, orchestrator, flags_drift, "modifier event-flag drift")

	var economy_authority = RunEconomyStateScript.new()
	var economy_profile := _load_json_array(ECONOMY_PATH)[0] as Dictionary
	suite.assert_true(bool(economy_authority.configure(economy_profile, 100).get("ok", false)), "economy writer configures")
	suite.assert_true(economy_authority.restore_snapshot(orchestrator.snapshot()["run_economy"]), "economy writer restores authority")
	var prepared: Dictionary = economy_authority.prepare_transaction(
		"event_gold_spend", -25, economy_authority.revision(), {"operation": "gold_delta"}
	)
	var economy_commit: Dictionary = economy_authority.commit_transaction(prepared.get("ticket", {}))
	suite.assert_true(bool(economy_commit.get("ok", false)), "negative gold delta commits through RunEconomyState")
	var spend_runtime := _runtime_snapshot(
		orchestrator.snapshot()["floor_plan"], economy_authority.snapshot(),
		assigned_event, str(node["id"]), event_id, orchestrator.snapshot()["build"]
	)
	var spend_before_revision: int = orchestrator.revision()
	var spent = orchestrator.commit_event_transaction(
		_candidate(orchestrator, spend_runtime), spend_before_revision
	)
	suite.assert_true(spent.ok, "event transaction accepts canonical negative gold delta")
	suite.assert_equal(spent.new_revision, spend_before_revision + 1, "gold event transaction advances once")
	suite.assert_equal(orchestrator.snapshot()["run_economy"]["balance"], 75, "RunEconomyState remains gold writer")


func _test_pending_route_rejects_external_commit(suite, floor: Dictionary, templates: Array) -> void:
	var fixture := _event_room_fixture(suite, floor, templates, "run-event-state-route")
	if fixture.is_empty():
		return
	var orchestrator = fixture["orchestrator"]
	var node := fixture["node"] as Dictionary
	suite.assert_true(orchestrator.complete_floor_node(str(node["id"]), orchestrator.revision()).ok, "route fixture clears event room")
	var edge := _first_outgoing_edge(orchestrator.snapshot()["floor_plan"])
	if edge.is_empty():
		suite.assert_true(false, "event room exposes an outgoing route")
		return
	var begun = orchestrator.begin_route_transition(StringName(str(edge["id"])), orchestrator.revision())
	suite.assert_true(begun.ok, "route fixture stages external route")
	var before: Dictionary = orchestrator.snapshot()
	var rejected = orchestrator.commit_event_transaction(
		_candidate(orchestrator, orchestrator.snapshot()["dungeon_event_runtime"]), orchestrator.revision()
	)
	suite.assert_equal(rejected.code, &"INVALID_PHASE", "pending route blocks event submission")
	suite.assert_equal(orchestrator.snapshot(), before, "pending-route rejection is byte-atomic")


func _event_room_fixture(suite, floor: Dictionary, templates: Array, run_id: String) -> Dictionary:
	var orchestrator = _started_orchestrator(run_id)
	var economy_initialized = orchestrator.initialize_launch_economy(
		_economy_snapshot(100, 100, []), _empty_merchant_snapshot(), orchestrator.revision()
	)
	suite.assert_true(economy_initialized.ok, "event fixture initializes economy")
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261002, floor, templates)
	if not bool(generated.get("ok", false)):
		suite.assert_true(false, "event fixture generates a floor")
		return {}
	var started = orchestrator.start_floor(generated["plan"], floor, templates, orchestrator.revision())
	suite.assert_true(started.ok, "event fixture starts floor")
	if not started.ok:
		return {}
	var node := _navigate_to_room_type(suite, orchestrator, "event")
	if node.is_empty():
		return {}
	var runtime_snapshot := _runtime_snapshot(
		orchestrator.snapshot()["floor_plan"], orchestrator.snapshot()["run_economy"],
		_empty_event_snapshot(), "", "", orchestrator.snapshot()["build"]
	)
	var before_revision: int = orchestrator.revision()
	var runtime_initialized = orchestrator.initialize_launch_events(runtime_snapshot, before_revision)
	suite.assert_true(runtime_initialized.ok, "event fixture initializes complete runtime")
	suite.assert_equal(runtime_initialized.new_revision, before_revision + 1, "runtime initialization advances once")
	return {"orchestrator": orchestrator, "node": node, "runtime_snapshot": runtime_snapshot}


func _candidate(orchestrator, runtime_snapshot: Dictionary) -> Dictionary:
	var state: RefCounted = orchestrator.get("_state")
	var participants := _participants(runtime_snapshot)
	return {
		"dungeon_event_runtime": runtime_snapshot.duplicate(true),
		"run_economy": (participants["economy"] as Dictionary).duplicate(true),
		"floor_plan": ((participants["route"] as Dictionary)["plan"] as Dictionary).duplicate(true),
		"resources": {
			"resource": (participants["resource"] as Dictionary).duplicate(true),
			"health": (participants["health"] as Dictionary).duplicate(true),
		},
		"build": state.get("build_state").call("transaction_snapshot").duplicate(true),
	}


func _runtime_snapshot(
	plan: Dictionary,
	economy_snapshot: Dictionary,
	event_snapshot: Dictionary,
	active_node_id: String,
	active_event_id: String,
	build_snapshot: Dictionary
) -> Dictionary:
	var resource = EventResourceAuthorityScript.new()
	assert(resource.configure({"time_shard": 2, "forge_essence": 1}))
	var health = EventHealthAuthorityScript.new()
	assert(health.configure(50.0, 100.0))
	var economy = RunEconomyStateScript.new()
	assert(bool(economy.configure(_load_json_array(ECONOMY_PATH)[0], 100).get("ok", false)))
	assert(economy.restore_snapshot(economy_snapshot))
	var modifier = EventModifierAuthorityScript.new()
	assert(modifier.configure(
		(build_snapshot.get("curses", []) as Array).duplicate(),
		(event_snapshot.get("narrative_flags", {}) as Dictionary).duplicate(true),
		(event_snapshot.get("temporary_modifiers", []) as Array).duplicate(true)
	))
	var route = EventRouteAuthorityScript.new()
	assert(route.configure(plan))
	var event_state = DungeonEventRunStateScript.new()
	assert(bool(event_state.configure(CONTENT_FINGERPRINT).get("ok", false)))
	assert(event_state.restore_snapshot(event_snapshot))
	var consequences = ConsequenceRuntimeScript.new()
	assert(consequences.configure(resource, health, economy, modifier, route, event_state))
	var runtime = DungeonEventRuntimeScript.new()
	assert(runtime.configure(
		_load_json_array(EVENT_PATH), DungeonEventSelectorScript.new(), event_state,
		EventRequirementServiceScript.new(), consequences,
		Callable(self, "_runtime_context"), Callable(self, "_runtime_state_sink"),
		Callable(self, "_runtime_fact_sink"), "run-event-state-test-publication-secret"
	))
	if not active_node_id.is_empty():
		runtime.set("_active_node_key", "%s:%s" % [str(plan["floor_id"]), active_node_id])
		runtime.set("_active_event_id", active_event_id)
	return runtime.snapshot()


func _assigned_event_snapshot(
	before: Dictionary,
	floor_id: String,
	floor_index: int,
	node_id: String,
	event_id: String
) -> Dictionary:
	var authority = DungeonEventRunStateScript.new()
	authority.configure(CONTENT_FINGERPRINT)
	assert(authority.restore_snapshot(before))
	var assigned: Dictionary = authority.assign_event({
		"floor_id": floor_id, "floor_index": floor_index, "node_id": node_id,
		"event_id": event_id, "repeat_policy": "repeatable",
	}, int(before["revision"]))
	assert(bool(assigned.get("ok", false)))
	return authority.snapshot()


func _empty_event_snapshot() -> Dictionary:
	var authority = DungeonEventRunStateScript.new()
	assert(bool(authority.configure(CONTENT_FINGERPRINT).get("ok", false)))
	return authority.snapshot()


func _event_state(runtime_snapshot: Dictionary) -> Dictionary:
	return _participants(runtime_snapshot)["event_state"] as Dictionary


func _modifier_state(runtime_snapshot: Dictionary) -> Dictionary:
	return _participants(runtime_snapshot)["modifier"] as Dictionary


func _participants(runtime_snapshot: Dictionary) -> Dictionary:
	return ((runtime_snapshot["consequence_runtime"] as Dictionary)["participant_snapshots"] as Dictionary)


func _assert_candidate_rejected(suite, orchestrator, candidate: Dictionary, label: String) -> void:
	var before: Dictionary = orchestrator.snapshot()
	var rejected = orchestrator.commit_event_transaction(candidate, orchestrator.revision())
	suite.assert_equal(rejected.code, &"INVALID_ARGUMENT", "%s rejects" % label)
	suite.assert_equal(orchestrator.snapshot(), before, "%s is byte-atomic" % label)


func _navigate_to_room_type(suite, orchestrator, room_type: String) -> Dictionary:
	var path := _path_to_room_type(orchestrator.snapshot()["floor_plan"], room_type)
	if path.is_empty():
		suite.assert_true(false, "generated floor exposes a reachable %s room" % room_type)
		return {}
	for edge_value: Variant in path:
		var edge := edge_value as Dictionary
		var begun = orchestrator.begin_route_transition(StringName(str(edge["id"])), orchestrator.revision())
		if not begun.ok:
			suite.assert_true(false, "event path route begins")
			return {}
		var finalized = orchestrator.finalize_route_transition(str(begun.context["transition_id"]), orchestrator.revision())
		if not finalized.ok:
			suite.assert_true(false, "event path route finalizes")
			return {}
		var node_id := str(edge["destination_node_id"])
		if not orchestrator.enter_floor_node(node_id, orchestrator.revision()).ok:
			suite.assert_true(false, "event path node enters")
			return {}
		var node := _node_by_id(orchestrator.snapshot()["floor_plan"], node_id)
		if str(node.get("room_type", "")) == room_type:
			suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.ROOM_ACTIVE, "event room uses RoomActive")
			return node
		if not orchestrator.complete_floor_node(node_id, orchestrator.revision()).ok:
			suite.assert_true(false, "event path intermediate room clears")
			return {}
	return {}


func _empty_merchant_snapshot() -> Dictionary:
	var authority = MerchantRunStateScript.new()
	assert(bool(authority.configure(CONTENT_FINGERPRINT).get("ok", false)))
	return authority.snapshot()


func _economy_snapshot(initial_gold: int, balance: int, ledger: Array) -> Dictionary:
	return {
		"schema_id": "planewalker.run_economy", "schema_version": 1,
		"profile_id": "launch_economy_v1", "initial_gold": initial_gold,
		"balance": balance, "revision": ledger.size(), "ledger": ledger.duplicate(true),
		"settled_floor_indices": [],
	}


func _started_orchestrator(run_id: String):
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run({
		"seed": 20261002, "difficulty": "normal",
		"character_id": "character_time_guardian", "weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"], "milestone": "LAUNCH",
	}, run_id)
	return orchestrator


func _runtime_context() -> Dictionary:
	return {
		"global_revision": 0,
		"requirements": {
			"floor_index": 0, "resources": {"time_shard": 2, "forge_essence": 1},
			"health": {"current": 50.0, "maximum": 100.0}, "gold": 100,
			"reward_tags": [], "curse_ids": [], "narrative_flags": {},
		},
		"selection": {"run_seed": 20261002, "floor_index": 0},
	}


func _runtime_state_sink(_candidate: Dictionary, expected_revision: int) -> Dictionary:
	return {"ok": true, "code": &"OK", "new_revision": expected_revision + 1, "context": {}}


func _runtime_fact_sink(_fact: Dictionary) -> bool:
	return true


func _path_to_room_type(plan: Dictionary, room_type: String) -> Array[Dictionary]:
	var outgoing: Dictionary = {}
	for edge_value: Variant in plan.get("edges", []):
		var edge := edge_value as Dictionary
		var source := str(edge["source_node_id"])
		if not outgoing.has(source):
			outgoing[source] = []
		(outgoing[source] as Array).append(edge.duplicate(true))
	for source_value: Variant in outgoing.keys():
		(outgoing[source_value] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["choice_order"]) < int(right["choice_order"])
		)
	var queue: Array[Dictionary] = [{"node_id": str(plan["current_node_id"]), "path": []}]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var cursor := queue.pop_front() as Dictionary
		var node_id := str(cursor["node_id"])
		if visited.has(node_id):
			continue
		visited[node_id] = true
		if str(_node_by_id(plan, node_id).get("room_type", "")) == room_type:
			var result: Array[Dictionary] = []
			for path_edge: Variant in cursor["path"]:
				result.append((path_edge as Dictionary).duplicate(true))
			return result
		for edge_value: Variant in outgoing.get(node_id, []):
			var edge := edge_value as Dictionary
			var next_path := (cursor["path"] as Array).duplicate(true)
			next_path.append(edge.duplicate(true))
			queue.append({"node_id": str(edge["destination_node_id"]), "path": next_path})
	return []


func _first_outgoing_edge(plan: Dictionary) -> Dictionary:
	var current := str(plan.get("current_node_id", ""))
	var candidates: Array[Dictionary] = []
	for edge_value: Variant in plan.get("edges", []):
		var edge := edge_value as Dictionary
		if str(edge.get("source_node_id", "")) == current:
			candidates.append(edge.duplicate(true))
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["choice_order"]) < int(right["choice_order"])
	)
	return candidates[0] if not candidates.is_empty() else {}


func _node_by_id(plan: Dictionary, node_id: String) -> Dictionary:
	for node_value: Variant in plan.get("nodes", []):
		var node := node_value as Dictionary
		if str(node.get("id", "")) == node_id:
			return node.duplicate(true)
	return {}


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Array).duplicate(true) if parsed is Array else []
