extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Run := preload("res://scripts/application/run_state.gd")
const RunConfig := preload("res://scripts/application/run_config.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Generator := preload("res://scripts/dungeon/floor_plan_generator.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
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
const PlayerScene := preload("res://scenes/player/player.tscn")
var suite: RefCounted
var _fault: StringName = &""
var _service: RefCounted
var _player: Node2D
var _run_state: RefCounted
var _at_promotion: Dictionary = {}
var _reentrant: Dictionary = {}
var _drift_on_promote := false
var _event_runtime: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	_service = Service.new()
	suite.assert_true(_service.has_method("enable_narrative"), "Profile service requires durable native narrative integration")
	if not _service.has_method("enable_narrative"):
		suite.finish(get_tree())
		return
	var catalog: RefCounted = Factory.load_base().context.catalog
	var packs := [{"pack_id": "base", "pack_version": "1.0.0", "schema_version": 2, "fingerprint_sha256": "a".repeat(64)}]
	var save := Save.new()
	suite.assert_true(save.configure(Paths.resolve_default("user://p16-narrative-service", "p16-narrative-service"), "test-p16-narrative", {"packs": packs, "aggregate_sha256": Envelope.content_snapshot_digest(packs)}, Callable(), Callable(self, "_inject_fault")).ok, "narrative integration uses physical Save files")
	suite.assert_true(_service.configure(catalog, save, "slot_narrative", "base").ok, "strict production Meta Profile configures")
	var entries := _content("narrative_definitions.json")
	var sources := _content("narrative_sources.json")
	suite.assert_true(_service.enable_narrative(entries, sources).ok, "all authored narrative producers configure")
	var dialogue := {"command_id": "intro-phia", "kind": "narrative_dialogue", "npc_id": "phia", "node_id": "phia_intro", "choice_id": "phia_intro_remember"}
	var before: Dictionary = _service.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not _service.execute_narrative(dialogue, before.revision).ok, "dialogue write failure cannot publish affinity or consumption")
	suite.assert_equal(_service.snapshot(), before, "failed physical dialogue write preserves the complete Profile")
	_fault = &""
	suite.assert_true(_service.execute_narrative(dialogue, before.revision).ok, "dialogue retry promotes its one candidate")
	var request := {"seed": 73, "difficulty": "normal", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	var launch_config := RunConfig.normalized({"milestone": "LAUNCH", "seed": 73, "accessibility_assists": {"damage_received_multiplier": 0.8, "enemy_telegraph_scale": 1.25}})
	suite.assert_true(_service.has_method("pending_launch_config"), "durable launch retains complete native run configuration")
	if not _service.has_method("pending_launch_config"):
		suite.finish(get_tree())
		return
	for mutation: String in ["seed", "milestone", "time_pair", "assist", "unknown"]:
		var bad_config := launch_config.duplicate(true)
		match mutation:
			"seed": bad_config.seed += 1
			"milestone": bad_config.milestone = "M1"
			"time_pair": bad_config.enabled_time_skills = ["accelerate", "rift"]
			"assist": bad_config.accessibility_assists.damage_received_multiplier = 0.1
			"unknown": bad_config.hidden_bonus = true
		before = _service.snapshot()
		suite.assert_true(not _service.prepare_launch(request, before.revision, bad_config).ok, "invalid or mismatched %s native launch config refuses before persistence" % mutation)
		suite.assert_equal(_service.snapshot(), before, "invalid launch config changes no native launch sequence or Profile")
	before = _service.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not _service.prepare_launch(request, before.revision, launch_config).ok, "failed launch write cannot consume a launch sequence")
	suite.assert_equal(_service.snapshot(), before, "failed launch retains exact frozen-profile preparation authority")
	_fault = &"after_primary_promote"
	var launched: Dictionary = _service.prepare_launch(request, before.revision, launch_config)
	_fault = &""
	suite.assert_true(launched.ok, "native narrative session has a durable launch receipt")
	if not launched.ok:
		suite.finish(get_tree())
		return
	suite.assert_true(_service.has_method("frozen_launch_projection"), "durable launch retains its exact frozen projection before native bootstrap")
	var bootstrap_restart := Service.new()
	suite.assert_true(bootstrap_restart.configure(catalog, save, "slot_narrative", "base").ok and bootstrap_restart.enable_narrative(entries, sources).ok, "promoted launch reloads before native bootstrap with the same receipt")
	suite.assert_equal(bootstrap_restart.snapshot().active_launch_receipt, _service.snapshot().active_launch_receipt, "physical pending-launch restart reuses its one committed sequence and run identity")
	suite.assert_true(JSON.parse_string(Envelope.canonical_json(bootstrap_restart.pending_launch_config())) == JSON.parse_string(Envelope.canonical_json(launch_config)), "physical pending-launch restart restores exact native configuration including accessibility assists")
	var detached_config: Dictionary = bootstrap_restart.pending_launch_config()
	detached_config.accessibility_assists.damage_received_multiplier = 0.6
	suite.assert_equal(bootstrap_restart.pending_launch_config().accessibility_assists.damage_received_multiplier, 0.8, "pending launch config getter owns a detached native configuration")
	if _service.has_method("frozen_launch_projection"):
		var frozen: Dictionary = bootstrap_restart.frozen_launch_projection()
		suite.assert_true(JSON.parse_string(Envelope.canonical_json(frozen)) == JSON.parse_string(Envelope.canonical_json(launched.context.projection)), "physical pending-launch restart reads the original frozen projection instead of re-deriving from changed profile revision")
		frozen.stat_bonuses.max_hp = 0.5
		suite.assert_equal(bootstrap_restart.frozen_launch_projection().projection_digest, launched.context.projection.projection_digest, "frozen pending-launch projection read is detached")
	_service = bootstrap_restart
	_player = PlayerScene.instantiate() as Node2D
	add_child(_player)
	await get_tree().process_frame
	_player.set_physics_process(false)
	_player.get_node("TimeManager").set_process(false)
	_player.get_node("RewindRecorder").set_process(false)
	var registry := Registry.new()
	var report: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "actual Launch profiles load for native narrative binding")
	var native_config := {"milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "meta_run_projection": launched.context.projection}
	suite.assert_true(_player.configure_run(StringName(launched.context.launch.run_id)), "real Player belongs to the exact launched run")
	suite.assert_true(_player.configure_loadout(native_config), "narrative Player uses real Launch profiles and frozen Meta stats after native run identity")
	suite.assert_true(not _player.full_player_replay_identity().is_empty(), "native narrative fixture follows production Host configuration order")
	_run_state = Run.new()
	_run_state.reset_domain(launch_config, launched.context.launch.run_id)
	_run_state.phase = Phase.Value.RUN_PREPARING
	suite.assert_true(_run_state.bind_meta_run_projection(launched.context.projection, catalog), "actual Run binds the authenticated frozen Meta projection before preparation")
	_run_state.bind_player_reward_baseline(_player.reward_effect_snapshot())
	var economy := Economy.new()
	suite.assert_true(economy.configure(_content("economy_profiles.json")[0], 10).ok, "real authored economy configures for narrative event-health integration")
	var merchant := Merchant.new()
	suite.assert_true(merchant.configure("b".repeat(64)).ok and _run_state.initialize_launch_economy_state(economy.snapshot(), merchant.snapshot()), "native Run initializes matched economy and Merchant before floor entry")
	var floors := _content("floors.json")
	var templates := _content("room_templates.json")
	_enter_floor(floors[0], templates)
	var native_validation = Envelope.validate_active_run_snapshot(_run_state.snapshot())
	suite.assert_true(native_validation.ok, "native narrative event-health Run is a valid complete Save envelope participant: " + str(native_validation.metadata))
	suite.assert_true(_service.bind_narrative_run(_run_state, _player).ok, "service binds actual Run and Player rather than caller context dictionaries")
	var incompatible := PlayerScene.instantiate() as Node2D
	add_child(incompatible)
	incompatible.set_physics_process(false)
	incompatible.configure_run(StringName(launched.context.launch.run_id))
	suite.assert_true(not _service.bind_narrative_run(_run_state, incompatible).ok, "same run string with default M1 loadout cannot bind to a Launch/meta session")
	suite.assert_true(_service.bind_narrative_run(_run_state, _player).ok, "correct binding remains available after refused incompatible Player")
	incompatible.queue_free()
	suite.assert_true(_service.has_method("retain_active_run") and _service.has_method("restore_active_run"), "native Run checkpoint has authenticated atomic retention and recovery APIs")
	if _service.has_method("retain_active_run"):
		before = _service.snapshot()
		var run_checkpoint: Dictionary = _run_state.snapshot()
		var player_checkpoint: Dictionary = _player.reward_effect_snapshot()
		var valid_foreign_profile := before.duplicate(true)
		valid_foreign_profile.unlocked_nodes = ["W-01"]
		var valid_foreign_projection: Dictionary = MetaProjection.from_profile(valid_foreign_profile, catalog).context.projection
		_run_state.resources.meta_run_projection = valid_foreign_projection
		suite.assert_true(not _service.retain_active_run(_run_state, _player, before.revision).ok, "a valid but foreign permanent projection cannot replace the durable launch checkpoint")
		_run_state.resources.meta_run_projection = run_checkpoint.resources.meta_run_projection.duplicate(true)
		_run_state.resources.meta_run_projection.stat_bonuses.max_hp = 0.01
		suite.assert_true(not _service.retain_active_run(_run_state, _player, before.revision).ok, "unchanged projection digest with altered native payload cannot save")
		_run_state.resources.meta_run_projection = run_checkpoint.resources.meta_run_projection.duplicate(true)
		_run_state.config.accessibility_assists.damage_received_multiplier = 0.6
		suite.assert_true(not _service.retain_active_run(_run_state, _player, before.revision).ok, "native config cannot drift from the durable launch configuration")
		_run_state.config = run_checkpoint.config.duplicate(true)
		suite.assert_equal(_service.snapshot(), before, "refused checkpoints cannot advance the durable Profile")
		_fault = &"before_primary_promote"
		suite.assert_true(not _service.retain_active_run(_run_state, _player, before.revision).ok, "failed native checkpoint write is retryable")
		suite.assert_equal(_service.snapshot(), before, "failed native checkpoint advances no Meta revision")
		suite.assert_true(_run_state.snapshot() == run_checkpoint and _player.reward_effect_snapshot() == player_checkpoint, "failed native checkpoint changes no native state")
		_fault = &"after_primary_promote"
		var retained: Dictionary = _service.retain_active_run(_run_state, _player, before.revision)
		suite.assert_true(retained.ok and retained.context.reconciled_committed_write, "native checkpoint retry reconciles the actual primary atomically")
		_fault = &""
		suite.assert_true(_service.payload().active_run_state == run_checkpoint and _service.payload().reward_effect_state == player_checkpoint, "native checkpoint stores complete Run and native reward participants in one envelope")
		_player.health.current_hp -= 1.0
		suite.assert_true(_service.restore_active_run(_run_state, _player).ok and _player.reward_effect_snapshot() == player_checkpoint, "general native checkpoint recovery restores actual saved participants")
		_drift_on_promote = true
		var drifted_retention: Dictionary = _service.retain_active_run(_run_state, _player, _service.snapshot().revision)
		_drift_on_promote = false
		suite.assert_equal(drifted_retention.code, &"NATIVE_PUBLICATION_PENDING", "committed native checkpoint detects callback drift and requires recovery")
		var saved_revision: int = _service.snapshot().revision
		suite.assert_true(not _service.retain_active_run(_run_state, _player, saved_revision).ok and _service.snapshot().revision == saved_revision, "publication-pending checkpoint cannot overwrite its recovery point")
		suite.assert_true(_service.restore_active_run(_run_state, _player).ok and _player.reward_effect_snapshot() == player_checkpoint, "checkpoint callback drift recovers without another Profile command")
	var runtime_parent := Node2D.new()
	add_child(runtime_parent)
	var room := _room(templates)
	var token_result: Dictionary = _service.install_narrative_occurrence("collect", "phia_marker_1", room.node, room.template, "room_exit", runtime_parent)
	suite.assert_true(token_result.ok, "service installs an authored source at the validated native scene anchor")
	if not token_result.ok:
		_player.queue_free()
		room.node.queue_free()
		runtime_parent.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var token: Area2D = token_result.context.occurrence
	suite.assert_true(not _service.install_narrative_occurrence("collect", "heart_fragment_2", room.node, room.template, "room_exit", runtime_parent).ok, "authored source from another floor cannot be installed")
	var collect := {"command_id": "phia-marker", "kind": "narrative_collect", "source_receipt_id": "phia_marker_1"}
	var fake := Area2D.new()
	runtime_parent.add_child(fake)
	suite.assert_true(not _service.execute_narrative(collect, _service.snapshot().revision, fake).ok, "arbitrary scene node cannot impersonate an issued occurrence")
	suite.assert_true(not _service.execute_narrative(collect, _service.snapshot().revision).ok, "source string alone cannot mint a collection")
	_player.global_position = token.global_position + Vector2(100, 0)
	await get_tree().physics_frame
	suite.assert_true(not _service.execute_narrative(collect, _service.snapshot().revision, token).ok, "real source still requires native Player contact")
	_player.global_position = token.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	var original_mask := token.collision_mask
	token.collision_mask = 0
	suite.assert_true(not _service.execute_narrative(collect, _service.snapshot().revision, token).ok, "changed native collision mask cannot authorize a source")
	token.collision_mask = original_mask
	var collision := token.get_child(0) as CollisionShape2D
	collision.shape.radius += 1.0
	suite.assert_true(not _service.execute_narrative(collect, _service.snapshot().revision, token).ok, "mutated native contact radius cannot authorize a source")
	collision.shape.radius -= 1.0
	room.node.position += Vector2.ONE
	suite.assert_true(not _service.execute_narrative(collect, _service.snapshot().revision, token).ok, "moved room cannot keep a stale source token")
	room.node.position -= Vector2.ONE
	var anchor: Marker2D = room.node.get_node("InteractionAnchors/room_exit")
	anchor.position += Vector2.ONE
	suite.assert_true(not _service.execute_narrative(collect, _service.snapshot().revision, token).ok, "moved authored anchor cannot keep a stale source token")
	anchor.position -= Vector2.ONE
	await get_tree().physics_frame
	await get_tree().physics_frame
	before = _service.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not _service.execute_narrative(collect, before.revision, token).ok, "failed source write retains its genuine contact token for retry")
	suite.assert_equal(_service.snapshot(), before, "failed native source collection changes no durable facts")
	_fault = &""
	var source_player_before: Dictionary = _player.reward_effect_snapshot()
	_drift_on_promote = true
	var collected: Dictionary = _service.execute_narrative(collect, before.revision, token)
	_drift_on_promote = false
	suite.assert_true(collected.code == &"NATIVE_PUBLICATION_PENDING" and _service.snapshot().revision == before.revision + 1, "committed pure collection detects native callback drift while preserving its one durable grant")
	suite.assert_true(_service.restore_narrative_run().ok and _player.reward_effect_snapshot() == source_player_before, "pure collection callback drift restores saved native state without another grant")
	suite.assert_equal(_reentrant.get("code"), &"BUSY", "primary promotion cannot reenter the narrative command pipeline")
	collect.command_id = "phia-marker-renamed"
	suite.assert_true(not _service.execute_narrative(collect, _service.snapshot().revision, token).ok, "renaming a command cannot collect the scene source twice")
	room.node.queue_free()
	fake.queue_free()
	for index: int in range(4):
		_complete_floor(launched.context.launch)
		_enter_floor(floors[index + 1], templates)
	room = _room(templates)
	var vera_result: Dictionary = _service.install_narrative_occurrence("choice", "choice_vera_1", room.node, room.template, "room_exit", runtime_parent)
	suite.assert_true(vera_result.ok, "Vera uses a distinct authenticated native occurrence on her authored floor")
	if vera_result.ok:
		var vera: Area2D = vera_result.context.occurrence
		_player.global_position = vera.global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		var listen := {"command_id": "vera-listen", "kind": "narrative_choice", "definition_id": "choice_vera_1", "choice_id": "listen"}
		var player_before: Dictionary = _player.reward_effect_snapshot()
		var run_before: Dictionary = _run_state.snapshot()
		before = _service.snapshot()
		_fault = &"before_primary_promote"
		suite.assert_true(not _service.execute_narrative(listen, before.revision, vera).ok, "failed Vera save cannot spend native maximum HP")
		suite.assert_equal(_player.reward_effect_snapshot(), player_before, "failed Vera transaction leaves every native Player participant unchanged")
		suite.assert_equal(_run_state.snapshot(), run_before, "failed Vera transaction leaves active Run unchanged")
		_fault = &"after_primary_promote"
		var listened: Dictionary = _service.execute_narrative(listen, before.revision, vera)
		suite.assert_true(listened.ok and listened.context.reconciled_committed_write, "Vera reconciles actual promoted primary before native publication: " + str(listened.get("code")))
		suite.assert_equal(_at_promotion.player, player_before, "physical promotion observes original Player capacity")
		suite.assert_true(_at_promotion.run == run_before, "physical promotion observes original active Run")
		suite.assert_equal(_player.stats.max_hp, player_before.stats.max_hp - 5.0, "Vera reduces real Stats capacity by five exactly once")
		suite.assert_equal(_player.health.max_hp, _player.stats.max_hp, "native Health and Stats agree after durable publication")
		suite.assert_equal(_run_state.resources.get("health", {}).get("maximum"), _player.health.max_hp, "Vera synchronizes the actual Run Event health resource maximum")
		suite.assert_equal(_run_state.resources.get("health"), _run_state.dungeon_event_runtime.get("consequence_runtime", {}).get("participant_snapshots", {}).get("health", {}), "Vera saves Event participant health and resource mirror together")
		suite.assert_true(_service.payload().reward_effect_state == _player.reward_effect_snapshot(), "full existing Player reward state is saved with narrative facts")
		suite.assert_true(_service.payload().active_run_state == _run_state.snapshot(), "the same primary retains the complete resulting active Run")
		_fault = &""
		var stale := Service.new()
		suite.assert_true(stale.configure(catalog, save, "slot_narrative", "base").ok and stale.enable_narrative(entries, sources).ok and stale.bind_narrative_run(_run_state, _player).ok, "stale restore regression starts from the actual physical primary")
		var next_occurrence: Dictionary = _service.install_narrative_occurrence("choice", "choice_vera_2", room.node, room.template, "room_exit", runtime_parent)
		suite.assert_true(next_occurrence.ok, "second authored Vera choice has a distinct physical occurrence")
		if next_occurrence.ok:
			var next_token: Area2D = next_occurrence.context.occurrence
			await get_tree().physics_frame
			await get_tree().physics_frame
			var next_choice := {"command_id": "vera-second", "kind": "narrative_choice", "definition_id": "choice_vera_2", "choice_id": "listen"}
			var capacity_before: float = _player.health.max_hp
			_drift_on_promote = true
			var pending: Dictionary = _service.execute_narrative(next_choice, _service.snapshot().revision, next_token)
			_drift_on_promote = false
			suite.assert_equal(pending.code, &"NATIVE_PUBLICATION_PENDING", "committed narrative with native drift exposes its explicit recovery state")
			suite.assert_equal(_player.health.max_hp, capacity_before, "native drift cannot partially publish the saved capacity")
			suite.assert_equal(_service.execute_narrative({"command_id": "pending-credit", "kind": "narrative_credits"}, _service.snapshot().revision).code, &"NATIVE_PUBLICATION_PENDING", "durable native drift requires recovery before another narrative command")
			var pending_profile: Dictionary = _service.snapshot()
			suite.assert_true(_service.restore_narrative_run().ok, "pending native publication restores the authoritative physical primary")
			suite.assert_equal(_player.health.max_hp, capacity_before - 5.0, "pending recovery applies exactly the already-saved second cost")
			suite.assert_equal(_service.snapshot(), pending_profile, "native recovery does not create another profile command")
			var restored_player: Dictionary = _player.reward_effect_snapshot()
			var restored_run: Dictionary = _run_state.snapshot()
			suite.assert_true(not stale.restore_narrative_run().ok, "older service cannot restore an obsolete primary after a newer narrative commit")
			suite.assert_true(_player.reward_effect_snapshot() == restored_player and _run_state.snapshot() == restored_run, "stale native restoration leaves every live participant unchanged")
			suite.assert_true(not _service.execute_narrative(next_choice, _service.snapshot().revision, next_token).ok, "pending recovery cannot duplicate the committed choice")
		var restarted := Service.new()
		suite.assert_true(restarted.configure(catalog, save, "slot_narrative", "base").ok and restarted.enable_narrative(entries, sources).ok, "new service reloads Vera Profile and full native state from physical JSON")
		suite.assert_true(restarted.bind_narrative_run(_run_state, _player).ok, "reloaded service binds the same native run")
		var restored: Dictionary = restarted.restore_narrative_run()
		suite.assert_true(restored.ok, "durable native narrative state has a verified restoration path: " + str(restored.code))
		suite.assert_equal(restarted.snapshot(), _service.snapshot(), "physical restart preserves exact source consumption and affinity")
	_complete_floor(launched.context.launch)
	_run_state.phase = Phase.Value.VICTORY
	_run_state.result = {"result": "victory"}
	_run_state.run_time_ms = 1000
	room.node.queue_free()
	room = _room(templates)
	var heart_result: Dictionary = _service.install_narrative_occurrence("collect", "heart_fragment_5", room.node, room.template, "room_exit", runtime_parent)
	suite.assert_true(heart_result.ok, "actual final Boss victory can still install its authored fifth heart fragment")
	if heart_result.ok:
		var heart_token: Area2D = heart_result.context.occurrence
		_player.global_position = heart_token.global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		var heart: Dictionary = _service.execute_narrative({"command_id": "heart-five", "kind": "narrative_collect", "source_receipt_id": "heart_fragment_5"}, _service.snapshot().revision, heart_token)
		suite.assert_true(heart.ok, "real post-victory native contact persists the final authored heart fragment")
	var ending := {"command_id": "native-ending", "kind": "narrative_ending", "ending_id": "shattered_freedom"}
	var terminal_before: Dictionary = _run_state.snapshot()
	_run_state.events.pop_back()
	suite.assert_true(not _service.execute_narrative(ending, _service.snapshot().revision).ok, "victory without the real fifth Boss source cannot expose endings")
	_run_state.events = terminal_before.events
	before = _service.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not _service.execute_narrative(ending, before.revision).ok, "ending write failure preserves an unconsumed terminal choice")
	_fault = &""
	suite.assert_true(_service.execute_narrative(ending, before.revision).ok, "real five-floor terminal sources authorize one durable ending")
	ending.command_id = "renamed-ending"
	suite.assert_true(not _service.execute_narrative(ending, _service.snapshot().revision).ok, "native terminal victory cannot choose twice")
	var receipts: Array = []
	for event: Dictionary in _run_state.events:
		if event.get("type") == Settlement.SOURCE_TYPE:
			receipts.append(event.receipt)
	suite.assert_true(_service.settle_terminal(_run_state.snapshot(), receipts, _service.snapshot().revision).ok, "authentic five-floor Run settles after its native story choice")
	if _service.has_method("frozen_launch_projection"):
		suite.assert_true(_service.frozen_launch_projection().is_empty() and _service.payload().get("pending_meta_run_projection", {}).is_empty() and _service.pending_launch_config().is_empty() and _service.payload().get("pending_run_config", {}).is_empty(), "terminal settlement retires frozen pending-launch projection and native config together")
	var terminal_restart := Service.new()
	suite.assert_true(terminal_restart.configure(catalog, save, "slot_narrative", "base").ok and terminal_restart.enable_narrative(entries, sources).ok, "settled terminal narrative reloads without a live Player or Run")
	suite.assert_true(terminal_restart.narrative_ending_view().ok, "physical settled terminal still supplies authenticated ending facts")
	suite.assert_true(not terminal_restart.execute_narrative(ending, terminal_restart.snapshot().revision).ok, "settled JSON terminal cannot repeat an already chosen ending")
	var credits := {"command_id": "credits-complete", "kind": "narrative_credits", "ending_id": "shattered_freedom"}
	before = terminal_restart.snapshot()
	_fault = &"before_primary_promote"
	suite.assert_true(not terminal_restart.execute_narrative(credits, before.revision).ok, "credits write failure leaves completion unclaimed")
	suite.assert_equal(terminal_restart.snapshot(), before, "failed credits save preserves the entire settled Profile")
	_fault = &""
	suite.assert_true(terminal_restart.execute_narrative(credits, before.revision).ok, "settled ending credits persist after physical restart")
	credits.command_id = "renamed-credits"
	suite.assert_true(not terminal_restart.execute_narrative(credits, terminal_restart.snapshot().revision).ok, "renamed credits command cannot complete the same ending twice")
	_service.retire_narrative_occurrences()
	_player.queue_free()
	room.node.queue_free()
	runtime_parent.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_player = null
	_service = null
	suite.finish(get_tree())


