extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const EnemyDefinition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const BossDefinition := preload("res://scripts/enemies/launch/boss_definition.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const ProductionBridge := preload("res://scripts/enemies/launch/production_hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const NATIVE_METHODS: Array[StringName] = [&"supports_native_launch_frame_protocol", &"prepare_native_launch_frame", &"owns_native_launch_frame_token", &"can_commit_native_launch_frame", &"commit_native_launch_frame", &"rollback_native_launch_frame", &"can_publish_native_launch_frame", &"publish_native_launch_frame"]
const TOKEN_PATH := "res://scripts/enemies/launch/native_hostile_frame_token.gd"
var suite: RefCounted


class ForgedAuthority:
	extends RefCounted
	var _registry: RefCounted
	func _current_runtime_frame() -> int:
		return 0
	func owns_native_actor_preparation_context(_actor: Node2D, _frame: int) -> bool:
		return true
	func owns_native_actor_frame_context(_actor: Node2D, _token: RefCounted, _frame: int) -> bool:
		return true


class InterceptingEffects extends "res://scripts/enemies/launch/launch_hostile_effect_authority.gd":
	var before_actor_commit: Callable
	var refuse_commit := false
	func can_commit(ticket: Dictionary) -> bool:
		if before_actor_commit.is_valid():
			var callback := before_actor_commit
			before_actor_commit = Callable()
			callback.call()
		return super.can_commit(ticket)
	func commit(ticket: Dictionary) -> Dictionary:
		return {"ok": false} if refuse_commit else super.commit(ticket)


class ClaimingActor extends "res://scripts/enemies/launch/launch_hostile_actor.gd":
	var native_preparations := 0
	func supports_native_launch_frame_protocol() -> bool:
		return true
	func prepare_native_launch_frame(_frame: int, _observations: Dictionary, _authority: RefCounted) -> Dictionary:
		native_preparations += 1
		return {"ok": false}


class UnknownProductionBridge extends "res://scripts/enemies/launch/production_hostile_frame_bridge.gd":
	pass


class InterceptingHealth extends "res://scripts/combat/health_component.gd":
	var before_publication: Callable
	var before_native_frame_snapshot: Callable
	func runtime_state_snapshot() -> Dictionary:
		var actor := get_parent()
		if before_native_frame_snapshot.is_valid() and actor.get("_native_launch_frame_mutating") and actor.get("_native_launch_frame_token") != null:
			var callback := before_native_frame_snapshot
			before_native_frame_snapshot = Callable()
			callback.call()
		return super.runtime_state_snapshot()
	func prepare_frame_signal_publication(ticket: Dictionary) -> Dictionary:
		if before_publication.is_valid():
			var callback := before_publication
			before_publication = Callable()
			callback.call()
		return super.prepare_frame_signal_publication(ticket)


class CountingBossRuntime extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var before_match_calls := 0
	var forge_geometry_reads := 0
	func matches_snapshot(value: Dictionary) -> bool:
		before_match_calls += 1
		return super.matches_snapshot(value)
	func forge_arena_snapshot() -> Dictionary:
		forge_geometry_reads += 1
		return super.forge_arena_snapshot()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	await _test_actor("shattered_sentinel")
	await _test_actor("eternal_hound")
	await _test_actor("shattered_sentinel", false, true)
	await _test_actor("forge_colossus", false, true)
	for row: Dictionary in Content.read_catalog("bosses.json"):
		await _test_actor(str(row.id))
		if row.id in ["void_throne", "time_sovereign"]:
			await _test_actor(str(row.id), true)
	await _test_legacy_lease_fallback()
	await _test_custom_fallback()
	suite.finish(get_tree())


func _test_actor(id: String, historical: bool = false, production: bool = false) -> void:
	var boss := not Content.boss(id).is_empty()
	var room_id := "room_boss_" + id if boss else "room_combat_open_field"
	var room := (load("res://data/content_packs/base/assets/rooms/launch/%s.tscn" % room_id) as PackedScene).instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var template: Dictionary = {}
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if row.id == room_id:
			template = row
	var path := "res://data/content_packs/base/assets/%s/launch/%s_%s.tscn" % ["bosses" if boss else "enemies", "boss" if boss else "enemy", id]
	var actor := (load(path) as PackedScene).instantiate() as Node2D
	if id in ["shattered_sentinel", "eternal_hound", "forge_colossus", "time_sovereign"]:
		actor.get_node("HealthComponent").set_script(InterceptingHealth)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.global_position = Vector2(320, 180)
	var parser: RefCounted = BossDefinition.new() if boss else EnemyDefinition.new()
	suite.assert_true(parser.configure(Content.boss(id) if boss else Content.enemy(id)).ok, "owned fixture parses authored " + id)
	var definition: Dictionary = parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	identity.hostile_source_id = "owned-" + id
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok and actor.configure_launch_room_motion(room, template).ok, "owned fixture binds the actual validated native room")
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = actor.global_position + Vector2(20, 0)
	var source := Node2D.new()
	var attacker := Node2D.new()
	add_child(source)
	add_child(attacker)
	suite.assert_true(actor.apply_elemental_status(&"burn", &"owned-burn", 1, 60, 1.0, 30, -1.0, source, attacker), "owned fixture retains real status source/attacker identities")
	var context := Actions.context(1)
	context.source_position = _point(actor.global_position)
	context.target_position = _point(player.global_position)
	if historical:
		_install_historical_action(actor, definition, context)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var label := id + (" historical" if historical else "")
	var public_candidate := _test_public_candidate(actor, context, source, attacker, label)
	var protocol_ready := true
	for method: StringName in NATIVE_METHODS:
		suite.assert_true(actor.has_method(method), "genuine native protocol exists: " + label + ":" + str(method))
		protocol_ready = protocol_ready and actor.has_method(method)
	var bridge: RefCounted = ProductionBridge.new() if production else Bridge.new()
	for method: StringName in [&"owns_native_actor_preparation_context", &"owns_native_actor_frame_context"]:
		suite.assert_true(bridge.has_method(method), "genuine Bridge owns exact native context: " + label + ":" + str(method))
		protocol_ready = protocol_ready and bridge.has_method(method)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-p15"), "owned fixture configures the genuine Effects authority")
	var registry := Registry.new()
	if protocol_ready:
		var forged := ForgedAuthority.new()
		forged._registry = registry
		suite.assert_true(actor.configure_hostile_threat_authority(registry, Callable(forged, "_current_runtime_frame")), "legacy binding accepts callable forged authority fixture")
		var forgery: Dictionary = actor.call("prepare_native_launch_frame", 1, context, forged)
		suite.assert_true(not forgery.get("ok", false) and actor.get("_prepared_launch_frame").is_empty() and actor.get("_native_launch_frame_token") == null, "fake Bridge with true ownership methods and real provider binding cannot issue candidate or marker")
		if id == "shattered_sentinel":
			var forged_script: Script = forged.get_script()
			var canonical_bridge_script: Script = Bridge
			var original_path := forged_script.resource_path
			forged_script.take_over_path(canonical_bridge_script.resource_path)
			forgery = actor.call("prepare_native_launch_frame", 1, context, forged)
			suite.assert_true(not forgery.get("ok", false) and actor.get("_prepared_launch_frame").is_empty() and actor.get("_native_launch_frame_token") == null, "distinct same-path forged Bridge cannot authenticate its bound provider")
			canonical_bridge_script.take_over_path("res://scripts/enemies/launch/hostile_frame_bridge.gd")
			forged_script.take_over_path(original_path)
			var canonical_production_script: Script = ProductionBridge
			forged_script.take_over_path(canonical_production_script.resource_path)
			forgery = actor.call("prepare_native_launch_frame", 1, context, forged)
			suite.assert_true(not forgery.get("ok", false) and not Bridge.authenticates_native_bridge_script(forged) and actor.get("_prepared_launch_frame").is_empty() and actor.get("_native_launch_frame_token") == null, "distinct same-path Production spoof cannot issue any native candidate")
			canonical_production_script.take_over_path("res://scripts/enemies/launch/production_hostile_frame_bridge.gd")
			forged_script.take_over_path(original_path)
			var unknown := UnknownProductionBridge.new()
			var unknown_effects := Effects.new()
			unknown_effects.configure("run-p15")
			suite.assert_true(unknown.configure(player, registry, [actor], unknown_effects), "unknown Production subclass keeps valid public binding")
			var unknown_script: Script = unknown.get_script()
			var unknown_path := unknown_script.resource_path
			unknown_script.take_over_path(canonical_production_script.resource_path)
			var unknown_ticket: Dictionary = unknown.begin_frame(1)
			suite.assert_true(unknown.prepare_frame(unknown_ticket) and not unknown.get("_active").records[0].native_actor_frame and not unknown.get("_active").records[0].actor_ticket.is_empty() and not Bridge.authenticates_native_bridge_script(unknown), "same-path unknown Production subclass retains complete public fallback")
			suite.assert_true(unknown.rollback_frame(unknown_ticket), "unknown Production fallback preserves exact compensation")
			canonical_production_script.take_over_path("res://scripts/enemies/launch/production_hostile_frame_bridge.gd")
			unknown_script.take_over_path(unknown_path)
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "owned fixture binds actual Player, Actor, Registry and Effects")
	if protocol_ready:
		if id == "forge_colossus":
			_test_native_guard_counts(actor, bridge)
		if id in ["eternal_hound", "forge_colossus"]:
			_test_native_budget_binding(actor, bridge, effects, id)
		if id == "shattered_sentinel" or id == "time_sovereign" and not historical:
			_test_native_configuration(actor, player, bridge, id)
		_test_owned_bridge(actor, player, bridge, effects, registry, public_candidate, label)
	else:
		var before := var_to_bytes(actor.launch_runtime_snapshot())
		var frame_ticket: Dictionary = bridge.begin_frame(1)
		suite.assert_true(not frame_ticket.is_empty() and bridge.prepare_frame(frame_ticket), "preproduction real dictionary Bridge still prepares: " + label)
		suite.assert_true(bridge.rollback_frame(frame_ticket), "preproduction real dictionary Bridge still compensates: " + label)
		suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "preproduction compensation remains byte-exact: " + label)
	actor.queue_free()
	player.queue_free()
	room.queue_free()
	source.queue_free()
	attacker.queue_free()
	await get_tree().process_frame


