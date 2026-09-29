class_name CombatAudioSynth
extends Node

const MIX_RATE := 22050
const VOICE_COUNT := 8

const CUE_DEFINITIONS := {
	&"sword_swing": {"duration": 0.09, "start_hz": 760.0, "end_hz": 310.0, "gain": 0.28, "wave": "square", "noise": 0.08},
	&"sword_finisher": {"duration": 0.13, "start_hz": 620.0, "end_hz": 140.0, "gain": 0.38, "wave": "square", "noise": 0.16},
	&"sword_heavy": {"duration": 0.17, "start_hz": 340.0, "end_hz": 72.0, "gain": 0.46, "wave": "saw", "noise": 0.22},
	&"hit_light": {"duration": 0.08, "start_hz": 520.0, "end_hz": 180.0, "gain": 0.34, "wave": "triangle", "noise": 0.30},
	&"hit_finisher": {"duration": 0.14, "start_hz": 430.0, "end_hz": 105.0, "gain": 0.48, "wave": "square", "noise": 0.38},
	&"hit_heavy": {"duration": 0.18, "start_hz": 240.0, "end_hz": 62.0, "gain": 0.58, "wave": "sine", "noise": 0.44},
	&"player_hurt": {"duration": 0.19, "start_hz": 170.0, "end_hz": 74.0, "gain": 0.48, "wave": "saw", "noise": 0.26},
	&"dash": {"duration": 0.10, "start_hz": 980.0, "end_hz": 420.0, "gain": 0.22, "wave": "triangle", "noise": 0.16},
	&"danger_windup": {"duration": 0.24, "start_hz": 180.0, "end_hz": 610.0, "gain": 0.23, "wave": "triangle", "noise": 0.04},
	&"boss_windup_low": {"duration": 0.32, "start_hz": 82.0, "end_hz": 210.0, "gain": 0.34, "wave": "square", "noise": 0.08},
	&"boss_windup_high": {"duration": 0.30, "start_hz": 360.0, "end_hz": 880.0, "gain": 0.27, "wave": "triangle", "noise": 0.04},
	&"boss_windup_void": {"duration": 0.38, "start_hz": 126.0, "end_hz": 48.0, "gain": 0.36, "wave": "saw", "noise": 0.13},
	&"time_stop": {"duration": 0.46, "start_hz": 620.0, "end_hz": 1180.0, "gain": 0.30, "wave": "sine", "noise": 0.02, "harmonic": 1.5},
	&"time_rewind": {"duration": 0.50, "start_hz": 960.0, "end_hz": 210.0, "gain": 0.32, "wave": "triangle", "noise": 0.05, "harmonic": 0.5},
	&"enemy_death": {"duration": 0.22, "start_hz": 260.0, "end_hz": 54.0, "gain": 0.34, "wave": "saw", "noise": 0.32},
}

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _cue_history: Array[StringName] = []
var _headless_playback_suppressed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless_playback_suppressed = DisplayServer.get_name().to_lower() == "headless"
	_build_library()
	for _index: int in range(VOICE_COUNT):
		var voice := AudioStreamPlayer.new()
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		voice.bus = &"SFX"
		add_child(voice)
		voice.finished.connect(_on_voice_finished.bind(voice))
		_voices.append(voice)


func play_cue(cue_id: StringName, intensity: float = 1.0) -> bool:
	if not _streams.has(cue_id) or _voices.is_empty():
		return false
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stop()
	voice.stream = _streams[cue_id]
	voice.volume_db = linear_to_db(clampf(intensity, 0.05, 1.0))
	if not _headless_playback_suppressed:
		voice.play()
	_cue_history.append(cue_id)
	if _cue_history.size() > 32:
		_cue_history.pop_front()
	return true


func get_contract_snapshot() -> Dictionary:
	var cues := {}
	for cue_id: StringName in _streams.keys():
		var stream := _streams[cue_id] as AudioStreamWAV
		cues[cue_id] = {
			"mix_rate": stream.mix_rate,
			"data_bytes": stream.data.size(),
			"fingerprint": _fingerprint(stream.data),
			"duration": float(CUE_DEFINITIONS[cue_id]["duration"]),
		}
	return {
		"mix_rate": MIX_RATE,
		"bus": &"SFX",
		"headless_playback_suppressed": _headless_playback_suppressed,
		"voice_count": _voices.size(),
		"active_voice_count": _active_voice_count(),
		"assigned_stream_count": _assigned_stream_count(),
		"cues": cues,
		"history": _cue_history.duplicate(),
	}


func clear_history() -> void:
	stop_all()
	_cue_history.clear()


func stop_all() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
		voice.stream = null


func _exit_tree() -> void:
	stop_all()
	_streams.clear()


func _on_voice_finished(voice: AudioStreamPlayer) -> void:
	if voice != null and is_instance_valid(voice):
		voice.stream = null


func _active_voice_count() -> int:
	var count := 0
	for voice: AudioStreamPlayer in _voices:
		if voice.playing:
			count += 1
	return count


func _assigned_stream_count() -> int:
	var count := 0
	for voice: AudioStreamPlayer in _voices:
		if voice.stream != null:
			count += 1
	return count


func _build_library() -> void:
	_streams.clear()
	for cue_id: StringName in CUE_DEFINITIONS.keys():
		_streams[cue_id] = _build_stream(CUE_DEFINITIONS[cue_id], cue_id)


func _build_stream(definition: Dictionary, cue_id: StringName) -> AudioStreamWAV:
	var duration := maxf(0.04, float(definition["duration"]))
	var sample_count := maxi(1, roundi(duration * MIX_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	var noise_state: int = 0x45D9F3B ^ hash(cue_id)
	for sample_index: int in range(sample_count):
		var progress := float(sample_index) / float(maxi(1, sample_count - 1))
		var frequency := lerpf(float(definition["start_hz"]), float(definition["end_hz"]), progress)
		phase = fmod(phase + frequency / MIX_RATE, 1.0)
		noise_state = int((noise_state * 1103515245 + 12345) & 0x7fffffff)
		var noise_sample := float(noise_state % 65536) / 32767.5 - 1.0
		var tonal := _wave_sample(str(definition["wave"]), phase)
		if definition.has("harmonic"):
			tonal = tonal * 0.72 + sin(TAU * phase * float(definition["harmonic"])) * 0.28
		var attack := minf(1.0, progress / 0.08)
		var release := pow(1.0 - progress, 1.8)
		var envelope := attack * release
		var noise_mix := clampf(float(definition.get("noise", 0.0)), 0.0, 0.8)
		var sample := (tonal * (1.0 - noise_mix) + noise_sample * noise_mix) * envelope * float(definition["gain"])
		_write_sample_16(data, sample_index, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream


func _wave_sample(wave: String, phase: float) -> float:
	match wave:
		"square":
			return 1.0 if phase < 0.5 else -1.0
		"triangle":
			return 1.0 - 4.0 * absf(phase - 0.5)
		"saw":
			return phase * 2.0 - 1.0
		_:
			return sin(TAU * phase)


func _write_sample_16(data: PackedByteArray, sample_index: int, sample: float) -> void:
	var value := clampi(roundi(clampf(sample, -1.0, 1.0) * 32767.0), -32768, 32767)
	if value < 0:
		value += 65536
	data[sample_index * 2] = value & 0xff
	data[sample_index * 2 + 1] = (value >> 8) & 0xff


func _fingerprint(data: PackedByteArray) -> int:
	var result: int = 2166136261
	var stride := maxi(1, data.size() / 128)
	for index: int in range(0, data.size(), stride):
		result = int((result ^ int(data[index])) * 16777619)
	return result
