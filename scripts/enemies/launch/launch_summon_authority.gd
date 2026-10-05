class_name LaunchSummonAuthority
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const SummonDefinitionScript := preload("res://scripts/enemies/launch/summon_definition.gd")
const SummonProjection := preload("res://scripts/enemies/launch/launch_summon_projection.gd")
const SummonActor := preload("res://scripts/enemies/launch/launch_summon_actor.gd")
const CopyProjection := preload("res://scripts/enemies/launch/launch_ordinary_copy_projection.gd")
const CopyActor := preload("res://scripts/enemies/launch/launch_ordinary_copy_actor.gd")
const EnemyDefinitionScript := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Mirroring := preload("res://scripts/enemies/launch/launch_elite_mirroring_runtime.gd")
const AffixDefinitionScript := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const ZoneProjection := preload("res://scripts/enemies/launch/launch_semantic_zone_projection.gd")
const RoomContract := preload("res://scripts/dungeon/room_scene_contract.gd")
const STATE_FIELDS := ["schema_version", "run_id", "initial_frame", "runtime_frame", "claims", "rows"]
const ROW_FIELDS := ["id", "parent_source_id", "parent_definition_id", "action_id", "generation", "slot_index", "seed", "request_frame", "position", "projection", "lifetime_frames", "spawn_warning_frames", "spawn_mode", "retire_on_owner_death", "phase", "warning_frame", "birth_frame", "expires_frame", "retired_frame", "room_motion"]
const LEASE_FIELDS := ["id", "parent_source_id", "seed", "birth_frame", "expires_frame", "retire_on_owner_death"]
const MAX_SUMMONS := 8
const MAX_RESERVATIONS := 256
const MAX_LEASES := 4096
const MIRROR_ACTION_ID := "affix_mirroring"
const SPLIT_ACTION_ID := "affix_splitting"
var _state: Dictionary = {}
var _pending: Dictionary = {}
var _committed := false
var _next_ticket := 1
var _root: Node2D
var _actors: Dictionary = {}
var _warnings: Dictionary = {}
var _owners: Dictionary = {}
var _definitions: Dictionary = {}
var _death_actions: Dictionary = {}
var _ordinary_parents: Dictionary = {}
var _summon_actions: Dictionary = {}
var _summon_owner_retirement: Dictionary = {}
var _fallback_room: Node2D
var _fallback_template: Dictionary = {}


func configure(run_id: String, frame: int) -> bool:
	if not _pending.is_empty() or not _actors.is_empty() or not _warnings.is_empty() or not _stable(run_id) or not Contract.integer_in_range(frame, 0, 2147400000):
		return false
	_definitions.clear()
	_death_actions.clear()
	_ordinary_parents.clear()
	_summon_actions.clear()
	_summon_owner_retirement.clear()
	var sources: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/summons.json"))
	if not sources is Array or sources.size() != 9:
		return false
	for source: Dictionary in sources:
		var parser := SummonDefinitionScript.new()
		if not parser.configure(source).ok or _definitions.has(source.id):
			return false
		_definitions[source.id] = parser.snapshot()
	for enemy: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/enemies.json")):
		var parser := EnemyDefinitionScript.new()
		if not parser.configure(enemy).ok:
			return false
		_ordinary_parents[enemy.id] = parser.runtime_projection()
		if not _register_summon_actions(enemy, "enemy"):
			return false
		if enemy.id in ["ruins_wraith", "void_spore"]:
			var parsed: Dictionary = Contract.create(enemy.elite_actions[0], "elite")
			if not parsed.ok or parsed.definition.handler_id != "summon":
				return false
			_death_actions[enemy.id] = parsed.definition
	for boss: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/bosses.json")):
		if not _register_summon_actions(boss, "boss"):
			return false
	_state = {"schema_version": 1, "run_id": run_id, "initial_frame": frame, "runtime_frame": frame, "claims": [], "rows": []}
	return true


func _register_summon_actions(parent: Dictionary, kind: String) -> bool:
	var actions := {}
	for source: Dictionary in parent.actions + parent.get("elite_actions", []):
		if source.handler_id != "summon":
			continue
		var parsed := Contract.create(source, kind)
		if not parsed.ok or actions.has(source.id):
			return false
		actions[source.id] = parsed.definition
	_summon_actions[parent.id] = actions
	_summon_owner_retirement[parent.id] = kind == "boss" or bool(parent.mechanisms.get("retire_summons_on_owner_death", false))
	return true


func configure_native_root(root: Node2D) -> bool:
	if _root != null or not is_instance_valid(root) or not root.is_inside_tree() or root.global_transform != Transform2D.IDENTITY:
		return false
	_root = root
	return true


