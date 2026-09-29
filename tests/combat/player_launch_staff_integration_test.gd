extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite
var _commits: Array[Dictionary] = []
var _resource_facts: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	EventBus.weapon_action_committed.connect(_on_weapon_action_committed)
	EventBus.weapon_resource_changed.connect(_on_weapon_resource_changed)
	await _test_launch_and_expansion_assemble_authoritative_staff()
	await _test_m1_and_next_reject_launch_staff_atomically()
	await _test_staff_aim_and_primary_charge_boundaries()
	await _test_staff_ultimate_hold_boundaries()
	await _test_staff_ultimate_time_energy_rewards_are_live_and_exactly_once()
	await _test_adapter_construction_release_and_payload_feedback()
	await _test_staff_lifecycle_cleanup_boundaries()
	if EventBus.weapon_action_committed.is_connected(_on_weapon_action_committed):
		EventBus.weapon_action_committed.disconnect(_on_weapon_action_committed)
	if EventBus.weapon_resource_changed.is_connected(_on_weapon_resource_changed):
		EventBus.weapon_resource_changed.disconnect(_on_weapon_resource_changed)
	_suite.finish(get_tree())


func _test_launch_and_expansion_assemble_authoritative_staff() -> void:
	for milestone: String in ["LAUNCH", "EXPANSION"]:
		var player := await _spawn_player()
		_suite.assert_true(
			player.configure_loadout(_staff_config(milestone)),
			"%s accepts the authoritative Staff profile" % milestone
		)
		_suite.assert_true(player.weapon_runtime != null, "%s assembles a Staff runtime" % milestone)
		_suite.assert_true(player.weapon_action_coordinator != null, "%s assembles a Staff coordinator" % milestone)
		_suite.assert_true(player.get_node_or_null("StaffWeapon") != null, "%s scene owns the Staff adapter" % milestone)
		_suite.assert_equal(player.weapon_presentation_snapshot().get("weapon_id"), "staff", "%s equips Staff authority" % milestone)
		_suite.assert_equal(player.weapon_presentation_snapshot().get("profile_id"), "staff_launch_v1", "%s preserves Staff profile identity" % milestone)
		_suite.assert_close(float(player.weapon_runtime.snapshot().get("mana", -1.0)), 100.0, "%s starts at one hundred Mana" % milestone)
		await _free_player(player)

	var player := await _spawn_player()
	var implicit_profile := _staff_config("LAUNCH")
	implicit_profile.erase("weapon_profile")
	_suite.assert_true(player.configure_loadout(implicit_profile), "Launch Staff selects its authoritative profile when omitted")
	_suite.assert_equal(player.weapon_presentation_snapshot().get("profile_id"), "staff_launch_v1", "implicit Staff selection resolves the Launch profile")
	_suite.assert_true(bool(player.weapon_presentation_snapshot().get("compatibility_profile_fallback", false)), "implicit Staff selection is disclosed as a compatibility fallback")
	await _free_player(player)


func _test_m1_and_next_reject_launch_staff_atomically() -> void:
	var player := await _spawn_player()
	var accepted_before: Dictionary = player.weapon_presentation_snapshot()
	for milestone: String in ["M1", "NEXT"]:
		_suite.assert_true(
			not player.configure_loadout(_staff_config(milestone)),
			"%s rejects the Launch-only Staff profile" % milestone
		)
		_suite.assert_equal(
			player.weapon_presentation_snapshot(),
			accepted_before,
			"%s Staff rejection preserves the accepted runtime atomically" % milestone
		)
	await _free_player(player)


