extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/narrative/narrative_runtime.gd") as Script
	suite.assert_true(implementation != null, "narrative candidate runtime exists")
	if implementation != null:
		_test_dialogue(implementation)
		_test_collections_and_hidden_lines(implementation)
		_test_choices_and_endings(implementation)
		_test_exposure(implementation)
		_test_closed_command_refusals(implementation)
	suite.finish(get_tree())


func _runtime(implementation: Script, catalog: RefCounted) -> RefCounted:
	var value: RefCounted = implementation.new()
	var configured: Dictionary = value.configure(_entries(), _sources(), catalog)
	suite.assert_true(configured.ok, "real narrative and source content configures: " + str(configured))
	return value


func _test_dialogue(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := Fixtures.profile(catalog)
	profile.statistics = {"finished_runs": 1, "victories": 0, "deaths": 1, "abandons": 0}
	profile.completed_boss_ids = ["forest_heart", "forge_colossus", "ruin_king", "time_sovereign", "void_throne"]
	for npc: Dictionary in _entries():
		if npc.definition_kind != "npc":
			continue
		var views: Dictionary = runtime.dialogue_view(profile, npc.npc_id)
		suite.assert_true(views.ok, "each NPC has a live dialogue projection")
		suite.assert_equal(views.context.nodes.size(), 13, "all thirteen authored nodes remain readable")
		for node: Dictionary in npc.dialogue_nodes:
			var choice: Dictionary = node.choices[-1]
			var command := {"command_id": "read-" + str(node.id), "kind": "narrative_dialogue", "npc_id": npc.npc_id, "node_id": node.id, "choice_id": choice.id}
			var before := profile.duplicate(true)
			var prepared: Dictionary = runtime.prepare_command(profile, command, profile.revision)
			suite.assert_true(prepared.ok, "authored NPC arc reaches node: " + str(node.id) + " " + str(prepared))
			if not prepared.ok:
				continue
			suite.assert_equal(profile, before, "dialogue preparation never farms live affinity")
			profile = prepared.context.candidate
			command.command_id += "-alternate"
			command.choice_id = node.choices[0].id
			suite.assert_true(not runtime.prepare_command(profile, command, profile.revision).ok, "one node cannot consume multiple alternative choices")
		suite.assert_equal(profile.npc_affinity[npc.npc_id], 100, "all eight authored arcs reach full affinity")
		suite.assert_true(profile.narrative_state.flags.has(npc.resolution_flag), "authored NPC resolution grants its flag")
	suite.assert_equal(profile.narrative_state.balance_choice_sources.size(), 3, "three different key choices produce exactly three balance sources")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(profile))
	suite.assert_equal(runtime.dialogue_view(parsed, "sibyl"), runtime.dialogue_view(profile, "sibyl"), "read/choice consumption survives physical JSON")
	suite.assert_true(not runtime.prepare_command(profile, {"command_id": "stale", "kind": "narrative_dialogue", "npc_id": "sibyl", "node_id": "sibyl_intro", "choice_id": "sibyl_intro_remember"}, 0).ok, "stale dialogue submission refuses")


