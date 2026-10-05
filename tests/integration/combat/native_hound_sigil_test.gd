extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"

const Replay := preload("res://scripts/replay/replay_recorder.gd")
const AffixRules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")


func _run() -> void:
	suite = Suite.new()
	var f := await _fixture("eternal_hound")
	var actor: Node2D = f.actors[0]
	var deaths: Array[String] = []
	actor.hostile_final_death.connect(func(source: StringName, _receipt: String): deaths.append(str(source)))
	suite.assert_true(actor.health.take_damage(_sigil_hit(f, 1, 1000.0)) > 0.0, "real Player lethal enters once-only Hound dormancy")
	suite.assert_close(actor.health.current_hp, 1.0, "dormant principal keeps one HP")
	suite.assert_true(not actor.health.dead and deaths.is_empty(), "dormant body remains counted without final death")
	var sigil := actor.get_node_or_null("DormantSigil") as Node2D
	suite.assert_true(sigil != null, "dormant native Hound exposes an actual weapon-targetable construct")
	if sigil == null:
		await _dispose(f)
		suite.finish(get_tree())
		return
	suite.assert_true(not sigil.is_in_group("enemies") and not sigil.has_node("HealthComponent"), "sigil is a construct without another enemy body or reward authority")
	var forged: Dictionary = _sigil_hit(f, 99, 5.0).snapshot()
	forged.attacker = null
	suite.assert_close(sigil.get_node("Hurtbox").receive_hit(Damage.from_plan(forged)), 0.0, "unowned damage cannot mutate an authenticated native sigil")
	actor.apply_time_rift(&"hound-sigil-rift", 0.4)
	suite.assert_true(actor.is_time_rifted(), "ordinary Rift control can coexist with derived dormant sigil geometry")
	await _capture_sigil(f)
	suite.assert_close(actor.health.take_damage(_sigil_hit(f, 2, 1000.0)), 0.0, "dormant parent body cannot receive direct damage")
	suite.assert_close(sigil.get_node("Hurtbox").receive_hit(_sigil_hit(f, 3, 5.0)), 5.0, "actual sigil Hurtbox forwards authenticated Player damage")
	suite.assert_close(sigil.get_node("Hurtbox").receive_hit(_sigil_hit(f, 3, 5.0)), 0.0, "duplicate sigil weapon identity cannot remove HP twice")
	suite.assert_close(actor.launch_runtime_snapshot().runtime.mechanism_state.sigil_hp, 7.0, "sigil HP is authoritative species state")
	var before: Dictionary = actor.launch_transaction_snapshot()
	var damage := _sigil_hit(f, 4, 7.0)
	var player_ticket: Dictionary = f.bridge.begin_frame(1)
	suite.assert_true(not player_ticket.is_empty() and f.bridge.prepare_frame(player_ticket), "shared native frame captures dormant parent before terminal sigil hit")
	suite.assert_close(sigil.get_node("Hurtbox").receive_hit(damage), 7.0, "sigil destruction stages parent final Health death")
	suite.assert_true(actor.health.dead and deaths.is_empty(), "sealed sigil death remains unpublished before frame acceptance")
	suite.assert_true(f.bridge.rollback_frame(player_ticket), "rejected sigil death compensates complete native participant")
	suite.assert_equal(actor.launch_transaction_snapshot(), before, "sigil rollback restores HP, once-only counters, claims and Health")
	suite.assert_true(actor.get_node("DormantSigil").get_node("Hurtbox").collision_layer == 4 and deaths.is_empty(), "rollback preserves weapon-targetable sigil and no kill observation")
	var captured: Dictionary = actor.native_cold_snapshot(func(source: Node): return {"id": "player"} if source == f.player else {})
	suite.assert_true(not captured.is_empty(), "compensated dormant Actor reaches stable cold boundary: " + str([actor.get("_prepared_launch_frame"), actor.health.frame_signal_transaction_is_active(), actor.health.hostile_body_application_is_active()]))
	if captured.is_empty():
		await _dispose(f)
		suite.finish(get_tree())
		return
	var encoded: Dictionary = Replay.encode_replay_json(captured)
	suite.assert_true(encoded.ok, "dormant cold envelope encodes safely: " + str(encoded))
	if not encoded.ok:
		await _dispose(f)
		suite.finish(get_tree())
		return
	var cold: Dictionary = Replay.decode_replay_json(encoded.json).replay
	var twin := await _fixture("eternal_hound")
	suite.assert_true(twin.actors[0].restore_native_cold_snapshot(cold, func(binding: Dictionary): return twin.player if binding.get("id") == "player" else null), "typed cold snapshot reconstructs live dormant sigil")
	suite.assert_equal(twin.actors[0].launch_runtime_snapshot(), actor.launch_runtime_snapshot(), "cold dormant species and Health state remain exact")
	suite.assert_true(twin.actors[0].get_node_or_null("DormantSigil") != null, "fresh Actor owns physical restored construct")
	suite.assert_close(sigil.get_node("Hurtbox").receive_hit(damage), 7.0, "retry of compensated sigil identity finalizes original parent")
	suite.assert_true(actor.health.dead and deaths.size() == 1, "sigil destruction publishes exactly one original-principal final death")
	suite.assert_true(actor.get_node("DormantSigil").get_node("Hurtbox").collision_layer == 0, "final sigil cannot remain damaging or targetable")
	await _dispose(f)
	twin.actors[0].apply_time_stop_source(&"hound-unscaled-stop", 5.1)
	for frame: int in range(1, 300):
		suite.assert_true(_step(twin), "accepted unscaled dormancy frame%d" % frame)
	var reform_ticket: Dictionary = twin.bridge.begin_frame(300)
	var reform_prepared: bool = twin.bridge.prepare_frame(reform_ticket)
	suite.assert_true(reform_prepared, "reform frame prepares exact Health restoration: " + str(twin.effects.get("_pending")))
	var reform_publication: Dictionary = twin.bridge.prepare_frame_publication(reform_ticket) if reform_prepared else {}
	suite.assert_true(not reform_publication.is_empty(), "reform frame reaches stable publication boundary: " + str([twin.actors[0].get("_prepared_launch_frame"), twin.actors[0].health.current_hp]))
	if not reform_publication.is_empty():
		suite.assert_true(twin.bridge.finalize_frame_publication(reform_publication) and twin.bridge.seal_frame_publication(reform_publication), "reform frame seals atomically")
		twin.bridge.publish_prepared_frame()
	suite.assert_close(twin.actors[0].health.current_hp, 35.0, "surviving sigil reforms its parent after exactly three hundred frames")
	suite.assert_true(twin.actors[0].get_node("DormantSigil").get_node("Hurtbox").collision_layer == 0, "reform removes sigil targetability")
	suite.assert_true(twin.actors[0].health.take_damage(_sigil_hit(twin, 5, 1000.0)) > 0.0 and twin.actors[0].health.dead, "reformed Hound cannot enter another dormancy")
	await _dispose(twin)
	await _test_sigil_budget()
	await _test_mixed_components()
	await _test_affixed_terminal()
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		await _test_normal_weapon(weapon)
	suite.finish(get_tree())


