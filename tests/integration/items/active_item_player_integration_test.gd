extends Node

const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const StatsScript := preload("res://scripts/core/stats.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const TimeManagerScript := preload("res://scripts/time_system/time_manager.gd")

const ITEMS_PATH := "res://data/content_packs/base/content/items.json"

var _suite
var _active_by_id: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_load_active_definitions()
	_test_one_slot_requires_explicit_replacement()
	_test_energy_active_commits_cost_cooldown_and_payload_atomically()
	_test_health_active_spends_exact_nonlethal_cost()
	_test_failed_activation_preserves_player_and_runtime_state()
	_suite.finish(get_tree())


func _test_one_slot_requires_explicit_replacement() -> void:
	var fixture := _fixture()
	var player: Node = fixture["player"]
	var equipped: Dictionary = player.call(
		"equip_active_item",
		_active_by_id["absolute_zero_device"].duplicate(true)
	)
	_suite.assert_true(bool(equipped.get("ok", false)), "empty active slot accepts an item")
	var before: Dictionary = player.call("active_item_snapshot")
	var rejected: Dictionary = player.call(
		"equip_active_item",
		_active_by_id["paradox_beacon"].duplicate(true)
	)
	_suite.assert_equal(rejected.get("code"), &"REPLACEMENT_REQUIRED", "occupied slot requires confirmation")
	_suite.assert_equal(player.call("active_item_snapshot"), before, "declined implicit replacement changes nothing")
	var replaced: Dictionary = player.call(
		"equip_active_item",
		_active_by_id["paradox_beacon"].duplicate(true),
		true
	)
	_suite.assert_true(bool(replaced.get("ok", false)), "explicit replacement succeeds")
	_suite.assert_equal(
		player.call("active_item_snapshot").get("definition", {}).get("id"),
		"paradox_beacon",
		"replacement installs the selected active"
	)
	_free_fixture(fixture)


func _test_energy_active_commits_cost_cooldown_and_payload_atomically() -> void:
	var fixture := _fixture()
	var player: Node = fixture["player"]
	var time_manager: Node = fixture["time_manager"]
	time_manager.set("energy", 80.0)
	player.set("_runtime_frame", 20)
	player.call("equip_active_item", _active_by_id["absolute_zero_device"].duplicate(true))
	var result: Dictionary = player.call("activate_equipped_active_item", {"is_boss_target": true})
	_suite.assert_true(bool(result.get("ok", false)), "equipped energy active commits")
	_suite.assert_close(float(time_manager.get("energy")), 45.0, "active spends exact energy cost once")
	_suite.assert_equal(result.get("content_id"), "absolute_zero_device", "activation keeps content identity")
	_suite.assert_equal(
		result.get("payload_descriptor", {}).get("family"),
		"area_weakpoint_exposure",
		"activation exposes the freeze-burst payload"
	)
	_suite.assert_equal(
		result.get("boss_conversion", {}).get("behavior"),
		"weakpoint_exposure",
		"Boss target receives exposure rather than hard control"
	)
	_suite.assert_equal(
		player.call("active_item_presentation_snapshot").get("cooldown_remaining_frames"),
		900,
		"HUD projection sees exact cooldown"
	)
	var repeated: Dictionary = player.call("activate_equipped_active_item")
	_suite.assert_equal(repeated.get("code"), &"COOLDOWN_ACTIVE", "repeat input rejects during cooldown")
	_suite.assert_close(float(time_manager.get("energy")), 45.0, "rejected repeat spends no extra energy")
	_free_fixture(fixture)


func _test_health_active_spends_exact_nonlethal_cost() -> void:
	var fixture := _fixture()
	var player: Node = fixture["player"]
	var health: Node = fixture["health"]
	health.set("current_hp", 70.0)
	player.set("_runtime_frame", 44)
	player.call("equip_active_item", _active_by_id["blood_price_relic"].duplicate(true))
	var expected_health_cost := float(health.get("max_hp")) * 0.18
	var result: Dictionary = player.call("activate_equipped_active_item")
	_suite.assert_true(bool(result.get("ok", false)), "health-cost active commits")
	_suite.assert_close(
		float(health.get("current_hp")),
		70.0 - expected_health_cost,
		"blood price spends eighteen percent max HP"
	)
	_suite.assert_equal(
		result.get("payload_descriptor", {}).get("damage_multiplier"),
		1.8,
		"blood price exposes its exact damage window"
	)

	player.call("equip_active_item", _active_by_id["redline_injector"].duplicate(true), true)
	health.set("current_hp", 10.0)
	var before: Dictionary = player.call("active_item_snapshot")
	var rejected: Dictionary = player.call("activate_equipped_active_item")
	_suite.assert_equal(rejected.get("code"), &"INSUFFICIENT_RESOURCE", "lethal health spend rejects")
	_suite.assert_close(float(health.get("current_hp")), 10.0, "rejected health spend preserves HP")
	_suite.assert_equal(player.call("active_item_snapshot"), before, "rejected health spend preserves runtime")
	_free_fixture(fixture)


func _test_failed_activation_preserves_player_and_runtime_state() -> void:
	var fixture := _fixture()
	var player: Node = fixture["player"]
	var time_manager: Node = fixture["time_manager"]
	time_manager.set("energy", 10.0)
	player.set("_runtime_frame", 90)
	player.call("equip_active_item", _active_by_id["army_of_yesterday"].duplicate(true))
	var runtime_before: Dictionary = player.call("active_item_snapshot")
	var energy_before := float(time_manager.get("energy"))
	var rejected: Dictionary = player.call("activate_equipped_active_item")
	_suite.assert_equal(rejected.get("code"), &"INSUFFICIENT_RESOURCE", "insufficient energy is typed")
	_suite.assert_equal(player.call("active_item_snapshot"), runtime_before, "failed activation preserves runtime exactly")
	_suite.assert_close(float(time_manager.get("energy")), energy_before, "failed activation preserves energy")
	_free_fixture(fixture)


func _load_active_definitions() -> void:
	var file := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	_suite.assert_true(file != null, "Launch items can be opened")
	if file == null:
		return
	var value: Variant = JSON.parse_string(file.get_as_text())
	_suite.assert_true(value is Array, "Launch items are a JSON array")
	if not value is Array:
		return
	for entry_value: Variant in value:
		if entry_value is Dictionary and str((entry_value as Dictionary).get("item_mode", "")) == "active":
			_active_by_id[str((entry_value as Dictionary).get("id", ""))] = (entry_value as Dictionary).duplicate(true)
	_suite.assert_equal(_active_by_id.size(), 8, "fixture resolves all eight Launch actives")


func _fixture() -> Dictionary:
	var player = PlayerControllerScript.new()
	player.stats = StatsScript.new()
	var health = HealthComponentScript.new()
	add_child(health)
	health.call("configure_from_stats", player.stats)
	var time_manager = TimeManagerScript.new()
	add_child(time_manager)
	time_manager.call("configure_from_stats", player.stats)
	player.health = health
	player.time_manager = time_manager
	return {"player": player, "health": health, "time_manager": time_manager}


func _free_fixture(fixture: Dictionary) -> void:
	(fixture["health"] as Node).queue_free()
	(fixture["time_manager"] as Node).queue_free()
	(fixture["player"] as Node).free()
