class_name EncounterSettlementAdapter
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const EnemyRuntime := preload("res://scripts/enemies/launch/launch_enemy_runtime.gd")
const Actor := preload("res://scripts/enemies/launch/launch_hostile_actor.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Run := preload("res://scripts/application/run_state.gd")
const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const LAUNCH_FIELDS := ["schema_id", "sequence", "run_id", "difficulty", "seed", "character_id", "weapon_id", "time_abilities", "projection_digest"]
const POLICY_FIELDS := ["schema_id", "schema_version", "ordinary", "elite", "boss", "support"]

var _run: RefCounted
var _encounter: RefCounted
var _launch: Dictionary = {}
var _policy: Dictionary = {}
var _definition: Dictionary = {}
var _enemy_definitions: Dictionary = {}
var _bindings: Dictionary = {}
var _pending_deaths: Dictionary = {}
var _node_id := ""
var _floor_id := ""
var _encounter_identity: Dictionary = {}
var _encounter_digest := ""


func configure(run: RefCounted, encounter: RefCounted, launch: Dictionary, policy: Dictionary) -> Dictionary:
	if _run != null or not run is Run or not encounter is Encounter:
		return _failure(&"CONFIGURATION_INVALID")
	if not Catalog.exact_fields(launch, LAUNCH_FIELDS) or launch.schema_id != "meta_launch_receipt_v1" or not Catalog.bounded_int(launch.sequence, 1, Catalog.MAX_VALUE) or not _policy_valid(policy):
		return _failure(&"POLICY_OR_LAUNCH_INVALID")
	var state: Dictionary = run.snapshot()
	var encounter_state: Dictionary = encounter.snapshot()
	var definition: Dictionary = encounter.configured_encounter()
	var node: Dictionary = run.current_floor_node()
	if node.is_empty() or not bool(node.visited) or bool(node.cleared) or node.room_type not in ["combat", "elite"] or definition.is_empty() or encounter_state.is_empty() or definition.floor_id != state.floor_plan.get("floor_id") or definition.room_type != node.room_type or encounter_state.identity.run_id != launch.run_id or encounter_state.identity.room_id != node.id or not _run_matches(state, launch):
		return _failure(&"RUN_ENCOUNTER_MISMATCH")
	var entries: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/enemies.json"))
	if not entries is Array:
		return _failure(&"ENEMY_CONTENT_UNAVAILABLE")
	var definitions: Dictionary = {}
	for row: Variant in entries:
		var parser = Enemy.new()
		if not row is Dictionary or not parser.configure(row).ok or definitions.has(row.id):
			return _failure(&"ENEMY_CONTENT_INVALID")
		definitions[row.id] = parser
	for wave: Dictionary in definition.waves:
		for spawn: Dictionary in wave.spawns:
			if not definitions.has(spawn.enemy_id):
				return _failure(&"UNSUPPORTED_PRINCIPAL")
	_run = run
	_encounter = encounter
	_launch = launch.duplicate(true)
	_policy = policy.duplicate(true)
	_definition = definition
	_enemy_definitions = definitions
	_node_id = node.id
	_floor_id = definition.floor_id
	_encounter_identity = encounter_state.identity.duplicate(true)
	_encounter_digest = encounter_state.encounter_digest
	return _success()


func register_actor(spawn_id: String, actor: Node) -> Dictionary:
	if not _active_room() or not is_instance_valid(actor) or not actor is Actor:
		return _failure(&"ACTOR_INVALID")
	var pending: Dictionary = _encounter.snapshot().pending_spawns
	if not pending.has(spawn_id):
		return _failure(&"SPAWN_UNDECLARED")
	var spawn: Dictionary = pending[spawn_id]
	var native: Dictionary = actor.launch_runtime_snapshot()
	if native.runtime.is_empty() or native.runtime.terminal or native.health.get("dead", true) or native.runtime.identity.run_id != _launch.run_id or native.runtime.identity.seed != _launch.seed or native.runtime.identity.hostile_source_id != str(actor.hostile_source_id) or not Catalog.stable_id(str(actor.hostile_source_id)) or _bindings.has(str(actor.hostile_source_id)):
		return _failure(&"ACTOR_INVALID")
	for binding: Dictionary in _bindings.values():
		if binding.actor.get_ref() == actor:
			return _failure(&"ACTOR_ALREADY_BOUND")
	var definition: Dictionary = _enemy_definitions[spawn.enemy_id].runtime_projection("elite" if spawn.elite else "enemy")
	var validator = EnemyRuntime.new()
	if not validator.configure(definition, native.runtime.identity).ok or validator.snapshot().definition_digest != native.runtime.definition_digest:
		return _failure(&"ACTOR_DEFINITION_MISMATCH")
	var source_id := str(actor.hostile_source_id)
	if not _encounter.register_spawned(spawn_id, source_id):
		return _failure(&"REGISTRATION_REFUSED")
	var callback := Callable(self, "_on_final_death").bind(weakref(actor))
	actor.hostile_final_death.connect(callback)
	_bindings[source_id] = {"actor": weakref(actor), "callback": callback, "spawn_id": spawn_id, "elite": bool(spawn.elite), "identity": native.runtime.identity.duplicate(true), "definition_digest": native.runtime.definition_digest}
	return _success()


func receipts() -> Array:
	var result: Array = []
	if _run == null:
		return result
	for event: Variant in _run.snapshot().events:
		if event is Dictionary and event.get("type") == Settlement.SOURCE_TYPE:
			result.append(event.receipt.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.source_id) < str(b.source_id))
	return result


func pending_sources() -> Array:
	var result: Array = []
	var ids: Array = _pending_deaths.keys()
	ids.sort()
	for id: String in ids:
		result.append(_pending_deaths[id].duplicate(true))
	return result


