extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")


class DamageOwner:
	extends Node2D

	var weapon_decision: Dictionary = {}
	var character_decision: Dictionary = {}
	var query_count: int = 0
	var commit_count: int = 0
	var commit_result: bool = true
	var hit_control_count: int = 0
	var knockback_count: int = 0
	var target_multiplier: float = 1.0

	func damage_defense_decisions(_damage_info: RefCounted) -> Dictionary:
		query_count += 1
		return {
			"weapon": weapon_decision.duplicate(true),
			"character": character_decision.duplicate(true),
		}

	func commit_damage_defense(_decisions: Dictionary, _resolution: RefCounted) -> bool:
		commit_count += 1
		return commit_result

	func apply_knockback(_value: Vector2) -> void:
		knockback_count += 1

	func apply_weapon_hit_control(_damage_info: RefCounted, _amount: float) -> void:
		hit_control_count += 1

	func get_damage_taken_multiplier() -> float:
		return target_multiplier


var _suite
var _damage_about_count: int = 0
var _damage_applied_count: int = 0
var _hit_confirmed_count: int = 0
var _damaged_signal_count: int = 0
var _capture_irreversible_order: bool = false
var _irreversible_order: Array[Dictionary] = []
var _observed_health: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var original_persistent := GameState.persistent.duplicate(true)
	var fixture := await _create_fixture()
	var owner: DamageOwner = fixture["owner"]
	var health: HealthComponent = fixture["health"]
	health.damaged.connect(_on_health_damaged)
	_connect_damage_facts()

	await _test_overlapping_invulnerability(health)
	_test_accessibility_snapshot(owner, health)
	_test_ordered_damage_stages(owner, health)
	_test_critical_keeps_planned_original_amount(owner, health)
	_test_pending_target_identity_resolves_without_instance_ids(owner, health)
	_test_prevented_damage_has_no_generic_side_effects(owner, health)
	_test_malformed_decisions_fail_closed(owner, health)
	_test_dead_and_invulnerable_targets_are_prevented(owner, health)
	_test_unguardable_and_irreversible_damage_bypass_defense(owner, health)
	_test_invalid_and_bypass_skip_owner_planning(owner, health)
	_test_rejected_defense_commit_is_atomic(owner, health)
	_test_take_damage_queries_and_commits_owner_decisions(owner, health)
	_test_irreversible_loss_is_actual_atomic_and_published_before_death(health)
	_test_full_player_replay_restore_is_validated_and_atomic(health)

	_disconnect_damage_facts()
	if health.damaged.is_connected(_on_health_damaged):
		health.damaged.disconnect(_on_health_damaged)
	GameState.persistent = original_persistent
	owner.queue_free()
	await get_tree().process_frame
	_suite.finish(get_tree())


func _create_fixture() -> Dictionary:
	var owner := DamageOwner.new()
	owner.name = "PlayerDamageOwner"
	owner.add_to_group("player")
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 100.0
	owner.add_child(health)
	add_child(owner)
	await get_tree().process_frame
	_suite.assert_true(health.configure_run(&"health-pipeline-run"), "health fixture installs the authoritative run")
	return {"owner": owner, "health": health}


func _test_overlapping_invulnerability(health: HealthComponent) -> void:
	health.apply_invulnerability(0.12)
	await get_tree().create_timer(0.04).timeout
	health.apply_invulnerability(0.32)
	await get_tree().create_timer(0.12).timeout

	var damage_info := _damage_plan(10.0, ["enemy:melee"], 1)
	var blocked_damage: float = health.take_damage(damage_info)
	_suite.assert_close(blocked_damage, 0.0, "earlier expiry cannot end overlapping invulnerability")
	_suite.assert_close(health.current_hp, 100.0, "health remains unchanged before latest expiry")

	await get_tree().create_timer(0.24).timeout
	var applied_damage: float = health.take_damage(damage_info)
	_suite.assert_close(applied_damage, 10.0, "damage applies after latest invulnerability expiry")
	_suite.assert_close(health.current_hp, 90.0, "health changes after latest expiry")

	health.apply_invulnerability(0.08)
	get_tree().paused = true
	await get_tree().create_timer(0.12, true).timeout
	_suite.assert_true(health.invulnerable, "paused gameplay preserves invulnerability duration")
	get_tree().paused = false
	await get_tree().create_timer(0.10).timeout
	_suite.assert_true(not health.invulnerable, "invulnerability expires after gameplay resumes")


