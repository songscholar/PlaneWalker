extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const DungeonEventDefinitionScript := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const DungeonEventRuntimeScript := preload("res://scripts/events/dungeon_event_runtime.gd")
const DungeonEventSelectorScript := preload("res://scripts/events/dungeon_event_selector.gd")
const DungeonEventRunStateScript := preload("res://scripts/events/dungeon_event_run_state.gd")
const EventRequirementServiceScript := preload("res://scripts/events/event_requirement_service.gd")
const ConsequenceRuntimeScript := preload("res://scripts/events/dungeon_event_consequence_runtime.gd")
const EventResourceAuthorityScript := preload("res://scripts/events/event_resource_authority.gd")
const EventHealthAuthorityScript := preload("res://scripts/events/event_health_authority.gd")
const EventModifierAuthorityScript := preload("res://scripts/events/event_modifier_authority.gd")
const EventRouteAuthorityScript := preload("res://scripts/events/event_route_authority.gd")
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const EVENT_IDS: Array[String] = [
	"event_chronal_altar", "event_cursed_pool", "event_final_choice",
	"event_lost_journal", "event_memory_mirror", "event_old_reunion",
	"event_perfect_rewind", "event_planar_merchant", "event_rift_garden",
	"event_sacrificial_altar", "event_sleeping_guardian", "event_smiths_legacy",
	"event_soul_contract", "event_time_paradox", "event_trapped_traveler",
	"event_twisted_well", "event_void_rift", "event_void_whispers",
]
const PUBLICATION_SECRET := "p14f-smoke-publication-secret-0123456789abcdef0123456789abcdef"
const NODE_ID := "event_node"
const FIRST_SEED := 20261002
const EXPECTED_OUTCOMES := 39
const EXPECTED_OPTIONS := 36
const EXPECTED_REQUIREMENT_REJECTIONS := 9

var _suite
var _registry: RefCounted
var _definitions: Array[Dictionary] = []
var _content_fingerprint := ""
var _economy_profile: Dictionary = {}
var _floor_ids: Dictionary = {}
var _fixture: Dictionary = {}
var _revision := 0
var _facts: Array[Dictionary] = []
var _state_writes: Array[Dictionary] = []
var _outcomes_covered: Dictionary = {}
var _options_covered: Dictionary = {}
var _operations_covered: Dictionary = {}
var _pending_counts := {"reward": 0, "encounter": 0}
var _published_count := 0
var _executions := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report: RefCounted = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"LAUNCH")
	_suite.assert_true(not report.call("has_blocking_errors"), "smoke loads the authoritative Base Pack")
	if report.call("has_blocking_errors"):
		_suite.finish(get_tree())
		return
	for value: Dictionary in _registry.call("get_by_category", &"dungeon_event", &"LAUNCH"):
		_definitions.append(_definition_fields(value, DungeonEventDefinitionScript.ROOT_FIELDS))
	_content_fingerprint = JSON.stringify(_definitions).sha256_text()
	var profiles: Array = _registry.call("get_by_category", &"economy_profile", &"LAUNCH")
	_suite.assert_equal(profiles.size(), 1, "one authoritative Launch economy profile")
	if profiles.size() != 1:
		_suite.finish(get_tree())
		return
	_economy_profile = _definition_fields(profiles[0] as Dictionary, EconomyProfileScript.ROOT_FIELDS)
	for floor_definition: Dictionary in _registry.call("get_floor_definitions", &"LAUNCH"):
		_floor_ids[int(floor_definition["order"]) - 1] = str(floor_definition["id"])
	_suite.assert_equal(_floor_ids.size(), 5, "fixtures use all five authoritative floor identities")
	_assert_catalog()
	for definition: Dictionary in _definitions:
		for option: Dictionary in definition["options"]:
			for outcome: Dictionary in option["outcomes"]:
				var seed := _seed_for_outcome(definition, option, outcome)
				_suite.assert_true(seed >= FIRST_SEED, "%s has a deterministic branch seed" % _case_id(definition, option, outcome))
				if seed < FIRST_SEED:
					continue
				var first := _execute_branch(definition, option, outcome, seed)
				var second := _execute_branch(definition, option, outcome, seed)
				_suite.assert_true(not first.is_empty(), "branch execution produces certification evidence")
				_suite.assert_equal(JSON.stringify(second), JSON.stringify(first), "%s repeats byte-identically" % _case_id(definition, option, outcome))
	var rejected := _test_authored_requirement_rejections()
	_suite.assert_equal(_options_covered.size(), EXPECTED_OPTIONS, "all 36 options execute real handlers")
	_suite.assert_equal(_outcomes_covered.size(), EXPECTED_OUTCOMES, "all 39 authored outcome branches execute")
	_suite.assert_equal(_executions, EXPECTED_OUTCOMES * 2, "every branch executes twice")
	_suite.assert_equal(_pending_counts, {"reward": 16, "encounter": 2}, "both deterministic passes restore and authenticate every pending branch")
	_suite.assert_equal(rejected, EXPECTED_REQUIREMENT_REJECTIONS, "all nine non-floor requirement gates reject exactly")
	_suite.assert_equal(_published_count, 252, "all 78 executions publish opened, committed, completion when pending, and dismissal exactly once")
	_suite.assert_equal(_sorted_keys(_operations_covered), [
		"curse_add", "encounter_start", "health_delta", "map_reveal", "narrative_flag",
		"resource_delta", "reward_draft", "route_skip", "temporary_modifier",
	], "all nine authored consequence operation kinds have concrete assertions")
	print("P14F EVENT SMOKE: events=%d options=%d outcomes=%d executions=%d pending_reward=%d pending_encounter=%d requirement_rejections=%d publications=%d" % [
		_definitions.size(), _options_covered.size(), _outcomes_covered.size(), _executions,
		_pending_counts["reward"], _pending_counts["encounter"], rejected, _published_count,
	])
	_fixture.clear()
	_suite.finish(get_tree())