func retry_pending_deaths() -> Dictionary:
	if not _active_room():
		return _failure(&"ROOM_RETIRED")
	for source: Dictionary in pending_sources():
		var committed := _commit_death(source)
		if not committed.ok:
			return committed
	return _success()


func detach() -> void:
	for binding: Dictionary in _bindings.values():
		var actor: Node = binding.actor.get_ref()
		if is_instance_valid(actor) and actor.hostile_final_death.is_connected(binding.callback):
			actor.hostile_final_death.disconnect(binding.callback)
	_bindings.clear()
	_pending_deaths.clear()
	_run = null
	_encounter = null
	_launch.clear()
	_enemy_definitions.clear()
	_encounter_identity.clear()
	_encounter_digest = ""


func _on_final_death(source_id: StringName, receipt_id: String, actor_reference: WeakRef) -> void:
	var id := str(source_id)
	var actor: Node = actor_reference.get_ref()
	if not _active_room() or not _bindings.has(id) or not is_instance_valid(actor) or _bindings[id].actor.get_ref() != actor or actor.hostile_source_id != source_id:
		return
	var native: Dictionary = actor.launch_runtime_snapshot()
	var canonical := "hostile_defeat:%s" % (_launch.run_id + "|" + id).sha256_text().substr(0, 40)
	if receipt_id != canonical or native.death_receipt != canonical or native.runtime.identity != _bindings[id].identity or native.runtime.definition_digest != _bindings[id].definition_digest or not native.runtime.terminal or not native.health.get("dead", false) or float(native.health.get("current_hp", 1.0)) > 0.0:
		return
	var roster: Dictionary = _encounter.snapshot().roster
	if not roster.has(id) or roster[id].spawn_id != _bindings[id].spawn_id:
		return
	var amounts: Dictionary = _policy.elite if _bindings[id].elite else _policy.ordinary
	var source := {"schema_id": Settlement.SOURCE_TYPE, "run_id": _launch.run_id, "launch_sequence": int(_launch.sequence), "floor_id": _floor_id, "node_id": _node_id, "kind": "material", "payload": {"actor_role": "principal", "principal_source_id": id, "defeat_receipt": canonical, "chronos_shards": int(amounts.chronos_shards), "existential_imprints": int(amounts.existential_imprints)}}
	source["source_id"] = Settlement.source_id(source, canonical)
	for existing: Dictionary in receipts():
		if existing.source_id == source.source_id or existing.get("payload", {}).get("defeat_receipt") == canonical:
			return
	# Native actors retire after death. Retain the authenticated source for a refused-write retry.
	_pending_deaths[id] = source.duplicate(true)
	_commit_death(source)


func _commit_death(source: Dictionary) -> Dictionary:
	var id: String = source.payload.principal_source_id
	var canonical: String = source.payload.defeat_receipt
	if not _active_room() or not _pending_deaths.has(id) or _pending_deaths[id] != source:
		return _failure(&"ROOM_RETIRED")
	var roster: Dictionary = _encounter.snapshot().roster
	if not _bindings.has(id) or not roster.has(id) or roster[id].spawn_id != _bindings[id].spawn_id:
		return _failure(&"DEFEAT_REFUSED")
	var pays_material: bool = source.payload.chronos_shards > 0 or source.payload.existential_imprints > 0
	if pays_material and not _run.can_append_meta_material_source(source):
		return _failure(&"RETENTION_REFUSED")
	var encounter_before: Dictionary = _encounter.snapshot()
	if not _encounter.notify_entity_defeated(id, canonical):
		return _failure(&"DEFEAT_REFUSED")
	if pays_material and not _run.append_meta_material_source(source):
		if not _encounter.restore_snapshot(encounter_before):
			return _failure(&"ROLLBACK_REFUSED")
		return _failure(&"RETENTION_REFUSED")
	_pending_deaths.erase(id)
	return _success()


func _active_room() -> bool:
	if _run == null or _encounter == null:
		return false
	var state: Dictionary = _run.snapshot()
	var node: Dictionary = _run.current_floor_node()
	var encounter_state: Dictionary = _encounter.snapshot()
	return not encounter_state.is_empty() and encounter_state.identity == _encounter_identity and encounter_state.encounter_digest == _encounter_digest and not node.is_empty() and node.id == _node_id and bool(node.visited) and not bool(node.cleared) and not Phase.is_terminal(state.phase) and state.floor_plan.get("floor_id") == _floor_id and _run_matches(state, _launch)


func _run_matches(state: Dictionary, launch: Dictionary) -> bool:
	return state.run_id == launch.run_id and state.run_seed == launch.seed and state.config.get("milestone") in ["LAUNCH", "EXPANSION"] and state.config.get("difficulty") == launch.difficulty and state.config.get("character_id") == launch.character_id and state.config.get("weapon_id") == launch.weapon_id and state.config.get("enabled_time_skills") == launch.time_abilities and state.resources.get("meta_run_projection", {}).get("projection_digest") == launch.projection_digest


func _policy_valid(value: Dictionary) -> bool:
	if not Catalog.exact_fields(value, POLICY_FIELDS) or value.schema_id != "planewalker.meta_material_policy" or not Catalog.bounded_int(value.schema_version, 1, 1):
		return false
	for kind: String in ["ordinary", "elite", "boss", "support"]:
		if not Catalog.exact_fields(value[kind], ["chronos_shards", "existential_imprints"]) or not Catalog.bounded_int(value[kind].chronos_shards, 0, 5) or not Catalog.bounded_int(value[kind].existential_imprints, 0, 1):
			return false
	return value.boss.chronos_shards == 0 and value.boss.existential_imprints == 0 and value.support.chronos_shards == 0 and value.support.existential_imprints == 0


func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}


func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}
