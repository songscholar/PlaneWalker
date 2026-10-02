extends Node

const MerchantWeaponUpgradeAuthorityScript := preload(
	"res://scripts/economy/merchant_weapon_upgrade_authority.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const MERCHANTS_PATH := "res://data/content_packs/base/content/merchants.json"
const ECONOMY_PATH := "res://data/content_packs/base/content/economy_profiles.json"
const WEAPON_IDS: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]


class FakePlayer extends RefCounted:
	var state: Dictionary
	var fail_after_apply: bool = false
	var apply_calls: int = 0

	func _init(weapon_id: String = "sword") -> void:
		state = {
			"weapon_id": weapon_id,
			"capabilities": {"weapon.damage": 1.0},
		}

	func weapon_upgrade_snapshot() -> Dictionary:
		return state.duplicate(true)

	func can_restore_weapon_upgrade_snapshot(value: Dictionary) -> bool:
		if value.size() != 2 or not value.has("weapon_id") or not value.has("capabilities"):
			return false
		if typeof(value["weapon_id"]) != TYPE_STRING or not WEAPON_IDS.has(str(value["weapon_id"])):
			return false
		if not value["capabilities"] is Dictionary:
			return false
		var damage: Variant = (value["capabilities"] as Dictionary).get("weapon.damage")
		return (
			typeof(damage) in [TYPE_INT, TYPE_FLOAT]
			and is_finite(float(damage))
			and float(damage) > 0.0
		)

	func restore_weapon_upgrade_snapshot(value: Dictionary) -> bool:
		if not can_restore_weapon_upgrade_snapshot(value):
			return false
		state = value.duplicate(true)
		return true

	func apply_weapon_capability_effect(capability: StringName, value: Variant) -> bool:
		apply_calls += 1
		if (
			capability != &"weapon.damage"
			or typeof(value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(value))
			or float(value) <= 0.0
		):
			return false
		var capabilities := state["capabilities"] as Dictionary
		capabilities["weapon.damage"] = float(capabilities["weapon.damage"]) * float(value)
		return not fail_after_apply


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_configure_and_prepare_freeze_authoritative_policy(suite)
	_test_all_five_weapons_upgrade_from_zero_to_cap(suite)
	_test_stale_weapon_and_duplicate_transactions_fail_closed(suite)
	_test_failed_commit_restores_exact_player_state(suite)
	_test_snapshot_restore_preserves_level_weapon_and_completed_ids(suite)
	_test_pending_and_committed_rollback_are_exact(suite)
	suite.finish(get_tree())


func _test_configure_and_prepare_freeze_authoritative_policy(suite) -> void:
	var fixture := _fixture("sword", 3)
	var before: Dictionary = fixture.player.weapon_upgrade_snapshot()
	var prepared: Dictionary = fixture.authority.prepare("upgrade_prepare")
	suite.assert_true(bool(prepared.get("ok", false)), "forgekeeper weapon upgrade prepares")
	var ticket := prepared.get("ticket", {}) as Dictionary
	suite.assert_equal(ticket.get("service_id"), "weapon_upgrade", "ticket freezes the typed service")
	suite.assert_equal(ticket.get("cost_kind"), "gold", "upgrade exposes its authoritative gold cost")
	suite.assert_equal(ticket.get("price"), 156, "floor three profile price is authoritative")
	suite.assert_equal(ticket.get("capability"), "weapon.damage", "upgrade capability is sealed")
	suite.assert_close(float(ticket.get("value", 0.0)), 1.10, "upgrade multiplier is sealed")
	suite.assert_equal(ticket.get("current_level"), 0, "first upgrade starts at level zero")
	suite.assert_equal(ticket.get("next_level"), 1, "first upgrade advances exactly one level")
	suite.assert_equal(fixture.player.weapon_upgrade_snapshot(), before, "prepare has zero player side effects")

	var missing_service = MerchantWeaponUpgradeAuthorityScript.new()
	var missing_result: Dictionary = missing_service.configure(
		_merchant("merchant_wayfarer"), _profile(), 3, FakePlayer.new()
	)
	suite.assert_equal(missing_result.get("code"), &"SERVICE_NOT_OFFERED", "configure requires weapon upgrade service")

	var no_gold_merchant := _merchant("merchant_forgekeeper")
	no_gold_merchant["accepted_costs"] = ["forge_essence"]
	var no_gold = MerchantWeaponUpgradeAuthorityScript.new()
	var no_gold_result: Dictionary = no_gold.configure(no_gold_merchant, _profile(), 3, FakePlayer.new())
	suite.assert_equal(no_gold_result.get("code"), &"COST_NOT_ACCEPTED", "configure requires authoritative gold acceptance")


