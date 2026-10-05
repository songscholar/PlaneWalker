extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var path := "res://scripts/enemies/launch/forge_arena_runtime.gd"
	suite.assert_true(FileAccess.file_exists(path), "Forge has an authoritative native arena domain")
	if FileAccess.file_exists(path):
		var parser := Definition.new()
		parser.configure(Content.boss("forge_colossus"))
		var identity := {"run_id": "run-forge", "hostile_source_id": "forge-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
		var runtime: RefCounted = load(path).new()
		suite.assert_true(runtime.configure(parser.runtime_projection(), identity).ok, "Forge arena binds authored recipes")
		var initial: Dictionary = runtime.snapshot()
		suite.assert_true(initial.covers.size() == 4 and initial.vents.size() == 4 and initial.cooling_pools.size() == 4, "Forge manifests four anvils, fixed delegated vents and permanent cooling pools")
		for cover: Dictionary in initial.covers:
			suite.assert_true(cover.max_hp == 120.0 and cover.current_hp == 120.0, "each native anvil owns exactly120HP")
		suite.assert_true(initial.vent_damage_authority == "rule_forge_vents", "one P14 authority owns vent damage")
		var fact := {"fact_id": "anvil-hit", "run_id": "run-forge", "owner_source_id": "forge-owner", "construct_id": "forge_anvil:0", "runtime_frame": 1, "amount": 200.0}
		suite.assert_equal(runtime.accept_damage_fact(fact).get("amount"), 120.0, "anvil overkill clamps independently")
		suite.assert_true(not runtime.accept_damage_fact(fact).ok and not runtime.can_restore_snapshot(runtime.snapshot(), true), "duplicate anvil receipt and staged cold boundary fail closed")
		runtime.advance_frame(1)
		var burn := {"run_id": "run-forge", "owner_source_id": "forge-owner", "target_id": "player", "attack_generation": 7, "runtime_frame": 1}
		suite.assert_true(runtime.accept_burn_fact(burn).ok and runtime.snapshot().burns.size() == 1, "slam retains source-owned finite burn")
		var cooling: Dictionary = initial.cooling_pools[0].position
		suite.assert_true(runtime.observe_target("player", cooling).get("cooled", false) and runtime.snapshot().burns.is_empty(), "cooling entry removes this Boss-owned burn")
		runtime.observe_target("player", {"x": 320.0, "y": 180.0})
		burn.attack_generation = 8
		runtime.accept_burn_fact(burn)
		suite.assert_true(not runtime.observe_target("player", cooling).get("cooled", true) and runtime.snapshot().burns.size() == 1, "same actor cannot retrigger cooling inside30frames")
		runtime.observe_target("other-player", cooling)
		suite.assert_true(runtime.snapshot().cooling_claims.size() == 2, "cooling cooldown is per actor")
		for frame: int in range(2, 31):
			runtime.advance_frame(frame)
		runtime.observe_target("player", {"x": 320.0, "y": 180.0})
		runtime.advance_frame(31)
		suite.assert_true(runtime.observe_target("player", cooling).get("cooled", false), "cooling accepts re-entry exactly30frames later")
		suite.assert_true(runtime.accept_phase(1, 31).ok and runtime.accept_phase(2, 31).ok, "form transitions remain monotonic and retain cooling")
		suite.assert_equal(runtime.snapshot().cooling_pools, initial.cooling_pools, "cooling pools survive all forms")
		var current: Dictionary = runtime.snapshot()
		suite.assert_true(runtime.can_restore_snapshot(current, true) and runtime.restore_snapshot(current), "native cold arena validates accepted damage, burn and cooling provenance")
		for mutation: String in ["hp", "vent", "cooldown", "burn", "phase", "unknown"]:
			var forged := current.duplicate(true)
			match mutation:
				"hp": forged.covers[0].current_hp = 1.0
				"vent": forged.vent_damage_authority = "boss"
				"cooldown": forged.cooling_claims[0].runtime_frame = 2
				"burn": forged.burns.append({"target_id": "forged"})
				"phase": forged.phase_index = 1
				"unknown": forged.extra = true
			suite.assert_true(not runtime.can_restore_snapshot(forged), "cold Forge rejects forged " + mutation)
		var foreign := burn.duplicate(true)
		foreign.owner_source_id = "foreign-owner"
		suite.assert_true(not runtime.accept_burn_fact(foreign).ok, "Forge cannot claim another burn owner")
		var finite: RefCounted = load(path).new()
		finite.configure(parser.runtime_projection(), identity)
		burn.runtime_frame = 0
		finite.accept_burn_fact(burn)
		var ticks := 0
		for frame: int in range(1, 182):
			finite.advance_frame(frame)
			ticks += finite.burn_damage_requests(frame).size()
		suite.assert_true(ticks == 3 and finite.snapshot().burns.is_empty(), "finite180frame burn produces exactly three10damage ticks then retires")
		suite.assert_true(finite.can_restore_snapshot(finite.snapshot(), true), "expired finite burn retains reconstructible tickprovenance")
	suite.finish(get_tree())
