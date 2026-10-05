extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Coordinator := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Atlas := preload("res://scripts/presentation/actor_atlas_projection.gd")
const Telegraph := preload("res://scripts/fx/combat_telegraph_2d.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Hitbox := preload("res://scripts/combat/hitbox.gd")
var suite: RefCounted


class CountingBoss extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return super.snapshot()


class ColdQueries extends RefCounted:
	var runtime: RefCounted

	func snapshot() -> Dictionary:
		return runtime.snapshot()

	func arena_snapshot() -> Dictionary:
		return runtime.arena_snapshot()

	func void_arena_snapshot() -> Dictionary:
		return runtime.void_arena_snapshot()

	func void_auxiliary_snapshot() -> Dictionary:
		return runtime.void_auxiliary_snapshot()

	func forest_auxiliary_snapshot() -> Dictionary:
		return runtime.forest_auxiliary_snapshot()

	func is_exposed() -> bool:
		return runtime.is_exposed()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for row: Dictionary in Content.read_catalog("bosses.json"):
		await _check_boss(row)
	suite.finish(get_tree())


func _check_boss(row: Dictionary) -> void:
	var parser := Definition.new()
	suite.assert_true(parser.configure(row).ok, "visual observation uses authored Boss " + row.id)
	var definition := parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	identity.hostile_source_id = "visual-" + row.id
	var actor := (load("res://data/content_packs/base/assets/bosses/launch/boss_%s.tscn" % row.id) as PackedScene).instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(320, 144)
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "actual Boss configures complete native visual authority")
	var initial: Dictionary = actor.launch_runtime_snapshot().runtime
	var runtime := CountingBoss.new()
	var origin: Vector2 = actor.call("_native_arena_origin")
	suite.assert_true(runtime.configure_arena_origin(_point(origin), _point(actor.global_position)) and runtime.configure(definition, identity).ok and runtime.restore_snapshot(initial), "counted real Boss restores its exact actual boundary")
	actor.set("_launch_runtime", runtime)
	var registry := Registry.new()
	actor.set("_hostile_threat_registry", registry)
	var reference := Atlas.new()
	add_child(reference)
	suite.assert_true(reference.configure(row.id), "original production atlas provides the reference projection")
	var root_reference := Telegraph.new()
	add_child(root_reference)
	root_reference.set_process(false)
	_assert_batch(actor, runtime, reference, root_reference, definition, registry, "configured " + row.id)
	var action: Dictionary = definition.actions[1 if row.id == "forest_heart" else 0]
	await _check_action(actor, runtime, reference, root_reference, definition, registry, action)
	if row.id == "forest_heart":
		suite.assert_true(runtime.restore_snapshot(initial), "Forest restores actual pre-sweep authority")
		await _check_action(actor, runtime, reference, root_reference, definition, registry, Content.action("matriarch_root_sweep"))
	if row.id == "time_sovereign":
		suite.assert_true(runtime.restore_snapshot(initial), "Time Sovereign restores before authentic history")
		for frame: int in range(1, 9):
			actor.global_position += Vector2.RIGHT
			suite.assert_true(runtime.advance_frame(frame, _context(actor, frame), false).ok, "native frames record distinct historical landing positions")
		await _check_action(actor, runtime, reference, root_reference, definition, registry, Content.action("traitor_self_rewind"))
	suite.assert_true(runtime.cancel(&"visual_observation").ok, "actual terminal mutation retires presentation")
	_assert_batch(actor, runtime, reference, root_reference, definition, registry, "terminal " + row.id)
	suite.assert_true(runtime.restore_snapshot(initial), "complete historical authority restores after terminal")
	_assert_batch(actor, runtime, reference, root_reference, definition, registry, "rollback " + row.id)
	suite.assert_true(runtime.request_action(str(action.id), _context(actor, runtime.native_runtime_frame())).ok, "actual warning exercises query-less fallback")
	var cold := ColdQueries.new()
	cold.runtime = runtime
	actor.set("_launch_runtime", cold)
	_assert_batch(actor, runtime, reference, root_reference, definition, registry, "fallback " + row.id, true)
	actor.set("_launch_runtime", runtime)
	await _check_deferred(actor, runtime, reference, root_reference, definition, registry)
	var changed_identity := identity.duplicate(true)
	changed_identity.hostile_source_id += "-reconfigured"
	suite.assert_true(actor.configure_launch_definition(definition, changed_identity).ok, "actual owner reconfiguration replaces current presentation authority")
	var changed: Dictionary = actor.launch_runtime_snapshot().runtime
	runtime = CountingBoss.new()
	suite.assert_true(runtime.configure_arena_origin(_point(origin), _point(actor.global_position)) and runtime.configure(definition, changed_identity).ok and runtime.restore_snapshot(changed), "counted authority follows the newly configured actual owner")
	actor.set("_launch_runtime", runtime)
	_assert_batch(actor, runtime, reference, root_reference, definition, registry, "reconfigured " + row.id)
	actor.queue_free()
	reference.queue_free()
	root_reference.queue_free()
	await get_tree().process_frame


