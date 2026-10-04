extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")

var _fault: StringName = &""
var _observed: RefCounted
var _at_promotion: Dictionary = {}


func _ready() -> void:
	var suite = Suite.new()
	var loaded := Factory.load_base()
	suite.assert_true(loaded.ok, "workshop uses the actual production Meta catalog")
	if not loaded.ok:
		suite.finish(get_tree())
		return
	var catalog: RefCounted = loaded.context.catalog
	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/forge_definitions.json"))
	var state = Profile.new()
	state.configure(catalog)
	var initial := state.snapshot()
	initial.chronos_shards = 400
	initial.existential_imprints = 10
	initial.unlocked_nodes = ["F-01", "F-02", "F-03", "F-04"]
	var packs := [{"pack_id": "base", "pack_version": "1.0.0", "schema_version": 2, "fingerprint_sha256": "a".repeat(64)}]
	var content := {"packs": packs, "aggregate_sha256": Envelope.content_snapshot_digest(packs)}
	var save = Save.new()
	save.configure(Paths.resolve_default("user://p16-workshop-service", "p16-workshop-service"), "test-p16-workshop", content, Callable(), Callable(self, "_inject_fault"))
	var service = Service.new()
	_observed = service
	suite.assert_true(service.configure(catalog, save, "slot_workshop", "base", {"meta_profile_state": initial}).ok, "workshop service configures strict initial Profile")
	suite.assert_true(service.enable_workshop(entries).ok, "authored workshop producers configure behind durable service")
	var upgrade := {"command_id": "upgrade-sword-1", "kind": "forge_upgrade", "weapon_id": "sword"}
	_fault = &"before_primary_promote"
	suite.assert_true(not service.execute(upgrade, 0).ok, "failed promotion cannot publish forge candidate")
	suite.assert_equal(service.snapshot(), initial, "failed forge preserves balances, level and history")
	_fault = &""
	var upgraded: Dictionary = service.execute(upgrade, 0)
	suite.assert_true(upgraded.ok, "forge retry durably promotes once")
	suite.assert_equal(_at_promotion, initial, "live forge level stays unchanged until primary promotion")
	suite.assert_equal(service.snapshot().chronos_shards, 395, "level one spends authored five-shard cost")
	suite.assert_equal(service.forge_projection("sword").attack_bonus, 0.01, "committed weapon projection carries one-percent forging")
	suite.assert_true(not service.execute(upgrade, service.snapshot().revision).ok, "duplicate forge command refuses")
	var reloaded = Service.new()
	suite.assert_true(reloaded.configure(catalog, save, "slot_workshop", "base").ok and reloaded.enable_workshop(entries).ok, "fresh service reloads actual v4 workshop state")
	suite.assert_equal(reloaded.snapshot(), service.snapshot(), "physical restart preserves forge and currency together")
	var enchant := {"command_id": "select-en14", "kind": "enchant_preference", "weapon_id": "sword", "enchantment_ids": ["EN-14"]}
	_fault = &"before_primary_promote"
	var before := service.snapshot()
	suite.assert_true(not service.execute(enchant, before.revision).ok, "unpromoted enchant acquisition refuses")
	suite.assert_equal(service.snapshot(), before, "failed acquisition consumes no imprints or owned marker")
	_fault = &""
	suite.assert_true(service.execute(enchant, before.revision).ok, "acquisition retry commits preferences and ownership with cost")
	suite.assert_equal(service.snapshot().existential_imprints, 5, "EN14 first acquisition spends exactly five imprints")
	suite.assert_true(service.snapshot().completed_command_ids.has("forge-enchant-unlock:EN-14"), "trusted fixed unlock marker is persisted")
	suite.assert_true(not reloaded.execute({"command_id": "stale-build", "kind": "build_save", "build": _build()}, reloaded.snapshot().revision).ok, "old durable service cannot overwrite acquired forge state")
	suite.assert_true(not service.execute({"command_id": "forge-enchant-unlock:EN-01", "kind": "build_save", "build": _build()}, service.snapshot().revision).ok, "public build command cannot occupy trusted unlock namespace")
	var conflict := {"command_id": "conflict", "kind": "enchant_preference", "weapon_id": "sword", "enchantment_ids": ["EN-01", "EN-02"]}
	suite.assert_true(not service.execute(conflict, service.snapshot().revision).ok, "mutually exclusive preferences refuse before durable write")
	var create := {"command_id": "save-build", "kind": "build_save", "build": _build()}
	before = service.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not service.execute(create, before.revision).ok, "failed build promotion refuses")
	suite.assert_equal(service.snapshot(), before, "failed build write leaves the complete live Profile unchanged")
	_fault = &"after_primary_promote"
	var committed: Dictionary = service.execute(create, before.revision)
	suite.assert_true(committed.ok and committed.context.reconciled_committed_write, "promoted build primary reconciles an ambiguous write failure")
	_fault = &""
	var resumed = Service.new()
	_observed = resumed
	suite.assert_true(resumed.configure(catalog, save, "slot_workshop", "base").ok and resumed.enable_workshop(entries).ok, "restart reloads purchased enchant and saved build")
	suite.assert_equal(resumed.resolve_build("main").context.build.weapon_id, "sword", "saved build resolves through current production unlocks")
	suite.assert_true(resumed.execute({"command_id": "unequip", "kind": "enchant_preference", "weapon_id": "sword", "enchantment_ids": []}, resumed.snapshot().revision).ok, "unequip commits without losing ownership")
	suite.assert_true(resumed.execute({"command_id": "recall-bow", "kind": "enchant_preference", "weapon_id": "bow", "enchantment_ids": ["EN-14"]}, resumed.snapshot().revision).ok, "acquired enchant recalls to another unlocked weapon after restart")
	suite.assert_equal(resumed.snapshot().existential_imprints, 5, "recall never spends acquisition imprints again")
	suite.assert_true(resumed.execute({"command_id": "temper", "kind": "void_temper", "weapon_id": "sword", "payment_currency": "existential_imprints"}, resumed.snapshot().revision).ok, "void temper commits authored currency choice")
	suite.assert_equal(resumed.snapshot().existential_imprints, 2, "temper spends three imprints")
	suite.assert_true(resumed.execute({"command_id": "remove-build", "kind": "build_remove", "build_id": "main"}, resumed.snapshot().revision).ok, "build removal persists")
	suite.assert_true(not resumed.resolve_build("main").ok, "removed build cannot launch")
	suite.assert_equal(save.inspect_profile("slot_workshop", "base").payload.schema_version, 4, "all workshop commands use strict Profile v4")
	_observed = null
	suite.finish(get_tree())


func _build() -> Dictionary:
	return {"id": "main", "name": "Sword", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}


func _inject_fault(point: StringName) -> bool:
	if point == &"before_primary_promote" and _observed != null:
		_at_promotion = _observed.snapshot()
	return point == _fault