func _install_historical_action(actor: Node2D, definition: Dictionary, context: Dictionary) -> void:
	var runtime: RefCounted = actor.get("_launch_runtime")
	var initial := context.duplicate(true)
	initial.runtime_frame = 0
	var action_id := str(definition.actions[0].id)
	suite.assert_true(runtime.request_action(action_id, initial).ok, "genuine Boss commits its authored action before historical replacement")
	var legacy: RefCounted = runtime.call("_make_action", 0, false, false, true) if definition.id == "void_throne" else runtime.call("_make_action", 0, false, true, false)
	suite.assert_true(legacy.request_action(action_id, initial).ok, "genuine historical coordinator commits its authored warning")
	runtime.set("_action", legacy)
	runtime.set("_legacy_void_action" if definition.id == "void_throne" else "_legacy_time_action", true)
	suite.assert_true(runtime.can_restore_native_snapshot(runtime.snapshot()), "complete current native validation accepts genuine historical action")


func _test_public_candidate(actor: Node2D, context: Dictionary, source: Node, attacker: Node, label: String) -> Dictionary:
	var before := var_to_bytes(actor.launch_runtime_snapshot())
	var prepared: Dictionary = actor.prepare_launch_frame(1, context)
	suite.assert_true(prepared.ok, "complete public preparation remains available: " + label)
	if not prepared.ok:
		return {}
	suite.assert_equal(prepared.keys(), ["ok", "ticket", "batch"], "public success field order remains exact")
	suite.assert_equal(prepared.ticket.keys(), ["ticket_id", "hostile_source_id", "runtime_frame", "before", "after", "batch", "health_before", "collision_target"], "public full ticket field order remains exact")
	var pristine: Dictionary = prepared.ticket.duplicate(true)
	var retained := var_to_bytes(actor.get("_prepared_launch_frame"))
	for state: Dictionary in [pristine.before, pristine.after]:
		for entry: Dictionary in state.status.entries.values():
			suite.assert_true(entry.damage_source == source and entry.damage_attacker == attacker, "public full typed state keeps actual burn object identities")
	prepared.ticket.before.runtime.action.cooldowns["caller"] = 23
	prepared.ticket.after.position.x = -500.0
	prepared.ticket.health_before.current_hp = -100.0
	prepared.batch.threat_facts.append({"caller": true})
	suite.assert_equal(var_to_bytes(actor.get("_prepared_launch_frame")), retained, "public branch mutation cannot poison owned candidate")
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "public branch mutation cannot poison live authority")
	suite.assert_true(not actor.can_commit_launch_frame(prepared.ticket), "public complete equality still refuses tampered output")
	suite.assert_true(actor.can_commit_launch_frame(pristine) and actor.rollback_launch_frame(pristine), "authentic public ticket remains valid and compensates independently")
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "public compensation remains complete and byte-exact")
	return pristine


