extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Route := preload("res://tests/support/native_launch_route_fixture.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")
const FailureProbe := preload("res://tests/support/native_frame_failure_probe.gd")
const SURVIVAL_SOURCE := &"p15_full_run_survival_fixture"
const MAX_ROOM_FRAMES := 18000

var suite: RefCounted
var main: Node
var host: Node
var player: Node2D
var controller: Node
var service: RefCounted
var report := {"schema_version": 1, "report_kind": "actual_native_five_floor_combat", "synthetic": false, "human_playtests": 0, "unassisted_victory": false, "survival_fixture": str(SURVIVAL_SOURCE), "content_snapshot": {}, "seed": 4, "rooms": [], "bosses": [], "frames": 0, "complete": false, "failures": []}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var registry := Registry.new()
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not loaded.has_blocking_errors(), "full native run loads the actual Base content authority")
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var save := Save.new()
	report.content_snapshot = Content.snapshot(registry)
	suite.assert_true(save.configure(GameState.save_path.get_base_dir().path_join("plane_walker/save"), "0.4.0-dev", report.content_snapshot).ok and save.enable_meta_profile(catalog).ok, "full native run owns production physical Profile storage")
	suite.assert_true(save.save_profile("slot_1", "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "full native run persists the explicit unlocked Profile fixture before Main activation")
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	host = main.get_node("RunRuntimeHost")
	controller = main.get_node("CombatRoom01")
	controller.visible = true
	controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	player = controller.get_node("Player")
	service = GameState.profile_runtime_service()
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "accelerate"], "difficulty": "normal", "seed": int(report.seed)}
	var started: bool = main._launch_run(config, false, true)
	suite.assert_true(started, "Main's production entry starts the actual five-floor native run: " + str(main.get("_last_launch_rejection")))
	Route.freeze(main)
	var old_ticks := Engine.physics_ticks_per_second
	var old_scale := Engine.time_scale
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	if started:
		await _walk_run()
	Engine.physics_ticks_per_second = old_ticks
	Engine.time_scale = old_scale
	var state: Dictionary = host.runtime_snapshot()
	report.complete = int(state.phase) == Phase.Value.VICTORY and report.bosses == Settlement.BOSS_ORDER and report.failures.is_empty()
	suite.assert_true(report.complete, "actual accepted native combat reaches five Boss receipts and production victory: " + str(report.failures))
	if report.complete:
		await _finish_victory(catalog, save)
		report.complete = report.failures.is_empty() and report.get("settlement", {}).get("terminal_reason") == "victory" and report.get("physical_settlement_verified", false)
	suite.assert_true(report.complete, "actual Main victory, ending, credits and physical Profile reload all complete: " + str(report.failures))
	var output := "res://build/p15-five-floor-native-run.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	suite.assert_true(file != null, "full native run retains its actual versioned report")
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	player.cancel_transient_actions()
	await _dispose_main()
	suite.finish(get_tree())


func _walk_run() -> void:
	for _step: int in range(180):
		var state: Dictionary = host.runtime_snapshot()
		if int(state.phase) == Phase.Value.VICTORY:
			return
		var node: Dictionary = host.native_run_state().current_floor_node()
		var result: Variant
		if not state.open_offer.is_empty():
			var offer: Dictionary = state.open_offer
			host._on_option_chosen(str(offer.offer_id), str(offer.options[0].option_id), int(offer.revision))
			result = {"ok": int(host.runtime_snapshot().revision) > int(state.revision), "code": "reward"}
		elif int(state.phase) == Phase.Value.RUN_PREPARING:
			result = host.start_next_floor(int(state.revision))
		elif node.id == state.floor_plan.entry_node_id or node.cleared:
			var choices: Array = host.route_choices()
			if choices.is_empty():
				report.failures.append("no actual route choices at " + str(node.id))
				return
			var selected: Dictionary = choices[0]
			for choice: Dictionary in choices:
				if choice.room_type in ["combat", "elite", "boss"]:
					selected = choice
					break
			result = host.select_route(StringName(selected.edge_id), int(state.revision))
		else:
			match str(node.room_type):
				"combat", "elite", "boss":
					if not await _fight_room(state, node):
						return
					result = {"ok": true, "code": "actual_native_defeat"}
				"shop": result = host.leave_merchant(int(state.revision))
				"event":
					result = host.choose_event_option(&"decline", int(state.revision)) if host.dungeon_ui_context().event.phase == "open" else host.dismiss_event(int(state.revision))
				"treasure", "rest": result = host.resolve_room_interaction(&"leave", int(state.revision))
				_:
					report.failures.append("unsupported actual room " + str(node.room_type))
					return
		if not result.ok:
			report.failures.append("actual route refused at%s:%s" % [node.id, result.get("code")])
			return
		main.get_node("DungeonFlow").refresh(true)
		Route.freeze(main)
		await get_tree().process_frame
		main.get_node("NarrativeFlow").close()
	report.failures.append("full native route exceeded180 transitions")