func _assert_catalog() -> void:
	var ids: Array[String] = []
	var option_count := 0
	var outcome_count := 0
	var special_count := 0
	for definition: Dictionary in _definitions:
		ids.append(str(definition["id"]))
		special_count += int(bool(definition["special"]))
		var option_ids: Array[String] = []
		for option: Dictionary in definition["options"]:
			option_count += 1
			option_ids.append(str(option["id"]))
			outcome_count += (option["outcomes"] as Array).size()
		option_ids.sort()
		_suite.assert_equal(option_ids, ["commit", "decline"], "%s has both authored choices" % definition["id"])
	ids.sort()
	_suite.assert_equal(ids, EVENT_IDS, "Base Pack has exactly the eighteen approved event identities")
	_suite.assert_equal(special_count, 3, "Base Pack contains three special and fifteen regular events")
	_suite.assert_equal(option_count, EXPECTED_OPTIONS, "Base Pack contains 36 authored options")
	_suite.assert_equal(outcome_count, EXPECTED_OUTCOMES, "Base Pack contains 39 authored outcome branches")


func _execute_branch(definition: Dictionary, option: Dictionary, outcome: Dictionary, seed: int) -> Dictionary:
	var label := _case_id(definition, option, outcome)
	var runtime := _new_fixture(definition, seed)
	if runtime == null:
		return {}
	var opened: Dictionary = runtime.call("open_event", _fixture["room"], {})
	_suite.assert_true(bool(opened.get("ok", false)), "%s opens through the real selector: %s" % [label, opened])
	if not bool(opened.get("ok", false)):
		return {}
	_suite.assert_equal(runtime.call("view_state")["event_id"], definition["id"], "%s selects the actual authored event" % label)
	_suite.assert_equal(_facts.size(), 1, "%s publishes its opened fact" % label)
	var before: Dictionary = runtime.call("snapshot")
	var unknown: Dictionary = runtime.call("choose_option", &"unknown_smoke_option", _revision)
	_suite.assert_equal(unknown.get("code"), &"OPTION_NOT_FOUND", "%s rejects unknown option identities" % label)
	_suite.assert_equal(runtime.call("snapshot"), before, "%s unknown option is side-effect free" % label)
	if str(option["outcome_visibility"]) == "hidden_until_commit":
		var view_text := JSON.stringify(runtime.call("view_state"))
		for hidden_outcome: Dictionary in option["outcomes"]:
			_suite.assert_true(not view_text.contains(str(hidden_outcome["id"])), "%s hides every unresolved variant" % label)
			_suite.assert_true(not view_text.contains(str(hidden_outcome["outcome_key"])), "%s hides unresolved outcome keys" % label)
	var chosen: Dictionary = runtime.call("choose_option", StringName(option["id"]), _revision)
	_suite.assert_true(bool(chosen.get("ok", false)), "%s executes its authored handler: %s" % [label, chosen])
	if not bool(chosen.get("ok", false)):
		return {}
	var committed: Dictionary = runtime.call("snapshot")
	var state := _event_state(committed)
	var assignment := _assignment(committed)
	_suite.assert_equal(assignment["option_id"], option["id"], "%s records the exact option" % label)
	_suite.assert_equal(assignment["outcome_id"], outcome["id"], "%s reaches the intended weighted branch" % label)
	_suite.assert_equal(assignment["outcome_key"], outcome["outcome_key"], "%s retains its authored outcome" % label)
	_suite.assert_equal(assignment["result_key"], outcome["outcome_key"] if str(assignment["phase"]) == "resolved" else "", "%s exposes a result only after terminal resolution" % label)
	_suite.assert_equal(_facts.size(), 2, "%s publishes its committed fact exactly once" % label)
	_suite.assert_equal(_facts[1]["payload"]["kind"], "event_committed", "%s emits the correct committed fact" % label)
	_assert_consequences(before, committed, outcome, label)
	_assert_persisted(runtime, label)
	var phase := str(assignment["phase"])
	_suite.assert_true(phase in ["resolved", "pending_reward", "pending_encounter"], "%s cannot stop at identity-only or reserved state" % label)
	var duplicate: Dictionary = runtime.call("choose_option", StringName(option["id"]), _revision)
	_suite.assert_equal(duplicate.get("code"), &"EVENT_NOT_OPEN", "%s rejects a second choice" % label)
	_suite.assert_equal(runtime.call("snapshot"), committed, "%s duplicate choice has no side effects" % label)
	_suite.assert_equal(_facts.size(), 2, "%s duplicate choice cannot republish" % label)

	# Every branch, including pending continuations, must survive a fresh runtime.
	runtime = _restore_fresh_runtime(definition, seed, committed, label)
	if runtime == null:
		return {}
	if phase.begins_with("pending_"):
		var kind := "reward" if phase == "pending_reward" else "encounter"
		var pending := state["pending_%s" % kind] as Dictionary
		var continuation_id := str(pending["continuation_id"])
		_suite.assert_true(not continuation_id.is_empty(), "%s has an authenticated continuation identity" % label)
		var rejected := _complete(runtime, kind, "event_cont_v1:forged", {})
		_suite.assert_equal(rejected.get("code"), &"CONTINUATION_MISMATCH", "%s rejects unauthenticated completion" % label)
		_suite.assert_equal(runtime.call("snapshot"), committed, "%s forged completion leaves every participant unchanged" % label)
		_suite.assert_equal(_facts.size(), 2, "%s forged completion publishes nothing" % label)
		var completed := _complete(runtime, kind, continuation_id, {"source": "all_dungeon_events_smoke"})
		_suite.assert_true(bool(completed.get("ok", false)), "%s restored authenticated continuation resolves: %s" % [label, completed])
		_suite.assert_equal(runtime.call("view_state")["phase"], "resolved", "%s continuation reaches terminal result" % label)
		_suite.assert_equal(_facts.size(), 3, "%s continuation publishes exactly one completion" % label)
		_suite.assert_equal(_facts[2]["payload"]["kind"], "event_%s_completed" % kind, "%s publishes the typed completion" % label)
		var resolved: Dictionary = runtime.call("snapshot")
		var repeated := _complete(runtime, kind, continuation_id, {})
		_suite.assert_equal(repeated.get("code"), StringName("PENDING_%s_NOT_FOUND" % kind.to_upper()), "%s consumes its continuation once" % label)
		_suite.assert_equal(runtime.call("snapshot"), resolved, "%s repeated completion is side-effect free" % label)
		_pending_counts[kind] = int(_pending_counts[kind]) + 1
	var dismissed: Dictionary = runtime.call("dismiss_result", _revision)
	_suite.assert_true(bool(dismissed.get("ok", false)), "%s dismisses the terminal result" % label)
	_suite.assert_equal(runtime.call("view_state")["phase"], "dismissed", "%s reaches dismissed" % label)
	_suite.assert_equal(runtime.call("view_state")["result_key"], outcome["outcome_key"], "%s dismissal retains the authored result" % label)
	var expected_fact_count := 4 if phase.begins_with("pending_") else 3
	_suite.assert_equal(_facts.size(), expected_fact_count, "%s has the exact publication count" % label)
	var unique_fact_ids: Dictionary = {}
	for fact: Dictionary in _facts:
		unique_fact_ids[str(fact["fact_id"])] = true
		_suite.assert_equal(fact["payload"]["event_id"], definition["id"], "%s publication binds the actual event" % label)
	_suite.assert_equal(unique_fact_ids.size(), _facts.size(), "%s has no duplicate external effects" % label)
	_assert_persisted(runtime, label)
	_outcomes_covered[label] = true
	_options_covered["%s/%s" % [definition["id"], option["id"]]] = true
	_published_count += _facts.size()
	_executions += 1
	return {"seed": seed, "committed": committed, "final": runtime.call("snapshot"), "facts": _facts.duplicate(true)}


