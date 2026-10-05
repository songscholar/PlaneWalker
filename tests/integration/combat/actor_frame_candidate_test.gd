extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const EnemyDefinition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const BossDefinition := preload("res://scripts/enemies/launch/boss_definition.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _check_actor("shattered_sentinel")
	await _check_actor("shattered_sentinel", true)
	for row: Dictionary in Content.read_catalog("bosses.json"):
		await _check_actor(str(row.id))
	await _check_actor("shattered_sentinel", false, true)
	suite.finish(get_tree())


func _check_actor(id: String, shielded: bool = false, contact: bool = false) -> void:
	var boss := not Content.boss(id).is_empty()
	var room_id := "room_boss_" + id if boss else "room_combat_open_field"
	var room := (load("res://data/content_packs/base/assets/rooms/launch/%s.tscn" % room_id) as PackedScene).instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var template: Dictionary = {}
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if row.id == room_id:
			template = row
	var path := "res://data/content_packs/base/assets/%s/launch/%s_%s.tscn" % ["bosses" if boss else "enemies", "boss" if boss else "enemy", id]
	var actor := (load(path) as PackedScene).instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(320, 180)
	if shielded:
		suite.assert_true(actor.configure_launch_affixes([Content.affix("shielded")], 3).ok, "actual Shielded configuration precedes actor binding")
	var parser: RefCounted = BossDefinition.new() if boss else EnemyDefinition.new()
	suite.assert_true(parser.configure(Content.boss(id) if boss else Content.enemy(id)).ok, "candidate fixture parses authored " + id)
	var definition: Dictionary = parser.runtime_projection() if boss else parser.runtime_projection("elite" if shielded else "enemy")
	var identity := Actions.identity()
	identity.seed = 42
	identity.hostile_source_id = "candidate-" + id
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok and actor.configure_launch_room_motion(room, template).ok, "actual candidate actor binds its validated native room")
	var source := Node2D.new()
	var attacker := Node2D.new()
	add_child(source)
	add_child(attacker)
	suite.assert_true(actor.apply_elemental_status(&"burn", &"candidate-burn", 1, 60, 1.0, 30, -1.0, source, attacker), "real burn retains live source/attacker identities")
	actor.set_meta("bow_time_erosion_sources", {"bow:1": {"stacks": 2, "time_damage_taken_per_stack": 0.15}})
	actor.set_meta("planewalker_replay_external_fact_claims", {"external:1": {"digest": "retained"}})
	actor.set_meta("elemental_status_seed_initialized", 17)
	actor.set_meta("elemental_status_seed_material", "candidate-seed")
	actor.set("_weapon_hit_control_claims", {17: true, 21: true})
	(actor.get("_weapon_hit_control_claim_order") as Array).assign([17, 21])
	actor.set("_weakpoint_token", 5)
	actor.set("_time_stop_token_sequence", 6)
	actor.set("_elemental_blind_action_sequence", 7)
	actor.set("_action_credit", 0.25)
	actor.set("_knockback_velocity", Vector2(-900, 0) if contact else Vector2(2, 1))
	var blocker: StaticBody2D
	if contact:
		blocker = StaticBody2D.new()
		blocker.collision_layer = 1
		blocker.collision_mask = 0
		blocker.position = Vector2(299, 180)
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = Vector2(4, 80)
		blocker.add_child(shape)
		add_child(blocker)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var label := id + (" shielded" if shielded else "") + (" contact" if contact else "")
	for frame: int in range(1, 4):
		_check_frame(actor, frame, source, attacker, label, blocker if frame == 1 else null)
	actor.queue_free()
	room.queue_free()
	source.queue_free()
	attacker.queue_free()
	if blocker != null:
		blocker.queue_free()
	await get_tree().process_frame


