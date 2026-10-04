extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var implementation := load("res://scripts/enemies/launch/launch_boss_runtime.gd") as Script
	suite.assert_true(implementation != null, "five native Bosses require a deterministic fixed-frame runtime")
	for row: Dictionary in Fixtures.read_catalog("bosses.json"):
		var parser := Definition.new()
		var parsed: Dictionary = parser.configure(row)
		suite.assert_true(parsed.ok, "native Boss uses authored definition: " + row.id)
		if not parsed.ok:
			continue
		var projection: Dictionary = parser.runtime_projection()
		suite.assert_true(projection.has("collision_radius_px") and projection.get("collision_radius_px") == row.collision_radius_px, "runtime retains physical Boss collision size: " + row.id)
		if implementation == null:
			continue
		var runtime: RefCounted = implementation.new()
		var identity := Actions.identity()
		identity.seed = 42
		suite.assert_true(runtime.configure(projection, identity).ok, "native runtime accepts real Boss: " + row.id)
		var checkpoint: Dictionary = runtime.snapshot()
		suite.assert_true(not checkpoint.is_empty() and checkpoint.runtime_frame == 0 and checkpoint.mechanism_state.phase_index == 0, "Boss begins with exact authored first phase")
		var first: Dictionary = runtime.advance_frame(1, Actions.context(1))
		suite.assert_true(first.ok, "sequential actual Boss frame advances")
		suite.assert_true(runtime.restore_snapshot(checkpoint), "exact native Boss domain checkpoint restores")
		suite.assert_equal(runtime.advance_frame(1, Actions.context(1)), first, "restored Boss decision and geometry remain deterministic")
		var before: Dictionary = runtime.snapshot()
		suite.assert_true(not runtime.advance_frame(3, Actions.context(3)).ok and runtime.snapshot() == before, "skipped Boss frame refuses without mutation")
		var forged := before.duplicate(true)
		forged.mechanism_state.phase_index = row.phases.size()
		suite.assert_true(not runtime.restore_snapshot(forged) and runtime.snapshot() == before, "out-of-range Boss phase snapshot refuses unchanged")
		_test_controls(suite, implementation, projection, identity)
		_test_phases(suite, implementation, projection, identity)
		_test_snapshot_guards(suite, implementation, projection, identity)
		_test_authored_actions(suite, implementation, projection, identity)
		_test_enrage(suite, implementation, projection, identity)
		_test_character_tail(suite, implementation, projection, identity)
		_test_long_damage_history(suite, implementation, projection, identity)
		_test_weapon_source_lifetime(suite, implementation, projection, identity)
	suite.finish(get_tree())


func _test_controls(suite: RefCounted, implementation: Script, definition: Dictionary, identity: Dictionary) -> void:
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "control fixture binds actual Boss definition")
	var context := _context(0, definition.actions[0])
	suite.assert_true(runtime.request_action(definition.actions[0].id, context).ok, "actual Boss begins authored warning")
	suite.assert_true(runtime.add_control_source("stop-native", "stop", 180, 1.0), "Boss accepts actual three-second Stop conversion")
	var stopped: Dictionary = runtime.snapshot()
	suite.assert_equal(stopped.mechanism_state.delay_remaining_frames, 63, "Stop grants the authored 0.35 warning conversion")
	suite.assert_true(runtime.is_exposed() and not runtime.control_modifiers().action_paused, "Boss Stop exposes the core through positive conversion")
	suite.assert_true(not runtime.add_control_source("stop-native", "stop", 180, 1.0) and runtime.snapshot() == stopped, "duplicate Stop source cannot extend again")
	suite.assert_true(not runtime.add_control_source("invalid-rift", "rift", 30, -1.0) and runtime.snapshot() == stopped, "invalid negative Rift magnitude refuses without clamping into a valid source")
	suite.assert_true(runtime.add_control_source("rift-native", "rift", 30, 0.25), "positive Rift uses Boss movement floor")
	suite.assert_close(runtime.control_modifiers().movement_multiplier, 0.70, "Boss Rift floor is 0.70")
	var checkpoint: Dictionary = runtime.snapshot()
	var next := _context(1, definition.actions[0])
	var batch: Dictionary = runtime.advance_frame(1, next, false)
	suite.assert_true(batch.ok and runtime.snapshot().action.paused_frames == 1 and runtime.snapshot().mechanism_state.delay_remaining_frames == 62, "one accepted frame advances one converted warning clock")
	suite.assert_true(runtime.restore_snapshot(checkpoint), "Boss restores exact pending Stop and Rift conversion")
	suite.assert_equal(runtime.advance_frame(1, next, false), batch, "converted Boss frame restores deterministically")


