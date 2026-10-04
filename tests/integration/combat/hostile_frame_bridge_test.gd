extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const ActorScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ActorFixture := preload("res://tests/unit/enemies/launch_enemy_runtime_test.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")


class HitInjectingBridge extends "res://scripts/enemies/launch/hostile_frame_bridge.gd":
	var before_hostile_preparation: Callable

	func prepare_frame(ticket: Dictionary) -> bool:
		if before_hostile_preparation.is_valid():
			before_hostile_preparation.call()
		return super.prepare_frame(ticket)


class SealRejectingBridge extends "res://scripts/enemies/launch/hostile_frame_bridge.gd":
	var rollback_calls := 0

	func seal_frame_publication(_publication: Dictionary) -> bool:
		return false

	func rollback_frame(ticket: Dictionary) -> bool:
		rollback_calls += 1
		return super.rollback_frame(ticket)


class EffectDouble extends RefCounted:
	var reject_commit := false
	var rejected_publication := false
	var publications := 0
	var commits := 0
	var rollback_count := 0
	var preparation_context: Dictionary = {}
	var prepared_batches: Array = []
	var _committed := false

	func prepare_effects(batches: Array, context: Dictionary) -> Dictionary:
		preparation_context = context.duplicate()
		prepared_batches = batches.duplicate(true)
		return {"ok": true, "ticket": {"frame": context.runtime_frame}}

	func can_commit(_ticket: Dictionary) -> bool:
		return not _committed

	func commit(_ticket: Dictionary) -> Dictionary:
		if reject_commit:
			return {"ok": false}
		commits += 1
		_committed = true
		return {"ok": true}

	func rollback(_ticket: Dictionary) -> bool:
		rollback_count += 1
		_committed = false
		return true

	func can_publish(_ticket: Dictionary) -> bool:
		return _committed and not rejected_publication

	func publish_effect_observations(_ticket: Dictionary) -> bool:
		if not _committed:
			return false
		publications += 1
		_committed = false
		return true


var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/hostile_frame_bridge.gd") as Script
	suite.assert_true(implementation != null, "P15 HostileFrameBridge exists")
	if implementation != null:
		await _test_frame_start_checkpoint_compensation(implementation)
		await _test_detached_publication(implementation)
		await _test_same_frame_death(implementation)
		await _test_player_optional_boundary(implementation)
		await _test_tracked_native_hits_are_atomic()
		await _test_native_lifecycle_and_next_wave()
		await _test_real_hostile_effect_frame(implementation)
		await _test_irreversible_seal_failure()
	suite.finish(get_tree())


func _actors() -> Array:
	var player := PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(120, 100)
	var actor := ActorScene.instantiate()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var identity := Actions.identity()
	identity.seed = 42
	suite.assert_true(actor.configure_launch_definition(ActorFixture.definition(), identity).ok, "bridge native actor configures")
	actor.global_position = Vector2(100, 100)
	return [player, actor]


func _damage(player: Node, amount: float = 10.0, hit_index: int = 0) -> RefCounted:
	return Damage.from_plan({
		"run_id": "run-p15", "target_id": "hostile:test-a", "hostile_source_id": "player:1",
		"attack_generation": 1, "action_token": 1, "source_generation": 1,
		"hit_index": hit_index,
		"amount": amount, "damage_type": Damage.DamageType.PHYSICAL,
		"attacker": player, "source": player, "tags": [], "can_crit": false,
	})


