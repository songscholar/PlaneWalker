extends Node

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const DamageResolutionScript := preload("res://scripts/combat/damage_resolution.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const RESOLUTION_FIELDS: Array[String] = [
	"action_token",
	"attack_generation",
	"finalized_damage",
	"guard_kind",
	"hostile_source_id",
	"irreversible",
	"original_amount",
	"post_accessibility_amount",
	"post_character_defense_amount",
	"post_defense_amount",
	"post_weapon_defense_amount",
	"prevent_reason",
	"prevented",
	"resolution_id",
	"run_id",
	"tags",
	"target_id",
]

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_damage_info_from_plan_deep_freezes_source_collections()
	_test_damage_info_copy_for_source_preserves_frozen_plan()
	_test_damage_info_rejects_invalid_plans()
	_test_prevented_resolution_is_true_zero_damage()
	_test_applied_resolution_has_exact_isolated_snapshot()
	_test_resolution_id_is_stable_and_instance_independent()
	_test_resolution_id_distinguishes_hit_identity()
	_test_resolution_rejects_invalid_applied_damage_and_context()
	_suite.finish(get_tree())


func _test_damage_info_from_plan_deep_freezes_source_collections() -> void:
	var original_tags: Array[String] = ["enemy:melee", "control:slow"]
	var original_control := {
		"kind": "slow",
		"parameters": {"ratio": 0.25, "frames": 30},
		"points": [Vector2(2.0, 3.0)],
	}
	var plan := _damage_plan(24.0)
	plan["tags"] = original_tags
	plan["control_effect"] = original_control
	var info = DamageInfoScript.from_plan(plan)
	_suite.assert_true(info != null, "valid damage plan creates immutable DamageInfo")
	if info == null:
		return

	original_tags.append("mutated:source")
	(original_control["parameters"] as Dictionary)["ratio"] = 99.0
	(original_control["points"] as Array).append(Vector2(9.0, 9.0))
	(plan["tags"] as Array).append("mutated:plan")
	var exposed_tags: Array[String] = info.tags
	exposed_tags.append("mutated:getter")
	var exposed_control: Dictionary = info.control_effect
	(exposed_control["parameters"] as Dictionary)["frames"] = 999
	var exposed_snapshot: Dictionary = info.snapshot()
	(exposed_snapshot["tags"] as Array).append("mutated:snapshot")
	(exposed_snapshot["control_effect"] as Dictionary)["kind"] = "stun"

	_suite.assert_equal(info.tags, ["enemy:melee", "control:slow"], "DamageInfo tags are isolated from source and getter mutation")
	_suite.assert_equal(
		(info.control_effect["parameters"] as Dictionary)["ratio"],
		0.25,
		"DamageInfo nested control values are deep-frozen"
	)
	_suite.assert_equal(
		(info.control_effect["parameters"] as Dictionary)["frames"],
		30,
		"DamageInfo control getter returns a deep copy"
	)
	_suite.assert_equal(info.snapshot()["control_effect"]["kind"], "slow", "DamageInfo snapshot returns a deep copy")
	_suite.assert_equal(str(info.run_id), "run-a", "DamageInfo projects stable run identity")
	_suite.assert_equal(str(info.target_id), "player", "DamageInfo projects stable target identity")
	_suite.assert_equal(str(info.hostile_source_id), "enemy-a", "DamageInfo projects hostile identity")
	_suite.assert_equal(info.attack_generation, 3, "DamageInfo freezes attack generation")
	_suite.assert_equal(info.hit_index, 2, "DamageInfo freezes authored hit index")


