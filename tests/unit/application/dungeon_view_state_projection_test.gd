extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ProjectorScript := preload("res://scripts/application/run_view_state_projector.gd")
const FacadeScript := preload("res://scripts/application/run_runtime_facade.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var projector = ProjectorScript.new()
	for method: String in ["project_dungeon_map", "project_merchant", "project_dungeon_event", "project_room_interaction", "project_floor_transition"]:
		suite.assert_true(projector.has_method(method), "%s has a production projection entrypoint" % method)
	if not projector.has_method("project_dungeon_map"):
		suite.finish(get_tree())
		return
	_test_map(suite, projector)
	_test_merchant(suite, projector)
	_test_event(suite, projector)
	_test_interactions(suite, projector)
	suite.finish(get_tree())


func _test_map(suite, projector) -> void:
	var facade = FacadeScript.new()
	suite.assert_true(facade.boot().ok, "real dungeon content boots")
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}
	suite.assert_true(facade.start_run(config, "projection-run").ok, "real Launch run starts")
	var state: Dictionary = facade.snapshot()
	state["run_economy"]["balance"] = 123
	var floors := _content("floors")
	var projected = projector.project_dungeon_map(state, facade.route_choices(), floors[0])
	suite.assert_true(projected.ok, "real FloorPlan projects")
	if not projected.ok:
		return
	var view: Dictionary = projected.context["view_state"]
	var contract = load("res://scripts/ui/contracts/dungeon_map_view_state.gd")
	suite.assert_true(contract.validate(view).ok, "map contract accepts projection")
	suite.assert_equal(view["revision"], state["revision"], "commands use authoritative revision")
	suite.assert_equal(view["gold"], 123, "map projects authoritative economy balance")
	for node: Dictionary in view["nodes"]:
		if not node["revealed"]:
			suite.assert_equal(node["room_type"], "unknown", "hidden room type stays hidden")
			suite.assert_equal(node["name_key"], "UI_ROOM_UNKNOWN", "hidden rooms use localized neutral copy")
		suite.assert_true(not node.has("event_id") and not node.has("template_id"), "map omits hidden content identities")
	var extra := view.duplicate(true)
	extra["event_id"] = "event_final_choice"
	suite.assert_true(not contract.validate(extra).ok, "map refuses extra root fields")
	extra = view.duplicate(true)
	extra["edges"][0]["destination_node_id"] = "forged_node"
	suite.assert_true(not contract.validate(extra).ok, "map refuses unknown topology endpoints")
	extra = view.duplicate(true)
	extra["edges"] = []
	extra["routes"] = []
	suite.assert_true(not contract.validate(extra).ok, "map refuses disconnected topology")
	extra = view.duplicate(true)
	extra["revision"] = []
	suite.assert_true(not contract.validate(extra).ok, "malformed revisions fail without a runtime error")
	extra = view.duplicate(true)
	for node: Dictionary in extra["nodes"]:
		if not node["revealed"]:
			node["room_type"] = "event"
			break
	suite.assert_true(not contract.validate(extra).ok, "map rejects unrevealed room knowledge")
	view["nodes"][0]["name_key"] = "forged"
	suite.assert_true(not state["floor_plan"]["nodes"][0].has("name_key"), "projection does not mutate domain nodes")


func _test_merchant(suite, projector) -> void:
	var item: Dictionary = _content("items")[0]
	var merchant: Dictionary = _content("merchants")[0]
	var source := {"node_key": "floor_ruins_of_remnant:f1", "merchant_id": merchant["id"], "name_key": merchant["name_key"], "description_key": merchant["description_key"], "intro_key": merchant["intro_key"], "farewell_key": merchant["farewell_key"], "services": ["purchase_reward"], "gold": 10, "economy_revision": 1, "inventory": {"offers": [{"offer_id": "offer_1", "reward_id": item["id"], "category": "item", "rarity": item["rarity"], "price": 20, "sold": false}]}, "service_state": {}, "visibility": {}}
	var result = projector.project_merchant(_authority(), source, [item], [])
	suite.assert_true(result.ok, "merchant projects typed content copy")
	if not result.ok:
		return
	var contract = load("res://scripts/ui/contracts/merchant_view_state.gd")
	var view: Dictionary = result.context["view_state"]
	suite.assert_true(contract.validate(view).ok, "merchant contract accepts projection")
	suite.assert_true(not view["offers"][0]["available"], "unaffordable purchase is disabled")
	suite.assert_true(not str(view["offers"][0]["disabled_reason_key"]).is_empty(), "disabled purchase explains its reason")
	view["offers"][0]["affordable"] = true
	suite.assert_true(not contract.validate(view).ok, "merchant rejects inconsistent affordability")
	source["inventory"]["offers"][0]["reward_id"] = "unknown_item"
	suite.assert_true(not projector.project_merchant(_authority(), source, [item], []).ok, "merchant rejects unknown reward IDs")


func _test_event(suite, projector) -> void:
	var source := {"phase": "open", "event_id": "event_chronal_altar", "name_key": "EVENT_CHRONAL_ALTAR_NAME", "description_key": "EVENT_CHRONAL_ALTAR_DESC", "prompt_key": "EVENT_CHRONAL_ALTAR_PROMPT", "options": [{"id": "commit", "label_key": "EVENT_CHRONAL_ALTAR_OPTION_COMMIT", "eligible": false, "disabled_reason_key": "EVENT_REQUIREMENT_GOLD", "outcome_visibility": "hidden_until_commit", "visible_preview": []}], "revision": 7, "result_key": "", "pending_kind": ""}
	var result = projector.project_dungeon_event(_authority(), source)
	suite.assert_true(result.ok, "safe event view projects")
	if not result.ok:
		return
	var contract = load("res://scripts/ui/contracts/dungeon_event_view_state.gd")
	var view: Dictionary = result.context["view_state"].duplicate(true)
	suite.assert_true(contract.validate(view).ok, "event contract accepts projection")
	view["options"][0]["visible_preview"] = ["EVENT_CHRONAL_ALTAR_OUTCOME_COMMIT"]
	suite.assert_true(not contract.validate(view).ok, "event rejects hidden result leakage")
	view = result.context["view_state"].duplicate(true)
	view["options"][0]["id"] = "run_script"
	suite.assert_true(not contract.validate(view).ok, "event rejects unknown option IDs")
	source["options"][0]["disabled_reason_key"] = ""
	suite.assert_true(not projector.project_dungeon_event(_authority(), source).ok, "disabled event options require a reason")
	source["options"][0]["disabled_reason_key"] = "EVENT_REQUIREMENT_GOLD"
	source["outcomes"] = []
	suite.assert_true(not projector.project_dungeon_event(_authority(), source).ok, "projection refuses raw consequence payloads")
	source.erase("outcomes")
	source["phase"] = "pending_reward"
	source["pending_kind"] = "reward"
	source["result_key"] = ""
	suite.assert_true(not projector.project_dungeon_event(_authority(), source).ok, "pending event reward requires real player options")
	var item: Dictionary = _content("items")[0]
	var reward := {"schema_version": 1, "offer_id": "event_reward_1", "category": "item", "title_key": "UI_CHOOSE_REWARD", "revision": 7, "can_skip": false, "continuation_id": "continuation_1", "options": [{"option_id": "reward_option_1", "content_id": item["id"], "name_key": item["name_key"], "description_key": item["description_key"], "archetype_key": "ARCHETYPE_FREEZE_BURST", "role_key": "ROLE_STARTER", "rarity": item["rarity"], "icon_id": "item_frozen_burst", "effect_summary_keys": []}]}
	result = projector.project_dungeon_event(_authority(), source, reward)
	suite.assert_true(result.ok, "pending event preserves a real player reward choice")
	reward["options"][0]["effects"] = {"damage": 999}
	suite.assert_true(not projector.project_dungeon_event(_authority(), source, reward).ok, "event reward projection refuses executable effect data")


func _test_interactions(suite, projector) -> void:
	var source := {"room_type": "rest", "node_id": "rest_1", "name_key": "ROOM_TYPE_REST", "description_key": "UI_REST_DESC", "choices": [{"id": "heal", "label_key": "UI_REST_HEAL", "description_key": "UI_REST_HEAL_DESC", "available": true, "disabled_reason_key": ""}]}
	var result = projector.project_room_interaction(_authority(), source)
	suite.assert_true(result.ok, "room interaction projects")
	source["choices"][0]["id"] = "run_script"
	suite.assert_true(not projector.project_room_interaction(_authority(), source).ok, "room interaction refuses unknown commands")
	var authority := _authority()
	authority["completed_floor_ids"] = ["floor_ruins_of_remnant"]
	result = projector.project_floor_transition(authority, _content("floors"))
	suite.assert_true(result.ok, "completed floor projects next-floor view")
	if result.ok:
		suite.assert_equal(result.context["view_state"]["next_floor_index"], 1, "next floor uses zero-based authority index")


func _authority() -> Dictionary:
	return {"run_id": "projection-run", "revision": 7, "run_economy": {"balance": 10}}


func _content(collection: String) -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/%s.json" % collection)) as Array
