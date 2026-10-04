extends Node

const RunnerScript := preload("res://tools/dungeon/dungeon_simulation_runner.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const CHARACTERS := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]
const WEAPONS := ["sword", "bow", "gun", "staff", "gauntlets"]
const TIME_PAIRS := [
	["stop", "rewind"], ["stop", "rift"], ["stop", "accelerate"],
	["rewind", "rift"], ["rewind", "accelerate"], ["rift", "accelerate"],
]
const FLOOR_RULES := [
	"rule_crumbling_ground", "rule_void_spores", "rule_temporal_distortion",
	"rule_forge_vents", "rule_collapsing_plane",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var cases := 0
	for character_id: String in CHARACTERS:
		for weapon_id: String in WEAPONS:
			for time_pair: Array in TIME_PAIRS:
				var runner = RunnerScript.new()
				var player: Node = PlayerScene.instantiate()
				player.process_mode = Node.PROCESS_MODE_DISABLED
				add_child(player)
				player.set_physics_process(false)
				player.get_node("TimeManager").set_process(false)
				player.get_node("RewindRecorder").set_process(false)
				var config: Dictionary = runner.launch_config(20261001, character_id, weapon_id, time_pair)
				var initialized: Dictionary = runner.initialize(config, player)
				var label := "%s/%s/%s+%s" % [character_id, weapon_id, time_pair[0], time_pair[1]]
				suite.assert_true(bool(initialized.get("ok", false)), "%s initializes: %s" % [label, initialized])
				if bool(initialized.get("ok", false)):
					var configured: bool = player.configure_loadout(runner.player_config())
					suite.assert_true(configured, "%s configures the real Player" % label)
					if configured:
						var result: Dictionary = await runner.run_five_floors(true)
						suite.assert_equal(result.get("failures"), [], "%s completes dungeon domains" % label)
						suite.assert_equal(result.get("floor_summaries", []).size(), 5, "%s reaches all five floors" % label)
						suite.assert_true(bool(result.get("victory", false)), "%s reaches terminal victory" % label)
						suite.assert_true(int(result.get("merchant_purchase_count", 0)) > 0, "%s purchases an authored offer" % label)
						suite.assert_true(int(result.get("event_consequence_count", 0)) > 0, "%s commits an authored event consequence" % label)
						suite.assert_true(bool(result.get("save_restored", false)), "%s restores physical Save" % label)
						suite.assert_true(bool(result.get("replay_restored", false)), "%s restores authenticated Replay" % label)
						suite.assert_true(bool(result.get("player_replay_restored", false)), "%s restores the real Player Replay" % label)
						for floor: Dictionary in result.get("floor_summaries", []):
							var floor_index := int(floor["floor_index"])
							suite.assert_equal(floor["rule_id"], FLOOR_RULES[floor_index], "%s exercises authored floor %d rule" % [label, floor_index + 1])
							suite.assert_true(int(floor["rule_effect_count"]) > 0, "%s floor %d production effects commit" % [label, floor_index + 1])
							if floor_index == 2:
								suite.assert_true(int(floor["rule_modifier_observation_count"]) > 0, "%s temporal distortion reaches physical Player modifiers" % label)
						var types: Array = result.get("room_types", [])
						for room_type: String in ["combat", "elite", "treasure", "shop", "event", "rest", "boss"]:
							suite.assert_true(types.has(room_type), "%s exercises %s room" % [label, room_type])
						cases += 1
						if cases % 30 == 0:
							print("P14 dungeon loadout matrix: %d / 150 complete" % cases)
						if not (result.get("failures", []) as Array).is_empty():
							player.queue_free()
							await get_tree().process_frame
							suite.finish(get_tree())
							return
				player.queue_free()
				await get_tree().process_frame
	suite.assert_equal(cases, 150, "all five characters, five weapons and six time pairs certify")
	suite.finish(get_tree())
