extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_profile_fixtures.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")
const Run := preload("res://scripts/application/run_state.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Generator := preload("res://scripts/dungeon/floor_plan_generator.gd")
const ResourceAuthority := preload("res://scripts/events/event_resource_authority.gd")
const BOSS_ORDER := ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]


func _ready() -> void:
	var suite = Suite.new()
	var catalog = Catalog.new()
	suite.assert_true(catalog.configure(Fixtures.meta_entries()).ok, "Meta content configures")
	var authority = Settlement.new()
	var boss_map: Dictionary = {}
	for index: int in range(5):
		boss_map[Envelope.FLOOR_IDS[index]] = BOSS_ORDER[index]
	suite.assert_true(authority.configure(catalog, boss_map), "settlement uses canonical authored Boss associations")
	var swapped: Dictionary = boss_map.duplicate()
	swapped[Envelope.FLOOR_IDS[0]] = BOSS_ORDER[1]
	swapped[Envelope.FLOOR_IDS[1]] = BOSS_ORDER[0]
	suite.assert_true(not Settlement.new().configure(catalog, swapped), "swapped canonical Boss associations refuse configuration")
	for row: Array in [[0, false, "normal", 3, 0], [2, false, "normal", 63, 4], [5, true, "normal", 235, 10], [5, true, "hard", 352, 10], [5, true, "nightmare", 587, 10]]:
		var fixture := _fixture(catalog, row[0], row[1], row[2])
		var before: Dictionary = fixture.profile.duplicate(true)
		var result: Dictionary = authority.prepare(fixture.profile, fixture.launch, fixture.run, fixture.receipts)
		suite.assert_true(result.ok, "authentic terminal %s prepares: %s" % [str(row), str(result)])
		if not result.ok:
			continue
		suite.assert_equal(result.context.receipt.shards, row[3], "whole settlement rounds difficulty exactly once")
		suite.assert_equal(result.context.receipt.imprints, row[4], "first canonical Boss grants two imprints once")
		suite.assert_equal(result.context.candidate.soul_reserve, 5, "seventeen remaining soul retains floor(thirty percent)")
		suite.assert_equal(fixture.profile, before, "preparation never writes profile currency")
		var profile = Profile.new()
		suite.assert_true(profile.configure(catalog, result.context.candidate), "candidate has a valid strict persistent profile")
		suite.assert_true(not authority.prepare(result.context.candidate, fixture.launch, fixture.run, fixture.receipts).ok, "retired launch cannot pay a second settlement")
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(fixture.run))
		var repeat: Dictionary = authority.prepare(fixture.profile, fixture.launch, parsed, JSON.parse_string(JSON.stringify(fixture.receipts)))
		suite.assert_true(repeat.ok, "actual JSON terminal facts remain readable")
		if repeat.ok:
			suite.assert_equal(repeat.context, result.context, "JSON terminal restoration produces the identical candidate and receipt")
		if row[0] > 0:
			var experienced: Dictionary = fixture.profile.duplicate(true)
			experienced.completed_boss_ids = Catalog.BOSS_IDS.duplicate()
			var known: Dictionary = authority.prepare(experienced, fixture.launch, fixture.run, fixture.receipts)
			suite.assert_true(known.ok, "previously resolved Bosses still permit genuine run settlement")
			if known.ok:
				suite.assert_equal(known.context.receipt.imprints, 0, "a later launch cannot repeat first-Boss imprints")
	var fixture := _fixture(catalog, 2, false, "hard")
	var principal := "ruins-material-principal"
	var defeat := "hostile_defeat:%s" % ("settle-1|" + principal).sha256_text().substr(0, 40)
	var material := _source("material", fixture.run.floor_plan.floor_id, fixture.run.floor_plan.current_node_id, {"actor_role": "principal", "principal_source_id": principal, "defeat_receipt": defeat, "chronos_shards": 4, "existential_imprints": 1})
	fixture.run.events.append({"type": "meta_settlement_source_v1", "receipt": material})
	fixture.receipts.append(material)
	var granted: Dictionary = authority.prepare(fixture.profile, fixture.launch, fixture.run, fixture.receipts)
	suite.assert_true(granted.ok, "material receipt belongs to an actual cleared room and terminal ledger: %s" % str(granted))
	if granted.ok:
		suite.assert_equal(granted.context.receipt.shards, 100, "material shards join the single difficulty rounding")
		suite.assert_equal(granted.context.receipt.imprints, 5, "material imprints are not difficulty multiplied")
	for mutation: String in ["duplicate", "missing", "invented", "summon", "wrong_run", "wrong_boss", "not_terminal", "projection", "overflow", "negative_soul", "abandon", "not_played", "wrong_seed", "wrong_difficulty", "wrong_loadout", "unvisited", "duplicate_ledger", "fractional_material", "renamed_material", "foreign_defeat"]:
		var bad := fixture.duplicate(true)
		match mutation:
			"duplicate": bad.receipts.append(bad.receipts[0].duplicate(true))
			"missing": bad.receipts.pop_back()
			"invented": bad.receipts[-1].source_id = "unrecorded-source"
			"summon":
				bad.receipts[-1].payload.actor_role = "summon"
				bad.run.events[-1].receipt = bad.receipts[-1].duplicate(true)
			"wrong_run": bad.run.run_id = "foreign-run"
			"wrong_boss":
				bad.receipts[0].payload.boss_id = "void_throne"
				for event: Dictionary in bad.run.events:
					if event.get("type") == "meta_settlement_source_v1" and event.receipt.source_id == bad.receipts[0].source_id:
						event.receipt = bad.receipts[0].duplicate(true)
			"not_terminal": bad.run.phase = Phase.Value.COMBAT_ACTIVE
			"projection": bad.run.resources.meta_run_projection.projection_digest = "0".repeat(64)
			"overflow": bad.profile.chronos_shards = Catalog.MAX_VALUE
			"negative_soul": bad.run.resources.resource.resources.soul_energy = -1
			"abandon": bad.run.result.result = "abandon"
			"not_played": bad.run.run_time_ms = 0
			"wrong_seed": bad.run.run_seed += 1
			"wrong_difficulty": bad.run.config.difficulty = "normal"
			"wrong_loadout": bad.run.config.weapon_id = "staff"
			"unvisited":
				bad.receipts[-1].node_id = "unvisited-room"
				bad.run.events[-1].receipt = bad.receipts[-1].duplicate(true)
			"duplicate_ledger": bad.run.events.append(bad.run.events[-1].duplicate(true))
			"fractional_material":
				bad.receipts[-1].payload.chronos_shards = 0.5
				bad.run.events[-1].receipt = bad.receipts[-1].duplicate(true)
			"renamed_material":
				var renamed: Dictionary = bad.receipts[-1].duplicate(true)
				renamed.source_id = "renamed-native-defeat"
				bad.receipts.append(renamed)
				bad.run.events.append({"type": "meta_settlement_source_v1", "receipt": renamed.duplicate(true)})
			"foreign_defeat":
				bad.receipts[-1].payload.defeat_receipt = "hostile_defeat:" + "0".repeat(40)
				bad.run.events[-1].receipt = bad.receipts[-1].duplicate(true)
		var prior: Dictionary = bad.profile.duplicate(true)
		suite.assert_true(not authority.prepare(bad.profile, bad.launch, bad.run, bad.receipts).ok, "invalid %s refuses settlement" % mutation)
		suite.assert_equal(bad.profile, prior, "invalid input cannot mint or rewrite currency")
	var later: Dictionary = fixture.profile.duplicate(true)
	later.unlocked_nodes = ["W-07", "W-08"]
	var frozen: Dictionary = authority.prepare(later, fixture.launch, fixture.run, fixture.receipts)
	suite.assert_true(frozen.ok, "later profile purchases do not replace the frozen launch projection")
	if frozen.ok:
		suite.assert_equal(frozen.context.candidate.soul_reserve, 5, "retention belongs to launch-time effects")
	var legacy: Dictionary = fixture.profile.duplicate(true)
	legacy.active_launch_receipt = {}
	legacy.launch_sequence = 0
	var imported: Dictionary = authority.import_legacy_statistics(legacy, fixture.run, "legacy-terminal-1")
	suite.assert_true(imported.ok, "legacy terminal without a launch receipt imports statistics only")
	if imported.ok:
		suite.assert_equal(imported.context.candidate.chronos_shards, 0, "legacy summary cannot fabricate shards")
		suite.assert_equal(imported.context.candidate.existential_imprints, 0, "legacy summary cannot fabricate first-Boss imprints")
		suite.assert_true(not authority.import_legacy_statistics(imported.context.candidate, fixture.run, "legacy-terminal-1").ok, "legacy statistics import is once per durable source")
		suite.assert_true(not authority.import_legacy_statistics(imported.context.candidate, fixture.run, "renamed-legacy-terminal").ok, "renaming legacy import source cannot count the same run twice")
	suite.finish(get_tree())


