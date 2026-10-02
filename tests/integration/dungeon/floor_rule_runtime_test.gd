extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RULE_SCRIPTS: Array[GDScript] = [
	preload("res://scripts/dungeon/floor_rules/crumbling_ground_rule.gd"),
	preload("res://scripts/dungeon/floor_rules/void_spores_rule.gd"),
	preload("res://scripts/dungeon/floor_rules/temporal_distortion_rule.gd"),
	preload("res://scripts/dungeon/floor_rules/forge_vents_rule.gd"),
	preload("res://scripts/dungeon/floor_rules/collapsing_plane_rule.gd"),
]
const ACTIVE_FRAME_BY_RULE := {
	"rule_crumbling_ground": 45,
	"rule_void_spores": 60,
	"rule_temporal_distortion": 45,
	"rule_forge_vents": 30,
	"rule_collapsing_plane": 75,
}
const ACTIVE_DURATION_BY_RULE := {
	"rule_crumbling_ground": 90,
	"rule_void_spores": 120,
	"rule_temporal_distortion": 150,
	"rule_forge_vents": 60,
	"rule_collapsing_plane": 180,
}


class EffectAuthority:
	extends RefCounted

	var batches: Array[Array] = []
	var reject_next: bool = false

	func commit_floor_rule_effects(facts: Array) -> bool:
		if reject_next:
			reject_next = false
			return false
		batches.append(facts.duplicate(true))
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	for rule_script: GDScript in RULE_SCRIPTS:
		_test_rule(suite, rule_script)
	_test_authority_rejection_is_atomic(suite)
	_test_reduced_motion_preserves_gameplay_history(suite)
	_test_invalid_configuration(suite)
	suite.finish(get_tree())


func _test_rule(suite, rule_script: GDScript) -> void:
	var authority := EffectAuthority.new()
	var runtime: RefCounted = rule_script.new()
	var rule_id := str(runtime.call("rule_id"))
	var configured: Dictionary = runtime.call("configure", _configuration(true), authority)
	suite.assert_true(bool(configured.get("ok", false)), "%s configures with injected authority" % rule_id)
	var warning: Dictionary = runtime.call("advance_frame", 0)
	suite.assert_true(bool(warning.get("ok", false)), "%s accepts frame zero" % rule_id)
	suite.assert_equal(warning.get("phase"), "warning", "%s begins with a warning phase" % rule_id)
	suite.assert_equal(warning.get("presentation", []).size(), 1, "%s emits one warning transition" % rule_id)
	var warning_cue := warning.get("presentation", [])[0] as Dictionary
	suite.assert_equal(warning_cue.get("visual_mode"), "static_outline", "%s provides reduced-motion static warning" % rule_id)
	suite.assert_true(not bool(warning_cue.get("flash_enabled", true)), "%s suppresses reduced-motion flash" % rule_id)
	suite.assert_true(bool(warning_cue.get("subtitle_required", false)), "%s warning keeps a subtitle cue" % rule_id)

	var active_frame := int(ACTIVE_FRAME_BY_RULE[rule_id])
	var active: Dictionary = runtime.call("advance_frame", active_frame, {"target_ids": ["player"]})
	suite.assert_true(bool(active.get("ok", false)), "%s reaches active phase" % rule_id)
	suite.assert_equal(active.get("phase"), "active", "%s active phase is deterministic" % rule_id)
	suite.assert_true(not (active.get("facts", []) as Array).is_empty(), "%s routes a typed fact through authority" % rule_id)
	var applied_modifier_id := ""
	for fact_value: Variant in active.get("facts", []) as Array:
		var fact := fact_value as Dictionary
		suite.assert_true(str(fact.get("fact_type", "")) in ["damage", "modifier"], "%s emits only typed damage/modifier facts" % rule_id)
		if str(fact.get("fact_type", "")) == "damage":
			var payload := fact["payload"] as Dictionary
			suite.assert_true(bool(payload.get("nonlethal", false)), "%s damage is explicitly nonlethal" % rule_id)
			suite.assert_true(float(payload.get("amount", 99.0)) <= 12.0, "%s damage remains bounded" % rule_id)
		elif str(fact.get("payload", {}).get("operation", "")) == "apply":
			applied_modifier_id = str(fact.get("payload", {}).get("modifier_id", ""))
	suite.assert_true(
		not (active.get("snapshot", {}).get("safe_zone_ids", []) as Array).has(
			str(active.get("snapshot", {}).get("active_zone_id", ""))
		),
		"%s never activates a declared safe zone" % rule_id
	)
	suite.assert_true(not authority.batches.is_empty(), "%s commits effects only through the injected authority" % rule_id)

	var canonical: Dictionary = runtime.call("snapshot")
	var restored: RefCounted = rule_script.new()
	var restore_authority := EffectAuthority.new()
	suite.assert_true(bool(restored.call("configure", _configuration(true), restore_authority).get("ok", false)), "%s restore fixture configures" % rule_id)
	suite.assert_true(bool(restored.call("can_restore_snapshot", canonical)), "%s accepts its canonical Save/Replay snapshot" % rule_id)
	suite.assert_true(bool(restored.call("restore_snapshot", canonical)), "%s restores its canonical Save/Replay snapshot" % rule_id)
	suite.assert_equal(restored.call("snapshot"), canonical, "%s Save/Replay round-trip is exact" % rule_id)
	var forged := canonical.duplicate(true)
	forged["phase"] = "warning" if str(canonical["phase"]) != "warning" else "active"
	suite.assert_true(not bool(restored.call("can_restore_snapshot", forged)), "%s rejects phase/frame drift" % rule_id)

	var recovery_frame := active_frame + int(ACTIVE_DURATION_BY_RULE[rule_id])
	var recovery: Dictionary = runtime.call("advance_frame", recovery_frame)
	suite.assert_true(bool(recovery.get("ok", false)), "%s reaches bounded cleanup" % rule_id)
	suite.assert_equal(recovery.get("phase"), "recovery", "%s exits active state" % rule_id)
	var cleanup_modifier_id := ""
	for fact_value: Variant in recovery.get("facts", []) as Array:
		var fact := fact_value as Dictionary
		if str(fact.get("fact_type", "")) == "modifier" and str(fact.get("payload", {}).get("operation", "")) == "remove":
			cleanup_modifier_id = str(fact.get("payload", {}).get("modifier_id", ""))
	if applied_modifier_id.is_empty():
		suite.assert_equal(cleanup_modifier_id, "", "%s does not remove a modifier it never applied" % rule_id)
	else:
		suite.assert_equal(cleanup_modifier_id, applied_modifier_id, "%s removes the exact applied modifier" % rule_id)
	runtime.call("reset")
	var empty: Dictionary = runtime.call("snapshot")
	suite.assert_true(not bool(empty.get("configured", true)), "%s reset clears configuration" % rule_id)
	suite.assert_equal(empty.get("phase"), "idle", "%s reset returns to idle" % rule_id)


