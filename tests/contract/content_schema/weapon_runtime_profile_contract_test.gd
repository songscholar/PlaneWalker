extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const SCHEMA_PATH := "res://data/schemas/weapon_runtime_profile_v1.schema.json"
const RUNTIME_PATH := "res://scripts/combat/weapons/weapon_runtime_profile.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_schema_contract(suite)
	var runtime_script: Variant = _load_runtime_script(suite)
	if runtime_script != null:
		_test_valid_sword_profile(suite, runtime_script)
		_test_invalid_profiles_fail_closed(suite, runtime_script)
	suite.finish(get_tree())


func _test_schema_contract(suite) -> void:
	var schema_value: Variant = _read_json(SCHEMA_PATH, suite)
	if not schema_value is Dictionary:
		return
	var schema: Dictionary = schema_value
	suite.assert_equal(
		schema.get("$id"),
		"planewalker://schemas/weapon-runtime-profile/1.0.0",
		"weapon runtime profile schema id is stable"
	)
	suite.assert_equal(schema.get("additionalProperties"), false, "profile rejects unknown root fields")
	for field: String in [
		"id", "category", "availability", "name_key", "description_key", "tags",
		"compatibility", "effects", "references", "profile_version", "weapon_id",
		"actions", "resources", "capabilities", "payloads", "cues",
	]:
		suite.assert_true(schema.get("required", []).has(field), "profile schema requires %s" % field)

	var properties: Dictionary = schema.get("properties", {})
	suite.assert_equal(
		properties.get("category", {}).get("const"),
		"weapon_runtime_profile",
		"profile category is closed"
	)
	suite.assert_equal(
		properties.get("effects", {}).get("maxProperties"),
		0,
		"runtime profiles cannot embed executable content effects"
	)
	suite.assert_equal(
		properties.get("profile_version", {}).get("minimum"),
		1,
		"profile versions are positive integers"
	)
	var runtime_kinds: Array = properties.get("runtime_kind", {}).get("enum", [])
	for runtime_kind: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		suite.assert_true(runtime_kinds.has(runtime_kind), "schema supports runtime kind %s" % runtime_kind)
	suite.assert_equal(
		properties.get("time_interactions", {}).get("additionalProperties"),
		false,
		"time interaction ids are closed to canonical abilities"
	)
	suite.assert_equal(
		properties.get("boss_interactions", {}).get("additionalProperties"),
		false,
		"Boss interaction ids are closed to declared Boss contracts"
	)

	var action_definition: Dictionary = schema.get("$defs", {}).get("action", {})
	var action_properties: Dictionary = action_definition.get("properties", {})
	for frame_field: String in ["windup_frames", "active_frames", "recovery_frames", "buffer_frames"]:
		suite.assert_equal(
			action_properties.get(frame_field, {}).get("minimum"),
			1,
			"%s is a positive frame count" % frame_field
		)
	var semantic_actions: Array = action_properties.get("semantic_action", {}).get("enum", [])
	for semantic_action: String in [
		"weapon_primary", "weapon_secondary", "weapon_utility",
		"weapon_skill", "weapon_ultimate",
	]:
		suite.assert_true(
			semantic_actions.has(semantic_action),
			"schema supports semantic action %s" % semantic_action
		)


func _test_valid_sword_profile(suite, runtime_script: Variant) -> void:
	var profile = runtime_script.new()
	var source := _valid_sword_profile()
	var result: Dictionary = profile.configure(source)
	suite.assert_true(bool(result.get("ok", false)), "sword_m1_v1 configures: %s" % str(result.get("context", {})))
	var snapshot: Dictionary = profile.snapshot()
	suite.assert_equal(snapshot.get("id"), "sword_m1_v1", "profile identity is retained")
	suite.assert_equal(snapshot.get("profile_version"), 1, "profile version is retained")
	suite.assert_equal(snapshot.get("weapon_id"), "sword", "profile weapon identity is retained")
	suite.assert_true(snapshot.get("availability", []).has("M1"), "sword_m1_v1 includes M1")
	suite.assert_true(snapshot.get("availability", []).has("CURRENT"), "sword_m1_v1 includes CURRENT")
	suite.assert_equal(
		profile.action_for_semantic(&"weapon_primary").get("action_id"),
		"sword.light",
		"semantic primary resolves to the configured action"
	)
	suite.assert_equal(
		profile.resource(&"combo").get("maximum"),
		3,
		"profile exposes its validated resource contract"
	)
	suite.assert_true(profile.has_capability(&"weapon.damage"), "profile exposes declared capabilities")
	suite.assert_equal(snapshot.get("runtime_kind"), "sword", "profile retains its runtime kind")
	suite.assert_equal(
		profile.time_interaction(&"stop").get("type"),
		"duration_modifier",
		"profile exposes a typed Time Stop descriptor"
	)
	suite.assert_equal(
		profile.boss_interaction(&"chrono_warden").get("type"),
		"poise_conversion",
		"profile exposes a typed Chrono Warden conversion"
	)
	suite.assert_equal(
		profile.payload(&"sword.light.hit").get("kind"),
		"melee_hitbox",
		"profile exposes a validated payload"
	)
	suite.assert_equal(
		profile.cue(&"sword.light").get("audio_id"),
		"sword_swing",
		"profile exposes a validated cue"
	)

	source["availability"].clear()
	source["actions"][0]["windup_frames"] = 999
	suite.assert_true(snapshot.get("availability", []).has("M1"), "configured profile is isolated from caller mutation")
	suite.assert_equal(profile.action_for_semantic(&"weapon_primary").get("windup_frames"), 6, "actions are deep copied")


