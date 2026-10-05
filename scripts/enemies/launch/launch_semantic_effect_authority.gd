class_name LaunchSemanticEffectAuthority
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Geometry := preload("res://scripts/combat/hostile_threat_registry.gd")
const ActorScript := preload("res://scripts/enemies/launch/launch_hostile_actor.gd")
const ZoneProjection := preload("res://scripts/enemies/launch/launch_semantic_zone_projection.gd")
const StormPattern := preload("res://scripts/enemies/launch/launch_storm_pattern.gd")
const Spatial := preload("res://scripts/enemies/launch/enemy_spatial_runtime.gd")
const SpatialConstruct := preload("res://scripts/enemies/launch/launch_enemy_spatial_construct.gd")
const Calculator := preload("res://scripts/combat/damage_calculator.gd")
const LEGACY_STATE_FIELDS := ["schema_version", "run_id", "initial_frame", "runtime_frame", "claims", "heal_sources", "heal_recipients", "histories", "zones", "statuses"]
const STATE_FIELDS := ["schema_version", "run_id", "initial_frame", "runtime_frame", "claims", "heal_sources", "heal_recipients", "histories", "zones", "statuses", "spatial"]
const ZONE_FIELDS := ["id", "source_id", "action_id", "generation", "hit_index", "reserved_frame", "active_frame", "expires_frame", "geometry", "initial_damage", "damage", "damage_type", "tick_damage_type", "tick_frames", "warning_frames", "lifetime_frames", "slow_multiplier", "slow_frames", "enemy_only_freeze", "owner_immunity", "ally_damage", "owner_zone_cap", "phase"]
const STATUS_FIELDS := ["id", "target_id", "expires_frame", "slow_multiplier", "speed_multiplier", "attack_multiplier", "freeze_actions"]
const MAX_CLAIMS := 4096
const MAX_ZONES := 12
const MAX_RESERVATIONS := 256
const MAX_FRAME := 2147483647 - Contract.MAX_FRAME

var _state: Dictionary = {}
var _pending: Dictionary = {}
var _next_ticket := 1
var _committed := false
var _root: Node2D
var _nodes: Dictionary = {}
var _targets: Dictionary = {}
var _geometry: RefCounted = Geometry.new()
var _spatial: RefCounted = Spatial.new()
var _spatial_nodes := {}
var _frame_authority: WeakRef


func configure(run_id: String, frame: int = 0) -> bool:
	if not _pending.is_empty() or not _nodes.is_empty() or not _stable(run_id) or not _frame(frame) or not _spatial.configure_catalog():
		return false
	_state = {"schema_version": 2, "run_id": run_id, "initial_frame": frame, "runtime_frame": frame, "claims": [], "heal_sources": {}, "heal_recipients": {}, "histories": {}, "zones": [], "statuses": [], "spatial": Spatial.initial_state(run_id, frame)}
	return true


func configure_native_root(root: Node2D) -> bool:
	if _root != null or not _pending.is_empty() or not is_instance_valid(root) or not root.is_inside_tree() or not root.global_transform.is_equal_approx(Transform2D.IDENTITY):
		return false
	_root = root
	return true


func bind_native_targets(actors: Dictionary, targets: Dictionary) -> bool:
	if _state.is_empty() or not _pending.is_empty() or actors.size() > 32 or targets.size() > 8:
		return false
	var combined := targets.duplicate()
	for id: String in actors:
		if combined.has(id) or not _native_actor(actors[id]) or str(actors[id].hostile_source_id) != id:
			return false
		combined[id] = actors[id]
	if _observations(combined).size() != combined.size():
		return false
	_targets = combined
	return true


func dispose_native_effects() -> bool:
	if not _pending.is_empty() or _state.is_empty():
		return false
	var checkpoints := _status_checkpoints(_targets)
	if not _apply_statuses({"statuses": []}, _targets):
		_restore_status_checkpoints(checkpoints)
		return false
	_state.zones = []
	_state.statuses = []
	for row: Dictionary in _state.spatial.rows:
		row.phase = "RETIRED"
	_prune_native(_state)
	_targets.clear()
	_root = null
	return true


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func native_nodes() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for row: Dictionary in _state.get("zones", []):
		if row.phase != "PENDING" and _nodes.has(row.id) and is_instance_valid(_nodes[row.id]):
			result.append(_nodes[row.id])
	return result


func pending_work() -> Dictionary:
	return {"zones": _state.get("zones", []).size()}


func native_spatial_nodes() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for row: Dictionary in _state.get("spatial", {}).get("rows", []):
		if row.phase in ["WARNING", "ACTIVE", "COLLAPSE"] and is_instance_valid(_spatial_nodes.get(row.id)):
			result.append(_spatial_nodes[row.id])
	return result


func configure_spatial_frame_authority(authority: RefCounted) -> bool:
	if authority == null or not authority.has_method("frame_transaction_is_active") or _frame_authority != null and _frame_authority.get_ref() != authority:
		return false
	_frame_authority = weakref(authority)
	return true


func apply_native_portal_transits(frame: int, targets: Dictionary, authority: RefCounted) -> bool:
	if _state.is_empty() or not _pending.is_empty() or _frame_authority == null or _frame_authority.get_ref() != authority or not authority.frame_transaction_is_active() or frame != int(_state.runtime_frame) + 1 or not _native_matches(_state):
		return false
	var keys: Array = targets.keys()
	keys.sort()
	var moved := {}
	for row: Dictionary in _state.spatial.rows:
		if row.kind != "portal" or row.phase != "ACTIVE" or frame >= int(row.expires_frame):
			continue
		for id: String in keys:
			var target: Variant = targets[id]
			if moved.has(id) or not is_instance_valid(target) or not target is CharacterBody2D or target.get_node("HealthComponent").dead or target.get_node("HealthComponent").frame_signal_transaction_runtime_frame() != frame:
				continue
			var player: bool = target is PlayerController
			if player and row.parameters.team_rule == "enemy_only" or frame < int(row.transit_claims.get(id, -12)) + 12:
				continue
			if not player:
				var affix: Variant = target.get("_affix_runtime")
				if affix != null and affix.displacement_multiplier() == 0.0 or target.has_method("is_time_stopped") and target.is_time_stopped():
					continue
			for endpoint: int in range(2):
				var entry := _vector(row.geometry[endpoint].origin)
				if target.global_position.distance_to(entry) > 16.0:
					continue
				var exit := _vector(row.geometry[1 - endpoint].origin)
				var destination := exit + entry.direction_to(exit) * 24.0
				var safe := _portal_inside_room(row, target, destination, targets)
				for other: Variant in targets.values():
					if is_instance_valid(other) and other is PlayerController and other != target and destination.distance_to(other.global_position) < 48.0:
						safe = false
				var arrival: Transform2D = target.global_transform
				arrival.origin = destination
				if safe and not target.test_move(arrival, Vector2.ZERO, null, 0.08, true):
					target.global_position = destination
					row.transit_claims[id] = frame
					moved[id] = true
				break
	return _spatial.valid_state(_state.spatial) and _sync_spatial_native(_state)


func _portal_inside_room(row: Dictionary, target: CharacterBody2D, destination: Vector2, targets: Dictionary) -> bool:
	var owner: Variant = targets.get(row.owner_id)
	if not is_instance_valid(owner) or not owner.has_method("launch_room_motion_snapshot"):
		return false
	var room: Dictionary = owner.launch_room_motion_snapshot()
	if room.is_empty():
		return false
	var bounds: Dictionary = room.bounds
	var shape := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or not shape.shape is CircleShape2D:
		return false
	return Rect2(float(bounds.x), float(bounds.y), float(bounds.width), float(bounds.height)).grow(-float(shape.shape.radius)).has_point(destination)


func receive_spatial_hit(id: String, info: RefCounted) -> float:
	if _state.is_empty() or not _pending.is_empty() or info == null or not _native_matches(_state):
		return 0.0
	var attacker: Node = info.attacker
	var run := StringName(str(_state.run_id))
	var target: Variant = _spatial_nodes.get(id)
	if not is_instance_valid(attacker) or not attacker is PlayerController or not is_instance_valid(target) or not attacker.authenticates_native_damage_run(info, target, run):
		return 0.0
	var frame: int = attacker.health.frame_signal_transaction_runtime_frame()
	var before := snapshot()
	var amount: float = _spatial.accept_damage(_state.spatial, id, {"run_id": str(run), "source_id": str(info.hostile_source_id), "generation": int(info.attack_generation), "hit_index": int(info.hit_index), "runtime_frame": int(_state.runtime_frame) if frame < 0 else frame, "amount": Calculator.critical_amount(info, float(info.amount))})
	if amount <= 0.0:
		return 0.0
	_apply_link_statuses(_state)
	if not _sync_spatial_native(_state) or not _apply_statuses(_state, _targets):
		_state = before
		_sync_spatial_native(before)
		_apply_statuses(before, _targets)
		return 0.0
	return amount