func _test_owned_bridge(actor: Node2D, player: Node2D, bridge: RefCounted, _effects: RefCounted, registry: RefCounted, public_candidate: Dictionary, label: String) -> void:
	suite.assert_true(actor.call("supports_native_launch_frame_protocol"), "only the exact migrated native scene opts in")
	var before := var_to_bytes(actor.launch_runtime_snapshot())
	var unauthorized: Dictionary = actor.call("prepare_native_launch_frame", 1, Actions.context(1), RefCounted.new())
	suite.assert_true(not unauthorized.get("ok", false) and var_to_bytes(actor.launch_runtime_snapshot()) == before, "unbound native preparation refuses without changing actual authority")
	var frame_ticket: Dictionary = bridge.begin_frame(1)
	suite.assert_true(not frame_ticket.is_empty() and bridge.prepare_frame(frame_ticket), "real native Bridge prepares and commits owned candidate: " + label)
	if bridge.get("_active").get("records", []).is_empty():
		return
	var record: Dictionary = bridge.get("_active").records[0]
	suite.assert_true(record.get("native_actor_frame", false) and record.get("actor_token") is RefCounted and record.get("actor_ticket", {}).is_empty(), "native Bridge retains only opaque marker and no public full ticket")
	var token: Variant = record.get("actor_token")
	if not token is RefCounted:
		bridge.rollback_frame(frame_ticket)
		return
	suite.assert_true(token.get_script() != null and token.get_script().resource_path == TOKEN_PATH, "native marker uses the exact empty protocol class")
	for property: Dictionary in token.get_property_list():
		suite.assert_true(property.type not in [TYPE_DICTIONARY, TYPE_ARRAY], "opaque marker exposes no mutable before/after payload")
	var owned: Dictionary = actor.get("_prepared_launch_frame")
	for field: String in ["before", "after", "batch", "health_before", "collision_target"]:
		suite.assert_equal(var_to_bytes(owned[field]), var_to_bytes(public_candidate[field]), "native candidate preserves exact public typed field " + field)
	suite.assert_true(actor.call("owns_native_launch_frame_token", token, bridge) and actor.call("can_publish_native_launch_frame", token, bridge), "exact native marker survives actual committed candidate")
	suite.assert_true(not actor.call("commit_native_launch_frame", token, bridge), "committed native candidate cannot commit twice")
	var pending := var_to_bytes(owned)
	for forged: RefCounted in [RefCounted.new(), token.get_script().new()]:
		suite.assert_true(not actor.call("owns_native_launch_frame_token", forged, bridge) and not actor.call("rollback_native_launch_frame", forged, bridge), "arbitrary or same-class marker cannot authenticate or consume compensation")
	suite.assert_true(not actor.call("owns_native_launch_frame_token", token, RefCounted.new()) and not actor.call("publish_native_launch_frame", token, RefCounted.new()), "another authority cannot use the authentic marker")
	suite.assert_equal(var_to_bytes(actor.get("_prepared_launch_frame")), pending, "foreign token/authority refusals retain exact canonical candidate")
	var batch: Dictionary = actor.prepared_launch_frame_batch()
	batch.threat_facts.append({"caller": true})
	suite.assert_equal(var_to_bytes(actor.get("_prepared_launch_frame")), pending, "detached batch callers cannot mutate the native candidate")
	suite.assert_true(actor.call("rollback_native_launch_frame", token, bridge), "authentic native rollback restores candidate before state")
	suite.assert_true(not actor.call("owns_native_launch_frame_token", token, bridge), "candidate rollback immediately revokes the old marker")
	suite.assert_true(bridge.rollback_frame(frame_ticket), "Bridge still restores its required earlier pre-weapon checkpoint")
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "complete native rollback remains byte-exact")
	suite.assert_equal(registry.snapshot(), [], "complete native rollback restores physical threat prefix")
	suite.assert_true(not actor.call("rollback_native_launch_frame", token, bridge), "revoked marker cannot restore twice")
	if label == "shattered_sentinel":
		_test_failure_boundaries(actor, player, registry, before)
		suite.assert_true(bridge.configure(player, registry, [actor], _effects), "original Bridge rebinds after independent native refusal fixtures")
	var damages: Array = []
	var publication_reentry: Array = []
	actor.get_node("HealthComponent").damaged.connect(func(amount: float, hp: float):
		damages.append([amount, hp])
		publication_reentry.append(bridge.begin_frame(2).is_empty() and not bridge.is_ready_for_frame(2) and not bridge.rollback_frame(frame_ticket) and actor.get("_native_launch_frame_token") == null)
		bridge.publish_prepared_frame())
	var retry: Dictionary = bridge.begin_frame(1)
	actor.get_node("HealthComponent").take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": str(actor.hostile_source_id), "hostile_source_id": "player:1", "attack_generation": 7, "action_token": 7, "amount": 10.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false, "source": player, "attacker": player}))
	suite.assert_true(bridge.prepare_frame(retry), "compensated owned frame retries deterministically after real Player weapon damage")
	var fresh: Variant = bridge.get("_active").records[0].get("actor_token")
	suite.assert_true(fresh is RefCounted and not is_same(fresh, token), "native retry issues a different exact marker")
	suite.assert_equal(damages, [], "native preparation publishes no premature actual Health signal")
	var publication: Dictionary = bridge.prepare_frame_publication(retry)
	suite.assert_true(not publication.is_empty() and bridge.finalize_frame_publication(publication) and bridge.seal_frame_publication(publication), "actual native retry finalizes and seals all original siblings")
	suite.assert_true(not actor.call("owns_native_launch_frame_token", fresh, bridge), "sealing publication revokes the committed Actor marker")
	bridge.publish_prepared_frame()
	suite.assert_equal(damages.size(), 1, "accepted native retry publishes actual Player weapon damage exactly once")
	suite.assert_equal(publication_reentry, [true], "actual Health publication callback cannot begin or repeat a native frame")
	bridge.publish_prepared_frame()
	suite.assert_equal(damages.size(), 1, "repeated native publication cannot duplicate observers")
	suite.assert_true(not actor.call("publish_native_launch_frame", fresh, bridge) and not bridge.rollback_frame(retry), "published native candidate cannot publish or compensate again")