func _check_frame(actor: Node2D, frame: int, source: Node, attacker: Node, label: String, collision: Node) -> void:
	var context := Actions.context(frame)
	context.source_position = _point(actor.global_position)
	context.target_position = _point(actor.global_position + Vector2(120, 0))
	var before: Dictionary = actor.call("_actor_state")
	var before_bytes := var_to_bytes(before)
	var prepared: Dictionary = actor.prepare_launch_frame(frame, context)
	suite.assert_true(prepared.ok, "actual frame prepares: " + label)
	if not prepared.ok:
		return
	var ticket: Dictionary = prepared.ticket
	var pristine := ticket.duplicate(true)
	var retained := var_to_bytes(actor.get("_prepared_launch_frame"))
	suite.assert_equal(var_to_bytes(ticket.before), before_bytes, "before retains complete original typed state: " + label)
	suite.assert_equal(var_to_bytes(ticket.after), var_to_bytes(_original_after(before, ticket.after)), "after preserves original construction field order/types: " + label)
	suite.assert_equal(var_to_bytes(actor.call("_actor_state")), before_bytes, "candidate construction never mutates live state: " + label)
	for state: Dictionary in [ticket.before, ticket.after]:
		for entry: Dictionary in state.status.entries.values():
			suite.assert_true(entry.damage_source == source and entry.damage_attacker == attacker, "deep container copies preserve actual burn Node identities: " + label)
	if collision != null:
		suite.assert_true(ticket.collision_target == collision and actor.get("_prepared_launch_frame").collision_target == collision, "real body contact preserves exact collision object identity")
	if frame == 1:
		_microbenchmark(actor, pristine, label)
	var after_bytes := var_to_bytes(ticket.after)
	_mutate_state(ticket.before)
	suite.assert_equal(var_to_bytes(ticket.after), after_bytes, "returned before mutation cannot alter sibling after: " + label)
	suite.assert_equal(var_to_bytes(actor.get("_prepared_launch_frame")), retained, "returned before mutation cannot alter retained ticket: " + label)
	suite.assert_equal(var_to_bytes(actor.call("_actor_state")), before_bytes, "returned before mutation cannot alter live authority: " + label)
	suite.assert_true(not actor.can_commit_launch_frame(ticket), "complete ticket equality rejects mutated before")
	ticket.before = pristine.before.duplicate(true)
	_mutate_state(ticket.after)
	suite.assert_equal(var_to_bytes(ticket.before), before_bytes, "returned after mutation cannot alter sibling before: " + label)
	suite.assert_equal(var_to_bytes(actor.get("_prepared_launch_frame")), retained, "returned after mutation cannot alter retained ticket: " + label)
	suite.assert_true(not actor.can_commit_launch_frame(ticket), "complete ticket equality rejects mutated after")
	var batch_bytes := var_to_bytes(ticket.batch)
	prepared.batch.threat_facts.append({"caller": true})
	suite.assert_equal(var_to_bytes(actor.get("_prepared_launch_frame")), retained, "returned batch mutation cannot alter retained ticket: " + label)
	suite.assert_equal(var_to_bytes(ticket.batch), batch_bytes, "returned batch stays detached from actual returned ticket batch")
	ticket.batch.effect_requests.append({"caller": true})
	ticket.health_before.current_hp = -100.0
	suite.assert_equal(var_to_bytes(actor.get("_prepared_launch_frame")), retained, "ticket batch/Health mutation cannot alter retained ticket: " + label)
	suite.assert_equal(var_to_bytes(actor.call("_actor_state")), before_bytes, "all returned branch mutations preserve exact live state: " + label)
	suite.assert_true(actor.can_commit_launch_frame(pristine), "pristine independently retained ticket stays valid: " + label)
	suite.assert_true(actor.commit_launch_frame(pristine), "actual candidate commits: " + label)
	suite.assert_equal(var_to_bytes(actor.call("_actor_state")), var_to_bytes(pristine.after), "commit installs complete exact after bytes: " + label)
	suite.assert_true(actor.rollback_launch_frame(pristine), "actual candidate compensates: " + label)
	suite.assert_equal(var_to_bytes(actor.call("_actor_state")), before_bytes, "compensation restores complete exact before bytes: " + label)
	var retry: Dictionary = actor.prepare_launch_frame(frame, context)
	suite.assert_true(retry.ok, "compensated actual frame retries: " + label)
	if not retry.ok:
		return
	for field: String in ["before", "after", "batch", "health_before", "collision_target"]:
		suite.assert_equal(var_to_bytes(retry.ticket[field]), var_to_bytes(pristine[field]), "retry preserves full typed candidate field " + field)
	suite.assert_true(actor.commit_launch_frame(retry.ticket) and actor.publish_launch_frame(retry.ticket), "actual retry commits and publishes: " + label)
	suite.assert_true(not actor.can_commit_launch_frame(retry.ticket) and not actor.rollback_launch_frame(retry.ticket), "published candidate cannot be reused")


