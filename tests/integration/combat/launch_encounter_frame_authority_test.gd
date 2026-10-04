extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const Fixtures := preload("res://tests/support/p15_encounter_fixtures.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Coordinator := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const MothScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_corrosive_moth.tscn")
const RoomScene := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")

class RejectingBridge extends "res://scripts/enemies/launch/hostile_frame_bridge.gd":
	var kill_actor: Node2D
	var reject_at := -1
	var kill_at := 62

	func begin_frame(frame: int) -> Dictionary:
		var ticket := super.begin_frame(frame)
		if not ticket.is_empty() and frame == kill_at and is_instance_valid(kill_actor):
			kill_actor.get_node("HealthComponent").lose_health(1000.0, null)
		return ticket

	func finalize_frame_publication(publication: Dictionary) -> bool:
		if publication.ticket.runtime_frame == reject_at:
			reject_at = -1
			return false
		return super.finalize_frame_publication(publication)

var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var path := "res://scripts/dungeon/launch_encounter_frame_authority.gd"
	suite.assert_true(FileAccess.file_exists(path), "native room pending-work authority exists")
	if FileAccess.file_exists(path):
		var implementation := load(path)
		_test_ledger_cas(implementation)
		await _test_native_moth_completion(implementation)
	suite.finish(get_tree())


func _encounter() -> RefCounted:
	var definition := Fixtures.encounter()
	definition.waves.resize(1)
	definition.waves[0].spawns.resize(1)
	definition.waves[0].spawns[0].enemy_id = "corrosive_moth"
	var result := Encounter.new()
	suite.assert_true(result.configure(definition, Fixtures.identity()).ok, "authored closed encounter configures one native Moth spawn")
	for frame: int in range(1, 32):
		var advance: Dictionary = result.advance_frame(frame)
		suite.assert_true(advance.ok, "room accepts each full pre-spawn warning frame")
	return result


func _test_ledger_cas(implementation: Script) -> void:
	var encounter := _encounter()
	suite.assert_true(encounter.register_spawned("spawn_1", "hostile-moth-room"), "unit native ledger binds declared source")
	var effects := Effects.new()
	effects.configure("run-p15", 31)
	var ledger: RefCounted = implementation.new()
	suite.assert_true(ledger.configure(encounter, effects), "room authority binds the exact existing run and accepted frame")
	suite.assert_true(not ledger.configure(encounter, effects), "room authority cannot rebind live ownership")
	var foreign := Effects.new()
	foreign.configure("foreign-run", 31)
	suite.assert_true(not implementation.new().configure(encounter, foreign), "foreign run cannot own the room ledger")
	var registry := Threats.new()
	var effects_ticket: Dictionary = effects.prepare_effects([], {"run_id": "run-p15", "runtime_frame": 32, "threat_registry": registry, "actors": {}, "targets": {}})
	suite.assert_true(effects_ticket.ok, "real effects authority seals an empty native payload transition")
	var before: Dictionary = ledger.snapshot()
	var corrupt := before.duplicate(true)
	corrupt.runtime_frame += 1
	suite.assert_true(not ledger.can_restore_launch_transaction_snapshot(corrupt), "live room checkpoint cannot separate encounter and aggregate clocks")
	var forged: Dictionary = effects_ticket.ticket.duplicate(true)
	forged.runtime_frame += 1
	suite.assert_true(not ledger.prepare_frame(forged).ok and ledger.snapshot() == before, "forged effect ticket cannot authorize a room frame")
	var prepared: Dictionary = ledger.prepare_frame(effects_ticket.ticket)
	suite.assert_true(prepared.ok and ledger.snapshot() == before, "room preflight is pure and consumes only the sealed effects transition")
	if prepared.ok:
		encounter.reserve_pending_work("external-construct", "construct", "hostile-moth-room")
		suite.assert_true(not ledger.can_commit(prepared.ticket), "late room-ledger mutation rejects compare-and-swap commit")
		suite.assert_true(ledger.rollback(prepared.ticket), "room compensation restores its exact before snapshot")
		suite.assert_equal(ledger.snapshot(), before, "room compensation retains the same accepted clock")
	effects.rollback(effects_ticket.ticket)
	suite.assert_true(not encounter.configure({}, Fixtures.identity()).ok, "room invalidation probe rejects an invalid new definition")
	suite.assert_true(not ledger.is_ready_for_frame(32), "invalidated encounter identity fails closed at the native frame boundary")