func _spatial_observations(actors: Dictionary, targets: Dictionary, frame: int) -> Dictionary:
	var result := {}
	for id: String in targets:
		var target: Node2D = targets[id]
		var dead: bool = target.get_node("HealthComponent").dead
		var kind := "player"
		if actors.has(id):
			kind = str(target.get("_launch_definition").actor_kind)
			var prepared: Dictionary = target.get("_prepared_launch_frame")
			dead = dead or bool((prepared.after.runtime if not prepared.is_empty() else target.launch_runtime_snapshot().runtime).terminal)
		result[id] = {"position": _point(_predicted_position(target, frame)), "dead": dead, "kind": kind}
	return result


func _spatial_safe(row: Dictionary, targets: Dictionary, frame: int) -> bool:
	if not _root_ready():
		return false
	if row.kind == "link":
		return true
	var owner: Variant = targets.get(row.owner_id)
	var room: Dictionary = owner.launch_room_motion_snapshot() if is_instance_valid(owner) and owner.has_method("launch_room_motion_snapshot") else {}
	var bounds: Dictionary = room.get("bounds", {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0})
	var rectangle := Rect2(float(bounds.x), float(bounds.y), float(bounds.width), float(bounds.height))
	for fact: Dictionary in row.geometry:
		var origin := _vector(fact.origin)
		var direction := _vector(fact.aim_direction)
		var destination := origin + direction * float(fact.length)
		if not rectangle.grow(-float(fact.radius)).has_point(origin) or not rectangle.grow(-float(fact.radius)).has_point(destination):
			return false
		if row.kind == "portal":
			for target: Variant in targets.values():
				if is_instance_valid(target) and target is PlayerController and origin.distance_to(_predicted_position(target, frame)) < 48.0:
					return false
			continue
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(float(fact.length), float(fact.radius) * 2.0)
		query.shape = shape
		query.transform = Transform2D(direction.angle(), origin + direction * float(fact.length) * 0.5)
		query.collision_mask = 1 | 2 | 4
		query.collide_with_bodies = true
		query.collide_with_areas = false
		for node: Node2D in native_spatial_nodes():
			var sibling: Dictionary = node.native_construct_snapshot()
			if sibling.owner_id == row.owner_id and sibling.generation == row.generation:
				query.exclude.append(node.get_rid())
		if not _root.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
		for target: Variant in targets.values():
			if is_instance_valid(target) and target is Node2D:
				var expanded := fact.duplicate(true)
				var body_shape := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
				if body_shape != null and body_shape.shape is CircleShape2D:
					expanded.radius += float(body_shape.shape.radius)
				if _contains(expanded, _predicted_position(target, frame)):
					return false
	return row.kind != "portal" or _vector(row.geometry[0].origin).distance_to(_vector(row.geometry[1].origin)) >= 96.0


func _apply_link_statuses(value: Dictionary) -> void:
	value.statuses = value.statuses.filter(func(status: Dictionary): return not str(status.id).begins_with("link_"))
	for row: Dictionary in value.spatial.rows:
		if row.kind != "link" or row.phase != "ACTIVE":
			continue
		for recipient: String in row.recipients:
			_upsert_status(value, {"id": "link_" + JSON.stringify([row.id, recipient]).sha256_text().substr(0, 40), "target_id": recipient, "expires_frame": int(row.expires_frame), "slow_multiplier": 1.0, "speed_multiplier": float(row.parameters.speed_multiplier), "attack_multiplier": float(row.parameters.attack_multiplier), "freeze_actions": false})


func _sync_spatial_native(value: Dictionary) -> bool:
	var live := {}
	for row: Dictionary in value.get("spatial", {}).get("rows", []):
		if row.phase not in ["WARNING", "ACTIVE", "COLLAPSE"]:
			continue
		if not _root_ready():
			return false
		if not is_instance_valid(_spatial_nodes.get(row.id)):
			var node := SpatialConstruct.new()
			node.configure(self, row.id)
			_root.add_child(node)
			_spatial_nodes[row.id] = node
		if not _spatial_nodes[row.id].present(row, int(value.runtime_frame)):
			return false
		live[row.id] = true
	for id: String in _spatial_nodes:
		if not live.has(id) and is_instance_valid(_spatial_nodes[id]):
			_spatial_nodes[id].deactivate()
	return true


