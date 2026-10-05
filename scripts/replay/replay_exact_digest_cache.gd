extends RefCounted

var _mutex := Mutex.new()
var _max_entries: int
var _max_source_bytes: int
var _entries: Dictionary = {}
var _order: Array[PackedByteArray] = []
var _source_bytes := 0
var _hits := 0
var _misses := 0


func _init(max_entries: int = 128, max_source_bytes: int = 16 * 1024 * 1024) -> void:
	_max_entries = maxi(0, max_entries)
	_max_source_bytes = maxi(0, max_source_bytes)


func lookup(source: PackedByteArray) -> String:
	_mutex.lock()
	var result: String = _entries.get(source, "")
	if result.is_empty():
		_misses += 1
	else:
		_hits += 1
	_mutex.unlock()
	return result


func store(source: PackedByteArray, digest: String) -> bool:
	if (
		_max_entries == 0 or source.size() > _max_source_bytes
		or not _is_sha256(digest)
	):
		return false
	_mutex.lock()
	if _entries.has(source):
		var matches: bool = _entries[source] == digest
		_mutex.unlock()
		return matches
	while _entries.size() >= _max_entries or _source_bytes + source.size() > _max_source_bytes:
		var retired: PackedByteArray = _order.pop_front()
		_entries.erase(retired)
		_source_bytes -= retired.size()
	# Packed bytes provide exact equality after the engine's dictionary hash lookup.
	var retained := source.duplicate()
	_entries[retained] = digest
	_order.append(retained)
	_source_bytes += retained.size()
	_mutex.unlock()
	return true


static func _is_sha256(digest: String) -> bool:
	if digest.length() != 64:
		return false
	for index: int in range(digest.length()):
		if "0123456789abcdef".find(digest.substr(index, 1)) < 0:
			return false
	return true


func clear() -> void:
	_mutex.lock()
	_entries.clear()
	_order.clear()
	_source_bytes = 0
	_hits = 0
	_misses = 0
	_mutex.unlock()


func snapshot() -> Dictionary:
	_mutex.lock()
	var result := {"entries": _entries.size(), "source_bytes": _source_bytes, "hits": _hits, "misses": _misses, "max_entries": _max_entries, "max_source_bytes": _max_source_bytes}
	_mutex.unlock()
	return result
