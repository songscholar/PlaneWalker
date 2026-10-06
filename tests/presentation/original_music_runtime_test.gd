extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Retirement := preload("res://tests/support/audio_playback_retirement.gd")
var _context := {"cue_id": "music_hub", "paused": false}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var source := load("res://scripts/audio/music_director.gd") as Script
	suite.assert_true(source != null, "original music has a native presentation director")
	if source == null:
		suite.finish(get_tree())
		return
	var director: Node = source.new()
	add_child(director)
	suite.assert_true(director.configure(func(): return _context.duplicate(true)), "director accepts a read-only cue source")
	director.set_process(false)
	director._process(0.3)
	suite.assert_equal(director.snapshot().cue_id, "music_hub", "Hub music is selected")
	var decoded: Array = []
	var descriptor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/production/music/manifest.json"))
	for row: Dictionary in descriptor.cues:
		var stream := load("res://assets/production/music/" + row.path) as AudioStreamWAV
		suite.assert_true(stream != null and stream.stereo and stream.mix_rate == 22050 and stream.data.size() > 0, "actual imported WAV decodes: " + row.id)
		decoded.append(row.id)
	_context.cue_id = "music_boss_ruin_king"
	director._process(0.2)
	var fading: Dictionary = director.snapshot()
	suite.assert_true(fading.gains[0] > 0.0 and fading.gains[1] > 0.0, "two decks crossfade without stopping the outgoing cue")
	_context.paused = true
	director._process(0.4)
	suite.assert_equal(director.snapshot().gains, fading.gains, "pause freezes the crossfade presentation clock")
	suite.assert_equal(director.snapshot().paused, [true, true], "pause freezes both audio players")
	_context.paused = false
	_context.cue_id = "music_training"
	director._process(0.3)
	director._process(0.3)
	suite.assert_equal(director.snapshot().cue_id, "music_training", "a new cue can interrupt the preceding crossfade")
	suite.assert_equal(director.snapshot().playing.count(true), 1, "completed crossfade retires its silent player")
	suite.assert_true(director.snapshot().loops_valid, "native streams loop through their complete PCM frames")
	_context.cue_id = "invalid_cue"
	director._process(0.3)
	suite.assert_equal(director.snapshot().cue_id, "music_training", "unknown cue cannot replace an authenticated stream")
	director.queue_free()
	await get_tree().process_frame
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var actual := main.get_node_or_null("MusicDirector")
	suite.assert_true(actual != null, "actual Main owns the soundtrack lifecycle")
	if actual != null:
		actual.set_process(false)
		actual._process(0.3)
		suite.assert_equal(actual.snapshot().cue_id, "music_hub", "actual Hub routes the Hub score")
		var training_revision: int = int(GameState.profile_runtime_service().snapshot().revision)
		suite.assert_true(main._start_hub_training(&"T-05", training_revision), "real Hub command opens the music fixture's practice session")
		actual._process(0.3)
		suite.assert_equal(actual.snapshot().cue_id, "music_training", "actual independent practice selects its training score")
		suite.assert_true(main.get_node("TrainingFlow").close().ok, "actual training closes before the music fixture Launch")
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261005}
		suite.assert_true(main._launch_run(config, false, true), "music fixture starts one actual Launch")
		main.set_process(false)
		var host: Node = main.get_node("RunRuntimeHost")
		host.set_process(false)
		var player: Node = main.get_node("CombatRoom01/Player")
		player.set_physics_process(false)
		player.get_node("TimeManager").set_process(false)
		player.get_node("RewindRecorder").set_process(false)
		main.get_node("TutorialFlow").set_process(false)
		var before: Dictionary = player.full_player_replay_snapshot()
		var run_before: Dictionary = host.runtime_snapshot()
		var profile_before: Dictionary = GameState.profile_runtime_service().snapshot()
		var bus_volume := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
		actual._process(0.3)
		suite.assert_equal(actual.snapshot().cue_id, "music_ruins_of_remnant", "actual first-floor gateway selects its authoritative music cue")
		get_tree().paused = true
		actual._process(0.3)
		suite.assert_equal(actual.snapshot().paused, [true, true], "actual dungeon pause suspends soundtrack")
		get_tree().paused = false
		actual._process(0.3)
		suite.assert_equal(player.full_player_replay_snapshot(), before, "music cannot change the full native Player replay")
		suite.assert_equal(host.runtime_snapshot(), run_before, "music cannot change any Run field")
		suite.assert_equal(GameState.profile_runtime_service().snapshot(), profile_before, "music cannot write Profile facts")
		suite.assert_equal(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), bus_volume, "soundtrack leaves the accessibility volume authority unchanged")
	var playback_refs: Array[WeakRef] = []
	for deck: Node in main.get_node("MusicDirector").get_children():
		if deck is AudioStreamPlayer and deck.playing and deck.get_stream_playback() != null:
			playback_refs.append(weakref(deck.get_stream_playback()))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_true(await Retirement.await_release(get_tree(), playback_refs), "actual Main audio retirement finishes within the wall-time deadline")
	suite.assert_true(playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null), "Main releases independent music playback before exit")
	suite.finish(get_tree())