func _assert_consequences(before: Dictionary, after: Dictionary, outcome: Dictionary, label: String) -> void:
	var old := _participants(before)
	var current := _participants(after)
	var state := current["event_state"] as Dictionary
	var transaction_id := str(_assignment(after)["transaction_id"])
	for consequence: Dictionary in outcome["consequences"]:
		var operation := str(consequence["operation"])
		var arguments := consequence["arguments"] as Dictionary
		_operations_covered[operation] = true
		match operation:
			"resource_delta":
				var resource_id := str(arguments["resource"])
				if resource_id == "gold":
					_suite.assert_equal(int(current["economy"]["balance"]), int(old["economy"]["balance"]) + int(arguments["amount"]), "%s changes authoritative gold" % label)
				else:
					_suite.assert_equal(int(current["resource"]["resources"][resource_id]), int(old["resource"]["resources"][resource_id]) + int(arguments["amount"]), "%s changes the authored resource" % label)
			"health_delta":
				var target := minf(float(old["health"]["maximum"]), float(old["health"]["current"]) + float(arguments["amount"]))
				_suite.assert_close(float(current["health"]["current"]), target, "%s applies exact health delta" % label)
			"curse_add", "curse_remove":
				var curses: Array = (old["modifier"]["curse_ids"] as Array).duplicate()
				if operation == "curse_add":
					curses.append(str(arguments["curse_id"]))
				else:
					curses.erase(str(arguments["curse_id"]))
				curses.sort()
				_suite.assert_equal(current["modifier"]["curse_ids"], curses, "%s changes the actual curse set" % label)
			"narrative_flag":
				_suite.assert_equal(current["modifier"]["narrative_flags"].get(str(arguments["flag"])), arguments["value"], "%s applies its actual narrative flag" % label)
			"temporary_modifier":
				var expected := arguments.duplicate(true)
				expected["source_transaction_id"] = transaction_id
				_suite.assert_true((current["modifier"]["temporary_modifiers"] as Array).has(expected), "%s installs exact modifier magnitude, duration, and provenance" % label)
			"reward_draft":
				var pending := state["pending_reward"] as Dictionary
				_suite.assert_equal(pending.get("pool_id"), arguments["pool_id"], "%s reserves the authored reward pool" % label)
				_suite.assert_equal(pending.get("count"), arguments["count"], "%s reserves the authored reward count" % label)
				_suite.assert_equal(pending.get("transaction_id"), transaction_id, "%s binds reward reservation to its transaction" % label)
			"encounter_start":
				var pending := state["pending_encounter"] as Dictionary
				_suite.assert_equal(pending.get("encounter_id"), arguments["encounter_id"], "%s reserves the actual authored encounter" % label)
				_suite.assert_equal(pending.get("transaction_id"), transaction_id, "%s binds encounter reservation to its transaction" % label)
			"map_reveal":
				var depth := int(arguments["depth"])
				var plan := current["route"]["plan"] as Dictionary
				for step: int in range(1, 5):
					_suite.assert_equal(_node(plan, "forward_%d" % step)["revealed"], step <= depth, "%s reveals exactly authored depth at edge %d" % [label, step])
				_suite.assert_equal(plan["current_node_id"], NODE_ID, "%s reveal does not traverse" % label)
			"route_skip":
				var rooms := int(arguments["rooms"])
				var plan := current["route"]["plan"] as Dictionary
				_suite.assert_equal(plan["current_node_id"], "forward_%d" % rooms, "%s traverses the exact authored edge count" % label)
				_suite.assert_equal((plan["selected_edge_ids"] as Array).size(), rooms + 1, "%s records every traversed edge" % label)
				_suite.assert_equal(plan["abandoned_node_ids"], [], "%s never abandons its traversed path" % label)
				for step: int in range(1, 5):
					var node := _node(plan, "forward_%d" % step)
					_suite.assert_equal(node["visited"], step <= rooms, "%s visits exactly the skipped chain" % label)
					_suite.assert_equal(node["cleared"], step < rooms, "%s clears intermediate rooms but not its landing" % label)
			_:
				_suite.assert_true(false, "%s has no smoke assertion for %s" % [label, operation])
		var changed: bool = _effect_value(old, operation) != _effect_value(current, operation)
		_suite.assert_true(changed, "%s/%s must change domain values, not only identity or revision" % [label, operation])
	_suite.assert_equal(current["route"]["plan"]["generation_digest"], old["route"]["plan"]["generation_digest"], "%s preserves generated dungeon identity" % label)


