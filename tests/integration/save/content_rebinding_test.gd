extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Snapshots := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const FileOps := preload("res://scripts/save/save_file_ops.gd")

var suite: RefCounted
var _source: Dictionary = {}
var _target: Dictionary = {}
var _catalog: RefCounted
var _observed: RefCounted
var _expected: Dictionary = {}
var _fault: StringName = &""
var _reentry: RefCounted
var _reconfigure: RefCounted
var _at_boundary: RefCounted
var _other_writer: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var api := Save.new()
	suite.assert_true(api.has_method("rebind_profile_content"), "production Save service needs an authenticated atomic content rebinding API")
	if not api.has_method("rebind_profile_content"):
		suite.finish(get_tree())
		return
	_catalog = Factory.load_base().context.catalog
	var legacy_packs := [{"pack_id": "base", "pack_version": "0.4.0-dev", "schema_version": 1, "fingerprint_sha256": "1".repeat(64)}]
	_source = {"packs": legacy_packs, "aggregate_sha256": Envelope.content_snapshot_digest(legacy_packs)}
	var registry := Registry.new()
	var report: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "target comes from the actual validated Base Registry")
	_target = Snapshots.snapshot(registry)
	suite.assert_true(not _target.is_empty() and _target != _source, "actual authored fingerprint differs from the known historical synthetic baseline")
	_test_refusals()
	for point: StringName in Save.FAULT_POINTS:
		_test_fault(point)
	_test_clean_and_stale()
	_test_other_writer_conflict()
	_test_new_profile()
	suite.finish(get_tree())


func _new_service(case_id: String, content: Dictionary, inject: bool = false) -> RefCounted:
	var save := Save.new()
	var root := _case_root(case_id)
	suite.assert_true(save.configure(root, "0.4.0-dev", content, Callable(), Callable(self, "_inject_fault") if inject else Callable()).ok, "physical content rebinding fixture configures")
	suite.assert_true(save.enable_meta_profile(_catalog).ok, "physical content rebinding retains strict current Meta Profile validation")
	return save


func _case_root(case_id: String) -> String:
	return Paths.resolve_default("user://p16-content-rebind/" + case_id, "p16-content-rebind/" + case_id)


func _seed(save: RefCounted) -> Dictionary:
	var profile := Profile.new()
	profile.configure(_catalog)
	var payload := {"meta_profile_state": profile.snapshot(), "sentinel": {"nested": ["preserved", 73]}, "settings": {"legacy_marker": "keep"}}
	payload.meta_profile_state.chronos_shards = 73
	suite.assert_true(save.save_profile("slot_rebind", "base", payload).ok, "strict Meta Profile seed reaches a real primary")
	var inspected = save.inspect_profile("slot_rebind", "base")
	suite.assert_true(inspected.ok, "source primary is independently inspected before any migration")
	return inspected.payload


func _test_refusals() -> void:
	var save := _new_service("refusals", _source)
	var before := _seed(save)
	for mutation: String in ["payload", "sequence", "digest", "snapshot", "missing"]:
		var preimage := before.duplicate(true)
		match mutation:
			"payload": preimage.payload.sentinel.nested.append("invented")
			"sequence": preimage.sequence += 1
			"digest": preimage.integrity.digest = "0".repeat(64)
			"snapshot": preimage.content_snapshot = _target.duplicate(true)
			"missing": preimage.clear()
		suite.assert_true(not save.rebind_profile_content("slot_rebind", "base", _source, _target, preimage).ok, "tampered %s exact preimage refuses content rebinding" % mutation)
		suite.assert_equal(save.inspect_profile("slot_rebind", "base").payload, before, "refused migration leaves actual primary and source binding intact")
	var bad_target := _target.duplicate(true)
	bad_target.packs[0].fingerprint_sha256 = "0".repeat(64)
	suite.assert_true(not save.rebind_profile_content("slot_rebind", "base", _source, bad_target, before).ok, "target snapshot must authenticate its declared pack aggregate")
	suite.assert_true(not save.rebind_profile_content("slot_rebind", "base", _target, _target, before).ok, "source service must already be configured to the exact prior snapshot")
	suite.assert_true(not save.rebind_profile_content("../outside", "base", _source, _target, before).ok, "content rebind observes existing profile path policy")
	var target_reader := _new_service("refusals", _target)
	suite.assert_equal(target_reader.load_profile("slot_rebind", "base").code, &"CONTENT_MISMATCH", "ordinary loading does not silently accept the old synthetic content")
	suite.assert_equal(save.inspect_profile("slot_rebind", "base").payload, before, "all invalid boundaries preserve source primary")


