extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")


func _ready() -> void:
	var suite := Suite.new()
	var parser := Definition.new()
	suite.assert_true(parser.configure(Content.boss("void_throne")).ok, "projection cache fixture starts from authored Void definition")
	var base := parser.runtime_projection()
	var live := Definition.new()
	suite.assert_true(live.configure_runtime_projection(base).ok, "first exact source passes complete native definition parser")
	var source: Script = load("res://scripts/enemies/launch/boss_definition.gd")
	var cache: Variant = source.get("_runtime_projection_cache")
	suite.assert_true(cache is Array and cache.size() > 0 and cache.size() <= 4, "successful native projection retains bounded typed cache")
	if not cache is Array:
		suite.finish(get_tree())
		return
	for entry: Variant in cache:
		suite.assert_true(entry is Dictionary and entry.get("source") is PackedByteArray and entry.get("state") is PackedByteArray, "cached source and accepted instance state hold detached typed bytes")
	var accepted := live.snapshot()
	for _repeat: int in range(8):
		var result: Dictionary = live.configure_runtime_projection(base)
		suite.assert_true(result.ok and live.snapshot() == accepted and result.definition == base, "exact cache hit reconstructs the complete parser instance")
		result.definition.actions[0].warning_frames += 1
	suite.assert_equal(live.runtime_projection(), base, "mutated returned projection cannot poison cache or parser state")
	for kind: String in ["float_counter", "bool_counter", "missing", "foreign", "action_id", "max_hp", "mechanism"]:
		var forged := base.duplicate(true)
		match kind:
			"float_counter": forged.actions[0].warning_frames = float(forged.actions[0].warning_frames)
			"bool_counter": forged.actions[0].warning_frames = true
			"missing": forged.erase("arena")
			"foreign": forged.foreign = true
			"action_id": forged.actions[0].id = "unknown_action"
			"max_hp": forged.max_hp += 1.0
			"mechanism": forged.mechanisms.scepter_burn_tick_frames += 1
		var fresh := Definition.new()
		var cold_result: Dictionary = fresh.call("_configure_runtime_projection_uncached", forged)
		var warm_result: Dictionary = live.configure_runtime_projection(forged)
		suite.assert_equal(warm_result, cold_result, "warm parser preserves complete fresh verdict for " + kind)
		if not cold_result.ok:
			suite.assert_true(live.snapshot().is_empty() and live.runtime_projection().is_empty(), "failed cached-source variation clears prior parser for " + kind)
		suite.assert_true(live.configure_runtime_projection(base).ok, "valid exact source restores parser after refused variation")
	var difficulty: Dictionary = Definition.difficulty_projection(base, 1.5, 1.25)
	var daily: Dictionary = Definition.daily_projection(base, ["swift_finish", "bullet_hell"])
	suite.assert_true(difficulty.ok and daily.ok, "projection cache retains actual difficulty and daily variants")
	for projected: Dictionary in [difficulty.definition, daily.definition]:
		var changed := projected.duplicate(true)
		var fresh := Definition.new()
		suite.assert_true(fresh.call("_configure_runtime_projection_uncached", projected).ok and live.configure_runtime_projection(projected).ok and live.snapshot() == fresh.snapshot() and live.runtime_projection() == fresh.runtime_projection(), "cache reconstructs variant metadata and complete normalized snapshot")
		changed.actions[0].hit_schedule[0].damage += 1.0
		suite.assert_true(not live.configure_runtime_projection(changed).ok, "warm variant cannot detach gameplay values from frozen Base proof")
	var mutated := base.duplicate(true)
	suite.assert_true(live.configure_runtime_projection(mutated).ok, "source mutation fixture warms exact cache")
	mutated.defense += 1.0
	suite.assert_true(live.configure_runtime_projection(base).ok and live.runtime_projection() == base, "external source Dictionary mutation leaves prior cache entry unchanged")
	for id: String in ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]:
		var authored := Definition.new()
		suite.assert_true(authored.configure(Content.boss(id)).ok and live.configure_runtime_projection(authored.runtime_projection()).ok, "all five authored Boss sources retain exact parsing")
		suite.assert_true(source.get("_runtime_projection_cache").size() <= 4, "source cache capacity remains at most four under variants and Boss eviction")
	var threads: Array[Thread] = []
	for _worker: int in range(5):
		var thread := Thread.new()
		threads.append(thread)
		suite.assert_equal(thread.start(func() -> bool:
			for _repeat: int in range(20):
				var worker := Definition.new()
				if not worker.configure_runtime_projection(base).ok or worker.runtime_projection() != base:
					return false
				var forged := base.duplicate(true)
				forged.actions[0].warning_frames = true
				if worker.configure_runtime_projection(forged).ok or not worker.snapshot().is_empty():
					return false
			return true), OK, "native definition cache worker starts")
	for thread: Thread in threads:
		suite.assert_true(thread.wait_to_finish(), "parallel exact-source parsing preserves authentic and forged verdicts")
	suite.assert_true(source.get("_runtime_projection_cache").size() <= 4, "concurrent source cache recording stays bounded")
	suite.finish(get_tree())
