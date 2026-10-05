extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Snapshots := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const RuntimePaths := preload("res://scripts/save/runtime_user_data_path.gd")

var _fault: StringName = &""


func _ready() -> void:
	var suite := Suite.new()
	var service := Service.new()
	if not service.has_method("configure_cosmetics"):
		suite.assert_true(false, "native cosmetics use the actual atomic Profile and physical Save service")
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var meta: RefCounted = Factory.from_registry(registry).context.catalog
	var profile := Profile.new()
	profile.configure(meta)
	var initial: Dictionary = profile.snapshot()
	initial.statistics.finished_runs = 1
	initial.statistics.deaths = 1
	var save := Save.new()
	var root := RuntimePaths.resolve_default("user://p23-cosmetics", "p23-cosmetics")
	suite.assert_true(save.configure(root, "p23-test", Snapshots.snapshot(registry), Callable(), Callable(self, "_inject_fault")).ok, "actual Save configures with authored Base identity")
	suite.assert_true(save.enable_meta_profile(meta).ok, "strict Meta validation configures")
	suite.assert_true(save.save_profile("slot", "base", {"meta_profile_state": initial}).ok, "durable progress fixture is physically promoted before commands")
	suite.assert_true(service.configure(meta, save, "slot", "base").ok and service.configure_cosmetics(registry).ok, "service cold-loads actual durable profile and cosmetic catalog")
	var before: Dictionary = service.payload()
	var claim := {"command_id": "claim-return", "kind": "cosmetic_claim", "cosmetic_id": "wanderer.return"}
	_fault = &"before_primary_promote"
	suite.assert_true(not service.execute_cosmetic(claim, 0).ok, "unpromoted physical claim cannot publish collection")
	suite.assert_equal(service.payload(), before, "failed claim leaves live collection exact")
	_fault = &""
	suite.assert_true(service.execute_cosmetic(claim, 0).ok, "retry durably claims the free first-return appearance once")
	suite.assert_equal(service.snapshot().revision, 1, "claim consumes actual Profile revision")
	suite.assert_true(not service.execute_cosmetic(claim, 1).ok, "claim command remains consumed")
	suite.assert_true(not service.execute_cosmetic({"command_id": "forge-progress", "kind": "cosmetic_claim", "cosmetic_id": "wanderer.victory", "victories": 1}, 1).ok, "caller progress fields refuse at command boundary")
	suite.assert_true(not service.execute_cosmetic({"command_id": "locked-victory", "kind": "cosmetic_claim", "cosmetic_id": "wanderer.victory"}, 1).ok, "actual death fixture cannot claim victory appearance")
	var equip := {"command_id": "equip-return", "kind": "cosmetic_equip", "cosmetic_id": "wanderer.return"}
	_fault = &"before_primary_promote"
	suite.assert_true(not service.execute_cosmetic(equip, 1).ok, "failed equipment promotion leaves original appearance")
	suite.assert_equal(service.equipped_cosmetic("wanderer"), "wanderer.default", "failed write cannot publish a new appearance")
	_fault = &"after_primary_promote"
	suite.assert_true(service.execute_cosmetic(equip, 1).ok, "promoted primary reconciles ambiguous equipment write")
	_fault = &""
	var cold := Service.new()
	suite.assert_true(cold.configure(meta, save, "slot", "base").ok and cold.configure_cosmetics(registry).ok, "fresh service reloads physically promoted collection")
	suite.assert_equal(cold.equipped_cosmetic("wanderer"), "wanderer.return", "actual JSON cold reload preserves equipment")
	suite.assert_equal(cold.snapshot().statistics, initial.statistics, "appearance commands cannot alter progression statistics")
	var forged: Dictionary = cold.payload()
	forged.cosmetic_collection.equipped_by_character.wanderer = "wanderer.victory"
	suite.assert_true(not save.save_profile("slot", "base", forged).ok, "physical Save rejects unclaimed equipped appearance")
	suite.assert_true(cold.execute_cosmetic({"command_id": "restore-original", "kind": "cosmetic_equip", "cosmetic_id": "wanderer.default"}, 2).ok, "original appearance can always be restored for an owned character")
	var foreign: Dictionary = cold.payload()
	foreign.cosmetic_collection.equipped_by_character.wanderer = "wanderer.return"
	suite.assert_true(save.save_profile("slot", "base", foreign).ok, "positive control: a competing writer promotes a valid collection at the same Profile revision")
	suite.assert_equal(cold.execute_cosmetic({"command_id": "stale-equip", "kind": "cosmetic_equip", "cosmetic_id": "wanderer.return"}, 3).code, &"STALE_DURABLE_PROFILE", "old collection cannot overwrite a newer physical collection with matching Meta revision")
	var latest := Service.new()
	suite.assert_true(latest.configure(meta, save, "slot", "base").ok and latest.configure_cosmetics(registry).ok, "actual latest primary remains recoverable after competing writer refusal")
	suite.assert_equal(latest.equipped_cosmetic("wanderer"), "wanderer.return", "refused stale write preserves the competing durable equipment")
	var request := {"seed": 42, "difficulty": "normal", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	suite.assert_true(latest.prepare_launch(request, 3).ok, "actual native launch freezes the current Profile")
	before = latest.payload()
	suite.assert_equal(latest.execute_cosmetic({"command_id": "active-equip", "kind": "cosmetic_equip", "cosmetic_id": "wanderer.default"}, 4).code, &"LAUNCH_ACTIVE", "equipment changes refuse while a native run owns the Profile")
	suite.assert_equal(latest.payload(), before, "active-run refusal leaves exact pending native launch and cosmetics intact")
	suite.finish(get_tree())


func _inject_fault(point: StringName) -> bool:
	return point == _fault
