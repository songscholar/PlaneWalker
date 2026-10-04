extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Snapshots := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Config := preload("res://scripts/application/run_config.gd")
const Contract := preload("res://scripts/ui/contracts/hub_view_state.gd")

var _fault := false
var _facade: RefCounted
var _service: RefCounted
var _callback_refused := false


func _ready() -> void:
	var suite := Suite.new()
	var path := "res://scripts/hub/hub_runtime_facade.gd"
	suite.assert_true(ResourceLoader.exists(path), "Hub requires an actual Profile-backed runtime facade")
	if ResourceLoader.exists(path):
		var facade: RefCounted = load(path).new()
		for api: String in ["configure", "travel", "command", "view_state"]:
			suite.assert_true(facade.has_method(api), "Hub facade provides guarded workflow API: " + api)
		_exercise(suite, facade)
	suite.finish(get_tree())


func _exercise(suite: RefCounted, facade: RefCounted) -> void:
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "Hub reads actual validated Base pack")
	if report.has_blocking_errors():
		return
	var built := Factory.from_registry(registry)
	var profile := Profile.new()
	profile.configure(built.context.catalog)
	var initial := profile.snapshot()
	initial.chronos_shards = 4000
	initial.existential_imprints = 500
	initial.unlocked_nodes = ["F-01", "F-02", "F-03", "F-04"]
	var root := Paths.resolve_default("user://p16-hub-facade", "p16-hub-facade")
	var save := Save.new()
	suite.assert_true(save.configure(root, "0.4.0-dev", Snapshots.snapshot(registry), Callable(), Callable(self, "_inject_fault")).ok, "Hub physical Save service configures against actual content")
	var service := Service.new()
	_service = service
	_facade = facade
	suite.assert_true(service.configure(built.context.catalog, save, "hub_slot", "base", {"meta_profile_state": initial}).ok, "Hub owns strict initial Profile")
	suite.assert_true(service.enable_workshop(registry.get_catalog_entries(&"forge_definition", &"LAUNCH")).ok, "real workshop service enables")
	suite.assert_true(service.enable_narrative(registry.get_catalog_entries(&"narrative_definition", &"LAUNCH"), registry.get_catalog_entries(&"narrative_source_definition", &"LAUNCH")).ok, "real narrative service enables")
	var configured: Dictionary = facade.configure(registry, service, {"daily": Callable(self, "_broken_provider")})
	suite.assert_true(configured.ok, "Registry/Profile-backed Hub facade configures: " + str(configured))
	if not configured.ok:
		return
	var view: Dictionary = facade.view_state()
	suite.assert_true(Contract.validate(view).ok and view.districts.size() == 3 and view.functions.size() == 3 and view.nodes.size() == 42, "closed view projects actual districts and 42 authored nodes")
	view.currencies.chronos_shards = 0
	view.loadout.selected.weapon_id = "gun"
	suite.assert_equal(facade.view_state().currencies.chronos_shards, 4000, "detached view mutation cannot alter owned state")
	view = facade.view_state()
	var malformed := view.duplicate(true)
	malformed.nodes[0]["foreign"] = true
	suite.assert_true(not Contract.validate(malformed).ok, "Hub closed row contract refuses unknown fields")
	suite.assert_true(_command("council", "open", {}).ok, "current physical district opens council panel")
	var available: Dictionary = {}
	for node: Dictionary in facade.view_state().nodes:
		if node.available:
			available = node
			break
	suite.assert_true(not available.is_empty(), "actual Meta catalog yields eligible node")
	if not available.is_empty():
		var before: Dictionary = facade.view_state()
		_fault = true
		var purchase := {"command_id": "hub-meta-buy", "kind": "meta_unlock", "node_id": available.id}
		suite.assert_true(not _command("council", "meta_unlock", purchase).ok, "failed physical purchase cannot publish")
		suite.assert_equal(facade.view_state(), before, "failed purchase preserves Profile, Hub revision and epoch")
		_fault = false
		suite.assert_true(_command("council", "meta_unlock", purchase).ok, "purchase retry uses exact Profile service")
		suite.assert_true(service.snapshot().unlocked_nodes.has(available.id), "Meta ownership saves before Hub publication")
		suite.assert_equal(service.snapshot().chronos_shards, 4000 - int(available.cost.chronos_shards), "purchase charges authored shard cost")
		suite.assert_true(_callback_refused, "save callback cannot reenter Hub command or reconfigure facade")
	view = facade.view_state()
	var stale := {"epoch": view.epoch - 1, "function_id": "council", "operation": "back", "payload": {}}
	suite.assert_true(not facade.command(stale, view.revision).ok, "stale epoch refuses")
	suite.assert_true(not facade.travel("hub_craft", view.revision - 1, view.epoch).ok, "stale Profile revision refuses travel")
	suite.assert_equal(facade.view_state(), view, "stale commands leave detached state identical")
	suite.assert_true(facade.travel("hub_craft", view.revision, view.epoch).ok and _command("forge", "open", {}).ok, "authored craft district opens forge")
	var sword: Dictionary = {}
	for weapon: Dictionary in facade.view_state().forge.weapons:
		if weapon.id == "sword":
			sword = weapon
	suite.assert_true(sword.upgrade.available and sword.upgrade.cost.chronos_shards == 5, "forge view exposes authored five-shard next upgrade")
	suite.assert_true(_command("forge", "forge_upgrade", {"command_id": "hub-forge", "kind": "forge_upgrade", "weapon_id": "sword"}).ok, "real forge command persists")
	suite.assert_equal(service.forge_projection("sword").forge_level, 1, "Hub forge state comes from durable service")
	suite.assert_true(_command("meditation", "open", {}).ok, "meditation opens in actual craft district")
	suite.assert_true(facade.view_state().loadout.get("build_save", {}).get("available", false), "actual BuildLibrary candidate exposes save availability")
	var build := {"id": "hub-main", "name": "Rift Sword", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["rift", "accelerate"]}
	suite.assert_true(_command("meditation", "build_save", {"command_id": "hub-build", "kind": "build_save", "build": build}).ok, "Hub persists owned loadout through BuildLibrary")
	suite.assert_true(facade.view_state().builds[0].get("remove", {}).get("available", false), "actual BuildLibrary candidate exposes removal availability")
	suite.assert_true(_command("meditation", "build_select", {"build_id": "hub-main"}).ok, "Hub resolves saved build")
	suite.assert_equal(facade.view_state().loadout.selected.enabled_time_skills, ["rift", "accelerate"], "persisted lexical pair converts to canonical Run order")
	view = facade.view_state()
	suite.assert_true(not _command("meditation", "select_loadout", {"character_id": "time_lord", "weapon_id": "gun", "time_abilities": ["stop", "rewind"], "difficulty": "normal"}).ok, "unowned loadout refuses before launch")
	suite.assert_equal(facade.view_state(), view, "ownership refusal leaves selection and profile unchanged")
	suite.assert_true(not _command("meditation", "forge_upgrade", {"command_id": "wrong-panel", "kind": "forge_upgrade", "weapon_id": "sword"}).ok, "current panel cannot dispatch another destination's write")
	var dialogue: Dictionary = facade.view_state().dialogue
	var chosen: Dictionary = {}
	for node: Dictionary in dialogue.nodes:
		if node.available and not node.choices.is_empty():
			chosen = node
			break
	suite.assert_true(not chosen.is_empty(), "actual NPC content exposes an available Hub choice")
	if not chosen.is_empty():
		suite.assert_true(_command("meditation", "narrative_dialogue", {"command_id": "hub-dialogue", "kind": "narrative_dialogue", "npc_id": dialogue.npc_id, "node_id": chosen.id, "choice_id": chosen.choices[0].id}).ok, "native Hub dialogue physically saves through service")
	view = facade.view_state()
	suite.assert_true(facade.travel("hub_council", view.revision, view.epoch).ok and _command("gateway", "open", {}).ok, "gateway opens in actual council district")
	suite.assert_true(_command("gateway", "provider_refresh", {"provider_id": "daily"}).ok, "malformed provider response safely falls back")
	suite.assert_equal(facade.view_state().providers[0].status, "UNAVAILABLE", "provider outage is explicitly unavailable")
	var launch: Dictionary = _command("gateway", "launch", {"seed": 2037})
	suite.assert_true(launch.ok and Config.validate(launch.context.get("run_config", {})).ok and launch.context.run_config.size() == Config.DEFAULTS.size(), "offline launch returns complete validated production config")
	suite.assert_true(launch.context.run_config.milestone == "LAUNCH" and launch.context.run_config.seed == 2037, "gateway preserves requested deterministic Launch seed")
	suite.assert_true(service.snapshot().active_launch_receipt.is_empty(), "Main owns durable preparation after facade validation")
	var restarted := Service.new()
	suite.assert_true(restarted.configure(built.context.catalog, save, "hub_slot", "base").ok and restarted.enable_workshop(registry.get_catalog_entries(&"forge_definition", &"LAUNCH")).ok, "actual disk reload configures")
	suite.assert_equal(restarted.snapshot(), service.snapshot(), "physical restart retains Meta, forge, build and dialogue together")
	suite.assert_true(service.prepare_launch({"seed": 2037, "difficulty": launch.context.run_config.difficulty, "character_id": launch.context.run_config.character_id, "weapon_id": launch.context.run_config.weapon_id, "time_abilities": launch.context.run_config.enabled_time_skills}, service.snapshot().revision, launch.context.run_config).ok, "returned complete configuration crosses real durable launch boundary")
	suite.assert_true(not _command("gateway", "launch", {"seed": 2037}).ok and not facade.view_state().launch_available, "active launch prevents another gateway launch")
	_facade = null
	_service = null


func _command(function_id: String, operation: String, payload: Dictionary) -> Dictionary:
	var view: Dictionary = _facade.view_state()
	return _facade.command({"epoch": view.epoch, "function_id": function_id, "operation": operation, "payload": payload}, view.revision)


func _inject_fault(point: StringName) -> bool:
	if point == &"before_primary_promote" and _facade != null:
		var view: Dictionary = _facade.view_state()
		_callback_refused = not _facade.command({"epoch": view.epoch, "function_id": view.function_id, "operation": "back", "payload": {}}, view.revision).ok and not _facade.configure(Registry.new(), _service).ok
	return _fault and point == &"before_primary_promote"


func _broken_provider() -> Dictionary:
	return {"ok": false, "error": "offline"}
