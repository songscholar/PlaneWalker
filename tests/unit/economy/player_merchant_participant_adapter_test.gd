extends Node

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const MerchantWeaponUpgradeAuthorityScript := preload(
	"res://scripts/economy/merchant_weapon_upgrade_authority.gd"
)
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const MERCHANTS_PATH := "res://data/content_packs/base/content/merchants.json"
const ECONOMY_PATH := "res://data/content_packs/base/content/economy_profiles.json"
const WEAPON_IDS: Array[StringName] = [
	&"sword",
	&"bow",
	&"gun",
	&"staff",
	&"gauntlets",
]

var _registry: RefCounted
var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report: RefCounted = _registry.call("load_packs", [
		{"path": "res://data/content_packs/base/pack.json", "required": true},
	], "0.4.0-dev", &"M1")
	_suite.assert_true(
		not report.call("has_blocking_errors"),
		"merchant participant fixture loads the authoritative Base Pack"
	)
	await _test_weapon_upgrade_contract_for_all_five_weapons()
	await _test_real_weapon_upgrade_authority_uses_player_protocol()
	await _test_nonlethal_health_cost_is_atomic_and_recoverable()
	await _test_nonlethal_health_cost_rejects_stale_tampered_and_lethal_requests()
	_suite.finish(get_tree())


func _test_weapon_upgrade_contract_for_all_five_weapons() -> void:
	for weapon_id: StringName in WEAPON_IDS:
		var player := await _spawn_player(weapon_id)
		_suite.assert_true(
			player.has_method("weapon_upgrade_snapshot"),
			"%s exposes the merchant upgrade snapshot" % str(weapon_id)
		)
		_suite.assert_true(
			player.has_method("can_restore_weapon_upgrade_snapshot"),
			"%s exposes upgrade snapshot validation" % str(weapon_id)
		)
		_suite.assert_true(
			player.has_method("restore_weapon_upgrade_snapshot"),
			"%s exposes upgrade compensation" % str(weapon_id)
		)
		if not (
			player.has_method("weapon_upgrade_snapshot")
			and player.has_method("can_restore_weapon_upgrade_snapshot")
			and player.has_method("restore_weapon_upgrade_snapshot")
		):
			await _free_player(player)
			continue

		var before: Dictionary = player.call("weapon_upgrade_snapshot")
		_suite.assert_equal(
			str(before.get("weapon_id", "")),
			str(weapon_id),
			"%s snapshot binds the equipped weapon" % str(weapon_id)
		)
		_suite.assert_true(
			bool(player.call("can_restore_weapon_upgrade_snapshot", before.duplicate(true))),
			"%s accepts its isolated upgrade snapshot" % str(weapon_id)
		)
		var leaked := before.duplicate(true)
		(leaked["modifiers"] as Dictionary)["weapon.damage"] = 9.0
		_suite.assert_equal(
			player.call("weapon_upgrade_snapshot"),
			before,
			"%s snapshot is deeply isolated" % str(weapon_id)
		)

		for level: int in range(1, 4):
			_suite.assert_true(
				bool(player.call("apply_weapon_capability_effect", &"weapon.damage", 1.10)),
				"%s merchant upgrade level %d applies through the two-argument protocol"
				% [str(weapon_id), level]
			)
			var upgraded: Dictionary = player.call("weapon_upgrade_snapshot")
			_suite.assert_close(
				float((upgraded.get("modifiers", {}) as Dictionary).get("weapon.damage", 0.0)),
				pow(1.10, level),
				"%s level %d maps to multiplicative weapon.damage" % [str(weapon_id), level]
			)

		_suite.assert_true(
			bool(player.call("restore_weapon_upgrade_snapshot", before.duplicate(true))),
			"%s merchant upgrade compensates" % str(weapon_id)
		)
		_suite.assert_equal(
			player.call("weapon_upgrade_snapshot"),
			before,
			"%s compensation restores the exact participant state" % str(weapon_id)
		)
		var forged := before.duplicate(true)
		forged["weapon_id"] = "bow" if weapon_id != &"bow" else "gun"
		_suite.assert_true(
			not bool(player.call("can_restore_weapon_upgrade_snapshot", forged)),
			"%s rejects a cross-weapon snapshot" % str(weapon_id)
		)
		_suite.assert_true(
			not bool(player.call("restore_weapon_upgrade_snapshot", forged)),
			"%s cross-weapon rejection is fail-closed" % str(weapon_id)
		)
		_suite.assert_equal(
			player.call("weapon_upgrade_snapshot"),
			before,
			"%s rejected restore is mutation-free" % str(weapon_id)
		)
		await _free_player(player)