func _fight_room(run: Dictionary, node: Dictionary) -> bool:
	var runner: Node = controller.encounter_runner()
	var driver: Node = runner.get_node("NativeLaunchEncounterDriver")
	var row := {"floor_index": int(run.current_floor_index), "node_id": str(node.id), "room_type": str(node.room_type), "frames": 0, "definitions": {}, "damage_count": 0, "body_loss": 0.0, "terminal_receipts": [], "boss_id": ""}
	var expected_boss: String = Settlement.BOSS_ORDER[int(run.current_floor_index)] if node.room_type == "boss" else ""
	var record_damage := func(info: RefCounted, target: Node, amount: float) -> void:
		if info.attacker == player and amount > 0.0 and target is LaunchHostileActor:
			row.damage_count += 1
			var observed: Dictionary = target.health.published_damage_observation_context(info)
			row.body_loss += maxf(0.0, float(observed.get("hp_before", amount)) - float(observed.get("hp_after", 0.0)))
	EventBus.hit_confirmed.connect(record_damage)
	host.set_dungeon_selection_safety(false)
	player.health.acquire_invulnerability_source(SURVIVAL_SOURCE)
	var press_frame := -1
	var released := true
	var last_damage_frame := 0
	var last_damage_count := 0
	var last_position := player.global_position
	var stuck_frames := 0
	var turn_direction := 1.0
	var time_cast := false
	for frame: int in range(1, MAX_ROOM_FRAMES + 1):
		var actors: Dictionary = driver.get("_actors")
		var candidates: Array[Node2D] = []
		for actor: Node2D in actors.values():
			if not is_instance_valid(actor) or actor.health.dead:
				continue
			var definition: Dictionary = actor.get("_launch_definition")
			row.definitions[definition.id] = true
			if definition.actor_kind == "boss":
				row.boss_id = str(definition.id)
				if definition.id != expected_boss:
					report.failures.append("actual Boss fallback or wrong floor identity: " + str(definition.id))
					break
			if not actor.has_meta("p15_full_run_death_bound"):
				actor.set_meta("p15_full_run_death_bound", true)
				actor.hostile_final_death.connect(func(source: StringName, receipt: String): row.terminal_receipts.append({"source_id": str(source), "receipt": receipt}))
			var sigil := actor.get_node_or_null("DormantSigil") as Node2D
			candidates.append(sigil if sigil != null and sigil.visible else actor)
		for actor: Node2D in driver.get("_effects").native_summon_actors().values():
			if is_instance_valid(actor) and not actor.health.dead:
				candidates.append(actor)
		candidates.sort_custom(func(a: Node2D, b: Node2D): return player.global_position.distance_squared_to(a.global_position) < player.global_position.distance_squared_to(b.global_position))
		var aim := Vector2.RIGHT
		var movement := Vector2.ZERO
		if not candidates.is_empty():
			var target: Node2D = candidates[0]
			aim = player.global_position.direction_to(target.global_position)
			var distance := player.global_position.distance_to(target.global_position)
			movement = aim if distance > 44.0 else -aim if distance < 34.0 else Vector2.ZERO
			if stuck_frames >= 20 and distance > 52.0:
				movement = aim.rotated(turn_direction * PI * 0.5)
			if player.weapon_action_coordinator.phase_name() == &"READY" and player.action_state.current_state == 0:
				if not time_cast and frame > 60:
					time_cast = true
					player.try_action(&"time_accelerate")
				elif player.try_action(&"weapon_primary"):
					press_frame = frame
					released = false
		if not released and frame - press_frame >= 40:
			player.call("_submit_weapon_intent", &"weapon_primary", &"released")
			released = true
		if not player.advance_action_frame({"aim": aim, "movement": movement}):
			_diagnose_refusal(driver, {"aim": aim, "movement": movement})
			report.failures.append("actual native frame refused in%s:%d" % [node.id, frame])
			break
		row.frames = frame
		report.frames += 1
		host._process(1.0 / 60.0)
		await get_tree().physics_frame
		if not Rect2(0, 0, 640, 360).grow(-12.0).has_point(player.global_position):
			report.failures.append("actual Player escaped production physical room boundary at " + str(player.global_position))
			break
		if player.global_position.distance_squared_to(last_position) < 0.01 and movement.length_squared() > 0.1:
			stuck_frames += 1
		else:
			stuck_frames = 0
		if stuck_frames == 80:
			turn_direction *= -1.0
			stuck_frames = 20
		last_position = player.global_position
		if row.damage_count > last_damage_count:
			last_damage_count = row.damage_count
			last_damage_frame = frame
		if frame % 500 == 0:
			print("P15_FULL_NATIVE_ROOM ", run.current_floor_index, " ", node.id, " frame=", frame, " damage=", row.damage_count, " actors=", actors.size())
		var current: Dictionary = host.native_run_state().current_floor_node()
		if current.cleared:
			if row.damage_count == 0 or row.terminal_receipts.is_empty():
				report.failures.append("room advanced without actual physical damage and final death: " + str(node.id))
			if not expected_boss.is_empty():
				if row.boss_id != expected_boss or row.terminal_receipts.size() != 1:
					report.failures.append("actual Boss final receipt mismatch: " + expected_boss)
				else:
					report.bosses.append(row.boss_id)
			report.rooms.append(row)
			EventBus.hit_confirmed.disconnect(record_damage)
			player.cancel_transient_actions()
			return report.failures.is_empty()
		if frame - last_damage_frame > 2400 and not candidates.is_empty():
			report.failures.append("actual ordinary input made no progress in " + str(node.id))
			break
	report.rooms.append(row)
	EventBus.hit_confirmed.disconnect(record_damage)
	player.cancel_transient_actions()
	if report.failures.is_empty():
		report.failures.append("actual room exceeded frame bound " + str(node.id))
	return false


