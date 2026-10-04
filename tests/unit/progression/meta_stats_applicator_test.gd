extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const StatsResource := preload("res://scripts/core/stats.gd")
const Loadout := preload("res://scripts/player/player_loadout_runtime.gd")
const IMPLEMENTATION := "res://scripts/progression/meta_stats_applicator.gd"
const CHARACTER_CONTENT := "res://data/content_packs/base/content/character_runtime_profiles.json"

var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	suite.assert_true(ResourceLoader.exists(IMPLEMENTATION), "pure MetaStatsApplicator exists")
	if ResourceLoader.exists(IMPLEMENTATION):
		var implementation := load(IMPLEMENTATION) as Script
		_test_real_loadout_matrix(implementation)
		_test_character_layer(implementation)
		_test_refusals_and_detachment(implementation)
	suite.finish(get_tree())


func _test_real_loadout_matrix(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var projections := _projections(catalog)
	var time_ids := ["accelerate", "rewind", "rift", "stop"]
	var count := 0
	for definition: Dictionary in _launch_profiles():
		for weapon_id: String in ["bow", "gauntlets", "gun", "staff", "sword"]:
			for first: int in range(4):
				for second: int in range(first + 1, 4):
					var loadout = Loadout.new()
					suite.assert_true(loadout.configure({"milestone": "LAUNCH", "character_id": definition.character_id, "character_profile": definition,
						"weapon_id": weapon_id, "enabled_time_skills": [time_ids[first], time_ids[second]], "character_talents": []}), "actual loadout accepts each canonical character/weapon/time pair")
					loadout.free()
					for tier: int in range(projections.size()):
						var result: Dictionary = implementation.prepare(definition, {}, weapon_id, projections[tier], catalog)
						suite.assert_true(result.ok, "fresh and complete Meta prepare each canonical loadout")
						if not result.ok:
							continue
						var actual: Dictionary = result.context.stats
						var native = StatsResource.new()
						suite.assert_true(native.apply_profile(actual), "permanent totals are compatible with actual Stats Resource")
						var expected: Dictionary = definition.base_stats.duplicate(true)
						if tier == 1:
							expected.max_hp *= 1.05
							expected.attack *= 1.03 * 1.05
							expected.attack_speed *= 1.02
						for stat: String in StatsResource.PROFILE_FIELDS:
							suite.assert_close(actual[stat], expected[stat], "authored permanent calculation preserves each base stat: " + stat)
						suite.assert_close(result.context.entrance_healing, 0.02 if tier == 1 else 0.0, "entrance healing is a policy ratio")
						suite.assert_close(result.context.void_reduction, 0.02 if tier == 1 else 0.0, "void mitigation is a policy ratio")
					count += 1
	suite.assert_equal(count, 150, "five real characters by five weapons by six time pairs are exercised at two permanent tiers")


func _test_character_layer(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var definition := _character("time_guardian")
	var projection: Dictionary = _projections(catalog)[1]
	var bonuses := {"max_hp": 0.20, "attack": 0.15, "defense": 0.15, "speed": 0.08}
	var result: Dictionary = implementation.prepare(definition, bonuses, "sword", projection, catalog)
	suite.assert_true(result.ok, "canonical maximum character and permanent layers stay in the combined budget")
	if not result.ok:
		return
	var actual: Dictionary = result.context.stats
	suite.assert_close(actual.max_hp, 240.0 * 1.20 * 1.05, "character HP and Meta multiply exactly once")
	suite.assert_close(actual.attack, 27.0 * 1.15 * 1.03 * 1.05, "character attack, Meta and selected weapon forge multiply exactly once")
	suite.assert_close(actual.defense, 10.0 * 1.15, "percentage defense multiplies nonzero character base")
	suite.assert_close(actual.move_speed, 190.0 * 1.08, "permanent speed maps to Stats move_speed")
	suite.assert_close(actual.attack_speed, 0.9 * 1.02, "Meta attack speed preserves real character rate")
	suite.assert_close(actual.time_energy_max, 120.0, "permanent system adds no unearned time capacity")
	var wanderer: Dictionary = implementation.prepare(_character("wanderer"), {}, "sword", projection, catalog)
	suite.assert_close(wanderer.context.stats.max_hp, 210.0, "run talent HP is left to its existing one-time reward handler")
	var profile := Fixtures.profile(catalog)
	profile.forge_state.sword.level = 5
	var distinct: Dictionary = MetaProjection.from_profile(profile, catalog).context.projection
	var bow: Dictionary = implementation.prepare(definition, {}, "bow", distinct, catalog)
	var sword: Dictionary = implementation.prepare(definition, {}, "sword", distinct, catalog)
	suite.assert_close(bow.context.stats.attack, 27.0 * 1.03, "unforged selected bow gains no other weapon's forge benefit")
	suite.assert_close(sword.context.stats.attack, 27.0 * 1.03 * 1.05, "only the selected forged weapon gains its bonus")


func _test_refusals_and_detachment(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var definition := _character("wanderer")
	var projection: Dictionary = _projections(catalog)[1]
	var before := definition.duplicate(true)
	var projection_before := projection.duplicate(true)
	var first: Dictionary = implementation.prepare(definition, {}, "sword", projection, catalog)
	suite.assert_equal(implementation.prepare(definition, {}, "sword", projection, catalog), first, "repeat preparation is deterministic and idempotent")
	suite.assert_equal(definition, before, "calculation never modifies authoritative character source")
	suite.assert_equal(projection, projection_before, "calculation never modifies frozen launch projection")
	first.context.stats.attack = 99999.0
	suite.assert_close(implementation.prepare(definition, {}, "sword", projection, catalog).context.stats.attack, 30.0 * 1.03 * 1.05, "returned totals are detached from future calculation")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(projection))
	suite.assert_equal(implementation.prepare(definition, {}, "sword", decoded, catalog), implementation.prepare(definition, {}, "sword", projection, catalog), "actual JSON float normalization preserves derived totals")
	suite.assert_true(not implementation.prepare(definition, {}, "sword", projection, null).ok, "catalog is required to authenticate projection")
	suite.assert_true(not implementation.prepare(definition, {}, "dagger", projection, catalog).ok, "unknown weapon refuses without a fallback")
	suite.assert_true(not implementation.prepare({}, {}, "sword", projection, catalog).ok, "empty character authority refuses")
	for bonuses: Dictionary in [{"attack": 0.16}, {"max_hp": true}, {"speed": -0.01}, {"attack": NAN}, {"move_speed": 0.01}, {"attack_speed": 0.01}]:
		suite.assert_true(not implementation.prepare(definition, bonuses, "sword", projection, catalog).ok, "invalid or inflated character permanent layer refuses")
	for mutation: String in ["overbudget", "rehash", "catalog", "unknown", "forge"]:
		var corrupt := projection.duplicate(true)
		match mutation:
			"overbudget": corrupt.stat_bonuses.attack = 0.50
			"rehash": corrupt.stat_bonuses.attack = 0.01
			"catalog": corrupt.catalog_fingerprint = "0".repeat(64)
			"unknown": corrupt.unknown_stat = 0.01
			"forge": corrupt.forge_attack_bonuses.sword = 0.06
		corrupt["projection_digest"] = MetaProjection.digest(corrupt)
		suite.assert_true(not implementation.prepare(definition, {}, "sword", corrupt, catalog).ok, "rehashed contradiction refuses: " + mutation)
	for mutation: String in ["bool", "fraction", "missing", "unknown"]:
		var corrupt := definition.duplicate(true)
		match mutation:
			"bool": corrupt.base_stats.attack = true
			"fraction": corrupt.base_stats.crit_chance = 1.5
			"missing": corrupt.base_stats.erase("attack")
			"unknown": corrupt.base_stats.unknown_stat = 100
		suite.assert_true(not implementation.prepare(corrupt, {}, "sword", projection, catalog).ok, "malformed real character structure refuses: " + mutation)


func _projections(catalog: RefCounted) -> Array:
	var fresh = Profile.new()
	fresh.configure(catalog)
	var maximum := Fixtures.profile(catalog)
	for weapon_id: String in ["bow", "gauntlets", "gun", "staff", "sword"]:
		maximum.forge_state[weapon_id].level = 5
	return [MetaProjection.from_profile(fresh.snapshot(), catalog).context.projection, MetaProjection.from_profile(maximum, catalog).context.projection]


func _launch_profiles() -> Array:
	var result: Array = []
	for value: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(CHARACTER_CONTENT)):
		if value.availability.has("LAUNCH"):
			result.append(value)
	return result


func _character(character_id: String) -> Dictionary:
	for definition: Dictionary in _launch_profiles():
		if definition.character_id == character_id:
			return definition
	return {}