func _test_all_five_weapons_upgrade_from_zero_to_cap(suite) -> void:
	for weapon_id: String in WEAPON_IDS:
		var fixture := _fixture(weapon_id, 3)
		for level: int in range(3):
			var transaction_id := "%s_level_%d" % [weapon_id, level + 1]
			var prepared: Dictionary = fixture.authority.prepare(transaction_id)
			suite.assert_true(bool(prepared.get("ok", false)), "%s level %d prepares" % [weapon_id, level + 1])
			var committed: Dictionary = fixture.authority.commit(prepared.get("ticket", {}))
			suite.assert_true(bool(committed.get("ok", false)), "%s level %d commits" % [weapon_id, level + 1])
			suite.assert_equal(fixture.authority.snapshot().get("level"), level + 1, "%s level increments once" % weapon_id)
		suite.assert_close(
			float((fixture.player.state["capabilities"] as Dictionary)["weapon.damage"]),
			pow(1.10, 3),
			"%s receives three multiplicative upgrades" % weapon_id
		)
		var capped: Dictionary = fixture.authority.prepare("%s_level_4" % weapon_id)
		suite.assert_equal(capped.get("code"), &"UPGRADE_CAP_REACHED", "%s cannot exceed level three" % weapon_id)
		suite.assert_equal(fixture.player.apply_calls, 3, "%s applies exactly three effects" % weapon_id)


func _test_stale_weapon_and_duplicate_transactions_fail_closed(suite) -> void:
	var fixture := _fixture("bow", 3)
	var prepared: Dictionary = fixture.authority.prepare("stale_weapon")
	fixture.player.state["weapon_id"] = "gun"
	var stale_commit: Dictionary = fixture.authority.commit(prepared.get("ticket", {}))
	suite.assert_equal(stale_commit.get("code"), &"WEAPON_STALE", "weapon swap invalidates a prepared ticket")
	suite.assert_equal(fixture.authority.snapshot().get("level"), 0, "stale commit does not advance level")
	suite.assert_equal(fixture.player.apply_calls, 0, "stale commit never invokes the player effect")
	fixture.player.state["weapon_id"] = "bow"
	suite.assert_true(bool(fixture.authority.rollback(prepared.get("ticket", {})).get("ok", false)), "stale pending ticket can be cancelled")

	var first: Dictionary = fixture.authority.prepare("duplicate_upgrade")
	var committed: Dictionary = fixture.authority.commit(first.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "duplicate fixture commits once")
	suite.assert_equal(fixture.authority.prepare("duplicate_upgrade").get("code"), &"DUPLICATE_TRANSACTION", "completed id cannot prepare twice")
	suite.assert_equal(fixture.authority.commit(first.get("ticket", {})).get("code"), &"DUPLICATE_TRANSACTION", "completed ticket cannot commit twice")