func _finish_victory(catalog: RefCounted, save: RefCounted) -> void:
	var flow: Node = main.get_node("NarrativeFlow")
	var occurrences: Array = flow.get("_occurrences")
	if occurrences.size() != 1 or not is_instance_valid(occurrences[0].token.get_ref()):
		report.failures.append("authentic victory did not issue its native final heart fragment")
		return
	var heart: Area2D = occurrences[0].token.get_ref()
	for _frame: int in range(300):
		if not is_instance_valid(heart) or flow.panel().visible:
			break
		var direction := player.global_position.direction_to(heart.global_position)
		Input.action_press("move_right", maxf(0.0, direction.x))
		Input.action_press("move_left", maxf(0.0, -direction.x))
		Input.action_press("move_down", maxf(0.0, direction.y))
		Input.action_press("move_up", maxf(0.0, -direction.y))
		flow._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
	for action: String in ["move_right", "move_left", "move_down", "move_up"]:
		Input.action_release(action)
	if not service.snapshot().narrative_state.heart_fragments.has("floor_throne_of_void"):
		report.failures.append("ordinary native terminal traversal did not collect the actual final fragment")
		return
	if not _narrative_action(flow, "continue"):
		return
	var ending := ""
	for control: Control in flow.panel().action_controls():
		var id := str(control.get_meta("action_id", ""))
		if id.begins_with("ending:") and not (control as Button).disabled:
			ending = id.trim_prefix("ending:")
			break
	if ending.is_empty() or not _narrative_action(flow, "ending:" + ending):
		report.failures.append("authentic terminal has no available saved ending")
		return
	var profile: Dictionary = service.snapshot()
	if profile.statistics.victories != 1 or profile.statistics.finished_runs != 1 or not profile.active_launch_receipt.is_empty() or not service.verified_settled_run().ok:
		report.failures.append("real victory did not persist exactly one authenticated settlement")
		return
	report["ending_id"] = ending
	report["settlement"] = profile.last_settlement_receipt.duplicate(true)
	if not _narrative_action(flow, "credits:" + ending) or not main.get_node("HubFlowCoordinator").is_hub_visible():
		report.failures.append("saved credits did not return the actual Main to Hub")
		return
	var reloaded := Service.new()
	var fresh: Dictionary = reloaded.configure(catalog, save, "slot_1", "base")
	if not fresh.ok or reloaded.snapshot() != service.snapshot() or not reloaded.verified_settled_run().ok or not reloaded.snapshot().narrative_state.credits_completed.has(ending):
		report.failures.append("fresh physical Profile does not retain authenticated victory and selected credits")
		return
	report["physical_settlement_verified"] = true


