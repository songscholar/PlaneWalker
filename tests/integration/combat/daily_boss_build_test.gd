extends "res://tests/integration/combat/daily_boss_native_test.gd"


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var catalog := preload("res://scripts/modes/daily_boss_catalog.gd").new()
	_suite.assert_true(catalog.configure(_registry), "native Build suite loads the actual daily catalog")
	var observed := {}
	var weapons := {}
	var origin := _clock
	for offset: int in range(365):
		_clock = origin + offset * 86400
		var definition: Dictionary = catalog.projection(_clock)
		var case_id := "%s-%s" % [definition.weapon_id, definition.boss_id if definition.weapon_id == "gun" else "any"]
		if observed.has(case_id):
			continue
		observed[case_id] = true
		weapons[definition.weapon_id] = true
		var rich := _daily_flow(_daily_fixture("rich-" + case_id))
		var lean := _daily_flow(_daily_fixture("lean-" + case_id, false))
		var rich_start: Dictionary = rich.start()
		var lean_start: Dictionary = lean.start()
		_suite.assert_true(rich_start.ok and lean_start.ok, "same daily starts with rich and lean ordinary Meta for %s: %s / %s" % [definition.weapon_id, str(rich_start), str(lean_start)])
		if not rich_start.ok or not lean_start.ok:
			await _daily_dispose(rich)
			await _daily_dispose(lean)
			continue
		rich.current_player().set_physics_process(false)
		lean.current_player().set_physics_process(false)
		lean.get("_stage").position = Vector2(1280, 0)
		_suite.assert_equal(rich.baseline_player_effects().health.max_hp, 100.0, "daily uses Wanderer base 100 HP before content effects")
		_suite.assert_equal(rich.current_player().reward_effect_snapshot(), lean.current_player().reward_effect_snapshot(), "different Meta and unlock ownership cannot change actual fixed daily Build " + definition.weapon_id)
		var receipts: Array = rich.installed_build_receipts()
		for index: int in range(receipts.size()):
			var entry: Dictionary = receipts[index]
			_suite.assert_true(entry.receipt.operation_count > 0 and entry.receipt.before_snapshot != entry.receipt.after_snapshot, "each authored daily Build/condition commits actual native effects")
			if index >= 5:
				var condition := str(entry.definition_id).trim_prefix("daily_")
				if condition == "frail":
					_suite.assert_true(is_equal_approx(float(entry.receipt.after_snapshot.health.max_hp), float(entry.receipt.before_snapshot.health.max_hp) * 0.7), "frail daily condition actually reduces native maximum HP by thirty percent")
				elif condition in ["melee_specialist", "ranged_specialist"]:
					var melee: bool = definition.weapon_id in ["sword", "gauntlets"]
					var factor := 1.3 if (condition == "melee_specialist") == melee else 0.7
					var before: float = entry.receipt.before_snapshot.weapon.modifiers.get("weapon.damage", 1.0)
					var after: float = entry.receipt.after_snapshot.weapon.modifiers.get("weapon.damage", 1.0)
					_suite.assert_true(is_equal_approx(after, before * factor), "specialization changes actual selected weapon damage by the authored factor")
				else:
					_suite.assert_true(preload("res://scripts/modes/daily_boss_catalog.gd").NATIVE_RULES.has(condition), "native rule receipt comes from the authoritative daily catalog")
		var player: Node2D = rich.current_player()
		var boss: Node2D = rich.current_boss()
		player.health.invulnerable = true
		player.global_position = boss.global_position + Vector2(42, 0)
		await get_tree().physics_frame
		_suite.assert_true(player.advance_action_frame({"aim": Vector2.LEFT}) and player.try_action(&"weapon_primary"), "actual fixed daily weapon accepts native primary " + definition.weapon_id)
		for frame: int in range(150):
			if frame == 40:
				player.call("_submit_weapon_intent", &"weapon_primary", &"released")
			_suite.assert_true(player.advance_action_frame({"aim": player.global_position.direction_to(boss.global_position)}), "native fixed daily weapon commits real hostile frame " + definition.weapon_id)
			await get_tree().physics_frame
		_suite.assert_true(boss.health.current_hp < boss.health.max_hp, "every fixed daily weapon damages its actual selected Boss %s/%s: %s" % [definition.weapon_id, definition.boss_id, str({"boss_hp": boss.health.current_hp, "player_hp": player.health.current_hp, "weapon": player.weapon_runtime.snapshot()})])
		_suite.assert_true(rich.abandon().ok and lean.abandon().ok, "actual Build proof retires each admitted attempt once")
		await _daily_dispose(rich)
		await _daily_dispose(lean)
		if observed.size() == 9:
			break
	_suite.assert_equal(weapons.size(), 5, "real daily Build/collision proof covers all five weapons")
	_suite.assert_equal(observed.size(), 9, "actual swept daily Gun collision covers all five distinct native Bosses")
	_clock = origin
	var locked := _daily_flow(_daily_fixture("victory-gate", false, "base", false))
	_suite.assert_true(not locked.start().ok and locked.preview().reason == "DAILY_VICTORY_REQUIRED", "unearned normal victory cannot enter daily")
	await _daily_dispose(locked)
	var modified := _daily_flow(_daily_fixture("mod-gate", true, "mod-test"))
	_suite.assert_true(not modified.start().ok and modified.preview().reason == "DAILY_MOD_UNAVAILABLE", "Mod save domain cannot enter the fixed daily category")
	await _daily_dispose(modified)
	_suite.finish(get_tree())
