extends Node

const SuiteScript := preload("res://tests/support/test_suite.gd")
const FloorsScript := preload("res://scripts/dungeon/floor_definition.gd")
const LIFETIME_PATH := "res://scripts/events/event_modifier_lifetime.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = SuiteScript.new()
	suite.assert_true(ResourceLoader.exists(LIFETIME_PATH), "event effect lifetime authority exists")
	if ResourceLoader.exists(LIFETIME_PATH):
		var lifetime = load(LIFETIME_PATH)
		_test_successful_completion_and_expiry(lifetime, suite)
		_test_closed_boundaries(lifetime, suite)
		_test_source_authentication(lifetime, suite)
		_test_legacy_baselines(lifetime, suite)
	suite.finish(get_tree())


func _test_successful_completion_and_expiry(lifetime: GDScript, suite: RefCounted) -> void:
	var events: Array = [{"type": "legacy_fact", "value": 7}]
	var original := events.duplicate(true)
	var assignments := _assignments("tx_grace", 0, "event_1")
	var modifiers := [_modifier("tx_grace", 3)]
	var projected: Dictionary = lifetime.active_projection(events, assignments, modifiers)
	suite.assert_true(projected.get("ok", false), "a grant is active while its source room is still open")
	suite.assert_equal(projected.get("context", {}).get("modifiers", []).size(), 1, "open source consumes no duration")
	var appended: Dictionary = lifetime.append_completed_room(events, FloorsScript.FLOOR_IDS[0], 0, "event_1")
	suite.assert_true(appended.get("ok", false), "successful source room completion creates a typed fact")
	suite.assert_equal(events, original, "append does not mutate its caller's ledger")
	if not appended.get("ok", false):
		return
	events = appended["context"]["events"]
	suite.assert_equal(events[0], original[0], "existing unrelated event history survives")
	suite.assert_equal(events[1]["sequence"], 1, "successful room facts have their own contiguous sequence")
	projected = lifetime.active_projection(events, assignments, modifiers)
	suite.assert_equal(projected.get("context", {}).get("modifiers", []).size(), 1, "source room clear itself never consumes a room")
	var duplicate: Dictionary = lifetime.append_completed_room(events, FloorsScript.FLOOR_IDS[0], 0, "event_1")
	suite.assert_equal(duplicate.get("code"), &"ALREADY_COMPLETED", "duplicate source room completion cannot decrement again")
	for index: int in range(3):
		appended = lifetime.append_completed_room(events, FloorsScript.FLOOR_IDS[1], 1, "room_%d" % index)
		suite.assert_true(appended.get("ok", false), "successful later rooms advance the lifetime across a floor boundary")
		if not appended.get("ok", false):
			return
		events = appended["context"]["events"]
		projected = lifetime.active_projection(events, assignments, modifiers)
		suite.assert_true(projected.get("ok", false), "cross-floor active projection remains valid")
		suite.assert_equal(projected.get("context", {}).get("modifiers", []).size(), 1 if index < 2 else 0, "three later successful rooms expire exactly on the third clear")
	suite.assert_equal(modifiers[0]["duration_rooms"], 3, "expiry does not erase or rewrite the authenticated grant")
	var replayed: Dictionary = lifetime.active_projection(events.duplicate(true), assignments.duplicate(true), modifiers.duplicate(true))
	suite.assert_equal(replayed, projected, "Save/Replay reconstruction has identical lifetime output")
	assignments.merge(_assignments("tx_new_grace", 1, "event_2"))
	modifiers = [_modifier("tx_new_grace", 3)]
	projected = lifetime.active_projection(events, assignments, modifiers)
	suite.assert_equal(projected.get("context", {}).get("modifiers", []), [{"modifier_id": "chronal_grace", "magnitude": 1.15, "source_transaction_id": "tx_new_grace"}], "a fresh source can reacquire an expired identity")


