extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"

const Replay := preload("res://scripts/replay/replay_recorder.gd")


func _run() -> void:
	suite = Suite.new()
	var f := await _fixture("phase_ranger")
	f.player.global_position = Vector2(16000, 16000)
	var actor: Node2D = f.actors[0]
	actor.apply_time_rift(&"phase-start-rift", 0.4)
	for _frame: int in range(179):
		suite.assert_true(_step(f), "actual Ranger accepts native idle shift clock")
	var state: Dictionary = actor.launch_runtime_snapshot().runtime.mechanism_state
	suite.assert_true(state.has("phase_shift"), "native Phase Ranger owns authored shift mechanism state")
	if not state.has("phase_shift"):
		await _dispose(f)
		suite.finish(get_tree())
		return
	suite.assert_true(_step(f), "native Ranger reserves shift after complete one-hundred-eighty-frame cooldown")
	state = actor.launch_runtime_snapshot().runtime.mechanism_state
	suite.assert_true(state.phase_shift.phase == "DEPARTURE" and state.phase_shift.remaining_frames == 23 and state.phase_shift.reservations.size() == 1, "Ranger freezes a safe marked landing and complete floor-four warning")
	var origin := actor.global_position
	var landing: Dictionary = state.phase_shift.reservations[0].landing
	suite.assert_true(origin.distance_to(Vector2(float(landing.x), float(landing.y))) <= 80.001 and actor.get_node_or_null("PhaseArrival") != null, "actual Ranger shift respects distance cap and native arrival marker")
	await _capture_arrival(f)
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	var twin := await _fixture("phase_ranger")
	suite.assert_true(twin.actors[0].restore_native_cold_snapshot(Replay.decode_replay_json(Replay.encode_replay_json(cold).json).replay, func(_binding: Dictionary): return null), "typed cold Ranger restores frozen arrival marker and shift sequence")
	var forged := cold.duplicate(true)
	forged.actor.runtime.mechanism_state.phase_shift.reservations[0].landing.x += 1.0
	suite.assert_true(not twin.actors[0].can_restore_native_cold_snapshot(forged, func(_binding: Dictionary): return null), "noncanonical shifted landing cannot enter cold Actor")
	actor.apply_time_stop_source(&"phase-shift-stop", 10.0 / 60.0)
	for _frame: int in range(10):
		suite.assert_true(_step(f), "Stop accepts shared Ranger frame while freezing shift warning")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.mechanism_state.phase_shift, state.phase_shift, "Stop preserves complete marked arrival warning")
	suite.assert_true(actor.get("_launch_runtime").add_control_source("phase-shift-rift", "rift", 30, 0.4), "actual Rift applies during marked departure")
	for _frame: int in range(22):
		suite.assert_true(_step(f), "Ranger retains complete departure warning before relocation")
	suite.assert_equal(actor.global_position, origin, "Ranger cannot relocate before final warning frame")
	var before: Dictionary = actor.launch_transaction_snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(int(f.frame) + 1)
	suite.assert_true(f.bridge.prepare_frame(ticket) and actor.global_position != origin, "native arrival relocates only after full safe warning: " + str([actor.launch_runtime_snapshot().runtime.mechanism_state.phase_shift, actor.global_position, origin]))
	suite.assert_true(f.bridge.rollback_frame(ticket), "refused native shift restores complete shared participant")
	suite.assert_equal(actor.launch_transaction_snapshot(), before, "rejected shift preserves exact landing, clock, position, Health and generation")
	suite.assert_true(_step(f), "same-frame shift retry accepts identical frozen landing")
	state = actor.launch_runtime_snapshot().runtime.mechanism_state
	suite.assert_true(state.phase_shift.phase == "ARRIVAL" and state.phase_shift.remaining_frames == 30, "native arrival grants thirty vulnerable recovery frames: " + str(state.phase_shift))
	suite.assert_true(actor.health.take_damage(_phase_damage(f, 801, 20.0)) > 0.0, "actual Player weapon damage remains effective during shift recovery")
	f.player.global_position = actor.global_position + Vector2(-80, 0)
	for _frame: int in range(29):
		suite.assert_true(_step(f) and actor.launch_runtime_snapshot().runtime.action.phase == "IDLE", "Ranger recovery cannot attack or relocate")
	suite.assert_true(_step(f) and actor.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.phase == "IDLE" and actor.launch_runtime_snapshot().runtime.action.phase == "IDLE", "Ranger retains all thirty nonattacking recovery frames")
	suite.assert_true(_step(f) and actor.launch_runtime_snapshot().runtime.action.phase == "WARNING", "Ranger can resume an ordinary attack only after full recovery")
	await _dispose(f)
	await _dispose(twin)
	await _test_blocked_landing(false)
	await _test_blocked_landing(true)
	await _test_late_occupancy()
	await _test_busy_action()
	await _test_historical()
	await _test_teleporting_affix()
	suite.finish(get_tree())