func _enter_floor(floor: Dictionary, templates: Array) -> void:
	var generated: Dictionary = Generator.new().generate(73, floor, templates)
	suite.assert_true(_run_state.configure_floor_plan(generated.plan, floor, templates).ok, "narrative test uses the actual generated floor")
	for node: Dictionary in generated.plan.nodes:
		if node.id == generated.plan.boss_node_id:
			_run_state.room_total = int(node.layer)
	_run_state.phase = Phase.Value.ROOM_ACTIVE
	if _run_state.dungeon_event_runtime.is_empty():
		_initialize_event_health()
	suite.assert_true(_run_state.commit_meta_floor_entrance(_player.health.current_hp, _player.health.max_hp, _player.health.current_hp), "native Meta entry records this actual floor once before route progression")
	for edge: Dictionary in _run_state.floor_plan.edges:
		if edge.source_node_id == _run_state.floor_plan.current_node_id and not edge.locked:
			suite.assert_true(_run_state.select_floor_edge(StringName(edge.id)).ok, "native route visits an actual authored room")
			break
	var node_type: String = _run_state.current_floor_node().room_type
	_run_state.phase = Phase.Value.COMBAT_ACTIVE if node_type in ["combat", "elite"] else (Phase.Value.BOSS_ACTIVE if node_type == "boss" else Phase.Value.ROOM_ACTIVE)


