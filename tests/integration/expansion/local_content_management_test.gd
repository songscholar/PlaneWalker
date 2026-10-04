extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Manager := preload("res://scripts/expansion/expansion_content_manager.gd")
const Provider := preload("res://scripts/expansion/offline_entitlement_provider.gd")
const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const Save := preload("res://scripts/save/save_service.gd")
const FileOps := preload("res://scripts/save/save_file_ops.gd")
const Installer := preload("res://scripts/expansion/data_only_pack_installer.gd")

const BASE_SPECS := [{"path": "res://data/content_packs/base/pack.json", "required": true}]
var _locked := false
var _fault := false
var _root := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	_root = OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("p18a")
	suite.assert_true(not _root.begins_with("user://") and _root.is_absolute_path(), "physical isolated test root is explicit")
	_test_provider(suite)
	_test_manager(suite)
	_test_install_refusal(suite)
	_test_staged_installation(suite)
	_test_corrupt_optional_isolation(suite)
	suite.finish(get_tree())


func _test_provider(suite) -> void:
	var provider = Provider.new()
	var rows := [{"pack_id": "fixture_dlc", "entitlement_tag": "fixture.owned", "name_key": "FIXTURE_DLC_NAME", "description_key": "FIXTURE_DLC_DESC", "local_source_path": ""}]
	suite.assert_true(provider.configure(rows, ["fixture.owned"]).ok, "explicit fixture ownership configures")
	var snapshot: Dictionary = provider.snapshot()
	suite.assert_equal(snapshot.status, "LOCAL_FIXTURE", "ownership is explicitly an offline fixture")
	suite.assert_true(snapshot.entries[0].owned and not snapshot.supports_purchase, "fixture discovery reports ownership without purchase support")
	snapshot.owned_tags.clear()
	suite.assert_equal(provider.snapshot().owned_tags, ["fixture.owned"], "provider snapshots are detached")
	suite.assert_true(not provider.configure(rows, ["../unsafe"]).ok, "unsafe entitlement tags refuse")
	suite.assert_equal(provider.snapshot().owned_tags, ["fixture.owned"], "failed provider configure preserves prior state")
	rows.append(rows[0].duplicate(true))
	suite.assert_true(not provider.configure(rows, []).ok, "duplicate discovery IDs refuse")


