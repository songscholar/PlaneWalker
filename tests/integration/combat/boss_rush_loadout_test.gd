extends "res://tests/integration/save/boss_rush_checkpoint_test.gd"

const CASES := [
	["wanderer", "sword", ["stop", "rewind"]],
	["time_guardian", "gauntlets", ["stop", "accelerate"]],
	["void_walker", "bow", ["stop", "rift"]],
	["primordial_knight", "gun", ["rewind", "accelerate"]],
	["time_lord", "staff", ["rewind", "rift"]],
	["time_lord", "sword", ["accelerate", "rift"]],
]


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	for index: int in range(CASES.size()):
		var fixture := _fixture("loadout-%d" % index)
		var flow := _flow(fixture)
		var request := REQUEST.duplicate(true)
		request.character_id = CASES[index][0]
		request.weapon_id = CASES[index][1]
		request.time_abilities = CASES[index][2].duplicate()
		var label := str(CASES[index])
		_suite.assert_true(flow.start(request).ok, "selected native challenge loadout launches " + label)
		var player: Node2D = flow.current_player()
		var boss: Node2D = flow.current_boss()
		player.set_physics_process(false)
		player.global_position = boss.global_position + Vector2(42, 0)
		await get_tree().physics_frame
		_suite.assert_true(player.advance_action_frame({"aim": Vector2.LEFT}), "native combat establishes selected action frame " + label)
		_suite.assert_true(player.try_action(&"weapon_primary"), "real selected weapon accepts primary command " + label)
		for frame: int in range(150):
			if frame == 40:
				player.call("_submit_weapon_intent", &"weapon_primary", &"released")
			_suite.assert_true(player.advance_action_frame({"aim": player.global_position.direction_to(boss.global_position)}), "native selected weapon and hostile commit accepted frame " + label)
			await get_tree().physics_frame
		_suite.assert_true(boss.health.current_hp < boss.health.max_hp, "real selected weapon damages bound native Boss " + label)
		_suite.assert_true(player.try_action(&"time_slot_1"), "real first selected time ability casts against native Boss " + label)
		for _frame: int in range(240):
			_suite.assert_true(player.advance_action_frame(), "selected time ability and hostile commit accepted frame " + label)
		_suite.assert_true(player.try_action(&"time_slot_2"), "real second selected time ability casts against native Boss " + label)
		for _frame: int in range(30):
			_suite.assert_true(player.advance_action_frame(), "second time ability commits native frame " + label)
		_suite.assert_true(flow.snapshot().elapsed_frames == 421, "challenge timer uses every actual committed combat frame " + label)
		boss.health.lose_health(100000, player)
		await get_tree().process_frame
		await get_tree().process_frame
		_suite.assert_true(flow.snapshot().status == "STAGE_CLEAR", "selected weapon/time native combat yields authenticated durable stage " + label)
		await _dispose(flow)
	_suite.finish(get_tree())