func _check_action(actor: Node2D, runtime: RefCounted, reference: Sprite2D, root_reference: Node2D, definition: Dictionary, registry: RefCounted, action: Dictionary) -> void:
	registry.clear()
	var started: Dictionary = runtime.request_action(str(action.id), _context(actor, runtime.native_runtime_frame()))
	suite.assert_true(started.ok, "actual authored warning starts " + action.id)
	if not started.ok:
		return
	if action.id == "traitor_self_rewind":
		suite.assert_true(runtime.snapshot().mechanism_state.rewind.landing != _point(actor.global_position), "authentic self-rewind projects a distinct historical landing")
	for fact: Dictionary in started.get("threat_facts", []):
		suite.assert_true(registry.register_fact(Coordinator.native_threat_fact(fact)), "actual committed fact joins the threat authority")
	_assert_batch(actor, runtime, reference, root_reference, definition, registry, "warning " + action.id)
	var first: int = runtime.native_runtime_frame()
	var duration: int = int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames)
	for elapsed: int in range(1, duration + 1):
		var frame := first + elapsed
		suite.assert_true(runtime.advance_frame(frame, _context(actor, frame), false).ok, "actual accepted visual clock advances " + action.id)
		if elapsed in [int(action.warning_frames), int(action.warning_frames) + int(action.active_frames), duration]:
			_assert_batch(actor, runtime, reference, root_reference, definition, registry, "frame %d %s" % [frame, action.id])
	suite.assert_true(runtime.cancel_action(&"visual_cancel").ok, "actual action cancellation preserves visual retirement")
	_assert_batch(actor, runtime, reference, root_reference, definition, registry, "cancelled " + action.id)


func _assert_batch(actor: Node2D, runtime: RefCounted, reference: Sprite2D, root_reference: Node2D, definition: Dictionary, registry: RefCounted, label: String, fallback: bool = false) -> void:
	var complete: Dictionary = runtime.snapshot()
	var before := _authority_bytes(actor, registry)
	var facts := _legacy_facts(complete, definition)
	var returned: Array = actor.native_cold_threat_facts()
	suite.assert_equal(var_to_bytes(returned), var_to_bytes(facts), "all native cold fact fields retain original typed bytes: " + label)
	if not returned.is_empty():
		returned[0].origin = Vector2(-900, -800)
		returned[0].summon_slots.append(Vector2.ONE)
	suite.assert_equal(_authority_bytes(actor, registry), before, "returned geometry mutation cannot change complete authority: " + label)
	var pose: StringName = &"cast" if complete.action.phase == "WARNING" else &"attack" if complete.action.phase == "ACTIVE" else &"idle"
	if complete.terminal:
		pose = &"death"
	var facing := Vector2.RIGHT if complete.action.committed_aim.is_empty() else _vector(complete.action.committed_aim)
	suite.assert_true(reference.present(pose, facing, float(complete.runtime_frame) / 60.0, false, false), "original atlas accepts reference state")
	reference.modulate = Color(0.55, 0.95, 1.0) if runtime.is_exposed() else Color.WHITE
	var root_visible: bool = definition.id == "forest_heart" and not complete.terminal and complete.action.action_id == "matriarch_root_sweep" and complete.action.phase in ["WARNING", "ACTIVE"]
	if root_visible:
		root_reference.set_accessibility_options(bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))
		suite.assert_true(root_reference.project_fact(Coordinator.native_threat_fact(complete.action.committed_geometry[0]), str(complete.action.action_id)), "original rooted geometry forms its reference")
	else:
		root_reference.clear_telegraph()
	var expected_watch := _legacy_watch(actor, complete, definition)
	runtime.full_snapshot_calls = 0
	for _repeat: int in range(16):
		actor.call("_refresh_control_visual")
		var sprite := actor.get_node("Sprite2D") as Sprite2D
		suite.assert_equal(var_to_bytes(sprite.snapshot()), var_to_bytes(reference.snapshot()), "sprite atlas fields retain exact original projection: " + label)
		suite.assert_equal(sprite.modulate, reference.modulate, "exposure tint preserves current authority: " + label)
		_assert_telegraphs(actor, complete, facts, root_reference, root_visible, label)
		var watch := actor.get_node_or_null("WatchHurtbox")
		if watch != null:
			suite.assert_equal(var_to_bytes(watch.projection_snapshot()), var_to_bytes(expected_watch), "Watch retains original complete projection: " + label)
	var per_refresh := 3 + int(definition.id == "time_sovereign") if fallback else int(definition.id == "time_sovereign") + int(complete.action.action_id == "traitor_self_rewind")
	suite.assert_equal(runtime.full_snapshot_calls, per_refresh * 16, "sixteen actual refreshes avoid complete Boss histories except retained branches: " + label)
	suite.assert_equal(_authority_bytes(actor, registry), before, "visual refresh preserves complete typed Actor/Health/threat state: " + label)