func _phase_damage(f: Dictionary, generation: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": "run-summon-lifecycle", "target_id": str(f.actors[0].hostile_source_id), "hostile_source_id": "player:1", "attack_generation": generation, "action_token": generation, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "source": f.player, "attacker": f.player, "tags": ["weapon:sword"], "can_crit": false})


func _shift_fixture() -> Dictionary:
	var f := await _fixture("phase_ranger")
	f.player.global_position = Vector2(16000, 16000)
	for _frame: int in range(180):
		suite.assert_true(_step(f), "actual Ranger accepts complete first shift cooldown")
	return f


func _test_blocked_landing(static_wall: bool) -> void:
	var f := await _shift_fixture()
	var actor: Node2D = f.actors[0]
	var receipt: Dictionary = actor.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.reservations[0].duplicate(true)
	var origin := actor.global_position
	var destination := Vector2(float(receipt.landing.x), float(receipt.landing.y))
	var blocker: StaticBody2D
	if static_wall:
		blocker = StaticBody2D.new()
		blocker.collision_layer = 1
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.shape.radius = 16.0
		blocker.add_child(shape)
		add_child(blocker)
		blocker.global_position = destination
	else:
		f.player.global_position = destination
	await get_tree().physics_frame
	await get_tree().physics_frame
	for _frame: int in range(23):
		suite.assert_true(_step(f), "occupied marked landing retains accepted full warning")
	var shift: Dictionary = actor.launch_runtime_snapshot().runtime.mechanism_state.phase_shift
	suite.assert_true(shift.phase == "ARRIVAL" and shift.remaining_frames == 30 and shift.reservations[0].outcome == "BLOCKED" and shift.reservations[0].landing == receipt.landing and actor.global_position == origin, "new " + ("static wall" if static_wall else "Player occupancy") + " blocks frozen arrival without instant retargeting")
	if blocker != null:
		blocker.queue_free()
	await _dispose(f)


func _test_late_occupancy() -> void:
	var f := await _shift_fixture()
	var actor: Node2D = f.actors[0]
	for _frame: int in range(22):
		suite.assert_true(_step(f), "late occupancy fixture retains complete warning")
	var before: Dictionary = actor.launch_transaction_snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(int(f.frame) + 1)
	suite.assert_true(f.bridge.prepare_frame(ticket) and actor.global_position != Vector2(float(before.actor.position.x), float(before.actor.position.y)), "clear landing prepares native relocation")
	f.player.global_position = actor.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(f.bridge.prepare_frame_publication(ticket).is_empty(), "late Player occupancy refuses relocation before publication")
	suite.assert_true(f.bridge.rollback_frame(ticket) and actor.launch_transaction_snapshot() == before, "late arrival refusal restores exact species receipt, position and generation")
	suite.assert_true(_step(f) and actor.launch_runtime_snapshot().runtime.mechanism_state.phase_shift.reservations[0].outcome == "BLOCKED", "same frozen landing retries as blocked after accepted occupancy")
	await _dispose(f)


func _test_busy_action() -> void:
	var f := await _fixture("phase_ranger")
	f.player.global_position = Vector2(16000, 16000)
	f.actors[0].global_position += Vector2(16, 0)
	for _frame: int in range(179):
		suite.assert_true(_step(f), "busy fixture advances native shift cooldown")
	f.player.global_position = f.actors[0].global_position + Vector2(-80, 0)
	suite.assert_true(_start(f, "phase_ranger.phase_arrow"), "native real projectile action owns warning at shift due boundary")
	suite.assert_true(_step(f) and f.actors[0].launch_runtime_snapshot().runtime.mechanism_state.phase_shift.elapsed_frames == 179, "due shift cannot cancel or deadlock an existing projectile action")
	var reserved := false
	for _frame: int in range(90):
		suite.assert_true(_step(f), "ongoing projectile action reaches its accepted idle boundary")
		if not f.actors[0].launch_runtime_snapshot().runtime.mechanism_state.phase_shift.reservations.is_empty():
			reserved = true
			break
	suite.assert_true(reserved and f.actors[0].launch_runtime_snapshot().runtime.action.phase == "IDLE", "due shift receives next idle boundary before another action starts")
	await _dispose(f)


func _test_historical() -> void:
	var f := await _fixture("phase_ranger")
	var cold: Dictionary = f.actors[0].native_cold_snapshot(func(_source: Node): return {})
	cold.actor.runtime.schema_version = 1
	cold.actor.runtime.mechanism_state.erase("phase_shift")
	var malformed := cold.duplicate(true)
	malformed.actor.runtime.schema_version = 1.0
	suite.assert_true(not f.actors[0].can_restore_native_cold_snapshot(malformed, func(_binding: Dictionary): return null), "historical runtime migration refuses a floating schema number")
	suite.assert_true(f.actors[0].restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "exact historical native Ranger envelope normalizes explicitly")
	var shift: Dictionary = f.actors[0].launch_runtime_snapshot().runtime.mechanism_state.phase_shift
	f.player.global_position = Vector2(16000, 16000)
	for _frame: int in range(400):
		suite.assert_true(_step(f), "historical Ranger continues prior action/control behavior")
	suite.assert_true(not shift.enabled and f.actors[0].launch_runtime_snapshot().runtime.mechanism_state.phase_shift == shift and not f.actors[0].get_node("PhaseArrival").visible, "historical continuation never invents a shift or arrival marker")
	var disabled: Dictionary = f.actors[0].native_cold_snapshot(func(_source: Node): return {})
	disabled.actor.runtime.mechanism_state.phase_shift.elapsed_frames = 0.0
	suite.assert_true(not f.actors[0].can_restore_native_cold_snapshot(disabled, func(_binding: Dictionary): return null), "disabled historical shift retains strict integer counters")
	await _dispose(f)


func _capture_arrival(f: Dictionary) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		var center := Vector2i(f.actors[0].get_node("PhaseArrival").global_position * Vector2(pixels.get_size()) / Vector2(640, 360))
		var colors := {}
		var extent := ceili(16.0 * float(pixels.get_width()) / 640.0)
		for y: int in range(maxi(0, center.y - extent), mini(pixels.get_height(), center.y + extent)):
			for x: int in range(maxi(0, center.x - extent), mini(pixels.get_width(), center.x + extent)):
				colors[pixels.get_pixel(x, y).to_rgba32()] = true
		suite.assert_true(colors.size() >= 3, "native Phase arrival raster renders at " + str(resolution))
		var output := "res://build/visual-evidence/native-enemy-mechanisms/phase-arrival-%dx%d.png" % [resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "actual native Phase screenshot retains visual evidence")


func _test_teleporting_affix() -> void:
	var f := await _fixture("phase_ranger", 1, ["teleporting"])
	f.player.global_position = Vector2(16000, 16000)
	var accepted := true
	for _frame: int in range(900):
		if not _step(f):
			accepted = false
			break
	var species: Dictionary = f.actors[0].launch_runtime_snapshot().runtime.mechanism_state.phase_shift
	var affix: Dictionary = f.actors[0].launch_affix_runtime_snapshot().teleporting
	suite.assert_true(accepted and species.reservations.size() >= 3 and affix.reservations.size() >= 1 and species.reservations[0].outcome == "LANDED" and affix.reservations[0].outcome == "LANDED", "authored species and Teleporting affix clocks take safe turns without duplicate relocation or deadlock")
	await _dispose(f)