func _narrative_action(flow: Node, id: String) -> bool:
	for control: Control in flow.panel().action_controls():
		if str(control.get_meta("action_id", "")) == id and control is Button and not control.disabled:
			control.pressed.emit()
			return true
	report.failures.append("native narrative control unavailable: " + id)
	return false


func _dispose_main() -> void:
	var playback_refs: Array[WeakRef] = []
	for deck: Node in main.get_node("MusicDirector").get_children():
		if deck is AudioStreamPlayer and deck.playing and deck.get_stream_playback() != null:
			playback_refs.append(weakref(deck.get_stream_playback()))
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for _step: int in range(20):
		if playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null):
			break
		await get_tree().create_timer(0.01).timeout
	suite.assert_true(playback_refs.all(func(reference: WeakRef): return reference.get_ref() == null), "full actual Main run releases independent music playback before process exit")


func _diagnose_refusal(driver: Node, intents: Dictionary) -> void:
	var before := {"intents_valid": not player._validated_frame_intents(intents).is_empty(), "preflight": player._fixed_frame_preflight(), "transaction_available": not player._fixed_frame_transaction_snapshot().is_empty(), "player_frame": player.get("_runtime_frame"), "time_frame": player.time_manager.replay_snapshot().runtime_frame, "weapon_frame": player.weapon_action_coordinator.snapshot().frame, "action_frame": player.action_state.snapshot().frame, "character_frame": player.character_action_coordinator.snapshot().last_runtime_frame, "world_frame": player.world_payload_authority.replay_snapshot().last_runtime_frame, "rewind_frame": player.rewind_recorder.get("_last_runtime_frame"), "rewind_transaction": player.rewind_recorder.get("_active_transaction"), "time_ticket": player.get("_active_time_frame_signal_ticket"), "health_ticket": player.get("_active_health_frame_signal_ticket"), "world_ticket": player.get("_active_world_frame_ticket")}
	var diagnostic: Dictionary = FailureProbe.inspect(player, driver.get("_actors"), driver.get("_effects"), controller.hostile_threat_registry())
	diagnostic["player_preflight"] = before
	var bridge: RefCounted = player.get("_hostile_frame_participant")
	diagnostic["bridge"] = bridge.frame_rejection_snapshot()
	diagnostic["bridge_readiness"] = {"last_frame": bridge.get("_last_runtime_frame"), "active": not bridge.get("_active").is_empty(), "detached": not bridge.get("_detached").is_empty(), "publishing": bridge.get("_publishing"), "encounter_ready": bridge.get("_encounter_authority").is_ready_for_frame(int(player.get("_runtime_frame")) + 1), "summons": {}}
	for source: String in driver.get("_effects").native_summon_actors():
		var child: Node2D = driver.get("_effects").native_summon_actors()[source]
		diagnostic.bridge_readiness.summons[source] = {"frame": child.launch_runtime_snapshot().runtime.runtime_frame, "terminal": child.launch_runtime_snapshot().runtime.terminal, "queued": child.is_queued_for_deletion(), "run_id": child.launch_runtime_snapshot().runtime.identity.run_id, "bridge_same": bridge.get("_actors").get(source) == child}
	for source: String in bridge.get("_actors"):
		var actor: Variant = bridge.get("_actors")[source]
		diagnostic.bridge_readiness[source] = {"valid": is_instance_valid(actor)}
		if is_instance_valid(actor):
			diagnostic.bridge_readiness[source]["frame"] = actor.launch_runtime_snapshot().runtime.runtime_frame
			diagnostic.bridge_readiness[source]["terminal"] = actor.launch_runtime_snapshot().runtime.terminal
	report["native_refusal"] = diagnostic
	print("P15_FULL_NATIVE_REJECTION ", diagnostic)