func _fixture(catalog: RefCounted, completed: int, victory: bool, difficulty: String) -> Dictionary:
	var profile = Profile.new()
	profile.configure(catalog)
	var value: Dictionary = profile.snapshot()
	var projection: Dictionary = MetaProjection.from_profile(value, catalog).context.projection
	var launch := {"schema_id": "meta_launch_receipt_v1", "sequence": 1, "run_id": "settle-1", "difficulty": difficulty, "seed": 20261004, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "projection_digest": projection.projection_digest}
	value.launch_sequence = 1
	value.active_launch_receipt = launch.duplicate(true)
	var state = Run.new()
	state.reset_domain({"milestone": "LAUNCH", "seed": launch.seed, "difficulty": difficulty}, launch.run_id)
	var floors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/floors.json"))
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	var sources: Array = []
	for index: int in range(mini(completed + 1, 5)):
		var generated: Dictionary = Generator.new().generate(launch.seed, floors[index], templates)
		state.configure_floor_plan(generated.plan, floors[index], templates)
		for _step: int in range(16):
			var edge: Dictionary = {}
			for possible: Dictionary in state.floor_plan.edges:
				if possible.source_node_id == state.floor_plan.current_node_id and not possible.locked:
					edge = possible
					break
			if edge.is_empty():
				break
			state.select_floor_edge(StringName(edge.id))
			state.complete_current_floor_node(state.floor_plan.current_node_id)
			if state.floor_plan.current_node_id == state.floor_plan.boss_node_id:
				state.append_completed_floor()
				var source := _source("boss", floors[index].id, state.floor_plan.boss_node_id, {"actor_role": "principal", "boss_id": BOSS_ORDER[index]})
				sources.append(source)
				state.events.append({"type": "meta_settlement_source_v1", "receipt": source.duplicate(true)})
				break
			if index == completed:
				break
	state.phase = Phase.Value.VICTORY if victory else Phase.Value.DEFEAT
	state.result = {"result": "victory" if victory else "death"}
	state.run_time_ms = 1000
	var resource = ResourceAuthority.new()
	resource.configure({"soul_energy": 17})
	state.resources = {"resource": resource.snapshot(), "meta_run_projection": projection}
	# This domain fixture retains the historical Launch shape, before event participants.
	var terminal: Dictionary = state.snapshot()
	terminal.erase("dungeon_event_runtime")
	return {"profile": value, "launch": launch, "run": terminal, "receipts": sources}


func _source(kind: String, floor_id: String, node_id: String, payload: Dictionary) -> Dictionary:
	var identity: String = payload.get("defeat_receipt", payload.get("boss_id", ""))
	var source_id := "meta_%s:%s" % [kind, ("settle-1|1|%s|%s|%s" % [floor_id, node_id, identity]).sha256_text().substr(0, 40)]
	return {"schema_id": "meta_settlement_source_v1", "source_id": source_id, "run_id": "settle-1", "launch_sequence": 1, "floor_id": floor_id, "node_id": node_id, "kind": kind, "payload": payload}