func _test_staff_aim_and_primary_charge_boundaries() -> void:
	_commits.clear()
	var player := await _spawn_staff()
	var staff: Node2D = player.get_node("StaffWeapon")
	staff.global_rotation = PI * 0.5
	_suite.assert_equal(
		player.call("_weapon_aim_direction").round(),
		Vector2.DOWN,
		"Staff submission context reads the equipped adapter rotation"
	)
	_resource_facts.clear()
	_suite.assert_true(player.try_action(&"weapon_primary"), "Staff primary enters coordinator HOLD")
	for _frame: int in range(29):
		player.advance_action_frame()
	_suite.assert_true(
		bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")),
		"Staff primary releases at frame 29"
	)
	_suite.assert_equal(_last_commit_action(), "arcane_bolt", "frame 29 resolves Arcane Bolt")
	_suite.assert_close(float(player.weapon_runtime.snapshot().get("mana", -1.0)), 100.0, "Arcane Bolt spends no Mana")
	_suite.assert_equal(_mana_fact_count(), 0, "unchanged Mana does not publish a duplicate fact")
	await _free_player(player)

	_commits.clear()
	_resource_facts.clear()
	player = await _spawn_staff()
	_resource_facts.clear()
	_suite.assert_true(player.try_action(&"weapon_primary"), "charged Staff primary enters coordinator HOLD")
	for _frame: int in range(30):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "HOLD", "frame 30 remains held until release")
	_suite.assert_true(
		bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")),
		"Staff primary releases at frame 30"
	)
	_suite.assert_equal(_last_commit_action(), "charged_element", "frame 30 resolves Charged Element")
	_suite.assert_close(float(player.weapon_runtime.snapshot().get("mana", -1.0)), 80.0, "Fire charge spends exactly twenty Mana")
	_suite.assert_equal(_mana_fact_count(), 1, "one committed Mana change publishes exactly one typed fact")
	if _mana_fact_count() == 1:
		var fact := _last_mana_fact()
		_suite.assert_equal(fact.get("weapon_id"), &"staff", "Mana fact identifies Staff")
		_suite.assert_equal(fact.get("resource_id"), &"mana", "Mana fact identifies Mana")
		_suite.assert_close(float(fact.get("current", -1.0)), 80.0, "Mana fact publishes the committed balance")
		_suite.assert_close(float(fact.get("maximum", -1.0)), 100.0, "Mana fact publishes the current maximum")
	await _free_player(player)


func _test_staff_ultimate_hold_boundaries() -> void:
	_commits.clear()
	var player := await _spawn_staff()
	var time_manager: Node = player.get_node("TimeManager")
	_suite.assert_true(player.try_action(&"weapon_ultimate"), "Staff ultimate enters its sixty-frame HOLD")
	for _frame: int in range(59):
		player.advance_action_frame()
	_suite.assert_true(
		not bool(player.call("_submit_weapon_intent", &"weapon_ultimate", &"released")),
		"Staff ultimate rejects frame 59"
	)
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "READY", "undercharged Staff ultimate rolls back to READY")
	_suite.assert_close(float(player.weapon_runtime.snapshot().get("mana", -1.0)), 100.0, "undercharged ultimate spends no Mana")
	_suite.assert_close(float(time_manager.energy), 100.0, "undercharged ultimate spends no Time Energy")
	await _free_player(player)

	_commits.clear()
	_resource_facts.clear()
	player = await _spawn_staff()
	time_manager = player.get_node("TimeManager")
	_resource_facts.clear()
	_suite.assert_true(player.try_action(&"weapon_ultimate"), "Staff frame-60 fixture enters HOLD")
	for _frame: int in range(60):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "WINDUP", "Staff ultimate auto-releases at frame 60")
	_suite.assert_equal(_last_commit_action(), "primordial_wrath", "frame 60 resolves Primordial Wrath")
	_suite.assert_close(float(player.weapon_runtime.snapshot().get("mana", -1.0)), 40.0, "Primordial Wrath spends sixty Mana")
	_suite.assert_close(float(time_manager.energy), 45.0, "Primordial Wrath spends fifty-five Time Energy")
	_suite.assert_equal(_mana_fact_count(), 1, "ultimate Mana spend publishes exactly one typed fact")
	await _free_player(player)


