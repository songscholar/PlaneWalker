extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Snapshots := preload("res://scripts/content/content_snapshot_provider.gd")
const Run := preload("res://scripts/application/run_state.gd")
const RunConfig := preload("res://scripts/application/run_config.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Generator := preload("res://scripts/dungeon/floor_plan_generator.gd")
const Economy := preload("res://scripts/economy/run_economy_state.gd")
const Merchant := preload("res://scripts/economy/merchant_run_state.gd")
const EventRuntime := preload("res://scripts/events/dungeon_event_runtime.gd")
const EventState := preload("res://scripts/events/dungeon_event_run_state.gd")
const EventSelector := preload("res://scripts/events/dungeon_event_selector.gd")
const EventRequirements := preload("res://scripts/events/event_requirement_service.gd")
const EventConsequences := preload("res://scripts/events/dungeon_event_consequence_runtime.gd")
const EventResources := preload("res://scripts/events/event_resource_authority.gd")
const EventHealth := preload("res://scripts/events/event_health_authority.gd")
const EventModifiers := preload("res://scripts/events/event_modifier_authority.gd")
const EventRoute := preload("res://scripts/events/event_route_authority.gd")
const Adapter := preload("res://scripts/onboarding/tutorial_native_adapter.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")

var suite: RefCounted
var _service: RefCounted
var _save: RefCounted
var _catalog: RefCounted
var _player: Node2D
var _state: RefCounted
var _adapter: RefCounted
var _fault: StringName = &""
var _drift_on_promote := false
var _detach_on_saved := false
var _drift_on_saved := false
var _saved: Array = []
var _reentrant: Dictionary = {}
var _configure_during_saved: Dictionary = {}
var _before_promote: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	_service = Service.new()
	for api: String in ["enable_tutorial", "tutorial_progress_view", "execute_tutorial", "bind_tutorial_run", "observe_tutorial", "restore_tutorial_run", "retire_tutorial_run"]:
		suite.assert_true(_service.has_method(api), "physical tutorial integration requires service API: " + api)
		if not _service.has_method(api):
			suite.finish(get_tree())
			return
	_catalog = Factory.load_base().context.catalog
	var registry := Registry.new()
	var report: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "actual Base Registry configures the tutorial session")
	_save = Save.new()
	suite.assert_true(_save.configure(Paths.resolve_default("user://p16-tutorial-service", "p16-tutorial-service"), "test-p16-tutorial", Snapshots.snapshot(registry), Callable(), Callable(self, "_inject_fault")).ok, "tutorial service uses actual content and physical JSON storage")
	suite.assert_true(_service.configure(_catalog, _save, "slot_tutorial", "base").ok and _service.enable_tutorial(_content("tutorial_definitions.json")).ok, "physical tutorial configures actual authored progress")
	var request := {"seed": 73, "difficulty": "normal", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	var config := RunConfig.normalized({"milestone": "LAUNCH", "seed": 73, "character_talents": ["tal_ruin_execute", "tal_eternity_reserve"]})
	var launched: Dictionary = _service.prepare_launch(request, _service.snapshot().revision, config)
	suite.assert_true(launched.ok, "native tutorial starts with a saved authenticated launch")
	if not launched.ok:
		suite.finish(get_tree())
		return
	_player = PlayerScene.instantiate() as Node2D
	_player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_player)
	await get_tree().process_frame
	var native_config := {"milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "meta_run_projection": launched.context.projection}
	native_config.character_talents = ["tal_eternity_reserve", "tal_ruin_execute"]
	native_config.character_talent_definitions = []
	for talent: Dictionary in _content("talents.json"):
		if config.character_talents.has(talent.id):
			native_config.character_talent_definitions.append(talent)
	suite.assert_true(_player.configure_run(StringName(launched.context.launch.run_id)) and _player.configure_loadout(native_config), "tutorial fixture follows native Host Player construction order")
	_state = Run.new()
	_state.reset_domain(config, launched.context.launch.run_id)
	_state.phase = Phase.Value.RUN_PREPARING
	suite.assert_true(_state.bind_meta_run_projection(launched.context.projection, _catalog), "actual Run binds the exact frozen projection")
	_state.bind_player_reward_baseline(_player.reward_effect_snapshot())
	_initialize_floor()
	var validated = Envelope.validate_active_run_snapshot(_state.snapshot())
	suite.assert_true(validated.ok, "complete actual native Run passes Save contract: " + str(validated.metadata))
	suite.assert_true(_service.retain_active_run(_state, _player, _service.snapshot().revision).ok, "physical baseline retains both native reward and Run participants")
	var wrong := Node.new()
	suite.assert_true(not _service.bind_tutorial_run(_state, wrong).ok and not _service.bind_tutorial_run(RefCounted.new(), _player).ok, "foreign native objects cannot bind to the Profile")
	wrong.free()
	var foreign_talents := PlayerScene.instantiate() as Node2D
	foreign_talents.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(foreign_talents)
	await get_tree().process_frame
	var talent_config := native_config.duplicate(true)
	talent_config.character_talents = ["tal_eternity_reserve"]
	for talent: Dictionary in _content("talents.json"):
		if talent.id == "tal_eternity_reserve":
			talent_config.character_talent_definitions = [talent]
	suite.assert_true(foreign_talents.configure_run(StringName(launched.context.launch.run_id)) and foreign_talents.configure_loadout(talent_config), "adversarial native Player uses valid authored foreign talent selection")
	suite.assert_true(not _service.bind_tutorial_run(_state, foreign_talents).ok, "valid foreign native talents cannot replace durable launch configuration")
	foreign_talents.queue_free()
	var actual_world: Node = _player.world_payload_authority
	_player.world_payload_authority = null
	suite.assert_true(not _service.bind_tutorial_run(_state, _player).ok, "missing actual native World snapshot participant cannot bind Tutorial observer")
	_player.world_payload_authority = actual_world
	var bound: Dictionary = _service.bind_tutorial_run(_state, _player)
	suite.assert_true(bound.ok, "service creates native observer for identical selected talent set despite canonical runtime order")
	if not bound.ok:
		await _finish()
		return
	_adapter = bound.context.adapter
	_adapter.observation_saved.connect(_on_saved)
	suite.assert_true(not _service.observe_tutorial(Adapter.new(), _service.snapshot().revision).ok, "caller-created adapter cannot submit observations")
	suite.assert_true(_player.advance_action_frame(_intents(1, Vector2.RIGHT)), "actual first movement frame commits")
	var pending: Array = _adapter.pending_observations()
	suite.assert_true(pending.size() == 1 and pending[0].action_id == "move" and pending[0].trigger_ids == ["first_dungeon_entry"], "real native entry derives one movement receipt and authored hint trigger")
	var before: Dictionary = _service.snapshot()
	var before_payload: Dictionary = _service.payload()
	var before_run: Dictionary = _state.snapshot()
	var before_player: Dictionary = _player.reward_effect_snapshot()
	_fault = &"before_primary_promote"
	var failed: Dictionary = _service.observe_tutorial(_adapter, before.revision)
	suite.assert_true(not failed.ok and not failed.context.has("hints"), "physical failure publishes no tutorial hints")
	suite.assert_equal(_service.snapshot(), before, "physical failure advances no tutorial Profile progress")
	suite.assert_equal(_service.payload(), before_payload, "physical failure preserves the complete service payload")
	suite.assert_true(_state.snapshot() == before_run and _player.reward_effect_snapshot() == before_player, "physical failure changes no native participants")
	suite.assert_equal(_adapter.pending_observations(), pending, "failed physical write retains the exact sealed adapter receipt for retry")
	suite.assert_equal(_saved.size(), 0, "failed primary promotion cannot notify the UI")
	_fault = &"after_primary_promote"
	var observed: Dictionary = _service.observe_tutorial(_adapter, before.revision)
	_fault = &""
	suite.assert_true(observed.ok and observed.context.reconciled_committed_write and observed.context.hints.size() == 1, "retry reconciles actual committed primary before returning authored hint")
	suite.assert_true(_before_promote.profile == before and _before_promote.saved_count == 0, "primary promotion precedes Profile and UI publication")
	suite.assert_true(_saved.size() == 1 and _adapter.pending_observations().is_empty(), "saved native receipt is consumed and published exactly once")
	suite.assert_equal(_reentrant.get("code"), &"BUSY", "adapter saved callback cannot reenter the physical service")
	suite.assert_true(not _configure_during_saved.ok, "adapter saved callback cannot reconfigure the live service")
	suite.assert_true(_service.payload().active_run_state == before_run and _service.payload().reward_effect_state == before_player, "one physical envelope stores progress and complete native reward/Run checkpoint")
	for frame: int in range(2, 4):
		suite.assert_true(_player.advance_action_frame(_intents(frame, Vector2.RIGHT)), "actual subsequent movement frame commits")
		suite.assert_true(_service.observe_tutorial(_adapter, _service.snapshot().revision).ok, "actual movement persists without forged receipts")
	var dash := _intents(4, Vector2.ZERO)
	dash.dash = [{"id": &"dash", "edge": &"pressed", "held_frames": 0, "mode": &"press"}]
	suite.assert_true(_player.advance_action_frame(dash), "actual dash arbitration commits")
	var completed: Dictionary = _service.observe_tutorial(_adapter, _service.snapshot().revision)
	suite.assert_true(completed.ok and completed.context.completed_lessons == ["movement_dodge"], "three native movements and one native dash complete exactly the authored lesson")
	suite.assert_equal(_service.snapshot().tutorial_state.completed_lessons, ["movement_dodge"], "lesson completion is durable Profile state")
	for talent: Dictionary in _content("talents.json"):
		if talent.id == "tal_steel_recover":
			suite.assert_true(_state.apply_reward_definition(talent).ok and _player.install_character_talent(talent), "actual native Player and Run acquire a valid additional character talent")
	suite.assert_true(_service.retain_active_run(_state, _player, _service.snapshot().revision).ok, "earned native talent does not alter or invalidate frozen initial talent selection")
	var launch_before: Dictionary = _service.snapshot().active_launch_receipt
	var projection_before: Dictionary = _service.frozen_launch_projection()
	var suppress := {"command_id": "suppress", "kind": "tutorial_suppress", "suppressed": true}
	before = _service.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not _service.execute_tutorial(suppress, before.revision).ok and _service.snapshot() == before, "suppression write failure leaves preferences and active receipt unchanged")
	_fault = &""
	suite.assert_true(_service.execute_tutorial(suppress, before.revision).ok, "suppression retry persists once")
	suite.assert_true(not _service.execute_tutorial(suppress, _service.snapshot().revision).ok, "duplicate suppression command refuses")
	var skip := {"command_id": "skip-weapon", "kind": "tutorial_skip", "lesson_id": "weapon_basics"}
	before = _service.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not _service.execute_tutorial(skip, before.revision).ok and _service.snapshot() == before, "skip save failure cannot publish progress")
	_fault = &""
	suite.assert_true(_service.execute_tutorial(skip, before.revision).ok and _service.snapshot().tutorial_state.skipped_lessons == ["weapon_basics"], "skip retry persists actual authored lesson")
	suite.assert_true(_service.snapshot().active_launch_receipt == launch_before and _service.frozen_launch_projection() == projection_before, "skip and suppression preserve frozen launch authority")
	var stale := Service.new()
	suite.assert_true(stale.configure(_catalog, _save, "slot_tutorial", "base").ok and stale.enable_tutorial(_content("tutorial_definitions.json")).ok, "stale service starts from actual saved tutorial watermark")
	var stale_bound: Dictionary = stale.bind_tutorial_run(_state, _player)
	suite.assert_true(stale_bound.ok, "stale service binds current native checkpoint")
	_adapter.detach()
	var restarted := Service.new()
	suite.assert_true(restarted.configure(_catalog, _save, "slot_tutorial", "base").ok and restarted.enable_tutorial(_content("tutorial_definitions.json")).ok, "physical restart restores progress and watermark")
	_service = restarted
	bound = _service.bind_tutorial_run(_state, _player)
	suite.assert_true(bound.ok and bound.context.adapter.pending_observations().is_empty(), "replacement native observer does not replay consumed observations")
	_adapter = bound.context.adapter
	_adapter.observation_saved.connect(_on_saved)
	_idle_frames()
	suite.assert_true(_advance_native("weapon_primary", "weapon"), "restart receives a real new accepted native action")
	suite.assert_true(_adapter.pending_observations().size() == 1 and _adapter.pending_observations()[0].action_sequence == 5, "physical watermark continues action sequence without duplicate entry hint")
	before = _service.snapshot()
	before_player = _player.reward_effect_snapshot()
	_drift_on_promote = true
	var drifted: Dictionary = _service.observe_tutorial(_adapter, before.revision)
	_drift_on_promote = false
	suite.assert_true(drifted.code == &"NATIVE_PUBLICATION_PENDING" and _service.snapshot().revision == before.revision + 1, "promoted primary with native drift retains one durable progress advance")
	suite.assert_true(not drifted.context.has("hints") and _adapter.pending_observations().size() == 1, "native drift exposes no hints and preserves unconfirmed sealed receipt until recovery")
	suite.assert_equal(_service.retain_active_run(_state, _player, _service.snapshot().revision).code, &"NATIVE_PUBLICATION_PENDING", "native retention cannot overwrite publication recovery point")
	var old_adapter: RefCounted = _adapter
	var restored: Dictionary = _service.restore_tutorial_run()
	suite.assert_true(restored.ok and restored.context.adapter != old_adapter and old_adapter.pending_observations().is_empty(), "recovery restores saved native participants and retires old receipt owner")
	suite.assert_equal(_player.reward_effect_snapshot(), before_player, "native recovery restores the saved full reward participant state")
	_adapter = restored.context.adapter
	_adapter.observation_saved.connect(_on_saved)
	suite.assert_true(not stale.restore_tutorial_run().ok, "stale service cannot restore an obsolete primary")
	stale.retire_tutorial_run()
	_idle_frames()
	suite.assert_true(_advance_native("weapon_skill", "weapon"), "saved callback test receives authentic accepted weapon skill")
	_detach_on_saved = true
	var notification_before := _saved.size()
	var callback_pending: Dictionary = _service.observe_tutorial(_adapter, _service.snapshot().revision)
	_detach_on_saved = false
	suite.assert_true(callback_pending.code == &"NATIVE_PUBLICATION_PENDING" and _saved.size() == notification_before + 1 and _adapter.pending_observations().is_empty(), "saved callback detachment consumes committed receipt once before requiring recovery")
	var callback_revision: int = _service.snapshot().revision
	suite.assert_true(not _service.observe_tutorial(_adapter, callback_revision).ok, "saved callback failure cannot resend consumed tutorial receipt")
	restored = _service.restore_tutorial_run()
	suite.assert_true(restored.ok and _service.snapshot().revision == callback_revision, "saved callback recovery creates a fresh observer without another progress grant")
	_adapter = restored.context.adapter
	_adapter.observation_saved.connect(_on_saved)
	_idle_frames()
	suite.assert_true(_advance_native("time_slot_1", "time"), "saved callback drift test receives authentic time action")
	_drift_on_saved = true
	callback_pending = _service.observe_tutorial(_adapter, _service.snapshot().revision)
	_drift_on_saved = false
	suite.assert_equal(callback_pending.code, &"NATIVE_PUBLICATION_PENDING", "saved notification native reward drift requires physical recovery")
	_service.retire_tutorial_run()
	suite.assert_equal(_service.retain_active_run(_state, _player, _service.snapshot().revision).code, &"NATIVE_PUBLICATION_PENDING", "retiring presentation cannot bypass durable native recovery")
	suite.assert_equal(_service.execute({"command_id": "pending-meta", "kind": "meta_unlock", "node_id": "W-01"}, _service.snapshot().revision).code, &"NATIVE_PUBLICATION_PENDING", "another Profile command cannot overwrite publication recovery state")
	restored = _service.restore_tutorial_run()
	suite.assert_true(restored.ok, "retirement attempt preserves actual native binding needed for recovery")
	_adapter = restored.context.adapter if restored.ok else _adapter
	await _finish()