func _test_accessibility_snapshot(owner: DamageOwner, health: HealthComponent) -> void:
	var settings := GameState.normalized_settings()
	settings["damage_received_multiplier"] = 0.6
	GameState.persistent["settings"] = settings
	health.current_hp = 100.0
	var damage_info := _damage_plan(10.0, ["enemy:melee"], 10)
	var default_damage: float = health.take_damage(damage_info)
	_suite.assert_close(default_damage, 10.0, "player damage defaults to an unassisted run without a snapshot")
	_suite.assert_close(health.current_hp, 90.0, "persistent settings do not leak into an unconfigured run")

	health.configure_accessibility_assists({"damage_received_multiplier": 0.6})
	health.current_hp = 100.0
	var assisted_damage: float = health.take_damage(damage_info)
	_suite.assert_close(assisted_damage, 6.0, "run snapshot damage assist reduces incoming damage deterministically")
	_suite.assert_close(health.current_hp, 94.0, "damage assist changes only the applied player damage")

	settings["damage_received_multiplier"] = 0.8
	GameState.persistent["settings"] = settings
	health.current_hp = 100.0
	var stable_damage: float = health.take_damage(damage_info)
	_suite.assert_close(stable_damage, 6.0, "mid-run persistent setting changes cannot mutate the run snapshot")
	_suite.assert_close(health.current_hp, 94.0, "recorded and applied damage assist stay aligned for the run")
	health.configure_accessibility_assists({"damage_received_multiplier": 1.0})
	owner.target_multiplier = 1.0


func _test_ordered_damage_stages(owner: DamageOwner, health: HealthComponent) -> void:
	health.current_hp = 100.0
	health.defense = 3.0
	health.configure_accessibility_assists({"damage_received_multiplier": 0.5})
	owner.target_multiplier = 1.0
	var resolution: RefCounted = health.resolve_and_apply_damage(
		_damage_plan(100.0, ["enemy:melee"], 20),
		{"multiplier": 0.8, "guard_kind": "weapon_normal"},
		{"multiplier": 0.5, "guard_kind": "guardian_normal"}
	)
	var snapshot: Dictionary = resolution.snapshot()
	_suite.assert_close(float(snapshot["original_amount"]), 100.0, "resolution records original damage")
	_suite.assert_close(float(snapshot["post_weapon_defense_amount"]), 80.0, "weapon defense executes first")
	_suite.assert_close(float(snapshot["post_character_defense_amount"]), 40.0, "character defense executes second")
	_suite.assert_close(float(snapshot["post_accessibility_amount"]), 20.0, "accessibility executes after defense decisions")
	_suite.assert_close(float(snapshot["post_defense_amount"]), 17.0, "flat defense executes after percentage stages")
	_suite.assert_close(float(snapshot["finalized_damage"]), 17.0, "finalized damage matches the ordered pipeline")
	_suite.assert_close(health.current_hp, 83.0, "only finalized damage is subtracted from HP")
	_suite.assert_equal(snapshot["guard_kind"], &"guardian_normal", "last applied defense stage identifies the resolution guard")
	health.defense = 0.0
	health.configure_accessibility_assists({"damage_received_multiplier": 1.0})


func _test_critical_keeps_planned_original_amount(owner: DamageOwner, health: HealthComponent) -> void:
	health.current_hp = 100.0
	health.defense = 0.0
	health.configure_accessibility_assists({"damage_received_multiplier": 1.0})
	owner.target_multiplier = 1.0
	var resolution: RefCounted = health.resolve_and_apply_damage(
		_critical_damage_plan(20.0, 21),
		{"multiplier": 0.5, "guard_kind": "weapon_normal"},
		{}
	)
	var snapshot: Dictionary = resolution.snapshot()
	_suite.assert_close(float(snapshot["original_amount"]), 20.0, "critical outcome cannot rewrite the authored original amount")
	_suite.assert_close(float(snapshot["post_weapon_defense_amount"]), 10.0, "weapon defense evaluates the planned amount before critical target-stage modifiers")
	_suite.assert_close(float(snapshot["post_accessibility_amount"]), 15.0, "critical outcome is represented in the post-modifier stage")
	_suite.assert_close(float(snapshot["finalized_damage"]), 15.0, "critical damage remains applied by the compatibility pipeline")
	_suite.assert_close(health.current_hp, 85.0, "critical pipeline subtracts its finalized amount once")


