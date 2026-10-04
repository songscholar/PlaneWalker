class_name MusicDirector
extends Node

const ROOT := "res://assets/production/music/"
const FADE_SECONDS := 0.6
const FLOOR_CUES := ["music_ruins_of_remnant", "music_void_forest", "music_time_rift", "music_plane_forge", "music_throne_of_void"]
const BOSS_CUES := ["music_boss_ruin_king", "music_boss_forest_heart", "music_boss_time_sovereign", "music_boss_forge_colossus", "music_boss_void_throne"]
const OTHER_CUES := ["music_hub", "music_training", "music_credits", "music_victory", "music_defeat"]
var _source: Callable
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _gains := [0.0, 0.0]
var _start_gains := [0.0, 0.0]
var _target_gains := [0.0, 0.0]
var _cue_id := ""
var _active_deck := 1
var _fade_clock := FADE_SECONDS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index: int in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "MusicDeck%d" % index
		player.bus = &"Music"
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)


func configure(source: Callable) -> bool:
	if not is_node_ready() or not source.is_valid() or _source.is_valid() or AudioServer.get_bus_index(&"Music") < 0:
		return false
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	if not manifest is Dictionary or manifest.get("schema_id") != "plane_walker_original_music_v1" or manifest.get("schema_version") != 1 or not manifest.get("cues") is Array or manifest.cues.size() != 15:
		return false
	var streams: Dictionary = {}
	for row: Variant in manifest.cues:
		if not row is Dictionary or row.get("id") not in FLOOR_CUES + BOSS_CUES + OTHER_CUES or streams.has(row.id) or row.get("path") != str(row.id) + ".wav" or row.get("sample_rate") != 22050 or row.get("channels") != 2 or row.get("loop_begin") != 0 or typeof(row.get("frames")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(row.frames)) or float(row.frames) != floor(float(row.frames)) or int(row.frames) < 22050 or row.get("loop_end") != row.frames:
			return false
		if not ResourceLoader.exists(ROOT + row.path, "AudioStreamWAV"):
			return false
		var original := load(ROOT + row.path) as AudioStreamWAV
		if original == null or not original.stereo or original.mix_rate != 22050 or original.format not in [AudioStreamWAV.FORMAT_16_BITS, AudioStreamWAV.FORMAT_QOA] or original.data.is_empty() or absf(original.get_length() * original.mix_rate - int(row.frames)) >= 1.0:
			return false
		var stream := original.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(row.frames)
		streams[row.id] = stream
	_streams = streams
	_source = source
	return true


func _process(delta: float) -> void:
	if not _source.is_valid() or not is_finite(delta) or delta < 0.0:
		return
	var context: Variant = _source.call()
	if not context is Dictionary or not context.get("cue_id") is String or not context.get("paused") is bool:
		return
	var paused: bool = context.paused
	for player: AudioStreamPlayer in _players:
		player.stream_paused = paused
	if paused:
		return
	if context.cue_id != _cue_id and _streams.has(context.cue_id):
		_active_deck = 1 - _active_deck
		var selected: AudioStreamPlayer = _players[_active_deck]
		selected.stop()
		_gains[_active_deck] = 0.0
		selected.volume_db = -80.0
		selected.stream = _streams[context.cue_id]
		selected.play()
		_cue_id = context.cue_id
		_start_gains = _gains.duplicate()
		_target_gains = [0.0, 0.0]
		_target_gains[_active_deck] = 1.0
		_fade_clock = 0.0
	_fade_clock = minf(FADE_SECONDS, _fade_clock + minf(delta, 0.3))
	for index: int in range(2):
		_gains[index] = lerpf(float(_start_gains[index]), float(_target_gains[index]), _fade_clock / FADE_SECONDS)
		_players[index].volume_db = linear_to_db(maxf(0.0001, float(_gains[index])))
		if _fade_clock == FADE_SECONDS and _target_gains[index] == 0.0:
			_players[index].stop()


func snapshot() -> Dictionary:
	var paused: Array = []
	var playing: Array = []
	var loops_valid := not _streams.is_empty()
	for player: AudioStreamPlayer in _players:
		paused.append(player.stream_paused)
		playing.append(player.playing)
	for stream: AudioStreamWAV in _streams.values():
		loops_valid = loops_valid and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and absf(stream.loop_end - stream.get_length() * stream.mix_rate) < 1.0
	return {"cue_id": _cue_id, "gains": _gains.duplicate(), "paused": paused, "playing": playing, "loops_valid": loops_valid}


func _exit_tree() -> void:
	_source = Callable()
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.stream = null
	_streams.clear()