func _test_authority_rejection_is_atomic(suite) -> void:
	var runtime: RefCounted = RULE_SCRIPTS[0].new()
	var authority := EffectAuthority.new()
	runtime.call("configure", _configuration(false), authority)
	runtime.call("advance_frame", 0)
	var before: Dictionary = runtime.call("snapshot")
	authority.reject_next = true
	var rejected: Dictionary = runtime.call("advance_frame", 45)
	suite.assert_true(not bool(rejected.get("ok", true)), "rejected floor-rule fact fails the frame transaction")
	suite.assert_equal(runtime.call("snapshot"), before, "authority rejection restores exact runtime state")
	suite.assert_equal(rejected.get("facts"), [], "authority rejection exposes no committed facts")
	suite.assert_equal(rejected.get("presentation"), [], "authority rejection emits no late presentation notification")


func _test_reduced_motion_preserves_gameplay_history(suite) -> void:
	var normal_authority := EffectAuthority.new()
	var reduced_authority := EffectAuthority.new()
	var normal: RefCounted = RULE_SCRIPTS[4].new()
	var reduced: RefCounted = RULE_SCRIPTS[4].new()
	normal.call("configure", _configuration(false), normal_authority)
	reduced.call("configure", _configuration(true), reduced_authority)
	var normal_result: Dictionary = normal.call("advance_frame", 75, {"target_ids": ["player"]})
	var reduced_result: Dictionary = reduced.call("advance_frame", 75, {"target_ids": ["player"]})
	suite.assert_equal(
		normal_result.get("facts", []),
		reduced_result.get("facts", []),
		"reduced motion changes presentation only, never gameplay history"
	)


func _test_invalid_configuration(suite) -> void:
	var runtime: RefCounted = RULE_SCRIPTS[4].new()
	var missing_authority: Dictionary = runtime.call("configure", _configuration(false))
	suite.assert_true(not bool(missing_authority.get("ok", true)), "floor rules require an injected effect authority")
	var outside := _configuration(false)
	outside["zones"][0]["bounds"]["width"] = 700.0
	var invalid_zone: Dictionary = runtime.call("configure", outside, EffectAuthority.new())
	suite.assert_true(not bool(invalid_zone.get("ok", true)), "floor rules reject zones outside 640x360")


func _configuration(reduced_motion: bool) -> Dictionary:
	return {
		"room_id": "room_combat_pillared_hall",
		"room_seed": 20261002,
		"zones": [
			{"id": "hazard_west", "bounds": {"x": 32.0, "y": 48.0, "width": 160.0, "height": 120.0}},
			{"id": "safe_core", "bounds": {"x": 224.0, "y": 96.0, "width": 192.0, "height": 168.0}},
		],
		"safe_zone_ids": ["safe_core"],
		"reduced_motion": reduced_motion,
		"hit_flash_enabled": true,
	}
