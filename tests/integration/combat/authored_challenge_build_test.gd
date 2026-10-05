extends "res://tests/integration/combat/authored_challenge_native_test.gd"


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var catalog := preload("res://scripts/modes/authored_challenge_catalog.gd").new()
	_suite.assert_true(catalog.configure(_registry), "authored Build suite loads canonical production definitions")
	var weapons := {}
	for definition: Dictionary in catalog.entries():
		var rich := _authored_flow(_daily_fixture("authored-rich-" + definition.id))
		var lean := _authored_flow(_daily_fixture("authored-lean-" + definition.id, false))
		var rich_start: Dictionary = rich.start(definition.id)
		var lean_start: Dictionary = lean.start(definition.id)
		_suite.assert_true(rich_start.ok and lean_start.ok, "actual authored fixed Build admits rich and lean ordinary Meta " + definition.weapon_id)
		if not rich_start.ok or not lean_start.ok:
			await _dispose(rich)
			await _dispose(lean)
			continue
		weapons[definition.weapon_id] = true
		rich.current_player().set_physics_process(false)
		lean.current_player().set_physics_process(false)
		lean.get("_stage").position = Vector2(1280, 0)
		_suite.assert_equal(rich.baseline_player_effects().health.max_hp, 100.0, "authored fixed Build standardizes native baseline before content effects")
		_suite.assert_equal(rich.current_player().reward_effect_snapshot(), lean.current_player().reward_effect_snapshot(), "ordinary Meta and ownership cannot alter authored native Build " + definition.weapon_id)
		var receipts: Array = rich.installed_build_receipts()
		_suite.assert_equal(receipts.size(), 5, "each authored native Build installs three items blessing and curse")
		for entry: Dictionary in receipts:
			_suite.assert_true(entry.receipt.operation_count > 0 and entry.receipt.before_snapshot != entry.receipt.after_snapshot, "every authored content choice commits a real native effect " + str(entry.definition_id))
		var player: Node2D = rich.current_player()
		var boss: Node2D = rich.current_boss()
		player.health.invulnerable = true
		player.global_position = boss.global_position + Vector2(42, 0)
		await get_tree().physics_frame
		_suite.assert_true(player.advance_action_frame({"aim": Vector2.LEFT}) and player.try_action(&"weapon_primary"), "authored selected weapon accepts actual native primary " + definition.weapon_id)
		for frame: int in range(150):
			if frame == 40:
				player.call("_submit_weapon_intent", &"weapon_primary", &"released")
			_suite.assert_true(player.advance_action_frame({"aim": player.global_position.direction_to(boss.global_position)}), "fixed authored weapon commits actual Player and hostile frame " + definition.weapon_id)
			await get_tree().physics_frame
		_suite.assert_true(boss.health.current_hp < boss.health.max_hp, "all authored selected weapons physically damage their real Boss %s/%s: %s" % [definition.weapon_id, definition.boss_ids[0], str({"hp": boss.health.current_hp, "max": boss.health.max_hp, "weapon": player.weapon_runtime.snapshot()})])
		_suite.assert_true(rich.abandon().ok and lean.abandon().ok, "fixed Build proof retires independent authored attempts")
		await _dispose(rich)
		await _dispose(lean)
	_suite.assert_equal(weapons.size(), 5, "native authored Build and physical weapon evidence covers all five weapons")
	for case: Dictionary in [{"id": "bow_precision", "losses": 7, "damage": 1.0, "heal": 1.0}, {"id": "staff_resolve", "losses": 1, "damage": 40.0, "heal": 0.0}]:
		var flow := _authored_flow(_daily_fixture("authored-objective-" + case.id))
		_suite.assert_true(flow.start(case.id).ok, "real native objective failure case admits fixed Build " + case.id)
		await _frames(3)
		for _loss: int in range(case.losses):
			flow.current_player().health.lose_health(case.damage)
			flow.current_player().health.heal(case.heal)
		await _kill_boss(flow)
		var result: Dictionary = flow.preview().history[case.id][-1]
		_suite.assert_true(result.status == "OBJECTIVE_FAILED" and not flow.preview().best.has(case.id), "actual damage or health objective failure never publishes fresh best " + case.id)
		_suite.assert_equal(result.damage_events, case.losses, "native objective counts authentic separate Health losses " + case.id)
		await _dispose(flow)
	_suite.finish(get_tree())
