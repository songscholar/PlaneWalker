extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
var suite: RefCounted


class CountedBoss extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var context_calls := 0
	var native_commit_context_calls := 0
	var actor: WeakRef
	func _snapshot_validation_context() -> PackedByteArray:
		context_calls += 1
		var owner: Node = actor.get_ref() if actor != null else null
		if owner != null and owner.get("_native_launch_frame_mutating") and owner.get("_native_launch_frame_token") != null:
			native_commit_context_calls += 1
		return super._snapshot_validation_context()


class ClaimingCommit extends "res://scripts/enemies/launch/launch_boss_actor.gd":
	func can_commit_launch_frame(_ticket: Dictionary) -> bool:
		return true


class InterveningStatus extends "res://scripts/enemies/launch/launch_elemental_status_runtime.gd":
	var after_validation: Callable
	func can_restore_transaction_snapshot(value: Dictionary) -> bool:
		var accepted := super.can_restore_transaction_snapshot(value)
		if accepted and after_validation.is_valid():
			var callback := after_validation
			after_validation = Callable()
			callback.call()
		return accepted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for row: Dictionary in Content.read_catalog("bosses.json"):
		await _test_actor(row)
	await _test_custom_validator()
	await _test_custom_status_intervention()
	suite.finish(get_tree())


func _fixture(row: Dictionary, claiming: bool = false) -> Dictionary:
	var room_id := "room_boss_" + str(row.id)
	var room := (load("res://data/content_packs/base/assets/rooms/launch/%s.tscn" % room_id) as PackedScene).instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var template: Dictionary = {}
	for candidate: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if candidate.id == room_id:
			template = candidate
	var actor := (load("res://data/content_packs/base/assets/bosses/launch/boss_%s.tscn" % row.id) as PackedScene).instantiate() as Node2D
	if claiming:
		actor.set_script(ClaimingCommit)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(320, 180)
	var parser := Definition.new()
	suite.assert_true(parser.configure(row).ok, "commit fixture resolves authored Boss " + row.id)
	var identity := Actions.identity()
	identity.seed = 42
	identity.hostile_source_id = "commit-" + str(row.id)
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok and actor.configure_launch_room_motion(room, template).ok, "commit fixture binds actual actor and physical room")
	var original: RefCounted = actor.get("_launch_runtime")
	var runtime := CountedBoss.new()
	suite.assert_true(runtime.configure(actor.get("_launch_definition"), actor.get("_launch_identity")).ok and runtime.configure_arena_origin(original.get("_arena_origin"), original.get("_arena_trunk_origin")) and runtime.restore_snapshot(original.snapshot()), "counter delegates complete production configuration and restoration")
	runtime.actor = weakref(actor)
	actor.set("_launch_runtime", runtime)
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = actor.global_position + Vector2(20, 0)
	return {"room": room, "actor": actor, "runtime": runtime, "player": player}


func _test_actor(row: Dictionary) -> void:
	var fixture := _fixture(row)
	var actor: Node2D = fixture.actor
	var runtime: RefCounted = fixture.runtime
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before := var_to_bytes(actor.launch_runtime_snapshot())
	var observations := Actions.context(1)
	observations.source_position = _point(actor.global_position)
	observations.target_position = _point(fixture.player.global_position)
	var prepared: Dictionary = actor.prepare_launch_frame(1, observations)
	suite.assert_true(prepared.ok, "public commit prepares actual complete Boss candidate")
	if prepared.get("ok", false):
		runtime.set("context_calls", 0)
		suite.assert_true(actor.commit_launch_frame(prepared.ticket), "actual public commit retains complete validation and installation")
		suite.assert_equal(runtime.get("context_calls"), 2, "single public commit uses one actor guard plus original runtime restore guard: " + row.id)
		suite.assert_equal(var_to_bytes(runtime.snapshot()), var_to_bytes(prepared.ticket.after.runtime), "actual public installation preserves every typed candidate field")
		suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "public rollback retains original full compensation guard")
		suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "public rollback restores exact complete actor state")
	var registry := Registry.new()
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-p15"), "native effects retains authoritative run")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(fixture.player, registry, [actor], effects), "real native Bridge binds original actor and effects")
	var frame := bridge.begin_frame(1)
	runtime.set("native_commit_context_calls", 0)
	suite.assert_true(not frame.is_empty() and bridge.prepare_frame(frame), "real Bridge prepares and commits exact native frame")
	suite.assert_equal(runtime.get("native_commit_context_calls"), 2, "actual native commit avoids a duplicate actor guard: " + row.id)
	suite.assert_true(bridge.rollback_frame(frame), "real Bridge retains full checkpoint rollback")
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "native rollback restores original typed actor state")
	suite.assert_equal(registry.snapshot(), [], "native rollback restores original threat prefix")
	var retry := bridge.begin_frame(1)
	suite.assert_true(not retry.is_empty() and bridge.prepare_frame(retry), "compensated actual frame retries deterministically")
	var publication := bridge.prepare_frame_publication(retry)
	suite.assert_true(not publication.is_empty() and bridge.finalize_frame_publication(publication) and bridge.seal_frame_publication(publication), "real frame retains original publication gates")
	bridge.publish_prepared_frame()
	suite.assert_equal(runtime.native_runtime_frame(), 1, "only accepted actual publication advances Boss frame")
	await _dispose(fixture)


func _test_custom_validator() -> void:
	var fixture := _fixture(Content.boss("ruin_king"), true)
	var actor: Node2D = fixture.actor
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before := var_to_bytes(actor.launch_runtime_snapshot())
	var observations := Actions.context(1)
	observations.source_position = _point(actor.global_position)
	observations.target_position = _point(fixture.player.global_position)
	var prepared: Dictionary = actor.prepare_launch_frame(1, observations)
	suite.assert_true(prepared.get("ok", false), "custom override fixture prepares actual full candidate")
	if prepared.get("ok", false):
		var owned: Dictionary = actor.get("_prepared_launch_frame")
		owned.after.runtime.terminal = 0
		suite.assert_true(not actor.commit_launch_frame(owned), "custom can-commit override cannot bypass the original complete restore guard")
		suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "custom override refusal cannot install forged runtime state")
	await _dispose(fixture)


func _test_custom_status_intervention() -> void:
	var fixture := _fixture(Content.boss("ruin_king"))
	var actor: Node2D = fixture.actor
	var status := InterveningStatus.new()
	suite.assert_true(status.restore_transaction_snapshot(actor.elemental_status_runtime.transaction_snapshot()), "custom status fixture restores original exact authority")
	actor.elemental_status_runtime = status
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before := var_to_bytes(actor.launch_runtime_snapshot())
	var observations := Actions.context(1)
	observations.source_position = _point(actor.global_position)
	observations.target_position = _point(fixture.player.global_position)
	var prepared: Dictionary = actor.prepare_launch_frame(1, observations)
	suite.assert_true(prepared.get("ok", false), "custom status prepares an otherwise authentic full candidate")
	if prepared.get("ok", false):
		status.after_validation = func(): prepared.ticket.after.runtime.terminal = 0
		suite.assert_true(not actor.commit_launch_frame(prepared.ticket), "custom status callback cannot change an earlier validated runtime before installation")
		suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "custom status intervention preserves the original complete refusal behavior")
	await _dispose(fixture)


func _dispose(fixture: Dictionary) -> void:
	fixture.actor.queue_free()
	fixture.player.queue_free()
	fixture.room.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