func _test_invalid_profiles_fail_closed(suite, runtime_script: Variant) -> void:
	var profile = runtime_script.new()
	var valid := _valid_sword_profile()
	var configured: Dictionary = profile.configure(valid)
	suite.assert_true(bool(configured.get("ok", false)), "fail-closed fixture begins from a valid profile")
	var accepted: Dictionary = profile.snapshot()

	var invalid_cases: Array[Dictionary] = []
	invalid_cases.append(_case("unknown root field", func(value: Dictionary): value["script_path"] = "res://hostile.gd"))
	invalid_cases.append(_case("wrong category", func(value: Dictionary): value["category"] = "weapon"))
	invalid_cases.append(_case("non-empty effects", func(value: Dictionary): value["effects"] = {"script": "run"}))
	invalid_cases.append(_case("non-positive profile version", func(value: Dictionary): value["profile_version"] = 0))
	invalid_cases.append(_case("profile weapon mismatch", func(value: Dictionary): value["weapon_id"] = "bow"))
	invalid_cases.append(_case("runtime kind mismatch", func(value: Dictionary): value["runtime_kind"] = "bow"))
	invalid_cases.append(_case("sword M1 profile missing M1", func(value: Dictionary): value["availability"] = ["CURRENT"]))
	invalid_cases.append(_case("sword M1 profile missing CURRENT", func(value: Dictionary): value["availability"] = ["M1"]))
	invalid_cases.append(_case("zero windup", func(value: Dictionary): value["actions"][0]["windup_frames"] = 0))
	invalid_cases.append(_case("zero active", func(value: Dictionary): value["actions"][0]["active_frames"] = 0))
	invalid_cases.append(_case("zero recovery", func(value: Dictionary): value["actions"][0]["recovery_frames"] = 0))
	invalid_cases.append(_case("cancel after recovery", func(value: Dictionary): value["actions"][0]["cancel_from_frame"] = 12))
	invalid_cases.append(_case("duplicate action id", func(value: Dictionary): value["actions"].append(value["actions"][0].duplicate(true))))
	invalid_cases.append(_case("unknown resource cost", func(value: Dictionary): value["actions"][0]["resource_costs"] = {"ghost": 1}))
	invalid_cases.append(_case("duplicate resource id", func(value: Dictionary): value["resources"].append(value["resources"][0].duplicate(true))))
	invalid_cases.append(_case("resource initial below minimum", func(value: Dictionary): value["resources"][0]["initial"] = -1))
	invalid_cases.append(_case("unknown payload reference", func(value: Dictionary): value["actions"][0]["payload_id"] = "missing.payload"))
	invalid_cases.append(_case("unknown cue reference", func(value: Dictionary): value["actions"][0]["cue_id"] = "missing.cue"))
	invalid_cases.append(_case("duplicate payload id", func(value: Dictionary): value["payloads"].append(value["payloads"][0].duplicate(true))))
	invalid_cases.append(_case("duplicate cue id", func(value: Dictionary): value["cues"].append(value["cues"][0].duplicate(true))))
	invalid_cases.append(_case("invalid capability", func(value: Dictionary): value["capabilities"] = ["Weapon Damage"]))
	invalid_cases.append(_case("unknown time interaction", func(value: Dictionary): value["time_interactions"]["time_travel"] = value["time_interactions"]["stop"].duplicate(true)))
	invalid_cases.append(_case("time interaction script field", func(value: Dictionary): value["time_interactions"]["stop"]["script_path"] = "res://hostile.gd"))
	invalid_cases.append(_case("time interaction nested executable parameter", func(value: Dictionary): value["time_interactions"]["stop"]["parameters"]["nested"] = {"handler_name": "apply_stop"}))
	invalid_cases.append(_case("unknown Boss interaction", func(value: Dictionary): value["boss_interactions"]["unknown_boss"] = value["boss_interactions"]["chrono_warden"].duplicate(true)))
	invalid_cases.append(_case("Boss interaction method parameter", func(value: Dictionary): value["boss_interactions"]["chrono_warden"]["parameters"]["method_name"] = "apply_poison"))

	for invalid_case: Dictionary in invalid_cases:
		var candidate: Dictionary = valid.duplicate(true)
		var mutate: Callable = invalid_case["mutate"]
		mutate.call(candidate)
		var result: Dictionary = profile.configure(candidate)
		suite.assert_true(not bool(result.get("ok", false)), "%s fails closed" % invalid_case["label"])
		suite.assert_equal(profile.snapshot(), accepted, "%s preserves the accepted profile" % invalid_case["label"])