func _test_real_weapon_upgrade_authority_uses_player_protocol() -> void:
	var player := await _spawn_player(&"sword")
	var merchants := _read_dictionary_array(MERCHANTS_PATH)
	var profiles := _read_dictionary_array(ECONOMY_PATH)
	var forgekeeper: Dictionary = {}
	for merchant: Dictionary in merchants:
		if str(merchant.get("id", "")) == "merchant_forgekeeper":
			forgekeeper = merchant.duplicate(true)
	var profile: Dictionary = profiles[0].duplicate(true) if profiles.size() == 1 else {}
	var authority = MerchantWeaponUpgradeAuthorityScript.new()
	var configured: Dictionary = authority.configure(forgekeeper, profile, 3, player)
	_suite.assert_true(
		bool(configured.get("ok", false)),
		"real weapon upgrade authority accepts the Player participant"
	)
	var before: Dictionary = player.call("weapon_upgrade_snapshot")
	var prepared: Dictionary = authority.prepare("real_player_upgrade")
	_suite.assert_true(bool(prepared.get("ok", false)), "real Player upgrade prepares")
	var committed: Dictionary = authority.commit(prepared.get("ticket", {}))
	_suite.assert_true(bool(committed.get("ok", false)), "real Player upgrade commits")
	var after: Dictionary = player.call("weapon_upgrade_snapshot")
	_suite.assert_close(
		float((after.get("modifiers", {}) as Dictionary).get("weapon.damage", 0.0)),
		1.10,
		"authority commit applies one sealed damage multiplier"
	)
	var rolled_back: Dictionary = authority.rollback(committed.get("receipt", {}))
	_suite.assert_true(bool(rolled_back.get("ok", false)), "real Player upgrade compensates")
	_suite.assert_equal(
		player.call("weapon_upgrade_snapshot"),
		before,
		"authority compensation restores the real Player exactly"
	)
	await _free_player(player)


func _test_nonlethal_health_cost_is_atomic_and_recoverable() -> void:
	var player := await _spawn_player(&"sword")
	for method: StringName in [
		&"prepare_nonlethal_health_cost",
		&"commit_nonlethal_health_cost",
		&"rollback_nonlethal_health_cost",
	]:
		_suite.assert_true(player.has_method(method), "Player exposes %s" % str(method))
	if not player.has_method("prepare_nonlethal_health_cost"):
		await _free_player(player)
		return

	var health: Node = player.get_node("HealthComponent")
	health.set("current_hp", 10.0)
	var before: Dictionary = player.call("reward_effect_snapshot")
	var prepared: Dictionary = player.call(
		"prepare_nonlethal_health_cost", "health_trade_atomic", 3, before.duplicate(true)
	)
	_suite.assert_true(bool(prepared.get("ok", false)), "nonlethal health cost prepares")
	_suite.assert_equal(
		player.call("reward_effect_snapshot"), before, "prepare has zero Player side effects"
	)
	var ticket := prepared.get("ticket", {}) as Dictionary
	_suite.assert_equal(ticket.get("transaction_id"), "health_trade_atomic", "ticket binds transaction")
	_suite.assert_equal(ticket.get("cost"), 3, "ticket binds integer health cost")
	_suite.assert_equal(ticket.get("before_snapshot"), before, "ticket freezes the complete Player snapshot")
	_suite.assert_close(
		float(((ticket.get("after_snapshot", {}) as Dictionary).get("health", {}) as Dictionary).get("current_hp", 0.0)),
		7.0,
		"ticket preserves at least one HP"
	)

	var committed: Dictionary = player.call(
		"commit_nonlethal_health_cost", ticket.duplicate(true)
	)
	_suite.assert_true(bool(committed.get("ok", false)), "nonlethal health cost commits")
	_suite.assert_close(float(health.get("current_hp")), 7.0, "commit deducts the exact health cost")
	_suite.assert_true(not bool(health.get("dead")), "health trade never marks a surviving Player dead")
	var receipt := committed.get("receipt", {}) as Dictionary
	var rolled_back: Dictionary = player.call(
		"rollback_nonlethal_health_cost", receipt.duplicate(true)
	)
	_suite.assert_true(bool(rolled_back.get("ok", false)), "committed health cost compensates")
	_suite.assert_equal(
		player.call("reward_effect_snapshot"), before, "health compensation restores exact Player state"
	)
	await _free_player(player)


