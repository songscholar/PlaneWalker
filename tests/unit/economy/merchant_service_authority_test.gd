extends Node

const MerchantServiceAuthorityScript := preload(
	"res://scripts/economy/merchant_service_authority.gd"
)
const PlayerRewardEffectRuntimeScript := preload(
	"res://scripts/items/player_reward_effect_runtime.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const MERCHANTS_PATH := "res://data/content_packs/base/content/merchants.json"
const ECONOMY_PATH := "res://data/content_packs/base/content/economy_profiles.json"


class FakePlayer extends RefCounted:
	var state := {
		"schema_version": 1,
		"health": {"current_hp": 40.0, "max_hp": 100.0},
	}

	func reward_effect_snapshot() -> Dictionary:
		return state.duplicate(true)

	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		if not value.has("health") or not value["health"] is Dictionary:
			return false
		state = value.duplicate(true)
		return true

	func reward_effect_apply_operation(operation: Dictionary) -> Dictionary:
		if (
			str(operation.get("effect_id", "")) != "heal"
			or str(operation.get("runtime_domain", "")) != "trigger"
			or typeof(operation.get("value")) not in [TYPE_INT, TYPE_FLOAT]
		):
			return {"ok": false, "code": &"OPERATION_REJECTED"}
		var health := state["health"] as Dictionary
		health["current_hp"] = minf(
			float(health["max_hp"]),
			float(health["current_hp"]) + float(operation["value"])
		)
		return {"ok": true, "code": &"OK"}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_prepare_uses_authoritative_hp_and_price(suite)
	_test_full_hp_and_unoffered_service_fail_closed(suite)
	_test_accepted_cost_is_authoritative(suite)
	_test_commit_and_rollback_are_atomic(suite)
	_test_snapshot_restore_preserves_duplicate_transactions(suite)
	suite.finish(get_tree())


func _test_prepare_uses_authoritative_hp_and_price(suite) -> void:
	var fixture := _fixture("merchant_wayfarer", 2)
	var before: Dictionary = fixture.player.reward_effect_snapshot()
	var prepared: Dictionary = fixture.authority.prepare_service("heal_prepare", &"heal")
	suite.assert_true(bool(prepared.get("ok", false)), "heal prepares")
	var ticket := prepared.get("ticket", {}) as Dictionary
	suite.assert_equal(ticket.get("price"), 46, "floor multiplier determines heal price")
	suite.assert_equal(ticket.get("cost_kind"), "gold", "heal exposes a typed gold cost")
	suite.assert_close(float(ticket.get("heal_amount", -1.0)), 30.0, "heal derives thirty percent maximum HP")
	suite.assert_equal(fixture.player.reward_effect_snapshot(), before, "prepare has zero player side effects")


func _test_full_hp_and_unoffered_service_fail_closed(suite) -> void:
	var full := _fixture("merchant_wayfarer", 1)
	full.player.state["health"]["current_hp"] = 100.0
	var full_result: Dictionary = full.authority.prepare_service("heal_full", &"heal")
	suite.assert_equal(full_result.get("code"), &"HEAL_NOT_NEEDED", "full HP cannot create a chargeable heal")

	var unoffered := _fixture("merchant_chronomancer", 2)
	var unoffered_result: Dictionary = unoffered.authority.prepare_service("heal_unoffered", &"heal")
	suite.assert_equal(unoffered_result.get("code"), &"SERVICE_NOT_OFFERED", "merchant service list is authoritative")


func _test_accepted_cost_is_authoritative(suite) -> void:
	var merchant := _merchant("merchant_wayfarer")
	merchant["accepted_costs"] = ["reward"]
	var player := FakePlayer.new()
	var authority = MerchantServiceAuthorityScript.new()
	var configured: Dictionary = authority.configure(
		merchant,
		_profile(),
		1,
		player,
		PlayerRewardEffectRuntimeScript.new()
	)
	suite.assert_true(bool(configured.get("ok", false)), "merchant without gold remains structurally valid")
	var result: Dictionary = authority.prepare_service("heal_no_gold", &"heal")
	suite.assert_equal(result.get("code"), &"COST_NOT_ACCEPTED", "heal requires merchant gold acceptance")


func _test_commit_and_rollback_are_atomic(suite) -> void:
	var fixture := _fixture("merchant_wayfarer", 1)
	var before: Dictionary = fixture.player.reward_effect_snapshot()
	var prepared: Dictionary = fixture.authority.prepare_service("heal_commit", &"heal")
	var committed: Dictionary = fixture.authority.commit_service(prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "prepared heal commits")
	suite.assert_close(float(fixture.player.state["health"]["current_hp"]), 70.0, "commit applies the frozen heal once")
	var duplicate: Dictionary = fixture.authority.prepare_service("heal_commit", &"heal")
	suite.assert_equal(duplicate.get("code"), &"DUPLICATE_TRANSACTION", "committed transaction cannot replay")
	var rolled_back: Dictionary = fixture.authority.rollback_service(committed.get("receipt", {}))
	suite.assert_true(bool(rolled_back.get("ok", false)), "committed heal rolls back")
	suite.assert_equal(fixture.player.reward_effect_snapshot(), before, "rollback restores exact player state")
	var retried: Dictionary = fixture.authority.prepare_service("heal_commit", &"heal")
	suite.assert_true(bool(retried.get("ok", false)), "compensated transaction id can be retried")


func _test_snapshot_restore_preserves_duplicate_transactions(suite) -> void:
	var fixture := _fixture("merchant_wayfarer", 1)
	var prepared: Dictionary = fixture.authority.prepare_service("heal_restore", &"heal")
	var committed: Dictionary = fixture.authority.commit_service(prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "restore fixture commits")
	var saved: Dictionary = fixture.authority.snapshot()

	var restored = MerchantServiceAuthorityScript.new()
	var configured: Dictionary = restored.configure(
		_merchant("merchant_wayfarer"),
		_profile(),
		1,
		fixture.player,
		PlayerRewardEffectRuntimeScript.new()
	)
	suite.assert_true(bool(configured.get("ok", false)), "restored authority configures")
	suite.assert_true(restored.can_restore_snapshot(saved), "saved authority snapshot validates")
	suite.assert_true(restored.restore_snapshot(saved), "saved authority snapshot restores")
	var duplicate: Dictionary = restored.prepare_service("heal_restore", &"heal")
	suite.assert_equal(duplicate.get("code"), &"DUPLICATE_TRANSACTION", "restored transaction id remains consumed")


func _fixture(merchant_id: String, floor_number: int) -> Dictionary:
	var player := FakePlayer.new()
	var authority = MerchantServiceAuthorityScript.new()
	var configured: Dictionary = authority.configure(
		_merchant(merchant_id),
		_profile(),
		floor_number,
		player,
		PlayerRewardEffectRuntimeScript.new()
	)
	if not bool(configured.get("ok", false)):
		push_error("Merchant service fixture failed: %s" % str(configured))
	return {"authority": authority, "player": player}


func _merchant(merchant_id: String) -> Dictionary:
	for merchant: Dictionary in _read_dictionary_array(MERCHANTS_PATH):
		if str(merchant.get("id", "")) == merchant_id:
			return merchant.duplicate(true)
	return {}


func _profile() -> Dictionary:
	var profiles := _read_dictionary_array(ECONOMY_PATH)
	return profiles[0].duplicate(true) if profiles.size() == 1 else {}


func _read_dictionary_array(path: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var rows: Array[Dictionary] = []
	if parsed is Array:
		for value: Variant in parsed as Array:
			if value is Dictionary:
				rows.append((value as Dictionary).duplicate(true))
	return rows