func _test_closed_boundaries(lifetime: GDScript, suite: RefCounted) -> void:
	var first: Dictionary = lifetime.append_completed_room([], FloorsScript.FLOOR_IDS[0], 0, "room_1")
	if not first.get("ok", false):
		return
	var valid: Array = first["context"]["events"]
	var variants: Array = []
	for field: String in ["type", "sequence", "floor_id", "floor_index", "node_id"]:
		var missing := valid.duplicate(true)
		missing[0].erase(field)
		variants.append(missing)
	var unknown := valid.duplicate(true)
	unknown[0]["extra"] = true
	variants.append(unknown)
	var wrong_type := valid.duplicate(true)
	wrong_type[0]["type"] = "room_completed_v2"
	variants.append(wrong_type)
	var wrong_sequence := valid.duplicate(true)
	wrong_sequence[0]["sequence"] = 2
	variants.append(wrong_sequence)
	var wrong_floor := valid.duplicate(true)
	wrong_floor[0]["floor_index"] = 1
	variants.append(wrong_floor)
	var duplicate := valid.duplicate(true)
	duplicate.append(valid[0].duplicate(true))
	duplicate[1]["sequence"] = 2
	variants.append(duplicate)
	var reversed: Array = [
		{"type": "room_completed_v1", "sequence": 1, "floor_id": FloorsScript.FLOOR_IDS[1], "floor_index": 1, "node_id": "room_2"},
		{"type": "room_completed_v1", "sequence": 2, "floor_id": FloorsScript.FLOOR_IDS[0], "floor_index": 0, "node_id": "room_1"},
	]
	variants.append(reversed)
	for candidate: Array in variants:
		suite.assert_true(not lifetime.validate_events(candidate).get("ok", false), "malformed or ambiguous room lifetime history is rejected")
	for node_id: String in ["", "entry", "invalid room"]:
		suite.assert_true(not lifetime.append_completed_room(valid, FloorsScript.FLOOR_IDS[0], 0, node_id).get("ok", false), "only completed real room identities can enter the ledger")
	var mutated := valid.duplicate(true)
	lifetime.active_projection(mutated, _assignments("tx_grace", 0, "event_1"), [_modifier("tx_grace", 3)])
	suite.assert_equal(mutated, valid, "projection never mutates sealed completion facts")


func _test_source_authentication(lifetime: GDScript, suite: RefCounted) -> void:
	var modifier := _modifier("tx_grace", 3)
	suite.assert_true(not lifetime.active_projection([], {}, [modifier]).get("ok", false), "unbound modifier sources cannot be projected")
	var assignments := _assignments("tx_grace", 0, "event_1")
	var ambiguous := assignments.duplicate(true)
	ambiguous.merge(_assignments("tx_grace", 1, "event_2"))
	suite.assert_true(not lifetime.active_projection([], ambiguous, [modifier]).get("ok", false), "two event assignments cannot authenticate the same source")
	for phase: String in ["open", "reserved", "unknown"]:
		var uncommitted := assignments.duplicate(true)
		uncommitted.values()[0]["phase"] = phase
		suite.assert_true(not lifetime.active_projection([], uncommitted, [modifier]).get("ok", false), "uncommitted assignment does not authenticate an active effect")
	var forged := assignments.duplicate(true)
	forged.values()[0]["floor_index"] = 1
	suite.assert_true(not lifetime.active_projection([], forged, [modifier]).get("ok", false), "source floor identity and index must match")
	var extra := modifier.duplicate(true)
	extra["remaining_rooms"] = 100
	suite.assert_true(not lifetime.active_projection([], assignments, [extra]).get("ok", false), "client-supplied remaining duration is not accepted")
	var invalid := modifier.duplicate(true)
	invalid["magnitude"] = 11.0
	suite.assert_true(not lifetime.active_projection([], assignments, [invalid]).get("ok", false), "persisted effect magnitude keeps the authored boundary")


func _assignments(transaction_id: String, floor_index: int, node_id: String) -> Dictionary:
	var floor_id: String = FloorsScript.FLOOR_IDS[floor_index]
	return {"%s:%s" % [floor_id, node_id]: {"floor_id": floor_id, "floor_index": floor_index, "node_id": node_id, "transaction_id": transaction_id, "phase": "resolved"}}