func _test_pending_target_identity_resolves_without_instance_ids(owner: DamageOwner, health: HealthComponent) -> void:
	health.current_hp = 100.0
	owner.set_meta("stable_target_id", 404)
	var resolved: RefCounted = health.resolve_and_apply_damage(_damage_plan_with_target(5.0, 22, "pending_target"))
	_suite.assert_equal(resolved.snapshot()["target_id"], &"404", "pending target identity resolves from authoritative target metadata")
	owner.remove_meta("stable_target_id")
	var unresolved: RefCounted = health.resolve_and_apply_damage(_damage_plan_with_target(5.0, 23, "pending_target"))
	_suite.assert_equal(unresolved.snapshot()["target_id"], &"pending_target", "missing target authority preserves pending identity without instance fallback")


func _test_prevented_damage_has_no_generic_side_effects(owner: DamageOwner, health: HealthComponent) -> void:
	health.current_hp = 100.0
	owner.hit_control_count = 0
	owner.knockback_count = 0
	_reset_damage_facts()
	var resolution: RefCounted = health.resolve_and_apply_damage(
		_damage_plan(100.0, ["enemy:melee"], 30),
		{"prevented": true, "guard_kind": "sword_perfect"},
		{}
	)
	var snapshot: Dictionary = resolution.snapshot()
	_suite.assert_true(resolution.is_prevented(), "perfect guard produces a prevented resolution")
	_suite.assert_close(health.current_hp, 100.0, "prevented damage cannot subtract then heal")
	_suite.assert_close(float(snapshot["finalized_damage"]), 0.0, "prevented resolution finalizes zero damage")
	_suite.assert_equal(_damage_applied_count, 0, "prevented resolution publishes no generic damage fact")
	_suite.assert_equal(_hit_confirmed_count, 0, "prevented resolution publishes no generic hit fact")
	_suite.assert_equal(owner.hit_control_count, 0, "prevented resolution applies no hit control")
	_suite.assert_equal(owner.knockback_count, 0, "prevented resolution applies no knockback")


func _test_malformed_decisions_fail_closed(owner: DamageOwner, health: HealthComponent) -> void:
	var cases: Array[Dictionary] = [
		{"unknown": true},
		{"multiplier": -0.1},
		{"multiplier": 1.1},
		{"prevented": true, "multiplier": 0.5, "guard_kind": "invalid"},
		{"prevented": false, "prevent_reason": "conflict"},
		{"commit_context": []},
	]
	for index in range(cases.size()):
		health.current_hp = 100.0
		_reset_damage_facts()
		var resolution: RefCounted = health.resolve_and_apply_damage(
			_damage_plan(25.0, ["enemy:melee"], 40 + index),
			cases[index],
			{}
		)
		_suite.assert_true(resolution.is_prevented(), "malformed defense case %d fails closed" % index)
		_suite.assert_equal(resolution.snapshot()["prevent_reason"], &"invalid_decision", "malformed defense case %d has a stable reason" % index)
		_suite.assert_close(health.current_hp, 100.0, "malformed defense case %d preserves HP" % index)
		_suite.assert_equal(_damage_applied_count, 0, "malformed defense case %d publishes no damage fact" % index)
		_suite.assert_equal(_hit_confirmed_count, 0, "malformed defense case %d publishes no hit fact" % index)

	owner.weapon_decision = {"unknown": true}
	owner.character_decision = {}
	owner.commit_count = 0
	owner.hit_control_count = 0
	owner.knockback_count = 0
	health.current_hp = 100.0
	_suite.assert_close(health.take_damage(_damage_plan(20.0, ["enemy:melee"], 49)), 0.0, "invalid owner decision fails closed through compatibility wrapper")
	_suite.assert_equal(owner.commit_count, 0, "invalid owner decision is never committed")
	_suite.assert_close(health.current_hp, 100.0, "invalid owner decision preserves HP")
	owner.weapon_decision = {}


