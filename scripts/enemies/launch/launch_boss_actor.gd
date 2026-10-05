class_name LaunchBossActor
extends "res://scripts/enemies/launch/launch_hostile_actor.gd"

const BossRuntime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const BossStatus := preload("res://scripts/enemies/launch/boss_elemental_status_runtime.gd")
const Construct := preload("res://scripts/enemies/launch/launch_boss_construct.gd")
const ForgeFixture := preload("res://scripts/enemies/launch/launch_forge_arena_fixture.gd")
const Wall := preload("res://scripts/enemies/launch/launch_boss_wall.gd")
const ForestRoot := preload("res://scripts/enemies/launch/launch_forest_root.gd")
const VoidConstruct := preload("res://scripts/enemies/launch/launch_void_arena_construct.gd")
const ForestAuxiliaryConstruct := preload("res://scripts/enemies/launch/launch_forest_auxiliary_construct.gd")
const RootTelegraph := preload("res://scripts/fx/combat_telegraph_2d.gd")
const Calculator := preload("res://scripts/combat/damage_calculator.gd")
var _exposure_replay_authority: RefCounted
var _arena_effects: WeakRef


func _create_launch_runtime() -> RefCounted:
	var runtime := BossRuntime.new()
	runtime.configure_arena_origin(_point(_native_arena_origin()), _point(global_position))
	return runtime


func _create_launch_status_runtime() -> RefCounted:
	return BossStatus.new()


func _native_body_claim_capacity() -> int:
	return BossRuntime.MAX_CLAIMS


func _ready() -> void:
	super._ready()
	add_to_group("bosses")
	var watch_shape := get_node_or_null("WatchHurtbox/CollisionShape2D") as CollisionShape2D
	if watch_shape != null and watch_shape.shape != null:
		watch_shape.shape = watch_shape.shape.duplicate()


func _native_geometry_matches_definition() -> bool:
	if not super._native_geometry_matches_definition():
		return false
	if _launch_definition.get("id", "") == "forge_colossus":
		var state := native_forge_arena_snapshot()
		var arena := get_node_or_null("ArenaConstructs")
		var fixtures := get_node_or_null("ForgeFixtures")
		if state.is_empty() or state.arena_origin != _point(_native_arena_origin()) or arena == null or fixtures == null or arena.get_child_count() != 4 or fixtures.get_child_count() != 8:
			return false
		for index: int in range(4):
			if not arena.get_child(index) is Construct or not arena.get_child(index).native_geometry_matches(state.covers[index], _native_arena_origin(), bool(state.terminal)):
				return false
		var rows: Array = state.vents + state.cooling_pools
		for index: int in range(8):
			if not fixtures.get_child(index) is ForgeFixture or not fixtures.get_child(index).native_geometry_matches(rows[index], _native_arena_origin(), bool(state.terminal)):
				return false
	if _launch_definition.get("id", "") == "void_throne":
		var holder := get_node_or_null("VoidArenaConstructs")
		var state := native_void_arena_snapshot()
		if holder == null or state.is_empty() or state.arena_origin != _point(_native_arena_origin()) or holder.get_child_count() != state.pillars.size() + state.cores.size():
			return false
		var rows: Array = state.pillars + state.cores
		for index: int in range(rows.size()):
			var construct := holder.get_child(index)
			if not construct is VoidConstruct or not construct.native_geometry_matches(rows[index], _native_arena_origin(), bool(state.terminal)):
				return false
	if _launch_definition.get("id", "") == "forest_heart":
		var arena := get_node_or_null("ArenaConstructs")
		var state := native_arena_snapshot()
		if arena == null or state.is_empty() or state.arena_origin != _point(_native_arena_origin()) or arena.get_child_count() != 6:
			return false
		for index: int in range(6):
			var root := arena.get_child(index)
			if not root is ForestRoot or not root.native_geometry_matches(state.roots[index], _native_arena_origin(), bool(state.terminal)):
				return false
		var auxiliary := get_node_or_null("AuxiliaryConstructs")
		var rows := _forest_construct_rows()
		if auxiliary == null or auxiliary.get_child_count() != rows.size():
			return false
		for index: int in range(rows.size()):
			if not auxiliary.get_child(index) is ForestAuxiliaryConstruct or not auxiliary.get_child(index).native_geometry_matches(rows[index].value, _native_arena_origin(), bool(state.terminal)):
				return false
	if _launch_definition.get("id", "") == "ruin_king":
		var arena := get_node_or_null("ArenaConstructs")
		var state: Dictionary = native_arena_snapshot()
		if arena == null or state.is_empty() or arena.get_child_count() != 4 + state.walls.size():
			return false
		for index: int in range(4):
			var cover := arena.get_child(index)
			if not cover is Construct or not cover.native_geometry_matches(state.covers[index], _native_arena_origin(), bool(state.terminal)):
				return false
		for index: int in range(state.walls.size()):
			var wall := arena.get_child(index + 4)
			if not wall is Wall or not wall.native_geometry_matches(state.walls[index], _native_arena_origin(), bool(state.terminal)):
				return false
		for claim: Dictionary in state.wall_claims:
			if _room_motion.is_empty() or claim.bounds != _room_motion.bounds:
				return false
	if _launch_definition.get("id", "") != "time_sovereign":
		return true
	var watch := get_node_or_null("WatchHurtbox") as Area2D
	var shape := get_node_or_null("WatchHurtbox/CollisionShape2D") as CollisionShape2D
	var primary := get_node("Hurtbox") as Area2D
	return watch != null and shape != null and shape.shape is CircleShape2D and not shape.disabled and watch.transform == Transform2D.IDENTITY and shape.transform == Transform2D.IDENTITY and shape.shape.radius == float(_launch_definition.collision_radius_px) and watch.collision_layer == (0 if _launch_runtime.snapshot().terminal else 4) and watch.collision_mask == 0 and primary.collision_layer == 0


func _restore_actor_state(value: Dictionary) -> bool:
	if not super._restore_actor_state(value):
		return false
	_refresh_control_visual()
	return true