func _sigil_hit(f: Dictionary, generation: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": "run-summon-lifecycle", "target_id": str(f.actors[0].hostile_source_id), "hostile_source_id": "player:1", "attack_generation": generation, "hit_index": 0, "action_token": generation, "source_generation": generation, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "source": f.player, "attacker": f.player, "tags": ["weapon:sword"], "can_crit": false})


func _test_sigil_budget() -> void:
	var f := await _fixture("eternal_hound", 9)
	for index: int in range(8):
		var info: Dictionary = _sigil_hit(f, 100 + index, 1000.0).snapshot()
		info.target_id = str(f.actors[index].hostile_source_id)
		suite.assert_true(f.actors[index].health.take_damage(Damage.from_plan(info)) > 0.0, "native construct budget admits dormant sigil%d" % index)
	suite.assert_equal(f.effects.native_construct_count(), 8, "eight live sigils consume the complete shared construct cap")
	var refused: Dictionary = _sigil_hit(f, 110, 1000.0).snapshot()
	refused.target_id = str(f.actors[8].hostile_source_id)
	var before: Dictionary = f.actors[8].launch_transaction_snapshot()
	suite.assert_close(f.actors[8].health.take_damage(Damage.from_plan(refused)), 0.0, "full construct budget refuses a ninth dormant publication")
	suite.assert_equal(f.actors[8].launch_transaction_snapshot(), before, "refused dormancy cannot consume its once-only counter or body HP")
	suite.assert_close(f.actors[0].get_node("DormantSigil/Hurtbox").receive_hit(_sigil_hit(f, 111, 12.0)), 12.0, "terminal sigil destruction releases one construct slot")
	suite.assert_true(f.actors[8].health.take_damage(Damage.from_plan(refused)) > 0.0 and f.effects.native_construct_count() == 8, "exact deferred lethal identity enters dormancy when a construct slot is free")
	await _dispose(f)


func _capture_sigil(f: Dictionary) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		var center := Vector2i(f.actors[0].global_position * Vector2(pixels.get_size()) / Vector2(640, 360))
		var colors := {}
		var extent := ceili(16.0 * float(pixels.get_width()) / 640.0)
		for y: int in range(center.y - extent, center.y + extent):
			for x: int in range(center.x - extent, center.x + extent):
				colors[pixels.get_pixel(x, y).to_rgba32()] = true
		suite.assert_true(colors.size() >= 3, "native Hound sigil raster renders at " + str(resolution))
		var output := "res://build/visual-evidence/native-enemy-mechanisms/hound-sigil-%dx%d.png" % [resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "actual native sigil screenshot retains visual evidence")


func _test_mixed_components() -> void:
	var f := await _fixture("eternal_hound")
	var actor: Node2D = f.actors[0]
	actor.health.take_damage(_sigil_hit(f, 121, 1000.0))
	var physical: Dictionary = _sigil_hit(f, 122, 3.0).snapshot()
	var temporal := physical.duplicate(true)
	temporal.damage_type = Damage.DamageType.TIME
	temporal.amount = 4.0
	suite.assert_close(actor.get_node("DormantSigil/Hurtbox").receive_hit(Damage.from_plan(physical)), 3.0, "mixed payload physical component reaches native sigil")
	suite.assert_close(actor.get_node("DormantSigil/Hurtbox").receive_hit(Damage.from_plan(temporal)), 4.0, "same native hit admits its distinct authored Time component")
	suite.assert_close(actor.get_node("DormantSigil/Hurtbox").receive_hit(Damage.from_plan(temporal)), 0.0, "duplicate mixed component cannot remove sigil HP again")
	suite.assert_close(actor.launch_runtime_snapshot().runtime.mechanism_state.sigil_hp, 5.0, "mixed payload preserves exact aggregate sigil HP")
	await _dispose(f)


func _test_normal_weapon(weapon: String) -> void:
	var f := await _fixture("eternal_hound")
	var actor: Node2D = f.actors[0]
	var deaths: Array[String] = []
	actor.hostile_final_death.connect(func(source: StringName, _receipt: String): deaths.append(str(source)))
	actor.health.take_damage(_sigil_hit(f, 201, 1000.0))
	f.player.process_mode = Node.PROCESS_MODE_INHERIT
	f.player.set_physics_process(false)
	f.player.get_node("TimeManager").set_process(false)
	f.player.get_node("RewindRecorder").set_process(false)
	suite.assert_true(f.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": f.player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}) and f.player.configure_hostile_frame_participant(f.bridge), "normal " + weapon + " binds native dormant sigil authority")
	f.player.global_position = actor.global_position - Vector2(42, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}) and f.player.try_action(&"weapon_primary"), "normal " + weapon + " input attacks actual dormant sigil Hurtbox")
	for frame: int in range(120):
		if frame == 40:
			f.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
		suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}), "native " + weapon + " sigil collision frame accepts")
		await get_tree().physics_frame
		if not deaths.is_empty():
			break
	suite.assert_equal(deaths.size(), 1, "actual " + weapon + " producer destroys construct and publishes one original-parent kill")
	f.player.cancel_transient_actions()
	await _dispose(f)