func _test_manager(suite) -> void:
	var provider = Provider.new()
	suite.assert_true(provider.configure([], ["fixture.owned"]).ok, "manager fixture entitlement configures")
	var storage := _root.path_join("manager")
	var manager = _manager(storage, Callable(provider, "snapshot"), suite)
	if manager == null:
		return
	var base_context: Dictionary = manager.activation_context()
	suite.assert_equal(base_context.save_domain, "base", "empty local selection uses base domain")
	suite.assert_true(base_context.verified_play_eligible, "base keeps existing verification eligibility")
	var source_a := _write_pack("fixture_local_a", {}, "", suite)
	var source_b := _write_pack("fixture_local_b", {"fixture_local_a": "1.0.0"}, "fixture.owned", suite)
	var installed: Dictionary = manager.install(source_a)
	suite.assert_true(installed.ok, "localized real data-only optional item installs: " + JSON.stringify(installed))
	suite.assert_true(manager.install(source_a).ok, "identical physical installation is idempotent")
	suite.assert_true(manager.install(source_b).ok, "tagged dependent package installs while disabled")
	suite.assert_equal(manager.discovery().installed.size(), 2, "discovery reports actual physical installations")
	suite.assert_true(not manager.set_enabled(["fixture_local_b"]).ok, "missing enabled dependency refuses entire candidate")
	suite.assert_equal(manager.activation_context(), base_context, "dependency failure leaves active base unchanged")
	suite.assert_true(manager.set_enabled(["fixture_local_b", "fixture_local_a"]).ok, "owned complete dependency candidate activates")
	var active: Dictionary = manager.activation_context()
	suite.assert_equal(active.activation_order, ["base", "fixture_local_a", "fixture_local_b"], "actual registry activation is deterministic dependency order")
	suite.assert_true(active.save_domain.begins_with("mod_") and active.save_domain.length() == 32, "complete active digest derives bounded mod domain")
	suite.assert_true(not active.verified_play_eligible, "local packages disable verified ranking")
	suite.assert_true(not manager.active_registry().get_content(&"fixture_local_a_item").is_empty(), "real content authority exposes activated optional definition")
	var detached: Dictionary = manager.discovery()
	detached.enabled_pack_ids.clear()
	suite.assert_equal(manager.discovery().enabled_pack_ids, ["fixture_local_a", "fixture_local_b"], "UI discovery is detached")
	_locked = true
	for result: Dictionary in [manager.set_enabled([]), manager.uninstall("fixture_local_a"), manager.install(source_a)]:
		suite.assert_true(not result.ok and result.code == &"RUN_ACTIVE", "actual native run lock prevents mutation")
	_locked = false
	suite.assert_equal(manager.activation_context(), active, "run-lock refusals preserve active context")
	suite.assert_true(not manager.uninstall("fixture_local_a").ok, "enabled package cannot uninstall")
	suite.assert_true(not manager.set_enabled(["fixture_local_b"]).ok, "removing a required enabled dependency refuses")
	var reopened = _manager(storage, Callable(provider, "snapshot"), suite)
	suite.assert_equal(reopened.activation_context(), active, "physical restart recovers exact selected content and domain")
	suite.assert_true(provider.configure([], []).ok, "fixture revokes optional tag without claiming storefront action")
	suite.assert_true(reopened.refresh().ok, "idle refresh isolates revoked optional entitlement")
	suite.assert_equal(reopened.discovery().enabled_pack_ids, ["fixture_local_a"], "revoked tagged content is isolated while independent content remains")
	suite.assert_equal(reopened.discovery().requested_pack_ids, ["fixture_local_a", "fixture_local_b"], "offline isolation preserves retained user intent")
	suite.assert_true(provider.configure([], ["fixture.owned"]).ok and reopened.refresh().ok, "recovered local entitlement restores exact selected fingerprints")
	suite.assert_equal(reopened.activation_context(), active, "entitlement recovery returns original snapshot domain")
	_fault = true
	reopened.set_selection_fault_injector(Callable(self, "_selection_fault"))
	suite.assert_true(not reopened.set_enabled([]).ok, "pre-promotion selection fault refuses candidate publication")
	suite.assert_equal(reopened.activation_context(), active, "failed physical retention preserves published candidate")
	_fault = false
	var recovered = _manager(storage, Callable(provider, "snapshot"), suite)
	suite.assert_equal(recovered.activation_context(), active, "selection fault leaves durable prior content selection")
	FileOps.new().remove_tree(source_a)
	FileOps.new().remove_tree(source_b)
	suite.assert_true(recovered.set_enabled(["fixture_local_a"]).ok, "installed bytes remain independent of deleted source")
	var one: Dictionary = recovered.activation_context()
	suite.assert_true(one.save_domain != active.save_domain, "different complete snapshot gives isolated gameplay domain")
	_test_save_isolation(suite, base_context, one)
	var offline = _manager(storage, Callable(), suite)
	suite.assert_equal(offline.discovery().entitlements.status, "OFFLINE_UNAVAILABLE", "missing optional provider publishes clear offline status")
	suite.assert_true(not offline.set_enabled(["fixture_local_a", "fixture_local_b"]).ok, "missing provider refuses tagged optional activation")
	suite.assert_true(offline.set_enabled(["fixture_local_a"]).ok, "untagged local package remains available offline")
	suite.assert_true(offline.set_enabled([]).ok and offline.uninstall("fixture_local_a").ok, "disabled package uninstalls after successful base selection")
	suite.assert_equal(offline.activation_context().save_domain, "base", "base domain returns without mutating mod saves")


