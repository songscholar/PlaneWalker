extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const CHARACTERS: Array[StringName] = [
	&"wanderer",
	&"time_guardian",
	&"void_walker",
	&"primordial_knight",
	&"time_lord",
]
const WEAPONS: Array[StringName] = [&"sword", &"bow", &"gun", &"staff", &"gauntlets"]
const TIME_PAIRS: Array[Array] = [
	[&"stop", &"rewind"],
	[&"stop", &"rift"],
	[&"stop", &"accelerate"],
	[&"rewind", &"rift"],
	[&"rewind", &"accelerate"],
	[&"rift", &"accelerate"],
]
const CONTENT_BY_WEAPON := {
	&"sword": {
		"starter": &"frozen_burst",
		"payoff": &"bls_stop_weakpoint",
		"active": &"absolute_zero_device",
	},
	&"bow": {
		"starter": &"piercing_draw",
		"payoff": &"bls_weakpoint_refund",
		"active": &"railshot_module",
	},
	&"gun": {
		"starter": &"anchor_thread",
		"payoff": &"bls_rewind_path",
		"active": &"paradox_beacon",
	},
	&"staff": {
		"starter": &"rift_engine",
		"payoff": &"bls_rift_bloom",
		"active": &"gravity_snare_device",
	},
	&"gauntlets": {
		"starter": &"overdrive_heart",
		"payoff": &"bls_overdrive_refund",
		"active": &"redline_injector",
	},
}
const GENERAL_RISK_ID := &"curse_fickle_time"

var _suite
var _registry: RefCounted


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report: RefCounted = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(
		not report.call("has_blocking_errors"),
		"Launch pool matrix loads the authoritative Base Pack"
	)
	if report.call("has_blocking_errors"):
		_suite.finish(get_tree())
		return

	var case_index := 0
	var activated_content_ids: Dictionary = {}
	for character_id: StringName in CHARACTERS:
		for weapon_id: StringName in WEAPONS:
			for time_pair: Array in TIME_PAIRS:
				var result := await _run_case(
					character_id,
					weapon_id,
					time_pair,
					20260901 + (case_index % 30),
					case_index
				)
				if bool(result.get("configured", false)):
					case_index += 1
				var active_id := str(result.get("active_content_id", ""))
				if not active_id.is_empty():
					activated_content_ids[active_id] = true
	_suite.assert_equal(case_index, 150, "matrix executes all five characters, five weapons, and six time pairs")
	_suite.assert_equal(
		activated_content_ids.size(),
		5,
		"matrix executes one representative active route for every weapon"
	)
	_suite.assert_true(
		get_tree().get_nodes_in_group("time_rifts").is_empty(),
		"Launch pool matrix leaves no shared Time Rift nodes"
	)
	_suite.finish(get_tree())


func _run_case(
	character_id: StringName,
	weapon_id: StringName,
	time_pair: Array,
	seed_value: int,
	case_index: int
) -> Dictionary:
	var label := "%s × %s × %s+%s" % [
		str(character_id),
		str(weapon_id),
		str(time_pair[0]),
		str(time_pair[1]),
	]
	var character_profile: Dictionary = _registry.call(
		"resolve_character_runtime_profile", character_id, &"LAUNCH"
	)
	var talent_ids := character_profile.get("talent_ids", []) as Array
	_suite.assert_equal(talent_ids.size(), 3, "%s resolves three character talents" % label)
	if talent_ids.size() != 3:
		return {}
	var talent_id := str(talent_ids[case_index % talent_ids.size()])
	var talent_definition: Dictionary = _registry.call(
		"get_content",
		StringName(talent_id)
	)
	_suite.assert_true(
		not talent_definition.is_empty(),
		"%s resolves representative talent definition %s" % [label, talent_id]
	)
	if talent_definition.is_empty():
		return {}
	var player: Node = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	await get_tree().process_frame
	var configured: bool = player.configure_loadout({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": str(character_id),
		"character_profile": character_profile,
		"character_talents": [talent_id],
		"character_talent_definitions": [talent_definition],
		"weapon_id": str(weapon_id),
		"weapon_profile": _registry.call(
			"resolve_weapon_runtime_profile", weapon_id, &"LAUNCH"
		),
		"enabled_time_skills": time_pair.duplicate(true),
		"difficulty": "normal",
		"seed": seed_value,
	})
	_suite.assert_true(configured, "%s configures with representative talent %s" % [label, talent_id])
	if not configured:
		await _free_player(player)
		return {}
	_suite.assert_equal(
		player.loadout_runtime.character_talent_ids(),
		[StringName(talent_id)],
		"%s installs its content-backed talent identity" % label
	)

	var content_ids := CONTENT_BY_WEAPON[weapon_id] as Dictionary
	var before_effects: Dictionary = player.reward_effect_snapshot()
	var starter_result: Dictionary = player.apply_reward(
		_registry.call("get_content", content_ids["starter"])
	)
	_suite.assert_true(
		bool(starter_result.get("ok", false)),
		"%s executes representative starter %s: %s" % [
			label, str(content_ids["starter"]), str(starter_result),
		]
	)
	var payoff_result: Dictionary = player.apply_reward(
		_registry.call("get_content", content_ids["payoff"])
	)
	_suite.assert_true(
		bool(payoff_result.get("ok", false)),
		"%s executes representative payoff %s: %s" % [
			label, str(content_ids["payoff"]), str(payoff_result),
		]
	)
	var risk_result: Dictionary = player.apply_curse(
		_registry.call("get_content", GENERAL_RISK_ID)
	)
	_suite.assert_true(
		bool(risk_result.get("ok", false)),
		"%s executes bounded curse tradeoff %s: %s" % [
			label, str(GENERAL_RISK_ID), str(risk_result),
		]
	)
	_suite.assert_true(
		player.reward_effect_snapshot() != before_effects,
		"%s representative pool content mutates observable Player state" % label
	)

	var active_definition: Dictionary = _registry.call("get_content", content_ids["active"])
	var equipped: Dictionary = player.equip_active_item(active_definition)
	_suite.assert_true(
		bool(equipped.get("ok", false)),
		"%s equips representative active %s" % [label, str(content_ids["active"])]
	)
	var time_manager: Node = player.get_node("TimeManager")
	var health: Node = player.get_node("HealthComponent")
	time_manager.set("energy", float(time_manager.get("max_energy")))
	health.set("current_hp", float(health.get("max_hp")))
	player.set("_runtime_frame", 100 + case_index)
	var activation: Dictionary = player.activate_equipped_active_item({"is_boss_target": true})
	_suite.assert_true(
		bool(activation.get("ok", false)),
		"%s activates representative active %s: %s" % [
			label, str(content_ids["active"]), str(activation),
		]
	)
	_suite.assert_true(
		int(player.active_item_presentation_snapshot().get("cooldown_remaining_frames", 0)) > 0,
		"%s active execution starts an observable cooldown" % label
	)
	var result := {
		"configured": true,
		"active_content_id": str(activation.get("content_id", "")),
	}
	await _free_player(player)
	return result


func _free_player(player: Node) -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