func _test_damage_info_copy_for_source_preserves_frozen_plan() -> void:
	var first_source := Node.new()
	var replacement_source := Node.new()
	var attacker := Node.new()
	var plan := _damage_plan(12.5)
	plan["source"] = first_source
	plan["attacker"] = attacker
	plan["control_effect"] = {"kind": "push", "nested": {"distance": 4.0}}
	var info = DamageInfoScript.from_plan(plan)
	var copied = info.copy_for_source(replacement_source) if info != null else null
	_suite.assert_true(copied != null, "copy_for_source returns a DamageInfo")
	if copied != null:
		_suite.assert_true(copied.source == replacement_source, "copy_for_source substitutes only source")
		_suite.assert_true(copied.attacker == attacker, "copy_for_source preserves attacker")
		_suite.assert_equal(copied.amount, 12.5, "copy_for_source preserves amount")
		_suite.assert_equal(copied.tags, ["enemy:melee"], "copy_for_source preserves tags")
		var copied_tags: Array[String] = copied.tags
		copied_tags.append("mutated:getter")
		_suite.assert_equal(copied.tags, ["enemy:melee"], "copied tags remain getter-isolated")
		_suite.assert_equal(info.tags, ["enemy:melee"], "copied tag mutation does not alter original")
		var copied_control: Dictionary = copied.control_effect
		(copied_control["nested"] as Dictionary)["distance"] = 100.0
		_suite.assert_equal(
			(copied.control_effect["nested"] as Dictionary)["distance"],
			4.0,
			"copied control getter remains isolated"
		)
		_suite.assert_equal(info.source, first_source, "copy_for_source does not mutate original source")
	first_source.free()
	replacement_source.free()
	attacker.free()


func _test_damage_info_rejects_invalid_plans() -> void:
	var cases: Array[Dictionary] = []
	var missing_identity := _damage_plan(10.0)
	missing_identity.erase("run_id")
	cases.append(missing_identity)
	var negative_amount := _damage_plan(-0.01)
	cases.append(negative_amount)
	var infinite_amount := _damage_plan(INF)
	cases.append(infinite_amount)
	var invalid_type := _damage_plan(10.0)
	invalid_type["damage_type"] = 999
	cases.append(invalid_type)
	var negative_generation := _damage_plan(10.0)
	negative_generation["attack_generation"] = -1
	cases.append(negative_generation)
	var invalid_crit := _damage_plan(10.0)
	invalid_crit["crit_chance"] = NAN
	cases.append(invalid_crit)
	var invalid_knockback := _damage_plan(10.0)
	invalid_knockback["knockback"] = Vector2(INF, 0.0)
	cases.append(invalid_knockback)
	var invalid_tags := _damage_plan(10.0)
	invalid_tags["tags"] = ["enemy:melee", 7]
	cases.append(invalid_tags)
	var invalid_control := _damage_plan(10.0)
	invalid_control["control_effect"] = {"ratio": INF}
	cases.append(invalid_control)
	var oversized_identity := _damage_plan(10.0)
	oversized_identity["hostile_source_id"] = "x".repeat(65)
	cases.append(oversized_identity)
	for index: int in range(cases.size()):
		_suite.assert_true(
			DamageInfoScript.from_plan(cases[index]) == null,
			"invalid damage plan %d fails closed" % index
		)

func _test_prevented_resolution_is_true_zero_damage() -> void:
	var context := _resolution_context()
	context["post_weapon_defense_amount"] = 0.0
	context["post_character_defense_amount"] = 0.0
	context["post_accessibility_amount"] = 0.0
	context["post_defense_amount"] = 0.0
	context["guard_kind"] = &"sword_perfect"
	var resolution = DamageResolutionScript.prevented(&"sword_perfect", context)
	_suite.assert_true(resolution != null, "valid prevention creates a DamageResolution")
	if resolution == null:
		return
	_suite.assert_true(resolution.is_prevented(), "prevented result reports prevention")
	_suite.assert_close(resolution.finalized_damage(), 0.0, "prevented result fixes finalized damage at zero")
	var snapshot: Dictionary = resolution.snapshot()
	_suite.assert_equal(snapshot["prevent_reason"], &"sword_perfect", "prevention preserves typed reason")
	_suite.assert_equal(snapshot["guard_kind"], &"sword_perfect", "prevention preserves guard kind")
	_suite.assert_equal(snapshot["prevented"], true, "prevention snapshot is explicit")


