extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const EnemyScene := preload("res://scenes/enemies/enemy_tank.tscn")
const SESSION_PATH := "res://scripts/replay/player_replay_view_session.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(SESSION_PATH), "isolated player replay viewing session must exist")
	if not ResourceLoader.exists(SESSION_PATH):
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "viewing fixture loads actual launch content")
	var replay := await Fixture.record(self, registry, suite, "view-session", 803)
	var original := replay.duplicate(true)
	var live_enemy := EnemyScene.instantiate()
	add_child(live_enemy)
	live_enemy.process_mode = Node.PROCESS_MODE_DISABLED
	live_enemy.set_physics_process(false)
	var live_before: Dictionary = live_enemy.get("_time_stop_sources").duplicate(true)
	var global_facts: Array = []
	var global_observer := func(ability_id: StringName, _token: int, _generation: int, _frame: int, _run_id: StringName, _context: Dictionary): global_facts.append(ability_id)
	EventBus.time_skill_committed.connect(global_observer)
	var unsafe := await Fixture.spawn(self, registry, suite, "view-session", 803)
	suite.assert_true(not load(SESSION_PATH).new().configure(replay, unsafe).ok, "disabled Player in a shared world is not an isolated viewing target")
	unsafe.queue_free()
	await get_tree().process_frame
	var target := await Fixture.spawn(self, registry, suite, "view-session", 803, true)
	var session: RefCounted = load(SESSION_PATH).new()
	var configured: Dictionary = session.configure(replay, target)
	suite.assert_true(configured.ok, "actual independent Player is bound to replay viewing")
	if configured.ok:
		suite.assert_true(session.seek(3).ok, "native Player seeks forward to a physical snapshot")
		suite.assert_equal(target.full_player_replay_snapshot(), replay.frames[3].snapshot, "seek verifies exact original state")
		suite.assert_true(session.seek(0).ok, "native Player seeks backward")
		var before: Dictionary = target.full_player_replay_snapshot()
		var cursor: Dictionary = session.snapshot()
		suite.assert_true(not session.seek(999).ok, "out-of-range seek refuses")
		suite.assert_equal(target.full_player_replay_snapshot(), before, "rejected seek leaves actual Player unchanged")
		suite.assert_equal(session.snapshot(), cursor, "rejected seek leaves cursor unchanged")
		var played: Dictionary = session.play_to_terminal()
		suite.assert_true(played.ok, "actual movement and time actions replay deterministically: " + str(played))
		suite.assert_equal(target.full_player_replay_snapshot(), replay.frames[-1].snapshot, "verified playback reaches exact terminal Player state")
		suite.assert_equal(replay, original, "viewing never mutates the recording")
		suite.assert_equal(live_enemy.get("_time_stop_sources"), live_before, "replay Stop and seek cannot freeze a live enemy in the same SceneTree")
		suite.assert_equal(global_facts, [], "replay time facts never publish into live gameplay observers")
		target.process_mode = Node.PROCESS_MODE_INHERIT
		suite.assert_true(not session.seek(0).ok, "a target returned to live processing cannot be controlled by viewing")
		target.process_mode = Node.PROCESS_MODE_DISABLED
		target.get_parent().queue_free()
		await get_tree().process_frame
		suite.assert_true(not session.seek(0).ok, "freed viewing targets reject safely")
	else:
		target.get_parent().queue_free()
		await get_tree().process_frame
	var divergent := replay.duplicate(true)
	divergent.frames[2].snapshot.player_state.position += Vector2(13, 0)
	divergent.frames[2].digest = Recorder.full_player_frame_digest(divergent.frames[2])
	divergent.terminal_digest = Recorder.full_player_terminal_digest(divergent)
	var verification_target := await Fixture.spawn(self, registry, suite, "view-session", 803, true)
	var verifier: RefCounted = load(SESSION_PATH).new()
	suite.assert_true(verifier.configure(divergent, verification_target).ok and verifier.seek(0).ok, "rehashed trajectory is structurally valid for actual execution verification")
	var verification_before: Dictionary = verification_target.full_player_replay_snapshot()
	var cursor_before: Dictionary = verifier.snapshot()
	var drift: Dictionary = verifier.play_to_terminal()
	suite.assert_true(not drift.ok, "actual Player execution detects rehashed trajectory divergence")
	suite.assert_equal(drift.context.index, 2, "playback reports first diverging frame")
	suite.assert_equal(verification_target.full_player_replay_snapshot(), verification_before, "divergence rolls actual Player back atomically")
	suite.assert_equal(verifier.snapshot(), cursor_before, "divergence preserves viewing cursor")
	suite.assert_equal(live_enemy.get("_time_stop_sources"), live_before, "divergence rollback cannot change third-party live actors")
	suite.assert_equal(global_facts, [], "failed playback cannot leak global gameplay facts")
	verification_target.get_parent().queue_free()
	live_enemy.queue_free()
	EventBus.time_skill_committed.disconnect(global_observer)
	await get_tree().process_frame
	suite.finish(get_tree())
