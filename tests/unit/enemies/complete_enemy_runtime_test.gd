extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/launch_enemy_runtime.gd")
	_test_all_content(implementation)
	var probe: RefCounted = implementation.new()
	suite.assert_true(probe.has_method("prepare_lethal_transition"), "canonical enemies expose observation-only lethal transition preparation")
	if probe.has_method("prepare_lethal_transition"):
		_test_revival(implementation)
		_test_titan_and_forms(implementation)
		_test_blink_and_kiting(implementation)
		_test_triple_blink(implementation)
	suite.finish(get_tree())


func _definition(id: String, elite: bool = false) -> Dictionary:
	var definition := Definition.new()
	suite.assert_true(definition.configure(Content.enemy(id)).ok, "actual authored definition parses: " + id)
	return definition.runtime_projection("elite" if elite else "enemy")


func _runtime(implementation: Script, id: String, elite: bool = false) -> RefCounted:
	var runtime: RefCounted = implementation.new()
	var identity := Fixtures.identity()
	identity.seed = 42
	suite.assert_true(runtime.configure(_definition(id, elite), identity).ok, "canonical runtime configures: " + id)
	return runtime


func _fact(id: String, frame: int, amount: float, hp: float) -> Dictionary:
	return {"fact_id": id, "runtime_frame": frame, "target_source_id": "hostile:test-a", "amount": amount, "hp_after": hp}


func _test_all_content(implementation: Script) -> void:
	var catalog: Array = Content.read_catalog("enemies.json")
	suite.assert_equal(catalog.size(), 22, "production catalog contains exactly twenty-two species")
	for record: Dictionary in catalog:
		for elite: bool in [false, true]:
			var runtime := _runtime(implementation, record.id, elite)
			if runtime.snapshot().is_empty():
				continue
			var restored := _runtime(implementation, record.id, elite)
			suite.assert_true(restored.restore_snapshot(runtime.snapshot()), "canonical snapshot round trip: " + record.id)
			for frame: int in range(1, 121):
				var context := Fixtures.context(frame)
				context.target_position = {"x": 160.0, "y": 100.0}
				var actual: Dictionary = runtime.advance_frame(frame, context)
				suite.assert_true(actual.ok, "sequential canonical frame: " + record.id)
				suite.assert_equal(actual, restored.advance_frame(frame, context), "canonical checkpoint deterministic: " + record.id)
			var checkpoint: Dictionary = runtime.snapshot()
			suite.assert_true(restored.can_restore_snapshot(checkpoint), "active authored checkpoint validates: " + record.id)
			var malformed := checkpoint.duplicate(true)
			malformed.mechanism_state.unowned = true
			suite.assert_true(not restored.restore_snapshot(malformed), "unowned mechanism field rejects: " + record.id)
			suite.assert_equal(restored.snapshot(), checkpoint, "invalid checkpoint is atomic: " + record.id)


func _test_revival(implementation: Script) -> void:
	for pair: Array in [["chrono_guard", 90, 54.0], ["eternal_hound", 300, 35.0]]:
		var runtime := _runtime(implementation, pair[0])
		var before: Dictionary = runtime.snapshot()
		var decision: Dictionary = runtime.prepare_lethal_transition()
		suite.assert_true(decision.ok and not decision.final_death, "first lethal is nonterminal: " + pair[0])
		suite.assert_equal(runtime.snapshot(), before, "lethal preparation never mutates domain")
		var forged := decision.duplicate(true)
		forged.hp_after = 20.0
		suite.assert_true(not runtime.commit_lethal_transition(forged), "forged lifecycle decision rejects")
		suite.assert_true(runtime.commit_lethal_transition(decision), "authored nonterminal lifecycle commits")
		suite.assert_true(not runtime.commit_lethal_transition(decision), "once-only lifecycle ticket cannot repeat")
		suite.assert_true(runtime.add_control_source("stop-revival", "stop", 30, 1.0), "recovery accepts independent Stop source")
		var hp_requests: Array = []
		for frame: int in range(1, int(pair[1]) + 1):
			var result: Dictionary = runtime.advance_frame(frame, Fixtures.context(frame), false)
			suite.assert_true(result.ok and result.hit_facts.is_empty(), "recovery is nonattacking")
			hp_requests.append_array(result.mechanism_requests)
		suite.assert_equal(hp_requests.size(), 1, "exactly one recovery HP request")
		suite.assert_equal(hp_requests[0].amount, pair[2], "authored recovery HP")
		var second: Dictionary = runtime.prepare_lethal_transition()
		suite.assert_true(second.ok and second.final_death, "revival remains consumed after recovery")
		var restored := _runtime(implementation, pair[0])
		suite.assert_true(restored.restore_snapshot(runtime.snapshot()), "once-only lifecycle state checkpoints")
		suite.assert_true(restored.prepare_lethal_transition().final_death, "restore cannot grant a second revival")
	var hound := _runtime(implementation, "eternal_hound")
	hound.commit_lethal_transition(hound.prepare_lethal_transition())
	suite.assert_true(hound.accept_sigil_damage("sigil-hit", 12.0).final_death, "destroying authored dormant sigil finalizes parent")
	suite.assert_true(not hound.accept_sigil_damage("sigil-hit", 12.0).ok, "sigil hit cannot repeat after finalization")


