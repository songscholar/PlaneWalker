extends RefCounted

static var active := false
static var _stack: Array[String] = []
static var _samples: Dictionary = {}


static func start() -> void:
	_stack.clear()
	_samples.clear()
	active = true


static func enter(label: String) -> int:
	_stack.append(label)
	return Time.get_ticks_usec()


static func leave(started: int) -> void:
	var elapsed := Time.get_ticks_usec() - started
	var path := "/".join(_stack)
	if not _samples.has(path):
		_samples[path] = []
	_samples[path].append(elapsed)
	_stack.pop_back()


static func finish(frame_count: int) -> Dictionary:
	active = false
	var rows := {}
	for path: String in _samples:
		var values: Array = _samples[path].duplicate()
		values.sort()
		var total := 0
		for value: int in values:
			total += value
		rows[path] = {"calls": values.size(), "total_usec": total, "mean_call_usec": float(total) / maxi(1, values.size()), "p95_call_usec": values[maxi(0, ceili(values.size() * 0.95) - 1)], "mean_per_frame_usec": float(total) / maxi(1, frame_count)}
	return {"schema_version": 1, "instrumented": true, "purpose": "inclusive_main_thread_function_cpu_diagnostic", "sample_frames": frame_count, "stack_empty": _stack.is_empty(), "rows": rows}