func _test_fault(point: StringName) -> void:
	var case_id := "fault-" + str(point)
	var save := _new_service(case_id, _source, true)
	_expected = _seed(save)
	_observed = save
	_fault = point
	_reentry = null
	_reconfigure = null
	var rebound = save.rebind_profile_content("slot_rebind", "base", _source, _target, _expected)
	_fault = &""
	_observed = null
	suite.assert_true(_reentry != null and _reconfigure != null, "migration reaches its authenticated physical transaction: %s" % str(rebound.to_dictionary()))
	if _reentry == null or _reconfigure == null:
		return
	suite.assert_equal(_reentry.code, &"BUSY", "native content transaction rejects reentrant rebinding")
	suite.assert_equal(_reconfigure.code, &"BUSY", "native content transaction cannot replace its configured preimage during callback")
	if point == &"after_primary_promote":
		suite.assert_true(rebound.ok and rebound.metadata.reconciled_committed_write, "actual promoted target primary reconciles a post-promotion failure")
		suite.assert_equal(_at_boundary.code, &"CONTENT_MISMATCH", "target becomes visible to ordinary reads only after transaction verification publishes binding")
		suite.assert_true(save.load_profile("slot_rebind", "base").ok, "reconciled transaction publishes the new content binding")
		var fresh := _new_service(case_id, _target)
		suite.assert_equal(fresh.load_profile("slot_rebind", "base").payload, _expected.payload, "reconciled exact candidate survives a real target-configured restart")
	else:
		suite.assert_true(not rebound.ok, "pre-promotion %s failure refuses migration publication" % str(point))
		suite.assert_equal(save.inspect_profile("slot_rebind", "base").payload, _expected, "failed migration preserves old primary and source binding")
		suite.assert_equal(save.load_profile("slot_rebind", "base").payload, _expected.payload, "new-content pending cannot be treated as a committed migration")
		var retry = save.rebind_profile_content("slot_rebind", "base", _source, _target, _expected)
		suite.assert_true(retry.ok, "exact-preimage retry completes the one migration")
		var fresh := _new_service(case_id, _target)
		suite.assert_equal(fresh.load_profile("slot_rebind", "base").payload, _expected.payload, "retry retains complete strict Meta and extension payload")


func _test_clean_and_stale() -> void:
	var save := _new_service("clean", _source)
	var before := _seed(save)
	var settings := {"locale": "zh_CN", "master_volume": 0.4, "master_muted": false, "camera_shake_enabled": true, "hit_flash_enabled": true, "reduced_motion": false}
	suite.assert_true(save.save_settings(settings).ok, "global settings have an independently committed physical scope")
	var unchanged = save.rebind_profile_content("slot_rebind", "base", _source, _source, before)
	suite.assert_true(unchanged.ok and not unchanged.metadata.committed and save.inspect_profile("slot_rebind", "base").payload == before, "already matching content is an authenticated no-op without another physical save")
	suite.assert_true(save.save_profile("slot_other", "base", before.payload).ok, "another physical profile has its own content boundary")
	var payload: Dictionary = before.payload.duplicate(true)
	payload.sentinel.nested.append("newer")
	suite.assert_true(save.save_profile("slot_rebind", "base", payload).ok, "a genuine later write invalidates an earlier migration preimage")
	suite.assert_true(not save.rebind_profile_content("slot_rebind", "base", _source, _target, before).ok, "stale authenticated preimage refuses even when source content is unchanged")
	before = save.inspect_profile("slot_rebind", "base").payload
	var rebound = save.rebind_profile_content("slot_rebind", "base", _source, _target, before)
	suite.assert_true(rebound.ok and rebound.metadata.committed and not rebound.metadata.reconciled_committed_write, "clean rebinding proves one actual primary commit: %s" % str(rebound.to_dictionary()))
	var after: Dictionary = save.inspect_profile("slot_rebind", "base").payload
	suite.assert_equal(after.sequence, before.sequence + 1, "content migration consumes one physical save sequence")
	suite.assert_equal(after.payload, before.payload, "rebinding preserves the full authenticated payload rather than re-deriving gameplay")
	suite.assert_equal(after.created_at_utc, before.created_at_utc, "content migration preserves profile creation identity")
	suite.assert_equal(save.load_settings().payload, settings, "profile content rebinding preserves independent global settings")
	suite.assert_equal(save.inspect_profile("slot_other", "base").code, &"CONTENT_MISMATCH", "rebinding one primary does not rewrite or relax another profile")
	suite.assert_true(not save.rebind_profile_content("slot_rebind", "base", _source, _target, before).ok, "completed migration cannot consume the old preimage a second time")
	var old_reader := _new_service("clean", _source)
	suite.assert_equal(old_reader.load_profile("slot_rebind", "base").code, &"CONTENT_MISMATCH", "old configured readers cannot consume the migrated primary")
	suite.assert_true(old_reader.load_profile("slot_other", "base").ok, "unmigrated profile remains recoverable through its original explicit binding")