func prepare_launch_frame(frame: int, observations: Dictionary) -> Dictionary:
	if _launch_definition.get("id", "") in ["time_sovereign", "ruin_king", "forest_heart", "void_throne", "forge_colossus"] and not _native_geometry_matches_definition():
		return _launch_failure("boss_native_geometry")
	var result := super.prepare_launch_frame(frame, observations)
	if result.ok and _launch_definition.get("id", "") == "forge_colossus":
		return _prepare_native_forge_frame(result, observations)
	if result.ok and _launch_definition.get("id", "") == "forest_heart":
		return _prepare_native_forest_frame(result, observations)
	if result.ok and _launch_definition.get("id", "") == "void_throne":
		if result.ticket.after.runtime.void_arena_state.phase_index == 2 and result.ticket.after.runtime.void_arena_state.player_heal.is_empty() and not result.ticket.after.runtime.terminal:
			result.ticket.batch.mechanism_requests.append({"kind": "void_p3_player_heal", "run_id": str(_launch_identity.run_id), "hostile_source_id": str(hostile_source_id), "runtime_frame": frame, "attack_generation": int(_launch_identity.next_generation_floor), "hit_index": 63, "target_id": str(observations.target_id), "fraction": 0.3})
		result.batch = result.ticket.batch.duplicate(true)
		_prepared_launch_frame = result.ticket.duplicate(true)
		return result
	if not result.ok or _launch_definition.get("id", "") != "ruin_king":
		return result
	for request: Dictionary in result.ticket.batch.effect_requests:
		if request.get("handler_id") != "wall":
			continue
		var preview := BossRuntime.new()
		preview.configure(_launch_definition, _launch_identity)
		if _room_motion.is_empty() or not preview.restore_snapshot(result.ticket.after.runtime):
			return _launch_failure("wall_admission")
		if not _wall_static_placement_valid(preview.snapshot().action):
			var cancelled: Dictionary = preview.cancel_action(&"wall_outside_safe_room_placement")
			if not cancelled.ok:
				return _launch_failure("wall_declined_admission")
			result.ticket.batch.effect_requests = []
			result.ticket.batch.phase = "IDLE"
			result.ticket.batch.retired_generations.append_array(cancelled.retired_generations)
		elif not preview.accept_arena_wall_request(request, _room_motion.bounds).ok:
			return _launch_failure("wall_admission")
		result.ticket.after.runtime = preview.snapshot()
	for request: Dictionary in result.ticket.batch.mechanism_requests:
		if request.get("kind", "") == "boss_aftershock":
			if _room_motion.is_empty():
				return _launch_failure("aftershock_room_bounds")
			request["bounds"] = _room_motion.bounds.duplicate(true)
		elif request.get("kind", "") == "boss_wall_collapse":
			if _room_motion.is_empty():
				return _launch_failure("wall_collapse_room_bounds")
			request.position = _point(_native_arena_origin() + _vector(request.position))
			request["bounds"] = _room_motion.bounds.duplicate(true)
	result.batch = result.ticket.batch.duplicate(true)
	_prepared_launch_frame = result.ticket.duplicate(true)
	var target: Variant = result.ticket.collision_target
	if target is Construct and target.get_parent() == get_node("ArenaConstructs") and result.ticket.after.runtime.action.action_id == "guardian_charge" and result.ticket.after.runtime.action.phase == "ACTIVE":
		var preview := BossRuntime.new()
		preview.configure(_launch_definition, _launch_identity)
		if not preview.restore_snapshot(result.ticket.after.runtime):
			return _launch_failure("charge_cover_checkpoint")
		var impact: Dictionary = preview.accept_arena_charge_impact(str(target.native_construct_snapshot().id))
		if not impact.ok:
			return _launch_failure("charge_cover_impact")
		result.ticket.after.runtime = preview.snapshot()
		result.ticket.batch.hit_facts = []
		result.ticket.batch.phase = "IDLE"
		result.ticket.batch.retired_generations.append_array(impact.retired_generations)
		result.batch = result.ticket.batch.duplicate(true)
		_prepared_launch_frame = result.ticket.duplicate(true)
	return result


func _native_action_activation_blocked(frame: int, observations: Dictionary) -> bool:
	if _launch_definition.get("id", "") == "forest_heart":
		var forest_action: Dictionary = _launch_runtime.snapshot().action
		if forest_action.phase != "WARNING":
			return false
		if forest_action.action_id == "matriarch_void_cage" and frame - int(forest_action.commit_frame) - int(forest_action.paused_frames) >= 70:
			return not _forest_cage_placement_valid(forest_action)
		if forest_action.action_id == "matriarch_enrage_dissolution" and frame - int(forest_action.commit_frame) - int(forest_action.paused_frames) >= 80:
			var inset := mini(2, int(_launch_runtime.forest_auxiliary_snapshot().erosion_steps) + 1) * 16.0
			return not _motion_bounds().grow(-inset - 14.0).has_point(_vector(observations.target_position))
		return false
	if _launch_definition.get("id", "") != "ruin_king":
		return false
	var action: Dictionary = _launch_runtime.snapshot().action
	if action.action_id != "guardian_wall" or action.phase != "WARNING" or frame - int(action.commit_frame) - int(action.paused_frames) < 55:
		return false
	if _room_motion.is_empty():
		return true
	if not _wall_static_placement_valid(action):
		return false
	if _arena_effects != null:
		var authority: RefCounted = _arena_effects.get_ref()
		var arena := native_arena_snapshot()
		var live := 0
		for row: Dictionary in arena.covers + arena.walls:
			live += int(not row.broken and not bool(row.get("expired", false)))
		if authority != null and live + int(authority.arena_debris_active_count()) + 2 > 8:
			return true
	for fact: Dictionary in action.committed_geometry:
		var origin := _vector(fact.origin)
		var direction := _vector(fact.aim_direction)
		var center := origin + direction * 32.0
		for subject: Dictionary in [{"position": observations.source_position, "radius": float(_launch_definition.collision_radius_px)}, {"position": observations.target_position, "radius": 14.0}]:
			var offset := (_vector(subject.position) - center).rotated(-direction.angle())
			var closest := Vector2(clampf(offset.x, -32.0, 32.0), clampf(offset.y, -6.0, 6.0))
			if offset.distance_to(closest) <= float(subject.radius) + 0.5:
				return true
	return false


func bind_native_construct_budget(authority: RefCounted) -> bool:
	if authority == null or not authority.has_method("arena_debris_active_count"):
		return false
	_arena_effects = weakref(authority)
	return true


func _wall_static_placement_valid(action: Dictionary) -> bool:
	if _room_motion.is_empty():
		return false
	var bounds := _motion_bounds()
	var retreat := _vector(action.committed_origin) - _vector(action.committed_aim) * (float(_launch_definition.collision_radius_px) + 7.0)
	if not _within_bounds(retreat, bounds, float(_launch_definition.collision_radius_px)):
		return false
	for fact: Dictionary in action.committed_geometry:
		var origin := _vector(fact.origin)
		var endpoint := origin + _vector(fact.aim_direction) * float(fact.length)
		if not _within_bounds(origin, bounds, 6.0) or not _within_bounds(endpoint, bounds, 6.0):
			return false
	return true


