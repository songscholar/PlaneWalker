class_name ProfileRuntimeService
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const Forge := preload("res://scripts/progression/forge_runtime.gd")
const Builds := preload("res://scripts/progression/build_library.gd")
const Narrative := preload("res://scripts/narrative/narrative_runtime.gd")
const NarrativeContent := preload("res://scripts/narrative/narrative_catalog.gd")
const Tutorial := preload("res://scripts/onboarding/tutorial_runtime.gd")
const TutorialAdapter := preload("res://scripts/onboarding/tutorial_native_adapter.gd")
const TrainingAdapter := preload("res://scripts/training/training_runtime.gd")
const Run := preload("res://scripts/application/run_state.gd")
const RunConfig := preload("res://scripts/application/run_config.gd")
const Player := preload("res://scripts/player/player_controller.gd")
const Room := preload("res://scripts/dungeon/launch_room_scene.gd")
const RoomContract := preload("res://scripts/dungeon/room_scene_contract.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const SaveStorage := preload("res://scripts/save/save_service.gd")
const NativeCheckpoint := preload("res://scripts/save/native_run_checkpoint_authority.gd")
const LocalRecordRules := preload("res://scripts/community/local_run_record_rules.gd")
const CosmeticCatalogScript := preload("res://scripts/progression/cosmetic_catalog.gd")
const CosmeticRuntimeScript := preload("res://scripts/progression/cosmetic_collection_runtime.gd")
const ChallengeRewards := preload("res://scripts/progression/challenge_reward_catalog.gd")
const ModeRewards := preload("res://scripts/progression/mode_reward_authority.gd")
const OCCURRENCE_RADIUS := 48.0
const MAX_OCCURRENCES := 64
const MIRROR_FIELDS := ["chronos_shards", "existential_imprints", "unlocked_nodes", "discovered_items", "unlocked_characters", "unlocked_weapons", "weapon_proficiency", "npc_affinity", "unlocked_achievements", "cosmetics"]
const BOSS_ORDER := ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]

var _catalog: RefCounted
var _profile: RefCounted
var _settlement: RefCounted
var _save: RefCounted
var _profile_id := ""
var _save_domain := ""
var _payload: Dictionary = {}
var _busy := false
var _forge: RefCounted
var _builds: RefCounted
var _narrative: RefCounted
var _narrative_content: RefCounted
var _narrative_run: RefCounted
var _narrative_player: WeakRef
var _narrative_launch: Dictionary = {}
var _occurrences: Dictionary = {}
var _narrative_publication := false
var _narrative_recovery_pending := false
var _tutorial: RefCounted
var _tutorial_adapter: RefCounted
var _tutorial_run: RefCounted
var _tutorial_player: WeakRef
var _tutorial_publication := false
var _tutorial_recovery_pending := false
var _training_adapter: RefCounted
var _training_publication := false
var _training_recovery_pending := false
var _native_checkpoint_host: WeakRef
var _checkpoint_recovery_pending := false
var _cosmetic_catalog: RefCounted
var _cosmetic_runtime: RefCounted
var _challenge_rewards: RefCounted
var _mode_rewards: RefCounted


func configure(catalog: RefCounted, save_service: RefCounted, profile_id: String, save_domain: String, initial_payload: Dictionary = {}) -> Dictionary:
	if _busy or _narrative_publication or _tutorial_publication or _training_publication or save_service == null or not save_service.has_method("save_profile") or not save_service.has_method("load_profile") or not save_service.has_method("inspect_profile") or not Paths.validate_id(profile_id).ok or not Paths.validate_id(save_domain).ok:
		return _failure(&"CONFIGURATION_INVALID")
	if not save_service.has_method("enable_meta_profile") or not save_service.call("enable_meta_profile", catalog).ok:
		return _failure(&"CONFIGURATION_INVALID")
	var loaded = save_service.call("load_profile", profile_id, save_domain)
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		return _failure(loaded.code)
	var payload_value: Dictionary = loaded.payload if loaded.ok else initial_payload
	var state = Profile.new()
	var nested: Variant = payload_value.get("meta_profile_state", {})
	if not nested is Dictionary or not state.configure(catalog, nested) or loaded.ok and nested.is_empty():
		return _failure(&"PROFILE_INVALID")
	if not _mirrors_match(payload_value, state.snapshot()):
		return _failure(&"PROFILE_MIRROR_MISMATCH")
	var challenge_rewards := ChallengeRewards.new()
	if not challenge_rewards.configure() or not challenge_rewards.valid_collection(payload_value.get("challenge_reward_collection", challenge_rewards.empty_collection())):
		return _failure(&"MODE_REWARD_COLLECTION_INVALID")
	var settlement = Settlement.new()
	var bosses: Dictionary = {}
	for index: int in range(5):
		bosses[Envelope.FLOOR_IDS[index]] = BOSS_ORDER[index]
	if not settlement.configure(catalog, bosses):
		return _failure(&"CONFIGURATION_INVALID")
	_catalog = catalog
	_profile = state
	_settlement = settlement
	_save = save_service
	_profile_id = profile_id
	_save_domain = save_domain
	_payload = payload_value.duplicate(true)
	_forge = null
	_builds = null
	retire_narrative_occurrences()
	_narrative = null
	_narrative_content = null
	_narrative_run = null
	_narrative_player = null
	_narrative_launch.clear()
	_narrative_recovery_pending = false
	_tutorial_recovery_pending = false
	retire_tutorial_run()
	_tutorial = null
	retire_training()
	_native_checkpoint_host = null
	_checkpoint_recovery_pending = false
	_cosmetic_catalog = null
	_cosmetic_runtime = null
	_challenge_rewards = challenge_rewards
	_mode_rewards = null
	return _success({"snapshot": snapshot()})


func snapshot() -> Dictionary:
	return _profile.call("snapshot") if _profile != null else {}


func payload() -> Dictionary:
	return _payload.duplicate(true)


func configure_mode_rewards(registry: RefCounted, sources: Array) -> Dictionary:
	if _profile == null or _busy or sources.size() > 2:
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	var authority := ModeRewards.new()
	if not authority.configure(registry, local_record_storage_identity()):
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	for source: Variant in sources:
		if not source is Node or not authority.attach(source).ok:
			return _failure(&"MODE_REWARD_SOURCE_INVALID")
	_mode_rewards = authority
	return _success({})


func claim_mode_rewards(mode_id: String, expected_revision: int) -> Dictionary:
	if _mode_rewards == null or _busy or not snapshot().active_launch_receipt.is_empty():
		return _failure(&"MODE_REWARD_SOURCE_INVALID")
	if expected_revision != int(snapshot().revision):
		return _failure(&"STALE_REVISION")
	var prepared: Dictionary = _mode_rewards.prepare(mode_id, challenge_reward_collection())
	if not prepared.ok:
		return prepared
	if prepared.context.duplicate:
		return _success({"duplicate": true, "collection": challenge_reward_collection(), "aggregate": prepared.context.aggregate})
	var candidate := snapshot()
	if candidate.completed_command_ids.size() >= Profile.MAX_HISTORY or candidate.revision >= Catalog.MAX_VALUE:
		return _failure(&"TRANSACTION_LIMIT")
	if candidate.completed_command_ids.has(prepared.context.command_id):
		return _failure(&"MODE_REWARD_COLLECTION_INVALID")
	candidate.completed_command_ids.append(prepared.context.command_id)
	candidate.completed_command_ids.sort()
	candidate.revision += 1
	var ticket: Dictionary = _profile.prepare_candidate(candidate)
	if not ticket.ok:
		return ticket
	var result := _persist_ticket(ticket.context.ticket, {"challenge_reward_collection": prepared.context.collection})
	if result.ok:
		result.context["collection"] = challenge_reward_collection()
		result.context["aggregate"] = prepared.context.aggregate.duplicate(true)
	return result


func challenge_reward_collection() -> Dictionary:
	return _payload.get("challenge_reward_collection", _challenge_rewards.empty_collection()).duplicate(true) if _challenge_rewards != null else {}


func challenge_reward_view() -> Dictionary:
	var collection := challenge_reward_collection()
	var rows: Array[Dictionary] = []
	for id: String in collection.get("owned_ids", []):
		var row: Dictionary = _challenge_rewards.definition(id)
		row["equipped"] = collection.equipped_ids.has(id)
		rows.append(row)
	return {"rows": rows, "revision": int(snapshot().get("revision", 0))}


func equip_challenge_reward(id: String, equipped: bool, expected_revision: int) -> Dictionary:
	if _busy or _challenge_rewards == null or not snapshot().active_launch_receipt.is_empty():
		return _failure(&"MODE_REWARD_EQUIP_INVALID")
	if expected_revision != int(snapshot().revision):
		return _failure(&"STALE_REVISION")
	var collection := challenge_reward_collection()
	var definition: Dictionary = _challenge_rewards.definition(id)
	if definition.is_empty() or not collection.owned_ids.has(id):
		return _failure(&"MODE_REWARD_NOT_OWNED")
	if collection.equipped_ids.has(id) == equipped:
		return _success({"duplicate": true, "collection": collection})
	if equipped:
		if definition.kind != "item":
			for existing: String in collection.equipped_ids.duplicate():
				if _challenge_rewards.definition(existing).kind == definition.kind:
					collection.equipped_ids.erase(existing)
		collection.equipped_ids.append(id)
	else:
		collection.equipped_ids.erase(id)
	collection.equipped_ids.sort()
	if not _challenge_rewards.valid_collection(collection):
		return _failure(&"MODE_REWARD_COLLECTION_INVALID")
	var candidate := snapshot()
	if candidate.completed_command_ids.size() >= Profile.MAX_HISTORY or candidate.revision >= Catalog.MAX_VALUE:
		return _failure(&"TRANSACTION_LIMIT")
	candidate.completed_command_ids.append("mode-equip:%d:%s" % [int(candidate.revision), (id + str(equipped)).sha256_text().substr(0, 32)])
	candidate.completed_command_ids.sort()
	candidate.revision += 1
	var ticket: Dictionary = _profile.prepare_candidate(candidate)
	return _persist_ticket(ticket.context.ticket, {"challenge_reward_collection": collection}) if ticket.ok else ticket