func can_restore_transaction_snapshot(value: Dictionary) -> bool:
	value = normalize_transaction_snapshot(value)
	if _state.is_empty() or not Contract.exact_fields(value, STATE_FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 2 or value.run_id != _state.run_id or value.initial_frame != _state.initial_frame or not _frame(value.runtime_frame) or value.runtime_frame < value.initial_frame or not _claims(value.claims) or not value.spatial is Dictionary or not _spatial.valid_state(value.spatial) or value.spatial.run_id != value.run_id or value.spatial.initial_frame != value.initial_frame or value.spatial.runtime_frame != value.runtime_frame:
		return false
	if not value.zones is Array or value.zones.size() > MAX_RESERVATIONS or not value.statuses is Array or value.statuses.size() > 256 or not _valid_heals(value.heal_sources, value.heal_recipients) or not _valid_histories(value.histories, value.runtime_frame):
		return false
	var ids: Dictionary = {}
	var active := 0
	for row: Variant in value.zones:
		if not row is Dictionary or not _valid_zone(row, value.runtime_frame) or ids.has(row.id):
			return false
		ids[row.id] = true
		active += int(row.phase != "PENDING")
	if active > MAX_ZONES:
		return false
	ids.clear()
	for status: Variant in value.statuses:
		if not status is Dictionary or not Contract.exact_fields(status, STATUS_FIELDS) or not _stable(status.id) or not _stable(status.target_id) or ids.has(status.id) or not _frame(status.expires_frame) or status.expires_frame < value.runtime_frame or status.expires_frame > value.runtime_frame + 600 or not Contract.number_in_range(status.slow_multiplier, 0.4, 1.0) or not Contract.number_in_range(status.speed_multiplier, 1.0, 1.25) or not Contract.number_in_range(status.attack_multiplier, 0.8, 1.25) or typeof(status.freeze_actions) != TYPE_BOOL:
			return false
		ids[status.id] = true
	return true


func restore_transaction_snapshot(value: Dictionary) -> bool:
	value = normalize_transaction_snapshot(value)
	if not _pending.is_empty() or not can_restore_transaction_snapshot(value):
		return false
	var before := snapshot()
	_state = value.duplicate(true)
	if _sync_native(value, true) and _apply_statuses(value, _targets):
		return true
	_state = before
	_sync_native(before, true)
	_apply_statuses(before, _targets)
	return false


static func normalize_transaction_snapshot(value: Dictionary) -> Dictionary:
	if typeof(value.get("schema_version")) != TYPE_INT:
		return {}
	if value.schema_version == 2:
		return value.duplicate(true)
	if value.schema_version != 1 or not Contract.exact_fields(value, LEGACY_STATE_FIELDS):
		return {}
	var normalized := value.duplicate(true)
	normalized.schema_version = 2
	normalized["spatial"] = Spatial.initial_state(str(value.run_id), int(value.initial_frame))
	normalized.spatial.runtime_frame = value.runtime_frame
	return normalized


func prepare_effects(batches: Array, context: Dictionary, foreign_active_zones: int = 0, retired_children: Array[String] = [], foreign_constructs: int = 0) -> Dictionary:
	if _state.is_empty() or not _pending.is_empty() or foreign_active_zones < 0 or foreign_active_zones > MAX_ZONES or not Contract.exact_fields(context, ["run_id", "runtime_frame", "threat_registry", "actors", "targets"]) or context.run_id != _state.run_id or not _frame(context.runtime_frame) or context.runtime_frame != int(_state.runtime_frame) + 1 or not context.actors is Dictionary or not context.targets is Dictionary or batches.size() > 32 or not _native_matches(snapshot()):
		return _failure("context_or_projection")
	var before := snapshot()
	var next := snapshot()
	next.runtime_frame = context.runtime_frame
	next.zones = next.zones.filter(func(row: Dictionary): return row.phase == "PENDING" or row.expires_frame >= next.runtime_frame)
	for source: String in retired_children:
		_retire_owned_zones(next, source, context.actors)
	var zone_capacity := MAX_ZONES - foreign_active_zones
	if _active_zone_count(next) > zone_capacity:
		return _failure("shared_zone_budget")
	var targets: Dictionary = context.targets.duplicate()
	for id: String in context.actors:
		if not _native_actor(context.actors[id]) or str(context.actors[id].hostile_source_id) != id:
			return _failure("native_actor")
		targets[id] = context.actors[id]
	var observations := _observations(targets)
	if observations.size() != targets.size():
		return _failure("native_targets")
	_record_histories(next, context.actors)
	var spatial_observations := _spatial_observations(context.actors, targets, int(context.runtime_frame))
	var spatial_advanced: Dictionary = _spatial.advance(next.spatial, int(context.runtime_frame), spatial_observations, func(row: Dictionary): return _spatial_safe(row, targets, int(context.runtime_frame)), foreign_constructs)
	if not spatial_advanced.ok:
		return _failure("spatial_frame")
	for row: Dictionary in spatial_advanced.collapse_warnings:
		for index: int in range(row.geometry.size()):
			var collapse := {"hostile_source_id": row.owner_id, "attack_generation": row.generation, "runtime_frame": next.runtime_frame, "position": row.geometry[index].origin.duplicate(true), "parameters": {"warning_frames": 45, "damage": 20.0, "radius": 32.0}}
			if not _reserve_explosion(next, collapse, zone_capacity, "plane_ripper.portal_collapse.%s.%d" % [str(row.id), index], "void"):
				return _failure("portal_collapse")
	var health_requests: Array[Dictionary] = []
	var pending_heals: Dictionary = {}
	var damages: Array[Dictionary] = []
	var previous := ""
	for wrapper: Variant in batches:
		if not wrapper is Dictionary or not Contract.exact_fields(wrapper, ["hostile_source_id", "batch"]) or not _stable(wrapper.hostile_source_id) or wrapper.hostile_source_id <= previous or not context.actors.has(wrapper.hostile_source_id) or not wrapper.batch is Dictionary:
			return _failure("source_order")
		previous = wrapper.hostile_source_id
		var actor: Node2D = context.actors[wrapper.hostile_source_id]
		if actor.prepared_launch_frame_batch() != wrapper.batch or wrapper.batch.get("runtime_frame", -1) != context.runtime_frame or not wrapper.batch.get("effect_requests") is Array or not wrapper.batch.get("hit_facts") is Array or not wrapper.batch.get("mechanism_requests", []) is Array:
			return _failure("unsealed_batch")
		var definition: Dictionary = actor.get("_launch_definition")
		if definition.id == "forge_colossus" and actor.prepared_launch_arena_payloads_retired():
			next.zones = next.zones.filter(func(row: Dictionary): return row.source_id != wrapper.hostile_source_id)
		elif definition.id == "void_throne" and actor.prepared_launch_arena_payloads_retired():
			_retire_owned_zones(next, wrapper.hostile_source_id, context.actors)
		for request: Dictionary in wrapper.batch.effect_requests:
			if request.handler_id in ["melee", "charge", "projectile_volley", "blink"]:
				continue
			var action := _action(definition, str(request.action_id))
			if action.is_empty() or request.hostile_source_id != wrapper.hostile_source_id or request.run_id != context.run_id or request.runtime_frame != context.runtime_frame or request.parameters != action.parameters:
				return _failure("authored_effect")
			var claim := JSON.stringify([request.hostile_source_id, request.attack_generation, request.handler_id]).sha256_text()
			if next.claims.has(claim) or next.claims.size() >= MAX_CLAIMS:
				return _failure("effect_claim")
			next.claims.append(claim)
			match request.handler_id:
				"self_rewind":
					var rewinds: Array = wrapper.batch.get("mechanism_requests", []).filter(func(row: Dictionary): return row.get("kind", "") == "boss_self_rewind" and row.get("attack_generation", -1) == request.attack_generation)
					if definition.actor_kind != "boss" or rewinds.size() != 1:
						return _failure("self_rewind_pair")
				"heal":
					var healing := _prepare_heal(next, request, definition, context.actors, pending_heals)
					if not healing.ok:
						return healing
					if not healing.request.is_empty():
						health_requests.append(healing.request)
				"zone", "pull_zone":
					if not _reserve_zones(next, request, definition, action, zone_capacity, _zone_attack_multiplier(wrapper.batch, action), int(actor.get("_launch_identity").seed)):
						return _failure("zone_reservation")
				"wall":
					if definition.actor_kind != "boss":
						if not _spatial.reserve(next.spatial, request, definition.id, spatial_observations):
							return _failure("enemy_wall")
					elif not actor.has_method("prepared_launch_wall_effect_allowed") or not actor.prepared_launch_wall_effect_allowed(request):
						return _failure("unsealed_native_wall")
				"link", "portal":
					if not _spatial.reserve(next.spatial, request, definition.id, spatial_observations):
						return _failure("enemy_spatial")
				"summon":
					pass
				_: return _failure("unimplemented_semantic_handler")
		for hit: Dictionary in wrapper.batch.hit_facts:
			if definition.id == "forge_colossus" and hit.hit_index == 0 and hit.action_id in ["forge_hammer_slam", "forge_furnace_spray", "forge_eruption", "forge_enrage_ultimate"]:
				if not _reserve_forge_ground(next, hit, definition, zone_capacity):
					return _failure("forge_ground_reservation")
			if hit.handler_id != "blink":
				continue
			if not targets.has(hit.target_id) or hit.geometry.size() != 1:
				return _failure("blink_hit")
			if _contains(hit.geometry[0], _predicted_position(targets[hit.target_id], int(context.runtime_frame))):
				damages.append({"payload_id": _id([wrapper.hostile_source_id, hit.attack_generation, "blink"]), "hostile_source_id": wrapper.hostile_source_id, "attack_generation": int(hit.attack_generation), "hit_index": int(hit.hit_index), "target_id": hit.target_id, "runtime_frame": int(context.runtime_frame), "damage": float(hit.damage), "damage_type": hit.damage_type})
		for request: Dictionary in wrapper.batch.get("mechanism_requests", []):
			match request.get("kind", ""):
				"consume_actor", "death_pool", "boss_aftershock", "forest_flower", "void_p3_player_heal", "forge_burn_tick", "void_burn_tick", "void_shard_pickup": continue
				"void_tear_final":
					if not actor.has_method("prepared_launch_void_mechanism_allowed") or not actor.prepared_launch_void_mechanism_allowed(request) or not _reserve_explosion(next, request, zone_capacity, "void_throne.tear_final", "void"):
						return _failure("void_tear_final")
				"forest_seed_pool", "forest_cage_pulse", "forest_cage_collapse":
					if not actor.has_method("prepared_launch_forest_mechanism_allowed") or not actor.prepared_launch_forest_mechanism_allowed(request) or not _reserve_forest_effect(next, request, zone_capacity):
						return _failure("forest_native_mechanism")
				"restore_hp", "boss_self_rewind":
					if not Contract.number_in_range(request.get("amount"), 0.0, 1000000.0) or request.hostile_source_id != wrapper.hostile_source_id or request.runtime_frame != context.runtime_frame:
						return _failure("health_mechanism")
					var health: Node = actor.get_node("HealthComponent")
					var amount: float = maxf(0.0, float(request.amount) - float(health.current_hp)) if request.kind == "restore_hp" else minf(float(request.amount), float(health.max_hp) - float(health.current_hp))
					if amount > 0.0 and not health.dead:
						health_requests.append(_health_request(request, wrapper.hostile_source_id, amount, "restore_hp" if request.kind == "restore_hp" else "heal"))
				"warned_explosion":
					if not _reserve_explosion(next, request, zone_capacity):
						return _failure("warned_explosion")
				"boss_wall_collapse":
					if not actor.has_method("prepared_launch_wall_collapse_allowed") or not actor.prepared_launch_wall_collapse_allowed(request):
						return _failure("unsealed_wall_collapse")
					var collapse_claim := JSON.stringify([request.hostile_source_id, request.wall_id, "collapse"]).sha256_text()
					if next.claims.has(collapse_claim) or next.claims.size() >= MAX_CLAIMS or not _reserve_explosion(next, request, zone_capacity, "ruin_king.wall_collapse", "physical"):
						return _failure("wall_collapse_reservation")
					next.claims.append(collapse_claim)
				_: return _failure("unimplemented_semantic_mechanism")
		if not _prepare_terminal_effects(next, actor, definition, context.actors, zone_capacity, retired_children.has(wrapper.hostile_source_id)):
			return _failure("terminal_semantics")
	var terminal_ids: Array = context.actors.keys()
	terminal_ids.sort()
	for id: String in terminal_ids:
		var actor: Node2D = context.actors[id]
		if bool(actor.launch_runtime_snapshot().runtime.terminal) and not _prepare_terminal_effects(next, actor, actor.get("_launch_definition"), context.actors, zone_capacity, retired_children.has(id)):
			return _failure("finalized_terminal_semantics")
	_advance_zones(next, targets, context.actors, damages, zone_capacity)
	_apply_link_statuses(next)
	if not can_restore_transaction_snapshot(next) or (not next.zones.is_empty() and not _root_ready()):
		return _failure("candidate_state_or_root")
	var ticket := {"ticket_id": _next_ticket, "before": before, "after": next, "targets": targets, "observations": observations, "status_before": _status_checkpoints(targets)}
	_next_ticket += 1
	_pending = ticket.duplicate(true)
	_committed = false
	return {"ok": true, "ticket": ticket.duplicate(true), "damage_requests": damages, "health_requests": health_requests}


func can_commit(ticket: Dictionary) -> bool:
	return _matches(ticket) and not _committed and snapshot() == ticket.before and can_restore_transaction_snapshot(ticket.after) and _native_matches(ticket.before) and _observations_match(ticket.observations, ticket.after.runtime_frame)


func commit(ticket: Dictionary) -> bool:
	if not can_commit(ticket):
		return false
	_state = ticket.after.duplicate(true)
	_targets = ticket.targets.duplicate()
	if not _sync_native(_state) or not _apply_statuses(_state, ticket.targets):
		return false
	_committed = true
	return true


func rollback(ticket: Dictionary) -> bool:
	if not _matches(ticket):
		return false
	_state = ticket.before.duplicate(true)
	if not _sync_native(_state, true) or not _restore_status_checkpoints(ticket.status_before):
		return false
	_pending.clear()
	_committed = false
	return true


func can_publish(ticket: Dictionary) -> bool:
	return _matches(ticket) and _committed and snapshot() == ticket.after and _native_matches(ticket.after)


func publish(ticket: Dictionary) -> bool:
	if not can_publish(ticket):
		return false
	_prune_native(ticket.after)
	_pending.clear()
	_committed = false
	return true


func threat_facts_for_snapshot(value: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in value.get("zones", []):
		if row.phase == "PENDING":
			continue
		var fact: Dictionary = row.geometry.duplicate(true)
		fact.hostile_source_id = row.id
		fact.attack_generation = 1
		fact.active_from_frame = int(row.active_frame) - int(row.warning_frames)
		fact.active_through_frame = row.expires_frame
		var native := Actions.native_threat_fact(fact)
		if native.is_empty():
			return []
		result.append(native)
	return result


func work_records_for_snapshot(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in value.get("zones", []):
		result[row.id] = {"kind": "zone", "owner_source_id": row.source_id, "phase": "PENDING" if row.phase == "PENDING" else "ACTIVE"}
	for row: Dictionary in value.get("spatial", {}).get("rows", []):
		if row.phase != "RETIRED":
			result[row.id] = {"kind": "construct", "owner_source_id": row.owner_id, "phase": "PENDING" if row.phase == "PENDING" else "ACTIVE"}
	return result


static func active_zone_count_for_snapshot(value: Dictionary, frame: int) -> int:
	return value.get("zones", []).filter(func(row: Dictionary): return row.phase != "PENDING" and int(row.expires_frame) >= frame).size()


func _prepare_heal(next: Dictionary, request: Dictionary, definition: Dictionary, actors: Dictionary, pending_heals: Dictionary) -> Dictionary:
	var source: Node2D = actors[request.hostile_source_id]
	var source_health: Node = source.get_node("HealthComponent")
	var candidates: Array[String] = []
	for id: String in actors:
		var actor: Node2D = actors[id]
		var health: Node = actor.get_node("HealthComponent")
		var target_definition: Dictionary = actor.get("_launch_definition")
		var target_state: Dictionary = actor.launch_runtime_snapshot().runtime
		if id == request.hostile_source_id or health.dead or target_state.terminal or health.current_hp <= 0.0 or health.current_hp >= health.max_hp or target_definition.actor_kind == "boss" or target_definition.runtime_kind in ["rift_watcher", "rewind_priest"] or int(target_state.mechanism_state.get("recovery_remaining_frames", 0)) > 0 or int(target_state.mechanism_state.get("dormancy_remaining_frames", 0)) > 0:
			continue
		if _predicted_position(source, next.runtime_frame).distance_to(_predicted_position(actor, next.runtime_frame)) <= float(request.parameters.recipient_radius_px):
			candidates.append(id)
	candidates.sort_custom(func(a: String, b: String):
		var ha: Node = actors[a].get_node("HealthComponent")
		var hb: Node = actors[b].get_node("HealthComponent")
		var ra: float = float(ha.current_hp) / float(ha.max_hp)
		var rb: float = float(hb.current_hp) / float(hb.max_hp)
		return a < b if is_equal_approx(ra, rb) else ra < rb
	)
	var per_source: Dictionary = next.heal_sources.get(request.hostile_source_id, {})
	for id: String in candidates:
		var health: Node = actors[id].get_node("HealthComponent")
		var source_cap := float(source_health.max_hp) * float(definition.mechanisms.get("recipient_heal_fraction_cap", 0.4))
		var total_cap := float(health.max_hp) * float(definition.mechanisms.get("all_sources_recipient_heal_fraction_cap", 0.8))
		var amount := minf(float(request.parameters.heal_amount), minf(source_cap - float(per_source.get(id, 0.0)), total_cap - float(next.heal_recipients.get(id, 0.0))))
		amount = minf(amount, float(health.max_hp) - float(health.current_hp) - float(pending_heals.get(id, 0.0)))
		if definition.runtime_kind == "rewind_priest":
			var peak := float(health.current_hp)
			for row: Dictionary in next.histories.get(id, {}).get("frames", []):
				peak = maxf(peak, float(row.hp))
			amount = minf(amount, peak - float(health.current_hp) - float(pending_heals.get(id, 0.0)))
			if request.action_id.ends_with(".rewind_heal"):
				amount = minf(amount, float(health.max_hp) * float(definition.mechanisms.base_heal_recipient_fraction))
		if amount <= 0.0:
			continue
		per_source[id] = float(per_source.get(id, 0.0)) + amount
		pending_heals[id] = float(pending_heals.get(id, 0.0)) + amount
		next.heal_sources[request.hostile_source_id] = per_source
		next.heal_recipients[id] = float(next.heal_recipients.get(id, 0.0)) + amount
		if definition.runtime_kind == "rewind_priest" and request.action_id.ends_with(".time_reverse"):
			_upsert_status(next, {"id": _id([request.hostile_source_id, id, "priest_buff"]), "target_id": id, "expires_frame": int(next.runtime_frame) + int(definition.mechanisms.elite_attack_buff_frames), "slow_multiplier": 1.0, "speed_multiplier": 1.0, "attack_multiplier": float(definition.mechanisms.elite_attack_multiplier), "freeze_actions": false})
		return {"ok": true, "request": _health_request(request, id, amount, "heal")}
	return {"ok": true, "request": {}}


func _reserve_zones(next: Dictionary, request: Dictionary, definition: Dictionary, action: Dictionary, capacity: int, attack_multiplier: float, seed: int = 0) -> bool:
	if next.zones.size() + request.geometry.size() > MAX_RESERVATIONS:
		return false
	if definition.runtime_kind == "rift_weaver" and request.action_id.ends_with(".rift_fusion"):
		next.zones = next.zones.filter(func(row: Dictionary): return row.source_id != request.hostile_source_id)
	var cap: int = definition.mechanisms.get("pool_count_cap", definition.mechanisms.get("zone_count_cap", MAX_ZONES))
	var owned := 0
	for zone: Dictionary in next.zones:
		if zone.source_id == request.hostile_source_id and zone.phase != "PENDING":
			owned += 1
	for index: int in range(request.geometry.size()):
		var fact: Dictionary = request.geometry[index]
		var damaging: Dictionary = action.hit_schedule[mini(index, action.hit_schedule.size() - 1)] if not action.hit_schedule.is_empty() else {"damage": 0.0, "damage_type": "time"}
		var row := _zone(request, fact, index, float(damaging.damage), str(damaging.damage_type), 0, int(request.parameters.lifetime_frames), int(request.parameters.tick_interval_frames), float(request.parameters.slow_multiplier), int(request.parameters.get("slow_duration_frames", 0)))
		if request.action_id == "forge_furnace_devour":
			row["pull_parameters"] = {"speed": float(request.parameters.pull_px_per_second), "inner_radius": float(definition.mechanisms.devour_inner_radius_px), "inner_damage": float(definition.mechanisms.devour_inner_damage)}
		elif request.action_id == "voidking_vortex":
			row["pull_parameters"] = {"speed": float(request.parameters.pull_px_per_second), "inner_radius": float(definition.mechanisms.vortex_inner_radius_px), "inner_damage": float(definition.mechanisms.vortex_inner_damage)}
		row.initial_damage *= attack_multiplier
		if definition.actor_kind != "boss":
			row.damage = 0.0
			if request.action_id in ["bramble_mage.bramble_growth", "rift_weaver.rift_fusion", "chrono_storm_elemental.time_storm", "forge_titan.flame_breath"]:
				row.damage = float(damaging.damage)
			elif request.action_id == "forge_titan.ground_fissure":
				row.damage = float(definition.mechanisms.corpse_pool_damage) * (1.25 if definition.actor_kind == "elite" else 1.0)
			elif request.action_id == "chaos_amalgam.chaos_outburst":
				row.damage = float(definition.mechanisms.elite_burn_damage) * 1.25
				row.tick_damage_type = "fire"
		row.damage *= attack_multiplier
		row.owner_zone_cap = cap
		row.owner_immunity = definition.runtime_kind == "bramble_mage"
		row.ally_damage = definition.runtime_kind == "bramble_mage"
		row.enemy_only_freeze = request.action_id.ends_with(".time_stasis")
		if request.action_id == "chrono_storm_elemental.time_storm":
			row["storm_pattern"] = StormPattern.create(seed, str(request.hostile_source_id), int(request.attack_generation), index, definition.mechanisms)
		if _active_zone_count(next) >= capacity or owned >= cap:
			row.warning_frames = int(action.warning_frames)
			_make_pending(row)
		else:
			owned += 1
		next.zones.append(row)
	return true


func _reserve_forge_ground(next: Dictionary, hit: Dictionary, definition: Dictionary, capacity: int) -> bool:
	var mechanisms: Dictionary = definition.mechanisms
	var lifetime := int(mechanisms.slam_pool_lifetime_frames)
	match hit.action_id:
		"forge_furnace_spray": lifetime = int(mechanisms.spray_pool_lifetime_frames)
		"forge_eruption": lifetime = int(mechanisms.eruption_pool_lifetime_frames)
		"forge_enrage_ultimate": lifetime = int(mechanisms.enrage_pool_lifetime_frames)
	if next.zones.size() + hit.geometry.size() > MAX_RESERVATIONS:
		return false
	for index: int in range(hit.geometry.size()):
		var geometry: Dictionary = hit.geometry[index].duplicate(true)
		if hit.action_id == "forge_hammer_slam":
			geometry.radius = float(mechanisms.slam_pool_radius_px)
		var request := hit.duplicate(true)
		request.action_id = hit.action_id + ".ground_pool"
		var row := _zone(request, geometry, index, float(mechanisms.slam_pool_tick_damage), "fire", 0, lifetime, int(mechanisms.slam_pool_tick_frames), 1.0, 0)
		row.initial_damage = 0.0
		if _active_zone_count(next) >= capacity:
			row.warning_frames = 30
			_make_pending(row)
		next.zones.append(row)
	return true


func _reserve_explosion(next: Dictionary, request: Dictionary, capacity: int, action_id: String = "forge_titan.overheat_explosion", damage_type: String = "fire") -> bool:
	if next.zones.size() >= MAX_RESERVATIONS or not Contract.valid_point(request.get("position")) or not request.get("parameters") is Dictionary or not Contract.exact_fields(request.parameters, ["warning_frames", "damage", "radius"]) or not Contract.integer_in_range(request.parameters.warning_frames, 23, 600) or not Contract.number_in_range(request.parameters.damage, 0.0, 600.0) or not Contract.number_in_range(request.parameters.radius, 1.0, 320.0):
		return false
	var fact := {"hostile_source_id": request.hostile_source_id, "attack_generation": request.attack_generation, "shape": "circle", "origin": request.position.duplicate(true), "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": request.position.duplicate(true), "summon_slots": [], "radius": float(request.parameters.radius), "length": 0.0, "active_from_frame": next.runtime_frame, "active_through_frame": int(next.runtime_frame) + int(request.parameters.warning_frames)}
	var source := request.duplicate(true)
	source["action_id"] = action_id
	var row := _zone(source, fact, 0, float(request.parameters.damage), damage_type, int(request.parameters.warning_frames), 1, 1, 1.0, 0)
	if _active_zone_count(next) >= capacity:
		_make_pending(row)
	next.zones.append(row)
	return true


func _reserve_forest_effect(next: Dictionary, request: Dictionary, capacity: int) -> bool:
	var action_id := "forest_heart.%s.%s.%d" % [str(request.kind), str(request.get("construct_id", "pool")).sha256_text().substr(0, 16), int(request.get("hit_index", 0))]
	var claim := JSON.stringify([request.hostile_source_id, request.attack_generation, action_id]).sha256_text()
	if next.claims.has(claim) or next.claims.size() >= MAX_CLAIMS:
		return false
	if request.kind != "forest_seed_pool":
		if not _reserve_explosion(next, request, capacity, action_id, "void"):
			return false
	else:
		if next.zones.size() >= MAX_RESERVATIONS or not Contract.valid_point(request.get("position")) or not request.get("parameters") is Dictionary or not Contract.exact_fields(request.parameters, ["radius", "lifetime_frames", "tick_frames", "damage"]) or request.parameters.radius != 29.0 or request.parameters.lifetime_frames != 480 or request.parameters.tick_frames != 60 or not Contract.number_in_range(request.parameters.damage, 0.0, 600.0):
			return false
		var source := request.duplicate(true)
		source["action_id"] = action_id
		var fact := {"hostile_source_id": request.hostile_source_id, "attack_generation": request.attack_generation, "shape": "circle", "origin": request.position.duplicate(true), "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": request.position.duplicate(true), "summon_slots": [], "radius": 29.0, "length": 0.0, "active_from_frame": next.runtime_frame, "active_through_frame": int(next.runtime_frame) + 479}
		var row := _zone(source, fact, 0, float(request.parameters.damage), "void", 0, 480, 60, 1.0, 0)
		# A delayed pool must announce its new activation after capacity becomes free.
		if _active_zone_count(next) >= capacity:
			row.warning_frames = 40
			_make_pending(row)
		next.zones.append(row)
	next.claims.append(claim)
	return true


func _prepare_terminal_effects(next: Dictionary, actor: Node2D, definition: Dictionary, actors: Dictionary, capacity: int, owner_retired: bool = false) -> bool:
	var prepared: Dictionary = actor.get("_prepared_launch_frame")
	var source: String = str(actor.hostile_source_id)
	if prepared.is_empty():
		var current: Dictionary = actor.launch_runtime_snapshot()
		var receipt := "hostile_defeat:%s" % (str(next.run_id) + "|" + source).sha256_text().substr(0, 40)
		if not bool(current.runtime.terminal) or not bool(current.health.dead) or current.death_receipt != receipt:
			return true
	elif not bool(prepared.after.runtime.terminal):
		return true
	var claim := JSON.stringify([source, "terminal"]).sha256_text()
	if next.claims.has(claim):
		return true
	if next.claims.size() >= MAX_CLAIMS:
		return false
	next.claims.append(claim)
	if definition.actor_kind in ["boss", "summon"]:
		_retire_owned_zones(next, source, actors)
		if definition.actor_kind == "summon" and definition.id == "timeline_echo" and not owner_retired:
			return _reserve_terminal_zone(next, source, definition.id, "final_explosion", _predicted_position(actor, int(next.runtime_frame)), 32.0, int(definition.summon_contract.definition.final_explosion_warning_frames), 1, 20.0, "time", 1.0, 0, capacity)
		return true
	var mechanisms: Dictionary = definition.mechanisms
	if definition.runtime_kind == "rift_watcher":
		var recipients: Array = next.heal_sources.get(source, {}).keys()
		recipients.sort()
		for id: String in recipients:
			if actors.has(id) and not actors[id].get_node("HealthComponent").dead:
				_upsert_status(next, {"id": _id([source, id, "watcher_death"]), "target_id": id, "expires_frame": int(next.runtime_frame) + int(mechanisms.death_debuff_frames), "slow_multiplier": 1.0, "speed_multiplier": 1.0, "attack_multiplier": float(mechanisms.death_attack_multiplier), "freeze_actions": false})
		return true
	var position := _predicted_position(actor, int(next.runtime_frame))
	match definition.runtime_kind:
		"chrono_storm_elemental":
			return _reserve_terminal_zone(next, source, definition.id, "death_pulse", position, float(mechanisms.pattern_radius_px), int(mechanisms.death_warning_frames), 1, 0.0, "time", float(mechanisms.death_slow_multiplier), int(mechanisms.death_slow_frames), capacity)
		"forge_titan":
			if not _reserve_terminal_zone(next, source, definition.id, "corpse_explosion", position, float(mechanisms.explosion_radius_px), int(mechanisms.corpse_explosion_warning_frames), 1, float(mechanisms.explosion_damage), "fire", 1.0, 0, capacity):
				return false
			return _reserve_terminal_zone(next, source, definition.id, "corpse_pool", position, float(mechanisms.corpse_pool_radius_px), int(mechanisms.corpse_explosion_warning_frames) + 1, int(mechanisms.pool_lifetime_frames), float(mechanisms.corpse_pool_damage), "fire", 1.0, 0, capacity, int(mechanisms.corpse_pool_tick_frames))
		"void_spore":
			return _reserve_terminal_zone(next, source, definition.id, "residual", position, float(mechanisms.residual_radius_px), int(mechanisms.chain_warning_frames), int(mechanisms.residual_lifetime_frames), float(mechanisms.residual_tick_damage), "void", float(mechanisms.residual_slow_multiplier), 0, capacity, int(mechanisms.residual_tick_frames))
	return true


func _retire_owned_zones(next: Dictionary, source: String, actors: Dictionary) -> void:
	var ids := {}
	for row: Dictionary in next.zones:
		if row.source_id == source:
			for target: String in actors.keys() + ["player:1"]:
				ids[_id([row.id, target, "status"])] = true
	next.zones = next.zones.filter(func(row: Dictionary): return row.source_id != source)
	next.statuses = next.statuses.filter(func(row: Dictionary): return not ids.has(row.id))


func _reserve_terminal_zone(next: Dictionary, source: String, species: String, suffix: String, position: Vector2, radius: float, warning: int, lifetime: int, damage: float, damage_type: String, slow: float, slow_frames: int, capacity: int, tick_frames: int = 60) -> bool:
	if next.zones.size() >= MAX_RESERVATIONS:
		return false
	var point := {"x": position.x, "y": position.y}
	var request := {"hostile_source_id": source, "attack_generation": 1, "action_id": "%s.%s" % [species, suffix], "runtime_frame": int(next.runtime_frame)}
	var geometry := {"hostile_source_id": source, "attack_generation": 1, "shape": "circle", "origin": point, "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": point, "summon_slots": [], "radius": radius, "length": 0.0, "active_from_frame": int(next.runtime_frame), "active_through_frame": int(next.runtime_frame) + warning + lifetime - 1}
	var row := _zone(request, geometry, 0, damage, damage_type, warning, lifetime, tick_frames, slow, slow_frames)
	if _active_zone_count(next) >= capacity:
		_make_pending(row)
	next.zones.append(row)
	return true


func _advance_zones(next: Dictionary, targets: Dictionary, actors: Dictionary, damages: Array[Dictionary], capacity: int) -> void:
	next.statuses = next.statuses.filter(func(row: Dictionary): return row.expires_frame >= next.runtime_frame)
	var retained: Array = next.zones.filter(func(row: Dictionary): return row.phase == "PENDING" or int(next.runtime_frame) <= int(row.expires_frame))
	var active := 0
	var owners: Dictionary = {}
	for row: Dictionary in retained:
		if row.phase != "PENDING":
			active += 1
			owners[row.source_id] = int(owners.get(row.source_id, 0)) + 1
	# Existing visible hazards reserve capacity before any delayed decision is admitted.
	for row: Dictionary in retained:
		if row.phase == "PENDING" and active < capacity and int(owners.get(row.source_id, 0)) < int(row.owner_zone_cap):
			row.active_frame = int(next.runtime_frame) + int(row.warning_frames)
			row.expires_frame = int(row.active_frame) + int(row.lifetime_frames) - 1
			row.phase = "WARNING" if row.warning_frames > 0 else "ACTIVE"
			active += 1
			owners[row.source_id] = int(owners.get(row.source_id, 0)) + 1
		if row.phase != "PENDING":
			row.phase = "WARNING" if next.runtime_frame < row.active_frame else "ACTIVE"
			if row.phase == "ACTIVE":
				var tick: bool = (int(next.runtime_frame) - int(row.active_frame)) % int(row.tick_frames) == 0
				var movement: Dictionary = StormPattern.project(row.storm_pattern, int(row.active_frame), int(next.runtime_frame)) if row.has("storm_pattern") else {"slow_multiplier": float(row.slow_multiplier), "speed_multiplier": 1.0}
				var ids: Array = targets.keys()
				ids.sort()
				for id: String in ids:
					var target: Node2D = targets[id]
					var health: Node = target.get_node("HealthComponent")
					var actor_target: bool = actors.has(id)
					var ally_control: bool = row.enemy_only_freeze or row.action_id in ["chrono_storm_elemental.time_storm", "chrono_storm_elemental.death_pulse"]
					if health.dead or (id == row.source_id and row.owner_immunity) or (actor_target and not row.ally_damage and not ally_control) or not _contains(row.geometry, _predicted_position(target, next.runtime_frame)):
						continue
					if row.action_id == "forge_enrage_ultimate.ground_pool" and actors.has(row.source_id) and actors[row.source_id].forge_cooling_corridor_contains(_predicted_position(target, next.runtime_frame)):
						continue
					var initial: bool = int(next.runtime_frame) == int(row.active_frame)
					var damage: float = float(row.initial_damage) if initial else float(row.damage)
					if tick and damage > 0.0 and (not actor_target or row.ally_damage) and (not row.enemy_only_freeze or not actor_target):
						damages.append({"payload_id": row.id, "hostile_source_id": row.source_id, "attack_generation": 1, "hit_index": (int(next.runtime_frame) - int(row.active_frame)) / int(row.tick_frames), "target_id": id, "runtime_frame": int(next.runtime_frame), "damage": damage, "damage_type": row.damage_type if initial else row.tick_damage_type})
					if row.has("pull_parameters") and not actor_target and _vector(row.geometry.origin).distance_to(_predicted_position(target, next.runtime_frame)) <= float(row.pull_parameters.inner_radius):
						var inner_claim := JSON.stringify([row.id, id, "inner"]).sha256_text()
						if not next.claims.has(inner_claim) and next.claims.size() < MAX_CLAIMS:
							next.claims.append(inner_claim)
							damages.append({"payload_id": row.id + ":inner", "hostile_source_id": row.source_id, "attack_generation": 1, "hit_index": 63, "target_id": id, "runtime_frame": int(next.runtime_frame), "damage": float(row.pull_parameters.inner_damage), "damage_type": "void" if row.action_id == "voidking_vortex" else "fire"})
					if movement.slow_multiplier < 1.0 or movement.speed_multiplier > 1.0 or row.enemy_only_freeze:
						_upsert_status(next, {"id": _id([row.id, id, "status"]), "target_id": id, "expires_frame": int(next.runtime_frame) + (0 if row.has("storm_pattern") else maxi(0, int(row.slow_frames))), "slow_multiplier": float(movement.slow_multiplier), "speed_multiplier": float(movement.speed_multiplier), "attack_multiplier": 1.0, "freeze_actions": bool(row.enemy_only_freeze and actors.has(id))})
	next.zones = retained


func _zone(request: Dictionary, geometry: Dictionary, index: int, damage: float, damage_type: String, warning: int, lifetime: int, tick: int, slow: float, slow_frames: int) -> Dictionary:
	return {"id": _id([request.hostile_source_id, request.attack_generation, request.action_id, index]), "source_id": request.hostile_source_id, "action_id": request.action_id, "generation": int(request.attack_generation), "hit_index": index, "reserved_frame": int(request.runtime_frame), "active_frame": int(request.runtime_frame) + warning, "expires_frame": int(request.runtime_frame) + warning + lifetime - 1, "geometry": geometry.duplicate(true), "initial_damage": damage, "damage": damage, "damage_type": damage_type, "tick_damage_type": damage_type, "tick_frames": tick, "warning_frames": warning, "lifetime_frames": lifetime, "slow_multiplier": slow, "slow_frames": slow_frames, "enemy_only_freeze": false, "owner_immunity": false, "ally_damage": false, "owner_zone_cap": MAX_ZONES, "phase": "WARNING" if warning > 0 else "ACTIVE"}


func _apply_statuses(value: Dictionary, targets: Dictionary) -> bool:
	for id: String in targets:
		var target: Variant = targets[id]
		if not is_instance_valid(target) or not target is Node2D:
			continue
		var slow := 1.0
		var speed := 1.0
		var attack_buff := 1.0
		var attack_debuff := 1.0
		var freeze := false
		for status: Dictionary in value.statuses:
			if status.target_id == id:
				slow = minf(slow, float(status.slow_multiplier))
				speed = maxf(speed, float(status.speed_multiplier))
				attack_buff = maxf(attack_buff, float(status.attack_multiplier))
				attack_debuff = minf(attack_debuff, float(status.attack_multiplier))
				freeze = freeze or status.freeze_actions
		if target.has_method("apply_floor_rule_modifier"):
			if not value.has("zones") and target is PlayerController:
				for entry: Dictionary in target.floor_rule_effect_snapshot().modifiers.values():
					if str(entry.source_id).begins_with("void_auxiliary:") and not target.apply_floor_rule_modifier(StringName(entry.source_id), StringName(entry.modifier_id), &"remove", {}):
						return false
			if not target.apply_floor_rule_modifier(&"launch_semantic", &"movement", &"apply" if slow != 1.0 or speed != 1.0 else &"remove", {"movement_multiplier": maxf(0.4, slow * speed)} if slow != 1.0 or speed != 1.0 else {}):
				return false
			var pull := Vector2.ZERO
			for zone: Dictionary in value.get("zones", []):
				if zone.has("pull_parameters") and zone.phase == "ACTIVE" and _contains(zone.geometry, target.global_position):
					pull += target.global_position.direction_to(_vector(zone.geometry.origin)) * float(zone.pull_parameters.speed)
			pull = pull.limit_length(32.0)
			if not target.apply_floor_rule_modifier(&"launch_forge_pull", &"pull", &"remove" if pull.is_zero_approx() else &"apply", {} if pull.is_zero_approx() else {"pull_x": pull.normalized().x, "pull_y": pull.normalized().y, "pull_speed": pull.length()}):
				return false
			for owner: Variant in targets.values():
				if _native_actor(owner) and owner.get("_launch_definition").id == "forge_colossus" and not owner.sync_native_forge_modifier(target, id, not value.has("zones")):
					return false
				if _native_actor(owner) and owner.get("_launch_definition").id == "void_throne" and not owner.sync_native_void_modifier(target, id, not value.has("zones")):
					return false
		elif _native_actor(target):
			var runtime: RefCounted = target.get("_launch_runtime")
			for suffix: String in ["slow", "speed", "attack_buff", "attack_debuff", "freeze"]:
				runtime.clear_control_source("semantic_%s" % suffix)
			if not runtime.snapshot().terminal:
				if slow < 1.0 and not runtime.add_control_source("semantic_slow", "rift", 2, slow):
					return false
				if speed > 1.0 and not runtime.add_control_source("semantic_speed", "speed_buff", 2, speed):
					return false
				if attack_buff > 1.0 and not runtime.add_control_source("semantic_attack_buff", "attack_buff", 2, attack_buff):
					return false
				if attack_debuff < 1.0 and not runtime.add_control_source("semantic_attack_debuff", "attack_debuff", 2, attack_debuff):
					return false
				if freeze and not runtime.add_control_source("semantic_freeze", "stop", 2, 1.0):
					return false
	return true


func _status_checkpoints(targets: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for target: Variant in targets.values():
		if not is_instance_valid(target) or not target is Node2D:
			continue
		if target.has_method("floor_rule_effect_snapshot"):
			result.append({"target": target, "kind": "player", "snapshot": target.floor_rule_effect_snapshot()})
		elif _native_actor(target):
			result.append({"target": target, "kind": "actor", "snapshot": target._actor_state()})
	return result


func _restore_status_checkpoints(records: Array) -> bool:
	for record: Dictionary in records:
		if not is_instance_valid(record.target):
			return false
		if record.kind == "player":
			if not record.target.restore_floor_rule_effect_snapshot(record.snapshot):
				return false
		elif not record.target._restore_actor_state(record.snapshot):
			return false
	return true


func _sync_native(value: Dictionary, prune: bool = false) -> bool:
	if not _sync_spatial_native(value):
		return false
	var live: Dictionary = {}
	for row: Dictionary in value.zones:
		if row.phase == "PENDING":
			continue
		if not _root_ready():
			return false
		if not _nodes.has(row.id):
			var node := ZoneProjection.new()
			_root.add_child(node)
			_nodes[row.id] = node
		if not is_instance_valid(_nodes[row.id]) or not _nodes[row.id].project_record(row, value.runtime_frame):
			return false
		live[row.id] = true
	for id: String in _nodes:
		if not live.has(id) and is_instance_valid(_nodes[id]):
			_nodes[id].visible = false
	if prune:
		_prune_native(value)
	return true


func _prune_native(value: Dictionary) -> void:
	var spatial_live := {}
	for row: Dictionary in value.get("spatial", {}).get("rows", []):
		if row.phase in ["WARNING", "ACTIVE", "COLLAPSE"]:
			spatial_live[row.id] = true
	for id: String in _spatial_nodes.keys():
		if not spatial_live.has(id):
			var node: Node = _spatial_nodes[id]
			_spatial_nodes.erase(id)
			if is_instance_valid(node):
				node.deactivate()
				if node.get_parent() != null:
					node.get_parent().remove_child(node)
				node.queue_free()
	var live: Dictionary = {}
	for row: Dictionary in value.zones:
		if row.phase != "PENDING":
			live[row.id] = true
	for id: String in _nodes.keys():
		if not live.has(id):
			var node: Node2D = _nodes[id]
			_nodes.erase(id)
			if is_instance_valid(node):
				if node.get_parent() != null:
					node.get_parent().remove_child(node)
				node.queue_free()


func _native_matches(value: Dictionary) -> bool:
	if _root != null and not _root_ready():
		return false
	for row: Dictionary in value.get("zones", []):
		if row.phase != "PENDING" and (not _nodes.has(row.id) or not is_instance_valid(_nodes[row.id]) or not _nodes[row.id].matches_record(row)):
			return false
	for row: Dictionary in value.get("spatial", {}).get("rows", []):
		if row.phase in ["WARNING", "ACTIVE", "COLLAPSE"] and (not is_instance_valid(_spatial_nodes.get(row.id)) or _spatial_nodes[row.id].get_parent() != _root or not _spatial_nodes[row.id].matches_record(row, int(value.runtime_frame))):
			return false
	return true


func _observations(targets: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in targets:
		var target: Variant = targets[id]
		if not _stable(id) or not target is Node2D or not is_instance_valid(target) or not target.has_node("HealthComponent"):
			return {}
		var health: Node = target.get_node("HealthComponent")
		if not health.has_method("runtime_state_snapshot") or str(health.irreversible_run_id()) != _state.run_id:
			return {}
		result[id] = {"target": target, "position": target.global_position, "prepared_position": target.prepared_launch_frame_position() if _native_actor(target) else target.global_position, "health": health.runtime_state_snapshot()}
	return result


func _observations_match(records: Dictionary, frame: int) -> bool:
	for record: Dictionary in records.values():
		if not is_instance_valid(record.target) or record.target.is_queued_for_deletion() or record.target.get_node("HealthComponent").runtime_state_snapshot() != record.health:
			return false
		var expected: Vector2 = record.prepared_position if _native_actor(record.target) and int(record.target.launch_runtime_snapshot().runtime.runtime_frame) == frame else record.position
		if record.target.global_position != expected:
			return false
	return true


func _record_histories(next: Dictionary, actors: Dictionary) -> void:
	for history: Dictionary in next.histories.values():
		history.frames = history.frames.filter(func(row: Dictionary): return row.frame > int(next.runtime_frame) - 180)
	for id: String in actors:
		var health: Node = actors[id].get_node("HealthComponent")
		if health.dead:
			continue
		var history: Dictionary = next.histories.get(id, {"max_hp": float(health.max_hp), "frames": []})
		history.frames.append({"frame": int(next.runtime_frame), "hp": float(health.current_hp)})
		history.frames = history.frames.filter(func(row: Dictionary): return row.frame > int(next.runtime_frame) - 180)
		next.histories[id] = history


static func _vector(point: Dictionary) -> Vector2:
	return Vector2(float(point.x), float(point.y))


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _contains(fact: Dictionary, position: Vector2) -> bool:
	var native := Actions.native_threat_fact(fact)
	return not native.is_empty() and _geometry._distance_to_fact(position, native) <= 0.0


static func _predicted_position(target: Node2D, frame: int) -> Vector2:
	return target.prepared_launch_frame_position() if _native_actor(target) and not target.prepared_launch_frame_batch().is_empty() and int(target.prepared_launch_frame_batch().get("runtime_frame", -1)) == frame else target.global_position


static func _health_request(source: Dictionary, target_id: String, amount: float, kind: String) -> Dictionary:
	return {"kind": kind, "hostile_source_id": source.hostile_source_id, "attack_generation": int(source.attack_generation), "hit_index": int(source.get("hit_index", 0)), "target_id": target_id, "runtime_frame": int(source.runtime_frame), "amount": amount}


static func _upsert_status(next: Dictionary, value: Dictionary) -> void:
	for index: int in range(next.statuses.size()):
		if next.statuses[index].id == value.id:
			next.statuses[index] = value
			return
	next.statuses.append(value)


static func _valid_zone(row: Dictionary, frame: int) -> bool:
	var fields: Array = ZONE_FIELDS + (["storm_pattern"] if row.has("storm_pattern") else []) + (["pull_parameters"] if row.has("pull_parameters") else [])
	if row.has("pull_parameters") and (row.action_id not in ["forge_furnace_devour", "voidking_vortex"] or not row.pull_parameters is Dictionary or not Contract.exact_fields(row.pull_parameters, ["speed", "inner_radius", "inner_damage"]) or row.pull_parameters.speed != 32.0 or row.pull_parameters.inner_radius != (24.0 if row.action_id == "voidking_vortex" else 16.0) or row.pull_parameters.inner_damage != 40.0):
		return false
	if not Contract.exact_fields(row, fields) or row.has("storm_pattern") and (row.action_id != "chrono_storm_elemental.time_storm" or not StormPattern.valid(row.storm_pattern)) or not _stable(row.id) or not _stable(row.source_id) or not Contract.valid_id(row.action_id) or not Contract.integer_in_range(row.generation, 1, MAX_FRAME) or not Contract.integer_in_range(row.hit_index, 0, 63) or not _frame(row.reserved_frame) or row.reserved_frame > frame or row.phase not in ["PENDING", "WARNING", "ACTIVE"] or not row.geometry is Dictionary or Actions.native_threat_fact(row.geometry).is_empty():
		return false
	if not Contract.number_in_range(row.initial_damage, 0.0, 600.0) or not Contract.number_in_range(row.damage, 0.0, 600.0) or row.damage_type not in Contract.DAMAGE_TYPES or row.tick_damage_type not in Contract.DAMAGE_TYPES or not Contract.integer_in_range(row.tick_frames, 1, 600) or not Contract.integer_in_range(row.warning_frames, 0, 600) or not Contract.integer_in_range(row.lifetime_frames, 1, 1200) or not Contract.number_in_range(row.slow_multiplier, 0.4, 1.0) or not Contract.integer_in_range(row.slow_frames, 0, 600) or not Contract.integer_in_range(row.owner_zone_cap, 1, MAX_ZONES) or typeof(row.owner_immunity) != TYPE_BOOL or typeof(row.enemy_only_freeze) != TYPE_BOOL or typeof(row.ally_damage) != TYPE_BOOL:
		return false
	if row.phase == "PENDING":
		return row.active_frame == -1 and row.expires_frame == -1
	return _frame(row.active_frame) and _frame(row.expires_frame) and row.active_frame >= row.reserved_frame + row.warning_frames and row.expires_frame == row.active_frame + row.lifetime_frames - 1 and row.expires_frame >= frame and row.phase == ("WARNING" if frame < row.active_frame else "ACTIVE")


static func _valid_heals(sources: Variant, recipients: Variant) -> bool:
	if not sources is Dictionary or sources.size() > 32 or not recipients is Dictionary or recipients.size() > 32:
		return false
	for id: Variant in recipients:
		if not _stable(id) or not Contract.number_in_range(recipients[id], 0.0, 1000000.0):
			return false
	for id: Variant in sources:
		if not _stable(id) or not sources[id] is Dictionary or sources[id].size() > 32:
			return false
		for target: Variant in sources[id]:
			if not _stable(target) or not Contract.number_in_range(sources[id][target], 0.0, 1000000.0):
				return false
	return true


static func _valid_histories(histories: Variant, frame: int) -> bool:
	if not histories is Dictionary or histories.size() > 32:
		return false
	for id: Variant in histories:
		var history: Variant = histories[id]
		if not _stable(id) or not history is Dictionary or not Contract.exact_fields(history, ["max_hp", "frames"]) or not Contract.number_in_range(history.max_hp, 1.0, 1000000.0) or not history.frames is Array or history.frames.size() > 180:
			return false
		var previous := -1
		for row: Variant in history.frames:
			if not row is Dictionary or not Contract.exact_fields(row, ["frame", "hp"]) or not _frame(row.frame) or row.frame <= previous or row.frame <= frame - 180 or row.frame > frame or not Contract.number_in_range(row.hp, 0.0, history.max_hp):
				return false
			previous = row.frame
	return true


static func _claims(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_CLAIMS:
		return false
	var seen: Dictionary = {}
	for claim: Variant in value:
		if typeof(claim) != TYPE_STRING or claim.length() != 64 or not claim.is_valid_hex_number(false) or seen.has(claim):
			return false
		seen[claim] = true
	return true


static func _action(definition: Dictionary, action_id: String) -> Dictionary:
	for action: Dictionary in definition.get("actions", []):
		if action.id == action_id:
			return action
	return {}


static func _zone_attack_multiplier(batch: Dictionary, action: Dictionary) -> float:
	for fact: Dictionary in batch.hit_facts:
		if fact.handler_id == "zone" and fact.action_id == action.id:
			for hit: Dictionary in action.hit_schedule:
				if hit.hit_index == fact.hit_index and float(hit.damage) > 0.0:
					return float(fact.damage) / float(hit.damage)
	return 1.0


static func _active_zone_count(value: Dictionary) -> int:
	return value.zones.filter(func(row: Dictionary): return row.phase != "PENDING").size()


static func _make_pending(row: Dictionary) -> void:
	row.phase = "PENDING"
	row.active_frame = -1
	row.expires_frame = -1


static func _native_actor(value: Variant) -> bool:
	if not is_instance_valid(value) or not value is Node2D:
		return false
	var script: Script = value.get_script()
	while script != null:
		if script == ActorScript:
			return true
		script = script.get_base_script()
	return false


func _root_ready() -> bool:
	return is_instance_valid(_root) and _root.is_inside_tree() and not _root.is_queued_for_deletion() and _root.global_transform.is_equal_approx(Transform2D.IDENTITY)


func _matches(ticket: Dictionary) -> bool:
	return not _pending.is_empty() and ticket == _pending


static func _id(parts: Array) -> String:
	return "semantic_" + JSON.stringify(parts).sha256_text().substr(0, 32)


static func _stable(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 64 or value.strip_edges() != value:
		return false
	for index: int in range(value.length()):
		if value.unicode_at(index) < 33 or value.unicode_at(index) > 126:
			return false
	return true


static func _frame(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= MAX_FRAME


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"LAUNCH_SEMANTIC_INVALID", "context": {"field": field}}