func _test_dead_and_invulnerable_targets_are_prevented(owner: DamageOwner, health: HealthComponent) -> void:
	health.current_hp = 100.0
	health.dead = true
	_reset_damage_facts()
	var dead_resolution: RefCounted = health.resolve_and_apply_damage(_damage_plan(20.0, ["enemy:melee"], 50))
	_suite.assert_true(dead_resolution.is_prevented(), "dead target returns a prevented resolution")
	_suite.assert_equal(dead_resolution.snapshot()["prevent_reason"], &"target_dead", "dead target uses a stable prevention reason")
	_suite.assert_close(health.current_hp, 100.0, "dead target HP is unchanged")
	health.dead = false
	health.invulnerable = true
	var immune_resolution: RefCounted = health.resolve_and_apply_damage(_damage_plan(20.0, ["enemy:melee"], 51))
	_suite.assert_true(immune_resolution.is_prevented(), "invulnerable target returns a prevented resolution")
	_suite.assert_equal(immune_resolution.snapshot()["prevent_reason"], &"target_invulnerable", "invulnerable target uses a stable prevention reason")
	_suite.assert_close(health.current_hp, 100.0, "invulnerable target HP is unchanged")
	_suite.assert_equal(_damage_applied_count, 0, "target validity prevention publishes no damage fact")
	_suite.assert_equal(_hit_confirmed_count, 0, "target validity prevention publishes no hit fact")
	health.invulnerable = false
	owner.commit_count = 0


func _test_unguardable_and_irreversible_damage_bypass_defense(owner: DamageOwner, health: HealthComponent) -> void:
	for case_value in [
		{"tag": "damage:unguardable", "token": 60, "irreversible": false},
		{"tag": "damage:irreversible", "token": 61, "irreversible": true},
	]:
		health.current_hp = 100.0
		var hp_loss_before: Dictionary = health.hp_loss_state()
		var resolution: RefCounted = health.resolve_and_apply_damage(
			_damage_plan(20.0, [case_value["tag"]], int(case_value["token"])),
			{"prevented": true, "guard_kind": "sword_perfect"},
			{"multiplier": 0.5, "guard_kind": "guardian_normal"}
		)
		var snapshot: Dictionary = resolution.snapshot()
		_suite.assert_true(not resolution.is_prevented(), "%s bypasses defense prevention" % case_value["tag"])
		_suite.assert_close(float(snapshot["post_weapon_defense_amount"]), 20.0, "%s bypasses weapon defense" % case_value["tag"])
		_suite.assert_close(float(snapshot["post_character_defense_amount"]), 20.0, "%s bypasses character defense" % case_value["tag"])
		_suite.assert_equal(snapshot["irreversible"], case_value["irreversible"], "%s records irreversible semantics" % case_value["tag"])
		_suite.assert_close(health.current_hp, 80.0, "%s still applies damage" % case_value["tag"])
		var hp_loss_after: Dictionary = health.hp_loss_state()
		if bool(case_value["irreversible"]):
			_suite.assert_close(
				float(hp_loss_after.get("irreversible_hp_loss_total", -1.0)),
				float(hp_loss_before.get("irreversible_hp_loss_total", 0.0)) + 20.0,
				"irreversible DamageInfo records the actual finalized loss"
			)
			_suite.assert_equal(
				int(hp_loss_after.get("revision", -1)),
				int(hp_loss_before.get("revision", 0)) + 1,
				"irreversible DamageInfo commits one stable ledger claim"
			)
		else:
			_suite.assert_equal(hp_loss_after, hp_loss_before, "unguardable-only damage does not enter the irreversible ledger")
	owner.commit_count = 0


func _test_invalid_and_bypass_skip_owner_planning(owner: DamageOwner, health: HealthComponent) -> void:
	owner.weapon_decision = {"prevented": true, "guard_kind": "sword_perfect"}
	owner.character_decision = {}
	owner.query_count = 0
	owner.commit_count = 0
	health.current_hp = 100.0
	_suite.assert_close(health.take_damage(null), 0.0, "null damage input fails closed")
	_suite.assert_equal(owner.query_count, 0, "invalid damage input never reaches owner defense planning")
	_suite.assert_equal(owner.commit_count, 0, "invalid damage input never reaches owner defense commit")
	var bypass_damage := health.take_damage(_damage_plan(20.0, ["damage:unguardable"], 62))
	_suite.assert_close(bypass_damage, 20.0, "unguardable damage bypasses a planned perfect guard")
	_suite.assert_close(health.current_hp, 80.0, "unguardable damage applies exactly once")
	_suite.assert_equal(owner.query_count, 0, "unguardable damage does not query owner defense planning")
	_suite.assert_equal(owner.commit_count, 0, "unguardable damage does not commit owner defense")
	owner.weapon_decision = {}


