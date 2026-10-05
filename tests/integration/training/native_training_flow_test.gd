extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Snapshots := preload("res://scripts/content/content_snapshot_provider.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")

var suite: RefCounted
var _fault := false
var _saved: Array = []
var _service: RefCounted
var _flow: Node
var _player: Node2D
var _drift := false
var _detach_saved := false
var _reentrant: Dictionary = {}
var _reconfigure: Dictionary = {}
var _registry: RefCounted
var _save: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/training/native_training_flow.gd") as Script
	suite.assert_true(implementation != null, "native training flow requires actual Player/World success-frame bootstrap")
	if implementation == null:
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	_registry = registry
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not loaded.has_blocking_errors(), "training uses real activated Launch content")
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var save := Save.new()
	_save = save
	suite.assert_true(save.configure(Paths.resolve_default("user://p16-training", "p16-training"), "test-training", Snapshots.snapshot(registry), Callable(), Callable(self, "_inject_fault")).ok, "training uses physical Profile save")
	var service := Service.new()
	_service = service
	suite.assert_true(service.configure(catalog, save, "training_slot", "base").ok, "training configures real fresh Profile")
	var flow: Node = implementation.new()
	_flow = flow
	add_child(flow)
	flow.set_process(false)
	suite.assert_true(flow.configure(registry, service).ok, "native flow binds real content and Profile service")
	var before: Dictionary = service.snapshot()
	var request := {"task_id": "T-01", "seed": 42, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	var unavailable := request.duplicate(true)
	unavailable.task_id = "T-05"
	suite.assert_equal(flow.start(unavailable).code, &"TRAINING_BOSS_UNAVAILABLE", "unimplemented Boss conversion cannot fabricate task-five reward")
	suite.assert_true(flow.training_player() == null and service.snapshot() == before, "unavailable drill changes no native or Profile participant")
	var started: Dictionary = flow.start(request)
	suite.assert_true(started.ok, "training creates independent actual native Player and World")
	if not started.ok:
		flow.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var player: Node2D = started.context.player
	_player = player
	player.set_physics_process(false)
	var adapter: RefCounted = started.context.adapter
	adapter.observation_saved.connect(_on_saved)
	suite.assert_equal(player.loadout_runtime.run_seed(), request.seed, "training seed reaches the actual native loadout")
	suite.assert_equal(service.bind_training(player, "T-01", 43).code, &"TRAINING_BINDING_INVALID", "service refuses a different seed for the actual attempt")
	suite.assert_equal(service.bind_training(player, "T-02", 42).code, &"TRAINING_BINDING_INVALID", "service refuses a different task for the actual attempt")
	suite.assert_true(service.get("_training_adapter") == adapter, "refused deterministic identity never retires the issued adapter")
	suite.assert_true(service.snapshot() == before and service.snapshot().active_launch_receipt.is_empty(), "training bootstrap creates no launch receipt or progression mutation")
	player.authoritative_frame_committed.emit(1)
	suite.assert_true(adapter.pending_observations().is_empty(), "public frame signal cannot certify an uncommitted input")
	suite.assert_true(player.advance_action_frame(_intents(1, Vector2.RIGHT)), "real movement frame commits for task one")
	suite.assert_equal(adapter.pending_observations().size(), 1, "successful native input creates one sealed training observation")
	_fault = true
	var failed: Dictionary = flow.process_pending_observations()
	suite.assert_true(not failed.ok and service.snapshot() == before and _saved.is_empty(), "failed primary promotion publishes no reward or training progress")
	suite.assert_equal(adapter.pending_observations().size(), 1, "failed physical save retains exact native receipt")
	_fault = false
	suite.assert_true(flow.process_pending_observations().ok, "physical training save retries authentic observation")
	var dash := _intents(2, Vector2.ZERO)
	dash.dash = [{"id": &"dash", "edge": &"pressed", "held_frames": 0, "mode": &"press"}]
	suite.assert_true(player.advance_action_frame(dash), "actual training dash frame commits")
	suite.assert_true(adapter.is_live_binding(), "native dash checkpoint validates: " + str(Replay.validate_full_player_snapshot(player.full_player_replay_snapshot(), player.full_player_replay_identity())))
	suite.assert_equal(adapter.pending_observations().size(), 1, "accepted dash issues observation: " + str(player.priority_arbitration_snapshot()))
	var completed: Dictionary = flow.process_pending_observations()
	suite.assert_true(completed.ok and completed.context.get("completed_tasks", []) == ["T-01"], "native movement and dash complete only selected authored task: " + str(completed))
	suite.assert_equal(service.snapshot().chronos_shards, before.chronos_shards + 3, "first task grants exactly three durable shards")
	var permanent: Dictionary = service.snapshot()
	suite.assert_true(permanent.launch_sequence == before.launch_sequence and permanent.last_settlement_receipt == before.last_settlement_receipt and permanent.statistics == before.statistics, "practice actions do not consume launch sequence, settlement or run statistics")
	suite.assert_true(not service.observe_training(RefCounted.new(), permanent.revision).ok, "caller-created adapter cannot submit fabricated receipts")
	suite.assert_true(flow.reset_attempt().ok, "native reset replaces completed attempt and refills")
	player = flow.training_player()
	player.set_physics_process(false)
	suite.assert_close(player.health.current_hp, player.health.max_hp, "native attempt reset restores actual full HP")
	suite.assert_true(service.snapshot() == permanent, "reset never clears durable claim or grants another reward")
	suite.assert_true(player.advance_action_frame(_intents(1, Vector2.RIGHT)) and flow.process_pending_observations().ok, "repeat task receives a new actual movement")
	suite.assert_true(player.advance_action_frame(dash) and flow.process_pending_observations().ok, "repeat task receives a new actual dash")
	suite.assert_equal(service.snapshot().chronos_shards, permanent.chronos_shards, "repeated native completion never rewards twice")
	flow.close()
	await get_tree().process_frame
	suite.assert_true(flow.training_player() == null and adapter.pending_observations().is_empty(), "close retires actual training subtree and receipt owner")
	await _test_sandbox_matrix(flow, service)
	await _test_real_weapon_tasks(flow, service)
	await _test_native_refusal(flow, service)
	await _test_save_publication(flow, service)
	await _test_lifecycle(flow)
	flow.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _intents(frame: int, movement: Vector2) -> Dictionary:
	return {"movement": movement, "aim": Vector2.RIGHT, "dash": [], "weapon": [], "time": [], "character": [], "meta": {"source": "training-test", "target_frame": frame, "frame": frame}}


func _inject_fault(stage: StringName) -> bool:
	if stage == &"before_primary_promote" and _drift and is_instance_valid(_player):
		_player.health.current_hp -= 1.0
	return _fault and stage == &"before_primary_promote"


func _on_saved(receipt: Dictionary) -> void:
	_saved.append(receipt.duplicate(true))
	var primary = _save.inspect_profile("training_slot", "base")
	suite.assert_true(primary.ok and int(primary.payload.payload.meta_profile_state.revision) == int(_service.snapshot().revision), "saved training observation sees promoted durable Profile")
	_reentrant = _service.execute_tutorial({"command_id": "training-reentry", "kind": "tutorial_suppress", "suppressed": true}, int(_service.snapshot().revision))
	_reconfigure = _service.enable_tutorial(_registry.get_catalog_entries(&"tutorial_definition", &"LAUNCH"))
	if _detach_saved:
		_flow.training_adapter().detach()


func _test_sandbox_matrix(flow: Node, service: RefCounted) -> void:
	var before: Dictionary = service.snapshot()
	var cases := 0
	for character: String in Catalog.CHARACTER_IDS:
		for weapon: String in Catalog.WEAPON_IDS:
			for first: int in range(Catalog.TIME_IDS.size()):
				for second: int in range(first + 1, Catalog.TIME_IDS.size()):
					var request := {"task_id": "T-02", "seed": 71, "character_id": character, "weapon_id": weapon, "time_abilities": [Catalog.TIME_IDS[first], Catalog.TIME_IDS[second]]}
					var started: Dictionary = flow.start(request)
					suite.assert_true(started.ok, "sandbox configures canonical loadout: " + character + "/" + weapon + "/" + str(request.time_abilities))
					if started.ok:
						var player: Node2D = started.context.player
						player.set_physics_process(false)
						var identity: Dictionary = player.full_player_replay_identity()
						suite.assert_true(identity.character_id == character and identity.weapon_id == weapon and identity.time_ability_ids == request.time_abilities and started.context.adapter.is_live_binding(), "150-matrix uses actual configured native identity and World")
						cases += 1
					flow.close()
					await get_tree().process_frame
	suite.assert_equal(cases, 150, "all five-character/five-weapon/six-pair sandbox loadouts configure")
	suite.assert_equal(service.snapshot(), before, "sandbox matrix does not unlock or spend Profile content")


func _test_real_weapon_tasks(flow: Node, service: RefCounted) -> void:
	var before: Dictionary = service.snapshot()
	for weapon: String in Catalog.WEAPON_IDS:
		var request := {"task_id": "T-02", "seed": 74, "character_id": "wanderer", "weapon_id": weapon, "time_abilities": ["stop", "rewind"]}
		var started: Dictionary = flow.start(request)
		suite.assert_true(started.ok, "five-weapon primary drill starts with actual " + weapon)
		if not started.ok:
			continue
		var player: Node2D = started.context.player
		player.set_physics_process(false)
		await get_tree().process_frame
		var action := _intents(1, Vector2.ZERO)
		action.weapon = [{"id": &"weapon_primary", "edge": &"pressed", "held_frames": 0, "mode": &"hold"}]
		suite.assert_true(player.advance_action_frame(action), "actual primary action frame accepts: " + weapon)
		if player.weapon_action_coordinator.phase_name() == &"HOLD":
			suite.assert_true(started.context.adapter.pending_observations().is_empty(), "unreleased primary HOLD cannot finish attack training: " + weapon)
			var release := _intents(2, Vector2.ZERO)
			release.weapon = [{"id": &"weapon_primary", "edge": &"released", "held_frames": 1, "mode": &"hold"}]
			suite.assert_true(player.advance_action_frame(release), "actual native primary release commits: " + weapon)
		var observed: Dictionary = flow.process_pending_observations()
		suite.assert_true(observed.ok and observed.context.get("consumed", false), "native primary action persists through actual service: " + weapon)
		suite.assert_equal(service.snapshot().chronos_shards, before.chronos_shards + 5, "five native weapons share one first-completion task reward")
		flow.close()
		await get_tree().process_frame
	for task: String in ["T-03", "T-04", "T-06"]:
		var request := {"task_id": task, "seed": 77, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
		var started: Dictionary = flow.start(request)
		suite.assert_true(started.ok, "real selected training task starts: " + task)
		if not started.ok:
			continue
		var player: Node2D = started.context.player
		player.set_physics_process(false)
		await get_tree().process_frame
		var action_id: String = {"T-03": "time_slot_1", "T-04": "weapon_primary", "T-06": "weapon_skill"}[task]
		var category := "time" if task == "T-03" else "weapon"
		var action := _intents(1, Vector2.ZERO)
		action[category] = [{"id": StringName(action_id), "edge": &"pressed", "held_frames": 0, "mode": &"hold" if task == "T-04" else &"press"}]
		suite.assert_true(player.advance_action_frame(action) and flow.process_pending_observations().ok, "actual selected task action commits: " + task)
		var recovery_start := 2
		if task == "T-04" and player.weapon_action_coordinator.phase_name() == &"HOLD":
			var released := _intents(2, Vector2.ZERO)
			released.weapon = [{"id": &"weapon_primary", "edge": &"released", "held_frames": 1, "mode": &"hold"}]
			suite.assert_true(player.advance_action_frame(released) and flow.process_pending_observations().ok, "actual combined drill releases its committed attack")
			recovery_start = 3
		if task != "T-03":
			for frame: int in range(recovery_start, 121):
				suite.assert_true(player.advance_action_frame(_intents(frame, Vector2.ZERO)), "native action recovery advances in training")
			var next := _intents(121, Vector2.ZERO)
			category = "dash" if task == "T-04" else "time"
			action_id = "dash" if task == "T-04" else "time_slot_1"
			next[category] = [{"id": StringName(action_id), "edge": &"pressed", "held_frames": 0, "mode": &"press"}]
			suite.assert_true(player.advance_action_frame(next), "real combination follow-up commits: " + task)
			var result: Dictionary = flow.process_pending_observations()
			suite.assert_true(result.ok and result.context.get("completed_tasks", []) == [task], "real combination completes only selected task: " + task)
		flow.close()
		await get_tree().process_frame
	suite.assert_equal(service.snapshot().chronos_shards, before.chronos_shards + 38, "tasks two, three, four and six grant exactly 5/5/8/20 once")
	suite.assert_true(not service.tutorial_progress_view().context.training_claims.has("T-05"), "unavailable Boss task has no claim")
	suite.assert_true(service.snapshot().statistics == before.statistics and service.snapshot().launch_sequence == before.launch_sequence, "actual five-weapon and combination drills leave formal run statistics unchanged")


func _test_native_refusal(flow: Node, service: RefCounted) -> void:
	var request := {"task_id": "T-01", "seed": 81, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	var started: Dictionary = flow.start(request)
	if not started.ok:
		suite.assert_true(false, "native refusal drill configures")
		return
	var player: Node2D = started.context.player
	player.set_physics_process(false)
	await get_tree().process_frame
	var adapter: RefCounted = started.context.adapter
	var before: Dictionary = service.snapshot()
	var world: Node = player.world_payload_authority
	player.world_payload_authority = null
	suite.assert_true(not adapter.is_live_binding() and not service.bind_training(player, "T-01", 81).ok, "missing actual native World refuses binding and observations")
	player.world_payload_authority = world
	player.remove_child(world)
	suite.assert_true(not adapter.is_live_binding(), "detached actual World refuses without script error")
	player.add_child(world)
	suite.assert_true(adapter.is_live_binding(), "reattached original World revalidates actual native state")
	suite.assert_true(not player.advance_action_frame({"unknown": true}) and adapter.pending_observations().is_empty(), "rejected input frame cannot grant training progress")
	world.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not suite.expect_rejected_player_frame(player, _intents(1, Vector2.RIGHT)), "actual late World refusal exercises training failed-frame boundary")
	suite.assert_true(adapter.pending_observations().is_empty() and service.snapshot() == before, "rolled-back native frame publishes no training receipt or reward")
	world.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(_intents(1, Vector2.RIGHT)), "exact successful frame retries after native refusal")
	suite.assert_true(flow.process_pending_observations().ok, "retried native frame persists actual observation")
	player.health.lose_health(player.health.current_hp, "training-death")
	suite.assert_true(player.health.dead, "practice exercises authentic native Health death")
	var permanent: Dictionary = service.snapshot()
	suite.assert_true(flow.reset_attempt().ok, "practice death resets independent native attempt")
	player = flow.training_player()
	player.set_physics_process(false)
	suite.assert_true(not player.health.dead and player.health.current_hp == player.health.max_hp, "death reset refills actual native HP")
	suite.assert_true(service.snapshot() == permanent and permanent.statistics == before.statistics and permanent.last_settlement_receipt == before.last_settlement_receipt, "practice death consumes no launch settlement or death statistic")
	flow.close()
	await get_tree().process_frame


func _test_save_publication(flow: Node, service: RefCounted) -> void:
	var request := {"task_id": "T-01", "seed": 86, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	var started: Dictionary = flow.start(request)
	if not started.ok:
		suite.assert_true(false, "publication drill configures")
		return
	_player = started.context.player
	_player.set_physics_process(false)
	await get_tree().process_frame
	started.context.adapter.observation_saved.connect(_on_saved)
	suite.assert_true(_player.advance_action_frame(_intents(1, Vector2.RIGHT)), "save drift test receives actual movement")
	var before: Dictionary = service.snapshot()
	_drift = true
	var drifted: Dictionary = flow.process_pending_observations()
	_drift = false
	suite.assert_equal(drifted.code, &"NATIVE_PUBLICATION_PENDING", "native drift after promoted primary quarantines publication")
	suite.assert_equal(service.snapshot().revision, before.revision + 1, "promoted native observation stays durable exactly once")
	suite.assert_true(not drifted.context.has("completed_tasks"), "unconfirmed native drift publishes no task completion")
	flow.close()
	await get_tree().process_frame
	started = flow.start(request)
	suite.assert_true(started.ok, "new training binding resumes durable watermark after native drift")
	_player = started.context.player
	_player.set_physics_process(false)
	await get_tree().process_frame
	started.context.adapter.observation_saved.connect(_on_saved)
	suite.assert_true(_player.advance_action_frame(_intents(1, Vector2.RIGHT)), "saved callback test receives real new movement")
	_detach_saved = true
	var pending: Dictionary = flow.process_pending_observations()
	_detach_saved = false
	suite.assert_equal(pending.code, &"NATIVE_PUBLICATION_PENDING", "saved callback detachment consumes receipt once before stopping presentation")
	suite.assert_equal(_reentrant.code, &"BUSY", "saved callback cannot reenter Profile progress mutation")
	suite.assert_true(not _reconfigure.ok, "saved callback cannot replace authored tutorial runtime")
	flow.close()
	await get_tree().process_frame
	var restarted := Service.new()
	suite.assert_true(restarted.configure(Factory.from_registry(_registry).context.catalog, _save, "training_slot", "base").ok, "physical restart reads actual training rewards and watermark")
	suite.assert_equal(restarted.snapshot(), service.snapshot(), "physical training restart preserves all claims and rewards")


func _test_lifecycle(flow: Node) -> void:
	var request := {"task_id": "T-02", "seed": 92, "character_id": "wanderer", "weapon_id": "gun", "time_abilities": ["rift", "stop"]}
	var started: Dictionary = flow.start(request)
	if not started.ok:
		suite.assert_true(false, "native retirement fixture configures")
		return
	var player: Node2D = started.context.player
	player.set_physics_process(false)
	await get_tree().process_frame
	var action := _intents(1, Vector2.ZERO)
	action.weapon = [{"id": &"weapon_primary", "edge": &"pressed", "held_frames": 0, "mode": &"hold"}]
	suite.assert_true(player.advance_action_frame(action), "actual gun input commits before native retirement")
	var release := _intents(2, Vector2.ZERO)
	release.weapon = [{"id": &"weapon_primary", "edge": &"released", "held_frames": 1, "mode": &"hold"}]
	suite.assert_true(player.advance_action_frame(release), "real gun trigger release creates its native attack")
	for frame: int in range(3, 16):
		suite.assert_true(player.advance_action_frame(_intents(frame, Vector2.ZERO)), "gun release travels through actual native frames")
	var projectiles: Array = []
	for node: Node in player.gun_weapon.owned_projectiles_for_test():
		projectiles.append(weakref(node))
	suite.assert_true(not projectiles.is_empty(), "real gun owns a live external projectile before close")
	flow.close()
	await get_tree().process_frame
	await get_tree().process_frame
	for reference: WeakRef in projectiles:
		suite.assert_true(reference.get_ref() == null, "native close releases real external weapon projectiles")
	request.task_id = "T-03"
	started = flow.start(request)
	player = started.context.player
	player.set_physics_process(false)
	await get_tree().process_frame
	action = _intents(1, Vector2.ZERO)
	action.time = [{"id": &"time_slot_1", "edge": &"pressed", "held_frames": 0, "mode": &"press"}]
	suite.assert_true(player.advance_action_frame(action), "actual Rift input creates owned World content")
	var world: Node = player.world_payload_authority
	suite.assert_true(not world.replay_snapshot().descriptors.is_empty(), "training Rift uses actual native World descriptors")
	var world_ref: WeakRef = weakref(world)
	flow.close()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_true(world_ref.get_ref() == null, "native close releases independent World and Rift subtree")
	request.task_id = "T-01"
	started = flow.start(request)
	player = started.context.player
	player.set_physics_process(false)
	await get_tree().process_frame
	var baseline: Dictionary = player.full_player_replay_snapshot()
	var adapter: RefCounted = started.context.adapter
	for frame: int in range(1, 4):
		suite.assert_true(player.advance_action_frame(_intents(frame, Vector2.RIGHT)), "clock rollback fixture receives actual input")
	suite.assert_equal(adapter.pending_observations().size(), 1, "saturated movement requirement retains one observation instead of writing every frame")
	suite.assert_true(player.restore_full_player_replay_snapshot(baseline), "training tests actual full native Replay rollback")
	suite.assert_true(not adapter.is_live_binding(), "clock rollback permanently retires native training observation binding")
	for frame: int in range(1, 5):
		suite.assert_true(player.advance_action_frame(_intents(frame, Vector2.RIGHT)), "native Replay catch-up uses actual frames")
	suite.assert_true(not adapter.is_live_binding(), "later clock catch-up cannot reactivate retired reward owner")
	flow.close()
	await get_tree().process_frame