func _effect_value(participants: Dictionary, operation: String) -> Variant:
	match operation:
		"resource_delta":
			return [participants["economy"]["balance"], participants["resource"]["resources"]]
		"health_delta":
			return participants["health"]["current"]
		"curse_add", "curse_remove":
			return participants["modifier"]["curse_ids"]
		"narrative_flag":
			return participants["modifier"]["narrative_flags"]
		"temporary_modifier":
			return participants["modifier"]["temporary_modifiers"]
		"reward_draft":
			return participants["event_state"]["pending_reward"]
		"encounter_start":
			return participants["event_state"]["pending_encounter"]
		"map_reveal", "route_skip":
			return participants["route"]["plan"]["nodes"]
	return null


func _restore_fresh_runtime(definition: Dictionary, seed: int, saved: Dictionary, label: String) -> RefCounted:
	var facts := _facts.duplicate(true)
	var writes := _state_writes.duplicate(true)
	var revision := _revision
	var wrong_secret := _new_fixture(definition, seed, PUBLICATION_SECRET + "-wrong")
	if wrong_secret == null:
		return null
	_suite.assert_true(not bool(wrong_secret.call("restore_snapshot", saved)), "%s rejects a different publication authority" % label)
	_suite.assert_equal([_facts.size(), _state_writes.size(), _revision], [0, 0, 0], "%s failed restore cannot publish or persist" % label)
	var restored := _new_fixture(definition, seed)
	if restored == null:
		return null
	_suite.assert_true(bool(restored.call("can_restore_snapshot", saved)), "%s is restorable before mutation" % label)
	var restored_ok := bool(restored.call("restore_snapshot", saved))
	_suite.assert_true(restored_ok, "%s restores into fresh real authorities" % label)
	if not restored_ok:
		return null
	_suite.assert_equal([_facts.size(), _state_writes.size(), _revision], [0, 0, 0], "%s validation and restore cannot publish or persist" % label)
	_revision = revision
	_facts = facts
	_state_writes = writes
	_suite.assert_equal(JSON.stringify(restored.call("snapshot")), JSON.stringify(saved), "%s restore is byte-identical" % label)
	var acknowledged_facts := facts.duplicate(true)
	var no_publication: Dictionary = restored.call("flush_pending_facts")
	_suite.assert_true(bool(no_publication.get("ok", false)), "%s restored publication ledger flushes" % label)
	_suite.assert_equal(_facts, acknowledged_facts, "%s restore cannot republish acknowledged facts" % label)
	return restored


