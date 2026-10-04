extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const ProjectionScript := preload("res://scripts/progression/meta_run_projection.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")
const Run := preload("res://scripts/application/run_state.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Generator := preload("res://scripts/dungeon/floor_plan_generator.gd")
const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	var implementation = load("res://scripts/progression/encounter_settlement_adapter.gd")
	suite.assert_true(implementation != null, "native Encounter-to-settlement source adapter exists")
	if implementation == null:
		suite.finish(get_tree())
		return
	var catalog: RefCounted = Factory.load_base().context.catalog
	var profile = Profile.new()
	profile.configure(catalog)
	var projection: Dictionary = ProjectionScript.from_profile(profile.snapshot(), catalog).context.projection
	var launch := {"schema_id": "meta_launch_receipt_v1", "sequence": 1, "run_id": "native-material-run", "difficulty": "normal", "seed": 42, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "projection_digest": projection.projection_digest}
	var state = Run.new()
	state.reset_domain({"milestone": "LAUNCH", "seed": 42}, launch.run_id)
	var floors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/floors.json"))
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	var generated: Dictionary = Generator.new().generate(42, floors[0], templates)
	suite.assert_true(state.configure_floor_plan(generated.plan, floors[0], templates).ok, "native source test uses actual generated floor plan")
	var node := _enter_combat(state)
	suite.assert_true(not node.is_empty(), "generated route supplies a visited combat node")
	state.phase = Phase.Value.COMBAT_ACTIVE
	state.run_time_ms = 1000
	state.resources = {"meta_run_projection": projection}
	# This recipe is an explicit adapter fixture; production P15 recipe authoring is separate.
	var spawn := {"id": "native_elite", "enemy_id": "shattered_sentinel", "spawn_slot_id": "enemy_wave_primary", "spawn_offset": {"x": 0.0, "y": 0.0}, "elite": true, "affix_ids": ["frenzy"], "mechanism_ids": []}
	var definition := {"id": "encounter_profile_ruins_adapter_v1.sentinel_trial", "floor_id": floors[0].id, "recipe_id": "sentinel_trial", "room_type": node.room_type, "waves": [{"id": "native_wave", "delay_frames": 0, "warning_frames": 30, "spawns": [spawn]}]}
	var encounter = Encounter.new()
	var configured: Dictionary = encounter.configure(definition, {"run_id": launch.run_id, "room_id": node.id, "runtime_frame": 0, "encounter_generation": 1})
	suite.assert_true(configured.ok, "registered role comes from the closed Encounter recipe: %s" % str(configured))
	for frame: int in range(1, 32):
		encounter.advance_frame(frame)
	var adapter: RefCounted = implementation.new()
	var policy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/meta_material_policy.json"))
	suite.assert_true(not implementation.new().configure(RefCounted.new(), encounter, launch, policy).ok, "foreign run participant refuses without a protocol crash")
	suite.assert_true(not implementation.new().configure(state, RefCounted.new(), launch, policy).ok, "foreign encounter participant refuses without a protocol crash")
	suite.assert_true(not implementation.new().configure(state, Encounter.new(), launch, policy).ok, "unconfigured native encounter refuses atomically")
	for field: String in ["run_id", "character_id", "projection_digest"]:
		var foreign_launch := launch.duplicate(true)
		foreign_launch[field] = "foreign"
		suite.assert_true(not implementation.new().configure(state, encounter, foreign_launch, policy).ok, "foreign launch %s refuses" % field)
	for role: String in ["boss", "support"]:
		var invalid_policy := policy.duplicate(true)
		invalid_policy[role].chronos_shards = 1
		suite.assert_true(not implementation.new().configure(state, encounter, launch, invalid_policy).ok, "non-principal %s material refuses" % role)
	var open_policy := policy.duplicate(true)
	open_policy.elite.unexpected = 1
	suite.assert_true(not implementation.new().configure(state, encounter, launch, open_policy).ok, "unknown nested material policy fields refuse")
	suite.assert_true(adapter.configure(state, encounter, launch, policy).ok, "native adapter binds matching run, node and authored policy")
	var parser = Enemy.new()
	parser.configure(Content.enemy())
	var actor := (load("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn") as PackedScene).instantiate()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var identity := {"run_id": launch.run_id, "hostile_source_id": "hostile:native-elite", "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}
	var foreign_identity := identity.duplicate(true)
	foreign_identity.seed = 43
	actor.configure_launch_definition(parser.runtime_projection("elite"), foreign_identity)
	suite.assert_true(not adapter.register_actor("native_elite", actor).ok, "foreign native seed cannot bind a material principal")
	var foreign_definition := parser.runtime_projection("elite")
	foreign_definition.max_hp += 1.0
	actor.configure_launch_definition(foreign_definition, identity)
	suite.assert_true(not adapter.register_actor("native_elite", actor).ok, "self-consistent but unauthored native stats cannot bind a principal")
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection("elite"), identity).ok, "source is a real configured native hostile actor")
	actor.hostile_source_id = &"hostile:property-alias"
	suite.assert_true(not adapter.register_actor("native_elite", actor).ok, "actor property alias cannot replace the native runtime source identity")
	actor.hostile_source_id = StringName(identity.hostile_source_id)
	suite.assert_true(not adapter.register_actor("undeclared", actor).ok, "native actor requires an exact pending spawn")
	suite.assert_true(adapter.register_actor("native_elite", actor).ok, "native registration binds one declared principal spawn")
	suite.assert_true(not adapter.register_actor("native_elite", actor).ok, "duplicate registration cannot duplicate counted role")
	var bound_encounter: Dictionary = encounter.snapshot()
	var foreign_encounter_identity: Dictionary = bound_encounter.identity.duplicate(true)
	foreign_encounter_identity.encounter_generation = 2
	encounter.configure(definition, foreign_encounter_identity)
	suite.assert_equal(adapter.retry_pending_deaths().code, &"ROOM_RETIRED", "same-room replacement generation cannot inherit native material authority")
	encounter.configure(definition, bound_encounter.identity)
	suite.assert_true(encounter.restore_snapshot(bound_encounter), "test restores the original Encounter generation and roster")
	var receipt := "hostile_defeat:%s" % (launch.run_id + "|hostile:native-elite").sha256_text().substr(0, 40)
	actor.hostile_final_death.emit(actor.hostile_source_id, receipt)
	suite.assert_equal(adapter.receipts(), [], "manually emitted live-actor signal cannot mint material")
	suite.assert_equal(encounter.alive_count(), 1, "forged final-death signal cannot clear registered actor")
	var original_events: Array = state.events.duplicate(true)
	state.events.resize(4096)
	var damage := Damage.from_plan({"run_id": launch.run_id, "target_id": "hostile:native-elite", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 1000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["attack:heavy"], "can_crit": false})
	actor.get_node("HealthComponent").take_damage(damage)
	suite.assert_equal(adapter.receipts(), [], "capacity refusal cannot publish a partial material source")
	suite.assert_equal(encounter.alive_count(), 1, "capacity refusal retains counted principal until atomic retry")
	suite.assert_equal(adapter.pending_sources().size(), 1, "authenticated native death is retained for an explicit retry")
	suite.assert_equal(adapter.retry_pending_deaths().code, &"RETENTION_REFUSED", "capacity refusal is observable by the coordinator")
	var pending: Array = adapter.pending_sources()
	pending[0].payload.chronos_shards = 999
	suite.assert_equal(adapter.pending_sources()[0].payload.chronos_shards, 1, "pending-source views are detached")
	state.events = original_events
	state.suspended = true
	suite.assert_equal(adapter.retry_pending_deaths().code, &"RETENTION_REFUSED", "suspended run retains rather than spends material")
	state.suspended = false
	var original_revision: int = state.revision
	state.revision = 2147483647
	suite.assert_equal(adapter.retry_pending_deaths().code, &"RETENTION_REFUSED", "revision overflow retains rather than drops a native receipt")
	state.revision = original_revision
	state.phase = Phase.Value.DEFEAT
	suite.assert_equal(adapter.retry_pending_deaths().code, &"ROOM_RETIRED", "retired run cannot migrate a pending source into a terminal room")
	state.phase = Phase.Value.COMBAT_ACTIVE
	actor.queue_free()
	await get_tree().process_frame
	suite.assert_true(not is_instance_valid(actor), "native actor is released before source retry")
	suite.assert_true(adapter.retry_pending_deaths().ok, "retained authenticated death can commit after Actor retirement")
	suite.assert_equal(encounter.alive_count(), 0, "real final death removes the counted native principal")
	var receipts: Array = adapter.receipts()
	suite.assert_equal(receipts.size(), 1, "real native death seals one material source into RunState")
	if receipts.size() == 1:
		suite.assert_equal(receipts[0].payload.chronos_shards, 1, "elite policy adds one shard only at later settlement")
		suite.assert_equal(receipts[0].payload.actor_role, "principal", "material role comes from Encounter registration")
		suite.assert_equal(receipts[0].payload.defeat_receipt, receipt, "native death receipt is preserved without renaming")
	suite.assert_true(adapter.retry_pending_deaths().ok, "repeated retry is a successful no-op")
	suite.assert_equal(adapter.receipts(), receipts, "repeated native terminal signal cannot seal the source twice")
	var detached: Array = adapter.receipts()
	if not detached.is_empty():
		detached[0].payload.chronos_shards = 999
	suite.assert_equal(adapter.receipts(), receipts, "source projection never exposes mutable RunState references")
	state.phase = Phase.Value.DEFEAT
	state.result = {"result": "death"}
	var value := profile.snapshot()
	value.launch_sequence = 1
	value.active_launch_receipt = launch
	var authority = Settlement.new()
	var bosses: Dictionary = {}
	for index: int in range(5):
		bosses[Settlement.Envelope.FLOOR_IDS[index]] = Settlement.BOSS_ORDER[index]
	authority.configure(catalog, bosses)
	var terminal := state.snapshot()
	var settled: Dictionary = authority.prepare(value, launch, terminal, receipts)
	suite.assert_true(settled.ok, "death in an unfinished visited room settles actual defeated principal material: %s" % str(settled))
	if settled.ok:
		suite.assert_equal(settled.context.receipt.shards, 4, "one native elite shard joins genuine three-shard death guarantee")
		suite.assert_true(authority.prepare(value, launch, JSON.parse_string(JSON.stringify(terminal)), JSON.parse_string(JSON.stringify(receipts))).ok, "native receipt survives actual JSON terminal reload")
		var oversized_receipts: Array = receipts.duplicate(true)
		oversized_receipts[0].payload.chronos_shards = 6
		var oversized_terminal := terminal.duplicate(true)
		for event: Dictionary in oversized_terminal.events:
			if event.get("type") == Settlement.SOURCE_TYPE:
				event.receipt.payload.chronos_shards = 6
		suite.assert_true(not authority.prepare(value, launch, oversized_terminal, oversized_receipts).ok, "matching retained and submitted sources still refuse above-policy material")
	var before := state.snapshot()
	suite.assert_equal(adapter.retry_pending_deaths().code, &"ROOM_RETIRED", "terminal retry refuses explicitly")
	suite.assert_equal(state.snapshot(), before, "terminal run cannot accept another native source")
	adapter.detach()
	if is_instance_valid(actor):
		actor.queue_free()
	await get_tree().process_frame
	await _ordinary_case(suite, implementation, launch, projection, floors[0], templates, generated.plan, policy)
	suite.finish(get_tree())


