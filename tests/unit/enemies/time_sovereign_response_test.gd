extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const Responses := preload("res://scripts/enemies/launch/time_sovereign_response_runtime.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var parser := Definition.new()
	parser.configure(Fixtures.boss("time_sovereign"))
	var runtime := Runtime.new()
	var identity := Actions.identity()
	identity.seed = 42
	var configured: Dictionary = runtime.configure(parser.runtime_projection(), identity)
	suite.assert_true(configured.ok, "Time Sovereign configures canonical domain: " + str(configured))
	suite.assert_true(runtime.has_method("accept_time_ability_receipt"), "Time Sovereign needs a bounded authentic paid-ability response admission")
	if not runtime.has_method("accept_time_ability_receipt"):
		suite.finish(get_tree())
		return
	suite.assert_true(runtime.snapshot().has("time_response"), "Time Sovereign response ledger must survive native cold snapshots")
	if not configured.ok:
		suite.finish(get_tree())
		return
	for phase: int in [0, 1]:
		for ability: String in ["stop", "rewind", "accelerate", "rift"]:
			_test_response(suite, parser.runtime_projection(), identity, phase, ability)
	_test_bounded_queue(suite, parser.runtime_projection(), identity)
	_test_stop_delay(suite, parser.runtime_projection(), identity)
	_test_historical(suite, parser.runtime_projection(), identity)
	_test_shared_cooldown(suite, parser.runtime_projection(), identity)
	_test_small_watch_hits(suite, parser.runtime_projection(), identity)
	_test_receipt_restore_boundary(suite, parser.runtime_projection(), identity)
	suite.finish(get_tree())


func _receipt(frame: int, token: int, ability: String) -> Dictionary:
	var receipt := {"id": "", "run_id": "run-p15", "owner_generation": 1, "action_generation": 1, "action_token": token, "ability_id": ability, "runtime_frame": frame, "endpoint": {"x": 180.0, "y": 100.0}, "facing": {"x": 1.0, "y": 0.0}}
	receipt.id = Responses.receipt_id(receipt)
	return receipt


func _watch(frame: int, id: String, amount: float, accelerated: bool = false, echo: bool = false) -> Dictionary:
	return {"fact_id": id, "runtime_frame": frame, "amount": amount, "accelerated": accelerated, "rewind_echo": echo}


func _test_response(suite: RefCounted, definition: Dictionary, identity: Dictionary, phase: int, ability: String) -> void:
	var runtime := Runtime.new()
	runtime.configure(definition, identity)
	var frame := 0
	if phase == 1:
		runtime.accept_damage_fact({"fact_id": "response-phase", "runtime_frame": 0, "target_source_id": identity.hostile_source_id, "amount": 800.0, "hp_after": 1200.0})
		for next: int in range(1, 61):
			runtime.advance_frame(next, Actions.context(next), false)
		frame = 60
	suite.assert_true(not runtime.request_action("traitor.counter_" + ability, Actions.context(frame)).ok, "UI-like direct request cannot invent a paid ability response")
	suite.assert_true(runtime.request_action("traitor_temporal_slash", Actions.context(frame)).ok, "existing primary warning precedes queued response")
	var receipt := _receipt(frame, 1, ability)
	suite.assert_true(runtime.accept_time_ability_receipt(receipt).ok, "paid ability generation queues " + ability)
	var queued: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.accept_time_ability_receipt(receipt).ok and runtime.snapshot() == queued, "duplicate paid generation cannot queue twice")
	var forged := receipt.duplicate(true)
	forged.action_token = 2
	suite.assert_true(not runtime.accept_time_ability_receipt(forged).ok, "forged identity without producer digest refuses")
	var primary_through: int = runtime.snapshot().action.idle_through_frame
	for offset: int in range(1, primary_through - frame + 2):
		runtime.advance_frame(frame + offset, Actions.context(frame + offset), false)
		if offset <= 70:
			suite.assert_equal(runtime.snapshot().action.action_id, "traitor_temporal_slash", "queued response preserves primary through recovery")
	frame = primary_through + 1
	var requested: Dictionary = runtime.request_action("traitor.counter_" + ability, Actions.context(frame))
	suite.assert_true(requested.ok, "deferred response starts after full primary recovery and authored idle: " + ability + " " + str(requested))
	if not requested.ok:
		return
	var start := frame
	var active: Dictionary = runtime.snapshot().time_response.active
	suite.assert_equal(runtime.snapshot().time_response.cooldown_until_frame, start + (900 if phase == 0 else 600), "all response kinds share exact phase cooldown")
	if ability == "rewind":
		suite.assert_equal(requested.threat_facts.size(), 2, "Rewind marks frozen endpoint and separate safe arrival")
		suite.assert_equal(requested.threat_facts[1].origin, receipt.endpoint, "actual restored endpoint stays frozen")
		suite.assert_close(Vector2(float(requested.threat_facts[0].origin.x), float(requested.threat_facts[0].origin.y)).distance_to(Vector2(180, 100)), 48.0, "marked arrival remains48pxfrom restoredPlayer")
		suite.assert_equal(requested.threat_facts[0].origin, {"x": 132.0, "y": 100.0}, "marked arrival locks paid Player facing rather than Boss approach")
		var exposed: Dictionary = runtime.accept_time_response_watch_hit(_watch(frame, "rewind-echo", 1.0, false, true))
		suite.assert_equal(exposed.exposure_frames, 30, "authentic echo creates30framepositivewatchwindow")
		suite.assert_equal(runtime.accept_time_response_watch_hit(_watch(frame, "rewind-echo-again", 1.0, false, true)).exposure_frames, 0, "same paid rewind cannot grant multiple echo windows")
	if ability == "stop":
		var first: Dictionary = runtime.accept_time_response_watch_hit(_watch(frame, "counter-stop-1", 20.0))
		suite.assert_true(first.ok and not first.cancel_action, "Stop counter40loss threshold accumulates actual watch loss")
		suite.assert_true(not runtime.accept_time_response_watch_hit(_watch(frame, "counter-stop-1", 20.0)).cancel_action, "spent watch identity never adds cancellation damage twice")
		var second: Dictionary = runtime.accept_time_response_watch_hit(_watch(frame, "counter-stop-2", 20.0))
		suite.assert_true(second.cancel_action and second.exposure_frames == 60 and second.recovery_frames == 60 and runtime.snapshot().action.phase == "IDLE", "forty actual watch loss cancels pulse and grants full60framepunishment")
	else:
		for offset: int in range(1, 46):
			frame = start + offset
			var result: Dictionary = runtime.advance_frame(frame, Actions.context(frame), false)
			suite.assert_true(result.ok, "response accepts fixed warningframe")
			if offset < 45:
				suite.assert_true(result.hit_facts.is_empty() and result.effect_requests.is_empty(), "response retains all45warningframes before effects")
		if ability == "accelerate":
			suite.assert_equal(runtime.snapshot().time_response.active.expires_frame, frame + 119, "accelerate field has finite120frameauthoredlifetime")
			for index: int in range(6):
				var hit: Dictionary = runtime.accept_time_response_watch_hit(_watch(frame, "accelerated:%d" % index, 1.0, true))
				suite.assert_equal(hit.shatter_zone, index == 5, "six distinct accelerated identities shatter once")
			suite.assert_true(not runtime.time_response_zone_alive(int(active.attack_generation)) and runtime.is_exposed(), "shattered field retires and grants90framepositivewindow")
		elif ability == "rift":
			for offset: int in range(46, 76):
				frame = start + offset
				runtime.advance_frame(frame, Actions.context(frame), false)
			suite.assert_equal(runtime.snapshot().mechanism_state.delay_remaining_frames, 45, "Rift pulse waits30activeframes then grants45extra recovery")
	var cold: Dictionary = runtime.snapshot()
	var encoded := Replay.encode_replay_json(cold)
	var fresh := Runtime.new()
	fresh.configure(definition, identity)
	suite.assert_true(encoded.ok and fresh.restore_snapshot(Replay.decode_replay_json(encoded.json).replay) and fresh.snapshot() == cold, "fresh typed cold state retains paid generation and positive responsewindow: " + ability + " " + str(phase))
	var forged_cold := cold.duplicate(true)
	forged_cold.time_response.active.start_frame = int(receipt.runtime_frame) - 1
	suite.assert_true(not fresh.can_restore_snapshot(forged_cold) and fresh.snapshot() == cold, "impossible prepaymentresponse snapshot refuses unchanged: " + ability)