func _complete(runtime: RefCounted, kind: String, continuation_id: String, result: Dictionary) -> Dictionary:
	if kind == "reward":
		return runtime.call("complete_reward", continuation_id, result, _revision)
	return runtime.call("complete_encounter", continuation_id, true, result, _revision)


func _test_authored_requirement_rejections() -> int:
	var rejected := 0
	for definition: Dictionary in _definitions:
		for option: Dictionary in definition["options"]:
			for requirement: Dictionary in option["requirements"]:
				var operation := str(requirement["operation"])
				if operation == "floor_index_min":
					continue
				var label := "%s/%s/%s" % [definition["id"], option["id"], operation]
				var runtime := _new_fixture(definition, FIRST_SEED)
				if runtime == null:
					continue
				var opened: Dictionary = runtime.call("open_event", _fixture["room"], {})
				_suite.assert_true(bool(opened.get("ok", false)), "%s opens before its authority changes" % label)
				if not bool(opened.get("ok", false)):
					continue
				var arguments := requirement["arguments"] as Dictionary
				match operation:
					"gold_min":
						_fixture["economy"].configure(_economy_profile, int(arguments["amount"]) - 1)
					"health_min":
						_fixture["health"].configure(float(arguments["amount"]) - 1.0, 100.0)
					"health_max_ratio":
						_fixture["health"].configure(100.0, 100.0)
					"resource_min":
						var resources: Dictionary = _fixture["resource"].snapshot()["resources"]
						resources[str(arguments["resource"])] = int(arguments["amount"]) - 1
						_fixture["resource"].configure(resources)
					"lacks_curse":
						var curses: Array = _fixture["modifier"].snapshot()["curse_ids"]
						curses.append(str(arguments["curse_id"]))
						curses.sort()
						_suite.assert_true(_fixture["modifier"].configure(curses, {}, []), "%s configures its rejected curse state" % label)
					_:
						_suite.assert_true(false, "%s needs an authored rejection fixture" % label)
				var before: Dictionary = runtime.call("snapshot")
				var writes_before := _state_writes.size()
				var revision_before := _revision
				var result: Dictionary = runtime.call("choose_option", StringName(option["id"]), _revision)
				var reason := "EVENT_REQUIREMENT_%s" % operation.to_upper()
				_suite.assert_equal(result.get("code"), &"OPTION_INELIGIBLE", "%s returns typed requirement rejection" % label)
				_suite.assert_equal(result.get("context", {}).get("disabled_reason_key"), reason, "%s returns the exact authored reason" % label)
				for option_view: Dictionary in runtime.call("view_state")["options"]:
					if str(option_view["id"]) == str(option["id"]):
						_suite.assert_equal(option_view["eligible"], false, "%s is disabled in UI-safe state" % label)
						_suite.assert_equal(option_view["disabled_reason_key"], reason, "%s view and command agree" % label)
				_suite.assert_equal(runtime.call("snapshot"), before, "%s rejection leaves every authority unchanged" % label)
				_suite.assert_equal(_state_writes.size(), writes_before, "%s rejection cannot write state" % label)
				_suite.assert_equal(_revision, revision_before, "%s rejection cannot advance revision" % label)
				_suite.assert_equal(_facts.size(), 1, "%s rejection cannot publish a committed fact" % label)
				rejected += 1
	return rejected


