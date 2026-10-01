extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var a = SeedServiceScript.derive_seed(123, &"draft", 1, 2, 3)
	var b = SeedServiceScript.derive_seed(123, &"draft", 1, 2, 3)
	suite.assert_equal(a, b, "same seed inputs are deterministic")
	suite.assert_true(a != SeedServiceScript.derive_seed(123, &"combat", 1, 2, 3), "channels are isolated")
	suite.assert_true(a != SeedServiceScript.derive_seed(123, &"draft", 1, 2, 4), "roll indexes are isolated")
	suite.assert_true(a != SeedServiceScript.derive_seed(123, &"draft", 2, 2, 3), "floor indexes are isolated")
	suite.assert_true(a != SeedServiceScript.derive_seed(123, &"draft", 1, 3, 3), "room indexes are isolated")
	suite.assert_equal(
		SeedServiceScript.make_rng(123, &"draft", 1, 2, 3).randi(),
		SeedServiceScript.make_rng(123, &"draft", 1, 2, 3).randi(),
		"derived RNG streams reproduce"
	)
	suite.assert_equal(
		SeedServiceScript.derive_seed(-123, &"draft", 1, 2, 3),
		SeedServiceScript.derive_seed(-123, &"draft", 1, 2, 3),
		"negative run seeds are deterministic"
	)
	var node_seed := SeedServiceScript.derive_node_seed(
		7001,
		&"floor_time_rift",
		&"layer_03_left",
		&"room_template",
		0
	)
	var sibling_node_seed := SeedServiceScript.derive_node_seed(
		7001,
		&"floor_time_rift",
		&"layer_03_right",
		&"room_template",
		0
	)
	suite.assert_equal(
		node_seed,
		SeedServiceScript.derive_node_seed(
			7001,
			&"floor_time_rift",
			&"layer_03_left",
			&"room_template",
			0
		),
		"node channel is stable"
	)
	suite.assert_true(node_seed != sibling_node_seed, "sibling nodes own isolated channels")
	suite.assert_equal(
		node_seed,
		SeedServiceScript.derive_seed(
			7001,
			&"floor_plan_v1:floor_time_rift:layer_03_left:room_template",
			0,
			0,
			0
		),
		"node seeds stay inside the floor_plan_v1 floor domain"
	)
	suite.assert_true(
		node_seed
		!= SeedServiceScript.derive_node_seed(
			7001,
			&"floor_time_rift",
			&"layer_03_left",
			&"event_reference",
			0
		),
		"node subchannels are isolated"
	)
	var action_seed := SeedServiceScript.derive_weapon_action_seed(
		123,
		&"bow_launch_v1",
		&"scatter_shot",
		&"bow_scatter",
		17,
		0
	)
	suite.assert_equal(
		action_seed,
		SeedServiceScript.derive_weapon_action_seed(
			123,
			&"bow_launch_v1",
			&"scatter_shot",
			&"bow_scatter",
			17,
			0
		),
		"weapon action seeds reproduce from the complete stable context"
	)
	var isolated_action_seeds: Array[int] = [
		SeedServiceScript.derive_weapon_action_seed(124, &"bow_launch_v1", &"scatter_shot", &"bow_scatter", 17, 0),
		SeedServiceScript.derive_weapon_action_seed(123, &"bow_candidate_v1", &"scatter_shot", &"bow_scatter", 17, 0),
		SeedServiceScript.derive_weapon_action_seed(123, &"bow_launch_v1", &"arrow_rain", &"bow_scatter", 17, 0),
		SeedServiceScript.derive_weapon_action_seed(123, &"bow_launch_v1", &"scatter_shot", &"bow_arrow_rain", 17, 0),
		SeedServiceScript.derive_weapon_action_seed(123, &"bow_launch_v1", &"scatter_shot", &"bow_scatter", 18, 0),
		SeedServiceScript.derive_weapon_action_seed(123, &"bow_launch_v1", &"scatter_shot", &"bow_scatter", 17, 1),
	]
	for isolated_seed: int in isolated_action_seeds:
		suite.assert_true(action_seed != isolated_seed, "each weapon action seed dimension owns an isolated channel")
	suite.finish(get_tree())
