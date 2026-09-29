extends Node

const PlayerArrowScript := preload("res://scripts/combat/player_arrow.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


class EnergyManager extends Node:
	var restored: float = 0.0


	func restore_energy(amount: float) -> void:
		restored += amount


class RewardOwner extends Node:
	var claims: Dictionary = {}


	func claim_weapon_action_reward(token: int, reward_kind: StringName) -> bool:
		if token <= 0 or reward_kind == &"":
			return false
		var key := "%d:%s" % [token, str(reward_kind)]
		if claims.has(key):
			return false
		claims[key] = true
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_profile_reward_is_claimed_once_per_action_token()
	_test_legacy_reward_remains_per_projectile()
	_suite.finish(get_tree())


func _test_profile_reward_is_claimed_once_per_action_token() -> void:
	var owner := RewardOwner.new()
	var energy := EnergyManager.new()
	energy.name = "TimeManager"
	owner.add_child(energy)
	add_child(owner)

	var first := _profile_arrow(owner, 17)
	var second := _profile_arrow(owner, 17)
	var next_action := _profile_arrow(owner, 18)
	first.call("_restore_time_energy")
	first.call("_restore_time_energy")
	second.call("_restore_time_energy")
	_suite.assert_close(
		energy.restored,
		6.0,
		"one action token restores full-charge energy at most once across projectile hits"
	)
	next_action.call("_restore_time_energy")
	_suite.assert_close(
		energy.restored,
		12.0,
		"a later action token may claim its own full-charge energy reward"
	)

	first.free()
	second.free()
	next_action.free()
	owner.free()


func _test_legacy_reward_remains_per_projectile() -> void:
	var owner := RewardOwner.new()
	var energy := EnergyManager.new()
	energy.name = "TimeManager"
	owner.add_child(energy)
	add_child(owner)

	var first := _legacy_arrow(owner)
	var second := _legacy_arrow(owner)
	first.call("_restore_time_energy")
	second.call("_restore_time_energy")
	_suite.assert_close(
		energy.restored,
		12.0,
		"legacy arrows without a token preserve the prior per-projectile reward behavior"
	)

	first.free()
	second.free()
	owner.free()


func _profile_arrow(owner: Node, token: int) -> Node:
	var arrow = PlayerArrowScript.new()
	arrow.full_charge = true
	arrow.time_energy_restore = 6.0
	arrow.owner_entity = owner
	arrow.action_token = token
	arrow.energy_reward_once_per_action = true
	return arrow


func _legacy_arrow(owner: Node) -> Node:
	var arrow = PlayerArrowScript.new()
	arrow.full_charge = true
	arrow.time_energy_restore = 6.0
	arrow.owner_entity = owner
	return arrow
