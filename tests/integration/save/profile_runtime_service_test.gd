extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_profile_fixtures.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const RuntimePaths := preload("res://scripts/save/runtime_user_data_path.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Run := preload("res://scripts/application/run_state.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Generator := preload("res://scripts/dungeon/floor_plan_generator.gd")

var _fault: StringName = &""
var _observed_service: RefCounted
var _observed_profile: Dictionary = {}


func _ready() -> void:
	var suite = Suite.new()
	var catalog = Catalog.new()
	catalog.configure(Fixtures.meta_entries())
	var state = Profile.new()
	state.configure(catalog)
	var seed_profile: Dictionary = state.snapshot()
	seed_profile.chronos_shards = 50
	var save = Save.new()
	var packs := [{"pack_id": "base", "pack_version": "1.0.0", "schema_version": 2, "fingerprint_sha256": "a".repeat(64)}]
	var content := {"packs": packs, "aggregate_sha256": Envelope.content_snapshot_digest(packs)}
	var root := RuntimePaths.resolve_default("user://p16-profile-service", "p16-profile-service")
	suite.assert_true(save.configure(root, "test-p16", content, Callable(), Callable(self, "_inject_fault")).ok, "physical Save service configures")
	var service = Service.new()
	_observed_service = service
	suite.assert_true(service.configure(catalog, save, "slot_p16", "base", {"meta_profile_state": seed_profile}).ok, "profile service accepts a validated initial profile")
	var command := {"command_id": "buy-w01", "kind": "meta_unlock", "node_id": "W-01"}
	_fault = &"before_primary_promote"
	var rejected: Dictionary = service.execute(command, 0)
	suite.assert_true(not rejected.ok, "failed physical promotion refuses purchase publication")
	suite.assert_equal(service.snapshot(), seed_profile, "failed purchase changes no live currency or unlock")
	suite.assert_equal(save.inspect_profile("slot_p16").code, &"NOT_FOUND", "unpromoted pending file is not committed profile state")
	_fault = &""
	suite.assert_true(service.execute(command, 0).ok, "retry persists and publishes the purchase once")
	suite.assert_equal(_observed_profile, seed_profile, "live profile remains unchanged at physical promotion boundary")
	suite.assert_equal(service.snapshot().chronos_shards, 45, "real purchase uses authored cost")
	suite.assert_true(not service.execute(command, 0).ok, "old revision cannot repeat purchase")
	suite.assert_true(not service.execute(command, 1).ok, "same command cannot repeat even with current revision")
	suite.assert_true(not service.execute({"command_id": "forge-enchant-unlock:EN-14", "kind": "meta_unlock", "node_id": "C-01"}, 1).ok, "public purchase cannot fabricate a trusted forge unlock source")
	var restored = Service.new()
	var booted: Dictionary = restored.configure(catalog, save, "slot_p16", "base")
	suite.assert_true(booted.ok, "fresh service reads the actual JSON primary: %s" % str(booted))
	suite.assert_equal(restored.snapshot(), service.snapshot(), "physical restart preserves exact validated profile")
	var request := {"seed": 20261004, "difficulty": "normal", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	_fault = &"before_primary_promote"
	var before: Dictionary = service.snapshot()
	suite.assert_true(not service.prepare_launch(request, before.revision).ok, "failed launch persistence cannot consume a run sequence")
	suite.assert_equal(service.snapshot(), before, "failed launch leaves immutable effects and launch sequence untouched")
	_fault = &""
	var launched: Dictionary = service.prepare_launch(request, before.revision)
	suite.assert_true(launched.ok, "launch receipt persists before dungeon installation: %s" % str(launched))
	if not launched.ok:
		suite.finish(get_tree())
		return
	suite.assert_equal(launched.context.projection.stat_bonuses.max_hp, 0.02, "launch freezes actually purchased permanent benefit")
	suite.assert_true(not restored.execute({"command_id": "old-purchase", "kind": "meta_unlock", "node_id": "C-01"}, restored.snapshot().revision).ok, "another old service cannot overwrite a newer durable profile")
	suite.assert_true(not service.prepare_launch(request, service.snapshot().revision).ok, "active receipt prevents a second launch")
	var terminal := _terminal(launched.context.launch, launched.context.projection)
	before = service.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not service.settle_terminal(terminal, [], before.revision).ok, "failed terminal write cannot publish payout")
	suite.assert_equal(service.snapshot(), before, "failed settlement retains the active launch and currency")
	_fault = &""
	var settled: Dictionary = service.settle_terminal(terminal, [], before.revision)
	suite.assert_true(settled.ok, "terminal retry persists payout and retires launch together: %s" % str(settled))
	suite.assert_equal(service.snapshot().chronos_shards, 48, "one genuine death pays three guarantee shards")
	suite.assert_true(not service.settle_terminal(terminal, [], service.snapshot().revision).ok, "retired receipt refuses duplicate payout")
	var after_restart = Service.new()
	suite.assert_true(after_restart.configure(catalog, save, "slot_p16", "base").ok, "restart reads settlement and terminal together")
	suite.assert_equal(after_restart.snapshot(), service.snapshot(), "profile and settlement survive actual JSON reload")
	suite.assert_equal(after_restart.payload().active_run_state.get("run_id", ""), terminal.run_id, "final terminal remains available for resumable ending flow")
	_fault = &"after_primary_promote"
	var repaired: Dictionary = after_restart.execute({"command_id": "buy-c01", "kind": "meta_unlock", "node_id": "C-01"}, after_restart.snapshot().revision)
	suite.assert_true(repaired.ok, "committed primary is recognized after an ambiguous post-promotion failure")
	suite.assert_equal(after_restart.snapshot().chronos_shards, 43, "durable reconciliation neither loses nor repeats a purchase")
	suite.assert_true(not after_restart.execute({"command_id": "buy-c01", "kind": "meta_unlock", "node_id": "C-01"}, after_restart.snapshot().revision).ok, "reconciled command stays consumed")
	_fault = &""
	_observed_service = after_restart
	var relaunch: Dictionary = after_restart.prepare_launch(request, after_restart.snapshot().revision)
	suite.assert_true(relaunch.ok, "finished run permits the next durable launch")
	if relaunch.ok:
		suite.assert_equal(relaunch.context.launch.sequence, 2, "launch sequence survives restart and advances monotonically")
		suite.assert_true(after_restart.payload().active_run_state.is_empty(), "new launch retires the old terminal payload")
		var active := _terminal(relaunch.context.launch, relaunch.context.projection)
		active.phase = Phase.Value.COMBAT_ACTIVE
		active.result = {}
		before = after_restart.snapshot()
		suite.assert_true(after_restart.abandon_run(active, before.revision).ok, "explicit abandon durably consumes the active launch")
		suite.assert_equal(after_restart.snapshot().chronos_shards, before.chronos_shards, "abandon never fabricates a death guarantee")
		suite.assert_equal(after_restart.snapshot().statistics.abandons, 1, "abandon records exactly one finished attempt")
		suite.assert_true(not after_restart.abandon_run(active, after_restart.snapshot().revision).ok, "repeat abandon cannot change statistics")
	_observed_service = null
	suite.finish(get_tree())


func _inject_fault(point: StringName) -> bool:
	if point == &"before_primary_promote" and _observed_service != null:
		_observed_profile = _observed_service.snapshot()
	return point == _fault


func _terminal(launch: Dictionary, projection: Dictionary) -> Dictionary:
	var state = Run.new()
	state.reset_domain({"milestone": "LAUNCH", "seed": launch.seed, "difficulty": launch.difficulty}, launch.run_id)
	var floors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/floors.json"))
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	var generated: Dictionary = Generator.new().generate(launch.seed, floors[0], templates)
	state.configure_floor_plan(generated.plan, floors[0], templates)
	for node: Dictionary in generated.plan.nodes:
		if node.id == generated.plan.boss_node_id:
			state.room_total = int(node.layer)
	state.run_time_ms = 1000
	state.phase = Phase.Value.DEFEAT
	state.result = {"result": "death"}
	state.resources = {"meta_run_projection": projection.duplicate(true)}
	return state.snapshot()
