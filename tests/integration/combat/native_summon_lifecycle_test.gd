extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
const Player := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const SummonProjection := preload("res://scripts/enemies/launch/launch_summon_projection.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for entry: Array in [["forest_caller", "forest_caller.void_call"], ["forest_caller", "forest_caller.great_call"], ["void_hunter", "void_hunter.hunter_echo"], ["phase_ranger", "phase_ranger.phase_split"], ["forest_heart", "matriarch_call"], ["time_sovereign", "traitor_timeline_split"]]:
		await _authored_action(entry[0], entry[1])
	for id: String in ["ruins_wraith", "void_spore"]:
		await _terminal_split(id)
		await _natural_terminal_split(id)
	await _budget_and_rollback()
	await _late_birth_refusal()
	await _owner_cleanup()
	await _lifetime()
	await _echo_explosion()
	suite.finish(get_tree())


func _fixture(id: String, count: int = 1, affixes: Array[String] = []) -> Dictionary:
	var boss_source := Content.boss(id)
	var is_boss := not boss_source.is_empty()
	var room_id := "room_boss_" + id if is_boss else "room_boss_time_sovereign"
	var room := load("res://data/content_packs/base/assets/rooms/launch/%s.tscn" % room_id).instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var template := {}
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if row.id == room_id:
			template = row
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-summon-lifecycle")
	player.global_position = Vector2(400, 220)
	player.health.acquire_invulnerability_source(&"summon-matrix")
	var actors: Array[Node2D] = []
	for index: int in range(count):
		var actor := load("res://data/content_packs/base/assets/%s/launch/%s_%s.tscn" % ["bosses" if is_boss else "enemies", "boss" if is_boss else "enemy", id]).instantiate() as Node2D
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		add_child(actor)
		actor.global_position = Vector2(320, 180)
		if not affixes.is_empty():
			var definitions: Array = []
			for affix: String in affixes:
				definitions.append(Content.affix(affix))
			suite.assert_true(actor.configure_launch_affixes(definitions, 5).ok, "actual authored parent binds requested native affixes")
		var parser: RefCounted = Boss.new() if is_boss else Enemy.new()
		parser.configure(boss_source if is_boss else Content.enemy(id))
		var projection: Dictionary = parser.runtime_projection() if is_boss else parser.runtime_projection("elite")
		suite.assert_true(actor.configure_launch_definition(projection, {"run_id": "run-summon-lifecycle", "hostile_source_id": "summon-owner-%d" % index, "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}).ok and actor.configure_launch_room_motion(room, template).ok, "actual authored parent binds native summon room " + id)
		actors.append(actor)
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-summon-lifecycle", 0)
	effects.configure_native_payloads(root)
	effects.configure_native_summon_room(room, template)
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, actors, effects), "real parents share authenticated summon frame participant")
	await get_tree().physics_frame
	return {"room": room, "actors": actors, "player": player, "root": root, "effects": effects, "registry": registry, "bridge": bridge, "frame": 0}


func _start(f: Dictionary, id: String) -> bool:
	var accepted := true
	for actor: Node2D in f.actors:
		var started: Dictionary = actor.get("_launch_runtime").request_action(id, {"runtime_frame": f.frame, "source_position": _point(actor.global_position), "target_position": _point(f.player.global_position), "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1"})
		accepted = started.ok and accepted
		for fact: Dictionary in started.get("threat_facts", []):
			f.registry.register_fact(Actions.native_threat_fact(fact))
		actor.project_runtime_snapshot(actor.launch_runtime_snapshot())
	return accepted


func _step(f: Dictionary) -> bool:
	var frame := int(f.frame) + 1
	var ticket: Dictionary = f.bridge.begin_frame(frame)
	if ticket.is_empty() or not f.bridge.prepare_frame(ticket) or not _publish(f.bridge, ticket):
		if not ticket.is_empty():
			f.bridge.rollback_frame(ticket)
		return false
	f.frame = frame
	return true


func _authored_action(id: String, action_id: String) -> void:
	var f := await _fixture(id)
	if not Content.boss(id).is_empty():
		_unlock_boss(f)
	var action := Content.action(action_id)
	suite.assert_true(_start(f, action_id), "native parent begins authored summon " + action_id)
	var accepted := true
	for frame: int in range(1, int(action.warning_frames) + 1):
		accepted = _step(f) and accepted
		if frame < int(action.warning_frames):
			suite.assert_equal(f.effects.native_summon_actors().size(), 0, "child body cannot precede complete authored parent warning")
	suite.assert_true(accepted and f.effects.native_summon_actors().size() == action.parameters.count, "authored summon creates exact child count " + action_id)
	for child: Node2D in f.effects.native_summon_actors().values():
		suite.assert_true(child.get("_launch_definition").id == action.parameters.definition_id and child.get_meta("summoned") and not child.get_meta("reward_eligible"), "authored native child retains support identity and zero reward eligibility")
	suite.assert_true(_step(f), "newly born child executes next shared native frame")
	if action_id == "forest_caller.void_call":
		var forged: Dictionary = f.effects.launch_transaction_snapshot()
		var swapped: Dictionary = Content.read_catalog("summons.json").filter(func(row: Dictionary): return row.id == "small_void_spore")[0]
		forged.summons.rows[0].projection = SummonProjection.create(swapped).definition
		forged.summons.rows[0].lifetime_frames = int(swapped.lifetime_frames)
		forged.summons.rows[0].expires_frame = int(forged.summons.rows[0].birth_frame) + int(swapped.lifetime_frames)
		suite.assert_true(not f.effects.can_restore_launch_transaction_snapshot(forged), "cold summon snapshot rejects internally consistent child substitution outside its parent's authored action")
		forged = f.effects.launch_transaction_snapshot()
		forged.summons.rows[0].retire_on_owner_death = false
		suite.assert_true(not f.effects.can_restore_launch_transaction_snapshot(forged), "cold summon snapshot preserves canonical caller-owned child retirement")
	await _capture(f, action.parameters.definition_id)
	await _dispose(f)


func _terminal_split(id: String) -> void:
	var f := await _fixture(id)
	var actor: Node2D = f.actors[0]
	var action := Content.action(id + (".spirit_split" if id == "ruins_wraith" else ".spore_split"))
	var ticket: Dictionary = f.bridge.begin_frame(1)
	suite.assert_true(_hit(actor, f.player, 100000.0, 1) > 0.0, "actual native Player weapon stages elite split death")
	var prepared: bool = f.bridge.prepare_frame(ticket)
	suite.assert_true(prepared and _publish(f.bridge, ticket), "elite death reserves authoritative pending split work " + id)
	if not prepared:
		f.bridge.rollback_frame(ticket)
		await _dispose(f)
		return
	f.frame = 1
	f.bridge.retire_actor(str(actor.hostile_source_id))
	suite.assert_equal(f.effects.work_snapshot().records.size(), 2 + int(id == "void_spore"), "death children keep real pending encounter work")
	for _frame: int in range(int(action.warning_frames)):
		suite.assert_true(_step(f), "orphan split completes full authored visible spawn warning")
	suite.assert_equal(f.effects.native_summon_actors().size(), 2, "elite terminal split creates two real nonrecursive child bodies " + id)
	await _capture(f, action.parameters.definition_id)
	await _dispose(f)


func _natural_terminal_split(id: String) -> void:
	var f := await _fixture(id)
	var actor: Node2D = f.actors[0]
	var source := str(actor.hostile_source_id)
	var action_id := id + (".spirit_detonation" if id == "ruins_wraith" else ".spore_burst")
	var action := Content.action(action_id)
	f.player.global_position = actor.global_position + Vector2(20, 0)
	suite.assert_true(_start(f, action_id), "natural elite begins actual terminal attack " + id)
	f.player.global_position = Vector2(400, 220)
	var consumed := false
	for _frame: int in range(int(action.warning_frames) + int(action.active_frames) + 2):
		var before: Dictionary = f.effects.snapshot()
		var body_before: Dictionary = actor.launch_runtime_snapshot()
		var frame := int(f.frame) + 1
		var ticket: Dictionary = f.bridge.begin_frame(frame)
		var prepared: bool = not ticket.is_empty() and f.bridge.prepare_frame(ticket)
		suite.assert_true(prepared, "natural terminal attack accepts native frame " + id)
		if not prepared:
			if not ticket.is_empty():
				f.bridge.rollback_frame(ticket)
			break
		if actor.prepared_launch_frame_consumes_actor():
			var candidate: Dictionary = f.effects.summon_snapshot()
			suite.assert_true(actor.get_node("HealthComponent").dead and candidate.rows.size() == 2, "prepared natural consumption reserves authenticated split children " + id)
			suite.assert_true(f.bridge.rollback_frame(ticket) and f.effects.snapshot() == before and actor.launch_runtime_snapshot() == body_before, "rejected natural consumption restores exact principal and summon reservation state")
			suite.assert_true(_step(f) and actor.get_node("HealthComponent").dead and f.effects.summon_snapshot() == candidate, "same natural consumption retries once with identical child identity and warning clocks")
			f.bridge.retire_actor(source)
			consumed = true
			break
		suite.assert_true(_publish(f.bridge, ticket), "natural terminal attack publishes complete warning and active clocks")
		f.frame = frame
	suite.assert_true(consumed, "authored native self-consumption reaches final split " + id)
	if consumed:
		var split := Content.action(id + (".spirit_split" if id == "ruins_wraith" else ".spore_split"))
		for _warning: int in range(int(split.warning_frames)):
			suite.assert_true(_step(f), "natural terminal split retains full spawn warning")
		suite.assert_equal(f.effects.native_summon_actors().size(), 2, "natural native terminal attack leaves two actual split bodies " + id)
	await _dispose(f)


func _budget_and_rollback() -> void:
	var f := await _fixture("forest_caller", 5)
	suite.assert_true(_start(f, "forest_caller.void_call"), "five real callers reserve ten authenticated children")
	for _frame: int in range(44):
		suite.assert_true(_step(f), "budget fixture retains parent full warning")
	var before: Dictionary = f.effects.snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(45)
	suite.assert_true(f.bridge.prepare_frame(ticket) and f.effects.native_summon_actors().size() == 8, "native admission respects exact eight-body summon budget")
	suite.assert_true(f.bridge.rollback_frame(ticket), "late sibling refusal compensates child birth")
	suite.assert_equal(f.effects.snapshot(), before, "rejected birth restores complete claims, reservations and authority clocks")
	suite.assert_equal(f.effects.native_summon_actors().size(), 0, "rejected births leave no weapon-targetable child bodies")
	suite.assert_true(_step(f), "same authored birth retries without consuming source identities")
	suite.assert_equal(f.effects.summon_snapshot().rows.filter(func(row: Dictionary): return row.phase == "PENDING").size(), 2, "over-budget children remain authoritative pending work")
	if f.effects.native_summon_actors().is_empty():
		await _dispose(f)
		return
	var child: Node2D = f.effects.native_summon_actors().values()[0]
	var child_before: Dictionary = child.launch_runtime_snapshot()
	before = f.effects.snapshot()
	ticket = f.bridge.begin_frame(46)
	suite.assert_true(_hit(child, f.player, 100000.0, 2) > 0.0 and f.bridge.prepare_frame(ticket), "native child accepts actual lethal Player weapon damage")
	suite.assert_true(f.bridge.rollback_frame(ticket), "rejected child death and deferred admission compensate together")
	suite.assert_equal(child.launch_runtime_snapshot(), child_before, "rejected child lethal restores actual Health and action/control facts")
	suite.assert_equal(f.effects.snapshot(), before, "rejected child lethal restores budget and pending warning clocks")
	ticket = f.bridge.begin_frame(46)
	_hit(child, f.player, 100000.0, 2)
	suite.assert_true(f.bridge.prepare_frame(ticket) and _publish(f.bridge, ticket), "same native child lethal accepts once after retry")
	f.frame = 46
	suite.assert_equal(f.effects.native_summon_actors().size(), 7, "accepted child death opens one live summon slot")
	suite.assert_equal(f.effects.summon_snapshot().rows.filter(func(row: Dictionary): return row.phase == "WARNING").size(), 1, "deferred child restarts complete thirty-frame native warning")
	for _frame: int in range(29):
		suite.assert_true(_step(f), "deferred admission retains visible warning")
	suite.assert_equal(f.effects.native_summon_actors().size(), 7, "deferred body cannot shorten rewarning")
	suite.assert_true(_step(f) and f.effects.native_summon_actors().size() == 8, "deferred child materializes after complete rewarning")
	await _dispose(f)


func _late_birth_refusal() -> void:
	var f := await _fixture("forest_caller")
	_start(f, "forest_caller.void_call")
	for _frame: int in range(44):
		_step(f)
	var before: Dictionary = f.effects.snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(45)
	suite.assert_true(f.bridge.prepare_frame(ticket), "safe original summon slots prepare actual native birth")
	var original: Vector2 = f.player.global_position
	f.player.global_position = f.effects.native_summon_actors().values()[0].global_position
	suite.assert_true(f.bridge.prepare_frame_publication(ticket).is_empty(), "late Player overlap refuses summon birth before native publication")
	f.player.global_position = original
	suite.assert_true(f.bridge.rollback_frame(ticket) and f.effects.snapshot() == before and f.effects.native_summon_actors().is_empty(), "late unsafe birth restores exact reservations and native bodies")
	suite.assert_true(_step(f) and f.effects.native_summon_actors().size() == 2, "same original safe slots retry with stable child identities")
	await _dispose(f)


func _owner_cleanup() -> void:
	var f := await _fixture("forest_caller")
	_start(f, "forest_caller.void_call")
	for _frame: int in range(45):
		_step(f)
	f.actors[0].get("_launch_runtime").add_control_source("caller-isolation", "stop", 120, 1.0)
	for _frame: int in range(31):
		_step(f)
	suite.assert_true(not f.effects.payload_snapshot().projectiles.is_empty(), "real firefly publishes native projectile before owner cleanup")
	var ticket: Dictionary = f.bridge.begin_frame(int(f.frame) + 1)
	_hit(f.actors[0], f.player, 100000.0, 21)
	suite.assert_true(f.bridge.prepare_frame(ticket) and _publish(f.bridge, ticket), "actual caller final death retires child bodies and owned native projectile in one frame")
	f.frame = int(f.frame) + 1
	suite.assert_true(f.effects.native_summon_actors().is_empty() and f.effects.payload_snapshot().projectiles.is_empty() and f.effects.work_snapshot().records.is_empty(), "owner retirement cannot leave orphan child damage or encounter work")
	await _dispose(f)


func _lifetime() -> void:
	var f := await _fixture("void_hunter")
	_start(f, "void_hunter.hunter_echo")
	for _frame: int in range(35):
		_step(f)
	var child: Node2D = f.effects.native_summon_actors().values()[0]
	f.actors[0].get("_launch_runtime").add_control_source("ttl-isolation", "stop", 600, 1.0)
	child.get("_launch_runtime").add_control_source("ttl-isolation", "stop", 600, 1.0)
	for _frame: int in range(479):
		suite.assert_true(_step(f), "unscaled summon lifetime accepts every native clock")
	var before: Dictionary = f.effects.snapshot()
	var body_before: Dictionary = child.launch_runtime_snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(515)
	suite.assert_true(f.bridge.prepare_frame(ticket) and f.effects.native_summon_actors().is_empty(), "summon expires exactly after authored four-hundred-eighty accepted frames")
	suite.assert_true(f.bridge.rollback_frame(ticket) and child.launch_runtime_snapshot() == body_before and f.effects.snapshot() == before, "rejected lifetime expiry restores actual HP, lease and action/control clocks")
	suite.assert_true(_step(f) and f.effects.native_summon_actors().is_empty(), "authored expiry retries once without extending lifetime")
	await _dispose(f)


func _echo_explosion() -> void:
	var f := await _fixture("time_sovereign")
	_unlock_boss(f)
	_start(f, "traitor_timeline_split")
	for _frame: int in range(75):
		suite.assert_true(_step(f), "timeline split completes full authored warning")
	var children: Dictionary = f.effects.native_summon_actors()
	if children.size() != 2:
		suite.assert_true(false, "timeline explosion requires two actual children")
		await _dispose(f)
		return
	var child: Node2D = children.values()[0]
	f.actors[0].get("_launch_runtime").add_control_source("echo-isolation", "stop", 240, 1.0)
	for other: Node2D in children.values():
		other.get("_launch_runtime").add_control_source("echo-isolation", "stop", 240, 1.0)
	f.player.global_position = child.global_position + Vector2(20, 0)
	var death_frame := int(f.frame) + 1
	var ticket: Dictionary = f.bridge.begin_frame(death_frame)
	_hit(child, f.player, 100000.0, 3)
	suite.assert_true(f.bridge.prepare_frame(ticket) and _publish(f.bridge, ticket), "actual timeline death reserves its legitimate final explosion")
	f.frame = death_frame
	var zones: Array = f.effects.semantic_snapshot().zones.filter(func(row: Dictionary): return row.action_id == "timeline_echo.final_explosion")
	suite.assert_true(zones.size() == 1 and zones[0].warning_frames == 35 and zones[0].damage == 20.0 and zones[0].geometry.radius == 32.0, "timeline final explosion has approved damage, radius and full warning")
	await _capture(f, "timeline-final-warning")
	f.player.health.release_invulnerability_source(&"summon-matrix")
	var hp: float = f.player.health.current_hp
	for _frame: int in range(34):
		suite.assert_true(_step(f), "terminal echo retains complete thirty-five-frame warning")
	suite.assert_equal(f.player.health.current_hp, hp, "terminal echo cannot damage before warning expires")
	suite.assert_true(_step(f) and f.player.health.current_hp == hp - 20.0, "real terminal echo explosion damages Player after full warning")
	await _dispose(f)


func _unlock_boss(f: Dictionary) -> void:
	var actor: Node2D = f.actors[0]
	f.player.global_position = Vector2(600, 180)
	var ticket: Dictionary = f.bridge.begin_frame(1)
	_hit(actor, f.player, actor.get_node("HealthComponent").max_hp * 0.5 + actor.get_node("HealthComponent").defense, 20)
	suite.assert_true(f.bridge.prepare_frame(ticket) and _publish(f.bridge, ticket), "real native weapon damage unlocks authored phase-two summon")
	f.frame = 1
	actor.get("_launch_runtime").add_control_source("phase-isolation", "stop", 100, 1.0)
	for _frame: int in range(61):
		suite.assert_true(_step(f), "phase-two summon preserves complete nonattacking transition")
	actor.get("_launch_runtime").clear_control_source("phase-isolation")
	actor.cancel_active_attack()
	f.player.global_position = actor.global_position + Vector2(80, 40)


func _hit(actor: Node2D, player: Node2D, amount: float, generation: int) -> float:
	return actor.get_node("WatchHurtbox" if actor.get("_launch_definition").id == "time_sovereign" else "Hurtbox").receive_hit(Damage.from_plan({"run_id": "run-summon-lifecycle", "target_id": str(actor.hostile_source_id), "hostile_source_id": "player:sword", "attack_generation": generation, "action_token": generation, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": player, "attacker": player}))


func _publish(bridge: RefCounted, ticket: Dictionary) -> bool:
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	if publication.is_empty() or not bridge.finalize_frame_publication(publication) or not bridge.seal_frame_publication(publication):
		return false
	bridge.publish_prepared_frame()
	return true


func _capture(f: Dictionary, label: String) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		for child: Node2D in f.effects.native_summon_actors().values():
			var colors := {}
			var center := Vector2i(child.global_position * Vector2(pixels.get_size()) / Vector2(640, 360))
			var extent := ceili(16.0 * float(pixels.get_width()) / 640.0)
			for y: int in range(maxi(0, center.y - extent), mini(pixels.get_height(), center.y + extent)):
				for x: int in range(maxi(0, center.x - extent), mini(pixels.get_width(), center.x + extent)):
					colors[pixels.get_pixel(x, y).to_rgba32()] = true
			suite.assert_true(colors.size() >= 3, "actual native summon raster renders at " + str(resolution))
		var output := "res://build/visual-evidence/native-summons/%s-%dx%d.png" % [label, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "native summon screenshot retained")


func _dispose(f: Dictionary) -> void:
	f.effects.dispose_native_effects()
	for node: Variant in f.actors + [f.player, f.root, f.room]:
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
