extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Snapshots := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Facade := preload("res://scripts/hub/hub_runtime_facade.gd")
const Codec := preload("res://scripts/progression/build_share_codec.gd")

var _fault := false
var _facade: RefCounted
var _reentry_refused := false


func _ready() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "share flow uses actual Base registry")
	if report.has_blocking_errors():
		suite.finish(get_tree())
		return
	var built := Factory.from_registry(registry)
	var save := Save.new()
	suite.assert_true(save.configure(Paths.resolve_default("user://p20a-hub-share", "p20a-hub-share"), "0.4.0-dev", Snapshots.snapshot(registry), Callable(), Callable(self, "_inject_fault")).ok, "physical sharing save configures")
	var service := Service.new()
	suite.assert_true(service.configure(built.context.catalog, save, "share_slot", "base").ok and service.enable_workshop(registry.get_catalog_entries(&"forge_definition", &"LAUNCH")).ok, "production locked Profile/workshop configures")
	_facade = Facade.new()
	suite.assert_true(_facade.configure(registry, service).ok, "actual Hub sharing facade configures")
	var state: Dictionary = _facade.view_state()
	suite.assert_true(_facade.travel("hub_craft", state.revision, state.epoch).ok and _command("open", {}).ok, "meditation opens in authored district")
	var sample := {"id": "source", "name": "Shared Sword", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	suite.assert_true(_command("build_save", {"command_id": "save-source", "kind": "build_save", "build": sample}).ok, "real owned build saves")
	var profile_before: Dictionary = service.snapshot()
	var exported := _command("build_export", {"build_id": "source"})
	suite.assert_true(exported.ok, "owned build exports through guarded meditation command")
	if not exported.ok:
		_facade = null
		suite.finish(get_tree())
		return
	suite.assert_equal(service.snapshot(), profile_before, "export does not write or alter Profile")
	var code: String = exported.context.share_code
	var imported: Dictionary = Codec.decode(code)
	var request := {"command_id": "import-source", "share_code": code}
	var before: Dictionary = _facade.view_state()
	var envelope_before: Dictionary = save.inspect_profile("share_slot", "base").payload
	_fault = true
	suite.assert_true(not _command("build_import", request).ok, "physical promotion failure rejects import")
	suite.assert_equal(_facade.view_state(), before, "failed import retains Profile revision and Hub epoch")
	suite.assert_equal(save.inspect_profile("share_slot", "base").payload, envelope_before, "failed import preserves exact durable envelope")
	suite.assert_true(_reentry_refused, "save callback cannot reenter import")
	_fault = false
	suite.assert_true(_command("build_import", request).ok, "same import retries through real save")
	suite.assert_true(service.resolve_build(imported.context.build.id).ok, "deterministic imported ID resolves through BuildLibrary")
	suite.assert_equal(service.snapshot().chronos_shards, profile_before.chronos_shards, "import never grants currency")
	suite.assert_equal(service.snapshot().unlocked_nodes, profile_before.unlocked_nodes, "import never grants progression")
	suite.assert_equal(service.snapshot().unlocked_characters, profile_before.unlocked_characters, "import never grants character unlocks")
	var after: Dictionary = service.snapshot()
	suite.assert_equal(_command("build_import", {"command_id": "import-again", "share_code": code}).code, &"NO_CHANGE", "same portable identity refuses duplicate write")
	suite.assert_equal(service.snapshot(), after, "idempotent duplicate retains Profile")
	var locked := sample.duplicate(true)
	locked.character_id = "time_lord"
	locked.weapon_id = "staff"
	var locked_code: Dictionary = Codec.encode(locked)
	suite.assert_equal(_command("build_import", {"command_id": "import-locked", "share_code": locked_code.context.share_code}).code, &"LOADOUT_INVALID", "receiver's actual ownership blocks locked loadout")
	suite.assert_equal(service.snapshot(), after, "locked share cannot modify Profile")
	suite.assert_true(not _command("build_import", {"command_id": "bad", "share_code": code, "currency": 1000}).ok, "extra import fields refuse")
	suite.assert_true(not _command("build_export", {"build_id": "missing"}).ok, "unknown export ID refuses")
	state = _facade.view_state()
	suite.assert_true(not _facade.command({"epoch": state.epoch - 1, "function_id": "meditation", "operation": "build_import", "payload": request}, state.revision).ok, "retired import epoch refuses")
	var restarted := Service.new()
	suite.assert_true(restarted.configure(built.context.catalog, save, "share_slot", "base").ok and restarted.enable_workshop(registry.get_catalog_entries(&"forge_definition", &"LAUNCH")).ok, "physical restart enables sharing library")
	suite.assert_equal(restarted.snapshot(), after, "import survives actual disk restart")
	for index: int in range(30):
		var filling := sample.duplicate(true)
		filling.id = "fill-%d" % index
		suite.assert_true(service.execute({"command_id": "fill-%d" % index, "kind": "build_save", "build": filling}, service.snapshot().revision).ok, "library fills through real atomic save")
	var full: Dictionary = service.snapshot()
	sample.name = "Overflow"
	var overflow: Dictionary = Codec.encode(sample)
	suite.assert_equal(_command("build_import", {"command_id": "overflow", "share_code": overflow.context.share_code}).code, &"BUILD_CAPACITY", "full library rejects another imported ID")
	suite.assert_equal(service.snapshot(), full, "capacity refusal preserves full library")
	_facade = null
	suite.finish(get_tree())


func _command(operation: String, payload: Dictionary) -> Dictionary:
	var view: Dictionary = _facade.view_state()
	return _facade.command({"epoch": view.epoch, "function_id": "meditation", "operation": operation, "payload": payload}, view.revision)


func _inject_fault(point: StringName) -> bool:
	if _fault and point == &"before_primary_promote" and _facade != null:
		_reentry_refused = not _command("build_import", {"command_id": "reenter", "share_code": "invalid"}).ok
	return _fault and point == &"before_primary_promote"