func configure_native_room(room: Node2D, template: Dictionary) -> bool:
	if _fallback_room != null or not is_instance_valid(room) or not room.is_inside_tree() or not RoomContract.validate(room, template).ok:
		return false
	_fallback_room = room
	_fallback_template = template.duplicate(true)
	return true


func bind_native_targets(actors: Dictionary) -> bool:
	if not _pending.is_empty():
		return false
	for id: String in actors:
		if not is_instance_valid(actors[id]) or not actors[id].has_method("launch_runtime_snapshot"):
			return false
		if actors[id].get("_launch_definition").get("actor_kind") != "summon":
			_owners[id] = actors[id]
	return true


func retired_owner_child_sources(actors: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for row: Dictionary in _state.get("rows", []):
		if not row.retire_on_owner_death:
			continue
		var owner: Variant = actors.get(row.parent_source_id, _owners.get(row.parent_source_id))
		var terminal: bool = not is_instance_valid(owner)
		if not terminal:
			var prepared: Dictionary = owner.get("_prepared_launch_frame")
			terminal = owner.get_node("HealthComponent").dead or bool((prepared.after.runtime if not prepared.is_empty() else owner.launch_runtime_snapshot().runtime).terminal)
		if terminal:
			result.append(str(row.id))
	result.sort()
	return result


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func native_actors() -> Dictionary:
	var result := {}
	for row: Dictionary in _state.get("rows", []):
		if row.phase == "ACTIVE" and is_instance_valid(_actors.get(row.id)):
			result[row.id] = _actors[row.id]
	return result


func owns_child_lease(actor: Node2D, lease: Dictionary) -> bool:
	if not is_instance_valid(actor) or not Contract.exact_fields(lease, LEASE_FIELDS) or _actors.get(lease.id) != actor or str(actor.hostile_source_id) != lease.id:
		return false
	for row: Dictionary in _state.rows:
		if row.id == lease.id:
			return _lease(row) == lease
	return false


func child_retirement_required(actor: Node2D, frame: int) -> bool:
	var lease: Dictionary = actor.get("_summon_lease")
	if not owns_child_lease(actor, lease):
		return false
	if frame >= int(lease.expires_frame):
		return true
	var owner: Variant = _owners.get(lease.parent_source_id)
	return bool(lease.retire_on_owner_death) and (not is_instance_valid(owner) or owner.get_node("HealthComponent").dead)


func capture_native_terminal_split(owner: Node2D, receipt: String, targets: Dictionary) -> bool:
	if not is_instance_valid(owner) or _state.is_empty() or not _pending.is_empty() or not _native_matches(_state):
		return false
	var source := str(owner.hostile_source_id)
	var definition: Dictionary = owner.get("_launch_definition")
	var identity: Dictionary = owner.get("_launch_identity")
	var state: Dictionary = owner.launch_runtime_snapshot().runtime
	var health: Node = owner.get_node("HealthComponent")
	var expected := "hostile_defeat:%s" % (str(identity.run_id) + "|" + source).sha256_text().substr(0, 40)
	var splitting: Dictionary = owner.native_splitting_configuration()
	if _owners.get(source) != owner or definition.actor_kind != "elite" or (not _death_actions.has(definition.id) and splitting.is_empty()) or identity.run_id != _state.run_id or state.runtime_frame != _state.runtime_frame or not state.terminal or not health.dead or health.current_hp != 0.0 or receipt != expected or owner.get("_death_receipt") != expected:
		return false
	if _state.rows.any(func(row: Dictionary): return row.spawn_mode in ["DEATH", "SPLIT"] and row.parent_source_id == source):
		return true
	var before := snapshot()
	var next := snapshot()
	var reserved := false
	if not splitting.is_empty():
		reserved = _reserve_affix_split(next, owner, definition, owner.global_position, targets)
	else:
		var action: Dictionary = _death_actions[definition.id]
		reserved = definition.actions.has(action) and _reserve_death_rows(next, owner, definition, action, int(state.action.next_generation_floor), owner.global_position, targets)
	if not reserved or not can_restore_snapshot(next):
		return false
	_state = next
	if not _sync_native(_state):
		_state = before
		_sync_native(_state, true)
		return false
	return true


func prepare(batches: Array, context: Dictionary) -> Dictionary:
	if _state.is_empty() or not _pending.is_empty() or context.run_id != _state.run_id or context.runtime_frame != int(_state.runtime_frame) + 1 or not _native_matches(_state) or not bind_native_targets(context.actors):
		return _failure("summon_context")
	var before := snapshot()
	var next := snapshot()
	next.runtime_frame = context.runtime_frame
	for row: Dictionary in next.rows:
		if row.phase == "RETIRED":
			continue
		var owner: Variant = _owners.get(row.parent_source_id)
		if row.retire_on_owner_death and (not is_instance_valid(owner) or owner.get_node("HealthComponent").dead):
			_retire(row, int(next.runtime_frame))
		elif row.phase == "ACTIVE":
			var child: Node = _actors.get(row.id)
			var prepared: Dictionary = child.get("_prepared_launch_frame") if is_instance_valid(child) else {}
			if not is_instance_valid(child) or child.get_node("HealthComponent").dead or (not prepared.is_empty() and prepared.after.runtime.terminal):
				_retire(row, int(next.runtime_frame))
	for wrapper: Dictionary in batches:
		var owner: Node2D = context.actors[wrapper.hostile_source_id]
		var definition: Dictionary = owner.get("_launch_definition")
		for request: Dictionary in wrapper.batch.effect_requests:
			if request.handler_id != "summon":
				continue
			var action := {}
			for candidate: Dictionary in definition.actions:
				if candidate.id == request.action_id:
					action = candidate
			if definition.actor_kind == "summon" or owner.prepared_launch_frame_batch() != wrapper.batch or action.is_empty() or request.parameters != action.parameters or request.geometry.size() != int(request.parameters.count) or int(action.warning_frames) < 30 or not _definitions.has(request.parameters.definition_id) or request.hostile_source_id != wrapper.hostile_source_id or request.run_id != next.run_id or request.runtime_frame != next.runtime_frame:
				return _failure("summon_authored_request")
			var claim := JSON.stringify([request.hostile_source_id, request.attack_generation, request.action_id]).sha256_text()
			if next.claims.has(claim) or next.claims.size() >= MAX_LEASES or next.rows.size() + int(request.parameters.count) > MAX_LEASES or _live_count(next, false) + int(request.parameters.count) > MAX_RESERVATIONS:
				return _failure("summon_claim_capacity")
			next.claims.append(claim)
			var projection: Dictionary = SummonProjection.create(_definitions[request.parameters.definition_id])
			var room: Dictionary = owner.launch_room_motion_snapshot()
			if not projection.ok or room.is_empty() or int(request.parameters.lifetime_frames) > int(projection.definition.summon_contract.definition.lifetime_frames):
				return _failure("summon_projection_or_room")
			for index: int in range(int(request.parameters.count)):
				var geometry: Dictionary = request.geometry[index]
				if geometry.shape != "summon_slots" or geometry.summon_slots.size() != 1 or not Contract.valid_point(geometry.summon_slots[0]):
					return _failure("summon_frozen_slot")
				var row := _row(next, owner, definition, action, int(request.attack_generation), index, geometry.summon_slots[0], projection.definition, room)
				if _live_count(next, true) < MAX_SUMMONS and _safe(row, context.targets):
					_birth(row, int(next.runtime_frame))
				next.rows.append(row)
		if not _reserve_terminal_split(next, owner, context.targets):
			return _failure("summon_terminal_split")
		if not _reserve_mirroring(next, owner, context.targets):
			return _failure("summon_mirroring")
	for row: Dictionary in next.rows:
		if row.phase == "PENDING" and row.request_frame < next.runtime_frame and _live_count(next, true) < MAX_SUMMONS and _safe(row, context.targets):
			row.phase = "WARNING"
			row.warning_frame = int(next.runtime_frame)
		elif row.phase == "WARNING" and int(next.runtime_frame) >= int(row.warning_frame) + int(row.spawn_warning_frames):
			if _safe(row, context.targets):
				_birth(row, int(next.runtime_frame))
			else:
				row.phase = "PENDING"
				row.warning_frame = -1
	if not can_restore_snapshot(next) or (_live_count(next, false) > 0 and not is_instance_valid(_root)):
		return _failure("summon_candidate")
	var ticket := {"ticket_id": _next_ticket, "before": before, "after": next, "targets": context.targets.duplicate()}
	_next_ticket += 1
	_pending = ticket.duplicate(true)
	_committed = false
	return {"ok": true, "ticket": ticket.duplicate(true)}


func can_commit(ticket: Dictionary) -> bool:
	return _matches(ticket) and not _committed and snapshot() == ticket.before and _native_matches(ticket.before) and _new_births_safe(ticket)


func commit(ticket: Dictionary) -> bool:
	if not can_commit(ticket):
		return false
	_state = ticket.after.duplicate(true)
	_committed = _sync_native(_state)
	return _committed


func rollback(ticket: Dictionary) -> bool:
	if not _matches(ticket):
		return false
	_state = ticket.before.duplicate(true)
	var ok := _sync_native(_state, true)
	_pending.clear()
	_committed = false
	return ok


func can_publish(ticket: Dictionary) -> bool:
	return _matches(ticket) and _committed and snapshot() == ticket.after and _native_matches(ticket.after) and _new_births_safe(ticket)


func publish(ticket: Dictionary) -> bool:
	if not can_publish(ticket):
		return false
	_sync_native(_state, true)
	_pending.clear()
	_committed = false
	return true


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, STATE_FIELDS) or value.schema_version != 1 or value.run_id != _state.run_id or value.initial_frame != _state.initial_frame or not Contract.integer_in_range(value.runtime_frame, int(value.initial_frame), 2147400000) or not value.claims is Array or value.claims.size() > MAX_LEASES or not value.rows is Array or value.rows.size() > MAX_LEASES:
		return false
	var claims := {}
	for claim: Variant in value.claims:
		if not claim is String or claim.length() != 64 or not claim.is_valid_hex_number(false) or claims.has(claim):
			return false
		claims[claim] = true
	var ids := {}
	for row: Variant in value.rows:
		if not row is Dictionary or not Contract.exact_fields(row, ROW_FIELDS) or not _stable(row.parent_source_id) or not Contract.valid_id(row.parent_definition_id) or not Contract.valid_id(row.action_id) or not Contract.integer_in_range(row.generation, 1, 2147400000) or not Contract.integer_in_range(row.slot_index, 0, 7) or row.id != _row_id(value.run_id, row) or ids.has(row.id) or not Contract.integer_in_range(row.seed, -2147483648, 2147483647) or not Contract.integer_in_range(row.request_frame, int(value.initial_frame) + (0 if row.spawn_mode in ["DEATH", "SPLIT"] else 1), int(value.runtime_frame)) or not Contract.valid_point(row.position) or not row.projection is Dictionary or not Contract.integer_in_range(row.lifetime_frames, 1, 1200) or not Contract.integer_in_range(row.spawn_warning_frames, 30, 120) or row.spawn_mode not in ["ACTION", "DEATH", "MIRROR", "SPLIT"] or typeof(row.retire_on_owner_death) != TYPE_BOOL or row.phase not in ["PENDING", "WARNING", "ACTIVE", "RETIRED"] or not row.room_motion is Dictionary or not row.room_motion.get("bounds") is Dictionary:
			return false
		if not _valid_row_projection(row):
			return false
		var death: Dictionary = _death_actions.get(row.parent_definition_id, {})
		if not claims.has(JSON.stringify([row.parent_source_id, row.generation, row.action_id]).sha256_text()) or not _within_bounds(row):
			return false
		if row.spawn_mode == "DEATH" and (death.is_empty() or row.action_id != death.id or row.slot_index >= death.parameters.count or row.projection.id != death.parameters.definition_id or row.lifetime_frames != death.parameters.lifetime_frames or row.retire_on_owner_death):
			return false
		var authored: Dictionary = _summon_actions.get(row.parent_definition_id, {}).get(row.action_id, {})
		if row.spawn_mode == "ACTION" and (authored.is_empty() or row.projection.id != authored.parameters.definition_id or row.slot_index >= int(authored.parameters.count) or row.lifetime_frames != int(authored.parameters.lifetime_frames) or row.retire_on_owner_death != _summon_owner_retirement.get(row.parent_definition_id)):
			return false
		if row.spawn_mode == "MIRROR" and (row.action_id != MIRROR_ACTION_ID or row.slot_index != 0 or row.projection.id != "elite_mirror" or row.projection.summon_contract.parent != _ordinary_parents.get(row.parent_definition_id, {}) or row.lifetime_frames != int(AffixDefinitionScript.PARAMETERS.mirroring.lifetime_frames) or not row.retire_on_owner_death or int(row.generation) > Mirroring.MAX_RESERVATIONS):
			return false
		for field: String in ["warning_frame", "birth_frame", "expires_frame", "retired_frame"]:
			if not Contract.integer_in_range(row[field], -1, 2147401200):
				return false
		if row.phase == "PENDING" and [row.warning_frame, row.birth_frame, row.expires_frame, row.retired_frame] != [-1, -1, -1, -1]:
			return false
		if row.phase == "WARNING" and (row.warning_frame < row.request_frame or (row.spawn_mode == "ACTION" and row.warning_frame == row.request_frame) or row.warning_frame > value.runtime_frame or row.birth_frame != -1 or row.expires_frame != -1 or row.retired_frame != -1):
			return false
		if row.birth_frame != -1 and (row.birth_frame < row.request_frame or row.birth_frame > value.runtime_frame or row.expires_frame != row.birth_frame + row.lifetime_frames or (row.warning_frame != -1 and row.birth_frame < row.warning_frame + row.spawn_warning_frames)):
			return false
		if row.phase == "ACTIVE" and (row.birth_frame == -1 or row.expires_frame <= value.runtime_frame or row.retired_frame != -1):
			return false
		if row.phase == "RETIRED" and (row.retired_frame < row.request_frame or row.retired_frame > value.runtime_frame):
			return false
		ids[row.id] = true
	for row: Dictionary in value.rows:
		if row.spawn_mode == "SPLIT":
			var pair: Array = value.rows.filter(func(candidate: Dictionary): return candidate.spawn_mode == "SPLIT" and candidate.parent_source_id == row.parent_source_id)
			if pair.size() != 2 or pair[0].slot_index == pair[1].slot_index or pair[0].projection != pair[1].projection or pair[0].request_frame != pair[1].request_frame or pair[0].seed != pair[1].seed or pair[0].room_motion != pair[1].room_motion or pair[0].position == pair[1].position:
				return false
	var live_mirrors := {}
	for row: Dictionary in value.rows:
		if row.spawn_mode == "MIRROR" and row.phase != "RETIRED":
			if live_mirrors.has(row.parent_source_id):
				return false
			live_mirrors[row.parent_source_id] = true
	return _live_count(value, true) <= MAX_SUMMONS and _live_count(value, false) <= MAX_RESERVATIONS