func _test_failure_boundaries(actor: Node2D, player: Node2D, registry: RefCounted, before: PackedByteArray) -> void:
	var initial_effects := Effects.new()
	initial_effects.configure("run-p15")
	var initial_bridge := Bridge.new()
	suite.assert_true(initial_bridge.configure(player, registry, [actor], initial_effects), "pre-issuance failure fixture configures genuine native authorities")
	var initial_ticket: Dictionary = initial_bridge.begin_frame(1)
	var room: Node2D = actor.get("_motion_room")
	var room_transform := room.transform
	room.position += Vector2(1, 0)
	suite.assert_true(not initial_bridge.prepare_frame(initial_ticket) and actor.get("_prepared_launch_frame").is_empty() and actor.get("_native_launch_frame_token") == null, "actual room authority drift refuses before candidate or marker issuance")
	suite.assert_true(initial_bridge.prepare_frame_publication(initial_ticket).is_empty() and initial_bridge.get("_last_runtime_frame") == 0, "pre-issuance native failure cannot publish or advance accepted time")
	room.transform = room_transform
	suite.assert_true(initial_bridge.rollback_frame(initial_ticket) and var_to_bytes(actor.launch_runtime_snapshot()) == before, "repaired physical room permits original complete pre-weapon compensation")
	for refusal: String in ["effects", "health", "roster", "record", "rebind", "identity", "retirement", "restore", "rollback_failure", "finalized", "publication_reentry"]:
		var effects := InterceptingEffects.new()
		effects.configure("run-p15")
		var bridge := Bridge.new()
		suite.assert_true(bridge.configure(player, registry, [actor], effects), "native refusal fixture configures exact real Bridge: " + refusal)
		var ticket: Dictionary = bridge.begin_frame(1)
		var checkpoint: Dictionary = bridge.get("_active").records[0].checkpoint.duplicate(true)
		var reentry: Array = []
		effects.before_actor_commit = func():
			var record: Dictionary = bridge.get("_active").records[0]
			var marker: RefCounted = record.actor_token
			reentry.append(bridge.begin_frame(1).is_empty() and not bridge.prepare_frame(ticket) and not bridge.rollback_frame(ticket) and bridge.prepare_frame_publication(ticket).is_empty() and not bridge.finalize_frame_publication({}) and not bridge.seal_frame_publication({}))
			suite.assert_true(actor.owns_native_launch_frame_token(marker, bridge), "refused Bridge reentry preserves authentic compensation marker")
			if refusal == "health":
				actor.health.current_hp -= 1.0
				suite.assert_true(not actor.can_commit_native_launch_frame(marker, bridge), "live Health drift remains visible through native commit guard")
		effects.refuse_commit = refusal == "effects"
		var accepted := bridge.prepare_frame(ticket)
		suite.assert_equal(reentry, [true], "native transaction refuses all callback reentry before actor commit")
		var record: Dictionary = bridge.get("_active").records[0]
		var marker: RefCounted = record.actor_token
		if refusal in ["effects", "health"]:
			suite.assert_true(not accepted and bridge.prepare_frame_publication(ticket).is_empty(), "late native sibling/Health failure cannot prepare publication")
		else:
			suite.assert_true(accepted, "native candidate commits before refusal boundary: " + refusal)
		if refusal == "roster":
			bridge.get("_actors")[str(actor.hostile_source_id)] = player
			suite.assert_true(not actor.owns_native_launch_frame_token(marker, bridge) and not actor.can_publish_native_launch_frame(marker, bridge), "replaced live roster cannot authenticate the prepared marker")
			bridge.get("_actors")[str(actor.hostile_source_id)] = actor
		elif refusal == "record":
			record.actor_token = RefCounted.new()
			suite.assert_true(not actor.owns_native_launch_frame_token(marker, bridge), "different marker in same exact frame record cannot reauthorize old marker")
			record.actor_token = marker
		elif refusal == "rebind":
			suite.assert_true(actor.configure_hostile_threat_authority(registry, Callable(bridge, "_current_runtime_frame")), "accepted inherited authority rebind remains available")
			suite.assert_true(actor.get("_native_launch_frame_token") == null and not actor.owns_native_launch_frame_token(marker, bridge), "even same-provider accepted rebind immediately revokes marker")
		elif refusal == "restore":
			suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "original complete transaction restoration still compensates candidate")
			suite.assert_true(actor.get("_native_launch_frame_token") == null and not actor.owns_native_launch_frame_token(marker, bridge), "complete transaction restore immediately revokes marker")
		elif refusal == "identity":
			suite.assert_true(actor.configure_hostile_identity(actor.hostile_source_id), "accepted inherited same-source identity configuration remains available")
			suite.assert_true(actor.get("_native_launch_frame_token") == null and not actor.owns_native_launch_frame_token(marker, bridge), "accepted same-source identity reconfiguration immediately revokes marker")
		elif refusal == "retirement":
			actor.retire_hostile_identity(&"owned-fixture-retirement")
			suite.assert_true(actor.get("_native_launch_frame_token") == null and not actor.owns_native_launch_frame_token(marker, bridge), "inherited identity retirement immediately revokes marker")
		elif refusal == "rollback_failure":
			record.checkpoint.actor.runtime.schema_version = -1
			suite.assert_true(not bridge.rollback_frame(ticket) and bridge.get("_active").is_empty() and bridge.get("_last_runtime_frame") == 0, "failed original checkpoint restore clears active records without advancing accepted frame")
			suite.assert_true(not actor.owns_native_launch_frame_token(marker, bridge) and not actor.publish_native_launch_frame(marker, bridge), "failed compensation cannot manufacture authority or publish held marker")
			suite.assert_true(actor.restore_launch_transaction_snapshot(checkpoint), "fixture explicitly restores its pristine checkpoint after intentional original failure")
			var retry: Dictionary = bridge.begin_frame(1)
			suite.assert_true(bridge.prepare_frame(retry) and not actor.owns_native_launch_frame_token(marker, bridge), "same-frame new transaction cannot reauthorize failed transaction marker")
			suite.assert_true(bridge.rollback_frame(retry), "fresh retry retains original pre-weapon compensation")
		elif refusal == "finalized":
			var publication: Dictionary = bridge.prepare_frame_publication(ticket)
			suite.assert_true(not publication.is_empty() and bridge.finalize_frame_publication(publication), "native finalization detaches without publication")
			suite.assert_true(actor.get("_native_launch_frame_token") == null, "native publication cleanup revokes before external observers")
		elif refusal == "publication_reentry":
			actor.health.before_publication = func():
				var refused: bool = bridge.prepare_frame_publication(ticket).is_empty()
				suite.assert_true(refused, "participant Health callback cannot recursively prepare native publication")
				if refused:
					suite.assert_true(not bridge.rollback_frame(ticket) and not bridge.finalize_frame_publication({}) and not bridge.seal_frame_publication({}), "participant Health callback cannot mutate outer native publication transaction")
			var publication: Dictionary = bridge.prepare_frame_publication(ticket)
			suite.assert_true(not publication.is_empty(), "refused publication callback preserves outer candidate and compensation")
		if refusal == "restore":
			suite.assert_true(not bridge.rollback_frame(ticket), "original Health rollback still refuses an already restored signal transaction")
		elif refusal != "rollback_failure":
			suite.assert_true(bridge.rollback_frame(ticket), "original pre-weapon checkpoint compensates native refusal boundary: " + refusal)
		suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "native refusal restores exact typed authoritative state: " + refusal)
		suite.assert_equal(registry.snapshot(), [], "native refusal restores registry without observations")