func _test_phases(suite: RefCounted, implementation: Script, definition: Dictionary, identity: Dictionary) -> void:
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(definition, identity).ok, "phase fixture binds actual Boss")
	var phase_action := ""
	for id: String in definition.phases[1].action_ids:
		if id not in definition.phases[0].action_ids:
			phase_action = id
			break
	suite.assert_true(not phase_action.is_empty(), "authored second phase adds an action: " + definition.id)
	suite.assert_true(not runtime.request_action(phase_action, Actions.context(0)).ok, "next-phase action cannot bypass authored HP threshold")
	suite.assert_true(runtime.request_action(definition.actions[0].id, _context(0, definition.actions[0])).ok, "phase change owns an actual committed warning")
	var hp := float(definition.max_hp) * float(definition.phases[1].hp_threshold)
	var fact := {"fact_id": "phase-hit", "runtime_frame": 0, "target_source_id": identity.hostile_source_id, "amount": float(definition.max_hp) - hp, "hp_after": hp}
	var changed: Dictionary = runtime.accept_damage_fact(fact)
	suite.assert_true(changed.ok and not changed.retired_generations.is_empty() and runtime.snapshot().mechanism_state.phase_index == 1 and runtime.snapshot().action.phase == "IDLE", "authored HP transition cancels and retires the real primary warning")
	var checkpoint: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.accept_damage_fact(fact).ok and runtime.snapshot() == checkpoint, "duplicate accepted damage fact cannot repeat phase transition")
	for frame: int in range(1, 60):
		var next: Dictionary = runtime.advance_frame(frame, Actions.context(frame))
		suite.assert_true(next.ok and next.threat_facts.is_empty() and next.hit_facts.is_empty(), "phase cue remains nonattacking for sixty accepted frames")
	var final: Dictionary = runtime.advance_frame(60, Actions.context(60), false)
	suite.assert_true(final.ok and runtime.request_action(phase_action, _context(60, _action(definition, phase_action))).ok, "next-phase action becomes available after the entire cue")
	suite.assert_true(runtime.restore_snapshot(checkpoint), "phase checkpoint restores full changed action regime")
	var forged := checkpoint.duplicate(true)
	forged.mechanism_state.damage_claims.append("phase-hit")
	suite.assert_true(not runtime.restore_snapshot(forged) and runtime.snapshot() == checkpoint, "duplicate damage claims in a restored Boss snapshot refuse unchanged")


func _action(definition: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in definition.actions:
		if row.id == id:
			return row
	return {}


func _test_snapshot_guards(suite: RefCounted, implementation: Script, definition: Dictionary, identity: Dictionary) -> void:
	var runtime: RefCounted = implementation.new()
	runtime.configure(definition, identity)
	runtime.add_control_source("rift:snapshot", "rift", 120, 0.70)
	var before: Dictionary = runtime.snapshot()
	var forged := before.duplicate(true)
	forged.control.sources[0].magnitude = 0.40
	suite.assert_true(not runtime.restore_snapshot(forged) and runtime.snapshot() == before, "Boss snapshot cannot restore ordinary Rift magnitude: " + definition.id)
	forged = before.duplicate(true)
	forged.control.sources[0].kind = "stop"
	forged.control.sources[0].magnitude = 1.0
	suite.assert_true(not runtime.restore_snapshot(forged) and runtime.snapshot() == before, "Boss snapshot cannot replace positive Stop conversion with full freeze: " + definition.id)
	forged = before.duplicate(true)
	forged.mechanism_state.last_action_id = definition.actions[0].id
	forged.mechanism_state.consecutive_actions = int(definition.actions[0].max_consecutive) + 1
	suite.assert_true(not runtime.restore_snapshot(forged) and runtime.snapshot() == before, "Boss snapshot cannot exceed authored consecutive action budget: " + definition.id)
	var malformed := definition.duplicate(true)
	malformed["unknown"] = true
	suite.assert_true(not implementation.new().configure(malformed, identity).ok, "Boss runtime projection rejects unknown fields")
	malformed = definition.duplicate(true)
	malformed.actions[0].id = "foreign_boss_action"
	suite.assert_true(not implementation.new().configure(malformed, identity).ok, "Boss runtime projection rejects foreign authored action")
	var foreign := identity.duplicate(true)
	foreign.runtime_frame = 0.5
	suite.assert_true(not implementation.new().configure(definition, foreign).ok, "Boss runtime rejects fractional accepted-frame identity")


func _test_authored_actions(suite: RefCounted, implementation: Script, definition: Dictionary, identity: Dictionary) -> void:
	for action: Dictionary in definition.actions:
		if action.id == definition.enrage.action_id:
			continue
		var phase := 0
		for index: int in range(definition.phases.size()):
			if action.id in definition.phases[index].action_ids:
				phase = index
				break
		var runtime: RefCounted = implementation.new()
		runtime.configure(definition, identity)
		var frame := 0
		if phase > 0:
			var hp := float(definition.max_hp) * float(definition.phases[phase].hp_threshold)
			runtime.accept_damage_fact({"fact_id": "action-phase", "runtime_frame": 0, "target_source_id": identity.hostile_source_id, "amount": float(definition.max_hp) - hp, "hp_after": hp})
			for next_frame: int in range(1, 61):
				runtime.advance_frame(next_frame, Actions.context(next_frame), false)
			frame = 60
		var request: Dictionary = runtime.request_action(action.id, _context(frame, action))
		suite.assert_true(request.ok and (action.geometry.is_empty() or not request.threat_facts.is_empty()), "every authored Boss move commits its declared warning geometry: " + action.id)
		if not request.ok:
			continue
		var warning: Dictionary = runtime.snapshot()
		var total_hits := 0
		var total_effects := 0
		var last: Dictionary = {}
		for offset: int in range(1, int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames) + 1):
			last = runtime.advance_frame(frame + offset, _context(frame + offset, action), false)
			suite.assert_true(last.ok, "authored action advances through exact fixed-frame schedule: " + action.id)
			total_hits += last.get("hit_facts", []).size()
			total_effects += last.get("effect_requests", []).size()
		suite.assert_true(last.get("phase") == "IDLE" and total_hits == action.hit_schedule.size() and total_effects > 0, "authored Boss move completes exact hit/effect schedule: " + action.id)
		suite.assert_true(runtime.restore_snapshot(warning), "every real warning restores its authored regime: " + action.id)