func _initialize_floor() -> void:
	var economy := Economy.new()
	var merchant := Merchant.new()
	suite.assert_true(economy.configure(_content("economy_profiles.json")[0], 10).ok and merchant.configure("b".repeat(64)).ok and _state.initialize_launch_economy_state(economy.snapshot(), merchant.snapshot()), "complete native economy and merchant initialize before actual floor entry")
	var floor: Dictionary = _content("floors.json")[0]
	var templates := _content("room_templates.json")
	var generated: Dictionary = Generator.new().generate(73, floor, templates)
	suite.assert_true(_state.configure_floor_plan(generated.plan, floor, templates).ok, "native tutorial uses actual generated first floor")
	for node: Dictionary in generated.plan.nodes:
		if node.id == generated.plan.boss_node_id:
			_state.room_total = int(node.layer)
	_state.phase = Phase.Value.ROOM_ACTIVE
	var resource := EventResources.new()
	var health := EventHealth.new()
	var modifier := EventModifiers.new()
	var route := EventRoute.new()
	var state := EventState.new()
	var definitions: Array = Envelope._launch_event_definitions()
	var fingerprint: String = Envelope._event_runtime_digest({"events": definitions})
	suite.assert_true(resource.configure({"time_shard": 0, "forge_essence": 0}) and health.configure(_player.health.current_hp, _player.health.max_hp) and modifier.configure([], {}, []) and route.configure(_state.floor_plan) and state.configure(fingerprint).ok, "actual native Event participants configure for floor health")
	var consequences := EventConsequences.new()
	suite.assert_true(consequences.configure(resource, health, economy, modifier, route, state), "actual complete Event consequence runtime configures")
	var runtime := EventRuntime.new()
	var secret: String = Envelope._event_runtime_digest({"schema": "event_publication_secret_v1", "content_fingerprint": fingerprint, "run_id": _state.run_id, "run_seed": _state.run_seed})
	suite.assert_true(runtime.configure(definitions, EventSelector.new(), state, EventRequirements.new(), consequences, Callable(self, "_event_context"), Callable(self, "_event_sink"), Callable(self, "_event_fact_sink"), secret) and _state.initialize_launch_event_state(runtime.snapshot()), "actual authored Event runtime initializes native Run")
	suite.assert_true(_state.commit_meta_floor_entrance(_player.health.current_hp, _player.health.max_hp, _player.health.current_hp), "native Meta entrance commits exactly once")