func restore_snapshot(value: Dictionary) -> bool:
	if not _pending.is_empty() or not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return _sync_native(_state, true)


func dispose_native_effects() -> bool:
	if not _pending.is_empty():
		return false
	for node: Node in _actors.values() + _warnings.values():
		if is_instance_valid(node):
			node.queue_free()
	_actors.clear()
	_warnings.clear()
	_owners.clear()
	return true


static func work_records(value: Dictionary) -> Dictionary:
	var records := {}
	for row: Dictionary in value.rows:
		if row.phase != "RETIRED":
			records[row.id] = {"kind": "summon", "owner_source_id": row.parent_source_id, "phase": "PENDING" if row.phase == "PENDING" else "ACTIVE"}
	return records


func _sync_native(value: Dictionary, prune: bool = false) -> bool:
	var active := {}
	var warnings := {}
	for row: Dictionary in value.rows:
		if row.phase == "ACTIVE":
			active[row.id] = true
			if not _actors.has(row.id):
				var owner: Variant = _owners.get(row.parent_source_id)
				var room: Node2D = owner.get("_motion_room") if is_instance_valid(owner) else _fallback_room
				if not is_instance_valid(_root) or not is_instance_valid(room):
					return false
				var actor: Node2D = CopyActor.instantiate_copy(str(row.parent_definition_id)) if row.spawn_mode == "SPLIT" else SummonActor.instantiate_summon(str(row.projection.id))
				if actor == null:
					return false
				_root.add_child(actor)
				actor.global_position = Vector2(float(row.position.x), float(row.position.y))
				var identity := {"run_id": str(value.run_id), "hostile_source_id": str(row.id), "next_generation_floor": 1, "runtime_frame": int(row.birth_frame), "seed": int(row.seed)}
				var template := _fallback_template if room == _fallback_room else _room_template(str(row.room_motion.room_id))
				if template.get("id") != row.room_motion.room_id:
					return false
				if not actor.configure_launch_definition(row.projection, identity).ok or not actor.configure_launch_room_motion(room, template).ok:
					actor.queue_free()
					return false
				_actors[row.id] = actor
				if not actor.configure_summon_lease(self, _lease(row)):
					return false
			_actors[row.id].collision_layer = 4
			_actors[row.id].get_node("Hurtbox").collision_layer = 4
			_actors[row.id].visible = true
		elif row.phase == "WARNING":
			warnings[row.id] = true
			if not _warnings.has(row.id):
				var warning := ZoneProjection.new()
				_root.add_child(warning)
				_warnings[row.id] = warning
			if not _warnings[row.id].project_record({"id": row.id, "damage_type": "void", "geometry": {"shape": "circle", "origin": row.position, "radius": 16.0}, "phase": "WARNING"}, int(value.runtime_frame)):
				return false
	for id: String in _actors.keys():
		if not active.has(id) and prune:
			_actors[id].collision_layer = 0
			_actors[id].get_node("Hurtbox").collision_layer = 0
			_actors[id].visible = false
			_actors[id].queue_free()
			_actors.erase(id)
	for id: String in _warnings.keys():
		if not warnings.has(id):
			_warnings[id].visible = false
			if prune:
				_warnings[id].queue_free()
				_warnings.erase(id)
	return true