func _new_fixture(definition: Dictionary, seed: int, secret: String = PUBLICATION_SECRET) -> RefCounted:
	_revision = 0
	_facts.clear()
	_state_writes.clear()
	var floor_index := int(definition["floor_min"]) - 1
	var room := {"floor_id": str(_floor_ids[floor_index]), "floor_index": floor_index, "node_id": NODE_ID, "primary_event_id": str(definition["id"])}
	var resource := EventResourceAuthorityScript.new()
	var health := EventHealthAuthorityScript.new()
	var economy := RunEconomyStateScript.new()
	var modifier := EventModifierAuthorityScript.new()
	var route := EventRouteAuthorityScript.new()
	var event_state := DungeonEventRunStateScript.new()
	var consequence := ConsequenceRuntimeScript.new()
	var curses: Array = ["curse_stasis_fracture"] if str(definition["trigger_predicate_id"]) == "has_curse" else []
	var configured := resource.configure({"time_shard": 2, "forge_essence": 1})
	configured = health.configure(30.0, 100.0) and configured
	configured = bool(economy.configure(_economy_profile, 200).get("ok", false)) and configured
	configured = modifier.configure(curses, {}, []) and configured
	configured = route.configure(_route_plan(room, seed)) and configured
	configured = bool(event_state.configure(_content_fingerprint).get("ok", false)) and configured
	configured = consequence.configure(resource, health, economy, modifier, route, event_state) and configured
	_fixture = {"room": room, "seed": seed, "definition": definition, "resource": resource, "health": health, "economy": economy, "modifier": modifier, "route": route, "event_state": event_state}
	var runtime := DungeonEventRuntimeScript.new()
	# Isolate one unchanged Base Pack row; full-pool competition is tested by the selector suite.
	configured = runtime.configure([definition], DungeonEventSelectorScript.new(), event_state, EventRequirementServiceScript.new(), consequence, Callable(self, "_provide_context"), Callable(self, "_commit_state"), Callable(self, "_publish_fact"), secret) and configured
	_suite.assert_true(configured, "%s configures all real runtime participants" % definition["id"])
	return runtime if configured else null