func _room(templates: Array) -> Dictionary:
	var node: Dictionary = _run_state.current_floor_node()
	for template: Dictionary in templates:
		if template.id != node.template_id:
			continue
		var room: Node2D = load(template.scene_path).instantiate()
		add_child(room)
		var presentation: Dictionary = room.FLOOR_PRESENTATION[_run_state.floor_plan.floor_id]
		suite.assert_true(room.bind_room(node, template, {"floor_id": _run_state.floor_plan.floor_id, "palette_id": presentation.palette_id, "environment_rule_id": presentation.environment_rule_id, "room_seed": 73}).ok and room.activate_room().ok, "source belongs to an actually bound active room scene")
		return {"node": room, "template": template}
	return {}


func _complete_floor(launch: Dictionary) -> void:
	for _step: int in range(16):
		var node: Dictionary = _run_state.current_floor_node()
		if not node.cleared:
			if node.room_type == "event":
				_resolve_native_event(node)
			suite.assert_true(_run_state.complete_current_floor_node(node.id).ok, "authentic route records the room completion fact")
		if node.id == _run_state.floor_plan.boss_node_id:
			suite.assert_true(_run_state.append_completed_floor(), "authentic route records the canonical completed floor")
			var source := {"schema_id": Settlement.SOURCE_TYPE, "run_id": launch.run_id, "launch_sequence": int(launch.sequence), "floor_id": _run_state.floor_plan.floor_id, "node_id": node.id, "kind": "boss", "payload": {"actor_role": "principal", "boss_id": Settlement.BOSS_ORDER[_run_state.current_floor_index]}}
			source["source_id"] = Settlement.source_id(source, source.payload.boss_id)
			_run_state.events.append({"type": Settlement.SOURCE_TYPE, "receipt": source})
			return
		for edge: Dictionary in _run_state.floor_plan.edges:
			if edge.source_node_id == node.id and not edge.locked:
				_run_state.select_floor_edge(StringName(edge.id))
				break
		var active: String = _run_state.current_floor_node().room_type
		_run_state.phase = Phase.Value.COMBAT_ACTIVE if active in ["combat", "elite"] else (Phase.Value.BOSS_ACTIVE if active == "boss" else Phase.Value.ROOM_ACTIVE)