func _test_rejected_defense_commit_is_atomic(owner: DamageOwner, health: HealthComponent) -> void:
	owner.commit_result = false
	owner.weapon_decision = {"multiplier": 0.5, "guard_kind": "weapon_normal"}
	owner.character_decision = {}
	owner.commit_count = 0
	owner.hit_control_count = 0
	owner.knockback_count = 0
	health.current_hp = 100.0
	_reset_damage_facts()
	seed(7331)
	var expected_next_random := randf()
	seed(7331)
	var reduced := health.take_damage(_damage_plan(40.0, ["enemy:melee"], 63))
	var actual_next_random := randf()
	_suite.assert_close(reduced, 0.0, "rejected reduction commit returns prevented damage")
	_suite.assert_close(
		actual_next_random,
		expected_next_random,
		"rejected defense commit cannot advance global combat RNG"
	)
	_suite.assert_close(health.current_hp, 100.0, "rejected reduction commit preserves HP")
	_suite.assert_equal(owner.commit_count, 1, "rejected reduction commit is attempted exactly once")
	_suite.assert_equal(_damage_about_count, 0, "rejected reduction commit publishes no damage observation")
	_suite.assert_equal(_damage_applied_count, 0, "rejected reduction commit publishes no generic damage fact")
	_suite.assert_equal(_hit_confirmed_count, 0, "rejected reduction commit publishes no generic hit fact")
	_suite.assert_equal(_damaged_signal_count, 0, "rejected reduction commit publishes no damaged signal")
	_suite.assert_equal(owner.hit_control_count, 0, "rejected reduction commit applies no hit control")
	_suite.assert_equal(owner.knockback_count, 0, "rejected reduction commit applies no knockback")

	owner.weapon_decision = {"prevented": true, "guard_kind": "sword_perfect"}
	_reset_damage_facts()
	var prevented := health.take_damage(_damage_plan(40.0, ["enemy:melee"], 64))
	_suite.assert_close(prevented, 0.0, "rejected prevention commit remains prevented")
	_suite.assert_close(health.current_hp, 100.0, "rejected prevention commit preserves HP")
	_suite.assert_equal(owner.commit_count, 2, "rejected prevention commit is attempted exactly once")
	_suite.assert_equal(_damage_about_count, 0, "rejected prevention commit publishes no damage observation")
	_suite.assert_equal(_damage_applied_count, 0, "rejected prevention commit publishes no generic damage fact")
	_suite.assert_equal(_hit_confirmed_count, 0, "rejected prevention commit publishes no generic hit fact")
	_suite.assert_equal(_damaged_signal_count, 0, "rejected prevention commit publishes no damaged signal")
	_suite.assert_equal(owner.hit_control_count, 0, "rejected prevention commit applies no hit control")
	_suite.assert_equal(owner.knockback_count, 0, "rejected prevention commit applies no knockback")
	owner.commit_result = true
	owner.weapon_decision = {}
	owner.character_decision = {}
	randomize()


func _test_take_damage_queries_and_commits_owner_decisions(owner: DamageOwner, health: HealthComponent) -> void:
	health.current_hp = 100.0
	owner.weapon_decision = {"multiplier": 0.5, "guard_kind": "weapon_normal"}
	owner.character_decision = {"multiplier": 0.5, "guard_kind": "guardian_normal"}
	owner.commit_count = 0
	var applied := health.take_damage(_damage_plan(40.0, ["enemy:melee"], 70))
	_suite.assert_close(applied, 10.0, "compatibility wrapper applies owner defense decisions in order")
	_suite.assert_close(health.current_hp, 90.0, "compatibility wrapper subtracts resolved damage")
	_suite.assert_equal(owner.commit_count, 1, "compatibility wrapper commits accepted owner decisions once")
	owner.weapon_decision = {"prevented": true, "guard_kind": "sword_perfect"}
	owner.character_decision = {}
	var prevented := health.take_damage(_damage_plan(40.0, ["enemy:melee"], 71))
	_suite.assert_close(prevented, 0.0, "compatibility wrapper reports zero for prevented damage")
	_suite.assert_close(health.current_hp, 90.0, "compatibility wrapper leaves prevented HP unchanged")
	_suite.assert_equal(owner.commit_count, 2, "compatibility wrapper commits a valid prevented guard once")
	owner.weapon_decision = {}
	owner.character_decision = {}