func _provide_context() -> Dictionary:
	var health_snapshot: Dictionary = _fixture["health"].snapshot()
	var health := {"current": health_snapshot["current"], "maximum": health_snapshot["maximum"]}
	var gold := int(_fixture["economy"].snapshot()["balance"])
	var resources: Dictionary = _fixture["resource"].snapshot()["resources"]
	resources["gold"] = gold
	var modifiers: Dictionary = _fixture["modifier"].snapshot()
	var room := _fixture["room"] as Dictionary
	var predicate := str(_fixture["definition"]["trigger_predicate_id"])
	return {
		"global_revision": _revision,
		"selection": {
			"run_seed": int(_fixture["seed"]), "availability": "LAUNCH",
			"floor_id": room["floor_id"], "floor_index": room["floor_index"],
			"node_id": NODE_ID, "primary_event_id": room["primary_event_id"],
			"health": health, "economy": {"gold": gold},
			"build": {"curse_ids": modifiers["curse_ids"]}, "resources": resources,
			"narrative_flags": modifiers["narrative_flags"],
			"meta": {"perfect_rewind_available": predicate == "perfect_rewind_available", "old_reunion_eligible": predicate == "old_reunion_eligible"},
			"seen_run_event_ids": [], "seen_floor_event_keys": [],
		},
		"requirements": {
			"resources": resources, "health": health, "gold": gold,
			"reward_tags": [], "curse_ids": modifiers["curse_ids"],
			"narrative_flags": modifiers["narrative_flags"], "floor_index": room["floor_index"],
		},
	}


func _commit_state(command: Dictionary, expected_revision: int) -> Dictionary:
	if expected_revision != _revision:
		return {"ok": false, "code": &"STALE_REVISION", "new_revision": _revision, "context": {}}
	_suite.assert_equal(command.get("event_state"), _fixture["event_state"].snapshot(), "state sink receives actual authority state")
	_state_writes.append(command.duplicate(true))
	_revision += 1
	return {"ok": true, "code": &"OK", "new_revision": _revision, "context": {}}


func _publish_fact(fact_id: String, payload: Dictionary) -> bool:
	_suite.assert_true(not _state_writes.is_empty(), "publication follows authoritative persistence")
	if not _state_writes.is_empty():
		var pending: Array = _state_writes.back()["publication_state"]["pending_facts"]
		_suite.assert_true(pending.has({"fact_id": fact_id, "payload": payload}), "published fact was durably persisted before delivery")
	_facts.append({"fact_id": fact_id, "payload": payload.duplicate(true)})
	return true


func _assert_persisted(runtime: RefCounted, label: String) -> void:
	var saved: Dictionary = runtime.call("snapshot")
	_suite.assert_true(not _state_writes.is_empty(), "%s persists state" % label)
	if _state_writes.is_empty():
		return
	_suite.assert_equal(_state_writes.back()["event_state"], _event_state(saved), "%s persists the committed event state" % label)
	var publication := _state_writes.back()["publication_state"] as Dictionary
	for key: String in publication:
		_suite.assert_equal(publication[key], saved[key], "%s persists %s" % [label, key])
	_suite.assert_equal(saved["pending_facts"], [], "%s acknowledges every publication" % label)
	_suite.assert_equal((saved["emitted_fact_ids"] as Array).size(), _facts.size(), "%s ledger matches externally observed facts" % label)