func configure_launch_room_motion(room: Node2D, template: Dictionary) -> Dictionary:
	var result := super.configure_launch_room_motion(room, template)
	if result.ok:
		if not _launch_runtime.configure_arena_origin(_point(_native_arena_origin()), _point(global_position)):
			return _launch_failure("forest_arena_origin")
		_refresh_native_arena()
	return result


func _refresh_control_visual() -> void:
	_refresh_native_arena()
	_refresh_native_void()
	var state: Dictionary = _launch_runtime.snapshot()
	_refresh_root_sweep_telegraph(state)
	var watch := get_node_or_null("WatchHurtbox") as Area2D
	if watch != null and not state.is_empty():
		watch.present(native_watch_snapshot())
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if state.is_empty() or sprite == null or not sprite.has_method("configure"):
		return
	if not sprite.configure(str(_launch_definition.id)):
		return
	var pose: StringName = &"idle"
	match state.action.phase:
		"WARNING": pose = &"cast"
		"ACTIVE": pose = &"attack"
		"RECOVERY": pose = &"idle"
	if state.terminal:
		pose = &"death"
	var facing := Vector2.RIGHT if state.action.committed_aim.is_empty() else _vector(state.action.committed_aim)
	sprite.present(pose, facing, float(state.runtime_frame) / 60.0, false, false)
	sprite.modulate = Color(0.55, 0.95, 1.0) if _launch_runtime.is_exposed() else Color.WHITE


func _refresh_root_sweep_telegraph(state: Dictionary) -> void:
	if _launch_definition.get("id", "") != "forest_heart":
		return
	var telegraph := get_node_or_null("RootSweepTelegraph") as Node2D
	if state.is_empty() or state.terminal or state.action.action_id != "matriarch_root_sweep" or state.action.phase not in ["WARNING", "ACTIVE"]:
		if telegraph != null:
			telegraph.clear_telegraph()
		return
	if telegraph == null:
		telegraph = RootTelegraph.new()
		telegraph.name = "RootSweepTelegraph"
		telegraph.z_index = 1
		add_child(telegraph)
	telegraph.set_accessibility_options(bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))
	telegraph.project_fact(Actions.native_threat_fact(state.action.committed_geometry[0]), str(state.action.action_id))


func native_arena_snapshot() -> Dictionary:
	return _launch_runtime.arena_snapshot()


func native_void_arena_snapshot() -> Dictionary:
	return _launch_runtime.void_arena_snapshot()


func _refresh_native_void() -> void:
	var state := native_void_arena_snapshot()
	if state.is_empty():
		return
	var holder := get_node_or_null("VoidArenaConstructs")
	if holder == null:
		holder = Node2D.new()
		holder.name = "VoidArenaConstructs"
		add_child(holder)
	var rows: Array = state.pillars + state.cores
	var replace := false
	for index: int in range(mini(rows.size(), holder.get_child_count())):
		if holder.get_child(index).native_construct_snapshot().get("id") != rows[index].id:
			replace = true
	while holder.get_child_count() > (0 if replace else rows.size()):
		var surplus := holder.get_child(holder.get_child_count() - 1)
		holder.remove_child(surplus)
		surplus.queue_free()
	for index: int in range(rows.size()):
		var construct: Node2D
		if index >= holder.get_child_count():
			construct = VoidConstruct.new()
			construct.name = "VoidConstruct%d" % index
			construct.configure(self, str(rows[index].id))
			holder.add_child(construct)
		else:
			construct = holder.get_child(index)
		construct.present(rows[index], _native_arena_origin(), bool(state.terminal))


func receive_native_void_construct_hit(id: String, damage_info: RefCounted) -> float:
	if damage_info == null or health == null or health.dead or not _prepared_launch_frame.is_empty() or native_void_arena_snapshot().is_empty() or not _native_geometry_matches_definition():
		return 0.0
	var attacker: Node = damage_info.attacker
	if not attacker is PlayerController or not attacker.authenticates_native_damage_run(damage_info, self, StringName(str(_launch_identity.run_id))):
		return 0.0
	var amount: float = Calculator.critical_amount(damage_info, float(damage_info.amount))
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	var frame: int = health.frame_signal_transaction_runtime_frame()
	if frame < 0:
		frame = _hostile_runtime_frame()
	var fact_id := (_damage_identity(damage_info) + ":" + id).sha256_text()
	var preview: RefCounted = _create_launch_runtime()
	if not preview.configure(_launch_definition, _launch_identity).ok or not preview.restore_snapshot(_launch_runtime.snapshot()):
		return 0.0
	var result: Dictionary = preview.accept_void_arena_damage({"fact_id": fact_id, "run_id": str(_launch_identity.run_id), "owner_source_id": str(hostile_source_id), "construct_id": id, "runtime_frame": frame, "amount": amount})
	if not result.ok:
		return 0.0
	var body_loss := minf(float(health.current_hp), float(result.body_damage))
	if body_loss > 0.0 and not preview.accept_damage_fact({"fact_id": (fact_id + ":body").sha256_text(), "runtime_frame": frame, "target_source_id": str(hostile_source_id), "amount": body_loss, "hp_after": float(health.current_hp) - body_loss}).ok:
		return 0.0
	if not _launch_runtime.restore_snapshot(preview.snapshot()):
		return 0.0
	if body_loss > 0.0:
		health.lose_health(body_loss, attacker)
	if _hostile_threat_registry != null:
		for generation: int in result.retired_generations:
			_hostile_threat_registry.retire(hostile_source_id, generation)
	_refresh_control_visual()
	return float(result.amount)


func prepared_launch_void_heal_allowed(request: Dictionary) -> bool:
	return not _prepared_launch_frame.is_empty() and _launch_definition.get("id") == "void_throne" and _prepared_launch_frame.batch.mechanism_requests.has(request) and request.get("kind") == "void_p3_player_heal" and not _prepared_launch_frame.after.runtime.terminal and _prepared_launch_frame.after.runtime.void_arena_state.phase_index == 2 and _prepared_launch_frame.after.runtime.void_arena_state.player_heal.is_empty()


func settle_native_void_heal(request: Dictionary, player: Node2D, amount: float) -> bool:
	return prepared_launch_void_heal_allowed(request) and _prepared_frame_committed and player is PlayerController and player.current_run_id() == StringName(str(_launch_identity.run_id)) and (not player.health.dead or amount == 0.0) and _launch_runtime.accept_void_player_heal(str(_launch_identity.run_id), str(request.target_id), int(request.runtime_frame), float(player.health.max_hp), amount, not player.health.dead)


func _native_arena_origin() -> Vector2:
	return Vector2(float(_room_motion.bounds.x), float(_room_motion.bounds.y)) if not _room_motion.is_empty() else Vector2.ZERO