func _native_matches(value: Dictionary) -> bool:
	for row: Dictionary in value.rows:
		if row.phase == "ACTIVE":
			var actor: Node = _actors.get(row.id)
			if not is_instance_valid(actor) or actor.is_queued_for_deletion() or actor.get_parent() != _root or actor.get("_launch_definition") != row.projection or not owns_child_lease(actor, _lease(row)) or actor.collision_layer != 4 or actor.get_node("Hurtbox").collision_layer != 4 or not actor.visible:
				return false
		elif row.phase == "WARNING" and (not is_instance_valid(_warnings.get(row.id)) or not _warnings[row.id].visible):
			return false
	return true


func _new_births_safe(ticket: Dictionary) -> bool:
	var previous := {}
	for row: Dictionary in ticket.before.rows:
		if row.phase == "ACTIVE":
			previous[row.id] = true
	for row: Dictionary in ticket.after.rows:
		if row.phase == "ACTIVE" and not previous.has(row.id) and not _safe(row, ticket.targets):
			return false
	return true


func _safe(row: Dictionary, targets: Dictionary) -> bool:
	if not is_instance_valid(_root) or not _within_bounds(row):
		return false
	var position := Vector2(float(row.position.x), float(row.position.y))
	for target: Node2D in targets.values():
		if not is_instance_valid(target) or target.global_position.distance_to(position) <= float(row.projection.collision_radius_px) + 10.0:
			return false
	var shape := CircleShape2D.new()
	shape.radius = float(row.projection.collision_radius_px)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = 1
	return _root.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _reserve_terminal_split(next: Dictionary, owner: Node2D, targets: Dictionary) -> bool:
	var definition: Dictionary = owner.get("_launch_definition")
	var prepared: Dictionary = owner.get("_prepared_launch_frame")
	if definition.actor_kind != "elite" or prepared.is_empty() or not prepared.after.runtime.terminal:
		return true
	if not owner.get_node("HealthComponent").dead and not owner.prepared_launch_frame_consumes_actor():
		return true
	if not owner.native_splitting_configuration().is_empty():
		return _reserve_affix_split(next, owner, definition, Vector2(float(prepared.after.position.x), float(prepared.after.position.y)), targets)
	if not _death_actions.has(definition.id):
		return true
	var action: Dictionary = _death_actions[definition.id]
	if not definition.actions.has(action):
		return false
	var generation: int = int(prepared.before.runtime.action.next_generation_floor)
	var origin := Vector2(float(prepared.after.position.x), float(prepared.after.position.y))
	return _reserve_death_rows(next, owner, definition, action, generation, origin, targets)


