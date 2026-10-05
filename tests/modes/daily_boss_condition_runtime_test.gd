extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const Payload := preload("res://scripts/enemies/launch/launch_hostile_payload_runtime.gd")
var _suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = Suite.new()
	for row: Dictionary in Fixtures.read_catalog("bosses.json"):
		var parser := Definition.new()
		_suite.assert_true(parser.configure(row).ok, "authored Daily Boss parses " + row.id)
		var base := parser.runtime_projection()
		_verify_swift(base)
		_verify_low_hp(base)
		_verify_volleys(base)
	_suite.finish(get_tree())


func _identity() -> Dictionary:
	var result := Actions.identity()
	result.seed = 42
	return result


func _verify_swift(base: Dictionary) -> void:
	var projected := Definition.daily_projection(base, ["swift_finish"])
	var runtime := Runtime.new()
	_suite.assert_true(projected.ok and runtime.configure(projected.definition, _identity()).ok, "sixty-second Daily enrage binds " + base.id)
	for frame: int in range(1, 3600):
		if not runtime.advance_frame(frame, Actions.context(frame), false).ok:
			_suite.assert_true(false, "accepted Daily enrage clock advances " + base.id)
			return
	_suite.assert_true(not runtime.snapshot().mechanism_state.enraged, "Daily Boss remains calm through accepted frame3599 " + base.id)
	_suite.assert_true(runtime.advance_frame(3600, Actions.context(3600), false).ok and runtime.snapshot().mechanism_state.enraged, "Daily Boss enrages at accepted frame3600 " + base.id)
	var cold := Runtime.new()
	_suite.assert_true(cold.configure(projected.definition, _identity()).ok and cold.restore_snapshot(runtime.snapshot()), "Daily exact enrage boundary cold-restores " + base.id)
	var forged: Dictionary = projected.definition.duplicate(true)
	forged.enrage.threshold_frames += 1
	_suite.assert_true(not Runtime.new().configure(forged, _identity()).ok, "Daily projection cannot forge enrage threshold " + base.id)


func _verify_low_hp(base: Dictionary) -> void:
	var projected := Definition.daily_projection(base, ["final_strike"])
	for below: bool in [false, true]:
		var runtime := Runtime.new()
		runtime.configure(projected.definition, _identity())
		var hp := float(base.max_hp) * 0.1 - (1.0 if below else 0.0)
		_suite.assert_true(runtime.accept_damage_fact({"fact_id": "daily-threshold", "runtime_frame": 0, "target_source_id": _identity().hostile_source_id, "amount": float(base.max_hp) - hp, "hp_after": hp}).ok, "authentic low-HP damage settles " + base.id)
		var multiplier := 2.0 if below else 1.0
		_suite.assert_equal(runtime.daily_outgoing_multiplier(), multiplier, "strict ten-percent outgoing threshold " + base.id)
		for frame: int in range(1, 61):
			runtime.advance_frame(frame, Actions.context(frame), false)
		var action: Dictionary = {}
		for candidate: Dictionary in projected.definition.actions:
			if candidate.id in base.phases[-1].action_ids and candidate.id != "matriarch_root_sweep" and not candidate.hit_schedule.is_empty() and candidate.hit_schedule[0].offset_frame == 0 and candidate.handler_id in ["melee", "area", "projectile_volley"]:
				action = candidate
				break
		_suite.assert_true(runtime.request_action(action.id, _context(60, action)).ok, "native threshold attack begins " + action.id)
		var result: Dictionary = {}
		for frame: int in range(61, 61 + int(action.warning_frames)):
			result = runtime.advance_frame(frame, _context(frame, action), false)
		_suite.assert_true(not result.get("hit_facts", []).is_empty(), "native threshold attack emits actual hits " + action.id)
		for hit: Dictionary in result.get("hit_facts", []):
			var phase_damage := float(base.mechanisms.phase_damage_overrides.get(base.phases[-1].id, {}).get(action.id, action.hit_schedule[0].damage))
			_suite.assert_equal(hit.damage, phase_damage * multiplier, "actual outgoing hit follows strict low-HP multiplier " + action.id)
		if base.id != "ruin_king":
			continue
		runtime = Runtime.new()
		runtime.configure(projected.definition, _identity())
		runtime.accept_damage_fact({"fact_id": "daily-charge-threshold", "runtime_frame": 0, "target_source_id": _identity().hostile_source_id, "amount": float(base.max_hp) - hp, "hp_after": hp})
		for frame: int in range(1, 61):
			runtime.advance_frame(frame, Actions.context(frame), false)
		action = _action(projected.definition, "guardian_charge")
		_suite.assert_true(runtime.request_action(action.id, _context(60, action)).ok, "native Daily charge begins")
		for frame: int in range(61, 61 + int(action.warning_frames)):
			runtime.advance_frame(frame, _context(frame, action), false)
		var contact := runtime.charge_contact_fact(60 + int(action.warning_frames), "player:1")
		_suite.assert_true(not contact.is_empty(), "native Daily charge creates actual contact fact")
		_suite.assert_equal(contact.get("damage"), float(action.hit_schedule[0].damage) * multiplier, "actual charge contact follows strict low-HP multiplier")


