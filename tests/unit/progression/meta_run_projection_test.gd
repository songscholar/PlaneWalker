extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_profile_fixtures.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const State := preload("res://scripts/progression/meta_profile_state.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")


func _ready() -> void:
	var suite = Suite.new()
	var catalog = Catalog.new()
	suite.assert_true(catalog.configure(Fixtures.meta_entries()).ok, "all authored meta definitions configure")
	var state = State.new()
	suite.assert_true(state.configure(catalog), "fresh profile configures")
	var profile: Dictionary = state.snapshot()
	var empty: Dictionary = MetaProjection.from_profile(profile, catalog)
	suite.assert_true(empty.ok, "fresh profile produces an explicit no-benefit projection")
	suite.assert_close(empty.context.projection.stat_bonuses.max_hp, 0.0, "fresh HP has no hidden buff")
	profile.chronos_shards = 10000
	profile.existential_imprints = 100
	suite.assert_true(state.restore_snapshot(profile), "earned fixture currencies restore")
	var pending: Array = catalog.ids()
	for _pass: int in range(42):
		for id: String in pending.duplicate():
			var prepared: Dictionary = state.prepare_command({"command_id": "unlock-%s" % id, "kind": "meta_unlock", "node_id": id}, state.snapshot().revision)
			if prepared.ok:
				suite.assert_true(state.commit_candidate(prepared.context.ticket).ok, "legal Meta purchase commits")
				pending.erase(id)
	suite.assert_true(pending.is_empty(), "every legacy Meta node is reachable without invalid prerequisites")
	profile = state.snapshot()
	for weapon: String in catalog.WEAPON_IDS:
		profile.forge_state[weapon].level = 5
	suite.assert_true(state.restore_snapshot(profile), "maximum legal forge levels restore")
	var result: Dictionary = MetaProjection.from_profile(state.snapshot(), catalog)
	suite.assert_true(result.ok, "maximum legal permanent projection derives")
	var projected: Dictionary = result.context.projection
	suite.assert_close(projected.stat_bonuses.max_hp, 0.05, "Meta HP capped at five percent")
	suite.assert_close(projected.stat_bonuses.attack, 0.03, "Meta attack capped at three percent")
	suite.assert_close(projected.stat_bonuses.attack_speed, 0.02, "Meta attack speed is two percent")
	suite.assert_close(projected.direct_combat_budget, 0.14, "all authored direct Meta benefits use fourteen percent")
	suite.assert_close(projected.forge_attack_bonuses.sword, 0.05, "forge attack is five percent")
	suite.assert_close(projected.soul_retention, 0.70, "retention uses the greatest unlocked authored tier")
	suite.assert_true(MetaProjection.validate(projected, catalog), "derived projection validates against authoritative content")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(projected))
	suite.assert_true(MetaProjection.validate(decoded, catalog), "physical JSON projection validates")
	suite.assert_true(MetaProjection.validate_combined(projected, {"max_hp": 0.20, "attack": 0.15, "defense": 0.15, "speed": 0.08}, "sword", catalog), "canonical maximum character/forge/Meta combination stays within thirty percent")
	suite.assert_true(not MetaProjection.validate_combined(projected, {"attack": 0.30}, "sword", catalog), "inflated character projection refuses rather than clamps")
	suite.assert_true(not MetaProjection.validate(projected), "a projection requires its authoritative content catalog")
	var corrupted := projected.duplicate(true)
	corrupted.stat_bonuses.max_hp = 0.50
	corrupted.projection_digest = MetaProjection.digest(corrupted)
	suite.assert_true(not MetaProjection.validate(corrupted, catalog), "rehashed excessive benefits still reject")
	corrupted = projected.duplicate(true)
	corrupted.stat_bonuses.attack = 0.01
	corrupted.projection_digest = MetaProjection.digest(corrupted)
	suite.assert_true(not MetaProjection.validate(corrupted, catalog), "rehashed understated benefits cannot contradict unlocked content")
	var frozen := projected.duplicate(true)
	profile = state.snapshot()
	profile.forge_state.sword.level = 0
	suite.assert_true(state.restore_snapshot(profile), "later profile changes remain possible")
	suite.assert_equal(projected, frozen, "run-start projection cannot alias later profile changes")
	suite.finish(get_tree())