func _test_applied_resolution_has_exact_isolated_snapshot() -> void:
	var context := _resolution_context()
	context["post_weapon_defense_amount"] = 80.0
	context["post_character_defense_amount"] = 40.0
	context["post_accessibility_amount"] = 20.0
	context["post_defense_amount"] = 17.0
	context["guard_kind"] = &"guardian_normal"
	var resolution = DamageResolutionScript.applied(17.0, context)
	_suite.assert_true(resolution != null, "positive finalized damage creates an applied resolution")
	if resolution == null:
		return
	_suite.assert_true(not resolution.is_prevented(), "applied resolution is not prevented")
	_suite.assert_close(resolution.finalized_damage(), 17.0, "applied resolution exposes final amount")
	var snapshot: Dictionary = resolution.snapshot()
	var actual_fields: Array[String] = []
	for key: Variant in snapshot.keys():
		actual_fields.append(str(key))
	actual_fields.sort()
	_suite.assert_equal(actual_fields, RESOLUTION_FIELDS, "DamageResolution snapshot has exactly seventeen fields")
	_suite.assert_equal(snapshot["post_weapon_defense_amount"], 80.0, "weapon stage is frozen")
	_suite.assert_equal(snapshot["post_character_defense_amount"], 40.0, "character stage is frozen")
	_suite.assert_equal(snapshot["post_accessibility_amount"], 20.0, "accessibility stage is frozen")
	_suite.assert_equal(snapshot["post_defense_amount"], 17.0, "flat defense stage is frozen")
	(snapshot["tags"] as Array).append("mutated:snapshot")
	snapshot["finalized_damage"] = 999.0
	_suite.assert_equal(resolution.snapshot()["tags"], ["enemy:melee"], "resolution tags are snapshot-isolated")
	_suite.assert_close(resolution.finalized_damage(), 17.0, "resolution numeric state is snapshot-isolated")
	(context["tags"] as Array).append("mutated:context")
	_suite.assert_equal(resolution.snapshot()["tags"], ["enemy:melee"], "resolution deep-copies source context")


func _test_resolution_id_is_stable_and_instance_independent() -> void:
	var transient_a := Node.new()
	var transient_b := Node.new()
	var context_a := _resolution_context()
	var context_b := _resolution_context()
	var first = DamageResolutionScript.applied(94.0, context_a)
	var second = DamageResolutionScript.applied(94.0, context_b)
	_suite.assert_true(first != null and second != null, "stable resolution fixtures are valid")
	if first != null and second != null:
		var first_id := str(first.snapshot()["resolution_id"])
		var second_id := str(second.snapshot()["resolution_id"])
		_suite.assert_equal(first_id, second_id, "resolution ID ignores transient instance references")
		_suite.assert_true(not first_id.contains(str(transient_a.get_instance_id())), "resolution ID never embeds an instance ID")
		var changed_context := _resolution_context()
		changed_context["action_token"] = 43
		var changed = DamageResolutionScript.applied(94.0, changed_context)
		_suite.assert_true(
			changed != null and str(changed.snapshot()["resolution_id"]) != first_id,
			"stable resolution ID changes with authoritative identity"
		)
	transient_a.free()
	transient_b.free()