func _route_plan(room: Dictionary, seed: int) -> Dictionary:
	var nodes: Array[Dictionary] = [
		_route_node("entry", 0, "entry", true, true, true, room),
		_route_node(NODE_ID, 1, "event", true, true, true, room),
	]
	var edges: Array[Dictionary] = [_edge("edge_entry_event", "entry", NODE_ID)]
	var previous := NODE_ID
	for step: int in range(1, 5):
		var id := "forward_%d" % step
		nodes.append(_route_node(id, step + 1, "combat", false, false, false, room))
		edges.append(_edge("edge_forward_%d" % step, previous, id))
		previous = id
	nodes.append(_route_node("boss", 6, "boss", false, false, false, room))
	edges.append(_edge("edge_boss", previous, "boss"))
	var plan := {
		"schema_version": 1, "generator_version": "floor_plan_v1", "run_seed": seed,
		"floor_id": room["floor_id"], "floor_index": room["floor_index"],
		"entry_node_id": "entry", "boss_node_id": "boss", "current_node_id": NODE_ID,
		"nodes": nodes, "edges": edges, "selected_edge_ids": ["edge_entry_event"],
		"visited_node_ids": ["entry", NODE_ID], "abandoned_node_ids": [],
		"generation_digest": "", "revision": 1,
	}
	plan["generation_digest"] = FloorPlanScript.compute_generation_digest(plan)
	return plan


func _route_node(id: String, layer: int, room_type: String, revealed: bool, visited: bool, cleared: bool, room: Dictionary) -> Dictionary:
	return {
		"id": id, "layer": layer, "room_type": room_type, "template_id": "template_%s" % id,
		"encounter_id": "", "event_id": room["primary_event_id"] if room_type == "event" else "",
		"merchant_id": "", "reward_policy_id": "reward_policy_smoke", "seed_channel_suffix": id,
		"revealed": revealed, "visited": visited, "cleared": cleared,
	}


func _edge(id: String, source: String, destination: String) -> Dictionary:
	return {"id": id, "source_node_id": source, "destination_node_id": destination, "choice_order": 0, "locked": false, "route_summary_facts": {"room_type": "combat", "template_id": "template_smoke"}}


func _node(plan: Dictionary, id: String) -> Dictionary:
	for value: Dictionary in plan["nodes"]:
		if str(value["id"]) == id:
			return value
	return {}


func _seed_for_outcome(definition: Dictionary, option: Dictionary, target: Dictionary) -> int:
	var total_weight := 0
	var lower_bound := 0
	for outcome: Dictionary in option["outcomes"]:
		if str(outcome["id"]) == str(target["id"]):
			lower_bound = total_weight
		total_weight += int(outcome["weight"])
	var channel := StringName("event_outcome_v1:%s:%s" % [definition["id"], NODE_ID])
	for seed: int in range(FIRST_SEED, FIRST_SEED + 10000):
		var roll := posmod(SeedServiceScript.derive_seed(seed, channel, int(definition["floor_min"]) - 1, 0, 0), total_weight)
		if roll >= lower_bound and roll < lower_bound + int(target["weight"]):
			return seed
	return -1


func _participants(snapshot_value: Dictionary) -> Dictionary:
	return snapshot_value["consequence_runtime"]["participant_snapshots"] as Dictionary


func _event_state(snapshot_value: Dictionary) -> Dictionary:
	return _participants(snapshot_value)["event_state"] as Dictionary


func _assignment(snapshot_value: Dictionary) -> Dictionary:
	return _event_state(snapshot_value)["selected_event_by_node"][snapshot_value["active_node_key"]] as Dictionary


func _case_id(definition: Dictionary, option: Dictionary, outcome: Dictionary) -> String:
	return "%s/%s/%s" % [definition["id"], option["id"], outcome["id"]]


func _sorted_keys(value: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in value:
		keys.append(str(key))
	keys.sort()
	return keys


func _definition_fields(value: Dictionary, fields: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for field: String in fields:
		if value.has(field):
			result[field] = value[field]
	return result.duplicate(true)