func _test_irreversible_loss_is_actual_atomic_and_published_before_death(health: HealthComponent) -> void:
	_suite.assert_true(health.configure_run(&"health-irrev-run"), "health can install a new authoritative run")
	health.current_hp = 20.0
	health.dead = false
	_reset_damage_facts()

	var first: RefCounted = health.lose_health_irreversible(
		6.0,
		&"curse:time_stop",
		801,
		9,
		&"health-irrev-run"
	)
	_suite.assert_true(first != null and not first.is_prevented(), "first irreversible claim applies")
	if first != null:
		_suite.assert_close(first.finalized_damage(), 6.0, "first irreversible resolution reports actual loss")
	var after_first: Dictionary = health.hp_loss_state()
	_suite.assert_equal(
		after_first,
		{"irreversible_hp_loss_total": 6.0, "revision": 1},
		"first irreversible claim updates total and revision once"
	)
	var damaged_after_first := _damaged_signal_count

	var duplicate: RefCounted = health.lose_health_irreversible(
		99.0,
		&"curse:time_stop",
		801,
		9,
		&"health-irrev-run"
	)
	_suite.assert_true(duplicate != null and duplicate.is_prevented(), "duplicate irreversible claim is rejected")
	if duplicate != null:
		_suite.assert_close(duplicate.finalized_damage(), 0.0, "duplicate irreversible claim finalizes zero damage")
	_suite.assert_close(health.current_hp, 14.0, "duplicate irreversible claim cannot change HP")
	_suite.assert_equal(health.hp_loss_state(), after_first, "duplicate irreversible claim cannot change ledger state")
	_suite.assert_equal(_damaged_signal_count, damaged_after_first, "duplicate irreversible claim emits no damaged signal")

	_irreversible_order.clear()
	_observed_health = health
	_capture_irreversible_order = true
	EventBus.entity_died.connect(_on_irreversible_entity_died)
	health.died.connect(_on_irreversible_died)
	var terminal: RefCounted = health.lose_health_irreversible(
		100.0,
		&"terminal_cost",
		802,
		9,
		&"health-irrev-run"
	)
	_capture_irreversible_order = false
	if EventBus.entity_died.is_connected(_on_irreversible_entity_died):
		EventBus.entity_died.disconnect(_on_irreversible_entity_died)
	if health.died.is_connected(_on_irreversible_died):
		health.died.disconnect(_on_irreversible_died)

	_suite.assert_true(terminal != null and not terminal.is_prevented(), "terminal irreversible claim applies")
	if terminal != null:
		_suite.assert_close(terminal.finalized_damage(), 14.0, "overkill records and reports only actual HP removed")
	_suite.assert_close(health.current_hp, 0.0, "terminal irreversible loss reaches zero HP")
	_suite.assert_true(health.dead, "terminal irreversible loss marks the target dead")
	_suite.assert_equal(
		health.hp_loss_state(),
		{"irreversible_hp_loss_total": 20.0, "revision": 2},
		"terminal overkill adds only the remaining fourteen HP"
	)
	var observed_events: Array[String] = []
	for observation: Dictionary in _irreversible_order:
		observed_events.append(str(observation.get("event", "")))
		_suite.assert_equal(
			observation.get("hp_loss_state", {}),
			{"irreversible_hp_loss_total": 20.0, "revision": 2},
			"%s observes the committed terminal ledger claim" % str(observation.get("event", "death callback"))
		)
	_suite.assert_equal(observed_events.count("damaged"), 1, "terminal irreversible loss emits one damaged callback")
	_suite.assert_equal(observed_events.count("entity_died"), 1, "entity_died observes one terminal publication")
	_suite.assert_equal(observed_events.count("died"), 1, "died observes one terminal publication")
	_observed_health = null