func _test_bounded_queue(suite: RefCounted, definition: Dictionary, identity: Dictionary) -> void:
	var runtime := Runtime.new()
	runtime.configure(definition, identity)
	for token: int in range(1, 33):
		var accepted: Dictionary = runtime.accept_time_ability_receipt(_receipt(0, token, "accelerate"))
		suite.assert_true(accepted.ok, "full responsequeue does not consume or reject the paid Player ability")
	suite.assert_equal(runtime.snapshot().time_response.pending.size(), 4, "pending responses remainboundedatfour")
	suite.assert_true(not runtime.accept_time_ability_receipt(_receipt(0, 1, "accelerate")).ok, "oldest spent producer token remains rejected after capacity")
	suite.assert_true(runtime.can_restore_snapshot(runtime.snapshot()), "full bounded ledger remains strict cold boundary")


func _test_stop_delay(suite: RefCounted, definition: Dictionary, identity: Dictionary) -> void:
	var runtime := Runtime.new()
	runtime.configure(definition, identity)
	suite.assert_true(runtime.accept_time_ability_receipt(_receipt(0, 1, "stop")).ok, "idle paid Stop queues its delayed response")
	for frame: int in range(1, 72):
		runtime.advance_frame(frame, Actions.context(frame), false)
		suite.assert_true(not runtime.request_action("traitor.counter_stop", Actions.context(frame)).ok, "Stop never starts before frame72")
	runtime.advance_frame(72, Actions.context(72), false)
	suite.assert_true(runtime.request_action("traitor.counter_stop", Actions.context(72)).ok, "idle Stop starts exactly at its72frameboundary")