func _test_staff_ultimate_time_energy_rewards_are_live_and_exactly_once() -> void:
	_commits.clear()
	_resource_facts.clear()
	var player := await _spawn_staff()
	var staff: Node = player.get_node("StaffWeapon")
	var time_manager: Node = player.get_node("TimeManager")
	_resource_facts.clear()
	_suite.assert_true(player.try_action(&"weapon_ultimate"), "Staff reward fixture enters ultimate HOLD")
	for _frame: int in range(60):
		player.advance_action_frame()
	var token := int(_commits.back().get("token", 0)) if not _commits.is_empty() else 0
	var context: Dictionary = _commits.back().get("context", {}) if not _commits.is_empty() else {}
	var generation := int(context.get("action_generation", 0))
	_suite.assert_true(token > 0 and generation > 0, "ultimate reward fixture captures live token-generation identity")
	_suite.assert_close(float(time_manager.energy), 45.0, "ultimate reward fixture starts after committed Time Energy spend")

	_resource_facts.clear()
	for _frame: int in range(20):
		player.advance_action_frame()
	var payloads: Array[Node] = staff.call("owned_payloads_for_test")
	var zone: Node = payloads[0] if not payloads.is_empty() else null
	_suite.assert_true(zone != null and is_instance_valid(zone), "ultimate reward fixture releases the real seeded zone")
	if zone != null and is_instance_valid(zone):
		zone.call("advance_execution_for_test", 6)
	_suite.assert_close(float(time_manager.energy), 47.0, "one live ultimate tick restores exactly two Time Energy")
	_suite.assert_equal(_time_energy_fact_count(), 1, "one live ultimate tick publishes one typed Time Energy fact")
	if _time_energy_fact_count() == 1:
		var fact := _last_time_energy_fact()
		_suite.assert_equal(fact.get("weapon_id"), &"staff", "ultimate reward fact identifies Staff")
		_suite.assert_equal(fact.get("resource_id"), &"time_energy", "ultimate reward fact identifies Time Energy")
		_suite.assert_close(float(fact.get("current", -1.0)), 47.0, "ultimate reward fact publishes the restored balance")
		_suite.assert_close(float(fact.get("maximum", -1.0)), 100.0, "ultimate reward fact publishes the maximum balance")
		_suite.assert_equal(fact.get("reason"), &"ultimate_tick", "ultimate reward fact uses the typed ultimate-tick reason")

	staff.resource_reward_requested.emit(token, &"staff_ultimate_tick:0", &"time_energy", 2.0)
	_suite.assert_close(float(time_manager.energy), 47.0, "duplicate ultimate reward claim cannot restore Time Energy twice")
	_suite.assert_equal(_time_energy_fact_count(), 1, "duplicate ultimate reward claim cannot publish a duplicate typed fact")

	staff.resource_reward_requested.emit(token + 1000, &"staff_ultimate_tick:1", &"time_energy", 2.0)
	_suite.assert_close(float(time_manager.energy), 47.0, "stale ultimate token is rejected")
	_suite.assert_equal(_time_energy_fact_count(), 1, "stale ultimate token publishes no typed fact")

	var generations_value: Variant = player.get("_weapon_action_generations_by_token")
	if generations_value is Dictionary:
		var generations := (generations_value as Dictionary).duplicate()
		generations.erase(token)
		player.set("_weapon_action_generations_by_token", generations)
	staff.resource_reward_requested.emit(token, &"staff_ultimate_tick:1", &"time_energy", 2.0)
	_suite.assert_close(float(time_manager.energy), 47.0, "ultimate reward without a live generation is rejected")
	_suite.assert_equal(_time_energy_fact_count(), 1, "missing-generation reward publishes no typed fact")

	player.reset_runtime_state()
	time_manager.energy = 40.0
	_resource_facts.clear()
	staff.resource_reward_requested.emit(token, &"staff_ultimate_tick:2", &"time_energy", 2.0)
	_suite.assert_close(float(time_manager.energy), 40.0, "runtime reset rejects rewards from the prior Staff generation")
	_suite.assert_equal(_time_energy_fact_count(), 0, "runtime reset blocks stale ultimate typed facts")
	await _free_player(player)


