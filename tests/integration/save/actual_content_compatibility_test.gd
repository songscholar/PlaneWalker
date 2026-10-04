extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const Snapshots := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")

var _suite: RefCounted
var _fault: StringName = &""
var _save: RefCounted
var _source: Dictionary = {}
var _target: Dictionary = {}
var _expected: Dictionary = {}
var _catalog: RefCounted
var _reentry_refused := false
var _writer: RefCounted


func _ready() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "compatibility target consumes validated actual Base")
	var target := Snapshots.snapshot(registry)
	var built := Factory.from_registry(registry)
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/save/compatibility/base_p16_actual_pre_hub.json"))
	var source_packs := [{"pack_id": old.pack_id, "pack_version": old.pack_version, "schema_version": int(old.schema_version), "fingerprint_sha256": Descriptor.canonical_digest(old)}]
	var source := {"packs": source_packs, "aggregate_sha256": Envelope.content_snapshot_digest(source_packs)}
	var path := "res://scripts/save/actual_content_compatibility_ledger.gd"
	suite.assert_true(ResourceLoader.exists(path), "actual-content upgrades require an explicit trusted compatibility ledger")
	if ResourceLoader.exists(path):
		var ledger: RefCounted = load(path).new()
		suite.assert_true(ledger.has_method("trusted_sources"), "ledger exposes exact source snapshots for strict Save inspection")
		_suite = suite
		_catalog = built.context.catalog
		_target = target
		_test_policy(ledger, source)
	suite.finish(get_tree())


func _test_policy(ledger: RefCounted, original: Dictionary) -> void:
	var sources: Array = ledger.trusted_sources(_target, _catalog.fingerprint())
	_suite.assert_equal(sources.size(), 6, "ledger contains only six audited actual-content sources")
	_suite.assert_true(not ledger.audit_view().is_empty(), "ledger authenticates pinned metadata and full descriptor proof")
	if sources.size() != 6:
		return
	_suite.assert_equal(sources[0], original, "5bee/54bee shared source derives from the complete historical descriptor")
	var middle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/save/compatibility/base_p16_hub_before_narrative.json"))
	_suite.assert_equal(sources[1].packs[0].fingerprint_sha256, Descriptor.canonical_digest(middle), "100d754 source derives from complete intermediate Hub descriptor")
	var narrative: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/save/compatibility/base_p16_narrative_before_training.json"))
	_suite.assert_equal(sources[2].packs[0].fingerprint_sha256, Descriptor.canonical_digest(narrative), "b6e6a2c Narrative source derives from its complete committed descriptor")
	var before_ambush: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/save/compatibility/base_p17_before_native_ambush.json"))
	_suite.assert_equal(sources[3].packs[0].fingerprint_sha256, Descriptor.canonical_digest(before_ambush), "native ambush source derives from the complete retained pre-anchor descriptor")
	var before_corpse: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/save/compatibility/base_p19_before_corpse_tuning.json"))
	_suite.assert_equal(sources[4].packs[0].fingerprint_sha256, Descriptor.canonical_digest(before_corpse), "corpse tuning source derives from the complete retained 2b25db3 descriptor")
	var before_sharing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/save/compatibility/base_p20_before_build_sharing.json"))
	_suite.assert_equal(sources[5].packs[0].fingerprint_sha256, Descriptor.canonical_digest(before_sharing), "build sharing UI source derives from the complete retained f25c218 descriptor")
	_suite.assert_true(ledger.trusted_sources(_target, "0".repeat(64)).is_empty(), "different Meta semantics cannot authorize rebinding")
	_suite.assert_true(ledger.trusted_sources(sources[0], _catalog.fingerprint()).is_empty(), "unknown or reverse target has no implicit compatibility")
	for mutation: String in ["pack", "version", "schema", "aggregate", "extra", "mod"]:
		var forged := _target.duplicate(true)
		match mutation:
			"pack": forged.packs[0].fingerprint_sha256 = "f".repeat(64)
			"version": forged.packs[0].pack_version = "0.5.0-dev"
			"schema": forged.packs[0].schema_version = 3
			"aggregate": forged.aggregate_sha256 = "f".repeat(64)
			"extra": forged["trusted"] = true
			"mod": forged.packs.append({"pack_id": "mod", "pack_version": "1", "schema_version": 2, "fingerprint_sha256": "f".repeat(64)})
		if mutation != "aggregate":
			forged.aggregate_sha256 = Envelope.content_snapshot_digest(forged.packs)
		_suite.assert_true(ledger.trusted_sources(forged, _catalog.fingerprint()).is_empty(), "validly recomputed unknown target still refuses: " + mutation)
	var detached: Array = ledger.trusted_sources(_target, _catalog.fingerprint())
	detached[0].packs[0].fingerprint_sha256 = "f".repeat(64)
	_suite.assert_equal(ledger.trusted_sources(_target, _catalog.fingerprint()), sources, "caller cannot mutate the trusted source table")
	var audit: Dictionary = ledger.audit_view()
	audit.transitions[0].target_id = audit.transitions[0].source_id
	_suite.assert_true(ledger.audit_view().transitions[0].target_id != audit.transitions[0].target_id, "audit metadata is detached")
	for index: int in range(sources.size()):
		_source = sources[index]
		for point: StringName in Save.FAULT_POINTS:
			_test_fault("source-%d-%s" % [index, point], point)
		_test_preimage_refusal("preimage-%d" % index)
	_test_unknown_source(ledger)