func _reserve_affix_split(next: Dictionary, owner: Node2D, definition: Dictionary, origin: Vector2, targets: Dictionary) -> bool:
	var source := str(owner.hostile_source_id)
	var claim := JSON.stringify([source, 1, SPLIT_ACTION_ID]).sha256_text()
	if next.claims.has(claim):
		return true
	if next.claims.size() >= MAX_LEASES or next.rows.size() + 2 > MAX_LEASES or _live_count(next, false) + 2 > MAX_RESERVATIONS:
		return false
	var projection := CopyProjection.create(str(definition.id), owner.native_splitting_configuration())
	var room: Dictionary = owner.launch_room_motion_snapshot()
	if not projection.ok or room.is_empty():
		return false
	var parameters: Dictionary = AffixDefinitionScript.PARAMETERS.splitting
	var action := {"id": SPLIT_ACTION_ID, "parameters": {"definition_id": definition.id, "lifetime_frames": int(parameters.lifetime_frames)}}
	var positions: Array[Vector2] = []
	var receipt := {"sequence": 1, "source_position": {"x": origin.x, "y": origin.y}}
	for index: int in range(2):
		var row := _row(next, owner, definition, action, 1, index, receipt.source_position, projection.definition, room)
		row.id = _split_id(str(next.run_id), source, index)
		row.spawn_mode = "SPLIT"
		row.spawn_warning_frames = int(parameters.spawn_warning_frames)
		row.retire_on_owner_death = false
		var chosen := {}
		for position: Vector2 in Mirroring.candidate_positions(owner.get("_launch_identity"), receipt):
			if positions.any(func(previous: Vector2): return previous.distance_to(position) < float(projection.definition.collision_radius_px) * 2.0 + 4.0):
				continue
			row.position = {"x": position.x, "y": position.y}
			if not _within_bounds(row):
				continue
			if chosen.is_empty():
				chosen = row.position.duplicate(true)
			if _live_count(next, true) < MAX_SUMMONS and _safe(row, targets):
				chosen = row.position.duplicate(true)
				row.phase = "WARNING"
				row.warning_frame = int(next.runtime_frame)
				break
		if chosen.is_empty():
			return false
		row.position = chosen
		positions.append(Vector2(float(chosen.x), float(chosen.y)))
		next.rows.append(row)
	next.claims.append(claim)
	return true


