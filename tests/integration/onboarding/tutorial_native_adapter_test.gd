extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const Runtime := preload("res://scripts/onboarding/tutorial_runtime.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Run := preload("res://scripts/application/run_state.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Generator := preload("res://scripts/dungeon/floor_plan_generator.gd")

var suite: RefCounted
var _published: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/onboarding/tutorial_native_adapter.gd") as Script
	suite.assert_true(implementation != null, "native tutorial adapter derives observations from committed Player frames")
	if implementation == null:
		suite.finish(get_tree())
		return
	var catalog := Fixtures.catalog()
	var profile := Fixtures.profile(catalog)
	var projection: Dictionary = MetaProjection.from_profile(profile, catalog).context.projection
	profile.launch_sequence = 1
	profile.active_launch_receipt = {"schema_id": "meta_launch_receipt_v1", "sequence": 1, "run_id": "native-tutorial-run", "difficulty": "normal", "seed": 42, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "projection_digest": projection.projection_digest}
	var registry := Registry.new()
	var report: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "real Launch content loads for tutorial native test")
	var player := PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	var config := {"milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "meta_run_projection": projection}
	suite.assert_true(player.configure_run(&"native-tutorial-run") and player.configure_loadout(config), "adapter test uses real configured native Launch Player")
	var state := Run.new()
	state.reset_domain({"milestone": "LAUNCH", "seed": 42}, "native-tutorial-run")
	state.resources.meta_run_projection = projection
	var floors: Array = _content("floors.json")
	var templates: Array = _content("room_templates.json")
	var generated: Dictionary = Generator.new().generate(42, floors[0], templates)
	suite.assert_true(state.configure_floor_plan(generated.plan, floors[0], templates).ok, "native tutorial belongs to an actual generated floor")
	state.phase = Phase.Value.ROOM_ACTIVE
	var adapter: RefCounted = implementation.new()
	suite.assert_true(not implementation.new().bind_normal_run(profile, RefCounted.new(), player).ok, "foreign Run refuses before native protocol access")
	var foreign_player := Node.new()
	suite.assert_true(not implementation.new().bind_normal_run(profile, state, foreign_player).ok, "foreign Player refuses before native protocol access")
	foreign_player.free()
	var resources_before: Dictionary = state.resources.duplicate(true)
	state.resources.meta_run_projection = true
	suite.assert_true(not implementation.new().bind_normal_run(profile, state, player).ok, "malformed native projection refuses without protocol error")
	state.resources = resources_before.duplicate(true)
	var contradictory_projection := projection.duplicate(true)
	contradictory_projection.stat_bonuses.attack += 0.01
	state.resources.meta_run_projection = contradictory_projection
	suite.assert_true(not implementation.new().bind_normal_run(profile, state, player).ok, "unchanged digest cannot authenticate contradictory native projection fields")
	state.resources = resources_before.duplicate(true)
	suite.assert_true(adapter.bind_normal_run(profile, state, player).ok, "adapter binds actual Run, Player and active profile receipt")
	adapter.observation_saved.connect(_on_saved)
	player.authoritative_frame_committed.emit(1)
	suite.assert_equal(adapter.pending_observations().size(), 0, "forged early frame notification has no matching committed native frame")
	var runtime := Runtime.new()
	runtime.configure(_content("tutorial_definitions.json"), catalog)
	var initial: Dictionary = player.full_player_replay_snapshot()
	for frame: int in range(1, 4):
		suite.assert_true(player.advance_action_frame(_intents(frame, Vector2.RIGHT)), "actual native movement frame commits")
		var ticket: Dictionary = adapter.prepared_observation(profile)
		suite.assert_true(ticket.ok, "committed movement derives a sealed tutorial receipt")
		if not ticket.ok:
			continue
		suite.assert_equal(ticket.context.receipt.action_id, "move", "native displacement maps to movement semantic")
		suite.assert_equal(_published.size(), frame - 1, "prepared observation cannot publish before durable confirmation")
		var altered: Dictionary = ticket.context.receipt.duplicate(true)
		altered.action_id = "boss_conversion"
		suite.assert_true(not adapter.can_confirm_saved(altered, ticket.context.seal), "caller cannot change an issued native semantic fact")
		state.resources.meta_run_projection = contradictory_projection.duplicate(true)
		suite.assert_true(not adapter.can_confirm_saved(ticket.context.receipt, ticket.context.seal), "live projection fields cannot drift behind an unchanged digest")
		state.resources = resources_before.duplicate(true)
		var candidate: Dictionary = runtime.prepare_observation(profile, ticket.context.receipt, profile.revision)
		suite.assert_true(candidate.ok, "native receipt reaches real pure tutorial runtime")
		if candidate.ok:
			profile = candidate.context.candidate
			suite.assert_true(adapter.can_confirm_saved(ticket.context.receipt, ticket.context.seal), "sealed ticket remains available through deferred save")
			suite.assert_true(adapter.confirm_saved(ticket.context.receipt, ticket.context.seal).ok, "confirmed observation publishes once")
			suite.assert_true(not adapter.confirm_saved(ticket.context.receipt, ticket.context.seal).ok, "confirmed ticket cannot publish twice")
	suite.assert_equal(_published.size(), 3, "three successful frames publish only after confirmation")
	var committed_intents: Dictionary = player.authoritative_frame_intents(3)
	suite.assert_equal(committed_intents.movement, Vector2.RIGHT, "committed getter exposes the actual movement intent")
	committed_intents.movement = Vector2.ZERO
	committed_intents.meta.source = "forged"
	suite.assert_equal(player.authoritative_frame_intents(3).movement, Vector2.RIGHT, "returned movement alias cannot rewrite a committed native frame")
	suite.assert_true(player.authoritative_frame_intents(3).meta.source != "forged", "returned nested alias cannot rewrite committed native metadata")
	suite.assert_true(player.authoritative_frame_intents(2).is_empty(), "getter cannot authenticate a retired frame")
	var knockback_position: Vector2 = player.global_position
	player.apply_knockback(Vector2(180.0, 0.0))
	suite.assert_true(player.advance_action_frame(_intents(4, Vector2.ZERO)), "native knockback with zero input commits")
	suite.assert_true(player.global_position.distance_squared_to(knockback_position) > 0.000001, "native knockback actually displaces the Player")
	suite.assert_true(adapter.pending_observations().is_empty(), "knockback without a movement intent cannot complete movement teaching")
	suite.assert_true(player.advance_action_frame(_intents(5, Vector2.RIGHT)), "real input while knockback remains commits")
	var movement_ticket: Dictionary = adapter.prepared_observation(profile)
	suite.assert_true(movement_ticket.ok, "real movement intent still teaches movement with native knockback")
	if movement_ticket.ok:
		suite.assert_equal(movement_ticket.context.receipt.action_id, "move", "movement derives from authenticated input and native displacement together")
		var movement_candidate: Dictionary = runtime.prepare_observation(profile, movement_ticket.context.receipt, profile.revision)
		suite.assert_true(movement_candidate.ok, "authenticated fourth movement reaches tutorial runtime")
		if movement_candidate.ok:
			profile = movement_candidate.context.candidate
			adapter.confirm_saved(movement_ticket.context.receipt, movement_ticket.context.seal)
	var before_count: int = adapter.pending_observations().size()
	suite.assert_true(not player.advance_action_frame({"unknown": true}), "invalid native frame fails before commit")
	suite.assert_equal(adapter.pending_observations().size(), before_count, "failed native frame has no tutorial notification")
	state.suspended = true
	suite.assert_true(player.advance_action_frame(_intents(6, Vector2.RIGHT)), "suspension test advances native clock explicitly")
	suite.assert_true(adapter.pending_observations().is_empty(), "suspended Run cannot accumulate teaching actions")
	state.suspended = false
	get_tree().paused = true
	suite.assert_true(player.advance_action_frame(_intents(7, Vector2.RIGHT)), "pause test advances native clock explicitly")
	suite.assert_true(adapter.pending_observations().is_empty(), "pause cannot accumulate teaching actions")
	get_tree().paused = false
	state.phase = Phase.Value.HUB
	suite.assert_true(player.advance_action_frame(_intents(8, Vector2.RIGHT)), "Hub test advances native clock explicitly")
	suite.assert_true(adapter.pending_observations().is_empty(), "Hub does not consume normal-run teaching progress")
	state.phase = Phase.Value.ROOM_ACTIVE
	suite.assert_true(player.restore_full_player_replay_snapshot(initial), "real Replay restoration is exercised")
	suite.assert_true(adapter.pending_observations().is_empty(), "Replay restore emits no new committed semantic action")
	var restored_frame: int = player.full_player_replay_snapshot().frame
	player.advance_action_frame(_intents(restored_frame + 1, Vector2.RIGHT))
	suite.assert_true(adapter.pending_observations().is_empty(), "clock rollback retires observation binding instead of recounting replayed actions")
	adapter.detach()
	player.queue_free()
	await get_tree().process_frame
	await _test_native_semantics(implementation, profile, state, config, runtime)
	suite.finish(get_tree())


func _test_native_semantics(implementation: Script, profile: Dictionary, state: RefCounted, config: Dictionary, runtime: RefCounted) -> void:
	for action_id: String in ["dash", "weapon_primary", "weapon_skill", "time_slot_1"]:
		var player: Node2D = await _spawn_native_player(config)
		var observer: RefCounted = implementation.new()
		suite.assert_true(observer.bind_normal_run(profile, state, player).ok, "fresh native binding observes " + action_id)
		var intents := _intents(1, Vector2.ZERO)
		var category: String = {"dash": "dash", "weapon_primary": "weapon", "weapon_skill": "weapon", "time_slot_1": "time"}[action_id]
		intents[category] = [{"id": StringName(action_id), "edge": &"pressed", "held_frames": 0, "mode": &"press"}]
		suite.assert_true(player.advance_action_frame(intents), "actual native action frame commits: " + action_id)
		var pending: Array = observer.pending_observations()
		suite.assert_equal(pending.size(), 1, "accepted native action creates one teaching semantic: " + action_id)
		if not pending.is_empty():
			suite.assert_equal(pending[0].action_id, action_id, "actual arbitration owns the accepted teaching action: " + action_id)
		observer.detach()
		suite.assert_true(not observer.bind_normal_run(profile, state, player).ok, "detached binding cannot silently reuse a retired receipt owner")
		observer.detach()
		player.queue_free()
		await get_tree().process_frame
	var player: Node2D = await _spawn_native_player(config)
	var publishing: RefCounted = implementation.new()
	suite.assert_true(publishing.bind_normal_run(profile, state, player).ok, "callback fixture binds actual native state")
	suite.assert_true(player.advance_action_frame(_intents(1, Vector2.RIGHT)), "callback fixture commits authentic movement")
	var ticket: Dictionary = publishing.prepared_observation(profile)
	suite.assert_true(ticket.ok, "callback fixture receives sealed native observation")
	if ticket.ok:
		var candidate: Dictionary = runtime.prepare_observation(profile, ticket.context.receipt, profile.revision)
		suite.assert_true(candidate.ok, "callback observation has a valid durable candidate")
		if candidate.ok:
			var delivered: Array = []
			var publisher_ref: WeakRef = weakref(publishing)
			publishing.observation_saved.connect(func(receipt: Dictionary) -> void:
				delivered.append(receipt.duplicate(true))
				publisher_ref.get_ref().detach()
			)
			var published: Dictionary = publishing.confirm_saved(ticket.context.receipt, ticket.context.seal)
			suite.assert_true(not published.ok and published.code == &"NATIVE_PUBLICATION_PENDING", "saved callback identity drift reports explicit publication recovery")
			suite.assert_equal(delivered.size(), 1, "identity drift cannot publish a prefix twice")
			suite.assert_true(not publishing.confirm_saved(ticket.context.receipt, ticket.context.seal).ok, "saved callback drift cannot replay the consumed native ticket")
	publishing.detach()
	player.queue_free()
	await get_tree().process_frame
	player = await _spawn_native_player(config)
	var generation_observer: RefCounted = implementation.new()
	suite.assert_true(generation_observer.bind_normal_run(profile, state, player).ok, "generation fixture binds actual native state")
	suite.assert_true(player.advance_action_frame(_intents(1, Vector2.RIGHT)), "generation fixture commits authentic movement")
	var generation_ticket: Dictionary = generation_observer.prepared_observation(profile)
	suite.assert_true(generation_ticket.ok, "generation fixture has a pending authentic observation")
	suite.assert_true(player.configure_loadout(config), "actual loadout reconfiguration advances owner generation")
	if generation_ticket.ok:
		suite.assert_true(not generation_observer.can_confirm_saved(generation_ticket.context.receipt, generation_ticket.context.seal), "retired owner generation cannot confirm an old teaching receipt")
		suite.assert_true(not generation_observer.prepared_observation(profile).ok, "generation drift refuses before physical Save")
	generation_observer.detach()
	player.queue_free()
	await get_tree().process_frame
	await _test_compensated_frame(implementation, profile, state, config)


func _test_compensated_frame(implementation: Script, profile: Dictionary, state: RefCounted, config: Dictionary) -> void:
	var player: Node2D = await _spawn_native_player(config)
	var observer: RefCounted = implementation.new()
	suite.assert_true(observer.bind_normal_run(profile, state, player).ok, "fault fixture binds an authentic native observation owner")
	var committed: Array = []
	player.authoritative_frame_committed.connect(func(frame: int) -> void: committed.append(frame))
	var authority: Node = player.get_node("WorldPayloadAuthority")
	var before: Dictionary = player.full_player_replay_snapshot()
	authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not player.advance_action_frame(_intents(1, Vector2.RIGHT)), "actual World commit fault rejects a partially prepared movement frame")
	authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_equal(player.full_player_replay_snapshot(), before, "native commit failure compensates the full Player preimage")
	suite.assert_true(committed.is_empty(), "compensated native frame emits no authoritative notification")
	suite.assert_true(player.authoritative_frame_intents(1).is_empty(), "compensated native frame has no authenticated input record")
	suite.assert_true(observer.pending_observations().is_empty(), "compensated native frame cannot enqueue a teaching observation")
	suite.assert_true(player.advance_action_frame(_intents(1, Vector2.RIGHT)), "the same native frame can recover after failed World commit")
	suite.assert_equal(committed, [1], "recovery emits one successfully committed native frame")
	suite.assert_equal(observer.pending_observations().size(), 1, "recovery counts actual teaching movement once")
	observer.detach()
	player.queue_free()
	await get_tree().process_frame


func _spawn_native_player(config: Dictionary) -> Node2D:
	var player := PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	suite.assert_true(player.configure_run(&"native-tutorial-run") and player.configure_loadout(config), "semantic fixture uses real configured native Launch Player")
	return player


func _on_saved(receipt: Dictionary) -> void:
	_published.append(receipt.duplicate(true))


func _intents(frame: int, movement: Vector2) -> Dictionary:
	return {"dash": [], "time": [], "weapon": [], "character": [], "movement": movement, "aim": Vector2.RIGHT, "meta": {"source": "native_tutorial_adapter_test", "target_frame": frame, "frame": frame}}


func _content(filename: String) -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/" + filename))
