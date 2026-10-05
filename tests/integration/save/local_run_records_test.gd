extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Run := preload("res://scripts/application/run_state.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Generator := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RecordRules := preload("res://scripts/community/local_run_record_rules.gd")


func _ready() -> void:
	var suite := Suite.new()
	suite.assert_true(Service.new().has_method("verified_settled_run"), "read-only durable settlement authentication is required")
	suite.assert_true(ResourceLoader.exists("res://scripts/community/local_run_records.gd"), "offline local board must have a real writer")
	if not ResourceLoader.exists("res://scripts/community/local_run_records.gd") or not Service.new().has_method("verified_settled_run"):
		suite.finish(get_tree())
		return
	var records_script: Script = load("res://scripts/community/local_run_records.gd")
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var binding := Content.snapshot(registry)
	var catalog := Fixtures.catalog()
	var root := Paths.resolve_default("user://p20b-records", "p20b-records")
	var physical := Save.new()
	physical.configure(root.path_join("profiles"), "test-p20b", binding)
	var service := Service.new()
	service.configure(catalog, physical, "record_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	var records: RefCounted = records_script.new()
	suite.assert_true(records.configure(service, root.path_join("boards"), "test-p20b", binding, "base").ok, "independent board configures from actual Profile")
	suite.assert_equal(records.sync_settled_run().code, &"NO_SETTLED_RUN", "idle Profile cannot invent a result")
	var terminal := _settle(suite, service, 3000)
	var verified: Dictionary = service.verified_settled_run()
	suite.assert_true(verified.ok and verified.context.terminal == terminal and verified.context.content_snapshot == binding, "read-only authentication returns detached real terminal and content")
	var profile_before := service.snapshot()
	var synchronized: Dictionary = records.sync_settled_run()
	suite.assert_true(synchronized.ok and synchronized.context.inserted, "real settled Run enters independent board")
	suite.assert_equal(service.snapshot(), profile_before, "record acknowledgement changes no Meta Profile state")
	suite.assert_true(service.payload().local_records_outbox.sources.is_empty(), "physical board confirmation consumes durable outbox")
	var board: Dictionary = records.snapshot()
	suite.assert_equal(board.entries.size(), 1, "first authentic Run has one record")
	suite.assert_equal(board.entries[0].score, 0, "entry death cannot fabricate completed-room points")
	suite.assert_true(records.sync_settled_run().code == &"NO_SETTLED_RUN" and records.snapshot() == board, "same full Run identity is consumed exactly once")
	var restarted: RefCounted = records_script.new()
	suite.assert_true(restarted.configure(service, root.path_join("boards"), "test-p20b", binding, "base").ok and restarted.snapshot() == board, "a fresh writer reloads physical board JSON")
	var public_before: Dictionary = records.snapshot()
	public_before.entries.clear()
	suite.assert_equal(records.snapshot(), board, "public snapshots cannot mutate ranking")
	var conflict: String = verified.context.receipt.digest
	for point: StringName in Save.FAULT_POINTS:
		_settle(suite, service, 2000)
		var before: Dictionary = records.snapshot()
		records.set_fault_injector(func(at: StringName): return at == point)
		var written: Dictionary = records.sync_settled_run()
		if point == &"after_primary_promote":
			suite.assert_true(written.ok and written.context.reconciled_committed_write, "promoted primary alone reconciles an ambiguous record write: " + str(written))
		else:
			suite.assert_true(not written.ok and records.snapshot() == before, "unpromoted fault preserves board memory: " + str(point))
		records.set_fault_injector(Callable())
		suite.assert_true(records.sync_settled_run().ok or point == &"after_primary_promote", "next authentic refresh retries failed record: " + str(point))
		var after: Dictionary = records.snapshot()
		suite.assert_true(records.sync_settled_run().code == &"NO_SETTLED_RUN" and records.snapshot() == after, "fault recovery consumes the receipt exactly once")
	var reentrant := {"code": &""}
	_settle(suite, service, 1000)
	records.set_fault_injector(func(at: StringName):
		if at == &"after_pending_verify": reentrant.code = records.sync_settled_run().code
		return false)
	suite.assert_true(records.sync_settled_run().ok and reentrant.code == &"BUSY", "record promotion rejects reentrant publication")
	records.set_fault_injector(Callable())
	board = records.snapshot()
	suite.assert_equal(board.entries[0].run_time_ms, 1000, "equal scores rank smaller elapsed time first")
	var detached: Dictionary = service.verified_settled_run().context
	detached.terminal.run_time_ms = 0
	suite.assert_true(service.verified_settled_run().ok, "detached terminal cannot rewrite saved authentication")
	var payload := service.payload()
	payload.active_run_state.run_time_ms = 0
	suite.assert_true(physical.save_profile("record_owner", "base", payload).ok, "tamper fixture persists a structurally valid zero-time terminal")
	suite.assert_equal(service.verified_settled_run().code, &"STALE_DURABLE_PROFILE", "old service refuses a changed physical primary")
	var forged := Service.new()
	forged.configure(catalog, physical, "record_owner", "base")
	suite.assert_true(not forged.verified_settled_run().ok, "fresh service rejects physically saved forged terminal")
	suite.assert_equal(records.snapshot(), board, "forged terminal cannot change existing board")
	var mod_service := Service.new()
	mod_service.configure(catalog, physical, "record_owner", "mod_test", {"meta_profile_state": Fixtures.profile(catalog)})
	var mods: RefCounted = records_script.new()
	suite.assert_true(mods.configure(mod_service, root.path_join("boards"), "test-p20b", binding, "mod_test").ok and mods.snapshot().entries.is_empty(), "Mod scope has an independent empty board")
	_settle(suite, mod_service, 1000)
	suite.assert_true(mods.sync_settled_run().ok and mods.provider_row().entries[0].name.contains(tr("UI_COMMUNITY_UNRANKED")), "Mod record is explicitly Local / Unranked")
	suite.assert_equal(records.snapshot(), board, "Mod publication does not affect the base board")
	suite.assert_true(conflict != service.snapshot().last_settlement_receipt.digest, "test exercises distinct physical settlement identities")
	payload = service.payload()
	suite.assert_true(physical.save_profile("record_owner", "base", payload).ok, "restore trusted physical Profile for remaining boundary cases")
	_settle(suite, service, 5000, true)
	suite.assert_true(records.sync_settled_run().ok, "typed completed-room ledger is accepted")
	suite.assert_equal(records.snapshot().entries[0].score, 1000, "one canonical completed room outranks an entry death")
	var other_binding := binding.duplicate(true)
	other_binding.packs[0].fingerprint_sha256 = "b".repeat(64)
	other_binding.aggregate_sha256 = preload("res://scripts/save/save_envelope.gd").content_snapshot_digest(other_binding.packs)
	var other_content: RefCounted = records_script.new()
	suite.assert_equal(other_content.configure(service, root.path_join("boards"), "test-p20b", other_binding, "base").code, &"RECORD_SCOPE_MISMATCH", "authenticated Profile cannot configure another content identity")
	var alternate_save := Save.new()
	alternate_save.configure(root.path_join("alternate_profiles"), "test-p20b", other_binding)
	var alternate_service := Service.new()
	alternate_service.configure(catalog, alternate_save, "record_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	suite.assert_true(other_content.configure(alternate_service, root.path_join("boards"), "test-p20b", other_binding, "base").ok and other_content.snapshot().entries.is_empty(), "real alternate-content Profile has a separate physical board")
	var competitor := Service.new()
	competitor.configure(catalog, physical, "competing_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	_settle(suite, competitor, 1500)
	var competing_records: RefCounted = records_script.new()
	competing_records.configure(competitor, root.path_join("boards"), "test-p20b", binding, "base")
	_settle(suite, service, 1600)
	var interleaved := {"done": false, "ok": false}
	records.set_fault_injector(func(at: StringName):
		if at == &"before_primary_promote" and not interleaved.done:
			interleaved.done = true
			interleaved.ok = competing_records.sync_settled_run().ok
		return false)
	suite.assert_equal(records.sync_settled_run().code, &"STALE_PRIMARY", "promotion compare-exchange refuses another writer's newer board")
	suite.assert_true(interleaved.ok, "competing authentic writer commits its own record")
	records.set_fault_injector(Callable())
	suite.assert_true(records.sync_settled_run().ok, "retry merges authenticated records after competing promotion")
	suite.assert_true(records.snapshot().watermarks.has("competing_owner") and records.snapshot().watermarks.has("record_owner"), "competing writers lose no Profile watermark")
	var active_service := Service.new()
	active_service.configure(catalog, physical, "active_reader", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	active_service.prepare_launch({"seed": 4, "difficulty": "normal", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}, 0)
	var active_reader: RefCounted = records_script.new()
	active_reader.configure(active_service, root.path_join("boards"), "test-p20b", binding, "base")
	_settle(suite, competitor, 1200)
	competing_records.sync_settled_run()
	suite.assert_true(active_reader.provider_row().available and active_reader.snapshot().watermarks.competing_owner.launch_sequence == 2, "read-only refresh during active Run observes another writer's physical board")
	var storage: RefCounted = records.get("_save")
	var board_id: String = records.get("_board_id")
	var full: Dictionary = records.snapshot()
	var template: Dictionary = full.entries[0].duplicate(true)
	full.entries.clear()
	full.watermarks = {"fixture_history": {"launch_sequence": 1000, "run_id": "meta-run-fixture_history-1000", "receipt_digest": template.receipt_digest}}
	for sequence: int in range(1, 1001):
		var retained := template.duplicate(true)
		retained.profile_id = "fixture_history"
		retained.run_id = "meta-run-fixture_history-%d" % sequence
		retained.launch_sequence = sequence
		retained.completed_rooms = 0
		retained.score = 0
		retained.run_time_ms = 4000
		retained.id = "record_" + JSON.stringify({"profile_id": retained.profile_id, "run_id": retained.run_id, "receipt_digest": retained.receipt_digest}, "", true, true).sha256_text()
		full.entries.append(retained)
	full.entries.sort_custom(func(left: Dictionary, right: Dictionary): return left.id < right.id)
	suite.assert_true(storage.save_profile(board_id, "local", {"local_run_records": full}).ok, "bounded-history fixture writes physical protocol through SaveService")
	_settle(suite, service, 1000)
	suite.assert_true(records.sync_settled_run().ok, "new authenticated Run merges into a full historical board")
	board = records.snapshot()
	suite.assert_equal(board.entries.size(), 1000, "top records remain bounded after the 1001st identity")
	suite.assert_equal(board.entries[0].profile_id, "record_owner", "faster equal-score record wins deterministic ordering")
	suite.assert_true(board.watermarks.has("fixture_history"), "eviction retains consumed historical identities")
	var primary_before = storage.inspect_profile(board_id, "local")
	suite.assert_true(records.sync_settled_run().code == &"NO_SETTLED_RUN" and storage.inspect_profile(board_id, "local").payload == primary_before.payload, "duplicate refresh of bounded board performs no physical write")
	var authentic_source: Dictionary = service.verified_settled_run().context
	var queued_payload := service.payload()
	var queued_source: Dictionary = {}
	for field: String in ["profile_id", "save_domain", "content_snapshot", "terminal", "launch", "receipt"]:
		queued_source[field] = authentic_source[field]
	queued_payload.local_records_outbox = {"schema_version": 1, "sources": [queued_source]}
	var queue_written = physical.save_profile("record_owner", "base", queued_payload)
	var queue_boot: Dictionary = service.configure(catalog, physical, "record_owner", "base")
	suite.assert_true(queue_written.ok and queue_boot.ok, "conflict fixture restores an independently authenticated queued source: " + str(queue_written.to_dictionary()) + " " + str(queue_boot))
	var future_board := board.duplicate(true)
	future_board.entries = []
	future_board.watermarks = {"record_owner": {"launch_sequence": 2000000000, "run_id": "meta-run-record_owner-2000000000", "receipt_digest": authentic_source.receipt.digest}}
	storage.save_profile(board_id, "local", {"local_run_records": future_board})
	suite.assert_equal(service.acknowledge_local_records(storage, board_id).code, &"RECORD_ACK_INVALID", "forged future watermark cannot consume authenticated pending source")
	suite.assert_equal(service.payload().local_records_outbox.sources.size(), 1, "future watermark refusal retains physical outbox")
	storage.save_profile("foreign_board", "local", {"local_run_records": board})
	suite.assert_equal(service.acknowledge_local_records(storage, "foreign_board").code, &"RECORD_ACK_INVALID", "physical board id must bind its actual content and domain")
	suite.assert_equal(service.payload().local_records_outbox.sources.size(), 1, "foreign board refusal retains physical outbox")
	storage.save_profile(board_id, "local", {"local_run_records": board})
	physical.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	var ack_pending: Dictionary = records.sync_settled_run()
	suite.assert_true(ack_pending.ok and ack_pending.context.acknowledgement_pending and service.payload().local_records_outbox.sources.size() == 1, "failed optional acknowledgement preserves its authenticated durable source")
	physical.set_fault_injector(Callable())
	suite.assert_true(records.sync_settled_run().ok and service.payload().local_records_outbox.sources.is_empty(), "retry independently confirms committed board and consumes failed acknowledgement")
	physical.save_profile("record_owner", "base", queued_payload)
	service.configure(catalog, physical, "record_owner", "base")
	var conflicted := board.duplicate(true)
	conflicted.watermarks.record_owner.receipt_digest = "c".repeat(64)
	for record: Dictionary in conflicted.entries:
		if record.profile_id == "record_owner":
			record.receipt_digest = "c".repeat(64)
			record.id = "record_" + JSON.stringify({"profile_id": record.profile_id, "run_id": record.run_id, "receipt_digest": record.receipt_digest}, "", true, true).sha256_text()
	suite.assert_true(storage.save_profile(board_id, "local", {"local_run_records": conflicted}).ok, "conflicting-receipt fixture retains structurally valid full Run identity")
	primary_before = storage.inspect_profile(board_id, "local")
	suite.assert_equal(records.sync_settled_run().code, &"RECORD_IDENTITY_CONFLICT", "same Profile sequence with a different receipt fails closed")
	suite.assert_equal(storage.inspect_profile(board_id, "local").payload, primary_before.payload, "conflict refusal preserves physical board bytes")
	var limited := board.duplicate(true)
	limited.entries = []
	limited.watermarks = {}
	for index: int in range(1000):
		limited.watermarks["owner_%d" % index] = {"launch_sequence": 1, "run_id": "meta-run-owner_%d-1" % index, "receipt_digest": "d".repeat(64)}
	storage.save_profile(board_id, "local", {"local_run_records": limited})
	suite.assert_equal(records.sync_settled_run().code, &"OWNER_LIMIT", "bounded owner metadata refuses an additional owner without eviction")
	var malformed := board.duplicate(true)
	malformed.schema_version = 99
	storage.save_profile(board_id, "local", {"local_run_records": malformed})
	var refused: RefCounted = records_script.new()
	suite.assert_equal(refused.configure(service, root.path_join("boards"), "test-p20b", binding, "base").code, &"BOARD_INVALID", "unknown board version is not silently replaced")
	storage.save_profile(board_id, "local", {"local_run_records": board})
	_settle(suite, alternate_service, 1000)
	var rebound_save := Save.new()
	rebound_save.configure(root.path_join("rebound_profiles"), "test-p20b", binding)
	rebound_save.enable_meta_profile(catalog)
	rebound_save.save_profile("record_owner", "base", alternate_service.payload())
	var rebound_service := Service.new()
	rebound_service.configure(catalog, rebound_save, "record_owner", "base")
	var rebound_records: RefCounted = records_script.new()
	rebound_records.configure(rebound_service, root.path_join("boards"), "test-p20b", binding, "base")
	suite.assert_true(rebound_records.sync_settled_run().ok, "retained queued source preserves its original actual-content board after compatible rebinding")
	suite.assert_true(other_content.provider_row().available and other_content.snapshot().entries.size() == 1, "historical queued record is written only to its original content board")
	suite.assert_equal(rebound_records.snapshot(), board, "historical queue processing leaves current-content board intact")
	var corrupt_receipt := service.payload()
	corrupt_receipt.meta_profile_state.last_settlement_receipt.digest = "0".repeat(64)
	physical.save_profile("record_owner", "base", corrupt_receipt)
	var invalid_receipt := Service.new()
	invalid_receipt.configure(catalog, physical, "record_owner", "base")
	suite.assert_equal(invalid_receipt.verified_settled_run().code, &"SETTLEMENT_DIGEST_INVALID", "saved receipt digest must bind real terminal sources")
	_test_outbox_retention(suite, catalog, binding, root)
	_test_legacy_abandon(suite, catalog, binding, root, authentic_source.terminal)
	suite.finish(get_tree())


func _test_legacy_abandon(suite: RefCounted, catalog: RefCounted, binding: Dictionary, root: String, template: Dictionary) -> void:
	var physical := Save.new()
	physical.configure(root.path_join("legacy_abandon"), "test-p20b", binding)
	var service := Service.new()
	service.configure(catalog, physical, "record_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	var request := {"seed": 20261005, "difficulty": "normal", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	var launched: Dictionary = service.prepare_launch(request, 0)
	var active := template.duplicate(true)
	active.run_id = launched.context.launch.run_id
	active.resources.meta_run_projection = launched.context.projection
	active.phase = Phase.Value.COMBAT_ACTIVE
	active.result = {}
	suite.assert_true(service.abandon_run(active, int(service.snapshot().revision)).ok, "legacy abandon fixture consumes real launch")
	var payload := service.payload()
	payload.erase("local_records_outbox")
	physical.save_profile("record_owner", "base", payload)
	service.configure(catalog, physical, "record_owner", "base")
	suite.assert_equal(service.verified_settled_run().code, &"NO_SETTLED_RUN", "legacy abandoned run cannot fabricate local result")
	suite.assert_true(service.verified_local_record_outbox().ok and service.verified_local_record_outbox().context.sources.is_empty(), "legacy abandon fallback permits subsequent settlement")
	_settle(suite, service, 2000)


func _test_outbox_retention(suite: RefCounted, catalog: RefCounted, binding: Dictionary, root: String) -> void:
	var physical := Save.new()
	physical.configure(root.path_join("retention"), "test-p20b", binding)
	var service := Service.new()
	service.configure(catalog, physical, "record_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	_settle(suite, service, 4000)
	var payload := service.payload()
	payload.meta_profile_state.launch_sequence = 1000
	var queue: Array = []
	var authority: RefCounted = service.get("_settlement")
	for sequence: int in range(1, 1001):
		var source: Dictionary = payload.local_records_outbox.sources[0].duplicate(true)
		source.terminal.run_id = "meta-run-record_owner-%d" % sequence
		source.launch.run_id = source.terminal.run_id
		source.launch.sequence = sequence
		source.receipt.run_id = source.terminal.run_id
		source.receipt.sequence = sequence
		var unsigned: Dictionary = source.receipt.duplicate(true)
		unsigned.erase("digest")
		var verified_sources: Dictionary = authority.verified_run_sources(source.launch, source.terminal)
		source.receipt.digest = JSON.stringify({"receipt": unsigned, "projection_digest": source.launch.projection_digest, "sources": verified_sources.context.sources}, "", true, true).sha256_text()
		queue.append(source)
	payload.local_records_outbox = {"schema_version": 1, "sources": queue}
	suite.assert_true(physical.save_profile("record_owner", "base", payload).ok and service.configure(catalog, physical, "record_owner", "base").ok, "bounded retention fixture uses physical authenticated protocol")
	suite.assert_true(service.verified_local_record_outbox().ok, "all queued fixture sources independently authenticate")
	_settle(suite, service, 1000, true)
	suite.assert_equal(service.payload().local_records_outbox.sources.size(), 1000, "full optional queue stays bounded while core settlement succeeds")
	suite.assert_equal(service.payload().local_records_outbox.get("omitted_count", 0), 1, "queue overflow records its deterministic retention count")
	var retained_latest := false
	for source: Dictionary in service.payload().local_records_outbox.sources:
		retained_latest = retained_latest or source.receipt.sequence == 1001
	suite.assert_true(retained_latest, "highest-score run survives top-1000 pending retention")
	suite.assert_true(service.snapshot().last_settlement_receipt.sequence == 1001 and service.verified_local_record_outbox().ok, "overflow publishes a real authenticated settlement")
	var board_storage := Save.new()
	board_storage.configure(root.path_join("retention_boards"), "test-p20b", binding)
	var board_id := RecordRules.board_id(binding, "base")
	var consumed_source: Dictionary = queue[998]
	var consumed_board := {"schema_version": 1, "content_snapshot": binding, "save_domain": "base", "entries": [], "watermarks": {"record_owner": {"launch_sequence": 999, "run_id": consumed_source.receipt.run_id, "receipt_digest": consumed_source.receipt.digest}}}
	suite.assert_true(board_storage.save_profile(board_id, "local", {"local_run_records": consumed_board}).ok, "retention recovery fixture has actual consumed historical watermark")
	var records: RefCounted = load("res://scripts/community/local_run_records.gd").new()
	records.configure(service, root.path_join("retention_boards"), "test-p20b", binding, "base")
	suite.assert_true(records.sync_settled_run().ok, "score-ranked pending queue publishes in launch order against consumed history")
	suite.assert_true(records.snapshot().entries[0].score == 1000 and records.snapshot().entries[0].launch_sequence == 1001, "retained highest score becomes the actual physical board leader")
	suite.assert_true(service.payload().local_records_outbox.sources.is_empty() and service.payload().local_records_outbox.omitted_count == 1, "physical publication acknowledgement preserves overflow count")


func _settle(suite: RefCounted, service: RefCounted, elapsed: int, clear_room: bool = false) -> Dictionary:
	var request := {"seed": 20261005, "difficulty": "normal", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	var launched: Dictionary = service.prepare_launch(request, int(service.snapshot().revision))
	suite.assert_true(launched.ok, "record fixture launches through durable Profile service")
	if not launched.ok:
		return {}
	var state := Run.new()
	state.reset_domain(launched.context.run_config, launched.context.launch.run_id)
	var floors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/floors.json"))
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	var generated: Dictionary = Generator.new().generate(request.seed, floors[0], templates)
	state.configure_floor_plan(generated.plan, floors[0], templates)
	if clear_room:
		for edge: Dictionary in state.floor_plan.edges:
			if edge.source_node_id == state.floor_plan.current_node_id:
				suite.assert_true(state.select_floor_edge(StringName(edge.id)).ok, "score fixture selects canonical route")
				suite.assert_true(state.complete_current_floor_node(str(state.floor_plan.current_node_id)).ok, "score fixture writes typed completed-room fact")
				break
	for node: Dictionary in generated.plan.nodes:
		if node.id == generated.plan.boss_node_id: state.room_total = int(node.layer)
	state.run_time_ms = elapsed
	state.phase = Phase.Value.DEFEAT
	state.result = {"result": "death"}
	state.resources = {"meta_run_projection": launched.context.projection.duplicate(true)}
	var terminal := state.snapshot()
	suite.assert_true(service.settle_terminal(terminal, [], int(service.snapshot().revision)).ok, "record fixture settles authentic terminal")
	return terminal