func _test_install_refusal(suite) -> void:
	var manager = _manager(_root.path_join("refusal"), Callable(), suite)
	var scene_source := _write_pack("fixture_scene", {}, "", suite)
	var source := JSON.parse_string(FileAccess.get_file_as_string(scene_source.path_join("pack.json"))) as Dictionary
	_write_bytes(scene_source.path_join("assets/unsafe.tscn"), "[gd_scene format=3]\n[ext_resource type=\"Script\" path=\"res://scripts/main.gd\" id=\"1\"]\n".to_utf8_buffer(), suite)
	source.asset_manifest = ["assets/unsafe.tscn"]
	source.integrity_hashes["assets/unsafe.tscn"] = FileAccess.get_sha256(scene_source.path_join("assets/unsafe.tscn"))
	_write_bytes(scene_source.path_join("pack.json"), JSON.stringify(source).to_utf8_buffer(), suite)
	suite.assert_true(not manager.install(scene_source).ok, "script-bearing native scene cannot enter data-only installation")
	var executable := _write_pack("fixture_exec", {}, "", suite)
	var exec_descriptor := JSON.parse_string(FileAccess.get_file_as_string(executable.path_join("pack.json"))) as Dictionary
	_write_bytes(executable.path_join("assets/unsafe.json"), JSON.stringify({"script_path": "res://scripts/main.gd"}).to_utf8_buffer(), suite)
	exec_descriptor.asset_manifest = ["assets/unsafe.json"]
	exec_descriptor.integrity_hashes["assets/unsafe.json"] = FileAccess.get_sha256(executable.path_join("assets/unsafe.json"))
	_write_bytes(executable.path_join("pack.json"), JSON.stringify(exec_descriptor).to_utf8_buffer(), suite)
	suite.assert_true(not manager.install(executable).ok, "executable JSON asset paths refuse")
	var tampered := _write_pack("fixture_tampered", {}, "", suite)
	_write_bytes(tampered.path_join("content/items.json"), "[]".to_utf8_buffer(), suite)
	suite.assert_true(not manager.install(tampered).ok, "bad source bytes refuse before installation")
	var invalid_content := _write_pack("fixture_invalid", {}, "", suite)
	var invalid_descriptor := JSON.parse_string(FileAccess.get_file_as_string(invalid_content.path_join("pack.json"))) as Dictionary
	var entries := JSON.parse_string(FileAccess.get_file_as_string(invalid_content.path_join("content/items.json"))) as Array
	entries[0]["script_path"] = "res://scripts/main.gd"
	_write_bytes(invalid_content.path_join("content/items.json"), JSON.stringify(entries).to_utf8_buffer(), suite)
	invalid_descriptor.integrity_hashes["content/items.json"] = FileAccess.get_sha256(invalid_content.path_join("content/items.json"))
	_write_bytes(invalid_content.path_join("pack.json"), JSON.stringify(invalid_descriptor).to_utf8_buffer(), suite)
	suite.assert_true(not manager.install(invalid_content).ok, "unknown executable content field cannot silently install")
	suite.assert_true(manager.discovery().installed.is_empty(), "all hostile candidates leave physical catalog empty")
	var unsafe_lock = Manager.new()
	suite.assert_true(not unsafe_lock.configure(_root.path_join("bad_lock"), BASE_SPECS, "0.4.0-dev", &"EXPANSION", Callable(), Callable()).ok, "mutation authority requires real run lock")
	var symlink_source := _write_pack("fixture_symlink", {}, "", suite)
	var original_item := symlink_source.path_join("content/items.json")
	var safe_external := _root.path_join("safe_external.json")
	suite.assert_equal(DirAccess.copy_absolute(original_item, safe_external), OK, "symlink fixture retains authenticated external bytes")
	suite.assert_equal(DirAccess.remove_absolute(original_item), OK, "symlink fixture removes original declared source")
	var source_directory := DirAccess.open(symlink_source)
	suite.assert_equal(source_directory.create_link(safe_external, original_item), OK, "fixture creates actual symbolic link")
	suite.assert_true(not manager.install(symlink_source).ok, "declared file symbolic link refuses even when digest matches")
	suite.assert_true(FileAccess.file_exists(safe_external), "symlink refusal preserves external target")
	var oversized := _write_pack("fixture_oversized", {}, "", suite)
	var oversized_descriptor := JSON.parse_string(FileAccess.get_file_as_string(oversized.path_join("pack.json"))) as Dictionary
	var oversized_bytes := PackedByteArray()
	oversized_bytes.resize(Installer.MAX_FILE_BYTES + 1)
	_write_bytes(oversized.path_join("assets/oversized.wav"), oversized_bytes, suite)
	oversized_descriptor.asset_manifest = ["assets/oversized.wav"]
	oversized_descriptor.integrity_hashes["assets/oversized.wav"] = FileAccess.get_sha256(oversized.path_join("assets/oversized.wav"))
	_write_bytes(oversized.path_join("pack.json"), JSON.stringify(oversized_descriptor).to_utf8_buffer(), suite)
	var oversized_result: Dictionary = manager.install(oversized)
	suite.assert_true(not oversized_result.ok and oversized_result.code == &"INSTALL_LIMIT", "oversized authenticated asset refuses bounded capture")
	var malformed = _manager(_root.path_join("malformed_provider"), Callable(self, "_malformed_provider"), suite)
	suite.assert_equal(malformed.discovery().entitlements.status, "OFFLINE_UNAVAILABLE", "malformed optional provider falls back to offline Base")
	var incompatible := _write_pack("fixture_incompatible", {}, "", suite)
	var incompatible_descriptor := JSON.parse_string(FileAccess.get_file_as_string(incompatible.path_join("pack.json"))) as Dictionary
	incompatible_descriptor.game_version_range = ">=9.0.0"
	_write_bytes(incompatible.path_join("pack.json"), JSON.stringify(incompatible_descriptor).to_utf8_buffer(), suite)
	suite.assert_true(not manager.install(incompatible).ok, "optional resolver isolation cannot masquerade as successful install")


