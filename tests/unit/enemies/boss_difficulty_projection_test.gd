extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Catalog := preload("res://scripts/modes/boss_rush_catalog.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Runtime := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")


func _ready() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var catalog := Catalog.new()
	suite.assert_true(catalog.configure(registry), "authored five-boss catalog configures")
	var api := Definition.new()
	if not api.has_method("difficulty_projection"):
		suite.assert_true(false, "validated native Boss difficulty projection exists")
		suite.finish(get_tree())
		return
	for index: int in range(5):
		var base: Dictionary = catalog.stage(index).runtime_definition
		var scaled: Dictionary = api.call("difficulty_projection", base, 1.2, 1.1)
		suite.assert_true(scaled.ok, "canonical difficulty projection configures " + str(base.id))
		if not scaled.ok:
			continue
		var projected: Dictionary = scaled.definition
		suite.assert_true(is_equal_approx(projected.max_hp, base.max_hp * 1.2), "HP scale reaches runtime definition")
		for action_index: int in range(base.actions.size()):
			for hit_index: int in range(base.actions[action_index].hit_schedule.size()):
				suite.assert_true(is_equal_approx(projected.actions[action_index].hit_schedule[hit_index].damage, base.actions[action_index].hit_schedule[hit_index].damage * 1.1), "primary attack damage scales")
		for phase: String in base.mechanisms.phase_damage_overrides:
			for action: String in base.mechanisms.phase_damage_overrides[phase]:
				suite.assert_true(is_equal_approx(projected.mechanisms.phase_damage_overrides[phase][action], base.mechanisms.phase_damage_overrides[phase][action] * 1.1), "phase override damage scales")
		for field: String in ["aftershock_damage", "wall_collapse_damage", "seed_pool_tick_damage", "cage_pulse_damage", "cage_collapse_damage", "echo_final_damage", "slam_pool_tick_damage", "slam_burn_damage", "lava_pool_tick_damage", "devour_inner_damage", "scepter_burn_damage", "tear_final_damage", "vortex_inner_damage"]:
			if base.mechanisms.has(field):
				suite.assert_true(is_equal_approx(projected.mechanisms[field], base.mechanisms[field] * 1.1), "auxiliary outgoing damage scales " + field)
		var identity := {"run_id": "difficulty-native", "hostile_source_id": "difficulty-" + str(base.id), "next_generation_floor": 1, "runtime_frame": 0, "seed": 31}
		var runtime := Runtime.new()
		suite.assert_true(runtime.configure(projected, identity).ok and is_equal_approx(runtime.snapshot().mechanism_state.hp_current, base.max_hp * 1.2), "actual Boss runtime accepts scaled HP")
		var cold := Runtime.new()
		suite.assert_true(cold.configure(projected, identity).ok and cold.restore_snapshot(runtime.snapshot()), "scaled runtime restores against same projection")
		var malformed := projected.duplicate(true)
		malformed.max_hp += 1.0
		suite.assert_true(not Definition.new().configure_runtime_projection(malformed).ok, "unsealed HP mutation refuses")
		malformed = projected.duplicate(true)
		malformed.difficulty.hp_multiplier = 4.0
		suite.assert_true(not Definition.new().configure_runtime_projection(malformed).ok, "oversize difficulty refuses")
		var json: Dictionary = JSON.parse_string(JSON.stringify(projected))
		suite.assert_true(Definition.new().configure_runtime_projection(json).ok, "physical JSON projection round trip validates")
	suite.finish(get_tree())