func _test_failed_commit_restores_exact_player_state(suite) -> void:
	var fixture := _fixture("staff", 4)
	var before_player: Dictionary = fixture.player.weapon_upgrade_snapshot()
	var before_authority: Dictionary = fixture.authority.snapshot()
	var prepared: Dictionary = fixture.authority.prepare("partial_failure")
	fixture.player.fail_after_apply = true
	var failed: Dictionary = fixture.authority.commit(prepared.get("ticket", {}))
	suite.assert_equal(failed.get("code"), &"PLAYER_APPLY_FAILED", "mutating false return fails closed")
	suite.assert_equal(fixture.player.weapon_upgrade_snapshot(), before_player, "failed commit restores exact player snapshot")
	suite.assert_equal(fixture.authority.snapshot(), before_authority, "failed commit preserves authority snapshot")


func _test_snapshot_restore_preserves_level_weapon_and_completed_ids(suite) -> void:
	var fixture := _fixture("gauntlets", 5)
	for transaction_id: String in ["restore_one", "restore_two"]:
		var prepared: Dictionary = fixture.authority.prepare(transaction_id)
		suite.assert_true(bool(fixture.authority.commit(prepared.get("ticket", {})).get("ok", false)), "%s commits" % transaction_id)
	var saved: Dictionary = fixture.authority.snapshot()

	var restored = MerchantWeaponUpgradeAuthorityScript.new()
	var configured: Dictionary = restored.configure(
		_merchant("merchant_forgekeeper"), _profile(), 5, fixture.player
	)
	suite.assert_true(bool(configured.get("ok", false)), "restore authority configures")
	suite.assert_true(restored.can_restore_snapshot(saved), "saved authority snapshot validates")
	suite.assert_true(restored.restore_snapshot(saved), "saved authority snapshot restores")
	suite.assert_equal(restored.snapshot(), saved, "restore round trips byte-identical state")
	suite.assert_equal(restored.prepare("restore_one").get("code"), &"DUPLICATE_TRANSACTION", "restored completed id remains consumed")

	var wrong_weapon_player := FakePlayer.new("sword")
	var wrong_weapon = MerchantWeaponUpgradeAuthorityScript.new()
	wrong_weapon.configure(_merchant("merchant_forgekeeper"), _profile(), 5, wrong_weapon_player)
	suite.assert_true(not wrong_weapon.can_restore_snapshot(saved), "snapshot cannot migrate levels across weapons")


func _test_pending_and_committed_rollback_are_exact(suite) -> void:
	var fixture := _fixture("gun", 3)
	var pending: Dictionary = fixture.authority.prepare("pending_rollback")
	suite.assert_true(bool(fixture.authority.rollback(pending.get("ticket", {})).get("ok", false)), "pending ticket rolls back")
	suite.assert_true(bool(fixture.authority.prepare("pending_rollback").get("ok", false)), "cancelled pending id can retry")

	var retry_ticket: Dictionary = fixture.authority.prepare("committed_rollback")
	var before_player: Dictionary = fixture.player.weapon_upgrade_snapshot()
	var before_authority: Dictionary = fixture.authority.snapshot()
	var committed: Dictionary = fixture.authority.commit(retry_ticket.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "rollback fixture commits")
	var rolled_back: Dictionary = fixture.authority.rollback(committed.get("receipt", {}))
	suite.assert_true(bool(rolled_back.get("ok", false)), "committed upgrade rolls back")
	suite.assert_equal(fixture.player.weapon_upgrade_snapshot(), before_player, "rollback restores exact player state")
	suite.assert_equal(fixture.authority.snapshot(), before_authority, "rollback restores exact authority state")
	suite.assert_true(bool(fixture.authority.prepare("committed_rollback").get("ok", false)), "compensated id can retry")


func _fixture(weapon_id: String, floor_number: int) -> Dictionary:
	var player := FakePlayer.new(weapon_id)
	var authority = MerchantWeaponUpgradeAuthorityScript.new()
	var configured: Dictionary = authority.configure(
		_merchant("merchant_forgekeeper"), _profile(), floor_number, player
	)
	if not bool(configured.get("ok", false)):
		push_error("Merchant weapon upgrade fixture failed: %s" % str(configured))
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
