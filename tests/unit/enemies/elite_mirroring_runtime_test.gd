extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const AffixProjection := preload("res://scripts/enemies/launch/launch_elite_affix_projection.gd")
const Affix := preload("res://scripts/enemies/launch/launch_elite_affix_runtime.gd")
const Mirroring := preload("res://scripts/enemies/launch/launch_elite_mirroring_runtime.gd")
const SummonProjection := preload("res://scripts/enemies/launch/launch_summon_projection.gd")
const Rules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var parser := Definition.new()
	parser.configure(Content.enemy())
	var identity := {"run_id": "run-mirroring", "hostile_source_id": "mirror-owner", "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}
	var compiler := AffixProjection.new()
	suite.assert_true(compiler.configure([Content.affix("mirroring")], 4).ok, "default native compiler accepts Mirroring")
	var projected: Dictionary = compiler.project(parser.runtime_projection("elite"))
	suite.assert_true(projected.ok and projected.configuration.pending_ids.is_empty() and projected.configuration.native_revision == AffixProjection.CURRENT_NATIVE_REVISION, "current native revision executes Mirroring")
	var runtime := Affix.new()
	suite.assert_true(runtime.configure(projected.configuration, identity, 160.0), "closed native affix runtime configures Mirroring")
	var origin := {"x": 320.0, "y": 180.0}
	for frame: int in range(1, 900):
		suite.assert_true(runtime.advance_frame(frame, 160.0, false, false, 1.0, {}, origin).ok, "pure native clock accepts frame%d" % frame)
	suite.assert_true(runtime.snapshot().mirroring.reservations.is_empty(), "pure Mirroring cannot reserve before complete900-frame interval")
	var before := runtime.snapshot()
	suite.assert_true(not runtime.advance_frame(900, 160.0, false, false, 1.0).ok and runtime.snapshot() == before, "missing native source position refuses without spending interval")
	suite.assert_true(runtime.advance_frame(900, 160.0, false, false, 1.0, {}, origin).ok, "complete900-frame interval accepts owned reservation")
	suite.assert_equal(runtime.snapshot().mirroring.reservations, [{"sequence": 1, "elapsed_frame": 900, "runtime_frame": 900, "source_position": origin}], "pure native receipt retains exact sequence, clocks and source position")
	for frame: int in range(901, 911):
		suite.assert_true(runtime.advance_frame(frame, 160.0, false, true, 1.0, {}, origin).ok, "paused native interval still accepts outer frame")
	suite.assert_equal(runtime.snapshot().mirroring.elapsed_frames, 900, "Stop spends no native Mirroring interval")
	for frame: int in range(911, 1811):
		suite.assert_true(runtime.advance_frame(frame, 160.0, false, false, 1.0, {}, origin).ok, "native Mirroring resumes accepted interval")
	suite.assert_equal(runtime.snapshot().mirroring.reservations.back().runtime_frame, 1810, "next reservation requires complete900 unpaused accepted frames")
	var accepted := runtime.snapshot()
	suite.assert_true(runtime.can_restore_snapshot(accepted), "closed native Mirroring history reconstructs")
	for mutation: String in ["sequence", "elapsed_frame", "runtime_frame", "position", "erased", "extra"]:
		var forged := accepted.duplicate(true)
		match mutation:
			"sequence": forged.mirroring.reservations[0].sequence = 2
			"elapsed_frame": forged.mirroring.reservations[0].elapsed_frame = 899
			"runtime_frame": forged.mirroring.reservations.back().runtime_frame = 1811
			"position": forged.mirroring.reservations[0].source_position = {"x": INF, "y": 0.0}
			"erased": forged.mirroring.reservations.pop_front()
			"extra": forged.mirroring.hidden_child = true
		suite.assert_true(not runtime.restore_snapshot(forged) and runtime.snapshot() == accepted, "native Mirroring refuses %s without mutation" % mutation)
	var historical := AffixProjection.new()
	var revision_nine := AffixProjection.new()
	suite.assert_true(revision_nine.configure([Content.affix("mirroring")], 4, 9).ok, "explicit native revision nine remains supported")
	var prior: Dictionary = revision_nine.project(parser.runtime_projection("elite"))
	suite.assert_true(prior.ok and prior.configuration.pending_ids.is_empty() and prior.configuration.native_revision == 9, "explicit revision nine retains executable Mirroring")
	var prior_runtime := Affix.new()
	suite.assert_true(prior_runtime.configure(prior.configuration, identity, 160.0) and prior_runtime.snapshot().has("mirroring"), "revision nine independently retains the native Mirroring clock")
	suite.assert_true(historical.configure([Content.affix("mirroring")], 4, 8).ok, "explicit native revision eight remains supported")
	var old: Dictionary = historical.project(parser.runtime_projection("elite"))
	suite.assert_equal(old.configuration.pending_ids, ["mirroring"], "explicit revision eight keeps Mirroring metadata-only")
	suite.assert_true(old.definition.affix_signature != projected.definition.affix_signature, "native Mirroring has a separate definition signature")
	var old_runtime := Affix.new()
	suite.assert_true(old_runtime.configure(old.configuration, identity, 160.0) and not old_runtime.snapshot().has("mirroring"), "historical native state does not silently gain Mirroring clock")
	var bounded := Mirroring.initial_state()
	bounded.elapsed_frames = Mirroring.MAX_RESERVATIONS * 900
	for index: int in range(Mirroring.MAX_RESERVATIONS):
		bounded.reservations.append({"sequence": index + 1, "elapsed_frame": (index + 1) * 900, "runtime_frame": (index + 1) * 900, "source_position": origin.duplicate(true)})
	suite.assert_true(Mirroring.can_restore(bounded, identity, int(bounded.elapsed_frames)), "all4096 native reservation receipts reconstruct")
	var full: Dictionary = bounded.duplicate(true)
	bounded.elapsed_frames += 899
	suite.assert_true(Mirroring.can_restore(bounded, identity, int(bounded.elapsed_frames)), "saturated pre-interval native history reconstructs")
	bounded = Mirroring.advance(bounded, int(bounded.elapsed_frames) + 1, false, origin)
	suite.assert_equal(bounded.reservations, full.reservations, "reservation4097 cannot evict accepted native history")
	suite.assert_equal(bounded.elapsed_frames, int(full.elapsed_frames) + 900, "full optional scheduling ledger cannot stall owner accepted combat clocks")
	suite.assert_true(Mirroring.can_restore(bounded, identity, int(bounded.elapsed_frames)), "saturated optional native ledger still reconstructs")
	_test_ordinary_parent_contracts()
	suite.finish(get_tree())


func _test_ordinary_parent_contracts() -> void:
	var mirror := {}
	for row: Dictionary in Content.read_catalog("summons.json"):
		if row.id == "elite_mirror":
			mirror = row
	var tested := 0
	for source: Dictionary in Content.read_catalog("enemies.json"):
		if not Rules.legal_for(source.id, 4, ["mirroring"]):
			continue
		var parser := Definition.new()
		parser.configure(source)
		var parent: Dictionary = parser.runtime_projection()
		var result := SummonProjection.create(mirror, parent)
		suite.assert_true(result.ok, "legal ordinary Mirroring parent has safe native projection: " + str(source.id))
		if not result.ok:
			continue
		tested += 1
		suite.assert_close(result.definition.max_hp, maxf(1.0, float(parent.max_hp) * 0.20), "every mirror uses ordinary parent twenty-percent HP: " + str(source.id))
		suite.assert_equal(result.definition.actions.size(), 1, "every mirror executes at most one safe native action")
		var first := {}
		for candidate: Dictionary in parent.actions:
			if candidate.hit_schedule.any(func(hit: Dictionary): return float(hit.damage) > 0.0):
				first = candidate
				break
		var action: Dictionary = result.definition.actions[0]
		if first.is_empty():
			suite.assert_true(result.definition.mechanisms.harmless, "ordinary nondamaging parent cannot create a hidden mirror attack")
		else:
			suite.assert_true(not result.definition.mechanisms.harmless and action.handler_id == first.handler_id and action.warning_frames >= 23 and action.hit_schedule.size() == first.hit_schedule.size(), "mirror retains only first ordinary damaging action and full warning: " + str(source.id))
			for index: int in range(action.hit_schedule.size()):
				suite.assert_close(action.hit_schedule[index].damage, float(first.hit_schedule[index].damage) * 0.50, "every mirror hit uses ordinary parent half damage: " + str(source.id))
	suite.assert_true(tested > 0, "canonical legal Mirroring parent contracts are exercised")