func _test_full_player_replay_restore_is_validated_and_atomic(health: HealthComponent) -> void:
	_suite.assert_true(
		health.configure_run(&"health-replay-run"),
		"Health Replay fixture installs a fresh authoritative run"
	)
	health.max_hp = 140.0
	health.current_hp = 110.0
	health.healing_multiplier = 0.75
	health.dead = false
	var recorded_loss: RefCounted = health.lose_health_irreversible(
		8.0,
		&"curse:time_stop",
		901,
		12,
		&"health-replay-run"
	)
	_suite.assert_true(
		recorded_loss != null and not recorded_loss.is_prevented(),
		"Health Replay fixture records one authoritative irreversible claim"
	)
	var checkpoint: Dictionary = health.runtime_state_snapshot()
	var state_before_validation: Dictionary = health.runtime_state_snapshot()
	_suite.assert_true(
		health.can_restore_replay_snapshot(checkpoint),
		"Health accepts its complete validated Replay snapshot"
	)
	_suite.assert_equal(
		health.runtime_state_snapshot(),
		state_before_validation,
		"Health Replay preflight is pure"
	)

	health.max_hp = 220.0
	health.current_hp = 73.0
	health.healing_multiplier = 1.8
	health.dead = false
	var later_loss: RefCounted = health.lose_health_irreversible(
		5.0,
		&"corruption_tick",
		902,
		12,
		&"health-replay-run"
	)
	_suite.assert_true(
		later_loss != null and not later_loss.is_prevented(),
		"Health Replay mutation fixture advances the irreversible ledger"
	)
	_suite.assert_true(
		health.restore_replay_snapshot(checkpoint),
		"Health restores the full validated Replay checkpoint"
	)
	_suite.assert_equal(
		health.runtime_state_snapshot(),
		checkpoint,
		"Health Replay restore installs HP, maximum, healing, death, and ledger exactly"
	)
	var hp_before_duplicate := health.current_hp
	var replayed_duplicate: RefCounted = health.lose_health_irreversible(
		99.0,
		&"curse:time_stop",
		901,
		12,
		&"health-replay-run"
	)
	_suite.assert_true(
		replayed_duplicate != null and replayed_duplicate.is_prevented(),
		"Health Replay restore preserves irreversible duplicate-claim protection"
	)
	_suite.assert_close(
		health.current_hp,
		hp_before_duplicate,
		"restored irreversible claims cannot be charged twice"
	)
	_suite.assert_equal(
		health.runtime_state_snapshot(),
		checkpoint,
		"duplicate irreversible rejection leaves the restored checkpoint exact"
	)

	var dead_checkpoint := checkpoint.duplicate(true)
	dead_checkpoint["current_hp"] = 0.0
	dead_checkpoint["dead"] = true
	_suite.assert_true(
		health.can_restore_replay_snapshot(dead_checkpoint),
		"Health accepts a coherent terminal Replay state"
	)
	_suite.assert_true(
		health.restore_replay_snapshot(dead_checkpoint),
		"Health restores the recorded death state without publishing gameplay events"
	)
	_suite.assert_equal(
		health.runtime_state_snapshot(),
		dead_checkpoint,
		"Health Replay restore preserves the exact terminal snapshot"
	)

	var missing_field := dead_checkpoint.duplicate(true)
	missing_field.erase("healing_multiplier")
	var unknown_field := dead_checkpoint.duplicate(true)
	unknown_field["unexpected"] = true
	var non_finite_hp := dead_checkpoint.duplicate(true)
	non_finite_hp["current_hp"] = NAN
	var invalid_maximum := dead_checkpoint.duplicate(true)
	invalid_maximum["max_hp"] = 0.0
	var hp_above_maximum := dead_checkpoint.duplicate(true)
	hp_above_maximum["current_hp"] = 141.0
	hp_above_maximum["dead"] = false
	var invalid_healing := dead_checkpoint.duplicate(true)
	invalid_healing["healing_multiplier"] = -0.1
	var incoherent_death := dead_checkpoint.duplicate(true)
	incoherent_death["current_hp"] = 10.0
	var incoherent_living := dead_checkpoint.duplicate(true)
	incoherent_living["dead"] = false
	var stale_run := dead_checkpoint.duplicate(true)
	stale_run["run_id"] = &"another-run"
	var forged_ledger := dead_checkpoint.duplicate(true)
	var forged_ledger_value := (forged_ledger["ledger"] as Dictionary).duplicate(true)
	forged_ledger_value["claim_root"] = "0".repeat(64)
	forged_ledger["ledger"] = forged_ledger_value
	var invalid_snapshots: Array[Dictionary] = [
		missing_field,
		unknown_field,
		non_finite_hp,
		invalid_maximum,
		hp_above_maximum,
		invalid_healing,
		incoherent_death,
		incoherent_living,
		stale_run,
		forged_ledger,
	]
	var before_rejections: Dictionary = health.runtime_state_snapshot()
	for index: int in range(invalid_snapshots.size()):
		_suite.assert_true(
			not health.can_restore_replay_snapshot(invalid_snapshots[index]),
			"invalid Health Replay snapshot %d fails pure preflight" % index
		)
		_suite.assert_true(
			not health.restore_replay_snapshot(invalid_snapshots[index]),
			"invalid Health Replay snapshot %d is rejected" % index
		)
		_suite.assert_equal(
			health.runtime_state_snapshot(),
			before_rejections,
			"failed Health Replay restore %d is atomic" % index
		)


