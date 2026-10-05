extends RefCounted

const Store := preload("res://scripts/replay/run_replay_stream_store.gd")
const Codec := preload("res://scripts/replay/run_replay_chunk_codec.gd")


func run(storage: RefCounted, samples: Array[Dictionary], count: int) -> Dictionary:
	if not storage is Store or samples.is_empty() or samples.size() > Codec.MAX_OBSERVATIONS or count < 1 or count > Store.MAX_OBSERVATIONS:
		return _failure(&"REPLAY_BUDGET_INPUT_INVALID")
	var identity: Dictionary = samples[0].get("player", {}).get("identity", {})
	for sample: Dictionary in samples:
		if not Codec._safe(sample) or sample.get("player", {}).get("identity", {}) != identity:
			return _failure(&"REPLAY_BUDGET_INPUT_INVALID")
	var begun: Dictionary = storage.begin(identity, int(samples[0].get("run", {}).get("run_seed", 0)))
	if not begun.ok:
		return begun
	var id: String = begun.context.id
	var start := Time.get_ticks_usec()
	var commit_ms: Array[float] = []
	var first: Dictionary = {}
	var last: Dictionary = {}
	var sequence := 0
	while sequence < count:
		var batch: Array[Dictionary] = []
		for _index: int in range(mini(Codec.MAX_OBSERVATIONS, count - sequence)):
			# Repetition measures physical storage; it is never a gameplay tape.
			var sample := samples[sequence % samples.size()].duplicate(true)
			sample.sequence = sequence
			batch.append(sample)
			if sequence == 0:
				first = sample.duplicate(true)
			last = sample.duplicate(true)
			sequence += 1
		var write_start := Time.get_ticks_usec()
		var appended: Dictionary = storage.append(id, batch)
		commit_ms.append(float(Time.get_ticks_usec() - write_start) / 1000.0)
		if not appended.ok:
			storage.finish(id, "FAILED")
			return _failure(appended.code, {"observations_before_failure": sequence - batch.size()})
		if sequence % 12000 == 0:
			print("REPLAY_BUDGET_PROGRESS ", sequence, "/", count)
	var finished: Dictionary = storage.finish(id, "INTERRUPTED")
	if not finished.ok:
		return finished
	for expected: Dictionary in [first, last]:
		var read: Dictionary = storage.read(id, int(expected.sequence))
		if not read.ok or var_to_bytes(read.context.observation) != var_to_bytes(expected):
			return _failure(&"REPLAY_BUDGET_EXACT_SEEK_FAILED")
	var row: Dictionary = {}
	for entry: Dictionary in storage.rows():
		if entry.id == id:
			row = entry
	if row.is_empty() or int(row.observation_count) != count:
		return _failure(&"REPLAY_BUDGET_COUNT_INVALID")
	commit_ms.sort()
	var total_ms := float(Time.get_ticks_usec() - start) / 1000.0
	var report := {
		"schema_version": 1,
		"classification": "synthetic_repeated_native_samples",
		"observations": count,
		"source_sample_count": samples.size(),
		"compressed_bytes": row.compressed_bytes,
		"run_byte_limit": Store.MAX_RUN_BYTES,
		"chunks": commit_ms.size(),
		"elapsed_ms": total_ms,
		"average_ms_per_observation": total_ms / float(count),
		"commit_p95_ms": commit_ms[mini(commit_ms.size() - 1, int(ceil(float(commit_ms.size()) * 0.95)) - 1)],
		"commit_max_ms": commit_ms[-1],
		"peak_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"first_sha256": Codec.byte_digest(var_to_bytes(first)),
		"last_sha256": Codec.byte_digest(var_to_bytes(last)),
		"gameplay_completion_certified": false,
	}
	return {"ok": true, "code": &"OK", "context": {"report": report}}


static func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context}