func _test_collections_and_hidden_lines(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := _active_profile(catalog)
	profile.statistics = {"finished_runs": 1, "victories": 0, "deaths": 1, "abandons": 0}
	profile.completed_boss_ids = ["forest_heart", "forge_colossus", "ruin_king", "time_sovereign", "void_throne"]
	var early := {"command_id": "early-hidden", "kind": "narrative_collect", "source_receipt_id": "hidden_primordial_whispers_1"}
	suite.assert_true(not runtime.prepare_command(profile, early, profile.revision, _context(profile, "floor_ruins_of_remnant")).ok, "hidden story cannot skip its factual prerequisites")
	profile = _talk_intro(runtime, profile, "phia")
	for source: Dictionary in _sources():
		var command := {"command_id": "collect-" + str(source.source_receipt_id), "kind": "narrative_collect", "source_receipt_id": source.source_receipt_id}
		var context := _context(profile, source.floor_id)
		if source.source_kind == "heart_fragment":
			context.boss_ids = []
			suite.assert_true(not runtime.prepare_command(profile, command, profile.revision, context).ok, "heart source requires this run's canonical Boss fact")
			context.boss_ids = [source.requirements[0].id]
		var before := profile.duplicate(true)
		var result: Dictionary = runtime.prepare_command(profile, command, profile.revision, context)
		suite.assert_true(result.ok, "every authored source has a grant path: " + str(source.source_receipt_id))
		if result.ok:
			suite.assert_equal(profile, before, "source preparation is detached")
			profile = result.context.candidate
			command.command_id += "-reload"
			suite.assert_true(not runtime.prepare_command(profile, command, profile.revision, context).ok, "source reload never grants twice")
	suite.assert_equal(profile.narrative_state.heart_fragments.size(), 5, "five distinct canonical heart fragments grant")
	for row: Dictionary in _entries():
		if row.definition_kind in ["artifact", "environment_record"]:
			var result: Dictionary = runtime.prepare_command(profile, {"command_id": "collect-" + str(row.source_receipt_id), "kind": "narrative_collect", "source_receipt_id": row.source_receipt_id}, profile.revision, _context(profile, row.floor_id))
			suite.assert_true(result.ok, "all artifact/environment authored sources grant")
			if result.ok:
				profile = result.context.candidate
	for npc: Dictionary in _entries():
		if npc.definition_kind == "npc":
			profile = _advance_arc(runtime, profile, npc)
	for row: Dictionary in _entries():
		if row.definition_kind != "choice":
			continue
		var option := "listen" if row.choice_family == "vera" else "spare"
		var choice: Dictionary = runtime.prepare_command(profile, {"command_id": "reach-" + str(row.id), "kind": "narrative_choice", "definition_id": row.id, "choice_id": option}, profile.revision, _context(profile, row.floor_id, 100.0 - float(profile.narrative_state.vera_conversations) * 5.0))
		suite.assert_true(choice.ok, "hidden-ending choice fact has a real grant path")
		if choice.ok:
			profile = choice.context.candidate
	var exposure: Dictionary = runtime.prepare_void_observation(profile, {"run_id": "narrative-run", "launch_sequence": 1, "from_frame": 0, "through_frame": 18000, "void_active_frames": 18000}, profile.revision)
	suite.assert_true(exposure.ok, "hidden-ending exposure fact has a real native observation path")
	if exposure.ok:
		profile = exposure.context.candidate
	for row: Dictionary in _entries():
		if row.definition_kind != "hidden_line":
			continue
		for step: Dictionary in row.steps:
			var result: Dictionary = runtime.prepare_command(profile, {"command_id": "step-" + str(step.id), "kind": "narrative_collect", "source_receipt_id": step.source_receipt_id}, profile.revision, _context(profile, step.floor_id))
			suite.assert_true(result.ok, "every hidden line reaches all five steps: " + str(step.id) + " " + str(result))
			if result.ok:
				profile = result.context.candidate
		suite.assert_equal(profile.narrative_state.hidden_steps[row.storyline_id], 5, "hidden line completion is bounded at five")
		suite.assert_true(profile.narrative_state.flags.has(row.completion_flag), "completion grants authored hidden flag")
	suite.assert_equal(profile.narrative_state.artifacts.size(), 10, "all ten lore artifacts are distinct from run item slots")
	suite.assert_equal(profile.narrative_state.environment_records.size(), 21, "all twenty-one environmental records grant")
	var ending_view: Dictionary = runtime.ending_view(profile, {"run_id": "narrative-run", "launch_sequence": 1, "terminal_reason": "victory", "boss_ids": ["void_throne"]})
	var echo_available := false
	for ending: Dictionary in ending_view.context.endings:
		if ending.ending_id == "echo_of_primordial":
			echo_available = ending.eligible
	suite.assert_true(echo_available, "hidden ending is reachable through all authored domain grant paths")
	var bad_context := _context(profile, "floor_ruins_of_remnant")
	bad_context.run_id = "other-run"
	suite.assert_true(not runtime.prepare_command(profile, early, profile.revision, bad_context).ok, "other-run source facts refuse")
	suite.assert_true(not runtime.prepare_command(profile, {"command_id": "invented", "kind": "narrative_collect", "source_receipt_id": "invented-source"}, profile.revision, _context(profile, "floor_ruins_of_remnant")).ok, "unknown source identity refuses")
	var sources := _sources()
	sources[0].floor_id = "floor_unknown"
	suite.assert_true(not runtime.configure(_entries(), sources, catalog).ok, "invalid source configure clears authority")
	suite.assert_true(not runtime.dialogue_view(profile, "phia").ok, "cleared content cannot project stale views")


func _test_choices_and_endings(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := _active_profile(catalog)
	var context := _context(profile, "floor_throne_of_void")
	var defer := {"command_id": "defer", "kind": "narrative_choice", "definition_id": "choice_vera_1", "choice_id": "defer"}
	var before := profile.duplicate(true)
	var result: Dictionary = runtime.prepare_command(profile, defer, profile.revision, context)
	suite.assert_true(result.ok and result.context.deferred, "Vera defer is a valid nonpersistent choice")
	suite.assert_equal(profile, before, "defer does not consume source or apply temporary cost")
	for number: int in range(1, 6):
		var command := {"command_id": "vera-" + str(number), "kind": "narrative_choice", "definition_id": "choice_vera_" + str(number), "choice_id": "listen"}
		context = _context(profile, "floor_throne_of_void", 100.0 - 5.0 * (number - 1))
		var unaffordable := context.duplicate(true)
		unaffordable.max_hp = 5.0
		unaffordable.current_hp = 5.0
		suite.assert_true(not runtime.prepare_command(profile, command, profile.revision, unaffordable).ok, "invalid HP capacity leaves Vera step available")
		result = runtime.prepare_command(profile, command, profile.revision, context)
		suite.assert_true(result.ok, "each sequential Vera conversation prepares")
		if result.ok:
			profile = result.context.candidate
			suite.assert_equal(result.context.run_effect.amount, 5, "authored temporary cost is exactly five")
			suite.assert_equal(result.context.run_effect.after.max_hp, context.max_hp - 5.0, "HP projection is derived once from real capacity")
			suite.assert_true(result.context.run_effect.after.current_hp > 0.0, "temporary capacity cost cannot kill a living Player")
			command.command_id += "-duplicate"
			suite.assert_true(not runtime.prepare_command(profile, command, profile.revision, context).ok, "Vera source survives reload and cannot spend HP twice")
	suite.assert_equal(profile.npc_affinity.vera, 80, "five authored conversations grant eighty affinity")
	suite.assert_equal(profile.narrative_state.vera_conversations, 5, "Vera count is capped at five")
	for number: int in range(1, 6):
		var definition: Dictionary
		for row: Dictionary in _entries():
			if row.id == "choice_nemesis_" + str(number):
				definition = row
		result = runtime.prepare_command(profile, {"command_id": "nemesis-" + str(number), "kind": "narrative_choice", "definition_id": definition.id, "choice_id": "spare"}, profile.revision, _context(profile, definition.floor_id))
		suite.assert_true(result.ok, "five sequential Nemesis encounters prepare")
		if result.ok:
			profile = result.context.candidate
	suite.assert_equal(profile.narrative_state.nemesis_choices, ["spare", "spare", "spare", "spare", "spare"], "Nemesis order is preserved")
	var facts := {"run_id": "narrative-run", "launch_sequence": 1, "terminal_reason": "victory", "boss_ids": ["void_throne"]}
	result = runtime.prepare_command(profile, {"command_id": "choose-ending", "kind": "narrative_ending", "ending_id": "shattered_freedom"}, profile.revision, facts)
	suite.assert_true(result.ok, "authentic victory fallback ending prepares")
	if not result.ok:
		return
	profile = result.context.candidate
	suite.assert_true(profile.narrative_state.endings.has("shattered_freedom"), "ending and interrupted credits are separate durable facts")
	suite.assert_true(profile.narrative_state.credits_completed.is_empty(), "choosing an ending does not pretend credits ran")
	suite.assert_true(not runtime.prepare_command(profile, {"command_id": "choose-twice", "kind": "narrative_ending", "ending_id": "shattered_freedom"}, profile.revision, facts).ok, "one terminal victory permits one final choice")
	profile.npc_affinity.elara = 80
	profile.narrative_state.heart_fragments = ["floor_plane_forge", "floor_ruins_of_remnant", "floor_throne_of_void", "floor_time_rift", "floor_void_forest"]
	suite.assert_true(not runtime.prepare_command(profile, {"command_id": "renamed-other-ending", "kind": "narrative_ending", "ending_id": "return_of_order"}, profile.revision, facts).ok, "renaming a command cannot choose a different eligible ending for the same victory")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(profile))
	result = runtime.prepare_command(parsed, {"command_id": "credits", "kind": "narrative_credits", "ending_id": "shattered_freedom"}, parsed.revision)
	suite.assert_true(result.ok, "interrupted credits resume after physical JSON reload")
	if result.ok:
		suite.assert_equal(result.context.candidate.narrative_state.credits_completed, ["shattered_freedom"], "credit completion is durable and distinct")
		profile = result.context.candidate
		suite.assert_true(not runtime.prepare_command(profile, {"command_id": "credits-again", "kind": "narrative_credits", "ending_id": "shattered_freedom"}, profile.revision).ok, "renamed credits completion cannot duplicate the fact")
	profile.launch_sequence = 2
	profile.active_launch_receipt.sequence = 2
	profile.active_launch_receipt.run_id = "narrative-next"
	facts.run_id = "narrative-next"
	facts.launch_sequence = 2
	result = runtime.prepare_command(profile, {"command_id": "second-victory", "kind": "narrative_ending", "ending_id": "return_of_order"}, profile.revision, facts)
	suite.assert_true(result.ok, "a later authentic victory can discover another eligible ending")
	if result.ok:
		profile = result.context.candidate
		suite.assert_equal(profile.narrative_state.endings, ["return_of_order", "shattered_freedom"], "endings form a finite gallery collection")
		var markers := 0
		for source: String in profile.narrative_state.consumed_sources:
			if source.begins_with("ending-choice:"):
				markers += 1
		suite.assert_equal(markers, 1, "later victory replaces one current ending watermark")


func _test_exposure(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := _active_profile(catalog)
	var before := profile.duplicate(true)
	var observation := {"run_id": "narrative-run", "launch_sequence": 1, "from_frame": 0, "through_frame": 18000, "void_active_frames": 18000}
	var result: Dictionary = runtime.prepare_void_observation(profile, observation, profile.revision)
	suite.assert_true(result.ok, "native active frame observation prepares cumulative exposure")
	if not result.ok:
		return
	suite.assert_equal(profile, before, "exposure preparation is detached")
	profile = result.context.candidate
	suite.assert_equal(profile.narrative_state.void_exposure_frames, 18000, "five minutes of active Void gameplay are counted")
	suite.assert_true(not runtime.prepare_void_observation(profile, observation, profile.revision).ok, "exposure duplicate refuses without per-frame history")
	for frame: int in range(18001, 19001):
		observation.from_frame = frame - 1
		observation.through_frame = frame
		observation.void_active_frames = 0
		result = runtime.prepare_void_observation(profile, observation, profile.revision)
		if not result.ok:
			suite.assert_true(false, "non-Void/menu/pause frames can advance the watermark without exposure")
			break
		profile = result.context.candidate
	suite.assert_equal(profile.narrative_state.void_exposure_frames, 18000, "unexposed elapsed frames add no active exposure")
	suite.assert_equal(profile.narrative_state.consumed_sources.size(), 1, "one bounded current watermark replaces thousands of frame receipts")
	suite.assert_equal(profile.completed_command_ids.size(), 0, "native frame accounting cannot exhaust command history")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(profile))
	suite.assert_true(not runtime.prepare_void_observation(parsed, observation, parsed.revision).ok, "exposure watermark survives JSON reload")
	observation.from_frame = 19000
	observation.through_frame = 19001
	observation.void_active_frames = 2
	suite.assert_true(not runtime.prepare_void_observation(profile, observation, profile.revision).ok, "more active frames than elapsed frames refuse")
	observation.void_active_frames = 1
	observation.run_id = "fake-run"
	suite.assert_true(not runtime.prepare_void_observation(profile, observation, profile.revision).ok, "other-run active frame facts refuse")
	for mutation: String in ["duplicate", "noncanonical"]:
		var corrupt := profile.duplicate(true)
		if mutation == "duplicate":
			corrupt.narrative_state.consumed_sources.append("void-watermark:1:19001")
			corrupt.narrative_state.consumed_sources.sort()
		else:
			corrupt.narrative_state.consumed_sources = ["void-watermark:01:19000"]
		observation.run_id = "narrative-run"
		suite.assert_true(not runtime.prepare_void_observation(corrupt, observation, corrupt.revision).ok, "ambiguous or noncanonical exposure watermark refuses")
	profile.launch_sequence = 2
	profile.active_launch_receipt.sequence = 2
	profile.active_launch_receipt.run_id = "narrative-next"
	var next_observation := {"run_id": "narrative-next", "launch_sequence": 2, "from_frame": 0, "through_frame": 1, "void_active_frames": 1}
	result = runtime.prepare_void_observation(profile, next_observation, profile.revision)
	suite.assert_true(result.ok, "next native launch begins at zero and replaces old exposure watermark")
	if result.ok:
		profile = result.context.candidate
		suite.assert_equal(profile.narrative_state.consumed_sources, ["void-watermark:2:1"], "only one current launch exposure watermark is retained")
		suite.assert_equal(profile.narrative_state.void_exposure_frames, 18001, "new launch retains cumulative exposure")
		suite.assert_true(not runtime.prepare_void_observation(profile, observation, profile.revision).ok, "retired launch cannot add unseen old frames")


func _test_closed_command_refusals(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime := _runtime(implementation, catalog)
	var profile := _active_profile(catalog)
	var command := {"command_id": "closed-choice", "kind": "narrative_choice", "definition_id": "choice_vera_1", "choice_id": "listen"}
	var before := profile.duplicate(true)
	for mutation: String in ["extra", "bool", "fraction", "capacity", "current"]:
		var context := _context(profile, "floor_throne_of_void")
		match mutation:
			"extra": context.reward = 100
			"bool": context.launch_sequence = true
			"fraction": context.launch_sequence = 1.5
			"capacity": context.max_hp = true
			"current": context.current_hp = -1
		suite.assert_true(not runtime.prepare_command(profile, command, profile.revision, context).ok, "closed native context refuses malformed value")
		suite.assert_equal(profile, before, "context refusal preserves caller state")
	for mutation: String in ["extra", "bool", "reserved"]:
		var malformed := command.duplicate(true)
		match mutation:
			"extra": malformed.grant_affinity = 100
			"bool": malformed.choice_id = true
			"reserved": malformed.command_id = "narrative-source:invented"
		suite.assert_true(not runtime.prepare_command(profile, malformed, profile.revision, _context(profile, "floor_throne_of_void")).ok, "closed public command refuses malformed or reserved value")
		suite.assert_equal(profile, before, "command refusal preserves caller state")
	profile.revision = 2147483647
	before = profile.duplicate(true)
	suite.assert_true(not runtime.prepare_command(profile, command, profile.revision, _context(profile, "floor_throne_of_void")).ok, "revision overflow refuses before any effect")
	suite.assert_equal(profile, before, "overflow leaves caller unchanged")
	profile.revision = 0
	for index: int in range(4096):
		profile.completed_command_ids.append("full-%04d" % index)
	before = profile.duplicate(true)
	suite.assert_true(not runtime.prepare_command(profile, command, profile.revision, _context(profile, "floor_throne_of_void")).ok, "bounded public command history refuses overflow")
	suite.assert_equal(profile, before, "full history leaves caller unchanged")


func _talk_intro(runtime: RefCounted, profile: Dictionary, npc_id: String) -> Dictionary:
	var result: Dictionary = runtime.prepare_command(profile, {"command_id": "intro-" + npc_id, "kind": "narrative_dialogue", "npc_id": npc_id, "node_id": npc_id + "_intro", "choice_id": npc_id + "_intro_remember"}, profile.revision)
	suite.assert_true(result.ok, "intro has a real grant path")
	return result.context.candidate if result.ok else profile


func _advance_arc(runtime: RefCounted, profile: Dictionary, npc: Dictionary) -> Dictionary:
	for node: Dictionary in npc.dialogue_nodes:
		if profile.narrative_state.consumed_sources.has("dialogue:" + str(node.id)):
			continue
		var result: Dictionary = runtime.prepare_command(profile, {"command_id": "reach-" + str(node.id), "kind": "narrative_dialogue", "npc_id": npc.npc_id, "node_id": node.id, "choice_id": node.choices[-1].id}, profile.revision)
		suite.assert_true(result.ok, "NPC affinity advances through authored choices")
		if result.ok:
			profile = result.context.candidate
	return profile


func _active_profile(catalog: RefCounted) -> Dictionary:
	var profile := Fixtures.profile(catalog)
	profile.launch_sequence = 1
	profile.active_launch_receipt = {"schema_id": "meta_launch_receipt_v1", "sequence": 1, "run_id": "narrative-run", "difficulty": "normal", "seed": 73, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["rewind", "stop"], "projection_digest": "a".repeat(64)}
	return profile


func _context(profile: Dictionary, floor_id: String, max_hp: float = 100.0) -> Dictionary:
	return {"run_id": "narrative-run", "launch_sequence": int(profile.launch_sequence), "floor_id": floor_id, "boss_ids": [], "max_hp": max_hp, "current_hp": max_hp}


func _entries() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/narrative_definitions.json"))


func _sources() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/narrative_sources.json"))