func _test_affixed_terminal() -> void:
	suite.assert_true(not AffixRules.legal_for("eternal_hound", 5, ["splitting"]), "Hound child ownership retains authored Splitting exclusion")
	var f := await _fixture("eternal_hound", 1, ["shielded"])
	var actor: Node2D = f.actors[0]
	var deaths: Array[String] = []
	actor.hostile_final_death.connect(func(source: StringName, _receipt: String): deaths.append(str(source)))
	suite.assert_true(actor.health.take_damage(_sigil_hit(f, 301, 1000.0)) > 0.0 and actor.health.current_hp == 1.0, "Shielded principal still enters once-only dormancy")
	var claims_before: Array = actor.launch_affix_runtime_snapshot().shielded.damage_claims.duplicate(true)
	suite.assert_close(actor.get_node("DormantSigil/Hurtbox").receive_hit(_sigil_hit(f, 302, 12.0)), 12.0, "affixed sigil destruction settles the original Health component")
	suite.assert_true(actor.health.dead and deaths == [str(actor.hostile_source_id)], "construct destruction emits exactly the original Hound death identity")
	suite.assert_equal(actor.launch_affix_runtime_snapshot().shielded.damage_claims, claims_before, "sigil settlement cannot create another Shielded damage claim")
	suite.assert_true(actor.launch_affix_runtime_snapshot().terminal and _step(f), "terminal affix cancellation accepts shared native frame")
	suite.assert_equal(f.effects.summon_snapshot().rows.size(), 0, "destroyed dormant sigil cannot recursively create another principal")
	await _dispose(f)
