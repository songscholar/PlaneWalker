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
const Run := preload("res://scripts/application/run_state.gd")
const RunConfig := preload("res://scripts/application/run_config.gd")
const Player := preload("res://scripts/player/player_controller.gd")
const Room := preload("res://scripts/dungeon/launch_room_scene.gd")
const RoomContract := preload("res://scripts/dungeon/room_scene_contract.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
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


func configure(catalog: RefCounted, save_service: RefCounted, profile_id: String, save_domain: String, initial_payload: Dictionary = {}) -> Dictionary:
	if _busy or _narrative_publication or save_service == null or not save_service.has_method("save_profile") or not save_service.has_method("load_profile") or not save_service.has_method("inspect_profile") or not Paths.validate_id(profile_id).ok or not Paths.validate_id(save_domain).ok:
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
	return _success({"snapshot": snapshot()})


func snapshot() -> Dictionary:
	return _profile.call("snapshot") if _profile != null else {}


func payload() -> Dictionary:
	return _payload.duplicate(true)


func frozen_launch_projection() -> Dictionary:
	var profile := snapshot()
	var projection: Variant = _payload.get("pending_meta_run_projection")
	if profile.is_empty() or profile.active_launch_receipt.is_empty() or not projection is Dictionary or not MetaProjection.validate(projection, _catalog) or projection.projection_digest != profile.active_launch_receipt.projection_digest:
		return {}
	return projection.duplicate(true)


func pending_launch_config() -> Dictionary:
	var profile := snapshot()
	var value: Variant = _payload.get("pending_run_config")
	if profile.is_empty() or profile.active_launch_receipt.is_empty() or not value is Dictionary or not Catalog.exact_fields(value, RunConfig.DEFAULTS.keys()):
		return {}
	return _validated_launch_config(value, profile.active_launch_receipt, true)


func retain_active_run(run: RefCounted, player: Node, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	if _narrative_recovery_pending:
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


func enable_workshop(entries: Array) -> Dictionary:
	if _profile == null or _busy:
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


func enable_narrative(entries: Array, sources: Array) -> Dictionary:
	if _profile == null or _busy or _narrative_publication:
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
	if _narrative == null or _busy or _narrative_publication or not run is Run or not is_instance_valid(player) or not player is Player or not player.is_inside_tree():
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
	if _narrative == null or _busy or _narrative_publication or _occurrences.size() >= MAX_OCCURRENCES or not _native_narrative_active(kind == "collect") or not room is Room or not is_instance_valid(runtime_parent) or not runtime_parent.is_inside_tree() or runtime_parent == room or room.is_ancestor_of(runtime_parent):
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
		if not Envelope.validate_active_run_snapshot(run_after).ok:
			_profile.discard_candidate(prepared.context.ticket)
			return _failure(&"NATIVE_RUN_ENVELOPE_INVALID")
		payload_changes.active_run_state = run_after
		payload_changes.reward_effect_state = player_after
	_narrative_publication = true
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
	_narrative_publication = false
	if persisted.ok:
		persisted.context.merge(receipt, false)
	return persisted


func restore_narrative_run() -> Dictionary:
	if _narrative_run == null or _narrative_player == null or _busy or _narrative_publication:
		return _failure(&"NARRATIVE_BINDING_INVALID")
	return restore_active_run(_narrative_run, _narrative_player.get_ref())


func restore_active_run(run: RefCounted, player: Node) -> Dictionary:
	if _profile == null or _busy or _narrative_publication or not run is Run or not is_instance_valid(player) or not player is Player or not player.is_inside_tree():
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
	var restored: bool = player.restore_reward_effect_snapshot(player_value, false) and run.restore_launch_run_snapshot(run_value, floor.floor_definition, floor.room_templates)
	if not restored:
		player.restore_reward_effect_snapshot(before, false)
	_narrative_publication = false
	if restored:
		_narrative_recovery_pending = false
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
	var projected: Dictionary = MetaProjection.from_profile(before, _catalog)
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
	var persisted := _persist_ticket(prepared.context.ticket, {"active_run_state": {}, "reward_effect_state": {}, "pending_meta_run_projection": projected.context.projection, "pending_run_config": frozen_config})
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
	var persisted := _persist_ticket(prepared.context.ticket, {"active_run_state": terminal, "pending_meta_run_projection": {}, "pending_run_config": {}})
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
	return _persist_ticket(prepared.context.ticket, {"active_run_state": settlement.context.terminal, "pending_meta_run_projection": {}, "pending_run_config": {}})


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
		next_payload = durable.duplicate(true)
	elif primary.code != &"NOT_FOUND":
		return _discard_failure(ticket, primary.code)
	for key: String in payload_changes:
		next_payload[key] = payload_changes[key].duplicate(true)
	next_payload["meta_profile_state"] = candidate.duplicate(true)
	for field: String in MIRROR_FIELDS:
		next_payload[field] = _copy(candidate[field])
	var written = _save.call("save_profile", _profile_id, _save_domain, next_payload)
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
	return _success({"snapshot": snapshot(), "reconciled_committed_write": reconciled})


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
	if _profile == null or _busy or _narrative_publication:
		return _failure(&"BUSY" if _busy or _narrative_publication else &"NOT_CONFIGURED")
	if expected_revision != snapshot().revision:
		return _failure(&"STALE_REVISION")
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
	if not is_instance_valid(player) or not player is Player or player.loadout_runtime == null or launch.is_empty():
		return false
	var loadout: Dictionary = player.loadout_runtime.snapshot()
	return not player.full_player_replay_identity().is_empty() and _run_config_matches_pending(run_value) and str(player.current_run_id()) == launch.run_id and loadout.get("milestone") == run_value.config.get("milestone") and loadout.get("milestone") in ["LAUNCH", "EXPANSION"] and loadout.get("character_id") == launch.character_id and loadout.get("weapon_id") == launch.weapon_id and loadout.get("enabled_time_skills") == launch.time_abilities and _json_equal(player.meta_run_projection_snapshot(), run_value.resources.get("meta_run_projection"))


func _native_player_stamp(player: Node) -> Dictionary:
	return {"identity": player.full_player_replay_identity(), "generation": player.owner_character_generation()}


func _validated_launch_config(value: Dictionary, launch: Dictionary, persisted: bool = false) -> Dictionary:
	for key: Variant in value:
		if not RunConfig.DEFAULTS.has(key):
			return {}
	var config := RunConfig.normalized(value)
	if persisted:
		if not Catalog.bounded_int(config.schema_version, 1, 1) or not Catalog.bounded_int(config.seed, 0, Catalog.MAX_VALUE):
			return {}
		config.schema_version = int(config.schema_version)
		config.seed = int(config.seed)
	if not RunConfig.validate(config).ok or config.milestone not in ["LAUNCH", "EXPANSION"] or config.seed != launch.seed or config.difficulty != launch.difficulty or config.character_id != launch.character_id or config.weapon_id != launch.weapon_id or config.enabled_time_skills != launch.time_abilities:
		return {}
	return config


func _run_config_matches_pending(value: Dictionary) -> bool:
	if not _payload.has("pending_run_config") or snapshot().active_launch_receipt.is_empty():
		return true
	var frozen := pending_launch_config()
	return not frozen.is_empty() and value.get("config") is Dictionary and Catalog.exact_fields(value.config, RunConfig.DEFAULTS.keys()) and _json_equal(value.config, frozen)


func _clone_narrative_run(value: Dictionary) -> RefCounted:
	return _clone_native_run(_narrative_run, value)


func _clone_native_run(run: RefCounted, value: Dictionary) -> RefCounted:
	var floor: Dictionary = run.floor_transaction_snapshot()
	var clone := Run.new()
	clone.reset_domain(value.config, value.run_id)
	return clone if clone.restore_launch_run_snapshot(value, floor.floor_definition, floor.room_templates) else null


func _restore_bound_run(value: Dictionary) -> bool:
	var floor: Dictionary = _narrative_run.floor_transaction_snapshot()
	return _narrative_run.restore_launch_run_snapshot(value, floor.floor_definition, floor.room_templates)


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