func _test_enrage(suite: RefCounted, implementation: Script, definition: Dictionary, identity: Dictionary) -> void:
	var runtime: RefCounted = implementation.new()
	runtime.configure(definition, identity)
	var action := _action(definition, definition.enrage.action_id)
	suite.assert_true(not runtime.request_action(action.id, _context(0, action)).ok, "enrage move is unavailable before accepted-frame threshold")
	for frame: int in range(1, int(definition.enrage.threshold_frames) + 1):
		var result: Dictionary = runtime.advance_frame(frame, _context(frame, action), false)
		if not result.ok:
			suite.assert_true(false, "accepted-frame enrage clock failed: " + definition.id)
			return
	var frame := int(definition.enrage.threshold_frames)
	suite.assert_true(runtime.snapshot().mechanism_state.enraged, "enrage begins at exact accepted-frame threshold: " + definition.id)
	var request: Dictionary = runtime.request_action(action.id, _context(frame, action))
	suite.assert_true(request.ok, "all five authored enrage moves become real actions")
	if not request.ok:
		return
	var checkpoint: Dictionary = runtime.snapshot()
	suite.assert_equal(checkpoint.action.cooldowns[action.id], frame + ceili(int(action.cooldown_frames) * 0.85), "enrage uses authored cooldown multiplier")
	var result: Dictionary = {}
	for offset: int in range(1, int(action.warning_frames) + 1):
		result = runtime.advance_frame(frame + offset, _context(frame + offset, action), false)
	suite.assert_true(result.ok and not result.hit_facts.is_empty(), "enrage preserves complete authored warning floor")
	if not result.hit_facts.is_empty():
		suite.assert_close(result.hit_facts[0].damage, float(action.hit_schedule[0].damage) * 1.20, "enrage uses authored damage multiplier")
	suite.assert_true(runtime.restore_snapshot(checkpoint), "enraged action restores exact pending next frame")