func _event_context() -> Dictionary:
	return {}


func _event_sink(_command: Dictionary, _revision: int) -> Dictionary:
	return {"ok": false, "code": &"UNAVAILABLE"}


func _event_fact_sink(_fact: Dictionary) -> bool:
	return false


func _inject_fault(point: StringName) -> bool:
	if point == &"before_primary_promote" and _service != null:
		_before_promote = {"profile": _service.snapshot(), "saved_count": _saved.size()}
		if _drift_on_promote:
			_player.health.current_hp -= 1.0
	return point == _fault


func _on_saved(receipt: Dictionary) -> void:
	var primary = _save.inspect_profile("slot_tutorial", "base")
	suite.assert_true(primary.ok and primary.payload.payload.meta_profile_state.revision == _service.snapshot().revision, "native saved notification observes already committed physical Profile")
	_saved.append(receipt.duplicate(true))
	_reentrant = _service.execute_tutorial({"command_id": "reentrant", "kind": "tutorial_suppress", "suppressed": true}, _service.snapshot().revision)
	_configure_during_saved = _service.configure(_catalog, _save, "slot_tutorial", "base")
	if _detach_on_saved:
		_adapter.detach()
	if _drift_on_saved:
		_player.health.current_hp -= 1.0


func _intents(frame: int, movement: Vector2) -> Dictionary:
	return {"dash": [], "time": [], "weapon": [], "character": [], "movement": movement, "aim": Vector2.RIGHT, "meta": {"source": "tutorial_profile_service_test", "target_frame": frame, "frame": frame}}


func _idle_frames() -> void:
	for _index: int in range(60):
		var frame: int = int(_player.priority_arbitration_snapshot().frame) + 1
		suite.assert_true(_player.advance_action_frame(_intents(frame, Vector2.ZERO)), "actual native recovery frame commits without teaching semantics")


func _advance_native(action_id: String, category: String) -> bool:
	var frame: int = int(_player.priority_arbitration_snapshot().frame) + 1
	var intents := _intents(frame, Vector2.ZERO)
	intents[category] = [{"id": StringName(action_id), "edge": &"pressed", "held_frames": 0, "mode": &"press"}]
	return _player.advance_action_frame(intents)


func _content(filename: String) -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/" + filename))


func _finish() -> void:
	_service.retire_tutorial_run()
	_player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_service = null
	_player = null
	suite.finish(get_tree())