func _inject_fault(point: StringName) -> bool:
	if point == &"before_primary_promote" and _service != null:
		_at_promotion = {"profile": _service.snapshot(), "player": _player.reward_effect_snapshot() if is_instance_valid(_player) else {}, "run": _run_state.snapshot() if _run_state != null else {}}
		_reentrant = _service.execute_narrative({"command_id": "reentrant", "kind": "narrative_credits"}, _service.snapshot().revision)
		if _drift_on_promote and is_instance_valid(_player):
			_player.health.current_hp -= 1.0
	return point == _fault


func _initialize_event_health(restore: bool = false) -> void:
	var resource := EventResources.new()
	var health := EventHealth.new()
	var economy := Economy.new()
	var modifier := EventModifiers.new()
	var route := EventRoute.new()
	var state := EventState.new()
	suite.assert_true(resource.configure({"time_shard": 0, "forge_essence": 0}) and health.configure(_player.health.current_hp, _player.health.max_hp), "actual Event authorities derive current native Player health")
	suite.assert_true(economy.configure(_content("economy_profiles.json")[0], 10).ok and economy.restore_snapshot(_run_state.run_economy), "Event consequence economy matches the actual native Run")
	var definitions: Array = Envelope._launch_event_definitions()
	var fingerprint: String = Envelope._event_runtime_digest({"events": definitions})
	suite.assert_true(modifier.configure([], {}, []) and route.configure(_run_state.floor_plan) and state.configure(fingerprint).ok, "actual Event participants configure from the generated route and authored content fingerprint")
	var consequences := EventConsequences.new()
	suite.assert_true(consequences.configure(resource, health, economy, modifier, route, state), "complete native Event consequence runtime configures")
	var runtime := EventRuntime.new()
	var publication_secret: String = Envelope._event_runtime_digest({"schema": "event_publication_secret_v1", "content_fingerprint": fingerprint, "run_id": _run_state.run_id, "run_seed": _run_state.run_seed})
	suite.assert_true(runtime.configure(definitions, EventSelector.new(), state, EventRequirements.new(), consequences, Callable(self, "_event_context"), Callable(self, "_event_sink"), Callable(self, "_event_fact_sink"), publication_secret), "all actual authored dungeon events configure for native narrative health")
	if restore:
		suite.assert_true(runtime.restore_snapshot(_run_state.dungeon_event_runtime), "actual Event runtime restores current native Run participants before choosing")
	else:
		suite.assert_true(_run_state.initialize_launch_event_state(runtime.snapshot()), "actual native Run accepts the complete Event runtime and frozen Meta projection")
	_event_runtime = runtime