func _test_other_writer_conflict() -> void:
	var save := _new_service("other-writer", _source, true)
	_expected = _seed(save)
	_observed = save
	_other_writer = _new_service("other-writer", _source)
	var rebound = save.rebind_profile_content("slot_rebind", "base", _source, _target, _expected)
	_other_writer = null
	_observed = null
	suite.assert_true(not rebound.ok, "another Save instance cannot change the primary during promotion and have its genuine write overwritten")
	var actual: Dictionary = save.inspect_profile("slot_rebind", "base").payload
	suite.assert_equal(str(actual.payload.sentinel.nested[-1]), "concurrent-write", "commit preimage check retains the other writer's genuine primary")


func _test_new_profile() -> void:
	var save := _new_service("absent", _source)
	var changed = save.rebind_profile_content("slot_rebind", "base", _source, _target, {})
	suite.assert_true(changed.ok and not changed.metadata.committed and changed.metadata.source_kind == "absent", "new-profile binding update reports absence without claiming a file commit")
	suite.assert_equal(save.inspect_profile("slot_rebind", "base").code, &"NOT_FOUND", "new-profile binding update writes no artificial primary")
	var primary := _seed(save)
	suite.assert_equal(primary.content_snapshot, JSON.parse_string(Envelope.canonical_json(_target)), "first genuine new-profile save uses the validated target content")
	var missing := _new_service("absent-preimage", _source)
	suite.assert_true(not missing.rebind_profile_content("slot_rebind", "base", _source, _target, primary).ok, "missing primary cannot accept a nonempty historical preimage")
	var orphan := _new_service("orphan", _source)
	var prior := _seed(_new_service("archive-source", _source))
	var directory := _case_root("orphan").path_join("profiles/slot_rebind/base")
	var files := FileOps.new()
	suite.assert_true(files.ensure_directory(directory).ok and files.write_utf8(directory.path_join(Save.BACKUP_ONE_FILE), Envelope.canonical_json(prior)).ok, "orphan case contains a genuine prior-content recovery envelope")
	suite.assert_true(not orphan.rebind_profile_content("slot_rebind", "base", _source, _target, {}).ok, "remaining physical recovery files prevent a false new-profile binding update")


func _inject_fault(point: StringName) -> bool:
	if _observed != null:
		_reentry = _observed.rebind_profile_content("slot_rebind", "base", _source, _target, _expected)
		_reconfigure = _observed.configure("user://wrong-root", "0.4.0-dev", _target)
		_at_boundary = _observed.inspect_profile("slot_rebind", "base")
		if point == &"before_primary_promote" and _other_writer != null:
			var payload: Dictionary = _expected.payload.duplicate(true)
			payload.sentinel.nested.append("concurrent-write")
			suite.assert_true(_other_writer.save_profile("slot_rebind", "base", payload).ok, "independent authentic writer commits at the promotion callback")
	return point == _fault