func _test_historical(suite: RefCounted, definition: Dictionary, identity: Dictionary) -> void:
	for target_frame: int in [0, 35, 42, 91]:
		var old := Runtime.new()
		old.configure(definition, identity)
		old._action = old._make_action(0, false, true, false)
		old._legacy_time_action = true
		old.request_action("traitor_temporal_slash", Actions.context(0))
		for frame: int in range(1, target_frame + 1):
			old.advance_frame(frame, Actions.context(frame), false)
		var legacy: Dictionary = old.snapshot()
		legacy.schema_version = 1
		legacy.erase("time_response")
		var fresh := Runtime.new()
		fresh.configure(definition, identity)
		var normalized: Dictionary = fresh.normalize_native_snapshot(legacy)
		suite.assert_true(not normalized.is_empty() and normalized.schema_version == 9 and normalized.time_response.watermark.is_empty() and fresh.restore_snapshot(normalized), "exact historical Time Boss receives empty responseledger atframe%d" % target_frame)
		if normalized.is_empty():
			continue
		var next: Dictionary = fresh.advance_frame(target_frame + 1, Actions.context(target_frame + 1), false)
		suite.assert_true(next.ok, "historical action retains its next acceptedframe%d" % target_frame)


func _test_shared_cooldown(suite: RefCounted, definition: Dictionary, identity: Dictionary) -> void:
	var runtime := Runtime.new()
	runtime.configure(definition, identity)
	runtime.accept_time_ability_receipt(_receipt(0, 1, "accelerate"))
	runtime.accept_time_ability_receipt(_receipt(0, 2, "accelerate"))
	suite.assert_true(runtime.request_action("traitor.counter_accelerate", Actions.context(0)).ok, "first paid Accelerate begins its native sharedcooldown")
	for frame: int in range(1, 900):
		runtime.advance_frame(frame, Actions.context(frame), false)
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.request_action("traitor.counter_accelerate", Actions.context(899)).ok and runtime.snapshot() == before, "pending paid response cannot consume or reset sharedcooldown early")
	runtime.advance_frame(900, Actions.context(900), false)
	suite.assert_true(runtime.request_action("traitor.counter_accelerate", Actions.context(900)).ok, "second paid generation starts exactly at sharedcooldownboundary")
	suite.assert_true(runtime.can_restore_snapshot(runtime.snapshot()), "consecutive authentic same-kind responses remain coldrestorable")
	var forged: Dictionary = runtime.snapshot()
	forged.time_response.active.attack_generation -= 1
	suite.assert_true(not runtime.can_restore_snapshot(forged), "active response generation must match the authentic current action")


func _test_small_watch_hits(suite: RefCounted, definition: Dictionary, identity: Dictionary) -> void:
	var runtime := Runtime.new()
	runtime.configure(definition, identity)
	runtime.accept_time_ability_receipt(_receipt(0, 1, "stop"))
	for frame: int in range(1, 73):
		runtime.advance_frame(frame, Actions.context(frame), false)
	runtime.request_action("traitor.counter_stop", Actions.context(72))
	for index: int in range(80):
		runtime.accept_time_response_watch_hit(_watch(72, "small-watch:%d" % index, 0.5))
	suite.assert_true(runtime.snapshot().time_response.active.cancelled and runtime.can_restore_snapshot(runtime.snapshot()), "many small accepted watch losses retain the full cancellation and cold ledger")


func _test_receipt_restore_boundary(suite: RefCounted, definition: Dictionary, identity: Dictionary) -> void:
	var runtime := Runtime.new()
	runtime.configure(definition, identity)
	runtime.accept_time_ability_receipt(_receipt(0, 1, "rewind"))
	runtime.request_action("traitor.counter_rewind", Actions.context(0))
	var cold: Dictionary = runtime.snapshot()
	for field: String in ["empty_watermark", "future_rewind", "duplicate_pending", "wrong_cooldown"]:
		var forged := cold.duplicate(true)
		match field:
			"empty_watermark": forged.time_response.watermark = {}
			"future_rewind": forged.time_response.last_rewind.receipt = _receipt(0, 2, "rewind")
			"duplicate_pending": forged.time_response.pending = [forged.time_response.active.receipt.duplicate(true)]
			"wrong_cooldown": forged.time_response.cooldown_until_frame += 1
		suite.assert_true(not runtime.can_restore_snapshot(forged) and runtime.snapshot() == cold, "strict response boundary refuses impossible receipt chronology: " + field)