func challenge_reward_projection() -> Dictionary:
	if _challenge_rewards == null:
		return _failure(&"MODE_REWARD_COLLECTION_INVALID")
	var projection: Dictionary = _challenge_rewards.projection(challenge_reward_collection(), local_record_storage_identity())
	return _success({"projection": projection}) if not projection.is_empty() else _failure(&"MODE_REWARD_COLLECTION_INVALID")


func configure_cosmetics(registry: RefCounted) -> Dictionary:
	var ready := _readiness(int(snapshot().get("revision", -1)))
	if not ready.ok:
		return ready
	if registry == null or not registry.has_method("get_catalog_entries"):
		return _failure(&"CONFIGURATION_INVALID")
	var catalog := CosmeticCatalogScript.new()
	var canonical := CosmeticCatalogScript.load_base()
	var runtime := CosmeticRuntimeScript.new()
	if not catalog.configure(registry.get_catalog_entries(&"cosmetic_definition", &"LAUNCH")).ok or canonical == null or catalog.fingerprint() != canonical.fingerprint() or not runtime.configure(catalog, _catalog):
		return _failure(&"COSMETIC_CONTENT_MISMATCH")
	if not catalog.validate_collection(_payload.get("cosmetic_collection", catalog.empty_collection()), snapshot()):
		return _failure(&"COSMETIC_COLLECTION_INVALID")
	_cosmetic_catalog = catalog
	_cosmetic_runtime = runtime
	return _success({})


func cosmetic_view(character_id: String) -> Dictionary:
	if _cosmetic_catalog == null:
		return {}
	var profile := snapshot()
	var collection: Dictionary = _payload.get("cosmetic_collection", _cosmetic_catalog.empty_collection())
	var rows: Array = []
	for definition: Dictionary in _cosmetic_catalog.for_character(character_id):
		var status: Dictionary = _cosmetic_catalog.unlock_status(definition.cosmetic_id, profile)
		var owned: bool = status.ok and (definition.unlock_route == "default" or collection.claimed_ids.has(definition.cosmetic_id))
		var equipped: bool = status.ok and _cosmetic_catalog.equipped(collection, character_id) == definition.cosmetic_id
		var available: bool = status.ok and profile.active_launch_receipt.is_empty() and not equipped
		rows.append({"id": definition.cosmetic_id, "character_id": character_id, "name_key": definition.name_key, "description_key": definition.description_key, "atlas_path": definition.atlas_path, "owned": owned, "equipped": equipped, "operation": "cosmetic_equip" if owned else "cosmetic_claim", "available": available, "reason_key": "" if available else ("HUB_LAUNCH_ACTIVE" if not profile.active_launch_receipt.is_empty() else "HUB_COSMETIC_EQUIPPED" if equipped else "HUB_" + str(status.code)), "cost": {"chronos_shards": 0, "existential_imprints": 0}})
	return {"character_id": character_id, "equipped_id": _cosmetic_catalog.equipped(collection, character_id), "rows": rows}


func equipped_cosmetic(character_id: String) -> String:
	return _cosmetic_catalog.equipped(_payload.get("cosmetic_collection", _cosmetic_catalog.empty_collection()), character_id) if _cosmetic_catalog != null else character_id + ".default"


