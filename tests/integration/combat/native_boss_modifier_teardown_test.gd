extends "res://tests/integration/combat/void_auxiliary_native_test.gd"

const MODIFIER_CASES := [
	{"id": "void_throne", "scene": preload("res://data/content_packs/base/assets/bosses/launch/boss_void_throne.tscn"), "method": "sync_native_void_modifier", "source": "void_auxiliary:", "modifier": "status", "values": {"attack_multiplier": 0.85}},
	{"id": "time_sovereign", "scene": preload("res://data/content_packs/base/assets/bosses/launch/boss_time_sovereign.tscn"), "method": "sync_native_time_auxiliary_modifier", "source": "time_auxiliary:", "modifier": "mark", "values": {"time_damage_taken_multiplier": 1.15}},
	{"id": "forge_colossus", "scene": preload("res://data/content_packs/base/assets/bosses/launch/boss_forge_colossus.tscn"), "method": "sync_native_forge_modifier", "source": "forge_burn:", "modifier": "burn", "values": {"movement_multiplier": 1.0}},
]


func _run() -> void:
	suite = Suite.new()
	for row: Dictionary in MODIFIER_CASES:
		await _detached_modifier(row)
	await _detached_void_disposal()
	suite.finish(get_tree())


func _detached_modifier(row: Dictionary) -> void:
	var actor: Node2D = row.scene.instantiate()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var definition := Definition.new()
	suite.assert_true(definition.configure(Content.boss(row.id)).ok, "teardown fixture uses authentic " + row.id)
	var identity := {"run_id": "modifier-teardown", "hostile_source_id": "teardown-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}
	suite.assert_true(actor.configure_launch_definition(definition.runtime_projection(), identity).ok, "native modifier owner configures")
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"modifier-teardown")
	var source := StringName(str(row.source) + str(actor.hostile_source_id))
	var modifier := StringName(row.modifier)
	var key := "%s|%s" % [source, modifier]
	var foreign_source := StringName(str(row.source) + "foreign-owner")
	var foreign_key := "%s|%s" % [foreign_source, modifier]
	suite.assert_true(player.apply_floor_rule_modifier(source, modifier, &"apply", row.values), "same source owns exact native modifier")
	suite.assert_true(player.apply_floor_rule_modifier(foreign_source, modifier, &"apply", row.values), "foreign owner retains independent modifier")
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	remove_child(player)
	world.add_child(player)
	var before: Dictionary = player.floor_rule_effect_snapshot()
	suite.assert_true(not actor.call(row.method, player, "player:teardown"), "new modifier sync rejects another live World2D")
	suite.assert_equal(player.floor_rule_effect_snapshot(), before, "foreign World2D rejection preserves both owners")
	world.remove_child(player)
	add_child(player)
	remove_child(actor)
	suite.assert_true(not actor.call(row.method, player, "player:teardown"), "new modifier sync rejects a detached source without engine errors")
	suite.assert_equal(player.floor_rule_effect_snapshot(), before, "detached source cannot mutate current modifiers")
	player.configure_run(&"another-run")
	suite.assert_true(player.apply_floor_rule_modifier(source, modifier, &"apply", row.values), "different run owns its independent matching source key")
	var other_run: Dictionary = player.floor_rule_effect_snapshot()
	suite.assert_true(not actor.call(row.method, player, "player:teardown", true), "teardown refuses a different current run")
	suite.assert_equal(player.floor_rule_effect_snapshot(), other_run, "different run refusal preserves exact Player state")
	player.configure_run(&"modifier-teardown")
	player.apply_floor_rule_modifier(source, modifier, &"apply", row.values)
	player.apply_floor_rule_modifier(foreign_source, modifier, &"apply", row.values)
	suite.assert_true(actor.call(row.method, player, "player:teardown", true), "detached native owner clears only its same-run modifier")
	var cleared: Dictionary = player.floor_rule_effect_snapshot()
	suite.assert_true(not cleared.modifiers.has(key) and cleared.modifiers.has(foreign_key), "detached cleanup preserves foreign source ownership")
	suite.assert_true(actor.call(row.method, player, "player:teardown", true), "same-source cleanup is idempotent")
	suite.assert_equal(player.floor_rule_effect_snapshot(), cleared, "repeated cleanup preserves exact retained modifiers")
	remove_child(player)
	player.apply_floor_rule_modifier(source, modifier, &"apply", row.values)
	suite.assert_true(not actor.call(row.method, player, "player:teardown"), "applying effects refuses two detached nodes")
	suite.assert_true(actor.call(row.method, player, "player:teardown", true), "teardown clears same-run ownership after both nodes detach")
	suite.assert_true(not player.floor_rule_effect_snapshot().modifiers.has(key) and player.floor_rule_effect_snapshot().modifiers.has(foreign_key), "fully detached cleanup preserves foreign modifiers")
	actor.free()
	player.free()
	world.queue_free()
	await get_tree().process_frame


func _detached_void_disposal() -> void:
	var context := _open_case(true, Vector2(350, 180))
	_request(context, "voidking_devour")
	_frames(context, 135)
	var key := "void_auxiliary:%s|status" % str(context.actor.hostile_source_id)
	suite.assert_true(context.actor.native_void_auxiliary_snapshot().statuses.size() == 1 and context.player.floor_rule_effect_snapshot().modifiers.has(key), "authentic Devour installs a native owned debuff before detach")
	context.player.apply_floor_rule_modifier(&"foreign-status", &"retained", &"apply", {"movement_multiplier": 0.9})
	context.actor.get_parent().remove_child(context.actor)
	suite.assert_true(context.effects.dispose_native_effects(), "actual room disposal accepts detached surviving Boss owner")
	suite.assert_true(not context.player.floor_rule_effect_snapshot().modifiers.has(key), "actual disposal retires authentic source-owned Devour debuff")
	suite.assert_true(context.player.floor_rule_effect_snapshot().modifiers.has("foreign-status|retained"), "actual detached-owner disposal preserves foreign modifiers")
	suite.assert_true(context.effects.dispose_native_effects(), "actual effect disposal stays idempotent")
	context.actor.free()
	for key_to_free: String in ["player", "room", "root"]:
		context[key_to_free].queue_free()
	await get_tree().process_frame