func _test_resolution_id_distinguishes_hit_identity() -> void:
	var base_context := _resolution_context()
	var changed_hit_index := _resolution_context()
	changed_hit_index["hit_index"] = int(base_context["hit_index"]) + 1
	var changed_source_generation := _resolution_context()
	changed_source_generation["source_generation"] = int(base_context["source_generation"]) + 1
	var base_resolution = DamageResolutionScript.applied(94.0, base_context)
	var hit_resolution = DamageResolutionScript.applied(94.0, changed_hit_index)
	var source_resolution = DamageResolutionScript.applied(94.0, changed_source_generation)
	_suite.assert_true(
		base_resolution != null and hit_resolution != null and source_resolution != null,
		"hit-identity resolution fixtures are valid"
	)
	if base_resolution == null or hit_resolution == null or source_resolution == null:
		return
	var base_id := str(base_resolution.snapshot()["resolution_id"])
	_suite.assert_true(
		str(hit_resolution.snapshot()["resolution_id"]) != base_id,
		"resolution ID changes when hit_index changes"
	)
	_suite.assert_true(
		str(source_resolution.snapshot()["resolution_id"]) != base_id,
		"resolution ID changes when source_generation changes"
	)


func _test_resolution_rejects_invalid_applied_damage_and_context() -> void:
	_suite.assert_true(DamageResolutionScript.applied(0.0, _resolution_context()) == null, "applied zero damage is rejected")
	_suite.assert_true(DamageResolutionScript.applied(-1.0, _resolution_context()) == null, "applied negative damage is rejected")
	_suite.assert_true(DamageResolutionScript.applied(INF, _resolution_context()) == null, "applied infinite damage is rejected")
	_suite.assert_true(DamageResolutionScript.applied(NAN, _resolution_context()) == null, "applied NaN damage is rejected")
	_suite.assert_true(DamageResolutionScript.prevented(&"", _resolution_context()) == null, "empty prevention reason is rejected")
	var invalid_stage := _resolution_context()
	invalid_stage["post_accessibility_amount"] = INF
	_suite.assert_true(DamageResolutionScript.applied(94.0, invalid_stage) == null, "non-finite resolution stage is rejected")
	var missing_target := _resolution_context()
	missing_target.erase("target_id")
	_suite.assert_true(DamageResolutionScript.applied(94.0, missing_target) == null, "missing target identity is rejected")
	var invalid_tags := _resolution_context()
	invalid_tags["tags"] = ["enemy:melee", 9]
	_suite.assert_true(DamageResolutionScript.applied(94.0, invalid_tags) == null, "non-string resolution tag is rejected")
	var oversized_identity := _resolution_context()
	oversized_identity["run_id"] = "r".repeat(65)
	_suite.assert_true(DamageResolutionScript.applied(94.0, oversized_identity) == null, "resolution identity is capped at sixty-four characters")
	var invalid_hit_index := _resolution_context()
	invalid_hit_index["hit_index"] = -1
	_suite.assert_true(DamageResolutionScript.applied(94.0, invalid_hit_index) == null, "negative hit index is rejected")
	var invalid_source_generation := _resolution_context()
	invalid_source_generation["source_generation"] = -1
	_suite.assert_true(DamageResolutionScript.applied(94.0, invalid_source_generation) == null, "negative source generation is rejected")


func _damage_plan(amount: float) -> Dictionary:
	return {
		"run_id": &"run-a",
		"target_id": &"player",
		"hostile_source_id": &"enemy-a",
		"attack_generation": 3,
		"hit_index": 2,
		"action_token": 42,
		"amount": amount,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"can_crit": true,
		"crit_chance": 0.15,
		"crit_multiplier": 1.5,
		"knockback": Vector2(20.0, -4.0),
		"tags": ["enemy:melee"],
		"source_generation": 7,
		"control_effect": {},
	}


func _resolution_context() -> Dictionary:
	return {
		"run_id": &"run-a",
		"target_id": &"player",
		"hostile_source_id": &"enemy-a",
		"attack_generation": 3,
		"hit_index": 2,
		"action_token": 42,
		"source_generation": 7,
		"original_amount": 100.0,
		"post_weapon_defense_amount": 100.0,
		"post_character_defense_amount": 100.0,
		"post_accessibility_amount": 100.0,
		"post_defense_amount": 94.0,
		"guard_kind": &"none",
		"irreversible": false,
		"tags": ["enemy:melee"],
	}