func _test_native_budget_binding(actor: Node2D, bridge: RefCounted, effects: RefCounted, id: String) -> void:
	var field := "_arena_effects" if id == "forge_colossus" else "_hound_construct_authority"
	var before := var_to_bytes(actor.launch_runtime_snapshot())
	var replacement := Effects.new()
	suite.assert_true(replacement.configure("run-p15"), "budget replacement uses actual configured Effects: " + id)
	var wrong_run := Effects.new()
	wrong_run.configure("different-run")
	var ticket: Dictionary = bridge.begin_frame(1)
	var reentry: Array = []
	actor.health.before_native_frame_snapshot = func():
		var marker: RefCounted = actor.get("_native_launch_frame_token")
		reentry.append(not actor.bind_native_construct_budget(replacement) and actor.get(field).get_ref() == effects and not replacement.get("_construct_owners").has(str(actor.hostile_source_id)) and is_same(actor.get("_native_launch_frame_token"), marker))
	suite.assert_true(bridge.prepare_frame(ticket), "budget callback fixture prepares actual native candidate: " + id)
	var token: RefCounted = bridge.get("_active").records[0].actor_token
	suite.assert_true(not actor.bind_native_construct_budget(wrong_run) and actor.owns_native_launch_frame_token(token, bridge), "refused wrong-run budget binding preserves authentic marker: " + id)
	suite.assert_true(actor.publish_native_launch_frame(token, bridge), "budget callback refusal preserves outer native publication: " + id)
	suite.assert_equal(reentry, [true], "actual Health live-state callback cannot change construct authority during native commit: " + id)
	suite.assert_true(bridge.rollback_frame(ticket), "budget callback fixture retains complete pre-weapon compensation: " + id)
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "budget callback compensation preserves complete actual state: " + id)
	suite.assert_true(actor.bind_native_construct_budget(effects), "original budget authority restores after publication fixture: " + id)
	for authority: RefCounted in [replacement, replacement]:
		ticket = bridge.begin_frame(1)
		suite.assert_true(bridge.prepare_frame(ticket), "budget revocation fixture prepares actual native candidate: " + id)
		token = bridge.get("_active").records[0].actor_token
		suite.assert_true(actor.bind_native_construct_budget(authority) and actor.get(field).get_ref() == authority and authority.get("_construct_owners").has(str(actor.hostile_source_id)), "accepted actual budget binding installs and registers the owner: " + id)
		suite.assert_true(actor.get("_native_launch_frame_token") == null and not actor.owns_native_launch_frame_token(token, bridge) and not actor.publish_native_launch_frame(token, bridge), "accepted budget replacement or same-authority rebind immediately revokes marker: " + id)
		suite.assert_true(bridge.rollback_frame(ticket), "budget revocation retains original complete pre-weapon compensation: " + id)
		suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "budget rebind compensation preserves complete actual state: " + id)
	suite.assert_true(actor.bind_native_construct_budget(effects), "budget fixture restores original Effects for later native semantics: " + id)