func _new_save(case_id: String, binding: Dictionary, inject: bool = false) -> RefCounted:
	var value := Save.new()
	_suite.assert_true(value.configure(_root(case_id), "0.4.0-dev", binding, Callable(), Callable(self, "_inject_fault") if inject else Callable()).ok and value.enable_meta_profile(_catalog).ok, "strict physical fixture configures")
	return value


func _root(case_id: String) -> String:
	return Paths.resolve_default("user://p16-actual-compatibility/" + case_id, "p16-actual-compatibility/" + case_id)


func _seed(save: RefCounted) -> Dictionary:
	var profile := Profile.new()
	profile.configure(_catalog)
	var initial := profile.snapshot()
	initial.chronos_shards = 73
	_suite.assert_true(save.save_profile("slot_compat", "base", {"meta_profile_state": initial, "sentinel": {"nested": ["complete", 47]}}).ok, "source actual-content Profile v4 saves physically")
	var service := Service.new()
	_suite.assert_true(service.configure(_catalog, save, "slot_compat", "base").ok, "source Profile service reloads strict envelope")
	var launched: Dictionary = service.prepare_launch({"seed": 71, "difficulty": "normal", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}, service.snapshot().revision)
	_suite.assert_true(launched.ok, "source fixture contains authentic frozen launch receipt and configuration")
	return save.inspect_profile("slot_compat", "base").payload


func _test_fault(case_id: String, point: StringName) -> void:
	_save = _new_save(case_id, _source, true)
	_expected = _seed(_save)
	var primary_path := _root(case_id).path_join("profiles/slot_compat/base/primary.json")
	var bytes := FileAccess.get_file_as_string(primary_path)
	_suite.assert_equal(_expected.schema_version, 4.0, "actual source uses strict Meta-enabled Profile v4")
	_suite.assert_equal(_new_save(case_id, _target).inspect_profile("slot_compat", "base").code, &"CONTENT_MISMATCH", "ordinary target reader does not silently consume old content")
	_fault = point
	_reentry_refused = false
	var result = _save.rebind_profile_content("slot_compat", "base", _source, _target, _expected)
	_fault = &""
	_suite.assert_true(_reentry_refused, "ledger path retains Save busy and reconfiguration guard")
	if point == &"after_primary_promote":
		_suite.assert_true(result.ok and result.metadata.reconciled_committed_write, "promoted exact primary reconciles actual-content transition")
	else:
		_suite.assert_true(not result.ok, "pre-promotion fault refuses actual-content transition: " + str(point))
		_suite.assert_equal(FileAccess.get_file_as_string(primary_path), bytes, "failed actual-content migration preserves exact primary bytes")
		_suite.assert_equal(_save.inspect_profile("slot_compat", "base").payload, _expected, "failed actual-content migration preserves full envelope")
		result = _save.rebind_profile_content("slot_compat", "base", _source, _target, _expected)
		_suite.assert_true(result.ok, "authenticated retry promotes once")
	var restarted := _new_save(case_id, _target)
	var actual = restarted.inspect_profile("slot_compat", "base")
	_suite.assert_true(actual.ok, "fresh exact-target service reloads physical migration")
	if actual.ok:
		_suite.assert_equal(actual.payload.payload, _expected.payload, "complete Meta, frozen launch, config and extension payload remain identical")
		_suite.assert_equal(actual.payload.sequence, _expected.sequence + 1, "one migration consumes exactly one physical sequence")
		_suite.assert_equal(actual.payload.created_at_utc, _expected.created_at_utc, "profile creation identity survives actual-content upgrade")
	_save = null