func _reserve_death_rows(next: Dictionary, owner: Node2D, definition: Dictionary, action: Dictionary, generation: int, origin: Vector2, targets: Dictionary) -> bool:
	var source := str(owner.hostile_source_id)
	var claim := JSON.stringify([source, generation, action.id]).sha256_text()
	if next.claims.has(claim):
		return true
	if next.claims.size() >= MAX_LEASES or next.rows.size() + int(action.parameters.count) > MAX_LEASES or _live_count(next, false) + int(action.parameters.count) > MAX_RESERVATIONS:
		return false
	var projection := SummonProjection.create(_definitions[action.parameters.definition_id])
	var room: Dictionary = owner.launch_room_motion_snapshot()
	if not projection.ok or room.is_empty():
		return false
	next.claims.append(claim)
	for index: int in range(int(action.parameters.count)):
		var offset: Dictionary = action.geometry[index].origin_offset
		var position := origin + Vector2(float(offset.x), float(offset.y))
		var row := _row(next, owner, definition, action, generation, index, {"x": position.x, "y": position.y}, projection.definition, room)
		row.spawn_mode = "DEATH"
		row.spawn_warning_frames = int(action.warning_frames)
		if _live_count(next, true) < MAX_SUMMONS and _safe(row, targets):
			row.phase = "WARNING"
			row.warning_frame = int(next.runtime_frame)
		next.rows.append(row)
	return true