func _test_native_configuration(actor: Node2D, player: Node2D, bridge: RefCounted, id: String) -> void:
	var before := var_to_bytes(actor.launch_runtime_snapshot())
	var status_before := var_to_bytes(actor.elemental_status_runtime.transaction_snapshot())
	var replay := RefCounted.new()
	var foreign_player := PlayerScene.instantiate() as Node2D
	foreign_player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(foreign_player)
	var configurations: Array = ["seed"] if id == "shattered_sentinel" else ["time", "replay"]
	for configuration: String in configurations:
		var ticket: Dictionary = bridge.begin_frame(1)
		var reentry: Array = []
		actor.health.before_native_frame_snapshot = func():
			var marker: RefCounted = actor.get("_native_launch_frame_token")
			if configuration == "seed":
				var original := var_to_bytes(actor.elemental_status_runtime.transaction_snapshot())
				actor.configure_elemental_status_seed(9001, 0.15, 0.20)
				reentry.append(var_to_bytes(actor.elemental_status_runtime.transaction_snapshot()) == original and is_same(actor.get("_native_launch_frame_token"), marker))
			elif configuration == "time":
				reentry.append(not actor.bind_native_time_manager(player.time_manager) and actor.get("_native_time_manager").get_ref() == player.time_manager and is_same(actor.get("_native_launch_frame_token"), marker))
			else:
				reentry.append(not actor.configure_character_boss_exposure_replay_authority(replay) and actor.get("_exposure_replay_authority") == null and is_same(actor.get("_native_launch_frame_token"), marker))
		suite.assert_true(bridge.prepare_frame(ticket), "actual native commit refuses configuration callback: " + configuration)
		suite.assert_equal(reentry, [true], "configuration reentry preserves authority and exact candidate: " + configuration)
		suite.assert_true(bridge.rollback_frame(ticket), "configuration callback retains complete compensation: " + configuration)
		suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "configuration callback preserves actual typed state: " + configuration)
		suite.assert_equal(var_to_bytes(actor.elemental_status_runtime.transaction_snapshot()), status_before, "configuration callback compensates exact status configuration: " + configuration)
		for attempt: int in range(2):
			ticket = bridge.begin_frame(1)
			suite.assert_true(bridge.prepare_frame(ticket), "configuration invalidation prepares actual committed token: " + configuration)
			var token: RefCounted = bridge.get("_active").records[0].actor_token
			if configuration == "seed":
				actor.configure_elemental_status_seed(9001, 0.15, 0.20)
				suite.assert_equal(actor.elemental_status_runtime.get("_deterministic_seed"), 9001, "accepted seed configuration preserves inherited behavior")
			elif configuration == "time":
				suite.assert_true(not actor.bind_native_time_manager(null) and actor.owns_native_launch_frame_token(token, bridge), "refused Time manager configuration preserves marker")
				suite.assert_true(not actor.bind_native_time_manager(foreign_player.time_manager) and actor.owns_native_launch_frame_token(token, bridge), "foreign actual Time manager refusal preserves binding and marker")
				suite.assert_true(actor.bind_native_time_manager(player.time_manager), "same actual Time manager may rebind outside mutation")
			else:
				suite.assert_true(not actor.configure_character_boss_exposure_replay_authority(null) and actor.owns_native_launch_frame_token(token, bridge), "null Replay authority refusal preserves marker")
				if attempt == 1:
					suite.assert_true(not actor.configure_character_boss_exposure_replay_authority(RefCounted.new()) and actor.owns_native_launch_frame_token(token, bridge), "foreign Replay authority refusal preserves bound marker")
				suite.assert_true(actor.configure_character_boss_exposure_replay_authority(replay) and actor.get("_exposure_replay_authority") == replay, "accepted Replay authority installs exact opaque owner")
			suite.assert_true(actor.get("_native_launch_frame_token") == null and not actor.owns_native_launch_frame_token(token, bridge) and not actor.publish_native_launch_frame(token, bridge), "accepted configuration or same binding revokes old token: " + configuration)
			suite.assert_true(bridge.rollback_frame(ticket), "configuration change preserves pre-weapon compensation: " + configuration)
			suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "configuration change compensates full typed state: " + configuration)
			suite.assert_equal(var_to_bytes(actor.elemental_status_runtime.transaction_snapshot()), status_before, "configuration change compensates exact status seed and floors: " + configuration)
	foreign_player.queue_free()