func _refresh_native_arena() -> void:
	var state := native_arena_snapshot()
	if state.is_empty():
		return
	if _launch_definition.get("id", "") == "forge_colossus":
		_refresh_native_forge(state)
		return
	if _launch_definition.get("id", "") == "forest_heart":
		_refresh_native_forest(state)
		return
	var arena := get_node_or_null("ArenaConstructs")
	if arena == null:
		arena = Node2D.new()
		arena.name = "ArenaConstructs"
		add_child(arena)
		for cover: Dictionary in state.covers:
			var body := Construct.new()
			body.name = "Cover%d" % int(cover.slot)
			body.configure(self, str(cover.id))
			arena.add_child(body)
	var replace_walls := false
	for index: int in range(mini(state.walls.size(), arena.get_child_count() - 4)):
		if arena.get_child(index + 4).native_construct_snapshot().get("id") != state.walls[index].id:
			replace_walls = true
	while arena.get_child_count() > (4 if replace_walls else 4 + state.walls.size()):
		var surplus := arena.get_child(arena.get_child_count() - 1)
		arena.remove_child(surplus)
		surplus.queue_free()
	for index: int in range(4):
		arena.get_child(index).present(state.covers[index], _native_arena_origin(), bool(state.terminal))
	for index: int in range(state.walls.size()):
		var wall: Node2D
		if arena.get_child_count() <= index + 4:
			wall = Wall.new()
			wall.name = "Wall%d" % index
			wall.configure(self, str(state.walls[index].id))
			arena.add_child(wall)
		else:
			wall = arena.get_child(index + 4)
		wall.present(state.walls[index], _native_arena_origin(), bool(state.terminal))


func native_forge_arena_snapshot() -> Dictionary:
	return _launch_runtime.forge_arena_snapshot() if _launch_runtime != null else {}


func _refresh_native_forge(state: Dictionary) -> void:
	var arena := get_node_or_null("ArenaConstructs")
	if arena == null:
		arena = Node2D.new()
		arena.name = "ArenaConstructs"
		add_child(arena)
		for row: Dictionary in state.covers:
			var body := Construct.new()
			body.name = "Anvil%d" % int(row.slot)
			body.configure(self, str(row.id))
			arena.add_child(body)
	for index: int in range(4):
		arena.get_child(index).present(state.covers[index], _native_arena_origin(), bool(state.terminal))
	var holder := get_node_or_null("ForgeFixtures")
	var rows: Array = state.vents + state.cooling_pools
	if holder == null:
		holder = Node2D.new()
		holder.name = "ForgeFixtures"
		add_child(holder)
		for index: int in range(8):
			var fixture := ForgeFixture.new()
			fixture.name = "Vent%d" % index if index < 4 else "Cooling%d" % (index - 4)
			fixture.configure(self, "vent" if index < 4 else "cooling")
			holder.add_child(fixture)
	for index: int in range(8):
		holder.get_child(index).present(rows[index], _native_arena_origin(), bool(state.terminal))


func _prepare_native_forge_frame(result: Dictionary, observations: Dictionary) -> Dictionary:
	var preview := BossRuntime.new()
	preview.configure_arena_origin(_point(_native_arena_origin()), _point(global_position))
	if not preview.configure(_launch_definition, _launch_identity).ok or not preview.restore_snapshot(result.ticket.after.runtime):
		return _launch_failure("forge_arena_candidate")
	if not preview.snapshot().terminal:
		if not preview.observe_forge_target(str(observations.target_id), observations.target_position).ok:
			return _launch_failure("forge_cooling_candidate")
		for request: Dictionary in preview.forge_burn_damage_requests(int(result.ticket.runtime_frame)):
			request["kind"] = "forge_burn_tick"
			result.ticket.batch.mechanism_requests.append(request)
	result.ticket.after.runtime = preview.snapshot()
	result.batch = result.ticket.batch.duplicate(true)
	_prepared_launch_frame = result.ticket.duplicate(true)
	return result


func prepared_launch_forge_mechanism_allowed(request: Dictionary) -> bool:
	return _launch_definition.get("id", "") == "forge_colossus" and not _prepared_launch_frame.is_empty() and _prepared_launch_frame.batch.mechanism_requests.has(request) and request.get("kind") == "forge_burn_tick"


func sync_native_forge_modifier(target: Node2D, target_id: String, clear: bool = false) -> bool:
	var state := native_forge_arena_snapshot()
	if state.is_empty() or not target is PlayerController or target.current_run_id() != StringName(str(_launch_identity.run_id)) or target.get_world_2d() != get_world_2d():
		return false
	var burning: bool = not clear and not state.terminal and state.burns.any(func(row: Dictionary): return row.target_id == target_id)
	return target.apply_floor_rule_modifier(StringName("forge_burn:" + str(hostile_source_id)), &"burn", &"apply" if burning else &"remove", {"movement_multiplier": 1.0} if burning else {})


func settle_native_forge_slam(hit: Dictionary, target: Node2D, loss: float) -> bool:
	if _launch_definition.get("id", "") != "forge_colossus" or not _prepared_frame_committed or _prepared_launch_frame.is_empty() or not _prepared_launch_frame.batch.hit_facts.has(hit) or hit.action_id != "forge_hammer_slam" or not target is PlayerController:
		return false
	if loss > 0.0 and not _launch_runtime.accept_forge_burn_fact({"run_id": str(_launch_identity.run_id), "owner_source_id": str(hostile_source_id), "target_id": str(hit.target_id), "attack_generation": int(hit.attack_generation), "runtime_frame": int(hit.runtime_frame)}).ok:
		return false
	return sync_native_forge_modifier(target, str(hit.target_id))


func _refresh_native_forest(state: Dictionary) -> void:
	var arena := get_node_or_null("ArenaConstructs")
	if arena == null:
		arena = Node2D.new()
		arena.name = "ArenaConstructs"
		add_child(arena)
		for row: Dictionary in state.roots:
			var root := ForestRoot.new()
			root.name = "Root%d" % int(row.slot)
			root.configure(self, str(row.id))
			arena.add_child(root)
	for index: int in range(6):
		arena.get_child(index).present(state.roots[index], _native_arena_origin(), bool(state.terminal))
	_refresh_native_forest_auxiliary(bool(state.terminal))


