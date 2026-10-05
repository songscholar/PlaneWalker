extends Node

const Suite := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	var suite := Suite.new()
	var path := "res://scripts/modes/daily_reward_state.gd"
	suite.assert_true(ResourceLoader.exists(path), "daily rewards must own actual durable tokens gold and streak entitlements")
	if not ResourceLoader.exists(path):
		suite.finish(get_tree())
		return
	var reward: Script = load(path)
	var state: Dictionary = reward.empty()
	for day: int in range(30):
		state = reward.award(state, day, "VICTORY", 0)
		state = reward.award(state, day, "VICTORY", 0)
	suite.assert_true(reward.valid(state), "thirty-day reward wallet is closed and bounded")
	suite.assert_equal(state.tokens, 30, "repeat attempts cannot award a second daily token")
	suite.assert_equal(state.gold, 1500, "first daily native victory awards exactly fifty separate mode gold")
	suite.assert_equal(state.participation.streak, 30, "participation streak spans thirty distinct consecutive dates")
	suite.assert_equal(state.victory.streak, 30, "victory streak spans actual successful dates")
	for id: String in ["daily_participation_frame", "daily_walker_frame", "eternal_traveler"]:
		suite.assert_true(state.entitlements.has(id), "native streak owns permanent entitlement " + id)
	suite.assert_equal(state.perfect_day, 29, "damage-free daily title has its actual date")
	var exchange: Dictionary = reward.purchase(state, "daily_weapon_skin")
	suite.assert_true(exchange.ok and exchange.state.tokens == 25 and exchange.state.owned_ids.has("daily_weapon_skin"), "five-token exchange commits exact ownership and price")
	suite.assert_true(not reward.purchase(exchange.state, "daily_weapon_skin").ok, "repeat purchase refuses before another spend")
	var colored: Dictionary = reward.purchase(exchange.state, "daily_character_color")
	var eternal: Dictionary = reward.purchase(colored.state, "daily_archive_decoration")
	suite.assert_true(colored.ok and colored.state.tokens == 15 and not eternal.ok, "ten and twenty-token entries enforce actual balance")
	state = reward.award(exchange.state, 32, "DEFEAT", 1)
	suite.assert_equal(state.participation.streak, 1, "missed dates reset current participation streak")
	suite.assert_equal(state.victory.streak, 30, "defeat cannot create a new victory credit")
	state = reward.award(state, 33, "VICTORY", 1)
	suite.assert_equal(state.victory.streak, 1, "next victorious date resets an interrupted victory streak")
	suite.assert_equal(state.perfect_day, 29, "damage followed by recovery cannot manufacture a flawless title")
	var malformed := state.duplicate(true)
	malformed.tokens += 1
	suite.assert_true(not reward.valid(malformed), "forged token totals fail accounting validation")
	malformed = state.duplicate(true)
	malformed.entitlements.append("foreign_reward")
	suite.assert_true(not reward.valid(malformed), "unknown permanent entitlements refuse")
	suite.finish(get_tree())
