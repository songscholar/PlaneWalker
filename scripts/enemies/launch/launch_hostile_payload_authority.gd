class_name LaunchHostilePayloadAuthority
extends RefCounted

const Runtime := preload("res://scripts/enemies/launch/launch_hostile_payload_runtime.gd")
const ProjectionScript := preload("res://scripts/enemies/launch/launch_hostile_payload_projection.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const DebrisNode := preload("res://scripts/enemies/launch/launch_ruin_debris.gd")
const Calculator := preload("res://scripts/combat/damage_calculator.gd")
const TICKET_FIELDS := ["ticket_id", "runtime_frame", "before", "after", "damage_requests", "semantic_impacts", "native_contacts", "target_positions", "targets", "landing_queries", "static_exclusions"]

var _runtime: RefCounted = Runtime.new()
var _root: Node2D
var _nodes: Dictionary = {}
var _pending: Dictionary = {}
var _committed := false
var _next_ticket := 1
var _known_targets: Dictionary = {}
var _debris_nodes: Dictionary = {}


func configure(run_id: String, frame: int) -> bool:
	return _pending.is_empty() and _nodes.is_empty() and _debris_nodes.is_empty() and _runtime.configure(run_id, frame)


func configure_native_root(root: Node2D) -> bool:
	if _root != null or not _pending.is_empty() or not is_instance_valid(root) or not root.is_inside_tree() or not root.global_transform.is_equal_approx(Transform2D.IDENTITY):
		return false
	_root = root
	return true


func snapshot() -> Dictionary:
	return _runtime.snapshot()


func owns_semantic_impact(impact: Dictionary) -> bool:
	return not _pending.is_empty() and not _committed and _pending.semantic_impacts.has(impact) and impact.runtime_frame == _pending.runtime_frame


func native_nodes() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for row: Dictionary in _records(snapshot()):
		if row.phase not in ["PENDING", "DORMANT"] and _nodes.has(row.id) and is_instance_valid(_nodes[row.id]):
			result.append(_nodes[row.id])
	return result


func native_debris_nodes() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for row: Dictionary in snapshot().get("arena_debris", {}).get("rows", []):
		if row.phase == "ACTIVE" and _debris_nodes.has(row.id) and is_instance_valid(_debris_nodes[row.id]):
			result.append(_debris_nodes[row.id])
	return result


func debris_active_count() -> int:
	return native_debris_nodes().size()


func receive_debris_hit(id: String, info: RefCounted) -> float:
	if not _pending.is_empty() or info == null or not _native_matches(snapshot()):
		return 0.0
	var attacker: Node = info.attacker
	var run := StringName(str(snapshot().run_id))
	if not is_instance_valid(attacker) or not attacker is PlayerController or attacker.current_run_id() != run or info.run_id not in [run, &"runtime"]:
		return 0.0
	var amount: float = Calculator.critical_amount(info, float(info.amount))
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	var data: Dictionary = info.snapshot()
	var frame: int = attacker.health.frame_signal_transaction_runtime_frame()
	var result: Dictionary = _runtime.accept_debris_damage({"fact_id": JSON.stringify([data.run_id, data.target_id, data.hostile_source_id, data.attack_generation, data.hit_index, id]).sha256_text(), "run_id": str(run), "construct_id": id, "runtime_frame": int(snapshot().runtime_frame) if frame < 0 else frame, "amount": amount})
	if not result.ok or not _sync_debris(snapshot()):
		return 0.0
	return float(result.amount)


func add_control_source(id: String, source: String, kind: String, frames: int, magnitude: float) -> bool:
	return _pending.is_empty() and _runtime.add_control_source(id, source, kind, frames, magnitude)


func clear_control_source(id: String, source: String) -> bool:
	return _pending.is_empty() and _runtime.clear_control_source(id, source)


func payload_modifiers(id: String) -> Dictionary:
	for row: Dictionary in _records(snapshot()):
		if row.id == id:
			return _runtime._modifiers(row.control)
	return {}


func transaction_snapshot() -> Dictionary:
	return snapshot() if _pending.is_empty() else {}


func can_restore_transaction_snapshot(value: Dictionary) -> bool:
	return _runtime.can_restore_snapshot(value)


func restore_transaction_snapshot(value: Dictionary) -> bool:
	if not _pending.is_empty() or not _runtime.restore_snapshot(value):
		return false
	return _sync_native(value, true)


func prepare_payloads(batches: Array, context: Dictionary, foreign_active_zones: int = 0, retired_children: Array[String] = [], foreign_constructs: int = 0) -> Dictionary:
	if foreign_constructs < 0 or foreign_constructs > 8 or foreign_active_zones < 0 or foreign_active_zones > Runtime.MAX_ZONES or not _pending.is_empty() or context.runtime_frame != int(snapshot().runtime_frame) + 1 or context.run_id != snapshot().run_id or not _native_matches(snapshot()):
		return _failure("unavailable_or_native_projection")
	var before := snapshot()
	var has_live_payloads: bool = not before.projectiles.is_empty() or not before.zones.is_empty()
	var target_descriptors := _target_descriptors(context.targets) if has_live_payloads else {}
	if has_live_payloads and target_descriptors.size() != context.targets.size():
		return _failure("target_geometry")
	var contacts: Dictionary = {}
	var native_contacts: Array[Dictionary] = []
	var motion: Dictionary = _runtime.motion_for_frame(context.runtime_frame)
	for id: String in motion:
		if not _nodes.has(id):
			return _failure("missing_projectile_body")
		var node: CharacterBody2D = _nodes[id]
		var displacement := Vector2(motion[id].displacement.x, motion[id].displacement.y)
		if displacement.is_zero_approx():
			continue
		var collision := node.move_and_collide(displacement, true)
		if collision == null:
			continue
		var collider: Object = collision.get_collider()
		var target_id := ""
		for candidate: String in context.targets:
			if context.targets[candidate] == collider:
				target_id = candidate
				break
		var position := node.global_position + collision.get_travel()
		contacts[id] = {"kind": "world" if target_id.is_empty() else "target", "target_id": target_id, "position": {"x": position.x, "y": position.y}}
		native_contacts.append({"id": id, "node": node, "collider": collider, "position": position})
	var preview := Runtime.new()
	preview.configure(before.run_id, before.initial_frame)
	if not preview.restore_snapshot(before):
		return _failure("checkpoint")
	var retired_sources: Array[String] = retired_children.duplicate()
	var terminal_sources: Array[String] = retired_children.duplicate()
	for source: String in context.actors:
		if bool(context.actors[source].launch_runtime_snapshot().runtime.terminal):
			retired_sources.append(source)
			terminal_sources.append(source)
	for wrapper: Dictionary in batches:
		var actor: Node2D = context.actors[wrapper.hostile_source_id]
		if not retired_sources.has(str(wrapper.hostile_source_id)) and actor.has_method("prepared_launch_arena_payloads_retired") and actor.prepared_launch_arena_payloads_retired():
			retired_sources.append(str(wrapper.hostile_source_id))
	preview.retire_arena_payloads(retired_sources)
	preview.retire_payload_sources(terminal_sources)
	var zone_capacity := Runtime.MAX_ZONES - foreign_active_zones
	var debris_context := _debris_context(before, context, contacts, motion, foreign_constructs)
	var advanced: Dictionary = preview.advance_frame(context.runtime_frame, {"projectile_contacts": contacts, "targets": target_descriptors}, zone_capacity, debris_context)
	if not advanced.ok:
		return advanced
	for wrapper: Dictionary in batches:
		var actor: Node2D = context.actors[wrapper.hostile_source_id]
		for hit: Dictionary in wrapper.batch.hit_facts:
			if hit.handler_id != "projectile_volley":
				continue
			var room: Dictionary = actor.launch_room_motion_snapshot()
			if _root == null or room.is_empty() or not actor.has_method("prepared_launch_payload_parameters"):
				return _failure("missing_payload_room_authority")
			var mechanisms: Dictionary = actor.prepared_launch_payload_parameters()
			if not preview.reserve_projectile(hit, room.bounds, mechanisms).ok:
				return _failure("projectile_reservation")
		for mechanism: Dictionary in wrapper.batch.get("mechanism_requests", []):
			if mechanism.get("kind", "") == "boss_aftershock":
				if _root == null or not actor.has_method("prepared_launch_arena_payload_allowed") or not actor.prepared_launch_arena_payload_allowed(mechanism) or not preview.reserve_boss_aftershock(mechanism, zone_capacity).ok:
					return _failure("unsealed_boss_aftershock")
				continue
			if mechanism.get("kind", "") != "death_pool":
				continue
			var room: Dictionary = actor.launch_room_motion_snapshot()
			if _root == null or room.is_empty() or not actor.has_method("prepared_launch_frame_reserves_death_pool") or not actor.prepared_launch_frame_reserves_death_pool() or not actor.get_node("HealthComponent").dead or mechanism.bounds != room.bounds or not preview.reserve_death_pool(mechanism, zone_capacity).ok:
				return _failure("unsealed_death_pool")
	var after: Dictionary = preview.snapshot()
	var active_before: Dictionary = {}
	for row: Dictionary in before.get("arena_debris", {}).get("rows", []):
		if row.phase == "ACTIVE":
			active_before[row.id] = true
	var landing_queries: Array[Dictionary] = []
	for row: Dictionary in after.get("arena_debris", {}).get("rows", []):
		if row.phase == "ACTIVE" and not active_before.has(row.id):
			landing_queries.append(row.position.duplicate(true))
	var ticket := {"ticket_id": _next_ticket, "runtime_frame": context.runtime_frame, "before": before, "after": after, "damage_requests": advanced.damage_requests, "semantic_impacts": advanced.semantic_impacts, "native_contacts": native_contacts, "target_positions": target_descriptors, "targets": context.targets.duplicate() if has_live_payloads else {}, "landing_queries": landing_queries, "static_exclusions": debris_context.static_exclusions}
	_next_ticket += 1
	_pending = ticket.duplicate(true)
	_committed = false
	return {"ok": true, "ticket": ticket.duplicate(true), "damage_requests": advanced.damage_requests.duplicate(true)}


func can_commit(ticket: Dictionary) -> bool:
	if not _ticket_matches(ticket) or _committed or snapshot() != ticket.before or not _native_matches(ticket.before) or not _runtime.can_restore_snapshot(ticket.after) or _target_descriptors(ticket.targets) != ticket.target_positions:
		return false
	var motion: Dictionary = _runtime.motion_for_frame(ticket.runtime_frame)
	var sealed_contacts: Dictionary = {}
	for contact: Dictionary in ticket.native_contacts:
		if not is_instance_valid(contact.node) or not is_instance_valid(contact.collider) or not motion.has(contact.id):
			return false
		sealed_contacts[contact.id] = contact
	for id: String in motion:
		var displacement := Vector2(motion[id].displacement.x, motion[id].displacement.y)
		if displacement.is_zero_approx():
			continue
		var node: CharacterBody2D = _nodes[id]
		var collision := node.move_and_collide(displacement, true)
		if (collision == null) != (not sealed_contacts.has(id)):
			return false
		if collision != null:
			var contact: Dictionary = sealed_contacts[id]
			if collision.get_collider() != contact.collider or not (node.global_position + collision.get_travel()).is_equal_approx(contact.position):
				return false
	return _landing_queries_clear(ticket.landing_queries, ticket.static_exclusions)


func commit(ticket: Dictionary) -> bool:
	if not can_commit(ticket) or not _runtime.restore_snapshot(ticket.after):
		return false
	for id: String in ticket.targets:
		_known_targets[id] = weakref(ticket.targets[id])
	if not _sync_native(ticket.after):
		return false
	_committed = true
	return true


func rollback(ticket: Dictionary) -> bool:
	if not _ticket_matches(ticket) or not _runtime.restore_snapshot(ticket.before) or not _sync_native(ticket.before, true):
		return false
	_pending.clear()
	_committed = false
	return true


func can_publish(ticket: Dictionary) -> bool:
	return _ticket_matches(ticket) and _committed and snapshot() == ticket.after and _native_matches(ticket.after) and _landing_queries_clear(ticket.landing_queries, ticket.static_exclusions)


func publish(ticket: Dictionary) -> bool:
	if not can_publish(ticket):
		return false
	_prune_native(ticket.after)
	_pending.clear()
	_committed = false
	return true


func _sync_native(value: Dictionary, prune: bool = false) -> bool:
	var live: Dictionary = {}
	for row: Dictionary in _records(value):
		if row.phase == "PENDING":
			continue
		if not is_instance_valid(_root) or not _root.is_inside_tree():
			return false
		if not _nodes.has(row.id):
			var node := ProjectionScript.new()
			if not node.configure_payload(self, row.id, row.definition):
				node.free()
				return false
			_root.add_child(node)
			_nodes[row.id] = node
		if not is_instance_valid(_nodes[row.id]) or not _nodes[row.id].project_record(row, int(value.runtime_frame)):
			return false
		if row.definition.kind == "projectile":
			var bodies: Dictionary = {}
			for id: String in row.hit_targets:
				if _known_targets.has(id):
					bodies[id] = _known_targets[id].get_ref()
			if not _nodes[row.id].project_hit_targets(row.hit_targets, bodies):
				return false
		live[row.id] = true
	for id: String in _nodes:
		if not live.has(id):
			if not is_instance_valid(_nodes[id]):
				return false
			_nodes[id].deactivate()
	if prune:
		_prune_native(value)
	return _sync_debris(value, prune)


func _prune_native(value: Dictionary) -> void:
	var live: Dictionary = {}
	for row: Dictionary in _records(value):
		if row.phase != "PENDING":
			live[row.id] = true
	for id: String in _nodes.keys():
		if not live.has(id):
			var node: Node2D = _nodes[id]
			_nodes.erase(id)
			if not is_instance_valid(node):
				continue
			node.deactivate()
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	_prune_debris(value)


func _native_matches(value: Dictionary) -> bool:
	if _root != null and (not is_instance_valid(_root) or not _root.is_inside_tree() or _root.is_queued_for_deletion() or not _root.global_transform.is_equal_approx(Transform2D.IDENTITY)):
		return false
	for row: Dictionary in _records(value):
		if row.phase == "PENDING":
			continue
		if not is_instance_valid(_root) or not _root.global_transform.is_equal_approx(Transform2D.IDENTITY) or not _nodes.has(row.id) or not is_instance_valid(_nodes[row.id]):
			return false
		var node: Node2D = _nodes[row.id]
		var position: Dictionary = row.position if row.definition.kind == "projectile" else row.definition.position
		if not node.is_inside_tree() or node.get_parent() != _root or node.visible != (row.phase != "DORMANT") or node.global_position != Vector2(position.x, position.y) or not node.native_definition_matches(row.definition) or row.definition.kind == "projectile" and not node.native_hit_targets_match(row.hit_targets):
			return false
	return _debris_matches(value)


func _sync_debris(value: Dictionary, prune: bool = false) -> bool:
	var rows: Dictionary = {}
	for row: Dictionary in value.get("arena_debris", {}).get("rows", []):
		if row.activated_frame >= 0:
			rows[row.id] = row
		if row.phase != "ACTIVE":
			continue
		if not is_instance_valid(_root):
			return false
		if not _debris_nodes.has(row.id):
			var node := DebrisNode.new()
			node.configure(self, str(row.id))
			_root.add_child(node)
			_debris_nodes[row.id] = node
		_debris_nodes[row.id].present(row)
	for id: String in _debris_nodes:
		if rows.has(id):
			_debris_nodes[id].present(rows[id])
		else:
			_debris_nodes[id].deactivate()
	if prune:
		_prune_debris(value)
	return true


func _prune_debris(value: Dictionary) -> void:
	var live: Dictionary = {}
	for row: Dictionary in value.get("arena_debris", {}).get("rows", []):
		if row.phase == "ACTIVE":
			live[row.id] = true
	for id: String in _debris_nodes.keys():
		if live.has(id):
			continue
		var node: Node = _debris_nodes[id]
		_debris_nodes.erase(id)
		if is_instance_valid(node):
			node.deactivate()
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()


func _debris_matches(value: Dictionary) -> bool:
	for row: Dictionary in value.get("arena_debris", {}).get("rows", []):
		if row.phase == "ACTIVE" and (not _debris_nodes.has(row.id) or not is_instance_valid(_debris_nodes[row.id]) or _debris_nodes[row.id].get_parent() != _root or not _debris_nodes[row.id].native_geometry_matches(row)):
			return false
	return true


func _debris_context(value: Dictionary, context: Dictionary, contacts: Dictionary, motion: Dictionary, foreign_constructs: int = 0) -> Dictionary:
	if value.get("schema_version") != 2:
		return {"occupied": {}, "foreign_constructs": 0, "retired_sources": [], "static_exclusions": []}
	var occupied: Dictionary = {}
	var count := foreign_constructs
	var retired: Array[String] = []
	for source: String in context.actors:
		var actor: Node2D = context.actors[source]
		var state: Dictionary = actor.launch_runtime_snapshot().runtime
		var prepared: Dictionary = actor.get("_prepared_launch_frame")
		if not prepared.is_empty():
			state = prepared.after.runtime
		if state.terminal and actor.get("_launch_definition").id == "ruin_king":
			retired.append(source)
		var radius: float = actor.get("_launch_definition").collision_radius_px
		occupied[source + ":body"] = {"position": {"x": actor.global_position.x, "y": actor.global_position.y}, "radius": radius, "clearance": 0.0}
		if not prepared.is_empty():
			occupied[source + ":candidate"] = {"position": prepared.after.position.duplicate(true), "radius": radius, "clearance": 0.0}
		if not state.terminal and int(state.mechanism_state.get("dormancy_remaining_frames", 0)) > 0:
			count += 1
			occupied[source + ":dormant-sigil"] = {"position": {"x": actor.global_position.x, "y": actor.global_position.y}, "radius": 12.0, "clearance": 0.0}
		var arena: Dictionary = state.get("arena_state", {})
		if arena.is_empty() or arena.terminal:
			continue
		var room: Dictionary = actor.launch_room_motion_snapshot()
		var origin := Vector2.ZERO if room.is_empty() else Vector2(float(room.bounds.x), float(room.bounds.y))
		for row: Dictionary in arena.get("covers", []) + arena.get("walls", []) + arena.get("roots", []):
			if row.broken or row.get("expired", false) or row.get("retired", false):
				continue
			count += 1
			occupied[source + ":" + row.id] = {"position": {"x": origin.x + float(row.position.x), "y": origin.y + float(row.position.y)}, "radius": float(row.radius_px) + float(row.get("length_px", 0.0)) * 0.5, "clearance": 48.0}
	for id: String in context.targets:
		var target: Node2D = context.targets[id]
		var shape := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null and shape.shape is CircleShape2D:
			occupied["target:" + id] = {"position": {"x": target.global_position.x, "y": target.global_position.y}, "radius": float(shape.shape.radius), "clearance": 0.0}
	var bounds: Dictionary = {}
	var active := 0
	for row: Dictionary in value.get("arena_debris", {}).get("rows", []):
		active += int(row.phase == "ACTIVE" and int(row.age) + 1 < 480)
		if row.phase == "PENDING":
			bounds[JSON.stringify(row.event.bounds)] = row.event.bounds
	if active >= mini(4, 8 - count):
		bounds.clear()
	for row: Dictionary in value.projectiles:
		if not row.definition.has("debris_recipe") or row.phase != "ACTIVE":
			continue
		if contacts.has(row.id) or not motion[row.id].action_paused and (int(row.age) + 1 >= int(row.definition.lifetime_frames) or Runtime._vector(motion[row.id].from).distance_to(Runtime._vector(row.definition.origin)) + Runtime._vector(motion[row.id].displacement).length() >= float(row.definition.range_px) - 0.00001 or not Runtime._inside(motion[row.id].to, row.definition.bounds)):
			bounds[JSON.stringify(row.definition.bounds)] = row.definition.bounds
	var excluded: Array[RID] = []
	for node: Node2D in native_debris_nodes():
		excluded.append(node.get_rid())
	for actor: Node2D in context.actors.values():
		var arena := actor.get_node_or_null("ArenaConstructs")
		if arena != null:
			for body: CollisionObject2D in arena.get_children():
				excluded.append(body.get_rid())
	for room_bounds: Dictionary in bounds.values():
		occupied.merge(_blocked_debris_candidates(room_bounds, excluded))
	return {"occupied": occupied, "foreign_constructs": count, "retired_sources": retired, "static_exclusions": excluded}


func _landing_queries_clear(points: Array, excluded: Array) -> bool:
	if points.is_empty():
		return true
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 60.0
	query.shape = shape
	query.collision_mask = 1
	query.collide_with_areas = false
	var exclusions: Array[RID] = []
	exclusions.assign(excluded)
	for node: Node2D in native_debris_nodes():
		exclusions.append(node.get_rid())
	query.exclude = exclusions
	for point: Dictionary in points:
		query.transform = Transform2D(0.0, Runtime._vector(point))
		if not _root.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


func _blocked_debris_candidates(bounds: Dictionary, excluded: Array[RID]) -> Dictionary:
	var blocked: Dictionary = {}
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 60.0
	query.shape = shape
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = excluded
	for point: Vector2 in Runtime.Debris.candidate_positions(bounds, {"x": float(bounds.x), "y": float(bounds.y)}):
		query.transform = Transform2D(0.0, point)
		if not _root.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			blocked["static:%s:%s" % [point.x, point.y]] = {"position": {"x": point.x, "y": point.y}, "radius": 0.0, "clearance": 0.0}
	return blocked


func _ticket_matches(ticket: Dictionary) -> bool:
	return Contract.exact_fields(ticket, TICKET_FIELDS) and not _pending.is_empty() and ticket == _pending


static func _records(value: Dictionary) -> Array:
	return value.projectiles + value.zones


static func _target_descriptors(targets: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in targets:
		var target: Variant = targets[id]
		if not target is Node2D or not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
			return {}
		var body := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if body == null or not body.is_inside_tree() or not body.shape is CircleShape2D or body.disabled or not body.transform.is_equal_approx(Transform2D.IDENTITY) or not target.global_scale.is_equal_approx(Vector2.ONE) or not Contract.number_in_range(body.shape.radius, 1, 32):
			return {}
		result[id] = {"position": {"x": target.global_position.x, "y": target.global_position.y}, "collision_radius_px": body.shape.radius}
	return result


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "code": &"HOSTILE_PAYLOAD_NATIVE_INVALID", "context": {"reason": reason}}
