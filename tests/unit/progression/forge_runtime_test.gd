extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/progression/forge_runtime.gd") as Script
	suite.assert_true(implementation != null, "authoritative ForgeRuntime exists")
	if implementation != null:
		_test_upgrades(implementation)
		_test_preferences(implementation)
		_test_rejections(implementation)
	suite.finish(get_tree())


func _test_upgrades(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime: RefCounted = implementation.new()
	var configured: Dictionary = runtime.configure(Fixtures.forge_entries(), catalog)
	suite.assert_true(configured.ok, "all authoritative forge definitions configure: " + str(configured))
	if not configured.ok:
		return
	for weapon_id: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		var profile := Fixtures.profile(catalog)
		for level: int in range(1, 6):
			var before := profile.duplicate(true)
			var command := {"command_id": "forge-" + weapon_id + "-" + str(level), "kind": "forge_upgrade", "weapon_id": weapon_id}
			var result: Dictionary = runtime.prepare_command(profile, command, profile.revision)
			suite.assert_true(result.ok, "canonical forge level prepares: " + weapon_id + str(level))
			if not result.ok:
				continue
			suite.assert_equal(profile, before, "forge preparation cannot mutate input or spend early")
			profile = result.context.candidate
			suite.assert_equal(before.chronos_shards - profile.chronos_shards, [5, 10, 20, 35, 50][level - 1], "exact authored level cost")
			suite.assert_equal(profile.forge_state[weapon_id].level, level, "reliable upgrade increases one level")
			suite.assert_true(not runtime.prepare_command(profile, command, profile.revision).ok, "same forge command never spends twice")
			suite.assert_true(not runtime.prepare_command(profile, {"command_id": "stale", "kind": "forge_upgrade", "weapon_id": weapon_id}, before.revision).ok, "stale revision refuses")
		suite.assert_equal(runtime.weapon_projection(profile, weapon_id).attack_bonus, 0.05, "forge has exactly five percent maximum attack")
		suite.assert_true(not runtime.prepare_command(profile, {"command_id": "sixth", "kind": "forge_upgrade", "weapon_id": weapon_id}, profile.revision).ok, "sixth level refuses")
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(profile))
		suite.assert_equal(runtime.weapon_projection(parsed, weapon_id), runtime.weapon_projection(profile, weapon_id), "physical JSON preserves forge projection")


func _test_preferences(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(Fixtures.forge_entries(), catalog).ok, "preference catalog configures")
	var profile := Fixtures.profile(catalog)
	var result: Dictionary = runtime.prepare_command(profile, {"command_id": "unlock-existence", "kind": "enchant_preference", "weapon_id": "sword", "enchantment_ids": ["EN-14"]}, 0)
	suite.assert_true(result.ok, "legendary preference acquisition prepares")
	if not result.ok:
		return
	profile = result.context.candidate
	suite.assert_equal(profile.existential_imprints, 15, "five imprint unlock spends once")
	suite.assert_equal(profile.chronos_shards, 950, "authored fifty shards spend once")
	suite.assert_true(profile.completed_command_ids.has("forge-enchant-unlock:EN-14"), "durable internal unlock source survives unequip")
	suite.assert_equal(runtime.weapon_projection(profile, "sword").attack_bonus, 0.0, "preference adds no permanent proc or attack")
	result = runtime.prepare_command(profile, {"command_id": "unequip", "kind": "enchant_preference", "weapon_id": "sword", "enchantment_ids": []}, profile.revision)
	suite.assert_true(result.ok, "preferences may be cleared without losing acquisition")
	profile = result.context.candidate
	var restored: Dictionary = JSON.parse_string(JSON.stringify(profile))
	result = runtime.prepare_command(restored, {"command_id": "reequip", "kind": "enchant_preference", "weapon_id": "bow", "enchantment_ids": ["EN-14"]}, restored.revision)
	suite.assert_true(result.ok, "owned preference recalls on another weapon after JSON reload")
	if result.ok:
		suite.assert_equal(result.context.candidate.existential_imprints, 15, "re-equip cannot charge unlock twice")
		suite.assert_equal(result.context.candidate.chronos_shards, 950, "re-equip is free after first acquisition")
	for ids: Array in [["EN-01", "EN-02"], ["EN-04", "EN-05"], ["EN-14", "EN-14"], ["EN-99"]]:
		suite.assert_true(not runtime.prepare_command(profile, {"command_id": "bad-preference", "kind": "enchant_preference", "weapon_id": "sword", "enchantment_ids": ids}, profile.revision).ok, "closed preference or mutually-exclusive group refuses")
	var before := profile.duplicate(true)
	result = runtime.prepare_command(profile, {"command_id": "temper", "kind": "void_temper", "weapon_id": "sword", "payment_currency": "existential_imprints"}, profile.revision)
	suite.assert_true(result.ok, "authored imprint temper prepares")
	if result.ok:
		suite.assert_equal(profile, before, "temper preparation is isolated")
		profile = result.context.candidate
		suite.assert_equal(profile.existential_imprints, before.existential_imprints - 3, "imprint temper exact cost")
		suite.assert_equal(runtime.weapon_projection(profile, "sword").attack_bonus, 0.0, "tempering never adds combat multiplier")
		suite.assert_true(not runtime.prepare_command(profile, {"command_id": "temper-again", "kind": "void_temper", "weapon_id": "sword", "payment_currency": "chronos_shards"}, profile.revision).ok, "temper cannot be acquired twice")


func _test_rejections(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(Fixtures.forge_entries(), catalog).ok, "refusal runtime configures")
	var profile := Fixtures.profile(catalog, false)
	var command := {"command_id": "missing-node", "kind": "forge_upgrade", "weapon_id": "sword"}
	suite.assert_true(not runtime.prepare_command({}, command, 0).ok, "empty profile is a refusal, never an implicit fresh authority")
	suite.assert_equal(runtime.weapon_projection({}, "sword"), {}, "empty profile cannot project forging")
	suite.assert_true(not runtime.prepare_command(profile, command, profile.revision).ok, "locked forging refuses")
	profile = Fixtures.profile(catalog)
	profile.chronos_shards = 4
	var before := profile.duplicate(true)
	suite.assert_true(not runtime.prepare_command(profile, command, profile.revision).ok, "insufficient shards refuse")
	suite.assert_equal(profile, before, "refusal preserves entire input")
	command.command_id = "forge-enchant-unlock:EN-14"
	suite.assert_true(not runtime.prepare_command(profile, command, profile.revision).ok, "user cannot forge internal unlock source")
	var definitions := Fixtures.forge_entries()
	definitions[0].levels[0].attack_bonus = 0.9
	suite.assert_true(not runtime.configure(definitions, catalog).ok, "over-budget content refuses configuration")
	suite.assert_equal(runtime.weapon_projection(Fixtures.profile(catalog), "sword"), {}, "invalid configuration clears old content")