func _test_nonlethal_health_cost_rejects_stale_tampered_and_lethal_requests() -> void:
	var player := await _spawn_player(&"sword")
	if not player.has_method("prepare_nonlethal_health_cost"):
		await _free_player(player)
		return
	var health: Node = player.get_node("HealthComponent")
	health.set("current_hp", 10.0)
	var before: Dictionary = player.call("reward_effect_snapshot")
	var lethal: Dictionary = player.call(
		"prepare_nonlethal_health_cost", "health_trade_lethal", 10, before.duplicate(true)
	)
	_suite.assert_true(not bool(lethal.get("ok", false)), "lethal health cost is rejected")
	_suite.assert_equal(lethal.get("code"), &"HEALTH_COST_LETHAL", "lethal rejection is typed")
	_suite.assert_equal(player.call("reward_effect_snapshot"), before, "lethal rejection is mutation-free")

	var prepared: Dictionary = player.call(
		"prepare_nonlethal_health_cost", "health_trade_tamper", 3, before.duplicate(true)
	)
	var ticket := (prepared.get("ticket", {}) as Dictionary).duplicate(true)
	var forged := ticket.duplicate(true)
	forged["cost"] = 4
	var forged_commit: Dictionary = player.call("commit_nonlethal_health_cost", forged)
	_suite.assert_true(not bool(forged_commit.get("ok", false)), "tampered health ticket is rejected")
	_suite.assert_equal(player.call("reward_effect_snapshot"), before, "tampered ticket is mutation-free")

	health.set("current_hp", 9.0)
	var stale_commit: Dictionary = player.call(
		"commit_nonlethal_health_cost", ticket.duplicate(true)
	)
	_suite.assert_true(not bool(stale_commit.get("ok", false)), "stale health ticket is rejected")
	_suite.assert_equal(stale_commit.get("code"), &"HEALTH_COST_STALE", "stale rejection is typed")
	health.set("current_hp", 10.0)
	_suite.assert_true(
		bool((player.call("rollback_nonlethal_health_cost", ticket.duplicate(true)) as Dictionary).get("ok", false)),
		"pending health ticket can be cancelled without mutation"
	)
	_suite.assert_equal(player.call("reward_effect_snapshot"), before, "pending cancellation preserves state")
	await _free_player(player)


func _spawn_player(weapon_id: StringName) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var character_profile: Dictionary = _registry.call(
		"resolve_character_runtime_profile", &"wanderer", &"LAUNCH"
	)
	var weapon_profile: Dictionary = _registry.call(
		"resolve_weapon_runtime_profile", weapon_id, &"LAUNCH"
	)
	_suite.assert_true(
		player.configure_loadout({
			"schema_version": 1,
			"milestone": "LAUNCH",
			"character_id": "wanderer",
			"character_profile": character_profile,
			"character_talents": [],
			"weapon_id": str(weapon_id),
			"weapon_profile": weapon_profile,
			"enabled_time_skills": [&"stop", &"rewind"],
			"difficulty": "normal",
			"seed": 20261002,
		}),
		"merchant participant fixture equips %s" % str(weapon_id)
	)
	return player


func _free_player(player: Node) -> void:
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


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