func _forest_construct_rows() -> Array[Dictionary]:
	var state: Dictionary = _launch_runtime.forest_auxiliary_snapshot()
	var rows: Array[Dictionary] = []
	if state.is_empty():
		return rows
	for sac: Dictionary in state.sacs:
		var value := sac.duplicate(true)
		value["marked"] = state.seeds.any(func(seed: Dictionary): return seed.sac_id == value.id and seed.burst_frame == -1 and seed.cancelled_frame == -1)
		rows.append({"kind": "sac", "value": value})
	for flower: Dictionary in state.flowers:
		rows.append({"kind": "flower", "value": flower.duplicate(true)})
	for wall: Dictionary in state.cages:
		rows.append({"kind": "wall", "value": wall.duplicate(true)})
	var inset := float(state.erosion_steps) * 16.0
	if inset > 0.0:
		for slot: int in range(4):
			var horizontal := slot < 2
			var position := Vector2(320, inset * 0.5 if slot == 0 else 360.0 - inset * 0.5) if horizontal else Vector2(inset * 0.5 if slot == 2 else 640.0 - inset * 0.5, 180)
			rows.append({"kind": "erosion", "value": {"id": "forest_erosion:%d" % slot, "position": _point(position), "length": 640.0 if horizontal else 360.0, "thickness": inset, "rotation": 0.0 if horizontal else PI * 0.5}})
	return rows


func _refresh_native_forest_auxiliary(terminal: bool) -> void:
	var holder := get_node_or_null("AuxiliaryConstructs")
	if holder == null:
		holder = Node2D.new()
		holder.name = "AuxiliaryConstructs"
		add_child(holder)
	var rows := _forest_construct_rows()
	var replace := false
	for index: int in range(mini(holder.get_child_count(), rows.size())):
		if holder.get_child(index).native_construct_snapshot().get("id") != rows[index].value.id:
			replace = true
	while holder.get_child_count() > (0 if replace else rows.size()):
		var retired := holder.get_child(holder.get_child_count() - 1)
		holder.remove_child(retired)
		retired.queue_free()
	for index: int in range(rows.size()):
		var construct: Node2D
		if index >= holder.get_child_count():
			construct = ForestAuxiliaryConstruct.new()
			construct.name = "ForestAuxiliary%d" % index
			construct.configure(self, str(rows[index].kind))
			holder.add_child(construct)
		else:
			construct = holder.get_child(index)
		construct.present(rows[index].value, _native_arena_origin(), terminal)


func _prepare_native_forest_frame(result: Dictionary, observations: Dictionary) -> Dictionary:
	var preview := BossRuntime.new()
	preview.configure_arena_origin(_point(_native_arena_origin()), _point(global_position))
	if not preview.configure(_launch_definition, _launch_identity).ok or not preview.restore_snapshot(result.ticket.after.runtime):
		return _launch_failure("forest_auxiliary_candidate")
	for request: Dictionary in result.ticket.batch.effect_requests:
		if request.get("action_id") == "matriarch_void_cage" and not preview.accept_forest_cage(request):
			return _launch_failure("forest_cage_admission")
	for request: Dictionary in preview.forest_cage_requests(int(result.ticket.runtime_frame)):
		if not result.ticket.batch.mechanism_requests.has(request):
			result.ticket.batch.mechanism_requests.append(request)
	for flower: Dictionary in preview.forest_auxiliary_snapshot().flowers:
		if not flower.used and (_native_arena_origin() + _vector(flower.position)).distance_to(_vector(observations.target_position)) <= float(flower.radius_px) + 14.0:
			result.ticket.batch.mechanism_requests.append({"kind": "forest_flower", "run_id": str(_launch_identity.run_id), "hostile_source_id": str(hostile_source_id), "runtime_frame": int(result.ticket.runtime_frame), "attack_generation": int(result.ticket.runtime_frame), "hit_index": int(flower.slot), "construct_id": str(flower.id), "target_id": str(observations.target_id), "amount": 20.0})
	for request: Dictionary in result.ticket.batch.mechanism_requests:
		if request.kind in ["forest_seed_pool", "forest_cage_pulse", "forest_cage_collapse"]:
			if _room_motion.is_empty():
				return _launch_failure("forest_effect_bounds")
			request["bounds"] = _room_motion.bounds.duplicate(true)
	result.ticket.after.runtime = preview.snapshot()
	result.batch = result.ticket.batch.duplicate(true)
	_prepared_launch_frame = result.ticket.duplicate(true)
	return result


func can_commit_launch_frame(ticket: Dictionary) -> bool:
	return super.can_commit_launch_frame(ticket) and _forest_cage_ticket_safe(ticket, false)


func can_publish_launch_frame(ticket: Dictionary) -> bool:
	return super.can_publish_launch_frame(ticket) and _forest_cage_ticket_safe(ticket, true)


func _forest_cage_ticket_safe(ticket: Dictionary, committed: bool) -> bool:
	if _launch_definition.get("id") != "forest_heart" or not ticket.batch.effect_requests.any(func(request: Dictionary): return request.action_id == "matriarch_void_cage"):
		return true
	return _forest_cage_placement_valid(ticket.after.runtime.action, committed)


func _forest_cage_placement_valid(action: Dictionary, committed: bool = false) -> bool:
	if _room_motion.is_empty():
		return false
	var owned: Array[RID] = []
	if committed:
		for construct: StaticBody2D in get_node("AuxiliaryConstructs").get_children():
			if construct.native_construct_snapshot().get("attack_generation", -1) == action.geometry_generations[0]:
				owned.append(construct.get_rid())
	for fact: Dictionary in action.committed_geometry:
		var start := _vector(fact.origin)
		var direction := _vector(fact.aim_direction)
		var end := start + direction * float(fact.length)
		if not _within_bounds(start, _motion_bounds(), 6.0) or not _within_bounds(end, _motion_bounds(), 6.0):
			return false
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(float(fact.length), 10.0)
		query.shape = shape
		query.transform = Transform2D(direction.angle(), (start + end) * 0.5)
		query.collision_mask = 7
		query.exclude = owned
		query.collide_with_areas = false
		if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


func receive_native_forest_auxiliary_hit(id: String, info: RefCounted) -> float:
	if info == null or _launch_definition.get("id", "") != "forest_heart" or not _native_geometry_matches_definition() or not is_instance_valid(info.attacker) or not info.attacker is PlayerController or not info.attacker.authenticates_native_damage_run(info, self, StringName(str(_launch_identity.run_id))):
		return 0.0
	var amount: float = Calculator.critical_amount(info, float(info.amount))
	var frame: int = health.frame_signal_transaction_runtime_frame()
	var accepted: Dictionary = _launch_runtime.accept_forest_auxiliary_damage({"fact_id": (_damage_identity(info) + ":" + id).sha256_text(), "run_id": str(_launch_identity.run_id), "owner_source_id": str(hostile_source_id), "construct_id": id, "runtime_frame": _hostile_runtime_frame() if frame < 0 else frame, "amount": amount})
	if not accepted.ok:
		return 0.0
	if _hostile_threat_registry != null:
		for generation: int in accepted.get("retired_generations", []):
			_hostile_threat_registry.retire(hostile_source_id, generation)
	_refresh_control_visual()
	return float(accepted.amount)


