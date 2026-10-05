extends RefCounted

const PlayerScene := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const Orchestrator := preload("res://scripts/application/run_orchestrator.gd")


static func build(stage: Node2D, registry: RefCounted, definition: Dictionary, request: Dictionary, run_id: String, source_prefix: String, encounter_id: String) -> Dictionary:
	var room_scene: PackedScene = load(definition.template.scene_path)
	var boss_scene: PackedScene = load(definition.boss_scene)
	if room_scene == null or boss_scene == null:
		return {"ok": false, "reason": "scene_resource"}
	var room: Node2D = room_scene.instantiate()
	stage.add_child(room)
	var player: Node2D = PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	stage.add_child(player)
	var native_config := {"milestone": "LAUNCH", "seed": int(request.seed), "character_id": request.character_id, "weapon_id": request.weapon_id, "enabled_time_skills": request.time_abilities.duplicate(), "accessibility_assists": request.accessibility_assists, "character_profile": registry.resolve_character_runtime_profile(StringName(request.character_id), &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(StringName(request.weapon_id), &"LAUNCH")}
	if not player.configure_run(StringName(run_id)) or not player.configure_loadout(native_config):
		return {"ok": false, "reason": "player_configuration"}
	player.global_position = room.get_node("PlayerEntry").global_position
	var boss: Node2D = boss_scene.instantiate()
	var source_id := source_prefix + "-" + run_id.sha256_text().substr(0, 40)
	boss.set_meta("run_id", StringName(run_id))
	boss.set_meta("encounter_id", StringName(encounter_id))
	boss.set_meta("room_id", StringName(str(definition.template.id)))
	boss.set_meta("encounter_spawn_id", source_id)
	boss.set_meta("stable_target_id", run_id.sha256_text().substr(0, 12).hex_to_int())
	boss.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	stage.add_child(boss)
	boss.global_position = room.get_node("EncounterAnchors/boss_primary").global_position
	boss.target = player
	var identity := {"run_id": run_id, "hostile_source_id": source_id, "next_generation_floor": 1, "runtime_frame": int(player.priority_arbitration_snapshot().frame), "seed": int(request.seed)}
	var configured: Dictionary = boss.configure_launch_definition(definition.runtime_definition, identity)
	if not configured.get("ok", false):
		return {"ok": false, "reason": "boss_definition: " + str(configured)}
	var motion: Dictionary = boss.configure_launch_room_motion(room, definition.template)
	if not motion.get("ok", false) or not boss.configure_character_boss_exposure_replay_authority(RefCounted.new()):
		return {"ok": false, "reason": "boss_room_motion: " + str(motion)}
	var payloads := Node2D.new()
	stage.add_child(payloads)
	var effects := Effects.new()
	var bridge := Bridge.new()
	if not effects.configure(run_id, int(identity.runtime_frame)) or not effects.configure_native_payloads(payloads):
		return {"ok": false, "reason": "effects_configuration"}
	if not bridge.configure(player, Threats.new(), [boss], effects) or not player.configure_hostile_frame_participant(bridge):
		effects.dispose_native_effects()
		return {"ok": false, "reason": "bridge_configuration"}
	var orchestrator := Orchestrator.new()
	orchestrator.enter_hub()
	orchestrator.start_run({"milestone": "LAUNCH", "character_id": request.character_id, "weapon_id": request.weapon_id, "enabled_time_skills": request.time_abilities, "seed": int(request.seed), "accessibility_assists": request.accessibility_assists}, run_id)
	orchestrator.preparation_completed()
	orchestrator.room_entered(true)
	return {"ok": true, "room": room, "player": player, "boss": boss, "effects": effects, "bridge": bridge, "orchestrator": orchestrator}