func _verify_volleys(base: Dictionary) -> void:
	var projected := Definition.daily_projection(base, ["bullet_hell"])
	for action: Dictionary in projected.definition.actions:
		if action.handler_id != "projectile_volley":
			continue
		var runtime := Runtime.new()
		runtime.configure(projected.definition, _identity())
		var start := 0
		for phase: int in range(base.phases.size()):
			if action.id not in base.phases[phase].action_ids:
				continue
			if phase > 0:
				var hp := float(base.max_hp) * float(base.phases[phase].hp_threshold)
				runtime.accept_damage_fact({"fact_id": "daily-volley-phase", "runtime_frame": 0, "target_source_id": _identity().hostile_source_id, "amount": float(base.max_hp) - hp, "hp_after": hp})
				start = 60
				for frame: int in range(1, start + 1):
					runtime.advance_frame(frame, Actions.context(frame), false)
			break
		var request := runtime.request_action(action.id, _context(start, action))
		_suite.assert_true(request.ok, "expanded native volley begins " + action.id)
		var payload := Payload.new()
		payload.configure("run-p15", start)
		var mechanisms: Dictionary = {}
		if action.id == "guardian_debris_barrage":
			for field: String in ["debris_hp", "debris_lifetime_frames", "debris_count_cap"]:
				mechanisms[field] = base.mechanisms[field]
		for frame: int in range(start + 1, start + int(action.warning_frames) + int(action.active_frames) + 1):
			var batch := runtime.advance_frame(frame, _context(frame, action), false)
			_suite.assert_true(payload.advance_frame(frame, {"targets": {}, "projectile_contacts": {}}).ok, "actual volley payload accepts sequential frame")
			for hit: Dictionary in batch.get("hit_facts", []):
				_suite.assert_true(payload.reserve_projectile(hit, {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0}, mechanisms).ok, "every expanded lane reserves actual native projectile " + action.id)
		var original := _action(base, action.id)
		var expected := ceili(original.geometry.size() * 1.5)
		_suite.assert_equal(payload.snapshot().projectiles.size(), expected, "actual reserved projectile count is150percent rounded up " + action.id)
		var cold := Payload.new()
		cold.configure("run-p15", start)
		_suite.assert_true(cold.restore_snapshot(payload.snapshot()), "expanded actual projectile ledger cold-restores " + action.id)
		if action.id == "guardian_debris_barrage":
			_suite.assert_equal(expected, 9, "Daily debris retains nine distinct landing identities")
			_suite.assert_equal(payload.snapshot().arena_debris.recipe.count_cap, 4, "Daily debris preserves four-live-body arena budget")
		if action.id == "voidking_shard_projection":
			_suite.assert_equal(expected, 12, "Daily shard projection emits twelve distinct native lanes")


func _action(definition: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in definition.actions:
		if row.id == id:
			return row
	return {}


func _context(frame: int, action: Dictionary) -> Dictionary:
	var result := Actions.context(frame)
	result.target_position.x = 100.0 + maxf(float(action.distance_min_px), minf(40.0, float(action.distance_max_px)))
	return result
