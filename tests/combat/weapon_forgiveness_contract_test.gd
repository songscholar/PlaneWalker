extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponForgivenessScript := preload(
	"res://scripts/combat/weapons/weapon_forgiveness.gd"
)

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_five_descriptors_freeze_to_strict_fingerprinted_envelopes()
	_test_tampering_and_cross_weapon_reuse_fail_closed()
	_test_successful_commit_context_is_explicit_and_one_shot_owned()
	_suite.finish(get_tree())


func _test_five_descriptors_freeze_to_strict_fingerprinted_envelopes() -> void:
	for descriptor: Dictionary in _descriptors():
		var weapon_id := StringName(str(descriptor["weapon_id"]))
		var frozen: Dictionary = WeaponForgivenessScript.freeze_from_context(
			{"character_forgiveness": descriptor.duplicate(true)},
			weapon_id
		)
		_suite.assert_true(bool(frozen.get("ok", false)), "%s descriptor freezes" % weapon_id)
		var envelope := frozen.get("envelope", {}) as Dictionary
		_suite.assert_true(
			WeaponForgivenessScript.is_valid_envelope(envelope, weapon_id),
			"%s envelope validates" % weapon_id
		)
		_suite.assert_equal(
			str((envelope.get("descriptor", {}) as Dictionary).get("weapon_id", "")),
			str(weapon_id),
			"%s envelope freezes canonical weapon identity" % weapon_id
		)
		_suite.assert_equal(
			str(envelope.get("fingerprint", "")).length(),
			64,
			"%s envelope has a SHA-256 fingerprint" % weapon_id
		)


func _test_tampering_and_cross_weapon_reuse_fail_closed() -> void:
	var frozen: Dictionary = WeaponForgivenessScript.freeze_from_context(
		{"character_forgiveness": _descriptors()[0]},
		&"sword"
	)
	var envelope := (frozen.get("envelope", {}) as Dictionary).duplicate(true)
	(envelope["descriptor"] as Dictionary)["recovery_reduction_frames"] = 5
	_suite.assert_true(
		not WeaponForgivenessScript.is_valid_envelope(envelope, &"sword"),
		"post-freeze descriptor mutation invalidates the envelope"
	)

	var canonical := frozen.get("envelope", {}) as Dictionary
	_suite.assert_true(
		not WeaponForgivenessScript.is_valid_envelope(canonical, &"bow"),
		"a frozen Sword descriptor cannot be reused by Bow"
	)
	var extra_field := _descriptors()[1].duplicate(true)
	extra_field["stack_count"] = 2
	_suite.assert_true(
		not bool(WeaponForgivenessScript.freeze_from_context(
			{"character_forgiveness": extra_field},
			&"bow"
		).get("ok", true)),
		"unknown descriptor fields fail closed"
	)


func _test_successful_commit_context_is_explicit_and_one_shot_owned() -> void:
	var frozen: Dictionary = WeaponForgivenessScript.freeze_from_context(
		{"character_forgiveness": _descriptors()[2]},
		&"gun"
	)
	var plan := {"weapon_id": "gun"}
	WeaponForgivenessScript.attach_to_plan(plan, frozen.get("envelope", {}))
	var consume := WeaponForgivenessScript.consumption_context(plan, &"gun")
	_suite.assert_equal(consume.get("consume_forgiveness"), true, "successful commit requests one consumption")
	_suite.assert_equal(consume.get("weapon_id"), "gun", "consumption identifies the owning weapon")
	_suite.assert_equal(
		consume.get("character_forgiveness_fingerprint"),
		(plan.get("character_forgiveness", {}) as Dictionary).get("fingerprint"),
		"consumption returns the exact frozen fingerprint"
	)
	_suite.assert_equal(
		WeaponForgivenessScript.consumption_context({"weapon_id": "gun"}, &"gun"),
		{},
		"an action without a frozen descriptor cannot consume one"
	)


func _descriptors() -> Array[Dictionary]:
	return [
		{
			"weapon_id": &"sword",
			"expires_after_frames": 180,
			"recovery_reduction_frames": 4,
			"minimum_recovery_frames": 1,
		},
		{
			"weapon_id": &"bow",
			"expires_after_frames": 180,
			"full_charge_frames": 44,
		},
		{
			"weapon_id": &"gun",
			"expires_after_frames": 180,
			"perfect_start_frame": 26,
			"perfect_end_frame": 37,
		},
		{
			"weapon_id": &"staff",
			"expires_after_frames": 180,
			"window_extension_frames": 60,
			"window_cap_frames": 360,
		},
		{
			"weapon_id": &"gauntlets",
			"expires_after_frames": 180,
			"combo_extension_frames": 30,
			"combo_cap_frames": 150,
		},
	]
