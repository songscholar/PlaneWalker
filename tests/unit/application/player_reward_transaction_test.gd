extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Transaction := preload("res://scripts/application/player_reward_transaction.gd")


class Participant:
	extends RefCounted
	var value := 1
	var publication := false
	var ignore_restore := false

	func reward_effect_snapshot() -> Dictionary:
		return {"value": value}

	func restore_reward_effect_snapshot(snapshot: Dictionary) -> bool:
		if not ignore_restore:
			value = snapshot.value
		return true

	func reward_effect_begin_publication() -> bool:
		if publication:
			return false
		publication = true
		return true

	func reward_effect_publication_can_commit() -> bool:
		return publication

	func reward_effect_commit_publication() -> bool:
		publication = false
		return true

	func reward_effect_rollback_publication() -> bool:
		publication = false
		return true

	func character_talent_transaction_snapshot() -> Dictionary:
		return reward_effect_snapshot()

	func restore_character_talent_transaction_snapshot(snapshot: Dictionary) -> bool:
		return restore_reward_effect_snapshot(snapshot)

	func install_character_talent(_definition: Dictionary) -> bool:
		value += 1
		return true

	func full_player_replay_snapshot() -> Dictionary:
		return reward_effect_snapshot()

	func restore_full_player_replay_snapshot(snapshot: Dictionary) -> bool:
		return restore_reward_effect_snapshot(snapshot)

	func active_item_snapshot() -> Dictionary:
		return {"configured": false}

	func equip_active_item(_definition: Dictionary, _replace: bool) -> Dictionary:
		value += 1
		return {"ok": true}


class Effects:
	extends RefCounted

	func prepare(_definition: Dictionary, snapshot: Dictionary) -> Dictionary:
		return {"ok": true, "plan": {"before": snapshot.duplicate(true)}}

	func commit(_plan: Dictionary, participant: Object) -> Dictionary:
		participant.value += 1
		return {"ok": true, "receipt": {"committed": true}}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	for definition: Dictionary in [
		{"id": "fixture_reward", "category": "item"},
		{"id": "fixture_talent", "category": "talent"},
		{"id": "fixture_active", "item_mode": "active"},
	]:
		for ignore_restore: bool in [false, true]:
			var participant := Participant.new()
			var transaction = Transaction.new()
			suite.assert_true(transaction.configure(participant, Effects.new()), "reward participants configure")
			suite.assert_true(transaction.apply(definition), "reward provisionally changes the participant")
			suite.assert_equal(participant.value, 2, "reward changes actual participant state before compensation")
			participant.ignore_restore = ignore_restore
			suite.assert_equal(transaction.rollback(), not ignore_restore, "compensation verifies restored state even when the participant reports success")
			suite.assert_true(not participant.publication, "compensation always closes provisional publication")
			if not ignore_restore:
				suite.assert_equal(participant.value, 1, "successful compensation restores the original state")
	suite.finish(get_tree())