func _test_staged_installation(suite) -> void:
	var installer = Installer.new()
	suite.assert_true(installer.configure(_root.path_join("staged_manager")).ok, "physical staged installer configures")
	var source := _write_pack("fixture_staged", {}, "", suite)
	_write_bytes(source.path_join("undeclared.gd"), "extends Node\n".to_utf8_buffer(), suite)
	var prepared: Dictionary = installer.prepare(source)
	suite.assert_true(prepared.ok, "bounded source bytes prepare immutable staging")
	if not prepared.ok:
		return
	var fingerprint := str(prepared.context.descriptor.fingerprint_sha256)
	var stage_path := str(prepared.context.path)
	suite.assert_true(not FileAccess.file_exists(stage_path.path_join("undeclared.gd")), "undeclared executable bytes are never copied")
	FileOps.new().remove_tree(source)
	var installed: Dictionary = installer.commit_prepared(fingerprint)
	suite.assert_true(installed.ok, "prepared install commits after source disappears")
	suite.assert_true(Descriptor.load_path(installed.context.path).ok, "promoted bytes pass authoritative descriptor validation")
	var marker := _root.path_join("outside_install_marker.json")
	_write_bytes(marker, "{}".to_utf8_buffer(), suite)
	var link := str(installed.context.path).path_join("extra_link.json")
	var installed_directory := DirAccess.open(str(installed.context.path))
	suite.assert_equal(installed_directory.create_link(marker, link), OK, "cleanup fixture creates unmanaged extra link")
	suite.assert_true(installer.uninstall(fingerprint).ok, "known installation cleanup unlinks symbolic link safely")
	suite.assert_true(FileAccess.file_exists(marker), "cleanup never removes symbolic link target")


func _malformed_provider() -> Dictionary:
	return {"status": "LOCAL_FIXTURE", "owned_tags": ["fixture.owned"], "entries": [Callable(self, "_run_lock")], "supports_purchase": false}


func _test_corrupt_optional_isolation(suite) -> void:
	var storage := _root.path_join("corrupt_optional")
	var manager = _manager(storage, Callable(), suite)
	var source_a := _write_pack("fixture_damaged_a", {}, "", suite)
	var source_b := _write_pack("fixture_damaged_b", {"fixture_damaged_a": "1.0.0"}, "", suite)
	suite.assert_true(manager.install(source_a).ok and manager.install(source_b).ok, "physical corrupt-option fixture installs complete dependency chain")
	suite.assert_true(manager.set_enabled(["fixture_damaged_a", "fixture_damaged_b"]).ok, "physical dependency fixture retains selected fingerprints")
	var source_descriptor: Dictionary = Descriptor.load_path(source_a).descriptor
	var installed_a := storage.path_join("packs").path_join(str(source_descriptor.fingerprint_sha256))
	_write_bytes(installed_a.path_join("content/items.json"), "[]".to_utf8_buffer(), suite)
	var reopened = _manager(storage, Callable(), suite)
	suite.assert_equal(reopened.activation_context().save_domain, "base", "corrupt optional package and required dependant isolate without blocking actual Base")
	suite.assert_equal(reopened.discovery().requested_pack_ids, ["fixture_damaged_a", "fixture_damaged_b"], "physical corruption preserves retained selection intent")
	suite.assert_true(not reopened.discovery().diagnostics.is_empty(), "corrupt physical installations have actionable discovery diagnostics")
	suite.assert_true(reopened.set_enabled([]).ok, "explicit Base selection repairs optional selection without touching gameplay save")
	var independent := _write_pack("fixture_independent", {}, "", suite)
	suite.assert_true(reopened.install(independent).ok, "broken disabled optional dependency cannot block an independent local package")


