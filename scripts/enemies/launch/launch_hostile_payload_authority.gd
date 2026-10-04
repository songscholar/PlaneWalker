class_name LaunchHostilePayloadAuthority
extends RefCounted

const Runtime := preload("res://scripts/enemies/launch/launch_hostile_payload_runtime.gd")
const ProjectionScript := preload("res://scripts/enemies/launch/launch_hostile_payload_projection.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const TICKET_FIELDS := ["ticket_id", "runtime_frame", "before", "after", "damage_requests", "native_contacts", "target_positions", "targets"]

var _runtime: RefCounted = Runtime.new()
var _root: Node2D
var _nodes: Dictionary = {}
var _pending: Dictionary = {}
var _committed := false
var _next_ticket := 1
var _known_targets: Dictionary = {}


func configure(run_id: String, frame: int) -> bool:
	return _pending.is_empty() and _nodes.is_empty() and _runtime.configure(run_id, frame)


func configure_native_root(root: Node2D) -> bool:
	if _root != null or not _pending.is_empty() or not is_instance_valid(root) or not root.is_inside_tree() or not root.global_transform.is_equal_approx(Transform2D.IDENTITY):
		return false
	_root = root
	return true


func snapshot() -> Dictionary:
	return _runtime.snapshot()


func native_nodes() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for row: Dictionary in _records(snapshot()):
		if row.phase != "PENDING" and _nodes.has(row.id) and is_instance_valid(_nodes[row.id]):
			result.append(_nodes[row.id])
	return result


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


func prepare_payloads(batches: Array, context: Dictionary) -> Dictionary:
	if not _pending.is_empty() or context.runtime_frame != int(snapshot().runtime_frame) + 1 or context.run_id != snapshot().run_id or not _native_matches(snapshot()):
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
	var advanced: Dictionary = preview.advance_frame(context.runtime_frame, {"projectile_contacts": contacts, "targets": target_descriptors})
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
			if mechanism.get("kind", "") != "death_pool":
				continue
			var room: Dictionary = actor.launch_room_motion_snapshot()
			if _root == null or room.is_empty() or not actor.has_method("prepared_launch_frame_reserves_death_pool") or not actor.prepared_launch_frame_reserves_death_pool() or not actor.get_node("HealthComponent").dead or mechanism.bounds != room.bounds or not preview.reserve_death_pool(mechanism).ok:
				return _failure("unsealed_death_pool")
	var ticket := {"ticket_id": _next_ticket, "runtime_frame": context.runtime_frame, "before": before, "after": preview.snapshot(), "damage_requests": advanced.damage_requests, "native_contacts": native_contacts, "target_positions": target_descriptors, "targets": context.targets.duplicate() if has_live_payloads else {}}
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
	return true


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
	return _ticket_matches(ticket) and _committed and snapshot() == ticket.after and _native_matches(ticket.after)


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
	return true


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
		if not node.is_inside_tree() or node.get_parent() != _root or not node.visible or node.global_position != Vector2(position.x, position.y) or not node.native_definition_matches(row.definition) or row.definition.kind == "projectile" and not node.native_hit_targets_match(row.hit_targets):
			return false
	return true


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