func _reserve_mirroring(next: Dictionary, owner: Node2D, targets: Dictionary) -> bool:
	if not owner.has_method("prepared_launch_mirroring_reservation"):
		return true
	var receipt: Dictionary = owner.prepared_launch_mirroring_reservation()
	if receipt.is_empty():
		return true
	var definition: Dictionary = owner.get("_launch_definition")
	var source := str(owner.hostile_source_id)
	var claim := JSON.stringify([source, int(receipt.sequence), MIRROR_ACTION_ID]).sha256_text()
	if definition.actor_kind != "elite" or receipt.runtime_frame != next.runtime_frame or not _ordinary_parents.has(definition.id):
		return false
	if next.claims.has(claim):
		return false
	if next.claims.size() >= MAX_LEASES:
		return true
	next.claims.append(claim)
	if next.rows.any(func(row: Dictionary): return row.spawn_mode == "MIRROR" and row.parent_source_id == source and row.phase != "RETIRED") or next.rows.size() >= MAX_LEASES or _live_count(next, false) >= MAX_RESERVATIONS:
		return true
	var projection := SummonProjection.create(_definitions.elite_mirror, _ordinary_parents[definition.id])
	var room: Dictionary = owner.launch_room_motion_snapshot()
	if not projection.ok or room.is_empty():
		return false
	var action := {"id": MIRROR_ACTION_ID, "parameters": AffixDefinitionScript.PARAMETERS.mirroring.duplicate(true)}
	var row := _row(next, owner, definition, action, int(receipt.sequence), 0, receipt.source_position, projection.definition, room)
	row.id = _mirror_id(str(next.run_id), source, int(receipt.sequence))
	row.spawn_mode = "MIRROR"
	row.spawn_warning_frames = int(action.parameters.spawn_warning_frames)
	row.retire_on_owner_death = true
	var chosen := {}
	for position: Vector2 in Mirroring.candidate_positions(owner.get("_launch_identity"), receipt):
		row.position = {"x": position.x, "y": position.y}
		if not _within_bounds(row):
			continue
		if chosen.is_empty():
			chosen = row.position.duplicate(true)
		if _live_count(next, true) < MAX_SUMMONS and _safe(row, targets):
			chosen = row.position.duplicate(true)
			row.phase = "WARNING"
			row.warning_frame = int(next.runtime_frame)
			break
	if chosen.is_empty():
		return true
	row.position = chosen
	next.rows.append(row)
	return true


static func valid_mirroring_cold_bindings(value: Dictionary, actors: Dictionary) -> bool:
	for row: Dictionary in value.rows:
		if row.spawn_mode != "MIRROR":
			continue
		var owner: Variant = actors.get(row.parent_source_id)
		if not owner is Dictionary:
			if row.phase != "RETIRED":
				return false
			continue
		var receipts: Array = owner.actor.get("affix_runtime", {}).get("mirroring", {}).get("reservations", [])
		if owner.definition_id != row.parent_definition_id or owner.identity.seed != row.seed or receipts.size() < int(row.generation):
			return false
		var receipt: Dictionary = receipts[int(row.generation) - 1]
		if receipt.runtime_frame != row.request_frame or not Mirroring.authentic_position(owner.identity, receipt, row.position):
			return false
	for source: String in actors:
		var owner: Dictionary = actors[source]
		for receipt: Dictionary in owner.actor.get("affix_runtime", {}).get("mirroring", {}).get("reservations", []):
			if not value.claims.has(JSON.stringify([source, int(receipt.sequence), MIRROR_ACTION_ID]).sha256_text()) and value.claims.size() < MAX_LEASES:
				return false
	return true