func _test_titan_and_forms(implementation: Script) -> void:
	var titan := _runtime(implementation, "forge_titan")
	suite.assert_true(not titan.request_action("forge_titan.flame_breath", Fixtures.context()).ok, "Titan breath is locked above half HP")
	titan.accept_damage_fact(_fact("titan-threshold", 0, 250.0, 100.0))
	suite.assert_equal(titan.species_attack_multiplier(), 1.25, "Titan overheat affects attacks")
	suite.assert_equal(titan.species_speed_multiplier(), 1.15, "Titan overheat affects speed")
	var requests: Array = []
	for frame: int in range(1, 601):
		var result: Dictionary = titan.advance_frame(frame, Fixtures.context(frame), false)
		requests.append_array(result.mechanism_requests)
	suite.assert_equal(titan.species_attack_multiplier(), 1.0, "overheat expires after exactly 600 frames")
	suite.assert_equal(requests.size(), 1, "overheat reserves one independently warned explosion")
	suite.assert_equal(requests[0].parameters.warning_frames, 60, "overheat explosion retains full warning")
	titan.accept_damage_fact(_fact("titan-threshold-repeat", 600, 1.0, 99.0))
	suite.assert_equal(titan.species_attack_multiplier(), 1.0, "later damage cannot restart overheat")
	var chaos := _runtime(implementation, "chaos_amalgam")
	suite.assert_true(not chaos.request_action("chaos_amalgam.frost_wave", Fixtures.context()).ok, "red form rejects blue action")
	for frame: int in range(1, 221):
		chaos.advance_frame(frame, Fixtures.context(frame), false)
	var commitment := Fixtures.context(220)
	chaos.request_action("chaos_amalgam.rage_combo", commitment)
	for frame: int in range(221, 316):
		chaos.advance_frame(frame, Fixtures.context(frame), false)
	suite.assert_equal(chaos.snapshot().mechanism_state.form_id, "red", "due form change cannot replace committed action")
	chaos.advance_frame(316, Fixtures.context(316), false)
	suite.assert_equal(chaos.snapshot().mechanism_state.form_id, "blue", "first idle frame commits deterministic next form")
	suite.assert_equal(chaos.snapshot().mechanism_state.switch_remaining_frames, 30, "form switch receives authored recovery")