func _test_frame_start_checkpoint_compensation(implementation: Script) -> void:
	var nodes := _actors()
	var player: Node = nodes[0]
	var actor: Node = nodes[1]
	var effect := EffectDouble.new()
	effect.reject_commit = true
	var registry := Registry.new()
	var bridge: RefCounted = implementation.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effect), "bridge binds strict native participants")
	var before: Dictionary = actor.launch_runtime_snapshot()
	var damaged: Array = []
	actor.get_node("HealthComponent").damaged.connect(func(amount: float, hp: float): damaged.append([amount, hp]))
	var ticket: Dictionary = bridge.begin_frame(1)
	suite.assert_true(not ticket.is_empty(), "bridge captures actors before Player weapon/world updates")
	var forged := ticket.duplicate(true)
	forged.runtime_frame = 2
	suite.assert_true(not bridge.prepare_frame(forged) and not bridge.rollback_frame(forged), "forged frame ticket cannot prepare or consume compensation")
	actor.get_node("HealthComponent").take_damage(_damage(player))
	actor.apply_time_stop_source(&"weapon-hit:stop", 2.0 / 60.0)
	suite.assert_true(actor.get_node("HealthComponent").current_hp < before.health.current_hp, "weapon hit changes actual target before hostile preparation")
	player.global_position = Vector2(140, 100)
	suite.assert_true(not bridge.prepare_frame(ticket), "effect commit refusal rejects after actor candidates commit")
	suite.assert_equal(effect.preparation_context.targets["player:1"].global_position, Vector2(140, 100), "hostile effects observe post-movement Player position")
	suite.assert_true(bridge.rollback_frame(ticket), "late refusal compensates all frame-start participants")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "compensation restores pre-weapon health, ledger, controls, movement, and action clocks")
	suite.assert_equal(damaged, [], "rejected frame leaks no target damage signal")
	suite.assert_equal(registry.snapshot(), [], "rejected frame restores frame-start threat registry")
	suite.assert_true(not bridge.rollback_frame(ticket), "consumed compensation cannot restore twice")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_detached_publication(implementation: Script) -> void:
	var nodes := _actors()
	var player: Node = nodes[0]
	var actor: Node = nodes[1]
	var effect := EffectDouble.new()
	var bridge: RefCounted = implementation.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effect), "publication bridge configures")
	var damaged: Array = []
	actor.get_node("HealthComponent").damaged.connect(func(amount: float, hp: float): damaged.append([amount, hp]))
	var observed_hits: Array = []
	var hit_observer := func(info: RefCounted, target: Node, _amount: float):
		if target == actor:
			observed_hits.append(actor.get_node("HealthComponent").published_damage_observation_context(info))
	EventBus.hit_confirmed.connect(hit_observer)
	var ticket: Dictionary = bridge.begin_frame(1)
	actor.get_node("HealthComponent").take_damage(_damage(player))
	actor.get_node("HealthComponent").take_damage(_damage(player, 10.0, 1))
	suite.assert_true(bridge.prepare_frame(ticket), "bridge prepares actual post-movement action and effect candidates")
	suite.assert_equal(damaged, [], "successful candidate still buffers native observations")
	suite.assert_equal(observed_hits, [], "public hit facts remain buffered before sibling acceptance")
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	suite.assert_true(not publication.is_empty(), "bridge produces detached publication candidate")
	suite.assert_true(bridge.finalize_frame_publication(publication), "all hostile observers detach without publishing")
	suite.assert_equal(damaged, [], "hostile finalization preserves global no-observer boundary")
	suite.assert_equal(effect.publications, 0, "hostile effect facts wait for Player siblings")
	suite.assert_true(bridge.seal_frame_publication(publication), "accepted global frame retires compensation checkpoints")
	bridge.publish_prepared_frame()
	suite.assert_equal(damaged.size(), 2, "accepted global frame publishes both target hits once")
	suite.assert_equal(observed_hits.size(), 2, "accepted public hit facts preserve every original settlement")
	if observed_hits.size() == 2:
		suite.assert_equal([observed_hits[0].hp_before, observed_hits[0].hp_after], [80.0, 70.0], "first deferred hit retains its own HP transition")
		suite.assert_equal([observed_hits[1].hp_before, observed_hits[1].hp_after], [70.0, 60.0], "second deferred hit retains its own HP transition")
	suite.assert_equal(actor.get_node("HealthComponent").published_damage_observation_context(_damage(player)), {}, "observer context expires outside matching callbacks")
	suite.assert_equal(effect.publications, 1, "accepted global frame publishes effects once")
	bridge.publish_prepared_frame()
	suite.assert_equal(damaged.size(), 2, "repeated publication is idempotent")
	suite.assert_true(not bridge.rollback_frame(ticket), "published irreversible frame cannot roll back")
	EventBus.hit_confirmed.disconnect(hit_observer)
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_same_frame_death(implementation: Script) -> void:
	var nodes := _actors()
	var player: Node = nodes[0]
	var actor: Node = nodes[1]
	var effect := EffectDouble.new()
	var bridge: RefCounted = implementation.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effect), "death bridge configures")
	var deaths: Array = []
	actor.hostile_final_death.connect(func(source_id: StringName, receipt_id: String): deaths.append([source_id, receipt_id]))
	var ticket: Dictionary = bridge.begin_frame(1)
	actor.get_node("HealthComponent").take_damage(_damage(player, 1000.0))
	suite.assert_equal(deaths, [], "weapon lethal hit defers final encounter receipt")
	suite.assert_true(bridge.prepare_frame(ticket), "same-frame dead actor prepares terminal cancellation instead of rejecting Player frame")
	if not effect.prepared_batches.is_empty():
		suite.assert_equal(effect.prepared_batches[0].batch.hit_facts, [], "same-frame death produces no new hostile damage")
	var publication: Dictionary = bridge.prepare_frame_publication(ticket)
	suite.assert_true(bridge.finalize_frame_publication(publication), "same-frame death finalizes without publishing")
	suite.assert_true(bridge.seal_frame_publication(publication), "same-frame death seals with all Player siblings")
	bridge.publish_prepared_frame()
	suite.assert_equal(deaths.size(), 1, "same-frame death publishes one actual encounter receipt")
	suite.assert_true(actor.launch_runtime_snapshot().runtime.terminal, "same-frame death commits terminal domain cleanup")
	suite.assert_true(bridge.is_ready_for_frame(2), "terminal actor cannot block the next authoritative frame")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_player_optional_boundary(implementation: Script) -> void:
	var nodes := _actors()
	var player: Node = nodes[0]
	var actor: Node = nodes[1]
	suite.assert_true(player.has_method("configure_hostile_frame_participant"), "real Player supports an optional hostile frame participant")
	if player.has_method("configure_hostile_frame_participant"):
		var effect := EffectDouble.new()
		var bridge: RefCounted = implementation.new()
		suite.assert_true(bridge.configure(player, Registry.new(), [actor], effect), "Player frame bridge configures")
		suite.assert_true(player.configure_hostile_frame_participant(bridge), "Player binds the live hostile participant")
		var before: Dictionary = actor.launch_runtime_snapshot()
		suite.assert_true(player.advance_action_frame(), "Player and hostile advance through one accepted fixed frame")
		suite.assert_equal(actor.launch_runtime_snapshot().runtime.runtime_frame, before.runtime.runtime_frame + 1, "optional participant advances at the same authoritative Player clock")
		suite.assert_equal(effect.publications, 1, "Player global frame publishes hostile facts once")
		var accepted_actor: Dictionary = actor.launch_runtime_snapshot()
		var accepted_player: Dictionary = player.weapon_replay_snapshot()
		player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
		suite.assert_true(not player.advance_action_frame(), "late World commit failure refuses the complete Player/hostile frame")
		suite.assert_equal(actor.launch_runtime_snapshot(), accepted_actor, "late World failure restores exact frame-start hostile state")
		suite.assert_equal(player.weapon_replay_snapshot(), accepted_player, "late World failure restores exact frame-start Player state")
		suite.assert_equal(effect.publications, 1, "late World failure leaks no public hostile effects")
		player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
		suite.assert_true(player.advance_action_frame(), "compensated Player and hostile retry the same frame")
		suite.assert_equal(effect.publications, 2, "accepted retry publishes only once")
		suite.assert_true(player.configure_hostile_frame_participant(null), "idle Player detaches retired hostile participant")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_tracked_native_hits_are_atomic() -> void:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	var profile: Dictionary = {}
	for value: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/weapon_runtime_profiles.json")):
		if value.id == "sword_launch_v1":
			profile = value
	suite.assert_true(player.configure_loadout({
		"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer",
		"weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal", "seed": 42, "weapon_profile": profile,
	}), "native hit fixture configures actual Sword runtime")
	suite.assert_true(player.configure_run(&"run-p15"), "tracked native hits share actual run identity")
	player.global_position = Vector2(120, 100)
	suite.assert_true(player.advance_action_frame() and player.try_action(&"weapon_primary"), "actual Sword action enters HOLD")
	for _frame: int in range(30):
		suite.assert_true(player.advance_action_frame(), "actual Sword earns full charge through fixed frames")
	suite.assert_true(player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "actual Sword full charge releases")
	var guard := 90
	while str(player.weapon_replay_snapshot().phase) != "ACTIVE" and guard > 0:
		suite.assert_true(player.advance_action_frame(), "actual Sword advances to live payload")
		guard -= 1
	suite.assert_true(guard > 0, "tracked native hits use a committed ACTIVE Sword action")
	var identity: Dictionary = player.call("_current_weapon_replay_fact_identity")
	suite.assert_true(not identity.is_empty(), "actual action owns token and generation without private fact seeding")
	var actor := ActorScene.instantiate()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var actor_identity := Actions.identity()
	actor_identity.seed = 42
	actor_identity.runtime_frame = int(player.get("_runtime_frame"))
	suite.assert_true(actor.configure_launch_definition(ActorFixture.definition(), actor_identity).ok, "native target joins actual Player clock")
	actor.global_position = Vector2(100, 100)
	actor.set_meta("stable_target_id", 701)
	actor.set_meta("weakpoint_active", true)
	var health := actor.get_node("HealthComponent")
	var bridge := HitInjectingBridge.new()
	var effects := EffectDouble.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "tracked hit bridge configures")
	suite.assert_true(player.configure_hostile_frame_participant(bridge), "actual Player binds tracked native targets")
	var mastery: Array = []
	var mastery_observer := func(_weapon: StringName, _family: StringName, mastery_id: StringName, _action: StringName, _token: int, _generation: int, _target: int, _context: Dictionary): mastery.append(mastery_id)
	EventBus.weapon_mastery_confirmed.connect(mastery_observer)
	var public_hits: Array = []
	var hit_observer := func(info: RefCounted, target: Node, _amount: float):
		if target == actor:
			public_hits.append(health.published_damage_observation_context(info))
	EventBus.hit_confirmed.connect(hit_observer)
	var internal_facts: Array = []
	var early_mastery: Array = []
	bridge.before_hostile_preparation = func():
		for hit_index: int in range(2):
			var damage := Damage.from_plan({
				"run_id": "run-p15", "target_id": "hostile:test-a", "hostile_source_id": "player:1",
				"attack_generation": int(identity.generation), "action_token": int(identity.token),
				"source_generation": int(identity.generation), "hit_index": hit_index,
				"amount": 10.0, "damage_type": Damage.DamageType.PHYSICAL,
				"attacker": player, "source": player, "tags": ["weapon:sword", "attack:charged"], "can_crit": false,
			})
			health.take_damage(damage)
		internal_facts.assign(_combat_facts(player))
		early_mastery.assign(mastery)
	var before_actor: Dictionary = actor.launch_runtime_snapshot()
	var before_player: Dictionary = player.weapon_replay_snapshot()
	var before_events: Array = player.weapon_replay_events()
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not player.advance_action_frame(), "late World rejection compensates tracked native hits")
	suite.assert_equal(internal_facts.size(), 2, "both damage facts stage at original native settlement")
	if internal_facts.size() == 2:
		suite.assert_equal([internal_facts[0].data.hp_before, internal_facts[0].data.hp_after], [80.0, 70.0], "first staged Replay fact preserves first HP transition")
		suite.assert_equal([internal_facts[1].data.hp_before, internal_facts[1].data.hp_after], [70.0, 60.0], "second staged Replay fact preserves second HP transition")
	suite.assert_equal(early_mastery, [], "internal mastery settlement exposes no event before global acceptance")
	suite.assert_equal(mastery, [], "rejected native hit frame leaks no mastery observation")
	suite.assert_equal(public_hits, [], "rejected native hit frame leaks no public hit")
	suite.assert_equal(player.weapon_replay_snapshot(), before_player, "native hit rejection restores exact Player mastery and action state")
	suite.assert_equal(player.weapon_replay_events(), before_events, "native hit rejection removes staged Replay facts")
	suite.assert_equal(actor.launch_runtime_snapshot(), before_actor, "native hit rejection restores exact target Health and controls")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(), "same tracked native action retries accepted frame")
	suite.assert_equal(early_mastery, [], "accepted retry also delays mastery until seal")
	suite.assert_equal(mastery, [&"sword_charged_commitment"], "accepted retry publishes one mastery family claim")
	suite.assert_equal(public_hits.size(), 2, "accepted retry publishes each native hit once")
	suite.assert_equal(_combat_facts(player).size(), 2, "deferred public hit callback cannot duplicate internally recorded Replay facts")
	for context: Dictionary in public_hits:
		suite.assert_true(context.internal_observation_recorded, "public hit carries internally settled observation marker")
	EventBus.weapon_mastery_confirmed.disconnect(mastery_observer)
	EventBus.hit_confirmed.disconnect(hit_observer)
	player.configure_hostile_frame_participant(null)
	player.cancel_transient_actions()
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _combat_facts(player: Node) -> Array:
	var result: Array = []
	for event: Dictionary in player.weapon_replay_events():
		if event.event_type == "external_fact" and event.payload.fact_type == "combat_damage":
			result.append(event.payload.duplicate(true))
	return result