func _damage_plan(amount: float, tags: Array[String], token: int) -> RefCounted:
	return DamageInfoScript.from_plan({
		"run_id": "health-pipeline-run",
		"target_id": "player",
		"hostile_source_id": "enemy-health-test",
		"attack_generation": token,
		"action_token": token,
		"amount": amount,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": self,
		"attacker": self,
		"can_crit": false,
		"crit_chance": 0.0,
		"crit_multiplier": 1.5,
		"knockback": Vector2.ZERO,
		"tags": tags,
		"control_effect": {},
	})


func _critical_damage_plan(amount: float, token: int) -> RefCounted:
	return DamageInfoScript.from_plan({
		"run_id": "health-pipeline-run",
		"target_id": "player",
		"hostile_source_id": "enemy-health-test",
		"attack_generation": token,
		"action_token": token,
		"amount": amount,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": self,
		"attacker": self,
		"can_crit": true,
		"crit_chance": 1.0,
		"crit_multiplier": 1.5,
		"knockback": Vector2.ZERO,
		"tags": ["enemy:melee"],
		"control_effect": {},
	})


func _damage_plan_with_target(amount: float, token: int, target_id: String) -> RefCounted:
	return DamageInfoScript.from_plan({
		"run_id": "health-pipeline-run",
		"target_id": target_id,
		"hostile_source_id": "enemy-health-test",
		"attack_generation": token,
		"action_token": token,
		"amount": amount,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": self,
		"attacker": self,
		"can_crit": false,
		"tags": ["enemy:melee"],
	})


func _connect_damage_facts() -> void:
	EventBus.damage_about_to_apply.connect(_on_damage_about_to_apply)
	EventBus.damage_applied.connect(_on_damage_applied)
	EventBus.hit_confirmed.connect(_on_hit_confirmed)


func _disconnect_damage_facts() -> void:
	if EventBus.damage_about_to_apply.is_connected(_on_damage_about_to_apply):
		EventBus.damage_about_to_apply.disconnect(_on_damage_about_to_apply)
	if EventBus.damage_applied.is_connected(_on_damage_applied):
		EventBus.damage_applied.disconnect(_on_damage_applied)
	if EventBus.hit_confirmed.is_connected(_on_hit_confirmed):
		EventBus.hit_confirmed.disconnect(_on_hit_confirmed)


func _reset_damage_facts() -> void:
	_damage_about_count = 0
	_damage_applied_count = 0
	_hit_confirmed_count = 0
	_damaged_signal_count = 0


func _on_damage_applied(_damage_info: Variant, _target: Node, _amount: float) -> void:
	_damage_applied_count += 1


func _on_damage_about_to_apply(_damage_info: Variant, _target: Node) -> void:
	_damage_about_count += 1


func _on_health_damaged(_amount: float, _current_hp: float) -> void:
	_damaged_signal_count += 1
	if _capture_irreversible_order:
		_capture_irreversible_observation("damaged")


func _on_hit_confirmed(_damage_info: Variant, _target: Node, _amount: float) -> void:
	_hit_confirmed_count += 1


func _on_irreversible_entity_died(_entity: Node, _killer: Variant) -> void:
	_capture_irreversible_observation("entity_died")


func _on_irreversible_died(_killer: Variant) -> void:
	_capture_irreversible_observation("died")


func _capture_irreversible_observation(event_name: String) -> void:
	if _observed_health == null or not _observed_health.has_method("hp_loss_state"):
		return
	_irreversible_order.append({
		"event": event_name,
		"hp_loss_state": (_observed_health.call("hp_loss_state") as Dictionary).duplicate(true),
	})