func _mutate_state(state: Dictionary) -> void:
	state.runtime.action.cooldowns["caller"] = 23
	state.status.entries.clear()
	state.position.x = -500.0
	state.knockback.y = -700.0
	state.weapon_claims.clear()
	state.weapon_claim_order.append(99)
	state.weapon_metadata.bow_time_erosion_sources["bow:1"].stacks = 8
	state.weapon_metadata.planewalker_replay_external_fact_claims["external:1"].digest = "caller"
	state.room_motion.bounds.x = -900.0
	if state.has("affixes"):
		state.affixes.ids.append("caller")
		state.affixes.pending_ids.append("caller")
		state.affixes.clear()
	if state.has("affix_runtime"):
		state.affix_runtime.shielded.current_pool = -1.0


func _original_after(before: Dictionary, replacements: Dictionary) -> Dictionary:
	var after := before.duplicate(true)
	for field: String in ["runtime", "status", "position", "knockback", "action_credit"]:
		after[field] = replacements[field]
	if before.has("affix_runtime"):
		after.affix_runtime = replacements.affix_runtime
	return after


func _microbenchmark(actor: Node2D, ticket: Dictionary, label: String) -> void:
	var before: Dictionary = ticket.before
	var replacement: Dictionary = ticket.after
	const REPETITIONS := 1000
	var started := Time.get_ticks_usec()
	var result: Dictionary
	for _repeat: int in range(REPETITIONS):
		result = _original_after(before, replacement)
	var original_usec := Time.get_ticks_usec() - started
	var available := actor.has_method("_actor_frame_candidate")
	suite.assert_true(available, "actual optimized candidate constructor must be observable: " + label)
	var candidate_usec := -1
	if available:
		started = Time.get_ticks_usec()
		for _repeat: int in range(REPETITIONS):
			result = actor.call("_actor_frame_candidate", before, replacement.runtime, replacement.status, replacement.position, replacement.knockback, float(replacement.action_credit), replacement.get("affix_runtime", {}))
		candidate_usec = Time.get_ticks_usec() - started
		suite.assert_equal(var_to_bytes(result), var_to_bytes(replacement), "actual narrow constructor retains original typed bytes: " + label)
		var owned := before.duplicate(true)
		result = actor.call("_actor_frame_candidate", owned, replacement.runtime, replacement.status, replacement.position, replacement.knockback, float(replacement.action_credit), replacement.get("affix_runtime", {}))
		owned.weapon_claims.clear()
		owned.weapon_claim_order.append(55)
		owned.weapon_metadata.bow_time_erosion_sources["bow:1"].stacks = 55
		owned.weapon_metadata.planewalker_replay_external_fact_claims["external:1"].digest = "changed"
		owned.room_motion.bounds.x = -55.0
		if owned.has("affixes"):
			owned.affixes.ids.append("caller")
			owned.affixes.pending_ids.append("caller")
			owned.affixes.clear()
		suite.assert_equal(var_to_bytes(result), var_to_bytes(replacement), "unchanged containers are independently owned before exit copies: " + label)
	var discarded_bytes := var_to_bytes(before.runtime).size() + var_to_bytes(before.status).size() + var_to_bytes(before.position).size() + var_to_bytes(before.knockback).size()
	if before.has("affix_runtime"):
		discarded_bytes += var_to_bytes(before.affix_runtime).size()
	print("PLANEWALKER_ACTOR_CANDIDATE_MICROBENCH ", JSON.stringify({"schema_version": 1, "label": label, "repetitions": REPETITIONS, "original_usec": original_usec, "candidate_usec": candidate_usec, "candidate_available": available, "overwritten_branch_serialized_bytes": discarded_bytes, "hardware_timing_gate": false}))


func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