func _event_context() -> Dictionary:
	var participants: Dictionary = _event_runtime.snapshot().consequence_runtime.participant_snapshots
	var health := {"current": float(participants.health.current), "maximum": float(participants.health.maximum)}
	var resource: Dictionary = participants.resource.resources
	var modifier: Dictionary = participants.modifier
	return {"global_revision": _run_state.revision, "requirements": {"resources": resource, "health": health, "gold": int(participants.economy.balance), "reward_tags": [], "curse_ids": modifier.curse_ids, "narrative_flags": modifier.narrative_flags, "floor_index": _run_state.current_floor_index}, "selection": {"run_seed": _run_state.run_seed, "floor_index": _run_state.current_floor_index, "availability": "LAUNCH", "health": health, "economy": {"gold": int(participants.economy.balance)}, "build": {"curse_ids": modifier.curse_ids}, "resources": resource, "flags": modifier.narrative_flags, "meta": {"perfect_rewind_available": true, "old_reunion_eligible": false}}}


func _event_sink(command: Dictionary, expected_revision: int) -> Dictionary:
	if expected_revision != _run_state.revision:
		return {"ok": false, "code": &"STALE_REVISION", "new_revision": _run_state.revision}
	var runtime: Dictionary = _event_runtime.snapshot()
	for field: String in ["emitted_fact_ids", "pending_facts", "encounter_success_by_transaction", "publication_ledger", "publication_digest"]:
		runtime[field] = command.publication_state[field].duplicate(true) if command.publication_state[field] is Array or command.publication_state[field] is Dictionary else command.publication_state[field]
	var participants: Dictionary = runtime.consequence_runtime.participant_snapshots
	participants.event_state = command.event_state.duplicate(true)
	var resources: Dictionary = _run_state.resources.duplicate(true)
	resources.resource = participants.resource
	resources.health = participants.health
	var candidate := {"dungeon_event_runtime": runtime, "run_economy": participants.economy, "floor_plan": participants.route.plan, "resources": resources, "build": _run_state.build_state.transaction_snapshot()}
	if not _run_state.commit_event_transaction_state(candidate):
		return {"ok": false, "code": &"EVENT_NATIVE_STATE_INVALID", "new_revision": _run_state.revision}
	_run_state.advance_revision()
	return {"ok": true, "code": &"OK", "new_revision": _run_state.revision}


func _event_fact_sink(_fact_id: String, _payload: Dictionary) -> bool:
	return true


func _resolve_native_event(node: Dictionary) -> void:
	_run_state.phase = Phase.Value.ROOM_ACTIVE
	_initialize_event_health(true)
	var opened: Dictionary = _event_runtime.open_event({"floor_id": _run_state.floor_plan.floor_id, "floor_index": _run_state.current_floor_index, "node_id": node.id, "primary_event_id": node.event_id}, {})
	suite.assert_true(opened.ok, "actual authored Event opens on the native route: " + str(opened.code))
	if not opened.ok:
		return
	var chosen: Dictionary = _event_runtime.choose_option(&"decline", _run_state.revision)
	suite.assert_true(chosen.ok, "actual authored Event decline resolves before native room completion: " + str(chosen.code))
	if chosen.ok:
		suite.assert_true(_event_runtime.dismiss_result(_run_state.revision).ok, "actual Event result retires before the route advances")


func _content(name: String) -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/" + name))