func _test_preimage_refusal(case_id: String) -> void:
	_save = _new_save(case_id, _source, true)
	_expected = _seed(_save)
	var primary_path := _root(case_id).path_join("profiles/slot_compat/base/primary.json")
	var before := FileAccess.get_file_as_string(primary_path)
	for field: String in ["payload", "digest", "snapshot"]:
		var changed := _expected.duplicate(true)
		match field:
			"payload": changed.payload.sentinel.nested.append("tampered")
			"digest": changed.integrity.digest = "f".repeat(64)
			"snapshot": changed.content_snapshot = _target.duplicate(true)
		_suite.assert_true(not _save.rebind_profile_content("slot_compat", "base", _source, _target, changed).ok, "actual-source tampered full preimage refuses: " + field)
		_suite.assert_equal(FileAccess.get_file_as_string(primary_path), before, "altered preimage preserves physical bytes")
	_writer = _new_save(case_id, _source)
	var result = _save.rebind_profile_content("slot_compat", "base", _source, _target, _expected)
	_writer = null
	_suite.assert_true(not result.ok, "source-authenticated concurrent writer refuses final promotion")
	var actual = _save.inspect_profile("slot_compat", "base")
	_suite.assert_equal(actual.payload.payload.sentinel.nested[-1], "concurrent", "genuine concurrent write survives migration refusal")
	_save = null


func _test_unknown_source(ledger: RefCounted) -> void:
	var unknown := _source.duplicate(true)
	unknown.packs[0].fingerprint_sha256 = "f".repeat(64)
	unknown.aggregate_sha256 = Envelope.content_snapshot_digest(unknown.packs)
	var save := _new_save("unknown", unknown)
	var seeded := _seed(save)
	var before := FileAccess.get_file_as_string(_root("unknown").path_join("profiles/slot_compat/base/primary.json"))
	var accepted := false
	for candidate: Dictionary in ledger.trusted_sources(_target, _catalog.fingerprint()):
		accepted = accepted or _new_save("unknown", candidate).inspect_profile("slot_compat", "base").ok
	_suite.assert_true(not accepted, "self-declared source fingerprint cannot enter trusted candidate inspection")
	_suite.assert_equal(save.inspect_profile("slot_compat", "base").payload, seeded, "unknown source keeps its exact authenticated envelope")
	_suite.assert_equal(FileAccess.get_file_as_string(_root("unknown").path_join("profiles/slot_compat/base/primary.json")), before, "unknown-content policy performs no physical migration")


func _inject_fault(point: StringName) -> bool:
	if _save != null and _fault == point:
		_reentry_refused = _save.rebind_profile_content("slot_compat", "base", _source, _target, _expected).code == &"BUSY" and _save.configure(_root("unrelated"), "0.4.0-dev", _target).code == &"BUSY"
	if point == &"before_primary_promote" and _writer != null:
		var payload: Dictionary = _expected.payload.duplicate(true)
		payload.sentinel.nested.append("concurrent")
		_suite.assert_true(_writer.save_profile("slot_compat", "base", payload).ok, "another real writer changes the source primary")
	return _fault == point