func _test_native_lifecycle_and_next_wave() -> void:
	var nodes := _actors()
	var player: Node = nodes[0]
	var actor: Node = nodes[1]
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	var bridge := HitInjectingBridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], EffectDouble.new()), "lifecycle bridge configures")
	suite.assert_true(player.configure_hostile_frame_participant(bridge), "lifecycle bridge binds live Player")
	suite.assert_true(not bridge.retire_actor("hostile:test-a"), "live hostile cannot silently leave roster")
	bridge.before_hostile_preparation = func(): actor.get_node("HealthComponent").take_damage(_damage(player, 1000.0))
	suite.assert_true(player.advance_action_frame(), "accepted lethal Player frame retires native roster")
	bridge.before_hostile_preparation = Callable()
	await get_tree().create_timer(0.3).timeout
	suite.assert_true(not is_instance_valid(actor), "published native death releases corpse after bounded presentation")
	for _frame: int in range(5):
		suite.assert_true(player.advance_action_frame(), "freed terminal actor cannot block subsequent Player frames")
	var next_actor := ActorScene.instantiate()
	next_actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(next_actor)
	next_actor.global_position = Vector2(100, 100)
	var identity := Actions.identity()
	identity.hostile_source_id = "hostile:test-b"
	identity.seed = 43
	identity.runtime_frame = int(player.get("_runtime_frame"))
	suite.assert_true(next_actor.configure_launch_definition(ActorFixture.definition(), identity).ok, "next wave installs current accepted clock")
	suite.assert_true(bridge.register_actor(next_actor), "idle bridge registers next native wave")
	suite.assert_true(not bridge.register_actor(next_actor), "duplicate live source cannot join twice")
	suite.assert_true(player.advance_action_frame(), "Player and next native wave advance together")
	suite.assert_equal(next_actor.launch_runtime_snapshot().runtime.runtime_frame, int(player.get("_runtime_frame")), "new wave advances at authoritative Player frame")
	player.configure_hostile_frame_participant(null)
	next_actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_real_hostile_effect_frame(implementation: Script) -> void:
	var effect_script := load("res://scripts/enemies/launch/launch_hostile_effect_authority.gd") as Script
	suite.assert_true(effect_script != null, "bridge binds production hostile effect authority")
	if effect_script == null:
		return
	var nodes := _actors()
	var player: Node = nodes[0]
	var actor: Node = nodes[1]
	var health := player.get_node("HealthComponent")
	suite.assert_true(PhysicsServer2D.body_get_space(player.get_rid()) == player.get_world_2d().space, "manual native Player frames retain a registered collision body")
	health.current_hp = 100.0
	health.defense = 0.0
	var effects: RefCounted = effect_script.new()
	suite.assert_true(effects.configure("run-p15", 0), "real effect authority configures matching run clock")
	var registry := Registry.new()
	var bridge: RefCounted = implementation.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "real native actor and effects share frame bridge")
	suite.assert_true(player.configure_hostile_frame_participant(bridge), "actual Player accepts production effects")
	var hits: Array = []
	var observer := func(_info: RefCounted, target: Node, amount: float):
		if target == player:
			hits.append(amount)
	EventBus.hit_confirmed.connect(observer)
	var guard := 120
	while actor.launch_runtime_snapshot().runtime.action.phase == "IDLE" and guard > 0:
		suite.assert_true(player.advance_action_frame(), "native warning advances without Player damage")
		guard -= 1
	suite.assert_true(guard > 0, "seeded native action selects before bounded startup deadline")
	var hit_frame := int(actor.launch_runtime_snapshot().runtime.action.commit_frame) + 30
	while int(player.get("_runtime_frame")) < hit_frame - 1:
		suite.assert_true(player.advance_action_frame(), "native warning completes before scheduled hit")
	suite.assert_equal(health.current_hp, 100.0, "complete warning leaves real Player Health untouched")
	var before_actor: Dictionary = actor.launch_runtime_snapshot()
	var before_player: Dictionary = player.weapon_replay_snapshot()
	var before_registry: Array = registry.snapshot()
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not player.advance_action_frame(), "late World refusal compensates actual scheduled hostile damage")
	suite.assert_equal(health.current_hp, 100.0, "late refusal restores actual Player Health and damage ledger")
	suite.assert_equal(actor.launch_runtime_snapshot(), before_actor, "late refusal restores actual hostile clock")
	suite.assert_equal(player.weapon_replay_snapshot(), before_player, "late refusal restores complete Player weapon state")
	suite.assert_equal(registry.snapshot(), before_registry, "late refusal restores authoritative telegraph and claims")
	suite.assert_equal(hits, [], "late refusal publishes no hostile hit")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_true(player.advance_action_frame(), "real hostile action retries the exact scheduled frame")
	suite.assert_equal(health.current_hp, 88.0, "paired native sweep applies twelve damage once to actual Player")
	suite.assert_equal(hits, [12.0], "accepted native effect publishes one logical hit")
	var hit_position: Vector2 = player.global_position
	suite.assert_true(player.advance_action_frame(), "Player continues after native hit publication")
	suite.assert_true(player.global_position.distance_to(hit_position) > 0.0, "accepted hostile knockback moves the actual registered Player body")
	suite.assert_equal(health.current_hp, 88.0, "next active frame cannot duplicate scheduled hit")
	EventBus.hit_confirmed.disconnect(observer)
	player.configure_hostile_frame_participant(null)
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _test_irreversible_seal_failure() -> void:
	var nodes := _actors()
	var player: Node = nodes[0]
	var actor: Node = nodes[1]
	var effects := EffectDouble.new()
	var bridge := SealRejectingBridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "fatal-seal fixture binds complete participants")
	suite.assert_true(player.configure_hostile_frame_participant(bridge), "fatal-seal fixture binds actual Player")
	suite.assert_true(not player.advance_action_frame(), "unexpected post-World seal failure fails closed")
	suite.assert_equal(bridge.rollback_calls, 0, "irreversible World commit cannot trigger ordinary rollback")
	suite.assert_equal(int(player.get("_runtime_frame")), 1, "fatal seal retains already committed Player clock")
	suite.assert_equal(actor.launch_runtime_snapshot().runtime.runtime_frame, 1, "fatal seal retains already committed hostile clock")
	suite.assert_equal(player.world_payload_authority.replay_snapshot().last_runtime_frame, 1, "fatal seal retains irreversible World clock")
	suite.assert_equal(effects.publications, 0, "fatal seal exposes no partially accepted publication")
	suite.assert_true(not player.advance_action_frame(), "fatal seal blocks subsequent frame until reconstruction")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame
