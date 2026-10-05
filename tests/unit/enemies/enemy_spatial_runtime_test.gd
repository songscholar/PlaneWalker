extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Spatial := preload("res://scripts/enemies/launch/enemy_spatial_runtime.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	_wall_budget_and_tampering()
	_link_cap_and_lifetime()
	_portal_cap_and_collapse()
	suite.finish(get_tree())


func _fixture(action_id: String) -> Dictionary:
	var action := Content.action(action_id)
	var actor := action_id.get_slice(".", 0)
	var coordinator := Actions.new()
	var identity := {"run_id": "run-spatial-domain", "hostile_source_id": "spatial-owner", "next_generation_floor": 1, "runtime_frame": 0}
	suite.assert_true(coordinator.configure({"id": actor, "actor_kind": "elite", "actions": [action]}, identity).ok, "canonical spatial action configures domain")
	suite.assert_true(coordinator.request_action(action_id, {"runtime_frame": 0, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 430.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"}).ok, "canonical spatial action freezes warning")
	var result := {}
	for frame: int in range(1, int(action.warning_frames) + 1):
		result = coordinator.advance_frame(frame, {"runtime_frame": frame, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 430.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"})
	var runtime := Spatial.new()
	suite.assert_true(runtime.configure_catalog(), "exact five authored spatial actions load")
	var state := Spatial.initial_state("run-spatial-domain", int(action.warning_frames))
	var observations := {"spatial-owner": {"position": {"x": 320.0, "y": 180.0}, "dead": false, "kind": "elite"}, "ally-a": {"position": {"x": 240.0, "y": 130.0}, "dead": false, "kind": "enemy"}, "ally-b": {"position": {"x": 400.0, "y": 130.0}, "dead": false, "kind": "enemy"}}
	return {"runtime": runtime, "state": state, "request": result.effect_requests[0], "observations": observations, "definition_id": actor}


func _reserve(f: Dictionary, generation: int = 1) -> bool:
	var request: Dictionary = f.request.duplicate(true)
	request.attack_generation = generation
	request.runtime_frame = f.state.runtime_frame
	return f.runtime.reserve(f.state, request, f.definition_id, f.observations)


func _advance(f: Dictionary, through: int, capacity: int = 0, safe: bool = true) -> Array:
	var collapses: Array = []
	for frame: int in range(int(f.state.runtime_frame) + 1, through + 1):
		var result: Dictionary = f.runtime.advance(f.state, frame, f.observations, func(_row: Dictionary): return safe, capacity)
		suite.assert_true(result.ok and f.runtime.valid_state(f.state), "finite spatial state validates at each accepted frame")
		if not result.ok:
			break
		collapses.append_array(result.collapse_warnings)
	return collapses


func _wall_budget_and_tampering() -> void:
	var f := _fixture("bramble_mage.bramble_cage")
	suite.assert_true(_reserve(f), "authored cage reserves three segments")
	suite.assert_equal(f.state.rows.size(), 3, "cage has three independently identified HP targets")
	_advance(f, 100, 6)
	suite.assert_equal(Spatial.active_count(f.state), 2, "six foreign constructs reserve shared8slot budget")
	suite.assert_equal(f.state.rows[2].phase, "PENDING", "excess wall waits without physical collision")
	_advance(f, 101)
	suite.assert_equal(f.state.rows[2].warning_frame, 101, "released slot starts complete new warning")
	_advance(f, 150)
	suite.assert_equal(Spatial.active_count(f.state), 2, "pending segment stays harmless through full50frame warning")
	_advance(f, 151)
	suite.assert_equal(Spatial.active_count(f.state), 3, "released segment activates exactly after full50frames")
	for field: String in ["radius", "length", "active_from_frame", "hostile_source_id"]:
		var forged: Dictionary = f.state.duplicate(true)
		forged.rows[0].geometry[0][field] = "forged" if field == "hostile_source_id" else 999
		suite.assert_true(not f.runtime.valid_state(forged), "cold cage rejects forged geometry field " + field)
	var unknown: Dictionary = f.state.duplicate(true)
	unknown["unknown"] = true
	suite.assert_true(not f.runtime.valid_state(unknown), "current spatial schema rejects unknown fields")
	var claim := {"run_id": "run-spatial-domain", "source_id": "player:sword", "generation": 10, "hit_index": 0, "runtime_frame": 151, "amount": 12.0}
	suite.assert_equal(f.runtime.accept_damage(f.state, f.state.rows[0].id, claim), 12.0, "wall HP accepts exact authenticated amount")
	suite.assert_equal(f.runtime.accept_damage(f.state, f.state.rows[0].id, claim), 0.0, "same damage claim remains spent")
	f.observations["spatial-owner"].dead = true
	_advance(f, 152)
	suite.assert_true(f.state.rows.all(func(row: Dictionary): return row.phase == "RETIRED"), "owner death retires every cage segment")
	var deferred := _fixture("void_web_weaver.web_cage")
	_reserve(deferred)
	_advance(deferred, 110, 0, false)
	suite.assert_true(deferred.state.rows.all(func(row: Dictionary): return row.phase == "PENDING"), "occupied wall geometry defers collision without shortening warning")
	_advance(deferred, 111)
	_advance(deferred, 165)
	suite.assert_equal(Spatial.active_count(deferred.state), 0, "safe reactivation retains all55warningframes")
	_advance(deferred, 166)
	suite.assert_equal(Spatial.active_count(deferred.state), 3, "safe deferred Web cage activates at exact55frame boundary")


func _link_cap_and_lifetime() -> void:
	var f := _fixture("void_web_weaver.void_web")
	for generation: int in range(1, 5):
		suite.assert_true(_reserve(f, generation), "distinct Web cast reserves finite link")
	_advance(f, 70)
	suite.assert_equal(Spatial.active_count(f.state), 3, "one owner cannot exceed three live links")
	suite.assert_equal(f.state.rows[3].phase, "PENDING", "fourth link retains owned-cap work")
	var fact := {"run_id": "run-spatial-domain", "source_id": "player:bow", "generation": 1, "hit_index": 0, "runtime_frame": 70, "amount": 99.0}
	suite.assert_equal(f.runtime.accept_damage(f.state, f.state.rows[0].id, fact), 15.0, "link damage caps at authored15HP")
	_advance(f, 71)
	suite.assert_equal(f.state.rows[3].phase, "WARNING", "broken link releases slot with full new warning")
	_advance(f, 106)
	suite.assert_equal(Spatial.active_count(f.state), 3, "replacement link enters owned cap after complete35warningframes")
	f.observations["ally-a"].dead = true
	_advance(f, 107)
	suite.assert_equal(Spatial.active_count(f.state), 0, "recipient death cancels every linked benefit")
	var ttl := _fixture("void_web_weaver.void_web")
	_reserve(ttl)
	_advance(ttl, 549)
	suite.assert_equal(Spatial.active_count(ttl.state), 1, "link lives exactly through last of480frames")
	_advance(ttl, 550)
	suite.assert_equal(Spatial.active_count(ttl.state), 0, "link TTL retires at exact480acceptedframes")


func _portal_cap_and_collapse() -> void:
	var f := _fixture("plane_ripper.plane_rip")
	_reserve(f, 1)
	_reserve(f, 2)
	_advance(f, 100)
	suite.assert_equal(Spatial.active_count(f.state), 1, "one portal pair per owner remains admitted")
	suite.assert_equal(f.state.rows[1].phase, "PENDING", "second portal waits without unsafe transit")
	f.observations["spatial-owner"].dead = true
	suite.assert_equal(_advance(f, 101).size(), 1, "active portal emits exactly one owner death collapse reservation")
	suite.assert_equal(f.state.rows[1].phase, "RETIRED", "dead owner cancels pending portal")
	_advance(f, 145)
	suite.assert_equal(f.state.rows[0].phase, "COLLAPSE", "portal death remains harmless through first44warningframes")
	_advance(f, 146)
	suite.assert_equal(f.state.rows[0].phase, "RETIRED", "portal retires at exact45frame collapse boundary")