func _valid_sword_profile() -> Dictionary:
	return {
		"id": "sword_m1_v1",
		"category": "weapon_runtime_profile",
		"availability": ["M1", "CURRENT"],
		"name_key": "WEAPON_SWORD_NAME",
		"description_key": "WEAPON_SWORD_DESC",
		"tags": ["melee", "m1_parity"],
		"compatibility": {"weapon_ids": ["sword"]},
		"effects": {},
		"references": ["sword"],
		"profile_version": 1,
		"weapon_id": "sword",
		"runtime_kind": "sword",
		"actions": [
			{
				"action_id": "sword.light",
				"semantic_action": "weapon_primary",
				"activation_mode": "press",
				"windup_frames": 6,
				"active_frames": 5,
				"recovery_frames": 11,
				"cancel_from_frame": 6,
				"buffer_frames": 12,
				"movement_multiplier": 0.55,
				"resource_costs": {"combo": 0},
				"payload_id": "sword.light.hit",
				"cue_id": "sword.light",
			},
			{
				"action_id": "sword.heavy",
				"semantic_action": "weapon_secondary",
				"activation_mode": "press",
				"windup_frames": 21,
				"active_frames": 8,
				"recovery_frames": 27,
				"cancel_from_frame": 15,
				"buffer_frames": 12,
				"movement_multiplier": 0.2,
				"resource_costs": {"combo": 0},
				"payload_id": "sword.heavy.hit",
				"cue_id": "sword.heavy",
			},
		],
		"resources": [
			{"resource_id": "combo", "minimum": 0, "maximum": 3, "initial": 0},
		],
		"capabilities": ["weapon.attack_speed", "weapon.combo", "weapon.damage"],
		"payloads": [
			{
				"payload_id": "sword.light.hit",
				"kind": "melee_hitbox",
				"parameters": {"damage_multiplier": 0.8, "knockback": 120.0},
			},
			{
				"payload_id": "sword.heavy.hit",
				"kind": "melee_hitbox",
				"parameters": {"damage_multiplier": 2.0, "knockback": 260.0},
			},
		],
		"cues": [
			{
				"cue_id": "sword.light",
				"animation_id": "sword_light",
				"vfx_id": "sword_arc_light",
				"audio_id": "sword_swing",
				"camera_id": "impact_light",
			},
			{
				"cue_id": "sword.heavy",
				"animation_id": "sword_heavy",
				"vfx_id": "sword_arc_heavy",
				"audio_id": "sword_heavy_swing",
				"camera_id": "impact_heavy",
			},
		],
		"time_interactions": {
			"stop": {
				"interaction_id": "sword.stop.judgment",
				"type": "duration_modifier",
				"parameters": {"duration_multiplier": 1.0},
			},
			"rewind": {
				"interaction_id": "sword.rewind.strike",
				"type": "next_action_modifier",
				"parameters": {"damage_multiplier": 1.0},
			},
			"accelerate": {
				"interaction_id": "sword.accelerate.plan",
				"type": "future_timing_modifier",
				"parameters": {"timing_multiplier": 1.0},
			},
			"rift": {
				"interaction_id": "sword.rift.guard",
				"type": "zone_conversion",
				"parameters": {"radius_multiplier": 1.0},
			},
		},
		"boss_interactions": {
			"chrono_warden": {
				"conversion_id": "sword.chrono_warden.poise",
				"type": "poise_conversion",
				"parameters": {"poise_multiplier": 1.0},
			},
		},
	}


func _case(label: String, mutate: Callable) -> Dictionary:
	return {"label": label, "mutate": mutate}


func _load_runtime_script(suite) -> Variant:
	suite.assert_true(FileAccess.file_exists(RUNTIME_PATH), "%s exists" % RUNTIME_PATH)
	if not FileAccess.file_exists(RUNTIME_PATH):
		return null
	var runtime_script: Variant = load(RUNTIME_PATH)
	suite.assert_true(runtime_script != null, "%s loads" % RUNTIME_PATH)
	return runtime_script


func _read_json(path: String, suite) -> Variant:
	suite.assert_true(FileAccess.file_exists(path), "%s exists" % path)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s can be opened" % path)
	if file == null:
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	suite.assert_equal(error, OK, "%s contains valid JSON" % path)
	return parser.data if error == OK else {}