func prepared_launch_forest_mechanism_allowed(request: Dictionary) -> bool:
	return _launch_definition.get("id", "") == "forest_heart" and not _prepared_launch_frame.is_empty() and _prepared_launch_frame.batch.mechanism_requests.has(request) and request.runtime_frame == _prepared_launch_frame.runtime_frame and not _prepared_launch_frame.after.runtime.terminal and (request.kind == "forest_flower" or not _room_motion.is_empty() and request.get("bounds") == _room_motion.bounds)


func settle_native_forest_flower(request: Dictionary, actual_heal: float) -> bool:
	if not prepared_launch_forest_mechanism_allowed(request) or request.kind != "forest_flower" or not _prepared_frame_committed:
		return false
	var accepted: bool = _launch_runtime.accept_forest_flower(str(request.construct_id), str(request.target_id), int(request.runtime_frame), actual_heal)
	if accepted:
		_refresh_control_visual()
	return accepted


func native_forest_drain_allowance(generation: int, actual_loss: float) -> float:
	return _launch_runtime.forest_drain_allowance(generation, actual_loss)


func settle_native_forest_drain(id: String, generation: int, index: int, frame: int, loss: float, healed: float) -> bool:
	if not _prepared_frame_committed or _prepared_launch_frame.is_empty() or frame != int(_prepared_launch_frame.runtime_frame) or not _prepared_launch_frame.batch.hit_facts.any(func(hit: Dictionary): return hit.action_id == "matriarch_drain_roots" and hit.attack_generation == generation and hit.hit_index == index):
		return false
	return _launch_runtime.accept_forest_drain(id, generation, index, frame, loss, healed)


func prepared_launch_wall_effect_allowed(request: Dictionary) -> bool:
	if _prepared_launch_frame.is_empty() or request.get("handler_id") != "wall" or not _prepared_launch_frame.batch.effect_requests.has(request) or _room_motion.is_empty():
		return false
	if _launch_definition.get("id", "") == "forest_heart":
		return request.action_id == "matriarch_void_cage" and _prepared_launch_frame.after.runtime.forest_auxiliary.cages.any(func(row: Dictionary): return row.attack_generation == request.attack_generation and row.spawn_frame == request.runtime_frame)
	var state: Dictionary = _prepared_launch_frame.after.runtime.arena_state
	for claim: Dictionary in state.wall_claims:
		if claim.attack_generation == request.attack_generation and claim.runtime_frame == request.runtime_frame and claim.geometry == request.geometry and claim.bounds == _room_motion.bounds:
			return true
	return false


func prepared_launch_wall_collapse_allowed(request: Dictionary) -> bool:
	if _prepared_launch_frame.is_empty() or _room_motion.is_empty() or request.get("kind") != "boss_wall_collapse" or not _prepared_launch_frame.batch.mechanism_requests.has(request) or request.get("bounds") != _room_motion.bounds or not request.get("parameters") is Dictionary or not Contract.exact_fields(request.parameters, ["warning_frames", "damage", "radius"]) or request.parameters.warning_frames != 40 or request.parameters.radius != 24.0 or not Contract.number_in_range(request.parameters.damage, 6.4, 12.0):
		return false
	var state: Dictionary = _prepared_launch_frame.after.runtime.arena_state
	if state.terminal:
		return false
	for wall: Dictionary in state.walls:
		if wall.id == request.get("wall_id"):
			return not wall.broken and wall.expired and request.runtime_frame == int(wall.spawn_frame) + 600 and request.attack_generation == int(wall.attack_generation) + int(wall.slot) and request.position == _point(_native_arena_origin() + _vector(wall.position))
	return false


func receive_native_construct_hit(id: String, damage_info: RefCounted) -> float:
	if damage_info == null or native_arena_snapshot().is_empty() or not _native_geometry_matches_definition():
		return 0.0
	var attacker: Node = damage_info.attacker
	var run := StringName(str(_launch_identity.run_id))
	if not is_instance_valid(attacker) or not attacker is PlayerController or not attacker.authenticates_native_damage_run(damage_info, self, run):
		return 0.0
	var amount: float = Calculator.critical_amount(damage_info, float(damage_info.amount))
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	var frame: int = health.frame_signal_transaction_runtime_frame()
	var result: Dictionary = _launch_runtime.accept_arena_damage_fact({"fact_id": (_damage_identity(damage_info) + ":" + id).sha256_text(), "run_id": str(run), "owner_source_id": str(hostile_source_id), "construct_id": id, "runtime_frame": _hostile_runtime_frame() if frame < 0 else frame, "amount": amount})
	if not result.ok:
		return 0.0
	if _hostile_threat_registry != null:
		for generation: int in result.get("retired_generations", []):
			_hostile_threat_registry.retire(hostile_source_id, generation)
	_refresh_control_visual()
	return float(result.amount)


func _can_restore_actor_state(value: Dictionary) -> bool:
	if not super._can_restore_actor_state(value):
		return false
	if _launch_definition.get("id", "") == "void_throne":
		return value.runtime.void_arena_state.arena_origin == _point(_native_arena_origin())
	if _launch_definition.get("id", "") == "forge_colossus":
		return value.runtime.forge_arena_state.arena_origin == _point(_native_arena_origin())
	return _launch_definition.get("id", "") != "forest_heart" or value.runtime.arena_state.arena_origin == _point(_native_arena_origin())


func prepared_launch_hit_blocked_by_cover(hit: Dictionary, target: Node2D) -> bool:
	if _launch_definition.get("id", "") == "forge_colossus" and not _prepared_launch_frame.is_empty() and _prepared_launch_frame.batch.hit_facts.has(hit) and hit.action_id == "forge_enrage_ultimate":
		return forge_cooling_corridor_contains(target.global_position)
	if _launch_definition.get("id", "") != "ruin_king" or _prepared_launch_frame.is_empty() or not _prepared_launch_frame.batch.hit_facts.has(hit) or hit.action_id != "guardian_rift_beam" or not _native_geometry_matches_definition() or not is_instance_valid(target):
		return false
	var state: Dictionary = _prepared_launch_frame.after.runtime.arena_state
	var origin := _vector(hit.geometry[0].origin)
	var endpoint := target.global_position
	var length := origin.distance_to(endpoint)
	if length <= 0.0:
		return false
	var direction := origin.direction_to(endpoint)
	for cover: Dictionary in state.covers:
		if cover.broken or state.terminal:
			continue
		var center := _native_arena_origin() + _vector(cover.position)
		var along := (center - origin).dot(direction)
		if along > 0.0 and along < length and Geometry2D.get_closest_point_to_segment(center, origin, endpoint).distance_to(center) <= float(cover.radius_px):
			return true
	return false


