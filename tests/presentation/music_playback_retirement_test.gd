extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Director := preload("res://scripts/audio/music_director.gd")
const Retirement := preload("res://tests/support/audio_playback_retirement.gd")
var _context := {"cue_id": "music_hub", "paused": false}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var director := Director.new()
	add_child(director)
	suite.assert_true(director.configure(func(): return _context.duplicate(true)), "retirement fixture configures the production music director")
	director.set_process(false)
	director._process(0.3)
	_context.cue_id = "music_credits"
	director._process(0.2)
	var playback_refs: Array[WeakRef] = []
	for deck: Node in director.get_children():
		if deck is AudioStreamPlayer and deck.playing and deck.get_stream_playback() != null:
			playback_refs.append(weakref(deck.get_stream_playback()))
	var stream_refs: Array[WeakRef] = _stream_refs(director)
	suite.assert_equal(playback_refs.size(), 2, "retirement fixture begins during the actual two-deck crossfade")
	var started := Time.get_ticks_usec()
	director.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var retired: bool = await Retirement.await_release(get_tree(), playback_refs + stream_refs)
	print("MUSIC_RETIREMENT elapsed_usec=", Time.get_ticks_usec() - started, " valid_director=", is_instance_valid(director), " playbacks_live=", playback_refs.filter(func(reference: WeakRef): return reference.get_ref() != null).size(), " streams_live=", stream_refs.filter(func(reference: WeakRef): return reference.get_ref() != null).size())
	suite.assert_true(retired, "the bounded wall-time drain retires all actual playback and stream objects")
	suite.assert_true(playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null), "both production playback objects are released before exit")
	suite.assert_true(stream_refs.all(func(reference: WeakRef): return reference.get_ref() == null), "all private loop streams are released before exit")
	var retained := RefCounted.new()
	var retained_refs: Array[WeakRef] = [weakref(retained)]
	var timeout_started := Time.get_ticks_usec()
	suite.assert_true(not await Retirement.await_release(get_tree(), retained_refs, 2000), "a still-owned reference cannot be mistaken for a released playback")
	suite.assert_true(Time.get_ticks_usec() - timeout_started >= 2000, "a refusal waits for the real wall-time deadline")
	suite.assert_true(not Retirement.released(retained_refs), "the drain never clears or replaces the observed reference")
	retained = null
	suite.assert_true(await Retirement.await_release(get_tree(), retained_refs, 0), "an already released reference needs no wall-time delay")
	suite.finish(get_tree())


func _stream_refs(director: Node) -> Array[WeakRef]:
	var references: Array[WeakRef] = []
	for stream: AudioStreamWAV in director.get("_streams").values():
		references.append(weakref(stream))
	return references
