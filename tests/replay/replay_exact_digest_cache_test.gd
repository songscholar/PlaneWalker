extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const CACHE_PATH := "res://scripts/replay/replay_exact_digest_cache.gd"
const DIGEST := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(CACHE_PATH), "bounded exact-source positive cache exists")
	if not ResourceLoader.exists(CACHE_PATH):
		suite.finish(get_tree())
		return
	var cache_script: GDScript = load(CACHE_PATH)
	var cache: RefCounted = cache_script.new(2, 128)
	var first := PackedByteArray([1, 2, 3])
	var original := first.duplicate()
	suite.assert_equal(cache.lookup(first), "", "cold lookup misses")
	suite.assert_true(cache.store(first, DIGEST), "positive digest enters bounded cache")
	first[0] = 9
	suite.assert_equal(cache.lookup(original), DIGEST, "caller mutation cannot alter retained exact key")
	suite.assert_equal(cache.lookup(first), "", "same-length modified bytes miss")
	suite.assert_true(cache.store(PackedByteArray([4]), DIGEST), "second entry enters")
	suite.assert_true(cache.store(PackedByteArray([5]), DIGEST), "third entry evicts oldest")
	suite.assert_equal(cache.lookup(original), "", "entry capacity is enforced")
	suite.assert_equal(cache.snapshot().entries, 2, "entry count remains bounded")
	suite.assert_true(not cache.store(PackedByteArray([6]), ""), "failed digest cannot enter positive cache")
	suite.assert_true(not cache.store(PackedByteArray([6]), "z".repeat(64)), "malformed digest cannot enter cache")
	for digest: String in ["-" + "a".repeat(63), "+" + "a".repeat(63), "A".repeat(64)]:
		suite.assert_true(not cache.store(PackedByteArray([6]), digest), "signed or uppercase digest cannot enter positive cache")
	var bytes_cache: RefCounted = cache_script.new(10, 4)
	suite.assert_true(bytes_cache.store(original, DIGEST), "source fits byte budget")
	suite.assert_true(bytes_cache.store(PackedByteArray([4, 5]), DIGEST), "new source evicts to byte budget")
	suite.assert_equal(bytes_cache.lookup(original), "", "byte budget evicts old source")
	suite.assert_true(not bytes_cache.store(PackedByteArray([1, 2, 3, 4, 5]), DIGEST), "oversized source falls back without storage")
	suite.assert_true(bytes_cache.snapshot().source_bytes <= 4, "retained source bytes remain bounded")
	var typed := var_to_bytes({"value": 1})
	var untyped := var_to_bytes({"value": 1.0})
	suite.assert_true(typed != untyped, "typed source keys preserve integer versus float")
	suite.assert_true(cache.store(typed, DIGEST), "typed source is admitted")
	suite.assert_equal(cache.lookup(untyped), "", "canonical-equivalent values cannot reuse a typed key")
	var threads: Array[Thread] = []
	for worker: int in range(4):
		var thread := Thread.new()
		thread.start(_concurrent.bind(cache, worker))
		threads.append(thread)
	for thread: Thread in threads:
		suite.assert_true(thread.wait_to_finish(), "concurrent exact lookups never return another source's digest")
	suite.assert_true(cache.snapshot().entries <= 2 and cache.snapshot().source_bytes <= 128, "concurrent eviction preserves both bounds")
	cache.clear()
	suite.assert_equal(cache.snapshot().entries, 0, "clear retires all keys")
	suite.assert_equal(cache.snapshot().source_bytes, 0, "clear retires source-byte accounting")
	suite.finish(get_tree())


func _concurrent(cache: RefCounted, worker: int) -> bool:
	for index: int in range(200):
		var source := var_to_bytes([worker, index])
		var digest := ("%d:%d" % [worker, index]).sha256_text()
		cache.store(source, digest)
		var found: String = cache.lookup(source)
		if not found.is_empty() and found != digest:
			return false
	return true