func forge_cooling_corridor_contains(position: Vector2) -> bool:
	var state := native_forge_arena_snapshot()
	if state.is_empty() or state.terminal:
		return false
	var point := position - _native_arena_origin()
	if absf(point.x - 320.0) <= 24.0 and point.y >= 48.0 and point.y <= 312.0:
		return true
	for pool: Dictionary in state.cooling_pools:
		if point.distance_to(_vector(pool.position)) <= float(pool.radius_px):
			return true
	return false


func prepared_launch_arena_payload_allowed(request: Dictionary) -> bool:
	return not _prepared_launch_frame.is_empty() and _launch_definition.get("id", "") == "ruin_king" and request.get("kind", "") == "boss_aftershock" and _prepared_launch_frame.batch.mechanism_requests.has(request) and not _prepared_launch_frame.after.runtime.terminal and not _room_motion.is_empty() and request.get("bounds") == _room_motion.bounds


func prepared_launch_payload_parameters() -> Dictionary:
	if not _prepared_launch_frame.is_empty() and _launch_definition.get("id", "") == "forge_colossus":
		return {"lava_pool_radius_px": _launch_definition.mechanisms.lava_pool_radius_px, "lava_pool_lifetime_frames": _launch_definition.mechanisms.lava_pool_lifetime_frames, "lava_pool_tick_damage": _launch_definition.mechanisms.lava_pool_tick_damage, "lava_pool_tick_frames": _launch_definition.mechanisms.lava_pool_tick_frames}
	if _prepared_launch_frame.is_empty() or _launch_definition.get("id", "") != "ruin_king":
		return {}
	return {"debris_hp": _launch_definition.mechanisms.debris_hp, "debris_lifetime_frames": _launch_definition.mechanisms.debris_lifetime_frames, "debris_count_cap": _launch_definition.mechanisms.debris_count_cap}


func prepared_launch_arena_payloads_retired() -> bool:
	if _prepared_launch_frame.is_empty():
		return false
	var state: Dictionary = _prepared_launch_frame.after.runtime
	return bool(state.terminal) or state.mechanism_state.phase_index > 0 and int(state.mechanism_state.phase_transition_until_frame) >= int(_prepared_launch_frame.runtime_frame)


func normalize_native_cold_snapshot(value: Dictionary) -> Dictionary:
	if not value.get("actor") is Dictionary or not value.actor.get("runtime") is Dictionary:
		return {}
	var normalized: Dictionary = _launch_runtime.normalize_native_snapshot(value.actor.runtime)
	if normalized.is_empty() or not _launch_runtime.can_restore_native_snapshot(normalized):
		return {}
	var result := value.duplicate(true)
	result.actor.runtime = normalized
	return result


func _cold_actor_state(value: Dictionary, source_resolver: Callable) -> Dictionary:
	var state := super._cold_actor_state(value, source_resolver)
	if state.is_empty():
		return {}
	state.runtime = _launch_runtime.normalize_native_snapshot(state.runtime)
	return state if not state.runtime.is_empty() and _launch_runtime.can_restore_native_snapshot(state.runtime) else {}


func native_watch_snapshot() -> Dictionary:
	var state: Dictionary = _launch_runtime.snapshot()
	if state.is_empty() or _launch_definition.get("id", "") != "time_sovereign":
		return {}
	var rewind: Dictionary = state.mechanism_state.rewind
	var active: bool = state.action.phase == "WARNING" and state.action.action_id == "traitor_self_rewind" and not rewind.is_empty() and not rewind.consumed
	var broken: bool = not rewind.is_empty() and rewind.cancelled and float(rewind.weakpoint_damage) >= float(_launch_definition.mechanisms.rewind_interrupt_damage)
	return {"owner_source_id": str(hostile_source_id), "runtime_frame": int(state.runtime_frame), "hittable": not state.terminal and health != null and not health.dead, "cast_generation": int(rewind.attack_generation) if active else 0, "maximum_hp": float(_launch_definition.mechanisms.rewind_interrupt_damage), "current_hp": 0.0 if broken else float(_launch_definition.mechanisms.rewind_interrupt_damage) - (float(rewind.weakpoint_damage) if active else 0.0)}


func receive_native_watch_hit(damage_info: RefCounted) -> float:
	if damage_info == null or _launch_definition.get("id", "") != "time_sovereign" or not native_watch_snapshot().hittable:
		return 0.0
	var run := StringName(str(_launch_identity.run_id))
	if damage_info.run_id != run:
		var attacker: Node = damage_info.attacker
		if damage_info.run_id != &"runtime" or not is_instance_valid(attacker) or not attacker is PlayerController or attacker.current_run_id() != run:
			return 0.0
	var state: Dictionary = _launch_runtime.snapshot()
	var id := _native_body_fact_id(damage_info)
	if state.mechanism_state.damage_claims.has(id):
		return 0.0
	return health.take_damage(damage_info)


func apply_weapon_hit_control(damage_info: RefCounted, final_amount: float) -> bool:
	var body: Dictionary = health.hostile_body_application(damage_info, final_amount)
	var before: Dictionary = body.before if not body.is_empty() else _launch_runtime.snapshot()
	var accepted := super.apply_weapon_hit_control(damage_info, final_amount)
	if accepted and _launch_definition.get("id", "") in ["forest_heart", "void_throne"]:
		_refresh_control_visual()
	if damage_info == null or before.is_empty() or _launch_definition.get("id", "") != "time_sovereign":
		return accepted
	var after: Dictionary = _launch_runtime.snapshot()
	var id := _native_body_fact_id(damage_info)
	var rewind: Dictionary = before.mechanism_state.rewind
	# Group-targeted spells and physical watch collisions settle one body identity.
	if not before.mechanism_state.damage_claims.has(id) and after.mechanism_state.damage_claims.has(id) and before.action.phase == "WARNING" and before.action.action_id == "traitor_self_rewind" and not rewind.is_empty() and not rewind.consumed:
		var frame: int = health.frame_signal_transaction_runtime_frame()
		var result: Dictionary = _launch_runtime.accept_weakpoint_damage_fact({"fact_id": id, "runtime_frame": _hostile_runtime_frame() if frame < 0 else frame, "attack_generation": int(rewind.attack_generation), "amount": final_amount})
		if result.ok and _hostile_threat_registry != null:
			for generation: int in result.retired_generations:
				_hostile_threat_registry.retire(hostile_source_id, generation)
	_refresh_control_visual()
	return accepted


static func _damage_identity(damage_info: RefCounted) -> String:
	var info: Dictionary = damage_info.snapshot()
	return JSON.stringify([info.run_id, info.target_id, info.hostile_source_id, info.attack_generation, info.hit_index]).sha256_text()