func _test_native_guard_counts(actor: Node2D, bridge: RefCounted) -> void:
	var original: RefCounted = actor.get("_launch_runtime")
	var before := var_to_bytes(actor.launch_runtime_snapshot())
	var counter := CountingBossRuntime.new()
	counter.configure_arena_origin(_point(actor.call("_native_arena_origin")), _point(actor.global_position))
	suite.assert_true(counter.configure(actor.get("_launch_definition"), actor.get("_launch_identity")).ok and counter.restore_snapshot(original.snapshot()), "counting actual Boss runtime delegates complete original configuration and restoration")
	actor.set("_launch_runtime", counter)
	var ticket: Dictionary = bridge.begin_frame(1)
	counter.before_match_calls = 0
	suite.assert_true(bridge.prepare_frame(ticket), "canonical native Actor commits with full delegated Boss live-state validation")
	suite.assert_equal(counter.before_match_calls, 2, "native Bridge retains exactly the original two complete before-state guards")
	var token: RefCounted = bridge.get("_active").records[0].actor_token
	counter.forge_geometry_reads = 0
	suite.assert_true(actor.publish_native_launch_frame(token, bridge), "canonical native publication still performs original live Forge geometry guard")
	suite.assert_equal(counter.forge_geometry_reads, 1, "native publication retains exactly one original current geometry guard")
	suite.assert_true(bridge.rollback_frame(ticket), "guard-count publication can still compensate original pre-weapon transaction")
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), before, "delegated guard-count fixture preserves complete actual Boss state")
	actor.set("_launch_runtime", original)