func _test_native_moth_completion(implementation: Script) -> void:
	var registry := Registry.new()
	suite.assert_true(not registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH").has_blocking_errors(), "actual activated content loads for native room completion")
	var player := PlayerScene.instantiate() as Node2D
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "character_talents": [], "weapon_id": "sword", "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}
	suite.assert_true(player.configure_loadout(config) and player.configure_run(&"run-p15"), "native room test uses actual Launch Character and weapon contracts")
	player.global_position = Vector2(160, 100)
	player.set_meta(&"stable_target_key", "player")
	for _frame: int in range(31):
		suite.assert_true(player.advance_action_frame(), "Player advances actual accepted pre-spawn frames")
	var encounter := _encounter()
	var room := RoomScene.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var template: Dictionary = {}
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	for authored: Dictionary in templates:
		if authored.id == "room_combat_open_field":
			template = authored.duplicate(true)
	var actor := MothScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(100, 100)
	var parser := Enemy.new()
	parser.configure(Content.enemy("corrosive_moth"))
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-p15", "hostile_source_id": "hostile-moth-room", "next_generation_floor": 7, "runtime_frame": 31, "seed": 42}).ok and actor.configure_launch_room_motion(room, template).ok, "native Moth binds a validated physical room at the actual accepted spawn frame")
	suite.assert_true(encounter.register_spawned("spawn_1", "hostile-moth-room"), "native room acknowledges its actual Moth source")
	var death_receipts: Array = []
	actor.hostile_final_death.connect(func(source: StringName, receipt: String):
		death_receipts.append(receipt)
		suite.assert_true(encounter.notify_entity_defeated(str(source), receipt), "published authentic native death removes only the room roster body")
	)
	var native_root := Node2D.new()
	add_child(native_root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-p15", 31) and effects.configure_native_payloads(native_root), "native payload owner binds at the same room clock")
	var threats := Threats.new()
	var started: Dictionary = actor.get("_launch_runtime").request_action("corrosive_moth.corrosive_spit", {"runtime_frame": 31, "source_position": {"x": 100.0, "y": 100.0}, "target_position": {"x": 160.0, "y": 100.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player"})
	for fact: Dictionary in started.threat_facts:
		threats.register_fact(Coordinator.native_threat_fact(fact))
	var ledger: RefCounted = implementation.new()
	suite.assert_true(ledger.configure(encounter, effects), "native room frame authority owns the real encounter and payload aggregate")
	var observed: Array = []
	var reentry: Array = []
	ledger.encounter_frame_observed.connect(func(result: Dictionary):
		if not result.encounter_completed.is_empty():
			observed.append(result.duplicate(true))
			reentry.append(player.advance_action_frame())
	)
	var bridge := RejectingBridge.new()
	bridge.kill_actor = actor
	suite.assert_true(bridge.configure(player, threats, [actor], effects), "actual Player binds the native hostile effect aggregate")
	var same_run_foreign_effects := Effects.new()
	same_run_foreign_effects.configure("run-p15", 31)
	var foreign_ledger: RefCounted = implementation.new()
	suite.assert_true(foreign_ledger.configure(encounter, same_run_foreign_effects), "ownership probe uses a separate same-run effects object")
	suite.assert_true(not bridge.configure_encounter_authority(foreign_ledger), "same run and clock cannot replace the exact native effects owner")
	suite.assert_true(bridge.configure_encounter_authority(ledger) and player.configure_hostile_frame_participant(bridge), "actual Player transaction includes the native room ledger")
	suite.assert_true(not bridge.configure(player, threats, [actor], same_run_foreign_effects) and bridge.get("_effects") == effects, "bound room authority rejects later effect-owner replacement without mutation")
	await get_tree().physics_frame
	var impact_frame := -1
	var completion_frame := -1
	for frame: int in range(32, 220):
		if frame in [61, 62, 74] or (impact_frame > 0 and frame == impact_frame + 120):
			var before: Dictionary = ledger.snapshot()
			var effects_before: Dictionary = effects.snapshot()
			bridge.reject_at = frame
			suite.assert_true(not player.advance_action_frame(), "late whole-frame rejection compensates room reservation, death, impact or completion")
			suite.assert_equal(ledger.snapshot(), before, "rejected room frame restores exact pending work and accepted clock")
			suite.assert_equal(effects.snapshot(), effects_before, "room rollback retains the exact authoritative payload transition")
			suite.assert_equal(observed, [], "rejected native completion emits no room observation")
		var accepted: bool = player.advance_action_frame()
		suite.assert_true(accepted, "Player accepts native room frame %d" % frame)
		if not accepted:
			break
		var payload: Dictionary = effects.payload_snapshot()
		suite.assert_equal(encounter.snapshot().pending_work.size(), payload.projectiles.size() + payload.zones.size(), "room work counts every native payload reservation")
		if frame == 62:
			suite.assert_equal(death_receipts.size(), 1, "native parent death emits one authenticated receipt")
			suite.assert_true(encounter.alive_count() == 0 and encounter.snapshot().pending_work.size() == 2 and not encounter.can_complete(), "dead Moth leaves independent projectile and warned pool pending")
		for zone: Dictionary in payload.zones:
			if impact_frame < 0 and zone.definition.kind == "impact_pool":
				impact_frame = frame
				player.global_position = Vector2(zone.definition.position.x, zone.definition.position.y)
		if not payload.projectiles.is_empty() or not payload.zones.is_empty():
			suite.assert_true(not encounter.can_complete(), "live or queued dangerous payloads forbid native room completion")
		if encounter.can_complete():
			completion_frame = frame
			break
		await get_tree().physics_frame
	suite.assert_true(impact_frame > 61 and completion_frame == impact_frame + 120, "room completes only on the accepted final acid retirement frame")
	suite.assert_equal(observed.size(), 1, "accepted native completion publishes exactly one room observation")
	suite.assert_equal(reentry, [false], "room observation publication rejects whole-frame callback reentry")
	suite.assert_equal(player.get_node("HealthComponent").current_hp, 186.0, "actual Launch Character receives projectile and two finite acid ticks before room clear")
	suite.assert_true(player.advance_action_frame(), "Player can leave an already completed room without advancing terminal encounter state")
	suite.assert_equal(observed.size(), 1, "post-completion Player frame cannot republish the room clear")
	player.configure_hostile_frame_participant(null)
	player.queue_free()
	if is_instance_valid(actor):
		actor.queue_free()
	native_root.queue_free()
	room.queue_free()
	await get_tree().process_frame