func _test_character_tail(suite: RefCounted, implementation: Script, definition: Dictionary, identity: Dictionary) -> void:
	var runtime: RefCounted = implementation.new()
	runtime.configure(definition, identity)
	runtime.add_control_source("stop:tail", "stop", 180, 1.0)
	suite.assert_true(runtime.extend_character_boss_exposure(1, 18), "Character tail binds actual Boss Stop exposure")
	var before: Dictionary = runtime.snapshot()
	for frame: int in range(1, 46):
		runtime.advance_frame(frame, Actions.context(frame), false)
	suite.assert_equal(runtime.snapshot().conversion.claims[0].remaining_frames, 18, "positive Character extension waits for actual base Stop exposure")
	runtime.advance_frame(46, Actions.context(46), false)
	suite.assert_true(runtime.is_exposed() and runtime.snapshot().conversion.claims[0].state == "active" and runtime.snapshot().conversion.claims[0].remaining_frames == 18, "Character tail activates at first accepted frame after original window")
	var activated: Dictionary = runtime.snapshot()
	suite.assert_true(runtime.add_control_source("stop:tail-second", "stop", 180, 1.0), "new real Stop source preserves a pending Character tail")
	var suspended: Dictionary = runtime.snapshot()
	suite.assert_true(suspended.conversion.claims[0].state == "pending" and runtime.can_restore_snapshot(suspended), "new Stop immediately suspends active Character tail before frame preparation")
	suite.assert_true(runtime.restore_snapshot(activated), "actual pending-tail compensation restores prior active state")
	for frame: int in range(47, 65):
		runtime.advance_frame(frame, Actions.context(frame), false)
	suite.assert_true(not runtime.is_exposed() and runtime.snapshot().conversion.claims.is_empty(), "eighteen accepted frames expire eighteen-frame Character tail")
	suite.assert_true(runtime.restore_snapshot(activated), "complete hostile rollback restores active Character countdown")
	var forged := activated.duplicate(true)
	forged.conversion.claims[0].remaining_frames = 31
	suite.assert_true(not runtime.restore_snapshot(forged) and runtime.snapshot() == activated, "forged Character duration refuses without partial restoration")
	suite.assert_true(runtime.restore_snapshot(before), "complete hostile rollback restores pre-countdown pending Character state")


func _test_long_damage_history(suite: RefCounted, implementation: Script, definition: Dictionary, identity: Dictionary) -> void:
	var runtime: RefCounted = implementation.new()
	runtime.configure(definition, identity)
	for frame: int in range(1, 515):
		var hp := float(runtime.snapshot().mechanism_state.hp_current) - 0.1
		var fact := {"fact_id": "accepted-hit:%d" % frame, "runtime_frame": frame, "target_source_id": identity.hostile_source_id, "amount": 0.1, "hp_after": hp}
		suite.assert_true(runtime.accept_damage_fact(fact).ok, "long Boss battle cannot exhaust damage acceptance: " + definition.id)
		runtime.advance_frame(frame, Actions.context(frame), false)
	var before: Dictionary = runtime.snapshot()
	suite.assert_equal(before.mechanism_state.damage_claims.size(), 512, "Boss hit history stays bounded through long accepted battle")
	suite.assert_true(runtime.can_restore_snapshot(before), "bounded long-battle damage checkpoint remains strict and restorable")
	var old := {"fact_id": "accepted-hit:1", "runtime_frame": 1, "target_source_id": identity.hostile_source_id, "amount": 0.1, "hp_after": float(before.mechanism_state.hp_current) - 0.1}
	suite.assert_true(not runtime.accept_damage_fact(old).ok and runtime.snapshot() == before, "evicted historical damage identity cannot cross accepted-frame boundary")


func _test_weapon_source_lifetime(suite: RefCounted, implementation: Script, definition: Dictionary, identity: Dictionary) -> void:
	var runtime: RefCounted = implementation.new()
	runtime.configure(definition, identity)
	var action: Dictionary = definition.actions[0]
	runtime.request_action(action.id, _context(0, action))
	var frame := int(action.warning_frames) + int(action.active_frames)
	for next: int in range(1, frame + 1):
		runtime.advance_frame(next, _context(next, action), false)
	suite.assert_true(runtime.apply_weapon_control_conversion("poise:claim", 0, 0, float(definition.phases[0].poise_threshold)), "actual recovery converts threshold poise into positive exposure")
	suite.assert_equal(runtime.snapshot().conversion.weapon_sources[0].expires_through_frame, frame + 45, "poise source lifetime covers its entire final granted window")
	for next: int in range(frame + 1, frame + 3):
		runtime.advance_frame(next, _context(next, action), false)
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.apply_weapon_control_conversion("poise:claim", 0, 0, float(definition.phases[0].poise_threshold)) and runtime.snapshot() == before, "same poise source cannot reenter while its actual grant remains live")


func _context(frame: int, action: Dictionary) -> Dictionary:
	var result := Actions.context(frame)
	result.source_position = {"x": 100.0, "y": 100.0}
	result.target_position = {"x": 100.0 + maxf(float(action.distance_min_px), minf(40.0, float(action.distance_max_px))), "y": 100.0}
	return result