func _test_blink_and_kiting(implementation: Script) -> void:
	var archer := _runtime(implementation, "void_archer")
	var close := Fixtures.context(1)
	close.target_position = {"x": 140.0, "y": 100.0}
	suite.assert_true(archer.motion_for_frame(1, close).displacement.x < 0.0, "Archer retreats below authored kite band")
	var blink := _runtime(implementation, "blink_striker")
	var start := Fixtures.context()
	start.target_position = {"x": 148.0, "y": 100.0}
	var commitment: Dictionary = blink.request_action("blink_striker.blink_cut", start)
	suite.assert_true(commitment.ok, "Blink commits visible target geometry")
	suite.assert_equal(commitment.threat_facts[0].origin, {"x": 148.0, "y": 100.0}, "Blink damage envelope warns committed landing")
	blink.add_control_source("stop-blink", "stop", 3, 1.0)
	for frame: int in range(1, 4):
		suite.assert_equal(blink.motion_for_frame(frame, Fixtures.context(frame)).displacement, {"x": 0.0, "y": 0.0}, "Stop postpones blink transit")
		blink.advance_frame(frame, Fixtures.context(frame), false)
	var travelled := 0.0
	for frame: int in range(4, 12):
		var context := Fixtures.context(frame)
		context.source_position.x += travelled
		context.target_position.x = 300.0
		var motion: Dictionary = blink.motion_for_frame(frame, context)
		travelled += float(motion.displacement.x)
		context.source_position.x += float(motion.displacement.x)
		blink.advance_frame(frame, context, false)
	suite.assert_true(is_equal_approx(travelled, 48.0), "Blink follows committed transit rather than live target")
	var slowed := _runtime(implementation, "blink_striker")
	slowed.add_control_source("rift-blink", "rift", 60, 0.5)
	var rift_commitment: Dictionary = slowed.request_action("blink_striker.blink_cut", start)
	suite.assert_equal(rift_commitment.threat_facts[0].origin, {"x": 124.0, "y": 100.0}, "Rift warning freezes the shortened landing before transit")
	var distance := 0.0
	for frame: int in range(1, 9):
		var context := Fixtures.context(frame)
		context.source_position.x += distance
		var motion: Dictionary = slowed.motion_for_frame(frame, context)
		distance += float(motion.displacement.x)
		context.source_position.x += float(motion.displacement.x)
		slowed.advance_frame(frame, context, false)
	suite.assert_true(is_equal_approx(distance, 24.0), "Rift halves authored blink travel")


func _test_triple_blink(implementation: Script) -> void:
	var authored := _definition("blink_striker", true)
	var action: Dictionary = authored.actions.back()
	suite.assert_equal(action.active_frames, 70, "elite blink timeline fits three fully warned strikes")
	suite.assert_equal(action.hit_schedule.map(func(hit: Dictionary): return hit.offset_frame), [0, 33, 66], "elite blink allows eight transit and twenty-five post-landing frames")
	var runtime := _runtime(implementation, "blink_striker", true)
	var context := Fixtures.context()
	context.target_position = {"x": 148.0, "y": 100.0}
	var commitment: Dictionary = runtime.request_action("blink_striker.triple_blink", context)
	suite.assert_equal(commitment.threat_facts.map(func(fact: Dictionary): return fact.origin), [{"x": 148.0, "y": 100.0}, {"x": 148.0, "y": 132.0}, {"x": 148.0, "y": 68.0}], "three landing envelopes are fixed and distinct from first warning")
	var position := Vector2(100.0, 100.0)
	var landing_frames := [8, 58, 91]
	var strike_frames := [50, 83, 116]
	var points := [Vector2(148, 100), Vector2(148, 132), Vector2(148, 68)]
	var hits: Array = []
	for frame: int in range(1, 121):
		var observations := Fixtures.context(frame)
		observations.source_position = {"x": position.x, "y": position.y}
		var motion: Dictionary = runtime.motion_for_frame(frame, observations)
		position += Vector2(float(motion.displacement.x), float(motion.displacement.y))
		observations.source_position = {"x": position.x, "y": position.y}
		var result: Dictionary = runtime.advance_frame(frame, observations, false)
		for hit: Dictionary in result.hit_facts:
			hits.append(frame)
			var index: int = hit.hit_index
			suite.assert_true(position.is_equal_approx(points[index]), "each elite blink hit uses its physical committed landing")
			suite.assert_equal(hit.geometry.size(), 1, "each blink strike authorizes only its own warned landing")
			suite.assert_equal(hit.geometry[0].origin, {"x": points[index].x, "y": points[index].y}, "independent blink geometry follows its indexed landing")
			suite.assert_equal(hit.attack_generation, 7 + index, "independent blink strike uses its own reserved generation")
		if landing_frames.has(frame):
			var index: int = landing_frames.find(frame)
			suite.assert_true(position.is_equal_approx(points[index]), "each elite blink transit ends at its warned envelope")
			suite.assert_true(strike_frames[index] - frame >= 25, "each landing retains twenty-five-frame followup warning")
	suite.assert_equal(hits, strike_frames, "elite blink emits each independent strike on authored frame")
	var malformed := authored.duplicate(true)
	malformed.actions.back().hit_schedule[1].offset_frame = 27
	var identity := Fixtures.identity()
	identity.seed = 42
	suite.assert_true(not implementation.new().configure(malformed, identity).ok, "impossible blink transit/warning timeline rejects")
