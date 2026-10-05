extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Route := preload("res://tests/support/native_launch_route_fixture.gd")
const Checkpoint := preload("res://scripts/save/native_run_checkpoint_authority.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	for case_name: String in ["warning", "fighting", "actor_warning", "payload", "payload_zone", "burn", "semantic_zone", "summon", "orphan_summon", "boss", "boss_cover", "boss_legacy_arena", "boss_aftershock_dormant", "boss_aftershock_warning", "elite", "elite_legacy_affixes", "event", "native_drift", "presentation_drift"]:
		var selected := OS.get_environment("PLANEWALKER_CHECKPOINT_CASE")
		if not selected.is_empty() and selected != case_name:
			continue
		await _exercise(suite, case_name)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _exercise(suite: RefCounted, case_name: String) -> void:
	var boss_case := case_name.begins_with("boss")
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	var host: Node = main.get_node("RunRuntimeHost")
	var controller: Node = main.get_node("CombatRoom01")
	controller.visible = true
	controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	var player: Node = controller.get_node("Player")
	var runner: Node = controller.encounter_runner()
	var catalog: RefCounted = Factory.load_base().context.catalog
	var save := Save.new()
	var service := Service.new()
	var slot := "native_combat_" + ("elite_legacy" if case_name == "elite_legacy_affixes" else case_name)
	if slot.length() > 32:
		slot = "native_" + case_name
	suite.assert_true(save.configure(Paths.resolve_default("user://p16r-checkpoint", "p16r-checkpoint"), "0.4.0-dev", Content.snapshot(host.content_registry())).ok, "native combat checkpoint uses actual activated content and physical SaveService")
	suite.assert_true(service.configure(catalog, save, slot, "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "native combat checkpoint configures an authenticated physical Profile")
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	if case_name == "event":
		config.seed = 6
	suite.assert_true(host.start_profile_run(config, service, int(service.snapshot().revision)).ok, "actual Host accepts the seeded native combat launch")
	var selected: bool = await _route_to_native_target(suite, host, false, "void_hunter", true) if case_name == "orphan_summon" else await _route_to_native_target(suite, host, false, "forest_caller") if case_name == "summon" else await _route_to_elite(host) if case_name.begins_with("elite") else await _route_to_native_target(suite, host, boss_case) if boss_case or case_name == "semantic_zone" else await _route_to_encounter(suite, host, case_name == "event")
	suite.assert_true(selected, "actual Host routes to the authored encounter for " + case_name)
	if not selected:
		await _dispose(main)
		return
	host.set_dungeon_selection_safety(false)
	player.health.acquire_invulnerability_source(&"cold_checkpoint_fixture")
	var publication_refusal := {}
	if case_name == "warning":
		runner.spawn_warning_requested.connect(func(_spawn: Dictionary, _duration: float) -> void:
			var before_payload: Dictionary = service.payload()
			var refused: Variant = host.checkpoint_profile_run(int(service.snapshot().revision))
			publication_refusal["safe"] = not refused.ok and refused.code == &"CHECKPOINT_UNSAFE" and service.payload() == before_payload
		, CONNECT_ONE_SHOT)
	var ready := false
	var requested_summon := false
	var summon_owner := ""
	for _frame: int in range(600):
		if case_name in ["summon", "orphan_summon"] and not requested_summon:
			for actor: Node2D in controller.get_node("Enemies").get_children():
				var definition: Dictionary = actor.get("_launch_definition")
				if definition.id != ("forest_caller" if case_name == "summon" else "void_hunter") or case_name == "orphan_summon" and definition.actor_kind != "elite":
					continue
				actor.cancel_active_attack()
				player.global_position = actor.global_position + Vector2(80, 40)
				var frame: int = actor.get("_launch_runtime").snapshot().runtime_frame
				var delta := actor.global_position.direction_to(player.global_position)
				var request: Dictionary = actor.get("_launch_runtime").request_action("forest_caller.void_call" if case_name == "summon" else "void_hunter.hunter_echo", {"runtime_frame": frame, "source_position": {"x": actor.global_position.x, "y": actor.global_position.y}, "target_position": {"x": player.global_position.x, "y": player.global_position.y}, "facing_direction": {"x": delta.x, "y": delta.y}, "target_id": "player:1"})
				requested_summon = request.ok
				summon_owner = str(actor.hostile_source_id)
				for fact: Dictionary in request.get("threat_facts", []):
					controller.hostile_threat_registry().register_fact(Actions.native_threat_fact(fact))
				actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
				break
		if case_name == "semantic_zone":
			for actor: Node in controller.get_node("Enemies").get_children():
				if actor.get("_launch_definition").id == "chrono_guard":
					player.global_position = actor.global_position + Vector2(32.0, 0.0)
		if not player.advance_action_frame():
			break
		var native: Dictionary = runner.native_launch_snapshot()
		if native.is_empty():
			break
		if case_name in ["summon", "orphan_summon"]:
			ready = requested_summon and not native.summon_actors.is_empty() and native.summon_actors.values().all(func(state: Dictionary): return state.runtime.runtime_frame == player.priority_arbitration_snapshot().frame)
		elif case_name == "warning":
			ready = native.encounter.status == "WARNING"
		elif case_name.begins_with("boss_aftershock"):
			for zone: Dictionary in native.effects.payloads.zones:
				ready = ready or zone.definition.kind == "boss_aftershock" and zone.phase == ("DORMANT" if case_name.ends_with("dormant") else "WARNING")
		elif case_name == "actor_warning" or boss_case:
			for state: Dictionary in native.actors.values():
				ready = ready or state.runtime.action.phase == ("RECOVERY" if boss_case else "WARNING")
		elif case_name == "semantic_zone":
			for zone: Dictionary in native.effects.semantics.zones:
				player.global_position = Vector2(float(zone.geometry.origin.x), float(zone.geometry.origin.y))
				ready = ready or zone.phase == "ACTIVE" and not native.effects.semantics.statuses.is_empty()
		elif case_name == "payload_zone":
			ready = not native.effects.payloads.zones.is_empty()
		elif case_name != "payload":
			ready = native.encounter.status == "FIGHTING" and native.actors.size() > 0
		else:
			ready = not native.effects.payloads.projectiles.is_empty()
		if ready:
			break
		await get_tree().physics_frame
	suite.assert_true(ready, "actual accepted Player frames reach native checkpoint state " + case_name)
	if not ready:
		await _dispose(main)
		return
	if case_name == "orphan_summon":
		var driver: Node = runner.get_node("NativeLaunchEncounterDriver")
		var owner: Node2D = driver.get("_actors").get(summon_owner)
		var hit := Damage.from_plan({"run_id": str(player.current_run_id()), "target_id": summon_owner, "hostile_source_id": "player:sword", "attack_generation": 501, "action_token": 501, "amount": 100000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})
		suite.assert_true(is_instance_valid(owner) and owner.get_node("Hurtbox").receive_hit(hit) > 0.0 and not driver.get("_actors").has(summon_owner), "actual authored echo retains its lifetime after authenticated ordinary principal death")
		suite.assert_true(player.advance_action_frame() and not runner.native_launch_snapshot().summon_actors.is_empty(), "surviving native echo continues after principal retirement")
		await get_tree().physics_frame
	if case_name.begins_with("elite"):
		var driver: Node = runner.get_node("NativeLaunchEncounterDriver")
		var elite_seen := false
		var current: Dictionary = driver.cold_snapshot()
		for source: String in current.actors:
			var saved: Dictionary = current.actors[source]
			var spawn: Dictionary = driver._cold_spawn(current.definition, str(current.encounter.roster[source].spawn_id))
			if not spawn.elite:
				continue
			elite_seen = true
			var actor: Node = driver.get("_actors")[source]
			suite.assert_equal(actor.launch_affix_snapshot().get("ids", []), spawn.affix_ids, "actual production elite configures its canonical authored affixes")
			var downgraded: Dictionary = saved.duplicate(true)
			downgraded.actor.erase("affixes")
			var legacy: Node = driver._instantiate_actor(spawn, saved.identity, actor.global_position, true)
			suite.assert_true(legacy != null, "explicit historical constructor retains the original metadata-only elite")
			if legacy == null:
				continue
			suite.assert_true(not legacy.can_restore_native_cold_snapshot(downgraded, Callable(driver, "_resolve_cold_source")), "stripping new elite configuration cannot downgrade its sealed runtime definition")
			if case_name == "elite_legacy_affixes":
				current.actors[source] = legacy.native_cold_snapshot(Callable(driver, "_cold_source_binding"))
			legacy.free()
		if case_name == "elite_legacy_affixes":
			suite.assert_true(driver.discard_cold_restore() and driver.restore_cold_snapshot(current), "actual Driver reconstructs a closed V1 metadata-only elite without inventing affix effects")
			for source: String in current.actors:
				var spawn: Dictionary = driver._cold_spawn(current.definition, str(current.encounter.roster[source].spawn_id))
				if spawn.elite:
					suite.assert_equal(driver.get("_actors")[source].launch_affix_snapshot(), {}, "restored historical room retains its original elite behavior")
		suite.assert_true(elite_seen, "real elite encounter fixture exercises native affix construction")
	if case_name == "warning":
		suite.assert_true(publication_refusal.get("safe", false), "actual in-flight warning publication refuses capture without changing durable Profile")
	if case_name == "burn":
		var actor: Node = controller.get_node("Enemies").get_child(0)
		suite.assert_true(actor.elemental_status_runtime.apply_status(&"burn", &"cold_player_burn", 1, 90, 1.0, 30, -1.0, player, player), "actual native actor retains a Player-origin burn source")
		for _frame: int in range(29):
			suite.assert_true(player.advance_action_frame(), "native burn advances to its next tick checkpoint")
			await get_tree().physics_frame
	if boss_case:
		var boss: Node = controller.get_node("Enemies").get_child(0)
		if case_name != "boss_aftershock_dormant":
			suite.assert_true(boss.apply_weapon_control_conversion("cold_exposure", 0, 30, 0.0), "actual native Boss retains exposure conversion in its cold checkpoint")
		if case_name == "boss_cover":
			# Damage is an explicit native-collision fixture; route and cold owners are real.
			var cover := boss.get_node("ArenaConstructs/Cover0")
			var hit := Damage.from_plan({"run_id": str(player.current_run_id()), "target_id": "cold_cover", "hostile_source_id": "player:sword", "attack_generation": 17, "action_token": 17, "amount": 80.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player})
			suite.assert_equal(cover.get_node("Hurtbox").receive_hit(hit), 80.0, "actual Host cover fixture destroys its authoritative native pillar")
			suite.assert_true(player.advance_action_frame() and cover.collision_layer == 0, "accepted native Player continuation retains the broken pillar")
	var before: Dictionary = runner.native_launch_snapshot()
	var player_before: Dictionary = player.full_player_replay_snapshot()
	var run_before: Dictionary = host.runtime_snapshot()
	var actor_instances: Dictionary = {}
	for actor: Node in controller.get_node("Enemies").get_children():
		actor_instances[str(actor.hostile_source_id)] = actor.get_instance_id()
	var payload_instances: Array[int] = []
	for node: Node in runner.get_node("NativeLaunchEncounterDriver").get("_effects").native_payload_nodes():
		payload_instances.append(node.get_instance_id())
	var retained: Variant = host.checkpoint_profile_run(int(service.snapshot().revision))
	suite.assert_true(retained.ok, "actual active native " + case_name + " checkpoint persists without retiring combat: " + str(retained.code) + " " + str(retained.context))
	if not retained.ok:
		await _dispose(main)
		return
	var profile_before: Dictionary = service.snapshot()
	var captured := Checkpoint.capture(host)
	suite.assert_true(captured.ok, "active native checkpoint remains valid after physical promotion")
	if case_name == "boss_legacy_arena":
		var historical: Dictionary = Replay.decode_replay_json(captured.context.checkpoint.encounter_codec).replay
		for source: String in historical.actors:
			var runtime: Dictionary = historical.actors[source].actor.runtime
			suite.assert_true(runtime.schema_version == 2 and runtime.arena_state.damage_claims.is_empty(), "actual Ruin checkpoint authenticates current intact native arena before historical encoding")
			runtime.erase("arena_state")
			runtime.schema_version = 1
		var payload: Dictionary = service.payload()
		payload.native_run_checkpoint = _replace_native(captured.context.checkpoint, historical)
		payload = JSON.parse_string(JSON.stringify(payload, "", true, true))
		var historical_save := Save.new()
		historical_save.configure(Paths.resolve_default("user://p16r-checkpoint", "p16r-checkpoint"), "0.4.0-dev", Content.snapshot(host.content_registry()))
		historical_save.enable_meta_profile(catalog)
		var validated := Checkpoint.validate(payload.native_run_checkpoint, payload.active_run_state, payload.reward_effect_state)
		var written: Variant = historical_save.save_profile(slot, "base", payload)
		suite.assert_true(validated.ok and written.ok, "actual physical primary retains an exact pre-arena Ruin runtime version1 checkpoint: " + str(validated.code) + " " + str(written.code) + " " + str(written.metadata))
	if case_name in ["warning", "actor_warning", "payload", "boss"]:
		_tampered_extensions(suite, captured)
	suite.assert_equal(runner.native_launch_snapshot(), before, "checkpoint capture cannot advance or mutate actual native combat")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "checkpoint capture preserves exact accepted Player frame")
	suite.assert_true(player.advance_action_frame(), "uninterrupted native branch accepts its next frame")
	var next_native: Dictionary = runner.native_launch_snapshot()
	var next_player: Dictionary = player.full_player_replay_snapshot()
	await _dispose(main)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	Route.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	host = main.get_node("RunRuntimeHost")
	controller = main.get_node("CombatRoom01")
	player = controller.get_node("Player")
	runner = controller.encounter_runner()
	var reopened := Service.new()
	suite.assert_true(reopened.configure(catalog, save, slot, "base").ok, "new Profile service reads the promoted native combat primary")
	if case_name == "fighting":
		await _reconstruction_failure(suite, host, reopened, save, catalog, slot)
	if case_name == "native_drift":
		host.profile_run_restored.connect(func(_id: String, _run: Dictionary) -> void:
			controller.get_node("Enemies").get_child(0).position += Vector2.ONE
		, CONNECT_ONE_SHOT)
	var restored: Variant = host.restore_profile_checkpoint(reopened, int(reopened.snapshot().revision))
	if case_name == "native_drift":
		suite.assert_true(not restored.ok and restored.code == &"NATIVE_PUBLICATION_PENDING" and player.process_mode == Node.PROCESS_MODE_DISABLED and controller.process_mode == Node.PROCESS_MODE_DISABLED, "restored native actor callback drift freezes both actual combat owners")
		suite.assert_equal(reopened.snapshot(), profile_before, "native callback drift cannot revise the durable Profile")
		await _dispose(main)
		return
	suite.assert_true(restored.ok, "new Main cold-reconstructs active native " + case_name + " encounter: " + str(restored.code) + " " + str(restored.context))
	if not restored.ok:
		await _dispose(main)
		return
	suite.assert_equal(runner.native_launch_snapshot(), before, "cold native aggregate preserves actors, waves, effects and clocks")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "cold native combat preserves exact full Player replay")
	suite.assert_true(_equal_json(host.runtime_snapshot(), run_before), "cold combat preserves original Run and route revision")
	suite.assert_equal(reopened.snapshot(), profile_before, "cold combat cannot mint another launch or revise durable Profile")
	if case_name == "presentation_drift":
		var presented: Variant = host.present_restored_checkpoint(func() -> void: controller.get_node("Enemies").get_child(0).position += Vector2.ONE)
		suite.assert_true(not presented.ok and presented.code == &"NATIVE_PUBLICATION_PENDING" and player.process_mode == Node.PROCESS_MODE_DISABLED and controller.process_mode == Node.PROCESS_MODE_DISABLED, "first presentation authenticates and freezes native actor drift")
		await _dispose(main)
		return
	await get_tree().physics_frame
	# physics_frame emits before the server consumes reconstructed body transforms.
	await get_tree().physics_frame
	for actor: Node in controller.get_node("Enemies").get_children():
		suite.assert_true(actor_instances.has(str(actor.hostile_source_id)) and actor_instances[str(actor.hostile_source_id)] != actor.get_instance_id(), "cold combat reconstructs a new native actor with its original source identity")
	for node: Node in runner.get_node("NativeLaunchEncounterDriver").get("_effects").native_payload_nodes():
		suite.assert_true(not payload_instances.has(node.get_instance_id()), "cold combat reconstructs actual hostile payload nodes")
	suite.assert_true(player.advance_action_frame(), "cold-reconstructed native branch accepts the same next frame")
	suite.assert_equal(runner.native_launch_snapshot(), next_native, "cold native encounter continuation matches uninterrupted accepted-frame branch")
	suite.assert_equal(player.full_player_replay_snapshot(), next_player, "cold native Player continuation matches uninterrupted accepted-frame branch")
	await _settle_reconstructed(suite, host, controller, player, runner, case_name == "event")
	await _dispose(main)


func _route_to_encounter(suite: RefCounted, host: Node, event: bool) -> bool:
	for node_id: String in ["layer_01_a", "layer_02_a", "layer_03_c"] if event else ["layer_01_a"]:
		var selected := false
		for choice: Dictionary in host.route_choices():
			if choice.node_id == node_id:
				selected = host.select_route(StringName(choice.edge_id), int(host.runtime_snapshot().revision)).ok
				break
		if not selected:
			return false
		if not event:
			return true
		if node_id == "layer_03_c":
			suite.assert_equal(host.native_checkpoint_participants().facade.event_view_state().event_id, "event_sleeping_guardian", "cold event fixture selects the authored guardian continuation")
			return host.choose_event_option(&"commit", int(host.runtime_snapshot().revision)).ok
		# Only the prerequisites are fixture clears; the saved ambush remains native.
		if not host.native_checkpoint_participants().runtime.complete_current_room().ok:
			return false
		for _choice: int in range(6):
			var state: Dictionary = host.runtime_snapshot()
			if state.open_offer.is_empty():
				break
			var offer: Dictionary = state.open_offer
			host._on_option_chosen(str(offer.offer_id), str(offer.options[0].option_id), int(offer.revision))
		await get_tree().process_frame
	return false


func _route_to_native_target(suite: RefCounted, host: Node, boss: bool, enemy_id: String = "chrono_guard", require_elite: bool = false) -> bool:
	for _step: int in range(140):
		var state: Dictionary = host.runtime_snapshot()
		var node: Dictionary = host.native_run_state().current_floor_node()
		if boss and node.room_type == "boss":
			return true
		if not boss and node.room_type in ["combat", "elite"]:
			var definition: Dictionary = host.native_checkpoint_participants().facade.current_encounter_definition()
			var waves: Array = definition.get("waves", [])
			if not waves.is_empty():
				for spawn: Dictionary in waves[0].spawns:
					if spawn.enemy_id == enemy_id and (not require_elite or spawn.elite):
						return true
		if not state.open_offer.is_empty():
			var offer: Dictionary = state.open_offer
			host._on_option_chosen(str(offer.offer_id), str(offer.options[0].option_id), int(offer.revision))
		elif int(state.phase) == Phase.Value.RUN_PREPARING:
			if not host.start_next_floor(int(state.revision)).ok:
				return false
		elif node.id == state.floor_plan.entry_node_id or node.cleared:
			var choices: Array = host.route_choices()
			if choices.is_empty():
				return false
			var selected: Dictionary = choices[0]
			for choice: Dictionary in choices:
				if choice.room_type in ["combat", "elite", "boss"]:
					selected = choice
					break
			var routed: Variant = host.select_route(StringName(selected.edge_id), int(state.revision))
			if not routed.ok:
				suite.assert_true(false, "native cold Boss fixture route fails at " + str(node.id) + ": " + str(routed.code))
				return false
		else:
			var result: Variant
			match node.room_type:
				"shop": result = host.leave_merchant(int(state.revision))
				"event": result = host.choose_event_option(&"decline", int(state.revision)) if host.dungeon_ui_context().event.phase == "open" else host.dismiss_event(int(state.revision))
				"treasure", "rest": result = host.resolve_room_interaction(&"leave", int(state.revision))
				_:
					if node.room_type == "boss":
						var launch: Dictionary = host.native_checkpoint_participants().profile.snapshot().active_launch_receipt
						var source := {"schema_id": Settlement.SOURCE_TYPE, "run_id": launch.run_id, "launch_sequence": int(launch.sequence), "floor_id": state.floor_plan.floor_id, "node_id": node.id, "kind": "boss", "payload": {"actor_role": "principal", "boss_id": Settlement.BOSS_ORDER[int(state.current_floor_index)]}}
						source["source_id"] = Settlement.source_id(source, source.payload.boss_id)
						host.native_run_state().events.append({"type": Settlement.SOURCE_TYPE, "receipt": source})
					result = host.native_checkpoint_participants().runtime.complete_current_room()
			if not result.ok:
				suite.assert_true(false, "native cold Boss fixture completion fails at " + str(node.id) + ": " + str(result.code))
				return false
		await get_tree().process_frame
	return false


func _route_to_elite(host: Node) -> bool:
	for _step: int in range(30):
		var state: Dictionary = host.runtime_snapshot()
		var node: Dictionary = host.native_run_state().current_floor_node()
		if node.room_type == "elite":
			return true
		if not state.open_offer.is_empty():
			var offer: Dictionary = state.open_offer
			host._on_option_chosen(str(offer.offer_id), str(offer.options[0].option_id), int(offer.revision))
		elif node.id == state.floor_plan.entry_node_id or node.cleared:
			var choices: Array = host.route_choices()
			if choices.is_empty():
				return false
			var selected: Dictionary = choices[0]
			for choice: Dictionary in choices:
				if choice.room_type == "elite":
					selected = choice
					break
			if not host.select_route(StringName(selected.edge_id), int(state.revision)).ok:
				return false
		else:
			var result: Variant
			match node.room_type:
				"shop": result = host.leave_merchant(int(state.revision))
				"event": result = host.choose_event_option(&"decline", int(state.revision)) if host.dungeon_ui_context().event.phase == "open" else host.dismiss_event(int(state.revision))
				"treasure", "rest": result = host.resolve_room_interaction(&"leave", int(state.revision))
				_: result = host.native_checkpoint_participants().runtime.complete_current_room()
			if not result.ok:
				return false
		await get_tree().process_frame
	return false


func _tampered_extensions(suite: RefCounted, captured: Dictionary) -> void:
	var native: Dictionary = Replay.decode_replay_json(captured.context.checkpoint.encounter_codec).replay
	for field: String in ["room_identity", "clock", "pending_type", "wave", "actor_identity", "payload_fact", "actor_fact", "missing_actor_fact", "dead_actor", "boss_hp"]:
		var changed: Dictionary = native.duplicate(true)
		match field:
			"room_identity": changed.encounter.identity.room_id = "forged_room"
			"clock": changed.last_flushed_frame += 1
			"pending_type": changed.encounter.pending_spawns = 1
			"wave": changed.encounter.spawn_frame += 1
			"actor_identity":
				if changed.actors.is_empty():
					continue
				changed.actors[changed.actors.keys()[0]].identity.hostile_source_id = "forged_source"
			"payload_fact":
				if changed.effects.payloads.projectiles.is_empty():
					continue
				for fact: Dictionary in changed.threats:
					if str(fact.hostile_source_id).begins_with("payload-"):
						fact.radius += 1.0
			"actor_fact", "missing_actor_fact":
				var selected := -1
				for index: int in range(changed.threats.size()):
					if changed.actors.has(str(changed.threats[index].hostile_source_id)):
						selected = index
						break
				if selected == -1:
					continue
				if field == "actor_fact":
					changed.threats[selected].radius += 1.0
				else:
					changed.threats.remove_at(selected)
			"dead_actor":
				if changed.actors.is_empty():
					continue
				changed.actors[changed.actors.keys()[0]].health.dead = true
			"boss_hp":
				if changed.actors.is_empty() or not changed.actors[changed.actors.keys()[0]].actor.runtime.mechanism_state.has("hp_current"):
					continue
				changed.actors[changed.actors.keys()[0]].health.current_hp -= 1.0
		var checkpoint: Dictionary = _replace_native(captured.context.checkpoint, changed)
		suite.assert_true(not Checkpoint.validate(checkpoint, captured.context.run, captured.context.reward).ok, "re-signed native extension rejects " + field + " before reconstruction")


func _replace_native(checkpoint: Dictionary, native: Dictionary) -> Dictionary:
	var changed := checkpoint.duplicate(true)
	changed.encounter_codec = Replay.encode_replay_json(native).json
	changed.erase("digest")
	changed.digest = Checkpoint.canonical(changed).sha256_text()
	return changed


func _reconstruction_failure(suite: RefCounted, host: Node, service: RefCounted, save: RefCounted, catalog: RefCounted, slot: String) -> void:
	var original: Dictionary = service.payload()
	var player: Node = host.native_checkpoint_participants().player
	var controller: Node = host.native_checkpoint_participants().controller
	var scene_host: Node = host.native_checkpoint_participants().scene_host
	var runner: Node = controller.encounter_runner()
	var player_before: Dictionary = player.full_player_replay_snapshot()
	var world_before: Node = player.world_payload_authority
	var scene_before: Dictionary = scene_host.active_snapshot()
	var runner_before: Dictionary = runner.checkpoint_restore_preimage()
	var binding_before: Dictionary = controller.checkpoint_hostile_binding()
	var changed := original.duplicate(true)
	var native: Dictionary = Replay.decode_replay_json(changed.native_run_checkpoint.encounter_codec).replay
	native.actors[native.actors.keys()[0]].actor.weapon_claim_order = [-1]
	changed.native_run_checkpoint = _replace_native(changed.native_run_checkpoint, native)
	changed = JSON.parse_string(JSON.stringify(changed, "", true, true))
	var written: Variant = save.save_profile(slot, "base", changed)
	suite.assert_true(written.ok, "fixture promotes a re-signed but unreconstructable actual actor checkpoint: " + str(written.code) + " " + str(written.diagnostics))
	if not written.ok:
		return
	var reopened := Service.new()
	suite.assert_true(reopened.configure(catalog, save, slot, "base").ok, "unreconstructable Actor does not damage authenticated Profile data")
	var refused: Variant = host.restore_profile_checkpoint(reopened, int(reopened.snapshot().revision))
	suite.assert_true(not refused.ok and refused.code != &"INTEGRITY_FAILURE", "Actor reconstruction rejection compensates staged native owners")
	suite.assert_true(player.full_player_replay_snapshot() == player_before and player.world_payload_authority == world_before, "failed aggregate restoration recovers exact Player and World instances")
	suite.assert_equal(scene_host.active_snapshot(), scene_before, "failed aggregate restoration recovers exact scene generation")
	suite.assert_equal(runner.checkpoint_restore_preimage(), runner_before, "failed aggregate restoration recovers exact Runner generation and state")
	suite.assert_equal(controller.checkpoint_hostile_binding(), binding_before, "failed aggregate restoration recovers exact threat owner and facts")
	suite.assert_true(controller.get_node("Enemies").get_child_count() == 0 and controller.get_node_or_null("NativeLaunchHostilePayloads") == null, "failed aggregate restoration synchronously removes all staged native actors and payloads")
	suite.assert_true(_equal_json(reopened.payload(), changed), "failed aggregate restoration cannot alter promoted physical evidence")
	suite.assert_true(save.save_profile(slot, "base", JSON.parse_string(JSON.stringify(original, "", true, true))).ok, "valid physical checkpoint can be retained after compensation")


func _settle_reconstructed(suite: RefCounted, host: Node, controller: Node, player: Node, runner: Node, event: bool) -> void:
	var completed := {"count": 0}
	var encounter_id: String = runner.native_launch_snapshot().definition.id
	runner.encounter_completed.connect(func(_id: StringName) -> void: completed.count += 1)
	for _frame: int in range(600):
		for actor: Node in controller.get_node("Enemies").get_children():
			if not actor.is_queued_for_deletion():
				actor.health.lose_health(1000.0, null)
		if not runner.is_active():
			break
		suite.assert_true(player.advance_action_frame(), "cold encounter accepts fixture lethal receipts through actual Player frames")
		await get_tree().physics_frame
	suite.assert_true(not runner.is_active() and completed.count == 1, "cold encounter settles the original actual encounter exactly once")
	var settled: Dictionary = host.runtime_snapshot()
	runner.encounter_completed.emit(StringName(encounter_id))
	suite.assert_equal(host.runtime_snapshot(), settled, "replayed cold encounter completion cannot mint another consequence")
	if event:
		suite.assert_true(host.native_checkpoint_participants().facade.event_view_state().phase == "resolved" and host.dismiss_event(int(settled.revision)).ok, "cold event encounter resolves and dismisses its original continuation")
	elif host.native_run_state().current_floor_node().room_type != "boss":
		suite.assert_true(not settled.open_offer.is_empty(), "cold regular encounter opens its actual authored reward")


func _equal_json(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left, "", true, true)) == JSON.parse_string(JSON.stringify(right, "", true, true))


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