func _test_save_isolation(suite, base_context: Dictionary, mod_context: Dictionary) -> void:
	var save_root := _root.path_join("gameplay_saves")
	var base_save = Save.new()
	suite.assert_true(base_save.configure(save_root, "0.4.0-dev", base_context.content_snapshot).ok, "real Base save service configures")
	suite.assert_true(base_save.save_profile("slot_1", "base", {"fixture_marker": "base"}).ok, "physical Base save writes")
	var base_path := save_root.path_join("profiles/slot_1/base/primary.json")
	var original := FileAccess.get_file_as_bytes(base_path)
	var mod_save = Save.new()
	suite.assert_true(mod_save.configure(save_root, "0.4.0-dev", mod_context.content_snapshot).ok, "real Mod save service configures")
	suite.assert_true(mod_save.save_profile("slot_1", mod_context.save_domain, {"fixture_marker": "mod"}).ok, "physical Mod save writes in isolated domain")
	suite.assert_equal(FileAccess.get_file_as_bytes(base_path), original, "Mod progress leaves physical Base bytes unchanged")
	suite.assert_equal(base_save.load_profile("slot_1", "base").payload.fixture_marker, "base", "Base progress remains readable")
	suite.assert_true(not base_save.load_profile("slot_1", mod_context.save_domain).ok, "foreign full snapshot cannot reopen Mod domain")


func _manager(path: String, entitlement: Callable, suite):
	var manager = Manager.new()
	var configured: Dictionary = manager.configure(path, BASE_SPECS, "0.4.0-dev", &"EXPANSION", entitlement, Callable(self, "_run_lock"))
	suite.assert_true(configured.ok, "physical manager configures with actual Base content")
	return manager if configured.ok else null


func _run_lock() -> bool:
	return _locked


func _selection_fault(point: StringName) -> bool:
	return _fault and point == &"before_primary_promote"


func _write_pack(pack_id: String, dependencies: Dictionary, tag: String, suite) -> String:
	var path := _root.path_join("sources").path_join(pack_id)
	var key := pack_id.to_upper()
	var entries := [{"id": pack_id + "_item", "category": "item", "availability": ["EXPANSION"], "name_key": key + "_NAME", "description_key": key + "_DESC", "tags": ["time"], "compatibility": {}, "effects": {"attack_multiplier": 1.05}, "kind": "weapon", "archetype": "freeze_burst", "role": "starter", "rarity": "common", "icon_id": pack_id}]
	_write_bytes(path.path_join("content/items.json"), JSON.stringify(entries).to_utf8_buffer(), suite)
	_write_bytes(path.path_join("localization/strings.csv"), ("keys,en,zh_CN\n%s_NAME,Local item,Local item\n%s_DESC,Local item description,Local item description\n" % [key, key]).to_utf8_buffer(), suite)
	var dependency_rows: Array = []
	for id: String in dependencies:
		dependency_rows.append({"pack_id": id, "version_range": str(dependencies[id]), "required": true})
	var descriptor := {"pack_id": pack_id, "pack_version": "1.0.0", "schema_version": 2, "game_version_range": ">=0.4.0 <1.0.0", "dependencies": dependency_rows, "load_order": 100, "content_manifest": ["content/items.json"], "localization_sources": ["localization/strings.csv"], "asset_manifest": [], "integrity_hashes": {"content/items.json": FileAccess.get_sha256(path.path_join("content/items.json")), "localization/strings.csv": FileAccess.get_sha256(path.path_join("localization/strings.csv"))}, "entitlement_tag": tag}
	_write_bytes(path.path_join("pack.json"), JSON.stringify(descriptor).to_utf8_buffer(), suite)
	return path


func _write_bytes(path: String, bytes: PackedByteArray, suite) -> void:
	suite.assert_equal(DirAccess.make_dir_recursive_absolute(path.get_base_dir()), OK, "fixture directory exists")
	var file := FileAccess.open(path, FileAccess.WRITE)
	suite.assert_true(file != null, "fixture bytes open")
	if file != null:
		file.store_buffer(bytes)
		file.close()