func execute_cosmetic(command: Dictionary, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	if _cosmetic_runtime == null:
		return _failure(&"COSMETICS_NOT_CONFIGURED")
	var produced: Dictionary = _cosmetic_runtime.prepare(snapshot(), _payload.get("cosmetic_collection", _cosmetic_catalog.empty_collection()), command, expected_revision)
	if not produced.ok:
		return produced
	var prepared: Dictionary = _profile.prepare_candidate(produced.context.candidate)
	if not prepared.ok:
		return prepared
	return _persist_ticket(prepared.context.ticket, {"cosmetic_collection": produced.context.collection})


func frozen_launch_projection() -> Dictionary:
	var profile := snapshot()
	var projection: Variant = _payload.get("pending_meta_run_projection")
	if profile.is_empty() or profile.active_launch_receipt.is_empty() or not projection is Dictionary or not MetaProjection.validate(projection, _catalog) or projection.projection_digest != profile.active_launch_receipt.projection_digest:
		return {}
	if projection.has("challenge_reward_projection") and not _json_equal(projection.challenge_reward_projection, _challenge_rewards.projection(challenge_reward_collection(), local_record_storage_identity())):
		return {}
	return projection.duplicate(true)


func pending_launch_config() -> Dictionary:
	var profile := snapshot()
	var value: Variant = _payload.get("pending_run_config")
	if profile.is_empty() or profile.active_launch_receipt.is_empty() or not value is Dictionary or not _canonical_launch_config_fields(value):
		return {}
	return _validated_launch_config(value, profile.active_launch_receipt, true)


func retain_active_run(run: RefCounted, player: Node, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	if _narrative_recovery_pending or _tutorial_recovery_pending:
		return _failure(&"NATIVE_PUBLICATION_PENDING")
	if not run is Run or not is_instance_valid(player) or not player is Player or not player.is_inside_tree():
		return _failure(&"NATIVE_BINDING_INVALID")
	var before := snapshot()
	var launch: Dictionary = before.active_launch_receipt
	var run_before: Dictionary = run.snapshot()
	var player_before: Dictionary = player.reward_effect_snapshot()
	var player_stamp := _native_player_stamp(player)
	if launch.is_empty() or not _player_matches_launch(player, launch, run_before) or not _settlement.verified_run_sources(launch, run_before).ok or not Replay.validate_full_player_reward_effect_state(player_before) or _clone_native_run(run, run_before) == null:
		return _failure(&"NATIVE_CHECKPOINT_INVALID")
	if before.revision == Catalog.MAX_VALUE:
		return _failure(&"TRANSACTION_LIMIT")
	var candidate := before.duplicate(true)
	candidate.revision += 1
	var prepared: Dictionary = _profile.prepare_candidate(candidate)
	if not prepared.ok:
		return prepared
	var persisted := _persist_ticket(prepared.context.ticket, {"active_run_state": run_before, "reward_effect_state": player_before})
	if persisted.ok and (not is_instance_valid(player) or player.reward_effect_snapshot() != player_before or _native_player_stamp(player) != player_stamp or run.snapshot() != run_before):
		_narrative_recovery_pending = true
		return _failure(&"NATIVE_PUBLICATION_PENDING")
	return persisted


func retain_native_checkpoint(host: Node, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var captured := NativeCheckpoint.capture(host)
	if not captured.ok:
		return captured
	var participants: Dictionary = host.native_checkpoint_participants()
	var run: RefCounted = host.native_run_state()
	var player: Node = participants.player
	var before := snapshot()
	var launch := _launch_for_run(captured.context.run)
	if participants.profile != self or launch.is_empty():
		return {"ok": false, "code": &"NATIVE_CHECKPOINT_INVALID", "context": {"stage": "profile_binding"}}
	if not _player_matches_launch(player, launch, captured.context.run):
		return {"ok": false, "code": &"NATIVE_CHECKPOINT_INVALID", "context": {"stage": "player_launch"}}
	var sources: Dictionary = _settlement.verified_run_sources(launch, captured.context.run)
	if not sources.ok or _clone_native_run(run, captured.context.run) == null:
		return {"ok": false, "code": &"NATIVE_CHECKPOINT_INVALID", "context": {"stage": "run_validation", "sources": sources}}
	if before.revision == Catalog.MAX_VALUE:
		return _failure(&"TRANSACTION_LIMIT")
	var candidate := before.duplicate(true)
	candidate.revision += 1
	var prepared: Dictionary = _profile.prepare_candidate(candidate)
	if not prepared.ok:
		return prepared
	var persisted := _persist_ticket(prepared.context.ticket, {"active_run_state": captured.context.run, "reward_effect_state": captured.context.reward, "native_run_checkpoint": captured.context.checkpoint})
	if persisted.ok:
		var after := NativeCheckpoint.capture(host)
		if not after.ok or after.context != captured.context:
			_narrative_recovery_pending = true
			return _failure(&"NATIVE_PUBLICATION_PENDING")
		persisted.context["checkpoint_digest"] = captured.context.checkpoint.digest
		bind_native_checkpoint_host(host)
	return persisted


func bind_native_checkpoint_host(host: Node) -> bool:
	if not NativeCheckpoint._native_host(host) or not host.is_inside_tree() or host.native_checkpoint_participants().profile != self or host.native_run_state() == null:
		return false
	_native_checkpoint_host = weakref(host)
	return true


func authenticated_native_checkpoint(expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var primary = _save.inspect_profile(_profile_id, _save_domain)
	if not primary.ok or not _json_equal(primary.payload.payload, _with_runtime_defaults(_payload)):
		return _failure(&"STALE_DURABLE_PROFILE")
	var checkpoint: Variant = _payload.get("native_run_checkpoint", {})
	var run_value: Variant = _payload.get("active_run_state", {})
	var reward_value: Variant = _payload.get("reward_effect_state", {})
	if not checkpoint is Dictionary or checkpoint.is_empty():
		return _failure(&"NATIVE_CHECKPOINT_NOT_AVAILABLE")
	if not run_value is Dictionary or not reward_value is Dictionary:
		return _failure(&"NATIVE_CHECKPOINT_INVALID")
	var valid := NativeCheckpoint.validate(checkpoint, run_value, reward_value)
	if not valid.ok:
		return valid
	var launch := _launch_for_run(run_value)
	if launch.is_empty() or not _json_equal(launch, checkpoint.launch_receipt) or not _settlement.verified_run_sources(launch, run_value).ok:
		return _failure(&"NATIVE_CHECKPOINT_INVALID")
	return _success({"checkpoint": checkpoint.duplicate(true), "run": run_value.duplicate(true), "replay": valid.context.replay.duplicate(true), "native": valid.context.native.duplicate(true)})


func authenticated_active_run(expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var primary = _save.inspect_profile(_profile_id, _save_domain)
	if not primary.ok or not _json_equal(primary.payload.payload, _with_runtime_defaults(_payload)):
		return _failure(&"STALE_DURABLE_PROFILE")
	var run_value: Variant = _payload.get("active_run_state", {})
	if not run_value is Dictionary or run_value.is_empty():
		return _failure(&"ACTIVE_RUN_INVALID")
	var launch := _launch_for_run(run_value)
	if launch.is_empty() or not _settlement.verified_run_sources(launch, run_value).ok:
		return _failure(&"ACTIVE_RUN_INVALID")
	return _success({"run": run_value.duplicate(true), "launch": launch})


func verified_settled_run() -> Dictionary:
	var ready := _readiness(int(snapshot().get("revision", -1)))
	if not ready.ok:
		return ready
	var profile := snapshot()
	if not profile.active_launch_receipt.is_empty() or profile.last_settlement_receipt.is_empty():
		return _failure(&"NO_SETTLED_RUN")
	var primary = _save.inspect_profile(_profile_id, _save_domain)
	if not primary.ok or not _json_equal(primary.payload.payload, _with_runtime_defaults(_payload)):
		return _failure(&"STALE_DURABLE_PROFILE")
	var terminal: Dictionary = _payload.get("active_run_state", {})
	var receipt: Dictionary = profile.last_settlement_receipt
	if receipt.terminal_reason == "abandon":
		return _failure(&"NO_SETTLED_RUN")
	return _verified_local_record_source({"profile_id": _profile_id, "save_domain": _save_domain, "content_snapshot": primary.payload.content_snapshot, "terminal": terminal, "launch": _launch_for_run(terminal), "receipt": receipt})


func local_record_storage_identity() -> Dictionary:
	return {"profile_id": _profile_id, "save_domain": _save_domain, "content_snapshot": _save.configured_content_snapshot()} if _save != null else {}


func verified_local_record_outbox() -> Dictionary:
	var ready := _readiness(int(snapshot().get("revision", -1)))
	if not ready.ok:
		return ready
	var primary = _save.inspect_profile(_profile_id, _save_domain)
	if primary.code == &"NOT_FOUND" and not _payload.has("local_records_outbox"):
		return _success({"sources": []})
	if not primary.ok or not _json_equal(primary.payload.payload, _with_runtime_defaults(_payload)):
		return _failure(&"STALE_DURABLE_PROFILE")
	var outbox: Variant = _payload.get("local_records_outbox", {"schema_version": 1, "sources": []})
	if not (Catalog.exact_fields(outbox, ["schema_version", "sources"]) or Catalog.exact_fields(outbox, ["schema_version", "sources", "omitted_count"])) or not Catalog.bounded_int(outbox.schema_version, 1, 1) or not outbox.sources is Array or outbox.sources.size() > LocalRecordRules.MAX_ENTRIES or not Catalog.bounded_int(outbox.get("omitted_count", 0), 0, Catalog.MAX_VALUE):
		return _failure(&"RECORD_OUTBOX_INVALID")
	var verified_sources: Array = []
	var seen: Dictionary = {}
	for value: Variant in outbox.sources:
		var verified := _verified_local_record_source(value)
		if not verified.ok:
			return verified
		var identity: String = verified.context.receipt.run_id
		if seen.has(identity):
			return _failure(&"RECORD_OUTBOX_INVALID")
		seen[identity] = true
		verified_sources.append(verified.context)
	if verified_sources.is_empty() and not _payload.has("local_records_outbox"):
		var last := verified_settled_run()
		if last.ok:
			verified_sources.append(last.context)
		elif last.code != &"NO_SETTLED_RUN":
			return last
	verified_sources.sort_custom(func(left: Dictionary, right: Dictionary): return left.receipt.sequence < right.receipt.sequence)
	return _success({"sources": verified_sources, "omitted_count": int(outbox.get("omitted_count", 0))})


func acknowledge_local_records(board_storage: RefCounted, board_id: String) -> Dictionary:
	if not board_storage is SaveStorage or not Paths.validate_id(board_id).ok:
		return _failure(&"RECORD_ACK_INVALID")
	var authenticated := verified_local_record_outbox()
	if not authenticated.ok:
		return authenticated
	var outbox: Dictionary = _payload.get("local_records_outbox", {})
	if outbox.is_empty() or outbox.sources.is_empty():
		return _success({"acknowledged": 0})
	var board_primary = board_storage.inspect_profile(board_id, "local")
	if not board_primary.ok:
		return _failure(&"RECORD_ACK_INVALID")
	var board: Variant = board_primary.payload.payload.get("local_run_records")
	if not LocalRecordRules.valid_board(board, board_primary.payload.content_snapshot, _save_domain) or board_id != LocalRecordRules.board_id(board_primary.payload.content_snapshot, _save_domain):
		return _failure(&"RECORD_ACK_INVALID")
	var watermark: Variant = board.watermarks.get(_profile_id, {})
	if not Catalog.exact_fields(watermark, ["launch_sequence", "run_id", "receipt_digest"]) or not Catalog.bounded_int(watermark.launch_sequence, 1, int(snapshot().launch_sequence)):
		return _failure(&"RECORD_ACK_INVALID")
	var watermark_authenticated := false
	for source: Dictionary in authenticated.context.sources:
		watermark_authenticated = watermark_authenticated or (_json_equal(source.content_snapshot, board.content_snapshot) and source.receipt.sequence == watermark.launch_sequence and source.receipt.run_id == watermark.run_id and source.receipt.digest == watermark.receipt_digest)
	if not watermark_authenticated:
		return _failure(&"RECORD_ACK_INVALID")
	var remaining: Array = []
	for source: Dictionary in outbox.sources:
		var consumed: bool = _json_equal(source.content_snapshot, board.content_snapshot) and (source.receipt.sequence < watermark.launch_sequence or source.receipt.sequence == watermark.launch_sequence and source.receipt.run_id == watermark.run_id and source.receipt.digest == watermark.receipt_digest)
		if not consumed:
			remaining.append(source.duplicate(true))
	var acknowledged: int = outbox.sources.size() - remaining.size()
	if acknowledged == 0:
		return _success({"acknowledged": 0})
	var primary = _save.inspect_profile(_profile_id, _save_domain)
	if not primary.ok or not _json_equal(primary.payload.payload, _with_runtime_defaults(_payload)):
		return _failure(&"STALE_DURABLE_PROFILE")
	var candidate := _payload.duplicate(true)
	candidate.local_records_outbox = {"schema_version": 1, "sources": remaining, "omitted_count": authenticated.context.get("omitted_count", 0)}
	_busy = true
	var written = _save.save_profile_compare_exchange(_profile_id, _save_domain, candidate, primary.payload)
	if not written.ok:
		var actual = _save.inspect_profile(_profile_id, _save_domain)
		if not actual.ok or not _json_equal(actual.payload.payload, _with_runtime_defaults(candidate)):
			_busy = false
			return _failure(written.code)
	_payload = _with_runtime_defaults(candidate)
	_busy = false
	return _success({"acknowledged": acknowledged})


func _verified_local_record_source(value: Variant) -> Dictionary:
	if not Catalog.exact_fields(value, ["profile_id", "save_domain", "content_snapshot", "terminal", "launch", "receipt"]) or value.profile_id != _profile_id or value.save_domain != _save_domain or not value.terminal is Dictionary or not value.launch is Dictionary or not value.receipt is Dictionary or not Catalog.exact_fields(value.receipt, ["schema_id", "sequence", "run_id", "terminal_reason", "shards", "imprints", "soul_reserve", "digest"]):
		return _failure(&"RECORD_OUTBOX_INVALID")
	var binding = Envelope.create_profile(_profile_id, _save_domain, 0, "local-record", "2000-01-01T00:00:00Z", "2000-01-01T00:00:00Z", value.content_snapshot, {})
	var normalized = Envelope.validate_active_run_snapshot(value.terminal, _catalog)
	if not binding.ok or not normalized.ok or normalized.payload.is_empty():
		return _failure(&"SETTLED_RUN_INVALID")
	var terminal: Dictionary = normalized.payload
	var launch: Dictionary = value.launch
	var receipt: Dictionary = value.receipt
	var facts: Dictionary = _settlement.verified_terminal_facts(launch, terminal)
	var sources: Dictionary = _settlement.verified_run_sources(launch, terminal)
	if not facts.ok or not sources.ok or receipt.schema_id != "meta_settlement_receipt_v1" or not Catalog.bounded_int(receipt.sequence, 1, int(snapshot().launch_sequence)) or receipt.run_id != "meta-run-%s-%d" % [_profile_id, int(receipt.sequence)] or receipt.run_id != facts.context.run_id or receipt.sequence != facts.context.launch_sequence or receipt.terminal_reason != facts.context.terminal_reason:
		return _failure(&"SETTLED_RUN_INVALID")
	for field: String in ["shards", "imprints", "soul_reserve"]:
		if not Catalog.bounded_int(receipt[field], 0, Catalog.MAX_VALUE):
			return _failure(&"SETTLED_RUN_INVALID")
	var unsigned := receipt.duplicate(true)
	unsigned.erase("digest")
	for field: String in ["sequence", "shards", "imprints", "soul_reserve"]:
		unsigned[field] = int(unsigned[field])
	var digest := JSON.stringify({"receipt": unsigned, "projection_digest": launch.projection_digest, "sources": sources.context.sources}, "", true, true).sha256_text()
	if receipt.digest != digest:
		return _failure(&"SETTLEMENT_DIGEST_INVALID")
	if receipt.sequence == snapshot().last_settlement_receipt.get("sequence", -1) and not _json_equal(receipt, snapshot().last_settlement_receipt):
		return _failure(&"SETTLED_RUN_INVALID")
	var normalized_receipt := unsigned.duplicate(true)
	normalized_receipt["digest"] = receipt.digest
	return _success({"profile_id": _profile_id, "save_domain": _save_domain, "content_snapshot": binding.payload.content_snapshot, "terminal": terminal, "config": terminal.config, "receipt": normalized_receipt, "launch": launch, "facts": facts.context})


func enable_workshop(entries: Array) -> Dictionary:
	if _profile == null or _busy or _narrative_publication or _tutorial_publication or _training_publication:
		return _failure(&"NOT_CONFIGURED")
	var forge = Forge.new()
	var configured: Dictionary = forge.configure(entries, _catalog)
	var builds = Builds.new()
	if not configured.ok or not builds.configure(_catalog):
		return _failure(&"WORKSHOP_CONTENT_INVALID")
	_forge = forge
	_builds = builds
	return _success({})


func forge_projection(weapon_id: String) -> Dictionary:
	return _forge.call("weapon_projection", snapshot(), weapon_id) if _forge != null else {}


func resolve_build(build_id: String) -> Dictionary:
	return _builds.call("resolve", snapshot(), build_id) if _builds != null else _failure(&"WORKSHOP_NOT_CONFIGURED")


func enable_tutorial(entries: Array) -> Dictionary:
	if _profile == null or _busy or _narrative_publication or _tutorial_publication or _training_publication or _tutorial_recovery_pending:
		return _failure(&"NOT_CONFIGURED")
	var runtime := Tutorial.new()
	var configured := runtime.configure(entries, _catalog)
	if not configured.ok:
		return configured
	retire_tutorial_run()
	_tutorial = runtime
	return _success({})


func tutorial_progress_view() -> Dictionary:
	return _tutorial.progress_view(snapshot()) if _tutorial != null else _failure(&"TUTORIAL_NOT_CONFIGURED")


func bind_training(player: Node, task_id: String, seed: int, boss: Node = null) -> Dictionary:
	if _tutorial == null or _busy or _training_publication or _narrative_publication or _tutorial_publication or _narrative_recovery_pending or _tutorial_recovery_pending or not snapshot().active_launch_receipt.is_empty():
		return _failure(&"TRAINING_BINDING_INVALID")
	var drill: Dictionary = _tutorial.training_definition(task_id)
	if drill.is_empty():
		return _failure(&"TRAINING_TASK_INVALID")
	if task_id == "T-05" and boss == null:
		return _failure(&"TRAINING_BOSS_UNAVAILABLE")
	var decoded: Dictionary = _tutorial.progress_view(snapshot())
	if not decoded.ok:
		return decoded
	var sequence := int(decoded.context.watermarks.get("training_drill", {}).get("session_sequence", 0)) + 1
	var adapter := TrainingAdapter.new()
	if not adapter.configure(player, {"session_sequence": sequence, "seed": seed}, drill, boss):
		return _failure(&"TRAINING_BINDING_INVALID")
	retire_training()
	_training_adapter = adapter
	return _success({"adapter": adapter})


func observe_training(adapter: RefCounted, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	if adapter == null or adapter != _training_adapter or _tutorial == null or not snapshot().active_launch_receipt.is_empty():
		return _failure(&"TRAINING_BINDING_INVALID")
	var observation: Dictionary = adapter.prepared_observation(snapshot())
	var checkpoint: Dictionary = adapter.native_checkpoint()
	if not observation.ok or checkpoint.is_empty():
		return _failure(&"TRAINING_OBSERVATION_UNAVAILABLE")
	var produced: Dictionary = _tutorial.prepare_observation(snapshot(), observation.context.receipt, expected_revision, adapter.task_id())
	if not produced.ok:
		return produced
	var prepared: Dictionary = _profile.prepare_candidate(produced.context.candidate)
	if not prepared.ok:
		return prepared
	_training_publication = true
	var persisted := _persist_ticket(prepared.context.ticket)
	if persisted.ok:
		if adapter.native_checkpoint() != checkpoint or not adapter.can_confirm_saved(observation.context.receipt, observation.context.seal):
			_training_recovery_pending = true
			_training_publication = false
			return _failure(&"NATIVE_PUBLICATION_PENDING")
		var confirmed: Dictionary = adapter.confirm_saved(observation.context.receipt, observation.context.seal)
		if not confirmed.ok or adapter.native_checkpoint() != checkpoint:
			_training_recovery_pending = true
			_training_publication = false
			return _failure(&"NATIVE_PUBLICATION_PENDING")
		persisted.context.completed_tasks = produced.context.completed_tasks.duplicate()
		persisted.context.receipt = observation.context.receipt.duplicate(true)
		persisted.context.consumed = true
	_training_publication = false
	return persisted


func retire_training() -> void:
	if _busy or _training_publication:
		return
	if _training_adapter != null:
		_training_adapter.detach()
	_training_adapter = null
	_training_recovery_pending = false


func bind_tutorial_run(run: RefCounted, player: Node) -> Dictionary:
	if _tutorial == null or _busy or _narrative_publication or _tutorial_publication or _training_publication or _tutorial_recovery_pending or not run is Run or not is_instance_valid(player) or not player is Player or not player.is_inside_tree():
		return _failure(&"TUTORIAL_BINDING_INVALID")
	var launch: Dictionary = snapshot().active_launch_receipt
	var state: Dictionary = run.snapshot()
	if launch.is_empty() or not _player_matches_launch(player, launch, state) or player.full_player_replay_snapshot().is_empty() or not _settlement.verified_run_sources(launch, state).ok or not Replay.validate_full_player_reward_effect_state(player.reward_effect_snapshot()) or _clone_native_run(run, state) == null:
		return _failure(&"TUTORIAL_BINDING_INVALID")
	var adapter := TutorialAdapter.new()
	var bound := adapter.bind_normal_run(snapshot(), run, player, _tutorial.content_catalog())
	if not bound.ok:
		return bound
	retire_tutorial_run()
	_tutorial_adapter = adapter
	_tutorial_run = run
	_tutorial_player = weakref(player)
	return {"ok": true, "code": &"OK", "context": {"adapter": adapter}}


func execute_tutorial(command: Dictionary, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	if _tutorial == null:
		return _failure(&"TUTORIAL_NOT_CONFIGURED")
	if _tutorial_recovery_pending or _narrative_recovery_pending:
		return _failure(&"NATIVE_PUBLICATION_PENDING")
	var produced: Dictionary = _tutorial.prepare_command(snapshot(), command, expected_revision)
	if not produced.ok:
		return produced
	return _persist_tutorial(produced, _tutorial_native_checkpoint() if _tutorial_adapter != null else {})


func observe_tutorial(adapter: RefCounted, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	if _tutorial == null or adapter == null or adapter != _tutorial_adapter:
		return _failure(&"TUTORIAL_BINDING_INVALID")
	if _tutorial_recovery_pending or _narrative_recovery_pending:
		return _failure(&"NATIVE_PUBLICATION_PENDING")
	var observation: Dictionary = adapter.prepared_observation(snapshot())
	if not observation.ok:
		return observation
	var checkpoint := _tutorial_native_checkpoint()
	if checkpoint.is_empty():
		return _failure(&"TUTORIAL_BINDING_INVALID")
	var produced: Dictionary = _tutorial.prepare_observation(snapshot(), observation.context.receipt, expected_revision)
	if not produced.ok:
		return produced
	return _persist_tutorial(produced, checkpoint, observation.context)


func restore_tutorial_run() -> Dictionary:
	if _tutorial == null or _tutorial_run == null or _tutorial_player == null or _busy or _narrative_publication or _tutorial_publication or _training_publication:
		return _failure(&"TUTORIAL_BINDING_INVALID")
	var run: RefCounted = _tutorial_run
	var player: Node = _tutorial_player.get_ref()
	var restored := restore_active_run(run, player)
	if not restored.ok:
		return restored
	retire_tutorial_run()
	return bind_tutorial_run(run, player)


func retire_tutorial_run() -> void:
	if _busy or _narrative_publication or _tutorial_publication or _training_publication or _tutorial_recovery_pending:
		return
	if _tutorial_adapter != null:
		_tutorial_adapter.detach()
	_tutorial_adapter = null
	_tutorial_run = null
	_tutorial_player = null


func _tutorial_native_checkpoint() -> Dictionary:
	var player: Node = _tutorial_player.get_ref() if _tutorial_player != null else null
	var launch: Dictionary = snapshot().active_launch_receipt
	if _tutorial_run == null or launch.is_empty() or not is_instance_valid(player) or not player.is_inside_tree():
		return {}
	var host: Node = _native_checkpoint_host.get_ref() if _native_checkpoint_host != null else null
	var state: Dictionary = host.runtime_snapshot() if is_instance_valid(host) and host.native_run_state() == _tutorial_run else _tutorial_run.snapshot()
	var reward: Dictionary = player.reward_effect_snapshot()
	var native_frame: Dictionary = player.full_player_replay_snapshot()
	if not _player_matches_launch(player, launch, state) or native_frame.is_empty() or not _settlement.verified_run_sources(launch, state).ok or not Replay.validate_full_player_reward_effect_state(reward) or _clone_native_run(_tutorial_run, state) == null:
		return {}
	return {"active_run_state": state, "reward_effect_state": reward, "native_frame": native_frame, "player_id": player.get_instance_id(), "run_id": _tutorial_run.get_instance_id()}


func _persist_tutorial(produced: Dictionary, checkpoint: Dictionary, observation: Dictionary = {}) -> Dictionary:
	if _tutorial_adapter != null and checkpoint.is_empty():
		return _failure(&"TUTORIAL_BINDING_INVALID")
	var prepared: Dictionary = _profile.prepare_candidate(produced.context.candidate)
	if not prepared.ok:
		return prepared
	var changes: Dictionary = {}
	if not checkpoint.is_empty():
		changes = {"active_run_state": checkpoint.active_run_state, "reward_effect_state": checkpoint.reward_effect_state}
	_tutorial_publication = true
	var persisted := _persist_ticket(prepared.context.ticket, changes)
	if persisted.ok and not checkpoint.is_empty():
		if _tutorial_native_checkpoint() != checkpoint or not observation.is_empty() and not _tutorial_adapter.can_confirm_saved(observation.receipt, observation.seal):
			_tutorial_recovery_pending = true
			_tutorial_publication = false
			return _failure(&"NATIVE_PUBLICATION_PENDING")
		if not observation.is_empty():
			var confirmed: Dictionary = _tutorial_adapter.confirm_saved(observation.receipt, observation.seal)
			if not confirmed.ok or _tutorial_native_checkpoint() != checkpoint:
				_tutorial_recovery_pending = true
				_tutorial_publication = false
				return _failure(&"NATIVE_PUBLICATION_PENDING")
	_tutorial_publication = false
	if persisted.ok:
		var receipt: Dictionary = produced.context.duplicate(true)
		receipt.erase("candidate")
		persisted.context.merge(receipt, false)
		if not observation.is_empty():
			persisted.context.receipt = observation.receipt.duplicate(true)
	return persisted


func enable_narrative(entries: Array, sources: Array) -> Dictionary:
	if _profile == null or _busy or _narrative_publication or _tutorial_publication or _training_publication:
		return _failure(&"NOT_CONFIGURED")
	var runtime := Narrative.new()
	var content := NarrativeContent.new()
	var configured := runtime.configure(entries, sources, _catalog)
	if not configured.ok or not content.configure(entries, _catalog, sources).ok:
		return _failure(&"NARRATIVE_CONTENT_INVALID")
	retire_narrative_occurrences()
	_narrative = runtime
	_narrative_content = content
	return _success({})


func bind_narrative_run(run: RefCounted, player: Node) -> Dictionary:
	if _narrative == null or _busy or _narrative_publication or _tutorial_publication or _training_publication or not run is Run or not is_instance_valid(player) or not player is Player or not player.is_inside_tree():
		return _failure(&"NARRATIVE_BINDING_INVALID")
	var launch := _launch_for_run(run.snapshot())
	if launch.is_empty() or not _player_matches_launch(player, launch, run.snapshot()) or not _settlement.verified_run_sources(launch, run.snapshot()).ok or not Replay.validate_full_player_reward_effect_state(player.reward_effect_snapshot()):
		return _failure(&"NARRATIVE_BINDING_INVALID")
	retire_narrative_occurrences()
	_narrative_run = run
	_narrative_player = weakref(player)
	_narrative_launch = launch
	_narrative_recovery_pending = not _payload.get("reward_effect_state", {}).is_empty() and (_payload.get("reward_effect_state") != player.reward_effect_snapshot() or _payload.get("active_run_state") != run.snapshot())
	return _success({})


func install_narrative_occurrence(kind: String, id: String, room: Node2D, template: Dictionary, anchor_id: String, runtime_parent: Node2D) -> Dictionary:
	if _narrative == null or _busy or _narrative_publication or _tutorial_publication or _training_publication or _occurrences.size() >= MAX_OCCURRENCES or not _native_narrative_active(kind == "collect") or not room is Room or not is_instance_valid(runtime_parent) or not runtime_parent.is_inside_tree() or runtime_parent == room or room.is_ancestor_of(runtime_parent):
		return _failure(&"OCCURRENCE_INVALID")
	var definition := _occurrence_definition(kind, id)
	var node: Dictionary = _narrative_run.current_floor_node()
	var binding: Dictionary = room.binding_snapshot()
	var verified := RoomContract.validate(room, template)
	if definition.is_empty() or definition.floor_id != _narrative_run.floor_plan.floor_id or not verified.ok or not room.is_inside_tree() or not binding.bound or not binding.active or binding.binding.node_id != node.id or binding.binding.floor_id != definition.floor_id or binding.binding.content_id != node.template_id or template.id != node.template_id:
		return _failure(&"OCCURRENCE_INVALID")
	var anchor := room.get_node_or_null("InteractionAnchors/" + anchor_id) as Marker2D
	if anchor == null or str(anchor.get_meta("anchor_id", "")) != anchor_id or not anchor.global_position.is_finite():
		return _failure(&"OCCURRENCE_INVALID")
	var token := Area2D.new()
	var player: Node = _narrative_player.get_ref()
	token.name = "NarrativeOccurrence"
	token.collision_layer = 0
	token.collision_mask = player.collision_layer
	token.monitorable = false
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = OCCURRENCE_RADIUS
	collision.shape = shape
	token.add_child(collision)
	runtime_parent.add_child(token)
	token.global_position = anchor.global_position
	_occurrences[token.get_instance_id()] = {"token": weakref(token), "room": weakref(room), "parent": weakref(runtime_parent), "anchor": weakref(anchor), "kind": kind, "id": id, "template": template.duplicate(true), "node_id": node.id, "floor_id": definition.floor_id, "binding": binding.duplicate(true), "room_transform": room.global_transform, "position": anchor.global_position, "shape": shape, "collision": weakref(collision), "player_layer": player.collision_layer}
	return {"ok": true, "code": &"OK", "context": {"occurrence": token}}


func retire_narrative_occurrences() -> void:
	for record: Dictionary in _occurrences.values():
		var token: Node = record.token.get_ref()
		if is_instance_valid(token):
			token.queue_free()
	_occurrences.clear()


func narrative_dialogue_view(npc_id: String) -> Dictionary:
	return _narrative.dialogue_view(snapshot(), npc_id) if _narrative != null else _failure(&"NARRATIVE_NOT_CONFIGURED")


func narrative_ending_view() -> Dictionary:
	if _narrative == null:
		return _failure(&"NARRATIVE_NOT_CONFIGURED")
	if _narrative_recovery_pending:
		return _failure(&"NATIVE_PUBLICATION_PENDING")
	var facts := _native_terminal_facts()
	return _narrative.ending_view(snapshot(), facts.context if facts.ok else {})


func execute_narrative(command: Dictionary, expected_revision: int, occurrence: Area2D = null) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	if _narrative == null:
		return _failure(&"NARRATIVE_NOT_CONFIGURED")
	if _narrative_recovery_pending:
		return _failure(&"NATIVE_PUBLICATION_PENDING")
	var context: Dictionary = {}
	var kind: Variant = command.get("kind")
	if kind in ["narrative_collect", "narrative_choice"]:
		if not _occurrence_matches(command, occurrence):
			return _failure(&"OCCURRENCE_INVALID")
		context = _native_narrative_context(kind == "narrative_collect")
		if context.is_empty():
			return _failure(&"NATIVE_CONTEXT_INVALID")
	elif kind == "narrative_ending":
		var facts := _native_terminal_facts()
		if not facts.ok:
			return facts
		context = facts.context
	elif occurrence != null:
		return _failure(&"OCCURRENCE_INVALID")
	var produced: Dictionary = _narrative.prepare_command(snapshot(), command, expected_revision, context)
	if not produced.ok or produced.context.get("deferred", false):
		return produced
	var prepared: Dictionary = _profile.prepare_candidate(produced.context.candidate)
	if not prepared.ok:
		return prepared
	var receipt: Dictionary = produced.context.duplicate(true)
	receipt.erase("candidate")
	var payload_changes: Dictionary = {}
	var player_before: Dictionary = {}
	var player_stamp: Dictionary = {}
	var player_after: Dictionary = {}
	var run_before: Dictionary = {}
	var run_after: Dictionary = {}
	if kind in ["narrative_collect", "narrative_choice", "narrative_ending"] and _narrative_run != null:
		var native_player: Node = _narrative_player.get_ref() if _narrative_player != null else null
		run_before = _narrative_run.snapshot()
		if not is_instance_valid(native_player) or not _player_matches_launch(native_player, _narrative_launch, run_before):
			_profile.discard_candidate(prepared.context.ticket)
			return _failure(&"NATIVE_BINDING_INVALID")
		player_before = native_player.reward_effect_snapshot()
		player_stamp = _native_player_stamp(native_player)
		payload_changes.active_run_state = run_before
		payload_changes.reward_effect_state = player_before
	var effect: Dictionary = produced.context.get("run_effect", {})
	if not effect.is_empty():
		var player: Node = _narrative_player.get_ref()
		player_after = player_before.duplicate(true)
		player_after.stats.max_hp = effect.after.max_hp
		player_after.health.max_hp = effect.after.max_hp
		player_after.health.current_hp = effect.after.current_hp
		if not player.can_restore_reward_effect_snapshot(player_after) or not Replay.validate_full_player_reward_effect_state(player_after):
			_profile.discard_candidate(prepared.context.ticket)
			return _failure(&"NATIVE_EFFECT_INVALID")
		var clone := _clone_narrative_run(run_before)
		if clone == null:
			_profile.discard_candidate(prepared.context.ticket)
			return _failure(&"NATIVE_RUN_SNAPSHOT_INVALID")
		if not clone.dungeon_event_runtime.is_empty() and not clone.observe_player_health(player_after.health.current_hp, player_after.health.max_hp):
			_profile.discard_candidate(prepared.context.ticket)
			return _failure(&"NATIVE_HEALTH_SYNC_INVALID")
		clone.advance_revision()
		run_after = clone.snapshot()
		if not Envelope.validate_active_run_snapshot(run_after, _catalog).ok:
			_profile.discard_candidate(prepared.context.ticket)
			return _failure(&"NATIVE_RUN_ENVELOPE_INVALID")
		payload_changes.active_run_state = run_after
		payload_changes.reward_effect_state = player_after
	_narrative_publication = true
	if not player_after.is_empty() and not _payload.get("native_run_checkpoint", {}).is_empty():
		# Capture the validated effect from native participants, then restore before the physical write.
		var native_player: Node = _narrative_player.get_ref()
		var full_before: Dictionary = native_player.full_player_replay_snapshot()
		var staged: bool = native_player.restore_reward_effect_snapshot(player_after, false) and _restore_bound_run(run_after)
		var synchronized := _checkpoint_changes(payload_changes) if staged else _failure(&"NATIVE_EFFECT_INVALID")
		var compensated: bool = native_player.restore_reward_effect_snapshot(player_before, false) and _restore_bound_run(run_before) and native_player.full_player_replay_snapshot() == full_before and _narrative_run.snapshot() == run_before
		if not synchronized.ok or not compensated:
			_profile.discard_candidate(prepared.context.ticket)
			_narrative_publication = false
			if not compensated:
				_narrative_recovery_pending = true
			return synchronized if compensated else _failure(&"NATIVE_PUBLICATION_PENDING")
		payload_changes = synchronized.context.changes
	var persisted := _persist_ticket(prepared.context.ticket, payload_changes)
	if persisted.ok and not run_before.is_empty():
		var player: Node = _narrative_player.get_ref() if _narrative_player != null else null
		if not is_instance_valid(player) or player.reward_effect_snapshot() != player_before or _native_player_stamp(player) != player_stamp or _narrative_run.snapshot() != run_before:
			_narrative_publication = false
			_narrative_recovery_pending = true
			return _failure(&"NATIVE_PUBLICATION_PENDING")
		if not player_after.is_empty() and (not player.restore_reward_effect_snapshot(player_after, false) or not _restore_bound_run(run_after)):
			_narrative_publication = false
			_narrative_recovery_pending = true
			return _failure(&"NATIVE_PUBLICATION_PENDING")
		if payload_changes.has("native_run_checkpoint"):
			var host: Node = _native_checkpoint_host.get_ref() if _native_checkpoint_host != null else null
			var current := NativeCheckpoint.capture(host)
			if not current.ok or current.context.checkpoint != payload_changes.native_run_checkpoint:
				_narrative_publication = false
				_narrative_recovery_pending = true
				return _failure(&"NATIVE_PUBLICATION_PENDING")
	_narrative_publication = false
	if persisted.ok:
		persisted.context.merge(receipt, false)
	return persisted


func restore_narrative_run() -> Dictionary:
	if _narrative_run == null or _narrative_player == null or _busy or _narrative_publication or _tutorial_publication or _training_publication:
		return _failure(&"NARRATIVE_BINDING_INVALID")
	return restore_active_run(_narrative_run, _narrative_player.get_ref())


func restore_active_run(run: RefCounted, player: Node) -> Dictionary:
	if _profile == null or _busy or _narrative_publication or _tutorial_publication or _training_publication or not run is Run or not is_instance_valid(player) or not player is Player or not player.is_inside_tree():
		return _failure(&"NATIVE_BINDING_INVALID")
	var inspected = _save.inspect_profile(_profile_id, _save_domain)
	if not inspected.ok or not _json_equal(inspected.payload.payload, _with_runtime_defaults(_payload)):
		return _failure(&"STALE_DURABLE_PROFILE")
	var run_value: Variant = _payload.get("active_run_state")
	var player_value: Variant = _payload.get("reward_effect_state")
	if not run_value is Dictionary or not player_value is Dictionary or run_value.is_empty() or player_value.is_empty():
		return _failure(&"NATIVE_RESTORE_INVALID")
	var launch := _launch_for_run(run_value)
	if launch.is_empty() or not _player_matches_launch(player, launch, run_value):
		return _failure(&"NATIVE_RESTORE_LOADOUT_MISMATCH")
	if not _settlement.verified_run_sources(launch, run_value).ok or _clone_native_run(run, run_value) == null:
		return _failure(&"NATIVE_RESTORE_RUN_INVALID")
	if not Replay.validate_full_player_reward_effect_state(player_value) or not player.can_restore_reward_effect_snapshot(player_value):
		return _failure(&"NATIVE_RESTORE_PLAYER_INVALID")
	var before: Dictionary = player.reward_effect_snapshot()
	var floor: Dictionary = run.floor_transaction_snapshot()
	_narrative_publication = true
	var restored: bool = player.restore_reward_effect_snapshot(player_value, false) and run.restore_launch_run_snapshot(run_value, floor.floor_definition, floor.room_templates, _catalog)
	if not restored:
		player.restore_reward_effect_snapshot(before, false)
	_narrative_publication = false
	if restored:
		if not _payload.get("native_run_checkpoint", {}).is_empty():
			var host: Node = _native_checkpoint_host.get_ref() if _native_checkpoint_host != null else null
			var captured := NativeCheckpoint.capture(host)
			if not captured.ok or captured.context.checkpoint != _payload.native_run_checkpoint:
				_checkpoint_recovery_pending = true
				return _failure(&"NATIVE_PUBLICATION_PENDING")
		_narrative_recovery_pending = false
		_tutorial_recovery_pending = false
		_checkpoint_recovery_pending = false
	return _success({}) if restored else _failure(&"NATIVE_RESTORE_INVALID")


func execute(command: Dictionary, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var kind: Variant = command.get("kind")
	var producer: RefCounted
	if kind in ["forge_upgrade", "enchant_preference", "void_temper"]:
		producer = _forge
	elif kind in ["build_save", "build_remove"]:
		producer = _builds
	elif kind != "meta_unlock":
		return _failure(&"COMMAND_INVALID")
	var prepared: Dictionary
	var receipt: Dictionary = {}
	if kind == "meta_unlock":
		prepared = _profile.call("prepare_command", command, expected_revision)
	else:
		if producer == null:
			return _failure(&"WORKSHOP_NOT_CONFIGURED")
		var produced: Dictionary = producer.call("prepare_command", snapshot(), command, expected_revision)
		if not produced.ok:
			return produced
		prepared = _profile.call("prepare_candidate", produced.context.candidate)
		receipt = produced.context.duplicate(true)
		receipt.erase("candidate")
	if not prepared.ok:
		return prepared
	var persisted := _persist_ticket(prepared.context.ticket)
	if persisted.ok:
		persisted.context.merge(receipt, false)
	return persisted


func prepare_launch(request: Dictionary, expected_revision: int, run_config: Dictionary = {}) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var before := snapshot()
	if not before.active_launch_receipt.is_empty():
		return _failure(&"LAUNCH_ACTIVE")
	if not Catalog.exact_fields(request, ["seed", "difficulty", "character_id", "weapon_id", "time_abilities"]) or not Catalog.bounded_int(request.seed, 0, Catalog.MAX_VALUE) or request.difficulty not in ["normal", "hard", "nightmare"] or not before.unlocked_characters.has(request.character_id) or not before.unlocked_weapons.has(request.weapon_id) or before.launch_sequence == Catalog.MAX_VALUE:
		return _failure(&"LOADOUT_INVALID")
	var config_value := run_config.duplicate(true)
	if config_value.is_empty():
		config_value = {"milestone": "LAUNCH", "seed": int(request.seed), "difficulty": request.difficulty, "character_id": request.character_id, "weapon_id": request.weapon_id, "enabled_time_skills": request.time_abilities}
	var frozen_config := _validated_launch_config(config_value, request)
	if frozen_config.is_empty():
		return _failure(&"RUN_CONFIG_INVALID")
	var rewards: Dictionary = _challenge_rewards.projection(challenge_reward_collection(), local_record_storage_identity()) if not challenge_reward_collection().equipped_ids.is_empty() else {}
	var projected: Dictionary = MetaProjection.from_profile(before, _catalog, rewards)
	if not projected.ok:
		return projected
	var candidate := before.duplicate(true)
	candidate.launch_sequence += 1
	candidate.revision += 1
	var launch := {"schema_id": "meta_launch_receipt_v1", "sequence": candidate.launch_sequence, "run_id": "meta-run-%s-%d" % [_profile_id, candidate.launch_sequence], "difficulty": request.difficulty, "seed": int(request.seed), "character_id": request.character_id, "weapon_id": request.weapon_id, "time_abilities": request.time_abilities, "projection_digest": projected.context.projection.projection_digest}
	candidate.active_launch_receipt = launch.duplicate(true)
	var prepared: Dictionary = _profile.call("prepare_candidate", candidate)
	if not prepared.ok:
		return _failure(&"LOADOUT_INVALID")
	var persisted := _persist_ticket(prepared.context.ticket, {"active_run_state": {}, "reward_effect_state": {}, "native_run_checkpoint": {}, "pending_meta_run_projection": projected.context.projection, "pending_run_config": frozen_config})
	if persisted.ok:
		persisted.context["launch"] = launch.duplicate(true)
		persisted.context["projection"] = projected.context.projection.duplicate(true)
		persisted.context["run_config"] = frozen_config.duplicate(true)
	return persisted


func settle_terminal(terminal: Dictionary, receipts: Array, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var before := snapshot()
	if not _run_config_matches_pending(terminal):
		return _failure(&"RUN_CONFIG_MISMATCH")
	var settlement: Dictionary = _settlement.call("prepare", before, before.active_launch_receipt, terminal, receipts)
	if not settlement.ok:
		return settlement
	var prepared: Dictionary = _profile.call("prepare_candidate", settlement.context.candidate)
	if not prepared.ok:
		return prepared
	var retained := verified_local_record_outbox()
	if not retained.ok:
		_profile.discard_candidate(prepared.context.ticket)
		return retained
	var queue: Array = []
	for source: Dictionary in retained.context.sources:
		queue.append({"profile_id": source.profile_id, "save_domain": source.save_domain, "content_snapshot": source.content_snapshot, "terminal": source.terminal, "launch": source.launch, "receipt": source.receipt})
	queue.append({"profile_id": _profile_id, "save_domain": _save_domain, "content_snapshot": _save.configured_content_snapshot(), "terminal": Envelope.validate_active_run_snapshot(terminal, _catalog).payload, "launch": before.active_launch_receipt.duplicate(true), "receipt": settlement.context.receipt.duplicate(true)})
	var omitted_count: int = retained.context.get("omitted_count", 0)
	if queue.size() > LocalRecordRules.MAX_ENTRIES:
		var ranked: Array = []
		for source: Dictionary in queue:
			ranked.append({"source": source, "record": LocalRecordRules.record(source)})
		ranked.sort_custom(func(left: Dictionary, right: Dictionary): return LocalRecordRules.ranks_before(left.record, right.record))
		omitted_count = mini(Catalog.MAX_VALUE, omitted_count + queue.size() - LocalRecordRules.MAX_ENTRIES)
		queue.clear()
		for index: int in range(LocalRecordRules.MAX_ENTRIES):
			queue.append(ranked[index].source)
	var persisted := _persist_ticket(prepared.context.ticket, {"active_run_state": terminal, "pending_meta_run_projection": {}, "pending_run_config": {}, "local_records_outbox": {"schema_version": 1, "sources": queue, "omitted_count": omitted_count}})
	if persisted.ok:
		persisted.context["receipt"] = settlement.context.receipt.duplicate(true)
	return persisted


func abandon_run(active_run: Dictionary, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var before := snapshot()
	if not _run_config_matches_pending(active_run):
		return _failure(&"RUN_CONFIG_MISMATCH")
	var settlement: Dictionary = _settlement.call("prepare_abandon", before, before.active_launch_receipt, active_run)
	if not settlement.ok:
		return settlement
	var prepared: Dictionary = _profile.call("prepare_candidate", settlement.context.candidate)
	if not prepared.ok:
		return prepared
	return _persist_ticket(prepared.context.ticket, {"active_run_state": settlement.context.terminal, "native_run_checkpoint": {}, "pending_meta_run_projection": {}, "pending_run_config": {}})


func _persist_ticket(ticket: Dictionary, payload_changes: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _profile.call("candidate_snapshot", ticket)
	if candidate.is_empty() or _busy:
		return _failure(&"TICKET_INVALID")
	_busy = true
	var primary = _save.call("inspect_profile", _profile_id, _save_domain)
	var next_payload := _payload.duplicate(true)
	if primary.ok:
		var durable: Dictionary = primary.payload.payload
		var state = Profile.new()
		if not durable.get("meta_profile_state") is Dictionary or not state.configure(_catalog, durable.meta_profile_state) or state.snapshot() != snapshot() or not _mirrors_match(durable, state.snapshot()):
			return _discard_failure(ticket, &"STALE_DURABLE_PROFILE")
		if payload_changes.has("cosmetic_collection") and not _json_equal(durable.get("cosmetic_collection", _cosmetic_catalog.empty_collection()), _payload.get("cosmetic_collection", _cosmetic_catalog.empty_collection())):
			return _discard_failure(ticket, &"STALE_DURABLE_PROFILE")
		if payload_changes.has("challenge_reward_collection") and not _json_equal(durable.get("challenge_reward_collection", _challenge_rewards.empty_collection()), challenge_reward_collection()):
			return _discard_failure(ticket, &"STALE_DURABLE_PROFILE")
		next_payload = durable.duplicate(true)
	elif primary.code != &"NOT_FOUND":
		return _discard_failure(ticket, primary.code)
	var synchronize: bool = not next_payload.get("native_run_checkpoint", {}).is_empty() and not payload_changes.has("native_run_checkpoint") and (payload_changes.has("active_run_state") or payload_changes.has("reward_effect_state"))
	if synchronize:
		var synchronized := _checkpoint_changes(payload_changes)
		if not synchronized.ok:
			return _discard_failure(ticket, synchronized.code)
		payload_changes = synchronized.context.changes
	for key: String in payload_changes:
		next_payload[key] = payload_changes[key].duplicate(true)
	next_payload["meta_profile_state"] = candidate.duplicate(true)
	for field: String in MIRROR_FIELDS:
		next_payload[field] = _copy(candidate[field])
	var written = _save.call("save_profile_compare_exchange", _profile_id, _save_domain, next_payload, primary.payload if primary.ok else {}) if payload_changes.has("challenge_reward_collection") else _save.call("save_profile", _profile_id, _save_domain, next_payload)
	if written.metadata.get("reason") == "expected_primary_stale":
		return _discard_failure(ticket, &"STALE_DURABLE_PROFILE")
	var reconciled := false
	if not written.ok:
		# Only the promoted primary proves commit; loading could promote an uncommitted pending file.
		var inspected = _save.call("inspect_profile", _profile_id, _save_domain)
		if not inspected.ok or not _json_equal(inspected.payload.payload, _with_runtime_defaults(next_payload)):
			return _discard_failure(ticket, written.code)
		reconciled = true
	var committed: Dictionary = _profile.call("commit_candidate", ticket)
	_busy = false
	if not committed.ok:
		return _failure(&"INTEGRITY_FAILURE")
	_payload = _with_runtime_defaults(next_payload)
	if synchronize:
		var host: Node = _native_checkpoint_host.get_ref() if _native_checkpoint_host != null else null
		var after := NativeCheckpoint.capture(host)
		if not after.ok or after.context.checkpoint != payload_changes.native_run_checkpoint:
			_checkpoint_recovery_pending = true
			return _failure(&"NATIVE_PUBLICATION_PENDING")
	return _success({"snapshot": snapshot(), "reconciled_committed_write": reconciled})


func _checkpoint_changes(changes: Dictionary) -> Dictionary:
	var host: Node = _native_checkpoint_host.get_ref() if _native_checkpoint_host != null else null
	var captured := NativeCheckpoint.capture(host)
	if not captured.ok:
		return captured
	if changes.has("active_run_state") and not _json_equal(changes.active_run_state, captured.context.run) or changes.has("reward_effect_state") and not _json_equal(changes.reward_effect_state, captured.context.reward):
		return _failure(&"NATIVE_CHECKPOINT_INVALID")
	var synchronized := changes.duplicate(true)
	synchronized["active_run_state"] = captured.context.run.duplicate(true)
	synchronized["reward_effect_state"] = captured.context.reward.duplicate(true)
	synchronized["native_run_checkpoint"] = captured.context.checkpoint.duplicate(true)
	return _success({"changes": synchronized})


func _with_runtime_defaults(value: Dictionary) -> Dictionary:
	var normalized := value.duplicate(true)
	if not normalized.has("active_item_state"):
		normalized["active_item_state"] = Envelope.empty_active_item_state()
	for field: String in ["reward_effect_state", "active_run_state"]:
		if not normalized.has(field):
			normalized[field] = {}
	return normalized


func _discard_failure(ticket: Dictionary, code: StringName) -> Dictionary:
	_profile.call("discard_candidate", ticket)
	_busy = false
	return _failure(code)


func _readiness(expected_revision: int) -> Dictionary:
	if _profile == null or _busy or _narrative_publication or _tutorial_publication or _training_publication:
		return _failure(&"BUSY" if _busy or _narrative_publication or _tutorial_publication or _training_publication else &"NOT_CONFIGURED")
	if expected_revision != snapshot().revision:
		return _failure(&"STALE_REVISION")
	if _narrative_recovery_pending or _tutorial_recovery_pending or _training_recovery_pending or _checkpoint_recovery_pending:
		return _failure(&"NATIVE_PUBLICATION_PENDING")
	return _success({})


func _launch_for_run(value: Dictionary) -> Dictionary:
	var profile := snapshot()
	if profile.is_empty() or value.is_empty():
		return {}
	if not profile.active_launch_receipt.is_empty():
		return profile.active_launch_receipt.duplicate(true)
	var settled: Dictionary = profile.last_settlement_receipt
	if settled.is_empty() or settled.sequence != profile.launch_sequence or settled.run_id != value.get("run_id") or settled.terminal_reason != value.get("result", {}).get("result") or value != _payload.get("active_run_state"):
		return {}
	return {"schema_id": "meta_launch_receipt_v1", "sequence": int(settled.sequence), "run_id": settled.run_id, "difficulty": value.config.get("difficulty"), "seed": value.run_seed, "character_id": value.config.get("character_id"), "weapon_id": value.config.get("weapon_id"), "time_abilities": value.config.get("enabled_time_skills"), "projection_digest": value.resources.get("meta_run_projection", {}).get("projection_digest")}


func _native_narrative_active(allow_victory_collection: bool = false) -> bool:
	if _narrative_run == null or _narrative_player == null or _narrative_recovery_pending:
		return false
	var player: Node = _narrative_player.get_ref()
	var profile := snapshot()
	var state: Dictionary = _narrative_run.snapshot()
	if not is_instance_valid(player) or not player.is_inside_tree() or not _player_matches_launch(player, _narrative_launch, state) or state.suspended or profile.active_launch_receipt.is_empty() or profile.active_launch_receipt != _narrative_launch or player.health.dead or not _settlement.verified_run_sources(_narrative_launch, state).ok:
		return false
	if not Phase.is_terminal(state.phase):
		return true
	var terminal: Dictionary = _settlement.verified_terminal_facts(_narrative_launch, state)
	return allow_victory_collection and terminal.ok and terminal.context.terminal_reason == "victory"


func _native_narrative_context(allow_victory_collection: bool = false) -> Dictionary:
	if not _native_narrative_active(allow_victory_collection):
		return {}
	var sources: Dictionary = _settlement.verified_run_sources(_narrative_launch, _narrative_run.snapshot())
	var boss_ids: Array = []
	for source: Dictionary in sources.context.sources:
		if source.kind == "boss":
			boss_ids.append(source.payload.boss_id)
	boss_ids.sort()
	var player: Node = _narrative_player.get_ref()
	return {"run_id": _narrative_launch.run_id, "launch_sequence": int(_narrative_launch.sequence), "floor_id": _narrative_run.floor_plan.floor_id, "boss_ids": boss_ids, "max_hp": float(player.health.max_hp), "current_hp": float(player.health.current_hp)}


func _native_terminal_facts() -> Dictionary:
	var state: Dictionary = _narrative_run.snapshot() if _narrative_run != null else _payload.get("active_run_state", {})
	var launch := _launch_for_run(state)
	return _settlement.verified_terminal_facts(launch, state) if not launch.is_empty() else _failure(&"TERMINAL_INVALID")


func _occurrence_definition(kind: String, id: String) -> Dictionary:
	if kind == "choice":
		var row: Dictionary = _narrative_content.definition(id)
		return row if row.get("definition_kind") == "choice" else {}
	if kind != "collect":
		return {}
	for category: String in ["artifact", "environment_record", "source"]:
		for row: Dictionary in _narrative_content.definitions(category):
			if row.source_receipt_id == id:
				return row
	for row: Dictionary in _narrative_content.definitions("hidden_line"):
		for step: Dictionary in row.steps:
			if step.source_receipt_id == id:
				return step
	return {}


func _occurrence_matches(command: Dictionary, token: Area2D) -> bool:
	if not is_instance_valid(token) or not _occurrences.has(token.get_instance_id()) or not _native_narrative_active(command.get("kind") == "narrative_collect"):
		return false
	var record: Dictionary = _occurrences[token.get_instance_id()]
	var room: Node2D = record.room.get_ref()
	var parent: Node2D = record.parent.get_ref()
	var anchor: Marker2D = record.anchor.get_ref()
	var collision: CollisionShape2D = record.collision.get_ref()
	var player: Node2D = _narrative_player.get_ref()
	var node: Dictionary = _narrative_run.current_floor_node()
	var requested: Variant = command.get("source_receipt_id") if record.kind == "collect" else command.get("definition_id")
	return record.token.get_ref() == token and requested == record.id and command.get("kind") == "narrative_" + record.kind and is_instance_valid(room) and is_instance_valid(parent) and is_instance_valid(anchor) and is_instance_valid(collision) and token.get_parent() == parent and room.is_inside_tree() and token.is_inside_tree() and room.binding_snapshot() == record.binding and room.global_transform == record.room_transform and RoomContract.validate(room, record.template).ok and node.id == record.node_id and _narrative_run.floor_plan.floor_id == record.floor_id and anchor.global_position == record.position and token.global_position == record.position and token.global_transform.x == Vector2.RIGHT and token.global_transform.y == Vector2.DOWN and token.collision_layer == 0 and token.collision_mask == record.player_layer and player.collision_layer == record.player_layer and record.player_layer != 0 and token.monitoring and not token.monitorable and not collision.disabled and collision.transform == Transform2D.IDENTITY and collision.shape == record.shape and record.shape.radius == OCCURRENCE_RADIUS and player.global_position.distance_to(record.position) <= OCCURRENCE_RADIUS and token.overlaps_body(player)


func _player_matches_launch(player: Node, launch: Dictionary, run_value: Dictionary) -> bool:
	if not is_instance_valid(player) or not player is Player or player.loadout_runtime == null or launch.is_empty() or not run_value.get("config") is Dictionary or not run_value.config.get("character_talents") is Array:
		return false
	var loadout: Dictionary = player.loadout_runtime.snapshot()
	var identity: Dictionary = player.full_player_replay_identity()
	if identity.is_empty() or not identity.get("character_talent_ids") is Array:
		return false
	var initial_talents: Array = identity.character_talent_ids.duplicate()
	var selected_talents: Array = run_value.config.character_talents.duplicate()
	initial_talents.sort()
	selected_talents.sort()
	return initial_talents == selected_talents and _run_config_matches_pending(run_value) and str(player.current_run_id()) == launch.run_id and loadout.get("milestone") == run_value.config.get("milestone") and loadout.get("milestone") in ["LAUNCH", "EXPANSION"] and loadout.get("character_id") == launch.character_id and loadout.get("weapon_id") == launch.weapon_id and loadout.get("enabled_time_skills") == launch.time_abilities and _json_equal(player.meta_run_projection_snapshot(), run_value.resources.get("meta_run_projection"))


func _native_player_stamp(player: Node) -> Dictionary:
	return {"identity": player.full_player_replay_identity(), "generation": player.owner_character_generation()}


func _validated_launch_config(value: Dictionary, launch: Dictionary, persisted: bool = false) -> Dictionary:
	for key: Variant in value:
		if not RunConfig.DEFAULTS.has(key) and key != "launch_encounter_revision":
			return {}
	var config := RunConfig.normalized(value)
	if persisted:
		if not Catalog.bounded_int(config.schema_version, 1, 1) or not Catalog.bounded_int(config.seed, 0, Catalog.MAX_VALUE):
			return {}
		config.schema_version = int(config.schema_version)
		config.seed = int(config.seed)
		if config.has("launch_encounter_revision"):
			if not Catalog.bounded_int(config.launch_encounter_revision, 1, 3):
				return {}
			config.launch_encounter_revision = int(config.launch_encounter_revision)
	if not RunConfig.validate(config).ok or config.milestone not in ["LAUNCH", "EXPANSION"] or config.seed != launch.seed or config.difficulty != launch.difficulty or config.character_id != launch.character_id or config.weapon_id != launch.weapon_id or config.enabled_time_skills != launch.time_abilities:
		return {}
	return config


func _run_config_matches_pending(value: Dictionary) -> bool:
	if not _payload.has("pending_run_config") or snapshot().active_launch_receipt.is_empty():
		return true
	var frozen := pending_launch_config()
	return not frozen.is_empty() and value.get("config") is Dictionary and _canonical_launch_config_fields(value.config) and _json_equal(value.config, frozen)


func _canonical_launch_config_fields(value: Dictionary) -> bool:
	var fields: Array = RunConfig.DEFAULTS.keys()
	if value.has("launch_encounter_revision"):
		fields.append("launch_encounter_revision")
	return Catalog.exact_fields(value, fields)


func _clone_narrative_run(value: Dictionary) -> RefCounted:
	return _clone_native_run(_narrative_run, value)


func _clone_native_run(run: RefCounted, value: Dictionary) -> RefCounted:
	var floor: Dictionary = run.floor_transaction_snapshot()
	var clone := Run.new()
	clone.reset_domain(value.config, value.run_id)
	return clone if clone.restore_launch_run_snapshot(value, floor.floor_definition, floor.room_templates, _catalog) else null


func _restore_bound_run(value: Dictionary) -> bool:
	var floor: Dictionary = _narrative_run.floor_transaction_snapshot()
	return _narrative_run.restore_launch_run_snapshot(value, floor.floor_definition, floor.room_templates, _catalog)


func _mirrors_match(value: Dictionary, profile: Dictionary) -> bool:
	for field: String in MIRROR_FIELDS:
		if value.has(field) and not _json_equal(value[field], profile[field]):
			return false
	return true


func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value


func _json_equal(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(Envelope.canonical_json(left)) == JSON.parse_string(Envelope.canonical_json(right))


func _success(context: Dictionary) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