func _test_adapter_construction_release_and_payload_feedback() -> void:
	_commits.clear()
	_resource_facts.clear()
	var player := await _spawn_staff()
	var staff: Node = player.get_node("StaffWeapon")
	_resource_facts.clear()
	_suite.assert_true(player.try_action(&"weapon_primary"), "payload fixture starts Staff primary HOLD")
	for _frame: int in range(30):
		player.advance_action_frame()
	_suite.assert_true(
		bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")),
		"payload fixture commits Charged Element"
	)
	_suite.assert_equal(staff.call("prepared_payload_count_for_test"), 1, "commit constructs one adapter-owned payload before ACTIVE")
	var token := int(_commits.back().get("token", 0)) if not _commits.is_empty() else 0
	_suite.assert_true(token > 0, "payload fixture captures a coordinator token")
	for _frame: int in range(8):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "ACTIVE", "charged cast enters ACTIVE after exact windup")
	_suite.assert_equal(staff.call("prepared_payload_count_for_test"), 0, "ACTIVE consumes the prepared payload")
	_suite.assert_equal(staff.call("owned_payload_count_for_test"), 1, "ACTIVE releases one Staff projectile")

	var payloads: Array[Node] = staff.call("owned_payloads_for_test")
	var payload: Node = payloads[0] if not payloads.is_empty() else null
	_suite.assert_true(payload != null and is_instance_valid(payload), "released Staff payload remains live for feedback")
	if payload != null and is_instance_valid(payload):
		_resource_facts.clear()
		var mana_before := float(player.weapon_runtime.snapshot().get("mana", -1.0))
		var hit_result := {
			"type": "damage_resolved",
			"claim_id": "damage:0:integration:fire:7001",
			"descriptor_id": str(payload.get("descriptor_id")),
			"outcome_index": int(payload.get("outcome_index")),
			"outcome_id": "%s:%d" % [str(payload.get("descriptor_id")), int(payload.get("outcome_index"))],
			"target_id": 7001,
			"element_id": str(payload.get("element_id")),
			"element": str(payload.get("element_id")),
			"terminal": false,
			"hit": true,
			"damage": 25.0,
			"damage_scope": "integration",
			"impact_position": Vector2.ZERO,
		}
		payload.payload_result.emit(int(payload.get("action_token")), int(payload.get("generation")), hit_result)
		_suite.assert_true(not hit_result.is_empty(), "real Staff projectile reports a resolved damage packet")
		var mana_after := float(player.weapon_runtime.snapshot().get("mana", -1.0))
		_suite.assert_true(mana_after > mana_before, "payload hit returns bounded Mana through the runtime sink")
		_suite.assert_equal(_mana_fact_count(), 1, "accepted payload Mana return publishes one typed fact")
		payload.payload_result.emit(int(payload.get("action_token")), int(payload.get("generation")), hit_result)
		_suite.assert_equal(_mana_fact_count(), 1, "duplicate payload callback cannot publish duplicate Mana facts")
	for _frame: int in range(20):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "READY", "completed Staff action returns coordinator authority to READY")
	_suite.assert_true(not bool(staff.call("is_profile_action_active")), "completed Staff action routes finish to the adapter")
	await _free_player(player)

	player = await _spawn_staff()
	staff = player.get_node("StaffWeapon")
	_suite.assert_true(player.try_action(&"weapon_primary"), "terminal fixture starts Staff primary HOLD")
	for _frame: int in range(30):
		player.advance_action_frame()
	_suite.assert_true(bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")), "terminal fixture commits Charged Element")
	for _frame: int in range(8):
		player.advance_action_frame()
	payloads = staff.call("owned_payloads_for_test")
	payload = payloads[0] if not payloads.is_empty() else null
	_suite.assert_true(payload != null and is_instance_valid(payload), "terminal fixture releases a real Staff projectile")
	if payload != null and is_instance_valid(payload):
		payload.call("complete_without_hit_for_test")
		var cast_ledgers: Dictionary = player.weapon_runtime.snapshot().get("cast_ledgers", {})
		var cast: Dictionary = cast_ledgers.get(str(int(_commits.back().get("token", 0))), {})
		var outcomes: Dictionary = cast.get("outcomes", {})
		_suite.assert_equal(outcomes.size(), 1, "terminal miss closes exactly one runtime outcome")
	await _free_player(player)


func _test_staff_lifecycle_cleanup_boundaries() -> void:
	var player := await _spawn_staff()
	var staff: Node = player.get_node("StaffWeapon")
	await _release_charged_payload(player)
	_suite.assert_equal(staff.call("owned_payload_count_for_test"), 1, "reset fixture owns one released Staff payload")
	player.reset_runtime_state()
	_suite.assert_equal(staff.call("owned_payload_count_for_test"), 0, "runtime reset clears released Staff payloads")
	await get_tree().process_frame

	await _release_charged_payload(player)
	_suite.assert_true(player.restore_rewind_safe_action_state({"action_state": "FREE"}), "rewind-safe restore succeeds for Staff")
	_suite.assert_equal(staff.call("owned_payload_count_for_test"), 0, "rewind restore clears released Staff payloads")
	await get_tree().process_frame

	await _release_charged_payload(player)
	_suite.assert_true(player.configure_loadout(_staff_config("LAUNCH")), "Staff loadout reconfigure succeeds")
	_suite.assert_equal(staff.call("owned_payload_count_for_test"), 0, "loadout reconfigure clears prior Staff payloads")
	await get_tree().process_frame

	await _release_charged_payload(player)
	player.call("_on_died", null)
	_suite.assert_equal(staff.call("owned_payload_count_for_test"), 0, "death clears released Staff payloads")
	_suite.assert_equal(player.weapon_runtime.snapshot().get("active_phase"), "READY", "death cancels Staff runtime authority")
	await _free_player(player)


func _release_charged_payload(player: Node) -> void:
	_suite.assert_true(player.try_action(&"weapon_primary"), "cleanup fixture starts Staff primary HOLD")
	for _frame: int in range(30):
		player.advance_action_frame()
	_suite.assert_true(bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")), "cleanup fixture commits Charged Element")
	for _frame: int in range(8):
		player.advance_action_frame()


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	return player


func _spawn_staff() -> Node:
	var player := await _spawn_player()
	var config := _staff_config("LAUNCH")
	_suite.assert_true(player.configure_loadout(config), "Player accepts the authoritative Launch Staff profile")
	return player


func _staff_config(milestone: String) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": milestone,
		"character_id": "wanderer",
		"weapon_id": "staff",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
		"weapon_profile": _profile_definition("staff_launch_v1"),
	}


func _profile_definition(profile_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/content_packs/base/content/weapon_runtime_profiles.json")
	)
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == profile_id:
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _last_commit_action() -> String:
	return str(_commits.back().get("action_id", "")) if not _commits.is_empty() else ""


func _mana_fact_count() -> int:
	var count := 0
	for fact: Dictionary in _resource_facts:
		if fact.get("weapon_id") == &"staff" and fact.get("resource_id") == &"mana":
			count += 1
	return count


func _last_mana_fact() -> Dictionary:
	for index: int in range(_resource_facts.size() - 1, -1, -1):
		var fact: Dictionary = _resource_facts[index]
		if fact.get("weapon_id") == &"staff" and fact.get("resource_id") == &"mana":
			return fact.duplicate(true)
	return {}


func _time_energy_fact_count() -> int:
	var count := 0
	for fact: Dictionary in _resource_facts:
		if fact.get("weapon_id") == &"staff" and fact.get("resource_id") == &"time_energy":
			count += 1
	return count


func _last_time_energy_fact() -> Dictionary:
	for index: int in range(_resource_facts.size() - 1, -1, -1):
		var fact: Dictionary = _resource_facts[index]
		if fact.get("weapon_id") == &"staff" and fact.get("resource_id") == &"time_energy":
			return fact.duplicate(true)
	return {}


func _free_player(player: Node) -> void:
	if is_instance_valid(player):
		player.cancel_transient_actions()
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _on_weapon_action_committed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary
) -> void:
	if weapon_id != &"staff":
		return
	_commits.append({
		"weapon_id": weapon_id,
		"action_id": str(action_id),
		"token": token,
		"context": context.duplicate(true),
	})


func _on_weapon_resource_changed(
	weapon_id: StringName,
	resource_id: StringName,
	current: float,
	maximum: float,
	reason: StringName
) -> void:
	_resource_facts.append({
		"weapon_id": weapon_id,
		"resource_id": resource_id,
		"current": current,
		"maximum": maximum,
		"reason": reason,
	})
