extends Node

const Main := preload("res://scenes/main.tscn")
const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Store := preload("res://scripts/replay/run_replay_stream_store.gd")
const Route := preload("res://tests/support/native_launch_route_fixture.gd")
const SURVIVAL := &"native_performance_survival_fixture"

var suite: RefCounted
var main: Node
var host: Node
var player: Node2D
var recorder: Node
var _retention_store: RefCounted
var _retention_id := ""
var report := {"schema_version": 1, "report_kind": "actual_native_main_performance", "status": "failed", "human_playtests": 0, "unassisted_victory": false, "fps_certified": false, "survival_fixture": str(SURVIVAL), "prerequisite_route_fixture": false, "rendered": false, "content_snapshot": {}, "requested_frames": 0, "accepted_frames": 0, "native_duration_ms": 0.0, "wall_duration_usec": 0, "sample_frames": {}, "metrics": {}, "render_wait": {"count": 0}, "observed_peak_counts": {"actors": 0, "summons": 0, "projectiles": 0, "zones": 0, "constructs": 0, "threats": 0}, "recording": {}, "hub": {}, "failures": []}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	report.requested_frames = _option("FRAMES", 600)
	report.rendered = OS.get_environment("PLANEWALKER_PERFORMANCE_RENDERED") == "true" and DisplayServer.get_name() != "headless"
	var registry := Registry.new()
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	_check(not loaded.has_blocking_errors(), "actual authoritative Base content loads")
	report.content_snapshot = Content.snapshot(registry)
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var save := Save.new()
	_check(save.configure(GameState.save_path.get_base_dir().path_join("plane_walker/save"), "0.4.0-dev", report.content_snapshot).ok and save.enable_meta_profile(catalog).ok and save.save_profile("slot_1", "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "physical unlocked Profile fixture persists before Main")
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	await _hub()
	var started: bool = main._launch_run({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "accelerate"], "difficulty": "normal", "seed": 4}, false, true)
	_check(started, "production Main launches actual native Run")
	host = main.get_node("RunRuntimeHost")
	player = main.get_node("CombatRoom01/Player")
	recorder = main.get_node("NativeRunReplayRecorder")
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	main.get_node("CombatRoom01").visible = true
	main.get_node("CombatRoom01").process_mode = Node.PROCESS_MODE_PAUSABLE
	var old_ticks := Engine.physics_ticks_per_second
	var old_scale := Engine.time_scale
	var old_fps := Engine.max_fps
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_fps = 0
	report["scheduler"] = {"physics_ticks_per_second": 60, "time_scale": Engine.time_scale, "native_hz": 60, "wall_accelerated": OS.get_environment("PLANEWALKER_PERFORMANCE_WALL_ACCELERATED") == "true"}
	if started and await _stage_room(_option("BOSS_FLOOR", -1)):
		host.set_dungeon_selection_safety(false)
		player.health.acquire_invulnerability_source(SURVIVAL)
		if await _reach_phase(_option("PHASE", 0)):
			_check(recorder.finish("INTERRUPTED").ok and recorder.start(true).ok, "phase admission ends before independent measured tape begins")
			await _measure()
	Engine.physics_ticks_per_second = old_ticks
	Engine.time_scale = old_scale
	Engine.max_fps = old_fps
	await _dispose()
	if _retention_store != null:
		var reloaded: Dictionary = _retention_store.reload()
		_check(reloaded.ok, "retired recorder's durable manifest reloads")
		report.recording.status = retained_recording_status(_retention_store, _retention_id) if reloaded.ok else "UNAVAILABLE"
	report.status = "pass" if report.failures.is_empty() and report.accepted_frames == report.requested_frames else "failed"
	var output := OS.get_environment("PLANEWALKER_PERFORMANCE_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	_check(file != null, "physical metric report opens")
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	suite.finish(get_tree())


func _hub() -> void:
	var flow: Node = main.get_node("HubFlowCoordinator")
	var started := Time.get_ticks_usec()
	var visited := 0
	for district: String in ["hub_council", "hub_craft", "hub_rift"]:
		_check(flow.travel(district).ok, "actual Hub district opens")
		for row: Dictionary in flow.view_state().functions:
			_check(flow.open_function(str(row.id)).ok, "actual Hub function opens")
			visited += 1
			await get_tree().process_frame
			flow.close_panel()
	var waits: Array[int] = []
	for _frame: int in range(_option("HUB_FRAMES", 120)):
		var before := Time.get_ticks_usec()
		await get_tree().process_frame
		if report.rendered:
			await RenderingServer.frame_post_draw
		waits.append(Time.get_ticks_usec() - before)
	report.hub = {"frames": waits.size(), "visited_functions": visited, "wall_duration_usec": Time.get_ticks_usec() - started, "scheduler_and_render_wait": _distribution(waits)}


func _stage_room(floor_index: int) -> bool:
	if floor_index > 0:
		report.prerequisite_route_fixture = true
		if not await Route.reach(main, suite, false, floor_index - 1, true):
			return _check(false, "declared prerequisite fixture reaches previous Boss boundary")
		if not host.start_next_floor(int(host.runtime_snapshot().revision)).ok:
			return _check(false, "actual floor handoff opens requested floor")
	for _step: int in range(40):
		var state: Dictionary = host.runtime_snapshot()
		var node: Dictionary = host.native_run_state().current_floor_node()
		if not state.open_offer.is_empty():
			var offer: Dictionary = state.open_offer
			host._on_option_chosen(str(offer.offer_id), str(offer.options[0].option_id), int(offer.revision))
		elif node.id == state.floor_plan.entry_node_id or node.cleared:
			var choices: Array = host.route_choices()
			if choices.is_empty():
				return _check(false, "requested actual route has a destination")
			var selected: Dictionary = choices[0]
			for candidate: Dictionary in choices:
				if candidate.room_type in ["combat", "elite", "boss"]:
					selected = candidate
					break
			if not host.select_route(StringName(selected.edge_id), int(state.revision)).ok:
				return _check(false, "actual route admission accepts")
		elif floor_index < 0 and node.room_type in ["combat", "elite"] or floor_index >= 0 and node.room_type == "boss":
			main.get_node("NarrativeFlow").close()
			Route.freeze(main)
			if recorder.snapshot().active:
				_check(recorder.finish("INTERRUPTED").ok, "prerequisite tape stays explicitly incomplete")
			_check(recorder.start(true).ok, "actual selected native encounter starts independent recorder")
			report["encounter"] = {"floor_index": int(state.current_floor_index), "node_id": str(node.id), "room_type": str(node.room_type)}
			return report.failures.is_empty()
		else:
			report.prerequisite_route_fixture = true
			var result: Variant
			match node.room_type:
				"shop": result = host.leave_merchant(int(state.revision))
				"event": result = host.choose_event_option(&"decline", int(state.revision)) if host.dungeon_ui_context().event.phase == "open" else host.dismiss_event(int(state.revision))
				"treasure", "rest": result = host.resolve_room_interaction(&"leave", int(state.revision))
				_: result = host.native_checkpoint_participants().runtime.complete_current_room()
			if not result.ok:
				return _check(false, "declared route prerequisite progresses")
		main.get_node("DungeonFlow").refresh(true)
		Route.freeze(main)
		await get_tree().process_frame
		main.get_node("NarrativeFlow").close()
	return _check(false, "requested encounter lies within bounded route")


func _reach_phase(target: int) -> bool:
	if target == 0:
		return true
	var pressed := -1
	for frame: int in range(16000):
		var driver: Node = main.get_node("CombatRoom01").encounter_runner().get_node("NativeLaunchEncounterDriver")
		var actors: Dictionary = driver.get("_actors")
		var boss: Node2D
		for actor: Node2D in actors.values():
			if actor.get("_launch_definition").actor_kind == "boss":
				boss = actor
		if boss != null:
			if int(boss.launch_runtime_snapshot().runtime.mechanism_state.phase_index) >= target:
				player.cancel_transient_actions()
				report["phase_admission_frames"] = frame
				return true
			var aim := player.global_position.direction_to(boss.global_position)
			var distance := player.global_position.distance_to(boss.global_position)
			if player.weapon_action_coordinator.phase_name() == &"READY" and player.action_state.current_state == 0 and player.try_action(&"weapon_primary"):
				pressed = frame
			if pressed >= 0 and frame - pressed >= 40:
				player.call("_submit_weapon_intent", &"weapon_primary", &"released")
				pressed = -1
			if not player.advance_action_frame({"aim": aim, "movement": aim if distance > 44.0 else -aim if distance < 34.0 else Vector2.ZERO}):
				return _check(false, "real Sword phase admission accepts every native frame")
		else:
			if not player.advance_action_frame():
				return _check(false, "actual Boss spawn advances")
		host._process(1.0 / 60.0)
		await get_tree().physics_frame
	return _check(false, "real Sword reaches requested authored HP phase")


func _measure() -> void:
	var timings := {"player_advance": [], "host_process": [], "physics_wait": [], "observer": []}
	var render_times: Array[int] = []
	var first: Dictionary = {}
	var last: Dictionary = {}
	var before_recorded: int = int(recorder.snapshot().observation_count)
	var previous_frame: int = int(player.priority_arbitration_snapshot().frame)
	var started := Time.get_ticks_usec()
	var peak_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for index: int in range(report.requested_frames):
		var before := Time.get_ticks_usec()
		var accepted: bool = player.advance_action_frame({"aim": Vector2.RIGHT, "movement": Vector2.ZERO})
		timings.player_advance.append(Time.get_ticks_usec() - before)
		if not accepted:
			_check(false, "actual measured native Player frame accepts")
			break
		before = Time.get_ticks_usec()
		host._process(1.0 / 60.0)
		timings.host_process.append(Time.get_ticks_usec() - before)
		before = Time.get_ticks_usec()
		await get_tree().physics_frame
		timings.physics_wait.append(Time.get_ticks_usec() - before)
		if report.rendered:
			before = Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			render_times.append(Time.get_ticks_usec() - before)
		before = Time.get_ticks_usec()
		last = recorder.latest_observation()
		var current: Dictionary = recorder.snapshot()
		if not current.active or not str(current.failure).is_empty() or int(last.get("player", {}).get("frame", -1)) != previous_frame + 1 or current.observation_count != before_recorded + index + 1:
			_check(false, "every accepted actual frame owns one unique automatic observation")
			break
		previous_frame += 1
		if first.is_empty():
			first = last.duplicate(true)
		_counts()
		peak_memory = maxi(peak_memory, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
		timings.observer.append(Time.get_ticks_usec() - before)
		report.accepted_frames += 1
		if (index + 1) % 600 == 0:
			print("NATIVE_PERFORMANCE_PROGRESS ", index + 1, "/", report.requested_frames, " recorder=", current.committed_count, " buffered=", current.buffered_count)
	report.wall_duration_usec = Time.get_ticks_usec() - started
	report.native_duration_ms = float(report.accepted_frames) * 1000.0 / 60.0
	report["peak_native_static_bytes"] = peak_memory
	for key: String in timings:
		report.metrics[key] = _distribution(timings[key])
	if report.rendered:
		report.render_wait = _distribution(render_times)
	if not first.is_empty():
		report.sample_frames = {"first": int(first.player.frame), "last": int(last.player.frame), "unique_count": int(report.accepted_frames)}
		await _retain(first, last)


func _counts() -> void:
	var driver: Node = main.get_node("CombatRoom01").encounter_runner().get_node("NativeLaunchEncounterDriver")
	var effects: RefCounted = driver.get("_effects")
	var payload: Dictionary = effects.payload_snapshot()
	var observed := {"actors": driver.get("_actors").size(), "summons": effects.native_summon_actors().size(), "projectiles": payload.projectiles.size(), "zones": payload.zones.size() + effects.native_semantic_nodes().size(), "constructs": effects.native_construct_count(), "threats": main.get_node("CombatRoom01").hostile_threat_registry().snapshot().size()}
	for key: String in observed:
		report.observed_peak_counts[key] = maxi(int(report.observed_peak_counts[key]), int(observed[key]))


func _retain(first: Dictionary, last: Dictionary) -> void:
	var before := Time.get_ticks_usec()
	_check(recorder.flush().ok and recorder.finish("INTERRUPTED").ok, "actual independent tape physically flushes and stays incomplete")
	var identity: Dictionary = GameState.profile_runtime_service().local_record_storage_identity()
	var fresh := Store.new()
	_check(fresh.configure(recorder.storage_root(), "0.4.0-dev", identity.content_snapshot, identity.profile_id, identity.save_domain).ok, "fresh physical store loads the actual tape")
	_retention_store = fresh
	_retention_id = str(recorder.snapshot().id)
	var first_read: Dictionary = fresh.read(recorder.snapshot().id, int(first.sequence))
	var last_read: Dictionary = fresh.read(recorder.snapshot().id, int(last.sequence))
	var first_exact: bool = first_read.ok and var_to_bytes(first_read.context.observation) == var_to_bytes(first)
	var last_exact: bool = last_read.ok and var_to_bytes(last_read.context.observation) == var_to_bytes(last)
	_check(first_exact and last_exact, "physical first and last measured automatic samples are byte-exact")
	report.recording = {"status": retained_recording_status(fresh, _retention_id), "actual_sample_count": int(report.accepted_frames), "first_sha256": Store.Codec.byte_digest(var_to_bytes(first)), "last_sha256": Store.Codec.byte_digest(var_to_bytes(last)), "physical_first_exact": first_exact, "physical_last_exact": last_exact, "failure": str(recorder.snapshot().failure), "retention_usec": Time.get_ticks_usec() - before, "total_tape_observations": int(recorder.snapshot().observation_count)}


static func retained_recording_status(storage: RefCounted, id: String) -> String:
	for row: Dictionary in storage.rows():
		if str(row.id) == id:
			return str(row.status)
	return "UNAVAILABLE"


static func _distribution(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0
	for value: int in values:
		total += value
	return {"count": values.size(), "total_usec": total, "mean_usec": float(total) / values.size(), "p50_usec": ordered[maxi(0, int(ceil(values.size() * 0.5)) - 1)], "p95_usec": ordered[maxi(0, int(ceil(values.size() * 0.95)) - 1)], "maximum_usec": ordered[-1]}


func _check(condition: bool, message: String) -> bool:
	suite.assert_true(condition, message)
	if not condition:
		report.failures.append(message)
	return condition


static func _option(name: String, fallback: int) -> int:
	var value := OS.get_environment("PLANEWALKER_PERFORMANCE_" + name)
	return fallback if value.is_empty() else int(value)


func _dispose() -> void:
	var playback_refs: Array[WeakRef] = []
	for deck: Node in main.get_node("MusicDirector").get_children():
		if deck is AudioStreamPlayer and deck.playing and deck.get_stream_playback() != null:
			playback_refs.append(weakref(deck.get_stream_playback()))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for _step: int in range(20):
		if playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null):
			break
		# Fixed-fps advances simulation timers faster than the audio server's wall clock.
		OS.delay_msec(10)
		await get_tree().process_frame
	_check(playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null), "actual Main releases audio playback before exit")