func _ordinary_case(suite: RefCounted, implementation: Script, launch: Dictionary, projection: Dictionary, floor_definition: Dictionary, templates: Array, plan: Dictionary, policy: Dictionary) -> void:
	var state = Run.new()
	state.reset_domain({"milestone": "LAUNCH", "seed": 42}, launch.run_id)
	state.configure_floor_plan(plan, floor_definition, templates)
	var node := _enter_combat(state)
	state.phase = Phase.Value.COMBAT_ACTIVE
	state.resources = {"meta_run_projection": projection}
	var spawn := {"id": "ordinary", "enemy_id": "shattered_sentinel", "spawn_slot_id": "enemy_wave_primary", "spawn_offset": {"x": 0.0, "y": 0.0}, "elite": false, "affix_ids": [], "mechanism_ids": []}
	var second_spawn := spawn.duplicate(true)
	second_spawn.id = "ordinary_second"
	var definition := {"id": "encounter_profile_ruins_adapter_v1.ordinary_trial", "floor_id": floor_definition.id, "recipe_id": "ordinary_trial", "room_type": node.room_type, "waves": [{"id": "ordinary_wave", "delay_frames": 0, "warning_frames": 30, "spawns": [spawn, second_spawn]}]}
	var encounter = Encounter.new()
	encounter.configure(definition, {"run_id": launch.run_id, "room_id": node.id, "runtime_frame": 0, "encounter_generation": 1})
	for frame: int in range(1, 32):
		encounter.advance_frame(frame)
	var adapter: RefCounted = implementation.new()
	suite.assert_true(adapter.configure(state, encounter, launch, policy).ok, "ordinary test binds the same native policy")
	var parser = Enemy.new()
	parser.configure(Content.enemy())
	var actor := (load("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn") as PackedScene).instantiate()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var identity := {"run_id": launch.run_id, "hostile_source_id": "hostile:ordinary", "next_generation_floor": 1, "runtime_frame": 0, "seed": 42}
	actor.configure_launch_definition(parser.runtime_projection(), identity)
	suite.assert_true(adapter.register_actor("ordinary", actor).ok, "ordinary principal registers without elite material")
	var alias_identity := identity.duplicate(true)
	alias_identity.hostile_source_id = "hostile:ordinary-second"
	actor.configure_launch_definition(parser.runtime_projection(), alias_identity)
	suite.assert_equal(adapter.register_actor("ordinary_second", actor).code, &"ACTOR_ALREADY_BOUND", "one native object cannot occupy two counted principal spawns")
	actor.configure_launch_definition(parser.runtime_projection(), identity)
	state.events.resize(4096)
	actor.get_node("HealthComponent").take_damage(Damage.from_plan({"run_id": launch.run_id, "target_id": "hostile:ordinary", "hostile_source_id": "player:1", "attack_generation": 1, "action_token": 1, "amount": 1000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false}))
	suite.assert_equal(encounter.alive_count(), 0, "zero-pay ordinary death retires even when material event retention is full")
	suite.assert_equal(adapter.receipts(), [], "ordinary death never mints the elite reward")
	suite.assert_equal(adapter.pending_sources(), [], "zero-pay death has no retry backlog")
	adapter.detach()
	actor.queue_free()
	await get_tree().process_frame


func _enter_combat(state: RefCounted) -> Dictionary:
	for _step: int in range(16):
		var edge: Dictionary = {}
		for candidate: Dictionary in state.floor_plan.edges:
			if candidate.source_node_id == state.floor_plan.current_node_id and not candidate.locked:
				edge = candidate
				break
		if edge.is_empty():
			return {}
		state.select_floor_edge(StringName(edge.id))
		var node: Dictionary = state.current_floor_node()
		if node.room_type in ["combat", "elite"]:
			return node
		state.complete_current_floor_node(node.id)
	return {}