func _on_died(killer: Variant) -> void:
	super._on_died(killer)
	if not _death_receipt.is_empty():
		remove_from_group("bosses")


func apply_weapon_control_conversion(source_id: StringName, recovery_frames: int, exposure_frames: int, poise_damage: float) -> bool:
	var accepted: bool = _launch_runtime.apply_weapon_control_conversion(str(source_id), recovery_frames, exposure_frames, poise_damage)
	if accepted:
		_refresh_control_visual()
	return accepted


func extend_character_boss_exposure(stop_generation: int, frames: int) -> bool:
	var accepted: bool = _launch_runtime.extend_character_boss_exposure(stop_generation, frames)
	if accepted:
		_refresh_control_visual()
	return accepted


func character_boss_exposure_identity() -> Dictionary:
	var state: Dictionary = _launch_runtime.snapshot()
	if state.is_empty():
		return {}
	var identity: Dictionary = {}
	for field: String in ["run_id", "room_id", "encounter_id", "encounter_spawn_id", "encounter_enemy_id"]:
		var value := str(get_meta(field, "")).strip_edges()
		if value.is_empty() or value.length() > 128:
			return {}
		identity[field] = value
	identity.hostile_source_id = str(hostile_source_id)
	identity.hostile_next_generation_floor = int(state.action.next_generation_floor)
	identity.committed_attack_generation = int(state.action.geometry_generations[0]) if not state.action.geometry_generations.is_empty() else 0
	return identity


func character_boss_exposure_snapshot() -> Dictionary:
	return _launch_runtime.character_boss_exposure_snapshot(character_boss_exposure_identity())


func can_restore_character_boss_exposure_snapshot(value: Dictionary) -> bool:
	return _launch_runtime.can_restore_character_boss_exposure(value, character_boss_exposure_identity())


func restore_character_boss_exposure_snapshot(value: Dictionary) -> bool:
	var restored: bool = _launch_runtime.restore_character_boss_exposure(value, character_boss_exposure_identity())
	if restored:
		_refresh_control_visual()
	return restored


func configure_character_boss_exposure_replay_authority(authority: RefCounted) -> bool:
	if authority == null or _exposure_replay_authority != null and _exposure_replay_authority != authority:
		return false
	_exposure_replay_authority = authority
	return true


func can_restore_character_boss_exposure_replay_snapshot(value: Dictionary, authority: RefCounted) -> bool:
	return authority != null and authority == _exposure_replay_authority and _launch_runtime.can_restore_character_boss_exposure(value, character_boss_exposure_identity(), true)


func restore_character_boss_exposure_replay_snapshot(value: Dictionary, authority: RefCounted) -> bool:
	if not can_restore_character_boss_exposure_replay_snapshot(value, authority):
		return false
	var restored: bool = _launch_runtime.restore_character_boss_exposure(value, character_boss_exposure_identity(), true)
	if restored:
		_refresh_control_visual()
	return restored


func get_boss_ui_snapshot() -> Dictionary:
	var state: Dictionary = _launch_runtime.snapshot()
	if state.is_empty() or health == null:
		return {}
	var action: Dictionary = _launch_runtime._action_definition(str(state.action.action_id))
	var remaining := 0
	if not action.is_empty():
		var elapsed := int(state.runtime_frame) - int(state.action.commit_frame) - int(state.action.paused_frames)
		remaining = int(action.warning_frames) - elapsed if state.action.phase == "WARNING" else int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames) - elapsed
		remaining = maxi(0, remaining) + int(state.mechanism_state.delay_remaining_frames)
	var label := "NONE" if action.is_empty() else str(action.handler_id).to_upper()
	return {"action": label, "phase": "WINDUP" if state.action.phase == "WARNING" else str(state.action.phase), "remaining": float(remaining) / 60.0, "boss_phase": int(state.mechanism_state.phase_index) + 1, "exposed": _launch_runtime.is_exposed(), "name": tr("BOSS_%s_NAME" % str(_launch_definition.id).to_upper()), "phase_total": _launch_definition.phases.size(), "current_hp": float(health.current_hp), "maximum_hp": float(health.max_hp), "enraged": bool(state.mechanism_state.enraged)}


func apply_elemental_status(effect_id: StringName, source_id: StringName, generation: int, duration_frames: int, magnitude: float = 1.0, tick_interval_frames: int = 30, attack_speed_multiplier: float = -1.0, damage_source: Node = null, damage_attacker: Node = null) -> bool:
	if effect_id in [&"freeze", &"blind"] and not has_elemental_status(effect_id, source_id, generation):
		if not elemental_status_runtime._is_valid_application(effect_id, source_id, generation, duration_frames, magnitude, tick_interval_frames, attack_speed_multiplier):
			return false
		var material := "%s|%s|%d" % [str(effect_id), str(source_id), generation]
		if not apply_weapon_control_conversion(StringName("staff_conversion:" + material.sha256_text().substr(0, 40)), 12 if effect_id == &"freeze" else 8, 0, 0.0):
			return false
	return super.apply_elemental_status(effect_id, source_id, generation, duration_frames, magnitude, tick_interval_frames, attack_speed_multiplier, damage_source, damage_attacker)


func _resolve_weapon_hit_control(effect: Dictionary, damage_info: RefCounted, final_amount: float) -> bool:
	if str(effect.get("kind", "")) != "launch":
		return super._resolve_weapon_hit_control(effect, damage_info, final_amount)
	if damage_info == null or str(effect.get("conversion_id", "")) != "gauntlets_poised_launch" or not damage_info.tags.has("weapon:gauntlets") or typeof(effect.get("airborne")) != TYPE_BOOL or effect.airborne or str(effect.get("active_attack_policy", "")) != "preserve_committed" or typeof(effect.get("interrupt_active_attack")) != TYPE_BOOL or effect.interrupt_active_attack:
		return false
	if not effect.get("allowed_states") is Array or not Contract.number_in_range(effect.get("poise_damage"), 0.000001, 1000000.0) or not Contract.number_in_range(effect.get("boss_poise_multiplier"), 1.40, 1.40) or not Contract.number_in_range(effect.get("displacement_pixels", 0.0), 0.0, 1000000.0):
		return false
	var phase: String = _launch_runtime.snapshot().action.phase
	var conversion_state := "EXPOSED" if _launch_runtime.is_exposed() and phase != "WARNING" else "WINDUP" if phase == "WARNING" else phase
	if conversion_state not in effect.allowed_states:
		return false
	var source := str(effect.get("source_id", "gauntlets_poised_launch:%d:%d" % [int(damage_info.action_token), int(damage_info.source_generation)]))
	return apply_weapon_control_conversion(StringName(source), 0, 0, float(effect.poise_damage) * 1.40)