func _test_custom_fallback() -> void:
	var actor := (load("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn") as PackedScene).instantiate() as Node2D
	actor.set_script(ClaimingActor)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = Vector2(320, 180)
	var parser := EnemyDefinition.new()
	parser.configure(Content.enemy("shattered_sentinel"))
	var identity := Actions.identity()
	identity.seed = 42
	identity.hostile_source_id = "custom-native-claim"
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok, "custom fallback configures actual native definition")
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(340, 180)
	var effects := Effects.new()
	effects.configure("run-p15")
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "custom support claimant configures through original public contract")
	var custom_script: Script = actor.get_script()
	var canonical_actor_script: Script = LaunchHostileActor
	var original_path := custom_script.resource_path
	custom_script.take_over_path(canonical_actor_script.resource_path)
	var ticket: Dictionary = bridge.begin_frame(1)
	suite.assert_true(bridge.prepare_frame(ticket) and actor.native_preparations == 0 and not bridge.get("_active").records[0].native_actor_frame, "same-path custom script claiming support stays public fallback without native invocation")
	suite.assert_true(bridge.rollback_frame(ticket), "custom same-path fallback retains original checkpoint compensation")
	canonical_actor_script.take_over_path("res://scripts/enemies/launch/launch_hostile_actor.gd")
	custom_script.take_over_path(original_path)
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_legacy_lease_fallback() -> void:
	for path: String in ["res://scripts/enemies/launch/launch_summon_actor.gd", "res://scripts/enemies/launch/launch_ordinary_copy_actor.gd"]:
		var actor := (load("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn") as PackedScene).instantiate() as Node2D
		actor.set_script(load(path))
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(actor)
		if actor.has_method("supports_native_launch_frame_protocol"):
			suite.assert_true(not actor.call("supports_native_launch_frame_protocol"), "unmigrated summon/copy cannot inherit native support")
		var prepared: Dictionary = actor.prepare_launch_frame(1, Actions.context(1))
		suite.assert_true(not prepared.ok and prepared.context.field == "summon_lease", "legacy summon/copy retains authentic public lease refusal")
		actor.queue_free()
		await get_tree().process_frame


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