func _assert_telegraphs(actor: Node2D, complete: Dictionary, facts: Array, root_reference: Node2D, root_visible: bool, label: String) -> void:
	var phase: String = "TERMINAL" if complete.terminal or complete.action.action_id == "matriarch_root_sweep" else str(complete.action.phase)
	var visible_facts: Array = facts if phase in ["WARNING", "ACTIVE"] else []
	var holder := actor.get_node_or_null("LaunchTelegraphs")
	suite.assert_equal(holder.get_child_count() if holder != null else 0, visible_facts.size(), "all original committed telegraph primitives remain visible: " + label)
	if holder != null:
		suite.assert_equal(holder.z_index, 4 if str(complete.action.action_id).begins_with("traitor.counter_") else -1, "counter telegraph ordering preserves original rule")
		for index: int in range(mini(holder.get_child_count(), visible_facts.size())):
			var expected := Telegraph.new()
			expected.set_accessibility_options(bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))
			suite.assert_true(expected.project_fact(visible_facts[index], str(complete.action.action_id)), "original committed primitive forms its reference")
			suite.assert_equal(var_to_bytes(holder.get_child(index).get_snapshot()), var_to_bytes(expected.get_snapshot()), "complete telegraph fields retain original typed projection: " + label)
			expected.free()
	var root := actor.get_node_or_null("RootSweepTelegraph")
	suite.assert_equal(root != null and root.visible, root_visible, "root-owned warning visibility preserves original rule: " + label)
	if root != null:
		suite.assert_equal(var_to_bytes(root.get_snapshot()), var_to_bytes(root_reference.get_snapshot()), "complete root warning retains original typed projection: " + label)


func _check_deferred(actor: Node2D, runtime: RefCounted, reference: Sprite2D, root_reference: Node2D, definition: Dictionary, registry: RefCounted) -> void:
	var sprite := actor.get_node("Sprite2D")
	var shown := var_to_bytes(sprite.snapshot())
	suite.assert_true(runtime.cancel_action(&"contact_visual_cancel").ok, "accepted action changes before contact projection")
	runtime.full_snapshot_calls = 0
	Hitbox.dispatch_contact(func():
		actor.call("_refresh_control_visual")
		actor.call("_refresh_control_visual")
		suite.assert_true(actor.get("_queued_control_visual"), "native contact queues a deferred visual flush")
		suite.assert_equal(var_to_bytes(sprite.snapshot()), shown, "contact dispatch preserves presentation until safe flush")
	)
	suite.assert_equal(runtime.full_snapshot_calls, 0, "contact dispatch never reads complete authority")
	await get_tree().process_frame
	suite.assert_true(not actor.get("_queued_control_visual"), "deferred visual flush clears its one pending flag")
	_assert_batch(actor, runtime, reference, root_reference, definition, registry, "deferred " + definition.id)


func _authority_bytes(actor: Node2D, registry: RefCounted) -> PackedByteArray:
	return var_to_bytes({"actor": actor.launch_runtime_snapshot(), "health": actor.get_node("HealthComponent").runtime_state_snapshot(), "threats": registry.snapshot()})


func _legacy_facts(state: Dictionary, definition: Dictionary) -> Array:
	var facts: Array = state.action.committed_geometry.duplicate(true)
	if state.action.action_id == "traitor_self_rewind" and not state.mechanism_state.rewind.is_empty():
		var action := {}
		for candidate: Dictionary in definition.actions + definition.get("time_responses", []):
			if candidate.id == state.action.action_id:
				action = candidate
		if action.is_empty():
			return []
		var landing: Dictionary = state.mechanism_state.rewind.landing
		facts = [{"hostile_source_id": state.identity.hostile_source_id, "attack_generation": state.action.geometry_generations[0], "shape": "circle", "origin": landing, "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": landing, "summon_slots": [], "radius": 16.0, "length": 0.0, "active_from_frame": state.action.commit_frame, "active_through_frame": int(state.action.idle_through_frame) - int(action.idle_frames)}]
	var result: Array = []
	for fact: Dictionary in facts:
		result.append(Coordinator.native_threat_fact(fact))
	return result


func _legacy_watch(actor: Node2D, state: Dictionary, definition: Dictionary) -> Dictionary:
	if definition.id != "time_sovereign":
		return {}
	var rewind: Dictionary = state.mechanism_state.rewind
	var active: bool = state.action.phase == "WARNING" and state.action.action_id == "traitor_self_rewind" and not rewind.is_empty() and not rewind.consumed
	var broken: bool = not rewind.is_empty() and rewind.cancelled and float(rewind.weakpoint_damage) >= float(definition.mechanisms.rewind_interrupt_damage)
	var health := actor.get_node("HealthComponent")
	return {"owner_source_id": str(actor.get("hostile_source_id")), "runtime_frame": int(state.runtime_frame), "hittable": not state.terminal and health != null and not health.dead, "cast_generation": int(rewind.attack_generation) if active else 0, "maximum_hp": float(definition.mechanisms.rewind_interrupt_damage), "current_hp": 0.0 if broken else float(definition.mechanisms.rewind_interrupt_damage) - (float(rewind.weakpoint_damage) if active else 0.0)}


func _context(actor: Node2D, frame: int) -> Dictionary:
	var context := Actions.context(frame)
	context.source_position = _point(actor.global_position)
	context.target_position = _point(actor.global_position + Vector2(20, 0))
	return context


func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))