func _row(next: Dictionary, owner: Node2D, definition: Dictionary, action: Dictionary, generation: int, index: int, position: Dictionary, projection: Dictionary, room: Dictionary) -> Dictionary:
	return {"id": _id(str(next.run_id), str(owner.hostile_source_id), generation, index), "parent_source_id": str(owner.hostile_source_id), "parent_definition_id": str(definition.id), "action_id": str(action.id), "generation": generation, "slot_index": index, "seed": int(owner.get("_launch_identity").seed), "request_frame": int(next.runtime_frame), "position": position.duplicate(true), "projection": projection.duplicate(true), "lifetime_frames": int(action.parameters.lifetime_frames), "spawn_warning_frames": int(_definitions.get(action.parameters.definition_id, {}).get("spawn_warning_frames", 30)), "spawn_mode": "ACTION", "retire_on_owner_death": definition.actor_kind == "boss" or bool(definition.mechanisms.get("retire_summons_on_owner_death", false)), "phase": "PENDING", "warning_frame": -1, "birth_frame": -1, "expires_frame": -1, "retired_frame": -1, "room_motion": room.duplicate(true)}


func _valid_row_projection(row: Dictionary) -> bool:
	if row.spawn_mode == "SPLIT":
		return row.action_id == SPLIT_ACTION_ID and row.generation == 1 and row.slot_index in [0, 1] and CopyProjection.validate(row.projection) and row.projection.id == row.parent_definition_id and row.lifetime_frames == int(AffixDefinitionScript.PARAMETERS.splitting.lifetime_frames) and row.spawn_warning_frames == int(AffixDefinitionScript.PARAMETERS.splitting.spawn_warning_frames) and not row.retire_on_owner_death
	var contract: Variant = row.projection.get("summon_contract")
	if not contract is Dictionary or not contract.get("definition") is Dictionary or not contract.get("parent") is Dictionary:
		return false
	var projection := SummonProjection.create(contract.definition, contract.parent)
	var death: Dictionary = _death_actions.get(row.parent_definition_id, {})
	var warning: int = int(AffixDefinitionScript.PARAMETERS.mirroring.spawn_warning_frames) if row.spawn_mode == "MIRROR" else (int(death.get("warning_frames", -1)) if row.spawn_mode == "DEATH" else int(contract.definition.spawn_warning_frames))
	return projection.ok and projection.definition == row.projection and row.lifetime_frames <= contract.definition.lifetime_frames and row.spawn_warning_frames == warning


static func _within_bounds(row: Dictionary) -> bool:
	var bounds: Dictionary = row.room_motion.bounds
	if not Contract.exact_fields(bounds, ["x", "y", "width", "height"]) or not Contract.valid_point({"x": bounds.x, "y": bounds.y}) or not Contract.number_in_range(bounds.width, 1.0, 6400.0) or not Contract.number_in_range(bounds.height, 1.0, 6400.0):
		return false
	return Rect2(float(bounds.x), float(bounds.y), float(bounds.width), float(bounds.height)).grow(-float(row.projection.collision_radius_px)).has_point(Vector2(float(row.position.x), float(row.position.y)))


static func _lease(row: Dictionary) -> Dictionary:
	var lease := {}
	for field: String in LEASE_FIELDS:
		lease[field] = row[field]
	return lease


static func _birth(row: Dictionary, frame: int) -> void:
	row.phase = "ACTIVE"
	row.birth_frame = frame
	row.expires_frame = frame + int(row.lifetime_frames)


static func _retire(row: Dictionary, frame: int) -> void:
	row.phase = "RETIRED"
	row.retired_frame = frame


static func _live_count(value: Dictionary, active_only: bool) -> int:
	var count := 0
	for row: Dictionary in value.rows:
		count += int(row.phase in ["ACTIVE", "WARNING"] if active_only else row.phase != "RETIRED")
	return count


static func _room_template(id: String) -> Dictionary:
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if row.id == id:
			return row
	return {}


static func _id(run_id: String, source_id: String, generation: int, slot: int) -> String:
	return "summon_" + JSON.stringify([run_id, source_id, generation, slot]).sha256_text().substr(0, 56)


static func _mirror_id(run_id: String, source_id: String, sequence: int) -> String:
	return "summon_" + JSON.stringify([run_id, source_id, "affix:mirroring", sequence, 0]).sha256_text().substr(0, 56)


static func _split_id(run_id: String, source_id: String, slot: int) -> String:
	return "summon_" + JSON.stringify([run_id, source_id, "affix:splitting", 1, slot]).sha256_text().substr(0, 56)


static func _row_id(run_id: String, row: Dictionary) -> String:
	if row.spawn_mode == "SPLIT":
		return _split_id(run_id, row.parent_source_id, row.slot_index)
	return _mirror_id(run_id, row.parent_source_id, row.generation) if row.spawn_mode == "MIRROR" else _id(run_id, row.parent_source_id, row.generation, row.slot_index)


static func _stable(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 128


func _matches(ticket: Dictionary) -> bool:
	return not _pending.is_empty() and _pending == ticket


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "code": &"NATIVE_SUMMON_INVALID", "context": {"reason": reason}}