func _test_legacy_baselines(lifetime: GDScript, suite: RefCounted) -> void:
	var authority = lifetime.new()
	suite.assert_true(authority.has_method("normalize_legacy_baselines"), "legacy modifier sources have an explicit one-time lifetime migration")
	if not authority.has_method("normalize_legacy_baselines"):
		return
	var events: Array = [{"type": "legacy_fact", "value": 7}]
	var original := events.duplicate(true)
	var assignments := _assignments("tx_legacy_grace", 0, "legacy_event")
	assignments.values()[0]["phase"] = "dismissed"
	var modifiers := [_modifier("tx_legacy_grace", 3)]
	var original_modifiers := modifiers.duplicate(true)
	var migrated: Dictionary = lifetime.normalize_legacy_baselines(events, assignments, modifiers)
	suite.assert_true(migrated.get("ok", false), "legacy dismissed source receives a conservative restore baseline")
	if not migrated.get("ok", false):
		return
	events = migrated["context"]["events"]
	suite.assert_equal(original, [{"type": "legacy_fact", "value": 7}], "legacy migration preserves its caller's ledger")
	suite.assert_equal(events, original + [{"type": "modifier_lifetime_baseline_v1", "source_transaction_id": "tx_legacy_grace", "after_room_sequence": 0}], "migration records its exact lifetime decision without fabricating room clears")
	suite.assert_equal(lifetime.normalize_legacy_baselines(events, assignments, modifiers).get("context", {}).get("events"), events, "repeated restore never resets an existing baseline")
	for index: int in range(3):
		var appended: Dictionary = lifetime.append_completed_room(events, FloorsScript.FLOOR_IDS[1], 1, "legacy_followup_%d" % index)
		suite.assert_true(appended.get("ok", false), "migrated source advances through later real completion facts")
		if not appended.get("ok", false):
			return
		events = appended["context"]["events"]
		var projected: Dictionary = lifetime.active_projection(events, assignments, modifiers)
		suite.assert_equal(projected.get("context", {}).get("modifiers", []).size(), 1 if index < 2 else 0, "legacy grant expires on its third subsequent successful clear")
		suite.assert_equal(lifetime.normalize_legacy_baselines(events, assignments, modifiers).get("context", {}).get("events"), events, "restoring after each clear cannot extend the duration")
	suite.assert_equal(modifiers, original_modifiers, "migration and expiry preserve the sealed authored grant")
	var unresolved := _assignments("tx_unresolved", 1, "new_event")
	unresolved.merge(assignments)
	var unresolved_modifiers := [_modifier("tx_unresolved", 3)]
	var untouched: Dictionary = lifetime.normalize_legacy_baselines(events, unresolved, unresolved_modifiers)
	suite.assert_true(untouched.get("ok", false), "unresolved source remains valid without migration")
	suite.assert_equal(untouched.get("context", {}).get("events"), events, "normal unresolved grants never acquire legacy baselines")
	var completed: Dictionary = lifetime.append_completed_room([], FloorsScript.FLOOR_IDS[0], 0, "legacy_event")
	var source_history: Array = completed["context"]["events"]
	suite.assert_equal(lifetime.normalize_legacy_baselines(source_history, assignments, modifiers).get("context", {}).get("events"), source_history, "authenticated source clears need no legacy migration")
	var malformed: Array = [
		[{"type": "modifier_lifetime_baseline_v1", "source_transaction_id": "tx_legacy_grace", "after_room_sequence": 1}],
		[{"type": "modifier_lifetime_baseline_v1", "source_transaction_id": "tx_legacy_grace", "after_room_sequence": -1}],
		[{"type": "modifier_lifetime_baseline_v2", "source_transaction_id": "tx_legacy_grace", "after_room_sequence": 0}],
		[{"type": "modifier_lifetime_baseline_v1", "source_transaction_id": "", "after_room_sequence": 0}],
		[{"type": "modifier_lifetime_baseline_v1", "source_transaction_id": "tx_legacy_grace", "after_room_sequence": 0, "extra": true}],
		[{"type": "modifier_lifetime_baseline_v1", "source_transaction_id": "tx_legacy_grace", "after_room_sequence": 0}, {"type": "modifier_lifetime_baseline_v1", "source_transaction_id": "tx_legacy_grace", "after_room_sequence": 0}],
	]
	for candidate: Array in malformed:
		suite.assert_true(not lifetime.validate_events(candidate).get("ok", false), "malformed or future legacy baselines are rejected")
	var forged := [{"type": "modifier_lifetime_baseline_v1", "source_transaction_id": "tx_forged", "after_room_sequence": 0}]
	suite.assert_true(not lifetime.active_projection(forged, assignments, modifiers).get("ok", false), "legacy baseline must authenticate against an actual dismissed event source")


func _modifier(source: String, duration: int) -> Dictionary:
	return {"modifier_id": "chronal_grace", "duration_rooms": duration, "magnitude": 1.15, "source_transaction_id": source}
